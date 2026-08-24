#!/usr/bin/env bash
# DRV-1 -- derived criteria come from what the repo already declares; a repo
# with no way to say it is well is REFUSED, never handed a fabricated
# criterion (THR-SEQ ESITO 3). Subject: scripts/graft_init.sh --derive.
# Four arms:
#   1 no signal: package.json with scripts but none of test/typecheck/lint
#     and no tsconfig.json -> --derive refuses naming the absence, NOTHING
#     written [RED today: --derive is unknown usage, no named refusal]
#   1b no package.json at all -> same refusal class, nothing written
#   2 npm repo with scripts.test -> `<slice>-test=npm test` lands verbatim
#     in the spec criteria and in claims.json; typecheck/lint NOT invented
#   3 derived + declared compose: --derive --criterion both present in the
#     graft, neither displacing the other
# GREEN: refusals clean and named, derivation verbatim, composition holds.
# RED: any arm fails. UNMEASURED (2): git/node/harnesswright absent.
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/drv.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
printf 'Implement the slice.\n' > "$WORK/task.md"

mkrepo() {
  mkdir -p "$1"; git -C "$1" init -q
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name tester
  git -C "$1" config commit.gpgsign false
  echo seed > "$1/seed.txt"
  git -C "$1" add -- seed.txt && git -C "$1" commit -qm "fixture: seed"
}

graft_derive() { # $1 repo, extra args follow
  local repo="$1"; shift
  bash "$GRAFT" --repo "$repo" --slice G1 --title "derived slice" \
    --task "$WORK/task.md" --tools Read,Write --turns 4 --wall 4m --scope src \
    --verifier-id https://example.invalid/verifier/v1 --tier T3 --derive "$@" 2>&1
}

# Arm 1 -- a repo that cannot say it is well is told so, not flattered.
R1="$WORK/r1"; mkrepo "$R1"
printf '{"name":"x","version":"0.0.0","scripts":{"start":"node ."}}\n' > "$R1/package.json"
out="$(graft_derive "$R1")"; rc=$?
[ "$rc" -ne 0 ] \
  || { echo "RED [arm1]: --derive grafted a repo with no quality signal: $out" >&2; exit 1; }
printf '%s\n' "$out" | grep -qi "no way to say it is well" \
  || { echo "RED [arm1]: refusal does not name the absence: $out" >&2; exit 1; }
{ [ ! -e "$R1/.harness" ] && [ ! -e "$R1/.verity" ]; } \
  || { echo "RED [arm1]: refusal left graft files behind" >&2; exit 1; }
echo "ok [arm1: signal-less npm repo refused, absence named, nothing written]"

# Arm 1b -- no package.json at all: same refusal class.
R1B="$WORK/r1b"; mkrepo "$R1B"
out="$(graft_derive "$R1B")"; rc=$?
{ [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -qi "no way to say it is well"; } \
  || { echo "RED [arm1b]: package.json-less repo not refused by name: $out" >&2; exit 1; }
[ ! -e "$R1B/.harness" ] \
  || { echo "RED [arm1b]: refusal left graft files behind" >&2; exit 1; }
echo "ok [arm1b: package.json-less repo refused, nothing written]"

# Arm 2 -- what the repo declares is derived verbatim; nothing else appears.
R2="$WORK/r2"; mkrepo "$R2"
printf '{"name":"x","version":"0.0.0","scripts":{"test":"node --test"}}\n' > "$R2/package.json"
out="$(graft_derive "$R2")"; rc=$?
[ "$rc" -eq 0 ] \
  || { echo "RED [arm2]: --derive refused a repo with a test script: $out" >&2; exit 1; }
python3 - "$R2" <<'PY' || { echo "RED [arm2]: derived criterion not landed verbatim" >&2; exit 1; }
import json, sys
top = sys.argv[1]
claims = {c["id"]: c["run"] for c in json.load(open(top + "/.verity/claims.json"))["claims"]}
assert claims == {"G1-test": "npm test"}, claims
spec = open(top + "/.harness/specs/G1.md").read()
assert "  - G1-test\n" in spec, spec[:400]
assert "typecheck" not in spec and "lint" not in spec, spec[:400]
PY
echo "ok [arm2: scripts.test derived verbatim; typecheck/lint not invented]"

# Arm 3 -- derived and declared compose.
R3="$WORK/r3"; mkrepo "$R3"
printf '{"name":"x","version":"0.0.0","scripts":{"test":"node --test"}}\n' > "$R3/package.json"
out="$(graft_derive "$R3" --criterion 'g1-extra=test -f seed.txt')"; rc=$?
[ "$rc" -eq 0 ] \
  || { echo "RED [arm3]: derived+declared composition refused: $out" >&2; exit 1; }
python3 - "$R3" <<'PY' || { echo "RED [arm3]: composition did not land both criteria" >&2; exit 1; }
import json, sys
claims = {c["id"] for c in json.load(open(sys.argv[1] + "/.verity/claims.json"))["claims"]}
assert claims == {"g1-extra", "G1-test"}, claims
PY
echo "ok [arm3: declared and derived criteria compose]"

echo "GREEN: derivation reads the repo and refuses to invent"
