// Exploration probe (UX lane): Monaco quick-fix UI for the simp-lens code action (W4c). Under the browser lock.
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { SC, ORIGIN, LAUNCH_ARGS, lockHeld, waitGalleryReady, sleep, api } from '../bringup/lib.mjs';
lockHeld();
const OUT = path.join(SC, 'out/ux/explore'); fs.mkdirSync(OUT, { recursive: true });
const browser = await chromium.launch({ args: LAUNCH_ARGS });
const page = await (await browser.newContext({ viewport: { width: 1440, height: 900 } })).newPage();
page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') console.log('console', m.type(), JSON.stringify(m.text().slice(0, 200))); });
await page.goto(`${ORIGIN}/showcase/#simp-lens`, { waitUntil: 'domcontentloaded' });
const b = await waitGalleryReady(page);
console.log('boot', b.ms, b.s && b.s.phase);
const fr = page.frameLocator('#qed64-frame');
const pe = (fn, a) => page.evaluate(([src, a]) => { const w = document.getElementById('qed64-frame').contentWindow; return new w.Function('arg', `return (${src})(arg);`)(a); }, [fn.toString(), a ?? null]);
console.log('platform', await pe(() => navigator.platform), await pe(() => navigator.userAgent));
await pe(() => { const e = window.qed64.editor; e.setPosition({ lineNumber: 16, column: 47 }); e.focus(); });
await sleep(3000);
await page.screenshot({ path: path.join(OUT, 'ca-0.png') });
const lb = await fr.locator('.codicon-light-bulb, .codicon-lightbulb, .lightBulbWidget, .codicon-lightbulb-autofix').evaluateAll((els) => els.map((e) => ({ cls: e.className, vis: e.getBoundingClientRect().width })));
console.log('lightbulbs', JSON.stringify(lb));
for (const key of ['Meta+Period', 'Control+Period']) {
  await page.keyboard.press(key);
  await sleep(2500);
  const menu = await fr.locator('body').evaluate((body) => {
    const cands = [...body.querySelectorAll('.action-widget, .context-view, .monaco-list, [role=menu], [role=listbox]')];
    return cands.map((c) => ({ cls: String(c.className).slice(0, 80), role: c.getAttribute('role'), text: c.innerText.slice(0, 300), w: c.getBoundingClientRect().width }));
  });
  console.log(key, JSON.stringify(menu));
  await page.screenshot({ path: path.join(OUT, `ca-${key}.png`) });
  if (menu.some((m) => /Try this/.test(m.text))) { console.log('menu opened by', key); break; }
}
const txt0 = await api.text(page);
const items = await fr.locator('.action-widget .monaco-list-row, [role=option], [role=menuitem]').evaluateAll((els) => els.map((e) => ({ cls: String(e.className).slice(0, 60), role: e.getAttribute('role'), text: e.innerText.slice(0, 120), aria: e.getAttribute('aria-label') })));
console.log('items', JSON.stringify(items));
fs.writeFileSync(path.join(OUT, 'ca-dom.html'), await fr.locator('body').evaluate((b) => { const w = b.querySelector('.action-widget') || b.querySelector('.context-view'); return w ? w.outerHTML : 'none'; }));
await page.keyboard.press('Enter');
await sleep(2500);
const txt1 = await api.text(page);
console.log('changed', txt0 !== txt1, JSON.stringify((txt1 || '').split('\n')[15]));
await browser.close();
