/* Light/dark theme. Load in <head> (no defer) so the theme is set before first paint.
   Any <button data-theme-toggle> becomes the toggle. A button with no child elements gets a text label;
   a button that contains icons (see .sun / .moon in theme.css) keeps them and only gets an aria-label.
   The choice is remembered per browser. */
(function () {
  var root = document.documentElement;
  try { var saved = localStorage['site-theme']; } catch (e) {}
  root.dataset.theme = saved || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  document.addEventListener("DOMContentLoaded", function () {
    var buttons = document.querySelectorAll("[data-theme-toggle]");
    function sync() {
      var dark = root.dataset.theme === "dark";
      buttons.forEach(function (b) {
        b.setAttribute("aria-label", dark ? "Switch to light mode" : "Switch to dark mode");
        b.title = b.getAttribute("aria-label");
        if (!b.firstElementChild) b.textContent = dark ? "☀ Light" : "☾ Dark";
      });
    }
    buttons.forEach(function (b) {
      b.addEventListener("click", function () {
        root.dataset.theme = root.dataset.theme === "dark" ? "light" : "dark";
        try { localStorage['site-theme'] = root.dataset.theme; } catch (e) {}
        sync();
      });
    });
    sync();
  });
})();
