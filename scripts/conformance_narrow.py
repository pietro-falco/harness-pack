#!/usr/bin/env python3
"""Narrowing proposal: the record's answer to a surface wider than the use.

  conformance_narrow.py OUT_PROPOSAL_JSON STATEMENT_JSON [STATEMENT_JSON...]

Reads one or more conformance records and emits a PROPOSAL artifact: the
narrowest surface the accumulated evidence supports -- tools every record
declared, minus tools no record ever saw executed; a max spawn depth no
deeper than the deepest delegation observed. The proposal carries the
digest of every record it derives from, so it is verifiable against the
same evidence chain and recomputable by anyone holding the records.

PROPOSE, NEVER APPLY. This tool writes a side-car file and edits nothing:
a narrowing is the operator's decision, and a spec that rewrites itself
without a trace is exactly what this harness exists to prevent. An input
set whose declarations disagree is refused -- a proposal computed across
different surfaces would narrow nobody's declaration in particular.

Canonical form (ADR-018 D1): sorted keys, compact separators, UTF-8, no
trailing newline. Exit 0 written, 3 refused.
"""
import hashlib
import json
import os
import sys

PROPOSAL_TYPE = (
    "https://github.com/pietro-falco/harness-pack/attestation/"
    "narrowing-proposal/v1")


def die(msg):
    sys.stderr.write("conformance_narrow: %s\n" % msg)
    sys.exit(3)


def main():
    if len(sys.argv) < 3:
        die("usage: conformance_narrow.py OUT_PROPOSAL_JSON "
            "STATEMENT_JSON [STATEMENT_JSON...]")
    out_path = sys.argv[1]
    based_on = []
    declared_seen = None
    executed = set()
    max_depth_observed = 0
    for st_path in sys.argv[2:]:
        try:
            raw = open(st_path, "rb").read()
            st = json.loads(raw.decode("utf-8"))
            pred = st["predicate"]
            declared = pred["declaredSurface"]
            exercised = pred["exercised"]
        except (OSError, KeyError, TypeError, ValueError,
                json.JSONDecodeError) as exc:
            die("unreadable record %s: %s" % (st_path, exc))
        if declared_seen is None:
            declared_seen = declared
        elif declared_seen != declared:
            die("records declare different surfaces; refusing to propose "
                "across them")
        for entry in exercised:
            if entry["result"] == "ok":
                executed.add(entry["tool"])
                if entry["depth"] > max_depth_observed:
                    max_depth_observed = entry["depth"]
        based_on.append({"name": os.path.basename(st_path),
                         "sha256": hashlib.sha256(raw).hexdigest()})
    if declared_seen is None:
        die("no records given")
    dropped = sorted(set(declared_seen["tools"]) - executed)
    proposal = {
        "_type": PROPOSAL_TYPE,
        "basedOn": sorted(based_on, key=lambda b: b["name"]),
        "declared": {"maxSpawnDepth": declared_seen["maxSpawnDepth"],
                     "tools": declared_seen["tools"]},
        "observed": {"executedTools": sorted(executed),
                     "maxDepth": max_depth_observed},
        "proposed": {"maxSpawnDepth": max_depth_observed,
                     "tools": sorted(set(declared_seen["tools"]) & executed)},
        "droppedAuthorizations": dropped,
    }
    canon = json.dumps(proposal, sort_keys=True, separators=(",", ":"),
                       ensure_ascii=False).encode("utf-8")
    with open(out_path, "wb") as fh:
        fh.write(canon)
    sys.stdout.write("%s sha256:%s\n"
                     % (out_path, hashlib.sha256(canon).hexdigest()))


if __name__ == "__main__":
    main()
