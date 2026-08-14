# THR-SUBAGENT — findings (evidence record)

Run 20260813T194853Z · harness-pack @ ef78ad8 (branch main, dirty tree) ·
claude CLI 2.1.231 · operator session model: fable-5 · arm model: sonnet
(explicit) · all shell scripts in this arc pass shellcheck 0.11.0.

## Gate (verbatim, run start)

```
RED — 5 fact(s) diverged:
  THR-GATE/GATE-3 — harness-pack main is 0 commits ahead of origin/main
    expected: 0
    observed: 2
    target 0: the CLAIM reaches it, the OBSERVATION does not — this fact is seeded as done
  THR-WIRING/WIR-2 — twelve bypass fixtures exist on disk
    expected: 24
    observed: 28
  THR-WIRING/WIR-5 — run_tests.sh names a tracked bypass fixture on sixteen lines
    expected: 28
    observed: 32
  THR-WIRING/WIR-6 — the register is twelve literal bypass_row lines in tests/run_tests.sh
    expected: 24
    observed: 28
  STRUCTURE/status-done — THR-GATE is DONE with 0 of 1 progress fact(s) at target; GATE-3 below target. DONE is a measure here, not a label: close it by moving the observation, never by editing the status
state: GUARD-SCOPE | RED 37/42 | tgt 2/8 | hp ef78ad8 hw 1aaf794 rsr - vlt ce4bc76 | 2026-08-13T19:44Z
```

Exit code: **1**. Classification: GATE-3 and STRUCTURE/status-done
**out-of-scope** (unpushed commits; operator push closes both). WIR-2/WIR-5/
WIR-6 **in-scope** (fixture register, THR-SUBAGENT territory), reconciled by
the tracker delta below. Version check: `claude --version` → `2.1.231
(Claude Code)` ≥ 2.1.219 floor.

World motion during the run, recorded not repaired: the four bypass_ft_*
fixtures moved untracked→staged in the harness-pack index between 19:44Z and
19:53Z with no git command issued from this session (WIR-1 went red, 28 vs
24, invisible at 19:44). Presumed concurrent operator session.

## Commit 0 — the gate cannot scope

Defect recorded: WIR-2 is NAMED "twelve bypass fixtures exist on disk" and
CARRIES expected 24 — human-readable name and machine value diverge, and
neither matched the disk (28 at start). Repair emitted as a unified diff,
never written into 80-governance/: `patches/gate-scope-argument.diff` (copy
at `tests/fixtures/gate-scope-argument.diff`). Semantics validated on the
live tracker with a patched copy: `--scope THR-DIALECT` → exit 0 with
out-of-scope reds present; `--scope THR-WIRING` → exit 1 on in-scope reds
only; unknown scope → exit 2; state files never written by a scoped run.
Fixture FT-12 observed RED against the deployed gate (no `--scope`) and
GREEN against the patched copy.

## Commit 1 — eight arms, two detectors each

Preflight: `--max-turns` and `--append-subagent-system-prompt` are accepted
on 2.1.231 though absent from `--help`. `--permission-mode` choices carry no
"default". Every arm: separate `claude -p`, pinned recorded session id,
stream-json, `--forward-subagent-text`, `--strict-mcp-config` with no
`--mcp-config`, explicit permission mode, explicit
CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH, bounded turns/wall/budget. Detectors:
content-pinned disk markers vs stream/transcripts; agreement required.

| arm | session | question | outcome |
|-----|---------|----------|---------|
| A8 | 28038de1 | positive control, Bash in pool+allowlist | CONFORME — both markers, detectors agree |
| A1fg | 265bd37d | no tools field → inherits restricted pool | CONFORME — no Bash tool_use |
| A1bg | 903274d4 | same, background | CONFORME |
| A2fg | 1dce3698 | child tools can widen? | CONFORME (subset) — Bash EMITTED, runtime rejected: "No such tool available: Bash. Bash is disabled for this session, in subagents as well as here." |
| A2bg | 360f77a0 | same, background | CONFORME — **the background filter INTERSECTS the inherited pool; it does not replace it** (the suite's central question) |
| A3 | a0621a3d | depth 2 | CONFORME — leaf alive, no widening |
| A4 | 40b78262 | builtin default config | CONFORME — general-purpose executes Bash |
| A5 | 436a3cf9 | parent acceptEdits vs child "default" | CONFORME — child Write executed with no grant; parent mode governs |
| A6 | db62cda0 | memory "project" paths | CONFORME — `<cwd>/.claude/agent-memory/probe/{MEMORY.md,probe_constant.md}`; nothing under ~/.claude |
| A7 | cc0bcff5 | skills content into child context? | DIVERGENTE — CLAIM-SKILL-ABSENT, zero body strings, no Skill tool added. Premise caveat: no vault symlink in ~/.claude/skills |

Incidental measurements: `--tools ""` is disable-ALL and removed Agent
itself (first A4 run, kept at `arms/A4-tools-empty-string/`); a model CAN
emit a tool_use for an unoffered tool — pool absence surfaces as a runtime
error result, not emission impossibility.

Apparatus limitation: the session sandbox write-denies
`~/.claude/projects`, so child sessions persist no transcripts; hook
payloads name the intended files (`…/<sid>/subagents/agent-<id>.jsonl`) but
they do not exist. The captured stream plus disk markers carry the evidence.

## Commit 2 — propagation frozen at depth 2

Register line: **`--append-subagent-system-prompt` reaches depth-2
subagents — measured: token `c34e557bb6d8ab0d` (16 hex, present only in the
flag text) named the marker the depth-2 leaf wrote; negative control without
the flag wrote `control.marker`, token in 0 stream lines and 0 transcripts —
doc: flag propagates to nested subagents, version floor v2.1.205 — measured
on 2.1.231, 2026-08-13.** Corroboration channel divergence: the documented
transcript grep under `~/.claude/projects/*/<sessionId>/subagents/` is empty
because of the sandbox write-deny above; the stream (6 token occurrences,
pos) corroborates instead.

## Commit 2b — three seams

1. `$HARNESS_SCOPE` survives into PreToolUse hook invocations fired inside
   subagents at depth 1 and depth 2 (rows carry agent_id/agent_type and
   scope=THR-SUBAGENT). GUARD-SCOPE is depth-transparent; THR-SUBAGENT
   reduces to a configuration change.
2. SubagentStart exists and fires per spawn on 2.1.231 (2 start + 2 stop
   rows on the depth-2 run). Payload: agent_id, agent_type, cwd, session_id,
   transcript_path — **no depth field**. The delegation ledger is
   depth-blind; FT-9 holds it RED.
3. Report marker (recorded as signal, not interpreted): the Agent
   tool_result appends a text block `agentId: <id> (use SendMessage with to:
   '<id>' …)` + `<usage>subagent_tokens… tool_uses… duration_ms…</usage>`.

## Commit 3 — emitter

Precondition machine-read from RESULT.json (apparatus_green ∧ A8 CONFORME
with both markers). Emission target `harnesswright/scripts/emit_agents.mjs`
(the sandbox write-denies ~/Code/harnesswright; the file is emitted at
`emitter/emit_agents.mjs` and frozen at `tests/fixtures/emit_agents.mjs`).
Closed sixteen-key vocabulary; static checks all observed firing:
E_TOOLS_SUPERSET 66 · E_UNKNOWN_KEY 67 · E_AGENT_WITHOUT_DEPTH_BOUND 68 ·
E_MEMORY_UNDECLARED 69 · E_SKILL_NOT_ALLOWLISTED 70 · E_ZERO_TOOLS 71 ·
E_DENY_FORM 72 · E_PRECONDITION 65. Deny rules: bare-name form required;
resolution deny-first-then-tools, a tool in both lists is removed (FT-18
asserts the declared surface). External gate divergence: `claude` ACCEPTS a
malformed `--agents` silently (exit 0, no error) — the CLI is not a
validation gate; FT-19 stands RED holding that visible. A valid emission is
accepted and functional (every arm ran through the same `--agents` shape).

## Fixtures

FT-5..FT-19, files `tests/bypass_ft_*_fixture.sh`, 15 new; every one
observed failing at least once (adverse inputs or broken-detector stubs,
recorded in the session transcript) and observed in its declared state.
Register: 15 `bypass_row` lines appended to tests/run_tests.sh; declared
states GREEN except FT-9, FT-12, FT-19 RED (defects held visible). Suite run
after registration: all 43 rows `ok` (declared == observed);
single suite failure = register completeness "registered and NOT tracked"
(the 15 new fixtures are intentionally uncommitted; closes with the first
emitted commit). Shellcheck gate: pinned 0.9.0 vs installed 0.11.0 →
unmeasured on this machine (pre-existing; pinned binary unreachable from the
session sandbox — GitHub release assets live on a host outside the network
allowlist). Verity: 12 passed, 0 failed, OVERALL: PASS.

## Tracker delta (one operator edit closes it)

Fixture count recomputed: start 28, end 43 (glob tests/bypass_*).

| fact | claim (name) | expected now | observed end-of-run | proposed edit |
|------|--------------|--------------|---------------------|---------------|
| WIR-2 | "twelve bypass fixtures exist on disk" | 24 | 43 | claim → "the bypass fixtures on disk match the register cardinality"; expected → 43 |
| WIR-1 | "twelve bypass fixtures are tracked" | 24 | 28 (43 once the emitted commits land) | expected → 43 after commit; same claim rename |
| WIR-5 | "…on sixteen lines" | 28 | 47 | expected → 47; drop the numeral from the claim |
| WIR-6 | "…twelve literal bypass_row lines" | 24 | 43 | expected → 43; drop the numeral from the claim |

Defect recorded (commit 0): in WIR-2 the readable name says twelve, the
machine value says 24, the disk said 28 at start and says 43 now. Names that
carry counts go stale in a channel the gate never checks; the proposed edits
remove counts from names and keep them in `expected` where the gate lives.

## Emitted commit sequence (not executed; explicit paths, no -A, hooks on)

```
git add -- docs/adrs/ADR-023-the-subagent-surface-is-measured-not-inherited-by-declaration.md
git commit -m "docs(adr): propose ADR-023 — the subagent surface is measured, not inherited by declaration"

git add -- tests/fixtures/gate-scope-argument.diff tests/bypass_ft_scoped_gate_out_of_scope_red_fixture.sh
git commit -m "test(gate): emit scoped-gate repair and FT-12 — out-of-scope red must not read as abort"

git add -- runs/THR-SUBAGENT/.current runs/THR-SUBAGENT/20260813T194853Z/apparatus runs/THR-SUBAGENT/20260813T194853Z/arms runs/THR-SUBAGENT/20260813T194853Z/STATE.md tests/fixtures/detect.py tests/bypass_ft_positive_control_bash_in_pool_fixture.sh tests/bypass_ft_stale_marker_precedence_fixture.sh tests/bypass_ft_write_tool_misattribution_fixture.sh tests/bypass_ft_permission_mode_precedence_fixture.sh
git commit -m "test(subagent): eight-arm apparatus and evidence — the background filter intersects the pool"

git add -- tests/bypass_ft_appended_prompt_negative_control_fixture.sh
git commit -m "test(subagent): freeze depth-2 prompt propagation with its negative control"

git add -- tests/bypass_ft_spawn_ledger_depth_blind_fixture.sh tests/bypass_ft_scope_env_absent_at_depth_fixture.sh
git commit -m "test(subagent): observational seams — scope env is depth-transparent, spawn ledger is depth-blind"

git add -- runs/THR-SUBAGENT/20260813T194853Z/emitter tests/fixtures/emit_agents.mjs tests/fixtures/thr_subagent_result_green.json tests/bypass_ft_emitter_tools_superset_fixture.sh tests/bypass_ft_emitter_unknown_key_fixture.sh tests/bypass_ft_emitter_agent_without_depth_bound_fixture.sh tests/bypass_ft_emitter_memory_undeclared_fixture.sh tests/bypass_ft_emitter_empty_tools_resolution_fixture.sh tests/bypass_ft_emitter_deny_order_inversion_fixture.sh tests/bypass_ft_emitter_output_rejected_by_cli_fixture.sh
git commit -m "feat(emitter): --agents emitter with closed vocabulary and seven static refusals"

git add -- tests/run_tests.sh runs/THR-SUBAGENT/20260813T194853Z/RESULT.json runs/THR-SUBAGENT/20260813T194853Z/FINDINGS.md runs/THR-SUBAGENT/20260813T194853Z/adr/ADR-023.accepted.md
git commit -m "test(register): fifteen THR-SUBAGENT rows; suite asserts them declared==observed"

# second half of the two-commit ADR cycle: overwrite the proposed file with
# runs/THR-SUBAGENT/20260813T194853Z/adr/ADR-023.accepted.md, then
git add -- docs/adrs/ADR-023-the-subagent-surface-is-measured-not-inherited-by-declaration.md
git commit -m "docs(adr): accept ADR-023 — implementation and evidence in-tree"
```

## Assumption ledger

1. **"A model cannot emit a tool_use for an unoffered tool" — FALSIFIED.**
   A2fg/A2bg emitted Bash tool_uses the runtime then rejected. Pool absence
   is an error result, not emission impossibility; detectors must separate
   emission from execution (they do).
2. **--max-budget-usd on a subscription-only account** — passed on every
   arm; no billing error surfaced and no budget stop triggered at these
   sizes. Whether it binds spend on subscription auth is UNVERIFIED here;
   treated as harmless-if-inert.
3. **`Bash(claude *)` permission-rule syntax** — not exercised by this run;
   deny rules in the emitter use bare names precisely because the
   parenthesized form leaves the tool in context (E_DENY_FORM). Assumed, not
   measured.
4. **The pool the child sees is the parent's `--tools`, not settings** —
   arms ran with `--settings '{"disableAllHooks":true}'`, cwd outside any
   repo, `--strict-mcp-config`; user-level settings were not proven inert
   but no tool outside the declared pool ever executed in any arm.
5. **ADR numbering and fixture ordinals free** — verified by listing:
   ADR-023 next after ADR-022; FT-5 next after FT-1..FT-4.
6. **Arm model** — sonnet by explicit flag on all arms; a `model` field
   observed in results diverging from fable is expected and recorded, not an
   error (spec's own instruction).
