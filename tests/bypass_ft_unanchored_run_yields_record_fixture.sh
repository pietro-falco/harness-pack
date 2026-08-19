#!/usr/bin/env bash
# FT-33 -- unanchored-run-yields-record. The wiring's own falsifier: a run
# the launcher executed WITHOUT depositing into the observation ledger must
# produce no conformance record at all. If one appears, the wiring is
# ornamental -- the deposit can be skipped and the record still exists to
# be mistaken for an anchored one. The guarantee under test is about the
# record, not the run: an unanchored run may run, close, and write its
# usual per-run outputs; what it may not do is leave a statement.json.
#
# THE LAUNCHER IS REAL. scripts/launch_worker.sh runs end to end with
# stubbed collaborators (the bypass_att pattern): a stub harnesswright, a
# stub verity, and a stub claude that emits a well-formed stream-json
# transcript. The anchor tool, the builder, and the verifier are the ones
# in tree.
#
# THREE ARMS, one green control:
#   control    CONFORMANCE_LEDGER_REPO set, both deposits land
#              -> a record exists and verifies CONFORMANT (exit 0)
#              against the fixture's scratch ledger. The control is what
#              makes the two zeros below mean something.
#   no-ledger  CONFORMANCE_LEDGER_REPO unset
#              -> the launcher runs exactly as before the wiring and NO
#              statement.json exists under the run's output directory.
#   sabotage   the ledger stops accepting deposits BETWEEN the two (the
#              stub child makes it read-only mid-run), so the declaration
#              entry exists and the stream entry cannot
#              -> NO statement.json, and the launcher's stderr carries the
#              builder's OWN refusal ("run is not anchored"): the real
#              path reaches conformance_record.py's gate, measured here
#              rather than assumed from the test that feeds the builder
#              directly.
#
# GREEN: control record CONFORMANT; both arms leave zero records and the
# sabotage arm shows the builder's refusal. RED: any unanchored arm leaves
# a record file -- the wiring is ornamental.
# UNMEASURED (2): machinery absent or the control run did not produce a
# verifiable record.
#
# RED was observed against an ornamental variant of the wired launcher
# (its close path, when the stream deposit fails, writes anchors.json by
# reusing the declaration entry id for both roles -- 40-hex, accepted by
# the builder's shape check): the sabotage arm left a built record for a
# run whose stream digest was never deposited
# (runs/THR-WIRE/20260814T150517Z/P1-wiring-fixture-seen-failing.txt, the
# variant's diff beside it), then GREEN against the launcher in tree.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="${LAUNCH_WORKER:-$PACK/scripts/launch_worker.sh}"
VERIFY="$PACK/scripts/conformance_verify.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft33.XXXXXX")" || exit 2
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "UNMEASURED: $*" >&2; exit 2; }

[ -f "$LAUNCHER" ] || broken "launcher not found at $LAUNCHER"
[ -f "$VERIFY" ] || broken "scripts/conformance_verify.py is not where this fixture expects it"
command -v node >/dev/null 2>&1 || broken "node is not available; the launcher's two collaborators are node CLIs"

CONST_SHA="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$PACK/CONSTITUTION.md")"
python3 - "$WORK/manifest.json" "$CONST_SHA" <<'PY'
import json, sys
json.dump({
    "manifest_version": 1,
    "verifier_id": "https://verifier.example.invalid/harness-pack/v1",
    "constitution_hash_expected": sys.argv[2],
    "model_tiers": {"worker": "T3"},
    "tiers": {"T3": {"name": "subagent", "chain": ["HAIKU_CLASS_MODEL"]}},
}, open(sys.argv[1], "w"))
PY

mkdir -p "$WORK/bin"
cat > "$WORK/bin/claude" <<'CLAUDE_STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "0.0.0-fixture (stub)"; exit 0; fi
cat >/dev/null
# Mid-run sabotage: between the two deposits, the ledger stops taking
# writes. Fabricates the CONDITION, not the mechanism -- the launcher, the
# anchor tool and the builder are untouched.
if [ "${FT33_SABOTAGE:-}" = "1" ] && [ -n "${FT33_LEDGER:-}" ]; then
  chmod -R a-w "$FT33_LEDGER"
fi
stream=0
for a in "$@"; do [ "$a" = "stream-json" ] && stream=1; done
if [ "$stream" = "1" ]; then
  printf '%s\n' '{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","id":"tu_r1","name":"Read","input":{}}]}}'
  printf '%s\n' '{"type":"user","parent_tool_use_id":null,"message":{"content":[{"type":"tool_result","tool_use_id":"tu_r1","is_error":false,"content":""}]}}'
fi
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"session_id":"stub","total_cost_usd":0,"duration_ms":1,"permission_denials":[]}'
exit 0
CLAUDE_STUB
chmod +x "$WORK/bin/claude"

cat > "$WORK/hw.js" <<'HW_STUB'
process.stdout.write(JSON.stringify({
  kind: "unlocked", id: "S-DEMO", eligible_mode_b: true,
  spec: { model: "worker", tools: ["Read"], criteria: ["c1"],
          budget: { turns: 5 }, scope: ["README.md"] }
}));
HW_STUB

cat > "$WORK/verity.js" <<'VERITY_STUB'
process.stdout.write(JSON.stringify({
  results: [ { id: "c1", type: "command", verdict: "PASS", evidence: "exit 0" } ]
}));
VERITY_STUB

seed_repo() {  # $1 = dir
  mkdir -p "$1/specs" "$1/out" || return 1
  git -C "$1" init -q 2>/dev/null || return 1
  git -C "$1" config user.email t@example.invalid || return 1
  git -C "$1" config user.name tester || return 1
  git -C "$1" config commit.gpgsign false || return 1
  printf 'Fixture slice. The executor is a stub; the launcher is real.\n' > "$1/specs/S-DEMO.md"
}

run_launcher() {  # $1 = repo, $2 = ledger-or-empty, $3 = sabotage 0|1, $4 = logfile
  (
    cd "$1" || exit 1
    export PATH="$WORK/bin:$PATH" \
           TELEGRAM_BOT_TOKEN="" TELEGRAM_CHAT_ID="" \
           FT33_SABOTAGE="$3" FT33_LEDGER="$2" \
           HARNESS_HOME="$PACK" \
           HARNESSWRIGHT_CLI="$WORK/hw.js" \
           VERITY_CLI="$WORK/verity.js" \
           HARNESS_MANIFEST="$WORK/manifest.json" \
           RECEIPTS_DIR="$1/out"
    if [ -n "$2" ]; then export CONFORMANCE_LEDGER_REPO="$2"; fi
    bash "$LAUNCHER" specs/S-DEMO.md
  ) > "$4" 2>&1
  return $?
}

records_in() { find "$1" -name statement.json 2>/dev/null | grep -c . ; }

echo "== bypass_ft_unanchored_run_yields_record: no deposit, no record =="

# ---- control: ledger present, both deposits land ----------------------------
C="$WORK/control"
seed_repo "$C" || broken "could not seed the control repo"
git init -q "$C-ledger" || broken "could not init the control ledger"
run_launcher "$C" "$C-ledger" 0 "$WORK/control.out"
C_RC=$?
C_N="$(records_in "$C/out")"
[ "$C_N" -eq 1 ] || { sed 's/^/     | /' "$WORK/control.out"; broken "control run (exit $C_RC) left $C_N record(s), expected exactly 1"; }
C_REC="$(find "$C/out" -name statement.json | head -1)"
C_VERDICT="$(python3 "$VERIFY" "$C_REC" --ledger-repo "$C-ledger" 2>&1)"; C_VRC=$?
[ "$C_VRC" -eq 0 ] || { printf '%s\n' "$C_VERDICT" >&2; broken "control record did not verify CONFORMANT (exit $C_VRC); the two zeros below could not mean anything"; }
note "control: launcher exit $C_RC, one record, $(printf '%s' "$C_VERDICT" | head -1) against the scratch ledger"

# ---- arm 1: no ledger named -> no record ------------------------------------
U="$WORK/noledger"
seed_repo "$U" || broken "could not seed the no-ledger repo"
run_launcher "$U" "" 0 "$WORK/noledger.out"
U_RC=$?
U_N="$(records_in "$U/out")"
note "arm 1 [no-ledger]: launcher exit $U_RC, $U_N record(s)"

# ---- arm 2: deposits sabotaged mid-run -> no record, builder's refusal ------
S="$WORK/sabotage"
seed_repo "$S" || broken "could not seed the sabotage repo"
git init -q "$S-ledger" || broken "could not init the sabotage ledger"
run_launcher "$S" "$S-ledger" 1 "$WORK/sabotage.out"
S_RC=$?
chmod -R u+w "$S-ledger" 2>/dev/null
S_N="$(records_in "$S/out")"
S_REFUSAL=0
grep -q "run is not anchored" "$WORK/sabotage.out" && S_REFUSAL=1
# The premise, checked and not assumed: the declaration entry exists and
# the stream entry does not, so the run really is half-deposited.
S_ENTRIES="$(git -C "$S-ledger" rev-list refs/observations/ledger 2>/dev/null | grep -c . )"
[ "$S_ENTRIES" -eq 1 ] || broken "sabotage arm deposited $S_ENTRIES entries, expected exactly 1 (the declaration); the arm did not reach its condition"
note "arm 2 [sabotage]: launcher exit $S_RC, $S_N record(s), builder refusal seen=$S_REFUSAL, ledger entries=$S_ENTRIES"

FAIL=0
[ "$U_N" -eq 0 ] || { echo "RED: a run the launcher executed with no ledger named left $U_N record(s); the wiring is ornamental" >&2; FAIL=1; }
[ "$S_N" -eq 0 ] || { echo "RED: a run whose stream digest was never deposited left $S_N record(s); the wiring is ornamental" >&2; FAIL=1; }
[ "$S_REFUSAL" -eq 1 ] || { echo "RED: the builder's refusal never surfaced on the real path; the absence of a record cannot be attributed to the gate" >&2; FAIL=1; }
[ "$FAIL" -eq 0 ] || exit 1

echo "GREEN: no deposit, no record -- the builder's own refusal is the gate the real path crosses"
