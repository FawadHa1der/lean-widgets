// Verify every card's "Things to try" against what actually renders, through the real UI:
// click the card, expand "Show all", click each hint button (the gallery moves the cursor), then check the claim:
//   cursor  the InfoView's info block is the one for the hint's position (<file>.lean:<line>:<char>) and holds the
//           golden widget panel (expectPanel: "HTML Display" title or rpc block, exact svg tag counts, texts unique to
//           this cursor), and every quoted text (expectTexts) is inside that panel;
//   click   the link (by text, or SVG edge by title, or [apply]) exists; clicking it changes the document by exactly the
//           frozen edit; QED64 re-checks the edited version with 0 errors and 0 warnings; Reset restores the example;
//   select  (expectSelectPanel, derived from the golden of that exact selection by build-gallery) BEFORE: the info
//           block of the position holds no selection and none of the texts the selection should make appear;
//           then shift-click the subterm(s) / hypothesis in the goal view; AFTER: the block holds >= one selected
//           subterm per pick, every claimed text (whitespace-insensitive leaf runs) is in it; then the selection is
//           shift-clicked off again and must be back to 0;
//   hover   (expectHover, from the golden hover) BEFORE: no hover popup (.tooltip-code-content) in the InfoView; hover
//           the tag inside the panel's code element `codeText` of THIS position's panel; AFTER: a popup whose own text
//           is exactly "<expr> : <type>"; moving the mouse away removes it.
// Every console message / page error is classified against selectors.json consoleAllowlist (lib.mjs
// classifyConsole); anything outside it, or over a per-load limit, fails the run.
// Fault injection (proves the select / hover checks are not vacuous; every hint of that kind must then FAIL):
//   --fault no-select  do everything except the shift-clicks;  --fault no-hover  move the mouse elsewhere instead.
// Usage: scripts/with-browser-lock.sh bringup node tests/ux/bringup/hints.mjs [--only id,id] [--tag hints] [--kinds cursor,click,select,hover] [--fault no-select|no-hover]
import path from 'node:path';
import { chromium } from 'playwright';
import { ORIGIN, OUT, LAUNCH_ARGS, EXAMPLES, SEL, lockHeld, checkPanel, classifyConsole, consoleLine, watchConsole, api, infoview, ivText, ivSettled, waitGalleryReady, writeJson, sleep, until, installTap, tapSummary } from './lib.mjs';

lockHeld();
const argv = process.argv.slice(2);
const opt = (k, d = null) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const only = opt('only') ? opt('only').split(',') : EXAMPLES.map((e) => e.id);
const tag = opt('tag', 'hints');
const kinds = opt('kinds') ? opt('kinds').split(',') : null; // e.g. --kinds cursor (mutation runs)
const fault = opt('fault'); // no-select | no-hover (fault injection, see the header)
if (fault && !['no-select', 'no-hover'].includes(fault)) throw new Error(`unknown --fault ${fault}`);
const POPUP = '.tooltip .tooltip-code-content'; // @leanprover/infoview 0.11.1 hover popup of an InteractiveCode tag
const t0 = Date.now();
const browser = await chromium.launch({ args: LAUNCH_ARGS });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const tapReports = await installTap(ctx); // LSP tap: pairs each empty console.error with its -32800 reply (console.mjs pairWith)
const page = await ctx.newPage();
const watch = watchConsole(page, t0, `${tag}.console.jsonl`);
const res = { examples: {}, summary: { total: 0, pass: 0, fail: 0 } };
const pageEval = (fn, arg) => page.evaluate(([src, a]) => { const w = document.getElementById('qed64-frame').contentWindow; return new w.Function('arg', `return (${src})(arg);`)(a); }, [fn.toString(), arg === undefined ? null : arg]);

function applyEdit(text, r, newText) {
  const lines = text.split('\n');
  const off = (p) => lines.slice(0, p.line).reduce((n, l) => n + l.length + 1, 0) + p.character;
  return text.slice(0, off(r.start)) + newText + text.slice(off(r.end));
}
async function installDiagTap() {
  return pageEval(() => {
    const r = window.qed64.relay; if (r.__bringupTap) return 'already';
    const tc = r.toClient; window.__pub = [];
    r.toClient = function (m) { try { if (m.method === 'textDocument/publishDiagnostics') window.__pub.push({ version: m.params.version, diags: m.params.diagnostics.map((d) => ({ sev: d.severity, line: d.range.start.line, msg: String(d.message).slice(0, 160) })) }); } catch { /* ignore */ } return tc.apply(this, arguments); };
    r.__bringupTap = true; return 'installed';
  });
}
const qstatus = () => pageEval(() => { const s = window.qed64.status(); return { phase: s.phase, version: s.version }; });
async function waitQReady(minVersion, ms = 300000) {
  return until(async () => { const s = await qstatus(); return s.phase === 'ready' && s.version > minVersion ? s : null; }, { timeoutMs: ms, intervalMs: 150 });
}
async function diagsFor(version) {
  // the last publish for this version (the server publishes progressively; the final one is the verdict)
  await sleep(800);
  return pageEval((v) => { const p = (window.__pub || []).filter((x) => x.version === v); return p.length ? p[p.length - 1].diags : null; }, version);
}
async function openCard(id) {
  await page.locator(`#card-${id}`).click();
  await until(async () => { const s = await api.status(page); return s.phase === 'ready' && s.shown === id ? s : null; }, { timeoutMs: 330000 });
  const more = page.locator(`li.card[data-id="${id}"] .hints-toggle`);
  if (await more.isVisible().catch(() => false) && /Show all/.test(await more.textContent())) await more.click();
}
async function resetExample(ex) {
  await page.locator('#reset-btn').click();
  return until(async () => { const s = await api.status(page); const t = await api.text(page); return s.phase === 'ready' && !s.edited && t === ex.text ? s : null; }, { timeoutMs: 120000 });
}
/** Mark the k-th outermost element in the goal view whose text is exactly `target` (or a hypothesis name). */
async function markSelectable(sel) {
  return infoview(page).locator('body').evaluate((b, s) => {
    for (const el of b.querySelectorAll('[data-bringup-sel]')) el.removeAttribute('data-bringup-sel');
    const goals = [...b.querySelectorAll('.goal, div:has(> .goal-vdash)')];
    const scope = goals[s.goal || 0] ? goals[s.goal || 0] : b;
    let cands;
    // hypotheses live in .goal-hyp rows beside (not inside) the data-is-goal target row
    if (s.hyp) cands = [...b.querySelectorAll('.goal-hyp, .goal-hyp *')].filter((e) => e.children.length === 0 && e.textContent.trim() === s.hyp);
    else {
      // a parenthesised occurrence renders as "(if …)" inside its own span
      const norm = (t) => t.replace(/\s+/g, ' ').trim().replace(/^\((.*)\)$/, '$1');
      const all = [...scope.querySelectorAll('span')].filter((e) => norm(e.textContent) === s.target);
      cands = all.filter((e) => !all.includes(e.parentElement)); // outermost exact matches
    }
    const el = cands[s.occurrence || 0];
    if (!el) return { ok: false, n: cands.length };
    el.setAttribute('data-bringup-sel', '1');
    return { ok: true, n: cands.length };
  }, sel);
}
/** Mark the link a click hint names. */
async function markLink(c) {
  return infoview(page).locator('body').evaluate((b, c) => {
    for (const el of b.querySelectorAll('[data-bringup-link]')) el.removeAttribute('data-bringup-link');
    let el = null;
    if (c.kind === 'tryThis') el = [...b.querySelectorAll('span.link, a.link, .link')].find((e) => e.textContent.trim() === '[apply]');
    else if (c.linkText) el = [...b.querySelectorAll('a, .link, [class*="link"]')].find((e) => e.textContent.trim() === c.linkText);
    else if (c.linkTitle) {
      el = [...b.querySelectorAll('[title]')].find((e) => e.getAttribute('title') === c.linkTitle)
        || [...b.querySelectorAll('title')].map((t) => t.textContent.trim() === c.linkTitle ? t.parentElement : null).find(Boolean);
    }
    if (!el) return { ok: false };
    el.setAttribute('data-bringup-link', '1');
    return { ok: true, tag: el.tagName.toLowerCase(), text: el.textContent.trim().slice(0, 60) };
  }, c);
}

try {
  await page.goto(`${ORIGIN}/showcase/#${only[0]}`, { waitUntil: 'domcontentloaded' });
  const b = await waitGalleryReady(page);
  res.bootMs = b.ms;
  await installDiagTap();
  for (const id of only) {
    const ex = EXAMPLES.find((e) => e.id === id);
    const out = [];
    await openCard(id);
    for (let i = 0; i < ex.tryThis.length; i++) {
      const h = ex.tryThis[i];
      if (kinds && !kinds.includes(h.kind)) continue;
      const r = { i, kind: h.kind, label: h.label, ok: false };
      const t1 = Date.now();
      try {
        const btn = page.locator(`li.card[data-id="${id}"] .card-hints .hint`).nth(i);
        r.buttonText = (await btn.innerText()).split('\n')[1] || null;
        await btn.click();
        await until(async () => { const s = await api.status(page); return s.phase === 'ready' && s.cursor && s.cursor.lineNumber === h.lineNumber ? s : null; }, { timeoutMs: 120000 });
        await sleep(400);
        r.settled = await ivSettled(page, { timeoutMs: 120000 });
        if (h.kind === 'cursor') {
          // The panel bound to THIS position (the info block whose summary reads <file>.lean:<line>:<char>), with the
          // golden's widget title, exact svg tag counts and position-specific texts, plus the card's quoted texts.
          if (!h.expectPanel) throw new Error('hint has no expectPanel (rerun node scripts/build-gallery.mjs)');
          let chk = null;
          await until(async () => { chk = await checkPanel(page, h.expectPanel, { extraTexts: h.expectTexts }); return chk.ok; }, { timeoutMs: 30000 });
          const t = await ivText(page);
          r.unrecognised = /Unrecognised error/.test(t);
          r.panel = chk && { ok: chk.ok, reason: chk.reason, at: chk.at, heads: chk.heads, panelTitle: chk.panelTitle, svgTags: chk.svgTags, svgDiff: chk.svgDiff, missingTexts: chk.missingTexts };
          r.missing = chk ? chk.missingTexts : h.expectTexts;
          r.ok = !!(chk && chk.ok) && !r.unrecognised;
          if (!r.ok && chk) r.error = chk.reason;
        } else if (h.kind === 'click') {
          const c = h.expectClick;
          const m = await until(() => markLink(c).then((x) => (x.ok ? x : null)), { timeoutMs: 30000 });
          r.link = m;
          if (!m) throw new Error(`link not found: ${c.linkText || c.linkTitle}`);
          const before = await api.text(page);
          const v0 = (await qstatus()).version;
          await infoview(page).locator('[data-bringup-link]').click({ force: true });
          const after = await until(async () => { const t = await api.text(page); return t !== before ? t : null; }, { timeoutMs: 15000, intervalMs: 50 });
          r.clickToEditMs = Date.now() - t1;
          const want = c.range ? applyEdit(before, c.range, c.newText) : null;
          r.editExact = after === want;
          const st = await waitQReady(v0, 300000);
          r.settleMs = Date.now() - t1;
          const d = st ? await diagsFor(st.version) : null;
          r.errors = d ? d.filter((x) => x.sev === 1).length : null; r.warnings = d ? d.filter((x) => x.sev === 2).length : null;
          if (d && (r.errors || r.warnings)) r.diags = d.filter((x) => x.sev <= 2);
          const s = await api.status(page);
          r.chipEdited = s.edited === true;
          r.reset = !!(await resetExample(ex));
          r.ok = !!(after && r.editExact && r.errors === 0 && r.warnings === 0 && r.chipEdited && r.reset);
        } else if (h.kind === 'select') {
          const sp = h.expectSelectPanel;
          if (!sp) throw new Error('hint has no expectSelectPanel (rerun node scripts/build-gallery.mjs)');
          // The texts the selection makes appear, and every claimed text, are looked up in the info block of THIS
          // position only (the rpc panel + goal view), never anywhere in the InfoView.
          const appearExp = { at: sp.at, panelTitle: null, svgTagCounts: null, texts: sp.appear };
          const allExp = { at: sp.at, panelTitle: null, svgTagCounts: null, texts: sp.texts };
          // BEFORE: the unselected panel of this position has rendered (its golden cursor expectation holds), nothing
          // is selected, and none of `appear` shows
          const ch = ex.tryThis.find((x) => x.kind === 'cursor' && x.line === h.line && x.character === h.character);
          if (!ch || !ch.expectPanel) throw new Error(`no cursor hint with expectPanel at ${h.lineNumber}:${h.character}`);
          let base = null;
          await until(async () => { base = await checkPanel(page, ch.expectPanel); return base.ok; }, { timeoutMs: 30000 });
          if (!base || !base.ok) throw new Error(`before: the unselected panel did not render: ${base && base.reason}`);
          await infoview(page).locator('body').evaluate((b) => { for (const e of b.querySelectorAll('[data-bringup-pick]')) e.removeAttribute('data-bringup-pick'); });
          const pre = await checkPanel(page, appearExp, { squash: true });
          r.before = { selectedCount: pre.selectedCount, present: sp.appear.filter((t) => !pre.missingTexts.includes(t)), reason: pre.selectedCount === null ? pre.reason : null };
          if (pre.selectedCount === null) throw new Error(`before: ${pre.reason}`);
          if (pre.selectedCount !== 0) throw new Error(`before: ${pre.selectedCount} subterms already selected`);
          if (r.before.present.length) throw new Error(`before any selection the block already shows ${JSON.stringify(r.before.present)} (vacuous claim)`);
          r.picks = [];
          for (const sel of h.expectSelect) {
            const m = await until(() => markSelectable(sel).then((x) => (x.ok ? x : null)), { timeoutMs: 20000 });
            r.picks.push(m);
            if (!m) throw new Error(`selectable not found: ${JSON.stringify(sel)}`);
            await infoview(page).locator('[data-bringup-sel]').evaluate((e, i) => e.setAttribute('data-bringup-pick', String(i)), r.picks.length - 1);
            if (fault !== 'no-select') await infoview(page).locator('[data-bringup-sel]').click({ modifiers: ['Shift'] });
            await sleep(600);
          }
          // AFTER: >= 1 selected subterm per pick, and every claimed text in the block
          let chk = null;
          await until(async () => { chk = await checkPanel(page, allExp, { squash: true }); return chk.ok && chk.selectedCount >= h.expectSelect.length; }, { timeoutMs: 30000 });
          r.after = { selectedCount: chk ? chk.selectedCount : null, missing: chk ? chk.missingTexts : sp.texts };
          r.missing = r.after.missing;
          r.ok = !!(chk && chk.ok && chk.selectedCount >= h.expectSelect.length);
          if (!r.ok) r.error = chk && !chk.ok ? chk.reason : `after: ${chk ? chk.selectedCount : '?'} selected subterms, want >= ${h.expectSelect.length}`;
          // clear: shift-click each pick again (newest first; shift-click toggles), then require 0 selected
          if (fault !== 'no-select') {
            for (let k = h.expectSelect.length - 1; k >= 0; k--) await infoview(page).locator(`[data-bringup-pick="${k}"]`).click({ modifiers: ['Shift'] }).catch(() => {});
          }
          const cleared = await until(async () => { const c = await checkPanel(page, { ...appearExp, texts: [] }, { squash: true }); return c.selectedCount === 0 ? c : null; }, { timeoutMs: 15000 });
          r.cleared = !!cleared;
          if (!r.cleared) { r.ok = false; r.error = `${r.error ? `${r.error}; ` : ''}selection not cleared`; }
        } else if (h.kind === 'hover') {
          const hv = h.expectHover;
          if (!hv || !hv.popupText) throw new Error('hint has no expectHover.popupText (rerun node scripts/build-gallery.mjs)');
          // tag THIS position's panel (the cursor hint of the same line carries its golden expectation)
          const ch = ex.tryThis.find((x) => x.kind === 'cursor' && x.line === h.line && x.character === h.character);
          let pc = null;
          await until(async () => { pc = await checkPanel(page, ch.expectPanel); return pc.ok; }, { timeoutMs: 30000 });
          if (!pc || !pc.ok) throw new Error(`panel of line ${h.lineNumber} not found: ${pc && pc.reason}`);
          const popups = () => infoview(page).locator(POPUP).evaluateAll((els) => els.map((e) => e.textContent.replace(/\s+/g, ' ').trim()));
          r.before = await popups();
          if (r.before.length) throw new Error(`before the hover a popup is already open: ${JSON.stringify(r.before)}`);
          const mk = await infoview(page).locator('[data-bringup-panel]').evaluate((p, hv) => {
            for (const e of document.querySelectorAll('[data-bringup-hover]')) e.removeAttribute('data-bringup-hover');
            const norm = (t) => t.replace(/\s+/g, ' ').trim();
            const code = [...p.querySelectorAll('.font-code, code')].find((c) => norm(c.textContent) === hv.codeText);
            if (!code) return { ok: false, why: `no code element ${hv.codeText}` };
            const all = [code, ...code.querySelectorAll('*')].filter((e) => norm(e.textContent) === hv.tagText);
            const el = all.find((e) => ![...e.children].some((c) => all.includes(c))) || null;
            if (!el) return { ok: false, why: `no tag ${hv.tagText} in ${hv.codeText}` };
            el.setAttribute('data-bringup-hover', '1');
            return { ok: true, tag: el.tagName.toLowerCase(), hasTooltipAttr: el.hasAttribute('data-has-tooltip-on-hover') };
          }, hv);
          r.target = mk;
          if (!mk.ok) throw new Error(mk.why);
          if (fault === 'no-hover') await page.mouse.move(5, 5);
          else await infoview(page).locator('[data-bringup-hover]').hover();
          const got = await until(async () => { const p = await popups(); return p.includes(hv.popupText) ? p : null; }, { timeoutMs: 15000 });
          r.popups = got || await popups();
          r.ok = !!got;
          if (!r.ok) r.error = `no popup “${hv.popupText}” after the hover (popups: ${JSON.stringify(r.popups)})`;
          await page.mouse.move(5, 5);
          r.closed = !!(await until(async () => ((await popups()).length === 0 ? true : null), { timeoutMs: 10000 }));
          if (!r.closed) { r.ok = false; r.error = `${r.error ? `${r.error}; ` : ''}popup did not close`; }
        }
      } catch (e) { r.error = String(e && e.message || e).slice(0, 300); }
      r.ms = Date.now() - t1;
      out.push(r);
      res.summary.total++; res.summary[r.ok ? 'pass' : 'fail']++;
      console.log(`${r.ok ? 'ok  ' : 'FAIL'} ${id} #${i} ${h.kind} ${h.label}${r.error ? ` — ${r.error}` : ''}${r.missing && r.missing.length ? ` missing ${JSON.stringify(r.missing)}` : ''}${r.kind === 'click' ? ` edit ${r.editExact} err ${r.errors} warn ${r.warnings} ${r.settleMs} ms` : ''}`);
      if (h.kind === 'click' && !r.reset) { await resetExample(ex).catch(() => null); }
    }
    await page.screenshot({ path: path.join(OUT, `${tag}-${id}.png`) });
    res.examples[id] = out;
  }
} catch (e) { res.error = String(e && e.stack || e).slice(0, 1200); }
res.crashed = watch.crashed;
res.fault = fault || null;
res.console = classifyConsole(watch, SEL.consoleAllowlist, { reports: tapReports }); res.tap = tapSummary(tapReports);
console.log(consoleLine(res.console));
res.bridgeStats = await api.bridge(page).catch(() => null);
res.pageErrors = watch.pageErrors;
res.consoleErrors = watch.messages.filter((m) => m.type === 'error' || m.type === 'warning');
res.wallMs = Date.now() - t0;
writeJson(`${tag}.json`, res);
await browser.close();
const bad = res.summary.fail || res.error || res.crashed || !res.console.ok;
console.log(`HINTS ${bad ? 'FAIL' : 'OK'} ${res.summary.pass}/${res.summary.total}${res.console.ok ? '' : ' (console)'}${fault ? ` fault ${fault}` : ''}`);
process.exit(bad ? 1 : 0);
