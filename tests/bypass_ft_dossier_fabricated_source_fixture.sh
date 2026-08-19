#!/usr/bin/env bash
# DOSSIER-2 -- a dossier with a fabricated source must fail (THR-DOSSIER
# ESITO 3), and the dossier's author must not be able to write his own
# evidence (THR-METALS ESITI 2-3). No criterion can say a dossier is GOOD;
# what is checkable is that its sources exist as captured evidence, that
# they say what the document attributes to them, that the coverage
# declared BEFORE writing is met, that every quoted support line comes
# from the CHILDREN'S captured candidate set (an input the author cannot
# write, ADR-025), that a source's class (filed/agency/company/other) is
# corroborated and the primary floor met, that company-only claims are
# marked in the reader's own line, that dated figures carry the date they
# REFER to, and that every figure in the document lives inside a verified
# quote. Before the THR-METALS subject existed, an author-invented pair
# PASSED (fixture-seen-passing.txt in that run): that is this fixture's
# "seen passing" state for arm 7, and the fixture is RED against the
# pre-METALS checker by construction. Since THR-SPEC: a declared child
# procedure must be evidenced as LOADED (C13 acks; e2-seen-passing.txt in
# that run shows the pre-SPEC gate had no place to declare one), and the
# primary floor counts DISTINCT ENTI, never pages (e4-seen-passing.txt in
# that run shows the shipped dossier's four same-ente pages satisfying a
# floor of four).
# Subject: scripts/dossier_check.py --doc D.md --sources sources.json
#          --coverage COVERAGE.json --candidates candidates.json
#          [--procedure PROC.md]
#          (snapshots resolve beside sources.json; no network I/O).
# Fifteen arms:
#   1 fabricated source: document cites [S2], manifest names a snapshot
#     that does not exist -> FAIL naming S2
#   2 misattribution: snapshot exists but the support quote is nowhere in
#     it -> FAIL naming S2
#   3 positive control: citations resolve, hashes match, quotes present
#     and candidate-backed, classes corroborated, floor met, figure dated,
#     document numbers quoted, coverage met -> PASS, counts > 0, exit 0
#   4 trivially-empty: one cited claim against a coverage declaration that
#     requires more -> FAIL naming the coverage shortfall (C5/C6)
#   5 empty-for-the-wrong-reason: no snapshot verified at all ->
#     snapshots_verified=0 named, FAIL, never a pass
#   6 tamper: one snapshot byte flipped after the manifest hashed it ->
#     FAIL naming the hash mismatch (C2)
#   7 author-invented pair [THE THR-METALS CLASS]: the quote IS a verbatim
#     snapshot substring but is NOT in the captured candidate set -> FAIL
#     naming C8 and the source (the pre-METALS checker PASSED this)
#   8 class laundering: a company-hosted source declared "filed" -> FAIL
#     C9, not corroborated by host
#   9 primary floor: fewer corroborated filed/agency cited sources than
#     the declared minimum -> FAIL C9 naming the minimum
#  10 company-only marking: a claim whose every supporting source is
#     company class, unmarked -> FAIL C10; the SAME claim carrying
#     [company-sourced] in the reader's line -> PASS (both sides run)
#  11 undated figure: a support pair whose quote carries a digit but no
#     valid as_of (the date the figure refers to) -> FAIL C11
#  12 number outside evidence [the PsiQuantum class]: a figure in the
#     document that appears in no verified quote (a mangled extraction or
#     a typo) -> FAIL C12 naming the figure
#  13 candidates absent: no captured candidate set -> exit 2 UNMEASURED,
#     never a silent pass
#  14 procedure not actually loaded [THE THR-SPEC E2 CLASS]: a declared
#     child procedure whose ack set is empty (a), whose ack digest is
#     wrong (b), or whose candidates block exists while the gate is
#     invoked without --procedure (c) -> FAIL C13 by name each way; the
#     correct ack (d) -> PASS. Work must not proceed as if loading
#     succeeded when it did not.
#  15 primary floor counts pages, not enti [THE THR-SPEC E4 CLASS]: two
#     corroborated primary pages on ONE ente against a declared minimum
#     of two -> FAIL C9 naming distinct enti (the pre-SPEC checker
#     counted pages and passed this)
# GREEN: all fifteen arms hold. RED: any arm fails, including the subject
# being absent or pre-METALS (nothing then refuses the author-invented
# pair) or pre-SPEC (nothing then demands the loaded-procedure ack, and
# pages still satisfy the ente floor). UNMEASURED (2): python3 absent.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/scripts/dossier_check.py"
command -v python3 >/dev/null || { echo "UNMEASURED: python3 absent" >&2; exit 2; }
[ -f "$CHECK" ] || {
  echo "RED: scripts/dossier_check.py absent -- nothing on disk refuses a dossier with a fabricated reference (the seen-passing state)" >&2
  exit 1
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dossck.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

run_check() { # dir [extra args...] -> stdout+stderr; exit code is the check's
  ( d="$1"; shift; cd "$d" && python3 "$CHECK" --doc DOC.md --sources sources.json --coverage COVERAGE.json --candidates candidates.json "$@" 2>&1 )
}

# A two-section, two-source dossier where everything is genuine: both
# sources agency-class, each on ITS OWN declared primary host (two enti --
# the C9 floor counts distinct enti since THR-SPEC), the one dated figure
# carries as_of, the one document digit lives inside a verified quote, and
# every support quote is a member of the captured candidate set. Arms
# mutate copies of it.
mkbase() { # dir
  mkdir -p "$1/sources"
  cat > "$1/DOC.md" <<'EOF'
# Tiny dossier

## Alpha

Water boils at one hundred degrees Celsius at sea level [S1].
The snapshot's own figure for the boiling point is 100 degrees [S1].

## Beta

The sky's daytime color is explained by Rayleigh scattering [S2].
EOF
  cat > "$1/sources/S1.md" <<'EOF'
url: https://example.invalid/physics
fetched_at: 2026-08-16T19:00:00Z

At standard atmospheric pressure, water boils at 100 degrees Celsius.
EOF
  cat > "$1/sources/S2.md" <<'EOF'
url: https://example-two.invalid/atmosphere
fetched_at: 2026-08-16T19:00:00Z

Rayleigh scattering of sunlight explains the blue color of the daytime sky.
EOF
  python3 - "$1" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]
def h(p): return hashlib.sha256(open(os.path.join(d, p), "rb").read()).hexdigest()
manifest = {"sources": [
  {"id": "S1", "url": "https://example.invalid/physics", "title": "physics",
   "class": "agency", "snapshot": "sources/S1.md", "sha256": h("sources/S1.md"),
   "support": [{"for": "Water boils at one hundred degrees Celsius at sea level [S1].",
                "quote": "water boils at 100 degrees Celsius", "as_of": "2026"}]},
  {"id": "S2", "url": "https://example-two.invalid/atmosphere", "title": "atmosphere",
   "class": "agency", "snapshot": "sources/S2.md", "sha256": h("sources/S2.md"),
   "support": [{"for": "The sky's daytime color is explained by Rayleigh scattering [S2].",
                "quote": "Rayleigh scattering of sunlight explains the blue color"}]},
]}
json.dump(manifest, open(os.path.join(d, "sources.json"), "w"), indent=1)
coverage = {"sections": [{"heading": "## Alpha", "min_citations": 1},
                         {"heading": "## Beta", "min_citations": 1}],
            "min_distinct_sources": 2, "min_support_pairs": 2,
            "min_primary_sources": 2,
            "primary_host_suffixes": ["example.invalid", "example-two.invalid"]}
json.dump(coverage, open(os.path.join(d, "COVERAGE.json"), "w"), indent=1)
candidates = {"sources": {
  "S1": ["water boils at 100 degrees Celsius"],
  "S2": ["Rayleigh scattering of sunlight explains the blue color"]}}
json.dump(candidates, open(os.path.join(d, "candidates.json"), "w"), indent=1)
PY
}

# Arm 1 -- the fabricated reference: [S2]'s snapshot does not exist.
A1="$WORK/a1"; mkbase "$A1"; rm -f "$A1/sources/S2.md"
out="$(run_check "$A1")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm1]: a fabricated source (snapshot absent) PASSED -- the class this gate exists for: $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "S2" \
  || { echo "RED [arm1]: the refusal does not name the fabricated source S2: $out" >&2; exit 1; }
echo "ok [arm1: fabricated source refused by name]"

# Arm 2 -- the source exists but does not say it: quote nowhere in snapshot.
A2="$WORK/a2"; mkbase "$A2"
printf 'url: x\n\nEntirely other text about nothing relevant.\n' > "$A2/sources/S2.md"
python3 - "$A2" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]
m = json.load(open(os.path.join(d, "sources.json")))
m["sources"][1]["sha256"] = hashlib.sha256(open(os.path.join(d, "sources/S2.md"), "rb").read()).hexdigest()
json.dump(m, open(os.path.join(d, "sources.json"), "w"), indent=1)
PY
out="$(run_check "$A2")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm2]: a source that does not say what the document attributes to it PASSED: $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "S2" \
  || { echo "RED [arm2]: the misattribution refusal does not name S2: $out" >&2; exit 1; }
echo "ok [arm2: misattribution refused by name]"

# Arm 3 -- positive control: the genuine dossier passes with counts.
A3="$WORK/a3"; mkbase "$A3"
out="$(run_check "$A3")"; rc=$?
if [ "$rc" -ne 0 ]; then
  echo "RED [arm3]: a genuine dossier was refused (exit $rc): $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "snapshots_verified=2" \
  || { echo "RED [arm3]: PASS does not state its counts: $out" >&2; exit 1; }
echo "ok [arm3: genuine dossier passes, counts stated]"

# Arm 4 -- trivially empty: one cited claim, coverage demands more; the
# refusal must be the coverage class, not a source class.
A4="$WORK/a4"; mkbase "$A4"
cat > "$A4/DOC.md" <<'EOF'
# Tiny dossier

## Alpha

Water boils at one hundred degrees Celsius at sea level [S1].

## Beta

Some uncited prose.
EOF
python3 - "$A4" <<'PY'
import json, os, sys
d = sys.argv[1]
m = json.load(open(os.path.join(d, "sources.json")))
m["sources"] = m["sources"][:1]
json.dump(m, open(os.path.join(d, "sources.json"), "w"), indent=1)
PY
out="$(run_check "$A4")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm4]: a one-claim document passed a coverage declaration requiring more: $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -Eq "C5|C6" \
  || { echo "RED [arm4]: the thinness refusal is not named as coverage (C5/C6): $out" >&2; exit 1; }
echo "ok [arm4: trivially-empty refused as a coverage shortfall]"

# Arm 5 -- empty for the wrong reason: nothing verified may never pass.
A5="$WORK/a5"; mkbase "$A5"; rm -rf "$A5/sources"
out="$(run_check "$A5")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm5]: zero verified snapshots and the check still passed (the no-network masquerade): $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "snapshots_verified=0" \
  || { echo "RED [arm5]: the zero is not stated honestly: $out" >&2; exit 1; }
echo "ok [arm5: zero verified snapshots is a named fail, never a pass]"

# Arm 6 -- tamper: a byte flipped after the manifest hashed it.
A6="$WORK/a6"; mkbase "$A6"
printf 'x' >> "$A6/sources/S1.md"
out="$(run_check "$A6")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm6]: a tampered snapshot passed the hash pin: $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "C2" \
  || { echo "RED [arm6]: the tamper refusal is not named as integrity (C2): $out" >&2; exit 1; }
echo "ok [arm6: tampered snapshot refused as C2]"

# Arm 7 -- the author-invented pair (THR-METALS ESITO 2, ADR-025's form):
# the quote is a VERBATIM snapshot substring -- the pre-METALS checker
# passed it (fixture-seen-passing.txt) -- but it is not in the captured
# candidate set, so the author, not a child, chose it. Must be refused as
# C8 naming the source.
A7="$WORK/a7"; mkbase "$A7"
cat >> "$A7/DOC.md" <<'EOF'
The snapshot also states the pressure condition in its own words [S1].
EOF
python3 - "$A7" <<'PY'
import json, os, sys
d = sys.argv[1]
m = json.load(open(os.path.join(d, "sources.json")))
m["sources"][0]["support"].append(
  {"for": "The snapshot also states the pressure condition in its own words [S1].",
   "quote": "At standard atmospheric pressure"})
json.dump(m, open(os.path.join(d, "sources.json"), "w"), indent=1)
PY
out="$(run_check "$A7")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm7]: an author-invented support pair (verbatim in the snapshot, absent from the candidate set) PASSED -- the author wrote his own evidence: $out" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -q "C8" || ! printf '%s\n' "$out" | grep -q "S1"; then
  echo "RED [arm7]: the refusal is not named C8 against S1: $out" >&2; exit 1
fi
echo "ok [arm7: author-invented pair refused as C8 -- the author cannot write the citation]"

# Arm 8 -- class laundering: a company-hosted URL declared "filed" must be
# refused by host corroboration, not taken on trust.
A8="$WORK/a8"; mkbase "$A8"
python3 - "$A8" <<'PY'
import json, os, sys
d = sys.argv[1]
m = json.load(open(os.path.join(d, "sources.json")))
m["sources"][1]["class"] = "filed"
m["sources"][1]["url"] = "https://investor.acme-corp.example/press/uranium.html"
json.dump(m, open(os.path.join(d, "sources.json"), "w"), indent=1)
c = json.load(open(os.path.join(d, "COVERAGE.json")))
c["min_primary_sources"] = 1
json.dump(c, open(os.path.join(d, "COVERAGE.json"), "w"), indent=1)
PY
out="$(run_check "$A8")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm8]: a company-hosted source declared 'filed' PASSED -- class laundering: $out" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -q "C9" || ! printf '%s\n' "$out" | grep -qi "not corroborated"; then
  echo "RED [arm8]: the laundering refusal is not named C9/not-corroborated: $out" >&2; exit 1
fi
echo "ok [arm8: class laundering refused -- the host must corroborate the class]"

# Arm 9 -- primary floor: with S2 honestly company (and marked), only one
# corroborated primary source remains against a declared minimum of two.
A9="$WORK/a9"; mkbase "$A9"
python3 - "$A9" <<'PY'
import json, os, sys
d = sys.argv[1]
m = json.load(open(os.path.join(d, "sources.json")))
m["sources"][1]["class"] = "company"
m["sources"][1]["support"][0]["for"] = "The sky's daytime color is explained by Rayleigh scattering [company-sourced] [S2]."
json.dump(m, open(os.path.join(d, "sources.json"), "w"), indent=1)
doc = open(os.path.join(d, "DOC.md")).read().replace(
  "The sky's daytime color is explained by Rayleigh scattering [S2].",
  "The sky's daytime color is explained by Rayleigh scattering [company-sourced] [S2].")
open(os.path.join(d, "DOC.md"), "w").write(doc)
PY
out="$(run_check "$A9")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm9]: one primary source passed a declared minimum of two: $out" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -q "C9" || ! printf '%s\n' "$out" | grep -qi "minimum"; then
  echo "RED [arm9]: the floor refusal is not named C9/minimum: $out" >&2; exit 1
fi
echo "ok [arm9: primary floor enforced against the declaration]"

# Arm 10 -- company-only marking, both sides: the unmarked claim is
# refused; the SAME claim carrying [company-sourced] in the reader's line
# passes.
A10="$WORK/a10"; mkbase "$A10"
python3 - "$A10" <<'PY'
import json, os, sys
d = sys.argv[1]
m = json.load(open(os.path.join(d, "sources.json")))
m["sources"][1]["class"] = "company"
json.dump(m, open(os.path.join(d, "sources.json"), "w"), indent=1)
c = json.load(open(os.path.join(d, "COVERAGE.json")))
c["min_primary_sources"] = 1
json.dump(c, open(os.path.join(d, "COVERAGE.json"), "w"), indent=1)
PY
out="$(run_check "$A10")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm10a]: a claim supported ONLY by company material passed unmarked: $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "C10" \
  || { echo "RED [arm10a]: the unmarked company-only claim is not refused as C10: $out" >&2; exit 1; }
python3 - "$A10" <<'PY'
import json, os, sys
d = sys.argv[1]
m = json.load(open(os.path.join(d, "sources.json")))
m["sources"][1]["support"][0]["for"] = "The sky's daytime color is explained by Rayleigh scattering [company-sourced] [S2]."
json.dump(m, open(os.path.join(d, "sources.json"), "w"), indent=1)
doc = open(os.path.join(d, "DOC.md")).read().replace(
  "The sky's daytime color is explained by Rayleigh scattering [S2].",
  "The sky's daytime color is explained by Rayleigh scattering [company-sourced] [S2].")
open(os.path.join(d, "DOC.md"), "w").write(doc)
PY
out="$(run_check "$A10")"; rc=$?
if [ "$rc" -ne 0 ]; then
  echo "RED [arm10b]: the marked company-only claim was refused (exit $rc): $out" >&2
  exit 1
fi
echo "ok [arm10: company-only claim refused unmarked, accepted marked]"

# Arm 11 -- undated figure: the quote carries a digit, the pair carries no
# as_of (the date the figure refers to; the fetch date lives elsewhere).
A11="$WORK/a11"; mkbase "$A11"
python3 - "$A11" <<'PY'
import json, os, sys
d = sys.argv[1]
m = json.load(open(os.path.join(d, "sources.json")))
del m["sources"][0]["support"][0]["as_of"]
json.dump(m, open(os.path.join(d, "sources.json"), "w"), indent=1)
PY
out="$(run_check "$A11")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm11]: a dated figure without as_of PASSED: $out" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -q "C11" || ! printf '%s\n' "$out" | grep -q "S1"; then
  echo "RED [arm11]: the undated figure is not refused as C11 naming S1: $out" >&2; exit 1
fi
echo "ok [arm11: a figure must carry the date it refers to]"

# Arm 12 -- the PsiQuantum class: a figure in the document that no
# verified quote carries (a mangled extraction, a typo'd year, a rounded
# number). In finance a mangled figure is worse than an absent one.
A12="$WORK/a12"; mkbase "$A12"
python3 - "$A12" <<'PY'
import os, sys
d = sys.argv[1]
doc = open(os.path.join(d, "DOC.md")).read().replace(
  "The snapshot's own figure for the boiling point is 100 degrees [S1].",
  "The snapshot's own figure for the boiling point is 212 degrees [S1].")
open(os.path.join(d, "DOC.md"), "w").write(doc)
PY
out="$(run_check "$A12")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm12]: a document figure absent from every verified quote PASSED: $out" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -q "C12" || ! printf '%s\n' "$out" | grep -q "212"; then
  echo "RED [arm12]: the unquoted figure is not refused as C12 naming 212: $out" >&2; exit 1
fi
echo "ok [arm12: a figure the evidence does not carry cannot enter the document]"

# Arm 13 -- candidates absent: no captured candidate set is UNMEASURED,
# never a silent pass (the pre-METALS state must not be reachable by
# omission).
A13="$WORK/a13"; mkbase "$A13"; rm -f "$A13/candidates.json"
out="$(run_check "$A13")"; rc=$?
if [ "$rc" -ne 2 ]; then
  echo "RED [arm13]: a run without a candidate set exited $rc, want 2 UNMEASURED (0 would be the pre-METALS defect reachable by omission): $out" >&2
  exit 1
fi
echo "ok [arm13: no candidate set is UNMEASURED, never a pass]"

# Arm 14 -- procedure not actually loaded (THR-SPEC ESITO 2): a declared
# child procedure is evidence-bound by C13 -- the ack in candidates.json
# must equal the procedure file's own sha256, computable only by reading
# it. (a) empty ack set, (b) wrong digest, (c) candidates block present
# but the gate invoked without --procedure: each refused by name. (d) the
# correct ack passes. The pre-SPEC checker had no --procedure at all
# (e2-seen-passing.txt in the THR-SPEC run).
A14="$WORK/a14"; mkbase "$A14"
printf '# tiny child procedure\nreport format: as instructed.\n' > "$A14/procedure.md"
python3 - "$A14" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]
h = hashlib.sha256(open(os.path.join(d, "procedure.md"), "rb").read()).hexdigest()
c = json.load(open(os.path.join(d, "candidates.json")))
c["procedure"] = {"sha256": h, "acks": {}}
json.dump(c, open(os.path.join(d, "candidates.json"), "w"), indent=1)
PY
out="$(run_check "$A14" --procedure procedure.md)"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm14a]: a declared procedure with NO child ack PASSED -- work proceeded as if loading had happened: $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "C13" \
  || { echo "RED [arm14a]: the ackless procedure is not refused as C13: $out" >&2; exit 1; }
python3 - "$A14" <<'PY'
import json, os, sys
d = sys.argv[1]
c = json.load(open(os.path.join(d, "candidates.json")))
c["procedure"]["acks"] = {"child-A": "0" * 64}
json.dump(c, open(os.path.join(d, "candidates.json"), "w"), indent=1)
PY
out="$(run_check "$A14" --procedure procedure.md)"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm14b]: a WRONG ack digest PASSED -- the child did not read what it claims: $out" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -q "C13" || ! printf '%s\n' "$out" | grep -q "child-A"; then
  echo "RED [arm14b]: the wrong-digest refusal is not named C13/child-A: $out" >&2; exit 1
fi
out="$(run_check "$A14")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm14c]: candidates.json declares a procedure but the gate ran without --procedure and PASSED -- the asymmetry is silent: $out" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "C13" \
  || { echo "RED [arm14c]: the missing --procedure asymmetry is not refused as C13: $out" >&2; exit 1; }
python3 - "$A14" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]
h = hashlib.sha256(open(os.path.join(d, "procedure.md"), "rb").read()).hexdigest()
c = json.load(open(os.path.join(d, "candidates.json")))
c["procedure"]["acks"] = {"child-A": h}
json.dump(c, open(os.path.join(d, "candidates.json"), "w"), indent=1)
PY
out="$(run_check "$A14" --procedure procedure.md)"; rc=$?
if [ "$rc" -ne 0 ]; then
  echo "RED [arm14d]: the correct ack was refused (exit $rc): $out" >&2
  exit 1
fi
echo "ok [arm14: an unloaded procedure is refused as C13 each way; the true ack passes]"

# Arm 15 -- the primary floor counts DISTINCT ENTI (THR-SPEC ESITO 4): two
# corroborated primary pages, ONE ente, declared minimum two. The pre-SPEC
# checker counted pages and passed exactly this shape on the shipped
# dossier (e4-seen-passing.txt in the THR-SPEC run: four eia.gov pages
# against a floor of four).
A15="$WORK/a15"; mkbase "$A15"
python3 - "$A15" <<'PY'
import json, os, sys
d = sys.argv[1]
m = json.load(open(os.path.join(d, "sources.json")))
m["sources"][1]["url"] = "https://example.invalid/atmosphere"
json.dump(m, open(os.path.join(d, "sources.json"), "w"), indent=1)
PY
out="$(run_check "$A15")"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "RED [arm15]: two primary pages of ONE ente satisfied a floor of two -- pages counted, enti not: $out" >&2
  exit 1
fi
if ! printf '%s\n' "$out" | grep -q "C9" || ! printf '%s\n' "$out" | grep -qi "ente"; then
  echo "RED [arm15]: the floor refusal is not named C9/enti: $out" >&2; exit 1
fi
echo "ok [arm15: the primary floor counts distinct enti, never pages]"

echo "GREEN: a fabricated source fails the dossier, the author cannot write the citation, class and dating and figures are bound to evidence, a declared procedure must be evidenced as loaded, the primary floor counts enti, and no way of being empty reads as a pass, on all fifteen arms"
