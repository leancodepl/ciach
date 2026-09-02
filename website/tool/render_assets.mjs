// Rasterizes the static image assets in web/ from the SVG mark and an inline
// HTML card. Needs Node with Playwright and a Chromium it can launch:
//
//   PLAYWRIGHT_CHROMIUM=/path/to/chromium node tool/render_assets.mjs
//
// Outputs: web/favicon.png (96px, rounded, transparent corners),
// web/apple-touch-icon.png (180px, full-bleed: iOS masks the corners itself)
// and web/images/og.png (1200x630 social card).
import { chromium } from 'playwright';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const web = join(root, 'web');
const svg = readFileSync(join(web, 'favicon.svg'), 'utf8');
const mark = svg.match(/<g[\s\S]*<\/g>/)[0];

const browser = await chromium.launch({
  executablePath: process.env.PLAYWRIGHT_CHROMIUM,
  args: ['--no-sandbox'],
});

async function shoot(html, width, height, out, { transparent = false } = {}) {
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
  await page.setContent(`<!doctype html><style>html,body{margin:0;background:${transparent ? 'transparent' : '#050505'}}</style>${html}`);
  await page.screenshot({ path: out, omitBackground: transparent, clip: { x: 0, y: 0, width, height } });
  await page.close();
}

const icon = (size, rx) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="${size}" height="${size}" style="display:block">
     <rect width="64" height="64" rx="${rx}" fill="#050505"/>${mark}</svg>`;

await shoot(icon(96, 14), 96, 96, join(web, 'favicon.png'), { transparent: true });
await shoot(icon(180, 0), 180, 180, join(web, 'apple-touch-icon.png'));

const card = `
<style>
  .card { position: relative; width: 1200px; height: 630px; overflow: hidden; box-sizing: border-box;
    padding: 72px 80px; color: #f4f4f2; font-family: Inter, "Segoe UI", system-ui, sans-serif;
    background:
      radial-gradient(ellipse 620px 380px at 78% 32%, rgba(237, 255, 47, 0.14), transparent 70%),
      repeating-linear-gradient(115deg, transparent 0 118px, rgba(237, 255, 47, 0.08) 118px 119px),
      #050505; }
  .brand { display: flex; align-items: center; gap: 18px; font-size: 44px; font-weight: 800; letter-spacing: -0.03em; }
  .brand svg { width: 68px; height: 68px; border-radius: 18px; background: #edff2f; }
  h1 { margin: 52px 0 0; font-size: 78px; line-height: 1.05; font-weight: 800; letter-spacing: -0.035em; }
  h1 b { color: #edff2f; font-weight: 800; }
  p { margin: 28px 0 0; max-width: 960px; font-size: 30px; line-height: 1.35; color: #b9b9b4; }
  .foot { position: absolute; left: 80px; right: 80px; bottom: 64px; display: flex; align-items: center; justify-content: space-between; }
  .cmd { display: inline-flex; align-items: center; gap: 14px; padding: 18px 28px; border: 1px solid rgba(255,255,255,0.14);
    border-radius: 14px; background: rgba(255,255,255,0.05); font: 27px/1 "JetBrains Mono", "DejaVu Sans Mono", ui-monospace, monospace; color: #d8d8d3; }
  .cmd span { color: #edff2f; }
  .by { font-size: 24px; color: #8a8a86; }
</style>
<div class="card">
  <div class="brand">
    <svg viewBox="0 0 64 64" fill="none" stroke="#050505" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">
      <g transform="translate(8 8) scale(2)"><path d="M3 21 14.5 9.5"/><path d="M14.5 9.5 21 3c-1.5 5.5-4 8.5-8 10.5"/><path d="M9 15 5.5 18.5"/></g>
    </svg>
    ciach
  </div>
  <h1>Dead code detector for<br><b>Dart</b> and <b>Flutter</b>.</h1>
  <p>Finds declarations nothing references and removes them for you. Backed by the Dart analysis server.</p>
  <div class="foot">
    <div class="cmd"><span>$</span>dart pub global activate ciach</div>
    <div class="by">by LeanCode</div>
  </div>
</div>`;
await shoot(card, 1200, 630, join(web, 'images', 'og.png'));

await browser.close();
