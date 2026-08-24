#!/usr/bin/env bash
# SEQ-1 -- completion is a consequence of evidence, never an author's flag
# (THR-SEQ ESITO 1). A slice reads as passed ONLY because its gate passed in
# a run whose anchored conformance record verifies; a slice hand-marked
# passed without that evidence must STOP the launcher before anything is
# built on top of it. Subject: scripts/launch_worker.sh (validate-passed,
# fired before `next --json` is consumed, dry-run path included) and
# scripts/launch_checks.py mark-passed (the single writer).
# Five arms:
#   1 hand-marked: G1 status=passed by hand, no evidence anywhere ->
#     LAUNCH_DRYRUN=1 on G2 must STOP naming G1 and the missing completion
#     evidence [the arm that is RED today: the launcher ignores status]
#   2 positive control: green corpus evidence with arm= patched to G1
#     BEFORE anchoring in a scratch ledger, record built, receipt with gate
#     PASS -> mark-passed writes status+passedOn+completions.json;
#     validate-passed holds; dryrun on G2 proceeds; next resolves G2
#   3 tamper: one byte appended to the marked record -> dryrun on G2 STOPs
#     naming G1 (byte-matching digest, not file presence)
#   4 no passed slices, no ledger env -> dryrun proceeds (fresh grafts keep
#     working without an observation ledger)
#   5 gate-fail does not skip: full launcher with a stub claude on PATH on
#     a slice whose criterion fails -> non-zero exit naming the gate, NO
#     mark written, harness.json byte-identical, next re-resolves the SAME
#     slice -- the sequence stops there instead of skipping forward
# GREEN: all five arms hold. RED: any arm fails. UNMEASURED (2): git/node/
# harnesswright/verity CLI absent, or the machinery under test absent.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$ROOT/scripts/launch_worker.sh"
CHECKS="$ROOT/scripts/launch_checks.py"
GRAFT="$ROOT/scripts/graft_init.sh"
CORPUS="$ROOT/tests/fixtures/conformance_corpus.py"
LEDGER_TOOL="$ROOT/tests/fixtures/scratch_ledger.sh"
RECORD="$ROOT/scripts/conformance_record.py"
for f in "$LAUNCHER" "$CHECKS" "$GRAFT" "$CORPUS" "$LEDGER_TOOL" "$RECORD"; do
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
# Resolved and present is not runnable. A checkout carrying dist/cli.js and
# none of the modules it imports satisfies both checks above and then dies at
# import inside the run below, where this fixture reads the crash as its
# subject's verdict and exits RED for a missing build. One process spent here
# keeps that answer out of the RED column and in the unmeasured one.
HW_PROBE="$(cli_starts "$HW")" \
  || { echo "UNMEASURED: harnesswright CLI at $HW does not start -- $HW_PROBE" >&2; exit 2; }
# Exported, not kept local: the scripts this fixture drives resolve the CLI
# themselves, by the same documented seam (ADR-004 D2, env override first). A
# fixture that resolved a CLI its own subject cannot find would measure the
# resolver and nothing else.
export HARNESSWRIGHT_CLI="$HW"
VY="$(resolve_verity_cli "$ROOT")" \
  || { echo "UNMEASURED: verity CLI not resolvable (set VERITY_CLI)" >&2; exit 2; }
[ -f "$VY" ] || { echo "UNMEASURED: verity CLI not a file at $VY" >&2; exit 2; }
VY_PROBE="$(cli_starts "$VY")" \
  || { echo "UNMEASURED: verity CLI at $VY does not start -- $VY_PROBE" >&2; exit 2; }
export VERITY_CLI="$VY"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/seqpass.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
printf 'Read seed.txt and write docs/OUT.md describing it.\n' > "$WORK/task.md"

mkrepo() {
  mkdir -p "$1"; git -C "$1" init -q
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name tester
  git -C "$1" config commit.gpgsign false
  echo seed > "$1/seed.txt"
  git -C "$1" add -- seed.txt && git -C "$1" commit -qm "fixture: seed"
}

# Base repo: G1 grafted fresh, G2 added -- both by the real command, whose
# own fixtures hold those paths.
R0="$WORK/r0"; mkrepo "$R0"
bash "$GRAFT" --repo "$R0" --slice G1 --title "first slice" \
  --task "$WORK/task.md" --tools Read,Write --turns 4 --wall 4m --scope docs \
  --criterion 'g1-doc-exists=test -f docs/OUT.md' \
  --verifier-id https://example.invalid/verifier/v1 --tier T3 >/dev/null 2>&1 \
  || { echo "UNMEASURED: fresh graft failed on a clean repo" >&2; exit 2; }
HARNESSWRIGHT_CLI="$HW" bash "$GRAFT" --add --repo "$R0" --slice G2 \
  --title "second slice" --task "$WORK/task.md" --tools Read,Write --turns 4 \
  --wall 4m --scope docs --criterion 'g2-doc-exists=test -f docs/OUT2.md' \
  >/dev/null 2>&1 \
  || { echo "UNMEASURED: --add failed on a clean graft" >&2; exit 2; }

# Dry-run the launcher at repo $1 on spec id $2; $3 = ledger dir or "".
dryrun() {
  ( cd "$1" && \
    CONFORMANCE_LEDGER_REPO="${3:-}" HARNESS_HOME="$ROOT" \
    HARNESS_MANIFEST="$1/.harness/manifest.local.json" \
    HARNESSWRIGHT_CLI="$HW" VERITY_CLI="$VY" LAUNCH_DRYRUN=1 \
    bash "$LAUNCHER" ".harness/specs/$2.md" 2>&1 )
}

hand_mark() {
  python3 - "$1/.harness/harness.json" "$2" <<'PY'
import json, sys
p, s = sys.argv[1], sys.argv[2]
h = json.load(open(p))
h["slices"][s]["status"] = "passed"
open(p, "w").write(json.dumps(h, indent=2) + "\n")
PY
}

next_id() {
  ( cd "$1" && node "$HW" next --json 2>/dev/null ) \
    | python3 -c 'import json,sys;r=json.load(sys.stdin);print(r.get("id", r.get("kind")))'
}

# Arm 1 -- the flag anyone can set, and nothing behind it.
R1="$WORK/r1"; cp -R "$R0" "$R1"; hand_mark "$R1" G1
out="$(dryrun "$R1" G2 "$WORK/ledger-unused")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm1]: G1 hand-marked passed with no record and the launcher proceeded: $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "G1" \
  || { echo "RED [arm1]: refusal does not name the unsupported slice G1: $out" >&2; exit 1; }
printf '%s\n' "$out" | grep -qi "completion" \
  || { echo "RED [arm1]: refusal does not name the missing completion evidence: $out" >&2; exit 1; }
echo "ok [arm1: hand-marked slice refused, naming G1 and the missing evidence]"

# Arm 2 -- the positive control: evidence first, mark as its consequence.
R2="$WORK/r2"; cp -R "$R0" "$R2"
EVD="$R2/.harness/receipts/run-fx"; mkdir -p "$EVD"
python3 "$CORPUS" green "$EVD" \
  || { echo "UNMEASURED: corpus builder failed" >&2; exit 2; }
python3 - "$EVD/invocation.txt" <<'PY'
import sys
p = sys.argv[1]
b = open(p, "rb").read()
assert b.startswith(b"arm=SYN "), b[:20]
open(p, "wb").write(b.replace(b"arm=SYN ", b"arm=G1 ", 1))
PY
bash "$LEDGER_TOOL" "$EVD" "$WORK/ledger" run-fx >/dev/null \
  || { echo "UNMEASURED: scratch ledger anchoring failed" >&2; exit 2; }
python3 "$RECORD" "$EVD" "$EVD/statement.json" >/dev/null \
  || { echo "UNMEASURED: record builder refused the green evidence" >&2; exit 2; }
python3 - "$R2/.harness/receipts/run-fx.receipt.json" <<'PY'
import json, sys
json.dump({"run_id": "run-fx", "spec_id": "G1", "mode": "B",
           "gate": {"verdict": "PASS", "reason": "all declared criteria PASS",
                    "verity_exit": 0},
           "stop_reason": "gate-pass"}, open(sys.argv[1], "w"), indent=1)
PY
out="$(python3 "$CHECKS" mark-passed "$R2" G1 run-fx \
  "$R2/.harness/receipts/run-fx.receipt.json" "$EVD/statement.json" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] \
  || { echo "RED [arm2]: mark-passed refused supported evidence: $out" >&2; exit 1; }
python3 - "$R2/.harness/harness.json" <<'PY' \
  || { echo "RED [arm2]: harness.json does not carry status=passed + passedOn for G1" >&2; exit 1; }
import json, re, sys
g1 = json.load(open(sys.argv[1]))["slices"]["G1"]
assert g1.get("status") == "passed", g1
assert re.match(r"^\d{4}-\d{2}-\d{2}$", g1.get("passedOn", "")), g1
PY
[ -f "$R2/.harness/receipts/completions.json" ] \
  || { echo "RED [arm2]: completions.json not written" >&2; exit 1; }
out="$(dryrun "$R2" G2 "$WORK/ledger")"; rc=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q "DRYRUN ok id=G2"; } \
  || { echo "RED [arm2]: evidence-backed pass did not let G2 launch: $out" >&2; exit 1; }
[ "$(next_id "$R2")" = "G2" ] \
  || { echo "RED [arm2]: next does not resolve G2 after the evidenced mark" >&2; exit 1; }
echo "ok [arm2: evidenced mark accepted; G2 unlocked and launchable]"

# Arm 3 -- a byte moved in the record un-completes the slice.
R3="$WORK/r3"; cp -R "$R2" "$R3"
printf 'x' >> "$R3/.harness/receipts/run-fx/statement.json"
out="$(dryrun "$R3" G2 "$WORK/ledger")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm3]: record bytes moved and the launcher still proceeded: $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "G1" \
  || { echo "RED [arm3]: tamper refusal does not name G1: $out" >&2; exit 1; }
echo "ok [arm3: moved record byte refused, naming G1]"

# Arm 4 -- zero passed slices need zero ledger: fresh grafts keep working.
R4="$WORK/r4"; cp -R "$R0" "$R4"
out="$(dryrun "$R4" G1 "")"; rc=$?
{ [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q "DRYRUN ok id=G1"; } \
  || { echo "RED [arm4]: fresh graft without ledger no longer launches: $out" >&2; exit 1; }
echo "ok [arm4: no passed slices, no ledger needed]"

# Arm 5 -- a failed gate leaves no mark and the sequence cannot skip it.
R5="$WORK/r5"; mkrepo "$R5"
bash "$GRAFT" --repo "$R5" --slice G1 --title "never passes" \
  --task "$WORK/task.md" --tools Read,Write --turns 4 --wall 4m --scope docs \
  --criterion 'g1-never=test -f docs/NEVER.md' \
  --verifier-id https://example.invalid/verifier/v1 --tier T3 >/dev/null 2>&1 \
  || { echo "UNMEASURED: fresh graft failed for arm 5" >&2; exit 2; }
mkdir -p "$WORK/bin"
cat > "$WORK/bin/claude" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "stub-claude 0.0"; exit 0; fi
cat > /dev/null
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0,"duration_ms":1,"session_id":"stub","permission_denials":[]}\n'
STUB
chmod +x "$WORK/bin/claude"
H5="$(git hash-object "$R5/.harness/harness.json")"
out="$( cd "$R5" && \
  PATH="$WORK/bin:$PATH" CONFORMANCE_LEDGER_REPO="$WORK/ledger5" \
  HARNESS_HOME="$ROOT" HARNESS_MANIFEST="$R5/.harness/manifest.local.json" \
  HARNESSWRIGHT_CLI="$HW" VERITY_CLI="$VY" \
  bash "$LAUNCHER" ".harness/specs/G1.md" 2>&1 )"; rc=$?
# The ledger for arm 5 must exist before the launcher anchors into it.
if printf '%s\n' "$out" | grep -q "declaration digest could not be anchored"; then
  git init -q "$WORK/ledger5"
  git -C "$WORK/ledger5" config user.email t@example.invalid
  git -C "$WORK/ledger5" config user.name tester
  git -C "$WORK/ledger5" config commit.gpgsign false
  out="$( cd "$R5" && \
    PATH="$WORK/bin:$PATH" CONFORMANCE_LEDGER_REPO="$WORK/ledger5" \
    HARNESS_HOME="$ROOT" HARNESS_MANIFEST="$R5/.harness/manifest.local.json" \
    HARNESSWRIGHT_CLI="$HW" VERITY_CLI="$VY" \
    bash "$LAUNCHER" ".harness/specs/G1.md" 2>&1 )"; rc=$?
fi
[ "$rc" -ne 0 ] \
  || { echo "RED [arm5]: gate had to fail and the launcher exited 0: $out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "gate verdict=FAIL" \
  || { echo "RED [arm5]: stop does not name the gate: $out" >&2; exit 1; }
[ "$(git hash-object "$R5/.harness/harness.json")" = "$H5" ] \
  || { echo "RED [arm5]: a failed gate moved harness.json" >&2; exit 1; }
[ ! -f "$R5/.harness/receipts/completions.json" ] \
  || { echo "RED [arm5]: a failed gate wrote a completion" >&2; exit 1; }
[ "$(next_id "$R5")" = "G1" ] \
  || { echo "RED [arm5]: next skipped past the failed slice" >&2; exit 1; }
echo "ok [arm5: failed gate leaves no mark; the same slice stays next]"

echo "GREEN: completion is a consequence of evidence on all five arms"
