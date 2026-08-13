#!/usr/bin/env bash
# bypass_att_dirty_tree_subject -- the falsifier ADR-019 D2 names.
#
# THE ASSERTION (ADR-019 Verification, verbatim): "A fixture that emits a
# Statement on a dirty tree and asserts that `subject[0]` is **not** `HEAD`'s
# commit. Its value is that it fails on the *easy* implementation: the one that
# reaches for `git rev-parse HEAD` because it is available at `:52` and produces
# a well-formed artifact."
#
# WHY THE EASY IMPLEMENTATION IS THE LIKELY ONE, and it is worth restating because
# it is what this row defends against. `HALT_ROOT` is set from
# `git rev-parse --show-toplevel` at scripts/launch_worker.sh:52, so `HEAD` is
# derivable at receipt time for free, while the transcript's digest costs a line
# that did not exist until this commit. A producer under time pressure reaches for
# the value that is already in hand. What that buys is a Statement that NAMES A
# COMMIT AND ATTESTS TO A TREE THAT IS NOT THAT COMMIT -- `measure_criteria`
# measures the working tree (`vout="$(cd "$HALT_ROOT" && node "$VERITY_CLI" verify
# --json ...)"`, no `git` invocation anywhere in the function) and
# `write_receipt.py:89` writes `"phase": "working-tree-advisory"` unconditionally.
# Well-formed, machine-readable, and wrong.
#
# THE NAIVE FORM OF THIS ASSERTION IS VACUOUS, AND THE FIXTURE SAYS SO RATHER
# THAN INHERITING IT. `git rev-parse --show-object-format` returns `sha1` in this
# repository (ADR-018 D2 measured the same), so a commit id is 40 hex characters
# and a sha256 is 64: "subject[0].digest.sha256 != HEAD" can never be false by
# accident. A row resting on that comparison alone would be green because two
# string lengths differ, which is a fact about SHA-1 and not about this decision.
# So the predicate is shown to REFUSE the easy implementation's artifact, in both
# spellings a producer could reach for, before it is allowed to accept the real
# one:
#
#   control 1  subject[0].digest = {"sha256": "<HEAD>"} -- the easy value under
#              the wrong algorithm name. ADR-018 D2: "A git object id **is never
#              called `sha256`**", `digest_set.md:103` registers `gitCommit` for
#              exactly this.
#   control 2  subject[0].digest = {"gitCommit": "<HEAD>"} -- the easy value,
#              correctly labelled. Still refused, because the objection is not
#              the spelling: it is that HEAD is not what the gate measured.
#   control 3  a Statement whose subject IS the transcript must be ACCEPTED,
#              or a predicate refusing everything would look identical.
#   the row    the Statement the launcher in tree emits on a DIRTY tree must be
#              accepted, and its digest must equal the transcript's recomputed
#              bytes.
#
# THE PREMISE IS MEASURED, NOT ASSUMED. `git status --porcelain` is read in the
# run's own repository at the moment of the assertion, and a clean tree aborts the
# fixture rather than producing a green: on a clean tree the run is not the case
# D2 is about. ADR-019 records that "every measured run so far was on a dirty
# tree", which is why the dirty case is the one that has to hold.
#
# DECLARED GREEN, and this header is where the register reads that (ADR-017 D6).
#
# Nothing outside $WORK is written. The repository under measurement is created by
# this fixture inside its own scratch directory; harness-pack's own tree is read
# for execution only and its git state is never consulted or changed.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$PACK/scripts/launch_worker.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-att-dirty.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$LAUNCHER" ] || broken "scripts/launch_worker.sh is not where this fixture expects it"
command -v node >/dev/null 2>&1 || broken "node is not available; the launcher's two collaborators are node CLIs"

printf '%s' '{"manifest_version":1,"verifier_id":"https://verifier.example.invalid/harness-pack/v1","model_tiers":{"worker":"T3"},"tiers":{"T3":{"name":"subagent","chain":["HAIKU_CLASS_MODEL"]}}}' > "$WORK/manifest.json"

# The predicate. Prints ACCEPT / REJECT <reason>, exits 0 / 1.
#   argv[1] statement   argv[2] the transcript's sha256   argv[3] HEAD's commit id
cat > "$WORK/subject_is_transcript.py" <<'PREDICATE'
import json, sys

GIT_ALGS = {"gitcommit", "gittree", "gitblob", "gittag"}

def reject(reason):
    print("REJECT " + reason)
    sys.exit(1)

st = json.load(open(sys.argv[1]))
want, head = sys.argv[2], sys.argv[3]
subject = (st.get("subject") or [None])[0]
if not isinstance(subject, dict):
    reject("subject[0] is absent")
digest = subject.get("digest")
if not isinstance(digest, dict) or not digest:
    reject("subject[0].digest is absent or empty")

# (a) HEAD may never be the subject, whatever it is called.
for alg, value in digest.items():
    if alg.lower() in GIT_ALGS:
        reject("subject[0].digest carries a git object id under %r; ADR-019 D2 -- HEAD may appear as an "
               "annotation that declares itself to be one, never as subject" % (alg,))
    if isinstance(value, str) and head and value.strip().lower() == head.strip().lower():
        reject("subject[0].digest[%r] IS HEAD (%s); the Statement would name a commit and attest to a "
               "tree that is not that commit" % (alg, head))

# (b) the subject must be the transcript, by recomputed digest and not by shape.
got = digest.get("sha256")
if not isinstance(got, str) or got != want:
    reject("subject[0].digest.sha256 is %r, and the transcript's bytes hash to %r" % (got, want))
print("ACCEPT subject[0].digest.sha256 is the transcript, and HEAD %s appears nowhere in it" % (head[:12],))
sys.exit(0)
PREDICATE

# ---- the launcher's collaborators, stubbed -----------------------------------
mkdir -p "$WORK/bin"
cat > "$WORK/bin/claude" <<'CLAUDE_STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "0.0.0-fixture (stub)"; exit 0; fi
cat >/dev/null
# Inert on purpose: it changes nothing and commits nothing, so the tree it was
# handed is the tree the assertion measures.
printf '%s\n' '{"subtype":"success","num_turns":2,"total_cost_usd":0.01,"duration_ms":900,"session_id":"fixture-session"}'
CLAUDE_STUB
chmod +x "$WORK/bin/claude"

cat > "$WORK/hw.js" <<'HW_STUB'
process.stdout.write(JSON.stringify({
  kind: "unlocked", id: "S-DEMO", eligible_mode_b: true,
  spec: { model: "worker", tools: ["Read"], criteria: ["c1"],
          budget: { turns: 5, wall_clock: "30m" }, scope: ["README.md"] }
}));
HW_STUB

cat > "$WORK/verity.js" <<'VERITY_STUB'
process.stdout.write(JSON.stringify({
  results: [ { id: "c1", type: "command", verdict: "PASS", evidence: "exit 0" } ]
}));
VERITY_STUB

# ---- a repository with a commit, and a tree that has moved off it ------------
REPO="$WORK/repo"
mkdir -p "$REPO/specs" "$REPO/receipts" || broken "could not create the fixture repo"
git -C "$REPO" init -q 2>/dev/null || broken "git init failed"
git -C "$REPO" config user.email t@example.invalid || broken "could not pin the fixture identity"
git -C "$REPO" config user.name tester || broken "could not pin the fixture identity"
git -C "$REPO" config commit.gpgsign false || broken "could not disable signing in the fixture repo"
git -C "$REPO" config tag.gpgsign false || broken "could not disable signing in the fixture repo"
printf 'Fixture slice. The executor is a stub; the launcher is real.\n' > "$REPO/specs/S-DEMO.md"
printf 'committed\n' > "$REPO/README.md"
git -C "$REPO" add -- specs/S-DEMO.md README.md >/dev/null 2>&1 || broken "could not stage the fixture seed"
git -C "$REPO" commit -q -m "fixture: the commit the easy implementation would name" >/dev/null 2>&1 \
  || broken "could not commit the fixture seed; there would be no HEAD to refuse"
# The tree moves off HEAD, and stays off it: nothing below commits.
printf 'uncommitted, and this is the whole point\n' >> "$REPO/README.md"

HEAD_COMMIT="$(git -C "$REPO" rev-parse HEAD)" || broken "could not read HEAD"
OBJ_FORMAT="$(git -C "$REPO" rev-parse --show-object-format 2>/dev/null || echo unknown)"

echo "== bypass_att_dirty_tree_subject: the subject is the transcript, never HEAD (ADR-019 D2) =="

( cd "$REPO" || exit 1
  PATH="$WORK/bin:$PATH" \
  TELEGRAM_BOT_TOKEN="" TELEGRAM_CHAT_ID="" \
  HARNESS_HOME="$PACK" \
  HARNESSWRIGHT_CLI="$WORK/hw.js" \
  VERITY_CLI="$WORK/verity.js" \
  HARNESS_MANIFEST="$WORK/manifest.json" \
  RECEIPTS_DIR="$REPO/receipts" \
  bash "$LAUNCHER" specs/S-DEMO.md
) > "$WORK/run.out" 2>&1
RUN_RC=$?

STATEMENT="$(find "$REPO/receipts" -maxdepth 1 -name '*.intoto.json' | head -1)"
CC="$(find "$REPO/receipts" -maxdepth 1 -name '*.cc.json' | head -1)"
[ -n "$STATEMENT" ] || broken "the run exited $RUN_RC and emitted no Statement; there is nothing to judge. Log: $(tail -3 "$WORK/run.out" | tr '\n' ' ')"
[ -n "$CC" ] || broken "the run left no transcript; the subject cannot be recomputed"

# The premise, measured in the repo the run happened in, at assertion time.
DIRTY="$(git -C "$REPO" status --porcelain | grep -c . )"
[ "$DIRTY" -gt 0 ] || broken "the tree is clean, so this run is not the case D2 is about and a green here would be a green for the wrong reason"

CC_DIGEST="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$CC")" \
  || broken "could not recompute the transcript's digest"

note "premise: git status --porcelain reports $DIRTY dirty path(s); object format is $OBJ_FORMAT, so HEAD is ${#HEAD_COMMIT} chars"
note "         and a sha256 is 64 -- which is why the controls below, and not a length comparison, carry this row"

# ---- controls 1 and 2: the easy implementation, both spellings --------------
cat > "$WORK/fabricate_head_subject.py" <<'FABRICATE'
import json, sys
st = json.load(open(sys.argv[1]))
st["subject"][0]["digest"] = {sys.argv[3]: sys.argv[4]}
json.dump(st, open(sys.argv[2], "w"), sort_keys=True, separators=(",", ":"))
FABRICATE

C_FAIL=0
for alg in sha256 gitCommit; do
  python3 "$WORK/fabricate_head_subject.py" "$STATEMENT" "$WORK/easy-$alg.json" "$alg" "$HEAD_COMMIT" \
    || broken "could not fabricate the easy implementation's Statement for $alg"
  OUT="$(python3 "$WORK/subject_is_transcript.py" "$WORK/easy-$alg.json" "$CC_DIGEST" "$HEAD_COMMIT")"
  RC=$?
  if [ "$RC" -ne 1 ]; then
    C_FAIL=1
    note "control: the easy implementation under '$alg' was NOT refused (rc=$RC): $OUT"
  else
    note "control [$alg]: ${OUT}"
  fi
done
[ "$C_FAIL" -eq 0 ] || broken "the predicate accepted a Statement whose subject is HEAD; it cannot fail on the easy implementation, which is the whole value ADR-019 assigns this row"

# ---- control 3: the predicate is not wired to refuse everything -------------
C3_OUT="$(python3 "$WORK/subject_is_transcript.py" "$STATEMENT" "$CC_DIGEST" "$HEAD_COMMIT")"
C3_RC=$?

# ---- the row ----------------------------------------------------------------
# One more direction, cheap and worth having: HEAD must not appear ANYWHERE in the
# artifact's bytes, not merely outside the digest slot.
HEAD_IN_BYTES=0
if grep -qF "$HEAD_COMMIT" "$STATEMENT"; then HEAD_IN_BYTES=1; fi

if [ "$C3_RC" -eq 0 ] && [ "$HEAD_IN_BYTES" -eq 0 ]; then
  echo "GREEN [bypass_att_dirty_tree_subject] on a dirty tree the subject is the transcript, and HEAD is nowhere in the artifact"
  note "row: ${C3_OUT}"
  note "HEAD $HEAD_COMMIT appears 0 times in the emitted bytes"
  note "the Statement is TRUE on a dirty tree, which is the only state any run has been measured in;"
  note "that is the whole of D2's value, bought by declining the more impressive-looking subject"
  echo "att_dirty_tree_subject BYPASS FIXTURE: GREEN"
  exit 0
fi

echo "RED [bypass_att_dirty_tree_subject] the Statement names something other than the transcript on a dirty tree"
note "row: ${C3_OUT} (rc=$C3_RC)"
if [ "$HEAD_IN_BYTES" -ne 0 ]; then
  note "HEAD $HEAD_COMMIT appears in the emitted bytes; D2 permits HEAD only as an annotation that"
  note "declares itself to be one, and this artifact carries no such annotation slot"
fi
note "a Statement that names a commit while the gate measured a tree is a false assertion a consumer"
note "has no way to detect from the artifact -- the failure mode an attestation is least able to survive"
echo "att_dirty_tree_subject BYPASS FIXTURE: RED"
exit 1
