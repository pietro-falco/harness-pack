#!/usr/bin/env bash
# Falsifier for slice-claim isolation (vault ADR-054 D3: "an unlocked slice per
# `harnesswright next` (machine state in `.harness/locks/`, not ledger prose), a
# dedicated worktree with disjoint scope").
#
# Three invariants, each asserted by racing real processes -- never by reading code:
#
#   I1  N concurrent claimers of ONE slice  -> exactly one acquires.
#   I2  N concurrent claimers of ONE workspace (one git index) -> exactly one acquires.
#   I3  A holder killed with SIGKILL leaves a lease that is reclaimable.
#
# Two claimer models, selected with --mode:
#
#   lease   scripts/slice_lease.py -- the mechanism under test.
#   legacy  the mechanism that shipped before it, modelled literally from
#           harnesswright src/next.ts:126-127 ("A lock is a fact of presence only
#           (ADR-004 D2); its content is audit-only and never parsed" /
#           `existsSync(join(cwd, `.harness/locks/${result.id}.lock`))`) plus the
#           measured fact that no code outside next.test.ts ever creates that file.
#           A pure read, so every claimer wins. This mode exists to be seen red.
#
# Scratch trees live under $TMPDIR and are removed on exit. `mktemp -d` with no
# template resolves to the system temp dir, which the default sandbox posture
# refuses (see .verity/evidence/2026-08-01-adr008-testrun/adr008-tmpdir-probe.txt),
# so every temp path here is templated under $TMPDIR explicitly.
set -uo pipefail

MODE="lease"
CLAIMERS=8
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --claimers) CLAIMERS="${2:-}"; shift 2 ;;
    *) echo "usage: parallel_claim_fixture.sh [--mode lease|legacy] [--claimers N]" >&2; exit 2 ;;
  esac
done
case "$MODE" in lease|legacy) ;; *) echo "unknown --mode: $MODE" >&2; exit 2 ;; esac

PACK="$(cd "$(dirname "$0")/.." && pwd)"
LEASE="$PACK/scripts/slice_lease.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-claim.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

fail=0
note() { printf '  %s\n' "$*"; }

# A scratch repo with a real index, so "the same git index" is a real object and
# not a stand-in.
REPO="$WORK/repo"
mkdir -p "$REPO/.harness/locks"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" config user.email fixture@invalid >/dev/null 2>&1
git -C "$REPO" config user.name fixture >/dev/null 2>&1

# One claimer process. Exits 0 when it believes it holds the claim, non-zero
# otherwise -- the only signal the fixture reads.
#
# A claimer that acquired stays alive until the race has been scored. That is not
# fixture bookkeeping, it is the semantics under test: the lease records a holder
# pid, so a "holder" that had already exited would be correctly reclaimable and
# every later claimer would legitimately win. The launcher holds its lease for the
# life of the run (`--pid $$`), and the claimer models exactly that.
cat > "$WORK/claim.sh" <<'CLAIMER'
#!/usr/bin/env bash
MODE="$1"; REPO="$2"; KEY="$3"; RUNID="$4"; BARRIER="$5"; LEASE="$6"; RCFILE="$7"
# Start barrier: every claimer spins here, so the acquire attempts land inside the
# same few milliseconds instead of being serialised by process startup.
while [ ! -e "$BARRIER" ]; do :; done
if [ "$MODE" = "legacy" ]; then
  # harnesswright src/next.ts:127, literally: a presence check and nothing else.
  # Nothing in the stack writes the file, so the branch is never taken.
  [ -e "$REPO/.harness/locks/$KEY.lock" ] && rc=3 || rc=0
else
  python3 "$LEASE" acquire --root "$REPO" --key "$KEY" --run-id "$RUNID" \
    --ttl 120 --pid $$ >/dev/null 2>&1
  rc=$?
fi
echo "$rc" > "$RCFILE"
# Hold, if we hold, until the scorer says the race is over.
[ "$rc" -eq 0 ] && while [ ! -e "$BARRIER.done" ]; do :; done
exit "$rc"
CLAIMER
chmod +x "$WORK/claim.sh"

race() {
  # race <key> -> prints the number of claimers that exited 0
  # Split: `local a=$1 b=$a` expands every word before any assignment lands.
  local key="$1" i n f winners=0
  local barrier="$WORK/barrier.$key"
  rm -f "$barrier" "$barrier.done" "$WORK"/rc.* 2>/dev/null
  for i in $(seq 1 "$CLAIMERS"); do
    "$WORK/claim.sh" "$MODE" "$REPO" "$key" "run-$i" "$barrier" "$LEASE" "$WORK/rc.$i" &
  done
  : > "$barrier"
  # Score once every claimer has decided; only then release the holders.
  for _ in $(seq 1 400); do
    n=0
    for f in "$WORK"/rc.*; do [ -e "$f" ] && n=$((n + 1)); done
    [ "$n" -ge "$CLAIMERS" ] && break
    sleep 0.05
  done
  : > "$barrier.done"
  wait
  for i in $(seq 1 "$CLAIMERS"); do
    [ "$(cat "$WORK/rc.$i" 2>/dev/null || echo 99)" = "0" ] && winners=$((winners + 1))
  done
  # Leave the tree clean for the next scenario.
  python3 "$LEASE" release --root "$REPO" --key "$key" >/dev/null 2>&1
  printf '%s' "$winners"
}

echo "== parallel claim fixture (mode=$MODE, claimers=$CLAIMERS) =="

# ---- I1: one slice, N claimers, exactly one winner -------------------------
W="$(race S-PARALLEL-001)"
if [ "$W" = "1" ]; then
  echo "ok [I1 same slice: exactly one of $CLAIMERS claimers acquired]"
else
  echo "FAIL [I1 same slice]: $W of $CLAIMERS claimers acquired, expected exactly 1"
  note "two sessions can take the same task; the claim is not atomic"
  fail=1
fi

# ---- I2: one workspace (one git index), N claimers, exactly one winner -----
# `_workspace` is the launcher's index-scoped key. A leading underscore cannot be
# a slice id, so it can never collide with one, and it lives in the same locks
# dir -- which is per-worktree, so two *different* worktrees never contend here.
W="$(race _workspace)"
if [ "$W" = "1" ]; then
  echo "ok [I2 same workspace: exactly one of $CLAIMERS claimers acquired]"
else
  echo "FAIL [I2 same workspace]: $W of $CLAIMERS claimers acquired, expected exactly 1"
  note "two sessions can write $(git -C "$REPO" rev-parse --git-path index 2>/dev/null)"
  fail=1
fi

# ---- I3: SIGKILL must not strand a task forever ----------------------------
if [ "$MODE" = "legacy" ]; then
  echo "skip [I3 SIGKILL reclaim]: legacy claimer holds nothing, so nothing can strand"
else
  rm -f "$REPO/.harness/locks/S-KILL-001.lock"
  # A holder that takes a long lease and is then killed uncleanly: no trap runs,
  # no release is written. A TTL alone would strand the slice for its whole term,
  # so reclaim must not wait for the TTL.
  python3 - "$LEASE" "$REPO" >/dev/null 2>&1 <<'HOLDER' &
import os, subprocess, sys, time
lease, repo = sys.argv[1], sys.argv[2]
# A day-long TTL on purpose: if reclaim needed the lease to expire, this scenario
# would hang for 24h instead of passing. Only holder-death can make it green.
rc = subprocess.call([sys.executable, lease, "acquire", "--root", repo,
                      "--key", "S-KILL-001", "--run-id", "doomed", "--ttl", "86400",
                      "--pid", str(os.getpid())])
if rc != 0:
    sys.exit(rc)
time.sleep(3600)
HOLDER
  HOLDER_PID=$!
  # Wait for the lease to appear rather than sleeping a guessed interval.
  for _ in $(seq 1 200); do
    [ -e "$REPO/.harness/locks/S-KILL-001.lock" ] && break
    sleep 0.05
  done
  if [ ! -e "$REPO/.harness/locks/S-KILL-001.lock" ]; then
    echo "FAIL [I3 SIGKILL reclaim]: holder never acquired the lease"
    fail=1
  else
    kill -9 "$HOLDER_PID" 2>/dev/null
    wait "$HOLDER_PID" 2>/dev/null
    python3 "$LEASE" acquire --root "$REPO" --key S-KILL-001 --run-id successor --ttl 120 \
      >"$WORK/reclaim.out" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
      echo "ok [I3 SIGKILL reclaim: successor acquired a lease held by a killed process]"
    else
      echo "FAIL [I3 SIGKILL reclaim]: successor exited $rc, expected 0"
      note "a killed session strands its task; $(head -c 200 "$WORK/reclaim.out")"
      fail=1
    fi
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo "PARALLEL CLAIM FIXTURE: RED (mode=$MODE)"
  exit 1
fi
echo "PARALLEL CLAIM FIXTURE: GREEN (mode=$MODE)"
