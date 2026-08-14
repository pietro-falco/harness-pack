#!/usr/bin/env bash
# FT-16 -- emitter-memory-undeclared. Arm A6 measured where memory "project"
# writes: <cwd>/.claude/agent-memory/<agent-name>/, nothing under ~/.claude.
# A spec that grants memory without declaring that path has an agent writing
# state the spec never mentions. Rejected with E_MEMORY_UNDECLARED (69).
# GREEN: rejected with 69. RED: any other exit. UNMEASURED (2): preconditions.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMITTER="${THR_EMITTER:-$ROOT/tests/fixtures/emit_agents.mjs}"
RESULT="$ROOT/tests/fixtures/thr_subagent_result_green.json"
command -v node >/dev/null 2>&1 || { echo "UNMEASURED: node absent" >&2; exit 2; }
if ! { [ -f "$EMITTER" ] && [ -f "$RESULT" ]; }; then echo "UNMEASURED: emitter or green RESULT copy absent" >&2; exit 2; fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft16.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/spec.json" <<'JSON'
{"parent_tools":["Read"],
 "agents":{"p":{"description":"d","prompt":"p","tools":["Read"],"memory":"project"}}}
JSON
node "$EMITTER" --spec "$WORK/spec.json" --result "$RESULT" >/dev/null 2>"$WORK/err"; rc=$?
[ "$rc" -eq 69 ] || { echo "RED: expected E_MEMORY_UNDECLARED (69), got $rc" >&2; exit 1; }
grep -q E_MEMORY_UNDECLARED "$WORK/err" || { echo "RED: exit 69 without the error named" >&2; exit 1; }
echo "GREEN: memory without a declared path rejected"
