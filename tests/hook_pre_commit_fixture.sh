#!/usr/bin/env bash
# Fixture for .githooks/pre-commit -- the multi-leg pre-commit container
# installed by ADR-009 D4 Case B.
#
# WHAT IS ASSERTED, and it is deliberately narrow: that when the container IS
# invoked by git it REPORTS and DOES NOT BLOCK. Every case therefore asserts
# BOTH halves -- the text the hook wrote on stderr, and the existence of the
# commit that text was written during. Asserting only that the commit succeeded
# would be satisfied by a hook that was never installed, and asserting only the
# text would be satisfied by a hook that printed and then aborted. Neither half
# alone is the decision D4 Case B took.
#
# THE ANTI-VACUITY CONTROL IS THE POINT OF THE FILE. `no_hook_installed_*` runs
# the same commit as `adr_add_alone_*` with core.hooksPath aimed at an empty
# directory: no hook fires, nothing is printed, and the commit still succeeds.
# It is what makes the finding observed in the first case attributable to the
# hook rather than to the shape of the scenario.
#
# HERMETIC BY CONSTRUCTION, which is why tests/run_tests.sh registers it FLAT
# and adds nothing to UNMEASURED_REGISTER. The scenario is a throwaway
# repository built under $TMPDIR with identity, gpgsign and core.hooksPath
# pinned into that repository's own .git/config and nowhere else. No hook, no
# hooksPath and no configuration of any kind is set in the repository this file
# is tracked in -- ADR-009 D4 records that core.hooksPath is local clone
# configuration that does not travel with a repository, and OR-C records that
# the bootstrap closing that gap is declared and not implemented. No linter, no
# network and no agent runs here: nothing an environment can refuse, so there
# is no third state to declare.
#
# STATES, in the grammar this suite speaks:
#   PASSED (0)     every case observed the verdict it declares.
#   FAILED (1)     a case observed a different verdict. A defect in the hook or
#                  in this fixture, cleared by hand.
#   UNMEASURED (2) a control did not behave and a case never reached its
#                  question. Not a pass and not an accusation.
#
# THE HOOK IS NEVER READ THROUGH A PIPE, and neither is git: each commit's exit
# status is captured from the invocation itself, with stderr redirected to a
# file. `git commit | tee` would report tee's status and every case below would
# be a verdict about the wrong process.
#
# Run standalone:  bash tests/hook_pre_commit_fixture.sh
# Point HOOK_BIN at another copy to drive a variant of the container.

set -u

FIX=${0##*/}

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) ||
  { printf '%s: not inside a git work tree\n' "$FIX" >&2; exit 2; }
HOOK_REAL="${HOOK_BIN:-$ROOT/.githooks/pre-commit}"
GATE_REAL="$ROOT/scripts/gate_adr_contract.sh"
CONF_REAL="$ROOT/scripts/measured_surface.conf"
[ -x "$HOOK_REAL" ] || { printf '%s: not executable: %s\n' "$FIX" "$HOOK_REAL" >&2; exit 2; }
[ -x "$GATE_REAL" ] || { printf '%s: not executable: %s\n' "$FIX" "$GATE_REAL" >&2; exit 2; }
[ -f "$CONF_REAL" ] || { printf '%s: declaration not found: %s\n' "$FIX" "$CONF_REAL" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/hookfix.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM
REPO="$WORK/repo"
ERR="$WORK/err"
PASS=0
FAILN=0

ok()  { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
bad() { FAILN=$((FAILN + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

G() { git -C "$REPO" "$@"; }

mkdir -p "$REPO" "$WORK/nohooks" || exit 2
git -c init.defaultBranch=main init -q "$REPO" || exit 2
mkdir -p "$REPO/.githooks" "$REPO/docs/adrs" "$REPO/scripts" || exit 2

# Identity, signing and hooks are pinned into the throwaway repository's own
# config. This is the only place in this fixture where core.hooksPath is set.
G config user.name fixture           || exit 2
G config user.email fixture@invalid  || exit 2
G config commit.gpgsign false        || exit 2
G config tag.gpgsign false           || exit 2
G config core.hooksPath .githooks    || exit 2

cp "$HOOK_REAL" "$REPO/.githooks/pre-commit" || exit 2
chmod 0755 "$REPO/.githooks/pre-commit" || exit 2

# The gate and its declaration are placed where the hook resolves them and are
# left UNTRACKED on purpose: moving the gate aside for the absent case must
# produce no change git would report, so no case can be contaminated by the
# setup of another.
GATE_IN_REPO="$REPO/scripts/gate_adr_contract.sh"
cp "$GATE_REAL" "$GATE_IN_REPO" || exit 2
chmod 0755 "$GATE_IN_REPO" || exit 2
cp "$CONF_REAL" "$REPO/scripts/measured_surface.conf" || exit 2
CONF_MISSING="$WORK/conf.missing"

printf '#!/usr/bin/env bash\ntrue\n' > "$REPO/scripts/real.sh" || exit 2
printf 'readme\n'                    > "$REPO/README.md"       || exit 2
G add -- scripts/real.sh README.md || exit 2
G commit -q -m base >/dev/null 2>&1 || exit 2

# A commit exists iff HEAD moved. Read before and after, never inferred from
# git's own exit status: a hook that aborted and a hook that never ran both
# leave the caller looking at an exit code and not at the history.
head_now() { G rev-parse HEAD 2>/dev/null; }

# do_commit <msg> <path> -- stage one path, commit it, leave the exit status in
# RC, the stderr in $ERR and whether HEAD moved in MOVED.
RC=0
MOVED=no
do_commit() {
  local msg=$1 path=$2 before after
  before=$(head_now)
  G add -- "$path" || exit 2
  G commit -q -m "$msg" 2>"$ERR"
  RC=$?
  after=$(head_now)
  if [ -n "$after" ] && [ "$after" != "$before" ]; then MOVED=yes; else MOVED=no; fi
}

commit_case() {  # commit_case <name> -- asserts the commit landed
  if [ "$RC" -eq 0 ] && [ "$MOVED" = yes ]; then ok "$1"
  else bad "$1" "git exit $RC, HEAD moved: $MOVED -- the leg blocked a commit it must only report on"; fi
}

# --- the finding case: printed, and not blocking --------------------------
printf 'a\n' > "$REPO/docs/adrs/ADR-001.md" || exit 2
do_commit c1 docs/adrs/ADR-001.md
cp "$ERR" "$WORK/err.finding" || exit 2
if grep -q 'adr-contract FINDING' "$ERR" &&
   grep -q 'adds a file under docs/adrs/ and touches no file on the measured surface' "$ERR"; then
  ok adr_add_alone_finding_printed
else
  bad adr_add_alone_finding_printed "the gate's finding is absent from the hook's stderr"
fi
if grep -q 'does not block' "$ERR"; then ok finding_names_itself_as_a_report
else bad finding_names_itself_as_a_report "the finding line does not say the leg reports rather than blocks"; fi
commit_case adr_add_alone_commit_exists

# --- the conformant case: silent, and not blocking ------------------------
printf 'a\n' > "$REPO/docs/adrs/ADR-002.md" || exit 2
printf 'true\n' >> "$REPO/scripts/real.sh" || exit 2
G add -- scripts/real.sh || exit 2
do_commit c2 docs/adrs/ADR-002.md
if grep -q 'adr-contract' "$ERR"; then
  bad conformant_commit_prints_no_finding "the leg spoke on a change it accepts"
else ok conformant_commit_prints_no_finding; fi
commit_case conformant_commit_exists

# --- the gate is absent: named, never silent ------------------------------
mv "$GATE_IN_REPO" "$WORK/gate.away" || exit 2
printf 'a\n' > "$REPO/docs/adrs/ADR-003.md" || exit 2
do_commit c3 docs/adrs/ADR-003.md
if grep -q 'adr-contract DID NOT RUN' "$ERR" &&
   grep -q 'scripts/gate_adr_contract.sh is absent or not executable' "$ERR"; then
  ok gate_absent_line_names_what_it_did_not_resolve
else bad gate_absent_line_names_what_it_did_not_resolve "an unresolved gate was silent"; fi
if grep -q 'adr-contract FINDING' "$ERR"; then
  bad gate_absent_is_not_reported_as_a_finding "an absent gate was reported as a contract finding"
else ok gate_absent_is_not_reported_as_a_finding; fi
commit_case gate_absent_commit_exists
mv "$WORK/gate.away" "$GATE_IN_REPO" || exit 2

# --- the gate errors (exit 2): distinct from a finding --------------------
printf 'a\n' > "$REPO/docs/adrs/ADR-004.md" || exit 2
export ADR_GATE_CONF="$CONF_MISSING"
do_commit c4 docs/adrs/ADR-004.md
unset ADR_GATE_CONF
if grep -q 'the gate reported an error or a missing declaration' "$ERR"; then
  ok gate_exit2_line_distinct_from_finding
else bad gate_exit2_line_distinct_from_finding "exit 2 was not distinguished from exit 1 in the text"; fi
if grep -q 'adr-contract FINDING' "$ERR"; then
  bad gate_exit2_is_not_reported_as_a_finding "an error was reported as a contract finding"
else ok gate_exit2_is_not_reported_as_a_finding; fi
if grep -q 'declaration not found' "$ERR"; then ok gate_exit2_relays_the_gate_message
else bad gate_exit2_relays_the_gate_message "the gate's own message was not relayed"; fi
commit_case gate_exit2_commit_exists

# --- ANTI-VACUITY: no hook installed, nothing printed ---------------------
# The same change as the first case, committed through a clone whose hooks path
# holds no hook. A commit that succeeds proves nothing on its own; what this
# case measures is that the finding text is ABSENT when the container does not
# run, which is the only thing that makes its presence above attributable.
printf 'a\n' > "$REPO/docs/adrs/ADR-005.md" || exit 2
BEFORE=$(head_now)
G add -- docs/adrs/ADR-005.md || exit 2
G -c core.hooksPath="$WORK/nohooks" commit -q -m c5 2>"$ERR"
RC=$?
AFTER=$(head_now)
if [ -n "$AFTER" ] && [ "$AFTER" != "$BEFORE" ]; then MOVED=yes; else MOVED=no; fi
if grep -q 'adr-contract' "$ERR"; then
  bad no_hook_installed_prints_nothing "a hook that is not installed produced the hook's own text"
else ok no_hook_installed_prints_nothing; fi
commit_case no_hook_installed_commit_exists
if [ -s "$WORK/err.finding" ]; then ok finding_control_captured_output
else bad finding_control_captured_output "the finding case captured no stderr at all: every text assertion above is vacuous"; fi

printf '%s: observed finding on a real commit, verbatim (ADR-009 OR-C evidence):\n' "$FIX"
cat "$WORK/err.finding"

printf '%s: pass=%d fail=%d\n' "$FIX" "$PASS" "$FAILN"
if [ "$FAILN" -gt 0 ]; then exit 1; fi
exit 0
