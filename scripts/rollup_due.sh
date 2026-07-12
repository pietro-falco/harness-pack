#!/usr/bin/env bash
# RS-001 trigger check. Counts loose *.receipt.json in RECEIPTS_DIR;
# exit 0 = due (count >= ROLLUP_THRESHOLD), exit 1 = not due.
# Env: RECEIPTS_DIR (default: ./.harness/pack/receipts),
#      ROLLUP_THRESHOLD (default: 25)
set -euo pipefail
RECEIPTS_DIR="${RECEIPTS_DIR:-./.harness/pack/receipts}"
ROLLUP_THRESHOLD="${ROLLUP_THRESHOLD:-25}"

if [ ! -d "$RECEIPTS_DIR" ]; then
  exit 1
fi

count=$(find "$RECEIPTS_DIR" -maxdepth 1 -name '*.receipt.json' -type f | wc -l)
[ "$count" -ge "$ROLLUP_THRESHOLD" ]
