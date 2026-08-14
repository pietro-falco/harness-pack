#!/usr/bin/env bash
# FT-15 -- emitter-agent-without-depth-bound. An agent that pools Agent can
# delegate, and a spec that does not declare max_spawn_depth has declared an
# unbounded delegation tree. Measured on 2.1.231 the depth env
# (CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH) is what bounds it, so the spec must
# carry the number the launcher will export. Rejected with
# E_AGENT_WITHOUT_DEPTH_BOUND (68).
# GREEN: rejected with 68. RED: any other exit. UNMEASURED (2): preconditions.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMITTER="${THR_EMITTER:-$ROOT/tests/fixtures/emit_agents.mjs}"
RESULT="$ROOT/tests/fixtures/thr_subagent_result_green.json"
command -v node >/dev/null 2>&1 || { echo "UNMEASURED: node absent" >&2; exit 2; }
if ! { [ -f "$EMITTER" ] && [ -f "$RESULT" ]; }; then echo "UNMEASURED: emitter or green RESULT copy absent" >&2; exit 2; fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft15.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/spec.json" <<'JSON'
{"parent_tools":["Read","Agent"],
 "agents":{"p":{"description":"d","prompt":"p","tools":["Read","Agent"]}}}
JSON
node "$EMITTER" --spec "$WORK/spec.json" --result "$RESULT" >/dev/null 2>"$WORK/err"; rc=$?
[ "$rc" -eq 68 ] || { echo "RED: expected E_AGENT_WITHOUT_DEPTH_BOUND (68), got $rc" >&2; exit 1; }
grep -q E_AGENT_WITHOUT_DEPTH_BOUND "$WORK/err" || { echo "RED: exit 68 without the error named" >&2; exit 1; }
echo "GREEN: Agent without a declared depth bound rejected"
