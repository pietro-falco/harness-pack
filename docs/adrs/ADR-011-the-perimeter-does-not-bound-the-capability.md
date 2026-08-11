---
type: adr
status: proposed
title: "The allowlist closes the tool plane and bounds nothing inside it: Bash substitutes for every tool withheld, and the only content-inspecting layer reads one plane"
id: ADR-011
date: 2026-08-11
related-adrs: [harness-pack/ADR-001, harness-pack/ADR-008, harness-pack/ADR-009, harness-pack/ADR-010]
---

# ADR-011 — The perimeter does not bound the capability

## Status

**Proposed** (2026-08-11; docs-only). No code, no fixture, no schema change and no
constitution edit ships with this commit. Per the two-commit lifecycle stated in
`docs/STACK.md` § Agent contract, acceptance is a separate operator commit; the
implementation lands after that flip and carries its red fixtures in the same
commit as the green.

## Numbering note

011 follows the filename maximum (`ADR-010`) in `docs/adrs/`. A sweep for the token
`ADR-011` returns zero hits in this repository and thirty-one in the vault, all of
them referring to the vault's own ADR-011 on scanner selection. That is a different
namespace and does not consume this number; `vault/ADR-051` D3 settles it, as
`ADR-009` records for its own number. The gap at 007 is untouched.

## Basis

| Repository | HEAD |
|---|---|
| `~/Code/harness-pack` | `c9d67704afb19db50c4df581e4d5e8f7359e3eec` |
| `~/Code/harnesswright` | `edb12a499615bf12aa80e5db1c67a268cb247114` |
| `~/Code/verity` | `4dc016b354f3a6eb953590167b46bc29eacf3fcb` |
| `~/Code/lanewright` | `ab77a81da6eecc4f7942c1e508b319c844049da8` |
| `~/Obsidian-Vault` | `a9f0e758fdf6e4d6644b01c70ff05370f8a0f1d3` |
| `~/Code/harness-smoke` | `f8b83699b681f555b8fd6213bb80c14bdc1675e7` |

Blobs read for this document, by digest at the basis:

| Artifact | sha256 |
|---|---|
| `scripts/guard_pretooluse.py` | `2a4b861f8dd1fe8c2abaa2c2872ae483d3b42dc381ef3f5cde589e719795d07b` |
| `templates/settings.mode-b.json` | `36cabfb418e499fd5dc1be105312ab7348c0c8f08355d7f28d30863146eaf7da` |
| `docs/STACK.md` | `37ce7d581c65846da7a1718168026e69213de3996e9378720df4d697db8ecb3b` |
| `.verity/claims.json` | `564a4b44040b15e18e53321bc4049bab6b6eb11255707ea34fae40721bc5cc6c` |

The enforced copy at the enforced path carries the same guard digest as the pack
source at this basis. Nothing gates that they agree; see Not measured.

Three fixtures were executed from the operator shell on 2026-08-11, each in a
scratch directory under the temporary root with an EXIT trap, with a digest of all
six repositories taken before and after the run and found identical:

| Fixture | Exit | Verdict |
|---|---|---|
| `tests/bypass_f2_guard_nonbash_fixture.sh` | 1 | RED |
| `tests/bypass_f4_deny_literal_fixture.sh` | 1 | RED |
| `tests/bypass_f6_permission_layers_write_fixture.sh` | 1 | RED |

The fixtures were untracked at authoring time and are staged but uncommitted at
this basis. They land with the implementation, not with this document.

## Context

Four things decide whether a Mode B worker's tool call happens, not three.

- **The allowlist.** `launch_worker.sh:343` passes `--allowedTools "$TOOLS"`. The
  list comes from `spec.tools`, which the planner always fills (`:116`) and on
  whose absence the launcher STOPs (`:150`). This layer has a closed complement by
  construction: a tool not named is not admitted, including a tool that does not
  exist yet.
- **The declarative plane.** `templates/settings.mode-b.json` carries ten deny
  rules: eight `Bash(...)` forms and two bare tool names.
- **The dynamic plane.** The PreToolUse hook, matcher `*`, resolved by absolute
  enforced path.
- **The human.** `launch_worker.sh:344` passes `--permission-mode dontAsk`, so
  nothing is ever asked.

The first layer is the right shape and it works. The defect is not that the
perimeter is open. It is that a closed perimeter bounds nothing when one of its
members is a universal substitute for the rest.

`bypass_f4` measures that substitution directly. Through Bash, with the run not
halted, six commands whose effect is destruction or hook disablement were allowed:
two Python one-liners, a Perl one-liner, `truncate -s 0`, a redirection of
`/dev/null` over the constitution, and `git config core.hooksPath /dev/null`. The
same two effects in their enumerated spellings were refused with exit 2. The guard
is reached, parses these payloads, and can say no. It does not, because it matches
words and the effects have unbounded spellings.

The other two layers do not close the gap on the plane that writes files.
`bypass_f6` measures that the declarative plane carries zero rules naming Write,
Edit, MultiEdit or NotebookEdit — while its own control shows that bare tool names
are expressible there, since `WebFetch` and `WebSearch` are denied exactly that
way. `bypass_f2` measures that the dynamic plane returns 0 for every call whose
tool name is not `Bash`, at `guard_pretooluse.py:83`, before any input is read.

Two prior decisions in this repository already assign that ground and are not
occupied. `ADR-001` D1 decides that the mode-b settings template gains, in its own
words, Edit/Write denies on any path under `.claude` or `.harness`; the guard half
of that same decision landed and is visible in the DENY list, the settings half did
not. `ADR-008` D5 assigns the tool layer — Edit, Write, Read, WebFetch, MCP —
to the permissions plane as its enforcement plane, and states that the partition
works because the two planes never overlap. The partition holds. The plane it
assigns the writing tools to is empty for them.

The settings file states the reason for the wide matcher in its own comment: the
guard also carries the kill-switch, which must neutralise a run in flight across
Edit and Write, not only shell-outs. The matcher is `*`. The body reads one plane.

## Decision

### D1 — What an enforcement rule binds is an effect on a path, never a tool name and never a command spelling

Names and spellings are proxies whose complement is open. A rule written over
either is stale the moment a tool ships, a runtime is installed, or a spelling is
found — and its staleness is silent, because nothing in the pack measures the
complement of a list.

Every enforcement rule this pack adds from here is expressed as a predicate over
the write target. Rules already written over names or spellings are not the
boundary and are labelled accordingly (D2, D3).

This is the decision that makes the three that follow cost nothing to keep. A tool
that does not exist yet, a command spelling not yet enumerated, and a language
runtime not yet installed are all covered on the day they arrive, without an
amendment to this document.

### D2 — On the Bash plane, the DENY list stops being the boundary and is labelled as what it is

The sixteen patterns stay. They are defense in depth, which is what `ADR-001` D1
calls them in its own heading, and they make a bad call fail loudly inside a
session. They are not load-bearing, they are not counted in any coverage claim, and
the file says so at the point of definition.

The boundary for the Bash plane becomes a predicate over write targets, per D1.

**Falsifier:** `bypass_f4`, RED at this basis — 6 of 6 effect-equivalent commands
allowed while their enumerated spellings are refused. Green, in the fixture's own
words: when the effect is refused however it is spelled.

### D3 — The declarative plane carries the rules two prior decisions already assign to it

`settings.mode-b.json` gains deny rules covering writes to the governance-critical
paths: the constitution, the gate's own oracle under `.verity/`, the test suite,
and any path under `.claude` or `.harness` as `ADR-001` D1 already decided.

This is defense in depth and not the boundary either. The allowlist is the closed
layer; a declarative deny is what remains true when a spec's tools list is wrong,
when the launch line is edited, and when a run is started outside the launcher.

**Falsifier:** `bypass_f6`, RED at this basis — 0 of 10 rules name a writing tool,
while its control shows bare tool names are already denied there.

The fixture states the constraint that keeps this decision honest: a layer-1 deny
rule alone clears `bypass_f6` and leaves `bypass_f2` red. D3 does not discharge D4,
and an implementation that lands D3 alone has not answered this document.

### D4 — The guard evaluates every call the matcher hands it, or the matcher stops claiming to

The matcher is `*` and the file's own comment gives the reason. Either the guard
evaluates non-Bash calls against the write-target predicate of D1, or the matcher
narrows to the plane the body actually reads and the comment is corrected. The
gap between a wide matcher and a narrow body is not a configuration detail: it is a
stated reason for a setting that the code does not honour.

**Falsifier:** `bypass_f2`, RED at this basis — the same effect is a stop condition
through Bash and unexamined through Write and Edit, with the run not halted, which
is the state a run is in while it is running. Green, in the fixture's own words:
when a Write or Edit whose target is a governance-critical path is refused with the
run NOT halted.

## Verification

Three fixtures, red before green, in the implementation commit. All three are red
at this basis and were red before this document was authored.

| Fixture | Subject | Green when |
|---|---|---|
| `bypass_f4` | the DENY list read against the two effects its own docstring names | the effect is refused however it is spelled |
| `bypass_f6` | the composition of the declarative plane, the dynamic plane, and the human | at least one layer refuses a Write to a governance-critical path while the run is unattended |
| `bypass_f2` | `guard_pretooluse.py:83` | a Write or Edit whose target is a governance-critical path is refused with the run NOT halted |

Each fixture carries its own positive control, in the sense `ADR-008` D3 requires:
`bypass_f4` shows the same two effects refused in their enumerated spellings before
showing six equivalents allowed; `bypass_f6` shows that bare tool names are already
deniable in the declarative plane; `bypass_f2` shows a Bash `rm` blocked with exit 2
in the same session in which a Write returns 0. None of the three can be cleared by
a change that makes the pack refuse everything.

For this docs-only commit:
exactly one path changed

git show --stat --oneline HEAD

post-commit truth is the committed blob, never the working tree

git show HEAD:docs/adrs/ADR-011-the-perimeter-does-not-bound-the-capability.md | head -8

the declared two-command gate, both halves

bash tests/run_tests.sh
node "<verity entrypoint>" verify .verity/claims.json


## Consequences

- Three of the four layers gain a rule shaped over paths rather than over names.
  The allowlist is unchanged: it is already the right shape.
- The DENY list survives with a demotion in status and no change in content. Any
  future coverage claim that counts it is a defect by this document.
- A spec that declares no writing tool no longer buys a run that cannot write; it
  buys a run whose writes to the governance paths are refused by a layer that does
  not depend on the spec being right.
- `ADR-001` D1's settings half is discharged, three years of drift after the guard
  half landed alone. Whether that decision was ever accepted is open (OR-1).
- The cost of a new tool shipping in the executor drops to zero for this pack: D1's
  predicate does not enumerate tools.

## Non-goals

- `--permission-mode dontAsk` is not removed here. The unattended run is the point
  of Mode B; this document bounds what an unattended run can reach, not whether it
  is unattended.
- `spec.scope` and `spec.budget` are REQUIRED fields with no reader. That is a
  separate defect with its own fixtures and its own document.
- The tamper detector is never invoked by the launcher, and no automated check runs
  verity. Separate document.
- The receipt records neither the prompt nor the calls. Separate document.
- The slice lease is scoped per-toplevel rather than per-repository. Separate
  document, and the one that gates parallel workers on one repository.

## Open requirements

- **OR-1 — `ADR-001` states no status.** It carries no `status:` frontmatter key
  and no Status heading. The same holds for `ADR-002`, `ADR-003` and `ADR-004`. D3
  discharges a decision whose acceptance is not established from any blob read for
  this document. Resolve under `ADR-009`'s contract checker and its form
  precedence; do not resolve by recall.
- **OR-2 — shadowed rules are unannotated.** `ADR-008` D5 requires every Bash deny
  rule whose tokens the hook already covers to be removed or annotated SHADOWED.
  Seven of the ten rules are so covered and none is annotated. `ADR-008` is
  Proposed; this is recorded against it, not decided here.
- **OR-3 — two receipts cited as prior art were not opened in this arc.** The runs
  of 2026-08-10 on the smoke repository are held to show an artifact born through
  Bash under a tools list excluding every writing tool. No decision in this
  document rests on them; `bypass_f4` carries that weight from a measurement taken
  today. Read them and either promote the claim or withdraw it.
- **OR-4 — the effective allowlist of a run may not be recorded.** The dry-run
  decision line prints the tool list. Whether the receipt carries it is not
  established. If it does not, the perimeter of a completed run cannot be
  reconstructed from its receipt, and every claim about what a past run could reach
  is unfalsifiable.
- **OR-5 — privacy-lint scope over `tests/` is unread.** Six privacy claims exist;
  one was read in full. `docs/adrs/` is excluded from that one; `tests/` is not.
  The fixtures land in a later commit governed by claims whose run strings have not
  been read.
- **OR-6 — the class, not the instance.** The defect shape behind D3 is a declared
  obligation with no reader. One fixture in this repository already computes that
  predicate for a single field. Generalising it into a standing gate over every
  REQUIRED template field belongs to the document that owns those fields.

## Not measured

Under `ADR-008` D6 these are tier B and are recorded here rather than cited as
established properties anywhere.

- That the enforced copy of the guard matches the pack source at launch. The two
  digests agree at this basis, by observation and not by any gate.
- Whether any layer other than the four named participates. The claim of four rests
  on reading the launch line and the settings file, not on an exhaustive search.
- The divergence of `lanewright` from its remote. The probe that measured the other
  five repositories masked its own exit status on that repository.
- The contents of any receipt under the smoke repository.

## Notes

**Lessons.** Two are carried by this arc and need allocation in the lessons file
rather than letters invented here.

- A falsifier can be green at birth because of a word boundary. One fixture in this
  set records that its first version matched a bare substring and came out green on
  a workflow that does not contain the token, because a longer word contains it.
- Staged is not untracked. A document written in the middle of this arc recorded
  nine fixtures as untracked and therefore as no violation; they were staged. An
  explicit-path staging discipline does not protect a commit from an index loaded
  elsewhere, because the commit takes the whole index.

**Provenance.** The measurements behind this document were taken from the operator
shell in a single turn per probe, each with the script's digest recorded before
execution and its exit code after. No measurement was taken by an agent session
inside the tree it measured.
