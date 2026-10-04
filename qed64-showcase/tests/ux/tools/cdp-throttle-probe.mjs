// Which CDP network-emulation call reaches a DEDICATED WORKER's fetch? (last-mile lane, 2026-10-03). QED64's lean worker
// downloads the runtime and the snapshots itself; Network.emulateNetworkConditions in a worker's own session answers
// "Not supported" and a page-level call leaves worker fetches unthrottled (throttle-t50). For each variant this opens a
// fresh page on --origin, applies the variant, starts a dedicated worker that fetches --file (no cache), and times it.
//   UX_RUN=<run> scripts/with-browser-lock.sh <lane> node tests/ux/tools/cdp-throttle-probe.mjs --origin http://localhost:5197
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { LAUNCH_ARGS, RUN_DIR, lockHeld, cooldown } from '../lib/qed64.mjs';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const ORIGIN = arg('--origin', 'http://localhost:5197'); const PORT = Number(arg('--cdp-port', '9341'));
// default: the first lean.js chunk the served runtime manifest names (16 MiB); no pin-specific name in this file
const FILE = arg('--file', null) || (await (await fetch(`${ORIGIN}/runtime/runtime-manifest.json`)).json()).files['lean.js'].chunks[0].url;
const MBPS = 50; const BPS = (MBPS * 1e6) / 8; const RTT = 40;
lockHeld(); await cooldown();
const browser = await chromium.launch({ args: [...LAUNCH_ARGS, `--remote-debugging-port=${PORT}`] });
const ver = await (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json();
const proto = await (await fetch(`http://127.0.0.1:${PORT}/json/protocol`)).json();
const net = proto.domains.find((d) => d.domain === 'Network');
const out = { browser: ver.Browser, origin: ORIGIN, file: FILE, link: { MBPS, RTT }, protocol: net.commands.filter((c) => /emulateNetwork|overrideNetworkState|Throttl/i.test(c.name)).map((c) => ({ name: c.name, experimental: !!c.experimental, params: (c.parameters || []).map((p) => p.name) })), variants: [] };
const ws = new WebSocket(ver.webSocketDebuggerUrl); await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
let id = 0; const pend = new Map(); const attached = [];
const send = (method, params = {}, sessionId) => new Promise((res, rej) => { const i = ++id; pend.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method, params, ...(sessionId ? { sessionId } : {}) })); });
let onAttach = null;
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { const p = pend.get(m.id); pend.delete(m.id); m.error ? p.rej(new Error(m.error.message)) : p.res(m.result); return; } if (m.method === 'Target.attachedToTarget') { attached.push(m.params); if (onAttach) onAttach(m.params, m.sessionId); } };
const cond = { offline: false, latency: RTT, downloadThroughput: BPS, uploadThroughput: BPS };
const rule = { offline: false, matchedNetworkConditions: [{ urlPattern: '', latency: RTT, downloadThroughput: BPS, uploadThroughput: BPS }] };
const variants = [
  { name: 'none (control)', page: null, worker: null },
  { name: 'page emulateNetworkConditions', page: ['Network.emulateNetworkConditions', cond], worker: null },
  { name: 'page emulateNetworkConditionsByRule', page: ['Network.emulateNetworkConditionsByRule', rule], worker: null },
  { name: 'page + worker emulateNetworkConditionsByRule', page: ['Network.emulateNetworkConditionsByRule', rule], worker: ['Network.emulateNetworkConditionsByRule', rule] },
];
await send('Target.setAutoAttach', { autoAttach: true, waitForDebuggerOnStart: true, flatten: true });
for (const v of variants) {
  const rec = { name: v.name, errors: [] };
  const ctx = await browser.newContext();
  onAttach = async (p, parent) => {
    const sid = p.sessionId; const t = p.targetInfo.type; console.log(`  attached ${t} ${p.targetInfo.url.slice(0, 60)} waiting=${p.waitingForDebugger}`);
    try {
      if (t === 'page') { await send('Network.enable', {}, sid).catch((e) => rec.errors.push(`page enable: ${e.message}`)); if (v.page) await send(v.page[0], v.page[1], sid).catch((e) => rec.errors.push(`page ${v.page[0]}: ${e.message}`)); await send('Target.setAutoAttach', { autoAttach: true, waitForDebuggerOnStart: true, flatten: true }, sid); }
      if (t === 'worker') { await send('Network.enable', {}, sid).catch((e) => rec.errors.push(`worker enable: ${e.message}`)); if (v.worker) await send(v.worker[0], v.worker[1], sid).catch((e) => rec.errors.push(`worker ${v.worker[0]}: ${e.message}`)); }
    } finally { if (p.waitingForDebugger) await send('Runtime.runIfWaitingForDebugger', {}, sid).catch(() => {}); }
  };
  console.log(`  variant ${v.name}: newPage`);
  const page = await ctx.newPage();
  await page.waitForTimeout(300);
  console.log('  goto');
  await page.goto(`${ORIGIN}/showcase/pin.json`, { timeout: 30000 });
  console.log('  evaluate');
  const r = await page.evaluate(async (file) => {
    const src = `onmessage = async (e) => { const t = performance.now(); const r = await fetch(e.data, { cache: 'no-store' }); const b = await r.arrayBuffer(); postMessage({ bytes: b.byteLength, ms: performance.now() - t }); };`;
    const w = new Worker(URL.createObjectURL(new Blob([src], { type: 'text/javascript' })));
    const res = await new Promise((ok) => { w.onmessage = (e) => ok(e.data); w.onerror = (e) => ok({ bytes: 0, ms: 1, error: String(e.message) }); w.postMessage(file); setTimeout(() => ok({ bytes: 0, ms: 1, error: 'worker timeout 60 s' }), 60000); });
    const t = performance.now(); const pr = await fetch(file, { cache: 'no-store' }); const pb = await pr.arrayBuffer();
    return { worker: res, page: { bytes: pb.byteLength, ms: performance.now() - t } };
  }, FILE);
  rec.workerMbps = +((r.worker.bytes * 8) / (r.worker.ms * 1000)).toFixed(1); rec.pageMbps = +((r.page.bytes * 8) / (r.page.ms * 1000)).toFixed(1);
  rec.workerError = r.worker.error || null; rec.workerMs = Math.round(r.worker.ms); rec.pageMs = Math.round(r.page.ms); rec.bytes = r.worker.bytes;
  out.variants.push(rec);
  console.log(`VARIANT ${v.name}: worker ${rec.workerMbps} Mbit/s (${rec.workerMs} ms), page ${rec.pageMbps} Mbit/s (${rec.pageMs} ms) ${rec.errors.length ? `errors ${rec.errors.join('; ')}` : ''}`);
  await ctx.close();
}
console.log(`PROTOCOL ${JSON.stringify(out.protocol)}`);
fs.mkdirSync(path.join(RUN_DIR, 'explore'), { recursive: true });
fs.writeFileSync(path.join(RUN_DIR, 'explore', 'cdp-throttle-probe.json'), `${JSON.stringify(out, null, 1)}\n`);
ws.close(); await browser.close();
