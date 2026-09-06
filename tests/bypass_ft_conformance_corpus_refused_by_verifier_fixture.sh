#!/usr/bin/env bash
# conformance-corpus-refused-by-verifier -- the tracked corpus of
# conformance records contains records the tracked verifier refuses. That
# is the whole of what this file measures, and it measures it in the
# tracked tree, not only on a clone.
#
# NOT A ROUND-TRIP, and the name this file carried until now asserted one.
# The tracked emitter scripts/conformance_record.py writes
# `"transformation": None` (line 236) and never populates that object, and
# no tracked program writes the `completeness` key the three records carry
# inside it. The refused records therefore have no tracked producer, and no
# emitter -> verifier loop is under measurement here. One direction only:
# which records in the corpus the verifier refuses.
#
# THE VERDICT STRING SAYS ONLY WHAT WAS MEASURED. It read "records this
# repository emits" while the paragraph above it recorded that no tracked
# emitter produces them -- the file contradicted itself on its own most
# visible line, and the claim pinned the contradiction as an expected
# substring. What the corpus leg actually resolves is the TRACKED record
# set, so the line now reads "records tracked in this repository". The
# measurement did not change; the sentence stopped overstating it.
#
# WHAT IS MEASURED, and by what. Three legs, each RESOLVED BY CONTENT and
# never by the name of a file or of the directory holding it:
#   verifier  the tracked .py whose module-level KEYSETS declares a closed
#             keyset for `transformation` (read statically, ast, no import
#             and no execution)
#   emitter   a tracked .py that declares the same module-level
#             PREDICATE_TYPE as the verifier and declares no KEYSETS of its
#             own -- it writes records of that type rather than judging them
#   corpus    every file under the corpus root that parses as JSON and whose
#             top-level predicateType equals the verifier's. Under a git
#             repository the corpus is the TRACKED set, so the control is
#             the same in a fresh clone as it is in a dirty working tree.
# A hit is one record the verifier rejects with a reason of the form
# "<where> carries keys outside the closed vocabulary: <keys>". The class,
# not one instance of it: any object whose closed keyset the emitter
# overflows is the same defect.
#
# EXIT CONTRACT of the judge, and of this fixture. Six codes, all distinct.
# GREEN and UNMEASURED never share one: an exit that cannot tell "nothing
# was found" from "nothing was looked at" reports a vacuum as a pass, and
# that is the defect this file refuses to reproduce.
#   0  GREEN              corpus non-empty, zero hits
#   1  RED                corpus non-empty, hits > 0
#   2  UNMEASURED corpus  corpus root absent, or resolved to zero records
#   3  UNMEASURED emitter no emitter located
#   5  UNMEASURED verifier no verifier located
#   4  FIXTURE BROKEN     a control arm did not answer what it must
# The suite's register reads 2 through its UNMEASURED-2 door and 3, 4 and 5
# as EXIT<n>, which fails the row loudly. That is the right routing: each of
# them says this tree cannot run its own falsifier.
#
# FIVE ARMS:
#   P  positive control: the tracked corpus of this repository  -> want 1
#   N  negative control: one synthetic record whose transformation carries
#      {id, sha256} and nothing else, on a corpus of one       -> want 0,
#      and the corpus count it prints must be 1, not 0
#   G  anti-vacuity BY GENERATION, not by grep: twelve generated records,
#      none carrying a key outside any closed keyset           -> want 0
#      with a printed corpus count of 12; and the same twelve with ONE
#      mutated to carry the offending key                      -> want 1
#      with exactly one hit. The pair is what shows the measured quantity
#      is real and was driven to zero, rather than never taken.
#   Z  null case: an empty corpus root                         -> want 2,
#      never 0
#   E  emitter leg: the real corpus, measured against a repository copy
#      that holds the verifier and no emitter                  -> want 3
#
# RED is this file's DECLARED state and the state it was observed in. It is
# not repaired here: the repair moves either the closed vocabulary or the
# emitter, and both are outside the commit that installs the judge.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ftcrcv.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

broken() { echo "FIXTURE BROKEN: $*" >&2; exit 4; }

cat > "$WORK/judge.py" <<'JUDGE'
"""Round-trip judge: emitter -> verifier, over a corpus of records.

  judge.py --repo REPO --corpus DIR

Exits 0 GREEN, 1 RED, 2 UNMEASURED-corpus, 3 UNMEASURED-emitter,
5 UNMEASURED-verifier. Every leg is resolved from content.
"""
import ast
import json
import os
import subprocess
import sys

MARK = "carries keys outside the closed vocabulary"


def out(line):
    sys.stdout.write(line + "\n")


def module_consts(path):
    """Module-level literal assignments, without importing the module.

    ast.literal_eval folds implicit string concatenation, so a constant
    spelled across two parenthesised lines reads as the one string it is.
    Nothing in the candidate file executes.
    """
    try:
        with open(path, "rb") as fh:
            tree = ast.parse(fh.read(), filename=path)
    except (OSError, SyntaxError, ValueError):
        return {}
    consts = {}
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        for target in node.targets:
            if not isinstance(target, ast.Name):
                continue
            try:
                consts[target.id] = ast.literal_eval(node.value)
            except (ValueError, TypeError, SyntaxError, MemoryError,
                    RecursionError):
                consts[target.id] = None
    return consts


def tracked_python(repo):
    proc = subprocess.run(["git", "-C", repo, "ls-files", "-z", "--", "*.py"],
                          capture_output=True)
    if proc.returncode != 0:
        return []
    return [os.path.join(repo, p)
            for p in proc.stdout.decode("utf-8").split("\0") if p]


def resolve_legs(repo):
    """The verifier declares a closed keyset for `transformation`; an
    emitter declares the same record type and no keyset of its own."""
    verifier = None
    emitters = []
    candidates = []
    for path in tracked_python(repo):
        consts = module_consts(path)
        keysets = consts.get("KEYSETS")
        pt = consts.get("PREDICATE_TYPE")
        if isinstance(keysets, dict) and "transformation" in keysets:
            if verifier is None:
                verifier = (path, pt, keysets)
            continue
        if isinstance(pt, str):
            candidates.append((path, pt))
    if verifier is not None:
        emitters = [p for p, pt in candidates if pt == verifier[1]]
    return verifier, emitters


def corpus_files(root):
    """Under a git repository the corpus is the tracked set: a working tree
    carrying scratch records must not enlarge or shrink the control."""
    if not os.path.isdir(root):
        return None
    proc = subprocess.run(["git", "-C", root, "ls-files", "-z"],
                          capture_output=True)
    if proc.returncode == 0:
        return [os.path.join(root, p)
                for p in proc.stdout.decode("utf-8").split("\0") if p]
    found = []
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            found.append(os.path.join(dirpath, name))
    return found


def records(paths, predicate_type):
    hits = []
    for path in paths:
        try:
            with open(path, "rb") as fh:
                raw = fh.read()
            obj = json.loads(raw.decode("utf-8"))
        except (OSError, UnicodeDecodeError, ValueError):
            continue
        if isinstance(obj, dict) and obj.get("predicateType") == predicate_type:
            hits.append(path)
    return sorted(hits)


def main(argv):
    repo = corpus = None
    i = 0
    while i < len(argv):
        if argv[i] == "--repo":
            repo = argv[i + 1]
            i += 2
        elif argv[i] == "--corpus":
            corpus = argv[i + 1]
            i += 2
        else:
            out("verdict: UNMEASURED-CORPUS")
            out("  unknown argument %r" % argv[i])
            return 2
    if repo is None or corpus is None:
        out("verdict: UNMEASURED-CORPUS")
        out("  --repo and --corpus are both required")
        return 2

    verifier, emitters = resolve_legs(repo)
    if verifier is None:
        out("verdict: UNMEASURED-VERIFIER")
        out("  no tracked module declares a closed keyset for transformation")
        return 5
    vpath, predicate_type, keysets = verifier
    out("verifier: %s" % os.path.relpath(vpath, repo))
    out("closed keyset transformation: %s"
        % ",".join(sorted(keysets["transformation"])))
    if not emitters:
        out("verdict: UNMEASURED-EMITTER")
        out("  no tracked module declares PREDICATE_TYPE %s without also "
            "declaring a keyset of its own" % predicate_type)
        return 3
    for path in sorted(emitters):
        out("emitter: %s" % os.path.relpath(path, repo))

    paths = corpus_files(corpus)
    if paths is None:
        out("corpus: 0 records read from %s (root absent)" % corpus)
        out("verdict: UNMEASURED-CORPUS")
        return 2
    found = records(paths, predicate_type)
    out("corpus: %d record(s) read from %s" % (len(found), corpus))
    if not found:
        out("verdict: UNMEASURED-CORPUS")
        out("  the root resolved, and no file under it declares "
            "predicateType %s" % predicate_type)
        return 2

    hits = 0
    for path in found:
        proc = subprocess.run([sys.executable, vpath, path],
                              capture_output=True, text=True)
        for line in (proc.stdout + proc.stderr).splitlines():
            if MARK in line:
                hits += 1
                out("hit: %s -- %s" % (os.path.basename(path), line.strip()))
                break
    out("hits: %d" % hits)
    if hits:
        out("verdict: RED")
        return 1
    out("verdict: GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
JUDGE

cat > "$WORK/mkrec.py" <<'MKREC'
"""Write one canonical synthetic conformance record.

  mkrec.py OUT PREDICATE_TYPE STATEMENT_TYPE RULE_ID TAG [EXTRA_KEY]

Canonical form is not decoration: the verifier refuses a record whose bytes
are not the canonical serialisation, and a record refused there never
reaches the closed-vocabulary check the judge is measuring. EXTRA_KEY, when
given, is the key written into `transformation` that the vocabulary does
not admit.
"""
import hashlib
import json
import sys

out, ptype, stype, rule_id, tag = sys.argv[1:6]
extra = sys.argv[6] if len(sys.argv) > 6 else None


def hexof(text, width):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:width]


transformation = {
    "id": "path-transform/v1",
    "sha256": hexof("rule" + tag, 64),
}
if extra:
    transformation[extra] = {"note": "a key the closed vocabulary omits"}

statement = {
    "_type": stype,
    "predicateType": ptype,
    "subject": [{"digest": {"sha256": hexof("subject" + tag, 64)},
                 "name": "stream.jsonl"}],
    "predicate": {
        "anchor": {"declarationEntry": hexof("decl" + tag, 40),
                   "streamEntry": hexof("stream" + tag, 40)},
        "comparisonRule": {"id": rule_id, "sha256": hexof("cmp" + tag, 64)},
        "completeness": {"streamResultEvent": True},
        "declaredSurface": {"allowedTools": [], "maxSpawnDepth": 2,
                            "permissionMode": "manual", "tools": ["Read"]},
        "delegations": [],
        "evidence": [{"name": "stream.jsonl", "role": "stream",
                      "sha256": hexof("subject" + tag, 64)}],
        "exercised": [],
        "measurement": {"run": tag, "source": tag},
        "transformation": transformation,
        "unusedAuthorizations": ["Read"],
    },
}
blob = json.dumps(statement, sort_keys=True, separators=(",", ":"),
                  ensure_ascii=False).encode("utf-8")
with open(out, "wb") as fh:
    fh.write(blob)
MKREC

# The record type and the rule id are read from the verifier this repository
# tracks, never spelled a second time here: a fixture that hard-codes the
# contract it is checking stops measuring the contract the moment it moves.
consts="$(python3 - "$ROOT" <<'CONSTS'
import ast
import os
import subprocess
import sys

repo = sys.argv[1]
proc = subprocess.run(["git", "-C", repo, "ls-files", "-z", "--", "*.py"],
                      capture_output=True)
for rel in proc.stdout.decode("utf-8").split("\0"):
    if not rel:
        continue
    path = os.path.join(repo, rel)
    try:
        with open(path, "rb") as fh:
            tree = ast.parse(fh.read(), filename=path)
    except (OSError, SyntaxError, ValueError):
        continue
    found = {}
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        for target in node.targets:
            if isinstance(target, ast.Name):
                try:
                    found[target.id] = ast.literal_eval(node.value)
                except Exception:
                    pass
    ks = found.get("KEYSETS")
    if isinstance(ks, dict) and "transformation" in ks:
        print(found.get("PREDICATE_TYPE", ""))
        print(found.get("STATEMENT_TYPE", ""))
        print(found.get("RULE_ID", ""))
        break
CONSTS
)" || broken "could not read the verifier's declared constants"
PTYPE="$(printf '%s\n' "$consts" | sed -n 1p)"
STYPE="$(printf '%s\n' "$consts" | sed -n 2p)"
RULEID="$(printf '%s\n' "$consts" | sed -n 3p)"
if [ -z "$PTYPE" ] || [ -z "$STYPE" ] || [ -z "$RULEID" ]; then
  broken "the verifier declared no PREDICATE_TYPE/STATEMENT_TYPE/RULE_ID"
fi

judge() {
  local corpus="$1" repo="${2:-$ROOT}"
  python3 "$WORK/judge.py" --repo "$repo" --corpus "$corpus" 2>&1
}

arm() {
  local name="$1" want="$2" corpus="$3" repo="${4:-$ROOT}"
  local text rc
  set +e
  text="$(judge "$corpus" "$repo")"
  rc=$?
  set -e
  printf '%s\n' "$text" | sed "s/^/  [$name] /"
  echo "  [$name] exit $rc (want $want)"
  ARM_TEXT="$text"
  ARM_RC="$rc"
  [ "$rc" = "$want" ]
}

# Arm P is the only arm whose answer is the fixture's answer, so it is read
# and never asserted here: the register at the tail of the suite is where
# the expected state is declared, and a fixture that also declares it would
# be grading its own homework.
echo "== arm P: positive control, the tracked corpus of this repository =="
set +e
arm P 1 "$ROOT"
set -e
p_rc="$ARM_RC"

echo "== arm N: negative control, transformation = {id, sha256} only =="
mkdir -p "$WORK/neg"
python3 "$WORK/mkrec.py" "$WORK/neg/one.json" "$PTYPE" "$STYPE" "$RULEID" n1 \
  || broken "could not write the negative control record"
arm N 0 "$WORK/neg" || broken \
  "the negative control did not answer GREEN; the judge cannot tell a clean \
record from a dirty one, so arm P proves nothing"
printf '%s\n' "$ARM_TEXT" | grep -q '^corpus: 1 record' || broken \
  "the negative control answered GREEN over a corpus it reported as other \
than 1 record; GREEN by emptiness is the vacuum this arm exists to exclude"

echo "== arm G: anti-vacuity by generation, twelve records =="
mkdir -p "$WORK/gen"
i=1
while [ "$i" -le 12 ]; do
  python3 "$WORK/mkrec.py" "$WORK/gen/g$i.json" "$PTYPE" "$STYPE" "$RULEID" \
    "g$i" || broken "could not generate record g$i"
  i=$((i + 1))
done
arm G-clean 0 "$WORK/gen" || broken \
  "a generated corpus carrying no out-of-vocabulary key did not answer GREEN"
printf '%s\n' "$ARM_TEXT" | grep -q '^corpus: 12 record' || broken \
  "the generated corpus did not resolve to the twelve records written into \
it; a count that is not the count generated measures something else"
cp -R "$WORK/gen" "$WORK/gen-mutant"
python3 "$WORK/mkrec.py" "$WORK/gen-mutant/g7.json" "$PTYPE" "$STYPE" \
  "$RULEID" g7 completeness \
  || broken "could not write the mutated record"
arm G-mutant 1 "$WORK/gen-mutant" || broken \
  "one record out of twelve carries a key outside the closed vocabulary and \
the judge did not see it; the quantity arm G-clean drove to zero was never \
being measured"
printf '%s\n' "$ARM_TEXT" | grep -q '^hits: 1' || broken \
  "the mutated corpus answered RED on a hit count other than the single \
record mutated"

echo "== arm Z: null case, an empty corpus root =="
mkdir -p "$WORK/empty"
arm Z 2 "$WORK/empty" || broken \
  "an empty corpus did not answer UNMEASURED; a corpus nobody read must \
never be reported as a corpus with nothing in it"

echo "== arm E: the emitter leg, a repository copy holding no emitter =="
mkdir -p "$WORK/noemit"
git -C "$WORK/noemit" init -q || broken "could not init the emitter-less copy"
git -C "$WORK/noemit" config user.email t@example.invalid
git -C "$WORK/noemit" config user.name tester
git -C "$WORK/noemit" config commit.gpgsign false
mkdir -p "$WORK/noemit/scripts"
VERIFIER_REL="$(python3 "$WORK/judge.py" --repo "$ROOT" \
  --corpus "$WORK/empty" 2>&1 | sed -n 's/^verifier: //p')"
[ -n "$VERIFIER_REL" ] || broken "the judge named no verifier to copy"
cp "$ROOT/$VERIFIER_REL" "$WORK/noemit/scripts/" \
  || broken "could not copy the verifier into the emitter-less copy"
git -C "$WORK/noemit" add -- scripts \
  || broken "could not track the verifier in the emitter-less copy"
git -C "$WORK/noemit" commit -q -m "verifier only" \
  || broken "could not commit the emitter-less copy"
arm E 3 "$ROOT" "$WORK/noemit" || broken \
  "a repository with no emitter did not answer UNMEASURED-EMITTER; the \
round-trip has one leg missing and the judge reported a measurement"

echo "== verdict =="
case "$p_rc" in
  0) echo "GREEN: the emitter's records pass the verifier that reads them"; ;;
  1) echo "RED: the verifier refuses records tracked in this repository"; ;;
  2) echo "UNMEASURED: the corpus did not resolve"; ;;
  3) echo "UNMEASURED: no emitter located"; ;;
  5) echo "UNMEASURED: no verifier located"; ;;
  *) broken "arm P answered an exit outside the judge's contract: $p_rc" ;;
esac
exit "$p_rc"
