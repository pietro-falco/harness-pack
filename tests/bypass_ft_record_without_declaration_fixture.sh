#!/usr/bin/env bash
# FT-21 -- record-without-declaration. A run with no declared surface is NOT
# MEASURED, never a pass: absence of declaration is not conformity. Two ways
# a record can lack its declaration -- the declaration evidence entry removed,
# or the declaredSurface facts removed -- and both must exit 2 with the
# NOT-MEASURED verdict, never 0.
# GREEN: control CONFORMANT; both mutants exit 2 naming NOT-MEASURED.
# RED: any mutant exits 0, or exits without NOT-MEASURED. UNMEASURED (2):
# machinery absent or control cannot be built.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="${CONFORMANCE_CORPUS:-$ROOT/tests/fixtures/conformance_corpus.py}"
RECORD="${CONFORMANCE_RECORD:-$ROOT/scripts/conformance_record.py}"
VERIFY="${CONFORMANCE_VERIFY:-$ROOT/scripts/conformance_verify.py}"
for f in "$CORPUS" "$RECORD" "$VERIFY"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft21.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
if ! python3 "$CORPUS" green "$WORK/green" \
   || ! python3 "$RECORD" "$WORK/green" "$WORK/green/statement.json" >/dev/null; then
  echo "UNMEASURED: green corpus or builder failed" >&2; exit 2
fi
python3 "$VERIFY" "$WORK/green/statement.json" >/dev/null; rc=$?
[ "$rc" -eq 0 ] || { echo "UNMEASURED: positive control not CONFORMANT (exit $rc)" >&2; exit 2; }
check_mutant() {
  out="$(python3 "$VERIFY" "$1" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "RED: $2 verified 0; absence of declaration read as conformity" >&2; exit 1
  fi
  [ "$rc" -eq 2 ] || { echo "RED: $2 exited $rc, expected 2 (not measured)" >&2; exit 1; }
  printf '%s\n' "$out" | grep -q "NOT-MEASURED" \
    || { echo "RED: $2 exit 2 without NOT-MEASURED named" >&2; exit 1; }
}
mutate() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
src, dst, kind = sys.argv[1], sys.argv[2], sys.argv[3]
st = json.load(open(src))
if kind == "no-evidence":
    st["predicate"]["evidence"] = [
        e for e in st["predicate"]["evidence"] if e["role"] != "declaration"]
else:
    del st["predicate"]["declaredSurface"]
data = json.dumps(st, sort_keys=True, separators=(",", ":"),
                  ensure_ascii=False).encode("utf-8")
open(dst, "wb").write(data)
PY
}
mutate "$WORK/green/statement.json" "$WORK/green/mut1.json" no-evidence
check_mutant "$WORK/green/mut1.json" "record without declaration evidence"
mutate "$WORK/green/statement.json" "$WORK/green/mut2.json" no-surface
check_mutant "$WORK/green/mut2.json" "record without declaredSurface"
echo "GREEN: both declaration-less records NOT-MEASURED (2), never a pass"
