---
status: accepted
date: 2026-08-14
accepted: 2026-08-14
decision-makers: operator
---

# ADR-024 — the absence of declaration is not conformity

## Context

Three mechanisms exist in this stack and do not speak to each other: the
arc gate checks the tracker, `verity` checks the claims, `run_tests.sh`
checks the fixtures. None of them answers the question a reviewer of an
automated system acting on regulated records asks first: **did this
execution stay inside what it declared beforehand?** A trace cannot answer
it — a trace says what happened, not whether it was permitted. The
comparison must be computable without trusting any model's summary and
verifiable by someone who was not present at the run.

The survey of the existing surface was read, not recalled (evidence
record: the P1 survey in the THR-CONFORMANCE run directory, with per-source
citations). Its verdict: no surveyed format carries the comparison.
OpenTelemetry GenAI and OpenInference carry the comparison's *inputs*
(a declared tool list attribute, per-call tool names) and no comparison,
no verdict, no depth. Spec Kit compares artifacts to artifacts, never an
execution to an authorization. LangSmith records runs; LangGraph gates
future actions and records nothing about permission. The Agent SDK
documents its own gap: "`allowedTools` … does not restrict Claude to only
these tools" — the pre-approval/binding distinction ADR-022 named. The
comparison SHAPE exists exactly once, in the in-toto layout: a signed
a-priori declaration (`expected_command`, artifact rules, authorized
keys), link metadata recording what ran, and a verifier that fails closed
on mismatch — but its vocabulary is supply-chain steps over artifacts,
not tool calls with delegation depth. So the envelope is adopted and the
predicate is new: integration at the layer that exists, novelty only at
the layer that does not.

Thesis: **an execution is conformant only with respect to a surface
declared before it ran, and the absence of declaration is not conformity —
it is the absence of the measurement.**

## Decision

**D1 — the conformance record is an in-toto Statement with a new,
versioned, closed predicate.** predicateType
`…/attestation/conformance-record/v1` (URI rooted at this repository's
public remote). The subject is the run's stream transcript digest —
ADR-019's discipline, the subject is the transcript. The predicate
vocabulary is CLOSED: the verifier refuses any key outside the spelled
sets, so a prose field cannot enter a record without making it
NOT-RECOMPUTABLE (fixture FT-23). Canonical form is ADR-018 D1 (sorted
keys, compact separators, UTF-8, no trailing newline); the writer is an
ADR-020 D2 allowlist writer — every string it emits is a literal it
spells, a machine-read tool name or id, a basename, or a digest.

**D2 — the declared surface enters resolved, never as a pattern.** The
builder and the verifier both refuse a glob or a parenthesized scope in
the declared tool list: a glob expands differently at different moments,
and a surface that changes with its evaluation time is not a declaration.
The declaration is read from the machine-written launch header
(`invocation.txt`), never from any narration of it.

**D3 — the delegation tree is recomputed from `parent_tool_use_id`
chains, never taken from the hook ledger.** SubagentStart fires per spawn
but its payload carries no depth (measured 2026-08-13, ADR-023 C2b; FT-9
holds the ledger's depth-blindness RED). Depth is therefore a derived
fact: a tool_use in an event with no parent is depth 0; one whose event
names parent P is depth(P)+1; an unresolvable parent makes the record
unbuildable and the verification NOT-RECOMPUTABLE, never a guess.
Documented floor for all-depth forwarding of `parent_tool_use_id` is CLI
v2.1.219 (measured here on 2.1.231/2.1.232).

**D4 — readings are ADR-023 D6's.** `executed` is an emitted call whose
paired result is not an error; `error` is an attempt the runtime refused —
it never counts against the surface and never counts as exercising it;
`unresolved` (no paired result) blocks every verdict, because an unpaired
call could have been the one that left the surface. Conformance is judged
on executed calls only; the record still carries the attempts, visibly.

**D5 — the verifier recomputes everything and its exit codes are the
gate's.** 0 CONFORMANT, 1 DIVERGENT, 2 NOT-RECOMPUTABLE / NOT-MEASURED /
INCOMPLETE — and 2 is never a pass. Evidence digests must match before
any fact is recomputed (the digest travels, the bytes do not); recomputed
facts must equal the record's facts; only then is the comparison rule
applied. The rule itself is data (`conformance_rule_v1.json`,
ADR-018's algorithm-as-data), pinned in the record by id and digest.
The verifier's stream analysis is an independent implementation from the
builder's, deliberately: two computations that must agree turn a defect
into a visible disagreement instead of a shared blind spot. Verification
is deterministic; two replays that differ are a verifier defect (FT-25).

**D6 — the record reports the unused surface, and narrowing is proposed,
never applied.** `unusedAuthorizations` — declared tools never executed —
is a required, recomputed field: a record that omits it is DIVERGENT
(FT-26). From accumulated records, `conformance_narrow.py` emits a
narrowing-proposal artifact (`…/attestation/narrowing-proposal/v1`)
carrying the digest of every record it derives from. It writes a side-car
and edits nothing: a spec that rewrites itself without a trace is exactly
what this harness exists to prevent. Records whose declarations differ
are refused rather than averaged.

**D7 — the record is the API.** Consumers read the record and its
evidence; nothing is rewritten for a consumer. The proof is not a
declaration but a second, trivial consumer: `conformance_dump.py` renders
the whole record as static text with no access to the run. The live view
(`conformance_watch.py`) extends the arc gate's state-line contract — one
short line, atomically replaced, rewritten only on change, readable every
300ms without recomputation — in its own `conformance.state` file; the
gate's own line is not touched. Watch renders, it never verdicts: it
shows an out-of-surface emission the moment it appears (declared
threshold: three poll intervals) and leaves judgment to the record and
the verifier.

## Consequences

A Mode-B run can now close with an artifact that answers "did this
execution stay inside its declaration, and how much of the declaration
did it never need" — computable by machine, replayable by an absent
reviewer, and carrying the width of the unused bound as first-class data.
The eight fixtures FT-20..FT-27 hold the properties, each observed
failing once against a sabotaged consumer and once in its declared state
before registration. Real records for three of yesterday's measurement
arms exist in the THR-CONFORMANCE run directory and verify CONFORMANT
beside their evidence.

## Open records

**OR-1** — the arm evidence streams under runs/ carry local absolute
paths, so they stay untracked; the records reference them by digest only.
A record verifies beside its evidence; published alone it is
NOT-RECOMPUTABLE by design, not by accident.

**OR-2** — predicate v1 measures tool names and delegation depth. It does
not measure argument-level scope (a path a Write touched, a command a
Bash ran). That extension is a v2 decision with its own fixtures, not a
quiet field.

**OR-3** — the watcher reads a run directory shaped like yesterday's arms
(declaration + growing stream). Wiring it into `launch_worker.sh` so
every worker run produces a record by default is deliberate future work,
not smuggled in here.

**OR-4** — named execution modes (a read-only mode, a bounded-write mode)
would each be a spec that emits its own bound and its own record format.
Their shape is a product decision that does not derive from this
evidence; it is held at the operator's stop.

## Ratification

Accepted with the implementation in the same tree: the record builder,
verifier, rule file, dump, narrowing and watch consumers
(scripts/conformance_*.py, scripts/conformance_rule_v1.json), the
synthetic corpus and the eight fixtures FT-20..FT-27 with their register
rows, and the THR-CONFORMANCE evidence record
(runs/THR-CONFORMANCE/20260814T002404Z: three real-arm Statements
verifying CONFORMANT beside their evidence, the fixture falsification
pass, and the P1 survey). The second commit of the two-commit cycle
replaces the Proposed text with this file unchanged except for this
section and the status field. OR-4's stop stands: no named mode is
defined by this acceptance.
