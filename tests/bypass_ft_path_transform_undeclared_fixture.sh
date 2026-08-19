#!/usr/bin/env bash
# path-transform-undeclared -- a re-pinned blob is evidence of a declared
# transformation only when the rule that produced it sits alongside the
# re-pin and its digest matches. scripts/path_transform_verify.py
# (path-transform/v1) is the subject: given evidence whose paths are already
# substituted -- bytes that read as clean -- but with no rule file present,
# or a rule file whose sha256 does not match what the record declares, the
# verifier MUST refuse (nonzero), never treat clean-looking bytes as proof.
#
# THREE ARMS, one script, one working tree per arm:
#   A. rule file absent entirely       -> want exit 2 (UNDECLARED)
#   B. rule file present, wrong sha256 -> want exit 3 (RULE-DRIFT)
#   C. rule file present, matches      -> want exit 0 (DECLARED) -- the
#      positive control: without it, arms A/B could pass for a verifier that
#      always exits nonzero regardless of what it was given.
#
# STATES. RED (exit 1): any arm's exit code does not match what it wants --
# the verifier either accepted an undeclared transformation or refused a
# genuinely declared one. GREEN (exit 0): all three arms match.
set -u

VERIFY="${PATH_TRANSFORM_VERIFY:-$(cd "$(dirname "$0")/.." && pwd)/scripts/path_transform_verify.py}"
if ! command -v python3 >/dev/null 2>&1; then
  echo "UNMEASURED: python3 absent" >&2
  exit 2
fi
if [ ! -f "$VERIFY" ]; then
  echo "UNMEASURED: verifier not found at $VERIFY" >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft_pt.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/repo/evidence"
ORIGINAL_BYTES="the executing session's cwd was <LOCAL_ROOT>/Code/harness-pack"
printf '%s\n' "$ORIGINAL_BYTES" > "$WORK/repo/evidence/sample.txt"
NEW_SHA="$(python3 -c "
import hashlib
data = open('$WORK/repo/evidence/sample.txt', 'rb').read()
print(hashlib.sha1(('blob %d\0' % len(data)).encode() + data).hexdigest())
")"

mkdir -p "$WORK/repo/scripts"
RULE_JSON='{"id":"path-transform/v1","mechanism":"literal-substring-replace","pattern":"/Users/nobody","replacement":"<LOCAL_ROOT>"}'
printf '%s' "$RULE_JSON" > "$WORK/repo/scripts/path_transform_rule_v1.json"
TRUE_RULE_SHA="$(python3 -c "
import hashlib
print(hashlib.sha256(open('$WORK/repo/scripts/path_transform_rule_v1.json','rb').read()).hexdigest())
")"

cat > "$WORK/record.json" <<JSON
{
  "rule": {"id": "path-transform/v1", "sha256": "$TRUE_RULE_SHA"},
  "entries": [
    {"path": "evidence/sample.txt", "originalSha": "0000000000000000000000000000000000000000", "newSha": "$NEW_SHA"}
  ]
}
JSON

fail=0

# Arm A: rule file absent.
mv "$WORK/repo/scripts/path_transform_rule_v1.json" "$WORK/rule.aside"
python3 "$VERIFY" "$WORK/record.json" --repo-root "$WORK/repo" >"$WORK/out.a" 2>&1
rc_a=$?
if [ "$rc_a" -ne 2 ]; then
  echo "RED: arm A (rule absent) gave exit $rc_a, want 2 (UNDECLARED)" >&2
  cat "$WORK/out.a" >&2
  fail=1
fi
mv "$WORK/rule.aside" "$WORK/repo/scripts/path_transform_rule_v1.json"

# Arm B: rule file present, digest does not match the record's pin.
printf '%s' '{"id":"path-transform/v1","pattern":"/Users/someone-else"}' \
  > "$WORK/repo/scripts/path_transform_rule_v1.json"
python3 "$VERIFY" "$WORK/record.json" --repo-root "$WORK/repo" >"$WORK/out.b" 2>&1
rc_b=$?
if [ "$rc_b" -ne 3 ]; then
  echo "RED: arm B (rule digest mismatch) gave exit $rc_b, want 3 (RULE-DRIFT)" >&2
  cat "$WORK/out.b" >&2
  fail=1
fi

# Arm C: positive control -- rule restored to the one the record actually pins.
printf '%s' "$RULE_JSON" > "$WORK/repo/scripts/path_transform_rule_v1.json"
python3 "$VERIFY" "$WORK/record.json" --repo-root "$WORK/repo" >"$WORK/out.c" 2>&1
rc_c=$?
if [ "$rc_c" -ne 0 ]; then
  echo "RED: arm C (positive control, rule matches) gave exit $rc_c, want 0 (DECLARED)" >&2
  cat "$WORK/out.c" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "GREEN: undeclared (2), rule-drift (3), and declared (0) all separated correctly"
exit 0
