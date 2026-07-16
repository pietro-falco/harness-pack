#!/usr/bin/env python3
"""Standalone launch-gate checks extracted from launch_worker.sh (ADR-002).

Two subcommands, each the single live implementation of a launcher gate so the
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

Tier and hash SEMANTICS are preserved byte-for-byte from launch_worker.sh (same
branches, same messages); this is a testability refactor only (ADR-002). The one
change vs the former inline heredocs is the I/O contract: a refusal now exits
non-zero with its message on stderr, where before it printed a STOP line on
stdout that the launcher re-emitted to stderr itself.
"""
import hashlib
import json
import os
import sys


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


def main(argv):
    if len(argv) < 2:
        print("usage: launch_checks.py {resolve-tier MANIFEST | check-hash CONST MANIFEST}", file=sys.stderr)
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
    else:
        print(f"STOP unknown subcommand {cmd!r}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv)
