#!/bin/sh
printf '{"scope":"%s","payload":%s}\n' "${HARNESS_SCOPE:-UNSET}" "$(cat)" \
  >> "${SEAM_LEDGER_DIR:?}/pretooluse.jsonl"
