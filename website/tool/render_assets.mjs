// Rasterizes the static image assets in web/ from the SVG mark and an inline
// HTML card, or checks that the committed files still match what it renders.
//
//   npm ci && npx playwright install --with-deps chromium
//   node tool/render_assets.mjs          # write web/favicon.png, web/apple-touch-icon.png, web/images/og.png
//   node tool/render_assets.mjs --check  # render to a temp dir and compare against the committed files
//
// The social card is rendered with the site's stylesheet and web fonts, so
// curl must be able to reach Google Fonts. Pixel output depends on the
// Chromium build, so --check is meant for CI on Linux with the Playwright
// version pinned in package.json; small antialiasing differences are
// tolerated, a changed layout, colour or font is not.
import { chromium } from 'playwright';
import pixelmatch from 'pixelmatch';
import { PNG } from 'pngjs';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const web = join(root, 'web');

/** Relative paths of the files this script produces. */
const assets = ['favicon.png', 'apple-touch-icon.png', 'images/og.png'];

// Share of pixels that may differ before --check fails.
const maxDifferentPixels = 0.005;

const logoSvg = (size) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 21 14.5 9.5"/><path d="M14.5 9.5 21 3c-1.5 5.5-4 8.5-8 10.5"/><path d="M9 15 5.5 18.5"/></svg>`;

const fontsCss =
  'https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=JetBrains+Mono:wght@400;600&display=swap';

// Chromium may not be able to reach Google Fonts (a proxy, a sandbox), so the
// font files are fetched with curl, which honours the usual proxy settings,
// and handed to the page as local files.
function fetchFonts(fontDir) {
  const curl = (url, ...args) =>
    execFileSync('curl', ['--fail', '--silent', '--show-error', '--location', ...args, url]);
  // A modern UA makes Google Fonts answer with woff2 sources.
  const ua = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36';
  let css = curl(fontsCss, '--user-agent', ua).toString();
  let n = 0;
  css = css.replace(/url\((https:[^)]+)\)/g, (_, url) => {
    const file = join(fontDir, `font-${n++}.woff2`);
    writeFileSync(file, curl(url));
    return `url(${pathToFileURL(file).href})`;
  });
  if (n === 0) throw new Error('No font files found in the Google Fonts stylesheet');
  return css;
}

// The social card is the landing page's hero, laid out for 1200x630: it links
// the site's own stylesheet and fonts, so it changes with the design.
const card = (fontFaces) => `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<style>${fontFaces}</style>
<link rel="stylesheet" href="${pathToFileURL(join(web, 'styles.css')).href}">
<style>
  html, body { margin: 0; background: var(--bg); }
  .card { position: relative; isolation: isolate; box-sizing: border-box; width: 1200px; height: 630px;
    padding: 60px 80px; overflow: hidden; border: 0; border-radius: 0; box-shadow: none; background: var(--bg); }
  .card .hero-bg { mask-image: none; -webkit-mask-image: none; }
  .card .logo { font-size: 2.1rem; }
  .card .logo-mark { width: 56px; height: 56px; border-radius: 15px; }
  .card .hero-badges { margin: 34px 0 0; gap: 0.6rem; }
  .card .pill { font-size: 1.05rem; padding: 0.4rem 0.95rem; }
  .card h1 { margin: 18px 0 0; font-size: 80px; font-weight: 700; line-height: 1.02; letter-spacing: -0.035em; color: var(--text); }
  .card .hero-lead { max-width: 60rem; margin-top: 26px; font-size: 1.9rem; line-height: 1.3; }
  .card .foot { position: absolute; left: 80px; right: 80px; bottom: 60px; display: flex; align-items: center; justify-content: space-between; }
  .card .install-command { max-width: none; padding: 0.9rem 1.6rem 0.9rem 1.4rem; gap: 1rem; }
  .card .install-command code { font-size: 1.55rem; overflow: visible; }
  .card .tk-prompt { font-size: 1.55rem; }
  .card .by { font-size: 1.35rem; color: var(--muted); }
</style></head>
<body><div class="card">
  <div class="hero-bg"></div>
  <span class="logo"><span class="logo-mark">${logoSvg(30)}</span><span class="logo-text">ciach</span></span>
  <p class="hero-badges"><span class="pill pill-accent">pub.dev</span><span class="pill">Dart 3.10+</span><span class="pill">Apache-2.0</span></p>
  <h1>Dead code detector for<br><span class="accent">Dart</span> and <span class="accent">Flutter</span>.</h1>
  <p class="hero-lead">Finds declarations nothing references and removes them for you. Backed by the Dart analysis server.</p>
  <div class="foot">
    <div class="install-command"><span class="tk-prompt">$</span><code>dart pub global activate ciach</code></div>
    <span class="by">by LeanCode</span>
  </div>
</div></body></html>`;

/** Renders every asset into [outDir], which mirrors the layout of web/. */
async function render(outDir) {
  mkdirSync(join(outDir, 'images'), { recursive: true });
  const work = mkdtempSync(join(tmpdir(), 'ciach-assets-'));
  // The full Chromium rather than the headless shell, so local runs and CI
  // rasterize with the same binary.
  const browser = await chromium.launch({ channel: 'chromium', args: ['--no-sandbox'] });
  try {
    const shoot = async (html, width, height, out, { transparent = false } = {}) => {
      const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
      await page.setContent(
        `<!doctype html><style>html,body{margin:0;background:${transparent ? 'transparent' : '#050505'}}</style>${html}`,
      );
      await page.screenshot({ path: out, omitBackground: transparent, clip: { x: 0, y: 0, width, height } });
      await page.close();
    };

    const mark = readFileSync(join(web, 'favicon.svg'), 'utf8').match(/<g[\s\S]*<\/g>/)[0];
    const icon = (size, rx) =>
      `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="${size}" height="${size}" style="display:block">
         <rect width="64" height="64" rx="${rx}" fill="#050505"/>${mark}</svg>`;
    // Rounded with transparent corners for browsers; full-bleed for iOS, which
    // masks the corners itself.
    await shoot(icon(96, 14), 96, 96, join(outDir, 'favicon.png'), { transparent: true });
    await shoot(icon(180, 0), 180, 180, join(outDir, 'apple-touch-icon.png'));

    const html = join(work, 'og.html');
    writeFileSync(html, card(fetchFonts(work)));
    const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
    await page.goto(pathToFileURL(html).href, { waitUntil: 'load' });
    await page.evaluate(() => document.fonts.ready);
    // document.fonts.check() is vacuously true when no face matches, so look
    // at the faces themselves: both families must be present and loaded.
    const loaded = await page.evaluate(() =>
      [...document.fonts].filter((f) => f.status === 'loaded').map((f) => f.family.replace(/"/g, '')),
    );
    for (const family of ['Space Grotesk', 'JetBrains Mono']) {
      if (!loaded.includes(family)) {
        throw new Error(`Web font not loaded: ${family} (loaded: ${[...new Set(loaded)].join(', ') || 'none'})`);
      }
    }
    await page.screenshot({ path: join(outDir, 'images', 'og.png'), clip: { x: 0, y: 0, width: 1200, height: 630 } });
    await page.close();
  } finally {
    await browser.close();
    rmSync(work, { recursive: true, force: true });
  }
}

/** Compares a fresh render against web/; writes diff images next to the render. */
async function check() {
  const outDir = mkdtempSync(join(tmpdir(), 'ciach-assets-check-'));
  await render(outDir);
  let failed = false;
  for (const asset of assets) {
    const expected = PNG.sync.read(readFileSync(join(web, asset)));
    const actual = PNG.sync.read(readFileSync(join(outDir, asset)));
    const label = relative(root, join(web, asset));
    if (expected.width !== actual.width || expected.height !== actual.height) {
      console.log(`FAIL ${label}: ${expected.width}x${expected.height} committed, ${actual.width}x${actual.height} rendered`);
      failed = true;
      continue;
    }
    const diff = new PNG({ width: expected.width, height: expected.height });
    const differing = pixelmatch(expected.data, actual.data, diff.data, expected.width, expected.height, {
      threshold: 0.1,
    });
    const share = differing / (expected.width * expected.height);
    const verdict = share > maxDifferentPixels ? 'FAIL' : 'ok  ';
    console.log(`${verdict} ${label}: ${differing} pixels differ (${(share * 100).toFixed(3)}%)`);
    if (share > maxDifferentPixels) {
      failed = true;
      writeFileSync(join(outDir, asset.replace(/\.png$/, '.diff.png')), PNG.sync.write(diff));
    }
  }
  if (failed) {
    console.log(`\nRendered files and diffs are in ${outDir}.`);
    console.log('If the change is intended, run `node tool/render_assets.mjs` and commit the result.');
    process.exit(1);
  }
  rmSync(outDir, { recursive: true, force: true });
}

if (process.argv.includes('--check')) {
  await check();
} else {
  await render(web);
}
