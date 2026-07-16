#!/usr/bin/env python3
"""G3 fail-closed guard + operator HALT kill-switch. PreToolUse hook on all tools.

Contract: reads hook JSON on stdin. Exit 0 = allow. Exit 2 = block
(stderr is fed back to the model). Policy lives HERE and is tested
directly with fixtures (tests/guard_cases.jsonl); the settings entry
stays boring on purpose.

HALT is checked before the Bash filter and blocks every tool, not just
Bash: it must neutralise a run already in flight, and a worker with Edit
and Write can do damage without ever shelling out. That is why the
settings matcher is "*" and not "Bash".

The HALT search walks UP from each candidate root, so a worker cannot
escape the kill-switch by working from a subdirectory. It stops at the
repo root (the first dir holding .git) rather than climbing out of the
repo.

Fail-closed means false positives are accepted: e.g. a benign
`grep 'rm -rf' README.md` is blocked. The escape hatch is Mode A with
an explicit operator directive, never a guard bypass.
"""
import json
import os
import re
import sys
from pathlib import Path

BOUNDARY = r"(^|[\s;&|`$('\"])"
DENY = [
    BOUNDARY + r"rm[\s]",  BOUNDARY + r"rm$",
    BOUNDARY + r"rmdir(\s|$)",
    BOUNDARY + r"shred(\s|$)",
    BOUNDARY + r"ln(\s|$)",
    BOUNDARY + r"mv(\s|$)",
    BOUNDARY + r"chmod(\s|$)",
    BOUNDARY + r"chflags(\s|$)",
    r"git\s+push\b.*(--force\b|--force-with-lease\b)",
    r"git\s+push\b.*\s\+\S",          # +refspec force push
    r"--no-verify\b",
    r"git\s+add\s+(-A\b|--all\b|-u\b)",
    r"git\s+reset\s+--hard",
    BOUNDARY + r"git\s+clean\b",
    r"filter-branch|filter-repo",
    r"\bfind\b.*\s-delete\b",
]

def halt_engaged(payload_cwd: object) -> bool:
    """True if .harness/HALT exists at, or anywhere above, a candidate root.

    Non-string or empty candidates are skipped, never coerced: a guard whose
    whole contract is fail-closed must not die on a TypeError, because a
    crash exits 1, and exit 1 is non-blocking.
    """
    try:
        here = str(Path.cwd())
    except OSError:
        here = ""
    for base in (payload_cwd, os.environ.get("CLAUDE_PROJECT_DIR"), here):
        if not isinstance(base, str) or not base:
            continue
        try:
            start = Path(base).resolve()
        except OSError:
            continue
        for d in (start, *start.parents):
            if (d / ".harness" / "HALT").exists():
                return True
            if (d / ".git").exists():
                break  # repo root: checked it, do not climb out of the repo
    return False

def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        print("G3-BLOCKED: unparseable hook payload (fail-closed).", file=sys.stderr)
        return 2
    if halt_engaged(payload.get("cwd")):
        print("HALT: operator kill-switch engaged; all tool use blocked.",
              file=sys.stderr)
        return 2
    if payload.get("tool_name") != "Bash":
        return 0
    cmd = payload.get("tool_input", {}).get("command", "")
    if not isinstance(cmd, str):
        print("G3-BLOCKED: non-string command (fail-closed).", file=sys.stderr)
        return 2
    for rx in DENY:
        if re.search(rx, cmd):
            print(f"G3-BLOCKED: destructive pattern [{rx}] requires an "
                  f"explicit operator directive (L-021). This is a stop "
                  f"condition, not an obstacle.", file=sys.stderr)
            return 2
    return 0

if __name__ == "__main__":
    sys.exit(main())
