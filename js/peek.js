/* Hover preview: a tiny CRT that shows what a link points to. Needs css/peek.css.
   Shown for links to this site and *.github.io (framed live), and for any link with data-peek.
   data-peek="page-or-image": an image (png/jpg/webp/gif) or a page to frame, for targets that cannot be framed.
   Load at the end of <body>. Off on touch screens and narrow windows. */
(function () {
  var canPeek = matchMedia("(hover: hover) and (min-width: 42.01em)");
  if (!matchMedia("(hover: hover)").matches) return;
  var box = document.createElement("div"), cap = document.createElement("small"), screen = document.createElement("div"), cur, timer;
  box.id = "peek"; box.setAttribute("aria-hidden", "true"); box.append(cap, screen); document.body.append(box);
  function src(a) { return a.dataset.peek || a.href; }  /* data-peek: a page URL or an image, for links that cannot be framed */
  function ok(a) {
    var u = new URL(src(a), location.href);
    return /^https?:|^file:/.test(u.protocol) && (u.origin === location.origin || u.hostname.endsWith(".github.io")) && u.pathname !== location.pathname;
  }
  function show(a) {
    var f;
    if (/\.(png|jpe?g|webp|gif)$/i.test(src(a))) { f = document.createElement("img"); f.src = src(a); f.alt = ""; }
    else { f = document.createElement("iframe"); f.src = src(a); f.tabIndex = -1; f.setAttribute("sandbox", "allow-scripts allow-same-origin"); }
    screen.replaceChildren(f); box.classList.add("on");
  }
  function hide() {
    clearTimeout(timer); box.classList.remove("on");
    setTimeout(function () { if (!box.classList.contains("on")) screen.replaceChildren(); }, 250);
  }
  function move(e) {
    var w = box.offsetWidth, h = box.offsetHeight, x = e.clientX + 24, y = e.clientY + 20;
    if (x + w > innerWidth - 8) x = e.clientX - w - 24;
    if (y + h > innerHeight - 8) y = innerHeight - h - 8;
    box.style.left = Math.max(8, x) + "px"; box.style.top = Math.max(8, y) + "px";
  }
  document.addEventListener("mouseover", function (e) {
    var a = e.target.closest && e.target.closest("a[href]");
    if (a === cur) return;
    hide(); cur = a;
    if (a && canPeek.matches && ok(a)) { var u = new URL(a.href); cap.textContent = "▶ " + (u.origin === location.origin ? u.pathname.slice(1) : u.host + u.pathname); move(e); timer = setTimeout(show, 250, a); }
  });
  document.addEventListener("mousemove", function (e) { if (cur) move(e); });
})();
