#!/usr/bin/env bash
# FT-20 -- out-of-surface-call-undetected. An executed call outside the
# declared surface must never verify 0, whether the divergence is in the run
# (honest record of a run that left its surface) or in the record (facts
# doctored after the fact). If either reaches 0, the record carries nothing.
# GREEN: control CONFORMANT (0); honest out-of-surface run DIVERGENT (1);
# doctored record non-zero. RED: any of the two reaches 0, or control drifts.
# UNMEASURED (2): the conformance machinery itself is absent or the positive
# control cannot be built.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="${CONFORMANCE_CORPUS:-$ROOT/tests/fixtures/conformance_corpus.py}"
RECORD="${CONFORMANCE_RECORD:-$ROOT/scripts/conformance_record.py}"
VERIFY="${CONFORMANCE_VERIFY:-$ROOT/scripts/conformance_verify.py}"
for f in "$CORPUS" "$RECORD" "$VERIFY"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft20.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
if ! python3 "$CORPUS" green "$WORK/green" \
   || ! python3 "$RECORD" "$WORK/green" "$WORK/green/statement.json" >/dev/null; then
  echo "UNMEASURED: green corpus or builder failed" >&2; exit 2
fi
python3 "$VERIFY" "$WORK/green/statement.json" >/dev/null; rc=$?
[ "$rc" -eq 0 ] || { echo "UNMEASURED: positive control not CONFORMANT (exit $rc)" >&2; exit 2; }
# (a) honest record of a run whose depth-2 Bash executed outside the surface
if ! python3 "$CORPUS" oos-run "$WORK/oos" \
   || ! python3 "$RECORD" "$WORK/oos" "$WORK/oos/statement.json" >/dev/null; then
  echo "UNMEASURED: oos corpus or builder failed" >&2; exit 2
fi
python3 "$VERIFY" "$WORK/oos/statement.json" >/dev/null; rc=$?
[ "$rc" -eq 1 ] || { echo "RED: out-of-surface execution verified exit $rc, expected 1" >&2; exit 1; }
# (b) doctored record: the rejected Bash flipped to an executed call
python3 - "$WORK/green/statement.json" <<'PY'
import json, sys
path = sys.argv[1]
st = json.load(open(path))
for entry in st["predicate"]["exercised"]:
    if entry["tool"] == "Bash":
        entry["result"] = "ok"
data = json.dumps(st, sort_keys=True, separators=(",", ":"),
                  ensure_ascii=False).encode("utf-8")
open(path, "wb").write(data)
PY
python3 "$VERIFY" "$WORK/green/statement.json" >/dev/null; rc=$?
[ "$rc" -ne 0 ] || { echo "RED: doctored record verified 0; the record carries nothing" >&2; exit 1; }
echo "GREEN: out-of-surface execution and doctored facts both refused"
