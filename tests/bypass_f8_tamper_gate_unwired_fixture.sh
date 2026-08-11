#!/usr/bin/env bash
# F8 -- the tamper detector is never consulted by the launcher: a run launches
# over an enforced tree that the detector, asked directly, calls tampered.
#
# THE SUBJECT is scripts/launch_worker.sh's pack-side gate sequence
# (:47-190) read against scripts/detect_tamper.sh. The detector exists, it is
# fail-closed, `just verify` calls it (Justfile:33,:44) -- and no line of the
# launcher mentions it. The gates the launcher does run are HALT, CLI
# resolution, the tier resolution and the constitution pin; the question "is
# the enforced runtime still the one that was deployed" is not among them.
#
# WHY THAT MATTERS HERE AND NOT ONLY AT DEPLOY TIME. ADR-001's whole shape is
# that the enforced copy under the deploy root is the thing that actually runs:
# templates/settings.mode-b.json:18 points the PreToolUse hook at an absolute
# path inside it, deliberately, so a worker cannot retarget the guard. That
# argument buys nothing if the bytes at that absolute path can drift and no
# launch ever checks. `just verify` checks -- when an operator types it. A run
# launched by anything else does not.
#
# THE THREE ROWS, in the order they run:
#
#   control A  the detector, asked directly about a fabricated enforced root:
#              matching manifest -> DETECT-OK exit 0, one byte changed ->
#              DETECT-FAIL exit 1. It works and it can say no.
#   control B  the launcher's dry-run path IS gated: the same invocation with
#              .harness/HALT present is refused. So a gate that exists fires
#              before the dry-run exit, and row C's silence is an absence
#              rather than an artifact of stopping early.
#   row C      the launcher, run with ENFORCED pointing at the tampered root
#              control A just condemned, reaches DRYRUN ok and exits 0.
#
# LAUNCH_DRYRUN=1 stops the launcher after the last pack-side gate and before
# it writes or spawns anything (:180-183), which is exactly where a tamper gate
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
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$PACK/scripts/launch_worker.sh"
DETECT="$PACK/scripts/detect_tamper.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-f8.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$LAUNCHER" ] || broken "scripts/launch_worker.sh is not where this fixture expects it"
[ -f "$DETECT" ]   || broken "scripts/detect_tamper.sh is not where this fixture expects it"
command -v node >/dev/null 2>&1 \
  || broken "node is not installed; the launcher invokes 'next --json' through it and this row cannot be posed"

echo "== F8 the launcher consults no tamper gate =="

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

# ---- the throwaway repo and the two stub CLIs ------------------------------
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
# The launcher resolves the verity CLI fail-closed and requires the file to
# exist, but does not invoke it before the dry-run exit.
printf 'process.exit(0);\n' > "$WORK/verity.js"
printf -- '---\nid: S-042\ntier: T2\nmode: B\n---\nfixture spec body\n' > "$REPO/S-042.md"

launch() {  # launch -> exit code; stdout+stderr in $WORK/launch.out
  ( cd "$REPO" && LAUNCH_DRYRUN=1 \
      HARNESSWRIGHT_CLI="$WORK/hw.js" VERITY_CLI="$WORK/verity.js" \
      HARNESS_MANIFEST="$PACK/templates/manifest.example.json" \
      ENFORCED="$ENF" \
      bash "$LAUNCHER" "$REPO/S-042.md" ) >"$WORK/launch.out" 2>&1
  echo $?
}

# ---- control B: the dry-run path is gated ----------------------------------
mkdir -p "$REPO/.harness"
: > "$REPO/.harness/HALT"
HALT_RC="$(launch)"
rm -f "$REPO/.harness/HALT"
if [ "$HALT_RC" = "0" ] || ! grep -q 'HALT file present' "$WORK/launch.out"; then
  broken "the dry-run path did not refuse a HALTed repo (rc=$HALT_RC); gates may not fire before the dry-run exit, so row C would measure nothing"
fi
note "control B: the same dry-run invocation is refused when a gate fires (HALT, rc=$HALT_RC)"

# ---- row C: launched over the condemned tree -------------------------------
LAUNCH_RC="$(launch)"
DRY_LINE="$(grep -m1 'DRYRUN' "$WORK/launch.out" 2>/dev/null)"
SRC_REFS="$(grep -c 'detect_tamper' "$LAUNCHER")"

if [ "$LAUNCH_RC" = "0" ] && [ "$SRC_REFS" -eq 0 ]; then
  echo "RED [F8] the launcher launches over a tree its own detector condemns"
  note "ENFORCED pointed at the root control A called DETECT-FAIL, and the"
  note "launcher answered:  $DRY_LINE"
  note "launcher exit                                  : $LAUNCH_RC"
  note "references to detect_tamper in launch_worker.sh : $SRC_REFS"
  note "control B shows a gate that exists does fire on this path, so this is"
  note "the tamper gate being absent, not the dry-run stopping short of it"
  note "the detector is fail-closed and Justfile:33,:44 call it, so the check"
  note "runs exactly when an operator types 'just verify' and at no other time"
  note "settings.mode-b.json:18 pins the hook to an absolute path inside the"
  note "enforced tree so a worker cannot retarget the guard; nothing checks that"
  note "the bytes at that path are still the deployed ones when a run starts"
  note "green when the launcher runs the detector as a pack-side gate and STOPs"
  note "on DETECT-FAIL, beside the HALT and constitution-pin gates it already has"
  echo "F8 BYPASS FIXTURE: RED"
  exit 1
fi

echo "GREEN [F8] the launch was gated on the enforced tree"
note "launcher exit=$LAUNCH_RC over a condemned ENFORCED; detect_tamper references=$SRC_REFS"
echo "F8 BYPASS FIXTURE: GREEN"
exit 0
