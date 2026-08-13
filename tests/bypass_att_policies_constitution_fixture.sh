#!/usr/bin/env bash
# bypass_att_policies_constitution -- the falsifier ADR-020 D4 names, AND THIS
# FILE CLOSES ADR-019 OR-4.
#
# THE ASSERTION (ADR-020 Verification, verbatim): "A fixture asserting that
# `verifier.policies` **never** contains the digest of `CONSTITUTION.md`."
#
# OR-4 held this row open as the pair to OR-5. ADR-019 OR-4, verbatim: "The
# writer exists, so the premise that held this open is gone. It is not written
# here because it is the pair to OR-5, whose reason is specific and is stated
# there." OR-5's reason was that ADR-020 was Proposed. ADR-020 is ratified in
# this commit, so both premises are gone and this is OR-4's fixture.
#
# NOT YET OBSERVED WHEN IT WAS WRITTEN, AND OBSERVED HERE. ADR-020's row declared
# itself a prediction and named exactly what it is aimed at: "Its value is that
# it fails on the *attractive* implementation: `constitution_hash` is the only
# digest-shaped value already in the receipt (`scripts/write_receipt.py:135`), it
# is already pinned fail-closed at `scripts/launch_checks.py:61-64`, and it is
# therefore the value a producer reaches for when SVR v0.2 demands a
# `ResourceDescriptor` and none is at hand. The fixture exists to refuse that
# reach."
#
# WHY THE WRONG DIGEST IS WORSE THAN NO DIGEST, which is the whole reason this
# row is not cosmetic. ADR-020 D4: "`CONSTITUTION.md` governs the **child** -- the
# subject being judged -- not the judge. Putting it in `verifier.policies` would
# assert that the harness verified the run against the constitution, which is
# precisely the thing the harness does *not* do." A consumer reading such a
# Statement has no way to second-guess it. It is the same failure class as
# ADR-019 D2's rejected `HEAD` subject: well-formed, readable, and untrue.
#
# THE FOUR ARMS, and each is a state the emitter must reach differently:
#
#   arm 1  a gate that read the claims manifest -> policies carries THAT digest,
#          and it is the manifest's, recomputed here from the file's bytes.
#   arm 2  the constitution's digest is in the receipt the emitter was handed,
#          and appears NOWHERE in the artifact. This is the row proper.
#   arm 3  no digest available (no gate, or an unreadable manifest) -> policies
#          is `[]`. D4: "nothing is invented." A fabricated descriptor here would
#          be the defect, not the empty array.
#   arm 4  a digest that is present but malformed -> the emitter STOPs and writes
#          NOTHING. A false descriptor is refused on the same ground ADR-019 D7
#          refuses an empty subject.
#
# The two digests are made DIFFERENT by construction: arm 2 is only a measurement
# if the value that must be absent could have been present and distinguishable.
#
# DECLARED GREEN, and this header is where the register reads that (ADR-017 D6).
# It goes RED if the emitter ever reaches for `constitution_hash`, or invents a
# descriptor on the empty branch, or accepts a malformed one.
#
# Nothing outside $WORK is written. CONSTITUTION.md is READ, never modified.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
RECEIPT_WRITER="$PACK/scripts/write_receipt.py"
STATEMENT_WRITER="$PACK/scripts/write_statement.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-att-pol.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }
sha_of() { python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

[ -f "$RECEIPT_WRITER" ] || broken "scripts/write_receipt.py is not where this fixture expects it"
[ -f "$STATEMENT_WRITER" ] || broken "scripts/write_statement.py is not where this fixture expects it"
[ -f "$PACK/CONSTITUTION.md" ] || broken "CONSTITUTION.md is not where this fixture expects it"
[ -f "$PACK/.verity/claims.json" ] || broken ".verity/claims.json is not where this fixture expects it; D4's descriptor has no subject"

CONST_SHA="$(sha_of "$PACK/CONSTITUTION.md")" || broken "could not digest CONSTITUTION.md"
CLAIMS_SHA="$(sha_of "$PACK/.verity/claims.json")" || broken "could not digest .verity/claims.json"

# The premise of arm 2. If these two were equal the row could not tell a correct
# descriptor from the attractive wrong one, and its green would be an accident.
[ "$CONST_SHA" != "$CLAIMS_SHA" ] \
  || broken "CONSTITUTION.md and .verity/claims.json have the same digest; arm 2 cannot discriminate"

echo "== bypass_att_policies_constitution: verifier.policies is the verifier's policy, never the doer's (ADR-020 D4; closes ADR-019 OR-4) =="
note "CONSTITUTION.md      sha256 = $CONST_SHA"
note ".verity/claims.json  sha256 = $CLAIMS_SHA"

# ---- the receipt, carrying the constitution's digest where D4 says it lives ---
# CONSTITUTION_HASH is the real one, not a placeholder: the attractive value has
# to actually be in the emitter's hand for its absence downstream to mean
# anything.
CC="$WORK/run-fixture-pol.cc.json"
printf '%s' '{"subtype":"success","num_turns":2,"total_cost_usd":0.01,"duration_ms":900,"session_id":"fixture-session","permission_denials":[]}' > "$CC"
printf '%s' '{"manifest_version":1,"verifier_id":"https://verifier.example.invalid/harness-pack/v1"}' > "$WORK/manifest.json"

RECEIPT="$WORK/run-fixture-pol.receipt.json"
CC_EXIT=0 \
GATE_JSON='{"verdict":"PASS","reason":"all declared criteria PASS","verity_exit":0,"claims":[{"id":"c1","type":"command","verdict":"PASS","evidence":"exit 0"}]}' \
BASELINE_JSON='{"verdict":"FAIL","reason":"criteria failed: c1","verity_exit":1,"claims":[{"id":"c1","type":"command","verdict":"FAIL","evidence":"exit 1"}]}' \
RUN_ID="run-fixture-pol" SPEC_ID="S-FIXTURE" MODEL_STRING="worker" \
TIER_RESOLVED="T3" MODEL_USED="HAIKU_CLASS_MODEL" MANIFEST_VERSION="1" \
CONSTITUTION_HASH="$CONST_SHA" \
TOOL_VERSION="0.0.0-fixture" STARTED_AT="2026-08-13T10:14:00Z" ENDED_AT="2026-08-13T10:15:00Z" \
  python3 "$RECEIPT_WRITER" "$CC" "$RECEIPT" >/dev/null \
  || broken "scripts/write_receipt.py did not compose the fixture receipt"

grep -qF -- "$CONST_SHA" "$RECEIPT" \
  || broken "the fixture receipt does not carry the constitution's digest; arm 2 would be vacuous"
note "the receipt carries the constitution's digest, so the attractive value IS in the emitter's hand"

CC_DIGEST="$(sha_of "$CC")" || broken "could not digest the fixture transcript"

emit() {
  # $1 = CLAIMS_SHA256 value, $2 = output path. Prints the emitter's own output.
  OUT_PATH="$CC" OUT_SHA256="$CC_DIGEST" HARNESS_MANIFEST="$WORK/manifest.json" \
  CLAIMS_SHA256="$1" python3 "$STATEMENT_WRITER" "$RECEIPT" "$2" 2>&1
}
policies_json() {
  python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1]))["predicate"]["verifier"]["policies"],sort_keys=True,separators=(",",":")))' "$1"
}

FAILED=0

# ---- arm 1: the gate read the manifest --------------------------------------
A1="$WORK/arm1.intoto.json"
A1_OUT="$(emit "$CLAIMS_SHA" "$A1")" \
  || broken "arm 1: the emitter refused a well-formed claims digest: $A1_OUT"
[ -f "$A1" ] || broken "arm 1: the emitter reported success and wrote no Statement"
A1_POL="$(policies_json "$A1")"
if [ "$A1_POL" = "[{\"digest\":{\"sha256\":\"$CLAIMS_SHA\"}}]" ]; then
  note "arm 1: policies carries the claims manifest's ResourceDescriptor, digest only"
else
  FAILED=1
  note "arm 1: policies is $A1_POL, expected the claims manifest's digest and nothing else"
fi

# ---- arm 2: THE ROW. the constitution's digest is nowhere in the artifact ----
if grep -qF -- "$CONST_SHA" "$A1"; then
  FAILED=1
  note "arm 2: the constitution's digest APPEARS in the Statement"
else
  note "arm 2: the constitution's digest appears nowhere in the Statement's bytes"
fi

# ---- arm 3: no digest available -> [] and not a fabrication ------------------
A3="$WORK/arm3.intoto.json"
A3_OUT="$(emit "" "$A3")" \
  || broken "arm 3: the emitter refused the empty branch, which D4 declares as decided: $A3_OUT"
[ -f "$A3" ] || broken "arm 3: the emitter reported success and wrote no Statement on the empty branch"
A3_POL="$(policies_json "$A3")"
if [ "$A3_POL" = "[]" ]; then
  note "arm 3: no gate digest -> policies is [], svr.md:74-76's minimal conformant form"
else
  FAILED=1
  note "arm 3: policies is $A3_POL on the empty branch; D4 says nothing is invented there"
fi
if grep -qF -- "$CONST_SHA" "$A3"; then
  FAILED=1
  note "arm 3: the constitution's digest was reached for once no other descriptor was at hand -- the exact reach D4 refuses"
fi

# ---- arm 4: a malformed digest is refused, and nothing is written ------------
A4="$WORK/arm4.intoto.json"
A4_RC=0
A4_OUT="$(emit "not-a-digest" "$A4")" || A4_RC=1
if [ "$A4_RC" -ne 0 ] && [ ! -f "$A4" ]; then
  note "arm 4: a malformed digest -> STOP, no file written -- $(printf '%s' "$A4_OUT" | head -1)"
else
  FAILED=1
  note "arm 4: a malformed digest was not refused (rc=$A4_RC); a false descriptor must be refused"
fi

if [ "$FAILED" -eq 0 ]; then
  echo "GREEN [bypass_att_policies_constitution] verifier.policies carries the claims manifest, never the constitution"
  note "four arms held: the manifest's descriptor, the constitution's absence, the empty branch, the malformed refusal"
  note "ADR-020 D4: 'Collapsing doer-policy into verifier-policy destroys the distinction the entire harness is built on'"
  echo "att_policies_constitution BYPASS FIXTURE: GREEN"
  exit 0
fi

echo "RED [bypass_att_policies_constitution] verifier.policies does not hold the distinction D4 draws"
note "CONSTITUTION.md governs the child; .verity/claims.json is what the verifier verified against."
note "A Statement that names the wrong one is well-formed, machine-readable and untrue."
echo "att_policies_constitution BYPASS FIXTURE: RED"
exit 1
