#!/usr/bin/env bash
# bypass_att_prose_leak -- the falsifier ADR-020 D2 names, AND THIS FILE CLOSES
# ADR-019 OR-5.
#
# THE ASSERTION (ADR-020 Verification, verbatim): "A Statement carrying any field
# outside D2's allowlist -- a `verity` `evidence` string, a `gate.reason`, a
# `denials` member, a `subtype`, a `session_id` -- must be **rejected**."
#
# OR-5 held this row open with a reason, and the reason is quoted because the row
# is only admissible now that it is gone. ADR-019 OR-5, verbatim: "ADR-C is
# `harness-pack/ADR-020`, it names D6's falsifier `bypass_att_prose_leak` in its
# own Verification, and it is **Proposed**. `harness-pack/ADR-006:56` forbids
# writing that fixture against a Proposed ADR, so it belongs to that document's
# ratification." ADR-020 is ratified in this commit. This is that fixture.
#
# NOT YET OBSERVED WHEN IT WAS WRITTEN, AND OBSERVED HERE. ADR-020 declared the
# row honestly -- "No Statement has ever been emitted, so there is no measured RED
# behind this one. It is a prediction until the fixture runs, and it must be
# written so that it fails against the *lenient* implementation -- the one that
# copies a field through because the field happened to be in hand." The REDs
# below are produced deliberately and observed in this commit.
#
# WHAT THE LENIENT IMPLEMENTATION LOOKS LIKE, and why the row is aimed at it. The
# receipt this fixture feeds the emitter carries every one of D1's three carrier
# classes at once, with real leaking values:
#
#   class 1  refusals.denials  -- write_receipt.py:124 copies the array "as
#            received and unmodified" (:98). A refused Write preserves its whole
#            attempted `content`.
#   class 2  subtype, session_id -- :137 and :141, unbounded scalars straight
#            from the child's cc.json.
#   class 3  claims[*].evidence, contribution.baseline.claims[*].evidence,
#            gate.reason -- strings verity produced, passed through with no
#            inspection at launch_worker.sh:303 and :307-312. This is the class
#            that actually leaked in N3-PUBLISH.md's census.
#
# A producer that reached for any of them would produce a well-formed Statement.
# The row measures that NONE of those bytes reaches the artifact, and it measures
# it by searching the artifact's bytes for them rather than by reading the
# emitter's source: what D2 decides is a property of the artifact, not of the
# writer's good intentions.
#
# THE BOUNDARY UNDER TEST IS scripts/statement_lint.py, which ADR-020 D3 puts in
# front of publication and which .verity/claims.json wires as
# `publication-boundary-statement-allowlist`. It is RUN, never read.
#
# DECLARED GREEN, and this header is where the register reads that (ADR-017 D6).
# It goes RED the moment the emitter copies any verifier- or child-authored
# string into the artifact, or the moment the boundary stops refusing one.
#
# Nothing outside $WORK is written. No repository file is created, moved or
# edited by this fixture.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
RECEIPT_WRITER="$PACK/scripts/write_receipt.py"
STATEMENT_WRITER="$PACK/scripts/write_statement.py"
BOUNDARY="$PACK/scripts/statement_lint.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-att-prose.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$RECEIPT_WRITER" ] || broken "scripts/write_receipt.py is not where this fixture expects it"
[ -f "$STATEMENT_WRITER" ] || broken "scripts/write_statement.py is not where this fixture expects it"
[ -f "$BOUNDARY" ] || broken "scripts/statement_lint.py is not where this fixture expects it; ADR-020 D3's claim has no detector"

# The boundary, invoked as a consumer would invoke it. Exit 0 = accepted.
accepts() { python3 "$BOUNDARY" "$1"; }

# The leaking strings, spelled once. Each is the shape its carrier class actually
# produces, and each is searched for in the emitted artifact at the end.
# Exported because the python heredocs below read them from the environment
# rather than having them interpolated into their source: a value spliced into
# a program's text is a value that has to be escaped correctly, and an escaping
# bug here would weaken the specimen silently.
export LEAK_EVIDENCE='does not exist at /srv/agents/private/worker/README.md'
export LEAK_REASON='gate-fail: criteria failed: readme-committed'
export LEAK_SUBTYPE='error_during_execution: /srv/agents/private/worker'
export LEAK_SESSION='sess-/srv/agents/private/worker-0001'
export LEAK_DENIAL='/srv/agents/private/worker/secrets.env'

echo "== bypass_att_prose_leak: no verifier- or child-authored string reaches the Statement (ADR-020 D2/D3; closes ADR-019 OR-5) =="

# ---- control 1: the boundary refuses each shape D2 excludes -------------------
# Written by hand, not produced by anything in tree. Each is a conforming
# Statement with exactly one thing added or replaced, so what moved is what is
# under test. A boundary that accepts any of them is measuring nothing and the
# green below would be worth nothing.
export BASE='{"_type":"https://in-toto.io/Statement/v1","subject":[{"digest":{"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"name":"run.cc.json"}],"predicateType":"https://in-toto.io/attestation/svr/v0.2","predicate":{"verifier":{"id":"https://verifier.example.invalid/harness-pack/v1","policies":[]},"timeCreated":"2026-08-13T10:15:00Z","properties":["HARNESS_GATE_PASS"]}}'

if ! python3 - "$WORK" <<'SHAPES'
import json, os, sys
work = sys.argv[1]
base = json.loads(os.environ["BASE"])

def mutate(fn):
    st = json.loads(json.dumps(base))
    fn(st)
    return st

def ev(st):    st["predicate"]["evidence"] = os.environ["LEAK_EVIDENCE"]
def rs(st):    st["predicate"]["reason"] = os.environ["LEAK_REASON"]
def sub(st):   st["predicate"]["subtype"] = os.environ["LEAK_SUBTYPE"]
def sess(st):  st["predicate"]["session_id"] = os.environ["LEAK_SESSION"]
def den(st):   st["predicate"]["denials"] = [{"tool_name": "Write", "tool_input": {"file_path": os.environ["LEAK_DENIAL"]}}]
# The sixth is the one no key-name allowlist would catch on its own: an ALLOWED
# key carrying a disallowed value. D2 is an allowlist over slots AND over what
# each slot may hold, and this shape is what tells the two apart.
def prose(st): st["predicate"]["properties"] = [os.environ["LEAK_REASON"]]

for name, fn in (("evidence", ev), ("reason", rs), ("subtype", sub),
                 ("session_id", sess), ("denials", den), ("prose-in-enum", prose)):
    with open(os.path.join(work, "leak-%s.json" % name), "w", encoding="utf-8") as f:
        f.write(json.dumps(mutate(fn), sort_keys=True, separators=(",", ":")))
SHAPES
then
  broken "could not construct the control-1 shapes"
fi

C1_FAIL=0
for shape in evidence reason subtype session_id denials prose-in-enum; do
  if OUT="$(accepts "$WORK/leak-$shape.json" 2>&1)"; then
    C1_FAIL=1
    note "control 1: '$shape' was ACCEPTED by the boundary -- it cannot see the leak"
  else
    note "control 1: $(printf '%-14s' "$shape") -> $(printf '%s' "$OUT" | head -1)"
  fi
done
[ "$C1_FAIL" -eq 0 ] || broken "control 1: the boundary accepted a Statement carrying a field ADR-020 D2 excludes; it cannot tell the defect from a conforming artifact"

# ---- control 2: the boundary is not wired to reject everything ---------------
printf '%s' "$BASE" > "$WORK/conforming.json"
C2_OUT="$(accepts "$WORK/conforming.json" 2>&1)" \
  || broken "control 2: a hand-written conforming Statement was rejected ($C2_OUT); a boundary that refuses everything discriminates nothing"
note "control 2: a hand-written conforming Statement -> $(printf '%s' "$C2_OUT" | head -1)"

# ---- the measurement: a leaking receipt, and the artifact derived from it -----
# The receipt is composed by scripts/write_receipt.py rather than typed here, so
# the pair the emitter is fed is the pair the launcher would hand it. Every one
# of D1's three carrier classes carries a leaking value.
CC="$WORK/run-fixture-prose.cc.json"
if ! python3 - "$CC" <<'CCJSON'
import json, os, sys
cc = {
    "subtype": os.environ["LEAK_SUBTYPE"],
    "num_turns": 4,
    "total_cost_usd": 0.03,
    "duration_ms": 3100,
    "session_id": os.environ["LEAK_SESSION"],
    "permission_denials": [
        {"tool_name": "Write",
         "tool_input": {"file_path": os.environ["LEAK_DENIAL"],
                        "content": "TOKEN=" + os.environ["LEAK_DENIAL"]}}
    ],
}
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write(json.dumps(cc))
CCJSON
then
  broken "could not construct the leaking cc.json"
fi

printf '%s' '{"manifest_version":1,"verifier_id":"https://verifier.example.invalid/harness-pack/v1"}' > "$WORK/manifest.json"

RECEIPT="$WORK/run-fixture-prose.receipt.json"
CC_EXIT=0 \
GATE_JSON="{\"verdict\":\"FAIL\",\"reason\":\"$LEAK_REASON\",\"verity_exit\":1,\"claims\":[{\"id\":\"readme-committed\",\"type\":\"file_exists\",\"verdict\":\"FAIL\",\"evidence\":\"$LEAK_EVIDENCE\"}]}" \
BASELINE_JSON="{\"verdict\":\"FAIL\",\"reason\":\"$LEAK_REASON\",\"verity_exit\":1,\"claims\":[{\"id\":\"readme-committed\",\"type\":\"file_exists\",\"verdict\":\"FAIL\",\"evidence\":\"$LEAK_EVIDENCE\"}]}" \
RUN_ID="run-fixture-prose" SPEC_ID="S-FIXTURE" MODEL_STRING="worker" \
TIER_RESOLVED="T3" MODEL_USED="HAIKU_CLASS_MODEL" MANIFEST_VERSION="1" \
CONSTITUTION_HASH="00a92e1544ba9dd55591388830a7f86bf1a8d555e22f455f05b5eb267ecaf97d" \
TOOL_VERSION="0.0.0-fixture" STARTED_AT="2026-08-13T10:14:00Z" ENDED_AT="2026-08-13T10:15:00Z" \
  python3 "$RECEIPT_WRITER" "$CC" "$RECEIPT" >/dev/null \
  || broken "scripts/write_receipt.py did not compose the fixture receipt"

# THE RECEIPT MUST ACTUALLY LEAK, or the row proves nothing. This is the control
# that keeps the measurement from being a tautology: if the writer had sanitised
# the receipt, the Statement would be clean for a reason that has nothing to do
# with D2, and ADR-020's Non-goals are explicit that the receipt is NOT sanitised.
RECEIPT_LEAKS=0
for leak in "$LEAK_EVIDENCE" "$LEAK_REASON" "$LEAK_SUBTYPE" "$LEAK_SESSION" "$LEAK_DENIAL"; do
  grep -qF -- "$leak" "$RECEIPT" || { RECEIPT_LEAKS=1; note "the receipt does NOT carry: $leak"; }
done
[ "$RECEIPT_LEAKS" -eq 0 ] || broken "the fixture receipt does not carry the strings this row exists to keep out of the Statement; the measurement would be vacuous"
note "the receipt carries all five leaking strings, as ADR-020 D1 says it does and its Non-goals say it will keep doing"

CC_DIGEST="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$CC")" \
  || broken "could not digest the fixture transcript"

STATEMENT="$WORK/run-fixture-prose.intoto.json"
EMIT_OUT="$(OUT_PATH="$CC" OUT_SHA256="$CC_DIGEST" HARNESS_MANIFEST="$WORK/manifest.json" \
  python3 "$STATEMENT_WRITER" "$RECEIPT" "$STATEMENT" 2>&1)" \
  || broken "scripts/write_statement.py refused a receipt it could read: $EMIT_OUT"
[ -f "$STATEMENT" ] || broken "the emitter reported success and wrote no Statement; there is nothing to judge"

# Half one: the boundary accepts what the emitter wrote.
ROW_RC=0
ROW_OUT="$(accepts "$STATEMENT" 2>&1)" || ROW_RC=1

# Half two, and it is not decoration. A boundary that accepts the artifact says
# the artifact is well-formed; it does not by itself say the leak was excluded
# rather than never attempted. So the artifact's BYTES are searched for each of
# the five strings the receipt is now known to carry.
BYTES_CLEAN=0
for leak in "$LEAK_EVIDENCE" "$LEAK_REASON" "$LEAK_SUBTYPE" "$LEAK_SESSION" "$LEAK_DENIAL"; do
  if grep -qF -- "$leak" "$STATEMENT"; then
    BYTES_CLEAN=1
    note "the Statement CARRIES: $leak"
  fi
done

if [ "$ROW_RC" -eq 0 ] && [ "$BYTES_CLEAN" -eq 0 ]; then
  echo "GREEN [bypass_att_prose_leak] the receipt leaks on all three carrier classes and the Statement carries none of it"
  note "boundary on the emitted artifact: $(printf '%s' "$ROW_OUT" | head -1)"
  note "six leak shapes refused (control 1), one conforming artifact accepted (control 2)"
  note "five leaking strings present in the receipt, zero present in the Statement's bytes"
  echo "att_prose_leak BYPASS FIXTURE: GREEN"
  exit 0
fi

echo "RED [bypass_att_prose_leak] a verifier- or child-authored string reached the publishable artifact"
note "boundary on the emitted artifact: ${ROW_OUT} (rc=$ROW_RC)"
note "ADR-020 D2, verbatim: 'no field of the Statement is ever populated by a string that the child"
note "or verity produced. Not evidence, not reason, not subtype, not session_id, not any member of denials.'"
note "A denylist's failure mode is a Statement that carries something, invisible and permanent once published."
echo "att_prose_leak BYPASS FIXTURE: RED"
exit 1
