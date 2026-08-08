#!/usr/bin/env bash
# Falsifier for the atomicity of the lease TAKE in scripts/slice_lease.py
# (vault ADR-054 D3, Accepted: "an unlocked slice per `harnesswright next`
# (machine state in `.harness/locks/`, not ledger prose)").
#
# ONE ROW, one invariant, declared by the module about itself at
# scripts/slice_lease.py:13-15 -- quoted verbatim in the red below, read out of
# the source at run time so the quotation cannot rot away from the file.
#
# THE SITE. scripts/slice_lease.py takes the lock with a single
# O_CREAT|O_EXCL open, and only afterwards writes the JSON record. Between
# those two points the lock file exists under its final name and is zero bytes.
# `_read()` returns None for it, `_staleness()` maps None to "holder left an
# unwritable record (killed mid-acquire)" -- i.e. STALE -- and `cmd_acquire`
# renames a stale lock aside and retakes it. So a claimer that is alive, healthy
# and merely mid-acquire is classified as dead, and its key is taken from under
# it. The exact line numbers are resolved from the source at run time (see
# `anchor` below) and printed in the red, so the red always names a real site.
#
# WHY THIS IS DETERMINISTIC, and not a race that happens to be lost. The fixture
# does not race anything. It reconstructs the window by doing exactly what the
# source's O_EXCL line does -- the same open, the same flags, the same mode --
# and then holds that descriptor open for the whole measurement. The second
# claimer is the real, unmodified implementation, and it meets exactly the
# on-disk state the window leaves: one zero-byte lock, one live holder pid.
# No sleeps, no barriers, no concurrent processes, nothing scheduled: the
# outcome cannot move with load, with core count, or with how many other
# processes are running. A falsifier whose verdict needed statistics would not
# be a gate, so this one is built to need none.
#
# WHAT IS RECONSTRUCTED AND WHAT IS REAL. Reconstructed: the holder, which is
# this fixture sitting in the window (the source cannot be stopped there without
# editing it, and this commit does not edit it). Real and unmodified: the second
# claimer, the classification it applies, and the break-aside it performs. The
# holder then completes its record exactly as the source does after its O_EXCL
# succeeded -- unconditionally, with no re-check of the path it opened -- which
# is why the count of grants, not merely the second claimer's exit code, is
# reported: both processes end the scenario believing they hold the key.
#
# Modes:
#   (default)     the TDD posture. Exit 0 iff the row is GREEN.
#   --expect-red  the register posture. Exit 0 iff the row is RED, i.e. the
#                 defect is still present and still observed. This is how
#                 tests/run_tests.sh wires the row while the take is not atomic,
#                 so the red is re-observed on every run instead of being parked
#                 in a commit message. When the take is repaired the row goes
#                 GREEN, this mode goes red, and the wiring is flipped to the
#                 plain call in the same commit -- deliberately, not silently.
#
# Exit codes: 0 verdict as the mode expects | 1 verdict inverted | 2 the fixture
# could not set its scenario up and has therefore measured nothing. Exit 2 is
# never reported as a red (same convention as tests/adr008_falsifier_fixture.sh).
#
# Scratch dirs are templated under $TMPDIR: BSD `mktemp -d` with no template
# reaches for the Darwin per-user temp dir, which an agent session's sandbox
# denies (same reason as tests/run_tests.sh:6-10). Nothing absolute is printed:
# the output of this fixture is committed as evidence, and .verity/claims.json
# refuses tracked files that carry machine paths.
set -uo pipefail

MODE="assert-green"
while [ $# -gt 0 ]; do
  case "$1" in
    --expect-red) MODE="expect-red"; shift ;;
    *) echo "usage: lease_window_fixture.sh [--expect-red]" >&2; exit 2 ;;
  esac
done

PACK="$(cd "$(dirname "$0")/.." && pwd)"
LEASE="$PACK/scripts/slice_lease.py"
KEY="S-WINDOW-001"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-leasewin.XXXXXX")" || exit 1
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
L_EXCL="$(anchor 'os.O_CREAT | os.O_EXCL' 'the O_EXCL take')" || exit 2
L_READ="$(anchor 'except (OSError, ValueError):' 'the unparseable-record read')" || exit 2
L_STALE="$(anchor 'killed mid-acquire' 'the stale classification')" || exit 2
L_BREAK="$(anchor 'os.rename(path, "%s.stale-%d-%d"' 'the break-aside')" || exit 2
L_WRITE="$(anchor 'with os.fdopen(fd, "w", encoding="utf-8") as fh:' 'the record write')" || exit 2
L_PRINT="$(anchor 'print("ACQUIRED %s %s %s"' 'the ACQUIRED print')" || exit 2

# The invariant this row falsifies, quoted out of the source at run time. The
# anchor is checked so a quotation that has drifted off its subject cannot be
# passed off as verbatim.
INV_FROM=13
INV_TO=15
INVARIANT="$(sed -n "${INV_FROM},${INV_TO}p" "$LEASE")"
case "$INVARIANT" in
  *"syscall, one winner"*) ;;
  *) broken "scripts/slice_lease.py:${INV_FROM}-${INV_TO} no longer declares the atomicity invariant" ;;
esac

# ---- the scenario ----------------------------------------------------------
# Prints key=value lines and nothing else. No absolute path, no pid: the stale
# suffix is normalised so this output is stable enough to commit as evidence and
# carries no machine identity.
cat > "$WORK/window.py" <<'WINDOW'
import json, os, re, socket, subprocess, sys, time

lease, root, key = sys.argv[1], sys.argv[2], sys.argv[3]
locks = os.path.join(root, ".harness", "locks")
os.makedirs(locks, exist_ok=True)
path = os.path.join(locks, key + ".lock")

# The window, entered by doing exactly what the source's O_EXCL line does.
fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
print("window_open=1")
print("size_at_window=%d" % os.path.getsize(path))
os.kill(os.getpid(), 0)          # the holder is alive, and stays alive throughout
print("holder_alive=1")

st = subprocess.run([sys.executable, lease, "status", "--root", root, "--key", key],
                    capture_output=True, text=True)
try:
    s = json.loads(st.stdout)
except ValueError:
    s = {}
print("status_state=%s" % s.get("state"))
print("status_reason=%s" % s.get("reason"))

# The second claimer: the real implementation, unmodified, meeting the window.
p = subprocess.run([sys.executable, lease, "acquire", "--root", root, "--key", key,
                    "--run-id", "second", "--ttl", "120", "--pid", str(os.getpid())],
                   capture_output=True, text=True)
print("second_rc=%d" % p.returncode)
print("second_out=%s" % (p.stdout.strip() or p.stderr.strip()))

# The holder completes its record as the source does once its O_EXCL succeeded:
# unconditionally, without re-reading the path it opened.
now = time.time()
rec = {"key": key, "run_id": "first", "pid": os.getpid(), "host": socket.gethostname(),
       "acquired_at": now, "expires_at": now + 120, "ttl": 120}
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    json.dump(rec, fh, sort_keys=True)
    fh.write("\n")
print("holder_wrote=1")

names = [re.sub(r"\.stale-\d+-\d+$", ".stale-<pid>-<attempt>", n)
         for n in sorted(os.listdir(locks))]
print("locks_after=%s" % " ".join(names))
try:
    with open(path, encoding="utf-8") as fh:
        print("live_holder=%s" % json.load(fh).get("run_id"))
except (OSError, ValueError):
    print("live_holder=<unreadable>")
# Both processes leave this scenario believing they hold `key`: the holder
# because its O_EXCL succeeded and it wrote and would print ACQUIRED, the second
# claimer because it exited 0.
print("grants=%d" % (1 + (1 if p.returncode == 0 else 0)))
WINDOW

OUT="$WORK/window.out"
python3 "$WORK/window.py" "$LEASE" "$WORK/repo" "$KEY" >"$OUT" 2>"$WORK/window.err" \
  || broken "the window scenario did not run: $(head -c 300 "$WORK/window.err")"

val() { sed -n "s/^$1=//p" "$OUT" | head -1; }
SIZE="$(val size_at_window)"
STATE="$(val status_state)"
REASON="$(val status_reason)"
RC="$(val second_rc)"
SECOND_OUT="$(val second_out)"
LOCKS_AFTER="$(val locks_after)"
LIVE="$(val live_holder)"
GRANTS="$(val grants)"

[ "$(val window_open)" = "1" ] || broken "could not enter the acquire window"
[ -n "$RC" ] || broken "the second claimer produced no exit code"

echo "== lease acquire window: one row (vault ADR-054 D3) =="

if [ "$RC" != "0" ]; then
  STATE_ROW="GREEN"
  echo "GREEN [lease acquire window] a second claimer meeting the window did not acquire" \
       "(exit $RC, $SECOND_OUT)"
else
  STATE_ROW="RED"
  echo "RED [lease acquire window] scripts/slice_lease.py:${L_EXCL} takes the lock with"
  note "O_CREAT|O_EXCL and only at :${L_WRITE}-${L_PRINT} writes the record and prints ACQUIRED."
  note "In between, the lock exists under its final name at ${SIZE} bytes: _read() returns"
  note "None (:${L_READ}), _staleness() maps None to stale (:${L_STALE}), and the claimer"
  note "renames the lock aside (:${L_BREAK}) and takes the key from a holder that is alive."
  note "measured, with the holder alive and inside the window:"
  note "  status state=${STATE} reason=${REASON}"
  note "  second claimer exit=${RC} ${SECOND_OUT}"
  note "  locks after: ${LOCKS_AFTER}"
  note "  live lock names run_id=${LIVE}; the holder then wrote its record and would"
  note "  print ACQUIRED (:${L_PRINT}) -> grants=${GRANTS} for one key"
  note "the source declares the opposite of itself at scripts/slice_lease.py:${INV_FROM}-${INV_TO}:"
  printf '%s\n' "$INVARIANT" | while IFS= read -r line; do note "  | $line"; done
  note "green when no second claimer can take the key while the first is inside that window"
fi

echo "-- lease acquire window: take-is-atomic=${STATE_ROW}"

case "$MODE" in
  expect-red)
    if [ "$STATE_ROW" = "RED" ]; then
      echo "LEASE WINDOW FIXTURE: RED, as registered (the take is not atomic)"
      exit 0
    fi
    echo "LEASE WINDOW FIXTURE: GREEN while registered RED -- the row moved; flip the wiring"
    exit 1
    ;;
  *)
    [ "$STATE_ROW" = "GREEN" ] && { echo "LEASE WINDOW FIXTURE: GREEN"; exit 0; }
    echo "LEASE WINDOW FIXTURE: RED"
    exit 1
    ;;
esac
