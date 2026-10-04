// Headed-window facts behind two headed-only UX failures (last-mile lane, 2026-10-03):
//   * the REAL display as the browser sees it (a context WITHOUT viewport emulation: devicePixelRatio, screen size), which
//     decides glyph rasterisation in a headed window (C13 baselines);
//   * requestAnimationFrame cadence and the latency of one Playwright locator.click() in an emulated 1440x900 page (C4's
//     storm assumes clicks land about 250 ms apart; Playwright's click waits for the element to be stable over
//     animation frames, so a slow frame clock stretches every click).
// Writes out/ux/$UX_RUN/explore/timing-<tag>.json. Run under the browser lock:
//   UX_RUN=<run> scripts/with-browser-lock.sh <lane> node tests/ux/tools/headed-timing-probe.mjs --tag cft --headed --channel chromium
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { LAUNCH_ARGS, RUN_DIR, lockHeld, cooldown } from '../lib/qed64.mjs';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const TAG = arg('--tag', 'probe'); const CHANNEL = arg('--channel', undefined); const HEADED = process.argv.includes('--headed');
fs.mkdirSync(path.join(RUN_DIR, 'explore'), { recursive: true });
lockHeld(); await cooldown();
const out = { tag: TAG, channel: CHANNEL || null, headed: HEADED, at: new Date().toISOString() };
const browser = await chromium.launch({ args: LAUNCH_ARGS, headless: !HEADED, channel: CHANNEL });
out.version = browser.version();
const real = await browser.newContext({ viewport: null });
const rp = await real.newPage();
await rp.setContent('<p>x</p>');
out.realDisplay = await rp.evaluate(() => ({ dpr: devicePixelRatio, screen: [screen.width, screen.height], inner: [innerWidth, innerHeight], matchRetina: matchMedia('(min-resolution: 2dppx)').matches }));
await real.close();
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
const p = await ctx.newPage();
await p.setContent('<style>button{margin:4px;padding:8px}</style>' + Array.from({ length: 8 }, (_, i) => `<button id=b${i}>card ${i}</button>`).join('') + '<script>window.hits=[];document.addEventListener("click",(e)=>hits.push([e.target.id,performance.now()]))</script>');
out.raf = await p.evaluate(() => new Promise((res) => { const ts = []; const f = (t) => { ts.push(t); if (ts.length < 121) requestAnimationFrame(f); else { const d = ts.slice(1).map((x, i) => x - ts[i]).sort((a, b) => a - b); res({ frames: d.length, medianMs: +d[d.length >> 1].toFixed(2), p90Ms: +d[Math.floor(d.length * 0.9)].toFixed(2), maxMs: +d[d.length - 1].toFixed(2), totalMs: +(ts[ts.length - 1] - ts[0]).toFixed(0) }); } }; requestAnimationFrame(f); }));
const lat = [];
for (let r = 0; r < 3; r++) for (let i = 0; i < 8; i++) { const t = Date.now(); await p.locator(`#b${i}`).click({ timeout: 5000 }); lat.push(Date.now() - t); }
lat.sort((a, b) => a - b);
out.clickLatencyMs = { n: lat.length, median: lat[lat.length >> 1], p90: lat[Math.floor(lat.length * 0.9)], max: lat[lat.length - 1], min: lat[0] };
console.log(`TIMING ${TAG} ${out.version}: real display ${JSON.stringify(out.realDisplay)}; rAF ${JSON.stringify(out.raf)}; click ${JSON.stringify(out.clickLatencyMs)}`);
fs.writeFileSync(path.join(RUN_DIR, 'explore', `timing-${TAG}.json`), `${JSON.stringify(out, null, 1)}\n`);
await browser.close();
