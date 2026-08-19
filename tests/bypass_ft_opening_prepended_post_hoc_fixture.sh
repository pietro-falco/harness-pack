#!/usr/bin/env bash
# FT-35 -- opening-prepended-post-hoc. A RESIDUE MEASURE, not a falsifier
# queueing a repair. THR-RESIDUE asked for the mutation score of the
# opening binding (ADR-026 D3) against one mutant: the apparatus with its
# operation order PERMUTED -- the child writes its stream first, and only
# then does the apparatus compose and deposit the declaration, prepend the
# opening line, and deposit the stream. Chain in the protocol order, two
# entries, first line naming the current declaration entry id.
#
# The mutant SURVIVES, and the survival is structural, not incidental:
# built from the same child bytes against fresh deterministic ledgers
# (conformance_anchor.sh pins identity and dates), the true-order
# apparatus and the permuted apparatus emit BITWISE-IDENTICAL evidence
# pairs, anchors, records, and ledger heads. The verifier's input space
# does not contain the distinction, so no check over that space can --
# and FT-34's own green control (control-new) is already built in the
# mutant's order. What D3 therefore measures, and all it measures: the
# stream was COMPOSED no earlier than the chain state the declaration
# entry extends. That the EXECUTION began after the deposit remains a
# property of the apparatus a reader trusts (ADR-026 L1 as amended by
# THR-RESIDUE); it is not eliminable by any byte-reading verifier on
# this input space, nor by a mechanism living on the same machine as
# the apparatus it would have to measure.
#
# TWO CONSTRUCTIONS from one set of child bytes, plus an identity check:
#   control-true  the protocol order: declaration deposited, opening
#                 line written, child bytes appended, stream deposited
#                                            -> want 0 CONFORMANT
#   arm-mutant    the permuted order: child bytes first, declaration
#                 deposited, opening line PREPENDED, stream deposited
#                                            -> want 0 CONFORMANT (survival)
#   identity      evidence pair, anchors.json, statement.json and the
#                 ledger head identical across the two constructions
#
# GREEN: both CONFORMANT and byte-identical -- the residue stands exactly
#        as ADR-026 (amended) declares it.
# RED:   arm-mutant refused (some mechanism now claims more than the
#        declared residue: re-measure and re-declare before trusting it),
#        or byte-identity broken (the input space changed; the structural
#        argument above must be re-established or this row withdrawn).
# UNMEASURED (2): machinery absent or control-true not CONFORMANT.
#
# Survival observed against verifier blob 7fd6d99514 (ADR-026 D1-D3 in):
# runs/THR-RESIDUE/20260814T164414Z/P1-mutant-seen-surviving.txt.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="${CONFORMANCE_CORPUS:-$ROOT/tests/fixtures/conformance_corpus.py}"
RECORD="${CONFORMANCE_RECORD:-$ROOT/scripts/conformance_record.py}"
VERIFY="${CONFORMANCE_VERIFY:-$ROOT/scripts/conformance_verify.py}"
ANCHOR="${CONFORMANCE_ANCHOR:-$ROOT/scripts/conformance_anchor.sh}"
for f in "$CORPUS" "$RECORD" "$VERIFY" "$ANCHOR"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft35.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
own_ledger() {
  if ! { git init -q --template= "$1" \
         && git -C "$1" config user.name t \
         && git -C "$1" config user.email t@example.invalid \
         && git -C "$1" config commit.gpgsign false; }; then
    echo "UNMEASURED: could not init ledger $1" >&2; exit 2
  fi
}
openline() {
  # Byte-for-byte the line the launcher writes (launch_worker.sh, ADR-026 D2).
  printf '{"type":"conformance_anchor","run":"%s","declarationEntry":"%s"}\n' "$1" "$2"
}

# One set of child bytes, one marked declaration -- the shared inputs.
python3 "$CORPUS" green "$WORK/stage" || { echo "UNMEASURED: corpus failed" >&2; exit 2; }
python3 - "$WORK/stage" <<'PY' || { echo "UNMEASURED: could not mark declaration" >&2; exit 2; }
import sys, os
p = os.path.join(sys.argv[1], "invocation.txt")
lines = open(p, encoding="utf-8").read().splitlines(True)
lines[0] = lines[0].rstrip("\n") + " streamecho=v1\n"
open(p, "w", encoding="utf-8").write("".join(lines))
PY

# control-true: the protocol order, as the launcher performs it. Both
# constructions carry the SAME run-dir basename (the verifier derives the
# run name from it), under different parents, against separate ledgers.
mkdir -p "$WORK/t/residue"
cp "$WORK/stage/invocation.txt" "$WORK/t/residue/invocation.txt"
own_ledger "$WORK/led-true"
dtrue=$(bash "$ANCHOR" --ledger-repo "$WORK/led-true" --run residue --role declaration --digest "$(sha "$WORK/t/residue/invocation.txt")") \
  || { echo "UNMEASURED: declaration anchor failed (true)" >&2; exit 2; }
openline residue "$dtrue" > "$WORK/t/residue/stream.jsonl"
cat "$WORK/stage/stream.jsonl" >> "$WORK/t/residue/stream.jsonl"
strue=$(bash "$ANCHOR" --ledger-repo "$WORK/led-true" --run residue --role stream --digest "$(sha "$WORK/t/residue/stream.jsonl")") \
  || { echo "UNMEASURED: stream anchor failed (true)" >&2; exit 2; }
printf '{"declarationEntry":"%s","streamEntry":"%s"}\n' "$dtrue" "$strue" > "$WORK/t/residue/anchors.json"
python3 "$RECORD" "$WORK/t/residue" "$WORK/t/residue/statement.json" >/dev/null \
  || { echo "UNMEASURED: builder refused the true-order run dir" >&2; exit 2; }
out_true="$(python3 "$VERIFY" "$WORK/t/residue/statement.json" --ledger-repo "$WORK/led-true" 2>&1)"; rc_true=$?
[ "$rc_true" -eq 0 ] || { echo "UNMEASURED: control-true not CONFORMANT (exit $rc_true)" >&2; printf '%s\n' "$out_true" >&2; exit 2; }

# arm-mutant: the permuted order -- the child ran before the declaration
# existed; the apparatus wraps the finished bytes.
mkdir -p "$WORK/m/residue"
cp "$WORK/stage/stream.jsonl" "$WORK/m/residue/stream.jsonl"          # child first
cp "$WORK/stage/invocation.txt" "$WORK/m/residue/invocation.txt"      # then the declaration
own_ledger "$WORK/led-mut"
dmut=$(bash "$ANCHOR" --ledger-repo "$WORK/led-mut" --run residue --role declaration --digest "$(sha "$WORK/m/residue/invocation.txt")") \
  || { echo "UNMEASURED: declaration anchor failed (mutant)" >&2; exit 2; }
openline residue "$dmut" > "$WORK/m/residue/opening"                   # prepend post hoc
cat "$WORK/m/residue/stream.jsonl" >> "$WORK/m/residue/opening"
mv "$WORK/m/residue/opening" "$WORK/m/residue/stream.jsonl"
smut=$(bash "$ANCHOR" --ledger-repo "$WORK/led-mut" --run residue --role stream --digest "$(sha "$WORK/m/residue/stream.jsonl")") \
  || { echo "UNMEASURED: stream anchor failed (mutant)" >&2; exit 2; }
printf '{"declarationEntry":"%s","streamEntry":"%s"}\n' "$dmut" "$smut" > "$WORK/m/residue/anchors.json"
python3 "$RECORD" "$WORK/m/residue" "$WORK/m/residue/statement.json" >/dev/null \
  || { echo "UNMEASURED: builder refused the mutant run dir" >&2; exit 2; }
out_mut="$(python3 "$VERIFY" "$WORK/m/residue/statement.json" --ledger-repo "$WORK/led-mut" 2>&1)"; rc_mut=$?
if [ "$rc_mut" -ne 0 ]; then
  echo "RED: the order-permuted mutant was REFUSED (exit $rc_mut) -- some mechanism now claims more than the residue ADR-026 (amended) declares. Re-measure, re-declare, and only then trust this green" >&2
  printf '%s\n' "$out_mut" >&2
  exit 1
fi

# identity: the structural half. Same bytes in, same bytes out, both orders.
mismatch=""
for f in invocation.txt stream.jsonl anchors.json statement.json; do
  [ "$(sha "$WORK/t/residue/$f")" = "$(sha "$WORK/m/residue/$f")" ] || mismatch="$mismatch $f"
done
head_true=$(git -C "$WORK/led-true" rev-parse refs/observations/ledger)
head_mut=$(git -C "$WORK/led-mut" rev-parse refs/observations/ledger)
[ "$head_true" = "$head_mut" ] || mismatch="$mismatch ledger-head"
if [ -n "$mismatch" ]; then
  echo "RED: the two constructions are no longer byte-identical ($mismatch) -- the verifier's input space changed, and the structural survival argument must be re-established or this row withdrawn" >&2
  exit 1
fi

echo "measured: control-true CONFORMANT (exit 0); arm-mutant CONFORMANT (exit 0)"
echo "measured: declarationEntry $dtrue == $dmut; streamEntry $strue == $smut; ledger head $head_true identical"
echo "measured: evidence pair, anchors.json, statement.json bitwise-identical across the two orders (statement sha256 $(sha "$WORK/t/residue/statement.json"))"
echo "GREEN: the order-permuted apparatus is indistinguishable in bytes from the protocol apparatus; D3 binds stream COMPOSITION to the chain state, never the execution to the deposit -- the residue stands as declared"
