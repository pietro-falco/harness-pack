#!/usr/bin/env bash
# FT-19 -- emitter-output-rejected-by-cli. The external gate the emitter was
# specified against: a malformed --agents value must be REJECTED by `claude`.
#
# 2026-08-13, CLI 2.1.231 -- RED. Measured on 2.1.231 it is NOT: `--agents
# '{"broken": '` is swallowed silently and the session runs without the agents,
# exit 0. The row stood RED to hold that defect visible: the CLI was not a
# validation gate, so the emitter's own static checks were the only gate an
# emission passed. That reading is NOT rewritten here. It is one half of the
# bisection below, and it is what makes the floor a fact instead of a taste.
#
# 2026-08-25 -- appended, not substituted. Bisected across every installed CLI,
# each run under its own PATH shim, each shim's `claude --version` read back
# inside the shim to prove the shim took:
#
#   2.1.237   exit 1   RED     malformed --agents accepted silently (exit 0)
#   2.1.241   exit 1   RED     malformed --agents accepted silently (exit 0)
#   2.1.245   exit 0   GREEN   malformed --agents rejected by the CLI (exit 1)
#
# The declared state is therefore GREEN, and GREEN at or above the floor only.
# The transition is LOCATED BETWEEN 2.1.241 and 2.1.245 and is NOT individuated:
# no CLI between those two is installed, so no run reachable from this tree can
# name the release that closed it. A declared limit is a fact; a limit left
# implied would be a claim, so it is spelled here rather than assumed.
#
# The subject of this row is an EXTERNAL gate. Its state is not a property of
# this tree and no commit here can move it -- which is why the row carries the
# version that produced each reading.
#
# RED (exit 1): the CLI accepts the malformed value silently.
# GREEN (exit 0): the CLI rejects it non-zero.
# UNMEASURED (2): no claude binary, the probe could not run at all, or the CLI
# is below the floor. In all three the row never reached its own question.
#
# Every run prints the observed CLI version, on EVERY branch -- GREEN, RED, and
# the ones that never reach the probe. Without that line a flip between GREEN
# and RED is a mystery; with it, it is attributable to the binary that made it.
set -u

# The floor: the LOWEST version this row has been observed GREEN on. Not the
# newest installed, and not a guess at where the fix landed. 2.1.241 measured
# RED and 2.1.245 measured GREEN, so every version below 2.1.245 is one this
# row has either seen fail or never seen at all. Either way it cannot speak for
# it, and a verdict it cannot speak for is worse than no verdict. Raise this
# only against a run, never against a release note.
FT19_CLI_FLOOR="2.1.245"

# Field-by-field numeric compare, no external tool: `sort -V` is not the same
# program on every host this runs on, and a floor read by a tool that may or
# may not support -V is not a floor. A version string that does not parse
# yields zeroes and lands below the floor, which is the safe side: it produces
# no verdict rather than a verdict about an unidentified binary.
ft19_below_floor() {
  local i h w
  local -a have want
  IFS=. read -r -a have <<<"$1"
  IFS=. read -r -a want <<<"$2"
  for i in 0 1 2; do
    h="${have[i]:-0}"; w="${want[i]:-0}"
    h="${h%%[!0-9]*}"; w="${w%%[!0-9]*}"
    [ -n "$h" ] || h=0
    [ -n "$w" ] || w=0
    if [ "$((10#$h))" -lt "$((10#$w))" ]; then return 0; fi
    if [ "$((10#$h))" -gt "$((10#$w))" ]; then return 1; fi
  done
  return 1
}

observed="absent"
if command -v claude >/dev/null 2>&1; then
  observed="$(claude --version 2>/dev/null | awk 'NR==1 {print $1}')"
  [ -n "$observed" ] || observed="unreadable"
fi
echo "FT-19 observed CLI version: $observed (floor $FT19_CLI_FLOOR)" >&2

if [ "$observed" = "absent" ]; then
  echo "UNMEASURED: claude binary absent" >&2
  exit 2
fi
if ft19_below_floor "$observed" "$FT19_CLI_FLOOR"; then
  echo "UNMEASURED: observed CLI $observed is not at or above the FT-19 floor $FT19_CLI_FLOOR, and below the floor this row returns no verdict. The header records RED at 2.1.231 and GREEN at 2.1.245; the transition sits between 2.1.241 and 2.1.245 and is not individuated, so a reading taken here would attribute a state to a version this row has never measured" >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft19.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
( cd "$WORK" && timeout 90 claude -p "Reply with exactly: OK" \
    --agents '{"broken": ' --max-turns 1 --model haiku \
    --output-format text >/dev/null 2>"$WORK/err" )
rc=$?
if [ "$rc" -eq 124 ]; then echo "UNMEASURED: probe timed out (CLI $observed)" >&2; exit 2; fi
if [ "$rc" -eq 0 ]; then
  echo "RED: malformed --agents accepted silently (exit 0) by CLI $observed; the CLI is not a gate" >&2
  exit 1
fi
echo "GREEN: malformed --agents rejected by CLI $observed (exit $rc)"
