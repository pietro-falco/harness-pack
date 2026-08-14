#!/usr/bin/env bash
# FT-9 -- spawn-ledger-depth-blind. The SubagentStart hook fires per spawn on
# 2.1.231 and its payload names agent_id, agent_type, cwd, session_id,
# transcript_path -- and NO depth. A delegation ledger that cannot say at what
# depth a spawn happened cannot distinguish a flat fan-out from a chain, so
# the observability primitive a multi-agent run needs is still missing. This
# row stands RED until the payload (or the ledger deriving it) carries depth.
# RED (exit 1): SubagentStart rows lack a numeric depth field (today).
# GREEN: every spawn row carries one. UNMEASURED (2): no recorded ledger.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="${THR_SUBAGENT_RUN:-}"
[ -z "$RUN" ] && [ -f "$ROOT/runs/THR-SUBAGENT/.current" ] && RUN="$(cat "$ROOT/runs/THR-SUBAGENT/.current")"
LEDGER="${THR_SPAWN_LEDGER:-$RUN/arms/C2b/ledger/spawn.jsonl}"
[ -f "$LEDGER" ] || { echo "UNMEASURED: no recorded spawn ledger" >&2; exit 2; }
python3 - "$LEDGER" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
starts = [r for r in rows if r["payload"].get("hook_event_name") == "SubagentStart"]
if len(starts) < 2:
    print("UNMEASURED: fewer than two SubagentStart rows on a depth-2 run", file=sys.stderr)
    raise SystemExit(2)
blind = [r for r in starts if not isinstance(r["payload"].get("depth"), int)]
if blind:
    print("RED: %d/%d SubagentStart rows carry no depth field; the ledger is depth-blind"
          % (len(blind), len(starts)), file=sys.stderr)
    raise SystemExit(1)
print("GREEN: every spawn row carries a numeric depth")
PY
