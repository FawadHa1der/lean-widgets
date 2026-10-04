// X4 — InfoView click paths on the stock pair (BUILD-PLAN §3 X4). Decides whether the
// InfoView -> editor applyEdit path (core Try-this and ProofWidgets MakeEditLink) works in QED64.
//   (a) init-only `example (n : Nat) : n + 0 = n := by simp?` -> click core Try-this link
//   (b) `import Mathlib.Tactic.Widget.Conv` + `conv?` -> shift-click a goal subterm -> "Generate conv"
// Each case runs in two modes:
//   raw    — the stock page exactly as shipped (decides whether applyEdit works in QED64 at all)
//   bridge — the same page plus gallery/qed64-bridge.js installed from the same origin (an init
//            script here; iframe.contentWindow in the M2 gallery). Zero QED64 changes either way.
//   strip  — bridge with {edits:false}: repairs only the abortSignal defect, so case (b) isolates
//            whether MakeEditLink's applyEdit works on the stock wiring once the panel renders.
// Usage: node tests/experiments/x4-click-paths.mjs [a:raw b:raw a:bridge b:bridge]
import fs from 'node:fs';
import path from 'node:path';
import { SC, ORIGIN, launch, waitPhase, installTap, consoleWatch, writeResult, sleep } from './lib.mjs';

const runs = process.argv.slice(2).length ? process.argv.slice(2) : ['a:raw', 'b:raw', 'a:bridge', 'b:bridge'];
const BRIDGE_SRC = fs.readFileSync(path.join(SC, 'gallery/qed64-bridge.js'), 'utf8');
const SEL = (await import(path.join(SC, 'scripts/lib/pins.mjs'))).loadSelectors(); // "@qed64-main-bundle" -> the active pin's bundle
const shots = path.join(SC, 'out', 'experiments', 'x4');
fs.mkdirSync(shots, { recursive: true });

const DOC_A = 'example (n : Nat) : n + 0 = n := by simp?\n';
const DOC_B = `import Mathlib.Tactic.Widget.Conv

example (a b c : Nat) : a + (b + c) = (c + b) + a := by
  conv?
  omega
`;

async function boot(browser, doc, url, mode) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  if (mode === 'bridge' || mode === 'strip') {
    const opts = mode === 'strip' ? '{ edits: false }' : 'undefined';
    await ctx.addInitScript({ content: `${BRIDGE_SRC}\nif (window.top === window) window.installQed64Bridge(window, ${opts});` });
  }
  // seed the boot input once (guarded so a reload would not re-seed)
  await ctx.addInitScript((t) => { try { if (!sessionStorage.getItem('x4-seeded')) { localStorage.setItem('qed64.buffer', t); sessionStorage.setItem('x4-seeded', '1'); } } catch {} }, doc);
  const page = await ctx.newPage();
  const watch = consoleWatch(page);
  const t0 = Date.now();
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  const w = await waitPhase(page, /^ready$/, { timeoutMs: 300000 });
  await installTap(page);
  return { ctx, page, watch, boot: { ms: Date.now() - t0, phase: w.status?.phase, header: w.status?.header, snapshots: await page.evaluate(() => [...(globalThis.qed64.relay.session?.snapshots ?? [])]) } };
}
const text = (page) => page.evaluate(() => globalThis.qed64.editor.getModel().getValue());
const status = (page) => page.evaluate(() => globalThis.qed64.status());
const stats = (page) => page.evaluate(() => ({ ...globalThis.qed64.relay.stats }));
async function setCursor(page, line, col) {
  await page.evaluate(([l, c]) => { const e = globalThis.qed64.editor; e.setPosition({ lineNumber: l, column: c }); e.focus(); }, [line, col]);
}
/** Latest diagnostics for the current document version via the toClient tap. */
async function diagsNow(page) {
  return page.evaluate(() => {
    const v = globalThis.qed64.status().version;
    const all = globalThis.__pub || [];
    const forV = all.filter((p) => p.version === v);
    const last = forV.at(-1) ?? all.at(-1) ?? null;
    return { version: v, publishes: all.length, lastVersion: last?.version ?? null, diags: (last?.diagnostics ?? []).map((d) => ({ sev: d.severity, line: d.range.start.line + 1, msg: d.message.slice(0, 200) })) };
  });
}
async function settle(page, minVersion) {
  const w = await waitPhase(page, /^ready$/, { timeoutMs: 120000, minVersion });
  // ready must hold for 1 s
  await sleep(1000);
  const s = await status(page);
  return { ...w, stableReady: s.phase === 'ready' && s.version === w.status?.version };
}
async function ivText(iv) { return (await iv.locator('body').innerText({ timeout: 10000 }).catch(() => '')).slice(0, 4000); }
async function ivSettled(iv) {
  // §8.1 settled: no updating summary and no "Error updating"
  for (let i = 0; i < 120; i++) {
    const gold = await iv.locator(SEL.infoview.updatingSummary).count();
    const err = await iv.locator(SEL.infoview.errorDiv, { hasText: 'Error updating' }).count();
    if (!gold && !err) return true;
    await sleep(250);
  }
  return false;
}

async function caseA(browser, mode) {
  const r = { case: 'a', mode, doc: DOC_A };
  const { ctx, page, watch, boot: b } = await boot(browser, DOC_A, `${ORIGIN}/`, mode);
  r.boot = b;
  try {
    const st0 = await stats(page);
    const s0 = await status(page);
    r.diagsBefore = await diagsNow(page);
    await setCursor(page, 1, DOC_A.indexOf('simp?') + 2);
    const iv = page.frameLocator(SEL.infoview.frame);
    const link = iv.locator(SEL.infoview.coreTryThis).first();
    await link.waitFor({ timeout: 30000 });
    await ivSettled(iv);
    r.linkText = await link.innerText();
    r.ivTextBefore = await ivText(iv);
    await page.screenshot({ path: path.join(shots, `a-${mode}-before.png`) });
    const before = await text(page);
    await link.click();
    const t0 = Date.now(); let after = before;
    while (Date.now() - t0 < 15000 && after === before) { await sleep(100); after = await text(page); }
    r.textChanged = after !== before; r.clickToEditMs = Date.now() - t0; r.textAfter = after;
    if (r.textChanged) {
      const se = await settle(page, s0.version);
      r.afterPhase = se.status?.phase; r.afterVersion = se.status?.version; r.stableReady = se.stableReady;
      await sleep(1500);
      r.diagsAfter = await diagsNow(page);
      r.errorsAfter = r.diagsAfter.diags.filter((d) => d.sev === 1).length;
    }
    const st1 = await stats(page);
    r.statsBefore = st0; r.statsAfter = st1;
    r.rangedUnchanged = st0.rangedChanges === st1.rangedChanges;
    r.selection = await page.evaluate(() => globalThis.qed64.editor.getSelection());
    await page.screenshot({ path: path.join(shots, `a-${mode}-after.png`) });
    r.pass = !!(r.textChanged && /simp only/.test(after) && !/simp\?/.test(after) && r.afterPhase === 'ready' && r.errorsAfter === 0 && st1.workerDeaths === st0.workerDeaths && st1.reboots === st0.reboots);
  } catch (e) { r.error = String(e.stack || e).slice(0, 1500); r.pass = false; r.ivTextAtError = await ivText(page.frameLocator(SEL.infoview.frame)); await page.screenshot({ path: path.join(shots, `a-${mode}-error.png`) }).catch(() => {}); }
  r.bridge = await page.evaluate(() => globalThis.__qed64Bridge ?? null).catch(() => null);
  r.console = { pageErrors: watch.pageErrors, errors: watch.errors.slice(0, 10), crashed: watch.crashed, tail: watch.tail.slice(-15) };
  await ctx.close();
  return r;
}

async function caseB(browser, mode) {
  const r = { case: 'b', mode, doc: DOC_B };
  const { ctx, page, watch, boot: b } = await boot(browser, DOC_B, `${ORIGIN}/`, mode);
  r.boot = b;
  try {
    const st0 = await stats(page);
    const s0 = await status(page);
    r.diagsBefore = await diagsNow(page);
    const lines = DOC_B.split('\n');
    const ln = lines.findIndex((l) => l.includes('conv?')) + 1;
    await setCursor(page, ln, lines[ln - 1].indexOf('conv?') + 3);
    const iv = page.frameLocator(SEL.infoview.frame);
    const panel = iv.locator(SEL.infoview.panelSummary, { hasText: SEL.conv.panelTitle });
    const panelErr = iv.getByText(/abortSignal|Unrecognised error/).first();
    await Promise.race([panel.first().waitFor({ timeout: 60000 }), panelErr.waitFor({ timeout: 60000 })]);
    if (await panelErr.count()) { r.panelError = (await panelErr.innerText()).slice(0, 600); throw new Error('conv? panel failed to render: ' + r.panelError.slice(0, 200)); }
    await ivSettled(iv);
    r.ivTextBefore = await ivText(iv);
    await page.screenshot({ path: path.join(shots, `b-${mode}-before.png`) });
    // shift-click a goal subterm: the `c + b` inside the goal's RHS
    const goal = iv.locator(SEL.infoview.goalTarget).first();
    await goal.waitFor({ timeout: 30000 });
    r.goalText = await goal.innerText();
    const sub = goal.locator(SEL.infoview.subterm, { hasText: SEL.conv.subtermText }).last();
    r.subtermCandidates = await goal.locator(SEL.infoview.subterm).evaluateAll((els) => els.map((e) => e.textContent).slice(0, 40));
    await sub.click({ modifiers: ['Shift'] });
    await sleep(500);
    r.selectedCount = await iv.locator(SEL.infoview.selectedSubterm).count();
    const gen = iv.locator(SEL.infoview.makeEditLink, { hasText: SEL.conv.generateText }).first();
    await gen.waitFor({ timeout: 30000 });
    r.ivTextSelected = await ivText(iv);
    await page.screenshot({ path: path.join(shots, `b-${mode}-selected.png`) });
    const before = await text(page);
    await gen.click();
    const t0 = Date.now(); let after = before;
    while (Date.now() - t0 < 15000 && after === before) { await sleep(100); after = await text(page); }
    r.textChanged = after !== before; r.clickToEditMs = Date.now() - t0; r.textAfter = after;
    if (r.textChanged) {
      const se = await settle(page, s0.version);
      r.afterPhase = se.status?.phase; r.afterVersion = se.status?.version; r.stableReady = se.stableReady;
      await sleep(1500);
      r.diagsAfter = await diagsNow(page);
      r.errorsAfter = r.diagsAfter.diags.filter((d) => d.sev === 1).length;
    }
    const st1 = await stats(page);
    r.statsBefore = st0; r.statsAfter = st1;
    r.rangedUnchanged = st0.rangedChanges === st1.rangedChanges;
    r.selection = await page.evaluate(() => globalThis.qed64.editor.getSelection());
    r.rpcErrors = await page.evaluate(() => (globalThis.__rpc || []).filter((x) => x.err).slice(0, 10));
    await page.screenshot({ path: path.join(shots, `b-${mode}-after.png`) });
    r.pass = !!(r.textChanged && /conv =>/.test(after) && /enter/.test(after) && !/conv\?/.test(after) && r.afterPhase === 'ready' && r.errorsAfter === 0 && st1.workerDeaths === st0.workerDeaths && st1.reboots === st0.reboots);
  } catch (e) { r.error = String(e.stack || e).slice(0, 1500); r.pass = false; r.ivTextAtError = await ivText(page.frameLocator(SEL.infoview.frame)); r.ivHtmlAtError = (await page.frameLocator(SEL.infoview.frame).locator('body').innerHTML().catch(() => '')).slice(0, 20000); await page.screenshot({ path: path.join(shots, `b-${mode}-error.png`) }).catch(() => {}); }
  r.bridge = await page.evaluate(() => globalThis.__qed64Bridge ?? null).catch(() => null);
  r.console = { pageErrors: watch.pageErrors, errors: watch.errors.slice(0, 10), crashed: watch.crashed, tail: watch.tail.slice(-15) };
  await ctx.close();
  return r;
}

const out = {};
for (const run of runs) {
  const [c, mode] = run.split(':');
  const browser = await launch();
  try { out[run] = c === 'a' ? await caseA(browser, mode) : await caseB(browser, mode); }
  finally { await browser.close(); }
  const r = out[run];
  console.log(JSON.stringify({ ...r, ivHtmlAtError: r.ivHtmlAtError ? `${r.ivHtmlAtError.length} chars` : undefined, console: { ...r.console, tail: undefined } }, null, 1));
  if (r.ivHtmlAtError) fs.writeFileSync(path.join(shots, `${c}-${mode}-error-iv.html`), r.ivHtmlAtError);
  delete r.ivHtmlAtError;
  await sleep(3000);
}
let prev = {};
try { prev = JSON.parse(fs.readFileSync(path.join(SC, 'out/experiments/x4.json'), 'utf8')).runs ?? {}; } catch {}
const all = { ...prev, ...out };
const verdict = {
  applyEditStockPage: all['a:raw'] ? (all['a:raw'].textChanged ? 'works' : 'BROKEN') : 'not run',
  rpcPanelStockPage: all['b:raw'] ? (all['b:raw'].panelError ? 'BROKEN' : 'renders') : 'not run',
  applyEditWithBridge: all['a:bridge'] ? (all['a:bridge'].pass ? 'works' : 'fails') : 'not run',
  makeEditLinkStockApplyEdit: all['b:strip'] ? (all['b:strip'].textChanged ? 'works' : 'BROKEN') : 'not run',
  makeEditLinkWithBridge: all['b:bridge'] ? (all['b:bridge'].pass ? 'works' : 'fails') : 'not run',
};
const pass = !!(all['a:bridge']?.pass && all['b:bridge']?.pass);
writeResult('x4', { pass, answered: !!(all['a:raw'] && all['b:raw']), verdict, selectors: SEL, runs: all });
process.exit(Object.values(out).every((r) => r.pass || r.mode === 'raw' || r.mode === 'strip') ? 0 : 1);
