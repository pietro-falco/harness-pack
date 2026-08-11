---
type: adr
status: proposed
title: "Two REQUIRED spec fields, one now enforced and one still spent by nobody: a template obligation the pack cannot hold anyone to is a claim about the run that the run does not have to honour"
id: ADR-013
date: 2026-08-11
related-adrs: [harness-pack/ADR-004, harness-pack/ADR-005, harness-pack/ADR-006, harness-pack/ADR-009, harness-pack/ADR-011]
---

# ADR-013 — A declared obligation with no reader

## Status

**Proposed** (2026-08-11; docs-only). No code, no fixture, no schema change and no
constitution edit ships with this commit. Per the two-commit lifecycle in
`docs/STACK.md` § Agent contract, acceptance is a separate operator commit and
implementation follows the flip.

One half of this document's subject is already in `HEAD`. See Provenance.

## Numbering note

013 follows 012 and 011 by filename maximum in `docs/adrs/`. A sweep for the token
`ADR-013` returns zero hits in this repository and eighteen in the vault, all in the
vault's own namespace, which `vault/ADR-051` D3 keeps on an independent counter.
012 is likewise free here and is not taken by this document: it is reserved by
intent for the slice lease, whose falsifier is `bypass_f1`, and reserving by intent
is not reserving in fact. If 012 is authored later than this document, its own sweep
decides.

## Basis

| Repository | HEAD |
|---|---|
| `~/Code/harness-pack` | `ed9d5ad7c823e94bb843c25af7646f9d90986be5` |
| `~/Code/harnesswright` | `edb12a499615bf12aa80e5db1c67a268cb247114` |
| `~/Code/verity` | `4dc016b354f3a6eb953590167b46bc29eacf3fcb` |
| `~/Code/lanewright` | `ab77a81da6eecc4f7942c1e508b319c844049da8` |
| `~/Obsidian-Vault` | `a9f0e758fdf6e4d6644b01c70ff05370f8a0f1d3` |
| `~/Code/harness-smoke` | `f8b83699b681f555b8fd6213bb80c14bdc1675e7` |

Blob read for this document, at `HEAD`:

| Artifact | sha256 |
|---|---|
| `templates/spec.mode-b.template.md` | `e612691df4423c870d6e71e9139920357b3515784a1ce451c0c68fc0aa2259b3` |

Both fixtures were executed from the operator shell against the committed tree, with
a digest of all six repositories taken before and after and found identical:

| Fixture | Measured | Exit | Verdict |
|---|---|---|---|
| `tests/bypass_fc_scope_unread_fixture.sh` | 2026-08-11T15:40Z | 1 | RED |
| `tests/bypass_fc_scope_unread_fixture.sh` | 2026-08-11T20:14Z | 0 | GREEN |
| `tests/bypass_fb_budget_tokens_unbounded_fixture.sh` | 2026-08-11T20:20Z | 1 | RED |

The `scope` row is red and green on one unmodified fixture, one commit apart. The
`budget` row is red at this basis.

## Context

`templates/spec.mode-b.template.md` marks six fields REQUIRED. The launcher STOPs on
four of them by name — `model` at `:137`, `tools` at `:149`, `criteria` at `:154`,
and now `scope` at `:162` — and the pattern that finds those reads found, before
`c846887`, zero reads of `scope` anywhere under `scripts/`, including in the pack's
own spec linter.

`bypass_fc` measured that gap with the control that makes it a measurement rather
than an assertion: `tools: []` was refused by the same launcher, one field away in
the same template, while a scope naming an absolute path and a parent-directory
component reached the decision line unchanged. A REQUIRED declaration was doing work
for one field and none for the next.

`budget` is the field the same pattern still holds for. `:139` reads
`spec.get("budget") or {}` and never stops: a budget that is absent and a budget
declaring only `tokens` are indistinguishable downstream, because `:141` and `:143`
resolve both to the sentinel `"0"`. The sentinel is deliberate and documented at
`:115-116` and `:337-338` — an undeclared dimension emits no flag, and the old
silent 15/20 defaults are gone. What replaced them for a tokens-only budget is not a
different bound. It is no bound: `:346` adds no `--max-turns`, `:348-352` wraps the
spawn in no `gtimeout` and no `timeout`.

`tokens` occurs zero times in the launcher. The template offers three dimensions and
declares that any one of them satisfies the obligation; the pack can spend two.

The shape is one shape. A template field marked REQUIRED is a statement about what
every Mode B run honours. Where nothing reads the field, the statement is about a
document rather than about a run, and the run is bounded by whatever the layers
below happen to enforce — which `ADR-011` has just finished measuring.

## Decision

### D1 — A field the template marks REQUIRED is refused at the launcher or is not marked REQUIRED

There is no third state. A field carrying an obligation the pack cannot hold anyone
to reads to an operator as a bound and behaves as a comment.

Withdrawing a declaration is a legitimate outcome of this decision and is an
operator act, recorded in the ADR that withdraws it. It is not an implementation
detail available to whoever is closing a fixture, and `bypass_fb` enforces that
distinction directly: its first control reads the declaration at `:14`, and the
declaration's absence is recorded as FIXTURE BROKEN rather than as green.

### D2 — `scope` is refused on each of its three obligations, and never normalized

The template states three things at `:21-22`: present, non-empty, repo-relative. Each
is refused on its own line so a spec violating one is named for that one.

A leading `/` is not stripped and a `..` component is not resolved. Normalizing
would hand the run a perimeter the operator did not declare, and the declaration is
what is being enforced.

**Falsifier:** `bypass_fc`, RED at 15:40Z and GREEN at 20:14Z against `c846887`, with
its control intact: a legal scope still reaches the decision line, so this is
enforcement and not a launcher that refuses everything. Reads of `scope` under
`scripts/` went from 0 to 5.

This decision is a record of code already in `HEAD`. See Provenance.

### D3 — A budget the launcher cannot spend is a STOP, not a silent zero

`:139` gains a refusal on the same footing as its four neighbours: a spec whose
budget declares no dimension the launcher can turn into a bound does not launch.

This is one of exactly three ways `bypass_fb` names to clear its row, and it is the
one that adds no new bound and no new estimator. The row also permits resolving a
turn bound or a wall-clock bound from `tokens`; both would require deciding what a
token budget converts into, which is a modelling decision this document does not
have the measurement to make. Spending `tokens` as a bound of its own clears the row
only if it lands on `max_turns` or `wall_sec`, which are the two dimensions the row
reads.

The sentinel is untouched. A declared dimension still emits its flag and an
undeclared one still emits none; what changes is that a spec declaring no spendable
dimension no longer reaches the spawn.

**Falsifier:** `bypass_fb`, RED at this basis — a template-legal budget of
`{tokens: 200000}` reaches the decision line with `max_turns=0 wall_sec=0`, while its
control, `{turns: 10, wall_clock: "15m"}`, resolves to `10` and `900` through the
same driver and the same launcher.

### D4 — The obligation is stated once, in the template, and read by the linter as well as the launcher

The launcher refuses at launch. `scripts/lint_specs.py` refuses at authoring time,
and today it does not know `scope` exists. A spec author who learns of an obligation
only when a run STOPs has learned it in the most expensive place available.

Both readers derive the REQUIRED set from the template rather than restating it, so
a field added to the template is enforced without either reader being edited. The
mechanism is chosen at implementation; what this decision fixes is that there is one
statement of the obligation and no copy of it in code.

**Falsifier:** the row `bypass_fc` already computes, generalised — for every field
the template marks REQUIRED, a read under `scripts/`. Named at acceptance under
`ADR-008` D7 with its negative twin: a template field marked REQUIRED and read by
nobody must make it red, and a field the template does not mark must not.

## Verification

Two fixtures at acceptance, plus the generalised row D4 names.

| Fixture | Green when |
|---|---|
| `bypass_fc` | all three obligations at `:21-22` are enforced before spawn, and a legal scope still reaches the decision line |
| `bypass_fb` | a tokens-only budget can no longer reach the decision line with both bounds at 0, and the green line names which of the three ways closed it |

`bypass_fc` is already green and its implementation is already in `HEAD`. It is
carried here as the measurement D2 records, not as work outstanding.

For this docs-only commit:

git show --stat --oneline HEAD
git show HEAD:docs/adrs/ADR-013-a-declared-obligation-with-no-reader.md | head -8
bash tests/run_tests.sh
node "<verity entrypoint>" verify .verity/claims.json


## Consequences

- Six REQUIRED fields, six readers. The count is checkable rather than asserted.
- A spec whose only budget dimension is `tokens` stops being launchable. No such
  spec is known to exist in this stack; if one does, it fails loudly at its next
  launch rather than running unbounded.
- An unbounded Mode B run stops being reachable through a template-legal document.
  It remains reachable through a launcher invoked outside the pack, which is not
  this document's subject.
- `scope` is enforced as a declaration and not yet as a write bound. Nothing hands
  the list to the settings template or to the guard. `ADR-011` D1 is what closes
  that, and until it lands a narrow scope buys a narrow claim rather than a narrow
  run.

## Non-goals

- Converting `tokens` into a turn or wall-clock bound. That is a modelling decision
  and this document has no measurement to make it with.
- Handing `scope` to any enforcement layer. `ADR-011` owns the write bound.
- The slice lease and its two keys. Separate document, falsifier `bypass_f1`.
- The `stop_conditions` and `efficiency` fields. `efficiency` is REQUIRED and may be
  empty, which is an obligation of a different shape and is not measured here.

## Open requirements

- **OR-1 — `ADR-004 D7` is cited twice and does not exist.** The template at `:19`
  and the launcher at `:151` both cite it for the gate scope. `ADR-004` carries D1
  through D6 and no D7. This is the defect class `ADR-009`'s contract checker exists
  to detect, and the same class the vault records for a `harnesswright` document
  citing a token absent from the blob it names. Resolve there, not here; do not
  resolve by guessing which decision was meant.
- **OR-2 — a bare `D6` at `:115-116` resolves by proximity.** `:111` cites
  `ADR-005 D5/D6` and two lines later `D6` appears unqualified for the budget
  read-never-default rule. `ADR-006` also has a D6 and it concerns a licence. The
  reading is almost certainly `ADR-005`, and almost certainly is not a citation
  form. Qualify it or drop it.
- **OR-3 — `lint_specs.py` was not opened for this document.** D4 asserts it does
  not read `scope`, on the strength of a fixture line reporting zero reads across
  `scripts/*.{sh,py}` and naming the linter. The file itself is unread here.
- **OR-4 — no spec corpus was surveyed.** Whether any registered spec declares a
  tokens-only budget is unknown. D3 makes such a spec fail at launch; if one exists
  and is in use, that is a migration and not only a gate.
- **OR-5 — the six REQUIRED fields were read from the template, not from a parser.**
  The count rests on a grep for the token REQUIRED over the first thirty lines. A
  seventh field below that window, or a field whose comment spells the obligation
  differently, is outside what was measured.

## Not measured

Under `ADR-008` D6 these are tier B.

- What `harnesswright`'s spec gate enforces. The template header calls every field a
  `spec.js` gate per `ADR-006`; that file was not opened, and a field enforced there
  and not at the launcher is a different situation from a field enforced nowhere.
- Whether `next --json` can emit a spec object the template forbids. Both fixtures
  drive the launcher through a stub planner, which is the documented seam and is
  also not the real planner.
- The three effects `bypass_fb` names beyond the two bounds it reads. The row
  mentions a third path at `:212`; the lines read there describe the lease take and
  its two keys, and no reading was taken of what an unbounded run does to a lease
  TTL.

## Provenance

The `scope` enforcement in D2 landed in `c846887`, with its test-side prerequisite in
`efa22ef`, before this document existed in any state. `docs/STACK.md` § Agent
contract requires implementation to follow an ADR whose status reads Accepted. It
did not.

This is recorded here as evidence and not as an aside, in the form `ADR-008` uses for
the same class of breach. The code is not reverted and the history is not rewritten:
the commits are atomic, correctly ordered, and the fixture that governs them was red
before them and green after, which is the property the cycle exists to produce. What
the cycle would have added is the operator review between the decision and the code,
and that review is being taken now, after the fact, by accepting this document.

The measurements behind this document were taken from the operator shell, each with
the script's digest recorded before execution and its exit code after. No measurement
was taken by an agent session inside the tree it measured.
