#!/usr/bin/env python3
"""Conformance verifier: recompute the comparison, trust nothing narrated.

  conformance_verify.py STATEMENT_JSON [EVIDENCE_DIR]

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
import sys

STATEMENT_TYPE = "https://in-toto.io/Statement/v1"
PREDICATE_TYPE = (
    "https://github.com/pietro-falco/harness-pack/attestation/"
    "conformance-record/v1")
RULE_ID = "conformance-compare/v1"
RULE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "conformance_rule_v1.json")

KEYSETS = {
    "statement": {"_type", "predicate", "predicateType", "subject"},
    "subject": {"digest", "name"},
    "digest": {"sha256"},
    "predicate": {"comparisonRule", "completeness", "declaredSurface",
                  "delegations", "evidence", "exercised", "measurement",
                  "unusedAuthorizations"},
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
    keys_exactly(pred["comparisonRule"], "comparisonRule", "comparisonRule")
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


def recompute_stream(path):
    """Independent re-analysis: iterative depth resolution, own pairing."""
    uses = {}
    order = []
    error_by_id = {}
    parent_by_id = {}
    complete = False
    with open(path, encoding="utf-8") as fh:
        for line in fh:
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


def parse_declaration(path):
    with open(path, encoding="utf-8") as fh:
        header = fh.readline().strip()
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
    if len(sys.argv) not in (2, 3):
        not_recomputable("usage: conformance_verify.py STATEMENT_JSON "
                         "[EVIDENCE_DIR]")
    st_path = sys.argv[1]
    if os.path.isdir(st_path):
        st_path = os.path.join(st_path, "statement.json")
    evidence_dir = sys.argv[2] if len(sys.argv) == 3 else os.path.dirname(
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

    by_role = {}
    for e in pred["evidence"]:
        if e["role"] not in ("declaration", "stream"):
            not_recomputable("evidence role %r outside declaration|stream"
                             % e["role"])
        by_role[e["role"]] = e
    if "declaration" not in by_role:
        finish("NOT-MEASURED", 2,
               ["no declaration evidence in the record; absence of "
                "declaration is not conformity"])
    if "stream" not in by_role:
        not_recomputable("no stream evidence in the record")

    paths = {}
    for role, e in sorted(by_role.items()):
        path = os.path.join(evidence_dir, os.path.basename(e["name"]))
        if not os.path.isfile(path):
            not_recomputable("%s evidence %s not present beside the record"
                             % (role, e["name"]))
        if sha256_file(path) != e["sha256"]:
            not_recomputable("%s evidence digest mismatch: the bytes on "
                             "disk are not the bytes the record measured"
                             % role)
        paths[role] = path
    if st["subject"][0]["digest"]["sha256"] != by_role["stream"]["sha256"]:
        not_recomputable("subject digest is not the stream evidence digest")

    declared = parse_declaration(paths["declaration"])
    if not declared["tools"]:
        finish("NOT-MEASURED", 2,
               ["declared surface is empty; absence of declaration is "
                "not conformity"])
    exercised, delegations, complete = recompute_stream(paths["stream"])

    reasons = []
    if pred["declaredSurface"] != declared:
        reasons.append("record declaredSurface differs from the "
                       "declaration evidence")
    if pred["exercised"] != exercised:
        reasons.append("record exercised list differs from the facts "
                       "recomputed from the stream")
    if pred["delegations"] != delegations:
        reasons.append("record delegation tree differs from the tree "
                       "recomputed from parent_tool_use_id")
    executed_tools = sorted({e["tool"] for e in exercised
                             if e["result"] == "ok"})
    unused = sorted(set(declared["tools"]) - set(executed_tools))
    if pred["unusedAuthorizations"] != unused:
        reasons.append("record unusedAuthorizations differs from declared "
                       "minus executed: an authorization wider than the "
                       "use went unreported")
    if pred["completeness"]["streamResultEvent"] != complete:
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
