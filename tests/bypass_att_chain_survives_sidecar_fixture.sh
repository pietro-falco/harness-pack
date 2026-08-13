#!/usr/bin/env bash
# bypass_att_chain_survives_sidecar -- the falsifier ADR-019 D5 names.
#
# THE ASSERTION (ADR-019 Verification, verbatim): "A fixture that appends the
# receipt to a chain, writes the side-car, and re-verifies the chain, which
# **must still verify**." ADR-019 adopts it in shape from
# `harnesswright/ADR-0008` D5 `:115`, whose own sentence is the other half:
# "Under the rejected in-receipt design the same fixture breaks the chain, and
# that break is the demonstration."
#
# WHAT D5 DECIDES AND WHY. The Statement is a SIBLING file,
# `<run_id>.intoto.json`, never an amendment to the receipt.
# `scripts/receipt_chain.py:47-48` records the sha256 of the source file's RAW
# BYTES -- `with open(src, "rb") as f: digest = _sha(f.read())` -- so a receipt
# mutated after a rollup no longer matches the digest every covering line
# recorded. "The proprietary receipt does not change by one byte as a result of
# this ADR", and this row is that sentence under test.
#
# WHERE THE BREAK IS ACTUALLY VISIBLE, measured rather than assumed, because the
# answer is not the obvious one. `verify()` reads exactly two fields per line,
# `entry.get("prev_sha256") != prev or entry.get("seq") != i` at
# `receipt_chain.py:70`, and re-hashes the raw bytes of each LINE at `:73`. It
# never re-opens the source file. So mutating the receipt does NOT move
# `verify`'s verdict -- ADR-018 D4 measured the same narrowness from the other
# side -- and the covering line's recorded `sha256` is where the mutation shows.
# Both are asserted below, separately, because they are different instruments and
# a fixture that conflated them would report the weaker one as if it were the
# stronger:
#
#   arm 1  the chain verifies before the side-car is written (premise).
#   arm 2  the side-car is written beside the receipt. The receipt's bytes are
#          unchanged, the chain STILL verifies, and the covering line's recorded
#          digest still matches the receipt on disk.
#   arm 3  the REJECTED in-receipt design, applied to a copy: the same Statement
#          folded into the receipt as a field. The covering line's recorded
#          digest no longer matches -- that break is the demonstration -- and
#          `verify` is shown to stay VALID even so, which is the measured fact
#          about the instrument rather than a defect in this row.
#
# ARM 3 IS THE CONTROL, and without it arm 2 is worth nothing: a chain that
# verifies after an operation that could not have disturbed it is not evidence
# that the operation is safe.
#
# DECLARED GREEN, and this header is where the register reads that (ADR-017 D6).
#
# Nothing outside $WORK is written. `examples/receipt-chain.sample.jsonl` and any
# `.harness/` chain are neither read nor appended to: the chain measured here is
# one this fixture creates from GENESIS in its own scratch directory.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
RECEIPT_WRITER="$PACK/scripts/write_receipt.py"
STATEMENT_WRITER="$PACK/scripts/write_statement.py"
CHAIN_TOOL="$PACK/scripts/receipt_chain.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-att-chain.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$RECEIPT_WRITER" ] || broken "scripts/write_receipt.py is not where this fixture expects it"
[ -f "$STATEMENT_WRITER" ] || broken "scripts/write_statement.py is not where this fixture expects it"
[ -f "$CHAIN_TOOL" ] || broken "scripts/receipt_chain.py is not where this fixture expects it"

digest_of() { python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

# The covering line's own record, read out of the chain rather than recomputed:
# prints the `sha256` the chain line stores for a given source_filename.
cat > "$WORK/recorded_digest.py" <<'RECORDED'
import json, sys
want = sys.argv[2]
for raw in open(sys.argv[1], "rb"):
    stripped = raw.rstrip(b"\n")
    if not stripped:
        continue
    entry = json.loads(stripped)
    if entry.get("source_filename") == want:
        print(entry.get("sha256", ""))
        sys.exit(0)
print("")
sys.exit(1)
RECORDED

echo "== bypass_att_chain_survives_sidecar: a sibling file, never an amendment (ADR-019 D5) =="

RUN="$WORK/run"
mkdir -p "$RUN" || broken "could not create the run directory"
CC="$RUN/run-fixture-chain.cc.json"
RECEIPT="$RUN/run-fixture-chain.receipt.json"
STATEMENT="$RUN/run-fixture-chain.intoto.json"
printf '%s' '{"subtype":"success","num_turns":6,"total_cost_usd":0.03,"duration_ms":3100,"session_id":"fixture-session","permission_denials":[]}' > "$CC"
printf '%s' '{"manifest_version":1,"verifier_id":"https://verifier.example.invalid/harness-pack/v1"}' > "$WORK/manifest.json"

CC_EXIT=0 \
GATE_JSON='{"verdict":"PASS","reason":"all declared criteria PASS","verity_exit":0,"claims":[{"id":"c1","type":"command","verdict":"PASS","evidence":"exit 0"}]}' \
BASELINE_JSON='{"verdict":"FAIL","reason":"criteria failed: c1","verity_exit":1,"claims":[{"id":"c1","type":"command","verdict":"FAIL","evidence":"exit 1"}]}' \
RUN_ID="run-fixture-chain" SPEC_ID="S-FIXTURE" MODEL_STRING="worker" \
TIER_RESOLVED="T3" MODEL_USED="HAIKU_CLASS_MODEL" MANIFEST_VERSION="1" \
CONSTITUTION_HASH="00a92e1544ba9dd55591388830a7f86bf1a8d555e22f455f05b5eb267ecaf97d" \
TOOL_VERSION="0.0.0-fixture" STARTED_AT="2026-08-13T10:14:00Z" ENDED_AT="2026-08-13T10:15:00Z" \
  python3 "$RECEIPT_WRITER" "$CC" "$RECEIPT" >/dev/null \
  || broken "scripts/write_receipt.py did not compose the fixture receipt"

# ---- arm 1: the chain verifies before anything is written beside it ---------
CHAIN="$WORK/receipt-chain.jsonl"
APPEND_OUT="$(python3 "$CHAIN_TOOL" append --chain "$CHAIN" --run-id "att-chain-sidecar" "$RECEIPT" 2>&1)"
APPEND_RC=$?
[ "$APPEND_RC" -eq 0 ] || broken "receipt_chain.py append failed (rc=$APPEND_RC): $APPEND_OUT"
BEFORE_OUT="$(python3 "$CHAIN_TOOL" verify --chain "$CHAIN" 2>&1)"
BEFORE_RC=$?
[ "$BEFORE_RC" -eq 0 ] || broken "the freshly appended chain does not verify ($BEFORE_OUT); there is no premise to preserve"
RECEIPT_BEFORE="$(digest_of "$RECEIPT")"
RECORDED="$(python3 "$WORK/recorded_digest.py" "$CHAIN" "run-fixture-chain.receipt.json")" \
  || broken "the chain carries no line covering the receipt"
[ "$RECORDED" = "$RECEIPT_BEFORE" ] || broken "the covering line records $RECORDED and the receipt hashes to $RECEIPT_BEFORE before anything happened"
note "arm 1: ${BEFORE_OUT}; the covering line records $RECORDED, which is the receipt's bytes"

# ---- arm 2: write the side-car, then re-verify -------------------------------
CC_DIGEST="$(digest_of "$CC")" || broken "could not digest the fixture transcript"
EMIT_OUT="$(OUT_PATH="$CC" OUT_SHA256="$CC_DIGEST" HARNESS_MANIFEST="$WORK/manifest.json" \
  python3 "$STATEMENT_WRITER" "$RECEIPT" "$STATEMENT" 2>&1)"
EMIT_RC=$?
[ "$EMIT_RC" -eq 0 ] || broken "scripts/write_statement.py exited $EMIT_RC: $EMIT_OUT"
[ -f "$STATEMENT" ] || broken "the emitter wrote no side-car; there is nothing to have survived"

AFTER_OUT="$(python3 "$CHAIN_TOOL" verify --chain "$CHAIN" 2>&1)"
AFTER_RC=$?
RECEIPT_AFTER="$(digest_of "$RECEIPT")"
RECORDED_AFTER="$(python3 "$WORK/recorded_digest.py" "$CHAIN" "run-fixture-chain.receipt.json")"

A2_FAIL=0
[ "$AFTER_RC" -eq 0 ] || A2_FAIL=1
[ "$RECEIPT_BEFORE" = "$RECEIPT_AFTER" ] || A2_FAIL=1
[ "$RECORDED_AFTER" = "$RECEIPT_AFTER" ] || A2_FAIL=1
note "arm 2: side-car written beside the receipt ($(basename "$STATEMENT")); ${AFTER_OUT}"
note "       receipt bytes $RECEIPT_BEFORE -> $RECEIPT_AFTER; covering line still records $RECORDED_AFTER"

# ---- arm 3: the rejected in-receipt design, on a copy ------------------------
# The same Statement, folded into the receipt as a field. This is the design D5
# refuses, and the fixture applies it to a COPY so the chain built above still
# covers the untouched original: what is measured is the mutation, not a second
# chain.
MUTANT="$WORK/mutant"
mkdir -p "$MUTANT" || broken "could not create the arm 3 directory"
cp "$RECEIPT" "$MUTANT/run-fixture-chain.receipt.json" || broken "could not copy the receipt for arm 3"
MUT_CHAIN="$WORK/mutant-chain.jsonl"
python3 "$CHAIN_TOOL" append --chain "$MUT_CHAIN" --run-id "att-chain-in-receipt" "$MUTANT/run-fixture-chain.receipt.json" >/dev/null 2>&1 \
  || broken "could not build the arm 3 chain"
MUT_BEFORE="$(python3 "$WORK/recorded_digest.py" "$MUT_CHAIN" "run-fixture-chain.receipt.json")" \
  || broken "the arm 3 chain carries no covering line"
python3 - "$MUTANT/run-fixture-chain.receipt.json" "$STATEMENT" <<'FOLD'
import json, sys
receipt = json.load(open(sys.argv[1]))
receipt["attestation"] = json.load(open(sys.argv[2]))
json.dump(receipt, open(sys.argv[1], "w"), indent=1)
FOLD
FOLD_RC=$?
[ "$FOLD_RC" -eq 0 ] || broken "could not apply the rejected in-receipt design to the copy"
MUT_ACTUAL="$(digest_of "$MUTANT/run-fixture-chain.receipt.json")"
MUT_VERIFY="$(python3 "$CHAIN_TOOL" verify --chain "$MUT_CHAIN" 2>&1)"
MUT_VERIFY_RC=$?

A3_FAIL=0
[ "$MUT_BEFORE" != "$MUT_ACTUAL" ] || A3_FAIL=1
note "arm 3 [the demonstration]: the in-receipt design moves the receipt's bytes from $MUT_BEFORE"
note "       to $MUT_ACTUAL, while the covering line still records the first. Every line covering"
note "       that receipt now records a digest the file no longer has"
note "arm 3 [the instrument]: receipt_chain.py verify says '${MUT_VERIFY}' (rc=$MUT_VERIFY_RC) on that same"
note "       chain, because :70 reads only prev_sha256 and seq and :73 re-hashes the LINE, never the source."
note "       The break is real and verify is not where it shows -- stated, not glossed"

if [ "$A2_FAIL" -eq 0 ] && [ "$A3_FAIL" -eq 0 ]; then
  echo "GREEN [bypass_att_chain_survives_sidecar] the chain survives the side-car, and would not survive the amendment"
  note "the proprietary receipt did not change by one byte, which is what makes a sibling file free"
  note "and an in-receipt field expensive"
  echo "att_chain_survives_sidecar BYPASS FIXTURE: GREEN"
  exit 0
fi

echo "RED [bypass_att_chain_survives_sidecar] the side-car did not leave the chain where it found it"
if [ "$A2_FAIL" -ne 0 ]; then
  note "arm 2: verify said '${AFTER_OUT}' (rc=$AFTER_RC); receipt $RECEIPT_BEFORE -> $RECEIPT_AFTER;"
  note "       covering line records $RECORDED_AFTER"
fi
if [ "$A3_FAIL" -ne 0 ]; then
  note "arm 3: the rejected in-receipt design left the recorded digest unchanged, so this fixture cannot"
  note "       show that the sibling design buys anything and its green above would be evidence of nothing"
fi
echo "att_chain_survives_sidecar BYPASS FIXTURE: RED"
exit 1
