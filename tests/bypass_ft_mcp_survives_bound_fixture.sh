#!/usr/bin/env bash
# FT-3 -- the bound does not reach MCP tools, and nothing in the spawned
# command closes that door either.
#
# THIS ROW STANDS GREEN, and does so from the commit that ratifies ADR-022. It
# was written RED and observed RED against the launcher at
# harness-pack@ef78ad8 -- byte-identical to 14e225f under scripts/, tests/ and
# templates/, so the basis ADR-022 names is the basis measured -- where
# `grep -rn 'strict-mcp\|mcp-config' scripts/
# templates/` returned nothing at all and the child was spawned with whatever
# MCP configuration its own resolution order happened to find. What closes it
# is ADR-022 D3 -- "Mode B passes `--strict-mcp-config` with no `--mcp-config`,
# so no MCP server loads" -- landing in the same tree that ratifies the
# decision.
#
# Everything below this paragraph is written in the tense of the defect,
# because that defect is what this fixture still poses on every run.
#
# THE SUBJECT is the child command at scripts/launch_worker.sh:354-360, read
# for what is NOT in it. This row is the only one of ADR-022's four whose
# subject is an absent flag rather than a misused one, and the reason it exists
# at all is a measurement in the ADR's Context that surprised its author:
#
#     claude -p <prompt> --tools Read
#       -> Read, mcp__plugin_context7_context7__query-docs,
#          mcp__plugin_context7_context7__resolve-library-id
#
# With the bound in force -- the very flag FT-1 exists to install -- two MCP
# tools remained on the surface. `--tools` bounds the built-ins and does not
# reach the MCP namespace, so D1 alone would buy a bound with a hole in it, and
# a spec declaring `tools: [Read]` would still hand the model whatever servers
# the ambient configuration resolved. D3 is the separate door, and this row is
# the one that holds it shut.
#
# THE ROW HAS TWO HALVES AND BOTH ARE LOAD-BEARING. `--strict-mcp-config`
# present is the instruction to consider ONLY the configuration given on the
# command line; no `--mcp-config` is what makes that set empty. Either one
# alone is not the decision: strict with a config file loads exactly that
# file's servers, and no config file without strict falls back to the ambient
# resolution the flag exists to suppress. Control 4 drives precisely that
# combination -- strict AND a config -- and requires this row to call it RED,
# so the second half is measured rather than assumed.
#
# WHAT THIS ROW DOES NOT MEASURE. That `--strict-mcp-config` in fact suppresses
# ambient MCP resolution on the CLI installed today is a live-semantics claim,
# and it needs a real child. ADR-002 requires launch checks a fresh clone can
# run offline, so it cannot be a row here; ADR-022 OR-3 carries that hole for
# the whole family and names the procedure -- re-run the live probe and capture
# its output on every CLI upgrade. This row measures what the launcher HANDS
# the child, which is hermetic, and which is the half that can regress silently
# inside this repository.
#
# WHY THE DRIVER IS A `claude` STUB, AND WHY THE STAND-INS ARE PATCHED COPIES:
# the same reasons FT-1 states, and the same mechanism. The stand-ins copy the
# whole scripts/ dir because :88-89, :237, :464 and :493 all resolve their
# helpers from the launcher's OWN directory.
#
# Exit codes: 0 the invariant holds, 1 red, 2 the fixture could not set up.
# Scratch is templated under $TMPDIR and removed on every exit path. Nothing
# absolute is printed.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$PACK/scripts/launch_worker.sh"
CONST_REAL="$PACK/CONSTITUTION.md"
SETTINGS_SRC="$PACK/templates/settings.mode-b.json"
MANIFEST_SRC="$PACK/templates/manifest.example.json"

DECLARED_TOOLS_JSON='["Read","Grep"]'
DECLARED_TOOLS_CSV='Read,Grep'

# Assembled around D so the pinned shellcheck (severity=style) does not report
# SC2016 on a single-quoted expansion; this tree carries no disable directives.
D='$'
# The anchor is the FLAG NAME, never the whole line: D2 rewrites this line's
# value, and an anchor carrying it would report FIXTURE BROKEN at exactly the
# moment the family was repaired. All this row needs is an insertion point.
ANCHOR="--allowedTools"

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$LAUNCHER" ]     || broken "scripts/launch_worker.sh is not where this fixture expects it"
[ -f "$CONST_REAL" ]   || broken "CONSTITUTION.md is not where this fixture expects it"
[ -f "$SETTINGS_SRC" ] || broken "templates/settings.mode-b.json is not where this fixture expects it"
[ -f "$MANIFEST_SRC" ] || broken "templates/manifest.example.json is not where this fixture expects it"
command -v node    >/dev/null 2>&1 || broken "node is not available; the launcher invokes 'node \$HW_CLI next --json'"
command -v git     >/dev/null 2>&1 || broken "git is not available"
command -v python3 >/dev/null 2>&1 || broken "python3 is not available"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-ft3.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

redact() { sed -e "s#$WORK#<scratch>#g" -e "s#$PACK#<pack>#g" "$1" | head -1; }

# ---- the scratch pack ------------------------------------------------------
HOME_SCRATCH="$WORK/pack"
mkdir -p "$HOME_SCRATCH/templates" || broken "could not build the scratch pack"
cp "$CONST_REAL" "$HOME_SCRATCH/CONSTITUTION.md" || broken "could not stage the constitution"
cp "$SETTINGS_SRC" "$HOME_SCRATCH/templates/settings.mode-b.json" || broken "could not stage settings.mode-b.json"

REPO="$WORK/repo"
mkdir -p "$REPO/.harness/specs" || broken "could not create the throwaway repo dir"
git -C "$REPO" init -q || broken "could not init the throwaway repo"
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" config user.name tester
git -C "$REPO" config commit.gpgsign false
git -C "$REPO" config tag.gpgsign false
: > "$REPO/keep"
git -C "$REPO" add -- keep >/dev/null 2>&1 || broken "could not stage the seed file"
git -C "$REPO" commit -q -m "fixture: seed commit" >/dev/null 2>&1 \
  || broken "could not seed the throwaway repo"

SLICE="S-ft3"
SPEC="$REPO/.harness/specs/$SLICE.md"
printf '%s\n' "fixture spec body; the launcher never parses it (ADR-005 D1)" > "$SPEC"

HW="$WORK/fake_next.js"
cat > "$HW" <<JSEOF
if (process.argv[2] !== "next") {
  process.stderr.write("fake next: unexpected subcommand " + process.argv[2] + "\\n");
  process.exit(9);
}
process.stdout.write(JSON.stringify({
  kind: "unlocked",
  id: "$SLICE",
  eligible_mode_b: true,
  spec: {
    model: "worker",
    budget: { turns: 10 },
    tools: $DECLARED_TOOLS_JSON,
    criteria: ["fixture-claim"],
    scope: ["src/"]
  }
}));
JSEOF

VER="$WORK/fake_verity.js"
cat > "$VER" <<'JSEOF'
if (process.argv[2] !== "verify") {
  process.stderr.write("fake verity: unexpected subcommand " + process.argv[2] + "\n");
  process.exit(9);
}
process.stdout.write(JSON.stringify({
  results: [{ id: "fixture-claim", type: "fixture", verdict: "PASS", evidence: "fixture stub" }]
}));
JSEOF

BIN="$WORK/bin"
mkdir -p "$BIN" || broken "could not create the stub bin dir"
cat > "$BIN/claude" <<'SHEOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "0.0.0-fixture"
  exit 0
fi
: > "$FT_SPAWNED"
printf '%s\n' "$@" > "$FT_ARGV"
cat > /dev/null
printf '%s\n' '{"subtype":"success","num_turns":1,"total_cost_usd":0,"duration_ms":1,"session_id":"ft3-fixture","permission_denials":[]}'
exit 0
SHEOF
chmod +x "$BIN/claude" || broken "could not make the claude stub executable"

# ---- the stand-ins ---------------------------------------------------------
# make_standin <dir> <line>... -- the real launcher, copied whole, with the
# given argument lines inserted immediately after the anchor. Exactly one
# anchor must match: zero means the line this row is written against has moved,
# more than one means the insertion point is ambiguous, and both are exit 2.
# The copies exist to be killed by; scripts/ is untouched and nothing here is a
# proposal.
make_standin() {
  local dir="$1"; shift
  cp -R "$PACK/scripts" "$dir" || broken "could not copy scripts/ for the stand-in"
  local payload=""
  local arg
  for arg in "$@"; do payload="${payload}  ${arg}"$'\n'; done
  if ! SI_FILE="$dir/launch_worker.sh" SI_ANCHOR="$ANCHOR" SI_PAYLOAD="$payload" python3 <<'PYEOF'
import os, sys
path = os.environ["SI_FILE"]
anchor = os.environ["SI_ANCHOR"]
with open(path) as fh:
    lines = fh.readlines()
out, hits = [], 0
for line in lines:
    out.append(line)
    if line.strip().startswith(anchor):
        out.append(os.environ["SI_PAYLOAD"])
        hits += 1
if hits != 1:
    sys.stderr.write("anchor matched %d time(s)\n" % hits)
    sys.exit(3)
with open(path, "w") as fh:
    fh.write("".join(out))
PYEOF
  then
    broken "could not build the stand-in: the anchor '$ANCHOR' did not match exactly once in scripts/launch_worker.sh, so this fixture is reading a shape that has moved"
  fi
}

ARGV="$WORK/argv.txt"
SPAWNED="$WORK/spawned.marker"
RUN_OUT="$WORK/run.out"
RUN_ERR="$WORK/run.err"
RUN_RC=0

run_case() {
  rm -f "$ARGV" "$SPAWNED"
  ( cd "$REPO" && \
    PATH="$BIN:$PATH" \
    FT_ARGV="$ARGV" \
    FT_SPAWNED="$SPAWNED" \
    HARNESS_HOME="$HOME_SCRATCH" \
    HARNESS_MANIFEST="$MANIFEST_SRC" \
    HARNESSWRIGHT_CLI="$HW" \
    VERITY_CLI="$VER" \
    RECEIPTS_DIR="$WORK/receipts" \
    bash "$1" "$SPEC" ) >"$RUN_OUT" 2>"$RUN_ERR"
  RUN_RC=$?
  return 0
}

spawned() { [ -f "$SPAWNED" ]; }

# Each run overwrites $ARGV, so every case that will be judged keeps its own
# copy and ARGV_READ names the one being read.
ARGV_READ="$ARGV"
snap() { cp "$ARGV" "$1" 2>/dev/null || broken "no argv was captured for the case being judged"; }

# Whole-line matches only: the capture is one argument per line, so
# `--mcp-config` and `--strict-mcp-config` are distinct lines and neither can
# be mistaken for the other by substring.
flag_value() {
  [ -f "$ARGV_READ" ] || return 0
  awk -v f="$1" 'p { print; exit } $0 == f { p = 1 }' "$ARGV_READ"
}
flag_present() { [ -f "$ARGV_READ" ] && grep -Fxq -- "$1" "$ARGV_READ"; }

# decide <spawned:0|1> <rc> -- two halves, one verdict. Prints the verdict block
# on stdout; returns 0 GREEN, 1 RED. The row and both stand-in controls go
# through this one function.
decide() {
  local strict cfg
  if [ "$1" != "0" ]; then
    echo "RED [FT-3] the launcher never reached the spawn (rc=$2), so no MCP posture was handed to any child"
    return 1
  fi
  strict=1
  if flag_present "--strict-mcp-config"; then strict=0; fi
  cfg=1
  if flag_present "--mcp-config"; then cfg=0; fi
  if [ "$strict" != "0" ]; then
    echo "RED [FT-3] the MCP door is open: the spawned command carries no --strict-mcp-config"
    note "$(printf '%-24s: %s' "--strict-mcp-config" "ABSENT from the spawned argv")"
    note "$(printf '%-24s: %s' "--mcp-config" "$(if [ "$cfg" = "0" ]; then printf '%s' "$(flag_value "--mcp-config")"; else printf 'absent'; fi)")"
    note "without it the child resolves MCP servers from the ambient configuration,"
    note "and ADR-022's Context measures --tools leaving two mcp__ tools on the"
    note "surface with the bound in force: the bound does not reach that namespace"
    return 1
  fi
  if [ "$cfg" = "0" ]; then
    echo "RED [FT-3] strict, but not empty: the spawned command names an MCP config to load"
    note "$(printf '%-24s: %s' "--strict-mcp-config" "present")"
    note "$(printf '%-24s: %s' "--mcp-config" "$(flag_value "--mcp-config")")"
    note "--strict-mcp-config restricts the child to the configuration given on the"
    note "command line; naming one makes that set non-empty, which is a declared"
    note "server and not the closed door D3 decides"
    return 1
  fi
  echo "GREEN [FT-3] the MCP door is shut: --strict-mcp-config is present and no --mcp-config is given"
  note "$(printf '%-24s: %s' "--strict-mcp-config" "present")"
  note "$(printf '%-24s: %s' "--mcp-config" "absent, so the strict set is empty")"
  return 0
}

echo "== FT-3 the bound does not reach MCP tools, and the spawned command does not close that door =="

# ---- control 1: the line the stand-ins are anchored to is still on disk -----
grep -Fq -e "$ANCHOR" "$LAUNCHER" \
  || broken "scripts/launch_worker.sh no longer passes $ANCHOR at all; the stand-ins have no insertion point and this fixture is reading a shape that has moved"
note "control 1: the launcher still assembles its child command around $ANCHOR"

# ---- the row ---------------------------------------------------------------
run_case "$LAUNCHER"
ROW_RC=$RUN_RC
ROW_SPAWNED=1
if spawned; then ROW_SPAWNED=0; fi
ROW_ARGV="$WORK/argv.row.txt"

# ---- control 2: the capture transmits ---------------------------------------
# "No --strict-mcp-config in the argv" is equally what a broken capture
# produces. The flags known to be on the command line are required to be there,
# which proves the stub saw the real argv before its silence is read as
# evidence.
[ "$ROW_SPAWNED" -eq 0 ] \
  || broken "the run never reached the spawn (rc=$ROW_RC); every gate between :213 and :370 has to pass for this fixture to say anything about the child's MCP posture: $(redact "$RUN_ERR")"
[ -s "$ARGV" ] \
  || broken "the child was spawned but no argv was captured; the stub is not recording what this row reads"
snap "$ROW_ARGV"
ARGV_READ="$ROW_ARGV"
ROW_ALLOWED="$(flag_value "--allowedTools")"
[ "$ROW_ALLOWED" = "$DECLARED_TOOLS_CSV" ] \
  || broken "the captured --allowedTools value is '$ROW_ALLOWED' and this fixture declared '$DECLARED_TOOLS_CSV'; the capture is not the real argv, and the absence read below would be the instrument's and not the launcher's"
flag_present "--permission-mode" \
  || broken "the captured argv carries no --permission-mode, which :359 passes unconditionally; the capture is not the real argv"
ROW_ARGC="$(wc -l < "$ROW_ARGV" | tr -d ' ')"
note "control 2: the stub captured $ROW_ARGC arguments carrying --allowedTools and --permission-mode, so an absent flag below is the launcher's silence and not the instrument's"

# ---- control 3: the green branch is reachable, and it fires -----------------
SI_OK="$WORK/standin_strict"
make_standin "$SI_OK" "--strict-mcp-config"
run_case "$SI_OK/launch_worker.sh"
OK_SPAWNED=1
if spawned; then OK_SPAWNED=0; fi
[ "$OK_SPAWNED" -eq 0 ] \
  || broken "the stand-in that emits --strict-mcp-config never reached the spawn (rc=$RUN_RC); there is no held case to drive the green branch with: $(redact "$RUN_ERR")"
snap "$WORK/argv.ctl3.txt"
ARGV_READ="$WORK/argv.ctl3.txt"
CTL3_BLOCK="$(decide "$OK_SPAWNED" "$RUN_RC")"
CTL3_EXIT=$?
[ "$CTL3_EXIT" -eq 0 ] \
  || broken "a launcher emitting --strict-mcp-config with no --mcp-config did not produce a GREEN verdict (verdict exit=$CTL3_EXIT); the green branch is written but not wired"
note "control 3: against a launcher patched to emit --strict-mcp-config, the same decide() returns GREEN (exit=$CTL3_EXIT)"
printf '%s\n' "$CTL3_BLOCK" | sed 's/^/     control 3 > /'

# ---- control 4: the second half is measured, not assumed --------------------
# Strict AND a config file. A row that only counted the presence of the strict
# flag would call this GREEN, and it is precisely the shape D3 forbids: the
# strict set is non-empty and a server loads.
SI_BAD="$WORK/standin_strict_with_config"
make_standin "$SI_BAD" "--strict-mcp-config" "--mcp-config \"${D}HARNESS_HOME/templates/settings.mode-b.json\""
run_case "$SI_BAD/launch_worker.sh"
BAD_SPAWNED=1
if spawned; then BAD_SPAWNED=0; fi
[ "$BAD_SPAWNED" -eq 0 ] \
  || broken "the strict-with-config stand-in never reached the spawn (rc=$RUN_RC); control 4 cannot show that the row reads the second half: $(redact "$RUN_ERR")"
snap "$WORK/argv.ctl4.txt"
ARGV_READ="$WORK/argv.ctl4.txt"
CTL4_BLOCK="$(decide "$BAD_SPAWNED" "$RUN_RC")"
CTL4_EXIT=$?
[ "$CTL4_EXIT" -ne 0 ] \
  || broken "a launcher emitting --strict-mcp-config TOGETHER WITH --mcp-config was judged GREEN; this row counts the presence of one flag and does not measure the empty set D3 decides"
printf '%s' "$CTL4_BLOCK" | grep -Fq 'strict, but not empty' \
  || broken "the strict-with-config stand-in was judged RED for some reason other than the config file; the row is not reading the half it claims to read"
note "control 4: --strict-mcp-config TOGETHER WITH --mcp-config is RED (exit=$CTL4_EXIT), so both halves of D3 are measured"

# ---- the verdict -----------------------------------------------------------
# Back to the row's own capture, taken before either stand-in ran.
ARGV_READ="$ROW_ARGV"
decide "$ROW_SPAWNED" "$ROW_RC"
VERDICT_EXIT=$?

if [ "$VERDICT_EXIT" -eq 0 ]; then
  echo "FT-3 BYPASS FIXTURE: GREEN"
  exit 0
fi
note "green when the spawned command carries --strict-mcp-config AND names no"
note "--mcp-config -- strict with a config file loads that file's servers, and"
note "no config without strict falls back to the ambient resolution the flag"
note "exists to suppress; a Mode B run that loads an MCP server does so by an"
note "explicit declaration in the spec, or not at all"
echo "FT-3 BYPASS FIXTURE: RED"
exit 1
