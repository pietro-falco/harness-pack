#!/usr/bin/env bash
# FT-28 -- typed-equality-bool-int. The verifier's fact comparison must be a
# comparison of JSON values, not of Python values: Python's == identifies
# True with 1, so a record carrying `true` where the stream gives the integer
# 1 (or 1 where the stream gives `true`) would compare equal to the recomputed
# facts and verify CONFORMANT. THR-COVER measured exactly that survival (C5).
# A wrong-typed record is not the record of the run; it must be DIVERGENT.
#
# TWO MUTANTS, one green control:
#   mut1  exercised[i].depth   integer 1 -> JSON true
#   mut2  completeness.streamResultEvent JSON true -> integer 1
# Each must exit 1 DIVERGENT naming the fact list that diverged.
#
# GREEN: control CONFORMANT; both mutants exit 1 with the named reason.
# RED: any mutant exits 0 (bool/int identification survives), or exits with
# a code other than 1. UNMEASURED (2): machinery absent or control not
# CONFORMANT.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="${CONFORMANCE_CORPUS:-$ROOT/tests/fixtures/conformance_corpus.py}"
RECORD="${CONFORMANCE_RECORD:-$ROOT/scripts/conformance_record.py}"
VERIFY="${CONFORMANCE_VERIFY:-$ROOT/scripts/conformance_verify.py}"
ANCHORS="${SCRATCH_LEDGER:-$ROOT/tests/fixtures/scratch_ledger.sh}"
for f in "$CORPUS" "$RECORD" "$VERIFY" "$ANCHORS"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft28.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
if ! python3 "$CORPUS" green "$WORK/green" \
   || ! bash "$ANCHORS" "$WORK/green" "$WORK/ledger" green >/dev/null \
   || ! python3 "$RECORD" "$WORK/green" "$WORK/green/statement.json" >/dev/null; then
  echo "UNMEASURED: green corpus or builder failed" >&2; exit 2
fi
python3 "$VERIFY" "$WORK/green/statement.json" --ledger-repo "$WORK/ledger" >/dev/null; rc=$?
[ "$rc" -eq 0 ] || { echo "UNMEASURED: positive control not CONFORMANT (exit $rc)" >&2; exit 2; }
mutate() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
src, dst, kind = sys.argv[1], sys.argv[2], sys.argv[3]
st = json.load(open(src))
pred = st["predicate"]
if kind == "depth-bool":
    hit = [e for e in pred["exercised"] if e["depth"] == 1 and e["tool"] == "Write"]
    assert hit and hit[0]["depth"] is not True, hit
    hit[0]["depth"] = True
else:
    assert pred["completeness"]["streamResultEvent"] is True
    pred["completeness"]["streamResultEvent"] = 1
data = json.dumps(st, sort_keys=True, separators=(",", ":"),
                  ensure_ascii=False).encode("utf-8")
assert (b'"depth":true' in data) or (b'"streamResultEvent":1' in data)
open(dst, "wb").write(data)
PY
}
check_mutant() {
  out="$(python3 "$VERIFY" "$1" --ledger-repo "$WORK/ledger" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "RED: $2 verified CONFORMANT; the equality predicate identifies bool with int" >&2; exit 1
  fi
  [ "$rc" -eq 1 ] || { echo "RED: $2 exited $rc, expected 1 (DIVERGENT)" >&2; exit 1; }
  printf '%s\n' "$out" | grep -q "$3" \
    || { echo "RED: $2 exit 1 without the expected reason ($3)" >&2; printf '%s\n' "$out" >&2; exit 1; }
}
mutate "$WORK/green/statement.json" "$WORK/green/mut1.json" depth-bool
check_mutant "$WORK/green/mut1.json" "depth true-for-1 record" \
  "record exercised list differs"
mutate "$WORK/green/statement.json" "$WORK/green/mut2.json" completeness-int
check_mutant "$WORK/green/mut2.json" "completeness 1-for-true record" \
  "record completeness differs"
echo "GREEN: both wrong-typed records DIVERGENT (1); bool is not int here"
