# ADR-008: Claude Code sandbox surface — measured boundary, attribution discipline, and enforcement-plane partition

- **Status:** Proposed
- **Date:** 2026-07-31
- **Deciders:** Pietro Falco
- **Related:** vault/ADR-061 (A1, the open mechanism question this begins to answer), vault/ADR-051 (ADR namespace registry and numbering), vault/ADR-055 (commit signing), vault/ADR-067 (guard repair), harness-pack/ADR-005 (receipt chain and receipts index), harness-pack/ADR-006 (two-commit ADR cycle)

## Context

On 2026-07-31 the Claude Code sandbox was exercised under a strict profile in this repository. The profile is loaded explicitly with `claude --settings <path>`, is untracked, and is ignored by `.gitignore`. The session produced observations about egress, filesystem writes, credential access, git operations, and the relationship between the PreToolUse hook and the permission rules.

This ADR records what that surface is, and — more importantly — what standard of evidence a claim about it must meet. It answers, for the mechanism half only, the question vault/ADR-061 A1 deliberately left open: whether the boundary can leave the Claude Code process. It does not decide the authority half, which remains vault-side.

Nothing here is implemented. Under harness-pack/ADR-006 no code may be written against a Proposed ADR; the fixture specification named in D7 is authored at acceptance, not now.

## Measurement basis

Every claim below is scoped to this basis. Outside it, the claims are unverified, not false.

- Claude Code 2.1.220, binary at /Users/pietrofalco/.local/bin/claude
- macOS 26.3.1, build 25D771280a; Darwin 25.3.0, arm64
- Strict profile: .claude/strict.settings.json, 1250 bytes, sha256 82aa230e55ef5a7192030775f329e56e1b55dcee9e2154f4ab70bd73478dc100, untracked, loaded only via --settings
- Profile contents that are load-bearing: sandbox.enabled true, failIfUnavailable true, allowUnsandboxedCommands false, autoAllowBashIfSandboxed true, filesystem.allowWrite = repository root plus ~/.npm, network.strictAllowlist true with five allowedDomains, credential denies for ~/.zshenv, ~/.ssh and ~/.claude/.credentials.json, and six permission deny rules
- User-level settings: ~/.claude/settings.json, 3137 bytes, untracked by any repository, defaultMode auto, additionalDirectories containing the Obsidian vault
- Live PreToolUse hook: /Users/pietrofalco/Obsidian-Vault/.claude/hooks/pre-bash-guard.py, 10255 bytes, mode 755, blob f88831a, registered at ~/.claude/settings.json lines 59-71 with matcher Bash
- Global git configuration in effect: commit.gpgsign true, tag.gpgsign true, gpg.format ssh, and a signing key path under ~/.ssh — a directory the profile's credential deny covers

## D1 — A boundary claim without a pinned basis is void

The sandbox is an undocumented surface of a product that ships continuously. A claim that omits the basis above is not a weak claim; it is an unfalsifiable one, because no later reader can determine what was being measured. Every receipt about this surface carries the basis block or is discarded.

## D2 — The configuration file is not evidence of the boundary, in either direction

The measurement shows the configuration failing to describe the boundary both ways. Fields are declared and inert: allowedDomains has no effect unless strictAllowlist is set. Behaviour is enforced and undeclared: writes to specific paths under .git were refused while sitting inside allowWrite, with nothing in any settings file naming them.

Therefore the boundary is defined by the set of fixture receipts, not by the settings file. Reading the configuration is orientation, never evidence. This is receipts-not-prose applied to policy itself, and it generalises beyond this repository.

## D3 — No denial is self-attributing; attribution requires a paired positive control

Policy denials arrive wearing the costume of ordinary failure: a non-zero curl exit for network, a permission error for the filesystem, a missing-file error for credentials. Nothing in the failure identifies the layer that produced it.

Therefore an attribution claim requires a negative twin executed in the same session under the same basis: one operation the policy should refuse and one adjacent operation it should permit, differing in the single dimension under test. A receipt that carries only the refusal establishes that something failed, never what refused it.

The discipline binds this document to itself. Where a refusal was observed but its twin was not run, the claim stays below the finding tier no matter how plausible the mechanism.

This is the attribution corollary to gate discipline D11 (a gate never observed failing is not a gate). D11 is currently carried by a Proposed ADR in a project folder while being cited as normative by an Accepted ADR, by the lessons file, and by live code in the vault. That defect is recorded in the notes below and is not resolved here.

## D4 — Structured and human-readable failure reports are both unreliable about cause

Three denials in the transcript corpus carry `toolDenialKind: "permission-rule"` while their literal text reads `PreToolUse:Bash hook error: [python3 .../pre-bash-guard.py]: BLOCKED by pre-bash-guard v3 [tokens]`. The decider was the hook; the field names the other plane. The misclassification is uniform across all three records, not incidental.

The same defect appears one layer down, outside the harness entirely. When a commit was attempted under the profile, the shell reported a permission error on the signing key path while git reported the same path as absent. Two programs, one path, one session, two incompatible causes, neither naming a policy.

Therefore receipts about failures carry the literal text, the command string, and the exit status. A structured classification field may be recorded as an observation but may never be the basis of an attribution, and neither may the failure text of a tool that has no knowledge of the policy layer.

This is L-033 raised to the platform level: a detector whose output is cited outside its measurement scope. Here the parties citing out of scope are the agent harness and the tools it invokes.

## D5 — Enforcement planes are partitioned: Bash to the hook, tools to permissions

The relative precedence of the PreToolUse hook and the permission rules is a property of Claude Code and is not configurable. The exposure it creates is configurable, by never letting the two planes overlap.

- The PreToolUse hook is the primary enforcement plane for shell commands. It is local code, falsifiable offline against unit fixtures at zero cost and in continuous operation.
- The permissions block is the enforcement plane for the tool layer: Edit, Write, Read, WebFetch, MCP. There is no shadowing there by construction, and rules are falsifiable in situ.
- Any Bash deny rule whose tokens are already covered by the hook is either removed, or annotated SHADOWED — unverifiable while hook active and excluded from every coverage claim.
- Narrow exception for catastrophic tokens (credential paths, recursive removal): duplicates are retained, accepted as unverified, and require a periodic hook-off run producing a dated receipt.

The partition is not merely prudent; it mirrors what the sandbox already imposes in nature, since the sandbox intercepts the shell subprocess and leaves the tool layer entirely to permissions.

## D6 — Claims are tiered, and only tier A may be cited as a finding

- **Tier A — receipted.** Established by an artifact on disk or in the transcript corpus, re-readable by a third party.
- **Tier B — observed without receipt.** Seen in the measurement session, surviving only as prose, or receipted without the twin that would attribute it. Under receipts-not-prose these are claims, not findings. They may be cited only as open requirements.
- **Tier C — withdrawn.** Contradicted or unsupported by measurement.

No tier B item may appear in any downstream document, gate, or specification as an established property of the sandbox.

## D7 — The fixture specification is named here and authored at acceptance

The fixtures are code. Under the two-commit cycle this document ships alone. At acceptance a companion specification is authored under specs/, following the repository convention where an ADR decides and a spec executes (the worked example being ADR-005 and RS-001). Each fixture in that specification declares: the claim, the command, the expected observable, the negative twin, and the attribution rule that connects them.

Privacy constraint for that future document: docs/adrs/ is excluded from the privacy claims, specs/ is not. The specification uses placeholders for absolute paths, repository names, and any bare numeric token matched as a word.

## D8 — This ADR decides mechanism only

Authority over autonomy arming stays in the vault per vault/ADR-061. This document supplies the mechanism recon that A1 said must never be assumed. It does not decide whether the mechanism is adopted, under what arming conditions, or with what human gate.

## Findings — tier A

- **A1.** The structured denial field misattributes the deciding plane, uniformly across three records. See D4.
- **A2.** The denied subprocess learns nothing: the tool result is absent entirely, the trailing echo of the exit status never executed, and the captured stderr is empty.
- **A3.** Attribution is asymmetric rather than absent. The transcript prose names the hook file and version; the structured field names the wrong plane; the subprocess receives neither. The general claim that no denial is self-attributing is false at the prose level and must be stated per observer.
- **A4.** The user-level hook is machine-global. A denial fired with the working directory in this repository, from a guard script resident in the Obsidian vault, registered at the user level. This repository inherits vault policy without declaring it anywhere in this repository.
- **A5.** Permission deny rules anchor to the command prefix. The user-level spelling does not match the working-directory idiom, which reaches the same staging operation. Only the glob-leading spelling covers it, and that spelling exists solely in the untracked strict profile. The default posture therefore does not cover the idiom at the permissions plane.
- **A6.** Two guards exist. The one under test in tests/guard_cases.jsonl, twenty records, is registered nowhere in the user settings. The one actually registered, matcher Bash, has no test corpus at all. The gate that runs is the gate never observed failing.
- **A7.** The live guard's own docstring declares it not installed while the user settings register that exact path as the PreToolUse hook. The artifact contradicts its own deployment state.
- **A8.** The strip_quoted bypass does not exist because strip_quoted does not exist: it was replaced by a function that locates the policed command name rather than deleting quoted substrings. The working-directory flag is enumerated among the git global value options and skipped when resolving the subcommand, so the idiom reaches the staging branch and is blocked. Corroborated behaviourally by the third denial record.
- **A9.** Neither search method supports an absence claim alone. A recursive filesystem sweep from the repository root silently skipped the .claude directory; a tracked-file search cannot see the untracked profile, which is the very artifact under discussion. Governance-document absence is established by tracked-file search; configuration-content absence only by explicit path.
- **A10.** The registered hook command string was edited mid-session on 2026-07-30, between two denials six seconds apart, changing which variable expands to the vault root. Hook registration is mutable state and belongs in the basis.
- **A11.** The user settings place the Obsidian vault in additionalDirectories. Every session on this machine, in any repository, holds the vault in scope.
- **A12.** Two independent auto-allow paths exist: the strict profile auto-allows shell commands when sandboxed, and the user-level default mode is auto. Observations about classifier behaviour under one path do not transfer to the other.
- **A13.** Under the profile, a commit could not be written: git exited 128 reporting the configured signing key as a missing file, while the shell reported a permission error on that same path in the same session. Two programs give incompatible causes for one path and neither names a policy. Which report is accurate is not decidable from inside the profile, because the deny covers the existence check itself.

## Claims — tier B, open requirements, not findings

- **B1.** Egress is intercepted below the proxy environment, not merely through it.
- **B2.** allowedDomains is inert unless strictAllowlist is set. The enabled arm was measured; the disabled arm never was, and the A/B substrate already sits on disk in two settings files that differ in exactly that field.
- **B3.** Deny globs bind to the exact path segment. Depth beyond one level was never probed; if the matcher crosses a separator, the claim is false.
- **B4.** An undeclared layer refuses writes to specific paths under .git while permitting others, all inside allowWrite. The probes were never re-run without the profile, so undeclared is asserted rather than isolated.
- **B5.** The sandbox covers the shell subprocess; the tool layer is covered solely by permission rules, where an Edit rule was observed to constrain Write.
- **B6.** Adoption constraints under the strict profile: local git configuration refused, staging and object writes permitted.
- **B7.** The auto-mode classifier is advisory rather than a gate, having refused and permitted adjacent paths within the same tree.
- **B8.** Signing is what makes commits impossible under the profile, by way of the credential deny on the ssh directory. The refusal is receipted (A13); the attribution is not. The competing explanation, that the signing key is genuinely absent, was not excluded, and cannot be excluded from inside the profile. Weak corroboration only: commits landed on this machine the same day under the same global configuration. The twin is the same commit attempted outside the profile, paired with an existence check on the key path.

## Withdrawn — tier C

- **C1.** The vault index causal claim is withdrawn, not downgraded. The named object does not exist in the vault object store, across a full scan of every loose and packed object. The ten-minute window around the index modification time contains no matching invocation in seventy-two transcript files; the nearest is nearly twenty minutes away. Both the thing to be explained and the proposed mechanism failed measurement. The adjudication rule was fixed before the data was read and is applied without adjustment.
- **C2.** What survives that investigation is stronger than what it replaced: the deny-rule prefix anchoring recorded as A5. That is a live structural gap in the default posture rather than an unproven past incident.
- **C3.** The claim that this sandbox refuses repository initialisation is contradicted by an untracked probe repository carrying a real git directory and an initial commit. The contradiction is itself unattributed twice over: no evidence establishes that the initialisation ran under the strict profile, and given A13 the initial commit could not have been written under it with signing in force. Whatever produced that commit either bypassed the signing configuration or ran outside the profile. The claim is neither confirmed nor refuted, and the probe repository cannot serve as evidence about initialisation until its own provenance is established.

## Consequences

- **Hooks execute inside the sandbox.** House policy forbids bypassing them. A pre-commit hook that touches the network or writes outside allowWrite therefore fails for policy, not because the artifact is bad — and by D3 nothing announces which. This produces a non-attributable false red: the inverse of L-033, where a detector is cited outside its scope. Here a detector fails for causes outside its scope. Any adopted profile must first prove the hook set runs clean inside it.
- **Commits cannot be produced under the strict profile while signing is in force.** This was measured while attempting to commit this document. The three-actor loop absorbs it, because the operator commits outside the profile. No unattended mode can absorb it: an agent running under this profile cannot write a commit object at all, which is a ceiling on Mode B under this configuration and not a detail of it. Whether the cause is the credential deny or a broken signing configuration changes the remedy entirely and is unresolved per B8.
- **Policy is inherited silently across repositories** through the machine-global hook and additionalDirectories. This repository is governed by a script it does not contain and does not reference.
- **The deny rules on the Bash plane are largely decorative** while the hook is active, and one of them is not even reachable for the idiom it appears to cover. D5 makes that state explicit rather than leaving it implied.

## Open requirements

Authored as a specification at acceptance, one fixture per item, each with its negative twin and its attribution rule: the egress interception arm with the proxy environment cleared; the strictAllowlist A/B across the two settings files; the glob depth probe; the .git write refusal re-run without the profile; the same path attempted through the shell and through the tool layer; the classifier consistency probe across adjacent paths; a hook-off run isolating the ordering of the two planes; a denial known to originate from a permission rule on a token the hook does not cover, to determine whether the structured field ever discriminates; a working-directory-idiom case added to the corpus of the guard that is actually registered, not the one that is merely tested; the commit refusal re-run outside the profile paired with an existence check on the signing key path; and an account of how the untracked probe repository's initial commit was written at all given the global signing configuration.

## Notes

**Numbering.** This document takes 008. 007 is held for the Claude Code version pin registered as a Layer-0 item in vault/ADR-061. The two accepted vault ADRs conflict on whether ledger-named numbers are reserved; 008 is compatible with both readings, 007 with only one. Resolving that conflict is a vault-side follow-up and is not attempted here.

**Cited authority.** D11 is cited as the governing discipline for the fixtures. It is currently carried by a Proposed ADR inside a project folder, while an Accepted ADR, the lessons file, and executing code in the vault all cite it as settled. Elevating it to an accepted governance ADR is a registered vault follow-up. Until then this document cites it as convention, and marks the citation as such rather than borrowing authority it does not have.

**Provenance.** The two commits carrying this document were written by the operator from outside the strict profile, because the profile refused to write a commit object while this document was being committed. The document could not be landed by the configuration it describes. That is recorded as evidence for B8 and for the second consequence above, not as an aside.
