#!/usr/bin/env python3
"""Standalone receipt writer extracted from launch_worker.sh (ADR-010).

Same move ADR-002 made for the two launch gates, for the same reason: the
receipt writer lived as an inline unquoted heredoc at launch_worker.sh:362-441
and could only be reached by driving the whole launcher, which fails closed on
`next --json` long before it composes anything. ADR-010's Verification asks two
fixtures to feed a constructed `cc.json` to "the receipt writer"; there was no
such thing to feed. There is now, and there is no logic fork -- the launcher
and the fixtures run this file.

  write_receipt.py CC_JSON OUT_JSON

CC_JSON is the child's `claude -p --output-format json` capture; OUT_JSON is
the receipt path. Everything the heredoc used to receive by shell interpolation
now arrives as an environment variable:

  CC_EXIT             the child's exit status (integer string)
  GATE_JSON           the t1 measurement, as measure_criteria emits it
  BASELINE_JSON       the t0 measurement, same shape
  RUN_ID SPEC_ID MODEL_STRING TIER_RESOLVED MODEL_USED MANIFEST_VERSION
  CONSTITUTION_HASH TOOL_VERSION STARTED_AT ENDED_AT

The composition SEMANTICS are preserved byte-for-byte from the heredoc: the
same branches, the same stop_reason labels, the same contribution arithmetic,
the same key order in the emitted object, the same `indent=1`, the same
"receipt: <path>" line on stdout. Only the I/O contract changed -- shell
interpolation into a Python string literal became an environment read, which is
the same substitution ADR-002 D2 made and is strictly safer for values carrying
a quote or a backslash.

The extraction composes exactly what the heredoc composed -- asserted by output
equivalence over every branch, not by inspection, and recorded under
.verity/evidence/2026-08-10-adr010-first-red/. ADR-010 D1's `refusals` object
then lands on top of it, marked at its site. It is the one semantic change in
this file, and the fixture that was red without it ran first, against the
extraction alone, in this same commit.
"""
import json, os, sys


def compose(cc, gate, baseline, cc_exit, env):
    if cc_exit != 0:
        stop_reason = "cc_exit=%d" % cc_exit
        claims = []
        gate_summary = {"verdict": "not-run", "reason": "CC did not exit 0; gate skipped"}
    else:
        v = gate.get("verdict", "NO-VERDICT")
        label = {"PASS": "gate-pass", "FAIL": "gate-fail", "STOP": "gate-stop", "NO-VERDICT": "gate-no-verdict"}.get(v, "gate-" + str(v).lower())
        stop_reason = label if v == "PASS" else label + ": " + gate.get("reason", "")
        claims = gate.get("claims", [])
        gate_summary = {"verdict": v, "reason": gate.get("reason", ""), "verity_exit": gate.get("verity_exit")}

    # contribution (ADR-008 D3, 0008:72-84). The delta between t0 and t1: 0008:41,
    # "the set of declared criteria whose verdict moved from FAIL or ABSENT at the
    # earlier point to PASS at the later one".
    #   phase        always working-tree-advisory in a launcher-written receipt
    #                (0008:86) -- the t0-to-t1 pair, never inferred by the reader.
    #   baseline     the item-level verdict table at t0, persisted here because it
    #                is not regenerable (0008:87). Its roll-up verdict follows the
    #                shape 0008:74-80 illustrates -- FAIL beside a claims table
    #                holding an ABSENT -- so it is all-PASS or FAIL, not the
    #                acquiring filter's gate-acceptance word.
    #   regressions  diagnostic only (0008:88); it never becomes a second
    #                acceptance authority.
    #   verdict      the total function of 0008:89: CONTRIBUTED when delta is
    #                non-empty, NO_OP when it is empty, NOT_EVALUATED when and only
    #                when the run stopped before the gate produced any verdict --
    #                the cross-field invariant being that NOT_EVALUATED holds if and
    #                only if the gate has no verdict. With no t1 there is no later
    #                point, so delta and regressions are empty rather than guessed.
    # The heredoc this came from was unquoted, so a backtick pair in these comments
    # was a live command substitution and quotations had to be written in plain
    # words. The extraction lifts that constraint; the wording is left as it was
    # written, because rewriting it would be a change this commit did not measure.
    b_claims = baseline.get("claims", []) or []
    b_verdict = "PASS" if b_claims and all(c.get("verdict") == "PASS" for c in b_claims) else "FAIL"
    gate_has_verdict = gate_summary.get("verdict") in ("PASS", "FAIL", "STOP")
    t1 = {c.get("id"): c.get("verdict") for c in claims}
    if gate_has_verdict:
        delta = [c["id"] for c in b_claims
                 if c.get("verdict") in ("FAIL", "ABSENT") and t1.get(c.get("id")) == "PASS"]
        regressions = [c["id"] for c in b_claims
                       if c.get("verdict") == "PASS" and t1.get(c.get("id")) != "PASS"]
        contribution_verdict = "CONTRIBUTED" if delta else "NO_OP"
    else:
        delta, regressions, contribution_verdict = [], [], "NOT_EVALUATED"
    contribution = {
      "phase": "working-tree-advisory",
      "baseline": {"verdict": b_verdict, "claims": b_claims},
      "delta": delta,
      "regressions": regressions,
      "verdict": contribution_verdict
    }

    # refusals (ADR-010 D1). The child already hands the parent this array and the
    # writer used to discard it; nothing new is acquired here. `count` is the
    # array's length, `denials` is the array as received and unmodified, and the
    # object is ALWAYS present -- on a clean run it is count 0 and empty lists,
    # because "an absent field and a zero field are the same to a reader who has
    # to guess" (ADR-010:112).
    #
    # D2: this records THAT calls were refused, never BY WHAT. A denial entry is
    # produced identically by the PreToolUse hook and by a declarative deny rule in
    # the settings layer, and templates/settings.mode-b.json deliberately runs both,
    # so the parent structurally cannot tell them apart. No `G3-BLOCKED`, no naming
    # of the guard, and no `violation_code` is written from here.
    #
    # ORDERING RULE for `tools`: sorted lexicographically over the deduplicated
    # names, and never a bare set(). The receipt is hashed into the append-only
    # chain (scripts/receipt_chain.py), so an unstable member order would give two
    # otherwise identical runs two different digests -- and Python's string hashing
    # is seed-randomised per process, which is exactly the instability a hash chain
    # must not inherit. Sorted is the rule, not an incidental property of how this
    # happens to be written.
    #
    # A cc.json the writer could not read arrives here as the `error_no_output`
    # stub built in main(), which carries no `permission_denials`, so this yields
    # count 0 for a run whose child output is unknown -- i.e. it says "nothing was
    # refused" about a run nothing is known about. That is D1 applied literally
    # (count is the array's length; an absent array has length 0) and it is carried
    # as an open item rather than repaired by inventing a fourth state here, which
    # would be a decision this ADR did not make.
    denials = cc.get("permission_denials") or []
    if not isinstance(denials, list):
        denials = []
    tools = sorted({d["tool_name"] for d in denials
                    if isinstance(d, dict) and isinstance(d.get("tool_name"), str)})
    refusals = {"count": len(denials), "tools": tools, "denials": denials}

    return {
      "run_id": env["RUN_ID"], "spec_id": env["SPEC_ID"], "mode": "B",
      "model_string": env["MODEL_STRING"], "tier_resolved": env["TIER_RESOLVED"],
      "model_used": env["MODEL_USED"], "manifest_version": int(env["MANIFEST_VERSION"]),
      "constitution_hash": env["CONSTITUTION_HASH"], "tool_version": env["TOOL_VERSION"],
      "started_at": env["STARTED_AT"], "ended_at": env["ENDED_AT"],
      "subtype": cc.get("subtype","unknown"),
      "num_turns": cc.get("num_turns", -1),
      "total_cost_usd": cc.get("total_cost_usd"),
      "duration_ms": cc.get("duration_ms"),
      "session_id": cc.get("session_id",""),
      "gate": gate_summary,
      "contribution": contribution,
      "refusals": refusals,
      "retries": 0,
      "stop_reason": stop_reason,
      "claims": claims
    }


def main(argv):
    if len(argv) != 3:
        print("usage: write_receipt.py CC_JSON OUT_JSON", file=sys.stderr)
        return 2
    try:
        cc = json.load(open(argv[1]))
    except Exception:
        cc = {"subtype": "error_no_output"}
    gate = json.loads(os.environ.get("GATE_JSON") or "{}") or {}
    baseline = json.loads(os.environ.get("BASELINE_JSON") or "{}") or {}
    cc_exit = int(os.environ["CC_EXIT"])
    receipt = compose(cc, gate, baseline, cc_exit, os.environ)
    json.dump(receipt, open(argv[2], "w"), indent=1)
    print("receipt:", argv[2])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
