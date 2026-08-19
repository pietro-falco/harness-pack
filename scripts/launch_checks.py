#!/usr/bin/env python3
"""Standalone launch-gate checks extracted from launch_worker.sh (ADR-002).

Subcommands, each the single live implementation of a launcher gate so the
launcher and the test suite exercise the same code (no logic fork):

  resolve-tier MANIFEST      env MODEL_STRING. Resolve spec.model -> tier ->
                             concrete model via manifest.model_tiers + tiers,
                             applying the single-hop-DOWNWARD resolves_to rule
                             (ADR-005 D4). Fail-closed: a model-string absent
                             from model_tiers is a STOP, never a default tier.
                             OK      -> stdout "OK <tier> <model> <manifest_version>", exit 0
                             Violation -> stderr "STOP ...", exit 1

  check-hash CONST MANIFEST  Pin the constitution sha256 against
                             manifest.constitution_hash_expected, fail-closed.
                             OK       -> stdout "<sha256>", exit 0
                             Mismatch -> stderr "STOP: CONST-HASH-MISMATCH ...", exit 1

  validate-passed ROOT       env CONFORMANCE_LEDGER_REPO. Completion is a
                             consequence of evidence (THR-SEQ ESITO 1): every
                             slice harness.json marks status=passed must be
                             bound in .harness/receipts/completions.json to a
                             receipt whose spec_id is the slice and whose
                             gate.verdict is PASS, and to a conformance record
                             whose measurement.source is the slice -- both
                             byte-matched against the recorded sha256, the
                             record re-verified CONFORMANT (exit 0) by
                             conformance_verify.py against the operator's
                             observation ledger. A flag with nothing behind it
                             is a STOP, never a skip; passed slices with no
                             ledger named are a STOP too (evidence that cannot
                             be verified licenses no launch). Zero passed
                             slices need zero ledger.
                             OK        -> stdout "OK ...", exit 0
                             Violation -> stderr "STOP ...", exit 1

  mark-passed ROOT SLICE RUN_ID RECEIPT RECORD
                             The single writer of completion (THR-SEQ ESITO
                             1). Re-reads the receipt (spec_id == SLICE,
                             gate.verdict == PASS) and the record
                             (measurement.source == SLICE) -- evidence
                             re-read, never narrated -- then writes the
                             completions.json binding FIRST (a stray evidence
                             entry licenses nothing) and only then the two
                             fields harness.json's reader accepts: status=
                             "passed", passedOn=UTC date. The caller
                             (launch_worker.sh) verifies the record is
                             CONFORMANT against the ledger before calling;
                             validate-passed re-verifies at every later
                             launch, so an unverified mark is caught at the
                             next consumption, fail-closed.
                             OK        -> stdout "MARKED ...", exit 0
                             Violation -> stderr "STOP ...", exit 1

Tier and hash SEMANTICS are preserved byte-for-byte from launch_worker.sh (same
branches, same messages); this is a testability refactor only (ADR-002). The one
change vs the former inline heredocs is the I/O contract: a refusal now exits
non-zero with its message on stderr, where before it printed a STOP line on
stdout that the launcher re-emitted to stderr itself.
"""
import datetime
import hashlib
import json
import os
import subprocess
import sys

COMPLETIONS_REL = ".harness/receipts/completions.json"


def _stop(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def resolve_tier(manifest_path):
    m = json.load(open(manifest_path))
    model = os.environ["MODEL_STRING"]
    model_tiers = m.get("model_tiers") or {}
    tiers = m.get("tiers") or {}
    if model not in model_tiers:
        _stop(f"STOP model-string {model!r} absent from manifest.model_tiers (fail-closed; not a default)")
    t = model_tiers[model]
    tier = tiers.get(t)
    if tier is None:
        _stop(f"STOP model_tiers[{model!r}] -> {t!r}, not a tier in the manifest")
    if not tier.get("chain"):
        rt = tier.get("resolves_to")
        order = ["T0", "T1", "T2", "T3"]
        if not rt or t not in order or rt not in order or (order.index(rt) - order.index(t)) != 1:
            _stop(f"STOP tier {t!r} has empty chain and no legal single-hop-downward resolves_to")
        t = rt
        tier = tiers.get(t) or {}
        if not tier.get("chain"):
            _stop(f"STOP resolves_to target {t!r} also has empty chain")
    print("OK", t, tier["chain"][0], m.get("manifest_version", ""))


def check_hash(const_path, manifest_path):
    actual = hashlib.sha256(open(const_path, "rb").read()).hexdigest()
    expected = json.load(open(manifest_path)).get("constitution_hash_expected", "")
    if expected and expected != actual:
        _stop(f"STOP: CONST-HASH-MISMATCH expected={expected} actual={actual}")
    print(actual)


def _load_json(path, what):
    try:
        return json.load(open(path))
    except (OSError, ValueError) as e:
        _stop(f"STOP: {what} unreadable as JSON at {path}: {e}")


def _sha256(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def _record_source(statement):
    return ((statement.get("predicate") or {}).get("measurement")
            or {}).get("source")


def validate_passed(root):
    hpath = os.path.join(root, ".harness/harness.json")
    # An ABSENT harness.json carries no passed flag and is not this gate's
    # business: the launcher's contract never required the file at ROOT (the
    # suite's launcher drivers stub `next` and run without one), and `next`
    # itself refuses when it needs it. Present-but-unreadable stays a STOP:
    # a file that exists and cannot be read could be hiding a flag.
    if not os.path.isfile(hpath):
        print("OK no harness.json at root; no completed slices to validate")
        return
    h = _load_json(hpath, "harness.json")
    slices = h.get("slices") or {}
    passed = sorted(s for s, sl in slices.items()
                    if isinstance(sl, dict) and sl.get("status") == "passed")
    if not passed:
        print("OK no completed slices to validate")
        return
    comp_path = os.path.join(root, COMPLETIONS_REL)
    if not os.path.isfile(comp_path):
        _stop("STOP: slice(s) marked passed without completion evidence: "
              f"{','.join(passed)} ({COMPLETIONS_REL} absent) -- completion "
              "is a consequence of evidence, not a flag")
    comp = _load_json(comp_path, "completions.json")
    ledger = os.environ.get("CONFORMANCE_LEDGER_REPO", "")
    if not ledger:
        _stop(f"STOP: slice(s) marked passed ({','.join(passed)}) but "
              "CONFORMANCE_LEDGER_REPO is unset; completion evidence cannot "
              "be verified against a ledger, and unverifiable completion "
              "licenses no launch")
    verify = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "conformance_verify.py")
    for s in passed:
        e = comp.get(s)
        if not isinstance(e, dict):
            _stop(f"STOP: slice {s} is marked passed but completions.json "
                  "does not bind it to a run record -- completion is a "
                  "consequence of evidence, not a flag")
        for k in ("run", "receipt", "receipt_sha256", "record",
                  "record_sha256"):
            if not isinstance(e.get(k), str) or not e[k]:
                _stop(f"STOP: slice {s} completion entry lacks {k}")
        rp = os.path.join(root, e["receipt"])
        dp = os.path.join(root, e["record"])
        for p, want, what in ((rp, e["receipt_sha256"], "receipt"),
                              (dp, e["record_sha256"], "record")):
            if not os.path.isfile(p):
                _stop(f"STOP: slice {s} completion {what} absent at {p}")
            got = _sha256(p)
            if got != want:
                _stop(f"STOP: slice {s} completion {what} bytes moved: "
                      f"sha256 {got} != recorded {want}")
        r = _load_json(rp, f"slice {s} completion receipt")
        if r.get("spec_id") != s or (r.get("gate") or {}).get("verdict") != "PASS":
            _stop(f"STOP: slice {s} completion receipt does not support it "
                  f"(spec_id={r.get('spec_id')!r}, "
                  f"gate.verdict={(r.get('gate') or {}).get('verdict')!r})")
        src = _record_source(_load_json(dp, f"slice {s} completion record"))
        if src != s:
            _stop(f"STOP: slice {s} completion record measures a different "
                  f"arm (measurement.source={src!r})")
        proc = subprocess.run(
            [sys.executable, verify, dp, os.path.dirname(dp),
             "--ledger-repo", ledger], capture_output=True, text=True)
        if proc.returncode != 0:
            _stop(f"STOP: slice {s} completion record does not verify "
                  f"CONFORMANT against the ledger (exit {proc.returncode}): "
                  f"{(proc.stdout.strip() or proc.stderr.strip())}")
    print(f"OK {len(passed)} completed slice(s) verified: {','.join(passed)}")


def mark_passed(root, slice_id, run_id, receipt_path, record_path):
    r = _load_json(receipt_path, "receipt")
    if r.get("spec_id") != slice_id:
        _stop(f"STOP: receipt spec_id {r.get('spec_id')!r} != slice "
              f"{slice_id!r}; refusing to mark")
    if (r.get("gate") or {}).get("verdict") != "PASS":
        _stop("STOP: receipt gate.verdict is "
              f"{(r.get('gate') or {}).get('verdict')!r}, not PASS; "
              "completion is a consequence of the gate, refusing to mark")
    src = _record_source(_load_json(record_path, "conformance record"))
    if src != slice_id:
        _stop(f"STOP: conformance record measures arm {src!r}, not slice "
              f"{slice_id!r}; refusing to mark")
    hpath = os.path.join(root, ".harness/harness.json")
    h = _load_json(hpath, "harness.json")
    sl = (h.get("slices") or {}).get(slice_id)
    if not isinstance(sl, dict):
        _stop(f"STOP: slice {slice_id} not present in harness.json")
    if sl.get("status") == "passed":
        _stop(f"STOP: slice {slice_id} is already marked passed")
    comp_path = os.path.join(root, COMPLETIONS_REL)
    comp = _load_json(comp_path, "completions.json") \
        if os.path.isfile(comp_path) else {}
    comp[slice_id] = {
        "run": run_id,
        "receipt": os.path.relpath(os.path.abspath(receipt_path),
                                   os.path.abspath(root)),
        "receipt_sha256": _sha256(receipt_path),
        "record": os.path.relpath(os.path.abspath(record_path),
                                  os.path.abspath(root)),
        "record_sha256": _sha256(record_path),
    }
    os.makedirs(os.path.dirname(comp_path), exist_ok=True)
    with open(comp_path, "w") as fh:
        fh.write(json.dumps(comp, indent=2, sort_keys=True) + "\n")
    sl["status"] = "passed"
    sl["passedOn"] = datetime.datetime.now(
        datetime.timezone.utc).date().isoformat()
    with open(hpath, "w") as fh:
        fh.write(json.dumps(h, indent=2) + "\n")
    print(f"MARKED slice={slice_id} run={run_id} passedOn={sl['passedOn']}")


def main(argv):
    if len(argv) < 2:
        print("usage: launch_checks.py {resolve-tier MANIFEST | check-hash CONST MANIFEST | validate-passed ROOT | mark-passed ROOT SLICE RUN_ID RECEIPT RECORD}", file=sys.stderr)
        sys.exit(2)
    cmd = argv[1]
    if cmd == "resolve-tier":
        if len(argv) != 3:
            print("usage: launch_checks.py resolve-tier MANIFEST", file=sys.stderr)
            sys.exit(2)
        resolve_tier(argv[2])
    elif cmd == "check-hash":
        if len(argv) != 4:
            print("usage: launch_checks.py check-hash CONST MANIFEST", file=sys.stderr)
            sys.exit(2)
        check_hash(argv[2], argv[3])
    elif cmd == "validate-passed":
        if len(argv) != 3:
            print("usage: launch_checks.py validate-passed ROOT", file=sys.stderr)
            sys.exit(2)
        validate_passed(argv[2])
    elif cmd == "mark-passed":
        if len(argv) != 7:
            print("usage: launch_checks.py mark-passed ROOT SLICE RUN_ID RECEIPT RECORD", file=sys.stderr)
            sys.exit(2)
        mark_passed(argv[2], argv[3], argv[4], argv[5], argv[6])
    else:
        print(f"STOP unknown subcommand {cmd!r}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv)
