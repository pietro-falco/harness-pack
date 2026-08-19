#!/usr/bin/env bash
# graft_init.sh -- make a bare repository reachable by the apparatus with one
# command instead of four hand-assembled files (THR-INIT).
#
#   graft_init.sh --repo DIR --slice ID --title STR --task FILE \
#     --tools CSV --turns N --wall Nm|Nh --scope CSV \
#     --criterion 'id=shell command' [--criterion ...] \
#     --verifier-id URI [--tier T1|T2|T3]
#
# ADD MODE (THR-USE, closing THR-INIT ESITO 4 item 1): `--add` appends ONE
# slice to an already-grafted repo, touching nothing that exists -- the new
# spec is written, harness.json gains one slice entry, the new claims are
# appended after the existing ones; manifest.local.json and every other
# slice's spec stay byte-identical, so --verifier-id/--tier are refused here.
# Before writing, every existing slice's spec criteria are checked against
# the manifest's claim ids: a slice declaring a criterion absent from the
# manifest is a gate that measures nothing (the defect THR-INIT found in the
# THR-SWARM-1 hand-grafts), and --add refuses to extend such a repo, naming
# the slice and the missing ids. Reachability is proven for the added slice
# WHEN ITS TURN COMES: in a throwaway .harness copy with every other slice
# marked passed, `next --json` must answer kind=unlocked, id=<slice>,
# eligible_mode_b=true, or everything --add wrote is rolled back.
#
# Writes exactly four files in DIR -- .harness/harness.json,
# .harness/manifest.local.json, .harness/specs/ID.md, .verity/claims.json --
# then proves reachability by requiring `next --json` at DIR to answer
# kind=unlocked, id=ID, eligible_mode_b=true; on any other answer it rolls
# back everything it wrote. Division of knowledge (THR-INIT ESITO 1): what is
# invariant across grafts is emitted, never asked; what the repo can say
# (project name, constitution hash) is read, never asked; only what the
# operator alone knows is an argument. Criteria are written ONCE where they
# have readers (the spec and the claims manifest); the harness.json slice
# carries no criteria copy, and no verified_on/staleness field is emitted --
# nothing reads them (ESITO 1 findings 2-3). Fail-closed throughout: every
# input is validated before the first write, a missing piece is a one-line
# refusal, and a graft file that already exists is refused, never replaced --
# the THR-SWARM-1 hand-grafts replaced a 26-claim tracked manifest and
# silently broke every other slice's gate (ESITO 1 finding 1).
#
# Not written here, and printed as the operator's own line at the end: the
# launch environment (observation ledger, CLI paths). No tracked default
# names an operator location (ADR-004 D2).
#
# Exit codes: 0 grafted and reachable; 1 refusal (reason on stderr); 2 usage.
set -euo pipefail

usage() {
  echo "usage: graft_init.sh [--add] --repo DIR --slice ID --title STR --task FILE \
--tools CSV --turns N --wall Nm|Nh --scope CSV \
[--derive] --criterion 'id=shell command' [--criterion ...] \
--verifier-id URI [--tier T1|T2|T3]   (--verifier-id/--tier: fresh graft only; \
--derive: read criteria from the repo's own package.json quality scripts)" >&2
  exit 2
}
stop() { echo "STOP: $*" >&2; exit 1; }

REPO="" SLICE="" TITLE="" TASK="" TOOLS="" TURNS="" WALL="" SCOPE=""
VERIFIER_ID="" TIER="T2" TIER_SOURCE="default" ADD=0 DERIVE=0
CRITERIA=""
while [ $# -gt 0 ]; do
  case $1 in
    --add) ADD=1; shift ;;
    --derive) DERIVE=1; shift ;;
    --repo) REPO=${2:-}; shift 2 ;;
    --slice) SLICE=${2:-}; shift 2 ;;
    --title) TITLE=${2:-}; shift 2 ;;
    --task) TASK=${2:-}; shift 2 ;;
    --tools) TOOLS=${2:-}; shift 2 ;;
    --turns) TURNS=${2:-}; shift 2 ;;
    --wall) WALL=${2:-}; shift 2 ;;
    --scope) SCOPE=${2:-}; shift 2 ;;
    --criterion) CRITERIA="$CRITERIA${CRITERIA:+$'\n'}${2:-}"; shift 2 ;;
    --verifier-id) VERIFIER_ID=${2:-}; shift 2 ;;
    --tier) TIER=${2:-}; TIER_SOURCE="declared"; shift 2 ;;
    *) usage ;;
  esac
done

# Validation, all of it before the first write. One refusal, one line.
[ -n "$REPO" ] || stop "--repo missing: the target repository directory"
[ -d "$REPO" ] || stop "--repo is not a directory: $REPO"
TOP="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" \
  || stop "--repo is not inside a git repository: $REPO"
[ "$TOP" = "$(cd "$REPO" && pwd -P)" ] \
  || stop "--repo must be the git toplevel, which is: $TOP"
[ -n "$SLICE" ] || stop "--slice missing: the slice id"
printf '%s' "$SLICE" | grep -Eq '^[A-Za-z0-9_.-]+$' \
  || stop "--slice must be a single path segment [A-Za-z0-9_.-]: $SLICE"
[ -n "$TITLE" ] || stop "--title missing: one line naming the slice"
[ -n "$TASK" ] || stop "--task missing: the file carrying the task body"
[ -s "$TASK" ] || stop "--task file unreadable or empty: $TASK"
[ -n "$TOOLS" ] || stop "--tools missing: comma-separated tool bound (e.g. Read,Write)"
printf '%s' "$TOOLS" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*(,[A-Za-z_][A-Za-z0-9_]*)*$' \
  || stop "--tools must be a comma-separated list of tool names: $TOOLS"
printf '%s' "$TURNS" | grep -Eq '^[1-9][0-9]*$' \
  || stop "--turns missing or not a positive integer: ${TURNS:-<absent>}"
printf '%s' "$WALL" | grep -Eq '^[0-9]+(m|h)$' \
  || stop "--wall missing or not Nm/Nh: ${WALL:-<absent>}"
[ -n "$SCOPE" ] || stop "--scope missing: comma-separated repo-relative write prefixes"
OLDIFS=$IFS; IFS=','
for p in $SCOPE; do
  [ -n "$p" ] || stop "--scope has an empty entry"
  case $p in
    /*) stop "--scope entry must be repo-relative, got absolute: $p" ;;
    */) stop "--scope entry must not end with /: $p" ;;
    ..|../*|*/..|*/../*) stop "--scope entry must not traverse upwards: $p" ;;
  esac
done
IFS=$OLDIFS
# Derived criteria (THR-SEQ ESITO 3): what the repo can say is READ, never
# asked -- the same division of knowledge THR-INIT ESITO 1 fixed for project
# name and constitution hash. package.json's own quality scripts become
# criteria verbatim (test, typecheck, lint; a tsconfig.json without a
# typecheck script derives `npx tsc --noEmit`), each named for its source on
# stderr, id-prefixed with the slice so grafts and adds stay collision-free.
# A repo offering NONE of them is refused in one line: a project with no way
# to say it is well gets told so, never handed a fabricated criterion that
# would pass by construction. Derived lines compose with --criterion (the
# part only the operator knows) and flow through the same format validation,
# duplicate refusal and manifest checks as declared ones -- one path, no fork.
if [ "$DERIVE" -eq 1 ]; then
  DERIVED="$(REPO_TOP="$TOP" SLICE="$SLICE" python3 - <<'PY'
import json, os, sys
top, s = os.environ["REPO_TOP"], os.environ["SLICE"]
def die(msg):
    sys.stderr.write("STOP: " + msg + "\n"); sys.exit(1)
pj = os.path.join(top, "package.json")
if not os.path.isfile(pj):
    die("--derive: no package.json at %s -- the repo offers no way to say "
        "it is well (derivation is npm-shaped; declare --criterion yourself)"
        % top)
try:
    scripts = json.load(open(pj)).get("scripts") or {}
except ValueError as e:
    die("--derive: package.json unreadable as JSON: %s" % e)
derived = []
if "test" in scripts:
    derived.append(("%s-test" % s, "npm test", "scripts.test"))
if "typecheck" in scripts:
    derived.append(("%s-typecheck" % s, "npm run typecheck",
                    "scripts.typecheck"))
elif os.path.isfile(os.path.join(top, "tsconfig.json")):
    derived.append(("%s-typecheck" % s, "npx tsc --noEmit", "tsconfig.json"))
if "lint" in scripts:
    derived.append(("%s-lint" % s, "npm run lint", "scripts.lint"))
if not derived:
    die("--derive: package.json declares no test/typecheck/lint script and "
        "no tsconfig.json is present -- the repo offers no way to say it is "
        "well; declare --criterion yourself or give the project one")
for cid, cmd, srcname in derived:
    sys.stderr.write("DERIVED %s=%s (from %s)\n" % (cid, cmd, srcname))
    print("%s=%s" % (cid, cmd))
PY
)" || exit 1
  CRITERIA="$CRITERIA${CRITERIA:+$'\n'}$DERIVED"
fi
[ -n "$CRITERIA" ] || stop "--criterion missing: at least one 'id=shell command' pair (or --derive on a repo that offers criteria)"
while IFS= read -r c; do
  printf '%s' "$c" | grep -Eq '^[A-Za-z0-9_.-]+=.+$' \
    || stop "--criterion must be 'id=shell command', got: $c"
done <<EOF
$CRITERIA
EOF
if [ "$ADD" -eq 1 ]; then
  [ -z "$VERIFIER_ID" ] || stop "--verifier-id is not accepted with --add: manifest.local.json belongs to the existing graft and is not touched"
  [ "$TIER_SOURCE" = "default" ] || stop "--tier is not accepted with --add: manifest.local.json belongs to the existing graft and is not touched"
else
  [ -n "$VERIFIER_ID" ] || stop "--verifier-id missing: a URI under the operator's domain (never defaulted; templates/manifest.example.json says why)"
fi
case $TIER in T1|T2|T3) ;; *) stop "--tier must be T1, T2 or T3, got: $TIER" ;; esac

# harnesswright CLI, launcher's resolution order (env, PATH, STOP): needed
# below to prove reachability, so it is resolved before anything is written.
if [ -n "${HARNESSWRIGHT_CLI:-}" ]; then HW_CLI="$HARNESSWRIGHT_CLI"
elif command -v harnesswright >/dev/null 2>&1; then HW_CLI="$(command -v harnesswright)"
else stop "harnesswright CLI not resolvable; install harnesswright or set HARNESSWRIGHT_CLI"; fi
[ -f "$HW_CLI" ] || stop "harnesswright CLI not resolvable at $HW_CLI"
HARNESS_HOME="${HARNESS_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"

if [ "$ADD" -eq 1 ]; then
  # ---- ADD MODE: extend a COMPLETE graft, touch nothing that exists. ----
  F_HARNESS=".harness/harness.json"
  F_MANIFEST=".harness/manifest.local.json"
  F_CLAIMS=".verity/claims.json"
  F_SPEC=".harness/specs/$SLICE.md"
  for f in "$F_HARNESS" "$F_MANIFEST" "$F_CLAIMS"; do
    [ -e "$TOP/$f" ] || stop "$f absent in $TOP; --add extends complete grafts only (graft fresh, without --add, first)"
  done
  [ ! -e "$TOP/$F_SPEC" ] || stop "$F_SPEC already exists in $TOP; a slice is added once"

  # Saved bytes for rollback: exactly what --add may write, nothing else.
  ADD_BAK="$(mktemp -d "${TMPDIR:-/tmp}/graftadd.XXXXXX")"
  cp "$TOP/$F_HARNESS" "$ADD_BAK/harness.json.bak"
  cp "$TOP/$F_CLAIMS" "$ADD_BAK/claims.json.bak"
  rollback_add() {
    cp "$ADD_BAK/harness.json.bak" "$TOP/$F_HARNESS"
    cp "$ADD_BAK/claims.json.bak" "$TOP/$F_CLAIMS"
    rm -f "$TOP/$F_SPEC"
    rm -rf "$ADD_BAK"
    return 0
  }

  # Checks and writes in one pass, fail-closed: any refusal below leaves the
  # tree exactly as found (nothing is written before the last check passes).
  # The spec emission mirrors the fresh writer below line-for-line; a drift
  # that breaks the emitted form is caught by both fixtures' next-parse arms.
  REPO_TOP="$TOP" SLICE="$SLICE" TITLE="$TITLE" TASK_FILE="$TASK" TOOLS="$TOOLS" \
  TURNS="$TURNS" WALL="$WALL" SCOPE="$SCOPE" CRITERIA="$CRITERIA" \
  python3 - <<'PY' || { rollback_add; exit 1; }
import json, os, sys

top = os.environ["REPO_TOP"]; s = os.environ["SLICE"]
tools = os.environ["TOOLS"].split(",")
scope = os.environ["SCOPE"].split(",")
crits = [c.split("=", 1) for c in os.environ["CRITERIA"].splitlines()]

def die(msg):
    sys.stderr.write("STOP: " + msg + "\n"); sys.exit(1)

try:
    h = json.load(open(os.path.join(top, ".harness/harness.json")))
except Exception as e:
    die(f".harness/harness.json unreadable as JSON: {e}")
try:
    m = json.load(open(os.path.join(top, ".verity/claims.json")))
except Exception as e:
    die(f".verity/claims.json unreadable as JSON: {e}")

slices = h.get("slices")
if not isinstance(slices, dict) or not slices:
    die(".harness/harness.json carries no slices; nothing to add to")
if s in slices:
    die(f"slice {s} already exists in .harness/harness.json; a slice is added once")
claims = m.get("claims")
if not isinstance(claims, list):
    die(".verity/claims.json carries no claims list")
claim_ids = [c.get("id") for c in claims]

dup = [cid for cid, _ in crits if cid in claim_ids]
if dup:
    die("criterion id(s) already in .verity/claims.json: " + ",".join(dup)
        + " (duplicated criteria are refused, never merged)")
seen = set()
dup = [cid for cid, _ in crits if cid in seen or seen.add(cid)]
if dup:
    die("criterion id(s) repeated on the command line: " + ",".join(dup))

# THE DEFECT GATE (THR-INIT ESITO 1 finding 1): a slice declaring a criterion
# absent from the manifest is a gate that measures nothing. Refused, named.
def spec_criteria(path):
    lines = open(path).read().splitlines()
    if not lines or lines[0].strip() != "---":
        return []
    out, inblock = [], False
    for ln in lines[1:]:
        if ln.strip() == "---":
            break
        if ln == "criteria:":
            inblock = True
            continue
        if inblock:
            if ln.startswith("  - "):
                out.append(ln[4:].strip())
                continue
            inblock = False
    return out

def broken_slices(slice_ids, ids):
    out = []
    for sid in sorted(slice_ids):
        p = os.path.join(top, f".harness/specs/{sid}.md")
        if not os.path.exists(p):
            continue  # a spec-less slice declares nothing to break
        missing = [c for c in spec_criteria(p) if c not in ids]
        if missing:
            out.append((sid, missing))
    return out

broken = broken_slices(slices, claim_ids)
if broken:
    die("existing gate measures nothing: " + "; ".join(
        f"slice {sid} declares criteria absent from .verity/claims.json: {','.join(miss)}"
        for sid, miss in broken) + " -- repair the manifest before adding a slice")

# All checks passed: write. Spec emission mirrors the fresh writer.
fm = ["---", "type: chore", "mode: B", "status: accepted", "effort: low",
      "efficiency: []", "model: worker", "tools:"]
fm += [f"  - {t}" for t in tools]
fm += ["budget:", f"  turns: {os.environ['TURNS']}",
       f"  wall_clock: \"{os.environ['WALL']}\"",
       "stop_conditions:", "  - budget-exhaustion", "criteria:"]
fm += [f"  - {cid}" for cid, _ in crits]
fm += ["scope:"] + [f"  - {p}" for p in scope] + ["---", ""]
body = [f"# {s} — {os.environ['TITLE']}", "", "## ADW", "", "```mermaid",
        "flowchart LR",
        f"  spec[{s} spec] --> exec[worker executes the task]",
        "  exec --> gate[verity gate on the declared criteria]",
        "  gate --> close[launcher closes the run]",
        "```", "", open(os.environ["TASK_FILE"]).read().rstrip(), ""]
with open(os.path.join(top, f".harness/specs/{s}.md"), "w") as fh:
    fh.write("\n".join(fm + body))

h["slices"][s] = {"title": os.environ["TITLE"], "manifest": ".verity/claims.json"}
with open(os.path.join(top, ".harness/harness.json"), "w") as fh:
    fh.write(json.dumps(h, indent=2) + "\n")

m["claims"] = claims + [{"id": cid, "type": "command",
                         "description": f"criterion {cid} of slice {s}",
                         "run": cmd, "expect": {"exitCode": 0}} for cid, cmd in crits]
with open(os.path.join(top, ".verity/claims.json"), "w") as fh:
    fh.write(json.dumps(m, indent=2) + "\n")

# Self-check on the WRITTEN state, new slice included: the invariant holds on
# what is now on disk, not on what this process intended to put there.
h2 = json.load(open(os.path.join(top, ".harness/harness.json")))
m2 = json.load(open(os.path.join(top, ".verity/claims.json")))
ids2 = [c.get("id") for c in m2.get("claims", [])]
broken = broken_slices(h2.get("slices", {}), ids2)
if broken:
    die("self-check after write failed: " + "; ".join(
        f"slice {sid} -> {','.join(miss)}" for sid, miss in broken))
PY

  # Reachability WHEN ITS TURN COMES, not "looks right": in a throwaway
  # .harness copy with every other slice marked passed, next must resolve THIS
  # slice as unlocked and Mode-B-eligible, or everything written is rolled back.
  SIM="$ADD_BAK/sim"
  mkdir -p "$SIM/.harness/specs"
  REPO_TOP="$TOP" SLICE="$SLICE" SIM="$SIM" python3 - <<'PY' || { rollback_add; stop "reachability sim could not be built; rolled back"; }
import json, os
top, s, sim = os.environ["REPO_TOP"], os.environ["SLICE"], os.environ["SIM"]
h = json.load(open(os.path.join(top, ".harness/harness.json")))
for sid, sl in h["slices"].items():
    if sid != s:
        sl["status"] = "passed"
with open(os.path.join(sim, ".harness/harness.json"), "w") as fh:
    fh.write(json.dumps(h, indent=2) + "\n")
PY
  cp "$TOP/$F_SPEC" "$SIM/.harness/specs/$SLICE.md"
  NEXT_OUT="$(cd "$SIM" && node "$HW_CLI" next --json 2>&1)" \
    || { rollback_add; stop "next --json refused the added slice, rolled back: $NEXT_OUT"; }
  VERDICT="$(NEXT_JSON="$NEXT_OUT" SLICE="$SLICE" python3 -c '
import json, os
r = json.loads(os.environ["NEXT_JSON"])
k, i, e = r.get("kind"), r.get("id"), r.get("eligible_mode_b")
ok = k == "unlocked" and i == os.environ["SLICE"] and e is True
print("OK" if ok else "kind=%s id=%s eligible_mode_b=%s" % (k, i, e))')"
  [ "$VERDICT" = "OK" ] || { rollback_add; stop "added slice is not reachable when its turn comes ($VERDICT), rolled back"; }
  rm -rf "$ADD_BAK"

  PROJECT="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("project",""))' "$TOP/$F_HARNESS")"
  VERITY_HINT="${VERITY_CLI:-$(command -v verity 2>/dev/null || echo '<set VERITY_CLI>')}"
  echo "GRAFTED-ADD project=$PROJECT slice=$SLICE"
  echo "  wrote: $F_SPEC; extended: $F_HARNESS $F_CLAIMS; untouched: $F_MANIFEST"
  echo "launch (when its turn comes):"
  echo "  cd $TOP && \\"
  echo "  CONFORMANCE_LEDGER_REPO=<your-observation-ledger> \\"
  echo "  HARNESS_MANIFEST=$TOP/$F_MANIFEST \\"
  echo "  HARNESSWRIGHT_CLI=$HW_CLI VERITY_CLI=$VERITY_HINT \\"
  echo "  HARNESS_HOME=$HARNESS_HOME \\"
  echo "  bash $HARNESS_HOME/scripts/launch_worker.sh $F_SPEC"
  exit 0
fi

# Read from disk, never asked: project name and constitution hash.
CONST="$HARNESS_HOME/CONSTITUTION.md"
[ -r "$CONST" ] || stop "constitution not readable at $CONST (set HARNESS_HOME to the pack root)"
CONST_SHA="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$CONST")"
PROJECT="$(basename "$TOP")"

# A graft file that already exists is a refusal, never a replacement.
F_HARNESS=".harness/harness.json"
F_MANIFEST=".harness/manifest.local.json"
F_SPEC=".harness/specs/$SLICE.md"
F_CLAIMS=".verity/claims.json"
for f in "$F_HARNESS" "$F_MANIFEST" "$F_SPEC" "$F_CLAIMS"; do
  [ ! -e "$TOP/$f" ] || stop "$f already exists in $TOP; this command grafts fresh repos only and never merges (add-a-slice is out of scope, see docs)"
done

MADE_HARNESS=0 MADE_SPECS=0 MADE_VERITY=0
[ -d "$TOP/.harness" ] || { mkdir "$TOP/.harness"; MADE_HARNESS=1; }
[ -d "$TOP/.harness/specs" ] || { mkdir "$TOP/.harness/specs"; MADE_SPECS=1; }
[ -d "$TOP/.verity" ] || { mkdir "$TOP/.verity"; MADE_VERITY=1; }
rollback() {
  rm -f "$TOP/$F_HARNESS" "$TOP/$F_MANIFEST" "$TOP/$F_SPEC" "$TOP/$F_CLAIMS"
  [ "$MADE_SPECS" -eq 0 ] || rmdir "$TOP/.harness/specs" 2>/dev/null || true
  [ "$MADE_HARNESS" -eq 0 ] || rmdir "$TOP/.harness" 2>/dev/null || true
  [ "$MADE_VERITY" -eq 0 ] || rmdir "$TOP/.verity" 2>/dev/null || true
  return 0
}

REPO_TOP="$TOP" SLICE="$SLICE" TITLE="$TITLE" TASK_FILE="$TASK" TOOLS="$TOOLS" \
TURNS="$TURNS" WALL="$WALL" SCOPE="$SCOPE" CRITERIA="$CRITERIA" \
VERIFIER_ID="$VERIFIER_ID" TIER="$TIER" PROJECT="$PROJECT" CONST_SHA="$CONST_SHA" \
python3 - <<'PY' || { rollback; stop "internal writer failed; rolled back"; }
import json, os
top = os.environ["REPO_TOP"]; s = os.environ["SLICE"]
tools = os.environ["TOOLS"].split(",")
scope = os.environ["SCOPE"].split(",")
crits = [c.split("=", 1) for c in os.environ["CRITERIA"].splitlines()]

def w(rel, text):
    with open(os.path.join(top, rel), "w") as fh:
        fh.write(text)

w(".harness/harness.json", json.dumps({
    "version": "0.1", "project": os.environ["PROJECT"], "workstreamCap": 1,
    "slices": {s: {"title": os.environ["TITLE"], "manifest": ".verity/claims.json"}},
}, indent=2) + "\n")

w(".harness/manifest.local.json", json.dumps({
    "manifest_version": 1,
    "constitution_hash_expected": os.environ["CONST_SHA"],
    "verifier_id": os.environ["VERIFIER_ID"],
    "model_tiers": {"worker": os.environ["TIER"]},
    "tiers": {
        "T1": {"name": "trust-anchor", "chain": ["claude-opus-5"]},
        "T2": {"name": "execution", "chain": ["claude-sonnet-5"]},
        "T3": {"name": "subagent", "chain": ["claude-haiku-4-5-20251001"]},
    },
}, indent=2) + "\n")

fm = ["---", "type: chore", "mode: B", "status: accepted", "effort: low",
      "efficiency: []", "model: worker", "tools:"]
fm += [f"  - {t}" for t in tools]
fm += ["budget:", f"  turns: {os.environ['TURNS']}",
       f"  wall_clock: \"{os.environ['WALL']}\"",
       "stop_conditions:", "  - budget-exhaustion", "criteria:"]
fm += [f"  - {cid}" for cid, _ in crits]
fm += ["scope:"] + [f"  - {p}" for p in scope] + ["---", ""]
body = [f"# {s} — {os.environ['TITLE']}", "", "## ADW", "", "```mermaid",
        "flowchart LR",
        f"  spec[{s} spec] --> exec[worker executes the task]",
        "  exec --> gate[verity gate on the declared criteria]",
        "  gate --> close[launcher closes the run]",
        "```", "", open(os.environ["TASK_FILE"]).read().rstrip(), ""]
w(f".harness/specs/{s}.md", "\n".join(fm + body))

w(".verity/claims.json", json.dumps({
    "version": "0.1",
    "claims": [{"id": cid, "type": "command",
                "description": f"criterion {cid} of slice {s}",
                "run": cmd, "expect": {"exitCode": 0}} for cid, cmd in crits],
}, indent=2) + "\n")
PY

# Reachability, not "looks right": next must resolve THIS slice as unlocked
# and Mode-B-eligible, or everything written above is rolled back.
NEXT_OUT="$(cd "$TOP" && node "$HW_CLI" next --json 2>&1)" \
  || { rollback; stop "next --json refused the graft, rolled back: $NEXT_OUT"; }
VERDICT="$(NEXT_JSON="$NEXT_OUT" SLICE="$SLICE" python3 -c '
import json, os
r = json.loads(os.environ["NEXT_JSON"])
k, i, e = r.get("kind"), r.get("id"), r.get("eligible_mode_b")
ok = k == "unlocked" and i == os.environ["SLICE"] and e is True
print("OK" if ok else "kind=%s id=%s eligible_mode_b=%s" % (k, i, e))')"
[ "$VERDICT" = "OK" ] || { rollback; stop "grafted config is not reachable ($VERDICT), rolled back"; }

# The operator's own line: launch environment is theirs to point (ADR-004 D2).
VERITY_HINT="${VERITY_CLI:-$(command -v verity 2>/dev/null || echo '<set VERITY_CLI>')}"
echo "GRAFTED project=$PROJECT slice=$SLICE tier=$TIER($TIER_SOURCE) constitution=$CONST_SHA"
echo "  wrote: $F_HARNESS $F_MANIFEST $F_SPEC $F_CLAIMS"
echo "launch:"
echo "  cd $TOP && \\"
echo "  CONFORMANCE_LEDGER_REPO=<your-observation-ledger> \\"
echo "  HARNESS_MANIFEST=$TOP/$F_MANIFEST \\"
echo "  HARNESSWRIGHT_CLI=$HW_CLI VERITY_CLI=$VERITY_HINT \\"
echo "  HARNESS_HOME=$HARNESS_HOME \\"
echo "  bash $HARNESS_HOME/scripts/launch_worker.sh $F_SPEC"
