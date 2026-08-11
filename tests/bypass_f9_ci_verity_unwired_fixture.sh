#!/usr/bin/env bash
# F9 -- half the declared gate never runs in CI: no automated check invokes
# verity, so the claims file is enforced only by an operator typing a command.
#
# THE SUBJECT is .github/workflows/ci.yml read against the gate CLAUDE.md
# declares. CLAUDE.md's "Gate -- run before claiming anything is done" names
# TWO commands and says of them: "Both commands must be green. A red gate is a
# full stop, not a retry."
#
#     bash tests/run_tests.sh
#     node "$VERITY_CLI" verify .verity/claims.json
#
# CI runs the first. Nothing anywhere runs the second: not ci.yml, and not
# tests/run_tests.sh, which is the only thing ci.yml invokes. So on every push
# and every pull request exactly one of the two declared halves is enforced,
# and the half that goes unenforced is the one holding the privacy claims --
# the ones that keep the operator's home path, vault name, private repo names
# and real model ids out of a public tree. Those claims fail OPEN: the way they
# break is that a tracked file starts carrying a machine path, and nothing on
# the push path looks.
#
# WHY THIS IS A SOURCE-LEVEL ROW AND WHY THAT IS ENOUGH. What is being asserted
# is the composition of the CI workflow, not the behaviour of any script -- the
# defect IS that a step does not exist. tests/run_tests.sh:224 makes the same
# kind of assertion about launch_worker.sh's default and labels it
# "(source-level)". The row reads the committed workflow, not a rendering of
# it, and it is greppable in one direction only: a step that invokes verity
# cannot be written without the string.
#
# THE CONTROLS run first and are what stop this from being a grep that would
# pass on an empty file. They require ci.yml to contain the two steps it does
# have, and .verity/claims.json to hold at least one claim -- i.e. there IS a
# workflow with steps, and there IS an oracle it declines to consult.
#
# WHY THE MATCH IS ANCHORED ON A WORD BOUNDARY. The first version of this row
# grepped for the bare substring `verity` and came out GREEN on a workflow that
# does not mention verity anywhere: ci.yml:17 and :37 carry the word
# `severity`, from the lint threshold, and `severity` contains `verity`. The
# green was the instrument, not the tree. It is recorded here rather than
# quietly corrected because it is the same defect F4 registers about the DENY
# list, one screen over, committed by the falsifier written to register it: a
# literal substring is not a term.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
# Nothing is written anywhere; every file is read in place.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
CI="$PACK/.github/workflows/ci.yml"
CLAIMS="$PACK/.verity/claims.json"
GUIDE="$PACK/CLAUDE.md"
SUITE="$PACK/tests/run_tests.sh"

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$CI" ]     || broken ".github/workflows/ci.yml is not where this fixture expects it"
[ -f "$CLAIMS" ] || broken ".verity/claims.json is not where this fixture expects it"
[ -f "$GUIDE" ]  || broken "CLAUDE.md is not where this fixture expects it"
[ -f "$SUITE" ]  || broken "tests/run_tests.sh is not where this fixture expects it"

echo "== F9 the second half of the declared gate is not wired to anything =="

# ---- controls ---------------------------------------------------------------
# The workflow exists and has the steps it does have: a grep that found nothing
# because it was pointed at an empty or renamed file would prove nothing.
grep -q 'run: bash tests/run_tests.sh' "$CI" \
  || broken "ci.yml does not invoke tests/run_tests.sh; this fixture is reading the wrong file or the workflow moved"
grep -q 'shellcheck' "$CI" \
  || broken "ci.yml carries no shellcheck step; this fixture is reading the wrong file"
# The gate CLAUDE.md declares is the two-command one this row measures against.
grep -q 'verify .verity/claims.json' "$GUIDE" \
  || broken "CLAUDE.md no longer declares the verity half of the gate; the obligation this row measures has moved"
CLAIM_COUNT="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("claims", [])))' "$CLAIMS" 2>/dev/null)"
case "$CLAIM_COUNT" in
  ''|*[!0-9]*) broken "could not count the claims in .verity/claims.json" ;;
esac
[ "$CLAIM_COUNT" -gt 0 ] || broken "the claims file declares no claims; there is no oracle to leave unconsulted"
note "control: ci.yml runs the suite and shellcheck; CLAUDE.md declares both halves;"
note "control: .verity/claims.json declares $CLAIM_COUNT claims"

# ---- the row ----------------------------------------------------------------
# Word-anchored on both sides, for the reason in the header: `severity` carries
# the substring and would answer a bare grep for it. Counted twice, and the two
# counts are not the same question: MENTIONS includes prose, INVOCATIONS drops
# every comment line -- tests/run_tests.sh:760 and :780 discuss verity in
# comments and run it nowhere, and a row that could not tell those apart would
# be the substring mistake again one level up.
mentions()   { grep -cE -- '\bverity\b|VERITY_CLI' "$1"; }
invocations() {
  grep -nE -- '\bverity\b|VERITY_CLI' "$1" | grep -vcE '^[0-9]+:[[:space:]]*#'
}
CI_MENTIONS="$(mentions "$CI")"
SUITE_MENTIONS="$(mentions "$SUITE")"
CI_VERITY="$(invocations "$CI")"
SUITE_VERITY="$(invocations "$SUITE")"
PRIVACY_CLAIMS="$(python3 -c 'import json,sys; print(sum(1 for c in json.load(open(sys.argv[1])).get("claims", []) if str(c.get("id","")).startswith("privacy-lint")))' "$CLAIMS" 2>/dev/null)"

if [ "$CI_VERITY" -eq 0 ] && [ "$SUITE_VERITY" -eq 0 ]; then
  echo "RED [F9] no automated check invokes verity, on any trigger"
  note ".github/workflows/ci.yml    : $CI_VERITY invocations ($CI_MENTIONS mentions incl. comments)"
  note "tests/run_tests.sh          : $SUITE_VERITY invocations ($SUITE_MENTIONS mentions, both comments)"
  note "                              and ci.yml runs nothing but that suite"
  note ".verity/claims.json         : $CLAIM_COUNT claims, $PRIVACY_CLAIMS of them privacy-lint"
  note "CLAUDE.md declares a two-command gate and says both must be green; CI"
  note "enforces one of the two on push and pull_request"
  note "the unenforced half is the fail-open one: a privacy claim breaks by a"
  note "tracked file GAINING a home path, a vault name, a private repo name or a"
  note "real model id, and nothing on the push path looks for it"
  note "green when a CI step runs verity over .verity/claims.json and the job"
  note "fails on a red claim -- the same command CLAUDE.md already declares"
  echo "F9 BYPASS FIXTURE: RED"
  exit 1
fi

echo "GREEN [F9] verity is wired into an automated check"
note "ci.yml invocations=$CI_VERITY, run_tests.sh invocations=$SUITE_VERITY"
echo "F9 BYPASS FIXTURE: GREEN"
exit 0
