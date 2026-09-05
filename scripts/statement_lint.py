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

    statement_lint.py --surface --selftest    discriminate on built-in repositories
    statement_lint.py --surface [--repo DIR] [--baseline REV] [--now REV]
                                [--class NAME=FLAGS:LITERAL ...] [--declaration PATH]
                                [--declare NAME=FILES:OCCURRENCES ...]

Exit 0 when every artifact examined conforms, 1 when any is refused, 2 when the
linter could not run at all. `--sweep` over zero artifacts is exit 0 and says so
on stdout: the vacuity is reported, never disguised as a measurement.

`--surface` is the same boundary asked at the other place material leaves the
machine -- the tracked tree, which is exactly what a push carries. What it
measures is a COMMIT: `--now` defaults to `HEAD`, so the verdict is a function
of the revision a receipt pins and of nothing on disk. Its rule and the defect
it replaces are documented at the section marked THE SECOND BOUNDARY below.
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


# ---------------------------------------------------------------------------
# THE SECOND BOUNDARY: --surface, over the TRACKED TREE.
#
# WHY A SECOND MODE AND NOT A SECOND FILE. The mode above presides over what a
# run EMITS. This one presides over what a push CARRIES. They are the same
# question -- may this leave the machine? -- asked at the two places material
# leaves it, and they share the vocabulary below: the same literal detector,
# the same specimen discipline, the same rule that a measurement which could
# not have failed is reported as vacuous rather than as green.
#
# WHAT WAS WRONG WITH THE CLAIM THIS REPLACES. `privacy-lint-*` in
# .verity/claims.json demands zero occurrences over the whole tracked tree,
# minus four hand-written pathspec exclusions. That claim is unsatisfiable
# twice over and unverified once:
#
#   - The rule that removes a string must state the string.
#     scripts/path_transform_rule_v1.json cannot exist without carrying the
#     path it replaces, so any landing that tracks it turns the claim red.
#   - Evidence is fixed by a digest. A machine fact inside a stream cannot be
#     edited away without breaking the digest that fixes it, which is the
#     whole point of fixing it.
#   - Nothing checks that an exclusion is ENTITLED to be one. `docs/adrs/` is
#     excluded wholesale, and it is where nearly the entire real exposure
#     lives. An exclusion nobody verifies is not a boundary; it is a habit.
#
# THE REFORMULATION. Zero on the surface a change ADDS; exactly the declared
# count on the surface that already EXISTS; two machine-checkable exemption
# reasons and no third; and every count carrying its own non-vacuity guard.
#
#   DECLARES  the file is a rule that names what it replaces -- it parses as
#             JSON, carries `pattern` and `replacement`, and every hit inside
#             it falls inside one of those two values. Reason 1.
#   PINNED    the file is evidence fixed by a digest -- its sha256 appears
#             verbatim in another tracked file, so rewriting it breaks the pin.
#             Reason 2.
#
# A file in neither is not an exemption.
#
# DECLARED VERSUS COMPUTED CLASSES, and why the asymmetry is the point. The
# quotable classes -- the home-path token, the vault name, a model-id prefix,
# the private repo names -- are passed in by the caller, so this file -- itself on the public
# surface -- never becomes an instance of what it detects. The classes that
# identify THIS machine are never passed in and never written down: they are
# computed from the running process (`homepath`, `hostname`). A computed class
# therefore cannot be laundered by quoting it in a declaration, because no
# declaration can name it. It remains exemptible under DECLARES only through
# the rule shape, which is exactly the file that has to state it.
# ---------------------------------------------------------------------------
RE_SHA256_TOKEN = re.compile(r"\b[0-9a-f]{64}\b")

# A class is a LITERAL, never a regex, and the reason is the guard below. The
# non-vacuity check has to build a specimen that the detector must fire on; for
# a literal the specimen IS the literal, derived at run time and costing this
# file no spelled-out private string. For a regex it would have to be supplied
# as text, and that text would be the private string, spelled, in whatever file
# supplied it. Several literals may share one class name; they accumulate.
CLASS_PROBE_NEGATIVE = b"a line with nothing of the kind anywhere in it"


class SurfaceError(Exception):
    """The mode could not run at all -- exit 2, never a verdict."""


def _git(repo, *args):
    import subprocess

    p = subprocess.run(("git", "-C", repo) + args, capture_output=True)
    return p.returncode, p.stdout


# THE MEASURED SIDE IS A REVISION, AND THERE IS NO LONGER A READER FOR ANYTHING
# ELSE. What used to stand here read the WORKING TREE, and that made the verdict
# a function of an input no receipt records: the same commit, the same subject
# and the same declaration produced PASS and FAIL an hour apart because a
# tracked file's bytes had been edited in place and never staged. git does not
# record the tree that was on disk at either moment, so a receipt pinning
# gitHeadSha did not identify the object it judged. Both sides of the comparison
# now come from `_tracked_at`, and the function that read the disk is gone
# rather than kept as an option: an option is a way back.
def _tracked_at(repo, rev):
    """path -> bytes, for the tree of `rev`. What a push of `rev` carries, and
    nothing a push leaves behind."""
    rc, _ = _git(repo, "rev-parse", "--verify", "%s^{tree}" % rev)
    if rc != 0:
        raise SurfaceError("baseline %r does not resolve in %s" % (rev, repo))
    rc, out = _git(repo, "ls-tree", "-r", "-z", rev)
    if rc != 0:
        raise SurfaceError("git ls-tree failed for %r" % rev)
    files = {}
    for row in out.split(b"\0"):
        if not row:
            continue
        meta, _, path = row.partition(b"\t")
        parts = meta.split()
        if len(parts) < 3 or parts[1] != b"blob":
            continue
        rc2, blob = _git(repo, "cat-file", "blob", parts[2].decode())
        if rc2 == 0:
            files[path.decode("utf-8", "replace")] = blob
    return files


def _classes(declared):
    """name -> (kind, [(literal_bytes, case_insensitive), ...]).

    The quotable classes arrive from the caller. The two that identify THIS
    machine are computed from the running process and are never written down
    anywhere, which is what makes them unlaunderable: a declaration cannot
    exempt what no declaration can name."""
    out = {}
    for spec in declared:
        name, _, rest = spec.partition("=")
        flags, _, literal = rest.partition(":")
        if not name or not literal:
            raise SurfaceError("--class wants NAME=FLAGS:LITERAL, got %r" % spec)
        out.setdefault(name, ("declared", []))[1].append(
            (literal.encode(), "I" in flags))
    home = os.path.expanduser("~")
    if home and home != "~" and len(home) >= 4:
        out["homepath"] = ("computed", [(home.encode(), False)])
    import socket

    short = socket.gethostname().split(".")[0]
    if short and len(short) >= 4:
        out["hostname"] = ("computed", [(short.encode(), True)])
    if not out:
        raise SurfaceError("no classes: a boundary with nothing to look for is not green")
    return out


def _find(blob, literal, ci):
    hay = blob.lower() if ci else blob
    needle = literal.lower() if ci else literal
    at, out = 0, []
    while True:
        i = hay.find(needle, at)
        if i < 0:
            return out
        out.append(i)
        at = i + 1


def _hits(blob, classes):
    """class -> [(offset, literal), ...] for every occurrence, all classes."""
    found = {}
    for name, (_kind, lits) in classes.items():
        for lit, ci in lits:
            for off in _find(blob, lit, ci):
                found.setdefault(name, []).append((off, lit))
    return found


def _exempt_rule(blob, hits):
    """Reason 1, first shape: the rule that removes a string must state the
    string -- and may state it only in the slots whose declared job is to quote
    it. A rule carrying it in a `note` beside them is not a rule; it is a leak
    wearing a rule's shape."""
    try:
        doc = json.loads(blob.decode("utf-8"))
    except Exception:
        return False
    if not isinstance(doc, dict):
        return False
    slots = [doc.get("pattern"), doc.get("replacement")]
    if not any(isinstance(s, str) for s in slots):
        return False
    spans = []
    for s in slots:
        if isinstance(s, str):
            for off in _find(blob, s.encode(), False):
                spans.append((off, off + len(s.encode())))
    for _name, occurrences in hits.items():
        for off, lit in occurrences:
            if not any(a <= off and off + len(lit) <= b for a, b in spans):
                return False
    return True


def _exempt_declaration(blob, hits, classes):
    """Reason 1, second shape: the file that NAMES the classes cannot avoid
    carrying them. It is exempt only where each occurrence is exactly a
    declared literal and nothing wider -- so a real machine fact pasted into
    it is still refused, and a computed class, which no declaration can name,
    is never exempt here at all."""
    for name, (kind, lits) in classes.items():
        if kind != "declared":
            continue
        for lit, ci in lits:
            if not _find(blob, lit, ci):
                # It does not in fact declare what the invocation says it does.
                return False
    for name, occurrences in hits.items():
        kind, lits = classes[name]
        if kind != "declared":
            return False
        exact = set(lit for lit, _ci in lits)
        for _off, lit in occurrences:
            if lit not in exact:
                return False
    return True


def _pin_index(files, skip):
    tokens = set()
    for path, blob in files.items():
        if path == skip:
            continue
        for m in RE_SHA256_TOKEN.finditer(blob.decode("latin-1")):
            tokens.add(m.group(0))
    return tokens


def _exemption(path, blob, hits, files, classes, declaration):
    if _exempt_rule(blob, hits):
        return "DECLARES/rule"
    if path == declaration and _exempt_declaration(blob, hits, classes):
        return "DECLARES/self"
    import hashlib

    if hashlib.sha256(blob).hexdigest() in _pin_index(files, path):
        return "PINNED"
    return None


def _guard(classes):
    """Non-vacuity, on every invocation, through the same code path the verdict
    uses. Every class's own literal is planted in a synthetic file; the walk
    must find each class in it and must refuse it, and must find nothing in a
    file built to carry nothing. A count this check cannot produce is reported
    UNMEASURED, never as zero."""
    problems = []
    probe = b"\n".join(lits[0][0] for _k, lits in classes.values())
    seen = _hits(probe, classes)
    for name in classes:
        if name not in seen:
            problems.append("%s: the detector did not fire on a specimen built from its own "
                            "literal -- this class measured nothing" % name)
    if _exemption("<probe>", probe, seen, {"<probe>": probe}, classes, None) is not None:
        problems.append("the probe was exempted; the exemption path cannot be trusted to "
                        "refuse anything")
    if _hits(CLASS_PROBE_NEGATIVE, classes):
        problems.append("the detector fired on a specimen built to carry nothing")
    return problems


def _remotes(repo):
    rc, out = _git(repo, "remote")
    if rc != 0:
        raise SurfaceError("git remote failed in %s" % repo)
    return [r.decode() for r in out.split() if r]


def surface(repo, baseline, declared_classes, declarations, declaration=None,
            now_rev="HEAD"):
    classes = _classes(declared_classes)
    unmeasured = _guard(classes)
    for u in unmeasured:
        print("UNMEASURED %s" % u)

    # THE SEPARATION, AND WHY IT IS THIS FACT AND NOT A PATH LIST. A repository
    # with no remote has no public surface: there is nowhere for a push to go.
    # That is a fact about the repository, read from it, not a promise anyone
    # made about it -- which is the whole difference between a separation and a
    # habit. The internal surface is complete and not presentable, and it stays
    # legible precisely because the day someone gives it a remote, this claim
    # stops being satisfied by the emptiness and starts measuring the tree.
    remotes = _remotes(repo)
    if not remotes:
        print("no remote configured: nothing can be pushed from %s, so the public "
              "surface is empty. This is the internal surface. Give this repository "
              "a remote and the same claim measures the whole tree against the "
              "declared baseline instead." % os.path.abspath(repo))
        return 1 if unmeasured else 0
    print("remotes: %s -- this repository publishes; the tracked set is the public surface"
          % ", ".join(remotes))

    rc, out = _git(repo, "rev-parse", now_rev)
    resolved = out.decode().strip() if rc == 0 else now_rev
    now = _tracked_at(repo, now_rev)
    print("measuring %s == %s: the verdict is a function of this commit and of "
          "nothing in the working tree" % (now_rev, resolved))
    if not now:
        raise SurfaceError("the tracked set of %r is empty; a boundary over nothing "
                           "is not green" % now_rev)
    base = _tracked_at(repo, baseline)

    # --- the surface that already exists: exactly as declared, not at most ---
    base_counts = {}
    for _path, blob in base.items():
        for name, occ in _hits(blob, classes).items():
            f, o = base_counts.get(name, (0, 0))
            base_counts[name] = (f + 1, o + len(occ))
    print("baseline %s: %d tracked file(s)" % (baseline, len(base)))
    moved = 0
    for name in sorted(classes):
        kind = classes[name][0]
        got = base_counts.get(name, (0, 0))
        want = declarations.get(name)
        if want is None:
            state = "undeclared"
        elif want == got:
            state = "as declared"
        else:
            state = "MOVED (declared %d file(s), %d occurrence(s))" % want
            moved += 1
        print("  baseline %-10s %-8s %d file(s), %d occurrence(s)  -- %s"
              % (name, kind, got[0], got[1], state))
    for name in declarations:
        if name not in classes:
            print("  baseline %-10s declared, but no such class in this invocation" % name)
            moved += 1

    # --- the surface this change adds: zero NEW, unless a reason says otherwise ---
    #
    # THE CHARGE IS PER FILE, PER CLASS, ON THE DELTA. Whole-file byte inequality
    # still decides which files are worth looking at -- that is only the candidate
    # set -- but what a file is charged is what the change ADDS to it:
    # max(0, now - base), class by class. The rule this replaces charged the whole
    # blob of every file whose bytes moved, so a document the baseline already
    # counts, and already ADMITS in its declared census, became a file charged
    # with every occurrence it had carried all along the moment one byte of it
    # changed for an unrelated reason. That is wider than the claim it serves,
    # whose own words are zero NEW occurrences on the surface a change adds; and a
    # boundary that refuses what it has already accepted is not measuring the
    # thing it is named for.
    #
    # PER CLASS AND CLAMPED, and neither is a detail. Collapsed into one number
    # per file, a commit that removes one class's occurrence and adds another's
    # nets to zero and travels. Unclamped, a commit whose only effect is to
    # REMOVE material is refused for a negative charge. Both are refused by
    # tests/bypass_ft_surface_charges_untouched_occurrences_fixture.sh.
    #
    # THE HOLE THIS FORM LEAVES, named rather than hidden: one occurrence of the
    # SAME class added and one removed in the same file in the same commit nets to
    # zero and is not charged. A count cannot see that; only an anchor on the
    # lines a diff adds can, and adopting one is a decision and not an edit. It is
    # recorded here so the next reader does not rediscover it from a survivor.
    #
    # EXEMPTION STAYS WHOLE-FILE. Whether a file is a rule that names what it
    # replaces, the declaration itself, or evidence fixed by a digest is a
    # property of the whole file, never of the occurrences one commit happens to
    # add. Asking it of the delta alone would let the shape of the bytes AROUND a
    # leak exempt the leak.
    added = sorted(p for p, b in now.items() if base.get(p) != b)
    print("delta vs %s: %d added or changed tracked file(s)" % (baseline, len(added)))
    refused = exempted = carried = 0
    for path in added:
        hits = _hits(now[path], classes)
        if not hits:
            continue
        was = _hits(base.get(path, b""), classes)
        charged = {}
        for name, occurrences in hits.items():
            gained = len(occurrences) - len(was.get(name, ()))
            if gained > 0:
                charged[name] = gained
        if not charged:
            # Reported and not skipped: a file that carries a class and is not
            # charged for it is exactly the case this rule changed, and a reader
            # who cannot see it cannot check that the change is the right width.
            carried += 1
            print("  CARRIED  %-62s %s  [bytes moved, no class gained an occurrence]"
                  % (path, ", ".join("%s x%d" % (k, len(v))
                                     for k, v in sorted(hits.items()))))
            continue
        reason = _exemption(path, now[path], hits, now, classes, declaration)
        detail = ", ".join("%s +%d of %d" % (k, charged[k], len(hits[k]))
                           for k in sorted(charged))
        if reason:
            exempted += 1
            print("  EXEMPT   %-62s %s  [%s]" % (path, detail, reason))
        else:
            refused += 1
            print("  REFUSED  %-62s %s  [no stated reason: neither the rule that names "
                  "what it replaces nor evidence fixed by a digest]" % (path, detail))
    print("surface: %d refused, %d exempt, %d carried, %d class(es) moved on the "
          "baseline, %d unmeasured"
          % (refused, exempted, carried, moved, len(unmeasured)))
    return 1 if (refused or moved or unmeasured) else 0


# The specimens for --surface --selftest, built as real repositories so that the
# boundary is exercised end to end -- ls-files, the baseline tree, both shapes
# of reason 1, reason 2 -- and not only in its inner functions. The literal
# planted here is a home path that is NOT this operator's: a control that had to
# spell the thing it guards would be an instance of what it refuses.
def surface_selftest():
    import hashlib
    import shutil
    import subprocess
    import tempfile

    home = "/" + "Users" + "/nobody/Code/thing"
    cls = ["userpath=F:" + LITERAL_USERS]
    failures = []
    root = tempfile.mkdtemp(prefix="surface-selftest.")
    try:
        def repo(name):
            d = os.path.join(root, name)
            os.makedirs(d)
            for cmd in (("init", "-q"), ("config", "user.email", "f@example.invalid"),
                        ("config", "user.name", "selftest"),
                        ("config", "commit.gpgsign", "false")):
                subprocess.run(("git", "-C", d) + cmd, capture_output=True)
            add(d, "README.md", "nothing private\n")
            subprocess.run(("git", "-C", d, "branch", "-f", "baseline", "HEAD"),
                           capture_output=True)
            # Every arm below measures a PUBLISHING repository; the two arms at
            # the end are the pair that measures the separation itself.
            subprocess.run(("git", "-C", d, "remote", "add", "origin",
                            "https://example.invalid/x.git"), capture_output=True)
            return d

        def add(d, rel, text):
            full = os.path.join(d, rel)
            if os.path.dirname(full):
                os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as fh:
                fh.write(text)
            subprocess.run(("git", "-C", d, "add", "--", rel), capture_output=True)
            subprocess.run(("git", "-C", d, "commit", "-q", "-m", "added"), capture_output=True)

        def arm(label, d, want, decls=None, declaration=None):
            try:
                rc = surface(d, "baseline", cls, decls or {}, declaration)
            except SurfaceError as e:
                failures.append("%s: the boundary could not run (%s)" % (label, e))
                return
            if rc != want:
                failures.append("%s: wanted exit %d, got %d" % (label, want, rc))

        d = repo("plain")
        add(d, "runs/note.md", "the run wrote into %s/out\n" % home)
        arm("a plain added file carrying a home path", d, 1)

        d = repo("rule")
        add(d, "scripts/rule.json",
            '{"id":"path-transform/v1","pattern":"%s","replacement":"<LOCAL_ROOT>"}' % home)
        arm("a rule that names what it replaces", d, 0)

        d = repo("rule-leaky")
        add(d, "scripts/rule.json",
            '{"id":"x","pattern":"%s/a","replacement":"<L>","note":"also seen at %s/b"}'
            % (home, home))
        arm("a rule carrying the string outside its own slots", d, 1)

        body = "ps row: 4711 1 8192 00:03 %s/bin/worker\n" % home
        sha = hashlib.sha256(body.encode()).hexdigest()
        d = repo("pinned")
        add(d, "runs/stream.jsonl", body)
        add(d, "runs/record.json",
            '{"subject":[{"name":"stream.jsonl","digest":{"sha256":"%s"}}]}\n' % sha)
        arm("evidence fixed by a digest", d, 0)

        d = repo("unpinned")
        add(d, "runs/stream.jsonl", body)
        add(d, "runs/record.json",
            '{"subject":[{"name":"stream.jsonl","digest":{"sha256":"%s"}}]}\n' % ("0" * 64))
        arm("the same evidence, unpinned", d, 1)

        d = repo("declaration")
        add(d, "claims.json", '{"run":"grep -F %s"}\n' % LITERAL_USERS)
        arm("the file that names the class, carrying it exactly", d, 0,
            None, "claims.json")

        # The strongest arm: the declaration exemption must not launder a fact
        # about THIS machine. `homepath` is computed, so no declaration can name
        # it, so the same file that is exempt above is refused here.
        d = repo("declaration-wider")
        add(d, "claims.json", '{"run":"grep -F %s","seen":"%s/out"}\n'
            % (LITERAL_USERS, os.path.expanduser("~")))
        arm("the declaration carrying a fact about this machine", d, 1, None, "claims.json")

        d = repo("clean")
        add(d, "docs/x.md", "a document naming nothing\n")
        arm("the positive control: an added file carrying nothing", d, 0)

        d = repo("declared-wrong")
        add(d, "README.md", "nothing private\nthe census ran under %s\n" % home)
        subprocess.run(("git", "-C", d, "branch", "-f", "baseline", "HEAD"), capture_output=True)
        add(d, "other.md", "still nothing\n")
        arm("a baseline count declared wrong by one", d, 1, {"userpath": (1, 2)})

        # The separation itself, as one repository measured twice. Nothing about
        # the tree changes between the two arms; only whether it can be pushed.
        d = repo("internal")
        add(d, "runs/note.md", "the run wrote into %s/out\n" % home)
        subprocess.run(("git", "-C", d, "remote", "remove", "origin"), capture_output=True)
        arm("internal material in a repository with no remote", d, 0)
        subprocess.run(("git", "-C", d, "remote", "add", "origin",
                        "https://example.invalid/x.git"), capture_output=True)
        arm("the same tree the moment it gains a remote", d, 1)
    finally:
        shutil.rmtree(root, ignore_errors=True)

    for f in failures:
        print("surface selftest FAILED: " + f, file=sys.stderr)
    if not failures:
        print("surface selftest: eleven specimens, each judged as intended")
    return 1 if failures else 0


def main(argv):
    args = argv[1:]
    if not args:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("usage: statement_lint.py [--selftest|--sweep [ROOT ...]|--surface ...|FILE ...]",
              file=sys.stderr)
        return 2

    if args[0] == "--surface":
        rest = args[1:]
        if rest and rest[0] == "--selftest":
            return surface_selftest()
        repo, baseline, cls, decl, declaration = ".", "origin/main", [], {}, None
        now_rev = "HEAD"
        i = 0
        while i < len(rest):
            a = rest[i]
            if a in ("--repo", "--baseline", "--now", "--class", "--declare",
                     "--declaration"):
                if i + 1 >= len(rest):
                    print("--surface: %s needs a value" % a, file=sys.stderr)
                    return 2
                v = rest[i + 1]
                if a == "--repo":
                    repo = v
                elif a == "--baseline":
                    baseline = v
                elif a == "--now":
                    now_rev = v
                elif a == "--declaration":
                    declaration = v
                elif a == "--class":
                    cls.append(v)
                else:
                    name, _, nums = v.partition("=")
                    f, _, o = nums.partition(":")
                    try:
                        decl[name] = (int(f), int(o))
                    except ValueError:
                        print("--declare wants NAME=FILES:OCCURRENCES, got %r" % v, file=sys.stderr)
                        return 2
                i += 2
                continue
            print("--surface: unknown argument %r" % a, file=sys.stderr)
            return 2
        try:
            return surface(repo, baseline, cls, decl, declaration, now_rev)
        except SurfaceError as e:
            print("UNMEASURED: %s" % e, file=sys.stderr)
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
