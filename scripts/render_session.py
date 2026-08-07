#!/usr/bin/env python3
"""Render a Claude Code session JSONL as readable lines, one per event.

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

Language: every human string lives in STRINGS, keyed by language then by a
stable message key. Nothing human is written at a call site. Classification is
decided from the record alone and carried as a CATEGORY, never as a display
string -- so selecting a language cannot merge, drop or move an event between
refusal, error and stop. Adding a third language means adding one table to
STRINGS: no logic changes, and the fixture's key-parity check refuses a table
that half-lands. Argparse help stays English-only by policy, since it is what
documents the flag that selects the language.

Stdlib only. No daemon, no listener, no state on disk.

Usage:
    render_session.py                       # latest session for this repo
    render_session.py --lang it             # same, in Italian
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
MARK_WIDTH = 13

DEFAULT_LANG = "en"

# Stable, language-independent classification. render() emits these; only
# emit() ever turns one into something a human reads.
CAT_PLAIN = "plain"
CAT_OUTCOME = "outcome"
CAT_REFUSAL = "refusal"
CAT_ERROR = "error"
CAT_STOP = "stop"
CAT_UNREADABLE = "unreadable"

MARK_KEY = {
    CAT_PLAIN: "mark.plain",
    CAT_OUTCOME: "mark.outcome",
    CAT_REFUSAL: "mark.refusal",
    CAT_ERROR: "mark.error",
    CAT_STOP: "mark.stop",
    CAT_UNREADABLE: "mark.unreadable",
}

# Every human string, in one place. The marks that matter carry a WORD in
# every language, not only a glyph: an operator greps this output, and a
# terminal without unicode must still show which lines are the bad ones.
STRINGS = {
    "en": {
        "mark.plain": "·",
        "mark.outcome": "  ↳",
        "mark.refusal": "⛔ REFUSED",
        "mark.error": "✗ ERROR",
        "mark.stop": "■ STOP",
        "mark.unreadable": "⚠ UNREADABLE",

        "evt.request": "request: {text}",
        "evt.says": "says: {text}",
        "evt.command": "command: {name}",
        "evt.compacted": "context compacted",
        "evt.system": "system: {text}",
        "evt.turn_ended": "turn ended",
        "evt.model_refused": "the model refused to answer: {text}",
        "evt.ok": "ok",
        "evt.not_run": "{tool} not run: {reason}",
        "evt.failed": "{tool} failed: {detail}",
        "evt.the_action": "the action",
        "evt.unparseable": "unparseable line ({n} chars), skipped",
        "evt.partial_tail":
            "unterminated tail ({n} chars): the session is still writing",

        "denial.user-rejected": "refused by the operator",
        "denial.permission-rule": "refused by a permission rule",
        "denial.automode-blocked": "blocked by the auto-mode classifier",
        "denial.automode-unavailable": "auto-mode unavailable",
        "denial.other": "refused ({kind})",

        "act.read": "reads  {path}",
        "act.write": "writes  {path}",
        "act.edit": "edits  {path}",
        "act.notebook": "edits the notebook  {path}",
        "act.bash": "runs  {arg}",
        "act.glob": "searches files  {arg}",
        "act.grep": "searches text  {arg}",
        "act.skill": "uses the skill  {arg}",
        "act.agent": "delegates to a subagent ({kind})  {arg}",
        "act.fetch": "fetches  {arg}",
        "act.websearch": "searches the web  {arg}",
        "act.toolsearch": "searches tools  {arg}",
        "act.ask": "asks the operator",
        "act.plan": "proposes the plan to the operator",
        "act.generic_arg": "uses {name}  {arg}",
        "act.generic": "uses {name}",

        "hdr.session": "== session [{label}] -> {path}",
        "err.none_found": "no session found in {dir}",
        "err.missing": "missing transcript: {path}",
    },
    "it": {
        "mark.plain": "·",
        "mark.outcome": "  ↳",
        "mark.refusal": "⛔ RIFIUTO",
        "mark.error": "✗ ERRORE",
        "mark.stop": "■ STOP",
        "mark.unreadable": "⚠ ILLEGGIBILE",

        "evt.request": "richiesta: {text}",
        "evt.says": "dice: {text}",
        "evt.command": "comando: {name}",
        "evt.compacted": "contesto compattato",
        "evt.system": "sistema: {text}",
        "evt.turn_ended": "turno concluso",
        "evt.model_refused": "il modello ha rifiutato di rispondere: {text}",
        "evt.ok": "ok",
        "evt.not_run": "{tool} non eseguito: {reason}",
        "evt.failed": "{tool} fallito: {detail}",
        "evt.the_action": "l'azione",
        "evt.unparseable": "riga non interpretabile ({n} caratteri), saltata",
        "evt.partial_tail":
            "coda non terminata ({n} caratteri): la sessione sta ancora scrivendo",

        "denial.user-rejected": "negato dall'operatore",
        "denial.permission-rule": "negato da una regola di permessi",
        "denial.automode-blocked": "bloccato dal classificatore auto-mode",
        "denial.automode-unavailable": "auto-mode non disponibile",
        "denial.other": "negato ({kind})",

        "act.read": "legge  {path}",
        "act.write": "scrive  {path}",
        "act.edit": "modifica  {path}",
        "act.notebook": "modifica il notebook  {path}",
        "act.bash": "esegue  {arg}",
        "act.glob": "cerca file  {arg}",
        "act.grep": "cerca nel testo  {arg}",
        "act.skill": "usa la skill  {arg}",
        "act.agent": "delega a un sottoagente ({kind})  {arg}",
        "act.fetch": "scarica  {arg}",
        "act.websearch": "cerca sul web  {arg}",
        "act.toolsearch": "cerca strumenti  {arg}",
        "act.ask": "chiede all'operatore",
        "act.plan": "propone il piano all'operatore",
        "act.generic_arg": "usa {name}  {arg}",
        "act.generic": "usa {name}",

        "hdr.session": "== sessione [{label}] -> {path}",
        "err.none_found": "nessuna sessione trovata in {dir}",
        "err.missing": "transcript assente: {path}",
    },
}


class Catalog:
    """Message lookup for one language. A missing key raises, loudly."""

    def __init__(self, lang):
        self.lang = lang
        self._table = STRINGS[lang]

    def __call__(self, key, **kw):
        template = self._table[key]
        return template.format(**kw) if kw else template


# toolDenialKind is the literal field Claude Code writes on the user record
# when a tool was blocked instead of run. Absent means the tool actually ran.
DENIAL_KINDS = ("user-rejected", "permission-rule", "automode-blocked",
                "automode-unavailable")

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


def _as_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(b.get("text", "") for b in content
                        if isinstance(b, dict) and b.get("type") == "text")
    return ""


def describe_tool(t, name, args, cwd):
    """One phrase for a tool call: the verb and its object."""
    def p(key):
        return shorten_path(args.get(key, ""), cwd)

    if name == "Read":
        return t("act.read", path=p("file_path"))
    if name == "Write":
        return t("act.write", path=p("file_path"))
    if name in ("Edit", "MultiEdit"):
        return t("act.edit", path=p("file_path"))
    if name == "NotebookEdit":
        return t("act.notebook", path=p("notebook_path"))
    if name == "Bash":
        return t("act.bash", arg=squeeze(args.get("command", ""), 88))
    if name == "Glob":
        return t("act.glob", arg=squeeze(args.get("pattern", ""), 60))
    if name == "Grep":
        return t("act.grep", arg=squeeze(args.get("pattern", ""), 60))
    if name == "Skill":
        return t("act.skill", arg=squeeze(args.get("skill", ""), 40))
    if name == "Agent":
        return t("act.agent", kind=args.get("subagent_type", "?"),
                 arg=squeeze(args.get("description", ""), 60))
    if name == "WebFetch":
        return t("act.fetch", arg=squeeze(args.get("url", ""), 70))
    if name == "WebSearch":
        return t("act.websearch", arg=squeeze(args.get("query", ""), 60))
    if name == "ToolSearch":
        return t("act.toolsearch", arg=squeeze(args.get("query", ""), 60))
    if name == "AskUserQuestion":
        return t("act.ask")
    if name == "ExitPlanMode":
        return t("act.plan")
    for key in ("file_path", "path", "query", "description", "command"):
        if isinstance(args.get(key), str):
            return t("act.generic_arg", name=name, arg=squeeze(args[key], 60))
    return t("act.generic", name=name)


def outcome_line(t, record, tools):
    """Render a tool_result: refusal, error, or plain success -- never mixed.

    The branch order is the whole point. A blocked tool never ran, so it is a
    refusal even though it also carries is_error; only a tool that actually
    ran can have failed.
    """
    message = record.get("message")
    blocks = message.get("content") if isinstance(message, dict) else None
    if not isinstance(blocks, list):
        return []
    lines = []
    for block in blocks:
        if not isinstance(block, dict) or block.get("type") != "tool_result":
            continue
        tool = tools.get(block.get("tool_use_id")) or t("evt.the_action")
        denial = record.get("toolDenialKind")
        if denial:
            reason = (t("denial." + denial) if denial in DENIAL_KINDS
                      else t("denial.other", kind=denial))
            lines.append((CAT_REFUSAL, t("evt.not_run", tool=tool, reason=reason)))
        elif block.get("is_error"):
            detail = squeeze(_as_text(block.get("content")), 90)
            lines.append((CAT_ERROR, t("evt.failed", tool=tool, detail=detail)))
        else:
            lines.append((CAT_OUTCOME, t("evt.ok")))
    return lines


def render(t, record, tools):
    """Return [(category, text)] for one parsed record. May be empty.

    The category is decided from the record alone; `t` only dresses it.
    """
    kind = record.get("type")
    if kind in SKIP_TYPES:
        return []
    cwd = record.get("cwd") or ""
    message = record.get("message")

    if kind == "system":
        sub = record.get("subtype")
        if sub in SKIP_SYSTEM_SUBTYPES:
            return []
        if sub == "compact_boundary":
            return [(CAT_PLAIN, t("evt.compacted"))]
        text = squeeze(record.get("content") or sub or "", 100)
        return [(CAT_PLAIN, t("evt.system", text=text))] if text else []

    if kind == "assistant" and isinstance(message, dict):
        lines = []
        stop = message.get("stop_reason")
        blocks = message.get("content")
        if stop == "refusal":
            # Fold the refusal text in; do not also render it as ordinary talk.
            return [(CAT_REFUSAL,
                     t("evt.model_refused", text=squeeze(_as_text(blocks), 90)))]
        if isinstance(blocks, list):
            for block in blocks:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "text":
                    said = squeeze(block.get("text", ""), 120)
                    if said:
                        lines.append((CAT_PLAIN, t("evt.says", text=said)))
                elif block.get("type") == "tool_use":
                    name = block.get("name", "?")
                    tools[block.get("id")] = name
                    args = block.get("input") or {}
                    lines.append((CAT_PLAIN,
                                  describe_tool(t, name, args, cwd)))
        if stop in ("end_turn", "stop_sequence"):
            lines.append((CAT_STOP, t("evt.turn_ended")))
        return lines

    if kind == "user" and isinstance(message, dict):
        content = message.get("content")
        if isinstance(content, list) and any(
                isinstance(b, dict) and b.get("type") == "tool_result"
                for b in content):
            return outcome_line(t, record, tools)
        if record.get("isMeta"):
            return []
        raw = _as_text(content) if isinstance(content, list) else content or ""
        if not isinstance(raw, str):
            return []
        # The TUI writes slash-command bookkeeping into the user stream. It is
        # not an operator request, and its markup is not for human eyes.
        named = re.search(r"<command-name>\s*(.*?)\s*</command-name>", raw)
        if named:
            return [(CAT_PLAIN,
                     t("evt.command", name=squeeze(named.group(1), 60)))]
        if raw.lstrip().startswith("<local-command-stdout>"):
            return []
        text = squeeze(raw, 120)
        return [(CAT_PLAIN, t("evt.request", text=text))] if text else []

    return []


def emit(stream, t, when, label, category, text, show_label):
    tag = ("[%s] " % label) if show_label else ""
    mark = t(MARK_KEY[category]).ljust(MARK_WIDTH)
    stream.write("%s %s%s %s\n" % (when, tag, mark, text))
    stream.flush()


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Render Claude Code session transcripts as readable lines.")
    ap.add_argument("sessions", nargs="*",
                    help="session id or path to a .jsonl (default: the latest)")
    ap.add_argument("-f", "--follow", action="store_true",
                    help="keep reading as the transcript grows")
    ap.add_argument("-n", "--latest", type=int, default=1, metavar="N",
                    help="render the N most recently modified sessions")
    ap.add_argument("--project", metavar="DIR",
                    help="project transcript dir (default: the slug for $PWD)")
    ap.add_argument("--lang", choices=sorted(STRINGS), default=DEFAULT_LANG,
                    help="output language (default: %s)" % DEFAULT_LANG)
    ap.add_argument("--label", action="store_true",
                    help="always prefix the session, even for a single one")
    ap.add_argument("--list", action="store_true",
                    help="list available transcripts and exit")
    args = ap.parse_args(argv)

    t = Catalog(args.lang)
    project = args.project or project_dir_for(os.getcwd())

    if args.list:
        try:
            names = sorted(os.listdir(project), reverse=True)
        except OSError:
            sys.stderr.write(t("err.none_found", dir=project) + "\n")
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
        sys.stderr.write(t("err.none_found", dir=project) + "\n")
        return 1

    show_label = args.label or len(found) > 1
    readers = [Transcript(path, label) for path, label in found]
    tools = {}
    out = sys.stdout

    for reader in readers:
        if not os.path.exists(reader.path) and not args.follow:
            sys.stderr.write(t("err.missing", path=reader.path) + "\n")
            return 1
        if show_label:
            out.write(t("hdr.session", label=reader.label, path=reader.path)
                      + "\n")
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
                                      [(CAT_UNREADABLE,
                                        t("evt.unparseable", n=len(raw)))]))
                        continue
                    if not isinstance(record, dict):
                        continue
                    batch.append((reader.label, clock(record),
                                  render(t, record, tools)))
            for label, when, lines in batch:
                for category, text in lines:
                    emit(out, t, when, label, category, text, show_label)
            if not args.follow:
                break
            time.sleep(POLL_SECONDS)
    except (KeyboardInterrupt, BrokenPipeError):
        return 0

    for reader in readers:
        tail = reader.partial()
        if tail:
            emit(out, t, "--:--:--", reader.label, CAT_UNREADABLE,
                 t("evt.partial_tail", n=len(tail)), show_label)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        sys.exit(0)
