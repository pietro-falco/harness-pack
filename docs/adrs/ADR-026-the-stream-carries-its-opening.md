---
status: accepted
date: 2026-08-14
accepted: 2026-08-14
decision-makers: operator
---

# ADR-026 — the stream carries its opening

## Context

ADR-025 D3 made the deposit ORDER verifiable: the declaration entry
precedes the stream entry in the chain, or the record refuses. Its L1
declared what order cannot say: that the declaration was deposited
BEFORE THE EXECUTION BEGAN was a property of the apparatus — the
deposit sits before the spawn in the launcher — and a reader had to
trust the launcher's code for it. OR-1 named the closing mechanism and
left it unimplemented by decision.

The gap is real and was observed before it was closed: a record built
by anchoring a PRE-EXISTING stream after the fact — declaration
marked, both digests deposited in the protocol order, everything
internally coherent — verified CONFORMANT under the ADR-025 verifier
(FT-34, seen-failing capture in the THR-PAYLOAD run directory). The
chain ordered the deposits; nothing bound the stream's bytes to the
run's opening.

## Decision

**D1 — the declaration declares the protocol it was deposited under.**
On the conformance path the launcher writes `streamecho=v1` into the
resolved declaration header BEFORE hashing and depositing it. The
marker therefore sits under the anchored declaration digest: an author
cannot add it to claim a binding that never happened, and cannot strip
it to escape the check, without diverging from an input they cannot
write. Records whose anchored declarations carry no marker predate
this protocol and verify as before — their exemption is itself
anchored, not asserted.

**D2 — the apparatus writes the opening into the stream.** After the
declaration entry id exists and before the child's first byte, the
launcher writes one line — the first line of the stream file —
carrying the run name and the declaration entry id. The child's
stream-json is appended after it, and the stream digest deposited at
close covers the whole file. Chosen over OR-1's literal phrasing (the
id entering the child's prompt and reappearing in the stream): the
stream-json init event echoes no invocation data (measured on the
THR-WIRE delivery stream), so a prompt-borne id reaches the stream
only through model compliance — narration, which this predicate
family refuses as a binding. The apparatus-written line is
deterministic bytes under the same digest: strictly cheaper, and
stronger as a binding because narration is refused — but what either
mechanism binds is the stream's composition, never the child's
execution (L3).

**D3 — the verifier reads the opening from the bytes.** When the
anchored declaration carries `streamecho=v1`, the verifier requires
the stream evidence's first line to name exactly the cited
declaration entry id and the record's run, and refuses
(NOT-RECOMPUTABLE, exit 2) otherwise. Refusal, never DIVERGENT: a
stream that cannot be bound to the run's opening says nothing about
the run's conduct — the anchor cannot mean what a reader would take
it to mean (the FT-32 posture). Falsifier: FT-34,
`bypass_ft_stream_echo_absent_fixture.sh`, observed RED against the
ADR-025 verifier, then GREEN in tree — two controls (pre-echo record;
echoed record) and two refusal arms (no echo; wrong id).

## Declared limits

**L1 — chain-relative time, not wall-clock.** A stream whose bytes
carry the declaration entry id was finalized no earlier than the
chain state that entry extends: the id is a function of the
predecessor head and the declaration manifest, so bytes that name it
postdate the chain position it was created on. That is the whole
claim. The anchor entries are deterministic by design (fixed identity
and dates), so an adversary who can predict the deposit-time head can
precompute the id before depositing; what they cannot do is make a
stream anchored by the apparatus carry an id the apparatus never
deposited, nor rewind the chain the id extends. Wall-clock dating
would need an input outside this stack (a timestamping authority) and
is not claimed.

**L2 — the binding assumes the apparatus writes the ledger, and only
the apparatus.** A record author who can run the anchor tool against
the operator's ledger is outside this measure, exactly as ADR-025 L2
places the tree-writing adversary outside its own. Unchanged, not
weakened: the ledger location stays operator-supplied and the deposit
stays apparatus-side.

**L3 — composition, not execution (THR-RESIDUE, measured).** What D3
verifies is that the stream FILE was composed — opening line first,
digest at close — no earlier than the chain state the declaration
entry extends. It does not verify that the CHILD's execution began
after the deposit: an apparatus with its operation order permuted
(child stream first; declaration composed and deposited; opening line
prepended; stream deposited) emits a record bitwise-identical to the
protocol apparatus's — same evidence pair, same anchors, same entry
ids, same ledger head (FT-35,
`bypass_ft_opening_prepended_post_hoc_fixture.sh`; captures in the
THR-RESIDUE run directory). The verifier's input space does not
contain the distinction, so no check over that space can close it —
FT-34's own green control is built in the mutant's order — and a
same-machine mechanism that would add the missing input is itself
apparatus the reader trusts. The residue is permanent by measure, not
open by decision: FT-35 stands GREEN while the residue is as declared
here, and goes RED the day any mechanism claims more, forcing a
re-declaration before the green can be trusted again.

## Consequences

- The launcher grows one header token and one first-line write;
  everything else on the conformance path is byte-identical, and the
  path without a ledger is untouched.
- The builder is untouched: the opening line carries no message
  content and no result type, so evidence analysis, completeness and
  the lifted terminal event all read through it unchanged. The delta
  is launcher and verifier only.
- Pre-echo records (the three THR-CONFORMANCE records, the THR-WIRE
  delivery) verify unchanged: no marker in their anchored
  declarations, no echo required.
- ADR-025 L1 is narrowed, not closed: a marked record's bytes show
  the stream was COMPOSED no earlier than the declaration entry — the
  recomputable half. Its "a reader trusts the launcher's code for the
  before-spawn half" sentence still applies to the EXECUTION: that the
  child ran after the deposit stays a property of the apparatus,
  measured permanent by FT-35 (L3).

## Open records

- OR-1: wall-clock dating (an input outside the stack) — not taken.
- OR-2 (inherited from ADR-025): the production ledger's home stays
  the operator's call; this mechanism does not care.

## Ratification

FT-34 observed RED against the ADR-025 verifier (blob f624699c),
then GREEN with D1–D3 in tree. Regression: the four in-tree records
CONFORMANT against the real ledger through the new verifier; the
FT-20..33 fleet green. The first marked record is the THR-PAYLOAD
delivery run, whose stream's first line carries its declaration entry
id, live, with nobody writing it by hand.

THR-RESIDUE (20260814T164414Z) then measured D3's mutation score
against the operation-order permutation: the mutant survives by
byte-identity (FT-35, preregistered, both predictions confirmed —
control-true and arm-mutant CONFORMANT, evidence pair and record and
ledger head bitwise-identical across the two orders), and this
amendment narrows the ADR's claim to what that measure sustains:
composition bound to the chain, execution left to the apparatus (L3).
