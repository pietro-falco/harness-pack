#!/usr/bin/env bash
# bypass_att_two_digest_shapes -- the falsifier ADR-018 D3 names.
#
# THE ASSERTION (ADR-018 D3, its Verification row): "A fixture that sweeps both
# repositories for `{\"alg\":` and for a `DigestSet`, and **fails if both shapes
# are emitted by new artifacts**." D3 supersedes harnesswright/ADR-0008 D5 on
# the shape only, and its whole cost is paid now because "the first artifact
# emitted under either shape makes the other one a migration".
#
# THIS FIXTURE IS GREEN BY VACUITY, AND THE VACUITY IS THE POINT. DO NOT DELETE
# IT AS AN ADR-017 DEFECT. Read the ADR's own words first: "It is green today by
# vacuity -- zero artifacts of either shape -- and that vacuity is the point: it
# must go RED the moment the second convention acquires its first artifact, not
# at some later audit."
#
# The difference between this row and the defect ADR-017 is about is the
# difference between a gate that has nothing to catch yet and a gate that cannot
# catch anything. ADR-017's defect is a falsifier nobody runs and a register
# that certifies it anyway. What makes this row a gate rather than a blind pass
# is the POSITIVE CONTROL below: two files are fabricated under $WORK, one
# carrying each shape, and the sweep must find both and the verdict function
# must return RED on them. A green from this fixture therefore says "the corpus
# holds at most one convention", never "the detector found nothing".
#
# THE TWO SHAPES.
#   alg-value  {"alg": "sha256", "value": "<hex>"} -- harnesswright/ADR-0008 D5
#              at :111, Accepted, and superseded on this point by D3.
#   digestset  {"<algorithm-name>": "<hex>"} used as the value of a field --
#              in-toto's shape, statement.md:15, resource_descriptor.md:46.
#              Recognised as an object whose keys are ALL registry algorithm
#              names and whose values are ALL lowercase hex. Algorithm names
#              read from spec/v1/digest_set.md @ in-toto/attestation main,
#              sha256 0b1889fdea7f6d623b41555632aedf04ee4398cf02a32002060608c75ebb038e,
#              8873 bytes -- the digest ADR-018 pins, re-fetched and re-matched
#              byte for byte when this fixture was written. Names at :32, :38
#              and :103.
#
# PROSE IS OUT OF SCOPE BY CONSTRUCTION. D3's subject is emitted artifacts, and
# the sweep enumerates tracked `*.json` and `*.jsonl` only. The ADRs that quote
# both shapes -- this repository's own ADR-018 among them -- are `.md` and are
# never read. That is why ADR-018's Context could record a sweep for `"alg"`
# returning "one hit, the ADR sentence itself" while this fixture returns zero:
# it sweeps a different thing, on purpose.
#
# FORM IS READ FROM BYTES, NEVER FROM THE FILENAME. Enumeration is still by
# glob; the PARSE is routed by content -- a whole JSON document first,
# line-delimited JSON as the fallback. The previous rule routed on
# `path.endswith(".jsonl")`, and that rule is false in this family: the two
# repositories carry OPPOSITE naming conventions for line-delimited receipts and
# the sweep spans both. Under the old rule every line-delimited receipt named
# `.json` came back unparseable, the scope guard below fired, and this row
# exited 2 -- not because the corpus held two digest conventions, but because
# the sweeper could not read its own declared scope.
#
# The renaming experiment was run and is NOT what landed: renaming those files
# to `.jsonl` also produced zero findings, which establishes that the green
# underneath them is true rather than masked. The defect was in the reader.
#
# THE ROUTING CARRIES ITS OWN FALSIFIER. CONTROL B is a line-delimited file
# named `.json`. It is swept twice on every run: once under the rule this
# fixture asserts, where it must yield exactly one finding of each shape, and
# once under the OLD extension rule, where it must come back unparseable. If the
# old rule ever stops failing on it, the subject of this repair has moved and
# this fixture refuses to certify anything. CONTROL C is the other direction:
# genuinely malformed bytes -- truncated, conflict-marked, empty -- must STILL
# come back unparseable under the new rule. A fallback that swallowed those
# would have bought the green by making the reader blind.
#
# A PARTIAL READ IS NOT A READ. When a line-delimited file fails on line k, the
# findings from lines 1..k-1 are discarded and the file is reported unparseable.
# Counting what was read before the failure would let a half-read file
# contribute to the verdict.
#
# AN EMPTY SCOPE IS NOT A GREEN. If the live file list comes back empty, the
# fixture is broken rather than green: a sweep that enumerated nothing has
# measured nothing.
#
# KNOWN DEFECT, NOT REPAIRED HERE (carried as an OR for THR-ADR-DEBT): broken()
# exits 2 on four distinct roads -- sweeper down on the control, positive
# control outside 1/1/RED, PACK not a git repository, live files unreadable. The
# register reads the code and not the message, so "the corpus is illegible" and
# "the control is broken" are indistinguishable to it. Changing that semantics
# changes what the whole register accuses, which is an ADR-017-shaped decision
# and not a line in this commit.
#
# harnesswright is OPTIONAL, exactly as scripts/harness_stats.py:281 already
# treats it ("harnesswright is optional (ADR-005 D6)"), and its absence is
# printed rather than swallowed. A narrowed sweep is reported in as many words,
# because a shape this fixture did not look at is a shape it cannot report on.
#
# DECLARED GREEN, read from this header and never from a run (ADR-017 D6). It
# goes RED when the corpus holds artifacts of both shapes -- which is the day
# the family acquired two digest conventions and D3 was not enforced.
#
# Nothing outside $WORK is written; both repositories are read-only here.
#
# Exit codes: 0 invariant holds, 1 red, 2 the fixture could not set up.
set -uo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hp-att-shapes.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

note() { printf '     %s\n' "$*"; }
broken() { echo "FIXTURE BROKEN: $*" >&2; exit 2; }

# The sweeper. Reads a NUL-free list of "<label>\t<path>" on argv[1] and prints
# one finding per shape occurrence as "<shape> <label> <jsonpath>". A file it
# cannot read in full is reported as "unparseable <label> <reason>" and
# contributes nothing, so the caller can refuse to certify a scope it did not
# actually cover. The last line is always "routed whole=<n> lines=<n>
# extension=<n>", so a caller can tell a completed sweep from a truncated one.
#
# SWEEP_ROUTING selects the rule. "content" is the rule this fixture asserts.
# "extension" is the OLD rule, kept only so the controls can exercise it and
# prove it fails where the new one must pass; it is never used on the live
# corpus.
cat > "$WORK/sweep.py" <<'SWEEPER'
import json, os, sys

ROUTING = os.environ.get("SWEEP_ROUTING", "content")
if ROUTING not in ("content", "extension"):
    sys.stderr.write("sweep: unknown SWEEP_ROUTING %r\n" % ROUTING)
    sys.exit(3)

# in-toto DigestSet registry, digest_set.md:32, :38, :103.
ALGS = {
    "sha256", "sha224", "sha384", "sha512", "sha512_224", "sha512_256",
    "sha3_224", "sha3_256", "sha3_384", "sha3_512", "shake128", "shake256",
    "blake2b", "blake2s", "ripemd160", "sm3", "gost", "sha1", "md5",
    "dirhash", "gitcommit", "gittree", "gitblob", "gittag",
}
HEX = set("0123456789abcdef")

def is_tagged_pair(obj):
    return isinstance(obj, dict) and "alg" in obj and "value" in obj

def is_digest_set(obj):
    if not isinstance(obj, dict) or not obj:
        return False
    for k, v in obj.items():
        if not isinstance(k, str) or k.lower() not in ALGS:
            return False
        if not isinstance(v, str) or not v or not set(v) <= HEX:
            return False
    return True

def walk(obj, path, label, out):
    if isinstance(obj, dict):
        if is_tagged_pair(obj):
            out.append(("alg-value", label, path))
        elif is_digest_set(obj):
            out.append(("digestset", label, path))
        for k, v in obj.items():
            walk(v, "%s.%s" % (path, k), label, out)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            walk(v, "%s[%d]" % (path, i), label, out)

def parse_whole(data, label, out):
    walk(json.loads(data), "$", label, out)

def parse_lines(data, label, out):
    for i, raw in enumerate(data.split(b"\n"), 1):
        if raw.strip():
            walk(json.loads(raw), "$L%d" % i, label, out)

def sweep_file(path, label):
    """(findings, how, error). findings is empty whenever error is set: a file
    is read in full or not read at all."""
    with open(path, "rb") as f:
        data = f.read()
    local = []
    if ROUTING == "extension":
        try:
            if path.endswith(".jsonl"):
                parse_lines(data, label, local)
            else:
                parse_whole(data, label, local)
        except Exception as exc:
            return [], "extension", type(exc).__name__
        return local, "extension", None
    try:
        parse_whole(data, label, local)
        return local, "whole", None
    except Exception:
        local = []
    try:
        parse_lines(data, label, local)
    except Exception as exc:
        return [], "lines", type(exc).__name__
    if not data.strip():
        return [], "lines", "EmptyFile"
    return local, "lines", None

findings = []
routed = {"whole": 0, "lines": 0, "extension": 0}
for row in open(sys.argv[1], encoding="utf-8"):
    row = row.rstrip("\n")
    if not row:
        continue
    label, path = row.split("\t", 1)
    try:
        local, how, err = sweep_file(path, label)
    except Exception as exc:
        print("unparseable %s %s" % (label, type(exc).__name__))
        continue
    if err is not None:
        print("unparseable %s %s" % (label, err))
        continue
    routed[how] = routed.get(how, 0) + 1
    findings.extend(local)

for shape, label, path in findings:
    print("%s %s %s" % (shape, label, path))
print("routed whole=%d lines=%d extension=%d"
      % (routed["whole"], routed["lines"], routed["extension"]))
SWEEPER

# The verdict function, applied identically to the control corpus and to the
# live one. It is a function and not an inline test precisely so that the
# control can exercise the same code that judges the corpus.
verdict() {  # $1 = findings file -> echoes RED or GREEN
  local a d
  a="$(awk '$1 == "alg-value"' "$1" | grep -c .)"
  d="$(awk '$1 == "digestset"' "$1" | grep -c .)"
  if [ "$a" -gt 0 ] && [ "$d" -gt 0 ]; then echo "RED"; else echo "GREEN"; fi
}

count() {  # $1 = findings file, $2 = first-field key
  awk -v k="$2" '$1 == k' "$1" | grep -c .
}

sweep() {  # $1 = routing, $2 = list, $3 = out, $4 = err
  SWEEP_ROUTING="$1" python3 "$WORK/sweep.py" "$2" > "$3" 2>"$4"
}

echo "== bypass_att_two_digest_shapes: one digest convention, not two (ADR-018 D3) =="

# ---- CONTROL A: the sweep can see both shapes, and the verdict can fail ------
cat > "$WORK/ctl-alg.json" <<'CTLA'
{"artifact": {"name": "control", "digest": {"alg": "sha256", "value":
"0000000000000000000000000000000000000000000000000000000000000000"}}}
CTLA
cat > "$WORK/ctl-ds.json" <<'CTLD'
{"subject": [{"name": "control", "digest": {"sha256": "1111111111111111111111111111111111111111111111111111111111111111"}}]}
CTLD
printf 'control\t%s\ncontrol\t%s\n' "$WORK/ctl-alg.json" "$WORK/ctl-ds.json" > "$WORK/ctl.list"
sweep content "$WORK/ctl.list" "$WORK/ctl.findings" "$WORK/ctl.err" \
  || broken "the sweeper failed on the control corpus: $(head -3 "$WORK/ctl.err")"
CTL_A="$(count "$WORK/ctl.findings" alg-value)"
CTL_D="$(count "$WORK/ctl.findings" digestset)"
CTL_VERDICT="$(verdict "$WORK/ctl.findings")"
if [ "$CTL_A" -ne 1 ] || [ "$CTL_D" -ne 1 ] || [ "$CTL_VERDICT" != "RED" ]; then
  broken "positive control: alg-value=$CTL_A digestset=$CTL_D verdict=$CTL_VERDICT, expected 1/1/RED. A green below would mean nothing"
fi
note "control A (both shapes, fabricated) -> alg-value=$CTL_A digestset=$CTL_D, verdict=$CTL_VERDICT"

# ---- CONTROL B: line-delimited content behind a .json name ------------------
# The falsifier of the routing rule itself. Under content routing it must be
# read; under the old extension routing it must NOT be.
cat > "$WORK/ctl-lines.json" <<'CTLL'
{"type": "thread.started", "digest": {"sha256": "2222222222222222222222222222222222222222222222222222222222222222"}}
{"type": "turn.completed", "artifact": {"digest": {"alg": "sha256", "value": "3333333333333333333333333333333333333333333333333333333333333333"}}}
CTLL
printf 'ctlB\t%s\n' "$WORK/ctl-lines.json" > "$WORK/ctlb.list"

sweep content "$WORK/ctlb.list" "$WORK/ctlb.new" "$WORK/ctlb.err" \
  || broken "the sweeper failed on control B under content routing: $(head -3 "$WORK/ctlb.err")"
B_A="$(count "$WORK/ctlb.new" alg-value)"
B_D="$(count "$WORK/ctlb.new" digestset)"
B_U="$(count "$WORK/ctlb.new" unparseable)"
if [ "$B_A" -ne 1 ] || [ "$B_D" -ne 1 ] || [ "$B_U" -ne 0 ]; then
  broken "control B under content routing: alg-value=$B_A digestset=$B_D unparseable=$B_U, expected 1/1/0. The new routing does not read line-delimited content behind a .json name, which is the whole subject of this rule"
fi

sweep extension "$WORK/ctlb.list" "$WORK/ctlb.old" "$WORK/ctlb.err2" \
  || broken "the sweeper failed on control B under extension routing: $(head -3 "$WORK/ctlb.err2")"
BO_A="$(count "$WORK/ctlb.old" alg-value)"
BO_D="$(count "$WORK/ctlb.old" digestset)"
BO_U="$(count "$WORK/ctlb.old" unparseable)"
if [ "$BO_U" -ne 1 ] || [ "$BO_A" -ne 0 ] || [ "$BO_D" -ne 0 ]; then
  broken "control B under the OLD extension routing: unparseable=$BO_U alg-value=$BO_A digestset=$BO_D, expected 1/0/0. The rule this fixture replaced no longer fails where it must, so the subject of the repair has moved and nothing below certifies anything"
fi
note "control B (JSONL behind .json) -> content: $B_A/$B_D/unparseable=$B_U · old extension rule: unparseable=$BO_U. Seen failing in both directions"

# ---- CONTROL C: the fallback did not make the reader blind ------------------
printf '%s' '{"alg":' > "$WORK/ctl-truncated.json"
cat > "$WORK/ctl-conflict.json" <<'CTLC'
{"subject": [{"digest": {"sha256": "4444444444444444444444444444444444444444444444444444444444444444"}}]}
<<<<<<< HEAD
CTLC
: > "$WORK/ctl-empty.json"
printf 'ctlC\t%s\nctlC\t%s\nctlC\t%s\n' \
  "$WORK/ctl-truncated.json" "$WORK/ctl-conflict.json" "$WORK/ctl-empty.json" > "$WORK/ctlc.list"
sweep content "$WORK/ctlc.list" "$WORK/ctlc.findings" "$WORK/ctlc.err" \
  || broken "the sweeper failed on control C: $(head -3 "$WORK/ctlc.err")"
C_U="$(count "$WORK/ctlc.findings" unparseable)"
C_A="$(count "$WORK/ctlc.findings" alg-value)"
C_D="$(count "$WORK/ctlc.findings" digestset)"
if [ "$C_U" -ne 3 ] || [ "$C_A" -ne 0 ] || [ "$C_D" -ne 0 ]; then
  broken "control C: unparseable=$C_U alg-value=$C_A digestset=$C_D, expected 3/0/0. Malformed bytes are being read as a document, or a partially read file leaked findings: the fallback bought its green by going blind"
fi
note "control C (truncated, conflict-marked, empty) -> unparseable=$C_U, findings leaked=$((C_A + C_D))"

# ---- the live corpus --------------------------------------------------------
: > "$WORK/live.list"
SWEPT=""
UNSWEPT=""

add_repo() {  # $1 = label, $2 = repo root
  local label="$1" root="$2" n
  git -C "$root" ls-files -- '*.json' '*.jsonl' \
    | awk -v lbl="$label" -v root="$root" 'NF {printf "%s:%s\t%s/%s\n", lbl, $0, root, $0}' \
    >> "$WORK/live.list"
  n="$(git -C "$root" ls-files -- '*.json' '*.jsonl' | grep -c .)"
  SWEPT="$SWEPT $label($n)"
}

git -C "$PACK" rev-parse --git-dir >/dev/null 2>&1 || broken "$PACK is not a git repository; the sweep has no file list"
add_repo harness-pack "$PACK"

HW="${HARNESSWRIGHT_REPO:-$PACK/../harnesswright}"
if git -C "$HW" rev-parse --git-dir >/dev/null 2>&1; then
  add_repo harnesswright "$(cd "$HW" && pwd)"
else
  UNSWEPT="harnesswright"
fi

LIVE_N="$(grep -c . "$WORK/live.list")"
if [ "$LIVE_N" -eq 0 ]; then
  broken "the live file list is empty: a sweep that enumerated nothing has measured nothing, and its green would be an assertion about no corpus at all"
fi

sweep content "$WORK/live.list" "$WORK/live.findings" "$WORK/live.err" \
  || broken "the sweeper failed on the live corpus: $(head -3 "$WORK/live.err")"

ROUTED="$(awk '$1 == "routed" {print $2, $3, $4}' "$WORK/live.findings")"
if [ -z "$ROUTED" ]; then
  broken "the sweeper produced no routing summary, so it did not run to completion over the live list"
fi

UNPARSEABLE="$(awk '$1 == "unparseable"' "$WORK/live.findings")"
if [ -n "$UNPARSEABLE" ]; then
  broken "tracked files the sweep could not read, so its scope is not the declared one -- $(printf '%s' "$UNPARSEABLE" | tr '\n' ' ')"
fi

LIVE_A="$(count "$WORK/live.findings" alg-value)"
LIVE_D="$(count "$WORK/live.findings" digestset)"
LIVE_VERDICT="$(verdict "$WORK/live.findings")"

note "swept (tracked *.json, *.jsonl):$SWEPT -- files enumerated: $LIVE_N"
note "routed by content: $ROUTED"
if [ -n "$UNSWEPT" ]; then
  note "NOT swept: $UNSWEPT -- not resolvable from here, and optional (harness_stats.py:281). A shape"
  note "           held only there is a shape this run did not look at, and is not reported on below"
fi
note "negative control: the live corpus -> alg-value=$LIVE_A digestset=$LIVE_D"

if [ "$LIVE_VERDICT" = "RED" ]; then
  echo "RED [bypass_att_two_digest_shapes] the corpus emits BOTH digest conventions"
  awk '$1 == "alg-value" || $1 == "digestset"' "$WORK/live.findings" | sed 's/^/      | /'
  note "ADR-018 D3 supersedes harnesswright/ADR-0008 D5 :111 on the shape, so exactly one of these two"
  note "is the family's convention and the other one is a migration that was never declared"
  note "green when at most one shape is emitted"
  echo "att_two_digest_shapes BYPASS FIXTURE: RED"
  exit 1
fi

echo "GREEN [bypass_att_two_digest_shapes] at most one digest convention is emitted"
if [ "$LIVE_A" -eq 0 ] && [ "$LIVE_D" -eq 0 ]; then
  note "green by VACUITY, which is the correct initial state and not a defect: ADR-018 D3 --"
  note "'it is green today by vacuity -- zero artifacts of either shape -- and that vacuity is the"
  note "point: it must go RED the moment the second convention acquires its first artifact'"
  note "controls A, B and C above are what separate this from a detector that cannot see"
fi
echo "att_two_digest_shapes BYPASS FIXTURE: GREEN"
exit 0
