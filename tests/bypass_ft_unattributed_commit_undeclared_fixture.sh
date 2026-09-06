#!/usr/bin/env bash
# FT-37 attribution-unattributed-commit-set -- the set of UNATTRIBUTED commits
# reachable from HEAD must equal, EXACTLY, a set declared by enumeration in a
# tracked baseline file. Not its size: its membership.
#
# WHERE THE BASELINE LIVES, and why it is not a file of its own. INTEGRITY.md
# is the only tracked integrity declaration this repository has, and it is
# added by the push this gate ships in. A second declaration at the root would
# be a second door on the same room -- two places to look, and one of them
# eventually stale. The judge reads $ROOT/INTEGRITY.md and nothing else.
#
# DECLARED UNMEASURED-BASELINE in the commit that installs it, and observed so.
# INTEGRITY.md exists in this commit; the section it will carry does not. A
# gate that shipped GREEN beside an input nobody has written would be
# certifying a decision no file records, so the judge spends a distinct exit on
# it (3) and the register declares EXIT3. A PRESENT FILE WITH NO SECTION IS NOT
# AN EMPTY ENUMERATION, and arm B-nosection holds that door shut: the two
# differ by exactly the decision this gate exists to make visible.
#
# THE ENUMERATION FORM is `.git-blame-ignore-revs`: one full sha per line, a
# '#' at the start of a line for a comment, and free text after the sha on the
# same line ignored. The judge takes the FIRST whitespace-separated token of
# every surviving line, so a row may carry its own short-sha, date and subject
# beside the sha it declares and the record stays readable to a person without
# a second lookup. A COMMENT IS NOT A DECLARATION: arm C-commented-out takes a
# true member of the observed set, prefixes it with '# ', and requires the gate
# to go RED. Commenting a line out withdraws the exemption; it does not hide
# the commit.
#
# WHAT IS "UNATTRIBUTED", and why it is DERIVED and not asserted. The judge
# reads %G? for every commit `git rev-list HEAD` returns and builds the
# distribution before it classifies anything. The map it then applies:
#
#   %G? = G   attributed    good signature, signer in this host's allowed_signers
#   %G? = U   attributed    good signature, signer NOT in this host's allowed
#                           signers -- the SAME commits, read on a host that
#                           has no allowed_signers file
#   %G? = N   unattributed  no signature at all
#   anything else           the map does not cover it -> FIXTURE BROKEN (4)
#
# G AND U ARE THE SAME COMMITS, and collapsing them is what makes this gate
# host-independent rather than a reading of one laptop's ~/.config. Measured on
# this tree at the basis that installs this file: with the allowed_signers file
# the distribution is 173 G + 18 N; with gpg.ssh.allowedSignersFile pointed at a
# path that does not exist it is 173 U + 18 N, and the set of N commits is
# byte-identical across the two. The allowed_signers file lives OUTSIDE the
# repository, so a judge that demanded G would go red on every clone that lacks
# it and would be measuring the host, not the history. B, E, X, Y and R are
# absent from this tree and are deliberately NOT bucketed: silently folding a
# bad or expired signature into either class is a decision, and this file will
# not take it on the operator's behalf.
#
# TWO KEYS, ONE CLASS. This repository signs with two ssh keys -- the operator's
# and agent-cc@harness-pack.invalid -- and one of them yields a grey
# "Unverified" badge on GitHub because that host does not know it. That badge is
# GitHub's key registry speaking, not %G?: both keys answer G here and U on a
# bare clone, and both are ATTRIBUTED. The judge prints every signer identity it
# saw so the two-key fact is visible in the record rather than assumed.
#
# SCOPE IS HEAD-REACHABLE, NOT origin/main..HEAD. After a push origin/main
# moves, and a gate scoped to the unpushed range would quietly stop measuring
# every commit it just published. `git rev-list HEAD` is the same set before and
# after a push, so an exemption that holds today holds tomorrow.
#
# SET-IDENTITY, NEVER CARDINALITY. Observed and declared must be EQUAL. A
# declared set that is a strict superset of the observed one is RED; a strict
# subset is RED; and a baseline that swaps one member for another is RED at
# unchanged cardinality -- arm S exists to prove exactly that, because a gate
# that compared two counts would pass it.
#
# THE KEY IS THE SHA, WITH THE PATCH-ID AS FALLBACK. A declared sha that is not
# among the observed unattributed commits is not immediately a fault: history
# gets rewritten and this repository keeps refs/backup/* precisely because it
# does. So the judge asks, in this order:
#   1  is the declared sha itself an unattributed commit?     -> covered
#   2  is it a commit this repository does not have at all?   -> BOGUS, and RED.
#      A baseline may not exempt something that is not here.
#   3  does its patch-id (`git show <sha> | git patch-id --stable`) match the
#      patch-id of an observed unattributed commit?           -> covered, and
#      the judge prints STALE-SHA: the exemption survived the rewrite and the
#      baseline is the thing that is out of date, not the history.
#   4  neither                                                -> UNMEASURED-
#      STALE (6). Not GREEN and not RED: the judge cannot tell an exemption
#      that was rewritten beyond recognition from one that was never real.
#
# EXIT CONTRACT. Six codes, all distinct, and GREEN shares none of them with a
# non-measurement. An exit that cannot separate "the sets are equal" from "no
# set was read" reports a vacuum as a pass.
#   0  GREEN               observed set == declared set
#   1  RED                 they differ, in either direction
#   2  UNMEASURED-SCOPE    no commit was read at all
#   3  UNMEASURED-BASELINE the baseline file is absent, unreadable, or carries
#                          no enumeration block
#   6  UNMEASURED-STALE    a declared commit resolved by neither sha nor patch-id
#   4  FIXTURE BROKEN      a control arm did not answer what it must, or the
#                          classification map did not cover an observed %G?
#
# TEN ARMS, each printed with its own exit:
#   P  positive control, on a CLONE of this repository: the measured set
#      declared verbatim answers GREEN, and ONE further unsigned commit turns
#      it RED. The clone carries no allowed_signers, so this arm is also where
#      the G/U collapse is exercised rather than argued.
#   N  negative control, on the real tree with a synthetic-but-correct
#      baseline -> GREEN, and it must print scanned>0 and delta=0. The baseline
#      is built by an INDEPENDENT `git log | awk` and never by the judge, so the
#      arm is not the judge agreeing with itself.
#   S  set-identity: one declared sha replaced by a well-formed sha no object
#      answers to -> RED at unchanged cardinality.
#   A  anti-vacuity BY GENERATION: a scratch repository in which every commit is
#      signed and the baseline declares the EMPTY set -> GREEN with scanned>0
#      printed. A green that came from never taking the measurement cannot pass
#      for this one.
#   R  rewrite resilience: a scratch repository rebased so that every sha moves
#      -> the exemption holds through the patch-id, STALE-SHA is printed, and
#      the exit is 0.
#   Z  null cases: an absent baseline -> 3, and a repository with no commits
#      -> 2.
#   C  comment tolerance, in both directions. C-comment: a synthetic baseline
#      carrying '# ' lines between the shas and free text after each sha ->
#      GREEN, with `declared` equal to the number of sha rows and not to the
#      number of lines. C-commented-out: one true member of the observed set
#      prefixed with '# ' -> RED, naming that commit UNDECLARED. The second arm
#      is what keeps the first from being a licence to park a commit behind a
#      '#'.
#   B  the baseline's two degenerate shapes, which are not one shape. B-
#      nosection: a baseline file that exists and carries no sentinel pair -> 3,
#      never GREEN-over-zero-declared. B-empty: the sentinels present around an
#      empty block, on a tree that has unattributed commits -> RED. An empty
#      block IS a declaration -- it declares that nothing is exempt -- and on
#      this tree that declaration is false. Arm A is the SAME empty block on a
#      tree where it is true, read from the same file; the pair is what
#      separates "declared empty" from "read nothing".
#
# The arms sign with an EPHEMERAL key this fixture generates in its own scratch
# directory. Nothing is read from the operator's ~/.config and nothing is
# written outside the work directory, so the arms answer the same on any host
# with git and ssh-keygen.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ftuca.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

broken() { echo "FIXTURE BROKEN: $*" >&2; exit 4; }

cat > "$WORK/judge.py" <<'JUDGE'
"""Attribution gate: the unattributed set reachable from HEAD, against a
declared enumeration.

  judge.py --repo REPO --baseline FILE

Exits 0 GREEN, 1 RED, 2 UNMEASURED-SCOPE, 3 UNMEASURED-BASELINE,
6 UNMEASURED-STALE, 4 FIXTURE-BROKEN. The classification of %G? is derived
from the observed distribution and printed before it is applied.
"""
import argparse
import os
import re
import subprocess
import sys

ATTRIBUTED = {"G", "U"}
UNATTRIBUTED = {"N"}
BEGIN = "ACCEPTED-UNATTRIBUTED-BEGIN"
END = "ACCEPTED-UNATTRIBUTED-END"
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
US = "\x1f"


def out(s):
    sys.stdout.write(s + "\n")
    sys.stdout.flush()


def git(repo, *args):
    p = subprocess.run(["git", "-C", repo] + list(args),
                       capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def patch_id(repo, sha):
    p1 = subprocess.run(["git", "-C", repo, "show", sha],
                        capture_output=True, text=True)
    if p1.returncode != 0:
        return None
    p2 = subprocess.run(["git", "patch-id", "--stable"], input=p1.stdout,
                        capture_output=True, text=True)
    parts = p2.stdout.split()
    return parts[0] if parts else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--baseline", required=True)
    a = ap.parse_args()

    fmt = "--format=%H" + US + "%G?" + US + "%GS" + US + "%s"
    rc, so, _ = git(a.repo, "log", "HEAD", fmt)
    rows = [ln for ln in so.splitlines() if ln.strip()] if rc == 0 else []
    if rc != 0 or not rows:
        out("scanned: 0")
        out("verdict: UNMEASURED-SCOPE")
        return 2

    codes, subjects, dist, signers = {}, {}, {}, {}
    for ln in rows:
        f = ln.split(US)
        if len(f) != 4:
            out("verdict: FIXTURE-BROKEN")
            sys.stderr.write("unparsable log row: %r\n" % ln)
            return 4
        h, code, signer, subj = f
        codes[h] = code
        subjects[h] = subj
        dist[code] = dist.get(code, 0) + 1
        if signer:
            signers[signer] = signers.get(signer, 0) + 1

    out("scanned: %d" % len(codes))
    out("distribution: " + " ".join("%s=%d" % (k, dist[k])
                                    for k in sorted(dist)))
    for k in sorted(dist):
        if k in ATTRIBUTED:
            role = "attributed"
        elif k in UNATTRIBUTED:
            role = "unattributed"
        else:
            role = "UNCLASSIFIED"
        out("map: %%G?=%s -> %s (%d commits)" % (k, role, dist[k]))
    for s in sorted(signers):
        out("signer: %s x%d" % (s, signers[s]))

    unknown = sorted(k for k in dist
                     if k not in ATTRIBUTED and k not in UNATTRIBUTED)
    if unknown:
        out("verdict: FIXTURE-BROKEN")
        sys.stderr.write("the classification map does not cover %%G? code(s): "
                         "%s -- bucketing one is a decision this judge will "
                         "not take on its own\n" % ",".join(unknown))
        return 4

    observed = sorted(h for h, c in codes.items() if c in UNATTRIBUTED)
    out("unattributed: %d" % len(observed))

    if not os.path.isfile(a.baseline):
        out("baseline: absent -- %s" % a.baseline)
        out("verdict: UNMEASURED-BASELINE")
        return 3
    try:
        with open(a.baseline, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        out("baseline: unreadable -- %s" % exc)
        out("verdict: UNMEASURED-BASELINE")
        return 3
    if BEGIN not in text or END not in text:
        out("baseline: no enumeration block (%s / %s absent)" % (BEGIN, END))
        out("verdict: UNMEASURED-BASELINE")
        return 3

    # `.git-blame-ignore-revs` form: one full sha per line, a '#' at the
    # start of a line is a comment, and anything after the sha on the line is
    # ignored. The declaration is the FIRST whitespace token of a surviving
    # line; a commented line declares nothing at all.
    block = text.split(BEGIN, 1)[1].split(END, 1)[0]
    declared = []
    for ln in block.splitlines():
        t = ln.strip()
        if not t or t.startswith("#") or t.startswith("<!--") or t == "-->":
            continue
        tok = t.split()[0]
        if not SHA_RE.match(tok):
            out("baseline: malformed enumeration entry %r" % t)
            out("verdict: UNMEASURED-BASELINE")
            return 3
        declared.append(tok)
    out("declared: %d" % len(declared))

    obs_set = set(observed)
    covered, stale, bogus, unresolved = {}, [], [], []
    dups = sorted({d for d in declared if declared.count(d) > 1})
    obs_pid = None
    for d in declared:
        if d in obs_set:
            covered[d] = d
            continue
        rc2, _, _ = git(a.repo, "cat-file", "-e", d + "^{commit}")
        if rc2 != 0:
            bogus.append(d)
            continue
        if obs_pid is None:
            obs_pid = {}
            for o in observed:
                pid = patch_id(a.repo, o)
                if pid:
                    obs_pid.setdefault(pid, []).append(o)
        dp = patch_id(a.repo, d)
        hit = obs_pid.get(dp) if dp else None
        if hit:
            covered[d] = hit[0]
            stale.append((d, hit[0]))
        else:
            unresolved.append(d)

    for d, o in stale:
        out("STALE-SHA %s -> %s (the exemption survived a rewrite; the "
            "baseline is out of date, the history is not)" % (d, o))
    for d in bogus:
        out("BOGUS %s (declared, and no commit in this repository answers "
            "to it)" % d)
    for d in dups:
        out("DUPLICATE %s" % d)
    if unresolved:
        for d in unresolved:
            out("UNRESOLVED %s (neither its sha nor its patch-id is present "
                "among the unattributed commits)" % d)
        out("verdict: UNMEASURED-STALE")
        return 6

    undeclared = sorted(obs_set - set(covered.values()))
    out("covered-by-sha: %d" % sum(1 for d, o in covered.items() if d == o))
    out("covered-by-patchid: %d" % len(stale))
    for h in undeclared:
        out("UNDECLARED %s %s" % (h, subjects.get(h, "")))
    delta = len(undeclared) + len(bogus) + len(dups)
    out("delta: %d" % delta)
    if delta:
        out("verdict: RED")
        return 1
    out("verdict: GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
JUDGE

# ---- scratch construction, all of it inside $WORK -------------------------
ssh-keygen -q -t ed25519 -N "" -C "ft37-scratch" -f "$WORK/sk" </dev/null \
  || broken "ssh-keygen produced no ephemeral signing key"
printf 'ft37@invalid %s\n' "$(awk '{print $1" "$2}' "$WORK/sk.pub")" \
  > "$WORK/allowed_signers"

mkrepo() {
  git init -q "$1" || broken "git init failed for $1"
  git -C "$1" config user.name "FT37 Scratch"
  git -C "$1" config user.email "ft37@invalid"
  git -C "$1" config gpg.format ssh
  git -C "$1" config gpg.ssh.allowedSignersFile "$WORK/allowed_signers"
  git -C "$1" config commit.gpgsign false
}

csigned() {
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add -- "$2" || broken "add failed in $1"
  git -C "$1" -c user.signingkey="$WORK/sk" -c commit.gpgsign=true \
    commit -q -m "$3" || broken "signed commit failed in $1"
}

cunsigned() {
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add -- "$2" || broken "add failed in $1"
  git -C "$1" -c commit.gpgsign=false commit -q -m "$3" \
    || broken "unsigned commit failed in $1"
}

# Shas arrive on stdin so no unquoted word-splitting is needed anywhere.
baseline_from() {
  { echo "<!-- ACCEPTED-UNATTRIBUTED-BEGIN -->"
    cat
    echo "<!-- ACCEPTED-UNATTRIBUTED-END -->"; } > "$1"
}

ARM_OUT=""
arm() { # name want repo baseline
  local name="$1" want="$2" rc
  set +e
  ARM_OUT="$(python3 "$WORK/judge.py" --repo "$3" --baseline "$4" 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "$ARM_OUT" | sed "s/^/  [$name] /"
  echo "arm $name: exit $rc (want $want)"
  [ "$rc" -eq "$want" ]
}

want_line() { # needle description
  printf '%s\n' "$ARM_OUT" | grep -qF -- "$1" \
    || broken "$2 -- the arm exited as wanted but never printed \"$1\""
}

reject_line() { # needle description
  if printf '%s\n' "$ARM_OUT" | grep -qF -- "$1"; then
    broken "$2 -- the arm printed \"$1\""
  fi
}

# ---- arm Z: the null cases ------------------------------------------------
mkrepo "$WORK/empty"
arm Z-scope 2 "$WORK/empty" "$WORK/nonexistent.md" \
  || broken "a repository with no commit did not answer UNMEASURED-SCOPE; a \
gate that reads nothing must not be able to answer GREEN"
arm Z-baseline 3 "$ROOT" "$WORK/nonexistent.md" \
  || broken "an absent baseline did not answer UNMEASURED-BASELINE; an absent \
declaration is not an empty declaration"
want_line "baseline: absent" "arm Z-baseline named no absent baseline"

# ---- the measured set of the real tree, built WITHOUT the judge -----------
git -C "$ROOT" log HEAD --format='%H %G?' | awk '$2=="N"{print $1}' \
  > "$WORK/real_unattributed.txt" \
  || broken "could not measure the real tree's unattributed set"
[ -s "$WORK/real_unattributed.txt" ] || broken "the real tree measured zero \
unattributed commits; arms N, S and P have nothing to discriminate on"
baseline_from "$WORK/real.base" < "$WORK/real_unattributed.txt"

# ---- arm N: negative control on the real tree -----------------------------
arm N 0 "$ROOT" "$WORK/real.base" \
  || broken "the real tree measured against a correct baseline did not answer \
GREEN; either the classification or the set identity is wrong"
want_line "delta: 0" "arm N answered GREEN on a non-zero delta"
n_scanned="$(printf '%s\n' "$ARM_OUT" | sed -n 's/^scanned: //p')"
[ "${n_scanned:-0}" -gt 0 ] || broken "arm N answered GREEN over a scanned \
count of ${n_scanned:-0}; a green that scanned nothing is a vacuum"
n_declared="$(printf '%s\n' "$ARM_OUT" | sed -n 's/^declared: //p')"
n_unattrib="$(printf '%s\n' "$ARM_OUT" | sed -n 's/^unattributed: //p')"
[ "$n_declared" = "$n_unattrib" ] || broken "arm N: declared $n_declared and \
unattributed $n_unattrib disagree on a run that answered GREEN"
echo "arm N: scanned=$n_scanned declared=$n_declared \
unattributed=$n_unattrib delta=0"

# ---- arm S: set identity, at unchanged cardinality ------------------------
sed '1s/.*/0000000000000000000000000000000000000001/' \
  "$WORK/real_unattributed.txt" | baseline_from "$WORK/swapped.base"
s_declared="$(grep -c '^[0-9a-f]\{40\}$' "$WORK/real_unattributed.txt")"
arm S 1 "$ROOT" "$WORK/swapped.base" \
  || broken "a baseline with one member swapped for a sha no object answers \
to did not answer RED; this gate is comparing counts, not sets"
want_line "BOGUS 0000000000000000000000000000000000000001" \
  "arm S went RED without naming the swapped member"
echo "arm S: cardinality unchanged at $s_declared, membership changed by one"

# ---- arm P: positive control, on a clone that has no allowed_signers ------
git clone -q "$ROOT" "$WORK/clone" 2>/dev/null \
  || broken "could not clone this repository for the positive control"
git -C "$WORK/clone" config user.name "FT37 Scratch"
git -C "$WORK/clone" config user.email "ft37@invalid"
# A clone inherits the operator's GLOBAL gpg.ssh.allowedSignersFile, so a bare
# `git clone` still reads G and would not exercise the U class at all. Pointing
# the clone's own config at a path that does not exist is what makes this arm
# the allowed_signers-free reading it claims to be -- the state of every fresh
# checkout on a host that never had that file.
git -C "$WORK/clone" config gpg.ssh.allowedSignersFile \
  "$WORK/no-such-allowed-signers" \
  || broken "could not blind the clone to the operator's allowed signers"
arm P-pre 0 "$WORK/clone" "$WORK/real.base" \
  || broken "the clone measured against the real baseline did not answer \
GREEN; the G/U collapse that makes this gate host-independent does not hold"
want_line "map: %G?=U -> attributed" "arm P-pre never exercised the U class, \
so the clone was not the allowed_signers-free reading this arm exists to be"
printf 'a sixth\n' > "$WORK/clone/ft37-positive-control.txt"
git -C "$WORK/clone" add -- ft37-positive-control.txt \
  || broken "could not stage the positive control's commit"
git -C "$WORK/clone" -c commit.gpgsign=false commit -q -m "unsigned, undeclared" \
  || broken "could not create the positive control's unsigned commit"
arm P 1 "$WORK/clone" "$WORK/real.base" \
  || broken "one further unsigned commit, declared nowhere, did not turn the \
gate RED; the gate does not detect what it exists to detect"
want_line "UNDECLARED" "arm P went RED without naming the undeclared commit"

# ---- arm A: anti-vacuity BY GENERATION ------------------------------------
mkrepo "$WORK/allsigned"
csigned "$WORK/allsigned" a.txt "a signed one"
csigned "$WORK/allsigned" b.txt "a signed two"
csigned "$WORK/allsigned" c.txt "a signed three"
printf '' | baseline_from "$WORK/empty.base"
arm A 0 "$WORK/allsigned" "$WORK/empty.base" \
  || broken "a repository in which every commit is signed did not answer \
GREEN against an empty declaration"
a_scanned="$(printf '%s\n' "$ARM_OUT" | sed -n 's/^scanned: //p')"
[ "${a_scanned:-0}" -gt 0 ] || broken "arm A answered GREEN over a scanned \
count of ${a_scanned:-0}; the empty set was not measured, it was assumed"
want_line "declared: 0" "arm A did not declare the empty set"
echo "arm A: scanned=$a_scanned over an empty declaration, GREEN by generation"

# ---- arm R: the exemption survives a rewrite ------------------------------
mkrepo "$WORK/rw"
cunsigned "$WORK/rw" a.txt "r one"
cunsigned "$WORK/rw" b.txt "r two"
cunsigned "$WORK/rw" c.txt "r three"
git -C "$WORK/rw" rev-list HEAD | baseline_from "$WORK/rw.base"
arm R-pre 0 "$WORK/rw" "$WORK/rw.base" \
  || broken "the un-rewritten scratch repository did not answer GREEN; arm R \
cannot show a rewrite surviving a gate that was never green before it"
git -C "$WORK/rw" branch ft37-backup HEAD \
  || broken "could not keep the pre-rewrite objects reachable"
rw_root="$(git -C "$WORK/rw" rev-list --max-parents=0 HEAD)"
git -C "$WORK/rw" checkout -q --detach "$rw_root" \
  || broken "could not detach onto the scratch root"
git -C "$WORK/rw" -c commit.gpgsign=false commit -q --amend -m "r one reworded" \
  || broken "could not reword the scratch root"
for rw_c in $(git -C "$WORK/rw" rev-list --reverse "$rw_root..ft37-backup"); do
  git -C "$WORK/rw" -c commit.gpgsign=false cherry-pick "$rw_c" >/dev/null 2>&1 \
    || broken "could not replay $rw_c onto the rewritten root"
done
rw_moved=0
while read -r rw_old; do
  git -C "$WORK/rw" merge-base --is-ancestor "$rw_old" HEAD 2>/dev/null \
    || rw_moved=$((rw_moved + 1))
done < <(grep '^[0-9a-f]\{40\}$' "$WORK/rw.base")
[ "$rw_moved" -eq 3 ] || broken "the rewrite moved $rw_moved of 3 shas; arm R \
must rewrite every declared sha or it is not testing what it claims"
arm R 0 "$WORK/rw" "$WORK/rw.base" \
  || broken "a rewrite that moved every declared sha broke the exemption; the \
patch-id fallback does not hold and a rebase would re-accuse accepted commits"
want_line "STALE-SHA" "arm R held the exemption without printing STALE-SHA; a \
baseline that is silently out of date is the state this line exists to name"
want_line "covered-by-patchid: 3" "arm R did not resolve all three through \
the patch-id"

# ---- arm C: a comment is not a declaration, in both directions ------------
# The body is built by hand rather than by the judge: three rows carrying a
# short-sha and a date after the full sha, a '#' comment line above them and a
# bare '#' between the groups, and the remaining rows bare. If the shape this
# arm claims to test is not in the file, the arm proves nothing, so the shape
# is asserted before it is measured.
{ echo "# a group heading, which declares nothing"
  head -3 "$WORK/real_unattributed.txt" | while read -r c_sha; do
      printf '%s  %s %s\n' "$c_sha" \
        "$(git -C "$ROOT" log -1 --format=%h "$c_sha")" \
        "$(git -C "$ROOT" log -1 --format=%ad --date=short "$c_sha")"
    done
  echo "#"
  echo "# and the rest, declared bare"
  sed -n '4,$p' "$WORK/real_unattributed.txt"; } > "$WORK/commented.body"
c_rows="$(grep -c '^[0-9a-f]\{40\}' "$WORK/commented.body")"
c_hashlines="$(grep -c '^#' "$WORK/commented.body")"
c_trailing="$(grep -c '^[0-9a-f]\{40\} .' "$WORK/commented.body")"
if [ "$c_hashlines" -lt 2 ] || [ "$c_trailing" -lt 3 ]; then
  broken "arm C-comment built a body with $c_hashlines comment lines and \
$c_trailing rows carrying trailing text; it must carry both or it is measuring \
a form it does not contain"
fi
[ "$c_rows" -eq "$s_declared" ] || broken "arm C-comment declared $c_rows of \
the $s_declared observed commits; the body lost a row while being decorated"
baseline_from "$WORK/commented.base" < "$WORK/commented.body"
arm C-comment 0 "$ROOT" "$WORK/commented.base" \
  || broken "a baseline in the .git-blame-ignore-revs form -- comment lines \
between the shas, short-sha and date after them -- did not answer GREEN; the \
enumeration this repository is about to write is not the one the judge reads"
want_line "declared: $c_rows" "arm C-comment counted something other than the \
$c_rows sha rows; a comment line was counted as a declaration"
want_line "delta: 0" "arm C-comment answered GREEN on a non-zero delta"
echo "arm C-comment: $c_rows sha rows, $c_hashlines comment lines, \
$c_trailing rows with trailing text, declared=$c_rows delta=0"

c_hidden="$(head -1 "$WORK/real_unattributed.txt")"
sed '1s/^/# /' "$WORK/real_unattributed.txt" | baseline_from "$WORK/hidden.base"
arm C-commented-out 1 "$ROOT" "$WORK/hidden.base" \
  || broken "a true member of the observed set, commented out with '# ', did \
not turn the gate RED; commenting a line would be a way to drop a commit from \
the declaration without the record showing it"
want_line "UNDECLARED $c_hidden" "arm C-commented-out went RED without naming \
the commit whose declaration was commented out"
want_line "declared: $((s_declared - 1))" "arm C-commented-out still counted \
the commented line among the declarations"
echo "arm C-commented-out: $c_hidden commented out, declared=$((s_declared - 1)) \
of $s_declared observed, RED"

# ---- arm B: the two degenerate baselines, which are not one --------------
printf '# INTEGRITY\n\nA tracked declaration that carries no unattributed\nenumeration at all.\n' \
  > "$WORK/nosection.md"
arm B-nosection 3 "$ROOT" "$WORK/nosection.md" \
  || broken "a baseline file that exists and carries no sentinel pair did not \
answer UNMEASURED-BASELINE; a present file with no section would have been \
read as an empty enumeration, which is the one thing it is not"
want_line "no enumeration block" "arm B-nosection answered 3 without naming \
the absent sentinels"
reject_line "declared: 0" "arm B-nosection reached a declaration count over a \
file that declares nothing; it must refuse before it counts"

arm B-empty 1 "$ROOT" "$WORK/empty.base" \
  || broken "an empty enumeration on a tree with $s_declared unattributed \
commits did not answer RED; an empty block is a declaration that nothing is \
exempt, and on this tree that declaration is false"
want_line "declared: 0" "arm B-empty did not declare the empty set"
want_line "delta: $s_declared" "arm B-empty went RED at a delta other than the \
$s_declared commits it declared nothing about"
echo "arm B-empty: the byte-identical empty declaration that answered GREEN \
in arm A answers RED here; the tree under it changed and the file did not"

echo "== verdict =="
set +e
python3 "$WORK/judge.py" --repo "$ROOT" --baseline "$ROOT/INTEGRITY.md"
p_rc=$?
set -e
case "$p_rc" in
  0) echo "GREEN: the unattributed set reachable from HEAD is exactly the declared set" ;;
  1) echo "RED: the unattributed set reachable from HEAD is not the declared set" ;;
  2) echo "UNMEASURED: no commit was read" ;;
  3) echo "UNMEASURED-BASELINE: no baseline declares an unattributed set" ;;
  6) echo "UNMEASURED-STALE: a declared commit resolved by neither sha nor patch-id" ;;
  *) broken "the judge answered an exit outside its contract: $p_rc" ;;
esac
exit "$p_rc"
