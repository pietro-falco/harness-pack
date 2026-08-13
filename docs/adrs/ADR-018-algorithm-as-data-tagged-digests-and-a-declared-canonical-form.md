---
type: adr
status: accepted
title: "Algorithm as data: tagged digests and a declared canonical form"
id: ADR-018
date: 2026-08-13
related-adrs: [harness-pack/ADR-005, harness-pack/ADR-006, harness-pack/ADR-008, harness-pack/ADR-009, harness-pack/ADR-019, harnesswright/ADR-0008, vault/ADR-051, vault/ADR-080]
---

# ADR-018 — Algorithm as Data: Tagged Digests and a Declared Canonical Form

## Status

Accepted 2026-08-13 by direct operator ratification, on the text committed at
`e4bfef2c0ac0c01b34e76ba33364fdedc2c900b6`, git blob
`ce7b8bf4347a4b4d9c0f3fc5d2db773e678164da`. Originally proposed 2026-08-13 as a
docs-only commit, under `harness-pack/ADR-006:56` — "No code is written against
this ADR while it is Proposed" — which `harness-pack/ADR-009:23` reads as
general. Per the two-commit lifecycle, acceptance requires operator review and a
separate ratification commit. This is that commit. [verified]

**The ratification commit is the implementing commit, and for a constraint ADR
the implementation is the falsifiers.** Three of the four this document names
land here, registered in `tests/run_tests.sh` under `ADR-017` D2, each carrying
the state its own header declares (`ADR-017` D6):

| Falsifier | Decision | Declared | File |
|---|---|---|---|
| `bypass_att_alg_unpinned` | D2 | RED | `tests/bypass_att_alg_unpinned_fixture.sh` |
| `bypass_att_two_digest_shapes` | D3 | GREEN | `tests/bypass_att_two_digest_shapes_fixture.sh` |
| `bypass_chain_form_migration` | D4 | RED | `tests/bypass_chain_form_migration_fixture.sh` |

`bypass_att_canon_reorder` (D1) is **not** written here, and its reason is OR-6.

**The ratified text differs from the proposed text on five points, named here
rather than left to a diff. No Decision text changes: D1 through D5 stand word
for word as proposed.**

1. This Status block, which records ratification in place of the
   nothing-ships-yet paragraph the proposing commit carried.
2. The Verification section's D1 row, which named a fixture this commit does not
   write; it now says why and refers to OR-6.
3. The Non-goals bullet reading "It writes no code, no schema file, and no
   fixture" — true of the proposing commit, not true of this one. No code and no
   schema file ship even so.
4. The Verification section's D4 row, whose "Not yet observed" was true when it
   was written and stopped being true in this commit. The original sentence is
   kept and the observation appended beneath it, so the record still shows what
   was inferred before it was seen.
5. The Basis's measurement-document paragraph, which cited the corpus at the
   temporary path it was produced under. The digests are unchanged — the same
   bytes — and the citation now names the split the corpus was carried into: a
   manifest tracked in this repository at
   `.verity/evidence/2026-08-13-attestation-s1/README.md`, and the bytes
   themselves held in the operator's private governance vault. Acceptance is
   what makes this document immutable, so a Basis pointing at a swept directory
   had to be repaired before acceptance attached to it, not after. The list
   stays at five and not six: the split is this same difference told correctly,
   not an additional one.

Two facts observed at ratification, recorded here rather than discovered later:

- **D4's falsifier was `[inferred]` and is now observed.** The proposed text
  said of it, "Not yet observed; declared as such".
  `bypass_chain_form_migration` ran at this basis and `verify` refused the mixed
  chain with the signature `INVALID: chain broken at line 3`, exactly as
  `scripts/receipt_chain.py:70` and `:73` predicted. The inference held.
  [verified]
- **The shellcheck leg of the gate does cover the shell this commit adds, and
  an earlier reading that said otherwise was wrong.** That reading observed that
  `.shellcheck-version` pins 0.9.0 while the ratifying host carries 0.11.0, and
  concluded from the mismatch alone that `tests/run_tests.sh` could only report
  `unattrib [shellcheck]` and exit 2 — leaving the three fixtures unchecked by
  the pinned linter. The conclusion did not survive being tested. The pin
  carries a digest per platform, and `scripts/fetch_shellcheck.sh:35` routes
  `Darwin:arm64` to the pinned `darwin.x86_64` build under Rosetta 2, for the
  reason `.shellcheck-version:14-21` states: without a darwin artifact the gate
  on this host is not unfavourable but *unreachable*, and a verdict nobody can
  reach is not a gate anyone can be held to. Fetched at this basis, the tarball
  hashed `7d3730694707605d6e60cec4efcb79a0632d61babc035aa16cda1b897536acf5`,
  matching `SHELLCHECK_SHA256_DARWIN_X86_64` character for character, and the
  extracted binary reports `version: 0.9.0`. With `$SHELLCHECK` pointed at it
  the suite prints ALL TESTS PASSED and exits 0, and the pinned linter at
  `--severity=style` returns **zero diagnostics and exit 0 on each of the three
  fixtures**. The distinction matters in the direction that costs something: an
  unreachable gate reported as unreachable is honest, but reported as
  unreachable when a committed script reaches it is the ratification declining
  to run its own gate — which is the substitution `ADR-017` exists to make
  expensive, in the shape hardest to notice. [verified]

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

**Measurement documents.** The S1/S2 measurement corpus, carried as a split.
Its manifest — path, sha256 and byte length for each of the thirty-two files —
is at `.verity/evidence/2026-08-13-attestation-s1/README.md` in this repository.
Its bytes are held in the operator's private governance vault, in a frozen
evidence bundle carrying those same thirty-two files under the same names. These
are the evidence base; this document cites them by digest and does not re-derive
them, and the digest is the same in either location because the bytes are.

**The corpus was produced under a temporary directory, made durable in this
repository, and then moved into the private vault by the operator.** All three
moves are written down, because the provenance of evidence is itself evidence
and the last link alone is not the chain. The bytes were written under
`${TMPDIR}/attest-s1/`, with one specification under `${TMPDIR}/attest-s2/`, on
a platform that sweeps that location — so the proposing commit's Basis cited an
evidence base with an expiry. They were copied unmodified into
`.verity/evidence/2026-08-13-attestation-s1/`, and every digest in the two
tables below was recomputed against that copy and compared with the value cited
here: **twelve citations, twelve matches, no divergence.** Taken together with
the two specifications `harness-pack/ADR-019` pins and this document does not,
that re-verification covered fourteen. They were then moved out of this
repository, and re-verified a second time at their new location — **all
thirty-two files, not only the fourteen the ADRs pin, matching on both sha256
and byte length, with no divergence**, and with the set of files there equal to
the set of rows in the manifest. Each move changed the path and nothing else.
[verified]

**Open requirement, recorded here so it is not rediscovered.** Two further
documents cite this same corpus by the temporary path and are **not** repointed
by this commit: `harness-pack/ADR-020`, at
`docs/adrs/ADR-020-the-publishable-artifact-is-the-statement.md` in this
repository, and `verity/0002`, at
`docs/adrs/0002-structured-evidence-the-digest-exists.md` in `verity`. Both are
Proposed, so both are still amendable, and each is its own commit. Until they
are repointed, two Proposed documents in this family rest on a path that does
not survive a reboot.

**The corpus is not tracked in this repository, and that is the decision rather
than an omission.** The privacy lint in `.verity/claims.json` guards tracked
files and its pathspecs exclude `docs/adrs/` but nothing under
`.verity/evidence/`. Measured over the thirty-two files while they were still on
disk here and before any was staged, four of its six claims went red:
`privacy-lint-user-paths` (21 files), `privacy-lint-worker-repo-names` (15),
`privacy-lint-vault-name` (7), `privacy-lint-operator-uid-bare` (4). The
measurement documents carry absolute paths and repository names because that is
what they measured — `N3-PUBLISH.md` is a census of receipts *by path* — so
rewriting them to pass the lint would falsify the evidence this document cites,
and widening the lint to exempt `.verity/evidence/` would be a privacy rule with
a carve-out for the one directory holding the private material.

Neither was done. The corpus was split instead: the manifest is tracked here and
the bytes are held in the private vault. The earlier form of this paragraph left
the choice open and said the citations did not depend on it; the choice has since
been made, and this is where it is recorded. It costs the citations nothing for
exactly the reason already stated: **the digests identify these bytes wherever
they are held.** [verified]

**One measured fact about the corpus's new location, recorded because it is a
property of the destination and not of the transfer.** The tree the bytes now
sit in is human-write exclusive under the vault's own written policy — a
standing rule stated for that whole tree, carrying one narrow behavioural
carve-out that has nothing to do with evidence — rather than a directory that
merely happens to be configured against agent writes. The agent holding the
corpus could not place it there and declined to try, and the move is the
operator's own act. A destination whose write-exclusivity is policy rather than
configuration is one whose guarantee does not change when a settings file does.
[verified]

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

The Source column names where each file was fetched from. The copies these
digests were taken from are in the corpus bundle named above, under `spec/`;
their paths and byte lengths are rows in the manifest.

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

**D1 — `bypass_att_canon_reorder`, named and NOT written. It is OR-6.** The
assertion stands as stated: the same logical content, serialized with reordered
keys, must produce the same content id. What cannot be written yet is a fixture
that asserts it against anything D1 binds.

The measured RED is real and is cited unchanged — `DETERMINISM.md:17-21`,
on-disk `61733668c8e16518ae7fb38502af10664cdc60646c779ece9aba84f5623ccb20` at
1560 bytes against sorted/compact
`c4da63a63f17793349c33e7fd3d283ce7e8157a02e6a883fae18f9e6d598e5e9` at 1298
bytes. [verified] But it was measured **on the existing receipt**, and D1
exempts the existing receipt in as many words: "**The existing receipt is not
retroactively canonicalized.**" A fixture built on that measurement would assert
D1 against the one artifact D1 does not reach, and would go green or red on
changes to a file this decision promises not to touch.

D1 binds **new** content-addressed artifacts, and none exists. Writing the
fixture now would produce a green assertion about nothing — which is the defect
`harness-pack/ADR-017` is about, and it is not admitted into the register that
exists to prevent it. OR-6 carries it, with the moment it becomes writable.

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

**Observed at ratification, and the inference held.**
`tests/bypass_chain_form_migration_fixture.sh` seeded a two-line old-form chain
with `receipt_chain.py append`, confirmed it verifies, appended a new-form line
whose `prev.sha256` is the sha256 of line 2's raw bytes — so the line is
materially correct under the new form and only its *shape* is wrong — and
`verify` refused it: `INVALID: chain broken at line 3`, the signature
`receipt_chain.py:71` emits. A second arm appended the same line carrying an
explicit seam declaration and was refused identically, which measures the other
half of D4: the "declared seam line" this decision permits has **no reader**,
because `:70` reads exactly `prev_sha256` and `seq`. That is OR-4, now observed
rather than assumed. The assertion is on the signature and not on an exit
integer, per `vault/ADR-073` D1 `:248-251`. [verified]

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
- **It writes no code and no schema file.** `scripts/write_receipt.py`,
  `scripts/receipt_chain.py` and `templates/receipt.schema.json` are read by the
  fixtures this commit lands and are edited by none of them. The proposing
  commit's form of this bullet also said "and no fixture"; the ratification
  commit ships three, which the Status block names and the register carries.

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
- **OR-6 — `bypass_att_canon_reorder`, D1's falsifier, deferred to its first
  subject.** D1 binds **new** content-addressed artifacts and exempts the
  existing receipt, and no new artifact exists at this basis. A fixture written
  now would either assert D1 against the exempt receipt — the wrong artifact —
  or against nothing at all, and a falsifier that is green because its subject
  does not exist is precisely the defect `harness-pack/ADR-017` names and the
  register built under `ADR-017` D2 refuses to carry.

  **Its birth moment is the first side-car Statement emitted** — the artifact
  `harness-pack/ADR-019` D5 places beside the receipt. That file is the first
  thing this repository content-addresses under D1, and the fixture is written
  in the commit that first writes one: reorder its keys, re-serialize, and
  require the same content id. Until then D1 is a constraint with no artifact to
  constrain, which is a fact about the schedule and not a hole in the decision.

  `harness-pack/ADR-019` OR-3 approaches the same seam from the other side — it
  leaves open whether the side-car is content-addressed at all. If that
  question is answered *no*, this OR does not close; it moves to whichever new
  artifact is content-addressed first, and if none ever is, D1 binds nothing and
  should be superseded rather than left standing with an unwritable falsifier.

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

## Amendment 1 — 2026-08-13 — OR-6 closes: `bypass_att_canon_reorder` has its subject

Appended, not edited. `status` remains `accepted`; no decision D1 through D5 is
altered, superseded or renumbered, and no open requirement is rewritten in place.
Nothing above this line is touched. This amendment records that **OR-6 is
closed**, by the exact event OR-6 itself named, and states what the closure did
and did not settle. The form is the one this repository already uses for a
post-acceptance record — `harness-pack/ADR-008` Amendments 1 and 2,
`harness-pack/ADR-010` Amendments 1 and 2 — and which `vault/ADR-080` states as
"Appended, not edited."

**The condition OR-6 set, quoted.** "**Its birth moment is the first side-car
Statement emitted** — the artifact `harness-pack/ADR-019` D5 places beside the
receipt. That file is the first thing this repository content-addresses under D1,
and the fixture is written in the commit that first writes one: reorder its keys,
re-serialize, and require the same content id."

**The condition is met.** `harness-pack/ADR-019` was ratified on 2026-08-13 and
its ratification commit is its implementing commit. `scripts/write_statement.py`
emits `<run_id>.intoto.json` beside the receipt, serialized in **D1's form** —
keys sorted lexicographically, compact separators, no whitespace, UTF-8 — and
with **no trailing newline**, so the file's bytes are the serialization and
`sha256(file)` is the artifact's content id without a second convention about
framing. `harness-pack/ADR-019` OR-3, which OR-6's last paragraph made the
closure conditional on, is answered **yes** in that document. [verified]

**The fixture, and what it had to show before it was allowed to agree with
itself.** `tests/bypass_att_canon_reorder_fixture.sh` is registered in
`tests/run_tests.sh` under `ADR-017` D2, declared **GREEN** by its own header
(`ADR-017` D6). Hashing the same bytes twice agrees trivially, so the row is
carried by two controls rather than by the agreement:

- **the reordering is real** — the reordered object serialized naively differs,
  byte for byte, from the emitted file (539 bytes against 516). If it did not,
  nothing was reordered and the agreement would be tautological;
- **the form is load-bearing** — the same reordered object in the receipt's own
  form (`indent=1`, unsorted, the form `scripts/write_receipt.py:163` uses and
  which D1 explicitly exempts) yields a **different** content id at 607 bytes.
  This is `DETERMINISM.md:24-26`'s measured formatting delta reproduced on the
  new artifact rather than cited from the exempt one.

With both controls holding, the reordered object re-serialized in D1's form
reproduced the emitted file's content id exactly. [verified]

**What this amendment does NOT do.** It does not migrate any chain and does not
touch `scripts/receipt_chain.py`: `bypass_att_alg_unpinned` and
`bypass_chain_form_migration` remain **RED**, as the register declares, and D4's
next-genesis rule is untouched. It does not close OR-1, and this text calls the
adopted form what D1 calls it and by no other name. OR-2 through OR-5 are
unaffected. The tracked sample `examples/receipt-chain.sample.jsonl` and the
existing receipt are exempt under D1 and D4 and were neither read as findings nor
written.

**One consequence worth stating rather than leaving to be noticed.** This
repository now holds **two** digest-carrying artifact families, not one. The
Context section's argument for reconciling the two tagged-digest conventions
"before the first artifact exists" has spent its window: the side-car is that
first artifact, and it was born in D2's `DigestSet` spelling —
`{"sha256": "<hex>"}` in `subject[0].digest`, which is also `statement.md:15`'s
own shape. D3's supersession of `harnesswright/ADR-0008` D5 `:111` therefore now
has an artifact behind it rather than only a decision, and **OR-2 — the
`harnesswright` amendment — is unchanged and still owed**. Until it lands, the
two documents disagree on disk while an artifact exists that follows this one.
[verified]

### Provenance of this amendment

Written at `harness-pack` `HEAD` `076b219bc446d478adf712dacc9836491623f8ce`,
against `harness-pack/ADR-019` git blob
`13064f802801addcb40b203e2b76608ebe1612db` — the text ratified in the same arc.
Every measurement quoted above is the fixture's own output on this basis, read
from the run and not from the fixture's source.
