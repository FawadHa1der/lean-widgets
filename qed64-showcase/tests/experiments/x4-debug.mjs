// X4 debugging aid: boot case (a), click the Try-this link, and record full page-error stacks,
// postMessage traffic between the InfoView iframe and the page, and the editor model/URI state.
import fs from 'node:fs';
import path from 'node:path';
import { SC, ORIGIN, launch, waitPhase, sleep } from './lib.mjs';
const DOC = 'example (n : Nat) : n + 0 = n := by simp?\n';
const browser = await launch();
const out = { errors: [], console: [] };
try {
  const ctx = await browser.newContext();
  await ctx.addInitScript((t) => {
    try { if (!sessionStorage.getItem('s')) { localStorage.setItem('qed64.buffer', t); sessionStorage.setItem('s', '1'); } } catch {}
    // record every message the page window receives (InfoView -> page RPC)
    if (window.top === window) {
      window.__msgs = [];
      window.addEventListener('message', (e) => { try { const d = typeof e.data === 'string' ? e.data : JSON.stringify(e.data); if (/applyEdit|insertText|showDocument/.test(d)) window.__msgs.push({ t: Date.now(), d: d.slice(0, 1500) }); } catch {} }, true);
    }
  }, DOC);
  const page = await ctx.newPage();
  page.on('pageerror', (e) => out.errors.push({ t: Date.now(), msg: String(e.message).slice(0, 500), stack: String(e.stack || '').slice(0, 3000) }));
  page.on('console', (m) => { if (m.type() !== 'log' || !/\[qed64\] ready/.test(m.text())) out.console.push(`${m.type()}: ${m.text().slice(0, 500)}`); });
  await page.goto(`${ORIGIN}/`, { waitUntil: 'domcontentloaded' });
  await waitPhase(page, /^ready$/);
  out.model = await page.evaluate(() => { const e = globalThis.qed64.editor; const m = e.getModel(); return { uri: m.uri.toString(), lang: m.getLanguageId(), version: m.getVersionId() }; });
  await page.evaluate(() => { const e = globalThis.qed64.editor; e.setPosition({ lineNumber: 1, column: 38 }); e.focus(); });
  const iv = page.frameLocator('#infoview iframe');
  const link = iv.locator('span.link.pointer.dim.font-code').first();
  await link.waitFor({ timeout: 30000 });
  await sleep(1000);
  out.errorsBeforeClick = out.errors.length;
  out.tClick = Date.now();
  await link.click();
  await sleep(4000);
  out.msgs = await page.evaluate(() => window.__msgs);
  out.text = await page.evaluate(() => globalThis.qed64.editor.getModel().getValue());
} finally { await browser.close(); }
fs.writeFileSync(path.join(SC, 'out/experiments/x4-debug.json'), JSON.stringify(out, null, 1));
console.log(JSON.stringify(out, null, 1).slice(0, 12000));
