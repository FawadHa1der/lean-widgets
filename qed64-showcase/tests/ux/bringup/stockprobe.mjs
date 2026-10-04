// The stock QED64 page WITHOUT the gallery: seed qed64.buffer with the first example, boot
// /?snapshots=snapshots/<overlay> top-level, then switch documents with editor.getModel().setValue() exactly as a
// user paste would. Records the pthread pool (status().pool), the Worker count, renderer RSS and crashes.
// Decides whether a renderer crash is the gallery's doing or the page's own.
// Usage: scripts/with-browser-lock.sh bringup node tests/ux/bringup/stockprobe.mjs --tag t --seq chart-kit,hasse-view
//          [--bridge none|init] [--cursor 0|1] [--overlay widgets8] [--restart 0|1]
//   --restart 1: switch by relay.restart({snapshots:['init','mathlib']}) + setValue (fresh worker per example)
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { SC, ORIGIN, LAUNCH_ARGS, EXAMPLES, lockHeld, watchConsole, rssSampler, writeJson, sleep, chromeRss, ivSettled } from './lib.mjs';

lockHeld();
const argv = process.argv.slice(2);
const opt = (k, d = null) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const tag = opt('tag', 'stockprobe');
const seq = opt('seq', 'chart-kit,hasse-view').split(',');
const bridge = opt('bridge', 'init');
const cursor = opt('cursor', '1') === '1';
const overlay = opt('overlay', 'widgets8');
const restart = opt('restart', '0') === '1';
const allCursors = opt('cursors', 'first') === 'all';
const SPECS = Object.fromEntries(EXAMPLES.map((e) => [e.id, JSON.parse(fs.readFileSync(path.join(SC, 'lean/examples', `${e.id}.json`), 'utf8'))]));
const byId = Object.fromEntries(EXAMPLES.map((e) => [e.id, e]));
const BRIDGE_SRC = fs.readFileSync(path.join(SC, 'gallery/qed64-bridge.js'), 'utf8');
const t0 = Date.now();
const ctx = await chromium.launchPersistentContext(path.join(SC, 'out/ux/profiles/bringup'), { args: LAUNCH_ARGS, viewport: { width: 1440, height: 900 } });
const page = ctx.pages()[0] || await ctx.newPage();
const watch = watchConsole(page, t0, `${tag}.console.jsonl`);
const rss = rssSampler(1000, t0);
if (bridge === 'init') await ctx.addInitScript({ content: `${BRIDGE_SRC}\nif (window.top === window) window.installQed64Bridge(window);` });
const res = { tag, seq, bridge, cursor, overlay, restart, steps: [] };
const q = (fn, a) => page.evaluate(fn, a);
const status = () => q(() => { const s = globalThis.qed64.status(); return { phase: s.phase, version: s.version, session: s.session, relay: s.relay, pool: s.pool, header: s.header && s.header.mode }; });
async function waitReady(pred, ms = 300000) {
  const t = Date.now();
  for (;;) {
    const s = await status().catch(() => null);
    if (s && s.phase === 'ready' && pred(s)) return s;
    if (watch.crashed) throw new Error('crashed');
    if (Date.now() - t > ms) throw new Error(`timeout; last ${JSON.stringify(s)}`);
    await sleep(200);
  }
}
const poolLog = [];
let peakRunning = 0, peakTotal = 0;
const pl = setInterval(async () => {
  const s = await status().catch(() => null);
  if (s && s.pool) { const tot = s.pool.unused + s.pool.running; poolLog.push({ t: Date.now() - t0, ...s.pool, phase: s.phase }); peakRunning = Math.max(peakRunning, s.pool.running); peakTotal = Math.max(peakTotal, tot); }
}, 250);
try {
  // seed exactly like the gallery: the boot document is localStorage['qed64.buffer'] (main.ts:335-342)
  await page.goto(`${ORIGIN}/showcase/pin.json`);
  await q((t) => localStorage.setItem('qed64.buffer', t), byId[seq[0]].text);
  await page.goto(`${ORIGIN}/?snapshots=snapshots/${overlay}`, { waitUntil: 'domcontentloaded' });
  let s = await waitReady(() => true);
  res.boot = { ms: Date.now() - t0, ...s, workers: watch.workers.length };
  for (let i = 0; i < seq.length; i++) {
    const ex = byId[seq[i]];
    const st = { id: ex.id, t: Date.now() - t0 };
    if (i > 0) {
      const v0 = s.version, s0 = s.session;
      if (restart) {
        await q(() => globalThis.qed64.relay.restart({ snapshots: ['init', 'mathlib'] }));
        await q((t) => globalThis.qed64.editor.getModel().setValue(t), ex.text);
        s = await waitReady((x) => x.session !== s0);
      } else {
        await q((t) => globalThis.qed64.editor.getModel().setValue(t), ex.text);
        s = await waitReady((x) => x.version > v0);
      }
    }
    st.readyMs = Date.now() - t0 - st.t;
    if (cursor) {
      const cs = allCursors ? SPECS[ex.id].cursors.map((c) => ({ lineNumber: c.line + 1, column: c.character + 1 })) : [ex.firstCursor];
      st.cursors = [];
      for (const c of cs) {
        await q((c) => { const e = globalThis.qed64.editor; e.setPosition({ lineNumber: c.lineNumber, column: c.column }); e.revealLineInCenter(c.lineNumber); e.focus(); }, c);
        await sleep(500);
        const settled = await ivSettled_(page);
        await sleep(1500);
        const sc = await status();
        st.cursors.push({ line: c.lineNumber, settled, pool: sc.pool, total: sc.pool.unused + sc.pool.running, workers: watch.workers.length });
        console.log(`  ${ex.id} L${c.lineNumber} pool ${JSON.stringify(sc.pool)} total ${sc.pool.unused + sc.pool.running}`);
      }
      st.settled = st.cursors.every((x) => x.settled);
    }
    await sleep(4000);
    s = await status();
    st.status = s; st.workers = watch.workers.length; st.rss = chromeRss();
    st.bridge = await q(() => globalThis.__qed64Bridge || null).catch(() => null);
    res.steps.push(st);
    watch.mark('step', st);
    console.log(JSON.stringify({ id: ex.id, readyMs: st.readyMs, pool: s.pool, session: s.session, workers: st.workers, rss: st.rss.totalGiB }));
  }
} catch (e) {
  res.error = String(e && e.message || e).slice(0, 600);
} finally {
  clearInterval(pl); rss.stop();
  res.crashed = watch.crashed; res.peakRunning = peakRunning; res.peakPoolTotal = peakTotal; res.workersCreated = watch.workers.length;
  res.rssPeak = rss.peak; res.poolLog = poolLog.filter((_, i) => i % 4 === 0); res.pageErrors = watch.pageErrors;
  res.wallMs = Date.now() - t0;
  writeJson(`${tag}.json`, res);
  await ctx.close().catch(() => {});
}
async function ivSettled_(p) {
  // the stock page's InfoView is one iframe deep here
  const iv = p.frameLocator('#infoview iframe'); const t = Date.now();
  for (;;) {
    const gold = await iv.locator('summary[class*=gold]').count().catch(() => 1);
    if (!gold) return true;
    if (Date.now() - t > 60000) return false;
    await sleep(200);
  }
}
void ivSettled;
process.exit(res.error || res.crashed ? 1 : 0);
