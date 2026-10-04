// What a browser build reports about its graphics and display (last-mile lane, 2026-10-03), to compare headed Chrome for
// Testing, headed branded Chrome and chrome-headless-shell under the same host state (e.g. a locked macOS screen):
// chrome://gpu "Graphics Feature Status" (compositing, rasterization, …), devicePixelRatio, screen size, and a screenshot of
// one fixed text page (system-ui and monospace glyphs, 1440x900, DSF 1) whose pixels can be compared between builds.
// Writes out/ux/$UX_RUN/explore/envprobe-<tag>.json and screens/envprobe-<tag>.png. Run under the browser lock:
//   UX_RUN=<run> scripts/with-browser-lock.sh <lane> node tests/ux/tools/headed-env-probe.mjs --tag cft --headed --channel chromium
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { LAUNCH_ARGS, RUN_DIR, SCREENS, lockHeld, cooldown } from '../lib/qed64.mjs';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const TAG = arg('--tag', 'probe'); const CHANNEL = arg('--channel', undefined); const HEADED = process.argv.includes('--headed');
fs.mkdirSync(path.join(RUN_DIR, 'explore'), { recursive: true }); fs.mkdirSync(SCREENS, { recursive: true });
lockHeld(); await cooldown();
const out = { tag: TAG, channel: CHANNEL || null, headed: HEADED, at: new Date().toISOString() };
let browser;
try { browser = await chromium.launch({ args: LAUNCH_ARGS, headless: !HEADED, channel: CHANNEL }); } catch (e) { out.launchError = String(e.message).split('\n').slice(0, 6).join(' | '); console.log(`LAUNCH FAILED ${out.launchError}`); fs.writeFileSync(path.join(RUN_DIR, 'explore', `envprobe-${TAG}.json`), `${JSON.stringify(out, null, 1)}\n`); process.exit(1); }
out.version = browser.version();
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1, colorScheme: 'light' });
const p = await ctx.newPage();
out.ua = await p.evaluate(() => navigator.userAgent);
await p.goto('chrome://gpu').catch((e) => { out.gpuError = String(e.message).slice(0, 200); });
await p.waitForTimeout(1500);
out.gpu = await p.evaluate(() => {
  // chrome://gpu renders into shadow roots; collect the text of every open shadow root too
  const texts = []; const walk = (n) => { if (n.shadowRoot) walk(n.shadowRoot); for (const c of n.children || []) walk(c); if (n.nodeType === 1 && !n.children.length && n.textContent) texts.push(n.textContent.trim()); };
  walk(document.documentElement);
  const all = texts.join('\n'); const i = all.indexOf('Graphics Feature Status');
  return i >= 0 ? all.slice(i, i + 1400) : all.slice(0, 1400);
}).catch((e) => `eval failed: ${e.message}`);
await p.goto('about:blank');
await p.setContent('<!doctype html><meta charset=utf-8><body style="margin:24px;font:16px system-ui;background:#fff;color:#111"><h2 style="font:600 20px system-ui">ChartKit available</h2><p>Exact-rational SVG charts (bar, step, line, scatter, categorical) — the chart is the theorem\'s data.</p><pre style="font:14px ui-monospace,Menlo,monospace">#hasse (Finset (Fin 3)) ∅ ⋖ {0}  ∀ x, x ≤ {0, 1, 2}</pre></body>');
out.display = await p.evaluate(() => ({ dpr: devicePixelRatio, screen: [screen.width, screen.height, screen.availWidth, screen.availHeight, screen.colorDepth], inner: [innerWidth, innerHeight], visibility: document.visibilityState, hasFocus: document.hasFocus(), textWidth: (() => { const c = document.createElement('canvas').getContext('2d'); c.font = '16px system-ui'; return c.measureText('Exact-rational SVG charts (bar, step, line, scatter, categorical)').width; })(), pWidth: document.querySelector('p').getBoundingClientRect().width, h2: document.querySelector('h2').getBoundingClientRect().height }));
await p.screenshot({ path: path.join(SCREENS, `envprobe-${TAG}.png`), clip: { x: 0, y: 0, width: 900, height: 200 } });
console.log(`ENVPROBE ${TAG}: ${out.version} ${out.ua}\n display ${JSON.stringify(out.display)}\n gpu: ${String(out.gpu).replace(/\n/g, ' | ').slice(0, 900)}`);
fs.writeFileSync(path.join(RUN_DIR, 'explore', `envprobe-${TAG}.json`), `${JSON.stringify(out, null, 1)}\n`);
await browser.close();
