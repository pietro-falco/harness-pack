#!/usr/bin/env bash
# Mode B launcher. Pack-side responsibilities only (ADR-005 D6): HALT check,
# constitution hash pin (fail-closed) + injection, bounded run, receipt write.
# It does NOT parse specs (ADR-005 D1/D2): it consumes `harnesswright next --json`
# and executes over the resolved plan. The one place the two model vocabularies
# meet is pack-side, resolving next's opaque model-string through the manifest's
# model_tiers to a concrete model (ADR-005 D4).
#
# Env:
#   HARNESSWRIGHT_CLI  path to the harnesswright CLI entrypoint
#                      (default: an installed `harnesswright` binary resolved via PATH)
#   HARNESS_HOME       pack dir (default: this script's parent)
#   HARNESS_MANIFEST   default: $HARNESS_HOME/templates/manifest.example.json
#   RECEIPTS_DIR       default: ./.harness/receipts
#   LAUNCH_DRYRUN      if =1, resolve + print the launch decision and exit 0 BEFORE
#                      hashing the constitution or invoking claude; writes nothing.
#                      Preview + test affordance; the gate logic above it is identical.
# Verify claude flag names against current Claude Code docs at wiring time; this file
# is the only seam if the runner CLI contract drifts.
set -euo pipefail

# Optional, fail-open Telegram notification. No-op (silent) unless both
# TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID are set; a notification failure
# must never alter the run outcome or exit code, so curl's result is
# discarded and this always returns 0. Never echo the token.
notify_telegram() {
  local text="$1"
  if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    return 0
  fi
  curl -s -m 5 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${text}" >/dev/null 2>&1 || true
  return 0
}

usage() { echo "usage: launch_worker.sh SPEC.md" >&2; exit 2; }
[ $# -eq 1 ] || usage
SPEC="$1"
[ -f "$SPEC" ] || { echo "STOP: spec file not found: $SPEC" >&2; exit 1; }

HARNESS_HOME="${HARNESS_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
MANIFEST="${HARNESS_MANIFEST:-$HARNESS_HOME/templates/manifest.example.json}"
CONST="$HARNESS_HOME/CONSTITUTION.md"
RECEIPTS_DIR="${RECEIPTS_DIR:-./.harness/receipts}"

# Operator kill-switch (unchanged): git-root-anchored HALT file, checked before the
# first write so a refused launch leaves no receipts dir behind and is independent of
# RECEIPTS_DIR. Checked first among the pack-side gates (ADR-005 D6), ahead of CLI
# resolution, so the emergency stop fires unconditionally even when harnesswright/verity
# are not installed.
HALT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [ -e "$HALT_ROOT/.harness/HALT" ]; then
  echo "STOP: HALT file present; refusing to launch." >&2; exit 1
fi

# harnesswright CLI, fail-closed (ADR-005 D6 STOP "CLI not resolvable"). Resolution order
# (harness-pack ADR-004 D2): HARNESSWRIGHT_CLI env override first; else an installed
# `harnesswright` binary on PATH; else STOP with actionable guidance. No literal home
# path is a tracked default -- the operator's install location is theirs to choose.
if [ -n "${HARNESSWRIGHT_CLI:-}" ]; then
  HW_CLI="$HARNESSWRIGHT_CLI"
elif command -v harnesswright >/dev/null 2>&1; then
  HW_CLI="$(command -v harnesswright)"
else
  echo "STOP: harnesswright CLI not resolvable; install harnesswright or set HARNESSWRIGHT_CLI" >&2
  exit 1
fi
[ -f "$HW_CLI" ] || { echo "STOP: harnesswright CLI not resolvable at $HW_CLI" >&2; exit 1; }

# verity CLI, fail-closed and resolved BEFORE launching CC (verity ADR-004 D7): a run
# whose claims cannot be gated must not start. Resolution order (harness-pack ADR-004
# D2): VERITY_CLI env override first; else an installed `verity` binary on PATH; else
# STOP with actionable guidance.
if [ -n "${VERITY_CLI:-}" ]; then
  :
elif command -v verity >/dev/null 2>&1; then
  VERITY_CLI="$(command -v verity)"
else
  echo "STOP: verity CLI not resolvable; install verity or set VERITY_CLI" >&2
  exit 1
fi
[ -f "$VERITY_CLI" ] || { echo "STOP: verity CLI not resolvable at $VERITY_CLI" >&2; exit 1; }

# Pack-side launch-gate checks (ADR-002): tier resolution + constitution hash pin,
# extracted verbatim into a standalone unit the tests exercise directly. Resolved
# beside THIS script (not via HARNESS_HOME, which is overridable), fail-closed.
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKS="$SELF_DIR/launch_checks.py"
[ -f "$CHECKS" ] || { echo "STOP: launch_checks.py not resolvable at $CHECKS" >&2; exit 1; }

# The slice the operator requested, derived from the spec FILENAME only, never by
# parsing the spec (ADR-005 D1: one dialect, and the launcher is not its second reader).
REQUESTED_ID="$(basename "$SPEC" .md)"

# Consume `next --json` (ADR-005 D2). next reads .harness/harness.json relative to its
# cwd, so run it at the target repo root. Capture stdout and exit code separately; a
# non-zero exit is a STOP (D6), never a fallback.
NEXT_ERR="${TMPDIR:-/tmp}/hw_next.$$.err"
set +e
NEXT_JSON="$(cd "$HALT_ROOT" && node "$HW_CLI" next --json 2>"$NEXT_ERR")"
NEXT_EXIT=$?
set -e
if [ "$NEXT_EXIT" -ne 0 ]; then
  echo "STOP: 'next --json' exited $NEXT_EXIT" >&2
  sed 's/^/  next: /' "$NEXT_ERR" >&2 2>/dev/null || true
  rm -f "$NEXT_ERR"; exit 1
fi
rm -f "$NEXT_ERR"

# Decide from next's machine output alone (ADR-005 D5/D6). The python prints exactly one
# of two lines and exits 0 either way (so `set -e` never preempts our own STOP handling):
#   STOP <human reason>
#   OK <id> <model_string> <maxturns> <wallsec> <tools_csv>
# maxturns/wallsec == 0 mean "dimension not declared -> emit no flag" (budget is read,
# never defaulted, D6). tools_csv is comma-joined (D3); next always fills spec.tools.
DECISION="$(
  REQUESTED_ID="$REQUESTED_ID" NEXT_JSON="$NEXT_JSON" python3 <<'PYEOF'
import json, os, re, sys
requested = os.environ["REQUESTED_ID"]
try:
    r = json.loads(os.environ["NEXT_JSON"])
except Exception as e:
    print(f"STOP next --json is not valid JSON: {e}"); sys.exit()
kind = r.get("kind", "")
if kind != "unlocked":
    print(f"STOP kind is {kind!r}, not 'unlocked' (nothing eligible to launch)"); sys.exit()
rid = r.get("id", "")
if rid != requested:
    print(f"STOP resolved id {rid!r} != requested {requested!r} (next is on a different slice)"); sys.exit()
if r.get("eligible_mode_b") is not True:
    print(f"STOP slice {rid} is not Mode-B-eligible (eligible_mode_b != true)"); sys.exit()
spec = r.get("spec")
if not isinstance(spec, dict):
    print(f"STOP resolved plan for {rid} carries no spec object"); sys.exit()
model = spec.get("model")
if not isinstance(model, str) or model == "":
    print(f"STOP spec.model missing or empty for {rid}"); sys.exit()
# spec.budget = the bounds this slice buys. templates/spec.mode-b.template.md:14 declares it
# REQUIRED in mode B with at least one of turns / wall_clock, which is two obligations -- the map
# must be PRESENT, and it must declare a dimension this launcher can SPEND -- each refused on its
# own line so a spec that violates one is named for that one. The third dimension the template
# names is advisory there and is read by nothing here: a budget declaring only it leaves both
# bounds on the 0 sentinel, which is no bound at all, and that is the second STOP.
# (No apostrophe anywhere in this block: it is inside `DECISION="$( ... <<PYEOF )"`, and a lone
# single quote there ends the command substitution early -- bash reports it as an EOF at :117.)
# Refused, never defaulted: reinstating a turn or wall-clock default would hand the run a bound the
# operator never declared, which is not the declaration being enforced. The old silent 15/20
# defaults are gone for exactly that reason and they stay gone (D6 STOPs, never defaults).
budget = spec.get("budget")
if not isinstance(budget, dict):
    print(f"STOP spec.budget missing for {rid} (REQUIRED in mode B: a map declaring turns and/or wall_clock)"); sys.exit()
turns = budget.get("turns")
maxturns = str(turns) if isinstance(turns, int) and turns > 0 else "0"
wc = budget.get("wall_clock")
wallsec = "0"
if isinstance(wc, str):
    m = re.match(r"^(\d+)(m|h)$", wc)
    if m:
        wallsec = str(int(m.group(1)) * (60 if m.group(2) == "m" else 3600))
if maxturns == "0" and wallsec == "0":
    print(f"STOP spec.budget for {rid} declares no dimension this launcher can spend (REQUIRED in mode B: turns as a positive integer, and/or wall_clock as Nm or Nh)"); sys.exit()
tools = spec.get("tools")
if not isinstance(tools, list) or not tools or any((not isinstance(t, str) or t == "") for t in tools):
    print(f"STOP spec.tools missing/empty for {rid} (expected a non-empty list from next)"); sys.exit()
# spec.criteria = the claim IDs this slice asserts (ADR-004 D7 gate scope). Note the
# collision: this is spec.criteria, NOT the top-level `criteria` next --json returns (which is harness.json).
criteria = spec.get("criteria")
if not isinstance(criteria, list) or not criteria or any((not isinstance(c, str) or c == "") for c in criteria):
    print(f"STOP spec.criteria missing/empty for {rid} (expected a non-empty list of claim IDs)"); sys.exit()
# spec.scope = where this slice may write. templates/spec.mode-b.template.md:21-22 declares it
# REQUIRED in mode B with a stated shape, which is three obligations -- present, non-empty, and
# repo-relative -- each refused on its own line so a spec that violates one is named for that one.
# Refused, never normalized: stripping a leading / or resolving a .. would hand the run a perimeter
# the operator did not declare, which is not the declaration being enforced (D6 STOPs, never defaults).
scope = spec.get("scope")
if not isinstance(scope, list):
    print(f"STOP spec.scope missing for {rid} (REQUIRED in mode B: a list of repo-relative prefixes)"); sys.exit()
if not scope or any((not isinstance(p, str) or p == "") for p in scope):
    print(f"STOP spec.scope empty for {rid} (REQUIRED in mode B: a non-empty list of repo-relative prefixes)"); sys.exit()
outside = [p for p in scope if p.startswith("/") or ".." in p.split("/")]
if outside:
    print(f"STOP spec.scope not repo-relative for {rid}: {' '.join(outside)} (no leading / and no '..' component)"); sys.exit()
print("OK", rid, model, maxturns, wallsec, ",".join(tools), ",".join(criteria))
PYEOF
)"
read -r VERDICT REST <<<"$DECISION"
if [ "$VERDICT" != "OK" ]; then
  echo "$DECISION" >&2
  exit 1
fi
read -r RESOLVED_ID MODEL_STRING MAXTURNS WALLSEC TOOLS CRITERIA <<<"$REST"

# Resolve the opaque model-string to a concrete model, pack-side, via the manifest
# (ADR-005 D4): spec.model -> model_tiers[model] -> tiers[T].chain[0]. Fail-closed: a
# model-string absent from model_tiers is a STOP, never a default tier. The existing
# single-hop-DOWNWARD resolves_to rule (empty chain) is preserved unchanged.
RESOLUTION="$(MODEL_STRING="$MODEL_STRING" python3 "$CHECKS" resolve-tier "$MANIFEST")" || exit 1
read -r RVERDICT RREST <<<"$RESOLUTION"
if [ "$RVERDICT" != "OK" ]; then
  echo "$RESOLUTION" >&2
  exit 1
fi
read -r TIER_RESOLVED MODEL MVER <<<"$RREST"

# Preview + test affordance: everything above is the real gate path. Stop here before
# touching the constitution or invoking claude, and write nothing.
if [ "${LAUNCH_DRYRUN:-}" = "1" ]; then
  echo "DRYRUN ok id=$RESOLVED_ID model_string=$MODEL_STRING tier=$TIER_RESOLVED model=$MODEL manifest=$MVER max_turns=$MAXTURNS wall_sec=$WALLSEC tools=$TOOLS"
  exit 0
fi

mkdir -p "$RECEIPTS_DIR"

# Constitution hash pin, fail-closed (ADR-002: via the extracted unit; check-hash
# echoes the computed digest on stdout, or STOPs on stderr + non-zero on mismatch).
CHASH="$(python3 "$CHECKS" check-hash "$CONST" "$MANIFEST")" || exit 1

TOOLVER="$(claude --version 2>/dev/null || echo unknown)"
RUN_ID="run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
OUT="$RECEIPTS_DIR/$RUN_ID.cc.json"

# Claim, then spawn -- never spawn on a slice we only read as free (vault ADR-054 D3).
# `next --json` above consulted the lock state, but consulting is all it does:
# harnesswright's next.ts:127 is an existsSync and nothing in the stack ever created
# the file, so two launchers racing on one repo both resolved the same slice as
# unlocked and both would launch. The take is here, it is a single O_EXCL create, and
# the launch does not happen without it. Two keys, in this order:
#   _workspace    one git index, one live run. A linked worktree has its own toplevel
#                 and therefore its own locks dir, so runs in SEPARATE worktrees never
#                 contend here -- which is the parallelism this buys.
#   $RESOLVED_ID  one slice, one live run. Same path harnesswright already reads.
# --pid $$ records THIS shell as the holder: the python acquirer exits immediately, and
# a lease naming a dead pid is reclaimable at once. That is also what keeps a SIGKILLed
# launcher from stranding its slice for the whole TTL.
LEASE="$SELF_DIR/slice_lease.py"
[ -f "$LEASE" ] || { echo "STOP: slice_lease.py not resolvable at $LEASE" >&2; exit 1; }
LEASE_TTL=3600
[ "$WALLSEC" != "0" ] && LEASE_TTL=$((WALLSEC + 300))
LEASE_HELD_WORKSPACE=""
LEASE_HELD_SLICE=""
release_leases() {
  [ -n "$LEASE_HELD_SLICE" ] && python3 "$LEASE" release --root "$HALT_ROOT" \
    --key "$LEASE_HELD_SLICE" --run-id "$RUN_ID" >/dev/null 2>&1
  [ -n "$LEASE_HELD_WORKSPACE" ] && python3 "$LEASE" release --root "$HALT_ROOT" \
    --key "$LEASE_HELD_WORKSPACE" --run-id "$RUN_ID" >/dev/null 2>&1
  return 0
}
trap release_leases EXIT
python3 "$LEASE" acquire --root "$HALT_ROOT" --key "_workspace" --run-id "$RUN_ID" \
  --ttl "$LEASE_TTL" --pid $$ \
  || { echo "STOP: workspace $HALT_ROOT is claimed by a live run; refusing to share its git index." >&2; exit 1; }
LEASE_HELD_WORKSPACE="_workspace"
python3 "$LEASE" acquire --root "$HALT_ROOT" --key "$RESOLVED_ID" --run-id "$RUN_ID" \
  --ttl "$LEASE_TTL" --pid $$ \
  || { echo "STOP: slice $RESOLVED_ID is claimed by a live run; refusing to take the same task twice." >&2; exit 1; }
LEASE_HELD_SLICE="$RESOLVED_ID"

echo "spec=$RESOLVED_ID model_string=$MODEL_STRING tier_resolved=$TIER_RESOLVED model=$MODEL manifest=$MVER constitution=$CHASH"

# ONE measurement path, used by t0 and by t1 (ADR-008 D2, 0008:51): the runner
# already resolved fail-closed above, the same target root, the same invocation
# form, and the same filter reducing verity's report to spec.criteria -- a
# function called twice, never a second copy. "t0 and t1 are commensurable by
# construction or they are not commensurable at all." Sets MEASURED_JSON:
#   {"verdict": PASS|FAIL|STOP|NO-VERDICT, "reason": str, "verity_exit": int,
#    "claims": [{"id","type","verdict","evidence"}, ...]}
# NO-VERDICT (and only NO-VERDICT) means no verdict was produced at all.
MEASURED_JSON="{}"
measure_criteria() {
  local verity_err vout vexit
  verity_err="${TMPDIR:-/tmp}/verity.$$.err"
  set +e
  vout="$(cd "$HALT_ROOT" && node "$VERITY_CLI" verify --json 2>"$verity_err")"
  vexit=$?
  set -e
  rm -f "$verity_err"
  MEASURED_JSON="$(
    CRITERIA="$CRITERIA" VERITY_EXIT="$vexit" VERITY_OUT="$vout" python3 <<'PYEOF'
import json, os
crit = [c for c in os.environ["CRITERIA"].split(",") if c]
vexit = int(os.environ["VERITY_EXIT"])
# verity exit 2 = usage/config error (missing/malformed manifest, unknown claim type):
# no verdict was produced, the gate could not run. Terminal (ADR-004 D3: a repo-determined
# config error a retry cannot fix), fail-closed.
if vexit == 2:
    print(json.dumps({"verdict": "NO-VERDICT", "reason": "verity config error (exit 2); gate could not run", "verity_exit": vexit, "claims": []}))
else:
    try:
        report = json.loads(os.environ["VERITY_OUT"])
        results = {r["id"]: r for r in report.get("results", [])}
    except Exception as e:
        print(json.dumps({"verdict": "NO-VERDICT", "reason": f"verity --json not parseable: {e}", "verity_exit": vexit, "claims": []}))
    else:
        items, missing, failed = [], [], []
        for cid in crit:
            r = results.get(cid)
            if r is None:
                missing.append(cid)
                items.append({"id": cid, "verdict": "ABSENT", "evidence": "criterion id not present in verity report"})
            else:
                items.append({"id": cid, "type": r.get("type"), "verdict": r.get("verdict"), "evidence": r.get("evidence")})
                if r.get("verdict") != "PASS":
                    failed.append(cid)
        if missing:
            verdict, reason = "STOP", "criteria absent from verity report: " + ",".join(missing)
        elif failed:
            verdict, reason = "FAIL", "criteria failed: " + ",".join(failed)
        else:
            verdict, reason = "PASS", "all declared criteria PASS"
        print(json.dumps({"verdict": verdict, "reason": reason, "verity_exit": vexit, "claims": items}))
PYEOF
  )"
}

# t0 -- the pre-launch baseline (ADR-008 D1, 0008:37). Measured HERE and nowhere
# else, against the three ordering constraints 0008:53 states as constraints
# rather than line numbers:
#   0008:55  after the slice's path lease is held -- the acquire directly above.
#            A baseline measured before the lease is measured on a tree another
#            session may still move, and its delta is noise.
#   0008:56  after criteria resolution -- $CRITERIA, read out of `next --json`
#            at :164 of this file.
#   0008:57  "Before the executor is spawned (`:236`), since a baseline taken
#            after the executor has written is not a baseline." The spawn is the
#            "${CMD[@]}" below.
# Measurement only: t0 never accepts and never rejects.
measure_criteria
BASELINE_JSON="$MEASURED_JSON"
BASELINE_VERDICT="$(printf '%s' "$BASELINE_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("verdict","NO-VERDICT"))')"

# Failure posture, reusing ADR-004 D3's distinguishing rule verbatim -- verdict
# presence, not exit code (0008:61). Verdicts produced: the run proceeds,
# whatever they are; a t0 in which every criterion reads FAIL or ABSENT is the
# healthy normal case and must never stop a run (0008:63). No verdict at all:
#   0008:64  "The baseline runner produced **no** verdict - spawn failure,
#            unparseable output, interruption: the launcher stops **before
#            spawning the executor**, with a distinct stop reason, and releases
#            the lease. A run whose baseline is unknown cannot report a
#            contribution."
# The distinct stop reason is `baseline-unknown`; the leases are released by the
# EXIT trap installed with the acquire. No receipt is written on this path: the
# run stopped before the gate, and 0008:89 places that state outside the receipt
# ("that one is an unknown *baseline*, which stops the run before spawn").
if [ "$BASELINE_VERDICT" = "NO-VERDICT" ]; then
  echo "STOP: baseline-unknown: t0 produced no verdict for $RESOLVED_ID; refusing to spawn the executor." >&2
  printf '%s\n' "$BASELINE_JSON" | sed 's/^/  baseline: /' >&2
  exit 1
fi

# Budget -> flags (ADR-005 D6): a declared dimension produces its flag; an undeclared
# dimension (sentinel 0) produces NO flag. The old silent 15/20 defaults are gone.
CMD=(claude -p
  --model "$MODEL"
  --append-system-prompt "$(cat "$CONST")"
  --settings "$HARNESS_HOME/templates/settings.mode-b.json"
  --allowedTools "$TOOLS"
  --permission-mode dontAsk
  --output-format json)
if [ "$MAXTURNS" != "0" ]; then CMD+=(--max-turns "$MAXTURNS"); fi
# Wall-clock -> kill after N seconds, prefer gtimeout (coreutils) then timeout.
if [ "$WALLSEC" != "0" ]; then
  if command -v gtimeout >/dev/null; then CMD=(gtimeout "$WALLSEC" "${CMD[@]}")
  elif command -v timeout >/dev/null; then CMD=(timeout "$WALLSEC" "${CMD[@]}")
  fi
fi

set +e
"${CMD[@]}" < "$SPEC" > "$OUT"
CC_EXIT=$?
set -e
ENDED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# The one line ADR-019 D1 costs, and it is taken HERE for a reason the decision
# states as a constraint rather than a preference: "the sha256 of its raw bytes,
# computed AFTER the child closes -- `CC_EXIT=$?` at :371 -- and BEFORE the
# writer is invoked at :409". The redirection above completes before $? is read,
# so the file is closed and final at this point, and nothing between here and the
# writer reopens it. This was ADR-019 OR-6; it is the whole of D1's cost, and
# without it the launcher holds the transcript's PATH and never its digest --
# which is the measured defect (GAP.md:207, `subject[0].digest set | FAIL | FAIL
# | FAIL`) the whole arc exists to close.
#
# hashlib, not shasum(1): python3 is already a hard dependency of this launcher
# and launch_checks.py:61 pins the constitution with exactly this call, so the
# two digests in the receipt family are computed by one library and not by two
# tools that differ per platform.
#
# EMPTY IS A DECIDED STATE, NOT A FAILURE. If $OUT is absent or unreadable the
# variable stays empty and the launcher does not stop: ADR-019 D7 owns that
# branch, the receipt is written exactly as always, and write_statement.py emits
# no side-car at all. The absence of the file is the signal.
OUT_SHA256=""
if [ -r "$OUT" ]; then
  OUT_SHA256="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$OUT" 2>/dev/null || true)"
fi

# Gate (ADR-004 D7): a Mode B run's "done" is a claim, not a fact. When CC exited 0, run
# verity over the target repo's manifest and judge THIS slice's declared criteria only
# (ADR-004 criteria = claim IDs; the manifest is repo-level and accretes across slices, so
# the gate is scoped to spec.criteria, not verity's overall verdict). verity is a black box:
# invoke, read --json report + exit code, filter by criteria. verity writes its own report
# under .verity/reports/; we embed the item-level verdicts here (D6). If CC did not exit 0,
# the stop condition is the CC failure itself and the gate is skipped.
GATE_JSON="{}"
if [ "$CC_EXIT" -eq 0 ]; then
  measure_criteria
  GATE_JSON="$MEASURED_JSON"
fi

# Receipt: reflects the gate, not just CC exit. claims[] carries item-level verdicts for
# the slice's criteria (D6); stop_reason names what actually stopped the run (D7).
#
# The composition itself lives in scripts/write_receipt.py (ADR-010), extracted from
# the inline heredoc that used to sit here for the reason ADR-002 extracted the two
# launch gates: a writer reachable only by driving the whole launcher cannot be fed a
# constructed cc.json, and ADR-010's two fixtures have to feed it one. There is no
# logic fork -- the launcher and the fixtures run that file. Resolved beside THIS
# script, like the other units, and fail-closed if absent.
WRITER="$SELF_DIR/write_receipt.py"
[ -f "$WRITER" ] || { echo "STOP: write_receipt.py not resolvable at $WRITER" >&2; exit 1; }
# Resolved before the call, not inside its argument list: $RUN_ID also appears in
# the assignment prefix below, and an expansion of it in the same command's
# arguments is the SC2097/SC2098 pair -- which shellcheck reports and which the
# pinned gate treats as an error.
RECEIPT="$RECEIPTS_DIR/$RUN_ID.receipt.json"
CC_EXIT="$CC_EXIT" GATE_JSON="$GATE_JSON" BASELINE_JSON="$BASELINE_JSON" \
  RUN_ID="$RUN_ID" SPEC_ID="$RESOLVED_ID" MODEL_STRING="$MODEL_STRING" \
  TIER_RESOLVED="$TIER_RESOLVED" MODEL_USED="$MODEL" MANIFEST_VERSION="$MVER" \
  CONSTITUTION_HASH="$CHASH" TOOL_VERSION="$TOOLVER" \
  STARTED_AT="$STARTED" ENDED_AT="$ENDED" \
  python3 "$WRITER" "$OUT" "$RECEIPT"

# Side-car in-toto Statement (ADR-019 D5): a SIBLING file, `<run_id>.intoto.json`,
# written beside the receipt and never into it. The precedent is
# harnesswright/ADR-0008 D5:107-109 and it is adopted rather than reinvented --
# receipt_chain.py:47-48 records the sha256 of the source file's bytes, so a
# receipt mutated after a rollup breaks every chain line covering it. The
# proprietary receipt does not change by one byte as a result of this.
#
# FAIL-OPEN AT THE CALL SITE, fail-closed inside the writer, and the two are not
# in tension. write_statement.py refuses to emit a Statement it cannot emit
# correctly (a manifest with no verifier_id, a receipt with no ended_at) and
# writes nothing when it refuses. What must never happen is that refusal changing
# what the RUN reports: the run is the thing attested, not the attestation, so a
# non-zero exit here is swallowed and neither the exit code below nor the gate's
# verdict can move because of it. An operator reads the refusal on stderr; a
# consumer reads the absence of the file.
STATEMENT_WRITER="$SELF_DIR/write_statement.py"
STATEMENT="$RECEIPTS_DIR/$RUN_ID.intoto.json"
if [ -f "$STATEMENT_WRITER" ]; then
  OUT_PATH="$OUT" OUT_SHA256="$OUT_SHA256" HARNESS_MANIFEST="$MANIFEST" \
    python3 "$STATEMENT_WRITER" "$RECEIPT" "$STATEMENT" || true
else
  echo "note: write_statement.py not resolvable at $STATEMENT_WRITER; no Statement emitted" >&2
fi

RECEIPT_STOP_REASON="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("stop_reason",""))' "$RECEIPT")"
# ADR-010 D3 extends the notification contract to carry refusals.count: "A refused
# run is loud to the operator and silent to $?." Only refusals.count is added.
# D3's sentence also says the contract was "already extended by ADR-0008 D4 to carry
# contribution.verdict" -- measured against this line at the ADR's own basis, it was
# not: the notification carried run_id, spec_id and stop_reason and nothing else.
# That gap belongs to harnesswright/ADR-0008 D4, not to this decision, so it is
# recorded and left where it is rather than repaired in passing here.
RECEIPT_REFUSALS="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])).get("refusals") or {}; print(r.get("count",""))' "$RECEIPT")"
notify_telegram "run_id=$RUN_ID spec_id=$RESOLVED_ID stop_reason=$RECEIPT_STOP_REASON refusals=$RECEIPT_REFUSALS"

# Final outcome (ADR-004 D3/D7): CC failure dominates and is returned as-is. Otherwise the
# gate decides: only an all-criteria-PASS verdict is a success; FAIL, STOP (absent criterion),
# and NO-VERDICT are all terminal non-zero exits for the operator to review.
#
# This rule does not move now that the receipt carries a contribution, and the
# non-movement is the decision, not an omission (ADR-008 D4, 0008:97): "A `NO_OP`
# under `gate.verdict: PASS` **exits 0**, and `stop_reason` stays `gate-pass`."
# 0008:99 gives the reason -- ADR-004 D3 classifies retryable versus terminal on
# verdict presence read off this code, so loading contribution onto it as a
# second, orthogonal axis makes the retry rule ambiguous and turns a legitimate
# no-op into an infrastructure failure a runner may retry. Contribution and
# acceptance are different questions and stay in different fields; the operator
# hears about the no-op through the notification above, never through $?.
if [ "$CC_EXIT" -ne 0 ]; then
  exit "$CC_EXIT"
fi
GATE_VERDICT="$(printf '%s' "$GATE_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("verdict","NO-VERDICT"))')"
[ "$GATE_VERDICT" = "PASS" ] || { echo "STOP: gate verdict=$GATE_VERDICT (run not accepted)" >&2; exit 1; }
