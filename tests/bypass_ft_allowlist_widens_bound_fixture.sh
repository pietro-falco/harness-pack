#!/usr/bin/env bash
# FT-2 -- the allowlist can name a tool the bound does not contain, and nothing
# refuses it.
#
# THIS ROW STANDS GREEN, and does so from the commit that ratifies ADR-022. It
# was written RED and observed RED against the launcher at
# harness-pack@ef78ad8 -- byte-identical to 14e225f under scripts/, tests/ and
# templates/, so the basis ADR-022 names is the basis measured -- where a spec
# whose allowlist named `Bash` while
# spec.tools declared only `Read` and `Grep` was launched without a word. What
# closes it is ADR-022 D2 -- "a name present in the allowlist and absent from
# spec.tools is a STOP before spawn, never a widening" -- landing in the same
# tree that ratifies the decision.
#
# Everything below this paragraph is written in the tense of the defect,
# because that defect is what this fixture still poses on every run. Soften the
# refusal into a warning, or into a silent intersection that drops the
# offending name and launches anyway, and this row goes red again: D2 decides a
# STOP, and a launcher that quietly repairs the operator's declaration has
# resolved a contradiction the operator never saw.
#
# THE SUBJECT is the relationship between two fields, which at basis is not a
# relationship at all because there is only one field. `scripts/launch_worker.sh:358`
# spends spec.tools on `--allowedTools` and nothing else, so "the allowlist" and
# "the bound" are the same list and cannot disagree. ADR-022 D1 separates them:
# `--tools` becomes the bound and `--allowedTools` is narrowed to what its name
# says, "the subset of spec.tools that executes without a prompt". The moment
# the two can be written separately, they can be written in contradiction, and
# D2 is the decision about which way that contradiction resolves.
#
# It resolves upward into a STOP and never downward into a widening, and the
# reason is the one ADR-022's Context measures: `--allowedTools` does not
# narrow anything. A launcher that honoured an allowlist naming a tool outside
# the bound would be honouring the one flag that cannot enforce a bound, and
# `--permission-mode dontAsk` at :359 answers the only prompt it could raise.
#
# THE FIELD THIS ROW READS IS `spec.allowed_tools`, and that name is this
# fixture's assumption rather than the ADR's. D2 decides the RULE -- an
# allowlist name outside spec.tools STOPs -- and names no field to carry the
# allowlist, because at basis no such field exists in either template. This row
# reads `allowed_tools`, optional, defaulting to spec.tools when absent, which
# is the shape under which the modal spec keeps exactly the meaning it has
# today. Control 4 measures that default explicitly, so a rename would surface
# here as a failure to refuse rather than as a silent pass.
#
# THE ROW IS A STOP *BEFORE SPAWN*, NOT MERELY A NON-ZERO EXIT. A launcher that
# spawned the child and then failed on the way out would have handed a widened
# surface to a model already running, so the marker written by the `claude` stub
# is what this row reads, and the exit code is only reported beside it. That is
# why this fixture runs the real launcher to completion under a stub rather
# than stopping at LAUNCH_DRYRUN: the dryrun exits at :208-211, before the
# spawn exists to be observed at all, and a row that never lets the spawn
# happen cannot testify that it did not.
#
# WHY THE DRIVER IS A FAKE `next`. The launcher does not parse specs (ADR-005
# D1); every field it acts on arrives through `node "$HW_CLI" next --json` at
# :101, and HARNESSWRIGHT_CLI (:10-11) is the documented seam. Everything
# downstream of that JSON is the real launcher running its real gates.
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

# The bound every case in this fixture declares, and the name that is outside
# it. `Bash` is deliberate: it is the widening with the largest blast radius in
# this stack, and it is in the Mode B template's own default list, so a reader
# cannot dismiss the case as contrived.
BOUND_JSON='["Read","Grep"]'
BOUND_CSV='Read,Grep'
OUTSIDE_NAME='Bash'
WIDENING_JSON='["Read","Bash"]'
LEGAL_JSON='["Read"]'

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$LAUNCHER" ]     || broken "scripts/launch_worker.sh is not where this fixture expects it"
[ -f "$CONST_REAL" ]   || broken "CONSTITUTION.md is not where this fixture expects it"
[ -f "$SETTINGS_SRC" ] || broken "templates/settings.mode-b.json is not where this fixture expects it"
[ -f "$MANIFEST_SRC" ] || broken "templates/manifest.example.json is not where this fixture expects it"
command -v node    >/dev/null 2>&1 || broken "node is not available; the launcher invokes 'node \$HW_CLI next --json'"
command -v git     >/dev/null 2>&1 || broken "git is not available"
command -v python3 >/dev/null 2>&1 || broken "python3 is not available"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-ft2.XXXXXX")" || exit 2
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

SLICE="S-ft2"
SPEC="$REPO/.harness/specs/$SLICE.md"
printf '%s\n' "fixture spec body; the launcher never parses it (ADR-005 D1)" > "$SPEC"

# The fake `next` emits whatever spec object the case under test puts in the
# environment, so the allowlist is the only thing that varies across cases.
HW="$WORK/fake_next.js"
cat > "$HW" <<'JSEOF'
if (process.argv[2] !== "next") {
  process.stderr.write("fake next: unexpected subcommand " + process.argv[2] + "\n");
  process.exit(9);
}
process.stdout.write(process.env.FIXTURE_NEXT_JSON || "");
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
printf '%s\n' '{"subtype":"success","num_turns":1,"total_cost_usd":0,"duration_ms":1,"session_id":"ft2-fixture","permission_denials":[]}'
exit 0
SHEOF
chmod +x "$BIN/claude" || broken "could not make the claude stub executable"

# ---- the stand-in ----------------------------------------------------------
# Control 5's stand-in: the minimum shape that would close this row -- read the
# two lists off the same `next --json` the launcher consumes, refuse before
# handing control to anything, and otherwise exec the real launcher unchanged.
# It is FABRICATED and it is not a proposal: it exists so decide()'s green arm
# executes, and scripts/ is untouched. Control 6 requires it to still launch a
# legal spec, so a blanket refuser cannot pass for a working gate.
STANDIN="$WORK/standin_admitting_launcher.sh"
cat > "$STANDIN" <<'SHEOF'
#!/usr/bin/env bash
set -uo pipefail
J="$(node "$HARNESSWRIGHT_CLI" next --json)" || exit 1
OFFENDERS="$(NEXT_JSON="$J" python3 <<'PYEOF'
import json, os
spec = json.loads(os.environ["NEXT_JSON"]).get("spec", {})
tools = spec.get("tools") or []
allowed = spec.get("allowed_tools")
if allowed is None:
    allowed = tools
print(" ".join([a for a in allowed if a not in tools]))
PYEOF
)" || exit 1
if [ -n "$OFFENDERS" ]; then
  echo "STOP spec.allowed_tools names tools absent from spec.tools: $OFFENDERS (the allowlist runs inside the bound, it never widens it)" >&2
  exit 1
fi
exec bash "$LAUNCHER_REAL" "$@"
SHEOF

ARGV="$WORK/argv.txt"
SPAWNED="$WORK/spawned.marker"
RUN_OUT="$WORK/run.out"
RUN_ERR="$WORK/run.err"
RUN_RC=0

# next_json <allowed_tools fragment> -- the bound, the budget, the criteria and
# the scope are identical in every case; the allowlist is the only variable.
next_json() {
  printf '{"kind":"unlocked","id":"%s","eligible_mode_b":true,"spec":{"model":"worker","budget":{"turns":10},"tools":%s,"criteria":["fixture-claim"],"scope":["src/"]%s}}' \
    "$SLICE" "$BOUND_JSON" "$1"
}

# run_case <launcher> <next json>
run_case() {
  rm -f "$ARGV" "$SPAWNED"
  ( cd "$REPO" && \
    PATH="$BIN:$PATH" \
    FIXTURE_NEXT_JSON="$2" \
    FT_ARGV="$ARGV" \
    FT_SPAWNED="$SPAWNED" \
    LAUNCHER_REAL="$LAUNCHER" \
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

# decide <spawned:0|1> <rc> <first stderr line> -- one obligation, one verdict.
# Prints the verdict block on stdout; returns 0 GREEN, 1 RED. The row and the
# stand-in control go through this one function.
decide() {
  if [ "$1" = "0" ]; then
    echo "RED [FT-2] the allowlist widens the bound: a spec naming '$OUTSIDE_NAME' in its allowlist and not in spec.tools was LAUNCHED"
    note "$(printf '%-26s: %s' "spec.tools" "$BOUND_CSV")"
    note "$(printf '%-26s: %s' "spec.allowed_tools" "$(printf '%s' "$WIDENING_JSON" | tr -d '[]\"')")"
    note "$(printf '%-26s: %s' "outcome" "spawned (rc=$2), no refusal anywhere on the path")"
    note "the allowlist is the one flag ADR-022's Context measures as removing"
    note "nothing, so a name admitted through it is admitted by the layer that"
    note "cannot bound anything, and --permission-mode dontAsk at :359 answers"
    note "the only prompt it could have raised"
    return 1
  fi
  if ! printf '%s' "$3" | grep -Fq -- "$OUTSIDE_NAME"; then
    echo "RED [FT-2] the launcher refused, but not for this reason: the STOP does not name '$OUTSIDE_NAME'"
    note "$(printf '%-26s: %s' "outcome" "REFUSED before spawn (rc=$2)")"
    note "$(printf '%-26s: %s' "reason given" "$3")"
    note "a refusal that cannot be attributed to the widening is a refusal about"
    note "something else, and this row would be certifying it by accident"
    return 1
  fi
  echo "GREEN [FT-2] an allowlist name outside spec.tools STOPs the launcher before spawn"
  note "$(printf '%-26s: %s' "spec.tools" "$BOUND_CSV")"
  note "$(printf '%-26s: %s' "spec.allowed_tools" "$(printf '%s' "$WIDENING_JSON" | tr -d '[]\"')")"
  note "$(printf '%-26s: %s' "outcome" "REFUSED before spawn (rc=$2)")"
  note "$(printf '%-26s: %s' "reason given" "$3")"
  return 0
}

echo "== FT-2 the allowlist can name a tool the bound does not contain =="

# ---- control 1: the driver can produce a launch -----------------------------
# Without this, "the widening spec was refused" is equally what a launcher that
# refuses everything produces, and "it was launched" would be the only
# observation this fixture could ever make.
run_case "$LAUNCHER" "$(next_json ", \"allowed_tools\": $LEGAL_JSON")"
CTL1_RC=$RUN_RC
spawned \
  || broken "a spec whose allowlist is a strict subset of spec.tools did not reach the spawn (rc=$CTL1_RC); this driver cannot produce a launch, so a refusal below would say nothing: $(redact "$RUN_ERR")"
note "control 1: allowed_tools $LEGAL_JSON inside tools $BOUND_JSON -> LAUNCHED (rc=$CTL1_RC)"

# ---- control 2: the launcher refuses what it is known to refuse -------------
# A gate one field away, in the same decision block, on the same path. It
# establishes that a STOP is a thing this launcher does before spawning, so the
# row's absence of one is about the allowlist and not about a launcher with no
# refusals in it.
run_case "$LAUNCHER" "$(printf '{"kind":"unlocked","id":"%s","eligible_mode_b":true,"spec":{"model":"worker","budget":{"turns":10},"tools":[],"criteria":["fixture-claim"],"scope":["src/"]}}' "$SLICE")"
CTL2_RC=$RUN_RC
CTL2_MSG="$(grep -m1 'spec.tools' "$RUN_ERR")"
[ "$CTL2_RC" != "0" ] \
  || broken "an empty spec.tools was ACCEPTED (rc=$CTL2_RC); this launcher refuses nothing, so the row below measures nothing"
if spawned; then
  broken "an empty spec.tools reached the spawn; the decision block's STOPs do not happen before the child, and this row's 'before spawn' cannot be measured here"
fi
[ -n "$CTL2_MSG" ] \
  || broken "an empty spec.tools was refused but not by the :163-165 gate; the reason was: $(redact "$RUN_ERR")"
note "control 2: tools:[] is REFUSED before spawn (rc=$CTL2_RC) -- $CTL2_MSG"

# ---- control 3: the stub marker distinguishes spawn from no-spawn -----------
# Control 1 wrote the marker and control 2 did not, on the same driver and the
# same filesystem. That contrast is what licenses reading the marker's ABSENCE
# below as evidence rather than as a fixture that forgot to look.
note "control 3: the same marker was written by control 1 and not by control 2, so its absence below is an observation and not an omission"

# ---- control 4: the default is the bound, and it still launches -------------
# `allowed_tools` absent must mean "the allowlist is spec.tools", which is
# exactly today's meaning of the one field that exists. A launcher that STOPped
# here would have made the new field mandatory, which D2 does not decide.
run_case "$LAUNCHER" "$(next_json '')"
CTL4_RC=$RUN_RC
spawned \
  || broken "a spec with NO allowed_tools field did not reach the spawn (rc=$CTL4_RC); the field is optional and its absence must mean the allowlist is spec.tools, not a new refusal: $(redact "$RUN_ERR")"
note "control 4: allowed_tools absent -> LAUNCHED (rc=$CTL4_RC); the field is optional and defaults to the bound"

# ---- control 5: the green branch is reachable, and it fires -----------------
run_case "$STANDIN" "$(next_json ", \"allowed_tools\": $WIDENING_JSON")"
SI_RC=$RUN_RC
SI_SPAWNED=1
if spawned; then SI_SPAWNED=0; fi
SI_MSG="$(redact "$RUN_ERR")"
[ "$SI_SPAWNED" -ne 0 ] \
  || broken "the fabricated admitting stand-in still spawned on a widening allowlist; there is no held case to drive the green branch with"
CTL5_BLOCK="$(decide "$SI_SPAWNED" "$SI_RC" "$SI_MSG")"
CTL5_EXIT=$?
[ "$CTL5_EXIT" -eq 0 ] \
  || broken "a case in which the launcher refused the widening before spawning did not produce a GREEN verdict (verdict exit=$CTL5_EXIT); the green branch is written but not wired"
note "control 5: against a fabricated launcher that checks the allowlist against the bound, the same decide() returns GREEN (exit=$CTL5_EXIT)"
printf '%s\n' "$CTL5_BLOCK" | sed 's/^/     control 5 > /'

# ---- control 6: the stand-in is a gate and not a blanket refuser ------------
run_case "$STANDIN" "$(next_json ", \"allowed_tools\": $LEGAL_JSON")"
CTL6_RC=$RUN_RC
spawned \
  || broken "the stand-in refused a legal allowlist too (rc=$CTL6_RC); control 5's GREEN came from a launcher that refuses everything, which is not the shape this row would accept: $(redact "$RUN_ERR")"
note "control 6: the same stand-in still LAUNCHES a legal allowlist (rc=$CTL6_RC), so control 5's GREEN is a gate and not a refusal of everything"

# ---- the row ---------------------------------------------------------------
run_case "$LAUNCHER" "$(next_json ", \"allowed_tools\": $WIDENING_JSON")"
ROW_RC=$RUN_RC
ROW_SPAWNED=1
if spawned; then ROW_SPAWNED=0; fi
ROW_MSG="$(redact "$RUN_ERR")"

decide "$ROW_SPAWNED" "$ROW_RC" "$ROW_MSG"
VERDICT_EXIT=$?

if [ "$VERDICT_EXIT" -eq 0 ]; then
  echo "FT-2 BYPASS FIXTURE: GREEN"
  exit 0
fi
note "green when a spec whose allowlist names a tool outside spec.tools is"
note "refused BEFORE the spawn, with a STOP that names the offending tool --"
note "while a legal allowlist, and an absent one, both still launch; a silent"
note "intersection that drops the name and runs anyway is a widening resolved"
note "downward and is refused here as loudly as no check at all"
echo "FT-2 BYPASS FIXTURE: RED"
exit 1
