#!/usr/bin/env bash
# FT-17 -- emitter-empty-tools-resolution. deny applies first, tools selects
# from the residue; a spec whose only declared tool is also denied resolves to
# zero tools, which at runtime is the documented "Agent would be spawned with
# zero tools" error. The emitter must refuse at emission time with
# E_ZERO_TOOLS (71) instead of shipping a definition that dies at spawn.
# GREEN: rejected with 71. RED: any other exit. UNMEASURED (2): preconditions.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMITTER="${THR_EMITTER:-$ROOT/tests/fixtures/emit_agents.mjs}"
RESULT="$ROOT/tests/fixtures/thr_subagent_result_green.json"
command -v node >/dev/null 2>&1 || { echo "UNMEASURED: node absent" >&2; exit 2; }
if ! { [ -f "$EMITTER" ] && [ -f "$RESULT" ]; }; then echo "UNMEASURED: emitter or green RESULT copy absent" >&2; exit 2; fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft17.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/spec.json" <<'JSON'
{"parent_tools":["Read","Write"],
 "agents":{"p":{"description":"d","prompt":"p","tools":["Write"],"disallowedTools":["Write"]}}}
JSON
node "$EMITTER" --spec "$WORK/spec.json" --result "$RESULT" >/dev/null 2>"$WORK/err"; rc=$?
[ "$rc" -eq 71 ] || { echo "RED: expected E_ZERO_TOOLS (71), got $rc" >&2; exit 1; }
grep -q E_ZERO_TOOLS "$WORK/err" || { echo "RED: exit 71 without the error named" >&2; exit 1; }
echo "GREEN: zero-tool resolution refused at emission time"
