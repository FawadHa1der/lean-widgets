// Where does the page's empty console.error come from? Gallery boot + 3 switches; in the QED64 page: every
// console.error (with stack, timestamp), every LSP error reply and every server->client request/notification that is
// not diagnostics/progress (timestamps on the same clock), so the empty error can be correlated with its trigger.
// Usage: scripts/with-browser-lock.sh bringup node tests/ux/bringup/emptyerr.mjs
import { chromium } from 'playwright';
import { ORIGIN, LAUNCH_ARGS, lockHeld, api, waitGalleryReady, writeJson, sleep } from './lib.mjs';

lockHeld();
const browser = await chromium.launch({ args: LAUNCH_ARGS });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
await ctx.addInitScript(() => {
  if (!/\?snapshots=/.test(location.search)) return;
  const rec = (window.__ee = []);
  const o = console.error;
  console.error = function (...a) { rec.push({ t: Math.round(performance.now()), kind: 'console.error', text: a.map((x) => typeof x === 'string' ? x : JSON.stringify(x)).join(' ').slice(0, 200), argTypes: a.map((x) => typeof x), stack: (new Error().stack || '').split('\n').slice(2, 14).map((s) => s.trim()).join(' | ') }); return o.apply(this, a); };
  const tap = setInterval(() => {
    const r = window.qed64 && window.qed64.relay; if (!r) return; clearInterval(tap);
    const tc = r.toClient;
    r.toClient = function (m) {
      try {
        if (m.error) rec.push({ t: Math.round(performance.now()), kind: 'lsp-error', id: m.id, code: m.error.code, message: String(m.error.message).slice(0, 200) });
        else if (m.method && !/publishDiagnostics|fileProgress|\$\/progress|headerStatus/.test(m.method)) rec.push({ t: Math.round(performance.now()), kind: 's2c', method: m.method, params: JSON.stringify(m.params || null).slice(0, 200) });
      } catch { /* ignore */ }
      return tc.apply(this, arguments);
    };
    const fc = r.fromClient;
    r.fromClient = function (m) {
      try { if (m.method && !/\$\/lean\/rpc\/(call|keepAlive)/.test(m.method)) rec.push({ t: Math.round(performance.now()), kind: 'c2s', method: m.method, id: m.id }); } catch { /* ignore */ }
      return fc.apply(this, arguments);
    };
  }, 5);
});
const page = await ctx.newPage();
const res = {};
try {
  await page.goto(`${ORIGIN}/showcase/#chart-kit`, { waitUntil: 'domcontentloaded' });
  await waitGalleryReady(page);
  for (const id of ['tree-scope', 'expr-xray', 'chart-kit']) { await sleep(3000); await api.select(page, id); }
  await sleep(4000);
  res.events = await page.frames().find((f) => /\?snapshots=/.test(f.url())).evaluate(() => window.__ee);
} catch (e) { res.error = String(e.stack || e).slice(0, 800); }
await browser.close();
writeJson('emptyerr.json', res);
for (const e of res.events || []) if (e.kind !== 'c2s' || !/didChange|didOpen|didClose|codeAction|documentSymbol|semantic|inlay|foldingRange|hover/.test(e.method)) console.log(JSON.stringify(e).slice(0, 400));
