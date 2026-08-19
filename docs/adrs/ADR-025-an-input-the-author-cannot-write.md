---
status: accepted
date: 2026-08-14
accepted: 2026-08-14
decision-makers: operator
---

# ADR-025 — an input the author cannot write

## Context

ADR-024 made the conformance record recomputable: every fact in it is
re-derived from the evidence pair and compared under typed equality, and
anything outside the closed vocabulary refuses. THR-COVER then measured
what recomputability alone buys, and the number is the reason this ADR
exists: **5 of 9** mutation classes killed. The four survivors shared one
shape — a mutant that rewrites evidence AND re-pins the digests
coherently is self-certifying, because every input the verifier read was
writable by the record's author. Internal coherence is exactly what a
mutant can manufacture (classes C6 and C8: stream substitution and
declaration widening, both CONFORMANT).

Thesis: **a conformance record is not verifiable without at least one
input its author cannot write, and the interval-observation ledger is
that input.** THR-ANCHOR built the anchor and re-measured: **10 of 10**
(twelve mutants over ten classes, C6/C8 in both author strategies), zero
kills for the wrong reason, and every THR-COVER survivor died through
exactly the channel the thesis assigned it — the anchored-digest
comparison for the coherent re-pins, non-inclusion for the forged
citations. The doctrine, condensed from THR-ANCHOR's P5 input map (the
full thirteen-row table lives in the THR-ANCHOR run directory and is
normative for this predicate family): a check resists author-side
mutation exactly to the extent that one of its inputs comes from a row
the author cannot write, and the binding must be a recomputation or a
digest comparison, never a narration. The three rows that bind here are
the ledger location (operator-supplied), the append-only chain itself,
and the anchored manifest bytes — the last never read back, only
re-derived from the record's own fields and compared by blob id.

Anchoring a posteriori, however, is a demonstration, not a guarantee: it
proves the mechanism holds when someone runs it, not that any run gets
it. The remaining decisions wire the deposit into the launcher so the
record's existence itself implies the anchor.

## Decision

**D1 — the anchor is the interval-observation ledger.** The chosen
anchor for the conformance record family is lanewright's append-only
observation ledger (`refs/observations/ledger`, compare-and-swap on the
ref): each evidence digest is pinned as a one-line manifest whose
gitBlob is the subject of a full interval-observation entry
(opened == closed == the head at append: an instantaneous read),
appended by the apparatus, never by the worker. Chosen over a second
mechanism (a signature scheme, an external timestamping service, a
pinned side file) because it is ONE mechanism this stack already
ratifies: the entries are adjudicable unchanged by lanewright's
interval/verify.py, the entry format is the ratified contract, and the
ledger sits outside the tree the record's author writes. The record
cites the two entry ids in `predicate.anchor`; the verifier recomputes
the manifest bytes from the record's own run name and digests and
compares blob ids. The accepted cost stands: an anchored record is NOT
verifiable in isolation — no ledger, no verdict.

**D2 — the launcher deposits, so the record cannot exist unanchored.**
When the operator names a ledger repository (`CONFORMANCE_LEDGER_REPO`;
no tracked default names an operator path, ADR-004 D2's posture),
`scripts/launch_worker.sh` itself: writes the resolved declaration —
tools and allowlist as resolved, the permission mode as passed, the
spawn-depth bound from `spec.max_spawn_depth` with 0 (licensing no
delegation) when undeclared — and deposits its digest BEFORE the spawn,
fail-closed: a run whose anchor cannot open does not start. At close it
deposits the stream digest, fail-open on the run and fail-closed on the
record: a close-side deposit failure cannot un-run the run, so it is
loud, writes no anchors.json, and the builder — reached UNCONDITIONALLY
on this path — refuses on its own line and no record exists. The
absence of the record is the signal. The guarantee is about the record,
never the run: with the variable unset the path is inert and the
launcher behaves as before. On this path the child runs in stream-json
(the transcript the facts are recomputed from), and the terminal result
event is lifted back out into the file every downstream reader already
reads; the transcript and the side-car subject are the stream itself
(ADR-019's discipline: the subject is the transcript). Falsifier:
FT-33, `bypass_ft_unanchored_run_yields_record_fixture.sh`, observed
RED against an ornamental variant that fabricates anchors.json on
deposit failure, then GREEN in tree — including the arm that measures
the builder's own refusal surfacing on the real path.

**D3 — the chain position is part of the protocol.** The deposit order
is declaration-then-stream, and a run is anchored exactly once, so the
verifier refuses (NOT-RECOMPUTABLE, exit 2) a record whose declaration
entry does not precede its stream entry in the chain, and a record
whose run appears in the chain beyond its two cited entries. Refusal,
never DIVERGENT: an anchor pair whose chain position contradicts the
protocol says nothing about the run — an inverted pair means both
digests were known at first deposit, and a re-anchored run is
ambiguous. Falsifier: FT-32,
`bypass_ft_anchor_order_inverted_fixture.sh`, observed RED against the
position-blind verifier, then GREEN.

## Declared limits

**L1 — the chain orders; it does not date.** That the declaration entry
precedes the stream entry is verifiable from the ledger. That the
declaration was deposited BEFORE THE EXECUTION BEGAN is not: it is a
property of the apparatus (the deposit sits before the spawn in the
launcher), and the ledger alone cannot show it. What would make it
verifiable — named, not implemented: feed the declaration entry id into
the child's invocation so the stream bytes themselves carry it; a
stream that contains the id of a chain entry cannot have closed before
that entry existed, turning the apparatus property into a recomputable
fact. Until then, a reader trusts the launcher's code for the
before-spawn half, and the record declares nothing stronger.

**L2 — the 10/10 holds against the record's author, not against the
tree's.** Every killed mutant wrote only the record and its evidence.
An adversary who writes the TREE — the verifier's own bytes, the rule
files resolved beside it — or the ledger repository is outside this
measure, exactly as the P5 input map's caveat rows state (co-location
is not enforcement). The bindings for that adversary are
operator/executor attribution (vault/ADR-055, commit signing — parked)
and an enforced-location pin for the verifier family; both stay parked
and neither is claimed here.

## Consequences

- The launcher grows one conditional path and two per-run ledger
  entries; everything it wrote before, it writes unchanged. Existing
  invocations without the variable are byte-path identical.
- Conformance-mode runs produce their transcript as stream-json; the
  single result object remains available to every existing reader as
  the lifted terminal event.
- Verification now requires the ledger (`--ledger-repo`) and walks the
  chain once per verification for the count check — linear in ledger
  length, accepted at current sizes.
- The three THR-CONFORMANCE records and the delivery record verify
  CONFORMANT through the new checks against the real ledger.

## Open records

- OR-1: L1's stream-echo of the declaration entry id — the one
  mechanism that would upgrade the order limit into a recomputable
  fact. Unimplemented by decision here.
- OR-2: whether the production ledger stays the lanewright observation
  ledger or gets a dedicated repository — the operator's call; the
  wiring takes a directory and does not care.
- OR-3: register rows for FT-32/FT-33 land with this ADR's sequence
  (they stack on THR-ANCHOR's pending register patch).

## Ratification

The measure precedes the Decision: 5/9 (THR-COVER) → 10/10
(THR-ANCHOR P4, preregistered, every kill through the predicted
channel), the P5 input map reconciling class by class. The wiring's own
two falsifiers were each observed failing and in the declared state
(THR-WIRE run directory: seen-failing and green captures, the
ornamental variant's diff beside them). The cycle closed end to end
once with nobody anchoring by hand: a live four-file run through the
wired launcher, its record built by the launcher and verified
CONFORMANT against the lanewright ledger, the chain grown by exactly
its two entries in order (THR-WIRE `real-run/DELIVERY.md`).
