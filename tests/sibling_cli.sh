#!/usr/bin/env bash
# Where the two CLIs are, declared once, in a tracked file.
#
# The falsifiers that drive a real launch need harnesswright and verity as
# executables. They knew two ways to find them: the HARNESSWRIGHT_CLI and
# VERITY_CLI environment variables, and a binary on $PATH. On a working tree
# where the three repos of the stack sit side by side and neither package is
# installed, both ways come up empty and six falsifiers exit 2 UNMEASURED --
# they never reach the question they exist to ask, and the suite's exit code
# stops saying anything about them. This file is the third way.
#
# The constant is RELATIVE to the harness-pack repo root, and relative on
# purpose. An absolute path would spell one machine's layout into a tracked
# file, would be wrong on every other checkout, and is the class of literal the
# surface-separation claim exists to keep off the public surface. What it
# assumes is only that the three repos are siblings -- the layout docs/STACK.md
# already describes.
#
# Precedence is unchanged where it mattered: the environment variable still
# wins, so a caller pointing at a specific build is never overridden, and a
# variable pointing at nothing still fails the caller's own -f check exactly as
# before. $PATH comes second. The sibling checkout is the last resort, and when
# it is absent too the resolver fails and the caller still exits 2 UNMEASURED.
# A machine without the sibling repos therefore measures precisely what it
# measured before this file existed: no regression, only a case that used to
# be unmeasured and now is not.
HARNESSWRIGHT_SIBLING_CLI=../harnesswright/dist/cli.js
VERITY_SIBLING_CLI=../verity/dist/cli.js

# $1: the harness-pack repo root. Prints the resolved path and returns 0, or
# prints nothing and returns 1. Existence of the resolved path is NOT asserted
# here: the caller's own `[ -f ]` check owns that verdict and its wording.
resolve_harnesswright_cli() {
  if [ -n "${HARNESSWRIGHT_CLI:-}" ]; then
    printf '%s\n' "$HARNESSWRIGHT_CLI"
    return 0
  fi
  if command -v harnesswright >/dev/null 2>&1; then
    command -v harnesswright
    return 0
  fi
  if [ -f "$1/$HARNESSWRIGHT_SIBLING_CLI" ]; then
    printf '%s\n' "$1/$HARNESSWRIGHT_SIBLING_CLI"
    return 0
  fi
  return 1
}

# $1: the harness-pack repo root. Same contract as above.
resolve_verity_cli() {
  if [ -n "${VERITY_CLI:-}" ]; then
    printf '%s\n' "$VERITY_CLI"
    return 0
  fi
  if command -v verity >/dev/null 2>&1; then
    command -v verity
    return 0
  fi
  if [ -f "$1/$VERITY_SIBLING_CLI" ]; then
    printf '%s\n' "$1/$VERITY_SIBLING_CLI"
    return 0
  fi
  return 1
}

# The argument the probe below passes, and the only one it passes. It is a
# command in neither CLI on purpose: the probe asks whether the program got as
# far as reading its arguments, not whether it can do anything with them. A CLI
# that starts and refuses this token has passed.
CLI_START_PROBE_ARG=__cli_start_probe__

# The third piece, and deliberately not a fourth branch inside either resolver
# above: those two answer "where", their contract says existence is the
# caller's verdict, and this asks a third question the caller owns too --
# "does what I resolved start?".
#
# It exists because tracking dist/cli.js made `[ -f ]` a lie. A clone that
# carries the entrypoint and none of the modules it imports satisfies every
# check the caller had: the path resolves, the file is there, and the first
# thing the fixture drives dies at import with a node stack trace the fixture
# reads as its subject misbehaving. That run exits RED and names the mechanism
# under test as the defect. It is a missing build.
#
# $1: a resolved CLI path, invoked the way every consumer in this repo invokes
# one -- `node <path>` (scripts/launch_worker.sh, scripts/graft_init.sh).
# Returns 0 and prints nothing when the program loaded and read its arguments.
# Returns 1 otherwise and prints one line of what it emitted instead, so the
# caller can name the reason in its own UNMEASURED wording.
#
# The discriminator is the nonce coming back. A CLI that loaded answers an
# unknown command by naming it; a CLI that died before its main ever ran emits
# a loader trace, which cannot contain a token the program never read. Nothing
# cheaper separates the two: both exit non-zero, both write to stderr, and a
# CLI that starts is under no obligation to exit 0 here -- both CLIs in this
# stack exit 2 on an unknown command, and that is a pass.
cli_starts() {
  probe_out="$(node "$1" "$CLI_START_PROBE_ARG" 2>&1)"
  case "$probe_out" in
    *"$CLI_START_PROBE_ARG"*) return 0 ;;
  esac
  # The first Error line, not the first line: node opens a crash with the file
  # and line of its own loader, and the line that names WHICH module is missing
  # is the one an operator can act on -- it is the name of the build nobody ran.
  probe_line="$(printf '%s\n' "$probe_out" | grep -m1 Error || true)"
  [ -n "$probe_line" ] || probe_line="$(printf '%s\n' "$probe_out" | head -n 1)"
  printf '%s' "$probe_line" | cut -c1-160
  return 1
}
