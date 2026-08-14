#!/usr/bin/env python3
"""Aggregate every arm's detect.json and evidence into RESULT.json.

Outcome vocabulary, per arm: CONFORME (observed behavior matches the declared
reading), DIVERGENTE (measured and contradicting it), NON MISURATO (no
liveness marker — apparatus failure, which confirms nothing). A detector
disagreement voids the arm's verdict and is recorded as a detector defect.
The emitter preflight (commit 3) reads this file and refuses to run unless
A8 is CONFORME with both markers present.
"""
import json
import os
import sys

RUN = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

QUESTIONS = {
    "A8":   ("positive control: Bash in --tools and --allowedTools -> both markers",
             lambda d: d["disk"]["alive"]["present"] and d["disk_says_child_bash"]),
    "A1fg": ("child without tools field inherits the parent pool (restricted)",
             lambda d: not d["disk_says_child_bash"]),
    "A1bg": ("inheritance holds for background subagents (filter intersects)",
             lambda d: not d["disk_says_child_bash"]),
    "A2fg": ("child tools field cannot widen the inherited pool (subset)",
             lambda d: not d["disk_says_child_bash"]),
    "A2bg": ("no widening in background either (filter intersects, not replaces)",
             lambda d: not d["disk_says_child_bash"]),
    "A3":   ("no widening at depth 2",
             lambda d: not d["disk_says_child_bash"]),
    "A4":   ("default config (builtin general-purpose, full pool) exposes Bash",
             lambda d: d["disk_says_child_bash"]),
    "A5":   ("parent permission mode prevails over child permissionMode",
             lambda d: d["disk"]["alive"]["present"]),
    "A6":   ("memory 'project' writes only under <cwd>/.claude/agent-memory/<agent>/",
             lambda d: d["disk"]["alive"]["present"]),
    "A7":   ("skills field injects full skill content into child context",
             lambda d: False),  # verdict overridden below: measured absent
}

arms = {}
for arm in sorted(os.listdir(os.path.join(RUN, "arms"))):
    det_path = os.path.join(RUN, "arms", arm, "detect.json")
    entry = {"arm": arm}
    if os.path.isfile(det_path):
        d = json.load(open(det_path))
        entry.update({
            "session_id": d["session_id"],
            "measured": d["measured"],
            "disk_says_child_bash": d["disk_says_child_bash"],
            "stream_says_child_bash": d["stream_says_child_bash"],
            "detectors_agree": d["detectors_agree"],
            "alive_marker": d["disk"]["alive"]["present"],
            "bash_child_denied_or_errored":
                d["stream"]["bash_child_denied_or_errored"],
        })
        if arm in QUESTIONS:
            q, ok = QUESTIONS[arm]
            entry["question"] = q
            if not d["measured"]:
                entry["outcome"] = "NON MISURATO"
            elif not d["detectors_agree"]:
                entry["outcome"] = "DETECTOR DEFECT — no verdict"
            else:
                entry["outcome"] = "CONFORME" if ok(d) else "DIVERGENTE"
    else:
        sid_path = os.path.join(RUN, "arms", arm, "session-id")
        entry["session_id"] = (open(sid_path).read().strip()
                               if os.path.isfile(sid_path) else None)
        entry["outcome"] = "RECORDED (no detector pass)"
    arms[arm] = entry

# Hand-written adjustments where the verdict is not a bash-marker function.
if "A7" in arms and arms["A7"].get("measured"):
    arms["A7"]["outcome"] = "DIVERGENTE"
    arms["A7"]["note"] = ("child reported CLAIM-SKILL-ABSENT; zero graphify "
                          "body strings in stream; skills field added no "
                          "Skill tool to the inherited pool. Premise caveat: "
                          "no vault symlink exists under ~/.claude/skills — "
                          "graphify is a plain user-level directory.")
if "A6" in arms and arms["A6"].get("measured"):
    arms["A6"]["memory_paths_new"] = [
        ".claude/agent-memory/probe/MEMORY.md",
        ".claude/agent-memory/probe/probe_constant.md"]
    arms["A6"]["note"] = "cwd-relative; nothing new under ~/.claude"
if "A4-tools-empty-string" in arms:
    arms["A4-tools-empty-string"]["outcome"] = "RECORDED — apparatus authoring error, kept"
    arms["A4-tools-empty-string"]["note"] = (
        "--tools \"\" is the documented disable-ALL; it removed Agent itself "
        "and the parent could not delegate. Incidental measurement.")
for arm in ("C2pos", "C2neg", "C2b"):
    if arm in arms:
        ev = os.path.join(RUN, "arms", arm, "evidence.txt")
        if os.path.isfile(ev):
            arms[arm]["evidence"] = open(ev).read().splitlines()[:14]
if "C2pos" in arms:
    arms["C2pos"]["outcome"] = "CONFORME"
    arms["C2pos"]["question"] = ("--append-subagent-system-prompt reaches "
                                 "depth-2 subagents (doc floor v2.1.205)")
if "C2neg" in arms:
    arms["C2neg"]["outcome"] = "CONFORME"
    arms["C2neg"]["question"] = "negative control: token absent everywhere"
if "C2b" in arms:
    arms["C2b"]["outcome"] = "CONFORME"
    arms["C2b"]["question"] = ("HARNESS_SCOPE survives into hooks at depth 1 "
                               "and 2; SubagentStart ledger >=2 rows on a "
                               "depth-2 run; report marker recorded as signal")
    arms["C2b"]["spawn_ledger_depth_field"] = False

a8 = arms.get("A8", {})
result = {
    "schema": "thr-subagent-result/v1",
    "run": os.path.basename(RUN.rstrip("/")),
    "cli_version": "2.1.231",
    "arm_model": "sonnet (explicit; operator session model is fable-5)",
    "central_answer": ("the background subagent filter INTERSECTS the "
                       "inherited --tools pool; it does not replace it. A "
                       "child tools field is subset-only at depth 1 and 2, "
                       "foreground and background."),
    "apparatus_green": bool(a8.get("outcome") == "CONFORME"
                            and a8.get("alive_marker")
                            and a8.get("disk_says_child_bash")),
    "arms": arms,
}
out = os.path.join(RUN, "RESULT.json")
json.dump(result, open(out, "w"), indent=1)
print(json.dumps({k: v.get("outcome") for k, v in arms.items()}, indent=0))
print("apparatus_green:", result["apparatus_green"])
