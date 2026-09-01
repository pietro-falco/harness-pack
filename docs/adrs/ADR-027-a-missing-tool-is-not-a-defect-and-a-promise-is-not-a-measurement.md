---
type: adr
status: proposed
title: "A missing tool is not a defect and a promise is not a measurement: the suite never enumerates the machine it needs, and the README's guarantees are bound to nothing"
id: ADR-027
date: 2026-08-30
related-adrs: [harness-pack/ADR-006, harness-pack/ADR-009, harness-pack/ADR-017, harness-pack/ADR-020, harness-pack/ADR-024]
---

# ADR-027 — A Missing Tool Is Not a Defect, and a Promise Is Not a Measurement

## Status

Proposed. No implementation is written against this ADR while it is
Proposed. What ships beside it is one falsifier, declared RED, and the
README repair that needs no decision. D3 below is the clause that says
why a falsifier is admissible here and an implementation is not.

## Context

The README's `## Requirements` section read, in full:

> Python 3 and bash. No packages to install, no daemon, no network
> calls, nothing listening on a port. CI runs on Python 3.12.

Measured against the suite the same README tells a reader to run: the
tool list is short by eleven names, "no packages to install" is false
for `node`, `shellcheck` and `gitleaks` at least, and "no network
calls" is false twice over. "No daemon" and "nothing listening on a
port" hold, and so does the CI version. That paragraph is repaired in
this commit, because a false sentence needs no ADR to become a true
one.

What needs an ADR is the two structural facts the sentence was resting
on. First: nothing in this repository enumerates what the suite needs
from the machine before the suite starts running, so an absent tool
arrives as a FAIL, and a FAIL in this repository is an accusation
against the code. Second: the README states guarantees in prose under a
heading that says `## Every claim has a fixture`, and its own claims
have none. Both are the same defect wearing two costumes: an assertion
nothing can refute.

## Basis

Measured at 818a2e1, on the tracked tree plus the untracked fixtures
present beside it. Outside this basis the statements below are
unverified, not false.

- `tests/run_tests.sh` contains exactly one `command -v` in its whole
  length. It guards `shellcheck`, and the absence branch spends
  `record_unmeasured` and prints an `unattrib` line, which is the
  correct handling and the only instance of it.
- Every other external prerequisite is checked, when it is checked at
  all, inside an individual fixture, by that fixture's own `broken()`,
  which exits 2. ADR-017 D4 routes exit 2 to FAIL unless the row
  declares `UNMEASURED-2` in the register's third column. Ten rows
  declare it; the rest do not.
- Nothing in `tests/run_tests.sh` reads the effective uid: `id -u`,
  `EUID` and `whoami` have zero occurrences.
- The suite shells out to `git`, `python3`, `node`, `shellcheck`,
  `gitleaks`, `ssh-keygen`, `ssh-agent`, `shasum`, `tar`, `cmp`,
  `diff`, and the `claude` binary. `node` alone appears in dozens of
  invocations across the fixtures, because the launcher's two
  collaborators are Node CLIs.
- Two fixtures make real network calls:
  `tests/adr008_falsifier_fixture.sh:575` and
  `tests/bypass_ft_emitter_output_rejected_by_cli_fixture.sh:86`, both
  through `claude -p`.
- One fixture reads outside this repository:
  `tests/bypass_ft_scoped_gate_out_of_scope_red_fixture.sh:46` globs
  under `$HOME` for a deployed thread gate, and correctly reports
  UNMEASURED when it finds zero or more than one.
- `tests/bypass_att_no_subject_no_statement_fixture.sh:142` fabricates
  its condition with `chmod 000`. That does not make a file unreadable
  to uid 0, so under root the fixture's condition is not the condition
  it declares.
- `.verity/claims.json` carries twelve claims. Six are privacy lints,
  five are drift guards over `docs/STACK.md` headings, one is the
  publication boundary. None of them reads `README.md`, and no fixture
  under `tests/` does either.

The suite's own tail already records the first half of this as an open
fixed point, in the comment above `UNMEASURED_REGISTER`: an
environment-conditional row "has no honest entry" in a register that
compares in both directions, and closing it "needs a second,
environment-conditional class -- a change to ADR-017 D4/D6 semantics,
which is a decision and not an edit". D1 is that decision.

## Decision

### D1 — The environment is enumerated before the first invariant runs, and an absent prerequisite routes to UNMEASURED by name

`scripts/preflight_env.sh --report` enumerates, before any invariant
executes, the external prerequisites this suite requires and the
effective uid. Its contract:

- one `absent <name>` line on stdout per declared prerequisite that
  does not resolve on `PATH`;
- one `uid <n>` line, always, carrying the effective uid;
- exit 0 when the environment is complete, exit 3 when it is not.

Neither exit is a failure and the program judges nothing. It reports.
`tests/run_tests.sh` calls it first and uses the names: an invariant
that declares a prerequisite the report named absent is routed to
UNMEASURED **under its own name**, through the same `record_unmeasured`
and `unattrib` path the shellcheck step already uses, and is never
routed to FAIL. Under uid 0, an invariant that declares it fabricates
its condition with permission bits is UNMEASURED for the same reason
and by the same mechanism: `chmod 000` is not a refusal to root, so the
fixture's condition was never built, and a verdict over a condition
that was not built is neither a pass nor a fail.

The rule this enforces is one sentence: **a FAIL accuses the code,
never the machine.** ADR-017 spent an entire decision making
`ALL TESTS PASSED` mean something; a run that prints `TESTS FAILED`
because a host has no `gitleaks` spends that meaning on a fact about
the host. The name is what makes the difference legible, and a count is
not a substitute: `unattrib` lines say which invariant went unmeasured
and why, and a preflight that only said "3 tools missing" would be the
cardinality-not-membership failure ADR-017 D5 already refuses
elsewhere.

The declared prerequisite list is data, not derivation, and lives
beside the preflight rather than inside it, so that the README's
`## Requirements` section and the preflight can be held to the same
list rather than to two lists that agree today.

### D2 — A README line that states a guarantee cites a claim, and a gate refuses one that cannot be checked

Every line of `README.md` that asserts a guarantee carries a trailing
marker of the form `[claim: <id>]`, naming an id in
`.verity/claims.json`.

`scripts/gate_readme_claims.sh --readme F --claims F --verdicts F`
reads every marker and answers:

- exit 0 when every cited id is present in the claims file and green in
  the verdicts file;
- exit 1 when a cited id is absent from the claims file, or present and
  not green;
- exit 2 when an input is missing or malformed.

`--verdicts` is one `<id> <green|red>` line per claim, produced by the
verity step the gate already runs. Greenness is a verdict this
repository computes once; a gate that recomputed it would be a second
implementation of it, and two implementations of one verdict is the
drift ADR-009 was written to avoid.

The gate runs in `tests/run_tests.sh` and in CI. Its effect is narrow
and worth stating plainly: it does not make the README true. It makes
an unbound guarantee impossible to leave in the README, which is the
difference between prose a reader must take on trust and prose that
goes red when the thing it promises stops being measured. The heading
`## Every claim has a fixture` becomes a statement about this document
too.

### D3 — A Proposed ADR ships the falsifier that would refute it, declared RED, and nothing else

There is a contradiction in this repository's own machinery and it
blocks this ADR from existing at all.

`scripts/gate_adr_contract.sh` rejects a change that ADDS a file under
`docs/adrs/` and touches no file on the measured surface declared in
`scripts/measured_surface.conf` (`scripts/*.sh`, `scripts/*.py`,
`tests/*.sh`). The two-commit lifecycle in force here wants the first
commit to be a Proposed ADR and nothing else, because ADR-006's
non-goal and ADR-009's application of it to itself both forbid writing
code against an ADR that is not yet Accepted. Installed as the
pre-commit hook ADR-009 D6 describes, the two rules together make a
Proposed ADR unproposable: docs-only is rejected by the gate, and
anything that satisfies the gate is code against a Proposed ADR.

**Resolution: the commit that proposes an ADR ships the falsifier that
would refute it, declared RED in the register of
`tests/run_tests.sh`, and ships no implementation.**

This is not a loophole and it is not a weakening of either rule.

- A falsifier is not an implementation. It states the ADR's question in
  executable form and answers nothing. Its declared state is RED
  precisely because the ADR is Proposed: the subjects it interrogates
  do not exist, and the row says so. What acceptance buys is the right
  to turn it GREEN.
- The contract gate is satisfied by the file that will hold the ADR
  accountable. The gate's purpose, in its own header, is that "a
  change that ADDS a file on the ADR surface" must also touch the
  surface this repo's linters read. A falsifier under `tests/*.sh` is
  the most load-bearing thing that could satisfy it, and strictly
  better than the comment-only edit to a measured file the gate's
  declared residue R1 already admits.
- ADR-017 D6 is satisfied without strain: the declared state is read
  off the fixture's own header, and the header declares RED because the
  subjects are absent, not because a run said so.

The alternative resolutions, and why they are not taken. Exempting
`status: proposed` additions from the gate would make the gate depend
on a `status:` field, which its header refuses in its first rule and
for good reason: a field an author writes cannot gate that author.
Landing the ADR and its implementation in one commit abolishes the
Proposed state and with it the review the state exists for.

## Falsifier register

**FT-36** — `tests/bypass_ft_env_unchecked_and_readme_unbound_fixture.sh`.
Registered `RED BROKEN`. Declared RED, and RED is the state at this
basis: both subjects are absent from the tree.

Four arms, both directions on each decision, each with a
post-construction control, because a scenario that was not built
measures nothing and `|| exit 2` inside a command substitution leaves
only the subshell:

| arm | scenario | want |
| --- | --- | --- |
| D1-neg | a `PATH` of symlinks resolving `git` and not `node` | `absent node`, rc 3 |
| D1-pos | the same `PATH` plus `node` | no `absent node`, a `uid` line, rc 0 or 3 |
| D2-neg | a doctored README citing an id absent from the claims file, every real claim green in the verdicts file | rc 1 |
| D2-pos | a doctored README citing a real id, green | rc 0 |

The D2-neg arm hands the gate an all-green verdicts file on purpose, so
that the absent id is the only ground left to refuse on. The positive
arms are not politeness: a preflight that named every tool absent, and
a gate that refused every document, would satisfy the negative arms and
bind nothing, and a zero that cannot be made to move is not a
measurement.

While the subjects are absent both positive arms are vacuous, and the
fixture says so in those words rather than counting them as arms that
passed. Both negative arms report that they are RED **because the
subject is absent, not because the prerequisite or the claim id is** --
the distinction this whole ADR is about, applied to its own falsifier.

## Declared limits

**L1 — FT-36 measures the report and the gate, never the routing.**
Whether `tests/run_tests.sh` actually routes a named absence to
UNMEASURED-by-name rather than to FAIL is a property of the suite, and
measuring it needs a doctored suite run against a doctored PATH. FT-36
does not do that. The half of D1 that matters most to a reader is
therefore declared here and unmeasured by this falsifier; closing it is
a second fixture, authored at acceptance beside the routing it
measures.

**L2 — the falsifier is itself an instance of the defect D1 names.**
FT-36 needs `node` and `git` to build its own two arms, and on a host
carrying neither it exits 2, which the register routes to FAIL. It is
registered `BROKEN` and not `UNMEASURED-2` deliberately: an eleventh
`UNMEASURED-2` row would need the register's own count amended, and
more importantly `UNMEASURED_REGISTER` compares membership in both
directions and has no honest entry for an environment-conditional row
-- the suite's tail argues this at length and leaves it open. D1 is the
decision that would give such a row a home. Until then this falsifier
carries the disease it describes, in the open.

**L3 — D2 binds a sentence to an id, not to a meaning.** A guarantee
that cites a green claim whose `run` tests something else satisfies the
gate. What D2 removes from this repository is the UNBOUND sentence, not
the mis-bound one. Binding meaning is not mechanisable here and is not
claimed; what the marker buys is that the binding is visible, in the
same document, to a reader who can judge it.

**L4 — the preflight reports, and the routing is the suite's.** Split
on purpose. A preflight that decided verdicts would be a second gate
beside `run_tests.sh` with its own opinion about what a failure is; a
reporter has no opinion, and the suite that already owns `fail`,
`unmeasured` and the two registers keeps owning them.

**L5 — the README's `## Requirements` text repaired in this commit is
prose, not a measurement.** It is true at this basis and nothing keeps
it true. Under D2 it would cite a claim; under D1 it would agree with
the preflight's declared list by construction. Both are consequences of
acceptance, and until then this paragraph is exactly the kind of
sentence this ADR exists to distrust.

## Consequences

- Until D1 lands, a fresh clone on a host without `gitleaks`,
  `ssh-agent` or `node` prints `TESTS FAILED` and accuses this
  repository of a defect it does not have. That is the state today; the
  README now says so instead of denying it.
- Under uid 0 the suite is not merely noisier, it is wrong in a
  specific place: `bypass_att_no_subject_no_statement`'s `chmod 000`
  branch does not fabricate its condition, and the row's verdict is
  about a condition that never existed. D1 turns that into UNMEASURED.
- `tests/run_tests.sh` grows one register row in this commit and
  nothing else. The preflight call and the README gate are acceptance
  work.
- The `UNMEASURED_REGISTER` fixed point the suite records gets an
  answer for the first time. Amending ADR-017 D4/D6 semantics to admit
  an environment-conditional class is part of D1's acceptance, not a
  side effect of it.
- The contract gate's declared residue R1 is untouched: the gate reads
  paths and not diffs, and D3 does not change that or claim to.
- This document's own repair missed a guarantee one section away from
  the one it was repairing, in the same commit that decided guarantees
  must be bound. The Quickstart kept `expect: ALL TESTS PASSED` while
  `## Requirements` was being rewritten directly above it, and the
  rewritten Requirements list omits the one prerequisite whose absence
  actually stops the suite certifying. An attentive human reading for
  exactly this defect, holding it in mind, corrected one sentence and
  walked past two others. That is the argument for D2 stated at full
  strength, and it comes from the defect and not from the proposal:
  review found the instance it was looking for and still left two
  behind, because nothing failed when they stayed.

## Open records

- OR-1: which invariant declares which prerequisite. D1 decides the
  mechanism and the report's shape, not the mapping. The mapping is
  per-fixture data, authored at acceptance, and it is where the real
  work is.
- OR-2: whether the `[claim: <id>]` marker belongs inline in the README
  or in a side file that names line ranges. Inline is chosen here
  because a binding a reader cannot see while reading the sentence is a
  binding that rots unread, but the cost is visible syntax in a
  published document and that is a legitimate objection.
  A third option was not considered when OR-2 was written: the marker
  lives on the claim's side, and the `description` in
  `.verity/claims.json` names the README anchor it binds. The
  dependency inverts -- the claim knows the prose instead of the prose
  knowing the claim -- and the published document stays clean, which
  answers the objection above without giving up the binding. Its cost
  is the one inline syntax was bought to avoid: the binding stops being
  visible to whoever reads the sentence, so a reader cannot tell a
  bound guarantee from an unbound one, and the author who edits the
  sentence gets no signal that a claim is pointing at it. That cost is
  the whole of the disagreement and the choice is not made here.
- OR-3: CI is the boundary and a local hook is an error detector, in
  `gate_adr_contract.sh`'s own words. D2's gate inherits that: it runs
  in CI, and its local run is a courtesy.

## Not measured

- Whether any host in use actually lacks one of the enumerated
  prerequisites. The defect is that the suite cannot say, not that a
  host is known to be short.
- Whether the twelve claims in `.verity/claims.json` are the right
  twelve to bind README guarantees to. D2 decides that a guarantee
  cites one; it does not decide that the current set suffices, and
  OR-1's sibling question -- which guarantee needs a claim that does
  not exist yet -- is answered at acceptance, one guarantee at a time.

## Provenance

The README sentence was measured false against the suite it describes.
The two structural findings behind it were read off `tests/run_tests.sh`
and `.verity/claims.json` at 818a2e1 and are listed in the Basis. The
D3 contradiction was found by trying to author this document: the
docs-only commit that ADR-006's non-goal requires is the commit
`scripts/gate_adr_contract.sh` rejects.

## Amendment — 2026-08-31: the Quickstart was a guarantee, and two of the twelve claims are red at the Basis

**Appended, not corrected.** Everything above is left as ratified. This
document is Proposed and stays Proposed; nothing here promotes it and no
implementation is written against it.

**D2's scope, as written, did not reach the line that mattered.** The
Context above repairs `## Requirements` and calls it "the README repair
that needs no decision". One section below it, `## Quickstart` read:

    bash tests/run_tests.sh        # expect: ALL TESTS PASSED

That is a guarantee. It is the first line of this repository a stranger
executes, and on the author's machine at 818a2e1 and after the commit
that carries this document, `bash tests/run_tests.sh` exits 2 and prints
`TESTS INCONCLUSIVE [unmeasured register]`. D2 says "every line of
`README.md` that asserts a guarantee", and that was already the right
rule; what this amendment records is that the rule was read narrowly,
as if the guarantees lived in `## Every claim has a fixture` and the
prose around them did not. It reaches every line of the README that
asserts an observable outcome, wherever it sits -- a comment inside a
fenced block included, because a reader runs the block and does not
grade the comment. The Quickstart line is repaired in this commit to
state the measured outcome instead of the intended one.

**The measurement corrects the finding that prompted it.** The exit-2
run was first read as this tree's declared state. It is not, or not
only. Measured on this machine, 2026-08-31, at 1d80fcb, same tree, two
arms differing in one environment variable:

    VERITY_CLI unset      exit 2   183 ok  0 FAIL  8 unattrib  72 PASS
                                   TESTS INCONCLUSIVE [unmeasured register]:
                                   bypass_ft_orphan_lock_blocks_resume
                                   bypass_ft_passed_without_record
                                   bypass_ft_sequence_continues_past_red_gate
    VERITY_CLI resolvable exit 0   187 ok  0 FAIL  5 unattrib  72 PASS
                                   ALL TESTS PASSED

Three rows move between the arms and no fourth. Each prints
`UNMEASURED: verity CLI not resolvable (set VERITY_CLI)`, so the trigger
is an absent prerequisite and not a broken invariant. The defect is that
the three rows do not declare the environment-conditional case the way
the five surviving rows do, so their absence reaches the register as
observed-and-not-declared and the suite refuses to certify. That is
exactly the class D1 exists to name, now with an instance measured on a
tool the repaired `## Requirements` list does not enumerate: `verity`
and `VERITY_CLI` appear nowhere in it, though `CLAUDE.md`'s gate has
required both all along. Repairing that list is not this commit's, and
it is not free: it is D1's mapping work, OR-1. [verified]

**Two of the twelve claims are red at the Basis, on tracked paths.**
`node <verity-cli> verify .verity/claims.json` at 1d80fcb: 10 passed, 2
failed, `OVERALL: FAIL`. The two are `privacy-lint-operator-uid-bare`
and `privacy-lint-model-id`. Both predicates are `git grep` over the
tracked tree, so both are red on tracked content -- `runs/THR-SUBAGENT/**`,
`.verity/evidence/**`, `scripts/tier_map.json` -- and not on scratch. No
gate blocks on this, consistently with `bypass_f9_ci_verity_unwired`
declared RED. [verified]

This is a fact of the Basis and it changes what D2 can bind at
acceptance, so it belongs here and not in the discovery that would
follow acceptance. D2 takes `--verdicts` and answers exit 1 when a cited
id is "present and not green". On day one, then, a guarantee bound to
either of these two ids makes the gate refuse -- not because the
guarantee is false, but because the claim under it is red for reasons
that have nothing to do with the sentence. `privacy-lint-operator-uid-bare`
sharpens this: its own description declares it "expected to stay RED
until the operator records a decision on the exposure it now measures",
and names why the repair is not the claim's to take. It is a
deliberately red claim. A gate that treats red as refusal cannot
distinguish a claim that broke from a claim that was never green by
design, and D2 as written does not draw that line. Ten ids are
bindable at acceptance and two are not. Whether D2 gains a declared-red
class, or those two guarantees stay unbound and say so, is a decision
this amendment records as owed and does not take.

**What this amendment does not do.** No preflight, no README gate, no
change under `scripts/`. FT-36 stays RED and its register line is
untouched. The suite's measured surface is unchanged: this commit
modifies two existing files and adds none, so `gate_adr_contract.sh`
exits 0 without the ADR-surface rule engaging.
