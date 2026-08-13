# Attestation S1/S2 — manifest of the measurement corpus four ADRs cite

## What this is

A manifest, not a corpus. This directory carries the path, sha256 and byte
length of every file the S1/S2 measurement corpus holds — nine measurement
documents produced on 2026-08-13, five external specifications pinned by digest,
and the eighteen shell procedures that produced them — and it carries none of
their bytes.

Nothing here is a decision. The files this manifest measures are themselves
measurements; the ADRs listed below decide, and each of them cites the corpus in
its Basis **by digest**, declaring that it does not re-derive any of it.

## Why the digests are here and the bytes are not

The measurement documents record absolute home paths and the names of private
repositories, because that is what they measured: `N3-PUBLISH.md` exists to
census receipts across repositories *by path*, and a sanitized census measures
something else. This repository is destined to be public and carries a privacy
lint in `.verity/claims.json` built to keep exactly that material out of tracked
files.

The two facts collide and neither yields. Measured over the thirty-two files
while they were still on disk here, before any of them was staged, four of the
six privacy claims went red:

| claim | files affected | hits |
|---|---|---|
| `privacy-lint-user-paths` | 21 | 69 |
| `privacy-lint-worker-repo-names` | 15 | 44 |
| `privacy-lint-vault-name` | 7 | 9 |
| `privacy-lint-operator-uid-bare` | 4 | 6 |

`privacy-lint-operator-uid-phrase` and `privacy-lint-model-id` were clean. Eight
of the thirty-two files tripped nothing; the other twenty-four tripped at least
one.

Rewriting the files so the lint passes would falsify the measurement the ADRs
cite. Exempting `.verity/evidence/` from the lint would be a privacy rule with a
carve-out for the one directory holding the private material. So the split was
taken instead: **the digest travels and the bytes do not.** A sha256 identifies
the bytes it names wherever those bytes are held, and that property is what
makes the split cost the citations nothing.

## Where the bytes are

In the operator's private governance vault, in a frozen evidence bundle holding
the same thirty-two files under the same names, with the same `spec/`
subdirectory. That bundle's README points back here for the digests and states,
as this file does, that one manifest in one location is the point — a second
copy would be a second source of truth.

The vault is not named here, and that omission is the rule this manifest
documents rather than an accident of drafting.

## Provenance — the whole chain, not the last link

Three moves, and this record is only evidence if it carries all three.

1. **Produced under a temporary directory.** The bytes were written under
   `${TMPDIR}/attest-s1/`, with one specification under `${TMPDIR}/attest-s2/`.
   On this platform that location is swept, so an ADR whose Basis cited it was
   an ADR whose evidence base had an expiry. An Accepted ADR is immutable; a
   Basis pointing at volatile evidence therefore had to be repaired **before**
   acceptance attached to it, not after.
2. **Made durable here**, at `.verity/evidence/2026-08-13-attestation-s1/` in
   this repository, copied unmodified. Each of the fourteen digests the ADRs pin
   was recomputed after that copy and compared against the value cited, and all
   fourteen matched. The copy changed the path and nothing else.
3. **Moved into the private vault by the operator.** Its destination there is
   human-write exclusive under the vault's own policy — a standing rule, not a
   permission that happened not to be granted — so the agent holding the corpus
   could not place it there and declined to try. The move is the operator's act;
   this manifest is what stayed behind.

The provenance is itself evidence, so it is stated rather than assumed: **these
bytes were produced under a temporary directory, made durable in this
repository, and then moved by hand into a location this repository cannot
write.**

## Re-verification performed in this commit

Every one of the thirty-two files was re-hashed at its new location and compared
against the three tables below — not only the fourteen the ADRs pin, but every
row.

**Thirty-two rows, thirty-two matches on both sha256 and byte length, no
divergence.** The set of files at the new location is exactly the set of rows in
these tables: no row without a file, no file without a row.

## Who cites it

| Document | Cites | Its Basis points at |
|---|---|---|
| `harness-pack/ADR-018` — algorithm as data | all nine documents; `digest_set.md`, `statement.md`, `resource_descriptor.md` | this manifest |
| `harness-pack/ADR-019` — the subject is the transcript | all nine documents; `svr.md`, `link.md`, `statement.md`, `resource_descriptor.md`, `digest_set.md` | this manifest |
| `harness-pack/ADR-020` — the publishable artifact is the Statement | seven of the nine (not `DETERMINISM.md`, not `CRYPTO-READINESS.md`); `svr.md`, `link.md`, `statement.md`, `resource_descriptor.md` | `${TMPDIR}` — open |
| `verity/0002` — structured evidence: the digest exists | `N3-PUBLISH.md`, `N4-VERITY.md` | `${TMPDIR}` — open |

`harness-pack/ADR-018` and `harness-pack/ADR-019` carry a Basis repointed at
this manifest; their digests are unchanged, because the bytes are.
`harness-pack/ADR-020` and `verity/0002` still cite the temporary path and are
an open requirement, recorded in `harness-pack/ADR-018`'s Basis so the next
session does not have to rediscover it.

## Contents

### Measurement documents

The nine the ADRs name.

| path | sha256 | bytes |
|---|---|---|
| `INDEX.md` | `1c39dd3b0ff5ee081b9e3cfe257b016ced75fa63fb91f55d61745dccffc7cf10` | 4824 |
| `GAP.md` | `0dc4c148cfd35e6a83757d1b5fff0ca63c2ec2d6bd311d4d2664c5d52ccd090f` | 11142 |
| `DETERMINISM.md` | `616cb3ceb5c916a4540607b971c49cfbff1d54e12f077a3047e5dfbcd20ef539` | 8163 |
| `CRYPTO-READINESS.md` | `e3abdf886361e9b438e5067fd25df935c931c21a7aefe11c95f5e803a3c694a6` | 8769 |
| `CORPUS.md` | `49ab237db64786f3cd92e343ab18ab320226fd50d33f9a93e6a8553997302654` | 9750 |
| `N1-SUBJECT.md` | `ee628ca4ea17e58d82eff7c012a974934e1e13d3b622a65701addc4ac7a7cccc` | 9940 |
| `N2-CHAIN.md` | `158095f6424589cbea12b3b1217f9667fdf825fc9f1f27a8dd6dcd16423933ea` | 9258 |
| `N3-PUBLISH.md` | `e7d7a33e4b307c1c99fabad1db22e83aae06cf5692bbd6fef79e795d9645e66e` | 10407 |
| `N4-VERITY.md` | `0030cbaadfed71a5f05eabe39c6a40a12a9922205b35584265e5216ea7cbfeaa` | 8831 |

### External specifications, byte-verbatim

Pinned by digest because a URI is not a citation: `harness-pack/ADR-019` D4
records the same URI serving two different versions. Source URIs below are the
paths under `in-toto/attestation` `main` from which each file was fetched on
2026-08-13; the digest, not the URI, is what the ADRs cite.

| path | source path in `in-toto/attestation` | sha256 | bytes |
|---|---|---|---|
| `spec/statement.md` | `spec/v1/statement.md` | `cbe684a18b812b8b613d9202eb43b2ea24477f91a2ad6ca5be935185a455ebea` | 2492 |
| `spec/resource_descriptor.md` | `spec/v1/resource_descriptor.md` | `bee71bedd6a957771233cbbe6494144157b865992e53cc91d607a8e02a34c58a` | 5912 |
| `spec/digest_set.md` | `spec/v1/digest_set.md` | `0b1889fdea7f6d623b41555632aedf04ee4398cf02a32002060608c75ebb038e` | 8873 |
| `spec/svr.md` | `spec/predicates/svr.md` | `60d47f833f7998926aa991d1aa6ab9ef9a2a916771a99232b624ea0c45c9da1a` | 7540 |
| `spec/link.md` | `spec/predicates/link.md` | `23703e071424e2468382a90355493cdc2c0defe8b97250a93db2be24c14cfbb0` | 4917 |

`spec/digest_set.md` is the one file that came from `${TMPDIR}/attest-s2/`
rather than from the S1 directory; it was fetched later, by `digestset_fetch.sh`,
and its digest matches the value `ADR-018` and `ADR-019` pin exactly.

### Procedures

The shell that produced the documents and fetched the specifications. No ADR
pins these; their digests are recorded here so the corpus can be re-derived and
compared rather than trusted.

| path | sha256 | bytes |
|---|---|---|
| `measure.sh` | `d36aa149809e2a7855519640f23bc7aff0b0a14f0679035b040c201b8214089b` | 6795 |
| `project.sh` | `0943cd4ff49de15319ca7bac1ac2572d90e149b35ad494332706da4ad4ddaefb` | 5975 |
| `corpus.sh` | `5f73b999bf8c0f92436a4e40833f7f254c3762e7fddadd6cd86db10e4dff5d21` | 1937 |
| `crypto.sh` | `d3662bea08af5b5101a83c544eec8b38e4e6901ce40e9313ddc4a9080dd82976` | 2021 |
| `fetch_verbatim.sh` | `765ed327f3d61a9d8f907a2bf6a896354d4d22b212b3b6e93a8bf7aafff6f84f` | 2612 |
| `digestset_fetch.sh` | `769409c9751940c3407f82a21f69ca26beb6496ec6d78ea08b7996174ef1ceec` | 389 |
| `receipt.sh` | `2308ec35deb31b284477a5cd8929a39a0dc4cdb969d0e09156f9c780acb09c32` | 2224 |
| `receipt2.sh` | `9c5b27f75d53718435fa9efe07eb1407c48f9456eb192ebb0e708ac9bf878d28` | 2584 |
| `n1.sh` | `14f337b0889e25fca56ae797848c0c104612a54fad57f82a02841362d3420182` | 1018 |
| `n1b.sh` | `039fec612b3b2c1df2fa4b1978c1fa992e6f59ed34d985e4c3bda3ac420124ec` | 1564 |
| `n2.sh` | `f83ab3a39edf20185eedb5669dba8319a100fd21ef7c694a20f3f5e122cd46bc` | 1877 |
| `n2b.sh` | `9ed82338215665057bae3a4ec768433cba7933b9e1fd49788e0ed8846c50144f` | 897 |
| `n2c.sh` | `fa155ea589198ce2d297a2772df8977e4ff974e090d6d441f48084e5a6873218` | 1446 |
| `n2d.sh` | `e25f494a3fbc6a40b0478ecf12f44c97e2512e8d34553b61299cf9a9cffec87d` | 1477 |
| `n3.sh` | `52bb8460543bfbde2e4220a2d60659bf696ab979e1f402f406566c07330ce45f` | 2480 |
| `n3b.sh` | `c54e7c435364080a27fc27bf9a806c2f104fd2008cf8beb720bcdb145dbb8a83` | 2403 |
| `n3c.sh` | `73538e985c1583c077702ec7148906dbe66c4673473881043ff28c0bd75b5800` | 1734 |
| `n4b.sh` | `c76d589b8f933921bf1171282f1cc190d7cb5099a00e3cf0309342e207be4906` | 1312 |

## What was deliberately left behind

The source directory held more than these thirty-two files. A corpus that copies
everything that happened to be in a directory is not evidence, it is a backup,
so the following were not brought across: the three candidate Statement
projections (`link-v0.3.json`, `test-result-v0.1.json`, `scai-v0.3.json`), the
raw GitHub API response behind one of the normative excerpts, the receipt census
listing, the re-serialized basis object, and the S1 abort note. None of them is
cited by any ADR, and each is an intermediate whose conclusion already lives in
one of the nine documents above.

Three further byte-verbatim files were also left behind for the same reason —
the fetch-provenance table, an issue-body excerpt, and a duplicate copy of
`spec/svr.md`. The provenance table's content that this corpus needs, the source
path for each specification, is reproduced in the specification table above.

Four specification files the S1 fetch retrieved are absent because no ADR pins
them: two in-toto predicate specs and the two `README.md` files of the
`spec/v1/` and `spec/predicates/` directories.

## What this directory does not settle

It does not make the corpus reachable from a clone of this repository. A reader
who wants the bytes has to be given them; what a reader gets here is the ability
to check, byte for byte, that whatever they are given is what the ADRs cited.
That is a smaller guarantee than shipping the corpus and a larger one than
trusting a description of it, and choosing it was a decision rather than a
default.
