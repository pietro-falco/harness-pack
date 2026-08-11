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
#                   PREMISE AMENDED by harnesswright/ADR-010 D1
#       "twin runs, criteria green at t0, one working stub / one inert |
#        artifacts identical; no contribution verdict exists"
#       The row's ASSERTION is untouched -- "the two artifacts must differ in
#       the contribution verdict" -- and its PREMISE is not the one printed
#       above. ADR-010 D1 amends both loci of that premise (0008:47 and the
#       register row itself) to:
#         "At least one declared criterion is `FAIL` or `ABSENT` at t0. The
#          working stub carries that criterion to `PASS`; the stub that returns
#          immediately does not."
#       The old premise made the row unclearable rather than merely red: with
#       every criterion already PASS at t0, 0008:41 admits nothing to the delta
#       for EITHER twin, 0008:45 rules the resulting empty delta "correct, not a
#       regression", and both artifacts read `NO_OP` no matter what any launcher
#       does. ADR-010 supplies a baseline on which 0008:41 is operative instead
#       of vacuous, and declares 0008:41, 0008:45 and D1's assertion intact.
#       Asserted here, in TWO halves observed in the same run, because ADR-010
#       D3(c) binds the commit that lands this arm to see the amended red before
#       it clears it (0008:139: "A row whose red has never been observed does not
#       count as a gate"):
#         half 1, the red -- the same twins run against the launcher as it stood
#           BEFORE the contribution field existed, taken from this repo's own
#           history and materialized under $TMPDIR. The artifacts do not differ,
#           because neither carries the field at all. Under the amended premise
#           this red had never been observed; the red on record was the old
#           premise's.
#         half 2, the green -- the same twins run against scripts/launch_worker.sh
#           in tree. Arm A yields `CONTRIBUTED` with a non-empty delta, arm B
#           `NO_OP` with an empty one, and the artifacts differ.
#       The row is GREEN only when both halves are observed. A green half whose
#       red never appeared is not evidence: it cannot distinguish a launcher that
#       discriminates from an assertion wired green.
#       Until 2026-08-08 this row compared two checked-in receipts under
#       tests/fixtures/adr008/. Those files are static: no launcher change can
#       ever move them, so the row could not go green by implementing D1 and was
#       not a gate. They stay in the tree as the preserved 2026-08-07 exhibit --
#       the committed evidence of that first red names their paths -- but the
#       assertion no longer reads them. It runs the launcher.
#       "The same tree" is realised as byte-identical copies of one seeded repo,
#       one per twin per half: run sequentially in a single directory, the second
#       twin would start from a tree the first one had already changed, which is
#       a different premise from the one the row names.
#       The in-tree launcher is never edited, patched or copied-with-changes to
#       stage the red. The pre-contribution launcher is a real commit's real
#       scripts/ tree, extracted read-only, so the red is an artefact of this
#       repo's history rather than a doctored stand-in.
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
#       it. Red until 2026-08-08 for the reason the decision exists: the
#       launcher ran the runner only after the executor had returned, so there
#       was no baseline to be unknown and nothing to stop. GREEN since the D
#       repair, which measures t0 under the lease and before the spawn.
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
#       Asserted: the no-op-shaped run -- criteria already PASS at baseline, an
#       executor that changes nothing -- exits 0 with `stop_reason: gate-pass`
#       and a receipt reading `contribution.verdict: NO_OP`.
#       It is measured on D6's run, which is that run: verity pinned all-PASS
#       and the inert stub. Until ADR-010 amended D1's premise it was measured
#       on D1's inert twin, which was the same run; under the amended premise
#       that twin sits on a baseline with a FAIL in it and its gate is FAIL, so
#       it is no longer the run this pin is about. The pin did not move -- its
#       subject did, and it moved to the run that still matches it rather than
#       to a repo built to look like one.
#       This row is neither a falsifier nor a discrimination control, and
#       registering it as either would misdescribe it. It cannot be red today:
#       a gate-PASS run already exits 0, and the red the register names ("exit
#       code differs from 0") is a red we must never see, on either side of the
#       implementation. Until 2026-08-08 its premise was not observable either
#       -- no run could be known to be a `NO_OP` until `contribution.verdict`
#       existed -- so it pinned the run's SHAPE. The D repair landed the field,
#       and the receipt now reads `NO_OP` in as many words, so the row
#       pins the named run and not merely one shaped like it. What it defends
#       is unchanged and is stated at ADR-008:103: a future reader who
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
#   --expect-registered the register posture. Exit 0 iff every row is in the
#                      state DECLARED FOR IT below, one literal per row. This is
#                      the third wiring of this fixture and the reason for each
#                      is worth keeping:
#                        --expect-red (2026-08-07) demanded all rows red. It
#                          could not survive rows that are green by construction:
#                          a control would have to be miscounted as a falsifier
#                          to keep the suite green.
#                        --expect-registered by CLASS (2026-08-08, first form)
#                          demanded all four FALSIFIER rows red and both
#                          non-falsifier rows green. It could not survive the
#                          first decision landing: from that moment neither the
#                          default posture nor the registered one described the
#                          tree, because the register's rows no longer share a
#                          state.
#                        per-row declaration (here) has no global state to
#                          describe, so it survives ADR-008 landing one decision
#                          at a time. A row's expected state moves by editing
#                          that row's literal, in the commit that moves it, with
#                          the reason beside it. There is no longer a mode to
#                          flip in order to make the suite green -- which is the
#                          defect ADR-009 exists to prevent -- because the mode
#                          no longer says anything about any row.
#                      The literals are read by a reader, not by a program: the
#                      block below is compared against the ADR-008 register at
#                      0008:143-150 with nothing executed.
#   --discriminate     the discrimination control for the D1 and D2 FALSIFIER
#                      rows. Exit 0 iff each of those two assertions can be made
#                      to say GREEN, by fabricating under $TMPDIR the artifact
#                      the row demands -- and still says RED when handed an
#                      artifact that lacks it. It proves the ASSERTION
#                      discriminates; it proves nothing about the launcher, and
#                      no in-tree source is read for anything but execution.
#                      A falsifier nobody has ever seen green is indistinguishable
#                      from one wired red unconditionally, and a repair cannot
#                      start from a gate that cannot move. That is what this mode
#                      buys, and it is why it runs on every suite invocation
#                      rather than being demonstrated once in a commit message.
#                      It is not a register row: it asserts on fabricated inputs,
#                      so it is neither a FALSIFIER, a CONTROL nor a PIN in the
#                      sense ADR-009 D1 defines for register rows. It is a test
#                      of this file.
#   --shared-filter    the assertion harnesswright/ADR-010 D3(a) records as
#                      outstanding, quoting 0008:59: "the implementation slice
#                      ... **asserts** the shared filter path rather than
#                      documenting it". Exit 0 iff t0 and t1 are COMMENSURABLE on
#                      a run built so that two independently written filters
#                      would diverge -- and iff the same assertion goes red
#                      against a copy of the launcher, under $TMPDIR, whose t1
#                      phase is routed through a second, drifted reduction.
#                      It is NOT a register row either, and for a stronger reason
#                      than --discriminate's: none of ADR-008's eight rows at
#                      0008:143-150 names it. It carries no EXPECT_* literal and
#                      it is neither a FALSIFIER, a CONTROL nor a PIN in the
#                      sense ADR-009 D1 defines for register rows -- it is an
#                      assertion of THIS repo, discharging an obligation ADR-010
#                      D3(a) records against ADR-008. Adding it to the register
#                      would be inventing a row in an Accepted ADR.
#
# Scratch dirs are templated under $TMPDIR: BSD `mktemp -d` with no template
# reaches for the Darwin per-user temp dir, which an agent session's sandbox
# denies (same reason as tests/run_tests.sh:6-10).
set -uo pipefail

MODE="assert-green"
while [ $# -gt 0 ]; do
  case "$1" in
    --expect-registered) MODE="expect-registered"; shift ;;
    --discriminate) MODE="discriminate"; shift ;;
    --shared-filter) MODE="shared-filter"; shift ;;
    *) echo "usage: adr008_falsifier_fixture.sh [--expect-registered|--discriminate|--shared-filter]" >&2; exit 2 ;;
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

# D1's assertion, in a file rather than inline, for one reason: --discriminate
# has to run THIS program and not a restatement of it. A control that re-types
# the assertion proves that the copy discriminates, which is worth nothing.
# Prints GREEN / RED / PREMISE and exits 0 / 1 / 2.
#
# The premise is no longer read out of the artifacts. Under harnesswright/ADR-010
# D1 it is a property of the TREE at t0 -- "at least one declared criterion is
# FAIL or ABSENT" -- so the caller measures it on the seed both twins are copied
# from, and checks the carry on each pair. It cannot be read here: the red half's
# artifacts predate the contribution field and carry no baseline table at all, so
# a premise check in this program would abort the very half 0008:139 demands.
# What is left is D1's assertion and nothing else, which is what ADR-010 D1
# declares intact: the two artifacts must differ in the contribution verdict.
# The old gate-PASS/PASS check is gone with the old premise -- under the amended
# one arm B's gate is FAIL by construction, and that is the point, not a defect.
cat > "$WORK/assert_d1.py" <<'ASSERT_D1'
import json, sys
def load(path):
    try:
        return json.load(open(path))
    except Exception as e:
        print("PREMISE receipt %s is not readable JSON: %s" % (path, e))
        sys.exit(2)
a = load(sys.argv[1])
b = load(sys.argv[2])
va = (a.get("contribution") or {}).get("verdict")
vb = (b.get("contribution") or {}).get("verdict")
if va is not None and vb is not None and va != vb:
    print("GREEN a=%s b=%s" % (va, vb))
    sys.exit(0)
print("RED contribution.verdict a=%s b=%s; the two artifacts are indistinguishable"
      % (va if va is not None else "<absent>", vb if vb is not None else "<absent>"))
sys.exit(1)
ASSERT_D1

# Fabrication, used only by --discriminate: copy a real launcher receipt and add
# the one field the launcher does not yet write. Everything else is left exactly
# as the launcher wrote it, so the fabricated artifact differs from the red run
# in precisely the thing D1 is about.
cat > "$WORK/fabricate_contribution.py" <<'FABRICATE'
import json, sys
src, dst, verdict = sys.argv[1], sys.argv[2], sys.argv[3]
r = json.load(open(src))
r["contribution"] = {"verdict": verdict, "delta": [] if verdict == "NO_OP" else ["README.md"]}
json.dump(r, open(dst, "w"), indent=2)
FABRICATE

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
    criteria: ["readme-committed", "checks-pass"],
    // budget and scope are REQUIRED of a mode B spec by
    // templates/spec.mode-b.template.md:14 and :21. A spec omitting them is not
    // a spec this fixture is entitled to fabricate, and the launcher gates on
    // both, so a stub that omits them measures the gate rather than D1/D2/D3/D6.
    // The budget is deliberately loose: the executor stub above exits at once,
    // and neither the turn cap nor the gtimeout wrapper may ever be what ends a
    // run whose contribution this fixture is reading.
    budget: { turns: 20, wall_clock: "30m" },
    scope: ["README.md"]
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

cat > "$WORK/verity-tree.js" <<'VERITY_TREE'
// The runner for D1's amended premise (harnesswright/ADR-010 D1). Unlike the
// three above it does not answer from a constant: it READS THE TREE, so a
// criterion that is FAIL at t0 reaches PASS at t1 exactly when the executor did
// the work -- which is the movement 0008:41 admits to the delta, and the whole
// content of "the working stub carries that criterion to PASS; the stub that
// returns immediately does not". Both declared criteria hang on one observable
// fact, README.md committed at HEAD: the working stub establishes it and the
// inert stub does not. Nothing here reads a clock, a load average or a pid, so
// the verdict is a function of the tree and of nothing else.
const { execFileSync } = require("child_process");
let committed = false;
try {
  execFileSync("git", ["show", "HEAD:README.md"], { stdio: "ignore" });
  committed = true;
} catch (e) {
  committed = false;
}
const verdict = committed ? "PASS" : "FAIL";
process.stdout.write(JSON.stringify({
  results: [
    { id: "readme-committed", type: "git_committed", verdict: verdict,
      evidence: "git show HEAD:README.md exit " + (committed ? "0" : "128") },
    { id: "checks-pass", type: "command", verdict: verdict,
      evidence: "exit " + (committed ? "0" : "1") }
  ]
}));
VERITY_TREE

cat > "$WORK/verity-silent.js" <<'VERITY_SILENT'
// ADR-008:66's pinned runner: exits non-zero and prints nothing. No verdict is
// produced, so the baseline is unknown -- and a run whose baseline is unknown
// cannot report a contribution (ADR-008:64).
process.exit(3);
VERITY_SILENT

cat > "$WORK/verity-skew.js" <<'VERITY_SKEW'
// The runner for --shared-filter. A CONSTANT report: it reads no tree, no clock
// and no environment, so t0 and t1 receive byte-identical input and any
// difference between the two tables is a difference between the reductions that
// produced them, never a difference in what was measured.
// It is skewed against spec.criteria (["readme-committed","checks-pass"]) on
// purpose, so that all three reductions a filter must perform are exercised in
// one report -- which is where two filters written independently drift apart:
//   readme-committed  DECLARED, absent here      -> ABSENT must be synthesized
//   checks-pass       DECLARED, reported non-PASS -> the verdict is passed through
//   unrelated-claim   reported, NOT declared      -> it must be dropped
process.stdout.write(JSON.stringify({
  results: [
    { id: "checks-pass", type: "command", verdict: "FAIL", evidence: "exit 1" },
    { id: "unrelated-claim", type: "command", verdict: "PASS", evidence: "exit 0" }
  ]
}));
VERITY_SKEW

cat > "$WORK/manifest.json" <<'MANIFEST'
{
  "manifest_version": 1,
  "model_tiers": { "worker": "T3" },
  "tiers": { "T3": { "name": "subagent", "chain": ["HAIKU_CLASS_MODEL"] } }
}
MANIFEST

# One launcher invocation. TELEGRAM_* are blanked on purpose: the launcher's
# notifier is fail-open and would otherwise send a real message from a test run.
#
# $6 names WHICH launcher, defaulting to the one in tree. Only D1's red half
# passes it, to run the pre-contribution launcher out of $TMPDIR; every other
# caller gets scripts/launch_worker.sh exactly as before. HARNESS_HOME is pinned
# to $PACK for both, which is already the in-tree launcher's own default -- the
# materialized one needs it stated, since it resolves CONSTITUTION.md and
# templates/ relative to a home it would otherwise take from $TMPDIR.
run_launcher() {  # $1=repo $2=verity_cli $3=stub_mode $4=spawn_marker $5=logfile [$6=launcher]
  rm -f "$4"
  (
    cd "$1" || exit 1
    PATH="$WORK/bin:$PATH" \
    TELEGRAM_BOT_TOKEN="" \
    TELEGRAM_CHAT_ID="" \
    ADR008_STUB_MODE="$3" \
    ADR008_SPAWN_MARKER="$4" \
    HARNESS_HOME="$PACK" \
    HARNESSWRIGHT_CLI="$WORK/hw.js" \
    VERITY_CLI="$2" \
    HARNESS_MANIFEST="$WORK/manifest.json" \
    RECEIPTS_DIR="$1/receipts" \
    bash "${6:-$PACK/scripts/launch_worker.sh}" specs/S-DEMO.md
  ) > "$5" 2>&1
  return $?
}

receipt_of() {  # $1 = repo; prints the receipt path, empty if none was written
  local r=( "$1"/receipts/*.receipt.json )
  [ -f "${r[0]}" ] && printf '%s' "${r[0]}"
  return 0
}

# D2's assertion, in a function for the same reason D1's is in a file: the
# discrimination control has to run the predicate the row runs, not a retyping
# of it. The absence of the spawn marker IS the assertion (ADR-008:66).
d2_says_green() {  # $1 = spawn marker path
  [ ! -e "$1" ]
}

# ---- --discriminate ---------------------------------------------------------
# Not a register row. It asks one question of each of the two rows this repo is
# about to repair: CAN this assertion say GREEN? A falsifier that cannot is
# wired red rather than measuring, and the repair would be aimed at nothing.
# Each row is handed a fabricated artifact under $TMPDIR -- the thing the row
# demands and the launcher does not yet produce -- and must go GREEN; then it is
# handed an artifact WITHOUT that thing and must stay RED. Both directions,
# because an assertion that says GREEN unconditionally discriminates no better
# than one that says RED unconditionally. No in-tree source is written, copied
# or patched to build any of it.
if [ "$MODE" = "discriminate" ]; then
  echo "== ADR-008 discrimination control: can the D1 and D2 assertions move? =="
  DIS_FAIL=0

  # -- D1 (ADR-008:143) -------------------------------------------------------
  # The twins are produced live, exactly as the row produces them, and the
  # fabrication adds the single field the launcher does not write. Everything
  # else in the receipt is left as the launcher wrote it, so what separates the
  # fabricated artifact from the red run is precisely what D1 is about.
  DSEED="$WORK/dis-seed"
  seed_repo "$DSEED" || broken "could not seed the discrimination twin repo"
  DA="$WORK/dis-a"; DB="$WORK/dis-b"
  cp -a "$DSEED" "$DA" || broken "could not copy the discrimination tree for A"
  cp -a "$DSEED" "$DB" || broken "could not copy the discrimination tree for B"
  run_launcher "$DA" "$WORK/verity-pass.js" working "$WORK/dis-a.spawned" "$WORK/dis-a.out"
  run_launcher "$DB" "$WORK/verity-pass.js" inert   "$WORK/dis-b.spawned" "$WORK/dis-b.out"
  DRA="$(receipt_of "$DA")"; DRB="$(receipt_of "$DB")"
  if [ -z "$DRA" ] || [ -z "$DRB" ]; then
    broken "the discrimination twins wrote no receipt; there is nothing to fabricate from"
  fi

  mkdir -p "$WORK/fab"
  python3 "$WORK/fabricate_contribution.py" "$DRA" "$WORK/fab/a-contributed.json" CONTRIBUTED \
    || broken "could not fabricate the CONTRIBUTED receipt"
  python3 "$WORK/fabricate_contribution.py" "$DRB" "$WORK/fab/b-no-op.json" NO_OP \
    || broken "could not fabricate the NO_OP receipt"
  python3 "$WORK/fabricate_contribution.py" "$DRB" "$WORK/fab/b-no-op-twin.json" NO_OP \
    || broken "could not fabricate the second NO_OP receipt"

  D1_MOVED="$(python3 "$WORK/assert_d1.py" "$WORK/fab/a-contributed.json" "$WORK/fab/b-no-op.json")"
  D1_MOVED_RC=$?
  # The other direction: the field is present in BOTH and identical. A row that
  # called this GREEN would be asserting "the field exists", not "the artifacts
  # differ", and its red today would be evidence of nothing.
  D1_HELD="$(python3 "$WORK/assert_d1.py" "$WORK/fab/b-no-op.json" "$WORK/fab/b-no-op-twin.json")"
  D1_HELD_RC=$?
  if [ "$D1_MOVED_RC" -eq 0 ] && [ "$D1_HELD_RC" -eq 1 ]; then
    echo "GREEN [D1 discrimination] the row moves on the field alone: ${D1_MOVED}"
    note "and holds red when both artifacts carry it identically: ${D1_HELD#RED }"
    note "fabricated from live receipts $(basename "$DRA") / $(basename "$DRB") under \$TMPDIR"
  else
    echo "RED [D1 discrimination] ADR-008:143 -- the row could not be made to move."
    note "fabricated differing verdicts -> exit $D1_MOVED_RC: ${D1_MOVED}"
    note "fabricated identical verdicts -> exit $D1_HELD_RC: ${D1_HELD}"
    note "expected 0 then 1. The falsifier is vacuous: it is not measuring the"
    note "difference D1 names, so implementing D1 could not turn it green."
    DIS_FAIL=1
  fi

  # -- D2, row 1 (ADR-008:144) ------------------------------------------------
  # The row asserts an ABSENCE, so the artifact to fabricate is a run in which
  # the executor was genuinely never invoked. This stand-in is that run and
  # nothing more: it consults the baseline runner first and spawns only on a
  # verdict. It is not a launcher, does not pretend to be one, and
  # scripts/launch_worker.sh is neither read into it nor patched to make it.
  mkdir -p "$WORK/d2-standin-cwd"
  cat > "$WORK/standin_baseline_first.sh" <<'STANDIN'
#!/usr/bin/env bash
# Consult the baseline, THEN decide whether to spawn. That ordering is the whole
# content of ADR-008:64, and the whole content of this file.
set -uo pipefail
BASELINE="$(node "$VERITY_CLI" verify --json 2>/dev/null)"
BASELINE_RC=$?
if [ "$BASELINE_RC" -ne 0 ] || [ -z "$BASELINE" ]; then
  echo "stand-in: baseline unknown (runner exit $BASELINE_RC); the executor is not spawned" >&2
  exit 3
fi
printf 'fixture prompt\n' | claude -p >/dev/null 2>&1
exit 0
STANDIN
  chmod +x "$WORK/standin_baseline_first.sh"

  run_standin() {  # $1 = verity cli, $2 = spawn marker
    rm -f "$2"
    (
      cd "$WORK/d2-standin-cwd" || exit 1
      PATH="$WORK/bin:$PATH" \
      VERITY_CLI="$1" \
      ADR008_SPAWN_MARKER="$2" \
      bash "$WORK/standin_baseline_first.sh"
    ) >/dev/null 2>&1
  }

  run_standin "$WORK/verity-silent.js" "$WORK/dis-d2-unknown.spawned"
  run_standin "$WORK/verity-pass.js"   "$WORK/dis-d2-known.spawned"

  # Same predicate the row runs. Green on the unknown baseline, and -- the half
  # that makes the other half mean something -- red on the known one. Without
  # the second call, "no marker" would be indistinguishable from "nothing ran".
  if d2_says_green "$WORK/dis-d2-unknown.spawned" \
     && ! d2_says_green "$WORK/dis-d2-known.spawned"; then
    echo "GREEN [D2 discrimination] the row moves on the spawn alone: marker absent under an"
    note "unknown baseline, present under a known one, same predicate both times"
    note "fabricated by \$TMPDIR/$(basename "$WORK")/standin_baseline_first.sh; scripts/launch_worker.sh untouched"
  else
    echo "RED [D2 discrimination] ADR-008:144 -- the row could not be made to move."
    note "unknown baseline, marker absent: $(d2_says_green "$WORK/dis-d2-unknown.spawned" && echo yes || echo NO)"
    note "known baseline, marker present: $(d2_says_green "$WORK/dis-d2-known.spawned" && echo NO || echo yes)"
    note "expected yes then yes. Either the assertion cannot see a spawn it should"
    note "see, or it cannot see the absence of one -- in both cases its red today"
    note "is evidence of nothing and D2 cannot be implemented against it."
    DIS_FAIL=1
  fi

  if [ "$DIS_FAIL" -eq 0 ]; then
    echo "ADR-008 DISCRIMINATION CONTROL: D1 and D2 both reach GREEN on a fabricated artifact and both hold RED without one"
    exit 0
  fi
  echo "ADR-008 DISCRIMINATION CONTROL: RED -- a falsifier above cannot move"
  note "a row that cannot say GREEN is wired red rather than measuring, and the"
  note "decision it gates cannot be implemented against it. Repair the row first."
  exit 1
fi

# ---- --shared-filter --------------------------------------------------------
# harnesswright/ADR-010 D3(a), quoting 0008:59 verbatim:
#   "The implementation slice measures the current order, states the three
#    anchoring lines in its receipt, and **asserts** the shared filter path
#    rather than documenting it."
# This block is that assertion. It is NOT a register row: none of ADR-008's eight
# rows at 0008:143-150 names it, it carries no EXPECT_* literal, and it is
# neither a FALSIFIER, a CONTROL nor a PIN in the sense ADR-009 D1 defines for
# register rows. It is an assertion of THIS repo discharging an obligation
# ADR-010 D3(a) records; adding it to the register would be inventing a row in an
# Accepted ADR.
#
# WHY IT IS NOT A GREP. 0008:51 asks for "one function used by both phases" and
# gives the reason in the same sentence: "t0 and t1 are commensurable by
# construction or they are not commensurable at all." COMMENSURABILITY is the
# property the decision is about, and a count of definitions does not measure it
# -- a rewrite that duplicates the reduction under the same name passes a grep
# unchanged. So the assertion is behavioural: it builds a run on which two
# independently written filters WOULD diverge, and requires that t0 and t1 do
# not.
#
# THE SCENARIO. verity is pinned to a constant report (verity-skew.js above) and
# the executor is the inert stub, so both phases receive byte-identical input and
# the tree between them does not move. Under one reduction the two tables are
# therefore identical of necessity, not by luck. The report is skewed so that all
# three reductions are exercised at once: a declared criterion absent from the
# report (ABSENT must be synthesized), a declared criterion reported non-PASS
# (the verdict is passed through), and a reported criterion nobody declared (it
# must be dropped).
# GREEN requires all three: the t0 table (contribution.baseline.claims) and the
# t1 table (claims) identical item for item; an empty delta; verdict NO_OP. The
# last two follow from the first under 0008:41 and are asserted anyway, because
# together they are the coherence of the contribution object a reader reads.
#
# THE RED, in the same run, because a green half alone is evidence of nothing.
# It is built from a COPY of scripts/ under $TMPDIR whose t1 CALL SITE -- and
# only its t1 call site -- is routed through a second, drifted reduction: the
# duplication 0008:51 forbids, carrying the drift a duplicate acquires. Two
# variants, one per kind of divergence:
#   absent-is-pass  the drifted t1 reads an unreported criterion as PASS. The
#                   tables differ, the delta names a criterion nothing moved, and
#                   an inert run reports CONTRIBUTED.
#   no-reduction    the drifted t1 reports what verity reported instead of
#                   reducing to spec.criteria. Its delta stays empty and its
#                   verdict stays NO_OP -- which is why this variant is here: it
#                   is the one that proves the assertion reads the TABLES and not
#                   merely the verdict field.
# scripts/ in tree is read and never written: cp reads it, the patcher writes
# only the copy, and the patcher refuses unless its anchor occurs exactly once.
# Unlike D1's red half this red is built from the working tree rather than from
# history, so it needs no history at all and survives a --depth 1 clone.
if [ "$MODE" = "shared-filter" ]; then
  echo "== ADR-010 D3(a) / 0008:59: the shared filter path, asserted behaviourally =="
  SF_FAIL=0

  # The assertion, in a file for the reason assert_d1.py is in one: both halves
  # must run THIS program and not a restatement of it.
  # Prints GREEN / RED / PREMISE and exits 0 / 1 / 2.
  cat > "$WORK/assert_shared_filter.py" <<'ASSERT_SF'
import json, sys
r = json.load(open(sys.argv[1]))
contribution = r.get("contribution") or {}
t0 = ((contribution.get("baseline") or {}).get("claims")) or []
t1 = r.get("claims") or []
gate = (r.get("gate") or {}).get("verdict")
if not t0 or not t1:
    print("PREMISE the receipt carries no t0 table (%d items) or no t1 table (%d items); nothing was compared" % (len(t0), len(t1)))
    sys.exit(2)
if gate not in ("PASS", "FAIL", "STOP"):
    print("PREMISE gate.verdict=%r, so t1 never produced a table and there is no pair" % (gate,))
    sys.exit(2)
def shape(items):
    return [(c.get("id"), c.get("verdict")) for c in items]
faults = []
if shape(t0) != shape(t1):
    faults.append("the two tables are not the same reduction: t0 %s vs t1 %s" % (shape(t0), shape(t1)))
elif t0 != t1:
    faults.append("t0 and t1 agree on id and verdict but not item for item: %s vs %s" % (t0, t1))
if contribution.get("delta"):
    faults.append("delta %s is non-empty although nothing moved between t0 and t1" % (contribution.get("delta"),))
if contribution.get("verdict") != "NO_OP":
    faults.append("contribution.verdict=%r, and an empty delta is NO_OP (0008:89)" % (contribution.get("verdict"),))
if faults:
    print("RED " + "; ".join(faults))
    sys.exit(1)
print("GREEN t0 and t1 identical item for item %s, delta empty, verdict NO_OP" % (shape(t0),))
sys.exit(0)
ASSERT_SF

  # The patcher. It writes only the copy it is handed, and it refuses rather than
  # patch nothing: a silent no-match would produce a "red" that is just the green
  # run under another name.
  cat > "$WORK/patch_t1_filter.py" <<'PATCH_T1'
import sys
path, fn_path = sys.argv[1], sys.argv[2]
ANCHOR = ('GATE_JSON="{}"\n'
          'if [ "$CC_EXIT" -eq 0 ]; then\n'
          '  measure_criteria\n'
          '  GATE_JSON="$MEASURED_JSON"\n'
          'fi\n')
text = open(path).read()
n = text.count(ANCHOR)
if n != 1:
    print("the t1 call site anchor occurs %d times, expected exactly 1" % n)
    sys.exit(2)
if text.count("\nmeasure_criteria\n") != 1:
    print("the t0 call site is not a single bare call; refusing to patch")
    sys.exit(2)
drift = open(fn_path).read()
text = text.replace(ANCHOR, drift + "\n" + ANCHOR.replace("  measure_criteria\n", "  measure_criteria_t1\n"))
if text.count("\nmeasure_criteria\n") != 1 or text.count("measure_criteria_t1") < 2:
    print("the patched copy does not carry one untouched t0 call beside one drifted t1 call")
    sys.exit(2)
open(path, "w").write(text)
print("patched")
PATCH_T1

  # Drift 1: the reduction to spec.criteria is kept and ABSENT is read as PASS.
  # Written the way a duplicate is written -- by somebody who had not read the
  # first -- and one word apart from it. Never in tree.
  cat > "$WORK/drift-absent-is-pass.sh" <<'DRIFT_ABSENT'
measure_criteria_t1() {
  local vout vexit
  set +e
  vout="$(cd "$HALT_ROOT" && node "$VERITY_CLI" verify --json 2>/dev/null)"
  vexit=$?
  set -e
  MEASURED_JSON="$(
    CRITERIA="$CRITERIA" VERITY_EXIT="$vexit" VERITY_OUT="$vout" python3 <<'DRIFT_ABSENT_PY'
import json, os
crit = [c for c in os.environ["CRITERIA"].split(",") if c]
vexit = int(os.environ["VERITY_EXIT"])
try:
    results = {r["id"]: r for r in json.loads(os.environ["VERITY_OUT"]).get("results", [])}
except Exception as e:
    print(json.dumps({"verdict": "NO-VERDICT", "reason": str(e), "verity_exit": vexit, "claims": []}))
else:
    items, failed = [], []
    for cid in crit:
        r = results.get(cid)
        if r is None:
            items.append({"id": cid, "verdict": "PASS", "evidence": "criterion id not present in verity report"})
        else:
            items.append({"id": cid, "type": r.get("type"), "verdict": r.get("verdict"), "evidence": r.get("evidence")})
            if r.get("verdict") != "PASS":
                failed.append(cid)
    verdict = "FAIL" if failed else "PASS"
    reason = ("criteria failed: " + ",".join(failed)) if failed else "all declared criteria PASS"
    print(json.dumps({"verdict": verdict, "reason": reason, "verity_exit": vexit, "claims": items}))
DRIFT_ABSENT_PY
  )"
}
DRIFT_ABSENT

  # Drift 2: no reduction at all. It reports what verity reported, which is the
  # other half of what the shared filter does and the half a duplicate is most
  # likely to leave out.
  cat > "$WORK/drift-no-reduction.sh" <<'DRIFT_NORED'
measure_criteria_t1() {
  local vout vexit
  set +e
  vout="$(cd "$HALT_ROOT" && node "$VERITY_CLI" verify --json 2>/dev/null)"
  vexit=$?
  set -e
  MEASURED_JSON="$(
    VERITY_EXIT="$vexit" VERITY_OUT="$vout" python3 <<'DRIFT_NORED_PY'
import json, os
vexit = int(os.environ["VERITY_EXIT"])
try:
    results = json.loads(os.environ["VERITY_OUT"]).get("results", [])
except Exception as e:
    print(json.dumps({"verdict": "NO-VERDICT", "reason": str(e), "verity_exit": vexit, "claims": []}))
else:
    items = [{"id": r.get("id"), "type": r.get("type"), "verdict": r.get("verdict"),
              "evidence": r.get("evidence")} for r in results]
    failed = [i["id"] for i in items if i["verdict"] != "PASS"]
    verdict = "FAIL" if failed else "PASS"
    reason = ("criteria failed: " + ",".join(failed)) if failed else "all declared criteria PASS"
    print(json.dumps({"verdict": verdict, "reason": reason, "verity_exit": vexit, "claims": items}))
DRIFT_NORED_PY
  )"
}
DRIFT_NORED

  SF_SEED="$WORK/sf-seed"
  seed_repo "$SF_SEED" || broken "could not seed the shared-filter repo"

  # A copy of scripts/ under $TMPDIR with ONE call site rerouted. Sets
  # SF_DIV_LAUNCHER. The whole tree is copied, not the launcher alone, because
  # the launcher resolves launch_checks.py and slice_lease.py beside itself.
  sf_build_divergent() {  # $1 = variant tag
    local tag="$1" root="$WORK/div-$1" patched
    mkdir -p "$root" || broken "could not create the divergent root for $tag"
    cp -a "$PACK/scripts" "$root/scripts" || broken "could not copy scripts/ for variant $tag"
    patched="$(python3 "$WORK/patch_t1_filter.py" "$root/scripts/launch_worker.sh" "$WORK/drift-$tag.sh" 2>&1)" \
      || broken "could not route variant $tag's t1 phase through a drifted reduction: $patched"
    SF_DIV_LAUNCHER="$root/scripts/launch_worker.sh"
  }

  # One run against one launcher, leaving its measurement in SF_*. Same seed,
  # same runner, same stub every time: the only thing that differs between calls
  # is which launcher wrote the receipt.
  sf_run() {  # $1 = tag, $2 = launcher path
    local tag="$1" launcher="$2" repo="$WORK/sf-$1"
    cp -a "$SF_SEED" "$repo" || broken "could not copy the shared-filter tree for $tag"
    run_launcher "$repo" "$WORK/verity-skew.js" inert "$WORK/sf-$tag.spawned" "$WORK/sf-$tag.out" "$launcher"
    SF_LAUNCH_RC=$?
    SF_RECEIPT="$(receipt_of "$repo")"
    [ -n "$SF_RECEIPT" ] || broken "the $tag run exited $SF_LAUNCH_RC and wrote no receipt; there is no pair to compare"
    # The premise, checked and not assumed: the executor was inert, so nothing in
    # the tree moved between t0 and t1.
    ! git -C "$repo" show HEAD:README.md >/dev/null 2>&1 \
      || broken "the $tag run's inert stub changed the tree; t0 and t1 no longer share an input"
    SF_OUT="$(python3 "$WORK/assert_shared_filter.py" "$SF_RECEIPT")"
    SF_RC=$?
    [ "$SF_RC" -eq 2 ] && broken "shared-filter $tag: $SF_OUT"
    return 0
  }

  # Half 1: the reds. Each divergent copy differs from the launcher in tree in
  # exactly one thing -- whether both phases share a reduction.
  for SF_VARIANT in absent-is-pass no-reduction; do
    sf_build_divergent "$SF_VARIANT"
    sf_run "red-$SF_VARIANT" "$SF_DIV_LAUNCHER"
    if [ "$SF_RC" -eq 1 ]; then
      echo "RED  [shared filter, t1 drifted: $SF_VARIANT] the copy's contribution is incoherent:"
      note "${SF_OUT#RED }"
      note "receipt $(basename "$SF_RECEIPT"), written by \$TMPDIR/$(basename "$WORK")/div-$SF_VARIANT/scripts/launch_worker.sh"
      note "that copy differs from scripts/launch_worker.sh in $(diff "$PACK/scripts/launch_worker.sh" "$SF_DIV_LAUNCHER" | grep -c '^[<>]') lines:"
      note "the injected reduction and the one call site that reaches it. t0 still calls the"
      note "filter in tree, so the divergence is between the phases and nowhere else."
    else
      echo "RED  [shared filter, t1 drifted: $SF_VARIANT] NOT OBSERVED -- a launcher whose t1"
      note "phase uses a different reduction was not seen to diverge: ${SF_OUT}"
      note "the assertion is not measuring commensurability, so its green below would be"
      note "evidence of nothing. 0008:51 is not asserted by this file."
      SF_FAIL=1
    fi
  done

  # Half 2: the green, against the launcher in tree, same seed and same runner.
  sf_run green "$PACK/scripts/launch_worker.sh"
  if [ "$SF_RC" -eq 0 ]; then
    echo "GREEN [shared filter, launcher in tree] t0 and t1 are commensurable on the run the"
    note "two drifted copies above are seen incoherent on: ${SF_OUT#GREEN }"
    note "receipt $(basename "$SF_RECEIPT"), written by scripts/launch_worker.sh"
  else
    echo "GREEN [shared filter, launcher in tree] NOT OBSERVED -- 0008:51's construction does"
    note "not hold: ${SF_OUT#RED }"
    note "t0 and t1 are not commensurable, so the delta between them is not a delta."
    SF_FAIL=1
  fi

  if [ "$SF_FAIL" -eq 0 ]; then
    echo "ADR-010 D3(a): SHARED FILTER ASSERTED -- t0 and t1 diverge under a drifted t1 and do not diverge in tree"
    exit 0
  fi
  echo "ADR-010 D3(a): SHARED FILTER NOT ASSERTED"
  note "0008:59 asks for an assertion, not a document, and 0008:51 says what it must"
  note "assert: t0 and t1 commensurable by construction. A half that did not appear"
  note "above is the half that carries that meaning."
  exit 1
fi

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
# ADR-008:143 / ADR-008:47, on the premise harnesswright/ADR-010 D1 amends them
# to. Live launcher invocations over one tree, copied byte-for-byte so every twin
# starts from the same state, run TWICE: once against the launcher as it stood
# before the contribution field existed (the red 0008:139 requires be seen first,
# and which under the amended premise had never been seen), then against the
# launcher in tree (the green). The premise is CHECKED on every pair, not
# assumed: if it stops holding, the row is measuring a different pair and must
# break loudly instead of going quietly either way.
SEED="$WORK/twin-seed"
seed_repo "$SEED" || broken "could not seed the D1 twin repo"

# The amended premise itself, measured on the seed both twins are copied from,
# with the same runner and the same invocation form the launcher uses for t0:
# at least one declared criterion must be FAIL or ABSENT, or there is nothing
# that can move and 0008:41 is vacuous again. It is measured HERE rather than
# read out of a receipt because the red half's artifacts predate the field and
# carry no baseline table at all.
D1_T0_MOVABLE="$(
  (cd "$SEED" && node "$WORK/verity-tree.js" verify --json) | python3 -c '
import json, sys
results = {r["id"]: r.get("verdict") for r in json.load(sys.stdin).get("results", [])}
print(",".join(c for c in ("readme-committed", "checks-pass")
                if results.get(c) in ("FAIL", None)))'
)"
[ -n "$D1_T0_MOVABLE" ] || broken "D1 premise (harnesswright/ADR-010 D1): no declared criterion reads FAIL or ABSENT at t0 on the seed tree, so neither twin has anything that can move"

# The red half's artefact: the launcher as it stood BEFORE the contribution
# field, located by the property that defines it rather than by a pinned sha --
# the newest commit whose launch_worker.sh contains no "contribution" at all.
# The whole scripts/ tree of that commit is extracted under $TMPDIR, so the
# historical launcher runs beside the historical helpers it resolves next to
# itself. scripts/ in tree is read by git and never written, patched or copied
# with changes: the red is an artefact of this repo's history, not a doctored
# stand-in of the current launcher.
D1_PRE_COMMIT=""
while IFS= read -r c; do
  blob="$(git -C "$PACK" show "$c:scripts/launch_worker.sh" 2>/dev/null)" || continue
  case "$blob" in *contribution*) continue ;; esac
  D1_PRE_COMMIT="$c"
  break
done < <(git -C "$PACK" log --format=%H -- scripts/launch_worker.sh 2>/dev/null)
[ -n "$D1_PRE_COMMIT" ] || broken "no commit reachable from HEAD carries a scripts/launch_worker.sh without the contribution field, so D1's amended red cannot be staged from history (a shallow clone has no such history: fetch the full one)"
mkdir -p "$WORK/pre-contribution"
git -C "$PACK" archive "$D1_PRE_COMMIT" scripts | tar -x -C "$WORK/pre-contribution" \
  || broken "could not materialize the pre-contribution scripts/ tree at $D1_PRE_COMMIT"
D1_PRE_LAUNCHER="$WORK/pre-contribution/scripts/launch_worker.sh"
[ -f "$D1_PRE_LAUNCHER" ] || broken "the materialized pre-contribution tree has no scripts/launch_worker.sh"
grep -q 'contribution' "$D1_PRE_LAUNCHER" \
  && broken "the launcher materialized from $D1_PRE_COMMIT mentions contribution after all; it is not the pre-field artefact"

# One twin pair against one launcher. Leaves its measurement in TWIN_*, which
# the caller copies out immediately -- both halves run the SAME assertion
# program on the same kind of pair, so the only thing that differs between them
# is which launcher wrote the artifacts.
d1_run_twins() {  # $1 = tag, $2 = launcher path
  local tag="$1" launcher="$2" a b ga gb
  a="$WORK/twin-$tag-a"; b="$WORK/twin-$tag-b"
  cp -a "$SEED" "$a" || broken "could not copy the twin tree for $tag/A"
  cp -a "$SEED" "$b" || broken "could not copy the twin tree for $tag/B"
  run_launcher "$a" "$WORK/verity-tree.js" working "$WORK/twin-$tag-a.spawned" "$WORK/twin-$tag-a.out" "$launcher"
  TWIN_RC_A=$?
  run_launcher "$b" "$WORK/verity-tree.js" inert "$WORK/twin-$tag-b.spawned" "$WORK/twin-$tag-b.out" "$launcher"
  TWIN_RC_B=$?
  TWIN_RECEIPT_A="$(receipt_of "$a")"
  TWIN_RECEIPT_B="$(receipt_of "$b")"
  [ -n "$TWIN_RECEIPT_A" ] || broken "twin $tag/A exited $TWIN_RC_A and wrote no receipt"
  [ -n "$TWIN_RECEIPT_B" ] || broken "twin $tag/B exited $TWIN_RC_B and wrote no receipt"
  # The carry, which is the half of the amended premise the seed measurement
  # cannot see: the working stub took the movable criteria to PASS and the inert
  # one left them where they were. Read off the tree AND off the gate the
  # launcher wrote, since both artifacts carry a gate whatever else they lack.
  git -C "$a" show HEAD:README.md >/dev/null 2>&1 \
    || broken "twin $tag/A's working stub committed nothing; no criterion was carried to PASS"
  ! git -C "$b" show HEAD:README.md >/dev/null 2>&1 \
    || broken "twin $tag/B's inert stub changed the tree"
  ga="$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1])).get("gate") or {}).get("verdict",""))' "$TWIN_RECEIPT_A")"
  gb="$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1])).get("gate") or {}).get("verdict",""))' "$TWIN_RECEIPT_B")"
  [ "$ga" = "PASS" ] || broken "twin $tag/A gate verdict=$ga, expected PASS: the working stub did not carry $D1_T0_MOVABLE to PASS"
  [ "$gb" = "PASS" ] && broken "twin $tag/B gate verdict=PASS: the inert stub's criteria moved anyway, so the pair is not the one ADR-010 D1 names"
  TWIN_OUT="$(python3 "$WORK/assert_d1.py" "$TWIN_RECEIPT_A" "$TWIN_RECEIPT_B")"
  TWIN_RC=$?
  return 0
}

# Half 1: the red, observed FIRST. 0008:139 is an ordering as much as an
# obligation -- "seen red BEFORE the decision it belongs to is implemented" --
# and this arm keeps that order inside a single run.
d1_run_twins pre "$D1_PRE_LAUNCHER"
D1_RED_OUT="$TWIN_OUT"; D1_RED_RC="$TWIN_RC"
D1_RED_A="$TWIN_RECEIPT_A"; D1_RED_B="$TWIN_RECEIPT_B"
D1_RED_RC_A="$TWIN_RC_A"; D1_RED_RC_B="$TWIN_RC_B"
[ "$D1_RED_RC" -eq 2 ] && broken "D1 red half: $D1_RED_OUT"

# Half 2: the green, on the same seed, the same stubs and the same assertion.
d1_run_twins now "$PACK/scripts/launch_worker.sh"
D1_GREEN_OUT="$TWIN_OUT"; D1_GREEN_RC="$TWIN_RC"
D1_GREEN_A="$TWIN_RECEIPT_A"; D1_GREEN_B="$TWIN_RECEIPT_B"
D1_GREEN_RC_A="$TWIN_RC_A"; D1_GREEN_RC_B="$TWIN_RC_B"
[ "$D1_GREEN_RC" -eq 2 ] && broken "D1 green half: $D1_GREEN_OUT"

D1_DELTA_A="$(python3 -c 'import json,sys;print(",".join((json.load(open(sys.argv[1])).get("contribution") or {}).get("delta") or []) or "<empty>")' "$D1_GREEN_A" 2>/dev/null)"
D1_PRE_SHORT="$(git -C "$PACK" rev-parse --short "$D1_PRE_COMMIT" 2>/dev/null || printf '%s' "$D1_PRE_COMMIT")"

if [ "$D1_RED_RC" -eq 1 ]; then
  echo "RED  [D1 half 1/2, before the field] ADR-008:143 register / harnesswright/ADR-010 D3(c) --"
  note "against scripts/launch_worker.sh as it stood at $D1_PRE_SHORT, materialized under \$TMPDIR:"
  note "${D1_RED_OUT#RED }"
  note "twin A worked (exit $D1_RED_RC_A, $(basename "$D1_RED_A")), twin B was inert (exit $D1_RED_RC_B, $(basename "$D1_RED_B"))"
  note "criteria movable at t0: $D1_T0_MOVABLE. The premise holds and the artifacts still do"
  note "not differ, because that launcher writes no contribution field at all."
else
  echo "RED  [D1 half 1/2, before the field] NOT OBSERVED -- the pre-contribution launcher at"
  note "$D1_PRE_SHORT produced artifacts the assertion separates: ${D1_RED_OUT}"
  note "a row whose red cannot be observed does not count as a gate (0008:139), so the"
  note "green half below is evidence of nothing and this row cannot be reported green."
fi

if [ "$D1_GREEN_RC" -eq 0 ]; then
  echo "GREEN [D1 half 2/2, after the field] against scripts/launch_worker.sh in tree, the same"
  note "twins over the same seed differ: ${D1_GREEN_OUT#GREEN }"
  note "arm A delta: $D1_DELTA_A (exit $D1_GREEN_RC_A, $(basename "$D1_GREEN_A"))"
  note "arm B (inert): empty delta (exit $D1_GREEN_RC_B, $(basename "$D1_GREEN_B"))"
else
  echo "GREEN [D1 half 2/2, after the field] NOT OBSERVED -- ADR-008:47's assertion, which"
  note "ADR-010 D1 declares intact, is not satisfied by the launcher in tree:"
  note "${D1_GREEN_OUT#RED }"
  note "twin A (worked): $(basename "$D1_GREEN_A"), exit $D1_GREEN_RC_A"
  note "twin B (inert):  $(basename "$D1_GREEN_B"), exit $D1_GREEN_RC_B"
fi

if [ "$D1_RED_RC" -eq 1 ] && [ "$D1_GREEN_RC" -eq 0 ]; then
  D1_STATE="GREEN"
  echo "GREEN [D1 falsifier] the row was seen red and then cleared in THIS run, on the premise"
  note "harnesswright/ADR-010 D1 amends 0008:47 and 0008:143 to. Both halves are asserted"
  note "every run: a commit carrying only the green half leaves the gate in the state"
  note "0008:139 refuses to count."
else
  echo "RED [D1 falsifier] ADR-008:143 register / harnesswright/ADR-010 D3(c) -- the row is"
  note "green only when BOTH halves are observed in one run: red against a launcher"
  note "without the contribution field, then green against the launcher in tree."
  note "half 1 (red expected): $([ "$D1_RED_RC" -eq 1 ] && echo observed || echo "NOT observed")"
  note "half 2 (green expected): $([ "$D1_GREEN_RC" -eq 0 ] && echo observed || echo "NOT observed")"
fi

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
if d2_says_green "$WORK/d2f.spawned"; then
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
# ADR-008:147 / ADR-008:103, :97. Asserted on D6's run: criteria already PASS at
# baseline, an inert executor, so it IS the no-op run this pin is about and the
# pin is measured on it rather than on a repo built to look like it. It was
# asserted on D1's inert twin until harnesswright/ADR-010 amended D1's premise;
# that twin now sits on a baseline with a FAIL in it and its gate is FAIL, which
# is a different run. The pin is unchanged -- exit 0, stop_reason gate-pass, and
# the receipt saying NO_OP in as many words -- and now reads it here.
D4_STOP="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("stop_reason",""))' "$RECEIPT" 2>/dev/null)"
D4_VERDICT="$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1])).get("contribution") or {}).get("verdict",""))' "$RECEIPT" 2>/dev/null)"
if [ "$LAUNCH_RC" -eq 0 ] && [ "$D4_STOP" = "gate-pass" ] && [ "$D4_VERDICT" = "NO_OP" ]; then
  D4_STATE="GREEN"
  echo "GREEN [D4 pin] NO_OP run exits 0 with stop_reason=gate-pass ($(basename "$RECEIPT"))"
else
  echo "RED [D4 pin] ADR-008:147 register / ADR-008:97 -- a no-op under gate.verdict PASS"
  note "exits 0 and keeps stop_reason gate-pass. Contribution and acceptance are"
  note "different questions and stay in different fields (ADR-008:99)."
  note "run: launcher exit $LAUNCH_RC, stop_reason=${D4_STOP:-<absent>}, contribution.verdict=${D4_VERDICT:-<absent>}"
  note "this row is a pinned non-behaviour, red on neither side of the implementation:"
  note "a red here means the exit code moved, and D3's retry classification broke."
fi

# ---- the declared state, one literal per row --------------------------------
# What --expect-registered compares against. Six literals, each naming its row's
# class (ADR-009 D1), its register line, and why the row stands where it stands.
# Nothing here is computed and nothing here is derived from a run: a reader holds
# this block beside the ADR-008 register at 0008:143-150 and checks it by eye.
#
# A row's expected state moves by editing ITS literal, in the commit that moves
# it. That is the whole mechanism, and it is why there is no mode that can be
# flipped to make the suite green.

# FALSIFIER, register 0008:149. Unimplemented, and not by this slice: the
# schema requires `tier_requested` and the launcher writes `tier_resolved`.
# Schema work is out of scope here (touching it would invalidate every
# receipt already in the tree), so this red is carried forward unchanged.
EXPECT_D6="RED"

# FALSIFIER, register 0008:143. CHANGED RED -> GREEN, and this is the one
# literal this commit flips. What moved is the row's PREMISE, not its assertion
# and not the launcher: harnesswright/ADR-010 D1 amends both loci of the premise
# -- 0008:47's "a tree whose criteria are already PASS" and the register row's
# "criteria green at t0" -- to "at least one declared criterion is FAIL or
# ABSENT at t0; the working stub carries that criterion to PASS, the stub that
# returns immediately does not", and declares 0008:41, 0008:45 and D1's
# assertion each intact. The paragraph this replaces argued the old premise and
# the assertion could not both hold, and named three ways to force the row green
# that all damaged an accepted decision; ADR-010 took none of them and changed
# the baseline instead, which is the one move that leaves 0008:41 operative
# rather than vacuous.
# The row is green because the arm above observed BOTH halves in this run, which
# is what ADR-010 D3(c) binds this commit to: red against the launcher as it
# stood before the contribution field existed, then green against the launcher
# in tree. Under the amended premise that red had never been observed -- the red
# on record was the old premise's -- and 0008:139 does not count a row whose red
# has not been seen. A future red here is one of two facts, and the arm says
# which: the launcher stopped discriminating, or the pre-field artefact is no
# longer reachable and the gate is no longer being demonstrated.
EXPECT_D1="GREEN"

# FALSIFIER, register 0008:146. Unimplemented, and not by this slice: rejecting
# the three malformed receipts requires the contract to express D3's total
# function, which is schema work. Carried forward unchanged.
EXPECT_D3="RED"

# FALSIFIER, register 0008:144. CHANGED RED -> GREEN by the D repair, and this
# is the one literal this commit flips. The launcher now measures t0 under the
# lease and before the spawn, so a baseline that produces no verdict stops the
# run where 0008:64 says it stops -- before the executor -- and the absence of
# the invocation, which is the whole assertion at 0008:66, is now observable.
EXPECT_D2F="GREEN"

# CONTROL, register 0008:145, classified by ADR-009 D2. Green before the change
# and green after: its evidentiary value is that D2 discriminates instead of
# blocking everything. A red here means the repair blocks runs it must let
# through, and that is the signal to stop, not to adjust this literal.
EXPECT_D2C="GREEN"

# PIN, register 0008:147, classified by ADR-009 D2. A non-behaviour fixed
# against regression: the no-op-shaped run exits 0 with stop_reason gate-pass,
# on both sides of the change (0008:97). A red here means the exit code moved
# and D3's retry classification broke.
EXPECT_D4="GREEN"

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
  MISMATCH=""
  # One comparison, applied per row. No counting: a count cannot say WHICH row
  # left its declared state, and "3/4 red" is exactly the report that let a
  # global mode stand in for six independent facts.
  declared() {  # $1 = row, $2 = declared, $3 = observed
    [ "$2" = "$3" ] || MISMATCH="$MISMATCH $1(declared=$2 observed=$3)"
    return 0
  }
  declared D6/schema-tier-requested        "$EXPECT_D6"  "$D6_STATE"
  declared D1/twin-contribution-verdict    "$EXPECT_D1"  "$D1_STATE"
  declared D3/malformed-contribution       "$EXPECT_D3"  "$D3_STATE"
  declared D2/unknown-baseline             "$EXPECT_D2F" "$D2F_STATE"
  declared D2/all-FAIL-baseline            "$EXPECT_D2C" "$D2C_STATE"
  declared D4/no-op-exit-0                 "$EXPECT_D4"  "$D4_STATE"
  echo "-- declared:            D6=$EXPECT_D6 D1=$EXPECT_D1 D3=$EXPECT_D3 D2/unknown-baseline=$EXPECT_D2F | D2/all-FAIL-baseline=$EXPECT_D2C | D4/no-op-exit-0=$EXPECT_D4"
  if [ -z "$MISMATCH" ]; then
    echo "ADR-008 FALSIFIER FIXTURE: all six rows in the state declared for them"
    exit 0
  fi
  echo "ADR-008 FALSIFIER FIXTURE: row(s) not in their declared state:$MISMATCH"
  note "a row moved. Either an implementation landed and its literal in this file"
  note "has not been updated in the same commit, or something moved a row nobody"
  note "was implementing. Both are read by naming the row above, never by"
  note "adjusting a mode: the literal is the declaration, and the commit that"
  note "changes it says which row and why."
  exit 1
fi
if [ "$FALSIFIERS_RED" -eq 0 ] && [ "$GREENS_WANTED_RED" -eq 0 ]; then
  echo "ADR-008 FALSIFIER FIXTURE: GREEN"
  exit 0
fi
echo "ADR-008 FALSIFIER FIXTURE: RED ($((FALSIFIERS_RED + GREENS_WANTED_RED))/6 rows)"
exit 1
