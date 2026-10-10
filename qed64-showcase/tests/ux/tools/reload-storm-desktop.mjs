// The L9 reload storm for any browser mode and either entry point (final-gate lane, 2026-10-02). It is
// tests/ux/tools/reload-storm.mjs with its hot path UNCHANGED (fresh profile; boot to ready; reloads at 0/3/6/9/12 s with
// waitUntil 'commit'; then up to 120 s for ready again; a crash is Playwright's page 'crash' event), plus what the
// l9-desktop lane's storm-desktop2.mjs / storm-desktop3.mjs added (moved here from $W/l9-desktop as docs/NEXT-STEPS.md
// asked), plus the /showcase/ entry point:
//   --channel <name> / --headed   browser selection (no flag: chrome-headless-shell, the UX suite's browser; --headed:
//                                 Chrome for Testing in a real window; --channel chromium without --headed: new headless)
//   --entry stock|showcase        stock: the stock QED64 page with our region, /?snapshots=snapshots/widgets8 (as
//                                 reload-storm.mjs); showcase: the visitor's path /showcase/ (the gallery iframes the
//                                 stock page from the same origin, so both share one renderer); ready = the gallery's
//                                 __showcase.status().phase === 'ready' (QED64 ready AND the first example elaborated)
//   --path <p>                    any other path (overrides --entry)
//   wall-clock epochs of every reload, of ready and of the crash (an external RSS sampler, a separate process, is lined
//   up afterwards; no `ps` runs between ready and the reloads, which would delay reload 0: l9-desktop RESULTS.md)
// Run it under the host browser lock with DEBUG=pw:browser (the V8 OOM line that tells V1 from V2 is in the browser's
// stderr). Writes out/ux/$UX_RUN/explore/reload-storm-<tag>.json.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { launch, RUN_DIR, sleep, OVERLAY_W8, BOOT_WAITED_RE, RUNTIME_START_RE, pageLines } from '../lib/qed64.mjs';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const ORIGIN = arg('--origin', 'http://localhost:5190');
const TAG = arg('--tag', 'run');
const CHANNEL = arg('--channel', undefined);
const HEADED = process.argv.includes('--headed');
const ENTRY = arg('--entry', 'stock');
if (!['stock', 'showcase'].includes(ENTRY)) throw new Error(`--entry ${ENTRY}: want stock or showcase`);
const PATH = arg('--path', ENTRY === 'showcase' ? '/showcase/' : `/?snapshots=snapshots/${OVERLAY_W8}`); // the pin's served widgets8 directory
const URL = `${ORIGIN}${PATH}`;
const GALLERY = /^\/showcase\//.test(PATH);
const mode = HEADED ? 'headed' : (CHANNEL ? `${CHANNEL}-new-headless` : 'headless-shell');
const out = { tag: TAG, url: URL, entry: GALLERY ? 'showcase' : 'stock', mode, channel: CHANNEL || null, headed: HEADED, startedAt: new Date().toISOString() };
const s = await launch({ title: `reload-storm-desktop ${TAG}`, file: 'tools/reload-storm-desktop.mjs' }, { profile: 'fresh', label: `storm-${TAG}`, headed: HEADED, channel: CHANNEL });
const page = s.page() || await s.newPage();
const t0 = Date.now(); out.t0Epoch = t0;
const workers = [];
page.on('worker', (w) => { const r = { t: Date.now() - t0, url: w.url().replace(/^https?:\/\/localhost:\d+/, '').slice(0, 60), closed: null }; workers.push(r); w.on('close', () => { r.closed = Date.now() - t0; }); });
let crashed = null; page.on('crash', () => { crashed = Date.now() - t0; });
const alive = () => workers.filter((w) => w.closed === null).length;
// stock: qed64.status() of the page; showcase: the gallery's phase, plus qed64.status() of its same-origin iframe
const status = () => page.evaluate((gallery) => {
  try {
    if (!gallery) { const s = window.qed64 && window.qed64.status(); return s ? { phase: s.phase, relay: s.relay, pool: s.pool } : null; }
    const g = window.__showcase && window.__showcase.status();
    const f = document.querySelector('iframe'); let q = null;
    try { q = f && f.contentWindow && f.contentWindow.qed64 && f.contentWindow.qed64.status(); } catch { q = null; }
    return g ? { phase: g.phase, current: g.current, qed64Phase: q ? q.phase : null, relay: q ? q.relay : null, pool: q ? q.pool : null } : null;
  } catch { return null; }
}, GALLERY).catch(() => null);
const waitReady = async (ms) => { const t = Date.now(); for (;;) { if (crashed !== null) return null; const st = await status(); if (st && st.phase === 'ready') return Date.now() - t; if (Date.now() - t > ms) return null; await sleep(250); } };
const samples = []; let sampling = true;
(async () => { while (sampling) { samples.push({ t: Date.now() - t0, alive: alive(), created: workers.length }); await sleep(250); } })();
try {
  await page.goto(URL, { waitUntil: 'domcontentloaded' });
  out.firstReadyMs = await waitReady(180000);
  out.readyEpoch = out.firstReadyMs === null ? null : Date.now();
  out.atFirstReady = { alive: alive(), created: workers.length, status: await status() };
  console.log(`[${TAG}] first ready ${out.firstReadyMs} ms; workers alive ${out.atFirstReady.alive} (created ${out.atFirstReady.created}); ${JSON.stringify(out.atFirstReady.status)}`);
  const ts = Date.now(); out.reloads = [];
  for (let i = 0; i < 5 && crashed === null; i++) {
    if (i) await sleep(Math.max(0, i * 3000 - (Date.now() - ts)));
    const r = { i, at: Date.now() - ts, tRun: Date.now() - t0, aliveBefore: alive() };
    try { await page.reload({ waitUntil: 'commit' }); r.ok = true; } catch (e) { r.ok = false; r.error = String(e.message).split('\n')[0].slice(0, 120); }
    out.reloads.push(r);
    console.log(`[${TAG}] reload ${i} at ${r.at} ms: alive before ${r.aliveBefore} ${r.ok ? '' : r.error}`);
  }
  out.readyAfterMs = crashed === null ? await waitReady(120000) : null;
} catch (e) { out.error = String(e.message).split('\n')[0].slice(0, 200); }
sampling = false; await sleep(300);
out.crashedAtMs = crashed; out.crashEpoch = crashed === null ? null : t0 + crashed;
if (crashed !== null) {
  const prev = (out.reloads || []).filter((r) => r.tRun <= crashed);
  out.crashAfterReload = prev.length ? { reloadIndex: prev[prev.length - 1].i, msAfterReload: crashed - prev[prev.length - 1].tRun } : { reloadIndex: null, msAfterReload: null };
}
// the same #55-residual timeline the suite's C10 records (tests/ux/specs/30-robustness.spec.mjs): every '[boot] waited' line
// and runtime start ('[mem] runtime-initialized') of the page, relative to t0 and to the reload sent last before it, and the
// crash against the last of each (QED64 #55 residual; the page logs its worker's stderr as console.debug '[lean:stderr] …')
{
  const sent = (out.reloads || []).map((r) => ({ i: r.i, wall: t0 + r.tRun }));
  const near = (wall) => { const p = sent.filter((r) => r.wall <= wall).pop(); return p ? { reload: p.i, msAfterReload: wall - p.wall } : { reload: null, msAfterReload: null }; };
  out.bootWaited = pageLines(s, BOOT_WAITED_RE, { sinceWall: t0 }).map((x) => { const g = BOOT_WAITED_RE.exec(x.text); return { atMs: x.wall - t0, ...near(x.wall), waitedMs: +g[1], stopping: +g[2], workers: g[3], budgetSpent: !!g[4] }; });
  out.runtimeStarts = pageLines(s, RUNTIME_START_RE, { sinceWall: t0 }).map((x) => ({ atMs: x.wall - t0, ...near(x.wall), mib: +RUNTIME_START_RE.exec(x.text)[1] }));
  const sinceLast = (list, at) => { const e = list.filter((x) => x.atMs <= at).pop(); return e ? at - e.atMs : null; };
  out.crashAt = crashed === null ? null : { atMs: crashed, ...near(t0 + crashed), msSinceLastBootWaited: sinceLast(out.bootWaited, crashed), msSinceLastRuntimeStart: sinceLast(out.runtimeStarts, crashed) };
}
out.peakAlive = Math.max(...samples.map((x) => x.alive));
out.peakAliveAt = (samples.find((x) => x.alive === out.peakAlive) || {}).t;
out.created = workers.length; out.closed = workers.filter((w) => w.closed !== null).length;
out.samples = samples.filter((_, i) => i % 2 === 0);
try { out.browserVersion = s.browser ? s.browser.version() : null; } catch { /* ignore */ }
const bp = (spawnSync('ps', ['-axo', 'pid=,command='], { encoding: 'utf8' }).stdout || '').split('\n').find((l) => /ms-playwright/.test(l) && !/--type=/.test(l));
out.browserCmd = bp ? bp.trim().replace(/\s+/g, ' ').slice(0, 300) : null;
const c = out.crashAfterReload;
out.summary = `${TAG}: crashed ${crashed === null ? 'no' : `at ${crashed} ms (${c.msAfterReload} ms after reload ${c.reloadIndex})`}; first ready ${out.firstReadyMs} ms; peak live workers ${out.peakAlive} at ${out.peakAliveAt} ms; created ${out.created}, closed ${out.closed}; ready after storm ${out.readyAfterMs} ms${out.error ? `; error ${out.error}` : ''}`;
console.log(`SUMMARY ${out.summary}`);
await s.close();
const dir = path.join(RUN_DIR, 'explore'); fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(path.join(dir, `reload-storm-${TAG}.json`), `${JSON.stringify(out, null, 1)}\n`);
