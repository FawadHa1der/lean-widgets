// C1 cold boot, C2 warm boot, C3 memory (+ the L-switch lane: all 8 widgets in one boot via the gallery's setValue,
// each first-cursor panel equal to its golden; C16 no collision offer for any gallery example), C4 switching.
import fs from 'node:fs';
import path from 'node:path';
import { test, expect } from '../lib/fixtures.mjs';
import { Gallery, EXAMPLES, IDS, GOLDENS, PROFILES, WARM_PROFILE, SC, ORIGIN, API, API_REVISION, GALLERY_PIN, chromeRss, rssSampler, screenPath, rel, sleep, until, serverBytes, MEM_FAIL_BYTES } from '../lib/qed64.mjs';
import { goldenCursor } from '../lib/actions.mjs';

const GiB = 1073741824;
// v1 embed mode (EMBEDDING.md §3): the page neither reads nor writes localStorage['qed64.buffer']; C1 seeds this sentinel on
// the origin before the gallery navigates and requires it untouched once ready (the gallery no longer seeds the buffer either)
const BUFFER_SENTINEL = '-- UX C1 sentinel: embed mode must neither read nor write qed64.buffer\n';
// The overlay the gallery boots by default (widgets8): its two snapshots, from the served index (the transfer sizes and
// digests change with every rebake; they were constants until the 2026-10-01 re-pin, docs/REPIN-LOG.md)
const W8 = JSON.parse(fs.readFileSync(path.join(SC, 'out/overlay/snapshots/widgets8/index.json'), 'utf8')).snapshots;
const W8_TRANSFER = W8.reduce((a, x) => a + x.transfer, 0);
const W8_KEY = W8.map((x) => x.digest).join(' ');
/** Phase timeline: poll the gallery + QED64 status every 100 ms and record each transition. */
function timeline(g) {
  const tl = []; let last = ''; let stop = false;
  const t0 = g.tNav || Date.now();
  (async () => {
    while (!stop) {
      const s = await g.status().catch(() => null);
      const key = s ? `${s.phase}|${s.qed64 ? s.qed64.phase : '-'}|${s.qed64 && s.qed64.relay ? s.qed64.relay : '-'}` : 'no-gallery';
      if (key !== last) { tl.push({ t: Date.now() - t0, gallery: s && s.phase, qed64: s && s.qed64 ? s.qed64.phase : null, relay: s && s.qed64 ? s.qed64.relay : null }); last = key; }
      await sleep(100);
    }
  })();
  return { tl, stop: () => { stop = true; } };
}
async function firstPanel(g, id, timeoutMs = 60000) {
  const ex = EXAMPLES.find((e) => e.id === id);
  const c = { line: ex.firstCursor.line, character: ex.firstCursor.character };
  await g.ivSettled({ timeoutMs });
  return g.expectPanel(c, goldenCursor(id, c.line, c.character).panels[0], { timeoutMs });
}

test('C1 cold boot: fresh profile (empty OPFS and HTTP cache) to ready, phase timeline, bytes per prefix', async ({ ux }) => {
  const m = ux.metrics;
  const s = await ux.launch({ profile: 'fresh', label: 'cold' });
  const page = s.page() || await s.newPage();
  const g = new Gallery(s, page);
  if (API) {
    // the sentinel goes into the origin's storage before the gallery is opened (a document of the origin is needed to reach it)
    await page.goto(`${ORIGIN}/showcase/pin.json`);
    await page.evaluate((t) => localStorage.setItem('qed64.buffer', t), BUFFER_SENTINEL);
  }
  g.tNav = Date.now();
  const tl = timeline(g);
  await page.goto(`${ORIGIN}/showcase/#chart-kit`, { waitUntil: 'domcontentloaded' });
  const b = await g.waitGallery();
  tl.stop();
  m.readyMs = b.ms; m.timeline = tl.tl; m.bytes = s.bytes; m.server = serverBytes(g.tNav);
  m.panel = await firstPanel(g, 'chart-kit').then((r) => ({ equal: r.equal, ms: r.ms, diffs: r.diffs.slice(0, 3) }));
  m.status = { phase: b.s.phase, bootMs: b.s.bootMs, overlay: b.s.overlay, preflightOk: b.s.preflight && b.s.preflight.ok };
  m.rssAtReady = chromeRss();
  await page.screenshot({ path: screenPath('C1-cold-ready.png') });
  console.log(`C1 cold boot ${b.ms} ms (gallery bootMs ${b.s.bootMs}); server ${JSON.stringify(m.server)}; timeline ${JSON.stringify(tl.tl)}`);
  expect(b.s.phase).toBe('ready');
  expect(b.ms, 'budget <= 180 s locally').toBeLessThanOrEqual(180000);
  expect(m.server.snapz && m.server.snapz.bytes, 'a cold boot downloads both overlay snapshots (init + widgets region)').toBe(W8_TRANSFER);
  expect(m.panel.equal, `first panel: ${m.panel.diffs}`).toBe(true);
  // the gallery's mode: pin.json's apiRevision, or the served release's /qed64-build.json when the server serves another pin
  // than pin.json describes (UX_PIN with the active pin's gallery) — the same rule the suite's API comes from (lib/qed64.mjs)
  expect({ mode: b.s.mode, modeSource: b.s.modeSource }, 'the gallery runs the mode the suite branches on').toEqual({ mode: API ? 'v1' : 'legacy', modeSource: GALLERY_PIN.modeSource || 'pin.json' });
  expect(b.s.api.missing, 'no capability the gallery needs is missing').toEqual([]);
  if (API) {
    // v1 (EMBEDDING.md §2.1, §3): the gallery runs the page in embed mode through the API it got from qed64:frame-api (or the
    // frozen api by polling), seeds nothing (seed.action 'embed'), and the page honoured #code= once and dropped it
    const frame = await g.frameFacts(); const a = await g.apiStatus();
    m.v1 = { api: b.s.api, seed: b.s.seed, frame: { search: frame.search, hash: frame.hash, bufferUntouched: frame.buffer === BUFFER_SENTINEL, examplesHidden: frame.embedExamplesHidden }, revision: a && a.revision, frozen: a && a.frozen, build: a && a.build, document: b.s.document };
    console.log(`C1 v1 ${JSON.stringify(m.v1)}`);
    expect(b.s.api, 'the gallery holds the v1 API of the framed page').toMatchObject({ present: true, revision: API_REVISION, embed: true });
    expect(['frame-api', 'poll'], 'obtained from the qed64:frame-api event, or the frozen api by polling').toContain(b.s.api.via);
    expect(b.s.api.capabilities).toMatchObject({ editorRpc: true, widgetSourceCache: true, documents: true, events: true, restart: true, embedMode: true, liveness: true, memory: true, offers: true });
    expect(a && a.revision, 'pin.json apiRevision is the page\'s api.revision').toBe(API_REVISION);
    expect(a && a.frozen, 'api and api.capabilities are frozen').toBe(true);
    expect(b.s.seed, 'embed mode: the gallery seeds no buffer').toEqual({ saved: false, action: 'embed', error: null });
    expect(frame.search, 'the frame runs in embed mode on the widgets8 overlay').toMatch(/(^\?|&)embed=1(&|$)/);
    expect(frame.search).toMatch(/(^\?|&)snapshots=snapshots\/widgets8(&|$)/);
    expect(frame.hash, '#code= was read once and dropped (§3.1)').not.toMatch(/code=/);
    expect(frame.buffer, 'localStorage qed64.buffer neither read nor written by the embedded page or the gallery').toBe(BUFFER_SENTINEL);
    expect(frame.embedExamplesHidden, 'embed mode hides the examples menu').toBe(true);
    expect(b.s.document, 'status().document reports the forwarded version and the persisted text').toMatchObject({ version: expect.any(Number), length: EXAMPLES.find((e) => e.id === 'chart-kit').text.length });
  }
  // every card's thumbnail is wired and loads from the server on a cold profile (bring-up audit r2 minor)
  m.thumbs = await g.thumbs();
  console.log(`C1 thumbnails ${JSON.stringify(m.thumbs.map((t) => `${t.id} ${t.naturalWidth}x${t.naturalHeight} ${t.w}x${t.h} ${t.ok ? 'ok' : 'BAD'}`))}`);
  expect(m.thumbs.filter((t) => !t.ok), 'card thumbnails that are not visible with naturalWidth 480').toEqual([]);
  expect(m.thumbs.length).toBe(8);
});

test('C2 warm boot: persistent profile, 0 .snapz bytes, only revalidations', async ({ ux }) => {
  const m = ux.metrics;
  // prime the persistent profile once per set of snapshots (not measured): a warm boot needs THESE snapshots in OPFS.
  // The mark records the overlay's digests; a rebake (re-pin) changes them, and the profile is primed again.
  const primeMark = path.join(WARM_PROFILE, '.ux-primed');
  const primedFor = fs.existsSync(primeMark) ? (fs.readFileSync(primeMark, 'utf8').split('\n')[1] || '') : '';
  if (primedFor !== W8_KEY) {
    const p = await ux.launch({ profile: 'warm', label: 'prime' });
    const gp = await Gallery.open(p, { hash: 'chart-kit' });
    m.prime = { ms: gp.boot.ms, phase: gp.boot.s.phase, snapz: p.bytes.snapz || null };
    await ux.close(p);
    if (gp.boot.s.phase === 'ready') fs.writeFileSync(primeMark, `${new Date().toISOString()}\n${W8_KEY}\n`);
  }
  const s = await ux.launch({ profile: 'warm', label: 'warm' });
  const page = s.page() || await s.newPage();
  const g = new Gallery(s, page); g.tNav = Date.now();
  const tl = timeline(g);
  const snapzReq = [];
  page.on('request', (r) => { if (/\.snapz/.test(r.url()) && r.method() === 'GET') snapzReq.push(r.url().replace(/^http:\/\/localhost:\d+/, '')); });
  await page.goto(`http://localhost:5190/showcase/#chart-kit`, { waitUntil: 'domcontentloaded' });
  const b = await g.waitGallery();
  tl.stop();
  m.readyMs = b.ms; m.timeline = tl.tl; m.bytes = s.bytes; m.snapzGetRequests = snapzReq;
  m.server = serverBytes(g.tNav); // network truth: what serve.mjs actually sent during this boot
  m.panel = await firstPanel(g, 'chart-kit').then((r) => ({ equal: r.equal, ms: r.ms }));
  console.log(`C2 warm boot ${b.ms} ms; snapz GET requests ${snapzReq.length}; server ${JSON.stringify(m.server)}`);
  expect(b.s.phase).toBe('ready');
  expect(b.ms, 'budget <= 20 s').toBeLessThanOrEqual(20000);
  expect((m.server.snapz || { bytes: 0 }).bytes, '0 .snapz bytes from the server (only the preflight HEADs, no body)').toBe(0);
  expect(snapzReq.length, 'the page does not even request a .snapz (the snapshots come from the profile)').toBe(0);
  expect(m.panel.equal).toBe(true);
});

test('C3 memory + L-switch lane + C16: one boot, all 8 widgets by card clicks, RSS and wasm heap, no collision offer', async ({ ux }) => {
  const m = ux.metrics;
  const s = await ux.launch({ profile: 'warm', label: 'mem' });
  const rss = rssSampler(1000);
  const g = await Gallery.open(s, { hash: IDS[0] });
  expect(g.boot.s.phase).toBe('ready');
  await sleep(1000);
  m.atReady = { rss: chromeRss(), heap: await g.telemetry() };
  m.widgets = {};
  const fail = [];
  for (const id of IDS) {
    const t = Date.now();
    const sel = (await g.status()).shown === id ? { ok: true } : await g.selectUI(id); // a real click on the card
    const p = await firstPanel(g, id);
    const st = await g.status(); const q = await g.qstatus();
    const action = await g.qframe.locator('button, a').filter({ hasText: 'Load exact imports' }).count();
    // v1: the offer is a structured fact (api.status().offer, EMBEDDING.md §2.2) that the gallery mirrors in status().qed64.offer
    const apiOffer = API ? (st.qed64 ? st.qed64.offer : undefined) : null;
    const w = { selectOk: sel.ok, ms: Date.now() - t, panelEqual: p.equal, diffs: p.diffs.slice(0, 3), header: q.header && q.header.mode, collision: q.collision, galleryCollision: st.qed64 && st.qed64.collision, exactImportsOffer: action, apiOffer, rss: chromeRss(), heap: await g.telemetry(), pool: q.pool };
    m.widgets[id] = w;
    if (!sel.ok || !p.equal) fail.push(`${id}: select ${sel.ok} panel ${p.equal} ${w.diffs}`);
    if (w.collision !== null || w.galleryCollision !== null || action) fail.push(`${id}: collision offer (C16) ${JSON.stringify(w.collision)} action ${action}`);
    if (API && apiOffer !== null) fail.push(`${id}: v1 status().qed64.offer is ${JSON.stringify(apiOffer)}, not null (no exact-imports offer for a gallery example)`);
    console.log(`C3 ${id} panel ${p.equal} ${w.ms} ms header ${w.header} collision ${JSON.stringify(w.collision)} rss renderer ${w.rss.rendererGiB} GiB (${w.rss.rendererGB} GB) heap ${w.heap && w.heap.currentBytes}`);
  }
  await sleep(1500);
  m.afterAll = { rss: chromeRss(), heap: await g.telemetry() };
  rss.stop();
  m.peak = rss.peak; m.samples = rss.samples.length;
  m.heapGrewAfterRegion = m.afterAll.heap && m.atReady.heap ? m.afterAll.heap.currentBytes > m.atReady.heap.currentBytes : null;
  const q = await g.qstatus();
  m.relay = q.stats;
  m.failLineBytes = MEM_FAIL_BYTES;
  if (API) {
    // v1: the wasm heap the API projects (status().memory, EMBEDDING.md §2.2) beside the worker's telemetry; and the ?mem knob,
    // when a run passes it (?mem=<GiB> -> &memory=<GiB>, no light first session), must have been applied by the page:
    // status().mem.applied = (api.status().memory.initialBytes === the requested bytes)
    const st = await g.status();
    m.v1 = { memory: q.memory, mem: st.mem, offer: q.offer };
    console.log(`C3 v1 ${JSON.stringify(m.v1)}`);
    expect(q.memory, 'api.status().memory carries the commit and the meter readings').toMatchObject({ initialBytes: expect.any(Number), currentBytes: expect.any(Number) });
    expect(st.mem, 'no ?mem session wrap in v1').toMatchObject({ wrapped: false, light: null, sessions: [] });
    if (st.mem.requestedGiB != null) expect(st.mem, '?mem was applied through &memory= (api.status().memory.initialBytes === the requested bytes)').toMatchObject({ ok: true, applied: true, memory: { initialBytes: st.mem.bytes } });
    expect(q.offer, 'no offer after the 8 examples').toBeNull();
  }
  console.log(`C3 RSS renderer at ready ${m.atReady.rss.rendererGB} GB, after 8 ${m.afterAll.rss.rendererGB} GB, peak ${m.peak.rendererGB} GB = ${m.peak.rendererGiB} GiB (total ${m.peak.totalGiB} GiB), fail line ${MEM_FAIL_BYTES / 1e9} GB; heap ${m.atReady.heap && m.atReady.heap.currentBytes} -> ${m.afterAll.heap && m.afterAll.heap.currentBytes}`);
  expect(fail).toEqual([]);
  expect(m.peak.rendererBytes, `renderer RSS (summed) < ${MEM_FAIL_BYTES / 1e9} GB (BUILD-PLAN §8.3 C3)`).toBeLessThan(MEM_FAIL_BYTES);
  expect(q.stats.workerDeaths).toBe(0);
  if (API) {
    // v1 ?mem=<GiB> (contract item 8): the knob travels as &memory=<GiB> on the frame URL, no light first session, no wrap,
    // and the page commits exactly that (status().mem.applied: api.status().memory.initialBytes === the requested bytes).
    // Measured AFTER the RSS gate above, in a NEW browser (as C21 (b) and C23): the 8-example session is classified now under
    // C3's own strict verdict (no scenario: no session may be disposed during the lane) and closed, so no second runtime
    // boots in the same renderer (the L9 reload/restart pattern) and nothing is disposed mid-flight.
    await ux.close(s);
    const s3 = await ux.launch({ profile: 'warm', label: 'mem3' });
    const gm = await Gallery.open(s3, { hash: 'chart-kit', query: '?mem=3' });
    expect(gm.boot.s.phase).toBe('ready');
    const sm = await gm.status(); const fm = await gm.frameFacts();
    m.v1mem = { mem: sm.mem, search: fm && fm.search };
    console.log(`C3 v1 ?mem ${JSON.stringify(m.v1mem)}`);
    expect(sm.mem, '?mem=3 applied through &memory=3').toMatchObject({ requestedGiB: 3, bytes: 3 * 1073741824, ok: true, applied: true, wrapped: false, light: null, sessions: [], memory: { initialBytes: 3 * 1073741824 } });
    expect(fm && fm.search, 'the frame URL carries &memory=3').toMatch(/[?&]memory=3(&|$)/);
  }
});

test('C4 switching through the UI: 8 sequential card clicks, then a storm of 8 card clicks in 2 s', async ({ ux }) => {
  const m = ux.metrics;
  const s = await ux.launch({ profile: 'warm', label: 'switch' });
  const g = await Gallery.open(s, { hash: 'tree-scope' });
  expect(g.boot.s.phase).toBe('ready');
  const q0 = await g.qstatus();
  const order = ['chart-kit', 'hasse-view', 'interval-inspector', 'simp-lens', 'expr-xray', 'tree-scope', 'graph-scope', 'dist-lens'];
  m.sequential = [];
  const fail = [];
  for (const id of order) {
    const t = Date.now();
    const r = await g.selectUI(id); // a real mouse click on the card
    const p = await firstPanel(g, id);
    const iv = await g.ivText();
    const rec = { id, ok: r.ok, via: 'card click', switchMs: r.ok ? r.s.lastSwitchMs : null, toPanelMs: Date.now() - t, panelEqual: p.equal, noConnection: /No connection to Lean/.test(iv) };
    m.sequential.push(rec);
    if (!r.ok || !p.equal || rec.noConnection) fail.push(`sequential ${id}: ${JSON.stringify(rec)}`);
  }
  // storm: 8 real card clicks 250 ms apart (2 s); the last wins, the first 7 settle SUPERSEDED (read from the gallery's
  // selection log). The sequential pass ended on dist-lens, so the storm starts elsewhere (re-selecting is a no-op).
  const storm = ['graph-scope', 'tree-scope', 'expr-xray', 'dist-lens', 'simp-lens', 'interval-inspector', 'hasse-view', 'chart-kit'];
  const s0 = await g.status();
  const tok0 = s0.selections.length ? s0.selections[s0.selections.length - 1].token : 0;
  const t = Date.now();
  m.stormClicks = [];
  for (let i = 0; i < storm.length; i++) {
    await sleep(Math.max(0, i * 250 - (Date.now() - t)));
    await g.page.locator(`#card-${storm[i]}`).click({ timeout: 5000 });
    m.stormClicks.push({ id: storm[i], at: Date.now() - t });
  }
  const settled = await until(async () => { const st = await g.status(); const mine = st.selections.filter((l) => l.token > tok0 && l.source === 'rail'); return mine.length === storm.length && mine.every((l) => l.outcome) ? mine : null; }, { timeoutMs: 330000, intervalMs: 150 });
  const results = settled ? settled.map((l) => l.outcome) : ['TIMEOUT'];
  m.stormIds = settled ? settled.map((l) => l.id) : null;
  const p = await firstPanel(g, 'chart-kit');
  const st = await g.status(); const q1 = await g.qstatus(); const iv = await g.ivText();
  m.storm = { results, ms: Date.now() - t, shown: st.shown, panelEqual: p.equal, diffs: p.diffs.slice(0, 3), staleText: /bipartite|Hasse|poset:|X-Ray|Simp Lens|dist: 6 outcomes/.test(iv), noConnection: /No connection to Lean/.test(iv), workerDeaths: q1.stats.workerDeaths - q0.stats.workerDeaths, reboots: q1.stats.reboots - q0.stats.reboots, textIsChartKit: (await g.currentText()) === EXAMPLES.find((e) => e.id === 'chart-kit').text };
  await g.page.screenshot({ path: screenPath('C4-after-storm.png') });
  console.log(`C4 sequential ${m.sequential.map((r) => `${r.id}:${r.switchMs}`).join(' ')}; storm ${JSON.stringify(m.storm)}`);
  expect(fail).toEqual([]);
  expect(m.stormClicks[7].at, '8 clicks within 2 s').toBeLessThanOrEqual(2100);
  expect(m.stormIds).toEqual(storm);
  expect(results.slice(0, 7).every((r) => r === 'SUPERSEDED')).toBe(true);
  expect(results[7]).toBe('ok');
  expect(m.storm).toMatchObject({ shown: 'chart-kit', panelEqual: true, staleText: false, noConnection: false, workerDeaths: 0, reboots: 0, textIsChartKit: true });
});
