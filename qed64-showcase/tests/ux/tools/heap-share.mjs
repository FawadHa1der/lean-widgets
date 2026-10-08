#!/usr/bin/env node
// heap-share.mjs — how much JS heap the gallery itself adds on top of QED64, for QED64's HARDENING #55 headroom residual
// (2026-10-07: QED64's reload-storm ballast experiment showed that an embedding page's own heap decides the reload-crash
// rate: one booted runtime takes most of the renderer's 4 GiB pointer cage).
//
// Three arms, interleaved round by round, a FRESH profile per sample, every arm booting the same document (the chart-kit
// example, so the same snapshot, the same elaboration and the same widget panel):
//   stock    the QED64 page top-level (/?snapshots=snapshots/widgets8, plain mode; qed64.buffer seeded with the text)
//   host     a trivial same-origin embed host: one iframe of /?embed=1&snapshots=snapshots/widgets8#code=<text>, served by
//            Playwright route interception at /showcase/__heap-host.html with the isolation headers (no file is added
//            to the served tree; the host has no script of its own)
//   gallery  /showcase/#chart-kit (our gallery, the same page in its iframe)
// Same-origin frames share ONE isolate, so performance.memory read in the top window is the whole page's JS heap (the top
// document + the QED64 page + the InfoView frame); `host - stock` is the cost of embedding at all, `gallery - host` is the
// gallery's own share. Also recorded: performance.measureUserAgentSpecificMemory() (cross-origin isolated pages only;
// per-frame and per-worker attribution) and the renderer RSS (ps).
//
// Measured at ready (QED64 phase ready on a serving relay with the example's text) + --settle-s (default 5).
//
//   UX_RUN=heap-share-1 scripts/with-browser-lock.sh heap -- node tests/ux/tools/heap-share.mjs --origin http://localhost:5237 [--rounds 5] [--settle-s 5]
//
// The origin must serve the ACTIVE pin (a v1 pin: apiRevision in gallery/pin.json). Report: out/ux/<UX_RUN>/heap-share.json.
// Exit 0 = every sample measured, 1 = a sample failed (boot timeout, crash), 3 = infrastructure (lock, server, harness).
import fs from 'node:fs';
import path from 'node:path';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const ORIGIN = arg('--origin', process.env.UX_ORIGIN || 'http://localhost:5237');
const ROUNDS = Math.max(1, Number(arg('--rounds', '5')) || 5);
const SETTLE_MS = Math.max(0, Number(arg('--settle-s', '5')) * 1000);
const BOOT_BUDGET_MS = 400000;
process.env.UX_ORIGIN = ORIGIN;
process.env.UX_RUN = process.env.UX_RUN || 'heap-share';
let H;
try { H = await import('../lib/qed64.mjs'); } catch (e) { console.error(`heap-share: refused — the harness did not load: ${e.message}`); process.exit(3); }
const { launch, BY_ID, RUN_DIR, sleep, chromeRss, SC } = H;
if (!H.API) { console.error('heap-share: refused — the served gallery is a legacy page (no apiRevision); the arms need the v1 page'); process.exit(3); }

const EX = BY_ID['chart-kit'];
const OVERLAY = 'widgets8';
const HOST_PATH = '/showcase/__heap-host.html';
const HOST_BODY = `<!doctype html><meta charset="utf-8"><title>heap host</title>
<style>html,body{margin:0;height:100%}iframe{display:block;border:0;width:100%;height:100%}</style>
<iframe id="qed64-frame" allow="clipboard-read; clipboard-write" src="/?embed=1&snapshots=snapshots/${OVERLAY}#code=${encodeURIComponent(EX.text)}"></iframe>`;
const ISOLATION = { 'content-type': 'text/html; charset=utf-8', 'cross-origin-opener-policy': 'same-origin', 'cross-origin-embedder-policy': 'require-corp', 'cross-origin-resource-policy': 'same-origin', 'cache-control': 'no-store' };

const report = { startedAt: new Date().toISOString(), origin: ORIGIN, pin: H.GALLERY_PIN.pin, apiRevision: H.API_REVISION, rounds: ROUNDS, settleMs: SETTLE_MS, example: EX.id, overlay: OVERLAY, samples: [], summary: null, complete: false };
const save = () => { fs.mkdirSync(RUN_DIR, { recursive: true }); fs.writeFileSync(path.join(RUN_DIR, 'heap-share.json'), `${JSON.stringify(report, null, 2)}\n`); };

/** QED64's api status in a window (the top page for 'stock', the iframe for the others). */
const apiReadyIn = (target) => target.evaluate((want) => {
  const a = window.qed64 && window.qed64.api; if (!a) return null;
  let s; try { s = a.status(); } catch { return null; }
  let text = null; try { const d = a.getDocument(); text = d ? d.text : null; } catch { text = null; }
  return { phase: s.phase, relay: s.relay, ok: (s.phase === 'ready' || s.phase === 'headerRefused') && s.relay === 'serving' && text === want, failed: !!(s.boot && s.boot.failed) };
}, EX.text).catch(() => null);

/** The measurement, evaluated in the TOP window. */
const MEASURE = async () => {
  const pm = performance.memory ? { used: performance.memory.usedJSHeapSize, total: performance.memory.totalJSHeapSize, limit: performance.memory.jsHeapSizeLimit } : null;
  let ua = null;
  if (typeof performance.measureUserAgentSpecificMemory === 'function' && self.crossOriginIsolated) {
    try {
      const r = await Promise.race([performance.measureUserAgentSpecificMemory(), new Promise((_, j) => setTimeout(() => j(new Error('timeout 90 s')), 90000))]);
      ua = { bytes: r.bytes, breakdown: r.breakdown.filter((b) => b.bytes > 0).map((b) => ({ bytes: b.bytes, types: b.types, urls: b.attribution.map((x) => `${x.url}${x.scope ? ` [${x.scope}]` : ''}${x.container ? ` <${x.container.id || x.container.src || ''}>` : ''}`) })) };
    } catch (e) { ua = { error: String(e && e.message || e) }; }
  } else ua = { error: self.crossOriginIsolated ? 'measureUserAgentSpecificMemory unavailable' : 'not cross-origin isolated' };
  return { pm, ua, coi: self.crossOriginIsolated };
};

async function sample(arm, round) {
  const rec = { arm, round, ok: false, readyMs: null, pm: null, ua: null, rss: null, error: null };
  const s = await launch({ title: `heap-share ${arm} ${round}`, file: 'tools/heap-share.mjs' }, { profile: 'fresh', label: `${arm}${round}` });
  try {
    const page = await s.newPage();
    await page.route(`**${HOST_PATH}`, (route) => route.fulfill({ status: 200, headers: ISOLATION, body: HOST_BODY }));
    const t0 = Date.now();
    let frameOf = () => page; // where QED64's api lives
    if (arm === 'stock') {
      await page.goto(`${ORIGIN}/showcase/pin.json`);
      await page.evaluate((t) => localStorage.setItem('qed64.buffer', t), EX.text);
      await page.goto(`${ORIGIN}/?snapshots=snapshots/${OVERLAY}`, { waitUntil: 'domcontentloaded' });
    } else if (arm === 'host') {
      await page.goto(`${ORIGIN}${HOST_PATH}`, { waitUntil: 'domcontentloaded' });
      frameOf = () => page.frames().find((f) => f !== page.mainFrame() && /\/\?embed=1/.test(f.url())) || null;
    } else {
      await page.goto(`${ORIGIN}/showcase/#${EX.id}`, { waitUntil: 'domcontentloaded' });
      frameOf = () => page.frames().find((f) => f !== page.mainFrame() && /\/\?embed=1/.test(f.url())) || null;
    }
    for (;;) {
      if (s.watches.some((w) => w.crashed)) throw new Error('renderer crashed before ready');
      const f = frameOf(); const st = f ? await apiReadyIn(f) : null;
      if (st && st.failed) throw new Error(`QED64 boot failed (${JSON.stringify(st)})`);
      if (st && st.ok) break;
      if (Date.now() - t0 > BOOT_BUDGET_MS) throw new Error(`not ready within ${BOOT_BUDGET_MS / 1000} s (last ${JSON.stringify(st)})`);
      await sleep(250);
    }
    if (arm === 'gallery') { // the gallery's own ready (cursor placed, panel requested) as well
      for (const t1 = Date.now(); ;) { const gs = await page.evaluate(() => window.__showcase && window.__showcase.status().phase).catch(() => null); if (gs === 'ready') break; if (Date.now() - t1 > 60000) throw new Error(`gallery not ready (${gs})`); await sleep(250); }
    }
    rec.readyMs = Date.now() - t0;
    await sleep(SETTLE_MS);
    const m = await page.evaluate(MEASURE);
    rec.pm = m.pm; rec.ua = m.ua; rec.coi = m.coi;
    rec.rss = chromeRss();
    rec.ok = !!(m.pm && m.coi);
    if (!m.coi) rec.error = 'the top window is not cross-origin isolated';
  } catch (e) { rec.error = String(e && e.message || e).slice(0, 400); }
  finally { await s.close().catch(() => {}); }
  return rec;
}

const MiB = 1048576;
const stats = (xs) => { const v = xs.filter((x) => Number.isFinite(x)).sort((a, b) => a - b); if (!v.length) return null; const med = v.length % 2 ? v[(v.length - 1) / 2] : (v[v.length / 2 - 1] + v[v.length / 2]) / 2; return { n: v.length, minMiB: +(v[0] / MiB).toFixed(1), medianMiB: +(med / MiB).toFixed(1), maxMiB: +(v[v.length - 1] / MiB).toFixed(1) }; };
const ARMS = ['stock', 'host', 'gallery'];
let failed = 0;
for (let r = 1; r <= ROUNDS; r++) {
  for (let i = 0; i < ARMS.length; i++) {
    const arm = ARMS[(i + r - 1) % ARMS.length]; // rotate the order each round (interleaved, no fixed position)
    const rec = await sample(arm, r);
    if (!rec.ok) failed++;
    report.samples.push(rec); save();
    console.log(`heap-share r${r} ${arm.padEnd(7)} ${rec.ok ? 'ok ' : 'ERR'} ready ${rec.readyMs ?? '–'} ms  used ${rec.pm ? (rec.pm.used / MiB).toFixed(1) : '–'} MiB  total ${rec.pm ? (rec.pm.total / MiB).toFixed(1) : '–'} MiB  ua ${rec.ua && rec.ua.bytes ? (rec.ua.bytes / MiB).toFixed(1) + ' MiB' : (rec.ua && rec.ua.error) || '–'}  renderer ${rec.rss ? rec.rss.rendererGB + ' GB' : '–'}${rec.error ? `  (${rec.error})` : ''}`);
  }
}
const by = (arm, f) => report.samples.filter((x) => x.arm === arm && x.ok).map(f);
report.summary = Object.fromEntries(ARMS.map((a) => [a, { usedHeap: stats(by(a, (x) => x.pm.used)), totalHeap: stats(by(a, (x) => x.pm.total)), uaBytes: stats(by(a, (x) => (x.ua && x.ua.bytes) || NaN)), rendererRss: stats(by(a, (x) => (x.rss && x.rss.rendererBytes) || NaN)) }]));
const med = (a) => report.summary[a].usedHeap && report.summary[a].usedHeap.medianMiB;
report.summary.deltaUsedHeapMedianMiB = { embedding: med('host') != null && med('stock') != null ? +(med('host') - med('stock')).toFixed(1) : null, gallery: med('gallery') != null && med('host') != null ? +(med('gallery') - med('host')).toFixed(1) : null };
report.complete = true; report.failed = failed; report.finishedAt = new Date().toISOString(); save();
console.log(`heap-share: ${report.samples.length - failed}/${report.samples.length} samples; used-heap medians (MiB): ${ARMS.map((a) => `${a} ${med(a)}`).join(', ')}; host-stock ${report.summary.deltaUsedHeapMedianMiB.embedding}, gallery-host ${report.summary.deltaUsedHeapMedianMiB.gallery}; report ${path.relative(SC, path.join(RUN_DIR, 'heap-share.json'))}`);
process.exit(failed ? 1 : 0);
