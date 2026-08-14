#!/usr/bin/env python3
"""Live view over a running measurement: the state line, extended.

  conformance_watch.py RUN_DIR [--interval-ms N] [--once] [--max-seconds S]

RUN_DIR holds `invocation.txt` (the declaration) and `stream.jsonl` (the
growing transcript). This watcher maintains RUN_DIR/conformance.state: ONE
short line, atomically replaced (write-temp-then-rename), rewritten only
when its content changes -- the same contract as the arc gate's state line,
which a statusline rereads every 300ms without recomputing anything. This
file EXTENDS that seam to conformance; it does not replace or touch the
gate's own line.

Line shape:

  CONF <source> | tools <k> depth<=<m> | calls=<n> maxd=<d> | \
oos-emit=<e> oos-exec=<x> unresolved=<u> | RUNNING|COMPLETE

  oos-emit   tool_use emissions naming a tool outside the declared pool.
             Doctrine (ADR-023 D6): an emission proves nothing about the
             pool -- it is shown the moment it appears because a live view
             answers "is something trying to leave the surface", not "did
             the surface hold". Membership is still read from results.
  oos-exec   out-of-surface emissions whose paired result is NOT an error:
             the surface did not hold. This is the alarm.

Declared detection threshold: a line appended to stream.jsonl is reflected
in conformance.state within 3 poll intervals (default interval 100ms ->
300ms). The monitor-blind fixture holds this number; change it there when
changing it here.

Watch renders live state; it never verdicts. The record and
conformance_verify.py do. Exit 0 on clean termination (--once, stream
complete, or --max-seconds elapsed), 3 on usage error.
"""
import json
import os
import sys
import time


def die(msg):
    sys.stderr.write("conformance_watch: %s\n" % msg)
    sys.exit(3)


def parse_declaration(path):
    with open(path, encoding="utf-8") as fh:
        header = fh.readline().strip()
    fields = dict(t.partition("=")[::2] for t in header.split() if "=" in t)
    missing = [k for k in ("tools", "depth") if k not in fields]
    if missing:
        die("declaration lacks %s" % ",".join(missing))
    if not fields["depth"].isdigit():
        die("declared depth %r is not a number" % fields["depth"])
    tools = sorted(t for t in fields["tools"].split(",") if t)
    return tools, int(fields["depth"]), fields.get("arm", "-")


class Tally(object):
    def __init__(self, declared_tools):
        self.declared = set(declared_tools)
        self.calls = 0
        self.max_depth = 0
        self.oos_emit = 0
        self.oos_exec = 0
        self.depth_by_id = {}
        self.oos_pending = set()
        self.unresolved = set()
        self.complete = False

    def feed(self, ev):
        if ev.get("type") == "result":
            self.complete = True
        parent = ev.get("parent_tool_use_id")
        msg = ev.get("message")
        blocks = msg.get("content") if isinstance(msg, dict) else None
        if not isinstance(blocks, list):
            return
        for b in blocks:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "tool_use":
                uid, name = b.get("id"), b.get("name")
                self.calls += 1
                if parent is None:
                    depth = 0
                elif parent in self.depth_by_id:
                    depth = self.depth_by_id[parent] + 1
                else:
                    depth = -1
                if uid is not None:
                    self.depth_by_id[uid] = depth
                    self.unresolved.add(uid)
                if depth > self.max_depth:
                    self.max_depth = depth
                if name not in self.declared:
                    self.oos_emit += 1
                    if uid is not None:
                        self.oos_pending.add(uid)
            elif b.get("type") == "tool_result":
                uid = b.get("tool_use_id")
                self.unresolved.discard(uid)
                if uid in self.oos_pending:
                    self.oos_pending.discard(uid)
                    if not bool(b.get("is_error")):
                        self.oos_exec += 1

    def line(self, source, declared_count, max_spawn):
        return ("CONF %s | tools %d depth<=%d | calls=%d maxd=%d | "
                "oos-emit=%d oos-exec=%d unresolved=%d | %s"
                % (source, declared_count, max_spawn, self.calls,
                   self.max_depth, self.oos_emit, self.oos_exec,
                   len(self.unresolved),
                   "COMPLETE" if self.complete else "RUNNING"))


def write_state(path, line, last):
    if line == last:
        return line
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(line + "\n")
    os.replace(tmp, path)
    return line


def main():
    args = sys.argv[1:]
    interval_ms, once, max_seconds = 100, False, None
    run_dir = None
    while args:
        arg = args.pop(0)
        if arg == "--interval-ms":
            if not args:
                die("--interval-ms needs a value")
            interval_ms = int(args.pop(0))
        elif arg == "--once":
            once = True
        elif arg == "--max-seconds":
            if not args:
                die("--max-seconds needs a value")
            max_seconds = float(args.pop(0))
        elif run_dir is None:
            run_dir = arg
        else:
            die("unexpected argument %r" % arg)
    if run_dir is None:
        die("usage: conformance_watch.py RUN_DIR [--interval-ms N] "
            "[--once] [--max-seconds S]")
    decl = os.path.join(run_dir, "invocation.txt")
    stream = os.path.join(run_dir, "stream.jsonl")
    state = os.path.join(run_dir, "conformance.state")
    if not os.path.isfile(decl):
        die("no declaration at %s" % decl)
    tools, max_spawn, source = parse_declaration(decl)

    tally = Tally(tools)
    offset, buf, last = 0, "", None
    started = time.time()
    while True:
        try:
            size = os.path.getsize(stream)
        except OSError:
            size = 0
        if size > offset:
            with open(stream, encoding="utf-8") as fh:
                fh.seek(offset)
                buf += fh.read(size - offset)
                offset = size
            while "\n" in buf:
                line, _, buf = buf.partition("\n")
                line = line.strip()
                if not line:
                    continue
                try:
                    tally.feed(json.loads(line))
                except json.JSONDecodeError:
                    continue
        last = write_state(state, tally.line(source, len(tools), max_spawn),
                           last)
        if once or tally.complete:
            break
        if max_seconds is not None and time.time() - started >= max_seconds:
            break
        time.sleep(interval_ms / 1000.0)
    sys.exit(0)


if __name__ == "__main__":
    main()
