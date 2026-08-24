#!/usr/bin/env bash
# ADD-1 -- a slice added to a grafted repo touches nothing that exists, and a
# slice whose declared criterion is absent from the claims manifest is a gate
# that measures nothing: --add REFUSES to create one and REFUSES to extend a
# repo that already carries one (the defect THR-INIT found in the THR-SWARM-1
# hand-grafts: harness.json pointing slices at criteria that no longer exist).
# Subject: scripts/graft_init.sh --add (override GRAFT_CMD for a stand-in).
# Six arms:
#   1 existing gate broken (a criterion hand-removed from the manifest while
#     the spec still declares it) -> --add refuses naming the slice AND the
#     absent criterion id; all four graft files byte-identical after refusal
#   2 --add on an ungrafted repo -> refuse; NOTHING left on disk
#   3 --add with a slice id already in harness.json -> refuse; bytes intact
#   4 --add with a criterion id already in the manifest -> refuse naming the
#     duplicate; bytes intact
#   5 positive control: init G1 then --add G2 -> exit 0; manifest.local.json
#     and specs/G1.md byte-identical; claims = old ids (same commands) + new;
#     harness.json carries both; with G1 marked passed, `next --json` answers
#     kind=unlocked id=G2 eligible_mode_b=true -- reachable when its turn comes
#   6 moving control: a stub that appends the slice without checking the
#     existing gate must be ACCUSED by arm 1's own check
# GREEN: 1-4 refuse clean, 5 accepted and reachable, 6 accuses the stub.
# RED: any arm fails. UNMEASURED (2): git/node/harnesswright CLI absent, or
# the command under test absent.
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
# Exported, not kept local: the scripts this fixture drives resolve the CLI
# themselves, by the same documented seam (ADR-004 D2, env override first). A
# fixture that resolved a CLI its own subject cannot find would measure the
# resolver and nothing else.
export HARNESSWRIGHT_CLI="$HW"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/graftadd.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
printf 'Read seed.txt and write docs/OUT.md describing it.\n' > "$WORK/task.md"

mkrepo() {
  mkdir -p "$1"; git -C "$1" init -q
  git -C "$1" config user.email t@example.invalid
  git -C "$1" config user.name tester
  git -C "$1" config commit.gpgsign false
  echo seed > "$1/seed.txt"
  git -C "$1" add -- seed.txt && git -C "$1" commit -qm "fixture: seed"
}

# Fresh graft of G1 with the REAL command (its own fixture holds that path).
init_g1() {
  bash "$GRAFT" --repo "$1" --slice G1 --title "first slice" \
    --task "$WORK/task.md" --tools Read,Write --turns 4 --wall 4m --scope docs \
    --criterion 'g1-doc-exists=test -f docs/OUT.md' \
    --criterion 'g1-doc-nonempty=test -s docs/OUT.md' \
    --verifier-id https://example.invalid/verifier/v1 --tier T3 >/dev/null 2>&1 \
    || { echo "UNMEASURED: fresh graft failed on a clean repo (its own fixture covers that path)" >&2; exit 2; }
}

# The four graft-file hashes, one line, for byte-intactness checks.
graft_hashes() {
  git hash-object "$1/.harness/harness.json" "$1/.harness/manifest.local.json" \
    "$1/.harness/specs/G1.md" "$1/.verity/claims.json" 2>/dev/null | tr '\n' ' '
}

# Run $2 (the command) in --add mode against repo $1, adding G2. $3 optional
# criterion override. Output on stdout; exit code is the command's own.
run_add() {
  local crit="${3:-g2-doc-exists=test -f docs/OUT2.md}"
  bash "$2" --add --repo "$1" --slice "${4:-G2}" --title "second slice" \
    --task "$WORK/task.md" --tools Read,Write --turns 4 --wall 4m --scope docs \
    --criterion "$crit" 2>&1
}

# A refusal is clean only if it exits non-zero, names the expected token, and
# moved no graft byte. $1 repo, $2 rc, $3 output, $4 token, $5 pre-hashes.
# Prints the accusation instead of exiting so arm 6 can reuse it in reverse.
refuse_intact() {
  [ "$2" -ne 0 ] || { echo "extended a repo it had to refuse (exit 0)"; return; }
  printf '%s\n' "$3" | grep -qi -- "$4" \
    || { echo "refusal does not name '$4': $3"; return; }
  [ "$(graft_hashes "$1")" = "$5" ] \
    || { echo "refused but moved graft bytes"; return; }
  echo OK
}

# Arm 1 -- the THR-SWARM-1 defect, reproduced: spec still declares
# g1-doc-nonempty, the manifest no longer carries it. --add must refuse.
R1="$WORK/r1"; mkrepo "$R1"; init_g1 "$R1"
python3 - "$R1/.verity/claims.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p))
m["claims"] = [c for c in m["claims"] if c["id"] != "g1-doc-nonempty"]
json.dump(m, open(p, "w"), indent=2)
PY
H1="$(graft_hashes "$R1")"
out="$(run_add "$R1" "$GRAFT")"; rc=$?
v="$(refuse_intact "$R1" "$rc" "$out" "g1-doc-nonempty" "$H1")"
[ "$v" = OK ] || { echo "RED [arm1]: $v" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "G1" \
  || { echo "RED [arm1]: refusal does not name the broken slice G1: $out" >&2; exit 1; }
echo "ok [arm1]: broken existing gate refused, slice and criterion named, bytes intact"

# Arm 2 -- ungrafted repo: nothing to add to, nothing left behind.
R2="$WORK/r2"; mkrepo "$R2"
out="$(run_add "$R2" "$GRAFT")"; rc=$?
[ "$rc" -ne 0 ] || { echo "RED [arm2]: added a slice to an ungrafted repo (exit 0)" >&2; exit 1; }
printf '%s\n' "$out" | grep -qi "harness.json" \
  || { echo "RED [arm2]: refusal does not name the missing graft: $out" >&2; exit 1; }
[ ! -e "$R2/.harness" ] || { echo "RED [arm2]: refused but left .harness behind" >&2; exit 1; }
[ ! -e "$R2/.verity" ] || { echo "RED [arm2]: refused but left .verity behind" >&2; exit 1; }
echo "ok [arm2]: ungrafted repo refused clean"

# Arm 3 -- slice id already present.
R3="$WORK/r3"; mkrepo "$R3"; init_g1 "$R3"
H3="$(graft_hashes "$R3")"
out="$(run_add "$R3" "$GRAFT" "" G1)"; rc=$?
v="$(refuse_intact "$R3" "$rc" "$out" "G1" "$H3")"
[ "$v" = OK ] || { echo "RED [arm3]: $v" >&2; exit 1; }
echo "ok [arm3]: duplicate slice id refused, bytes intact"

# Arm 4 -- criterion id already in the manifest: duplicated criteria are the
# defect class, refused, never merged.
R4="$WORK/r4"; mkrepo "$R4"; init_g1 "$R4"
H4="$(graft_hashes "$R4")"
out="$(run_add "$R4" "$GRAFT" 'g1-doc-exists=test -f docs/OUT2.md')"; rc=$?
v="$(refuse_intact "$R4" "$rc" "$out" "g1-doc-exists" "$H4")"
[ "$v" = OK ] || { echo "RED [arm4]: $v" >&2; exit 1; }
echo "ok [arm4]: duplicate criterion id refused, bytes intact"

# Arm 5 -- positive control: add G2, touch nothing that exists, and be
# reachable when the turn comes.
R5="$WORK/r5"; mkrepo "$R5"; init_g1 "$R5"
PRE_MANIFEST="$(git hash-object "$R5/.harness/manifest.local.json")"
PRE_SPEC1="$(git hash-object "$R5/.harness/specs/G1.md")"
out="$(run_add "$R5" "$GRAFT")"; rc=$?
[ "$rc" -eq 0 ] || { echo "RED [arm5]: complete --add refused (exit $rc): $out" >&2; exit 1; }
[ "$(git hash-object "$R5/.harness/manifest.local.json")" = "$PRE_MANIFEST" ] \
  || { echo "RED [arm5]: manifest.local.json bytes moved" >&2; exit 1; }
[ "$(git hash-object "$R5/.harness/specs/G1.md")" = "$PRE_SPEC1" ] \
  || { echo "RED [arm5]: specs/G1.md bytes moved" >&2; exit 1; }
[ -s "$R5/.harness/specs/G2.md" ] || { echo "RED [arm5]: specs/G2.md absent/empty" >&2; exit 1; }
python3 - "$R5" <<'PY' || { echo "RED [arm5]: written state wrong (detail above)" >&2; exit 1; }
import json, sys
top = sys.argv[1]
h = json.load(open(f"{top}/.harness/harness.json"))
assert set(h["slices"]) == {"G1", "G2"}, f"slices: {sorted(h['slices'])}"
m = json.load(open(f"{top}/.verity/claims.json"))
ids = [c["id"] for c in m["claims"]]
assert ids == ["g1-doc-exists", "g1-doc-nonempty", "g2-doc-exists"], f"claim ids: {ids}"
byid = {c["id"]: c for c in m["claims"]}
assert byid["g1-doc-exists"]["run"] == "test -f docs/OUT.md", "g1 claim command moved"
PY
python3 - "$R5/.harness/harness.json" <<'PY'
import json, sys
p = sys.argv[1]
h = json.load(open(p))
h["slices"]["G1"]["status"] = "passed"
json.dump(h, open(p, "w"), indent=2)
PY
next="$(cd "$R5" && node "$HW" next --json 2>&1)" \
  || { echo "RED [arm5]: next --json failed after the add: $next" >&2; exit 1; }
NEXT_JSON="$next" python3 - <<'PY' || { echo "RED [arm5]: G2 not reachable when its turn comes (verdict above)" >&2; exit 1; }
import json, os, sys
r = json.loads(os.environ["NEXT_JSON"])
ok = r.get("kind") == "unlocked" and r.get("id") == "G2" and r.get("eligible_mode_b") is True
print(json.dumps({k: r.get(k) for k in ("kind", "id", "eligible_mode_b")}))
sys.exit(0 if ok else 1)
PY
echo "ok [arm5]: G2 added, existing bytes intact, reachable when its turn comes"

# Arm 6 -- the row must be able to accuse a guesser: a stub that appends the
# slice and never looks at the existing gate. Same shape as arm 1.
STUB="$WORK/stub_appender.sh"
cat > "$STUB" <<'EOS'
#!/usr/bin/env bash
repo=""; slice=G2
while [ $# -gt 0 ]; do case $1 in
  --repo) repo=$2; shift 2 ;; --slice) slice=$2; shift 2 ;; *) shift ;;
esac; done
python3 - "$repo" "$slice" <<'PY'
import json, sys
top, s = sys.argv[1], sys.argv[2]
h = json.load(open(f"{top}/.harness/harness.json"))
h["slices"][s] = {"title": "appended", "manifest": ".verity/claims.json"}
json.dump(h, open(f"{top}/.harness/harness.json", "w"), indent=2)
m = json.load(open(f"{top}/.verity/claims.json"))
m["claims"].append({"id": f"{s.lower()}-doc-exists", "type": "command",
                    "run": "test -f docs/OUT2.md", "expect": {"exitCode": 0}})
json.dump(m, open(f"{top}/.verity/claims.json", "w"), indent=2)
open(f"{top}/.harness/specs/{s}.md", "w").write("---\nmode: B\n---\n")
PY
echo "slice appended (existing gate not consulted)"
EOS
R6="$WORK/r6"; mkrepo "$R6"; init_g1 "$R6"
python3 - "$R6/.verity/claims.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p))
m["claims"] = [c for c in m["claims"] if c["id"] != "g1-doc-nonempty"]
json.dump(m, open(p, "w"), indent=2)
PY
H6="$(graft_hashes "$R6")"
out="$(run_add "$R6" "$STUB")"; rc=$?
v="$(refuse_intact "$R6" "$rc" "$out" "g1-doc-nonempty" "$H6")"
[ "$v" != OK ] || { echo "RED [arm6]: the appender stub passed the refusal check; this row cannot move" >&2; exit 1; }
echo "ok [arm6]: appender accused -- $v"

echo "GREEN: broken gates refused with bytes intact, clean add reachable, appender accusable"
exit 0
