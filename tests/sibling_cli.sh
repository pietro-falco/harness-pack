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

# Which `git` binary every fixture that sources this file actually runs.
#
# On a Mac with Xcode installed, the `git` that $PATH resolves to is not git:
# it is Apple's xcrun trampoline, which locates the developer directory and
# then execs the real binary inside it. Measured on this tree, the trampoline
# costs 26.4ms per invocation over the binary it ends up running -- 41.4ms
# against 15.0ms -- and the git-heavy fixtures here call git in the hundreds.
# That is the whole of the saving and the whole of the claim: not fewer git
# calls and not a faster git, the same calls run without the middleman.
#
# The substitution is made only where it is PROVABLY a substitution. The binary
# xcrun points at must declare the same version string as the `git` that would
# otherwise have run. Where the two strings differ -- a wrapper earlier on
# $PATH, a second toolchain, a machine where xcrun answers for a different
# install -- nothing is substituted and `git` runs exactly as it does today.
# That fallback is not a degradation dressed up as one: it is behaviourally
# identical to this file before this paragraph existed, and it is the only
# fallback allowed here, because a resolver that silently picked a DIFFERENT
# git would quietly turn every fixture into a measurement of another binary.
#
# What goes on $PATH is a directory holding one symlink named `git`, and
# deliberately NOT the toolchain's own bin directory: that directory also
# carries python3, make, gcc and ld, so putting it first would swap the python3
# every fixture in this suite runs. Exactly one name is substituted; the rest
# of $PATH is left alone.
#
# No absolute path is spelled here, in code or in comment. The toolchain is
# asked for at runtime, and the link lives under $TMPDIR beside every other
# scratch object this suite builds -- which is why the constant below is a bare
# NAME and the directory is only ever composed where $TMPDIR is known to be
# set. With no scratch root named, nothing is substituted, which is the same
# no-op every other unproven case takes.
GIT_SUBSTITUTE_DIR_NAME=harness-pack-git-substitute

# Returns 0 when `git` on $PATH is now the substituted binary, 1 when it is
# untouched. Both are success for the caller: nothing here is fatal, because a
# resolution that cannot be proven leaves the suite measuring what it measured
# before.
resolve_git_substitute() {
  local git_current git_candidate version_current version_candidate dir
  # Resolved already by an ancestor: the marker names a directory that is on
  # $PATH and holds the link. The exported $PATH is what carries the answer
  # down -- the launcher, the graft command and every bash they spawn get the
  # substituted git without resolving anything, and that is where the great
  # majority of the git calls in this suite actually happen. The marker is the
  # narrower guard beside it: it makes a RE-source cost no process. Nothing in
  # the suite re-sources this file today, so that branch is insurance rather
  # than a saving, and it is worth exactly that much.
  if [ -n "${HARNESS_GIT_SUBSTITUTE:-}" ] && [ -x "${HARNESS_GIT_SUBSTITUTE}/git" ]; then
    return 0
  fi
  command -v xcrun >/dev/null 2>&1 || return 1
  [ -n "${TMPDIR:-}" ] || return 1
  git_current="$(command -v git 2>/dev/null)" || return 1
  git_candidate="$(xcrun --find git 2>/dev/null)" || return 1
  [ -x "$git_candidate" ] || return 1
  # Nothing to substitute: what would run is already the binary xcrun names.
  if [ "$git_current" -ef "$git_candidate" ]; then
    return 1
  fi
  # The parity gate, and the reason the whole string is compared rather than a
  # parsed number: the build and Apple's own suffix are what separate the two
  # installs that actually collide on this platform.
  version_current="$("$git_current" --version 2>/dev/null)" || return 1
  version_candidate="$("$git_candidate" --version 2>/dev/null)" || return 1
  [ "$version_current" = "$version_candidate" ] || return 1
  dir="$TMPDIR/$GIT_SUBSTITUTE_DIR_NAME"
  mkdir -p "$dir" || return 1
  # Re-pointed only when it does not already point at today's candidate, so a
  # link left by a previous toolchain cannot survive into this run and the
  # steady state writes nothing. The rename is what publishes it: `ln -sf`
  # unlinks before it links, and a concurrently exec'ing child that fell into
  # that window would see no `git` at all.
  if [ ! "$dir/git" -ef "$git_candidate" ]; then
    ln -sf "$git_candidate" "$dir/.git.$$" || return 1
    mv -f "$dir/.git.$$" "$dir/git" || return 1
  fi
  PATH="$dir:$PATH"
  HARNESS_GIT_SUBSTITUTE="$dir"
  export PATH HARNESS_GIT_SUBSTITUTE
  return 0
}

# Sourcing this file is what applies it: the fixtures already source it, they
# already run standalone as well as under tests/run_tests.sh, and a resolution
# that had to be called by hand would be a resolution some of them forgot.
resolve_git_substitute || :
