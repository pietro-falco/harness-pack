#!/usr/bin/env bash
# F-d -- the declared scope binds no write, and this row has to be DIFFERENTIAL
# or it accuses a defect two other rows already accuse.
#
# THIS ROW STANDS RED. templates/spec.mode-b.template.md:21-22 declares `scope`
# REQUIRED with a stated shape; c846887 made the launcher refuse a malformed one
# before spawn (that is F-c, and it is GREEN). Nothing anywhere reads the value
# of a WELL-FORMED scope to decide whether a write may happen.
#
# WHY DIFFERENTIAL, AND WHY THAT IS THE WHOLE DESIGN OF THIS ROW.
# Two rows already accuse the guard over a Write:
#
#   F2  measures the guard's tool filter on its own, and goes GREEN when
#       Write/Edit inputs are read at all.
#   F6  measures the composition of the three permission layers, and its own
#       header says it goes GREEN on EITHER repair.
#
# A hard-coded deny-list of governance paths in the guard flips BOTH of them,
# and leaves `scope` exactly as unread as it is today. A third row asking "is
# this Write refused?" would therefore be a third falsifier for a defect already
# covered twice -- the accumulation ADR-017 exists to make expensive.
#
# So this row does not ask whether a write is refused. It asks whether the SAME
# payload gets DIFFERENT verdicts under DIFFERENT declared scopes:
#
#   arm DENY    scope=src/    Write -> docs/probe.md    must be refused (rc 2)
#   arm ALLOW   scope=docs/   Write -> docs/probe.md    must be allowed (rc 0)
#
# One payload, two declarations, two verdicts. A hard-coded rule answers both
# arms the same way and leaves this row RED under a distinct message. The ALLOW
# arm is not politeness: a guard that refuses every write is bounded exactly as
# little as one that refuses none, and both are useless to a Mode B run.
#
# RELATION TO F-c, which is the pair this row completes. F-c measures the
# REFUSAL of a malformed scope, in the launcher, and is GREEN. This row measures
# the GRANTING AWAY of a well-formed one, and is RED. F2 and F6 are expected to
# stay RED after this row goes GREEN: differential binding is not a governance
# deny-list, and neither implies the other. If a repair flips all four, the
# repair was wider than any of the four rows described, and that is a finding.
#
# THE SEAM. The guard is a PreToolUse hook; its payload carries no path to the
# slice's spec and no slice id (measured 2026-08-13 on claude 2.1.229 against a
# real child), so the declared scope cannot arrive in the payload. A hook
# process inherits the environment of whatever launched `claude` -- measured the
# same day, same way -- so this row hands the scope to the guard in
# HARNESS_SCOPE, comma-separated repo-relative prefixes, which is the seam
# ADR-021 D2 decides on. A guard that ignores that variable entirely is what
# this row reports today.
#
# THE CONTROLS COME FIRST, and they are about this guard being alive and not
# about scope: it must refuse a Bash deletion by its DENY list (not by HALT,
# which would make every arm rc=2 and the row would measure nothing), and it
# must allow a benign Bash. Without both, the arms below are noise.
#
# Exit codes: 0 green, 1 red, 2 the fixture could not reach its question.
# Every read is in place; the only writes are under $TMPDIR.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$PACK/scripts/guard_pretooluse.py"
TEMPLATE="$PACK/templates/spec.mode-b.template.md"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-fd.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }
scrub() { sed -e "s#$WORK#<scratch>#g" -e "s#$PACK#<pack>#g"; }

[ -f "$GUARD" ]    || broken "scripts/guard_pretooluse.py is not where this fixture expects it"
[ -f "$TEMPLATE" ] || broken "templates/spec.mode-b.template.md is not where this fixture expects it"
command -v python3 >/dev/null 2>&1 || broken "python3 is not available"

# The obligation this row is about must still be declared. Withdrawing it is an
# operator decision, recorded as BROKEN, never as a repair. Same clause as F-c.
grep -Fq 'REQUIRED (mode B): non-empty; repo-relative prefixes, no leading / or ..' "$TEMPLATE" \
  || broken "the template no longer declares scope REQUIRED with that shape; the obligation this row measures has moved"

# A throwaway tree with the two prefixes the arms name. .git makes it a repo
# root, which is where the guard's HALT walk stops; no .harness/HALT anywhere,
# so HALT answers nothing here and every rc below is the Bash filter or the
# scope decision, never the kill-switch.
REPO="$WORK/repo"
mkdir -p "$REPO/.git" "$REPO/src" "$REPO/docs" || broken "could not build the throwaway tree"
[ -e "$REPO/.harness/HALT" ] && broken "the throwaway tree is not clean"

ask() {
  printf '%s' "$2" | ( cd "$REPO" && CLAUDE_PROJECT_DIR="" HARNESS_SCOPE="$1" python3 "$GUARD" ) \
    >/dev/null 2>"$WORK/err"
  echo $?
}
write_payload() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","cwd":sys.argv[1],"tool_input":{"file_path":sys.argv[2],"content":"x"}}))' \
    "$REPO" "$1"
}
bash_payload() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' \
    "$REPO" "$1"
}

echo "== F-d one payload, two declared scopes, one verdict =="

# ---- controls ---------------------------------------------------------------
CTL_DENY="$(ask "src/" "$(bash_payload "rm CONSTITUTION.md")")"
CTL_MSG="$(head -1 "$WORK/err" 2>/dev/null | cut -c1-40 | scrub)"
[ "$CTL_DENY" = "2" ] \
  || broken "the guard did not refuse a Bash deletion (rc=$CTL_DENY); it cannot refuse anything here, so nothing below is measurable"
case "$CTL_MSG" in
  G3-BLOCKED*) : ;;
  *) broken "the Bash control was blocked by '$CTL_MSG', not by the DENY list; if HALT is answering, every arm is rc=2 and this row measures nothing" ;;
esac
CTL_ALLOW="$(ask "src/" "$(bash_payload "ls -la")")"
[ "$CTL_ALLOW" = "0" ] \
  || broken "the guard refused a benign Bash (rc=$CTL_ALLOW); it is refusing everything, and a differential row cannot be read against it"
note "control: Bash 'rm' -> rc=$CTL_DENY by the DENY list ($CTL_MSG...); benign Bash -> rc=$CTL_ALLOW"

# ---- the arms ---------------------------------------------------------------
TARGET="$REPO/docs/probe.md"
DENY_RC="$(ask "src/"  "$(write_payload "$TARGET")")"
ALLOW_RC="$(ask "docs/" "$(write_payload "$TARGET")")"

case "$DENY_RC" in 0|2) : ;; *) broken "the deny arm returned rc=$DENY_RC, which is neither allow (0) nor block (2); the guard crashed rather than deciding, and a crash exits non-blocking" ;; esac
case "$ALLOW_RC" in 0|2) : ;; *) broken "the allow arm returned rc=$ALLOW_RC, which is neither allow (0) nor block (2)" ;; esac

if [ "$DENY_RC" = "2" ] && [ "$ALLOW_RC" = "0" ]; then
  echo "GREEN [F-d] the declared scope decides the verdict on one identical payload"
  note "scope=src/  Write docs/probe.md -> rc=$DENY_RC  (refused)"
  note "scope=docs/ Write docs/probe.md -> rc=$ALLOW_RC  (allowed)"
  note "same payload, same guard, different declaration, different verdict"
  echo "F-d BYPASS FIXTURE: GREEN"
  exit 0
fi

if [ "$DENY_RC" = "$ALLOW_RC" ] && [ "$DENY_RC" = "2" ]; then
  echo "RED [F-d] the write is refused regardless of the declared scope"
  note "scope=src/  -> rc=$DENY_RC ; scope=docs/ -> rc=$ALLOW_RC"
  note "a rule that refuses both arms is not a binding on the declared value: it"
  note "is a fixed policy wearing the shape of one. F2 and F6 are satisfied by"
  note "exactly this and are the rows that should carry it, not this one"
  echo "F-d BYPASS FIXTURE: RED"
  exit 1
fi

echo "RED [F-d] a REQUIRED field states where the slice may write and no layer spends it"
note "scope=src/  Write docs/probe.md -> rc=$DENY_RC  (out of the declared scope, allowed)"
note "scope=docs/ Write docs/probe.md -> rc=$ALLOW_RC  (in scope, allowed)"
note "guard_pretooluse.py:83 returns 0 for every tool_name != \"Bash\" before any"
note "input is read; only HALT sits above that line, and HALT is lifted here --"
note "which is the state a run is in while it is running"
note "the same guard refuses 'rm' through Bash (rc=$CTL_DENY), so the zero above is a"
note "decision this guard makes and not an instrument that cannot see the payload"
note "HARNESS_SCOPE carried a different value into each arm and neither answer"
note "moved: the seam ADR-021 D2 names is unread, not merely unwired"
note "green when the two arms diverge -- refused out of scope, allowed in scope --"
note "with the run NOT halted; a rule that refuses both is reported separately above"
echo "F-d BYPASS FIXTURE: RED"
exit 1
