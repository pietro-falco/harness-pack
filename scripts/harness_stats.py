#!/usr/bin/env python3
"""On-demand mission-control dashboard over the seven D6 read-only
sources (ADR-005 D6/D7). Stdlib only, no server, no JavaScript.
Usage: harness_stats.py RECEIPTS_DIR [OUT_DIR]
Emits dashboard.html (primary) + stats.md (secondary). Inefficiency flags:
- subtype != success
- num_turns >= 80% of a 15-turn default budget (tune per fleet)
- missing constitution_hash (non-compliant run)
"""
import glob, hashlib, html, json, os, subprocess, sys, tempfile
from collections import Counter
from datetime import datetime, timezone

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


def _resolve_harnesswright_cli():
    """Same resolution order as launch_worker.sh: HARNESSWRIGHT_CLI env
    (empty string counts as unset) wins, invoked via `node`; otherwise
    a `harnesswright` binary on PATH. None if neither resolves --
    harnesswright is optional (ADR-005 D6)."""
    cli = os.environ.get("HARNESSWRIGHT_CLI", "")
    if cli:
        return ["node", cli]
    import shutil
    path_bin = shutil.which("harnesswright")
    if path_bin:
        return [path_bin]
    return None


def next_slice(root):
    """S4: harnesswright next --json (the eligible slice). Parsed
    defensively field-by-field, mirroring the launcher's own consumer
    (launch_worker.sh) -- the schema is derived from that consumer, not
    verified against a live harnesswright (ADR-005 D6). spec.model is
    an opaque model_string (e.g. "executor"), never a real model id, so
    it is safe to surface here."""
    base = _resolve_harnesswright_cli()
    if base is None:
        return {"status": "unavailable"}
    res = run_cmd(base + ["next", "--json"], cwd=root, timeout=10)
    if res is None:
        return {"status": "unavailable"}
    rc, out, err = res
    if rc != 0:
        return {"status": "unavailable", "detail": (err or out or "").strip()}
    try:
        data = json.loads(out)
    except Exception:
        return {"status": "unavailable", "detail": "next --json returned non-JSON output"}
    if not isinstance(data, dict):
        return {"status": "unavailable"}

    kind = data.get("kind")
    if kind != "unlocked":
        return {"status": kind or "unavailable"}

    spec = data.get("spec") if isinstance(data.get("spec"), dict) else {}
    budget = spec.get("budget") if isinstance(spec.get("budget"), dict) else {}
    tools = spec.get("tools") if isinstance(spec.get("tools"), list) else []
    criteria = spec.get("criteria") if isinstance(spec.get("criteria"), list) else []
    return {
        "status": "unlocked",
        "id": data.get("id"),
        "eligible_mode_b": data.get("eligible_mode_b"),
        "model": spec.get("model"),
        "turns": budget.get("turns"),
        "wall_clock": budget.get("wall_clock"),
        "tools": [t for t in tools if isinstance(t, str) and t],
        "criteria": [c for c in criteria if isinstance(c, str) and c],
    }


def tamper():
    """S7: enforced-tree integrity via detect_tamper.sh. Distinguishes
    "not deployed" (enforced root absent -- neutral, expected on a dev
    machine) from "diverges" (tampered or incomplete -- an operator
    full-stop), never conflating the two (ADR-005 D6)."""
    script = os.path.join(SCRIPT_DIR, "detect_tamper.sh")
    res = run_cmd(["bash", script], timeout=30)
    if res is None:
        return {"status": "unavailable"}
    rc, out, err = res
    text = (out or "") + (err or "")
    if rc == 0:
        return {"status": "ok", "detail": out.strip()}
    # detect_tamper.sh's own two non-tamper messages: an absent enforced
    # root or a missing/empty manifest both mean "not deployed yet", not
    # tampering -- only its shasum-mismatch message means "diverges".
    if "enforced root absent" in text or "manifest missing or empty" in text:
        return {"status": "not-deployed", "detail": text.strip()}
    return {"status": "diverges", "detail": text.strip()}


def esc(v):
    """html.escape over str() -- every runtime value rendered into the
    dashboard passes through here."""
    return html.escape(str(v))


def row_kind(row):
    """Classify a merged row: unreadable > source-only > run. A
    source-only row is an index row (never a loose tail receipt) whose
    five run fields are all null -- it indexes a non-receipt source
    (ADR-005 D2), so it is not a failed run and is never flagged as
    one. A loose receipt with the same nulls stays a run: a receipt
    file with no metadata is a broken run, not a non-run source."""
    if row.get("subtype") == "unreadable":
        return "unreadable"
    if not row.get("_tail") and all(
            row.get(k) is None
            for k in ("run_id", "spec_id", "subtype", "num_turns", "started_at")):
        return "source-only"
    return "run"


def gate_verdict(r):
    """Gate verdict of one row, read the same two ways receipts_index.py
    distills it (flat gate_verdict on index rows, nested gate.verdict on
    raw receipts) -- a schema read, not a fork of the gate logic."""
    gv = r.get("gate_verdict")
    if gv is not None:
        return gv
    gate = r.get("gate")
    if isinstance(gate, dict):
        return gate.get("verdict")
    return None


def display_dir(rdir, root):
    """Provenance label for the header: repo-relative when the receipts
    dir sits under the repo root, else its basename -- never an absolute
    path, so the rendered HTML cannot leak a local home directory."""
    ab = os.path.abspath(rdir)
    if root:
        rel = os.path.relpath(ab, os.path.abspath(root))
        if ".." not in rel.split(os.sep):
            return rel
    return os.path.basename(ab)


def collect(rdir):
    """Gather the seven D6 render sources. Every collector degrades
    instead of raising; a degraded source is data for the source map,
    never a renderer error (ADR-005 D6)."""
    index_rows = load_index(rdir)
    loose_pairs = list_loose_receipts(rdir)
    runs = merge_runs(rdir, index_rows, loose_pairs)
    root = repo_root(rdir)
    run_rows = [r for r in runs if row_kind(r) != "source-only"]
    chain = chain_status(rdir)
    chain_links = 0
    if chain["path_exists"]:
        try:
            with open(os.path.join(rdir, "receipt-chain.jsonl"),
                      encoding="utf-8") as f:
                chain_links = sum(1 for line in f if line.strip())
        except OSError:
            chain_links = 0
    costs = [r.get("total_cost_usd") for r in run_rows]
    return {
        "runs": runs,
        "run_rows": run_rows,
        "by_sub": Counter(r.get("subtype", "?") for r in run_rows),
        "by_tier": Counter(tier_cell(r) for r in run_rows),
        "turns": sum(r.get("num_turns") or 0 for r in run_rows),
        "cost": sum(c or 0 for c in costs),
        "cost_covered": sum(1 for c in costs if c is not None),
        "index_present": os.path.exists(
            os.path.join(rdir, "receipts-index.jsonl")),
        "index_count": len(index_rows),
        "loose_count": len(loose_pairs),
        "chain": chain,
        "chain_links": chain_links,
        "co_index": co_index_status(rdir),
        "halt": halt(root),
        "git": git_ops(root),
        # S4 is gated on root: outside a repo there is no state dir for
        # harnesswright to read, so the CLI is never even invoked.
        "slice": next_slice(root) if root else {"status": "unavailable"},
        "tamper": tamper(),
        "rdir_display": display_dir(rdir, root),
        "generated_utc": datetime.now(timezone.utc).strftime(
            "%Y-%m-%d %H:%M UTC"),
    }


def render_stats_md(ctx):
    # The header lines stay verbatim from the original renderer (the D1
    # test pins the literal "runs: N" prefix); detail sections append.
    rows, turns, cost = ctx["run_rows"], ctx["turns"], ctx["cost"]
    lines = ["# Harness stats", "",
             f"runs: {len(rows)}  total_turns: {turns}  total_cost_usd: {cost:.4f}",
             f"by subtype: {dict(ctx['by_sub'])}", f"by tier: {dict(ctx['by_tier'])}", "",
             "## Flagged runs"]
    for r in rows:
        fl = flags(r)
        if fl:
            lines.append(f"- {r.get('run_id','?')} [{r.get('spec_id','?')}] "
                         f"turns={r.get('num_turns')} -> {', '.join(fl)}")
    chain, ci = ctx["chain"], ctx["co_index"]
    lines += ["", "## Chain",
              "working-tree: " + str(chain.get("working_tree") or "no chain file"),
              "HEAD-anchored: " + str(chain.get("head") or "no chain file"),
              f"links: {ctx['chain_links']}",
              "co-index gate: " + str(ci.get("status"))]
    h, g = ctx["halt"], ctx["git"]
    lines += ["", "## Repo state", "HALT: " + str(h.get("status"))]
    if g.get("status") == "ok":
        lines.append(f"recent operator commits ({len(g['lines'])}):")
        lines += ["  " + l for l in g["lines"]]
    else:
        lines.append("recent operator commits: unavailable")
    s = ctx["slice"]
    lines += ["", "## Eligible slice", "status: " + str(s.get("status"))]
    if s.get("status") == "unlocked":
        lines += [f"id: {display_value(s.get('id'))}",
                  f"model: {display_value(s.get('model'))}",
                  f"budget: turns={display_value(s.get('turns'))} "
                  f"wall_clock={display_value(s.get('wall_clock'))}",
                  f"mode-B eligible: {display_value(s.get('eligible_mode_b'))}"]
    t = ctx["tamper"]
    lines += ["", "## Enforced tree", "status: " + str(t.get("status"))]
    lines += ["", "## Sources",
              "index: " + (f"present, {ctx['index_count']} rows"
                           if ctx["index_present"] else "absent"),
              f"loose receipts: {ctx['loose_count']}",
              "chain: " + ("present" if chain["path_exists"] else "absent"),
              "co-index gate: " + str(ci.get("status")),
              "next slice: " + str(s.get("status")),
              "git log: " + str(g.get("status")),
              "HALT: " + str(h.get("status")),
              "enforced tree: " + str(t.get("status"))]
    return "\n".join(lines) + "\n"


# ---- dashboard (ADR-005 D7: static HTML is the primary rendering) ----

GLYPH = {"green": "✓", "amber": "▲", "hot": "■", "grey": "—"}

# Dark-only design system. Contrast is computed, never eyeballed: every
# ink and semantic color below measures >= 4.5:1 against --panel (mute
# was re-stepped upward to clear that bar). No 3-digit hex anywhere.
_CSS = """
:root{
  --bg:#0E0F0C; --panel:#161711; --raised:#1C1D16; --hair:#2A2B22;
  --ink:#E9E7DA; --ink-2:#A9A796; --mute:#8A8875;
  --green:#57C878; --amber:#E8A93C; --hot:#F07636; --grey:#9A9888;
  --mono:ui-monospace,"SF Mono",Menlo,Consolas,monospace;
  --sans:system-ui,-apple-system,"Segoe UI",sans-serif;
}
*{box-sizing:border-box;margin:0;padding:0}
html{color-scheme:dark}
body{background:var(--bg);color:var(--ink);font:13px/1.45 var(--sans);padding:0 16px 48px}
.wrap{max-width:1560px;margin:0 auto}
.halt-banner{background:var(--hot);color:var(--bg);font:600 13px/1.2 var(--sans);letter-spacing:.02em;padding:12px 16px;margin:0 -16px}
header{display:flex;align-items:baseline;justify-content:space-between;flex-wrap:wrap;gap:8px 16px;padding:20px 0 14px;border-bottom:1px solid var(--hair)}
h1{font:600 16px/1.2 var(--sans);letter-spacing:.06em}
.prov{font:11.5px var(--mono);color:var(--ink-2)}
.eyebrow{font:600 10px/1 var(--sans);letter-spacing:.08em;text-transform:uppercase;color:var(--ink-2)}
section{margin:18px 0}
section>.eyebrow{margin-bottom:8px}
.rail{display:grid;grid-template-columns:repeat(5,1fr);gap:16px;margin:16px 0}
.rail-cell{background:var(--panel);border:1px solid var(--hair);border-radius:4px;padding:10px 12px;min-width:0}
.rail-state{font:600 16px/1.3 var(--mono);margin-top:6px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rail-sub{font:11.5px/1.4 var(--mono);color:var(--mute);margin-top:2px}
.c-green{color:var(--green)}.c-amber{color:var(--amber)}.c-hot{color:var(--hot)}.c-grey{color:var(--grey)}
.kpis{display:flex;flex-wrap:wrap;gap:16px}
.kpi{background:var(--panel);border:1px solid var(--hair);border-radius:4px;padding:10px 14px;flex:1 1 150px}
.kpi-value{font:600 22px/1.2 var(--mono);font-variant-numeric:tabular-nums;margin-top:6px}
.kpi-sub{font:11.5px/1.4 var(--mono);color:var(--mute);margin-top:2px}
.spark{display:block;margin-top:8px}
.spark polyline{fill:none;stroke:var(--mute);stroke-width:2}
.spark-none{display:block;margin-top:8px;color:var(--mute)}
.dot-green{fill:var(--green)}.dot-amber{fill:var(--amber)}.dot-hot{fill:var(--hot)}.dot-grey{fill:var(--grey)}
.card{background:var(--panel);border:1px solid var(--hair);border-radius:4px}
.card-pad{padding:12px 14px}
table{width:100%;border-collapse:collapse;font:11.5px/1.4 var(--mono)}
thead th{position:sticky;top:0;z-index:1;background:var(--raised);color:var(--ink-2);font:600 10px/1 var(--sans);letter-spacing:.08em;text-transform:uppercase;text-align:left;padding:8px 10px;border-bottom:1px solid var(--hair);white-space:nowrap}
td{padding:3px 10px;height:26px;border-bottom:1px solid var(--hair);white-space:nowrap;vertical-align:middle}
tbody tr:last-child td{border-bottom:0}
th.num,td.num{text-align:right;font-variant-numeric:tabular-nums}
td.trunc{max-width:190px;overflow:hidden;text-overflow:ellipsis}
td.null{color:var(--mute)}
tr.flagged>td:first-child{box-shadow:inset 2px 0 var(--amber)}
tr.hot>td:first-child{box-shadow:inset 2px 0 var(--hot)}
tr.srconly td{color:var(--mute)}
.chip{display:inline-block;font:600 10px/1.7 var(--mono);padding:0 7px;border-radius:3px;white-space:nowrap}
.chip-green{color:var(--green);background:rgba(87,200,120,.14)}
.chip-amber{color:var(--amber);background:rgba(232,169,60,.14)}
.chip-hot{color:var(--hot);background:rgba(240,118,54,.14)}
.chip-grey{color:var(--grey);background:rgba(154,152,136,.14)}
.cols{display:grid;grid-template-columns:1fr 1fr;gap:16px;align-items:start}
.kv{display:grid;grid-template-columns:150px 1fr;gap:4px 12px;font:11.5px/1.6 var(--mono);margin-top:10px}
.kv dt{color:var(--ink-2)}
.kv dd{min-width:0;overflow-wrap:anywhere}
.cardnote{font:11.5px/1.5 var(--mono);color:var(--grey);margin-top:8px}
.crit{margin:2px 0 0 16px}
.crit li{margin:2px 0}
.commits{font:11.5px/1.9 var(--mono);color:var(--ink-2);overflow-x:auto}
.srcmap{display:flex;flex-wrap:wrap;gap:8px 22px;font:11.5px/1.6 var(--mono)}
.src{display:flex;gap:7px;align-items:baseline;white-space:nowrap}
.src-name{color:var(--ink-2)}
.src-why{color:var(--mute)}
@media(max-width:1000px){.rail{grid-template-columns:repeat(2,1fr)}.cols{grid-template-columns:1fr}}
"""


def _state(color, text):
    return f'<span class="c-{color}">{GLYPH[color]} {esc(text)}</span>'


def _chip(color, label):
    return f'<span class="chip chip-{color}">{GLYPH[color]} {esc(label)}</span>'


def _td(v, cls=""):
    """One ledger cell. Null renders as a muted dash -- never zero,
    never an empty cell: 0 is a measured value, the dash is absence."""
    isnull = v is None or v == "—"
    inner = "—" if isnull else esc(v)
    c = (cls + (" null" if isnull else "")).strip()
    return f'<td class="{c}">{inner}</td>' if c else f"<td>{inner}</td>"


def _sparkline(values, final_color):
    """Inline-SVG trend over the last runs. None is a gap in the line,
    never a zero; fewer than two known points renders a plain dash. A
    lone point between gaps draws no segment -- the final dot below
    still marks the latest known value. Coordinates stay inside the
    120x28 viewBox by construction."""
    pts = values[-24:]
    known = [v for v in pts if v is not None]
    if len(known) < 2:
        return '<span class="spark-none">—</span>'
    top = max(known)
    n = len(pts)

    def xy(i, v):
        x = 4 + 112 * i / (n - 1)
        y = 24 - (18 * v / top if top else 0)
        return f"{x:.1f},{y:.1f}"

    segs, cur = [], []
    for i, v in enumerate(pts):
        if v is None:
            if len(cur) >= 2:
                segs.append(cur)
            cur = []
        else:
            cur.append(xy(i, v))
    if len(cur) >= 2:
        segs.append(cur)
    lines = "".join('<polyline points="' + " ".join(s) + '"/>' for s in segs)
    last_i = max(i for i, v in enumerate(pts) if v is not None)
    fx, fy = xy(last_i, pts[last_i]).split(",")
    dot = f'<circle cx="{fx}" cy="{fy}" r="2.5" class="dot-{final_color}"/>'
    return ('<svg class="spark" viewBox="0 0 120 28" width="120" height="28" '
            'aria-hidden="true">' + lines + dot + "</svg>")


def _rail(ctx):
    """The status rail: five instrument cells reading the stack's real
    trust pipeline in order -- kill-switch, log integrity, deploy
    integrity, last verdict, next eligible slice. Green only where a
    verification actually passed; neutral states stay grey."""
    h, ch, ci = ctx["halt"], ctx["chain"], ctx["co_index"]
    t, s = ctx["tamper"], ctx["slice"]
    run_rows, links = ctx["run_rows"], ctx["chain_links"]

    if h.get("status") == "engaged":
        halt_c = ("hot", "ENGAGED", "operator kill-switch is set")
    elif h.get("status") == "clear":
        halt_c = ("grey", "clear", "no HALT file")
    else:
        halt_c = ("grey", "unavailable", "not in a git repo")

    if not ch["path_exists"]:
        chain_c = ("grey", "no chain", "nothing rolled up yet")
    elif ch.get("working_tree") == "INVALID" or ch.get("head") == "INVALID":
        chain_c = ("hot", "INVALID", "hash chain broken")
    elif ci.get("status") == "DRIFT":
        chain_c = ("amber", "CO-INDEX DRIFT", "index and chain disagree")
    elif ch.get("head") == "VALID":
        chain_c = ("green", "VALID @HEAD", f"{links} links · authoritative")
    elif ch.get("working_tree") == "VALID":
        chain_c = ("green", "VALID", f"{links} links · advisory · no HEAD anchor")
    else:
        chain_c = ("grey", "unavailable", "verify did not run")

    tree_c = {"ok": ("green", "DETECT-OK", "enforced tree matches manifest"),
              "not-deployed": ("grey", "not deployed",
                               "no enforced tree on this machine"),
              "diverges": ("hot", "DIVERGES", "tampered or incomplete deploy"),
              }.get(t.get("status"),
                    ("grey", "unavailable", "detect script did not run"))

    last = run_rows[-1] if run_rows else None
    if last is None:
        gate_c = ("grey", "no runs", "nothing to judge yet")
    else:
        v = gate_verdict(last)
        rid = str(display_value(last.get("run_id")))
        if v == "PASS":
            gate_c = ("green", "PASS", f"last run {rid}")
        elif v == "FAIL":
            gate_c = ("hot", "FAIL", f"last run {rid}")
        elif v is None:
            gate_c = ("grey", "no verdict", f"last run {rid} carries none")
        else:
            gate_c = ("amber", str(v), f"last run {rid}")

    sst = s.get("status")
    if sst == "unlocked":
        slice_c = ("amber", f"{display_value(s.get('id'))} ready",
                   "waiting on the operator")
    elif sst == "unavailable":
        slice_c = ("grey", "unavailable", "harnesswright not resolvable")
    else:
        slice_c = ("grey", str(sst), "no eligible slice")

    cells = []
    for name, (color, word, sub) in (("halt", halt_c), ("chain", chain_c),
                                     ("tree", tree_c), ("gate", gate_c),
                                     ("slice", slice_c)):
        cells.append(
            f'<div class="rail-cell" data-rail="{name}">'
            f'<div class="eyebrow">{name.upper()}</div>'
            f'<div class="rail-state c-{color}">{GLYPH[color]} {esc(word)}</div>'
            f'<div class="rail-sub">{esc(sub)}</div></div>')
    return '<div class="rail">' + "".join(cells) + "</div>"


def _kpis(ctx):
    run_rows, runs = ctx["run_rows"], ctx["runs"]
    indexed = sum(1 for r in run_rows if not r.get("_tail"))
    tail = len(run_rows) - indexed
    srconly = len(runs) - len(run_rows)
    last_gate = gate_verdict(run_rows[-1]) if run_rows else None
    dot = ("green" if last_gate == "PASS"
           else "hot" if last_gate == "FAIL" else "grey")
    succ = ctx["by_sub"].get("success", 0)
    flagged = sum(1 for r in run_rows if flags(r))
    cells = [
        ("runs", str(len(run_rows)),
         f"{indexed} indexed · {tail} tail · {srconly} non-run src", ""),
        ("turns total", str(ctx["turns"]), "",
         _sparkline([r.get("num_turns") for r in run_rows], dot)),
        ("cost usd", f"{ctx['cost']:.2f}",
         f"on {ctx['cost_covered']}/{len(run_rows)} runs",
         _sparkline([r.get("total_cost_usd") for r in run_rows], dot)),
        ("success", f"{succ}/{len(run_rows)}", "subtype == success", ""),
        ("flagged", str(flagged), "runs with attention flags", ""),
    ]
    out = []
    for label, value, sub, spark in cells:
        out.append('<div class="kpi"><div class="eyebrow">' + esc(label)
                   + f'</div><div class="kpi-value">{esc(value)}</div>'
                   + (f'<div class="kpi-sub">{esc(sub)}</div>' if sub else "")
                   + spark + "</div>")
    return '<div class="kpis">' + "".join(out) + "</div>"


LEDGER_COLS = (("seq", "num"), ("run", ""), ("spec", ""), ("type", ""),
               ("model_string", ""), ("tier", ""), ("model_used", ""),
               ("turns", "num"), ("cost", "num"), ("subtype", ""),
               ("gate", ""), ("stop", ""), ("flags", ""))


def _ledger(ctx):
    head = "".join(f'<th class="{c}">{esc(n)}</th>' if c else f"<th>{esc(n)}</th>"
                   for n, c in LEDGER_COLS)
    body = []
    for r in ctx["runs"]:
        kind = row_kind(r)
        fl = flags(r) if kind != "source-only" else []
        v = gate_verdict(r)
        classes = []
        if kind == "source-only":
            classes.append("srconly")
        else:
            if "NOT-SUCCESS" in fl or v == "FAIL":
                classes.append("hot")
            if fl:
                classes.append("flagged")
        if r.get("_drift"):
            classes.append("drift")
        tr_open = ('<tr class="' + " ".join(classes) + '">') if classes else "<tr>"

        if kind == "source-only":
            flag_html = _chip("grey", "non-run source")
        else:
            chips = []
            if kind == "unreadable":
                chips.append(_chip("amber", "UNREADABLE"))
            for f in fl:
                chips.append(_chip("hot" if f == "NOT-SUCCESS" else "amber", f))
            if r.get("_drift"):
                chips.append(_chip("amber", "SHA DRIFT"))
            flag_html = " ".join(chips) or '<span class="null">—</span>'

        if v == "PASS":
            gate_html = _chip("green", "PASS")
        elif v == "FAIL":
            gate_html = _chip("hot", "FAIL")
        elif v is None:
            gate_html = '<span class="null">—</span>'
        else:
            gate_html = _chip("amber", str(v))

        # The tier column stays a bare <td> rendered by tier_cell()
        # verbatim -- the D4 assertions pin the literal <td>T2</td>.
        cells = [
            _td(r.get("_seq_display"), "num"),
            _td(r.get("run_id"), "trunc"),
            _td(r.get("spec_id"), "trunc"),
            _td(r.get("type")),
            _td(r.get("model_string"), "trunc"),
            f"<td>{esc(display_value(tier_cell(r)))}</td>",
            _td(r.get("model_used"), "trunc"),
            _td(r.get("num_turns"), "num"),
            _td(r.get("_cost_display"), "num"),
            _td(r.get("subtype")),
            "<td>" + gate_html + "</td>",
            _td(r.get("stop_reason"), "trunc"),
            "<td>" + flag_html + "</td>",
        ]
        body.append(tr_open + "".join(cells) + "</tr>")
    if not body:
        body.append('<tr><td class="null" colspan="13">no runs recorded — '
                    "the ledger fills after the first receipt</td></tr>")
    return ('<section><div class="eyebrow">recent runs — index ∪ loose</div>'
            '<div class="card"><table><thead><tr>' + head
            + "</tr></thead><tbody>\n" + "\n".join(body)
            + "\n</tbody></table></div></section>")


def _slice_card(s):
    head = '<div class="eyebrow">eligible slice</div>'
    st = s.get("status")
    if st != "unlocked":
        why = {"unavailable": "harnesswright not resolvable from here"
               }.get(st, "no slice is eligible right now")
        return ('<div class="card card-pad">' + head
                + f'<div class="rail-state">{_state("grey", st or "unavailable")}</div>'
                + f'<p class="cardnote">{esc(why)}</p></div>')
    pairs = [("id", display_value(s.get("id"))),
             ("mode B eligible", display_value(s.get("eligible_mode_b"))),
             ("model", display_value(s.get("model"))),
             ("budget turns", display_value(s.get("turns"))),
             ("wall clock", display_value(s.get("wall_clock"))),
             ("tools", " · ".join(s.get("tools") or []) or "—")]
    kv = "".join(f"<dt>{esc(k)}</dt><dd>{esc(v)}</dd>" for k, v in pairs)
    crit = s.get("criteria") or []
    if crit:
        kv += ('<dt>criteria</dt><dd><ul class="crit">'
               + "".join(f"<li>{esc(c)}</li>" for c in crit) + "</ul></dd>")
    else:
        kv += '<dt>criteria</dt><dd class="null">—</dd>'
    unlocked = _state("amber", str(display_value(s.get("id"))) + " unlocked")
    return ('<div class="card card-pad">' + head
            + f'<div class="rail-state">{unlocked}</div>'
            + '<div class="rail-sub">waiting on the operator</div>'
            + f'<dl class="kv">{kv}</dl></div>')


def _chain_card(ctx):
    ch, ci, links = ctx["chain"], ctx["co_index"], ctx["chain_links"]
    head = '<div class="eyebrow">chain status</div>'
    if not ch["path_exists"]:
        return ('<div class="card card-pad">' + head
                + f'<div class="rail-state">{_state("grey", "no chain")}</div>'
                + '<p class="cardnote">receipt-chain.jsonl absent — nothing '
                  "has been rolled up yet</p></div>")

    def vstate(v):
        if v == "VALID":
            return _state("green", "VALID")
        if v == "INVALID":
            return _state("hot", "INVALID")
        return _state("grey", v or "unavailable")

    ci_st = ci.get("status")
    if ci_st == "VALID":
        ci_html = _state("green", "VALID")
    elif ci_st == "DRIFT":
        ci_html = (_state("amber", "DRIFT")
                   + f' <span class="src-why">{esc(ci.get("detail") or "")}</span>')
    else:
        ci_html = _state("grey", "unavailable")
    kv = ("<dt>working-tree</dt><dd>" + vstate(ch.get("working_tree"))
          + ' <span class="src-why">advisory</span></dd>'
          + "<dt>@HEAD</dt><dd>" + vstate(ch.get("head"))
          + ' <span class="src-why">authoritative</span></dd>'
          + f"<dt>links</dt><dd>{links}</dd>"
          + "<dt>co-index gate</dt><dd>" + ci_html + "</dd>")
    return ('<div class="card card-pad">' + head
            + f'<dl class="kv">{kv}</dl></div>')


def _commits(g):
    if g.get("status") != "ok":
        inner = '<p class="cardnote">unavailable — not in a git repo</p>'
    else:
        inner = ('<div class="commits">'
                 + "<br>".join(esc(l) for l in g["lines"]) + "</div>")
    return ('<section><div class="eyebrow">operator commits</div>'
            '<div class="card card-pad">' + inner + "</div></section>")


def _sources(ctx):
    """The D6 source map: degradation is shown, never silent. Grey is
    the honest color for "read fine" -- green is reserved for states a
    verification actually passed."""
    ch, ci, t = ctx["chain"], ctx["co_index"], ctx["tamper"]
    s, g, h = ctx["slice"], ctx["git"], ctx["halt"]
    items = [("index", "grey",
              f"{ctx['index_count']} rows" if ctx["index_present"] else "absent"),
             ("loose", "grey", f"{ctx['loose_count']} receipts")]
    if not ch["path_exists"]:
        items.append(("chain", "grey", "absent"))
    elif ch.get("working_tree") == "INVALID" or ch.get("head") == "INVALID":
        items.append(("chain", "hot", "INVALID"))
    elif ch.get("head") == "VALID" or ch.get("working_tree") == "VALID":
        items.append(("chain", "green", "verified"))
    else:
        items.append(("chain", "grey", "present"))
    ci_st = ci.get("status")
    items.append(("co-index",
                  {"VALID": "green", "DRIFT": "amber"}.get(ci_st, "grey"),
                  ci_st or "unavailable"))
    sst = s.get("status")
    items.append(("next-slice", "amber" if sst == "unlocked" else "grey", sst))
    items.append(("git-log", "grey", g.get("status")))
    hst = h.get("status")
    items.append(("halt", "hot" if hst == "engaged" else "grey", hst))
    tst = t.get("status")
    items.append(("enforced-tree",
                  {"ok": "green", "diverges": "hot"}.get(tst, "grey"), tst))
    spans = "".join(
        f'<div class="src"><span class="src-name">{esc(name)}</span>'
        + _state(color, str(word)) + "</div>"
        for name, color, word in items)
    # The tamper detail is NOT rendered: detect_tamper.sh's message
    # carries the absolute ENFORCED path, and the board must never
    # embed an absolute local path. The status word is the signal.
    return ('<section><div class="eyebrow">enforced tree · source map</div>'
            '<div class="card card-pad">'
            '<div class="srcmap">' + spans + "</div></div></section>")


def render_dashboard(ctx):
    parts = ["<!doctype html>", '<meta charset="utf-8">',
             '<meta name="color-scheme" content="dark">',
             '<meta name="viewport" content="width=device-width,initial-scale=1">',
             "<title>harness mission control</title>",
             "<style>" + _CSS + "</style>"]
    h = ctx["halt"]
    if h.get("status") == "engaged":
        mtime = h.get("mtime")
        since = (datetime.fromtimestamp(mtime, timezone.utc)
                 .strftime("%Y-%m-%d %H:%M UTC") if mtime else "unknown time")
        parts.append('<div class="halt-banner">■ HALT — operator kill-switch '
                     "engaged · .harness/HALT · since " + esc(since) + "</div>")
    parts.append('<div class="wrap">')
    parts.append("<header><h1>HARNESS MISSION CONTROL</h1>"
                 + f'<div class="prov">{esc(ctx["rdir_display"])} · '
                 + f'generated {esc(ctx["generated_utc"])}</div></header>')
    parts.append(_rail(ctx))
    parts.append(_kpis(ctx))
    parts.append(_ledger(ctx))
    parts.append('<section><div class="cols">' + _slice_card(ctx["slice"])
                 + _chain_card(ctx) + "</div></section>")
    parts.append(_commits(ctx["git"]))
    parts.append(_sources(ctx))
    parts.append("</div>")
    return "\n".join(parts)


def main():
    rdir = sys.argv[1] if len(sys.argv) > 1 else "./.harness/receipts"
    odir = sys.argv[2] if len(sys.argv) > 2 else rdir
    ctx = collect(rdir)
    open(os.path.join(odir, "stats.md"), "w").write(render_stats_md(ctx))
    open(os.path.join(odir, "dashboard.html"), "w").write(render_dashboard(ctx))
    print("wrote", os.path.join(odir, "stats.md"), "and dashboard.html")

if __name__ == "__main__":
    main()
