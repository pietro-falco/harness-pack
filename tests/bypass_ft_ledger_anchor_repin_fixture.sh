#!/usr/bin/env bash
# FT-30 -- ledger-anchor-repin. THR-COVER measured that a mutant which
# rewrites evidence AND re-pins the digests coherently is self-certifying:
# every check the verifier held was internal to the record/evidence pair
# (C6 stream substitution, C8 declaration widening -- both CONFORMANT at
# 5/9). The anchor closes that class: the apparatus pins the declaration
# and stream digests into the append-only observation ledger BEFORE the
# record is built, the record cites the entries, and the verifier compares
# the record's digests against the anchored blobs -- an input the record's
# author cannot write.
#
# FIVE ARMS, one green control:
#   A  stream bytes changed, stream+subject digests re-pinned coherently,
#      facts untouched (the appended line is not JSON)   -> want 1 DIVERGENT
#      naming the anchor
#   B  declaration widened to encompass the attempted Bash, its digest
#      re-pinned, declaredSurface and unusedAuthorizations updated
#      coherently                                        -> want 1 DIVERGENT
#      naming the anchor
#   C  anchor.streamEntry forged (an oid the ledger does not contain)
#                                                        -> want 2, entry not
#      included in the ledger
#   D  anchor stripped from the record entirely          -> want 2, closed
#      vocabulary (lacks required keys)
#   E  anchored record verified with NO --ledger-repo    -> want 2, not
#      verifiable in isolation
#
# GREEN: control CONFORMANT; all five arms exit with the wanted code and
# reason. RED: any arm reaches 0, or exits with the wrong code -- the
# record is self-certifying again. UNMEASURED (2): machinery absent or
# control not CONFORMANT.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="${CONFORMANCE_CORPUS:-$ROOT/tests/fixtures/conformance_corpus.py}"
RECORD="${CONFORMANCE_RECORD:-$ROOT/scripts/conformance_record.py}"
VERIFY="${CONFORMANCE_VERIFY:-$ROOT/scripts/conformance_verify.py}"
ANCHORS="${SCRATCH_LEDGER:-$ROOT/tests/fixtures/scratch_ledger.sh}"
for f in "$CORPUS" "$RECORD" "$VERIFY" "$ANCHORS"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft30.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
if ! python3 "$CORPUS" green "$WORK/green" \
   || ! bash "$ANCHORS" "$WORK/green" "$WORK/ledger" green >/dev/null \
   || ! python3 "$RECORD" "$WORK/green" "$WORK/green/statement.json" >/dev/null; then
  echo "UNMEASURED: green corpus or builder failed" >&2; exit 2
fi
python3 "$VERIFY" "$WORK/green/statement.json" --ledger-repo "$WORK/ledger" >/dev/null; rc=$?
[ "$rc" -eq 0 ] || { echo "UNMEASURED: positive control not CONFORMANT (exit $rc)" >&2; exit 2; }

repin() {
  # Re-pin the named role's digest (and the subject, for the stream) to the
  # evidence bytes now on disk -- the coherent-mutant move.
  python3 - "$1" "$2" <<'PY'
import hashlib, json, os, sys
d, role = sys.argv[1], sys.argv[2]
st = json.load(open(os.path.join(d, "statement.json")))
name = next(e["name"] for e in st["predicate"]["evidence"] if e["role"] == role)
digest = hashlib.sha256(open(os.path.join(d, name), "rb").read()).hexdigest()
for e in st["predicate"]["evidence"]:
    if e["role"] == role:
        e["sha256"] = digest
if role == "stream":
    st["subject"][0]["digest"]["sha256"] = digest
data = json.dumps(st, sort_keys=True, separators=(",", ":"),
                  ensure_ascii=False).encode("utf-8")
open(os.path.join(d, "statement.json"), "wb").write(data)
PY
}
want() {
  # want DIR CODE REASON LABEL [EXTRA_VERIFY_ARGS...]
  d=$1; code=$2; reason=$3; label=$4; shift 4
  out="$(python3 "$VERIFY" "$d/statement.json" "$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && [ "$code" -ne 0 ]; then
    echo "RED: $label verified CONFORMANT; the record is self-certifying" >&2; exit 1
  fi
  [ "$rc" -eq "$code" ] || { echo "RED: $label exited $rc, expected $code" >&2; printf '%s\n' "$out" >&2; exit 1; }
  printf '%s\n' "$out" | grep -q "$reason" \
    || { echo "RED: $label exit $code without the expected reason ($reason)" >&2; printf '%s\n' "$out" >&2; exit 1; }
}

# Arm A: stream substituted, digests re-pinned coherently, facts untouched.
cp -R "$WORK/green" "$WORK/repin-stream"
printf 'trailing non-json byte the facts never see\n' >> "$WORK/repin-stream/stream.jsonl"
repin "$WORK/repin-stream" stream
want "$WORK/repin-stream" 1 "anchored" "stream-repinned record" --ledger-repo "$WORK/ledger"

# Arm B: declaration widened a posteriori, digest re-pinned, facts coherent.
cp -R "$WORK/green" "$WORK/repin-decl"
python3 - "$WORK/repin-decl" <<'PY'
import json, os, sys
d = sys.argv[1]
inv = open(os.path.join(d, "invocation.txt"), "rb").read()
head, sep, tail = inv.partition(b"\n")
assert b"tools=Read,Write,Agent " in head, head
head = head.replace(b"tools=Read,Write,Agent ", b"tools=Read,Write,Agent,Bash ")
open(os.path.join(d, "invocation.txt"), "wb").write(head + sep + tail)
st = json.load(open(os.path.join(d, "statement.json")))
ds = st["predicate"]["declaredSurface"]
assert ds["tools"] == ["Agent", "Read", "Write"], ds
ds["tools"] = ["Agent", "Bash", "Read", "Write"]
assert st["predicate"]["unusedAuthorizations"] == ["Read"]
st["predicate"]["unusedAuthorizations"] = ["Bash", "Read"]
data = json.dumps(st, sort_keys=True, separators=(",", ":"),
                  ensure_ascii=False).encode("utf-8")
open(os.path.join(d, "statement.json"), "wb").write(data)
PY
repin "$WORK/repin-decl" declaration
want "$WORK/repin-decl" 1 "anchored" "declaration-repinned record" --ledger-repo "$WORK/ledger"

# Arm C: anchor entry forged -- an oid the ledger does not contain.
cp -R "$WORK/green" "$WORK/forged"
python3 - "$WORK/forged/statement.json" <<'PY'
import json, sys
st = json.load(open(sys.argv[1]))
st["predicate"]["anchor"]["streamEntry"] = "f" * 40
data = json.dumps(st, sort_keys=True, separators=(",", ":"),
                  ensure_ascii=False).encode("utf-8")
open(sys.argv[1], "wb").write(data)
PY
want "$WORK/forged" 2 "not included in the ledger" "forged-entry record" --ledger-repo "$WORK/ledger"

# Arm D: anchor stripped from the record.
cp -R "$WORK/green" "$WORK/stripped"
python3 - "$WORK/stripped/statement.json" <<'PY'
import json, sys
st = json.load(open(sys.argv[1]))
del st["predicate"]["anchor"]
data = json.dumps(st, sort_keys=True, separators=(",", ":"),
                  ensure_ascii=False).encode("utf-8")
open(sys.argv[1], "wb").write(data)
PY
want "$WORK/stripped" 2 "lacks required keys" "anchor-stripped record" --ledger-repo "$WORK/ledger"

# Arm E: anchored record with no ledger supplied -- never a pass in isolation.
want "$WORK/green" 2 "not verifiable in isolation" "ledgerless verification"

echo "GREEN: re-pinned digests diverge from the anchor; forged, stripped and ledgerless records refused"
