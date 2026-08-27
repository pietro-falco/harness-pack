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

WRITE_TOOLS = ("Write", "Edit", "MultiEdit", "NotebookEdit")


def repo_root(payload_cwd: object) -> str:
    """The directory the declared prefixes are relative to.

    Same candidate order as halt_engaged, and for the same reason: the payload's
    cwd is what the child reports, CLAUDE_PROJECT_DIR is what the launcher set,
    and this process's cwd is the last resort. Climbs to the first .git.
    """
    try:
        here = os.getcwd()
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
            if (d / ".git").exists():
                return str(d)
        return str(start)
    return ""


def scope_violation(payload: dict) -> str:
    """Empty string if this write is inside the declared scope, else why not.

    ADR-021 D1/D2. The PreToolUse payload carries no path to the slice spec, so
    the declared scope arrives in HARNESS_SCOPE, comma-separated repo-relative
    prefixes, exported by the launcher before the spawn.

    Fail-closed on absence: a scope that never reached this hook is not a scope
    the run is honouring, and a write bound nobody delivered is the defect
    ADR-013 named one layer up. Refused, never normalised -- trimming a leading
    slash or resolving a ".." would hand the run a perimeter nobody declared.

    Both sides go through realpath: on macOS a payload's file_path arrives
    already resolved (/private/tmp/...), and a prefix comparison against an
    unresolved root would never match.
    """
    raw = os.environ.get("HARNESS_SCOPE")
    if not isinstance(raw, str) or not raw.strip():
        return ("no declared scope reached this hook (HARNESS_SCOPE absent or "
                "empty); a write bound that was never delivered is not a bound")
    prefixes = [p for p in raw.split(",") if p]
    if not prefixes:
        return "HARNESS_SCOPE holds no prefix after splitting on ','"
    bad = [p for p in prefixes
           if p.startswith("/") or ".." in p.split("/")
           or any(c.isspace() for c in p)]
    if bad:
        return "HARNESS_SCOPE carries a malformed prefix: %s" % " ".join(bad)
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return "write tool with a non-object tool_input"
    fp = tool_input.get("file_path")
    if not isinstance(fp, str) or not fp:
        return "write tool with no file_path"
    root = repo_root(payload.get("cwd"))
    if not root:
        return "no directory to resolve the declared prefixes against"
    try:
        target = os.path.realpath(fp if os.path.isabs(fp) else os.path.join(root, fp))
    except OSError:
        return "file_path could not be resolved"
    for p in prefixes:
        try:
            allowed = os.path.realpath(os.path.join(root, p))
        except OSError:
            continue
        if target == allowed or target.startswith(allowed + os.sep):
            return ""
    return "write outside the declared scope [%s]: %s" % (raw, fp)


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
    tool_name = payload.get("tool_name")
    # ADR-021 D1, layer 2. This line used to read `!= "Bash": return 0`, which
    # waved every structured write through before any input was read. The write
    # tools are decided on their declared file_path; everything else still falls
    # through to the Bash filter below, unchanged.
    if tool_name in WRITE_TOOLS:
        why = scope_violation(payload)
        if why:
            print(f"G3-BLOCKED: {why} (ADR-021 D1). This is a stop condition, "
                  f"not an obstacle.", file=sys.stderr)
            return 2
        return 0
    if tool_name != "Bash":
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
