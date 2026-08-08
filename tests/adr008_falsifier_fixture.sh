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
#       Asserted: the no-op-shaped run -- D1's inert twin, criteria already PASS
#       at baseline, an executor that changes nothing -- exits 0 with
#       `stop_reason: gate-pass`.
#       This row is neither a falsifier nor a discrimination control, and
#       registering it as either would misdescribe it. It cannot be red today:
#       a gate-PASS run already exits 0, and the red the register names ("exit
#       code differs from 0") is a red we must never see, on either side of the
#       implementation. Until 2026-08-08 its premise was not observable either
#       -- no run could be known to be a `NO_OP` until `contribution.verdict`
#       existed -- so it pinned the run's SHAPE. The D repair landed the field,
#       and twin B's receipt now reads `NO_OP` in as many words, so the row
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
    *) echo "usage: adr008_falsifier_fixture.sh [--expect-registered|--discriminate]" >&2; exit 2 ;;
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
cat > "$WORK/assert_d1.py" <<'ASSERT_D1'
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
  [ -n "$DRA" ] && [ -n "$DRB" ] \
    || broken "the discrimination twins wrote no receipt; there is nothing to fabricate from"

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

D1_OUT="$(python3 "$WORK/assert_d1.py" "$RECEIPT_A" "$RECEIPT_B")"
D1_RC=$?
case "$D1_RC" in
  0) D1_STATE="GREEN"; echo "GREEN [D1 falsifier] twin artifacts differ in the contribution verdict (${D1_OUT#GREEN })" ;;
  1) echo "RED [D1 falsifier] ADR-008:143 register / ADR-008:47 -- two LIVE launcher runs over"
     note "one tree whose criteria were already PASS at baseline, one executor working and"
     note "one inert, must write receipts that differ in the contribution verdict."
     note "twin A (worked, committed README.md): $(basename "$RECEIPT_A"), launcher exit $RC_A"
     note "twin B (inert, changed nothing):      $(basename "$RECEIPT_B"), launcher exit $RC_B"
     note "${D1_OUT#RED }"
     # The note this replaced -- "green when the launcher writes
     # contribution.verdict" -- became false on 2026-08-08: the launcher writes
     # it, and the row is still red. The assertion above is unchanged; only this
     # diagnostic is, because a fixture that keeps explaining a red it no longer
     # has is the drift these registers exist to catch.
     note "the launcher DOES write contribution.verdict, and both twins read NO_OP."
     note "0008:41 moves a criterion into the delta only from FAIL or ABSENT to PASS;"
     note "on 0008:47's premise -- a tree already PASS at t0 -- no criterion can move,"
     note "for either twin. 0008:45 rules that case correct and not a regression, and"
     note "says so 'here so it is never fixed'. The premise and the assertion of this"
     note "row cannot both hold: see EXPECT_D1 below for the three ways to force it"
     note "green and why none of them is a launcher repair." ;;
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

# FALSIFIER, register 0008:143. Still RED after the D repair, and the cause has
# CHANGED -- which is the reason this literal carries prose instead of a word.
# The launcher now writes contribution.verdict, so the red is no longer
# "the field does not exist". Both twins now read NO_OP, and they must:
#   0008:47 sets the premise "two launcher runs against a tree whose criteria
#     are already PASS", and requires that "the two artifacts must differ in the
#     contribution verdict".
#   0008:41 defines the delta as "the set of declared criteria whose verdict
#     moved from `FAIL` or `ABSENT` at the earlier point to `PASS` at the later
#     one". On a tree already PASS at t0, no criterion can move, for either twin.
#   0008:45 rules on exactly that case: "Re-running a slice that has already
#     contributed yields an empty delta and `NO_OP`. That is **correct, not a
#     regression** ... Stated here so it is never 'fixed'."
# So the row's premise and the row's assertion cannot both hold. Under 0008:41
# and 0008:45 the honest verdict for BOTH twins is NO_OP, and the artifacts are
# identical because neither run contributed. The three ways to turn this green
# are: compare something other than the contribution verdict (weakening the
# assertion), give twin A a baseline that is not all-PASS (rewriting 0008:47's
# premise into a different row), or define the delta on something other than
# criterion movement (contradicting 0008:41). None is a launcher repair, and
# none is taken here. The row stays RED and the seam is reported to the operator
# rather than papered over by this literal.
EXPECT_D1="RED"

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
