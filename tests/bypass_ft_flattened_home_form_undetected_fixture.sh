#!/usr/bin/env bash
# FT-28 -- flattened-home-form-undetected. privacy-lint-user-paths asks exactly
# one question of every tracked file -- does it carry the home prefix spelled
# with path separators -- and a path whose separators have been rewritten
# answers no while carrying the same private identifier, character for
# character, in the same file. The two spellings are one fact about one machine;
# only one of them is looked for, so the claim can be green over a tree that is
# full of the other. This row holds the unlooked-for spelling visible.
#
# The separator spelling is not quoted in that sentence, and the omission is the
# subject restated: the first draft of this header quoted it, and the claim this
# file is about went RED on this file. A detector may not be the exposure.
#
# THE SURFACE is the one the claim itself presides over: every tracked file,
# minus the same four pathspec exclusions, reproduced below. They are repeated
# rather than derived because the alternative is a row that measures a wider
# surface than the claim and accuses it of exposure it never took on -- and a
# row measuring a NARROWER one, which would be the failure that matters, is
# caught by the same repetition being visible in both places.
#
# NEITHER SPELLING IS WRITTEN DOWN HERE, and that is not fastidiousness. A
# detector that must state the string it hunts publishes that string in the
# tracked file whose purpose is to remove it, and the detector becomes the leak
# it was written to close. Both spellings are COMPUTED from the running process,
# for the same reason `homepath` is a computed class in scripts/statement_lint.py
# and can never be a declared one: a declaration cannot exempt what no
# declaration is able to name.
#
# STATES. RED (exit 1): at least one tracked file inside the measured surface
# carries the home path in either spelling. GREEN (exit 0): none does. BROKEN
# (exit 2): a control below did not behave, so this run never established what
# the row measures -- that is not a verdict about this repository, and it is
# cleared by realigning the fixture by hand, never by re-running it.
#
# Observed RED against the real tracked tree at f1e2f47 on 2026-08-18, before
# this file was registered: 40 files, 396 occurrences of the flattened spelling,
# 0 of the separator spelling -- which is precisely the shape that keeps
# privacy-lint-user-paths green while the material sits in the tree.
set -u

FLAG_OCC=0

# The two spellings, computed. The flattening is the one Claude Code applies to
# a project path when it uses that path as a directory NAME: every separator
# becomes a hyphen. Nothing here is a guess about the private value -- $HOME is
# whatever the process was given.
HOME_SEP="$HOME"
HOME_FLAT="$(printf '%s' "$HOME" | tr '/' '-')"

# A degenerate $HOME would make both patterns match half the tree and turn this
# row into an accusation about nothing. The bound is the same one
# scripts/statement_lint.py applies to its computed classes.
if [ "${#HOME_SEP}" -lt 4 ] || [ "$HOME_SEP" = "/" ]; then
  echo "BROKEN: \$HOME is ${#HOME_SEP} characters; a pattern that short measures noise, not exposure" >&2
  exit 2
fi
if [ "$HOME_FLAT" = "$HOME_SEP" ]; then
  echo "BROKEN: the flattened spelling equals the separator spelling, so this row has only one pattern and cannot be about two" >&2
  exit 2
fi

# `-e` and not a bare pattern: the flattened spelling begins with the hyphen the
# separator became, and git would read it as an option.
count_files() {
  git -C "$1" grep -lF -e "$2" -- \
    ':!docs/adrs/' ':!*.example.json' ':!workers.local.json' ':!.verity/claims.json' \
    2>/dev/null | grep -c . || true
}
count_occ() {
  git -C "$1" grep -oF -e "$2" -- \
    ':!docs/adrs/' ':!*.example.json' ':!workers.local.json' ':!.verity/claims.json' \
    2>/dev/null | grep -c . || true
}

# ---------------------------------------------------------------- the controls
#
# Four arms in a scratch repository, and every one of them exists to make this
# row's assertion MOVE. A detector that cannot be shown finding something, and
# then shown finding nothing, reports its own opinion rather than the tree's
# contents; and arm 3 is the one that decides whether the row has a subject at
# all -- if the separator spelling could see the flattened material, there would
# be no blindness here to hold visible and this file should not exist.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft28.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
CTL="$WORK/ctl"
mkdir -p "$CTL"
git -C "$CTL" init -q
git -C "$CTL" config user.email t@example.invalid
git -C "$CTL" config user.name tester
git -C "$CTL" config commit.gpgsign false
git -C "$CTL" config tag.gpgsign false

printf 'a line with nothing of the kind anywhere in it\n' > "$CTL/clean.txt"
git -C "$CTL" add -- clean.txt
git -C "$CTL" commit -qm "clean"

# Arm 1: the negative control. Nothing planted, nothing found -- in both
# spellings. A detector that answers RED here answers RED always.
if [ "$(count_occ "$CTL" "$HOME_FLAT")" != "0" ] || [ "$(count_occ "$CTL" "$HOME_SEP")" != "0" ]; then
  echo "BROKEN: the negative control matched a repository with nothing planted in it" >&2
  exit 2
fi

# Arm 2: the positive control. Three occurrences of the flattened spelling in
# two files, and the detector must report exactly three in exactly two -- a
# count, not a boolean, because the RED below is reported as a count and an
# arm that only proves non-zero does not qualify it.
printf 'x%sy\nz%sw\n' "$HOME_FLAT" "$HOME_FLAT" > "$CTL/planted-a.txt"
printf 'q%s\n' "$HOME_FLAT" > "$CTL/planted-b.txt"
git -C "$CTL" add -- planted-a.txt planted-b.txt
git -C "$CTL" commit -qm "planted"
if [ "$(count_files "$CTL" "$HOME_FLAT")" != "2" ] || [ "$(count_occ "$CTL" "$HOME_FLAT")" != "3" ]; then
  echo "BROKEN: positive control wanted 2 files / 3 occurrences, detector said $(count_files "$CTL" "$HOME_FLAT") / $(count_occ "$CTL" "$HOME_FLAT")" >&2
  exit 2
fi

# Arm 3: the blindness itself, and the reason this row has a subject. The
# claim's own predicate is run verbatim against the repository arm 2 just
# planted. It must find NOTHING. If it finds something, the separator spelling
# already covers the flattened material, this row measures a gap that is not
# there, and saying RED below would be an accusation with no defect under it.
if git -C "$CTL" grep -qF -e "$HOME_SEP" -- \
  ':!docs/adrs/' ':!*.example.json' ':!workers.local.json' ':!.verity/claims.json' 2>/dev/null; then
  echo "BROKEN: the separator spelling matched the flattened material, so there is no blindness for this row to hold visible" >&2
  exit 2
fi

# Arm 4: the exclusion parity. The same material under one of the four excluded
# pathspecs must NOT be counted, or this row is measuring a wider surface than
# the claim it is about and its RED would accuse the wrong tree.
mkdir -p "$CTL/docs/adrs"
printf 'excluded %s\n' "$HOME_FLAT" > "$CTL/docs/adrs/ADR-000-excluded.md"
git -C "$CTL" add -- docs/adrs/ADR-000-excluded.md
git -C "$CTL" commit -qm "excluded"
if [ "$(count_occ "$CTL" "$HOME_FLAT")" != "3" ]; then
  echo "BROKEN: exclusion parity -- material under an excluded pathspec was counted (detector said $(count_occ "$CTL" "$HOME_FLAT"), want 3)" >&2
  exit 2
fi

# ------------------------------------------------------------- the measurement
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "BROKEN: $ROOT is not a work tree, so the tracked surface was never read" >&2
  exit 2
fi

SEP_FILES="$(count_files "$ROOT" "$HOME_SEP")"
SEP_OCC="$(count_occ "$ROOT" "$HOME_SEP")"
FLAT_FILES="$(count_files "$ROOT" "$HOME_FLAT")"
FLAT_OCC="$(count_occ "$ROOT" "$HOME_FLAT")"
FLAG_OCC=$((SEP_OCC + FLAT_OCC))

# The counts are the report and the counts are all of it. Naming a file here
# would be useful and naming a line would be more useful still, and both would
# put a locator for the private value into the suite's own output, which is
# published wherever a run log is. Completeness is reportable; identity is not.
if [ "$FLAG_OCC" -ne 0 ]; then
  echo "RED: the tracked surface carries the operator home path -- separator spelling: $SEP_FILES file(s), $SEP_OCC occurrence(s); flattened spelling: $FLAT_FILES file(s), $FLAT_OCC occurrence(s)" >&2
  exit 1
fi

echo "GREEN: no tracked file inside the measured surface carries the operator home path in either spelling"
exit 0
