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

echo "== D1: canonical receipts dir resolution (ADR-005) =="
TMPD5="$(mktemp -d)"
trap 'rm -rf "$TMPD" "$TMPD2" "$TMPD3" "$TMPD3R" "$TMPD4" "$TMPD4N" "$TMPD5"' EXIT
mkdir -p "$TMPD5/.harness/receipts"
printf '{"run_id":"r1","subtype":"success","num_turns":1}\n' > "$TMPD5/.harness/receipts/r1.receipt.json"
set +e
( cd "$TMPD5" && ROLLUP_THRESHOLD=1 "$PACK/scripts/rollup_due.sh" ) >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "FAIL [rollup_due.sh must default to ./.harness/receipts]: rc=$rc"; fail=1
else
  echo "ok [rollup_due.sh resolves canonical ./.harness/receipts]"
fi
set +e
( cd "$TMPD5" && python3 "$PACK/scripts/harness_stats.py" ) >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ] || ! grep -q "runs: 1" "$TMPD5/.harness/receipts/stats.md" 2>/dev/null; then
  echo "FAIL [harness_stats.py must default to ./.harness/receipts]: rc=$rc"; fail=1
else
  echo "ok [harness_stats.py resolves canonical ./.harness/receipts]"
fi
if grep -Eq 'RECEIPTS_DIR:-\./\.harness/receipts\}' "$PACK/scripts/launch_worker.sh"; then
  echo "ok [launch_worker.sh default is canonical ./.harness/receipts (source-level)]"
else
  echo "FAIL [launch_worker.sh default must be ./.harness/receipts]"; fail=1
fi

echo "== D4: reader tolerates both receipt schema forms (ADR-005) =="
TMPD6="$(mktemp -d)"
trap 'rm -rf "$TMPD" "$TMPD2" "$TMPD3" "$TMPD3R" "$TMPD4" "$TMPD4N" "$TMPD5" "$TMPD6"' EXIT
mkdir -p "$TMPD6/receipts"
printf '{"run_id":"old","spec_id":"S-OLD","tier_requested":"T1","subtype":"success","num_turns":2}\n' > "$TMPD6/receipts/old.receipt.json"
printf '{"run_id":"new","spec_id":"S-NEW","model_string":"executor","tier_resolved":"T2","model_used":"SONNET_CLASS_MODEL","subtype":"success","num_turns":3}\n' > "$TMPD6/receipts/new.receipt.json"
set +e
python3 "$PACK/scripts/harness_stats.py" "$TMPD6/receipts" >/dev/null 2>"$TMPD6/err"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "FAIL [reader must parse both schema forms]: rc=$rc"; cat "$TMPD6/err" 2>/dev/null; fail=1
else
  echo "ok [reader parsed both schema forms]"
fi
if grep -q "<td>T2</td>" "$TMPD6/receipts/dashboard.html" 2>/dev/null && grep -q "<td>T1</td>" "$TMPD6/receipts/dashboard.html" 2>/dev/null; then
  echo "ok [D4 fallback: new->tier_resolved T2, old->tier_requested T1]"
else
  echo "FAIL [D4 fallback: expected T2 (new) and T1 (old) in dashboard]"; fail=1
fi

echo "== D6: union index+loose (dedup + tail ordering, ADR-005 D2/D6) =="
TMPD7="$(mktemp -d)"
trap 'rm -rf "$TMPD" "$TMPD2" "$TMPD3" "$TMPD3R" "$TMPD4" "$TMPD4N" "$TMPD5" "$TMPD6" "$TMPD7"' EXIT
set +e
python3 - "$TMPD7" <<'PY'
import hashlib, json, os, sys
sys.path.insert(0, "scripts")
import harness_stats as hs

rdir = sys.argv[1]

def write(name, content):
    with open(os.path.join(rdir, name), "w") as f:
        f.write(content)

# Loose receipt still present after being rolled up (overlap, sha now diverges).
write("run-A.receipt.json", '{"run_id":"run-A","subtype":"success","num_turns":5}\n')
# Loose receipt still present after being rolled up (overlap, sha matches exactly).
write("run-D.receipt.json", '{"run_id":"run-D","subtype":"success","num_turns":9}\n')
d_sha = hashlib.sha256(open(os.path.join(rdir, "run-D.receipt.json"), "rb").read()).hexdigest()
# Tail: not yet rolled up.
write("run-C.receipt.json", '{"run_id":"run-C","subtype":"success","num_turns":4}\n')

index_lines = [
    {"seq": 1, "run_id": "run-A", "spec_id": "S-A", "subtype": "success",
     "num_turns": 5, "total_cost_usd": 0.2, "source_filename": "run-A.receipt.json",
     "source_sha256": "deadbeef"},
    {"seq": 2, "run_id": "run-B", "spec_id": "S-B", "subtype": "success",
     "num_turns": 7, "total_cost_usd": None, "source_filename": "run-B.receipt.json",
     "source_sha256": "badc0de"},
    {"seq": 3, "run_id": "run-D", "spec_id": "S-D", "subtype": "success",
     "num_turns": 9, "total_cost_usd": 0.3, "source_filename": "run-D.receipt.json",
     "source_sha256": d_sha},
]
with open(os.path.join(rdir, "receipts-index.jsonl"), "w") as f:
    for row in index_lines:
        f.write(json.dumps(row) + "\n")

idx = hs.load_index(rdir)
assert len(idx) == 3, f"load_index: expected 3 rows, got {len(idx)}"

loose = hs.list_loose_receipts(rdir)
names = sorted(n for n, _ in loose)
assert names == ["run-A.receipt.json", "run-C.receipt.json", "run-D.receipt.json"], names

merged = hs.merge_runs(rdir, idx, loose)
assert len(merged) == 4, f"expected 4 (3 index + 1 tail), got {len(merged)}"

by_name = {r["source_filename"]: r for r in merged}
assert by_name["run-A.receipt.json"]["_tail"] is False
assert by_name["run-A.receipt.json"].get("_drift"), "expected a drift note on sha mismatch"
assert by_name["run-D.receipt.json"].get("_drift") is None, "matching sha must not raise a false drift note"
assert by_name["run-B.receipt.json"]["_seq_display"] == 2
assert by_name["run-B.receipt.json"]["_cost_display"] == "—"
assert by_name["run-C.receipt.json"]["_tail"] is True
assert by_name["run-C.receipt.json"]["_seq_display"] == "—"

assert [r["source_filename"] for r in merged] == [
    "run-A.receipt.json", "run-B.receipt.json", "run-D.receipt.json", "run-C.receipt.json"
], "expected index rows in seq order, then tail lexicographic"

print("PASS")
PY
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "FAIL [D6 union index+loose]: rc=$rc"; fail=1
else
  echo "ok [D6: union dedups by source_filename, seq order, tail dash, drift note on sha mismatch]"
fi

echo "== D6: chain status (advisory working-tree + HEAD-anchored, ADR-005 D6) =="
TMPD8="$(mktemp -d)"
trap 'rm -rf "$TMPD" "$TMPD2" "$TMPD3" "$TMPD3R" "$TMPD4" "$TMPD4N" "$TMPD5" "$TMPD6" "$TMPD7" "$TMPD8"' EXIT
printf 'src-a\n' > "$TMPD8/a.receipt.json"
printf 'src-b\n' > "$TMPD8/b.receipt.json"
python3 scripts/receipt_chain.py append --chain "$TMPD8/receipt-chain.jsonl" \
  --run-id run-chain-status "$TMPD8/a.receipt.json" "$TMPD8/b.receipt.json" >/dev/null
set +e
out="$(python3 -c '
import sys
sys.path.insert(0, "scripts")
import harness_stats as hs
r = hs.chain_status(sys.argv[1])
print(r["path_exists"], r["working_tree"], r["head"])
' "$TMPD8")"
rc=$?
set -e
# TMPD8 is a bare mktemp dir with no ancestor git repo, so the chain is
# valid working-tree but has no HEAD anchor: the expected neutral state,
# not a warning (harness-pack's own .harness/ is gitignored the same way).
if [ "$rc" -ne 0 ] || [ "$out" != "True VALID no HEAD anchor" ]; then
  echo "FAIL [chain_status: expected 'True VALID no HEAD anchor']: rc=$rc out=$out"; fail=1
else
  echo "ok [chain_status: working-tree VALID, no-HEAD-anchor renders neutral outside a repo]"
fi
# Absent chain file degrades to unavailable, not an error.
TMPD8B="$(mktemp -d)"
trap 'rm -rf "$TMPD" "$TMPD2" "$TMPD3" "$TMPD3R" "$TMPD4" "$TMPD4N" "$TMPD5" "$TMPD6" "$TMPD7" "$TMPD8" "$TMPD8B"' EXIT
out2="$(python3 -c '
import sys
sys.path.insert(0, "scripts")
import harness_stats as hs
r = hs.chain_status(sys.argv[1])
print(r["path_exists"], r["working_tree"], r["head"])
' "$TMPD8B")"
if [ "$out2" = "False None None" ]; then
  echo "ok [chain_status: missing chain file degrades to unavailable, not an error]"
else
  echo "FAIL [chain_status: expected 'False None None' for missing chain]: $out2"; fail=1
fi

echo "== D6: co-index gate signal (receipts_index.py gate, read-only) =="
TMPD9="$(mktemp -d)"
trap 'rm -rf "$TMPD" "$TMPD2" "$TMPD3" "$TMPD3R" "$TMPD4" "$TMPD4N" "$TMPD5" "$TMPD6" "$TMPD7" "$TMPD8" "$TMPD8B" "$TMPD9"' EXIT
printf '{"x":"a"}' > "$TMPD9/a.receipt.json"
printf '{"x":"b"}' > "$TMPD9/b.receipt.json"
python3 scripts/receipt_chain.py append --chain "$TMPD9/receipt-chain.jsonl" \
  --run-id run-co-index "$TMPD9/a.receipt.json" "$TMPD9/b.receipt.json" >/dev/null
python3 scripts/receipts_index.py append --index "$TMPD9/receipts-index.jsonl" \
  "$TMPD9/a.receipt.json" "$TMPD9/b.receipt.json" >/dev/null
out="$(python3 -c '
import sys
sys.path.insert(0, "scripts")
import harness_stats as hs
print(hs.co_index_status(sys.argv[1])["status"])
' "$TMPD9")"
if [ "$out" = "VALID" ]; then
  echo "ok [co_index_status: VALID on a freshly co-indexed pair]"
else
  echo "FAIL [co_index_status: expected VALID, got $out]"; fail=1
fi
# Mutate the index's recorded sha -- receipts_index.py gate must catch it.
python3 -c '
import json
p = "'"$TMPD9"'/receipts-index.jsonl"
lines = open(p).read().splitlines(keepends=True)
o = json.loads(lines[0]); o["source_sha256"] = "0" * 64
lines[0] = json.dumps(o, sort_keys=True, separators=(",", ":")) + "\n"
open(p, "w").writelines(lines)
'
out2="$(python3 -c '
import sys
sys.path.insert(0, "scripts")
import harness_stats as hs
print(hs.co_index_status(sys.argv[1])["status"])
' "$TMPD9")"
if [ "$out2" = "DRIFT" ]; then
  echo "ok [co_index_status: DRIFT signal on sha mismatch, non-fatal]"
else
  echo "FAIL [co_index_status: expected DRIFT, got $out2]"; fail=1
fi
set +e
python3 scripts/harness_stats.py "$TMPD9" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "FAIL [renderer must stay exit 0 despite co-index drift]: rc=$rc"; fail=1
else
  echo "ok [renderer exit 0 despite co-index drift (collector unwired, degradation-only)]"
fi
# Missing chain or index degrades to unavailable, not an error.
TMPD9B="$(mktemp -d)"
trap 'rm -rf "$TMPD" "$TMPD2" "$TMPD3" "$TMPD3R" "$TMPD4" "$TMPD4N" "$TMPD5" "$TMPD6" "$TMPD7" "$TMPD8" "$TMPD8B" "$TMPD9" "$TMPD9B"' EXIT
out3="$(python3 -c '
import sys
sys.path.insert(0, "scripts")
import harness_stats as hs
print(hs.co_index_status(sys.argv[1])["status"])
' "$TMPD9B")"
if [ "$out3" = "unavailable" ]; then
  echo "ok [co_index_status: missing index+chain degrades to unavailable]"
else
  echo "FAIL [co_index_status: expected unavailable, got $out3]"; fail=1
fi

echo "== receipt_chain selftest =="
python3 scripts/receipt_chain.py selftest || fail=1

echo "== receipts-index co-indexing selftest =="
python3 scripts/receipts_index.py selftest || fail=1

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
