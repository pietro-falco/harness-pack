# THR-CONFORMANCE run state — 20260814T002404Z

## Cursor

PHASE: complete through P4. HARD STOP before P5 (mode format is the
operator's product decision — ADR-024 OR-4).
NEXT: operator actions only — (1) execute yesterday's THR-SUBAGENT commit
sequence, then this run's COMMIT-SEQUENCE.md; (2) apply
gate-tracker-delta.md by hand; (3) push (clears GATE-3); (4) decide
ADR-024 acceptance (second commit from adr/ADR-024.accepted.md);
(5) decide the P5 mode format to unlock that phase.

## Closed this run

- GATE: exit 1 RED by design, 6 facts classified (GATE.txt) — none abort.
  Measurement pin: claude 2.1.232.
- P0a: shellcheck pin reconciled by INSTALLING the pinned 0.9.0 darwin
  binary (sha256 == declaration); nine SC2015 repairs; pinned gate exit 0.
  ADR-023 OR-3 discharged. Pin unchanged.
- P0b: doctrine fixed as ADR-023 D6 (membership from ABSENCE of runtime
  error, never presence of emission); two-axis detector reformulated
  (pool_membership reading, unresolved counted, never dropped).
- P0c: A7 downgraded DIVERGENT -> NOT MEASURED (premise absent and
  unattainable from the sandbox); ADR-023 A7 bullet + OR-4 revised;
  accepted copy regenerated. Yesterday's FINDINGS/RESULT untouched.
- P1: seven sources read with citations (P1-surface-survey.md). No
  existing declared-vs-exercised conformance format; in-toto layout has
  the shape on the wrong vocabulary; envelope adopted, predicate new.
- P2: conformance-record/v1 Statement — resolved surface, delegation tree
  from parent_tool_use_id, per-call depth + D6 readings, rule-as-data by
  id+digest, closed vocabulary, canonical form. Builder + INDEPENDENT
  verifier (exits 0/1/2; 2 never a pass). Three real-arm records (A8, A3,
  A2fg) verify CONFORMANT beside their evidence.
- P3: unusedAuthorizations required and recomputed; narrowing-proposal/v1
  emitted from records (A3: drop Read), digest-chained, never applied.
- P4: verify + watch + dump. Watch extends the gate state-line contract in
  conformance.state (oos shown in 53–112ms, declared 300ms). Dump is the
  second trivial consumer proving the record is the API.
- Fixtures FT-20..FT-27: all eight observed GREEN in declared state AND
  RED against sabotaged stubs (fixture-falsification.txt). Registered;
  suite red ONLY on register completeness (untracked until commits land).
  Verity 12/12 PASS.
- ADR-024 emitted both ways (proposed on disk, accepted in adr/), not
  committed.

## Evidence map

GATE.txt · P1-surface-survey.md · records/{A8,A3,A2fg}.{statement,dump,
narrowing} · fixture-falsification.txt · COMMIT-SEQUENCE.md ·
gate-tracker-delta.md · ASSUMPTIONS.md · adr/ADR-024.accepted.md
