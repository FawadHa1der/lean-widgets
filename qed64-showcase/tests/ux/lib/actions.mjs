// Real-UI interactions shared by the W1–W8 tests and C20 (tests/ux/specs/10-widgets.spec.mjs, 20-click-all.spec.mjs).
// Every interaction goes through the real InfoView / Monaco DOM with Playwright's real mouse and keyboard; the
// page's API is used only to READ state and to place the editor cursor (exactly what the gallery itself does).
import { applyEdit, errorsWarnings, sha256, sleep, until, captureHang, captureQed64Reboot, GOLDENS, SPECS, BY_ID } from './qed64.mjs';

export const goldenCursor = (id, line, character) => GOLDENS[id].cursors.find((c) => c.line === line && c.character === character) || null;
/** The spec cursor (line + character) a click on `cursorLine` is made from. */
export const cursorOfLine = (id, line) => SPECS[id].cursors.find((c) => c.line === line) || GOLDENS[id].cursors.find((c) => c.line === line) || { line, character: 0 };

/** Place the cursor, then require the panel at that position to equal its golden (full signature). */
export async function checkCursor(g, id, cur, { timeoutMs = 60000 } = {}) {
  const gc = goldenCursor(id, cur.line, cur.character);
  if (!gc || !gc.panels.length) return { ok: false, reason: `no golden cursor ${cur.line}:${cur.character}` };
  const t = Date.now();
  await g.setCursor(cur.line, cur.character);
  await sleep(250);
  await g.ivSettled({ timeoutMs });
  const r = await g.expectPanel({ line: cur.line, character: cur.character }, gc.panels[0], { timeoutMs });
  const iv = await g.ivText();
  const unrec = /Unrecognised error|abortSignal/.test(iv);
  return { ok: r.equal && !unrec, line: cur.line, character: cur.character, panel: gc.panels[0].id, kind: gc.panels[0].kind, ms: Date.now() - t, diffs: r.diffs, unrecognised: unrec, heads: r.heads, counts: r.sig ? { tags: Object.values(r.sig.tagCounts).reduce((a, b) => a + b, 0), texts: r.sig.texts.length, links: r.sig.links.length, codeTexts: r.sig.codeTexts.length } : null };
}

/**
 * Click one link in the InfoView with the real mouse and verify the edit and the re-elaboration.
 * link: {kind: 'makeEditLink'|'tryThis', linkText, title, edit: {range, newText}, editedSha256?}
 * at: {line, character} cursor position the link is rendered at; goldenPanel: the panel the link lives in (makeEditLink)
 * Returns a record; ok = text after == applyEdit(example) (== native sha256 when given), version re-checked with
 * 0 errors / 0 warnings, workerDeaths unchanged.
 */
export async function clickLink(g, ex, link, at, goldenPanel, { elabTimeoutMs = 300000, reset = true, beforeClick = null } = {}) {
  const r = { kind: link.kind, linkText: link.linkText, title: link.title || null, at: `${at.line}:${at.character}`, ok: false };
  const t0 = Date.now();
  r.stalls = [];
  if (reset && (await g.currentText()) !== ex.text) { const rs = await g.resetUI(ex, { stalls: r.stalls }); r.resetBeforeMs = rs.ms; if (!rs.ok) { r.error = 'reset before the click failed'; return r; } }
  const st0 = await g.qstatus();
  await g.setCursor(at.line, at.character);
  await sleep(200);
  await g.ivSettled({ timeoutMs: 120000 });
  let target;
  if (link.kind === 'makeEditLink') {
    const p = await g.expectPanel(at, goldenPanel, { timeoutMs: 60000 });
    r.panelEqual = p.equal; r.panelMs = p.ms;
    if (!p.equal) { r.error = `panel at ${r.at} != golden: ${p.diffs.slice(0, 3).join('; ')}`; return r; }
    const idx = goldenPanel.links.findIndex((l) => l.linkText === link.linkText && (l.title || null) === (link.title || null) && JSON.stringify(l.edit) === JSON.stringify(link.edit));
    if (idx < 0) { r.error = 'link not in the golden panel'; return r; }
    r.index = idx;
    target = g.iv.locator(`[data-ux-panel] [data-ux-link="${idx}"]`);
  } else {
    // core Try this: the [apply] span (title "Apply suggestion") of the message whose suggestion is this edit
    const first = link.edit.newText.split('\n')[0];
    const m = await until(() => g.iv.locator('body').evaluate((b, a) => {
      for (const e of b.querySelectorAll('[data-ux-apply]')) e.removeAttribute('data-ux-apply');
      const norm = (s) => String(s).replace(/\s+/g, ' ').trim();
      const posRe = /\.lean:(\d+):(\d+)/;
      const blocks = [...b.querySelectorAll('details')].filter((d) => { const s = d.querySelector(':scope > summary'); const m2 = s && norm(s.textContent).match(/^[\w.\-/ ]+\.lean:(\d+):(\d+)/); return m2 && `${m2[1]}:${m2[2]}` === `${a.line + 1}:${a.character}`; });
      if (!blocks.length) return null;
      const cands = [...blocks[0].querySelectorAll('span.link')].filter((e) => norm(e.textContent) === '[apply]' && norm(e.closest('pre') ? e.closest('pre').textContent : '').includes(norm(a.first)));
      if (cands.length !== 1) return cands.length ? { n: cands.length } : null;
      cands[0].setAttribute('data-ux-apply', '1');
      return { n: 1, title: cands[0].getAttribute('title'), pos: posRe.test(blocks[0].textContent) };
    }, { line: at.line, character: at.character, first }), { timeoutMs: 60000, intervalMs: 300 });
    r.apply = m;
    if (!m || m.n !== 1) { r.error = `[apply] for “${first}” not found uniquely (${m ? m.n : 0})`; return r; }
    target = g.iv.locator('[data-ux-apply]');
  }
  const before = await g.currentText();
  const v0 = (await g.qstatus()).version;
  const lv0 = ((await g.status()) || {}).liveness || null;
  // Where a user would click: a point of the link that nothing else covers. Neither Playwright's centre click nor its
  // visibility rule fits SVG edges: an edge is <a><line/></a>, a horizontal or vertical edge has a zero-height (or
  // zero-width) box, which Playwright calls "not visible", and K4's two diagonals cross exactly at their midpoints, so
  // a centre click lands on the other edge. So: scroll the link into view, then for an edge walk along its line, else
  // sample its box, and take the first point whose topmost element (document.elementFromPoint, the browser's own hit
  // test) is inside this link; then press the real mouse there (page coordinates = the InfoView iframe's content box
  // + the point's client coordinates in it).
  const pt = await target.evaluate(async (a) => {
    a.scrollIntoView({ block: 'center', inline: 'center' });
    await new Promise((res) => requestAnimationFrame(() => requestAnimationFrame(res)));
    const r = a.getBoundingClientRect();
    const inside = (x, y) => { const e = document.elementFromPoint(x, y); return !!e && (e === a || a.contains(e)); };
    const pts = [];
    const ln = a.querySelector('line');
    if (ln && ln.getScreenCTM) {
      const m = ln.getScreenCTM(); const n = (k) => Number(ln.getAttribute(k)) || 0;
      for (const t of [0.5, 0.35, 0.65, 0.25, 0.75, 0.15, 0.85]) { const x = n('x1') + t * (n('x2') - n('x1')); const y = n('y1') + t * (n('y2') - n('y1')); pts.push([m.a * x + m.c * y + m.e, m.b * x + m.d * y + m.f, `line t=${t}`]); }
    }
    pts.push([r.left + r.width / 2, r.top + r.height / 2, 'centre']);
    for (const fx of [0.25, 0.75, 0.1, 0.9]) for (const fy of [0.5, 0.25, 0.75]) pts.push([r.left + fx * r.width, r.top + fy * r.height, `box ${fx},${fy}`]);
    for (const [x, y, how] of pts) if (inside(x, y)) return { cx: x, cy: y, how, box: [Math.round(r.width), Math.round(r.height)], plain: how === 'centre' && r.width > 1 && r.height > 1 };
    return null;
  });
  r.clickPoint = pt ? `${pt.how} (box ${pt.box})` : null;
  if (!pt) { r.error = 'no point of the link is uncovered (nothing a user could click)'; return r; }
  if (beforeClick) r.beforeClick = await beforeClick(); // C21: freeze the checker once the panel is up
  let tc;
  if (pt.plain) {
    // an ordinary link whose centre is uncovered: Playwright's actionable click (visible, stable, receives events)
    tc = Date.now();
    await target.click({ timeout: 15000 }); r.clickMode = 'mouse';
  } else {
    // a zero-height/width edge or a covered centre: the real mouse at the uncovered point, once the panel is still
    // (the same point must still hit the link 300 ms later)
    await sleep(300);
    const still = await target.evaluate((a, p) => { const e = document.elementFromPoint(p.cx, p.cy); return !!e && (e === a || a.contains(e)); }, pt);
    if (!still) { r.error = `the panel moved under the chosen point (${pt.how})`; return r; }
    const ivFrame = g.qframe.locator('#infoview iframe');
    const box = await ivFrame.boundingBox();
    const border = await ivFrame.evaluate((f) => ({ l: f.clientLeft, t: f.clientTop }));
    tc = Date.now();
    await g.page.mouse.click(box.x + border.l + pt.cx, box.y + border.t + pt.cy);
    r.clickMode = 'mouse-at-point';
  }
  const after = await until(async () => { const t = await g.currentText(); return t !== before ? t : null; }, { timeoutMs: 15000, intervalMs: 40 });
  r.clickToEditMs = Date.now() - tc;
  if (!after) { r.error = 'the click did not change the document'; return r; }
  const want = applyEdit(before, link.edit.range, link.edit.newText);
  r.editExact = after === want;
  if (link.editedSha256) r.nativeSha = sha256(after) === link.editedSha256;
  // Ready, or the gallery's stall card (QED64 L7: the checker stops making progress, docs/UX-RESULTS.md). A stall is
  // answered through the card ("Restart Lean": a fresh checker on the SAME post-click text), and the link is then
  // judged on that re-check exactly as before; every stall is recorded (r.stalls) and reported by the caller.
  // In the liveness probe's default (auto) mode a frozen runtime is restarted by the gallery itself (~20 s); in observe
  // mode (hang hunts) the wedge is captured here first (captureHang), then answered through the card as above.
  let st = null; const tw = Date.now();
  r.captures = [];
  while (!st && Date.now() - tw < elabTimeoutMs) {
    st = await g.waitReady({ minVersion: v0, timeoutMs: 1500 });
    if (!st) { const c = await g.maybeCapture(`click ${r.at} “${link.linkText || link.title}”`); if (c) { r.captures.push(c); st = await g.waitReady({ minVersion: v0, timeoutMs: 500 }); } }
    if (!st && await g.stallCardVisible()) { r.stalls.push(await g.recoverStall('click')); st = await g.waitReady({ minVersion: v0, text: after, timeoutMs: 120000 }); }
  }
  r.clickToReadyMs = Date.now() - tc;
  const lv1 = ((await g.status()) || {}).liveness || null;
  if (lv0 && lv1) r.liveness = { sent: lv1.sent - lv0.sent, answered: lv1.answered - lv0.answered, alive: (lv1.alive || 0) - (lv0.alive || 0), missed: lv1.missed - lv0.missed, wedged: lv1.wedged - lv0.wedged, restarts: lv1.restarts - lv0.restarts, events: lv1.events.filter((e) => e.t > ((lv0.events[lv0.events.length - 1] || {}).t ?? -1) && e.source !== 'probe' && e.source !== 'answered') };
  // QED64 9fdf9b8+ handled an L7 itself (its liveness: died "wedged", relay reboot) during this click: record it post hoc
  const qw = lv0 && lv1 && lv0.qed64 && lv1.qed64 ? lv1.qed64.wedgedReboots - lv0.qed64.wedgedReboots : 0;
  if (qw > 0) {
    r.qed64WedgedReboots = qw; r.qed64LastReboot = lv1.qed64.lastReboot;
    r.captures.push(await captureQed64Reboot(g, { context: `click ${r.at} “${link.linkText || link.title}”: QED64 rebooted a wedged session (${qw}x)` }));
  }
  if (r.stalls.length || (r.liveness && r.liveness.restarts) || qw > 0) r.recoveredFromStall = !!st;
  if (!st) {
    r.error = `not ready within ${elabTimeoutMs} ms after the click`;
    r.captures.push(await captureHang(g, { context: `C20/W click ${r.at} “${link.linkText || link.title}”: ${r.error}` })); // before any reset
    return r;
  }
  r.version = st.version; r.pool = st.pool || null;
  const d = await g.diagnosticsOf(st.version);
  r.diagnostics = d ? d.length : null;
  const ew = errorsWarnings(d);
  r.errors = d ? ew.filter((x) => x.sev === 1).length : null; r.warnings = d ? ew.filter((x) => x.sev === 2).length : null;
  if (ew.length) r.problems = ew.slice(0, 4);
  r.textAfterIsCurrent = (await g.currentText()) === after;
  r.workerDeaths = st.stats.workerDeaths - st0.stats.workerDeaths;
  // a QED64-handled L7 (its liveness: died "wedged", the relay rebooted and replayed the text) is the one accepted death:
  // exactly one per "wedged" reboot the gallery saw during this click (close-out 3: C23 found that this check used to
  // fail such a click with a misleading "0 errors / 0 warnings" message, so C20 could not have accepted one)
  r.unexplainedDeaths = r.workerDeaths - qw;
  r.ok = !!(r.editExact && r.nativeSha !== false && d && r.errors === 0 && r.warnings === 0 && r.textAfterIsCurrent && r.unexplainedDeaths === 0);
  if (!r.ok && !r.error) r.error = !r.editExact ? 'edit differs from the frozen edit' : r.nativeSha === false ? 'post-click text sha256 != native click-all' : !d ? 'no diagnostics for the edited version'
    : (r.errors || r.warnings) ? `${r.errors} errors / ${r.warnings} warnings after the click` : !r.textAfterIsCurrent ? 'the editor text changed after the click\'s re-check'
    : `${r.workerDeaths} worker death(s) during the click, ${qw} of them QED64 "wedged" reboot(s)`;
  r.ms = Date.now() - t0;
  return r;
}

/** Mark the k-th outermost element in the goal view whose text is exactly `target` (or the hypothesis name). */
export async function markSelectable(g, sel) {
  return g.iv.locator('body').evaluate((b, s) => {
    for (const el of b.querySelectorAll('[data-ux-sel]')) el.removeAttribute('data-ux-sel');
    const goals = [...b.querySelectorAll('.goal, div:has(> .goal-vdash)')];
    const scope = goals[s.goal || 0] ? goals[s.goal || 0] : b;
    let cands;
    if (s.hyp) cands = [...b.querySelectorAll('.goal-hyp, .goal-hyp *')].filter((e) => e.children.length === 0 && e.textContent.trim() === s.hyp);
    else {
      const norm = (t) => t.replace(/\s+/g, ' ').trim().replace(/^\((.*)\)$/, '$1');
      const all = [...scope.querySelectorAll('span')].filter((e) => norm(e.textContent) === s.target);
      cands = all.filter((e) => !all.includes(e.parentElement));
    }
    const el = cands[s.occurrence || 0];
    if (!el) return { ok: false, n: cands.length };
    el.setAttribute('data-ux-sel', String(s.k));
    return { ok: true, n: cands.length, tag: el.tagName.toLowerCase() };
  }, sel);
}

/**
 * A golden selection (lean/expect/…/selections[i]) through real shift-clicks: BEFORE the unselected panel equals its
 * golden and nothing is selected; shift-click each pick; AFTER the panel equals the golden of exactly this selection
 * (full signature) with >= one selected subterm per pick; shift-click them off; the unselected golden is back.
 */
export async function checkSelection(g, id, gsel) {
  const at = { line: gsel.line, character: gsel.character };
  const base = goldenCursor(id, gsel.line, gsel.character);
  const r = { at: `${at.line}:${at.character}`, picks: gsel.select, ok: false };
  const t0 = Date.now();
  await g.setCursor(at.line, at.character);
  await g.ivSettled();
  const pre = await g.expectPanel(at, base.panels[0], { timeoutMs: 60000 });
  const preSig = await g.signature(at, { panelTitle: base.panels[0].panelTitle || null });
  r.before = { equal: pre.equal, selectedCount: preSig.selectedCount };
  if (!pre.equal || preSig.selectedCount !== 0) { r.error = `before: ${pre.equal ? `${preSig.selectedCount} selected` : pre.diffs.slice(0, 2).join('; ')}`; return r; }
  r.marks = [];
  for (let k = 0; k < gsel.select.length; k++) {
    const m = await until(() => markSelectable(g, { ...gsel.select[k], k }).then((x) => (x.ok ? x : null)), { timeoutMs: 20000 });
    r.marks.push(m);
    if (!m) { r.error = `selectable ${JSON.stringify(gsel.select[k])} not found`; return r; }
    await g.iv.locator(`[data-ux-sel="${k}"]`).click({ modifiers: ['Shift'] });
    await sleep(500);
    await g.iv.locator(`[data-ux-sel="${k}"]`).evaluate((e, kk) => { e.setAttribute('data-ux-pick', String(kk)); }, k);
  }
  const post = await g.expectPanel(at, gsel.panels[0], { timeoutMs: 60000 });
  const postSig = await g.signature(at, { panelTitle: gsel.panels[0].panelTitle || null });
  r.after = { equal: post.equal, selectedCount: postSig.selectedCount, diffs: post.diffs.slice(0, 4), ms: post.ms };
  for (let k = gsel.select.length - 1; k >= 0; k--) await g.iv.locator(`[data-ux-pick="${k}"]`).click({ modifiers: ['Shift'] }).catch(() => {});
  const cleared = await g.expectPanel(at, base.panels[0], { timeoutMs: 30000 });
  const clrSig = await g.signature(at, { panelTitle: base.panels[0].panelTitle || null });
  r.cleared = { equal: cleared.equal, selectedCount: clrSig.selectedCount };
  r.ok = post.equal && postSig.selectedCount >= gsel.select.length && cleared.equal && clrSig.selectedCount === 0;
  if (!r.ok) r.error = !post.equal ? `after: ${post.diffs.slice(0, 3).join('; ')}` : postSig.selectedCount < gsel.select.length ? `after: ${postSig.selectedCount} selected` : 'not cleared';
  r.ms = Date.now() - t0;
  return r;
}

const POPUP = '.tooltip .tooltip-code-content';
/** The golden hover through a real mouse hover: popup text exactly "<expr> : <type>", gone after mouse-out. */
export async function checkHover(g, id, gh, popupText) {
  const cur = cursorOfLine(id, gh.cursorLine);
  const at = { line: cur.line, character: cur.character };
  const r = { at: `${at.line}:${at.character}`, tagText: gh.tagText, codeText: gh.codeText, ok: false };
  await g.setCursor(at.line, at.character);
  await g.ivSettled();
  const p = await g.expectPanel(at, goldenCursor(id, at.line, at.character).panels[0], { timeoutMs: 60000 });
  if (!p.equal) { r.error = `panel: ${p.diffs.slice(0, 2).join('; ')}`; return r; }
  const popups = () => g.iv.locator(POPUP).evaluateAll((els) => els.map((e) => e.textContent.replace(/\s+/g, ' ').trim()));
  r.before = await popups();
  const mk = await g.iv.locator('[data-ux-panel]').evaluate((p2, hv) => {
    for (const e of document.querySelectorAll('[data-ux-hover]')) e.removeAttribute('data-ux-hover');
    const norm = (t) => t.replace(/\s+/g, ' ').trim();
    const codes = [...p2.querySelectorAll('.font-code, code')].filter((c) => norm(c.textContent) === hv.codeText);
    const code = codes[hv.code || 0] || codes[0];
    if (!code) return { ok: false, why: `no code element ${hv.codeText}` };
    const all = [code, ...code.querySelectorAll('*')].filter((e) => norm(e.textContent) === hv.tagText);
    const el = all.find((e) => ![...e.children].some((c) => all.includes(c))) || null;
    if (!el) return { ok: false, why: `no tag ${hv.tagText}` };
    el.setAttribute('data-ux-hover', '1');
    return { ok: true, hasTooltip: el.hasAttribute('data-has-tooltip-on-hover') };
  }, gh);
  r.target = mk;
  if (!mk.ok) { r.error = mk.why; return r; }
  const t = Date.now();
  await g.iv.locator('[data-ux-hover]').hover();
  const got = await until(async () => { const pp = await popups(); return pp.includes(popupText) ? pp : null; }, { timeoutMs: 15000 });
  r.hoverToPopupMs = Date.now() - t;
  r.popups = got || await popups();
  await g.page.mouse.move(3, 3);
  r.closed = !!(await until(async () => ((await popups()).length === 0 ? true : null), { timeoutMs: 10000 }));
  r.ok = r.before.length === 0 && !!got && r.closed;
  if (!r.ok) r.error = r.before.length ? 'popup open before the hover' : !got ? `no popup “${popupText}”` : 'popup did not close';
  return r;
}

/**
 * A golden code action through Monaco's own UI: cursor at the action's position, the quick-fix menu opened with the
 * lightbulb (via: 'lightbulb') or Cmd/Ctrl+. (via: 'keyboard'), the item whose label is exactly the golden title
 * clicked with the mouse; the document must change by exactly the golden edit (== the Try-this link's edit) and
 * re-check clean.
 */
export async function checkCodeAction(g, ex, ca, { via = 'keyboard', linkEditedSha256 = null } = {}) {
  const act = ca.actions[0];
  const r = { at: `${ca.line}:${ca.character}`, via, title: act.title, ok: false };
  if ((await g.currentText()) !== ex.text) { const rs = await g.resetUI(ex); if (!rs.ok) { r.error = 'reset failed'; return r; } }
  const st0 = await g.qstatus();
  await g.setCursor(ca.line, ca.character);
  await g.focusEditor();
  await sleep(300);
  const qf = g.qframe;
  const t = Date.now();
  if (via === 'lightbulb') {
    const lb = qf.locator('.lightBulbWidget');
    const shown = await until(async () => ((await lb.count()) && (await lb.first().isVisible()) ? true : null), { timeoutMs: 30000 });
    r.lightbulbMs = Date.now() - t;
    if (!shown) { r.error = 'no lightbulb'; return r; }
    await lb.first().click();
  } else {
    await g.page.keyboard.press('ControlOrMeta+Period');
  }
  const row = qf.locator('.action-widget .monaco-list-row.action').filter({ hasText: act.title.split('\n')[0] });
  const ok = await until(async () => ((await row.count()) ? true : null), { timeoutMs: 30000 });
  r.menuMs = Date.now() - t;
  r.menu = await qf.locator('.action-widget .monaco-list-row').evaluateAll((els) => els.map((e) => ({ role: e.getAttribute('role'), label: e.getAttribute('aria-label') || e.textContent.trim() }))).catch(() => []);
  if (!ok) { r.error = 'quick-fix menu has no matching item'; await g.page.keyboard.press('Escape'); return r; }
  // Monaco's action list renders a multi-line title on one line: each newline of the title becomes one space (seen:
  // golden "…List.append_nil,\n  List.map_id_fun…" → label "…List.append_nil,   List.map_id_fun…"); everything else exact
  r.labelExact = r.menu.some((m) => m.role === 'option' && m.label === act.title.replace(/\r?\n/g, ' '));
  const before = await g.currentText();
  const v0 = (await g.qstatus()).version;
  const lv0 = ((await g.status()) || {}).liveness || null;
  // Monaco's action widget lays an invisible full-window div.context-view-pointerBlock over the page until the mouse
  // moves (it removes itself on mousemove, exactly as for a user); so move the real mouse onto the item first.
  const box = await row.first().boundingBox();
  if (box) await g.page.mouse.move(box.x + box.width / 2, box.y + box.height / 2, { steps: 3 });
  await sleep(150);
  r.pointerBlockAfterMove = await qf.locator('.context-view-pointerBlock').count();
  const tc = Date.now();
  await row.first().click();
  const after = await until(async () => { const x = await g.currentText(); return x !== before ? x : null; }, { timeoutMs: 15000, intervalMs: 40 });
  r.clickToEditMs = Date.now() - tc;
  if (!after) { r.error = 'the code action did not change the document'; return r; }
  const e = act.edits[0];
  r.editExact = after === applyEdit(before, e.range, e.newText);
  if (linkEditedSha256) r.sameAsLinkClick = sha256(after) === linkEditedSha256;
  const st = await g.waitReady({ minVersion: v0, timeoutMs: 300000 });
  if (!st) { r.error = 'not ready after the code action'; return r; }
  const d = await g.diagnosticsOf(st.version);
  const ew = errorsWarnings(d);
  r.errors = d ? ew.filter((x) => x.sev === 1).length : null; r.warnings = d ? ew.filter((x) => x.sev === 2).length : null;
  r.workerDeaths = st.stats.workerDeaths - st0.stats.workerDeaths;
  r.clickToReadyMs = Date.now() - tc;
  r.ok = !!(r.labelExact && r.editExact && r.sameAsLinkClick !== false && d && r.errors === 0 && r.warnings === 0 && r.workerDeaths === 0);
  if (!r.ok && !r.error) r.error = !r.labelExact ? 'menu label differs from the golden title' : !r.editExact ? 'edit differs' : r.sameAsLinkClick === false ? 'differs from the [apply] edit' : `${r.errors} errors / ${r.warnings} warnings`;
  return r;
}

/** Toggle a <details> summary in the panel with the mouse (collapse, then expand) and require the golden back. */
export async function checkToggle(g, id, cur, which) {
  const gc = goldenCursor(id, cur.line, cur.character);
  const at = { line: cur.line, character: cur.character };
  await g.setCursor(at.line, at.character);
  await g.ivSettled();
  const p = await g.expectPanel(at, gc.panels[0], { timeoutMs: 60000 });
  const r = { at: `${at.line}:${at.character}`, which, ok: false };
  if (!p.equal) { r.error = `panel: ${p.diffs.slice(0, 2).join('; ')}`; return r; }
  // which: 'panel' = the "HTML Display" summary itself; 'inner' = the first <details> summary inside the widget
  const mark = await g.iv.locator('[data-ux-panel]').evaluate((root, w) => {
    for (const e of document.querySelectorAll('[data-ux-toggle]')) e.removeAttribute('data-ux-toggle');
    const d = w === 'panel' ? root.parentElement : root.tagName === 'DETAILS' ? root : root.querySelector('details');
    if (!d || d.tagName !== 'DETAILS') return null;
    d.setAttribute('data-ux-toggle', '1');
    return { open: d.open, summary: (d.querySelector(':scope > summary') || {}).textContent.trim().slice(0, 60) };
  }, which);
  if (!mark) { r.error = 'no details to toggle'; return r; }
  r.summary = mark.summary; r.open0 = mark.open;
  const sum = g.iv.locator('[data-ux-toggle] > summary');
  const isOpen = () => g.iv.locator('[data-ux-toggle]').evaluate((d) => d.open);
  const visibleH = () => g.iv.locator('[data-ux-toggle]').evaluate((d) => d.getBoundingClientRect().height);
  const h0 = await visibleH();
  await sum.click();
  r.open1 = await until(async () => ((await isOpen()) !== mark.open ? String(await isOpen()) : null), { timeoutMs: 5000 });
  const h1 = await visibleH();
  await sum.click();
  r.open2 = await until(async () => ((await isOpen()) === mark.open ? String(await isOpen()) : null), { timeoutMs: 5000 });
  const h2 = await visibleH();
  r.heights = [Math.round(h0), Math.round(h1), Math.round(h2)];
  const back = await g.expectPanel(at, gc.panels[0], { timeoutMs: 30000 });
  r.goldenBack = back.equal;
  r.ok = r.open1 === String(!mark.open) && r.open2 === String(mark.open) && (mark.open ? h1 < h0 : h1 > h0) && Math.abs(h2 - h0) < 2 && back.equal;
  if (!r.ok) r.error = `toggle: open ${mark.open} → ${r.open1} → ${r.open2}, heights ${r.heights}, golden back ${back.equal}`;
  return r;
}
export { BY_ID };
