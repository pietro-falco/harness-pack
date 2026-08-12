#!/usr/bin/env bash
# F-e -- a secret placed in CONSTITUTION.md reaches the worker's system prompt
# verbatim, because nothing on the injection path looks at what it injects.
#
# THE ASSERTION UNDER TEST IS NOT THIS REPOSITORY'S. It is row B116 of
# rubric-table-BCD.md@8e392a0dd338d2a937f1ce029faf437b5249318f678416d97f9121cf0e8defd8,
# which reads, in full:
#
#     | B116 | B:116 | Secrets stay out of context, injected only at runtime |
#     FALSIFICABILE | NEW: `bypass_fe_secret_in_context` | No scan exists;
#     `CONSTITUTION.md` is injected verbatim, unscanned |
#
# That file lives outside this repository and outside any git tree, so control 1
# cannot read it and this fixture does not pretend to. It is quoted here at its
# digest, and what control 1 reads are the two IN-REPO literals the row is about.
#
# ONLY THE FIRST HALF OF B116 IS MEASURED. "Secrets stay out of context" is
# falsifiable against this stack, and this fixture falsifies it. "injected only
# at runtime" is not: no runtime secret-injection mechanism is declared anywhere
# in this repository, and a row asserting that an undeclared feature is absent
# measures nothing at all. That half is out of scope BY DECISION, and saying so
# is the decision -- an unmeasured half left unnamed would read as a measured one.
#
# THE SUBJECT is scripts/launch_worker.sh:44 composed with :217 and :356. The
# file is read twice and transformed never:
#
#     :44    CONST="$HARNESS_HOME/CONSTITUTION.md"
#     :217   CHASH="$(python3 "$CHECKS" check-hash "$CONST" "$MANIFEST")" || exit 1
#     :356     --append-system-prompt "$(cat "$CONST")"
#
# and the file itself declares that this is the contract (CONSTITUTION.md:6-9):
#
#     injection-contract: appended verbatim (via --append-system-prompt) to
#     every worker system prompt by the launcher; sha256 recorded in every
#     receipt as constitution_hash.
#
# "appended verbatim" is not an accusation this fixture makes. It is the
# repository's own statement that nothing intervenes, and control 1 reads it.
#
# THE THREAT MODEL IS OPERATOR ERROR, NOT AN ADVERSARY. /opt/harness/CONSTITUTION.md
# is root:wheel and covered by /opt/harness/MANIFEST.sha256:15, so an unprivileged
# writer cannot reach it and a row framed around one would die on "requires root,
# out of scope". The row framed around the operator survives, and it is the one
# B116 is actually about: the operator edits the constitution, re-pins the
# manifest -- the DOCUMENTED procedure for every change to that file -- and
# whatever was pasted in is now in the system prompt of every worker, forever,
# with no gate anywhere on the path.
#
# WHAT THE PIN BUYS AND WHAT IT DOES NOT. :217 is a real, fail-closed gate and
# control 4 proves it fires. What it measures is the IDENTITY of the bytes, not
# their content: a clean re-pin and a poisoned re-pin are the same operation to
# it, and it is satisfied by both. The receipt records constitution_hash and never
# the text (scripts/write_receipt.py:135), so the audit artifact witnesses THAT
# the constitution changed and cannot witness WHAT it now carries. This is why the
# fixture has to observe the child directly: there is no artifact to read instead.
#
# WHY THIS FIXTURE CANNOT USE THE SEAM THE OTHERS USE. LAUNCH_DRYRUN exits at
# :208-211 -- "Stop here before touching the constitution or invoking claude" --
# so under the dryrun the constitution is never read and the injection never
# happens. F-b, F-c and F8 build their rows on that exit; F-e cannot. It runs the
# real launcher all the way to the spawn at :370 with a stub `claude` first on
# PATH, which means every gate between :213 and :370 -- hash pin, tool version,
# both slice leases, and the t0 baseline through the real measure_criteria -- has
# to be satisfied for real. A fixture that could not get past them would be
# reporting on the leases, not on the constitution.
#
# THE CONTROLS ARE THE POINT OF THIS FIXTURE, not a preamble.
#
#   control 1  the two literals this row is about are still on disk, in the
#              constitution and in the launcher. Their absence is exit 2, never
#              a pass: if the injection contract or the injection line moved,
#              this fixture is reading a shape that no longer exists.
#   control 2  the canary is secret-shaped by an EXTERNAL judgment. gitleaks is
#              handed the string and must flag it. Without this the fixture would
#              be asserting on its own authority that some text is a secret, and
#              a row proving that arbitrary text reaches the prompt proves
#              nothing anyone disputes. gitleaks absent is exit 2, not a pass.
#   control 3  the driver transmits. The same driver is run FIRST on the INTACT
#              constitution and is required to come back with the injection-
#              contract line present in the captured prompt and the canary
#              absent. Only against that is "the canary is in the prompt" a
#              statement about the constitution rather than about the stub: a
#              capture containing the canary and nothing else is also what a
#              harness that captured its own scratch file would produce.
#   control 4  the pin is live. The doctored constitution with the manifest NOT
#              re-pinned must be REFUSED before the spawn. This is what makes the
#              row's re-pin the operator's documented procedure and not the
#              circumvention of a gate -- without it the row would be open to
#              "you disabled the check", and the answer has to be measured.
#   control 5  the GREEN branch is reachable, and it fires. The row is red today,
#              so decide()'s green arm would otherwise be written and never
#              executed, and a branch never executed is not a gate. A FABRICATED
#              wrapper -- gitleaks over the constitution, STOP before exec'ing
#              the real launcher -- is driven by the same run_case() and judged by
#              the same decide(), and must come back GREEN. It is the minimum fix
#              this row would accept, built here only to be killed by; nothing
#              proposes it and scripts/ is untouched.
#
# WHY THE DRIVER IS A FAKE `next` AND A FAKE `verity`. The launcher does not parse
# specs (ADR-005 D1); its budget, tools, criteria and scope all arrive through
# `node "$HW_CLI" next --json` at :101, and HARNESSWRIGHT_CLI (:10-11) is the
# documented seam. VERITY_CLI is the second: measure_criteria at :271-313 runs
# `node "$VERITY_CLI" verify --json` BEFORE the spawn, and a t0 that produces no
# verdict STOPs the run at :346-350. F-b can leave its verity stub empty because
# it exits at the dryrun and never reaches that call; this one reaches it, so the
# stub emits a real report. Everything between those two JSON documents and the
# spawn is the real launcher running its real gates, against the shipped
# templates/manifest.example.json rather than a synthetic one.
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

# The canary. Every variable component is zeros, so the string is manifestly
# fictitious to a reader, and control 2 requires it to be a finding to a scanner.
# The trailing directive keeps this line from arming a repo-wide secret gate
# against its own test corpus when ADR-009 OR-B is eventually closed: a named,
# in-place exception, not an entry in a config file that would outlive it.
CANARY='xoxb-000000000000-000000000000-abcdefghijklmnopqrstuvwx' # gitleaks:allow

# The two in-repo literals control 1 reads. The launcher one is assembled around
# D so the pinned shellcheck (severity=style) does not report SC2016 on a
# single-quoted expansion, and this tree carries no disable directives.
D='$'
CONTRACT_LINE='injection-contract: appended verbatim (via --append-system-prompt) to'
INJECT_LINE="--append-system-prompt \"${D}(cat \"${D}CONST\")\""

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$LAUNCHER" ]     || broken "scripts/launch_worker.sh is not where this fixture expects it"
[ -f "$CONST_REAL" ]   || broken "CONSTITUTION.md is not where this fixture expects it"
[ -f "$SETTINGS_SRC" ] || broken "templates/settings.mode-b.json is not where this fixture expects it"
[ -f "$MANIFEST_SRC" ] || broken "templates/manifest.example.json is not where this fixture expects it"
command -v node     >/dev/null 2>&1 || broken "node is not available; the launcher invokes 'node \$HW_CLI next --json'"
command -v git      >/dev/null 2>&1 || broken "git is not available"
command -v python3  >/dev/null 2>&1 || broken "python3 is not available"
command -v shasum   >/dev/null 2>&1 || broken "shasum is not available; the manifest re-pin needs it"
command -v gitleaks >/dev/null 2>&1 || broken "gitleaks is not available; control 2 cannot obtain an external judgment on the canary, and this fixture will not assert on its own authority that a string is a secret"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-fe.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

# The broken() paths below quote the launcher's own STOP lines, which can name
# the scratch dir or the pack. First line only, both absolute prefixes scrubbed.
redact() { sed -e "s#$WORK#<scratch>#g" -e "s#$PACK#<pack>#g" "$1" | head -1; }

# ---- the scratch pack, the scratch repo, the stubs -------------------------
# HARNESS_HOME is the documented override (:12) and :44 derives CONST from it, so
# the doctored constitution lives here and the tracked one is never touched. The
# settings file is copied because :357 names it out of the same directory: a
# scratch pack missing a file the launcher references is a difference from
# production this fixture has not accounted for.
HOME_SCRATCH="$WORK/pack"
mkdir -p "$HOME_SCRATCH/templates" || broken "could not build the scratch pack"
cp "$SETTINGS_SRC" "$HOME_SCRATCH/templates/settings.mode-b.json" || broken "could not stage settings.mode-b.json"

CONST_DOCTORED="$WORK/const_doctored.md"
cp "$CONST_REAL" "$CONST_DOCTORED" || broken "could not copy the constitution"
{
  printf '\n'
  printf '## G-tmp -- deploy credential (pasted during the 2026-08 rotation)\n'
  printf 'slack_bot_token: %s\n' "$CANARY"
} >> "$CONST_DOCTORED"

MANIFEST_STOCK="$WORK/manifest_stock.json"
MANIFEST_PINNED="$WORK/manifest_pinned.json"
cp "$MANIFEST_SRC" "$MANIFEST_STOCK" || broken "could not copy the manifest"
DOCTORED_SHA="$(shasum -a 256 "$CONST_DOCTORED" | cut -d' ' -f1)"
[ -n "$DOCTORED_SHA" ] || broken "could not compute the doctored constitution digest"
MANIFEST_SRC="$MANIFEST_SRC" OUT_PATH="$MANIFEST_PINNED" NEW_SHA="$DOCTORED_SHA" python3 <<'PYEOF' || broken "could not re-pin the scratch manifest"
import json, os
m = json.load(open(os.environ["MANIFEST_SRC"]))
m["constitution_hash_expected"] = os.environ["NEW_SHA"]
json.dump(m, open(os.environ["OUT_PATH"], "w"), indent=2)
PYEOF

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

# REQUESTED_ID comes from the spec FILENAME only (:94), so this basename and the
# id in the fake next JSON must agree or :129-130 STOPs.
SLICE="S-fe"
SPEC="$REPO/.harness/specs/$SLICE.md"
printf '%s\n' "fixture spec body; the launcher never parses it (ADR-005 D1)" > "$SPEC"

HW="$WORK/fake_next.js"
cat > "$HW" <<'JSEOF'
if (process.argv[2] !== "next") {
  process.stderr.write("fake next: unexpected subcommand " + process.argv[2] + "\n");
  process.exit(9);
}
process.stdout.write(JSON.stringify({
  kind: "unlocked",
  id: "S-fe",
  eligible_mode_b: true,
  spec: {
    model: "worker",
    budget: { turns: 10 },
    tools: ["Read"],
    criteria: ["fixture-claim"],
    scope: ["src/"]
  }
}));
JSEOF

# The verity stub answers measure_criteria (:271-313) at t0 AND at t1. It reports
# the one declared criterion as PASS so the baseline carries a verdict (:331) and
# the run is not stopped at :346 before it ever reaches the constitution.
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

# The `claude` stub. CMD[0] at :354 is the bare word `claude`, resolved through
# PATH, which is the only seam by which the assembled argv can be observed at
# all: the launcher writes the prompt nowhere (:222 captures the child's STDOUT,
# not its system prompt) and the receipt carries the digest only. Two shapes,
# because :219 calls `claude --version` before the spawn and a stub answering
# only one of them would leave the launcher reading `unknown` where production
# reads a version.
BIN="$WORK/bin"
mkdir -p "$BIN" || broken "could not create the stub bin dir"
cat > "$BIN/claude" <<'SHEOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "0.0.0-fixture"
  exit 0
fi
: > "$FE_SPAWNED"
prev=""
for a in "$@"; do
  if [ "$prev" = "--append-system-prompt" ]; then
    printf '%s' "$a" > "$FE_CAPTURE"
    break
  fi
  prev="$a"
done
cat > /dev/null
printf '%s\n' '{"subtype":"success","num_turns":1,"total_cost_usd":0,"duration_ms":1,"session_id":"fe-fixture","permission_denials":[]}'
exit 0
SHEOF
chmod +x "$BIN/claude" || broken "could not make the claude stub executable"

# Control 5's stand-in: a FABRICATED scan step ON the injection path, and nothing
# else in this fixture runs against it. It is the minimum shape that would close
# this row -- look at the bytes before they are injected, refuse if a scanner
# calls them a secret -- and it exists so decide()'s green arm executes. It is not
# a proposal and scripts/ is untouched.
STANDIN="$WORK/standin_scanning_launcher.sh"
cat > "$STANDIN" <<'SHEOF'
#!/usr/bin/env bash
set -uo pipefail
C="${HARNESS_HOME:?}/CONSTITUTION.md"
D="$(mktemp -d "${TMPDIR:-/tmp}/fe-scan.XXXXXX")" || exit 2
cp "$C" "$D/const.md" || exit 2
gitleaks dir --no-banner "$D" >/dev/null 2>&1
rc=$?
rm -rf "$D"
if [ "$rc" -ne 0 ]; then
  echo "STOP: the constitution carries scanner-detectable secret material; refusing to inject it." >&2
  exit 1
fi
exec bash "$LAUNCHER_REAL" "$@"
SHEOF

CAPTURE="$WORK/captured_system_prompt.txt"
SPAWNED="$WORK/spawned.marker"
RUN_OUT="$WORK/run.out"
RUN_ERR="$WORK/run.err"
RUN_RC=0

# run_case <launcher> <constitution> <manifest>
# The real launcher for every control and for the row; the stand-in only for
# control 5. Everything from `next --json` to the spawn is the real launcher.
run_case() {
  rm -f "$CAPTURE" "$SPAWNED"
  cp "$2" "$HOME_SCRATCH/CONSTITUTION.md" || broken "could not stage the constitution under the scratch pack"
  ( cd "$REPO" && \
    PATH="$BIN:$PATH" \
    FE_CAPTURE="$CAPTURE" \
    FE_SPAWNED="$SPAWNED" \
    LAUNCHER_REAL="$LAUNCHER" \
    HARNESS_HOME="$HOME_SCRATCH" \
    HARNESS_MANIFEST="$3" \
    HARNESSWRIGHT_CLI="$HW" \
    VERITY_CLI="$VER" \
    RECEIPTS_DIR="$WORK/receipts" \
    bash "$1" "$SPEC" ) >"$RUN_OUT" 2>"$RUN_ERR"
  RUN_RC=$?
  return 0
}

spawned() { [ -f "$SPAWNED" ]; }
canary_in_prompt() { [ -f "$CAPTURE" ] && grep -Fq -- "$CANARY" "$CAPTURE"; }

# closure <rc> <spawned:0|1> <canary:0|1> -- how one case ended, in one phrase,
# naming which of the two ways closed it. Returns 0 when the obligation is HELD,
# 1 when the secret reached the prompt.
closure() {
  if [ "$2" != "0" ]; then
    printf 'REFUSED before spawn (rc=%s), closed by the LAUNCHER STOPPING' "$1"
    return 0
  fi
  if [ "$3" != "0" ]; then
    printf 'spawned (rc=%s), closed by the canary being ABSENT from the system prompt' "$1"
    return 0
  fi
  printf 'spawned (rc=%s), canary PRESENT VERBATIM in the system prompt' "$1"
  return 1
}

# decide <rc> <spawned> <canary> -- one obligation, one verdict. Prints the
# verdict block on stdout; returns 0 GREEN, 1 RED. Control 5 and the row go
# through this one function: a control exercising a private copy would prove
# nothing about the row.
decide() {
  local phrase held
  phrase="$(closure "$1" "$2" "$3")"
  closure "$1" "$2" "$3" >/dev/null; held=$?
  if [ "$held" -eq 0 ]; then
    echo "GREEN [F-e] a secret in the constitution does not reach the worker system prompt"
  else
    echo "RED [F-e] a secret in the constitution reaches the worker system prompt verbatim, unscanned"
  fi
  note "$(printf '%-34s: %s' "doctored constitution, re-pinned" "$phrase")"
  if [ "$held" -eq 0 ]; then
    return 0
  fi
  note "the same driver on the INTACT constitution transmits the contract line and"
  note "carries no canary (control 3), so this is the constitution answering and"
  note "not the capture harness"
  note "the pin at :217 fired on the same file with the manifest unrepinned"
  note "(control 4), so this row is the DOCUMENTED re-pin procedure and not the"
  note "circumvention of a gate"
  note "nothing on scripts/launch_worker.sh:44 -> :217 -> :356 looks at what it"
  note "injects: :217 pins the identity of the bytes, never their content, and a"
  note "clean re-pin and a poisoned one are the same operation to it"
  note "green when the launcher either stops before the spawn on a constitution"
  note "carrying scanner-detectable secret material, or the material is absent"
  note "from the prompt it hands the child -- there is no third way, because"
  note "re-pinning is the procedure, not a bypass"
  return 1
}

echo "== F-e a secret in CONSTITUTION.md reaches the worker system prompt unscanned =="

# ---- control 1: the two literals this row is about are still on disk ---------
grep -Fq -- "$CONTRACT_LINE" "$CONST_REAL" \
  || broken "CONSTITUTION.md no longer declares the verbatim injection contract; the declaration this row measures has moved"
grep -Fq -- "$INJECT_LINE" "$LAUNCHER" \
  || broken "scripts/launch_worker.sh no longer injects the constitution with --append-system-prompt \"\$(cat \"\$CONST\")\"; this fixture is reading the wrong shape"
note "control 1: the injection contract is declared at CONSTITUTION.md and performed at scripts/launch_worker.sh, both read literally"

# ---- control 2: the canary is secret-shaped by an external judgment ----------
GLDIR="$WORK/gl"
mkdir -p "$GLDIR" || broken "could not create the gitleaks probe dir"
printf '%s\n' "$CANARY" > "$GLDIR/canary.txt"
gitleaks dir --no-banner "$GLDIR" >/dev/null 2>&1
GL_RC=$?
rm -rf "$GLDIR"
[ "$GL_RC" -ne 0 ] \
  || broken "gitleaks did not flag the canary (rc=$GL_RC); it is not secret-shaped for this scanner, and a row showing that arbitrary text reaches the prompt measures nothing B116 asserts"
note "control 2: gitleaks flags the canary (rc=$GL_RC); the judgment that this string is a secret is external to this fixture"

# ---- control 3: the driver transmits ----------------------------------------
run_case "$LAUNCHER" "$CONST_REAL" "$MANIFEST_STOCK"
[ "$RUN_RC" -eq 0 ] \
  || broken "the control run over the INTACT constitution did not complete (rc=$RUN_RC): $(redact "$RUN_ERR")"
spawned \
  || broken "the control run over the INTACT constitution never reached the spawn; every gate between :213 and :370 has to pass for this fixture to say anything about the constitution"
[ -f "$CAPTURE" ] \
  || broken "the child was spawned with no --append-system-prompt argument; the injection this row measures did not happen and the fixture is reading the wrong shape"
grep -Fq -- "$CONTRACT_LINE" "$CAPTURE" \
  || broken "the INTACT constitution did not arrive in the captured system prompt; this driver is not transmitting the constitution, so the row below would measure the instrument"
if canary_in_prompt; then
  broken "the canary appeared in the prompt captured from the INTACT constitution; the capture is contaminated and proves nothing about the doctored file"
fi
# Verbatim, measured rather than quoted. The launcher injects the VALUE of
# $(cat "$CONST") (:356), and command substitution strips trailing newlines, so
# the captured argument is one byte shorter than the file and a byte count alone
# invites "then it is not verbatim". The expectation is therefore built by
# REPLICATING :356's own expression rather than by arithmetic, and compared by
# digest: equal digests say the child received the constitution byte for byte,
# modulo exactly the stripping the launcher's own expression performs.
CTL3_BYTES="$(wc -c < "$CAPTURE" | tr -d ' ')"
CONST_BYTES="$(wc -c < "$CONST_REAL" | tr -d ' ')"
EXPECT_SHA="$(printf '%s' "$(cat "$CONST_REAL")" | shasum -a 256 | cut -d' ' -f1)"
GOT_SHA="$(shasum -a 256 < "$CAPTURE" | cut -d' ' -f1)"
[ "$EXPECT_SHA" = "$GOT_SHA" ] \
  || broken "the captured system prompt is not the constitution: expected the digest of \$(cat CONSTITUTION.md) and got a different one ($CTL3_BYTES bytes captured against $CONST_BYTES on disk); this driver is not transmitting the file, so the row below would measure the instrument"
note "control 3: the intact constitution arrives verbatim -- the captured digest equals the digest of \$(cat CONSTITUTION.md), $CTL3_BYTES bytes of $CONST_BYTES (command substitution strips the trailing newline); contract line present, canary absent"

# ---- control 4: the pin at :217 is live -------------------------------------
run_case "$LAUNCHER" "$CONST_DOCTORED" "$MANIFEST_STOCK"
CTL4_RC=$RUN_RC
[ "$CTL4_RC" -ne 0 ] \
  || broken "the doctored constitution was accepted against an unrepinned manifest (rc=$CTL4_RC); the hash pin at :217 is not firing, and this row could not distinguish itself from disabling a gate"
if spawned; then
  broken "the launcher reached the spawn with the doctored constitution and an unrepinned manifest; :217 does not gate the injection path"
fi
note "control 4: doctored constitution + unrepinned manifest -> refused before spawn (rc=$CTL4_RC), so the row below is the documented re-pin, not a bypassed gate"

# ---- control 5: the GREEN branch is reachable, and it fires ------------------
run_case "$STANDIN" "$CONST_DOCTORED" "$MANIFEST_PINNED"
SI_RC=$RUN_RC
SI_SPAWNED=1
if spawned; then SI_SPAWNED=0; fi
SI_CANARY=1
if canary_in_prompt; then SI_CANARY=0; fi
[ "$SI_SPAWNED" -ne 0 ] \
  || broken "the fabricated scanning stand-in still spawned on a constitution carrying the canary; there is no held case to drive the green branch with"
CTL5_BLOCK="$(decide "$SI_RC" "$SI_SPAWNED" "$SI_CANARY")"
CTL5_EXIT=$?
[ "$CTL5_EXIT" -eq 0 ] \
  || broken "a case in which the launcher refused before spawning did not produce a GREEN verdict (verdict exit=$CTL5_EXIT); the green branch is written but not wired"
printf '%s' "$CTL5_BLOCK" | grep -Fq 'GREEN [F-e]' \
  || broken "the held case did not print the GREEN verdict; decide() is not the function this row will be judged by"
note "control 5: against a fabricated launcher that scans before injecting, the same decide() returns GREEN (exit=$CTL5_EXIT)"
printf '%s\n' "$CTL5_BLOCK" | sed 's/^/     control 5 > /'

# ---- the row ----------------------------------------------------------------
# The operator's own procedure, end to end: edit the constitution, re-pin the
# manifest, launch. Everything from here is the real launcher.
run_case "$LAUNCHER" "$CONST_DOCTORED" "$MANIFEST_PINNED"
ROW_RC=$RUN_RC
ROW_SPAWNED=1
if spawned; then ROW_SPAWNED=0; fi
if [ "$ROW_SPAWNED" -ne 0 ]; then
  if [ "$ROW_RC" -eq 0 ]; then
    broken "the row run exited 0 without reaching the spawn; the fixture cannot tell a refusal from a silent skip: $(redact "$RUN_ERR")"
  fi
fi
if [ "$ROW_SPAWNED" -eq 0 ] && [ ! -f "$CAPTURE" ]; then
  broken "the child was spawned with no --append-system-prompt argument; this fixture is reading the wrong shape"
fi
ROW_CANARY=1
if canary_in_prompt; then ROW_CANARY=0; fi

decide "$ROW_RC" "$ROW_SPAWNED" "$ROW_CANARY"
VERDICT_EXIT=$?

if [ "$VERDICT_EXIT" -eq 0 ]; then
  echo "F-e BYPASS FIXTURE: GREEN"
  exit 0
fi
echo "F-e BYPASS FIXTURE: RED"
exit 1
