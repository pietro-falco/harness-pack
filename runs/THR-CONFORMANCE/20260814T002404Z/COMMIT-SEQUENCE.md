# Emitted commit sequence — THR-CONFORMANCE 20260814T002404Z

Operator-executed, one logical unit per commit, explicit paths, never -A,
never --no-verify. Yesterday's THR-SUBAGENT sequence (its FINDINGS.md)
lands FIRST: today's P0 repairs live inside files that sequence already
names (the nine SC2015 fixture repairs, the reformulated
tests/fixtures/detect.py, the revised docs/adrs/ADR-023-*.md), so they
ride in with it — no extra commit is needed for P0.

```
git add -- docs/adrs/ADR-024-the-absence-of-declaration-is-not-conformity.md
git commit -m "docs(adr): propose ADR-024 — the absence of declaration is not conformity"

git add -- scripts/conformance_record.py scripts/conformance_verify.py scripts/conformance_rule_v1.json scripts/conformance_dump.py scripts/conformance_narrow.py scripts/conformance_watch.py
git commit -m "feat(conformance): record builder, independent verifier, rule-as-data, dump/narrow/watch consumers"

git add -- tests/fixtures/conformance_corpus.py tests/bypass_ft_out_of_surface_call_undetected_fixture.sh tests/bypass_ft_record_without_declaration_fixture.sh tests/bypass_ft_depth_collapse_fixture.sh tests/bypass_ft_narration_only_evidence_fixture.sh tests/bypass_ft_stream_truncated_fixture.sh tests/bypass_ft_replay_nondeterminism_fixture.sh tests/bypass_ft_unused_authorization_unreported_fixture.sh tests/bypass_ft_monitor_blind_while_running_fixture.sh tests/run_tests.sh
git commit -m "test(conformance): synthetic corpus and FT-20..FT-27, each observed failing and in declared state"

git add -- runs/THR-CONFORMANCE/20260814T002404Z
git commit -m "docs(run): THR-CONFORMANCE evidence record — real-arm Statements, falsification pass, P1 survey"

# Second half of the two-commit cycle, AFTER the operator accepts:
# replace the Proposed text with adr/ADR-024.accepted.md unchanged except
# status field and Ratification section, then:
git add -- docs/adrs/ADR-024-the-absence-of-declaration-is-not-conformity.md
git commit -m "docs(adr): accept ADR-024 — implementation and evidence in-tree"
```

Note: `scripts/launch_worker.sh` and
`docs/adrs/ADR-022-the-tool-list-must-bind-not-preapprove.md` carry
working-tree modifications that predate this thread; they are NOT in this
sequence and were not touched by it.
