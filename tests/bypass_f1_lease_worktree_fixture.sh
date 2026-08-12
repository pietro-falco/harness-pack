#!/usr/bin/env bash
# F1 -- the slice lease is scoped per-toplevel, so two worktrees of ONE repo
# take the SAME slice.
#
# THE SUBJECT is scripts/slice_lease.py composed with the root the launcher
# hands it. launch_worker.sh:52 sets HALT_ROOT from `git rev-parse
# --show-toplevel` and :227 takes the slice lease under that root; slice_lease
# resolves the locks directory as <root>/.harness/locks (:81-86). A linked
# worktree has its own toplevel, therefore its own locks directory, therefore
# its own copy of every lease name -- including the slice id.
#
# The module documents that split at :28-35 and calls it the parallelism it
# enables: "two runs in SEPARATE worktrees never meet and run in parallel".
# That reasoning is stated for `_workspace`, whose subject IS the git index and
# which is genuinely per-worktree. The slice id is not: a slice is a unit of
# WORK, one for the whole repo, and its lease is the thing that stops "two
# sessions [taking] the same task" (:29). Scoping it to the toplevel makes the
# second sentence false while the first stays true.
#
# WHY THIS ROW IS RED BY CONSTRUCTION. Nothing in the take consults the common
# git directory, the repo identity, or anything else two worktrees share. The
# two acquires below touch two different files and neither can see the other.
#
# THE CONTROL comes first and is not optional. It takes the same key twice
# under ONE root and requires the second to be refused. If it were not, this
# fixture would be observing a lease that refuses nobody, and its red would be
# evidence of nothing -- so a control that does not refuse is FIXTURE BROKEN
# (exit 2), never a red.
#
# Exit codes, same convention as tests/adr010_refusal_fixture.sh:
#   0  the invariant holds
#   1  red -- the slice was taken twice
#   2  the fixture could not set its scenario up
#
# Scratch dirs are templated under $TMPDIR (tests/run_tests.sh:11-15) and the
# throwaway repo is isolated from the operator's ~/.gitconfig exactly as
# tests/run_tests.sh:28-34 isolates its own. Nothing absolute is printed.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
LEASE="$PACK/scripts/slice_lease.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-f1.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$LEASE" ] || broken "scripts/slice_lease.py is not where this fixture expects it"

# Same isolation as tests/run_tests.sh:28-34: written into the throwaway repo's
# own .git/config and nowhere else.
init_fixture_repo() {
  git -C "$1" init -q
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name tester
  git -C "$1" config commit.gpgsign false
  git -C "$1" config tag.gpgsign false
}

REPO="$WORK/repo"
WT="$WORK/wt-second"
mkdir -p "$REPO" || broken "could not create the throwaway repo dir"
init_fixture_repo "$REPO" || broken "could not init the throwaway repo"
: > "$REPO/keep"
git -C "$REPO" add -- keep >/dev/null 2>&1 || broken "could not stage the seed file"
git -C "$REPO" commit -q -m "fixture: seed commit" >/dev/null 2>&1 \
  || broken "could not seed the throwaway repo"
git -C "$REPO" worktree add -b fixture-second "$WT" >/dev/null 2>&1 \
  || broken "could not add a second worktree to the throwaway repo"

# Derived exactly as launch_worker.sh:52 derives HALT_ROOT -- the launcher runs
# `git rev-parse --show-toplevel` with its cwd inside the target tree, so the
# fixture asks the same question from each worktree rather than assuming an
# answer.
ROOT_A="$(cd "$REPO" && git rev-parse --show-toplevel 2>/dev/null)"
ROOT_B="$(cd "$WT" && git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT_A" ] || [ -z "$ROOT_B" ]; then
  broken "could not resolve both worktree toplevels"
fi
[ "$ROOT_A" != "$ROOT_B" ] || broken "the two worktrees resolved the same toplevel"

# One repo: `git rev-parse --git-common-dir` is the object store both worktrees
# share, and it is what makes them one repo rather than two clones. Asserted, so
# a red below cannot be read as "two unrelated repos took two unrelated leases".
COMMON_A="$(cd "$REPO" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
COMMON_B="$(cd "$WT" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
if [ -z "$COMMON_A" ] || [ "$COMMON_A" != "$COMMON_B" ]; then
  broken "the two worktrees do not share one git common dir; they are not one repo"
fi

SLICE="S-042"
acq() {  # acq <root> <run-id> -> exit code of the take
  python3 "$LEASE" acquire --root "$1" --key "$SLICE" --run-id "$2" \
    --ttl 600 --pid $$ >/dev/null 2>&1
  echo $?
}

echo "== F1 slice lease is per-toplevel: two worktrees, one slice =="

# ---- control: the lease can refuse -----------------------------------------
# Same root, same key, two run ids. --pid $$ records THIS shell as the holder
# (as launch_worker.sh:224 records its own), so the holder is alive and the
# second take must be HELD (slice_lease.py:78 -> exit 3).
CTL_FIRST="$(acq "$ROOT_A" run-ctl-1)"
CTL_SECOND="$(acq "$ROOT_A" run-ctl-2)"
[ "$CTL_FIRST" = "0" ] \
  || broken "the control's first take did not succeed (rc=$CTL_FIRST); nothing here is measurable"
[ "$CTL_SECOND" = "3" ] \
  || broken "the control's second take was not refused (rc=$CTL_SECOND); a lease that refuses nobody makes the row below evidence of nothing"
note "control: under ONE toplevel the second take of $SLICE is refused (rc=$CTL_SECOND, HELD)"
python3 "$LEASE" release --root "$ROOT_A" --key "$SLICE" --run-id run-ctl-1 >/dev/null 2>&1

# ---- the row ---------------------------------------------------------------
TAKE_A="$(acq "$ROOT_A" run-worktree-a)"
TAKE_B="$(acq "$ROOT_B" run-worktree-b)"
[ "$TAKE_A" = "0" ] \
  || broken "the first worktree could not take the slice at all (rc=$TAKE_A)"

LOCK_A="$ROOT_A/.harness/locks/$SLICE.lock"
LOCK_B="$ROOT_B/.harness/locks/$SLICE.lock"
HOLDER_A="$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])) or {}).get("run_id"))' "$LOCK_A" 2>/dev/null)"
HOLDER_B="$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])) or {}).get("run_id"))' "$LOCK_B" 2>/dev/null)"

if [ "$TAKE_B" = "0" ]; then
  echo "RED [F1] one slice, one repo, two live holders"
  note "worktree A took $SLICE   : rc=$TAKE_A  holder=$HOLDER_A"
  note "worktree B took $SLICE   : rc=$TAKE_B  holder=$HOLDER_B"
  note "the two worktrees share one git common dir, so this is ONE repo and ONE"
  note "slice; they wrote two different lock files because the locks dir is"
  note "resolved under each toplevel (slice_lease.py:81-86) and the launcher"
  note "hands it the toplevel (launch_worker.sh:52, :227)"
  note "the control above shows the lease refusing a second taker under one root,"
  note "so this is the scope of the key, not a lease that never refuses"
  note "green when the second take is refused (rc=3) across worktrees of one repo,"
  note "i.e. when the slice key is scoped to the repo the slice belongs to while"
  note "_workspace stays per-worktree (slice_lease.py:28-35 keeps that half)"
  echo "F1 BYPASS FIXTURE: RED"
  exit 1
fi

echo "GREEN [F1] the second worktree was refused the slice (rc=$TAKE_B)"
note "holder stays $HOLDER_A; one slice, one live run, across worktrees of one repo"
echo "F1 BYPASS FIXTURE: GREEN"
exit 0
