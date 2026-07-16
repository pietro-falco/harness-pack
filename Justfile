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

# Verify the enforced tree still matches its pinned manifest (D4 gate).
verify:
    bash {{enforced}}/scripts/detect_tamper.sh

# Fail-closed pre-run checks: tamper gate + enforced present + all worker
# symlinks retargeted to enforced. Red until the operator retargets .harness/pack.
preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    enforced="{{enforced}}"
    detect="$enforced/scripts/detect_tamper.sh"
    [ -x "$detect" ] || { echo "PREFLIGHT-FAIL: detect gate missing or not executable at $detect (enforced not deployed with D4?)" >&2; exit 1; }
    "$detect" || { echo "PREFLIGHT-FAIL: tamper gate reported mismatch" >&2; exit 1; }
    [ -d "$enforced" ] || { echo "PREFLIGHT-FAIL: enforced root absent: $enforced" >&2; exit 1; }
    fail=0
    for link in \
        "$HOME/Code/harness-sandbox/.harness/pack" \
        "$HOME/Code/harness-smoke/.harness/pack" \
        "$HOME/Code/verifiable-intel/.harness/pack"; do
      if [ ! -L "$link" ]; then
        echo "PREFLIGHT-FAIL: not a symlink: $link" >&2; fail=1; continue
      fi
      target="$(readlink -f "$link" 2>/dev/null || true)"
      if [ "$target" != "$enforced" ]; then
        echo "PREFLIGHT-FAIL: $link -> ${target:-<unresolved>} (want $enforced)" >&2; fail=1
      else
        echo "ok: $link -> $enforced"
      fi
    done
    [ "$fail" -eq 0 ] || { echo "PREFLIGHT-FAIL: one or more symlinks not retargeted" >&2; exit 1; }
    echo "PREFLIGHT-OK: tamper gate green, enforced present, all symlinks retargeted"

# Supervised HALT-ready run over the enforced pack. NOT autonomous Mode B — the
# unattended invariant stays disarmed. Requires preflight green; runs from the
# target repo root with HARNESS_HOME pinned to enforced.
run SPEC:
    #!/usr/bin/env bash
    set -euo pipefail
    enforced="{{enforced}}"
    spec="{{SPEC}}"
    cd "{{invocation_directory()}}"
    [ -f "$spec" ] || { echo "RUN-FAIL: spec not found: $spec" >&2; exit 1; }
    root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    if [ -e "$root/.harness/HALT" ]; then
      echo "RUN-FAIL: HALT file present at $root/.harness/HALT; refusing." >&2; exit 1
    fi
    just --justfile "{{justfile()}}" preflight
    echo "preflight green; launching supervised run over enforced pack (HARNESS_HOME=$enforced)"
    HARNESS_HOME="$enforced" "$enforced/scripts/launch_worker.sh" "$spec"
