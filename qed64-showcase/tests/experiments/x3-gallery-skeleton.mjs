// X3 — M2 skeleton (BUILD-PLAN §3 X3): /showcase/x3.html seeds qed64.buffer, iframes
// /?snapshots=snapshots/rehearsal, reaches contentWindow.qed64, then switches with setValue.
import fs from 'node:fs';
import path from 'node:path';
import { SC, ORIGIN, launchPersistent, consoleWatch, writeResult, sleep } from './lib.mjs';

// warm profile from X2 (OPFS already holds the rehearsal regions) unless X3_COLD=1
const profile = path.join(SC, 'out', 'ux', 'profiles', process.env.X3_COLD ? 'x3-cold' : 'x2');
if (process.env.X3_COLD) fs.rmSync(profile, { recursive: true, force: true });
const ctx = await launchPersistent(profile);
let res;
try {
  const page = ctx.pages()[0] || await ctx.newPage();
  const watch = consoleWatch(page);
  await page.goto(`${ORIGIN}/showcase/x3.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => window.__x3?.done, null, { timeout: 420000, polling: 500 });
  res = await page.evaluate(() => window.__x3);
  await sleep(500);
  await page.screenshot({ path: path.join(SC, 'out', 'experiments', 'x3.png') });
  res.crashed = watch.crashed; res.pageErrors = watch.pageErrors; res.consoleErrors = watch.errors.slice(0, 10);
} finally { await ctx.close(); }
const pass = !!(res.ok && res.iframeCrossOriginIsolated === true && res.first?.phase === 'ready'
  && ['covered', 'exact'].includes(res.first?.header?.mode) && res.first.snapshots.includes('mathlib')
  && res.switched?.phase === 'ready' && ['covered', 'exact'].includes(res.switched?.header?.mode) && !res.crashed);
console.log(JSON.stringify(res, null, 1));
writeResult('x3', { pass, profile: path.relative(SC, profile), criteria: 'iframe crossOriginIsolated; seeded header boots [init,mathlib] and is covered; setValue switch reaches ready at an advanced version', ...res });
process.exit(pass ? 0 : 1);
