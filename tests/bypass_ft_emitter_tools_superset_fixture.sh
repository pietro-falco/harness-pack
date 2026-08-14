#!/usr/bin/env bash
# FT-13 -- emitter-tools-superset. An agent whose tools list names a tool the
# declared parent pool does not contain must be rejected at emission time with
# E_TOOLS_SUPERSET (66). The subset check is what makes an emitted declaration
# accurate regardless of runtime semantics (ADR-023): measured on 2.1.231 the
# runtime is subset-only too, but the emitter must not depend on that.
# GREEN: rejected with 66. RED: any other exit. UNMEASURED (2): node or the
# frozen emitter copy absent.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMITTER="${THR_EMITTER:-$ROOT/tests/fixtures/emit_agents.mjs}"
RESULT="$ROOT/tests/fixtures/thr_subagent_result_green.json"
command -v node >/dev/null 2>&1 || { echo "UNMEASURED: node absent" >&2; exit 2; }
if ! { [ -f "$EMITTER" ] && [ -f "$RESULT" ]; }; then echo "UNMEASURED: emitter or green RESULT copy absent" >&2; exit 2; fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft13.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/spec.json" <<'JSON'
{"parent_tools":["Read","Write"],
 "agents":{"p":{"description":"d","prompt":"p","tools":["Read","Bash"]}}}
JSON
node "$EMITTER" --spec "$WORK/spec.json" --result "$RESULT" >/dev/null 2>"$WORK/err"; rc=$?
[ "$rc" -eq 66 ] || { echo "RED: expected E_TOOLS_SUPERSET (66), got $rc" >&2; exit 1; }
grep -q E_TOOLS_SUPERSET "$WORK/err" || { echo "RED: exit 66 without E_TOOLS_SUPERSET named" >&2; exit 1; }
echo "GREEN: superset tools rejected with E_TOOLS_SUPERSET"
