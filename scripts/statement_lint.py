#!/usr/bin/env python3
"""The publication boundary: ADR-020 D3, over the EMITTED artifact.

WHAT THIS IS FOR, AND WHY IT IS NOT A GREP. ADR-020 D1 measured the defect this
file answers: `privacy-lint-user-paths` in .verity/claims.json is a `git grep`,
and `git grep` sees TRACKED FILES ONLY. Receipts are gitignored here
(.gitignore:1 and :7) and untracked in every other repository of the family, so
that claim is green because five hand-authored fixtures are clean and not
because any mechanism refuses a leaking artifact. ADR-020 D3, verbatim: "The new
claim must therefore preside over **the emitted artifact**, not over the tree."

A side-car Statement is untracked by construction -- it is written beside the
receipt under $RECEIPTS_DIR. This linter reaches it by walking the filesystem,
which is the one capability the existing lint structurally lacks. The difference
is not a tuning choice; it is what the claim is for.

AN ALLOWLIST, NEVER A DENYLIST (ADR-020 D2). The primary pass below is
STRUCTURAL: every string in the document must occupy a slot this file names, and
must satisfy that slot's rule. An unknown key is a rejection, not a warning. A
denylist over arbitrary input is a war that cannot be won -- ADR-020 D2 argues it
at length and the argument is adopted here rather than restated -- and its
failure mode is a Statement that CARRIES something, invisible and permanent once
published. An allowlist's failure mode is a Statement that is MISSING something,
visible and inert.

The two blunt checks ADR-020 D3 names by hand -- the literal home-directory
prefix this platform uses, and an absolute path by shape -- run as a SECOND pass
over every string at every depth. Under the structural pass they are redundant:
no conforming slot can hold either. They run anyway because D3 names them,
because redundancy at a boundary costs one traversal, and because they are the
arm that catches a URI slot carrying that prefix inside a `file:` URI -- the one
residual ADR-020's Assumption ledger row A3 records as unmeasured.

D2's allowlist, slot by slot, is `check_structure` below. Its vocabulary of
properties is the closed six-value enum ADR-019 D4 coined; `_properties` in
scripts/write_statement.py is the producer of the same six and this file is the
reader. They are deliberately two lists in two files: a reader that imported the
writer's list would agree with the writer by construction and would measure
nothing.

USAGE

    statement_lint.py --selftest              discriminate on built-in specimens
    statement_lint.py --sweep [ROOT ...]      lint every *.intoto.json found
    statement_lint.py FILE [FILE ...]         lint the named artifacts

Exit 0 when every artifact examined conforms, 1 when any is refused, 2 when the
linter could not run at all. `--sweep` over zero artifacts is exit 0 and says so
on stdout: the vacuity is reported, never disguised as a measurement.
"""
import json
import os
import re
import sys

# ADR-019 D4's controlled vocabulary, closed, six values. Spelled here as
# literals rather than imported from scripts/write_statement.py: a boundary that
# reads the producer's own list cannot refuse a value the producer invents.
HARNESS_PROPERTIES = frozenset(
    (
        "HARNESS_MODE_B",
        "HARNESS_CONSTITUTION_PINNED",
        "HARNESS_GATE_PASS",
        "HARNESS_CONTRIBUTION_CONTRIBUTED",
        "HARNESS_CONTRIBUTION_NO_OP",
        "HARNESS_REFUSALS_RECORDED",
    )
)

STATEMENT_TYPE = "https://in-toto.io/Statement/v1"
PREDICATE_TYPE = "https://in-toto.io/attestation/svr/v0.2"

# A DigestSet key is an algorithm NAME (digest_set.md); the value is lowercase
# hex. ADR-018 D2 is the rule that the algorithm is data and never a field name,
# and this pair of patterns is that rule read as an acceptance test.
RE_ALG = re.compile(r"\A[A-Za-z0-9_-]{1,32}\Z")
RE_HEX = re.compile(r"\A[0-9a-f]{8,128}\Z")

# An id, in D2's sense: a bare token. ADR-019 D1 fixes subject[*].name as the
# transcript's BASENAME, so a separator in it is already a violation of that
# decision before it is a privacy question.
RE_ID = re.compile(r"\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\Z")

# RFC 3339, the profile svr.md:99 requires for timeCreated.
RE_RFC3339 = re.compile(
    r"\A\d{4}-\d{2}-\d{2}[Tt]\d{2}:\d{2}:\d{2}(\.\d+)?([Zz]|[+-]\d{2}:\d{2})\Z"
)

# A URI with an explicit scheme. Deliberately narrow: the operator's verifier.id
# is a URI they choose, and a value with no scheme is not one.
RE_URI = re.compile(r"\A[a-z][a-z0-9+.-]*:[^\s]+\Z")

# The two blunt checks D3 names.
#
# LITERAL_USERS is ASSEMBLED, NOT SPELLED, and the reason is the same one
# tests/bypass_receipt_host_path_published_fixture.sh gives. A tracked file
# carrying this token literally is exactly what `privacy-lint-user-paths`
# refuses, and the detector written to answer ADR-020 D3 asking to be added to
# that claim's exclusion list would be reproducing, inside itself, the defect D3
# criticises. Two concatenations, and both claims stay honest.
LITERAL_USERS = "/" + "Users" + "/"

# RE_ABSPATH is SHAPE, not prefix: two or more separator-led segments in a row.
# ADR-020's ledger row A3 carries the false-positive risk as [assumed] and names
# the one slot that could collide -- a URI. That collision is resolved by scheme
# rather than by tuning the pattern: see _path_body below, which exempts a
# scheme-bearing URI from the SHAPE check and exempts nothing from the LITERAL
# check. `file:` is deliberately not exempt.
RE_ABSPATH = re.compile(r"/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)+")
RE_SCHEME = re.compile(r"\A([a-z][a-z0-9+.-]*):(.*)\Z", re.S)


def _path_body(text):
    """The part of a string the absolute-path SHAPE check applies to, or None
    when the string is exempt.

    A URI with a non-`file` scheme is exempt: `https://host/a/b` has an authority
    and a path that are the URI's own syntax and not a filesystem location, and
    `predicate.verifier.id` is required to be exactly such a URI. `file:` is NOT
    exempt -- a file URI IS an absolute path with a scheme in front of it, and an
    exemption that covered it would be the exemption that swallows the check.
    This is the resolution of ADR-020's A3, taken by scheme rather than by
    loosening the pattern until the false positives stop."""
    m = RE_SCHEME.match(text)
    if m is None:
        return text
    if m.group(1) == "file":
        return m.group(2)
    return None


class Refusal(Exception):
    """One rejection, carrying the JSON path that produced it."""


def _refuse(where, why):
    raise Refusal("%s: %s" % (where, why))


def _digest_set(node, where):
    """ADR-018 D2's spelling, and nothing else."""
    if not isinstance(node, dict) or not node:
        _refuse(where, "not a non-empty DigestSet object (ADR-018 D2)")
    for alg, value in node.items():
        if not RE_ALG.match(alg or ""):
            _refuse("%s[%r]" % (where, alg), "algorithm name outside the allowlist")
        if not isinstance(value, str) or not RE_HEX.match(value):
            _refuse(
                "%s[%s]" % (where, alg),
                "value is not lowercase hex; a DigestSet value is a digest and never prose",
            )


def _exact_keys(node, allowed, required, where):
    if not isinstance(node, dict):
        _refuse(where, "not a JSON object")
    extra = sorted(set(node) - set(allowed))
    if extra:
        # THE ALLOWLIST'S WHOLE POINT. An unrecognised key is refused without
        # inspecting its value: this is what makes an `evidence`, a `reason`, a
        # `subtype`, a `session_id` or a `denials` member impossible to smuggle
        # in, whatever it happens to contain (ADR-020 D2).
        _refuse(where, "carries key(s) outside D2's allowlist: %s" % ", ".join(extra))
    missing = sorted(set(required) - set(node))
    if missing:
        _refuse(where, "is missing required key(s): %s" % ", ".join(missing))


def check_structure(st):
    _exact_keys(st, ("_type", "subject", "predicateType", "predicate"),
                ("_type", "subject", "predicateType", "predicate"), "$")

    if st["_type"] != STATEMENT_TYPE:
        _refuse("$._type", "is not the pinned Statement v1 type URI")
    if st["predicateType"] != PREDICATE_TYPE:
        _refuse("$.predicateType", "is not the pinned SVR v0.2 predicate type URI")

    subject = st["subject"]
    if not isinstance(subject, list) or not subject:
        _refuse("$.subject", "is absent or empty")
    for i, element in enumerate(subject):
        at = "$.subject[%d]" % i
        _exact_keys(element, ("digest", "name"), ("digest",), at)
        _digest_set(element["digest"], at + ".digest")
        if "name" in element:
            if not isinstance(element["name"], str) or not RE_ID.match(element["name"]):
                _refuse(at + ".name", "is not a bare id; ADR-019 D1 fixes it as a basename")

    pred = st["predicate"]
    _exact_keys(pred, ("verifier", "timeCreated", "properties"),
                ("verifier", "timeCreated", "properties"), "$.predicate")

    ver = pred["verifier"]
    _exact_keys(ver, ("id", "policies"), ("id", "policies"), "$.predicate.verifier")
    if not isinstance(ver["id"], str) or not RE_URI.match(ver["id"]):
        _refuse("$.predicate.verifier.id", "is not a URI with an explicit scheme")

    policies = ver["policies"]
    if not isinstance(policies, list):
        _refuse("$.predicate.verifier.policies", "is not an array; svr.md:74-76 requires one, empty if none")
    for i, p in enumerate(policies):
        at = "$.predicate.verifier.policies[%d]" % i
        # ADR-020 D4: the descriptor carries a digest and nothing else.
        # resource_descriptor.md:26-27 is satisfied by `digest` alone, "so no
        # path need appear, which is also what D2 requires".
        _exact_keys(p, ("digest",), ("digest",), at)
        _digest_set(p["digest"], at + ".digest")

    if not isinstance(pred["timeCreated"], str) or not RE_RFC3339.match(pred["timeCreated"]):
        _refuse("$.predicate.timeCreated", "is not an RFC 3339 timestamp (svr.md:99)")

    props = pred["properties"]
    if not isinstance(props, list):
        _refuse("$.predicate.properties", "is not an array")
    for i, p in enumerate(props):
        if not isinstance(p, str) or p not in HARNESS_PROPERTIES:
            _refuse(
                "$.predicate.properties[%d]" % i,
                "value %r is outside the closed HARNESS_ vocabulary ADR-019 D4 coined" % (p,),
            )


def _walk_strings(node, where="$"):
    if isinstance(node, dict):
        for k, v in node.items():
            yield where + "." + str(k), str(k)
            for item in _walk_strings(v, where + "." + str(k)):
                yield item
    elif isinstance(node, list):
        for i, v in enumerate(node):
            for item in _walk_strings(v, "%s[%d]" % (where, i)):
                yield item
    elif isinstance(node, str):
        yield where, node


def check_literals(st):
    """The two blunt checks D3 names, over every string at every depth.

    Redundant under check_structure for every slot except the URI one, and run
    anyway: the URI slot is the residual, and one extra traversal is the whole
    cost."""
    for where, text in _walk_strings(st):
        if LITERAL_USERS in text:
            _refuse(where, "carries the literal token %r" % LITERAL_USERS)
        body = _path_body(text)
        if body is None:
            continue
        m = RE_ABSPATH.search(body)
        if m:
            _refuse(where, "carries an absolute path by shape: %r" % m.group(0))


def lint_object(st):
    """Both passes. Structural first: it is the decision, and the literal pass is
    the belt beside it."""
    if not isinstance(st, dict):
        _refuse("$", "the artifact is not a JSON object")
    check_structure(st)
    check_literals(st)


def lint_file(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            st = json.load(f)
    except Exception as e:
        return "REFUSED %s -- unreadable as JSON: %s" % (path, e), 1
    try:
        lint_object(st)
    except Refusal as r:
        return "REFUSED %s -- %s" % (path, r), 1
    return "ACCEPTED %s" % path, 0


# ---------------------------------------------------------------------------
# The self-test, and why the claim runs it.
#
# A sweep over zero emitted artifacts is green by vacuity. That vacuity is
# TEMPORAL -- it ends the first time any run emits a side-car -- and it is not
# the structural blindness ADR-020 D1 measured in privacy-lint-user-paths, which
# no number of runs can end. The distinction is worth having and it is still not
# a measurement, so the claim carries a control: two specimens constructed here,
# one conforming and one not, with the boundary required to tell them apart on
# every gate run. tests/bypass_att_prose_leak_fixture.sh drives the same
# boundary independently and with more arms; this is the cheap half, wired where
# the claim can reach it.
# ---------------------------------------------------------------------------
CONFORMING_SPECIMEN = {
    "_type": STATEMENT_TYPE,
    "subject": [
        {
            "digest": {"sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
            "name": "run-selftest.cc.json",
        }
    ],
    "predicateType": PREDICATE_TYPE,
    "predicate": {
        "verifier": {
            "id": "https://verifier.example.invalid/harness-pack/v1",
            "policies": [
                {"digest": {"sha256": "0000000000000000000000000000000000000000000000000000000000000000"}}
            ],
        },
        "timeCreated": "2026-08-13T10:15:00Z",
        "properties": ["HARNESS_GATE_PASS"],
    },
}


def _leaking_specimens():
    """One specimen per arm D3 names, each a minimal mutation of the conforming
    one so that what moved is exactly the thing under test.

    Two of the five are aimed at the STRUCTURAL pass and two at the LITERAL pass.
    The literal-pass pair is placed in `verifier.id` deliberately: that is the
    one slot the structural pass admits a separator into, so a specimen that put
    the path anywhere else would be caught by the structural rule and would
    leave the literal pass unexercised -- green, and measuring nothing."""
    out = []

    # (a) STRUCTURAL -- a field outside D2's allowlist. The lenient
    # implementation's mistake: a verity `evidence` string copied through
    # because it happened to be in hand.
    a = json.loads(json.dumps(CONFORMING_SPECIMEN))
    a["predicate"]["evidence"] = "exists, 412 bytes"
    out.append(("out-of-allowlist key", a))

    # (b) STRUCTURAL -- free text where the closed vocabulary belongs. This is
    # a real `gate.reason` string, assembled at launch_worker.sh:307-312.
    b = json.loads(json.dumps(CONFORMING_SPECIMEN))
    b["predicate"]["properties"] = ["gate-fail: criteria failed: C-1"]
    out.append(("prose in the closed enum", b))

    # (c) STRUCTURAL -- a subject name that is a path rather than the basename
    # ADR-019 D1 fixes.
    c = json.loads(json.dumps(CONFORMING_SPECIMEN))
    c["subject"][0]["name"] = "some/nested/run.cc.json"
    out.append(("subject name is a path", c))

    # (d) LITERAL -- the token D3 names, inside a well-formed URI. The structural
    # pass accepts this string: it has a scheme and no whitespace.
    d = json.loads(json.dumps(CONFORMING_SPECIMEN))
    d["predicate"]["verifier"]["id"] = "file://" + LITERAL_USERS + "someone/Code/repo/verifier"
    out.append(("literal home prefix in a URI", d))

    # (e) LITERAL -- an absolute path by shape under a prefix no denylist would
    # have guessed, again inside a well-formed `file:` URI.
    e = json.loads(json.dumps(CONFORMING_SPECIMEN))
    e["predicate"]["verifier"]["id"] = "file:///srv/agents/private/verifier"
    out.append(("absolute path by shape", e))

    return out


def selftest():
    failures = []
    try:
        lint_object(json.loads(json.dumps(CONFORMING_SPECIMEN)))
        print("selftest: conforming specimen ACCEPTED")
    except Refusal as r:
        failures.append("the conforming specimen was REFUSED (%s); a boundary that refuses "
                        "everything discriminates nothing" % r)
    for label, specimen in _leaking_specimens():
        try:
            lint_object(specimen)
        except Refusal as r:
            print("selftest: %-24s REFUSED -- %s" % (label, r))
        else:
            failures.append("the '%s' specimen was ACCEPTED; the boundary cannot see it" % label)
    for f in failures:
        print("selftest FAILED: " + f, file=sys.stderr)
    return 1 if failures else 0


def _sweep_roots(roots):
    found = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != ".git"]
            for name in filenames:
                if name.endswith(".intoto.json"):
                    found.append(os.path.join(dirpath, name))
    return sorted(found)


def main(argv):
    args = argv[1:]
    if not args:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("usage: statement_lint.py [--selftest|--sweep [ROOT ...]|FILE ...]", file=sys.stderr)
        return 2

    if args[0] == "--selftest":
        return selftest()

    if args[0] == "--sweep":
        roots = args[1:] or [os.environ.get("RECEIPTS_DIR") or ".harness/receipts", "receipts"]
        targets = _sweep_roots(roots)
        if not targets:
            # Reported, never disguised. A boundary with nothing to judge says so.
            print("sweep: 0 emitted Statements under %s -- nothing judged" % ", ".join(roots))
            return 0
    else:
        targets = args

    worst = 0
    for path in targets:
        line, rc = lint_file(path)
        print(line)
        worst = max(worst, rc)
    print("sweep: %d artifact(s) examined, %s" % (len(targets), "all conform" if worst == 0 else "REFUSALS above"))
    return worst


if __name__ == "__main__":
    sys.exit(main(sys.argv))
