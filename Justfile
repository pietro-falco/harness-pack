# harness-pack build surface.
# D5 adds `deploy`; D6 will add verify / preflight / run.

enforced := "/opt/harness"

# Deploy pack from HEAD to enforced /opt/harness (operator/sudo; idempotent).
deploy:
    #!/usr/bin/env bash
    set -euo pipefail
    repo="$(git rev-parse --show-toplevel)"
    head="$(git -C "$repo" rev-parse --short HEAD)"
    tarball="$(mktemp -t harness-pack.XXXXXX.tar)"
    trap 'rm -f "$tarball"' EXIT
    git -C "$repo" archive --format=tar HEAD -o "$tarball"
    sudo bash -euo pipefail -c '
      enforced="$1"; tarball="$2"
      case "$enforced" in /opt/*) ;; *) echo "refusing: enforced not under /opt" >&2; exit 1 ;; esac
      rm -rf "$enforced"
      mkdir -p "$enforced"
      tar -xf "$tarball" -C "$enforced"
      cd "$enforced"
      find . -type f ! -name MANIFEST.sha256 -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 > MANIFEST.sha256
      chown -R root:wheel "$enforced"
      find "$enforced" -type d -exec chmod 755 {} +
      find "$enforced" -type f -exec chmod 644 {} +
      find "$enforced" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod 755 {} +
    ' _ "{{enforced}}" "$tarball"
    echo "deployed HEAD ${head} -> {{enforced}}"
