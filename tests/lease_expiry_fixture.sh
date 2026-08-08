#!/usr/bin/env bash
# Falsifier for WHEN a lease is dated in scripts/slice_lease.py -- the second
# defect of the acquire path, left standing by the commit that made the take
# atomic (vault ADR-054 D3, quoted below out of the module rather than recalled).
#
# ONE ROW, and it is an ORDERING, not a duration. The row is red iff a lease the
# module published is dated EARLIER than an event that provably precedes it: the
# expiry of the lock it broke to get there. Nothing here measures how much
# earlier, and nothing here decides on an elapsed interval -- see WHY THIS IS
# DETERMINISTIC.
#
# THE SITE. `cmd_acquire` reads the clock once, before the retry loop, and every
# attempt inside the loop dates its record from that one read. A claimer that
# finds the key held, classifies the holder as stale, breaks it aside and
# retries therefore publishes a lease stamped from before the contention it just
# won: the TTL it advertises is already being spent when the lease is created.
# The exact line numbers are resolved from the source at run time (see `anchor`)
# and printed in the red, so the red always names a real site.
#
# WHY THIS IS DETERMINISTIC, and not a race that happens to be lost. The fixture
# waits on no interval and sleeps for no duration; its verdict cannot move with
# load, with core count, or with how many other processes are running.
#
# The predecessor lock is delivered to the claimer through a FIFO created at the
# lock's own name. That makes the claimer's own `_read()` a rendezvous the
# kernel enforces in both directions: the claimer cannot get past it until this
# fixture hands over a record, and this fixture's write end cannot open until
# the claimer has arrived there. So the two orderings the verdict rests on are
# causal, not sampled:
#
#   the claimer's single clock read  <  the stamp on the predecessor's expiry
#       because the stamp is taken after the write end opened, which the kernel
#       only permits once the claimer has reached _read() -- which it does after
#       that clock read. The stamp is then advanced to the first clock value
#       strictly greater than the read taken at the rendezvous, so the ordering
#       is strict at any clock resolution rather than probably strict.
#
#   the predecessor's expiry  <=  the clock the claimer classifies it against
#       because that classification happens after the record arrives, and the
#       record is written after the stamp. The predecessor names a host that is
#       not this one, so `_alive` answers yes unconditionally and the ONLY route
#       to stale left open is the expiry comparison. A claimer that exits 0 has
#       therefore read a clock at or past that expiry: the break is dated.
#
# A correct implementation dates its record at or after the attempt that took
# the key, hence at or after that break, hence at or after the predecessor's
# expiry -- and the row is green. This one dates it from before the rendezvous,
# and the row is red. The row goes green exactly when that single clock read
# moves inside the loop; that was measured against a repaired scratch copy
# before this row was wired, so this is a gate that can move, not one that can
# only be red.
#
# WHAT IS RECONSTRUCTED AND WHAT IS REAL. Reconstructed: how the predecessor's
# record is delivered -- a FIFO rather than a regular file, which changes WHEN
# the claimer reads it and not WHAT it reads; the bytes are an ordinary complete
# lease record. Real and unmodified: the claimer, its staleness classification,
# the break-aside it performs, the retry, and the record it publishes. The
# verdict is read back out of that published record.
#
# NOTHING IS ANCHORED TO AN ORDINAL. The published lease is identified by its
# key and run_id, not by which attempt or which file position produced it, and
# the predecessor by the record this fixture authored. The break-aside name is
# reported with its pid and attempt normalised away, and no verdict reads it.
#
# Modes:
#   (default)     the TDD posture. Exit 0 iff the row is GREEN.
#   --expect-red  the register posture. Exit 0 iff the row is RED, i.e. the
#                 defect is still present and still observed. This is how
#                 tests/run_tests.sh wires the row while the lease is dated
#                 before its contention, so the red is re-observed on every run
#                 instead of being parked in a commit message. When the clock
#                 read moves inside the loop the row goes GREEN, this mode goes
#                 red, and the wiring is flipped to the plain call in the same
#                 commit -- deliberately, not silently.
#
# Exit codes: 0 verdict as the mode expects | 1 verdict inverted | 2 the fixture
# could not set its scenario up and has therefore measured nothing. Exit 2 is
# never reported as a red (same convention as tests/lease_window_fixture.sh).
# No exit-2 path here is a timing budget: they are a missing source file, a
# scenario that did not run, and a claimer that died before the rendezvous.
#
# Scratch dirs are templated under $TMPDIR: BSD `mktemp -d` with no template
# reaches for the Darwin per-user temp dir, which an agent session's sandbox
# denies (same reason as tests/run_tests.sh:6-10). Nothing absolute is printed,
# and neither is the host name the predecessor is built from: the output of this
# fixture is committed as evidence, and .verity/claims.json refuses tracked
# files that carry machine paths.
set -uo pipefail

MODE="assert-green"
while [ $# -gt 0 ]; do
  case "$1" in
    --expect-red) MODE="expect-red"; shift ;;
    *) echo "usage: lease_expiry_fixture.sh [--expect-red]" >&2; exit 2 ;;
  esac
done

PACK="$(cd "$(dirname "$0")/.." && pwd)"
LEASE="$PACK/scripts/slice_lease.py"
KEY="S-EXPIRY-001"
TTL="120"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-leaseexp.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$LEASE" ] || broken "scripts/slice_lease.py is not where this fixture expects it"

# The site, resolved from the source rather than remembered. A red that names a
# line number it did not read is a red about a file that may no longer exist in
# that shape; if any anchor is gone the fixture has measured nothing (exit 2)
# instead of reporting a red against a moved target.
anchor() {  # anchor <fixed-string> <what> -> line number
  local n
  n="$(grep -nF -- "$1" "$LEASE" | head -1 | cut -d: -f1)"
  [ -n "$n" ] || broken "anchor for $2 not found in scripts/slice_lease.py: $1"
  printf '%s' "$n"
}
L_NOW="$(anchor 'now = time.time()' 'the single clock read')" || exit 2
L_LOOP="$(anchor 'for attempt in range(args.retries + 1):' 'the retry loop')" || exit 2
L_EXP="$(anchor 'expires = now + args.ttl' 'the expiry computed per attempt')" || exit 2
L_ACQ="$(anchor '"acquired_at": now,' 'the acquired_at stamp')" || exit 2
L_HOST="$(anchor 'if rec.get("host") != socket.gethostname():' 'the cross-host liveness answer')" || exit 2
L_CMP="$(anchor 'if now >= exp:' 'the expiry classification')" || exit 2
L_BREAK="$(anchor 'os.rename(path, "%s.stale-%d-%d"' 'the break-aside')" || exit 2
L_TTL="$(anchor 'seconds before the lease may be reclaimed' 'the ttl contract')" || exit 2

# The invariant this row falsifies, quoted out of the source at run time. The
# anchor is checked so a quotation that has drifted off its subject cannot be
# passed off as verbatim.
INV_FROM=42
INV_TO=43
INVARIANT="$(sed -n "${INV_FROM},${INV_TO}p" "$LEASE")"
case "$INVARIANT" in
  *"TTL-bounded"*) ;;
  *) broken "scripts/slice_lease.py:${INV_FROM}-${INV_TO} no longer declares the TTL bound" ;;
esac

# ---- the scenario ----------------------------------------------------------
# Prints key=value lines and nothing else. No absolute path, no host name, no
# raw pid: the stale suffix is normalised so this output is stable enough to
# commit as evidence and carries no machine identity.
cat > "$WORK/expiry.py" <<'SCENARIO'
import errno, fcntl, json, os, re, socket, subprocess, sys, time

lease, root, key, ttl = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
locks = os.path.join(root, ".harness", "locks")
os.makedirs(locks, exist_ok=True)
path = os.path.join(locks, key + ".lock")

# The predecessor is delivered through a FIFO at the lock's own name, so the
# claimer's own _read() becomes a rendezvous the kernel holds open in both
# directions. link() reports EEXIST for it exactly as it would for a file.
os.mkfifo(path, 0o644)
print("fifo=1")

p = subprocess.Popen([sys.executable, lease, "acquire", "--root", root, "--key", key,
                      "--run-id", "successor", "--ttl", ttl, "--pid", str(os.getpid())],
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

# O_WRONLY|O_NONBLOCK on a FIFO is ENXIO until a reader is present, so this
# returns exactly when the claimer has reached _read() -- no interval is waited
# on and none is assumed. A claimer that died before arriving is a scenario that
# did not run, not a verdict.
wfd = None
while wfd is None:
    try:
        wfd = os.open(path, os.O_WRONLY | os.O_NONBLOCK)
    except OSError as e:
        if e.errno != errno.ENXIO:
            raise
        if p.poll() is not None:
            print("rendezvous=0")
            print("early_rc=%d" % p.returncode)
            print("early_err=%s" % (p.stderr.read().strip().replace("\n", " ")[:200]))
            sys.exit(0)
        time.sleep(0)          # yield, not a wait: zero duration, no deadline
fcntl.fcntl(wfd, fcntl.F_SETFL, fcntl.fcntl(wfd, fcntl.F_GETFL) & ~os.O_NONBLOCK)
print("rendezvous=1")

# The claimer is now parked inside _read(), which it reached strictly after the
# clock read it will date its lease with. Stamp the predecessor's expiry at the
# first clock value strictly greater than a read taken here: strictly later than
# the claimer's read at any clock resolution, and reached by reading the clock
# rather than by waiting for it.
t0 = time.time()
stamp = time.time()
while stamp <= t0:
    stamp = time.time()

# host is deliberately not this one: _alive() then answers yes unconditionally,
# so the expiry comparison is the only route to stale left open and a claimer
# that proceeds has provably read a clock at or past `stamp`.
pred = {"key": key, "run_id": "predecessor", "pid": os.getpid(),
        "host": socket.gethostname() + ".fixture-invalid",
        "acquired_at": t0, "expires_at": stamp, "ttl": 0.0}
with os.fdopen(wfd, "w", encoding="utf-8") as fh:
    json.dump(pred, fh, sort_keys=True)
    fh.write("\n")

out, err = p.communicate()
print("claimer_rc=%d" % p.returncode)
print("claimer_out=%s" % ((out.strip() or err.strip()).replace("\n", " ")[:200]))

names = [re.sub(r"\.stale-\d+-\d+$", ".stale-<pid>-<attempt>", n)
         for n in sorted(os.listdir(locks))]
print("locks_after=%s" % " ".join(names))

try:
    with open(path, encoding="utf-8") as fh:
        succ = json.load(fh)
except (OSError, ValueError):
    succ = {}
print("succ_key=%s" % succ.get("key"))
print("succ_run_id=%s" % succ.get("run_id"))
print("succ_holder_alive=%d" % (1 if succ.get("pid") == os.getpid() else 0))
print("pred_expires_at=%r" % pred["expires_at"])
print("succ_acquired_at=%r" % succ.get("acquired_at"))
print("succ_expires_at=%r" % succ.get("expires_at"))

# The whole verdict: is the lease that displaced the predecessor dated before
# the predecessor's expiry -- the event the claimer itself had to observe as
# past in order to displace it?
a = succ.get("acquired_at")
if isinstance(a, (int, float)):
    print("dated_before_break=%d" % (1 if a < pred["expires_at"] else 0))
SCENARIO

OUT="$WORK/expiry.out"
python3 "$WORK/expiry.py" "$LEASE" "$WORK/repo" "$KEY" "$TTL" \
  >"$OUT" 2>"$WORK/expiry.err" \
  || broken "the expiry scenario did not run: $(head -c 300 "$WORK/expiry.err")"

val() { sed -n "s/^$1=//p" "$OUT" | head -1; }
RC="$(val claimer_rc)"
CLAIMER_OUT="$(val claimer_out)"
LOCKS_AFTER="$(val locks_after)"
PRED_EXP="$(val pred_expires_at)"
SUCC_ACQ="$(val succ_acquired_at)"
SUCC_EXP="$(val succ_expires_at)"
ALIVE="$(val succ_holder_alive)"
DATED="$(val dated_before_break)"

[ "$(val fifo)" = "1" ] || broken "the predecessor lock could not be staged"
[ "$(val rendezvous)" = "1" ] \
  || broken "the claimer never reached _read(): exit $(val early_rc) $(val early_err)"
[ "$RC" = "0" ] || broken "the claimer did not take the key after breaking the predecessor (exit $RC, $CLAIMER_OUT); nothing was published to date"
[ "$(val succ_key)" = "$KEY" ] || broken "the published record is not for $KEY"
[ "$(val succ_run_id)" = "successor" ] || broken "the published record was not written by the claimer"
case "$DATED" in
  0|1) ;;
  *) broken "the published record carries no usable acquired_at" ;;
esac

echo "== lease expiry ordering: one row (vault ADR-054 D3) =="

if [ "$DATED" = "0" ]; then
  STATE_ROW="GREEN"
  echo "GREEN [lease expiry ordering] the lease published after the break is dated at or" \
       "after the expiry that justified it (acquired_at=${SUCC_ACQ} >= ${PRED_EXP})"
else
  STATE_ROW="RED"
  echo "RED [lease expiry ordering] scripts/slice_lease.py:${L_NOW} reads the clock once,"
  note "before the retry loop at :${L_LOOP}, and every attempt inside it dates its record"
  note "from that one read (:${L_EXP}, :${L_ACQ}). A claimer that breaks a stale lock"
  note "(:${L_BREAK}) and retries therefore publishes a lease stamped from before the"
  note "contention it won: its TTL is already being spent when the lease is created."
  note "measured, with the predecessor handed over at the claimer's own _read():"
  note "  claimer exit=${RC} ${CLAIMER_OUT}"
  note "  the predecessor named a host that is not this one, so :${L_HOST} answers alive"
  note "  and :${L_CMP} is the only route to stale: the claimer read a clock >= ${PRED_EXP}"
  note "  the lease it then published is dated acquired_at=${SUCC_ACQ}, expires_at=${SUCC_EXP}"
  note "  -- earlier than the expiry it had just declared past, for a holder still alive"
  note "  (live_holder=${ALIVE})"
  note "  locks after: ${LOCKS_AFTER}"
  note "the source sells the bound this breaks at scripts/slice_lease.py:${L_TTL}:"
  note "  | $(sed -n "${L_TTL}p" "$LEASE" | sed 's/^ *//')"
  note "and at scripts/slice_lease.py:${INV_FROM}-${INV_TO}:"
  printf '%s\n' "$INVARIANT" | while IFS= read -r line; do note "  | $line"; done
  note "green when the clock read moves inside the loop, so a lease is dated no earlier"
  note "than the attempt that took it"
fi

echo "-- lease expiry ordering: lease-dated-after-its-contention=${STATE_ROW}"

case "$MODE" in
  expect-red)
    if [ "$STATE_ROW" = "RED" ]; then
      echo "LEASE EXPIRY FIXTURE: RED, as registered (the lease is dated before its contention)"
      exit 0
    fi
    echo "LEASE EXPIRY FIXTURE: GREEN while registered RED -- the row moved; flip the wiring"
    exit 1
    ;;
  *)
    [ "$STATE_ROW" = "GREEN" ] && { echo "LEASE EXPIRY FIXTURE: GREEN"; exit 0; }
    echo "LEASE EXPIRY FIXTURE: RED"
    exit 1
    ;;
esac
