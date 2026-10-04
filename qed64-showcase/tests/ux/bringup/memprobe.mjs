// Memory / crash probe for the gallery: boot /showcase/[?mem=G]#<first>, then select each id of --seq in turn.
// Every 1 s: renderer RSS (ps) and the wasm heap from the worker's telemetry (relay.session.lean.request).
// Streams console + page errors + crash to out/ux/bringup/<tag>.console.jsonl; summary to <tag>.json.
// Usage: scripts/with-browser-lock.sh bringup node tests/ux/bringup/memprobe.mjs --tag t --seq chart-kit,hasse-view [--mem 3] [--profile dir]
import path from 'node:path';
import { chromium } from 'playwright';
import { ORIGIN, LAUNCH_ARGS, OUT, EXAMPLES, lockHeld, watchConsole, rssSampler, api, ivText, ivSettled, waitGalleryReady, writeJson, sleep, chromeRss } from './lib.mjs';

lockHeld();
const argv = process.argv.slice(2);
const opt = (k, d = null) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const tag = opt('tag', 'memprobe');
const seq = (opt('seq', EXAMPLES.map((e) => e.id).join(','))).split(',');
const mem = opt('mem');
const profile = opt('profile');
const shots = argv.includes('--shots');
const t0 = Date.now();
const browser = profile ? null : await chromium.launch({ args: LAUNCH_ARGS });
const ctx = profile ? await chromium.launchPersistentContext(path.resolve(profile), { args: LAUNCH_ARGS, viewport: { width: 1440, height: 900 } })
  : await browser.newContext({ viewport: { width: 1440, height: 900 } });
const page = ctx.pages()[0] || await ctx.newPage();
const watch = watchConsole(page, t0, `${tag}.console.jsonl`);
const rss = rssSampler(1000, t0);
const heap = [];
let heapPeak = 0; let poolPeak = 0;
const tel = setInterval(async () => {
  const t = await page.evaluate(async () => {
    const w = document.getElementById('qed64-frame').contentWindow;
    const r = w && w.qed64 && w.qed64.relay; if (!r || !r.session || !r.session.lean) return null;
    const p = r.session.lean.request('telemetry');
    const v = await Promise.race([p, new Promise((res) => setTimeout(() => res(null), 1500))]);
    const m = v && (v.memory || (v.result && v.result.memory));
    const pool = w.qed64.status().pool;
    return m ? { session: r.session.id, pool, currentBytes: m.currentBytes, initialBytes: m.initialBytes, maximumBytes: m.maximumBytes, regionBytes: m.regionBytes, last: (m.checkpoints || []).slice(-1)[0] || null } : null;
  }).catch(() => null);
  if (t && t.pool) poolPeak = Math.max(poolPeak, t.pool.unused + t.pool.running);
  if (t) { heap.push({ t: Date.now() - t0, ...t }); if (t.currentBytes > heapPeak) { heapPeak = t.currentBytes; watch.mark('heap-peak', { currentBytes: t.currentBytes, session: t.session }); } }
}, 1000);
const res = { tag, seq, mem, profile, steps: [] };
try {
  const url = `${ORIGIN}/showcase/${mem ? `?mem=${mem}` : ''}#${seq[0]}`;
  watch.mark('goto', { url });
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  const r = await waitGalleryReady(page);
  res.boot = { ms: r.ms, timedOut: !!r.timedOut, phase: r.s && r.s.phase, qed64: r.s && r.s.qed64, mem: r.s && r.s.mem, bridge: r.s && r.s.bridge };
  watch.mark('booted', { ms: r.ms, rss: chromeRss() });
  for (const id of seq) {
    const st = { id, t: Date.now() - t0 };
    if (id !== (await api.status(page)).current || st.t < 0) { const s = await api.select(page, id); st.select = { ok: s.ok, code: s.code || null, msg: s.message || null }; }
    st.selectMs = Date.now() - t0 - st.t;
    st.settled = await ivSettled(page, { timeoutMs: 120000 });
    await sleep(1500);
    const text = await ivText(page);
    st.unrecognised = /Unrecognised error|abortSignal/.test(text);
    st.ivHead = text.slice(0, 160);
    st.rss = chromeRss(); st.heap = heap.at(-1) || null;
    const s = await api.status(page); st.phase = s.phase; st.qed64 = s.qed64 && { phase: s.qed64.phase, session: s.qed64.session, lastDeath: s.qed64.lastDeath };
    if (shots) await page.screenshot({ path: path.join(OUT, `${tag}-${id}.png`) });
    watch.mark('step', st);
    res.steps.push(st);
    console.log(JSON.stringify({ id, sel: st.select, settled: st.settled, unrec: st.unrecognised, rss: st.rss.totalGiB, pool: st.heap && st.heap.pool, heapMiB: st.heap && Math.round(st.heap.currentBytes / 1048576) }));
  }
  if (argv.includes('--crash')) {
    // one death through the relay's real death path: the reboot must go through the (wrapped) makeSession again
    const before = await page.evaluate(() => { const r = document.getElementById('qed64-frame').contentWindow.qed64.relay; const id = r.session.id; r.session.lean.died(null, 'crash', 'bring-up: crash reboot under ?mem'); return id; });
    const tC = Date.now();
    let after = null;
    for (let i = 0; i < 600 && !after; i++) {
      await sleep(250);
      after = await page.evaluate((old) => { const w = document.getElementById('qed64-frame').contentWindow; const r = w.qed64.relay; const s = w.qed64.status(); return s.phase === 'ready' && r.session.id !== old ? { session: r.session.id, initialBytes: r.session.initialBytes, snapshots: [...r.session.snapshots] } : null; }, before);
    }
    res.crashReboot = { before, after, ms: Date.now() - tC, galleryMem: (await api.status(page)).mem };
    await sleep(2000);
    res.crashReboot.heap = heap.at(-1) || null;
    console.log('crash reboot', JSON.stringify(res.crashReboot.after), res.crashReboot.ms, 'ms');
  }
  res.stats = await page.evaluate(() => { const w = document.getElementById('qed64-frame').contentWindow; return { ...w.qed64.relay.stats }; }).catch(() => null);
  res.final = await api.status(page).catch(() => null);
  res.bridgeStats = await api.bridge(page).catch(() => null);
} catch (e) {
  res.error = String(e && e.stack || e).slice(0, 1200);
} finally {
  clearInterval(tel); rss.stop();
  res.crashed = watch.crashed;
  res.poolPeak = poolPeak; res.workersCreated = watch.workers.length;
  res.rssPeak = rss.peak; res.heapPeakBytes = heapPeak; res.heap = heap.filter((_, i) => i % 3 === 0 || i === heap.length - 1);
  res.rssSamples = rss.samples.filter((_, i) => i % 3 === 0);
  res.pageErrors = watch.pageErrors;
  res.consoleCounts = watch.messages.reduce((a, m) => { a[m.type] = (a[m.type] || 0) + 1; return a; }, {});
  res.memLines = watch.messages.filter((m) => /\[mem\]/.test(m.text)).map((m) => `${m.t} ${m.text}`);
  res.wallMs = Date.now() - t0;
  writeJson(`${tag}.json`, res);
  await ctx.close().catch(() => {});
  if (browser) await browser.close().catch(() => {});
}
process.exit(res.error || res.crashed ? 1 : 0);
