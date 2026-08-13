---
type: adr
status: accepted
title: "The subject is the transcript: a side-car in-toto Statement"
id: ADR-019
date: 2026-08-13
related-adrs: [harness-pack/ADR-004, harness-pack/ADR-005, harness-pack/ADR-006, harness-pack/ADR-008, harness-pack/ADR-010, harness-pack/ADR-018, harnesswright/ADR-0008, vault/ADR-051, vault/ADR-080]
---

# ADR-019 — The Subject Is the Transcript: a Side-Car in-toto Statement

## Status

Accepted 2026-08-13 by direct operator ratification, on the text committed at
`076b219bc446d478adf712dacc9836491623f8ce`, git blob
`13064f802801addcb40b203e2b76608ebe1612db`. Originally proposed 2026-08-13 as a
docs-only commit, then amended in place while still Proposed to add `D7`, under
`harness-pack/ADR-006:56` — "No code is written against this ADR while it is
Proposed" — which `harness-pack/ADR-009:23` reads as general. Per the two-commit
lifecycle, acceptance requires operator review and a separate ratification
commit. This is that commit. [verified]

**The ratification commit is the implementing commit**, on the precedent
`harness-pack/ADR-018` set one document ago. Four things ship, and they are the
whole of what this decision costs:

- **The digest line.** `scripts/launch_worker.sh` computes the sha256 of `$OUT`'s
  raw bytes between `CC_EXIT=$?` and the receipt writer, exactly where D1 places
  it. This was OR-6 and it is one `if` and one `python3 -c`.
- **The emitter.** `scripts/write_statement.py`, a sibling of
  `scripts/write_receipt.py` on the same I/O contract, composing the Statement
  from the receipt and the digest and serializing it in `harness-pack/ADR-018`
  D1's form.
- **The wiring.** The launcher invokes the emitter after the receipt writer,
  **fail-open at the call site**: a refusal inside the emitter writes no file and
  cannot move the run's exit code or the gate's verdict. The run is the thing
  attested; the attestation is not the run.
- **The manifest key.** `templates/manifest.example.json` gains `verifier_id`,
  carrying a **placeholder** in the `*_CLASS_MODEL` convention and never a real
  domain, per `harness-pack/ADR-004`. This closes OR-2.

Six falsifiers land with it, registered in `tests/run_tests.sh` under `ADR-017`
D2, each carrying the state its own header declares (`ADR-017` D6):

| Falsifier | Decision | Declared | File |
|---|---|---|---|
| `bypass_att_subject_missing` | D1 | GREEN | `tests/bypass_att_subject_missing_fixture.sh` |
| `bypass_att_dirty_tree_subject` | D2 | GREEN | `tests/bypass_att_dirty_tree_subject_fixture.sh` |
| `bypass_att_result_desync` | D4 | GREEN | `tests/bypass_att_result_desync_fixture.sh` |
| `bypass_att_chain_survives_sidecar` | D5 | GREEN | `tests/bypass_att_chain_survives_sidecar_fixture.sh` |
| `bypass_att_no_subject_no_statement` | D7 | GREEN | `tests/bypass_att_no_subject_no_statement_fixture.sh` |
| `bypass_att_canon_reorder` | `harness-pack/ADR-018` D1 | GREEN | `tests/bypass_att_canon_reorder_fixture.sh` |

The sixth row is not this document's falsifier. It belongs to
`harness-pack/ADR-018` D1 and lands here because that ADR's **OR-6 named this
exact moment** as its birth: "Its birth moment is the first side-car Statement
emitted — the artifact `harness-pack/ADR-019` D5 places beside the receipt." That
artifact now exists, so the fixture has a subject. The closure is recorded in
`harness-pack/ADR-018` itself as an appended amendment, which is how a post-
acceptance closure is recorded in this repository — the form
`harness-pack/ADR-008` and `harness-pack/ADR-010` already use, and `vault/ADR-080`
states as "Appended, not edited." [verified]

**All six are declared GREEN, and that is stated rather than left to look like
the register going soft.** The implementation lands in the same arc as the
falsifiers, so their subject exists on arrival — the same situation
`bypass_att_two_digest_shapes` was registered GREEN in. What keeps them from
being vacuous is that every one carries a control that makes its own assertion
**move**: a fabricated artifact the row must refuse, beside the real one it must
accept. Where a RED had already been measured it is cited (D1); where a RED was a
prediction it was **produced and observed in this commit** (D4, D7).

**The ratified text differs from the proposed text on six points, named here
rather than left to a diff. No Decision text changes: D1 through D7 stand word
for word as proposed.**

1. This Status block, which records ratification in place of the
   nothing-ships-yet paragraph the proposing commit carried. The paragraph
   recording the in-place `D7` amendment is kept verbatim below, because it is
   part of the record and not part of the claim.
2. The Verification section's D4 and D7 rows, whose "Not yet observed" was true
   when written and stopped being true in this commit. Each original sentence is
   kept and the observation appended beneath it, so the record still shows what
   was predicted before it was seen — the form `harness-pack/ADR-018` used for
   its own D4 row.
3. The Verification section gains a seventh row, for `bypass_att_canon_reorder`,
   which is `harness-pack/ADR-018` D1's falsifier and is named here because this
   commit is where it becomes writable.
4. The Non-goals bullet reading "**It writes no code**, no fixture, and no
   schema" — true of the proposing commit, not true of this one. No schema file
   ships even so.
5. The Open requirements: OR-2, OR-3 and OR-6 are closed in place, each with the
   closure recorded beneath the original text. OR-1 stays open and its written
   branch is named. OR-4 and OR-5 stay open with their birth moment recorded as
   having arrived.
6. The Assumption ledger's `D7`-reachability row, whose observation was taken in
   this commit. The previous reading is preserved and the observation appended
   under it.

**Two facts observed at ratification, recorded here rather than discovered
later.**

- **`D7`'s branch is reachable, and NOT by the route a reader would assume.**
  `bypass_att_no_subject_no_statement` drove the launcher in tree twice. With the
  transcript genuinely **unreadable** at digest time, the run wrote its receipt
  carrying `subtype: error_no_output` and **zero** `.intoto.json` files: both
  halves of D7's assertion, observed. With an executor that simply **wrote
  nothing**, the receipt also read `error_no_output` — and a Statement **was**
  emitted, over a zero-byte transcript, subject digest
  `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`. The two
  states are not one state. `$OUT` is created by the launcher's own redirection
  `"${CMD[@]}" < "$SPEC" > "$OUT"` **before the child runs**, so an empty or
  malformed transcript is readable and has a digest like any other byte string.
  **`error_no_output` in a receipt does not imply D7's branch was taken**, and
  attesting to a zero-byte transcript is D1 applied literally with nothing
  fabricated. The Assumption ledger row that carried this as `[assumed]` is
  updated below rather than deleted. [verified]
- **The side-car is content-addressed, and the framing is part of the identity.**
  The emitter writes `harness-pack/ADR-018` D1's form with **no trailing
  newline**, so `sha256(file bytes)` equals the digest of the canonical string
  and no second convention about framing is needed. `bypass_att_canon_reorder`
  measured a 516-byte artifact whose reordered re-serialization reproduces its
  content id exactly, while the same object in the receipt's own form
  (`indent=1`, unsorted) produces a different one at 607 bytes — `DETERMINISM.md`'s
  measured formatting delta, reproduced on the new artifact. That is OR-3
  answered **yes**. [verified]

Amended in place while still Proposed (2026-08-13), on the text committed at
`240f8cf9b4602e205c30f313987282cea1eb62bf`, git blob
`eb39ec52d69204f0b14db1b4390ce939c431985c`. The amendment **adds `D7` and
changes no existing Decision text**: D1 through D6 stand word for word as they
were proposed. `D7` closes the one gap this document's own Assumption ledger had
already named — an `error_no_output` run, "where the Statement has no subject to
name, and D1 gives no rule for that case" — and the ledger row that named it is
rewritten to record that the case is now decided rather than assumed. The
Verification section gains `D7`'s falsifier by name; no fixture ships here
either, for the same reason the paragraph above gives. Proposed ADRs are
amendable in place; immutability attaches at acceptance. The form and the rule
are `vault/ADR-080`'s, whose own Status block records the same act performed on
itself while it was Proposed. [verified]

## Numbering note

019 is taken by sweep, not by increment, and it is the successor of the number
`harness-pack/ADR-018` takes. 012, 014, 015 and 016 remain reserved by intent
for the six-gap arc, per `ADR-017`'s numbering note; this document is not a gap
row. `grep -rn 'ADR-019'` over this repository excluding `.git` returned **zero
hits** at this basis, and `git grep -n 'HP-ADR-019\|harness-pack/ADR-019'` over
the vault at its `HEAD` returned **zero hits**. [verified]

**This document depends on `harness-pack/ADR-018` and is sequenced after it.**
`N1-SUBJECT.md:170-174` states why: "ADR-A cannot pick a subject without picking
an algorithm name, which is ADR-B's decision. **The two ADRs are coupled and
must be sequenced.**" Every digest spelling below is ADR-018 D2's. [verified]

## Basis

Every line number in this document is read against the bases below and is
**pinned here rather than maintained**.

**Repository heads.**

| Repo | Branch | HEAD |
|---|---|---|
| `harness-pack` | `main` | `3c2680daf6e9d0243fdb804c391fbb8b6f2659b1` |
| `verity` | `main` | `4dc016b354f3a6eb953590167b46bc29eacf3fcb` |
| `harnesswright` | `main` | `edb12a499615bf12aa80e5db1c67a268cb247114` |

Citations into `harness-pack` are read against the committed blob
(`git show HEAD:<path>`), never the working tree, which is dirty at this basis —
a fact D2 turns on. Citations into `verity` and `harnesswright` are read against
the pinned commits above.

**Measurement documents**, carried as a split. Their manifest — path, sha256 and
byte length for each of the thirty-two files — is at
`.verity/evidence/2026-08-13-attestation-s1/README.md` in `harness-pack`; their
bytes are held in the operator's private governance vault. Cited by digest, not
re-derived, and the digest is the same in either location because the bytes are.

**Produced under a temporary directory, made durable in `harness-pack`, and then
moved into the private vault by the operator**, because the provenance of
evidence is itself evidence and the last link alone is not the chain. The bytes
were written under `${TMPDIR}/attest-s1/`, with one specification under
`${TMPDIR}/attest-s2/`, on a platform that sweeps that location; they were copied
unmodified, every digest in the two tables below was recomputed against the copy
and matched the value cited here, and all thirty-two files were re-verified again
at their new location on both sha256 and byte length. Each move changed the path
and nothing else. `harness-pack/ADR-018`'s Basis carries the same repointing,
both re-verification counts, the decision to track the manifest rather than the
bytes and the privacy-lint measurement behind it, and the measured fact that the
corpus's new location is human-write exclusive by the vault's own policy rather
than by configuration. [verified]

| Document | sha256 |
|---|---|
| `INDEX.md` | `1c39dd3b0ff5ee081b9e3cfe257b016ced75fa63fb91f55d61745dccffc7cf10` |
| `GAP.md` | `0dc4c148cfd35e6a83757d1b5fff0ca63c2ec2d6bd311d4d2664c5d52ccd090f` |
| `DETERMINISM.md` | `616cb3ceb5c916a4540607b971c49cfbff1d54e12f077a3047e5dfbcd20ef539` |
| `CRYPTO-READINESS.md` | `e3abdf886361e9b438e5067fd25df935c931c21a7aefe11c95f5e803a3c694a6` |
| `CORPUS.md` | `49ab237db64786f3cd92e343ab18ab320226fd50d33f9a93e6a8553997302654` |
| `N1-SUBJECT.md` | `ee628ca4ea17e58d82eff7c012a974934e1e13d3b622a65701addc4ac7a7cccc` |
| `N2-CHAIN.md` | `158095f6424589cbea12b3b1217f9667fdf825fc9f1f27a8dd6dcd16423933ea` |
| `N3-PUBLISH.md` | `e7d7a33e4b307c1c99fabad1db22e83aae06cf5692bbd6fef79e795d9645e66e` |
| `N4-VERITY.md` | `0030cbaadfed71a5f05eabe39c6a40a12a9922205b35584265e5216ea7cbfeaa` |

**External specifications**, pinned by digest. D4 records at length why a URI is
not a citation.

| Spec | Type URI as read | sha256 | bytes |
|---|---|---|---|
| Simple Verification Result | `https://in-toto.io/attestation/svr/v0.2` | `60d47f833f7998926aa991d1aa6ab9ef9a2a916771a99232b624ea0c45c9da1a` | 7540 |
| Link | `https://in-toto.io/attestation/link/v0.3` | `23703e071424e2468382a90355493cdc2c0defe8b97250a93db2be24c14cfbb0` | — |
| Statement v1 | `https://in-toto.io/Statement/v1` | `cbe684a18b812b8b613d9202eb43b2ea24477f91a2ad6ca5be935185a455ebea` | — |
| ResourceDescriptor | — | `bee71bedd6a957771233cbbe6494144157b865992e53cc91d607a8e02a34c58a` | — |
| DigestSet | — | `0b1889fdea7f6d623b41555632aedf04ee4398cf02a32002060608c75ebb038e` | 8873 |

**Assertion labels.** `[verified]` — established by an artifact cited here and
re-readable by a third party. `[inferred]` — follows from cited artifacts by an
argument stated at the point of use. `[assumed]` — neither; carried in the
Assumption ledger with its falsifier. An unlabelled assertion is a defect in
this document. They map onto `harness-pack/ADR-008` D6's tiers: `[verified]` is
tier A and citable as a finding; `[inferred]` and `[assumed]` are tier B and
citable **only** as open requirements. [verified]

## Context

`GAP.md` projected the existing receipt into three candidate attestation shapes
and measured the same failure in all three: `subject[0].digest` is **ASSENTE**
(`GAP.md:42`, `:62`, `:112`, `:161`), and the summary table at `:207` reads
`subject[0].digest set | FAIL | FAIL | FAIL`. in-toto Statement v1 is not
permissive here — `statement.md:37`, verbatim: "Each element MUST have `digest`
set." [verified]

`GAP.md:214` names the shape of the defect: "What is missing is not volume of
data". The receipt is rich. It has no digest of anything the run produced.

That is a subject problem, and `N1-SUBJECT.md` was written to answer it by
enumerating every value in the launcher's hand at receipt-writing time. The
answer is narrow: one candidate, and it costs one line that does not exist.

## Decision

### D1 — The subject is the transcript

`subject[0]` is the file `$OUT`, defined at `scripts/launch_worker.sh:222` as
`"$RECEIPTS_DIR/$RUN_ID.cc.json"`. It is identified by the **sha256 of its raw
bytes**, computed **after the child closes** — `"${CMD[@]}" < "$SPEC" > "$OUT"`
at `:370`, `CC_EXIT=$?` at `:371` — and **before the writer is invoked** at
`:409`, `python3 "$WRITER" "$OUT" "$RECEIPT"`. [verified]

`subject[0].name` is the **basename**, never an absolute path. A path is
environment, not identity, and the specification says so on both halves:
`statement.md:54` — "IMPORTANT: Subject artifacts are matched purely by digest"
— and `resource_descriptor.md:37-39`, which asks that "`name` SHOULD be stable,
**such as a filename**, to allow consumers to reliably use the `name` as part of
their policy". A basename is the spec's own example of a stable name; an
absolute path is the least stable string available, and it is additionally the
de-literalization `harness-pack/ADR-004` already settled for this repository.
[verified]

The same section carries D1's other half: `resource_descriptor.md:51-52`, "the
producer SHOULD set this field to denote an **immutable** artifact or resource".
That is the property the rest of this decision is chosen for. [verified]

**Why this one.** `N1-SUBJECT.md` enumerated the launcher's values and `$OUT` is
the only one that is simultaneously (i) produced by the run, (ii) immutable once
closed, and (iii) already complete before the receipt exists. `N1-SUBJECT.md:135`
calls it "**The closest miss.** A write-once artifact the run produced, whose
file is complete and closed 39 lines before the writer runs at `:409`. But **no
digest of it is ever computed** — the launcher holds the *path*, never the hash.
One `shasum` away, and that one line does not exist today." [verified]

The whole cost of this decision is that one `shasum` line.

**The publish asymmetry is deliberate and is stated here rather than
discovered later.** `docs/OPERATOR-GUIDE.md:134` says: "receipts are designed to
be safe to publish, transcripts are not." Attesting to the transcript's *digest*
is therefore safe while shipping the transcript is not — the digest names the
artifact without disclosing it, which is the property a content-addressed
identifier exists to provide. `N1-SUBJECT.md:166-169` records the same reading.
Nothing in this ADR authorises publishing a transcript. [verified]

### D2 — HEAD is not the subject

`HALT_ROOT` is available from `scripts/launch_worker.sh:52`,
`git rev-parse --show-toplevel` answers, and `HEAD` is therefore derivable at
receipt time. It is still not the subject, and the reason is not cost.

`measure_criteria` (`:271-315`) measures the **working tree**. `:275`, verbatim:

```
  vout="$(cd "$HALT_ROOT" && node "$VERITY_CLI" verify --json 2>"$verity_err")"
```

That runs against the tree as it stands, not against any commit; no `git`
invocation appears anywhere in the function. It is called **twice** — `:329` for
the t0 baseline and `:384` for t1 — and `scripts/write_receipt.py:89` writes
`"phase": "working-tree-advisory"` unconditionally, with the comment at `:57`
stating it is "always working-tree-advisory in a launcher-written receipt".
[verified]

So binding `subject[0]` to `HEAD` would produce a Statement that **names a
commit and attests to a tree that is not that commit**. `N1-SUBJECT.md:160-163`
puts it exactly: "the working tree is what the gate actually measured and has no
digest at all; `HEAD` has a digest and is not what the gate measured. Choosing
`HEAD` buys a well-formed Statement that is untrue on a dirty tree, and every
measured run so far was on a dirty tree." [verified]

This is not a serialization gap that a better encoder would close. It is a
**false assertion**, well-formed, machine-readable, and wrong — the failure mode
an attestation is least able to survive, because a consumer has no way to detect
it from the artifact. The tree at this very basis is dirty — `git status
--porcelain` returns a non-empty result, carrying the untracked `.probe-repo/`
before this document's own two files were added — which is why the Basis section
says so rather than leaving it to be assumed. [verified]

`HEAD` **may** appear as an annotation that declares itself to be one. It may
never appear as `subject`.

### D3 — The constitution and the spec are materials, not subjects

**`constitution_hash` is an input, not a product.** It is the only
digest-shaped value already in the receipt — `scripts/write_receipt.py:135` —
and it is pinned fail-closed before the run: `scripts/launch_checks.py:61-64`
computes the sha256 of the constitution bytes and stops on
`CONST-HASH-MISMATCH` against `constitution_hash_expected` in the manifest,
whose example value sits at `templates/manifest.example.json:5`. It is a real
digest of a genuinely immutable artifact — `N1-SUBJECT.md:99`, `:117` — and
`N1-SUBJECT.md:126` names the disqualifying fact: as `subject[0]` it yields a
Statement about the governance text rather than about anything the run
produced. It descends to a material or an annotation. [verified]

**The spec blob is derivable but not derived.** `$SPEC` is `"$1"`
(`scripts/launch_worker.sh:39`), an argv path checked only for existence at
`:40`, reduced to a `basename` at `:94`, and fed to the child at `:370`. The
launcher runs `git` in exactly two places — `rev-parse --show-toplevel` at `:52`
and the worktree-claim check at `:253` — and **never on `$SPEC`**. A spec is
under no obligation to live in a repository at all. It descends to a material or
an annotation. [verified]

**If the spec blob is included, its algorithm name is `gitBlob`, not `sha256`.**
`harness-pack/ADR-018` D2, on the in-toto registry at `digest_set.md:103`. A git
object id labelled `sha256` is a false statement about the algorithm, and
`git rev-parse --show-object-format` returns `sha1` here. [verified]

### D4 — The predicate

**Primary: Simple Verification Result.**

**A measured fact about the specification itself, recorded because it is the
argument for pinning.** The same URI, read twice, gave two different documents.
A prior reading on 2026-08-13 reported Type URI `.../svr/v0.2`, Version 0.2,
sha256 `60d47f83…`; an independent fetch reported `.../svr/v0.1`, Version 0.1,
with changelog "0.1: Initial version".

**What this document read, literally.** Re-fetched at this basis from
`in-toto/attestation` `main`, `spec/predicates/svr.md`:

- sha256 `60d47f833f7998926aa991d1aa6ab9ef9a2a916771a99232b624ea0c45c9da1a`
- 7540 bytes
- `:3` — `Type URI: https://in-toto.io/attestation/svr/v0.2`
- `:5` — `Version: 0.2`
- byte-identical to the S1 copy (`diff` reported no differences)

The Type URI written into the artifact is the one read literally:
**`https://in-toto.io/attestation/svr/v0.2`**. The divergence is not a blocker;
it is the reason every external spec in the Basis carries a digest. A URI is not
a citation. [verified]

**The v0.2 reading requires a fourth field, and that is recorded, not
absorbed.** Counted precisely, because the count is the point:

- **Three required fields at the top of `predicate`:** `verifier` (`:80`),
  `timeCreated` (`:99`), `properties` (`:103`).
- **`verifier` itself carries two required sub-fields:** `verifier.id` (`:84`)
  and **`verifier.policies`** (`:92`).
- So the mandatory **leaves** a producer must fill are **four**:
  `verifier.id`, `verifier.policies`, `timeCreated`, `properties`.

The Parsing Rules at `:74-76` state the fourth one before the field table
reaches it: "The `verifier.policies` field MUST be present. If no explicit
policies were used, or the verifier cannot reference the policies, producers
MUST encode this as an empty array." The changelog at `:225-229` confirms this
is exactly what 0.2 changed, and that it "is not backward-compatible with v0.1
producers that omitted policy details".

A three-leaf mapping is therefore a **v0.1** mapping, and the mapping below is
written against three leaves because that is what the decision fixed. The fourth
is not silently invented here: it is OR-1. [verified]

**Mapping.**

- **`verifier.id`** — a URI under a domain the operator controls, versioned
  when the verification logic changes materially. `svr.md:86-90` RECOMMENDS
  precisely this: "It is RECOMMENDED to version the identifiers when their
  verification logic changes materially". The two values that version it are
  **`constitution_hash`** and **`manifest_version`**, both already in the
  receipt at `scripts/write_receipt.py:135` and `:134`. No new measurement is
  required to know when the identifier must move. [verified]
- **`timeCreated`** — `$.ended_at`, written at
  `scripts/write_receipt.py:136`. [verified]
- **`properties`** — a controlled vocabulary, `HARNESS_` prefixed, **coined here
  and closed**:

  Every line number in this table is in `scripts/write_receipt.py` unless named
  otherwise.

  | Property | Receipt source |
  |---|---|
  | `HARNESS_MODE_B` | `$.mode` = `"B"`, at `:132` |
  | `HARNESS_CONSTITUTION_PINNED` | `$.constitution_hash`, at `:135`; the pin is enforced at `scripts/launch_checks.py:61-64` |
  | `HARNESS_GATE_PASS` | `$.gate.verdict` = `PASS`; `gate_summary` built at `:52`, placed at `:142` |
  | `HARNESS_CONTRIBUTION_CONTRIBUTED` | `$.contribution.verdict` = `CONTRIBUTED`, assigned at `:85`, placed at `:93` |
  | `HARNESS_CONTRIBUTION_NO_OP` | `$.contribution.verdict` = `NO_OP`, assigned at `:85`, placed at `:93` |
  | `HARNESS_REFUSALS_RECORDED` | `$.refusals`, built at `:129`, placed at `:144` |

  The vocabulary has no `HARNESS_CONTRIBUTION_NOT_EVALUATED` and that is
  deliberate, not an omission: `NOT_EVALUATED` is the third value
  `write_receipt.py:87` can assign, and it means the gate produced no verdict.
  Under the passing-only rule below, a run that evaluated nothing emits neither
  contribution property. Absence already says it. [verified]

  The prefix convention is the specification's own: `svr.md:105-108` says
  properties "SHOULD be scoped according to the framework being verified or the
  verifier's policy rules. For example, this could be a policy engine prefix
  like `AMPEL_` or `CONFORMA_`." [verified]

  **`properties` lists ONLY properties verified as passing.** This is the
  specification's own word — `svr.md:105`, "Indicates the **passing** properties
  verified for the artifact". Therefore, and this is the rule a reader must not
  get wrong: **an absent property means not verified, never failed.** A consumer
  that reads absence as failure is reading the artifact incorrectly, and a
  producer that omits a property to signal failure is writing it incorrectly.
  The vocabulary is closed so that "not in the list" has exactly one meaning.
  [verified]

**Companion, optional: `link/v0.3`.** Type URI
`https://in-toto.io/attestation/link/v0.3` (`link.md:3`, Version 0.3 at `:7`).
It carries `byproducts` (`:86`, optional) and `environment` (`:92`, optional)
without loss, which is where the run's non-verdict material can go if it is ever
wanted. **It is not the primary predicate** and nothing in this ADR requires it
to exist. [verified]

### D5 — A side-car, never an amendment

The Statement is a **sibling file**, `<run_id>.intoto.json`, written beside the
receipt.

This is the exact precedent `harnesswright/ADR-0008` D5 `:107-109` sets, and it
is adopted rather than reinvented. That text: the authoritative record "must not
be added by amending one: `receipt_chain.py` records the sha256 of the source
file's bytes (harness-pack ADR-005), so a receipt mutated after a rollup breaks
every chain line covering it", and "The authoritative record is a **sibling
file** … The repository already carries this shape — `run-<id>.cc.json` sits
beside `run-<id>.receipt.json` — so this introduces a filename, not a
convention." [verified]

Re-verified at this basis rather than taken on the quotation:
`scripts/receipt_chain.py:47-48` hashes the source file's raw bytes, and
`verify()` at `:73` chains on the raw bytes of each line. A mutated receipt
breaks every covering line. [verified]

**The proprietary receipt does not change by one byte as a result of this ADR.**

### D6 — The Statement carries no prose

Digests, enums and ids only. Never `claims[*].evidence` (written at
`scripts/launch_worker.sh:301` and `:303`), never `gate.reason`
(`scripts/write_receipt.py:46`, `:52`), never `refusals.denials`
(`scripts/write_receipt.py:129`). [verified]

The rule is stated here; the full rationale belongs to **ADR-C**, the claims-layer
ADR, and is deferred to it rather than half-argued here. What this document
needs from it is only the boundary: the Statement is the machine-readable
assertion, and free text is not part of it.

### D7 — No transcript, no Statement

If `$OUT` is **absent or unreadable at the moment the digest is taken** — the
moment D1 fixes, between `CC_EXIT=$?` at `scripts/launch_worker.sh:371` and the
writer at `:409` — the launcher emits **no Statement at all**. The absence of
the side-car file is itself the signal.

Three shapes this rule refuses, named one at a time because each is a thing
someone would otherwise reach for:

- **No Statement with an empty subject.** Statement v1 does not admit one.
  `statement.md:37`, verbatim: "Each element MUST have `digest` set." A
  subject-less Statement is not a degraded artifact, it is a rejected one, so
  emitting one buys nothing a consumer can use. [verified]
- **No substitute subject.** Not `HEAD`, not the spec blob, not the
  constitution. D2 and D3 refuse each of those on the merits for the run that
  succeeded; a failure branch is not a licence to revisit them.
- **No change to the receipt.** The run still writes its receipt exactly as it
  writes one today, carrying the `{"subtype": "error_no_output"}` that
  `scripts/write_receipt.py:156-158` substitutes for an unreadable `cc.json`.
  D5's "**The proprietary receipt does not change by one byte as a result of
  this ADR**" holds on this branch too, and this decision is where that is
  stated rather than assumed. [verified]

**Why silence rather than a well-formed artifact.** Since Statement v1 rejects a
subject-less Statement, the only way to emit one on this branch is to
**fabricate a subject**. That is the same trade D2 already refused for `HEAD`,
and it fails in the same way. An artifact that is **absent** is a verifiable
fact: a third party looks for `<run_id>.intoto.json` beside the receipt, does
not find it, and knows precisely what that means. An artifact that is
**present** carrying an invented subject is a false assertion — well-formed,
machine-readable and wrong — which is the failure mode D2 names as "the one an
attestation is least able to survive, because a consumer has no way to detect it
from the artifact". [verified]

The asymmetry is the argument. A missing side-car costs a consumer one lookup. A
fabricated one costs them the ability to trust any side-car, including every
true one.

**This is a rule about the failure branch, and the failure branch is the first
thing an external reader inspects.** D1 is written for the run that produced a
transcript and says nothing about the run that did not. An unstated failure rule
is not an absent rule: it is a rule decided later, by whoever writes the code,
under time pressure, in the direction that yields an artifact. It is decided
here instead, while nothing has been written and the decision is free.

## Verification

Named here, authored at acceptance, to `vault/ADR-073` D1's standard — "A gate
observed only passing is untested and carries no evidentiary weight" (`:243-244`).
That ADR reads `status: proposed` at this basis (`:3`); its own D4 exempts this
citation direction explicitly, being scoped at `:371-372` to
"governance-citing-project only" with "Project documents citing governance …
untouched". [verified]

**D1 — `bypass_att_subject_missing`.** A Statement whose `subject[0].digest` is
absent or empty must be **rejected**. **RED already observed in S1**, not
predicted: all three projections fail the Statement v1 rule —
`GAP.md:207`, `subject[0].digest set | FAIL | FAIL | FAIL`, against
`statement.md:37`, "Each element MUST have `digest` set." The fixture's job is
to hold that RED in the suite rather than in a measurement document. [verified]

**Landed at ratification.** `tests/bypass_att_subject_missing_fixture.sh` carries
an acceptance predicate built from `statement.md:37` alone, refuses all three
shapes `GAP.md` measured — subject absent, `subject[0]` without `digest`,
`subject[0].digest` empty — accepts a hand-written conforming Statement, and then
requires the emitted one to be accepted **with `subject[0].digest.sha256` equal
to the transcript's recomputed bytes**. A subject carrying *some* digest
satisfies `statement.md:37` while still naming the wrong artifact, so the row
asserts which digest and not merely that there is one. GREEN. [verified]

**D2 — the dirty-tree fixture.** A fixture that emits a Statement on a dirty
tree and asserts that `subject[0]` is **not** `HEAD`'s commit. Its value is that
it fails on the *easy* implementation: the one that reaches for
`git rev-parse HEAD` because it is available at `:52` and produces a
well-formed artifact. [inferred] that the easy implementation is the likely one,
from the fact that `HEAD` is already derivable and `$OUT`'s digest is not.

**Landed at ratification, and one thing was measured that this row's naive form
would have got wrong.** `git rev-parse --show-object-format` returns `sha1`, so a
commit id is 40 characters and a sha256 is 64: "`subject[0].digest.sha256` is not
`HEAD`" can never be false by accident, and a row resting on that comparison
alone would be green because two string lengths differ. So
`tests/bypass_att_dirty_tree_subject_fixture.sh` refuses the easy
implementation's artifact in **both spellings** before accepting the real one —
`{"sha256": "<HEAD>"}`, the easy value under the algorithm name
`harness-pack/ADR-018` D2 forbids for a git object id, and
`{"gitCommit": "<HEAD>"}`, the same value correctly labelled and refused anyway,
because the objection is not the spelling. The premise is measured in the run's
own repository at assertion time (`git status --porcelain` non-empty), and the
run's `HEAD` appears **zero times** in the emitted bytes. GREEN. [verified]

**D4 — `bypass_att_result_desync`.** A Statement listing `HARNESS_GATE_PASS`
while the gate exited non-zero must be **rejected**. **Not yet observed, and
declared as such** — unlike D1, there is no measured RED behind this one, because
no Statement has ever been emitted. It is a prediction until the fixture runs.

**Observed at ratification, and the prediction held.** The fixture produced the
RED itself rather than waiting for one: three fabricated desyncs — a Statement
listing `HARNESS_GATE_PASS` beside a receipt whose gate read `FAIL`, `STOP` and
`NO-VERDICT` in turn — were each refused, and the emitter was then shown to omit
the property on all three of those runs while carrying it on a passing one.
"The gate exited non-zero" is read as `$.gate.verdict != "PASS"` and **not** as
`$.gate.verity_exit != 0`, and the reading is recorded because it is
load-bearing: `verity` runs over the whole target repository while the gate is
scoped to `spec.criteria`, so a run whose every declared criterion passes can sit
beside a non-zero `verity_exit` from a claim this slice never declared. A
detector keyed to the exit integer would refuse a Statement that is true.
`HARNESS_GATE_PASS` is keyed to the verdict the launcher takes the run's own exit
from. GREEN. [verified]

**D5 — the chain survives the side-car.** A fixture that appends the receipt to
a chain, writes the side-car, and re-verifies the chain, which **must still
verify**. This is `harnesswright/ADR-0008` D5 `:115`'s own falsifier, adopted
verbatim in shape: "Under the rejected in-receipt design the same fixture breaks
the chain, and that break is the demonstration." [verified] that the fixture is
specified there.

**Landed at ratification, and the demonstration is not where the quoted sentence
implies it is.** The chain verified before the side-car; the receipt's bytes were
unchanged after it (`5dc2bbb5…` on both sides); the covering line's recorded
digest still matched; `verify` still said `VALID: chain intact`. The rejected
in-receipt design, applied to a copy, moved the receipt's bytes to `fe70ad82…`
while its covering line went on recording the first — **and `verify` reported
`VALID` on that chain too**, because `scripts/receipt_chain.py:70` reads only
`prev_sha256` and `seq` and `:73` re-hashes the *line*, never the source file.
The break is real and `verify` is not the instrument that shows it, so the
fixture asserts on the covering line's recorded digest and says so rather than
letting a green `verify` stand in for a check it does not perform.
`harness-pack/ADR-018` D4 measured the same narrowness from the other side.
GREEN. [verified]

**D7 — `bypass_att_no_subject_no_statement`.** A run whose `cc.json` is
unreadable produces a receipt and **zero** `.intoto.json` files. **Not yet
observed, and declared as such** — no `error_no_output` run has been measured at
this basis and no Statement has ever been emitted, so both halves of the
assertion are predictions. Unlike D3 and D6 below, this row is not an exclusion
rule over a non-existent artifact: it asserts the **absence** of a file, which
is observable the moment a writer exists and is observable on a run the launcher
can already produce. The fixture belongs to this ADR's implementation, not to
the amendment that adds this decision, and it is written when the writer is.

**Observed at ratification, in both halves, and one of them corrected a reading
this document had not made explicit.** `tests/bypass_att_no_subject_no_statement_fixture.sh`
drove `scripts/launch_worker.sh` **in tree** twice, with the executor stub
fabricating the condition and nothing else:

- **Transcript genuinely unreadable at digest time.** The run wrote its receipt,
  carrying `subtype: error_no_output`, and the receipts directory held **zero**
  `.intoto.json` files. Both halves of this row, observed against the unpatched
  launcher. The fixture checks the premise — that the transcript really was
  unreadable — rather than inferring it from the zero.
- **Executor that simply wrote nothing.** The receipt *also* read
  `error_no_output`, and a Statement **was** emitted, over a zero-byte
  transcript, subject digest
  `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

**The two states are not one state, and the second is not a defect.** D7's
condition is "absent or **unreadable**", which is a property of the file and not
of its contents; `$OUT` is created by the launcher's own redirection
`"${CMD[@]}" < "$SPEC" > "$OUT"` **before the child runs**, so an empty or
malformed transcript is readable and has a digest like any other byte string.
Attesting to it is D1 applied literally, with nothing fabricated and nothing
substituted. What this observation costs is an inference a reader would otherwise
have made for free: **`error_no_output` in a receipt does not imply that D7's
branch was taken.** The Assumption ledger row that carried the branch's
reachability as `[assumed]` is updated below rather than deleted, and the second
falsifier it named — a reading under which `cc.json` cannot be unreadable, which
would make D7 vacuous — is **answered no**: the branch was reached. [verified]

**`bypass_att_canon_reorder` — not this document's row, named here because this
is where it becomes writable.** It is `harness-pack/ADR-018` D1's falsifier, held
open as that ADR's OR-6 for the reason it states — "a falsifier that is green
because its subject does not exist is precisely the defect
`harness-pack/ADR-017` names" — with its birth moment declared as "the first
side-car Statement emitted". D5's side-car is that artifact. The fixture reorders
the emitted Statement's keys at every depth, re-serializes in
`harness-pack/ADR-018` D1's form, and requires the same content id; it first
shows that the reordering is real (the naive serialization differs) and that the
form is load-bearing (the receipt's own `indent=1` form yields a different
content id). GREEN, and `harness-pack/ADR-018` OR-6 closes. [verified]

**D3 and D6 — no fixture named here.** Both are exclusion rules over an artifact
that does not exist; a falsifier named against a non-existent artifact is the
defect `harness-pack/ADR-017` is about. They are OR-4 and OR-5.

**At ratification the artifact exists, and neither row is written even so.** The
premise that held them open is gone — there is a Statement to exclude things
from — so their birth moment has arrived and is recorded as arrived. They are
still not written here, for a reason that is specific rather than general: D6's
falsifier is `bypass_att_prose_leak`, and `harness-pack/ADR-020` D2 owns it,
names it, and is **Proposed**. `harness-pack/ADR-006:56` forbids writing code
against a Proposed ADR, so the fixture belongs to that document's ratification
and not to this one. D3's falsifier waits with it rather than shipping alone,
because D3 and D6 are the two exclusion rules and splitting them across two
commits would leave the register carrying half a pair with nothing recording why.
Both stay OR-4 and OR-5, with this as their reason. [verified]

## Non-goals

- **It signs nothing.** No key, no DSSE envelope, no signing posture.
- **It anchors nothing to a transparency log.**
- **It does not touch `verity`.** The gate is read; the tool is unchanged.
- **It does not modify the receipt** — not its fields, not its serialization,
  not one byte.
- **It does not decide the claims layer.** That is a separate ADR (ADR-C), and
  D6 defers to it by name.
- **It writes no code**, no fixture, and no schema. True of the proposing commit;
  **not true of this one**, which ships the digest line, the emitter, the wiring,
  the manifest key and six fixtures, all named in the Status block. **No schema
  file ships even so**, and nothing here modifies `scripts/write_receipt.py`,
  `scripts/receipt_chain.py` or `templates/receipt.schema.json` — the receipt's
  serialization, including `indent=1` at `write_receipt.py:163`, is untouched.

## Open requirements

- **OR-1 — `verifier.policies` placement.** SVR v0.2 requires the field; the
  minimal conformant value is `[]`. The constitution is the obvious candidate
  ResourceDescriptor, since its digest is already pinned and enforced
  (`launch_checks.py:61-64`) — but D3 assigns the constitution to "a material or
  an annotation", and SVR has **no** `materials` field at all (that belongs to
  the `link/v0.3` companion). Which slot the constitution takes is therefore
  under-determined by D3 read against v0.2, and is **not decided here**.
  Falsified by the first conformant Statement: it must carry `verifier.policies`
  in some form, and whichever form it carries answers this.

  **OPEN at ratification, and the branch that ships is the written one.** The
  emitter writes `[]`, with the reason beside it in the source rather than left
  to be reconstructed. `harness-pack/ADR-020` D4 decides what the field carries —
  the `ResourceDescriptor` of the target repository's claims manifest, digested
  at the moment of the gate — and that document is **Proposed**, so
  `harness-pack/ADR-006:56` forbids implementing it. `svr.md:74-76` makes `[]`
  the minimal **conformant** value: "If no explicit policies were used, or the
  verifier cannot reference the policies, producers MUST encode this as an empty
  array." A recorded `[]` with a written reason is honest; a fabricated
  descriptor is not. This OR closes when `harness-pack/ADR-020` is ratified and
  its own OR-1 — the second `shasum` — is written.
- **OR-2 — the `verifier.id` domain.** D4 requires a URI under an
  operator-controlled domain. Which domain, and its versioning scheme, is an
  operator decision not taken here.

  **CLOSED at ratification.** The value is read from the manifest, key
  `verifier_id`, and is never defaulted: `scripts/write_statement.py` STOPs
  fail-closed on its absence — `STOP: VERIFIER-ID-ABSENT` — on the model
  `scripts/launch_checks.py:61-64` uses for `CONST-HASH-MISMATCH`.
  `templates/manifest.example.json` carries a **placeholder** in the
  `*_CLASS_MODEL` convention, `OPERATOR_VERIFIER_ID_URI`, never a real domain:
  `harness-pack/ADR-004` keeps operator literals out of tracked files and
  `privacy-lint-model-id` in `.verity/claims.json` already documents that
  convention by name. The domain and its versioning scheme remain the operator's
  to choose in their own copy, which is what this OR left open; what is closed is
  **where the value comes from**. [verified]
- **OR-3 — the side-car's own canonical form.** `harness-pack/ADR-018` D1 binds
  new content-addressed artifacts. Whether the side-car is itself
  content-addressed — and therefore whether it is rolled into the chain — is not
  decided here.

  **CLOSED at ratification: YES.** The emitter serializes in
  `harness-pack/ADR-018` D1's form — keys sorted lexicographically, compact
  separators, no whitespace, UTF-8 — and writes **no trailing newline**, so the
  file's bytes *are* the serialization and `sha256(file)` is the artifact's
  content id with no second convention about framing. That is what makes
  `harness-pack/ADR-018` OR-6 writable, and `bypass_att_canon_reorder` is the
  fixture that holds it. Per `harness-pack/ADR-018` OR-1, no document in this
  family may describe that form by the name of any external canonicalization
  standard, and this paragraph does not.

  **Whether the side-car is rolled INTO the chain is a separate question and is
  not closed here.** D5's falsifier establishes only that the chain survives the
  side-car's existence; appending the Statement as its own chain source is a
  decision no ADR has taken. [verified]
- **OR-4 — a falsifier for D3.** Named when the Statement writer exists.

  **OPEN at ratification, with its birth moment recorded as arrived.** The writer
  exists, so the premise that held this open is gone. It is not written here
  because it is the pair to OR-5, whose reason is specific and is stated there.
- **OR-5 — a falsifier for D6**, and ADR-C, which owns its rationale.

  **OPEN at ratification.** ADR-C is `harness-pack/ADR-020`, it names D6's
  falsifier `bypass_att_prose_leak` in its own Verification, and it is
  **Proposed**. `harness-pack/ADR-006:56` forbids writing that fixture against a
  Proposed ADR, so it belongs to that document's ratification. Both this OR and
  OR-4 close there.
- **OR-6 — the `shasum` line itself.** D1's whole cost is one line between
  `:371` and `:409` that does not exist. It is implementation and is not written
  here.

  **CLOSED at ratification: the implementation carries it.**
  `scripts/launch_worker.sh` now computes the sha256 of `$OUT`'s raw bytes
  between `CC_EXIT=$?` and the receipt writer, exactly where D1 places it. It
  uses `hashlib` through `python3 -c` rather than `shasum(1)`, because `python3`
  is already a hard dependency of the launcher and `scripts/launch_checks.py:61`
  pins the constitution with the same call — one library for both digests in the
  receipt family, rather than a tool that differs per platform. An unreadable
  `$OUT` leaves the variable empty, which is D7's branch and not a failure.
  [verified]

## Consequences

- The family's central measured defect closes. `subject[0].digest` stops being
  ASSENTE in all three projections (`GAP.md:207`) for the price of one `shasum`.
- The Statement is **true on a dirty tree**, which is the only state any run has
  been measured in. That is the whole of D2's value, and it is bought by
  declining the more impressive-looking subject.
- The receipt, the chain, and every chain line written to date are untouched.
  The artifact count grows by one file per run; the mutation count stays zero.
- A third-party verifier can check the subject without being given the
  transcript, and must not be given it (`OPERATOR-GUIDE.md:134`).
- The stack acquires a dependency on one external specification, pinned by
  digest. The two-readings divergence recorded in D4 is the reason that
  dependency is expressed as a hash and not as a link.

## Assumption ledger

- **[assumed] `$OUT` is closed and final at `:371`.** The redirection at `:370`
  completes before `CC_EXIT` is read, and nothing between `:371` and `:409`
  writes to it. Read from the launcher's control flow, not observed under a
  concurrent writer. *Falsified by:* any path that reopens `$OUT` after `:371` —
  a wrapper, a hook, a retry, or a `gtimeout`/`timeout` kill at `:364-365`
  leaving a partially flushed file that is later completed.
- **DECIDED, no longer assumed — `$OUT` may be absent at digest time.**
  `scripts/write_receipt.py:156-158` handles an unreadable `cc.json` by
  substituting `{"subtype": "error_no_output"}`, so the file can be missing or
  malformed. The proposed text carried this as `[assumed]`, with the note that
  "D1 gives no rule for that case". **`D7` is now that rule** — no transcript,
  no Statement — and it carries its own falsifier,
  `bypass_att_no_subject_no_statement`. What remains open is not the rule but
  the observation: **[assumed]** that the branch is reachable as described,
  since no `error_no_output` run has been measured at this basis. *Falsified
  by:* an `error_no_output` run that emits an `.intoto.json` at all — which
  falsifies D7, not this row; or by a reading of `write_receipt.py:156-158`
  under which `cc.json` cannot in fact be unreadable, which would make D7
  vacuous. That second falsifier is why the row stays in the ledger instead of
  being deleted as answered.

  **OBSERVED at ratification. The reading above is preserved and this is
  appended under it, not substituted for it.** The branch **is** reachable:
  `bypass_att_no_subject_no_statement` drove the launcher in tree with a
  genuinely unreadable transcript at digest time, and the run produced a receipt
  and zero `.intoto.json` files. The second falsifier — a reading under which
  `cc.json` cannot be unreadable — is therefore **answered no**, and D7 is not
  vacuous.

  What the observation did change is the sentence this row is written in.
  "`write_receipt.py:156-158` handles an unreadable `cc.json`" conflates two
  states that are not one state, and the run measured both. An `error_no_output`
  receipt is produced by a `cc.json` the writer cannot **parse**; D7 turns on a
  `$OUT` the launcher cannot **read**. The launcher's own redirection
  `"${CMD[@]}" < "$SPEC" > "$OUT"` creates the file before the child runs, so an
  executor that writes nothing leaves an empty, perfectly readable transcript: the
  receipt says `error_no_output` and a Statement **is** emitted, over zero bytes,
  digest `e3b0c442…`. That is D1 applied literally with nothing fabricated, and it
  is recorded here because the inference it blocks is one a reader would make for
  free — **`error_no_output` in a receipt does not imply D7's branch was taken.**
  What remains genuinely `[assumed]` is narrower than the row first carried:
  **[assumed]** that the unreadable branch is reachable in *production* and not
  only under a fixture that arranges it. *Falsified by:* a survey of real runs in
  which no `$OUT` is ever unreadable, which would make D7 a rule about a state
  only a test produces — still not vacuous, but smaller than it looks.
- **[assumed] The re-fetched `svr.md` at sha256 `60d47f83…` is what
  `in-toto/attestation` `main` serves to others.** Two readings of this URI have
  already disagreed once. *Falsified by:* a third reading with a different
  digest — which would not invalidate this ADR, since the pin records what was
  read, but would move the Type URI a future implementation must write.
- **[assumed] The six `HARNESS_` properties are sufficient to express what a
  consumer needs.** The vocabulary is coined here and closed, from the receipt
  fields that exist today. *Falsified by:* a consumer question that no
  combination of the six answers — at which point the vocabulary is extended by
  an amendment, never by an ad-hoc string.
- **[assumed] `manifest_version` and `constitution_hash` are the only two values
  that materially version the verification logic.** Both are in the receipt.
  *Falsified by:* a change in gate behaviour that moves neither — for example a
  change inside `verity` itself, whose version is **not** recorded in the
  receipt at this basis.

## Provenance

Decided from the S1/S2 measurement corpus listed in the Basis, principally
`N1-SUBJECT.md` and `GAP.md`, and from a re-verification pass at `harness-pack`
`3c2680d` in which every line citation above was read against the committed blob
and every external specification re-fetched and re-hashed. No citation in this
document was carried forward from prose.
