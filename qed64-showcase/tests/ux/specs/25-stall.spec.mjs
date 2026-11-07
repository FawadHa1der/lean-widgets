// C21 / C22 / C23: the gallery's answers to QED64 limitation L7 (docs/UX-RESULTS.md, out/hang/ROOT-CAUSE.md) on the QED64
// embedding contract v1 (deps/qed64/docs/EMBEDDING.md).
//
// L7: QED64's whole Lean runtime can freeze (every pthread stops; the worker's JS thread stays alive): QED64 keeps reporting
// 'elaborating' on a serving relay with no death and no LSP message, and a didChange does not help. The intermittent
// original (about 1 hang in 20 C20 runs) cannot be summoned on demand, so C21 FREEZES the checker deterministically with the
// same observable symptoms: right before an edit it detaches the current session's output inside the QED64 page
// (session.onLsp drops every LSP message, session.onStatus drops every 'ready'). A restart replaces the session, and with it
// the detached handlers, as it would replace a frozen worker. Everything this fixture produces is SYNTHETIC: it proves the
// gallery's handling and the hang capture, never anything about L7 itself.
//
// On api.capabilities.liveness the gallery's OWN probe is STOOD DOWN (status().liveness.probe 'stood-down', sent/answered/
// missed 0; QED64's worker liveness is projected by api.status().liveness and the `liveness` event, mirrored in
// status().liveness.qed64). The synthetic freeze is page-level, so QED64's worker keeps seeing frames and its own liveness
// correctly does nothing (liveness.qed64.stalled stays false, nothing reboots).
// C21 (a) default mode: the freeze is surfaced only by the stall card (shortened to ?stall=15), worded 'stopped', and
//   recovered by its "Restart Lean" (how 'api.restart'); (b) observe mode (?liveness=observe, the hang-hunt setting) in a
//   fresh browser (QED64 L9): the hang capture (tests/ux/lib/qed64.mjs captureHang) runs before anything is reset, nothing
//   restarts until the card's button; Keep waiting re-arms the card, the toolbar's Reset example restarts the checker on the
//   example.
// C22 (the negative): a legitimately slow elaboration is NOT restarted: (1) the slowest DistLens declared click (twoDice);
//   (2) a ~38 s silent `#eval IO.sleep` appended to the example, which keeps QED64 'elaborating' with no progress far past
//   any probe threshold; (3) a SATURATED task pool: 24 parallel `theorem … := by sleep 55000; trivial` keep every Lean task
//   thread busy. The block opts in with `set_option Elab.async true`: since QED64 HARDENING #70 (62a06e2) the resident
//   worker runs `-DElab.async=false`, so without it the 24 proofs elaborate one after another (24 x 55 s) and no pool
//   saturates; a file may still opt in (#70: "at its own risk"), and that is the configuration this case needs. No probe of
//   the gallery's own runs, QED64's own liveness (its probe is answered by the FileWorker main loop without a pool thread)
//   sees no stall and reboots nothing, and a 45 s card shown meanwhile is worded "Lean is still working".
// C23: a QED64-handled wedged reboot (fixture) reaches status().liveness.qed64 {wedgedReboots, lastReboot {from, to}} from
//   the API's `death` and `reboot` events, and the harness writes the post-hoc record.
import fs from 'node:fs';
import path from 'node:path';
import { test, expect } from '../lib/fixtures.mjs';
import { Gallery, BY_ID, GOLDENS, SC, PIN, RESTART_HOW, captureHang, screenPath, sleep, until, errorsWarnings } from '../lib/qed64.mjs';
import { clickLink, cursorOfLine, goldenCursor } from '../lib/actions.mjs';

const STALL_S = 15;
// status().liveness.qed64.totals: counted from the API's `liveness` events (no 'probes': the event has no such kind, so the
// gallery reports probes: null)
const TOTAL_KEYS = ['answered', 'stalls', 'resumed', 'rescues'];

/** Detach the current session's output inside the QED64 page (see the header). Returns the frozen session id. */
const freeze = (g) => g.q(() => {
  const r = window.qed64.relay; const s = r.session; const os = s.onStatus;
  s.onLsp = () => {};
  s.onStatus = (st) => { if (st.phase !== 'ready') os(st); };
  window.__uxFrozen = { session: s.id, at: Date.now(), fixture: 'C21 synthetic freeze (session output detached in the page)' };
  return s.id;
});
const galleryNow = (g) => g.page.evaluate(() => performance.now());

test('C21 stall handling (QED64 L7) on a frozen checker: the liveness probe restarts it by itself; observe mode records it, the hang capture runs, and the card still works', async ({ ux }) => {
  test.setTimeout(20 * 60 * 1000);
  const m = ux.metrics; m.v1 = true;
  const id = 'hasse-view'; const ex = BY_ID[id]; const gold = GOLDENS[id];
  // Restart Lean / Reset on the frozen session answer its requests in flight with QED64's "restarting with exact imports"
  // (stallRestart), and the InfoView's old RPC session may be refused once per request. No livenessObserved: the gallery's
  // probe never runs in v1, so its observe-mode console.warn must not appear either.
  ux.scenarios.push('stallRestart', 'relayRestartOrReboot');
  const s = await ux.launch({ profile: 'warm' });

  // ---- (a) default mode: the probe is stood down, the (15 s) card surfaces the freeze, its Restart Lean recovers it
  const g = await Gallery.open(s, { hash: id, query: `?stall=${STALL_S}` });
  expect(g.boot.s.phase).toBe('ready');
  expect(g.boot.s.api, 'the v1 API is present').toMatchObject({ present: true, embed: true });
  expect(g.boot.s.api.capabilities.liveness, 'this v1 branch assumes capabilities.liveness (the probe stands down on it)').toBe(true);
  expect(g.boot.s.stall).toMatchObject({ thresholdMs: STALL_S * 1000, shown: 0, active: false });
  expect(g.boot.s.liveness, 'the gallery probe stood down').toMatchObject({ mode: 'auto', probe: 'stood-down', sent: 0, answered: 0, missed: 0, wedged: 0, restarts: 0 });
  expect(g.boot.s.liveness.qed64, `QED64's liveness (pin ${PIN.id}) projected by the API`).toMatchObject({ builtIn: true, api: true });
  expect(PIN.liveness.builtIn, 'a pin with capabilities.liveness has QED64 liveness built in (pins/<id>/pin.json)').toBe(true);
  const q0 = await g.qstatus();
  const gc = gold.clicks[0];
  const cur = cursorOfLine(id, gc.cursorLine);
  const at = { line: cur.line, character: cur.character };
  let tFreeze = null;
  const r = await clickLink(g, ex, { kind: gc.kind, linkText: gc.linkText, title: gc.linkTitle || null, edit: gc.edit, editedSha256: gc.editedSha256 }, at, goldenCursor(id, at.line, at.character).panels[0],
    { elabTimeoutMs: 180000, beforeClick: async () => { const sid = await freeze(g); tFreeze = await galleryNow(g); return sid; } });
  m.frozenA = r.beforeClick;
  const sa = await g.status(); const qa = await g.qstatus(); const lv = sa.liveness;
  const stall = (r.stalls || [])[0] || null;
  m.a = {
    ok: r.ok, error: r.error || null, editExact: r.editExact, nativeSha: r.nativeSha, errors: r.errors, warnings: r.warnings, clickToReadyMs: r.clickToReadyMs,
    cardStalls: (r.stalls || []).length, cardShown: sa.stall.shown, card: stall && stall.card, variant: stall && stall.galleryStall && stall.galleryStall.variant, shownEvent: stall && stall.shownEvent, restartEvent: stall && stall.restartEvent,
    cardAfterFreezeMs: stall && stall.shownEvent && tFreeze !== null ? Math.round(stall.shownEvent.t - tFreeze) : null, qed64AtCard: stall && stall.qed64,
    liveness: { probe: lv.probe, sent: lv.sent, answered: lv.answered, missed: lv.missed, wedged: lv.wedged, restarts: lv.restarts }, wedgeEvents: lv.events.filter((e) => e.source === 'wedged').length, notice: sa.notice,
    qed64: { api: lv.qed64.api, stalled: lv.qed64.stalled, lastFrameAgoMs: lv.qed64.lastFrameAgoMs, lastAnswerAgoMs: lv.qed64.lastAnswerAgoMs, totals: lv.qed64.totals, wedgedReboots: lv.qed64.wedgedReboots, events: lv.events.filter((e) => String(e.source).startsWith('qed64-')).map((e) => e.source) },
    sessionAfter: qa.session, userRestarts: qa.stats.userRestarts - q0.stats.userRestarts, workerDeaths: qa.stats.workerDeaths - q0.stats.workerDeaths,
    probesSeenByTap: (await g.tap()).calls['showcase-live'] || 0,
  };
  await g.page.screenshot({ path: screenPath('C21-v1-card-recovered.png') });
  console.log(`C21 (a, v1) ${JSON.stringify(m.a)}`);
  expect(m.a.cardStalls, 'the card surfaced the freeze and Restart Lean was pressed once').toBe(1);
  expect(m.a.cardShown).toBe(1);
  expect(m.a.liveness, 'no probe of the gallery\'s own').toEqual({ probe: 'stood-down', sent: 0, answered: 0, missed: 0, wedged: 0, restarts: 0 });
  expect(m.a.wedgeEvents, 'no wedge declared by the gallery').toBe(0);
  expect(m.a.probesSeenByTap, 'no showcase-live probe went through the relay').toBe(0);
  expect(stall.card).toMatchObject({ role: 'alert', title: 'Lean has stopped making progress', restart: 'Restart Lean', reset: true, keepWaiting: 'Keep waiting' });
  expect(m.a.variant, 'no sign of life on a frozen checker (no frame, no fileProgress/diagnostics event, no QED64 answer): the card says it stopped').toBe('stopped');
  expect(stall.shownEvent && stall.shownEvent.idleMs, `shown after >= ${STALL_S} s without progress`).toBeGreaterThanOrEqual(STALL_S * 1000 - 500);
  // QED64 alone at that moment: the L7 symptoms (no death, relay serving, still 'elaborating', the frozen session), read through the API
  expect(stall.qed64).toMatchObject({ phase: 'elaborating', relay: 'serving', lastDeath: null, session: m.frozenA });
  expect(stall.restartEvent, 'Restart Lean = api.restart()').toMatchObject({ source: 'card', how: RESTART_HOW });
  // QED64's own liveness did not act on this page-level freeze (its worker kept seeing frames): no stall, no reboot
  expect(m.a.qed64).toMatchObject({ api: true, stalled: false, wedgedReboots: 0 });
  expect(m.a.qed64.totals.stalls).toBe(0);
  expect(sa.stall.events.some((e) => e.source === 'card' && e.how === RESTART_HOW)).toBe(true);
  expect(m.a, 'the post-click text re-checked clean on a new session').toMatchObject({ ok: true, editExact: true, nativeSha: true, errors: 0, warnings: 0, userRestarts: 1, workerDeaths: 0 });
  expect(m.a.sessionAfter).not.toBe(m.frozenA);
  expect(sa.error, 'no card left').toBeNull();
  const ra = await g.resetUI(ex);
  expect(ra.ok, 'Reset after the recovery').toBe(true);
  await ux.close(s);

  // ---- (b) observe mode (?liveness=observe) with the 15 s card, in a FRESH browser (QED64 L9): the same card (the mode
  // only changes what the stood-down probe would do), the hang capture BEFORE anything resets, nothing restarts until the
  // card's button; Keep waiting re-arms it, the toolbar's Reset example restarts the checker on the example (api.restart).
  const s2 = await ux.launch({ profile: 'warm', label: 'c21-observe' });
  const g2 = await Gallery.open(s2, { hash: id, query: `?stall=${STALL_S}&liveness=observe` });
  expect(g2.boot.s.phase).toBe('ready');
  expect(g2.boot.s.liveness).toMatchObject({ mode: 'observe', probe: 'stood-down', sent: 0 });
  expect(g2.boot.s.stall.thresholdMs).toBe(STALL_S * 1000);
  const q1 = await g2.qstatus();
  m.frozenB = await freeze(g2);
  const v0 = (await g2.qstatus()).version;
  const last = ex.text.split('\n').length - 1;
  await g2.setCursor(last, 0);
  await g2.focusEditor();
  await g2.page.keyboard.type('-- stalled?');
  const tEdit = Date.now();
  // QED64 alone, sampled every second until the card: never a death, never ready, relay serving
  m.b = { samples: [] };
  const first = await until(async () => {
    const q = await g2.qstatus(); m.b.samples.push({ t: Date.now() - tEdit, phase: q.phase, relay: q.relay, version: q.version, lastDeath: q.lastDeath, deaths: q.stats.workerDeaths });
    return (await g2.stallCardVisible()) ? Date.now() - tEdit : null;
  }, { timeoutMs: (STALL_S + 10) * 1000, intervalMs: 1000 });
  m.b.cardAfterMs = first;
  { const sb0 = await g2.status(); m.b.cardVariant = sb0.stall.variant; m.b.cardTitle = sb0.error && sb0.error.title; }
  expect(m.b.cardVariant, 'no sign of life on a frozen checker: the card says it stopped').toBe('stopped');
  expect(m.b.cardTitle).toBe('Lean has stopped making progress');
  await g2.page.screenshot({ path: screenPath('C21-stall-card.png') });
  expect(first, 'the card appeared after the keystroke').not.toBeNull();
  const edited = m.b.samples.filter((x) => x.version > v0);
  expect(edited.length).toBeGreaterThan(STALL_S - 3);
  expect(edited.every((x) => x.relay === 'serving' && x.phase === 'elaborating' && x.lastDeath === null && x.deaths === q1.stats.workerDeaths)).toBe(true);
  // observe mode in v1: for 10 s after the card nothing moves (no probe, no wedge, no restart, QED64 sees frames)
  const quiet = []; const tq = Date.now();
  while (Date.now() - tq < 10000) { const st = await g2.status(); const q = await g2.qstatus(); quiet.push({ t: Date.now() - tq, sent: st.liveness.sent, wedged: st.liveness.wedged, restarts: st.liveness.restarts, session: q.session, phase: q.phase, qed64Stalled: st.liveness.qed64.stalled, wedgedReboots: st.liveness.qed64.wedgedReboots, card: st.stall.active }); await sleep(1000); }
  const qb = await g2.qstatus(); const sbq = await g2.status();
  m.b.observe = { probe: sbq.liveness.probe, sent: sbq.liveness.sent, wedged: sbq.liveness.wedged, restarts: sbq.liveness.restarts, wedgeEvents: sbq.liveness.events.filter((e) => e.source === 'wedged').length, session: qb.session, userRestarts: qb.stats.userRestarts - q1.stats.userRestarts, qed64: { stalled: sbq.liveness.qed64.stalled, wedgedReboots: sbq.liveness.qed64.wedgedReboots, totals: sbq.liveness.qed64.totals }, quiet: quiet.length };
  expect(m.b.observe).toMatchObject({ probe: 'stood-down', sent: 0, wedged: 0, restarts: 0, wedgeEvents: 0, session: m.frozenB, userRestarts: 0 });
  expect(m.b.observe.qed64).toMatchObject({ stalled: false, wedgedReboots: 0 });
  expect(quiet.every((x) => x.session === m.frozenB && x.phase === 'elaborating' && x.restarts === 0 && x.card), 'frozen, carded, untouched for 10 s').toBe(true);
  // the hang capture, before anything resets it (the harness runs it directly: no wedge of the gallery's own to trigger maybeCapture in v1)
  const cap = await captureHang(g2, { context: 'C21 (b) synthetic freeze (v1: the card, no gallery probe)' });
  (g2.captures ||= []).push(cap);
  const doc = JSON.parse(fs.readFileSync(path.join(SC, cap.file), 'utf8'));
  m.b.capture = { file: cap.file, log: cap.log, summary: cap.summary, telemetry: { answered: doc.steps.b_telemetry.answered, ms: doc.steps.b_telemetry.ms }, d1: { workers: doc.steps.d1_rawCheckMailbox.workers, blocked: doc.steps.d1_rawCheckMailbox.blocked, calls: doc.steps.d1_rawCheckMailbox.calls.length, skipped: doc.steps.d1_rawCheckMailbox.skipped, resumed: doc.steps.d1_rawCheckMailbox.resumed }, d2: { called: doc.steps.d2_checkMailbox.called, ms: doc.steps.d2_checkMailbox.ms, resumed: doc.steps.d2_checkMailbox.resumed, pool: doc.steps.d2_checkMailbox.pool } };
  console.log(`C21 (b, v1) capture ${JSON.stringify(m.b.capture)}`);
  expect(doc.synthetic, 'labelled synthetic').toBe(true);
  expect(doc.evidence).toMatch(/NOT L7 evidence/);
  expect(doc.steps.a_status.qed64).toMatchObject({ phase: 'elaborating', relay: 'serving', session: m.frozenB });
  expect(doc.steps.a_status.qed64.pool).toBeTruthy();
  expect(doc.steps.b_telemetry.answered, 'telemetry answered (the worker JS thread is alive, as in L7)').toBe(true);
  expect(doc.steps.c_workerConsole.lines, 'the worker / [lean:…] console lines since the session started').toBeGreaterThan(0);
  expect(fs.existsSync(path.join(SC, doc.steps.c_workerConsole.file))).toBe(true);
  expect(doc.steps.d1_rawCheckMailbox.calls.length, 'the raw __emscripten_check_mailbox() was called once per eligible worker').toBeGreaterThanOrEqual(1);
  expect(doc.steps.d1_rawCheckMailbox.calls.every((c) => !c.error && typeof c.ms === 'number')).toBe(true);
  expect(doc.steps.d1_rawCheckMailbox.mainThread.length, 'one Emscripten main-thread worker').toBe(1);
  expect(doc.steps.d1_rawCheckMailbox.resumed, 'a JS-level freeze cannot be resumed by a mailbox kick').toBe(false);
  expect(doc.steps.d2_checkMailbox).toMatchObject({ called: 'checkMailbox() once', resumed: false });
  expect(doc.steps.d2_checkMailbox.error).toBeNull();
  expect(doc.steps.d2_checkMailbox.pool).toBeTruthy();
  // capture done; the card still works: Keep waiting hides it and it comes back after another threshold
  expect(await g2.stallCardVisible(), 'the card is still up after the capture').toBe(true);
  const tKeep = Date.now();
  await g2.page.locator('#error-dismiss').click();
  const hidden = await until(async () => { const st = await g2.status(); return st && !st.stall.active && (st.error === null) ? true : null; }, { timeoutMs: 3000, intervalMs: 100 });
  const again = await until(async () => ((await g2.stallCardVisible()) ? Date.now() - tKeep : null), { timeoutMs: (STALL_S + 10) * 1000, intervalMs: 250 });
  const sb = (await g2.status()).stall;
  m.b.keepWaiting = { hidden: !!hidden, cameBackAfterMs: again, shown: sb.shown, events: sb.events.map((e) => e.source) };
  expect(m.b.keepWaiting.hidden).toBe(true);
  expect(again, 'the card came back after another threshold').not.toBeNull();
  expect(again).toBeGreaterThanOrEqual(STALL_S * 1000 - 500);
  // Reset example (the toolbar button) on the stalled checker: setDocument then api.restart() on the example
  const tReset = Date.now();
  await g2.page.locator('#reset-btn').click();
  const back = await until(async () => { const st = await g2.status(); const q = await g2.qstatus(); const tx = await g2.currentText(); return st && st.phase === 'ready' && !st.edited && tx === ex.text && q && q.phase === 'ready' && q.session !== m.frozenB ? { st, q } : null; }, { timeoutMs: 120000, intervalMs: 150 });
  m.b.reset = { ok: !!back, ms: Date.now() - tReset, session: back && back.q.session, events: back && back.st.stall.events.slice(-4) };
  expect(back, 'Reset example recovered the stalled checker').not.toBeNull();
  expect(back.st.stall.events.some((e) => e.source === 'reset' && e.how === RESTART_HOW), `the reset restarted through ${RESTART_HOW}`).toBe(true);
  expect(back.st.error).toBeNull();
  expect(back.st.liveness.restarts, 'nothing restarted by a probe').toBe(0);
  expect(back.st.liveness.sent).toBe(0);
  const first0 = gold.cursors[0];
  const p = await g2.expectPanel({ line: first0.line, character: first0.character }, first0.panels[0], { timeoutMs: 60000 });
  const d = await g2.diagnosticsOf(back.q.version);
  m.b.after = { panelEqual: p.equal, errorsWarnings: errorsWarnings(d).length };
  const q2 = await g2.qstatus();
  m.relayB = { userRestarts: q2.stats.userRestarts - q1.stats.userRestarts, workerDeaths: q2.stats.workerDeaths - q1.stats.workerDeaths, reboots: q2.stats.reboots - q1.stats.reboots };
  await g2.page.screenshot({ path: screenPath('C21-after-reset.png') });
  // the test API still switches the mode value (it sends nothing in v1)
  m.b.apiSwitch = await g2.page.evaluate(() => { const l = window.__showcase.liveness('auto'); return { mode: l.mode, probe: l.probe, sent: l.sent }; });
  console.log(`C21 (b, v1) ${JSON.stringify({ ...m.b, samples: m.b.samples.length })} relay ${JSON.stringify(m.relayB)}`);
  expect(m.b.after).toEqual({ panelEqual: true, errorsWarnings: 0 });
  expect(m.relayB).toEqual({ userRestarts: 1, workerDeaths: 0, reboots: 0 });
  expect(m.b.apiSwitch).toEqual({ mode: 'auto', probe: 'stood-down', sent: 0 });
  await sleep(200);
});

test('C22 liveness probe, negative: a legitimately slow elaboration (the slowest DistLens click; a ~38 s silent #eval; a saturated task pool) is never restarted', async ({ ux }) => {
  test.setTimeout(15 * 60 * 1000);
  const m = ux.metrics; const id = 'dist-lens'; const ex = BY_ID[id]; const gold = GOLDENS[id];
  const s = await ux.launch({ profile: 'warm' });
  const g = await Gallery.open(s, { hash: id });
  expect(g.boot.s.phase).toBe('ready');
  expect(g.boot.s.liveness).toMatchObject({ mode: 'auto', probeAfterMs: 10000, probeTimeoutMs: 5000, wedged: 0, restarts: 0 });
  expect(g.boot.s.liveness.qed64.builtIn, `pin ${PIN.id}'s page has liveness of its own`).toBe(true);
  expect(g.boot.s.liveness, 'v1: the gallery probe is stood down on capabilities.liveness').toMatchObject({ probe: 'stood-down', sent: 0, qed64: { api: true } });
  const q0 = await g.qstatus();
  // (1) the slowest DistLens declared click (by the native click-all re-elaboration time)
  const slow = gold.clicks.map((c, i) => ({ c, i, ms: c.reElaborationMs || 0 })).sort((x, y) => y.ms - x.ms)[0];
  const cur = cursorOfLine(id, slow.c.cursorLine);
  const at = { line: cur.line, character: cur.character };
  const r = await clickLink(g, ex, { kind: slow.c.kind, linkText: slow.c.linkText, title: slow.c.linkTitle || null, edit: slow.c.edit, editedSha256: slow.c.editedSha256 }, at, goldenCursor(id, at.line, at.character).panels[0], { elabTimeoutMs: 300000 });
  m.click = { index: slow.i, nativeReElabMs: slow.ms, linkText: slow.c.linkText, ok: r.ok, error: r.error || null, clickToReadyMs: r.clickToReadyMs, liveness: r.liveness, stalls: (r.stalls || []).length };
  console.log(`C22 (1) ${JSON.stringify(m.click)}`);
  expect(m.click).toMatchObject({ ok: true, stalls: 0 });
  expect(r.liveness).toMatchObject({ missed: 0, wedged: 0, restarts: 0 });
  const rs = await g.resetUI(ex);
  expect(rs.ok).toBe(true);
  // (2) a long, silent command appended to the example: one input event, so one didChange
  const SLEEP_MS = 38000;
  const lv0 = (await g.status()).liveness; const qv = await g.qstatus();
  await g.setCursor(ex.text.split('\n').length - 1, 0);
  await g.focusEditor();
  await g.page.keyboard.insertText(`\n#eval IO.sleep ${SLEEP_MS}\n`);
  const t0 = Date.now();
  const samples = [];
  const done = await until(async () => {
    const st = await g.status(); const q = await g.qstatus();
    samples.push({ t: Date.now() - t0, phase: q.phase, version: q.version, session: q.session, idleMs: st.stall.idleMs, sent: st.liveness.sent - lv0.sent, answered: st.liveness.answered - lv0.answered, card: st.stall.active });
    return q.phase === 'ready' && q.version > qv.version && Date.now() - t0 > 2000 ? { st, q } : null;
  }, { timeoutMs: SLEEP_MS + 120000, intervalMs: 500 });
  expect(done, 'the slow command finished').not.toBeNull();
  const lv = done.st.liveness;
  // v1: QED64's frame clock read right after the verdict (done.st was read just BEFORE the ready qstatus of the same poll)
  const frameAgoAfterReady = (await g.status()).liveness.qed64.lastFrameAgoMs;
  const d = await g.diagnosticsOf(done.q.version);
  const q1 = await g.qstatus();
  m.eval = {
    sleepMs: SLEEP_MS, editToReadyMs: Date.now() - t0, maxIdleMs: Math.max(...samples.map((x) => x.idleMs)),
    probes: lv.sent - lv0.sent, answered: lv.answered - lv0.answered, missed: lv.missed - lv0.missed, wedged: lv.wedged - lv0.wedged, restarts: lv.restarts - lv0.restarts, lastAnswerMs: lv.lastAnswerMs, maxAnswerMs: lv.maxAnswerMs,
    answers: lv.events.filter((e) => e.source === 'answered').slice(-8).map((e) => e.ms),
    // QED64's own liveness during the same silence (its probe after 6 s without a frame, answered by the busy FileWorker)
    qed64: Object.fromEntries(TOTAL_KEYS.map((k) => [k, lv.qed64.totals[k] - lv0.qed64.totals[k]])), qed64WedgedReboots: lv.qed64.wedgedReboots - lv0.qed64.wedgedReboots,
    // v1: QED64's liveness as the API projects it at the end (status().liveness.qed64 mirrors api.status().liveness)
    qed64Live: { probe: lv.probe, stalled: lv.qed64.stalled, lastFrameAgoMs: lv.qed64.lastFrameAgoMs, lastAnswerAgoMs: lv.qed64.lastAnswerAgoMs, probeAfterMs: lv.qed64.probeAfterMs, wedgeAfterMs: lv.qed64.wedgeAfterMs, graceMs: lv.qed64.graceMs, totalsAnswered: lv.qed64.totals.answered, frameAgoAfterReady },
    cardShown: done.st.stall.shown, sessionSame: q1.session === q0.session, userRestarts: q1.stats.userRestarts - q0.stats.userRestarts, workerDeaths: q1.stats.workerDeaths - q0.stats.workerDeaths,
    errorsWarnings: errorsWarnings(d).length,
  };
  m.evalSamples = samples.filter((x, i) => i % 4 === 0);
  console.log(`C22 (2) ${JSON.stringify(m.eval)}`);
  expect(m.eval.editToReadyMs, 'it really was slow').toBeGreaterThanOrEqual(SLEEP_MS);
  {
    // v1: no probe of the gallery's own ran (stood down), nothing restarted, nothing rebooted; QED64's liveness, read through
    // the API, saw frames (the editor's and InfoView's requests keep flowing during a silent #eval) and reports numbers:
    // lastFrameAgoMs since its last Lean frame; lastAnswerAgoMs since its last answered probe (null until it probed once,
    // which a silent #eval in a gallery session normally never makes it do) and not stalled at the end
    expect(m.eval.probes, 'the gallery probe is stood down: nothing sent').toBe(0);
    expect(m.eval.qed64Live.probe).toBe('stood-down');
    expect(typeof m.eval.qed64Live.lastFrameAgoMs, 'api.status().liveness.lastFrameAgoMs is a number').toBe('number');
    expect(m.eval.qed64Live.frameAgoAfterReady, 'the ready verdict was a Lean frame: QED64 saw one within 5 s of ready').toBeLessThan(5000);
    if (m.eval.qed64Live.totalsAnswered > 0) expect(typeof m.eval.qed64Live.lastAnswerAgoMs, 'answered once: lastAnswerAgoMs is a number').toBe('number');
    expect(m.eval.qed64Live).toMatchObject({ stalled: false, probeAfterMs: 6000, wedgeAfterMs: 12000, graceMs: 4000 });
    expect(m.eval.qed64.stalls, 'no QED64 stall').toBe(0);
    expect(m.eval.qed64WedgedReboots, 'QED64 rebooted nothing').toBe(0);
    expect(m.eval).toMatchObject({ answered: 0, missed: 0, wedged: 0, restarts: 0, cardShown: 0, sessionSame: true, userRestarts: 0, workerDeaths: 0, errorsWarnings: 0 });
  }

  // (3) a saturated task pool: 24 parallel sleeping proofs (see the header). Same session, no reload: one edit.
  const rs3 = await g.resetUI(ex);
  expect(rs3.ok).toBe(true);
  const SAT_N = 24; const SAT_MS = 55000;
  // the sleeping proofs run in waves of the task manager's standard workers: J (n = 14) took 2 waves (111 s), a pin with
  // QED64's thread budget (#69: min(cores, 8)) takes 3 (K: 166 s)
  const SAT_WAVES = 3;
  const lv3 = (await g.status()).liveness; const q3 = await g.qstatus(); const st3 = (await g.status()).stall;
  const via3 = { ...lv3.aliveVia }; const ml3 = { ...lv3.mainLoop };
  // (Mathlib's unusedTactic linter warns that `sleep` "does nothing"; a user silencing it is part of the scenario)
  const sat = ['set_option Elab.async true', ...Array.from({ length: SAT_N }, (_, i) => `set_option linter.unusedTactic false in\ntheorem showcaseSat${i} : True := by sleep ${SAT_MS}; trivial`)].join('\n');
  await g.setCursor(ex.text.split('\n').length - 1, 0);
  await g.focusEditor();
  await g.page.keyboard.insertText(`\n${sat}\n`);
  const t3 = Date.now();
  const s3 = []; let shot = false;
  const done3 = await until(async () => {
    const st = await g.status(); const q = await g.qstatus();
    if (st.stall.active && !shot) { shot = true; await g.page.screenshot({ path: screenPath('C22-still-working-card.png') }).catch(() => {}); }
    s3.push({ t: Date.now() - t3, phase: q.phase, version: q.version, session: q.session, pool: q.pool || null, idleMs: st.stall.idleMs, sent: st.liveness.sent - lv3.sent, answered: st.liveness.answered - lv3.answered, alive: st.liveness.alive - lv3.alive, card: st.stall.active, variant: st.stall.variant, title: st.error && st.error.kind === 'stalled' ? st.error.title : null, qed64Answered: st.liveness.qed64.totals.answered - lv3.qed64.totals.answered });
    return q.phase === 'ready' && q.version > q3.version && Date.now() - t3 > 2000 ? { st, q } : null;
  }, { timeoutMs: SAT_WAVES * SAT_MS + 180000, intervalMs: 500 });
  expect(done3, 'the saturated elaboration finished').not.toBeNull();
  const lvS = done3.st.liveness; const frameAgoAfterReady3 = (await g.status()).liveness.qed64.lastFrameAgoMs; const d3 = await g.diagnosticsOf(done3.q.version); const q4 = await g.qstatus();
  const cards = s3.filter((x) => x.card);
  m.saturated = {
    theorems: SAT_N, sleepMs: SAT_MS, elabAsync: 'opt-in', editToReadyMs: Date.now() - t3, maxIdleMs: Math.max(...s3.map((x) => x.idleMs)),
    poolSaturated: s3.some((x) => x.pool && x.pool.unused === 0), poolMax: s3.reduce((a, x) => (x.pool ? { running: Math.max(a.running, x.pool.running || 0), unusedMin: Math.min(a.unusedMin, x.pool.unused) } : a), { running: 0, unusedMin: Infinity }),
    probes: lvS.sent - lv3.sent, answered: lvS.answered - lv3.answered, alive: lvS.alive - lv3.alive, aliveVia: Object.fromEntries(Object.keys(lvS.aliveVia).map((k) => [k, lvS.aliveVia[k] - (via3[k] || 0)])), missed: lvS.missed - lv3.missed, wedged: lvS.wedged - lv3.wedged, restarts: lvS.restarts - lv3.restarts,
    // the gallery's main-loop probe over (3): sent with every hover, answered by the FileWorker main loop (MethodNotFound)
    mainLoop: { sent: lvS.mainLoop.sent - ml3.sent, answered: lvS.mainLoop.answered - ml3.answered, synthetic: lvS.mainLoop.synthetic - ml3.synthetic, lastMs: lvS.mainLoop.lastMs, maxMs: lvS.mainLoop.maxMs },
    events: lvS.events.filter((e) => ['probe', 'answered', 'alive', 'missed', 'wedged', 'late', 'main-answered'].includes(e.source)).slice(-16).map((e) => `${e.source}${e.via ? `:${e.via}` : ''}${e.ms !== undefined && e.ms !== null ? `:${e.ms}ms` : ''}`),
    qed64: Object.fromEntries(TOTAL_KEYS.map((k) => [k, lvS.qed64.totals[k] - lv3.qed64.totals[k]])), qed64WedgedReboots: lvS.qed64.wedgedReboots - lv3.qed64.wedgedReboots,
    qed64Live: { probe: lvS.probe, stalled: lvS.qed64.stalled, lastFrameAgoMs: lvS.qed64.lastFrameAgoMs, lastAnswerAgoMs: lvS.qed64.lastAnswerAgoMs, totalsAnswered: lvS.qed64.totals.answered, frameAgoAfterReady: frameAgoAfterReady3 },
    cardShown: done3.st.stall.shown - st3.shown, cardVariants: [...new Set(cards.map((x) => x.variant))], cardTitles: [...new Set(cards.map((x) => x.title))],
    sessionSame: q4.session === q0.session, userRestarts: q4.stats.userRestarts - q0.stats.userRestarts, workerDeaths: q4.stats.workerDeaths - q0.stats.workerDeaths, errorsWarnings: errorsWarnings(d3).length, diagnostics: errorsWarnings(d3).slice(0, 3).map((x) => `${x.line}:${x.character} sev ${x.sev} ${String(x.msg).slice(0, 160)}`),
  };
  m.saturatedSamples = s3.filter((x, i) => i % 6 === 0);
  console.log(`C22 (3) ${JSON.stringify(m.saturated)}`);
  // the premise: every Lean task thread was busy, so proofs queued for one. All 24 at once would take one SAT_MS; a queue
  // takes at least two waves. (Up to J the 24-thread pthread pool also ran out, `unused` 0; with QED64 #69's task budget,
  // n = 8 standard workers, it no longer does (k-dl3: running 21, unused 3 at least), so `poolSaturated` is data only.)
  expect(m.saturated.editToReadyMs, 'every Lean task thread was busy: the proofs queued (at least 2 waves of SAT_MS): the premise of this case').toBeGreaterThanOrEqual(2 * SAT_MS);
  {
    // v1: no probe of the gallery's own (hover or main-loop) went out; QED64's own liveness (its probe is answered by the
    // FileWorker main loop without a pool thread) saw no stall and rebooted nothing, and is not stalled at the end
    expect(m.saturated.probes, 'the gallery probe is stood down: nothing sent').toBe(0);
    expect(m.saturated.mainLoop.sent, 'no main-loop probe either').toBe(0);
    expect(m.saturated).toMatchObject({ answered: 0, missed: 0 });
    expect(m.saturated.qed64Live).toMatchObject({ probe: 'stood-down', stalled: false });
    expect(typeof m.saturated.qed64Live.lastFrameAgoMs).toBe('number');
    expect(m.saturated.qed64Live.frameAgoAfterReady, 'the ready verdict was a Lean frame: QED64 saw one within 5 s of ready').toBeLessThan(5000);
    if (m.saturated.qed64Live.totalsAnswered > 0) expect(typeof m.saturated.qed64Live.lastAnswerAgoMs, 'QED64 probed and was answered: lastAnswerAgoMs is a number').toBe('number');
    expect(m.saturated.qed64.stalls, 'QED64 saw no stall (its own probe was answered)').toBe(0);
    expect(m.saturated.qed64WedgedReboots).toBe(0);
  }
  expect(m.saturated, 'not restarted: same session, the work kept').toMatchObject({ wedged: 0, restarts: 0, sessionSame: true, userRestarts: 0, workerDeaths: 0, errorsWarnings: 0 });
  // a 45 s card during this healthy (but silent) elaboration says so
  for (const v of m.saturated.cardVariants) expect(v, 'a card shown while Lean answers is worded "still working"').toBe('alive');
  for (const t of m.saturated.cardTitles) expect(t).toBe('Lean is still working');
  await sleep(200);
});

// C23 (close-out 3, audit minor): the post-hoc record of an L7 occurrence that QED64 handles ITSELF, exercised in the
// browser (every kept pin's page has QED64's own liveness, pins/<id>/pin.json liveness.builtIn). On
// such a pin QED64's worker serves the runtime mailbox every 1 s and its Lean-side liveness kills a
// wedged session (died "wedged") about 22-25 s after its last server frame; the relay reboots it and replays the text.
// No real L7 has reached that path in 15+ C20 runs, so this FIXTURE forces it: inside QED64's own lean.worker.js (the
// Emscripten main-thread worker, classic script, so its top-level functions are worker globals) it runs exactly what the
// worker's livenessStep runs when its detector decides "dead" — livenessLog(...) then die(null, "wedged", ...) — as soon
// as a declared click's edit is in the document (its elaboration in flight; clickLink's afterEdit hook). Until pin K it
// ran 0.8 s after arming; on pin L (runtime 5650321f) the click was ready in 668 ms, before the death (l-full1). Everything downstream is QED64's and the suite's real code: the relay's onDied ->
// failInFlight -> reboot('wedged') and replay, the gallery's observeQed64 (status().liveness.qed64, the qed64-wedged /
// qed64-rebooted events, the notice), and the harness's clickLink -> captureQed64Reboot (tests/ux/lib/actions.mjs), the
// very path C20 and W1-W8 take on a real QED64-handled hang. The record is labelled SYNTHETIC (window.__uxFixture): it
// proves the capture path, never anything about L7. A fresh browser, so the reboot is this renderer's only second boot.
test('C23 QED64-handled wedged reboot (fixture): the gallery reports it, the text re-checks on the new session, and the harness writes the post-hoc record', async ({ ux }) => {
  test.setTimeout(10 * 60 * 1000);
  const m = ux.metrics; const id = 'hasse-view'; const ex = BY_ID[id]; const gold = GOLDENS[id];
  // QED64's reboot answers the requests in flight with 'QED64: the Lean checker died (wedged)'; the InfoView's old RPC
  // session may be refused once per request
  ux.scenarios.push('qed64WedgedReboot', 'relayRestartOrReboot');
  const s = await ux.launch({ profile: 'warm', label: 'c23-qed64-wedged' });
  const g = await Gallery.open(s, { hash: id });
  expect(g.boot.s.phase).toBe('ready');
  expect(g.boot.s.liveness.qed64.builtIn, `pin ${PIN.id}'s page has liveness of its own`).toBe(true);
  const q0 = await g.qstatus(); const lv0 = (await g.status()).liveness;
  // QED64's runtime worker: the one worker that defines its liveness and death functions
  const findWorker = async () => {
    for (const w of g.page.workers()) {
      const ok = await Promise.race([w.evaluate(() => typeof die === 'function' && typeof livenessLog === 'function' && typeof startLiveness === 'function' && typeof ENVIRONMENT_IS_PTHREAD !== 'undefined' && !ENVIRONMENT_IS_PTHREAD).catch(() => false), sleep(3000).then(() => false)]);
      if (ok) return w;
    }
    return null;
  };
  const rw = await findWorker();
  expect(rw, 'QED64\'s runtime worker (lean.worker.js main thread) found').not.toBeNull();
  m.worker = rw.url().replace(/^https?:\/\/[^/]+/, '');
  const FIXTURE = 'C23 synthetic QED64 wedged death (die(null, "wedged") called in lean.worker.js)';
  const gc = gold.clicks[0];
  const cur = cursorOfLine(id, gc.cursorLine);
  const at = { line: cur.line, character: cur.character };
  const r = await clickLink(g, ex, { kind: gc.kind, linkText: gc.linkText, title: gc.linkTitle || null, edit: gc.edit, editedSha256: gc.editedSha256 }, at, goldenCursor(id, at.line, at.character).panels[0], {
    elabTimeoutMs: 180000,
    beforeClick: async () => {
      await g.q((f) => { window.__uxFixture = { at: Date.now(), fixture: f }; }, FIXTURE);
      return rw.evaluate(() => ({ armed: typeof die === 'function' && typeof livenessLog === 'function', died: typeof died === 'boolean' ? died : null }));
    },
    afterEdit: () => rw.evaluate((f) => {
      livenessLog(`[fixture] ${f}: the Lean side stopped (forced by the test; not a real stall)`);
      die(null, 'wedged', `the Lean runtime stopped answering (${f})`);
      return { fired: true, died: typeof died === 'boolean' ? died : null };
    }, FIXTURE),
  });
  const sa = await g.status(); const qa = await g.qstatus(); const lv = sa.liveness;
  const cap = (r.captures || []).find((c) => /-qed64-wedged\.json$/.test(c.file));
  m.click = { ok: r.ok, error: r.error || null, editExact: r.editExact, nativeSha: r.nativeSha, errors: r.errors, warnings: r.warnings, clickToReadyMs: r.clickToReadyMs, beforeClick: r.beforeClick, afterEdit: r.afterEdit || null, qed64WedgedReboots: r.qed64WedgedReboots || 0, lastReboot: r.qed64LastReboot || null, captures: (r.captures || []).map((c) => c.file), stalls: (r.stalls || []).length };
  m.gallery = { wedgedReboots: lv.qed64.wedgedReboots - lv0.qed64.wedgedReboots, events: lv.events.filter((e) => String(e.source).startsWith('qed64-')).map((e) => e.source), notice: sa.notice, galleryWedged: lv.wedged - lv0.wedged, galleryRestarts: lv.restarts - lv0.restarts, cardShown: sa.stall.shown };
  m.relay = { sessionBefore: q0.session, sessionAfter: qa.session, workerDeaths: qa.stats.workerDeaths - q0.stats.workerDeaths, reboots: qa.stats.reboots - q0.stats.reboots, userRestarts: qa.stats.userRestarts - q0.stats.userRestarts, lastDeath: qa.lastDeath };
  console.log(`C23 ${JSON.stringify({ click: m.click, gallery: m.gallery, relay: m.relay })}`);
  await g.page.screenshot({ path: screenPath('C23-after-qed64-reboot.png') });
  expect(m.click.beforeClick).toMatchObject({ armed: true, died: false });
  // the gallery saw QED64's own reboot (relay 'rebooting', rebootReason 'wedged') and did not act itself
  expect(m.gallery.wedgedReboots, 'the gallery counted exactly one QED64 "wedged" reboot').toBe(1);
  {
    // v1: the death and the reboot reach the gallery as the API's `death` and `reboot` events (EMBEDDING.md §2.4): recorded as
    // a 'qed64-death' event, counted in wedgedReboots (reboot reason 'wedged') with lastReboot {from, to}
    m.gallery.deathEvents = lv.events.filter((e) => e.source === 'qed64-death').length;
    expect(m.gallery.events).toEqual(expect.arrayContaining(['qed64-death', 'qed64-reboot', 'qed64-wedged']));
    expect(m.gallery.deathEvents, 'exactly one death recorded from the API').toBe(1);
    // the death's identity: the fixture's own wedged death on the session before, with its reboot announced (§2.4 death payload)
    const death = lv.events.find((e) => e.source === 'qed64-death');
    m.gallery.death = death;
    expect(death, 'the recorded death is the fixture\'s wedged death').toMatchObject({ kind: 'wedged', reason: 'wedged', session: m.relay.sessionBefore, willReboot: true });
    expect(death.message).toContain(FIXTURE);
    expect(m.click.lastReboot && m.click.lastReboot.lastDeath, 'lastReboot carries the death (api.status() read in the reboot handler)').toMatchObject({ reason: 'wedged' });
    expect(lv.probe, 'the gallery probe stood down throughout').toBe('stood-down');
    expect(lv.sent).toBe(0);
  }
  expect(m.gallery, 'the gallery restarted nothing and showed no card').toMatchObject({ galleryWedged: 0, galleryRestarts: 0, cardShown: 0 });
  // the relay: exactly one death and one reboot, no user restart, a new session. QED64 clears status().lastDeath once
  // the new session serves (measured here: null after ready), so the reason is read from the gallery's reboot record,
  // sampled while the relay was 'rebooting'
  expect(m.relay).toMatchObject({ workerDeaths: 1, reboots: 1, userRestarts: 0 });
  expect(m.relay.sessionAfter).not.toBe(m.relay.sessionBefore);
  expect(m.click.lastReboot, 'lastReboot {from, to} from the API\'s reboot event').toMatchObject({ from: m.relay.sessionBefore, to: m.relay.sessionAfter });
  // the post-click text re-checked clean on the new session, as C20 requires of a QED64-handled hang
  expect(m.click, 'the click re-checked clean after QED64\'s reboot').toMatchObject({ ok: true, editExact: true, nativeSha: true, errors: 0, warnings: 0, stalls: 0, qed64WedgedReboots: 1 });
  // the harness's post-hoc record (clickLink -> captureQed64Reboot), labelled synthetic
  expect(cap, 'clickLink wrote the post-hoc qed64-wedged record').toBeTruthy();
  const doc = JSON.parse(fs.readFileSync(path.join(SC, cap.file), 'utf8'));
  m.record = { file: cap.file, log: cap.log, summary: doc.summary, livenessLines: doc.workerConsole.liveness, lastDeath: doc.qed64 && doc.qed64.lastDeath, lastReboot: doc.qed64Liveness && doc.qed64Liveness.qed64.lastReboot };
  console.log(`C23 record ${JSON.stringify(m.record)}`);
  expect(doc).toMatchObject({ schema: 'qed64-showcase.qed64-reboot-capture/v1', postHoc: true, synthetic: true });
  expect(doc.evidence).toMatch(/NOT L7 evidence/);
  expect(doc.frozenFixture.fixture).toBe(FIXTURE);
  expect(doc.summary).toMatchObject({ postHoc: true, synthetic: true, wedgedReboots: 1 });
  {
    expect(doc.qed64Liveness.events.map((e) => e.source)).toEqual(expect.arrayContaining(['qed64-death', 'qed64-wedged']));
    const recDeath = doc.qed64Liveness.events.find((e) => e.source === 'qed64-death');
    expect(recDeath, 'the post-hoc record carries the fixture\'s death').toMatchObject({ kind: 'wedged', reason: 'wedged', session: m.relay.sessionBefore });
    expect(recDeath.message).toContain(FIXTURE);
    expect(doc.qed64Liveness.qed64.lastReboot, 'the reboot record (from the API\'s reboot event)').toMatchObject({ from: m.relay.sessionBefore, to: m.relay.sessionAfter });
  }
  expect(doc.qed64.session, 'the record was taken on the rebooted session').toBe(m.relay.sessionAfter);
  expect(doc.workerConsole.liveness.some((l) => /\[liveness\] \[fixture\]/.test(l)), 'the worker\'s [liveness] line is in the record').toBe(true);
  expect(fs.existsSync(path.join(SC, doc.workerConsole.file))).toBe(true);
  const rs = await g.resetUI(ex);
  expect(rs.ok, 'Reset after the reboot').toBe(true);
  await sleep(200);
});
