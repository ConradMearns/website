// Builds hover-preview images. Usage: node make-peek.mjs [name ...]   (no names = build everything)
// Every image comes out as an 816x510 jpg, which is 2x the 408x255 screen of the #peek panel in index.html.
import { chromium } from 'playwright-core';
import { execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import { readFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync, statSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, extname, join, resolve, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const config = JSON.parse(readFileSync(join(here, 'peek.config.json'), 'utf8'));
const outDir = resolve(here, config.out);
const siteRoot = resolve(here, '../..');
const W = 816, H = 510, PORT = 8799;
const work = mkdtempSync(join(tmpdir(), 'peek-'));
mkdirSync(outDir, { recursive: true });

const sh = (cmd, args) => execFileSync(cmd, args, { stdio: 'pipe' });
const finish = (src, name, gravity = 'center') => sh('convert', [src, '-resize', `${W}x${H}^`, '-gravity', gravity, '-extent', `${W}x${H}`, '-quality', '82', join(outDir, `${name}.jpg`)]);

// Site-relative page URLs ("/vibechecks/nl.html") are served from the repo root, so local pages
// that fetch() their own data files work (they would not from file://).
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.woff2': 'font/woff2' };
const server = createServer((req, res) => {
  const p = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname));
  let f = join(siteRoot, p);
  if (!f.startsWith(siteRoot)) { res.writeHead(403).end(); return; }
  if (existsSync(f) && statSync(f).isDirectory()) f = join(f, 'index.html');
  if (!existsSync(f)) { res.writeHead(404).end(); return; }
  res.writeHead(200, { 'content-type': MIME[extname(f)] || 'application/octet-stream' }).end(readFileSync(f));
}).listen(PORT);

function chromePath() {
  if (process.env.CHROMIUM_PATH) return process.env.CHROMIUM_PATH;
  const base = join(homedir(), '.cache/ms-playwright');
  if (!existsSync(base)) return undefined;
  const dir = readdirSync(base).filter(d => d.startsWith('chromium-')).sort().pop();
  return dir && join(base, dir, 'chrome-linux64/chrome');
}
let browser;
async function shoot(url, file, wait) {
  browser ??= await chromium.launch({ executablePath: chromePath() });
  const pg = await browser.newPage({ viewport: { width: 1024, height: 640 } });  // same size the iframe preview renders at
  try { await pg.goto(url.startsWith('/') ? `http://localhost:${PORT}${url}` : url, { waitUntil: 'load', timeout: 20000 }); }
  catch (e) { console.warn('  slow or failed load, shooting anyway:', url); }
  await pg.waitForTimeout(wait);
  await pg.screenshot({ path: file });
  await pg.close();
}

const builders = {
  // one live page
  async page(name, o) { const f = join(work, `${name}.png`); await shoot(o.url, f, o.wait ?? 2500); finish(f, name); },
  // a grid of live pages (default 3 columns)
  async collage(name, o) {
    const cols = o.cols ?? 3, rows = Math.ceil(o.pages.length / cols), cw = Math.floor(W / cols), ch = Math.floor(H / rows), cells = [];
    for (const [i, url] of o.pages.entries()) {
      const raw = join(work, `${name}-${i}.png`), cell = join(work, `${name}-c${i}.png`);
      await shoot(url, raw, o.wait ?? 2500);
      sh('convert', [raw, '-resize', `${cw}x${ch}^`, '-gravity', 'center', '-extent', `${cw}x${ch}`, cell]);
      cells.push(cell);
    }
    const grid = join(work, `${name}-grid.png`);
    sh('montage', [...cells, '-tile', `${cols}x${rows}`, '-geometry', '+0+0', '-background', '#000', grid]);
    finish(grid, name);
  },
  // first pages of a PDF laid side by side, like an open paper
  async pdf(name, o) {
    const pdf = join(work, `${name}.pdf`);
    if (/^https?:/.test(o.src)) writeFileSync(pdf, Buffer.from(await (await fetch(o.src)).arrayBuffer()));
    else sh('cp', [resolve(siteRoot, o.src), pdf]);
    const [a, b] = (o.pages ?? '1-2').split('-').map(Number);
    sh('pdftoppm', ['-f', String(a), '-l', String(b ?? a), '-png', '-r', '80', pdf, join(work, name)]);
    const pages = readdirSync(work).filter(f => f.startsWith(`${name}-`) && f.endsWith('.png')).sort().map(f => join(work, f));
    const strip = join(work, `${name}-strip.png`);
    sh('convert', [...pages, '+append', '-resize', `x${H}`, '-background', 'white', '-gravity', 'west', '-extent', `${W}x${H}`, strip]);
    finish(strip, name);
  },
  // an existing picture (README screenshot etc.), center-cropped to the panel shape
  async image(name, o) {
    const f = join(work, `${name}.src`);
    writeFileSync(f, Buffer.from(await (await fetch(o.src)).arrayBuffer()));
    finish(f, name, o.gravity);   // o.gravity: which part to keep when cropping (north for the top of a tall page)
  },
};

const wanted = process.argv.slice(2), all = Object.keys(config.images);
const names = wanted.length ? wanted : all;
try {
  for (const n of names) {
    if (!config.images[n]) { console.error(`unknown image "${n}" (have: ${all.join(', ')})`); process.exitCode = 1; continue; }
    console.log('building', n);
    await builders[config.images[n].type](n, config.images[n]);
  }
} finally {
  await browser?.close(); server.close(); rmSync(work, { recursive: true, force: true });
}
console.log('done ->', outDir);
