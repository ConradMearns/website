#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["markdown"]
# ///
"""Turn a markdown file into a post page in this folder's posts/ directory.

    ./md2post.py notes.md --title "My Post" --date 2026-01 [--tag draft] [--slug my-post]

The page is plain HTML in the site theme. After this it is the source: edit it by hand,
and add a row for it to index.html and the home page, and prev/next links to its neighbours, yourself. Local images are copied to posts/img/.
"""
import argparse, html, re, shutil
from pathlib import Path
import markdown

HERE = Path(__file__).parent
PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{title} — Without Objective — Conrad Mearns</title>
    <script src="../../js/theme.js"></script>
    <link rel="stylesheet" href="../../css/theme.css">
    <link rel="stylesheet" href="../../css/post.css">
</head>
<body>
    <header>
        <a href="../../index.html">conrads.website</a> /
        <a href="../index.html">without objective</a>
        <button type="button" data-theme-toggle aria-label="Toggle light and dark mode"></button>
    </header>

    <main>
        <article>
            <header>
                <h1>{title}</h1>
                <p><time>{date}</time>{tag}</p>
            </header>
{body}
        </article>
    </main>
</body>
</html>
"""

def convert(md_path, title, date, tag, slug):
    src = Path(md_path)
    text = src.read_text()
    text = re.sub(r"\[\[([^\]|]*\|)?([^\]]*)\]\]", lambda m: m.group(2).strip(), text)   # [[wikilinks]] -> their text
    body = markdown.markdown(text, extensions=["extra", "sane_lists"])
    body = re.sub(r"<(/?)h([1-4])>", lambda m: "<%sh%d>" % (m.group(1), min(int(m.group(2)) + 2, 6)), body)   # the title is the page's h1
    def img(m):
        name = Path(m.group(2).replace("&lt;", "").replace("&gt;", ""))
        local = src.parent / name
        if m.group(2).startswith(("http", "/")) or not local.exists():
            return m.group(0)
        (HERE / "posts" / "img").mkdir(parents=True, exist_ok=True)
        shutil.copy(local, HERE / "posts" / "img" / name.name.replace(" ", "-"))
        return m.group(1) + "img/" + name.name.replace(" ", "-") + m.group(3)
    body = re.sub(r'(<img [^>]*src=")([^"]+)(")', img, body)
    body = re.sub(r"<pre>[\s\S]*?</pre>|[^\n]+", lambda m: m.group(0) if m.group(0).startswith("<pre>") else "            " + m.group(0), body)   # indent, but not inside <pre>
    tagp = ' <span class="tag">%s</span>' % html.escape(tag) if tag else ""
    out = HERE / "posts" / (slug + ".html")
    out.parent.mkdir(exist_ok=True)
    out.write_text(PAGE.format(title=html.escape(title), date=date, tag=tagp, body=body))
    return out

if __name__ == "__main__":
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("md"); a.add_argument("--title", required=True); a.add_argument("--date", required=True)
    a.add_argument("--tag", default=""); a.add_argument("--slug")
    n = a.parse_args()
    print(convert(n.md, n.title, n.date, n.tag, n.slug or re.sub(r"[^a-z0-9]+", "-", n.title.lower()).strip("-")))
