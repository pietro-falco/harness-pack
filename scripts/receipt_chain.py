#!/usr/bin/env python3
"""Append-only hash-chained JSONL evidence log (receipt-chain.jsonl).

Each line: {"seq": n, "prev_sha256": <hex of previous raw line, no
trailing newline; "GENESIS" for line 1>, "source_filename": str,
"sha256": <hex of source file raw bytes>, "rolled_up_at": UTC ISO,
"run_id": str}

Commands:
  append --chain FILE --run-id ID SOURCE [SOURCE...]
  verify --chain FILE          (exit 0 valid, 1 invalid)
  selftest                     (round-trip, mutation, removal)

Guarantee boundary: verify detects mutation, insertion, reordering,
and removal of interior lines via seq + prev_sha256 linkage. From the
file alone it CANNOT detect mutation of the final line or clean
truncation of the tail: the head of the chain is anchored externally
by the atomic git commit (R5 in RS-001). The authoritative check is
verify against the committed blob (git show HEAD:<chain>); a
working-tree-only verify is advisory.

Torn-line policy: verify fails on any malformed line, including a
torn final line. Repairing a chain is destructive (G3): explicit
operator directive + erratum note.
"""
import argparse, hashlib, json, os, sys, tempfile
from datetime import datetime, timezone

def _sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()

def _last_line_hash(chain_path):
    if not os.path.exists(chain_path) or os.path.getsize(chain_path) == 0:
        return "GENESIS", 0
    last, count = None, 0
    with open(chain_path, "rb") as f:
        for raw in f:
            count += 1
            last = raw.rstrip(b"\n")
    return _sha(last), count

def append(chain, run_id, sources):
    prev, seq = _last_line_hash(chain)
    now = datetime.now(timezone.utc).isoformat()
    with open(chain, "a", encoding="utf-8") as out:
        for src in sources:
            with open(src, "rb") as f:
                digest = _sha(f.read())
            seq += 1
            entry = {"seq": seq, "prev_sha256": prev,
                     "source_filename": os.path.basename(src),
                     "sha256": digest, "rolled_up_at": now,
                     "run_id": run_id}
            line = json.dumps(entry, sort_keys=True, separators=(",", ":"))
            out.write(line + "\n")
            prev = _sha(line.encode("utf-8"))
            print(f"appended seq={seq} {os.path.basename(src)}")
    return 0

def verify(chain):
    prev = "GENESIS"
    with open(chain, "rb") as f:
        for i, raw in enumerate(f, 1):
            stripped = raw.rstrip(b"\n")
            try:
                entry = json.loads(stripped)
            except Exception:
                print(f"INVALID: line {i} is not valid JSON (torn line?)")
                return 1
            if entry.get("prev_sha256") != prev or entry.get("seq") != i:
                print(f"INVALID: chain broken at line {i}")
                return 1
            prev = _sha(stripped)
    print("VALID: chain intact")
    return 0

def selftest():
    with tempfile.TemporaryDirectory() as d:
        chain = os.path.join(d, "receipt-chain.jsonl")
        srcs = []
        for name in ("a.json", "b.json"):
            p = os.path.join(d, name)
            with open(p, "w") as f:
                f.write('{"x":"' + name + '"}')
            srcs.append(p)
        append(chain, "selftest", srcs)
        if verify(chain) != 0:
            print("SELFTEST FAIL: fresh chain did not verify")
            return 1
        good = open(chain, encoding="utf-8").read()

        # Case 1: mutate a NON-final line (line 1 of 2). Detection comes
        # from line 2's prev_sha256 no longer matching; the final line
        # has no successor in-file (git anchors the head, see docstring).
        tampered = good.replace('"source_filename":"a.json"',
                                '"source_filename":"TAMPERED"')
        if tampered == good:
            print("SELFTEST FAIL: tamper target not found in chain")
            return 1
        open(chain, "w", encoding="utf-8").write(tampered)
        if verify(chain) == 0:
            print("SELFTEST FAIL: line-1 mutation not detected")
            return 1

        # Case 2: remove the first line; seq/link check must catch it.
        lines = good.splitlines(keepends=True)
        open(chain, "w", encoding="utf-8").write("".join(lines[1:]))
        if verify(chain) == 0:
            print("SELFTEST FAIL: line removal not detected")
            return 1

        print("SELFTEST OK: mutation and removal detected")
        return 0

def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("append")
    a.add_argument("--chain", required=True)
    a.add_argument("--run-id", required=True)
    a.add_argument("sources", nargs="+")
    v = sub.add_parser("verify")
    v.add_argument("--chain", required=True)
    sub.add_parser("selftest")
    ns = ap.parse_args()
    if ns.cmd == "append":
        sys.exit(append(ns.chain, ns.run_id, ns.sources))
    if ns.cmd == "verify":
        sys.exit(verify(ns.chain))
    sys.exit(selftest())

if __name__ == "__main__":
    main()
