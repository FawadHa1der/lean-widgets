// C13 visual baselines (light). Per widget: the first-cursor panel in the real InfoView at 1440x900, and the whole
// gallery at 1440x900; the gallery at 390x844 (mobile emulation, stacked page). Baselines live in
// tests/ux/__screenshots__/ and were approved after the first green run (docs/UX-RESULTS.md); later runs compare with
// maxDiffPixelRatio 0.01 (playwright.config.mjs). Volatile regions are masked: the gallery status text (timings),
// the QED64 page bar (live memory readout) and Monaco's cursor layer (blink).
// Dark: only the gallery chrome follows prefers-color-scheme; the QED64 page and its InfoView stay light because the
// bundle hard-wires "Visual Studio Light" (gallery README resolved question 6) — recorded here as evidence, no baseline.
import { test, expect } from '../lib/fixtures.mjs';
import { Gallery, EXAMPLES, BY_ID, sleep } from '../lib/qed64.mjs';
import { goldenCursor } from '../lib/actions.mjs';

const firstAt = (id) => ({ line: BY_ID[id].firstCursor.line, character: BY_ID[id].firstCursor.character });
const masks = (g) => [g.page.locator('#status-text'), g.qframe.locator('#bar'), g.qframe.locator('.monaco-editor .cursors-layer')];

test('C13a visual baselines: 8 widget panels and the gallery at 1440x900 (light)', async ({ ux }) => {
  const m = ux.metrics; m.shots = [];
  const s = await ux.launch({ profile: 'warm', viewport: { width: 1440, height: 900 } });
  const g = await Gallery.open(s, { hash: EXAMPLES[0].id });
  expect(g.boot.s.phase).toBe('ready');
  const fail = [];
  for (const ex of EXAMPLES) {
    const id = ex.id;
    if ((await g.status()).shown !== id) { const r = await g.select(id); expect(r.ok).toBe(true); }
    const at = firstAt(id);
    await g.setCursor(at.line, at.character);
    const p = await g.expectPanel(at, goldenCursor(id, at.line, at.character).panels[0], { timeoutMs: 60000 });
    if (!p.equal) fail.push(`${id}: panel ${p.diffs.slice(0, 2)}`);
    await g.ivSettled(); await sleep(800);
    const panel = g.iv.locator('[data-ux-panel]').first();
    await panel.scrollIntoViewIfNeeded();
    await g.page.mouse.move(2, 2);
    for (const [name, fn] of [[`C13-panel-${id}.png`, () => expect(panel).toHaveScreenshot(`C13-panel-${id}.png`)], [`C13-gallery-${id}.png`, () => expect(g.page).toHaveScreenshot(`C13-gallery-${id}.png`, { mask: masks(g) })]]) {
      try { await fn(); m.shots.push({ name, ok: true }); } catch (e) { m.shots.push({ name, ok: false, error: String(e.message).split('\n').slice(0, 3).join(' ') }); fail.push(`${name}: ${String(e.message).split('\n')[0]}`); }
    }
  }
  expect(fail).toEqual([]);
});

test('C13b visual baseline: the gallery at 390x844 (mobile emulation, stacked page)', async ({ ux }) => {
  const m = ux.metrics;
  const s = await ux.launch({ profile: 'fresh', viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  const g = await Gallery.open(s, { hash: 'hasse-view' });
  expect(g.boot.s.phase).toBe('ready');
  const at = firstAt('hasse-view');
  const p = await g.expectPanel(at, goldenCursor('hasse-view', at.line, at.character).panels[0], { timeoutMs: 60000 });
  m.panelEqual = p.equal;
  m.layout = await g.page.evaluate(() => ({ scrollW: document.documentElement.scrollWidth, innerW: window.innerWidth, select: !!document.querySelector('#example-select') && getComputedStyle(document.querySelector('#example-select')).display !== 'none' }));
  m.stacked = await g.q(() => { const s = document.getElementById('split'); return s ? getComputedStyle(s).flexDirection : null; });
  await g.ivSettled(); await sleep(800);
  await expect(g.page).toHaveScreenshot('C13-gallery-390x844.png', { mask: masks(g) });
  expect(p.equal).toBe(true);
  expect(m.layout.scrollW, 'no horizontal page scroll at 390 px').toBeLessThanOrEqual(390);
  expect(m.stacked).toBe('column');
});

test('C13c dark scheme (evidence, no baseline): gallery chrome follows prefers-color-scheme, the QED64 InfoView stays light', async ({ ux }) => {
  const m = ux.metrics;
  const s = await ux.launch({ profile: 'warm', colorScheme: 'dark' });
  const g = await Gallery.open(s, { hash: 'tree-scope' });
  expect(g.boot.s.phase).toBe('ready');
  await g.ivSettled(); await sleep(800);
  m.galleryBg = await g.page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  m.infoviewBg = await g.iv.locator('body').evaluate((b) => getComputedStyle(b).backgroundColor);
  m.infoviewText = await g.iv.locator('body').evaluate((b) => getComputedStyle(b).color);
  m.pageTheme = await g.q(() => [...document.querySelectorAll('.monaco-editor')].map((e) => e.className.match(/vs(-dark)?\b/g)).flat().filter(Boolean).slice(0, 3));
  await g.page.screenshot({ path: (await import('../lib/qed64.mjs')).screenPath('C13-dark-1440.png') });
  console.log(`C13 dark ${JSON.stringify(m)}`);
  expect(m.galleryBg).not.toBe('rgb(255, 255, 255)');
  // QED64 limitation (bundle hard-wires "Visual Studio Light"): the InfoView is light under a dark OS scheme
  expect(m.infoviewText).toBe('rgb(0, 0, 0)');
});
