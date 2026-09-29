# peek images

Builds the images behind the hover preview on the home page (the little CRT that opens
when you rest the cursor on a link). Output goes to `../../peek/`, always as an **816x510 jpg**,
which is 2x the 408x255 screen of the `#peek` panel in `index.html`.

## Use

```sh
cd tools/peek
npm install                 # once: playwright-core (no browser download, see below)
node make-peek.mjs          # rebuild everything in peek.config.json
node make-peek.mjs whitepaper vibechecks   # or just some
```

Needs `convert`/`montage` (ImageMagick) and `pdftoppm` (poppler) on the PATH, and a Chromium.
The script looks for one in `~/.cache/ms-playwright`; otherwise set `CHROMIUM_PATH=/path/to/chrome`.

## Adding a preview for a link

1. Add an entry to `peek.config.json` under `images`. Four types:

   | type | what it does | fields |
   |------|--------------|--------|
   | `page` | screenshot of one live page | `url`, `wait` (ms) |
   | `collage` | grid of screenshots (3 columns by default) | `pages`, `cols`, `wait` |
   | `pdf` | first pages side by side, like an open paper | `src` (url or repo path), `pages` (`"1-2"`) |
   | `image` | an existing picture, cropped to fit | `src` (url), `gravity` (default `center`; `north` keeps the top of a tall page) |

   A `url` starting with `/` is a page of this site. The script serves the repo root itself, so
   pages that `fetch()` their own data files work. Anything else is loaded as given.
2. Run `node make-peek.mjs <name>`.
3. On the link in `index.html`, add `data-peek="peek/<name>.jpg"`. `data-peek` can also be a page
   URL (framed live) instead of an image.

Links to your own pages and to `*.github.io` need no `data-peek`: the preview frames the target directly.

## Why this exists (things learned the hard way)

- **github.com refuses to be framed** (`X-Frame-Options`). Repo pages, blob pages and PDFs all show
  blank, so those links get an image: a README screenshot, the project's Pages site, or a rendering.
  `raw.githubusercontent.com` does not help (it is served sandboxed).
- **Screenshot at 1024x640.** That is the size the live iframe preview renders at (it is scaled
  down to 0.398), so a collage shows the same crop a hover would.
- **Wait for the page.** Canvas and animation pages need 3+ seconds before they look like anything.
- **Headless Chromium has no real GPU.** WebGL pages can come out blank even when they work fine in a
  browser. Check the console first: `artifacts/orbit-viewer.html` was blank because of a real error
  (`randomDirection is not a function`, three.js r128), not because of headless.
- **Check what you are linking.** Cropping to a corner of a portrait page works for text; collages
  suit "a collection" links (Vibechecks, DIZZY Lab).
