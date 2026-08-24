#!/usr/bin/env bash
# DOSSIER-1 -- an orphan lock blocks nothing; a live lock keeps blocking
# (THR-DOSSIER ESITO 1). THR-RUN measured the defect this fixture holds
# open: a SIGKILLed run leaves lease records naming a dead pid, `next`
# judges eligibility from lock PRESENCE only (harnesswright next.ts:127,
# existsSync), and the one reclaim lives in acquire -- reached only after
# next already refused the slice. Resume therefore needed two manual
# releases. The rule under test: staleness must be applied WHERE
# ELIGIBILITY IS READ -- a lock whose holder is dead (or whose lease is
# expired, the TTL ceiling acquire already honors) is reclaimed before
# `next` answers; a lock whose holder is alive, and a record that does not
# parse (it names no holder to outlive -- lease_window doctrine), are left
# exactly as they are. Mutual exclusion that works is not traded for
# resume. Subject: scripts/slice_lease.py sweep + scripts/launch_worker.sh
# call sites.
# Four arms:
#   1 orphan lock blocks nothing [RED today]: complete lease records naming
#     a dead pid at S1.lock and _workspace.lock, exactly what kill -9
#     leaves -> the sequence sweeps them BY NAME and runs to SEQUENCE
#     COMPLETE with both slices marked, zero manual releases
#   2 live lock keeps blocking: lease naming a live pid -> the sequence
#     launches nothing for S1 and the lock survives byte-identical
#   3 unparsable record is not ours to break: garbage bytes at S1.lock ->
#     the sequence stops, the file survives byte-identical
#   4 expired lease is reclaimed at eligibility: live pid, expires_at in
#     the past -> swept (TTL-ceiling parity with acquire), sequence
#     completes
# GREEN: all four arms hold. RED: any arm fails. UNMEASURED (2): git/node/
# harnesswright/verity CLI absent, or the machinery under test absent.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$ROOT/scripts/launch_worker.sh"
GRAFT="$ROOT/scripts/graft_init.sh"
LEASE="$ROOT/scripts/slice_lease.py"
for f in "$LAUNCHER" "$GRAFT" "$LEASE"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
command -v git >/dev/null || { echo "UNMEASURED: git absent" >&2; exit 2; }
command -v node >/dev/null || { echo "UNMEASURED: node absent" >&2; exit 2; }
# tests/sibling_cli.sh adds a third way to find the CLIs -- a sibling checkout,
# named by a relative constant -- after the environment variable and $PATH,
# neither of which it displaces. Without it this row exits 2 on a tree where
# the stack is checked out but neither package is installed.
[ -f "$ROOT/tests/sibling_cli.sh" ] \
  || { echo "UNMEASURED: tests/sibling_cli.sh absent" >&2; exit 2; }
# shellcheck source=/dev/null
. "$ROOT/tests/sibling_cli.sh"
HW="$(resolve_harnesswright_cli "$ROOT")" \
  || { echo "UNMEASURED: harnesswright CLI not resolvable (set HARNESSWRIGHT_CLI)" >&2; exit 2; }
[ -f "$HW" ] || { echo "UNMEASURED: harnesswright CLI not a file at $HW" >&2; exit 2; }
# Exported, not kept local: the scripts this fixture drives resolve the CLI
# themselves, by the same documented seam (ADR-004 D2, env override first). A
# fixture that resolved a CLI its own subject cannot find would measure the
# resolver and nothing else.
export HARNESSWRIGHT_CLI="$HW"
VY="$(resolve_verity_cli "$ROOT")" \
  || { echo "UNMEASURED: verity CLI not resolvable (set VERITY_CLI)" >&2; exit 2; }
[ -f "$VY" ] || { echo "UNMEASURED: verity CLI not a file at $VY" >&2; exit 2; }
export VERITY_CLI="$VY"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/orphlk.XXXXXX")"
LIVE_PID=""
cleanup() { [ -n "$LIVE_PID" ] && kill "$LIVE_PID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
printf 'Write docs/OUT.md (slice 1) or docs/OUT2.md (slice 2).\n' > "$WORK/task.md"

mkrepo() {
  mkdir -p "$1"; git -C "$1" init -q
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name tester
  git -C "$1" config commit.gpgsign false
  echo seed > "$1/seed.txt"
  git -C "$1" add -- seed.txt && git -C "$1" commit -qm "fixture: seed"
}

mkledger() {
  git init -q "$1"
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name tester
  git -C "$1" config commit.gpgsign false
}

graft2() {
  bash "$GRAFT" --repo "$1" --slice S1 --title "first slice" \
    --task "$WORK/task.md" --tools Read,Write --turns 4 --wall 4m \
    --scope docs --criterion 's1-out=test -f docs/OUT.md' \
    --verifier-id https://example.invalid/verifier/v1 --tier T3 \
    >/dev/null 2>&1 \
    || { echo "UNMEASURED: fresh graft failed on a clean repo" >&2; exit 2; }
  HARNESSWRIGHT_CLI="$HW" bash "$GRAFT" --add --repo "$1" --slice S2 \
    --title "second slice" --task "$WORK/task.md" --tools Read,Write \
    --turns 4 --wall 4m --scope docs \
    --criterion 's2-out=test -f docs/OUT2.md' >/dev/null 2>&1 \
    || { echo "UNMEASURED: --add failed on a clean graft" >&2; exit 2; }
}

# A complete lease record, byte-shaped like cmd_acquire's, at the caller's
# key/pid/expiry -- exactly what a SIGKILLed run leaves behind (the take
# publishes a complete record or nothing).
plant_lock() { # repo key pid expires_at
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, os, socket, sys, time
repo, key, pid, exp = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4])
d = os.path.join(repo, ".harness", "locks")
os.makedirs(d, exist_ok=True)
rec = {"key": key, "run_id": "deadrun-fixture", "pid": pid,
       "host": socket.gethostname(), "acquired_at": time.time() - 60,
       "expires_at": exp, "ttl": 3600.0}
with open(os.path.join(d, key + ".lock"), "w", encoding="utf-8") as fh:
    json.dump(rec, fh, sort_keys=True); fh.write("\n")
PY
}

mkdir -p "$WORK/bin"
cat > "$WORK/bin/claude" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "stub-claude 0.0"; exit 0; fi
cat > /dev/null
mkdir -p docs; : > docs/OUT.md; : > docs/OUT2.md
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0,"duration_ms":1,"session_id":"stub","permission_denials":[]}\n'
STUB
chmod +x "$WORK/bin/claude"

run_seq() {
  ( cd "$1" && \
    env -u HARNESS_MANIFEST \
    PATH="$WORK/bin:$PATH" CONFORMANCE_LEDGER_REPO="$2" \
    HARNESS_HOME="$ROOT" HARNESSWRIGHT_CLI="$HW" VERITY_CLI="$VY" \
    bash "$LAUNCHER" --sequence 2>&1 )
}

receipts_for() {
  python3 - "$1" "$2" <<'PY'
import glob, json, os, sys
root, spec = sys.argv[1], sys.argv[2]
n = 0
for p in glob.glob(os.path.join(root, ".harness/receipts/*.receipt.json")):
    try:
        if json.load(open(p)).get("spec_id") == spec:
            n += 1
    except ValueError:
        pass
print(n)
PY
}

# A pid that is certainly dead: spawned by us, already reaped by us.
( : ) & DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null

# Arm 1 -- what kill -9 leaves must not need an operator: dead-pid leases
# on the slice AND the workspace, then ONE command to the end.
R1="$WORK/r1"; mkrepo "$R1"; graft2 "$R1"; mkledger "$WORK/ledger1"
plant_lock "$R1" S1 "$DEAD_PID" "$(python3 -c 'import time; print(time.time()+3600)')"
plant_lock "$R1" _workspace "$DEAD_PID" "$(python3 -c 'import time; print(time.time()+3600)')"
out="$(run_seq "$R1" "$WORK/ledger1")"; rc=$?
if [ "$rc" -ne 0 ]; then
  echo "RED [arm1]: dead-pid lock still blocks the resume (exit $rc); the reclaim never reached eligibility: $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "SEQUENCE COMPLETE" \
  || { echo "RED [arm1]: sequence did not run to the end past an orphan lock: $out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "SWEPT S1" \
  || { echo "RED [arm1]: the orphan slice lease was not swept by name: $out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "deadrun-fixture" \
  || { echo "RED [arm1]: the sweep does not name the dead run_id it reclaimed: $out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "MARKED slice=S1" \
  || { echo "RED [arm1]: S1 not marked from evidence after the sweep: $out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "MARKED slice=S2" \
  || { echo "RED [arm1]: S2 not marked from evidence after the sweep: $out" >&2; exit 1; }
echo "ok [arm1: dead-pid leases swept by name; one command to the end; zero releases]"

# Arm 2 -- a live holder keeps its lease: nothing launched, nothing touched.
R2="$WORK/r2"; mkrepo "$R2"; graft2 "$R2"; mkledger "$WORK/ledger2"
sleep 300 & LIVE_PID=$!
plant_lock "$R2" S1 "$LIVE_PID" "$(python3 -c 'import time; print(time.time()+3600)')"
H2="$(git hash-object "$R2/.harness/locks/S1.lock")"
out="$(run_seq "$R2" "$WORK/ledger2")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm2]: a LIVE holder's lock was ignored and the sequence ran: mutual exclusion traded for resume: $out" >&2
  exit 1
fi
[ "$(receipts_for "$R2" S1)" = "0" ] \
  || { echo "RED [arm2]: the sequence launched S1 under a live lock" >&2; exit 1; }
[ "$(git hash-object "$R2/.harness/locks/S1.lock")" = "$H2" ] \
  || { echo "RED [arm2]: a live holder's lease was modified" >&2; exit 1; }
kill "$LIVE_PID" 2>/dev/null; LIVE_PID=""
echo "ok [arm2: live lock still blocks; lease byte-identical]"

# Arm 3 -- a record that does not parse names no holder to outlive: left
# alone, and the operator's release remains the documented clear.
R3="$WORK/r3"; mkrepo "$R3"; graft2 "$R3"; mkledger "$WORK/ledger3"
mkdir -p "$R3/.harness/locks"
printf 'not json\n' > "$R3/.harness/locks/S1.lock"
H3="$(git hash-object "$R3/.harness/locks/S1.lock")"
out="$(run_seq "$R3" "$WORK/ledger3")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm3]: an unparsable record was broken on sight (lease_window doctrine violated): $out" >&2
  exit 1
fi
[ "$(receipts_for "$R3" S1)" = "0" ] \
  || { echo "RED [arm3]: the sequence launched S1 past an unparsable lock" >&2; exit 1; }
[ "$(git hash-object "$R3/.harness/locks/S1.lock")" = "$H3" ] \
  || { echo "RED [arm3]: the unparsable record was modified; it is not ours to break" >&2; exit 1; }
echo "ok [arm3: unparsable record left alone; sequence stops]"

# Arm 4 -- expires_at is a ceiling acquire already honors; eligibility now
# agrees: an expired lease, even with a live holder, is reclaimed.
R4="$WORK/r4"; mkrepo "$R4"; graft2 "$R4"; mkledger "$WORK/ledger4"
plant_lock "$R4" S1 "$$" "1"
out="$(run_seq "$R4" "$WORK/ledger4")"; rc=$?
if [ "$rc" -ne 0 ]; then
  echo "RED [arm4]: expired lease still blocks at eligibility (exit $rc): $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "SWEPT S1" \
  || { echo "RED [arm4]: the expired lease was not swept by name: $out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "SEQUENCE COMPLETE" \
  || { echo "RED [arm4]: sequence did not complete past an expired lease: $out" >&2; exit 1; }
echo "ok [arm4: expired lease reclaimed at eligibility; TTL parity with acquire]"

echo "GREEN: orphan locks block nothing, live locks keep blocking, on all four arms"
