#!/usr/bin/env python3
"""Render a Claude Code session JSONL as readable Italian, one line per event.

The operator has no way to see what a run is doing except by watching that
run's TUI. This reads the per-session transcript Claude Code writes under
~/.claude/projects/<slug>/<session-id>.jsonl and prints a human line per
event: what it is doing, to which file, with what outcome.

Three properties are load-bearing:

  * A live JSONL always has a ragged tail. A line that will not parse is
    MARKED and skipped; every later event still renders. Dying on the tail
    would make this useless exactly when it is needed -- mid-run.
  * A blocked action never renders as successful work. `toolDenialKind` and a
    model-level `stop_reason: "refusal"` are refusals, not activity. Printing
    a refusal as ordinary output is the receipt defect moved to the screen.
  * Refusal, error and stop are three distinct marks, not one.

Stdlib only. No daemon, no listener, no state on disk.

Usage:
    render_session.py                       # latest session for this repo
    render_session.py -n 3 --follow         # tail the 3 most recent
    render_session.py <session-id> ...      # named sessions
    render_session.py path/to/file.jsonl    # an explicit transcript
    render_session.py --list                # what is available
"""

import argparse
import datetime
import json
import os
import re
import sys
import time

PROJECTS = os.path.expanduser("~/.claude/projects")
POLL_SECONDS = 0.2
READ_CHUNK = 1 << 16

# Marks. The three that matter are words, not only glyphs, so they survive a
# pipe into grep and a terminal without unicode.
PLAIN = "·"
OUTCOME = "  ↳"
MARK_REFUSAL = "⛔ RIFIUTO"
MARK_ERROR = "✗ ERRORE"
MARK_STOP = "■ STOP"
MARK_BAD = "⚠ ILLEGGIBILE"
MARK_WIDTH = 13

# toolDenialKind is the literal field Claude Code writes on the user record
# when a tool was blocked instead of run. Absent means the tool actually ran.
DENIAL_REASON = {
    "user-rejected": "negato dall'operatore",
    "permission-rule": "negato da una regola di permessi",
    "automode-blocked": "bloccato dal classificatore auto-mode",
    "automode-unavailable": "auto-mode non disponibile",
}

# Record types that carry no operator-visible activity: UI state, titles,
# queue bookkeeping, snapshots. Rendering them would bury the signal.
SKIP_TYPES = frozenset((
    "mode", "permission-mode", "ai-title", "last-prompt", "attachment",
    "queue-operation", "file-history-snapshot", "file-history-delta",
    "summary",
))
SKIP_SYSTEM_SUBTYPES = frozenset((
    "turn_duration", "away_summary", "stop_hook_summary",
))


# --------------------------------------------------------------------------
# reading
# --------------------------------------------------------------------------

class Transcript:
    """Incremental line reader over a file that may still be growing.

    Only newline-terminated lines are handed out. Anything after the last
    newline is held in the buffer, because on a live file it is a write in
    progress, not corruption. That distinction is the whole trick: a partial
    tail is normal, a newline-terminated line that will not parse is not.
    """

    def __init__(self, path, label):
        self.path = path
        self.label = label
        self.buf = ""
        self.pos = 0
        self.fh = None

    def _open(self):
        if self.fh is not None:
            return True
        try:
            self.fh = open(self.path, "r", encoding="utf-8", errors="replace")
        except OSError:
            return False
        self.fh.seek(self.pos)
        return True

    def poll(self):
        """Return the complete lines that appeared since the last call."""
        if not self._open():
            return []
        try:
            size = os.path.getsize(self.path)
        except OSError:
            return []
        if size < self.pos:
            # Truncated or replaced under us: start over rather than read junk.
            self.fh.close()
            self.fh = None
            self.pos = 0
            self.buf = ""
            if not self._open():
                return []
        out = []
        while True:
            chunk = self.fh.read(READ_CHUNK)
            if not chunk:
                break
            self.buf += chunk
        self.pos = self.fh.tell()
        if "\n" in self.buf:
            *complete, self.buf = self.buf.split("\n")
            out.extend(complete)
        return out

    def partial(self):
        """Whatever is sitting past the last newline, if anything."""
        return self.buf.strip()


def project_dir_for(path):
    """Claude Code's slug for a working directory."""
    return os.path.join(PROJECTS, re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(path)))


def find_sessions(project, ids, latest):
    """Resolve CLI arguments to (path, label) pairs, newest last."""
    picked = []
    for token in ids:
        if os.path.sep in token or token.endswith(".jsonl"):
            picked.append(os.path.abspath(token))
        else:
            picked.append(os.path.join(project, token + ".jsonl"))
    if not picked:
        try:
            files = [os.path.join(project, f) for f in os.listdir(project)
                     if f.endswith(".jsonl")]
        except OSError:
            return []
        files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
        picked = files[:latest]
    return [(p, os.path.basename(p)[:-6][:8] or "?") for p in picked]


# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------

def clock(record):
    stamp = record.get("timestamp")
    if not isinstance(stamp, str):
        return "--:--:--"
    try:
        when = datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    except ValueError:
        return "--:--:--"
    return when.astimezone().strftime("%H:%M:%S")


def squeeze(text, limit):
    if not isinstance(text, str):
        text = str(text)
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def shorten_path(path, cwd):
    if not isinstance(path, str):
        return str(path)
    if cwd and path.startswith(cwd.rstrip("/") + "/"):
        return path[len(cwd.rstrip("/")) + 1:]
    return path.replace(os.path.expanduser("~"), "~", 1)


def describe_tool(name, args, cwd):
    """One Italian phrase for a tool call: the verb and its object."""
    def p(key):
        return shorten_path(args.get(key, ""), cwd)

    if name == "Read":
        return "legge  " + p("file_path")
    if name == "Write":
        return "scrive  " + p("file_path")
    if name in ("Edit", "MultiEdit"):
        return "modifica  " + p("file_path")
    if name == "NotebookEdit":
        return "modifica il notebook  " + p("notebook_path")
    if name == "Bash":
        cmd = squeeze(args.get("command", ""), 88)
        return "esegue  " + cmd
    if name == "Glob":
        return "cerca file  " + squeeze(args.get("pattern", ""), 60)
    if name == "Grep":
        return "cerca nel testo  " + squeeze(args.get("pattern", ""), 60)
    if name == "Skill":
        return "usa la skill  " + squeeze(args.get("skill", ""), 40)
    if name == "Agent":
        return ("delega a un sottoagente (%s)  %s"
                % (args.get("subagent_type", "?"),
                   squeeze(args.get("description", ""), 60)))
    if name == "WebFetch":
        return "scarica  " + squeeze(args.get("url", ""), 70)
    if name == "WebSearch":
        return "cerca sul web  " + squeeze(args.get("query", ""), 60)
    if name == "ToolSearch":
        return "cerca strumenti  " + squeeze(args.get("query", ""), 60)
    if name == "AskUserQuestion":
        return "chiede all'operatore"
    if name == "ExitPlanMode":
        return "propone il piano all'operatore"
    for key in ("file_path", "path", "query", "description", "command"):
        if isinstance(args.get(key), str):
            return "usa %s  %s" % (name, squeeze(args[key], 60))
    return "usa " + name


def outcome_line(record, tools):
    """Render a tool_result: refusal, error, or plain success -- never mixed."""
    message = record.get("message")
    blocks = message.get("content") if isinstance(message, dict) else None
    if not isinstance(blocks, list):
        return []
    lines = []
    for block in blocks:
        if not isinstance(block, dict) or block.get("type") != "tool_result":
            continue
        tool = tools.get(block.get("tool_use_id"), "l'azione")
        denial = record.get("toolDenialKind")
        if denial:
            reason = DENIAL_REASON.get(denial, "negato (%s)" % denial)
            lines.append((MARK_REFUSAL, "%s non eseguito: %s" % (tool, reason)))
        elif block.get("is_error"):
            detail = squeeze(_as_text(block.get("content")), 90)
            lines.append((MARK_ERROR, "%s fallito: %s" % (tool, detail)))
        else:
            lines.append((OUTCOME, "ok"))
    return lines


def _as_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(b.get("text", "") for b in content
                        if isinstance(b, dict) and b.get("type") == "text")
    return ""


def render(record, tools):
    """Return [(mark_or_None, text)] for one parsed record. May be empty."""
    kind = record.get("type")
    if kind in SKIP_TYPES:
        return []
    cwd = record.get("cwd") or ""
    message = record.get("message")

    if kind == "system":
        sub = record.get("subtype")
        if sub in SKIP_SYSTEM_SUBTYPES:
            return []
        text = squeeze(record.get("content") or sub or "", 100)
        if sub == "compact_boundary":
            return [(None, "contesto compattato")]
        return [(None, "sistema: " + text)] if text else []

    if kind == "assistant" and isinstance(message, dict):
        lines = []
        stop = message.get("stop_reason")
        blocks = message.get("content")
        if stop == "refusal":
            # Fold the refusal text in; do not also render it as ordinary talk.
            return [(MARK_REFUSAL,
                     "il modello ha rifiutato di rispondere: "
                     + squeeze(_as_text(blocks), 90))]
        if isinstance(blocks, list):
            for block in blocks:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "text":
                    said = squeeze(block.get("text", ""), 120)
                    if said:
                        lines.append((None, "dice: " + said))
                elif block.get("type") == "tool_use":
                    name = block.get("name", "?")
                    tools[block.get("id")] = name
                    args = block.get("input") or {}
                    lines.append((None, describe_tool(name, args, cwd)))
        if stop in ("end_turn", "stop_sequence"):
            lines.append((MARK_STOP, "turno concluso"))
        return lines

    if kind == "user" and isinstance(message, dict):
        content = message.get("content")
        if isinstance(content, list) and any(
                isinstance(b, dict) and b.get("type") == "tool_result"
                for b in content):
            return outcome_line(record, tools)
        if record.get("isMeta"):
            return []
        raw = _as_text(content) if isinstance(content, list) else content or ""
        if not isinstance(raw, str):
            return []
        # The TUI writes slash-command bookkeeping into the user stream. It is
        # not an operator request, and its markup is not for human eyes.
        name = re.search(r"<command-name>\s*(.*?)\s*</command-name>", raw)
        if name:
            return [(None, "comando: " + squeeze(name.group(1), 60))]
        if raw.lstrip().startswith("<local-command-stdout>"):
            return []
        return ([(None, "richiesta: " + squeeze(raw, 120))]
                if squeeze(raw, 120) else [])

    return []


def emit(stream, when, label, mark, text, show_label):
    tag = ("[%s] " % label) if show_label else ""
    stream.write("%s %s%s %s\n"
                 % (when, tag, (mark or PLAIN).ljust(MARK_WIDTH), text))
    stream.flush()


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Render Claude Code session transcripts in readable Italian.")
    ap.add_argument("sessions", nargs="*",
                    help="session id or path to a .jsonl (default: the latest)")
    ap.add_argument("-f", "--follow", action="store_true",
                    help="keep reading as the transcript grows")
    ap.add_argument("-n", "--latest", type=int, default=1, metavar="N",
                    help="render the N most recently modified sessions")
    ap.add_argument("--project", metavar="DIR",
                    help="project transcript dir (default: the slug for $PWD)")
    ap.add_argument("--label", action="store_true",
                    help="always prefix the session, even for a single one")
    ap.add_argument("--list", action="store_true",
                    help="list available transcripts and exit")
    args = ap.parse_args(argv)

    project = args.project or project_dir_for(os.getcwd())

    if args.list:
        try:
            names = sorted(os.listdir(project), reverse=True)
        except OSError:
            sys.stderr.write("nessuna sessione in %s\n" % project)
            return 1
        for name in names:
            if not name.endswith(".jsonl"):
                continue
            path = os.path.join(project, name)
            when = datetime.datetime.fromtimestamp(
                os.path.getmtime(path)).strftime("%Y-%m-%d %H:%M")
            sys.stdout.write("%s  %s\n" % (when, name[:-6]))
        return 0

    found = find_sessions(project, args.sessions, max(1, args.latest))
    if not found:
        sys.stderr.write("nessuna sessione trovata in %s\n" % project)
        return 1

    show_label = args.label or len(found) > 1
    readers = [Transcript(path, label) for path, label in found]
    tools = {}
    out = sys.stdout

    for reader in readers:
        if not os.path.exists(reader.path) and not args.follow:
            sys.stderr.write("transcript assente: %s\n" % reader.path)
            return 1
        if show_label:
            out.write("== sessione [%s] -> %s\n" % (reader.label, reader.path))
    out.flush()

    try:
        while True:
            batch = []
            for reader in readers:
                for raw in reader.poll():
                    if not raw.strip():
                        continue
                    try:
                        record = json.loads(raw)
                    except (ValueError, TypeError):
                        # A newline-terminated line that will not parse is real
                        # damage, not a live tail. Mark it and keep going.
                        # Report the damage, never echo it: the raw fragment is
                        # JSON, and JSON on screen is what this exists to avoid.
                        batch.append((reader.label, "--:--:--",
                                      [(MARK_BAD,
                                        "riga non interpretabile (%d caratteri), "
                                        "saltata" % len(raw))]))
                        continue
                    if not isinstance(record, dict):
                        continue
                    batch.append((reader.label, clock(record),
                                  render(record, tools)))
            for label, when, lines in batch:
                for mark, text in lines:
                    emit(out, when, label, mark, text, show_label)
            if not args.follow:
                break
            time.sleep(POLL_SECONDS)
    except (KeyboardInterrupt, BrokenPipeError):
        return 0

    for reader in readers:
        tail = reader.partial()
        if tail:
            emit(out, "--:--:--", reader.label, MARK_BAD,
                 "coda parziale non terminata (%d caratteri): la sessione sta "
                 "ancora scrivendo" % len(tail), show_label)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        sys.exit(0)
