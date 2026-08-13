#!/usr/bin/env bash
# bypass_att_subject_missing -- the falsifier ADR-019 D1 names.
#
# THE ASSERTION (ADR-019 Verification, verbatim): "A Statement whose
# `subject[0].digest` is absent or empty must be **rejected**."
#
# THE RED THIS ROW HOLDS WAS ALREADY MEASURED, and is cited rather than
# predicted. `GAP.md` projected the existing receipt into three candidate
# attestation shapes and measured the same failure in all three --
# `subject[0].digest` ASSENTE at `GAP.md:42`, `:62`, `:112` and `:161`, with the
# summary table at `:207` reading
#
#     subject[0].digest set | FAIL | FAIL | FAIL
#
# against the rule in-toto Statement v1 states at `statement.md:37`, verbatim:
# "Each element MUST have `digest` set." That measurement lives in a document
# nothing executes. This file is that RED made executable, and ADR-019 says so
# in as many words: "The fixture's job is to hold that RED in the suite rather
# than in a measurement document."
#
# The two documents are the ones ADR-019's Basis pins by digest --
# `GAP.md` 0dc4c148cfd35e6a83757d1b5fff0ca63c2ec2d6bd311d4d2664c5d52ccd090f and
# `spec/statement.md` cbe684a18b812b8b613d9202eb43b2ea24477f91a2ad6ca5be935185a455ebea.
# Their bytes are held in the operator's private governance vault and their
# manifest is tracked at .verity/evidence/2026-08-13-attestation-s1/README.md.
# This fixture re-derives nothing from them; it carries the RULE they establish.
#
# DECLARED GREEN, and this header is where the register reads that (ADR-017 D6).
# The row is green because scripts/write_statement.py now exists and emits a
# subject carrying a DigestSet. It goes RED the moment an emitter writes a
# Statement without one -- which is the state all three S1 projections were in
# and the state this repository was in until this commit.
#
# WHY THIS IS NOT A GREP FOR THE WORD "digest". The row is about ACCEPTANCE, so
# the fixture carries an acceptance predicate and shows it discriminates:
#
#   control 1  the three shapes GAP.md measured -- subject absent, subject[0]
#              without `digest`, subject[0] with an empty `digest` -- must all be
#              REJECTED. A predicate that accepts any of them is measuring
#              nothing and the green below would be worth nothing.
#   control 2  a hand-written, well-formed Statement must be ACCEPTED. Without
#              this, a predicate wired to reject everything would look identical.
#   the row    the Statement the EMITTER produces, on a receipt this fixture
#              constructs and feeds to scripts/write_receipt.py, must be
#              ACCEPTED -- and its digest must be the sha256 of the transcript's
#              bytes rather than any 64 characters that happen to be present.
#
# The emitter is RUN, never read: a fixture that greps a writer asserts the
# writer's source, and what ADR-019 D1 decides is a property of the artifact.
#
# Nothing outside $WORK is written. No repository file is created, moved or
# edited by this fixture.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
RECEIPT_WRITER="$PACK/scripts/write_receipt.py"
STATEMENT_WRITER="$PACK/scripts/write_statement.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-att-subject.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$RECEIPT_WRITER" ] || broken "scripts/write_receipt.py is not where this fixture expects it"
[ -f "$STATEMENT_WRITER" ] || broken "scripts/write_statement.py is not where this fixture expects it"

# The acceptance predicate: in-toto Statement v1's subject rule and nothing more.
# statement.md:37 is the whole of it -- "Each element MUST have `digest` set" --
# read together with the Schema block at :9-21, where `digest` is a DigestSet,
# an object mapping algorithm name to hex. Prints ACCEPT / REJECT <reason> and
# exits 0 / 1.
cat > "$WORK/accept_subject.py" <<'PREDICATE'
import json, sys

def reject(reason):
    print("REJECT " + reason)
    sys.exit(1)

try:
    st = json.load(open(sys.argv[1]))
except Exception as e:
    reject("the artifact is not readable JSON: %s" % e)
if not isinstance(st, dict):
    reject("the artifact is not a JSON object")
subject = st.get("subject")
if not isinstance(subject, list) or not subject:
    reject("subject is absent or empty; statement.md:9-21 requires an array of ResourceDescriptors")
for i, element in enumerate(subject):
    if not isinstance(element, dict):
        reject("subject[%d] is not an object" % i)
    digest = element.get("digest")
    # statement.md:37, verbatim: "Each element MUST have `digest` set."
    if digest is None:
        reject("subject[%d].digest is ABSENT; statement.md:37 -- 'Each element MUST have digest set.'" % i)
    if not isinstance(digest, dict) or not digest:
        reject("subject[%d].digest is EMPTY (%r); an empty DigestSet sets nothing" % (i, digest))
    for alg, value in digest.items():
        if not isinstance(alg, str) or not alg:
            reject("subject[%d].digest carries an unnamed algorithm" % i)
        if not isinstance(value, str) or not value:
            reject("subject[%d].digest[%r] is empty" % (i, alg))
print("ACCEPT subject[0].digest=%r" % (subject[0]["digest"],))
sys.exit(0)
PREDICATE

accepts() { python3 "$WORK/accept_subject.py" "$1"; }

echo "== bypass_att_subject_missing: a Statement with no subject digest is rejected (ADR-019 D1) =="

# ---- control 1: the three shapes GAP.md measured ----------------------------
# Written by hand, not produced by anything in tree. Each is one of the three
# ways a subject can fail the rule, and the summary row GAP.md:207 reports is
# FAIL on all three projections.
printf '%s' '{"_type":"https://in-toto.io/Statement/v1","predicateType":"https://in-toto.io/attestation/svr/v0.2","predicate":{}}' > "$WORK/no-subject.json"
printf '%s' '{"_type":"https://in-toto.io/Statement/v1","subject":[{"name":"run.cc.json"}],"predicateType":"https://in-toto.io/attestation/svr/v0.2","predicate":{}}' > "$WORK/no-digest.json"
printf '%s' '{"_type":"https://in-toto.io/Statement/v1","subject":[{"name":"run.cc.json","digest":{}}],"predicateType":"https://in-toto.io/attestation/svr/v0.2","predicate":{}}' > "$WORK/empty-digest.json"

C1_FAIL=0
for shape in no-subject no-digest empty-digest; do
  OUT="$(accepts "$WORK/$shape.json")"
  RC=$?
  if [ "$RC" -ne 1 ]; then
    C1_FAIL=1
    note "control 1: '$shape' was not rejected (rc=$RC): $OUT"
  else
    note "control 1: '$shape' -> ${OUT}"
  fi
done
[ "$C1_FAIL" -eq 0 ] || broken "control 1: the predicate accepted a subject GAP.md:207 measures as FAIL; it cannot tell the defect from a conforming artifact"

# ---- control 2: the predicate is not wired to reject everything -------------
printf '%s' '{"_type":"https://in-toto.io/Statement/v1","subject":[{"name":"run.cc.json","digest":{"sha256":"0000000000000000000000000000000000000000000000000000000000000000"}}],"predicateType":"https://in-toto.io/attestation/svr/v0.2","predicate":{}}' > "$WORK/well-formed.json"
C2_OUT="$(accepts "$WORK/well-formed.json")"
C2_RC=$?
[ "$C2_RC" -eq 0 ] || broken "control 2: a hand-written well-formed Statement was rejected ($C2_OUT); a predicate that refuses everything discriminates nothing"
note "control 2: a hand-written well-formed Statement -> ${C2_OUT}"

# ---- the measurement: what the emitter actually writes -----------------------
# The transcript is a real file with real bytes, and the receipt is composed by
# scripts/write_receipt.py rather than typed here, so the pair the emitter is fed
# is the pair the launcher would hand it. That is ADR-010's extraction being used
# for what it was extracted for.
CC="$WORK/run-fixture-subject.cc.json"
printf '%s' '{"subtype":"success","num_turns":3,"total_cost_usd":0.01,"duration_ms":1200,"session_id":"fixture-session","permission_denials":[]}' > "$CC"
printf '%s' '{"manifest_version":1,"verifier_id":"https://verifier.example.invalid/harness-pack/v1"}' > "$WORK/manifest.json"

RECEIPT="$WORK/run-fixture-subject.receipt.json"
CC_EXIT=0 \
GATE_JSON='{"verdict":"PASS","reason":"all declared criteria PASS","verity_exit":0,"claims":[{"id":"c1","type":"command","verdict":"PASS","evidence":"exit 0"}]}' \
BASELINE_JSON='{"verdict":"FAIL","reason":"criteria failed: c1","verity_exit":1,"claims":[{"id":"c1","type":"command","verdict":"FAIL","evidence":"exit 1"}]}' \
RUN_ID="run-fixture-subject" SPEC_ID="S-FIXTURE" MODEL_STRING="worker" \
TIER_RESOLVED="T3" MODEL_USED="HAIKU_CLASS_MODEL" MANIFEST_VERSION="1" \
CONSTITUTION_HASH="00a92e1544ba9dd55591388830a7f86bf1a8d555e22f455f05b5eb267ecaf97d" \
TOOL_VERSION="0.0.0-fixture" STARTED_AT="2026-08-13T10:14:00Z" ENDED_AT="2026-08-13T10:15:00Z" \
  python3 "$RECEIPT_WRITER" "$CC" "$RECEIPT" >/dev/null \
  || broken "scripts/write_receipt.py did not compose the fixture receipt"

CC_DIGEST="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$CC")" \
  || broken "could not digest the fixture transcript"

STATEMENT="$WORK/run-fixture-subject.intoto.json"
EMIT_OUT="$(OUT_PATH="$CC" OUT_SHA256="$CC_DIGEST" HARNESS_MANIFEST="$WORK/manifest.json" \
  python3 "$STATEMENT_WRITER" "$RECEIPT" "$STATEMENT" 2>&1)"
EMIT_RC=$?
[ "$EMIT_RC" -eq 0 ] || broken "scripts/write_statement.py exited $EMIT_RC on a transcript it could read: $EMIT_OUT"
[ -f "$STATEMENT" ] || broken "the emitter reported success and wrote no Statement; there is nothing to judge"

ROW_OUT="$(accepts "$STATEMENT")"
ROW_RC=$?

# The second half, and it is not decoration. A subject carrying SOME digest
# passes statement.md:37 while still naming the wrong artifact; ADR-019 D1 fixes
# WHICH digest -- "the sha256 of its raw bytes". Recomputed here from the
# transcript on disk rather than read back out of the artifact.
EMITTED_DIGEST="$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1]))["subject"][0]["digest"] or {}).get("sha256",""))' "$STATEMENT" 2>/dev/null)"

if [ "$ROW_RC" -eq 0 ] && [ -n "$EMITTED_DIGEST" ] && [ "$EMITTED_DIGEST" = "$CC_DIGEST" ]; then
  echo "GREEN [bypass_att_subject_missing] the emitted Statement carries a subject digest, and it is the transcript's"
  note "predicate: ${ROW_OUT}"
  note "subject[0].digest.sha256 = $EMITTED_DIGEST, recomputed from the transcript's bytes and equal"
  note "GAP.md:207 measured 'subject[0].digest set | FAIL | FAIL | FAIL' on all three projections;"
  note "the rule refused them here too (control 1) and accepts what the emitter writes"
  echo "att_subject_missing BYPASS FIXTURE: GREEN"
  exit 0
fi

echo "RED [bypass_att_subject_missing] the emitted Statement does not carry the transcript's digest as its subject"
note "predicate on the emitted artifact: ${ROW_OUT} (rc=$ROW_RC)"
note "subject[0].digest.sha256 = ${EMITTED_DIGEST:-<absent>}"
note "transcript sha256          = $CC_DIGEST"
note "statement.md:37 -- 'Each element MUST have digest set.' A Statement without one is not a"
note "degraded artifact, it is a rejected one, and a Statement with the WRONG one is worse:"
note "well-formed, machine-readable and untrue (ADR-019 D2's failure mode)"
echo "att_subject_missing BYPASS FIXTURE: RED"
exit 1
