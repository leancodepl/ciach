// Rasterizes the static image assets in web/ from the SVG mark and an inline
// HTML card. Needs Node with Playwright and a Chromium it can launch:
//
//   PLAYWRIGHT_CHROMIUM=/path/to/chromium node tool/render_assets.mjs
//
// Outputs: web/favicon.png (96px, rounded, transparent corners),
// web/apple-touch-icon.png (180px, full-bleed: iOS masks the corners itself)
// and web/images/og.png (the 1200x630 social card, rendered with the site's
// stylesheet and web fonts, so it needs network access to Google Fonts).
import { chromium } from 'playwright';
import { readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const web = join(root, 'web');
const svg = readFileSync(join(web, 'favicon.svg'), 'utf8');
const mark = svg.match(/<g[\s\S]*<\/g>/)[0];

const logoSvg = (size) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 21 14.5 9.5"/><path d="M14.5 9.5 21 3c-1.5 5.5-4 8.5-8 10.5"/><path d="M9 15 5.5 18.5"/></svg>`;

// Web fonts come from Google Fonts; honour an outbound proxy when one is set.
const proxy = process.env.HTTPS_PROXY || process.env.https_proxy;
const browser = await chromium.launch({
  ...(proxy ? { proxy: { server: proxy } } : {}),
  executablePath: process.env.PLAYWRIGHT_CHROMIUM,
  args: ['--no-sandbox'],
});

async function shoot(html, width, height, out, { transparent = false } = {}) {
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1, ignoreHTTPSErrors: true });
  await page.setContent(`<!doctype html><style>html,body{margin:0;background:${transparent ? 'transparent' : '#050505'}}</style>${html}`);
  await page.screenshot({ path: out, omitBackground: transparent, clip: { x: 0, y: 0, width, height } });
  await page.close();
}

const icon = (size, rx) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="${size}" height="${size}" style="display:block">
     <rect width="64" height="64" rx="${rx}" fill="#050505"/>${mark}</svg>`;

await shoot(icon(96, 14), 96, 96, join(web, 'favicon.png'), { transparent: true });
await shoot(icon(180, 0), 180, 180, join(web, 'apple-touch-icon.png'));

// The social card is the landing page's hero, laid out for 1200x630: it links
// the site's own stylesheet and fonts, so it changes with the design.
const fontsHref =
  'https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=JetBrains+Mono:wght@400;600&display=swap';
const card = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<link rel="stylesheet" href="${fontsHref}">
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

{
  const out = join(web, 'images', 'og.png');
  const tmp = join(tmpdir(), `ciach-og-${process.pid}.html`);
  writeFileSync(tmp, card);
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1, ignoreHTTPSErrors: true });
  await page.goto(pathToFileURL(tmp).href, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  for (const font of ["700 16px 'Space Grotesk'", "400 16px 'JetBrains Mono'"]) {
    if (!(await page.evaluate((f) => document.fonts.check(f), font))) {
      throw new Error(`Web font not loaded: ${font}. Is fonts.googleapis.com reachable?`);
    }
  }
  await page.screenshot({ path: out, clip: { x: 0, y: 0, width: 1200, height: 630 } });
  await page.close();
  rmSync(tmp);
}

await browser.close();
