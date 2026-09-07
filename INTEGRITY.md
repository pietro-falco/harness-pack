# INTEGRITY

The record of every declared transformation applied to a tracked blob in this
repository. A re-pinned blob digest is evidence of a declared transformation
only when it appears here, enumerated by path, against a rule file whose own
sha256 matches the one this record cites. A re-pin absent from this file is
undeclared content drift and must be treated as tampering, not as maintenance.

## Path transformation

**Rule:** `scripts/path_transform_rule_v2.json`  
**Rule sha256:** `0c73a6820a614cd6cc1e92ecf9318fad87df1e430114a44037a48389082023be`  
**Applied in merge:** `30361485ec1031ebf3596683f5e11f1dad49ec6c` (ours) x `f1e2f473983c7040a9b9ad7bfd7d3588e766b957` (theirs)

`path-transform/v2` replaces the operator home path with `<LOCAL_ROOT>` in two
encodings — the filesystem form and the dash-flattened form used by Claude Code
project-state directory names. Both patterns are stored in the rule file as JSON
`\u00XX` escapes, so the rule file is a fixed point of its own rule and does not
itself carry the substring `privacy-lint-user-paths` refuses.

### Superseded draft, never landed

`path-transform/v1` declared the filesystem form only. The remote side of this
merge carries 396 occurrences of the dash form and zero of the filesystem form,
so v1 reproduced the local blob on 0 of 40 paths. It is recorded here by digest
as a superseded draft and is not tracked in this repository.

**v1 draft sha256:** `556e0ad43aad7a06513aca9ace6243e25260f89aebc46757ce2d8ef12d3615ad` — superseded, never landed.

### Verification gates

| Gate | Question | Result |
| --- | --- | --- |
| G-A reproduction | v2 applied to the remote blob reproduces the local blob | 40/40 |
| G-A control (v1) | v1 applied to the remote blob reproduces the local blob | 0/40 |
| G-B idempotence | v2 applied twice equals v2 applied once | 40/40 |
| G-C anti-vacuity | remote blobs whose bytes v2 actually changes | 40 |

### Declared paths (40)

Each row is a path this transformation covers and the sha256 of the resulting
blob, which is the blob committed at this merge.

| # | Path | Resulting blob sha256 |
| --- | --- | --- |
| 1 | `runs/THR-SUBAGENT/20260813T194853Z/RESULT.json` | `be3d1aa8aca5a79efd586d249aab0c4affc48eeb940c47db65f88d8fb5721b50` |
| 2 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A1bg/detect.json` | `2f12d677e43396065750748fe63aba928506314f25ddeeca99563e60e0a78d00` |
| 3 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A1bg/invocation.txt` | `b0dd3a968f7cb260c8732639426b681b251b0184e7cc389e6be1acf6f74dcfa8` |
| 4 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A1bg/stream.jsonl` | `4cc85d3179f0a415416d069f85644193843da9165e48f902f4b98019c87c34ad` |
| 5 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A1fg/invocation.txt` | `e64f2589cff820d0a4520396b0758813129cf298523d833e0b4b9c2e41abe28a` |
| 6 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A1fg/stream.jsonl` | `d1c390d07b5a250622ea37d500d9bd9b4e4e33bac4ae737eaebd8a2b964032bd` |
| 7 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A2bg/detect.json` | `6779792d4092b6687973f1ddd1183e9a72957a601784bf964aaef304dabe5901` |
| 8 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A2bg/invocation.txt` | `a8cf6cc8773af7eb1ac8e39e04fbb40d2b94652856b27f1c745ee066c90aa907` |
| 9 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A2bg/stream.jsonl` | `e2cd4d4734071d61924b45e7468052968e5e57e22a190ea9aa5c6179dfeb9831` |
| 10 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A2fg/detect.json` | `576a2b6f49c0c2b333cb6bdce2bc1b3ce4293a4a745f598cac9e45ee012cba07` |
| 11 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A2fg/invocation.txt` | `aab83549ac5d580c5bc01b88adadebec656d8e134df6f42be67bfbbbc2c3a3c5` |
| 12 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A2fg/stream.jsonl` | `7e245e9bf34f382867a2bcda6f71dacc2916393b047fada7f9e12b5d2eed38e1` |
| 13 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A3/detect.json` | `7029eb3f7c44d8083f7c704f07c9093bba59e2459d4ce4263d8bfb63ce56e2cd` |
| 14 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A3/invocation.txt` | `f10e15aaee4e4c91aff1786d20be577af6b22e61ac4089f19e94085c62d8944b` |
| 15 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A3/stream.jsonl` | `afdccf2991c09cd134a2468f42715c00fb6d980f6ef5e30fd0cf9ef9dba94eaa` |
| 16 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A4-tools-empty-string/invocation.txt` | `47624d70b23c5c3733856eabd8cb812044913996b35182d00167a0d25238604a` |
| 17 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A4-tools-empty-string/stream.jsonl` | `731be7d0022785466f879e29a43780d879f6f067500920a1aecdb8961d1ecfb0` |
| 18 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A4/detect.json` | `be0e54190d13621bdffc6fc7b5c1e4a868b82bbd9d1bb8b25191e506112645ea` |
| 19 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A4/invocation.txt` | `8b068b3320691f8e76110c13741e016af2320e5054bf874c0ad7c149ee9587aa` |
| 20 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A4/stream.jsonl` | `c2ae65ba0b14912cdd7758c41df10866c4cc0cc075bfb6a6256c7c3f57fb9fe1` |
| 21 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A5/detect.json` | `1934a9d771e3c678a72e33df982f3454040e707a422d144999c21bb37b90c2cf` |
| 22 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A5/invocation.txt` | `3d3dfc17bb217df819b899c019a0440504d4d90c754ed41d2223fb8b9e632893` |
| 23 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A5/stream.jsonl` | `fc0aa806803d4240bbe38cd1a1a9e188cf76fc9d725acd1f31ba708e41538110` |
| 24 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A6/invocation.txt` | `a02cfc79203976be9c019f7f4e15020c3b318e22e2a0f36bf67aa42a655cb917` |
| 25 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A6/memory-after.txt` | `1e94295f5ff4768514ad7be7298827de264153a065c6db3b51234a1815ca6a27` |
| 26 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A6/stream.jsonl` | `6a62b6f9bdbf33951c878963019cc6f7bc5aa1b425fa1b4fa43235b7048bc63b` |
| 27 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A7/invocation.txt` | `843d787d2c54a2d691d5bc1f3eadded5210cabd57529d76c810d03ee4b0e11a4` |
| 28 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A7/stream.jsonl` | `5b3f349fd843186afe0381e40bd8102368d851233cd823eab4475e90b9510e71` |
| 29 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A8/detect.json` | `5105eb9873af6cebd5aafb826293ff46ff95d00d25b87aaae86774f5a1045291` |
| 30 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A8/invocation.txt` | `1bb03e0f38e64f5a5e6e6b6875aa9fe2b1f48a341e2cc3dcb924e16d3544510d` |
| 31 | `runs/THR-SUBAGENT/20260813T194853Z/arms/A8/stream.jsonl` | `f71998846bd7541431d21de5a1c82bc4d95b2383e56b29a7d878a8374f9cf6a6` |
| 32 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2b/evidence.txt` | `f1f35803754ffb5c8e688c6e211f45cdfc785db11ee371a47d7d411636e5cfb8` |
| 33 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2b/invocation.txt` | `32cd246f467f228095b66ebe983369f356bd4c48436196c8db18564834e5bf23` |
| 34 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2b/ledger/pretooluse.jsonl` | `577889355426c9ba91df04eaf65e6d5e113b2d55c6870ab31e967fbb2b1321d3` |
| 35 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2b/ledger/spawn.jsonl` | `bf8ff5b0d403f0af9ef78e99595dcb959948165321d0642c99a3bf713dd3fde8` |
| 36 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2b/stream.jsonl` | `ca0ce085cfc070165466b29d9acbb53b882249e8823942db38eb9a526354fb53` |
| 37 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2neg/invocation.txt` | `5c3ef58063ade02340a023c1276f8b14137874da6e8368bcfbdfb8979a9e34e9` |
| 38 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2neg/stream.jsonl` | `f9a5cb793d4b955f33dbb1ec0824f6b4bd9ce54fd8e4934ada7c9cc7e84074d4` |
| 39 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2pos/invocation.txt` | `d756f0b82df68c31c3510b51829867911821d0fbd24dc2054c9fd97b9db6e6e9` |
| 40 | `runs/THR-SUBAGENT/20260813T194853Z/arms/C2pos/stream.jsonl` | `cdd2f7f912842be3b8886bf57a00a718114739742ccd6e4cbf13d67a152fe64f` |

## Commit attribution

### What counts as a verifiable signature here

Signatures in this repository are SSH signatures: `gpg.format` is `ssh`, and
`git log --format=%G?` is the whole of the reading. Two keys sign here, the
operator's and an agent key, and both are listed in an `allowed_signers` file
that lives OUTSIDE the repository. A clone that has no such file reads `U`
where this host reads `G`.

`G` and `U` are the SAME class, and this document calls that class ATTRIBUTED.
The difference between them measures the reader's key list, not the history:
a gate that demanded `G` would go red on every clone that lacks the file and
would be reporting on one laptop's `~/.config`. `N` -- no signature at all --
is the UNATTRIBUTED class, and it is the class the rows below enumerate. No
other `%G?` code is bucketed: one appearing would halt the gate rather than be
folded silently into either side.

One of the two keys shows a grey "Unverified" badge on GitHub, because that
host does not know it. That is GitHub's key registry speaking, not `%G?`. Both
keys answer `G` here, `U` on a clone without the signers file, and both are
attributed.

### What the gate does, and what it does not do

The rows at the end of this section enumerate every UNATTRIBUTED commit
reachable from HEAD. Each row carries two tokens: the commit's full sha, and
that commit's stable `git patch-id`. Anything after the second token is free
text; a `#` at the start of a line is a comment and declares nothing.

`tests/bypass_ft_unattributed_commit_undeclared_fixture.sh` reads this section,
walks every commit reachable from HEAD, and requires the observed set and the
declared set to be EQUAL -- member for member, in both directions. A declared
sha the observed set does not contain fails it just as a commit the rows do not
name does.

THIS GATE COMPELS THE DECLARATION, NOT THE ABSENCE. Another unsigned commit
does not turn the suite red by existing; it turns it red by going undeclared.
Write its row and the suite is green again. What this section buys is that the
set cannot grow in silence -- not that it cannot grow.

A PATCH-ID MATCH NEVER PRODUCES GREEN. A patch-id identifies a diff, and a
commit is a diff plus its parent, author, committer, message and dates. If a
rewrite moves a declared sha, the written patch-id says which new commit
answers to which stale row, and the gate answers 6 UNMEASURED-STALE: neither a
pass nor an accusation, but an instruction to re-declare the row.

Run it:

```
bash tests/bypass_ft_unattributed_commit_undeclared_fixture.sh
```

IT NEEDS THE COMPLETE HISTORY, AND IT REFUSES TO ANSWER WITHOUT ONE. On a
shallow clone the set of commits reachable from HEAD is the checkout's depth
window and not this history, so the gate declares `UNMEASURED-SHALLOW` and
takes no verdict at all -- neither the accusation nor the pass would be about
this repository. Unshallow the clone and ask again:

```
git fetch --unshallow
```

A `--filter=blob:none` clone is a different reduction and is not affected: it
omits blobs and keeps every commit, so it measures exactly as a full clone
does.

### The check a reader can run without trusting this file

```
git log --format='%h %G? %ad %cd' --date=iso-strict
```

The second column is the signature reading. The third and fourth are the author
date and the committer date, and the gap between them is the subject of the
next paragraph.

### On when the signatures were made

AN SSH SIGNATURE CARRIES NO TIMESTAMP OF ITS OWN. There is no field to read
that says when a signature was made, so "these were not signed after the fact"
is not directly checkable in this repository, and this file will not assert it
as though it were.

The only check available is the gap between a commit's author date and its
committer date: a history rewritten to add signatures rewrites the commits, and
that moves the committer date while leaving the author date alone. THAT GAP IS
NOT A PROOF. It is an indirect reading of a rewrite, not of a signature, and a
rewrite that also set `GIT_COMMITTER_DATE` would leave nothing to see at all.

No figure is quoted here. A figure would be a measurement no gate takes, in a
published document, moving under every commit -- which is the class of claim
this section exists to stop making. Take the reading yourself, on the history in
front of you, with the same `git log --format='%h %G? %ad %cd'` the section
above prints: what the gap can show is a commit whose two dates are far apart,
and what it cannot show is when any signature was made.

What this repository does assert is the forward-looking half, which needs no
measurement: the rows below are not going to be closed by signing old commits
now. A signature applied today to a commit authored in July would assert an
attestation that never took place. The gap is declared instead of closed.

### The groups

**Founding history.** These commits precede the first attributed commit in this
repository, `a8c31a6`, authored 2026-07-13. Before it there was no signing
arrangement here to use. They are published on `origin/main`.

**Automated dependency updates.** Authored by `dependabot[bot]` through GitHub.
The operator did not author these bytes and cannot attest to them after the
fact. THE BYTES ARE HELD LOCALLY -- they are in this clone and in every other
one; what is absent is the authorship, not the possession. Published on
`origin/main`.

**Operator commits.** Authored after `a8c31a6` and with attributed commits
standing on both sides of them in time: signing was available and was not used.
These are the only rows below that `origin/main` does not carry.

### Three rows stand in a relation to the in-toto statements, and it is three different relations

Three tracked statements live under
`runs/THR-CONFORMANCE/20260814T002404Z/records/`. THOSE STATEMENTS PIN BLOBS BY
SHA256. Nothing in them names a commit at all. The fact this section records is
therefore not that records are anchored to unattributable commits -- it is that
BLOBS THOSE RECORDS PIN WERE INTRODUCED BY COMMITS THIS REPOSITORY CANNOT
ATTRIBUTE. The pins themselves are unaffected: a blob's digest does not depend
on who committed it.

Three rows below touch that material, by three different mechanisms:

- `4a6a611` introduced NO attested bytes. It wrote the CONTENT OF THE
  ATTESTATION: it added the `anchor` and `transformation` predicate objects to
  all three statements and re-pinned their subject and evidence digests. An
  unattributed commit authored what those records assert. Of the three this is
  the heaviest, and it is named first for that reason.
- `b0ce2f9` introduced the blobs the statements pin -- six of the files it
  added are named in them by sha256, in an `evidence` or `subject` role. The
  same commit also rewrote a pin inside all three statements, moving one
  evidence digest.
- `90e27ce` introduced one file that the Path transformation table above pins
  by path and digest. No statement names it.

A previous version of this section called two of these "commits that carry
bytes in-toto statements pin", which was one mechanism where there are three,
and it filed `4a6a611` under the lightest of them.

<pre>
<!-- ACCEPTED-UNATTRIBUTED-BEGIN -->
# founding history
71fce181977be83d44d24885ac2538bace4c2035  e8e7c994fad786d720e354f84e278df282be2a10  # 71fce18 2026-07-12 feat: harness-pack v0 (constitution v2.1, tier manifest, has
8dd899aec4e2c020860194b792743025af90e5ad  1b3b65ae33426724e80afef35cddd30b09538f6a  # 8dd899a 2026-07-12 docs(readme): plain-language rewrite with diagrams
386f4519961e5c91759b2e753017948fee5e4a33  ad74183ae73d3b540df01f7b59a2ebb0bcf65881  # 386f451 2026-07-12 fix(launcher): pipe spec via stdin — leading YAML fence was
b257ca0e33dfbb180765b932d3236255bb335914  6fc07e55c430c240f1efcdebab89337cc6d13c0f  # b257ca0 2026-07-12 fix(ci): shellcheck SC2002 + single-hop tier enforcement + f
a1405db8ad3d67bf4539085ee3786df1e79807ee  f4df46e3af9a71f443ae3cf589fa88ddc862f174  # a1405db 2026-07-12 chore(repo): gitignore .DS_Store, SHA-pin actions, dependabo
3466e1c83a39c0367dabf7b5d92330e3f6b3efd1  a2dd2cd42e484c28cee477cf05b8c78b1958eda5  # 3466e1c 2026-07-12 docs(constitution): v2.2 — injection wording, G4 cites L-021
b12aff39fea633e691d801488e080b4b47de3c05  d1fc60545cfaa72331619488aceb805ba24294bb  # b12aff3 2026-07-12 feat(launcher): pin constitution hash via constitution_hash_
c3a64febdcd465817bbc8e422d490915edabf684  4c23fc32f91843211476df6869b20825b1396fc2  # c3a64fe 2026-07-12 fix(specs): RS-001 trigger self-contained via rollup_due.sh
6d451a330b7caef2884343069116d457f3dd3c35  55b29ba5fd68618ace3833168a980be32146b702  # 6d451a3 2026-07-12 fix(launcher): pin HALT kill-switch to HARNESS_HOME, stable
835503f220e0e16d1e8bdc2f62459635b907a340  702bdb11f09ccc9fedb5ce4b839d10ee3716f348  # 835503f 2026-07-13 docs(examples): add verified receipt-chain sample
73f2a7356f9ec6dc5dc5642f142b6c1c037a3727  ecff4ded443b09108918a981314bf0d68c3bf2bd  # 73f2a73 2026-07-13 feat(halt): hot kill-switch — guard blocks all tools, walk-u
# automated dependency updates
ddf0a26d4a5a0bf7ec8ff0d0834328223c434b07  91f7bf7fea08797b7440a77213407ba2bf0595f5  # ddf0a26 2026-08-09 chore(deps): bump actions/setup-python from 5.6.0 to 7.0.0 (
393ab001ebf95d4200913544b1fe277c927cc97c  ad657d7de1f87c1bffd815ee445376bbe1b13453  # 393ab00 2026-08-09 chore(deps): bump actions/checkout from 4.3.1 to 7.0.1 (#3)
# operator commits
b0ce2f9e56ec8fb2d7d39dbb100144b23c31e84e  93e2e8e5d8be63c67d9e7b68bb9c7a33dc5db541  # b0ce2f9 2026-08-14 test(subagent): eight-arm evidence, path-transformed — the b
90e27cef83ee42bea98ab7dc0c83fc3b2a8aef70  6b64940ff734776909ddce165d38a4c478284bf2  # 90e27ce 2026-08-14 test(register): THR-SUBAGENT RESULT.json, path-transformed
4b6c98fd557777f08aa3262321dd09b90ffc4d66  5c48dd2f6b0fa028e2a40f57b5693dd734d99fa4  # 4b6c98f 2026-08-19 fix(fixture): FT-12 locates the deployed gate instead of nam
640511b17a7fed78f635c7c494c41986f4826c8f  51987097ba494504770a6ad602249710831ca8b5  # 640511b 2026-08-19 test(privacy): FT-28 detects the flattened home-path spellin
4a6a611abb2aebcb7a5e160fb565ae1b7d4b2f93  08a8b5bcdd58aee25c25773e6de7fe3c69c107a5  # 4a6a611 2026-08-19 privacy(tree): remove the flattened home-path spelling from
<!-- ACCEPTED-UNATTRIBUTED-END -->
</pre>

Matching is by sha, and the patch-id beside each sha is what identifies the
commit a row names if a rewrite moves it. Exemption is by enumeration only. No
commit is exempt by author, by date, or by membership in any class -- and that
includes the class "has the same diff as a commit that is declared", which is
what a patch-id match names and why a patch-id match cannot produce GREEN.

## Local-only refs

This clone carries refs that `git push origin main` does not send: three under
`refs/backup/` and ten branches besides `main`. A reader can list them in their
own copy:

```
git for-each-ref --format='%(refname)' refs/backup refs/heads
```

An earlier version of this section named one backup ref and said it must never
be published because the commits it reaches carry the operator's home path in
their trees. The trees do carry it. What was said to follow does not. Measured:

- the blobs carrying that path, in either of the two spellings the Path
  transformation section above describes, are reachable from HEAD and from
  `origin/main` alike. They are already published, in the history behind the
  commit that removed the spelling from the tracked surface;
- no local ref reaches such a blob that `origin/main` does not already have.
  Across every local ref, the objects reachable from it and from neither HEAD
  nor `origin/main` include no carrier at all;
- `git push origin main` from this clone sends no carrier.

So the reason to keep these refs unpublished is not that they hold something
`origin` lacks. It is that they are working state -- pre-rewrite history and
abandoned branches -- and publishing them would put working state into the
record as though it were the record.

The check, and what a non-empty answer means:

```
git ls-remote origin 'refs/backup/*'
```

Empty is the expected result and the one measured here. A NON-EMPTY RESULT IS
AN INCIDENT, not a state to reconcile: it means a `--mirror` push or an
explicit refspec published working state, and the refs are to be deleted on the
remote. `git push --mirror` and an explicit `refs/backup/*:refs/backup/*`
refspec both send them; a client-side `pre-push` hook sees the resolved ref
list in both cases -- measured -- so this is gateable, and it is not gated
today.

## The session trailer

Some commit messages in this history end with a trailer that names the session
in which the commit was produced:

```
Claude-Session: <url>
```

THE URL IS OPAQUE TO EVERY READER BUT THE OPERATOR. It does not resolve, and it
is not meant to: no reader can follow it to a transcript, and nothing in this
repository depends on one existing. It is a provenance marker -- it says that a
session produced this commit, and which session that was -- not a citation. A
reader who treats it as a source to consult has misread what it is for.

The identity this repository considers binding is the SIGNATURE, not the URL.
`%GS` is the whole of the attribution reading, exactly as `%G?` is the whole of
the signature reading:

```
git log --format='%h %G? %GS'
```

A reader verifies attribution in those two columns and NEVER at the trailer.
The trailer is message text, written by the same process that wrote the
subject; it attests to nothing it does not simply assert, and an unsigned
commit carrying one is unattributed exactly as an unsigned commit without one
is.

The trailer was not removed. Removing it would make the record less true: those
sessions happened, they produced those commits, and a message stripped of the
line would say less about how the commit came to exist than the message that
carries it. The class is declared here rather than deleted there.
