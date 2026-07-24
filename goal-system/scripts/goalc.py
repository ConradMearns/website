#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyyaml>=6", "rich>=13"]
# ///
"""goalc — structure is a fold.

The graph is compiled from indications.jsonl (machine-appended claims) and
approvals.jsonl (human-appended verdicts). Two views: optimistic (all but
rejected) and strict (approved only). This tool appends to approvals.jsonl
(approve/reject) and runs.jsonl (check); it edits nothing, ever.
"""
import json, re, subprocess, sys, datetime as dt
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IND, APPR = ROOT / "indications.jsonl", ROOT / "approvals.jsonl"
RUNS, GAPS = ROOT / "runs.jsonl", ROOT / "gaps.jsonl"
VIEWS = ROOT / "views"
GLYPH = {"pass": "✓", "fail": "✗", "stale": "◌", "none": "?", "pending": "…"}
STYLE = {"pass": "green", "fail": "bold red", "stale": "yellow", "none": "magenta"}
NODE_KINDS = ("goal", "strategy", "solution", "subject")
ATTR_KINDS = ("mode", "grade", "fundamental")

def now(): return dt.datetime.now(dt.timezone.utc)

def parse_dur(s):
    n, u = int(s[:-1]), s[-1]
    return dt.timedelta(**{{"h": "hours", "m": "minutes", "d": "days"}[u]: n})

def jsonl(p):
    return [json.loads(l) for l in p.read_text().splitlines() if l.strip()] if p.exists() else []

def verdicts():
    v = {}
    for a in jsonl(APPR):                      # append-only ⇒ latest wins
        v[a["indication"]] = a["verdict"]
    return v

def spans_of(i):
    return i.get("spans") or ([i["span"]] if i.get("span") else [])

def compile_view(view="optimistic"):
    """Fold the two logs into a graph. Later indications win on scalar fields."""
    v = verdicts()
    if view == "optimistic":
        keep = lambda i: v.get(i["id"]) != "rejected"
    else:
        keep = lambda i: v.get(i["id"]) == "approved"
    inds = [i for i in jsonl(IND) if keep(i)]
    nodes, relates = {}, []
    for i in inds:                             # pass 1: nodes
        if i["kind"] in NODE_KINDS:
            n = nodes.setdefault(i["node"], {"id": i["node"], "supported_by": [], "spans": []})
            n["type"] = i["kind"]
            for k in ("text", "name", "aliases", "subject", "recipe", "uri",
                      "ttl", "window", "check", "reviewed_by", "reviewed_at"):
                if k in i: n[k] = i[k]
            n["spans"] += spans_of(i)
            n["pending"] = v.get(i["id"]) != "approved"
    for i in inds:                             # pass 2: attrs + edges (skip dangling)
        k = i["kind"]
        if k in ATTR_KINDS and i["node"] in nodes:
            nodes[i["node"]][k] = i.get(k, True)
        elif k == "supports" and i["node"] in nodes and i["child"] in nodes:
            if i["child"] not in nodes[i["node"]]["supported_by"]:
                nodes[i["node"]]["supported_by"].append(i["child"])
        elif k == "relates" and i["node"] in nodes and i.get("to") in nodes:
            relates.append({"frm": i["node"], "to": i["to"], "effect": i["effect"],
                            "pending": v.get(i["id"]) != "approved"})
    return {"nodes": nodes, "relates": relates}

def run_history():
    hist = {}
    for r in jsonl(RUNS):
        hist.setdefault(r["solution_id"], []).append(r)
    return hist

def sol_status(sol, hist, mode=None):
    """Rule 7. maintain/avoid: every run in window passed (avoid = anti-maintain,
    a failed run means a violation was observed). achieve: one pass, sticky.
    No window → latest run + TTL (MVP fold)."""
    runs = hist.get(sol["id"], [])
    if mode == "achieve":
        return "pass" if any(r["status"] == "passed" for r in runs) else \
               ("fail" if runs else "none")
    if not runs: return "none"
    if sol.get("window"):
        cutoff = now() - parse_dur(sol["window"])
        scope = [r for r in runs if dt.datetime.fromisoformat(r["finished_at"]) >= cutoff]
        if not scope: return "none"            # absence of looking ≠ absence of violation
    else:
        scope = runs[-1:]
    latest = dt.datetime.fromisoformat(scope[-1]["finished_at"])
    if now() - latest > parse_dur(sol.get("ttl", "24h")): return "stale"
    return "pass" if all(r["status"] == "passed" for r in scope) else "fail"

def fold(nid, nodes, hist, mode=None, path=frozenset()):
    n = nodes[nid]
    if n["type"] == "solution":
        return sol_status(n, hist, mode)
    m = n.get("mode") if n["type"] == "goal" else mode
    # cycle-tolerant: a back-edge contributes nothing — circular support is
    # not evidence (it folds to "none" unless the loop has an external anchor)
    kids = [fold(c, nodes, hist, m, path | {nid})
            for c in n["supported_by"] if c not in path and c != nid]
    if not kids: return "none"
    if m == "achieve" and "pass" in kids: return "pass"   # sticky: one path suffices
    for w in ("fail", "stale", "none"):
        if w in kids: return w
    return "pass"

def roots(nodes):
    referenced = {c for n in nodes.values() for c in n["supported_by"]}
    return [i for i, n in nodes.items()
            if n["type"] in ("goal", "strategy") and i not in referenced]

def load_gaps(nodes):
    open_gaps = {}
    for e in jsonl(GAPS):
        if e["event"] == "raised": open_gaps[e["gap_id"]] = e
        elif e["event"] == "resolved": open_gaps.pop(e["gap_id"], None)
    anchored = {e.get("anchor") for e in open_gaps.values()}
    derived = [{"gap_id": f"derived:{i}", "kind": "missing_solution", "anchor": i,
                "derived": True,
                "question": f"{i} has no strategy or solution — what would evidence it?"}
               for i, n in nodes.items()
               if n["type"] == "goal" and not n["supported_by"] and i not in anchored]
    for loop in support_cycles(nodes):         # cycles are information, not errors
        anchor = loop[0]
        if anchor not in anchored:
            derived.append({"gap_id": f"derived:cycle:{anchor}", "kind": "cycle",
                            "anchor": anchor, "derived": True,
                            "question": f"support cycle {' -> '.join(loop + [loop[0]])}: "
                                        "one goal wearing several names (adjudicate: same?), "
                                        "a dynamic worth naming as its own node, or circular "
                                        "justification needing an external anchor?"})
    return list(open_gaps.values()) + derived

def support_cycles(nodes):
    """Distinct cycles in the supports relation, each as a node list."""
    cycles, done = [], set()
    def dfs(i, path):
        if i in path:
            loop = tuple(path[path.index(i):])
            key = frozenset(loop)
            if key not in done:
                done.add(key); cycles.append(list(loop))
            return
        for c in nodes.get(i, {}).get("supported_by") or []:
            if c in nodes: dfs(c, path + [i])
    for i in nodes: dfs(i, [])
    return cycles

def select(filt, graph):
    nodes = graph["nodes"]
    f = filt.lower()
    subj = next((i for i, n in nodes.items() if n["type"] == "subject"
                 and (f == i.lower() or f == n.get("name", "").lower()
                      or f in [a.lower() for a in n.get("aliases") or []])), None)
    if subj:
        sel = [i for i, n in nodes.items() if n.get("subject") == subj]
    elif filt in nodes:
        sel = [filt]
    else:
        subs = ", ".join(i for i, n in nodes.items() if n["type"] == "subject")
        sys.exit(f"no subject or node '{filt}' (subjects: {subs})")
    def desc(i, acc):
        for c in nodes[i]["supported_by"]:
            if c not in acc: acc.add(c); desc(c, acc)
        return acc
    return [i for i in sel if not any(i in desc(j, set()) for j in sel if j != i)]

def tree(filt=None, view="optimistic"):
    from rich.console import Console
    from rich.text import Text
    from rich.tree import Tree
    graph, hist = compile_view(view), run_history()
    nodes = graph["nodes"]
    gaps = {x["anchor"]: x for x in load_gaps(nodes) if x.get("anchor")}
    rel_from = {}
    for r in graph["relates"]:
        rel_from.setdefault(r["frm"], []).append(r)
    def label(nid):
        n = nodes[nid]; st = fold(nid, nodes, hist)
        t = Text()
        t.append(GLYPH["pending" if n.get("pending") else st] + " ",
                 style="grey50" if n.get("pending") else STYLE[st])
        t.append(n.get("text", nid), style="grey50 italic" if n.get("pending") else "")
        if n.get("fundamental"): t.append("  ★ fundamental", style="bold cyan")
        tags = []
        if n.get("pending"): tags.append("pending")
        if nid in gaps: tags.append(f"gap: {gaps[nid]['kind']}")
        if n["type"] == "solution": tags.append(n.get("recipe", n.get("uri", "")))
        if tags: t.append(f"  [{' · '.join(x for x in tags if x)}]", style="dim")
        for r in rel_from.get(nid, []):
            color = "green" if r["effect"] == "helps" else "red"
            t.append(f"  ⇄ {r['effect']} {r['to']}", style=f"dim {color}")
        return t
    def add(branch, nid):
        node = branch.add(label(nid))
        for c in nodes[nid]["supported_by"]:
            add(node, c)
    root = Tree("goals", hide_root=True)
    for r in (select(filt, graph) if filt else roots(nodes)):
        add(root, r)
    Console().print(root)

def pending_cmd():
    v = verdicts()
    rows = [i for i in jsonl(IND) if i["id"] not in v]
    for i in rows:
        extra = i.get("text") or i.get("name") or i.get("recipe") or ""
        edge = f" -> {i['child']}" if i["kind"] == "supports" else \
               f" -> {i.get('to')} ({i.get('effect')})" if i["kind"] == "relates" else ""
        attr = f" = {i.get(i['kind'])}" if i["kind"] in ATTR_KINDS and i["kind"] in i else ""
        print(f"{i['id']}  {i['kind']:10s} {i['node']}{edge}{attr}  {extra}")
    if not rows: print("nothing pending")

def approve(ids, verdict):
    known = {i["id"] for i in jsonl(IND)}
    bad = [x for x in ids if x not in known]
    if bad: sys.exit(f"unknown indication(s): {', '.join(bad)}")
    with APPR.open("a") as f:
        for x in ids:
            f.write(json.dumps({"indication": x, "verdict": verdict,
                                "at": now().isoformat(), "by": "conrad"}) + "\n")
    print(f"{verdict}: {' '.join(ids)}")

def lint():
    errs = []
    inds, v = jsonl(IND), verdicts()
    ids = set()
    for i in inds:                             # warrant is literal (rule 3)
        if i["id"] in ids: errs.append(f"{i['id']}: duplicate indication id")
        ids.add(i["id"])
        for s in spans_of(i):
            if not s.get("quote") or not s.get("source"):
                errs.append(f"{i['id']}: span missing quote/source"); continue
            src = ROOT / s["source"]
            if not src.exists():
                errs.append(f"{i['id']}: source {s['source']} does not exist"); continue
            # normalize whitespace and markdown blockquote markers
            norm = lambda t: re.sub(r"\s+", " ", re.sub(r"^\s*>+ ?", " ", t, flags=re.M)).strip()
            if norm(s["quote"]) not in norm(src.read_text()):
                errs.append(f"{i['id']}: quote not found in {s['source']} — hallucinated warrant?")
    for i in inds:
        if v.get(i["id"]) == "approved" and i["kind"] == "goal" and not spans_of(i):
            errs.append(f"{i['id']}: approved goal without a span (record, not infer)")
    strict = compile_view("strict")["nodes"]
    for nid, n in strict.items():              # determinism gradient on the strict view
        kids = n["supported_by"]
        if n["type"] == "goal" and kids and all(strict[c]["type"] == "solution" for c in kids):
            if n.get("grade") not in ("deterministic", "judgment"):
                errs.append(f"{nid}: approved leaf grade '{n.get('grade')}' — leaves must be deterministic (or judgment+review)")
        if n["type"] == "goal":
            for c in kids:
                if strict[c]["type"] == "goal":
                    errs.append(f"{nid}: goal→goal edge to {c} (decompose via a strategy)")
        if n["type"] == "strategy" and not n.get("reviewed_by"):
            errs.append(f"{nid}: approved strategy without sign-off (who carries the inferential debt?)")
    for e in errs: print("LINT:", e)
    return 1 if errs else 0

def check(only=None):
    graph, hist = compile_view("optimistic"), run_history()
    nodes = graph["nodes"]
    graph_sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                               capture_output=True, text=True).stdout.strip() or "nogit"
    for nid, n in nodes.items():
        if n["type"] != "solution" or n.get("check") != "check": continue
        if only and nid != only: continue
        if not only and sol_status(n, hist) == "pass": continue
        started = now().isoformat()
        p = subprocess.run(n["recipe"].split(), cwd=ROOT, capture_output=True, text=True)
        run = {"solution_id": nid, "started_at": started, "finished_at": now().isoformat(),
               "status": "passed" if p.returncode == 0 else "failed",
               "graph_sha": graph_sha, "subject_sha": None}
        with RUNS.open("a") as f: f.write(json.dumps(run) + "\n")
        print(f"{GLYPH['pass' if p.returncode == 0 else 'fail']} {nid}"
              + ("" if p.returncode == 0 else f"\n{p.stdout}{p.stderr}"))

def gaps_cmd():
    nodes = compile_view("optimistic")["nodes"]
    out = load_gaps(nodes)
    for gp in out:
        src = "derived" if gp.get("derived") else "authored"
        print(f"? [{src} · {gp['kind']} · anchor: {gp.get('anchor')}] {gp['question']}")
    if not out: print("no open gaps")

def build():
    import yaml
    VIEWS.mkdir(exist_ok=True)
    for view in ("optimistic", "approved"):
        g = compile_view("strict" if view == "approved" else view)
        out = {"view": view, "built_at": now().isoformat(),
               "nodes": {i: {k: val for k, val in n.items() if k != "pending"}
                         for i, n in sorted(g["nodes"].items())},
               "relates": g["relates"]}
        p = VIEWS / f"goals.{view}.yaml"
        p.write_text(yaml.safe_dump(out, sort_keys=False, allow_unicode=True))
        print(f"wrote {p.relative_to(ROOT)} ({len(g['nodes'])} nodes)")

def evidence(which):
    """Self-hosting leaves: exit 0 = pass."""
    inds, v, hist = jsonl(IND), verdicts(), run_history()
    if which == "provenance":                  # approved goals carry spans
        bad = [i["id"] for i in inds if v.get(i["id"]) == "approved"
               and i["kind"] == "goal" and not spans_of(i)]
    elif which == "grades":
        strict = compile_view("strict")["nodes"]
        bad = [nid for nid, n in strict.items()
               if n["type"] == "goal" and n["supported_by"]
               and all(strict[c]["type"] == "solution" for c in n["supported_by"])
               and n.get("grade") not in ("deterministic", "judgment")]
    elif which == "staleness":
        strict = compile_view("strict")["nodes"]
        bad = [nid for nid, n in strict.items() if n["type"] == "solution"
               and n.get("check") == "check" and sol_status(n, hist) == "stale"]
    elif which == "orphan-failures":
        bad = []                               # vacuous until .seeds/ exists
    else:
        sys.exit(f"unknown evidence target: {which}")
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "tree"
    args = sys.argv[2:]
    if cmd == "tree":
        view = "strict" if "--strict" in args else "optimistic"
        filt = next((a for a in args if not a.startswith("--")), None)
        tree(filt, view)
    elif cmd == "lint": sys.exit(lint())
    elif cmd == "check": check(args[0] if args else None)
    elif cmd == "gaps": gaps_cmd()
    elif cmd == "pending": pending_cmd()
    elif cmd == "approve": approve(args, "approved")
    elif cmd == "reject": approve(args, "rejected")
    elif cmd == "build": build()
    elif cmd == "evidence": evidence(args[0])
    else: sys.exit("usage: goalc.py [tree [FILTER] [--strict]|lint|check [SOL]|gaps|pending|approve I...|reject I...|build|evidence T]")
