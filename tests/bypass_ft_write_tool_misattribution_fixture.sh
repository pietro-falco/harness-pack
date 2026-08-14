#!/usr/bin/env bash
# FT-8 -- write-tool-misattribution. Liveness and capability are different
# facts: alive.marker is written by the Write tool and proves the child ran;
# only <ARM>.bash.marker proves Bash executed. A detector that let the Write
# marker satisfy the Bash claim would turn every live child into a false
# capability finding. Feed the frozen detector a workspace with ONLY a
# correctly-pinned alive.marker and assert the Bash claim stays false.
# GREEN: alive=present, bash claim=false. RED: Write liveness leaks into the
# Bash claim. UNMEASURED (2): python3 or the frozen detector copy absent.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DET="${THR_DETECT:-$ROOT/tests/fixtures/detect.py}"
command -v python3 >/dev/null 2>&1 || { echo "UNMEASURED: python3 absent" >&2; exit 2; }
[ -f "$DET" ] || { echo "UNMEASURED: frozen detect.py absent" >&2; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft8.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
ARMDIR="$WORK/runs/SYNTH/arms/A9"; WS="$WORK/ws"
mkdir -p "$ARMDIR" "$WS"
printf 'ffffffff-ffff-ffff-ffff-ffffffffffff\n' > "$ARMDIR/session-id"
: > "$ARMDIR/stream.jsonl"
printf 'A9/SYNTH' > "$WS/alive.marker"
python3 "$DET" "$ARMDIR" "$WS" > /dev/null
python3 - "$ARMDIR/detect.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
if not d["disk"]["alive"]["present"]:
    print("RED: pinned alive.marker not recognized", file=sys.stderr)
    raise SystemExit(1)
if d["disk_says_child_bash"]:
    print("RED: Write-produced liveness attributed to Bash", file=sys.stderr)
    raise SystemExit(1)
print("GREEN: liveness and Bash capability stay separate facts")
PY
