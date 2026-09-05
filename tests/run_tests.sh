#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
fail=0
# Invariants that were neither upheld nor violated, because the fixture that
# owns them could not attribute the run to the mechanism under test. Distinct
# from `fail` on purpose: an unmeasured invariant accuses nothing, but it must
# not be reported as a pass either. See the parallel-claim section below.
# Recorded BY NAME, never counted: the register at the tail declares which
# names this tree expects, and the comparison there is what decides the exit
# code. A total cannot say WHICH, so it cannot tell today's set from a
# different set of the same size.
unmeasured_observed=""
record_unmeasured() { unmeasured_observed="$(printf '%s\n%s' "$unmeasured_observed" "$1")"; }

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
  2) record_unmeasured parallel_claim_lease
     echo "unattrib [parallel claim, lease mode]: the isolation invariants went unmeasured this run (above); not a pass, not a fail" ;;
  *) fail=1 ;;
esac
set +e
bash tests/parallel_claim_fixture.sh --mode legacy >/dev/null 2>&1
rc=$?
set -e
case "$rc" in
  0) echo "FAIL [legacy claimer must stay red]: presence-check-only admitted one claimer"; fail=1 ;;
  2) record_unmeasured parallel_claim_legacy
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

echo "== ADR-010 D3(a): t0 and t1 share one filter (harnesswright ADR-008:51, :59) =="
# Not a register row -- none of ADR-008's seven names it. It is this repo's
# assertion discharging the obligation ADR-010 D3(a) records against 0008:59:
# "the implementation slice ... **asserts** the shared filter path rather than
# documenting it".
#
# What 0008:51 wants asserted is not a shape but a consequence: "t0 and t1 are
# commensurable by construction or they are not commensurable at all". A grep
# counting definitions cannot see that -- a rewrite duplicating the reduction
# under the same name would pass it unchanged -- so the fixture builds a run on
# which two independently written filters WOULD diverge (a declared criterion
# absent from verity's report, a declared one reported non-PASS, a reported one
# nobody declared) and requires that t0 and t1 do not.
#
# Both halves in one run, as D1's arm does. Red first, against copies of
# scripts/ under $TMPDIR whose t1 phase alone is routed through a drifted
# reduction -- one reading ABSENT as PASS, one skipping the reduction to
# spec.criteria; then green against the launcher in tree. scripts/ is read and
# never written. The red is built from the working tree rather than from history,
# so this line needs no history and survives a --depth 1 clone.
bash tests/adr008_falsifier_fixture.sh --shared-filter || fail=1

echo "== harness-pack ADR-010: a refusal is visible in the receipt (two rows) =="
# Not the ADR-010 named directly above -- that line discharges an obligation of
# harnesswright's ADR-010 against 0008:59. This one is THIS repo's
# docs/adrs/ADR-010-refusals-are-invisible-in-the-receipt.md, and it runs the two
# rows that ADR's Verification table declares.
#
# A plain call, not --expect-red: both rows stand green on the writer in tree as
# of the commit that added them. Their red is not recounted here because it was
# observed and committed literally, under
# .verity/evidence/2026-08-10-adr010-first-red/ -- including the arm that measures
# the defect against the UNCHANGED inline writer at the pre-repair basis, so the
# red cannot be read as an artifact of the extraction that made the writer
# invocable.
#
# The fixture has three outcomes and exits 2 on the third, which is the control
# row's pre-change posture (ADR-010:181-184 declares that row cannot be red
# before the change). Reaching that state again would mean the refusals object
# had disappeared from the writer's output entirely; it is routed to `unmeasured`
# rather than to `fail` so the suite says nothing was measured instead of
# accusing the writer of a defect it would not have described.
bash tests/adr010_refusal_fixture.sh
adr010_rc=$?
if [ "$adr010_rc" -eq 2 ]; then
  record_unmeasured adr010_refusal
elif [ "$adr010_rc" -ne 0 ]; then
  fail=1
fi

echo "== session transcript renderer =="
# Pins the two properties that make the renderer trustworthy to watch a live
# run: it survives a ragged JSONL tail, and it never renders a blocked action
# as successful work.
bash tests/render_session_fixture.sh || fail=1

# A FLAT row, not the three-state form the rows above use, and that is a
# property of the fixture rather than a relaxation of the gate. Every case it
# registers is measurable in every environment by construction: the agent family
# is driven by a stub ssh-add on $PATH, not by a socket a sandbox may refuse to
# let ssh-agent bind, and the one arm that does need a live agent is opt-in and
# off. Nothing is added to UNMEASURED_REGISTER either: that register compares in
# both directions, so a row whose measurability depends on the environment reads
# stale on the shell where it measures and inconclusive on the shell where it
# does not.
echo "== gate preamble: GREEN/RED/UNMEASURED per le ragioni che dichiara (THR-GATE-2 1b-C) =="
bash tests/gate_preamble_fixture.sh || fail=1

# FLAT for the same reason as the row above, and it is the fixture's own
# property again rather than a relaxation: every mutant is a copy the arm writes
# under $TMPDIR and drives through GATE_PREAMBLE, and the child runs are the
# cases above with the real-agent arm forced off. Nothing here can be refused by
# an environment, so there is no third state to register.
echo "== gate preamble: ogni mutante muore, e per il caso che lo dichiara (THR-GATE-2 1b-D) =="
bash tests/gate_preamble_fixture.sh --mutants || fail=1

# FLAT for the same reason as the two rows above, and it is this fixture's own
# property rather than a relaxation of the gate: every case it registers is
# measurable in every environment by construction. The scenario is a throwaway
# git repository this fixture builds under $TMPDIR with identity and signing
# pinned into that repository's own .git/config, and no linter, no network and
# no agent is invoked anywhere in it. Nothing can be refused by an environment,
# so there is no third state and nothing is added to UNMEASURED_REGISTER.
#
# A comment line in this file must not OPEN with a linter directive keyword.
# This file sits inside the surface it lints, so a line whose first word after
# '#' is the linter's own name is parsed as a directive and not as prose.
# Measured on 2026-08-28: SC1073 and SC1072, error-level, on the line that
# listed the two linters this fixture does not call -- a sentence about the gate
# that broke the gate.
echo "== ADR contract gate: an ADR addition must ride with measured work (THR-ADRGATE 4a) =="
bash tests/gate_adr_contract_fixture.sh || fail=1

# Same FLAT reading: every mutant is a copy the arm writes under $TMPDIR and
# drives through ADR_GATE_BIN, and each dies for the single case that declares
# it. A mutation that changes nothing is itself a failure here.
echo "== ADR contract gate: ogni mutante muore, e per il caso che lo dichiara (THR-ADRGATE 4a) =="
bash tests/gate_adr_contract_fixture.sh --mutants || fail=1

# FLAT for the same reason as the rows above, and it is again this fixture's own
# property rather than a relaxation. The scenario is a throwaway git repository
# built under $TMPDIR with identity, gpgsign and core.hooksPath pinned into that
# repository's own .git/config -- the only place any hooks path is set. Nothing
# is set in THIS repository: the tracked .githooks/pre-commit fires nowhere
# until an operator sets core.hooksPath in a clone, which ADR-009 D4 records as
# local clone configuration and OR-C records as an unclosed bootstrap gap.
#
# The leg reports and does not block (ADR-009 D1, D4 Case B), so a green row
# here is not evidence that any commit was stopped. Every case asserts both the
# text on stderr and the existence of the commit, and one case runs the same
# change with no hook installed: an uninstalled hook prints nothing, and that
# control is what makes the printed finding attributable to this file.
echo "== pre-commit container: the ADR contract leg reports and never blocks (THR-ADRGATE 4b) =="
bash tests/hook_pre_commit_fixture.sh || fail=1

echo "== bypass falsifier register: every tracked falsifier, in its declared state (ADR-017 D1) =="
# Until this block existed the tests/bypass_* falsifiers were linted by the gate
# below and executed by nothing. They sat inside the perimeter of the tooling
# and outside the perimeter of the meaning: ALL TESTS PASSED was printed over a
# tree in which any of them could be broken, could have gone green on its own,
# or could be missing entirely, and the suite had no way to know which. ADR-017
# D1 is the decision that the string above, and the exit 0 beside it, now
# additionally assert that every tracked falsifier ran and was observed in the
# state it declares.
#
# THE REGISTER IS DATA -- one literal line per falsifier, carrying its path, its
# declared state and its exit-2 policy, driven by the loop below (D2).
# Deliberately not a compacted array: a
# reader counting rows and a `grep -c 'tests/bypass_'` must reach the same
# number, and the tracker's WIR-5 counts the second.
#
# THE DECLARED STATE IS READ OFF THE FIXTURE'S OWN HEADER, never off a run (D6).
# Seeding these literals from a first execution would make the register a
# procedure certifying itself -- it would agree with whatever the tree does
# today, which is the question and not the answer.
#
# DIVERGENCE FAILS IN BOTH DIRECTIONS (D3). Declared RED and observed GREEN
# fails exactly as declared GREEN and observed RED does. A control that started
# binding with nobody recording why is a finding about this repo, not a repair
# to absorb, and the only way to clear it is to investigate and then amend the
# literal here in a commit that says what changed.
#
# rc 2 IS A FAILURE UNLESS THE ROW DECLARES OTHERWISE, AND IS NEVER A PASS (D4).
# The default is the strict reading: a bypass falsifier's exit 2 is FIXTURE
# BROKEN -- its own control could not confirm what it is measuring. That is
# deterministic, reproducible, and cleared by a human edit rather than by a
# re-run on a quieter machine. On 2026-08-11 exactly that state sat in the tree
# while this suite printed ALL TESTS PASSED.
#
# The exception is declared per row, in the THIRD COLUMN, and is admissible on
# one ground only: the fixture's own header defines its exit 2 as an ATTRIBUTION
# failure -- the row could not reach its question -- rather than a broken
# control. That row spends `unmeasured`, like the parallel-claim block above,
# and for the same reason: a refusal nobody can attribute accuses nobody. The
# reading is a property of the fixture, declared beside it, never a choice made
# at the call site, and a row that does not literally say UNMEASURED-2 gets the
# strict reading. Neither reading prints ALL TESTS PASSED: `fail` exits 1,
# `unmeasured` exits 2 with TESTS INCONCLUSIVE. The column decides what this
# suite ACCUSES, never whether it certifies.
BYPASS_REGISTER=""
bypass_row() { BYPASS_REGISTER="${BYPASS_REGISTER}${1} ${2} ${3}"$'\n'; }

#          path                                               declared  exit-2 policy
bypass_row tests/bypass_f1_lease_worktree_fixture.sh          RED       BROKEN
bypass_row tests/bypass_f2_guard_nonbash_fixture.sh           GREEN     BROKEN
bypass_row tests/bypass_f3_oracle_writable_fixture.sh         RED       BROKEN
bypass_row tests/bypass_f4_deny_literal_fixture.sh            RED       BROKEN
bypass_row tests/bypass_f5_receipt_provenance_fixture.sh      RED       BROKEN
bypass_row tests/bypass_f6_permission_layers_write_fixture.sh GREEN     BROKEN
bypass_row tests/bypass_f7_const_pin_absent_fixture.sh        RED       BROKEN
# The one lenient row in the register, and it is lenient because its own header
# is what says so -- F8 declares three states, and spells the third:
#
#   UNMEASURED (2)  the launcher refused for a reason NOT attributable to the
#                   detector. The row never reached its own question: that is
#                   neither a pass nor a fail, and it must not be spelled as
#                   either.
#
# Routing that to `fail` would accuse this repo of a defect the row never
# observed. It is the only row at this basis whose header carries that clause.
bypass_row tests/bypass_f8_tamper_gate_unwired_fixture.sh     RED       UNMEASURED-2
bypass_row tests/bypass_f9_ci_verity_unwired_fixture.sh       RED       BROKEN
bypass_row tests/bypass_fb_budget_tokens_unbounded_fixture.sh GREEN     BROKEN
bypass_row tests/bypass_fc_scope_unread_fixture.sh            GREEN     BROKEN
# F-d is DIFFERENTIAL and that is the whole reason it is a separate row. It does
# not ask whether a Write is refused -- F2 and F6, two lines up, already accuse
# that and go GREEN in this same commit on the guard's FAIL-CLOSED branch, where
# HARNESS_SCOPE never arrived at all. F-d asks whether ONE identical payload gets
# TWO verdicts under TWO declared scopes: scope=src/ refuses docs/probe.md, and
# scope=docs/ allows it. A guard that refused every Write would satisfy F2 and F6
# and leave this row RED under its own distinct message (the fixture spells that
# case separately at :133-141). GREEN here means the declared value was READ, not
# that writes got harder.
#
# Declared GREEN off this commit's own diff and not off a run, per D6: the
# fixture's header declares RED against the guard it was written against, and
# that RED was OBSERVED -- 2026-08-24, main c81301e's guard blob
# sha256 2a4b861f..., arm exit 1 -- beside GREEN on the guard this commit lands
# (sha256 65556aec..., arm exit 0). The observation is the reason the literal is
# GREEN and not RED; without it this row would be a green assertion about a
# repair that arrived in the same commit.
bypass_row tests/bypass_fd_scope_unenforced_fixture.sh       GREEN     BROKEN
bypass_row tests/bypass_fe_secret_in_context_fixture.sh       RED       BROKEN

# The attestation family, landed with ADR-018's ratification. Three rows and not
# four: ADR-018 names a falsifier for each of D1-D4, and D1's
# (`bypass_att_canon_reorder`) is NOT here. It cannot be written yet -- D1 binds
# NEW content-addressed artifacts and exempts the existing receipt, and no new
# artifact exists until ADR-019's side-car Statement does, so the file would be
# a green assertion about nothing. It is carried as ADR-018 OR-6 with that
# reason and its birth moment, which is the honest place for it: a falsifier
# listed against a non-existent artifact is the defect ADR-017 is about, and
# registering one here would put that defect inside the register built to
# prevent it.
#
# Two of these three rows clear by the same edit to scripts/receipt_chain.py,
# because this repository holds exactly ONE digest-carrying artifact today. They
# are separate rows because they are separate decisions -- D2 accuses the
# spelling of a digest in any new artifact, D4 accuses the timing of this one --
# and each header says so.
bypass_row tests/bypass_att_alg_unpinned_fixture.sh           RED       BROKEN
bypass_row tests/bypass_att_two_digest_shapes_fixture.sh      GREEN     BROKEN
bypass_row tests/bypass_chain_form_migration_fixture.sh       RED       BROKEN

# ADR-019's six, landed with its ratification. All six are declared GREEN, and
# that is not the register going soft: ADR-019's implementation -- the digest line
# at scripts/launch_worker.sh and scripts/write_statement.py -- lands in the same
# arc, so its falsifiers are green on arrival for the same reason
# bypass_att_two_digest_shapes was. What keeps them from being vacuous is that
# every one of them carries a control that makes its own assertion MOVE: a
# fabricated artifact the row must refuse, beside the real one it must accept. A
# row that can only ever say GREEN is not registered here, whatever it is called.
#
# The first of them also closes ADR-018 OR-6, which named its own birth moment:
# "the first side-car Statement emitted". That artifact now exists, so
# bypass_att_canon_reorder has a subject and stops being the green assertion about
# nothing the OR refused to admit.
#
# ADR-019's OR-4 and OR-5 -- falsifiers for its D3 and D6 -- are NOT among these
# six and are not registered. Their birth moment has arrived (the writer exists),
# but D6's falsifier is bypass_att_prose_leak, which ADR-020 D2 owns and which
# ADR-006:56 forbids while ADR-020 is Proposed. Naming a row here for a fixture
# this commit does not write is the defect ADR-017 is about.
bypass_row tests/bypass_att_canon_reorder_fixture.sh          GREEN     BROKEN
bypass_row tests/bypass_att_chain_survives_sidecar_fixture.sh GREEN     BROKEN
bypass_row tests/bypass_att_dirty_tree_subject_fixture.sh     GREEN     BROKEN
bypass_row tests/bypass_att_no_subject_no_statement_fixture.sh GREEN    BROKEN
bypass_row tests/bypass_att_result_desync_fixture.sh          GREEN     BROKEN
bypass_row tests/bypass_att_subject_missing_fixture.sh        GREEN     BROKEN

# ADR-020's three, landed with its ratification, and they are the rows the
# paragraph above said this commit was not allowed to write. ADR-006:56 forbade
# them while ADR-020 was Proposed; it is Accepted as of 2026-08-13 and the
# prohibition is spent. Two of the three also close ADR-019's last two open
# requirements -- OR-5 is bypass_att_prose_leak and OR-4 is
# bypass_att_policies_constitution -- which ADR-019 said in as many words would
# "close there".
#
# All three are declared GREEN and each carries a control that makes its own
# assertion MOVE, on the standard the six rows above are held to:
#
#   prose_leak                     six leak shapes the boundary must refuse,
#                                  beside one conforming artifact it must accept,
#                                  beside a receipt PROVEN to carry all five
#                                  leaking strings before the artifact is judged.
#   policies_constitution          four arms, and the two digests are asserted
#                                  DIFFERENT before arm 2 runs -- a row that
#                                  cannot distinguish the wrong value from the
#                                  right one is not a row.
#   receipt_host_path_published    the only one of the three whose RED was
#                                  ALREADY MEASURED rather than predicted:
#                                  N3-PUBLISH.md censused 2 of 49 receipts
#                                  carrying the token. The fixture reproduces it
#                                  at the census's own two JSON paths and fails
#                                  closed if it cannot.
bypass_row tests/bypass_att_prose_leak_fixture.sh             GREEN     BROKEN
bypass_row tests/bypass_att_policies_constitution_fixture.sh  GREEN     BROKEN
bypass_row tests/bypass_receipt_host_path_published_fixture.sh GREEN    BROKEN

# ADR-022's four, landed with its ratification. THREE GREEN AND ONE RED, and
# the red is the reason this block is worth reading.
#
# All four were written and observed RED against the launcher at ef78ad8 --
# before scripts/launch_worker.sh was touched -- with each red captured under
# .verity/evidence/2026-08-13-adr022-first-red/. ADR-022's own register makes
# that ordering a condition of ratification: "ratification without those four
# observations is a ratification against a register that decides nothing"
# (ADR-017 D5). Three of them went green on D1/D2/D3 landing in the same tree.
#
# THE FOURTH IS DECLARED RED AND IS EXPECTED TO STAY RED. This is not a row
# awaiting repair and it is not a defect anyone forgot: ADR-022 D5 names
# spec.scope's unenforceability "the residue", assigns it to ADR-011 rather
# than to itself, and says of this ADR that it "retires the allowlist as an
# excuse, nothing more". D3 above cuts both ways -- a row that started binding
# with nobody recording why fails exactly as a row that stopped does -- so if
# bypass_ft_bash_unbound goes GREEN, something carried the declared write
# perimeter to a layer that can act on it, and that is a decision somebody
# took and must record here rather than a repair to absorb quietly.
#
# The three green rows carry controls that make their own assertions MOVE, on
# the standard the ADR-019 and ADR-020 blocks above are held to:
#
#   tools_not_bound          a stand-in emitting --tools with the WRONG list
#                            must be RED beside the real one it accepts, so the
#                            row measures the bound and not the flag; a bound
#                            emitted twice is RED on its own line.
#   allowlist_widens_bound   a legal allowlist and an ABSENT one must both
#                            still launch, so the STOP is a gate and not a
#                            launcher that refuses everything.
#   mcp_survives_bound       --strict-mcp-config TOGETHER WITH --mcp-config
#                            must be RED, so the empty-set half of D3 is
#                            measured rather than assumed.
#
# And the red one carries the same discipline in the opposite direction: a
# fabricated quartet -- a launcher that emits and reads scope, a guard with a
# predicate over the write target, a settings file naming the field -- must be
# judged GREEN by the same decide(), or the row could only ever say RED and
# would be a slogan rather than a measurement.
bypass_row tests/bypass_ft_tools_not_bound_fixture.sh         GREEN     BROKEN
bypass_row tests/bypass_ft_allowlist_widens_bound_fixture.sh  GREEN     BROKEN
bypass_row tests/bypass_ft_mcp_survives_bound_fixture.sh      GREEN     BROKEN
bypass_row tests/bypass_ft_bash_unbound_fixture.sh            RED       BROKEN
# FT-5..FT-19, the THR-SUBAGENT arc (ADR-023). Rows that read a recorded run
# under runs/THR-SUBAGENT/ or need a live CLI declare UNMEASURED-2: on a
# machine without the recording (fresh CI clone) they never reach their own
# question. Hermetic rows keep the strict BROKEN reading.
bypass_row tests/bypass_ft_positive_control_bash_in_pool_fixture.sh GREEN UNMEASURED-2
bypass_row tests/bypass_ft_stale_marker_precedence_fixture.sh GREEN     BROKEN
bypass_row tests/bypass_ft_appended_prompt_negative_control_fixture.sh GREEN UNMEASURED-2
bypass_row tests/bypass_ft_write_tool_misattribution_fixture.sh GREEN   BROKEN
bypass_row tests/bypass_ft_spawn_ledger_depth_blind_fixture.sh RED      UNMEASURED-2
bypass_row tests/bypass_ft_scope_env_absent_at_depth_fixture.sh GREEN   UNMEASURED-2
bypass_row tests/bypass_ft_permission_mode_precedence_fixture.sh GREEN  UNMEASURED-2
bypass_row tests/bypass_ft_scoped_gate_out_of_scope_red_fixture.sh RED  UNMEASURED-2
bypass_row tests/bypass_ft_emitter_tools_superset_fixture.sh  GREEN     BROKEN
bypass_row tests/bypass_ft_emitter_unknown_key_fixture.sh     GREEN     BROKEN
bypass_row tests/bypass_ft_emitter_agent_without_depth_bound_fixture.sh GREEN BROKEN
bypass_row tests/bypass_ft_emitter_memory_undeclared_fixture.sh GREEN   BROKEN
bypass_row tests/bypass_ft_emitter_empty_tools_resolution_fixture.sh GREEN BROKEN
bypass_row tests/bypass_ft_emitter_deny_order_inversion_fixture.sh GREEN BROKEN
# FT-19 flips to GREEN, and the flip is bounded by a bisection and not by a
# single run: 2.1.237 and 2.1.241 measured RED, 2.1.245 measured GREEN. The
# transition therefore sits BETWEEN 2.1.241 and 2.1.245 and is not
# individuated. The fixture carries that floor as a named constant, prints the
# version it observed on every branch, and returns exit 2 below the floor
# rather than a verdict about a binary it never measured -- which is why the
# third column stays UNMEASURED-2.
#
# The subject of this row is an EXTERNAL gate. Its state is not a property of
# this tree and no commit here can move it, so the declared literal tracks a
# reading taken elsewhere; the fixture header keeps the 2026-08-13 RED at
# 2.1.231 beside the new one for exactly that reason.
bypass_row tests/bypass_ft_emitter_output_rejected_by_cli_fixture.sh GREEN UNMEASURED-2

# THR-CONFORMANCE eight (FT-20..FT-27, ADR-024): the conformance record --
# an execution is conformant only against a surface declared BEFORE it ran,
# and the absence of declaration is not conformity. Each fixture carries its
# own positive control (green corpus through the real builder) beside its
# falsifier (a doctored record, a divergent run, a sabotaged consumer), so
# every row's assertion can MOVE. All eight were observed failing once
# against stubbed verifiers/watchers before registration; the evidence
# record of that pass lives with the THR-CONFORMANCE run. FT-27 declares
# UNMEASURED-2 because a late-but-seen detection is attributable to machine
# load, not to the monitor -- blindness (never seen) stays RED.
bypass_row tests/bypass_ft_out_of_surface_call_undetected_fixture.sh GREEN BROKEN
bypass_row tests/bypass_ft_record_without_declaration_fixture.sh GREEN  BROKEN
bypass_row tests/bypass_ft_depth_collapse_fixture.sh          GREEN     BROKEN
bypass_row tests/bypass_ft_narration_only_evidence_fixture.sh GREEN     BROKEN
bypass_row tests/bypass_ft_stream_truncated_fixture.sh        GREEN     BROKEN
bypass_row tests/bypass_ft_replay_nondeterminism_fixture.sh   GREEN     BROKEN
bypass_row tests/bypass_ft_unused_authorization_unreported_fixture.sh GREEN BROKEN
bypass_row tests/bypass_ft_monitor_blind_while_running_fixture.sh GREEN UNMEASURED-2

# FT-28, and it is DECLARED RED because it was OBSERVED RED against this
# repository's own tracked tree at f1e2f47 before this row was written: 40 files
# carrying 396 occurrences of the operator's home path in the spelling
# privacy-lint-user-paths does not look for. Nothing was synthesized to produce
# that red and nothing needs to be -- the fixture that fails is the tree.
#
# The state is declared rather than repaired because the repair is not this
# suite's to take. Rewriting those 40 files changes 40 tracked blob digests, and
# three of them are cited by sha256 from conformance records under
# runs/THR-CONFORMANCE/ that resolve today; the order of the redaction and the
# re-pinning of those citations is an operator decision, and a row that went
# quietly green by having someone edit the tree underneath it would have hidden
# exactly the coupling that decision turns on.
#
# What this row is NOT is a permanent exemption. D3 above cuts both ways here as
# it does for bypass_ft_bash_unbound: if this goes GREEN, the tracked tree stopped
# carrying the material and somebody redacted it, which is a decision that gets
# recorded on this line rather than absorbed by amending the literal to match a
# run. The fixture's own four control arms -- a negative control, a counted
# positive control, the blindness of the separator spelling against planted
# flattened material, and exclusion parity with the claim's four pathspecs --
# are what keep the RED from being a slogan: the same detector was observed
# GREEN on a clean scratch tree and RED again one planted line later.
#
# 2026-08-19: RED -> GREEN, and this is the decision the paragraph above said
# would be recorded here rather than absorbed. The operator directed the
# redaction: the flattened spelling was substituted with the placeholder the
# v1 path transformation already uses, across all 40 tracked files carrying it
# (396 occurrences), in the same commit that moves this literal. The three
# conformance records that cited transformed bytes were re-pinned to the
# post-substitution digests and now declare the transformation and its
# completeness -- placeholder counts a reader can recount, zero residues in
# either spelling as this fixture measures them -- and the pre-transformation
# digests left the published artifacts. The detector is unchanged: the tree
# moved, and this line records why.
bypass_row tests/bypass_ft_flattened_home_form_undetected_fixture.sh GREEN BROKEN
bypass_row tests/bypass_ft_path_transform_undeclared_fixture.sh GREEN BROKEN

# FT -- the eleven-arm falsifier of scripts/statement_lint.py --surface, tracked
# here for the first time. It existed on disk, unregistered and untracked, while
# .verity/claims.json's own description named it as an independent driver of the
# same boundary: a tracked claim citing a falsifier no clone would receive.
# Tracking it is what makes that citation checkable, and D5 above is what makes
# tracking it require this row -- membership, not cardinality.
#
# DECLARED GREEN OFF THE HEADER AND NOT OFF A RUN (D6). The header declares
# GREEN as all eleven arms matching what each wants, and the mechanism those
# arms measure is present and implements --surface at this basis. The
# anti-vacuity is an OBSERVED RED, and its only TRACKED sede is the claim's own
# description in .verity/claims.json: "was observed RED with each exemption
# reason disabled before it was observed green". No file under .verity/evidence/
# carries that observation -- the run record naming its transcripts is not in
# the tracked set -- so this row cites the description and says so, rather than
# citing a path a fresh clone will not have. Nothing was manufactured to
# produce it and no run produced this literal.
#
# UNMEASURED-2 AND NOT BROKEN, on the ground D4 states and nothing wider: the
# fixture's own header spells its exit 2 -- "python3, git, or the boundary
# itself is absent, or the boundary does not implement --surface. That is not a
# pass and not a fail: the arm never reached its own question." That is the
# attribution reading, declared in the fixture, beside itself. It is also the
# house reading of that clause: bypass_ft_graft_incomplete_refused and
# bypass_ft_orphan_lock_blocks_resume both exit 2 on git or node absent and both
# carry UNMEASURED-2. bypass_ft_env_unchecked_and_readme_unbound is not a
# counter-precedent -- its own header spells its exit 2 BROKEN, which is why its
# row does. Nothing is added to UNMEASURED_REGISTER: on a host where this row
# measures, an entry there reads stale, and that register compares both ways.
bypass_row tests/bypass_ft_internal_enters_public_surface_fixture.sh GREEN UNMEASURED-2
bypass_row tests/bypass_ft_dossier_fabricated_source_fixture.sh GREEN BROKEN
bypass_row tests/bypass_ft_typed_equality_bool_int_fixture.sh GREEN BROKEN
bypass_row tests/bypass_ft_evidence_role_shadowing_fixture.sh GREEN BROKEN
bypass_row tests/bypass_ft_ledger_anchor_repin_fixture.sh GREEN BROKEN
bypass_row tests/bypass_ft_transform_citation_unbound_fixture.sh GREEN BROKEN
bypass_row tests/bypass_ft_anchor_order_inverted_fixture.sh GREEN BROKEN
bypass_row tests/bypass_ft_stream_echo_absent_fixture.sh GREEN BROKEN
bypass_row tests/bypass_ft_unanchored_run_yields_record_fixture.sh GREEN BROKEN
bypass_row tests/bypass_ft_opening_prepended_post_hoc_fixture.sh GREEN BROKEN
bypass_row tests/bypass_ft_passed_without_record_fixture.sh GREEN UNMEASURED-2
bypass_row tests/bypass_ft_sequence_continues_past_red_gate_fixture.sh GREEN UNMEASURED-2
bypass_row tests/bypass_ft_orphan_lock_blocks_resume_fixture.sh GREEN UNMEASURED-2
bypass_row tests/bypass_ft_added_slice_criterion_absent_fixture.sh GREEN UNMEASURED-2
bypass_row tests/bypass_ft_derive_no_signal_fixture.sh GREEN UNMEASURED-2
bypass_row tests/bypass_ft_graft_incomplete_refused_fixture.sh GREEN UNMEASURED-2

# ADR-027's falsifier, and the only file that ADR's proposing commit adds to the
# measured surface. DECLARED RED, and RED is what its own header declares: the
# two subjects it interrogates -- scripts/preflight_env.sh and
# scripts/gate_readme_claims.sh -- are absent from this tree, because ADR-027 is
# Proposed and no implementation is written against a Proposed ADR. This row is
# not a defect waiting on a repair. It is the question ADR-027 asks, in the one
# form this suite can hold an ADR to, and acceptance is what turns it GREEN.
#
# WHY A PROPOSED ADR SHIPS A FALSIFIER AT ALL (ADR-027 D3). scripts/
# gate_adr_contract.sh rejects an addition under docs/adrs/ that touches nothing
# on the measured surface, while the two-commit lifecycle wants the Proposed ADR
# to be docs-only; together the two rules make a Proposed ADR unproposable. A
# falsifier resolves it without bending either: it implements nothing, so "no
# code against a Proposed ADR" is intact, and it is the most load-bearing thing
# that could satisfy the gate.
#
# BROKEN and not UNMEASURED-2, though this row is exactly the environment-
# conditional kind the comment at UNMEASURED_REGISTER below says has no honest
# entry. It needs node and git to build its own two arms and exits 2 without
# them -- which is the disease ADR-027 D1 names, carried in the open by that
# ADR's own falsifier rather than excused here. The excuse is what acceptance
# would earn, and taking it first would be the register certifying itself.
bypass_row tests/bypass_ft_env_unchecked_and_readme_unbound_fixture.sh RED BROKEN

# COMPLETENESS IS MEMBERSHIP, NOT CARDINALITY (D5), and it runs before the
# fixtures because it is the cheap half. The set of registered paths must EQUAL
# the set `git ls-files` tracks, and the two directions are accused separately
# because they are different defects: a tracked falsifier nobody registered is a
# control the suite never runs, and a registered path that is not tracked is a
# row measuring something no clone will have.
#
# A count would pass a register carrying one row twice and one row not at all --
# right total, wrong contents, and exactly one falsifier silently unrun. Set
# comparison catches that duplicate too: `comm` pairs lines, so the second copy
# has no partner on the tracked side and is accused as registered-not-tracked
# while its victim is accused as tracked-not-registered.
bypass_declared_paths="$(printf '%s' "$BYPASS_REGISTER" | awk 'NF {print $1}' | LC_ALL=C sort)"
set +e
bypass_tracked_paths="$(git ls-files -- 'tests/bypass_*' | LC_ALL=C sort)"
bypass_ls_rc=$?
set -e
if [ "$bypass_ls_rc" -ne 0 ] || [ -z "$bypass_tracked_paths" ]; then
  echo "FAIL [bypass register completeness]: \`git ls-files -- 'tests/bypass_*'\` did not answer, so the register's completeness went unchecked. That is a failure and not an unmeasured invariant: D5 is the clause that makes an unwired falsifier visible, and a run that could not evaluate it must not certify the register"
  fail=1
else
  # -13 keeps what only the tracked side has; -23 what only the register has.
  bypass_unregistered="$(LC_ALL=C comm -13 <(printf '%s\n' "$bypass_declared_paths") <(printf '%s\n' "$bypass_tracked_paths"))"
  bypass_untracked="$(LC_ALL=C comm -23 <(printf '%s\n' "$bypass_declared_paths") <(printf '%s\n' "$bypass_tracked_paths"))"
  if [ -n "$bypass_unregistered" ]; then
    echo "FAIL [bypass register completeness]: tracked and NOT registered -- $(printf '%s' "$bypass_unregistered" | tr '\n' ' ')"
    echo "      D5: a tracked falsifier absent from the register is a control this suite never runs. Register it beside the others, carrying the state its own header declares, never the state a run produced"
    fail=1
  fi
  if [ -n "$bypass_untracked" ]; then
    echo "FAIL [bypass register completeness]: registered and NOT tracked -- $(printf '%s' "$bypass_untracked" | tr '\n' ' ')"
    echo "      D5: a registered path git does not track measures nothing in a fresh clone. Commit the falsifier, or drop the row -- and if the path appears twice in the register, this is the second copy"
    fail=1
  fi
  if [ -z "$bypass_unregistered" ] && [ -z "$bypass_untracked" ]; then
    echo "ok [bypass register completeness]: registered set == tracked set ($(printf '%s\n' "$bypass_tracked_paths" | wc -l | tr -d ' ') falsifiers)"
  fi
fi

# The fixtures are invoked with stdin closed: the loop reads the register off a
# here-string, and a child that consumed stdin would eat the rows below it and
# silently shorten the register. The here-string keeps the loop in this shell,
# so `fail` set inside it is the same `fail` the tail reads.
while read -r bp_path bp_declared bp_exit2; do
  [ -n "$bp_path" ] || continue
  if [ ! -f "$bp_path" ]; then
    echo "FAIL [bypass $bp_path]: registered and not on disk"
    fail=1
    continue
  fi
  set +e
  bp_out="$(bash "$bp_path" 2>&1 </dev/null)"
  bp_rc=$?
  set -e
  # Exit 2 leaves this loop by one of two doors, and the row's own third column
  # is what decides which (D4). Same rc, same loop, different verdict -- and the
  # strict door is the default, so a row that declares nothing gets accused.
  if [ "$bp_rc" -eq 2 ]; then
    if [ "$bp_exit2" = "UNMEASURED-2" ]; then
      # The row's own basename, minus the suffix every row carries, is the
      # name the register at the tail declares. Derived and never spelled
      # twice: a register keyed on a hand-copied string drifts from the file
      # it excuses the first time one of them is renamed.
      record_unmeasured "$(basename "$bp_path" _fixture.sh)"
      echo "unattrib [bypass $bp_path]: exit 2, and this row declares UNMEASURED-2 -- its header defines exit 2 as a refusal it cannot attribute to the mechanism under test, so the row never reached its own question. Not a pass, not a fail; the suite does not certify this run"
    else
      fail=1
      echo "FAIL [bypass $bp_path]: FIXTURE BROKEN (exit 2) -- the fixture's own control could not confirm what it is measuring. D4: with no UNMEASURED-2 on this row, exit 2 routes to fail. It is cleared by realigning the fixture by hand, not by re-running it"
    fi
    printf '%s\n' "$bp_out" | sed 's/^/      | /'
    continue
  fi
  case "$bp_rc" in
    0) bp_observed="GREEN" ;;
    1) bp_observed="RED" ;;
    *) bp_observed="EXIT$bp_rc" ;;
  esac
  if [ "$bp_observed" = "$bp_declared" ]; then
    echo "ok [bypass $bp_path]: declared $bp_declared, observed $bp_observed"
    continue
  fi
  fail=1
  echo "FAIL [bypass $bp_path]: declared $bp_declared, observed $bp_observed (exit $bp_rc). D3: investigate, then amend this row's literal in the commit that says what changed -- editing it to match this run is the failure mode the register exists to make expensive"
  printf '%s\n' "$bp_out" | sed 's/^/      | /'
done <<< "$BYPASS_REGISTER"

echo "== shellcheck =="
# Same gate as CI, not a local approximation of it: version and severity are
# read from the committed pin, so the invocation below is character-for-
# character the one .github/workflows/ci.yml runs -- and it runs only when the
# binary is the pinned one, which is what makes that sentence true rather than
# aspirational. Point $SHELLCHECK at a pinned binary to reproduce a CI verdict
# exactly.
#
# Two ways this gate can fail to be that gate, and neither is a quiet skip. A
# gate that steps aside and still lets the suite print ALL TESTS PASSED is not
# a gate -- it certifies something it never looked at.
#
#   tool absent      nothing ran at all.
#   tool mismatched  something ran, but not this gate. 0.9.0 and 0.11.0
#                    disagree about SC2015 on identical source, so a verdict
#                    from an unpinned binary neither clears these sources nor
#                    accuses them: reporting it as a pass is the certification
#                    this block refuses, and reporting it as a failure accuses
#                    the writer of a defect the pinned gate never described.
#
# Both are therefore unmeasured: nothing is accused, and nothing is claimed
# either. The old behaviour here was to warn and certify anyway, which said
# both "this verdict does NOT predict CI's" and ALL TESTS PASSED in one run.
SC_PIN_VERSION="$(sed -n 's/^SHELLCHECK_VERSION=//p' .shellcheck-version)"
SC_PIN_SEVERITY="$(sed -n 's/^SHELLCHECK_SEVERITY=//p' .shellcheck-version)"
SC_BIN="${SHELLCHECK:-shellcheck}"
if ! command -v "$SC_BIN" >/dev/null 2>&1; then
  record_unmeasured shellcheck
  echo "unattrib [shellcheck]: '$SC_BIN' is not installed, so the shell sources went unchecked this run; not a pass, not a fail. The gate pins shellcheck $SC_PIN_VERSION -- install it, or set \$SHELLCHECK to a $SC_PIN_VERSION binary"
else
  SC_HAVE="$("$SC_BIN" --version | sed -n 's/^version: //p')"
  if [ "$SC_HAVE" != "$SC_PIN_VERSION" ]; then
    record_unmeasured shellcheck
    echo "unattrib [shellcheck]: '$SC_BIN' is $SC_HAVE and the gate pins $SC_PIN_VERSION, so the shell sources went unchecked by this gate this run; not a pass, not a fail. Set \$SHELLCHECK to a $SC_PIN_VERSION binary"
  else
    "$SC_BIN" --severity="$SC_PIN_SEVERITY" scripts/*.sh tests/*.sh || fail=1
  fi
fi

echo "== compile check =="
python3 -m py_compile scripts/*.py || fail=1

# WHICH invariants are allowed to go unmeasured, declared by name.
#
# Until now this suite counted them and refused to exit 0 while the count was
# non-zero. On a tree that carries rows waiting on evidence a different step
# owes them, the count is never zero, the exit code is permanently 2, and an
# exit code that never changes reports nothing: a regression arriving under it
# is invisible, because the verdict it would have moved was already spent.
#
# The count is also blind in a second way. It answers "how many were not
# looked at" and cannot answer "which", so a row that stops attributing its
# run and a row whose evidence finally lands cancel out in a total: something
# moved in both directions and the number stayed put.
#
# So the set is declared here by name, and compared with the set this run
# observed, IN BOTH DIRECTIONS -- the same membership-not-cardinality
# discipline the bypass register applies above:
#
#   observed and NOT declared   something stopped being measurable and nobody
#                               said so. Exit non-zero; the run is not
#                               certified.
#   declared and NOT observed   a row this register still excuses answered its
#                               own question. That is good news and it is still
#                               a failure of this gate: the excuse outlived its
#                               reason and must be struck by hand. Without this
#                               direction the register only ever grows, and a
#                               permanent list of excuses is indistinguishable
#                               from no gate at all.
#
# Not a threshold and not a count: five declared rows are not satisfied by five
# observed rows, only by the same five.
#
# The second column is the reason the row cannot measure, verbatim from the
# fixture's own UNMEASURED line. Only the first column is compared; the reason
# is here so the register cannot be read without reading what it is waiting on.
# Every row below waits on recorded evidence from a THR-SUBAGENT run. Recording
# one to make a row pass is not this gate's business and is not a repair: a row
# leaves this register when the evidence it needs exists for its own reasons.
# ELEVEN rows in the register above declare UNMEASURED-2 in the third column and
# are absent from the list below: bypass_f8_tamper_gate_unwired,
# bypass_ft_scoped_gate_out_of_scope_red,
# bypass_ft_emitter_output_rejected_by_cli,
# bypass_ft_monitor_blind_while_running, bypass_ft_passed_without_record,
# bypass_ft_sequence_continues_past_red_gate,
# bypass_ft_orphan_lock_blocks_resume,
# bypass_ft_added_slice_criterion_absent, bypass_ft_derive_no_signal,
# bypass_ft_graft_incomplete_refused,
# bypass_ft_internal_enters_public_surface.
#
# That is not an omission to correct by adding them. This register compares in
# BOTH directions, so an environment-conditional row has no honest entry: listed,
# it reads stale on every shell where it does measure; unlisted, it reads
# undeclared on every shell where it does not. Either way TESTS INCONCLUSIVE.
# The comment at the gate-preamble row above already states the same fixed point
# for a fixture that solved it by construction; these ten cannot, because their
# subject is a recorded run or an external CLI.
#
# So the true scope of this suite's certification is narrower than ALL TESTS
# PASSED suggests: it certifies on a host where the observed unmeasured set
# equals the declared one, and nothing here says which host that is. Closing it
# needs a second, environment-conditional class -- a change to ADR-017 D4/D6
# semantics, which is a decision and not an edit. Recorded here, unrepaired, so
# the next reader does not rediscover it from the exit code.
#
# Owner of this file: THR-WIRING. Written by THR-ADRGATE, which reads it.
UNMEASURED_REGISTER='
bypass_ft_positive_control_bash_in_pool        no THR-SUBAGENT run with RESULT.json
bypass_ft_appended_prompt_negative_control     C2pos/C2neg evidence not recorded
bypass_ft_spawn_ledger_depth_blind             no recorded spawn ledger
bypass_ft_scope_env_absent_at_depth            no recorded PreToolUse ledger
bypass_ft_permission_mode_precedence           A5 not recorded
'
unmeasured_declared="$(printf '%s' "$UNMEASURED_REGISTER" | awk 'NF {print $1}' | LC_ALL=C sort)"
unmeasured_names="$(printf '%s' "$unmeasured_observed" | awk 'NF {print $1}' | LC_ALL=C sort)"
# -13 keeps what only the observed side has; -23 what only the register has.
unmeasured_undeclared="$(LC_ALL=C comm -13 <(printf '%s\n' "$unmeasured_declared") <(printf '%s\n' "$unmeasured_names"))"
unmeasured_stale="$(LC_ALL=C comm -23 <(printf '%s\n' "$unmeasured_declared") <(printf '%s\n' "$unmeasured_names"))"

# Three verdicts, because the suite has fixtures with three outcomes. A
# violation outranks a disagreement about the unmeasured set. Exit 1 says
# something was broken; exit 2 says the set of invariants nobody looked at is
# not the set this tree declares; exit 0 says both are as declared -- and the
# unattrib lines above still print, so exit 0 never means nothing went
# unmeasured, only that nothing went unmeasured unexpectedly.
if [ "$fail" -ne 0 ]; then
  echo "TESTS FAILED"
  exit 1
fi
if [ -n "$unmeasured_undeclared" ] || [ -n "$unmeasured_stale" ]; then
  if [ -n "$unmeasured_undeclared" ]; then
    echo "TESTS INCONCLUSIVE [unmeasured register]: observed and NOT declared -- $(printf '%s' "$unmeasured_undeclared" | tr '\n' ' ')"
    echo "      Something stopped being measurable and nothing said so. Read its unattrib line above and repair what stopped attributing. Declaring it here is the last move, never the first, and it is only honest when the row genuinely cannot measure yet and the reason can be named"
  fi
  if [ -n "$unmeasured_stale" ]; then
    echo "TESTS INCONCLUSIVE [unmeasured register]: declared and NOT observed -- $(printf '%s' "$unmeasured_stale" | tr '\n' ' ')"
    echo "      This row answered its own question this run and the register still excuses it. Strike it from UNMEASURED_REGISTER: an excuse that outlives its reason turns the register into a list nothing ever leaves"
  fi
  exit 2
fi
if [ -n "$unmeasured_names" ]; then
  echo "ok [unmeasured register]: $(printf '%s\n' "$unmeasured_names" | wc -l | tr -d ' ') invariant(s) went unmeasured and the set is exactly the one declared -- $(printf '%s' "$unmeasured_names" | tr '\n' ' ')"
fi
echo "ALL TESTS PASSED"
exit 0
