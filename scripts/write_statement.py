#!/usr/bin/env python3
"""Side-car in-toto Statement writer (ADR-019 D1/D4/D5/D6/D7).

  write_statement.py RECEIPT_JSON STATEMENT_JSON

Sibling of write_receipt.py, on the same I/O contract for the same reason: the
two paths that vary per invocation arrive as argv, everything else arrives as an
environment variable. ADR-002 D2 made that substitution for the launch gates and
ADR-010 kept it for the receipt writer, whose docstring gives the argument -- a
writer reachable only by driving the whole launcher cannot be fed a constructed
input, and the fixtures have to feed it one. This file is fed constructed inputs
by four of the six falsifiers ADR-019 names, so the property is load-bearing here
rather than inherited.

  OUT_PATH          the transcript path, $OUT in the launcher. Its BASENAME is
                    subject[0].name -- ADR-019 D1, "A path is environment, not
                    identity", on resource_descriptor.md:37-39, which asks that
                    `name` be stable "such as a filename".
  OUT_SHA256        the sha256 of $OUT's RAW BYTES, taken by the launcher after
                    the child closed the file (launch_worker.sh:371) and before
                    the receipt writer runs (:409). That one line is the whole
                    cost of D1 and was ADR-019 OR-6. EMPTY means the launcher
                    could not read $OUT: that is D7's branch, and this writer
                    then emits NOTHING.
  HARNESS_MANIFEST  the manifest the launcher resolved. The only field read from
                    it is `verifier_id`, and its absence is a fail-closed STOP on
                    the model of CONST-HASH-MISMATCH (launch_checks.py:61-64).
  CLAIMS_SHA256     the sha256 of the TARGET repository's .verity/claims.json,
                    taken by the launcher inside its gate branch. ADR-020 D4's
                    ResourceDescriptor, and the second of the two digest lines
                    the family named -- ADR-019 OR-1 and ADR-020 OR-1. EMPTY is a
                    decided state and not a failure: no gate ran, or the manifest
                    was unreadable, and `policies` is then `[]`.

WHAT THIS WRITER NEVER READS, and the rule is an allowlist rather than a denylist
(ADR-019 D6, whose rationale ADR-020 D2 carries). No field of the Statement is
ever populated by a string the child or `verity` produced: not `claims[*].evidence`,
not `contribution.baseline.claims[*].evidence`, not `gate.reason`, not
`refusals.denials`, not `subtype`, not `session_id`. The mechanism is not a filter
over those values -- it is that every string this file writes into the artifact is
either a literal spelled here, a digest, an id the launcher itself minted, or the
one URI read from the operator's manifest. A receipt field that is not named in
`_properties()` or in `main()` is not reachable from here at all.

CANONICAL FORM (ADR-018 D1): keys sorted lexicographically, compact separators,
no whitespace, UTF-8, and NO TRAILING NEWLINE -- a trailing byte is whitespace,
and the file's bytes are the artifact's content identity. That last detail is what
makes the side-car genuinely content-addressed and answers ADR-019 OR-3 yes.
ADR-018 OR-1 forbids every document in this family from calling this form by the
name of any external canonicalization standard; it is what it is described as
here, and the fixture bypass_att_canon_reorder holds it.
"""
import hashlib
import json
import os
import sys

# in-toto Statement v1. `statement.md:11` in the corpus ADR-019's Basis pins at
# sha256 cbe684a1..., and the Schema block at :9-21 fixes the four keys.
STATEMENT_TYPE = "https://in-toto.io/Statement/v1"

# Simple Verification Result. Read LITERALLY from `spec/svr.md:3` in the corpus
# ADR-019's Basis pins at sha256
# 60d47f833f7998926aa991d1aa6ab9ef9a2a916771a99232b624ea0c45c9da1a, 7540 bytes,
# and not from memory: ADR-019 D4 records the same URI serving two different
# versions on two readings, which is why the Basis pins a digest and not a link.
PREDICATE_TYPE = "https://in-toto.io/attestation/svr/v0.2"


def _stop(msg):
    """Fail-closed refusal, on launch_checks.py's shape: message on stderr, exit
    1, and NOTHING written. The launcher's call site is fail-open around this --
    a refusal here must never move the run's exit code or the gate's verdict --
    so the two postures compose rather than contradict: this writer refuses to
    emit a Statement it cannot emit correctly, and the run it is attesting to is
    unaffected either way. The run is the thing attested; the attestation is not
    the run."""
    print(msg, file=sys.stderr)
    sys.exit(1)


def _properties(receipt):
    """ADR-019 D4's controlled vocabulary, closed, six values, in the order that
    ADR's table declares them. The order is the table's and is fixed here rather
    than incidental, because the array is part of a content-addressed artifact.

    Every entry is a LITERAL spelled in this function. The receipt is read only to
    decide whether a literal is appended, never for a value to copy through, which
    is ADR-020 D2's allowlist expressed as code rather than as a rule to remember.

    `properties` lists ONLY properties verified as passing -- svr.md:105,
    "Indicates the passing properties verified for the artifact". So an ABSENT
    property means NOT VERIFIED and never FAILED. The vocabulary is closed so
    that "not in the list" has exactly one meaning, and it deliberately has no
    HARNESS_CONTRIBUTION_NOT_EVALUATED: a run that evaluated nothing emits neither
    contribution property, and absence already says it (ADR-019 D4).
    """
    props = []
    if receipt.get("mode") == "B":
        props.append("HARNESS_MODE_B")
    # The pin is enforced before the run, fail-closed, at launch_checks.py:61-64;
    # the receipt carries the digest that pin computed (write_receipt.py:135). A
    # receipt reaching this writer with a constitution_hash is a receipt whose
    # run got past CONST-HASH-MISMATCH.
    if isinstance(receipt.get("constitution_hash"), str) and receipt["constitution_hash"]:
        props.append("HARNESS_CONSTITUTION_PINNED")
    gate = receipt.get("gate") or {}
    # KEYED TO THE VERDICT, NEVER TO `verity_exit`, and the distinction is the one
    # bypass_att_result_desync measures. `gate.verdict` is the launcher's own
    # judgement over spec.criteria (launch_worker.sh:306-312) and it is what
    # decides the run's exit at :439 -- so "the gate exited non-zero" is exactly
    # "verdict is not PASS". `verity_exit` is repo-wide and can be non-zero while
    # every DECLARED criterion passes, so keying on it would refuse a Statement
    # that is true.
    if gate.get("verdict") == "PASS":
        props.append("HARNESS_GATE_PASS")
    contribution = receipt.get("contribution") or {}
    if contribution.get("verdict") == "CONTRIBUTED":
        props.append("HARNESS_CONTRIBUTION_CONTRIBUTED")
    if contribution.get("verdict") == "NO_OP":
        props.append("HARNESS_CONTRIBUTION_NO_OP")
    # ADR-010 D1 makes the object ALWAYS present, count 0 on a clean run. The
    # property therefore says that refusals were RECORDED, not that any occurred,
    # and its own count is not carried: a count is a number about the child's
    # behaviour and D4's vocabulary is a set of passing properties.
    if isinstance(receipt.get("refusals"), dict):
        props.append("HARNESS_REFUSALS_RECORDED")
    return props


def _policies(claims_sha256):
    """ADR-020 D4, and the field ADR-019 OR-1 left written as `[]` with a reason.

    D4 decides what this carries: "the `ResourceDescriptor` of the **claims
    manifest of the target repository** -- `.verity/claims.json`, the path
    `verity` `src/verify.ts:9` fixes as `DEFAULT_MANIFEST_PATH`. Its `digest` is
    the sha256 of that file's bytes, computed **at the moment of the gate**".
    The launcher takes that digest inside its gate branch and passes it here;
    this function decides only how to spell it.

    DIGEST ALONE, NO PATH. `resource_descriptor.md:26-27` is satisfied by
    `digest` on its own -- "a ResourceDescriptor MUST specify one of `uri`,
    `digest` or `content` at a minimum" -- and ADR-020 D2's allowlist is why the
    minimum is what gets written: a `uri` here would be an absolute path in a
    publishable artifact, which is the whole thing D3's boundary refuses.

    THE CONSTITUTION NEVER APPEARS HERE. D4: "`CONSTITUTION.md` governs the
    CHILD -- the subject being judged -- not the judge." The receipt carries
    `constitution_hash` and this function does not read it. That is asserted by
    tests/bypass_att_policies_constitution_fixture.sh rather than left to this
    comment.

    `[]` IS THE HONEST BRANCH, NOT A DEGRADED ONE. An empty CLAIMS_SHA256 means
    the gate did not run, or the manifest was not readable when it did. D4:
    "nothing is invented. The fact is recorded and `verifier.policies` is left
    `[]`", which `svr.md:74-76` makes the minimal CONFORMANT value.
    """
    value = (claims_sha256 or "").strip()
    if not value:
        return []
    # A digest that is present but malformed is not a weaker descriptor, it is a
    # false one, and it is refused on exactly the ground D7 refuses an empty
    # subject: a fabricated descriptor costs a consumer the ability to trust any
    # descriptor, including every true one.
    if len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
        _stop("STOP: POLICY-DIGEST-MALFORMED CLAIMS_SHA256 is not 64 lowercase hex characters; no Statement written")
    return [{"digest": {"sha256": value}}]


def compose(receipt, subject_name, subject_sha256, verifier_id, claims_sha256=""):
    """The Statement. Four keys, statement.md:9-21; `predicate` is optional there
    (`:62`) and is present because SVR v0.2 requires three fields inside it."""
    return {
        "_type": STATEMENT_TYPE,
        "subject": [
            {
                # ADR-018 D2: the algorithm is data, never a field name. This is
                # an in-toto DigestSet, `{"<algorithm-name>": "<hex>"}`, which is
                # also the shape statement.md:15 uses for subject[*].digest.
                # `sha256` is correct here because the value is a digest over raw
                # bytes (digest_set.md:32) -- a git object id would be `gitBlob`
                # or `gitCommit` (:103) and is not what D1 chose.
                "digest": {"sha256": subject_sha256},
                "name": subject_name,
            }
        ],
        "predicateType": PREDICATE_TYPE,
        "predicate": {
            "verifier": {
                "id": verifier_id,
                # ADR-020 D4, ratified 2026-08-13. This field carried `[]` with a
                # written reason while ADR-020 was Proposed and ADR-006:56 forbade
                # implementing it; the reason is now in _policies() above, and
                # ADR-019 OR-1 closes with this line. `[]` remains the value on
                # the branch D4 declares for it -- no gate, or no readable
                # manifest -- and it is still the minimal conformant form there.
                "policies": _policies(claims_sha256),
            },
            "timeCreated": receipt["ended_at"],
            "properties": _properties(receipt),
        },
    }


def main(argv):
    if len(argv) != 3:
        print("usage: write_statement.py RECEIPT_JSON STATEMENT_JSON", file=sys.stderr)
        return 2
    receipt_path, statement_path = argv[1], argv[2]

    # ---- D7: no transcript, no Statement ------------------------------------
    # "If $OUT is absent or unreadable at the moment the digest is taken ... the
    # launcher emits no Statement at all. The absence of the side-car file is
    # itself the signal." No file, no empty subject, no substitute subject. The
    # receipt is written by write_receipt.py exactly as always -- this branch
    # changes nothing about it, which is D7's third refusal.
    #
    # Statement v1 does not admit the alternative: statement.md:37, "Each element
    # MUST have `digest` set." So the only way to emit here would be to fabricate
    # a subject, which is the trade D2 already refused for HEAD. A missing
    # side-car costs a consumer one lookup; a fabricated one costs them the
    # ability to trust any side-car, including every true one.
    out_sha256 = (os.environ.get("OUT_SHA256") or "").strip()
    if not out_sha256:
        print("statement: none (no transcript digest; ADR-019 D7 -- the absence is the signal)")
        return 0

    # A digest that is present but not a sha256 is not a weaker subject, it is a
    # false one, and it is refused on the same ground D7 refuses an empty subject.
    if len(out_sha256) != 64 or any(c not in "0123456789abcdef" for c in out_sha256):
        _stop("STOP: SUBJECT-DIGEST-MALFORMED OUT_SHA256 is not 64 lowercase hex characters; no Statement written")

    out_path = os.environ.get("OUT_PATH") or ""
    if not out_path:
        _stop("STOP: SUBJECT-NAME-ABSENT OUT_PATH is empty, so subject[0].name cannot be the basename ADR-019 D1 requires; no Statement written")
    subject_name = os.path.basename(out_path)

    # ---- verifier.id, fail-closed -------------------------------------------
    # ADR-019 D4 requires a URI under a domain the operator controls; WHICH domain
    # was left open as that ADR's OR-2 and is an operator decision, so it is read
    # from the manifest and never defaulted, on the model launch_checks.py:61-64
    # uses for the constitution pin. templates/manifest.example.json carries a
    # PLACEHOLDER in the *_CLASS_MODEL convention, never a real domain: ADR-004
    # keeps operator literals out of tracked files, and the placeholder is what
    # the operator replaces in their own copy.
    #
    # The URI's SHAPE is not validated here. ADR-019 decides that the value comes
    # from the manifest and decides nothing about its form, and inventing a
    # conformance check would be this file legislating where the ADR did not.
    manifest_path = os.environ.get("HARNESS_MANIFEST") or ""
    if not manifest_path:
        _stop("STOP: VERIFIER-ID-ABSENT HARNESS_MANIFEST is unset, so verifier_id cannot be read; no Statement written")
    try:
        manifest = json.load(open(manifest_path))
    except Exception as e:
        _stop("STOP: VERIFIER-ID-ABSENT manifest %s is not readable JSON (%s); no Statement written" % (manifest_path, e))
    verifier_id = manifest.get("verifier_id")
    if not isinstance(verifier_id, str) or not verifier_id:
        _stop("STOP: VERIFIER-ID-ABSENT manifest %s declares no verifier_id; ADR-019 D4 requires one and this writer will not default it; no Statement written" % manifest_path)

    try:
        receipt = json.load(open(receipt_path))
    except Exception as e:
        _stop("STOP: RECEIPT-UNREADABLE %s (%s); the predicate is composed from the receipt and there is nothing to compose from; no Statement written" % (receipt_path, e))
    if not isinstance(receipt.get("ended_at"), str) or not receipt["ended_at"]:
        _stop("STOP: TIME-CREATED-ABSENT receipt %s carries no ended_at; svr.md:99 requires timeCreated; no Statement written" % receipt_path)

    # ADR-020 D4's descriptor. Read from the environment for the same reason
    # OUT_SHA256 is: the launcher computes it at the moment of the gate, which is
    # a moment this writer is not present for.
    statement = compose(receipt, subject_name, out_sha256, verifier_id,
                        os.environ.get("CLAIMS_SHA256") or "")

    # ADR-018 D1's form, and the bytes on disk ARE the serialization: no trailing
    # newline, so sha256(file) equals sha256(the canonical string) and the
    # artifact is content-addressed without a second convention about framing.
    data = json.dumps(statement, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    with open(statement_path, "w", encoding="utf-8") as f:
        f.write(data)
    print("statement:", statement_path, hashlib.sha256(data.encode("utf-8")).hexdigest())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
