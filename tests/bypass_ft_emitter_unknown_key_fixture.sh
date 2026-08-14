#!/usr/bin/env bash
# FT-14 -- emitter-unknown-key. The --agents vocabulary is CLOSED at the
# sixteen documented keys. A key outside it -- here "allowedTools", the exact
# confusion ADR-022 exists to prevent -- must be rejected with E_UNKNOWN_KEY
# (67), because the CLI ignores unknown keys silently and a spec author who
# typed allowedTools believing it bounds anything has declared nothing.
# GREEN: rejected with 67. RED: any other exit. UNMEASURED (2): preconditions.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMITTER="${THR_EMITTER:-$ROOT/tests/fixtures/emit_agents.mjs}"
RESULT="$ROOT/tests/fixtures/thr_subagent_result_green.json"
command -v node >/dev/null 2>&1 || { echo "UNMEASURED: node absent" >&2; exit 2; }
if ! { [ -f "$EMITTER" ] && [ -f "$RESULT" ]; }; then echo "UNMEASURED: emitter or green RESULT copy absent" >&2; exit 2; fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft14.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/spec.json" <<'JSON'
{"parent_tools":["Read"],
 "agents":{"p":{"description":"d","prompt":"p","allowedTools":["Read"]}}}
JSON
node "$EMITTER" --spec "$WORK/spec.json" --result "$RESULT" >/dev/null 2>"$WORK/err"; rc=$?
[ "$rc" -eq 67 ] || { echo "RED: expected E_UNKNOWN_KEY (67), got $rc" >&2; exit 1; }
grep -q E_UNKNOWN_KEY "$WORK/err" || { echo "RED: exit 67 without E_UNKNOWN_KEY named" >&2; exit 1; }
echo "GREEN: out-of-vocabulary key rejected with E_UNKNOWN_KEY"
