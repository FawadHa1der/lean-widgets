// Exploratory first boot of /showcase/ (default overlay): status, bridge installs, console, and the InfoView DOM
// outline for every example's first cursor. Output: out/ux/bringup/explore.json + explore-<id>.png
// Usage: scripts/with-browser-lock.sh bringup node tests/ux/bringup/explore.mjs [--profile <dir>]
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { SC, ORIGIN, OUT, LAUNCH_ARGS, EXAMPLES, lockHeld, watchConsole, api, infoview, ivText, ivSettled, waitGalleryReady, writeJson, sleep, chromeRss } from './lib.mjs';

lockHeld();
const argv = process.argv.slice(2);
const profIdx = argv.indexOf('--profile');
const profile = profIdx >= 0 ? path.resolve(argv[profIdx + 1]) : null;
const t0 = Date.now();
const ctx = profile
  ? await chromium.launchPersistentContext(profile, { args: LAUNCH_ARGS, viewport: { width: 1440, height: 900 } })
  : await (await chromium.launch({ args: LAUNCH_ARGS })).newContext({ viewport: { width: 1440, height: 900 } });
const res = { profile, examples: {} };
try {
  const page = ctx.pages()[0] || await ctx.newPage();
  const watch = watchConsole(page, t0);
  await page.goto(`${ORIGIN}/showcase/`, { waitUntil: 'domcontentloaded' });
  const r = await waitGalleryReady(page);
  res.boot = { ms: r.ms, timedOut: !!r.timedOut, status: r.s };
  res.bridgeAtBoot = await api.bridge(page);
  res.rssAtReady = chromeRss();
  for (const ex of EXAMPLES) {
    const e = {};
    const t1 = Date.now();
    if (ex.id !== r.s.current) { const s = await api.select(page, ex.id); e.select = { ok: s.ok, code: s.code || null, message: s.message || null, ms: Date.now() - t1 }; }
    await sleep(1500);
    e.settled = await ivSettled(page, { timeoutMs: 90000 });
    await sleep(800);
    e.ivText = (await ivText(page)).slice(0, 3000);
    e.outline = await infoview(page).locator('body').evaluate((b) => {
      const lines = [];
      const walk = (n, d) => {
        if (d > 9 || lines.length > 160) return;
        for (const c of n.children) {
          const cls = typeof c.className === 'string' ? c.className : (c.className && c.className.baseVal) || '';
          const r = c.getBoundingClientRect();
          lines.push(`${'  '.repeat(d)}${c.tagName.toLowerCase()}${c.id ? '#' + c.id : ''}${cls ? '.' + cls.trim().split(/\s+/).join('.') : ''} [${Math.round(r.x)},${Math.round(r.y)} ${Math.round(r.width)}x${Math.round(r.height)}]${c.children.length === 0 ? ' "' + (c.textContent || '').slice(0, 40) + '"' : ''}`);
          if (c.tagName.toLowerCase() !== 'svg') walk(c, d + 1);
        }
      };
      walk(b, 0);
      return lines;
    }).catch((err) => [`outline failed: ${err.message}`]);
    e.unrecognised = /Unrecognised error|abortSignal/.test(e.ivText);
    e.status = await api.status(page);
    e.bridge = await api.bridge(page);
    await page.screenshot({ path: path.join(OUT, `explore-${ex.id}.png`) });
    res.examples[ex.id] = e;
    console.log(ex.id, JSON.stringify({ sel: e.select, settled: e.settled, unrecognised: e.unrecognised, phase: e.status.phase, q: e.status.qed64 && e.status.qed64.phase, stripped: e.bridge && e.bridge.stripped }));
  }
  res.rssAfterAll = chromeRss();
  res.console = { messages: watch.messages, pageErrors: watch.pageErrors, crashed: watch.crashed };
} finally {
  res.wallMs = Date.now() - t0;
  writeJson('explore.json', res);
  await ctx.close();
  const b = ctx.browser && ctx.browser(); if (b) await b.close().catch(() => {});
}
