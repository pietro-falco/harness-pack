---
id: S-XXX            # one-shot slices: ledger numbering. Recurring: RS-XXX
title:
tier: T2             # T0..T3 semantic only; model names are forbidden here
mode: A              # A|B; B legal only if computed eligibility is B
effort: low          # low|high
budget:
  max_turns: 15
  wall_clock_min: 20
  max_budget_usd:    # optional; may be inert on subscription auth
tools: "Read,Edit,Bash,Grep,Glob"   # passed to --allowedTools in Mode B
trigger:
  check:             # deterministic command, exit-code semantics
  semantics:
scope:
  paths: []          # explicit path list; lease these if parallel
  repos: []          # cross-repo work is never implicit
criteria:
  - text:
    verify: gate     # gate (deterministic) | review (human judgment)
stop_conditions:
  - gate failure (never auto-retry)
  - budget exhausted
destructive_ops: none   # or quoted operator directive (L-021)
---

## Intent

## Path binding (execution-time, L-008)
All placeholders bind from recon output, never from authoring memory.

## Steps
- R1 (recon):

## Claims (deterministic receipts)
- V1:
