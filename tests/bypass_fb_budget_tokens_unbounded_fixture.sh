#!/usr/bin/env bash
# F-b -- `budget` is declared REQUIRED with a stated shape, and the launcher
# holds nobody to either half of that declaration.
#
# THE SUBJECT is templates/spec.mode-b.template.md:14 composed with
# scripts/launch_worker.sh:139-147. The template says of `budget`:
#
#     budget:   # REQUIRED: a map with at least one of tokens / turns / wall_clock
#
# That is TWO obligations, not one -- the map must be PRESENT, and it must carry
# a dimension the launcher can SPEND -- and :139 holds neither:
#
#     budget = spec.get("budget") or {}
#
# `or {}` is the whole of it. A spec carrying no budget at all and a spec
# declaring `budget: {tokens: 200000}` reach :140 and :142 as the same empty
# map, and both leave with maxturns="0" and wallsec="0". The declaration is
# defective in its own right: `tokens` is offered as a sufficient dimension and
# is spent by nobody -- the word does not occur in the launcher at all.
#
# WHAT THE SENTINEL BUYS. 0 is the documented no-flag value (:337-338: "an
# undeclared dimension (sentinel 0) produces NO flag ... The old silent 15/20
# defaults are gone"), so :346 emits no --max-turns and :348-352 wraps the spawn
# in no gtimeout/timeout. :224-225 takes the same sentinel a third way -- with
# wallsec 0 the slice lease TTL stays at the hardcoded 3600. The run that starts
# is bounded by nothing the spec declared and nothing the launcher supplies.
#
# THE DECISION IS PER-OBLIGATION, one verdict each, and GREEN requires both. A
# launcher that STOPped on a missing budget while still accepting a tokens-only
# one would have closed one obligation of two, and a single conjunction with a
# bare else would have recorded that as a repair. Partial enforcement exits 1
# with a verdict of its own that names the obligation still uncovered.
#
# WHAT CLOSES A ROW. Each row reads three things -- the accept/refuse verdict,
# max_turns and wall_sec -- so an obligation can be held in exactly three ways:
# a STOP on the budget, a resolved turn bound, or a resolved wall-clock bound.
# Every row names which one closed it, because a default wall_clock with turns
# still unlimited is not the same result as a refusal. Spending `tokens` as a
# bound of its own is one of those three only if it lands on max_turns or
# wall_sec, the two dimensions these rows read. Withdrawing the declaration from
# the template is not a fourth way: control 1 reads that declaration and its
# absence is FIXTURE BROKEN (exit 2), by design -- an obligation withdrawn is an
# operator decision, not a repair.
#
# THE CONTROLS ARE THE POINT OF THIS FIXTURE, not a preamble.
#
#   control 1  the template really does declare what these rows measure. Its
#              absence is exit 2, never a pass.
#   control 2  0 really is the no-flag sentinel, read literally off the two
#              guard lines. LAUNCH_DRYRUN exits at :193-196, before CMD is
#              built, so the sentinel-to-absent-flag link cannot be observed
#              behaviourally here and is asserted against the source instead.
#   control 3  a DECLARED budget travels end to end. LAUNCH_DRYRUN prints
#              max_turns and wall_sec, and a row showing only "these print
#              zeros" would be measuring the dryrun printer: zeros are also what
#              an instrument that never resolved anything prints. The same
#              driver is therefore run FIRST on budget{turns:10, wall_clock:15m}
#              and is required to come back with 10 and 900. Only against that
#              is a pair of zeros a statement about the budget path. It is one
#              control for both rows.
#   control 4  the PARTIAL branch is reachable and it fires. Both rows landing
#              on the same side would leave that branch written and never
#              executed, and a branch never executed is not a gate. So decide()
#              -- the same function the rows are judged by, not a copy of it --
#              is handed a genuinely mixed pair, measured through the same
#              dry()/field() driver against a fabricated HALF-ENFORCING launcher
#              that STOPs on an absent budget and accepts a tokens-only one. The
#              control asserts the verdict degrades to PARTIAL and names
#              `spendable`, and is FIXTURE BROKEN otherwise. The stand-in is
#              built under $TMPDIR; scripts/launch_worker.sh is untouched.
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

# Control 4's stand-in: a FABRICATED half-enforcing launcher, and nothing else
# in this fixture runs against it. It holds the `present` obligation and leaves
# `spendable` open, which is the mixed state neither row can produce on its own
# -- both rows land on the same side of any given tree, so the PARTIAL branch
# would otherwise never execute. It reaches its budget through the same
# `node $HARNESSWRIGHT_CLI next --json` seam and answers on the same decision
# line, so dry() and field() drive it unchanged.
STANDIN="$WORK/standin_half_enforcing.sh"
cat > "$STANDIN" <<'SHEOF'
#!/usr/bin/env bash
set -uo pipefail
NEXT_JSON="$(node "$HARNESSWRIGHT_CLI" next --json)" || exit 1
NEXT_JSON="$NEXT_JSON" python3 <<'PYEOF'
import json, os, re, sys
spec = json.loads(os.environ["NEXT_JSON"]).get("spec") or {}
budget = spec.get("budget")
if not isinstance(budget, dict):
    print("STOP spec.budget missing (stand-in holds PRESENT and nothing else)", file=sys.stderr)
    sys.exit(1)
turns = budget.get("turns")
maxturns = str(turns) if isinstance(turns, int) and turns > 0 else "0"
wc = budget.get("wall_clock")
m = re.match(r"^(\d+)(m|h)$", wc) if isinstance(wc, str) else None
wallsec = str(int(m.group(1)) * (60 if m.group(2) == "m" else 3600)) if m else "0"
print(f"DRYRUN ok id=stand-in max_turns={maxturns} wall_sec={wallsec}")
PYEOF
SHEOF

DRY_OUT="$WORK/dry.out"
DRY_ERR="$WORK/dry.err"
DRY_RC=0
# dry <launcher> <next-json>  ->  DRY_RC / DRY_OUT / DRY_ERR. For every row and
# for control 3 the launcher is the real one, and everything from `next --json`
# to the decision line is the real launcher. Control 4 passes the stand-in.
dry() {
  ( cd "$REPO" && \
    FIXTURE_NEXT_JSON="$2" \
    HARNESSWRIGHT_CLI="$HW" \
    VERITY_CLI="$VER" \
    HARNESS_MANIFEST="$MANIFEST" \
    LAUNCH_DRYRUN=1 \
    bash "$1" "$SPEC" ) >"$DRY_OUT" 2>"$DRY_ERR"
  DRY_RC=$?
  return 0
}
# field <key> -- pull one key=value out of the DRYRUN decision line (:194).
field() { tr ' ' '\n' < "$DRY_OUT" | grep -m1 "^$1=" | cut -d= -f2-; }

# next-json <budget-fragment> -- one slice, one model, one tool list, one
# criterion, one legal scope; the budget is the only thing that varies, and it
# varies by FRAGMENT so that the `present` row can omit the key entirely rather
# than declare it null.
next_json() {
  printf '{"kind":"unlocked","id":"%s","eligible_mode_b":true,"spec":{"model":"worker"%s,"tools":["Read","Bash"],"criteria":["fixture-claim"],"scope":["src/"]}}' \
    "$SLICE" "$1"
}

# closure <rc> <turns> <wall> -- how one row ended, in one phrase, naming which
# of the three closes it. Returns 0 when the obligation is HELD, 1 when the row
# reached the decision line with both bounds still at the sentinel.
closure() {
  if [ "$1" != "0" ]; then
    printf 'REFUSED  (rc=%s)' "$1"
    return 0
  fi
  if [ "$2" != "0" ] && [ "$3" != "0" ]; then
    printf 'accepted (rc=%s), closed by BOTH bounds: max_turns=%s wall_sec=%s' "$1" "$2" "$3"
    return 0
  fi
  if [ "$2" != "0" ]; then
    printf 'accepted (rc=%s), closed by the TURN bound only: max_turns=%s, wall_sec=%s' "$1" "$2" "$3"
    return 0
  fi
  if [ "$3" != "0" ]; then
    printf 'accepted (rc=%s), closed by the WALL-CLOCK bound only: wall_sec=%s, max_turns=%s' "$1" "$3" "$2"
    return 0
  fi
  printf 'accepted (rc=%s), UNBOUNDED: max_turns=%s wall_sec=%s' "$1" "$2" "$3"
  return 1
}

# rowline <label> <rc> <turns> <wall> <first stderr line>
rowline() {
  local ph
  ph="$(closure "$2" "$3" "$4")"
  if [ "$2" != "0" ]; then ph="$ph -- $5"; fi
  note "$(printf '%-29s: %s' "$1" "$ph")"
}

# decide <present rc,turns,wall,msg> <spendable rc,turns,wall,msg>
# One verdict per obligation, GREEN only when both are held. Prints the verdict
# block on stdout; returns 0 GREEN, 1 RED (whole or partial). Control 4 and the
# rows go through this one function: a control exercising a private copy of it
# would prove nothing about the rows.
decide() {
  local a_rc="$1" a_t="$2" a_w="$3" a_m="$4"
  local b_rc="$5" b_t="$6" b_w="$7" b_m="$8"
  local a_held=0 b_held=0 held=0 uncovered=""

  closure "$a_rc" "$a_t" "$a_w" >/dev/null; a_held=$?
  closure "$b_rc" "$b_t" "$b_w" >/dev/null; b_held=$?
  if [ "$a_held" -eq 0 ]; then held=$((held + 1)); else uncovered="present"; fi
  if [ "$b_held" -eq 0 ]; then held=$((held + 1)); else uncovered="${uncovered:+$uncovered, }spendable"; fi

  if [ "$held" -eq 2 ]; then
    echo "GREEN [F-b] both obligations at :14 are held before spawn"
  elif [ "$held" -eq 0 ]; then
    echo "RED [F-b] neither half of a REQUIRED declaration is held: an absent budget and a tokens-only budget both buy an unbounded run"
  else
    echo "RED [F-b] PARTIAL enforcement: $held of 2 obligations held, still uncovered: $uncovered"
  fi

  rowline "budget absent entirely"      "$a_rc" "$a_t" "$a_w" "$a_m"
  rowline "budget {tokens: 200000}"     "$b_rc" "$b_t" "$b_w" "$b_m"
  rowline "budget {turns:10, wall_clock}" "$CTL_RC" "$CTL_TURNS" "$CTL_WALL" ""
  note "                               (control 3: the same driver, the real launcher)"

  if [ "$held" -eq 2 ]; then
    note "a declared, spendable budget still reaches the decision line, so this is"
    note "enforcement and not a launcher that refuses every budget"
    return 0
  fi

  if [ "$held" -eq 0 ]; then
    note "the control above is the same driver and the same launcher, so the pairs"
    note "of zeros are the budget path answering, not an unresolved instrument"
    note "0 is the documented no-flag sentinel (:337-338), so such a run spawns"
    note "with no --max-turns (:346) and inside no gtimeout/timeout (:348-352);"
    note ":224-225 takes it a third way and leaves the slice lease TTL at 3600"
    note "the dimension the template calls sufficient is spent by nobody:"
    note "'tokens' occurs ${TOKENS_IN_LAUNCHER}x in the launcher, and next's budget map is read"
    note "at :140 and :143 only -- :139 turns both violations into the same {}"
  else
    note "each obligation is measured on its own, so closing one and leaving the"
    note "other open is recorded as $uncovered still uncovered, not as a repair"
  fi
  note "green when BOTH violating specs stop being able to reach the decision"
  note "line with both bounds at 0 -- and each row reads three things, so there"
  note "are exactly three ways per row: the launcher STOPs on a budget it cannot"
  note "spend, or it resolves a turn bound, or it resolves a wall-clock bound;"
  note "each row names which one closed it, because a wall-clock default with"
  note "turns still unlimited is not the result a refusal is"
  note "withdrawing the declaration at templates/spec.mode-b.template.md:14 is"
  note "not a further way: control 1 reads that declaration, and its absence is"
  note "recorded as FIXTURE BROKEN (exit 2), which is intended -- an obligation"
  note "withdrawn is an operator decision, not a repair"
  return 1
}

echo "== F-b budget is REQUIRED with a stated shape and neither half is held =="

# ---- control 1: the template really does declare both halves ----------------
grep -Fq 'REQUIRED: a map with at least one of tokens / turns / wall_clock' "$TEMPLATE" \
  || broken "templates/spec.mode-b.template.md no longer declares budget REQUIRED with at least one of tokens / turns / wall_clock; the obligations these rows measure have moved"

# ---- control 2: sentinel 0 means no flag, asserted on the guard lines --------
# DRYRUN exits at :193-196, before CMD exists, so the sentinel-to-flag link
# cannot be observed behaviourally here and is read literally off the two guards
# instead. The `$` in the two searched-for lines is assembled rather than
# written inside single quotes: the pinned shellcheck runs at severity=style,
# which reports SC2016 on a single-quoted `$VAR`, and this tree carries no
# disable directives.
D='$'
grep -Fq "if [ \"${D}MAXTURNS\" != \"0\" ]; then CMD+=(--max-turns \"${D}MAXTURNS\"); fi" "$LAUNCHER" \
  || broken "launch_worker.sh:346 no longer guards --max-turns on the 0 sentinel; this fixture is reading the wrong shape"
grep -Fq "if [ \"${D}WALLSEC\" != \"0\" ]; then" "$LAUNCHER" \
  || broken "launch_worker.sh:348 no longer guards the timeout wrapper on the 0 sentinel; this fixture is reading the wrong shape"
TOKENS_IN_LAUNCHER="$(grep -cE -- '\btokens\b' "$LAUNCHER")"
note "control 1: the template declares budget REQUIRED, tokens among the dimensions it calls sufficient"
note "control 2: the no-flag sentinel is guarded at :346 and :348; 'tokens' occurs ${TOKENS_IN_LAUNCHER}x in the launcher"

# ---- control 3: a DECLARED budget travels end to end, for both rows ---------
# Without this, a row of zeros below would only show that a dryrun prints zeros.
dry "$LAUNCHER" "$(next_json ',"budget":{"turns":10,"wall_clock":"15m"}')"
CTL_RC=$DRY_RC
CTL_TURNS="$(field max_turns)"
CTL_WALL="$(field wall_sec)"
[ "$CTL_RC" = "0" ] \
  || broken "the control launch did not reach the decision line (rc=$CTL_RC): $(redact "$DRY_ERR")"
if [ "$CTL_TURNS" != "10" ] || [ "$CTL_WALL" != "900" ]; then
  broken "a budget declaring turns:10 and wall_clock:15m resolved to max_turns=$CTL_TURNS wall_sec=$CTL_WALL; this driver is not transmitting budgets, so the rows below would measure the instrument"
fi
note "control 3: budget{turns:10, wall_clock:\"15m\"} -> max_turns=$CTL_TURNS wall_sec=$CTL_WALL (rc=$CTL_RC)"

# ---- control 4: the PARTIAL branch is reachable, and it fires ----------------
# Measured, not asserted: the stand-in is driven by the same dry() and read by
# the same field(), and its two outcomes are handed to the same decide().
dry "$STANDIN" "$(next_json '')"
SI_ABSENT_RC=$DRY_RC
SI_ABSENT_MSG="$(redact "$DRY_ERR")"
[ "$SI_ABSENT_RC" != "0" ] \
  || broken "the half-enforcing stand-in accepted a spec with no budget (rc=$SI_ABSENT_RC); it does not hold the obligation control 4 needs held"
dry "$STANDIN" "$(next_json ',"budget":{"tokens":200000}')"
SI_TOKENS_RC=$DRY_RC
SI_TOKENS_TURNS="$(field max_turns)"
SI_TOKENS_WALL="$(field wall_sec)"
if [ "$SI_TOKENS_RC" != "0" ] || [ "$SI_TOKENS_TURNS" != "0" ] || [ "$SI_TOKENS_WALL" != "0" ]; then
  broken "the half-enforcing stand-in did not leave the tokens-only budget open (rc=$SI_TOKENS_RC max_turns=$SI_TOKENS_TURNS wall_sec=$SI_TOKENS_WALL); there is no mixed pair to degrade on"
fi
CTL4_BLOCK="$(decide "$SI_ABSENT_RC" "0" "0" "$SI_ABSENT_MSG" \
                     "$SI_TOKENS_RC" "$SI_TOKENS_TURNS" "$SI_TOKENS_WALL" "")"
CTL4_EXIT=$?
[ "$CTL4_EXIT" -eq 1 ] \
  || broken "a mixed pair did not produce a RED verdict (verdict exit=$CTL4_EXIT); the per-obligation decision is not wired"
printf '%s' "$CTL4_BLOCK" | grep -Fq 'PARTIAL enforcement: 1 of 2 obligations held, still uncovered: spendable' \
  || broken "a pair holding only 'present' did not degrade to the PARTIAL verdict naming 'spendable'; the partial branch is written but not wired"
note "control 4: against a fabricated half-enforcing launcher, one held obligation"
note "           and one open one degrade to PARTIAL, naming the open one (exit=$CTL4_EXIT)"
printf '%s\n' "$CTL4_BLOCK" | sed 's/^/     control 4 > /'

# ---- the rows ---------------------------------------------------------------
# One row per obligation stated at :14, each with the spec that obligation
# forbids. DRY_ERR is overwritten by the next call, so each row's first stderr
# line is captured on the spot.
# (a) present: the map a REQUIRED declaration says must be there, absent.
dry "$LAUNCHER" "$(next_json '')"
ABSENT_RC=$DRY_RC
ABSENT_TURNS="$(field max_turns)"
ABSENT_WALL="$(field wall_sec)"
ABSENT_MSG="$(redact "$DRY_ERR")"
# (b) spendable: present, and carrying only the dimension nothing can spend.
dry "$LAUNCHER" "$(next_json ',"budget":{"tokens":200000}')"
TOKENS_RC=$DRY_RC
TOKENS_TURNS="$(field max_turns)"
TOKENS_WALL="$(field wall_sec)"
TOKENS_MSG="$(redact "$DRY_ERR")"

decide "$ABSENT_RC" "$ABSENT_TURNS" "$ABSENT_WALL" "$ABSENT_MSG" \
       "$TOKENS_RC" "$TOKENS_TURNS" "$TOKENS_WALL" "$TOKENS_MSG"
VERDICT_EXIT=$?

if [ "$VERDICT_EXIT" -eq 0 ]; then
  echo "F-b BYPASS FIXTURE: GREEN"
  exit 0
fi
echo "F-b BYPASS FIXTURE: RED"
exit 1
