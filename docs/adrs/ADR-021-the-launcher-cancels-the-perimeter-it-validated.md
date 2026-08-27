---
type: adr
status: accepted
title: "The launcher validates a perimeter and then cancels it: scope is refused for shape before spawn and granted away as a bare tool name at the spawn line, and for the template's default toolset it was never bindable at all"
id: ADR-021
date: 2026-08-13
related-adrs: [harness-pack/ADR-001, harness-pack/ADR-004, harness-pack/ADR-005, harness-pack/ADR-010, harness-pack/ADR-011, harness-pack/ADR-013, harness-pack/ADR-017, harness-pack/ADR-020]
---

# ADR-021 — The Launcher Cancels the Perimeter It Validated

## Status

**Accepted** 2026-08-13 by operator ratification on the text committed at `cff528a`,
git blob `af46262173959cfc184929504fdfad26fe696cdf`.

**The ratification commit is the implementing commit**, on the precedent
`harness-pack/ADR-018` set and `harness-pack/ADR-019` followed. Two edits to
`scripts/guard_pretooluse.py`, five to `scripts/launch_worker.sh`, and four register
literals amended with their reason.

### At acceptance

- **The tree moved under this document**, as the Proposed status anticipated. The
  Basis table was read at `95f508b`; the falsifiers landed at `83027970`. The
  attestation arc advanced `main` in parallel throughout, and the register grew from
  15 rows to 23 while this was written.
- **The Falsifiers section below predicted F2 and F6 would remain RED. That
  prediction was wrong and is corrected there rather than deleted.** Both flipped to
  GREEN on the implementing commit: F2 accused the blanket `return 0` at `guard:83`,
  which D1 removes, and neither row sets `HARNESS_SCOPE`, so both now take the
  fail-closed refusal. Weakening the guard to preserve the prediction would have been
  fitting the repair to the fixture. Independence is instead carried by F-d's allow
  arm, which returns 0 and separates a binding on the declared value from a blanket
  refusal. Seventeen rows did not move, `F-c` included. [verified]
- **`bash -n` is not wired into the suite, and it cost a turn.** On `bash 3.2.57`
  the decision block is a Python heredoc inside a command substitution, and the
  parser scans quotes through the heredoc body: one apostrophe in a Python comment
  left the substitution unterminated and the launcher stopped parsing, reported at
  the line where `$(` opens rather than where the apostrophe is. Folded into OR-5.
  [verified]

The tree is moving under this document while it is written. It is authored in the
worktree `guard-scope/adr-021` at `95f508b`, which the attestation arc advanced from
`076b219` during the authoring session. The Basis table records what was read and at
which blob; divergence at acceptance is declared there rather than discovered later,
on the convention `harness-pack/ADR-013` set.

## Basis

Read verbatim, in the worktree `guard-scope/adr-021`, HEAD `95f508b`, clean tree.

| path | blob |
|---|---|
| `scripts/launch_worker.sh` | `30e72be4325c3c5261c47bf165ff335075535e12` |
| `scripts/guard_pretooluse.py` | `9d1016625cc6b5f6970bf7b2fec26b827ed3f2d9` |
| `tests/run_tests.sh` | `caafce96a23b404444280a0c6f8b875257ca64c5` |
| `templates/spec.mode-b.template.md` | `9604a2d8480c3e588d084e4ea3feb5a682617446` |
| `templates/settings.mode-b.json` | `3767a347d55609cdab27c58c1237eee7b5a101eb` |

Platform measurements were taken on `claude 2.1.229`, by two throwaway probes run
outside any repository of this family. Their scripts are recorded by digest so the
measurement can be repeated rather than believed: probe 1
`34bad71eb417a95e97dc5efc3bd49481c540443f4848661d68230dfa74525a1d`, probe 2
`a2bbc612b3df3a7d193105d93a41c2d725e404d7a42a2824231f2a463a876e05`.

## Context

`harness-pack/ADR-013` D2 named `scope` a declared obligation with no reader. Half of
that has since been answered: `c846887` put three refusals in the launcher's decision
block at `:176-183` — missing, empty, not repo-relative — each on its own line, each
refused and never normalised. `bypass_fc_scope_unread` has stood GREEN since. That
half is closed and this document does not reopen it. [verified]

What was left unstated is the other half, and it is not an omission.

**The launcher grants away the perimeter it just refused to accept malformed.** At
`:358` the spawn line reads `--allowedTools "$TOOLS"`, where `$TOOLS` carries the
bare tool names of `spec.tools`. A bare tool name in the allow-set approves every
path. Measured directly: with `permissions.allow` carrying `Write(/src/**)` and the
run in `--permission-mode dontAsk`, a Write to `docs/` is refused and one to `src/`
succeeds; adding `--allowedTools "Write,Edit,Read,TodoWrite"` to the identical
settings makes the same Write to `docs/` succeed, with no denial recorded. Same
policy file, one flag apart. [verified] (probe 1, runs B and C)

One hundred and seventy-five lines separate the validation from its cancellation, and
both are in `scripts/launch_worker.sh`.

**The guard cannot be the place this is fixed alone.** `guard_pretooluse.py` is a
PreToolUse hook; its payload carries `cwd`, `tool_name`, `tool_input`, `tool_use_id`,
`session_id`, `prompt_id`, `transcript_path`, `permission_mode`, `hook_event_name` —
and no path to the slice's spec, no slice id, and no handle from which either could
be recovered. The spec reaches the worker as the child's stdin at `:370`, which is
prompt text. There is no field in which `scope` arrives. [verified] (probe 1, run A)

**But the guard is reachable by the environment.** A hook process inherits the
environment of the process that launched `claude`: a variable exported by the
launcher before the spawn was read inside the hook, unmodified. [verified] (probe 1,
run A) And the payload for a structured write carries `tool_input.file_path`,
absolute and already symlink-resolved — `/private/tmp/...`, not `/tmp/...` — so a
prefix comparison is only sound through `realpath` on both sides. [verified]

**And the last fact is the one that reorders this document.** The Mode B spec
template ships `tools:` defaulting to `Read`, `Bash`, `Grep`, `Glob`. Neither `Write`
nor `Edit` is in it. A run built from the template writes through Bash — which
permission rules scope by command string, not by path, and which the guard inspects
only against sixteen destructive patterns. For the template's own default toolset,
`scope` was never bindable by either layer. [verified]

That is not a residual. It is the modal case, and a decision that bounded writes for
`Write` and `Edit` while saying nothing about it would be claiming a perimeter it
does not hold — which is the defect `harness-pack/ADR-011` already named for this
repository. D3 exists so that this document does not commit it.

## Decision

### D1 — `scope` binds at two layers, and neither is sufficient alone

**Layer 1, the permission rules.** `--allowedTools` is constructed from
`spec.tools × spec.scope` rather than from `spec.tools` alone: a write-capable tool
is emitted as one path-scoped specifier per declared prefix, never as a bare name.
The CLI accepts specifiers in both spellings — one comma-joined argument and one
argument per rule — with identical results. [verified] (probe 2, runs D and D2)

`templates/settings.mode-b.json` carries no `allow` key; its ten rules are all
`deny`. Under `dontAsk` the entire allow-set is therefore whatever `--allowedTools`
emits, and no bare name in the settings file can win the first match against a
path-scoped rule. The settings template is unchanged by this decision, and the
enforced deploy at `/opt/harness` stays hash-pinned exactly as `ADR-001` D3 and
`ADR-054` leave it. [verified]

**Layer 2, the guard.** `guard_pretooluse.py:83` returns 0 for every `tool_name` that
is not `Bash`, before reading any input. That line goes. The guard reads the declared
scope from its inherited environment and refuses a `Write`, `Edit`, `MultiEdit` or
`NotebookEdit` whose `tool_input.file_path` falls outside it, exit 2, fail-closed on
a malformed or absent value. Comparison is by `realpath` on both sides.

**Redundancy is the decision, not an accident of it.** Layer 1 belongs to the
platform: this repository can configure it and cannot falsify it. Layer 2 is code
this pack owns, tests, and can watch fail on demand. A bound that exists only where
we cannot make it fail is a bound we are trusting, not verifying, and this family of
documents exists because those are different things.

### D2 — The delivery seam is the environment, and the decision line pays for it

`scope` reaches the guard as an environment variable exported by the launcher
immediately before the spawn at `:354-360`. Nothing is rendered per run: no settings
file is generated, no policy leaves the hash-pinned tree.

Reaching the spawn requires `scope` to survive the decision line, and that carries
two constraints which are part of this decision and not of its implementation.

**The two reads change together or not at all.** `:184` prints six fields after `OK`;
`:192` reads them with `CRITERIA` last, and therefore greedy. A seventh field added
to `:184` and not to `:192` produces no error: it is absorbed into `CRITERIA`, and
the run proceeds with a corrupted `ADR-004` D7 gate scope. The two lines are amended
in one commit.

**A fourth obligation joins the three at `:176-183`: no whitespace.** The transport
is space-separated. A prefix containing a space would split its field and shift every
field after it. The obligation is refused, never normalised, on the same footing and
for the same reason as the three `c846887` added: a scope the operator did not
declare must not be manufactured by trimming one they did.

### D3 — Enforceability is computed and declared, never assumed

The launcher derives from `spec.tools` whether `scope` is bindable for that run, and
the receipt records the answer.

A spec whose tools are write-capable structured tools is bindable: both layers apply,
and the receipt records `scope.enforced: true` with the emitted specifiers.

A spec carrying `Bash` is **not** bindable. Bash writes are bounded by neither layer,
and the run is still launched — Mode A remains the escape hatch, and refusing every
Bash spec would break the pack's own default template. But its receipt records
`scope.enforced: false` naming `Bash` as the reason, and no artifact of that run
asserts a write perimeter.

This is the whole of what separates this document from the defect it repairs. A
narrow `scope` on a Bash spec buys no narrowing today, and after this decision it
will still buy none — the difference is that the run will say so.

**What this leaves open, stated so no reader has to infer it.** The sound bound for
Bash is at the operating system, not in a string filter: the sixteen `DENY` patterns
in the guard are already the pack's own admission that command inspection does not
decide. That is OR-3, and it is a design study, not a paragraph. The one probe run
aimed at this gap did not measure it: the child emitted a compound command whose
first element was refused for an unrelated reason, so what was measured was the
severity of compound matching. The gap is argued here, not measured, and is labelled
accordingly. [inferred]

### D4 — Enforcement enlarges the receipt's disclosure surface, proportionally

Every refusal measured here — by permission rule and by hook alike — was recorded in
the child's `permission_denials` carrying the absolute `file_path` **and the entire
attempted `content`**. [verified] (probe 1 run B, probe 2 runs D, D2, F)

`ADR-010` D1 copies that array into the receipt verbatim and unmodified, and
`ADR-020` D1 censuses it as the receipt's primary arbitrary-input carrier. The
consequence is exact: this decision increases the receipt's disclosure surface in
direct proportion to how well its bound works, because every refused write deposits
its own payload in an artifact the operator guide calls safe to publish.

This is declared here and repaired in `ADR-020`'s family, as OR-4. A decision that
closed a measured gap by widening one already measured, silently, would be a worse
document than one that closed nothing.

## Falsifiers

Two rows, and the register's existing rows on this subject are why there are two and
not one.

`bypass_fd_scope_unenforced` — differential, and differential by necessity. It asks
the guard for a verdict on one identical payload under two declared scopes: a Write
to `docs/` with scope `src/` must be refused, and the same Write with scope `docs/`
must be allowed. A hard-coded governance deny-list answers both arms identically and
leaves this row RED; only a real binding on the declared value separates them. The
allow arm is the control: a guard that refuses every write is bounded exactly as
little as one that refuses none.

`bypass_fa_tools_widen_beyond_scope` — the launcher's row, built on the
`LAUNCH_DRYRUN` seam at `:208` that F-b, F-c and F8 already use, and inheriting
F-c's scaffolding rather than restating it. A legal spec with `scope: ["src/"]` and a
write-capable toolset must not produce an unrestricted `--allowedTools`.

**Relations, stated so the lattice stays checkable.** `F2` measures the guard's tool
filter alone and goes green when Write and Edit are read at all. `F6` measures the
composition of three layers and goes green on either repair. Both are satisfied by a
hard-coded deny-list, which is why neither can stand in for `fd`. `F-c` measures
refusal of a malformed scope and is GREEN; `fa` measures the granting-away of a
well-formed one, thirteen lines from it in the same file, and is RED. The two are
opposite verdicts on one field.

`F2` and `F6` were expected to remain RED. **They did not, and the expectation was
the defective half.** Both interrogate the guard without delivering a scope, and D1's
fail-closed refusal satisfies both greens. Recorded here rather than corrected away:
a decision that quietly deleted its own failed prediction would be worth less than one
that keeps it. The independence of the two layers is carried by F-d's allow arm.

## Provenance

`c846887` — "feat(launcher): STOP on a Mode B spec whose scope violates the declared
shape", 2026-08-11 — implemented the shape half of `ADR-013` D2 before this document
existed, and `bypass_fc_scope_unread` records it. It is read here on the footing
`harness-pack/ADR-008` set: the decision is recorded where the code already stands,
and only the tense was ever wrong.

## Open records

- **OR-1 — the applied perimeter is attested by nothing.** The receipt will carry the
  *declared* scope. No artifact binds declared to *applied*: a run that enforced
  nothing and one that enforced everything produce indistinguishable receipts. This
  is `ADR-011`'s shape reproduced one layer inside its own repair. Family
  `ADR-018`/`ADR-019`.
- **OR-2 — the write-capable tool set is hard-coded against a moving surface.** Four
  names on `claude 2.1.229`. A tool added by the platform is uncovered, and it is
  uncovered by silent permissiveness: no error, no red, one write that passes.
- **OR-3 — Bash writes need an OS bound.** See D3.
- **OR-4 — `permission_denials` carries attempted content into the receipt.** See D4.
  Routed to `ADR-020`.
- **OR-5 — the decision line is a positional format with a greedy tail, no
  round-trip test, and a shell-level fragility nothing gates.** This decision amends
  it under duress. Beyond the greedy tail: on `bash 3.2` the block's Python body is
  quote-scanned by the shell, so an apostrophe in a comment breaks the file at parse
  time. `bash -n` catches it and is not in the suite. The format deserves its own
  document.
- **OR-7 — `scope.enforced` is computed and not yet written.** D3's verdict travels
  the decision line and reaches the DRYRUN preview; `scripts/write_receipt.py` was
  not read in this arc and is not amended blind. Until it is, the enforceability
  verdict exists at launch and not in the artifact, which is OR-1's shape one field
  narrower.
- **OR-6 — `ADR-009` names an ADR contract checker that this repository does not
  wire.** `scripts/` holds none, and `tests/run_tests.sh` mentions `docs/adrs` once,
  in a comment. This document will be committed without any gate reading its
  frontmatter — which is `ADR-013`'s subject applied to the ADR corpus itself.
  [inferred: the checker may live in `harnesswright`, which was not read.]

## Amendment — 2026-08-25: the implementing commit is split, and this is its guard half

**Appended, not corrected.** Everything above is left as ratified.

Status records the ratification commit as the implementing commit: two edits to
`scripts/guard_pretooluse.py`, five to `scripts/launch_worker.sh`, four register
literals. That commit was never applied to `main`. What lands with this document is
its guard half alone:

| declared at ratification | lands here | deferred |
| --- | --- | --- |
| `guard_pretooluse.py`, 2 edits | yes, +90 −1 | — |
| `launch_worker.sh`, 5 edits | no | D2 delivery, D3 `scope.enforced` |
| register literals, 4 | 3 | `bypass_fa_tools_widen_beyond_scope` |

**What this half buys, and what it does not.** D1 lands: the four write tools have
their own branch, the declared value decides, and absence is refused. D2's delivery
seam and D3's verdict do not: the launcher exports nothing and computes nothing, so
`HARNESS_SCOPE` reaches the hook only when a caller sets it. The Mode B template in
tree declares `Read`, `Bash`, `Grep` and `Glob` — no write tool — so a run conforming
to it does not reach the new branch at all. This commit closes three register lines
and does not change what a template-conforming Mode B run is permitted to do. Stated
here so no reader has to infer it.

**The second falsifier does not land.** The Falsifiers section names two rows.
`bypass_fd_scope_unenforced` lands with its fixture. `bypass_fa_tools_widen_beyond_scope`
does not: it measures the launcher, and a register row against a subject this commit
does not repair is the accumulation `ADR-017` exists to make expensive. It stays on
the branch until the launcher half lands.

**F2, F6 and F-d were observed, not derived.** Two worktrees of `f113591` differing in
`scripts/guard_pretooluse.py` and this document's fixture and in nothing else, both
with the sibling `harnesswright` and `verity` CLIs resolvable, full suite run on each,
2026-08-25:

    f2   control RED           treatment GREEN
    f6   control RED           treatment GREEN
    f-d  not present           treatment GREEN

Three rows move between the arms and no fourth. Register completeness holds at 68 rows
in the control and 69 in the treatment. Outputs: `S1-CTL-2026-08-25.txt` sha256
`4aa1d645265978ceca537f315fc320c1f634e0bbc96419c67deb99235ed0b55d`,
`S1-TRT-2026-08-25.txt` sha256
`fdcc0a4ffc341e56683f125f03ef73837fd141226a30618e7c58f905c47c45fd`. [verified]

**OR-8 — `bypass_ft_emitter_output_rejected_by_cli` declares RED and observes GREEN**,
at `f113591`, with nothing from this document applied. It measures the `claude` CLI's
refusal of a malformed `--agents`, which the CLI now performs. The row diverges
identically in both arms above, so it is not this commit's to move: D3 requires the
literal be amended in the commit that says what changed, and this one did not change
it. The suite exits 1 on both arms, on this row alone. [verified]
