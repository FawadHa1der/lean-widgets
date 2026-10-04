// X5 — memory-knob contingency (BUILD-PLAN §3 X5). From the same origin, wrap
// qed64.relay.makeSession (an instance property: lsp-relay.ts:76-90) so every new ResidentSession
// gets initialBytes = 3 GiB (resident-session.ts:118,128,187; `readonly` is TS-only), then
// relay.restart({snapshots:['init','mathlib']}). Pass = telemetry shows a 3 GiB initial commit.
import { spawnSync } from 'node:child_process';
import { ORIGIN, launch, waitPhase, writeResult, sleep } from './lib.mjs';

const GiB = 2 ** 30;
const TARGET = 3 * GiB;
const rss = () => {
  const ps = spawnSync('ps', ['-axo', 'rss=,command='], { encoding: 'utf8' }).stdout || '';
  let kb = 0; for (const l of ps.split('\n')) if (/chrome-headless-shell/.test(l)) kb += Number(l.trim().split(/\s+/)[0]) || 0;
  return +(kb / 1024 / 1024).toFixed(2); // GiB
};
const browser = await launch();
const res = { memLog: [] };
try {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  page.on('console', (m) => { const t = m.text(); if (/\[mem\]|reserv|Memory|initialBytes/i.test(t)) res.memLog.push(`${((Date.now() - t0) / 1000).toFixed(1)}s ${t.slice(0, 200)}`); });
  const t0 = Date.now();
  await page.goto(`${ORIGIN}/`, { waitUntil: 'domcontentloaded' }); // stock pair, EXAMPLES.mathlib
  const w1 = await waitPhase(page, /^ready$/);
  const tel = () => page.evaluate(async () => {
    const s = globalThis.qed64.relay.session;
    const t = await s.lean.request('telemetry');
    return { session: s.id, snapshots: [...s.snapshots], initialBytes: s.initialBytes, maximumBytes: s.maximumBytes, memory: t?.memory ?? t?.result?.memory ?? null, state: t?.state ?? null };
  });
  res.baseline = { phase: w1.status?.phase, readyMs: w1.ms, ...(await tel()), rssGiB: rss() };
  console.log('baseline', JSON.stringify(res.baseline));
  // the knob: wrap makeSession on the instance
  res.wrap = await page.evaluate((target) => {
    const r = globalThis.qed64.relay;
    const own = Object.prototype.hasOwnProperty.call(r, 'makeSession');
    const orig = r.makeSession;
    r.makeSession = (opts) => { const s = orig(opts); s.initialBytes = target; return s; };
    return { ownProperty: own, type: typeof orig };
  }, TARGET);
  const sessBefore = res.baseline.session;
  const tR = Date.now();
  await page.evaluate(() => globalThis.qed64.relay.restart({ snapshots: ['init', 'mathlib'] }));
  // wait for a NEW session to reach ready
  let w2;
  for (let i = 0; i < 600; i++) {
    w2 = await waitPhase(page, /^ready$/, { timeoutMs: 5000 });
    if (w2.status?.phase === 'ready' && w2.status.session !== sessBefore) break;
    await sleep(500);
  }
  res.restartMs = Date.now() - tR;
  res.after = { phase: w2.status?.phase, ...(await tel()), stats: await page.evaluate(() => ({ ...globalThis.qed64.relay.stats })), rssGiB: rss() };
  console.log('after', JSON.stringify(res.after));
  await ctx.close();
} finally { await browser.close(); }
const cur = res.after?.memory?.currentBytes;
res.initialBytesChanged = res.after?.initialBytes === TARGET && res.baseline?.initialBytes === 2 * GiB;
const pass = !!(res.wrap?.ownProperty && res.after?.phase === 'ready' && res.after.session !== res.baseline.session
  && res.initialBytesChanged && cur >= TARGET && res.memLog.some((l) => /runtime-initialized: 3072 MiB/.test(l)));
console.log(res.memLog.join('\n'));
writeResult('x5', { pass, target: TARGET, criteria: 'new session initialBytes == 3 GiB, worker reports runtime-initialized 3072 MiB, telemetry currentBytes >= 3 GiB, ready', ...res });
process.exit(pass ? 0 : 1);
