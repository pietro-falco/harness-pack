#!/usr/bin/env bash
# gate_preamble.sh — commit-side gate preamble. THR-GATE-2, step 1b-C.
#
# WHAT THIS PROVIDES (source it; do not exec it from a hook without reading below)
#   gate_signing_env       agent signing configuration via the process environment
#   gate_preflight_agent   ssh-agent boundary preflight, matched on fingerprint
#   gate_verify_principal  signature identity, from %G? + %GS + exit status
#   gate_commit_shape      commit message form
#   gate_selftest          startup probe; a resolved-but-broken preamble is UNMEASURED
#
# WHAT THIS IS NOT — vault ADR-083 D9
#   This is an ERROR DETECTOR, not a security boundary. A hook invoked by a session
#   inherits that session's sandbox; it is not a more privileged plane. Every check
#   here is bypassed by a caller that declines to call it, by `git commit --no-verify`,
#   or by pointing GATE_PREAMBLE elsewhere. The boundary belongs on pre-receive or CI.
#   Neither exists. Do not cite this file as evidence that a commit could not have been
#   produced some other way. It only reports that a commit in hand does not hold up.
#
# EXIT CODES
#   0  GREEN       the assertion held
#   1  RED         the assertion failed
#   3  UNMEASURED  the assertion was not evaluated (missing tool, missing input,
#                  unresolvable configuration). UNMEASURED is never reported as GREEN
#                  and never as RED.
#
# This file deliberately does not call `set -e` or `set -u`: it is sourced, and those
# would mutate the caller's shell.

GATE_GREEN=0
GATE_RED=1
GATE_UNMEASURED=3
GATE_PREAMBLE_VERSION="1b-C.1"

: "${GATE_AGENT_PUB:=$HOME/.config/harness-signing/agent_ed25519.pub}"
: "${GATE_ALLOWED_SIGNERS:=$HOME/.config/harness-signing/allowed_signers}"
: "${GATE_EXPECTED_PRINCIPAL:=agent-cc@harness-pack.invalid}"
: "${GATE_DENY_PUBKEYS:=$HOME/.ssh/id_ed25519_signing.pub}"   # colon-separated
: "${GATE_SUBJECT_MAX:=72}"

# The two home-root segments SHAPE-6 looks for are ASSEMBLED, never spelled.
# scripts/statement_lint.py does the same at LITERAL_USERS, and
# tests/bypass_ft_flattened_home_form_undetected_fixture.sh says why: a
# detector that writes down the class it detects becomes an instance of it
# on the surface this repository measures. Neither segment is a guess about
# the operator's home -- they are the two platform home roots, and what
# identifies a machine is what follows them.
GATE_HOME_SEG="Users"
GATE_HOME_SEG_ALT="home"

gate_log() { printf 'gate_preamble[%s] %s\n' "$GATE_PREAMBLE_VERSION" "$*" >&2; }

# --- signing configuration through the process environment -------------------
# Writes git "command"-scope config into the environment. Per git-config(1) these
# pairs override every configuration FILE and are themselves overridden only by an
# explicit `git -c`. Consequence: no session has to rewrite commit.gpgsign or
# user.signingkey on disk, and the global config that points at the human key stops
# being the default path. Appends to any GIT_CONFIG_COUNT already present.
gate_signing_env() {
  if [ ! -r "$GATE_AGENT_PUB" ]; then
    gate_log "UNMEASURED signing-env: unreadable $GATE_AGENT_PUB"; return "$GATE_UNMEASURED"
  fi
  if [ ! -r "$GATE_ALLOWED_SIGNERS" ]; then
    gate_log "UNMEASURED signing-env: unreadable $GATE_ALLOWED_SIGNERS"; return "$GATE_UNMEASURED"
  fi
  local n="${GIT_CONFIG_COUNT:-0}"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  local -a pairs=(
    "gpg.format"                  "ssh"
    "user.signingkey"             "$GATE_AGENT_PUB"
    "gpg.ssh.allowedSignersFile"  "$GATE_ALLOWED_SIGNERS"
    "commit.gpgsign"              "true"
  )
  local i=0
  while [ "$i" -lt "${#pairs[@]}" ]; do
    export "GIT_CONFIG_KEY_${n}=${pairs[i]}"
    export "GIT_CONFIG_VALUE_${n}=${pairs[i+1]}"
    n=$((n + 1)); i=$((i + 2))
  done
  export GIT_CONFIG_COUNT="$n"
  gate_log "GREEN signing-env: $((${#pairs[@]} / 2)) pairs, GIT_CONFIG_COUNT=$n"
  return "$GATE_GREEN"
}

# Emits the same thing as eval-able shell, for launchers that cannot source this file.
gate_signing_env_print() {
  ( gate_signing_env >/dev/null 2>&1 || exit $?
    local k
    for k in $(seq 0 $((GIT_CONFIG_COUNT - 1))); do
      eval "printf 'export GIT_CONFIG_KEY_%s=%q\n' \"$k\" \"\$GIT_CONFIG_KEY_$k\""
      eval "printf 'export GIT_CONFIG_VALUE_%s=%q\n' \"$k\" \"\$GIT_CONFIG_VALUE_$k\""
    done
    printf 'export GIT_CONFIG_COUNT=%q\n' "$GIT_CONFIG_COUNT" )
}

# --- ssh-agent preflight -----------------------------------------------------
# A signing key loaded into ssh-agent voids its passphrase: git can sign with it
# unprompted. Nothing else reports this. Matching is on KEY FINGERPRINT only —
# never on the agent comment or on a file name, both of which the holder controls.
gate_preflight_agent() {
  command -v ssh-keygen >/dev/null 2>&1 || {
    gate_log "UNMEASURED preflight: ssh-keygen absent"; return "$GATE_UNMEASURED"; }

  local deny_fps="" f fp saved_ifs="$IFS"
  IFS=':'
  for f in $GATE_DENY_PUBKEYS; do
    IFS="$saved_ifs"
    [ -n "$f" ] || { IFS=':'; continue; }
    if [ ! -r "$f" ]; then
      gate_log "UNMEASURED preflight: deny-list pubkey unreadable: $f"
      IFS="$saved_ifs"; return "$GATE_UNMEASURED"
    fi
    fp=$(ssh-keygen -lf "$f" 2>/dev/null | awk '{print $2}')
    if [ -z "$fp" ]; then
      gate_log "UNMEASURED preflight: no fingerprint from $f"
      IFS="$saved_ifs"; return "$GATE_UNMEASURED"
    fi
    deny_fps="${deny_fps}${fp}"$'\n'
    IFS=':'
  done
  IFS="$saved_ifs"
  [ -n "$deny_fps" ] || {
    gate_log "UNMEASURED preflight: empty deny-list"; return "$GATE_UNMEASURED"; }

  if [ -z "${SSH_AUTH_SOCK:-}" ]; then
    gate_log "GREEN preflight: no ssh-agent in this environment"; return "$GATE_GREEN"
  fi
  command -v ssh-add >/dev/null 2>&1 || {
    gate_log "UNMEASURED preflight: ssh-add absent"; return "$GATE_UNMEASURED"; }

  local loaded rc
  loaded=$(ssh-add -l 2>/dev/null); rc=$?
  case "$rc" in
    1) gate_log "GREEN preflight: agent holds no identities"; return "$GATE_GREEN" ;;
    2) gate_log "GREEN preflight: agent unreachable"; return "$GATE_GREEN" ;;
    0) : ;;
    *) gate_log "UNMEASURED preflight: ssh-add exit $rc"; return "$GATE_UNMEASURED" ;;
  esac

  local afp
  while read -r _ afp _; do
    [ -n "$afp" ] || continue
    if printf '%s' "$deny_fps" | grep -Fxq -- "$afp"; then
      gate_log "RED preflight: deny-listed signing key is loaded in ssh-agent: $afp"
      return "$GATE_RED"
    fi
  done <<EOF
$loaded
EOF
  gate_log "GREEN preflight: no deny-listed fingerprint in agent"
  return "$GATE_GREEN"
}

# --- signature identity ------------------------------------------------------
# Three independent readings, all structural, none textual:
#   git verify-commit  -> exit status only, output discarded
#   %G?                -> must be exactly G
#   %GS                -> must equal the expected principal
# git verify-commit prints "Good ..." on its first line and exits non-zero when no
# principal matched: a gate that searches the output for that string passes a commit
# that must fail. That is why nothing here reads the output.
gate_verify_principal() {
  local commitish="${1:-}" expected="${2:-$GATE_EXPECTED_PRINCIPAL}"
  [ -n "$commitish" ] || { gate_log "UNMEASURED verify_principal: no commit-ish"; return "$GATE_UNMEASURED"; }
  command -v git >/dev/null 2>&1 || { gate_log "UNMEASURED verify_principal: git absent"; return "$GATE_UNMEASURED"; }

  local fmt asf
  fmt=$(git config --get gpg.format 2>/dev/null)
  [ "$fmt" = "ssh" ] || { gate_log "UNMEASURED verify_principal: gpg.format=${fmt:-<unset>}, want ssh"; return "$GATE_UNMEASURED"; }
  asf=$(git config --get gpg.ssh.allowedSignersFile 2>/dev/null)
  [ -n "$asf" ] || { gate_log "UNMEASURED verify_principal: gpg.ssh.allowedSignersFile unset"; return "$GATE_UNMEASURED"; }
  # Not a `case` on a quoted tilde: shellcheck reads a quoted tilde at the
  # start of a word as one that will not expand (SC2088), and the pinned gate
  # takes warnings at --severity=style. The prefix strip asks the same
  # question without writing one; the same expansion on the old line was not
  # flagged, so this form is the measured one.
  if [ "${asf#\~/}" != "$asf" ]; then
    asf="$HOME/${asf#\~/}"
  fi
  [ -r "$asf" ] || { gate_log "UNMEASURED verify_principal: unreadable allowed signers: $asf"; return "$GATE_UNMEASURED"; }
  git rev-parse --verify --quiet "${commitish}^{commit}" >/dev/null 2>&1 || {
    gate_log "UNMEASURED verify_principal: not a commit: $commitish"; return "$GATE_UNMEASURED"; }

  git verify-commit "$commitish" >/dev/null 2>&1
  local vc_rc=$?

  local out status signer
  out=$(git log -1 --format='%G?%n%GS' "$commitish" -- 2>/dev/null) || {
    gate_log "UNMEASURED verify_principal: git log failed on $commitish"; return "$GATE_UNMEASURED"; }
  status=${out%%$'\n'*}
  signer=${out#*$'\n'}
  [ "$signer" != "$status" ] || signer=""

  local ok=1
  [ "$vc_rc" -eq 0 ] || { gate_log "RED verify_principal: verify-commit exit $vc_rc"; ok=0; }
  [ "$status" = "G" ] || { gate_log "RED verify_principal: %G?=${status:-<empty>} want G"; ok=0; }
  [ "$signer" = "$expected" ] || { gate_log "RED verify_principal: %GS=${signer:-<empty>} want $expected"; ok=0; }
  [ "$ok" -eq 1 ] || return "$GATE_RED"
  gate_log "GREEN verify_principal: $commitish %G?=G %GS=$expected verify-commit=0"
  return "$GATE_GREEN"
}

# --- commit message form -----------------------------------------------------
# Argument is a message FILE (commit-msg hook) or a commit-ish.
# SHAPE-6 covers the one surface-separation class this thread has already produced:
# absolute home paths written verbatim into a message. The wider class is open.
gate_commit_shape() {
  local src="${1:-}" msg
  [ -n "$src" ] || { gate_log "UNMEASURED shape: no argument"; return "$GATE_UNMEASURED"; }
  if [ -f "$src" ]; then
    msg=$(git stripspace --strip-comments < "$src" 2>/dev/null) || {
      gate_log "UNMEASURED shape: stripspace failed on $src"; return "$GATE_UNMEASURED"; }
  else
    git rev-parse --verify --quiet "${src}^{commit}" >/dev/null 2>&1 || {
      gate_log "UNMEASURED shape: neither a file nor a commit: $src"; return "$GATE_UNMEASURED"; }
    msg=$(git log -1 --format='%B' "$src" -- 2>/dev/null) || {
      gate_log "UNMEASURED shape: git log failed on $src"; return "$GATE_UNMEASURED"; }
  fi

  local rc=0 subject second
  subject=${msg%%$'\n'*}
  [ -n "$subject" ] || { gate_log "RED shape SHAPE-1: empty subject"; rc=1; }
  if [ "${#subject}" -gt "$GATE_SUBJECT_MAX" ]; then
    gate_log "RED shape SHAPE-2: subject ${#subject} chars, max $GATE_SUBJECT_MAX"; rc=1
  fi
  if [ "$msg" != "$subject" ]; then
    second=${msg#*$'\n'}; second=${second%%$'\n'*}
    [ -z "$second" ] || { gate_log "RED shape SHAPE-3: line 2 must be blank"; rc=1; }
  fi
  case "$msg" in *$'\r'*) gate_log "RED shape SHAPE-4: carriage return present"; rc=1 ;; esac
  if printf '%s\n' "$msg" | grep -Eq '^(<<<<<<<|>>>>>>>)'; then
    gate_log "RED shape SHAPE-5: conflict marker at line start"; rc=1
  fi
  if printf '%s\n' "$msg" | grep -Eq "(/${GATE_HOME_SEG}/|/${GATE_HOME_SEG_ALT}/)[^/[:space:]]+"; then
    gate_log "RED shape SHAPE-6: absolute home path in message"; rc=1
  fi
  [ "$rc" -eq 0 ] || return "$GATE_RED"
  gate_log "GREEN shape: SHAPE-1..6"
  return "$GATE_GREEN"
}

# --- startup probe -----------------------------------------------------------
# A preamble that resolves but cannot run is UNMEASURED, never GREEN and never RED.
gate_selftest() {
  local rc=0 t
  for t in git ssh-keygen grep awk; do
    command -v "$t" >/dev/null 2>&1 || { gate_log "UNMEASURED selftest: $t absent"; rc=3; }
  done
  [ -r "$GATE_AGENT_PUB" ]        || { gate_log "UNMEASURED selftest: $GATE_AGENT_PUB unreadable"; rc=3; }
  [ -r "$GATE_ALLOWED_SIGNERS" ]  || { gate_log "UNMEASURED selftest: $GATE_ALLOWED_SIGNERS unreadable"; rc=3; }
  local fn
  for fn in gate_signing_env gate_preflight_agent gate_verify_principal gate_commit_shape; do
    declare -F "$fn" >/dev/null 2>&1 || { gate_log "UNMEASURED selftest: $fn undefined"; rc=3; }
  done
  [ "$rc" -eq 0 ] && gate_log "GREEN selftest: $GATE_PREAMBLE_VERSION"
  return "$rc"
}

# --- CLI ---------------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    selftest)          gate_selftest; exit $? ;;
    signing-env)       gate_signing_env_print; exit $? ;;
    preflight-agent)   gate_preflight_agent; exit $? ;;
    verify-principal)  shift; gate_verify_principal "$@"; exit $? ;;
    commit-shape)      shift; gate_commit_shape "$@"; exit $? ;;
    version)           printf '%s\n' "$GATE_PREAMBLE_VERSION"; exit 0 ;;
    *) printf 'usage: gate_preamble.sh {selftest|signing-env|preflight-agent|verify-principal <commit-ish> [principal]|commit-shape <file|commit-ish>|version}\n' >&2; exit 2 ;;
  esac
fi
