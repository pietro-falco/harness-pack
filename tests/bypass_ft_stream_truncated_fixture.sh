#!/usr/bin/env bash
# FT-24 -- stream-truncated. A run interrupted mid-flight is INCOMPLETE and
# never a pass: no terminal result event and calls with no paired result
# license no verdict in either direction (an unpaired call could have been
# the one that left the surface -- ADR-023 D6 forbids reading it as either).
# GREEN: control CONFORMANT; the truncated run's own honest record exits 2
# naming INCOMPLETE. RED: the truncated record verifies 0, or 1 -- a
# truncated stream accuses nobody. UNMEASURED (2): machinery absent or
# control cannot be built.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="${CONFORMANCE_CORPUS:-$ROOT/tests/fixtures/conformance_corpus.py}"
RECORD="${CONFORMANCE_RECORD:-$ROOT/scripts/conformance_record.py}"
VERIFY="${CONFORMANCE_VERIFY:-$ROOT/scripts/conformance_verify.py}"
for f in "$CORPUS" "$RECORD" "$VERIFY"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft24.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
if ! python3 "$CORPUS" green "$WORK/green" \
   || ! python3 "$RECORD" "$WORK/green" "$WORK/green/statement.json" >/dev/null; then
  echo "UNMEASURED: green corpus or builder failed" >&2; exit 2
fi
python3 "$VERIFY" "$WORK/green/statement.json" >/dev/null; rc=$?
[ "$rc" -eq 0 ] || { echo "UNMEASURED: positive control not CONFORMANT (exit $rc)" >&2; exit 2; }
if ! python3 "$CORPUS" truncated "$WORK/cut" \
   || ! python3 "$RECORD" "$WORK/cut" "$WORK/cut/statement.json" >/dev/null; then
  echo "UNMEASURED: truncated corpus or builder failed" >&2; exit 2
fi
out="$(python3 "$VERIFY" "$WORK/cut/statement.json" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED: truncated run verified CONFORMANT; an interrupted stream passed" >&2; exit 1
fi
[ "$rc" -eq 2 ] || { echo "RED: truncated run exited $rc, expected 2 (incomplete)" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "INCOMPLETE" \
  || { echo "RED: exit 2 without INCOMPLETE named" >&2; exit 1; }
echo "GREEN: truncated stream INCOMPLETE (2), never a pass"
