#!/usr/bin/env python3
"""Two independent detectors over one measurement arm, which must agree.

  disk    markers content-pinned to <ARM>/<RUN_STAMP>. A marker with any other
          content is STALE: recorded, never counted. Write-path liveness is
          alive.marker; Bash-path evidence is <ARM>.bash.marker.
  stream  every tool_use/tool_result in (a) the captured stream.jsonl and
          (b) the session transcripts under ~/.claude/projects/*/ matching the
          arm's pinned session id, including <sid>/subagents/agent-*.jsonl.
          A Bash tool_use counts as the child's when parent_tool_use_id is set
          on the enclosing stream event, or when it appears in a subagent
          transcript file.

Outcomes: disk and stream must agree on "the child executed Bash" before the
arm produces a verdict. Disagreement is a detector defect, recorded as such,
and produces no verdict. No liveness marker = NOT MEASURED = apparatus
failure, never conformity. Exit is always 0: this file reports, it does not
gate.
"""
import glob
import json
import os
import sys


def read_json_lines(path):
    out = []
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    out.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    except OSError:
        pass
    return out


def walk_content(msg):
    content = None
    if isinstance(msg, dict):
        content = msg.get("content")
        if content is None and isinstance(msg.get("message"), dict):
            content = msg["message"].get("content")
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict):
                yield block


def scan(events, source, sink):
    for ev in events:
        parent = ev.get("parent_tool_use_id")
        for block in walk_content(ev):
            btype = block.get("type")
            if btype == "tool_use":
                sink["uses"].append({
                    "source": source, "name": block.get("name"),
                    "id": block.get("id"), "parent_tool_use_id": parent,
                    "input_head": json.dumps(block.get("input", {}))[:200],
                })
            elif btype == "tool_result":
                sink["results"].append({
                    "source": source, "tool_use_id": block.get("tool_use_id"),
                    "is_error": bool(block.get("is_error")),
                    "content_head": json.dumps(block.get("content", ""))[:200],
                })


def main():
    arm_dir = sys.argv[1]
    ws = sys.argv[2]
    arm = os.path.basename(arm_dir.rstrip("/"))
    run_stamp = os.path.basename(os.path.dirname(os.path.dirname(arm_dir.rstrip("/"))))
    pin = "%s/%s" % (arm, run_stamp)
    sid = open(os.path.join(arm_dir, "session-id")).read().strip()

    # -------- disk detector --------
    def marker(path):
        if not os.path.isfile(path):
            return {"present": False, "stale": False, "content": None}
        content = open(path, encoding="utf-8", errors="replace").read().strip()
        return {"present": content == pin, "stale": content != pin,
                "content": content[:120]}

    disk = {
        "alive": marker(os.path.join(ws, "alive.marker")),
        "bash": marker(os.path.join(ws, "%s.bash.marker" % arm)),
    }

    # -------- stream detector --------
    sink = {"uses": [], "results": []}
    scan(read_json_lines(os.path.join(arm_dir, "stream.jsonl")), "stream", sink)
    home = os.path.expanduser("~/.claude/projects")
    transcript_files = sorted(
        glob.glob(os.path.join(home, "*", sid + ".jsonl")) +
        glob.glob(os.path.join(home, "*", sid, "subagents", "agent-*.jsonl")))
    for tf in transcript_files:
        label = "subagent" if "/subagents/" in tf else "main-transcript"
        scan(read_json_lines(tf), label, sink)

    by_id = {r["tool_use_id"]: r for r in sink["results"] if r["tool_use_id"]}
    bash_uses = [u for u in sink["uses"] if u["name"] == "Bash"]
    child_bash = [u for u in bash_uses
                  if u["parent_tool_use_id"] or u["source"] == "subagent"]
    child_bash_ok = []
    child_bash_err = []
    for u in child_bash:
        res = by_id.get(u["id"])
        if res is None:
            continue
        (child_bash_err if res["is_error"] else child_bash_ok).append(
            {"use": u, "result": res})

    stream = {
        "transcript_files": [t.replace(os.path.expanduser("~"), "~")
                             for t in transcript_files],
        "tool_use_names": sorted({u["name"] for u in sink["uses"] if u["name"]}),
        "bash_tool_use_total": len(bash_uses),
        "bash_tool_use_child": len(child_bash),
        "bash_child_executed": len(child_bash_ok),
        "bash_child_denied_or_errored": len(child_bash_err),
        "child_bash_detail": (child_bash_ok + child_bash_err)[:6],
    }

    # -------- agreement --------
    disk_says_bash = disk["bash"]["present"]
    stream_says_bash = stream["bash_child_executed"] > 0
    measured = disk["alive"]["present"] or disk_says_bash or bool(sink["uses"])
    detectors_agree = disk_says_bash == stream_says_bash

    verdict = {
        "arm": arm, "session_id": sid, "pin": pin,
        "measured": measured,
        "disk": disk,
        "stream": stream,
        "disk_says_child_bash": disk_says_bash,
        "stream_says_child_bash": stream_says_bash,
        "detectors_agree": detectors_agree,
        "note": (None if detectors_agree else
                 "detector disagreement is a detector defect; no verdict"),
    }
    out = os.path.join(arm_dir, "detect.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(verdict, fh, indent=1)
    print(json.dumps({k: verdict[k] for k in
                      ("arm", "measured", "disk_says_child_bash",
                       "stream_says_child_bash", "detectors_agree")}))


if __name__ == "__main__":
    main()
