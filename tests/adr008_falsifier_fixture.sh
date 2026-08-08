#!/usr/bin/env bash
# Falsifier register for harnesswright ADR-008 (Accepted 2026-08-07),
# "the contribution delta -- a pre-launch baseline, a three-phase gate, and a
# receipt that states its own no-op". The register is normative:
#
#   ADR-008:139  "each row must be **seen red** before the decision it belongs
#                 to is implemented. A row whose red has never been observed
#                 does not count as a gate."
#
# This file is that observation, made executable. It carries six of the eight
# rows -- D6, D1, D3, D2 (both rows), D4 -- and NOTHING that implements them.
# The launcher, the schema and the receipt writer are read here, never written.
# D5 and D7 stay uncovered on purpose: ADR-008:115 scopes D5's fixture to "that
# slice" (the acceptance sibling, a later slice), and D7's row asserts on a
# reward function this repo does not yet contain.
#
# Every row carries a classification, and the classification is load-bearing:
#
#   FALSIFIER  can be red today, and IS seen red today. Its red is the evidence
#              that the decision is not yet implemented. A falsifier that is
#              green before its implementation is a vacuous gate, so this file
#              fails loudly in that case rather than reporting a pass.
#   CONTROL    a discrimination control. It CANNOT be red before implementation,
#              because its job is to prove the rule under test discriminates
#              instead of blocking everything. It is registered as a control,
#              is green today, and must still be green when the decision lands.
#   PIN        a pinned non-behaviour. Neither of the above: it asserts that
#              something deliberately does NOT change, so it is green on both
#              sides of the implementation. Only D4 is one, and ADR-008:103
#              says so in as many words -- "a test that pins a deliberate
#              non-behaviour".
#
#   D6  FALSIFIER   ADR-008:149 (register) / ADR-008:127 (decision)
#       "launcher-produced receipt validated against the schema | fails on
#        `tier_requested`"
#       Asserted: a receipt produced by scripts/launch_worker.sh in THIS run
#       validates against templates/receipt.schema.json. The receipt is
#       produced, not stubbed, because the row says "produced by the current
#       launcher" and a hand-written stand-in would assert the stand-in.
#
#   D1  FALSIFIER   ADR-008:143 (register) / ADR-008:47 (decision)
#       "twin runs, criteria green at t0, one working stub / one inert |
#        artifacts identical; no contribution verdict exists"
#       Asserted: two LIVE launcher invocations over the same tree -- criteria
#       already PASS at baseline, one working executor stub, one inert -- write
#       receipts whose contribution verdicts DIFFER.
#       Until 2026-08-08 this row compared two checked-in receipts under
#       tests/fixtures/adr008/. Those files are static: no launcher change can
#       ever move them, so the row could not go green by implementing D1 and was
#       not a gate. They stay in the tree as the preserved 2026-08-07 exhibit --
#       the committed evidence of that first red names their paths -- but the
#       assertion no longer reads them. It runs the launcher.
#       "The same tree" is realised as two byte-identical copies of one seeded
#       repo, one per twin: run sequentially in a single directory, the second
#       twin would start from a tree the first one had already changed, which is
#       a different premise from the one the row names.
#
#   D3  FALSIFIER   ADR-008:146 (register) / ADR-008:93 (decision)
#       "`delta: []` with `CONTRIBUTED`; `NOT_EVALUATED` beside a gate verdict;
#        `NO_OP` with non-empty `delta` | all three accepted"
#       Asserted: the receipt contract REJECTS all three. Each fixture carries
#       every field the schema requires and every enum in range, so the only
#       thing that can reject it is the contribution invariant -- a red here
#       cannot be a red for some other reason.
#
#   D2  FALSIFIER   ADR-008:144 (register) / ADR-008:66, :64 (decision)
#       "runner pinned to a silent non-zero script | executor is spawned despite
#        an unknown baseline"
#       Asserted: with the baseline runner pinned to a script that exits
#       non-zero and prints nothing, the executor is NEVER invoked. The absence
#       of the invocation is the whole assertion, exactly as ADR-008:66 states
#       it. Red today for the reason the decision exists: the launcher runs the
#       runner only after the executor has returned (launch_worker.sh:265-268),
#       so there is no baseline to be unknown and nothing to stop.
#
#   D2  CONTROL     ADR-008:145 (register) / ADR-008:63 (decision)
#       "baseline all-`FAIL` | run blocked, when it must complete"
#       Asserted: with the runner producing verdicts that are all `FAIL`, the
#       executor IS invoked and the run reaches its receipt. ADR-008:63 -- "a t0
#       in which every criterion reads FAIL or ABSENT is the healthy normal case
#       and must never stop a run". This row cannot be red before D2 lands:
#       nothing blocks today, so nothing can be wrongly blocked. It is the pair
#       to the falsifier above, and the pair is what proves the rule
#       discriminates rather than merely blocking (ADR-008:66). Completion here
#       means the run reached its receipt, NOT exit 0 -- an all-`FAIL` gate
#       exits non-zero and always did.
#
#   D4  PIN         ADR-008:147 (register) / ADR-008:103, :97 (decision)
#       "`NO_OP` run | exit code differs from 0"
#       Asserted: the no-op-shaped run -- D1's inert twin, criteria already PASS
#       at baseline, an executor that changes nothing -- exits 0 with
#       `stop_reason: gate-pass`.
#       This row is neither a falsifier nor a discrimination control, and
#       registering it as either would misdescribe it. It cannot be red today:
#       a gate-PASS run already exits 0, and the red the register names ("exit
#       code differs from 0") is a red we must never see, on either side of the
#       implementation. Its premise is also not yet observable -- no run can be
#       known to be a `NO_OP` until `contribution.verdict` exists (D1/D3) -- so
#       today it pins the run's SHAPE, and gains the name `NO_OP` when the field
#       lands. What it defends is stated at ADR-008:103: a future reader who
#       finds the no-op, judges exit 0 wrong, and breaks D3's retry
#       classification while believing they are tightening the gate.
#
# "The receipt contract" means one thing throughout: the declaration in
# templates/receipt.schema.json, applied by validate_receipt below. One
# validator, used by D6 and by D3, so the two rows cannot disagree about what
# acceptance is.
#
# Modes:
#   (default)          the TDD posture. Exit 0 iff ALL six rows are GREEN.
#   --expect-registered the register posture. Exit 0 iff every FALSIFIER row is
#                      RED and every CONTROL/PIN row is GREEN -- each row in the
#                      state the register declares for it. This replaces the
#                      --expect-red of 2026-08-07, which could not survive rows
#                      that are green by construction: under it, a control would
#                      have to be miscounted as a falsifier to keep the suite
#                      green, which is the one defect this register cannot
#                      afford. This is how tests/run_tests.sh wires the fixture
#                      while ADR-008 is unimplemented, so the reds are
#                      re-observed on every run instead of being parked. When a
#                      decision lands, its row goes GREEN, this mode goes red,
#                      and the wiring is flipped to the default -- deliberately,
#                      not silently.
#
# Scratch dirs are templated under $TMPDIR: BSD `mktemp -d` with no template
# reaches for the Darwin per-user temp dir, which an agent session's sandbox
# denies (same reason as tests/run_tests.sh:6-10).
set -uo pipefail

MODE="assert-green"
while [ $# -gt 0 ]; do
  case "$1" in
    --expect-registered) MODE="expect-registered"; shift ;;
    *) echo "usage: adr008_falsifier_fixture.sh [--expect-registered]" >&2; exit 2 ;;
  esac
done

PACK="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$PACK/tests/fixtures/adr008"
SCHEMA="$PACK/templates/receipt.schema.json"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-adr008.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

D6_STATE="RED"; D1_STATE="RED"; D3_STATE="RED"
D2F_STATE="RED"; D2C_STATE="RED"; D4_STATE="RED"
note() { printf '     %s\n' "$*"; }
# A fixture that cannot set its scenario up has measured nothing. Exit 2 is
# reserved for that, and is never reported as a red.
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

# The receipt contract, and the only definition of "accepted" this file uses:
# every key in the schema's `required` list is present, and every property that
# declares an `enum` holds a value from it. Prints ACCEPT / REJECT and exits
# 0 / 1. It is deliberately nothing more -- the schema declares nothing more.
cat > "$WORK/validate_receipt.py" <<'VALIDATOR'
import json, sys
schema = json.load(open(sys.argv[1]))
receipt = json.load(open(sys.argv[2]))
missing = [k for k in schema.get("required", []) if k not in receipt]
bad_enum = [
    "%s=%r" % (k, receipt[k])
    for k, p in (schema.get("properties") or {}).items()
    if k in receipt and "enum" in p and receipt[k] not in p["enum"]
]
if missing or bad_enum:
    print("REJECT missing=%s enum=%s"
          % (",".join(missing) or "-", ",".join(bad_enum) or "-"))
    sys.exit(1)
print("ACCEPT")
VALIDATOR

# ---- the collaborators the launcher shells out to ---------------------------
# harnesswright and verity are node CLIs; `claude` is the executor. Stubbing
# them stubs the run, not the launcher -- which is the code under assertion.
# Signing and identity are pinned into each throwaway repo's own .git/config,
# for the reason tests/run_tests.sh:13-22 gives: without it the fixture
# inherits the operator's global config, `git commit` reaches for a key, and
# the verdict depends on whose machine it runs on.
seed_repo() {  # $1 = dir
  mkdir -p "$1/specs" "$1/receipts" || return 1
  git -C "$1" init -q 2>/dev/null || return 1
  git -C "$1" config user.email t@example.invalid || return 1
  git -C "$1" config user.name tester || return 1
  git -C "$1" config commit.gpgsign false || return 1
  git -C "$1" config tag.gpgsign false || return 1
  printf 'Fixture slice. The executor is a stub; the launcher is real.\n' \
    > "$1/specs/S-DEMO.md"
}

mkdir -p "$WORK/bin"
cat > "$WORK/bin/claude" <<'CLAUDE_STUB'
#!/usr/bin/env bash
# tool_version is read from `claude --version` (launch_worker.sh:191), BEFORE
# the executor is ever spawned. The version path must therefore never touch the
# spawn marker: the exhibit ADR-008:23 qualifies itself the same way, and so
# does this run.
if [ "${1:-}" = "--version" ]; then echo "0.0.0-fixture (stub)"; exit 0; fi
# Reached only from launch_worker.sh:252 -- the executor invocation itself.
# This marker is what D2's two rows read.
if [ -n "${ADR008_SPAWN_MARKER:-}" ]; then : > "$ADR008_SPAWN_MARKER"; fi
cat >/dev/null
# working: the executor contributes -- it writes and commits. inert: it returns
# immediately, having changed nothing. Both exit 0 and both report success, so
# the ONLY difference between the twins is whether work happened.
if [ "${ADR008_STUB_MODE:-inert}" = "working" ]; then
  printf 'Written by the working executor stub.\n' > README.md
  git add -- README.md >/dev/null 2>&1
  git commit -q -m "fixture: the working executor contributed" >/dev/null 2>&1
fi
printf '%s\n' '{"subtype":"success","num_turns":7,"total_cost_usd":0.0412,"duration_ms":41200,"session_id":"fixture-session"}'
CLAUDE_STUB
chmod +x "$WORK/bin/claude"

cat > "$WORK/hw.js" <<'HW_STUB'
// `harnesswright next --json`: one unlocked, Mode-B-eligible slice.
process.stdout.write(JSON.stringify({
  kind: "unlocked",
  id: "S-DEMO",
  eligible_mode_b: true,
  spec: {
    model: "worker",
    tools: ["Read", "Bash"],
    criteria: ["readme-committed", "checks-pass"]
  }
}));
HW_STUB

cat > "$WORK/verity-pass.js" <<'VERITY_PASS'
// `verity verify --json`: both declared criteria PASS, so the gate passes and
// the launcher writes a closure receipt on its success path.
process.stdout.write(JSON.stringify({
  results: [
    { id: "readme-committed", type: "git_committed", verdict: "PASS", evidence: "git show HEAD:README.md exit 0" },
    { id: "checks-pass", type: "command", verdict: "PASS", evidence: "exit 0" }
  ]
}));
VERITY_PASS

cat > "$WORK/verity-fail.js" <<'VERITY_FAIL'
// Verdicts produced, and every one of them FAIL: ADR-008:63's healthy normal
// case. The runner is healthy; the tree simply has not been worked on yet.
process.stdout.write(JSON.stringify({
  results: [
    { id: "readme-committed", type: "git_committed", verdict: "FAIL", evidence: "git show HEAD:README.md exit 128" },
    { id: "checks-pass", type: "command", verdict: "FAIL", evidence: "exit 1" }
  ]
}));
VERITY_FAIL

cat > "$WORK/verity-silent.js" <<'VERITY_SILENT'
// ADR-008:66's pinned runner: exits non-zero and prints nothing. No verdict is
// produced, so the baseline is unknown -- and a run whose baseline is unknown
// cannot report a contribution (ADR-008:64).
process.exit(3);
VERITY_SILENT

cat > "$WORK/manifest.json" <<'MANIFEST'
{
  "manifest_version": 1,
  "model_tiers": { "worker": "T3" },
  "tiers": { "T3": { "name": "subagent", "chain": ["HAIKU_CLASS_MODEL"] } }
}
MANIFEST

# One launcher invocation. TELEGRAM_* are blanked on purpose: the launcher's
# notifier is fail-open and would otherwise send a real message from a test run.
run_launcher() {  # $1=repo $2=verity_cli $3=stub_mode $4=spawn_marker $5=logfile
  rm -f "$4"
  (
    cd "$1" || exit 1
    PATH="$WORK/bin:$PATH" \
    TELEGRAM_BOT_TOKEN="" \
    TELEGRAM_CHAT_ID="" \
    ADR008_STUB_MODE="$3" \
    ADR008_SPAWN_MARKER="$4" \
    HARNESSWRIGHT_CLI="$WORK/hw.js" \
    VERITY_CLI="$2" \
    HARNESS_MANIFEST="$WORK/manifest.json" \
    RECEIPTS_DIR="$1/receipts" \
    bash "$PACK/scripts/launch_worker.sh" specs/S-DEMO.md
  ) > "$5" 2>&1
  return $?
}

receipt_of() {  # $1 = repo; prints the receipt path, empty if none was written
  local r=( "$1"/receipts/*.receipt.json )
  [ -f "${r[0]}" ] && printf '%s' "${r[0]}"
  return 0
}

echo "== ADR-008 falsifier register: D6, D1, D3, D2, D2, D4 =="

# ---- D6 (FALSIFIER) --------------------------------------------------------
# ADR-008:149 / ADR-008:127.
REPO6="$WORK/target"
seed_repo "$REPO6" || broken "could not seed the D6 target repo"
run_launcher "$REPO6" "$WORK/verity-pass.js" inert "$WORK/d6.spawned" "$WORK/d6.out"
LAUNCH_RC=$?

RECEIPT="$(receipt_of "$REPO6")"
if [ -z "$RECEIPT" ]; then
  sed 's/^/  launcher: /' "$WORK/d6.out" >&2
  broken "the launcher exited $LAUNCH_RC and wrote no receipt; D6 measured nothing"
fi

if D6_OUT="$(python3 "$WORK/validate_receipt.py" "$SCHEMA" "$RECEIPT" 2>&1)"; then
  D6_STATE="GREEN"
  echo "GREEN [D6 falsifier] launcher receipt validates against templates/receipt.schema.json ($D6_OUT)"
else
  echo "RED [D6 falsifier] ADR-008:149 register / ADR-008:127 -- a receipt produced by the"
  note "current launcher must validate against templates/receipt.schema.json."
  note "receipt: $(basename "$RECEIPT") (written by scripts/launch_worker.sh, launcher exit $LAUNCH_RC)"
  note "$D6_OUT"
  note "green when the schema and the launcher agree on tier_requested (ADR-008:123)"
fi

# ---- D1 (FALSIFIER) --------------------------------------------------------
# ADR-008:143 / ADR-008:47. Two live launcher invocations over one tree, copied
# byte-for-byte so both twins start from the same state. The premise -- criteria
# already PASS at baseline, one executor that worked and one that did not -- is
# CHECKED, not assumed: if it stops holding, the row is measuring a different
# pair and must break loudly instead of going quietly red.
SEED="$WORK/twin-seed"
seed_repo "$SEED" || broken "could not seed the D1 twin repo"
REPO_A="$WORK/twin-a"; REPO_B="$WORK/twin-b"
cp -a "$SEED" "$REPO_A" || broken "could not copy the twin tree for A"
cp -a "$SEED" "$REPO_B" || broken "could not copy the twin tree for B"

run_launcher "$REPO_A" "$WORK/verity-pass.js" working "$WORK/twin-a.spawned" "$WORK/twin-a.out"
RC_A=$?
run_launcher "$REPO_B" "$WORK/verity-pass.js" inert "$WORK/twin-b.spawned" "$WORK/twin-b.out"
RC_B=$?

RECEIPT_A="$(receipt_of "$REPO_A")"
RECEIPT_B="$(receipt_of "$REPO_B")"
[ -n "$RECEIPT_A" ] || broken "twin A exited $RC_A and wrote no receipt"
[ -n "$RECEIPT_B" ] || broken "twin B exited $RC_B and wrote no receipt"
# The working twin worked and the inert twin did not -- otherwise the two runs
# are not the pair ADR-008:47 names.
[ -f "$REPO_A/README.md" ] || broken "twin A's working stub changed nothing"
[ -f "$REPO_B/README.md" ] && broken "twin B's inert stub changed the tree"

D1_OUT="$(python3 - "$RECEIPT_A" "$RECEIPT_B" <<'PY'
import json, sys
a = json.load(open(sys.argv[1]))
b = json.load(open(sys.argv[2]))
ga = (a.get("gate") or {}).get("verdict")
gb = (b.get("gate") or {}).get("verdict")
if ga != "PASS" or gb != "PASS":
    print("PREMISE gate verdicts a=%s b=%s, expected PASS/PASS (criteria are "
          "already PASS at baseline)" % (ga, gb))
    sys.exit(2)
va = (a.get("contribution") or {}).get("verdict")
vb = (b.get("contribution") or {}).get("verdict")
if va is not None and vb is not None and va != vb:
    print("GREEN a=%s b=%s" % (va, vb))
    sys.exit(0)
print("RED contribution.verdict a=%s b=%s; the two artifacts are indistinguishable"
      % (va if va is not None else "<absent>", vb if vb is not None else "<absent>"))
sys.exit(1)
PY
)"
D1_RC=$?
case "$D1_RC" in
  0) D1_STATE="GREEN"; echo "GREEN [D1 falsifier] twin artifacts differ in the contribution verdict (${D1_OUT#GREEN })" ;;
  1) echo "RED [D1 falsifier] ADR-008:143 register / ADR-008:47 -- two LIVE launcher runs over"
     note "one tree whose criteria were already PASS at baseline, one executor working and"
     note "one inert, must write receipts that differ in the contribution verdict."
     note "twin A (worked, committed README.md): $(basename "$RECEIPT_A"), launcher exit $RC_A"
     note "twin B (inert, changed nothing):      $(basename "$RECEIPT_B"), launcher exit $RC_B"
     note "${D1_OUT#RED }"
     note "green when the launcher writes contribution.verdict (ADR-008:83)" ;;
  *) broken "D1 premise: $D1_OUT" ;;
esac

# ---- D3 (FALSIFIER) --------------------------------------------------------
# ADR-008:146 / ADR-008:93. "Accepted" is not rhetorical here: each fixture is
# put through the same validator D6 uses, and the count of accepts is the red.
D3_ACCEPTED=""
D3_REJECTED=""
for f in "$FIX"/malformed-*.receipt.json; do
  [ -f "$f" ] || broken "no malformed D3 fixtures found under $FIX"
  if python3 "$WORK/validate_receipt.py" "$SCHEMA" "$f" >/dev/null 2>&1; then
    D3_ACCEPTED="$D3_ACCEPTED $(basename "$f" .receipt.json)"
  else
    D3_REJECTED="$D3_REJECTED $(basename "$f" .receipt.json)"
  fi
done
if [ -z "$D3_ACCEPTED" ]; then
  D3_STATE="GREEN"
  echo "GREEN [D3 falsifier] all three malformed contribution receipts rejected:$D3_REJECTED"
else
  echo "RED [D3 falsifier] ADR-008:146 register / ADR-008:93 -- three malformed contribution"
  note "receipts must be rejected by the receipt contract. Accepted:$D3_ACCEPTED"
  note "templates/receipt.schema.json declares $(grep -c 'contribution' "$SCHEMA") rules about contribution,"
  note "so every value of contribution.verdict is legal and none of the three can be refused."
  note "green when the contract expresses D3's total function (ADR-008:89, ADR-008:123)"
fi

# ---- D2, row 1 (FALSIFIER) -------------------------------------------------
# ADR-008:144 / ADR-008:66. The runner is pinned to a script that exits non-zero
# and prints nothing; the assertion is the ABSENCE of an executor invocation.
REPO_D2F="$WORK/d2-unknown-baseline"
seed_repo "$REPO_D2F" || broken "could not seed the D2 falsifier repo"
run_launcher "$REPO_D2F" "$WORK/verity-silent.js" inert "$WORK/d2f.spawned" "$WORK/d2f.out"
RC_D2F=$?
if [ ! -e "$WORK/d2f.spawned" ]; then
  D2F_STATE="GREEN"
  echo "GREEN [D2 falsifier] executor never invoked under an unknown baseline (launcher exit $RC_D2F)"
else
  echo "RED [D2 falsifier] ADR-008:144 register / ADR-008:66 -- with the baseline runner"
  note "exiting non-zero and printing nothing, the launcher must stop BEFORE the executor"
  note "is spawned; the absence of the invocation is the assertion."
  note "the executor stub ran: $(basename "$WORK/d2f.spawned") exists (launcher exit $RC_D2F)"
  note "the launcher runs the runner only after the executor returns"
  note "(launch_worker.sh:265-268), so no baseline is taken and none can be unknown"
  note "green when the launcher measures t0 before spawning (ADR-008:57, ADR-008:64)"
fi

# ---- D2, row 2 (CONTROL) ---------------------------------------------------
# ADR-008:145 / ADR-008:63. The pair to the row above, and the reason the rule
# is a rule rather than a block: verdicts were produced and every one is FAIL,
# which is the healthy normal case and must run to completion. Completion is
# "the run reached its receipt", not exit 0 -- an all-FAIL gate exits non-zero.
REPO_D2C="$WORK/d2-all-fail-baseline"
seed_repo "$REPO_D2C" || broken "could not seed the D2 control repo"
run_launcher "$REPO_D2C" "$WORK/verity-fail.js" inert "$WORK/d2c.spawned" "$WORK/d2c.out"
RC_D2C=$?
RECEIPT_D2C="$(receipt_of "$REPO_D2C")"
if [ -e "$WORK/d2c.spawned" ] && [ -n "$RECEIPT_D2C" ]; then
  D2C_STATE="GREEN"
  echo "GREEN [D2 control] all-FAIL baseline ran to completion: executor invoked, receipt $(basename "$RECEIPT_D2C") written (launcher exit $RC_D2C)"
else
  echo "RED [D2 control] ADR-008:145 register / ADR-008:63 -- a baseline in which every"
  note "criterion reads FAIL is the healthy normal case and must never stop a run."
  note "executor invoked: $([ -e "$WORK/d2c.spawned" ] && echo yes || echo NO)"
  note "receipt written:  ${RECEIPT_D2C:-<none>} (launcher exit $RC_D2C)"
  note "this row is a discrimination control: it is green today and must stay green"
  note "when D2 lands. A red here means D2 blocks runs it must let through."
fi

# ---- D4 (PIN) --------------------------------------------------------------
# ADR-008:147 / ADR-008:103, :97. Asserted on D1's inert twin: that IS the
# no-op-shaped run -- criteria already PASS at baseline, an executor that
# changed nothing -- so the pin is measured on the run it is about rather than
# on a fourth repo built to look like it.
D4_STOP="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("stop_reason",""))' "$RECEIPT_B" 2>/dev/null)"
if [ "$RC_B" -eq 0 ] && [ "$D4_STOP" = "gate-pass" ]; then
  D4_STATE="GREEN"
  echo "GREEN [D4 pin] no-op-shaped run exits 0 with stop_reason=gate-pass (twin B, $(basename "$RECEIPT_B"))"
else
  echo "RED [D4 pin] ADR-008:147 register / ADR-008:97 -- a no-op under gate.verdict PASS"
  note "exits 0 and keeps stop_reason gate-pass. Contribution and acceptance are"
  note "different questions and stay in different fields (ADR-008:99)."
  note "twin B: launcher exit $RC_B, stop_reason=${D4_STOP:-<absent>}"
  note "this row is a pinned non-behaviour, red on neither side of the implementation:"
  note "a red here means the exit code moved, and D3's retry classification broke."
fi

# ---- verdict ---------------------------------------------------------------
echo "-- ADR-008 register: falsifiers D6=$D6_STATE D1=$D1_STATE D3=$D3_STATE D2/unknown-baseline=$D2F_STATE | control D2/all-FAIL-baseline=$D2C_STATE | pin D4/no-op-exit-0=$D4_STATE"
FALSIFIERS_RED=0
for s in "$D6_STATE" "$D1_STATE" "$D3_STATE" "$D2F_STATE"; do
  [ "$s" = "RED" ] && FALSIFIERS_RED=$((FALSIFIERS_RED + 1))
done
GREENS_WANTED_RED=0
for s in "$D2C_STATE" "$D4_STATE"; do
  [ "$s" = "RED" ] && GREENS_WANTED_RED=$((GREENS_WANTED_RED + 1))
done

if [ "$MODE" = "expect-registered" ]; then
  if [ "$FALSIFIERS_RED" -eq 4 ] && [ "$GREENS_WANTED_RED" -eq 0 ]; then
    echo "ADR-008 FALSIFIER FIXTURE: 4/4 falsifiers RED, 2/2 control+pin GREEN, as the register requires"
    exit 0
  fi
  echo "ADR-008 FALSIFIER FIXTURE: $FALSIFIERS_RED/4 falsifiers RED, $GREENS_WANTED_RED/2 control+pin RED"
  note "a falsifier went green with no implementation behind it, or a control/pin went"
  note "red, or an implementation landed and this fixture is still wired"
  note "--expect-registered in tests/run_tests.sh"
  exit 1
fi
if [ "$FALSIFIERS_RED" -eq 0 ] && [ "$GREENS_WANTED_RED" -eq 0 ]; then
  echo "ADR-008 FALSIFIER FIXTURE: GREEN"
  exit 0
fi
echo "ADR-008 FALSIFIER FIXTURE: RED ($((FALSIFIERS_RED + GREENS_WANTED_RED))/6 rows)"
exit 1
