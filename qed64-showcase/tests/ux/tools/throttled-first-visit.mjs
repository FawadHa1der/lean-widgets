// A first visit to /showcase/ over a throttled link (last-mile lane, 2026-10-03). Fresh profile (new context: empty HTTP
// cache and OPFS), chrome-headless-shell (the UX suite's browser) unless --channel/--headed, and CDP network emulation
// (Network.emulateNetworkConditions: --mbps down/up, --rtt ms) applied to EVERY target of the browser before it runs:
// a raw CDP client on --remote-debugging-port auto-attaches (flatten, waitForDebuggerOnStart) to the page, every
// dedicated worker (QED64's lean worker fetches the runtime and the snapshots) and every nested pthread worker, sets the
// conditions in that target's own session, then resumes it. Playwright's own sessions are untouched.
//
// What it records (out/ux/$UX_RUN/explore/throttle-<tag>.json, screenshots in out/ux/$UX_RUN/screens/):
//   * time to the gallery's ready (and QED64's phases), from page.goto;
//   * every --sample-ms: what the visitor sees: the gallery veil (#stage-veil) and its text, QED64's own boot card in the
//     iframe (#boot / #bootlabel / #bootnums / #bootfill width), the gallery status line, the error card (#error-card);
//     "progress visible" = the veil is shown with text OR the iframe and QED64's boot card are shown with a label, until
//     the gallery is ready; the longest stretch without any change of the visible progress text/bar is reported too;
//   * a screenshot every --shot-s seconds and at ready / error;
//   * per-request timing of the big downloads from the CDP Network events of each session (bytes, ms, achieved Mbit/s), so
//     the run itself shows the throttle took effect in the page and in the workers (not assumed);
//   * the console oracle of the harness (selectors.json allowlist) for the session.
// Run it under the host browser lock:
//   UX_RUN=<run> scripts/with-browser-lock.sh <lane> node tests/ux/tools/throttled-first-visit.mjs --origin http://localhost:5191 --mbps 50 --rtt 40 --tag t50
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { Session, Gallery, BY_ID, LAUNCH_ARGS, RUN_DIR, SCREENS, lockHeld, cooldown, chromeRss, sleep } from '../lib/qed64.mjs';
import { goldenCursor } from '../lib/actions.mjs';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const ORIGIN = arg('--origin', 'http://localhost:5191');
const TAG = arg('--tag', 'run');
const MBPS = Number(arg('--mbps', '50'));
const UP_MBPS = Number(arg('--up-mbps', String(MBPS)));
const RTT = Number(arg('--rtt', '40'));
const SAMPLE_MS = Number(arg('--sample-ms', '1000'));
const SHOT_S = Number(arg('--shot-s', '10'));
const MAX_S = Number(arg('--max-s', '900'));
const AFTER_READY_S = Number(arg('--after-ready-s', '10'));
const CDP_PORT = Number(arg('--cdp-port', '9340'));
const CHANNEL = arg('--channel', undefined);
const HEADED = process.argv.includes('--headed');
const PATH = arg('--path', '/showcase/');
// after ready: the InfoView panel at the shown example's first cursor must equal its golden (boot-fix lane, 2026-10-03);
// --no-panel skips it
const PANEL = !process.argv.includes('--no-panel');
// Exit code (final audit, 2026-10-03: the tool used to exit 0 whatever happened): 0 = PASS, 1 = FAIL (the RESULT line says
// why). PASS = ready reached, no renderer crash, console oracle ok, no error card at the end, the panel EQUAL to its golden
// (unless --no-panel), visible progress in every sample before ready except the first --grace-s seconds (the page has not
// painted yet; default 5), and no error card at all unless --expect-card (a deliberate stall test, e.g. ?bootStall=3).
const EXPECT_CARD = process.argv.includes('--expect-card');
const GRACE_MS = Number(arg('--grace-s', '5')) * 1000;
const BPS = (MBPS * 1e6) / 8; const UP_BPS = (UP_MBPS * 1e6) / 8;
// --no-cdp: the link is shaped OUTSIDE the browser (tests/ux/tools/throttle-proxy.mjs in front of --origin); CDP is then
// used only to time the requests (CDP emulation does not reach QED64's dedicated-worker downloads, see throttle-proxy.mjs)
const NO_CDP = process.argv.includes('--no-cdp');
const out = { tag: TAG, url: `${ORIGIN}${PATH}`, link: { downMbps: MBPS, upMbps: UP_MBPS, rttMs: RTT, downloadThroughputBytesPerS: BPS, latencyMs: RTT }, shaping: NO_CDP ? 'proxy (link shaped outside the browser; --mbps/--rtt are the proxy settings)' : 'CDP Network.emulateNetworkConditions per target', startedAt: new Date().toISOString(), browser: HEADED ? 'headed' : (CHANNEL || 'chrome-headless-shell') };
fs.mkdirSync(path.join(RUN_DIR, 'explore'), { recursive: true }); fs.mkdirSync(SCREENS, { recursive: true }); fs.mkdirSync(path.join(RUN_DIR, 'tests'), { recursive: true });
const shot = (n) => path.join(SCREENS, `throttle-${TAG}-${n}.png`);

lockHeld(); out.cooldown = await cooldown();
const browser = await chromium.launch({ args: [...LAUNCH_ARGS, `--remote-debugging-port=${CDP_PORT}`], headless: !HEADED, channel: CHANNEL });
out.browserVersion = browser.version();
const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, colorScheme: 'light', deviceScaleFactor: 1 });
const t0 = Date.now();
const s = new Session({ testInfo: { title: `throttle-${TAG}`, file: 'tools/throttled-first-visit.mjs' }, browser, context, t0, label: `throttle-${TAG}`, profile: 'fresh', cool: out.cooldown });
await s.init();

// ---------------------------------------------------------------- raw CDP: throttle every target before it runs
const ver = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json/version`)).json();
const ws = new WebSocket(ver.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
let nextId = 0; const pending = new Map(); const sessions = new Map(); const reqs = new Map(); const done = []; const attachErrors = [];
const send = (method, params = {}, sessionId) => new Promise((res, rej) => { const id = ++nextId; pending.set(id, { res, rej, method }); ws.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) })); });
const conditions = { offline: false, latency: RTT, downloadThroughput: BPS, uploadThroughput: UP_BPS };
async function onAttached({ sessionId, targetInfo, waitingForDebugger }, parent) {
  const rec = { type: targetInfo.type, url: targetInfo.url.replace(/^https?:\/\/localhost:\d+/, '').slice(0, 80), parent: parent ? (sessions.get(parent) || {}).type : 'browser', t: Date.now() - t0, throttled: false, errors: [] };
  sessions.set(sessionId, rec);
  const tryS = async (m, p) => { try { return await send(m, p, sessionId); } catch (e) { rec.errors.push(`${m}: ${e.message}`); return null; } };
  if (['page', 'iframe', 'worker', 'shared_worker', 'service_worker'].includes(targetInfo.type)) {
    await tryS('Network.enable', { maxTotalBufferSize: 1048576, maxResourceBufferSize: 1024 });
    rec.throttled = NO_CDP ? 'proxy' : (await tryS('Network.emulateNetworkConditions', conditions)) !== null;
    await tryS('Target.setAutoAttach', { autoAttach: true, waitForDebuggerOnStart: true, flatten: true });
  }
  if (waitingForDebugger) await tryS('Runtime.runIfWaitingForDebugger', {});
  rec.waited = !!waitingForDebugger;
}
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { const p = pending.get(m.id); pending.delete(m.id); if (m.error) p.rej(new Error(m.error.message)); else p.res(m.result); return; }
  if (m.method === 'Target.attachedToTarget') { onAttached(m.params, m.sessionId).catch((e) => attachErrors.push(String(e.message))); return; }
  const st = sessions.get(m.sessionId); const key = `${m.sessionId}|${m.params && m.params.requestId}`;
  if (m.method === 'Network.requestWillBeSent') reqs.set(key, { url: m.params.request.url.replace(/^https?:\/\/localhost:\d+/, ''), target: st ? st.type : '?', ts: m.params.timestamp, wall: Date.now() - t0 });
  else if (m.method === 'Network.responseReceived') { const r = reqs.get(key); if (r) { r.tsResp = m.params.timestamp; r.status = m.params.response.status; r.fromDiskCache = !!m.params.response.fromDiskCache; } }
  else if (m.method === 'Network.loadingFinished') { const r = reqs.get(key); if (r) { r.tsEnd = m.params.timestamp; r.bytes = m.params.encodedDataLength; r.wallEnd = Date.now() - t0; done.push(r); reqs.delete(key); } }
  else if (m.method === 'Network.loadingFailed') { const r = reqs.get(key); if (r) { r.failed = m.params.errorText; r.wallEnd = Date.now() - t0; done.push(r); reqs.delete(key); } }
};
await send('Target.setAutoAttach', { autoAttach: true, waitForDebuggerOnStart: true, flatten: true });

// ---------------------------------------------------------------- the visit
const page = await s.newPage();
await sleep(300); // the page target is attached and throttled (checked below) before it navigates
out.throttledBeforeNav = [...sessions.values()].filter((x) => x.type === 'page').map((x) => ({ throttled: x.throttled, errors: x.errors }));
let crashed = null; page.on('crash', () => { crashed = Date.now() - t0; });
const look = () => page.evaluate(() => {
  const vis = (el, win = window) => { if (!el) return false; const cs = win.getComputedStyle(el); const r = el.getBoundingClientRect(); return !el.hidden && cs.display !== 'none' && cs.visibility !== 'hidden' && Number(cs.opacity) > 0.05 && r.width > 0 && r.height > 0; };
  const txt = (el) => (el ? el.textContent.replace(/\s+/g, ' ').trim() : null);
  const g = window.__showcase && window.__showcase.status();
  const veil = document.getElementById('stage-veil'); const err = document.getElementById('error-card'); const fr = document.getElementById('qed64-frame');
  let boot = null;
  try {
    const d = fr && fr.contentDocument; const w = fr && fr.contentWindow;
    const b = d && d.getElementById('boot');
    if (b) boot = { visible: vis(b, w), card: vis(d.getElementById('bootcard'), w), cls: d.getElementById('bootcard') ? d.getElementById('bootcard').className : null, label: txt(d.getElementById('bootlabel')), nums: txt(d.getElementById('bootnums')), stat: txt(d.getElementById('bootstat')), fill: d.getElementById('bootfill') ? d.getElementById('bootfill').style.width : null };
  } catch (e) { boot = { error: String(e.message) }; }
  return { phase: g ? g.phase : null, qphase: g && g.qed64 ? g.qed64.phase : null, relay: g && g.qed64 ? g.qed64.relay : null, op: g ? g.op : null, status: txt(document.getElementById('status-text')),
    veil: { visible: vis(veil) && !veil.classList.contains('is-hidden'), text: txt(document.getElementById('veil-text')) },
    frameVisible: vis(fr), error: vis(err) ? { title: txt(document.getElementById('error-title')), detail: txt(document.getElementById('error-detail')), kind: g && g.error ? g.error.kind : null } : null, boot,
    // the gallery's own notice bar (the slow-download notice of the boot-fix lane) and what its boot wait saw
    notice: vis(document.getElementById('notice')) ? txt(document.getElementById('notice-text')) : null,
    gboot: g && g.boot ? { bytes: g.boot.bytes, idleMs: g.boot.idleMs, noticeShown: g.boot.noticeShown, stalls: g.boot.stalls, recovered: g.boot.recovered, uiWrapped: g.boot.uiWrapped, overlay: g.boot.pageBootOverlay, sources: g.boot.sources } : null };
}).catch((e) => ({ evalError: String(e.message).slice(0, 120) }));

const samples = []; const shots = []; let nextShot = 0; let readyAt = null; let firstErrorAt = null; let firstErrorShot = false;
const navT = Date.now();
await page.goto(out.url, { waitUntil: 'commit' });
for (;;) {
  const t = Date.now() - navT;
  const v = await look();
  const progress = !!(v.veil && v.veil.visible && v.veil.text) || !!(v.frameVisible && v.boot && v.boot.visible && v.boot.card && v.boot.label) || !!v.notice;
  samples.push({ t, rssGiB: chromeRss().rendererGiB, progress, ...v });
  if (v.error && firstErrorAt === null) firstErrorAt = t;
  if (t >= nextShot * 1000 || (v.error && !firstErrorShot) || (v.phase === 'ready' && readyAt === null)) {
    const n = v.phase === 'ready' && readyAt === null ? `ready-${Math.round(t / 1000)}s` : v.error && !firstErrorShot ? `error-${Math.round(t / 1000)}s` : `${String(Math.round(t / 1000)).padStart(4, '0')}s`;
    try { await page.screenshot({ path: shot(n) }); shots.push({ t, file: path.relative(RUN_DIR, shot(n)), phase: v.phase, label: v.boot && v.boot.label, nums: v.boot && v.boot.nums, veil: v.veil && v.veil.visible ? v.veil.text : null, error: v.error ? v.error.title : null }); } catch { /* ignore */ }
    if (v.error) firstErrorShot = true;
    while (nextShot * 1000 <= t) nextShot += SHOT_S;
  }
  if (v.phase === 'ready' && readyAt === null) { readyAt = t; console.log(`[${TAG}] gallery ready at ${(t / 1000).toFixed(1)} s`); }
  if (crashed !== null) break;
  if (readyAt !== null && t - readyAt >= AFTER_READY_S * 1000) break;
  if (t > MAX_S * 1000) break;
  if (samples.length % 15 === 0) console.log(`[${TAG}] ${(t / 1000).toFixed(0)} s: gallery ${v.phase} qed64 ${v.qphase} | veil ${v.veil && v.veil.visible ? `"${v.veil.text}"` : 'hidden'} | boot ${v.boot ? `${v.boot.visible ? 'shown' : 'hidden'} "${v.boot.label}" ${v.boot.nums || ''} ${v.boot.fill || ''}` : 'none'}${v.error ? ` | ERROR CARD "${v.error.title}"` : ''}`);
  await sleep(Math.max(0, SAMPLE_MS - ((Date.now() - navT) - t)));
}
out.readyMs = readyAt; out.crashedAtMs = crashed; out.firstErrorCardMs = firstErrorAt;
const pre = samples.filter((x) => readyAt === null || x.t < readyAt);
out.progress = {
  samplesBeforeReady: pre.length,
  withoutVisibleProgress: pre.filter((x) => !x.progress).map((x) => ({ t: x.t, phase: x.phase, veil: x.veil, frameVisible: x.frameVisible, boot: x.boot, evalError: x.evalError })),
  withErrorCard: samples.filter((x) => x.error).length,
  errorCards: [...new Map(samples.filter((x) => x.error).reverse().map((x) => [x.error.title, { firstT: x.t, ...x.error }])).values()], // reversed: Map keeps the last write, i.e. the FIRST sample
};
// the longest stretch (before ready) in which nothing the visitor sees as progress changed (label, numbers, bar, veil text)
let last = null; let lastT = 0; let longest = { ms: 0, from: 0, to: 0, what: null };
for (const x of pre) {
  const sig = JSON.stringify([x.veil && x.veil.visible ? x.veil.text : null, x.boot && x.boot.visible ? [x.boot.label, x.boot.nums, x.boot.fill, x.boot.stat] : null, x.notice || null, x.phase, x.qphase]);
  if (sig !== last) { last = sig; lastT = x.t; } else if (x.t - lastT > longest.ms) longest = { ms: x.t - lastT, from: lastT, to: x.t, what: sig.slice(0, 200) };
}
out.progress.longestUnchangedMs = longest;
out.labels = [...new Set(pre.map((x) => (x.boot && x.boot.visible ? x.boot.label : null)).filter(Boolean))];
out.veilTexts = [...new Set(pre.map((x) => (x.veil && x.veil.visible ? x.veil.text : null)).filter(Boolean))];
// phase timeline (changes only)
out.timeline = []; let prev = '';
for (const x of samples) { const k = `${x.phase}|${x.qphase}|${x.relay}`; if (k !== prev) { prev = k; out.timeline.push({ t: x.t, gallery: x.phase, qed64: x.qphase, relay: x.relay }); } }
// throughput: what the throttle did to each target's downloads (CDP timestamps are seconds)
const big = done.filter((r) => !r.failed && r.bytes > 1e6 && r.tsEnd && r.ts);
const byTarget = {};
for (const r of big) { const b = byTarget[r.target] || (byTarget[r.target] = { n: 0, bytes: 0, maxMbps: 0, list: [] }); const ms = (r.tsEnd - r.ts) * 1000; const mbps = (r.bytes * 8) / ((r.tsEnd - r.ts) * 1e6); b.n++; b.bytes += r.bytes; b.maxMbps = Math.max(b.maxMbps, +mbps.toFixed(1)); b.list.push({ url: r.url.slice(0, 70), bytes: r.bytes, ms: Math.round(ms), mbps: +mbps.toFixed(1), status: r.status }); }
const all = done.filter((r) => !r.failed && r.ts && r.tsEnd);
const tsMin = Math.min(...all.map((r) => r.ts)); const tsMax = Math.max(...all.map((r) => r.tsEnd));
const totalBytes = all.reduce((a, r) => a + (r.bytes || 0), 0);
out.network = { requests: done.length, failed: done.filter((r) => r.failed).map((r) => ({ url: r.url.slice(0, 80), target: r.target, failed: r.failed, wallEnd: r.wallEnd })), totalBytes, spanS: +(tsMax - tsMin).toFixed(1), aggregateMbps: +((totalBytes * 8) / ((tsMax - tsMin) * 1e6)).toFixed(1), byTarget, unfinished: reqs.size };
out.targets = [...sessions.values()].reduce((a, x) => { const k = `${x.type}${x.throttled ? '' : ' (NOT throttled)'}`; a[k] = (a[k] || 0) + 1; return a; }, {});
out.targetErrors = [...sessions.values()].filter((x) => x.errors.length).map((x) => ({ type: x.type, url: x.url, errors: x.errors })).slice(0, 10);
out.attachErrors = attachErrors.slice(0, 10);
out.shots = shots;
out.finalStatus = await page.evaluate(() => { const g = window.__showcase && window.__showcase.status(); return g ? { phase: g.phase, current: g.current, shown: g.shown, bootMs: g.bootMs, error: g.error, notice: g.notice, statusLine: g.statusLine, boot: g.boot } : null; }).catch(() => null);
out.errorCardAtEnd = samples.length ? samples[samples.length - 1].error || null : null;
out.notices = [...new Set(samples.map((x) => x.notice).filter(Boolean).map((t) => t.replace(/\d+ MB|\d+\.\d+ GB/g, '#')))];
out.firstNoticeMs = (samples.find((x) => x.notice) || {}).t ?? null;
// the panel: the shown example's first-cursor InfoView equals its golden (what a visitor sees once the boot is done)
out.panel = null;
if (PANEL && readyAt !== null && out.finalStatus && out.finalStatus.shown && crashed === null) {
  const id = out.finalStatus.shown; const at = { line: BY_ID[id].firstCursor.line, character: BY_ID[id].firstCursor.character };
  const gc = goldenCursor(id, at.line, at.character);
  if (gc) { const p = await new Gallery(s, page).expectPanel(at, gc.panels[0], { timeoutMs: 120000 }); out.panel = { id, at, equal: p.equal, ms: p.ms, diffs: p.diffs.slice(0, 5) }; }
  else out.panel = { id, at, equal: false, diffs: ['no golden for the first cursor'] };
  try { await page.screenshot({ path: shot('panel') }); shots.push({ t: Date.now() - navT, file: path.relative(RUN_DIR, shot('panel')), phase: 'panel' }); } catch { /* ignore */ }
}
const v = s.verdict({ scenarios: [] });
out.console = { ok: v.ok, counts: v.counts, unexpected: v.unexpected, crashed: v.crashed };
out.samples = samples.map((x) => ({ t: x.t, phase: x.phase, qphase: x.qphase, progress: x.progress, veil: x.veil && x.veil.visible ? x.veil.text : null, boot: x.boot && x.boot.visible ? `${x.boot.label} | ${x.boot.nums || ''} | ${x.boot.fill || ''}` : null, error: x.error ? x.error.title : null, notice: x.notice || null, gbytes: x.gboot ? x.gboot.bytes : null, gidleMs: x.gboot ? x.gboot.idleMs : null, rssGiB: x.rssGiB }));
out.summary = `${TAG}: ${MBPS} Mbit/s, ${RTT} ms RTT: ready ${readyAt === null ? 'NOT reached' : `${(readyAt / 1000).toFixed(1)} s`}; progress visible in ${pre.length - out.progress.withoutVisibleProgress.length}/${pre.length} samples before ready; error card in ${out.progress.withErrorCard} samples${firstErrorAt !== null ? ` (first at ${(firstErrorAt / 1000).toFixed(1)} s)` : ''}; longest unchanged progress ${(longest.ms / 1000).toFixed(1)} s; downloads ${(totalBytes / 1e6).toFixed(1)} MB at ${out.network.aggregateMbps} Mbit/s aggregate; targets ${JSON.stringify(out.targets)}; crash ${crashed === null ? 'no' : crashed}; console ${v.ok ? 'ok' : 'NOT ok'}; gallery notice ${out.firstNoticeMs === null ? 'never' : `from ${(out.firstNoticeMs / 1000).toFixed(1)} s`}; error card at end ${out.errorCardAtEnd ? `"${out.errorCardAtEnd}"` : 'none'}; panel ${out.panel ? `${out.panel.id} ${out.panel.equal ? 'EQUAL to golden' : `NOT equal (${out.panel.diffs.join('; ').slice(0, 160)})`}` : 'not checked'}`;
const fails = [];
if (readyAt === null) fails.push('ready not reached');
if (crashed !== null) fails.push(`renderer crash at ${crashed} ms`);
if (!v.ok) fails.push('console oracle not ok');
if (out.errorCardAtEnd) fails.push(`error card at the end "${out.errorCardAtEnd}"`);
if (!EXPECT_CARD && out.progress.withErrorCard) fails.push(`error card in ${out.progress.withErrorCard} samples (no --expect-card)`);
const noProgress = out.progress.withoutVisibleProgress.filter((x) => x.t >= GRACE_MS);
if (noProgress.length) fails.push(`no visible progress in ${noProgress.length} samples after the first ${GRACE_MS / 1000} s (first at ${(noProgress[0].t / 1000).toFixed(1)} s)`);
if (PANEL && !(out.panel && out.panel.equal)) fails.push(out.panel ? `panel ${out.panel.id} not equal to its golden` : 'panel not checked');
out.pass = fails.length === 0; out.fails = fails;
console.log(`SUMMARY ${out.summary}`);
console.log(`RESULT ${out.pass ? 'PASS' : `FAIL: ${fails.join('; ')}`}`);
fs.writeFileSync(path.join(RUN_DIR, 'explore', `throttle-${TAG}.json`), `${JSON.stringify(out, null, 1)}\n`);
try { ws.close(); } catch { /* ignore */ }
await s.close();
process.exit(out.pass ? 0 : 1);
