#!/usr/bin/env bash
# FT-31 -- transform-citation-unbound. A record whose evidence bytes moved
# under a DECLARED path transformation cites the transformation rule by id
# and sha256, exactly as it cites comparisonRule, and the verifier
# recomputes THROUGH the rule's inverse. What makes the citation a check
# and not a narration is the binding: the rule the verifier holds must be
# byte-identical to the rule the record cites. A record citing a rule that
# is not present, or whose digest does not match, must never verify.
#
# The verifier resolves its rules beside its own file, so each arm runs a
# COPY of the verifier in a scratch bin directory whose rule files this
# fixture controls; the repository's own rules are never touched.
#
# FOUR ARMS, one green control:
#   A  positive control: evidence transformed on disk, record pins the
#      pre-transform digests and cites the scratch rule   -> want 0
#   B  rule file absent beside the verifier               -> want 2, naming
#      the missing transformation rule
#   C  rule file present, different bytes (same semantics, so a verifier
#      that trusts the citation still inverts correctly)  -> want 2, digest
#      mismatch named
#   D  transformation null, evidence moved anyway         -> want 2, plain
#      digest mismatch (the pre-existing fail-closed refusal)
#
# GREEN: all four arms answer as wanted. RED: B or C reaches 0 -- the
# citation is decoration, not a bound input -- or A refuses a genuinely
# declared transformation. UNMEASURED (2): machinery absent or control
# cannot be built.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="${CONFORMANCE_CORPUS:-$ROOT/tests/fixtures/conformance_corpus.py}"
RECORD="${CONFORMANCE_RECORD:-$ROOT/scripts/conformance_record.py}"
VERIFY="${CONFORMANCE_VERIFY:-$ROOT/scripts/conformance_verify.py}"
ANCHORS="${SCRATCH_LEDGER:-$ROOT/tests/fixtures/scratch_ledger.sh}"
CONF_RULE="$ROOT/scripts/conformance_rule_v1.json"
for f in "$CORPUS" "$RECORD" "$VERIFY" "$ANCHORS" "$CONF_RULE"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft31.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

# The scratch transformation rule this fixture declares. A neutral pattern:
# the repository's real rule names the operator's home prefix, which no
# tracked fixture may carry.
mkdir -p "$WORK/bin"
cp "$VERIFY" "$WORK/bin/conformance_verify.py"
cp "$CONF_RULE" "$WORK/bin/conformance_rule_v1.json"
RULE_JSON='{"id":"path-transform/v1","mechanism":"literal-substring-replace","pattern":"/private/scratch-root","replacement":"<SCRATCH_ROOT>"}'
printf '%s' "$RULE_JSON" > "$WORK/bin/path_transform_rule_v1.json"
RULE_SHA="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$WORK/bin/path_transform_rule_v1.json")"

# Evidence that carries the pattern in bytes the facts never read: a second
# line in the declaration (only line one is parsed) and a non-JSON line in
# the stream (skipped by recomputation).
if ! python3 "$CORPUS" green "$WORK/green"; then
  echo "UNMEASURED: corpus failed" >&2; exit 2
fi
printf 'launcher cwd was /private/scratch-root/work\n' >> "$WORK/green/invocation.txt"
printf 'session cwd /private/scratch-root/work, not an event\n' >> "$WORK/green/stream.jsonl"
if ! bash "$ANCHORS" "$WORK/green" "$WORK/ledger" green >/dev/null \
   || ! python3 "$RECORD" "$WORK/green" "$WORK/green/statement.json" >/dev/null; then
  echo "UNMEASURED: anchoring or builder failed" >&2; exit 2
fi
python3 "$WORK/bin/conformance_verify.py" "$WORK/green/statement.json" --ledger-repo "$WORK/ledger" >/dev/null; rc=$?
[ "$rc" -eq 0 ] || { echo "UNMEASURED: pre-transform control not CONFORMANT (exit $rc)" >&2; exit 2; }

# The transformation: applied on disk AFTER the record measured and the
# apparatus anchored, exactly the sequence that produced the in-tree desync.
python3 - "$WORK/green" <<'PY'
import os, sys
d = sys.argv[1]
for name in ("invocation.txt", "stream.jsonl"):
    p = os.path.join(d, name)
    data = open(p, "rb").read()
    assert b"/private/scratch-root" in data
    open(p, "wb").write(data.replace(b"/private/scratch-root", b"<SCRATCH_ROOT>"))
PY
cite() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
src_dst, sha, mode = sys.argv[1], sys.argv[2], sys.argv[3]
st = json.load(open(src_dst))
if mode == "null":
    st["predicate"]["transformation"] = None
else:
    st["predicate"]["transformation"] = {"id": "path-transform/v1", "sha256": sha}
data = json.dumps(st, sort_keys=True, separators=(",", ":"),
                  ensure_ascii=False).encode("utf-8")
open(src_dst, "wb").write(data)
PY
}

# Arm A: positive control -- citation bound to the rule the verifier holds.
cite "$WORK/green/statement.json" "$RULE_SHA" cite
out="$(python3 "$WORK/bin/conformance_verify.py" "$WORK/green/statement.json" --ledger-repo "$WORK/ledger" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || { echo "RED: declared transformation refused (exit $rc); recompute-through failed" >&2; printf '%s\n' "$out" >&2; exit 1; }

# Arm B: rule file absent beside the verifier.
mv "$WORK/bin/path_transform_rule_v1.json" "$WORK/rule.aside"
out="$(python3 "$WORK/bin/conformance_verify.py" "$WORK/green/statement.json" --ledger-repo "$WORK/ledger" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED: record citing an absent transformation rule verified CONFORMANT" >&2; exit 1
fi
[ "$rc" -eq 2 ] || { echo "RED: absent rule gave exit $rc, expected 2" >&2; printf '%s\n' "$out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "transformation rule" \
  || { echo "RED: absent rule refused without naming the transformation rule" >&2; printf '%s\n' "$out" >&2; exit 1; }
mv "$WORK/rule.aside" "$WORK/bin/path_transform_rule_v1.json"

# Arm C: rule file present, different bytes, same semantics -- only the
# digest binding separates this from the declared rule.
printf '%s ' "$RULE_JSON" > "$WORK/bin/path_transform_rule_v1.json"
out="$(python3 "$WORK/bin/conformance_verify.py" "$WORK/green/statement.json" --ledger-repo "$WORK/ledger" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED: record citing a drifted transformation rule verified CONFORMANT; the citation is decoration" >&2; exit 1
fi
[ "$rc" -eq 2 ] || { echo "RED: drifted rule gave exit $rc, expected 2" >&2; printf '%s\n' "$out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "transformation rule digest mismatch" \
  || { echo "RED: drifted rule refused without the digest mismatch named" >&2; printf '%s\n' "$out" >&2; exit 1; }
printf '%s' "$RULE_JSON" > "$WORK/bin/path_transform_rule_v1.json"

# Arm D: transformation null, bytes moved anyway -- the plain refusal holds.
cite "$WORK/green/statement.json" "" null
out="$(python3 "$WORK/bin/conformance_verify.py" "$WORK/green/statement.json" --ledger-repo "$WORK/ledger" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || { echo "RED: undeclared moved bytes gave exit $rc, expected 2" >&2; printf '%s\n' "$out" >&2; exit 1; }
printf '%s\n' "$out" | grep -q "digest mismatch" \
  || { echo "RED: undeclared moved bytes refused without digest mismatch named" >&2; printf '%s\n' "$out" >&2; exit 1; }

echo "GREEN: declared transformation recomputes through; absent, drifted and undeclared all refused"
