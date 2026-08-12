#!/usr/bin/env bash
# Acquire the pinned shellcheck for THIS host, verified against the pin.
#
# tests/run_tests.sh and .github/workflows/ci.yml both run the gate only under
# the pinned version; anything else is unmeasured, never a pass. The pin named
# one artifact and the CI runner was the only host that could execute it, so on
# the authoring host the gate's verdict was unreachable rather than merely
# absent. .shellcheck-version now pins a digest per platform and this script
# picks by uname instead of leaving the operator to assemble a URL.
#
# It writes nothing into the repository. The binary lands in a user cache and
# its path goes to stdout, so the whole use is:
#
#   SHELLCHECK="$(scripts/fetch_shellcheck.sh)" bash tests/run_tests.sh
#
# Fail-closed on every branch: an unpinned platform, a digest mismatch, or an
# artifact whose own --version disagrees with the pin all STOP. A downloaded
# file that fails its digest is removed rather than left to be found later.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PACK="$(cd "$SELF_DIR/.." && pwd)"
PIN="$PACK/.shellcheck-version"
[ -f "$PIN" ] || { echo "STOP: .shellcheck-version not resolvable at $PIN" >&2; exit 1; }

VER="$(sed -n 's/^SHELLCHECK_VERSION=//p' "$PIN")"
[ -n "$VER" ] || { echo "STOP: .shellcheck-version declares no SHELLCHECK_VERSION" >&2; exit 1; }

# Darwin arm64 takes the x86_64 build under Rosetta 2: upstream publishes no
# arm64 darwin artifact for this release, and the analysis is a function of the
# version, not of the instruction set it was compiled for.
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS:$ARCH" in
  Darwin:arm64|Darwin:x86_64) PLAT="darwin.x86_64"; KEY="SHELLCHECK_SHA256_DARWIN_X86_64" ;;
  Linux:x86_64)               PLAT="linux.x86_64";  KEY="SHELLCHECK_SHA256_LINUX_X86_64" ;;
  Linux:aarch64|Linux:arm64)  PLAT="linux.aarch64"; KEY="SHELLCHECK_SHA256_LINUX_AARCH64" ;;
  *) echo "STOP: no artifact is pinned for $OS/$ARCH; add its digest to .shellcheck-version" >&2; exit 1 ;;
esac

WANT="$(sed -n "s/^$KEY=//p" "$PIN")"
[ -n "$WANT" ] || { echo "STOP: .shellcheck-version pins no $KEY, so this host cannot run the gate until that digest is added" >&2; exit 1; }

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/harness-pack/shellcheck-$VER-$PLAT"
BIN="$CACHE/shellcheck-v$VER/shellcheck"

digest_of() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    sha256sum "$1" | cut -d' ' -f1
  fi
}

if [ ! -x "$BIN" ]; then
  URL="https://github.com/koalaman/shellcheck/releases/download/v$VER/shellcheck-v$VER.$PLAT.tar.xz"
  TAR="$CACHE/shellcheck-v$VER.$PLAT.tar.xz"
  mkdir -p "$CACHE"
  echo "fetching $URL" >&2
  curl -fsSL -o "$TAR" "$URL" || { echo "STOP: download failed: $URL" >&2; exit 1; }
  GOT="$(digest_of "$TAR")"
  if [ "$GOT" != "$WANT" ]; then
    rm -f "$TAR"
    echo "STOP: digest mismatch, artifact discarded" >&2
    echo "  pinned:   $WANT" >&2
    echo "  computed: $GOT" >&2
    exit 1
  fi
  tar -xJf "$TAR" -C "$CACHE" || { echo "STOP: could not extract $TAR" >&2; exit 1; }
fi

[ -x "$BIN" ] || { echo "STOP: no executable at $BIN after extraction" >&2; exit 1; }
HAVE="$("$BIN" --version | sed -n 's/^version: //p')"
if [ "$HAVE" != "$VER" ]; then
  echo "STOP: the digest-verified artifact reports version '$HAVE', the pin declares '$VER'" >&2
  exit 1
fi

printf '%s\n' "$BIN"
