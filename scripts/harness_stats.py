#!/usr/bin/env python3
"""On-demand dashboard from receipts. Stdlib only, no server.
Usage: harness_stats.py RECEIPTS_DIR [OUT_DIR]
Emits stats.md + dashboard.html. Inefficiency flags:
- subtype != success
- num_turns >= 80% of a 15-turn default budget (tune per fleet)
- missing constitution_hash (non-compliant run)
"""
import glob, html, json, os, subprocess, sys
from collections import Counter

TURN_BUDGET = 15
# 80% of TURN_BUDGET: 15 * 0.8 == 12, kept as an integer so the flag
# does not rest on float rounding.
TURNS_FLAG_THRESHOLD = 12

SUBPROCESS_TIMEOUT = 10  # seconds per external call


def run_cmd(args, cwd=None, timeout=SUBPROCESS_TIMEOUT):
    """Read-only subprocess wrapper shared by the D6 collectors (S3-S7).
    Returns (rc, stdout, stderr), or None when the command cannot run at
    all (missing binary, timeout): callers degrade to "unavailable",
    never raise (ADR-005 D6 graceful degradation)."""
    try:
        p = subprocess.run(args, cwd=cwd, timeout=timeout,
                           stdin=subprocess.DEVNULL, capture_output=True,
                           text=True, errors="replace")
    except (OSError, subprocess.SubprocessError):
        return None
    return (p.returncode, p.stdout, p.stderr)


def load_loose(rdir):
    # S2: loose *.receipt.json under the canonical dir (the tail since
    # the last rollup). An unreadable receipt still yields a row.
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
    if n >= TURNS_FLAG_THRESHOLD: out.append("TURNS>=80%BUDGET")
    return out


def tier_cell(r):
    # ADR-005 D4 schema tolerance: new-form receipts carry tier_resolved; old-form
    # receipts have neither tier_resolved nor model_string, only tier_requested.
    # Prefer tier_resolved; else fall back model_string -> tier_requested; else None.
    tr = r.get("tier_resolved")
    if tr is not None:
        return tr
    ms = r.get("model_string")
    return ms if ms is not None else r.get("tier_requested")


def collect(rdir):
    # Gather render sources (ADR-005 D6). Skeleton: only S2 (loose
    # receipts) is active; collectors S1/S3-S7 land in follow-up slices.
    rows = load_loose(rdir)
    return {
        "rows": rows,
        "by_sub": Counter(r.get("subtype", "?") for r in rows),
        "by_tier": Counter(tier_cell(r) for r in rows),
        "turns": sum(r.get("num_turns") or 0 for r in rows),
        "cost": sum(r.get("total_cost_usd") or 0 for r in rows),
    }


def render_stats_md(ctx):
    rows, turns, cost = ctx["rows"], ctx["turns"], ctx["cost"]
    lines = ["# Harness stats", "",
             f"runs: {len(rows)}  total_turns: {turns}  total_cost_usd: {cost:.4f}",
             f"by subtype: {dict(ctx['by_sub'])}", f"by tier: {dict(ctx['by_tier'])}", "",
             "## Flagged runs"]
    for r in rows:
        fl = flags(r)
        if fl:
            lines.append(f"- {r.get('run_id','?')} [{r.get('spec_id','?')}] "
                         f"turns={r.get('num_turns')} -> {', '.join(fl)}")
    return "\n".join(lines) + "\n"


def render_dashboard(ctx):
    rows, turns, cost = ctx["rows"], ctx["turns"], ctx["cost"]
    tr = []
    for r in rows:
        tr.append((r.get("run_id","?"), r.get("spec_id","?"),
                   tier_cell(r), r.get("subtype","?"),
                   r.get("num_turns"), r.get("total_cost_usd"),
                   ", ".join(flags(r))))
    cells = "".join(
        "<tr>" + "".join(f"<td>{html.escape(str(c))}</td>" for c in row) + "</tr>"
        for row in tr)
    doc = ("<!doctype html><meta charset='utf-8'><title>harness</title>"
           "<style>body{font:14px monospace}td,th{padding:4px 8px;"
           "border-bottom:1px solid #ccc}tr:has(td:last-child:not(:empty))"
           "{background:#fee}</style>"
           f"<h1>Harness runs ({len(rows)})</h1>"
           f"<p>turns={turns} cost_usd={cost:.4f} subtypes={dict(ctx['by_sub'])}</p>"
           "<table><tr><th>run</th><th>spec</th><th>tier</th><th>subtype</th>"
           "<th>turns</th><th>cost</th><th>flags</th></tr>" + cells + "</table>")
    return doc


def main():
    rdir = sys.argv[1] if len(sys.argv) > 1 else "./.harness/receipts"
    odir = sys.argv[2] if len(sys.argv) > 2 else rdir
    ctx = collect(rdir)
    open(os.path.join(odir, "stats.md"), "w").write(render_stats_md(ctx))
    open(os.path.join(odir, "dashboard.html"), "w").write(render_dashboard(ctx))
    print("wrote", os.path.join(odir, "stats.md"), "and dashboard.html")

if __name__ == "__main__":
    main()
