// DIZZY explainer: the scene clock.
//
// A scene is one HTML file with <body data-duration="ms"> and a .stage of 1920x1080.
// All motion in a scene is CSS animation (or Web Animations). This script pauses every
// animation and drives them all from one clock, so a scene can be paused, scrubbed, and
// captured frame by frame. Nothing in a scene may use setTimeout, setInterval or
// requestAnimationFrame for motion.
//
// Standalone:  open the scene file. Space plays and pauses, arrows step 0.5s, click the bar to seek.
//              ?t=3000 opens paused at 3s. ?bare hides the bar.
// Embedded:    index.html loads the scene in an iframe and sends {type: play | pause | seek, t}.
// Capture:     window.__seek(ms) sets the clock; window.__duration is the length.

(function () {
  const W = 1920, H = 1080;
  const stage = document.querySelector('.stage');
  const duration = Number(document.body.dataset.duration || 8000);
  const params = new URLSearchParams(location.search);
  const embedded = window.parent !== window;

  function fit() {
    const s = Math.min(innerWidth / W, innerHeight / H);
    stage.style.transform = `translate(-50%, -50%) scale(${s})`;
  }
  addEventListener('resize', fit);
  fit();

  let t = Number(params.get('t') || 0);
  let playing = !embedded && !params.has('t');
  let last = null;
  let bar = null, fill = null, clock = null;

  // Keep every animation ever seen: one that has finished with fill `backwards` or `none`
  // drops out of document.getAnimations(), and would otherwise never be rewound on a seek back.
  const known = new Set();

  function apply() {
    for (const a of document.getAnimations()) known.add(a);
    for (const a of known) {
      if (a.playState !== 'paused') a.pause();
      a.currentTime = t;
    }
    if (fill) fill.style.width = (100 * t / duration) + '%';
    if (clock) clock.textContent = (t / 1000).toFixed(1) + ' / ' + (duration / 1000).toFixed(1) + 's';
  }

  function seek(ms) {
    t = Math.max(0, Math.min(duration, ms));
    apply();
  }

  function frame(now) {
    if (playing) {
      if (last !== null) t += now - last;
      last = now;
      if (t >= duration) {
        t = duration;
        playing = false;
        last = null;
        apply();
        if (embedded) parent.postMessage({ type: 'ended' }, '*');
      } else {
        apply();
        if (embedded) parent.postMessage({ type: 'time', t }, '*');
      }
    } else {
      last = null;
    }
    requestAnimationFrame(frame);
  }

  window.__seek = seek;
  window.__duration = duration;

  addEventListener('message', (e) => {
    const m = e.data || {};
    if (m.type === 'play') playing = true;
    if (m.type === 'pause') playing = false;
    if (m.type === 'seek') seek(m.t || 0);
  });

  if (!embedded && !params.has('bare')) {
    bar = document.createElement('div');
    bar.style.cssText = 'position:fixed;left:0;right:0;bottom:0;height:22px;background:rgba(24,32,43,.12);cursor:pointer;z-index:99';
    fill = document.createElement('div');
    fill.style.cssText = 'height:100%;width:0;background:rgba(24,32,43,.55)';
    clock = document.createElement('div');
    clock.style.cssText = 'position:fixed;right:10px;bottom:28px;font:13px monospace;color:#5d6876;z-index:99';
    bar.appendChild(fill);
    document.body.append(bar, clock);
    bar.addEventListener('click', (e) => seek(duration * e.clientX / innerWidth));
    addEventListener('keydown', (e) => {
      if (e.key === ' ') { if (!playing && t >= duration) t = 0; playing = !playing; e.preventDefault(); }
      if (e.key === 'ArrowRight') { playing = false; seek(t + 500); }
      if (e.key === 'ArrowLeft') { playing = false; seek(t - 500); }
      if (e.key === '0' || e.key === 'Home') seek(0);
    });
  }

  // Wait for fonts so text measures the same on every run, then start the clock.
  (document.fonts ? document.fonts.ready : Promise.resolve()).then(() => {
    apply();
    if (embedded) parent.postMessage({ type: 'ready', duration }, '*');
    requestAnimationFrame(frame);
  });
})();
