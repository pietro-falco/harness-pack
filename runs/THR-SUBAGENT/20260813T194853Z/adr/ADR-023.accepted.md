---
status: accepted
date: 2026-08-13
accepted: 2026-08-14
decision-makers: operator
---

# ADR-023 — the subagent surface is measured, not inherited by declaration

Closes ADR-022 OR-4. Thesis: the tool surface of a subagent is a measured
fact, not a property a declaration confers; and the parent's permission mode
prevails over anything the child declares. A spec can therefore declare a
subagent-spawning run as bounded only because the bound was measured on the
CLI that will run it, and because the emitter refuses any definition that
steps outside the declared subset — which keeps the declaration accurate even
where runtime semantics move.

## Context

ADR-022 established that `--tools` removes and `--allowedTools` pre-approves,
and left OR-4 open: whether the bound reaches tools obtained through the
Agent tool was untested, so no spec could declare a subagent-spawning run as
bounded. The documentation composes `--tools`, `--allowedTools`, `--agents`
`tools`/`permissionMode`/`memory`/`skills` without stating whether the filter
applied to background subagents intersects the inherited pool or replaces it.

THR-SUBAGENT run 20260813T194853Z (harness-pack `runs/THR-SUBAGENT/`,
RESULT.json) measured it on claude 2.1.231, arm model sonnet, with two
independent detectors — content-pinned disk markers, and the stream plus
whatever transcripts exist — required to agree before any verdict. The
positive control (A8: Bash in both `--tools` and `--allowedTools`) produced
both markers; every arm was measured; detectors agreed on every arm.

Measured, each with an arm to its name:

- **A1 fg/bg** — a child with no `tools` field inherits the parent's
  restricted pool. No Bash tool_use possible when the parent pool lacks it.
- **A2 fg/bg** — a child `tools` field naming Bash outside the parent pool
  does NOT widen it. The model can still emit the tool_use; the runtime
  rejects it: "No such tool available: Bash. Bash is disabled for this
  session, in subagents as well as here." Emission and execution are
  different facts, which is why the apparatus measures both.
- **A1bg/A2bg** — the background filter INTERSECTS the inherited pool; it
  does not replace it. This was the ambiguity; it is now a measurement.
- **A3** — the same subset semantics hold at depth 2.
- **A4** — the default configuration (no `--tools`, builtin general-purpose)
  exposes Bash, as its `Tools: *` declaration says.
- **A5** — parent `acceptEdits`, child `permissionMode: "default"`, no
  allowlist: the child's Write executed. The parent's mode governs; the
  child's declaration does not reintroduce prompting. The doc claim holds.
- **A6** — `memory: "project"` writes under `<cwd>/.claude/agent-memory/
  <agent-name>/` and nowhere under `~/.claude`. The path is declarable.
- **A7** — NOT MEASURED (downgraded 2026-08-14 from DIVERGENT): the arm's
  premise — a vault skill symlinked into `~/.claude/skills` — did not hold
  when the arm ran (`graphify` is a plain directory there, no symlink
  present), and the session sandbox write-denies `~/.claude/skills`, so the
  premise could not be established for a re-measure. The observation stands
  as recorded (child reported CLAIM-SKILL-ABSENT; zero body strings in the
  stream), but an outcome on a false premise is not a divergence from
  documentation. A spec still must not promise skill delivery through this
  field until a run with the premise valid measures it.
- **C2** — `--append-subagent-system-prompt` reaches depth 2: a 16-hex token
  present only in the flag text named the marker the depth-2 leaf wrote
  (`c34e557bb6d8ab0d.marker`); the negative control without the flag produced
  `control.marker` with the token nowhere. Doc floor v2.1.205; measured on
  2.1.231, 2026-08-13.
- **C2b** — `$HARNESS_SCOPE` survives into PreToolUse hooks fired inside
  subagents at depth 1 and 2 (GUARD-SCOPE is depth-transparent);
  SubagentStart fires per spawn but its payload carries no depth field (the
  ledger is depth-blind, held RED by FT-9); the subagent report marker is the
  appended `agentId: <id> … <usage>` block, recorded as a signal.
- **Gate divergence** — `claude` does not reject a malformed `--agents`
  value; it ignores it silently and runs (exit 0). The CLI is not a
  validation gate. FT-19 stands RED to hold that visible.

## Decision

**D1 — the declared surface is the subset, and the subset is checked at
emission time.** The harnesswright emitter (emission target
`harnesswright/scripts/emit_agents.mjs`; measured copy frozen at
`tests/fixtures/emit_agents.mjs`) refuses, with a distinct non-zero exit per
defect: agent tools not a subset of the declared parent pool; any key outside
the sixteen documented `--agents` keys; Agent pooled with no declared
`max_spawn_depth`; `memory` without an explicit declaration carrying a path;
`skills` outside a declared allowlist; a tools list resolving to zero tools;
a parenthesized deny rule where the bare-name form is required.

**D2 — resolution order is deny first, then tools on the residue.** A tool
named in both lists is removed. FT-18 asserts the emitted surface.

**D3 — the emitter's precondition is machine-read.** It refuses to emit
unless RESULT.json shows the positive control CONFORME with both markers.
An apparatus that measured nothing licenses nothing.

**D4 — no runtime re-check is required on this CLI.** The subset check makes
the declaration accurate regardless of runtime semantics; the arms decide
only whether a runtime check is ALSO needed. On 2.1.231 they measured
subset-only composition at depth 1 and 2, foreground and background, so none
is. A CLI upgrade re-runs the arms by procedure (same declared hole as
ADR-022 OR-3).

**D5 — permission precedence is modeled as measured.** The emitter treats a
child `permissionMode` as advisory metadata: the parent's mode governs at
runtime (A5), so a spec that needs a stricter child than its parent is
rejected as unrepresentable rather than emitted as a false promise.

**D6 — pool membership is read from the absence of the runtime error, never
from the presence of the emission.** A2fg/A2bg falsified the assumption that
a model cannot emit a tool_use for a tool it does not possess: the emission
happened and the runtime rejected it ("No such tool available: …"). An
emitted call therefore proves nothing about the pool; only its paired result
does. Three readings: in-pool (≥1 emitted call with a non-error result),
out-of-pool (≥1 emission, every paired result an error), unobserved (no
emission — absence of evidence, not evidence of absence). An emitted call
with no paired result is unresolved: recorded, never silently dropped,
never read as membership or its absence. The two-axis detector
(`tests/fixtures/detect.py`) is reformulated on this basis; yesterday's
verdicts stand because its execution axis already paired emissions with
results before counting.

## Consequences

A Mode-B spec can now declare a subagent-spawning run as bounded: the bound
is the emitted subset, ADR-022 OR-4 is closed by measurement, and the
fixture register carries the evidence (FT-5..FT-19, each observed failing
once and observed in its declared state).

## Open records

**OR-1** — child sessions under the session sandbox persist no transcripts
below `~/.claude/projects` (write-denied); hook payloads name the intended
paths (`…/<session>/subagents/agent-<id>.jsonl`) but the files do not exist.
The captured stream plus disk markers carry the evidence instead.

**OR-2** — SubagentStart payloads carry no depth; the delegation ledger is
depth-blind. FT-9 holds it RED.

**OR-3** — DISCHARGED 2026-08-14: the pinned 0.9.0 darwin binary was
fetched and its sha256 matched the declaration in `.shellcheck-version`
(`7d3730…acf5`); run character-for-character as the gate runs it, it flagged
SC2015 on nine fixtures this arc added (the exact behavioural signature the
pin file documents — 0.9.0 accuses, 0.11.0 is silent), the nine were
repaired to the if-form, and the pinned gate now exits 0 over
`scripts/*.sh tests/*.sh`. The pin stays 0.9.0; declaration and use
converge.

**OR-4** — RESOLVED BY DOWNGRADE 2026-08-14: the A7 premise (a vault skill
symlinked into `~/.claude/skills`) did not hold when the arm ran and the
sandbox write-denies the path, so the premise cannot be established from a
session. A7 is NOT MEASURED (see the Context list); the `skills` field
remains unpromisable until a run with the premise valid measures it.

**OR-5** — the arm model is sonnet by explicit choice; the operator session
was served by fable-5. Tool-surface mechanics are harness-level, but the
recording is model-tagged so a re-run can vary it.

**OR-5** — the arm model is sonnet by explicit choice; the operator session
was served by fable-5. Tool-surface mechanics are harness-level, but the
recording is model-tagged so a re-run can vary it.

## Ratification

Accepted with the implementation in the same tree: the emitter and its seven
static checks (FT-13..FT-19), the apparatus and arm evidence
(runs/THR-SUBAGENT/20260813T194853Z, FT-5..FT-11), and the scoped-gate repair
emitted as tests/fixtures/gate-scope-argument.diff (FT-12). The second commit
of the two-commit cycle replaces the Proposed text with this file unchanged
except for this section and the status field.
