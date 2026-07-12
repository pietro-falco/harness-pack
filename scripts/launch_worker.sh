#!/usr/bin/env bash
# Mode B launcher. Owns: HALT check, tier resolution (G6), constitution
# injection + hash (provability of G1..G7), bounded run, receipt write.
# Env: HARNESS_HOME (pack dir; default: this script's parent),
#      HARNESS_MANIFEST (default: $HARNESS_HOME/templates/manifest.example.json),
#      RECEIPTS_DIR (default: ./.harness/receipts)
# Verify flag names against current Claude Code docs at wiring time;
# this file is the only seam if the CLI contract drifts.
set -euo pipefail
SPEC="${1:?usage: launch_worker.sh SPEC.md}"
HARNESS_HOME="${HARNESS_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
MANIFEST="${HARNESS_MANIFEST:-$HARNESS_HOME/templates/manifest.example.json}"
CONST="$HARNESS_HOME/CONSTITUTION.md"
RECEIPTS_DIR="${RECEIPTS_DIR:-./.harness/receipts}"
mkdir -p "$RECEIPTS_DIR"

# Operator kill-switch: touch .harness/HALT to refuse new runs.
if [ -e "$(dirname "$RECEIPTS_DIR")/HALT" ]; then
  echo "STOP: HALT file present; refusing to launch." >&2; exit 1
fi

read -r SPEC_ID TIER MODE MAXTURNS WALLMIN TOOLS <<<"$(python3 - "$SPEC" <<'PYEOF'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
def grab(k, d=""):
    m = re.search(rf"^{k}:\s*\"?([^\"\n#]+)", t, re.M)
    return (m.group(1).strip() if m else d)
print(grab("id","UNKNOWN"), grab("tier",""), grab("mode","A"),
      grab("  max_turns","15"), grab("  wall_clock_min","20"),
      grab("tools","Read,Edit,Bash,Grep,Glob"))
PYEOF
)"
[ -n "$TIER" ] || { echo "STOP: spec missing tier" >&2; exit 1; }
[ "$MODE" = "B" ] || { echo "STOP: spec mode is not B; use Mode A flow." >&2; exit 1; }

read -r RESOLVED MODEL MVER <<<"$(python3 - "$MANIFEST" "$TIER" <<'PYEOF'
import json, sys
m = json.load(open(sys.argv[1])); t = sys.argv[2]
tier = m["tiers"][t]
if not tier.get("chain"):
    rt = tier.get("resolves_to")
    order = ["T0","T1","T2","T3"]
    if not rt or (order.index(rt) - order.index(t)) not in (0, 1):
        print("STOPX X 0"); sys.exit()
    t = rt; tier = m["tiers"][t]
    if not tier.get("chain"):
        print("STOPX X 0"); sys.exit()
print(t, tier["chain"][0], m["manifest_version"])
PYEOF
)"
[ "$RESOLVED" != "STOPX" ] || { echo "STOP: empty chain / illegal resolves_to (config error)" >&2; exit 1; }

CHASH="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$CONST")"
TOOLVER="$(claude --version 2>/dev/null || echo unknown)"
RUN_ID="run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
OUT="$RECEIPTS_DIR/$RUN_ID.cc.json"
echo "spec=$SPEC_ID tier_requested=$TIER tier_resolved=$RESOLVED model=$MODEL manifest=$MVER constitution=$CHASH"

TIMEOUT_CMD=""
command -v timeout >/dev/null && TIMEOUT_CMD="timeout $((WALLMIN*60))"
command -v gtimeout >/dev/null && TIMEOUT_CMD="gtimeout $((WALLMIN*60))"

set +e
# shellcheck disable=SC2086  # intentional word-splitting of optional timeout prefix
$TIMEOUT_CMD claude -p \
  --model "$MODEL" \
  --append-system-prompt "$(cat "$CONST")" \
  --settings "$HARNESS_HOME/templates/settings.mode-b.json" \
  --allowedTools "$TOOLS" \
  --permission-mode dontAsk \
  --max-turns "$MAXTURNS" \
  --output-format json < "$SPEC" > "$OUT"
CC_EXIT=$?
set -e
ENDED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "$OUT" "$RECEIPTS_DIR/$RUN_ID.receipt.json" <<PYEOF
import json, sys
try:
    cc = json.load(open(sys.argv[1]))
except Exception:
    cc = {"subtype": "error_no_output"}
receipt = {
  "run_id": "$RUN_ID", "spec_id": "$SPEC_ID", "mode": "B",
  "tier_requested": "$TIER", "tier_resolved": "$RESOLVED",
  "model_used": "$MODEL", "manifest_version": int("$MVER"),
  "constitution_hash": "$CHASH", "tool_version": "$TOOLVER",
  "started_at": "$STARTED", "ended_at": "$ENDED",
  "subtype": cc.get("subtype","unknown"),
  "num_turns": cc.get("num_turns", -1),
  "total_cost_usd": cc.get("total_cost_usd"),
  "duration_ms": cc.get("duration_ms"),
  "session_id": cc.get("session_id",""),
  "stop_reason": "cc_exit=$CC_EXIT",
  "claims": []
}
json.dump(receipt, open(sys.argv[2], "w"), indent=1)
print("receipt:", sys.argv[2])
PYEOF

# Non-success is a full stop for the operator to review (G5).
[ "$CC_EXIT" -eq 0 ] || exit "$CC_EXIT"
