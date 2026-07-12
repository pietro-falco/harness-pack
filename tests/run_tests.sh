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

echo "== single-hop tier resolution fixture (D8b) =="
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
cat > "$TMPD/manifest.json" <<'JSON'
{
  "manifest_version": 1,
  "tiers": {
    "T0": { "name": "judgment-authoring", "chain": [], "resolves_to": "T3" },
    "T1": { "name": "trust-anchor", "chain": ["OPUS_CLASS_MODEL"] },
    "T2": { "name": "execution", "chain": ["SONNET_CLASS_MODEL"] },
    "T3": { "name": "subagent", "chain": ["HAIKU_CLASS_MODEL"] }
  }
}
JSON
cat > "$TMPD/spec.md" <<'SPEC'
---
id: FIXTURE-T0-T3
tier: T0
mode: B
---
SPEC
set +e
HARNESS_MANIFEST="$TMPD/manifest.json" RECEIPTS_DIR="$TMPD/receipts" \
  scripts/launch_worker.sh "$TMPD/spec.md" >/dev/null 2>"$TMPD/err"
rc=$?
set -e
if [ "$rc" -eq 0 ] || ! grep -q "illegal resolves_to" "$TMPD/err"; then
  echo "FAIL [single-hop T0->T3 must be refused]: rc=$rc"; fail=1
else
  echo "ok [single-hop T0->T3 refused]: rc=$rc"
fi

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
