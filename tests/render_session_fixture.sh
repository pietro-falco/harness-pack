#!/usr/bin/env bash
# Fixture for scripts/render_session.py -- the session-transcript renderer.
#
# The renderer turns a Claude Code session JSONL into one human-readable line
# per event. The two properties that matter, and that this fixture pins:
#
#   1. A live JSONL always has a ragged tail. A malformed line must be MARKED
#      and skipped, and every event AFTER it must still render. A renderer that
#      dies on the tail is useless exactly when you need it -- mid-run.
#   2. A blocked action must never read as successful work. `toolDenialKind`
#      and a model-level `stop_reason: "refusal"` are refusals, not activity.
#      Rendering a refusal as ordinary output is the receipt defect moved to
#      the screen.
#
# Run standalone: bash tests/render_session_fixture.sh
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
PACK="$PWD"
RENDER="$PACK/scripts/render_session.py"
fail=0

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/render_session.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

SID_A="aaaa1111-0000-4000-8000-000000000001"
SID_B="bbbb2222-0000-4000-8000-000000000002"
PROJ="$TMPD/project"
mkdir -p "$PROJ"

# ---------------------------------------------------------------------------
# Build the fixture transcripts. Shapes are copied from real session JSONL:
# assistant records carry message.content[] blocks (tool_use / text) and
# message.stop_reason; the matching user record carries the tool_result block
# and, when the tool was BLOCKED rather than run, a top-level toolDenialKind.
# ---------------------------------------------------------------------------
python3 - "$PROJ" "$SID_A" "$SID_B" <<'PY'
import json, os, sys

proj, sid_a, sid_b = sys.argv[1], sys.argv[2], sys.argv[3]
CWD = "/Users/op/Code/harness-pack"


def rec(sid, typ, ts, **kw):
    d = {"type": typ, "sessionId": sid, "timestamp": ts, "cwd": CWD,
         "gitBranch": "main", "uuid": "u-%s-%s" % (sid[:4], ts[-6:-1])}
    d.update(kw)
    return d


def assistant(sid, ts, content, stop_reason="tool_use", **kw):
    return rec(sid, "assistant", ts,
               message={"role": "assistant", "model": "claude-opus-5",
                        "stop_reason": stop_reason, "content": content}, **kw)


def result(sid, ts, tuid, text, is_error=False, **kw):
    blk = {"type": "tool_result", "tool_use_id": tuid, "content": text}
    if is_error:
        blk["is_error"] = True
    return rec(sid, "user", ts,
               message={"role": "user", "content": [blk]}, **kw)


a = []
# 1. operator prompt
a.append(rec(sid_a, "user", "2026-08-07T09:00:01.000Z",
             message={"role": "user", "content": "Sistema il launcher."}))
# Slash-command bookkeeping the TUI writes into the user stream. It is not an
# operator request, and its markup must never reach the rendered view.
a.append(rec(sid_a, "user", "2026-08-07T09:00:01.200Z",
             message={"role": "user", "content":
                      "<command-name>/usage</command-name>\n"
                      "<command-message>usage</command-message>\n"
                      "<command-args></command-args>"}))
a.append(rec(sid_a, "user", "2026-08-07T09:00:01.400Z",
             message={"role": "user", "content":
                      "<local-command-stdout>Current usage: 12%</local-command-stdout>"}))
# 2-3. a tool that RAN and succeeded
a.append(assistant(sid_a, "2026-08-07T09:00:02.000Z", [
    {"type": "tool_use", "id": "toolu_read1", "name": "Read",
     "input": {"file_path": CWD + "/scripts/launch_worker.sh"}}]))
a.append(result(sid_a, "2026-08-07T09:00:03.000Z", "toolu_read1",
                "     1\t#!/usr/bin/env bash\n     2\tset -euo pipefail"))
# 4-5. a tool that was BLOCKED -- never ran. This must NOT read as work done.
a.append(assistant(sid_a, "2026-08-07T09:00:04.000Z", [
    {"type": "tool_use", "id": "toolu_bash1", "name": "Bash",
     "input": {"command": "rm -rf /Users/op/Code/harness-pack/receipts",
               "description": "Clear receipts"}}]))
a.append(result(sid_a, "2026-08-07T09:00:05.000Z", "toolu_bash1",
                "The user doesn't want to take this action right now.",
                is_error=True, toolDenialKind="user-rejected",
                toolUseResult="Error: The user doesn't want to take this action right now."))
a.append("__TRUNCATE_HERE__")
# 7-8. a tool that RAN and FAILED -- an error, categorically not a refusal
a.append(assistant(sid_a, "2026-08-07T09:00:07.000Z", [
    {"type": "tool_use", "id": "toolu_edit1", "name": "Edit",
     "input": {"file_path": CWD + "/scripts/launch_worker.sh",
               "old_string": "set -e", "new_string": "set -euo pipefail"}}]))
a.append(result(sid_a, "2026-08-07T09:00:08.000Z", "toolu_edit1",
                "Exit code 1\nString to replace not found in file.", is_error=True))
# 9. model-level refusal
a.append(assistant(sid_a, "2026-08-07T09:00:09.000Z", [
    {"type": "text", "text": "API Error: safeguards flagged this message."}],
    stop_reason="refusal"))
# 10. clean end of turn
a.append(assistant(sid_a, "2026-08-07T09:00:10.000Z", [
    {"type": "text", "text": "Ho fermato il lavoro."}], stop_reason="end_turn"))

with open(os.path.join(proj, sid_a + ".jsonl"), "w", encoding="utf-8") as fh:
    for e in a:
        if e == "__TRUNCATE_HERE__":
            # A line cut mid-object, still newline-terminated: the shape a
            # crashed or flushed-mid-write session leaves behind.
            fh.write('{"type":"assistant","sessionId":"%s","timestamp":"2026-08-07T09:00:06.0'
                     % sid_a + "\n")
            continue
        fh.write(json.dumps(e, ensure_ascii=False) + "\n")

b = [rec(sid_b, "user", "2026-08-07T09:00:01.500Z",
         message={"role": "user", "content": "Aggiorna la ADR."}),
     assistant(sid_b, "2026-08-07T09:00:02.500Z", [
         {"type": "tool_use", "id": "toolu_w1", "name": "Write",
          "input": {"file_path": CWD + "/docs/adrs/ADR-010.md", "content": "x"}}]),
     result(sid_b, "2026-08-07T09:00:03.500Z", "toolu_w1", "File created.")]
with open(os.path.join(proj, sid_b + ".jsonl"), "w", encoding="utf-8") as fh:
    for e in b:
        fh.write(json.dumps(e, ensure_ascii=False) + "\n")
PY

FIX_A="$PROJ/$SID_A.jsonl"
FIX_B="$PROJ/$SID_B.jsonl"
OUT="$TMPD/out.txt"

echo "== render_session: finished file with a truncated line =="
set +e
python3 "$RENDER" "$FIX_A" >"$OUT" 2>"$TMPD/err"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "FAIL [must survive a malformed line and exit 0]: rc=$rc"
  sed -n '1,15p' "$TMPD/err"
  fail=1
else
  echo "ok [survives a malformed line, rc=0]"
fi

check() { # check <label> <expected-count> <pattern>
  n=$(grep -c -- "$3" "$OUT" 2>/dev/null || true)
  if [ "$n" != "$2" ]; then
    echo "FAIL [$1]: expected $2 line(s) matching '$3', got $n"; fail=1
  else
    echo "ok [$1]"
  fi
}

# The malformed line is marked, not silently dropped.
check "malformed line is marked ILLEGGIBILE" 1 "ILLEGGIBILE"
# ...and the renderer keeps going: the Edit AFTER the truncated line renders.
n=$(grep -c "launch_worker.sh" "$OUT" 2>/dev/null || true)
if [ "$n" -lt 2 ]; then
  echo "FAIL [events after the malformed line still render]: launch_worker.sh seen $n time(s), want >=2"
  fail=1
else
  echo "ok [events after the malformed line still render]"
fi

# Refusals: the permission denial AND the model refusal, both marked.
check "permission denial marked RIFIUTO" 2 "RIFIUTO"
# A run-and-fail is an error, never a refusal.
check "failed tool marked ERRORE" 1 "ERRORE"
# End of turn is marked.
check "end of turn marked STOP" 1 "STOP"

# THE core assertion: a blocked action must not be rendered as successful work.
# Only the Read actually succeeded. If the denied Bash renders as ok, this is 2.
ok_n=$(grep -c "ok$" "$OUT" 2>/dev/null || true)
if [ "$ok_n" != "1" ]; then
  echo "FAIL [a refusal must not render as successful work]: $ok_n success outcome(s), want exactly 1"
  fail=1
else
  echo "ok [a refusal does not render as successful work]"
fi

# The denied command's outcome line carries RIFIUTO, not a success token.
if grep -q "user-rejected\|negato\|rifiut" "$OUT"; then
  echo "ok [denial reason is surfaced in prose]"
else
  echo "FAIL [denial reason must be surfaced in prose]"; fail=1
fi

# A slash command reads as a command, and its markup never reaches the screen.
check "slash command rendered as a command" 1 "comando: /usage"
if grep -q "command-name\|local-command-stdout\|command-args" "$OUT"; then
  echo "FAIL [TUI command markup must not reach the rendered view]"; fail=1
else
  echo "ok [no TUI command markup in the rendered view]"
fi

# The outcome continuation line must not also carry the ordinary-activity glyph.
if grep -q "↳ ·" "$OUT"; then
  echo "FAIL [outcome lines must not carry the plain-activity glyph]"; fail=1
else
  echo "ok [outcome lines carry no stray activity glyph]"
fi

# Machine field names and uuids must not leak into the human view.
if grep -qi "toolDenialKind\|stop_reason\|tool_use_id\|toolu_\|\"type\":" "$OUT"; then
  echo "FAIL [raw JSON field names / uuids must not leak into the rendered view]"
  grep -n -i "toolDenialKind\|stop_reason\|tool_use_id\|toolu_\|\"type\":" "$OUT" \
    | sed -n '1,3p' || true
  fail=1
else
  echo "ok [no raw field names or tool uuids in the rendered view]"
fi

echo "== render_session: multiple sessions, each line names its session =="
set +e
python3 "$RENDER" "$FIX_A" "$FIX_B" >"$TMPD/multi.txt" 2>/dev/null
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "FAIL [multi-session render must exit 0]: rc=$rc"; fail=1
else
  unlabelled=$(grep -c -v "\[" "$TMPD/multi.txt" 2>/dev/null || true)
  if [ "$unlabelled" != "0" ]; then
    echo "FAIL [every line must name its session when following >1]: $unlabelled unlabelled"
    fail=1
  elif ! grep -q "aaaa1111" "$TMPD/multi.txt" || ! grep -q "bbbb2222" "$TMPD/multi.txt"; then
    echo "FAIL [both session labels must appear]"; fail=1
  else
    echo "ok [every line names its session]"
  fi
fi

echo "== render_session: growing file, unterminated tail =="
# A file still being written ends mid-line with no newline. That tail must be
# held back (not rendered as a bogus event) and flagged, and the completed
# events before it must all render.
head -c 400 "$FIX_B" >"$TMPD/growing.jsonl"
set +e
python3 "$RENDER" "$TMPD/growing.jsonl" >"$TMPD/grow.txt" 2>/dev/null
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "FAIL [unterminated tail must not crash the renderer]: rc=$rc"; fail=1
elif ! grep -q "ILLEGGIBILE\|parziale" "$TMPD/grow.txt"; then
  echo "FAIL [unterminated tail must be flagged, not silently dropped]"; fail=1
else
  echo "ok [unterminated tail flagged, not crashed on]"
fi

echo "== render_session: --follow picks up appended events =="
: >"$TMPD/live.jsonl"
python3 "$RENDER" --follow "$TMPD/live.jsonl" >"$TMPD/live.txt" 2>/dev/null &
follow_pid=$!
cat "$FIX_A" >>"$TMPD/live.jsonl"
i=0
while [ "$i" -lt 60 ]; do
  if grep -q "STOP" "$TMPD/live.txt" 2>/dev/null; then break; fi
  i=$((i + 1)); sleep 0.1
done
kill "$follow_pid" 2>/dev/null || true
wait "$follow_pid" 2>/dev/null || true
if grep -q "STOP" "$TMPD/live.txt" 2>/dev/null && grep -q "RIFIUTO" "$TMPD/live.txt" 2>/dev/null; then
  echo "ok [--follow renders events appended after start]"
else
  echo "FAIL [--follow must render events appended after start]"
  sed -n '1,10p' "$TMPD/live.txt" 2>/dev/null
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "RENDER SESSION FIXTURE: FAILED"
  exit 1
fi
echo "RENDER SESSION FIXTURE: PASSED"
