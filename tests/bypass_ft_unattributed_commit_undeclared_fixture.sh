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
# THE KEY IS THE SHA. THE PATCH-ID IS DECLARED, AND IT NEVER EXEMPTS.
# A ROW CARRIES TWO TOKENS: the sha, and the stable patch-id of the commit that
# sha named when the row was written. Anything after the second token is free
# text. A row with one token is an incomplete declaration and answers 3.
#
# WHY THE PATCH-ID CANNOT BE A COVERAGE. A patch-id identifies a DIFF. A commit
# is (diff, parent, author, committer, message, dates) and `git patch-id`
# discards everything but the first. A match therefore establishes "this has
# the same diff", never "this is the commit I accepted", and an attribution
# exemption needs the second. The two are different facts and this judge will
# not spend one for the other.
#
# AND THE DISCRIMINATOR DOES NOT EXIST IN THE REPOSITORY. A rebase that moved a
# declared commit and a cherry-pick that replayed its diff as a new unsigned
# commit produce the SAME reading -- same declared count, same observed count,
# same patch-id match, same delta. Measured, on arms R and X, which differ in
# nothing a judge can see. Distinguishing them by whether the old object still
# resolves would work on this machine and fail on a clone, which is the exact
# host-dependence the G/U collapse below exists to remove. So the judge does
# not distinguish them: it refuses to certify either, and says which rows to
# re-declare.
#
# THE VERDICT, and it consults no object's resolvability anywhere:
#   observed    the shas of the unattributed commits reachable from HEAD
#   declared    the shas written in the block; pinned[S] is S's written patch-id
#   undeclared  observed \ declared        missing  declared \ observed
#
#   1  undeclared empty AND missing empty                    -> 0 GREEN
#   2  EVERY undeclared has a patch-id equal to pinned[S] for
#      some S in missing, AND EVERY missing explains an
#      undeclared this way -- a conjunction, not "at least
#      one"                                                  -> 6 UNMEASURED-
#                                                                 STALE
#   3  anything else                                          -> 1 RED
#
# THE INVARIANT THIS FILE EXISTS TO HOLD, printed on every run: A PATCH-ID
# MATCH NEVER PRODUCES GREEN. It is the one property the repair must guarantee
# and the one the defect violated -- the old judge let a patch-id coincidence
# carry an undeclared commit all the way to 0.
#
# EXIT CONTRACT. Seven codes, all distinct, and GREEN shares none of them with a
# non-measurement. An exit that cannot separate "the sets are equal" from "no
# set was read" reports a vacuum as a pass.
#   0  GREEN               observed set == declared set, by sha
#   1  RED                 they differ and the patch-ids do not account for it
#   2  UNMEASURED-SCOPE    no commit was read at all
#   3  UNMEASURED-BASELINE the baseline file is absent, unreadable, carries no
#                          enumeration block, or carries a row that is not a
#                          sha and a patch-id
#   5  UNMEASURED-SHALLOW  the history is truncated. The observed set is
#                          then the checkout's depth window and not this
#                          history, so the judge declares that it cannot
#                          measure instead of reporting a --depth setting
#                          as a property of this repository
#   6  UNMEASURED-STALE    every difference is accounted for by a declared
#                          patch-id: the rows name shas this history no longer
#                          has, and re-declaring them is the operator's act
#   4  FIXTURE BROKEN      a control arm did not answer what it must, or the
#                          classification map did not cover an observed %G?
#
# TWENTY-TWO ARMS, each printed with its own exit. The literal here read
# NINETEEN against nineteen invocations before this basis; it is the
# measured count now, and it is a count of INVOCATIONS, which is what a
# reader can check against `grep -cE '^ *v?arm ' "$0"`. Nineteen of them ask
# the judge a question directly through `arm`; the last three ask THIS FIXTURE
# a question, through `varm`, and are counted here because a reader counting
# arms must reach the same number either way:
#   P  positive control, on a CLONE of this repository: the measured set
#      declared verbatim answers GREEN, and ONE further unsigned commit turns
#      it RED. The clone carries no allowed_signers, so this arm is also where
#      the G/U collapse is exercised rather than argued.
#   N  negative control, on the real tree with a synthetic-but-correct
#      baseline -> GREEN, and it must print scanned>0, undeclared=0 and
#      declared-not-observed=0. The baseline is built by an INDEPENDENT
#      `git log | awk` walk and a patch-id taken from each commit it names,
#      never by the judge, so the arm is not the judge agreeing with itself.
#   S  set-identity, at unchanged cardinality, in the two shapes the two-token
#      row now has. S-bogus-row: both tokens replaced, so nothing explains the
#      commit the row displaced -> RED. S-sha-only: the sha replaced and the
#      TRUE patch-id kept -> 6, and never 0. Neither is a green; the second is
#      not an accusation either, it is "re-declare this row".
#   A  anti-vacuity BY GENERATION: a scratch repository in which every commit is
#      signed and the baseline declares the EMPTY set -> GREEN with scanned>0
#      printed. A green that came from never taking the measurement cannot pass
#      for this one.
#   R  after a rewrite that moved every declared sha: the written patch-ids say
#      which new commit answers to which old row, STALE-SHA names each pair,
#      and the exit is 6. NOT 0. A rewritten baseline IS stale; the gate says
#      so and hands the operator the mapping. "The exemption survives a future
#      rewrite" was the claim this arm used to carry, and it was false.
#   R-partial  the branch above is a CONJUNCTION. One undeclared commit, two
#      missing rows: the first row's patch-id explains it, the second explains
#      nothing. Every undeclared is accounted for and one row is not -> RED. A
#      judge that read the branch as "at least one" would answer 6 here.
#   Z  null cases: an absent baseline -> 3, and a repository with no commits
#      -> 2.
#   X  cherry-pick: the commit nobody declared. A signed base, one unsigned
#      commit D declared by sha, D put out of HEAD's reach and its diff
#      replayed as E -- a new unsigned commit with a different author, a
#      different message and a different sha. Nothing declares E. The OLD judge
#      answered 0: it derived D's patch-id from D's object, matched E, and
#      carried E to GREEN, which is an exemption for belonging to a class and
#      is what the declaration forbids in as many words. The repaired judge
#      answers 6 and names D as DECLARED-NOT-OBSERVED. The repair is "never
#      green", not "accuse": the unsigned replay no longer gets in without
#      somebody looking at it, and the judge does not pretend to know whether
#      a person rebased or somebody replayed a diff, because nothing in the
#      repository tells it which.
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
#   H  TRUNCATED HISTORY, DECLARED FAILING AT THIS BASIS on H-shallow. The
#      judge reads `git log HEAD` and never asks whether the history it walked
#      is the whole one. On a shallow clone that set is the checkout's DEPTH
#      WINDOW: the observed set becomes a function of --depth, and every
#      verdict below is then a statement about how the reader cloned rather
#      than about what this repository contains. It is the same class of defect
#      the G/U collapse above closed -- a judge that demanded %G?=G measured
#      the reader's key list. This one measures the reader's depth.
#      Three arms, one source repository, ONE complete and correct baseline,
#      and the key list pinned in every clone so DEPTH is the only variable:
#        H-shallow       a depth-bounded clone whose window does not reach the
#                        one declared commit. Asserted before the judge is
#                        asked: the clone is shallow, it sees fewer commits
#                        than the source has, and the declared sha is not among
#                        the commits it reaches.
#        H-full-control  THE SAME CLONE, `git fetch --unshallow`-ed in place ->
#                        GREEN. Same directory, same objects source, same
#                        baseline; only the depth moved. This is what proves
#                        the guard is not a permanent exemption for anything
#                        that once looked truncated, and that depth is the
#                        grandeur.
#        H-partial       `git clone --filter=blob:none`. MEASURED, not assumed:
#                        such a clone answers `false` to
#                        `--is-shallow-repository` and carries the COMPLETE
#                        commit history -- the two properties get confused and
#                        they are not the same one. It must therefore answer
#                        exactly as a full clone does, and never as a shallow
#                        one.
#      H-shallow answers 5 UNMEASURED-SHALLOW: a verdict of its own, distinct
#      from RED and from GREEN alike, and the whole of the repair. The OLD
#      judge answered 1 RED -- observed, at the basis that armed this block --
#      accusing the repository of a discrepancy that belongs to `--depth 2`.
#      RED WAS NOT THE ONLY WRONG ANSWER AND NOT THE WORST ONE, which is why
#      the repair is a distinct exit and not a louder RED. Measured on this
#      same source at a depth whose window happens to contain every declared
#      row, the old judge answered 0 GREEN: it certified a corpus the checkout
#      chose. A guard that only stopped the RED would have left that GREEN
#      standing, and a gate that can be made to pass by cloning shallower is
#      worse than one that can be made to fail that way.
#   V  THIS FIXTURE'S OWN ROOT, DECLARED FAILING AT THIS BASIS on V-shallow-root
#      and V-scratch-visible. Arm H measures a truncated clone the fixture
#      BUILDS. $ROOT is the one repository the arms cannot choose, and on a
#      shallow checkout TEN of the nineteen arms above are asking their
#      question about a corpus the checkout chose: eight invoke the judge with
#      --repo "$ROOT", and P-pre and P run against a clone of $ROOT, which
#      inherits its depth. Measured at this basis: the fixture answers 4
#      FIXTURE BROKEN there. 4 says a control could not confirm what it is
#      measuring, and here the control answered -- arm Z-baseline wanted 3 and
#      got 5, correctly, about a tree that is not measurable. The fixture
#      reported its own health where the tree's was the finding.
#      THE REPAIR IS A PREFLIGHT THAT REFUSES AND DOES NOT COVER, and the
#      three arms are one claim in three parts, run against THIS FILE copied
#      into a checkout rather than against the commit the checkout carries:
#        V-shallow-root     $ROOT shallow -> 5, each skipped arm naming itself
#                           and its reason, the scratch arms still observed
#                           running from the first to the last.
#        V-full-root        THE SAME CHECKOUT unshallowed in place -> 0. Only
#                           the depth moved, so the guard cannot be a permanent
#                           exemption for anything that ever looked truncated.
#        V-scratch-visible  $ROOT shallow AND a scratch arm genuinely broken ->
#                           4, NOT 5, with the inner run naming the BROKEN
#                           SCRATCH ARM. The exit code alone proves nothing
#                           here: the unrepaired fixture answers 4 to that same
#                           checkout for the other reason, which is why this
#                           arm is declared against the reason and not the
#                           number. It is the arm that fails if the preflight
#                           ever grows into a cover.
#
# The arms sign with an EPHEMERAL key this fixture generates in its own scratch
# directory. Nothing is read from the operator's ~/.config and nothing is
# written outside the work directory, so the arms answer the same on any host
# with git and ssh-keygen.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ftuca.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

broken() { echo "FIXTURE BROKEN: $*" >&2; exit 4; }

# The one property the repair guarantees, spelled once here and asserted on the
# arms that reach a verdict. If the judge stops printing it, the arms say so.
FT37_INVARIANT="INVARIANT: a patch-id match never produces GREEN"

cat > "$WORK/judge.py" <<'JUDGE'
"""Attribution gate: the unattributed set reachable from HEAD, against a
declared enumeration of sha AND patch-id.

  judge.py --repo REPO --baseline FILE

Exits 0 GREEN, 1 RED, 2 UNMEASURED-SCOPE, 3 UNMEASURED-BASELINE,
5 UNMEASURED-SHALLOW, 6 UNMEASURED-STALE, 4 FIXTURE-BROKEN.

A PATCH-ID MATCH NEVER PRODUCES GREEN. A patch-id identifies a diff; a commit
is a diff plus its parent, author, committer, message and dates, and patch-id
discards all of those. "Same diff" is not "the commit I accepted", and an
attribution exemption needs the second. So a declared patch-id can move a
verdict from RED to 6 -- it names which new commit answers to which stale row
-- and it can never move one to 0.

Nothing here asks whether an object resolves. A rule keyed on that would read
GREEN on the machine that still has refs/backup/* and something else on a
clone, which is the host-dependence the G/U collapse removes.
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
PID_RE = re.compile(r"^[0-9a-f]{40,64}$")
US = "\x1f"
INVARIANT = ("INVARIANT: a patch-id match never produces GREEN -- at most it "
             "produces 6 UNMEASURED-STALE")


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

    # A TRUNCATED HISTORY IS NOT A SMALLER HISTORY. `git log HEAD` on a shallow
    # clone returns the commits inside the checkout's depth window and stops --
    # no error, no marker on the rows, nothing in the output that distinguishes
    # "this history has six commits" from "this checkout was given two of them".
    # Every verdict below reads off that set, so on a shallow clone every
    # verdict is a function of --depth: a window that misses a declared row
    # accuses the repository of a discrepancy the history does not have, and a
    # window that happens to contain every declared row CERTIFIES -- measured,
    # exit 0 -- a corpus nobody chose. The second is the worse of the two and
    # it is why this is a distinct exit rather than a louder RED.
    #
    # SO THE JUDGE DOES NOT ANSWER. It declares that it cannot measure. 5 is
    # spent on that and shares its code with nothing: an exit that could not
    # separate "the sets are equal" from "the corpus was truncated" would
    # report a depth setting as a property of this repository.
    #
    # AND IT ASKS THE REPOSITORY, NEVER AN OBJECT.
    # `git rev-parse --is-shallow-repository` reads a property of the clone; no
    # sha is resolved here and none is looked up. That is the constraint the
    # patch-id repair was paid for -- a rule keyed on whether an object
    # resolves reads one way on the machine that still holds refs/backup/* and
    # another on a clone -- and it holds for this guard too.
    #
    # A GIT THAT CANNOT ANSWER IS NOT A FULL HISTORY. `--is-shallow-repository`
    # arrived in git 2.15; where it does not answer, this judge cannot tell a
    # truncated corpus from a whole one, and it says FIXTURE-BROKEN rather than
    # assuming the answer it would prefer.
    #
    # BEFORE THE BASELINE IS READ, and deliberately. On a shallow clone the
    # corpus is unmeasurable whatever the baseline says, and a 3 here would
    # send the operator to look at a file that is not the problem.
    rc_sh, so_sh, err_sh = git(a.repo, "rev-parse", "--is-shallow-repository")
    shallow = so_sh.strip()
    if rc_sh != 0 or shallow not in ("true", "false"):
        out("verdict: FIXTURE-BROKEN")
        sys.stderr.write("git rev-parse --is-shallow-repository answered %r "
                         "(rc %d, stderr %r) -- this judge will not assume a "
                         "complete history it could not confirm\n"
                         % (shallow, rc_sh, err_sh.strip()))
        return 4
    out("shallow: %s" % shallow)
    if shallow == "true":
        out("scanned: %d" % len(rows))
        out("depth-bounded: the observed set is this checkout's depth window, "
            "not this history -- the declaration is not what is being "
            "measured, and unshallowing the clone is what makes the "
            "measurement possible")
        out("verdict: UNMEASURED-SHALLOW")
        return 5

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
    out(INVARIANT)

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

    # TWO TOKENS PER ROW: the sha, then the stable patch-id the commit that sha
    # named had when the row was written. A '#' at the start of a line is a
    # comment and declares nothing; free text after the second token is
    # ignored, so a row may carry its own short-sha, date and subject and stay
    # readable to a person. A ROW WITH ONE TOKEN IS NOT A DECLARATION: an
    # incomplete declaration is refused, never read as a sha-only one.
    block = text.split(BEGIN, 1)[1].split(END, 1)[0]
    declared, pinned, order = [], {}, []
    for ln in block.splitlines():
        t = ln.strip()
        if not t or t.startswith("#") or t.startswith("<!--") or t == "-->":
            continue
        tok = t.split()
        if len(tok) < 2:
            out("baseline: incomplete declaration %r -- a row carries a sha "
                "AND its patch-id, and one token is not a declaration" % t)
            out("verdict: UNMEASURED-BASELINE")
            return 3
        sha, pid = tok[0], tok[1]
        if not SHA_RE.match(sha):
            out("baseline: malformed sha %r" % sha)
            out("verdict: UNMEASURED-BASELINE")
            return 3
        if not PID_RE.match(pid):
            out("baseline: malformed patch-id %r on row for %s" % (pid, sha))
            out("verdict: UNMEASURED-BASELINE")
            return 3
        declared.append(sha)
        order.append(sha)
        pinned[sha] = pid
    out("declared: %d" % len(declared))

    obs_set = set(observed)
    dec_set = set(declared)
    dups = sorted({d for d in declared if declared.count(d) > 1})
    for d in dups:
        out("DUPLICATE %s" % d)

    undeclared = sorted(obs_set - dec_set)
    missing = [d for d in order if d not in obs_set]
    out("undeclared: %d" % len(undeclared))
    out("declared-not-observed: %d" % len(missing))
    for h in undeclared:
        out("UNDECLARED %s %s" % (h, subjects.get(h, "")))
    for d in missing:
        out("DECLARED-NOT-OBSERVED %s pinned %s" % (d, pinned[d]))

    if not undeclared and not missing and not dups:
        out("explained-by-declared-patch-id: 0")
        out("verdict: GREEN")
        return 0

    # Patch-ids are taken from the OBSERVED commits only. The judge never asks
    # the repository about a declared sha, so the answer does not depend on
    # whether this clone still happens to hold the old object.
    explained_by, explains = {}, {}
    for h in undeclared:
        ph = patch_id(a.repo, h)
        if not ph:
            continue
        for d in missing:
            if pinned[d] == ph:
                explained_by[h] = d
                explains.setdefault(d, []).append(h)
                break
    for h in sorted(explained_by):
        out("STALE-SHA %s -> %s (the declared patch-id matches; the row names "
            "a sha this history no longer has, and re-declaring it is the "
            "operator's act, not this judge's)" % (explained_by[h], h))
    out("explained-by-declared-patch-id: %d" % len(explained_by))

    every_undeclared = all(h in explained_by for h in undeclared)
    every_missing = all(d in explains for d in missing)
    out("every-undeclared-explained: %s" % ("yes" if every_undeclared else "no"))
    out("every-declared-not-observed-explains: %s"
        % ("yes" if every_missing else "no"))
    if not dups and every_undeclared and every_missing:
        out("verdict: UNMEASURED-STALE")
        return 6
    out("verdict: RED")
    return 1


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

# A row of the enumeration: the sha, then the stable patch-id of the commit it
# names. Taken here from the repository so the arms' baselines are built
# INDEPENDENTLY of the judge, which never derives a patch-id from a declared
# sha.
pair_rows() {  # <repo>; shas on stdin, "sha patch-id" rows on stdout
  local pr_repo="$1" pr_sha pr_pid
  while read -r pr_sha; do
    [ -n "$pr_sha" ] || continue
    pr_pid="$(git -C "$pr_repo" show "$pr_sha" | git patch-id --stable \
      | cut -d' ' -f1)"
    [ -n "$pr_pid" ] || broken "no patch-id for $pr_sha in $pr_repo"
    printf '%s %s\n' "$pr_sha" "$pr_pid"
  done
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
pair_rows "$ROOT" < "$WORK/real_unattributed.txt" > "$WORK/real_pairs.txt"
baseline_from "$WORK/real.base" < "$WORK/real_pairs.txt"

# ---- arm N: negative control on the real tree -----------------------------
arm N 0 "$ROOT" "$WORK/real.base" \
  || broken "the real tree measured against a correct baseline did not answer \
GREEN; either the classification or the set identity is wrong"
want_line "undeclared: 0" "arm N answered GREEN over a non-empty undeclared set"
want_line "declared-not-observed: 0" "arm N answered GREEN with a row the \
observed set does not contain"
want_line "$FT37_INVARIANT" "arm N did not print the invariant this judge \
exists to hold"
n_scanned="$(printf '%s\n' "$ARM_OUT" | sed -n 's/^scanned: //p')"
[ "${n_scanned:-0}" -gt 0 ] || broken "arm N answered GREEN over a scanned \
count of ${n_scanned:-0}; a green that scanned nothing is a vacuum"
n_declared="$(printf '%s\n' "$ARM_OUT" | sed -n 's/^declared: //p')"
n_unattrib="$(printf '%s\n' "$ARM_OUT" | sed -n 's/^unattributed: //p')"
[ "$n_declared" = "$n_unattrib" ] || broken "arm N: declared $n_declared and \
unattributed $n_unattrib disagree on a run that answered GREEN"
echo "arm N: scanned=$n_scanned declared=$n_declared \
unattributed=$n_unattrib undeclared=0"

# ---- arm S: set identity, at unchanged cardinality, in TWO shapes ---------
# The two-token row can be corrupted in two ways and they are not one answer.
# S-bogus-row replaces BOTH tokens: nothing accounts for the commit the row
# stopped declaring, and the sets simply differ -> RED. S-sha-only replaces the
# sha and keeps the TRUE patch-id: the difference IS accounted for, so the
# verdict is 6 -- "re-declare this row" -- and never 0. A judge that answered
# GREEN to the second would be letting a written patch-id stand in for a
# declaration, which is the defect this file was repaired for.
s_declared="$(grep -c '^[0-9a-f]\{40\}$' "$WORK/real_unattributed.txt")"
s_hidden="$(head -1 "$WORK/real_unattributed.txt")"
S_FAKE_SHA=0000000000000000000000000000000000000001
S_FAKE_PID=0000000000000000000000000000000000000002
sed "1s/.*/$S_FAKE_SHA $S_FAKE_PID/" \
  "$WORK/real_pairs.txt" | baseline_from "$WORK/swapped.base"
arm S-bogus-row 1 "$ROOT" "$WORK/swapped.base" \
  || broken "a baseline with one row swapped for a sha and a patch-id nothing \
answers to did not answer RED; this gate is comparing counts, not sets"
want_line "DECLARED-NOT-OBSERVED $S_FAKE_SHA" \
  "arm S-bogus-row went RED without naming the swapped row"
want_line "UNDECLARED $s_hidden" "arm S-bogus-row went RED without naming the \
commit the swapped row stopped declaring"
echo "arm S-bogus-row: cardinality unchanged at $s_declared, membership \
changed by one, RED"

sed "1s/^[0-9a-f]\{40\}/$S_FAKE_SHA/" \
  "$WORK/real_pairs.txt" | baseline_from "$WORK/shaonly.base"
arm S-sha-only 6 "$ROOT" "$WORK/shaonly.base" \
  || broken "a row whose sha was swapped but whose TRUE patch-id was kept did \
not answer UNMEASURED-STALE; a written patch-id must account for a difference \
without certifying it, and it must never answer GREEN"
want_line "STALE-SHA $S_FAKE_SHA -> $s_hidden" "arm S-sha-only answered 6 \
without naming which row the observed commit answers to"
want_line "every-undeclared-explained: yes" "arm S-sha-only reached 6 on \
something other than a fully accounted difference"
reject_line "verdict: GREEN" "arm S-sha-only let a written patch-id certify a \
row the observed set does not contain"
echo "arm S-sha-only: cardinality unchanged at $s_declared, the true patch-id \
kept, 6 and never 0"

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

# ---- arm R: after a rewrite the declaration is STALE, and says which row ---
# The claim this arm used to carry was "the exemption survives a future
# rewrite", and it was false: a rewritten baseline names shas the history no
# longer has, which is the definition of stale. What the WRITTEN patch-ids buy
# is the mapping -- which new commit answers to which old row -- and the judge
# hands it over and refuses to certify. 6, never 0.
mkrepo "$WORK/rw"
cunsigned "$WORK/rw" a.txt "r one"
cunsigned "$WORK/rw" b.txt "r two"
cunsigned "$WORK/rw" c.txt "r three"
git -C "$WORK/rw" rev-list HEAD | pair_rows "$WORK/rw" > "$WORK/rw.pairs"
baseline_from "$WORK/rw.base" < "$WORK/rw.pairs"
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
done < <(awk '{print $1}' "$WORK/rw.pairs")
[ "$rw_moved" -eq 3 ] || broken "the rewrite moved $rw_moved of 3 shas; arm R \
must rewrite every declared sha or it is not testing what it claims"
arm R 6 "$WORK/rw" "$WORK/rw.base" \
  || broken "a rewrite that moved every declared sha did not answer \
UNMEASURED-STALE; either the written patch-ids failed to account for the three \
new commits, or the judge certified a baseline that names three shas this \
history no longer has"
want_line "STALE-SHA" "arm R reached 6 without printing STALE-SHA; the mapping \
from stale row to new commit is the whole of what this exit hands the operator"
want_line "explained-by-declared-patch-id: 3" "arm R did not account for all \
three through the WRITTEN patch-ids"
want_line "every-declared-not-observed-explains: yes" "arm R reached 6 with a \
row that explains nothing"
reject_line "verdict: GREEN" "arm R certified a rewritten baseline; a patch-id \
match must never produce GREEN"

# ---- arm R-partial: branch 6 is a CONJUNCTION, not "at least one" ---------
# One undeclared commit and TWO rows the observed set does not contain. The
# first row's written patch-id accounts for the commit; the second accounts for
# nothing. Every undeclared IS explained, and one row is NOT, so the conjunction
# fails and the verdict is RED. A judge that read branch 6 as "at least one
# match" would answer 6 here and would let a row nobody can account for ride in
# beside a row somebody can.
mkrepo "$WORK/rwp"
csigned "$WORK/rwp" a.txt "rp signed base"
cunsigned "$WORK/rwp" b.txt "rp the one unattributed commit"
rwp_u="$(git -C "$WORK/rwp" rev-parse HEAD)"
rwp_pid="$(git -C "$WORK/rwp" show "$rwp_u" | git patch-id --stable \
  | cut -d' ' -f1)"
[ -n "$rwp_pid" ] || broken "arm R-partial: no patch-id for the unattributed \
commit it is built around"
RWP_A=00000000000000000000000000000000000000aa
RWP_B=00000000000000000000000000000000000000bb
RWP_DEAD=00000000000000000000000000000000000000de
{ printf '%s %s\n' "$RWP_A" "$rwp_pid"
  printf '%s %s\n' "$RWP_B" "$RWP_DEAD"; } | baseline_from "$WORK/rwp.base"
arm R-partial 1 "$WORK/rwp" "$WORK/rwp.base" \
  || broken "two rows the observed set does not contain, one accounted for by \
its written patch-id and one accounted for by nothing, did not answer RED; \
branch 6 is being read as \"at least one match\" and not as the conjunction it \
is"
want_line "every-undeclared-explained: yes" "arm R-partial did not reach the \
conjunction it exists to test -- the undeclared half must hold for the failing \
half to be what decides"
want_line "every-declared-not-observed-explains: no" "arm R-partial went RED \
without the unexplained row being the reason"
want_line "DECLARED-NOT-OBSERVED $RWP_B" "arm R-partial went RED without \
naming the row nothing accounts for"
echo "arm R-partial: 1 undeclared explained, 1 of 2 rows unexplained, RED"

# ---- arm X: the cherry-pick nobody declared ------------------------------
# The commit E that HEAD reaches is unsigned, carries a different author and a
# different message from the declared D, and is named by no row. The OLD judge
# derived D's patch-id from D's object, matched E and answered GREEN. This one
# answers 6 and prints D as DECLARED-NOT-OBSERVED. Every precondition is
# asserted before the judge is asked anything, so an answer that came from a
# mis-built scratch repository cannot be read as the finding.
mkrepo "$WORK/xcp"
csigned "$WORK/xcp" base.txt "x signed base"
cunsigned "$WORK/xcp" declared.txt "x the declared unattributed commit"
xcp_d="$(git -C "$WORK/xcp" rev-parse HEAD)"
git -C "$WORK/xcp" update-ref refs/backup/xcp-original "$xcp_d" \
  || broken "could not park the declared commit on a ref outside HEAD's reach"
git -C "$WORK/xcp" checkout -q --detach "$xcp_d^" \
  || broken "could not detach onto the parent of the declared commit"
# A cherry-pick that keeps the author, the message and the parent reproduces the
# sha exactly, and there would be no second commit to find. Author and message
# are changed so that E is a genuinely different commit carrying the same diff.
XCP_ID="Somebody Else"
XCP_MAIL="else@invalid"
GIT_AUTHOR_NAME="$XCP_ID" GIT_AUTHOR_EMAIL="$XCP_MAIL" \
GIT_COMMITTER_NAME="$XCP_ID" GIT_COMMITTER_EMAIL="$XCP_MAIL" \
  git -C "$WORK/xcp" -c commit.gpgsign=false cherry-pick --no-commit "$xcp_d" \
  >/dev/null 2>&1 || broken "could not replay the declared diff"
GIT_AUTHOR_NAME="$XCP_ID" GIT_AUTHOR_EMAIL="$XCP_MAIL" \
GIT_COMMITTER_NAME="$XCP_ID" GIT_COMMITTER_EMAIL="$XCP_MAIL" \
  git -C "$WORK/xcp" -c commit.gpgsign=false commit -q \
  -m "x a commit nobody declared" \
  || broken "could not commit the undeclared replay"
xcp_e="$(git -C "$WORK/xcp" rev-parse HEAD)"

[ "$xcp_d" != "$xcp_e" ] || broken "arm X: the replay reproduced the declared \
sha, so there is no undeclared commit to exempt and the arm measures nothing"
git -C "$WORK/xcp" merge-base --is-ancestor "$xcp_d" HEAD 2>/dev/null \
  && broken "arm X: the declared commit is still reachable from HEAD, so the \
judge would cover it by sha and never reach the patch-id at all"
git -C "$WORK/xcp" cat-file -e "$xcp_d^{commit}" 2>/dev/null \
  || broken "arm X: the declared commit no longer resolves, so the judge would \
answer BOGUS and the arm would go RED for a reason that is not the finding"
[ "$(git -C "$WORK/xcp" log -1 --format='%G?' "$xcp_e")" = "N" ] \
  || broken "arm X: the replayed commit is not unattributed, so it would never \
enter the observed set"
xcp_pd="$(git -C "$WORK/xcp" show "$xcp_d" | git patch-id --stable | cut -d' ' -f1)"
xcp_pe="$(git -C "$WORK/xcp" show "$xcp_e" | git patch-id --stable | cut -d' ' -f1)"
if [ -z "$xcp_pd" ] || [ "$xcp_pd" != "$xcp_pe" ]; then
  broken "arm X: the two commits do not share a patch-id, so the fallback \
this arm is about is not the thing being exercised"
fi
printf '%s %s\n' "$xcp_d" "$xcp_pd" | baseline_from "$WORK/xcp.base"

echo "arm X-cherrypick: declared $xcp_d, not reachable from HEAD"
echo "arm X-cherrypick: undeclared $xcp_e ($XCP_ID, unsigned) shares patch-id $xcp_pd"
arm X-cherrypick 6 "$WORK/xcp" "$WORK/xcp.base" \
  || broken "an unsigned commit that no row names, sharing a patch-id with a \
row that does, did not answer UNMEASURED-STALE. If it answered 0 the patch-id \
is exempting again and the repair is gone; if it answered 1 the written \
patch-id stopped accounting for the difference at all"
want_line "DECLARED-NOT-OBSERVED $xcp_d" "arm X-cherrypick reached 6 without \
naming the declared commit HEAD no longer reaches; naming it is what turns \
this exit into an instruction instead of a shrug"
want_line "UNDECLARED $xcp_e" "arm X-cherrypick reached 6 without naming the \
commit nothing declares"
reject_line "verdict: GREEN" "arm X-cherrypick let a patch-id coincidence \
carry an unsigned undeclared commit to GREEN, which is the defect this file \
was repaired for"
echo "arm X-cherrypick: the unsigned replay by $XCP_ID is no longer waved \
through. 6, and the two rows to look at are printed by name."

# ---- arm C: a comment is not a declaration, in both directions ------------
# The body is built by hand rather than by the judge: three rows carrying a
# short-sha and a date after the full sha, a '#' comment line above them and a
# bare '#' between the groups, and the remaining rows bare. If the shape this
# arm claims to test is not in the file, the arm proves nothing, so the shape
# is asserted before it is measured.
{ echo "# a group heading, which declares nothing"
  head -3 "$WORK/real_pairs.txt" | while read -r c_sha c_pid; do
      printf '%s %s  %s %s\n' "$c_sha" "$c_pid" \
        "$(git -C "$ROOT" log -1 --format=%h "$c_sha")" \
        "$(git -C "$ROOT" log -1 --format=%ad --date=short "$c_sha")"
    done
  echo "#"
  echo "# and the rest, declared as the bare pair"
  sed -n '4,$p' "$WORK/real_pairs.txt"; } > "$WORK/commented.body"
c_rows="$(grep -c '^[0-9a-f]\{40\}' "$WORK/commented.body")"
c_hashlines="$(grep -c '^#' "$WORK/commented.body")"
c_trailing="$(grep -c '^[0-9a-f]\{40\} [0-9a-f]\{40,64\}  .' \
  "$WORK/commented.body")"
if [ "$c_hashlines" -lt 2 ] || [ "$c_trailing" -lt 3 ]; then
  broken "arm C-comment built a body with $c_hashlines comment lines and \
$c_trailing rows carrying text after the patch-id; it must carry both or it is \
measuring a form it does not contain"
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
want_line "undeclared: 0" "arm C-comment answered GREEN over a non-empty \
undeclared set"
echo "arm C-comment: $c_rows pair rows, $c_hashlines comment lines, \
$c_trailing rows with text after the patch-id, declared=$c_rows undeclared=0"

c_hidden="$s_hidden"
sed '1s/^/# /' "$WORK/real_pairs.txt" | baseline_from "$WORK/hidden.base"
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
want_line "undeclared: $s_declared" "arm B-empty went RED over an undeclared \
set other than the $s_declared commits it declared nothing about"
want_line "every-undeclared-explained: no" "arm B-empty reached RED without \
the empty declaration being what failed to account for them"
echo "arm B-empty: the byte-identical empty declaration that answered GREEN \
in arm A answers RED here; the tree under it changed and the file did not"

# ---- arm H: a truncated history is not a smaller history ------------------
# The source is built here rather than cloned from $ROOT: the arm needs a
# baseline that is COMPLETE AND CORRECT for the repository under it, and a
# clone of $ROOT would carry $ROOT's declaration, whose correctness is arm N's
# subject and not this one's. Six commits, one of them unsigned, and the
# declaration enumerates exactly that one.
mkrepo "$WORK/hsrc"
csigned "$WORK/hsrc" h1.txt "h one signed"
csigned "$WORK/hsrc" h2.txt "h two signed"
cunsigned "$WORK/hsrc" h3.txt "h three unsigned"
csigned "$WORK/hsrc" h4.txt "h four signed"
csigned "$WORK/hsrc" h5.txt "h five signed"
csigned "$WORK/hsrc" h6.txt "h six signed"
# Read by arm H-partial's clone and by nothing else. A `--filter` clone from a
# source that does not advertise the capability is silently a full one, and the
# arm asserts the filter landed before it claims to have measured a partial.
git -C "$WORK/hsrc" config uploadpack.allowFilter true
git -C "$WORK/hsrc" log HEAD --format='%H %G?' | awk '$2=="N"{print $1}' \
  | pair_rows "$WORK/hsrc" > "$WORK/h.pairs"
h_rows="$(grep -c '^[0-9a-f]\{40\} ' "$WORK/h.pairs" || true)"
[ "$h_rows" -eq 1 ] || broken "arm H: the source repository holds $h_rows \
unattributed commits where the arm builds exactly one; the baseline it is \
about to write would not be the complete-and-correct declaration these arms \
need, and every H verdict would be about the wrong thing"
baseline_from "$WORK/h.base" < "$WORK/h.pairs"
h_unsigned="$(cut -d' ' -f1 "$WORK/h.pairs")"
h_full="$(git -C "$WORK/hsrc" rev-list --count HEAD)"

# Every clone below gets the SAME key list. Without this the clones would read
# U where the source reads G -- attributed either way, so the verdict would not
# move, but the arms would be varying two things and claiming one. Depth is the
# variable; the key list is held.
hpin() { # <clone dir>
  git -C "$1" config gpg.format ssh
  git -C "$1" config gpg.ssh.allowedSignersFile "$WORK/allowed_signers"
}

# file:// and not a plain path: git IGNORES --depth on a local-path clone and
# hands over the whole history, so a plain path would build a full clone this
# arm would then describe as shallow.
git clone -q --depth 2 "file://$WORK/hsrc" "$WORK/hshallow" \
  || broken "arm H-shallow: the shallow clone could not be made"
hpin "$WORK/hshallow"
[ "$(git -C "$WORK/hshallow" rev-parse --is-shallow-repository)" = "true" ] \
  || broken "arm H-shallow: the clone is not shallow, so the arm measures \
nothing about depth"
h_seen="$(git -C "$WORK/hshallow" rev-list --count HEAD)"
[ "$h_seen" -lt "$h_full" ] || broken "arm H-shallow: the clone reaches \
$h_seen of the source's $h_full commits, so the window truncates nothing"
# The reachable set, never `cat-file -e`. Whether an object happens to sit in
# the clone's pack is exactly the host-dependent question this judge refuses to
# ask, and an arm that asked it would be measuring by a rule the judge is
# forbidden to use.
git -C "$WORK/hshallow" log HEAD --format='%H' | grep -qx "$h_unsigned" \
  && broken "arm H-shallow: the depth window still reaches the one declared \
commit, so the arm would not exercise a window that misses a declared row"
echo "arm H-shallow: $h_seen of $h_full commits inside the window, the \
declared $h_unsigned outside it"
arm H-shallow 5 "$WORK/hshallow" "$WORK/h.base" \
  || broken "a shallow clone did not answer UNMEASURED-SHALLOW. Exit 1 is the \
defect this arm was armed against -- the judge accusing the repository of a \
discrepancy that belongs to --depth 2 -- and exit 0 is the same defect at a \
depth whose window happens to hold every declared row"
want_line "shallow: true" "arm H-shallow reached exit 5 without the judge \
saying what it read; the reader is owed the property the refusal turns on"
want_line "verdict: UNMEASURED-SHALLOW" "arm H-shallow reached exit 5 without \
the verdict; the arm is declared against the verdict, not against the number"
reject_line "verdict: RED" "arm H-shallow accused the repository of a \
discrepancy that is a property of the checkout"
reject_line "verdict: GREEN" "arm H-shallow certified a corpus the checkout \
chose"
reject_line "DECLARED-NOT-OBSERVED" "arm H-shallow named a declared row as \
missing from a set it had already refused to measure; the rows are not the \
finding here and printing them would send the operator to edit the baseline"
echo "arm H-shallow: UNMEASURED-SHALLOW, and no row named -- the declaration \
is not what is being measured at --depth 2"

# ---- arm H-full-control: the same clone, at full depth --------------------
git -C "$WORK/hshallow" fetch -q --unshallow \
  || broken "arm H-full-control: --unshallow failed, so there is no full-depth \
reading of this clone to compare against"
[ "$(git -C "$WORK/hshallow" rev-parse --is-shallow-repository)" = "false" ] \
  || broken "arm H-full-control: the clone is still shallow after --unshallow"
h_after="$(git -C "$WORK/hshallow" rev-list --count HEAD)"
[ "$h_after" -eq "$h_full" ] || broken "arm H-full-control: the unshallowed \
clone reaches $h_after of the source's $h_full commits"
arm H-full-control 0 "$WORK/hshallow" "$WORK/h.base" \
  || broken "the SAME clone, same baseline, unshallowed in place, did not \
answer GREEN; without this reading H-shallow's verdict could be about the \
declaration rather than about the depth"
want_line "undeclared: 0" "arm H-full-control answered GREEN over a non-empty \
undeclared set"
want_line "declared-not-observed: 0" "arm H-full-control answered GREEN with a \
declared row the observed set does not contain"
echo "arm H-full-control: same directory, same baseline, $h_seen -> $h_after \
commits, GREEN. Depth is the grandeur"

# ---- arm H-partial: not shallow, and the whole commit history -------------
# A partial clone and a shallow one get confused because both fetch less. They
# are different reductions: --depth truncates the COMMIT graph, --filter omits
# BLOBS and keeps every commit. Both properties are measured here before the
# arm claims either.
git clone -q --filter=blob:none "file://$WORK/hsrc" "$WORK/hpartial" \
  || broken "arm H-partial: the partial clone could not be made"
hpin "$WORK/hpartial"
h_filter="$(git -C "$WORK/hpartial" config --get remote.origin.partialclonefilter \
  || true)"
[ "$h_filter" = "blob:none" ] || broken "arm H-partial NOT APPLICABLE: the \
clone records the filter as '$h_filter' rather than blob:none, so this git \
built a full clone and the arm would be describing a partial it does not have"
[ "$(git -C "$WORK/hpartial" rev-parse --is-shallow-repository)" = "false" ] \
  || broken "arm H-partial: a blob:none clone answered 'true' to \
--is-shallow-repository on this git, which is the opposite of what this arm \
was measured to hold"
h_part="$(git -C "$WORK/hpartial" rev-list --count HEAD)"
[ "$h_part" -eq "$h_full" ] || broken "arm H-partial: the partial clone \
reaches $h_part of the source's $h_full commits, so it does NOT carry the \
complete commit history and the arm's premise is false on this git"
echo "arm H-partial: filter=$h_filter, shallow=false, $h_part of $h_full \
commits -- reduced in blobs, complete in commits"
arm H-partial 0 "$WORK/hpartial" "$WORK/h.base" \
  || broken "a blob:none clone that is not shallow and carries every commit \
did not answer as a full clone does; a guard keyed on 'fetched less' rather \
than on depth would land here"
want_line "declared-not-observed: 0" "arm H-partial answered GREEN with a \
declared row the observed set does not contain"
echo "arm H-partial: GREEN, exactly as the full clone above -- the filter \
reduces blobs and the judge reads commits"

# ---- arm V: the preflight refuses to measure, and never covers ------------
# The three H arms above measure a truncated clone this fixture BUILDS. These
# three measure THIS FIXTURE, run from inside a truncated checkout of this
# repository, because $ROOT is the one repository the arms cannot choose.
#
# WHY $ROOT IS NOT LIKE THE OTHER CORPORA, measured at the basis that armed
# this block. EIGHT arms invoke the judge with --repo "$ROOT" -- Z-baseline, N,
# S-bogus-row, S-sha-only, C-comment, C-commented-out, B-nosection, B-empty.
# TWO MORE, P-pre and P, run against a clone of $ROOT and inherit its depth: a
# clone of a shallow repository answers `true` to --is-shallow-repository and
# reaches the same commits, which was measured on this git and not assumed. And
# the block that builds the baseline all ten share reads $ROOT's own log and
# calls broken when the depth window holds no unattributed commit at all. On a
# shallow checkout every one of those ten asks its question about a corpus the
# checkout chose.
#
# WHAT THE FIXTURE ANSWERS TODAY IS 4, AND 4 IS THE WRONG NUMBER. FIXTURE
# BROKEN says a control could not confirm what it is measuring. Here the
# control answered: arm Z-baseline wanted 3 and the judge said 5
# UNMEASURED-SHALLOW, correctly, about a tree that is not measurable. The
# fixture then reported its own health where the tree's was the finding.
#
# THE PREFLIGHT MUST NOT SHORT-CIRCUIT THE FIXTURE, and that is the risk this
# block exists to hold rather than to describe. A guard that answered
# "unmeasurable" for the WHOLE file the moment $ROOT looked truncated would
# hide every defect in the nine arms that build their own repositories and
# never read $ROOT. It would make a shallow checkout a place where this
# falsifier certifies nothing AND accuses nothing, which is worse than the 4 it
# replaces, and it would be reached by cloning shallower. So the three arms are
# one claim in three parts:
#
#   V-shallow-root     $ROOT shallow -> 5 UNMEASURED-SHALLOW. The arms that
#                      read $ROOT each say they were skipped and why, in both
#                      regions of the file; the scratch arms are observed
#                      running, first and last.
#   V-full-root        THE SAME CHECKOUT, `git fetch --unshallow`-ed in place
#                      -> 0. Same directory, same objects source, same fixture
#                      file; only the depth moved. Without it the guard would
#                      be indistinguishable from a permanent exemption for
#                      anything that ever looked truncated.
#   V-scratch-visible  $ROOT shallow AND one scratch arm genuinely broken -> 4,
#                      NOT 5, and the inner run names the BROKEN SCRATCH ARM
#                      and not a skipped $ROOT arm. THE EXIT CODE ALONE PROVES
#                      NOTHING HERE: the unrepaired fixture answers 4 to this
#                      same checkout, for the other reason. This is the arm
#                      that fails if the preflight ever grows into a cover.
#
# THE FIXTURE UNDER TEST IS THIS FILE, copied into the checkout and asserted
# byte-identical, never the one the checkout was cloned with. A clone carries
# the last COMMIT; the subject here is the tree being judged, and an arm that
# measured HEAD would let a working tree ship a preflight nobody ran -- the
# object half of the defect bypass_ft_surface_charges_untouched_occurrences
# was written for, one level up.
#
# The inner runs carry FT37_META=1, and that is what stops this block from
# recursing: without it V-full-root's inner run would build its own checkouts
# and run its own V arms, without end.
if [ -z "${FT37_META:-}" ]; then
  SELF_NAME="$(basename "$0")"
  SELF="$ROOT/tests/$SELF_NAME"
  [ -f "$SELF" ] || broken "arm V: this fixture is not at tests/$SELF_NAME \
under its own root, so the arms below would run a file that is not the one \
under test"

  V_OUT=""
  # The inner run's own judge output is not re-printed line for line -- three
  # nested runs would bury the register's log. The arm lines, the skip lines
  # and the verdict are, and every assertion below is made against the WHOLE
  # captured output and not against this summary.
  varm() { # name want checkout
    local v_name="$1" v_want="$2" v_rc
    set +e
    V_OUT="$(FT37_META=1 bash "$3/tests/$SELF_NAME" 2>&1)"
    v_rc=$?
    printf '%s\n' "$V_OUT" \
      | grep -E '^(arm |skipped \[|FIXTURE BROKEN|GREEN|RED|UNMEASURED)' \
      | sed "s/^/  [$v_name] /"
    set -e
    echo "arm $v_name: exit $v_rc (want $v_want)"
    [ "$v_rc" -eq "$v_want" ]
  }

  v_want_line() { # needle description
    printf '%s\n' "$V_OUT" | grep -qF -- "$1" \
      || broken "$2 -- the inner run exited as wanted and never printed \"$1\""
  }

  v_reject_line() { # needle description
    if printf '%s\n' "$V_OUT" | grep -qF -- "$1"; then
      broken "$2 -- the inner run printed \"$1\""
    fi
  }

  # file:// and not a plain path, for the reason arm H-shallow gives: git
  # IGNORES --depth on a local-path clone and hands over the whole history.
  git clone -q --depth 2 "file://$ROOT" "$WORK/vroot" \
    || broken "arm V: could not build a depth-bounded checkout of this \
repository"
  [ "$(git -C "$WORK/vroot" rev-parse --is-shallow-repository)" = "true" ] \
    || broken "arm V: the checkout it built answers 'false' to \
--is-shallow-repository, so these arms would measure nothing about depth"
  [ "$(git -C "$WORK/vroot" rev-list --count HEAD)" \
    -lt "$(git -C "$ROOT" rev-list --count HEAD)" ] \
    || broken "arm V: the depth window truncates nothing, so the checkout is \
not the truncated one these arms are about"
  cp "$SELF" "$WORK/vroot/tests/$SELF_NAME" \
    || broken "arm V: could not install the fixture under test into the checkout"
  cmp -s "$SELF" "$WORK/vroot/tests/$SELF_NAME" \
    || broken "arm V: the installed fixture is not byte-identical to this file, \
so the arms would be measuring the last commit and not this tree"

  varm V-shallow-root 5 "$WORK/vroot" \
    || broken "this fixture, run from inside a depth-bounded checkout of this \
repository, did not answer UNMEASURED-SHALLOW. Exit 4 is the defect this arm \
was armed against: FIXTURE BROKEN reports a control that could not confirm \
what it measures, and here the control answered -- it is the tree under it \
that is not measurable"
  # The needle is the TAIL verdict and not the bare word. Arm H-shallow prints
  # "verdict: UNMEASURED-SHALLOW" about its own scratch clone on every run,
  # green or not, so an assertion on that string would be satisfied by an inner
  # run that never refused anything -- measured, on the inner run this block
  # was armed against.
  v_want_line "UNMEASURED-SHALLOW: the history is truncated" "arm \
V-shallow-root reached exit 5 without the inner run reaching that verdict for \
its own root; the arm is declared against the verdict, not against the number"
  v_want_line "skipped [Z-baseline]" "arm V-shallow-root: the inner run never \
said that the first arm reading its own history was skipped, so a reader is \
not told which questions went unasked"
  v_want_line "skipped [P]" "arm V-shallow-root: the inner run ran an arm \
against a clone of a shallow checkout, and such a clone inherits the depth the \
run had already refused to judge on"
  v_want_line "skipped [B-empty]" "arm V-shallow-root: the inner run skipped \
the first group of arms reading its own history and not the last"
  v_want_line "arm A: scanned=" "arm V-shallow-root: a scratch arm did not run \
under the preflight, so the guard is covering the file rather than refusing to \
judge the tree"
  v_want_line "arm H-partial: GREEN" "arm V-shallow-root: the last scratch arm \
did not run, so the inner run stopped early rather than skipping selectively"
  v_reject_line "FIXTURE BROKEN" "arm V-shallow-root reached exit 5 through a \
broken control rather than through the preflight"
  echo "arm V-shallow-root: UNMEASURED-SHALLOW; the arms reading this \
repository's own history skipped by name in both regions, the scratch arms \
observed running from the first to the last"

  git -C "$WORK/vroot" fetch -q --unshallow \
    || broken "arm V-full-root: --unshallow failed, so there is no full-depth \
reading of this same checkout to compare against"
  [ "$(git -C "$WORK/vroot" rev-parse --is-shallow-repository)" = "false" ] \
    || broken "arm V-full-root: the checkout is still shallow after --unshallow"
  cmp -s "$SELF" "$WORK/vroot/tests/$SELF_NAME" \
    || broken "arm V-full-root: the fixture under test moved between the two \
readings, so depth is not the only thing that changed"
  varm V-full-root 0 "$WORK/vroot" \
    || broken "the SAME checkout, same directory, same fixture file, \
unshallowed in place, did not answer GREEN; without this reading \
V-shallow-root's 5 could be about anything that checkout carries rather than \
about its depth"
  v_want_line "verdict: GREEN" "arm V-full-root answered 0 without the inner \
run reaching GREEN"
  v_reject_line "UNMEASURED-SHALLOW: the history is truncated" "arm \
V-full-root: the preflight fired on a checkout that is not shallow, which is a \
permanent exemption and not a guard"
  v_reject_line "skipped [" "arm V-full-root: an arm was skipped on a checkout \
that carries the whole history"
  echo "arm V-full-root: the same directory and the same fixture, depth the \
only difference, GREEN. Depth is the grandeur here too"

  # The sabotage is ONE arm's declared want, in a copy, and both halves are
  # asserted before the inner run is asked anything: that the line moved, and
  # that NOTHING ELSE did. An arm that sabotaged more than it meant to would
  # answer 4 for a reason it could not name, which is the shape of the defect
  # it is here to refuse.
  git clone -q --depth 2 "file://$ROOT" "$WORK/vsab" \
    || broken "arm V-scratch-visible: could not build the second depth-bounded \
checkout"
  [ "$(git -C "$WORK/vsab" rev-parse --is-shallow-repository)" = "true" ] \
    || broken "arm V-scratch-visible: the second checkout is not shallow, so \
the arm would not be measuring a preflight at all"
  sed 's/^arm A 0 /arm A 1 /' "$SELF" > "$WORK/vsab/tests/$SELF_NAME" \
    || broken "arm V-scratch-visible: could not install the sabotaged fixture"
  grep -q '^arm A 1 ' "$WORK/vsab/tests/$SELF_NAME" \
    || broken "arm V-scratch-visible: the sabotage did not land, so the arm \
would be measuring an unbroken fixture and its 4 would mean nothing"
  v_sabotage="$(diff "$SELF" "$WORK/vsab/tests/$SELF_NAME" \
    | grep -c '^[<>]' || true)"
  [ "$v_sabotage" -eq 2 ] || broken "arm V-scratch-visible: the sabotage \
rewrote $v_sabotage lines where it must rewrite exactly one, so the inner \
run's exit could be about something other than the scratch arm it names"
  varm V-scratch-visible 4 "$WORK/vsab" \
    || broken "a shallow checkout carrying a genuinely broken SCRATCH arm did \
not answer FIXTURE BROKEN. If it answered 5 the preflight is covering real \
defects, which is the failure this arm exists to make expensive"
  v_want_line "did not answer GREEN against an empty declaration" \
    "arm V-scratch-visible reached exit 4 without the inner run naming the \
broken scratch arm. Before the preflight the same checkout answered 4 from arm \
Z-baseline, so an assertion on the exit code alone proves nothing here"
  v_reject_line "an absent baseline did not answer UNMEASURED-BASELINE" \
    "arm V-scratch-visible: the inner run broke on an arm reading its own \
history rather than on the sabotaged scratch arm, so the preflight never ran"
  v_want_line "skipped [Z-baseline]" "arm V-scratch-visible: the inner run \
reached the broken scratch arm without skipping the arms that read its own \
history, so the 4 did not come through the preflight"
  echo "arm V-scratch-visible: 4 and not 5, and the inner run names the broken \
scratch arm -- the preflight refuses to measure and does not cover"
fi

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
  5) echo "UNMEASURED-SHALLOW: the history is truncated, so the set read is this checkout's depth window and not this history -- unshallow the clone and ask again" ;;
  6) echo "UNMEASURED-STALE: every difference is accounted for by a declared patch-id, and a patch-id never certifies -- re-declare the rows named above" ;;
  *) broken "the judge answered an exit outside its contract: $p_rc" ;;
esac
exit "$p_rc"
