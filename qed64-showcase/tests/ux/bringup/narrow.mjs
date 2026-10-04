// Layout checks: 390x844 with the automatic stacking and with ?stack=0, plus dark mode at 1440x900 and 390x844.
// Metrics from the real DOM (gallery + QED64 page + InfoView); screenshots in out/ux/bringup/<dir>/.
// Usage: scripts/with-browser-lock.sh bringup node tests/ux/bringup/narrow.mjs [--dir after]
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { ORIGIN, OUT, LAUNCH_ARGS, lockHeld, api, infoview, ivSettled, waitGalleryReady, writeJson, sleep, until } from './lib.mjs';

lockHeld();
const argv = process.argv.slice(2);
const dir = argv.includes('--dir') ? argv[argv.indexOf('--dir') + 1] : 'after';
const D = path.join(OUT, dir); fs.mkdirSync(D, { recursive: true });
const pe = (page, fn) => page.evaluate((src) => { const w = document.getElementById('qed64-frame').contentWindow; return new w.Function(`return (${src})();`)(); }, fn.toString());
const runs = [
  { name: 'narrow-390', viewport: { width: 390, height: 844 }, scheme: 'light', q: '', id: 'hasse-view' },
  { name: 'narrow-390-stack0', viewport: { width: 390, height: 844 }, scheme: 'light', q: '?stack=0', id: 'hasse-view' },
  { name: 'dark-1440', viewport: { width: 1440, height: 900 }, scheme: 'dark', q: '', id: 'tree-scope' },
  { name: 'dark-390', viewport: { width: 390, height: 844 }, scheme: 'dark', q: '', id: 'graph-scope' },
];
const res = {};
const browser = await chromium.launch({ args: LAUNCH_ARGS });
for (const r of runs) {
  const ctx = await browser.newContext({ viewport: r.viewport, deviceScaleFactor: 2, colorScheme: r.scheme, isMobile: r.viewport.width < 600, hasTouch: r.viewport.width < 600 });
  const page = await ctx.newPage();
  const out = { pageErrors: [] };
  page.on('pageerror', (e) => out.pageErrors.push(String(e.message).slice(0, 120)));
  try {
    await page.goto(`${ORIGIN}/showcase/${r.q}#${r.id}`, { waitUntil: 'domcontentloaded' });
    const g = await waitGalleryReady(page);
    out.bootMs = g.ms; out.phase = g.s.phase;
    await ivSettled(page); await sleep(1500);
    out.gallery = await page.evaluate(() => {
      const box = (id) => { const e = document.getElementById(id) || document.querySelector(id); if (!e) return null; const b = e.getBoundingClientRect(); return { x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.width), h: Math.round(b.height) }; };
      return { scrollW: document.documentElement.scrollWidth, innerW: innerWidth, frame: box('qed64-frame'), topbar: box('.topbar'), mobileBar: box('.mobile-bar'), railDisplay: getComputedStyle(document.getElementById('rail')).display, bodyBg: getComputedStyle(document.body).backgroundColor, statusOverflow: (() => { const e = document.getElementById('status-text'); return e.scrollWidth > e.clientWidth; })() };
    });
    out.page = await pe(page, () => {
      const box = (sel) => { const e = document.querySelector(sel); if (!e) return null; const b = e.getBoundingClientRect(); return { x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.width), h: Math.round(b.height) }; };
      const ed = window.qed64.editor; const li = ed.getLayoutInfo();
      return { splitDir: getComputedStyle(document.getElementById('split')).flexDirection, bar: box('#bar'), split: box('#split'), editor: box('#editor'), infoview: box('#infoview'), monaco: { width: li.width, height: li.height }, stackStyle: !!document.getElementById('qed64-showcase-stack'), docScrollW: document.documentElement.scrollWidth, innerW: innerWidth, bodyBg: getComputedStyle(document.body).backgroundColor };
    });
    out.infoview = await infoview(page).locator('body').evaluate((b) => ({ bg: getComputedStyle(b).backgroundColor, color: getComputedStyle(b).color, scrollW: document.documentElement.scrollWidth, clientW: document.documentElement.clientWidth, svgs: b.querySelectorAll('svg').length }));
    out.splitFits = out.page.split && out.page.bar ? out.page.bar.h + out.page.split.h <= out.page.innerW * 10 && (out.page.bar.h + out.page.split.h) <= (await pe(page, () => innerHeight)) + 1 : null;
    await page.screenshot({ path: path.join(D, `${r.name}.png`) });
    if (r.viewport.width < 600) {
      // the narrow select bar works
      await page.selectOption('#example-select', 'chart-kit');
      await until(async () => { const s = await api.status(page); return s.phase === 'ready' && s.shown === 'chart-kit'; }, { timeoutMs: 120000 });
      await ivSettled(page); await sleep(1000);
      out.selectSwitched = (await api.status(page)).shown;
      await page.screenshot({ path: path.join(D, `${r.name}-chart-kit.png`) });
      await page.locator('#mobile-hints summary').click();
      await sleep(300);
      await page.screenshot({ path: path.join(D, `${r.name}-hints.png`) });
    }
  } catch (e) { out.error = String(e && e.message || e).slice(0, 500); }
  res[r.name] = out;
  console.log(r.name, JSON.stringify({ phase: out.phase, gallery: out.gallery, page: out.page, iv: out.infoview, err: out.error }));
  await ctx.close();
}
await browser.close();
writeJson(`narrow-${dir}.json`, res);
