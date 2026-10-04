// Trace which LSP/RPC requests the InfoView sends after the cursor lands on a widget command, against the pthread
// pool (status().pool) sampled every 100 ms. Stock page top-level, bridge by init script (as X4), fresh boot.
// Usage: scripts/with-browser-lock.sh bringup node tests/ux/bringup/rpctrace.mjs --tag t --id hasse-view [--line 18] [--bridge init|none]
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { SC, ORIGIN, LAUNCH_ARGS, EXAMPLES, lockHeld, watchConsole, writeJson, sleep, chromeRss } from './lib.mjs';

lockHeld();
const argv = process.argv.slice(2);
const opt = (k, d = null) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const tag = opt('tag', 'rpctrace');
const ex = EXAMPLES.find((e) => e.id === opt('id', 'hasse-view'));
const line = Number(opt('line', ex.firstCursor.lineNumber));
const bridge = opt('bridge', 'init');
const BRIDGE_SRC = fs.readFileSync(path.join(SC, 'gallery/qed64-bridge.js'), 'utf8');
const t0 = Date.now();
const ctx = await chromium.launchPersistentContext(path.join(SC, 'out/ux/profiles/bringup'), { args: LAUNCH_ARGS, viewport: { width: 1440, height: 900 } });
const page = ctx.pages()[0] || await ctx.newPage();
const watch = watchConsole(page, t0, `${tag}.console.jsonl`);
if (bridge === 'init') await ctx.addInitScript({ content: `${BRIDGE_SRC}\nif (window.top === window) window.installQed64Bridge(window);` });
const res = { tag, id: ex.id, line, bridge };
try {
  await page.goto(`${ORIGIN}/showcase/pin.json`);
  await page.evaluate((t) => localStorage.setItem('qed64.buffer', t), ex.text);
  await page.goto(`${ORIGIN}/?snapshots=snapshots/widgets8`, { waitUntil: 'domcontentloaded' });
  for (;;) { const s = await page.evaluate(() => globalThis.qed64 && globalThis.qed64.status()).catch(() => null); if (s && s.phase === 'ready') break; await sleep(200); }
  await sleep(1500);
  await page.evaluate(() => {
    const r = globalThis.qed64.relay; const T0 = performance.now();
    globalThis.__trace = [];
    const fc = r.fromClient.bind(r);
    r.fromClient = (m) => { try { const p = m.params || {}; globalThis.__trace.push({ t: Math.round(performance.now() - T0), dir: 'c2s', id: m.id ?? null, method: m.method, rpc: p.method || null }); } catch {} return fc(m); };
    const tc = r.toClient.bind(r);
    r.toClient = (m) => { try { if (m.id !== undefined && !m.method) globalThis.__trace.push({ t: Math.round(performance.now() - T0), dir: 's2c', id: m.id, err: m.error ? String(m.error.message).slice(0, 80) : null }); } catch {} return tc(m); };
    globalThis.__pool = [];
    setInterval(() => { const s = globalThis.qed64.status(); globalThis.__pool.push({ t: Math.round(performance.now() - T0), ...s.pool }); }, 100);
  });
  res.before = await page.evaluate(() => globalThis.qed64.status().pool);
  await page.evaluate((l) => { const e = globalThis.qed64.editor; e.setPosition({ lineNumber: l, column: 1 }); e.focus(); }, line);
  await sleep(8000);
  res.after = await page.evaluate(() => globalThis.qed64.status().pool);
} catch (e) { res.error = String(e && e.message || e).slice(0, 400); }
res.trace = await page.evaluate(() => globalThis.__trace).catch(() => null);
res.pool = await page.evaluate(() => { const p = globalThis.__pool; return p.filter((x, i) => i === 0 || x.running !== p[i - 1].running || x.unused !== p[i - 1].unused); }).catch(() => null);
res.bridgeStats = await page.evaluate(() => globalThis.__qed64Bridge).catch(() => null);
res.crashed = watch.crashed; res.rss = chromeRss(); res.workers = watch.workers.length;
writeJson(`${tag}.json`, res);
await ctx.close().catch(() => {});
process.exit(0);
