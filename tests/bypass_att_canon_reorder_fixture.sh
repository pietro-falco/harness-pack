#!/usr/bin/env bash
# bypass_att_canon_reorder -- the falsifier ADR-018 D1 names, AND THIS FILE
# CLOSES ADR-018 OR-6.
#
# OR-6 held this row open with a reason and a birth moment, and both are quoted
# here because the row is only admissible now that they are met. ADR-018 OR-6,
# verbatim: "D1 binds **new** content-addressed artifacts and exempts the
# existing receipt, and no new artifact exists at this basis. A fixture written
# now would either assert D1 against the exempt receipt -- the wrong artifact --
# or against nothing at all, and a falsifier that is green because its subject
# does not exist is precisely the defect `harness-pack/ADR-017` names." And the
# moment it named: "**Its birth moment is the first side-car Statement emitted**
# -- the artifact `harness-pack/ADR-019` D5 places beside the receipt. That file
# is the first thing this repository content-addresses under D1, and the fixture
# is written in the commit that first writes one: reorder its keys, re-serialize,
# and require the same content id."
#
# That artifact exists as of this commit: scripts/write_statement.py emits it.
# OR-6's other branch is also settled -- it warned that if ADR-019 OR-3 answered
# "the side-car is not content-addressed", the OR would move to whichever new
# artifact came first. ADR-019 OR-3 is answered YES: the emitter writes ADR-018
# D1's form and no trailing byte, so the file's bytes ARE the serialization and
# sha256(file) is its content id. This row is that answer under test.
#
# THE ASSERTION (ADR-018 D1): the same logical content, serialized with reordered
# keys, must produce the same content id. The adopted form is "JSON with keys
# sorted lexicographically, compact separators (`","`, `":"`), no whitespace,
# UTF-8". ADR-018 OR-1 forbids calling that form by the name of any external
# canonicalization standard -- the two divergences DETERMINISM.md:68-80 measured
# are open, not established -- so it is named here as it is named there and
# nowhere by the other name.
#
# THE FRAMING IS PART OF THE CONTENT IDENTITY, and it is asserted rather than
# assumed. A trailing newline is whitespace; a file carrying one would hash
# differently from the string that produced it, and "content-addressed" would
# then need a second convention about framing that nobody wrote down. The emitted
# file must therefore end in `}`.
#
# WHY THE REORDER CONTROL IS NOT VACUOUS. Hashing the same bytes twice trivially
# agrees, so a fixture that only re-hashed the emitted file would measure
# nothing. Three things are measured instead:
#
#   control 1  the reordering is REAL -- the naive serialization of the reordered
#              object must differ, byte for byte, from the emitted file. If it
#              did not, nothing was reordered and the agreement below is
#              tautological.
#   control 2  the form is LOAD-BEARING -- the same reordered object serialized
#              in the RECEIPT's form (`indent=1`, no key sort, the form
#              write_receipt.py:163 uses and D1 explicitly exempts) must produce
#              a DIFFERENT content id. This is DETERMINISM.md:24-26's measured
#              262-byte formatting delta reproduced on the new artifact.
#   the row    the reordered object, re-serialized in D1's form, must produce the
#              SAME content id as the emitted file's bytes.
#
# DECLARED GREEN, and this header is where the register reads that (ADR-017 D6).
# It goes RED if the emitter stops sorting keys, starts indenting, or appends a
# framing byte.
#
# Nothing outside $WORK is written. The tracked receipt fixtures and
# examples/receipt-chain.sample.jsonl are not read and not touched: D1 exempts
# the existing receipt and this row does not accuse it.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
RECEIPT_WRITER="$PACK/scripts/write_receipt.py"
STATEMENT_WRITER="$PACK/scripts/write_statement.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-att-canon.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$RECEIPT_WRITER" ] || broken "scripts/write_receipt.py is not where this fixture expects it"
[ -f "$STATEMENT_WRITER" ] || broken "scripts/write_statement.py is not where this fixture expects it"

# Reorder every object's keys at every depth, then serialize three ways. Python
# dicts preserve insertion order, so rebuilding a dict from reversed(keys) is a
# genuine reordering of the serialized form -- which control 1 verifies rather
# than assumes.
cat > "$WORK/reserialize.py" <<'RESERIALIZE'
import hashlib, json, sys

def reorder(node):
    if isinstance(node, dict):
        return {k: reorder(node[k]) for k in reversed(list(node.keys()))}
    if isinstance(node, list):
        return [reorder(v) for v in node]
    return node

mode = sys.argv[2]
obj = reorder(json.load(open(sys.argv[1])))
if mode == "canonical":
    # ADR-018 D1's form: keys sorted lexicographically, compact separators, no
    # whitespace, UTF-8.
    text = json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
elif mode == "naive":
    # No sort, default separators: what a writer produces when it does not
    # canonicalize at all.
    text = json.dumps(obj, ensure_ascii=False)
elif mode == "receipt-form":
    # write_receipt.py:163's form, which ADR-018 D1 exempts from the new rule.
    text = json.dumps(obj, indent=1, ensure_ascii=False)
else:
    print("unknown mode %r" % mode, file=sys.stderr)
    sys.exit(2)
raw = text.encode("utf-8")
print("%s %d" % (hashlib.sha256(raw).hexdigest(), len(raw)))
RESERIALIZE

echo "== bypass_att_canon_reorder: reordered keys, one content id (ADR-018 D1; closes ADR-018 OR-6) =="

# ---- the subject: a side-car Statement, emitted in this run -----------------
CC="$WORK/run-fixture-canon.cc.json"
printf '%s' '{"subtype":"success","num_turns":5,"total_cost_usd":0.02,"duration_ms":2400,"session_id":"fixture-session","permission_denials":[]}' > "$CC"
printf '%s' '{"manifest_version":1,"verifier_id":"https://verifier.example.invalid/harness-pack/v1"}' > "$WORK/manifest.json"

RECEIPT="$WORK/run-fixture-canon.receipt.json"
CC_EXIT=0 \
GATE_JSON='{"verdict":"PASS","reason":"all declared criteria PASS","verity_exit":0,"claims":[{"id":"c1","type":"command","verdict":"PASS","evidence":"exit 0"}]}' \
BASELINE_JSON='{"verdict":"FAIL","reason":"criteria failed: c1","verity_exit":1,"claims":[{"id":"c1","type":"command","verdict":"FAIL","evidence":"exit 1"}]}' \
RUN_ID="run-fixture-canon" SPEC_ID="S-FIXTURE" MODEL_STRING="worker" \
TIER_RESOLVED="T3" MODEL_USED="HAIKU_CLASS_MODEL" MANIFEST_VERSION="1" \
CONSTITUTION_HASH="00a92e1544ba9dd55591388830a7f86bf1a8d555e22f455f05b5eb267ecaf97d" \
TOOL_VERSION="0.0.0-fixture" STARTED_AT="2026-08-13T10:14:00Z" ENDED_AT="2026-08-13T10:15:00Z" \
  python3 "$RECEIPT_WRITER" "$CC" "$RECEIPT" >/dev/null \
  || broken "scripts/write_receipt.py did not compose the fixture receipt"

CC_DIGEST="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$CC")" \
  || broken "could not digest the fixture transcript"

STATEMENT="$WORK/run-fixture-canon.intoto.json"
EMIT_OUT="$(OUT_PATH="$CC" OUT_SHA256="$CC_DIGEST" HARNESS_MANIFEST="$WORK/manifest.json" \
  python3 "$STATEMENT_WRITER" "$RECEIPT" "$STATEMENT" 2>&1)"
EMIT_RC=$?
[ "$EMIT_RC" -eq 0 ] || broken "scripts/write_statement.py exited $EMIT_RC: $EMIT_OUT"
[ -f "$STATEMENT" ] || broken "the emitter wrote no Statement; there is no artifact to content-address"

EMITTED_ID="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$STATEMENT")"
EMITTED_LEN="$(wc -c < "$STATEMENT" | tr -d ' ')"

# ---- framing: the bytes on disk ARE the serialization -----------------------
LAST_BYTE="$(python3 -c 'import sys;print(repr(open(sys.argv[1],"rb").read()[-1:]))' "$STATEMENT")"
FRAMING_OK=0
[ "$LAST_BYTE" = "b'}'" ] && FRAMING_OK=1

# ---- control 1: the reordering is real --------------------------------------
NAIVE="$(python3 "$WORK/reserialize.py" "$STATEMENT" naive)" || broken "could not re-serialize naively"
NAIVE_ID="${NAIVE%% *}"
[ "$NAIVE_ID" != "$EMITTED_ID" ] \
  || broken "control 1: the naive serialization of the REORDERED object is byte-identical to the emitted file; nothing was reordered and the agreement below would be tautological"
note "control 1: reordered + naively serialized -> $NAIVE_ID (${NAIVE##* } bytes), which differs from the emitted file: the reorder is real"

# ---- control 2: the form is load-bearing ------------------------------------
RECEIPT_FORM="$(python3 "$WORK/reserialize.py" "$STATEMENT" receipt-form)" || broken "could not re-serialize in the receipt's form"
RECEIPT_FORM_ID="${RECEIPT_FORM%% *}"
[ "$RECEIPT_FORM_ID" != "$EMITTED_ID" ] \
  || broken "control 2: the receipt's own form produced the SAME content id as D1's form; the fixture cannot show that declaring a form buys anything"
note "control 2: same object in write_receipt.py:163's form (indent=1, unsorted) -> $RECEIPT_FORM_ID (${RECEIPT_FORM##* } bytes)"
note "           DETERMINISM.md:24-26 measured exactly this on the receipt: one object, two content ids"

# ---- the row ----------------------------------------------------------------
CANON="$(python3 "$WORK/reserialize.py" "$STATEMENT" canonical)" || broken "could not re-serialize in D1's form"
CANON_ID="${CANON%% *}"

if [ "$CANON_ID" = "$EMITTED_ID" ] && [ "$FRAMING_OK" -eq 1 ]; then
  echo "GREEN [bypass_att_canon_reorder] reordered keys, re-serialized in ADR-018 D1's form, one content id"
  note "emitted file      $EMITTED_ID ($EMITTED_LEN bytes, last byte $LAST_BYTE)"
  note "reordered + D1    $CANON_ID (${CANON##* } bytes)"
  note "the same logical content under two key orders is one artifact, which is what D1 decides"
  note "ADR-018 OR-6 named this row's birth moment as the first side-car Statement emitted."
  note "That artifact exists, it is the one measured above, and this row closes that OR."
  echo "att_canon_reorder BYPASS FIXTURE: GREEN"
  exit 0
fi

echo "RED [bypass_att_canon_reorder] the side-car is not content-addressed under ADR-018 D1"
note "emitted file      $EMITTED_ID ($EMITTED_LEN bytes, last byte $LAST_BYTE)"
note "reordered + D1    $CANON_ID (${CANON##* } bytes)"
if [ "$FRAMING_OK" -ne 1 ]; then
  note "the emitted file does not end in '}': a framing byte is whitespace, so the file's bytes are"
  note "not the serialization and 'content-addressed' needs a second convention nobody wrote down"
fi
if [ "$CANON_ID" != "$EMITTED_ID" ]; then
  note "the emitter is not writing D1's form: keys sorted lexicographically, compact separators"
  note "(',' and ':'), no whitespace, UTF-8. Two key orders are producing two content ids for one object"
fi
echo "att_canon_reorder BYPASS FIXTURE: RED"
exit 1
