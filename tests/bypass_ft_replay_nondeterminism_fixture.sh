#!/usr/bin/env bash
# FT-25 -- replay-nondeterminism. Two verifications of the same record must
# produce the same exit code and the same bytes on stdout: a verifier whose
# verdict varies between replays is itself the defect, whatever it says
# about the record. Replayed on a conformant record AND on a divergent one,
# because determinism only on the happy path is not determinism.
# GREEN: both replays byte-identical with identical exits. RED: any
# divergence between replays. UNMEASURED (2): machinery absent or control
# cannot be built.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="${CONFORMANCE_CORPUS:-$ROOT/tests/fixtures/conformance_corpus.py}"
RECORD="${CONFORMANCE_RECORD:-$ROOT/scripts/conformance_record.py}"
VERIFY="${CONFORMANCE_VERIFY:-$ROOT/scripts/conformance_verify.py}"
for f in "$CORPUS" "$RECORD" "$VERIFY"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft25.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
if ! python3 "$CORPUS" green "$WORK/green" \
   || ! python3 "$RECORD" "$WORK/green" "$WORK/green/statement.json" >/dev/null \
   || ! python3 "$CORPUS" oos-run "$WORK/oos" \
   || ! python3 "$RECORD" "$WORK/oos" "$WORK/oos/statement.json" >/dev/null; then
  echo "UNMEASURED: corpus or builder failed" >&2; exit 2
fi
replay() {
  python3 "$VERIFY" "$1" > "$2.out1" 2>&1; rc1=$?
  python3 "$VERIFY" "$1" > "$2.out2" 2>&1; rc2=$?
  [ "$rc1" -eq "$rc2" ] || { echo "RED: $3 replay exits differ ($rc1 vs $rc2)" >&2; exit 1; }
  cmp -s "$2.out1" "$2.out2" \
    || { echo "RED: $3 replay outputs differ byte-wise" >&2; exit 1; }
}
replay "$WORK/green/statement.json" "$WORK/green/replay" "conformant record"
replay "$WORK/oos/statement.json" "$WORK/oos/replay" "divergent record"
echo "GREEN: replays byte-identical on conformant and divergent records"
