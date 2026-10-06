#!/usr/bin/env node
// tests/ux/tools/v1-smoke.mjs — ONE browser smoke of the gallery's V1 mode (QED64 embedding contract v1,
// deps/qed64/docs/EMBEDDING.md) against a REAL pin that carries an apiRevision (pin F 84d594e): chromium headless, one
// page, a fresh profile, through the host browser lock:
//
//   LOCK_WAIT_S=7200 UX_RUN=v1-smoke scripts/with-browser-lock.sh v1a-smoke node tests/ux/tools/v1-smoke.mjs --origin http://localhost:5235
//
// What it checks (the gallery lane's contract items; the suite's goldens and specs are the tests lane's):
//   1. /showcase/#hasse-view reaches __showcase.status().phase 'ready' (progress-aware wait: a cold boot takes minutes);
//   2. status().api.present && .embed, bridge.stoodDown, liveness.probe 'stood-down', seed.action 'embed', mode 'v1';
//   3. the frame URL has embed=1 and no #code= left (the page read it once and dropped it);
//   4. localStorage['qed64.buffer'] on the QED64 origin still holds the sentinel seeded before navigation;
//   5. the InfoView shows the HasseView panel at the first cursor, equal to its golden signature (lean/expect);
//   6. the first MakeEditLink (or a core "Try this" [apply] span) edits the editor natively (capabilities.editorRpc):
//      currentText() changes and status().edited becomes true;
//   7. __showcase.reset() restores the example; __showcase.select('chart-kit') is ready with that text;
//   8. frame.contentWindow.location.reload() (a reload the gallery did not start) is adopted: setDocument from the
//      frame-api handler re-seeds the example, phase ready, currentText equals the example, api.adopted 1;
//   9. the console: every console.error / console.warning / pageerror the harness saw, classified against the suite's
//      allowlist (tests/ux/selectors.json consoleAllowlist, with the LSP tap pairing) in two windows: strictly before step 8's
//      reload, with relayRestartOrReboot after it, plus one whole-run pairing (each LSP reply explains one line over the
//      run); any unexpected / over-limit / unpaired line is printed verbatim.
// Report: out/ux/v1-smoke/report.json, `complete: true` only once every step ran and the console verdict was taken (a run
// killed by a timeout or a signal leaves `complete: false` / `interrupted`, never a report that looks finished).
// Exit 0 = every assertion passed, 1 = a failure, 3 = infrastructure (lock, cooldown, server, an interrupted or incomplete run).
// Worst-case budgets add up to ~30 min (+ the lock wait): run it in the background, or with a small LOCK_WAIT_S, and read
// `complete` in the report.
import fs from 'node:fs';
import path from 'node:path';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const ORIGIN = arg('--origin', process.env.UX_ORIGIN || 'http://localhost:5235');
process.env.UX_ORIGIN = ORIGIN;
process.env.UX_RUN = process.env.UX_RUN || 'v1-smoke';
// The console allowlist's '@qed64-main-bundle' resolves per pin (bundle names are content hashes): resolve it for the pin the
// server actually SERVES (X-Showcase-Pin on every serve.mjs response), not the active one, via the harness's UX_PIN.
const pinUrl = `${ORIGIN}/showcase/pin.json`;
let servedId = null;
try { const r = await fetch(pinUrl); if (!r.ok) throw new Error(`HTTP ${r.status}`); servedId = (r.headers.get('x-showcase-pin') || '').trim().split(/\s+/)[0] || null; } catch (e) { console.error(`v1-smoke: refused — ${pinUrl}: ${e.message}`); process.exit(3); }
const PINS = await import('../../../scripts/lib/pins.mjs');
if (servedId && servedId !== PINS.activePinId() && !process.env.UX_PIN) process.env.UX_PIN = servedId;
// the harness (launch: lock + cooldown + the LSP tap + the console watcher; Gallery: the /showcase/ driver) reads UX_RUN / UX_ORIGIN / UX_PIN at import
let H;
try { H = await import('../lib/qed64.mjs'); } catch (e) { console.error(`v1-smoke: refused — the harness did not load: ${e.message}`); process.exit(3); }
const { launch, Gallery, BY_ID, RUN_DIR, sleep, until, SC } = H;

const SENTINEL = '-- v1-smoke sentinel: embed mode must not read or write this\n';
const BOOT_BUDGET_MS = 400000; // a cold first boot of pin F (3–4 min) + slack; warm ~15 s
// every assertion a complete run records (a run that lacks one is incomplete: exit 3)
const EXPECTED = ['boot: ready', 'mode: v1 through the frame-api', 'bridge stood down', 'liveness probe stood down', 'seed: embed (no qed64.buffer seeding)', 'progress from api events', 'status().qed64 carries the api projections', 'document event + persistence', 'currentText() is the example (api.getDocument)', 'frame URL: embed=1, #code= consumed', 'page: frozen api, examples menu hidden, no bridge expando', 'qed64.buffer untouched (sentinel)', 'boot persistence (forced at navigation): qed64-showcase:document holds the example', 'InfoView shows the HasseView panel', 'InfoView link edits the editor natively', 'reset() restores the example', "select('chart-kit') ready with its text", 'qed64-showcase:document follows the switch', 'adopted reload re-seeds and follows the example', 'after the reload: sentinel still untouched, no #code=', 'no stall card, no gallery restart, no probe', 'console: nothing outside the allowlist'];
const report = { startedAt: new Date().toISOString(), origin: ORIGIN, servedPin: servedId, uxPin: process.env.UX_PIN || null, pin: null, complete: false, interrupted: null, missing: null, assertions: [], console: null, timings: {}, notes: [] };
let failed = 0;
function check(name, ok, detail) {
  report.assertions.push({ name, ok: !!ok, detail });
  if (!ok) failed++;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name} :: ${detail}`);
  save();
}
function save() { fs.mkdirSync(RUN_DIR, { recursive: true }); fs.writeFileSync(path.join(RUN_DIR, 'report.json'), `${JSON.stringify({ ...report, failed, total: report.assertions.length }, null, 2)}\n`); }
const pin = H.GALLERY_PIN;
report.pin = { pin: pin.pin, buildId: pin.buildId, apiRevision: H.API_REVISION, shell: pin.shell ?? null, modeSource: pin.modeSource || 'pin.json' };
if (!H.API) { console.error(`v1-smoke: refused — ${ORIGIN} serves a legacy page (no apiRevision; served pin ${servedId})`); save(); process.exit(3); }
console.log(`v1-smoke: ${ORIGIN} serves pin ${servedId || pin.pin} (gallery pin.json ${pin.pin}, ${pin.buildId}, api ${H.API_REVISION}); reports in ${path.relative(SC, RUN_DIR)}`);

const testInfo = { title: 'v1-smoke', file: 'tools/v1-smoke.mjs' };
let s = null;
let reloaded = false; // step 8 ran: the frame reload disposes a session on purpose (the console verdict's scenario)
let tReloadWall = null; let loadsAtReload = null; // when step 8 reloaded the frame, and the page loads counted until then
const sumLoads = () => s.watches.reduce((a, w) => ({ top: a.top + w.loads.top, qed64: a.qed64 + w.loads.qed64, infoview: a.infoview + w.loads.infoview }), { top: 0, qed64: 0, infoview: 0 });
const t0 = Date.now();
const T = (k) => { report.timings[k] = Date.now() - t0; };
// a killed run (a foreground timeout, ^C) says so in the report and closes the browser
for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, async () => {
    if (report.interrupted) { process.exit(3); return; } // a second signal: exit now
    report.interrupted = sig; report.finishedAt = new Date().toISOString(); save();
    console.error(`v1-smoke: interrupted by ${sig}; report.complete stays false`);
    setTimeout(() => process.exit(3), 15000).unref(); // a hard fallback: a wedged renderer must not keep the lock past the signal
    try { if (s) await Promise.race([s.close(), new Promise((r) => setTimeout(r, 10000))]); } catch { /* ignore */ } finally { process.exit(3); }
  });
}
try { s = await launch(testInfo, { profile: 'fresh', label: 'v1' }); } catch (e) {
  console.error(`v1-smoke: refused — ${e.message}`); report.notes.push(`infrastructure: ${e.message}`); report.finishedAt = new Date().toISOString(); save(); process.exit(3);
}
try {
  const page = await s.newPage();
  // the sentinel: seeded ONCE in the origin's storage (the gallery and the QED64 frame are the same origin) before the gallery
  // loads, from a document that runs no gallery or page code; never re-seeded, so a removal is caught as well as an overwrite
  await page.goto(`${ORIGIN}/showcase/pin.json`);
  await page.evaluate((t) => localStorage.setItem('qed64.buffer', t), SENTINEL);
  const g = new Gallery(s, page);
  const HV = BY_ID['hasse-view']; const CK = BY_ID['chart-kit'];
  const frame = async () => { const h = await page.$('#qed64-frame'); return h ? h.contentFrame() : null; };
  const status = () => g.status();
  // progress-aware boot wait: the gallery's own budget is re-armed by progress; we stop on ready / error / our hard budget
  const waitPhase = async (want, { timeoutMs = BOOT_BUDGET_MS, label = want } = {}) => {
    const tw = Date.now(); let last = null;
    for (;;) {
      last = await status();
      if (last && last.phase === want) return last;
      if (last && ['error', 'halted', 'unsupported'].includes(last.phase) && want !== last.phase) return last;
      if (Date.now() - tw > timeoutMs) { report.notes.push(`${label}: timed out after ${Math.round((Date.now() - tw) / 1000)} s; last status ${JSON.stringify(last && { phase: last.phase, op: last.op, boot: last.boot && { waiting: last.boot.waiting, elapsedMs: last.boot.elapsedMs, idleMs: last.boot.idleMs, bytes: last.boot.bytes, label: last.boot.label }, error: last.error })}`); return last; }
      await sleep(250);
    }
  };

  // 1. boot
  g.tNav = Date.now();
  await page.goto(`${ORIGIN}/showcase/#hasse-view`, { waitUntil: 'domcontentloaded' });
  let st = await waitPhase('ready', { label: 'first boot' });
  T('ready');
  check('boot: ready', st && st.phase === 'ready' && st.shown === 'hasse-view', `phase ${st && st.phase}, shown ${st && st.shown}, boot ${st && Math.round(st.bootMs)} ms, op ${JSON.stringify(st && st.op)}${st && st.error ? `, error ${JSON.stringify(st.error)}` : ''}`);
  // 2. the V1 mode facts
  check('mode: v1 through the frame-api', st && st.mode === 'v1' && st.api && st.api.present === true && st.api.embed === true && st.api.via === 'frame-api' && st.api.revision === H.API_REVISION && st.api.capabilities && st.api.capabilities.editorRpc === true && st.api.capabilities.widgetSourceCache === true && st.api.capabilities.liveness === true,
    `status().api ${JSON.stringify(st && st.api && { present: st.api.present, embed: st.api.embed, via: st.api.via, revision: st.api.revision, docs: st.api.docs, events: st.api.events, capabilities: st.api.capabilities })}`);
  check('bridge stood down', st && st.bridge && st.bridge.stoodDown === true && st.bridge.installed === false && st.bridge.installs.length === 0 && st.bridge.late === 0 && st.bridge.capabilityMismatch === null, `status().bridge ${JSON.stringify(st && st.bridge)}`);
  check('liveness probe stood down', st && st.liveness && st.liveness.probe === 'stood-down' && st.liveness.sent === 0 && st.liveness.answered === 0 && st.liveness.missed === 0 && st.liveness.qed64 && st.liveness.qed64.builtIn === true && st.liveness.qed64.api === true && st.liveness.qed64.probeAfterMs === 6000,
    `status().liveness probe ${st && st.liveness && st.liveness.probe}, sent ${st && st.liveness && st.liveness.sent}, qed64 ${JSON.stringify(st && st.liveness && st.liveness.qed64 && { builtIn: st.liveness.qed64.builtIn, api: st.liveness.qed64.api, stalled: st.liveness.qed64.stalled, lastAnswerAgoMs: st.liveness.qed64.lastAnswerAgoMs, lastFrameAgoMs: st.liveness.qed64.lastFrameAgoMs, probeAfterMs: st.liveness.qed64.probeAfterMs, totals: st.liveness.qed64.totals })}`);
  check('seed: embed (no qed64.buffer seeding)', st && st.seed && st.seed.action === 'embed' && st.seed.saved === false, `status().seed ${JSON.stringify(st && st.seed)}`);
  check('progress from api events', st && st.stall && st.stall.source === 'api-events' && st.stall.tapped === true && st.boot && st.boot.source === 'api-events' && st.boot.uiTapped === false && st.boot.apiBootEvents > 0,
    `stall {source ${st && st.stall && st.stall.source}, progressMsgs ${st && st.stall && st.stall.progressMsgs}}, boot {source ${st && st.boot && st.boot.source}, apiBootEvents ${st && st.boot && st.boot.apiBootEvents}, bytes ${st && st.boot && st.boot.bytes}, sources ${JSON.stringify(st && st.boot && st.boot.sources)}}`);
  check('status().qed64 carries the api projections', st && st.qed64 && st.qed64.phase === 'ready' && Array.isArray(st.qed64.snapshots) && st.qed64.snapshots.includes('mathlib') && st.qed64.boot && st.qed64.boot.done === true && st.qed64.liveness && st.qed64.memory && st.qed64.memory.initialBytes > 0,
    `qed64 ${JSON.stringify(st && st.qed64 && { phase: st.qed64.phase, version: st.qed64.version, session: st.qed64.session, snapshots: st.qed64.snapshots, boot: st.qed64.boot, memory: st.qed64.memory, offer: st.qed64.offer })}`);
  // the forced boot write (gallery.js boot(): persistDocument(ex.text, {force}) before the frame navigates) sets persisted on its
  // own, so persistence FROM the event is the event's arrival plus a second write: writes >= 2 (the boot write + a 'document' one)
  check('document event + persistence', st && st.document && st.document.version != null && st.document.length === HV.text.length && st.document.persisted === true && st.document.lastEventAgoMs != null && st.document.writes >= 2, `status().document ${JSON.stringify(st && st.document)}`);
  const curText = await g.currentText();
  check('currentText() is the example (api.getDocument)', curText === HV.text && st.cursor && st.cursor.lineNumber === HV.firstCursor.lineNumber, `text ${curText === HV.text ? 'equal' : `differs (${curText === null ? 'null' : `${curText.length} chars`})`}, cursor ${JSON.stringify(st && st.cursor)} (first cursor L${HV.firstCursor.lineNumber})`);
  // 3. the frame URL and the page's own view of things (read from the TEST; the gallery itself never touches them)
  const fr = await frame();
  const frameUrl = fr ? fr.url() : null;
  check('frame URL: embed=1, #code= consumed', !!frameUrl && /[?&]embed=1(&|$)/.test(frameUrl) && /[?&]snapshots=snapshots\/widgets8/.test(frameUrl) && !/#code=/.test(frameUrl) && !/#/.test(frameUrl), `frame url ${frameUrl}`);
  const pageFacts = fr ? await fr.evaluate(() => {
    const a = globalThis.qed64 && globalThis.qed64.api;
    const ex = document.getElementById('examples');
    return { frozen: !!a && Object.isFrozen(a) && Object.isFrozen(a.capabilities), revision: a && a.revision, doc: a && a.getDocument() && { version: a.getDocument().version, length: a.getDocument().text.length }, snapshots: a && a.status().snapshots, boot: a && a.status().boot, examplesHidden: !!ex && ex.style.display === 'none', /* the page's own inline style (embed mode), not the gallery's stylesheet */ buffer: (() => { try { return localStorage.getItem('qed64.buffer'); } catch { return 'storage-error'; } })(), saved: (() => { try { return localStorage.getItem('qed64-showcase:document'); } catch { return null; } })(), hasQed64Bridge: '__qed64Bridge' in window, hasShowcaseBridge: '__showcaseBridge' in window, showcaseKeys: !!window.__showcaseKeys, stack: !!document.getElementById('qed64-showcase-stack'), pageStyle: !!document.getElementById('qed64-showcase-page') };
  }).catch((e) => ({ error: String(e && e.message || e).slice(0, 200) })) : { error: 'no frame' };
  check('page: frozen api, examples menu hidden, no bridge expando', pageFacts.frozen === true && pageFacts.revision === H.API_REVISION && pageFacts.examplesHidden === true && pageFacts.hasQed64Bridge === false && pageFacts.hasShowcaseBridge === false && pageFacts.showcaseKeys === true && pageFacts.pageStyle === true,
    `${JSON.stringify({ ...pageFacts, buffer: pageFacts.buffer === SENTINEL ? 'sentinel' : pageFacts.buffer, saved: pageFacts.saved == null ? null : `${pageFacts.saved.length} chars` })}`);
  // 4. the sentinel
  check('qed64.buffer untouched (sentinel)', pageFacts.buffer === SENTINEL, `localStorage['qed64.buffer'] on the QED64 origin ${pageFacts.buffer === SENTINEL ? '== the sentinel' : `= ${JSON.stringify(pageFacts.buffer && pageFacts.buffer.slice(0, 60))}`}`);
  check('boot persistence (forced at navigation): qed64-showcase:document holds the example', pageFacts.saved === HV.text, `${pageFacts.saved === HV.text ? 'equal to hasse-view' : `${pageFacts.saved == null ? 'absent' : `${pageFacts.saved.length} chars`}`}`);
  // 5. the InfoView panel at the first cursor, compared with its golden signature as the suite does (this is the step that
  //    exercises the page's own widget-source cache in place of the stood-down bridge)
  const at = { line: HV.firstCursor.line, character: HV.firstCursor.character };
  const gc = H.GOLDENS['hasse-view'].cursors.find((c) => c.line === at.line && c.character === at.character) || null;
  const pnl = gc && gc.panels.length ? await g.expectPanel(at, gc.panels[0], { timeoutMs: 120000 }) : null;
  T('panel');
  const ivTxt = await g.ivText();
  check('InfoView shows the HasseView panel', !!pnl && pnl.equal && !/Unrecognised error|abortSignal/.test(ivTxt), pnl ? `golden ${gc.panels[0].id || gc.panels[0].kind || 'panel 0'} at ${at.line}:${at.character}: ${pnl.equal ? `equal in ${pnl.ms} ms` : `differs: ${pnl.diffs.slice(0, 3).join('; ')}`}` : `no golden cursor ${at.line}:${at.character} for hasse-view`);
  // 6. a native edit through the InfoView: the example's own first click hint at this cursor (examples.json tryThis
  //    kind 'click', expectClick {linkText, newText, range}): the MakeEditLink with exactly that text. (Every
  //    a.link.pointer.dim is NOT a MakeEditLink: the InfoView's own pin/unpin buttons share the class, with empty text.)
  const hint = HV.tryThis.find((h) => h.kind === 'click' && h.lineNumber === HV.firstCursor.lineNumber && h.expectClick && h.expectClick.kind === 'makeEditLink');
  const expectedAfter = hint ? H.applyEdit(HV.text, hint.expectClick.range, hint.expectClick.newText) : null;
  const allLinks = g.iv.locator('a.link.pointer.dim');
  const applies = g.iv.locator('span.link.pointer.dim.font-code[title="Apply suggestion"]');
  const nLinks = await allLinks.count().catch(() => 0); const nApplies = await applies.count().catch(() => 0);
  let clicked = null;
  if (hint) {
    const want = hint.expectClick.linkText.replace(/\s+/g, ' ').trim();
    const target = await until(async () => {
      const n = await allLinks.count().catch(() => 0);
      for (let i = 0; i < n; i++) { const t = (await allLinks.nth(i).innerText().catch(() => '')).replace(/\s+/g, ' ').trim(); if (t === want) return allLinks.nth(i); }
      return null;
    }, { timeoutMs: 60000, intervalMs: 500 });
    if (target) { clicked = { kind: 'MakeEditLink', text: want, title: await target.getAttribute('title').catch(() => null), hint: hint.label }; await target.click({ timeout: 10000 }); }
    else clicked = null;
  } else if (nApplies > 0) { clicked = { kind: 'tryThis', text: (await applies.first().innerText().catch(() => '')).slice(0, 60) }; await applies.first().click({ timeout: 10000 }); }
  const edited = clicked ? await until(async () => { const x = await status(); const t = await g.currentText(); return x && x.edited === true && t !== null && t !== HV.text ? { st: x, t } : null; }, { timeoutMs: 60000, intervalMs: 250 }) : null;
  T('edit');
  check('InfoView link edits the editor natively', !!clicked && !!edited && (expectedAfter === null || edited.t === expectedAfter), clicked ? `clicked ${JSON.stringify(clicked)} (a.link.pointer.dim ${nLinks}, [apply] ${nApplies}); ${edited ? `edited: text ${edited.t.length} chars (example ${HV.text.length}; ${expectedAfter === null ? 'no expected text' : edited.t === expectedAfter ? '== the hint\'s expected edit' : 'DIFFERS from the hint\'s expected edit'}), status().edited ${edited.st.edited}, bridge installed ${edited.st.bridge.installed}` : `NOT edited within 60 s: status().edited ${(await status()).edited}, text ${(await g.currentText() || '').length} chars`}` : `no MakeEditLink ${hint ? JSON.stringify(hint.expectClick.linkText) : '(no click hint at the first cursor)'} among ${nLinks} a.link.pointer.dim and no [apply] (${nApplies}) in the InfoView`);
  const diagAfterEdit = edited ? await until(async () => { const x = await status(); return x && x.qed64 && x.qed64.phase === 'ready' && x.edited ? x : null; }, { timeoutMs: 120000, intervalMs: 500 }) : null; // no edit: nothing to wait for
  report.notes.push(`after the edit: qed64 ${JSON.stringify(diagAfterEdit && { phase: diagAfterEdit.qed64.phase, version: diagAfterEdit.qed64.version })}, stall ${JSON.stringify(diagAfterEdit && { shown: diagAfterEdit.stall.shown, progressMsgs: diagAfterEdit.stall.progressMsgs })}`);
  // 7. reset, then another example
  await page.evaluate(() => { window.__showcase.reset().catch(() => {}); });
  const afterReset = await until(async () => { const x = await status(); const t = await g.currentText(); return x && x.phase === 'ready' && x.edited === false && t === HV.text ? { x, t } : null; }, { timeoutMs: 330000, intervalMs: 300 });
  T('reset');
  check('reset() restores the example', !!afterReset && afterReset.t === HV.text && afterReset.x.shown === 'hasse-view', afterReset ? `ready in ${Math.round(afterReset.x.lastSwitchMs)} ms, text ${afterReset.t === HV.text ? 'equal' : 'differs'}, how ${JSON.stringify(afterReset.x.stall.events.slice(-2))}` : `not ready within 330 s: ${JSON.stringify((await status()) && { phase: (await status()).phase, error: (await status()).error })}`);
  await page.evaluate(() => { window.__showcase.select('chart-kit').catch(() => {}); });
  const ck = await until(async () => { const x = await status(); const t = await g.currentText(); return x && x.phase === 'ready' && x.shown === 'chart-kit' && t === CK.text ? x : null; }, { timeoutMs: 330000, intervalMs: 300 });
  T('switch');
  check("select('chart-kit') ready with its text", !!ck && ck.cursor && ck.cursor.lineNumber === CK.firstCursor.lineNumber, ck ? `switch ${Math.round(ck.lastSwitchMs)} ms, qed64 v${ck.qed64.version} ${ck.qed64.phase}, cursor ${JSON.stringify(ck.cursor)}, document v${ck.document.version}` : `not ready: ${JSON.stringify((await status()) && { phase: (await status()).phase, shown: (await status()).shown, error: (await status()).error })}`);
  // the persisted document now holds chart-kit (within a second)
  const persisted = await until(async () => { const f = await frame(); const v = f ? await f.evaluate(() => { try { return localStorage.getItem('qed64-showcase:document'); } catch { return null; } }).catch(() => null) : null; return v === CK.text ? true : null; }, { timeoutMs: 5000, intervalMs: 250 });
  check('qed64-showcase:document follows the switch', persisted === true, persisted ? 'equal to chart-kit' : 'not updated within 5 s');
  // 8. a reload the gallery did not start: the page's own document (no #code= any more) must be re-seeded synchronously
  const before = await status();
  // the console windows (finally): before this instant no session may be disposed (strict); after it the reload's (as C25)
  tReloadWall = Date.now(); loadsAtReload = sumLoads();
  reloaded = true;
  await page.evaluate(() => { document.getElementById('qed64-frame').contentWindow.location.reload(); });
  const adopted = await until(async () => { const x = await status(); const t = await g.currentText(); return x && x.phase === 'ready' && x.booted && x.api && x.api.adopted >= 1 && x.op.label !== 'switch' && t === CK.text ? x : null; }, { timeoutMs: BOOT_BUDGET_MS, intervalMs: 300 });
  T('reload');
  const after = adopted || await status();
  check('adopted reload re-seeds and follows the example', !!adopted && adopted.shown === 'chart-kit' && adopted.api.adopted === 1 && adopted.api.docs === (before.api.docs + 1) && adopted.api.adoptSet && adopted.api.adoptSet.from === 'saved' && adopted.bridge.installed === false,
    `${adopted ? `ready ${Math.round(adopted.bootMs)} ms after the reload (op ${adopted.op.label}), shown ${adopted.shown}, api {adopted ${adopted.api.adopted}, docs ${adopted.api.docs}, adoptSet ${JSON.stringify(adopted.api.adoptSet)}}, snapshots ${JSON.stringify(adopted.qed64.snapshots)}, text equal` : `not adopted within the budget: ${JSON.stringify(after && { phase: after.phase, op: after.op, api: after.api && { adopted: after.api.adopted, docs: after.api.docs, adoptSet: after.api.adoptSet }, error: after.error, text: (await g.currentText() || '').length })}`}`);
  const fr2 = await frame();
  const after2 = fr2 ? await fr2.evaluate(() => ({ buffer: (() => { try { return localStorage.getItem('qed64.buffer'); } catch { return 'storage-error'; } })(), url: location.href, doc: globalThis.qed64 && globalThis.qed64.api.getDocument() && globalThis.qed64.api.getDocument().text.length })).catch(() => null) : null;
  check('after the reload: sentinel still untouched, no #code=', !!after2 && after2.buffer === SENTINEL && !/#code=/.test(after2.url) && after2.doc === CK.text.length, JSON.stringify(after2 && { buffer: after2.buffer === SENTINEL ? 'sentinel' : after2.buffer, url: after2.url, doc: after2.doc }));
  const final = await status();
  report.final = final && { phase: final.phase, shown: final.shown, api: final.api, bridge: final.bridge, document: final.document, liveness: { probe: final.liveness.probe, sent: final.liveness.sent, qed64: final.liveness.qed64, events: final.liveness.events.slice(-10) }, stall: { shown: final.stall.shown, restarts: final.stall.restarts, progressMsgs: final.stall.progressMsgs, events: final.stall.events.slice(-10) }, boot: { source: final.boot.source, apiBootEvents: final.boot.apiBootEvents, bytes: final.boot.bytes, sources: final.boot.sources, stalls: final.boot.stalls, recovered: final.boot.recovered, noticeShown: final.boot.noticeShown }, selections: final.selections, qed64: final.qed64 };
  check('no stall card, no gallery restart, no probe', final && final.stall.shown === 0 && final.stall.restarts === 0 && final.liveness.sent === 0 && final.liveness.wedged === 0 && final.boot.stalls === 0, `stall shown ${final && final.stall.shown}, restarts ${final && final.stall.restarts}, probes ${final && final.liveness.sent}, boot stalls ${final && final.boot.stalls}, wedged reboots ${final && final.liveness.qed64.wedgedReboots}`);
} catch (e) {
  check('harness', false, `threw: ${String(e && e.stack || e).slice(0, 600)}`);
} finally {
  // interrupted (a signal): the handler closes the browser and exits 3; never take a verdict on a half-run (exit 1 would read as a failure)
  if (report.interrupted) { save(); process.exit(3); }
  if (s) {
    // 9. the console, classified against the suite's allowlist (the LSP tap pairs the empty console.error with its -32800 reply),
    //    in TWO windows: before step 8's frame reload strictly (no scenario: nothing may dispose a session during boot, the
    //    InfoView edit, reset() or the switch), after it with relayRestartOrReboot (the reload disposes a session, as C25).
    //    Each window gets the page loads counted in it (the per-load limits). Each window pairs against ALL the LSP tap's
    //    replies, so one reply could explain a line on both sides: one whole-run classification (relayRestartOrReboot) must
    //    also leave no line unpaired and no empty console.error unexplained (each reply explains one line over the run).
    const all = { messages: s.watches.flatMap((w) => w.messages), pageErrors: s.watches.flatMap((w) => w.pageErrors), crashed: s.watches.some((w) => w.crashed) };
    const total = sumLoads();
    const win = (pred, loads) => ({ messages: all.messages.filter(pred), pageErrors: all.pageErrors.filter(pred), crashed: all.crashed, loads });
    const split = reloaded && tReloadWall != null;
    const vPre = H.classify(win((m) => !split || m.wall < tReloadWall, split ? loadsAtReload : total), s.reports, { scenarios: [] });
    const vPost = split ? H.classify(win((m) => m.wall >= tReloadWall, { top: total.top - loadsAtReload.top, qed64: total.qed64 - loadsAtReload.qed64, infoview: total.infoview - loadsAtReload.infoview }), s.reports, { scenarios: ['relayRestartOrReboot'] }) : null;
    const vAll = split ? H.classify(win(() => true, total), s.reports, { scenarios: ['relayRestartOrReboot'] }) : null;
    const wholeRunPaired = !vAll || ((vAll.unpaired || []).length === 0 && !(vAll.emptyErrors && vAll.emptyErrors.unexplained.length));
    const vs = [['pre-reload', vPre], ...(vPost ? [['post-reload', vPost]] : [])];
    const ok = vs.every(([, v]) => v.ok) && wholeRunPaired;
    const summary = (v) => ({ ok: v.ok, scenarios: v.scenarios, counts: v.counts, loads: v.loads, unexpected: v.unexpected, overLimit: v.overLimit, unpaired: v.unpaired, paired: v.paired, emptyErrors: v.emptyErrors, supersededErrors: v.supersededErrors, infoviewDom: v.infoviewDom, line: H.consoleLine(v) });
    const msgs = all.messages.filter((m) => m.type === 'error' || m.type === 'warning');
    const errs = all.pageErrors;
    report.console = { ok, reloadAtWall: tReloadWall, windows: Object.fromEntries(vs.map(([k, v]) => [k, summary(v)])), wholeRun: vAll && { paired: wholeRunPaired, unpaired: vAll.unpaired, emptyErrors: vAll.emptyErrors, line: H.consoleLine(vAll) }, unexpected: vs.flatMap(([k, v]) => (v.unexpected || []).map((u) => ({ window: k, ...u }))), loads: s.watches.map((w) => w.loads), lines: msgs.map((m) => ({ t: m.t, wall: m.wall, type: m.type, text: m.text, url: m.url, line: m.line, worker: m.worker })), pageErrors: errs.map((e) => ({ t: e.t, wall: e.wall, message: e.message, stack: e.stack })), lspErrorReplies: s.reports.filter((r) => r.kind === 'errorReply').map((r) => ({ code: r.code, message: r.message, id: r.id })).slice(0, 40), crashed: all.crashed };
    console.log(`console: ${msgs.length} error/warning line(s), ${errs.length} pageerror(s), allowlist verdict ${ok ? 'ok' : 'NOT ok'}`);
    for (const m of msgs) console.log(`  console.${m.type} [${m.t} ms]${split && m.wall >= tReloadWall ? ' (post-reload)' : ''} ${m.url || ''}:${m.line ?? ''} ${JSON.stringify(m.text)}`);
    for (const e of errs) console.log(`  pageerror [${e.t} ms]${split && e.wall >= tReloadWall ? ' (post-reload)' : ''} ${JSON.stringify(e.message)}`);
    for (const [k, v] of vs) {
      console.log(`  ${k}: ${H.consoleLine(v)}`);
      for (const u of v.unexpected || []) console.log(`  ${k} UNEXPECTED ${JSON.stringify(u)}`);
      for (const u of v.overLimit || []) console.log(`  ${k} OVER-LIMIT ${JSON.stringify(u)}`);
      for (const u of v.unpaired || []) console.log(`  ${k} UNPAIRED ${JSON.stringify(u)}`);
      if (v.emptyErrors && v.emptyErrors.unexplained.length) console.log(`  ${k} EMPTY-UNEXPLAINED ${JSON.stringify(v.emptyErrors)}`);
    }
    if (vAll) {
      for (const u of vAll.unpaired || []) console.log(`  whole-run UNPAIRED ${JSON.stringify(u)}`);
      if (vAll.emptyErrors && vAll.emptyErrors.unexplained.length) console.log(`  whole-run EMPTY-UNEXPLAINED ${JSON.stringify(vAll.emptyErrors)}`);
    }
    check('console: nothing outside the allowlist', ok && !report.console.crashed, `${vs.map(([k, v]) => `${k} ${H.consoleLine(v)}`).join(' | ')}${vAll ? ` | whole-run pairing ${wholeRunPaired ? 'ok' : 'NOT ok'} (unpaired ${(vAll.unpaired || []).length}, empty unexplained ${vAll.emptyErrors ? vAll.emptyErrors.unexplained.length : 0})` : ''}`);
    await s.close();
  }
  report.finishedAt = new Date().toISOString();
  const seen = new Set(report.assertions.map((a) => a.name));
  report.missing = EXPECTED.filter((n) => !seen.has(n));
  report.complete = report.missing.length === 0;
  save();
  console.log(`v1-smoke: ${report.assertions.length - failed}/${report.assertions.length} pass; ${report.complete ? 'complete' : `INCOMPLETE (missing ${report.missing.length}: ${report.missing.join(' | ')})`}; timings ${JSON.stringify(report.timings)}; report ${path.relative(SC, path.join(RUN_DIR, 'report.json'))}`);
  process.exit(report.interrupted ? 3 : failed ? 1 : report.complete ? 0 : 3);
}
