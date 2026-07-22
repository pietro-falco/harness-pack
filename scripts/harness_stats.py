#!/usr/bin/env python3
"""On-demand dashboard from receipts. Stdlib only, no server.
Usage: harness_stats.py RECEIPTS_DIR [OUT_DIR]
Emits stats.md + dashboard.html. Inefficiency flags:
- subtype != success
- num_turns >= 80% of a 15-turn default budget (tune per fleet)
- missing constitution_hash (non-compliant run)
"""
import glob, hashlib, html, json, os, subprocess, sys, tempfile
from collections import Counter

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

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


def display_value(v):
    """Render a schema-tolerant field for the mission-control table: an
    absent value is a dash, never zero or an empty cell (ADR-005 D4)."""
    return "—" if v is None else v


def _sha256_file(path):
    try:
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return None


def load_index(rdir):
    """S1: receipts-index.jsonl beside the loose receipts (ADR-005 D2).
    A missing file is simply an empty history (the caller decides how to
    surface that as "unavailable"). A malformed line is skipped with a
    parse-error note rather than raised (ADR-005 D6 graceful degradation
    -- the index never blocks the render)."""
    path = os.path.join(rdir, "receipts-index.jsonl")
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path, encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except Exception:
                rows.append({"seq": None, "source_filename": None,
                             "_index_parse_error": f"line {i} unreadable"})
    return rows


def list_loose_receipts(rdir):
    """Like load_loose(), but keeps each receipt's basename alongside its
    parsed content so callers (merge_runs) can dedup index<->loose overlap
    by source_filename -- the ADR-005 D2 join key, never run_id."""
    pairs = []
    for p in sorted(glob.glob(os.path.join(rdir, "*.receipt.json"))):
        basename = os.path.basename(p)
        try:
            pairs.append((basename, json.load(open(p))))
        except Exception:
            pairs.append((basename, {"run_id": basename, "subtype": "unreadable"}))
    return pairs


def merge_runs(rdir, index_rows, loose_pairs):
    """Union of receipts-index.jsonl (rolled-up history) and loose
    *.receipt.json (the tail since the last rollup). Dedup key is
    source_filename/basename (ADR-005 D2 join rule; never run_id).
    Index rows win on overlap; if the still-present loose copy no longer
    hashes to the index's source_sha256, a drift note is attached rather
    than silently trusting either side. Tail rows (not yet rolled up)
    render seq as a dash, ordered lexicographically by basename -- the
    same order the next rollup will assign seq numbers in (RS-001 R1)."""
    def seq_key(r):
        seq = r.get("seq")
        return (seq is None, seq if seq is not None else 0)

    indexed = {r["source_filename"]: r for r in index_rows if r.get("source_filename")}

    merged = []
    for r in sorted(index_rows, key=seq_key):
        row = dict(r)
        row["_seq_display"] = display_value(row.get("seq"))
        row["_cost_display"] = display_value(row.get("total_cost_usd"))
        row["_tail"] = False
        name = row.get("source_filename")
        if name:
            loose_path = os.path.join(rdir, name)
            if os.path.exists(loose_path):
                actual = _sha256_file(loose_path)
                expected = row.get("source_sha256")
                if actual and expected and actual != expected:
                    row["_drift"] = "source_sha256 mismatch vs loose copy"
        merged.append(row)

    tail = [(name, receipt) for name, receipt in loose_pairs if name not in indexed]
    tail.sort(key=lambda t: t[0])
    for name, receipt in tail:
        row = dict(receipt)
        row["source_filename"] = name
        row["_seq_display"] = "—"
        row["_cost_display"] = display_value(row.get("total_cost_usd"))
        row["_tail"] = True
        merged.append(row)
    return merged


def chain_status(rdir):
    """S3: receipt-chain.jsonl integrity (ADR-005 D6). The working-tree
    verify is advisory only; the authoritative check is against the
    blob committed at HEAD (receipt_chain.py's guarantee-boundary
    docstring) -- an uncommitted tail is expected, not a fault. A repo
    with no HEAD anchor for the chain (untracked, gitignored, or not a
    git repo at all) degrades to "no HEAD anchor", rendered neutral --
    that is the normal state for a gitignored .harness/, not a warning."""
    result = {"path_exists": False, "working_tree": None, "head": None}
    chain_path = os.path.join(rdir, "receipt-chain.jsonl")
    if not os.path.exists(chain_path):
        return result
    result["path_exists"] = True

    script = os.path.join(SCRIPT_DIR, "receipt_chain.py")
    wt = run_cmd([sys.executable, script, "verify", "--chain", chain_path])
    if wt is None:
        result["working_tree"] = "unavailable"
    else:
        rc, out, err = wt
        result["working_tree"] = "VALID" if rc == 0 else "INVALID"
        result["working_tree_detail"] = (out or err or "").strip()

    root_res = run_cmd(["git", "rev-parse", "--show-toplevel"], cwd=rdir)
    if root_res is None or root_res[0] != 0:
        result["head"] = "no HEAD anchor"
        return result
    root = root_res[1].strip()

    try:
        relpath = os.path.relpath(os.path.realpath(chain_path), os.path.realpath(root))
    except ValueError:
        result["head"] = "no HEAD anchor"
        return result

    show_res = run_cmd(["git", "show", f"HEAD:{relpath}"], cwd=root)
    if show_res is None or show_res[0] != 0:
        result["head"] = "no HEAD anchor"
        return result

    with tempfile.TemporaryDirectory() as tmpdir:
        head_chain = os.path.join(tmpdir, "receipt-chain.head.jsonl")
        with open(head_chain, "w", encoding="utf-8") as f:
            f.write(show_res[1])
        hv = run_cmd([sys.executable, script, "verify", "--chain", head_chain])
        if hv is None:
            result["head"] = "unavailable"
        else:
            rc, out, err = hv
            result["head"] = "VALID" if rc == 0 else "INVALID"
            result["head_detail"] = (out or err or "").strip()
    return result


def co_index_status(rdir):
    """S1+S3 cross-check: receipts_index.py gate -- the canonical V8
    co-indexing assertion (ADR-005 D3 single writer; never hand-roll a
    seq/sha comparison here, that would fork the logic). Either file
    missing degrades to "unavailable". A gate failure is a drift signal
    for the operator, not a renderer error: main() still exits 0
    (ADR-005 D6 graceful degradation)."""
    index_path = os.path.join(rdir, "receipts-index.jsonl")
    chain_path = os.path.join(rdir, "receipt-chain.jsonl")
    if not (os.path.exists(index_path) and os.path.exists(chain_path)):
        return {"status": "unavailable"}
    script = os.path.join(SCRIPT_DIR, "receipts_index.py")
    res = run_cmd([sys.executable, script, "gate",
                   "--index", index_path, "--chain", chain_path])
    if res is None:
        return {"status": "unavailable"}
    rc, out, err = res
    return {"status": "VALID" if rc == 0 else "DRIFT",
            "detail": (out or err or "").strip()}


def halt(root):
    """S6: .harness/HALT presence (the operator kill-switch, ADR-005
    D6). `root` is None (no git repo) -> unavailable; the file's mtime
    is surfaced when present so the banner can show since-when."""
    if root is None:
        return {"status": "unavailable"}
    path = os.path.join(root, ".harness", "HALT")
    if not os.path.exists(path):
        return {"status": "clear"}
    try:
        mtime = os.path.getmtime(path)
    except OSError:
        mtime = None
    return {"status": "engaged", "mtime": mtime}


def git_ops(root, n=15):
    """S5: recent operator commits (rollups, ADR propose/accept, deploy
    markers). No repo -> unavailable; never raises."""
    if root is None:
        return {"status": "unavailable"}
    res = run_cmd(["git", "log", "--oneline", f"-n{n}"], cwd=root)
    if res is None or res[0] != 0:
        return {"status": "unavailable"}
    lines = [l for l in res[1].splitlines() if l.strip()]
    return {"status": "ok", "lines": lines}


def repo_root(rdir):
    """Shared root resolution for the S4-S7 collectors: rc 128 (not a
    git repo) or any other subprocess failure degrades to None, which
    each collector treats as "unavailable" -- never a raised error."""
    res = run_cmd(["git", "rev-parse", "--show-toplevel"], cwd=rdir)
    if res is None or res[0] != 0:
        return None
    return res[1].strip()


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
