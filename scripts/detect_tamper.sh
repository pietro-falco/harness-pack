#!/usr/bin/env bash
# D4 detect gate (ADR-001): verify the enforced deploy still matches its pinned
# manifest — i.e. nothing was tampered under /opt/harness after deploy. Standalone
# and also called by `just verify`. Fail-closed: a missing enforced root or a
# missing/empty manifest is a STOP (exit 1), never a silent pass.
#
# Exit 0 = enforced tree matches MANIFEST.sha256 exactly.
# Exit 1 = mismatch, missing file, missing manifest, or missing enforced root.
set -euo pipefail

ENFORCED="${ENFORCED:-/opt/harness}"
MANIFEST_NAME="MANIFEST.sha256"

[ -d "$ENFORCED" ] || { echo "DETECT-FAIL: enforced root absent: $ENFORCED" >&2; exit 1; }
[ -s "$ENFORCED/$MANIFEST_NAME" ] || { echo "DETECT-FAIL: manifest missing or empty: $ENFORCED/$MANIFEST_NAME" >&2; exit 1; }

# shasum -c reads the manifest's relative paths; must run with cwd = enforced root.
# --status: no per-file output, exit code is the whole signal (0 all-match, 1 any-mismatch).
if ( cd "$ENFORCED" && shasum -a 256 -c "$MANIFEST_NAME" --status ); then
  echo "DETECT-OK: $ENFORCED matches $MANIFEST_NAME"
  exit 0
else
  echo "DETECT-FAIL: $ENFORCED diverges from $MANIFEST_NAME (tampered or incomplete)" >&2
  exit 1
fi
