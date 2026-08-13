---
status: proposed
title: "The tool list must bind, not merely pre-approve"
basis: harness-pack@3f027d7
date: 2026-08-13
supersedes: none
narrows: ADR-011 (premise, one direction only — see D5)
---

# ADR-022 — The tool list must bind, not merely pre-approve

## Context

`spec.tools` has, since the launcher existed, reached the child on one flag:
`scripts/launch_worker.sh:358` passes `--allowedTools "$TOOLS"`, where `$TOOLS` is
the comma-joined list emitted by the decision block at `:184` and read at `:192`.
`templates/spec.template.md:11` states the intent in a comment: `tools:
"Read,Edit,Bash,Grep,Glob"   # passed to --allowedTools in Mode B`.

That flag does not do what the field name promises. Measured on claude 2.1.231,
one prompt, two runs, everything else held constant:

    claude -p "List the exact names of every tool available to you, comma
    separated, nothing else." --tools Read
      -> Read, mcp__plugin_context7_context7__query-docs,
         mcp__plugin_context7_context7__resolve-library-id

    claude -p <same prompt> --allowedTools Read
      -> Agent, Bash, Edit, ListAgents, Read, ReportFindings, ScheduleWakeup,
         Skill, ToolSearch, Workflow, Write, CronCreate, ... WebSearch  (35 names)

`--allowedTools` names which tools execute without a permission prompt. It removes
nothing. `--tools` removes. Every Mode B run to date has therefore declared a tool
list that pre-approved a subset of a surface it never narrowed, and the model could
reach every other built-in by accepting a prompt the launcher answers for it —
`--permission-mode dontAsk` at `:359`.

ADR-011 is titled "the perimeter does not bound the capability" and names the
allowlist at `:75` as one of its producers. This decision does not contradict that
title; it removes one of the two reasons the title was true.

## Decisions

**D1 — `spec.tools` is a bound.** The launcher emits `--tools "$TOOLS"`. A tool
absent from `spec.tools` is absent from the child's surface, not merely unapproved.

**D2 — `--allowedTools` is retained and narrowed to what its name says.** It carries
the subset of `spec.tools` that executes without a prompt. A name present in the
allowlist and absent from `spec.tools` is a STOP before spawn, never a widening. The
allowlist can no longer be a ceiling; it is a convenience inside a ceiling set
elsewhere.

**D3 — the bound does not reach MCP tools, and Mode B closes that door
separately.** The probe above is the evidence: with `--tools Read` in force, two
`mcp__plugin_context7_*` tools remained on the surface. Mode B passes
`--strict-mcp-config` with no `--mcp-config`, so no MCP server loads. A Mode B run
that loads an MCP server does so by an explicit declaration in the spec, or not at
all.

**D4 — the bound has one named exception, recorded rather than discovered.** A tool
list that omits `EndConversation` does not remove it. This is stated, not measured
here, and D4 asserts only that the exception is declared: no falsifier in this
register may treat `EndConversation`'s presence as a breach of the bound.

**D5 — ADR-011's premise is narrowed in one direction only.** `--tools` bounds the
*built-in tool surface*. It does not bound what a bounded tool can reach: a spec
declaring `Bash` still hands the child unbounded capability through the shell, and
`spec.scope` still reaches no enforcement point (`:176-183` validates and drops it;
`tests/bypass_fc_scope_unread_fixture.sh:1-3` states the defect). ADR-011 stands on
the Bash case. This ADR retires the allowlist as an excuse, nothing more.

## Falsifier register

Each row must be RED at basis. A row that cannot go red is not registered.

| id | fixture | asserts | at basis |
|---|---|---|---|
| FT-1 | `tests/bypass_ft_tools_not_bound_fixture.sh` | a tool absent from `spec.tools` is absent from the child's reported surface | RED |
| FT-2 | `tests/bypass_ft_allowlist_widens_bound_fixture.sh` | an allowlist name absent from `spec.tools` STOPs the launcher before spawn | RED |
| FT-3 | `tests/bypass_ft_mcp_survives_bound_fixture.sh` | with the bound in force and no `--strict-mcp-config`, MCP tools remain reachable | RED |
| FT-4 | `tests/bypass_ft_bash_unbound_fixture.sh` | with `tools: Bash`, a write outside `spec.scope` succeeds | RED, and stays RED under this ADR by design — it is ADR-011's residue (D5), not this ADR's obligation |

FT-1 is the probe in Context, frozen. It is the whole of D1's evidence and must be
observed RED before the implementing commit exists.

## Open risks

**OR-1 — ADR-011's decision number is not read.** This document narrows ADR-011's
premise but names no D. ADR-011 is `accepted` and immutable; the narrowing clause
must cite the decision it narrows before ratification. Not determinable from what was
read at authoring time.

**OR-2 — the Mode B template's default tool line is unread.** If
`templates/spec.mode-b.template.md` defaults to a wide list, D1 binds to a bound
nobody chose, and the modal run is bounded only nominally. Read before ratification.

**OR-3 — the semantics are measured on 2.1.231 only.** A future release in which
`--tools` stops removing is a silent widening with no local signal. FT-1 is the
detector; it must run in CI, not only on the authoring host.

**OR-4 — propagation to subagents is unmeasured.** Whether `--tools` bounds tools
spawned through the Agent tool was not tested. Until it is, no spec may declare a
subagent-spawning run as bounded. This blocks the subagent arc, not this decision.
