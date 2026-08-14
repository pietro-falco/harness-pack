#!/usr/bin/env python3
"""Synthetic evidence corpus for the conformance fixtures (FT-20..FT-27).

  conformance_corpus.py VARIANT OUT_DIR

Writes OUT_DIR/invocation.txt and OUT_DIR/stream.jsonl. Synthetic and
deterministic on purpose: the real arm streams under runs/ carry local
absolute paths the privacy lint refuses in tracked files, and a fixture
corpus must be byte-stable across machines. Shape mirrors the measured
stream-json format (event-level parent_tool_use_id, tool_use/tool_result
blocks, one terminal result event).

Variants:
  green      declaration tools=Read,Write,Agent depth<=2; delegation chain
             0->1->2; Write executed at 1 and 2; Bash EMITTED at depth 2
             and rejected (is_error true) -- an attempt, not an exercise
             (ADR-023 D6); stream complete. Read declared, never executed.
  oos-run    same, but the depth-2 Bash result is NOT an error: an executed
             call outside the declared surface. A record built honestly
             from this run must verify DIVERGENT.
  truncated  green cut off mid-run: no result for the depth-2 calls, no
             terminal result event. A record built from it must verify
             INCOMPLETE, never CONFORMANT.
"""
import json
import os
import sys

DECLARATION = ("arm=SYN session=00000000-0000-0000-0000-000000000000 "
               "depth=2 pmode=manual tools=Read,Write,Agent "
               "allowed=Write,Agent bg=false\n")


def ev(kind, parent, block):
    return {"type": kind, "parent_tool_use_id": parent,
            "message": {"content": [block]}}


def use(uid, name):
    return {"type": "tool_use", "id": uid, "name": name, "input": {}}


def res(uid, err):
    return {"type": "tool_result", "tool_use_id": uid, "is_error": err,
            "content": ""}


def events(variant):
    bash_err = variant != "oos-run"
    full = [
        ev("assistant", None, use("tu_ag1", "Agent")),
        ev("assistant", "tu_ag1", use("tu_w1", "Write")),
        ev("user", "tu_ag1", res("tu_w1", False)),
        ev("assistant", "tu_ag1", use("tu_ag2", "Agent")),
        ev("assistant", "tu_ag2", use("tu_w2", "Write")),
        ev("user", "tu_ag2", res("tu_w2", False)),
        ev("assistant", "tu_ag2", use("tu_b1", "Bash")),
        ev("user", "tu_ag2", res("tu_b1", bash_err)),
        ev("user", "tu_ag1", res("tu_ag2", False)),
        ev("user", None, res("tu_ag1", False)),
        {"type": "result", "subtype": "success", "is_error": False},
    ]
    if variant == "truncated":
        return full[:7]
    return full


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("green", "oos-run",
                                                 "truncated"):
        sys.stderr.write("usage: conformance_corpus.py "
                         "green|oos-run|truncated OUT_DIR\n")
        sys.exit(3)
    variant, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "invocation.txt"), "w",
              encoding="utf-8") as fh:
        fh.write(DECLARATION)
    with open(os.path.join(out_dir, "stream.jsonl"), "w",
              encoding="utf-8") as fh:
        for event in events(variant):
            fh.write(json.dumps(event, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
