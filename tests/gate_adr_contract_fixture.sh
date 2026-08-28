#!/usr/bin/env bash
# Fixture for scripts/gate_adr_contract.sh -- the ADR contract gate (ADR-009).
#
# THE GATE IS AN ERROR DETECTOR, NOT A BOUNDARY, and its own header says so.
# What this file asserts is exactly one thing: that when the gate IS called it
# accepts and rejects for the reasons it declares, and that the surface it reads
# is the surface this repo's linters read. Nothing here is evidence that a commit
# could not have been produced without calling it.
#
# HERMETIC BY CONSTRUCTION, which is why tests/run_tests.sh registers it FLAT and
# adds nothing to UNMEASURED_REGISTER. The scenario is a throwaway repository
# built under $TMPDIR with identity, gpgsign and hooksPath pinned into that
# repository's own .git/config and nowhere else -- built by hand rather than
# through run_tests.sh's init_fixture_repo() so this fixture also runs standalone.
# No shellcheck, no py_compile, no agent, no network: nothing an environment can
# refuse, so there is no third state to declare.
#
# STATES, in the grammar this suite speaks:
#   PASSED (0)     every case observed the verdict it declares.
#   FAILED (1)     a case observed a different verdict. A defect in the gate or
#                  in this fixture, cleared by hand.
#   UNMEASURED (2) a control did not behave and a case never reached its
#                  question. Not a pass and not an accusation.
#
# THE GATE IS NEVER READ THROUGH A PIPE. `gate | tail; echo $?` reports tail's
# exit status, and one case below measures exactly that so the discipline is
# recorded rather than remembered.
#
# This fixture never invokes tests/run_tests.sh: it is registered there, and
# calling it back would recurse and would cost the whole suite.
#
# Run standalone:      bash tests/gate_adr_contract_fixture.sh
# Mutants arm:         bash tests/gate_adr_contract_fixture.sh --mutants
# Point ADR_GATE_BIN at another copy to drive a mutant of the gate.

set -u

FIX=${0##*/}
MUT_ARM=0
case "${1-}" in
  "")        : ;;
  --mutants) MUT_ARM=1 ;;
  *)         printf '%s: usage: %s [--mutants]\n' "$FIX" "$FIX" >&2; exit 2 ;;
esac

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) ||
  { printf '%s: not inside a git work tree\n' "$FIX" >&2; exit 2; }
GATE_REAL="${ADR_GATE_BIN:-$ROOT/scripts/gate_adr_contract.sh}"
CONF_REAL="$ROOT/scripts/measured_surface.conf"
SUITE="$ROOT/tests/run_tests.sh"
[ -x "$GATE_REAL" ] || { printf '%s: not executable: %s\n' "$FIX" "$GATE_REAL" >&2; exit 2; }
[ -f "$CONF_REAL" ] || { printf '%s: declaration not found: %s\n' "$FIX" "$CONF_REAL" >&2; exit 2; }
[ -f "$SUITE" ]     || { printf '%s: suite not found: %s\n' "$FIX" "$SUITE" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/adrgatefix.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM
OUT="$WORK/out"
GATE="$GATE_REAL"
PASS=0
FAILN=0

ok()  { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
bad() { FAILN=$((FAILN + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

conf_values() {  # conf_values <key> <file>
  local key=$1 file=$2 line k v
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    k=${line%% *}
    [ "$k" = "$key" ] || continue
    v=${line#"$k"}
    while [ "${v# }" != "$v" ]; do v=${v# }; done
    printf '%s\n' "$v"
  done < "$file"
}

# Every non-comment line of <file> that hands a glob to shellcheck or py_compile,
# and the glob tokens on them. Two outputs so a case can assert the extraction
# found what it claims to have found.
lint_lines() { grep -nE '(--severity=|py_compile)' "$1" | grep -vE '^[0-9]+:[[:space:]]*#'; }
lint_globs() { lint_lines "$1" | grep -oE '[^[:space:]]*[*][^[:space:]]*' | LC_ALL=C sort -u; }

REPO="$WORK/repo"
mkdir -p "$REPO" "$WORK/nohooks" || exit 2
G() {
  git -C "$REPO" -c user.name=fixture -c user.email=fixture@invalid \
      -c commit.gpgsign=false -c tag.gpgsign=false \
      -c core.hooksPath="$WORK/nohooks" "$@"
}
git -c init.defaultBranch=main init -q "$REPO" || exit 2
mkdir -p "$REPO/docs/adrs" "$REPO/scripts/lib" "$REPO/notes" || exit 2
printf 'seed\n'                      > "$REPO/docs/adrs/ADR-000-seed.md"
printf '#!/usr/bin/env bash\ntrue\n' > "$REPO/scripts/real.sh"
printf 'x = 1\n'                     > "$REPO/scripts/real.py"
printf '#!/usr/bin/env bash\ntrue\n' > "$REPO/scripts/lib/deep.sh"
printf 'readme\n'                    > "$REPO/README.md"
printf 'note\n'                      > "$REPO/notes/draft.md"
G add -- docs/adrs/ADR-000-seed.md scripts/real.sh scripts/real.py \
        scripts/lib/deep.sh README.md notes/draft.md || exit 2
G commit -q -m base || exit 2
# Untracked and matched by scripts/*.sh: the linters would read it, the
# declaration must not (R4). The control below asserts both halves.
printf '#!/usr/bin/env bash\ntrue\n' > "$REPO/scripts/ghost.sh"

CONF_OK="$WORK/conf.ok"
{ printf 'VERSION 1\n'
  printf 'ADR_PREFIX docs/adrs/\n'
  printf 'GLOB scripts/*.sh\n'
  printf 'GLOB scripts/*.py\n'; } > "$CONF_OK"
CONF_EMPTY="$WORK/conf.empty"
{ printf 'VERSION 1\n'; printf 'ADR_PREFIX docs/adrs/\n'; } > "$CONF_EMPTY"
CONF_BADGLOB="$WORK/conf.badglob"
{ printf 'VERSION 1\n'; printf 'ADR_PREFIX docs/adrs/\n'; printf 'GLOB allthethings\n'; } > "$CONF_BADGLOB"
CONF_MISSING="$WORK/conf.missing"

commit_now() {  # commit_now <msg> <path...>
  local msg=$1; shift
  G add -- "$@" || exit 2
  G commit -q -m "$msg" || exit 2
  G rev-parse HEAD
}

commit_staged() {  # commit_staged <msg> -- for a change git has already staged
  local msg=$1
  G commit -q -m "$msg" || exit 2
  G rev-parse HEAD
}

# `|| exit 2` inside $( ) leaves the SUBSHELL, not this fixture, so a scenario
# that fails to build hands the cases an empty revision and every one of them
# reports a verdict about nothing. Measured on 2026-08-28: `git mv` had already
# staged both halves of the rename, the `git add --` that followed refused the
# source path with exit 128, and two cases read the gate's exit 2 as a verdict.
# Every revision this scenario builds is therefore checked before any case runs,
# and a scenario that did not build exits 2 -- never a pass, never an accusation.
require_rev() {  # require_rev <name> <value>
  case "$2" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) : ;;
    *) printf '%s: scenario control failed: %s is not a revision (got "%s")\n' \
         "$FIX" "$1" "$2" >&2
       exit 2 ;;
  esac
}

printf 'a\n' > "$REPO/docs/adrs/ADR-001.md"
C_ALONE=$(commit_now c1 docs/adrs/ADR-001.md)
printf 'a\n' > "$REPO/docs/adrs/ADR-002.md"
printf 'true\n' >> "$REPO/scripts/real.sh"
C_MEASURED=$(commit_now c2 docs/adrs/ADR-002.md scripts/real.sh)
printf 'a\n' > "$REPO/docs/adrs/ADR-003.md"
printf 'more\n' >> "$REPO/README.md"
C_UNMEASURED=$(commit_now c3 docs/adrs/ADR-003.md README.md)
printf 'a\n' > "$REPO/docs/adrs/ADR-004.md"
printf 'true\n' >> "$REPO/scripts/lib/deep.sh"
C_NESTED=$(commit_now c4 docs/adrs/ADR-004.md scripts/lib/deep.sh)
printf 'edit\n' >> "$REPO/docs/adrs/ADR-000-seed.md"
C_MODIFY=$(commit_now c5 docs/adrs/ADR-000-seed.md)
printf 'more\n' >> "$REPO/README.md"
C_NOADR=$(commit_now c6 README.md)
G mv notes/draft.md docs/adrs/ADR-005.md || exit 2
C_RENAME=$(commit_staged c7)
printf 'a\n' > "$REPO/docs/adrs/ADR-006.md"
printf '# comment only\n' >> "$REPO/scripts/real.py"
C_RESIDUE=$(commit_now c8 docs/adrs/ADR-006.md scripts/real.py)
require_rev C_ALONE "$C_ALONE"
require_rev C_MEASURED "$C_MEASURED"
require_rev C_UNMEASURED "$C_UNMEASURED"
require_rev C_NESTED "$C_NESTED"
require_rev C_MODIFY "$C_MODIFY"
require_rev C_NOADR "$C_NOADR"
require_rev C_RENAME "$C_RENAME"
require_rev C_RESIDUE "$C_RESIDUE"

CASES=(
  "adr_add_alone_rejected|1|OK|$C_ALONE"
  "adr_add_with_measured_accepted|0|OK|$C_MEASURED"
  "adr_add_with_unmeasured_rejected|1|OK|$C_UNMEASURED"
  "adr_add_with_nested_lookalike_rejected|1|OK|$C_NESTED"
  "adr_modify_only_accepted|0|OK|$C_MODIFY"
  "no_adr_change_accepted|0|OK|$C_NOADR"
  "adr_rename_in_rejected|1|OK|$C_RENAME"
  "residue_r1_comment_only_measured_edit_accepted|0|OK|$C_RESIDUE"
  "empty_declaration_adr_add_errors|2|EMPTY|$C_ALONE"
  "empty_declaration_non_adr_change_errors|2|EMPTY|$C_NOADR"
  "malformed_glob_declaration_errors|2|BADGLOB|$C_ALONE"
  "missing_declaration_errors|2|MISSING|$C_ALONE"
)

MUTANTS=(
  "MUT-A%    A*)    is_add=0 ;;%adr_add_alone_rejected"
  "MUT-R%    R*|C*) is_add=0 ;;%adr_rename_in_rejected"
  "MUT-M%    M*)    is_add=1 ;;%adr_modify_only_accepted"
  "MUT-MEASURED%  return 0%adr_add_with_unmeasured_rejected"
  "MUT-DIRBLIND%    if [ 0 -eq 0 ]; then%adr_add_with_nested_lookalike_rejected"
  "MUT-EMPTY%:%empty_declaration_adr_add_errors"
  "MUT-ACCEPT%exit 0%empty_declaration_non_adr_change_errors"
)

conf_for() {
  case "$1" in
    OK)      printf '%s' "$CONF_OK" ;;
    EMPTY)   printf '%s' "$CONF_EMPTY" ;;
    BADGLOB) printf '%s' "$CONF_BADGLOB" ;;
    MISSING) printf '%s' "$CONF_MISSING" ;;
    *)       printf '%s' "/nonexistent" ;;
  esac
}

gate_exit() {  # gate_exit <conf-token> <rev>
  local conf
  conf=$(conf_for "$1")
  ( cd "$REPO" && ADR_GATE_CONF="$conf" "$GATE" --commit "$2" ) > "$OUT" 2>&1
  return $?
}

run_table() {
  local entry name want ctok rev got
  for entry in "${CASES[@]}"; do
    IFS='|' read -r name want ctok rev <<< "$entry"
    gate_exit "$ctok" "$rev"; got=$?
    if [ "$got" -eq "$want" ]; then ok "$name"
    else bad "$name" "want exit $want, got $got"; fi
  done
}

staged_cases() {
  local got
  printf 'a\n' > "$REPO/docs/adrs/ADR-007.md"
  G add -- docs/adrs/ADR-007.md || exit 2
  ( cd "$REPO" && ADR_GATE_CONF="$CONF_OK" "$GATE" --staged ) > "$OUT" 2>&1
  got=$?
  if [ "$got" -eq 1 ]; then ok staged_adr_add_alone_rejected
  else bad staged_adr_add_alone_rejected "want exit 1, got $got"; fi
  printf 'true\n' >> "$REPO/scripts/real.sh"
  G add -- scripts/real.sh || exit 2
  ( cd "$REPO" && ADR_GATE_CONF="$CONF_OK" "$GATE" --staged ) > "$OUT" 2>&1
  got=$?
  if [ "$got" -eq 0 ]; then ok staged_adr_add_with_measured_accepted
  else bad staged_adr_add_with_measured_accepted "want exit 0, got $got"; fi
  G reset -q --hard HEAD || exit 2
  rm -f "$REPO/docs/adrs/ADR-007.md"
}

pipe_case() {
  local direct piped
  ( cd "$REPO" && ADR_GATE_CONF="$CONF_OK" "$GATE" --commit "$C_ALONE" ) > "$OUT" 2>&1
  direct=$?
  ( cd "$REPO" && ADR_GATE_CONF="$CONF_OK" "$GATE" --commit "$C_ALONE" ) 2>&1 | tail -n 1 > /dev/null
  piped=$?
  if [ "$direct" -eq 1 ] && [ "$piped" -eq 0 ]; then ok pipe_hides_gate_exit_measured
  else bad pipe_hides_gate_exit_measured "direct=$direct piped=$piped"; fi
}

rename_shape_case() {
  local rc
  G diff-tree --no-commit-id -r -M --name-status "$C_RENAME" > "$WORK/rn" 2>/dev/null
  rc=$?
  if [ "$rc" -ne 0 ]; then bad rename_in_reported_as_rename "git diff-tree exit $rc"; return; fi
  if grep -q '^R' "$WORK/rn"; then ok rename_in_reported_as_rename
  else bad rename_in_reported_as_rename "git reported no rename: R3 is untested here"; fi
}

# The shell's own expansion of the declared globs, intersected with what git
# tracks: what --list-measured must equal, derived by a different route.
expected_surface() {  # expected_surface <repo> <conf> <outfile>
  local repo=$1 cf=$2 out=$3 g f
  conf_values GLOB "$cf" > "$WORK/globs"
  git -C "$repo" ls-files | LC_ALL=C sort > "$WORK/tracked"
  ( cd "$repo" || exit 2
    while IFS= read -r g || [ -n "$g" ]; do
      [ -n "$g" ] || continue
      # shellcheck disable=SC2086  # the declared glob must expand: that is the point
      for f in $g; do [ -e "$f" ] && printf '%s\n' "$f"; done
    done < "$WORK/globs"
  ) | LC_ALL=C sort -u > "$WORK/expanded"
  LC_ALL=C comm -12 "$WORK/expanded" "$WORK/tracked" > "$out"
}

surface_cases() {
  local got
  expected_surface "$REPO" "$CONF_OK" "$WORK/exp.scenario"
  if grep -qx 'scripts/ghost.sh' "$WORK/expanded"; then
    ok untracked_file_is_matched_by_the_lint_glob
  else
    bad untracked_file_is_matched_by_the_lint_glob "the R4 control never reached its question"
  fi
  ( cd "$REPO" && ADR_GATE_CONF="$CONF_OK" "$GATE" --list-measured ) > "$WORK/got.scenario" 2>"$OUT"
  got=$?
  if [ "$got" -ne 0 ]; then
    bad list_measured_equals_shell_expansion "--list-measured exit $got"
  else
    LC_ALL=C sort -o "$WORK/got.scenario" "$WORK/got.scenario"
    if cmp -s "$WORK/got.scenario" "$WORK/exp.scenario"; then ok list_measured_equals_shell_expansion
    else
      bad list_measured_equals_shell_expansion "matcher and shell disagree"
      LC_ALL=C comm -3 "$WORK/got.scenario" "$WORK/exp.scenario"
    fi
  fi
  if grep -qx 'scripts/ghost.sh' "$WORK/got.scenario"; then
    bad list_measured_excludes_untracked "an untracked file entered the declared surface"
  else ok list_measured_excludes_untracked; fi
  if grep -qx 'scripts/lib/deep.sh' "$WORK/got.scenario"; then
    bad list_measured_excludes_nested_lookalike "a nested path matched a single-level glob"
  else ok list_measured_excludes_nested_lookalike; fi
}

real_tree_cases() {
  local want n got g
  git -C "$ROOT" ls-files -- "$(conf_values ADR_PREFIX "$CONF_REAL" | head -n 1)" > "$WORK/adrfiles" 2>/dev/null
  if [ -s "$WORK/adrfiles" ]; then ok adr_surface_has_members
  else bad adr_surface_has_members "no tracked file under the declared ADR prefix: the rule has no members"; fi

  want=$(conf_values LINT_LINES "$CONF_REAL" | head -n 1)
  n=$(lint_lines "$SUITE" | wc -l | tr -d ' ')
  if [ -n "$want" ] && [ "$n" = "$want" ]; then ok lint_line_extraction_is_not_vacuous
  else bad lint_line_extraction_is_not_vacuous "declared LINT_LINES=${want:-<none>}, extracted $n"; fi

  conf_values GLOB "$CONF_REAL" | LC_ALL=C sort -u > "$WORK/declared.globs"
  lint_globs "$SUITE" > "$WORK/suite.globs"
  if [ ! -s "$WORK/suite.globs" ]; then
    bad declared_globs_match_the_lint_lines "extracted no glob from the lint lines"
  elif cmp -s "$WORK/declared.globs" "$WORK/suite.globs"; then
    ok declared_globs_match_the_lint_lines
  else
    bad declared_globs_match_the_lint_lines "declaration and lint lines differ"
    LC_ALL=C comm -3 "$WORK/declared.globs" "$WORK/suite.globs"
  fi

  # Negative control: the same extractor over a doctored copy must NOT agree.
  sed 's@py_compile@py_compile docs/*.sh@' "$SUITE" > "$WORK/suite.doctored"
  if cmp -s "$SUITE" "$WORK/suite.doctored"; then
    bad doctored_lint_line_breaks_parity "the doctoring changed nothing: this control proves nothing"
  else
    lint_globs "$WORK/suite.doctored" > "$WORK/doctored.globs"
    if cmp -s "$WORK/declared.globs" "$WORK/doctored.globs"; then
      bad doctored_lint_line_breaks_parity "an added glob left the parity assertion green"
    else ok doctored_lint_line_breaks_parity; fi
  fi

  while IFS= read -r g || [ -n "$g" ]; do
    [ -n "$g" ] || continue
    if git -C "$ROOT" ls-files -- "$g" | grep -q .; then :
    else bad every_declared_glob_has_a_tracked_member "no tracked file matches $g"; return; fi
  done < "$WORK/declared.globs"
  ok every_declared_glob_has_a_tracked_member

  expected_surface "$ROOT" "$CONF_REAL" "$WORK/exp.real"
  ( cd "$ROOT" && "$GATE" --list-measured ) > "$WORK/got.real" 2>"$OUT"
  got=$?
  if [ "$got" -ne 0 ]; then
    bad real_list_measured_equals_shell_expansion "--list-measured exit $got"
  else
    LC_ALL=C sort -o "$WORK/got.real" "$WORK/got.real"
    if cmp -s "$WORK/got.real" "$WORK/exp.real"; then ok real_list_measured_equals_shell_expansion
    else
      bad real_list_measured_equals_shell_expansion "matcher and shell disagree on this tree"
      LC_ALL=C comm -3 "$WORK/got.real" "$WORK/exp.real"
    fi
  fi
}

run_mutants() {
  local entry marker repl kcase dst e2 name want ctok rev got found f0
  cp "$GATE_REAL" "$WORK/gate.null" || exit 2
  chmod +x "$WORK/gate.null" || exit 2
  GATE="$WORK/gate.null"
  f0=$FAILN
  run_table
  if [ "$FAILN" -eq "$f0" ]; then ok mutant_null_control_green
  else bad mutant_null_control_green "the unmutated copy is not green: the harness proves nothing"; fi
  for entry in "${MUTANTS[@]}"; do
    IFS='%' read -r marker repl kcase <<< "$entry"
    dst="$WORK/gate.$marker"
    sed "s@^.*# ${marker}\$@${repl}  # ${marker}@" "$GATE_REAL" > "$dst" || exit 2
    chmod +x "$dst" || exit 2
    if cmp -s "$GATE_REAL" "$dst"; then
      bad "mutant_${marker}" "the mutation changed nothing: marker absent from the gate"
      continue
    fi
    found=0
    for e2 in "${CASES[@]}"; do
      IFS='|' read -r name want ctok rev <<< "$e2"
      [ "$name" = "$kcase" ] || continue
      found=1
      GATE="$dst"
      gate_exit "$ctok" "$rev"; got=$?
      if [ "$got" -eq "$want" ]; then bad "mutant_${marker}" "survived $kcase (exit $got)"
      else ok "mutant_${marker}_dead_by_${kcase}"; fi
      break
    done
    [ "$found" -eq 1 ] || bad "mutant_${marker}" "declared killing case $kcase is not in the table"
  done
  GATE=$GATE_REAL
}

run_table
staged_cases
pipe_case
rename_shape_case
surface_cases
real_tree_cases
if [ "$MUT_ARM" -eq 1 ]; then run_mutants; fi

printf '%s: pass=%d fail=%d\n' "$FIX" "$PASS" "$FAILN"
if [ "$FAILN" -gt 0 ]; then exit 1; fi
exit 0
