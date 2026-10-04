#!/usr/bin/env node
// boot-check.mjs — ONE cold browser boot of the gallery on a deployed (or locally served) Worker:
//   node scripts/deploy-rehearsal/boot-check.mjs <origin> <out dir> [example id, default hasse-view]
// Run it through scripts/with-browser-lock.sh (one Chrome at a time on this host). It opens <origin>/showcase/#<id> in a
// FRESH profile (a first visit: every artifact comes from the origin), waits for the gallery to settle, and checks:
//   - the gallery's own pairing preflight passed (status().preflight.ok) and it chose an overlay;
//   - QED64 reached `ready` with <id> current and the cursor on the example's first cursor line;
//   - the widget panel rendered in the InfoView: for hasse-view an <svg> with the golden tag counts (8 rect, 12 line,
//     16 text) and the text "Insertable examples (click to insert after the command)";
//   - every request went to <origin> (nothing else was contacted) and the page is crossOriginIsolated.
// Writes <out dir>/boot-<id>.png and <out dir>/boot-<id>.json; prints BOOT-CHECK OK / FAILED.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const [origin = 'http://localhost:8790', outDir = 'out/deploy-rehearsal', id = 'hasse-view'] = process.argv.slice(2);
const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const ex = JSON.parse(fs.readFileSync(path.join(SC, 'gallery/examples.json'), 'utf8')).examples.find((e) => e.id === id);
if (!ex) { console.error(`no example ${id}`); process.exit(2); }
const panel = (ex.tryThis || []).find((t) => t.kind === 'cursor' && t.expectPanel)?.expectPanel || null;
const claim = (ex.tryThis || []).find((t) => t.kind === 'cursor' && t.expectTexts)?.expectTexts || [];
fs.mkdirSync(outDir, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const out = { origin, id, startedAt: new Date().toISOString(), checks: [] };
const check = (ok, what, detail = '') => { out.checks.push({ ok: !!ok, what, detail }); console.log(`${ok ? 'OK  ' : 'FAIL'} ${what}${detail ? ` — ${detail}` : ''}`); };

const browser = await chromium.launch({ args: ['--enable-features=SharedArrayBuffer'], headless: true });
const t0 = Date.now();
try {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  context.setDefaultTimeout(45000);
  const hosts = new Map(); const r2 = { n: 0, bytes: 0, status: {} };
  context.on('request', (q) => { try { const u = new URL(q.url()); if (/^(https?|wss?):$/.test(u.protocol)) hosts.set(u.host, (hosts.get(u.host) || 0) + 1); } catch { /* data:, blob: */ } });
  context.on('response', (r) => {
    try {
      const u = new URL(r.url());
      if (!/^\/(runtime|profiles|snapshots)\//.test(u.pathname) || r.request().method() !== 'GET') return;
      r2.n++; r2.status[r.status()] = (r2.status[r.status()] || 0) + 1;
      r.request().sizes().then((s) => { r2.bytes += Math.max(0, s.responseBodySize || 0); }).catch(() => {});
    } catch { /* ignore */ }
  });
  const page = await context.newPage();
  const errors = []; page.on('pageerror', (e) => errors.push(String(e.message).slice(0, 200)));
  await page.goto(`${origin}/showcase/#${id}`, { waitUntil: 'domcontentloaded', timeout: 120000 });
  let s = null;
  for (;;) {
    s = await page.evaluate(() => window.__showcase && window.__showcase.status()).catch(() => null);
    if (s && ['ready', 'refused', 'error', 'halted'].includes(s.phase)) break;
    if (Date.now() - t0 > 600000) break;
    await sleep(500);
  }
  out.bootMs = Date.now() - t0;
  out.status = s && { phase: s.phase, current: s.current, overlay: s.overlay, preflight: s.preflight, qed64: s.qed64, cursor: s.cursor, error: s.error, bootMs: s.bootMs };
  check(s && s.preflight && s.preflight.ok, `gallery preflight passed (overlay ${s && s.overlay}, attempts ${s && s.preflight && JSON.stringify((s.preflight.attempts || []).map((a) => `${a.overlay}:${a.ok}`))})`, s && !s.preflight?.ok ? JSON.stringify(s.preflight).slice(0, 300) : '');
  check(s && s.phase === 'ready' && s.current === id && s.qed64 && s.qed64.phase === 'ready',
    `QED64 ready with ${id} current after ${(out.bootMs / 1000).toFixed(0)} s (gallery phase ${s && s.phase}, qed64 phase ${s && s.qed64 && s.qed64.phase})`, s && s.error ? JSON.stringify(s.error).slice(0, 300) : '');
  check(s && s.cursor && s.cursor.lineNumber === ex.firstCursor.lineNumber, `cursor on line ${s && s.cursor && s.cursor.lineNumber} (example's first cursor ${ex.firstCursor.lineNumber}: ${ex.firstCursor.command})`);
  check(await page.evaluate(() => window.crossOriginIsolated), 'the gallery page is crossOriginIsolated (COOP/COEP from the worker)');
  // the widget panel inside the QED64 iframe's InfoView iframe
  const iv = page.frameLocator('#qed64-frame').frameLocator('#infoview iframe');
  let counts = null; let texts = false;
  for (let i = 0; i < 120; i++) {
    counts = await iv.locator('svg').evaluateAll((svgs) => svgs.map((g) => ({ rect: g.querySelectorAll('rect').length, line: g.querySelectorAll('line').length, text: g.querySelectorAll('text').length }))).catch(() => null);
    const body = await iv.locator('body').innerText().catch(() => '');
    texts = claim.every((t) => body.replace(/\s+/g, ' ').includes(t));
    const want = panel && panel.svgTagCounts;
    if (texts && (!want || (counts || []).some((c) => c.rect === want.rect && c.line === want.line && c.text === want.text))) break;
    await sleep(500);
  }
  const want = panel && panel.svgTagCounts;
  out.panel = { svgCounts: counts, wantSvg: want || null, texts: claim, textsPresent: texts };
  check(texts && (!want || (counts || []).some((c) => c.rect === want.rect && c.line === want.line && c.text === want.text)),
    `${panel ? panel.widget : id} panel rendered: svg ${JSON.stringify(counts)} (want ${JSON.stringify(want)}), text ${JSON.stringify(claim)} ${texts ? 'present' : 'MISSING'}`);
  await sleep(1000);
  const shot = path.join(outDir, `boot-${id}.png`);
  await page.screenshot({ path: shot });
  out.screenshot = shot;
  const originHost = new URL(origin).host;
  out.hosts = Object.fromEntries(hosts); out.r2 = r2; out.pageErrors = errors;
  check([...hosts.keys()].every((h) => h === originHost), `every request went to ${originHost}`, JSON.stringify(out.hosts));
  console.log(`info artifacts: ${r2.n} GETs under /runtime/ /profiles/ /snapshots/, ${(r2.bytes / 1e6).toFixed(1)} MB bodies, statuses ${JSON.stringify(r2.status)}; page errors ${errors.length}; screenshot ${shot}`);
} finally {
  await browser.close().catch(() => {});
}
const ok = out.checks.length >= 6 && out.checks.every((c) => c.ok);
fs.writeFileSync(path.join(outDir, `boot-${id}.json`), JSON.stringify(out, null, 1) + '\n');
console.log(ok ? `BOOT-CHECK OK ${origin}/showcase/#${id}` : `BOOT-CHECK FAILED ${origin}/showcase/#${id}`);
process.exit(ok ? 0 : 1);
