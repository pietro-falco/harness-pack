#!/usr/bin/env bash
# FT-18 -- emitter-deny-order-inversion. Resolution order is deny first, then
# tools on the residue: a tool present in both tools and disallowedTools ends
# REMOVED. If it survives into the declared surface, the emitter has inverted
# the order and the definition it emits does not describe the agent that will
# run. Deny rules use the bare-name form on purpose: the parenthesized form
# leaves the tool in context and denies only matching calls (E_DENY_FORM
# guards that separately, FT-13..17 style).
# GREEN: emission succeeds AND the declared surface excludes the denied tool.
# RED: denied tool survives, or emission fails. UNMEASURED (2): preconditions.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMITTER="${THR_EMITTER:-$ROOT/tests/fixtures/emit_agents.mjs}"
RESULT="$ROOT/tests/fixtures/thr_subagent_result_green.json"
command -v node >/dev/null 2>&1 || { echo "UNMEASURED: node absent" >&2; exit 2; }
if ! { [ -f "$EMITTER" ] && [ -f "$RESULT" ]; }; then echo "UNMEASURED: emitter or green RESULT copy absent" >&2; exit 2; fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft18.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/spec.json" <<'JSON'
{"parent_tools":["Read","Write"],
 "agents":{"p":{"description":"d","prompt":"p","tools":["Read","Write"],"disallowedTools":["Write"]}}}
JSON
node "$EMITTER" --spec "$WORK/spec.json" --result "$RESULT" --explain >"$WORK/out" 2>"$WORK/err"; rc=$?
[ "$rc" -eq 0 ] || { echo "RED: emission failed rc=$rc where a one-tool surface should emit" >&2; exit 1; }
if grep -q '"p":\[[^]]*"Write"' "$WORK/err"; then
  echo "RED: Write survives in the declared surface; deny order inverted" >&2; exit 1
fi
grep -q '"p":\["Read"\]' "$WORK/err" || { echo "RED: declared surface is not [Read]" >&2; exit 1; }
echo "GREEN: tool present in both lists is removed from the declared surface"
