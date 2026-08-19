#!/usr/bin/env bash
# conformance_anchor.sh -- pin one evidence digest into the interval ledger.
#
#   conformance_anchor.sh --ledger-repo DIR --run RUN \
#       --role declaration|stream --digest SHA256
#
# Apparatus-side tool: run by the launcher/watcher, never by the worker. It
# appends ONE entry to the append-only observation ledger
# (refs/observations/ledger, lanewright ADR-004) in the given ledger
# repository, under a compare-and-swap on the ledger ref. The entry's read
# scope is a one-line manifest file
#
#   anchors/RUN/ROLE.anchor  containing
#   "conformance-anchor/v1 run=RUN role=ROLE sha256=DIGEST\n"
#
# so the entry's gitBlob content-addresses the digest being anchored. A
# conformance record then cites the entry id; the verifier recomputes the
# manifest bytes from the record's own fields and compares blob ids -- the
# anchored bytes never need to be read back, only re-derived. What makes
# this an anchor: the ledger lives OUTSIDE the tree the record's author can
# write, and the chain is append-only under compare-and-swap, so an
# a-posteriori rewrite of evidence digests in a record diverges from an
# input the author cannot reach.
#
# The entry is a full interval-observation statement (opened == closed ==
# the ledger head at append: an instantaneous read, attached where it
# validated) and is adjudicable by lanewright's interval/verify.py
# unchanged. This writer uses git plumbing directly rather than calling
# observe.sh: an anchor needs no open interval, and the ratified contract
# is the entry format, not the worker tool.
#
# Exit codes: 0 appended (entry id on stdout); 2 usage or unreadable
# repo; 6 compare-and-swap lost three times.
set -euo pipefail

LEDGER_REF="refs/observations/ledger"
ZERO="0000000000000000000000000000000000000000"

# Deterministic entry objects, same posture as interval/observe.sh: fixed
# identity and dates, so the same manifest on the same parent yields the
# same entry id on every run.
export GIT_AUTHOR_NAME="conformance-anchor" GIT_AUTHOR_EMAIL="none@invalid"
export GIT_COMMITTER_NAME="conformance-anchor" GIT_COMMITTER_EMAIL="none@invalid"
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"

die() { printf 'conformance_anchor.sh: %s\n' "$*" >&2; exit 2; }

repo="" run="" role="" digest=""
while [ $# -gt 0 ]; do
  case $1 in
    --ledger-repo) repo=$2; shift 2 ;;
    --run) run=$2; shift 2 ;;
    --role) role=$2; shift 2 ;;
    --digest) digest=$2; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done
if [ -z "$repo" ] || [ -z "$run" ] || [ -z "$role" ] || [ -z "$digest" ]; then
  die "usage: conformance_anchor.sh --ledger-repo DIR --run RUN --role declaration|stream --digest SHA256"
fi
case $role in declaration|stream) ;; *) die "role must be declaration or stream, got: $role" ;; esac
printf '%s' "$digest" | grep -Eq '^[0-9a-f]{64}$' || die "digest is not 64 lowercase hex chars"
case $run in
  */*|*..*|*'*'*|*'?'*|*'['*) die "run name must be a single path segment with no glob chars: $run" ;;
esac
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository: $repo"

rel="anchors/$run/$role.anchor"
mkdir -p "$repo/anchors/$run"
printf 'conformance-anchor/v1 run=%s role=%s sha256=%s\n' "$run" "$role" "$digest" > "$repo/$rel"
blob=$(git -C "$repo" hash-object -w -- "$rel")

tries=0
while :; do
  head=$(git -C "$repo" rev-parse -q --verify "$LEDGER_REF" 2>/dev/null || printf '%s' "$ZERO")
  python3 - "$repo/.anchor-statement.json" "$rel" "$blob" "$head" <<'PY'
import json, sys
out, rel, blob, head = sys.argv[1:5]
st = {
    "_type": "https://in-toto.io/Statement/v1",
    "subject": [{"name": rel, "digest": {"gitBlob": blob}}],
    "predicateType": "https://pietrofalco.dev/attestation/interval-observation/v1",
    "predicate": {
        "ledger": {"ref": "refs/observations/ledger", "predecessor": head},
        "interval": {"opened": head, "closed": head},
        "scope": {"reads": [{"path": rel, "gitBlob": blob}], "writes": []},
        "basis": [{"argv": ["git", "hash-object", "--", rel], "exit": 0}],
        "invalidation": {"rule": "scope-intersection/v1"},
    },
}
with open(out, "w") as fh:
    json.dump(st, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
  stblob=$(git -C "$repo" hash-object -w -- ".anchor-statement.json")
  rm -f "$repo/.anchor-statement.json"
  tree=$(printf '100644 blob %s\tstatement.json\n' "$stblob" | git -C "$repo" mktree)
  if [ "$head" = "$ZERO" ]; then
    entry=$(git -C "$repo" commit-tree "$tree" -m "entry")
  else
    entry=$(git -C "$repo" commit-tree "$tree" -p "$head" -m "entry")
  fi
  # The one atomic step: three-argument update-ref succeeds only if the ref
  # still holds $head. A lost race re-reads the head and retries.
  if git -C "$repo" update-ref "$LEDGER_REF" "$entry" "$head" 2>/dev/null; then
    printf '%s\n' "$entry"
    exit 0
  fi
  tries=$((tries + 1))
  if [ "$tries" -ge 3 ]; then
    printf 'conformance_anchor.sh: compare-and-swap lost %d times, giving up\n' "$tries" >&2
    exit 6
  fi
done
