#!/usr/bin/env python3
"""G3 fail-closed guard. PreToolUse hook on Bash.

Contract: reads hook JSON on stdin. Exit 0 = allow. Exit 2 = block
(stderr is fed back to the model). Policy lives HERE and is tested
directly with fixtures (tests/guard_cases.jsonl); the settings entry
stays boring on purpose.

Fail-closed means false positives are accepted: e.g. a benign
`grep 'rm -rf' README.md` is blocked. The escape hatch is Mode A with
an explicit operator directive, never a guard bypass.
"""
import json
import re
import sys

BOUNDARY = r"(^|[\s;&|`$('\"])"
DENY = [
    BOUNDARY + r"rm[\s]",  BOUNDARY + r"rm$",
    BOUNDARY + r"rmdir(\s|$)",
    BOUNDARY + r"shred(\s|$)",
    r"git\s+push\b.*(--force\b|--force-with-lease\b)",
    r"git\s+push\b.*\s\+\S",          # +refspec force push
    r"--no-verify\b",
    r"git\s+add\s+(-A\b|--all\b|-u\b)",
    r"git\s+reset\s+--hard",
    BOUNDARY + r"git\s+clean\b",
    r"filter-branch|filter-repo",
    r"\bfind\b.*\s-delete\b",
]

def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        print("G3-BLOCKED: unparseable hook payload (fail-closed).", file=sys.stderr)
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
