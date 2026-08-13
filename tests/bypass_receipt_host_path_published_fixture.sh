#!/usr/bin/env bash
# bypass_receipt_host_path_published -- the falsifier ADR-020 D1 and D3 name.
#
# THE ASSERTION (ADR-020 Verification, verbatim): "A receipt containing the
# literal home-directory prefix must be **refused by the publication boundary**."
# (The ADR spells the token; this file does not, for the reason three paragraphs
# down.)
#
# THE RED THIS ROW HOLDS WAS ALREADY MEASURED, and is cited rather than predicted.
# ADR-020's row, verbatim: "**RED already observed**, not predicted.
# `N3-PUBLISH.md` measured **2 of 49** receipts carrying the token, at these two
# JSON paths: `.contribution.baseline.claims[*].evidence` (2 receipts) and
# `.refusals.denials[*].tool_input.file_path` (1 receipt). The mechanism is
# `verity` `src/checks.ts:75` and the state that triggers it is the one
# `scripts/launch_worker.sh:335-336` calls healthy. The fixture's job is to hold
# that RED inside the suite instead of inside a measurement document that nothing
# executes."
#
# `N3-PUBLISH.md` is the document ADR-020's Basis pins by digest
# e7d7a33e4b307c1c99fabad1db22e83aae06cf5692bbd6fef79e795d9645e66e. Its bytes are
# held in the operator's private governance vault and its manifest is tracked at
# .verity/evidence/2026-08-13-attestation-s1/README.md. This fixture re-derives
# nothing from it; it reproduces the two JSON paths it named and carries the RULE.
#
# THE TOKEN IS NEVER WRITTEN LITERALLY IN THIS FILE. It is assembled at runtime
# from its two halves, because a tracked file carrying it is exactly what
# `privacy-lint-user-paths` in .verity/claims.json exists to refuse -- and a
# fixture that had to be added to that claim's exclusion list to run would be
# reproducing the defect ADR-020 D3 criticises rather than measuring it. The
# assembly is three lines and it keeps both claims honest at once.
#
# WHAT "REFUSED BY THE PUBLICATION BOUNDARY" MEANS AFTER ADR-020, and the reading
# is load-bearing. It does NOT mean the receipt is sanitised: ADR-020's Non-goals
# say in as many words that the receipt is not modified, not one byte, and D1 says
# the receipt "is not the thing to fix". It means the receipt is REMOVED FROM THE
# QUESTION -- the publishable artifact is the Statement, and the boundary is
# scripts/statement_lint.py in front of it. So the row measures two things at
# once: the receipt still carries the token (the RED, reproduced), and the
# artifact derived from it does not and would be refused if it did.
#
# DECLARED GREEN, and this header is where the register reads that (ADR-017 D6).
# It goes RED if a receipt's host path ever reaches the side-car, or if the
# boundary stops refusing one that does.
#
# Nothing outside $WORK is written. No repository file is created, moved or
# edited by this fixture, and no receipt anywhere on disk is read.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
RECEIPT_WRITER="$PACK/scripts/write_receipt.py"
STATEMENT_WRITER="$PACK/scripts/write_statement.py"
BOUNDARY="$PACK/scripts/statement_lint.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-att-hostpath.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

[ -f "$RECEIPT_WRITER" ] || broken "scripts/write_receipt.py is not where this fixture expects it"
[ -f "$STATEMENT_WRITER" ] || broken "scripts/write_statement.py is not where this fixture expects it"
[ -f "$BOUNDARY" ] || broken "scripts/statement_lint.py is not where this fixture expects it; ADR-020 D3's claim has no detector"

# The token, assembled rather than spelled. See the header.
SEP="/"
TOKEN="${SEP}Users${SEP}"
HOSTPATH="${TOKEN}someone${SEP}Code${SEP}worker${SEP}README.md"

# verity src/checks.ts:75's FAIL-branch evidence, reproduced in shape: the string
# is `does not exist at ${abs}` and `abs` is absolute by construction at :62.
# The PASS branch at :96 emits `exists, N bytes` and carries no path at all --
# which is why the leak is correlated with the baseline FAILING, and why
# launch_worker.sh:335-336 calling that state "the healthy normal case" makes it
# the modal case rather than an edge.
export LEAK_EVIDENCE="does not exist at $HOSTPATH"
export LEAK_DENIAL_PATH="$HOSTPATH"

accepts() { python3 "$BOUNDARY" "$1"; }

echo "== bypass_receipt_host_path_published: the host path in a receipt never reaches the publishable artifact (ADR-020 D1/D3) =="

# ---- control 1: the boundary refuses the token wherever it can appear --------
# Two shapes: the token in a structurally-allowed slot (a URI), and the token in
# a slot the structural rule already rejects. Both must be refused, and the first
# is the one that matters -- a boundary that only catches the token where the
# shape is already wrong is not catching the token.
CONF='{"_type":"https://in-toto.io/Statement/v1","subject":[{"digest":{"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"name":"run.cc.json"}],"predicateType":"https://in-toto.io/attestation/svr/v0.2","predicate":{"verifier":{"id":"https://verifier.example.invalid/harness-pack/v1","policies":[]},"timeCreated":"2026-08-13T10:15:00Z","properties":["HARNESS_GATE_PASS"]}}'
printf '%s' "$CONF" > "$WORK/conforming.json"

if ! python3 - "$WORK" "$HOSTPATH" <<'SHAPES'
import json, sys
work, hostpath = sys.argv[1], sys.argv[2]
base = json.load(open(work + "/conforming.json"))

a = json.loads(json.dumps(base))
a["predicate"]["verifier"]["id"] = "file://" + hostpath
json.dump(a, open(work + "/token-in-uri.json", "w"), sort_keys=True, separators=(",", ":"))

b = json.loads(json.dumps(base))
b["predicate"]["evidence"] = "does not exist at " + hostpath
json.dump(b, open(work + "/token-in-evidence.json", "w"), sort_keys=True, separators=(",", ":"))
SHAPES
then
  broken "could not construct the control-1 shapes"
fi

C1_FAIL=0
for shape in token-in-uri token-in-evidence; do
  if OUT="$(accepts "$WORK/$shape.json" 2>&1)"; then
    C1_FAIL=1
    note "control 1: '$shape' was ACCEPTED by the boundary"
  else
    note "control 1: $(printf '%-18s' "$shape") -> $(printf '%s' "$OUT" | head -1)"
  fi
done
[ "$C1_FAIL" -eq 0 ] || broken "control 1: the boundary published a host path; it cannot tell the defect from a conforming artifact"

# ---- control 2: the boundary is not wired to reject everything ---------------
C2_OUT="$(accepts "$WORK/conforming.json" 2>&1)" \
  || broken "control 2: a hand-written conforming Statement was rejected ($C2_OUT); a boundary that refuses everything discriminates nothing"
note "control 2: a hand-written conforming Statement -> $(printf '%s' "$C2_OUT" | head -1)"

# ---- the RED, reproduced: a receipt at the census's two JSON paths -----------
CC="$WORK/run-fixture-hostpath.cc.json"
if ! python3 - "$CC" <<'CCJSON'
import json, os, sys
cc = {
    "subtype": "success", "num_turns": 3, "total_cost_usd": 0.02,
    "duration_ms": 1500, "session_id": "fixture-session",
    # .refusals.denials[*].tool_input.file_path -- the census's second path,
    # 1 receipt of 49. write_receipt.py:124 copies this array unmodified.
    "permission_denials": [
        {"tool_name": "Read", "tool_input": {"file_path": os.environ["LEAK_DENIAL_PATH"]}}
    ],
}
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write(json.dumps(cc))
CCJSON
then
  broken "could not construct the leaking cc.json"
fi

printf '%s' '{"manifest_version":1,"verifier_id":"https://verifier.example.invalid/harness-pack/v1"}' > "$WORK/manifest.json"

# .contribution.baseline.claims[*].evidence -- the census's first path, 2 receipts
# of 49. A t0 baseline in which a file_exists claim FAILs is the state
# launch_worker.sh:335-336 declares healthy and normal.
RECEIPT="$WORK/run-fixture-hostpath.receipt.json"
CC_EXIT=0 \
GATE_JSON='{"verdict":"PASS","reason":"all declared criteria PASS","verity_exit":0,"claims":[{"id":"readme-committed","type":"file_exists","verdict":"PASS","evidence":"exists, 412 bytes"}]}' \
BASELINE_JSON="{\"verdict\":\"FAIL\",\"reason\":\"criteria failed: readme-committed\",\"verity_exit\":1,\"claims\":[{\"id\":\"readme-committed\",\"type\":\"file_exists\",\"verdict\":\"FAIL\",\"evidence\":\"$LEAK_EVIDENCE\"}]}" \
RUN_ID="run-fixture-hostpath" SPEC_ID="S-FIXTURE" MODEL_STRING="worker" \
TIER_RESOLVED="T3" MODEL_USED="HAIKU_CLASS_MODEL" MANIFEST_VERSION="1" \
CONSTITUTION_HASH="00a92e1544ba9dd55591388830a7f86bf1a8d555e22f455f05b5eb267ecaf97d" \
TOOL_VERSION="0.0.0-fixture" STARTED_AT="2026-08-13T10:14:00Z" ENDED_AT="2026-08-13T10:15:00Z" \
  python3 "$RECEIPT_WRITER" "$CC" "$RECEIPT" >/dev/null \
  || broken "scripts/write_receipt.py did not compose the fixture receipt"

# THE MEASURED RED, HELD IN THE SUITE. Both census paths must actually carry the
# token, or this row is asserting something about an artifact that does not have
# the defect. The JSON paths are read structurally rather than grepped, because
# the census named PATHS and a grep would agree with a token anywhere.
CENSUS_OUT="$(python3 - "$RECEIPT" "$TOKEN" <<'CENSUS'
import json, sys
r = json.load(open(sys.argv[1]))
token = sys.argv[2]
hits = []
for i, c in enumerate((r.get("contribution", {}).get("baseline", {}) or {}).get("claims", []) or []):
    if token in (c.get("evidence") or ""):
        hits.append(".contribution.baseline.claims[%d].evidence" % i)
for i, d in enumerate((r.get("refusals", {}) or {}).get("denials", []) or []):
    if token in str((d.get("tool_input") or {}).get("file_path") or ""):
        hits.append(".refusals.denials[%d].tool_input.file_path" % i)
print("|".join(hits))
sys.exit(0 if len(hits) == 2 else 1)
CENSUS
)" \
  || broken "the fixture receipt does not carry the token at both JSON paths N3-PUBLISH.md's census named; the RED is not reproduced and the row would be vacuous"
note "RED reproduced in-suite, at the census's own two JSON paths:"
for p in ${CENSUS_OUT//|/ }; do note "  $p"; done

# ---- the row: the artifact derived from that receipt --------------------------
CC_DIGEST="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$CC")" \
  || broken "could not digest the fixture transcript"

STATEMENT="$WORK/run-fixture-hostpath.intoto.json"
EMIT_OUT="$(OUT_PATH="$CC" OUT_SHA256="$CC_DIGEST" HARNESS_MANIFEST="$WORK/manifest.json" \
  python3 "$STATEMENT_WRITER" "$RECEIPT" "$STATEMENT" 2>&1)" \
  || broken "scripts/write_statement.py refused a receipt it could read: $EMIT_OUT"
[ -f "$STATEMENT" ] || broken "the emitter reported success and wrote no Statement; there is nothing to judge"

ROW_RC=0
ROW_OUT="$(accepts "$STATEMENT" 2>&1)" || ROW_RC=1
STATEMENT_CARRIES=0
grep -qF -- "$TOKEN" "$STATEMENT" && STATEMENT_CARRIES=1

# And the receipt is still exactly as unpublishable as it was: ADR-020's
# Non-goals promise no sanitisation, and a row that silently benefited from one
# would be measuring a decision nobody took.
grep -qF -- "$TOKEN" "$RECEIPT" || broken "the receipt no longer carries the token; something sanitised it, which ADR-020's Non-goals rule out"

if [ "$ROW_RC" -eq 0 ] && [ "$STATEMENT_CARRIES" -eq 0 ]; then
  echo "GREEN [bypass_receipt_host_path_published] the receipt carries the host path at both census paths; the publishable artifact carries none of it"
  note "boundary on the emitted artifact: $(printf '%s' "$ROW_OUT" | head -1)"
  note "the receipt is unchanged and still unpublishable -- ADR-020 D1: 'the receipt is not the thing to fix'"
  note "N3-PUBLISH.md measured 2 of 49 receipts carrying the token; that RED now lives in this suite"
  echo "receipt_host_path_published BYPASS FIXTURE: GREEN"
  exit 0
fi

echo "RED [bypass_receipt_host_path_published] a receipt's host path reached the publishable artifact"
note "boundary on the emitted artifact: ${ROW_OUT} (rc=$ROW_RC)"
note "the Statement carries the token: $([ "$STATEMENT_CARRIES" -eq 1 ] && echo yes || echo no)"
note "ADR-020 D1: the leak is correlated with the run being USEFUL -- a run that contributes is a run"
note "whose baseline failed, and its receipt carries the path. It is the modal case, not an edge."
echo "receipt_host_path_published BYPASS FIXTURE: RED"
exit 1
