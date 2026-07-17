# Operator guide

How to run, gate, and recover a harness-pack deployment. This is the pack from the operator's chair: what a launch actually checks, what a receipt actually proves, and what to do when something goes red.

## Who this is for

You are the operator in a three-actor loop: you decide, an authoring model designs, Claude Code executes. The pack sits between the last two. It launches bounded runs, injects the constitution, blocks what the constitution forbids, and writes receipts that outlive the session.

This guide assumes working fluency with git and a POSIX shell. It does not teach Claude Code, prompt design, or spec authoring. It teaches the operational surface: setup, launch, gates, receipts, emergencies, upkeep.

One idea governs everything below: an agent's "done" is a claim, not a fact. Every mechanism in this pack exists to turn claims into machine-verifiable receipts, and every red light described here is the system refusing to accept a claim without one.

## First-time setup

Prerequisites: git, python3, node, the `claude` CLI, and GNU coreutils if you are on macOS and want wall-clock enforcement (`gtimeout`).

Wire the pack into the target repo as a symlink, so the repo carries a reference and not a copy:

```
ln -s /path/to/harness-pack .harness/pack
```

Install the two CLIs the launcher refuses to run without:

```
npm install -g harnesswright @pietro-falco/verity
```

Or point the launcher at local entrypoints with `HARNESSWRIGHT_CLI` and `VERITY_CLI`. Resolution is fail-closed: env override first, then PATH, then STOP with actionable guidance. Note that verity is resolved before Claude Code is ever invoked: a run whose claims cannot be gated must not start.

Create your manifest. The file in `templates/manifest.example.json` is config, not governance: copy it to a private location, edit freely, and point the launcher at it.

```
cp templates/manifest.example.json ~/private/manifest.json
export HARNESS_MANIFEST=~/private/manifest.json
```

Replace the placeholder model names in the tier chains with real ones. Model strings are opaque values to the pack; receipts record the resolved tier and `manifest_version`, never a hardcoded model policy.

Pin the constitution. `constitution_hash_expected` in the manifest must equal the sha256 of the exact `CONSTITUTION.md` bytes the launcher will inject:

```
shasum -a 256 CONSTITUTION.md
```

On mismatch the launcher stops before writing anything. This is the point: nobody edits the governance text without the manifest saying so.

Install the guard at its enforced path:

```
sudo mkdir -p /opt/harness/scripts
sudo cp scripts/guard_pretooluse.py /opt/harness/scripts/
```

The path is absolute by design. `templates/settings.mode-b.json` references `/opt/harness/scripts/guard_pretooluse.py` directly, never the pack symlink and never an env var, so a worker cannot retarget the guard by moving a symlink or shadowing a variable.

Validate the whole chain without side effects:

```
LAUNCH_DRYRUN=1 .harness/pack/scripts/launch_worker.sh specs/S-001.md
```

A dry run walks every gate up to and including tier resolution, prints the launch decision on one line, and exits before touching the constitution or invoking `claude`. If it prints `DRYRUN ok`, your setup is sound.

## Anatomy of a run

`launch_worker.sh SPEC.md` is a sequence of fail-closed gates.

The HALT check runs first, before any write and ahead of CLI resolution, so the emergency stop fires unconditionally even on a half-installed system. The launcher then resolves `harnesswright` and `verity`, stopping if either is missing, and locates `launch_checks.py` beside itself.

The slice you are requesting is derived from the spec filename only. The launcher never parses the spec: it asks `harnesswright next --json` for the resolved plan, run at the repo root, and decides from that machine output alone. The decision stops unless the plan kind is `unlocked`, the resolved id matches the requested id, the slice is Mode B eligible, `spec.model` is present, and `spec.tools` and `spec.criteria` are non-empty lists. Budgets are read, never defaulted: a declared dimension produces its flag, an undeclared dimension produces no flag at all.

The opaque `spec.model` string resolves pack-side through the manifest: `model_tiers[model]` names a tier, the tier's chain names a concrete model. A model string absent from `model_tiers` is a STOP, never a default. An empty chain resolves a single hop downward only (T0 to T1 is legal, T2 to T1 never).

With `LAUNCH_DRYRUN=1` the launcher stops here. Otherwise it pins the constitution hash and invokes `claude -p` with the resolved model, the constitution appended to the system prompt, the Mode B settings, the spec's tool allowlist, and the budget flags. Wall-clock enforcement wraps the command in `gtimeout` or `timeout`.

When Claude Code exits 0, the gate runs: `verity verify --json` over the target repo, judged against this slice's declared criteria only. The claim manifest is repo-level and accretes across slices, so the gate is scoped to `spec.criteria`, never to verity's overall verdict. The receipt is then written whatever happened, and the final exit code follows a strict rule: a Claude Code failure dominates and is returned as is; otherwise only an all-criteria PASS is success.

## Mode A vs B

Mode A is the human gate: you are present, you review, you accept. Mode B is the deterministic gate: the run is bounded, network-denied, and accepted only by verity. A spec may declare `mode: B`, but B is legal only when the computed eligibility is B, and the launcher enforces that through `next`.

Mode B containment is two independent layers. Layer one is the declarative deny list in `templates/settings.mode-b.json`: destructive git and shell patterns plus `WebFetch` and `WebSearch`, denied at the permission level, where no hook allow can bring them back. Layer two is the PreToolUse guard hook, which blocks even in `bypassPermissions` and matches every tool, not just `Bash`, because it also carries the HALT kill switch and must be able to neutralise `Edit` and `Write` mid-run.

Guard false positives are accepted by design. The escape hatch is a Mode A rerun with a quoted operator directive in `destructive_ops`, never a guard bypass.

## HALT drill

HALT is one file: `.harness/HALT` at the git root of the target repo. Its presence has two effects. New launches are refused before the first write, so a refused launch leaves nothing behind. Runs already in flight are neutralised on their next tool call, whatever the tool, because the guard checks HALT under a matcher of `*`.

Drill it until it is boring. Create it, confirm the refusal, remove it, confirm recovery:

```
touch .harness/HALT
LAUNCH_DRYRUN=1 .harness/pack/scripts/launch_worker.sh specs/S-001.md
rm .harness/HALT
LAUNCH_DRYRUN=1 .harness/pack/scripts/launch_worker.sh specs/S-001.md
```

The first dry run must STOP, the second must print `DRYRUN ok`. HALT is anchored to the git root and independent of `RECEIPTS_DIR`, so it works even when receipts are redirected.

## Receipt hygiene

A receipt is metadata and hashes, never transcript content: run id, spec id, resolved tier and model, manifest version, constitution hash, timestamps, turn count, gate verdict with item-level claims, and the reason the run stopped. On subscription auth `total_cost_usd` may be null; `num_turns` is the primary budget signal. Receipts are permanent; transcript retention is your policy, not the pack's.

Loose `*.receipt.json` files accumulate in the receipts directory. The recurring slice RS-001 consolidates them: each receipt is appended to the hash-chained `receipt-chain.jsonl`, originals are archived via `git mv` (never `rm`), and the whole rollup lands as one atomic commit. The trigger is `scripts/rollup_due.sh`, due at 25 loose receipts by default.

That atomic commit is not bookkeeping, it is the security anchor. A working-tree verify cannot detect a mutated final line or a cleanly truncated tail; the committed blob can. Authoritative verification therefore reads the chain from git, via `git show HEAD:` on the chain path, and verifies those bytes rather than the working tree.

The chain has a single writer. The rollup takes a path-scoped lease on the receipts directory, and the recon snapshot taken at the start of the run is the scope: receipts appearing later are left untouched and picked up next time.

## When a gate goes red

Start from the receipt, not from the transcript. `stop_reason` names what actually stopped the run, `gate.reason` summarises the verdict, and `claims[]` carries item-level verdicts with evidence for each declared criterion.

`FAIL` means one or more declared criteria did not pass; the reason lists which. `STOP` means a declared criterion is absent from the verity report, which usually signals drift between the spec's criteria and the repo's claim manifest. `NO-VERDICT` means the gate could not run at all: verity exited 2, a config error a retry cannot fix, or its output was not parseable. And when Claude Code itself exits non-zero, the gate is skipped entirely and `stop_reason` records the `cc_exit`.

The one rule that never bends: gate failures are stop conditions, never auto-retried. `retries` in the receipt stays 0. You read the evidence, fix the cause, and relaunch deliberately.

Two reds deserve special handling. A torn final line in the chain, from a crash mid-append, makes verification fail loudly; the repair rewrites committed evidence, which is destructive, so it requires an explicit operator directive and an erratum entry, never a quiet fix. A guard block on something you actually wanted is a false positive, accepted by design: rerun the slice as Mode A with the operation quoted in `destructive_ops`.

Every red is a lesson candidate. If the failure exposed a guard gap, the gap becomes a test fixture and the fixture becomes a release.

## Routine maintenance

The manifest carries `verified_on` and a staleness rule of 30 days. Available models change without notice; revisit the tier chains on that cadence or when your provider announces changes, bump `verified_on`, and let receipts carry the new `manifest_version`.

Any edit to `CONSTITUTION.md` requires recomputing its sha256 and updating `constitution_hash_expected` in the same change, or every subsequent launch stops at the pin.

The Claude Code CLI and hooks contract can drift. Three files are the only seams: `scripts/launch_worker.sh` for flags, `templates/settings.mode-b.json` for hook wiring, `scripts/guard_pretooluse.py` for the guard itself. Verify flag and field names against current docs whenever you touch a seam.

Run the HALT drill on a schedule you will actually keep. Keep the rollup current, so the committed chain stays close to the loose receipts. And keep secret scanning in front of anything public: receipts are designed to be safe to publish, transcripts are not.
