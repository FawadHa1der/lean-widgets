// Exploration probe (UX lane): dump the InfoView info-block DOM at given positions, to design the DOM signature
// comparator of tests/ux/lib/qed64.mjs. Usage (under the browser lock):
//   node tests/ux/tools/domprobe.mjs <pkg>@<line0>:<char0>[,<line0>:<char0>...] [<pkg>@...]
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { SC, ORIGIN, LAUNCH_ARGS, lockHeld, infoview, waitGalleryReady, sleep, ivSettled } from '../bringup/lib.mjs';
lockHeld();
const jobs = process.argv.slice(2).map((a) => a.split('@'));
const id = jobs[0][0];
const OUT = path.join(SC, 'out/ux/explore'); fs.mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch({ args: LAUNCH_ARGS });
const page = await (await browser.newContext({ viewport: { width: 1440, height: 900 } })).newPage();
await page.goto(`${ORIGIN}/showcase/#${id}`, { waitUntil: 'domcontentloaded' });
const b = await waitGalleryReady(page);
console.log('boot', b.ms, b.s && b.s.phase);
for (const [id, posArg] of jobs) {
 const sel = await page.evaluate((i) => window.__showcase.select(i).then(() => 'ok', (e) => String(e)), id);
 console.log('select', id, sel);
 for (const p of posArg.split(',')) {
  const [l, c] = p.split(':').map(Number);
  await page.evaluate(([l, c]) => { const e = document.getElementById('qed64-frame').contentWindow.qed64.editor; e.setPosition({ lineNumber: l + 1, column: c + 1 }); }, [l, c]);
  await sleep(2500); await ivSettled(page); await sleep(1500);
  const html = await infoview(page).locator('body').evaluate((body) => body.innerHTML);
  const f = path.join(OUT, `dom-${id}-${l}-${c}.html`);
  fs.writeFileSync(f, html);
  console.log('wrote', f, html.length);
 }
}
await browser.close();
