#!/bin/sh
printf '{"at":"%s","payload":%s}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(cat)" \
  >> "${SEAM_LEDGER_DIR:?}/spawn.jsonl"
