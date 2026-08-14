#!/usr/bin/env bash
# COMMIT 2b — three observational seams, measured on a depth-2 run:
#   1. a PreToolUse hook that appends $HARNESS_SCOPE plus its stdin payload to
#      a JSONL ledger: does the env var survive into hook invocations fired
#      inside subagents at depth 1 and depth 2?
#   2. SubagentStart (and SubagentStop, same script, payload names the event)
#      appending one line per spawn: the delegation ledger, measured rather
#      than narrated. A depth-2 run must yield at least two spawn lines.
#   3. the marker Claude Code prepends to subagent reports when it recognizes
#      their form: extracted verbatim from the Agent tool_result, recorded as
#      a signal, not interpreted.
set -euo pipefail

RUN_DIR="${RUN_DIR:?export RUN_DIR}"
RUN_STAMP="$(basename "$RUN_DIR")"
WS_ROOT="${WS_ROOT:?export WS_ROOT}"
MODEL="${ARM_MODEL:-sonnet}"
ARM="C2b"

WS="$WS_ROOT/$ARM"
OUT="$RUN_DIR/arms/$ARM"
LEDGER="$OUT/ledger"
mkdir -p "$WS" "$OUT" "$LEDGER" "$OUT/hooks"
SID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
printf '%s\n' "$SID" > "$OUT/session-id"
PIN="$ARM/$RUN_STAMP"

cat > "$OUT/hooks/pretool.sh" <<'HOOK'
#!/bin/sh
printf '{"scope":"%s","payload":%s}\n' "${HARNESS_SCOPE:-UNSET}" "$(cat)" \
  >> "${SEAM_LEDGER_DIR:?}/pretooluse.jsonl"
HOOK
cat > "$OUT/hooks/spawn.sh" <<'HOOK'
#!/bin/sh
printf '{"at":"%s","payload":%s}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(cat)" \
  >> "${SEAM_LEDGER_DIR:?}/spawn.jsonl"
HOOK
chmod +x "$OUT/hooks/pretool.sh" "$OUT/hooks/spawn.sh"

cat > "$OUT/hook-settings.json" <<JSON
{
  "hooks": {
    "PreToolUse": [
      {"hooks": [{"type": "command", "command": "$OUT/hooks/pretool.sh"}]}
    ],
    "SubagentStart": [
      {"hooks": [{"type": "command", "command": "$OUT/hooks/spawn.sh"}]}
    ],
    "SubagentStop": [
      {"hooks": [{"type": "command", "command": "$OUT/hooks/spawn.sh"}]}
    ]
  }
}
JSON

PROBE_PROMPT="You are a measurement probe. Follow the task you are given exactly and in order."
RELAY_PROMPT="You are a relay. Call the Agent tool with subagent_type leaf and pass your entire task through verbatim as the task. When it returns, reply with its report verbatim."
AGENTS_JSON='{"mid":{"description":"Relay agent","prompt":"'"$RELAY_PROMPT"'","tools":["Read","Write","Agent"]},"leaf":{"description":"Leaf probe","prompt":"'"$PROBE_PROMPT"'","tools":["Read","Write"]}}'
CHILD_TASK="One step. Use the Write tool to create the file $WS/alive.marker with exactly this content: $PIN. Then reply DONE."
PARENT_PROMPT="You are the parent of a measurement arm. Do exactly this and nothing else: call the Agent tool with subagent_type mid and this exact task: $CHILD_TASK -- When the agent finishes, print its report verbatim and stop."

CMD=(claude -p "$PARENT_PROMPT"
     --session-id "$SID"
     --output-format stream-json --verbose --forward-subagent-text
     --include-hook-events
     --strict-mcp-config
     --max-turns 16 --max-budget-usd 2
     --permission-mode manual
     --model "$MODEL"
     --settings "$OUT/hook-settings.json"
     --tools "Read,Write,Agent"
     --allowedTools "Write,Agent"
     --agents "$AGENTS_JSON")

{ printf 'arm=%s session=%s\n' "$ARM" "$SID"
  printf 'argv:'; printf ' %q' "${CMD[@]}"; printf '\n'
} > "$OUT/invocation.txt"

set +e
( cd "$WS" && env CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=2 \
      CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS=1 \
      CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 \
      HARNESS_SCOPE=THR-SUBAGENT \
      SEAM_LEDGER_DIR="$LEDGER" \
      timeout 420 "${CMD[@]}" ) > "$OUT/stream.jsonl" 2> "$OUT/stderr.log"
RC=$?
set -e
printf '%s\n' "$RC" > "$OUT/exit-code"

{ echo "exit=$RC"
  echo "alive.marker: $(cat "$WS/alive.marker" 2>/dev/null || echo ABSENT)"
  echo "--- pretooluse.jsonl ($(wc -l < "$LEDGER/pretooluse.jsonl" 2>/dev/null || echo 0) rows) ---"
  cat "$LEDGER/pretooluse.jsonl" 2>/dev/null || true
  echo "--- spawn.jsonl ($(wc -l < "$LEDGER/spawn.jsonl" 2>/dev/null || echo 0) rows) ---"
  cat "$LEDGER/spawn.jsonl" 2>/dev/null || true
} > "$OUT/evidence.txt"
echo "seams done rc=$RC session=$SID rows: pretool=$(wc -l < "$LEDGER/pretooluse.jsonl" 2>/dev/null || echo 0) spawn=$(wc -l < "$LEDGER/spawn.jsonl" 2>/dev/null || echo 0)"
