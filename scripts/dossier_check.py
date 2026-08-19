#!/usr/bin/env python3
"""The checkable floor of a dossier: sources exist as captured evidence,
they say what the document attributes to them, the coverage declared
BEFORE writing is met (THR-DOSSIER ESITO 3), the author cannot write his
own citations, and every figure is bound to evidence, dated and classed
(THR-METALS ESITI 2-3).

WHAT THIS IS NOT. No check here says a dossier is GOOD -- relevance,
balance and truth stay with the human reader. What a machine CAN refuse is
the fabricated reference and its neighbours: the source that does not say
it, the snapshot altered after the fact, the document too thin to mean
anything, the check that verified nothing and called that clean -- and,
since THR-METALS, the support pair the AUTHOR wrote instead of selecting
(ADR-025: an input the author cannot write), the company release dressed
as a regulator filing, the company-only claim presented as neutral, the
undated figure, and the figure that appears in no verified quote.

OFFLINE BY CONSTRUCTION. The evidence is snapshot files captured at
research time and pinned by sha256 in the manifest; this checker performs
no network I/O, so "could not reach the network" can never masquerade as
"zero problems" -- an absent snapshot is a named C2 failure, and a run
that verified nothing fails C7 by count. Whether a URL still serves those
bytes tomorrow is re-checkable by anyone WITH a network, from the url and
snapshot recorded per source; it is deliberately not this gate.

INPUTS. --doc D.md (citations are [SNN] markers); --sources sources.json
(per source: id, url, title, class in {filed, agency, company, other},
snapshot path relative to sources.json, sha256 of the snapshot bytes,
support[] pairs {for: verbatim document sentence, quote: verbatim snapshot
substring, as_of: the date a numeric quote's figure REFERS to -- never the
fetch date}); --coverage COVERAGE.json (declared section headings with
min_citations each, min_distinct_sources, min_support_pairs,
min_primary_sources, primary_host_suffixes[] -- hashed before the document
is written, so the gate measures the declaration, not a number fitted
after); --candidates candidates.json ({"sources": {SNN: [candidate
quotes]}}, the children's captured proposals, hashed before writing --
REQUIRED: a dossier without a captured candidate set is UNMEASURED, never
a silent pass); --procedure PROC (OPTIONAL, THR-SPEC ESITO 2: the child
procedure file the run declares its children loaded; candidates.json must
then carry {"procedure": {"sha256": hex, "acks": {child: hex}}} and every
ack must equal the file's own sha256 -- computable only by reading it).

CHECKS, each violation named on its own line:
  C1 citation resolution   every [SNN] in the document is in the manifest,
                           and every manifest source is cited.
  C2 snapshot integrity    every snapshot exists and matches its sha256.
  C3 attribution           every support pair's `for` appears in the
                           document and its `quote` appears in the named
                           snapshot (whitespace-normalized substrings).
  C4 no naked citation     every cited source carries >= 1 support pair.
  C5 coverage              every declared heading is present; per-section
                           citation instances meet the declared minimum.
  C6 anti-trivial          distinct cited sources and total support pairs
                           meet the declared minimums.
  C7 honest zero           a PASS requires every count > 0; the counts
                           line is printed on every run, pass or fail.
  C8 candidate membership  every support quote EQUALS (whitespace-
                           normalized) a member of its own source's
                           captured candidate set -- selection, never
                           authorship; trimming a candidate is authorship.
                           An unused candidate is normal; an uncaptured
                           quote is refused.
  C9 source class          every source's class is declared and known;
                           filed/agency must be corroborated by the URL
                           host matching a declared primary suffix (a
                           company PR declared "filed" is refused by
                           name); DISTINCT ENTI -- matched primary
                           suffixes among corroborated cited primary
                           sources -- meet min_primary_sources: four
                           pages of one ente are one ente, never four
                           (THR-SPEC ESITO 4).
  C10 company-only marking a claim whose EVERY supporting source is
                           company-class must carry [company-sourced] in
                           the `for` text itself -- the marker sits in the
                           reader's own line, C3 forces it into the
                           document.
  C11 figure dating        a support pair whose quote carries a digit
                           must carry as_of matching YYYY[-MM[-DD]] --
                           the date the figure refers to.
  C12 number coverage      every numeric token in the document body
                           (headings, [SNN] markers, HTML comments and
                           fenced code excluded; thousands separators
                           normalized) appears inside at least one
                           VERIFIED quote -- a mangled or invented figure
                           has no quote to hide in.
  C13 procedure loaded     when a child procedure is declared (either
                           side), every recorded ack equals the file's
                           sha256; no ack, a wrong digest, or a one-sided
                           declaration is refused by name -- work must
                           not proceed as if loading had happened.
The semantic residue is declared, not hidden: C3 binds sentence to quote
mechanically, C8 binds quote to capture, C11 checks the date was answered
in valid form; whether the quote SUPPORTS the sentence and the date is the
figure's true reference date remain the human checks the pairing exists to
make one-look cheap.

Exit: 0 PASS; 1 FAIL (violations named); 2 UNMEASURED (an input absent or
unparsable). Nothing here writes, fetches, or imports off the standard
library.
"""
import argparse
import hashlib
import json
import os
import re
import sys
from urllib.parse import urlparse

CITE = re.compile(r"\[(S\d+)\]")
NUM = re.compile(r"\d[\d,]*(?:\.\d+)?")
AS_OF = re.compile(r"\d{4}(-\d{2}){0,2}$")
MARKER = "[company-sourced]"
CLASSES = ("filed", "agency", "company", "other")
PRIMARY = ("filed", "agency")


def _norm(s):
    return " ".join(s.split())


def _numbers(text):
    return {m.group(0).replace(",", "") for m in NUM.finditer(text)}


def _load(path, what):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError as e:
        print("UNMEASURED: %s not readable at %s: %s" % (what, path, e))
        sys.exit(2)


def _load_json(path, what):
    try:
        return json.loads(_load(path, what))
    except ValueError as e:
        print("UNMEASURED: %s does not parse at %s: %s" % (what, path, e))
        sys.exit(2)


def _host_corroborated(url, suffixes):
    host = urlparse(url).hostname if isinstance(url, str) else None
    if not host:
        return False, host, None
    for suf in suffixes:
        if host == suf or host.endswith("." + suf):
            return True, host, suf
    return False, host, None


def main(argv):
    ap = argparse.ArgumentParser(prog="dossier_check.py",
                                 description=__doc__.splitlines()[0])
    ap.add_argument("--doc", required=True)
    ap.add_argument("--sources", required=True)
    ap.add_argument("--coverage", required=True)
    ap.add_argument("--candidates", required=True)
    ap.add_argument("--procedure")
    args = ap.parse_args(argv)

    doc = _load(args.doc, "document")
    manifest = _load_json(args.sources, "sources manifest")
    coverage = _load_json(args.coverage, "coverage declaration")
    cand_doc = _load_json(args.candidates, "captured candidate set")
    base = os.path.dirname(os.path.abspath(args.sources))

    sources = manifest.get("sources")
    if not isinstance(sources, list):
        print("UNMEASURED: sources manifest carries no 'sources' list")
        sys.exit(2)
    cand_map = cand_doc.get("sources")
    if not isinstance(cand_map, dict) or not all(
            isinstance(v, list) and all(isinstance(q, str) for q in v)
            for v in cand_map.values()):
        print("UNMEASURED: candidate set carries no 'sources' map of quote lists")
        sys.exit(2)

    v = []
    doc_norm = _norm(doc)
    cited = re.findall(CITE, doc)
    cited_set = set(cited)
    by_id = {}
    for s in sources:
        sid = s.get("id")
        if not isinstance(sid, str) or sid in by_id:
            v.append("C1 FAIL manifest: missing or duplicate source id %r" % (sid,))
            continue
        by_id[sid] = s

    # C1 -- both directions: a citation into nothing, a source never used.
    for sid in sorted(cited_set - set(by_id)):
        v.append("C1 FAIL %s: cited in the document, absent from the manifest" % sid)
    for sid in sorted(set(by_id) - cited_set):
        v.append("C1 FAIL %s: in the manifest, never cited in the document" % sid)

    # C2 -- the snapshot is the evidence; absent or altered is a named fail.
    verified = set()
    snap_norm = {}
    for sid in sorted(by_id):
        s = by_id[sid]
        rel = s.get("snapshot")
        path = os.path.join(base, rel) if isinstance(rel, str) else None
        if path is None or not os.path.isfile(path):
            v.append("C2 FAIL %s: snapshot missing at %s" % (sid, rel))
            continue
        with open(path, "rb") as fh:
            raw = fh.read()
        digest = hashlib.sha256(raw).hexdigest()
        if digest != s.get("sha256"):
            v.append("C2 FAIL %s: sha256 mismatch (manifest %s, disk %s)"
                     % (sid, s.get("sha256"), digest))
            continue
        verified.add(sid)
        snap_norm[sid] = _norm(raw.decode("utf-8", errors="replace"))

    # C3/C4/C8/C11 -- attribution pairs; a quote is only checkable against
    # a snapshot that verified (its absence is already C2's line); every
    # quote must be a MEMBER of its source's captured candidate set (C8);
    # a numeric quote must carry the date its figure refers to (C11).
    pairs_checked = 0
    verified_quotes = []
    claim_classes = {}
    for sid in sorted(by_id):
        s = by_id[sid]
        support = s.get("support") or []
        cand_norm = {_norm(c) for c in cand_map.get(sid, [])}
        if sid in cited_set and not support:
            v.append("C4 FAIL %s: cited but carries no support pair" % sid)
        for i, pair in enumerate(support):
            f, q = pair.get("for", ""), pair.get("quote", "")
            claim_classes.setdefault(_norm(f), set()).add(s.get("class"))
            if _norm(f) not in doc_norm:
                v.append("C3 FAIL %s pair %d: 'for' text not found in the document: %r"
                         % (sid, i, f[:80]))
            if _norm(q) not in cand_norm:
                v.append("C8 FAIL %s pair %d: quote not in the captured candidate set: %r"
                         % (sid, i, q[:80]))
            if re.search(r"\d", q):
                as_of = pair.get("as_of")
                if not (isinstance(as_of, str) and AS_OF.match(as_of)):
                    v.append("C11 FAIL %s pair %d: numeric quote without valid as_of "
                             "(the date the figure refers to): %r" % (sid, i, as_of))
            if sid in snap_norm:
                if _norm(q) not in snap_norm[sid]:
                    v.append("C3 FAIL %s pair %d: quote not found in snapshot: %r"
                             % (sid, i, q[:80]))
                else:
                    pairs_checked += 1
                    verified_quotes.append(q)

    # C9 -- the class is declared, known, and corroborated by the host;
    # the primary floor is met by DISTINCT ENTI (matched primary suffixes)
    # among corroborated cited sources -- never by page count: four pages
    # of one ente are one ente (THR-SPEC ESITO 4).
    suffixes = coverage.get("primary_host_suffixes") or []
    primary_cited = set()
    primary_enti = set()
    for sid in sorted(by_id):
        cls = by_id[sid].get("class")
        if cls not in CLASSES:
            v.append("C9 FAIL %s: source class missing or unknown: %r" % (sid, cls))
            continue
        if cls in PRIMARY:
            ok, host, suf = _host_corroborated(by_id[sid].get("url"), suffixes)
            if not ok:
                v.append("C9 FAIL %s: class %r not corroborated by host %r"
                         % (sid, cls, host))
            elif sid in cited_set:
                primary_cited.add(sid)
                primary_enti.add(suf)
    min_primary = coverage.get("min_primary_sources", 0)
    if len(primary_enti) < min_primary:
        v.append("C9 FAIL: %d distinct primary ente(s) (%s) across %d corroborated "
                 "cited page(s), declared minimum %d -- the floor counts enti, "
                 "never pages"
                 % (len(primary_enti), ",".join(sorted(primary_enti)) or "-",
                    len(primary_cited), min_primary))

    # C13 -- a run that declares a child procedure must evidence the LOAD:
    # every recorded ack equals the procedure file's own sha256, computable
    # only by reading it (THR-SPEC ESITO 2). A one-sided declaration --
    # flag without block, block without flag -- is refused, never silent.
    proc_block = cand_doc.get("procedure")
    if args.procedure:
        try:
            with open(args.procedure, "rb") as fh:
                proc_sha = hashlib.sha256(fh.read()).hexdigest()
        except OSError as e:
            print("UNMEASURED: procedure not readable at %s: %s"
                  % (args.procedure, e))
            sys.exit(2)
        if not isinstance(proc_block, dict):
            v.append("C13 FAIL: --procedure declared to the gate but "
                     "candidates.json carries no procedure block")
        else:
            if proc_block.get("sha256") != proc_sha:
                v.append("C13 FAIL: candidates.json pins procedure sha256 %r, "
                         "the file on disk hashes %s"
                         % (proc_block.get("sha256"), proc_sha))
            acks = proc_block.get("acks")
            if not isinstance(acks, dict) or not acks:
                v.append("C13 FAIL: procedure declared but NO child ack recorded "
                         "-- work proceeded as if loading had happened")
            else:
                for child in sorted(acks):
                    if acks[child] != proc_sha:
                        v.append("C13 FAIL %s: ack %r != procedure sha256 %s -- "
                                 "the child did not read what it claims"
                                 % (child, acks[child], proc_sha))
    elif proc_block is not None:
        v.append("C13 FAIL: candidates.json declares a procedure but the gate "
                 "was invoked without --procedure (the asymmetry is not silent)")

    # C10 -- a claim carried ONLY by company material says so in the
    # reader's own line.
    for f_norm in sorted(claim_classes):
        if claim_classes[f_norm] == {"company"} and MARKER not in f_norm:
            v.append("C10 FAIL: company-only claim unmarked: %r" % f_norm[:80])

    # C5 -- the declared sections, counted between declared headings.
    heads = coverage.get("sections") or []
    positions = []
    for h in heads:
        heading = h.get("heading", "")
        m = re.search(r"(?m)^%s\s*$" % re.escape(heading), doc)
        positions.append((heading, m.start() if m else None,
                          h.get("min_citations", 0)))
    found = sorted(p for _, p, _ in positions if p is not None)
    for heading, pos, need in positions:
        if pos is None:
            v.append("C5 FAIL: declared section heading absent: %r" % heading)
            continue
        nxt = min((p for p in found if p > pos), default=len(doc))
        got = len(re.findall(CITE, doc[pos:nxt]))
        if got < need:
            v.append("C5 FAIL %r: %d citation(s), declared minimum %d"
                     % (heading, got, need))

    # C6 -- the two trivial-emptiness floors.
    min_src = coverage.get("min_distinct_sources", 0)
    min_pairs = coverage.get("min_support_pairs", 0)
    total_pairs = sum(len(by_id[s].get("support") or []) for s in by_id)
    if len(cited_set & set(by_id)) < min_src:
        v.append("C6 FAIL: %d distinct cited source(s), declared minimum %d"
                 % (len(cited_set & set(by_id)), min_src))
    if total_pairs < min_pairs:
        v.append("C6 FAIL: %d support pair(s), declared minimum %d"
                 % (total_pairs, min_pairs))

    # C12 -- every figure in the document body lives inside a verified
    # quote. Headings, [SNN] markers, HTML comments and fenced code are
    # structure, not claims; everything else with a digit must be quoted.
    body = re.sub(r"<!--.*?-->", "", doc, flags=re.S)
    body = re.sub(r"(?ms)^```.*?^```\s*$", "", body)
    body = "\n".join(l for l in body.splitlines() if not l.lstrip().startswith("#"))
    body = CITE.sub("", body).replace(MARKER, "")
    quote_nums = set()
    for q in verified_quotes:
        quote_nums |= _numbers(q)
    for tok in sorted(_numbers(body) - quote_nums):
        v.append("C12 FAIL: figure %s appears in the document inside no verified quote"
                 % tok)

    # C7 -- the honest zero: the counts are printed on every run, and a
    # clean sheet with nothing verified is not a pass.
    counts = ("counts: sources_cited=%d snapshots_verified=%d "
              "support_pairs_checked=%d candidate_pool=%d primary_cited=%d "
              "primary_enti=%d"
              % (len(cited_set), len(verified), pairs_checked,
                 sum(len(x) for x in cand_map.values()), len(primary_cited),
                 len(primary_enti)))
    if not v and (not cited_set or not verified or not pairs_checked):
        v.append("C7 FAIL: nothing verified (%s); an empty check is not a clean one" % counts)

    for line in v:
        print(line)
    print(counts)
    if v:
        print("DOSSIER CHECK: FAIL (%d violation(s))" % len(v))
        return 1
    print("DOSSIER CHECK: PASS (%s)" % counts)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
