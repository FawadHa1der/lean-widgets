// C5 edit-break-fix, C6 refused header, C7 unknown module, C8 bad overlay, C9 unpaired fixture, C10 reload storm,
// C11 network cut (serve.mjs CHAOS knob, our own server on :5191), C12 offline warm reload.
import fs from 'node:fs';
import path from 'node:path';
import { test, expect } from '../lib/fixtures.mjs';
import { W, Gallery, Stock, BY_ID, EXAMPLES, SC, API, chromeRss, screenPath, serverBytes, startServer, stopServer, sleep, until, errorsWarnings, rssSampler, MEM_FAIL_BYTES } from '../lib/qed64.mjs';
import { goldenCursor } from '../lib/actions.mjs';

// v1 (lib/qed64.mjs API): the stock page's failed boot is read as api.status().boot {failed, message} (EMBEDDING.md §2.2, §4:
// a missing overlay index is a named failure "?snapshots=<dir>: …"); on a legacy page as the boot card's "failed" class and
// its label (Stock.pageInfo bootFailed is that same fact in either mode). C25 (v1 persistence through the `document` event
// and an adopted frame reload) is new; on a legacy pin it asserts the page's own qed64.buffer restore the gallery adopts.
const firstAt = (id) => ({ line: BY_ID[id].firstCursor.line, character: BY_ID[id].firstCursor.character });
const firstGolden = (id) => goldenCursor(id, firstAt(id).line, firstAt(id).character).panels[0];
const allConsole = (s) => s.watches.flatMap((w) => [...w.messages.map((m) => `${m.type} ${m.text}`), ...w.pageErrors.map((e) => `pageerror ${e.message}`)]);

test('C5 edit, break, fix: a typo gives an error and the panel degrades without a page error; the fix brings the same panel back', async ({ ux }) => {
  const m = ux.metrics; const id = 'hasse-view'; const ex = BY_ID[id]; const at = firstAt(id);
  const s = await ux.launch({ profile: 'warm' });
  const g = await Gallery.open(s, { hash: id });
  expect(g.boot.s.phase).toBe('ready');
  const p0 = await g.expectPanel(at, firstGolden(id));
  m.before = { equal: p0.equal };
  expect(p0.equal).toBe(true);
  const line = ex.text.split('\n')[at.line];               // #hasse (Finset (Fin 3))
  const col = line.indexOf('Fin 3') + 3;                     // after "Fin"
  const v0 = (await g.qstatus()).version;
  await g.setCursor(at.line, col);
  await g.focusEditor();
  await g.page.keyboard.type('x');                           // #hasse (Finset (Finx 3))  — real keystroke
  const broken = await g.waitReady({ minVersion: v0, timeoutMs: 120000 });
  const dB = await g.diagnosticsOf(broken.version);
  m.broken = { version: broken.version, text: (await g.currentText()).split('\n')[at.line], errors: errorsWarnings(dB).filter((d) => d.sev === 1).map((d) => ({ line: d.line, msg: d.msg.slice(0, 120) })) };
  await g.setCursor(at.line, at.character);
  await sleep(1500); await g.ivSettled();
  const pB = await g.signature(at, { panelTitle: null });
  m.broken.panelPresent = pB.ok; m.broken.reason = pB.reason || null;
  m.broken.iv = (await g.ivText()).slice(0, 400);
  m.broken.chip = await g.page.locator(`#card-${id} .chip`).textContent();
  await g.page.screenshot({ path: screenPath('C5-broken.png') });
  // fix: delete the typo with the real keyboard
  await g.setCursor(at.line, col + 1);
  await g.focusEditor();
  const v1 = (await g.qstatus()).version;
  await g.page.keyboard.press('Backspace');
  const fixed = await g.waitReady({ minVersion: v1, timeoutMs: 120000, text: ex.text });
  const dF = await g.diagnosticsOf(fixed.version);
  await g.setCursor(at.line, at.character);
  const p1 = await g.expectPanel(at, firstGolden(id), { timeoutMs: 60000 });
  m.fixed = { version: fixed.version, errorsWarnings: errorsWarnings(dF).length, panelEqual: p1.equal, diffs: p1.diffs.slice(0, 3), textIsExample: (await g.currentText()) === ex.text };
  await g.page.screenshot({ path: screenPath('C5-fixed.png') });
  console.log(`C5 ${JSON.stringify({ broken: { errors: m.broken.errors, panelPresent: m.broken.panelPresent }, fixed: m.fixed })}`);
  expect(m.broken.errors.some((d) => d.line === at.line), 'an error diagnostic on the broken line').toBe(true);
  expect(m.broken.panelPresent, 'the HassePanel is gone while the command does not elaborate').toBe(false);
  expect(m.broken.iv).not.toMatch(/Unrecognised error|abortSignal/);
  expect(m.fixed).toMatchObject({ errorsWarnings: 0, panelEqual: true, textIsExample: true });
});

test('C6 refused header (stock page): import HasseView without Mathlib is refused, missing [HasseView], no widening; the gallery never emits it', async ({ ux }) => {
  const m = ux.metrics;
  m.galleryHeaders = EXAMPLES.map((e) => e.header);
  expect(EXAMPLES.every((e) => e.header[0] === 'import Mathlib' && e.header.length === 2 && e.text.startsWith(`${e.header.join('\n')}\n`))).toBe(true);
  const s = await ux.launch({ profile: 'fresh' });
  const st = await Stock.open(s, { buffer: 'import HasseView\n\n#check (1 : Nat)\n' });
  const r = await st.settle({ timeoutMs: 180000 });
  await sleep(5000); // give the page's own widening handler (main.ts) time to act, if it would
  const q = await st.qstatus(); const info = await st.pageInfo();
  const d = await st.diagnosticsOf(q.version).catch(() => null);
  m.status = { phase: q.phase, header: q.header, snapshots: q.snapshots, userRestarts: q.stats.userRestarts, reboots: q.stats.reboots, pill: info.pill, diags: d };
  await st.page.screenshot({ path: screenPath('C6-refused.png') });
  console.log(`C6 ${JSON.stringify(m.status)}`);
  expect(r).toBeTruthy();
  expect(q.phase).toBe('headerRefused');
  expect(q.header).toMatchObject({ mode: 'refused', missing: ['HasseView'] });
  expect(q.snapshots, 'booted init only: no Mathlib in the header').toEqual(['init']);
  expect(q.stats.userRestarts, 'no widening restart').toBe(0);
});

test('C7 unknown module (stock page): import Mathlib.NotAModule is refused with the stock diagnostic', async ({ ux }) => {
  const m = ux.metrics;
  const s = await ux.launch({ profile: 'fresh' });
  const st = await Stock.open(s, { buffer: 'import Mathlib.NotAModule\n\n#check (1 : Nat)\n' });
  await st.settle({ timeoutMs: 240000 });
  await sleep(3000);
  const q = await st.qstatus(); const info = await st.pageInfo();
  const d = await st.diagnosticsOf(q.version);
  m.status = { phase: q.phase, header: q.header, snapshots: q.snapshots, userRestarts: q.stats.userRestarts, pill: info.pill, diags: d };
  await st.page.screenshot({ path: screenPath('C7-unknown-module.png') });
  console.log(`C7 ${JSON.stringify(m.status)}`);
  expect(q.phase).toBe('headerRefused');
  expect(q.header).toMatchObject({ mode: 'refused', missing: ['Mathlib.NotAModule'] });
  // the stock text (wasm64-lean-kernel src/Lean/Server/FileWorker.lean:451)
  expect(d.some((x) => x.sev === 1 && x.line === 0 && x.msg === 'modules #[Mathlib.NotAModule] are not loaded in this session — use "Load exact imports"')).toBe(true);
});

test('C8 bad overlay: the stock page shows its boot-failure card; the gallery refuses before navigation with a friendly card', async ({ ux }) => {
  const m = ux.metrics;
  ux.scenarios.push('crashBreakerTripped', 'bootFailure');
  const s = await ux.launch({ profile: 'fresh', label: 'stock' });
  const st = await Stock.open(s, { buffer: BY_ID['hasse-view'].text, query: '?snapshots=snapshots/nope' });
  const r = await st.settle({ timeoutMs: 180000 });
  const info = await st.pageInfo(); const q = await st.qstatus();
  m.stock = { phase: q && q.phase, bootcard: info.bootcard, bootlabel: info.bootlabel, boot: info.boot, bootFailed: info.bootFailed, pill: info.pill, lastDeath: q && q.lastDeath, stats: q && q.stats };
  await st.page.screenshot({ path: screenPath('C8-stock-bootcard.png') });
  await ux.close(s);
  expect(r).toBeTruthy();
  if (API) {
    // v1 (EMBEDDING.md §4): a missing overlay index is a boot failure that NAMES the parameter, with cause kind 'missing'
    expect(m.stock.boot, 'api.status().boot reports the failed boot').toMatchObject({ failed: true, done: false });
    expect(m.stock.boot.message, 'the failure names ?snapshots=snapshots/nope').toMatch(/\?snapshots=snapshots\/nope/);
    expect(m.stock.bootFailed).toBe(true);
    expect(m.stock.bootlabel, 'the page\'s own card shows the same message').toBe(m.stock.boot.message);
  } else {
    expect(m.stock.bootcard).toMatch(/failed/);
    expect(m.stock.bootlabel).toMatch(/snapshot 'init' failed to load/);
  }
  // the gallery: preflight refuses, nothing loads
  const s2 = await ux.launch({ profile: 'fresh', label: 'gallery' });
  const g = await Gallery.open(s2, { hash: 'hasse-view', query: '?overlay=nope' });
  const card = g.page.locator('#error-card:not([hidden])');
  m.gallery = { phase: g.boot.s.phase, error: g.boot.s.error, cardVisible: await card.isVisible(), title: await g.page.locator('#error-title').textContent(), checks: await g.page.locator('#error-checks li').evaluateAll((els) => els.map((e) => `${e.className} ${e.textContent.trim()}`)), frameSrc: await g.page.locator('#qed64-frame').getAttribute('src'), qed64Loads: s2.watches[0].loads.qed64, role: await card.getAttribute('role') };
  await g.page.screenshot({ path: screenPath('C8-gallery-card.png') });
  console.log(`C8 ${JSON.stringify(m)}`);
  expect(m.gallery).toMatchObject({ phase: 'error', cardVisible: true, qed64Loads: 0, role: 'alert' });
  expect(m.gallery.title).toMatch(/nope/);
  expect(m.gallery.checks.some((c) => /^bad/.test(c))).toBe(true);
});

test('C9 unpaired fixture (temp overlay with an altered runtime): the gallery refuses; the stock page fails its boot', async ({ ux }) => {
  const m = ux.metrics;
  ux.scenarios.push('crashBreakerTripped', 'bootFailure');
  const name = `ux-unpaired-${process.pid}`;
  const dir = path.join(SC, 'out/overlay/snapshots', name);
  const w8 = path.join(SC, 'out/overlay/snapshots/widgets8');
  fs.mkdirSync(dir, { recursive: true });
  try {
    const idx = JSON.parse(fs.readFileSync(path.join(w8, 'index.json'), 'utf8'));
    for (const e of idx.snapshots) { e.runtime = 'wasm64-0000000000000000'; const f = path.basename(e.url); if (!fs.existsSync(path.join(dir, f))) fs.symlinkSync(path.join('..', 'widgets8', f), path.join(dir, f)); }
    fs.writeFileSync(path.join(dir, 'index.json'), JSON.stringify(idx, null, 1));
    m.fixture = { dir: path.relative(SC, dir), runtime: 'wasm64-0000000000000000', files: fs.readdirSync(dir) };
    // gallery
    const s = await ux.launch({ profile: 'fresh', label: 'gallery' });
    const g = await Gallery.open(s, { hash: 'hasse-view', query: `?overlay=${name}` });
    m.gallery = { phase: g.boot.s.phase, title: await g.page.locator('#error-title').textContent(), detail: await g.page.locator('#error-detail').textContent(), checks: await g.page.locator('#error-checks li.bad').evaluateAll((els) => els.map((e) => e.textContent.trim())), qed64Loads: s.watches[0].loads.qed64, failed: g.boot.s.preflight && g.boot.s.preflight.attempts.flatMap((a) => a.failed) };
    await g.page.screenshot({ path: screenPath('C9-gallery-unpaired.png') });
    await ux.close(s);
    // stock
    const s2 = await ux.launch({ profile: 'fresh', label: 'stock' });
    const st = await Stock.open(s2, { buffer: BY_ID['hasse-view'].text, query: `?snapshots=snapshots/${name}` });
    await st.settle({ timeoutMs: 180000 });
    const info = await st.pageInfo(); const q = await st.qstatus();
    const all = allConsole(s2);
    m.stock = { phase: q && q.phase, bootcard: info.bootcard, bootlabel: info.bootlabel, boot: info.boot, bootFailed: info.bootFailed, lastDeath: q && q.lastDeath, unpairedInUi: /SNAPSHOT_UNPAIRED|baked for runtime/.test(`${info.bootlabel} ${info.pill} ${JSON.stringify(q && q.lastDeath)}`), unpairedInConsole: all.filter((x) => /SNAPSHOT_UNPAIRED|baked for runtime/.test(x)).slice(0, 3), snapzGets: serverBytes(st.tNav).snapz || null };
    await st.page.screenshot({ path: screenPath('C9-stock-unpaired.png') });
    console.log(`C9 ${JSON.stringify(m)}`);
    expect(m.gallery.phase).toBe('error');
    expect(m.gallery.qed64Loads).toBe(0);
    expect(m.gallery.failed.some((f) => /runtime/.test(f))).toBe(true);
    if (API) {
      // v1: the unpaired snapshot is a named boot failure (api.status().boot; the death's cause kind 'unpaired', EMBEDDING.md §7.2)
      expect(m.stock.boot, 'api.status().boot reports the failed boot').toMatchObject({ failed: true });
      expect(m.stock.bootFailed).toBe(true);
      // every bootFailed death carries its cause (§7.2); an unpaired snapshot is kind 'unpaired' (SNAPSHOT_UNPAIRED)
      expect(m.stock.lastDeath && m.stock.lastDeath.cause, 'a bootFailed death carries its cause (EMBEDDING.md §7.2)').toMatchObject({ kind: 'unpaired' });
      expect(m.stock.lastDeath.reason).toBe('bootFailed');
      expect(typeof m.stock.boot.message === 'string' && m.stock.boot.message.length > 0, `api.status().boot.message names the failure (${JSON.stringify(m.stock.boot.message)})`).toBe(true);
    } else expect(m.stock.bootcard).toMatch(/failed/);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
  m.fixtureRemoved = !fs.existsSync(dir);
});

test('C10 reload storm: 5 reloads in 15 s, then ready with the right panel; no crash; workers released on pagehide', async ({ ux }) => {
  const m = ux.metrics; const id = 'graph-scope';
  ux.scenarios.push('relayRestartOrReboot');
  const s = await ux.launch({ profile: 'warm' });
  const g = await Gallery.open(s, { hash: id });
  expect(g.boot.s.phase).toBe('ready');
  const rss = rssSampler(500);
  m.atFirstReady = { rss: chromeRss(), workers: g.page.workers().length };
  const t = Date.now();
  m.reloads = [];
  for (let i = 0; i < 5; i++) {
    if (i) await sleep(Math.max(0, i * 3000 - (Date.now() - t))); // reloads at 0, 3, 6, 9, 12 s
    const st = await g.status().catch(() => null);
    m.reloads.push({ at: Date.now() - t, phaseBefore: st && st.phase, qed64Before: st && st.qed64 && st.qed64.phase });
    await g.page.reload({ waitUntil: 'commit' });
  }
  m.stormMs = Date.now() - t;
  const b = await g.waitGallery({ timeoutMs: 300000 });
  const p = await g.expectPanel(firstAt(id), firstGolden(id), { timeoutMs: 120000 });
  await sleep(3000);
  rss.stop();
  const w = s.watches[0];
  m.after = { phase: b.s.phase, ms: Date.now() - t, panelEqual: p.equal, crashed: w.crashed, rss: chromeRss(), peak: rss.peak, workersAlive: g.page.workers().length, workersCreated: w.workers.length, workersClosed: w.workers.filter((x) => x.closed !== null).length, loads: w.loads, bridgeLate: b.s.bridge.late, api: b.s.api, bridge: b.s.bridge };
  // the renderer RSS timeline (0.5 s) and the transient peak against the plan's fail line, in bytes (UX audit minor 1).
  // The transient overlap of a dying page and the next boot is QED64's (L8 in docs/UX-RESULTS.md): recorded and
  // reported, with the fail line asserted on the settled state; a crash fails the test.
  m.failLineBytes = MEM_FAIL_BYTES;
  m.samples = rss.samples.map((x) => ({ t: x.t, GB: x.rendererGB, renderers: x.renderers }));
  m.transient = { peakGB: rss.peak.rendererGB, peakGiB: rss.peak.rendererGiB, peakAtMs: rss.peak.t, overFailLine: rss.peak.rendererBytes >= MEM_FAIL_BYTES, msOverFailLine: rss.samples.filter((x) => x.rendererBytes >= MEM_FAIL_BYTES).length * 500 };
  await g.page.screenshot({ path: screenPath('C10-after-storm.png') });
  console.log(`C10 ${JSON.stringify({ ...m, samples: undefined })}`);
  console.log(`C10 renderer: first ready ${m.atFirstReady.rss.rendererGB} GB, transient peak ${m.transient.peakGB} GB at ${m.transient.peakAtMs} ms (${m.transient.msOverFailLine} ms over ${MEM_FAIL_BYTES / 1e9} GB), settled ${m.after.rss.rendererGB} GB`);
  expect(m.reloads[4].at, '5 reloads within 15 s').toBeLessThanOrEqual(15000);
  expect(m.after).toMatchObject({ phase: 'ready', panelEqual: true, crashed: false, bridgeLate: 0 });
  // v1: bridge.late is always 0 (no bridge is ever installed late on a stood-down page), so the storm's v1 outcome is asserted
  // on the api itself: the last gallery holds the frame's api in embed mode, the bridge stood down and is not installed, and
  // nothing was adopted (every reload is a fresh gallery that navigated its own frame)
  if (API) expect({ present: m.after.api.present, embed: m.after.api.embed, stoodDown: m.after.bridge.stoodDown, installed: m.after.bridge.installed, adopted: m.after.api.adopted }, 'v1: the gallery after the storm holds the api, bridge stood down').toEqual({ present: true, embed: true, stoodDown: true, installed: false, adopted: 0 });
  expect(m.after.workersAlive, 'no worker accumulation across the reloads').toBeLessThanOrEqual(m.atFirstReady.workers + 2);
  expect(m.after.rss.rendererBytes, `settled renderer RSS < ${MEM_FAIL_BYTES / 1e9} GB`).toBeLessThan(MEM_FAIL_BYTES);
});

test('C11 network cut mid-.snapz (serve.mjs CHAOS on our own :5191 server): a single cut is absorbed; a lasting cut is surfaced and a reload recovers', async ({ ux }) => {
  test.setTimeout(20 * 60 * 1000);
  const m = ux.metrics; const port = 5191; const origin = `http://localhost:${port}`;
  ux.scenarios.push('crashBreakerTripped', 'bootFailure', 'networkCut', 'relayRestartOrReboot');
  const LOG = path.join(W, 'logs', `serve-${port}.log`);
  const cutsSince = (t) => (fs.existsSync(LOG) ? fs.readFileSync(LOG, 'utf8').split('\n').filter((l) => /CHAOS-CUT/.test(l) && Date.parse(l.split(' ')[0]) >= t) : []);
  /** Boot the gallery at :5191 on a fresh profile and watch what the user is shown until it settles. */
  async function bootWatched(label) {
    const s = await ux.launch({ profile: 'fresh', label });
    const page = s.page() || await s.newPage();
    const g = new Gallery(s, page); g.tNav = Date.now();
    const seen = { maxDeaths: 0, lastDeath: null, cards: [], phases: [] };
    let stop = false;
    const poll = (async () => { while (!stop) { const st = await g.status().catch(() => null); if (st) { const k = `${st.phase}/${st.qed64 ? st.qed64.phase : '-'}`; if (seen.phases[seen.phases.length - 1] !== k) seen.phases.push(k); if (st.qed64 && st.qed64.lastDeath) seen.lastDeath = st.qed64.lastDeath; if (st.error && !seen.cards.some((c) => c.title === st.error.title)) seen.cards.push({ kind: st.error.kind, title: st.error.title, soft: st.error.soft }); } const q = await g.qstatus(); if (q) seen.maxDeaths = Math.max(seen.maxDeaths, q.stats.workerDeaths); await sleep(150); } })();
    await page.goto(`${origin}/showcase/#chart-kit`, { waitUntil: 'domcontentloaded' });
    const b = await g.waitGallery({ timeoutMs: 300000 });
    await sleep(2500);
    stop = true; await poll;
    return { s, g, page, b, seen };
  }
  try {
    // (a) one cut: the first .snapz GET dies after 20 MB
    m.serverA = startServer(port, { CHAOS: '\\.snapz$:20000000:1' });
    const A = await bootWatched('cut-once');
    m.once = { phase: A.b.s.phase, ms: A.b.ms, deaths: A.seen.maxDeaths, lastDeath: A.seen.lastDeath, cards: A.seen.cards, phases: A.seen.phases, cuts: cutsSince(A.g.tNav), prefetchWarning: A.s.watches[0].messages.some((x) => /raw prefetch error/.test(x.text)) };
    const pA = await A.g.expectPanel(firstAt('chart-kit'), firstGolden('chart-kit'), { timeoutMs: 60000 });
    m.once.panelEqual = pA.equal;
    await A.page.screenshot({ path: screenPath('C11-cut-once.png') });
    await ux.close(A.s);
    stopServer(port);
    // (b) a lasting cut: every .snapz GET dies after 1 MB (the network is gone for the snapshots)
    m.serverB = startServer(port, { CHAOS: '\\.snapz$:1000000:100000' });
    const B = await bootWatched('cut-lasting');
    m.lasting = { phase: B.b.s.phase, ms: B.b.ms, deaths: B.seen.maxDeaths, lastDeath: B.seen.lastDeath, cards: B.seen.cards, phases: B.seen.phases, cuts: cutsSince(B.g.tNav).length, errorTitle: await B.page.locator('#error-title').textContent().catch(() => null), cardVisible: await B.page.locator('#error-card:not([hidden])').isVisible() };
    await B.page.screenshot({ path: screenPath('C11-cut-lasting.png') });
    // UX audit minor 3d: the gallery's card must not cover QED64's own failed boot card (compact mode while it shows)
    const cardBox = await B.page.locator('#error-card').boundingBox().catch(() => null);
    const frameBox = await B.page.locator('#qed64-frame').boundingBox().catch(() => null);
    const bootBox = await B.page.frameLocator('#qed64-frame').locator('#bootcard').boundingBox().catch(() => null);
    const pageCard = bootBox && frameBox ? { x: bootBox.x, y: bootBox.y, width: bootBox.width, height: bootBox.height } : null;
    const overlap = (a, b) => !!(a && b) && a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
    m.lasting.layout = { compact: await B.page.locator('#error-card.is-compact').count(), card: cardBox, pageBootCard: pageCard, pageBootCardFailed: /failed/.test(await B.page.frameLocator('#qed64-frame').locator('#bootcard').getAttribute('class').catch(() => '') || ''), overlap: overlap(cardBox, pageCard) };
    // the network comes back: same port, no CHAOS; reload the same tab
    stopServer(port);
    m.serverC = startServer(port, {});
    const tR = Date.now();
    await B.page.reload({ waitUntil: 'domcontentloaded' });
    const b2 = await B.g.waitGallery({ timeoutMs: 300000 });
    const p = await B.g.expectPanel(firstAt('chart-kit'), firstGolden('chart-kit'), { timeoutMs: 60000 });
    m.recovered = { phase: b2.s.phase, ms: Date.now() - tR, panelEqual: p.equal, errorCard: b2.s.error };
    await B.page.screenshot({ path: screenPath('C11-recovered.png') });
    console.log(`C11 ${JSON.stringify(m)}`);
    expect(m.once.cuts.length, 'the server cut one .snapz response mid-stream').toBe(1);
    expect(m.once, 'a single cut is absorbed: QED64 streams the snapshot again, no death').toMatchObject({ phase: 'ready', deaths: 0, panelEqual: true, prefetchWarning: true });
    expect(m.lasting.cuts).toBeGreaterThan(1);
    expect(m.lasting.deaths > 0 || !!m.lasting.lastDeath, 'the lasting cut is a counted boot death').toBe(true);
    expect(m.lasting.cards.length > 0 || m.lasting.cardVisible, 'and the gallery shows it on a card').toBe(true);
    if (m.lasting.cardVisible && m.lasting.layout.pageBootCardFailed) expect(m.lasting.layout, 'the gallery card is compact and does not cover QED64\'s own boot card').toMatchObject({ compact: 1, overlap: false });
    expect(m.recovered).toMatchObject({ phase: 'ready', panelEqual: true, errorCard: null });
  } finally { m.serverStop = stopServer(port); }
});

test('C12 offline warm reload: snapshots come from the warm profile (no .snapz download); a cut-off overlay index is a QED64 limitation the gallery reports', async ({ ux }) => {
  const m = ux.metrics; const id = 'hasse-view';
  // (a) every GET of a .snapz is aborted (HEAD still answered: the gallery's preflight checks metadata only)
  const s = await ux.launch({ profile: 'warm', label: 'snapz-offline' });
  const aborted = []; const t0 = Date.now();
  await s.context.route('**/*.snapz', (r) => { if (r.request().method() === 'HEAD') return r.continue(); aborted.push(r.request().url()); return r.abort('internetdisconnected'); });
  const st = await Stock.open(s, { buffer: BY_ID[id].text });
  const r = await st.settle({ timeoutMs: 180000 });
  m.stock = { phase: r && r.s.phase, ms: Date.now() - t0, aborted: aborted.length, server: serverBytes(t0) };
  const g = await Gallery.open(s, { hash: id, page: await s.newPage() });
  const p = await g.expectPanel(firstAt(id), firstGolden(id), { timeoutMs: 60000 });
  m.gallery = { phase: g.boot.s.phase, ms: g.boot.ms, panelEqual: p.equal, aborted: aborted.length, server: serverBytes(t0) };
  await g.page.screenshot({ path: screenPath('C12-offline-snapz-gallery.png') });
  await ux.close(s);
  // (b) the whole overlay unreachable (index.json included)
  const s2 = await ux.launch({ profile: 'warm', label: 'overlay-offline' });
  await s2.context.route('**/snapshots/**', (rt) => rt.abort('internetdisconnected'));
  const g2 = await Gallery.open(s2, { hash: id });
  m.galleryOverlayOffline = { phase: g2.boot.s.phase, title: await g2.page.locator('#error-title').textContent().catch(() => null), cardVisible: await g2.page.locator('#error-card:not([hidden])').isVisible(), qed64Loads: s2.watches[0].loads.qed64, attempts: g2.boot.s.preflight && g2.boot.s.preflight.attempts };
  await g2.page.screenshot({ path: screenPath('C12-overlay-offline-gallery.png') });
  await ux.close(s2, { scenarios: ['networkCut'] });
  ux.scenarios.push('crashBreakerTripped', 'bootFailure', 'networkCut');
  const s3 = await ux.launch({ profile: 'warm', label: 'overlay-offline-stock' });
  await s3.context.route('**/snapshots/widgets8/**', (rt) => rt.abort('internetdisconnected'));
  const st3 = await Stock.open(s3, { buffer: BY_ID[id].text });
  await st3.settle({ timeoutMs: 180000 });
  const i3 = await st3.pageInfo(); const q3 = await st3.qstatus();
  m.stockOverlayOffline = { phase: q3 && q3.phase, bootcard: i3.bootcard, bootlabel: i3.bootlabel, boot: i3.boot, bootFailed: i3.bootFailed, lastDeath: q3 && q3.lastDeath };
  await st3.page.screenshot({ path: screenPath('C12-overlay-offline-stock.png') });
  console.log(`C12 ${JSON.stringify(m)}`);
  expect(m.stock).toMatchObject({ phase: 'ready', aborted: 0 });
  expect(m.gallery).toMatchObject({ phase: 'ready', panelEqual: true, aborted: 0 });
  expect((m.gallery.server.snapz || { n: 0 }).n, 'no .snapz GET reached the server').toBe(0);
  expect(m.galleryOverlayOffline).toMatchObject({ phase: 'error', cardVisible: true, qed64Loads: 0 });
  // documented QED64 limitation (UX-RESULTS L3): the page fetches the override index.json on every boot
  if (API) {
    // v1 (EMBEDDING.md §4): an unreachable overlay index is a NAMED boot failure (api.status().boot.failed, the message names ?snapshots=)
    expect(m.stockOverlayOffline.boot, 'api.status().boot reports the failed boot').toMatchObject({ failed: true });
    expect(m.stockOverlayOffline.boot.message).toMatch(/\?snapshots=snapshots\/widgets8/);
    expect(m.stockOverlayOffline.bootFailed).toBe(true);
  } else expect(m.stockOverlayOffline.bootcard).toMatch(/failed/);
});

// C25 (QED64 embedding contract v1 adoption): edits survive a reload of the FRAME that the gallery did not start (QED64's own
// Reload button, a user reload of the frame). In v1 embed mode (EMBEDDING.md §3) the page neither reads nor writes
// qed64.buffer, so the gallery owns persistence: every `document` event is written to localStorage['qed64-showcase:document']
// (at most once per second; status().document.persisted), and on the reloaded frame's qed64:frame-api the gallery calls
// api.setDocument(saved) synchronously (inside the page's 5 s boot-document window) and adopts the reload (adoptReload).
// On a legacy pin the page itself restores its qed64.buffer (saved 400 ms after every edit) and the gallery adopts what it
// shows: the same outcome (the edited text is back on a new session), asserted through the legacy facts.
test('C25 persistence across a frame reload: an in-page edit comes back on the reloaded frame the gallery adopts', async ({ ux }) => {
  test.setTimeout(10 * 60 * 1000);
  const m = ux.metrics; const id = 'hasse-view'; const ex = BY_ID[id]; const at = firstAt(id);
  ux.scenarios.push('relayRestartOrReboot'); // the reload disposes the running session mid-flight (QED64 N2 'Session disposed.')
  const s = await ux.launch({ profile: 'warm' });
  const g = await Gallery.open(s, { hash: id });
  expect(g.boot.s.phase).toBe('ready');
  const q0 = await g.qstatus(); const w = s.watches[0];
  m.mode = API ? 'v1' : 'legacy';
  // the edit: a comment appended with the real keyboard (one input, re-checks clean)
  const EDIT = '-- C25: an edit that must survive a frame reload';
  const last = ex.text.split('\n').length - 1;
  await g.setCursor(last, 0);
  await g.focusEditor();
  await g.page.keyboard.type(EDIT);
  const edited = `${ex.text}${EDIT}`;
  const st1 = await g.waitReady({ minVersion: q0.version, timeoutMs: 120000, text: edited });
  expect(st1, 'the edited text re-checked').not.toBeNull();
  m.edited = { version: st1.version, textOk: (await g.currentText()) === edited, errorsWarnings: errorsWarnings(await g.diagnosticsOf(st1.version)).length, chipEdited: (await g.status()).edited };
  expect(m.edited).toMatchObject({ textOk: true, errorsWarnings: 0, chipEdited: true });
  // persisted: v1 by the gallery from the `document` event (<= 1 s); legacy by the page's own 400 ms buffer save
  const persisted = await until(async () => {
    if (API) { const st = await g.status(); const stored = await g.page.evaluate(() => { try { return localStorage.getItem('qed64-showcase:document'); } catch { return null; } }); return st.document && st.document.persisted && stored === edited ? { document: st.document } : null; }
    const buf = await g.q(() => { try { return localStorage.getItem('qed64.buffer'); } catch (e) { return null; } }); return buf === edited ? { buffer: true } : null;
  }, { timeoutMs: 10000, intervalMs: 200 });
  m.persisted = persisted;
  expect(persisted, API ? 'status().document.persisted and qed64-showcase:document hold the edit' : 'the page saved its qed64.buffer').not.toBeNull();
  if (API) expect(persisted.document).toMatchObject({ persisted: true, version: expect.any(Number), length: edited.length });
  // reload the FRAME (not the gallery): what QED64's own Reload button or a user reload of the frame does
  const loads0 = w.loads.qed64; const sessionBefore = q0.session;
  const apiBefore = API ? (await g.status()).api : null;
  const frame = g.page.frames().find((f) => f.parentFrame() === g.page.mainFrame() && (() => { try { return new URL(f.url()).pathname === '/'; } catch { return false; } })());
  expect(frame, 'the QED64 frame').toBeTruthy();
  // a per-DOCUMENT marker: session ids restart at 's1' in every page document (src/runtime/client.ts sessionSeq is module
  // state), so the reloaded page's session id equals the old one; the marker is gone only in a NEW document
  await frame.evaluate(() => { window.__uxC25Old = true; });
  const newDocument = async () => (await g.q(() => !window.__uxC25Old).catch(() => false)) === true;
  const tR = Date.now();
  await frame.evaluate(() => { setTimeout(() => location.reload(), 0); return true; }).catch(() => {});
  const adopted = await until(async () => {
    if (!(w.loads.qed64 > loads0)) return null;
    const st = await g.status(); const q = await g.qstatus(); const tx = await g.currentText();
    return st && st.phase === 'ready' && st.booted && q && q.phase === 'ready' && q.session && tx === edited && (await newDocument()) ? { st, q } : null;
  }, { timeoutMs: 300000, intervalMs: 200 });
  m.adopted = { ok: !!adopted, ms: Date.now() - tR, loadsBefore: loads0, loadsAfter: w.loads.qed64, phase: adopted && adopted.st.phase, op: adopted && adopted.st.op && adopted.st.op.label, session: adopted && adopted.q.session, sessionBefore, newDocument: await newDocument(), version: adopted && adopted.q.version, textOk: adopted ? (await g.currentText()) === edited : null, crashed: w.crashed, error: adopted && adopted.st.error };
  if (API && adopted) m.adopted.v1 = { document: adopted.st.document, api: adopted.st.api, seed: adopted.st.seed, apiText: await g.q(() => window.qed64.api.getDocument().text) === edited, frame: await g.frameFacts() };
  await g.page.screenshot({ path: screenPath('C25-after-frame-reload.png') });
  console.log(`C25 ${JSON.stringify(m)}`);
  expect(m.adopted, 'the gallery adopted the reloaded frame with the edited text on a new session').toMatchObject({ ok: true, phase: 'ready', textOk: true, crashed: false, error: null });
  expect(m.adopted.loadsAfter, 'exactly one more QED64 page load').toBe(loads0 + 1);
  expect(m.adopted.newDocument, 'a new QED64 page document (the per-document marker is gone)').toBe(true);
  if (API) {
    expect(m.adopted.v1.document, 'the adopted document is the persisted one').toMatchObject({ persisted: true, length: edited.length });
    // the adoption path itself: on the reloaded frame's qed64:frame-api the gallery called api.setDocument(saved) synchronously
    // (api.adopted, adoptSet from 'saved' with the edit's length, one more api document), and the new session delivered its
    // own `document` event (lastEventAgoMs younger than the reload), so persisted/length are not inherited from before it
    expect(m.adopted.v1.api, 'adopted through api.setDocument(saved) in the frame-api handler').toMatchObject({ adopted: 1, docs: apiBefore.docs + 1, adoptSet: { from: 'saved', length: edited.length } });
    expect(typeof m.adopted.v1.document.lastEventAgoMs === 'number' && m.adopted.v1.document.lastEventAgoMs < m.adopted.ms, `a fresh document event on the new session (lastEventAgoMs ${m.adopted.v1.document.lastEventAgoMs} < ${m.adopted.ms} ms since the reload)`).toBe(true);
    expect(m.adopted.v1.apiText, 'api.getDocument() shows the edit').toBe(true);
    expect(m.adopted.v1.api).toMatchObject({ present: true, embed: true });
    expect(m.adopted.v1.seed).toMatchObject({ action: 'embed' });
    expect(m.adopted.v1.frame.hash, 'no #code= resurrected on the reload').not.toMatch(/code=/);
  }
  // the re-checked edit still elaborates clean and the panel is back at the first cursor
  const d = await g.diagnosticsOf(adopted.q.version);
  const p = await g.expectPanel(at, firstGolden(id), { timeoutMs: 60000 });
  m.after = { errorsWarnings: errorsWarnings(d).length, panelEqual: p.equal };
  expect(m.after).toEqual({ errorsWarnings: 0, panelEqual: true });
  const rs = await g.resetUI(ex);
  expect(rs.ok, 'Reset restores the example').toBe(true);
});
