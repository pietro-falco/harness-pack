# THR-SUBAGENT run state — 20260813T194853Z

## Cursor

PHASE: complete
NEXT: nothing — operator actions only: (1) apply
tests/fixtures/gate-scope-argument.diff to the vault gate by hand
(80-governance is human-write-exclusive), (2) execute the emitted commit
sequence in FINDINGS.md, (3) apply the tracker delta (FINDINGS.md, one
edit), (4) copy emitter/emit_agents.mjs to
harnesswright/scripts/emit_agents.mjs (sandbox could not write there),
(5) second ADR commit from adr/ADR-023.accepted.md.

## Verdict summary

- A8 positive control: CONFORME (both markers, detectors agree) — apparatus
  measures; commit 3 unlocked.
- Central question: the background subagent filter INTERSECTS the inherited
  --tools pool; it does not replace it. Child tools field is subset-only at
  depth 1 and 2, foreground and background.
- A5: parent permission mode prevails (doc confirmed). A6: memory "project"
  = <cwd>/.claude/agent-memory/<agent>/. A7: DIVERGENTE — skills field
  inert on this build. C2: --append-subagent-system-prompt reaches depth 2
  (token c34e557bb6d8ab0d), negative control clean. C2b: HARNESS_SCOPE
  depth-transparent; SubagentStart fires but is depth-blind; report marker
  = agentId+usage block.
- Emitter: seven static refusals all observed; CLI accepts malformed
  --agents silently (FT-19 RED).
- Fixtures FT-5..FT-19 on disk, registered (15 rows), all 43 register rows
  ok; suite red ONLY on register completeness (fixtures untracked until the
  emitted commits land). Verity 12/12 PASS.

Everything else: RESULT.json (machine), FINDINGS.md (evidence record).
