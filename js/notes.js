/* Annotated vibechecks: scroll-driven frame. the last note whose top has risen past 60% of the window decides what the frame shows.
   only the src changes, and a change to just the #fragment does not reload the page: it fires a
   hashchange inside it. That works for any page, also from file:// (where reaching into the frame would not). */
(function () {
    var frame = document.querySelector(".screen iframe"), screen = frame.parentNode, label = document.getElementById("label"), open = document.getElementById("open");
    var steps = Array.prototype.slice.call(document.querySelectorAll(".notes [data-view]")), current, timer, queued;

    function show(step) {
        if (step === current) return;
        current = step;
        steps.forEach(function (s) { s === step ? s.setAttribute("aria-current", "step") : s.removeAttribute("aria-current"); });
        label.textContent = step.dataset.label || "";
        if (open) open.href = step.dataset.view.split("#")[0];
        clearTimeout(timer);
        timer = setTimeout(function () {
            if (frame.getAttribute("src") !== step.dataset.view) frame.setAttribute("src", step.dataset.view);
        }, 150);   /* a fast scroll passes many steps: only the one you land on loads */
    }
    function update() {
        queued = false;
        var line = innerHeight * 0.6, pick = steps[0];
        steps.forEach(function (s) { if (s.getBoundingClientRect().top < line) pick = s; });
        show(pick);
    }
    function onScroll() { if (!queued) { queued = true; requestAnimationFrame(update); } }

    /* small screens: give the page its designed width and shrink it to fit, instead of squeezing it */
    function fit() {
        var design = +frame.dataset.width, w = screen.clientWidth;
        if (design && w < design) {
            var k = w / design;
            frame.style.cssText = "width:" + design + "px;height:" + screen.clientHeight / k + "px;transform:scale(" + k + ")";
        } else frame.removeAttribute("style");
    }

    steps.forEach(function (s) { s.addEventListener("click", function () { show(s); }); });
    addEventListener("scroll", onScroll, { passive: true });
    addEventListener("resize", function () { fit(); onScroll(); });
    fit(); update();
})();
