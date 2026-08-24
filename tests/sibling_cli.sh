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
