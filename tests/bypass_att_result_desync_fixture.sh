#!/usr/bin/env bash
# bypass_att_result_desync -- the falsifier ADR-019 D4 names.
#
# THE ASSERTION (ADR-019 Verification, verbatim): "A Statement listing
# `HARNESS_GATE_PASS` while the gate exited non-zero must be **rejected**."
#
# NOT YET OBSERVED WHEN IT WAS WRITTEN, AND OBSERVED HERE. ADR-019 declared the
# row honestly: "unlike D1, there is no measured RED behind this one, because no
# Statement has ever been emitted. It is a prediction until the fixture runs."
# The fixture runs in this commit, and the RED below is the first observation of
# it -- fabricated deliberately, on the same model ADR-018's D4 row used when its
# inference stopped being one.
#
# WHAT "THE GATE EXITED NON-ZERO" IS READ AS, and the reading is load-bearing
# enough to state rather than leave to whoever writes the detector. It is
# `$.gate.verdict != "PASS"`, because that is precisely what decides the run's
# exit: scripts/launch_worker.sh, `[ "$GATE_VERDICT" = "PASS" ] || { echo "STOP:
# gate verdict=$GATE_VERDICT (run not accepted)" >&2; exit 1; }`. It is NOT
# `$.gate.verity_exit != 0`. `verity` runs over the WHOLE target repository while
# the gate is scoped to `spec.criteria` (launch_worker.sh's measure_criteria), so
# a run in which every DECLARED criterion passes can sit beside a non-zero
# `verity_exit` from a claim this slice never declared. A detector keyed to
# `verity_exit` would refuse a Statement that is true, which is the opposite
# defect and just as expensive.
#
# THREE NON-PASS VERDICTS, NOT ONE. measure_criteria produces PASS, FAIL, STOP
# (a declared criterion absent from the report) and NO-VERDICT (the gate could
# not run). Each of the three non-PASS values is exercised, because a detector
# that catches only FAIL leaves two doors open.
#
#   control 1  a FABRICATED desynced Statement -- properties listing
#              HARNESS_GATE_PASS beside a receipt whose gate did not pass -- must
#              be REJECTED, once per non-PASS verdict. This is the RED.
#   control 2  a conforming pair -- a gate-PASS receipt and the Statement the
#              emitter writes for it, which does carry HARNESS_GATE_PASS -- must
#              be ACCEPTED. Without it a detector wired to reject every
#              HARNESS_GATE_PASS would look identical and would be useless.
#   the row    the Statement the EMITTER writes for each non-PASS receipt must be
#              ACCEPTED, and must not carry HARNESS_GATE_PASS at all.
#
# ABSENCE MEANS NOT VERIFIED, NEVER FAILED. `svr.md:105` -- "Indicates the
# **passing** properties verified for the artifact" -- so the emitter's correct
# behaviour on a failing gate is to say nothing about the gate, not to say
# something negative about it. The row asserts the absence of the property and
# never the presence of a HARNESS_GATE_FAIL, which does not exist and must not.
#
# DECLARED GREEN, and this header is where the register reads that (ADR-017 D6).
# It goes RED if an emitter ever couples the property to anything other than the
# verdict the run's exit is taken from.
#
# Nothing outside $WORK is written.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
RECEIPT_WRITER="$PACK/scripts/write_receipt.py"
STATEMENT_WRITER="$PACK/scripts/write_statement.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-att-desync.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$RECEIPT_WRITER" ] || broken "scripts/write_receipt.py is not where this fixture expects it"
[ -f "$STATEMENT_WRITER" ] || broken "scripts/write_statement.py is not where this fixture expects it"

printf '%s' '{"manifest_version":1,"verifier_id":"https://verifier.example.invalid/harness-pack/v1"}' > "$WORK/manifest.json"

# The detector: a Statement judged AGAINST ITS OWN RECEIPT. Prints
# ACCEPT / REJECT <reason> and exits 0 / 1.
cat > "$WORK/detect_desync.py" <<'DETECT'
import json, sys

statement = json.load(open(sys.argv[1]))
receipt = json.load(open(sys.argv[2]))
props = ((statement.get("predicate") or {}).get("properties")) or []
verdict = ((receipt.get("gate") or {}).get("verdict"))
claims = "HARNESS_GATE_PASS" in props
passed = verdict == "PASS"
if claims and not passed:
    print("REJECT the Statement lists HARNESS_GATE_PASS while gate.verdict=%r; "
          "launch_worker.sh exits non-zero on any verdict but PASS" % (verdict,))
    sys.exit(1)
# The other direction is not an error: svr.md:105 lists only PASSING properties,
# so a passing gate MAY be represented by the property and its absence would be
# "not verified", never "failed". What is refused is the claim without the fact.
print("ACCEPT gate.verdict=%r HARNESS_GATE_PASS=%s" % (verdict, claims))
sys.exit(0)
DETECT

# One receipt, composed by the real writer, for a given gate JSON.
make_receipt() {  # $1 = tag, $2 = gate json; prints the receipt path
  local tag="$1" gate="$2" cc="$WORK/$1.cc.json" receipt="$WORK/$1.receipt.json"
  printf '%s' '{"subtype":"success","num_turns":4,"total_cost_usd":0.02,"duration_ms":2000,"session_id":"fixture-session","permission_denials":[]}' > "$cc"
  CC_EXIT=0 GATE_JSON="$gate" \
  BASELINE_JSON='{"verdict":"FAIL","reason":"criteria failed: c1","verity_exit":1,"claims":[{"id":"c1","type":"command","verdict":"FAIL","evidence":"exit 1"}]}' \
  RUN_ID="run-fixture-$tag" SPEC_ID="S-FIXTURE" MODEL_STRING="worker" \
  TIER_RESOLVED="T3" MODEL_USED="HAIKU_CLASS_MODEL" MANIFEST_VERSION="1" \
  CONSTITUTION_HASH="00a92e1544ba9dd55591388830a7f86bf1a8d555e22f455f05b5eb267ecaf97d" \
  TOOL_VERSION="0.0.0-fixture" STARTED_AT="2026-08-13T10:14:00Z" ENDED_AT="2026-08-13T10:15:00Z" \
    python3 "$RECEIPT_WRITER" "$cc" "$receipt" >/dev/null || return 1
  printf '%s' "$receipt"
}

emit() {  # $1 = tag; prints the statement path
  local tag="$1" cc="$WORK/$1.cc.json" receipt="$WORK/$1.receipt.json" st="$WORK/$1.intoto.json" dig
  dig="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$cc")" || return 1
  OUT_PATH="$cc" OUT_SHA256="$dig" HARNESS_MANIFEST="$WORK/manifest.json" \
    python3 "$STATEMENT_WRITER" "$receipt" "$st" >/dev/null 2>&1 || return 1
  printf '%s' "$st"
}

props_of() { python3 -c 'import json,sys;print(",".join(((json.load(open(sys.argv[1])).get("predicate") or {}).get("properties")) or []))' "$1"; }

echo "== bypass_att_result_desync: HARNESS_GATE_PASS never outruns the gate (ADR-019 D4) =="

GATE_PASS='{"verdict":"PASS","reason":"all declared criteria PASS","verity_exit":0,"claims":[{"id":"c1","type":"command","verdict":"PASS","evidence":"exit 0"}]}'
GATE_FAIL='{"verdict":"FAIL","reason":"criteria failed: c1","verity_exit":1,"claims":[{"id":"c1","type":"command","verdict":"FAIL","evidence":"exit 1"}]}'
GATE_STOP='{"verdict":"STOP","reason":"criteria absent from verity report: c1","verity_exit":1,"claims":[{"id":"c1","verdict":"ABSENT","evidence":"criterion id not present in verity report"}]}'
GATE_NONE='{"verdict":"NO-VERDICT","reason":"verity config error (exit 2); gate could not run","verity_exit":2,"claims":[]}'

for tag in pass fail stop noverdict; do
  case "$tag" in
    pass) G="$GATE_PASS" ;;
    fail) G="$GATE_FAIL" ;;
    stop) G="$GATE_STOP" ;;
    *)    G="$GATE_NONE" ;;
  esac
  make_receipt "$tag" "$G" >/dev/null || broken "could not compose the '$tag' receipt"
  emit "$tag" >/dev/null || broken "the emitter refused the '$tag' pair; there is nothing to judge"
done

# ---- control 1: the RED, fabricated once per non-PASS verdict ---------------
# The lenient implementation: a writer that lists the property because the
# property was in hand, without consulting the verdict. Built by editing a
# Statement the emitter wrote, so the fabricated artifact differs from the real
# one in precisely the thing D4 is about.
cat > "$WORK/fabricate_desync.py" <<'FABRICATE'
import json, sys
st = json.load(open(sys.argv[1]))
props = ((st.get("predicate") or {}).get("properties")) or []
if "HARNESS_GATE_PASS" not in props:
    props.insert(2, "HARNESS_GATE_PASS")
st["predicate"]["properties"] = props
json.dump(st, open(sys.argv[2], "w"), sort_keys=True, separators=(",", ":"))
FABRICATE

C1_FAIL=0
for tag in fail stop noverdict; do
  python3 "$WORK/fabricate_desync.py" "$WORK/$tag.intoto.json" "$WORK/$tag.desynced.json" \
    || broken "could not fabricate the desynced Statement for '$tag'"
  OUT="$(python3 "$WORK/detect_desync.py" "$WORK/$tag.desynced.json" "$WORK/$tag.receipt.json")"
  RC=$?
  if [ "$RC" -ne 1 ]; then
    C1_FAIL=1
    note "control 1: the fabricated desync for '$tag' was NOT rejected (rc=$RC): $OUT"
  else
    note "control 1 [$tag]: ${OUT}"
  fi
done
[ "$C1_FAIL" -eq 0 ] || broken "control 1: the detector accepted a Statement claiming a gate pass the receipt denies; its verdicts below mean nothing"

# ---- control 2: a conforming pair is accepted -------------------------------
C2_OUT="$(python3 "$WORK/detect_desync.py" "$WORK/pass.intoto.json" "$WORK/pass.receipt.json")"
C2_RC=$?
[ "$C2_RC" -eq 0 ] || broken "control 2: a gate-PASS receipt and its own Statement were rejected ($C2_OUT); a detector that refuses every HARNESS_GATE_PASS discriminates nothing"
note "control 2: gate-PASS receipt + its emitted Statement -> ${C2_OUT}"
note "           properties: $(props_of "$WORK/pass.intoto.json")"

# ---- the row: what the emitter actually writes -------------------------------
ROW_FAIL=0
for tag in fail stop noverdict; do
  OUT="$(python3 "$WORK/detect_desync.py" "$WORK/$tag.intoto.json" "$WORK/$tag.receipt.json")"
  RC=$?
  P="$(props_of "$WORK/$tag.intoto.json")"
  case ",$P," in
    *,HARNESS_GATE_PASS,*) ROW_FAIL=1; note "the emitter listed HARNESS_GATE_PASS on the '$tag' run: $P" ;;
    *) : ;;
  esac
  if [ "$RC" -ne 0 ]; then
    ROW_FAIL=1
    note "the emitted '$tag' Statement was rejected: $OUT"
  else
    note "row [$tag]: ${OUT}; properties: ${P:-<none>}"
  fi
done

if [ "$ROW_FAIL" -eq 0 ]; then
  echo "GREEN [bypass_att_result_desync] the emitter never lists HARNESS_GATE_PASS on a gate that did not pass"
  note "FAIL, STOP and NO-VERDICT each omit the property; the property's ABSENCE means 'not verified',"
  note "never 'failed' (svr.md:105), and no HARNESS_GATE_FAIL is invented to say the negative"
  note "the RED this row predicted was observed above: three fabricated desyncs, three rejections"
  echo "att_result_desync BYPASS FIXTURE: GREEN"
  exit 0
fi

echo "RED [bypass_att_result_desync] a Statement claims a gate pass its receipt denies"
note "gate.verdict is what launch_worker.sh takes the run's exit from; a Statement that outruns it is"
note "well-formed, machine-readable and untrue -- ADR-019 D2's named failure mode, in the predicate"
note "instead of the subject"
echo "att_result_desync BYPASS FIXTURE: RED"
exit 1
