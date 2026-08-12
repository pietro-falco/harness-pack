---
type: adr
status: proposed
title: "Algorithm as data: tagged digests and a declared canonical form"
id: ADR-018
date: 2026-08-13
related-adrs: [harness-pack/ADR-005, harness-pack/ADR-006, harness-pack/ADR-008, harness-pack/ADR-009, harness-pack/ADR-019, harnesswright/ADR-0008, vault/ADR-051, vault/ADR-080]
---

# ADR-018 — Algorithm as Data: Tagged Digests and a Declared Canonical Form

## Status

Proposed

**This ADR decides; no code is written against it while it is Proposed.** No
implementation, no fixture, no schema file and no test ships with this commit.
`harness-pack/ADR-006:56` states the rule of itself — "No code is written
against this ADR while it is Proposed" — and `harness-pack/ADR-009:23` reads it
as general and applies it to itself in the same words. This document adopts that
reading and applies it here. [verified]

## Numbering note

018 is taken by sweep, not by increment. `ADR-017` is the filename maximum in
`docs/adrs/`; 012, 014, 015 and 016 are free by that maximum and remain reserved
by intent for the remaining rows of the six-gap arc that ADR-011 and ADR-013
opened, exactly as `ADR-017`'s own numbering note records. This document is not a
gap row and does not take one of them. [verified]

Sweeps run at this basis: `grep -rn 'ADR-018'` over this repository excluding
`.git` returns **zero hits**; `git grep -n 'HP-ADR-018\|harness-pack/ADR-018'`
over the vault at its `HEAD` returns **zero hits**. The same two sweeps for
`ADR-019` also return zero, and 019 is taken by the companion document
`harness-pack/ADR-019`. [verified]

A note on one collision this document must not create. `harnesswright/ADR-0008`
is "the contribution delta — a pre-launch baseline, a three-phase gate, and a
receipt that states its own no-op"; `harness-pack/ADR-008` is the Claude Code
sandbox surface. Different documents, different subjects, and the number is one
digit apart in spelling only: the harnesswright file is named `0008-…` while its
own frontmatter reads `id: ADR-008`. A bare `ADR-008` in this document would be
ambiguous, so every reference below carries the `vault/ADR-051` D1 namespace
prefix and the bare form is never used. [verified]

## Basis

Every line number in this document is read against the bases below and is
**pinned here rather than maintained**. A citation that moves is a citation
against a later basis, not an error in this one.

**Repository heads.**

| Repo | Branch | HEAD |
|---|---|---|
| `harness-pack` | `main` | `3c2680daf6e9d0243fdb804c391fbb8b6f2659b1` |
| `verity` | `main` | `4dc016b354f3a6eb953590167b46bc29eacf3fcb` |
| `harnesswright` | `main` | `edb12a499615bf12aa80e5db1c67a268cb247114` |

Citations into `harness-pack` are read against the committed blob
(`git show HEAD:<path>`), never the working tree, which is dirty at this basis.
Citations into `verity` and `harnesswright` are read against the pinned commits
above.

**Measurement documents.** The S1/S2 measurement corpus under
`${TMPDIR}/attest-s1/`. These are the evidence base; this document cites them
and does not re-derive them.

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

**External specifications**, re-fetched and pinned at this basis. An external
spec cited by URI alone is a citation to whatever that URI serves next; these
are pinned by digest for the reason `harness-pack/ADR-019` D4 records at
length — the same file read twice gave two different versions.

| Spec | Source | sha256 | bytes |
|---|---|---|---|
| in-toto `DigestSet` | `spec/v1/digest_set.md` @ `in-toto/attestation` `main` | `0b1889fdea7f6d623b41555632aedf04ee4398cf02a32002060608c75ebb038e` | 8873 |
| in-toto Statement v1 | `spec/v1/statement.md`, S1 copy | `cbe684a18b812b8b613d9202eb43b2ea24477f91a2ad6ca5be935185a455ebea` | — |
| in-toto ResourceDescriptor | `spec/v1/resource_descriptor.md`, S1 copy | `bee71bedd6a957771233cbbe6494144157b865992e53cc91d607a8e02a34c58a` | — |

**Assertion labels.** `[verified]` — established by an artifact cited here and
re-readable by a third party. `[inferred]` — follows from cited artifacts by an
argument stated at the point of use. `[assumed]` — neither; carried in the
Assumption ledger with its falsifier. An unlabelled assertion is a defect in
this document. These map onto `harness-pack/ADR-008` D6's tiers: `[verified]` is
tier A and may be cited as a finding; `[inferred]` and `[assumed]` are tier B
and may be cited **only** as open requirements. [verified]

## Context

Two defects were measured in S1/S2. They are independent, they are both about
digests, and each one makes the other harder to fix.

**No artifact in this family declares its canonicalization.** The receipt is
serialized by `scripts/write_receipt.py:163` — `json.dump(receipt,
open(argv[2], "w"), indent=1)` — with `indent=1` and **no** `sort_keys`.
`scripts/receipt_chain.py:47-48` then hashes that file's raw bytes:
`with open(src, "rb") as f: digest = _sha(f.read())`. So the receipt's content
identity is the identity of one particular serialization that was never
declared to be the serialization. Measured in `DETERMINISM.md:24-26`: the same
receipt on disk hashes to `61733668c8e16518ae7fb38502af10664cdc60646c779ece9aba84f5623ccb20`
at 1560 bytes; the same logical object re-serialized sorted, compact and
whitespace-free hashes to
`c4da63a63f17793349c33e7fd3d283ce7e8157a02e6a883fae18f9e6d598e5e9` at 1298
bytes. A 262-byte formatting delta, two different content ids, one object.
[verified]

The repository already writes the sorted-compact form — one line away, in the
same family. `scripts/receipt_chain.py:54` emits each chain line as
`json.dumps(entry, sort_keys=True, separators=(",", ":"))`. The form this
document adopts is therefore not new to the repo; what is new is *declaring* it,
and declaring which artifacts it binds. [verified]

**Two candidate tagged-digest conventions exist and zero implementations.**
`harnesswright/ADR-0008` D5, at `:111`, is Accepted (`:3`, `status: accepted`)
and fixes the shape verbatim: "any digest it carries is written as
`{"alg": "sha256", "value": "..."}`, algorithm as data, never folded into a
field name." in-toto's `DigestSet` is a different shape — a map from algorithm
name to hex, `{"sha256": "<hex>"}`. `N2-CHAIN.md:144-147` states the
consequence: "These are not the same shape and a verifier cannot read one as the
other." Neither has ever been emitted: a sweep for `"alg"` across all four repos
— `harnesswright`, `harness-pack`, `verity`, `verifiable-intel` — returns one
hit, the ADR sentence itself (`N2-CHAIN.md:140-141`), and an independent
re-sweep across the other three at this basis returns zero. The artifact ADR-0008 D5 binds,
`<run_id>.acceptance.json` at `:109`, is explicitly deferred at `:113` — "Its
implementation is a later slice". [verified]

So the family holds two conventions and no artifacts. That is the cheapest
possible moment to reconcile them, and the most expensive one to postpone: the
first artifact emitted under either shape makes the other one a migration.

## Decision

### D1 — A content-addressed artifact declares its canonical form before it receives an identifier

Every artifact that receives a content-addressed identifier declares its
canonicalization **before** it receives one. The form adopted for **new**
artifacts is JSON with keys sorted lexicographically, compact separators
(`","`, `":"`), no whitespace, UTF-8.

**The existing receipt is not retroactively canonicalized.**
`scripts/write_receipt.py:163` uses `indent=1` without `sort_keys` and continues
to do so until a later ADR changes it. The reason is not inertia:
`scripts/receipt_chain.py:47-48` hashes the receipt file's raw bytes, so
reformatting a receipt changes its digest, and every chain line covering it
records the old one. Reformatting is indistinguishable from tampering to the
instrument built to detect tampering. [verified]

**Open requirement, not a claim: the adopted form is NOT RFC 8785 JCS.**
`DETERMINISM.md:68-80` measures two divergences and this document registers both
as open, not as established properties:

- **Number serialization.** JCS mandates ECMAScript `Number::toString`. Python's
  float repr agrees for `$.total_cost_usd = 0.1019731` and for the integers in
  the measured receipt, but `DETERMINISM.md:74-76` records that "the agreement
  is incidental". `$.total_cost_usd` is a **float**, written at
  `scripts/write_receipt.py:139` from the child's value. [verified] that the
  field is a float and that the agreement was measured on one value;
  [assumed] that it holds for all values the child can produce.
- **String escaping.** JCS fixes an escaping table; `ensure_ascii=False`
  approximates it. `DETERMINISM.md:78-80` records that **no non-ASCII appears in
  the measured receipt**, so the difference is untested rather than absent.
  [verified] that it is untested.

Calling the adopted form "JCS" would be a claim this basis does not support.
It is called what it is: sorted, compact, UTF-8 JSON. Whether it is *made* JCS,
and at what cost, is OR-1.

### D2 — The algorithm is data, never a field name

Every digest written into a **new** artifact is an in-toto `DigestSet`: a JSON
object mapping algorithm name to lowercase hex, `{"<algorithm-name>": "<hex>"}`.
Never a field whose *name* is the algorithm.

Algorithm names follow the in-toto registry, pinned in the Basis:

- **`sha256`** for digests over raw bytes. Registered at `digest_set.md:32`.
- **`gitBlob`** and **`gitCommit`** for git object identifiers. Registered at
  `digest_set.md:103`, defined at `:105-107` as "The lowercase hex SHA-1 (40
  character) or SHA-256 (64 character) of a git commit, tree, blob, or tag
  object". [verified]

A git object id **is never called `sha256`**. Measured: `git rev-parse
--show-object-format` returns `sha1` in both `harness-pack` and `harness-smoke`
at this basis, and `N1-SUBJECT.md:52-54` records the same. A 40-hex git id
labelled `sha256` is a false statement about the algorithm, machine-readable and
wrong, and `digest_set.md:139` names `gitCommit` as the conventional choice for
git. [verified]

`prev_sha256` and `sha256` in the existing chain line are exactly the defect this
decision names: the algorithm folded into the field name, so the field cannot
express a second algorithm without being renamed. They are not retrofitted —
see D4.

### D3 — Partial supersession of `harnesswright/ADR-0008` D5, on the shape only

`harnesswright/ADR-0008` D5 `:111` is Accepted and fixes
`{"alg": "...", "value": "..."}`. **No artifact on disk emits it** (Context,
[verified]). On this one point it is superseded by D2.

The reason is not preference. Two tagged-digest conventions inside one stack is
precisely the drift this family of documents exists to prevent, and of the two,
`DigestSet` is the one a third-party verifier already reads: it is the shape
in-toto's own Statement uses for `subject[*].digest`
(`statement.md:15`, `"digest": {"<ALGORITHM>": "<HEX_VALUE>"}`) and the shape
`resource_descriptor.md:46` names. Choosing the other shape would mean every
consumer of these artifacts writes an adapter that exists only because two of
our own documents disagreed. [verified] on the shapes; [inferred] that a third
party reads `DigestSet` without an adapter, from the fact that it is the
framework's own shape.

**The rest of `harnesswright/ADR-0008` D5 stands, untouched.** The sibling-file
design at `:107-109` — the receipt is write-once, the authoritative record is a
sibling `<run_id>.acceptance.json`, and a receipt must not be amended because
`receipt_chain.py` records the sha256 of its bytes — is not weakened here. It is
in fact adopted and extended by `harness-pack/ADR-019` D5, which places its
Statement beside the receipt on the same precedent. What D3 changes is the
spelling of the digest that sibling carries, and nothing else. [verified]

**OR-2 — the amendment to `harnesswright` is not written here.** Amending an
Accepted ADR in another repository is a separate commit in that repository,
against its own gate. The exact target is
`harnesswright/docs/adrs/0008-contribution-delta-three-phase-gate.md`, D5, the
sentence at `:111`. Until that amendment lands, the two documents disagree on
disk and this document is the one that records the disagreement. That state is
declared, not hidden.

### D4 — The chain line takes the new form at the next genesis, never retroactively

Measured in `N2-CHAIN.md`, and each fact independently re-verified at this basis:

- `verify()` reads exactly two fields, `prev_sha256` and `seq`, both at
  `scripts/receipt_chain.py:70`. It never reads `sha256`.
  (`N2-CHAIN.md:99`, `:107`.) [verified]
- `prev = _sha(stripped)` at `scripts/receipt_chain.py:73` hashes the raw bytes
  of the line as written, so **any** change of line shape invalidates the chain
  from that line forward. (`N2-CHAIN.md:115`.) [verified]
- `harness-pack` has **no live chain**. One chain file is tracked,
  `examples/receipt-chain.sample.jsonl`, 3 lines, a fixture. There is no
  `.harness/` directory in the working tree at this basis.
  (`N2-CHAIN.md:27`, `:31-32`.) [verified]
- The only live chain in the family is 8 lines, in `verifiable-intel`.
  (`N2-CHAIN.md:26`, `:29`.) [verified]
- Lines that can be migrated **in place**: `0` (`N2-CHAIN.md:164`). [verified]

**Decision.** `harness-pack` adopts the new form **at the next genesis**, where
the cost is zero. Existing chains are **not** migrated: rewriting them is
exactly the mutation the chain exists to detect, and a chain that has been
rewritten to look correct is worth less than one that never claimed to be
migrated. A chain that must change shape does so at a **declared seam line**
that names the change, or it does not change at all.

**The new form** replaces `"sha256": <hex>` with `"digest": {"sha256": <hex>}`
and `"prev_sha256": <hex>` with `"prev": {"sha256": <hex>}`. `"GENESIS"` is
preserved as the sentinel value of the first line's `prev`, exactly as
`scripts/receipt_chain.py:34` and `:61` spell it today. [verified]

Note the blast radius this decision accepts and does not resolve:
`specs/recurring/RS-001-receipt-rollup.md` states the co-indexing invariant in
prose over `chain[i].sha256` at `:21` and `:83`. A form change moves that prose
too, in the same commit or not at all. [verified]

### D5 — The chain line has a schema

Measured: `templates/receipt.schema.json` does not constrain the chain line in
any way. It mentions `receipt-chain.jsonl` once, in a `$comment` at `:2`, and
constrains nothing about it — no `seq`, no `prev_sha256`, no line shape. It is
the only schema file tracked in the repository (`git ls-files | grep -i schema`
returns one path). The only declared contract for the chain line is prose: the
module docstring at `scripts/receipt_chain.py:4-7` and
`specs/recurring/RS-001-receipt-rollup.md`. [verified]

A format whose only contract is prose has no reader that can disagree with a
writer. This ADR decides that the **new** form is born with a schema.

**The schema file is not written here.** It is implementation, and
`harness-pack/ADR-006`'s rule binds this document to itself.

## Verification — one falsifier per decision, each named

Named here, authored at acceptance. `vault/ADR-073` D1 is the standard each of
these is written to meet: "A gate ships with a positive-control fixture that
makes it fail. **A gate observed only passing is untested and carries no
evidentiary weight.**" (`:243-244`, verbatim). Where a RED has already been
observed it is cited rather than predicted. [verified]

`vault/ADR-073` reads `status: proposed` at this basis (`:3`), and that is
recorded rather than glossed. It does not make this citation a defect: that
ADR's own D4 — "An accepted document may not rest on a proposed norm from
another namespace" — is **explicitly scoped** at `:371-372` to
"governance-citing-project only", and states that "Project documents citing
governance … are untouched". This is a project document citing governance, which
is the exempt direction, and the exemption holds whatever status this document
later takes. [verified]

**D1 — `bypass_att_canon_reorder`.** The same logical content, serialized with
reordered keys, must produce the same content id. **RED already observed in S1**,
and not predicted: `DETERMINISM.md:17-21`, on-disk
`61733668c8e16518ae7fb38502af10664cdc60646c779ece9aba84f5623ccb20` at 1560 bytes
against sorted/compact
`c4da63a63f17793349c33e7fd3d283ce7e8157a02e6a883fae18f9e6d598e5e9` at 1298
bytes. The fixture's job is to hold that RED in the suite instead of in a
measurement document. [verified]

**D2 — `bypass_att_alg_unpinned`.** A new artifact that writes a digest into a
field whose *name* is the algorithm must be rejected. **RED today, trivially and
structurally**: the chain line's `sha256` and `prev_sha256` are field names, so
the line cannot express a second algorithm at all — there is no place to put
one. [verified]

**D3 — a two-repo shape sweep.** A fixture that sweeps both repositories for
`{"alg":` and for a `DigestSet`, and **fails if both shapes are emitted by new
artifacts**. It is green today by vacuity — zero artifacts of either shape — and
that vacuity is the point: it must go RED the moment the second convention
acquires its first artifact, not at some later audit. Its negative control is
the live corpus at this basis, which must produce zero findings. [verified] on
the current count; [inferred] that vacuous-green is the correct starting state,
since the failure it guards against is a *second* shape appearing.

**D4 — an in-place migration is impossible, demonstrated.** A fixture that
appends a **new-form** line to an **old-form** chain and asserts that `verify`
**FAILS**. That failure is the demonstration that in-place migration does not
exist — not an argument that it is unwise. It is the same fixture idiom
`harnesswright/ADR-0008` D5 `:115` uses in the opposite direction, where the
chain must still verify. [inferred] that it fails, from `receipt_chain.py:70`
and `:73`: the appended line's `prev` would not be read as `prev_sha256`, so the
`entry.get("prev_sha256") != prev` test at `:70` compares `None` against a hex
string. Not yet observed; declared as such.

**D5 — no fixture here.** The schema does not exist, so there is nothing to
falsify. This is OR-3, and naming it as an open requirement rather than as a
falsifier is deliberate: a falsifier listed against a non-existent artifact is
the defect `harness-pack/ADR-017` is about.

## Non-goals

Explicitly, and each one is a thing a reader might otherwise assume this
document does:

- **It does not touch `scripts/write_receipt.py`.** The receipt's serialization
  is unchanged, including `indent=1` at `:163`.
- **It does not touch any existing chain.** Not the 8 live lines in
  `verifiable-intel`, not the 3 sample lines here, not the 3 stale copies.
- **It does not amend `harnesswright`.** That is OR-2, in another repo.
- **It does not choose the predicate or the subject.** That is
  `harness-pack/ADR-019`.
- **It writes no code**, no schema file, and no fixture.

## Open requirements

- **OR-1 — JCS conformance is open.** The adopted form is sorted/compact/UTF-8
  JSON, not RFC 8785. Falsified by a test vector set exercising ECMAScript
  number serialization and the JCS escaping table against the adopted
  serializer. Until then, no document in this family may describe the form as
  JCS or RFC 8785.
- **OR-2 — the `harnesswright/ADR-0008` D5 `:111` amendment.** Target path named
  in D3. Until it lands, two Accepted-or-Proposed documents in the family
  disagree on digest shape, and this document is where that is recorded.
- **OR-3 — the chain-line schema file.** Named by D5, authored at acceptance,
  falsifier to be named with it.
- **OR-4 — the seam-line format.** D4 permits a declared seam line as the only
  way an existing chain may change shape. What a seam line *is* — how it is
  spelled, how `verify` recognizes it, whether it is admitted at all — is not
  decided here. Falsified by the first chain that needs to change shape.
- **OR-5 — `RS-001`'s prose invariant.** D4's form change moves
  `specs/recurring/RS-001-receipt-rollup.md:21` and `:83`. Not performed here.

## Consequences

- The family acquires **one** digest convention, and it is the one an external
  verifier already reads. The cost is one sentence in another repo's Accepted
  ADR (OR-2), paid before any artifact exists.
- The existing receipt and the existing chains are bit-for-bit unchanged, so no
  chain line written to date is invalidated by this decision. The migration cost
  of the whole change, measured, is **8 evidence lines in one repository**
  (`N2-CHAIN.md:163`) — and this ADR declines to spend even that, deferring to
  the next genesis. [verified]
- The repository gains a stated position on canonicalization that it can be held
  to, in place of an unstated one it was already keeping by accident at
  `receipt_chain.py:54`.
- `harness-pack/ADR-019` becomes writable. It cannot name a subject without
  naming an algorithm, which is this document's decision
  (`N1-SUBJECT.md:170-174`). The two are coupled and sequenced: this one first.
  [verified]

## Assumption ledger

- **[assumed] Python's float repr agrees with ECMAScript `Number::toString` for
  every value `$.total_cost_usd` can take.** Measured true for one value,
  `0.1019731` (`DETERMINISM.md:74-76`), which does not establish it.
  *Falsified by:* a run whose `total_cost_usd` serializes differently under the
  two rules. This is why OR-1 exists rather than a JCS claim.
- **[assumed] The escaping divergence between `ensure_ascii=False` and the JCS
  table is unreachable for this corpus.** Held only because no non-ASCII appears
  in the measured receipt (`DETERMINISM.md:78-80`). *Falsified by:* any receipt
  field carrying non-ASCII — a spec id, a model string, a tool name, or a
  `stop_reason` containing a path with a non-ASCII character.
- **[assumed] `verifiable-intel`'s 8-line chain is the complete live-chain
  census for the family.** From `N2-CHAIN.md:15`, "14, of which 8 are evidence",
  measured over the repos surveyed there. *Falsified by:* a live chain in a repo
  outside that survey.
- **[assumed] No consumer outside this stack reads the current chain-line
  shape.** If one exists, D4's next-genesis form change breaks it silently, since
  the change is additive to nothing and renames two fields. *Falsified by:* any
  reader of `receipt-chain.jsonl` not in the four surveyed repos.
- **[assumed] `harnesswright/ADR-0008` D5 `:111` has no dependent already
  written elsewhere.** The sweep that found one hit
  (`N2-CHAIN.md:140-141`) covered four repos. *Falsified by:* a fifth repo, or an
  untracked artifact, emitting `{"alg": ...}`.

## Provenance

Decided from the S1/S2 measurement corpus listed in the Basis, and from a
re-verification pass at `harness-pack` `3c2680d` in which every line citation
above was read against the committed blob and every external spec re-fetched and
re-hashed. No citation in this document was carried forward from prose.
