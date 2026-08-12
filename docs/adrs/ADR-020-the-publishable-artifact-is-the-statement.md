---
type: adr
status: proposed
title: "The publishable artifact is the Statement: an allowlist, and a claim that presides over what is emitted"
id: ADR-020
date: 2026-08-13
related-adrs: [harness-pack/ADR-004, harness-pack/ADR-005, harness-pack/ADR-006, harness-pack/ADR-008, harness-pack/ADR-009, harness-pack/ADR-010, harness-pack/ADR-017, harness-pack/ADR-018, harness-pack/ADR-019, harnesswright/ADR-0008, vault/ADR-051, vault/ADR-080]
---

# ADR-020 — The Publishable Artifact Is the Statement

## Status

Proposed

**This ADR decides; no code is written against it while it is Proposed.** No
writer, no claim, no fixture and no documentation edit ships with this commit,
on the rule `harness-pack/ADR-006:56` states — "No code is written against this
ADR while it is Proposed" — and which `harness-pack/ADR-009:23` applies
generally. D1 identifies a false sentence in `docs/OPERATOR-GUIDE.md` and does
**not** correct it here: the correction is an edit to an existing file and
belongs to this ADR's implementation, not to its proposal. [verified]

## Numbering note

020 is taken by sweep, not by increment. It is the successor of the number
`harness-pack/ADR-019` takes. 012, 014, 015 and 016 remain reserved by intent
for the remaining rows of the six-gap arc, per `ADR-017`'s numbering note at
`:18-22`; this document is not a gap row and does not take one of them.
[verified]

**The sweep, and what it measured.** `git grep -nF 'ADR-020'` over this
repository returned **zero hits** at this basis, and `ls docs/adrs/ADR-020*`
matched nothing. Over the vault at its `HEAD`, the same bare token returns
**many** hits — `vault/ADR-020` is an Accepted supply-chain policy, and
`reps/ADR-020` is a live Proposed ADR in another sequence. The namespace-
qualified sweep is the one that governs: `git grep -nF 'harness-pack/ADR-020'`
over the vault returns **zero hits**, and the highest `harness-pack/ADR-NNN`
token the vault carries is `harness-pack/ADR-013`. [verified]

This is not a workaround for an inconvenient result; it is the mechanism
`vault/ADR-051` D3 fixes — "Counters remain independent per namespace and no
existing ADR is renamed or renumbered" — with `harness-pack/ADR-NNN` a
registered active prefix in that ADR's D1 registry. It is also the mechanism
this repository already used one commit ago: `harness-pack/ADR-019`'s own
numbering note records a namespace-qualified vault sweep, and both
`vault/ADR-018` and `vault/ADR-019` exist on disk while
`harness-pack/ADR-018` and `harness-pack/ADR-019` were committed regardless.
A bare-token vault sweep would have blocked those two as well. [verified]

## Publication note

This repository is destined to be public, and its own claims layer presides over
the boundary. `privacy-lint-worker-repo-names` in `.verity/claims.json` excludes
`docs/adrs/` from its `git grep`, so naming a private worker repository in an ADR
is **permitted by the lint**. This document nonetheless does not name one.

Where a worker repository appears below it is written as "a worker repository in
the family", because the repository's identity adds nothing to any decision here
— D5 is about a *class* of hazard, not about one repository. The measured
evidence is cited by JSON path and by count, never by receipt filename, for the
same reason: the falsifier D3 names needs the JSON paths, and needs nothing else.
The one place a repository name would be load-bearing is the hygiene fix D5
declines to make, and that fix is a separate commit in another repository, not
part of this document. This is a stated choice, not an omission. [verified]

## Basis

Every line number in this document is read against the bases below and is
**pinned here rather than maintained**. A later commit may move any of them; this
document does not track them.

**Repository heads.**

| Repo | Branch | HEAD |
|---|---|---|
| `harness-pack` | `main` | `240f8cf9b4602e205c30f313987282cea1eb62bf` |
| `verity` | `main` | `4dc016b354f3a6eb953590167b46bc29eacf3fcb` |
| `harnesswright` | `main` | `edb12a499615bf12aa80e5db1c67a268cb247114` |
| vault | `main` | `749b467497ac7dea62d101cdda4075b0c75dae2d` |

Citations into `harness-pack` are read against the committed blob
(`git show HEAD:<path>`), never the working tree, which is dirty at this basis.
Citations into `verity` and the vault are read against the pinned commits above.

**Measurement documents**, under `${TMPDIR}/attest-s1/`. Cited, **not
re-derived**; no census below was re-run for this document.

| Document | sha256 |
|---|---|
| `INDEX.md` | `1c39dd3b0ff5ee081b9e3cfe257b016ced75fa63fb91f55d61745dccffc7cf10` |
| `GAP.md` | `0dc4c148cfd35e6a83757d1b5fff0ca63c2ec2d6bd311d4d2664c5d52ccd090f` |
| `CORPUS.md` | `49ab237db64786f3cd92e343ab18ab320226fd50d33f9a93e6a8553997302654` |
| `N1-SUBJECT.md` | `ee628ca4ea17e58d82eff7c012a974934e1e13d3b622a65701addc4ac7a7cccc` |
| `N2-CHAIN.md` | `158095f6424589cbea12b3b1217f9667fdf825fc9f1f27a8dd6dcd16423933ea` |
| `N3-PUBLISH.md` | `e7d7a33e4b307c1c99fabad1db22e83aae06cf5692bbd6fef79e795d9645e66e` |
| `N4-VERITY.md` | `0030cbaadfed71a5f05eabe39c6a40a12a9922205b35584265e5216ea7cbfeaa` |

`N3-PUBLISH.md` is the load-bearing one for D1, D3 and D5. `N4-VERITY.md` is the
load-bearing one for D4's cost argument and for the coupling named in
Consequences.

**External specifications**, pinned by digest. `harness-pack/ADR-019` D4 records
at length why a URI is not a citation; that argument is adopted here rather than
restated.

| Spec | Type URI as read | sha256 | bytes |
|---|---|---|---|
| Simple Verification Result | `https://in-toto.io/attestation/svr/v0.2` | `60d47f833f7998926aa991d1aa6ab9ef9a2a916771a99232b624ea0c45c9da1a` | 7540 |
| Link | `https://in-toto.io/attestation/link/v0.3` | `23703e071424e2468382a90355493cdc2c0defe8b97250a93db2be24c14cfbb0` | 4917 |
| Statement v1 | `https://in-toto.io/Statement/v1` | `cbe684a18b812b8b613d9202eb43b2ea24477f91a2ad6ca5be935185a455ebea` | — |
| ResourceDescriptor | — | `bee71bedd6a957771233cbbe6494144157b865992e53cc91d607a8e02a34c58a` | — |

**Assertion labels.** `[verified]` — established by an artifact cited here and
re-readable by a third party. `[inferred]` — follows from cited artifacts by an
argument stated at the point of use. `[assumed]` — neither; carried in the
Assumption ledger with its falsifier. An unlabelled assertion is a defect in this
document. They map onto `harness-pack/ADR-008` D6's tiers: `[verified]` is tier A
and citable as a finding; `[inferred]` and `[assumed]` are tier B and citable
**only** as open requirements. [verified]

## Context

`harness-pack/ADR-019` D1 chose the transcript as `subject[0]` and closed the
family's central measured defect — `subject[0].digest` ASSENTE in all three
projections (`GAP.md:207`). It left a boundary question open by name in its D6:
the Statement carries no prose, "the full rationale belongs to **ADR-C**, the
claims-layer ADR, and is deferred to it rather than half-argued here". This is
that ADR, and the rationale is D2 and D3 below. [verified]

It also left `verifier.policies` under-determined as **OR-1**, because SVR v0.2
requires a field that `harness-pack/ADR-019` D3's material/annotation assignment
had nowhere to put. That is D4. [verified]

The reason all of this is urgent rather than tidy is a single measured fact:
**the artifact the operator guide says is safe to publish is not.**

## Decision

### D1 — The receipt is not publishable, and the documentation says otherwise

`docs/OPERATOR-GUIDE.md:134`, read from the committed blob, verbatim:

> Run the HALT drill on a schedule you will actually keep. Keep the rollup
> current, so the committed chain stays close to the loose receipts. And keep
> secret scanning in front of anything public: **receipts are designed to be safe
> to publish, transcripts are not.**

Measured against the corpus, the emphasised clause is **false as written**.
[verified]

**The measurement.** `N3-PUBLISH.md` censused every `*.receipt.json` on disk
across the family — **49 files, 0 unreadable**. **2 of 49 carry the operator's
home directory.** Aggregated by JSON path, with array indices collapsed:

| JSON path | receipts |
|---|---|
| `.contribution.baseline.claims[*].evidence` | 2 |
| `.refusals.denials[*].tool_input.file_path` | 1 |

[verified] (`N3-PUBLISH.md`, section (a))

**The mechanism, and why it is worse than a leak.** The path arrives from
`verity`'s `file_exists` **FAIL** branch. At `verity` `src/checks.ts:62`,
`const abs = resolve(ctx.cwd, claim.path)` — absolute by construction — and at
`:75`, `` evidence: `does not exist at ${abs}` ``. The PASS branch at `:96` emits
`` `exists, ${stat.size} bytes` `` and carries no path at all. `N3-PUBLISH.md`
measured both verdicts of the *same claim* in the *same receipt*: the t0 baseline
FAIL evidence is 67 bytes and carries the home directory; the t1 PASS evidence is
16 bytes and does not. [verified]

So a receipt discloses the operator's absolute home path **if and only if** a
`file_exists` claim was FAILing at t0. And `scripts/launch_worker.sh:335-336`
declares exactly that state to be normal and healthy, verbatim:

> a t0 in which every criterion reads FAIL or ABSENT is the
> healthy normal case and must never stop a run

[verified]

**The leak is therefore correlated with the run being useful.** A run that
contributes something is a run whose baseline failed, and its receipt carries the
path. This is not a rare edge; it is the modal case, and a sanitiser tuned on the
rare case would be tuned on the wrong distribution. [verified]

**Three carrier classes, read from `scripts/write_receipt.py` and not from the
data.** The distinction matters: a census tells you what has leaked, the writer
tells you what *can*.

1. **`refusals.denials`** — `:124`, `denials = cc.get("permission_denials") or []`,
   placed at `:129` inside `refusals`. The array is copied **verbatim and
   unmodified**; the file's own comment at `:98` says so — "`denials` is the array
   as received and unmodified". No depth bound, no length bound, no key
   allowlist. For a refused `Write` it preserves the entire attempted `content`.
   This is the primary arbitrary-input carrier and it is **deliberate**:
   `harness-pack/ADR-010` D1 is the decision that put it there. [verified]
2. **`subtype` and `session_id`** — `:137` and `:141`, unbounded scalars taken
   straight from the child's `cc.json`. [verified]
3. **`claims[*].evidence`, `contribution.baseline.claims[*].evidence`,
   `gate.reason`** — strings from `verity` passed through with no inspection.
   `scripts/launch_worker.sh:303` is the passthrough,
   `items.append({… "evidence": r.get("evidence")})`; `:301` is its sibling
   branch and emits a launcher-authored constant for an absent criterion, so it
   is *not* a carrier; `reason` is assembled at `:307`, `:309` and `:311` and
   emitted at `:312`. This is class (3), and it is the class that actually
   leaked. [verified]

Class (3) has a second and sharper edge. For `type: command` claims, `verity`
embeds matched stdout in its evidence — `src/checks.ts:241`,
`` if (stdoutOutcome) parts.push(`stdout: ${stdoutOutcome.evidence}`) `` — so a
claim whose command prints a secret puts that secret into the receipt **by
construction**, with no defect anywhere in the chain. [verified]

**The decision.** The sentence at `docs/OPERATOR-GUIDE.md:134` is corrected **at
acceptance**, not here, and its replacement names the Statement rather than the
receipt as the publishable artifact. What this document decides now is that the
sentence is false and that the receipt is not the thing to fix.

The design *intent* the sentence records — receipt safe, transcript unsafe — is
right, and `harness-pack/ADR-019` D1 turns on it. What is absent is any
enforcement: no sanitising code path, no claim that can see the artifact, and two
counterexamples on disk. "Designed to be safe" with no mechanism is an intention,
and an intention is not a property. [verified]

### D2 — The Statement is the publishable artifact, by allowlist

The side-car Statement of `harness-pack/ADR-019` D5 carries **only**:

- `DigestSet` objects, in `harness-pack/ADR-018` D2's spelling —
  `{"<algorithm-name>": "<hex>"}`, algorithm as data, never as a field name;
- values drawn from a **closed enum**, namely the `HARNESS_`-prefixed vocabulary
  coined and closed at `harness-pack/ADR-019` D4;
- ids;
- timestamps in RFC 3339;
- URIs.

Nothing else. **The rule is an allowlist. It is never a denylist.**

**This, and not the field list, is the decision.** A denylist over arbitrary
input is a war that cannot be won. The child chooses what appears in
`tool_input`; `write_receipt.py:98` records that the writer's contract is
explicitly *not* to sanitise; and every pattern a denylist adds is a patch
written after the fact, against the last leak rather than the next one. The
distribution argument in D1 makes this concrete: the leak that has actually
occurred is the *healthy* case, so the patterns a reasonable author would have
guessed at are the wrong ones.

An allowlist over a closed vocabulary of six properties cannot be lost in the
same way. Its failure mode is a Statement that is missing something, which is
visible and inert; a denylist's failure mode is a Statement that carries
something, which is invisible and permanent once published. [inferred] — from
the carrier analysis in D1 and from `svr.md:105`'s passing-only rule, by the
argument stated here.

**The explicit consequence, stated so it cannot be walked back: no field of the
Statement is ever populated by a string that the child or `verity` produced.**
Not `evidence`, not `reason`, not `subtype`, not `session_id`, not any member of
`denials`. Where a Statement needs to say that something was verified, it says so
with a closed-vocabulary property, never by quoting the verifier.

This is the same boundary `harness-pack/ADR-019` D6 drew and deferred; D2 is the
rationale that D6 said belonged here.

### D3 — The boundary is presided over by a claim, not by care

A `verity` claim over emitted Statements, which **FAILs** on any of:

- any occurrence of the literal token `/Users/`;
- any absolute path, by shape, whatever its prefix;
- any string outside D2's allowlist.

**Why this is a decision and not a chore.** The existing guard cannot see the
artifact. `privacy-lint-user-paths` in `.verity/claims.json` is `type: command`
and its `run` is, verbatim:

```
! git grep -qF '/Users/' -- ':!docs/adrs/' ':!*.example.json' ':!workers.local.json' ':!.verity/claims.json'
```

`git grep` sees **tracked files only**. `N3-PUBLISH.md` measured the receipt
posture across four repositories in the family: receipts are gitignored in three
of them and simply untracked in the fourth. In this repository the rules are
`.gitignore:1` (`.harness/`) and `.gitignore:7` (`receipts/`). The five
`*.receipt.json` files this repository does track are the ADR-008 fixtures under
`tests/fixtures/adr008/`, and none carries the token. [verified]

So the claim is **green for the wrong reason**: it passes because five fixtures
were authored clean, not because any mechanism prevents a leaking receipt from
reaching a tracked path. That is the vacuous-detector shape
`harness-pack/ADR-017` exists to name. [verified]

The new claim must therefore preside over **the emitted artifact**, not over the
tree. A side-car Statement is a new artifact deriving from an untracked receipt;
it inherits nothing from the current lint, and the two JSON paths the census
named — `.contribution.baseline.claims[*].evidence` and
`.refusals.denials[*].tool_input.*` — are precisely what it must be able to
refuse. [verified]

The claim's own exclusion list is the shape of the future problem: it already
excludes `docs/adrs/`, `*.example.json`, `workers.local.json` and itself. Each
exclusion is defensible individually and each one narrows what the guard can
see. A guard that must be excluded from the places prose lives is a guard that
cannot be the boundary for an artifact made of prose — which is the second
argument for D2's allowlist.

### D4 — `verifier.policies` is the verifier's policy, not the doer's

This closes **OR-1** of `harness-pack/ADR-019`.

`svr.md:92` declares the field required, and `:95-97` says what it holds,
verbatim:

> Identifies the policy artifacts used by the verifier when producing this
> result. Producers MUST include this field even when no policy can be
> referenced; in that case, the value MUST be an empty array.

[verified]

**The verifier is the gate.** In this harness that is `verity` plus the filter
over `spec.criteria` implemented in `measure_criteria`
(`scripts/launch_worker.sh:271-315`). Its policy artifact is the thing that
declares what gets checked.

**The constitution is not a policy artifact of the verifier.** `CONSTITUTION.md`
governs the **child** — the subject being judged — not the judge. Putting it in
`verifier.policies` would assert that the harness verified the run against the
constitution, which is precisely the thing the harness does *not* do: the gate
reads `verity`'s verdicts, and no gate anywhere reads the constitution's text.
Collapsing doer-policy into verifier-policy destroys the distinction the entire
harness is built on, and it does so in a machine-readable field that a consumer
would have no way to second-guess. This is the same failure class as
`harness-pack/ADR-019` D2's rejected `HEAD` subject: well-formed, readable, and
untrue. [verified]

**The decision.** `verifier.policies` carries the `ResourceDescriptor` of the
**claims manifest of the target repository** — `.verity/claims.json`, the path
`verity` `src/verify.ts:9` fixes as `DEFAULT_MANIFEST_PATH`. Its `digest` is the
sha256 of that file's bytes, computed **at the moment of the gate**, so that the
Statement records the policy that was actually in force rather than the one on
disk when a reader looks. `resource_descriptor.md:26-27` is satisfied by `digest`
alone — "a ResourceDescriptor MUST specify one of `uri`, `digest` or `content` at
a minimum" — so no path need appear, which is also what D2 requires. [verified]

The constitution goes to `link/v0.3` `materials`, which is where
`harness-pack/ADR-019` D3 had already sent it and where SVR has no slot:
`link.md:79`, "`materials`, _list of [ResourceDescriptor] objects, optional_".
`harness-pack/ADR-019` D4 already names `link/v0.3` as the optional companion.
[verified]

**Cost, named and not paid here.** One `shasum`, on the same model as the first:
`harness-pack/ADR-019` OR-6 named a single `shasum` line between
`launch_worker.sh:371` and `:409` as D1's whole cost, and this is the second such
line. It is **OR-1** below and is not implemented by this document.

**If the claims manifest is not reachable at gate time**, nothing is invented.
The fact is recorded and `verifier.policies` is left `[]`, which `svr.md:74-76`
makes the minimal conformant form: "The `verifier.policies` field MUST be
present. If no explicit policies were used, or the verifier cannot reference the
policies, producers MUST encode this as an empty array". A recorded `[]` with a
written reason is honest; a fabricated descriptor is not. [verified]

### D5 — Receipts do not become tracked

Named here and **not resolved here**.

A worker repository in the family has **no ignore rule for its own receipts
directory**. Its receipts are therefore untracked but **stageable** — one
`git add` from being committed — and it is the same repository that holds both
leaking receipts from D1's census. That repository does not run this
repository's `claims.json`, so nothing in its own commit path would refuse them.
[verified] (`N3-PUBLISH.md`, section (d))

This is a one-line `.gitignore` fix in another repository. It is **not** this
ADR's job to make, it is not implementation of any decision above, and it does
not wait on this ADR's acceptance — the hazard is live now and the fix is inert.
It is carried as **OR-2**, and a separate commit in that repository performs it.

Naming it here rather than fixing it here is the point: `harness-pack/ADR-017` is
about obligations that no one reads, and an ADR that quietly absorbed a
cross-repository fix into its own diff would be committing the inverse defect.

## Verification

Named here, authored at acceptance, to `vault/ADR-073` D1's standard — "A gate
observed only passing is untested and carries no evidentiary weight". Each
falsifier below declares whether its RED has been **observed** or is a
**prediction**; conflating the two is the defect `harness-pack/ADR-017` names.

**D1 and D3 — `bypass_receipt_host_path_published`.** A receipt containing the
literal token `/Users/` must be **refused by the publication boundary**.

**RED already observed**, not predicted. `N3-PUBLISH.md` measured **2 of 49**
receipts carrying the token, at these two JSON paths:
`.contribution.baseline.claims[*].evidence` (2 receipts) and
`.refusals.denials[*].tool_input.file_path` (1 receipt). The mechanism is
`verity` `src/checks.ts:75` and the state that triggers it is the one
`scripts/launch_worker.sh:335-336` calls healthy. The fixture's job is to hold
that RED inside the suite instead of inside a measurement document that nothing
executes. [verified]

**D2 — `bypass_att_prose_leak`.** A Statement carrying any field outside D2's
allowlist — a `verity` `evidence` string, a `gate.reason`, a `denials` member, a
`subtype`, a `session_id` — must be **rejected**.

**Not yet observed, and declared as such.** No Statement has ever been emitted,
so there is no measured RED behind this one. It is a prediction until the fixture
runs, and it must be written so that it fails against the *lenient* implementation
— the one that copies a field through because the field happened to be in hand.

**D4 — a `verifier.policies` fixture.** A fixture asserting that
`verifier.policies` **never** contains the digest of `CONSTITUTION.md`.

**Not yet observed, and declared as such.** Its value is that it fails on the
*attractive* implementation: `constitution_hash` is the only digest-shaped value
already in the receipt (`scripts/write_receipt.py:135`), it is already pinned
fail-closed at `scripts/launch_checks.py:61-64`, and it is therefore the value a
producer reaches for when SVR v0.2 demands a `ResourceDescriptor` and none is at
hand. The fixture exists to refuse that reach. [inferred] that it is the likely
reach, from the fact that the constitution's digest is present and the manifest's
is not — the same argument `harness-pack/ADR-019` D2's fixture makes about
`HEAD`.

**D5 — no fixture named here.** The hazard is in another repository, outside this
repository's suite, and its fix is a `.gitignore` line whose falsifier is
`git check-ignore`. Naming a fixture in this suite against an artifact this suite
cannot reach is the defect `harness-pack/ADR-017` is about. It is OR-2.

## Non-goals

- **It writes no code**, no claim, no fixture and no schema.
- **It does not edit `docs/OPERATOR-GUIDE.md`.** D1 declares the sentence false
  and defers the correction to implementation.
- **It does not modify the receipt** — not its fields, not its serialization, not
  one byte. The receipt stays exactly as unpublishable as it is; the response is
  a different artifact, not a sanitised receipt.
- **It does not sanitise anything.** There is no filter, no redactor, no pattern
  list. D2 is an allowlist over what is *constructed*, which is a different
  mechanism from removing things from what was *received*.
- **It signs nothing** and anchors nothing to a transparency log.
- **It does not touch `verity`.** The tool is read; `verity/ADR-002` is where
  `verity` decides anything.
- **It does not fix the worker repository.** D5 names the hazard; a separate
  commit in that repository performs the one-line fix.

## Open requirements

- **OR-1 — the second `shasum`.** D4 requires the sha256 of
  `.verity/claims.json`'s bytes at gate time. That line does not exist. It is
  implementation, on the same model as `harness-pack/ADR-019` OR-6, and is not
  written here.
- **OR-2 — the worker repository's ignore rule.** D5's one-line `.gitignore`
  fix, in another repository, as a separate commit. Falsified by
  `git check-ignore` against that repository's receipts directory.
- **OR-3 — `verity` is absent from `vault/ADR-051` D1's prefix registry.**
  That registry lists `vault/`, `reps/`, `harnesswright/`, `harness-pack/`,
  `reps-coach/` and a reserved `webapp/`. `vault/ADR-080`'s own namespace table
  lists a live `verity/` namespace at `~/Code/verity/docs/adrs/`, so this
  document's `verity/ADR-002` citations use a prefix that is in use and
  unregistered. `vault/ADR-051` D1 prescribes its own amendment mechanism for
  this, and `vault/ADR-080` OR-3 already applies it to a different namespace.
  Registering `verity/` is a vault-side act and is not performed here.
  [verified]
- **OR-4 — the Statement's own canonical form.** `harness-pack/ADR-018` D1 binds
  new content-addressed artifacts. Whether the side-car is content-addressed, and
  therefore whether it enters the chain, was left open as
  `harness-pack/ADR-019` OR-3 and is not closed here.
- **OR-5 — the `verifier.id` domain**, inherited unchanged from
  `harness-pack/ADR-019` OR-2. An operator decision.
- **OR-6 — at least one non-`command` claim.** See Consequences. Until one
  exists, D4's descriptor is well-formed and the Statement's `subject` digest
  comes from the transcript alone.

## Consequences

- **The publishable artifact changes identity.** Before this ADR the answer to
  "what may be published?" was a sentence in a guide with two counterexamples on
  disk. After it, the answer is an artifact with an allowlist and a claim that
  can refuse it. The receipt is not made safer; it is removed from the question.
- **`verifier.policies` stops being under-determined.** `harness-pack/ADR-019`
  OR-1 closes, and it closes in the direction that keeps judge and judged
  distinct.
- **The cost is one `shasum` and one claim.** No new dependency, no new format,
  no change to the receipt, the chain, or any chain line written to date.
- **A live hazard is named and left live, deliberately.** D5's repository still
  has stageable leaking receipts after this ADR is accepted, until OR-2 lands.
  That is a real residual and it is stated rather than implied.
- **The coupling with `verity/ADR-002` is asymmetric and is worth stating.** All
  ten claims in `.verity/claims.json` are `type: command` — `N4-VERITY.md`
  measured this, and `verity` `src/verify.ts:11` fixes the closed type set that
  makes `command` the one type with no artifact to digest. So `verity/ADR-002`'s
  structured-digest slot yields this repository **nothing** until at least one
  claim becomes `file_matches` or `git_committed`. That is OR-6, a claims-layer
  decision on this side, not a defect on `verity`'s. [verified]

## Assumption ledger

Every `[assumed]` in this document, with the observation that would falsify it.

| # | Assumption | Falsifier |
|---|---|---|
| A1 | **[assumed]** The `HARNESS_` vocabulary closed at `harness-pack/ADR-019` D4 is sufficient to express every verdict a consumer needs, so that D2's allowlist never has to be widened to a free-text field. | The first consumer requirement that cannot be met by adding a closed-vocabulary property — i.e. one that genuinely needs a string only the verifier could have written. That would reopen D2, not merely extend the enum. |
| A2 | **[assumed]** `.verity/claims.json` is readable at gate time in every deployment topology, including the enforced runtime location of `harness-pack/ADR-001`. | The first gate run in which the manifest cannot be read. D4 already declares the branch this takes: record the fact, emit `verifier.policies: []`. Falsification costs nothing because the fallback is written. |
| A3 | **[assumed]** An absolute path is detectable by shape in D3's claim without an unacceptable false-positive rate over legitimate Statement content. | A Statement that D3's claim refuses and that carries nothing outside D2's allowlist. Under D2 the risk is low — a conforming Statement contains only digests, enum values, ids, timestamps and URIs, and a URI is the only one that could resemble a path — but "low" is not "measured", and it has not been measured. |
| A4 | **[assumed]** The census's 49 receipts are representative of what receipts will contain, in the sense that the three carrier classes are exhaustive rather than merely the three that were found. | A receipt field carrying child- or verifier-authored content that is not in D1's list of three. The classes were read from `scripts/write_receipt.py`'s source rather than from the data, which is what makes this an assumption about the *writer* being fully read, not about the sample being large. Re-reading the writer at any later HEAD falsifies or confirms it directly. |
