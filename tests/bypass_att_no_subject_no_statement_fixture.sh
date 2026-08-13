#!/usr/bin/env bash
# bypass_att_no_subject_no_statement -- the falsifier ADR-019 D7 names.
#
# THE ASSERTION (ADR-019 Verification, verbatim): "A run whose `cc.json` is
# unreadable produces a receipt and **zero** `.intoto.json` files."
#
# NOT YET OBSERVED WHEN IT WAS WRITTEN, AND OBSERVED HERE, in both halves. ADR-019
# declared the row honestly -- "no `error_no_output` run has been measured at this
# basis and no Statement has ever been emitted, so both halves of the assertion
# are predictions" -- and its Assumption ledger carried the reachability of the
# branch as **[assumed]**, with this falsifier: "a reading of
# `write_receipt.py:156-158` under which `cc.json` cannot in fact be unreadable,
# which would make D7 vacuous." That falsifier is answered below, and the answer
# is not the one the ledger feared: the branch IS reachable, and the fixture
# reaches it against the launcher in tree.
#
# WHAT D7 BINDS, READ EXACTLY. "If `$OUT` is **absent or unreadable at the moment
# the digest is taken**". Unreadable is a property of the FILE, not of its
# contents. An empty or malformed `cc.json` is perfectly readable; it produces the
# `{"subtype": "error_no_output"}` receipt `write_receipt.py:156-158` substitutes,
# and it has a digest like any other byte string. The two states are not the same
# state, and arm 3 below measures the difference rather than arguing it.
#
# THREE ARMS.
#
#   arm 1  THE RULE, on the writer, driven directly. ADR-010 extracted the receipt
#          writer out of the launcher precisely so a fixture could feed it a
#          constructed input -- "a writer reachable only by driving the whole
#          launcher cannot be fed a constructed cc.json" -- and
#          scripts/write_statement.py is built on the same contract. Handed no
#          digest, it must write NO file and exit 0. Handed one, it must write
#          exactly one. Both directions, because a writer that never writes
#          anything would pass the first half alone.
#
#   arm 2  THE LAUNCHER, at D7's actual condition. A real run of
#          scripts/launch_worker.sh, unpatched, in which the transcript is
#          genuinely unreadable when the digest is taken. The executor stub makes
#          it so: the transcript is the stub's own stdout, the fixture hands the
#          stub the directory it lives in, and the stub chmods it unreadable
#          before returning. That fabricates the CONDITION and not the mechanism
#          -- the launcher, the digest line, the receipt writer and the Statement
#          writer are all the ones in tree -- which is the same standing the
#          ADR-008 register's stubs have.
#          Asserted: a receipt IS written, carrying `subtype: error_no_output`,
#          and the receipts directory holds ZERO `.intoto.json` files.
#
#   arm 3  THE SCOPE, observed and reported, never accused. A second real run
#          whose executor writes nothing at all. `$OUT` is then EMPTY and
#          READABLE, because the launcher's own redirection `"${CMD[@]}" < "$SPEC"
#          > "$OUT"` creates the file before the child ever runs. The receipt says
#          `error_no_output` and a Statement IS emitted, over the zero-byte
#          transcript. That is D1 applied literally and not a defect: the subject
#          is the file the run produced, the digest is the digest of its bytes,
#          and nothing is fabricated. It is reported because it is the thing a
#          reader would otherwise assume: `error_no_output` in a receipt does NOT
#          imply that D7's branch was taken.
#
# DECLARED GREEN, and this header is where the register reads that (ADR-017 D6).
# It goes RED if a Statement is ever emitted with no subject to name.
#
# Nothing outside $WORK is written. Every repository built here is created by
# this fixture inside its own scratch directory; no repository outside it is
# read for anything but execution, and none is written.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
RECEIPT_WRITER="$PACK/scripts/write_receipt.py"
STATEMENT_WRITER="$PACK/scripts/write_statement.py"
LAUNCHER="$PACK/scripts/launch_worker.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-att-d7.XXXXXX")" || exit 2
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$RECEIPT_WRITER" ] || broken "scripts/write_receipt.py is not where this fixture expects it"
[ -f "$STATEMENT_WRITER" ] || broken "scripts/write_statement.py is not where this fixture expects it"
[ -f "$LAUNCHER" ] || broken "scripts/launch_worker.sh is not where this fixture expects it"
command -v node >/dev/null 2>&1 || broken "node is not available; the launcher's two collaborators are node CLIs"

printf '%s' '{"manifest_version":1,"verifier_id":"https://verifier.example.invalid/harness-pack/v1","model_tiers":{"worker":"T3"},"tiers":{"T3":{"name":"subagent","chain":["HAIKU_CLASS_MODEL"]}}}' > "$WORK/manifest.json"

count_statements() { find "$1" -maxdepth 1 -name '*.intoto.json' | grep -c . ; }

echo "== bypass_att_no_subject_no_statement: no transcript, no Statement (ADR-019 D7) =="

# ---- arm 1: the rule, on the writer -----------------------------------------
A1="$WORK/arm1"
mkdir -p "$A1" || broken "could not create the arm 1 directory"
printf '%s' '{"subtype":"error_no_output"}' > "$A1/run-arm1.cc.json"
CC_EXIT=1 \
GATE_JSON='{}' \
BASELINE_JSON='{"verdict":"FAIL","reason":"criteria failed: c1","verity_exit":1,"claims":[{"id":"c1","type":"command","verdict":"FAIL","evidence":"exit 1"}]}' \
RUN_ID="run-arm1" SPEC_ID="S-FIXTURE" MODEL_STRING="worker" \
TIER_RESOLVED="T3" MODEL_USED="HAIKU_CLASS_MODEL" MANIFEST_VERSION="1" \
CONSTITUTION_HASH="00a92e1544ba9dd55591388830a7f86bf1a8d555e22f455f05b5eb267ecaf97d" \
TOOL_VERSION="0.0.0-fixture" STARTED_AT="2026-08-13T10:14:00Z" ENDED_AT="2026-08-13T10:15:00Z" \
  python3 "$RECEIPT_WRITER" "$A1/run-arm1.cc.json" "$A1/run-arm1.receipt.json" >/dev/null \
  || broken "scripts/write_receipt.py did not compose the arm 1 receipt"

RECEIPT_BEFORE="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$A1/run-arm1.receipt.json")"

A1_OUT="$(OUT_PATH="$A1/run-arm1.cc.json" OUT_SHA256="" HARNESS_MANIFEST="$WORK/manifest.json" \
  python3 "$STATEMENT_WRITER" "$A1/run-arm1.receipt.json" "$A1/run-arm1.intoto.json" 2>&1)"
A1_RC=$?
A1_N="$(count_statements "$A1")"
RECEIPT_AFTER="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$A1/run-arm1.receipt.json")"

# The control that makes the zero above mean something: handed a digest, the same
# writer in the same directory must write exactly one file.
A1_CTRL_DIGEST="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$A1/run-arm1.cc.json")"
OUT_PATH="$A1/run-arm1.cc.json" OUT_SHA256="$A1_CTRL_DIGEST" HARNESS_MANIFEST="$WORK/manifest.json" \
  python3 "$STATEMENT_WRITER" "$A1/run-arm1.receipt.json" "$A1/run-arm1.intoto.json" >/dev/null 2>&1 \
  || broken "arm 1 control: the writer refused a transcript it could digest; the zero above cannot be attributed to D7"
A1_CTRL_N="$(count_statements "$A1")"
[ "$A1_CTRL_N" -eq 1 ] || broken "arm 1 control: handed a digest, the writer produced $A1_CTRL_N file(s); it does not discriminate"

A1_FAIL=0
[ "$A1_N" -eq 0 ] || A1_FAIL=1
[ "$A1_RC" -eq 0 ] || A1_FAIL=1
[ "$RECEIPT_BEFORE" = "$RECEIPT_AFTER" ] || A1_FAIL=1
note "arm 1 [writer]: no digest -> $A1_N file(s), rc=$A1_RC, writer said: ${A1_OUT}"
note "arm 1 [control]: a digest -> $A1_CTRL_N file. The assertion moves, so its zero is a measurement"
note "arm 1 [receipt]: $RECEIPT_BEFORE before, $RECEIPT_AFTER after -- D7's third refusal, no change to the receipt"

# ---- the launcher's collaborators, stubbed -----------------------------------
mkdir -p "$WORK/bin"
cat > "$WORK/bin/claude" <<'CLAUDE_STUB'
#!/usr/bin/env bash
# tool_version is read before the executor is ever spawned, so the version path
# must not touch the transcript.
if [ "${1:-}" = "--version" ]; then echo "0.0.0-fixture (stub)"; exit 0; fi
cat >/dev/null
# The transcript is THIS process's stdout. The fixture hands us the directory it
# lives in and there is exactly one *.cc.json there, which is ours. Making it
# unreadable fabricates D7's CONDITION; the launcher, its digest line and both
# writers are untouched.
if [ "${D7_MODE:-silent}" = "unreadable" ]; then
  for f in "$D7_RECEIPTS_DIR"/*.cc.json; do
    if [ -f "$f" ]; then chmod 000 "$f"; fi
  done
fi
# Prints NOTHING on either branch: the transcript is zero bytes, which is what
# makes write_receipt.py:156-158 substitute its error_no_output stub.
exit 0
CLAUDE_STUB
chmod +x "$WORK/bin/claude"

cat > "$WORK/hw.js" <<'HW_STUB'
process.stdout.write(JSON.stringify({
  kind: "unlocked", id: "S-DEMO", eligible_mode_b: true,
  spec: { model: "worker", tools: ["Read"], criteria: ["c1"],
          budget: { turns: 5, wall_clock: "30m" }, scope: ["README.md"] }
}));
HW_STUB

cat > "$WORK/verity.js" <<'VERITY_STUB'
process.stdout.write(JSON.stringify({
  results: [ { id: "c1", type: "command", verdict: "PASS", evidence: "exit 0" } ]
}));
VERITY_STUB

seed_repo() {  # $1 = dir
  mkdir -p "$1/specs" "$1/receipts" || return 1
  git -C "$1" init -q 2>/dev/null || return 1
  git -C "$1" config user.email t@example.invalid || return 1
  git -C "$1" config user.name tester || return 1
  git -C "$1" config commit.gpgsign false || return 1
  git -C "$1" config tag.gpgsign false || return 1
  printf 'Fixture slice. The executor is a stub; the launcher is real.\n' > "$1/specs/S-DEMO.md"
}

run_launcher() {  # $1 = repo, $2 = D7_MODE, $3 = logfile
  (
    cd "$1" || exit 1
    PATH="$WORK/bin:$PATH" \
    TELEGRAM_BOT_TOKEN="" TELEGRAM_CHAT_ID="" \
    D7_MODE="$2" D7_RECEIPTS_DIR="$1/receipts" \
    HARNESS_HOME="$PACK" \
    HARNESSWRIGHT_CLI="$WORK/hw.js" \
    VERITY_CLI="$WORK/verity.js" \
    HARNESS_MANIFEST="$WORK/manifest.json" \
    RECEIPTS_DIR="$1/receipts" \
    bash "$LAUNCHER" specs/S-DEMO.md
  ) > "$3" 2>&1
  return $?
}

receipt_of() {  # $1 = repo
  local r=( "$1"/receipts/*.receipt.json )
  if [ -f "${r[0]}" ]; then printf '%s' "${r[0]}"; fi
  return 0
}

# ---- arm 2: the launcher, at D7's actual condition ---------------------------
A2="$WORK/arm2"
seed_repo "$A2" || broken "could not seed the arm 2 repo"
run_launcher "$A2" unreadable "$WORK/arm2.out"
A2_RC=$?
A2_RECEIPT="$(receipt_of "$A2")"
[ -n "$A2_RECEIPT" ] || broken "the arm 2 run exited $A2_RC and wrote no receipt; the row's first half cannot be measured"
A2_SUBTYPE="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("subtype",""))' "$A2_RECEIPT")"
A2_N="$(count_statements "$A2/receipts")"
# The premise, checked and not assumed: the transcript really was unreadable.
A2_CC="$(find "$A2/receipts" -maxdepth 1 -name '*.cc.json' | head -1)"
A2_READABLE="no"
if [ -r "$A2_CC" ]; then A2_READABLE="yes"; fi
[ "$A2_READABLE" = "no" ] || broken "arm 2: the transcript at $A2_CC is readable, so the run did not reach D7's condition and its zero would be a zero for some other reason"

note "arm 2 [launcher]: run exited $A2_RC, receipt $(basename "$A2_RECEIPT") subtype=$A2_SUBTYPE, $A2_N .intoto.json file(s)"
note "arm 2 [premise]: the transcript was UNREADABLE when the digest was taken -- D7's literal condition"

A2_FAIL=0
[ "$A2_N" -eq 0 ] || A2_FAIL=1
[ "$A2_SUBTYPE" = "error_no_output" ] || A2_FAIL=1

# ---- arm 3: the scope, observed and reported --------------------------------
A3="$WORK/arm3"
seed_repo "$A3" || broken "could not seed the arm 3 repo"
run_launcher "$A3" silent "$WORK/arm3.out"
A3_RC=$?
A3_RECEIPT="$(receipt_of "$A3")"
[ -n "$A3_RECEIPT" ] || broken "the arm 3 run exited $A3_RC and wrote no receipt"
A3_SUBTYPE="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("subtype",""))' "$A3_RECEIPT")"
A3_N="$(count_statements "$A3/receipts")"
A3_CC="$(find "$A3/receipts" -maxdepth 1 -name '*.cc.json' | head -1)"
A3_BYTES="$(wc -c < "$A3_CC" | tr -d ' ')"
A3_DIGEST=""
if [ "$A3_N" -eq 1 ]; then
  A3_DIGEST="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["subject"][0]["digest"]["sha256"])' "$(find "$A3/receipts" -maxdepth 1 -name '*.intoto.json' | head -1)")"
fi
note "arm 3 [scope]: an executor that writes nothing leaves a READABLE $A3_BYTES-byte transcript;"
note "               receipt subtype=$A3_SUBTYPE, $A3_N .intoto.json file(s), subject digest ${A3_DIGEST:-<none>}"
note "               This is NOT accused. D7's condition is 'absent or unreadable', and the launcher's own"
note "               redirection creates \$OUT before the child runs, so error_no_output in a receipt does"
note "               not imply D7's branch was taken. The Statement above names a zero-byte transcript by"
note "               its true digest: D1 applied literally, with nothing fabricated"

if [ "$A1_FAIL" -eq 0 ] && [ "$A2_FAIL" -eq 0 ]; then
  echo "GREEN [bypass_att_no_subject_no_statement] an unreadable transcript yields a receipt and zero Statements"
  note "both halves of the row were predictions when ADR-019 named them; both are observed above"
  note "the absence of the side-car is the signal, and it is a verifiable fact: a third party looks for"
  note "<run_id>.intoto.json beside the receipt, does not find it, and knows what that means"
  echo "att_no_subject_no_statement BYPASS FIXTURE: GREEN"
  exit 0
fi

echo "RED [bypass_att_no_subject_no_statement] a Statement exists for a run with no readable transcript"
if [ "$A1_FAIL" -ne 0 ]; then
  note "arm 1: the writer produced $A1_N file(s) with no digest (rc=$A1_RC), or moved the receipt"
fi
if [ "$A2_FAIL" -ne 0 ]; then
  note "arm 2: the launcher wrote $A2_N .intoto.json file(s) and a receipt with subtype=$A2_SUBTYPE"
fi
note "Statement v1 rejects a subject-less Statement (statement.md:37), so the only way to emit on this"
note "branch is to fabricate a subject -- the trade ADR-019 D2 already refused for HEAD. A missing"
note "side-car costs a consumer one lookup; a fabricated one costs them every true side-car"
echo "att_no_subject_no_statement BYPASS FIXTURE: RED"
exit 1
