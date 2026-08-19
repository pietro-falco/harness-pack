#!/usr/bin/env bash
# FT-34 -- stream-echo-absent. ADR-025 L1 named the one hole the anchor left
# open: the chain ORDERS the two deposits but does not DATE them against the
# execution -- that the declaration was deposited before the child ran was a
# property of the apparatus a reader had to trust. ADR-026 closes it: on the
# conformance path the launcher marks the resolved declaration with
# `streamecho=v1` BEFORE hashing and depositing it, and writes the
# declaration entry id as the FIRST line of the stream file before the
# child's first byte. The stream digest deposited at close covers that
# line, so a stream whose bytes carry the id was finalized no earlier than
# the chain state the entry extends. A record built by anchoring a
# PRE-EXISTING stream after the fact cannot carry the id: the bytes were
# final before the entry existed, and any edit moves the digest.
#
# A verifier that ignores the marker accepts exactly that record -- the
# a-posteriori shape this fixture builds: declaration marked, both digests
# anchored in the protocol order, record internally coherent, stream
# untouched by the id. What the check can NOT say is wall-clock time: the
# anchor entries are deterministic by design, so an adversary who can
# predict the deposit-time head can precompute the id; the binding is to
# the chain's state, not to a clock (ADR-026 declares it).
#
# FOUR ARMS, two green controls:
#   control-old  corpus record, NO marker (pre-echo protocol)
#                                          -> want 0 CONFORMANT
#   control-new  marker present, first stream line carries the cited
#                declaration entry id and run  -> want 0 CONFORMANT
#   arm-missing  marker present, the stream never carries the id (the
#                a-posteriori record)      -> want 2, reason naming the
#                opening binding
#   arm-wrong-id marker present, first line carries a DIFFERENT 40-hex
#                id                        -> want 2, same refusal family
#
# GREEN: both controls CONFORMANT; both arms exit 2 with the wanted reason.
# RED: either arm reaches 0 -- the marker is not being read.
# UNMEASURED (2): machinery absent or a control not CONFORMANT.
#
# RED was observed against the working-tree verifier at blob
# f624699ca28074a10e2654f022e4fd61a8a03e1e (order and count checks in, no
# opening binding): arm-missing verified CONFORMANT exit 0
# (runs/THR-PAYLOAD/20260814T155425Z/P1-echo-fixture-seen-failing.txt),
# then GREEN with the opening binding in place.
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
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft34.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
mark() {
  # Append the streamecho marker to the declaration header, pre-hash.
  python3 - "$1" <<'PY'
import sys, os
p = os.path.join(sys.argv[1], "invocation.txt")
lines = open(p, encoding="utf-8").read().splitlines(True)
lines[0] = lines[0].rstrip("\n") + " streamecho=v1\n"
open(p, "w", encoding="utf-8").write("".join(lines))
PY
}
echoline() {
  # Prepend the opening line the apparatus writes: run + declaration entry.
  python3 - "$1" "$2" "$3" <<'PY'
import sys, os
d, run, entry = sys.argv[1:4]
p = os.path.join(d, "stream.jsonl")
body = open(p, "rb").read()
line = ('{"type":"conformance_anchor","run":"%s","declarationEntry":"%s"}\n'
        % (run, entry)).encode("utf-8")
open(p, "wb").write(line + body)
PY
}
own_ledger() {
  # A ledger this fixture orders by hand (declaration first, echo between).
  if ! { git init -q --template= "$1" \
         && git -C "$1" config user.name t \
         && git -C "$1" config user.email t@example.invalid \
         && git -C "$1" config commit.gpgsign false; }; then
    echo "UNMEASURED: could not init ledger $1" >&2; exit 2
  fi
}
want() {
  # want DIR CODE REASON LABEL LEDGER
  d=$1; code=$2; reason=$3; label=$4; led=$5
  out="$(python3 "$VERIFY" "$d/statement.json" --ledger-repo "$led" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$code" -ne 0 ]; then
    echo "RED: $label verified CONFORMANT; the streamecho marker is not being read" >&2; exit 1
  fi
  [ "$rc" -eq "$code" ] || { echo "RED: $label exited $rc, expected $code" >&2; printf '%s\n' "$out" >&2; exit 1; }
  printf '%s\n' "$out" | grep -q "$reason" \
    || { echo "RED: $label exit $code without the expected reason ($reason)" >&2; printf '%s\n' "$out" >&2; exit 1; }
}

# control-old: the pre-echo protocol, untouched corpus record.
if ! python3 "$CORPUS" green "$WORK/old" \
   || ! bash "$ANCHORS" "$WORK/old" "$WORK/led-old" old >/dev/null \
   || ! python3 "$RECORD" "$WORK/old" "$WORK/old/statement.json" >/dev/null; then
  echo "UNMEASURED: pre-echo corpus or builder failed" >&2; exit 2
fi
python3 "$VERIFY" "$WORK/old/statement.json" --ledger-repo "$WORK/led-old" >/dev/null; rc=$?
[ "$rc" -eq 0 ] || { echo "UNMEASURED: pre-echo control not CONFORMANT (exit $rc)" >&2; exit 2; }

# arm-missing: the a-posteriori record the directive names -- marker
# present, deposits in the protocol order, the stream never carries the id.
python3 "$CORPUS" green "$WORK/miss" || { echo "UNMEASURED: corpus failed" >&2; exit 2; }
mark "$WORK/miss"
own_ledger "$WORK/led-miss"
dentry=$(bash "$ANCHOR" --ledger-repo "$WORK/led-miss" --run miss --role declaration --digest "$(sha "$WORK/miss/invocation.txt")") \
  || { echo "UNMEASURED: declaration anchor failed" >&2; exit 2; }
sentry=$(bash "$ANCHOR" --ledger-repo "$WORK/led-miss" --run miss --role stream --digest "$(sha "$WORK/miss/stream.jsonl")") \
  || { echo "UNMEASURED: stream anchor failed" >&2; exit 2; }
printf '{"declarationEntry":"%s","streamEntry":"%s"}\n' "$dentry" "$sentry" > "$WORK/miss/anchors.json"
python3 "$RECORD" "$WORK/miss" "$WORK/miss/statement.json" >/dev/null \
  || { echo "UNMEASURED: builder refused the marked run dir" >&2; exit 2; }
want "$WORK/miss" 2 "bound to its opening" "a-posteriori record (no echo)" "$WORK/led-miss"

# control-new: the echo protocol done right -- the id the chain deposited
# at open, first in the stream, then the stream deposit covers it.
python3 "$CORPUS" green "$WORK/new" || { echo "UNMEASURED: corpus failed" >&2; exit 2; }
mark "$WORK/new"
own_ledger "$WORK/led-new"
dentry=$(bash "$ANCHOR" --ledger-repo "$WORK/led-new" --run new --role declaration --digest "$(sha "$WORK/new/invocation.txt")") \
  || { echo "UNMEASURED: declaration anchor failed" >&2; exit 2; }
echoline "$WORK/new" new "$dentry"
sentry=$(bash "$ANCHOR" --ledger-repo "$WORK/led-new" --run new --role stream --digest "$(sha "$WORK/new/stream.jsonl")") \
  || { echo "UNMEASURED: stream anchor failed" >&2; exit 2; }
printf '{"declarationEntry":"%s","streamEntry":"%s"}\n' "$dentry" "$sentry" > "$WORK/new/anchors.json"
python3 "$RECORD" "$WORK/new" "$WORK/new/statement.json" >/dev/null \
  || { echo "UNMEASURED: builder refused the echoed run dir" >&2; exit 2; }
want "$WORK/new" 0 "CONFORMANT" "echoed record" "$WORK/led-new"

# arm-wrong-id: an echo line that names an id the chain never deposited
# for this declaration.
python3 "$CORPUS" green "$WORK/wrong" || { echo "UNMEASURED: corpus failed" >&2; exit 2; }
mark "$WORK/wrong"
own_ledger "$WORK/led-wrong"
dentry=$(bash "$ANCHOR" --ledger-repo "$WORK/led-wrong" --run wrong --role declaration --digest "$(sha "$WORK/wrong/invocation.txt")") \
  || { echo "UNMEASURED: declaration anchor failed" >&2; exit 2; }
echoline "$WORK/wrong" wrong "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
sentry=$(bash "$ANCHOR" --ledger-repo "$WORK/led-wrong" --run wrong --role stream --digest "$(sha "$WORK/wrong/stream.jsonl")") \
  || { echo "UNMEASURED: stream anchor failed" >&2; exit 2; }
printf '{"declarationEntry":"%s","streamEntry":"%s"}\n' "$dentry" "$sentry" > "$WORK/wrong/anchors.json"
python3 "$RECORD" "$WORK/wrong" "$WORK/wrong/statement.json" >/dev/null \
  || { echo "UNMEASURED: builder refused the wrong-id run dir" >&2; exit 2; }
want "$WORK/wrong" 2 "bound to its opening" "wrong-id record" "$WORK/led-wrong"

echo "GREEN: a stream that does not carry its declaration entry id refuses; the opening is read from the bytes, not assumed from the apparatus"
