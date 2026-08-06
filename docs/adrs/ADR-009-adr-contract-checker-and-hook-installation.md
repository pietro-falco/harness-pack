---
type: adr
status: proposed
title: "The ADR contract checker at site 2 — interface, corpus selection, form precedence, hook installation, and the OR-1 parity gate"
id: ADR-009
date: 2026-08-06
related-adrs: [vault/ADR-022, vault/ADR-051, vault/ADR-063, vault/ADR-073, vault/ADR-080, harness-pack/ADR-004, harness-pack/ADR-006, harness-pack/ADR-008]
---

# ADR-009: The ADR contract checker at site 2 — interface, corpus selection, form precedence, hook installation, and the OR-1 parity gate

- **Status:** Proposed
- **Date:** 2026-08-06
- **Deciders:** Pietro Falco
- **Related:** vault/ADR-080 (the cross-repo ADR artifact contract, Accepted; D1 the tolerant reader, D2 the status vocabulary, D3 MADR grandfathering, D4 placement, D5 selection, D6 the two enforcement sites and OR-1, plus Amendment 2's hook census — this document is the site-2 half of D6 and the instrument that makes OR-1 closable). vault/ADR-073 (D1, a gate is not a gate until observed to fail; the fixture idiom asserting a stderr signature). vault/ADR-022 (§1 placement, §5 the gitleaks requirement). vault/ADR-051 (D1 namespace registry, D3 counters independent per namespace). vault/ADR-063 (D5, why a single glob cannot select this corpus). harness-pack/ADR-004 (parameterized topology & sanitization, Accepted; the de-literalization this document is forbidden to reopen). harness-pack/ADR-006 (Proposed; its Non-goals bullet — no code is written against a Proposed ADR — governs this document and is applied to this document). harness-pack/ADR-008 (Proposed; D1 pinned measurement basis, D3 the paired positive control, D4 failure reports are unreliable about cause, D6 the claim tiers — the evidence discipline this document is written under). **This ADR decides; no code is written against it while it is Proposed. Neither the checker, nor any hook, nor any fixture ships with this commit.**

## Context

vault/ADR-080 D6 partitions enforcement of the ADR artifact contract into two sites, because `vault_health.py` cannot acquire a runtime dependency on `~/Code/`. Site 1 is a vault-side check; site 2 is `scripts/adr_contract.py` in this repository, covering the four code repos, invoked from a pre-commit hook. D6 states that two implementations of one specification will drift, and requires a parity fixture — OR-1 — that runs both over the same corpus and asserts identical findings. That fixture gates acceptance of this ADR.

What D6 does not do is write the specification. It postulates one. Nothing on disk in any of the five namespaces defines what a finding is, what shape it takes, or what an implementation does when it produces one. A parity gate over an unwritten specification compares two guesses.

This document writes that specification, decides site 2's interface against it, and specifies the fixtures. It writes no code. Under harness-pack/ADR-006 no code may be written against a Proposed ADR, and that rule binds this ADR to itself: the checker, the hook legs, and the seven fixtures are authored at acceptance, not now.

Two facts measured during this pass are load-bearing and were not available when ADR-080 was ratified. Both are recorded in the basis below and both change a decision.

## Measurement basis

Every claim below is scoped to this basis. Outside it the claims are unverified, not false.

- harness-pack `main` at `f74a8ab57c8d43c415b2abd570ee75ddc06d8410`, working tree clean but for one untracked path, `.probe-repo/`, which is deliberately not staged by this commit and is the same untracked probe repository harness-pack/ADR-008 C3 has an open requirement about.
- vault `main` at `44871a47489f0cdd09660738fde558ff59b94b13`. `80-governance/adrs/ADR-080-the-cross-repo-adr-artifact-contract.md` is 768 lines, `status: accepted`, and carries `## Amendment 1` at line 468 and `## Amendment 2` at line 625.
- harnesswright `main` at `9320294a9ac251c031efb6d504919e05ca43cd19`; verity `main` at `4dc016b354f3a6eb953590167b46bc29eacf3fcb`; lanewright `main` at `f32aa62b2bf3f58d6565f8edbb7277e966fe07a2` — the bases of the hook census at `/Users/pietrofalco/Code/_recon/claude-perms/hooks-census.md`, sha256 `d9937948b4c1c11cacafc886252a17bfb8d654c356850f3c48b952216a05ccc7` as pinned by ADR-080 Amendment 2.
- Both live hooks were read in full in this pass, from the working tree, not from the census transcription. They are **not** identical and the difference is load-bearing:

```sh
# harnesswright/.githooks/pre-commit — 3 lines
#!/bin/sh
set -e
gitleaks protect --staged
```

```sh
# verity/.githooks/pre-commit — 5 lines
#!/bin/sh
set -e

gitleaks protect --staged --redact
exit $?
```

- **M1 — site 1's corpus root is not addressable from its command line.** `vault_health.py:523` reads `root = Path(m.get("vault_root", ".")).resolve()`, where `m` is `SCRIPT_DIR / "checks.yaml"`. `parse_args` exposes `--check` and `--list-checks` and nothing else. There is no `--root`. A check function's signature is `chk_ledger_contract(c, idx, root)`, so the root is a parameter internally and a constant externally.
- **M2 — site 1 prints findings to stdout and exits 1 on any warn.** `vault_health.py:536` is `print(f"{f['severity']}: {f['path']}…— {f['message']}")`, and the `--check` path ends `sys.exit(1 if any(f["severity"] in ("critical","warn") for f in findings) else 0)`. Under `--check`, ADR-080 D6's severity `warn` therefore produces **exit 1**, not exit 0.
- **M3 — the ADR gate's prescribed idiom is blind to Form H.** `80-governance/code-execution-rules.md` prescribes `grep 'status:' <file>` before the first implementing commit. Run against the five Form-H-only Accepted records in `docs/adrs/` it returns zero lines, rc=1. Run against ADR-006 and ADR-008, which now carry both forms, it returns exactly one line — the Form Y line — and never sees `- **Status:** Proposed`.
- `.verity/claims.json` excludes `docs/adrs/` from all six privacy claims. Machine literals appear in this document as evidence and may not be copied into any file outside that directory.
- `Justfile` carries `deploy`, `verify`, `preflight`, `run`, `stats`. No recipe installs, configures, or invokes a git hook. `deploy` is operator-only under sudo and is untouched by this ADR.

## Numbering — the reservation sweep, and its outcome

`grep -rn 'ADR-009'` over the whole of harness-pack at `f74a8ab`, excluding `.git/`, returns **zero hits**. The same sweep over `~/Obsidian-Vault/80-governance` and `~/Obsidian-Vault/00-inbox` returns hits of two distinct kinds, and the distinction is the whole outcome:

- **The vault's own ADR-009** — `80-governance/adrs/ADR-009-phase-8-scouting-and-security-foundation.md`, Accepted, plus the twenty-odd documents citing it. This is a different namespace. vault/ADR-051 D3 settles it: counters remain independent per namespace and no existing ADR is renamed or renumbered. It is not a collision and it does not consume this number.
- **`harness-pack/ADR-009`, named five times in vault/ADR-080** — at lines 236, 292, 319, 339 and 719, as the ADR that OR-1 gates, that OR-5 resolves in, and that Amendment 2 declines to open. The number is not merely free; it is reserved by an Accepted vault ADR **for exactly this artifact**.

No successor number is taken and no re-sweep is required. Recorded because ADR-080's own numbering note records the opposite outcome — a number claimed from a carried-forward assumption rather than read from disk — as the exact defect class the contract exists to make detectable.

The gap at 007 is untouched. ADR-008's numbering note holds 007 for the Claude Code version pin, ADR-080 D4 records the gap as informational, and this ADR does not close it.

## The specification — what a finding is, in one table

ADR-080 D6 binds two sites to "one specification" and does not write it. It is written here. It binds site 2 absolutely. It binds site 1 by way of D6, and if the vault declines any row, OR-1 closes by an amendment on this side rather than by silent divergence — which is the failure mode D6 named.

Five codes, and nothing else is a finding.

| Code | Condition | Severity |
|---|---|---|
| `no-status-declaration` | A selected file carries neither a Form Y `status:` key nor a Form H status line | warn |
| `invalid-status` | A status value outside D2's closed set `proposed \| accepted \| adopted-install-deferred`, compared case-insensitively | warn |
| `duplicate-adr-id` | Two selected files in one namespace resolve to the same id | warn |
| `invalid-type` | Form Y present **and** carrying a `type` key whose value is not `adr` | warn |
| `status-declaration-conflict` | Both forms present and their normalised values differ (D3) | warn |

Three things this table settles by omission, each deliberate:

- **Absence of `type` is never a finding.** That is ADR-080 D3's grandfathering, expressed as the exemption-by-absence D3 requires rather than as a file list. At site 2 it is additionally free: D1 implies `type: adr` from residence in an ADR directory, so a Form H record cannot trigger `invalid-type` at all.
- **A gap in the number series is never a finding**, per ADR-080 D4, matching `chk_id_monotonicity`'s treatment of vault gaps.
- **`duplicate-adr-id` reads the working tree, never history.** harnesswright reused `0001` after deleting its predecessor; the predecessor is unreachable from HEAD, is not on disk, and is therefore invisible to a working-tree scan. The reachability qualifier ADR-080 D4 states is satisfied structurally rather than by a history walk, which also keeps the checker's cost independent of repository age.

## D1 — The exit code carries a class, the stderr carries the findings, and the hook decides the disposition

**Invocation.** `python3 scripts/adr_contract.py [ROOT ...]`. Zero or more repository roots as positional arguments. No subcommands. No required flags.

**Output.** Findings go to **stderr**, one per line, sorted by `(path, code)` so two runs and two sites are diff-comparable. The line shape mirrors site 1's, measured at M2, with a stable code token appended so a fixture can assert a signature rather than parse prose:

```
warn: <relpath>:<line> — <message> [<code>]
```

A trailing summary line on stderr names the count of files examined and the count of findings. stdout carries nothing at all.

**Exit codes — a closed three-value set.**

- **0** — the run completed and produced no finding.
- **1** — the run completed and produced at least one finding. This is deliberately the same integer site 1 returns for the same condition (M2), so the two sites do not disagree on the one code a reader is most likely to compare.
- **2** — the run did not complete. A root that does not exist, an unreadable file, a malformed argument, an ADR directory that exists and matches zero files. Any value outside `{0,1,2}` is undefined and is treated as class 2.

**A finding is not an error, and the distinction is the reason for three codes rather than two.** A finding is a statement about the corpus: some ADR is malformed. An error is a statement about the checker: it could not look. Collapsing them means a checker that silently fails to find its corpus is indistinguishable from a clean corpus — which is why an existing ADR directory yielding zero files is class 2 and not class 0. A selector that matches nothing and a corpus that is clean produce the same silence, and only one of them is good news.

**Disposition: the gate warns, it does not block.** Every code in the table is `warn`, and the hook leg (D4) returns 0 for classes 0, 1 and 2 alike. Three reasons, in order of weight:

1. **Parity would otherwise be vacuous.** ADR-080 D6 gives site 1 severity `warn`. If site 2 blocks on the same finding site 1 merely reports, the two sites do not say the same thing, and OR-1 compares finding sets while the sites disagree about what a finding means.
2. **Under `set -e` a block is mute.** Both live hooks are `set -e`, and verity's terminates `exit $?`. A non-zero from an appended leg aborts the commit with nothing after it. That is a proportionate price for a leaked secret. It is not a proportionate price for a missing `date:` key, and — by harness-pack/ADR-008 D4 — a mute abort is precisely the shape of failure that moves an agent confidently in the wrong direction.
3. **vault/ADR-073 D1.** A gate is not a gate until observed to fail. Landing site 2 blocking means the first observation of its block is a commit the operator wanted to make, on a rule never exercised. It lands as a reporter; promotion to blocking is a separate decision with its own falsifier, recorded as OR-C.

**M2 dissolves an apparent conflict rather than creating one.** Site 1 exits 1 on a `warn` under `--check`. So ADR-080 D6's `warn` names a **severity in the findings model, not a disposition**. Nothing in D6 says the vault check is non-blocking; it says the finding is not critical. Site 2 adopts the same severity and chooses its own disposition, which is what a per-site disposition is for. The parity surface is the finding set. It cannot be the exit code, and M2 is why: site 1's exit is computed from severity, site 2's from class, and no arithmetic reconciles them without one site lying about one of the two.

**Falsifier.** In a throwaway clone with the leg installed and a corpus containing one known-bad file: the commit completes, and its stderr carries the finding line with its code token. Falsified by the commit aborting, or by the finding line being absent, or by the summary line reporting a file count of zero.

## D2 — Selection is two-stage, the roots are discovered, and no path to this machine is ever written down

**Stage one — directories.** For each root, the single directory `<root>/docs/adrs/`. Not recursive. That is ADR-022 §1 placement as ADR-080 D4 registers it, and it is the layout all four code repos use. A root with no such directory contributes zero files and one informational stderr line; it is not a fault, because a repository may legitimately hold no ADRs yet. A directory that exists and yields zero matching files **is** a fault (D1, class 2).

**Stage two — filename shape.** Two independent basename tests against the entries of that one directory listing: `ADR-*.md`, or the four-digit form `NNNN-*.md` where `NNNN` is exactly four digits followed by a hyphen. Never one combined glob. ADR-063 D5 by way of ADR-080 D5 gives the reason: an fnmatch star crosses the path separator, and a glob written for one spelling cannot find the other. Both spellings must be recognised for either to be judged. `0000-adr-template.md` is excluded by exact basename and nothing else is — an exclusion list that grows is a maintenance surface, and ADR-080 D5 names exactly one file.

**Root resolution, in order, with no machine literal anywhere.**

1. The positional arguments, if any.
2. Otherwise `git rev-parse --show-toplevel` from the working directory. A pre-commit hook runs at the repository root, so the hook case needs no argument at all.
3. Otherwise the parent of the script's own resolved directory.

No `$HOME`, no repository name, no `/Users/`, and no `~/Code/` appears in the script or in any tracked file this ADR authorises. **harness-pack/ADR-004 already de-literalized this surface and is not reopened**; this is the same resolution discipline `scripts/launch_worker.sh` applies to `HW_CLI` and `VERITY_CLI`, and the same claim set in `.verity/claims.json` remains the invariant.

**No repository registry is introduced.** The four-repo sweep D6 describes is served by passing four roots as arguments, not by a tracked list of repository names — which the privacy claims forbid and ADR-004 D3 already externalized for the worker case. Whether the parity fixture's root list becomes a gitignored local file on the `workers.local.json` pattern is an implementation choice, not a decision this ADR makes.

**Falsifier.** `fx-four-digit` — a four-digit conformant file yields no finding, which is only possible if both spellings were found. Plus `git grep -qF '/Users/'` staying green outside `docs/adrs/` after the checker lands.

## D3 — Form Y wins, and their disagreement is itself a finding

ADR-080 D1 admits "either of two forms" and is silent on both-present-and-divergent. That silence is now load-bearing: at `f74a8ab` and harnesswright `739438c`, three Proposed ADRs — harness-pack/ADR-006, harness-pack/ADR-008, harnesswright/0007 — carry **both** `status: proposed` in Form Y frontmatter and `- **Status:** Proposed` in a Form H block. Today the two agree. At ratification someone flips one of them, and D1 says nothing about which the reader should believe.

**Form Y wins whenever it is present.** Three reasons:

1. **ADR-080 D1 already ranks them.** "Every ADR authored from acceptance onward uses Form Y. Form H is a reading accommodation for records already on disk, not a permitted output." The permitted output is the authority; the accommodation is not.
2. **Form Y is declared, Form H is derived.** Under Form H, `id` comes from the filename and `type` is implied by the directory. A precedence rule preferring the derived form over the declared one inverts the contract.
3. **It matches every existing machine reader.** `frontmatter_status_enum` and `chk_adr_crossrefs_resolve` both read frontmatter. A site-2 rule preferring Form H would guarantee the drift D6 exists to prevent, on day one.

**On disagreement the checker emits `status-declaration-conflict` and evaluates every other code against the Form Y value.** Not silence, and not a fault — the file is readable, it is just self-contradictory, which is exactly what a finding is for.

This is the highest-value code in the table, and M3 is why. `code-execution-rules.md` prescribes `grep 'status:' <file>` as the ADR gate. Measured at this basis, that idiom returns **zero lines** for the five Form-H-only Accepted records in `docs/adrs/`, and for a both-forms record it returns **only the Form Y line** — the pattern is case-sensitive and never matches `- **Status:**`. So a record whose frontmatter reads `accepted` while its Form H block still reads `Proposed` passes the ADR gate as Accepted and reads as Proposed to every human who opens it. The gate and the reader disagree, silently, and neither announces it. That is harness-pack/ADR-008 D4 at the level of the governance corpus itself: a report that misnames its cause is worse than one that reports nothing.

The prescribed idiom is **not corrected here.** ADR-080's Verification section already records a different defect in the same idiom — that it also matches the D2 vocabulary inside a fenced code block — and declines to fix `code-execution-rules.md` from within an ADR. This document declines for the same reason and adds its finding to the same pile, as OR-D.

**Falsifier.** `fx-both-forms-divergent` fires exactly one `status-declaration-conflict`. Its negative control is not a seventh fixture but the live corpus: the three converted records carry both forms in agreement at this basis and must produce **zero** findings. A rule that fires on agreement would make the checker noise from the first commit, and the D5 parity fixture's live-corpus arm is what observes it does not.

## D4 — Two installation cases, and the word "installed" does not cover both

ADR-080 Amendment 2 falsified OR-5's premise and split the fleet. The mechanism is decided here for both halves; nothing is installed by this commit.

### Case A — harnesswright and verity: an added leg on a live hook

Both carry a tracked, executable, `set -e` pre-commit hook running the gitleaks invocation ADR-022 §5 requires. Site 2 there is an added leg, not an installation.

- **The leg runs strictly after gitleaks.** It therefore cannot mask a secret finding: under `set -e`, a gitleaks failure aborts before the leg is reached.
- **In verity the leg is inserted before line 5, not appended at end of file.** `exit $?` terminates that script; text after it is unreachable and an append that assumes control falls through at EOF would be dead on arrival. In harnesswright, which has no terminal `exit`, the leg is appended after line 3.
- **A hazard the insertion creates, named rather than assumed.** After insertion, verity's `exit $?` refers to the leg's status, not gitleaks'. Because the leg always returns 0 and gitleaks already aborted via `set -e` on failure, `exit $?` remains observably `exit 0` — the same behaviour, a different referent. That is not a reason to leave it implicit. The verity edit is receipted with the pre-edit and post-edit sha256 of `.githooks/pre-commit` and **two observed commits**: one green, and one carrying a planted secret that still aborts with gitleaks' own signature. Nothing establishes that the gitleaks gate survived an edit except observing it fire after the edit.
- **The leg always returns 0**, for every class of D1. It captures the status, prints, and does not propagate. This is the concrete content of "does not weaken gitleaks".
- **Each edit is its own commit, in its own repository, against that repository's own ADR gate.** A harness-pack ADR does not authorise a commit in harnesswright or verity. It specifies what those commits must do if their own repositories authorise them.

### Case B — harness-pack and lanewright: a first installation

No hook, no `core.hooksPath`, samples only. A new tracked `.githooks/pre-commit` plus `core.hooksPath=.githooks` set locally per clone.

- **No `set -e`.** The hook runs the leg, captures the status, branches explicitly, and exits 0. `set -e` is what makes a first-installation hook abort mutely on any surprise, and it is what the fixture discipline already forbids in working scripts for the same reason.
- **The gitleaks gap is not closed here and is not bundled.** ADR-022 §5 requires gitleaks and these two repos lack it. That is OR-5's real residue after Amendment 2, and it is OR-B below. Bundling a secret gate into the same artifact as a documentation linter makes the linter's acceptance gate depend on gitleaks behaviour and makes a red on either block both. They are separable and they stay separate.

### Both cases — resolution, and what a fresh clone gets

- The checker lives in harness-pack and is reached from the other repos through `ADR_CONTRACT_CLI`, on the `HW_CLI`/`VERITY_CLI` pattern harness-pack/ADR-004 established. **There is no tracked default path**, because a default would be a machine literal in a tracked file in a repository that is not harness-pack. If the variable is unset or the target is unreadable, the leg prints one line naming the unresolved variable and returns 0. Absent is visible; it is never silent.
- **`core.hooksPath` is local clone configuration and does not travel with the repository.** A fresh clone of any of the four repos gets the tracked `.githooks/` directory and no `core.hooksPath`, and therefore fires no hook at all — including, today, in harnesswright and verity, where the gitleaks protection a reader would assume from the tracked file is one unset config key away from absent. **A bootstrap is therefore required. It is declared here and not implemented**, and whether it becomes a `just` recipe, a documented operator step, or neither is OR-C.
- **`just deploy` is untouched.** It is operator-only under sudo, no hook participates in it, and nothing in this ADR reaches it.

**Falsifier.** In a throwaway clone of a Case-A repo with the leg inserted: a commit carrying a planted secret aborts with gitleaks' signature on stderr, and a commit over a conformant corpus completes with the leg's summary line present. Falsified by the secret commit succeeding, by the leg's line being absent from a completing commit, or by any commit aborting with no stderr past the leg.

## D5 — The OR-1 parity fixture: two corpora, three assertions, one observed red

**Corpus.** A versioned fixture corpus in harness-pack under `tests/fixtures/adr-contract/`, holding the seven fixture files of the next section. Not the live corpus: the live corpus moves, so parity asserted against it is not reproducible, and it may not contain the deliberately-malformed records the positive fixtures require.

**A second, non-parity arm runs over the live corpus** at a pinned basis and asserts **zero findings** across all four code repos. It is not the parity gate. It is what observes that the three both-forms records of D3 are green and that the checker is not noise from its first commit.

**How it runs.** Both sites are invoked from harness-pack against the same corpus root, and the dependency direction is safe: harness-pack already depends on harnesswright and verity through the launcher, while the vault acquires no dependency on harness-pack — which is the property ADR-080 D6 was protecting.

M1 makes the mechanism concrete. Site 1 has no `--root`; its root comes from `checks.yaml`'s `vault_root`. The parity harness therefore runs site 1 **inside a throwaway local clone of the vault whose `checks.yaml` names the fixture corpus** — which requires no edit to site 1, and which is exactly the mutate-only-inside-a-throwaway-clone discipline the fixtures already carry. That this works at all is a property measured at M1, not an assumption; if site 1 lands reading its root by some other route, D5's mechanism changes and OR-A is where that is recorded.

**What it asserts — three assertions per run.**

1. Site 1's finding set equals the corpus's declared expected set.
2. Site 2's finding set equals the same declared expected set.
3. Site 1's finding set equals site 2's.

**Normalisation, and its limits.** A finding is normalised to the pair `(relpath, code)`. Path prefixes are stripped to the corpus root; severity spelling is folded. **Message prose is not compared.** Two implementations will word the same defect differently, and a gate that reds on wording fails for a reason that is not drift in the specification — which would make the gate a source of false stops rather than a detector of drift. The code and the subject must match exactly, and those are the whole of what the specification fixes.

**Why its failure is observable, and how that is established.** Assertions 1 and 2 catch a single-site bug; assertion 3 catches specification drift, which is the thing D6 predicted and the only thing a parity fixture uniquely detects. Under vault/ADR-073 D1 that is not enough: the gate is **observed failing before it is trusted**. One rule at one site is disabled, the parity run is executed, its red is receipted with the literal stderr and the mismatched pair, and the rule is restored. A parity fixture that has only ever been observed green is an assumption wearing a gate's clothes. The receipt of that deliberate red is the acceptance evidence for this ADR.

**Falsifier.** Any `(relpath, code)` pair present in one site's output and absent from the other's, per ADR-080 OR-1 verbatim. Additionally: an unreceipted deliberate red, or a live-corpus arm reporting any finding at the pinned basis.

## Fixtures — specified, not written

Seven. The six of ADR-080's Verification table, unchanged in mutation and in assertion, plus one for D3. Each asserts a **stderr signature and never an exit integer** (vault/ADR-073 D1), each mutates only inside a throwaway local clone, and none carries `set -e` — because non-zero exits are the evidence being collected. This mirrors `80-governance/skill-eval-harness/fixtures/run-fixtures.sh`.

| Fixture | Mutation | Asserted stderr signature |
|---|---|---|
| fx-no-status | ADR file with neither Form Y nor Form H | `no status declaration` … `[no-status-declaration]` |
| fx-bad-enum | status value `Adopted` | `invalid status adopted` … `[invalid-status]` |
| fx-dup-id | second file at an existing sequence number, both reachable from HEAD | `duplicate ADR id` … `[duplicate-adr-id]` |
| fx-case-variant | plain and bold status lines, mixed case | NO FINDING — D1 normalisation holds |
| fx-madr-legacy | copy of ADR-022, no `type` key | NO FINDING — D3 grandfathering holds |
| fx-four-digit | four-digit filename, conformant Form H | NO FINDING — D5 selection finds both spellings |
| **fx-both-forms-divergent** | Form Y `status: accepted` with Form H `- **Status:** Proposed` in one file | `status declaration conflict` … `[status-declaration-conflict]` |

The last three of the original six are negative controls and are not optional: a tolerant reader whose tolerance is never observed holding, and an exemption never observed not firing, are L-033 defects.

**One negative control now passes for a different reason than the one it was written for, and that is recorded rather than absorbed.** `fx-madr-legacy` was written to observe D3's grandfathering not firing. Under the specification above, absence of `type` is never a finding at either site, so the fixture would pass even if the grandfathering had never been implemented. Its assertion is unchanged and still correct; its evidentiary value is weaker than ADR-080 D3 assumed. A control that passes for an unintended reason is the same L-033 shape it exists to guard against, and naming it is cheaper than discovering it during a drift investigation.

`fx-both-forms-divergent` needs no separate negative twin: its twin is the live-corpus arm of D5, where three real records carry both forms in agreement and must stay silent.

## Non-goals

- **No code.** Not the checker, not a hook, not a hook leg, not a fixture, not a `just` recipe. harness-pack/ADR-006 forbids writing code against a Proposed ADR and this document is Proposed.
- **No hook installed, no `core.hooksPath` set, no git configuration touched, in any of the four repositories.**
- **No edit to any Accepted ADR in any namespace**, and no renaming or renumbering — ADR-080's non-goals stand unchanged.
- **No correction of `code-execution-rules.md`.** M3's defect is recorded as OR-D, in the same posture ADR-080's Verification section took toward the same idiom.
- **No closure of the gitleaks gap** in harness-pack or lanewright. OR-B.
- **No reopening of harness-pack/ADR-004.** Root resolution is discovered, never written down.
- **No promotion of site 2 to blocking.** OR-C.
- **No change to `Justfile`**, and in particular none to `deploy`, which is operator-only.
- **No decision about `.probe-repo/`.** It is untracked at this basis, it is not staged by this commit, and its provenance remains harness-pack/ADR-008's open requirement.

## Open requirements

- **OR-A — site 1's corpus root may not stay addressable.** M1 measured that `vault_health.py` takes its root from `checks.yaml` with no CLI override, which is what makes D5's throwaway-clone mechanism work today without editing site 1. `chk_adr_contract` does not yet exist. If it lands resolving its corpus by some other route, D5's mechanism changes shape. Falsified by a landed site 1 whose corpus root cannot be redirected at a fixture corpus by any means short of editing it.
- **OR-B — ADR-022 §5's gitleaks requirement is unmet in harness-pack and lanewright.** This is OR-5's residue after ADR-080 Amendment 2 corrected its premise: two repos comply, two do not. Deliberately not bundled with the ADR-contract leg. Falsified by either repo acquiring an ADR-contract leg while still carrying no secret gate.
- **OR-C — the `core.hooksPath` bootstrap, and the promotion question behind it.** No mechanism is chosen for making a fresh clone fire its tracked hooks, and until one exists every claim that a repository is hook-protected is a claim about one clone. Separately: promoting site 2 from warn to blocking is a decision this ADR declines, and under vault/ADR-073 D1 it may only be taken after the reporter has been observed producing a true finding on a real commit. Falsified by any document asserting that a fresh clone of any of the four repos is protected by its tracked hook.
- **OR-D — the ADR gate's own idiom is blind to Form H.** Measured at M3: `grep 'status:'` returns nothing for the five Form-H-only Accepted records and only the Form Y line for a both-forms record. The gate `code-execution-rules.md` prescribes cannot read the majority of this repository's own ADRs. Falsified by any session claiming to have verified a Form-H record's status with that idiom.

## Verification

```bash
# The reservation sweep, both halves (this document's Numbering section)
grep -rn 'ADR-009' . | grep -v '^./.git/'                    # harness-pack -> zero hits at f74a8ab
grep -rn 'harness-pack/ADR-009' ~/Obsidian-Vault/80-governance # -> five hits, all in ADR-080

# M3, the measurement D3 rests on. Expected: rc=1 and no output for a
# Form-H-only record; exactly one line, the Form Y line, for a both-forms record.
grep -n 'status:' docs/adrs/ADR-001-enforced-deploy-topology.md; echo $?
grep -n 'status:' docs/adrs/ADR-008-claude-code-sandbox-surface.md; echo $?

# M1 and M2, the two measurements that shaped D1 and D5.
sed -n '523p;536p' ~/Obsidian-Vault/80-governance/vault-health/vault_health.py

# The three both-forms records D3's negative control depends on. Expected: each
# file yields one Form Y status line and one Form H status line, in agreement.
grep -n '^status:\|^- \*\*Status:\*\*' docs/adrs/ADR-006-learning-layer.md \
                                        docs/adrs/ADR-008-claude-code-sandbox-surface.md

# This commit is docs-only and one path. Expected: exactly one file changed.
git show --stat HEAD

# Post-commit truth is the committed blob, never the working tree.
git show HEAD:docs/adrs/ADR-009-adr-contract-checker-and-hook-installation.md | head -10

# The standing gate, unaffected by a docs-only commit but not assumed to be.
bash tests/run_tests.sh
node "$VERITY_CLI" verify .verity/claims.json
```

At acceptance, and not before: the seven fixtures, the parity harness, and the receipted deliberate red of D5.

## Notes

**Provenance.** One read-only recon pass on 2026-08-06 at the basis above. Read in full and not by citation: vault/ADR-080 D1–D7, its Non-goals, Open requirements, Verification and Amendment 2; the hook census at `_recon/claude-perms/hooks-census.md`; both live `.githooks/pre-commit` files, from the working tree rather than from the census transcription, on the explicit assumption that they are **not** identical — which they are not, and the difference is what D4 turns on; harness-pack/ADR-008 in full; and harness-pack's `Justfile`. `vault_health.py` was read only at the two regions M1 and M2 name; no claim here rests on any other part of it.

**Standing on an Accepted ADR while Proposed.** ADR-080 is Accepted and this document implements its D6. It is nonetheless Proposed, and the ADR gate is Accepted status of the ADR being implemented against — so this document authorises no code until it is itself accepted. The distinction matters here because the artifact this ADR describes is the one that would check it.

**A specification written from one side.** ADR-080 D6 postulates "one specification" for two sites and does not write it. It is written above, from harness-pack. It binds site 2 without qualification and binds site 1 only through D6. If the vault declines a row, OR-1 is closed by an amendment on this side. Silent divergence is the one resolution that is not available, because it is the failure D6 exists to detect.
