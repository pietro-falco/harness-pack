#!/usr/bin/env bash
# FT-36 -- the suite never enumerates the machine it needs, and the README's
# guarantees are bound to nothing. The falsifier for ADR-027 D1 and D2, and it
# ships RED by construction: ADR-027 is Proposed, so neither subject exists in
# this tree yet.
#
# WHY A FALSIFIER SHIPS BESIDE A PROPOSED ADR. scripts/gate_adr_contract.sh
# rejects a change that ADDS a file under docs/adrs/ and touches nothing on the
# measured surface, while the two-commit lifecycle wants a Proposed ADR to be
# docs-only. The two rules together make a Proposed ADR unproposable. ADR-027
# resolves it by shipping THIS file instead of an implementation: a falsifier
# states the question, it does not answer it, so "no code against a Proposed
# ADR" is intact -- and the commit touches tests/*.sh, so the contract gate is
# satisfied by the thing the ADR is actually accountable to. The register row
# declares RED, which is the only honest literal for a control whose subject
# does not exist.
#
# THE TWO SUBJECTS, both absent at this basis and both named by ADR-027:
#
#   D1  scripts/preflight_env.sh --report
#       enumerates the suite's external prerequisites and the effective uid
#       BEFORE any invariant runs. One `absent <name>` line per prerequisite
#       that does not resolve, one `uid <n>` line always. Exit 0 when the
#       environment is complete, exit 3 when a name is missing. Neither is a
#       failure: the names the report carries are what route the invariants
#       that need them to UNMEASURED, because a FAIL must accuse the code and
#       never the machine.
#
#   D2  scripts/gate_readme_claims.sh --readme F --claims F --verdicts F
#       every README line stating a guarantee carries a trailing
#       `[claim: <id>]` marker. Exit 0 when every marker cites an id present in
#       the claims file and green in the verdicts file, exit 1 when one does
#       not, exit 2 when an input is missing or malformed.
#
# THE ARMS, in both directions, because a zero that cannot move is not a
# measurement:
#
#   D1-neg  a PATH resolving git and not node   want `absent node`, rc 3
#   D1-pos  the same PATH plus node             want no `absent node`, a `uid`
#                                               line, and rc 0 or 3
#   D2-neg  a README citing an id absent from the claims file, with every real
#           claim green in the verdicts file so that the absent id is the only
#           ground left to refuse on                                want rc 1
#   D2-pos  a README citing a real id, green in the same file       want rc 0
#
# EVERY ARM IS CHECKED AFTER IT IS BUILT and a scenario that did not get built
# is FIXTURE BROKEN (exit 2), never a verdict. `|| exit 2` inside a command
# substitution leaves the subshell and nothing else, so no constructor here
# runs inside one.
#
# STATES. RED (exit 1): a subject is absent, or present and answering an arm
# wrongly. GREEN (exit 0): all four arms answer as declared. BROKEN (exit 2):
# this host cannot carry the scenario -- which is itself an instance of the
# defect D1 names, and is reported in those words rather than disguised.
#
# DECLARED RED, and RED is what this basis holds: neither scripts/preflight_env.sh
# nor scripts/gate_readme_claims.sh exists, so every arm reports an absent
# subject rather than a wrong answer, and each says which absence it is
# reporting.
set -uo pipefail

note()   { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

PACK="$(cd "$(dirname "$0")/.." && pwd)" || broken "could not resolve the pack root from \$0"
PREFLIGHT="$PACK/scripts/preflight_env.sh"
GATE="$PACK/scripts/gate_readme_claims.sh"
CLAIMS="$PACK/.verity/claims.json"
DOC="$PACK/README.md"

[ -f "$CLAIMS" ] || broken ".verity/claims.json is not where this fixture expects it"
[ -f "$DOC" ]    || broken "README.md is not where this fixture expects it"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-ft36.XXXXXX")" || broken "mktemp -d failed"
trap 'rm -rf "$WORK"' EXIT

echo "== FT-36 the environment goes unenumerated, and no README guarantee cites a claim =="

red=0

# ---- D1: the two doctored PATHs -------------------------------------------
# The shim is a directory of symlinks and nothing else, so a tool is absent
# from it exactly when this fixture chose to omit it. Prefixing $PATH could
# never hide anything: a stand-in named `node` still resolves.
SHIM_TOOLS=(git python3 node shellcheck gitleaks ssh-keygen ssh-agent
            shasum tar cmp diff bash sh env sed grep awk)

build_shim() {
  local dir=$1 omit=$2 t src
  mkdir -p "$dir" || return 1
  for t in "${SHIM_TOOLS[@]}"; do
    [ "$t" = "$omit" ] && continue
    src=$(command -v "$t" 2>/dev/null) || continue
    [ -n "$src" ] || continue
    ln -s "$src" "$dir/$t" || return 1
  done
  return 0
}

resolves() ( PATH="$1"; export PATH; command -v "$2" >/dev/null 2>&1 )

command -v node >/dev/null 2>&1 \
  || broken "node does not resolve on this host, so the arm in which it is PRESENT cannot be built, and this row could not separate 'the preflight is absent' from 'the tool is absent'"
command -v git >/dev/null 2>&1 \
  || broken "git does not resolve on this host, so the canary proving the doctored PATH hides node and nothing else cannot be built"

SHIM_NEG="$WORK/path-without-node"
SHIM_POS="$WORK/path-with-node"
build_shim "$SHIM_NEG" node || broken "could not build the PATH that hides node"
build_shim "$SHIM_POS" ""   || broken "could not build the PATH that carries node"

resolves "$SHIM_NEG" node && broken "the D1-neg PATH still resolves node, so the scenario was not built and any absence measured through it would be somebody else's"
resolves "$SHIM_NEG" git  || broken "the D1-neg PATH resolves neither node nor git, so it hides everything and an absence measured through it names nothing in particular"
resolves "$SHIM_POS" node || broken "the D1-pos PATH does not resolve node, so the positive control was not built and the neg arm's zero cannot be shown to move"
resolves "$SHIM_POS" git  || broken "the D1-pos PATH does not resolve git"

note "arm control: the D1-neg PATH resolves git and not node; the D1-pos PATH resolves both"

if [ ! -f "$PREFLIGHT" ]; then
  red=1
  echo "RED [D1] scripts/preflight_env.sh does not exist: nothing enumerates this suite's prerequisites, or its uid, before the first invariant runs"
  note "this arm is RED because the PREFLIGHT is absent, not because a prerequisite is:"
  note "node and git both resolve on this host, and the two doctored PATHs above were"
  note "built and checked before the subject was asked anything"
  note "with no preflight, an absent prerequisite reaches the invariant that needs it and"
  note "the invariant fails: tests/run_tests.sh carries exactly one command -v in its"
  note "whole length and it guards shellcheck alone, which degrades to record_unmeasured;"
  note "every other prerequisite is checked inside a fixture, by a broken() that exits 2,"
  note "and the register's D4 routes that to FAIL -- the code accused for the machine"
  note "D1-pos cannot discriminate against an absent subject: a program that does not"
  note "exist names nothing under either PATH, so its silence here is vacuous, and that"
  note "vacuity is reported rather than counted as an arm that passed"
else
  ( PATH="$SHIM_NEG"; export PATH; bash "$PREFLIGHT" --report ) >"$WORK/d1-neg.out" 2>&1
  d1_neg_rc=$?
  ( PATH="$SHIM_POS"; export PATH; bash "$PREFLIGHT" --report ) >"$WORK/d1-pos.out" 2>&1
  d1_pos_rc=$?

  if grep -q '^absent node$' "$WORK/d1-neg.out" && [ "$d1_neg_rc" -eq 3 ]; then
    note "D1-neg: the preflight names node absent and exits 3"
  else
    red=1
    echo "RED [D1-neg] a prerequisite absent from PATH is not named by the preflight (rc=$d1_neg_rc)"
    sed 's/^/      | /' "$WORK/d1-neg.out"
  fi

  if grep -q '^absent node$' "$WORK/d1-pos.out"; then
    red=1
    echo "RED [D1-pos] the preflight names node absent on a PATH that resolves it, so the report is not reading the environment"
    sed 's/^/      | /' "$WORK/d1-pos.out"
  elif ! grep -q '^uid ' "$WORK/d1-pos.out"; then
    red=1
    echo "RED [D1-pos] the report carries no uid line, so the uid half of D1 is undeclared"
    sed 's/^/      | /' "$WORK/d1-pos.out"
  elif [ "$d1_pos_rc" -ne 0 ] && [ "$d1_pos_rc" -ne 3 ]; then
    red=1
    echo "RED [D1-pos] the preflight exited $d1_pos_rc, which is neither 0 (complete) nor 3 (a name is missing)"
  else
    note "D1-pos: the preflight does not name node on a PATH that resolves it, and reports the uid"
  fi
fi

# ---- D2: the two doctored documents ---------------------------------------
REAL_ID="publication-boundary-statement-allowlist"
FAKE_ID="ft36-no-such-claim-id"

grep -Fq "\"$REAL_ID\"" "$CLAIMS" \
  || broken "the id this fixture cites as REAL is absent from .verity/claims.json, so the positive arm would measure the wrong thing"
grep -Fq "$FAKE_ID" "$CLAIMS" \
  && broken "the id this fixture cites as ABSENT is present in .verity/claims.json, so the negative arm would measure the wrong thing"

VERDICTS="$WORK/verdicts"
grep -o '"id": "[^"]*"' "$CLAIMS" | sed -e 's/^"id": "//' -e 's/"$//' -e 's/$/ green/' > "$VERDICTS"
[ -s "$VERDICTS" ] || broken "could not derive a verdicts file from .verity/claims.json"
grep -Fqx "$REAL_ID green" "$VERDICTS" \
  || broken "the derived verdicts file does not carry the real id as green, so the positive arm has no green claim to cite"
grep -Fq "$FAKE_ID" "$VERDICTS" \
  && broken "the derived verdicts file carries the id that is supposed to be absent everywhere"

DOC_NEG="$WORK/README-cites-absent-claim.md"
DOC_POS="$WORK/README-cites-green-claim.md"
cp "$DOC" "$DOC_NEG" || broken "could not copy README.md for the D2-neg arm"
cp "$DOC" "$DOC_POS" || broken "could not copy README.md for the D2-pos arm"
BULLET="- **Tamper gate on the deployed copy**: the deployed pack's integrity is verified against a pinned hash before every run."
printf '%s [claim: %s]\n' "$BULLET" "$FAKE_ID" >> "$DOC_NEG"
printf '%s [claim: %s]\n' "$BULLET" "$REAL_ID" >> "$DOC_POS"

grep -Fq "[claim: $FAKE_ID]" "$DOC_NEG" || broken "the D2-neg document does not carry the marker this arm is about"
grep -Fq "[claim: $REAL_ID]" "$DOC_POS" || broken "the D2-pos document does not carry the marker this arm is about"
grep -Fq "[claim: $FAKE_ID]" "$DOC_POS" && broken "the D2-pos document carries the absent id too, so the two arms are not separated"

note "arm control: one document cites an id absent from the claims file, the other an id present there and green in the derived verdicts"

if [ ! -f "$GATE" ]; then
  red=1
  echo "RED [D2] scripts/gate_readme_claims.sh does not exist: no line of README.md is bound to any claim, and its guarantees cannot be falsified by the apparatus this repo uses for everything else"
  note "this arm is RED because the GATE is absent, not because a claim id is: both"
  note "documents were built and checked, and the verdicts file marks every real claim"
  note "green, so an absent id is the only ground the gate could refuse the first on"
  note "D2-pos cannot discriminate against an absent subject: a gate that does not exist"
  note "refuses nothing, and a refusal that never happens is not an acceptance"
else
  bash "$GATE" --readme "$DOC_NEG" --claims "$CLAIMS" --verdicts "$VERDICTS" >"$WORK/d2-neg.out" 2>&1
  d2_neg_rc=$?
  bash "$GATE" --readme "$DOC_POS" --claims "$CLAIMS" --verdicts "$VERDICTS" >"$WORK/d2-pos.out" 2>&1
  d2_pos_rc=$?

  if [ "$d2_neg_rc" -eq 1 ]; then
    note "D2-neg: the gate refuses a guarantee citing an id the claims file does not carry"
  else
    red=1
    echo "RED [D2-neg] the gate accepted a guarantee citing $FAKE_ID (rc=$d2_neg_rc, want 1)"
    sed 's/^/      | /' "$WORK/d2-neg.out"
  fi

  if [ "$d2_pos_rc" -eq 0 ]; then
    note "D2-pos: the gate accepts a guarantee citing an id that exists and is green"
  else
    red=1
    echo "RED [D2-pos] the gate refused a guarantee citing $REAL_ID (rc=$d2_pos_rc, want 0); a gate that refuses both arms binds nothing"
    sed 's/^/      | /' "$WORK/d2-pos.out"
  fi
fi

if [ "$red" -ne 0 ]; then
  echo "FT-36 BYPASS FIXTURE: RED"
  exit 1
fi

echo "GREEN [FT-36] the environment is enumerated by name before the suite runs, and a README guarantee stands or falls with a claim"
echo "FT-36 BYPASS FIXTURE: GREEN"
exit 0
