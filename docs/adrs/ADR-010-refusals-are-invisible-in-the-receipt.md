---
type: adr
status: accepted
title: "A refused tool call leaves no trace in the receipt, and the launcher already receives the evidence it does not read"
id: ADR-010
date: 2026-08-09
related-adrs: [harness-pack/ADR-008, harnesswright/ADR-0004, harnesswright/ADR-0008, vault/ADR-065]
---

# ADR-010 — Refusals are invisible in the receipt

## Status

**Accepted** (2026-08-10; docs-only). No code, no fixture, no schema change and no
constitution edit ships with this commit. Per the two-commit lifecycle, acceptance is
a separate operator commit; the implementation lands after it and carries its red
fixture in the same commit as the green.

## Numbering note

010 follows the filename maximum (`ADR-009`) in `docs/adrs/`. `ADR-007` was never
allocated; `vault/ADR-080` records the gap as informational and renumbers nothing.

## Basis

| Repository | HEAD |
|---|---|
| `~/Code/harness-pack` | `676425e66524935733172c5f5c56b8f44cfe35d9` |
| `~/Code/harnesswright` | `edb12a499615bf12aa80e5db1c67a268cb247114` |
| `~/Code/verity` | `4dc016b354f3a6eb953590167b46bc29eacf3fcb` |
| `~/Code/lanewright` | `ab77a81da6eecc4f7942c1e508b319c844049da8` |
| `~/Obsidian-Vault` | `fb06e2abddd6d709875886e69dce934b4aae4237` |

**The measurement.** Two `claude -p` sessions, operator shell, 2026-08-09, identical
invocation and identical settings mounting `scripts/guard_pretooluse.py` as the sole
PreToolUse hook. ARM 1 ran `wc -l notes.txt`, which the guard permits. ARM 2 ran
`grep -c filter-branch notes.txt`, which the guard denies — the guard was first
confirmed to exit 2 on that exact payload, offline, before the session was spawned.

Every field the launcher reads was identical across the two arms:
                ARM 1 (permitted)   ARM 2 (refused)

child exit code 0 0
subtype success success
is_error false false
num_turns 2 2
stop_reason end_turn end_turn
terminal_reason completed completed
permission_denials [] 1 entry


The single entry in ARM 2, verbatim from the child's JSON:

{"tool_name": "Bash", "tool_use_id": "toolu_01B9gCQL8ejB5BWxUkRpga1H",
"tool_input": {"command": "grep -c filter-branch notes.txt",
"description": "Count occurrences of "filter-branch" in notes.txt"}}


`grep -c 'G3-BLOCKED'` over the child's JSON returned 0 in both arms: the guard's
stderr is fed back to the model, never to the parent. The model paraphrased it in
`result`, which is prose and is not read by anything.

**Two earlier probes measured nothing, and the record says so.** A first probe asked
the child to run `rm -f <path>`; the model declined on its own and never issued the
tool call, so the hook was never invoked and `permission_denials` was empty. A second
used `grep -c 'chmod' notes.txt`; the guard's pattern requires whitespace or
end-of-string after the token and the closing quote satisfies neither, so the guard
returned 0. Both produced `subtype: success` and both would have been read as
confirmation by an author who did not check whether a refusal had occurred. They are
recorded because the finding below is only as good as the control that distinguishes
it from them.

**Where the receipt is written.** `scripts/launch_worker.sh:422-438` composes the
receipt. From the child's JSON it reads exactly five keys — `subtype`, `num_turns`,
`total_cost_usd`, `duration_ms`, `session_id` (`:428-432`). `permission_denials` is
not among them. The child's stdout is captured at `:342`; its stderr is neither
redirected nor retained.

## Context

A guard refusal does not stop the run. The hook returns 2, the tool call is blocked,
the session continues and exits 0. The launcher therefore takes the `CC_EXIT=0`
branch (`:355`), measures the criteria, and — no criterion having moved — writes
`gate.verdict: FAIL`, `contribution.verdict: NO_OP`, `stop_reason: gate-fail`.

That is byte-for-byte the shape of a run that worked freely and missed its criteria.
An operator reading receipts cannot tell a run that was prevented from working from a
run that worked and failed. Both are `NO_OP`. In Mode A a human sees the refusal in
the transcript; in Mode B there is no transcript, and the receipt is the whole record.

The stack already knows this class of defect and named it: `harnesswright/ADR-0008`
D3 requires `contribution` because `gate.verdict: PASS` beside a no-op was "legible
at a glance" in no existing field. This is the same argument one level down.
`contribution` answers *did the run move anything*. It cannot answer *was the run
allowed to try*.

## Decision

### D1 — The receipt carries a `refusals` object

A launcher-written receipt gains one new top-level object, derived from the child's
`permission_denials` array:

    "refusals": {
      "count": 1,
      "tools": ["Bash"],
      "denials": [ ... the child's array, verbatim ... ]
    }

`count` is the array's length. `tools` is the deduplicated set of `tool_name` values.
`denials` is the array as received, unmodified. When the child reports no denials the
object is present with `count: 0` and empty lists — never absent, because an absent
field and a zero field are the same to a reader who has to guess.

No new data is acquired. The launcher already receives this array and discards it.

### D2 — `refusals` records that calls were refused, never by what

The array carries no attribution. A denial entry is produced identically by the
PreToolUse hook and by a declarative deny rule in the settings layer; the parent
cannot distinguish them from this field, and `templates/settings.mode-b.json`
deliberately runs both layers.

The receipt therefore records the observation and stops there. It does not write
`G3-BLOCKED`, does not name the guard, and does not populate `violation_code`.
`vault/ADR-065` D7 reserves that field for a six-code taint vocabulary and is
Proposed; consuming it here would decide a Proposed ADR's shape from outside it, and
a guard refusal is not a taint trip.

`harness-pack/ADR-008` D4 reaches the same rule from a different measurement — that
a structured classification field may be recorded as an observation but never as the
basis of an attribution. That ADR is Proposed and is not relied on; the convergence
is noted, not cited as authority.

### D3 — The exit code and `stop_reason` do not move

`refusals` is a third orthogonal axis and stays in its own field, exactly as
`harnesswright/ADR-0008` D4 held for the second: "Contribution and acceptance are
different questions and stay in different fields." `ADR-0004` D3 classifies retryable
versus terminal by reading the gate's verdict off the exit code; a refused run whose
gate returned FAIL is terminal for the reason the gate gives, and loading a refusal
axis onto the same integer would make the retry rule ambiguous a second time.

A run with `refusals.count > 0` under `gate.verdict: PASS` exits 0. It is a strange
state — the run was obstructed and the criteria passed anyway — and the receipt is
where it becomes visible, not the exit code.

The notification contract of `ADR-0004` D7, already extended by `ADR-0008` D4 to
carry `contribution.verdict`, is extended once more to carry `refusals.count`. A
refused run is loud to the operator and silent to `$?`.

### D4 — The schema declares the field; the drift it already carries is not repaired here

`templates/receipt.schema.json` gains `refusals` in `properties`. It does **not**
enter `required`.

The schema is already divergent from its writer: it requires `tier_requested`, which
the launcher stopped writing, and it declares nothing about `contribution`, which the
launcher writes. `harness-pack/ADR-005` D4 assigned backward compatibility to readers
and deferred the schema as separate housekeeping; `harnesswright/ADR-0008:119` calls
the standing state what it is. Adding one more optional property does not deepen that
divergence and repairing it is a separate commit against a separate decision.

The measured reason this is safe to defer: no live path validates a receipt against
this schema. `git grep` for `receipt.schema.json` across the four code repositories
returns matches only under `tests/`, `.verity/evidence/`, and prose. The launcher
names neither `schema` nor `validate`.

## Verification

Two fixtures, red before green, in the implementation commit.

| Fixture | Input | Asserted |
|---|---|---|
| fx-refusal-invisible | a `cc.json` carrying a non-empty `permission_denials`, fed to the receipt writer | the receipt carries `refusals.count == 1` and the verbatim entry |
| fx-refusal-control | the same run with `permission_denials: []` | `refusals.count == 0` — NOT absent, NOT non-zero |

The first is the falsifier: red today, because the writer reads five keys and this is
not one of them, and clearable by reading a sixth.

The second is a control in the sense `ADR-009` D1 defines. It cannot be red before
the change, and that is the point: it proves the field discriminates rather than
firing on every run. A `refusals` object that is populated whether or not anything
was refused measures nothing.

Both fixtures construct their input. Under L-o that measures the assertion rather
than the row, and the gap is closed by anchoring: the Basis section records a real
`claude -p` session, with its own control arm, establishing that
`permission_denials` is what a refused child actually emits. The synthetic fixture
tests the launcher's reading of a shape whose reality was measured separately, and
neither half stands alone.

## Consequences

- An operator reading a Mode B receipt can tell an obstructed run from an unproductive
  one. Today both read `NO_OP`.
- Receipts grow by one object. On a clean run it is three empty-ish fields.
- The refusal is legible without any new instrumentation in the guard, which keeps
  the guard's contract — exit 2, stderr to the model — untouched.
- A defect this ADR does not close becomes visible and is carried as OR-2: the same
  three-way collapse admits a third arm.

## Non-goals

- **No change to the guard.** Its stderr channel and exit-2 contract are untouched.
- **No attribution of a refusal to a layer.** D2.
- **No edit to `CONSTITUTION.md`.** OR-1.
- **No repair of the `tier_requested` / `contribution` schema divergence.** D4.
- **No consumption of `violation_code`**, and no decision about `vault/ADR-065` D7.
- **No change to the exit code or to `stop_reason`.** D3.

## Open requirements

- **OR-1 — `CONSTITUTION.md:27` promises a receipt code no writer emits.** It reads
  "Absent that: STOP, receipt code G3-BLOCKED." `G3-BLOCKED` exists only as a stderr
  string in `scripts/guard_pretooluse.py`; `git grep` finds it in no receipt, no
  writer and no reader. D2 establishes that the launcher structurally cannot attribute
  a denial to the guard, so the line as written is unsatisfiable by the parent.
  Either the constitution's wording is corrected, or the guard gains a channel the
  parent reads. Both change the constitution's hash, which is pinned in the manifest
  and checked fail-closed at `:189`, so this lands as one coordinated commit and never
  as a drive-by edit. Falsified by any receipt in this repository carrying the string
  `G3-BLOCKED` while no writer emits it.

- **OR-2 — a model that declines on its own is as invisible as a refused one.** In
  the first probe recorded in Basis, the child refused a command by its own judgement,
  issued no tool call, and reported `permission_denials: []`, `subtype: success`,
  `num_turns: 1`. `refusals` does not catch that arm and this ADR does not claim it
  does. Three distinct causes of an unproductive Mode B run — the guard blocked, the
  model declined, the criteria did not move — collapse to two after this ADR instead
  of three. Falsified by a run in which the model self-declines and the receipt is
  distinguishable from a clean run.

- **OR-3 — the enforced copy is stale and cannot execute this decision.**
  `/opt/harness`, deployed 2026-07-16, is missing `launch_checks.py` and
  `slice_lease.py`, both of which its own `launch_worker.sh` resolves fail-closed,
  and its launcher predates the `contribution` work entirely. A Mode B run through the
  enforced topology runs neither this ADR's receipt nor `ADR-0008`'s. Redeployment,
  with `MANIFEST.sha256` regenerated, precedes any claim that a Mode B run exercised
  this decision. Falsified by any receipt attributed to the enforced copy carrying a
  `contribution` object.

## Not measured

- **The composed receipt of a refused run.** The child's behaviour was measured; the
  launcher's output under it was derived from `:422-438` read literally, not observed.
  No launcher-written receipt exists at this basis for a refused run, because the two
  CLIs the launcher resolves fail-closed are not installed.
- **Whether a denial from the settings deny layer produces an entry of the same
  shape.** D2's argument does not depend on it — it holds a fortiori if the shapes
  differ — but the claim that the parent cannot distinguish the layers rests on the
  hook arm alone.
- **Whether `permission_denials` is stable across Claude Code versions.** Measured at
  the version installed on 2026-08-09; the launcher's own header already names the CLI
  contract as a drift seam.

## Amendment 1 — 2026-08-11 — two premises corrected, both "Not measured" bullets moved, OR-3 closed, OR-4 opened

Six facts measured between this document's acceptance and the landing of its
implementation (`4e3e8ea`) change the record. None reopens a decision. Two correct a
premise the body states as settled, two move a "Not measured" bullet, one closes an
open requirement and one opens a new one. Nothing above this line is edited.

**D3's notification premise was false at the basis.** The paragraph at `:148-149`
reads the notification contract of `ADR-0004` D7 as "already extended by `ADR-0008`
D4 to carry `contribution.verdict`". Measured at `scripts/launch_worker.sh:444`, the
notify carried `run_id`, `spec_id` and `stop_reason` and nothing else. The extension
that sentence extends *once more* did not exist: `ADR-0008` D4 decided a field the
launcher never came to send. The divergence therefore belongs to
`harnesswright/ADR-0008` D4 and is not this document's to repair. What D3 actually
prescribes is unaffected, and the implementation did exactly that and no more — it
added `refusals.count` to the notification and nothing besides.

**OR-1's fail-closed clause was vacuous when it was written and is true now.** OR-1
argues that a constitution edit lands as one coordinated commit because it changes a
hash "which is pinned in the manifest and checked fail-closed at `:189`". At this
document's basis the operator manifest carried no `constitution_hash_expected` key,
and `launch_checks.py:62-64` treats an absent key as no expectation and exits 0
against any bytes whatever. The pin was a no-op, so the clause named a check that
could not fire. The key has been armed since 2026-08-10 (vault `a9f0e75`). The clause
is true today; it was not true when this document was accepted, and at its basis OR-1
rested on the unsatisfiable wording alone.

**The first "Not measured" bullet is closed by observation.** A launcher-written
receipt for a refused run now exists: `run-20260810T160808Z-85322`, produced by the
enforced launcher at `2bf3c15b` with writer `5ba78655`. It carries `refusals.count`
1, `refusals.tools` `["Write"]`, and a denial entry byte-equal to the one in the
child's JSON; the run exited 0 with `stop_reason: gate-pass`. That is the composed
receipt the bullet said had never been observed, and it matches what `:422-438` was
read to imply. Landed at `047fbca`, evidence under
`.verity/evidence/2026-08-10-adr010-first-green-real/`.

**The second "Not measured" bullet narrows and does not close.** That run's denial did
not come from the PreToolUse hook. The DENY leg of `scripts/guard_pretooluse.py:30-46`
is sixteen patterns matched against Bash command strings, with no rule keyed on a tool
name and none on a path, and HALT was not engaged; a `Write` call is outside its reach
entirely. The denial came from the `--allowedTools` layer — a **third** producer,
beside the hook and the settings deny rule that D2 names — and the entry it produced
is identical in shape to the hook's. D2 is strengthened by this rather than qualified:
a parent that could not distinguish two layers now cannot distinguish three. The
settings deny rule remains unexercised, so the bullet narrows to that arm and stays
open.

**OR-3 is closed by the falsifier this document declares for itself.** OR-3 is
falsified by "any receipt attributed to the enforced copy carrying a `contribution`
object", and two receipts dated 2026-08-10 from the enforced copy carry one. The
necessary reading is that OR-3 was anchored to this document's basis, when the
enforced copy was the deploy of 16 July. Redeployment satisfied the precondition OR-3
demanded rather than refuting the state it described: the requirement is **historical,
not falsified**, and the distinction matters because a falsifier that fires on the
remedy it asked for would otherwise read as a defect in the requirement.

**The ordering rule on `refusals.tools` keeps its rule and loses its reason.** The
implementation sorts the deduplicated tool names, and the justification recorded beside
the code is that the receipt is hashed into an append-only chain, where a set rendered
in arbitrary order would make byte-identical runs hash differently. That reason is
cited outside the scope anything here has measured: the enforced launcher names no
`receipt_chain`, and the worker repository contains no receipt-chain file at all. The
rule stands — deterministic ordering of a set is correct and costs nothing, and it
needs no chain to justify it — but the stated motivation is a claim about a mechanism
this stack has not been shown to run.

- **OR-4 — the append-only receipt chain is cited as a constraint and has not been
  located.** `ADR-005` decides a hash-chained receipt log; the ordering rationale above
  relies on it. Neither the enforced launcher nor the worker repository names it.
  Either the chain exists somewhere neither was read, or a decided mechanism is
  unimplemented and every argument resting on it is resting on nothing. Falsified by a
  chain file, or by a writer that links a receipt to its predecessor's hash, found in
  the executing topology.

Ledger. Corrects the premise of D3's third paragraph and the fail-closed clause of
OR-1; neither correction changes what D3 or OR-1 decides. Closes the first "Not
measured" bullet by observation. Narrows the second to the settings-deny arm and
records a third denial producer, strengthening D2. Closes OR-3 as historical rather
than falsified. Adds OR-4. Adds no decision, no fixture and no schema change. This
amendment is docs-only; the document's status remains **Accepted** and its frontmatter
is unchanged, as in `ADR-008`'s two amendments and in `vault/ADR-067`'s four.
