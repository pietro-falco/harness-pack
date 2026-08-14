#!/usr/bin/env bash
# FT-5 -- positive-control-bash-in-pool. Arm A8 is the row every other arm
# leans on: Bash in --tools AND in --allowedTools, both markers must appear
# (alive.marker via Write, A8.bash.marker via Bash) with both detectors in
# agreement. If A8 is not green, the apparatus measures nothing and every
# negative outcome elsewhere is void -- which is why this row asserts the
# recorded RESULT.json rather than trusting the prose around it.
# GREEN: A8 CONFORME, both markers, detectors agree. RED: anything else.
# UNMEASURED (2): no run directory on this machine (fresh CI clone).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="${THR_SUBAGENT_RUN:-}"
[ -z "$RUN" ] && [ -f "$ROOT/runs/THR-SUBAGENT/.current" ] && RUN="$(cat "$ROOT/runs/THR-SUBAGENT/.current")"
if ! { [ -n "$RUN" ] && [ -f "$RUN/RESULT.json" ]; }; then echo "UNMEASURED: no THR-SUBAGENT run with RESULT.json" >&2; exit 2; fi
python3 - "$RUN/RESULT.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
a8 = r.get("arms", {}).get("A8", {})
ok = (a8.get("outcome") == "CONFORME" and a8.get("alive_marker")
      and a8.get("disk_says_child_bash") and a8.get("stream_says_child_bash")
      and a8.get("detectors_agree"))
if not ok:
    print("RED: A8 positive control not green:", json.dumps(a8)[:200], file=sys.stderr)
    raise SystemExit(1)
print("GREEN: A8 produced both markers, detectors agree")
PY
