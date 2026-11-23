// Renders an SVG or HTML file to PNG with Chromium (Playwright): node render.cjs in.svg out.png width height
(async () => {
const { chromium } = require('playwright');
const { readFileSync } = require('fs');
const [, , input, output, w, h] = process.argv;
const width = parseInt(w), height = parseInt(h);
const body = readFileSync(input, 'utf8');
const html = input.endsWith('.html') ? body : `<!doctype html><html><head><style>
@import url('https://fonts.googleapis.com/css2?family=Exo+2:wght@500;700;800&display=block');
html,body{margin:0;padding:0;background:#0b1626}</style></head><body>${body}</body></html>`;
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
await page.setContent(html, { waitUntil: 'networkidle' });
await page.evaluate(() => document.fonts.ready);
await page.screenshot({ path: output, clip: { x: 0, y: 0, width, height } });
await browser.close();
})();
