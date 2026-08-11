#!/usr/bin/env bash
# F8 -- the tamper detector is never consulted by the launcher: a run launches
# over an enforced tree that the detector, asked directly, calls tampered.
#
# THE SUBJECT is scripts/launch_worker.sh's pack-side gate sequence
# (:47-196) read against scripts/detect_tamper.sh. The detector exists, it is
# fail-closed, `just verify` calls it (Justfile:33,:44) -- and no line of the
# launcher mentions it. The gates the launcher does run are HALT, CLI
# resolution, the spec-shape decision, the tier resolution and the constitution
# pin; the question "is the enforced runtime still the one that was deployed"
# is not among them.
#
# WHY THAT MATTERS HERE AND NOT ONLY AT DEPLOY TIME. ADR-001's whole shape is
# that the enforced copy under the deploy root is the thing that actually runs:
# templates/settings.mode-b.json:18 points the PreToolUse hook at an absolute
# path inside it, deliberately, so a worker cannot retarget the guard. That
# argument buys nothing if the bytes at that absolute path can drift and no
# launch ever checks. `just verify` checks -- when an operator types it. A run
# launched by anything else does not.
#
# THREE STATES, because a refusal is not by itself an answer:
#
#   GREEN (0)       the launcher refused AND the refusal is attributable to the
#                   detector.
#   RED (1)         the launcher proceeded (exit 0) over a tree its own detector
#                   condemns.
#   UNMEASURED (2)  the launcher refused for a reason NOT attributable to the
#                   detector. The row never reached its own question: that is
#                   neither a pass nor a fail, and it must not be spelled as
#                   either.
#
# WHY THE THIRD STATE EXISTS. This row used to decide on `exit != 0` alone, with
# a bare else. On 2026-08-11 the spec-scope gate landed one commit ahead of this
# file and made the launcher exit 1 for a reason that has nothing to do with
# tampering; the row printed
#     GREEN [F8] the launch was gated on the enforced tree
#          launcher exit=1 over a condemned ENFORCED; detect_tamper references=0
# -- a gate declared wired with the contrary evidence sitting on its own green
# line. Any refusal, for any reason, was a pass. The third state is the repair.
#
# ATTRIBUTION is the whole of it, and it is read off what the launcher SAID. A
# refusal counts for this row only if the launcher names the tamper condition in
# what it printed; the vocabulary below is the detector's own (detect_tamper.sh
# prints DETECT-FAIL, says "tampered", and names MANIFEST.sha256), plus the
# detector's filename, so a gate that shells out and surfaces its output is
# credited and so is one that says it in its own words. Counting `detect_tamper`
# in the launcher's SOURCE is not the predicate and must not become it: it is
# the same coarse signal as `exit != 0`, only pointed the other way. It is
# printed beside the verdict as corroboration and decides nothing.
#
# THE FOUR ROWS, in the order they run:
#
#   control A  the detector, asked directly about a fabricated enforced root:
#              matching manifest -> DETECT-OK exit 0, one byte changed ->
#              DETECT-FAIL exit 1. It works and it can say no.
#   control B  the launcher's dry-run path IS gated: the same invocation with
#              .harness/HALT present is refused. So a gate that exists fires
#              before the dry-run exit, and row D's silence is an absence
#              rather than an artifact of stopping early.
#   control C  the third state is reachable AND it fires. The same launcher,
#              over an INTACT fabricated enforced root, handed a plan whose
#              spec.scope is absolute -- refused by launch_worker.sh:166-168.
#              No tamper gate, wired or not, could have produced that refusal:
#              the tree it ran over is intact. The decision must therefore
#              degrade to UNMEASURED, and this row asserts it does, with the
#              exit code that verdict carries. A branch never executed is not a
#              gate, so the branch is executed on every run.
#   row D      the launcher, run with ENFORCED pointing at the tampered root
#              control A just condemned.
#
# The controls are separate rows and say so; the row under measurement is still
# row D, over the condemned tree, with the honest stub.
#
# LAUNCH_DRYRUN=1 stops the launcher after the last pack-side gate and before
# it writes or spawns anything (:193-196), which is exactly where a tamper gate
# would sit: every other pack-side gate is above that line, and control B
# proves they fire there. Nothing is spawned, no receipt is written, and the
# operator's real deploy root is never read -- ENFORCED is pinned to a
# fabricated tree under $TMPDIR, the same way tests/run_tests.sh:497 pins it.
#
# WHAT THIS ROW DOES NOT MEASURE: whether the operator's actual deploy is
# intact. That would need the real enforced root and is not this fixture's
# question. This measures that the launcher asks nobody.
#
# `next --json` and the verity CLI are stubs, because the subject is the gate
# sequence and not what a planner returns. They are stubs of the two CLIs the
# launcher resolves fail-closed; everything between them is the real launcher.
# HARNESS_MANIFEST is pinned to the pack's own example so the row does not
# depend on whatever manifest the operator has exported.
#
# Exit codes: 0 invariant holds, 1 red, 2 the row could not be posed
# (UNMEASURED) or the fixture could not set itself up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$PACK/scripts/launch_worker.sh"
DETECT="$PACK/scripts/detect_tamper.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-f8.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

# The detector's own refusal vocabulary, plus its filename. See ATTRIBUTION.
TAMPER_VOCAB='DETECT-FAIL|detect_tamper|tamper|MANIFEST\.sha256'

[ -f "$LAUNCHER" ] || broken "scripts/launch_worker.sh is not where this fixture expects it"
[ -f "$DETECT" ]   || broken "scripts/detect_tamper.sh is not where this fixture expects it"
command -v node >/dev/null 2>&1 \
  || broken "node is not installed; the launcher invokes 'next --json' through it and this row cannot be posed"

echo "== F8 the launcher consults no tamper gate =="

# Corroboration only, printed beside every verdict and read by none of them.
SRC_REFS="$(grep -c 'detect_tamper' "$LAUNCHER")"

# ---- the decision, shared by control C and row D ---------------------------
# One function, so the state control C provokes is the state row D would report:
# a control that exercised a private copy of this logic would prove nothing
# about the row. Prints the verdict block on stdout; returns 0 GREEN, 1 RED,
# 2 UNMEASURED. Reads only the launcher's exit code and the launcher's output.
decide() {  # decide <launcher exit> <launcher output file>
  local rc="$1" out="$2"
  local said named

  said="$(grep -m1 -E 'DRYRUN|STOP' "$out" 2>/dev/null)"
  if grep -Eiq "$TAMPER_VOCAB" "$out" 2>/dev/null; then named="yes"; else named="no"; fi

  if [ "$rc" = "0" ]; then
    echo "RED [F8] the launcher launches over a tree its own detector condemns"
    note "launcher exit                                   : $rc"
    note "the launcher answered                           : $said"
    note "refusal names the tamper condition              : $named (nothing was refused)"
    note "references to detect_tamper in launch_worker.sh : $SRC_REFS (corroboration, not the test)"
    return 1
  fi

  if [ "$named" = "yes" ]; then
    echo "GREEN [F8] the launch was gated on the enforced tree"
    note "launcher exit                                   : $rc"
    note "the launcher's refusal                          : $said"
    note "refusal names the tamper condition              : $named"
    note "references to detect_tamper in launch_worker.sh : $SRC_REFS (corroboration, not the test)"
    return 0
  fi

  echo "UNMEASURED [F8] the launcher refused for a reason it does not attribute to the detector"
  note "launcher exit                                   : $rc"
  note "the launcher's refusal                          : $said"
  note "refusal names the tamper condition              : $named"
  note "references to detect_tamper in launch_worker.sh : $SRC_REFS (corroboration, not the test)"
  note "a refusal the detector cannot be credited with does not answer this row:"
  note "it did not reach its own question, so it is neither a pass nor a fail"
  return 2
}

# ---- control A: a fabricated enforced root, and the real detector ----------
ENF="$WORK/enforced"
mkdir -p "$ENF/scripts" || broken "could not build the fabricated enforced root"
printf 'deployed byte\n' > "$ENF/scripts/guard_pretooluse.py"
( cd "$ENF" && shasum -a 256 scripts/guard_pretooluse.py > MANIFEST.sha256 ) \
  || broken "could not write the fabricated MANIFEST.sha256"
ENFORCED="$ENF" bash "$DETECT" >/dev/null 2>&1
INTACT_RC=$?
printf 'tampered byte\n' > "$ENF/scripts/guard_pretooluse.py"
ENFORCED="$ENF" bash "$DETECT" >"$WORK/detect.out" 2>&1
TAMPERED_RC=$?
[ "$INTACT_RC" -eq 0 ] \
  || broken "the detector refused an INTACT fabricated root (rc=$INTACT_RC); nothing below is measurable"
[ "$TAMPERED_RC" -ne 0 ] \
  || broken "the detector accepted a TAMPERED fabricated root (rc=$TAMPERED_RC); it cannot say no, so the row below measures nothing"
grep -q 'DETECT-FAIL' "$WORK/detect.out" \
  || broken "the detector's refusal did not name DETECT-FAIL"
note "control A: detector says OK on the intact root (rc=$INTACT_RC), DETECT-FAIL on the tampered one (rc=$TAMPERED_RC)"

# A second fabricated root that STAYS intact: control C runs over this one, so
# that its refusal is unattributable by construction and not merely by absence.
ENF_OK="$WORK/enforced-intact"
mkdir -p "$ENF_OK/scripts" || broken "could not build the intact fabricated enforced root"
printf 'deployed byte\n' > "$ENF_OK/scripts/guard_pretooluse.py"
( cd "$ENF_OK" && shasum -a 256 scripts/guard_pretooluse.py > MANIFEST.sha256 ) \
  || broken "could not write the intact fabricated MANIFEST.sha256"
ENFORCED="$ENF_OK" bash "$DETECT" >/dev/null 2>&1
ENF_OK_RC=$?
[ "$ENF_OK_RC" -eq 0 ] \
  || broken "the detector refused the root control C needs intact (rc=$ENF_OK_RC); its refusal would not be unattributable by construction"

# ---- the throwaway repo and the stub CLIs ----------------------------------
REPO="$WORK/repo"
mkdir -p "$REPO" || broken "could not create the throwaway repo dir"
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
// Stub of `harnesswright next --json`: one unlocked, Mode-B-eligible slice.
// scope is REQUIRED of a mode B spec by templates/spec.mode-b.template.md:21 and
// the launcher gates on it; the value is legal, repo-relative, and irrelevant to
// the tamper question this fixture asks, which is decided before any write.
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
cat > "$WORK/hw_badscope.js" <<'JS'
// Control C's stub: byte-for-byte the one above except spec.scope, which is
// absolute and therefore refused at launch_worker.sh:166-168. The refusal is
// the launcher's own and it is real; what it is not is attributable to the
// tamper detector, which is the whole point of the control.
if (process.argv[2] === "next") {
  process.stdout.write(JSON.stringify({
    kind: "unlocked", id: "S-042", eligible_mode_b: true,
    spec: { model: "executor", tools: ["Bash"], criteria: ["C-1"],
            budget: { turns: 3, wall_clock: "5m" }, scope: ["/etc"] }
  }));
  process.exit(0);
}
process.exit(1);
JS
# The launcher resolves the verity CLI fail-closed and requires the file to
# exist, but does not invoke it before the dry-run exit.
printf 'process.exit(0);\n' > "$WORK/verity.js"
printf -- '---\nid: S-042\ntier: T2\nmode: B\n---\nfixture spec body\n' > "$REPO/S-042.md"

launch() {  # launch <hw stub> <enforced root> <output file> -> exit code on stdout
  ( cd "$REPO" && LAUNCH_DRYRUN=1 \
      HARNESSWRIGHT_CLI="$1" VERITY_CLI="$WORK/verity.js" \
      HARNESS_MANIFEST="$PACK/templates/manifest.example.json" \
      ENFORCED="$2" \
      bash "$LAUNCHER" "$REPO/S-042.md" ) >"$3" 2>&1
  echo $?
}

# ---- control B: the dry-run path is gated ----------------------------------
mkdir -p "$REPO/.harness"
: > "$REPO/.harness/HALT"
HALT_RC="$(launch "$WORK/hw.js" "$ENF" "$WORK/launch.halt.out")"
rm -f "$REPO/.harness/HALT"
if [ "$HALT_RC" = "0" ] || ! grep -q 'HALT file present' "$WORK/launch.halt.out"; then
  broken "the dry-run path did not refuse a HALTed repo (rc=$HALT_RC); gates may not fire before the dry-run exit, so row D would measure nothing"
fi
note "control B: the same dry-run invocation is refused when a gate fires (HALT, rc=$HALT_RC)"

# ---- control C: the third state is reachable, and it fires -----------------
CTL_RC="$(launch "$WORK/hw_badscope.js" "$ENF_OK" "$WORK/launch.ctl.out")"
[ "$CTL_RC" != "0" ] \
  || broken "the control's illegal scope was not refused (rc=$CTL_RC); there is no unattributable refusal to degrade on"
grep -q 'spec.scope' "$WORK/launch.ctl.out" \
  || broken "the control was refused, but not by the scope gate: $(head -c 200 "$WORK/launch.ctl.out")"
CTL_BLOCK="$(decide "$CTL_RC" "$WORK/launch.ctl.out")"
CTL_EXIT=$?
[ "$CTL_EXIT" -eq 2 ] \
  || broken "a refusal no tamper gate could have produced did not degrade to UNMEASURED (verdict exit=$CTL_EXIT); the third state is written but not wired"
note "control C: over an INTACT root, an illegal-scope refusal degrades to UNMEASURED (verdict exit=$CTL_EXIT)"
printf '%s\n' "$CTL_BLOCK" | sed 's/^/     control C > /'

# ---- row D: launched over the condemned tree -------------------------------
LAUNCH_RC="$(launch "$WORK/hw.js" "$ENF" "$WORK/launch.out")"
decide "$LAUNCH_RC" "$WORK/launch.out"
VERDICT_EXIT=$?

case "$VERDICT_EXIT" in
  0)
    echo "F8 BYPASS FIXTURE: GREEN"
    exit 0
    ;;
  1)
    note "ENFORCED pointed at the root control A called DETECT-FAIL, and the"
    note "launcher never mentioned it"
    note "control B shows a gate that exists does fire on this path, so this is"
    note "the tamper gate being absent, not the dry-run stopping short of it"
    note "control C shows the row can say 'not measured', so this RED is a"
    note "measurement and not the only thing the row knows how to print"
    note "the detector is fail-closed and Justfile:33,:44 call it, so the check"
    note "runs exactly when an operator types 'just verify' and at no other time"
    note "settings.mode-b.json:18 pins the hook to an absolute path inside the"
    note "enforced tree so a worker cannot retarget the guard; nothing checks that"
    note "the bytes at that path are still the deployed ones when a run starts"
    note "green when the launcher runs the detector as a pack-side gate and STOPs"
    note "on DETECT-FAIL, beside the HALT and constitution-pin gates it already has"
    echo "F8 BYPASS FIXTURE: RED"
    exit 1
    ;;
  2)
    note "the row is not accusing the launcher of anything and is not clearing it"
    note "either; remove the unrelated refusal and run it again"
    echo "F8 BYPASS FIXTURE: UNMEASURED (the row could not be posed; see above)"
    exit 2
    ;;
  *)
    broken "the decision returned $VERDICT_EXIT, which is none of the three states"
    ;;
esac
