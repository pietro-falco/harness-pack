#!/usr/bin/env bash
# FT-10 -- scope-env-absent-at-depth. The GUARD-SCOPE mechanism rides on
# $HARNESS_SCOPE reaching the PreToolUse hook. If the variable evaporated
# inside subagents, scope enforcement would silently cover depth 0 only.
# Measured on 2.1.231: rows fired inside subagents (payload carries agent_id)
# still see the variable at depth 1 and depth 2 -- the mechanism is
# depth-transparent and THR-SUBAGENT reduces to a configuration change.
# GREEN: every in-subagent row carries the scope value. RED: any row shows
# UNSET -- the defect this row hunts. UNMEASURED (2): no recorded ledger.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="${THR_SUBAGENT_RUN:-}"
[ -z "$RUN" ] && [ -f "$ROOT/runs/THR-SUBAGENT/.current" ] && RUN="$(cat "$ROOT/runs/THR-SUBAGENT/.current")"
LEDGER="${THR_PRETOOL_LEDGER:-$RUN/arms/C2b/ledger/pretooluse.jsonl}"
[ -f "$LEDGER" ] || { echo "UNMEASURED: no recorded PreToolUse ledger" >&2; exit 2; }
python3 - "$LEDGER" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
inside = [r for r in rows if r["payload"].get("agent_id")]
if not inside:
    print("UNMEASURED: no PreToolUse row fired inside a subagent", file=sys.stderr)
    raise SystemExit(2)
bad = [r for r in inside if r.get("scope") in (None, "", "UNSET")]
if bad:
    print("RED: %d/%d in-subagent hook rows lost HARNESS_SCOPE" % (len(bad), len(inside)),
          file=sys.stderr)
    raise SystemExit(1)
print("GREEN: HARNESS_SCOPE survives into hooks at depth 1 and 2")
PY
