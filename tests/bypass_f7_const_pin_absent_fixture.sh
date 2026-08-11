#!/usr/bin/env bash
# F7 -- a manifest that pins nothing passes the constitution-hash gate in
# silence, and the receipt then records the digest as if it had been pinned.
#
# THE SUBJECT is scripts/launch_checks.py:60-65, the whole of check_hash:
#
#     actual   = sha256(open(const_path).read())
#     expected = json.load(open(manifest_path)).get("constitution_hash_expected", "")
#     if expected and expected != actual:
#         _stop(...)
#     print(actual)
#
# `if expected and ...`. The gate compares only when the manifest volunteers
# something to compare against. A manifest with the field absent, or present
# and empty, reaches `print(actual)` -- exit 0, digest on stdout, no line on
# stderr -- and is indistinguishable at every observation point from a manifest
# whose pin MATCHED.
#
# WHY THE SILENCE IS THE DEFECT AND NOT THE PASS. launch_worker.sh:189 takes
# that stdout as CHASH and :379 hands it to the receipt writer as
# CONSTITUTION_HASH, where it is written as the receipt's `constitution_hash`
# (scripts/write_receipt.py:135). CLAUDE.md states the pack's contract as
# "CONSTITUTION.md is injected verbatim into every worker run and its sha256 is
# pinned into every receipt" -- but a digest of the bytes that were read is not
# a pin. It is the same self-report whatever the bytes are: edit the
# constitution, and the receipt records the digest of the edited file with no
# gate having said anything. The pin only exists while the manifest happens to
# carry the field, and the manifest is config the operator copies and edits
# freely (templates/manifest.example.json:4).
#
# The docstring one screen above the code says the opposite of what the code
# does -- :15-18: "Pin the constitution sha256 against
# manifest.constitution_hash_expected, fail-closed." Fail-closed with an absent
# input is a STOP, not a print.
#
# THE CONTROLS are the two cases the field IS present for: a wrong pin must
# STOP, a right pin must pass. They run first. If they did not both hold, this
# fixture would be watching a gate that is broken in some other way and its red
# would be evidence of nothing. They also give the row its shape: the gate
# discriminates perfectly WHEN it is armed, and arming it is optional.
#
# Every arm runs the real scripts/launch_checks.py over files fabricated under
# $TMPDIR. The pack's own CONSTITUTION.md is never read, and nothing is written
# outside the scratch dir.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
CHECKS="$PACK/scripts/launch_checks.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-f7.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$CHECKS" ] || broken "scripts/launch_checks.py is not where this fixture expects it"

CONST="$WORK/CONSTITUTION.md"
printf 'governance body, pinned bytes\n' > "$CONST" || broken "could not write the fixture constitution"
ACTUAL="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$CONST")"
[ -n "$ACTUAL" ] || broken "could not compute the fixture constitution digest"

manifest() { printf '%s\n' "$2" > "$WORK/$1.json"; }
manifest absent  '{"manifest_version": 1}'
manifest empty   '{"manifest_version": 1, "constitution_hash_expected": ""}'
manifest wrong   '{"manifest_version": 1, "constitution_hash_expected": "0000000000000000000000000000000000000000000000000000000000000000"}'
manifest right   "{\"manifest_version\": 1, \"constitution_hash_expected\": \"$ACTUAL\"}"

# run <name> -> sets RC, OUT, ERR for that manifest
run() {
  OUT="$(python3 "$CHECKS" check-hash "$CONST" "$WORK/$1.json" 2>"$WORK/err")"
  RC=$?
  ERR="$(head -1 "$WORK/err" 2>/dev/null)"
}

echo "== F7 the constitution pin is optional, and its absence is silent =="

# ---- controls: the gate discriminates when it is armed ----------------------
run wrong
[ "$RC" -ne 0 ] || broken "a WRONG pin did not STOP (rc=$RC); the gate is broken in some other way and nothing below is measurable"
case "$ERR" in
  *CONST-HASH-MISMATCH*) : ;;
  *) broken "a wrong pin stopped without naming CONST-HASH-MISMATCH: $ERR" ;;
esac
WRONG_RC="$RC"
run right
[ "$RC" -eq 0 ] && [ "$OUT" = "$ACTUAL" ] \
  || broken "a MATCHING pin did not pass (rc=$RC out=${OUT:0:12}); nothing below is measurable"
RIGHT_RC="$RC"
RIGHT_OUT="$OUT"
note "control: wrong pin -> rc=$WRONG_RC STOP CONST-HASH-MISMATCH; matching pin -> rc=$RIGHT_RC, digest echoed"

# ---- the rows: the field absent, and the field empty ------------------------
run absent
ABSENT_RC="$RC"; ABSENT_OUT="$OUT"; ABSENT_ERR="$ERR"
run empty
EMPTY_RC="$RC"; EMPTY_OUT="$OUT"

if [ "$ABSENT_RC" -eq 0 ] || [ "$EMPTY_RC" -eq 0 ]; then
  echo "RED [F7] a manifest that pins nothing passes, and says nothing"
  note "field absent  -> rc=$ABSENT_RC  stdout=${ABSENT_OUT:0:16}...  stderr='${ABSENT_ERR}'"
  note "field empty   -> rc=$EMPTY_RC  stdout=${EMPTY_OUT:0:16}...";
  note "matching pin  -> rc=$RIGHT_RC  stdout=${RIGHT_OUT:0:16}...  (the control)"
  note "the unpinned runs and the pinned one are identical at every observation"
  note "point a caller has: exit code, stdout, stderr. launch_worker.sh:189 reads"
  note "that stdout as CHASH and :379 hands it to the receipt writer, which"
  note "records it as the receipt's constitution_hash (write_receipt.py:135)"
  note "so the receipt reports a pin for a run in which nothing was pinned, and"
  note "the digest it reports is of whatever bytes were there at read time"
  note "launch_checks.py:15-18 states this gate as 'fail-closed'; :63's"
  note "\`if expected and ...\` makes it fail-open on an absent input"
  note "green when an absent or empty constitution_hash_expected is a STOP"
  echo "F7 BYPASS FIXTURE: RED"
  exit 1
fi

echo "GREEN [F7] a manifest that pins nothing is refused"
note "field absent -> rc=$ABSENT_RC, field empty -> rc=$EMPTY_RC, matching pin -> rc=$RIGHT_RC"
echo "F7 BYPASS FIXTURE: GREEN"
exit 0
