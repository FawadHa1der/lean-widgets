// X2 — re-root rehearsal (BUILD-PLAN §3 X2). Overlay out/overlay/snapshots/rehearsal/ holds APFS
// clones of the stock init+mathlib .snapz plus a copy of the stock index. Boot
// /?snapshots=snapshots/rehearsal with the stock EXAMPLES.mathlib (fresh profile => no qed64.buffer),
// then a 2nd visit with the SAME persistent profile must download 0 .snapz bytes (OPFS key
// name.digest16, src/runtime/snapshots.ts:60-71).
import fs from 'node:fs';
import path from 'node:path';
import { SC, ORIGIN, BID, launchPersistent, waitPhase, consoleWatch, netMeter, writeResult, serverLogLength, serverLogSince, summarizeServerLog, sleep } from './lib.mjs';

const OVERLAY = 'snapshots/rehearsal';
const url = `${ORIGIN}/?snapshots=${OVERLAY}`;
const profile = path.join(SC, 'out', 'ux', 'profiles', 'x2');
fs.rmSync(profile, { recursive: true, force: true });
fs.mkdirSync(profile, { recursive: true });

async function visit(n) {
  const ctx = await launchPersistent(profile);
  const page = ctx.pages()[0] || await ctx.newPage();
  const watch = consoleWatch(page);
  const net = netMeter(page);
  const logFrom = serverLogLength();
  const t0 = Date.now();
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
    const coi = await page.evaluate(() => crossOriginIsolated);
    const w = await waitPhase(page, /^ready$/, { timeoutMs: 300000 });
    await sleep(1500); // let trailing requests finish and be logged
    const s = w.status || {};
    const extra = await page.evaluate(() => ({
      text0: globalThis.qed64.editor.getModel().getValue().split('\n')[0],
      stats: globalThis.qed64.relay.stats,
      snapIndex: (globalThis.qed64.artifacts.snapshots?.snapshots || globalThis.qed64.artifacts.snapshots || null),
      boot: document.getElementById('boot')?.className ?? null,
      pill: document.getElementById('ptext')?.textContent ?? null,
    })).catch((e) => ({ err: String(e) }));
    const srv = summarizeServerLog(serverLogSince(logFrom).lines);
    const unpaired = [...watch.tail, ...watch.errors, ...watch.pageErrors].some((l) => /SNAPSHOT_UNPAIRED/.test(l));
    return {
      visit: n, coi, bootMs: Date.now() - t0, readyMs: w.ms, phase: s.phase, header: s.header, phases: w.phases,
      timedOut: !!w.timedOut, failed: !!w.failed, lastDeath: s.lastDeath ?? null, session: s.session ?? null,
      unpaired, crashed: watch.crashed, pageErrors: watch.pageErrors, consoleErrors: watch.errors.slice(0, 10),
      firstLine: extra.text0, pill: extra.pill, stats: extra.stats,
      snapshotUrls: Array.isArray(extra.snapIndex) ? extra.snapIndex.map((e) => e.url) : extra.snapIndex,
      server: { requests: srv.requests, bytes: srv.bytes, snapzBytes: srv.snapzBytes, status: srv.status, snapz: srv.snapz },
      page: { byPrefix: net.byPrefix, requests: net.requests.length },
    };
  } finally {
    await ctx.close();
  }
}

const v1 = await visit(1);
console.log(JSON.stringify({ ...v1, phases: undefined }, null, 1));
await sleep(3000);
const v2 = await visit(2);
console.log(JSON.stringify({ ...v2, phases: undefined }, null, 1));
const okVisit = (v) => v.coi && v.phase === 'ready' && ['covered', 'exact'].includes(v.header?.mode) && !v.unpaired && !v.crashed;
const pass = okVisit(v1) && okVisit(v2) && v1.server.snapzBytes > 0 && v2.server.snapzBytes === 0
  && v1.server.snapz.every((l) => l.includes(`/${OVERLAY}/`));
writeResult('x2', { pass, url, buildId: BID, criteria: 'ready; header covered|exact; no SNAPSHOT_UNPAIRED; visit1 snapz fetched from overlay; visit2 0 snapz bytes', visit1: v1, visit2: v2 });
process.exit(pass ? 0 : 1);
