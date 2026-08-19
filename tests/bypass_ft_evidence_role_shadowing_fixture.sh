#!/usr/bin/env bash
# FT-29 -- evidence-role-shadowing. The verifier indexes evidence by role;
# with last-wins iteration a record can carry TWO entries under one role and
# only the last is ever digest-checked -- the first is an evidence assertion
# no check touches (THR-COVER C9 survived exactly this way, carrying an
# all-zeros sha256 that nothing read). Every evidence entry a record asserts
# must be checked, so a duplicate role must be refused: NOT-RECOMPUTABLE,
# never a pass.
#
# TWO MUTANTS, one green control:
#   mut1  evidence = [bogus stream (sha256 = 64 zeros), declaration, stream]
#   mut2  evidence = [bogus declaration (sha256 = 64 zeros), declaration, stream]
# Each must exit 2 naming the duplicate evidence role.
#
# GREEN: control CONFORMANT; both mutants exit 2 naming the duplicate role.
# RED: any mutant exits 0 (the shadowed entry went unchecked), or exits with
# a code other than 2. UNMEASURED (2): machinery absent or control not
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
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft29.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
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
src, dst, role = sys.argv[1], sys.argv[2], sys.argv[3]
st = json.load(open(src))
ev = st["predicate"]["evidence"]
assert [x["role"] for x in ev] == ["declaration", "stream"], ev
name = next(x["name"] for x in ev if x["role"] == role)
bogus = {"name": name, "role": role, "sha256": "00" * 32}
st["predicate"]["evidence"] = [bogus] + ev
data = json.dumps(st, sort_keys=True, separators=(",", ":"),
                  ensure_ascii=False).encode("utf-8")
open(dst, "wb").write(data)
PY
}
check_mutant() {
  out="$(python3 "$VERIFY" "$1" --ledger-repo "$WORK/ledger" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "RED: $2 verified CONFORMANT; the shadowed evidence entry was never checked" >&2; exit 1
  fi
  [ "$rc" -eq 2 ] || { echo "RED: $2 exited $rc, expected 2" >&2; exit 1; }
  printf '%s\n' "$out" | grep -q "duplicate evidence role" \
    || { echo "RED: $2 exit 2 without the duplicate role named" >&2; printf '%s\n' "$out" >&2; exit 1; }
}
mutate "$WORK/green/statement.json" "$WORK/green/mut1.json" stream
check_mutant "$WORK/green/mut1.json" "shadowed stream record"
mutate "$WORK/green/statement.json" "$WORK/green/mut2.json" declaration
check_mutant "$WORK/green/mut2.json" "shadowed declaration record"
echo "GREEN: both duplicate-role records refused (2); every asserted entry is checked"
