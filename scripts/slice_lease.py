#!/usr/bin/env python3
"""Atomic lease over a slice and over a workspace's git index (vault ADR-054 D3).

ADR-054 D3 makes Mode B require "an unlocked slice per `harnesswright next`
(machine state in `.harness/locks/`, not ledger prose), a dedicated worktree with
disjoint scope". harnesswright reads that state and never writes it -- `next.ts:127`
is `existsSync(join(cwd, ".harness/locks/<id>.lock"))`, and outside `next.test.ts`
nothing in the stack creates the file. So the precondition is read by the planner
and taken by nobody: every concurrent launcher sees the slice unlocked. This module
is the missing writer, and the launcher calls it before it spawns.

  acquire --root R --key K   Take the lease named K under R/.harness/locks/.
                             The take is a single O_CREAT|O_EXCL open -- one
                             syscall, one winner. Never a read followed by a
                             write, which is what leaves a race to lose.
                             OK       -> stdout "ACQUIRED <key> <run_id> <expires_at>", exit 0
                             Held     -> stderr "HELD ...", exit 3
  release --root R --key K   Drop a lease this run_id holds. A lease already
                             stolen by a successor is left alone (exit 3): the
                             successor's claim is not ours to delete.
  status  --root R --key K   Print the lease record as JSON plus a computed
                             state of free | held | stale. Read-only, exit 0.

TWO KEYS, ONE DIRECTORY. The launcher takes `<slice-id>` (so two sessions cannot
take the same task) and `_workspace` (so two sessions cannot write one git index).
A leading underscore is not a legal slice id, so the two key spaces cannot collide.
The locks directory is resolved against the git toplevel, and a linked worktree has
its own toplevel and its own index -- so two runs in ONE tree contend on
`_workspace` and serialise, while two runs in SEPARATE worktrees never meet and run
in parallel. That is the whole of the parallelism this module enables: it makes
concurrency legal exactly where the index is disjoint.

DEATH. A lease must not outlive its holder's usefulness, and a SIGKILLed session
runs no cleanup: no trap, no release, and possibly a lock file created but not yet
written. All three are reclaimed, in falling order of speed:

  unparseable record  -> stale at once (killed between create and write)
  holder pid is gone  -> stale at once (same host; the common case)
  expires_at passed   -> stale (different host, or a recycled pid; TTL-bounded)

Reclaiming is itself a race between survivors, so the break is an os.rename of the
lock aside to a unique name. rename is atomic and the source disappears with it, so
exactly one breaker succeeds and the losers simply retry. Nothing here polls, forks,
listens, or imports off the standard library.

Not flock: a kernel-held advisory lock would need no TTL at all, but it dies with the
process that opened the descriptor, and the process that runs this module is a
short-lived subprocess of the launcher. Holding it across the run would mean keeping
the fd open in the launcher's shell, and `flock(1)` is not present on macOS. Hence
`--pid`: the caller records ITSELF as the holder, and liveness is asked of that pid.
"""
import argparse
import errno
import json
import os
import socket
import sys
import time

HELD = 3


def _locks_dir(root):
    return os.path.join(root, ".harness", "locks")


def _lock_path(root, key):
    return os.path.join(_locks_dir(root), key + ".lock")


def _read(path):
    """The lease record, or None if it cannot be trusted.

    None is not an error: a lock file that exists but does not parse is what a
    holder killed between O_EXCL and write leaves behind, and it means the lease
    is stale, not that the caller did something wrong.
    """
    try:
        with open(path, encoding="utf-8") as fh:
            rec = json.load(fh)
    except (OSError, ValueError):
        return None
    return rec if isinstance(rec, dict) else None


def _alive(rec):
    """Is the recorded holder still running?

    Cross-host we cannot ask, so we answer 'yes' and let expires_at decide -- the
    conservative direction, since a wrong 'no' would hand one task to two sessions
    and a wrong 'yes' only delays reclaim until the TTL.
    """
    if rec.get("host") != socket.gethostname():
        return True
    pid = rec.get("pid")
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError as e:
        return e.errno != errno.ESRCH
    return True


def _staleness(rec, now):
    """Why this lease may be broken, or None if it may not."""
    if rec is None:
        return "holder left an unwritable record (killed mid-acquire)"
    exp = rec.get("expires_at")
    if not isinstance(exp, (int, float)):
        return "record carries no usable expires_at"
    if not _alive(rec):
        return "holder pid %s is gone" % rec.get("pid")
    if now >= exp:
        return "lease expired %ds ago" % int(now - exp)
    return None


def cmd_acquire(args):
    now = time.time()
    path = _lock_path(args.root, args.key)
    try:
        os.makedirs(_locks_dir(args.root), exist_ok=True)
    except OSError as e:
        print("STOP: locks dir not creatable at %s: %s" % (_locks_dir(args.root), e),
              file=sys.stderr)
        return 1

    for attempt in range(args.retries + 1):
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        except FileExistsError:
            rec = _read(path)
            why = _staleness(rec, time.time())
            if why is None:
                print("HELD %s by run_id=%s pid=%s host=%s until=%s"
                      % (args.key, rec.get("run_id"), rec.get("pid"), rec.get("host"),
                         _iso(rec.get("expires_at"))), file=sys.stderr)
                return HELD
            # Break it aside, atomically. Whoever loses this rename finds the lock
            # already gone or already retaken, and re-enters the loop either way.
            try:
                os.rename(path, "%s.stale-%d-%d" % (path, os.getpid(), attempt))
            except OSError:
                pass
            continue
        except OSError as e:
            print("STOP: lock not creatable at %s: %s" % (path, e), file=sys.stderr)
            return 1

        expires = now + args.ttl
        rec = {
            "key": args.key,
            "run_id": args.run_id,
            "pid": os.getpid() if args.pid is None else args.pid,
            "host": socket.gethostname(),
            "acquired_at": now,
            "expires_at": expires,
            "ttl": args.ttl,
        }
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(rec, fh, sort_keys=True)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        print("ACQUIRED %s %s %s" % (args.key, args.run_id, _iso(expires)))
        return 0

    print("HELD %s (contended through %d attempts)" % (args.key, args.retries + 1),
          file=sys.stderr)
    return HELD


def cmd_release(args):
    path = _lock_path(args.root, args.key)
    rec = _read(path)
    if rec is None and not os.path.exists(path):
        print("RELEASED %s (was not held)" % args.key)
        return 0
    if rec is not None and args.run_id is not None and rec.get("run_id") != args.run_id:
        print("STOP: %s is held by run_id=%s, not %s; refusing to release"
              % (args.key, rec.get("run_id"), args.run_id), file=sys.stderr)
        return HELD
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass
    except OSError as e:
        print("STOP: lock not removable at %s: %s" % (path, e), file=sys.stderr)
        return 1
    print("RELEASED %s %s" % (args.key, args.run_id))
    return 0


def cmd_status(args):
    path = _lock_path(args.root, args.key)
    if not os.path.exists(path):
        print(json.dumps({"key": args.key, "state": "free", "path": path}))
        return 0
    rec = _read(path)
    why = _staleness(rec, time.time())
    print(json.dumps({
        "key": args.key,
        "state": "held" if why is None else "stale",
        "reason": why,
        "path": path,
        "record": rec,
    }, sort_keys=True))
    return 0


def _iso(ts):
    if not isinstance(ts, (int, float)):
        return "?"
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts))


def main(argv):
    p = argparse.ArgumentParser(prog="slice_lease.py", description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn in (("acquire", cmd_acquire), ("release", cmd_release), ("status", cmd_status)):
        s = sub.add_parser(name)
        s.add_argument("--root", required=True,
                       help="workspace root; locks live at <root>/.harness/locks/")
        s.add_argument("--key", required=True,
                       help="slice id, or _workspace for the git-index lease")
        s.add_argument("--run-id", default=None)
        s.add_argument("--ttl", type=float, default=3600.0,
                       help="seconds before the lease may be reclaimed (default 3600)")
        s.add_argument("--retries", type=int, default=4,
                       help="re-attempts after breaking a stale lease (default 4)")
        s.add_argument("--pid", type=int, default=None,
                       help="record this pid as the holder instead of our own")
        s.set_defaults(fn=fn)
    args = p.parse_args(argv)
    args.root = os.path.abspath(args.root)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
