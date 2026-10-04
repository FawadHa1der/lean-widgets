// Dump the InfoView goal-view DOM at a cursor (selector discovery for shift-click selections).
// Usage: scripts/with-browser-lock.sh bringup node tests/ux/bringup/goaldom.mjs <id> <line> <col>
import { chromium } from 'playwright';
import { ORIGIN, LAUNCH_ARGS, lockHeld, infoview, waitGalleryReady, writeJson, sleep, ivSettled } from './lib.mjs';
lockHeld();
const [id, line, col] = process.argv.slice(2);
const browser = await chromium.launch({ args: LAUNCH_ARGS });
const page = await (await browser.newContext({ viewport: { width: 1440, height: 900 } })).newPage();
await page.goto(`${ORIGIN}/showcase/#${id}`, { waitUntil: 'domcontentloaded' });
await waitGalleryReady(page);
await page.evaluate(([l, c]) => { const e = document.getElementById('qed64-frame').contentWindow.qed64.editor; e.setPosition({ lineNumber: +l, column: +c }); e.focus(); }, [line, col]);
await sleep(1500); await ivSettled(page);
const html = await infoview(page).locator('body').evaluate((b) => {
  const g = b.querySelector('.goal') || b.querySelector('div:has(> .goal-vdash)') || b;
  return { goalClass: g.className, html: g.outerHTML.replace(/\s+/g, ' ').slice(0, 6000), hypsClasses: [...new Set([...b.querySelectorAll('[class]')].map((e) => e.className).filter((c) => typeof c === 'string' && /hyp|goal|vdash|selected|highlight/.test(c)))] };
});
writeJson(`goaldom-${id}-${line}.json`, html);
await browser.close();
