#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
fail=0
# Invariants that were neither upheld nor violated, because the fixture that
# owns them could not attribute the run to the mechanism under test. Distinct
# from `fail` on purpose: an unmeasured invariant accuses nothing, but it must
# not be reported as a pass either. See the parallel-claim section below.
unmeasured=0

# Every scratch dir is templated under $TMPDIR. BSD `mktemp -d` with no
# template ignores $TMPDIR and reaches for the Darwin per-user temp dir, which
# an agent session's sandbox denies -- the suite then halts on its first
# scratch dir and reports nothing. A gate that cannot run is not a gate, so
# the template is mandatory here, not stylistic.

# Every throwaway git repo the suite builds as a fixture is created through
# here, so its isolation from the operator's ~/.gitconfig is one fact in one
# place. Identity was already pinned locally; signing is pinned the same way.
# Without it the fixture inherits commit.gpgsign/user.signingkey from the
# global config and `git commit` dies reaching for a key under ~/.ssh -- the
# suite's verdict then depends on whose machine it runs on.
#
# The isolation is written into the throwaway repo's own .git/config and
# nowhere else: no global config is read or written, no environment is
# overridden for the rest of the suite, and no repo outside $TMPDIR is
# touched. Real harness-pack commits keep signing exactly as before.
init_fixture_repo() {
  git -C "$1" init -q
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name tester
  git -C "$1" config commit.gpgsign false
  git -C "$1" config tag.gpgsign false
}

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
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
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
TMPD2="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
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
TMPD3="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
TMPD3R="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
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
TMPD4="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"    # halted repo: holds .harness/HALT
TMPD4N="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"   # clean repo: no HALT anywhere, for the env-fallback case
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
TMPD5="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
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
TMPD6="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
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
TMPD7="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
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
TMPD8="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
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
TMPD8B="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
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
TMPD9="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
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
TMPD9B="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
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

echo "== D6: repo state (HALT banner + git log, ADR-005 D6) =="
TMPD10="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
trap 'rm -rf "$TMPD" "$TMPD2" "$TMPD3" "$TMPD3R" "$TMPD4" "$TMPD4N" "$TMPD5" "$TMPD6" "$TMPD7" "$TMPD8" "$TMPD8B" "$TMPD9" "$TMPD9B" "$TMPD10"' EXIT
# A real (throwaway) git repo so git_ops has commits to show and
# repo_root() resolves a real toplevel.
init_fixture_repo "$TMPD10"
( cd "$TMPD10" && touch keep && git add -- keep \
    && git commit -q -m "fixture: seed commit" )
mkdir -p "$TMPD10/.harness"
touch "$TMPD10/.harness/HALT"
out="$(python3 -c '
import sys
sys.path.insert(0, "scripts")
import harness_stats as hs
root = hs.repo_root(sys.argv[1])
h = hs.halt(root)
g = hs.git_ops(root)
print(h["status"], h.get("mtime") is not None, g["status"], len(g.get("lines", [])) >= 1)
' "$TMPD10")"
if [ "$out" = "engaged True ok True" ]; then
  echo "ok [repo state: HALT engaged with mtime, git log returns commits]"
else
  echo "FAIL [repo state engaged case]: $out"; fail=1
fi
rm -f "$TMPD10/.harness/HALT"
out2="$(python3 -c '
import sys
sys.path.insert(0, "scripts")
import harness_stats as hs
root = hs.repo_root(sys.argv[1])
print(hs.halt(root)["status"])
' "$TMPD10")"
if [ "$out2" = "clear" ]; then
  echo "ok [repo state: HALT lifted renders clear]"
else
  echo "FAIL [repo state: expected clear, got $out2]"; fail=1
fi
# A bare, non-git temp dir: both collectors degrade to unavailable, no raise.
TMPD10B="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
trap 'rm -rf "$TMPD" "$TMPD2" "$TMPD3" "$TMPD3R" "$TMPD4" "$TMPD4N" "$TMPD5" "$TMPD6" "$TMPD7" "$TMPD8" "$TMPD8B" "$TMPD9" "$TMPD9B" "$TMPD10" "$TMPD10B"' EXIT
out3="$(python3 -c '
import sys
sys.path.insert(0, "scripts")
import harness_stats as hs
root = hs.repo_root(sys.argv[1])
print(root, hs.halt(root)["status"], hs.git_ops(root)["status"])
' "$TMPD10B")"
if [ "$out3" = "None unavailable unavailable" ]; then
  echo "ok [repo state: outside a git repo, HALT and git log both degrade to unavailable]"
else
  echo "FAIL [repo state: expected 'None unavailable unavailable', got $out3]"; fail=1
fi

echo "== D6: external tools (next --json defensive, detect_tamper states, ADR-005 D6) =="
TMPD11="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
trap 'rm -rf "$TMPD" "$TMPD2" "$TMPD3" "$TMPD3R" "$TMPD4" "$TMPD4N" "$TMPD5" "$TMPD6" "$TMPD7" "$TMPD8" "$TMPD8B" "$TMPD9" "$TMPD9B" "$TMPD10" "$TMPD10B" "$TMPD11"' EXIT
# Pin the environment for determinism: this machine has a real /opt/harness
# and may have HARNESSWRIGHT_CLI exported, either of which would make this
# test depend on live deploy/tool state instead of the collector's logic.
out="$(HARNESSWRIGHT_CLI=/nonexistent/hw python3 -c '
import sys
sys.path.insert(0, "scripts")
import harness_stats as hs
print(hs.next_slice(sys.argv[1])["status"])
' "$TMPD11")"
if [ "$out" = "unavailable" ]; then
  echo "ok [next_slice: unresolvable harnesswright CLI degrades to unavailable]"
else
  echo "FAIL [next_slice: expected unavailable, got $out]"; fail=1
fi
out2="$(ENFORCED="$TMPD11/no-such-enforced-root" python3 -c '
import sys
sys.path.insert(0, "scripts")
import harness_stats as hs
print(hs.tamper()["status"])
')"
if [ "$out2" = "not-deployed" ]; then
  echo "ok [tamper: absent enforced root renders not-deployed (neutral), not diverges]"
else
  echo "FAIL [tamper: expected not-deployed, got $out2]"; fail=1
fi
# A present-but-empty enforced root (manifest missing) must ALSO render
# not-deployed, never diverges -- detect_tamper.sh's own distinction.
mkdir -p "$TMPD11/empty-enforced"
out3="$(ENFORCED="$TMPD11/empty-enforced" python3 -c '
import sys
sys.path.insert(0, "scripts")
import harness_stats as hs
r = hs.tamper()
print(r["status"], "manifest missing or empty" in r.get("detail", ""))
')"
if [ "$out3" = "not-deployed True" ]; then
  echo "ok [tamper: missing manifest under an existing enforced root also renders not-deployed]"
else
  echo "FAIL [tamper: expected 'not-deployed True', got $out3]"; fail=1
fi

echo "== D7: mission-control render (ADR-005 D6/D7) =="
TMPD12="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
trap 'rm -rf "$TMPD" "$TMPD2" "$TMPD3" "$TMPD3R" "$TMPD4" "$TMPD4N" "$TMPD5" "$TMPD6" "$TMPD7" "$TMPD8" "$TMPD8B" "$TMPD9" "$TMPD9B" "$TMPD10" "$TMPD10B" "$TMPD11" "$TMPD12"' EXIT
mkdir -p "$TMPD12/receipts"
# A full board: two run receipts and one JSON non-receipt source (a
# valid JSON dict with no run fields, so the five distilled run fields
# are all null -> a source-only row), co-indexed into chain + index.
# Env pinned as in the D6 external-tools block: this machine has a real
# /opt/harness and the render must not depend on live deploy state.
printf '{"run_id":"run-a","spec_id":"S-A","model_string":"executor","tier_resolved":"T2","model_used":"SONNET_CLASS_MODEL","subtype":"success","num_turns":3,"total_cost_usd":0.178,"constitution_hash":"c1","started_at":"t1","gate_verdict":"PASS"}\n' > "$TMPD12/receipts/run-a.receipt.json"
printf '{"run_id":"run-b","spec_id":"S-B","tier_requested":"T1","subtype":"success","num_turns":2,"constitution_hash":"c2","started_at":"t2"}\n' > "$TMPD12/receipts/run-b.receipt.json"
printf '{"report":"rollup summary artifact"}\n' > "$TMPD12/receipts/rollup-report.json"
# Only run-a and the report are rolled up. run-b stays a loose tail on
# purpose: distill() does not carry tier_requested (ADR-005 D2), so an
# old-form receipt keeps its T1 tier only while it is still loose --
# the bare-td assertion below depends on that.
python3 scripts/receipt_chain.py append --chain "$TMPD12/receipts/receipt-chain.jsonl" \
  --run-id run-d7 "$TMPD12/receipts/run-a.receipt.json" \
  "$TMPD12/receipts/rollup-report.json" >/dev/null
python3 scripts/receipts_index.py append --index "$TMPD12/receipts/receipts-index.jsonl" \
  "$TMPD12/receipts/run-a.receipt.json" \
  "$TMPD12/receipts/rollup-report.json" >/dev/null
# The report rolls away; run-a stays loose (overlap, no drift);
# run-t arrives after the rollup (tail row, seq dash).
rm "$TMPD12/receipts/rollup-report.json"
printf '{"run_id":"run-t","spec_id":"S-T","model_string":"executor","tier_resolved":"T2","subtype":"error_max_turns","num_turns":14,"constitution_hash":"c3","started_at":"t3"}\n' > "$TMPD12/receipts/run-t.receipt.json"
set +e
HARNESSWRIGHT_CLI=/nonexistent/hw ENFORCED="$TMPD12/none" \
  python3 scripts/harness_stats.py "$TMPD12/receipts" >/dev/null 2>&1
rc=$?
set -e
DASH="$TMPD12/receipts/dashboard.html"
if [ "$rc" -eq 0 ] && [ -s "$DASH" ]; then
  echo "ok [D7: full-board render exits 0]"
else
  echo "FAIL [D7: render rc=$rc or dashboard missing]"; fail=1
fi
if grep -q "<td>T2</td>" "$DASH" && grep -q "<td>T1</td>" "$DASH"; then
  echo "ok [D7: tier column stays a bare td under the full render]"
else
  echo "FAIL [D7: bare-td tier literals lost]"; fail=1
fi
if grep -q 'data-rail="halt"' "$DASH" && grep -q 'data-rail="chain"' "$DASH" \
   && grep -q 'data-rail="tree"' "$DASH" && grep -q 'data-rail="gate"' "$DASH" \
   && grep -q 'data-rail="slice"' "$DASH"; then
  echo "ok [D7: five-cell status rail present]"
else
  echo "FAIL [D7: status rail incomplete]"; fail=1
fi
# The source-only row renders as a non-run source, never as a failed
# run (ledger rows are newline-separated, so the check is per-row).
srcline="$(grep 'non-run source' "$DASH" || true)"
if [ -n "$srcline" ] && ! printf '%s' "$srcline" | grep -q 'NOT-SUCCESS'; then
  echo "ok [D7: source-only row rendered as non-run source, unflagged]"
else
  echo "FAIL [D7: source-only row missing or wrongly flagged]"; fail=1
fi
if ! grep -q '>None<' "$DASH"; then
  echo "ok [D7: null fields render as a dash, never None]"
else
  echo "FAIL [D7: literal None leaked into the dashboard]"; fail=1
fi
if ! grep -qF "$TMPD12" "$DASH"; then
  echo "ok [D7: no absolute fixture path leaks into the dashboard]"
else
  echo "FAIL [D7: absolute path leaked into the dashboard]"; fail=1
fi
if grep -q "^runs: " "$TMPD12/receipts/stats.md" \
   && grep -q "^## Chain" "$TMPD12/receipts/stats.md"; then
  echo "ok [D7: stats.md keeps its header line and gains detail sections]"
else
  echo "FAIL [D7: stats.md header/sections wrong]"; fail=1
fi
# HALT banner: engaged in a real repo renders the banner; lifted, gone.
TMPD12B="$(mktemp -d "${TMPDIR:-/tmp}/hp-test.XXXXXX")"
trap 'rm -rf "$TMPD" "$TMPD2" "$TMPD3" "$TMPD3R" "$TMPD4" "$TMPD4N" "$TMPD5" "$TMPD6" "$TMPD7" "$TMPD8" "$TMPD8B" "$TMPD9" "$TMPD9B" "$TMPD10" "$TMPD10B" "$TMPD11" "$TMPD12" "$TMPD12B"' EXIT
init_fixture_repo "$TMPD12B"
mkdir -p "$TMPD12B/.harness/receipts"
printf '{"run_id":"h1","subtype":"success","num_turns":1}\n' > "$TMPD12B/.harness/receipts/h1.receipt.json"
touch "$TMPD12B/.harness/HALT"
set +e
( cd "$TMPD12B" && HARNESSWRIGHT_CLI=/nonexistent/hw ENFORCED="$TMPD12B/none" \
    python3 "$PACK/scripts/harness_stats.py" ) >/dev/null 2>&1
rc=$?
set -e
BOARD="$TMPD12B/.harness/receipts/dashboard.html"
if [ "$rc" -eq 0 ] && grep -q '<div class="halt-banner"' "$BOARD"; then
  echo "ok [D7: HALT engaged renders the banner]"
else
  echo "FAIL [D7: HALT banner missing while engaged]: rc=$rc"; fail=1
fi
rm -f "$TMPD12B/.harness/HALT"
set +e
( cd "$TMPD12B" && HARNESSWRIGHT_CLI=/nonexistent/hw ENFORCED="$TMPD12B/none" \
    python3 "$PACK/scripts/harness_stats.py" ) >/dev/null 2>&1
rc=$?
set -e
# The grep targets the banner div, not the bare class name: the CSS
# block defines .halt-banner on every page, banner present or not.
if [ "$rc" -eq 0 ] && ! grep -q '<div class="halt-banner"' "$BOARD"; then
  echo "ok [D7: HALT lifted removes the banner]"
else
  echo "FAIL [D7: banner persisted after HALT lift]: rc=$rc"; fail=1
fi

echo "== receipt_chain selftest =="
python3 scripts/receipt_chain.py selftest || fail=1

echo "== receipts-index co-indexing selftest =="
python3 scripts/receipts_index.py selftest || fail=1

echo "== spec lint =="
python3 scripts/lint_specs.py || fail=1

echo "== parallel claim isolation (vault ADR-054 D3) =="
# Races real processes rather than reading code. Both directions are asserted every
# run: the lease must admit exactly one claimer, and the mechanism it replaced must
# still admit all of them. A gate never seen failing is not a gate, so the falsifier
# stays wired in rather than being described in a comment.
#
# The fixture has three outcomes, not two, and this is where the third one is
# kept from passing quietly. Exit 2 means it could not attribute a run to the
# mechanism -- a wall-clock budget was exceeded -- so the invariant went
# unmeasured. That is not a failure of the lease and is not reported as one, but
# it is also not a pass: it is counted here and it stops the suite from printing
# ALL TESTS PASSED at the end. See the fixture's header for the two budgets.
set +e
bash tests/parallel_claim_fixture.sh --mode lease
rc=$?
set -e
case "$rc" in
  0) ;;
  2) unmeasured=$((unmeasured + 1))
     echo "unattrib [parallel claim, lease mode]: the isolation invariants went unmeasured this run (above); not a pass, not a fail" ;;
  *) fail=1 ;;
esac
set +e
bash tests/parallel_claim_fixture.sh --mode legacy >/dev/null 2>&1
rc=$?
set -e
case "$rc" in
  0) echo "FAIL [legacy claimer must stay red]: presence-check-only admitted one claimer"; fail=1 ;;
  2) unmeasured=$((unmeasured + 1))
     echo "unattrib [legacy claimer]: the fixture could not attribute the legacy run, so its red was not re-observed" ;;
  *) echo "ok [legacy claimer still red: presence-check-only admits every claimer]" ;;
esac

echo "== lease acquire window: the take is atomic (vault ADR-054 D3) =="
# One row, registered RED before the take was repaired and asserted GREEN since,
# re-observed on every run for the same reason the legacy claimer above is: a
# defect closed in a commit message and asserted nowhere is a defect that can be
# silently reintroduced. scripts/slice_lease.py declares at :13-15 that its take
# is one syscall with one winner, and now earns it: the record is written under a
# staging name and published with a single link(), so the lock name never exists
# as a zero-byte file that the module would classify as stale and take from a
# live holder. The fixture reconstructs that window with a held descriptor --
# no race, no sleeps, no concurrency -- so its verdict does not depend on load.
#
# --expect-red is gone from this call, not from the fixture: the row now stands
# green on the fixture's own criterion, and the plain call is what holds it
# there. Reopen the window and this line goes red again, which is its whole job.
bash tests/lease_window_fixture.sh || fail=1

echo "== lease expiry ordering: a lease is dated no earlier than the attempt that took it (vault ADR-054 D3) =="
# The second defect of the same acquire path, registered RED before the dating
# was repaired and asserted GREEN since. cmd_acquire read the clock once, before
# the retry loop, so a claimer that broke a stale lock and retried published a
# lease stamped from before the contention it won -- its TTL already being spent
# when the lease was created. The read is now inside the loop, so every attempt
# dates its own record and a lease is dated no earlier than the attempt that took
# it; scripts/slice_lease.py says so at WHEN A LEASE IS DATED and this row is what
# holds it to that.
#
# The row is an ORDERING, not a duration. The fixture hands the predecessor's
# record to the claimer at the claimer's own _read(), through a FIFO at the
# lock's name, so the kernel enforces both orderings the verdict rests on: it
# waits on no interval, sleeps for no duration, and has no third outcome to
# count. Its verdict cannot move with load.
#
# --expect-red is gone from this call, not from the fixture: the row now stands
# green on the fixture's own criterion, and the plain call is what holds it
# there. Move that clock read back out of the loop and this line goes red again,
# which is its whole job.
bash tests/lease_expiry_fixture.sh || fail=1

echo "== ADR-008 falsifier register: six rows in their declared state (harnesswright ADR-008:139) =="
# Six rows of an Accepted ADR's falsifier register. The register is normative --
# "each row must be seen red before the decision it belongs to is implemented"
# -- so the reds are re-observed on every run here rather than being recounted
# in a commit message.
#
# --expect-registered no longer describes a posture the whole register shares.
# ADR-008 lands one decision at a time, and from the D repair on the register is
# mixed: D2's unknown-baseline row is green because the launcher now measures t0
# before the spawn, while D6 and D3 are still red because the schema is
# untouched. Neither an all-red mode nor an all-green one describes that tree.
# The expected state is therefore DECLARED PER ROW, as six literals in the
# fixture beside the register lines they answer to, and this call asserts that
# every row is where its own literal says it is.
#
# What that buys, and it is the point: the only way to make this line green
# again after a row moves is to edit THAT ROW's literal, in the commit that
# moved it, with the reason beside it. Changing a global mode so the suite goes
# green is the defect ADR-009 exists to prevent, and there is no longer a global
# mode to change.
bash tests/adr008_falsifier_fixture.sh --expect-registered || fail=1

echo "== ADR-008 discrimination control: the D1 and D2 rows can move =="
# The line above re-observes two reds. This one answers the question that makes
# those reds worth anything: could either row ever say GREEN? A falsifier that
# cannot is wired red rather than measuring, and its red is evidence of nothing.
#
# --discriminate hands each row the artifact it demands, fabricated under
# $TMPDIR -- the contribution verdict the launcher does not write, and a run in
# which the executor was never spawned -- and requires GREEN; then hands it an
# artifact without that thing and requires RED. Both directions, because an
# assertion that always says GREEN discriminates no better than one that always
# says RED. It runs the same assertion code the register rows run, not a copy.
#
# It asserts on fabricated inputs, so it says nothing about the launcher and
# does not become green when D1 or D2 lands -- unlike the line above, this one
# is not flipped by the implementer. It stays exactly as it is through the
# repair, which is when a silently-broken falsifier would do the most damage.
bash tests/adr008_falsifier_fixture.sh --discriminate || fail=1

echo "== session transcript renderer =="
# Pins the two properties that make the renderer trustworthy to watch a live
# run: it survives a ragged JSONL tail, and it never renders a blocked action
# as successful work.
bash tests/render_session_fixture.sh || fail=1

echo "== shellcheck (local, optional) =="
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh tests/*.sh || fail=1
else
  echo "shellcheck not installed locally; CI enforces it"
fi

echo "== compile check =="
python3 -m py_compile scripts/*.py || fail=1

# Three verdicts, because the suite now has a fixture with three outcomes. A
# violation outranks an unmeasured invariant. An unmeasured invariant does NOT
# print ALL TESTS PASSED and does NOT exit 0: the whole point of the third state
# is that it cannot be a quiet pass, and a caller that gates on the documented
# string or on the exit code sees the difference either way. Exit 2 says nothing
# was broken and something was not looked at; exit 1 says something was broken.
if [ "$fail" -ne 0 ]; then
  echo "TESTS FAILED"
  exit 1
fi
if [ "$unmeasured" -ne 0 ]; then
  echo "TESTS INCONCLUSIVE: nothing failed, $unmeasured invariant(s) went unmeasured (see the unattrib lines above); re-run on an unloaded machine"
  exit 2
fi
echo "ALL TESTS PASSED"
exit 0
