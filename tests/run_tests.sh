#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
fail=0

echo "== guard fixtures =="
while IFS= read -r line; do
  [ -n "$line" ] || continue
  cmd=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["command"])')
  exp=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["expect"])')
  set +e
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
    | python3 scripts/guard_pretooluse.py 2>/dev/null
  rc=$?
  set -e
  want=0; [ "$exp" = "block" ] && want=2
  if [ "$rc" -ne "$want" ]; then
    echo "FAIL [$exp got rc=$rc]: $cmd"; fail=1
  else
    echo "ok [$exp]: $cmd"
  fi
done < tests/guard_cases.jsonl

echo "== single-hop tier resolution unit (D8b, ADR-002) =="
# Assert on the extracted unit directly (scripts/launch_checks.py resolve-tier) — the
# same code the launcher runs — with no next/CLI/git dependency. Illegal hop refused,
# legal single-hop-down resolves (so the extraction is not hardcoded to fail).
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
# Illegal hop: T0 has an empty chain and resolves_to T3 (three tiers down, not one).
cat > "$TMPD/manifest-illegal.json" <<'JSON'
{
  "manifest_version": 1,
  "model_tiers": { "JUDGMENT_MODEL": "T0" },
  "tiers": {
    "T0": { "name": "judgment-authoring", "chain": [], "resolves_to": "T3" },
    "T1": { "name": "trust-anchor", "chain": ["OPUS_CLASS_MODEL"] },
    "T2": { "name": "execution", "chain": ["SONNET_CLASS_MODEL"] },
    "T3": { "name": "subagent", "chain": ["HAIKU_CLASS_MODEL"] }
  }
}
JSON
set +e
MODEL_STRING="JUDGMENT_MODEL" python3 scripts/launch_checks.py resolve-tier "$TMPD/manifest-illegal.json" \
  >/dev/null 2>"$TMPD/err"
rc=$?
set -e
if [ "$rc" -eq 0 ] || ! grep -q "no legal single-hop-downward resolves_to" "$TMPD/err"; then
  echo "FAIL [single-hop T0->T3 must be refused]: rc=$rc"; fail=1
else
  echo "ok [single-hop T0->T3 refused]: rc=$rc"
fi
# Positive companion: a legal single hop down (T0->T1) resolves to T1's model.
cat > "$TMPD/manifest-legal.json" <<'JSON'
{
  "manifest_version": 1,
  "model_tiers": { "JUDGMENT_MODEL": "T0" },
  "tiers": {
    "T0": { "name": "judgment-authoring", "chain": [], "resolves_to": "T1" },
    "T1": { "name": "trust-anchor", "chain": ["OPUS_CLASS_MODEL"] },
    "T2": { "name": "execution", "chain": ["SONNET_CLASS_MODEL"] },
    "T3": { "name": "subagent", "chain": ["HAIKU_CLASS_MODEL"] }
  }
}
JSON
set +e
legal_out="$(MODEL_STRING="JUDGMENT_MODEL" python3 scripts/launch_checks.py resolve-tier "$TMPD/manifest-legal.json" 2>/dev/null)"
rc=$?
set -e
if [ "$rc" -ne 0 ] || [ "$legal_out" != "OK T1 OPUS_CLASS_MODEL 1" ]; then
  echo "FAIL [single-hop T0->T1 must resolve]: rc=$rc out=$legal_out"; fail=1
else
  echo "ok [single-hop T0->T1 resolves]: $legal_out"
fi

echo "== constitution hash pinning unit (ADR-002) =="
# Assert on the extracted unit directly (scripts/launch_checks.py check-hash): wrong
# expected hash refused, matching hash passes and echoes the computed digest.
TMPD2="$(mktemp -d)"
trap 'rm -rf "$TMPD" "$TMPD2"' EXIT
printf 'constitution body\n' > "$TMPD2/CONSTITUTION.md"
# Wrong expected hash -> fail-closed refusal.
cat > "$TMPD2/manifest-wrong.json" <<'JSON'
{
  "manifest_version": 1,
  "constitution_hash_expected": "0000000000000000000000000000000000000000000000000000000000000000"
}
JSON
set +e
python3 scripts/launch_checks.py check-hash "$TMPD2/CONSTITUTION.md" "$TMPD2/manifest-wrong.json" \
  >/dev/null 2>"$TMPD2/err"
rc=$?
set -e
if [ "$rc" -eq 0 ] || ! grep -q "CONST-HASH-MISMATCH" "$TMPD2/err"; then
  echo "FAIL [wrong constitution_hash_expected must be refused]: rc=$rc"; fail=1
else
  echo "ok [constitution hash mismatch refused]: rc=$rc"
fi
# Positive companion: the matching expected hash passes and echoes the digest.
actual_chash="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$TMPD2/CONSTITUTION.md")"
cat > "$TMPD2/manifest-right.json" <<JSON
{
  "manifest_version": 1,
  "constitution_hash_expected": "$actual_chash"
}
JSON
set +e
right_out="$(python3 scripts/launch_checks.py check-hash "$TMPD2/CONSTITUTION.md" "$TMPD2/manifest-right.json" 2>/dev/null)"
rc=$?
set -e
if [ "$rc" -ne 0 ] || [ "$right_out" != "$actual_chash" ]; then
  echo "FAIL [correct constitution_hash_expected must pass]: rc=$rc"; fail=1
else
  echo "ok [constitution hash match passes]: rc=$rc"
fi

echo "== HALT kill-switch in target repo refuses launch =="
TMPD3="$(mktemp -d)"
TMPD3R="$(mktemp -d)"
trap 'rm -rf "$TMPD" "$TMPD2" "$TMPD3" "$TMPD3R"' EXIT
PACK="$PWD"
mkdir -p "$TMPD3/.harness"
touch "$TMPD3/.harness/HALT"
printf -- '---\nid: FIXTURE-HALT\ntier: T1\nmode: B\n---\n' > "$TMPD3/spec.md"
set +e
( cd "$TMPD3" && RECEIPTS_DIR="$TMPD3R/receipts" \
    "$PACK/scripts/launch_worker.sh" "$TMPD3/spec.md" ) >/dev/null 2>"$TMPD3/err"
rc=$?
set -e
rm -f "$TMPD3/.harness/HALT"
if [ "$rc" -eq 0 ] || ! grep -q "HALT file present" "$TMPD3/err"; then
  echo "FAIL [HALT in target repo must refuse launch regardless of RECEIPTS_DIR]: rc=$rc"; fail=1
else
  echo "ok [HALT in target repo refused launch, RECEIPTS_DIR overridden]: rc=$rc"
fi

echo "== HALT kill-switch neutralises a run in flight (guard, all tools) =="
TMPD4="$(mktemp -d)"    # halted repo: holds .harness/HALT
TMPD4N="$(mktemp -d)"   # clean repo: no HALT anywhere, for the env-fallback case
trap 'rm -rf "$TMPD" "$TMPD2" "$TMPD3" "$TMPD3R" "$TMPD4" "$TMPD4N"' EXIT
mkdir -p "$TMPD4/.harness" "$TMPD4/a/b"
touch "$TMPD4/.harness/HALT"
halt_case() {  # $1=label  $2=hook payload  $3=want rc;  env: CPD -> CLAUDE_PROJECT_DIR
  set +e
  printf '%s' "$2" \
    | CLAUDE_PROJECT_DIR="${CPD:-}" python3 scripts/guard_pretooluse.py 2>/dev/null
  rc=$?
  set -e
  if [ "$rc" -ne "$3" ]; then
    echo "FAIL [$1: want rc=$3 got rc=$rc]"; fail=1
  else
    echo "ok [$1]: rc=$rc"
  fi
}
CPD=""
halt_case "HALT blocks Edit" \
  "$(printf '{"tool_name":"Edit","cwd":"%s"}' "$TMPD4")" 2
halt_case "HALT blocks benign Bash" \
  "$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"%s"}' "$TMPD4")" 2
halt_case "HALT blocks from a deep subdir (no bypass by cd)" \
  "$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"%s/a/b"}' "$TMPD4")" 2
CPD="$TMPD4"
halt_case "HALT found via CLAUDE_PROJECT_DIR when payload cwd is clean" \
  "$(printf '{"tool_name":"Edit","cwd":"%s"}' "$TMPD4N")" 2
CPD=""
rm -f "$TMPD4/.harness/HALT"
halt_case "HALT lifted: benign Bash allowed" \
  "$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"%s"}' "$TMPD4")" 0

echo "== receipt_chain selftest =="
python3 scripts/receipt_chain.py selftest || fail=1

echo "== spec lint =="
python3 scripts/lint_specs.py || fail=1

echo "== shellcheck (local, optional) =="
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh tests/*.sh || fail=1
else
  echo "shellcheck not installed locally; CI enforces it"
fi

echo "== compile check =="
python3 -m py_compile scripts/*.py || fail=1

[ "$fail" -eq 0 ] && echo "ALL TESTS PASSED" || echo "TESTS FAILED"
exit "$fail"
