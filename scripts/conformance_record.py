#!/usr/bin/env python3
"""Conformance record builder: one in-toto Statement per run.

  conformance_record.py RUN_DIR OUT_STATEMENT_JSON

RUN_DIR must contain the two evidence files the record is computed from:

  invocation.txt   the machine-written launch header. Its FIRST line carries
                   the resolved declared surface -- `tools=`, `allowed=`,
                   `depth=`, `pmode=` -- as the launcher resolved it at spawn
                   time. Resolved names only; a glob expands differently at
                   different moments and is refused here.
  stream.jsonl     the captured stream-json transcript. The subject of the
                   Statement is this file's digest (ADR-019: the subject is
                   the transcript). The delegation tree is recomputed from
                   `parent_tool_use_id` chains, never from the hook ledger:
                   SubagentStart fires but its payload carries no depth
                   (measured 2026-08-13, ADR-023 C2b).

The predicate vocabulary is CLOSED: every key this writer emits is a literal
spelled in this file, and the verifier refuses any key outside that set. No
field is ever populated by prose any model produced (ADR-020 D2's allowlist
rule): every string in the Statement is a literal from here, a tool name or
id read from a machine event, a basename, or a digest.

Readings follow ADR-023 D6: an emitted call proves nothing about the pool;
only its paired result does. `result` is "ok" (paired, not an error),
"error" (paired, is_error -- an attempt, never an exercise), or
"unresolved" (no paired result -- recorded, never dropped).

CANONICAL FORM (ADR-018 D1): keys sorted lexicographically, compact
separators, UTF-8, NO TRAILING NEWLINE. The digest travels; the bytes do
not: evidence enters the record as basename + sha256 only.

Exit: 0 written; 3 on any precondition failure (missing evidence, glob in
the declaration, unresolvable parent chain). This writer never guesses.
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


def die(msg):
    sys.stderr.write("conformance_record: %s\n" % msg)
    sys.exit(3)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_declaration(path):
    """First line of invocation.txt: space-separated key=value fields."""
    with open(path, encoding="utf-8") as fh:
        header = fh.readline().strip()
    fields = {}
    for token in header.split():
        if "=" in token:
            key, _, value = token.partition("=")
            fields[key] = value
    for required in ("tools", "allowed", "depth", "pmode"):
        if required not in fields:
            die("declaration header lacks %s=" % required)
    tools = sorted(t for t in fields["tools"].split(",") if t)
    allowed = sorted(t for t in fields["allowed"].split(",") if t)
    for name in tools + allowed:
        if "*" in name or "?" in name or "(" in name:
            die("declared surface carries a pattern, not a resolved name: %r"
                % name)
    if not fields["depth"].isdigit():
        die("declared depth %r is not a number" % fields["depth"])
    return {
        "allowedTools": allowed,
        "maxSpawnDepth": int(fields["depth"]),
        "permissionMode": fields["pmode"],
        "tools": tools,
    }, fields.get("arm", "")


def read_stream(path):
    events = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return events


def analyze(events):
    """tool_use/tool_result pairing and depth from parent_tool_use_id."""
    uses = []
    results = {}
    saw_result_event = False
    for ev in events:
        if ev.get("type") == "result":
            saw_result_event = True
        parent = ev.get("parent_tool_use_id")
        content = None
        if isinstance(ev.get("message"), dict):
            content = ev["message"].get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use":
                uses.append({"id": block.get("id"),
                             "name": block.get("name"),
                             "event_parent": parent})
            elif block.get("type") == "tool_result":
                results[block.get("tool_use_id")] = bool(
                    block.get("is_error"))
    parent_of = {u["id"]: u["event_parent"] for u in uses}

    def depth_of(use_id, seen=()):
        parent = parent_of.get(use_id, None)
        if use_id in seen:
            die("parent_tool_use_id chain has a cycle at %s" % use_id)
        if parent is None:
            return 0
        if parent not in parent_of:
            die("parent_tool_use_id %s never appears as a tool_use; "
                "the delegation tree is not recomputable" % parent)
        return 1 + depth_of(parent, seen + (use_id,))

    exercised = []
    delegations = []
    for u in uses:
        if u["id"] is None or u["name"] is None:
            die("tool_use block without id or name")
        depth = depth_of(u["id"])
        if u["id"] in results:
            result = "error" if results[u["id"]] else "ok"
        else:
            result = "unresolved"
        exercised.append({
            "depth": depth,
            "parentToolUseId": u["event_parent"],
            "result": result,
            "tool": u["name"],
            "toolUseId": u["id"],
        })
        if u["name"] == "Agent" and result == "ok":
            delegations.append({
                "depth": depth,
                "parentToolUseId": u["event_parent"],
                "toolUseId": u["id"],
            })
    exercised.sort(key=lambda e: (e["depth"], e["toolUseId"]))
    delegations.sort(key=lambda d: (d["depth"], d["toolUseId"]))
    return exercised, delegations, saw_result_event


def main():
    if len(sys.argv) != 3:
        die("usage: conformance_record.py RUN_DIR OUT_STATEMENT_JSON")
    run_dir, out_path = sys.argv[1], sys.argv[2]
    decl_path = os.path.join(run_dir, "invocation.txt")
    stream_path = os.path.join(run_dir, "stream.jsonl")
    for path in (decl_path, stream_path, RULE_FILE):
        if not os.path.isfile(path):
            die("missing %s" % path)

    declared, source = parse_declaration(decl_path)
    exercised, delegations, stream_complete = analyze(
        read_stream(stream_path))

    executed_tools = sorted({e["tool"] for e in exercised
                             if e["result"] == "ok"})
    unused = sorted(set(declared["tools"]) - set(executed_tools))

    predicate = {
        "comparisonRule": {"id": RULE_ID,
                           "sha256": sha256_file(RULE_FILE)},
        "completeness": {"streamResultEvent": stream_complete},
        "declaredSurface": declared,
        "delegations": delegations,
        "evidence": [
            {"name": os.path.basename(decl_path),
             "role": "declaration",
             "sha256": sha256_file(decl_path)},
            {"name": os.path.basename(stream_path),
             "role": "stream",
             "sha256": sha256_file(stream_path)},
        ],
        "exercised": exercised,
        "measurement": {
            "run": os.path.basename(os.path.abspath(run_dir)),
            "source": source,
        },
        "unusedAuthorizations": unused,
    }
    statement = {
        "_type": STATEMENT_TYPE,
        "predicate": predicate,
        "predicateType": PREDICATE_TYPE,
        "subject": [{"digest": {"sha256": sha256_file(stream_path)},
                     "name": os.path.basename(stream_path)}],
    }
    canon = json.dumps(statement, sort_keys=True, separators=(",", ":"),
                       ensure_ascii=False).encode("utf-8")
    with open(out_path, "wb") as fh:
        fh.write(canon)
    sys.stdout.write("%s sha256:%s\n"
                     % (out_path, hashlib.sha256(canon).hexdigest()))


if __name__ == "__main__":
    main()
