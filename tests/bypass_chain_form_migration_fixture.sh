#!/usr/bin/env bash
# bypass_chain_form_migration -- the falsifier ADR-018 D4 names.
#
# THE DECISION (ADR-018 D4): "`harness-pack` adopts the new form **at the next
# genesis**, where the cost is zero. Existing chains are **not** migrated:
# rewriting them is exactly the mutation the chain exists to detect". The new
# form "replaces `\"sha256\": <hex>` with `\"digest\": {\"sha256\": <hex>}` and
# `\"prev_sha256\": <hex>` with `\"prev\": {\"sha256\": <hex>}`."
#
# TWO ARMS, AND THEY ARE DIFFERENT KINDS OF THING. The register carries one
# state for this file, so the header says which arm it belongs to.
#
#   ARM A  DEMONSTRATION. A new-form line appended to an old-form chain, and
#          `verify` refuses it. ADR-018 D4 declared this [inferred] and "Not yet
#          observed" -- from receipt_chain.py:70 and :73 -- so this run is the
#          observation. It is a PIN, not a falsifier: it must hold on both sides
#          of the implementation, and a day on which it stops holding is a day
#          in-place migration became silently possible.
#
#   ARM B  FALSIFIER, and it is the arm the register's RED belongs to. D4's
#          decided route is the NEXT GENESIS, and it is not wired:
#          scripts/receipt_chain.py:50-53 writes `prev_sha256` and `sha256` at
#          every genesis, so a chain born today is born old-form. Arm A is what
#          makes that expensive rather than merely untidy -- a chain born
#          old-form can never become new-form in place, so every genesis written
#          before the implementation lands spends, permanently, the one moment
#          D4 says costs nothing.
#
# WHY THE APPENDED LINE IS CORRECT UNDER THE NEW FORM. Its `prev.sha256` is the
# sha256 of line 2's raw bytes, computed here independently of the tool, and its
# `seq` is 3. A reader that understood the new form would accept it. The refusal
# is therefore attributable to the FORM and to nothing else -- had the line
# carried a wrong hash, the same refusal would have proved nothing.
#
# THE ASSERTION IS A SIGNATURE, NOT AN EXIT INTEGER. vault/ADR-073 D1 (:248-251):
# "Gate assertions prefer stable stderr signatures and observable side effects
# over exit-code equality, since two different failure paths routinely produce
# two different non-zero codes and asserting a specific integer is more brittle".
# The signature is the line `INVALID: chain broken at line`, emitted by
# `verify()` at scripts/receipt_chain.py:71 -- on stdout, which is where that
# function writes, so the fixture reads the merged stream and matches the text.
# The neighbouring failure path at :68 prints `INVALID: line N is not valid JSON
# (torn line?)` and would be a different finding; matching the text is what
# keeps the two apart, and an exit integer would not.
#
# DECLARED RED, read from this header and never from a run (ADR-017 D6). It
# clears when a genesis carries the new form -- one edit to `append`, which is
# also the edit that clears bypass_att_alg_unpinned. The two coincide at this
# basis because this repository holds exactly one digest-carrying artifact; they
# are separate rows because D2 accuses the SPELLING of a digest in any new
# artifact while D4 accuses the TIMING of this one, and only D4's row can be
# foreclosed by the passage of time.
#
# NEVER A REAL CHAIN. Every chain this fixture reads or writes is created by it
# under $WORK and destroyed on exit. examples/receipt-chain.sample.jsonl is not
# read here, .harness/ is not touched, and no chain outside $WORK is appended to
# under any arm.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
CHAIN_TOOL="$PACK/scripts/receipt_chain.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-chain-form.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$CHAIN_TOOL" ] || broken "scripts/receipt_chain.py is not where this fixture expects it"

sha_of_line() {  # $1 = file, $2 = 1-based line number -> sha256 of that line's raw bytes, newline stripped
  python3 - "$1" "$2" <<'PY'
import hashlib, sys
want = int(sys.argv[2])
with open(sys.argv[1], "rb") as f:
    for i, raw in enumerate(f, 1):
        if i == want:
            print(hashlib.sha256(raw.rstrip(b"\n")).hexdigest())
            break
PY
}

verify_chain() {  # $1 = chain -> sets VOUT, VRC. verify() prints its signature on stdout.
  VOUT="$(python3 "$CHAIN_TOOL" verify --chain "$1" 2>&1)"
  VRC=$?
}

echo "== bypass_chain_form_migration: a chain does not change shape in place (ADR-018 D4) =="

# ---- setup: an old-form chain, two lines, written by the tool itself --------
CHAIN="$WORK/receipt-chain.jsonl"
printf '{"x":"one"}' > "$WORK/src-a.json" || broken "could not write the fixture source files"
printf '{"x":"two"}' > "$WORK/src-b.json" || broken "could not write the fixture source files"
APPEND_OUT="$(python3 "$CHAIN_TOOL" append --chain "$CHAIN" --run-id "chain-form-old" "$WORK/src-a.json" "$WORK/src-b.json" 2>&1)"
APPEND_RC=$?
[ "$APPEND_RC" -eq 0 ] || broken "scripts/receipt_chain.py append failed (rc=$APPEND_RC): $APPEND_OUT"
LINES="$(grep -c . "$CHAIN")"
[ "$LINES" -eq 2 ] || broken "the seeded chain has $LINES line(s), expected 2"

# ---- control: the old-form chain verifies before anything is appended ------
# Without this, arm A's refusal could be a refusal of the setup.
verify_chain "$CHAIN"
if [ "$VRC" -ne 0 ]; then
  broken "the seeded old-form chain does not verify (rc=$VRC): $VOUT -- nothing below is measurable"
fi
case "$VOUT" in
  *"VALID: chain intact"*) : ;;
  *) broken "the seeded chain verified with an unexpected signature: $VOUT" ;;
esac
note "control: a two-line old-form chain, written by the tool, verifies -- '$VOUT'"

# ---- arm A: append a NEW-FORM line, correct under the new form -------------
PREV2="$(sha_of_line "$CHAIN" 2)"
[ -n "$PREV2" ] || broken "could not compute the sha256 of line 2"
DIGEST_C="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$WORK/src-a.json")"
[ -n "$DIGEST_C" ] || broken "could not compute the source digest for the appended line"

cp "$CHAIN" "$WORK/mixed.jsonl" || broken "could not copy the chain for arm A"
printf '{"digest":{"sha256":"%s"},"prev":{"sha256":"%s"},"rolled_up_at":"2026-01-01T00:00:00+00:00","run_id":"chain-form-new","seq":3,"source_filename":"src-c.json"}\n' \
  "$DIGEST_C" "$PREV2" >> "$WORK/mixed.jsonl" || broken "could not append the new-form line"

# the appended line is materially correct under the new form: prev names line 2
APPENDED="$(tail -1 "$WORK/mixed.jsonl")"
case "$APPENDED" in
  *"\"prev\":{\"sha256\":\"$PREV2\"}"*) : ;;
  *) broken "the appended line does not carry the computed prev; arm A would measure a bad hash, not a form" ;;
esac

verify_chain "$WORK/mixed.jsonl"
ARM_A_RC="$VRC"; ARM_A_OUT="$VOUT"
ARM_A="REFUSED"
case "$ARM_A_OUT" in
  *"INVALID: chain broken at line"*) : ;;
  *) ARM_A="ADMITTED" ;;
esac
[ "$ARM_A_RC" -ne 0 ] || ARM_A="ADMITTED"

# ---- arm A': the same line, DECLARING the form change ----------------------
# D4 permits one route: "A chain that must change shape does so at a declared
# seam line that names the change". OR-4 leaves the spelling open, so this arm
# offers the most generous spelling available -- the line says, in as many
# words, that the form changed -- and asks whether `verify` has any reader for
# it. It does not: :70 reads exactly `prev_sha256` and `seq`.
cp "$CHAIN" "$WORK/seam.jsonl" || broken "could not copy the chain for arm A'"
printf '{"chain_form":"digestset-v1","digest":{"sha256":"%s"},"prev":{"sha256":"%s"},"rolled_up_at":"2026-01-01T00:00:00+00:00","run_id":"chain-form-seam","seam":true,"seq":3,"source_filename":"src-c.json"}\n' \
  "$DIGEST_C" "$PREV2" >> "$WORK/seam.jsonl" || broken "could not append the seam line"
verify_chain "$WORK/seam.jsonl"
SEAM_OUT="$VOUT"
SEAM="REFUSED"
case "$SEAM_OUT" in
  *"INVALID: chain broken at line"*) : ;;
  *) SEAM="ADMITTED" ;;
esac

note "arm A  new-form line appended to the old-form chain -> $ARM_A: '$ARM_A_OUT'"
note "arm A' the same line declaring the seam            -> $SEAM: '$SEAM_OUT'"

if [ "$ARM_A" = "ADMITTED" ]; then
  echo "RED [bypass_chain_form_migration] verify ADMITTED a form change in place"
  note "D4 rests on this being impossible: 'rewriting them is exactly the mutation the chain exists"
  note "to detect'. If a chain can change shape in place and still verify, the premise is false and"
  note "the decision needs rereading, not the fixture"
  note "appended line: $APPENDED"
  echo "chain_form_migration BYPASS FIXTURE: RED"
  exit 1
fi

# ---- arm B: the route D4 DID decide is not wired ---------------------------
GENESIS="$WORK/genesis.jsonl"
APPEND_OUT="$(python3 "$CHAIN_TOOL" append --chain "$GENESIS" --run-id "chain-form-genesis" "$WORK/src-a.json" 2>&1)"
APPEND_RC=$?
[ "$APPEND_RC" -eq 0 ] || broken "append into an empty directory failed (rc=$APPEND_RC): $APPEND_OUT"
GLINE="$(head -1 "$GENESIS")"
GENESIS_FORM="new"
case "$GLINE" in
  *'"prev_sha256":'*|*'"sha256":'*) GENESIS_FORM="old" ;;
esac

if [ "$GENESIS_FORM" = "old" ]; then
  echo "RED [bypass_chain_form_migration] the next genesis still writes the old form, and arm A is why that is final"
  note "genesis written in this run: $GLINE"
  note "scripts/receipt_chain.py:50-53 emits prev_sha256/sha256 unconditionally -- there is no genesis"
  note "branch, so 'the next genesis' arrives in the old form however many times it arrives"
  note "arm A observed, for the first time, what D4 could only infer: a chain that starts old-form"
  note "cannot be carried to the new form in place, and arm A' shows that saying so in the line does"
  note "not help -- verify reads exactly prev_sha256 and seq (receipt_chain.py:70) and has no reader"
  note "for a declared seam (OR-4)"
  note "so the cost D4 called zero is only zero at a genesis that has not happened yet, and each one"
  note "written meanwhile forecloses itself"
  note "green when a chain created from GENESIS carries \"digest\"/\"prev\" DigestSets"
  echo "chain_form_migration BYPASS FIXTURE: RED"
  exit 1
fi

echo "GREEN [bypass_chain_form_migration] the next genesis is born in the new form, and in-place migration is still refused"
note "genesis written in this run: $GLINE"
note "arm A: $ARM_A, arm A': $SEAM"
echo "chain_form_migration BYPASS FIXTURE: GREEN"
exit 0
