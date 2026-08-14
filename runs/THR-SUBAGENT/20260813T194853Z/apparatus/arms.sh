#!/usr/bin/env bash
# THR-SUBAGENT measurement arms. One arm per invocation: arms.sh <ARM>
#
# Every arm is a separate `claude -p` with a pinned, recorded session id,
# stream-json output, --strict-mcp-config with no --mcp-config, an explicit
# --permission-mode, an explicit CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH, and a
# bounded --max-turns and wall clock. The pool axis (--tools) and the
# permission axis (--allowedTools) are set separately on purpose: the doc
# treats them as distinct mechanisms, so the apparatus must be able to observe
# (a) a Bash tool_use being emitted at all — Bash was in the child pool — and
# (b) that tool_use executing or being denied — permission decided.
#
# Two independent detectors, evaluated by detect.py after each arm:
#   disk    alive.marker written via the Write tool, <ARM>.bash.marker written
#           via the Bash tool, both content-pinned to <ARM>/<RUN_STAMP> so a
#           marker from any other run is stale and counts for nothing
#   stream  tool_use name=Bash attributable to the child (parent_tool_use_id
#           set, or present in the child transcript under
#           ~/.claude/projects/*/<session-id>/subagents/), plus its result
# No marker = NOT MEASURED = apparatus failure, never conformity.
set -euo pipefail

RUN_DIR="${RUN_DIR:?export RUN_DIR to the runs/THR-SUBAGENT/<stamp> directory}"
RUN_STAMP="$(basename "$RUN_DIR")"
WS_ROOT="${WS_ROOT:?export WS_ROOT to a writable workspace root outside any repo}"
MODEL="${ARM_MODEL:-sonnet}"

ARM="${1:?usage: arms.sh <A1fg|A1bg|A2fg|A2bg|A3|A4|A5|A6|A7|A8>}"

PROBE_PROMPT="You are a measurement probe. Follow the task you are given exactly and in order. Attempt every step even if a tool seems unavailable to you: a tool error is expected data. Never substitute one tool for another."
RELAY_PROMPT="You are a relay. Call the Agent tool with subagent_type leaf and pass your entire task through verbatim as the task. When it returns, reply with its report verbatim."

# Defaults, overridden per arm below.
DEPTH=1
PMODE=manual
TOOLS="Read,Write,Agent"
ALLOWED="Write,Bash,Agent"
AGENTS_JSON=""
AGENT_TYPE="probe"
BG=false
DISABLE_BUILTIN=0
DISABLE_BG_TASKS=1
MAXTURNS=12
WALL=300
TASK_KIND=markers

case "$ARM" in
  A1fg) DISABLE_BUILTIN=1
        AGENTS_JSON='{"probe":{"description":"Measurement probe","prompt":"'"$PROBE_PROMPT"'"}}' ;;
  A1bg) DISABLE_BUILTIN=1; DISABLE_BG_TASKS=0; BG=true; MAXTURNS=16; WALL=420
        AGENTS_JSON='{"probe":{"description":"Measurement probe","prompt":"'"$PROBE_PROMPT"'"}}' ;;
  A2fg) DISABLE_BUILTIN=1
        AGENTS_JSON='{"probe":{"description":"Measurement probe","prompt":"'"$PROBE_PROMPT"'","tools":["Read","Write","Bash"]}}' ;;
  A2bg) DISABLE_BUILTIN=1; DISABLE_BG_TASKS=0; BG=true; MAXTURNS=16; WALL=420
        AGENTS_JSON='{"probe":{"description":"Measurement probe","prompt":"'"$PROBE_PROMPT"'","tools":["Read","Write","Bash"]}}' ;;
  A3)   DISABLE_BUILTIN=1; DEPTH=2; AGENT_TYPE=mid; MAXTURNS=16; WALL=420; TASK_KIND=relay
        AGENTS_JSON='{"mid":{"description":"Relay agent","prompt":"'"$RELAY_PROMPT"'","tools":["Read","Write","Agent"]},"leaf":{"description":"Leaf probe","prompt":"'"$PROBE_PROMPT"'","tools":["Read","Write","Bash"]}}' ;;
  A4)   TOOLS=""; AGENT_TYPE=general-purpose ;;
  A5)   PMODE=acceptEdits; ALLOWED="Agent"
        AGENTS_JSON='{"probe":{"description":"Measurement probe","prompt":"'"$PROBE_PROMPT"'","permissionMode":"default"}}' ;;
  A6)   ALLOWED="Write,Agent"; TASK_KIND=memory
        AGENTS_JSON='{"probe":{"description":"Measurement probe","prompt":"'"$PROBE_PROMPT"'","memory":"project"}}' ;;
  A7)   ALLOWED="Write,Agent"; TASK_KIND=skill
        AGENTS_JSON='{"probe":{"description":"Measurement probe","prompt":"'"$PROBE_PROMPT"'","skills":["graphify"]}}' ;;
  A8)   TOOLS="Read,Write,Bash,Agent"
        AGENTS_JSON='{"probe":{"description":"Measurement probe","prompt":"'"$PROBE_PROMPT"'","tools":["Read","Write","Bash"]}}' ;;
  *) echo "unknown arm: $ARM" >&2; exit 64 ;;
esac

WS="$WS_ROOT/$ARM"
OUT="$RUN_DIR/arms/$ARM"
mkdir -p "$WS" "$OUT"
touch "$OUT/t0"
SID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
printf '%s\n' "$SID" > "$OUT/session-id"

PIN="$ARM/$RUN_STAMP"
case "$TASK_KIND" in
  markers|relay)
    CHILD_TASK="Two steps, in order. Step 1: use the Write tool to create the file $WS/alive.marker with exactly this content: $PIN. Step 2: call the Bash tool with exactly this command: printf %s '$PIN' > $WS/$ARM.bash.marker. You MUST attempt Step 2 even if you believe the Bash tool is unavailable; a tool error is expected data. Finally reply with DONE plus the exact list of tool names available to you." ;;
  memory)
    CHILD_TASK="Two steps, in order. Step 1: use the Write tool to create the file $WS/alive.marker with exactly this content: $PIN. Step 2: store in your persistent memory, for future runs: the probe constant is seventeen. Finally reply with DONE plus the exact list of tool names available to you." ;;
  skill)
    CHILD_TASK="Two steps, in order. Step 1: if the full content of a skill named graphify is present in your context, reply with a line starting CLAIM-SKILL-PRESENT: followed by the first markdown heading of that content verbatim; otherwise reply CLAIM-SKILL-ABSENT. Step 2: use the Write tool to create the file $WS/alive.marker with exactly this content: $PIN. Finally reply with DONE plus the exact list of tool names available to you." ;;
esac

if [ "$BG" = true ]; then
  PARENT_PROMPT="You are the parent of a measurement arm. Do exactly this and nothing else: call the Agent tool with subagent_type $AGENT_TYPE, run_in_background set to true, and this exact task: $CHILD_TASK -- After launching, do not end your turn until the background agent has completed; when its completion notification arrives, print its report verbatim and stop."
else
  PARENT_PROMPT="You are the parent of a measurement arm. Do exactly this and nothing else: call the Agent tool with subagent_type $AGENT_TYPE and this exact task: $CHILD_TASK -- When the agent finishes, print its report verbatim and stop."
fi

ENVV=("CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=$DEPTH")
[ "$DISABLE_BUILTIN" = 1 ] && ENVV+=("CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS=1")
[ "$DISABLE_BG_TASKS" = 1 ] && ENVV+=("CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1")

CMD=(claude -p "$PARENT_PROMPT"
     --session-id "$SID"
     --output-format stream-json --verbose --forward-subagent-text
     --strict-mcp-config
     --max-turns "$MAXTURNS" --max-budget-usd 2
     --permission-mode "$PMODE"
     --model "$MODEL"
     --settings '{"disableAllHooks":true}')
# A4 leaves TOOLS empty meaning "do not pass the flag" (default pool). An
# explicit --tools "" is the documented "disable all tools" and was observed
# doing exactly that on 2.1.231: it removed Agent itself and the parent could
# not delegate at all (first A4 run, kept under arms/A4-tools-empty-string/).
[ -n "$TOOLS" ] && CMD+=(--tools "$TOOLS")
[ -n "$ALLOWED" ] && CMD+=(--allowedTools "$ALLOWED")
[ -n "$AGENTS_JSON" ] && CMD+=(--agents "$AGENTS_JSON")

{ printf 'arm=%s session=%s depth=%s pmode=%s tools=%s allowed=%s bg=%s\n' \
    "$ARM" "$SID" "$DEPTH" "$PMODE" "$TOOLS" "$ALLOWED" "$BG"
  printf 'env: %s\n' "${ENVV[@]}"
  printf 'argv:'; printf ' %q' "${CMD[@]}"; printf '\n'
} > "$OUT/invocation.txt"

if [ "$TASK_KIND" = memory ]; then
  find "$WS/.claude" "$HOME/.claude/agent-memory" -type f 2>/dev/null | sort > "$OUT/memory-before.txt" || true
fi

set +e
( cd "$WS" && env "${ENVV[@]}" timeout "$WALL" "${CMD[@]}" ) \
  > "$OUT/stream.jsonl" 2> "$OUT/stderr.log"
RC=$?
set -e
printf '%s\n' "$RC" > "$OUT/exit-code"

if [ "$TASK_KIND" = memory ]; then
  find "$WS/.claude" "$HOME/.claude/agent-memory" -type f 2>/dev/null | sort > "$OUT/memory-after.txt" || true
  find "$HOME/.claude" -type f -newer "$OUT/t0" -path '*memor*' 2>/dev/null | sort > "$OUT/memory-new-under-home.txt" || true
fi

echo "arm $ARM done rc=$RC session=$SID"
