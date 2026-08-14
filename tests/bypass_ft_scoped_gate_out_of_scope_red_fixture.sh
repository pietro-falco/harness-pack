#!/usr/bin/env bash
# FT-12 -- scoped-gate-passes-on-out-of-scope-red. The harness-threads gate
# cannot distinguish "the tracker is stale" from "this workspace is usable":
# staleness detection and progress measurement are the same comparison, so
# exit 1 is the NORMAL state after any productive work, and a session that
# treats the gate as a go/no-go signal is reading somebody else's red.
#
# THE SUBJECT is 80-governance/harness/harness-threads-gate.py in the vault,
# measured as deployed there -- never patched in place by this fixture, because
# 80-governance/ is human-write-exclusive. The repair is emitted as
# tests/fixtures/gate-scope-argument.diff and lands only by operator hand.
#
# THE QUESTION, put to a synthetic two-thread tracker so the answer cannot
# drift with the live one: given --scope <THREAD-ID>,
#   - a fact RED outside the scope must yield exit 0
#   - a fact RED inside the scope must yield exit 1
#   - a scope naming no thread must yield exit 2 (unmeasurable, accuses nothing)
#
# STATES. RED (exit 1): the deployed gate has no --scope argument, or has one
# with inverted semantics -- the defect this row exists to hold visible. GREEN
# (exit 0): the deployed gate answers all three questions correctly. UNMEASURED
# (exit 2): the vault gate is not on this machine (fresh CI clone) -- the row
# never reached its question. Observed RED against vault@ce4bc76 on 2026-08-13,
# where `--scope` is an unrecognized argument.
set -u

GATE="${HARNESS_GATE:-$HOME/Obsidian-Vault/80-governance/harness/harness-threads-gate.py}"
if [ ! -f "$GATE" ]; then
  echo "UNMEASURED: gate not found at $GATE" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "UNMEASURED: python3 absent" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft12.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

TRACKER="$WORK/synthetic-tracker.json"
cat > "$TRACKER" <<'JSON'
{
  "schema": "harness-threads/v1",
  "title": "FT-12 synthetic tracker",
  "note": "two threads, one green fact in scope, one red fact out of scope",
  "fact_classes": {"anchor": "no target", "progress": "target"},
  "active": null,
  "repos": {"harness-pack": "."},
  "threads": [
    {"id": "SCOPE-IN", "status": "READY", "owns": [], "reads": [],
     "blocked_by": null, "closure_note": "synthetic; closed by deletion",
     "cited_facts": [
       {"id": "IN-1", "claim": "the constitution file exists once",
        "kind": "glob_count", "repo": "harness-pack",
        "pattern": "CONSTITUTION.md", "expected": 1}]},
    {"id": "SCOPE-OUT", "status": "READY", "owns": [], "reads": [],
     "blocked_by": null, "closure_note": "synthetic; closed by deletion",
     "cited_facts": [
       {"id": "OUT-1", "claim": "a file that never exists is present",
        "kind": "glob_count", "repo": "harness-pack",
        "pattern": "ft12_no_such_file_*", "expected": 1}]}
  ]
}
JSON

run_scoped() {
  python3 "$GATE" --tracker "$TRACKER" --repo "harness-pack=$ROOT" \
    --no-state --scope "$1" >"$WORK/out.$1" 2>&1
}

# Probe: does the deployed gate know --scope at all?
if run_scoped SCOPE-IN; then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ]; then
  if grep -q "unrecognized arguments" "$WORK/out.SCOPE-IN"; then
    echo "RED: deployed gate has no --scope argument (exit $rc)" >&2
    exit 1
  fi
  echo "RED: --scope SCOPE-IN with only out-of-scope red gave exit $rc, want 0" >&2
  exit 1
fi

run_scoped SCOPE-OUT
rc_in=$?
if [ "$rc_in" -ne 1 ]; then
  echo "RED: --scope SCOPE-OUT with an in-scope red gave exit $rc_in, want 1" >&2
  exit 1
fi

run_scoped NO-SUCH-THREAD
rc_unknown=$?
if [ "$rc_unknown" -ne 2 ]; then
  echo "RED: --scope naming no thread gave exit $rc_unknown, want 2" >&2
  exit 1
fi

echo "GREEN: scoped gate separates in-scope red (1) from out-of-scope red (0)"
exit 0
