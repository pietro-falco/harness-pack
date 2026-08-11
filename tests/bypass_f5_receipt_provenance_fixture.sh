#!/usr/bin/env bash
# F5 -- the receipt records neither the prompt the run was given nor a single
# call it made, and the identity it does record comes from a filename.
#
# THE SUBJECT is scripts/write_receipt.py's composition (:131-148), the
# contract templates/receipt.schema.json declares, and the identity path
# launch_worker.sh:94 -> :156 -> :377 hands the writer.
#
# TWO ROWS, and they fail the same reader for different reasons.
#
#   A  WHAT WAS DONE. The receipt carries no prompt, no digest of the prompt,
#      and no record of any tool call the child made. Its one per-call channel
#      is `refusals`, which is denials-only by construction: a run that wrote
#      forty files with nothing refused and a run that did nothing at all
#      compose the same `refusals.count: 0`. The composition is hash-chained
#      (scripts/receipt_chain.py) -- so what the chain proves untampered is a
#      record of the OUTCOME, next to nothing about the ACT.
#
#      The one near-miss is `session_id`, and it is not the exception: it is a
#      name for a file somewhere on the machine that ran the child, it is not
#      hashed into the chain, and nothing requires it to still exist. A pointer
#      to a transcript is not a transcript.
#
#      The launcher's own behaviour one screen away is the discrimination this
#      row rests on: it DOES pin bytes it cares about. CONSTITUTION.md is
#      sha256'd and the digest is written into the receipt (:189, :379). The
#      spec is opened as the child's stdin (:342) and hashed nowhere.
#
#   B  WHO DID IT. `spec_id` is the spec FILENAME. :94 takes REQUESTED_ID from
#      `basename "$SPEC" .md`; the decision block requires the planner's id to
#      equal it (:129-130); :377 hands that string to the writer as SPEC_ID.
#      The spec's CONTENT is never parsed -- ADR-005 D1 says the launcher is
#      not the dialect's second reader, and this row does not dispute that
#      decision. What it registers is the consequence the decision leaves
#      unhandled: rename a file and the receipt attributes the same bytes to a
#      different slice; keep the name and change every word inside it, and the
#      receipt cannot tell.
#
# Row B is measured by running the real launcher twice with LAUNCH_DRYRUN=1 --
# past every pack-side gate, before any write or spawn (:180-183) -- over two
# spec files whose names and bodies are crossed. `next --json` and the verity
# CLI are stubs; everything between them is the real launcher. HARNESS_MANIFEST
# is pinned to the pack's example so the row does not depend on the operator's
# exported manifest.
#
# Exit codes: 0 both invariants hold, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
WRITER="$PACK/scripts/write_receipt.py"
LAUNCHER="$PACK/scripts/launch_worker.sh"
SCHEMA="$PACK/templates/receipt.schema.json"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-f5.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$WRITER" ]   || broken "scripts/write_receipt.py is not where this fixture expects it"
[ -f "$LAUNCHER" ] || broken "scripts/launch_worker.sh is not where this fixture expects it"
[ -f "$SCHEMA" ]   || broken "templates/receipt.schema.json is not where this fixture expects it"

echo "== F5 the receipt records the outcome, not the act =="

# ---- row A: what was done --------------------------------------------------
# A child that worked: three turns, a session, nothing refused. This is the
# shape `claude -p --output-format json` returns, which is all the writer ever
# sees of the run.
cat > "$WORK/cc_worked.json" <<'J'
{"subtype": "success", "num_turns": 3, "is_error": false, "total_cost_usd": 0.44,
 "duration_ms": 91000, "session_id": "sess-worked", "permission_denials": []}
J
GJ='{"verdict":"PASS","reason":"all declared criteria PASS","verity_exit":0,"claims":[{"id":"C-1","type":"command","verdict":"PASS","evidence":"e"}]}'
BJ='{"verdict":"FAIL","reason":"criteria failed: C-1","verity_exit":1,"claims":[{"id":"C-1","type":"command","verdict":"FAIL","evidence":"e"}]}'

CC_EXIT=0 GATE_JSON="$GJ" BASELINE_JSON="$BJ" \
  RUN_ID=run-f5 SPEC_ID=S-042 MODEL_STRING=executor TIER_RESOLVED=T2 \
  MODEL_USED=SONNET_CLASS_MODEL MANIFEST_VERSION=1 CONSTITUTION_HASH=fixture-hash \
  TOOL_VERSION=fixture STARTED_AT=2026-08-11T00:00:00Z ENDED_AT=2026-08-11T00:01:31Z \
  python3 "$WRITER" "$WORK/cc_worked.json" "$WORK/worked.receipt.json" \
  >/dev/null 2>"$WORK/err" \
  || broken "the writer did not compose the worked run: $(head -c 300 "$WORK/err")"

# Every key name in the composed receipt, and in the declared schema, walked
# recursively -- a provenance field nested under gate or contribution would
# count, so the search is not top-level only.
keys_matching() {  # keys_matching <json file> <regex>
  python3 - "$1" "$2" <<'PY'
import json, re, sys
pat = re.compile(sys.argv[2], re.I)
hits = []
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if pat.search(str(k)):
                hits.append(k)
            walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
walk(json.load(open(sys.argv[1])))
print(",".join(sorted(set(hits))) or "-")
PY
}
PROV='prompt|spec_sha|spec_hash|spec_digest|transcript|tool_call|tool_use|actions|edits|writes|diff|files_changed'
R_PROV="$(keys_matching "$WORK/worked.receipt.json" "$PROV")"
S_PROV="$(keys_matching "$SCHEMA" "$PROV")"
R_REFUSALS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("refusals",{}).get("count"))' "$WORK/worked.receipt.json")"
R_SESSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("session_id"))' "$WORK/worked.receipt.json")"

# The discrimination: the launcher pins the bytes it cares about. Both counts
# are read off the real launcher, not asserted.
CONST_PINNED="$(grep -c 'check-hash' "$LAUNCHER")"
SPEC_HASHED="$(grep -n 'SPEC' "$LAUNCHER" | grep -cE 'sha|hashlib|shasum|digest')"
[ "$CONST_PINNED" -gt 0 ] \
  || broken "the launcher no longer hashes the constitution; the contrast this row rests on has moved"

ROW_A="GREEN"
if [ "$R_PROV" = "-" ] && [ "$S_PROV" = "-" ] && [ "$SPEC_HASHED" -eq 0 ]; then
  ROW_A="RED"
  echo "RED [F5-A] nothing in the receipt says what the run did"
  note "provenance-shaped keys in the composed receipt : $R_PROV"
  note "provenance-shaped keys in the declared schema  : $S_PROV"
  note "the only per-call channel is refusals, and it is denials-only:"
  note "  this run made 3 turns with nothing refused -> refusals.count=$R_REFUSALS"
  note "  a run that did nothing at all composes the same 0"
  note "session_id=$R_SESSION is a name for a file on the machine that ran the"
  note "child; it is not hashed into receipt-chain.jsonl and nothing keeps it alive"
  note "the launcher sha256s CONSTITUTION.md and writes the digest into the"
  note "receipt ($CONST_PINNED check-hash call(s)); the spec it feeds the child on"
  note "stdin (launch_worker.sh:342) is hashed on $SPEC_HASHED lines"
  note "so the hash chain proves an outcome record untampered while saying"
  note "nothing about the act that produced it"
  note "green when the receipt pins a digest of the prompt actually sent and"
  note "carries a record of the calls the child made, not only the refused ones"
else
  echo "GREEN [F5-A] the receipt carries provenance"
  note "receipt keys=$R_PROV schema keys=$S_PROV spec-hashing lines=$SPEC_HASHED"
fi

# ---- row B: who did it ------------------------------------------------------
ROW_B="UNMEASURED"
if ! command -v node >/dev/null 2>&1; then
  note "row B UNMEASURED: node is absent and the launcher reaches 'next --json' through it"
else
  REPO="$WORK/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@example.invalid
  git -C "$REPO" config user.name tester
  git -C "$REPO" config commit.gpgsign false
  git -C "$REPO" config tag.gpgsign false
  : > "$REPO/keep"
  git -C "$REPO" add -- keep >/dev/null 2>&1
  git -C "$REPO" commit -q -m "fixture: seed commit" >/dev/null 2>&1 \
    || broken "could not seed the throwaway repo"
  cat > "$WORK/hw.js" <<'JS'
// Stub of `harnesswright next --json`: the planner is on slice S-042.
// scope is REQUIRED of a mode B spec by templates/spec.mode-b.template.md:21 and
// the launcher gates on it; the value is legal, repo-relative, and irrelevant to
// the identity question this fixture asks, which is decided from the filename.
if (process.argv[2] === "next") {
  process.stdout.write(JSON.stringify({
    kind: "unlocked", id: "S-042", eligible_mode_b: true,
    spec: { model: "executor", tools: ["Bash"], criteria: ["C-1"],
            budget: { turns: 3, wall_clock: "5m" }, scope: ["src/"] }
  }));
  process.exit(0);
}
process.exit(1);
JS
  printf 'process.exit(0);\n' > "$WORK/verity.js"

  # Crossed on purpose: the NAME of one is the declared id of the other.
  printf -- '---\nid: S-SOMETHING-ELSE\ntier: T2\nmode: B\n---\nbody one\n' > "$REPO/S-042.md"
  printf -- '---\nid: S-042\ntier: T2\nmode: B\n---\nbody two\n' > "$REPO/S-SOMETHING-ELSE.md"

  launch() {
    ( cd "$REPO" && LAUNCH_DRYRUN=1 \
        HARNESSWRIGHT_CLI="$WORK/hw.js" VERITY_CLI="$WORK/verity.js" \
        HARNESS_MANIFEST="$PACK/templates/manifest.example.json" \
        bash "$LAUNCHER" "$REPO/$1" ) >"$WORK/launch.out" 2>&1
    echo $?
  }
  NAMED_RC="$(launch S-042.md)"
  NAMED_OUT="$(grep -m1 'DRYRUN\|STOP' "$WORK/launch.out")"
  CONTENT_RC="$(launch S-SOMETHING-ELSE.md)"
  CONTENT_OUT="$(grep -m1 'DRYRUN\|STOP' "$WORK/launch.out")"

  if [ "$NAMED_RC" = "0" ] && [ "$CONTENT_RC" != "0" ]; then
    ROW_B="RED"
    echo "RED [F5-B] identity is the filename; the spec's content is never consulted"
    note "file named S-042.md, body declares id S-SOMETHING-ELSE:"
    note "  rc=$NAMED_RC  $NAMED_OUT"
    note "file named S-SOMETHING-ELSE.md, body declares id S-042:"
    note "  rc=$CONTENT_RC  $CONTENT_OUT"
    note "the launch that proceeded is the one whose BODY names another slice;"
    note "the launch refused is the one whose body names the slice being run"
    note "launch_worker.sh:94 takes the id from basename, :129-130 requires the"
    note "planner to agree with it, :377 hands it to the writer as SPEC_ID, and"
    note "write_receipt.py:132 writes it as the receipt's spec_id"
    note "ADR-005 D1 keeps the launcher out of the spec dialect and this row does"
    note "not dispute that; what is unhandled is that nothing else ties the"
    note "receipt to the bytes the child was actually given"
    note "green when spec_id is derived from, or pinned against, the spec's"
    note "content -- a digest of the file fed on stdin would do it"
  elif [ "$NAMED_RC" = "0" ] && [ "$CONTENT_RC" = "0" ]; then
    ROW_B="GREEN"
    echo "GREEN [F5-B] both spellings resolved; identity does not hang on the filename"
  else
    ROW_B="UNMEASURED"
    note "row B UNMEASURED: the launcher refused the named arm too (rc=$NAMED_RC: $NAMED_OUT),"
    note "so the two arms differ in something other than the filename"
  fi
fi

echo "-- F5-A=$ROW_A F5-B=$ROW_B"
if [ "$ROW_A" = "RED" ] || [ "$ROW_B" = "RED" ]; then
  echo "F5 BYPASS FIXTURE: RED"
  exit 1
fi
if [ "$ROW_B" = "UNMEASURED" ]; then
  echo "F5 BYPASS FIXTURE: UNMEASURED (row B could not be posed; see above)"
  exit 2
fi
echo "F5 BYPASS FIXTURE: GREEN"
exit 0
