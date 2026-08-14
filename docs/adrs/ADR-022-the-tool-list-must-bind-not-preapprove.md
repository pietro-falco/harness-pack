---
status: accepted
title: "The tool list must bind, not merely pre-approve"
basis: harness-pack@0d65945
date: 2026-08-13
corrects: ADR-011 — a factual claim in Context, not a decision (D5)
departs_from: ADR-011 D1 (D6)
---

# ADR-022 — The tool list must bind, not merely pre-approve

## Context

`spec.tools` has, since the launcher existed, reached the child on one flag:
`scripts/launch_worker.sh:358` passes `--allowedTools "$TOOLS"`, where `$TOOLS` is
the comma-joined list emitted by the decision block at `:184` and read at `:192`.

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
reach every other built-in through a prompt the launcher answers for it —
`--permission-mode dontAsk` at `:359`.

Two facts about the field itself, established while authoring this decision and
recorded because they change what D1 buys:

**The field has two shapes.** `templates/spec.mode-b.template.md:9-13` declares a
YAML list — `Read`, `Bash`, `Grep`, `Glob`. `templates/spec.template.md:11` declares
a comma-joined string including `Edit`. Two templates, two shapes, two default sets,
one field name. D7 decides which one this ADR binds.

**The Mode B default contains `Bash`.** A run built from the template is bounded in
its built-in surface and unbounded in what a bounded tool reaches. D5 states the
consequence rather than letting D1's title imply otherwise.

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

**D5 — ADR-011 carries a factual claim this decision corrects, and a residue this
decision does not touch.**

ADR-011 states, in Context at `:78-79`, that the allowlist *"has a closed complement
by construction: a tool not named is not admitted"*; at `:87` that *"the first layer
is the right shape and it works"*; inside D3's motivation at `:157` that *"the
allowlist is the closed layer"*; and in Consequences at `:217` that it *"is already
the right shape"*. The measurement in Context falsifies all four. None is a
decision — the claim lives in prose that supports decisions, never in a D — so no
decision of ADR-011 is superseded, and ADR-011 stands. It is `accepted` and
immutable (`:3`, `:14`), so those four lines stay on disk saying something the tree
denies. This clause is the correction; there is no other place to put it.

The residue is untouched and stays ADR-011's. `spec.scope` is validated in shape at
`scripts/launch_worker.sh:176-183` and then dropped: the decision line at `:184`
emits six fields and scope is not among them, `:192` reads six fields and scope is
not among them, and neither permission layer is ever handed the list —
`grep -n 'scope' scripts/guard_pretooluse.py templates/settings.mode-b.json` returns
nothing. The guard returns 0 for every non-Bash tool at `:83-84` and, for Bash,
matches sixteen command spellings at `:30-46` with no predicate over the write
target. A spec declaring `Bash` therefore buys an unbounded run whatever `--tools`
says. That is ADR-011's case, and this ADR retires the allowlist as an excuse,
nothing more.

**D6 — admission is not enforcement, and this decision departs from ADR-011 D1 on
that distinction.** ADR-011 D1 (`:121`, `:128-129`) decides that an enforcement rule
binds *"an effect on a path, never a tool name and never a command spelling"*. D1
above expresses a rule over tool names. The two are reconciled by class, not by
exception: ADR-011 D1 governs rules that judge what an admitted tool may do, where a
name is a proxy for an effect and a bad one. `--tools` decides what is admitted at
all. A tool that is not on the surface produces no effect to judge, so no predicate
over a write target could express it. The departure is declared here rather than
argued away, and OR-6 carries the risk that the distinction is a convenience.

**D7 — the Mode B template's list form is what this decision binds.**
`templates/spec.mode-b.template.md:9-13` is the normative shape. The string form at
`templates/spec.template.md:11` is Mode A's and is out of scope here; its divergence
in both shape and default set is recorded as OR-5 and belongs to whoever owns that
template.

## Falsifier register

At basis no row in this register existed and none had been observed:
`git ls-files -- 'tests/bypass_ft_*'` was empty and `grep -n 'FT-' tests/run_tests.sh`
returned nothing. Each row had to be **written and observed RED before the
implementing commit exists**, with its red captured under
`.verity/evidence/2026-08-13-adr022-first-red/`, because ratification without those
four observations is a ratification against a register that decides nothing
(ADR-017 D5).

**All four were so observed, on 2026-08-13, and this ADR is ratified on that
record.** Each was run against `scripts/launch_worker.sh` at
sha256 `08dc97ec297852eae3dfe4b556d0ecc46d6eac5ae2edc9e4e808b62c78063050`, which is
`HEAD:scripts/launch_worker.sh` unrepaired, and each red is captured in the evidence
directory above with that digest recorded beside it. The fixture bytes measured there
are the bytes committed: the reds and the greens are the same files, not a red file
edited into a green one.

Every row is hermetic. The live semantics of `--tools` cannot be a CI row: it needs a
real child, and ADR-002 requires launch checks that a fresh clone can run offline.
Rows drive the real launcher with a `claude` stub first on `PATH` that prints its
argv and exits — the same mechanism ADR-010's fixtures use to feed a constructed
input to a writer reachable only through the launcher.

| id | fixture | asserts | at basis | at ratification |
|---|---|---|---|---|
| FT-1 | `tests/bypass_ft_tools_not_bound_fixture.sh` | the launcher's spawned command carries `--tools` with exactly `spec.tools`; absent flag, divergent list, or the flag emitted twice is RED | RED, observed | GREEN on D1 |
| FT-2 | `tests/bypass_ft_allowlist_widens_bound_fixture.sh` | an allowlist name absent from `spec.tools` STOPs the launcher before spawn | RED, observed | GREEN on D2 |
| FT-3 | `tests/bypass_ft_mcp_survives_bound_fixture.sh` | the spawned command carries `--strict-mcp-config` and no `--mcp-config` | RED, observed | GREEN on D3 |
| FT-4 | `tests/bypass_ft_bash_unbound_fixture.sh` | with `tools: [Bash]`, no layer holds a predicate over the write target: the decision line at `:184` emits no scope, the read at `:192` takes none, and neither `guard_pretooluse.py` nor `settings.mode-b.json` names the field | RED, observed | **RED, and stays RED under this ADR by design** — D5's residue, not this ADR's obligation |

FT-4's subject overlaps `tests/bypass_fc_scope_unread_fixture.sh`, which is GREEN
since `c846887` and measures the *shape* refusal. FT-4 measures the *absence of an
enforcement point* and must not be closeable by any repair to shape validation.

## Consequences

A spec built from the Mode B template is bounded to four built-ins and unbounded in
capability, because `Bash` is one of the four. D1 buys a real narrowing for a spec
that omits `Bash`, and a nominal one for the modal spec that does not. Removing
`Bash` from the template default would change what every existing spec resolves to
and is not decided here.

## Open risks

**OR-1 — Discharged 2026-08-13.** No single decision of ADR-011 carries the premise;
it lives in Context and Consequences prose. D5 cites all four lines and reclassifies
the act from narrowing to correction.

**OR-2 — Discharged 2026-08-13.** The Mode B default is `Read, Bash, Grep, Glob`
(`templates/spec.mode-b.template.md:9-13`). Recorded in Context and Consequences.

**OR-3 — the semantics are measured on 2.1.231 only, and no row detects a change.**
A release in which `--tools` stops removing is a silent widening with no local
signal, because the detecting measurement is not hermetic and cannot run in CI. The
live probe is re-run and its output captured on every CLI upgrade, by procedure and
not by gate. This is a declared hole.

**OR-4 — propagation to subagents is unmeasured.** Whether `--tools` bounds tools
reached through the Agent tool was not tested. Until it is, no spec may declare a
subagent-spawning run as bounded.

**OR-5 — two templates declare one field in two shapes.** `spec.template.md:11` is a
comma string including `Edit`; `spec.mode-b.template.md:9-13` is a YAML list without
it. D7 scopes this ADR to the second. The divergence itself is undecided.

**OR-6 — D6's distinction may be a convenience.** Admission and enforcement are
separated here on a reading of ADR-011 D1's intent, not on a clause that draws the
line. If the distinction does not hold, D1 is a departure needing its own
supersession of ADR-011 D1 rather than a reconciliation.

**OR-7 — ADR-011:75 cites `launch_worker.sh:343`/`:344`; at this basis those lines
are `:358`/`:359`.** Line drift inside an immutable document. Recorded, not
repairable.
