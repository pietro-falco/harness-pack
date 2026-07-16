# Risk register (operational Rumsfeld matrix + threat model)

## Known knowns
- Top available tier is operator-dependent and changes without
  notice; governance is model-agnostic by construction (tiers +
  manifest indirection).
- Deterministic gates work as stop conditions (validated in
  production by a real gate-failure stop).
- Guard false positives are accepted by design (fail-closed); escape
  hatch is Mode A with operator directive, never a bypass.

## Known unknowns (each with a containment seam)
- Claude Code CLI/hooks contract drift -> launch_worker.sh,
  settings.mode-b.json and guard_pretooluse.py are the only seams;
  verify flag/field names against current docs at wiring time.
- Cost fields, on an auth mode without standing API keys, may be
  absent/zero -> receipts treat total_cost_usd as nullable; num_turns
  is the primary budget signal.
- Hook env-var expansion is allowlist-gated in some configurations ->
  settings notes it; tests bypass settings and test the script
  directly.

## Unknown knowns (tacit assumptions made explicit)
- Single-writer on the chain -> path-scoped lease + R1 snapshot
  scope (TOCTOU-proof).
- "All loose receipts" was a mobile scope -> frozen at R1.
- Git rename detection -> V4 verifies renames-only literally.
- Timestamps -> UTC ISO 8601 everywhere, ordering is deterministic.

## Unknown unknowns (contained, not predicted)
Hard budgets, HALT kill-switch, stop-on-anomaly, append-only
hash-chained evidence: novel failures surface as gate failures with
receipts, never as silent corruption. Every occurrence feeds a
lesson candidate.

## Threat model notes
- Prompt injection via file/tool content -> constitution G7 +
  WebFetch/WebSearch denied by default in Mode B settings.
- Secrets in receipts/transcripts -> receipts carry metadata and
  hashes, never raw transcript content; transcript retention is an
  operator policy (receipts permanent, transcripts N days); secret
  scanning gates the public repo.
- Torn final line in the chain (crash mid-append) -> verify fails
  loudly; repair is destructive (G3), operator directive + erratum.
- Guard regex gaps -> two independent layers (declarative deny rules
  + hook); gaps become fixtures, fixtures become releases.
- Chain guarantee boundary: verify alone cannot detect final-line
  mutation or clean tail truncation; the committed blob is the anchor.
  Authoritative verification reads the chain from git
  (git show HEAD:<chain>) — RS-001's atomic commit exists to enable
  exactly this.
