#!/usr/bin/env python3
"""Conformance verifier: recompute the comparison, trust nothing narrated.

  conformance_verify.py STATEMENT_JSON [EVIDENCE_DIR] [--ledger-repo DIR]

Exit codes are the gate's own:
  0  CONFORMANT      every executed call inside the declared surface, every
                     delegation within the declared depth, record facts equal
                     the facts recomputed from the evidence.
  1  DIVERGENT       the execution left its declaration, or the record does
                     not match its own evidence.
  2  NOT-RECOMPUTABLE / NOT-MEASURED / INCOMPLETE -- never a pass. A record
                     that cannot be recomputed certifies nothing; a run with
                     no declaration is not conformant, it is unmeasured; a
                     truncated stream licenses no verdict.

EVIDENCE_DIR defaults to the statement's directory; the evidence files are
located by the record's own `evidence[].name` basenames. Digests must match
before any fact is recomputed: the digest travels, the bytes do not, and a
byte that moved makes the record NOT-RECOMPUTABLE, not wrong.

THE ANCHOR (--ledger-repo). Every check below except two is internal to the
record/evidence pair, and THR-COVER measured what that buys: a mutant that
rewrites evidence AND re-pins the digests coherently is self-certifying
(C6, C8 survived at 5/9). The predicate therefore takes one input from
where the record's author cannot write: the append-only observation ledger
(refs/observations/ledger, lanewright ADR-004, compare-and-swap on the
ref). The apparatus anchors the declaration digest at t0 and the stream
digest at close as ledger entries BEFORE the record is built
(conformance_anchor.sh); the record cites the two entry ids in
predicate.anchor; this verifier recomputes the anchored manifest bytes from
the record's own run name and digests and compares blob ids against the
cited entries. A record whose digests were re-pinned after anchoring
diverges from the chain, and the chain is not reachable from the record.
The cost is accepted by design: an anchored record is NOT verifiable in
isolation -- no ledger, no verdict (the same posture ADR-024 OR-1 takes
for evidence). Deep chain adjudication (rewrites, consistency against a
known head) stays with lanewright's interval/verify.py; this verifier
checks inclusion, the anchored blob, the deposit ORDER (the declaration
entry precedes the stream entry in the chain), and the COUNT (a run is
anchored exactly once). What none of that says is wall-clock time: order
is not a date, and that the declaration predates the execution is a
property of the apparatus, declared as a limit (ADR-025), not verified
here.

This file recomputes the stream analysis with its OWN implementation rather
than importing the builder's: two computations that must agree, so a defect
in one is a visible disagreement instead of a shared blind spot (the same
posture as the two-axis detector, ADR-023 D6).

The predicate vocabulary is CLOSED. Any key outside the sets spelled below
-- including any prose field a model might add -- is NOT-RECOMPUTABLE. A
record is facts and digests, or it is not a record.

Output is deterministic for a given input: fixed ordering, no timestamps.
Two runs over the same record that disagree are a verifier defect
(fixture: replay-nondeterminism).
"""
import hashlib
import json
import os
import subprocess
import sys

STATEMENT_TYPE = "https://in-toto.io/Statement/v1"
PREDICATE_TYPE = (
    "https://github.com/pietro-falco/harness-pack/attestation/"
    "conformance-record/v1")
RULE_ID = "conformance-compare/v1"
RULE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "conformance_rule_v1.json")
TRANSFORM_ID = "path-transform/v1"
TRANSFORM_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              "path_transform_rule_v1.json")

KEYSETS = {
    "statement": {"_type", "predicate", "predicateType", "subject"},
    "subject": {"digest", "name"},
    "digest": {"sha256"},
    "predicate": {"anchor", "comparisonRule", "completeness",
                  "declaredSurface", "delegations", "evidence", "exercised",
                  "measurement", "transformation", "unusedAuthorizations"},
    "anchor": {"declarationEntry", "streamEntry"},
    "transformation": {"id", "sha256"},
    "comparisonRule": {"id", "sha256"},
    "completeness": {"streamResultEvent"},
    "declaredSurface": {"allowedTools", "maxSpawnDepth", "permissionMode",
                        "tools"},
    "delegation": {"depth", "parentToolUseId", "toolUseId"},
    "evidence": {"name", "role", "sha256"},
    "exercised": {"depth", "parentToolUseId", "result", "tool", "toolUseId"},
    "measurement": {"run", "source"},
}


def finish(verdict, code, reasons):
    sys.stdout.write("verdict: %s\n" % verdict)
    for reason in sorted(reasons):
        sys.stdout.write("  %s\n" % reason)
    sys.exit(code)


def not_recomputable(reason):
    finish("NOT-RECOMPUTABLE", 2, [reason])


def keys_exactly(obj, keyset_name, where):
    if not isinstance(obj, dict):
        not_recomputable("%s is not an object" % where)
    expected = KEYSETS[keyset_name]
    got = set(obj.keys())
    if got - expected:
        not_recomputable("%s carries keys outside the closed vocabulary: %s"
                         % (where, ",".join(sorted(got - expected))))
    if expected - got:
        if keyset_name == "predicate" and "declaredSurface" in expected - got:
            finish("NOT-MEASURED", 2,
                   ["no declared surface in the record; absence of "
                    "declaration is not conformity"])
        not_recomputable("%s lacks required keys: %s"
                         % (where, ",".join(sorted(expected - got))))


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def git_blob_sha1(data):
    """The id git gives these bytes as a blob, recomputed without git: the
    anchored manifest never needs to be read back from the ledger, only
    re-derived from the record's own fields and compared by id."""
    header = ("blob %d\0" % len(data)).encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def git_ledger(repo, *args):
    """Read-only git against the ledger repository."""
    proc = subprocess.run(["git", "-C", repo] + list(args),
                          capture_output=True, text=True)
    return proc.returncode, proc.stdout.strip()


def typed_equal(a, b):
    """Equality of JSON values, not of Python values. Python's == identifies
    True with 1 (bool subclasses int), so a wrong-typed record would compare
    equal to the recomputed facts (THR-COVER C5). Canonical serialization
    distinguishes every JSON type: true is not 1, 1 is not 1.0."""
    def canon(v):
        return json.dumps(v, sort_keys=True, separators=(",", ":"),
                          ensure_ascii=False)
    return canon(a) == canon(b)


def load_statement(path):
    try:
        raw = open(path, "rb").read()
    except OSError as exc:
        not_recomputable("statement unreadable: %s" % exc)
    try:
        obj = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        not_recomputable("statement is not JSON: %s" % exc)
    canon = json.dumps(obj, sort_keys=True, separators=(",", ":"),
                       ensure_ascii=False).encode("utf-8")
    if canon != raw:
        not_recomputable("statement is not in canonical form")
    return obj


def check_schema(st):
    keys_exactly(st, "statement", "statement")
    if st["_type"] != STATEMENT_TYPE:
        not_recomputable("unknown _type %r" % st["_type"])
    if st["predicateType"] != PREDICATE_TYPE:
        not_recomputable("unknown predicateType %r" % st["predicateType"])
    if not isinstance(st["subject"], list) or len(st["subject"]) != 1:
        not_recomputable("subject must be a single-entry list")
    keys_exactly(st["subject"][0], "subject", "subject[0]")
    keys_exactly(st["subject"][0]["digest"], "digest", "subject[0].digest")
    pred = st["predicate"]
    keys_exactly(pred, "predicate", "predicate")
    keys_exactly(pred["anchor"], "anchor", "anchor")
    for key in ("declarationEntry", "streamEntry"):
        oid = pred["anchor"][key]
        if not (isinstance(oid, str) and len(oid) == 40
                and all(c in "0123456789abcdef" for c in oid)):
            not_recomputable("anchor.%s is not a 40-hex object id" % key)
    keys_exactly(pred["comparisonRule"], "comparisonRule", "comparisonRule")
    if pred["transformation"] is not None:
        keys_exactly(pred["transformation"], "transformation",
                     "transformation")
    keys_exactly(pred["completeness"], "completeness", "completeness")
    keys_exactly(pred["declaredSurface"], "declaredSurface", "declaredSurface")
    keys_exactly(pred["measurement"], "measurement", "measurement")
    for i, d in enumerate(pred["delegations"]):
        keys_exactly(d, "delegation", "delegations[%d]" % i)
    for i, e in enumerate(pred["evidence"]):
        keys_exactly(e, "evidence", "evidence[%d]" % i)
    for i, e in enumerate(pred["exercised"]):
        keys_exactly(e, "exercised", "exercised[%d]" % i)
        if e["result"] not in ("ok", "error", "unresolved"):
            not_recomputable("exercised[%d].result %r outside "
                             "ok|error|unresolved" % (i, e["result"]))
    for field in ("tools", "allowedTools"):
        if not isinstance(pred["declaredSurface"][field], list):
            not_recomputable("declaredSurface.%s is not a list" % field)
    if not isinstance(pred["unusedAuthorizations"], list):
        not_recomputable("unusedAuthorizations is not a list")


def recompute_stream(data):
    """Independent re-analysis: iterative depth resolution, own pairing.
    Takes the evidence BYTES, not a path: what is analysed is exactly what
    the digest check (possibly through the declared transformation)
    admitted, never a second read of the disk."""
    uses = {}
    order = []
    error_by_id = {}
    parent_by_id = {}
    complete = False
    for line in data.decode("utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if ev.get("type") == "result":
            complete = True
        msg = ev.get("message")
        blocks = msg.get("content") if isinstance(msg, dict) else None
        if not isinstance(blocks, list):
            continue
        for b in blocks:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "tool_use":
                uses[b.get("id")] = b.get("name")
                parent_by_id[b.get("id")] = ev.get("parent_tool_use_id")
                order.append(b.get("id"))
            elif b.get("type") == "tool_result":
                error_by_id[b.get("tool_use_id")] = bool(
                    b.get("is_error"))
    depth_by_id = {}
    pending = list(order)
    progress = True
    while pending and progress:
        progress = False
        remaining = []
        for uid in pending:
            parent = parent_by_id.get(uid)
            if parent is None:
                depth_by_id[uid] = 0
                progress = True
            elif parent in depth_by_id:
                depth_by_id[uid] = depth_by_id[parent] + 1
                progress = True
            else:
                remaining.append(uid)
        pending = remaining
    if pending:
        not_recomputable("delegation tree unresolvable for tool_use ids: %s"
                         % ",".join(sorted(str(p) for p in pending)))
    exercised = []
    delegations = []
    for uid in order:
        if uid is None or uses[uid] is None:
            not_recomputable("tool_use block without id or name in evidence")
        if uid in error_by_id:
            result = "error" if error_by_id[uid] else "ok"
        else:
            result = "unresolved"
        exercised.append({"depth": depth_by_id[uid],
                          "parentToolUseId": parent_by_id[uid],
                          "result": result, "tool": uses[uid],
                          "toolUseId": uid})
        if uses[uid] == "Agent" and result == "ok":
            delegations.append({"depth": depth_by_id[uid],
                                "parentToolUseId": parent_by_id[uid],
                                "toolUseId": uid})
    exercised.sort(key=lambda e: (e["depth"], e["toolUseId"]))
    delegations.sort(key=lambda d: (d["depth"], d["toolUseId"]))
    return exercised, delegations, complete


def parse_declaration(data):
    lines = data.decode("utf-8").splitlines()
    header = lines[0].strip() if lines else ""
    fields = dict(t.partition("=")[::2] for t in header.split() if "=" in t)
    missing = [k for k in ("tools", "allowed", "depth", "pmode")
               if k not in fields]
    if missing:
        finish("NOT-MEASURED", 2,
               ["declaration evidence lacks %s" % ",".join(missing)])
    tools = sorted(t for t in fields["tools"].split(",") if t)
    allowed = sorted(t for t in fields["allowed"].split(",") if t)
    for name in tools + allowed:
        if "*" in name or "?" in name or "(" in name:
            not_recomputable("declared surface carries a pattern, not a "
                             "resolved name: %r" % name)
    if not fields["depth"].isdigit():
        not_recomputable("declared depth %r is not a number"
                         % fields["depth"])
    return {
        "allowedTools": allowed,
        "maxSpawnDepth": int(fields["depth"]),
        "permissionMode": fields["pmode"],
        "tools": tools,
    }


def main():
    args = sys.argv[1:]
    ledger_repo = None
    positional = []
    i = 0
    while i < len(args):
        if args[i] == "--ledger-repo":
            if i + 1 >= len(args):
                not_recomputable("--ledger-repo needs a directory")
            ledger_repo = args[i + 1]
            i += 2
        else:
            positional.append(args[i])
            i += 1
    if len(positional) not in (1, 2):
        not_recomputable("usage: conformance_verify.py STATEMENT_JSON "
                         "[EVIDENCE_DIR] [--ledger-repo DIR]")
    st_path = positional[0]
    if os.path.isdir(st_path):
        st_path = os.path.join(st_path, "statement.json")
    evidence_dir = positional[1] if len(positional) == 2 else os.path.dirname(
        os.path.abspath(st_path))

    st = load_statement(st_path)
    check_schema(st)
    pred = st["predicate"]

    rule = pred["comparisonRule"]
    if rule["id"] != RULE_ID:
        not_recomputable("comparison rule id %r is not %r"
                         % (rule["id"], RULE_ID))
    if not os.path.isfile(RULE_FILE):
        not_recomputable("verifier's rule file missing")
    if sha256_file(RULE_FILE) != rule["sha256"]:
        not_recomputable("comparison rule digest mismatch: record pins a "
                         "rule this verifier does not hold")

    # The declared transformation, if the record cites one: resolved from
    # the verifier's own copy, exactly like the comparison rule.
    transform = None
    if pred["transformation"] is not None:
        if pred["transformation"]["id"] != TRANSFORM_ID:
            not_recomputable("transformation id %r is not %r"
                             % (pred["transformation"]["id"], TRANSFORM_ID))
        if not os.path.isfile(TRANSFORM_FILE):
            not_recomputable("record cites a transformation rule this "
                             "verifier does not hold: no rule file beside "
                             "the verifier")
        if sha256_file(TRANSFORM_FILE) != pred["transformation"]["sha256"]:
            not_recomputable("transformation rule digest mismatch: the rule "
                             "beside this verifier is not the rule the "
                             "record cites")
        with open(TRANSFORM_FILE, encoding="utf-8") as fh:
            try:
                tr_rule = json.load(fh)
            except json.JSONDecodeError:
                not_recomputable("verifier's transformation rule file "
                                 "is not JSON")
        if not (isinstance(tr_rule.get("pattern"), str)
                and isinstance(tr_rule.get("replacement"), str)):
            not_recomputable("verifier's transformation rule carries no "
                             "usable pattern/replacement")
        transform = (tr_rule["pattern"].encode("utf-8"),
                     tr_rule["replacement"].encode("utf-8"))

    by_role = {}
    for e in pred["evidence"]:
        if e["role"] not in ("declaration", "stream"):
            not_recomputable("evidence role %r outside declaration|stream"
                             % e["role"])
        if e["role"] in by_role:
            not_recomputable("duplicate evidence role %r: a shadowed entry "
                             "would be an evidence assertion no check ever "
                             "touches" % e["role"])
        by_role[e["role"]] = e
    if "declaration" not in by_role:
        finish("NOT-MEASURED", 2,
               ["no declaration evidence in the record; absence of "
                "declaration is not conformity"])
    if "stream" not in by_role:
        not_recomputable("no stream evidence in the record")

    content = {}
    for role, e in sorted(by_role.items()):
        path = os.path.join(evidence_dir, os.path.basename(e["name"]))
        if not os.path.isfile(path):
            not_recomputable("%s evidence %s not present beside the record"
                             % (role, e["name"]))
        with open(path, "rb") as fh:
            data = fh.read()
        if hashlib.sha256(data).hexdigest() != e["sha256"]:
            # The one legitimate way for evidence bytes to have moved: a
            # DECLARED transformation. Recompute through its inverse; a
            # digest that still mismatches is drift, not transformation.
            if transform is None:
                not_recomputable("%s evidence digest mismatch: the bytes "
                                 "on disk are not the bytes the record "
                                 "measured" % role)
            data = data.replace(transform[1], transform[0])
            if hashlib.sha256(data).hexdigest() != e["sha256"]:
                not_recomputable("%s evidence digest mismatch even through "
                                 "the declared transformation: the bytes on "
                                 "disk are not the bytes the record "
                                 "measured under the cited rule" % role)
        content[role] = data
    if st["subject"][0]["digest"]["sha256"] != by_role["stream"]["sha256"]:
        not_recomputable("subject digest is not the stream evidence digest")

    # The anchor: the one input the record's author cannot write. Inclusion
    # and identity of the cited entries are NOT-RECOMPUTABLE refusals (a
    # record citing an entry the chain does not carry certifies nothing);
    # a digest that differs from the anchored one is DIVERGENT (the record
    # contradicts the apparatus).
    if ledger_repo is None:
        not_recomputable("record is anchored to the observation ledger; "
                         "verification needs --ledger-repo -- an anchored "
                         "record is not verifiable in isolation")
    rc, head = git_ledger(ledger_repo, "rev-parse", "-q", "--verify",
                          "refs/observations/ledger")
    if rc != 0 or not head:
        not_recomputable("refs/observations/ledger not found in the ledger "
                         "repository")
    run_name = pred["measurement"]["run"]
    anchor_reasons = []
    for role, key in (("declaration", "declarationEntry"),
                      ("stream", "streamEntry")):
        entry = pred["anchor"][key]
        rc, _ = git_ledger(ledger_repo, "merge-base", "--is-ancestor",
                           entry, head)
        if rc != 0:
            not_recomputable("anchor %s %s is not included in the ledger: "
                             "the record cites an entry the chain does not "
                             "carry" % (key, entry))
        rc, raw = git_ledger(ledger_repo, "show",
                             "%s:statement.json" % entry)
        if rc != 0:
            not_recomputable("anchor %s %s carries no statement.json"
                             % (key, entry))
        try:
            row = json.loads(raw)["subject"]
            if len(row) != 1:
                raise ValueError("subject not single-row")
            got_name = row[0]["name"]
            got_blob = row[0]["digest"]["gitBlob"]
        except (ValueError, KeyError, IndexError, TypeError):
            not_recomputable("anchor %s %s statement is not readable as an "
                             "interval observation" % (key, entry))
        want_name = "anchors/%s/%s.anchor" % (run_name, role)
        if got_name != want_name:
            not_recomputable("anchor %s %s does not anchor this run's %s: "
                             "its subject is %r, not %s"
                             % (key, entry, role, got_name, want_name))
        manifest = ("conformance-anchor/v1 run=%s role=%s sha256=%s\n"
                    % (run_name, role,
                       by_role[role]["sha256"])).encode("utf-8")
        if git_blob_sha1(manifest) != got_blob:
            anchor_reasons.append(
                "record %s digest is not the digest the apparatus anchored "
                "in ledger entry %s: the record's pin diverges from an "
                "input its author cannot write" % (role, entry))

    # THE ORDER, then THE COUNT. The protocol is not just a pair of entries:
    # the apparatus deposits the declaration when the run starts and the
    # stream when it closes, so in the chain the declaration entry precedes
    # the stream entry, and a run is anchored exactly once. An inverted pair
    # means both digests were known when the first deposit was made -- the
    # anchor degrades to an input the author can time; a run appearing
    # beyond its two cited entries means it was re-anchored, and an
    # ambiguous anchor certifies nothing. Both are refusals (2), never
    # DIVERGENT: they say nothing about the run, only that the anchor
    # cannot mean what a reader would take it to mean. What neither check
    # can say is wall-clock time -- that the declaration was deposited
    # before the execution began is a property of the apparatus, not of the
    # chain, and it stays a declared limit (ADR-025), not a check.
    d_entry = pred["anchor"]["declarationEntry"]
    s_entry = pred["anchor"]["streamEntry"]
    rc, _ = git_ledger(ledger_repo, "merge-base", "--is-ancestor",
                       d_entry, s_entry)
    if rc != 0:
        not_recomputable("anchor declarationEntry %s does not precede "
                         "streamEntry %s in the ledger chain: the deposit "
                         "order contradicts the protocol (declaration at "
                         "spawn, stream at close)" % (d_entry, s_entry))
    rc, listing = git_ledger(ledger_repo, "rev-list", head)
    if rc != 0:
        not_recomputable("ledger chain is not listable from its head")
    prefix = "anchors/%s/" % run_name
    extra = []
    for entry in listing.split():
        if entry in (d_entry, s_entry):
            continue
        rc, raw = git_ledger(ledger_repo, "show",
                             "%s:statement.json" % entry)
        if rc != 0:
            continue
        try:
            name = json.loads(raw)["subject"][0]["name"]
        except (ValueError, KeyError, IndexError, TypeError):
            continue
        if isinstance(name, str) and name.startswith(prefix):
            extra.append(entry)
    if extra:
        not_recomputable("run %s appears in the ledger beyond the two "
                         "cited entries: %s -- a run anchored more than "
                         "once is ambiguous, and an ambiguous anchor "
                         "certifies nothing" % (run_name,
                                                ",".join(sorted(extra))))

    # THE OPENING (ADR-026 D3). When the anchored declaration carries the
    # streamecho=v1 marker, the apparatus committed -- under a digest the
    # author cannot re-pin -- to writing the declaration entry id as the
    # stream's first line before the child's first byte. The marker is
    # read from the declaration EVIDENCE, never from the record, and the
    # id from the stream BYTES the digest admitted: a stream that does
    # not carry it cannot be the one the apparatus opened under this
    # declaration -- the a-posteriori shape, whose stream was final
    # before the entry existed. Refusal, never DIVERGENT: an unbound
    # stream says nothing about the run's conduct (the FT-32 posture).
    # What none of this says is wall-clock time: the entries are
    # deterministic by design, so the binding is to the chain state the
    # entry extends, not to a clock (ADR-026 L1). Records whose anchored
    # declarations carry no marker predate the protocol and are exempt by
    # an input their author cannot write.
    decl_lines = content["declaration"].decode("utf-8").splitlines()
    decl_header = decl_lines[0].strip() if decl_lines else ""
    decl_fields = dict(t.partition("=")[::2]
                       for t in decl_header.split() if "=" in t)
    if decl_fields.get("streamecho") == "v1":
        stream_lines = content["stream"].decode("utf-8").splitlines()
        first = stream_lines[0].strip() if stream_lines else ""
        try:
            opening = json.loads(first)
        except json.JSONDecodeError:
            opening = None
        if not (isinstance(opening, dict)
                and opening.get("type") == "conformance_anchor"
                and opening.get("run") == run_name
                and opening.get("declarationEntry") == d_entry):
            not_recomputable(
                "declaration was deposited under streamecho=v1 but the "
                "stream's first line does not carry declaration entry %s "
                "for run %s: the record cannot be bound to its opening"
                % (d_entry, run_name))

    if anchor_reasons:
        finish("DIVERGENT", 1, anchor_reasons)

    declared = parse_declaration(content["declaration"])
    if not declared["tools"]:
        finish("NOT-MEASURED", 2,
               ["declared surface is empty; absence of declaration is "
                "not conformity"])
    exercised, delegations, complete = recompute_stream(content["stream"])

    reasons = []
    if not typed_equal(pred["declaredSurface"], declared):
        reasons.append("record declaredSurface differs from the "
                       "declaration evidence")
    if not typed_equal(pred["exercised"], exercised):
        reasons.append("record exercised list differs from the facts "
                       "recomputed from the stream")
    if not typed_equal(pred["delegations"], delegations):
        reasons.append("record delegation tree differs from the tree "
                       "recomputed from parent_tool_use_id")
    executed_tools = sorted({e["tool"] for e in exercised
                             if e["result"] == "ok"})
    unused = sorted(set(declared["tools"]) - set(executed_tools))
    if not typed_equal(pred["unusedAuthorizations"], unused):
        reasons.append("record unusedAuthorizations differs from declared "
                       "minus executed: an authorization wider than the "
                       "use went unreported")
    if not typed_equal(pred["completeness"]["streamResultEvent"], complete):
        reasons.append("record completeness differs from the stream")
    if reasons:
        finish("DIVERGENT", 1, reasons)

    if not complete:
        finish("INCOMPLETE", 2, ["stream carries no result event: the run "
                                 "was interrupted; no verdict"])
    unresolved = [e["toolUseId"] for e in exercised
                  if e["result"] == "unresolved"]
    if unresolved:
        finish("INCOMPLETE", 2, ["emitted calls with no paired result: %s"
                                 % ",".join(unresolved)])

    for e in exercised:
        if e["result"] == "ok" and e["tool"] not in declared["tools"]:
            reasons.append("executed call %s used tool %s outside the "
                           "declared surface at depth %d"
                           % (e["toolUseId"], e["tool"], e["depth"]))
    for d in delegations:
        if d["depth"] + 1 > declared["maxSpawnDepth"]:
            reasons.append("delegation %s spawns depth %d beyond declared "
                           "max %d" % (d["toolUseId"], d["depth"] + 1,
                                       declared["maxSpawnDepth"]))
    if reasons:
        finish("DIVERGENT", 1, reasons)
    finish("CONFORMANT", 0, [])


if __name__ == "__main__":
    main()
