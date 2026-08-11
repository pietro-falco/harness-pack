#!/usr/bin/env bash
# F-c -- `scope` is declared REQUIRED, with a stated shape, and is read by
# nothing in the pack.
#
# THE SUBJECT is templates/spec.mode-b.template.md:21-22 composed with every
# script under scripts/. The template says:
#
#     scope:   # REQUIRED (mode B): non-empty; repo-relative prefixes, no leading / or ..
#
# That is three obligations -- present, non-empty, and shaped -- and the pack
# holds nobody to any of them. The launcher's decision block reads model (:136),
# budget (:139), tools (:148) and criteria (:153) out of next's spec object and
# stops there; scripts/lint_specs.py, the one thing in the pack whose whole job
# is speccheck, lints tier, forbidden model tokens, verify: gate and
# destructive_ops and does not know the field exists. The field is a bound on
# where the worker may write, and it is the one bound in the template that
# nothing downstream can act on: the permission layers the worker actually runs
# under are settings.mode-b.json plus the guard, neither of which is handed the
# spec's scope list. A spec can declare `scope: [src/]` and the run it buys is
# not restricted to src/ by anything.
#
# THE DECISION IS PER-OBLIGATION, one verdict each, and GREEN requires all
# three. A launcher that STOPped on a missing scope but still accepted
# scope: ["/etc", "../../.ssh"] would have closed one obligation of three, and a
# single conjunction with a bare else would have recorded that as a repair.
# Partial enforcement exits 1 with a verdict of its own that names the
# obligation still uncovered.
#
# THE CONTROL IS THE POINT OF THIS FIXTURE, not a preamble. "The launcher
# accepted a spec with no scope" is worth nothing on its own -- a launcher that
# validated nothing at all would produce exactly that observation. So the same
# driver is run FIRST on a spec whose `tools` is empty, and is required to be
# REFUSED at :148-150 with the launcher's own message. tools and scope are
# declared by the same template, in the same voice, one field apart; the
# contrast is that one of them is a gate and the other is decoration.
#
# The source-level half is controlled the same way. A grep for a field read that
# finds nothing proves nothing until it has been shown to find something, so the
# same pattern is first pointed at `tools` -- a field the launcher demonstrably
# reads -- and required to hit. And the pattern is a FIELD READ, not the bare
# substring: F9, one screen over, went green on a workflow that never mentions
# verity because `severity` contains it, and here `scoped` at launch_worker.sh:350
# contains `scope`. A read of a JSON key has to name the key as a quoted literal
# or an attribute, so that is what is counted, alongside the raw word-anchored
# mention count -- two different questions, reported as two numbers.
#
# WHY THE DRIVER IS A FAKE `next`. Same seam as F-b and for the same reason: the
# launcher does not parse specs (ADR-005 D1), so the only way a scope field can
# reach it is through `harnesswright next --json` (:101), and HARNESSWRIGHT_CLI
# is the documented override (launch_worker.sh:11). Everything downstream of
# that JSON is the real launcher running its real gates.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
# Scratch is templated under $TMPDIR (tests/run_tests.sh:11-15) and the
# throwaway repo is isolated from the operator's ~/.gitconfig exactly as
# tests/run_tests.sh:28-34 isolates its own. Nothing absolute is printed.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$PACK/scripts/launch_worker.sh"
TEMPLATE="$PACK/templates/spec.mode-b.template.md"
MANIFEST="$PACK/templates/manifest.example.json"
LINTER="$PACK/scripts/lint_specs.py"

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$LAUNCHER" ] || broken "scripts/launch_worker.sh is not where this fixture expects it"
[ -f "$TEMPLATE" ] || broken "templates/spec.mode-b.template.md is not where this fixture expects it"
[ -f "$MANIFEST" ] || broken "templates/manifest.example.json is not where this fixture expects it"
[ -f "$LINTER" ]   || broken "scripts/lint_specs.py is not where this fixture expects it"
command -v node    >/dev/null 2>&1 || broken "node is not available; the launcher invokes 'node \$HW_CLI next --json'"
command -v git     >/dev/null 2>&1 || broken "git is not available"
command -v python3 >/dev/null 2>&1 || broken "python3 is not available"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-fc.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

# The broken() paths below quote the launcher's own STOP lines, which can name
# the scratch dir or the pack. First line only, with both absolute prefixes
# scrubbed: nothing absolute leaves this fixture on any exit path.
redact() { sed -e "s#$WORK#<scratch>#g" -e "s#$PACK#<pack>#g" "$1" | head -1; }

# Same isolation as tests/run_tests.sh:28-34: written into the throwaway repo's
# own .git/config and nowhere else.
REPO="$WORK/repo"
mkdir -p "$REPO/.harness/specs" || broken "could not create the throwaway repo dir"
git -C "$REPO" init -q                          || broken "could not init the throwaway repo"
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" config user.name tester
git -C "$REPO" config commit.gpgsign false
git -C "$REPO" config tag.gpgsign false
: > "$REPO/keep"
git -C "$REPO" add -- keep >/dev/null 2>&1      || broken "could not stage the seed file"
git -C "$REPO" commit -q -m "fixture: seed commit" >/dev/null 2>&1 \
  || broken "could not seed the throwaway repo"

# The launcher derives REQUESTED_ID from the spec FILENAME only (:94).
SLICE="S-fc"
SPEC="$REPO/.harness/specs/$SLICE.md"
printf '%s\n' "fixture spec body; the launcher never parses it (ADR-005 D1)" > "$SPEC"

HW="$WORK/fake_next.js"
cat > "$HW" <<'JSEOF'
if (process.argv[2] !== "next") {
  process.stderr.write("fake next: unexpected subcommand " + process.argv[2] + "\n");
  process.exit(9);
}
process.stdout.write(process.env.FIXTURE_NEXT_JSON || "");
JSEOF
# Resolved fail-closed at :75-83 before the dryrun exit; never invoked by DRYRUN.
VER="$WORK/fake_verity.js"
: > "$VER"

DRY_OUT="$WORK/dry.out"
DRY_ERR="$WORK/dry.err"
DRY_RC=0
dry() {
  ( cd "$REPO" && \
    FIXTURE_NEXT_JSON="$1" \
    HARNESSWRIGHT_CLI="$HW" \
    VERITY_CLI="$VER" \
    HARNESS_MANIFEST="$MANIFEST" \
    LAUNCH_DRYRUN=1 \
    bash "$LAUNCHER" "$SPEC" ) >"$DRY_OUT" 2>"$DRY_ERR"
  DRY_RC=$?
  return 0
}

# next-json <tools-json> <scope-fragment> -- the two fields under test are the
# only things that vary; model, budget and criteria are identical throughout.
next_json() {
  printf '{"kind":"unlocked","id":"%s","eligible_mode_b":true,"spec":{"model":"worker","budget":{"turns":10,"wall_clock":"15m"},"tools":%s,"criteria":["fixture-claim"]%s}}' \
    "$SLICE" "$1" "$2"
}

# fieldreads NAME FILE... -- lines that READ a JSON/YAML key of that name: an
# attribute access, a subscript, or a .get(), i.e. the key as a literal. Not the
# bare substring, and not a bare word either: `scoped` is a word that contains
# `scope` only as a substring, but `gate scope` in a comment is a whole word and
# still reads nothing.
Q="[\"']"
fieldreads() {
  local n="$1"; shift
  grep -rhE -- "\\.${n}\\b|\\[${Q}${n}${Q}\\]|get\\(${Q}${n}${Q}|\\b${n}=" "$@" 2>/dev/null | wc -l | tr -d ' '
}
mentions() { local n="$1"; shift; grep -rhE -- "\\b${n}\\b" "$@" 2>/dev/null | wc -l | tr -d ' '; }

SRC=("$PACK"/scripts/*.sh "$PACK"/scripts/*.py)

echo "== F-c scope is REQUIRED by the template and read by nothing =="

# ---- control 1: the template declares both fields, in the same voice ---------
grep -Fq 'REQUIRED (mode B): non-empty; repo-relative prefixes, no leading / or ..' "$TEMPLATE" \
  || broken "templates/spec.mode-b.template.md no longer declares scope REQUIRED with that shape; the obligation this row measures has moved"
grep -Fq 'REQUIRED: non-empty YAML list; launcher STOPs if next emits empty spec.tools' "$TEMPLATE" \
  || broken "templates/spec.mode-b.template.md no longer declares tools REQUIRED; the control field this row contrasts against has moved"

# ---- control 2: a REQUIRED field the launcher reads really does refuse -------
# Without this, "scope was accepted" would be an observation about a launcher
# that validates nothing, not about scope.
dry "$(next_json '[]' ', "scope": ["src/"]')"
CTL_RC=$DRY_RC
CTL_MSG="$(grep -m1 'spec.tools' "$DRY_ERR")"
[ "$CTL_RC" != "0" ] \
  || broken "an empty spec.tools was ACCEPTED (rc=$CTL_RC); this launcher refuses nothing, so the row below measures nothing"
[ -n "$CTL_MSG" ] \
  || broken "an empty spec.tools was refused but not by the :148-150 gate; refusal reason was: $(redact "$DRY_ERR")"
note "control: tools:[] is REFUSED (rc=$CTL_RC) -- $CTL_MSG"

# ---- control 3: the read-pattern can find a read ----------------------------
TOOLS_READS="$(fieldreads tools "$LAUNCHER")"
[ "$TOOLS_READS" -gt 0 ] \
  || broken "the field-read pattern found 0 reads of 'tools' in the launcher, which demonstrably reads it at :148; the instrument is broken, not the tree"
note "control: the same field-read pattern finds $TOOLS_READS read(s) of 'tools' in the launcher"

# ---- control 4: the driver can produce an acceptance ------------------------
dry "$(next_json '["Read","Bash"]' ', "scope": ["src/"]')"
LEGAL_RC=$DRY_RC
LEGAL_LINE="$(cat "$DRY_OUT")"
[ "$LEGAL_RC" = "0" ] \
  || broken "the fully-legal spec did not reach the decision line (rc=$LEGAL_RC): $(redact "$DRY_ERR")"
note "control: a spec with a legal scope reaches the decision line (rc=$LEGAL_RC)"

# ---- the rows ---------------------------------------------------------------
# One row per obligation stated at :21-22, each with the violating spec that
# obligation forbids. DRY_ERR is overwritten by the next call, so each row's
# first stderr line is captured on the spot.
# (a) present: the field a REQUIRED declaration says must be there, absent.
dry "$(next_json '["Read","Bash"]' '')"
ABSENT_RC=$DRY_RC
ABSENT_LINE="$(cat "$DRY_OUT")"
ABSENT_MSG="$(redact "$DRY_ERR")"
# (b) non-empty: present, and the empty list the template forbids first.
dry "$(next_json '["Read","Bash"]' ', "scope": []')"
EMPTY_RC=$DRY_RC
EMPTY_LINE="$(cat "$DRY_OUT")"
EMPTY_MSG="$(redact "$DRY_ERR")"
# (c) shaped: present, non-empty, violating both stated shape rules at once.
dry "$(next_json '["Read","Bash"]' ', "scope": ["/etc", "../../.ssh"]')"
ILLEGAL_RC=$DRY_RC
ILLEGAL_LINE="$(cat "$DRY_OUT")"
ILLEGAL_MSG="$(redact "$DRY_ERR")"

SCOPE_READS="$(fieldreads scope "${SRC[@]}")"
SCOPE_MENTIONS="$(mentions scope "${SRC[@]}")"
LINT_SCOPE="$(fieldreads scope "$LINTER")"

SAME="no"
[ "$LEGAL_LINE" = "$ABSENT_LINE" ] && [ "$LEGAL_LINE" = "$EMPTY_LINE" ] \
  && [ "$LEGAL_LINE" = "$ILLEGAL_LINE" ] && SAME="yes"

# outcome <rc> <first-stderr-line> -- how one row ended, in one phrase.
outcome() {
  if [ "$1" = "0" ]; then
    printf 'accepted (rc=%s), reached the decision line' "$1"
  else
    printf 'REFUSED  (rc=%s) -- %s' "$1" "$2"
  fi
}

# tally <label> <rc> -- an obligation is held only when the spec that violates
# it was refused; reaching the decision line leaves it uncovered, by name.
UNCOVERED=""
HELD=0
tally() {
  if [ "$2" = "0" ]; then
    UNCOVERED="${UNCOVERED:+$UNCOVERED, }$1"
  else
    HELD=$((HELD + 1))
  fi
}
tally "present"   "$ABSENT_RC"
tally "non-empty" "$EMPTY_RC"
tally "shaped"    "$ILLEGAL_RC"

if [ "$HELD" = "3" ]; then
  echo "GREEN [F-c] all three obligations at :21-22 are enforced before spawn"
  note "scope absent entirely        : $(outcome "$ABSENT_RC" "$ABSENT_MSG")"
  note "scope []                     : $(outcome "$EMPTY_RC" "$EMPTY_MSG")"
  note "scope [/etc, ../../.ssh]     : $(outcome "$ILLEGAL_RC" "$ILLEGAL_MSG")"
  note "a legal scope still reaches the decision line (rc=$LEGAL_RC), so this is"
  note "enforcement and not a launcher that refuses everything"
  note "scripts/*.{sh,py}            : $SCOPE_READS field reads of 'scope' ($SCOPE_MENTIONS word-anchored mentions)"
  echo "F-c BYPASS FIXTURE: GREEN"
  exit 0
fi

if [ "$HELD" = "0" ]; then
  echo "RED [F-c] a REQUIRED field with a stated shape is enforced by nobody"
else
  echo "RED [F-c] PARTIAL enforcement: $HELD of 3 obligations held, still uncovered: $UNCOVERED"
fi
note "scope absent entirely        : $(outcome "$ABSENT_RC" "$ABSENT_MSG")"
note "scope []                     : $(outcome "$EMPTY_RC" "$EMPTY_MSG")"
note "scope [/etc, ../../.ssh]     : $(outcome "$ILLEGAL_RC" "$ILLEGAL_MSG")"
note "                               (leading / and .., both forbidden by :22)"
note "tools []                     : refused  (rc=$CTL_RC) by the same launcher, one field apart in the same template"
if [ "$HELD" = "0" ]; then
  note "decision line identical across legal / absent / empty / illegal scope: $SAME"
  note "scripts/*.{sh,py}            : $SCOPE_READS field reads of 'scope' ($SCOPE_MENTIONS word-anchored mentions, all prose)"
  note "scripts/lint_specs.py        : $LINT_SCOPE reads -- the pack's only spec linter does not know the field exists"
  note "the pattern that returned $SCOPE_READS returns $TOOLS_READS on 'tools' in the same"
  note "launcher, so the zero is the tree answering and not a grep that misses"
  note "what this leaves unbounded: scope is the spec's statement of where the"
  note "worker may write, and the run's actual write bounds come from"
  note "templates/settings.mode-b.json and the PreToolUse guard, neither of which"
  note "is handed this list -- so a narrow scope buys no narrowing"
else
  note "each obligation is measured on its own, so closing one and leaving the"
  note "rest open is recorded as $UNCOVERED still uncovered, not as a repair"
  note "scripts/*.{sh,py}            : $SCOPE_READS field reads of 'scope' ($SCOPE_MENTIONS word-anchored mentions)"
fi
note "green when ALL THREE violating specs are refused before spawn -- no scope,"
note "scope: [], and prefixes that are absolute or escape the repo -- while a"
note "legal scope still reaches the decision line; anything less is the partial"
note "verdict above, which names the obligation still uncovered"
note "deleting the obligation from templates/spec.mode-b.template.md:21-22 is"
note "recorded as FIXTURE BROKEN (exit 2) by control 1, not as a success -- an"
note "obligation withdrawn is an operator decision, not a repair"
echo "F-c BYPASS FIXTURE: RED"
exit 1
