---
id: RS-001
title: receipt-rollup (recurring)
tier: T2
mode: B
effort: low
budget:
  max_turns: 15
  wall_clock_min: 20
tools: "Read,Bash,Grep,Glob"
trigger:
  check: scripts/rollup_due.sh
  semantics: exit 0 = due (loose receipt count >= threshold; threshold parametric, default 25), exit 1 = not due
scope:
  paths: ["<RECEIPTS_DIR>"]
criteria:
  - text: every file in the R1 snapshot is chained and archived
    verify: gate
  - text: receipt-chain.jsonl hash chain valid end-to-end
    verify: gate
  - text: receipts-index co-indexed to the chain (equal length; for all i index[i].seq==chain[i].seq and index[i].source_sha256==chain[i].sha256)
    verify: gate
stop_conditions:
  - gate failure (never auto-retry)
  - any D entry in git status --porcelain (renames only)
  - chain line delta != R1 snapshot count
  - index line delta != R1 snapshot count
  - receipts_index.py gate exit != 0
  - budget exhausted
destructive_ops: none
---

## Intent
Consolidate loose run receipts into the append-only, hash-chained
<RECEIPTS_DIR>/receipt-chain.jsonl and archive originals via git mv
(never rm).

Additionally, project each rolled-up receipt into the append-only
<RECEIPTS_DIR>/receipts-index.jsonl beside the chain (ADR-005 D2/D3),
co-indexed by seq. receipt_chain.py and the chain format are unchanged;
the index is purely additive and this rollup is its single writer.

## Path binding (execution-time, L-008)
<RECEIPTS_DIR> and <ARCHIVE_DIR> bind from literal repo state in R1.

## Concurrency
Take a path-scoped lease on <RECEIPTS_DIR>. The R1 snapshot list IS
the scope: receipts appearing after R1 are out of scope for this run
(TOCTOU-proof) and left untouched. The lease also covers
<RECEIPTS_DIR>/receipts-index.jsonl beside the chain.

## Steps
- R1 (recon): list loose *.receipt.json -> ordered snapshot (filename
  lexicographic), record count N. Literal stdout is the baseline.
- R2: python3 scripts/receipt_chain.py append
      --chain <RECEIPTS_DIR>/receipt-chain.jsonl --run-id <RUN_ID>
      <each R1 file in order>
- R2b: python3 scripts/receipts_index.py append
       --index <RECEIPTS_DIR>/receipts-index.jsonl
       <each R1 file in order>   (same order as R2; ADR-005 D3 single writer)
- R3: git mv each original to <ARCHIVE_DIR>/ (explicit paths, no -A).
- R4: tail -3 of the chain and of receipts-index.jsonl (cat-after-write);
      python3 scripts/receipts_index.py gate --index <RECEIPTS_DIR>/receipts-index.jsonl
        --chain <RECEIPTS_DIR>/receipt-chain.jsonl (must exit 0, co-indexing receipt);
      full git status --porcelain as receipt (only R entries + chain M/A;
      the index is gitignored and does not appear).
- R5: single atomic Conventional Commit (chore scope).

## Resume semantics
On interruption: set difference (R1 list minus already archived),
continue only those. All claims evaluate against the R1 list.

## Claims (deterministic receipts)
- V1: chain line delta == N (R1 count)
- V2: archived file count delta == N
- V3: every R1 file archived; files not in R1 untouched
- V4: git status --porcelain contained zero D entries during run
- V5: per appended line, sha256 matches archived file raw bytes
- V6: receipt_chain.py verify exits 0 on the full chain
- V7: tier_resolved recorded with manifest_version in the run receipt
- V8: receipts_index.py gate exits 0 — index and chain equal length and,
      for all i, index[i].seq==chain[i].seq and
      index[i].source_sha256==chain[i].sha256 (co-indexing, ADR-005 D2/D3)
Claim registration binds to the verity CLI contract at implementation
time (recon on verity, L-008); claim shapes are never authored from
memory.
