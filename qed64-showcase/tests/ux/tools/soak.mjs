// Soak: one gallery tab for --minutes (default 22), cycling through all eight widgets (last-mile lane, 2026-10-03).
// chrome-headless-shell (the UX suite's browser), fresh profile, /showcase/ on --origin. Every --tick-s (default 20 s) one
// tick on the next widget in rail order: a real mouse click on its rail card (Gallery.selectUI), then, for a widget with
// declared InfoView clicks, the next one of them with the real mouse (actions.mjs clickLink: edit == the frozen edit,
// 0 errors / 0 warnings on the re-checked version) and "Reset example" (resetUI); for a widget without declared clicks
// (ChartKit, ExprXRay, TreeScope) the cursor is placed on its first cursor and the panel must equal its golden
// (checkCursor). The tick then waits for the rest of its slot.
// Sampled: renderer RSS (chromeRss, every --rss-s s, own sampler), the wasm heap (the worker's telemetry
// memory.currentBytes), the page's JS heap (performance.memory), live workers, QED64 pool, gallery liveness/stall counters.
// Asserted afterwards (written into the JSON as `assert`): no renderer crash; every operation ok and none slower than
// --stall-ms (default 60 s); no stall card, no gallery liveness restart, no QED64 `wedged` reboot, no worker death;
// the console oracle ok; RSS bounded: the max renderer RSS of the last full cycle <= 1.10 x that of cycle 2, and the
// OLS slope of renderer RSS after cycle 1 is reported (MB/min) with its projection over one hour.
// Run it under the host browser lock:
//   UX_RUN=<run> scripts/with-browser-lock.sh <lane> node tests/ux/tools/soak.mjs --origin http://localhost:5191 --minutes 22
import fs from 'node:fs';
import path from 'node:path';
import { launch, Gallery, RUN_DIR, SCREENS, IDS, BY_ID, GOLDENS, chromeRss, sleep } from '../lib/qed64.mjs';
import { clickLink, checkCursor, cursorOfLine, goldenCursor } from '../lib/actions.mjs';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const ORIGIN = arg('--origin', 'http://localhost:5191');
const TAG = arg('--tag', 'soak');
const MINUTES = Number(arg('--minutes', '22'));
const TICK_MS = Number(arg('--tick-s', '20')) * 1000;
const RSS_MS = Number(arg('--rss-s', '5')) * 1000;
const STALL_MS = Number(arg('--stall-ms', '60000'));
fs.mkdirSync(path.join(RUN_DIR, 'explore'), { recursive: true }); fs.mkdirSync(SCREENS, { recursive: true }); fs.mkdirSync(path.join(RUN_DIR, 'tests'), { recursive: true });
const OUT = path.join(RUN_DIR, 'explore', `soak-${TAG}.json`);
const out = { tag: TAG, origin: ORIGIN, minutes: MINUTES, tickMs: TICK_MS, startedAt: new Date().toISOString(), ticks: [], rss: [], heap: [] };
const save = () => fs.writeFileSync(OUT, `${JSON.stringify(out, null, 1)}\n`);

const s = await launch({ title: `soak-${TAG}`, file: 'tools/soak.mjs' }, { profile: 'fresh', label: `soak-${TAG}` });
try { out.browserVersion = s.browser.version(); } catch { /* ignore */ }
const tStart = Date.now();
let crashed = null;
const g = await Gallery.open(s, { origin: ORIGIN });
g.page.on('crash', () => { crashed = Date.now() - tStart; });
out.boot = { phase: g.boot.s && g.boot.s.phase, ms: g.boot.ms };
console.log(`[${TAG}] boot ${out.boot.phase} in ${out.boot.ms} ms`);
await g.page.screenshot({ path: path.join(SCREENS, `soak-${TAG}-boot.png`) });
const watch = s.watches[0];
const live = () => (watch ? watch.workers.filter((w) => w.closed === null).length : null);

// renderer RSS sampler (own timer; ps only, nothing in the page)
let sampling = true;
(async () => { while (sampling) { const r = chromeRss(); out.rss.push({ t: Date.now() - tStart, rendererBytes: r.rendererBytes, totalBytes: r.totalBytes, renderers: r.renderers }); await sleep(RSS_MS); } })();
const jsHeap = () => g.page.evaluate(() => (performance.memory ? { used: performance.memory.usedJSHeapSize, total: performance.memory.totalJSHeapSize } : null)).catch(() => null);

const visits = Object.fromEntries(IDS.map((id) => [id, 0]));
const endAt = tStart + MINUTES * 60000;
let k = 0;
while (Date.now() < endAt && crashed === null) {
  const id = IDS[k % IDS.length]; const cycle = Math.floor(k / IDS.length); const ex = BY_ID[id]; const gold = GOLDENS[id];
  const tk = Date.now(); const rec = { k, cycle, id, t: tk - tStart, ops: [] };
  try {
    const sel = await g.selectUI(id, { timeoutMs: 330000 });
    rec.ops.push({ op: 'card', ok: sel.ok, code: sel.code, ms: sel.ms });
    if (sel.ok && gold.clicks.length) {
      const gc = gold.clicks[visits[id] % gold.clicks.length];
      const cur = cursorOfLine(id, gc.cursorLine); const at = { line: cur.line, character: cur.character };
      const panel = gc.kind === 'makeEditLink' ? goldenCursor(id, at.line, at.character).panels[0] : null;
      const t = Date.now();
      const r = await clickLink(g, ex, { kind: gc.kind, linkText: gc.linkText, title: gc.linkTitle || null, edit: gc.edit, editedSha256: gc.editedSha256 }, at, panel, { elabTimeoutMs: id === 'dist-lens' ? 300000 : 120000 });
      rec.ops.push({ op: `click ${gc.kind} “${(gc.linkText || gc.linkTitle || '').slice(0, 40)}”`, ok: r.ok, ms: Date.now() - t, error: r.error || null, errors: r.errors, warnings: r.warnings, stalls: (r.stalls || []).length });
      const rs = await g.resetUI(ex);
      rec.ops.push({ op: 'reset', ok: rs.ok, ms: rs.ms });
    } else if (sel.ok) {
      const r = await checkCursor(g, id, BY_ID[id].firstCursor ? { line: BY_ID[id].firstCursor.line, character: BY_ID[id].firstCursor.character } : cursorOfLine(id, 0));
      rec.ops.push({ op: 'cursor panel == golden', ok: r.ok, ms: r.ms, diffs: (r.diffs || []).slice(0, 2) });
    }
  } catch (e) { rec.ops.push({ op: 'exception', ok: false, error: String(e.message).split('\n')[0].slice(0, 200) }); }
  visits[id]++;
  const st = await g.status(); const q = await g.qstatus();
  const tel = await g.telemetry().catch(() => null); const jh = await jsHeap();
  rec.ms = Date.now() - tk;
  rec.galleryPhase = st && st.phase; rec.edited = st && st.edited;
  rec.stall = st && st.stall ? { shown: st.stall.shown, restarts: st.stall.restarts, active: st.stall.active } : null;
  rec.liveness = st && st.liveness ? { restarts: st.liveness.restarts, wedged: st.liveness.wedged, missed: st.liveness.missed, qed64WedgedReboots: st.liveness.qed64 ? st.liveness.qed64.wedgedReboots : null } : null;
  rec.qed64 = q ? { phase: q.phase, session: q.session, pool: q.pool, lastDeath: q.lastDeath ? { reason: q.lastDeath.reason || null, message: String(q.lastDeath.message || '').slice(0, 120) } : null, workerDeaths: q.stats ? q.stats.workerDeaths : null, reboots: q.stats ? q.stats.reboots : null, breakerTrips: q.stats ? q.stats.breakerTrips : null } : null;
  rec.wasmBytes = tel ? tel.currentBytes : null; rec.wasmSession = tel ? tel.session : null; rec.jsHeapUsed = jh ? jh.used : null; rec.workersAlive = live();
  out.heap.push({ t: Date.now() - tStart, wasmBytes: rec.wasmBytes, jsHeapUsed: rec.jsHeapUsed, session: rec.wasmSession });
  rec.ok = rec.ops.every((o) => o.ok) && rec.ops.every((o) => !(o.ms > STALL_MS));
  out.ticks.push(rec);
  const lastRss = out.rss.length ? out.rss[out.rss.length - 1].rendererBytes : 0;
  console.log(`[${TAG}] ${((Date.now() - tStart) / 60000).toFixed(1)} min k=${k} c${cycle} ${id}: ${rec.ops.map((o) => `${o.op.split(' ')[0]} ${o.ok ? 'ok' : 'FAIL'} ${o.ms}ms`).join(', ')} | renderer ${(lastRss / 2 ** 30).toFixed(2)} GiB wasm ${rec.wasmBytes ? (rec.wasmBytes / 2 ** 30).toFixed(2) : '?'} GiB workers ${rec.workersAlive} restarts ${rec.liveness && rec.liveness.restarts} stallShown ${rec.stall && rec.stall.shown}`);
  if ((k + 1) % IDS.length === 0) { try { await g.page.screenshot({ path: path.join(SCREENS, `soak-${TAG}-cycle${cycle}.png`) }); } catch { /* ignore */ } save(); }
  k++;
  const wait = tk + TICK_MS - Date.now();
  if (wait > 0) await sleep(Math.min(wait, Math.max(0, endAt - Date.now())));
}
sampling = false; await sleep(RSS_MS + 200);
out.endedAt = new Date().toISOString(); out.durationMin = +((Date.now() - tStart) / 60000).toFixed(2); out.crashedAtMs = crashed;
try { await g.page.screenshot({ path: path.join(SCREENS, `soak-${TAG}-end.png`) }); } catch { /* ignore */ }
// ---- analysis
const fullCycles = Math.floor(out.ticks.length / IDS.length);
const cycleOf = (t) => { const tk = out.ticks.filter((x) => x.t <= t).pop(); return tk ? tk.cycle : 0; };
const perCycle = [];
for (let c = 0; c < fullCycles; c++) {
  const ts = out.ticks.filter((x) => x.cycle === c); const from = ts[0].t; const to = (out.ticks.find((x) => x.cycle === c + 1) || { t: Infinity }).t;
  const rs = out.rss.filter((x) => x.t >= from && x.t < to).map((x) => x.rendererBytes);
  perCycle.push({ cycle: c, fromMin: +(from / 60000).toFixed(2), maxRendererGiB: +(Math.max(...rs) / 2 ** 30).toFixed(2), meanRendererGiB: +(rs.reduce((a, b) => a + b, 0) / rs.length / 2 ** 30).toFixed(2), wasmEndGiB: ts[ts.length - 1].wasmBytes ? +(ts[ts.length - 1].wasmBytes / 2 ** 30).toFixed(2) : null, ticksOk: ts.filter((x) => x.ok).length, ticks: ts.length });
}
out.perCycle = perCycle;
const ols = (pts) => { const n = pts.length; if (n < 3) return null; const mx = pts.reduce((a, p) => a + p[0], 0) / n; const my = pts.reduce((a, p) => a + p[1], 0) / n; let sxy = 0; let sxx = 0; for (const [x, y] of pts) { sxy += (x - mx) * (y - my); sxx += (x - mx) ** 2; } const b = sxy / sxx; const a = my - b * mx; let ssr = 0; let sst = 0; for (const [x, y] of pts) { ssr += (y - (a + b * x)) ** 2; sst += (y - my) ** 2; } return { slope: b, r2: sst ? 1 - ssr / sst : null, n }; };
const warm = out.ticks.find((x) => x.cycle === 1); const warmT = warm ? warm.t : 0;
const rr = ols(out.rss.filter((x) => x.t >= warmT && x.rendererBytes > 0).map((x) => [x.t / 60000, x.rendererBytes / 1e6]));
const wr = ols(out.heap.filter((x) => x.t >= warmT && x.wasmBytes).map((x) => [x.t / 60000, x.wasmBytes / 1e6]));
const jr = ols(out.heap.filter((x) => x.t >= warmT && x.jsHeapUsed).map((x) => [x.t / 60000, x.jsHeapUsed / 1e6]));
out.slopes = { fromMin: +(warmT / 60000).toFixed(2), rendererMBperMin: rr && +rr.slope.toFixed(1), rendererR2: rr && +rr.r2.toFixed(3), rendererProjectedGBperHour: rr && +((rr.slope * 60) / 1000).toFixed(2), wasmMBperMin: wr && +wr.slope.toFixed(1), wasmR2: wr && wr.r2 !== null ? +wr.r2.toFixed(3) : null, jsHeapMBperMin: jr && +jr.slope.toFixed(2), samples: rr && rr.n };
const allRss = out.rss.filter((x) => x.rendererBytes > 0).map((x) => x.rendererBytes);
out.rssSummary = { minGiB: +(Math.min(...allRss) / 2 ** 30).toFixed(2), maxGiB: +(Math.max(...allRss) / 2 ** 30).toFixed(2), firstGiB: +(allRss[0] / 2 ** 30).toFixed(2), lastGiB: +(allRss[allRss.length - 1] / 2 ** 30).toFixed(2), samples: allRss.length };
const ops = out.ticks.flatMap((x) => x.ops);
const lastT = out.ticks[out.ticks.length - 1] || {};
const v = s.verdict({ scenarios: [] });
out.console = { ok: v.ok, counts: v.counts, unexpected: v.unexpected, crashed: v.crashed };
const c2 = perCycle[1]; const cl = perCycle[perCycle.length - 1];
out.assert = {
  noCrash: crashed === null && !v.crashed,
  allOpsOk: ops.every((o) => o.ok),
  noSlowOp: ops.every((o) => !(o.ms > STALL_MS)),
  slowestOpMs: Math.max(...ops.map((o) => o.ms || 0)),
  noStallCard: out.ticks.every((x) => !x.stall || x.stall.shown === 0),
  noLivenessRestart: out.ticks.every((x) => !x.liveness || (x.liveness.restarts === 0)),
  noQed64WedgedReboot: out.ticks.every((x) => !x.liveness || !x.liveness.qed64WedgedReboots),
  oneWasmSession: new Set(out.heap.map((x) => x.session).filter(Boolean)).size === 1,
  noWorkerDeath: out.ticks.every((x) => !x.qed64 || (!x.qed64.workerDeaths && !x.qed64.breakerTrips)),
  consoleOk: v.ok,
  rssBounded: !!(c2 && cl && cl.maxRendererGiB <= 1.10 * c2.maxRendererGiB),
  fullCycles, ticks: out.ticks.length, minutes: out.durationMin, everyWidgetVisited: Object.values(visits).every((n) => n >= 2), visits,
};
out.assert.pass = ['noCrash', 'allOpsOk', 'noSlowOp', 'noStallCard', 'noLivenessRestart', 'noQed64WedgedReboot', 'oneWasmSession', 'noWorkerDeath', 'consoleOk', 'rssBounded', 'everyWidgetVisited'].every((x) => out.assert[x]) && out.durationMin >= 20;
out.summary = `${TAG}: ${out.durationMin} min, ${out.ticks.length} ticks (${fullCycles} full cycles of 8), ${ops.length} operations, ${ops.filter((o) => !o.ok).length} failed, slowest ${out.assert.slowestOpMs} ms; crash ${crashed === null ? 'no' : crashed}; renderer RSS ${out.rssSummary.firstGiB} -> ${out.rssSummary.lastGiB} GiB (min ${out.rssSummary.minGiB}, max ${out.rssSummary.maxGiB}), slope after cycle 1 ${out.slopes.rendererMBperMin} MB/min (R2 ${out.slopes.rendererR2}); wasm ${lastT.wasmBytes ? (lastT.wasmBytes / 2 ** 30).toFixed(2) : '?'} GiB, slope ${out.slopes.wasmMBperMin} MB/min; cycle-2 max ${c2 && c2.maxRendererGiB} GiB vs last-cycle max ${cl && cl.maxRendererGiB} GiB; console ${v.ok ? 'ok' : 'NOT ok'}; ASSERT ${out.assert.pass ? 'PASS' : 'FAIL'}`;
console.log(`SUMMARY ${out.summary}`);
save();
await s.close();
process.exit(out.assert.pass ? 0 : 1);
