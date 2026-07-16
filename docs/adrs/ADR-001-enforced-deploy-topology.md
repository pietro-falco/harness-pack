# ADR-001: Enforced-pack deploy topology — root-owned enforced copy, absolute guard resolution, and the detect gate

- **Status:** Accepted
- **Date:** 2026-07-16
- **Deciders:** Pietro Falco
- **Related:** vault ADR-057 (harness tamper-resistance & guard trust boundary — Accepted); vault ADR-058 (harness enforcement topology: deploy-split, symlink-independent guard resolution — Accepted); vault ADR-054 (harness deployment topology + Mode B preconditions — Accepted); vault ADR-022 (code-repo conventions & ADR namespace). External code repo: harnesswright ADR-005 (the launcher consumes `next --json`). This is harness-pack's first project ADR; it opens harness-pack's ADR sequence at ADR-001 per vault ADR-022 §1, independent of the vault and harnesswright sequences.

## Context

Vault ADR-057 established that the guard's trust boundary must rest on ownership, not on an in-place file lock, and rejected a same-owner `chmod` scheme: a worker that owns its enforcement surface can rewrite it. Vault ADR-058 chose the topology that realizes this — a deploy-split: the development source stays at `~/Code/harness-pack` (owner 501, git-seamless), and a distinct enforced copy, owned `root:wheel` and living outside any directory the worker (uid 501, group admin) can write, becomes the artifact the launcher runs; the guard resolves by an absolute path to that enforced copy, independent of any symlink. ADR-058 deliberately left two things to implementation-after-recon: the concrete enforced location (pinned, never assumed) and the code-side mechanism. This ADR is that realization.

Recon on the running system confirms the gap ADR-057/058 close:

- `HARNESS_HOME` is unset in the environment and every shell rc; it is defined only inside `scripts/launch_worker.sh` with a default of `$(dirname "$0")/..`, resolving to the dev tree `~/Code/harness-pack`. So `--settings`, `CONSTITUTION.md`, and the guard all resolve inside a tree owned by uid 501.
- `templates/settings.mode-b.json` wires the PreToolUse hook as `python3 "$CLAUDE_PROJECT_DIR/.harness/pack/scripts/guard_pretooluse.py"` — a symlink-relative resolution through the worker's own `.harness/pack`.
- `scripts/guard_pretooluse.py` denies `rm`/`rmdir`/`shred`/`git push --force`/`git reset --hard`/`git clean`/`filter-branch|repo`/`find -delete`/`--no-verify`/`git add -A|--all|-u`. It does not deny `ln`, `mv`, `chmod`, or `chflags` — the re-point hole this ADR's defense-in-depth layer addresses.
- Three worker repos carry `.harness/pack` symlinks, all pointing at the dev tree: `harness-sandbox`, `harness-smoke`, `verifiable-intel`.

## Decision

### D1 — Defense-in-depth deny surface (not the boundary)

The structural boundary is ownership (vault ADR-057) and the deploy-split (vault ADR-058); this layer adds to it and does not replace it. The mode-b settings template gains Bash denies for `ln` and `mv`, plus Edit/Write denies on any path under `.claude` or `.harness`; the guard's DENY list gains `ln` and `mv`. Rationale: with ownership as the real boundary, these denies exist to make a re-point attempt fail loudly inside a session, not to be load-bearing. A worker that somehow escaped the ownership boundary must not also find `ln`/`mv` available to re-point `.harness/pack`.

### D2 — Concrete enforced location: `/opt/harness`, `root:wheel`

The enforced copy lives at `/opt/harness`, owned `root:wheel`, mode 755. Recon walked the ancestry: `/opt` and `/` are both `root:wheel` 755, no group-write and no ACL at any level; uid 501 is not in `wheel`, so the worker cannot create, rename, or replace any node on that path without sudo. `/opt` is preferred over `/usr/local` (a conventional install target with more permission drift over time) and over `/Library/Application Support` (group `admin`, of which the operator is a member — one accidental `g+w` would open it). Pinned here per vault ADR-058's "concrete path pinned after recon — never assumed."

### D3 — The guard resolves by the absolute enforced path

`templates/settings.mode-b.json` rewrites its PreToolUse hook from the symlink-relative `$CLAUDE_PROJECT_DIR/.harness/pack/scripts/guard_pretooluse.py` to the absolute `/opt/harness/scripts/guard_pretooluse.py`. Guard resolution becomes symlink-independent (vault ADR-058): re-pointing a worker's `.harness/pack` cannot change which guard runs. `HARNESS_HOME` for a launch is set to `/opt/harness`, so `--settings`, `CONSTITUTION.md`, and the manifest all resolve to the enforced copy.

### D4 — The detect gate (standalone, operator-run, never invoked by the launcher)

A standalone preflight, owned by the operator and never called by the launcher (avoiding the circularity of a component vouching for itself), verifies before any Mode B run: (1) every worker `.harness/pack` resolves to the canonical `/opt/harness` — catching an `ln`/`mv` re-point; (2) the hash of each of {guard, settings, launcher, constitution, manifest} in the enforced copy equals its pin. Any mismatch is fail-closed: the gate exits non-zero and no run launches.

### D5 — `just deploy` is the sole dev→enforced bridge

The only sanctioned path from the dev tree to the enforced copy is `just deploy`, run under sudo (operator-gated): it copies the dev pack into `/opt/harness` as `root:wheel` and re-pins the D4 hash set on each deploy. There is no other write path to the enforced copy, and a worker cannot invoke it because it cannot elevate.

### D6 — The operator surface is a `just` recipe set

Four recipes: `deploy` (D5), `verify` (recompute and display enforced hashes vs pins), `preflight` (run the D4 detect gate), and `run` (`preflight && launch` — a run is gated on a green detect result). No always-on mechanism; every recipe is operator-invoked.

## Non-goals

This ADR does not change guard semantics beyond adding `ln`/`mv` to DENY (the existing deny list and the HALT walk-up stand verbatim). It does not re-decide the ownership boundary (vault ADR-057) or the deploy-split topology (vault ADR-058); it realizes them. It does not retarget the three worker symlinks — that is an operator act in a normal shell, out of band from any worker session (so it does not trip the D1 `ln` deny), an implementation step and not a decision here. It does not address the cross-repo ADR-index debt (three naming schemes, references by number without a bridge) — a separate governance session.

## Alternatives considered

- **In-place `chmod` lock, same owner** — rejected by vault ADR-057: a same-owner lock is not a boundary.
- **Enforced copy under `/usr/local`** — viable (root:wheel ancestry) but rejected as a conventional install target with more permission drift; `/opt` is cleaner and uncontested here.
- **Guard resolution left symlink-relative, deny surface as the only protection** — rejected: makes the defense-in-depth layer load-bearing, the exact inversion vault ADR-058 forbids.
- **Launcher runs the detect gate** — rejected: a component that vouches for its own integrity is circular; the gate is a standalone operator act (D4).

## Consequences

- The first real Mode B enforcement surface is a `root:wheel` copy at `/opt/harness` the worker cannot mutate; the dev tree stays git-seamless for authoring.
- The three worker symlinks (`harness-sandbox`, `harness-smoke`, `verifiable-intel`) must be retargeted from `~/Code/harness-pack` to `/opt/harness` as an operator step in a normal shell.
- The armed invariant — no unsupervised Mode B run until the deploy-split (vault ADR-058) and tamper-resistance (vault ADR-057) are Accepted and implemented — advances only when D1–D6 here are implemented and a supervised run over `/opt/harness` is green.
- A bidirectional discoverability bridge is due on accept per vault ADR-022 §4: a "## Vault ADRs affecting this project" section in harness-pack's CLAUDE.md/README, and a "## Project ADRs (code repo)" entry in the vault project hub.
