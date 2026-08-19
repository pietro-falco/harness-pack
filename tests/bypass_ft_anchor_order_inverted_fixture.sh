#!/usr/bin/env bash
# FT-32 -- anchor-order-inverted. The anchor protocol is an ORDER, not just
# a pair: the apparatus deposits the declaration digest when the run starts
# and the stream digest when it closes, so in the append-only chain the
# declaration entry PRECEDES the stream entry, and a run is anchored exactly
# once. A verifier that checks inclusion and the anchored blob but not the
# chain position accepts an anchor pair deposited in any order and any
# number of times -- which readmits the self-certification the anchor
# exists to close: re-anchor after mutating, or anchor both digests at
# close when everything is already known, and the "input the author cannot
# write" degrades to an input the author can time.
#
# What the chain CAN say is order; what it cannot say is wall-clock time.
# That the declaration was deposited before the execution began is a
# property of the apparatus, not of the ledger, and it is a declared limit
# (ADR-025), not a check this fixture could hold.
#
# THREE ARMS, one green control:
#   control    declaration anchored, then stream (scratch_ledger.sh's own
#              order)                              -> want 0 CONFORMANT
#   inverted   stream anchored FIRST, then the declaration; the record
#              cites both truthfully               -> want 2, reason naming
#              the order (does not precede)
#   duplicate  the same run anchored twice (four entries in the chain);
#              the record cites the newest pair    -> want 2, reason naming
#              the recurrence (beyond the two cited entries)
#
# GREEN: control CONFORMANT; both arms exit 2 with the wanted reason.
# RED: either arm reaches 0 -- the chain position is not being read.
# UNMEASURED (2): machinery absent or control not CONFORMANT.
#
# RED was observed against the working-tree verifier at sha256
# fe89e6ea54951d30e3b411a0b2a86fdd5d4c18008a27f7e92baba8ff41a41f88 (the
# THR-ANCHOR anchored verifier: inclusion + anchored blob, no position):
# both arms verified CONFORMANT exit 0
# (runs/THR-WIRE/20260814T150517Z/P2-order-fixture-seen-failing.txt),
# then GREEN with the order and uniqueness checks in place.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="${CONFORMANCE_CORPUS:-$ROOT/tests/fixtures/conformance_corpus.py}"
RECORD="${CONFORMANCE_RECORD:-$ROOT/scripts/conformance_record.py}"
VERIFY="${CONFORMANCE_VERIFY:-$ROOT/scripts/conformance_verify.py}"
ANCHOR="${CONFORMANCE_ANCHOR:-$ROOT/scripts/conformance_anchor.sh}"
ANCHORS="${SCRATCH_LEDGER:-$ROOT/tests/fixtures/scratch_ledger.sh}"
for f in "$CORPUS" "$RECORD" "$VERIFY" "$ANCHOR" "$ANCHORS"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft32.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
want() {
  # want DIR CODE REASON LABEL LEDGER
  d=$1; code=$2; reason=$3; label=$4; led=$5
  out="$(python3 "$VERIFY" "$d/statement.json" --ledger-repo "$led" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$code" -ne 0 ]; then
    echo "RED: $label verified CONFORMANT; the chain position is not being read" >&2; exit 1
  fi
  [ "$rc" -eq "$code" ] || { echo "RED: $label exited $rc, expected $code" >&2; printf '%s\n' "$out" >&2; exit 1; }
  printf '%s\n' "$out" | grep -q "$reason" \
    || { echo "RED: $label exit $code without the expected reason ($reason)" >&2; printf '%s\n' "$out" >&2; exit 1; }
}

# Positive control: the tool's own order (declaration, then stream).
if ! python3 "$CORPUS" green "$WORK/green" \
   || ! bash "$ANCHORS" "$WORK/green" "$WORK/ledger" green >/dev/null \
   || ! python3 "$RECORD" "$WORK/green" "$WORK/green/statement.json" >/dev/null; then
  echo "UNMEASURED: green corpus or builder failed" >&2; exit 2
fi
python3 "$VERIFY" "$WORK/green/statement.json" --ledger-repo "$WORK/ledger" >/dev/null; rc=$?
[ "$rc" -eq 0 ] || { echo "UNMEASURED: positive control not CONFORMANT (exit $rc)" >&2; exit 2; }

# Arm 1: the same digests, deposited in the inverted order. The record
# cites both entries truthfully; only the chain position is wrong.
python3 "$CORPUS" green "$WORK/inv" || { echo "UNMEASURED: corpus failed" >&2; exit 2; }
if ! { git init -q "$WORK/led-inv" \
       && git -C "$WORK/led-inv" config user.name t \
       && git -C "$WORK/led-inv" config user.email t@example.invalid \
       && git -C "$WORK/led-inv" config commit.gpgsign false; }; then
  echo "UNMEASURED: could not init the inverted ledger" >&2; exit 2
fi
sentry=$(bash "$ANCHOR" --ledger-repo "$WORK/led-inv" --run inv --role stream --digest "$(sha "$WORK/inv/stream.jsonl")") \
  || { echo "UNMEASURED: stream anchor failed" >&2; exit 2; }
dentry=$(bash "$ANCHOR" --ledger-repo "$WORK/led-inv" --run inv --role declaration --digest "$(sha "$WORK/inv/invocation.txt")") \
  || { echo "UNMEASURED: declaration anchor failed" >&2; exit 2; }
printf '{"declarationEntry":"%s","streamEntry":"%s"}\n' "$dentry" "$sentry" > "$WORK/inv/anchors.json"
python3 "$RECORD" "$WORK/inv" "$WORK/inv/statement.json" >/dev/null \
  || { echo "UNMEASURED: builder refused the inverted-order run dir" >&2; exit 2; }
want "$WORK/inv" 2 "does not precede" "inverted-order record" "$WORK/led-inv"

# Arm 2: the same run anchored twice; the record cites the newest pair,
# the older pair still names the run in the chain.
python3 "$CORPUS" green "$WORK/dup" || { echo "UNMEASURED: corpus failed" >&2; exit 2; }
if ! { bash "$ANCHORS" "$WORK/dup" "$WORK/led-dup" dup >/dev/null \
       && bash "$ANCHORS" "$WORK/dup" "$WORK/led-dup" dup >/dev/null; }; then
  echo "UNMEASURED: double anchoring failed" >&2; exit 2
fi
python3 "$RECORD" "$WORK/dup" "$WORK/dup/statement.json" >/dev/null \
  || { echo "UNMEASURED: builder refused the re-anchored run dir" >&2; exit 2; }
want "$WORK/dup" 2 "beyond the two cited entries" "re-anchored record" "$WORK/led-dup"

echo "GREEN: inverted deposit order and re-anchored runs refused; the chain position is read, not assumed"
