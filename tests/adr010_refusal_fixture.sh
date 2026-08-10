#!/usr/bin/env bash
# The two fixtures ADR-010's Verification table declares, in one run.
#
#   fx-refusal-invisible  a cc.json carrying a non-empty permission_denials, fed
#                         to the receipt writer -> the receipt carries
#                         refusals.count == 1 and the verbatim entry.
#   fx-refusal-control    the same run with permission_denials: [] ->
#                         refusals.count == 0, NOT absent, NOT non-zero.
#
# THE SUBJECT is scripts/write_receipt.py, the receipt writer ADR-010 extracted
# out of launch_worker.sh's inline heredoc so that "fed to the receipt writer"
# names something that can be fed. The extraction was a pure move; this fixture
# asserts about the composition, never about the extraction.
#
# WHY THE FIRST ROW IS THE FALSIFIER. Before D1 the writer read five keys off
# the child's JSON and permission_denials was not among them, so the row is red
# by construction and clearable by reading a sixth. Its red was observed and is
# committed under .verity/evidence/.
#
# WHY THE SECOND ROW HAS THREE OUTCOMES AND NOT TWO. ADR-010:181-184 makes the
# control's posture explicit: "It cannot be red before the change, and that is
# the point: it proves the field discriminates rather than firing on every run."
# A control that went red before the change would be a second falsifier, and the
# ADR says it is not one. So its pre-change outcome is the suite's third state
# (tests/run_tests.sh:5-9): with no `refusals` object anywhere in the writer's
# output there is no field whose discrimination could be measured, nothing is
# accused and nothing is claimed. It is red only in the one case that makes a
# control worth having -- the object is present and its count is non-zero on a
# run where nothing was refused, i.e. the field fires regardless and measures
# nothing.
#
# WHAT IS CONSTRUCTED AND WHAT IS REAL. Constructed: the cc.json of both arms,
# and the gate/baseline pair. Real and unmodified: the writer, and every branch
# it takes. ADR-010:186-191 records that this measures the assertion rather than
# the row, and anchors it to the two-arm `claude -p` session in its Basis, where
# permission_denials was measured to be what a refused child actually emits.
#
# Exit codes, same convention as tests/adr008_falsifier_fixture.sh:
#   0  every row is where this fixture expects it
#   1  a row is red
#   2  the fixture could not set its scenario up, or a row went unmeasured --
#      never reported as a red
#
# Scratch dirs are templated under $TMPDIR (same reason as tests/run_tests.sh:
# BSD `mktemp -d` with no template reaches for a per-user temp dir an agent
# session's sandbox denies). Nothing absolute is printed: this output is
# committed as evidence and .verity/claims.json refuses tracked files carrying
# machine paths.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
WRITER="$PACK/scripts/write_receipt.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-adr010.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$WRITER" ] || broken "scripts/write_receipt.py is not where this fixture expects it"

# The denial entry, verbatim from ADR-010:54-56 -- the single entry ARM 2 of the
# measured session emitted. The row asserts the receipt carries THIS object, not
# merely a count, because a count the writer synthesised from something else
# would satisfy a count-only assertion.
cat > "$WORK/cc_denied.json" <<'J'
{"subtype": "success", "num_turns": 2, "is_error": false, "total_cost_usd": 0.0123,
 "duration_ms": 4242, "session_id": "sess-arm2",
 "permission_denials": [{"tool_name": "Bash",
   "tool_use_id": "toolu_01B9gCQL8ejB5BWxUkRpga1H",
   "tool_input": {"command": "grep -c filter-branch notes.txt",
                  "description": "Count occurrences of filter-branch in notes.txt"}}]}
J
# The control arm: ADR-010:40-49 measured every other field identical across the
# two arms, so the only thing that moves here is permission_denials.
cat > "$WORK/cc_clean.json" <<'J'
{"subtype": "success", "num_turns": 2, "is_error": false, "total_cost_usd": 0.0123,
 "duration_ms": 4242, "session_id": "sess-arm1",
 "permission_denials": []}
J
# A run the guard obstructed still meets its criteria unmoved: gate FAIL, and a
# t0 identical to t1, which is the NO_OP that ADR-010's Context says both arms
# collapse onto.
GJ='{"verdict":"FAIL","reason":"criteria failed: C-1","verity_exit":1,"claims":[{"id":"C-1","type":"command","verdict":"FAIL","evidence":"e"}]}'
BJ="$GJ"

compose() {  # compose <cc.json> <out.json> -> writer exit code
  CC_EXIT=0 GATE_JSON="$GJ" BASELINE_JSON="$BJ" \
    RUN_ID=run-adr010 SPEC_ID=S-ADR010-001 MODEL_STRING=executor TIER_RESOLVED=T2 \
    MODEL_USED=SONNET_CLASS_MODEL MANIFEST_VERSION=1 CONSTITUTION_HASH=fixture-hash \
    TOOL_VERSION=fixture STARTED_AT=2026-08-10T00:00:00Z ENDED_AT=2026-08-10T00:00:01Z \
    python3 "$WRITER" "$1" "$2" >/dev/null 2>"$WORK/err"
}

compose "$WORK/cc_denied.json" "$WORK/denied.receipt.json" \
  || broken "the writer did not compose the denied arm: $(head -c 300 "$WORK/err")"
compose "$WORK/cc_clean.json" "$WORK/clean.receipt.json" \
  || broken "the writer did not compose the control arm: $(head -c 300 "$WORK/err")"

# Every reading below comes out of the composed receipts through one reader, so
# the two rows cannot disagree about what the writer wrote.
read_receipts() {
  python3 - "$WORK/denied.receipt.json" "$WORK/clean.receipt.json" "$WORK/cc_denied.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
c = json.load(open(sys.argv[2]))
src = json.load(open(sys.argv[3]))

def g(r, *path):
    cur = r
    for k in path:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(k)
    return cur

print("denied_has_refusals=%s" % ("refusals" in d))
print("clean_has_refusals=%s" % ("refusals" in c))
print("denied_count=%s" % g(d, "refusals", "count"))
print("clean_count=%s" % g(c, "refusals", "count"))
print("denied_tools=%s" % json.dumps(g(d, "refusals", "tools")))
print("clean_tools=%s" % json.dumps(g(c, "refusals", "tools")))
print("clean_denials=%s" % json.dumps(g(c, "refusals", "denials")))
# Verbatim: the receipt's entry must be the child's entry, unmodified.
print("denied_verbatim=%s" % (g(d, "refusals", "denials") == src["permission_denials"]))
# D3, read off the same pair: the refusal moves neither of these.
print("stop_reason_same=%s" % (d.get("stop_reason") == c.get("stop_reason")))
print("stop_reason=%s" % d.get("stop_reason"))
print("contribution_same=%s" % (g(d, "contribution", "verdict") == g(c, "contribution", "verdict")))
print("contribution=%s" % g(d, "contribution", "verdict"))
# D4 is about the schema, not the receipt; what the receipt must not carry is
# the attribution D2 forbids.
print("no_violation_code=%s" % ("violation_code" not in d))
print("no_g3=%s" % ("G3-BLOCKED" not in json.dumps(d)))
PY
}
read_receipts > "$WORK/read.out" 2>"$WORK/read.err" \
  || broken "could not read the composed receipts: $(head -c 300 "$WORK/read.err")"
val() { sed -n "s/^$1=//p" "$WORK/read.out" | head -1; }

# The ordering rule, measured rather than trusted. `refusals.tools` is a
# deduplicated set of names and the receipt is hashed into an append-only chain,
# so a set() iteration order -- randomised per process by Python's string hash
# seed -- would give two identical runs two different digests. Five FRESH
# interpreters is what makes that visible; one process could not see it.
cat > "$WORK/cc_multi.json" <<'J'
{"subtype": "success", "num_turns": 3, "session_id": "sess-multi",
 "permission_denials": [{"tool_name": "Write"}, {"tool_name": "Bash"},
                        {"tool_name": "Edit"}, {"tool_name": "Bash"},
                        {"tool_name": "WebFetch"}]}
J
ORDERS=""
for _ in 1 2 3 4 5; do
  compose "$WORK/cc_multi.json" "$WORK/multi.receipt.json" || break
  ORDERS="$ORDERS$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(json.dumps((r.get("refusals") or {}).get("tools")))' "$WORK/multi.receipt.json")
"
done
DISTINCT="$(printf '%s' "$ORDERS" | sort -u | grep -c .)"
FIRST_ORDER="$(printf '%s' "$ORDERS" | head -1)"
SORTED_ORDER='["Bash", "Edit", "WebFetch", "Write"]'

echo "== ADR-010 refusals in the receipt: two rows (ADR-010 Verification) =="

# ---- fx-refusal-invisible --------------------------------------------------
INVISIBLE="RED"
if [ "$(val denied_has_refusals)" = "True" ] \
   && [ "$(val denied_count)" = "1" ] \
   && [ "$(val denied_verbatim)" = "True" ] \
   && [ "$(val denied_tools)" = '["Bash"]' ] \
   && [ "$DISTINCT" = "1" ] && [ "$FIRST_ORDER" = "$SORTED_ORDER" ]; then
  INVISIBLE="GREEN"
  echo "GREEN [fx-refusal-invisible] the receipt of a refused run carries refusals.count=1,"
  note "tools=$(val denied_tools) and the child's entry verbatim; five fresh interpreters"
  note "agreed on the member order, and it is the sorted one"
  note "D3 holds across the pair: stop_reason=$(val stop_reason) on both arms,"
  note "contribution.verdict=$(val contribution) on both -- the refusal moved neither"
  note "D2 holds: no violation_code=$(val no_violation_code), no G3-BLOCKED=$(val no_g3)"
else
  echo "RED [fx-refusal-invisible] a refused run leaves no trace in the receipt"
  note "cc.json carried permission_denials with 1 entry (tool_name Bash), the entry"
  note "ADR-010:54-56 records verbatim from the measured session's refused arm."
  note "the composed receipt says:"
  note "  refusals present : $(val denied_has_refusals)"
  note "  refusals.count   : $(val denied_count)"
  note "  refusals.tools   : $(val denied_tools)"
  note "  entry verbatim   : $(val denied_verbatim)"
  note "  tools order over 5 fresh interpreters: distinct=$DISTINCT first=$FIRST_ORDER"
  note "the writer reads five keys off the child's JSON and permission_denials is"
  note "not among them, so the array it already receives is discarded (ADR-010:73-77)"
  note "green when the receipt carries refusals.count=1 and the entry unmodified"
fi

# ---- fx-refusal-control ----------------------------------------------------
# Three outcomes, for the reason set out in this file's header.
CONTROL="RED"
if [ "$(val clean_has_refusals)" != "True" ]; then
  CONTROL="UNMEASURED"
  echo "UNMEASURED [fx-refusal-control] the writer emits no refusals object at all, so"
  note "the question this control asks -- does the field discriminate, or does it fire"
  note "on every run -- cannot be posed against this output. Not a red: ADR-010:181-184"
  note "declares this row cannot be red before the change. Not a pass either: nothing"
  note "was measured about a field that does not exist."
  note "it becomes GREEN when a run with permission_denials: [] carries refusals.count=0"
elif [ "$(val clean_count)" = "0" ] \
     && [ "$(val clean_tools)" = "[]" ] \
     && [ "$(val clean_denials)" = "[]" ]; then
  CONTROL="GREEN"
  echo "GREEN [fx-refusal-control] a run with permission_denials: [] carries refusals.count=0"
  note "-- present, not absent, and not non-zero. The field discriminates: the same"
  note "writer wrote count=$(val denied_count) for the refused arm and count=$(val clean_count) for this one,"
  note "off inputs that differ in permission_denials and nothing else"
else
  echo "RED [fx-refusal-control] the refusals object does not discriminate"
  note "a run in which nothing was refused reports:"
  note "  refusals.count   : $(val clean_count)"
  note "  refusals.tools   : $(val clean_tools)"
  note "  refusals.denials : $(val clean_denials)"
  note "a field populated whether or not anything was refused measures nothing"
  note "(ADR-010:183-184)"
fi

echo "-- fx-refusal-invisible=${INVISIBLE} fx-refusal-control=${CONTROL}"

if [ "$INVISIBLE" = "RED" ] || [ "$CONTROL" = "RED" ]; then
  echo "ADR-010 REFUSAL FIXTURE: RED"
  exit 1
fi
if [ "$CONTROL" = "UNMEASURED" ]; then
  echo "ADR-010 REFUSAL FIXTURE: UNMEASURED (1 row could not be posed; see above)"
  exit 2
fi
echo "ADR-010 REFUSAL FIXTURE: GREEN"
exit 0
