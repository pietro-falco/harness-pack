#!/usr/bin/env bash
# FT-7 -- appended-prompt-negative-control. COMMIT 2 proves propagation with a
# 16-hex token that exists ONLY in the --append-subagent-system-prompt text;
# the proof is only as good as its negative control. This row asserts the
# recorded pair: C2pos produced <token>.marker at depth 2, C2neg produced
# control.marker with the token appearing nowhere (0 stream occurrences).
# GREEN: both halves hold. RED: either fails -- a token that appears in the
# negative control means the token leaked into a channel the flag does not
# own, and the depth-2 proof is void. UNMEASURED (2): no recorded run.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="${THR_SUBAGENT_RUN:-}"
[ -z "$RUN" ] && [ -f "$ROOT/runs/THR-SUBAGENT/.current" ] && RUN="$(cat "$ROOT/runs/THR-SUBAGENT/.current")"
POS="${THR_C2POS:-$RUN/arms/C2pos/evidence.txt}"
NEG="${THR_C2NEG:-$RUN/arms/C2neg/evidence.txt}"
if ! { [ -f "$POS" ] && [ -f "$NEG" ]; }; then echo "UNMEASURED: C2pos/C2neg evidence not recorded" >&2; exit 2; fi
grep -q "token marker: PRESENT" "$POS" || { echo "RED: positive run has no token marker at depth 2" >&2; exit 1; }
grep -q "token marker: ABSENT" "$NEG" || { echo "RED: negative control produced a token marker" >&2; exit 1; }
grep -q "control marker: PRESENT" "$NEG" || { echo "RED: negative control did not produce control.marker" >&2; exit 1; }
grep -q "token in stream.jsonl: 0" "$NEG" || { echo "RED: token leaked into the negative-control stream" >&2; exit 1; }
echo "GREEN: token only where the flag put it; negative control clean"
