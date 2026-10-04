// The gallery README's open questions, answered in real Chrome (one boot unless noted). Output: questions.json
//   q2 focus + InfoView following setPosition without a click      q3 Reset on identical text, and on a halted relay
//   q4 text sync under real typing (rangedChanges, lastText)        q9 clipboard (granted, and the execCommand fallback)
//   q10 F6 from inside Monaco back to the rail                      q11 the page's own #examples menu
//   q12 switch storm (8 selections in 2 s)                           q13 saved user buffer kept + restored; malformed #
//   q14 saved-buffer lifecycle over real reloads: edited example not a user buffer; history; Open = newest; chooser
// EVERY question has an explicit `ok` predicate over the fields gallery/README.md "Resolved questions" cites
// (bring-up audit 5 major: only q14 had one, and a Reset that did nothing passed q3). The run passes only if each
// wanted question (and the malformed-hash case) has ok === true; a question that was not reached counts as failed.
// Usage: scripts/with-browser-lock.sh bringup node tests/ux/bringup/questions.mjs [--only q2,q3]
import path from 'node:path';
import { chromium } from 'playwright';
import { ORIGIN, OUT, LAUNCH_ARGS, EXAMPLES, SEL, checkPanel, lockHeld, classifyConsole, consoleLine, watchConsole, api, infoview, ivText, ivSettled, waitGalleryReady, writeJson, sleep, until, installTap, tapSummary } from './lib.mjs';

lockHeld();
const argv = process.argv.slice(2);
const only = argv.includes('--only') ? argv[argv.indexOf('--only') + 1].split(',') : null;
const want = (q) => !only || only.includes(q);
const ALL_QS = ['q2', 'q3', 'q4', 'q9', 'q10', 'q11', 'q12', 'q13', 'q14'];
const firstCursorExp = (id) => { const ex = EXAMPLES.find((e) => e.id === id); const h = ex.tryThis.find((x) => x.kind === 'cursor' && x.line === ex.firstCursor.line && x.character === ex.firstCursor.character); return h && h.expectPanel; };
/** log one question's verdict, with the failing predicate parts */
const verdict = (q, parts) => { const bad = Object.entries(parts).filter(([, v]) => !v).map(([k]) => k); res[q].ok = bad.length === 0; res[q].failedChecks = bad; console.log(`${q} ${res[q].ok ? 'OK' : `FAIL (${bad.join(', ')})`}`); };
const byId = Object.fromEntries(EXAMPLES.map((e) => [e.id, e]));
const t0 = Date.now();
const res = {};
const pe = (page, fn, arg) => page.evaluate(([src, a]) => { const w = document.getElementById('qed64-frame').contentWindow; return new w.Function('arg', `return (${src})(arg);`)(a); }, [fn.toString(), arg === undefined ? null : arg]);
const qs = (page) => pe(page, () => { const s = window.qed64.status(); const r = window.qed64.relay; return { phase: s.phase, version: s.version, relay: s.relay, session: s.session, stats: { ...r.stats }, lastTextLen: r.lastText.length, lastTextEqModel: r.lastText === window.qed64.editor.getModel().getValue() }; });

const ORIG = 'theorem my_own_buffer : 1 + 1 = 2 := rfl\n';
const browser = await chromium.launch({ args: LAUNCH_ARGS });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
const tapReports = await installTap(ctx); // LSP tap: pairs each empty console.error with its -32800 reply (console.mjs pairWith)
// q13: a pre-existing user buffer on this origin before the gallery's first visit
await ctx.addInitScript((orig) => { try { if (location.pathname === '/showcase/pin.json' && !localStorage.getItem('qed64.buffer')) localStorage.setItem('qed64.buffer', orig); } catch { /* ignore */ } }, ORIG);
const page = await ctx.newPage();
const watch = watchConsole(page, t0, 'questions.console.jsonl');
try {
  await page.goto(`${ORIGIN}/showcase/pin.json`); // seeds the "user's" buffer via the init script
  // malformed deep link + q13 (saved before seeding)
  await page.goto(`${ORIGIN}/showcase/#%`, { waitUntil: 'domcontentloaded' });
  const b = await waitGalleryReady(page);
  const s0 = await api.status(page);
  res.malformedHash = { phase: s0.phase, shown: s0.shown, notice: s0.notice, pageErrors: watch.pageErrors.filter((e) => /URI/.test(e.message)).length };
  res.q13 = { seed: s0.seed, saved: s0.saved, savedValue: await page.evaluate(() => localStorage.getItem('qed64-showcase:saved')), restoreVisible: await page.locator('#restore-btn').isVisible() };
  res.bootMs = b.ms;
  res.malformedHash.ok = res.malformedHash.phase === 'ready' && res.malformedHash.shown === EXAMPLES[0].id && /no example called “%”/.test(res.malformedHash.notice || '') && res.malformedHash.pageErrors === 0;
  console.log(`malformedHash ${res.malformedHash.ok ? 'OK' : 'FAIL'} ${JSON.stringify(res.malformedHash)}`);

  if (want('q2')) {
    // after a selection: where is keyboard focus?
    await api.select(page, 'graph-scope');
    await sleep(800);
    res.q2 = {
      topActive: await page.evaluate(() => document.activeElement && (document.activeElement.id || document.activeElement.tagName)),
      pageActive: await pe(page, () => { const a = document.activeElement; return a && (a.className || a.tagName); }),
      editorHasTextFocus: await pe(page, () => window.qed64.editor.hasTextFocus()),
    };
    // type a key: does it land in Monaco? (then undo it)
    const v0 = (await qs(page)).version;
    await page.keyboard.press('End');
    await page.keyboard.type(' ');
    res.q2.typedLanded = (await api.text(page)) !== byId['graph-scope'].text;
    await page.keyboard.press('Backspace');
    await until(async () => (await api.text(page)) === byId['graph-scope'].text, { timeoutMs: 5000 });
    await until(async () => { const s = await qs(page); return s.phase === 'ready' && s.version > v0; }, { timeoutMs: 60000 });
    // focus the rail, then move the cursor PROGRAMMATICALLY (no click, no focus): does the InfoView follow?
    res.q2.undone = (await api.text(page)) === byId['graph-scope'].text;
    await page.locator('#card-graph-scope').focus();
    res.q2.headerBefore = (await ivText(page)).split('\n')[0];
    await pe(page, () => window.qed64.editor.setPosition({ lineNumber: 30, column: 1 }));
    await sleep(2500); await ivSettled(page);
    const t1 = await ivText(page);
    res.q2.followsWithoutFocus = { header: t1.split('\n')[0], showsLine30Panel: /components: 2 \(disconnected\)/.test(t1) };
    res.q2.topActiveAfter = await page.evaluate(() => document.activeElement && document.activeElement.id);
    res.q2.editorFocusedAfter = await pe(page, () => window.qed64.editor.hasTextFocus());
    await page.screenshot({ path: path.join(OUT, 'q2-focus.png') });
    verdict('q2', {
      frameActive: res.q2.topActive === 'qed64-frame', monacoInput: /inputarea/.test(res.q2.pageActive || ''), editorHasTextFocus: res.q2.editorHasTextFocus,
      typedLanded: res.q2.typedLanded, undone: res.q2.undone, movedFromElsewhere: res.q2.headerBefore !== 'Probe.lean:30:0',
      followsHeader: res.q2.followsWithoutFocus.header === 'Probe.lean:30:0', followsPanel: res.q2.followsWithoutFocus.showsLine30Panel,
      focusStayedOnRail: res.q2.topActiveAfter === 'card-graph-scope' && !res.q2.editorFocusedAfter,
    });
  }

  if (want('q3')) {
    // (a) Reset on identical text must emit a didChange (version bump, same session)
    await api.select(page, 'chart-kit');
    const a = await qs(page);
    const t = Date.now();
    await page.locator('#reset-btn').click();
    const doneA = await until(async () => { const s = await api.status(page); return s.phase === 'ready' && s.op.label === 'reset' && s.op.doneMs != null ? s : null; }, { timeoutMs: 60000 });
    const b2 = await qs(page);
    res.q3 = { identical: { resetFinished: !!doneA, versionBefore: a.version, versionAfter: b2.version, bumped: b2.version > a.version, ms: Date.now() - t, sessionSame: a.session === b2.session } };
    // (b) trip the crash breaker through the relay's real death path (3 deaths inside 120 s)
    const exp = firstCursorExp('chart-kit');
    const pre = (await until(async () => { const c = await checkPanel(page, exp); return c.ok ? c : null; }, { timeoutMs: 60000 })) || (await checkPanel(page, exp));
    res.q3.panelBeforeHalt = { ok: pre.ok, at: pre.at };
    await pe(page, () => { const r = window.qed64.relay; for (let i = 0; i < 3; i++) r.session.lean.died(null, 'crash', `bring-up breaker test ${i}`); return r.state.kind; });
    const halted = await until(async () => { const s = await api.status(page); return s.phase === 'halted' ? s : null; }, { timeoutMs: 15000 });
    const hq = await qs(page);
    res.q3.halted = { gallery: halted && halted.phase, card: halted && halted.error && halted.error.title, cardVisible: await page.locator('#error-card').isVisible(), relay: hq.relay, session: hq.session, version: hq.version, stats: hq.stats };
    // The old panel is still on screen while the relay is halted (the InfoView keeps its last render), so "panel back"
    // alone proves nothing (audit 5 mutant E). Make the stale state observable first: tag the stale panel element,
    // and move the cursor off the widget line (programmatically, while halted) so that the InfoView must re-request
    // the panel after Reset; then require the panel to come back as a NEW element, from the NEW session.
    const staleTagged = await infoview(page).locator('[data-bringup-panel]').evaluate((el) => { el.setAttribute('data-q3-stale', '1'); return true; }).catch(() => false);
    await pe(page, () => window.qed64.editor.setPosition({ lineNumber: 1, column: 1 }));
    await sleep(3000);
    const awayChk = await checkPanel(page, exp);
    res.q3.haltedCursorAway = { staleTagged, panelStillShown: awayChk.ok, heads: awayChk.heads, ivHead: (await ivText(page)).slice(0, 160) };
    await page.screenshot({ path: path.join(OUT, 'q3-halted.png') });
    // (c) Reset re-arms the relay: ready on a NEW session, a NEW document version, the halted card gone
    const t2 = Date.now();
    await page.locator('#reset-btn').click();
    const back = await until(async () => { const s = await api.status(page); return s.phase === 'ready' && s.qed64 && s.qed64.relay === 'serving' && s.qed64.session !== hq.session && s.op.label === 'reset' && s.op.doneMs != null ? s : null; }, { timeoutMs: 120000 });
    const aq = await qs(page);
    // a halted status reports version null: versionIncreased compares with the last ready version (b2) too
    res.q3.afterReset = { ok: !!back, ms: Date.now() - t2, session: aq.session, newSession: !!aq.session && aq.session !== hq.session, version: aq.version, lastReadyVersion: b2.version, versionIncreased: Number.isInteger(aq.version) && aq.version > Math.max(b2.version ?? -1, hq.version ?? -1), relay: aq.relay, errorCard: back ? back.error : null, cardHidden: !(await page.locator('#error-card').isVisible()), stats: aq.stats };
    // (d) the panel at the first cursor, rendered afresh (not the tagged stale element)
    const tp = Date.now();
    let fresh = null;
    await until(async () => {
      const c = await checkPanel(page, exp);
      if (!c.ok) return null;
      const stale = await infoview(page).locator('[data-bringup-panel]').evaluate((el) => el.hasAttribute('data-q3-stale') || !!el.closest('[data-q3-stale]')).catch(() => true);
      fresh = { ok: true, stale, at: c.at };
      return stale ? null : fresh;
    }, { timeoutMs: 60000, intervalMs: 300 });
    res.q3.panelBack = !!(fresh && !fresh.stale);
    res.q3.panelBackDetail = fresh;
    res.q3.panelBackMs = Date.now() - tp;
    res.q3.ivHeadAfterReset = (await ivText(page)).slice(0, 300);
    await page.screenshot({ path: path.join(OUT, 'q3-after-reset.png') });
    verdict('q3', {
      identicalFinished: res.q3.identical.resetFinished, identicalBumped: res.q3.identical.bumped, identicalSameSession: res.q3.identical.sessionSame,
      panelBeforeHalt: res.q3.panelBeforeHalt.ok,
      haltedGallery: res.q3.halted.gallery === 'halted', haltedRelay: res.q3.halted.relay === 'halted', haltedCard: res.q3.halted.card === 'The Lean checker stopped' && res.q3.halted.cardVisible,
      breakerTripped: (res.q3.halted.stats.breakerTrips || 0) >= 1,
      staleObservable: res.q3.haltedCursorAway.staleTagged && !res.q3.haltedCursorAway.panelStillShown,
      afterResetReady: res.q3.afterReset.ok, newSession: res.q3.afterReset.newSession, versionIncreased: res.q3.afterReset.versionIncreased,
      relayServing: res.q3.afterReset.relay === 'serving', cardGone: res.q3.afterReset.cardHidden && !res.q3.afterReset.errorCard,
      freshPanelBack: res.q3.panelBack,
    });
  }

  if (want('q4')) {
    await api.select(page, 'tree-scope');
    const a = await qs(page);
    await pe(page, () => { const e = window.qed64.editor; e.setPosition({ lineNumber: 17, column: 24 }); e.focus(); });
    await page.keyboard.type(', 40');
    await sleep(300);
    await until(async () => { const s = await qs(page); return s.phase === 'ready' && s.version > a.version; }, { timeoutMs: 60000 });
    const b4 = await qs(page);
    const st = await api.status(page);
    res.q4 = { before: a.stats.rangedChanges, after: b4.stats.rangedChanges, lastTextEqualsModel: b4.lastTextEqModel, versions: [a.version, b4.version], galleryEdited: st.edited, chip: await page.locator('#card-tree-scope .chip').textContent() };
    res.q4.panelSees40 = !!(await until(async () => /\b40\b/.test(await ivText(page)), { timeoutMs: 30000 }));
    res.q4.text17 = ((await api.text(page)) || '').split('\n')[16];
    await page.screenshot({ path: path.join(OUT, 'q4-edited.png') });
    await page.locator('#reset-btn').click();
    await until(async () => { const s = await api.status(page); return s.phase === 'ready' && !s.edited ? s : null; }, { timeoutMs: 60000 });
    res.q4.resetClearsEdited = !(await api.status(page)).edited;
    res.q4.restored = (await api.text(page)) === byId['tree-scope'].text;
    verdict('q4', {
      noRangedChanges: res.q4.before === 0 && res.q4.after === 0, lastTextEqualsModel: res.q4.lastTextEqualsModel, versionBumped: res.q4.versions[1] > res.q4.versions[0],
      typedText: res.q4.text17 === '#tree_scope [10, 20, 30, 40]', galleryEdited: res.q4.galleryEdited === true, chipEdited: /edited/.test(res.q4.chip || ''),
      panelSees40: res.q4.panelSees40, resetClearsEdited: res.q4.resetClearsEdited, restored: res.q4.restored,
    });
  }

  if (want('q9')) {
    await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: ORIGIN });
    await page.locator('#copy-btn').click();
    await sleep(200);
    const label = await page.locator('#copy-label').textContent();
    const clip = await page.evaluate(() => navigator.clipboard.readText()).catch((e) => `ERR ${e.message}`);
    const cur = (await api.status(page)).current;
    res.q9 = { granted: { label, equalsExample: clip === byId[cur].text } };
    await ctx.clearPermissions();
    await sleep(2000);
    await page.locator('#copy-btn').click();
    await sleep(200);
    res.q9.notGranted = { label: await page.locator('#copy-label').textContent() };
    verdict('q9', { grantedCopied: /Copied/.test(res.q9.granted.label || ''), clipboardEqualsExample: res.q9.granted.equalsExample === true, notGrantedCopied: /Copied/.test(res.q9.notGranted.label || '') });
  }

  if (want('q10')) {
    await page.locator('#qed64-frame').click({ position: { x: 300, y: 300 } }); // into Monaco
    await sleep(300);
    const inEditor = await pe(page, () => window.qed64.editor.hasTextFocus());
    await page.keyboard.press('F6');
    await sleep(300);
    const top = await page.evaluate(() => ({ id: document.activeElement && document.activeElement.id, cls: document.activeElement && document.activeElement.className }));
    const textUnchanged = (await api.text(page)) === byId[(await api.status(page)).current].text;
    await page.keyboard.press('F6');
    await sleep(300);
    res.q10 = { startedInEditor: inEditor, afterF6: top, textUnchanged, backInEditor: await pe(page, () => window.qed64.editor.hasTextFocus()) };
    const curId = (await api.status(page)).current;
    res.q10.current = curId;
    verdict('q10', { startedInEditor: inEditor === true, f6ToOpenCard: top.id === `card-${curId}`, textUnchanged, backInEditor: res.q10.backInEditor === true });
  }

  if (want('q11')) {
    res.q11 = { examplesMenuDisplay: await pe(page, () => getComputedStyle(document.getElementById('examples')).display) };
    // what the hidden menu would do (?pagebar=full keeps it): drive it directly and watch the gallery notice
    await pe(page, () => { const s = document.getElementById('examples'); s.value = 'init'; s.dispatchEvent(new Event('change', { bubbles: true })); });
    await sleep(1500);
    const st = await api.status(page);
    res.q11.afterStockExample = { edited: st.edited, chip: await page.locator(`#card-${st.current} .chip`).textContent(), firstLine: ((await api.text(page)) || '').split('\n')[0] };
    await page.locator('#reset-btn').click();
    await until(async () => { const s = await api.status(page); return s.phase === 'ready' && !s.edited ? s : null; }, { timeoutMs: 120000 });
    res.q11.resetRestores = (await api.text(page)) === byId[(await api.status(page)).current].text;
    verdict('q11', { menuHidden: res.q11.examplesMenuDisplay === 'none', replaced: !/^import Mathlib/.test(res.q11.afterStockExample.firstLine || 'import Mathlib'), edited: res.q11.afterStockExample.edited === true, chipEdited: /edited/.test(res.q11.afterStockExample.chip || ''), resetRestores: res.q11.resetRestores });
  }

  if (want('q12')) {
    const ids = ['chart-kit', 'hasse-view', 'interval-inspector', 'simp-lens', 'expr-xray', 'tree-scope', 'graph-scope', 'dist-lens'];
    const before = await qs(page);
    const t = Date.now();
    const results = await page.evaluate(async (ids) => {
      const ps = [];
      for (const id of ids) { ps.push(window.__showcase.select(id).then(() => 'ok', (e) => e.code || e.message)); await new Promise((r) => setTimeout(r, 250)); }
      return Promise.all(ps);
    }, ids);
    await ivSettled(page);
    await sleep(1500);
    const st = await api.status(page);
    const txt = await ivText(page);
    const after = await qs(page);
    res.q12 = { results, ms: Date.now() - t, shown: st.shown, panelIsLast: /dist: 6 outcomes over Fin 6/.test(txt), stalePanel: /bipartite|Sum of two dice/.test(txt), workerDeaths: after.stats.workerDeaths - before.stats.workerDeaths, rebootsDelta: after.stats.reboots - before.stats.reboots, bridge: await api.bridge(page) };
    res.q12.pool = await pe(page, () => window.qed64.status().pool);
    verdict('q12', {
      sevenSuperseded: results.length === 8 && results.slice(0, 7).every((r) => r === 'SUPERSEDED'), lastResolved: results[7] === 'ok', shownLast: res.q12.shown === 'dist-lens',
      panelIsLast: res.q12.panelIsLast, noStalePanel: !res.q12.stalePanel, noWorkerDeaths: res.q12.workerDeaths === 0, noReboot: res.q12.rebootsDelta === 0,
    });
  }

  if (want('q13')) {
    res.q13.initial = { seededSaved: !!(res.q13.seed && res.q13.seed.action === 'saved'), savedValueIsOriginal: res.q13.savedValue === ORIG, restoreVisible: res.q13.restoreVisible };
    const ok = await page.locator('#restore-btn').click().then(() => true, () => false);
    await sleep(500);
    const st = await api.status(page);
    res.q13.restore = { clicked: ok, textIsOriginal: (await api.text(page)) === ORIG, custom: st.custom, current: st.current };
    await sleep(1500);
    res.q13.restore.qed64 = (await qs(page)).phase;
    await page.screenshot({ path: path.join(OUT, 'q13-restored.png') });
    verdict('q13', { ...res.q13.initial, restoreClicked: ok, textIsOriginal: res.q13.restore.textIsOriginal, custom: res.q13.restore.custom === true, noCurrent: res.q13.restore.current === null, qed64Ready: res.q13.restore.qed64 === 'ready' });
  }
  if (want('q14')) {
    // saved-buffer lifecycle across real reloads (bring-up audit minor): an example edited in the gallery is persisted
    // by the page but must NOT become a "user buffer"; a later real user buffer goes to the history; "Open" opens the
    // NEWEST kept buffer and the chooser reaches the first one.
    const SECOND = 'theorem my_second_buffer : 2 + 2 = 4 := rfl\n';
    const ls = () => page.evaluate(() => ({ saved: localStorage.getItem('qed64-showcase:saved'), history: JSON.parse(localStorage.getItem('qed64-showcase:saved-history') || '[]'), exampleEdit: localStorage.getItem('qed64-showcase:edited-example'), buffer: localStorage.getItem('qed64.buffer') }));
    const persisted = (t) => until(async () => ((await ls()).buffer === t ? true : null), { timeoutMs: 10000 });
    const reload = async () => { await page.reload({ waitUntil: 'domcontentloaded' }); return waitGalleryReady(page); };
    res.q14 = {};
    await api.select(page, 'tree-scope');
    const edited = `${byId['tree-scope'].text}-- my edit of the example\n`;
    await pe(page, (t) => window.qed64.editor.getModel().setValue(t), edited);
    res.q14.editPersisted = !!(await persisted(edited));
    await reload();
    let st = await api.status(page); let l = await ls();
    res.q14.afterExampleEdit = { action: st.seed && st.seed.action, saved: l.saved === ORIG, history: l.history.length, exampleEditKept: l.exampleEdit === edited, entries: st.saved.entries, chooserVisible: await page.locator('#restore-pick').isVisible(), button: (await page.locator('#restore-btn').textContent()).trim() };
    // the user's own second file
    await page.locator('#restore-btn').click();
    await until(async () => ((await api.text(page)) === ORIG ? true : null), { timeoutMs: 10000 });
    await pe(page, (t) => window.qed64.editor.getModel().setValue(t), SECOND);
    res.q14.secondPersisted = !!(await persisted(SECOND));
    await reload();
    st = await api.status(page); l = await ls();
    res.q14.afterSecond = { action: st.seed && st.seed.action, saved: l.saved === ORIG, history: l.history, entries: st.saved.entries, chooserVisible: await page.locator('#restore-pick').isVisible(), options: await page.locator('#restore-pick option').allTextContents(), button: (await page.locator('#restore-btn').textContent()).trim() };
    await page.locator('#restore-btn').click();
    await until(async () => ((await api.text(page)) === SECOND ? true : null), { timeoutMs: 10000 });
    res.q14.openNewest = (await api.text(page)) === SECOND;
    await page.locator('#restore-pick').selectOption('1');
    await page.locator('#restore-btn').click();
    await until(async () => ((await api.text(page)) === ORIG ? true : null), { timeoutMs: 10000 });
    res.q14.openFirst = (await api.text(page)) === ORIG;
    st = await api.status(page);
    res.q14.custom = st.custom; res.q14.current = st.current;
    await page.locator('#restore-pick').scrollIntoViewIfNeeded();
    await page.screenshot({ path: path.join(OUT, 'q14-saved-chooser.png') });
    await page.locator('.rail-foot').screenshot({ path: path.join(OUT, 'q14-saved-chooser-rail.png') });
    res.q14.ok = res.q14.editPersisted && res.q14.afterExampleEdit.action === 'example' && res.q14.afterExampleEdit.saved && res.q14.afterExampleEdit.history === 0 && res.q14.afterExampleEdit.exampleEditKept
      && !res.q14.afterExampleEdit.chooserVisible && res.q14.secondPersisted && res.q14.afterSecond.action === 'history' && res.q14.afterSecond.saved
      && res.q14.afterSecond.history.length === 1 && res.q14.afterSecond.history[0] === SECOND && res.q14.afterSecond.chooserVisible && res.q14.afterSecond.options.length === 2
      && res.q14.openNewest && res.q14.openFirst && res.q14.custom === true && res.q14.current === null;
    console.log(`q14 ${res.q14.ok ? 'OK' : 'FAIL'} ${JSON.stringify(res.q14)}`);
  }
} catch (e) { res.error = String(e && e.stack || e).slice(0, 1500); }
res.crashed = watch.crashed; res.pageErrors = watch.pageErrors;
res.consoleErrors = watch.messages.filter((m) => m.type === 'error' || m.type === 'warning').map((m) => `${m.type} ${m.url}:${m.line} ${JSON.stringify(m.text.slice(0, 120))}`);
// q3 halts the relay (3 deaths trip the breaker) and restarts it: only then are the breaker's and the restarted
// relay's messages allowed (selectors.json consoleAllowlist.onlyInScenarios)
res.console = classifyConsole(watch, SEL.consoleAllowlist, { reports: tapReports, scenarios: want('q3') ? ['relayRestartOrReboot', 'crashBreakerTripped'] : [] }); res.tap = tapSummary(tapReports);
console.log(consoleLine(res.console));
res.wallMs = Date.now() - t0;
writeJson(only ? `questions-${only.join('-')}.json` : 'questions.json', res);
await browser.close();
// every WANTED question must exist with ok === true (missing = not reached = failed); malformedHash always runs.
// q13's record is created at boot, so it only counts when q13 itself was wanted.
const failedQs = [...ALL_QS.filter((q) => want(q) && !(res[q] && res[q].ok === true)), ...(res.malformedHash && res.malformedHash.ok === true ? [] : ['malformedHash'])];
const bad = !!res.error || res.crashed || !res.console.ok || failedQs.length > 0;
console.log(`QUESTIONS ${bad ? 'FAIL' : 'OK'}${res.error ? ' (error)' : ''}${failedQs.length ? ` failed ${failedQs}` : ''}${res.console.ok ? '' : ' (console)'}`);
process.exit(bad ? 1 : 0);
