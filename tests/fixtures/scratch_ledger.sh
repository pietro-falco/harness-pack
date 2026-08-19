#!/usr/bin/env bash
# scratch_ledger.sh -- per-fixture observation ledger, built in a throwaway
# repo so no fixture ever touches a real ledger.
#
#   scratch_ledger.sh EVIDENCE_DIR LEDGER_DIR RUN_NAME
#
# Initializes LEDGER_DIR as a git repository (identity pinned locally, same
# posture as the suite's other throwaway repos), anchors the sha256 of
# EVIDENCE_DIR/invocation.txt and EVIDENCE_DIR/stream.jsonl as two ledger
# entries via scripts/conformance_anchor.sh, and writes
# EVIDENCE_DIR/anchors.json with the two entry ids -- the file
# conformance_record.py requires before it will build a record.
# Idempotent per run name only in the append-only sense: calling it twice
# appends two more entries; anchors.json then cites the newest pair.
set -eu

if [ $# -ne 3 ]; then
  printf 'usage: scratch_ledger.sh EVIDENCE_DIR LEDGER_DIR RUN_NAME\n' >&2
  exit 2
fi
evd=$1 led=$2 run=$3
HERE="$(cd "$(dirname "$0")" && pwd)"
ANCHOR_TOOL="${CONFORMANCE_ANCHOR:-$HERE/../../scripts/conformance_anchor.sh}"
[ -f "$ANCHOR_TOOL" ] || { printf 'scratch_ledger.sh: anchor tool absent at %s\n' "$ANCHOR_TOOL" >&2; exit 2; }
[ -f "$evd/invocation.txt" ] || { printf 'scratch_ledger.sh: %s/invocation.txt absent\n' "$evd" >&2; exit 2; }
[ -f "$evd/stream.jsonl" ] || { printf 'scratch_ledger.sh: %s/stream.jsonl absent\n' "$evd" >&2; exit 2; }

if [ ! -d "$led/.git" ]; then
  git init -q "$led"
  git -C "$led" config user.name "scratch-ledger"
  git -C "$led" config user.email "none@invalid"
  git -C "$led" config commit.gpgsign false
fi

sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

dsha=$(sha "$evd/invocation.txt")
ssha=$(sha "$evd/stream.jsonl")
dentry=$(bash "$ANCHOR_TOOL" --ledger-repo "$led" --run "$run" --role declaration --digest "$dsha")
sentry=$(bash "$ANCHOR_TOOL" --ledger-repo "$led" --run "$run" --role stream --digest "$ssha")
printf '{"declarationEntry":"%s","streamEntry":"%s"}\n' "$dentry" "$sentry" > "$evd/anchors.json"
printf 'anchored %s: declaration %s stream %s\n' "$run" "$dentry" "$sentry"
