#!/usr/bin/env bash
# FT-1 -- `spec.tools` is spent on `--allowedTools`, which pre-approves and
# removes nothing, so the field named "tools" is not a bound on the child's
# tool surface.
#
# THIS ROW STANDS GREEN, and does so from the commit that ratifies ADR-022. It
# was written RED and observed RED against the launcher at
# harness-pack@ef78ad8 -- byte-identical to 14e225f under scripts/, tests/ and
# templates/, so the basis ADR-022 names is the basis measured -- where
# scripts/launch_worker.sh assembled its child
# command with `--allowedTools "$TOOLS"` and no `--tools` flag at all. What
# closes it is ADR-022 D1 -- "the launcher emits `--tools "$TOOLS"`; a tool
# absent from spec.tools is absent from the child's surface, not merely
# unapproved" -- landing in the same tree that ratifies the decision.
#
# Everything below this paragraph is written in the tense of the defect,
# because that defect is what this fixture still poses on every run. Take the
# flag back out, or let its value drift from the list the decision block
# resolved, and this row goes red again, which is its whole job.
#
# THE SUBJECT is scripts/launch_worker.sh's child command, composed from the
# decision block that resolves the list:
#
#     :184   print("OK", rid, model, maxturns, wallsec, ",".join(tools), ...)
#     :192   read -r RESOLVED_ID MODEL_STRING MAXTURNS WALLSEC TOOLS CRITERIA
#     :358     --allowedTools "$TOOLS"
#
# ADR-022's Context is the measurement this row exists to hold in place: on
# claude 2.1.231, one prompt and two runs, `--tools Read` came back with three
# names and `--allowedTools Read` came back with thirty-five. `--allowedTools`
# names what runs without a permission prompt. It removes nothing. `--tools`
# removes. A launcher that spends the field on the first flag has declared a
# bound and bought a pre-approval, and with `--permission-mode dontAsk` at
# :359 answering the prompt the allowlist was about, it has bought nothing at
# all.
#
# THE ROW IS IDENTITY, NOT PRESENCE, and control 4 is what makes that true. A
# `--tools` flag carrying some other list would satisfy a presence check while
# binding the child to a surface the spec never declared, so the value is
# compared against the exact comma-joined list the decision block resolved --
# the same string control 2 proves the launcher is already transmitting on the
# other flag.
#
# THE MEASUREMENT CANNOT BE THE LIVE SEMANTICS OF THE FLAG. Whether `--tools`
# still removes on the CLI installed today needs a real child and a real model,
# and ADR-002 requires launch checks a fresh clone can run offline. That hole is
# declared -- ADR-022 OR-3 -- and it is not this row's. This row measures what
# the launcher HANDS the child, which is hermetic, and it is the half that can
# regress silently in this repository.
#
# WHY THE DRIVER IS A `claude` STUB FIRST ON PATH. CMD[0] at :354 is the bare
# word `claude`, resolved through PATH, and the assembled argv is written
# nowhere else: :222 captures the child's STDOUT, and the receipt carries the
# transcript digest, never the command. The stub is the only seam by which the
# spawned command can be observed at all. It is the same mechanism F-e uses,
# for the same reason, and like F-e this row runs the REAL launcher all the way
# to the spawn at :370 -- hash pin, tool version, both slice leases and the t0
# baseline through the real measure_criteria all have to be satisfied for real.
# A fixture that could not get past them would be reporting on the leases.
#
# WHY THE STAND-INS ARE PATCHED COPIES OF THE LAUNCHER. Controls 3 and 4 need
# cases in which the flag IS emitted, and a fabricated mini-launcher would
# exercise a path the row does not measure. So the real launcher is copied into
# scratch with one line inserted after the anchor at :358, and driven through
# the same decide(). scripts/ is untouched; the copy exists to be killed by.
# The whole scripts/ dir is copied because :88-89 resolves launch_checks.py,
# :237 slice_lease.py, :464 write_receipt.py and :493 write_statement.py all
# from the launcher's OWN directory, so a lone copy would STOP on the first of
# them and the control would be reporting on a missing file.
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

# The list this row's fake `next` declares, and the exact string :184 joins it
# into. Two names, neither of them the launcher's own default anywhere, so a
# value that matches cannot have come from a hardcoded fallback.
DECLARED_TOOLS_JSON='["Read","Grep"]'
DECLARED_TOOLS_CSV='Read,Grep'
# The list control 4's divergent stand-in emits instead: a well-formed flag
# value that is not the declared one.
DIVERGENT_CSV='Write,WebFetch'

# Assembled around D so the pinned shellcheck (severity=style) does not report
# SC2016 on a single-quoted expansion; this tree carries no disable directives.
D='$'
# The anchor is the FLAG NAME, never the whole line. D2 rewrites this line's
# VALUE -- the allowlist stops being spec.tools and becomes the subset that
# runs unprompted -- so an anchor carrying the value would report FIXTURE
# BROKEN at exactly the moment the row was repaired. What this row needs from
# the anchor is an insertion point in the child command, and the flag name is
# that point under both spellings.
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-ft1.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

# The broken() paths below quote the launcher's own STOP lines, which can name
# the scratch dir or the pack. First line only, both absolute prefixes scrubbed.
redact() { sed -e "s#$WORK#<scratch>#g" -e "s#$PACK#<pack>#g" "$1" | head -1; }

# ---- the scratch pack ------------------------------------------------------
# HARNESS_HOME is the documented override (:12); :44 derives the constitution
# from it and :357 names settings.mode-b.json out of the same directory. The
# REAL constitution is copied in, unmodified, so the hash pin at :217 passes
# against the shipped manifest: this row is about the tool flags and must not
# also be a story about the pin.
HOME_SCRATCH="$WORK/pack"
mkdir -p "$HOME_SCRATCH/templates" || broken "could not build the scratch pack"
cp "$CONST_REAL" "$HOME_SCRATCH/CONSTITUTION.md" || broken "could not stage the constitution"
cp "$SETTINGS_SRC" "$HOME_SCRATCH/templates/settings.mode-b.json" || broken "could not stage settings.mode-b.json"

# Same git isolation as tests/run_tests.sh:28-34, written into the throwaway
# repo's own .git/config and nowhere else. HALT_ROOT (:52) resolves here, which
# is where both slice leases are taken (:251-258).
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

# REQUESTED_ID comes from the spec FILENAME only (:94), so this basename and
# the id in the fake next JSON must agree or :129-130 STOPs.
SLICE="S-ft1"
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

# The verity stub answers measure_criteria (:271-313) at t0 AND at t1. It
# reports the one declared criterion as PASS so the baseline carries a verdict
# (:331) and the run is not stopped at :346 before it ever reaches the spawn.
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

# The `claude` stub. Two shapes, because :219 calls `claude --version` before
# the spawn and a stub answering only one of them would leave the launcher
# reading `unknown` where production reads a version. The argv is written one
# argument per line: tool names and flag names carry no newlines, so the file
# is an exact, order-preserving record of what the launcher assembled.
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
printf '%s\n' '{"subtype":"success","num_turns":1,"total_cost_usd":0,"duration_ms":1,"session_id":"ft1-fixture","permission_denials":[]}'
exit 0
SHEOF
chmod +x "$BIN/claude" || broken "could not make the claude stub executable"

# ---- the stand-ins ---------------------------------------------------------
# make_standin <dir> <literal argument text> -- the real launcher, copied whole,
# emitting `--tools <text>` and exactly that.
#
# REPLACE IF PRESENT, INSERT IF NOT, and never both. The launcher this row
# demands emits a --tools line; the launcher it was written against did not.
# A builder that only inserted would produce a command carrying the flag TWICE
# once the repair landed, and the divergent control would then be measuring
# which of two duplicates the fixture happens to read rather than what the
# launcher binds. Exactly one line must be produced either way, and any other
# count is exit 2.
make_standin() {
  local dir="$1" argtext="$2"
  cp -R "$PACK/scripts" "$dir" || broken "could not copy scripts/ for the stand-in"
  if ! SI_FILE="$dir/launch_worker.sh" SI_ANCHOR="$ANCHOR" SI_ARG="$argtext" python3 <<'PYEOF'
import os, sys
path = os.environ["SI_FILE"]
anchor = os.environ["SI_ANCHOR"]
arg = os.environ["SI_ARG"]
with open(path) as fh:
    lines = fh.readlines()
line_out = '  --tools "%s"\n' % arg
existing = [i for i, l in enumerate(lines) if l.strip().startswith("--tools")]
if len(existing) > 1:
    sys.stderr.write("the launcher already emits --tools on %d lines\n" % len(existing))
    sys.exit(3)
if existing:
    lines[existing[0]] = line_out
else:
    out, hits = [], 0
    for line in lines:
        out.append(line)
        if line.strip().startswith(anchor):
            out.append(line_out)
            hits += 1
    if hits != 1:
        sys.stderr.write("anchor matched %d time(s)\n" % hits)
        sys.exit(3)
    lines = out
with open(path, "w") as fh:
    fh.write("".join(lines))
PYEOF
  then
    broken "could not build the stand-in: neither an existing --tools line nor exactly one '$ANCHOR' anchor was found in scripts/launch_worker.sh, so this fixture is reading a shape that has moved"
  fi
}

ARGV="$WORK/argv.txt"
SPAWNED="$WORK/spawned.marker"
RUN_OUT="$WORK/run.out"
RUN_ERR="$WORK/run.err"
RUN_RC=0

# run_case <launcher path> -- the real launcher for the row, a patched copy for
# controls 3 and 4. Everything from `next --json` to the spawn is real.
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
# copy and ARGV_READ names the one being read. Without this the row -- which
# must run before control 2 can qualify it -- would be judged on the argv of
# whichever stand-in ran last, and the verdict would be about the control.
ARGV_READ="$ARGV"
snap() { cp "$ARGV" "$1" 2>/dev/null || broken "no argv was captured for the case being judged"; }

# flag_value <flag> -- the argument immediately following <flag> in the captured
# argv, or the empty string when the flag is absent. Whole-line matches only:
# the capture is one argument per line, so a flag is a line and its value is the
# next one, and no substring of some other argument can be mistaken for either.
flag_value() {
  [ -f "$ARGV_READ" ] || return 0
  awk -v f="$1" 'p { print; exit } $0 == f { p = 1 }' "$ARGV_READ"
}
# How many times the flag appears -- presence is read off this count rather
# than off a separate predicate, so the absent case and the duplicated case are
# answered by one instrument. A bound declared twice is not a bound: which
# of the two the child honours is the CLI's business and not this repository's,
# and a fixture reading only the first would certify whichever one it happened
# to see.
flag_count() {
  [ -f "$ARGV_READ" ] || { echo 0; return; }
  awk -v f="$1" '$0 == f { n++ } END { print n + 0 }' "$ARGV_READ"
}

# decide <spawned:0|1> <rc> -- one obligation in two parts, one verdict.
# Prints the verdict block on stdout; returns 0 GREEN, 1 RED. The row and both
# stand-in controls go through this one function: a control exercising a
# private copy would prove nothing about the row.
decide() {
  local sp="$1" rc="$2" got present n
  if [ "$sp" != "0" ]; then
    echo "RED [FT-1] the launcher never reached the spawn (rc=$rc), so no bound was handed to any child"
    return 1
  fi
  n="$(flag_count "--tools")"
  present=1
  if [ "$n" -ge 1 ]; then present=0; fi
  got="$(flag_value "--tools")"
  if [ "$n" -gt 1 ]; then
    echo "RED [FT-1] the bound is declared $n times: the spawned command carries more than one --tools flag"
    note "$(printf '%-30s: %s' "declared by the spec" "$DECLARED_TOOLS_CSV")"
    note "$(printf '%-30s: %s' "first --tools" "$got")"
    note "which of the two the child honours is the CLI's business; a launcher"
    note "that hands it a contradiction has not declared a bound"
    return 1
  fi
  if [ "$present" != "0" ]; then
    echo "RED [FT-1] spec.tools is not a bound: the spawned command carries no --tools flag"
    note "$(printf '%-30s: %s' "--tools" "ABSENT from the spawned argv")"
    note "$(printf '%-30s: %s' "--allowedTools" "$(flag_value "--allowedTools")")"
    note "the field is spent entirely on the flag that pre-approves, and ADR-022's"
    note "Context measures that flag removing nothing: 35 tool names reached the"
    note "child under --allowedTools Read, against 3 under --tools Read"
    return 1
  fi
  if [ "$got" != "$DECLARED_TOOLS_CSV" ]; then
    echo "RED [FT-1] the bound is not spec.tools: --tools carries a list the spec never declared"
    note "$(printf '%-30s: %s' "declared by the spec" "$DECLARED_TOOLS_CSV")"
    note "$(printf '%-30s: %s' "handed to the child" "$got")"
    note "a --tools flag carrying some other list binds the child to a surface"
    note "the operator did not declare, which is a different defect and not a repair"
    return 1
  fi
  echo "GREEN [FT-1] spec.tools is a bound: the spawned command carries --tools with exactly the declared list"
  note "$(printf '%-30s: %s' "declared by the spec" "$DECLARED_TOOLS_CSV")"
  note "$(printf '%-30s: %s' "--tools" "$got")"
  note "$(printf '%-30s: %s' "--allowedTools" "$(flag_value "--allowedTools")")"
  return 0
}

echo "== FT-1 spec.tools is spent on --allowedTools, which pre-approves and removes nothing =="

# ---- control 1: the line this row is written against is still on disk -------
grep -Fq -e "$ANCHOR" "$LAUNCHER" \
  || broken "scripts/launch_worker.sh no longer passes $ANCHOR at all; the composition this row measures has moved, and the stand-ins have no insertion point"
note "control 1: the launcher still assembles its child command around $ANCHOR"

# ---- the row ---------------------------------------------------------------
# Run first, because controls 2 reads its capture: the question is what THIS
# launcher hands a child, and the controls qualify that same observation.
run_case "$LAUNCHER"
ROW_RC=$RUN_RC
ROW_SPAWNED=1
if spawned; then ROW_SPAWNED=0; fi
ROW_ARGV="$WORK/argv.row.txt"

# ---- control 2: the capture transmits, and agrees about the declared list ---
# Without this, "no --tools in the argv" is equally what a broken capture
# produces. The allowlist flag is known to be there and known to carry exactly
# the comma-joined spec.tools, so finding it proves the stub saw the real argv
# AND that this fixture's notion of the declared list is the launcher's.
[ "$ROW_SPAWNED" -eq 0 ] \
  || broken "the run never reached the spawn (rc=$ROW_RC); every gate between :213 and :370 has to pass for this fixture to say anything about the tool flags: $(redact "$RUN_ERR")"
[ -s "$ARGV" ] \
  || broken "the child was spawned but no argv was captured; the stub is not recording what this row reads"
snap "$ROW_ARGV"
ARGV_READ="$ROW_ARGV"
ROW_ALLOWED="$(flag_value "--allowedTools")"
[ "$ROW_ALLOWED" = "$DECLARED_TOOLS_CSV" ] \
  || broken "the captured --allowedTools value is '$ROW_ALLOWED' and this fixture declared '$DECLARED_TOOLS_CSV'; either the capture is not the real argv or the launcher no longer transmits spec.tools on that flag, and the row below would measure the instrument"
ROW_ARGC="$(wc -l < "$ROW_ARGV" | tr -d ' ')"
note "control 2: the stub captured $ROW_ARGC arguments and --allowedTools carries exactly the declared list, so the argv is the launcher's and the declared list is agreed"

# ---- control 3: the green branch is reachable, and it fires -----------------
SI_OK="$WORK/standin_bound"
make_standin "$SI_OK" "${D}TOOLS"
run_case "$SI_OK/launch_worker.sh"
OK_SPAWNED=1
if spawned; then OK_SPAWNED=0; fi
[ "$OK_SPAWNED" -eq 0 ] \
  || broken "the stand-in that emits --tools never reached the spawn (rc=$RUN_RC); there is no held case to drive the green branch with: $(redact "$RUN_ERR")"
snap "$WORK/argv.ctl3.txt"
ARGV_READ="$WORK/argv.ctl3.txt"
CTL3_BLOCK="$(decide "$OK_SPAWNED" "$RUN_RC")"
CTL3_EXIT=$?
[ "$CTL3_EXIT" -eq 0 ] \
  || broken "a launcher emitting --tools with exactly spec.tools did not produce a GREEN verdict (verdict exit=$CTL3_EXIT); the green branch is written but not wired"
note "control 3: against a launcher patched to emit --tools \"\$TOOLS\", the same decide() returns GREEN (exit=$CTL3_EXIT)"
printf '%s\n' "$CTL3_BLOCK" | sed 's/^/     control 3 > /'

# ---- control 4: the row measures identity, not presence --------------------
SI_BAD="$WORK/standin_divergent"
make_standin "$SI_BAD" "$DIVERGENT_CSV"
run_case "$SI_BAD/launch_worker.sh"
BAD_SPAWNED=1
if spawned; then BAD_SPAWNED=0; fi
[ "$BAD_SPAWNED" -eq 0 ] \
  || broken "the divergent stand-in never reached the spawn (rc=$RUN_RC); control 4 cannot show that the row reads the value: $(redact "$RUN_ERR")"
snap "$WORK/argv.ctl4.txt"
ARGV_READ="$WORK/argv.ctl4.txt"
CTL4_BLOCK="$(decide "$BAD_SPAWNED" "$RUN_RC")"
CTL4_EXIT=$?
[ "$CTL4_EXIT" -ne 0 ] \
  || broken "a launcher emitting --tools '$DIVERGENT_CSV' against a spec declaring '$DECLARED_TOOLS_CSV' was judged GREEN; this row measures the presence of a flag and not the bound it carries"
printf '%s' "$CTL4_BLOCK" | grep -Fq 'the bound is not spec.tools' \
  || broken "the divergent stand-in was judged RED for some reason other than the value; the row is not reading the list it claims to read"
note "control 4: a --tools carrying '$DIVERGENT_CSV' is RED against a spec declaring '$DECLARED_TOOLS_CSV' (exit=$CTL4_EXIT), so this row reads the bound and not merely the flag"

# ---- the verdict -----------------------------------------------------------
# Back to the row's own capture, taken before either stand-in ran.
ARGV_READ="$ROW_ARGV"
decide "$ROW_SPAWNED" "$ROW_RC"
VERDICT_EXIT=$?

if [ "$VERDICT_EXIT" -eq 0 ]; then
  echo "FT-1 BYPASS FIXTURE: GREEN"
  exit 0
fi
note "green when the spawned command carries --tools whose value is exactly the"
note "comma-joined spec.tools the decision block resolved at :184 -- neither the"
note "flag alone nor some other list, because a bound the operator did not"
note "declare is a different defect and not a repair"
echo "FT-1 BYPASS FIXTURE: RED"
exit 1
