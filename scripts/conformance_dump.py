#!/usr/bin/env python3
"""Second consumer of the conformance record: a static dump.

  conformance_dump.py STATEMENT_JSON

Reads ONLY the Statement -- never the stream, never the declaration file,
never any live state. Its existence is the proof that the record is the
API: a renderer with no access to the run can still say everything a
front-end would say. If a future interface needs a fact this dump cannot
print, the fact belongs in the record, not in the interface.

Deterministic plain text to stdout; exit 0 on a readable record, 3 on an
unreadable one. This file renders, it does not verify: a record that lies
dumps its lie, and conformance_verify.py is where lies go to die.
"""
import json
import sys


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: conformance_dump.py STATEMENT_JSON\n")
        sys.exit(3)
    try:
        st = json.load(open(sys.argv[1], encoding="utf-8"))
        pred = st["predicate"]
        subject = st["subject"][0]
        declared = pred["declaredSurface"]
        out = []
        out.append("conformance record %s" % st["predicateType"])
        out.append("subject %s sha256:%s"
                   % (subject["name"], subject["digest"]["sha256"]))
        out.append("run %s source %s" % (pred["measurement"]["run"],
                                         pred["measurement"]["source"]))
        out.append("declared tools: %s" % ",".join(declared["tools"]))
        out.append("declared max spawn depth: %d" % declared["maxSpawnDepth"])
        out.append("delegations:")
        for d in pred["delegations"]:
            out.append("  depth %d -> %d  %s" % (d["depth"], d["depth"] + 1,
                                                 d["toolUseId"]))
        out.append("exercised:")
        for e in pred["exercised"]:
            out.append("  depth %d  %-12s %-10s %s"
                       % (e["depth"], e["tool"], e["result"], e["toolUseId"]))
        out.append("unused authorizations: %s"
                   % (",".join(pred["unusedAuthorizations"]) or "-"))
        out.append("stream complete: %s"
                   % pred["completeness"]["streamResultEvent"])
        out.append("comparison rule: %s sha256:%s"
                   % (pred["comparisonRule"]["id"],
                      pred["comparisonRule"]["sha256"]))
        sys.stdout.write("\n".join(out) + "\n")
    except (OSError, KeyError, TypeError, ValueError,
            json.JSONDecodeError) as exc:
        sys.stderr.write("conformance_dump: unreadable record: %s\n" % exc)
        sys.exit(3)


if __name__ == "__main__":
    main()
