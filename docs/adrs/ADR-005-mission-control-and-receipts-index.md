# ADR-005: Mission-control dashboard & receipts-index rollup projection

- **Status:** Accepted
- **Date:** 2026-07-22
- **Deciders:** Pietro Falco
- **Related:** ADR-001 (enforced deploy topology, Accepted; the enforced copy under `$HARNESS_ROOT` is root-owned and the worker-side `.harness/pack` is a symlink into it, so `.harness/pack/receipts` is read-only and never a write target, D1 here). ADR-002 (hermetic launch checks, Accepted; `resolve-tier` in `scripts/launch_checks.py` stays the single live model resolver, reused by the model-preview ergonomics with no logic fork). ADR-004 (parameterized topology & sanitization, Accepted; its privacy-lint claim set in `.verity/claims.json` is the invariant every tracked artifact of this ADR must keep green, placeholders only, D5 here). RS-001 (`specs/recurring/RS-001-receipt-rollup.md`, the recurring rollup slice this ADR makes the single writer of the receipts-index). Cross-repo, qualified: **harnesswright** ADR-005 D4 (that is harnesswright's own ADR-005 in a different repo, the pack-side model-string to tier resolution the launcher consumes, not this document) and harnesswright's slice-ledger (`README.md:120-121`, whose claimed term "ledger" this ADR deliberately avoids); **verity** ADR-004 (the gate). Those three are external and only referenced. This ADR decides; implementation is one or more separate slices against it; no script, Justfile, template, or code is edited here.

## Context

Mode B operational state is scattered across four surfaces that never meet: loose per-run receipts (`<run_id>.receipt.json` plus `<run_id>.cc.json`, written by `scripts/launch_worker.sh:293-309`), the append-only hash-chained integrity log (`receipt-chain.jsonl`, `scripts/receipt_chain.py`), `git log`, and `harnesswright next --json`. There is already an embryonic dashboard, `scripts/harness_stats.py`, which emits `stats.md` plus `dashboard.html` (both gitignored) with per-run flags, stdlib only, no server. It is the right shape and the wrong reach.

Three facts from recon shape this decision:

- **The dashboard goes blind after rollup.** `harness_stats.py:14` reads only loose `*.receipt.json`. The recurring rollup RS-001 appends each receipt to the chain and then archives the originals via `git mv` (never `rm`), so once a rollup runs, the rolled-up history disappears from the dashboard's only input.
- **The chain cannot fill that gap.** A chain line carries integrity metadata alone: `seq`, `prev_sha256` (sha of the previous line text), `sha256` (of the source file bytes), `source_filename`, `rolled_up_at`, `run_id` (`scripts/receipt_chain.py:50-53`; sample in `examples/receipt-chain.sample.jsonl`). It carries no `total_cost_usd`, `num_turns`, `tier_resolved`, or `subtype`. It also cannot be joined to a run by id: the chain line's `run_id` is the rollup operation's id (sample value `sample-rollup-2026-07-13`), not the individual run's `run_id`.
- **The receipt write path already diverges on where receipts live.** `launch_worker.sh:45` writes to `./.harness/receipts`, but `scripts/rollup_due.sh:7` and `harness_stats.py:30` both default to `./.harness/pack/receipts`. `.harness/pack` is the worker-side symlink into the enforced, root-owned copy (ADR-001), so it is read-only and cannot hold live receipts. The three defaults must collapse to one canonical writable directory.

Two invariants constrain any answer. First, concrete model IDs never appear in tracked files: specs and governance name tiers (T0-T3) or `*_CLASS_MODEL` placeholders, and `.verity/claims.json` enforces this with the `privacy-lint-model-id` claim (`README.md:116-119`). Second, the pack ships no always-on service: the dashboard is a generated file, not a server (`README.md:141-144`). A receipt schema drift is also live and must be tolerated, not fixed by this ADR: `templates/receipt.schema.json` still requires `tier_requested` with no `model_string`, while the launcher now writes `model_string`/`tier_resolved`/`model_used` with no `tier_requested`, and the on-disk sample receipt matches the older shape.

This ADR introduces a data projection that survives archival, canonicalizes the receipts directory, and turns `harness_stats.py` into a mission-control renderer, without touching the chain's format or `receipt_chain.py`.

## Decision

### D1 - Canonical receipts directory is `./.harness/receipts`

The one writable receipts directory is `./.harness/receipts`, the path `launch_worker.sh:45` already writes to, resolved relative to the target repo root (the same root the HALT check anchors on, `launch_worker.sh:52`). The implementation slice aligns `rollup_due.sh` and `harness_stats.py` to read from that path. `.harness/pack/receipts` is retired as a default: it points into the enforced, root-owned copy through the `.harness/pack` symlink (ADR-001), which is read-only by construction and must never be a read or write target for live receipts.

### D2 - `receipts-index.jsonl`, an append-only projection co-indexed to the chain by `seq`

A second append-only artifact, `receipts-index.jsonl`, sits beside the chain and carries the distilled per-run fields the views need. One compact JSON object per line, `sort_keys` for determinism, co-indexed to the chain so that index line `i` and chain line `i` describe the same rolled-up receipt:

```json
{"seq": 1, "run_id": "run-...", "spec_id": "S-...", "type": "chore",
 "mode": "B", "model_string": "executor", "tier_resolved": "T2",
 "model_used": "SONNET_CLASS_MODEL", "subtype": "success",
 "num_turns": 5, "total_cost_usd": 0.178, "duration_ms": 52144,
 "started_at": "...", "ended_at": "...", "stop_reason": "gate-pass",
 "gate_verdict": "PASS", "constitution_hash": "...", "manifest_version": 1,
 "source_filename": "run-....receipt.json", "source_sha256": "..."}
```

The invariants are `index[i].seq == chain[i].seq` and `index[i].source_sha256 == chain[i].sha256`. The join between the two artifacts is always by `seq` (equivalently by `source_filename`), and **never by `run_id`**: the chain's `run_id` names the rollup, not the run, so a run_id join would be wrong. `total_cost_usd` and `duration_ms` are nullable, because on an auth mode without standing API keys the cost fields can be absent (`README.md:135-136`), in which case `num_turns` is the budget signal.

### D3 - Single writer: the RS-001 rollup

`receipts-index.jsonl` is written only by the RS-001 rollup, in the same lexicographic snapshot order (RS-001 step R1) in which the chain is appended. The rollup gains one added step: for each receipt it appends to the chain, it appends the distilled line to the index. `receipt_chain.py` and the chain's format are unchanged; the index is purely additive. The `~25` loose-receipt trigger (`rollup_due.sh`) and the `git mv` archival (never `rm`) are unchanged. A single writer plus co-indexing keeps the two files from drifting apart, and the rollup gate asserts it (index line delta equals chain line delta equals the R1 snapshot count).

### D4 - Schema-tolerant reader

Every reader of receipts and of the index tolerates the live schema drift rather than assuming one shape. When `model_string` is absent it falls back to `tier_requested`; any field absent from a given receipt shape reads as `null`. This keeps older receipts (and the on-disk sample) legible to the renderer and to the index writer without a migration, and without this ADR editing `templates/receipt.schema.json` (a separate housekeeping concern).

### D5 - Tooling and data are split across repos

The tooling is tracked in harness-pack and stays privacy-clean: the renderer, the index writer, and the `just` recipes carry only `*_CLASS_MODEL` placeholders and repo-relative paths, so ADR-004's privacy-lint claim set stays green. The data lives in the worker repos and is private: the real `*.receipt.json`, the populated `receipts-index.jsonl` (which will contain real `model_used`, cost, and session ids), and the generated `dashboard.html` are gitignored there, exactly as `receipts/` and `dashboard.html` already are. The tracked renderer reads data at run time and embeds no model id; the manifest map view (D6) shows placeholders in the public repo and resolves to real ids only against a private local manifest, whose output is gitignored. The pack ships no tracked, populated index.

### D6 - Render sources and views, read-only with graceful degradation

The renderer draws from, in order of centrality, and treats each as optional so a missing source degrades to "unavailable" rather than failing the render:

- `receipts-index.jsonl` (rolled-up history: cost, turns, tier, subtype, model per past run).
- loose `*.receipt.json` under the canonical directory (the tail since the last rollup).
- `receipt-chain.jsonl` plus `receipt_chain.py verify` (integrity: `seq` count and VALID/broken; the working-tree verify is advisory, the authoritative check is `git show HEAD:<chain>`, per `receipt_chain.py:14-20`).
- `harnesswright next --json` (the eligible slice), parsed defensively; the schema is derived from the launcher's consumer (`launch_worker.sh:117-156`) and is not verified against a live harnesswright at authoring time.
- `git log --oneline` (operator commits: rollups, ADR propose/accept, deploy markers).
- `.harness/HALT` presence (the kill-switch state).
- `scripts/detect_tamper.sh` exit (enforced-tree integrity).

The views are: recent runs (union of index and loose receipts, showing run, spec, type, the resolved `model_string -> tier -> model_used`, turns, cost or a dash when null, subtype, gate verdict, stop reason, flags); chain status; eligible slice; HALT state banner; and enforced-tree integrity.

### D7 - HTML static is primary, `stats.md` secondary, Obsidian Base rejected for telemetry

The primary rendering is a static HTML file, extending `harness_stats.py`'s existing `dashboard.html` (gitignored, stdlib only, no server, generated on demand). `stats.md` stays as a secondary Markdown emission (already produced), which the vault can embed if the operator wants a view there. An Obsidian Base is rejected for the telemetry surface: it would couple gitignored runtime telemetry to the vault, a knowledge and governance surface the README keeps separate from the pack, and Bases operate over vault Markdown notes rather than runtime JSONL, so the data has the wrong home. HTML honors every Mode B non-goal (no daemon, no LLM judgment, no always-on service) and opens in any worker repo, inside the vault or not.

### D8 - MVP scope is per-repo

The dashboard scope is a single repo's runtime state. A cross-repo aggregated view (fleet-wide, unioning the worker repos listed in `workers.local.json`) is an explicit v2 and is out of scope here. Nothing in D1-D7 precludes it: the per-repo `receipts-index.jsonl` is the natural aggregation unit a v2 would union.

### D9 - Optional one-way notification sink (activatable, off by default)

Run-state transitions (a run halting, a gate failing, a rollup landing, HALT arming) may optionally fire a fire-and-forget notification through a Claude Code Notification/Stop hook: always a desktop notification, and, if the operator opts in, a single Telegram sendMessage. The sink is off by default, one-way only, and carries no model id (tiers or placeholders only, per D5). It plants no listener and no daemon: one outbound call at a lifecycle event, consistent with the no-always-on non-goal. A two-way responder (approving or releasing a gated decision from Telegram) is out of scope here and deferred to the autonomy ADR, where sender-identity verification and the reply-releases-but-never-redefines-the-gate contract are decided.

## Non-goals

- No script, Justfile, template, or code is edited now. Implementation is one or more separate slices, eligible only once this ADR is Accepted.
- The `run_id` drift is not decided here. The launcher's `run_id` (`launch_worker.sh:192`) is generated independently of verity's report id and of harnesswright's slice identity, so a receipt cannot yet be joined to its verity report (evidence: a receipt `run-...145614Z-63495` alongside a verity report `run-...145635Z-63621` in the same run). That is a separate follow-on ADR. The MVP does not depend on it: the chain-to-index join is by `seq` and holds without it. Resolving it later enriches the dashboard with a verity-report-per-run column; it does not block the MVP.
- The cross-repo aggregated fleet view is v2 (D8).
- No architectural explainer via archify. The existing pre-rendered mermaid pipeline (`docs/diagrams/*.mmd` plus PNG assets, referenced from the README) remains the documentation norm for architecture diagrams.
- The chain format and `receipt_chain.py` are not changed; the index is additive.
- `templates/receipt.schema.json` is not reconciled here; D4 tolerates the drift, and updating the schema is separate housekeeping.
- The receipts-index is a data substrate only. Its consumption for autonomous case-based reuse or recursive learning is a separate future ADR, not decided here; readers of the index may propose but never redefine what a gate counts as PASS.

## Alternatives considered

- **Extend the chain line with telemetry fields (cost, turns, tier).** Rejected: it bloats the integrity record, couples the tamper-evidence artifact to schema-drifting data, and breaks the clean hash-only chain contract. A separate co-indexed projection keeps integrity and data orthogonal, and leaves `receipt_chain.py` untouched.
- **Name the artifact `receipts-ledger.jsonl`.** Rejected: "ledger" is the harnesswright slice-ledger's claimed term, and `README.md:120-121` states the distinct name is on purpose. `receipts-index.jsonl` avoids the vocabulary collision.
- **Render into an Obsidian Base.** Rejected (D7): wrong home for gitignored runtime telemetry, and Bases operate on vault notes, not JSONL.
- **Keep reading only loose receipts (the status quo).** Rejected: the dashboard goes blind after RS-001 archives the originals; the index is exactly what survives the `git mv`.
- **Join the chain and the index by `run_id`.** Rejected: the chain's `run_id` is the rollup id, not the run's (recon on `examples/receipt-chain.sample.jsonl`); `seq` plus `source_filename` is the correct join.
- **Keep `.harness/pack/receipts` as a read default and copy receipts there.** Rejected: it is the enforced, root-owned tree via the `.harness/pack` symlink (ADR-001), read-only by design; canonicalizing on the writable `./.harness/receipts` (D1) removes the divergence without weakening the enforcement topology.

## Consequences

Positive:

- The dashboard survives rollup: rolled-up history stays queryable from `receipts-index.jsonl` with no need to re-read archived receipt JSONs.
- One canonical receipts directory ends the three-default divergence (D1).
- Integrity and data stay orthogonal: the chain is unchanged and the index is additive, so the tamper-evidence guarantees are untouched.
- The privacy invariant holds: tracked tooling carries only placeholders, and real ids live only in gitignored worker-repo output (D5), so ADR-004's privacy-lint stays green.
- Token-zero, deterministic, on demand: no new runtime service, consistent with the pack's non-goals.

Accepted negatives:

- A second append-only artifact must stay in sync with the chain. Mitigated by the single writer (D3), co-indexing by `seq`, and a rollup gate asserting index line delta equals chain line delta.
- The index denormalizes several receipt fields. Accepted as the price of querying history without reading archived files.
- The eligible-slice and enforced-integrity views depend on external tools (harnesswright, `detect_tamper.sh`) and degrade to "unavailable" when those are absent (D6).

Risks:

- A worker repo that mistakenly tracks `receipts-index.jsonl` would leak real model ids, cost, and session data. Mitigation: the implementation slice extends the worker-repo gitignore convention (alongside `receipts/`), and the pack ships no tracked, populated index.
- The `next --json` schema is derived, not verified against a live harnesswright at authoring time, so the eligible-slice view must be parsed defensively and kept optional (D6).
- The `run_id` drift remains until the follow-on ADR, so the MVP omits the verity-report-per-run column rather than guessing a join.

## Status note

Accepted via the two-commit lifecycle: the original Proposed commit, then a separate Accept commit after operator review. Implementation slices are now eligible against this ADR. This document decides only what to build and where the artifacts live; it edits no code.
