#!/usr/bin/env bash
# FT-22 -- depth-collapse. A call exercised at depth 2 recorded as depth 1 is
# a wrong delegation tree, and verify must notice: the tree is recomputed
# from parent_tool_use_id chains in the evidence, never taken from the
# record's own claim (the hook ledger is depth-blind -- ADR-023 C2b -- which
# is why the chain is the source of truth). Two collapses tried: an
# exercised entry's depth, and a delegation edge's depth.
# GREEN: control CONFORMANT; both collapsed records DIVERGENT (1).
# RED: either collapse verifies 0 or anything other than 1.
# UNMEASURED (2): machinery absent or control cannot be built.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="${CONFORMANCE_CORPUS:-$ROOT/tests/fixtures/conformance_corpus.py}"
RECORD="${CONFORMANCE_RECORD:-$ROOT/scripts/conformance_record.py}"
VERIFY="${CONFORMANCE_VERIFY:-$ROOT/scripts/conformance_verify.py}"
for f in "$CORPUS" "$RECORD" "$VERIFY"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft22.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
if ! python3 "$CORPUS" green "$WORK/green" \
   || ! python3 "$RECORD" "$WORK/green" "$WORK/green/statement.json" >/dev/null; then
  echo "UNMEASURED: green corpus or builder failed" >&2; exit 2
fi
python3 "$VERIFY" "$WORK/green/statement.json" >/dev/null; rc=$?
[ "$rc" -eq 0 ] || { echo "UNMEASURED: positive control not CONFORMANT (exit $rc)" >&2; exit 2; }
collapse() {
  python3 - "$WORK/green/statement.json" "$1" "$2" <<'PY'
import json, sys
src, dst, kind = sys.argv[1], sys.argv[2], sys.argv[3]
st = json.load(open(src))
pred = st["predicate"]
if kind == "exercised":
    for entry in pred["exercised"]:
        if entry["depth"] == 2:
            entry["depth"] = 1
    pred["exercised"].sort(key=lambda e: (e["depth"], e["toolUseId"]))
else:
    for edge in pred["delegations"]:
        if edge["depth"] == 1:
            edge["depth"] = 0
    pred["delegations"].sort(key=lambda d: (d["depth"], d["toolUseId"]))
data = json.dumps(st, sort_keys=True, separators=(",", ":"),
                  ensure_ascii=False).encode("utf-8")
open(dst, "wb").write(data)
PY
}
collapse "$WORK/green/mut-exercised.json" exercised
python3 "$VERIFY" "$WORK/green/mut-exercised.json" >/dev/null; rc=$?
[ "$rc" -eq 1 ] || { echo "RED: depth-collapsed exercised list verified exit $rc, expected 1" >&2; exit 1; }
collapse "$WORK/green/mut-delegation.json" delegation
python3 "$VERIFY" "$WORK/green/mut-delegation.json" >/dev/null; rc=$?
[ "$rc" -eq 1 ] || { echo "RED: depth-collapsed delegation tree verified exit $rc, expected 1" >&2; exit 1; }
echo "GREEN: both depth collapses caught by recomputation (DIVERGENT)"
