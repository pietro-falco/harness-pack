#!/usr/bin/env python3
"""receipts-index.jsonl writer, co-indexing gate, and backfill (ADR-005 D2/D3).

Append-only per-run projection, co-indexed to receipt-chain.jsonl by seq.
The chain (receipt_chain.py) and its format are UNCHANGED (ADR-005 non-goal);
this index is purely additive, written by the RS-001 rollup as a separate
step (R2b) over the SAME lexicographic R1 snapshot, in the same order.

Privacy (ADR-005 D5): this tracked tool embeds NO model id. It reads
model_used from receipts at runtime and writes to the gitignored index.

Independence: `append` hashes the source bytes ITSELF and never reads the
chain, so `gate` is a real cross-check between two independent producers,
not a tautology. seq derives from the index tail alone.

Invariants asserted by `gate` (RS-001 V8):
  len(index) == len(chain)
  index[i].seq            == chain[i].seq              for all i
  index[i].source_sha256  == chain[i].sha256           for all i
  index[i].source_filename == chain[i].source_filename (belt-and-braces)

Schema tolerance (ADR-005 D4): distilled fields read via .get() -> null when
absent. `type` has no source in any current receipt shape (it is a SPEC field,
per templates/spec.mode-b.template.md, not copied into the receipt), so it is
structurally null until launch_worker.sh is extended (separate slice). A
receipt whose JSON is unreadable still gets a faithful line (seq/filename/sha
from bytes; distilled fields null; subtype="unreadable") so the index never
desyncs from the chain.

Commands:
  append   --index FILE SOURCE [SOURCE...]         append one distilled line per SOURCE
  gate     --index FILE --chain FILE               co-indexing assertion (exit 0/1)
  backfill --index FILE --chain FILE --archive DIR reconstruct a FRESH index from an
                                                   existing chain + archived receipts;
                                                   fail-closed on sha mismatch (tamper)
  selftest
"""
import argparse, hashlib, json, os, sys, tempfile, subprocess


def _sha_file(path) -> str:
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def _count_lines(path) -> int:
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return 0
    n = 0
    with open(path, "rb") as f:
        for raw in f:
            if raw.strip():
                n += 1
    return n


def _gate_verdict(r):
    gv = r.get("gate_verdict")
    if gv is not None:
        return gv
    gate = r.get("gate")
    if isinstance(gate, dict):
        return gate.get("verdict")
    return None


def _load_receipt(path):
    try:
        with open(path, "rb") as f:
            r = json.loads(f.read())
        return r if isinstance(r, dict) else {"subtype": "unreadable"}
    except Exception:
        return {"subtype": "unreadable"}


# The distilled fields named by ADR-005 D2. Single source of truth for a line.
def distill(seq, src_path, receipt, source_sha256=None):
    r = receipt if isinstance(receipt, dict) else {}
    return {
        "seq": seq,
        "run_id": r.get("run_id"),
        "spec_id": r.get("spec_id"),
        "type": r.get("type"),                       # STRUCTURAL null (spec field, not in receipt)
        "mode": r.get("mode"),
        "model_string": r.get("model_string"),       # null for old-form receipts (D4)
        "tier_resolved": r.get("tier_resolved"),
        "model_used": r.get("model_used"),
        "subtype": r.get("subtype"),
        "num_turns": r.get("num_turns"),
        "total_cost_usd": r.get("total_cost_usd"),   # nullable (D2: absent on keyless auth)
        "duration_ms": r.get("duration_ms"),         # nullable (D2)
        "started_at": r.get("started_at"),
        "ended_at": r.get("ended_at"),
        "stop_reason": r.get("stop_reason"),
        "gate_verdict": _gate_verdict(r),
        "constitution_hash": r.get("constitution_hash"),
        "manifest_version": r.get("manifest_version"),
        "source_filename": os.path.basename(src_path),
        "source_sha256": source_sha256 if source_sha256 is not None else _sha_file(src_path),
    }


def _emit(out, entry):
    out.write(json.dumps(entry, sort_keys=True, separators=(",", ":")) + "\n")


def append(index, sources):
    seq = _count_lines(index)
    with open(index, "a", encoding="utf-8") as out:
        for src in sources:
            seq += 1
            _emit(out, distill(seq, src, _load_receipt(src)))
            print(f"indexed seq={seq} {os.path.basename(src)}")
    return 0


def _read_jsonl(path):
    rows = []
    with open(path, "rb") as f:
        for i, raw in enumerate(f, 1):
            stripped = raw.rstrip(b"\n")
            if not stripped.strip():
                continue
            try:
                rows.append(json.loads(stripped))
            except Exception:
                print(f"INVALID: {os.path.basename(path)} line {i} not valid JSON (torn line?)")
                return None
    return rows


def gate(index, chain):
    idx = _read_jsonl(index)
    chn = _read_jsonl(chain)
    if idx is None or chn is None:
        return 1
    if len(idx) != len(chn):
        print(f"INVALID: length delta index={len(idx)} chain={len(chn)}")
        return 1
    for i, (a, b) in enumerate(zip(idx, chn), 1):
        if a.get("seq") != b.get("seq"):
            print(f"INVALID: seq mismatch at line {i}: index={a.get('seq')} chain={b.get('seq')}")
            return 1
        if a.get("source_sha256") != b.get("sha256"):
            print(f"INVALID: source_sha256 mismatch at line {i} (seq={a.get('seq')})")
            return 1
        if a.get("source_filename") != b.get("source_filename"):
            print(f"INVALID: source_filename mismatch at line {i} (seq={a.get('seq')})")
            return 1
    print(f"VALID: index co-indexed to chain ({len(idx)} lines)")
    return 0


def backfill(index, chain, archive):
    """Reconstruct a FRESH index from an existing chain + archived receipts.
    One-time migration for turning the index on against a non-empty chain.
    Refuses if the index already has lines. Fail-closed if an archived receipt
    is missing or its bytes no longer hash to the chain's recorded sha256."""
    if _count_lines(index) != 0:
        print("STOP: index is not empty; backfill only reconstructs a fresh index")
        return 1
    chn = _read_jsonl(chain)
    if chn is None:
        return 1
    with open(index, "a", encoding="utf-8") as out:
        for b in chn:
            fn = b.get("source_filename")
            src = os.path.join(archive, fn) if fn else None
            if not src or not os.path.exists(src):
                print(f"STOP: archived receipt not found for seq={b.get('seq')}: {fn}")
                return 1
            actual = _sha_file(src)
            if actual != b.get("sha256"):
                print(f"STOP: sha mismatch (tamper?) seq={b.get('seq')} {fn}")
                return 1
            _emit(out, distill(b.get("seq"), src, _load_receipt(src), source_sha256=actual))
            print(f"backfilled seq={b.get('seq')} {fn}")
    return gate(index, chain)


def selftest():
    here = os.path.dirname(os.path.abspath(__file__))
    chain_py = os.path.join(here, "receipt_chain.py")
    with tempfile.TemporaryDirectory() as d:
        shape1 = {"run_id": "run-A", "spec_id": "S-VI-001", "mode": "B",
                  "model_string": "executor", "tier_resolved": "T2",
                  "model_used": "SONNET_CLASS_MODEL", "manifest_version": 1,
                  "constitution_hash": "abc", "started_at": "t0", "ended_at": "t1",
                  "subtype": "success", "num_turns": 5, "total_cost_usd": None,
                  "duration_ms": None, "session_id": "s1",
                  "gate": {"verdict": "PASS", "reason": "", "verity_exit": 0},
                  "stop_reason": "gate-pass", "claims": []}
        shape2 = {"run_id": "run-B", "spec_id": "S-VI-002", "mode": "B",
                  "tier_requested": "T2", "tier_resolved": "T2",
                  "model_used": "SONNET_CLASS_MODEL", "manifest_version": 1,
                  "constitution_hash": "def", "started_at": "t2", "ended_at": "t3",
                  "subtype": "success", "num_turns": 7, "total_cost_usd": 0.12,
                  "duration_ms": 4000, "session_id": "s2",
                  "stop_reason": "cc_exit=0", "claims": []}
        srcs = []
        for name, obj in (("run-2026A.receipt.json", shape1),
                          ("run-2026B.receipt.json", shape2)):
            p = os.path.join(d, name)
            with open(p, "w") as f:
                json.dump(obj, f, indent=1)
            srcs.append(p)
        corrupt = os.path.join(d, "run-2026C.receipt.json")
        with open(corrupt, "w") as f:
            f.write("{ this is not valid json ")
        srcs.append(corrupt)

        chain = os.path.join(d, "receipt-chain.jsonl")
        index = os.path.join(d, "receipts-index.jsonl")

        rc = subprocess.run([sys.executable, chain_py, "append",
                             "--chain", chain, "--run-id", "rollup-selftest", *srcs])
        if rc.returncode != 0:
            print("SELFTEST FAIL: chain append errored"); return 1
        if append(index, srcs) != 0:
            print("SELFTEST FAIL: index append errored"); return 1

        if gate(index, chain) != 0:
            print("SELFTEST FAIL: gate did not pass on co-indexed files"); return 1
        good_index = open(index, encoding="utf-8").read()

        # sha mutation -> FAIL
        lines = good_index.splitlines(keepends=True)
        o0 = json.loads(lines[0]); o0["source_sha256"] = "0" * 64
        lines[0] = json.dumps(o0, sort_keys=True, separators=(",", ":")) + "\n"
        open(index, "w").write("".join(lines))
        if gate(index, chain) == 0:
            print("SELFTEST FAIL: sha drift not detected"); return 1

        # line drop -> FAIL
        open(index, "w").write("".join(good_index.splitlines(keepends=True)[1:]))
        if gate(index, chain) == 0:
            print("SELFTEST FAIL: line-drop drift not detected"); return 1

        # reorder -> FAIL
        gl = good_index.splitlines(keepends=True); gl[0], gl[1] = gl[1], gl[0]
        open(index, "w").write("".join(gl))
        if gate(index, chain) == 0:
            print("SELFTEST FAIL: reorder drift not detected"); return 1

        # corrupt receipt stayed co-indexed
        open(index, "w").write(good_index)
        c_row = _read_jsonl(index)[2]
        if c_row.get("subtype") != "unreadable" or not c_row.get("source_sha256") or c_row.get("seq") != 3:
            print("SELFTEST FAIL: corrupt receipt not faithfully co-indexed"); return 1

        # backfill: archive the sources, wipe the index, reconstruct from chain+archive -> gate PASS
        archive = os.path.join(d, "archive"); os.makedirs(archive)
        for p in srcs:
            os.rename(p, os.path.join(archive, os.path.basename(p)))
        os.remove(index)
        open(index, "w").close()
        if backfill(index, chain, archive) != 0:
            print("SELFTEST FAIL: backfill did not reconstruct a co-indexed index"); return 1

        # backfill tamper: mutate one archived receipt -> backfill FAILS on sha mismatch
        os.remove(index); open(index, "w").close()
        tampered = os.path.join(archive, "run-2026A.receipt.json")
        with open(tampered, "a") as f:
            f.write("\n")  # one byte changes the sha
        if backfill(index, chain, archive) == 0:
            print("SELFTEST FAIL: backfill did not detect tampered archived receipt"); return 1

        print("SELFTEST OK: co-indexing holds; gate fails on sha/drop/reorder; "
              "corrupt receipt stays co-indexed; backfill reconstructs and "
              "fails closed on tamper")
        return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("append"); a.add_argument("--index", required=True); a.add_argument("sources", nargs="+")
    g = sub.add_parser("gate"); g.add_argument("--index", required=True); g.add_argument("--chain", required=True)
    b = sub.add_parser("backfill"); b.add_argument("--index", required=True); b.add_argument("--chain", required=True); b.add_argument("--archive", required=True)
    sub.add_parser("selftest")
    ns = ap.parse_args()
    if ns.cmd == "append":
        sys.exit(append(ns.index, ns.sources))
    if ns.cmd == "gate":
        sys.exit(gate(ns.index, ns.chain))
    if ns.cmd == "backfill":
        sys.exit(backfill(ns.index, ns.chain, ns.archive))
    sys.exit(selftest())


if __name__ == "__main__":
    main()
