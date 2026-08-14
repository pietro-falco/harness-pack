#!/usr/bin/env bash
# FT-23 -- narration-only-evidence. A record sustained by a model's summary
# instead of machine facts is refused: the predicate vocabulary is CLOSED,
# so a prose field cannot even enter the record without making it
# NOT-RECOMPUTABLE. Two shapes tried: prose ADDED beside valid facts, and
# prose REPLACING the facts.
# GREEN: control CONFORMANT; both narrated records exit 2 naming
# NOT-RECOMPUTABLE. RED: either verifies 0 or exits without the verdict.
# UNMEASURED (2): machinery absent or control cannot be built.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="${CONFORMANCE_CORPUS:-$ROOT/tests/fixtures/conformance_corpus.py}"
RECORD="${CONFORMANCE_RECORD:-$ROOT/scripts/conformance_record.py}"
VERIFY="${CONFORMANCE_VERIFY:-$ROOT/scripts/conformance_verify.py}"
for f in "$CORPUS" "$RECORD" "$VERIFY"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft23.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
if ! python3 "$CORPUS" green "$WORK/green" \
   || ! python3 "$RECORD" "$WORK/green" "$WORK/green/statement.json" >/dev/null; then
  echo "UNMEASURED: green corpus or builder failed" >&2; exit 2
fi
python3 "$VERIFY" "$WORK/green/statement.json" >/dev/null; rc=$?
[ "$rc" -eq 0 ] || { echo "UNMEASURED: positive control not CONFORMANT (exit $rc)" >&2; exit 2; }
narrate() {
  python3 - "$WORK/green/statement.json" "$1" "$2" <<'PY'
import json, sys
src, dst, kind = sys.argv[1], sys.argv[2], sys.argv[3]
st = json.load(open(src))
prose = ("the run stayed comfortably within its declared surface and "
         "no anomalous behavior was observed")
if kind == "beside":
    st["predicate"]["narrative"] = prose
else:
    st["predicate"]["exercised"] = []
    st["predicate"]["delegations"] = []
    st["predicate"]["summaryOfActivity"] = prose
data = json.dumps(st, sort_keys=True, separators=(",", ":"),
                  ensure_ascii=False).encode("utf-8")
open(dst, "wb").write(data)
PY
}
check_refused() {
  out="$(python3 "$VERIFY" "$1" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "RED: $2 verified 0; a narrated record passed as evidence" >&2; exit 1
  fi
  [ "$rc" -eq 2 ] || { echo "RED: $2 exited $rc, expected 2" >&2; exit 1; }
  printf '%s\n' "$out" | grep -q "NOT-RECOMPUTABLE" \
    || { echo "RED: $2 exit 2 without NOT-RECOMPUTABLE named" >&2; exit 1; }
}
narrate "$WORK/green/mut-beside.json" beside
check_refused "$WORK/green/mut-beside.json" "prose beside the facts"
narrate "$WORK/green/mut-instead.json" instead
check_refused "$WORK/green/mut-instead.json" "prose instead of the facts"
echo "GREEN: narrated records refused; only machine facts enter the record"
