#!/usr/bin/env python3
"""Path-transformation verifier: a re-pinned blob is declared, or it is drift.

  path_transform_verify.py RECORD_JSON [--rule RULE_JSON] [--repo-root DIR]

A commit that changes a tracked file's blob sha with no code change is
ordinarily a red flag -- the one legitimate reason this repository accepts is
a *declared* literal-substring transformation: a rule file (path-transform
rule, e.g. `scripts/path_transform_rule_v1.json`) named by id and pinned by
its own sha256, plus a record of exactly which paths moved from which blob to
which blob under it. This script is what "declared" means operationally: it
recomputes rather than trusts the record's own narration.

Exit codes:
  0  DECLARED     rule file present, its sha256 matches the record's pin,
                  and every entry's current on-disk blob sha equals the
                  record's declared newSha, with none of the rule's pattern
                  still present in the file.
  2  UNDECLARED   the rule file the record cites does not exist on disk.
                  A blob that moved with no rule alongside it is exactly the
                  case this script exists to refuse -- silent redaction,
                  not declared transformation.
  3  RULE-DRIFT   the rule file exists but its sha256 does not match the
                  record's pin -- the rule on disk is not the rule the
                  transformation was declared under.
  4  BLOB-DRIFT   an entry's current on-disk blob sha does not equal the
                  record's declared newSha -- the file moved again since the
                  transformation, or the record's own arithmetic is wrong.
  5  INCOMPLETE   an entry's current on-disk bytes still contain the rule's
                  literal pattern -- the substitution the record claims to
                  have made was not actually made.
  1  MALFORMED    RECORD_JSON or RULE_JSON does not parse, or is missing a
                  required key. Never a pass.

Nothing here rewrites a file. This is read-only recomputation.
"""
import hashlib
import json
import sys


def git_blob_sha(repo_root, rel_path):
    with open(repo_root + "/" + rel_path, "rb") as fh:
        data = fh.read()
    header = ("blob %d\0" % len(data)).encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def main(argv):
    if len(argv) < 2:
        print("usage: path_transform_verify.py RECORD_JSON [--rule RULE_JSON] "
              "[--repo-root DIR]", file=sys.stderr)
        return 1

    record_path = argv[1]
    rule_path = None
    repo_root = "."
    i = 2
    while i < len(argv):
        if argv[i] == "--rule" and i + 1 < len(argv):
            rule_path = argv[i + 1]
            i += 2
        elif argv[i] == "--repo-root" and i + 1 < len(argv):
            repo_root = argv[i + 1]
            i += 2
        else:
            print("unrecognised argument: %s" % argv[i], file=sys.stderr)
            return 1

    try:
        with open(record_path) as fh:
            record = json.load(fh)
        rule_decl = record["rule"]
        rule_id = rule_decl["id"]
        rule_sha_declared = rule_decl["sha256"]
        entries = record["entries"]
        for e in entries:
            e["path"]; e["originalSha"]; e["newSha"]
    except (OSError, KeyError, json.JSONDecodeError) as exc:
        print("MALFORMED record: %s" % exc, file=sys.stderr)
        return 1

    if rule_path is None:
        rule_path = repo_root.rstrip("/") + "/scripts/path_transform_rule_v1.json"

    try:
        with open(rule_path, "rb") as fh:
            rule_bytes = fh.read()
    except OSError:
        print("UNDECLARED: rule file not found at %s (record cites id=%s, "
              "sha256=%s) -- a moved blob with no rule alongside it is not a "
              "declared transformation" % (rule_path, rule_id, rule_sha_declared),
              file=sys.stderr)
        return 2

    rule_sha_actual = hashlib.sha256(rule_bytes).hexdigest()
    if rule_sha_actual != rule_sha_declared:
        print("RULE-DRIFT: %s sha256 is %s, record declares %s" %
              (rule_path, rule_sha_actual, rule_sha_declared), file=sys.stderr)
        return 3

    try:
        rule = json.loads(rule_bytes)
        pattern = rule["pattern"]
    except (json.JSONDecodeError, KeyError) as exc:
        print("MALFORMED rule: %s" % exc, file=sys.stderr)
        return 1

    for e in entries:
        path, new_sha = e["path"], e["newSha"]
        try:
            actual_sha = git_blob_sha(repo_root, path)
        except OSError as exc:
            print("BLOB-DRIFT: cannot read %s: %s" % (path, exc), file=sys.stderr)
            return 4
        if actual_sha != new_sha:
            print("BLOB-DRIFT: %s is %s on disk, record declares %s" %
                  (path, actual_sha, new_sha), file=sys.stderr)
            return 4
        with open(repo_root.rstrip("/") + "/" + path, "rb") as fh:
            if pattern.encode("utf-8") in fh.read():
                print("INCOMPLETE: %s still contains the rule's literal pattern"
                      % path, file=sys.stderr)
                return 5

    print("DECLARED: rule %s verified, %d entr%s verified" %
          (rule_id, len(entries), "y" if len(entries) == 1 else "ies"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
