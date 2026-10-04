// C13 (headed) reproduction with and without --force-device-scale-factor=1 (last-mile lane, 2026-10-03). It takes the
// same two screenshots C13a takes for hasse-view (the first-cursor InfoView panel, and the whole gallery at 1440x900
// with C13's masks, animations disabled, caret hidden) in a headed window, so they can be compared pixel by pixel with
// tests/ux/__screenshots__/headed/ (written 2026-10-02 18:45Z) and with a failing run's actual images. Question: were
// the headed baselines rasterised for a 1x display (the window on a non-Retina screen) while today's window is on the 2x
// built-in Retina panel? Writes out/ux/$UX_RUN/screens/c13dsf-<tag>-{panel,gallery}.png and explore/c13dsf-<tag>.json.
//   UX_RUN=<run> scripts/with-browser-lock.sh <lane> node tests/ux/tools/c13-dsf-probe.mjs --origin http://localhost:5197 --tag forced1 --force-dsf 1
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { Session, Gallery, LAUNCH_ARGS, RUN_DIR, SCREENS, BY_ID, lockHeld, cooldown, sleep } from '../lib/qed64.mjs';
import { goldenCursor } from '../lib/actions.mjs';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const ORIGIN = arg('--origin', 'http://localhost:5197'); const TAG = arg('--tag', 'probe'); const CHANNEL = arg('--channel', 'chromium'); const DSF = arg('--force-dsf', null);
const ID = arg('--id', 'hasse-view');
// --mobile: C13b's setup (390x844, isMobile, hasTouch); --arg <a> (repeatable): an extra browser argument
const MOBILE = process.argv.includes('--mobile');
const EXTRA = process.argv.flatMap((x, i, a) => (x === '--arg' ? [a[i + 1]] : []));
fs.mkdirSync(path.join(RUN_DIR, 'explore'), { recursive: true }); fs.mkdirSync(SCREENS, { recursive: true }); fs.mkdirSync(path.join(RUN_DIR, 'tests'), { recursive: true });
lockHeld(); const cool = await cooldown();
const args = [...LAUNCH_ARGS, ...(DSF ? [`--force-device-scale-factor=${DSF}`] : []), ...EXTRA];
const browser = await chromium.launch({ args, headless: false, channel: CHANNEL });
const context = await browser.newContext(MOBILE ? { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, colorScheme: 'light', deviceScaleFactor: 1 } : { viewport: { width: 1440, height: 900 }, colorScheme: 'light', deviceScaleFactor: 1 });
const s = new Session({ testInfo: { title: `c13dsf-${TAG}`, file: 'tools/c13-dsf-probe.mjs' }, browser, context, t0: Date.now(), label: `c13dsf-${TAG}`, profile: 'fresh', cool });
await s.init();
const out = { tag: TAG, args, channel: CHANNEL, version: browser.version() };
const g = await Gallery.open(s, { hash: ID, origin: ORIGIN });
out.phase = g.boot.s.phase;
const at = { line: BY_ID[ID].firstCursor.line, character: BY_ID[ID].firstCursor.character };
await g.setCursor(at.line, at.character);
const p = await g.expectPanel(at, goldenCursor(ID, at.line, at.character).panels[0], { timeoutMs: 60000 });
out.panelEqual = p.equal;
await g.ivSettled(); await sleep(800);
const panel = g.iv.locator('[data-ux-panel]').first();
if (!MOBILE) { await panel.scrollIntoViewIfNeeded(); await g.page.mouse.move(2, 2); }
const realDpr = await (async () => { const pg = await browser.newContext({ viewport: null }).then((c) => c.newPage()); await pg.setContent('x'); const v = await pg.evaluate(() => devicePixelRatio); await pg.context().close(); return v; })();
out.realDisplayDpr = realDpr;
if (!MOBILE) await panel.screenshot({ path: path.join(SCREENS, `c13dsf-${TAG}-panel.png`), animations: 'disabled', caret: 'hide' });
await g.page.screenshot({ path: path.join(SCREENS, `c13dsf-${TAG}-gallery.png`), animations: 'disabled', caret: 'hide', mask: [g.page.locator('#status-text'), g.qframe.locator('#bar'), g.qframe.locator('.monaco-editor .cursors-layer')] });
console.log(`C13DSF ${TAG}: ${JSON.stringify(out)}`);
fs.writeFileSync(path.join(RUN_DIR, 'explore', `c13dsf-${TAG}.json`), `${JSON.stringify(out, null, 1)}\n`);
await s.close();
