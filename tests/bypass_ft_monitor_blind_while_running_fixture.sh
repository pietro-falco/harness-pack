#!/usr/bin/env bash
# FT-27 -- monitor-blind-while-running. The live view must show an
# out-of-surface call within its declared threshold: conformance_watch.py
# declares that a line appended to stream.jsonl is reflected in
# conformance.state within 3 poll intervals (interval 100ms -> 300ms).
# An out-of-surface EXECUTED call is appended mid-run; the state line must
# show oos-exec=1 within the declared threshold.
# GREEN: detected within 300ms. RED: never detected within 2s -- the
# monitor is blind. UNMEASURED (2): detected but late (load, not
# blindness -- re-run on an unloaded machine), or machinery absent.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="${CONFORMANCE_CORPUS:-$ROOT/tests/fixtures/conformance_corpus.py}"
WATCH="${CONFORMANCE_WATCH:-$ROOT/scripts/conformance_watch.py}"
for f in "$CORPUS" "$WATCH"; do
  [ -f "$f" ] || { echo "UNMEASURED: $f absent" >&2; exit 2; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft27.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
python3 - "$CORPUS" "$WATCH" "$WORK" <<'PY'
import json, os, subprocess, sys, time
corpus, watch, work = sys.argv[1], sys.argv[2], sys.argv[3]
run = os.path.join(work, "run")
if subprocess.run([sys.executable, corpus, "oos-run", run]).returncode != 0:
    print("UNMEASURED: corpus failed"); sys.exit(2)
lines = open(os.path.join(run, "stream.jsonl")).read().splitlines(True)
open(os.path.join(run, "stream.jsonl"), "w").writelines(lines[:7])
proc = subprocess.Popen([sys.executable, watch, run,
                         "--interval-ms", "100", "--max-seconds", "8"])
state = os.path.join(run, "conformance.state")
t0 = time.time()
while not os.path.isfile(state):
    if time.time() - t0 > 3:
        proc.kill()
        print("UNMEASURED: watch never wrote a state line"); sys.exit(2)
    time.sleep(0.02)
appended = time.time()
with open(os.path.join(run, "stream.jsonl"), "a") as fh:
    fh.writelines(lines[7:])
latency = None
while time.time() - appended < 2.0:
    if "oos-exec=1" in open(state).read():
        latency = (time.time() - appended) * 1000
        break
    time.sleep(0.02)
proc.terminate()
proc.wait()
if latency is None:
    print("RED: out-of-surface call never shown within 2s; monitor blind")
    sys.exit(1)
if latency > 300:
    print("UNMEASURED: shown after %dms, over the declared 300ms; "
          "attributable to load, not blindness" % latency)
    sys.exit(2)
print("GREEN: out-of-surface call shown in %dms (declared 300ms)" % latency)
sys.exit(0)
PY
