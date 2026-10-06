// Console / page-error census for the bridge install modes (stage-A auditor note: "installing the bridge from the
// parent window produced three page errors instead of one"). Every console.error/warn and window 'error' is
// recorded with a JS stack (init script in every frame), so each message can be attributed to its source.
// Modes:  top-none | top-init (X4 style, init script) | parent-none | parent-early | parent-late | gallery
//   parent-*: a same-origin parent (served by page.route with COOP/COEP) iframing the stock page, like x3.html.
// Cases:  a = X4 case (a), init-only `simp?` + click the core Try-this [apply];  hasse = gallery hasse-view, first cursor
// Usage: scripts/with-browser-lock.sh bringup node tests/ux/bringup/consoleprobe.mjs --modes top-none,parent-late --case a
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { SC, ORIGIN, LAUNCH_ARGS, EXAMPLES, lockHeld, writeJson, sleep } from './lib.mjs';

lockHeld();
const argv = process.argv.slice(2);
const opt = (k, d = null) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const modes = opt('modes', 'top-none,top-init,parent-none,parent-early,parent-late,gallery').split(',');
const kase = opt('case', 'a');
const tag = opt('tag', `console-${kase}`);
const BRIDGE_SRC = fs.readFileSync(path.join(SC, 'gallery/qed64-bridge.js'), 'utf8');
const DOC_A = 'example (n : Nat) : n + 0 = n := by simp?\n';
const hasse = EXAMPLES.find((e) => e.id === 'hasse-view');
const doc = kase === 'a' ? DOC_A : hasse.text;
const cursor = kase === 'a' ? { lineNumber: 1, column: DOC_A.indexOf('simp?') + 3 } : hasse.firstCursor;
const STACK_INIT = `(() => {
  const rec = (window.__census = []);
  const where = () => location.pathname + location.search;
  for (const k of ['error', 'warn']) {
    const o = console[k];
    console[k] = function (...a) { try { rec.push({ kind: 'console.' + k, frame: where(), text: a.map((x) => (x && x.message) || String(x)).join(' ').slice(0, 300), stack: (new Error().stack || '').split('\\n').slice(2, 9).join(' | ') }); } catch {} return o.apply(this, a); };
  }
  window.addEventListener('error', (e) => { try { rec.push({ kind: 'window.error', frame: where(), text: String(e.message).slice(0, 300), stack: String(e.error && e.error.stack || '').split('\\n').slice(0, 6).join(' | '), file: e.filename, line: e.lineno }); } catch {} });
  window.addEventListener('unhandledrejection', (e) => { try { rec.push({ kind: 'unhandledrejection', frame: where(), text: String(e.reason && e.reason.message || e.reason).slice(0, 300), stack: String(e.reason && e.reason.stack || '').split('\\n').slice(0, 6).join(' | ') }); } catch {} });
})();`;
const PARENT = (mode) => `<!doctype html><meta charset="utf-8"><title>bring-up parent</title>
<style>html,body{margin:0;height:100%}iframe{width:100%;height:100%;border:0}</style>
<script src="/showcase/qed64-bridge.js"></script>
<iframe id="f" title="qed64"></iframe>
<script>
const f = document.getElementById('f'); window.__installs = [];
const inst = (why) => { try { const w = f.contentWindow; if (!w || w.location.href === 'about:blank' || w.__showcaseBridge) return !!(w && w.__showcaseBridge); window.installQed64Bridge(w); window.__installs.push({ why, rs: w.document.readyState, q: !!w.qed64 }); return true; } catch (e) { return false; } };
f.src = '/?snapshots=snapshots/widgets8';
${mode === 'parent-early' ? "const tick = () => { if (!inst('commit-poll')) setTimeout(tick, 4); }; tick();" : ''}
window.__installLate = () => inst('late');
</script>`;

const results = {};
for (const mode of modes) {
  const browser = await chromium.launch({ args: LAUNCH_ARGS });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  await ctx.addInitScript({ content: STACK_INIT });
  if (mode === 'top-init') await ctx.addInitScript({ content: `${BRIDGE_SRC}\nif (window.top === window) window.installQed64Bridge(window);` });
  await ctx.route(`${ORIGIN}/bringup-parent.html*`, (route) => route.fulfill({ status: 200, contentType: 'text/html; charset=utf-8', headers: { 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp', 'Cross-Origin-Resource-Policy': 'same-origin' }, body: PARENT(mode) }));
  const page = await ctx.newPage();
  const r = { mode, pageErrors: [], console: [] };
  page.on('pageerror', (e) => r.pageErrors.push({ message: String(e.message).slice(0, 200), stack: String(e.stack || '').split('\n').slice(0, 5).join(' | ') }));
  page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') r.console.push({ type: m.type(), text: m.text().slice(0, 200), url: (m.location().url || '').replace(ORIGIN, ''), line: m.location().lineNumber }); });
  try {
    await page.goto(`${ORIGIN}/showcase/pin.json`);
    await page.evaluate((t) => localStorage.setItem('qed64.buffer', t), doc);
    const top = mode.startsWith('top');
    const url = top ? `${ORIGIN}/?snapshots=snapshots/widgets8` : mode === 'gallery' ? `${ORIGIN}/showcase/#hasse-view` : `${ORIGIN}/bringup-parent.html`;
    if (mode === 'gallery' && kase === 'a') throw new Error('gallery mode only runs case hasse');
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    const qw = top ? 'window' : "document.querySelector('iframe').contentWindow";
    const ev = (body) => page.evaluate(new Function(`const W = ${qw}; ${body}`));
    for (let i = 0; i < 1500; i++) { const ph = await ev('return W.qed64 && W.qed64.status().phase').catch(() => null); if (ph === 'ready') break; await sleep(200); }
    if (mode === 'parent-late') r.lateInstall = await page.evaluate(() => window.__installLate());
    await sleep(1000);
    await ev(`const e = W.qed64.editor; e.setPosition(${JSON.stringify(cursor)}); e.focus();`);
    const iv = top ? page.frameLocator('#infoview iframe') : page.frameLocator('iframe').first().frameLocator('#infoview iframe');
    if (kase === 'a') {
      const link = iv.locator('span.link.pointer.dim.font-code').first();
      await link.waitFor({ timeout: 30000 });
      const before = await ev('return W.qed64.editor.getModel().getValue()');
      await link.click();
      let after = before; for (let i = 0; i < 50 && after === before; i++) { await sleep(100); after = await ev('return W.qed64.editor.getModel().getValue()'); }
      r.textChanged = after !== before;
    } else {
      await sleep(6000);
      r.unrecognised = /Unrecognised error/.test(await iv.locator('body').innerText().catch(() => ''));
    }
    await sleep(2000);
    r.installs = top ? null : mode === 'gallery' ? await page.evaluate(() => window.__showcase.status().bridge.installs) : await page.evaluate(() => window.__installs);
    r.bridge = await ev('return W.__showcaseBridge || null').catch(() => null);
    // the census from every frame
    r.census = [];
    for (const fr of page.frames()) { const c = await fr.evaluate(() => window.__census || []).catch(() => []); r.census.push(...c); }
  } catch (e) { r.error = String(e && e.message || e).slice(0, 400); }
  await browser.close();
  results[mode] = r;
  console.log(JSON.stringify({ mode, pageErrors: r.pageErrors.length, consoleErrors: r.console.filter((c) => c.type === 'error').length, warnings: r.console.filter((c) => c.type === 'warning').length, textChanged: r.textChanged, unrec: r.unrecognised, error: r.error }));
}
writeJson(`${tag}.json`, { case: kase, results });
