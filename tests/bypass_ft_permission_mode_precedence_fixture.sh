#!/usr/bin/env bash
# FT-11 -- permission-mode-precedence. The doc declares the parent's
# permission mode prevails and a child permissionMode cannot override it. Arm
# A5 measured it: parent acceptEdits, child declaring "default", no
# --allowedTools at all -- the child's Write executed without a grant, so the
# parent's mode governed. The emitter models that precedence; this row pins
# the measurement the model rests on.
# GREEN: A5 alive marker present with detectors agreeing. RED: A5 measured
# and the Write was denied (child mode governed) -- the doc claim broke.
# UNMEASURED (2): no recorded run, or A5 not measured.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="${THR_SUBAGENT_RUN:-}"
[ -z "$RUN" ] && [ -f "$ROOT/runs/THR-SUBAGENT/.current" ] && RUN="$(cat "$ROOT/runs/THR-SUBAGENT/.current")"
if ! { [ -n "$RUN" ] && [ -f "$RUN/arms/A5/detect.json" ]; }; then echo "UNMEASURED: A5 not recorded" >&2; exit 2; fi
python3 - "$RUN/arms/A5/detect.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
if not d.get("measured"):
    print("UNMEASURED: A5 arm did not measure", file=sys.stderr)
    raise SystemExit(2)
if not (d["disk"]["alive"]["present"] and d["detectors_agree"]):
    print("RED: child Write did not execute under parent acceptEdits; "
          "parent-mode precedence broke", file=sys.stderr)
    raise SystemExit(1)
print("GREEN: parent permission mode governed the child")
PY
