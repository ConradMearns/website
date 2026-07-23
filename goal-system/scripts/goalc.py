#!/usr/bin/env python3
"""goalc — tree / lint / check over goals.yaml + runs.jsonl. Append-only; never edits goals.yaml."""
import json, subprocess, sys, datetime as dt
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("goalc needs pyyaml — run via `uv run scripts/goalc.py` (or `just tree`)")

ROOT = Path(__file__).resolve().parent.parent
GOALS, RUNS, GAPS = ROOT / "goals.yaml", ROOT / "runs.jsonl", ROOT / "gaps.jsonl"
GLYPH = {"pass": "✓", "fail": "✗", "stale": "◌", "none": "?", "candidate": "…"}
GRADES = ["deterministic", "statistical", "heuristic", "judgment"]

def now(): return dt.datetime.now(dt.timezone.utc)

def parse_ttl(s):
    n, u = int(s[:-1]), s[-1]
    return dt.timedelta(**{{"h": "hours", "m": "minutes", "d": "days"}[u]: n})

def load():
    g = yaml.safe_load(GOALS.read_text())
    runs = [json.loads(l) for l in RUNS.read_text().splitlines() if l.strip()] if RUNS.exists() else []
    latest = {}
    for r in runs:                      # append-only ⇒ last line per solution wins
        latest[r["solution_id"]] = r
    idx = {n["id"]: n for k in ("goals", "strategies", "solutions") for n in g.get(k) or []}
    return g, idx, latest

def load_gaps(idx):
    """Fold gaps.jsonl (latest event per gap_id wins) + derive structural gaps.

    Authored gaps are events: raised opens, resolved closes. Derived gaps are
    computed from structure — a goal with no support is a missing_solution —
    and are never stored. An open authored gap on a node suppresses the
    derived one (the question is more specific than the detection)."""
    open_gaps = {}
    if GAPS.exists():
        for line in GAPS.read_text().splitlines():
            if not line.strip(): continue
            e = json.loads(line)
            if e["event"] == "raised": open_gaps[e["gap_id"]] = e
            elif e["event"] == "resolved": open_gaps.pop(e["gap_id"], None)
    anchored = {e.get("anchor") for e in open_gaps.values()}
    derived = [{"gap_id": f"derived:{n['id']}", "kind": "missing_solution",
                "anchor": n["id"], "derived": True,
                "question": f"{n['id']} has no strategy or solution — what would evidence it?"}
               for n in idx.values()
               if "kind" not in n and "reviewed_by" not in n
               and not n.get("supported_by") and n["id"] not in anchored]
    return list(open_gaps.values()) + derived

def sol_status(sol, latest):
    r = latest.get(sol["id"])
    if not r: return "none"
    if now() - dt.datetime.fromisoformat(r["finished_at"]) > parse_ttl(sol.get("ttl", "24h")):
        return "stale"
    return "pass" if r["status"] == "passed" else "fail"

def fold(nid, idx, latest):
    n = idx[nid]
    if "kind" in n:                     # solution
        return sol_status(n, latest)
    kids = [fold(c, idx, latest) for c in n.get("supported_by") or []]
    if not kids: return "none"
    for w in ("fail", "stale", "none"):  # worst-of
        if w in kids: return w
    return "pass"

def roots(g, idx):
    referenced = {c for n in idx.values() for c in n.get("supported_by") or []}
    return [n["id"] for n in g.get("goals") or [] if n["id"] not in referenced]

def tree():
    g, idx, latest = load()
    gaps = {x["anchor"]: x for x in load_gaps(idx) if x.get("anchor")}
    def line(nid, prefix, last):
        n = idx[nid]; st = fold(nid, idx, latest)
        gl = GLYPH["candidate"] if n.get("status") == "candidate" else GLYPH[st]
        tags = []
        if n.get("status") == "candidate": tags.append("candidate")
        if nid in gaps: tags.append(f"gap: {gaps[nid]['kind']}")
        if "kind" in n: tags.append(n.get("recipe", n.get("uri", "")))
        branch = "" if prefix is None else ("└── " if last else "├── ")
        print(f"{prefix or ''}{branch}{gl} {n.get('text', nid)}"
              + (f"   [{' · '.join(t for t in tags if t)}]" if tags else ""))
        kids = n.get("supported_by") or []
        for i, c in enumerate(kids):
            ext = "" if prefix is None else (prefix + ("    " if last else "│   "))
            line(c, ext, i == len(kids) - 1)
    for r in roots(g, idx):
        line(r, None, True)
    for gp in load_gaps(idx):
        if gp.get("anchor") not in idx:
            print(f"? (unanchored gap {gp['gap_id']}) {gp['question']}")

def gaps_cmd():
    g, idx, _ = load()
    out = load_gaps(idx)
    for gp in out:
        src = "derived" if gp.get("derived") else "authored"
        print(f"? [{src} · {gp['kind']} · anchor: {gp.get('anchor')}] {gp['question']}")
    if not out: print("no open gaps")

def lint():
    g, idx, _ = load()
    errs = []
    if g.get("gaps"):
        errs.append("goals.yaml contains a 'gaps' block — gaps are events (gaps.jsonl) or derived, never structure")
    for n in g.get("goals") or []:
        if n.get("status") == "confirmed" and not n.get("derived_from"):
            errs.append(f"{n['id']}: confirmed without derived_from (record, not infer)")
        for d in n.get("derived_from") or []:
            if not d.get("quote") or not d.get("source"):
                errs.append(f"{n['id']}: span missing quote/source")
        kids = n.get("supported_by") or []
        for c in kids:
            if c not in idx: errs.append(f"{n['id']}: dangling edge → {c}")
        if kids and all(idx.get(c, {}).get("kind") is None and "reviewed_by" not in idx.get(c, {}) for c in kids):
            pass  # goal→goal edges allowed only via strategies:
        for c in kids:
            k = idx.get(c, {})
            if "kind" not in k and "supported_by" in k and "reviewed_by" not in k and k in (g.get("goals") or []):
                errs.append(f"{n['id']}: goal→goal edge to {c} (decompose via a strategy)")
        # determinism gradient: leaves (no children or only-solution children)
        if not kids and n.get("status") == "confirmed":
            errs.append(f"{n['id']}: confirmed leaf with no solution (gap it or evidence it)")
        if kids and all("kind" in idx.get(c, {}) for c in kids):
            if n.get("grade") not in ("deterministic", "judgment"):
                errs.append(f"{n['id']}: leaf grade '{n.get('grade')}' — leaves must be deterministic (or judgment+review)")
    for s in g.get("strategies") or []:
        if s.get("status") == "confirmed" and not s.get("reviewed_by"):
            errs.append(f"{s['id']}: confirmed strategy without sign-off (who carries the inferential debt?)")
    for e in errs: print("LINT:", e)
    return 1 if errs else 0

def check(only=None):
    g, idx, latest = load()
    graph_sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                               capture_output=True, text=True).stdout.strip() or "nogit"
    for sol in g.get("solutions") or []:
        if sol.get("kind") != "check": continue
        if only and sol["id"] != only: continue
        if not only and sol_status(sol, latest) == "pass": continue   # only due work
        started = now().isoformat()
        p = subprocess.run(sol["recipe"].split(), cwd=ROOT, capture_output=True, text=True)
        run = {"solution_id": sol["id"], "started_at": started, "finished_at": now().isoformat(),
               "status": "passed" if p.returncode == 0 else "failed",
               "graph_sha": graph_sha, "subject_sha": None}
        with RUNS.open("a") as f: f.write(json.dumps(run) + "\n")
        print(f"{GLYPH['pass' if p.returncode == 0 else 'fail']} {sol['id']}"
              + ("" if p.returncode == 0 else f"\n{p.stdout}{p.stderr}"))

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "tree"
    if cmd == "tree": tree()
    elif cmd == "lint": sys.exit(lint())
    elif cmd == "check": check(sys.argv[2] if len(sys.argv) > 2 else None)
    elif cmd == "gaps": gaps_cmd()
    else: sys.exit(f"usage: goalc.py [tree|lint|check [solution-id]|gaps]")
