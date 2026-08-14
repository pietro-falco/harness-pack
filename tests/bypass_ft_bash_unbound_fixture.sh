#!/usr/bin/env bash
# FT-4 -- a spec declaring `Bash` buys an unbounded run whatever the tool bound
# says, because no layer in this pack holds a predicate over the write target.
#
# THIS ROW IS RED, AND IT STAYS RED UNDER ADR-022 BY DESIGN. It is the only row
# of ADR-022's four that its own ADR does not undertake to close: D5 names it
# "the residue", says it "is untouched and stays ADR-011's", and says of ADR-022
# in as many words that it "retires the allowlist as an excuse, nothing more".
# A register in which every row goes green on the commit that writes it is a
# register recording an intention. This row is here so that the thing ADR-022
# does NOT buy is measured on every run, at the same cost as the things it does.
#
# WHAT D1 BUYS AND WHERE IT STOPS. ADR-022 D1 makes `spec.tools` a real bound:
# a tool absent from the list is absent from the child's surface. The Mode B
# template's own default list is `Read, Bash, Grep, Glob`
# (templates/spec.mode-b.template.md:9-13), so the modal spec is bounded in its
# built-in surface and unbounded in what a bounded tool reaches. ADR-022's
# Consequences states the same thing from the other side: "D1 buys a real
# narrowing for a spec that omits `Bash`, and a nominal one for the modal spec
# that does not."
#
# THIS ROW IS NOT A SECOND COPY OF F-c, AND MUST NOT BE CLOSEABLE BY ONE.
# `tests/bypass_fc_scope_unread_fixture.sh` has been GREEN since c846887, which
# put a gate at scripts/launch_worker.sh:176-183 refusing a spec.scope that is
# missing, empty, or not repo-relative. That gate validates the SHAPE of a
# declaration. This row measures whether the declaration is CARRIED ANYWHERE
# AFTERWARDS and whether any layer acts on it, and control 5 runs F-c's own
# subject to show the shape gate live and firing while all four obligations
# below remain unheld. Repairing shape validation harder cannot close this row,
# and that is deliberate.
#
# THE FOUR OBLIGATIONS, in the order ADR-022's register states them:
#
#   A  the decision line at :184 emits scope       -- it emits six fields and
#                                                     scope is not among them
#   B  the read at :192 takes it                   -- it reads six and scope is
#                                                     not among them
#   C  guard_pretooluse.py holds a predicate       -- the guard returns 0 for
#      over the write target                          every non-Bash tool at
#                                                     :83-84 and matches sixteen
#                                                     command spellings at
#                                                     :30-46, none of which say
#                                                     anything about WHERE a
#                                                     write lands
#   D  settings.mode-b.json names the field        -- it carries deny rules and
#                                                     a hook, and no path
#                                                     predicate at all
#
# Obligation C is measured TWICE and both are required: the field is unread in
# the source, and the guard is handed an actual out-of-scope write and permits
# it. A source-level absence alone would be a grep asserting a negative, and a
# behavioural permit alone would not say the field is the thing missing. Each
# obligation carries a POSITIVE CONTROL -- the same instrument pointed at a
# field the same file demonstrably does read -- because a pattern that finds
# nothing proves nothing until it has been shown to find something. F9 went
# green on a workflow that never mentions verity because `severity` contains
# it, and `scoped` at launch_worker.sh:350 contains `scope`.
#
# THE GREEN BRANCH IS REACHABLE AND IT FIRES. Control 6 builds a FABRICATED
# quartet -- a launcher copy that emits and reads scope, a guard that refuses a
# write outside it, a settings file that names it -- and drives the same
# decide() over those paths, which must come back GREEN. It is the minimum
# shape this row would accept, built here only to be killed by; nothing
# proposes it, no ADR decides it, and scripts/ and templates/ are untouched.
# Without it this row could only ever say RED, and a row with one reachable
# verdict is not a measurement.
#
# Exit codes: 0 the invariant holds, 1 red, 2 the fixture could not set up.
# Scratch is templated under $TMPDIR and removed on every exit path. Nothing
# absolute is printed.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$PACK/scripts/launch_worker.sh"
GUARD="$PACK/scripts/guard_pretooluse.py"
SETTINGS="$PACK/templates/settings.mode-b.json"
TEMPLATE="$PACK/templates/spec.mode-b.template.md"
MANIFEST="$PACK/templates/manifest.example.json"

# The declared perimeter every case in this fixture uses, and a write target
# plainly outside it. The command is inert -- nothing in this fixture executes
# it, the guard only ever inspects the JSON that describes it -- and it is
# chosen to match NONE of the sixteen destructive spellings at :30-46, so a
# block would mean the guard judged the TARGET and not the verb.
DECLARED_SCOPE='src/'
OUTSIDE_WRITE='printf %s pwned > ../../etc/harness_probe.txt'
INSIDE_WRITE='printf %s ok > src/note.txt'

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$LAUNCHER" ] || broken "scripts/launch_worker.sh is not where this fixture expects it"
[ -f "$GUARD" ]    || broken "scripts/guard_pretooluse.py is not where this fixture expects it"
[ -f "$SETTINGS" ] || broken "templates/settings.mode-b.json is not where this fixture expects it"
[ -f "$TEMPLATE" ] || broken "templates/spec.mode-b.template.md is not where this fixture expects it"
[ -f "$MANIFEST" ] || broken "templates/manifest.example.json is not where this fixture expects it"
command -v node    >/dev/null 2>&1 || broken "node is not available; the launcher invokes 'node \$HW_CLI next --json'"
command -v git     >/dev/null 2>&1 || broken "git is not available"
command -v python3 >/dev/null 2>&1 || broken "python3 is not available"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-ft4.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

redact() { sed -e "s#$WORK#<scratch>#g" -e "s#$PACK#<pack>#g" "$1" | head -1; }

# ---- the instruments -------------------------------------------------------
# emits_field <field> <launcher> -- does the decision line that hands the
# resolved plan back to the shell carry this field? The line is located by its
# own literal opening, never by line number, so drift renames nothing silently.
emits_field() {
  FF_NAME="$1" FF_FILE="$2" python3 <<'PYEOF'
import os, sys
name = os.environ["FF_NAME"]
hits = [l for l in open(os.environ["FF_FILE"]) if l.lstrip().startswith('print("OK"')]
if len(hits) != 1:
    sys.stderr.write("decision line matched %d time(s)\n" % len(hits))
    sys.exit(3)
sys.stdout.write("yes" if name in hits[0] else "no")
PYEOF
}

# takes_field <field> <launcher> -- does the shell-side read of that decision
# line bind a variable for this field? Case-insensitive, because the shell side
# spells the same fields in upper case.
takes_field() {
  FF_NAME="$1" FF_FILE="$2" python3 <<'PYEOF'
import os, sys
name = os.environ["FF_NAME"].lower()
hits = [l for l in open(os.environ["FF_FILE"]) if l.startswith("read -r RESOLVED_ID")]
if len(hits) != 1:
    sys.stderr.write("read line matched %d time(s)\n" % len(hits))
    sys.exit(3)
sys.stdout.write("yes" if name in hits[0].lower() else "no")
PYEOF
}

# fieldreads NAME FILE -- lines that READ a key of that name: an attribute
# access, a subscript, or a .get(), i.e. the key as a literal. The same
# instrument F-c uses, and for the same reason: not the bare substring, so
# `scoped` does not count, and not a bare word either, so `gate scope` in a
# comment reads nothing.
Q="[\"']"
fieldreads() {
  grep -rhE -- "\\.${1}\\b|\\[${Q}${1}${Q}\\]|get\\(${Q}${1}${Q}|\\b${1}=" "$2" 2>/dev/null | wc -l | tr -d ' '
}
# mentions NAME FILE -- word-anchored occurrences, prose included. A second
# number answering a second question, never a substitute for the first.
mentions() { grep -rhE -- "\\b${1}\\b" "$2" 2>/dev/null | wc -l | tr -d ' '; }

# A directory with no .harness/HALT at or above it, so the guard's kill-switch
# is not what answers the probes below.
CLEAN="$WORK/clean"
mkdir -p "$CLEAN" || broken "could not create the clean probe dir"
if [ -e "$CLEAN/.harness/HALT" ]; then broken "the clean probe dir is not clean"; fi

# ask <guard> <payload> -- the guard's own contract: hook JSON on stdin, exit 0
# allow, exit 2 block. Prints the exit code.
ask() {
  printf '%s' "$2" | ( cd "$CLEAN" && CLAUDE_PROJECT_DIR="" python3 "$1" ) >/dev/null 2>&1
  echo $?
}
# bash_payload <command> -- a PreToolUse payload for a Bash write.
bash_payload() {
  PL_CMD="$1" python3 <<'PYEOF'
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["PL_CMD"]}}))
PYEOF
}

echo "== FT-4 a spec declaring Bash buys an unbounded run, whatever the tool bound says =="

# ---- control 1: the field is declared, and declared REQUIRED ----------------
# An obligation withdrawn is an operator decision, not a repair, so the
# template no longer declaring scope is exit 2 and never a pass.
grep -Fq 'REQUIRED (mode B): non-empty; repo-relative prefixes, no leading / or ..' "$TEMPLATE" \
  || broken "templates/spec.mode-b.template.md no longer declares scope REQUIRED with that shape; the declaration this row measures has been withdrawn, which is an operator decision and not a repair"
note "control 1: the template still declares scope REQUIRED in mode B, as a non-empty list of repo-relative prefixes"

# ---- control 2: `Bash` is in the template's default tool list ---------------
# This is what makes the row modal rather than contrived: the spec a reader
# builds from the shipped template declares Bash without deciding to.
TPL_BASH="$(sed -n '/^tools:/,/^budget:/p' "$TEMPLATE" | grep -c -- '- Bash')"
[ "$TPL_BASH" -ge 1 ] \
  || broken "templates/spec.mode-b.template.md:9-13 no longer lists Bash among the default tools; this row's claim that the MODAL spec is unbounded no longer follows from the template, and ADR-022's Consequences would need rereading"
note "control 2: the Mode B template's default tool list still contains Bash, so the modal spec is the one this row is about"

# ---- control 3: the positive controls, one per instrument -------------------
# A pattern that finds nothing proves nothing until it has been shown to find
# something. Each instrument is pointed first at a field the same file
# demonstrably carries.
EMITS_TOOLS="$(emits_field tools "$LAUNCHER")" || broken "the decision line at :184 could not be located in scripts/launch_worker.sh; this fixture is reading a shape that has moved"
TAKES_TOOLS="$(takes_field TOOLS "$LAUNCHER")" || broken "the read at :192 could not be located in scripts/launch_worker.sh; this fixture is reading a shape that has moved"
GUARD_CMD_READS="$(fieldreads command "$GUARD")"
SET_PERMS="$(mentions permissions "$SETTINGS")"
[ "$EMITS_TOOLS" = "yes" ] \
  || broken "the emission instrument does not find 'tools' on the decision line the launcher demonstrably emits it on; the instrument is broken, not the tree"
[ "$TAKES_TOOLS" = "yes" ] \
  || broken "the read instrument does not find TOOLS on the read line the launcher demonstrably binds it on; the instrument is broken, not the tree"
[ "$GUARD_CMD_READS" -gt 0 ] \
  || broken "the field-read pattern found 0 reads of 'command' in the guard, which demonstrably reads it at :84; the instrument is broken, not the tree"
[ "$SET_PERMS" -gt 0 ] \
  || broken "the mention pattern found 0 occurrences of 'permissions' in settings.mode-b.json, which demonstrably carries that key; the instrument is broken, not the tree"
note "control 3: every instrument finds its positive control -- emits(tools)=$EMITS_TOOLS, takes(TOOLS)=$TAKES_TOOLS, guard field-reads of 'command'=$GUARD_CMD_READS, settings mentions of 'permissions'=$SET_PERMS"

# ---- control 4: the guard is live, and it does block things -----------------
# "The guard permitted the out-of-scope write" is worth nothing against a guard
# that permits everything. One of the sixteen spellings at :30-46, in the same
# probe harness, must be blocked.
GUARD_DENY_RC="$(ask "$GUARD" "$(bash_payload 'rm -rf src/')")"
[ "$GUARD_DENY_RC" = "2" ] \
  || broken "the guard did not block a destructive spelling it demonstrably denies (rc=$GUARD_DENY_RC); this guard is not enforcing anything, so the permits below would measure nothing"
note "control 4: the guard still BLOCKS a destructive verb (rc=$GUARD_DENY_RC), so a permit below is a judgment and not an absence of judgment"

# ---- control 5: F-c's gate is live, and this row is not closeable by it -----
# The shape gate at :176-183 refuses a scope that is absent, empty or not
# repo-relative, and F-c has been GREEN on it since c846887. It runs here so
# that this row's four obligations are read against a tree in which shape
# validation demonstrably works.
REPO="$WORK/repo"
mkdir -p "$REPO/.harness/specs" || broken "could not create the throwaway repo dir"
git -C "$REPO" init -q || broken "could not init the throwaway repo"
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" config user.name tester
git -C "$REPO" config commit.gpgsign false
git -C "$REPO" config tag.gpgsign false
: > "$REPO/keep"
git -C "$REPO" add -- keep >/dev/null 2>&1 || broken "could not stage the seed file"
git -C "$REPO" commit -q -m "fixture: seed commit" >/dev/null 2>&1 || broken "could not seed the throwaway repo"
SLICE="S-ft4"
SPEC="$REPO/.harness/specs/$SLICE.md"
printf '%s\n' "fixture spec body; the launcher never parses it (ADR-005 D1)" > "$SPEC"
HW="$WORK/fake_next.js"
cat > "$HW" <<'JSEOF'
if (process.argv[2] !== "next") {
  process.stderr.write("fake next: unexpected subcommand " + process.argv[2] + "\n");
  process.exit(9);
}
process.stdout.write(process.env.FIXTURE_NEXT_JSON || "");
JSEOF
VER="$WORK/fake_verity.js"
: > "$VER"
DRY_ERR="$WORK/dry.err"
dry() {
  ( cd "$REPO" && \
    FIXTURE_NEXT_JSON="$1" \
    HARNESSWRIGHT_CLI="$HW" \
    VERITY_CLI="$VER" \
    HARNESS_MANIFEST="$MANIFEST" \
    LAUNCH_DRYRUN=1 \
    bash "$LAUNCHER" "$SPEC" ) >"$WORK/dry.out" 2>"$DRY_ERR"
  echo $?
}
next_json() {
  printf '{"kind":"unlocked","id":"%s","eligible_mode_b":true,"spec":{"model":"worker","budget":{"turns":10},"tools":["Bash"],"criteria":["fixture-claim"]%s}}' \
    "$SLICE" "$1"
}
SHAPE_RC="$(dry "$(next_json ', "scope": ["/etc", "../../.ssh"]')")"
SHAPE_MSG="$(redact "$DRY_ERR")"
[ "$SHAPE_RC" != "0" ] \
  || broken "a scope of [/etc, ../../.ssh] reached the decision line (rc=$SHAPE_RC); the shape gate at :176-183 is not firing, which is F-c's row and not this one, and this fixture will not report on a tree where that has regressed"
LEGAL_RC="$(dry "$(next_json ", \"scope\": [\"$DECLARED_SCOPE\"]")")"
[ "$LEGAL_RC" = "0" ] \
  || broken "a legal scope did not reach the decision line (rc=$LEGAL_RC); the launcher refuses everything and nothing below can be attributed: $(redact "$DRY_ERR")"
note "control 5: the shape gate is LIVE -- scope [/etc, ../../.ssh] is refused (rc=$SHAPE_RC), a legal scope reaches the decision line (rc=$LEGAL_RC)"
note "            $SHAPE_MSG"
note "            so the four obligations below are read against a tree in which shape validation demonstrably works, and no repair to it can close this row"

# ---- decide ----------------------------------------------------------------
# decide <launcher> <guard> <settings> -- the four obligations, one verdict.
# Prints the verdict block on stdout; returns 0 GREEN, 1 RED. The row and
# control 6's fabricated quartet go through this one function: a control
# exercising a private copy would prove nothing about the row.
HELD=0
UNHELD=""
decide() {
  local lnch="$1" grd="$2" sett="$3"
  local a b c_src c_beh d rc_out rc_in
  HELD=0
  UNHELD=""
  a="$(emits_field scope "$lnch")" || { echo "RED [FT-4] the decision line could not be located"; return 1; }
  b="$(takes_field scope "$lnch")" || { echo "RED [FT-4] the read line could not be located"; return 1; }
  c_src="$(fieldreads scope "$grd")"
  d="$(mentions scope "$sett")"
  rc_out="$(ask "$grd" "$(bash_payload "$OUTSIDE_WRITE")")"
  rc_in="$(ask "$grd" "$(bash_payload "$INSIDE_WRITE")")"
  c_beh="no"
  # The predicate is over the TARGET, so it must separate the two writes: a
  # guard that blocked both would be refusing Bash, not bounding it.
  if [ "$rc_out" = "2" ] && [ "$rc_in" = "0" ]; then c_beh="yes"; fi

  if [ "$a" = "yes" ]; then HELD=$((HELD + 1)); else UNHELD="${UNHELD:+$UNHELD, }A/emitted"; fi
  if [ "$b" = "yes" ]; then HELD=$((HELD + 1)); else UNHELD="${UNHELD:+$UNHELD, }B/read"; fi
  if [ "$c_src" -gt 0 ] && [ "$c_beh" = "yes" ]; then HELD=$((HELD + 1)); else UNHELD="${UNHELD:+$UNHELD, }C/guard"; fi
  if [ "$d" -gt 0 ]; then HELD=$((HELD + 1)); else UNHELD="${UNHELD:+$UNHELD, }D/settings"; fi

  if [ "$HELD" = "4" ]; then
    echo "GREEN [FT-4] the declared write perimeter is carried and enforced: all four layers hold a predicate over the write target"
  elif [ "$HELD" = "0" ]; then
    echo "RED [FT-4] a spec declaring Bash buys an unbounded run: no layer holds a predicate over the write target"
  else
    echo "RED [FT-4] PARTIAL: $HELD of 4 layers carry the perimeter, still unheld: $UNHELD"
  fi
  note "$(printf '%-42s: %s' "A  decision line emits scope" "$a")"
  note "$(printf '%-42s: %s' "B  shell read binds it" "$b")"
  note "$(printf '%-42s: %s' "C  guard field-reads of 'scope'" "$c_src (word-anchored mentions: $(mentions scope "$grd"))")"
  note "$(printf '%-42s: %s' "C  guard on a write OUTSIDE the perimeter" "rc=$rc_out $(if [ "$rc_out" = "2" ]; then printf 'BLOCKED'; else printf 'PERMITTED'; fi)")"
  note "$(printf '%-42s: %s' "C  guard on a write INSIDE the perimeter" "rc=$rc_in $(if [ "$rc_in" = "2" ]; then printf 'BLOCKED'; else printf 'PERMITTED'; fi)")"
  note "$(printf '%-42s: %s' "D  settings.mode-b.json names scope" "$d occurrence(s)")"
  [ "$HELD" = "4" ] && return 0
  return 1
}

# ---- control 6: the green branch is reachable, and it fires -----------------
# A FABRICATED quartet, and nothing else in this fixture runs against it. It is
# the minimum shape this row would accept -- carry the declared perimeter down
# the same path the other fields travel, and give the guard a predicate over
# the target -- built here only so decide()'s green arm executes. Nothing
# proposes it, no ADR decides it, and scripts/ and templates/ are untouched.
FAB="$WORK/fabricated"
mkdir -p "$FAB" || broken "could not create the fabricated quartet dir"
FAB_LAUNCHER="$FAB/launch_worker.sh"
# The fabrication appends a field to each of the two lines rather than matching
# their full field lists as literals. The field lists are exactly what other
# decisions add to -- ADR-022 D2 added one to both -- so a literal match would
# make this control break on any unrelated field, and a control that breaks
# whenever the launcher gains a field is a control nobody can keep.
SRC_FILE="$LAUNCHER" OUT_FILE="$FAB_LAUNCHER" python3 <<'PYEOF' || broken "could not fabricate the launcher copy for control 6"
import os, sys
lines = open(os.environ["SRC_FILE"]).read().splitlines(True)
out, p_hits, r_hits = [], 0, 0
for line in lines:
    if line.lstrip().startswith('print("OK"'):
        body = line.rstrip("\n")
        close = body.rfind(")")
        if close == -1:
            sys.stderr.write("the decision line has no closing paren\n")
            sys.exit(3)
        line = body[:close] + ', ",".join(scope)' + body[close:] + "\n"
        p_hits += 1
    elif line.startswith("read -r RESOLVED_ID"):
        if " <<<" not in line:
            sys.stderr.write("the read line has no here-string\n")
            sys.exit(3)
        line = line.replace(" <<<", " SCOPE <<<", 1)
        r_hits += 1
    out.append(line)
if p_hits != 1 or r_hits != 1:
    sys.stderr.write("decision line matched %d, read line matched %d\n" % (p_hits, r_hits))
    sys.exit(3)
open(os.environ["OUT_FILE"], "w").write("".join(out))
PYEOF
FAB_GUARD="$FAB/guard_pretooluse.py"
cat > "$FAB_GUARD" <<'PYEOF'
#!/usr/bin/env python3
"""Fabricated stand-in for control 6 ONLY. Not a proposal; no ADR decides it.

The minimum shape FT-4 would accept from the guard: a predicate over the write
target, read off a declared perimeter rather than off the command's verb.
"""
import json
import re
import sys

def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 2
    if payload.get("tool_name") != "Bash":
        return 0
    cmd = payload.get("tool_input", {}).get("command", "")
    scope = payload.get("scope") or ["src/"]
    targets = re.findall(r">>?\s*(\S+)", cmd)
    for t in targets:
        if not any(t.startswith(p) for p in scope):
            print(f"G3-BLOCKED: write target {t} is outside the declared scope "
                  f"{scope}.", file=sys.stderr)
            return 2
    return 0

sys.exit(main())
PYEOF
FAB_SETTINGS="$FAB/settings.mode-b.json"
SRC_FILE="$SETTINGS" OUT_FILE="$FAB_SETTINGS" python3 <<'PYEOF' || broken "could not fabricate the settings copy for control 6"
import json, os
s = json.load(open(os.environ["SRC_FILE"]))
s["permissions"]["scope"] = ["src/"]
json.dump(s, open(os.environ["OUT_FILE"], "w"), indent=2)
PYEOF

CTL6_BLOCK="$(decide "$FAB_LAUNCHER" "$FAB_GUARD" "$FAB_SETTINGS")"
CTL6_EXIT=$?
[ "$CTL6_EXIT" -eq 0 ] \
  || broken "the fabricated quartet -- a launcher that emits and reads scope, a guard with a predicate over the target, a settings file naming the field -- did not produce a GREEN verdict (verdict exit=$CTL6_EXIT); the green branch is written but not wired, and this row could only ever say RED"
note "control 6: against a fabricated quartet carrying the perimeter end to end, the same decide() returns GREEN (exit=$CTL6_EXIT)"
printf '%s\n' "$CTL6_BLOCK" | sed 's/^/     control 6 > /'

# ---- the row ---------------------------------------------------------------
decide "$LAUNCHER" "$GUARD" "$SETTINGS"
VERDICT_EXIT=$?

if [ "$VERDICT_EXIT" -eq 0 ]; then
  echo "FT-4 BYPASS FIXTURE: GREEN"
  exit 0
fi
note "the spec's scope is validated in SHAPE at :176-183 and then dropped: the"
note "decision line emits six fields and scope is not among them, the read binds"
note "six and scope is not among them, and neither permission layer is ever"
note "handed the list"
note "so a spec declaring tools: [Bash] is bounded by ADR-022 D1 to one built-in"
note "and unbounded in what that built-in reaches -- and Bash is in the Mode B"
note "template's own default list, which is what makes this the modal spec and"
note "not a contrived one"
note "THIS ROW IS EXPECTED RED. ADR-022 D5 declares it the residue and does not"
note "undertake to close it: 'this ADR retires the allowlist as an excuse,"
note "nothing more'. Its green requires a decision nobody has taken -- carrying"
note "the perimeter to a layer that can act on it -- and until that decision"
note "exists, this row is the standing measurement of what the tool bound does"
note "not buy"
echo "FT-4 BYPASS FIXTURE: RED"
exit 1
