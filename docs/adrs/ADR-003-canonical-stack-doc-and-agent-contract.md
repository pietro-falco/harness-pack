# ADR-003: Canonical stack-integration doc (docs/STACK.md) and agent-contract home

- **Status:** Accepted
- **Date:** 2026-07-17
- **Deciders:** Pietro Falco
- **Related:** ADR-001 (harness-pack deploy topology — Accepted), ADR-002 (hermetically testable launch checks — Accepted). External code repos composed at runtime: harnesswright (the planner; launcher consumes `next --json`) and verity (the gate; launcher consumes `verify --json`), both MIT. Forward: ADR-004 (parameterized topology & sanitization) owns the literal-path/uid supersession of ADR-001 and the launcher-fallback changes — this ADR does not. Vault ADR-060 (license split; open question 3). The operator's private governance chain (`~/.claude/CLAUDE.md` and its vault `@import`s) is out of scope here and unchanged by this ADR.

## Context

harness-pack is the runtime composition point of a three-repo stack. The launcher resolves the harnesswright planner (`scripts/launch_worker.sh:36`, `HW_CLI`) and consumes its plan (`node "$HW_CLI" next --json`, `:69`), then resolves the verity gate (`:42`, `VERITY_CLI`) and consumes its report (`node "$VERITY_CLI" verify --json`, `:199`). The dependency is one-directional: harness-pack depends on both harnesswright and verity; neither depends on harness-pack, and verity depends on nothing in the stack. harness-pack is therefore the only repo that sees all three, which makes it the natural home for a document describing how they fit.

No such document exists today. The three-repo story is scattered across README sections — `## Architecture` (`README.md:36`), `## Where it sits` (`:168`), `## Governance` (`:179`) — none of which is a canonical, linkable account of the stack, and none of which states the contract a fresh agent session must follow. There is no committed `CLAUDE.md` in this repo (`ls CLAUDE.md` → absent), and no in-repo `@import` chain (`grep -rn '@import' CLAUDE.md` → none): the execution discipline an autonomous Claude Code session needs (the ADR gate, the two-commit propose→accept lifecycle, evidence-not-prose, git hygiene) currently lives only in the operator's private `~/.claude` chain, which is not committed and reaches no public clone. A public consumer of any of the three repos has nowhere to read either the stack architecture or the agent contract.

This ADR decides the **structure and policy** for closing that gap: where the canonical stack doc lives, what it must contain, where the agent contract is authoritative, the CLAUDE.md policy for the three repos, and the license-split rationale. It does **not** author `docs/STACK.md` or any `CLAUDE.md` — that prose is taste-critical and is authored later in slice S-SR-003 against this ADR as its spec.

## Decision

### D1 — Home: `docs/STACK.md` in harness-pack, not a meta-repo

The canonical stack-integration document lives at `docs/STACK.md` in **harness-pack**. Rationale, from recon: harness-pack is the only repo depending on both others (§Context), so the coupling direction stays clean — the doc lives with the code that does the composing, not above it; it is the runtime composition point (the launcher is the one place the three vocabularies meet); and a dedicated meta-repo would add a fourth, doc-only repo, doubling the drift surface for a solo maintainer with no offsetting benefit. harnesswright and verity each carry a one-line README pointer to this doc (the pointer edits are folded into a later README slice, S-SR-004 — not authored here).

### D2 — Required contents of `docs/STACK.md` (outline/spec, not prose)

The authoring slice (S-SR-003) must satisfy this section list; the one-line gloss states each section's job, not its wording:

- **Three-layer map** — Intent (specs + ADRs) → Execution (Claude Code, wrapped by harness-pack) → Truth (harnesswright plan gate → verity verification → hash-pinned receipts).
- **Composition diagram** — the one-directional dependency: harness-pack → {harnesswright, verity}; verity → nothing.
- **License rationale** — why the Apache-2.0 / MIT split stands (per D5).
- **Agent contract** — the authoritative execution-rules prose (per D3).

### D3 — Agent-contract home: authoritative in `docs/STACK.md §"Agent contract"`

The canonical agent contract — the execution rules a fresh Claude Code session needs (the ADR gate: implement only against an Accepted ADR; the two-commit propose→accept lifecycle; evidence discipline: raw output and receipts, never prose summaries in their place; git hygiene: explicit-path staging, no `--no-verify`, no destructive operations) — has its **single authoritative prose** in `docs/STACK.md §"Agent contract"`. Each repo's `CLAUDE.md` is a thin public projection that points at it rather than restating it, and the harnesswright-generated `CLAUDE.md` template (a future slice) draws from the same source. For public consumers this replaces the private-vault `@import` path as the way the contract is delivered. The operator's private vault chain (`~/.claude/CLAUDE.md` and its `@import`s) is explicitly unchanged and out of scope: this ADR governs only the public, committed surface.

### D4 — CLAUDE.md policy for the three repos (rule, not content)

Each of the three public repos carries a `CLAUDE.md` that is a **public projection only**: no vault paths, no `@import` of private files, no operator model identifiers. harness-pack and harnesswright each get a new `CLAUDE.md`; verity's existing `CLAUDE.md` is **extended, not replaced**. All three point at the D3 agent contract as their single source. Authoring the actual files is deferred to S-SR-003; this ADR fixes only the policy they must conform to.

### D5 — License-split rationale: keep as-is, document the why

The stack keeps its current license split, and `docs/STACK.md` records the rationale (per vault ADR-060, open question 3): **Apache-2.0 for harness-pack** — the runtime/enforcement layer, where the Apache patent grant is the right fit for code that executes and gates real work — and **MIT for harnesswright and verity** — thin libraries where MIT's minimal footprint maximizes reuse. This is a decision to **not relicense**: the split is deliberate, not drift, and the doc says so.

### D6 — Boundary with ADR-004

This ADR owns the **document** — where the stack story and the agent contract live and what they must contain. It does **not** touch `scripts/launch_worker.sh`, the `Justfile`, or ADR-001's enforced paths. The literal-path/uid supersession of ADR-001, the launcher-fallback changes, and repo sanitization belong to **ADR-004** (parameterized topology & sanitization). Sequencing: slice S-SR-002 (full harness-pack sanitization) depends on ADR-004; slice S-SR-003 (authoring `docs/STACK.md` + the three `CLAUDE.md` projections) depends on **this** ADR.

## Non-goals

- Not authoring `docs/STACK.md`, any `CLAUDE.md`, or the harnesswright CLAUDE.md template — all taste-critical prose deferred to S-SR-003.
- Not editing `scripts/launch_worker.sh`, the `Justfile`, or ADR-001's paths — that is ADR-004's scope (D6).
- Not editing the harnesswright/verity READMEs to add their pointers — folded into S-SR-004.
- Not relicensing any repo — the split is kept, only its rationale is documented (D5).
- Not altering the operator's private `~/.claude`/vault governance chain (D3).

## Alternatives considered

- **Meta-repo home for the stack doc** — rejected (D1): a fourth doc-only repo doubles the drift surface for a solo maintainer and inverts the clean coupling direction; the doc belongs with the repo that does the composing.
- **The agent contract lives independently in each repo's CLAUDE.md** — rejected: three independent copies drift with no single source of truth; D3 makes STACK.md authoritative and the CLAUDE.md files thin projections.
- **Relicensing to harmonize the stack on one license** — rejected (D5): no benefit; the Apache-2.0 (enforcement layer) / MIT (thin libraries) split is a deliberate, documented choice.

## Consequences

- Slice S-SR-003 (author `docs/STACK.md` and the three `CLAUDE.md` public projections) becomes eligible on this ADR's acceptance, with D2/D3/D4/D5 as its spec.
- A fresh Claude Code session against any public repo will, once S-SR-003 lands, have a committed, linkable agent contract to read — no dependency on the operator's private chain.
- The harnesswright/verity README pointer edits are deferred to S-SR-004, not made here.
- ADR-004 remains the owner of the topology/path/sanitization changes; this ADR deliberately leaves `scripts/launch_worker.sh`, the `Justfile`, and ADR-001's paths untouched, so the two slices do not collide.
