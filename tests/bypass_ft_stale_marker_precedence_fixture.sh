#!/usr/bin/env bash
# FT-6 -- stale-marker-precedence. A marker left by an earlier run must count
# for nothing: the disk detector pins marker CONTENT to <ARM>/<RUN-STAMP>, so
# a file with any other stamp is STALE -- recorded, never counted. A detector
# without that pin would read yesterday's liveness as today's conformity,
# which is the one lie an apparatus can tell that no arm can catch.
# GREEN: the frozen detector classifies a wrong-stamp marker as stale and
# claims no Bash. RED: a stale marker is counted. UNMEASURED (2): python3 or
# the frozen detector copy absent.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DET="${THR_DETECT:-$ROOT/tests/fixtures/detect.py}"
command -v python3 >/dev/null 2>&1 || { echo "UNMEASURED: python3 absent" >&2; exit 2; }
[ -f "$DET" ] || { echo "UNMEASURED: frozen detect.py absent" >&2; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft6.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
ARMDIR="$WORK/runs/SYNTH/arms/A9"; WS="$WORK/ws"
mkdir -p "$ARMDIR" "$WS"
printf 'ffffffff-ffff-ffff-ffff-ffffffffffff\n' > "$ARMDIR/session-id"
: > "$ARMDIR/stream.jsonl"
printf 'A9/SOME-OTHER-RUN' > "$WS/alive.marker"
printf 'A9/SOME-OTHER-RUN' > "$WS/A9.bash.marker"
python3 "$DET" "$ARMDIR" "$WS" > /dev/null
python3 - "$ARMDIR/detect.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
if d["disk"]["alive"]["present"] or d["disk_says_child_bash"]:
    print("RED: stale marker counted as live evidence", file=sys.stderr)
    raise SystemExit(1)
if not (d["disk"]["alive"]["stale"] and d["disk"]["bash"]["stale"]):
    print("RED: stale markers not recorded as stale", file=sys.stderr)
    raise SystemExit(1)
print("GREEN: wrong-stamp markers are stale, counted for nothing")
PY
