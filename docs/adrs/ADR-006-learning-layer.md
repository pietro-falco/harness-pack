---
type: adr
status: accepted
title: "Learning layer for Mode B — BDTS router + Quality-Diversity lesson archive"
id: ADR-006
date: 2026-07-28
related-adrs: [harness-pack/ADR-001, harness-pack/ADR-005, vault/ADR-046, vault/ADR-049, vault/ADR-051, harnesswright/ADR-006]
---

# ADR-006: Learning layer for Mode B — BDTS router + Quality-Diversity lesson archive

- **Status:** Accepted
- **Date:** 2026-07-28
- **Deciders:** Pietro Falco
- **Related:** ADR-001 (enforced deploy topology, Accepted; the enforced copy under `$HARNESS_ROOT` is root-owned, so the learning state and its receipts are worker-side artifacts and never write into the pack). ADR-005 (mission-control & receipts-index, Accepted; its `learning_metrics.jsonl` consumer is the dashboard surface D12 here names, and its privacy-lint claim set in `.verity/claims.json` is the invariant every tracked artifact of this ADR must keep green). Cross-repo, qualified: **vault** ADR-051 (cross-repo ADR namespace prefixes, Accepted — this ADR is cited elsewhere as `harness-pack/ADR-006`, and D14 below is closed against its D1 prefix registry); **vault** ADR-046 (code-repo governance inheritance, Accepted — D15 here inherits it with no exception); **vault** ADR-049 (LLM-wiki layer on the atlas, Accepted — the amended D9 routes derived pages through its staging contract); **harnesswright** ADR-006 (Mode B ADW-ization, Accepted — the `type` field this layer's contexts key on). Those are external and only referenced. Two further documents govern this one and are deliberately **not** tracked here: the implementation ledger *LEDGER DI IMPLEMENTAZIONE — Learning Layer Mode B* (v1.0), which holds the slice plan, and the source dossier *Motore di apprendimento ricorsivo per Mode B* (v0.3, sections S0–S17), from which every decision in the register below is drawn. Both carry commercial and personal material that has no place in a published repository, so they stay in the operator's private working set; this ADR is the publishable projection of them. **This ADR decides; no code is written against it while it is Proposed.**

## Context

"Recursive learning locally, without stressing the hardware" has one technical reading consistent with Mode B: the harness learns **in the space of policy and context**, not in any model's weights. Every run already produces a deterministic receipt — gate exit code, verity verdict, ledger row. That receipt is the only reward signal, and it feeds two closed-form structures: a discounted Beta posterior over execution arms, and a textual archive of distilled lessons. The thing that improves run over run is the harness; the model is unchanged, unfine-tuned, and interchangeable.

The governance already in force fixes the admissibility criteria before any algorithm is considered. Truth is deterministic only, never LLM-as-judge. A failed gate is a full stop, never an auto-retry. Tier escalation is a spec edit, never a silent runtime decision. Self-improvement loops stay in quarantine and never touch governance files. The hardware is a single 8&nbsp;GB laptop and the budget is subscriptions, not GPUs. Anything admitted must therefore have O(1) closed-form updates, state measured in kilobytes, decisions reproducible from a seed, and exactly one attachment point: it reads receipts and it writes receipts.

Two operators satisfy that, and they are orthogonal rather than competing: the router refines *where* to execute, the archive refines *with what knowledge*. Both read the same receipt; neither touches the chain of truth. The loop is contractive by construction — the discounted posterior is a moving average that tracks the true pass-rate with sublinear regret over stationary segments, and the archive is monotone per niche under elitism. The failure mode of every self-reinforcing system, feedback that confirms itself, is cut here by a structural fact: the reward is never produced by the system. It is the exit code of a deterministic gate that sits outside the loop.

<p align="center"><img src="../diagrams/harness-pack-ADR-006-loop.png" width="880" alt="The coupled learning loop: a typed spec feeds the router's select step, which either stops with exit 3 when no arm fits the budget or emits a routing decision; the prompt builder combines that decision with the top-k lessons drawn from the Quality-Diversity archive; the slice runs bounded through an adapter; the deterministic gate plus verity either stops with no retry or appends to the runtime ledger; the ledger's reward and cost drive the router and archive updates, which close the loop back to select and to the archive"></p>

Diagram source: `docs/diagrams/harness-pack-ADR-006-loop.mmd`, rendered to PNG at 3x with a transparent background. Per the standing S-SR-004 norm, no inline mermaid block is committed: the markdown references the rendered image, never the platform renderer.

## Decision

The decision register below is the authoritative state of the eighteen decisions this layer turns on. It carries the ledger's own two states verbatim: **FINALE** rows are settled by this ADR and do not reopen without a superseding ADR; **APERTA** rows are deliberately unresolved, each naming the slice or phase that closes it, and none of them blocks the pre-F0 documentation or the F0 shadow phase.

| ID | Decision | State | Motivation |
|---|---|---|---|
| D1 | Algorithms: BDTS router + Quality-Diversity lesson archive | **FINALE** | The two chosen candidates cover the two orthogonal axes of learning — policy and knowledge — and both v0.1 modules already pass their selftests 10/10, so the selection is settled by evidence rather than preference. |
| D2 | Conformal escalation of tier (wave 3) | APERTA | A finite-sample risk guarantee needs a calibration set that does not exist yet; it is decided at the end of F2 with at least two hundred receipts in hand. |
| D3 | `cost_weight` W = 0.5 | APERTA | The dual price only means something once real cost data exists, so W is calibrated in F0 over the shadow receipts on a 0.3–0.8 grid rather than guessed now. |
| D4 | Cost estimator: EWMA vs p50/p90 quantiles | APERTA | The right estimator depends on the observed dispersion; F0 measures the coefficient of variation and a value above 0.5 selects quantiles over the moving average. |
| D5 | Niche capacity K = 2 | APERTA | Elitism per niche is what makes archive quality monotone, but the right capacity is a function of archive size, so it is revisited once the archive passes fifty lessons. |
| D6 | Verity licence (BSL 1.1 vs AGPL) and trademark | APERTA | This is a legal decision requiring counsel, not an engineering one, and it gates nothing in F0 through F2. |
| D7 | Vendored Beta sampler (Cheng on xorshift64*) for bit-perfect replay | **FINALE** | The stdlib sampler makes replay depend on the Python runtime, which would break the one property the routing receipt exists to provide; vendoring the sampler is the only way replay stays identical across machines. Lands in slice L8d. |
| D8 | Repo separation: learning state never in an employer or client repo | **FINALE** | The learned state is derived from the operator's own work and carries IP exposure, so it lives only in the personal harness repo — a boundary that is cheaper to hold from day one than to retrofit. |
| D9 | Wiki is a derived view of the receipts, never a source of truth; human notes stay in a separate, non-injectable namespace. **Amended**: the sync writes no page into the atlas — it emits proposals into the staging directory carrying a `target_path`, conforming to the wiki-ingest frontmatter contract (`type: wiki`, non-empty `sources:`, `updated:`), subject to the ten-verified-run promotion gate | **FINALE** | A generated page that can diverge from the receipts is worse than no page, and writing straight into the atlas would put a machine writer inside a human-curated namespace; the staging-proposal route keeps promotion a human act. Lands in slice L12. |
| D10 | Prompts: versioned templates categorised by `type`; the assembled prompt is recorded as a receipt (hash plus full text), not reused as a blob | **FINALE** | Replay and audit need the exact text that was sent, while cache efficiency needs a stable prefix; separating the versioned template from the per-run prompt receipt gets both without a mutable blob store. Lands in slice L9. |
| D11 | Vector-valued ρ, one pressure per provider | **FINALE** | A single scalar quota cannot arbitrate between independent subscriptions, and the router is precisely the component that should perform that arbitration. Lands in slice L8f. |
| D12 | `learning_metrics.jsonl` as the single source for the dashboard | **FINALE** | One append-only source with many views is the same discipline ADR-005 already applies to the receipts-index, and it keeps the dashboard a rendered file rather than a service. Lands in slice L5. |
| D13 | YAML parser for the spec validator (PyYAML if already present, otherwise a stdlib subset) | APERTA | The modules are stdlib-pure by design and adding a dependency to the validator is a supply-chain decision, so it is taken in L3 against what the target environment actually has. |
| D14 | ADR number and namespace prefix | **FINALE** | Closed by this ADR, which is slice L0. Recon of `docs/adrs/` showed ADR-001 through ADR-005 with no gaps, so this ADR takes **006**; the prefix registry in vault ADR-051 D1 already carries an active `harness-pack/` row (Amendment 1), so the cross-repo citation form is `harness-pack/ADR-006` and no vault amendment is required. The ledger's provisional `harness/` prefix is **not** used: it has no row in that registry, and citing it before registration is exactly the ordering breach Amendment 1 was written to record. |
| D15 | The layer inherits vault governance via vault ADR-046 (the PreToolUse guard as a user-global hook) | **FINALE** | No property of this layer justifies an exception to the guard, and an exception is the kind of thing that is never reverted once granted. |
| D16 | Thread handoffs only via the `session-handoff` / `session-close` skills | **FINALE** | Continuity across sessions must rest on a written artifact rather than recall, which is the same evidence discipline the gate enforces on code. |
| D17 | Breakthrough track: receipt algebra (provenance semirings, §8 of the ledger) | APERTA | The idea is recorded so F0 does not foreclose it, but it requires the v2 receipt schema from L13 as a prerequisite and gets its own ADR after F1. |
| D18 | Cryptographic transparency of receipts (Merkle plus inclusion proof) | APERTA | Tamper-evidence is already commodity in this space, so the hash-chain is assumed sufficient until L13 measures it or a client asks for more. |

## Non-goals

- No code is written against this ADR while it is Proposed. The two v0.1 modules stay outside the repo until L2, which depends on acceptance.
- The gate never reads a lesson. Lessons are inert prose injected into executor prompts only; the reward stays an exit code.
- The router never invents an arm. It optimises strictly inside the `allowed_arms` set declared in the spec frontmatter, and a tier change remains a spec edit.
- Conformal escalation, TPE over hyperparameters, multi-tenancy, and commercial lesson packs are out of scope until F3 closes.
- This ADR does not touch the receipt-chain format, `receipt_chain.py`, the constitution, or the launcher.

## Consequences and rollback

Accepting this ADR adds a decision layer between the spec and the runner and a knowledge layer between the archive and the prompt. Both are observable — every `select` emits an auditable, replayable `routing_decision`, and every slice appends one line to `learning_metrics.jsonl` — and both are additive: with the layer inactive, the harness behaves exactly as it does today.

The kill-switch is the per-slice `learning: { route, lessons }` frontmatter flag, each field an enum over `off | shadow | on`. `shadow` writes receipts but decides nothing; `off` disables the operator entirely. The two fields are independent, so routing can be disabled without losing lesson injection and vice versa. **Rollback is setting the flags back, not deleting state**: the learned posteriors and archive are preserved and simply stop influencing anything, which makes a KPI regression a one-field revert rather than a migration. A phase KPI regression is a stop under the same fail-stop rule as a red gate.

The residual risks are the ones the dossier names rather than hides: naïve credit assignment when several lessons enter one prompt, cold start paid deliberately during F0 shadow, a discounted posterior that assumes slow drift and needs an explicit reset on an abrupt model change, and BM25 being lexical and therefore due for replacement past roughly two hundred lessons. Experiential stores are also a poisoning surface, and the mitigations — sanitiser on `add`, mandatory provenance, receipts-only additions, promotion to a real skill only through quarantine — are part of the layer, not an afterthought.

## Plan

The implementation plan is **not** restated here, and it is not tracked here either. It lives in the implementation ledger named at the head of this document, as slices L0 through L16, each carrying its dependency, its deterministic gate, and its exit KPI per phase: pre-F0 documentation (L0–L1), F0 shadow (L2–L7), F1 active routing (L8–L11), F2 (L12–L14), F3 (L15–L16). That ledger also holds the ten binding execution rules, the target repo layout, the typed spec schema, and the adapter contract. This ADR is slice L0; every subsequent slice is one commit against one gate, and none of them starts while this document reads Proposed.

## Status note

This is commit C1 of the two-commit ADR cycle: Proposed, documentation only, followed by a hard stop. Human review is the acceptance gate. Commit C2 changes this document's status to Accepted and nothing else — no code, no second file. Slice L2 unlocks only after C2 lands.
