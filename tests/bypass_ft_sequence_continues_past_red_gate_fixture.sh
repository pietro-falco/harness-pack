#!/usr/bin/env bash
# RUN-1 -- the sequence is a tracked command that stops where the gate stops
# (THR-RUN ESITO 1). One command takes a grafted repo to the end: slices in
# order, a red gate ends the sequence THERE, and the command says what it
# did. The launch environment is read from the repo and the installation
# (manifest from .harness/manifest.local.json, CLIs env->PATH->STOP, home
# from the script itself); the only thing asked is the observation ledger,
# which is the operator's by doctrine (ADR-004 D2). A sequence that skips a
# failed slice, or proceeds past a red gate, must be refused.
# Subject: scripts/launch_worker.sh --sequence [DIR].
# Five arms:
#   1 red gate stops the sequence: two-slice graft, S1's criterion cannot
#     pass (stub child does no work) -> non-zero exit naming the stop at
#     S1, nothing launched for S2, harness.json unmarked, next re-resolves
#     S1 [the arm that is RED today: no sequence mode exists on disk]
#   2 positive control: stub child does the in-scope work -> ONE command,
#     2 launches, 2 evidenced marks, SEQUENCE COMPLETE, exit 0; rerun
#     launches 0 children
#   3 the one question: CONFORMANCE_LEDGER_REPO unset -> STOP naming the
#     variable before any launch, nothing written
#   4 between-slice scope (ESITO 3): stub writes the criterion file AND an
#     out-of-scope file at the repo root -> gate passes, sequence STOPs
#     after S1 naming the path, S2 never launches
#   5 no-progress: gate passes but the record reads DIVERGENT (stub emits
#     an out-of-surface call), no mark lands -> the sequence STOPs on the
#     no-progress guard instead of relaunching the same slice forever
# GREEN: all five arms hold. RED: any arm fails. UNMEASURED (2): git/node/
# harnesswright/verity CLI absent, or the machinery under test absent.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$ROOT/scripts/launch_worker.sh"
GRAFT="$ROOT/scripts/graft_init.sh"
for f in "$LAUNCHER" "$GRAFT"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
command -v git >/dev/null || { echo "UNMEASURED: git absent" >&2; exit 2; }
command -v node >/dev/null || { echo "UNMEASURED: node absent" >&2; exit 2; }
if [ -n "${HARNESSWRIGHT_CLI:-}" ]; then HW="$HARNESSWRIGHT_CLI"
elif command -v harnesswright >/dev/null 2>&1; then HW="$(command -v harnesswright)"
else echo "UNMEASURED: harnesswright CLI not resolvable (set HARNESSWRIGHT_CLI)" >&2; exit 2; fi
[ -f "$HW" ] || { echo "UNMEASURED: harnesswright CLI not a file at $HW" >&2; exit 2; }
if [ -n "${VERITY_CLI:-}" ]; then VY="$VERITY_CLI"
elif command -v verity >/dev/null 2>&1; then VY="$(command -v verity)"
else echo "UNMEASURED: verity CLI not resolvable (set VERITY_CLI)" >&2; exit 2; fi
[ -f "$VY" ] || { echo "UNMEASURED: verity CLI not a file at $VY" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/seqrun.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
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

# Two-slice graft: S1 fresh, S2 added, both by the real command.
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

# Stub child on PATH: does what STUB_MODE says in the launcher's cwd, then
# emits a stream-json tail (the launcher owns the opening line). Modes:
#   none      -> no work (the gate must fail)
#   work      -> writes both criterion files, minimal conformant stream
#   work-evil -> the work PLUS an out-of-scope file at the repo root
#   divergent -> the work, but the stream carries an out-of-surface call
mkdir -p "$WORK/bin"
cat > "$WORK/bin/claude" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "stub-claude 0.0"; exit 0; fi
cat > /dev/null
case "${STUB_MODE:-none}" in
  work) mkdir -p docs; : > docs/OUT.md; : > docs/OUT2.md ;;
  work-evil) mkdir -p docs; : > docs/OUT.md; : > docs/OUT2.md; : > evil.txt ;;
  divergent)
    mkdir -p docs; : > docs/OUT.md; : > docs/OUT2.md
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu1","name":"Bash","input":{}}]},"parent_tool_use_id":null}\n'
    printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu1","is_error":false}]},"parent_tool_use_id":null}\n'
    ;;
esac
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0,"duration_ms":1,"session_id":"stub","permission_denials":[]}\n'
STUB
chmod +x "$WORK/bin/claude"

# The sequence under test. HARNESS_MANIFEST is deliberately STRIPPED (env -u,
# not merely unexported): reading the manifest from the target's own
# .harness/manifest.local.json is the claim, and a session that exports
# HARNESS_MANIFEST would silently win over it -- the first live THR-RUN
# invocation measured exactly that leak, so the fixture now removes it.
run_seq() {
  ( cd "$1" && \
    env -u HARNESS_MANIFEST \
    PATH="$WORK/bin:$PATH" STUB_MODE="$2" CONFORMANCE_LEDGER_REPO="${3:-}" \
    HARNESS_HOME="$ROOT" HARNESSWRIGHT_CLI="$HW" VERITY_CLI="$VY" \
    bash "$LAUNCHER" --sequence 2>&1 )
}

next_id() {
  ( cd "$1" && node "$HW" next --json 2>/dev/null ) \
    | python3 -c 'import json,sys;r=json.load(sys.stdin);print(r.get("id", r.get("kind")))'
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

# Arm 1 -- a red gate ends the sequence there, loudly, skipping nothing.
R1="$WORK/r1"; mkrepo "$R1"; graft2 "$R1"; mkledger "$WORK/ledger1"
H1="$(git hash-object "$R1/.harness/harness.json")"
out="$(run_seq "$R1" none "$WORK/ledger1")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm1]: S1's gate had to fail and the sequence exited 0: $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "SEQUENCE STOPPED at S1" \
  || { echo "RED [arm1]: no sequence stop naming S1 (a hand loop is still the only sequence): $out" >&2; exit 1; }
[ "$(receipts_for "$R1" S2)" = "0" ] \
  || { echo "RED [arm1]: the sequence launched S2 past S1's red gate" >&2; exit 1; }
[ "$(git hash-object "$R1/.harness/harness.json")" = "$H1" ] \
  || { echo "RED [arm1]: a failed gate moved harness.json" >&2; exit 1; }
[ "$(next_id "$R1")" = "S1" ] \
  || { echo "RED [arm1]: next does not re-resolve the failed slice S1" >&2; exit 1; }
echo "ok [arm1: red gate stops the sequence at S1; nothing skipped]"

# Arm 2 -- the positive control: one command to the end, then an idle rerun.
R2="$WORK/r2"; mkrepo "$R2"; graft2 "$R2"; mkledger "$WORK/ledger2"
out="$(run_seq "$R2" work "$WORK/ledger2")"; rc=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q "SEQUENCE COMPLETE"; } \
  || { echo "RED [arm2]: full sequence did not complete: $out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "MARKED slice=S1" \
  || { echo "RED [arm2]: S1 not marked from evidence: $out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "MARKED slice=S2" \
  || { echo "RED [arm2]: S2 not marked from evidence: $out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "repo .harness/manifest.local.json" \
  || { echo "RED [arm2]: the manifest was not read from the repo (source tag absent -- a bare path grep would also match an env override whose file happens to share the name): $out" >&2; exit 1; }
[ "$(next_id "$R2")" = "all-passed" ] \
  || { echo "RED [arm2]: next is not all-passed after the sequence" >&2; exit 1; }
n_before="$(receipts_for "$R2" S1)"
out="$(run_seq "$R2" work "$WORK/ledger2")"; rc=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q "SEQUENCE COMPLETE"; } \
  || { echo "RED [arm2]: idle rerun did not report complete: $out" >&2; exit 1; }
[ "$(receipts_for "$R2" S1)" = "$n_before" ] \
  || { echo "RED [arm2]: idle rerun launched a child on a passed slice" >&2; exit 1; }
echo "ok [arm2: one command to the end; rerun launches nothing]"

# Arm 3 -- the ledger is the one thing asked; unset is a STOP, not a launch.
R3="$WORK/r3"; mkrepo "$R3"; graft2 "$R3"
out="$(run_seq "$R3" work "")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm3]: no ledger named and the sequence still ran: $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "CONFORMANCE_LEDGER_REPO" \
  || { echo "RED [arm3]: refusal does not name the missing variable: $out" >&2; exit 1; }
[ ! -e "$R3/.harness/receipts" ] \
  || { echo "RED [arm3]: a refused sequence still wrote receipts" >&2; exit 1; }
echo "ok [arm3: no ledger, no launch; the one question is asked by name]"

# Arm 4 -- contamination is named between slices, not at the end.
R4="$WORK/r4"; mkrepo "$R4"; graft2 "$R4"; mkledger "$WORK/ledger4"
out="$(run_seq "$R4" work-evil "$WORK/ledger4")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm4]: out-of-scope write and the sequence ran to the end: $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "SEQUENCE STOPPED after S1" \
  || { echo "RED [arm4]: no between-slice stop after S1: $out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "evil.txt" \
  || { echo "RED [arm4]: the out-of-scope path is not named: $out" >&2; exit 1; }
[ "$(receipts_for "$R4" S2)" = "0" ] \
  || { echo "RED [arm4]: the sequence launched S2 on a contaminated tree" >&2; exit 1; }
echo "ok [arm4: out-of-scope write stops the sequence before the next slice]"

# Arm 5 -- gate passed, record DIVERGENT, no mark: stop, never spin.
R5="$WORK/r5"; mkrepo "$R5"; graft2 "$R5"; mkledger "$WORK/ledger5"
out="$(run_seq "$R5" divergent "$WORK/ledger5")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm5]: unmarkable slice and the sequence claimed completion: $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "no progress" \
  || { echo "RED [arm5]: no no-progress stop on an unmarkable slice: $out" >&2; exit 1; }
[ "$(receipts_for "$R5" S1)" = "1" ] \
  || { echo "RED [arm5]: the unmarkable slice was relaunched instead of stopped" >&2; exit 1; }
echo "ok [arm5: an unmarkable pass stops the sequence; no spin]"

echo "GREEN: the sequence is one command that stops where the gate stops on all five arms"
