#!/usr/bin/env bash
# Mode B launcher. Pack-side responsibilities only (ADR-005 D6): HALT check,
# constitution hash pin (fail-closed) + injection, bounded run, receipt write.
# It does NOT parse specs (ADR-005 D1/D2): it consumes `harnesswright next --json`
# and executes over the resolved plan. The one place the two model vocabularies
# meet is pack-side, resolving next's opaque model-string through the manifest's
# model_tiers to a concrete model (ADR-005 D4).
#
# Env:
#   HARNESSWRIGHT_CLI  path to the harnesswright CLI entrypoint
#                      (default: $HOME/Code/harnesswright/dist/cli.js)
#   HARNESS_HOME       pack dir (default: this script's parent)
#   HARNESS_MANIFEST   default: $HARNESS_HOME/templates/manifest.example.json
#   RECEIPTS_DIR       default: ./.harness/pack/receipts
#   LAUNCH_DRYRUN      if =1, resolve + print the launch decision and exit 0 BEFORE
#                      hashing the constitution or invoking claude; writes nothing.
#                      Preview + test affordance; the gate logic above it is identical.
# Verify claude flag names against current Claude Code docs at wiring time; this file
# is the only seam if the runner CLI contract drifts.
set -euo pipefail

usage() { echo "usage: launch_worker.sh SPEC.md" >&2; exit 2; }
[ $# -eq 1 ] || usage
SPEC="$1"
[ -f "$SPEC" ] || { echo "STOP: spec file not found: $SPEC" >&2; exit 1; }

HARNESS_HOME="${HARNESS_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
MANIFEST="${HARNESS_MANIFEST:-$HARNESS_HOME/templates/manifest.example.json}"
CONST="$HARNESS_HOME/CONSTITUTION.md"
RECEIPTS_DIR="${RECEIPTS_DIR:-./.harness/pack/receipts}"

# harnesswright CLI, fail-closed (ADR-005 D6 STOP "CLI not resolvable"; Consequences a:
# pin the resolution path at wiring time). Default to the LOCAL BUILD: it is the only
# artifact guaranteed to carry spec.tools/tools_source (ADR-005 D3); the published npm
# 0.1.1 may predate that field. Override via HARNESSWRIGHT_CLI.
HW_CLI="${HARNESSWRIGHT_CLI:-$HOME/Code/harnesswright/dist/cli.js}"
[ -f "$HW_CLI" ] || { echo "STOP: harnesswright CLI not resolvable at $HW_CLI" >&2; exit 1; }

# Operator kill-switch (unchanged): git-root-anchored HALT file, checked before the
# first write so a refused launch leaves no receipts dir behind and is independent of
# RECEIPTS_DIR.
HALT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [ -e "$HALT_ROOT/.harness/HALT" ]; then
  echo "STOP: HALT file present; refusing to launch." >&2; exit 1
fi

# The slice the operator requested, derived from the spec FILENAME only, never by
# parsing the spec (ADR-005 D1: one dialect, and the launcher is not its second reader).
REQUESTED_ID="$(basename "$SPEC" .md)"

# Consume `next --json` (ADR-005 D2). next reads .harness/harness.json relative to its
# cwd, so run it at the target repo root. Capture stdout and exit code separately; a
# non-zero exit is a STOP (D6), never a fallback.
NEXT_ERR="${TMPDIR:-/tmp}/hw_next.$$.err"
set +e
NEXT_JSON="$(cd "$HALT_ROOT" && node "$HW_CLI" next --json 2>"$NEXT_ERR")"
NEXT_EXIT=$?
set -e
if [ "$NEXT_EXIT" -ne 0 ]; then
  echo "STOP: 'next --json' exited $NEXT_EXIT" >&2
  sed 's/^/  next: /' "$NEXT_ERR" >&2 2>/dev/null || true
  rm -f "$NEXT_ERR"; exit 1
fi
rm -f "$NEXT_ERR"

# Decide from next's machine output alone (ADR-005 D5/D6). The python prints exactly one
# of two lines and exits 0 either way (so `set -e` never preempts our own STOP handling):
#   STOP <human reason>
#   OK <id> <model_string> <maxturns> <wallsec> <tools_csv>
# maxturns/wallsec == 0 mean "dimension not declared -> emit no flag" (budget is read,
# never defaulted, D6). tools_csv is comma-joined (D3); next always fills spec.tools.
DECISION="$(
  REQUESTED_ID="$REQUESTED_ID" NEXT_JSON="$NEXT_JSON" python3 <<'PYEOF'
import json, os, re, sys
requested = os.environ["REQUESTED_ID"]
try:
    r = json.loads(os.environ["NEXT_JSON"])
except Exception as e:
    print(f"STOP next --json is not valid JSON: {e}"); sys.exit()
kind = r.get("kind", "")
if kind != "unlocked":
    print(f"STOP kind is {kind!r}, not 'unlocked' (nothing eligible to launch)"); sys.exit()
rid = r.get("id", "")
if rid != requested:
    print(f"STOP resolved id {rid!r} != requested {requested!r} (next is on a different slice)"); sys.exit()
if r.get("eligible_mode_b") is not True:
    print(f"STOP slice {rid} is not Mode-B-eligible (eligible_mode_b != true)"); sys.exit()
spec = r.get("spec")
if not isinstance(spec, dict):
    print(f"STOP resolved plan for {rid} carries no spec object"); sys.exit()
model = spec.get("model")
if not isinstance(model, str) or model == "":
    print(f"STOP spec.model missing or empty for {rid}"); sys.exit()
budget = spec.get("budget") or {}
turns = budget.get("turns")
maxturns = str(turns) if isinstance(turns, int) and turns > 0 else "0"
wc = budget.get("wall_clock")
wallsec = "0"
if isinstance(wc, str):
    m = re.match(r"^(\d+)(m|h)$", wc)
    if m:
        wallsec = str(int(m.group(1)) * (60 if m.group(2) == "m" else 3600))
tools = spec.get("tools")
if not isinstance(tools, list) or not tools or any((not isinstance(t, str) or t == "") for t in tools):
    print(f"STOP spec.tools missing/empty for {rid} (expected a non-empty list from next)"); sys.exit()
print("OK", rid, model, maxturns, wallsec, ",".join(tools))
PYEOF
)"
read -r VERDICT REST <<<"$DECISION"
if [ "$VERDICT" != "OK" ]; then
  echo "$DECISION" >&2
  exit 1
fi
read -r RESOLVED_ID MODEL_STRING MAXTURNS WALLSEC TOOLS <<<"$REST"

# Resolve the opaque model-string to a concrete model, pack-side, via the manifest
# (ADR-005 D4): spec.model -> model_tiers[model] -> tiers[T].chain[0]. Fail-closed: a
# model-string absent from model_tiers is a STOP, never a default tier. The existing
# single-hop-DOWNWARD resolves_to rule (empty chain) is preserved unchanged.
RESOLUTION="$(
  MODEL_STRING="$MODEL_STRING" python3 - "$MANIFEST" <<'PYEOF'
import json, os, sys
m = json.load(open(sys.argv[1]))
model = os.environ["MODEL_STRING"]
model_tiers = m.get("model_tiers") or {}
tiers = m.get("tiers") or {}
if model not in model_tiers:
    print(f"STOP model-string {model!r} absent from manifest.model_tiers (fail-closed; not a default)"); sys.exit()
t = model_tiers[model]
tier = tiers.get(t)
if tier is None:
    print(f"STOP model_tiers[{model!r}] -> {t!r}, not a tier in the manifest"); sys.exit()
if not tier.get("chain"):
    rt = tier.get("resolves_to")
    order = ["T0", "T1", "T2", "T3"]
    if not rt or t not in order or rt not in order or (order.index(rt) - order.index(t)) != 1:
        print(f"STOP tier {t!r} has empty chain and no legal single-hop-downward resolves_to"); sys.exit()
    t = rt
    tier = tiers.get(t) or {}
    if not tier.get("chain"):
        print(f"STOP resolves_to target {t!r} also has empty chain"); sys.exit()
print("OK", t, tier["chain"][0], m.get("manifest_version", ""))
PYEOF
)"
read -r RVERDICT RREST <<<"$RESOLUTION"
if [ "$RVERDICT" != "OK" ]; then
  echo "$RESOLUTION" >&2
  exit 1
fi
read -r TIER_RESOLVED MODEL MVER <<<"$RREST"

# Preview + test affordance: everything above is the real gate path. Stop here before
# touching the constitution or invoking claude, and write nothing.
if [ "${LAUNCH_DRYRUN:-}" = "1" ]; then
  echo "DRYRUN ok id=$RESOLVED_ID model_string=$MODEL_STRING tier=$TIER_RESOLVED model=$MODEL manifest=$MVER max_turns=$MAXTURNS wall_sec=$WALLSEC tools=$TOOLS"
  exit 0
fi

mkdir -p "$RECEIPTS_DIR"

# Constitution hash pin, fail-closed (unchanged).
CHASH="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$CONST")"
EXPECTED_CHASH="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("constitution_hash_expected",""))' "$MANIFEST")"
if [ -n "$EXPECTED_CHASH" ] && [ "$EXPECTED_CHASH" != "$CHASH" ]; then
  echo "STOP: CONST-HASH-MISMATCH expected=$EXPECTED_CHASH actual=$CHASH" >&2
  exit 1
fi

TOOLVER="$(claude --version 2>/dev/null || echo unknown)"
RUN_ID="run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
OUT="$RECEIPTS_DIR/$RUN_ID.cc.json"
echo "spec=$RESOLVED_ID model_string=$MODEL_STRING tier_resolved=$TIER_RESOLVED model=$MODEL manifest=$MVER constitution=$CHASH"

# Budget -> flags (ADR-005 D6): a declared dimension produces its flag; an undeclared
# dimension (sentinel 0) produces NO flag. The old silent 15/20 defaults are gone.
CMD=(claude -p
  --model "$MODEL"
  --append-system-prompt "$(cat "$CONST")"
  --settings "$HARNESS_HOME/templates/settings.mode-b.json"
  --allowedTools "$TOOLS"
  --permission-mode dontAsk
  --output-format json)
if [ "$MAXTURNS" != "0" ]; then CMD+=(--max-turns "$MAXTURNS"); fi
# Wall-clock -> kill after N seconds, prefer gtimeout (coreutils) then timeout.
if [ "$WALLSEC" != "0" ]; then
  if command -v gtimeout >/dev/null; then CMD=(gtimeout "$WALLSEC" "${CMD[@]}")
  elif command -v timeout >/dev/null; then CMD=(timeout "$WALLSEC" "${CMD[@]}")
  fi
fi

set +e
"${CMD[@]}" < "$SPEC" > "$OUT"
CC_EXIT=$?
set -e
ENDED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# NOTE (ADR-004 D7, commit C): the receipt below still hardcodes "claims": [] and the
# run still stops on CC_EXIT alone. Wiring the verity gate into the receipt is the next
# commit; this commit changes only the plan-resolution inputs, not the gate.
python3 - "$OUT" "$RECEIPTS_DIR/$RUN_ID.receipt.json" <<PYEOF
import json, sys
try:
    cc = json.load(open(sys.argv[1]))
except Exception:
    cc = {"subtype": "error_no_output"}
receipt = {
  "run_id": "$RUN_ID", "spec_id": "$RESOLVED_ID", "mode": "B",
  "model_string": "$MODEL_STRING", "tier_resolved": "$TIER_RESOLVED",
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
