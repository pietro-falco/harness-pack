# ADR-004: Parameterized topology & sanitization (supersedes ADR-001 literals)

- **Status:** Proposed
- **Date:** 2026-07-17
- **Deciders:** Pietro Falco
- **Related:** ADR-001 (enforced deploy topology — Accepted; its literal path/uid/group **values** are superseded here, its structural property is not — see D1), ADR-002 (hermetic launch checks — Accepted; makes `tests/run_tests.sh` a meaningful gate), ADR-003 (canonical stack doc & agent-contract home — Accepted; owns the docs, D6 boundary). Vault ADR-057 (ownership trust boundary) and ADR-058 ("concrete path pinned after recon") — the properties this ADR preserves while de-literalizing. Vault ADR-059 D9 (README vault-section already sanitized in S-SR-001). This ADR decides; implementation is slice **S-SR-002**; no code, launcher, or Justfile is edited here.

## Context

harness-pack is being prepared for public release, and recon shows tracked files carry the operator's machine specifics as literal values:

- The launcher's harnesswright/verity fallback defaults hardcode the operator's home layout: `scripts/launch_worker.sh:36` `HW_CLI="${HARNESSWRIGHT_CLI:-$HOME/Code/harnesswright/dist/cli.js}"` and `:42` `VERITY_CLI="${VERITY_CLI:-$HOME/Code/verity/dist/cli.js}"` (also the doc comment `:11`).
- The Justfile enumerates the operator's private worker repos by name: `Justfile:46-48` — `$HOME/Code/harness-sandbox`, `$HOME/Code/harness-smoke`, `$HOME/Code/verifiable-intel`.
- ADR-001 itself states machine literals: the dev tree `~/Code/harness-pack` "owner 501" and "the worker (uid 501, group admin)" (`ADR-001:10`, `:14`); the enforced copy `/opt/harness`, `root:wheel`, mode 755, "uid 501 is not in `wheel`", group `admin` "of which the operator is a member" (`:27`); the guard path `/opt/harness/scripts/guard_pretooluse.py` (`:31`); the three worker repo names (`:59`).
- Two wording items describe the operator's plan rather than the pack's capability: `docs/RISKS.md:16` "Cost fields on subscription auth may be absent/zero" and `README.md:157` "On subscription auth, per-run cost fields may be null".

These literals were correct when ADR-001 pinned them (vault ADR-058: "concrete path pinned after recon — never assumed"), but for a public artifact they are a disclosure surface: home layout, operator uid, privileged group, and private worker-repo names. ADR-001's **structural decision** — an enforced copy that is root-owned, not writable by the operator uid, with symlink-independent guard resolution — remains exactly right; only its concrete **values** must stop being tracked literals. This ADR de-literalizes those values into parameters, redirects the launcher/Justfile resolution onto house conventions already present in the repo, rewords the capability phrasing, and fixes the gate S-SR-002 must pass. It edits nothing now — implementation is S-SR-002.

The recon also confirms the conventions to reuse (invent nothing new): the `*.example.json` → untracked `*.local.json` env-override pattern (`scripts/launch_worker.sh:28` `MANIFEST="${HARNESS_MANIFEST:-$HARNESS_HOME/templates/manifest.example.json}"`; README `:99-103` copies it to `model-manifest.local.json` and points `HARNESS_MANIFEST` at it); `command -v` for binary resolution (`scripts/launch_worker.sh:177-178`); and `*.local.json` already gitignored (`.gitignore:2`).

## Decision

### D1 — Supersession scope: literal values, not the property

This ADR **supersedes** the following ADR-001 items, replacing their tracked literals with parameters (D4): the dev-tree literal `~/Code/harness-pack` (`ADR-001:10`, `:14`); the enforced-location literal `/opt/harness` and the literal guard path `/opt/harness/scripts/guard_pretooluse.py` (`:27`, `:31`); the operator-identity literals `uid 501` and group `admin` (`:10`, `:14`, `:27`); and the worker-repo names (`:59`, externalized per D3). It **leaves intact** ADR-001's structural property in full: the enforced copy is root-owned, lives where no ancestor is writable by the operator uid, the guard resolves by an absolute path independent of any symlink, the detect gate stays a standalone operator act, and `just deploy` under sudo remains the sole dev→enforced bridge (ADR-001 D1–D6). Only the path/uid/group **values** become parameters. ADR-001 stays immutable and is superseded by reference (house style; Accepted ADRs are not edited).

### D2 — Launcher CLI resolution via installed binaries, not home paths

**Finding:** `scripts/launch_worker.sh:36`/`:42` default to `$HOME/Code/harnesswright/dist/cli.js` and `$HOME/Code/verity/dist/cli.js`. **Decision:** the fallback defaults change to `command -v harnesswright` / `command -v verity` (installed bins on `PATH`), matching the existing `command -v` house style (`:177-178`), and error with actionable guidance ("install harnesswright / set HARNESSWRIGHT_CLI") when neither the env override nor an installed binary resolves. The existing `HARNESSWRIGHT_CLI` / `VERITY_CLI` env overrides remain the first-precedence path (unchanged). No literal home path survives as a tracked default, in the code or its doc comment (`:11`).

### D3 — Worker list externalized to an untracked file

**Finding:** `Justfile:46-48` hardcodes the operator's three worker-repo paths. **Decision:** the worker list moves to an untracked `workers.local.json`, mirroring the repo's existing `*.local.json` convention (recon 4d); the Justfile reads that file at recipe time. `*.local.json` is already gitignored (`.gitignore:2`), so no worker-repo name or home path remains tracked. A `workers.example.json` (tracked, placeholder paths) documents the shape, mirroring `manifest.example.json`.

### D4 — Topology parameterization in ADR/doc prose

**Finding:** ADR-001's literals (recon 4c) disclose machine specifics. **Decision:** those literals become named parameters wherever the topology is described publicly: `$PACK_SRC` (the dev tree), `$HARNESS_ROOT` (the enforced copy), "the operator uid" (not `501`), and "the privileged group" (not `admin`). The enforced location stays **defined as a property** — root-owned, no ancestor writable by the operator uid — with the concrete path pinned at implementation time against a fresh ancestor-chain recon (unchanged from ADR-001/ADR-058, only de-literalized). The public text states the property without disclosing the operator's machine.

### D5 — Wording sanitization

**Finding:** `docs/RISKS.md:16` and `README.md:157` say "subscription auth". **Decision:** reword to a capability statement — "auth mode without standing API keys" — describing what the pack supports, not the operator's billing plan. The README vault-section debt is already resolved (S-SR-001, vault ADR-059 D9) and is noted here as done, not re-decided.

### D6 — Enforcement: the S-SR-002 gate

**Decision:** S-SR-002's acceptance gate is (1) a deterministic privacy-lint claim set — grep-zero across tracked files for the vault name, `/Users/` paths, the operator-uid pattern, the worker-repo names, and a real model-ID regex outside declared allowlists; (2) `tests/run_tests.sh` green (meaningful post-ADR-002); and (3) gitleaks clean. The claim set itself is authored in S-SR-002 (verity criteria), not here; this ADR fixes only *what* it must assert.

## Non-goals

- Not editing `scripts/launch_worker.sh`, the `Justfile`, `.gitignore`, `docs/RISKS.md`, or `README.md` now — all implementation is S-SR-002 against this ADR.
- Not touching ADR-001 — it is immutable and superseded by reference (D1).
- Not the harnesswright/verity-side literals — those are their own repos' slices.
- Not authoring `docs/STACK.md` or any `CLAUDE.md` — that is ADR-003's scope (S-SR-003), a separate slice.
- Not publishing harness-pack — publication is a separate operator gate after S-SR-002's privacy-lint is green.

## Boundary restatement

This ADR owns paths / launcher / Justfile / wording (the sanitization surface). ADR-003 owns the docs (`docs/STACK.md`, the `CLAUDE.md` projections). S-SR-002 (this ADR's implementation) and S-SR-003 (ADR-003's authoring) are separate slices on separate ADRs and must not be merged.

## Alternatives considered

- **Keep ADR-001's literals and scrub only at publish time** — rejected: the literals sit in tracked history and the launcher's real default; a publish-time scrub leaves the disclosure in git history and in every clone of the working tree.
- **Hardcode a public default path (e.g. `/opt/harness`) instead of parameterizing** — rejected: re-pins a machine-specific value as if universal; D4's property-plus-recon pin is what ADR-058 already prescribes.
- **Invent a new config mechanism for the worker list** — rejected: the repo already has the `*.local.json` env-override convention (recon 4d); reusing it (D3) avoids a second pattern to maintain.
- **Relicense/rewrite ADR-001 in place** — rejected: Accepted ADRs are immutable; supersession by reference is house style.

## Consequences

- On acceptance, slice S-SR-002 becomes eligible with D2–D6 as its spec.
- harness-pack becomes publishable only once S-SR-002's privacy-lint claims (D6) are green — publication remains a separate operator gate.
- ADR-001 remains the authoritative record of the *why* of the enforced-copy topology; this ADR is the authoritative record of the *values* being parameters, read together with it.
- A `workers.example.json` / `workers.local.json` pair enters the repo's convention set alongside `manifest.example.json` / `model-manifest.local.json` (S-SR-002).
