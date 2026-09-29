/* Webring Zero: the member list, and everything that uses it, in one file.
   Another ring would be its own pair of files (abc.js + abc.html) next to this one.

   TO JOIN OR EDIT THE RING: add or remove a member in the list just below. Nothing else needs to change.

   USE ON YOUR SITE (draws  <- previous | Webring Zero | next ->  right where you put it):
     <script src="https://conrads.website/webring/wrz.js" data-from="https://yoursite.example/"></script>
   data-from is your site's address as listed below. The links are a plain <nav class="webring"> in your text color.

   ON THE RING PAGE (no data-from): fills <table data-ring-table="wrz"> with the members, and exposes window.WEBRINGS.wrz. */
(function () {
  /* ---------- the members: keep this list in the order of the ring ---------- */
  var ring = {
    id: "WRZ",
    name: "Webring Zero",
    home: "https://conrads.website/webring/#wrz",
    members: [
      { name: "Conrad Mearns", url: "https://conrads.website/", blurb: "Tools for agents and event-driven systems. The ring's keeper.", peek: "peek/webring-conrad.jpg" },
      { name: "overgrown", url: "https://overgrown.kerp.zone/", blurb: "Thoughts, mostly unweeded.", peek: "peek/webring-overgrown.jpg" },
      { name: "The Horenberger Zone", url: "https://horenbergerb.github.io/caravan.html", blurb: "Caravan, an LLM-generated world you can explore.", peek: "peek/webring-horenberger.jpg" }
    ]
  };
  /* ---------- end of the list ---------- */

  var script = document.currentScript, base = script.src.replace(/[^/]*$/, "");

  function host(u) { try { return new URL(u).host.replace(/^www\./, ""); } catch (e) { return ""; } }
  function indexOf(url) { return ring.members.findIndex(function (m) { return host(m.url) === host(url); }); }

  /* where a hop from `url` goes: to = "prev" | "next" | "random". null if `url` isn't in the ring. */
  function hop(url, to) {
    var list = ring.members, i = indexOf(url), n = list.length;
    if (i < 0 || n < 2) return null;
    if (to === "prev") return list[(i - 1 + n) % n];
    if (to === "random") { var j; do { j = Math.floor(Math.random() * n); } while (j === i); return list[j]; }
    return list[(i + 1) % n];
  }

  function link(text, href, title) { var a = document.createElement("a"); a.textContent = text; a.href = href; if (title) a.title = title; return a; }
  function peekOf(m) { return m.peek ? new URL("../" + m.peek, base).href : ""; }

  /* the  <- previous | ring | next ->  bar for the site at `from`. opts.peek adds hover previews (needs js/peek.js on the page) */
  function nav(from, opts) {
    var el = document.createElement("nav"), prev = hop(from, "prev"), next = hop(from, "next");
    el.className = "webring"; el.setAttribute("aria-label", ring.name);
    el.style.cssText = "display:flex;flex-wrap:wrap;gap:.4em 1.2em;align-items:center";
    var home = link(ring.name, ring.home);
    if (!prev) { el.append(home); return el; }
    var a = link("← " + prev.name, prev.url, "Previous: " + prev.name), b = link(next.name + " →", next.url, "Next: " + next.name);
    if (opts && opts.peek) { if (prev.peek) a.dataset.peek = peekOf(prev); if (next.peek) b.dataset.peek = peekOf(next); }
    el.append(a, home, b, link("random", base + ring.id.toLowerCase() + ".html?to=random&from=" + encodeURIComponent(from), "A random member"));
    el.lastChild.setAttribute("data-nopeek", "");
    return el;
  }

  (window.WEBRINGS = window.WEBRINGS || {})[ring.id.toLowerCase()] = { ring: ring, hop: hop, nav: nav, indexOf: indexOf, base: base, peekOf: peekOf };

  if (script.dataset.from) script.after(nav(script.dataset.from));

  /* a table of the members: name (right), about (left) */
  document.querySelectorAll('[data-ring-table="' + ring.id.toLowerCase() + '"]').forEach(function (table) {
    var head = table.createTHead().insertRow();
    ["Member", "About"].forEach(function (t) { head.append(Object.assign(document.createElement("th"), { textContent: t })); });
    var body = table.createTBody();
    ring.members.forEach(function (m) {
      var row = body.insertRow(), name = row.insertCell(), about = row.insertCell();
      var a = link(m.name, m.url); a.rel = "noopener"; if (m.peek) a.dataset.peek = peekOf(m);
      name.append(a); about.textContent = m.blurb;
    });
  });
})();
