#!/usr/bin/env bash
# Fixture for scripts/gate_preamble.sh -- the commit-side gate preamble.
#
# THE PREAMBLE IS AN ERROR DETECTOR, NOT A BOUNDARY, and its own header says so.
# What this file can therefore assert is exactly one thing: that when the
# preamble IS called, each of its four assertions says GREEN, RED or UNMEASURED
# for the reason it claims to. Nothing here is evidence that a commit could not
# have been produced without calling it.
#
# THIS FIXTURE SIGNS ON PURPOSE, and that is why its scratch repository is NOT
# built through tests/run_tests.sh's init_fixture_repo(). That helper pins
# `commit.gpgsign false` into every repository it makes -- correct for every
# other fixture here and fatal for this one, whose whole subject is the identity
# of a signature. The isolation init_fixture_repo exists for is reproduced
# below by hand instead: identity, format and the allowed-signers file are
# written into the throwaway repositories' own .git/config and nowhere else, no
# global config is read for a verdict or written at all, and the two signing
# keys are generated fresh under $TMPDIR with an empty passphrase. Neither
# ~/.ssh nor the real agent key is opened, and no key that outlives this process
# is ever loaded into an agent.
#
# THE PF FAMILY IS DRIVEN BY A STUB `ssh-add`, NOT BY AN AGENT, and that is a
# measurement rather than a preference. Measured in this session: bind() on an
# AF_UNIX socket returns EPERM in every directory this process can write -- the
# working tree and $TMPDIR alike -- so ssh-agent has nowhere to publish a
# socket. A family that depends on one is permanently unmeasured in exactly the
# environment that runs it most, which is the environment an agent session
# provides. What gate_preflight_agent actually consumes is the ssh-add CONTRACT:
# an exit status, and at exit 0 one line per identity whose second field is the
# fingerprint. The stub supplies that contract, and every fingerprint it prints
# is COMPOSED from a real public key through `ssh-keygen -lf`. A case asserting
# against a fingerprint this fixture invented would be measuring the fixture.
#
# THE REAL-AGENT ARM SURVIVES, opt-in and off: set GATE_PREAMBLE_REAL_AGENT=1 to
# run the PF-REAL-* cases against a live disposable ssh-agent. It has never been
# observed green anywhere -- not here, not in CI -- because no environment this
# code has run in would let ssh-agent bind. It is kept because the day one does,
# the stub's fidelity becomes a question someone can answer instead of assume.
#
# STATES, in the three-state grammar this suite already speaks:
#   PASSED (0)      every case observed the verdict it declares below.
#   FAILED (1)      a case observed a different verdict. That is a defect in the
#                   preamble, or in this fixture, and it is cleared by hand.
#   UNMEASURED (2)  a case never reached its question -- a control did not
#                   behave, or the opt-in real-agent arm was asked for and the
#                   agent would not start. Not a pass and not an accusation.
#                   2, not the preamble's own 3: the exit code a FIXTURE gives
#                   this suite for "not measured" is 2 everywhere in tests/, and
#                   the register in tests/run_tests.sh reads that number.
#   With the real-agent arm off, which is the default, no case here depends on
#   anything the environment may refuse. That is why tests/run_tests.sh registers
#   this fixture on a flat row and adds nothing to UNMEASURED_REGISTER.
#
# Every case prints its own name, the verdict it expects, and the verdict it
# observed. The RED and UNMEASURED expectations are expectations like any other:
# a preamble that answered GREEN to them would be the defect.
#
# Run standalone: bash tests/gate_preamble_fixture.sh
# Point GATE_PREAMBLE at another copy to drive a mutant of the preamble.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PACK="$PWD"
PREAMBLE="${GATE_PREAMBLE:-$PACK/scripts/gate_preamble.sh}"

fail=0
unmeasured=0

if [ ! -r "$PREAMBLE" ]; then
  echo "UNMEASURED: no preamble at $PREAMBLE" >&2
  exit 2
fi

# Templated under $TMPDIR for the reason tests/run_tests.sh states at its head:
# a bare `mktemp -d` on BSD ignores $TMPDIR and reaches for a directory an agent
# session's sandbox denies.
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/gate_preamble.XXXXXX")" || exit 2
AGENT_PID=""
# Inline rather than a cleanup function, and not a stylistic choice: shellcheck
# reads a function reached only through `trap` as unreachable code (SC2317) and
# the pinned gate takes that at --severity=style. Every other fixture here spells
# its trap the same way.
trap 'if [ -n "$AGENT_PID" ]; then kill "$AGENT_PID" 2>/dev/null; fi; rm -rf "$TMPD"' EXIT
OUT="$TMPD/case.out"

# The absolute-home token is ASSEMBLED, never spelled, and the reason is the one
# scripts/statement_lint.py gives at LITERAL_USERS: a file that spells the class
# it detects becomes an instance of it on the public surface this repository
# measures. The runtime string is identical either way, so SHAPE-6 is driven by
# exactly the input the case names.
HOME_WORD=Users

# --------------------------------------------------------------- case plumbing
# The working directory is a PARAMETER, because three of the four assertions read
# it: gate_verify_principal asks git for the configuration of the repository it
# stands in, gate_signing_env is measured by asking git what it now answers, and
# gate_commit_shape falls back to a commit-ish when its argument is not a file.
observe() {  # observe NAME EXPECTED DIR -- command...
  local name="$1" want="$2" dir="$3"; shift 3
  local rc=0
  ( cd "$dir" && exec "$@" ) >"$OUT" 2>&1 || rc=$?
  if [ "$rc" -eq "$want" ]; then
    printf 'ok       [%s] atteso=%s osservato=%s\n' "$name" "$want" "$rc"
  else
    printf 'FAIL     [%s] atteso=%s osservato=%s\n' "$name" "$want" "$rc"
    sed -n '1,4p' "$OUT" | sed 's/^/           /'
    fail=1
  fi
}

unattrib() {  # unattrib NAME EXPECTED REASON
  printf 'unattrib [%s] atteso=%s osservato=3 -- %s\n' "$1" "$2" "$3"
  unmeasured=1
}

broken() {  # broken NAME REASON -- a control did not behave; the case has no subject
  printf 'BROKEN   [%s] %s\n' "$1" "$2" >&2
  unmeasured=1
}

# ------------------------------------------------------------- the two keys
# Two disposable ed25519 keys with an empty passphrase. `< /dev/null` because a
# key file that somehow already exists must not turn this into a prompt.
ssh-keygen -q -t ed25519 -N '' -C 'gate-preamble-fixture-A' -f "$TMPD/kA" </dev/null 2>>"$TMPD/keygen.err" \
  || { echo "UNMEASURED: ssh-keygen could not create key A" >&2; exit 2; }
ssh-keygen -q -t ed25519 -N '' -C 'gate-preamble-fixture-B' -f "$TMPD/kB" </dev/null 2>>"$TMPD/keygen.err" \
  || { echo "UNMEASURED: ssh-keygen could not create key B" >&2; exit 2; }

fingerprint() { ssh-keygen -lf "$1" 2>/dev/null | awk '{print $2}'; }
comment_of() { ssh-keygen -lf "$1" 2>/dev/null | cut -d' ' -f3-; }

FP_A="$(fingerprint "$TMPD/kA.pub")"
FP_B="$(fingerprint "$TMPD/kB.pub")"
if [ -z "$FP_A" ] || [ -z "$FP_B" ] || [ "$FP_A" = "$FP_B" ]; then
  echo "UNMEASURED: the two disposable keys do not have two distinct fingerprints" >&2
  exit 2
fi

# ------------------------------------------------- the scratch repository
REPO="$TMPD/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.invalid
git -C "$REPO" config user.name tester
git -C "$REPO" config gpg.format ssh
git -C "$REPO" config tag.gpgsign false
# Unsigned is the repository default here, and the two signed commits below opt
# in explicitly with -S. The operator's global commit.gpgsign therefore decides
# nothing about what this fixture measures.
git -C "$REPO" config commit.gpgsign false

commit_with() {  # commit_with <signingkey|-> <message>
  printf '%s\n' "$2" > "$REPO/f"
  git -C "$REPO" add -- f || return 1
  if [ "$1" = "-" ]; then
    git -C "$REPO" commit -q -m "$2" || return 1
  else
    git -C "$REPO" -c user.signingkey="$1" commit -qS -m "$2" || return 1
  fi
}

commit_with "$TMPD/kA" "signed by key A" || { echo "UNMEASURED: could not sign with key A" >&2; exit 2; }
C_A="$(git -C "$REPO" rev-parse HEAD)"
commit_with "$TMPD/kB" "signed by key B" || { echo "UNMEASURED: could not sign with key B" >&2; exit 2; }
C_B="$(git -C "$REPO" rev-parse HEAD)"
commit_with "-" "not signed at all" || { echo "UNMEASURED: could not write the unsigned commit" >&2; exit 2; }
C_U="$(git -C "$REPO" rev-parse HEAD)"

# allowed_signers is `PRINCIPAL KEYTYPE BASE64`; the trailing comment of the
# .pub is dropped on purpose, so no case can pass or fail on a comment.
signers_line() { printf '%s %s\n' "$1" "$(cut -d' ' -f1,2 < "$2")"; }
signers_line 'agent-cc@harness-pack.invalid' "$TMPD/kA.pub" > "$TMPD/signers_agent"
signers_line 'stranger@example.invalid'      "$TMPD/kB.pub" > "$TMPD/signers_stranger"

use_signers() { git -C "$REPO" config gpg.ssh.allowedSignersFile "$1"; }

echo "== gate_preamble: signature identity (gate_verify_principal) =="

use_signers "$TMPD/signers_agent"
observe VP-GREEN-agent-principal 0 "$REPO" bash "$PREAMBLE" verify-principal "$C_A"

# The control that gives this case its subject, and the trap the preamble's own
# header names: with no principal matched, `git verify-commit` still opens with
# "Good ..." and exits non-zero. A gate reading that output instead of the exit
# status passes this commit. If either half of the control stops holding, the
# RED below would be red for some other reason and is not claimed.
VC_OUT="$( (cd "$REPO" && git verify-commit "$C_B") 2>&1 )"
VC_RC=$?
G_B="$(git -C "$REPO" log -1 --format='%G?' "$C_B")"
case "$VC_OUT" in
  Good*) VC_SAYS_GOOD=1 ;;
  *)     VC_SAYS_GOOD=0 ;;
esac
if [ "$VC_RC" -eq 0 ] || [ "$VC_SAYS_GOOD" -ne 1 ] || [ "$G_B" != "U" ]; then
  broken VP-RED-no-principal-matched \
    "control: wanted verify-commit rc!=0 with a \"Good\" first line and %G?=U, got rc=$VC_RC good=$VC_SAYS_GOOD %G?=$G_B"
else
  observe VP-RED-no-principal-matched 1 "$REPO" bash "$PREAMBLE" verify-principal "$C_B"
fi

# The other side of the same coin: the signature is good AND a principal matched,
# so every textual reading of verify-commit says yes. Only the identity is wrong.
use_signers "$TMPD/signers_stranger"
( cd "$REPO" && git verify-commit "$C_B" >/dev/null 2>&1 )
VC_RC=$?
G_B="$(git -C "$REPO" log -1 --format='%G?' "$C_B")"
S_B="$(git -C "$REPO" log -1 --format='%GS' "$C_B")"
if [ "$VC_RC" -ne 0 ] || [ "$G_B" != "G" ] || [ "$S_B" != "stranger@example.invalid" ]; then
  broken VP-RED-wrong-principal \
    "control: wanted verify-commit rc=0, %G?=G, %GS=stranger@example.invalid; got rc=$VC_RC %G?=$G_B %GS=$S_B"
else
  observe VP-RED-wrong-principal 1 "$REPO" bash "$PREAMBLE" verify-principal "$C_B"
fi

use_signers "$TMPD/signers_agent"
G_U="$(git -C "$REPO" log -1 --format='%G?' "$C_U")"
if [ "$G_U" != "N" ]; then
  broken VP-RED-unsigned "control: wanted %G?=N on the unsigned commit, got %G?=$G_U"
else
  observe VP-RED-unsigned 1 "$REPO" bash "$PREAMBLE" verify-principal "$C_U"
fi

# Not a verdict about the commit: the configuration the verdict would rest on
# does not resolve, so no verdict is reached.
use_signers "$TMPD/no-such-allowed-signers"
observe VP-UNMEASURED-no-signers 3 "$REPO" bash "$PREAMBLE" verify-principal "$C_A"
use_signers "$TMPD/signers_agent"

echo "== gate_preamble: signing configuration (gate_signing_env) =="

# gate_signing_env MUTATES THE ENVIRONMENT OF ITS CALLER, so every case here
# sources the preamble and asks git the question inside the SAME process. Running
# `bash "$PREAMBLE" signing-env` instead would measure a subprocess that has
# already exited by the time the question is asked, and would answer nothing.
# This is the function that takes the signature off the human key; it shipped
# without a case.
SEREPO="$TMPD/serepo"
mkdir -p "$SEREPO"
git -C "$SEREPO" init -q
git -C "$SEREPO" config user.email t@example.invalid
git -C "$SEREPO" config user.name tester
# The repository's own config file names key B. Every case below asks which
# answer git gives when the process environment names key A instead.
git -C "$SEREPO" config user.signingkey "$TMPD/kB"

# The four probes below are FILES rather than `bash -c` strings, and not for
# taste: a single-quoted inline script is the only form that keeps the expansion
# inside the child, and shellcheck reads every one of them as SC2016 at
# --severity=style. Writing them out asks the same question with nothing to
# suppress.
cat > "$TMPD/se_control.sh" <<'SEC'
#!/usr/bin/env bash
# $1 is the signing key the repository's own config file names.
got="$(git config --get user.signingkey)"
if [ "$got" != "$1" ]; then
  printf 'control: user.signingkey=%s, want %s\n' "$got" "$1" >&2
  exit 1
fi
SEC

cat > "$TMPD/se_precedence.sh" <<'SEP'
#!/usr/bin/env bash
# $1 is the preamble. SOURCED: gate_signing_env mutates the caller.
. "$1" || exit 2
gate_signing_env >/dev/null 2>&1 || exit $?
got="$(git config --get user.signingkey)"
if [ "$got" != "$GATE_AGENT_PUB" ]; then
  printf 'user.signingkey=%s, want %s\n' "$got" "$GATE_AGENT_PUB" >&2
  exit 1
fi
SEP

cat > "$TMPD/se_append.sh" <<'SEA'
#!/usr/bin/env bash
# $1 is the preamble; $2 is the GIT_CONFIG_COUNT this run must end on.
. "$1" || exit 2
gate_signing_env >/dev/null 2>&1 || exit $?
if [ "$GIT_CONFIG_COUNT" != "$2" ]; then
  printf 'GIT_CONFIG_COUNT=%s, want %s\n' "$GIT_CONFIG_COUNT" "$2" >&2
  exit 1
fi
got="$(git config --get user.name)"
if [ "$got" != "preexisting" ]; then
  printf 'the preexisting pair did not survive: user.name=%s\n' "$got" >&2
  exit 1
fi
got="$(git config --get user.signingkey)"
if [ "$got" != "$GATE_AGENT_PUB" ]; then
  printf 'user.signingkey=%s, want %s\n' "$got" "$GATE_AGENT_PUB" >&2
  exit 1
fi
SEA

cat > "$TMPD/se_status.sh" <<'SES'
#!/usr/bin/env bash
# $1 is the preamble. Reports gate_signing_env's own exit status and nothing else.
. "$1" || exit 2
gate_signing_env >/dev/null 2>&1
exit $?
SES

# Without this the case under it demonstrates nothing: an env pair that agrees
# with the file it is supposed to outrank is not evidence of precedence.
observe SE-CONTROL-local-file-wins 0 "$SEREPO" \
  bash "$TMPD/se_control.sh" "$TMPD/kB"

observe SE-GREEN-env-beats-local-file 0 "$SEREPO" \
  env "GATE_AGENT_PUB=$TMPD/kA.pub" "GATE_ALLOWED_SIGNERS=$TMPD/signers_agent" \
  bash "$TMPD/se_precedence.sh" "$PREAMBLE"

# Four pairs appended to one already present. A gate_signing_env that started
# from zero would silently unset whatever the caller had configured, and the
# count alone would not show it -- so the preexisting pair is read back too.
observe SE-GREEN-appends-to-count 0 "$SEREPO" \
  env "GATE_AGENT_PUB=$TMPD/kA.pub" "GATE_ALLOWED_SIGNERS=$TMPD/signers_agent" \
      GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=preexisting \
  bash "$TMPD/se_append.sh" "$PREAMBLE" 5

# No configuration is written at all when the key it would point at cannot be
# read: that is UNMEASURED, and it is not a quiet fallback to whatever the
# operator's own config already says.
observe SE-UNMEASURED-agent-pub-gone 3 "$SEREPO" \
  env "GATE_AGENT_PUB=$TMPD/no-such-agent-key.pub" "GATE_ALLOWED_SIGNERS=$TMPD/signers_agent" \
  bash "$TMPD/se_status.sh" "$PREAMBLE"

echo "== gate_preamble: ssh-agent preflight (gate_preflight_agent) =="

# The deny-list is read before the agent is, so this one case measures whatever
# ssh-add happens to be on $PATH and whether or not one exists at all.
observe PF-UNMEASURED-denylist-gone 3 "$TMPD" \
  env GATE_DENY_PUBKEYS="$TMPD/no-such-key.pub" bash "$PREAMBLE" preflight-agent

# ------------------------------------------------------- the stub ssh-add
STUBDIR="$TMPD/stub"
STUB_MARKER="$TMPD/stub.invoked"
# Non-empty and never bound. gate_preflight_agent reads SSH_AUTH_SOCK for
# non-emptiness only before it invokes ssh-add, and the stub never connects.
FAKE_SOCK="$TMPD/there-is-no-socket-here"
mkdir -p "$STUBDIR"
cat > "$STUBDIR/ssh-add" <<'STUB'
#!/usr/bin/env bash
# Stand-in for ssh-add, first on $PATH for the PF cases only. It does not
# simulate an agent: it supplies the ssh-add contract the preamble reads, and
# every identity line it prints was composed by the caller from a real public
# key through `ssh-keygen -lf`.
if [ -n "${FIXTURE_STUB_MARKER:-}" ]; then
  : > "$FIXTURE_STUB_MARKER"
fi
if [ -n "${FIXTURE_STUB_OUT:-}" ] && [ -r "$FIXTURE_STUB_OUT" ]; then
  cat -- "$FIXTURE_STUB_OUT"
fi
exit "${FIXTURE_STUB_RC:-0}"
STUB
chmod +x "$STUBDIR/ssh-add"

# The identity lines, composed rather than written. `$3` is the comment field of
# `ssh-keygen -lf` output; assigning it leaves the fingerprint in `$2` untouched,
# which is the whole point of the renamed case.
ssh-keygen -lf "$TMPD/kA.pub" > "$TMPD/line_kA" 2>/dev/null
ssh-keygen -lf "$TMPD/kB.pub" > "$TMPD/line_kB" 2>/dev/null
awk -v c='an-entirely-unrelated-comment' '{ $3 = c; print }' "$TMPD/line_kA" > "$TMPD/line_renamed"
: > "$TMPD/line_none"

pf_case() {  # pf_case NAME EXPECTED STUB_EXIT STUB_OUTPUT_FILE
  local name="$1" want="$2" srrc="$3" sout="$4" rc=0
  rm -f "$STUB_MARKER"
  ( cd "$TMPD" && exec env "PATH=$STUBDIR:$PATH" "SSH_AUTH_SOCK=$FAKE_SOCK" \
      "FIXTURE_STUB_MARKER=$STUB_MARKER" "FIXTURE_STUB_RC=$srrc" "FIXTURE_STUB_OUT=$sout" \
      "GATE_DENY_PUBKEYS=$TMPD/kA.pub" bash "$PREAMBLE" preflight-agent ) >"$OUT" 2>&1 || rc=$?
  if [ ! -e "$STUB_MARKER" ]; then
    broken "$name" "control: the stub ssh-add was not what ran, so this verdict is about some other ssh-add"
    return 0
  fi
  if [ "$rc" -eq "$want" ]; then
    printf 'ok       [%s] atteso=%s osservato=%s\n' "$name" "$want" "$rc"
  else
    printf 'FAIL     [%s] atteso=%s osservato=%s\n' "$name" "$want" "$rc"
    sed -n '1,4p' "$OUT" | sed 's/^/           /'
    fail=1
  fi
}

# THE CONTROL THAT MAKES THE REST OF THE FAMILY MEAN ANYTHING. A $PATH that did
# not take sends every case below to the real ssh-add, which -- pointed at a
# socket that does not exist -- exits 2 and drives the preamble to GREEN. The
# exit status alone therefore cannot tell a working stub from an absent one:
# only the marker can.
rm -f "$STUB_MARKER"
pf_rc=0
( cd "$TMPD" && exec env "PATH=$STUBDIR:$PATH" "SSH_AUTH_SOCK=$FAKE_SOCK" \
    "FIXTURE_STUB_MARKER=$STUB_MARKER" "FIXTURE_STUB_RC=1" "FIXTURE_STUB_OUT=$TMPD/line_none" \
    "GATE_DENY_PUBKEYS=$TMPD/kA.pub" bash "$PREAMBLE" preflight-agent ) >"$OUT" 2>&1 || pf_rc=$?
if [ -e "$STUB_MARKER" ]; then stub_seen=yes; else stub_seen=no; fi
if [ "$stub_seen" = "yes" ] && [ "$pf_rc" -eq 0 ]; then
  printf 'ok       [PF-CONTROL-stub-is-invoked] atteso=0 osservato=%s\n' "$pf_rc"
else
  printf 'FAIL     [PF-CONTROL-stub-is-invoked] atteso=0 osservato=%s -- stub invoked: %s\n' \
    "$pf_rc" "$stub_seen"
  sed -n '1,4p' "$OUT" | sed 's/^/           /'
  fail=1
fi

pf_case PF-GREEN-empty-agent      0 1 "$TMPD/line_none"
pf_case PF-GREEN-agent-unreachable 0 2 "$TMPD/line_none"
pf_case PF-RED-denied-key-loaded  1 0 "$TMPD/line_kA"

# The same key material under another comment. The deny-list still names the
# ORIGINAL .pub: matching is on fingerprint, so the one thing the holder controls
# has changed and the verdict must not.
LINE_R_FP="$(awk '{print $2}' "$TMPD/line_renamed")"
LINE_R_COMMENT="$(awk '{print $3}' "$TMPD/line_renamed")"
LINE_A_COMMENT="$(awk '{print $3}' "$TMPD/line_kA")"
if [ "$LINE_R_FP" != "$FP_A" ] || [ -z "$LINE_A_COMMENT" ] || [ "$LINE_R_COMMENT" = "$LINE_A_COMMENT" ]; then
  broken PF-RED-denied-key-renamed \
    "control: wanted key A's fingerprint under a different comment, got fp=$LINE_R_FP comment=$LINE_R_COMMENT vs $LINE_A_COMMENT"
else
  pf_case PF-RED-denied-key-renamed 1 0 "$TMPD/line_renamed"
fi

# The negative control of the family: an agent that holds a key, just not that
# one. A preflight answering RED here answers RED to every agent.
LINE_B_FP="$(awk '{print $2}' "$TMPD/line_kB")"
if [ "$LINE_B_FP" != "$FP_B" ]; then
  broken PF-GREEN-other-key-loaded "control: the composed key B line carries fp=$LINE_B_FP, want $FP_B"
else
  pf_case PF-GREEN-other-key-loaded 0 0 "$TMPD/line_kB"
fi

# --------------------------------------------------- the real-agent arm (opt-in)
# Off by default for the reason this file's header measures: bind() on an
# AF_UNIX socket is refused in every writable directory this process has, so
# ssh-agent cannot publish one. Never observed green in any environment.
if [ "${GATE_PREAMBLE_REAL_AGENT:-0}" = "1" ]; then
  SOCK="$TMPD/a.sock"
  AGENT_WHY=""
  if ssh-agent -a "$SOCK" -s >"$TMPD/agent.env" 2>&1; then
    AGENT_PID="$(sed -n 's/^SSH_AGENT_PID=\([0-9][0-9]*\);.*/\1/p' "$TMPD/agent.env")"
    if [ -z "$AGENT_PID" ] || [ ! -S "$SOCK" ]; then
      AGENT_WHY="ssh-agent started but published no pid or no socket"
      AGENT_PID=""
    fi
  else
    AGENT_WHY="ssh-agent refused: $(head -n 1 "$TMPD/agent.env" | cut -c1-120)"
  fi

  agent_add() { SSH_AUTH_SOCK="$SOCK" ssh-add -q "$1" </dev/null 2>/dev/null; }
  agent_clear() { SSH_AUTH_SOCK="$SOCK" ssh-add -D >/dev/null 2>&1; }

  if [ -z "$AGENT_PID" ]; then
    unattrib PF-REAL-empty-agent      0 "$AGENT_WHY"
    unattrib PF-REAL-denied-key-loaded  1 "$AGENT_WHY"
    unattrib PF-REAL-denied-key-renamed 1 "$AGENT_WHY"
    unattrib PF-REAL-other-key-loaded 0 "$AGENT_WHY"
  else
    agent_clear
    observe PF-REAL-empty-agent 0 "$TMPD" \
      env SSH_AUTH_SOCK="$SOCK" GATE_DENY_PUBKEYS="$TMPD/kA.pub" bash "$PREAMBLE" preflight-agent

    if ! agent_add "$TMPD/kA"; then
      broken PF-REAL-denied-key-loaded "control: the agent would not take key A"
    else
      observe PF-REAL-denied-key-loaded 1 "$TMPD" \
        env SSH_AUTH_SOCK="$SOCK" GATE_DENY_PUBKEYS="$TMPD/kA.pub" bash "$PREAMBLE" preflight-agent
    fi

    agent_clear
    cp "$TMPD/kA" "$TMPD/renamed" && cp "$TMPD/kA.pub" "$TMPD/renamed.pub"
    chmod 600 "$TMPD/renamed"
    ssh-keygen -q -c -P '' -C 'an entirely unrelated comment' -f "$TMPD/renamed" >/dev/null 2>&1
    FP_R="$(fingerprint "$TMPD/renamed.pub")"
    if [ "$FP_R" != "$FP_A" ] || [ "$(comment_of "$TMPD/renamed.pub")" = "$(comment_of "$TMPD/kA.pub")" ]; then
      broken PF-REAL-denied-key-renamed \
        "control: wanted the same fingerprint under a different comment, got fp=$FP_R vs $FP_A"
    elif ! agent_add "$TMPD/renamed"; then
      broken PF-REAL-denied-key-renamed "control: the agent would not take the renamed copy"
    else
      observe PF-REAL-denied-key-renamed 1 "$TMPD" \
        env SSH_AUTH_SOCK="$SOCK" GATE_DENY_PUBKEYS="$TMPD/kA.pub" bash "$PREAMBLE" preflight-agent
    fi

    agent_clear
    if ! agent_add "$TMPD/kB"; then
      broken PF-REAL-other-key-loaded "control: the agent would not take key B"
    else
      observe PF-REAL-other-key-loaded 0 "$TMPD" \
        env SSH_AUTH_SOCK="$SOCK" GATE_DENY_PUBKEYS="$TMPD/kA.pub" bash "$PREAMBLE" preflight-agent
    fi
    agent_clear
  fi
fi

echo "== gate_preamble: commit message form (gate_commit_shape) =="

MSG="$TMPD/msg"
printf 'docs(gate): a subject and nothing else\n' > "$MSG.subject_only"
observe CS-GREEN-subject-only 0 "$REPO" bash "$PREAMBLE" commit-shape "$MSG.subject_only"

# A relative path and the bare word are both legitimate message content. A
# SHAPE-6 that fired on either would make the gate unusable for the commits it
# is meant to admit.
{
  printf 'docs(gate): a body that carries a relative path\n\n'
  printf 'The decision is docs/adrs/ADR-083.md and the reasoning is beside it.\n'
  printf '%s of this gate read that file before wiring anything.\n' "$HOME_WORD"
} > "$MSG.relative"
observe CS-GREEN-relative-and-word 0 "$REPO" bash "$PREAMBLE" commit-shape "$MSG.relative"

LONG_SUBJ="docs(gate): "
while [ "${#LONG_SUBJ}" -lt 90 ]; do LONG_SUBJ="${LONG_SUBJ}x"; done
printf '%s\n' "$LONG_SUBJ" > "$MSG.long"
if [ "${#LONG_SUBJ}" -ne 90 ]; then
  broken CS-RED-subject-too-long "control: wanted a 90-character subject, built ${#LONG_SUBJ}"
else
  observe CS-RED-subject-too-long 1 "$REPO" bash "$PREAMBLE" commit-shape "$MSG.long"
fi

# The one surface-separation class this thread has already produced. The path is
# a fiction assembled at run time; the operator's real home appears nowhere.
{
  printf 'docs(gate): a body that spells an absolute path\n\n'
  printf 'The file lives at /%s/exampleuser/Code/thing on the machine that wrote it.\n' "$HOME_WORD"
} > "$MSG.abshome"
observe CS-RED-absolute-home-path 1 "$REPO" bash "$PREAMBLE" commit-shape "$MSG.abshome"

{
  printf 'docs(gate): a body that starts on line two\n'
  printf 'No blank line separates this from the subject.\n'
} > "$MSG.noblank"
observe CS-RED-missing-blank-line 1 "$REPO" bash "$PREAMBLE" commit-shape "$MSG.noblank"

# The marker sits on line 3 with line 2 blank, so SHAPE-5 is the only assertion
# that can be the reason for the RED.
{
  printf 'docs(gate): a body carrying a conflict marker\n\n'
  printf '<<<<<<< ours\n'
} > "$MSG.conflict"
observe CS-RED-conflict-marker 1 "$REPO" bash "$PREAMBLE" commit-shape "$MSG.conflict"

if [ "$fail" -ne 0 ]; then
  echo "GATE PREAMBLE FIXTURE: FAILED"
  exit 1
fi
if [ "$unmeasured" -ne 0 ]; then
  echo "GATE PREAMBLE FIXTURE: UNMEASURED -- see the unattrib/BROKEN lines above; not a pass, not a fail"
  exit 2
fi
echo "GATE PREAMBLE FIXTURE: PASSED"
exit 0
