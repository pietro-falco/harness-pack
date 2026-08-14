#!/usr/bin/env bash
# COMMIT 2 — does --append-subagent-system-prompt reach depth-2 subagents?
# The doc claims it does from v2.1.205. The probe token is 16 hex chars that
# exist ONLY in the appended system prompt text: never in the task, never in
# CLAUDE.md, never in the --agents JSON. Not derivable from any other source,
# so a marker file named <token>.marker written by the depth-2 leaf is proof
# the appended text arrived. The negative control runs the same arm without
# the flag and must produce control.marker with the token nowhere on disk or
# in the stream. Usage: prompt_propagation.sh <pos|neg>
set -euo pipefail

RUN_DIR="${RUN_DIR:?export RUN_DIR}"
RUN_STAMP="$(basename "$RUN_DIR")"
WS_ROOT="${WS_ROOT:?export WS_ROOT}"
MODEL="${ARM_MODEL:-sonnet}"
VARIANT="${1:?usage: prompt_propagation.sh <pos|neg>}"
ARM="C2$VARIANT"

WS="$WS_ROOT/$ARM"
OUT="$RUN_DIR/arms/$ARM"
mkdir -p "$WS" "$OUT"
SID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
printf '%s\n' "$SID" > "$OUT/session-id"
PIN="$ARM/$RUN_STAMP"

# One token per variant, minted here and recorded; grep must find it nowhere
# but the flag text (pos) or nowhere at all (neg).
TOKEN="$(openssl rand -hex 8)"
printf '%s\n' "$TOKEN" > "$OUT/token"

PROBE_PROMPT="You are a measurement probe. Follow the task you are given exactly and in order."
RELAY_PROMPT="You are a relay. Call the Agent tool with subagent_type leaf and pass your entire task through verbatim as the task. When it returns, reply with its report verbatim."
AGENTS_JSON='{"mid":{"description":"Relay agent","prompt":"'"$RELAY_PROMPT"'","tools":["Read","Write","Agent"]},"leaf":{"description":"Leaf probe","prompt":"'"$PROBE_PROMPT"'","tools":["Read","Write"]}}'

CHILD_TASK="One step. If your system prompt contains a MEASUREMENT NOTE giving a marker file name, use the Write tool to create exactly that file inside $WS with exactly this content: $PIN. If no such note exists, create $WS/control.marker with that content instead. Then reply DONE."
PARENT_PROMPT="You are the parent of a measurement arm. Do exactly this and nothing else: call the Agent tool with subagent_type mid and this exact task: $CHILD_TASK -- When the agent finishes, print its report verbatim and stop."

CMD=(claude -p "$PARENT_PROMPT"
     --session-id "$SID"
     --output-format stream-json --verbose --forward-subagent-text
     --strict-mcp-config
     --max-turns 16 --max-budget-usd 2
     --permission-mode manual
     --model "$MODEL"
     --settings '{"disableAllHooks":true}'
     --tools "Read,Write,Agent"
     --allowedTools "Write,Agent"
     --agents "$AGENTS_JSON")
if [ "$VARIANT" = pos ]; then
  CMD+=(--append-subagent-system-prompt "MEASUREMENT NOTE: when a task asks you to create a marker file, name the file $TOKEN.marker.")
fi

{ printf 'arm=%s session=%s token=%s variant=%s\n' "$ARM" "$SID" "$TOKEN" "$VARIANT"
  printf 'argv:'; printf ' %q' "${CMD[@]}"; printf '\n'
} > "$OUT/invocation.txt"

set +e
( cd "$WS" && env CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=2 \
      CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS=1 \
      CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 \
      timeout 420 "${CMD[@]}" ) > "$OUT/stream.jsonl" 2> "$OUT/stderr.log"
RC=$?
set -e
printf '%s\n' "$RC" > "$OUT/exit-code"

# Evidence sweep, recorded not judged: which marker exists, where the token
# appears (stream, transcripts if any), and the disk listing.
{ echo "exit=$RC"
  echo "ws listing:"; ls -1 "$WS" 2>/dev/null
  if [ -f "$WS/$TOKEN.marker" ]; then echo "token marker: PRESENT content=$(cat "$WS/$TOKEN.marker")"; else echo "token marker: ABSENT"; fi
  if [ -f "$WS/control.marker" ]; then echo "control marker: PRESENT content=$(cat "$WS/control.marker")"; else echo "control marker: ABSENT"; fi
  printf 'token in stream.jsonl: %s occurrence(s)\n' "$(grep -c "$TOKEN" "$OUT/stream.jsonl" || true)"
  printf 'token in ~/.claude/projects transcripts: %s file(s)\n' "$(grep -rl "$TOKEN" "$HOME/.claude/projects" 2>/dev/null | wc -l | tr -d ' ')"
} > "$OUT/evidence.txt"
cat "$OUT/evidence.txt"
