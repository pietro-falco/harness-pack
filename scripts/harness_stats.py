#!/usr/bin/env python3
"""On-demand dashboard from receipts. Stdlib only, no server.
Usage: harness_stats.py RECEIPTS_DIR [OUT_DIR]
Emits stats.md + dashboard.html. Inefficiency flags:
- subtype != success
- num_turns >= 80% of a 15-turn default budget (tune per fleet)
- missing constitution_hash (non-compliant run)
"""
import glob, html, json, os, sys
from collections import Counter

def load(rdir):
    rows = []
    for p in sorted(glob.glob(os.path.join(rdir, "*.receipt.json"))):
        try:
            rows.append(json.load(open(p)))
        except Exception:
            rows.append({"run_id": os.path.basename(p), "subtype": "unreadable"})
    return rows

def flags(r):
    out = []
    if r.get("subtype") != "success": out.append("NOT-SUCCESS")
    if not r.get("constitution_hash"): out.append("NO-CONSTITUTION")
    n = r.get("num_turns") or 0
    if n >= 12: out.append("TURNS>=80%BUDGET")
    return out

def main():
    rdir = sys.argv[1] if len(sys.argv) > 1 else "./.harness/receipts"
    odir = sys.argv[2] if len(sys.argv) > 2 else rdir
    rows = load(rdir)
    by_sub = Counter(r.get("subtype", "?") for r in rows)
    by_tier = Counter(r.get("tier_resolved", "?") for r in rows)
    turns = sum(r.get("num_turns") or 0 for r in rows)
    cost = sum(r.get("total_cost_usd") or 0 for r in rows)
    lines = ["# Harness stats", "",
             f"runs: {len(rows)}  total_turns: {turns}  total_cost_usd: {cost:.4f}",
             f"by subtype: {dict(by_sub)}", f"by tier: {dict(by_tier)}", "",
             "## Flagged runs"]
    tr = []
    for r in rows:
        fl = flags(r)
        if fl:
            lines.append(f"- {r.get('run_id','?')} [{r.get('spec_id','?')}] "
                         f"turns={r.get('num_turns')} -> {', '.join(fl)}")
        tr.append((r.get("run_id","?"), r.get("spec_id","?"),
                   r.get("tier_resolved","?"), r.get("subtype","?"),
                   r.get("num_turns"), r.get("total_cost_usd"),
                   ", ".join(fl)))
    open(os.path.join(odir, "stats.md"), "w").write("\n".join(lines) + "\n")
    cells = "".join(
        "<tr>" + "".join(f"<td>{html.escape(str(c))}</td>" for c in row) + "</tr>"
        for row in tr)
    doc = ("<!doctype html><meta charset='utf-8'><title>harness</title>"
           "<style>body{font:14px monospace}td,th{padding:4px 8px;"
           "border-bottom:1px solid #ccc}tr:has(td:last-child:not(:empty))"
           "{background:#fee}</style>"
           f"<h1>Harness runs ({len(rows)})</h1>"
           f"<p>turns={turns} cost_usd={cost:.4f} subtypes={dict(by_sub)}</p>"
           "<table><tr><th>run</th><th>spec</th><th>tier</th><th>subtype</th>"
           "<th>turns</th><th>cost</th><th>flags</th></tr>" + cells + "</table>")
    open(os.path.join(odir, "dashboard.html"), "w").write(doc)
    print("wrote", os.path.join(odir, "stats.md"), "and dashboard.html")

if __name__ == "__main__":
    main()
