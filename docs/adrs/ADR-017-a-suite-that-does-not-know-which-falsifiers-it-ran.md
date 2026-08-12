---
type: adr
status: proposed
title: "Twelve tracked bypass falsifiers, zero invoked by the suite: a register of declared states, and what ALL TESTS PASSED is made to assert"
id: ADR-017
date: 2026-08-12
related-adrs: [harness-pack/ADR-008, harness-pack/ADR-011, harness-pack/ADR-013]
---

# ADR-017 — A Suite That Does Not Know Which Falsifiers It Ran

## Status

Proposed

## Numbering note

017 is taken by sweep, not by increment. 012, 014, 015 and 016 are free by filename
maximum and are reserved by intent for the remaining rows of the six-gap arc that
ADR-011 and ADR-013 opened. Reserving by intent is not reserving in fact, and this
document does not take one of them: it is not a gap row. A sweep for the token `ADR-017`
returns zero hits in this repository.

## Basis

- `harness-pack` `main` at `9d64e33`. Every line number in this document is read against
  that basis and against `tests/run_tests.sh` as it stands there — 862 lines, before the
  register block this document decides. The block adds 103 lines above the shellcheck
  gate, so every citation below moves by that amount once the implementation lands. They
  are pinned here rather than maintained.
- Twelve falsifiers tracked, `git ls-files -- 'tests/bypass_*' | wc -l` = 12, all twelve
  reachable from `HEAD`.
- `grep -c 'tests/bypass_' tests/run_tests.sh` = 0.

## Context

Twelve bypass falsifiers are tracked in this repo. Zero are invoked by
`tests/run_tests.sh`. They are linted on every run — `tests/*.sh` is inside the
shellcheck gate at :840 — and executed by nothing. They are inside the perimeter
of the tooling and outside the perimeter of the meaning.

On 2026-08-11 and 2026-08-12, observed on two consecutive turns:
`tests/run_tests.sh` exited 0 and printed ALL TESTS PASSED while
`tests/bypass_fb_budget_tokens_unbounded_fixture.sh` sat in the tree at exit 2,
FIXTURE BROKEN. Nothing in the suite was in a position to notice, because
nothing in the suite was looking.

The runner already carries the vocabulary this decision needs. It distinguishes
`fail` from `unmeasured` at :4 and :9, and the tail at :853-862 spends three
verdicts: exit 1 for a violation, exit 2 for an invariant that went unmeasured,
exit 0 for ALL TESTS PASSED. What it does not carry is an inventory. The
declared state of a falsifier is encoded today in the presence or absence of an
`--expect-red` flag on its call site — :685 and :707 both had one removed when
those rows turned green — which is a convention, honoured line by line, that no
single artifact enumerates and no gate reads.

An inventory that no artifact holds cannot be checked for completeness. That is
the defect: not that twelve rows are unwired, but that nothing in the repo is
in a position to say how many rows there are supposed to be.

## Decision

### D1 — ALL TESTS PASSED asserts the register

The string ALL TESTS PASSED, and the exit 0 beside it, now additionally assert
that every tracked bypass falsifier was executed and observed in its declared
state. This is not a check added beside the suite. It is a change to what the
suite's own verdict means, and it is why this decision is an ADR rather than a
commit.

### D2 — The register is data, one literal line per falsifier

The register lives in `tests/run_tests.sh` as one line per falsifier, carrying
the path and a declared state drawn from `{RED, GREEN}`, driven by a loop. One
line per falsifier and not a compacted array: a reader counting rows and a grep
counting occurrences must agree, and the tracker's `WIR-5` measures the second.

### D3 — Divergence fails in both directions

A falsifier declared RED and observed GREEN fails the suite exactly as a
falsifier declared GREEN and observed RED does. A control that started binding
without anyone repairing it is a finding about the repo, not a repair to be
absorbed. The response to it is to investigate and then amend the declared
state in a commit that says what changed. Editing the register to match an
observation, in either direction, without that commit, is the failure mode this
decision exists to make expensive.

### D4 — Exit 2 is a failure unless the row declares otherwise, and is never a pass

A bypass falsifier's exit 2 routes to `fail` by default. It means the fixture's own
control could not confirm what it is measuring — `F-b`'s header states this plainly, and
describes exiting 2 and continuing to exit 2 until realigned by hand. That is
deterministic, reproducible, and cleared by a human edit rather than by a re-run.

One exception, declared per row in a third register column and admissible on one ground
only: the fixture's own header defines its exit 2 as an ATTRIBUTION failure — the row
could not reach its question — rather than a broken control. `F8` is the only such row at
this basis, and it is explicit: exit 2 there means the launcher refused for a reason not
attributable to the tamper detector, which its header calls "neither a pass nor a fail,
and it must not be spelled as either". Writing that as `fail` would accuse this repo of a
defect the row never observed. Such a row routes to `unmeasured`.

The two readings are not a choice the implementer makes at the call site. They are a
property of the fixture, declared beside it, and the default is the strict one — a
falsifier that wants the lenient reading has to have said so in its own header first.

**Under neither reading does exit 2 print ALL TESTS PASSED.** `fail` yields exit 1;
`unmeasured` yields exit 2 and TESTS INCONCLUSIVE. The distinction decides what the suite
ACCUSES, never whether it certifies. On 2026-08-11 a broken falsifier sat in the tree and
the suite certified. Both branches of this decision close that, and the column decides
only which of the two true things gets said.

### D5 — Completeness is membership, not cardinality

The set of paths in the register must equal the set returned by
`git ls-files -- 'tests/bypass_*'`, compared as sets and accused in both directions: a
tracked falsifier missing from the register, and a registered path that is not tracked.

Cardinality alone is not this check. A register carrying one row twice and one row not at
all has the right count and the wrong contents, and would pass a count. The failure mode
D5 exists to close is a falsifier nobody runs, and a duplicate row hides exactly one of
those while looking correct in every summary.

D5 is the clause that makes the state this repo was actually in — twelve tracked, zero
wired, verdict green — unrepresentable.

### D6 — The declared state is read from the fixture, never from a run

Each declared state is drawn from the falsifier's own header: what that fixture
states it demonstrates. It is not seeded from a first execution. A register
whose values are produced by the procedure it gates decides nothing.

Where a fixture's header and its observed state disagree at the moment this
register is first written, that disagreement is recorded as a finding and the
declared state stays as the header states it. The suite goes red. That red is
the first thing this decision was built to surface.

### D7 — `fe` is in the tree the register is written against

`tests/bypass_fe_secret_in_context_fixture.sh` was staged and not committed when this
decision was drafted: the tree carried eleven, the index twelve, and a `git reset` would
have truncated the inventory to eleven while the register named twelve. It landed in
`9d64e33`, before this document was committed, so the condition is met by the tree rather
than by this clause.

The clause is kept rather than deleted because D5 is what now holds it: a register naming
twelve paths against a tree tracking eleven fails on membership, in the
registered-not-tracked direction. What was a sequencing instruction is now a checked
invariant, which is the better place for it. See Provenance.

## Falsifier register

Each row must be observed red before this ADR moves to Accepted.

| id | claim | falsifier | evidence |
|---|---|---|---|
| `W-1` | a tracked falsifier absent from the register fails the suite (D5) | stage a new `tests/bypass_zz_*` without registering it; run the suite | `.verity/evidence/2026-08-12-wiring-register/w1-first-red.txt` |
| `W-2a` | declared GREEN, observed RED fails (D3) | flip one register row from RED to GREEN; run | `.../w2a-first-red.txt` |
| `W-2b` | declared RED, observed GREEN fails (D3) | flip one register row from GREEN to RED; run | `.../w2b-first-red.txt` |
| `W-3` | exit 2 fails rather than going unmeasured (D4) | force one falsifier to exit 2; run; the suite must print TESTS FAILED and exit 1, not TESTS INCONCLUSIVE and exit 2 | `.../w3-first-red.txt` |
| `W-4` | a row declaring `UNMEASURED-2` routes its exit 2 to `unmeasured`, not to `fail` (D4) | force `bypass_f8` to exit 2; run; the suite must print TESTS INCONCLUSIVE and exit 2, not TESTS FAILED | `.../w4-first-red.txt` |

`W-3` and `W-4` are one observation split in two, and neither is worth anything alone.
The same exit code reaches the same loop and leaves by two different doors, and what
decides which door is the row's own declaration. A `W-3` observed without `W-4` would be
consistent with a register that routes every 2 to `fail` and reads no column; a `W-4`
without `W-3` with one that routes every 2 to `unmeasured`. `W-3` also reconstructs the
2026-08-11 observation directly. If neither can be made to fail, D4 is prose.

## Consequences

The suite gets slower by the cost of twelve fixture runs. That cost buys the
only thing that distinguishes this suite from one that prints the same string
without looking.

A falsifier that becomes green on its own now stops the build. This will be
mistaken for a regression by whoever meets it first. D3 exists so that the
mistake is expensive enough to be caught in review.

## Ownership note

`docs/adrs/` is owned by `THR-ADR`; `tests/run_tests.sh` and `tests/bypass_*`
by `THR-WIRING`. This ADR is authored at the request of `THR-WIRING` and
committed as a `THR-ADR` action. The Proposed → Accepted transition is the
second commit, again `THR-ADR`, carrying the evidence that the five rows above
were observed red. The implementation commit is the third and touches only
`THR-WIRING` paths.

## Provenance

The register block this document decides was authored, wired and measured in the working
tree BEFORE this document existed, and the four falsifier rows were observed red against
it. Under ADR-006's Non-goals no code is written against a Proposed ADR, and that rule
binds this document to itself.

The precedent is ADR-013, whose D2 and D3 both describe repairs already in `HEAD` when it
was written, and ADR-008's evidence discipline, which requires the basis of a measurement
to be pinned rather than implied. What is recorded here is the same shape: the instrument
was built and fired before the decision was accepted, no commit carried it, and the
implementation lands only after the flip. The falsifier rows cannot be observed any other
way — a register's falsifiers are unobservable until the register exists — and stating
that is preferable to a document that implies four reds were taken against a tree that
never held the code.

`fe`'s arrival in `9d64e33` is covered by the same note: D7 was written against an index
and is read against a tree.

## Not measured

The register is a second place where a fact about a falsifier is written, the first being
the falsifier's header. D6 fixes the direction of that dependency and D5 checks that no
row is missing, but **nothing checks that a copied declared state still matches the header
it was copied from.** The first exercise of this register found exactly that drift in
`bypass_fc`, by running the fixture rather than by comparing the two declarations, and a
row whose header changes without its register line changing would go unnoticed until the
fixture's behaviour moved too. Named here, not closed here.
