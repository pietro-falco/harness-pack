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
# the sweep reads tracked `*.json` and `*.jsonl` only. The ADRs that quote both
# shapes -- this repository's own ADR-018 among them -- are `.md` and are never
# read. That is why ADR-018's Context could record a sweep for `"alg"` returning
# "one hit, the ADR sentence itself" while this fixture returns zero: it sweeps
# a different thing, on purpose.
#
# THE NEW/EXISTING DISTINCTION IS NOT LOAD-BEARING HERE, YET. D3's failure needs
# BOTH shapes present, and at this basis the corpus holds ZERO of either, so no
# artifact is close enough to the line for its age to matter. When one is, it is
# bypass_att_alg_unpinned that carries the new-versus-exempt discrimination;
# this row carries the count of conventions.
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
# cannot parse is reported as "unparseable <label> <reason>" so the caller can
# refuse to certify a scope it did not actually cover.
cat > "$WORK/sweep.py" <<'SWEEPER'
import json, sys

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

findings = []
for row in open(sys.argv[1], encoding="utf-8"):
    row = row.rstrip("\n")
    if not row:
        continue
    label, path = row.split("\t", 1)
    try:
        if path.endswith(".jsonl"):
            with open(path, "rb") as f:
                for i, raw in enumerate(f, 1):
                    stripped = raw.rstrip(b"\n")
                    if stripped:
                        walk(json.loads(stripped), "$L%d" % i, label, findings)
        else:
            with open(path, "rb") as f:
                walk(json.load(f), "$", label, findings)
    except Exception as exc:
        print("unparseable %s %s" % (label, type(exc).__name__))

for shape, label, path in findings:
    print("%s %s %s" % (shape, label, path))
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

echo "== bypass_att_two_digest_shapes: one digest convention, not two (ADR-018 D3) =="

# ---- positive control: the sweep can see both shapes, and the verdict can fail
cat > "$WORK/ctl-alg.json" <<'CTLA'
{"artifact": {"name": "control", "digest": {"alg": "sha256", "value": "0000000000000000000000000000000000000000000000000000000000000000"}}}
CTLA
cat > "$WORK/ctl-ds.json" <<'CTLD'
{"subject": [{"name": "control", "digest": {"sha256": "1111111111111111111111111111111111111111111111111111111111111111"}}]}
CTLD
printf 'control\t%s\ncontrol\t%s\n' "$WORK/ctl-alg.json" "$WORK/ctl-ds.json" > "$WORK/ctl.list"
python3 "$WORK/sweep.py" "$WORK/ctl.list" > "$WORK/ctl.findings" 2>"$WORK/ctl.err" \
  || broken "the sweeper failed on the control corpus: $(head -3 "$WORK/ctl.err")"
CTL_A="$(awk '$1 == "alg-value"' "$WORK/ctl.findings" | grep -c .)"
CTL_D="$(awk '$1 == "digestset"' "$WORK/ctl.findings" | grep -c .)"
CTL_VERDICT="$(verdict "$WORK/ctl.findings")"
if [ "$CTL_A" -ne 1 ] || [ "$CTL_D" -ne 1 ] || [ "$CTL_VERDICT" != "RED" ]; then
  broken "positive control: alg-value=$CTL_A digestset=$CTL_D verdict=$CTL_VERDICT, expected 1/1/RED. A green below would mean nothing"
fi
note "positive control: a fabricated corpus carrying both shapes -> alg-value=$CTL_A digestset=$CTL_D, verdict=$CTL_VERDICT"

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

python3 "$WORK/sweep.py" "$WORK/live.list" > "$WORK/live.findings" 2>"$WORK/live.err" \
  || broken "the sweeper failed on the live corpus: $(head -3 "$WORK/live.err")"

UNPARSEABLE="$(awk '$1 == "unparseable"' "$WORK/live.findings")"
if [ -n "$UNPARSEABLE" ]; then
  broken "tracked files the sweep could not read, so its scope is not the declared one -- $(printf '%s' "$UNPARSEABLE" | tr '\n' ' ')"
fi

LIVE_A="$(awk '$1 == "alg-value"' "$WORK/live.findings" | grep -c .)"
LIVE_D="$(awk '$1 == "digestset"' "$WORK/live.findings" | grep -c .)"
LIVE_VERDICT="$(verdict "$WORK/live.findings")"

note "swept (tracked *.json, *.jsonl):$SWEPT"
if [ -n "$UNSWEPT" ]; then
  note "NOT swept: $UNSWEPT -- not resolvable from here, and optional (harness_stats.py:281). A shape"
  note "           held only there is a shape this run did not look at, and is not reported on below"
fi
note "negative control: the live corpus -> alg-value=$LIVE_A digestset=$LIVE_D"

if [ "$LIVE_VERDICT" = "RED" ]; then
  echo "RED [bypass_att_two_digest_shapes] the corpus emits BOTH digest conventions"
  printf '%s\n' "$(awk '$1 != "unparseable"' "$WORK/live.findings")" | sed 's/^/      | /'
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
  note "the positive control above is what separates this from a detector that cannot see"
fi
echo "att_two_digest_shapes BYPASS FIXTURE: GREEN"
exit 0
