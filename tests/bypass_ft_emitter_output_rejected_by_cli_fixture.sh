#!/usr/bin/env bash
# FT-19 -- emitter-output-rejected-by-cli. The external gate the emitter was
# specified against: a malformed --agents value must be REJECTED by `claude`.
# Measured on 2.1.231 (2026-08-13) it is NOT: `--agents '{"broken": '` is
# swallowed silently and the session runs without the agents, exit 0. This row
# stands RED to hold that defect visible: the CLI is not a validation gate, so
# the emitter's own static checks are the only gate an emission passes.
# RED (exit 1): the CLI accepts the malformed value silently (today's state).
# GREEN: a future CLI rejects it non-zero. UNMEASURED (2): no claude binary,
# or the probe could not run at all (this row needs a live CLI and a model).
set -u
command -v claude >/dev/null 2>&1 || { echo "UNMEASURED: claude binary absent" >&2; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft19.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
( cd "$WORK" && timeout 90 claude -p "Reply with exactly: OK" \
    --agents '{"broken": ' --max-turns 1 --model haiku \
    --output-format text >/dev/null 2>"$WORK/err" )
rc=$?
if [ "$rc" -eq 124 ]; then echo "UNMEASURED: probe timed out" >&2; exit 2; fi
if [ "$rc" -eq 0 ]; then
  echo "RED: malformed --agents accepted silently (exit 0); the CLI is not a gate" >&2
  exit 1
fi
echo "GREEN: malformed --agents rejected by the CLI (exit $rc)"
