#!/usr/bin/env bash
# surface-charges-untouched-occurrences -- the added-file rule of
# scripts/statement_lint.py --surface must charge a change for what it ADDS,
# and it must charge a COMMIT. The subject here is the WIDTH of that rule and
# the OBJECT it reads, never the overall verdict of any one invocation: this
# fixture asks what the boundary charges a file for and which bytes it charges,
# not whether this repository is green today.
#
# TWO DEFECTS, and an arm for each, because they are independent and a
# falsifier that measured one would certify half a repair as a whole one.
#
#   THE WIDTH.  what the claim decides -- zero NEW occurrences of a private
#               class on the surface a change adds. What the rule measures --
#               for every tracked file whose WHOLE bytes differ from the
#               baseline, the count of class literals in the WHOLE file.
#               Membership in the charged set is whole-file byte inequality and
#               the charge is taken over the whole blob, so a document the
#               baseline already counts and already ADMITS is charged with every
#               occurrence it has always carried the moment one byte of it
#               moves for an unrelated reason.
#   THE OBJECT. the measured side is read from the WORKING TREE. git records no
#               working tree, so the same commit, the same subject and the same
#               declaration can produce two opposite verdicts an hour apart, and
#               a receipt that pins gitHeadSha does not identify what it judged.
#               What a push carries is commits.
#
# THE SPECIMEN IS REAL AND IS NOT SPELLED HERE. The width arms are seeded from
# blobs this repository actually carries, extracted BY DIGEST with `git
# cat-file blob` and never from bytes typed into this file: one tracked
# document at two revisions whose class count is identical and whose bytes are
# not. A fixture that had to spell the strings it guards would be an instance
# of what the boundary refuses, so every class literal below is ASSEMBLED, for
# the same reason scripts/statement_lint.py assembles its own at LITERAL_USERS.
#
# SEVEN ARMS, one scratch repository each:
#   1 PASSAGE    the specimen's bytes change at HEAD and its count does not
#                -> want accept (0). The arm the width repair has to move.
#   2 REFUSAL    the same bytes plus one appended occurrence
#                -> want refusal (1), today and after any repair.
#   3 UNTOUCHED  the specimen sits at HEAD carrying its whole count and is not
#                edited; the commit adds a file that carries nothing
#                -> want accept (0).
#   4 COUNTING   a file the baseline does not have at all, carrying one
#                occurrence -> want refusal (1).
#   5 COMMIT     the specimen is byte-identical at the baseline and at HEAD,
#                and one occurrence is written into the WORKING TREE and never
#                staged -> want accept (0). The arm the object repair has to
#                move, and the only arm in which the working tree and HEAD
#                disagree at all.
#   6 PER-CLASS  one file, one class losing an occurrence and another gaining
#                one -> want refusal (1). A charge kept per FILE instead of per
#                CLASS nets these to zero and accepts a leak.
#   7 REMOVAL    a commit whose only effect is a class count that falls
#                -> want accept (0). A delta charged without the max(0, ...)
#                clamp refuses a change that removed material.
#
# WHY 3, 4, 6 AND 7 ARE HERE. Arms 1 and 5 on their own are satisfied by a
# boundary that stopped looking: a rule charging nothing accepts both for the
# wrong reason, and that is the failure a repair of this shape can actually
# introduce. Arm 4 is the counting control -- the baseline count is zero there,
# so the charge is the whole count, and a detector that stops counting accepts
# where refusal is wanted. Arm 3 is the control on the other side: the specimen
# is present, carrying every occurrence, and is not charged because it did not
# move. Arms 6 and 7 hold the two ways a delta can be computed and still be
# wrong -- collapsed across classes, and unclamped on removals.
#
# THE PREFLIGHT IS PART OF THE MEASUREMENT. Two of the boundary's classes are
# COMPUTED from the running process -- the operator's home path and this host's
# short name -- and no invocation can decline them. Arm 1 is green only if
# EVERY class, computed ones included, has the same count in the two pinned
# blobs, so a host whose short name happens to occur in one blob and not the
# other would turn arm 1 red for a reason that has nothing to do with the
# subject. That is an arm that never reached its question, so it is checked
# before any arm runs and reported as UNMEASURED by class name, never as a
# failed arm and never by printing the literal it counted.
#
# EVERY ARM ASSERTS ITS OWN SETUP. `git commit` failing silently, or a copy
# that did not land, would leave an arm measuring an empty delta and reporting
# `ok` for it -- a green that means nothing happened. So each arm states what
# must be true of its own repository before the boundary is asked: that the
# path it edited really differs between the baseline and HEAD, or really does
# not, or really differs between HEAD and the working tree. A setup that did
# not hold is UNMEASURED, not a verdict.
#
# THE RESIDUE, NAMED AND NOT MEASURED. A per-file delta count cannot see one
# occurrence added and one removed of THE SAME class in the same file in the
# same commit: the count is unchanged and the charge is zero. Arm 6 catches the
# cross-class form of that; the same-class form needs an anchor on the lines a
# diff adds, and adopting one is a decision and not an edit. It is left
# standing rather than asserted correct -- an arm claiming that case accepted
# would be this fixture certifying the blind spot as a decision.
#
# STATES. GREEN (exit 0): all seven arms as wanted. RED (exit 1): any arm
# differs -- the boundary charged a file for what it did not add, stopped
# charging what a change does add, or read a verdict off bytes no commit
# carries. UNMEASURED (exit 2): python3, git or the boundary is absent, the
# boundary does not implement --surface, this repository no longer carries the
# two blobs this fixture pins, those blobs no longer carry the counts it
# asserts, or an arm's own setup did not hold. That is not a pass and not a
# fail: the arm never reached its own question.
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
LINT="${STATEMENT_LINT:-$HERE/scripts/statement_lint.py}"
PACK="${SURFACE_PACK:-$HERE}"

broken() { echo "UNMEASURED: $*" >&2; exit 2; }

command -v python3 >/dev/null 2>&1 || broken "python3 absent"
command -v git     >/dev/null 2>&1 || broken "git absent"
[ -f "$LINT" ] || broken "boundary not found at $LINT"

# ASSEMBLED, NOT SPELLED. This file is tracked and therefore sits inside the
# surface the boundary measures; a control that spelled the class it guards
# would be an instance of what it refuses.
V="verifiable""-intel"
S="harness""-smoke"
VN="Obsidian""-Vault"

# The specimen, pinned by content and not by revision: a blob digest names the
# same bytes whatever HEAD does later, which is the only way a fixture about a
# baseline can outlive the branch it was written on.
ADR_REL="docs/adrs/ADR-018-algorithm-as-data-tagged-digests-and-a-declared-canonical-form.md"
BLOB_BASE=45bb8f3a2069c524de964c177b9a9bf1cb1a285c
BLOB_HEAD=030fcfc57a6098b8f15d91d0c3edf1284e8d1337
WANT_OCC=5

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft_surface_width.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

FAILS=0

SPEC_BASE="$WORK/specimen.base"
SPEC_HEAD="$WORK/specimen.head"

git -C "$PACK" cat-file blob "$BLOB_BASE" > "$SPEC_BASE" 2>/dev/null \
  || broken "$PACK does not carry blob $BLOB_BASE"
git -C "$PACK" cat-file blob "$BLOB_HEAD" > "$SPEC_HEAD" 2>/dev/null \
  || broken "$PACK does not carry blob $BLOB_HEAD"

cmp -s "$SPEC_BASE" "$SPEC_HEAD" \
  && broken "the two pinned blobs are byte-identical, so there is no passage arm left to measure"

# The preflight, in one place and in the boundary's own counting rule. It
# reports CLASS NAMES and counts, never the literal it counted: two of these
# classes are facts about this machine, and a control that printed them would
# publish what it exists to keep off the surface.
preflight="$(python3 - "$SPEC_BASE" "$SPEC_HEAD" "$WANT_OCC" \
                      workerrepo "$V" workerrepo "$S" vaultname "$VN" <<'PY'
import os
import socket
import sys

base = open(sys.argv[1], "rb").read()
head = open(sys.argv[2], "rb").read()
want = int(sys.argv[3])
rest = sys.argv[4:]
declared = [(rest[i], rest[i + 1], True) for i in range(0, len(rest), 2)]

# The two classes _classes() computes from the running process, on the same
# conditions it applies, so this preflight sees exactly what an arm will.
computed = []
home = os.path.expanduser("~")
if home and home != "~" and len(home) >= 4:
    computed.append(("homepath", home, False))
short = socket.gethostname().split(".")[0]
if short and len(short) >= 4:
    computed.append(("hostname", short, True))


def count(blob, literal, ci):
    hay = blob.lower() if ci else blob
    needle = literal.encode().lower() if ci else literal.encode()
    n, at = 0, 0
    while True:
        i = hay.find(needle, at)
        if i < 0:
            return n
        n += 1
        at = i + 1


problems = []
totals = [0, 0]
for name, literal, ci in declared + computed:
    a, b = count(base, literal, ci), count(head, literal, ci)
    if name == "workerrepo":
        totals[0] += a
        totals[1] += b
    if a != b:
        problems.append(
            "class %s occurs %d time(s) in the baseline blob and %d in the head blob; "
            "the passage arm is only about a count that does NOT move" % (name, a, b))
if totals != [want, want]:
    problems.append(
        "the pinned blobs no longer carry the count this fixture is about "
        "(workerrepo base=%d head=%d, wanted %d in each)" % (totals[0], totals[1], want))
print("\n".join(problems))
PY
)" || broken "the preflight could not run"
[ -z "$preflight" ] || broken "$preflight"

# new_repo NAME [SEED] -- one clean baseline commit, a `baseline` ref pointing
# at it, and a remote, because a repository with none has no public surface and
# the boundary returns before measuring anything. SEED, when given, is the
# specimen planted at the baseline.
new_repo() {
  local d="$WORK/$1"
  mkdir -p "$d/docs/adrs" || return 1
  git -C "$d" init -q 2>/dev/null || return 1
  git -C "$d" config user.email f@example.invalid
  git -C "$d" config user.name  fixture
  git -C "$d" config commit.gpgsign false
  printf 'a harness, and nothing private in it\n' > "$d/README.md"
  git -C "$d" add -- README.md
  if [ -n "${2:-}" ]; then
    cp -- "$2" "$d/$ADR_REL"
    git -C "$d" add -- "$ADR_REL"
  fi
  git -C "$d" commit -q -m baseline
  git -C "$d" branch -f baseline HEAD
  git -C "$d" remote add origin https://example.invalid/x.git
  printf '%s' "$d"
}

# commit_arm DIR REL -- stage exactly this path and commit it. Explicit paths
# only, and neither step may fail quietly: an arm whose commit did not happen
# measures an empty delta and reports `ok` for it.
commit_arm() {
  git -C "$1" add -- "$2" || broken "could not stage $2 in $1"
  git -C "$1" commit -q -m added || broken "could not commit $2 in $1"
  return 0
}

# rebase_baseline DIR -- move the `baseline` ref onto HEAD, for the arms whose
# baseline has to carry material of its own.
rebase_baseline() {
  git -C "$1" branch -f baseline HEAD || broken "could not move baseline in $1"
  return 0
}

# The three setup assertions. Each names what its arm needs to be true of its
# own repository BEFORE the boundary is asked, so a green can never mean
# nothing happened.
assert_moved() {  # assert_moved DIR REL LABEL
  git -C "$1" diff --quiet baseline HEAD -- "$2" \
    && broken "arm $3 left $2 identical between the baseline and HEAD; it would have measured an empty delta"
  return 0
}

assert_same() {  # assert_same DIR REL LABEL
  git -C "$1" diff --quiet baseline HEAD -- "$2" \
    || broken "arm $3 moved $2 between the baseline and HEAD; that arm is only about a specimen that did not move"
  return 0
}

assert_dirty() {  # assert_dirty DIR REL LABEL
  git -C "$1" diff --quiet HEAD -- "$2" \
    && broken "arm $3 left $2 identical to HEAD in the working tree; the uncommitted edit this arm is about did not happen"
  return 0
}

# run_arm LABEL DIR WANT_RC -- every arm is asked under the SAME three classes,
# so no arm's verdict depends on which classes it happened to declare.
run_arm() {
  local label="$1" dir="$2" want="$3" out rc
  out="$(python3 "$LINT" --surface --repo "$dir" --baseline baseline \
           --class "workerrepo=I:$V" --class "workerrepo=I:$S" \
           --class "vaultname=I:$VN" 2>&1)"; rc=$?
  if [ "$rc" -eq 2 ]; then
    echo "UNMEASURED: arm $label could not run: $out" >&2
    exit 2
  fi
  if [ "$rc" -ne "$want" ]; then
    printf 'FAIL arm %s: wanted exit %s, got %s\n' "$label" "$want" "$rc"
    printf '%s\n' "$out" | sed 's/^/    /'
    FAILS=$((FAILS + 1))
  else
    printf 'ok   arm %s: exit %s as wanted\n' "$label" "$rc"
  fi
}

# --- 1. PASSAGE: the bytes move at HEAD, the count does not -----------------
D="$(new_repo passage "$SPEC_BASE")" || broken "git init failed"
cp -- "$SPEC_HEAD" "$D/$ADR_REL"
commit_arm "$D" "$ADR_REL"
assert_moved "$D" "$ADR_REL" "1 PASSAGE"
run_arm "1 PASSAGE    bytes differ at HEAD, count unchanged" "$D" 0

# --- 2. REFUSAL: the same bytes and one occurrence more ---------------------
D="$(new_repo refusal "$SPEC_BASE")"
cp -- "$SPEC_HEAD" "$D/$ADR_REL"
printf 'A later line naming %s once more.\n' "$S" >> "$D/$ADR_REL"
commit_arm "$D" "$ADR_REL"
assert_moved "$D" "$ADR_REL" "2 REFUSAL"
run_arm "2 REFUSAL     bytes differ at HEAD, count up by one" "$D" 1

# --- 3. UNTOUCHED: the specimen is carried and not edited -------------------
D="$(new_repo untouched "$SPEC_BASE")"
printf 'a document about the boundary, naming nothing\n' > "$D/docs/x.md"
commit_arm "$D" docs/x.md
assert_same "$D" "$ADR_REL" "3 UNTOUCHED"
run_arm "3 UNTOUCHED   specimen carried, commit adds nothing private" "$D" 0

# --- 4. COUNTING: a file the baseline does not have at all ------------------
D="$(new_repo counting)"
printf 'the pool for this run was named %s\n' "$V" > "$D/docs/new.md"
commit_arm "$D" docs/new.md
assert_moved "$D" docs/new.md "4 COUNTING"
run_arm "4 COUNTING    a file absent from the baseline, carrying one" "$D" 1

# --- 5. COMMIT: the occurrence exists on disk and in no commit --------------
# The specimen is byte-identical at the baseline and at HEAD, so the width rule
# has nothing to charge here whatever form it takes; the only thing that can
# move this arm is WHICH BYTES the boundary reads. That is the point: this arm
# fails for a boundary that reads the working tree and passes for one that
# reads the commit, and it is the only arm in which the two disagree.
D="$(new_repo commit "$SPEC_BASE")"
printf 'an unrelated note\n' > "$D/docs/other.md"
commit_arm "$D" docs/other.md
assert_same "$D" "$ADR_REL" "5 COMMIT"
printf 'A line naming %s, written and never staged.\n' "$V" >> "$D/$ADR_REL"
assert_dirty "$D" "$ADR_REL" "5 COMMIT"
run_arm "5 COMMIT      one occurrence in the working tree, in no commit" "$D" 0

# --- 6. PER-CLASS: one class down by one, another up by one -----------------
D="$(new_repo perclass)"
printf 'the note named %s once\n' "$VN" > "$D/docs/pair.md"
commit_arm "$D" docs/pair.md
rebase_baseline "$D"
printf 'the note named %s once\n' "$V" > "$D/docs/pair.md"
commit_arm "$D" docs/pair.md
assert_moved "$D" docs/pair.md "6 PER-CLASS"
run_arm "6 PER-CLASS   one class loses one, another gains one" "$D" 1

# --- 7. REMOVAL: a class count that only falls ------------------------------
D="$(new_repo removal)"
printf 'named %s, then %s, then %s\n' "$V" "$V" "$V" > "$D/docs/shrink.md"
commit_arm "$D" docs/shrink.md
rebase_baseline "$D"
printf 'named %s once\n' "$V" > "$D/docs/shrink.md"
commit_arm "$D" docs/shrink.md
assert_moved "$D" docs/shrink.md "7 REMOVAL"
run_arm "7 REMOVAL     a class count that only falls" "$D" 0

if [ "$FAILS" -ne 0 ]; then
  printf 'RED: %s arm(s) did not match\n' "$FAILS"
  exit 1
fi
printf 'GREEN: seven arms, each as wanted\n'
exit 0
