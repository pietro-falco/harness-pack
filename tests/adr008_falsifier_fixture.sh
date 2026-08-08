#!/usr/bin/env bash
# Falsifier register for harnesswright ADR-008 (Accepted 2026-08-07),
# "the contribution delta -- a pre-launch baseline, a three-phase gate, and a
# receipt that states its own no-op". The register is normative:
#
#   ADR-008:139  "each row must be **seen red** before the decision it belongs
#                 to is implemented. A row whose red has never been observed
#                 does not count as a gate."
#
# This file is that observation, made executable. It carries three of the eight
# rows -- D6, D1, D3, in that order -- and NOTHING that implements them. The
# launcher, the schema and the receipt writer are read here, never written.
#
#   D6  ADR-008:149 (register) / ADR-008:127 (decision)
#       "launcher-produced receipt validated against the schema | fails on
#        `tier_requested`"
#       Asserted: a receipt produced by scripts/launch_worker.sh in THIS run
#       validates against templates/receipt.schema.json. The receipt is
#       produced, not stubbed, because the row says "produced by the current
#       launcher" and a hand-written stand-in would assert the stand-in.
#
#   D1  ADR-008:143 (register) / ADR-008:47 (decision)
#       "twin runs, criteria green at t0, one working stub / one inert |
#        artifacts identical; no contribution verdict exists"
#       Asserted: two artifacts of twin runs carry contribution verdicts that
#       DIFFER. The twins are tests/fixtures/adr008/twin-{a,b}.receipt.json,
#       derived from the 2026-08-07 exhibit ADR-008:21 describes. Their model
#       id is the *_CLASS_MODEL placeholder (.verity/claims.json,
#       privacy-lint-model-id): the property under test is that the two are
#       indistinguishable, and a placeholder applied to both preserves it.
#
#   D3  ADR-008:146 (register) / ADR-008:93 (decision)
#       "`delta: []` with `CONTRIBUTED`; `NOT_EVALUATED` beside a gate verdict;
#        `NO_OP` with non-empty `delta` | all three accepted"
#       Asserted: the receipt contract REJECTS all three. Each fixture carries
#       every field the schema requires and every enum in range, so the only
#       thing that can reject it is the contribution invariant -- a red here
#       cannot be a red for some other reason.
#
# "The receipt contract" means one thing throughout: the declaration in
# templates/receipt.schema.json, applied by validate_receipt below. One
# validator, used by D6 and by D3, so the two rows cannot disagree about what
# acceptance is.
#
# Modes:
#   (default)      the TDD posture. Exit 0 iff all three rows are GREEN.
#   --expect-red   the register posture. Exit 0 iff all three rows are RED.
#                  This is how tests/run_tests.sh wires it while ADR-008 is
#                  unimplemented, so the red is re-observed on every run
#                  instead of being parked. When a decision lands, its row
#                  goes GREEN, this mode goes red, and the wiring is flipped
#                  to the default -- deliberately, not silently.
#
# Scratch dirs are templated under $TMPDIR: BSD `mktemp -d` with no template
# reaches for the Darwin per-user temp dir, which an agent session's sandbox
# denies (same reason as tests/run_tests.sh:6-10).
set -uo pipefail

MODE="assert-green"
while [ $# -gt 0 ]; do
  case "$1" in
    --expect-red) MODE="expect-red"; shift ;;
    *) echo "usage: adr008_falsifier_fixture.sh [--expect-red]" >&2; exit 2 ;;
  esac
done

PACK="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$PACK/tests/fixtures/adr008"
SCHEMA="$PACK/templates/receipt.schema.json"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-adr008.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

D6_STATE="RED"; D1_STATE="RED"; D3_STATE="RED"
note() { printf '     %s\n' "$*"; }
# A fixture that cannot set its scenario up has measured nothing. Exit 2 is
# reserved for that, and is never reported as a red.
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

# The receipt contract, and the only definition of "accepted" this file uses:
# every key in the schema's `required` list is present, and every property that
# declares an `enum` holds a value from it. Prints ACCEPT / REJECT and exits
# 0 / 1. It is deliberately nothing more -- the schema declares nothing more.
cat > "$WORK/validate_receipt.py" <<'VALIDATOR'
import json, sys
schema = json.load(open(sys.argv[1]))
receipt = json.load(open(sys.argv[2]))
missing = [k for k in schema.get("required", []) if k not in receipt]
bad_enum = [
    "%s=%r" % (k, receipt[k])
    for k, p in (schema.get("properties") or {}).items()
    if k in receipt and "enum" in p and receipt[k] not in p["enum"]
]
if missing or bad_enum:
    print("REJECT missing=%s enum=%s"
          % (",".join(missing) or "-", ",".join(bad_enum) or "-"))
    sys.exit(1)
print("ACCEPT")
VALIDATOR

echo "== ADR-008 falsifier register: D6, D1, D3 =="

# ---- D6 --------------------------------------------------------------------
# ADR-008:149 / ADR-008:127. The receipt is produced by the real launcher over
# stubbed collaborators: harnesswright and verity are node CLIs the launcher
# shells out to, `claude` is the executor. Stubbing them stubs the run, not the
# receipt writer -- which is the code under assertion.
REPO="$WORK/target"
mkdir -p "$REPO/specs" "$REPO/receipts" "$WORK/bin"
git -C "$REPO" init -q 2>/dev/null || broken "could not init the target repo"
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" config user.name tester
git -C "$REPO" config commit.gpgsign false
git -C "$REPO" config tag.gpgsign false

printf 'Fixture slice. The executor is a stub; the launcher is real.\n' \
  > "$REPO/specs/S-DEMO.md"

cat > "$WORK/bin/claude" <<'CLAUDE_STUB'
#!/usr/bin/env bash
# tool_version is read from `claude --version`; the exhibit ADR-008:23 qualifies
# itself the same way, and so does this run.
if [ "${1:-}" = "--version" ]; then echo "0.0.0-fixture (stub)"; exit 0; fi
cat >/dev/null
printf '%s\n' '{"subtype":"success","num_turns":7,"total_cost_usd":0.0412,"duration_ms":41200,"session_id":"fixture-session"}'
CLAUDE_STUB
chmod +x "$WORK/bin/claude"

cat > "$WORK/hw.js" <<'HW_STUB'
// `harnesswright next --json`: one unlocked, Mode-B-eligible slice.
process.stdout.write(JSON.stringify({
  kind: "unlocked",
  id: "S-DEMO",
  eligible_mode_b: true,
  spec: {
    model: "worker",
    tools: ["Read", "Bash"],
    criteria: ["readme-committed", "checks-pass"]
  }
}));
HW_STUB

cat > "$WORK/verity.js" <<'VERITY_STUB'
// `verity verify --json`: both declared criteria PASS, so the gate passes and
// the launcher writes a closure receipt on its success path.
process.stdout.write(JSON.stringify({
  results: [
    { id: "readme-committed", type: "git_committed", verdict: "PASS", evidence: "git show HEAD:README.md exit 0" },
    { id: "checks-pass", type: "command", verdict: "PASS", evidence: "exit 0" }
  ]
}));
VERITY_STUB

cat > "$WORK/manifest.json" <<'MANIFEST'
{
  "manifest_version": 1,
  "model_tiers": { "worker": "T3" },
  "tiers": { "T3": { "name": "subagent", "chain": ["HAIKU_CLASS_MODEL"] } }
}
MANIFEST

# TELEGRAM_* are blanked on purpose: the launcher's notifier is fail-open and
# would otherwise send a real message from a test run.
(
  cd "$REPO" || exit 1
  PATH="$WORK/bin:$PATH" \
  TELEGRAM_BOT_TOKEN="" \
  TELEGRAM_CHAT_ID="" \
  HARNESSWRIGHT_CLI="$WORK/hw.js" \
  VERITY_CLI="$WORK/verity.js" \
  HARNESS_MANIFEST="$WORK/manifest.json" \
  RECEIPTS_DIR="$REPO/receipts" \
  bash "$PACK/scripts/launch_worker.sh" specs/S-DEMO.md
) > "$WORK/launch.out" 2>&1
LAUNCH_RC=$?

RECEIPTS=( "$REPO"/receipts/*.receipt.json )
RECEIPT="${RECEIPTS[0]}"
if [ ! -f "$RECEIPT" ]; then
  sed 's/^/  launcher: /' "$WORK/launch.out" >&2
  broken "the launcher exited $LAUNCH_RC and wrote no receipt; D6 measured nothing"
fi

if D6_OUT="$(python3 "$WORK/validate_receipt.py" "$SCHEMA" "$RECEIPT" 2>&1)"; then
  D6_STATE="GREEN"
  echo "GREEN [D6] launcher receipt validates against templates/receipt.schema.json ($D6_OUT)"
else
  echo "RED [D6] ADR-008:149 register / ADR-008:127 -- a receipt produced by the"
  note "current launcher must validate against templates/receipt.schema.json."
  note "receipt: $(basename "$RECEIPT") (written by scripts/launch_worker.sh, launcher exit $LAUNCH_RC)"
  note "$D6_OUT"
  note "green when the schema and the launcher agree on tier_requested (ADR-008:123)"
fi

# ---- D1 --------------------------------------------------------------------
# ADR-008:143 / ADR-008:47. The premise -- that the twins are indistinguishable
# apart from the four identity/timing fields -- is checked here rather than
# assumed: if it ever stops holding, the row is measuring a different pair and
# must break loudly instead of going quietly red.
D1_OUT="$(python3 - "$FIX/twin-a.receipt.json" "$FIX/twin-b.receipt.json" <<'PY'
import json, sys
a = json.load(open(sys.argv[1]))
b = json.load(open(sys.argv[2]))
IDENTITY = {"run_id", "started_at", "ended_at", "session_id"}
differ = {k for k in set(a) | set(b) if a.get(k) != b.get(k)}
if differ != IDENTITY:
    print("PREMISE the twins differ in %s, expected exactly %s"
          % (sorted(differ) or ["nothing"], sorted(IDENTITY)))
    sys.exit(2)
va = (a.get("contribution") or {}).get("verdict")
vb = (b.get("contribution") or {}).get("verdict")
if va is not None and vb is not None and va != vb:
    print("GREEN a=%s b=%s" % (va, vb))
    sys.exit(0)
print("RED contribution.verdict a=%s b=%s; the two artifacts are indistinguishable"
      % (va if va is not None else "<absent>", vb if vb is not None else "<absent>"))
sys.exit(1)
PY
)"
D1_RC=$?
case "$D1_RC" in
  0) D1_STATE="GREEN"; echo "GREEN [D1] twin artifacts differ in the contribution verdict (${D1_OUT#GREEN })" ;;
  1) echo "RED [D1] ADR-008:143 register / ADR-008:47 -- two artifacts of twin runs whose"
     note "criteria were already PASS at baseline must differ in the contribution verdict."
     note "twins: tests/fixtures/adr008/twin-a.receipt.json, twin-b.receipt.json"
     note "${D1_OUT#RED }"
     note "green when the launcher writes contribution.verdict (ADR-008:83)" ;;
  *) broken "D1 premise: $D1_OUT" ;;
esac

# ---- D3 --------------------------------------------------------------------
# ADR-008:146 / ADR-008:93. "Accepted" is not rhetorical here: each fixture is
# put through the same validator D6 uses, and the count of accepts is the red.
D3_ACCEPTED=""
D3_REJECTED=""
for f in "$FIX"/malformed-*.receipt.json; do
  [ -f "$f" ] || broken "no malformed D3 fixtures found under $FIX"
  if python3 "$WORK/validate_receipt.py" "$SCHEMA" "$f" >/dev/null 2>&1; then
    D3_ACCEPTED="$D3_ACCEPTED $(basename "$f" .receipt.json)"
  else
    D3_REJECTED="$D3_REJECTED $(basename "$f" .receipt.json)"
  fi
done
if [ -z "$D3_ACCEPTED" ]; then
  D3_STATE="GREEN"
  echo "GREEN [D3] all three malformed contribution receipts rejected:$D3_REJECTED"
else
  echo "RED [D3] ADR-008:146 register / ADR-008:93 -- three malformed contribution"
  note "receipts must be rejected by the receipt contract. Accepted:$D3_ACCEPTED"
  note "templates/receipt.schema.json declares $(grep -c 'contribution' "$SCHEMA") rules about contribution,"
  note "so every value of contribution.verdict is legal and none of the three can be refused."
  note "green when the contract expresses D3's total function (ADR-008:89, ADR-008:123)"
fi

# ---- verdict ---------------------------------------------------------------
echo "-- ADR-008 register: D6=$D6_STATE D1=$D1_STATE D3=$D3_STATE"
REDS=0
for s in "$D6_STATE" "$D1_STATE" "$D3_STATE"; do
  [ "$s" = "RED" ] && REDS=$((REDS + 1))
done

if [ "$MODE" = "expect-red" ]; then
  if [ "$REDS" -eq 3 ]; then
    echo "ADR-008 FALSIFIER FIXTURE: 3/3 rows RED as the register requires"
    exit 0
  fi
  echo "ADR-008 FALSIFIER FIXTURE: only $REDS/3 rows are RED"
  note "a row went green with no implementation behind it, or an implementation"
  note "landed and this fixture is still wired --expect-red in tests/run_tests.sh"
  exit 1
fi
if [ "$REDS" -eq 0 ]; then
  echo "ADR-008 FALSIFIER FIXTURE: GREEN"
  exit 0
fi
echo "ADR-008 FALSIFIER FIXTURE: RED ($REDS/3 rows)"
exit 1
