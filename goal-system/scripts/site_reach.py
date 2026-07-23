#!/usr/bin/env python3
"""Evidence: every HTML page in the site is reachable from index.html.

Exit 0 iff no unreachable pages. Prints the crawl summary as the artifact.
Site root = parent of the goal-system directory.
"""
import re, sys, pathlib, urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
SKIP_PARTS = {".git", "node_modules", "goal-system"}

pages = {p.relative_to(ROOT).as_posix() for p in ROOT.rglob("*.html")
         if not SKIP_PARTS & set(p.parts)}

def links(page):
    txt = (ROOT / page).read_text(errors="ignore")
    out = set()
    for href in re.findall(r'href=["\']([^"\'#?]+)', txt):
        if href.startswith(("http", "mailto:", "//")):
            continue
        t = ((ROOT / page).parent / urllib.parse.unquote(href)).resolve()
        if t.is_dir():
            t = t / "index.html"
        try:
            rel = t.relative_to(ROOT).as_posix()
        except ValueError:
            continue
        if rel in pages:
            out.add(rel)
    return out

seen, frontier = {"index.html": 0}, ["index.html"]
while frontier:
    nxt = []
    for p in frontier:
        for l in links(p):
            if l not in seen:
                seen[l] = seen[p] + 1
                nxt.append(l)
    frontier = nxt

unreachable = sorted(pages - set(seen))
fanout = sum(1 for d in seen.values() if d == 1)
print(f"pages={len(pages)} reachable={len(seen)} unreachable={len(unreachable)} "
      f"index_fanout={fanout} max_depth={max(seen.values())}")
for u in unreachable:
    print("UNREACHABLE", u)
sys.exit(1 if unreachable else 0)
