#!/usr/bin/env bash
# bypass_att_alg_unpinned -- the falsifier ADR-018 D2 names.
#
# THE ASSERTION (ADR-018 D2, verbatim): "Every digest written into a **new**
# artifact is an in-toto `DigestSet`: a JSON object mapping algorithm name to
# lowercase hex, `{"<algorithm-name>": "<hex>"}`. Never a field whose *name* is
# the algorithm."
#
# THE SCOPE IS THE HARD PART, AND IT IS WHY THIS FIXTURE IS NOT A GREP.
# D2 binds NEW artifacts. D4 exempts the ones that already exist -- "Existing
# chains are **not** migrated: rewriting them is exactly the mutation the chain
# exists to detect". A sweep that cannot tell the two apart accuses
# examples/receipt-chain.sample.jsonl, a tracked artifact this ADR deliberately
# leaves alone, and a fixture that accuses an exempt artifact is measuring the
# wrong thing loudly.
#
# The distinction is made operational rather than argued. Exactly one artifact
# reachable today is bound by D2, and D4 is what names it: "`harness-pack`
# adopts the new form **at the next genesis**, where the cost is zero." A chain
# created from GENESIS in this run IS that artifact -- born after the decision,
# costing nothing to shape correctly, and requiring nothing on disk to be
# migrated for it to be correct.
#
#   CONSTRAINED  the genesis line this fixture asks scripts/receipt_chain.py to
#                write, into an empty scratch directory, in this run.
#   EXEMPT       examples/receipt-chain.sample.jsonl, 3 tracked lines. Read
#                read-only, never written, and shown NOT to be accused.
#
# THE RULE THE DETECTOR APPLIES. A top-level key of a chain line is
# algorithm-named if the key, lowercased, equals a name in the in-toto registry
# or ends with `_<name>`. That is D2's own sentence made executable: `sha256` is
# the name itself and `prev_sha256` is the name folded into a longer one, and D2
# names both -- "`prev_sha256` and `sha256` in the existing chain line are
# exactly the defect this decision names: the algorithm folded into the field
# name, so the field cannot express a second algorithm without being renamed."
#
# ONLY TOP-LEVEL KEYS ARE INSPECTED, and that is not a shortcut. In the form D4
# adopts -- `"digest": {"sha256": <hex>}` -- the string `sha256` appears as the
# key of the DigestSet, which is the CORRECT place for it. A recursive detector
# would flag the repair as the defect. Control 1 fabricates that exact line and
# requires ZERO findings from it.
#
# The algorithm names are the registry's, read from `spec/v1/digest_set.md` @
# `in-toto/attestation` `main`, sha256
# 0b1889fdea7f6d623b41555632aedf04ee4398cf02a32002060608c75ebb038e, 8873 bytes
# -- the digest ADR-018 pins in its Basis, re-fetched and re-matched byte for
# byte when this fixture was written. Names read at :32 (the NIST family), :38
# (`dirHash`) and :103 (the git family).
#
# DECLARED RED, and this header is where the register reads that (ADR-017 D6).
# The genesis line scripts/receipt_chain.py:50-53 writes today carries
# `prev_sha256` and `sha256` as top-level field names: two findings on an
# artifact D2 binds. It goes GREEN when a genesis line is born carrying
# DigestSets -- one edit to `append`, which is the same edit that clears
# bypass_chain_form_migration. The two rows coincide at this basis because this
# repository holds exactly ONE digest-carrying artifact. They are separate rows
# because they are separate decisions, and they diverge the moment a second
# artifact exists (ADR-019 D5's side-car Statement).
#
# Nothing outside $WORK is written. The chain this fixture measures is one it
# creates; examples/ and .harness/ are never appended to.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
CHAIN_TOOL="$PACK/scripts/receipt_chain.py"
SAMPLE="$PACK/examples/receipt-chain.sample.jsonl"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-att-alg.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$CHAIN_TOOL" ] || broken "scripts/receipt_chain.py is not where this fixture expects it"
[ -f "$SAMPLE" ] || broken "examples/receipt-chain.sample.jsonl is not where this fixture expects it"

# The detector. One finding per algorithm-named TOP-LEVEL key, printed as
# "<line> <key>". Exits 0 whatever it finds: findings are data on stdout, not a
# verdict, and the verdict is this fixture's to make.
cat > "$WORK/algnames.py" <<'DETECTOR'
import json, sys

# in-toto DigestSet registry, digest_set.md:32, :38, :103.
ALGS = {
    "sha256", "sha224", "sha384", "sha512", "sha512_224", "sha512_256",
    "sha3_224", "sha3_256", "sha3_384", "sha3_512", "shake128", "shake256",
    "blake2b", "blake2s", "ripemd160", "sm3", "gost", "sha1", "md5",
    "dirhash", "gitcommit", "gittree", "gitblob", "gittag",
}

def algorithm_named(key):
    k = key.lower()
    if k in ALGS:
        return True
    return any(k.endswith("_" + a) for a in ALGS)

rc = 0
for lineno, raw in enumerate(open(sys.argv[1], "rb"), 1):
    stripped = raw.rstrip(b"\n")
    if not stripped:
        continue
    try:
        entry = json.loads(stripped)
    except Exception:
        print("%d <unparseable>" % lineno)
        rc = 0
        continue
    if not isinstance(entry, dict):
        continue
    for key in entry:
        if algorithm_named(key):
            print("%d %s" % (lineno, key))
sys.exit(rc)
DETECTOR

findings() { python3 "$WORK/algnames.py" "$1"; }
count_findings() { findings "$1" | grep -c . ; }

echo "== bypass_att_alg_unpinned: the algorithm is data, never a field name (ADR-018 D2) =="

# ---- control 1: the detector does not flag the repair -----------------------
# The form D4 adopts. `sha256` appears twice in this line and both times it is
# the key of a DigestSet, which is where D2 puts it. Zero findings, or the
# detector is unable to tell the defect from its fix and nothing below means
# anything.
cat > "$WORK/newform.jsonl" <<'NEWFORM'
{"digest":{"sha256":"0000000000000000000000000000000000000000000000000000000000000000"},"prev":{"sha256":"1111111111111111111111111111111111111111111111111111111111111111"},"rolled_up_at":"2026-01-01T00:00:00+00:00","run_id":"control-newform","seq":2,"source_filename":"a.json"}
NEWFORM
C1="$(count_findings "$WORK/newform.jsonl")"
[ "$C1" -eq 0 ] || broken "control 1: the detector flagged $C1 key(s) in a correctly-shaped new-form line; it cannot distinguish the defect from its repair"

# ---- control 2: the detector is not blind -----------------------------------
# A hand-written old-form line, independent of the tool under measurement. Two
# findings, or a zero below would say nothing at all.
cat > "$WORK/oldform.jsonl" <<'OLDFORM'
{"prev_sha256":"GENESIS","rolled_up_at":"2026-01-01T00:00:00+00:00","run_id":"control-oldform","seq":1,"sha256":"2222222222222222222222222222222222222222222222222222222222222222","source_filename":"a.json"}
OLDFORM
C2="$(count_findings "$WORK/oldform.jsonl")"
[ "$C2" -eq 2 ] || broken "control 2: a hand-written old-form line yielded $C2 finding(s), expected 2 (sha256, prev_sha256); the detector is not measuring what this fixture claims"
note "control: new-form line -> $C1 findings; hand-written old-form line -> $C2 findings ($(findings "$WORK/oldform.jsonl" | awk '{print $2}' | tr '\n' ' '))"

# ---- scope: the tracked sample is EXEMPT, and is shown to be ----------------
# Read-only. This is the artifact D4 leaves alone, and the fixture's job here is
# to demonstrate that it declines to accuse it -- not to find it clean.
SAMPLE_HITS="$(count_findings "$SAMPLE")"
note "scope: examples/receipt-chain.sample.jsonl carries $SAMPLE_HITS algorithm-named key(s) and is EXEMPT"
note "       D4: 'Existing chains are not migrated'. An existing artifact is outside D2's reach, so"
note "       those $SAMPLE_HITS keys are not findings. They are read here only to show the exemption is real"

# ---- the measurement: a genesis born in this run ----------------------------
printf '{"x":"one"}' > "$WORK/src-a.json" || broken "could not write the fixture source file"
CHAIN="$WORK/receipt-chain.jsonl"
APPEND_OUT="$(python3 "$CHAIN_TOOL" append --chain "$CHAIN" --run-id "att-alg-genesis" "$WORK/src-a.json" 2>&1)"
APPEND_RC=$?
[ "$APPEND_RC" -eq 0 ] || broken "scripts/receipt_chain.py append failed (rc=$APPEND_RC): $APPEND_OUT"
[ -s "$CHAIN" ] || broken "append reported success and wrote no genesis line"
GENESIS_LINE="$(head -1 "$CHAIN")"
case "$GENESIS_LINE" in
  *'"prev_sha256":"GENESIS"'*) : ;;
  *) broken "the line written is not a genesis line (no GENESIS sentinel): $GENESIS_LINE" ;;
esac

HITS="$(findings "$CHAIN")"
N="$(printf '%s' "$HITS" | grep -c .)"

if [ "$N" -gt 0 ]; then
  echo "RED [bypass_att_alg_unpinned] a genesis born after ADR-018 writes the algorithm as a field name"
  note "genesis line: $GENESIS_LINE"
  note "findings ($N): $(printf '%s' "$HITS" | awk '{print $2}' | tr '\n' ' ')"
  note "scripts/receipt_chain.py:50-53 builds that entry, and :54 serializes it. The two keys ARE the"
  note "algorithm: the field cannot carry a second one without being renamed, which is D2's whole point"
  note "this line is not exempt. D4 exempts chains that already exist; this one was created in this run,"
  note "in an empty directory, and D4 names precisely this moment -- 'the new form at the next genesis,"
  note "where the cost is zero'. The cost was zero and the old form was written anyway"
  note "green when a genesis line carries \"digest\": {\"sha256\": <hex>} and \"prev\": {\"sha256\": <hex>}"
  echo "att_alg_unpinned BYPASS FIXTURE: RED"
  exit 1
fi

echo "GREEN [bypass_att_alg_unpinned] a genesis born in this run names no algorithm in a field name"
note "genesis line: $GENESIS_LINE"
note "exempt sample untouched, $SAMPLE_HITS key(s), not accused"
echo "att_alg_unpinned BYPASS FIXTURE: GREEN"
exit 0
