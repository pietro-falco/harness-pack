#!/usr/bin/env python3
"""Spec lint: exit 1 on any violation.
Rules: tier in T0..T3; forbidden model-name substrings in spec body;
mode B requires every criterion verify: gate AND destructive_ops: none.
"""
import re, sys, glob

FORBIDDEN = ("claude-", "gpt-", "gemini-", "opus", "sonnet", "haiku")

def lint(path):
    errs = []
    t = open(path, encoding="utf-8").read()
    m = re.search(r"^tier:\s*(\S+)", t, re.M)
    if not m or m.group(1) not in {"T0", "T1", "T2", "T3"}:
        errs.append("tier missing or invalid")
    low = t.lower()
    for f in FORBIDDEN:
        if f in low:
            errs.append(f"model-name token '{f}' forbidden in specs")
    mode = re.search(r"^mode:\s*(\S+)", t, re.M)
    if mode and mode.group(1) == "B":
        verifies = re.findall(r"verify:\s*(\S+)", t)
        if not verifies or any(v != "gate" for v in verifies):
            errs.append("mode B requires every criterion verify: gate")
        d = re.search(r"^destructive_ops:\s*(\S+)", t, re.M)
        if not d or d.group(1) != "none":
            errs.append("mode B requires destructive_ops: none")
    return errs

def main():
    paths = sys.argv[1:] or glob.glob("specs/**/*.md", recursive=True)
    bad = 0
    for p in paths:
        for e in lint(p):
            print(f"{p}: {e}")
            bad += 1
    print("lint:", "FAIL" if bad else "OK")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
