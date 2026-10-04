// C15 stock-text regression, C16 forced collision ("Load exact imports" degrades gracefully), C17 gallery
// accessibility (keyboard-only walkthrough, aria, the veil out of the accessibility tree, forward focus order), C18 two
// tabs (record only), C19 headed sign-off (optional), C24 the browser capability card (before anything boots).
import { test, expect } from '../lib/fixtures.mjs';
import { Gallery, Stock, BY_ID, EXAMPLES, ORIGIN, CHANNEL, chromeRss, reclaimableGiB, screenPath, sleep, until, errorsWarnings } from '../lib/qed64.mjs';
import { goldenCursor } from '../lib/actions.mjs';

const firstAt = (id) => ({ line: BY_ID[id].firstCursor.line, character: BY_ID[id].firstCursor.character });

test('C15 stock regression: the page’s own EXAMPLES.mathlib text on the widgets8 superset is ready with 0 errors', async ({ ux }) => {
  const m = ux.metrics;
  const s = await ux.launch({ profile: 'fresh' });
  const st = await Stock.open(s, { buffer: null }); // no qed64.buffer: the page boots its built-in EXAMPLES.mathlib
  const r = await st.settle({ timeoutMs: 240000 });
  const q = await st.qstatus();
  const text = await st.text();
  const d = await st.diagnosticsOf(q.version);
  m.result = { phase: q.phase, header: q.header, firstLine: text.split('\n')[0], errors: (d || []).filter((x) => x.sev === 1), warnings: (d || []).filter((x) => x.sev === 2).map((x) => ({ line: x.line, msg: x.msg.slice(0, 80) })), collision: q.collision };
  await st.page.screenshot({ path: screenPath('C15-stock-mathlib.png') });
  console.log(`C15 ${JSON.stringify(m.result)}`);
  expect(r).toBeTruthy();
  expect(q.phase).toBe('ready');
  expect(text.startsWith('import Mathlib')).toBe(true);
  expect(d, 'diagnostics published').not.toBeNull();
  expect(m.result.errors).toEqual([]);
});

test('C16 forced collision: a name the covered superset already declares gets the stock note and offer; “Load exact imports” degrades gracefully', async ({ ux }) => {
  const m = ux.metrics;
  ux.scenarios.push('relayRestartOrReboot', 'exactImportsFallback');
  const s = await ux.launch({ profile: 'fresh' });
  const g = await Gallery.open(s, { hash: 'hasse-view' });
  expect(g.boot.s.phase).toBe('ready');
  const q0 = await g.qstatus();
  m.example = { collision: q0.collision, header: q0.header && q0.header.mode };
  const text = 'import Mathlib\nimport HasseView\n\n-- DistLens.Demo.die is in the widgets8 region but not in this header\'s closure\ndef DistLens.Demo.die : Nat := 0\n';
  const v0 = q0.version;
  await g.q((t) => window.qed64.editor.getModel().setValue(t), text);
  const st = await g.waitReady({ minVersion: v0, timeoutMs: 120000, text });
  const offer = g.qframe.locator('button, a').filter({ hasText: 'Load exact imports' });
  await until(async () => ((await offer.count()) ? true : null), { timeoutMs: 20000 });
  const q1 = await g.qstatus();
  const d1 = await g.diagnosticsOf(st.version);
  m.forced = { collision: q1.collision, header: q1.header && q1.header.mode, offer: await offer.count(), offerText: (await offer.count()) ? (await offer.first().textContent()).trim() : null, note: (d1 || []).filter((x) => x.sev === 3).map((x) => x.msg.slice(0, 200)), errors: (d1 || []).filter((x) => x.sev === 1).map((x) => x.msg.slice(0, 160)), galleryEdited: (await g.status()).edited };
  await g.page.screenshot({ path: screenPath('C16-collision-offer.png') });
  expect(m.example.collision, 'gallery examples never collide').toBeNull();
  expect(q1.collision, 'the forced name collides').not.toBeNull();
  expect(m.forced.offer).toBeGreaterThan(0);
  // take the offer: QED64 restarts with packs ['essential'] and warms the exact header; HasseView is not in the
  // essential pack, so the exact import fails and the page must fall back to the preloaded (covered) library
  const rss = []; const t = Date.now();
  const h = setInterval(() => rss.push(chromeRss().rendererBytes), 1000);
  await offer.first().click();
  const back = await until(async () => { const q = await g.qstatus(); return q && q.phase === 'ready' && q.stats.userRestarts > q0.stats.userRestarts ? q : null; }, { timeoutMs: 420000, intervalMs: 500 });
  clearInterval(h);
  const pill = await g.q(() => (document.getElementById('ptext') || {}).textContent || null);
  m.afterOffer = { ready: !!back, ms: Date.now() - t, header: back && back.header, collision: back && back.collision, userRestarts: back && back.stats.userRestarts, workerDeaths: back && back.stats.workerDeaths, pill, peakRendererGiB: +(Math.max(0, ...rss) / 1073741824).toFixed(2), peakRendererGB: +(Math.max(0, ...rss) / 1e9).toFixed(2), crashed: s.watches[0].crashed, warns: s.watches[0].messages.filter((x) => /exact import failed/.test(x.text)).map((x) => x.text.slice(0, 200)) };
  await g.page.screenshot({ path: screenPath('C16-after-exact-imports.png') });
  console.log(`C16 ${JSON.stringify(m)}`);
  expect(m.afterOffer).toMatchObject({ ready: true, crashed: false, workerDeaths: 0 });
  // the gallery can still show an example afterwards
  const r = await g.select('chart-kit');
  const p = await g.expectPanel(firstAt('chart-kit'), goldenCursor('chart-kit', firstAt('chart-kit').line, firstAt('chart-kit').character).panels[0], { timeoutMs: 120000 });
  m.recovered = { select: r.ok, panelEqual: p.equal };
  expect(m.recovered).toEqual({ select: true, panelEqual: true });
});

test('C17 gallery accessibility: keyboard-only walkthrough, roles, names, iframe title', async ({ ux }) => {
  const m = ux.metrics;
  const s = await ux.launch({ profile: 'warm' });
  const g = await Gallery.open(s, { hash: 'chart-kit' });
  expect(g.boot.s.phase).toBe('ready');
  const page = g.page;
  m.static = await page.evaluate(() => {
    const name = (el) => (el.getAttribute('aria-label') || el.textContent || el.getAttribute('title') || '').trim();
    const vis = (el) => !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
    return {
      lang: document.documentElement.lang,
      iframeTitle: document.getElementById('qed64-frame').getAttribute('title'),
      toolbar: (() => { const t = document.querySelector('[role=toolbar]'); return t ? t.getAttribute('aria-label') : null; })(),
      nav: (() => { const n = document.querySelector('nav'); return n ? n.getAttribute('aria-label') : null; })(),
      errorCardRole: document.getElementById('error-card').getAttribute('role'),
      liveRegion: document.getElementById('live-region').getAttribute('aria-live'),
      unnamedButtons: [...document.querySelectorAll('button')].filter((b) => vis(b) && !name(b)).map((b) => b.id || b.className),
      imgsWithoutAlt: [...document.querySelectorAll('img')].filter((i) => !i.hasAttribute('alt')).map((i) => i.getAttribute('src')),
      buttonsWithoutType: [...document.querySelectorAll('button')].filter((b) => !b.getAttribute('type')).length,
      skipLink: (() => { const a = document.querySelector('a[href^="#"]'); return a ? a.textContent.trim() : null; })(),
      cards: [...document.querySelectorAll('.card-main')].map((c) => ({ id: c.id, tabindex: c.getAttribute('tabindex'), current: c.getAttribute('aria-current') })),
    };
  });
  // keyboard only from here. After a boot the gallery has put focus in Monaco (so the InfoView follows the cursor).
  const active = () => page.evaluate(() => { const a = document.activeElement; return a ? { id: a.id || null, tag: a.tagName, cls: String(a.className).slice(0, 40), text: (a.getAttribute('aria-label') || a.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 50) } : null; });
  const editorFocused = () => g.q(() => window.qed64.editor.hasTextFocus());
  const text0 = await g.currentText();
  m.bootFocusInEditor = await editorFocused();
  await page.keyboard.press('F6'); await sleep(250);
  m.f6FromEditor = (await active()).id;                                   // the open card
  await page.keyboard.press('ArrowDown'); m.arrowDown = (await active()).id;
  m.focusVisible = await page.evaluate(() => { const cs = getComputedStyle(document.activeElement); return { outline: `${cs.outlineStyle} ${cs.outlineWidth}`, matches: document.activeElement.matches(':focus-visible') }; });
  await page.keyboard.press('End'); m.end = (await active()).id;
  await page.keyboard.press('Home'); m.home = (await active()).id;
  await page.keyboard.press('ArrowDown'); m.arrowDown2 = (await active()).id;
  const target = m.arrowDown2 && m.arrowDown2.replace(/^card-/, '');
  await page.keyboard.press('Enter');
  const sel = await until(async () => { const st = await g.status(); return st.phase === 'ready' && st.shown === target ? st : null; }, { timeoutMs: 120000 });
  m.enterOpened = { target, shown: sel && sel.shown, ariaCurrent: await page.locator(`#card-${target}`).getAttribute('aria-current'), editorFocus: await editorFocused() };
  await page.keyboard.press('F6'); await sleep(250);
  m.f6ToRail = (await active()).id;
  // Tab from the open card into its "Things to try"; Enter runs the first hint
  m.tabToHint = [];
  let hintFocused = null;
  for (let i = 0; i < 6; i++) { await page.keyboard.press('Tab'); const a = await active(); m.tabToHint.push(a && (a.id || a.cls)); if (a && /\bhint\b/.test(a.cls)) { hintFocused = a; break; } }
  m.hintFocused = hintFocused;
  const ex = BY_ID[target]; const h0 = ex.tryThis[0];
  if (hintFocused) {
    await page.keyboard.press('Enter');
    const st = await until(async () => { const x = await g.status(); return x.cursor && x.cursor.lineNumber === h0.lineNumber ? x : null; }, { timeoutMs: 30000 });
    m.hintEnter = { wantLine: h0.lineNumber, cursor: st && st.cursor, editorFocus: await editorFocused() };
  }
  await page.keyboard.press('F6'); await sleep(250);
  m.f6Back = (await active()).id;
  // backwards from the rail to the skip link, then use it
  m.shiftTab = [];
  let onSkip = false;
  for (let i = 0; i < 15; i++) { await page.keyboard.press('Shift+Tab'); const a = await active(); m.shiftTab.push(a && (a.id || a.cls || a.tag)); if (a && /skip-link/.test(a.cls)) { onSkip = true; break; } }
  m.reachedSkipLink = onSkip;
  if (onSkip) {
    await page.keyboard.press('Enter'); await sleep(500);
    const st = await g.status();
    m.skipLink = { active: (await active()).id, hash: await page.evaluate(() => location.hash), notice: st.notice, shown: st.shown, editorFocus: await editorFocused() };
  }
  m.textUnchanged = (await g.currentText()) === BY_ID[target].text;
  m.text0WasExample = text0 === BY_ID['chart-kit'].text;
  // (hardening lane) the veil, once hidden, is out of the accessibility tree and the focus order; the real browser's
  // capability check passed; then the forward Tab order from the top of the gallery document
  m.veil = await page.evaluate(() => { const v = document.getElementById('stage-veil'); const cs = getComputedStyle(v); return { hiddenClass: v.classList.contains('is-hidden'), ariaHidden: v.getAttribute('aria-hidden'), inert: v.inert === true, visibility: cs.visibility, opacity: cs.opacity }; });
  m.aria = await page.locator('body').ariaSnapshot();
  m.ariaHasVeilText = /Loading the gallery|Checking the widgets overlay/.test(m.aria);
  m.caps = (await g.status()).caps;
  // start from the top of the gallery document: F6 brings focus out of Monaco to the open card (proven above), blur it
  await page.keyboard.press('F6'); await sleep(250);
  // (Chrome keeps a sequential-navigation starting point at a blurred element, so the walk starts by focusing the skip link,
  // the first focusable element of the document; Shift+Tab reaching it from the rail is checked above)
  m.tabForward = await page.evaluate(() => { const a = document.activeElement; const was = a && a.id; const sk = document.getElementById('skip-link'); sk.focus(); return { was, first: document.activeElement === sk, restore: { pick: !document.getElementById('restore-pick').hidden, btn: !document.getElementById('restore-btn').hidden } }; });
  const focusInfo = () => page.evaluate(() => {
    const a = document.activeElement; if (!a || a === document.body) return null;
    const hiddenUp = (el) => { for (let e = el; e && e !== document.body; e = e.parentElement) { if (e.hidden || e.getAttribute('aria-hidden') === 'true' || e.inert) return true; const cs = getComputedStyle(e); if (cs.display === 'none' || cs.visibility === 'hidden') return true; } return false; };
    return { key: a.id || (a.classList.contains('hint') ? 'hint' : a.classList.contains('hints-toggle') ? 'hints-toggle' : a.tagName.toLowerCase()), inVeil: !!a.closest('#stage-veil'), hidden: hiddenUp(a), visible: !!(a.offsetWidth || a.offsetHeight || a.getClientRects().length), name: (a.getAttribute('aria-label') || a.textContent || a.getAttribute('title') || '').replace(/\s+/g, ' ').trim().slice(0, 40) };
  });
  m.tabOrder = [await focusInfo()];
  for (let i = 0; i < 30; i++) { await page.keyboard.press('Tab'); const f = await focusInfo(); m.tabOrder.push(f); if (!f || f.key === 'qed64-frame') break; }
  await page.screenshot({ path: screenPath('C17-keyboard.png') });
  console.log(`C17 ${JSON.stringify(m)}`);
  expect(m.static).toMatchObject({ lang: 'en', errorCardRole: 'alert', liveRegion: 'polite', unnamedButtons: [], imgsWithoutAlt: [], buttonsWithoutType: 0 });
  expect(m.static.iframeTitle).toBeTruthy(); expect(m.static.toolbar).toBeTruthy(); expect(m.static.nav).toBeTruthy();
  expect(m.bootFocusInEditor).toBe(true);
  expect(m.f6FromEditor).toBe('card-chart-kit');
  expect([m.arrowDown, m.end, m.home, m.arrowDown2]).toEqual(['card-hasse-view', 'card-dist-lens', 'card-chart-kit', 'card-hasse-view']);
  expect(m.focusVisible.outline, 'a visible focus ring on the card').not.toMatch(/^none/);
  expect(m.enterOpened).toMatchObject({ shown: target, ariaCurrent: 'true', editorFocus: true });
  expect(m.f6ToRail).toBe(`card-${target}`);
  expect(m.hintFocused, 'Tab reaches the open card’s hints').toBeTruthy();
  expect(m.hintEnter.cursor && m.hintEnter.cursor.lineNumber).toBe(h0.lineNumber);
  expect(m.f6Back).toBe(`card-${target}`);
  expect(m.reachedSkipLink, 'Shift+Tab reaches the skip link').toBe(true);
  expect(m.skipLink.notice, 'the skip link is not mistaken for a deep link').toBeNull();
  expect(m.skipLink).toMatchObject({ shown: target, hash: `#${target}`, active: 'qed64-frame', editorFocus: true });
  expect(m.textUnchanged, 'no keystroke leaked into the document').toBe(true);
  // the veil: hidden, aria-hidden, inert, not rendered, and nothing of it in the accessibility tree
  expect(m.veil).toMatchObject({ hiddenClass: true, ariaHidden: 'true', inert: true, visibility: 'hidden' });
  expect(m.ariaHasVeilText, 'the ready gallery\'s accessibility tree has no "Loading…" from the veil').toBe(false);
  expect(m.caps, 'this Chromium passes the capability check (isolated, SharedArrayBuffer, Memory64, deviceMemory)').toMatchObject({ ok: true, missing: [] });
  // forward focus order: skip link, the toolbar, the ONE rail card in the tab sequence (roving tabindex: the open card),
  // its "Things to try" buttons (folded to 4, then the toggle), then the QED64 editor; never a hidden or veiled element
  const keys = m.tabOrder.map((f) => f && f.key);
  const nHints = Math.min(4, BY_ID[target].tryThis.length);
  // the rail footer's kept-buffer controls come last when a buffer is kept (the warm profile may hold one)
  const want = ['skip-link', 'reset-btn', 'copy-btn', `card-${target}`, ...Array(nHints).fill('hint'), ...(BY_ID[target].tryThis.length > 4 ? ['hints-toggle'] : []),
    ...(m.tabForward.restore.pick ? ['restore-pick'] : []), ...(m.tabForward.restore.btn ? ['restore-btn'] : []), 'qed64-frame'];
  expect(m.tabForward).toMatchObject({ was: `card-${target}`, first: true });
  expect(keys, 'forward Tab order from the top of the gallery').toEqual(want);
  expect(m.tabOrder.filter((f) => f && (f.inVeil || f.hidden || !f.visible || !f.name)), 'every focus stop is visible, named, and not hidden or veiled').toEqual([]);
});

// C24 (hardening lane): the browser capability check runs before anything boots. A browser that lacks cross-origin
// isolation, SharedArrayBuffer or WebAssembly Memory64 gets a clear card ("This showcase needs a Chromium-based desktop
// browser (Chrome, Edge, Brave, Arc) on a computer with 16 GB of RAM or more, …; your browser lacks X"), no snapshot or
// runtime request and no QED64 navigation; a device that reports less than 8 GB (navigator.deviceMemory) gets a warning card whose "Try anyway"
// boots as usual. In this Chromium: (a) REAL: the gallery document served without COOP/COEP (the route strips them), so
// crossOriginIsolated is really false; (b) SIMULATED in the real browser: WebAssembly.validate refuses the 13-byte
// Memory64 probe (an init script, gallery window only); (c) SIMULATED: navigator.deviceMemory reads 4, then "Try anyway"
// boots a real QED64 session. No WebKit or Firefox build is cached on this host (~/Library/Caches/ms-playwright holds
// chromium-1234 and chromium_headless_shell-1234 only), so there is no run in another engine.
test('C24 capability card: no isolation / no Memory64 boots nothing and says why; low memory warns and "Try anyway" boots', async ({ ux }) => {
  test.setTimeout(10 * 60 * 1000);
  const m = ux.metrics;
  const s = await ux.launch({ profile: 'fresh' });
  const NEED = 'This showcase needs a Chromium-based desktop browser (Chrome, Edge, Brave, Arc) on a computer with 16 GB of RAM or more, one showcase tab at a time (a tab uses about 8–9 GB, about 12 GB on a reload); your browser lacks';
  const card = async (page) => page.evaluate(() => {
    const $ = (id) => document.getElementById(id); const vis = (el) => !!el && !el.hidden && getComputedStyle(el).display !== 'none' && !!(el.offsetWidth || el.offsetHeight);
    const st = window.__showcase && window.__showcase.status();
    return { phase: st && st.phase, caps: st && st.caps, cardVisible: vis($('error-card')), role: $('error-card').getAttribute('role'), title: $('error-title').textContent, detail: $('error-detail').textContent,
      checksBad: [...$('error-checks').querySelectorAll('li.bad')].map((li) => li.textContent), retry: vis($('error-retry')) ? $('error-retry').textContent : null, dismiss: vis($('error-dismiss')), stock: vis($('error-stock')),
      status: $('status-text').textContent, frameSrc: $('qed64-frame').getAttribute('src'), veilAriaHidden: $('stage-veil').getAttribute('aria-hidden'), cards: document.querySelectorAll('.card').length,
      // the stage fills the window below the top bar (it collapsed to 280 px with an empty rail before the layout fix) and the card is not clipped
      stageFills: $('stage').getBoundingClientRect().bottom >= innerHeight - 2, cardClipped: $('error-card').scrollHeight > $('error-card').clientHeight + 1 };
  });
  const watch = (page) => { const reqs = []; page.on('request', (r) => { const u = new URL(r.url()); if (/^\/(runtime|snapshots|profiles)\//.test(u.pathname) || (u.pathname === '/' && u.search.includes('snapshots='))) reqs.push(`${r.method()} ${u.pathname}${u.search}`); }); return reqs; };
  const openCase = async (label, setup) => {
    const page = await s.newPage(); const reqs = watch(page);
    await setup(page);
    await page.goto(`${ORIGIN}/showcase/#hasse-view`, { waitUntil: 'domcontentloaded' });
    const c = await until(async () => { const x = await card(page); return x && x.phase === 'unsupported' ? x : null; }, { timeoutMs: 30000, intervalMs: 100 });
    await sleep(1500); // nothing may start after the card either
    const after = await card(page);
    const sel = await page.evaluate(() => window.__showcase.select('chart-kit').then(() => 'resolved', (e) => e && e.code));
    await page.screenshot({ path: screenPath(`C24-${label}.png`) });
    return { page, c: after || c, reqs, sel };
  };
  // (a) REAL: no cross-origin isolation (COOP/COEP stripped from the gallery document only)
  const a = await openCase('no-isolation', (page) => page.route((u) => new URL(u).pathname === '/showcase/', async (route) => {
    const r = await route.fetch(); const h = { ...r.headers() }; delete h['cross-origin-opener-policy']; delete h['cross-origin-embedder-policy'];
    await route.fulfill({ response: r, headers: h });
  }));
  m.noIsolation = { ...a.c, coi: await a.page.evaluate(() => self.crossOriginIsolated), requests: a.reqs, select: a.sel };
  // (b) SIMULATED: Memory64 refused by WebAssembly.validate (the gallery window only; QED64's own worker never runs)
  const b = await openCase('no-memory64', (page) => page.addInitScript(() => {
    if (!location.pathname.startsWith('/showcase/')) return;
    const v = WebAssembly.validate; WebAssembly.validate = (bytes) => (bytes && bytes.length === 13 && bytes[8] === 5 && bytes[11] === 4 ? false : v(bytes));
  }));
  m.noMemory64 = { ...b.c, requests: b.reqs, select: b.sel };
  await a.page.close(); await b.page.close();
  console.log(`C24 ${JSON.stringify({ noIsolation: m.noIsolation, noMemory64: m.noMemory64 })}`);
  for (const [x, words, id] of [[m.noIsolation, 'cross-origin isolation', 'coi'], [m.noMemory64, 'WebAssembly Memory64', 'memory64']]) {
    expect(x, `${id}: the hard card, nothing loaded`).toMatchObject({ phase: 'unsupported', cardVisible: true, stageFills: true, cardClipped: false, role: 'alert', title: 'This browser cannot run the Lean widget gallery', retry: null, dismiss: false, stock: false, frameSrc: null, veilAriaHidden: 'true', status: 'This browser cannot run the gallery', requests: [], select: 'UNSUPPORTED' });
    expect(x.detail.startsWith(`${NEED} ${words}.`), `"${x.detail}"`).toBe(true);
    expect(x.caps.missing).toEqual([id]);
    expect(x.checksBad.length).toBe(1);
  }
  expect(m.noIsolation.coi, 'the route really removed isolation').toBe(false);
  // (c) SIMULATED low memory: the warning card, nothing loaded until "Try anyway", which then boots a real session
  const page = await s.newPage(); const reqs = watch(page);
  await page.addInitScript(() => { if (location.pathname.startsWith('/showcase/')) Object.defineProperty(Navigator.prototype, 'deviceMemory', { get: () => 4, configurable: true }); });
  await page.goto(`${ORIGIN}/showcase/#hasse-view`, { waitUntil: 'domcontentloaded' });
  const c0 = await until(async () => { const x = await card(page); return x && x.phase === 'unsupported' ? x : null; }, { timeoutMs: 30000, intervalMs: 100 });
  await sleep(1500);
  m.lowMemory = { ...(await card(page)), requestsBefore: reqs.slice() };
  await page.screenshot({ path: screenPath('C24-low-memory.png') });
  expect(c0).toBeTruthy();
  expect(m.lowMemory).toMatchObject({ phase: 'unsupported', cardVisible: true, stageFills: true, cardClipped: false, title: 'This device may not have enough memory', retry: 'Try anyway', dismiss: false, stock: false, frameSrc: null, cards: 8, requestsBefore: [] });
  expect(m.lowMemory.detail.startsWith(`${NEED} enough memory.`)).toBe(true);
  expect(m.lowMemory.caps).toMatchObject({ missing: ['memory'], hard: [], deviceMemory: 4 });
  await page.locator('#error-retry').click();
  const g = new Gallery(s, page);
  const boot = await g.waitGallery();
  m.tryAnyway = { phase: boot.s && boot.s.phase, shown: boot.s && boot.s.shown, override: boot.s && boot.s.caps.override, cardHidden: await page.locator('#error-card').isHidden(), snapzOrIndexRequests: reqs.length };
  console.log(`C24 (c) ${JSON.stringify({ lowMemory: m.lowMemory, tryAnyway: m.tryAnyway })}`);
  expect(m.tryAnyway).toMatchObject({ phase: 'ready', shown: 'hasse-view', override: true, cardHidden: true });
  expect(m.tryAnyway.snapzOrIndexRequests, 'the boot after "Try anyway" did load the snapshots').toBeGreaterThan(0);
});

test('C18 two tabs at once (record only): renderer RSS with two QED64 sessions', async ({ ux }) => {
  const m = ux.metrics; ux.recordOnly = true;
  const s = await ux.launch({ profile: 'warm' });
  const g1 = await Gallery.open(s, { hash: 'chart-kit' });
  m.tab1 = { phase: g1.boot.s.phase, ms: g1.boot.ms, rss: chromeRss() };
  m.reclaimableBeforeTab2 = +reclaimableGiB().toFixed(1);
  if (m.reclaimableBeforeTab2 < 12) { m.tab2 = { skipped: `only ${m.reclaimableBeforeTab2} GiB reclaimable (< 12 GiB): not opening a second QED64 session` }; return; }
  const p2 = await s.newPage();
  const peak = { r: 0, b: 0 }; const h = setInterval(() => { const x = chromeRss(); peak.r = Math.max(peak.r, x.rendererGiB); peak.b = Math.max(peak.b, x.rendererBytes); }, 1000);
  const g2 = await Gallery.open(s, { hash: 'graph-scope', page: p2 });
  await sleep(3000);
  clearInterval(h);
  const st1 = await g1.status().catch(() => null);
  m.tab2 = { phase: g2.boot.s && g2.boot.s.phase, ms: g2.boot.ms, tab1After: st1 && st1.phase, rss: chromeRss(), peakRendererGiB: peak.r, peakRendererGB: +(peak.b / 1e9).toFixed(2), crashed: s.watches.map((w) => w.crashed) };
  await p2.screenshot({ path: screenPath('C18-tab2.png') });
  console.log(`C18 ${JSON.stringify(m)}`);
});

test('C19 headed Chrome-for-Testing sign-off (optional; UX_HEADED=1, or UX_HEADED_ALL=1 for the whole suite headed)', async ({ ux }) => {
  test.skip(process.env.UX_HEADED !== '1' && process.env.UX_HEADED_ALL !== '1', 'optional headed run: set UX_HEADED=1 (it opens a visible browser window on the desktop)');
  const m = ux.metrics;
  const s = await ux.launch({ profile: 'fresh', headed: true, channel: CHANNEL || 'chromium' }); // UX_CHANNEL=chrome: branded Chrome
  const g = await Gallery.open(s, { hash: 'hasse-view' });
  const at = firstAt('hasse-view');
  const p = await g.expectPanel(at, goldenCursor('hasse-view', at.line, at.character).panels[0], { timeoutMs: 60000 });
  m.headed = { phase: g.boot.s.phase, bootMs: g.boot.ms, panelEqual: p.equal, ua: await g.page.evaluate(() => navigator.userAgent) };
  await g.page.screenshot({ path: screenPath('C19-headed.png') });
  expect(m.headed.phase).toBe('ready');
  expect(p.equal).toBe(true);
});
