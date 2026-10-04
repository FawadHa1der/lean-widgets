// Exploration probe (UX lane): what the STOCK page (and the gallery) do for C6 refused header, C7 unknown module,
// C8 bad overlay, C9 unpaired overlay, C12 offline warm reload. Under the browser lock. Needs the temp overlay
// out/overlay/snapshots/ux-unpaired (made by the caller). Writes out/ux/explore/stockcases.json.
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { SC, ORIGIN, LAUNCH_ARGS, lockHeld, sleep, until, waitGalleryReady, api } from '../bringup/lib.mjs';
lockHeld();
const OUT = path.join(SC, 'out/ux/explore'); fs.mkdirSync(OUT, { recursive: true });
const only = process.argv[2] ? process.argv[2].split(',') : ['c6', 'c7', 'c8', 'c9', 'c12'];
const res = {};
const st = (page) => page.evaluate(() => { const q = globalThis.qed64; if (!q) return { noQed64: true, boot: (document.getElementById('bootlabel') || {}).textContent, bootcard: (document.getElementById('bootcard') || {}).className }; const s = q.status(); return { phase: s.phase, version: s.version, header: s.header, collision: s.collision, session: s.session, snaps: q.relay.session.snapshots, stats: { ...q.relay.stats }, pill: (document.getElementById('ptext') || {}).textContent, action: (() => { const a = document.getElementById('action'); return a ? { hidden: a.hidden, display: getComputedStyle(a).display, text: a.textContent } : null; })(), bootcard: (document.getElementById('bootcard') || {}).className, bootlabel: (document.getElementById('bootlabel') || {}).textContent, lastDeath: s.lastDeath }; }).catch((e) => ({ err: e.message }));
async function stock(name, buffer, query, { ctxOpts = {}, waitMs = 120000, persistent = null, route = null } = {}) {
  const ctx = persistent ? await chromium.launchPersistentContext(persistent, { args: LAUNCH_ARGS, viewport: { width: 1440, height: 900 } }) : await (await chromium.launch({ args: LAUNCH_ARGS })).newContext({ viewport: { width: 1440, height: 900 }, ...ctxOpts });
  const page = ctx.pages()[0] || await ctx.newPage();
  const log = []; page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') log.push(`${m.type()} ${m.text().slice(0, 300)}`); }); page.on('pageerror', (e) => log.push(`pageerror ${String(e.message).slice(0, 300)}`));
  const bytes = { snapz: 0, aborted: 0 };
  page.on('response', async (r) => { if (/\.snapz/.test(r.url())) { const h = await r.allHeaders().catch(() => ({})); bytes.snapz += Number(h['content-length'] || 0); } });
  if (route) await ctx.route(route, (r) => { bytes.aborted++; return r.abort('internetdisconnected'); });
  await page.goto(`${ORIGIN}/showcase/pin.json`);
  await page.evaluate((b) => { if (b === null) localStorage.removeItem('qed64.buffer'); else localStorage.setItem('qed64.buffer', b); }, buffer);
  const t0 = Date.now();
  await page.goto(`${ORIGIN}/${query}`, { waitUntil: 'domcontentloaded' });
  let s = null;
  await until(async () => { s = await st(page); return s && (s.phase === 'ready' || s.phase === 'headerRefused' || s.phase === 'dead' || /failed/.test(s.bootcard || '')) ? s : null; }, { timeoutMs: waitMs, intervalMs: 300 });
  await sleep(3000);
  s = await st(page);
  const diags = await page.evaluate(() => { try { const m = globalThis.qed64.editor.getModel(); return globalThis.monaco ? null : null; } catch { return null; } }).catch(() => null);
  const markers = await page.evaluate(() => [...document.querySelectorAll('.monaco-hover, .squiggly-error')].length).catch(() => null);
  await page.screenshot({ path: path.join(OUT, `stock-${name}.png`) });
  const r = { ms: Date.now() - t0, s, log: log.slice(0, 20), bytes, markers, diags };
  await ctx.close();
  return r;
}
if (only.includes('c6')) res.c6 = await stock('c6', 'import HasseView\n\n#check (1 : Nat)\n', '?snapshots=snapshots/widgets8');
if (only.includes('c7')) res.c7 = await stock('c7', 'import Mathlib.NotAModule\n\n#check (1 : Nat)\n', '?snapshots=snapshots/widgets8');
if (only.includes('c8')) res.c8 = await stock('c8', 'import Mathlib\nimport HasseView\n\n#check (1 : Nat)\n', '?snapshots=snapshots/nope', { waitMs: 90000 });
if (only.includes('c9')) res.c9 = await stock('c9', 'import Mathlib\nimport HasseView\n\n#check (1 : Nat)\n', '?snapshots=snapshots/ux-unpaired', { waitMs: 90000 });
if (only.includes('c12')) {
  const prof = path.join(SC, 'out/ux/profiles/explore-warm');
  res.c12prime = await stock('c12-prime', 'import Mathlib\nimport HasseView\n\n#check (1 : Nat)\n', '?snapshots=snapshots/widgets8', { persistent: prof });
  res.c12warm = await stock('c12-warm', 'import Mathlib\nimport HasseView\n\n#check (1 : Nat)\n', '?snapshots=snapshots/widgets8', { persistent: prof });
  res.c12offline = await stock('c12-offline', 'import Mathlib\nimport HasseView\n\n#check (1 : Nat)\n', '?snapshots=snapshots/widgets8', { persistent: prof, route: '**/snapshots/widgets8/**' });
  // the gallery offline
  const ctx = await chromium.launchPersistentContext(prof, { args: LAUNCH_ARGS, viewport: { width: 1440, height: 900 } });
  const page = ctx.pages()[0] || await ctx.newPage(); let ab = 0;
  await ctx.route('**/snapshots/widgets8/**', (r) => { ab++; return r.abort('internetdisconnected'); });
  await page.goto(`${ORIGIN}/showcase/#hasse-view`, { waitUntil: 'domcontentloaded' });
  const g = await waitGalleryReady(page, { timeoutMs: 120000 });
  res.c12gallery = { ms: g.ms, phase: g.s && g.s.phase, error: g.s && g.s.error, aborted: ab, preflight: g.s && g.s.preflight };
  await page.screenshot({ path: path.join(OUT, 'gallery-c12-offline.png') });
  await ctx.close();
}
fs.writeFileSync(path.join(OUT, 'stockcases.json'), JSON.stringify(res, null, 2));
console.log(JSON.stringify(res, null, 1).slice(0, 9000));
process.exit(0);
