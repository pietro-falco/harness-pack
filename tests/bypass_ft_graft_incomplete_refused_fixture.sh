#!/usr/bin/env bash
# GRAFT-1 -- an incomplete graft REFUSES; it never fabricates a config that
# looks right and dies at the first run. Subject: scripts/graft_init.sh
# (override GRAFT_CMD to point the row at a stand-in). Five arms:
#   1 missing --criterion      -> refuse naming "criterion", leave NOTHING
#   2 unreadable --task file   -> refuse naming the task file, leave NOTHING
#   3 pre-existing .verity/claims.json (the THR-SWARM-1 replacement defect:
#     a hand-graft rewrote a 26-claim tracked manifest down to the new
#     slice's claims) -> refuse naming the file; pre-existing bytes intact,
#     no .harness left behind
#   4 positive control: complete input -> exit 0, four files written, and
#     `next --json` at the target root reports kind=unlocked, id=<slice>,
#     eligible_mode_b=true -- reachability, not "looks right"
#   5 moving control: a stub that scaffolds defaults for the missing piece
#     instead of refusing must be ACCUSED by arm 1's own check; a row that
#     cannot accuse the guesser measures nothing.
# GREEN: 1-3 refuse clean, 4 accepted and eligible, 5 accuses the stub.
# RED: any arm fails. UNMEASURED (2): git/node/harnesswright CLI absent,
# or the command under test absent.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRAFT="${GRAFT_CMD:-$ROOT/scripts/graft_init.sh}"
[ -f "$GRAFT" ] || { echo "UNMEASURED: command under test absent at $GRAFT" >&2; exit 2; }
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/graft1.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
printf 'Read seed.txt and write docs/OUT.md describing it.\n' > "$WORK/task.md"

mkrepo() {
  mkdir -p "$1"; git -C "$1" init -q
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name tester
  git -C "$1" config commit.gpgsign false
  echo seed > "$1/seed.txt"
  git -C "$1" add -- seed.txt && git -C "$1" commit -qm "fixture: seed"
}

# Run $3 (the command) against repo $1 in mode $2: full | nocrit | badtask.
# Output on stdout; exit code is the command's own.
run_graft() {
  # The tool list is one comma-separated ARGUMENT, not two array elements;
  # hoisting it into a variable says so where the array cannot.
  local task="$WORK/task.md" a tools="Read,Write"
  [ "$2" = badtask ] && task="$WORK/no-such-task.md"
  a=(--repo "$1" --slice G1 --title "graft fixture slice" \
     --task "$task" --tools "$tools" --turns 4 --wall 4m --scope docs \
     --verifier-id https://example.invalid/verifier/v1 --tier T3)
  [ "$2" = nocrit ] || a+=(--criterion 'g1-doc-exists=test -f docs/OUT.md')
  bash "$3" "${a[@]}" 2>&1
}

# A refusal is clean only if it exits non-zero, names the missing piece, and
# leaves no graft file behind. $1 repo, $2 rc, $3 output, $4 expected token.
# Prints the accusation instead of exiting so arm 5 can reuse it in reverse.
refuse_clean() {
  [ "$2" -ne 0 ] || { echo "accepted an incomplete graft (exit 0)"; return; }
  printf '%s\n' "$3" | grep -qi -- "$4" \
    || { echo "refusal does not name '$4': $3"; return; }
  [ ! -e "$1/.harness" ] || { echo "refused but left .harness behind"; return; }
  [ ! -e "$1/.verity" ] || { echo "refused but left .verity behind"; return; }
  echo OK
}

# Arm 1 -- missing --criterion.
R1="$WORK/r1"; mkrepo "$R1"
out="$(run_graft "$R1" nocrit "$GRAFT")"; rc=$?
v="$(refuse_clean "$R1" "$rc" "$out" criterion)"
[ "$v" = OK ] || { echo "RED [arm1]: $v" >&2; exit 1; }
echo "ok [arm1]: missing criterion refused clean"

# Arm 2 -- task file absent.
R2="$WORK/r2"; mkrepo "$R2"
out="$(run_graft "$R2" badtask "$GRAFT")"; rc=$?
v="$(refuse_clean "$R2" "$rc" "$out" task)"
[ "$v" = OK ] || { echo "RED [arm2]: $v" >&2; exit 1; }
echo "ok [arm2]: unreadable task refused clean"

# Arm 3 -- pre-existing claims manifest must be refused, never replaced.
R3="$WORK/r3"; mkrepo "$R3"
mkdir -p "$R3/.verity"
printf '{"version":"0.1","claims":[{"id":"pre","type":"command","run":"true","expect":{"exitCode":0}}]}\n' \
  > "$R3/.verity/claims.json"
pre_sha="$(git hash-object "$R3/.verity/claims.json")"
out="$(run_graft "$R3" full "$GRAFT")"; rc=$?
[ "$rc" -ne 0 ] || { echo "RED [arm3]: grafted over an existing claims manifest (exit 0)" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "claims.json" \
  || { echo "RED [arm3]: refusal does not name the existing file: $out" >&2; exit 1; }
[ "$(git hash-object "$R3/.verity/claims.json")" = "$pre_sha" ] \
  || { echo "RED [arm3]: pre-existing claims.json bytes moved" >&2; exit 1; }
[ ! -e "$R3/.harness" ] || { echo "RED [arm3]: refused but left .harness behind" >&2; exit 1; }
echo "ok [arm3]: existing manifest refused, bytes intact"

# Arm 4 -- positive control: complete input is accepted AND reachable.
R4="$WORK/r4"; mkrepo "$R4"
out="$(run_graft "$R4" full "$GRAFT")"; rc=$?
[ "$rc" -eq 0 ] || { echo "RED [arm4]: complete graft refused (exit $rc): $out" >&2; exit 1; }
for f in .harness/harness.json .harness/manifest.local.json .harness/specs/G1.md .verity/claims.json; do
  [ -s "$R4/$f" ] || { echo "RED [arm4]: accepted but $f absent/empty" >&2; exit 1; }
done
next="$(cd "$R4" && node "$HW" next --json 2>&1)" \
  || { echo "RED [arm4]: next --json failed on the grafted repo: $next" >&2; exit 1; }
NEXT_JSON="$next" python3 - <<'PY' || { echo "RED [arm4]: grafted repo not reachable (next verdict above)" >&2; exit 1; }
import json, os, sys
r = json.loads(os.environ["NEXT_JSON"])
ok = r.get("kind") == "unlocked" and r.get("id") == "G1" and r.get("eligible_mode_b") is True
print(json.dumps({k: r.get(k) for k in ("kind", "id", "eligible_mode_b")}))
sys.exit(0 if ok else 1)
PY
echo "ok [arm4]: complete graft accepted; next reports G1 unlocked and eligible"

# Arm 5 -- the row must be able to accuse a guesser. Same shape as arm 1,
# subject swapped for a stub that scaffolds a default criterion and exits 0.
STUB="$WORK/stub_guesser.sh"
cat > "$STUB" <<'EOS'
#!/usr/bin/env bash
repo=""; slice=S1
while [ $# -gt 0 ]; do case $1 in
  --repo) repo=$2; shift 2 ;; --slice) slice=$2; shift 2 ;; *) shift ;;
esac; done
mkdir -p "$repo/.harness/specs" "$repo/.verity"
echo '{"version":"0.1","project":"guessed","workstreamCap":1,"slices":{}}' > "$repo/.harness/harness.json"
echo '{}' > "$repo/.harness/manifest.local.json"
printf -- '---\nmode: B\n---\n' > "$repo/.harness/specs/$slice.md"
echo '{"version":"0.1","claims":[{"id":"guessed-default","type":"command","run":"true","expect":{"exitCode":0}}]}' > "$repo/.verity/claims.json"
echo "grafted (defaults applied for missing pieces)"
EOS
R5="$WORK/r5"; mkrepo "$R5"
out="$(run_graft "$R5" nocrit "$STUB")"; rc=$?
v="$(refuse_clean "$R5" "$rc" "$out" criterion)"
[ "$v" != OK ] || { echo "RED [arm5]: the guesser stub passed the refusal check; this row cannot move" >&2; exit 1; }
echo "ok [arm5]: guesser accused -- $v"

echo "GREEN: incomplete grafts refuse clean, complete graft reachable, guesser accusable"
exit 0
