// Exploration probe (re-pin lane, docs/REPIN-LOG.md): the C10 reload storm on the STOCK QED64 page (no gallery, no
// bridge), so two QED64 releases can be compared on the same host and browser. Run under the browser lock:
//   UX_RUN=repin-ab scripts/with-browser-lock.sh repin-ab node tests/ux/tools/reload-storm.mjs --origin http://localhost:5192 --tag old
// Fresh profile; boot to ready; then reloads at 0, 3, 6, 9 and 12 s (waitUntil 'commit', as C10); every 250 ms the
// number of live dedicated workers (page.on('worker') minus 'close', nested pthread workers included); crash; then ready
// again (120 s budget). Writes out/ux/<run>/explore/reload-storm-<tag>.json.
import fs from 'node:fs';
import path from 'node:path';
import { launch, RUN_DIR, sleep } from '../lib/qed64.mjs';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const ORIGIN = arg('--origin', 'http://localhost:5190');
const TAG = arg('--tag', 'run');
const URL = `${ORIGIN}/?snapshots=snapshots/widgets8`;
const out = { tag: TAG, url: URL, startedAt: new Date().toISOString() };
const s = await launch({ title: `reload-storm ${TAG}`, file: 'tools/reload-storm.mjs' }, { profile: 'fresh', label: `storm-${TAG}` });
const page = s.page() || await s.newPage();
const t0 = Date.now();
const workers = [];
page.on('worker', (w) => { const r = { t: Date.now() - t0, url: w.url().replace(/^https?:\/\/localhost:\d+/, '').slice(0, 60), closed: null }; workers.push(r); w.on('close', () => { r.closed = Date.now() - t0; }); });
let crashed = null; page.on('crash', () => { crashed = Date.now() - t0; });
const alive = () => workers.filter((w) => w.closed === null).length;
const status = () => page.evaluate(() => { try { const s = window.qed64 && window.qed64.status(); return s ? { phase: s.phase, relay: s.relay, pool: s.pool } : null; } catch { return null; } }).catch(() => null);
const waitReady = async (ms) => { const t = Date.now(); for (;;) { if (crashed !== null) return null; const st = await status(); if (st && st.phase === 'ready') return Date.now() - t; if (Date.now() - t > ms) return null; await sleep(250); } };
const samples = []; let sampling = true;
(async () => { while (sampling) { samples.push({ t: Date.now() - t0, alive: alive(), created: workers.length }); await sleep(250); } })();
try {
  await page.goto(URL, { waitUntil: 'domcontentloaded' });
  out.firstReadyMs = await waitReady(180000);
  out.atFirstReady = { alive: alive(), created: workers.length, status: await status() };
  console.log(`[${TAG}] first ready ${out.firstReadyMs} ms; workers alive ${out.atFirstReady.alive} (created ${out.atFirstReady.created}); ${JSON.stringify(out.atFirstReady.status)}`);
  const ts = Date.now(); out.reloads = [];
  for (let i = 0; i < 5 && crashed === null; i++) {
    if (i) await sleep(Math.max(0, i * 3000 - (Date.now() - ts)));
    const r = { i, at: Date.now() - ts, aliveBefore: alive() };
    try { await page.reload({ waitUntil: 'commit' }); r.ok = true; } catch (e) { r.ok = false; r.error = String(e.message).split('\n')[0].slice(0, 120); }
    out.reloads.push(r);
    console.log(`[${TAG}] reload ${i} at ${r.at} ms: alive before ${r.aliveBefore} ${r.ok ? '' : r.error}`);
  }
  out.readyAfterMs = crashed === null ? await waitReady(120000) : null;
} catch (e) { out.error = String(e.message).split('\n')[0].slice(0, 200); }
sampling = false; await sleep(300);
out.crashedAtMs = crashed;
out.peakAlive = Math.max(...samples.map((x) => x.alive));
out.peakAliveAt = (samples.find((x) => x.alive === out.peakAlive) || {}).t;
out.created = workers.length; out.closed = workers.filter((w) => w.closed !== null).length;
out.samples = samples.filter((_, i) => i % 2 === 0);
out.summary = `${TAG}: crashed ${crashed === null ? 'no' : `at ${crashed} ms`}; peak live workers ${out.peakAlive} at ${out.peakAliveAt} ms; created ${out.created}, closed ${out.closed}; ready after storm ${out.readyAfterMs} ms`;
console.log(`SUMMARY ${out.summary}`);
await s.close();
const dir = path.join(RUN_DIR, 'explore'); fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(path.join(dir, `reload-storm-${TAG}.json`), `${JSON.stringify(out, null, 1)}\n`);
