# ADR-002: Extract tier-resolution and constitution-hash checks into hermetically testable units

- **Status:** Accepted
- **Date:** 2026-07-17
- **Deciders:** Pietro Falco
- **Related:** ADR-001 (harness-pack deploy topology — Accepted). External code repos: harnesswright ADR-005 (the launcher consumes `next --json`; D4 pack-side model-string→tier resolution), verity ADR-004 (the gate). This ADR changes no semantics from either; it is a testability refactor of `scripts/launch_worker.sh`.

## Context

`scripts/launch_worker.sh` carries two fail-closed gates as inline `python3` heredocs: the pack-side tier resolution (spec.model → `model_tiers[model]` → `tiers[T].chain[0]`, applying the single-hop-**downward** `resolves_to` rule; ADR-005 D4, source `:131-155`) and the constitution hash pin (`:172-178`). Two fixtures in `tests/run_tests.sh` name these behaviors:

- "single-hop T0->T3 must be refused" (`:25-55`)
- "wrong constitution_hash_expected must be refused" (`:57-88`)

Recon at HEAD `c683fd0` confirms both fixtures assert nothing about the behavior they name. Each drives the *whole launcher* (`scripts/launch_worker.sh SPEC.md`), which fails closed at `next --json` (`:62-69`) on the tmp repo's missing `.harness/harness.json` long before control reaches either gate. The launcher exits non-zero for the wrong reason, and each fixture's `rc != 0` check passes on that early death. The post-`52c7da2` launcher rewrite (which introduced the `next --json` consumption) orphaned them: Fixture 1's `grep` target, the string `illegal resolves_to`, does not exist anywhere in the current source — the live refusal message is `STOP tier 'T0' has empty chain and no legal single-hop-downward resolves_to` (`:148`). So Fixture 1 is doubly dead: it never reaches the gate, and its assertion string would not match even if it did. Fixture 2's `grep` target `CONST-HASH-MISMATCH` is the real message (`:176`) but the code path is never reached.

Two ways to make the fixtures meaningful were weighed. Option (a): stand up a real `.harness/harness.json` + harnesswright dist so the launcher reaches the gates. Rejected — it re-couples the test to the exact external surface (`next --json` schema, dist layout) that rotted these fixtures in the first place, and a future launcher rewrite would rot them again. Option (b), taken here: make the two gates directly invocable in isolation, with no `next`/CLI/git/dist dependency, so the test exercises the gate logic itself and survives any launcher rewiring.

## Decision

### D1 — Extract the two gates into one standalone unit, `scripts/launch_checks.py`

The tier-resolution heredoc (`:131-155`) and the hash pin (`:172-178`) move verbatim (same branches, same messages, same f-strings) into `scripts/launch_checks.py`, exposed as two subcommands:

- `resolve-tier MANIFEST` (env `MODEL_STRING`) — resolves the model-string through `model_tiers`/`tiers` and the single-hop-downward `resolves_to` rule. Success → stdout `OK <tier> <model> <manifest_version>`, exit 0. Violation → stderr `STOP …`, exit non-zero.
- `check-hash CONST MANIFEST` — pins the constitution sha256 against `manifest.constitution_hash_expected`, fail-closed. Match (or no expected) → stdout `<sha256>`, exit 0. Mismatch → stderr `STOP: CONST-HASH-MISMATCH …`, exit non-zero.

### D2 — The launcher calls the unit; the unit is the single live implementation

`scripts/launch_worker.sh` replaces both inline heredocs with calls to `scripts/launch_checks.py` (resolved beside the launcher via `$0`, fail-closed if absent). There is no logic fork: the launcher and the test suite run the *same* code. The launcher's observable behavior is preserved byte-for-byte — the identical refusal message reaches the operator on stderr and the launcher still exits 1 on a refused resolution or a hash mismatch; the resolved `OK <tier> <model> <manifest_version>` line the launcher parses is unchanged.

### D3 — Both fixtures invoke the unit directly and assert the real message

The two fixtures in `tests/run_tests.sh` stop driving the whole launcher and instead call `scripts/launch_checks.py` with an illegal-hop manifest / wrong-hash input, asserting `rc != 0` **and** that stderr carries the message the current source actually emits (`no legal single-hop-downward resolves_to`; `CONST-HASH-MISMATCH`) — not the dead `illegal resolves_to` string. Each fixture also gains a positive companion (a legal single-hop-down resolves; a correct hash passes) so the suite proves the extraction did not simply hardcode failure.

## Non-goals

This ADR changes **no** tier or hash semantics. The legal/illegal-hop decision (ADR-005 D4), the fail-closed hash pin, and every `STOP` message are preserved verbatim; only their I/O contract changes — a refusal now exits non-zero with its message on stderr, where before it printed a `STOP` line on stdout that the launcher re-emitted to stderr itself. It does not alter `next --json` consumption, the verity gate, receipt writing, or the DRYRUN affordance. It does not parameterize the tier/hash surface (a clean follow-on, HP-ADR-003, is unblocked by this extraction).

## Alternatives considered

- **Stand up a real `.harness` repo + harnesswright dist for the fixtures (option a)** — rejected: re-couples the test to the exact external surface that rotted these fixtures, and would rot them again on the next launcher rewrite.
- **Leave the gates inline and duplicate their logic in the test** — rejected: a logic fork means the test and the launcher can drift; the extracted unit guarantees they are one implementation.
- **Delete the two dead fixtures** — rejected: the behaviors they name (single-hop-downward refusal, hash-pin fail-closed) are load-bearing gates that must stay under test.

## Consequences

- The test baseline goes green **and** meaningful: the two named fixtures now prove the refusal logic they name, via hermetic unit invocation with no `next`/CLI/git/dist dependency.
- The two gates survive a future launcher rewrite: the fixtures target `scripts/launch_checks.py`, not the launcher's external contract.
- A clean HP-ADR-003 that parameterizes this same tier/hash surface is unblocked.
- `scripts/launch_worker.sh` gains one runtime dependency (`scripts/launch_checks.py`, resolved beside it, fail-closed if missing); `just deploy` already copies the whole `scripts/` dir into the enforced copy, so no deploy change is required.
