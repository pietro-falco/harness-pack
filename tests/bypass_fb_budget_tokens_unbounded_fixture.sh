#!/usr/bin/env bash
# F-b -- a budget the template declares LEGAL buys a run with no turn limit and
# no wall-clock kill.
#
# THE SUBJECT is templates/spec.mode-b.template.md:14 composed with
# scripts/launch_worker.sh:139-147. The template says of `budget`:
#
#     budget:   # REQUIRED: a map with at least one of tokens / turns / wall_clock
#
# so `budget: {tokens: 200000}` satisfies every stated obligation. The launcher
# reads two keys out of that map and only two: :140 `turns` and :143
# `wall_clock`. `tokens` is read by nothing -- the string does not occur in the
# launcher at all. Both dimensions therefore resolve to the sentinel "0", which
# :324-325 documents as "an undeclared dimension (sentinel 0) produces NO flag",
# so :333 emits no --max-turns and :335-339 wraps the spawn in no gtimeout. The
# run that starts is bounded by nothing the spec declared and nothing the
# launcher supplies: the comment at :325 is exactly right that "the old silent
# 15/20 defaults are gone", and that is the defect, because the spec that took
# their place is allowed to declare a dimension the launcher cannot spend.
# :212 takes the same sentinel a third way -- with no wall_clock the slice lease
# TTL silently reverts to the hardcoded 3600.
#
# THE CONTROL IS THE POINT OF THIS FIXTURE, not a preamble. LAUNCH_DRYRUN prints
# max_turns and wall_sec, and a row that showed only "tokens-only prints zeros"
# would be measuring the dryrun printer, not the budget path: zeros are also
# what an instrument that never resolved anything prints. So the same driver is
# run FIRST on a budget carrying turns and wall_clock and is required to come
# back with 10 and 900 -- one declared budget travelling end to end, from next's
# JSON through :139-147 to the decision line. Only against that is the second
# run's pair of zeros a statement about the budget rather than about the harness.
# The link from sentinel to absent flag is asserted separately and literally,
# against the two guard lines themselves, because DRYRUN exits at :180 before
# CMD is built and cannot be asked what flags would have followed.
#
# WHAT COUNTS AS GREEN. The row reads three things -- the accept/refuse verdict,
# max_turns and wall_sec -- so there are exactly three ways it can turn green: a
# STOP on the budget, a resolved turn bound, or a resolved wall-clock bound. The
# green line names which one closed the case, because a default wall_clock with
# turns still unlimited is not the same result as a refusal. Withdrawing the
# declaration from the template is not a fourth way: control 1 reads that
# declaration and its absence is FIXTURE BROKEN (exit 2), by design.
#
# WHY THE DRIVER IS A FAKE `next`. The launcher does not parse specs (ADR-005
# D1); its only budget input is `harnesswright next --json`, invoked at :101 as
# `node "$HW_CLI" next --json`. HARNESSWRIGHT_CLI is the documented seam
# (launch_worker.sh:11), so the fixture hands it a node script that prints the
# JSON under test and asserts it was asked for `next`. Everything between that
# JSON and the decision line is the real launcher, running its real gates. The
# manifest is the shipped templates/manifest.example.json, not a synthetic one,
# so tier resolution is the shipped path too.
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

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$LAUNCHER" ] || broken "scripts/launch_worker.sh is not where this fixture expects it"
[ -f "$TEMPLATE" ] || broken "templates/spec.mode-b.template.md is not where this fixture expects it"
[ -f "$MANIFEST" ] || broken "templates/manifest.example.json is not where this fixture expects it"
command -v node    >/dev/null 2>&1 || broken "node is not available; the launcher invokes 'node \$HW_CLI next --json'"
command -v git     >/dev/null 2>&1 || broken "git is not available"
command -v python3 >/dev/null 2>&1 || broken "python3 is not available"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-fb.XXXXXX")" || exit 2
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

# The launcher derives REQUESTED_ID from the spec FILENAME only (:94), so the id
# in the JSON below must match this basename or :129 STOPs.
SLICE="S-fb"
SPEC="$REPO/.harness/specs/$SLICE.md"
printf '%s\n' "fixture spec body; the launcher never parses it (ADR-005 D1)" > "$SPEC"

# Fake harnesswright: prints the JSON under test on stdout, and refuses any
# subcommand other than `next` so a launcher that stopped asking for it would
# break the fixture rather than pass it.
HW="$WORK/fake_next.js"
cat > "$HW" <<'JSEOF'
if (process.argv[2] !== "next") {
  process.stderr.write("fake next: unexpected subcommand " + process.argv[2] + "\n");
  process.exit(9);
}
process.stdout.write(process.env.FIXTURE_NEXT_JSON || "");
JSEOF
# The launcher resolves verity fail-closed at :75-83 BEFORE the dryrun exit, but
# only checks that the path is a file; DRYRUN never invokes it.
VER="$WORK/fake_verity.js"
: > "$VER"

DRY_OUT="$WORK/dry.out"
DRY_ERR="$WORK/dry.err"
DRY_RC=0
# dry <next-json>  ->  DRY_RC / DRY_OUT / DRY_ERR. Everything from `next --json`
# to the decision line is the real launcher.
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
# field <key> -- pull one key=value out of the DRYRUN decision line (:181).
field() { tr ' ' '\n' < "$DRY_OUT" | grep -m1 "^$1=" | cut -d= -f2-; }

# next-json <budget-json> -- one slice, one model, one tool list, one criterion;
# the budget is the only thing that varies between the control and the row.
next_json() {
  printf '{"kind":"unlocked","id":"%s","eligible_mode_b":true,"spec":{"model":"worker","budget":%s,"tools":["Read","Bash"],"criteria":["fixture-claim"],"scope":["src/"]}}' \
    "$SLICE" "$1"
}

echo "== F-b a budget of only tokens is legal and buys an unbounded run =="

# ---- control 1: the template really does declare tokens sufficient ----------
grep -Fq 'REQUIRED: a map with at least one of tokens / turns / wall_clock' "$TEMPLATE" \
  || broken "templates/spec.mode-b.template.md no longer declares tokens as a sufficient budget; the obligation this row measures has moved"

# ---- control 2: sentinel 0 means no flag, asserted on the guard lines --------
# DRYRUN exits at :180, before CMD exists, so the sentinel-to-flag link cannot be
# observed behaviourally here and is read literally off the two guards instead.
# The `$` in the two searched-for lines is assembled rather than written inside
# single quotes: the pinned shellcheck runs at severity=style, which reports
# SC2016 on a single-quoted `$VAR`, and this tree carries no disable directives.
D='$'
grep -Fq "if [ \"${D}MAXTURNS\" != \"0\" ]; then CMD+=(--max-turns \"${D}MAXTURNS\"); fi" "$LAUNCHER" \
  || broken "launch_worker.sh:333 no longer guards --max-turns on the 0 sentinel; this fixture is reading the wrong shape"
grep -Fq "if [ \"${D}WALLSEC\" != \"0\" ]; then" "$LAUNCHER" \
  || broken "launch_worker.sh:335 no longer guards the timeout wrapper on the 0 sentinel; this fixture is reading the wrong shape"
TOKENS_IN_LAUNCHER="$(grep -cE -- '\btokens\b' "$LAUNCHER")"
note "control: the template declares tokens a sufficient budget; 0 is the no-flag"
note "control: sentinel at :333 and :335; 'tokens' occurs ${TOKENS_IN_LAUNCHER}x in the launcher"

# ---- control 3: a DECLARED budget travels end to end ------------------------
# Without this the row below would only show that a dryrun prints zeros.
dry "$(next_json '{"turns":10,"wall_clock":"15m"}')"
CTL_RC=$DRY_RC
CTL_TURNS="$(field max_turns)"
CTL_WALL="$(field wall_sec)"
[ "$CTL_RC" = "0" ] \
  || broken "the control launch did not reach the decision line (rc=$CTL_RC): $(redact "$DRY_ERR")"
[ "$CTL_TURNS" = "10" ] && [ "$CTL_WALL" = "900" ] \
  || broken "a budget declaring turns:10 and wall_clock:15m resolved to max_turns=$CTL_TURNS wall_sec=$CTL_WALL; this driver is not transmitting budgets, so the row below would measure the instrument"
note "control: budget{turns:10, wall_clock:\"15m\"} -> max_turns=$CTL_TURNS wall_sec=$CTL_WALL (rc=$CTL_RC)"

# ---- the row ----------------------------------------------------------------
dry "$(next_json '{"tokens":200000}')"
ROW_RC=$DRY_RC
ROW_TURNS="$(field max_turns)"
ROW_WALL="$(field wall_sec)"

if [ "$ROW_RC" = "0" ] && [ "$ROW_TURNS" = "0" ] && [ "$ROW_WALL" = "0" ]; then
  echo "RED [F-b] a template-legal budget resolves to no turn limit and no timeout"
  note "budget{tokens:200000}         : accepted (rc=$ROW_RC), max_turns=$ROW_TURNS wall_sec=$ROW_WALL"
  note "budget{turns:10,wall_clock}   : accepted (rc=$CTL_RC), max_turns=$CTL_TURNS wall_sec=$CTL_WALL"
  note "the control is the same driver and the same launcher, so the pair of"
  note "zeros above is the budget path answering, not an unresolved instrument"
  note "0 is the documented no-flag sentinel (:324-325), so this run spawns with"
  note "no --max-turns (:333) and inside no gtimeout/timeout (:335-339); :212"
  note "takes it a third way and reverts the slice lease TTL to a hard 3600"
  note "the declared dimension is spent by nobody: 'tokens' occurs ${TOKENS_IN_LAUNCHER}x in the"
  note "launcher, and next's budget map is read at :140 and :143 only"
  note "green when this same tokens-only budget can no longer reach the decision"
  note "line with both bounds at 0 -- and the row reads three things, so there"
  note "are exactly three ways: the launcher STOPs on a budget whose only"
  note "declared dimension it cannot spend, or it resolves a turn bound, or it"
  note "resolves a wall-clock bound; the green line names which one closed it"
  note "spending 'tokens' as a bound of its own is one of those three only if it"
  note "lands on max_turns or wall_sec -- the two dimensions this row reads"
  note "withdrawing the declaration at templates/spec.mode-b.template.md:14 is"
  note "not a fourth way: control 1 reads that declaration, and its absence is"
  note "recorded as FIXTURE BROKEN (exit 2), which is intended -- an obligation"
  note "withdrawn is an operator decision, not a repair"
  echo "F-b BYPASS FIXTURE: RED"
  exit 1
fi

echo "GREEN [F-b] a tokens-only budget does not buy an unbounded run"
# Which bound closed it is the whole content of this verdict: a default
# wall-clock with turns still unlimited is not the green a STOP is.
if [ "$ROW_RC" != "0" ]; then
  note "closed by REFUSAL: the launcher STOPped on a budget it cannot spend (rc=$ROW_RC)"
  note "stop: $(redact "$DRY_ERR")"
elif [ "$ROW_TURNS" != "0" ] && [ "$ROW_WALL" != "0" ]; then
  note "closed by BOTH bounds: max_turns=$ROW_TURNS wall_sec=$ROW_WALL (rc=$ROW_RC)"
elif [ "$ROW_TURNS" != "0" ]; then
  note "closed by the TURN bound only: max_turns=$ROW_TURNS, wall_sec=$ROW_WALL (rc=$ROW_RC)"
  note "the spawn still carries no timeout (:335-339) and :212 still reverts the"
  note "slice lease TTL to a hard 3600 -- weaker than a STOP, not the same result"
else
  note "closed by the WALL-CLOCK bound only: wall_sec=$ROW_WALL, max_turns=$ROW_TURNS (rc=$ROW_RC)"
  note "the spawn still carries no --max-turns (:333), so turns stay unlimited"
  note "-- weaker than a STOP, not the same result"
fi
echo "F-b BYPASS FIXTURE: GREEN"
exit 0
