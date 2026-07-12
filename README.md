# harness-pack

Governance pack for autonomous agent harnesses: a permanent worker
constitution, capability-tier model routing, hash-chained run receipts,
spec/receipt templates, a fail-closed PreToolUse guard, and an
on-demand stats dashboard. Zero runtime dependencies beyond Python 3
stdlib and bash.

Thesis: an agent's "done" is a claim, not a fact. Everything here
exists to turn claims into deterministic receipts.

Companion projects: harnesswright (evidence-gated slice ledgers),
verity (deterministic claim verification).

## Contents
- CONSTITUTION.md — guardrails injected verbatim into every worker run;
  its sha256 is recorded in every receipt as constitution_hash.
- templates/ — spec skeleton, receipt schema, model manifest example,
  Mode B settings (deny rules + guard hook).
- scripts/ — guard_pretooluse.py (fail-closed G3 enforcement),
  launch_worker.sh (tier resolution, constitution injection, receipt
  writing), receipt_chain.py (append-only hash-chained JSONL),
  harness_stats.py (stats.md + dashboard.html from receipts),
  lint_specs.py (schema/mode consistency).
- specs/recurring/ — RS-001 receipt-rollup, the canonical recurring
  deterministic slice.
- tests/ — fixtures and runner; CI runs them on every push.

## Vocabulary (aligned with harnesswright/verity)
- Criterion verification path: verify: gate (deterministic) or
  verify: review (human judgment). Mode B is legal only when every
  criterion is verify: gate and no destructive op is in scope.
- Tiers T0..T3 are semantic capability levels. Model names never
  appear in specs or governance; binding lives in a local
  model-manifest (see templates/manifest.example.json).
- receipt-chain.jsonl is the append-only, hash-chained evidence log.
  It is not a harnesswright slice ledger; the name is different on
  purpose.

## Non-goals
No LLM-as-judge gates. No auto-retry of failed gates. No always-on
services; the dashboard is generated on demand.
