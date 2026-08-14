#!/usr/bin/env bash
# FT-26 -- unused-authorization-unreported. The record does not only say
# whether the execution stayed inside its surface; it must also say how much
# of the surface went unused -- that is the detection of a bound wider than
# the need, and the input every narrowing proposal recomputes from. A record
# that hides a declared-never-executed capability must not verify.
# GREEN: the honest record NAMES the unused authorization (Read) and
# verifies 0; the record with unusedAuthorizations emptied is DIVERGENT (1).
# RED: the hiding record verifies 0, or the honest record fails to name the
# unused capability. UNMEASURED (2): machinery absent or control broken.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="${CONFORMANCE_CORPUS:-$ROOT/tests/fixtures/conformance_corpus.py}"
RECORD="${CONFORMANCE_RECORD:-$ROOT/scripts/conformance_record.py}"
VERIFY="${CONFORMANCE_VERIFY:-$ROOT/scripts/conformance_verify.py}"
for f in "$CORPUS" "$RECORD" "$VERIFY"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft26.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
if ! python3 "$CORPUS" green "$WORK/green" \
   || ! python3 "$RECORD" "$WORK/green" "$WORK/green/statement.json" >/dev/null; then
  echo "UNMEASURED: green corpus or builder failed" >&2; exit 2
fi
python3 - "$WORK/green/statement.json" <<'PY' || { echo "RED: honest record does not name Read as unused" >&2; exit 1; }
import json, sys
st = json.load(open(sys.argv[1]))
sys.exit(0 if st["predicate"]["unusedAuthorizations"] == ["Read"] else 1)
PY
python3 "$VERIFY" "$WORK/green/statement.json" >/dev/null; rc=$?
[ "$rc" -eq 0 ] || { echo "UNMEASURED: positive control not CONFORMANT (exit $rc)" >&2; exit 2; }
python3 - "$WORK/green/statement.json" "$WORK/green/mut.json" <<'PY'
import json, sys
st = json.load(open(sys.argv[1]))
st["predicate"]["unusedAuthorizations"] = []
data = json.dumps(st, sort_keys=True, separators=(",", ":"),
                  ensure_ascii=False).encode("utf-8")
open(sys.argv[2], "wb").write(data)
PY
python3 "$VERIFY" "$WORK/green/mut.json" >/dev/null; rc=$?
[ "$rc" -eq 1 ] || { echo "RED: record hiding an unused authorization verified exit $rc, expected 1" >&2; exit 1; }
echo "GREEN: unused authorization named by the record and its hiding caught"
