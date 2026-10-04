// tests/ux/lib/qed64.mjs — the UX suite harness (BUILD-PLAN §8.1, docs/TEST-PLAN-DELTAS.md applied).
//
//   launch()            one browser at a time (the suite runs under scripts/with-browser-lock.sh; every launch first
//                       waits for the §8.1 cooldown: >= 6 GiB free+inactive+speculative and no chrome-headless-shell),
//                       fresh context or a persistent profile, SharedArrayBuffer, the diagnostics/RPC tap installed in
//                       every QED64 page document (init script + exposeBinding, so it survives reloads), console
//                       watcher on every page, Playwright tracing kept only on failure (retain-on-failure semantics).
//   Gallery / Stock     drivers for /showcase/ and the bare QED64 page: status oracle (qed64.status(), relay.stats,
//                       __showcase.status()), the InfoView frameLocator, cursor placement, ready-at-version waits,
//                       the diagnostics of an exact document version.
//   domSignature()      the env-independent panel signature read from the REAL InfoView DOM (tag multiset, svg tag
//                       multiset, component counts, text leaves, InteractiveCode texts, MakeEditLink texts/titles),
//                       compared field by field with the frozen golden (lean/expect/w8/<pkg>.json, dist-lens:
//                       lean/expect/dist-lens.json). htmlSha256 and the MakeEditLink textDocument/version are NOT compared
//                       (env-dependent, TEST-PLAN-DELTAS §1).
//   classify()          the console oracle: tests/ux/bringup/console.mjs classifyConsole with EXACTLY
//                       tests/ux/selectors.json consoleAllowlist, plus a stricter correlation of the allowlisted empty
//                       console.error with LSP RequestCancelled (-32800) replies seen by the tap.
//   Metrics             out/ux/<run>/tests/<id>.json per test, merged into out/ux/<run>/metrics.json by global teardown.
import { spawnSync, execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { classifyConsole as classifyConsoleWith, consoleLine } from '../bringup/console.mjs';
import { TAP_SRC } from './lsp-tap.mjs';
import { browserLockFile } from '../../../scripts/lib/browser-lock.mjs';

export const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
export const { W } = await import('../../../scripts/lib/env.mjs'); // the work dir (QED64_SHOWCASE_WORK)
export const ORIGIN = process.env.UX_ORIGIN || 'http://localhost:5190';
export const RUN_ID = process.env.UX_RUN || 'adhoc';
export const RUN_DIR = path.join(SC, 'out', 'ux', RUN_ID);
export const SCREENS = path.join(RUN_DIR, 'screens');
export const PROFILES = path.join(SC, 'out', 'ux', 'profiles');
// UX_WARM_PROFILE: a separate warm profile for runs against another origin (mutation checks on :5192), so they never add
// that origin's snapshots to the suite's own warm profile (UX audit minor 5)
export const WARM_PROFILE = process.env.UX_WARM_PROFILE ? path.resolve(process.env.UX_WARM_PROFILE) : path.join(PROFILES, 'ux-warm');
export const LAUNCH_ARGS = ['--enable-features=SharedArrayBuffer'];
// UX_HEADED_ALL=1: the headed sign-off (final-gate lane): EVERY launch() opens Chrome for Testing in a real window (channel
// 'chromium', not headless) unless a test passes headed/channel itself; C19 runs too. Recorded as a headed sign-off by
// showcase.sh ux (ux-record.mjs), never as a verdict: the verdict browser stays chrome-headless-shell.
export const HEADED_ALL = process.env.UX_HEADED_ALL === '1';
// UX_CHANNEL=chrome (last-mile lane; only together with UX_HEADED_ALL=1): the headed sign-off in the INSTALLED branded Google
// Chrome (Playwright channel 'chrome', /Applications/Google Chrome.app) instead of Chrome for Testing. Unset (every verdict
// and every earlier sign-off): nothing changes. chromeRss() then counts the Chrome processes descended from this process
// (branded Chrome does not live under ms-playwright, and a visitor's own Chrome must never be counted).
export const CHANNEL = process.env.UX_CHANNEL || null;
if (CHANNEL && CHANNEL !== 'chrome') throw new Error(`UX_CHANNEL=${CHANNEL}: only 'chrome' (the installed branded Google Chrome) is supported`);
if (CHANNEL && !HEADED_ALL) throw new Error('UX_CHANNEL needs UX_HEADED_ALL=1 (the verdict browser stays chrome-headless-shell)');
export const LIVENESS_MODE = ['auto', 'observe', 'off'].includes(process.env.UX_LIVENESS) ? process.env.UX_LIVENESS : null;
export const HANG_DIR = path.join(SC, 'out', 'hang', 'captures');
// selectors.json with "@qed64-main-bundle" resolved to the ACTIVE pin's QED64 main bundle (scripts/lib/pins.mjs: bundle names
// are content hashes, so they differ per pin); the active pin is what :5190 serves (showcase.sh ux checks X-Showcase-Pin)
const PINS = await import(path.join(SC, 'scripts/lib/pins.mjs'));
// UX_PIN=<id>: the suite runs against a STAGED pin that UX_ORIGIN serves (SHOWCASE_PIN=<id> serve.mjs on another port), e.g.
// C22 on the fallback A without switching the active pin; global-setup checks the server's X-Showcase-Pin; never a verdict
export const UX_PIN = process.env.UX_PIN || null;
if (UX_PIN && !process.env.UX_ORIGIN) throw new Error('UX_PIN needs UX_ORIGIN (the server that serves that pin)');
export const SEL = PINS.loadSelectors(UX_PIN || undefined);
/** The tested pin's descriptor (pins/<id>/pin.json; the active pin unless UX_PIN): id, buildId, liveness.builtIn, … — tests branch on it. */
export const PIN = PINS.pinDescriptor(UX_PIN || undefined);
export const EXAMPLES = JSON.parse(fs.readFileSync(path.join(SC, 'gallery/examples.json'), 'utf8')).examples;
export const BY_ID = Object.fromEntries(EXAMPLES.map((e) => [e.id, e]));
export const IDS = EXAMPLES.map((e) => e.id);
export const SPECS = Object.fromEntries(IDS.map((id) => [id, JSON.parse(fs.readFileSync(path.join(SC, 'lean/examples', `${id}.json`), 'utf8'))]));
/** The golden of the widgets8 environment the gallery serves: w8 for phase 1, the only (w8) golden for dist-lens. */
export const goldenPath = (id) => (fs.existsSync(path.join(SC, 'lean/expect/w8', `${id}.json`)) ? path.join(SC, 'lean/expect/w8', `${id}.json`) : path.join(SC, 'lean/expect', `${id}.json`));
export const GOLDENS = Object.fromEntries(IDS.map((id) => [id, JSON.parse(fs.readFileSync(goldenPath(id), 'utf8'))]));
/** lean/expect/click-all: the native click-all of the same environment (w8). */
export const clickAllPath = (id) => (fs.existsSync(path.join(SC, 'lean/expect/click-all/w8', `${id}.json`)) ? path.join(SC, 'lean/expect/click-all/w8', `${id}.json`) : path.join(SC, 'lean/expect/click-all', `${id}.json`));
export const CLICKALL = Object.fromEntries(IDS.map((id) => [id, JSON.parse(fs.readFileSync(clickAllPath(id), 'utf8'))]));
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
export const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');
for (const d of [RUN_DIR, SCREENS, path.join(RUN_DIR, 'tests'), PROFILES]) fs.mkdirSync(d, { recursive: true });

// ------------------------------------------------------------------ host discipline
export function lockHeld() {
  const p = browserLockFile();
  if (!fs.existsSync(p)) throw new Error(`run the UX suite through scripts/with-browser-lock.sh (npm run test:ux): the host browser lock ${p} is absent`);
  return fs.readFileSync(p, 'utf8').trim();
}
const PLATFORM = await import('../../../scripts/lib/platform.mjs'); // vm_stat on macOS, MemAvailable on Linux
export function reclaimableGiB() { return PLATFORM.reclaimableBytes() / 1073741824; }
export function strayChrome() {
  return (spawnSync('pgrep', ['-fl', 'chrome-headless-shell'], { encoding: 'utf8' }).stdout || '').trim();
}
/** §8.1 cooldown before every boot. Waits up to `ms`; throws when it cannot be met. */
export async function cooldown({ minGiB = 6, ms = 180000 } = {}) {
  const t0 = Date.now();
  for (;;) {
    const free = reclaimableGiB(); const strays = strayChrome();
    if (free >= minGiB && !strays) return { freeGiB: +free.toFixed(1), waitedMs: Date.now() - t0 };
    if (Date.now() - t0 > ms) throw new Error(`cooldown refused after ${ms} ms: ${free.toFixed(1)} GiB reclaimable, strays: ${strays || 'none'}`);
    await sleep(1000);
  }
}
/**
 * The plan's memory fail line (BUILD-PLAN §8.3 C3: "Fail at >= 10.5 GB (macOS kill seen at about 11 GB)"), in BYTES:
 * 10.5e9 B = 9.78 GiB. (The first suite compared GiB with 10.5, i.e. 11.27 GB, above the kill line it guards: UX audit
 * minor 1.) Every memory assertion uses rendererBytes against this.
 */
export const MEM_FAIL_BYTES = 10.5e9;
/** Renderer/GPU/browser RSS of the Playwright Chrome processes (bytes, plus GiB for reading; ps rss is KiB). */
export function chromeRss() {
  const out = { totalBytes: 0, rendererBytes: 0, maxRendererBytes: 0, totalGiB: 0, rendererGiB: 0, maxRendererGiB: 0, rendererGB: 0, procs: 0, renderers: 0 };
  let lines;
  if (CHANNEL) {
    // branded Chrome (UX_CHANNEL): only processes descended from this test process (the browser Playwright launched)
    const rows = (spawnSync('ps', ['-axo', 'pid=,ppid=,rss=,command='], { encoding: 'utf8' }).stdout || '').split('\n').map((l) => /^\s*(\d+)\s+(\d+)\s+(\d+)\s+(.*)$/.exec(l)).filter(Boolean);
    const mine = new Set([process.pid]); let grew = true;
    while (grew) { grew = false; for (const r of rows) if (!mine.has(+r[1]) && mine.has(+r[2])) { mine.add(+r[1]); grew = true; } }
    lines = rows.filter((r) => +r[1] !== process.pid && mine.has(+r[1]) && /Google Chrome/.test(r[4])).map((r) => `${r[3]} ${r[4]}`);
  } else lines = (spawnSync('ps', ['-axo', 'rss=,command='], { encoding: 'utf8' }).stdout || '').split('\n');
  for (const l of lines) {
    if (!CHANNEL && (!/ms-playwright/.test(l) || !/chrome|Chromium/.test(l))) continue;
    const b = (Number(l.trim().split(/\s+/)[0]) || 0) * 1024;
    out.totalBytes += b; out.procs++;
    if (/--type=renderer/.test(l)) { out.rendererBytes += b; out.renderers++; out.maxRendererBytes = Math.max(out.maxRendererBytes, b); }
  }
  out.totalGiB = +(out.totalBytes / 1073741824).toFixed(2); out.rendererGiB = +(out.rendererBytes / 1073741824).toFixed(2);
  out.maxRendererGiB = +(out.maxRendererBytes / 1073741824).toFixed(2); out.rendererGB = +(out.rendererBytes / 1e9).toFixed(2);
  return out;
}
export function rssSampler(intervalMs = 1000) {
  const t0 = Date.now(); const samples = []; let peak = { rendererGiB: 0, totalGiB: 0 };
  const h = setInterval(() => { const r = chromeRss(); samples.push({ t: Date.now() - t0, ...r }); if (r.rendererBytes > (peak.rendererBytes || 0)) peak = { ...r, t: Date.now() - t0 }; }, intervalMs);
  return { samples, get peak() { return peak; }, stop: () => clearInterval(h) };
}
/**
 * Bytes the server actually sent (scripts/serve.mjs request log: `<iso> GET <url> <status> <sent>/<len> <ms>ms [route]`)
 * since `sinceMs` (epoch), grouped like Session.bytes. This is network truth: browser cache / OPFS hits never reach it.
 */
export function serverBytes(sinceMs, port = 5190) {
  const f = path.join(W, 'logs', `serve-${port}.log`);
  const out = {}; if (!fs.existsSync(f)) return { error: `no ${f}` };
  const size = fs.statSync(f).size; const fd = fs.openSync(f, 'r'); const n = Math.min(size, 8 << 20);
  const buf = Buffer.alloc(n); fs.readSync(fd, buf, 0, n, size - n); fs.closeSync(fd);
  for (const l of buf.toString('utf8').split('\n')) {
    const m = /^(\S+Z) (GET|HEAD) (\S+) (\d{3}) (\d+)\/(\d+)/.exec(l); if (!m) continue;
    const t = Date.parse(m[1]); if (!(t >= sinceMs)) continue;
    const p = m[3].split('?')[0];
    const k = p.startsWith('/snapshots/') ? (/\.snapz$/.test(p) ? `snapz${m[2] === 'HEAD' ? '-HEAD' : ''}` : 'snapshots-index') : (p.split('/')[1] || 'root');
    const b = out[k] || (out[k] = { n: 0, bytes: 0, s304: 0 }); b.n++; b.bytes += Number(m[5]); if (m[4] === '304') b.s304++;
  }
  return out;
}
export function serverUp(origin = ORIGIN) {
  const r = spawnSync('curl', ['-sf', '-o', '/dev/null', '-w', '%{http_code}', `${origin}/showcase/pin.json`], { encoding: 'utf8' });
  return r.status === 0 && r.stdout === '200';
}
/** Start our own serve.mjs on another port (e.g. CHAOS for C11); never touches 5190's server. */
export function startServer(port, env = {}) {
  const r = spawnSync(path.join(SC, 'scripts/serve-start.sh'), [], { encoding: 'utf8', env: { ...process.env, PORT: String(port), ...env } });
  if (r.status !== 0) throw new Error(`serve-start PORT=${port} failed: ${r.stdout} ${r.stderr}`);
  return r.stdout.trim();
}
export function stopServer(port) {
  if (String(port) === '5190') throw new Error('the suite never stops the :5190 server from a test');
  return spawnSync(path.join(SC, 'scripts/serve-stop.sh'), [], { encoding: 'utf8', env: { ...process.env, PORT: String(port) } }).stdout.trim();
}

// the tap (diagnostics + LSP error replies): tests/ux/lib/lsp-tap.mjs TAP_SRC (shared with tests/ux/bringup/lib.mjs)

// ------------------------------------------------------------------ InfoView DOM oracle (UX audit minor 2)
// D1 (abortSignal not stripped) shows as "Unrecognised error … abortSignal" RENDERED in the InfoView and is never
// logged, so the console oracle cannot see it. This init script (in the QED64 page) scans the InfoView document every
// 300 ms and reports, once per string per document, any selectors.json consoleAllowlist.neverAllowed string in its DOM
// text, so EVERY test fails on a broken panel, also the tests
// that compare no panel signature (C16 after recovery, C17, …). Session.verdict() counts these as unexpected.
const IV_SRC = `(() => {
  // runs in the QED64 page document (pathname '/'), which reliably gets init scripts; the InfoView is its same-origin
  // srcdoc iframe (#infoview iframe), read from here (an init script in the srcdoc frame itself did not run: fix-mutA)
  try { if (location.pathname !== '/' || window.__uxIvObs) return; } catch (e) { return; }
  window.__uxIvObs = { scans: 0, docs: 0 };
  const NEVER = ${JSON.stringify(SEL.consoleAllowlist.neverAllowed)};
  const rep = (o) => { try { if (typeof window.__uxReport === 'function') window.__uxReport(o); } catch (e) {} };
  const seen = new WeakMap();
  const scanDoc = (d) => {
    if (!d || !d.body) return;
    let s = seen.get(d); if (!s) { s = new Set(); seen.set(d, s); window.__uxIvObs.docs++; }
    const t = d.body.textContent || '';
    for (const n of NEVER) if (!s.has(n) && t.includes(n)) { s.add(n); const i = t.indexOf(n); rep({ kind: 'ivNeverAllowed', text: n, context: t.slice(Math.max(0, i - 100), i + 160) }); }
    for (const f of d.querySelectorAll('iframe')) { let cd = null; try { cd = f.contentDocument; } catch (e) { cd = null; } if (cd) scanDoc(cd); }
  };
  setInterval(() => { try { window.__uxIvObs.scans++; const host = document.getElementById('infoview'); if (!host) return; for (const f of host.querySelectorAll('iframe')) { let cd = null; try { cd = f.contentDocument; } catch (e) { cd = null; } if (cd) scanDoc(cd); } } catch (e) {} }, 300);
})();`;

// ------------------------------------------------------------------ console watcher (all frames, workers, loads)
export function watchConsole(page, t0, sink) {
  const w = { messages: [], pageErrors: [], crashed: false, workers: [], loads: { top: 0, qed64: 0, infoview: 0 } };
  const emit = (kind, rec) => { if (sink) sink(kind, rec); };
  page.on('console', (m) => {
    let loc = null; try { loc = m.location(); } catch { /* ignore */ }
    let worker = null; try { worker = m.worker ? (m.worker() ? m.worker().url() : null) : null; } catch { /* ignore */ }
    const rec = { t: Date.now() - t0, wall: Date.now(), type: m.type(), text: m.text().slice(0, 600), url: loc && loc.url ? loc.url.replace(/^https?:\/\/localhost:\d+/, '') : null, line: loc ? loc.lineNumber : null, worker: worker ? worker.replace(/^https?:\/\/localhost:\d+/, '') : null };
    w.messages.push(rec); emit('console', rec);
  });
  page.on('pageerror', (e) => { const rec = { t: Date.now() - t0, wall: Date.now(), message: String(e && e.message || e).slice(0, 400), name: e && e.name, stack: String(e && e.stack || '').split('\n').slice(0, 8).join('\n') }; w.pageErrors.push(rec); emit('pageerror', rec); });
  page.on('crash', () => { w.crashed = true; emit('crash', { t: Date.now() - t0, rss: chromeRss() }); });
  page.on('worker', (wk) => { const rec = { t: Date.now() - t0, url: wk.url().replace(/^https?:\/\/localhost:\d+/, '').slice(0, 120), closed: null }; w.workers.push(rec); wk.on('close', () => { rec.closed = Date.now() - t0; }); });
  // loads (selectors.json consoleAllowlist per-load limits), counted exactly like tests/ux/bringup/lib.mjs
  const depth = (f) => { let d = 0; for (let p = f.parentFrame(); p; p = p.parentFrame()) d++; return d; };
  page.on('request', (rq) => {
    try {
      if (!rq.isNavigationRequest() || rq.resourceType() !== 'document') return;
      const d = depth(rq.frame());
      // the QED64 page is depth 1 under the gallery, depth 0 when the stock page is top-level
      const isQed = (d === 1) || (d === 0 && /^https?:\/\/localhost:\d+\/(\?|$)/.test(rq.url()));
      if (d === 0) w.loads.top++;
      if (isQed) { w.loads.qed64++; emit('load', { t: Date.now() - t0, frame: 'qed64', url: rq.url() }); }
    } catch { /* ignore */ }
  });
  page.on('framenavigated', (f) => { try { if (depth(f) >= 2 && f.url() === 'about:srcdoc') { w.loads.infoview++; emit('load', { t: Date.now() - t0, frame: 'infoview' }); } } catch { /* ignore */ } });
  return w;
}

/**
 * The console oracle. classifyConsole (tests/ux/bringup/console.mjs) with EXACTLY selectors.json consoleAllowlist,
 * scenarios only where a test deliberately restarts / breaks the checker. Stricter than the allowlist: every empty
 * console.error at the allowlisted NotificationService site must be explained by an LSP RequestCancelled (-32800)
 * error reply seen by the tap within the 3 s before it (bring-up audit 4 minor: the entry has no count limit).
 */
// Headed sign-off only (UX_HEADED_ALL=1): desktop Chrome itself requests /favicon.ico for a top-level document without an
// icon link; the stock QED64 page (release dist/index.html) has neither a <link rel=icon> nor a favicon.ico, so every
// headed stock-page load logs one 'Failed to load resource … 404' for /favicon.ico (final-gate lane: C6, C7, C15;
// chrome-headless-shell never requests it; the gallery has favicon.svg). Allowed once per QED64 page load, headed only.
const HEADED_ALLOWLIST = { ...SEL.consoleAllowlist, consoleError: [...SEL.consoleAllowlist.consoleError, { text: '^Failed to load resource: the server responded with a status of 404 \\(Not Found\\)$', url: '/favicon.ico', maxPerPageLoad: 1, note: 'headed only: the browser UI fetches /favicon.ico; QED64 dist has none' }] };
export function classify(watch, reports, { scenarios = [] } = {}) {
  // reports: the allowlist's pairWith entry is also enforced inside classifyConsole (fail-closed without reports)
  const c = classifyConsoleWith(watch, HEADED_ALL ? HEADED_ALLOWLIST : SEL.consoleAllowlist, { scenarios, reports });
  const empty = watch.messages.filter((m) => m.type === 'error' && m.text === '' && String(m.url || '').startsWith(SEL.consoleAllowlist.consoleError[0].url));
  const cancels = reports.filter((r) => r.kind === 'errorReply' && r.code === -32800).map((r) => ({ ...r, used: false }));
  const unexplained = [];
  for (const m of empty) {
    const k = cancels.find((x) => !x.used && x.recvWall <= m.wall + 500 && x.recvWall >= m.wall - 3000);
    if (k) k.used = true; else unexplained.push({ t: m.t, url: m.url, line: m.line });
  }
  c.emptyErrors = { count: empty.length, cancelReplies: cancels.length, unexplained };
  if (unexplained.length) c.ok = false;
  // the InfoView DOM oracle (IV_SRC): a never-allowed string rendered in a panel fails like a console message
  const iv = reports.filter((r) => r.kind === 'ivNeverAllowed');
  c.infoviewDom = iv.map((r) => ({ text: r.text, context: String(r.context || '').slice(0, 260) }));
  if (iv.length) { c.ok = false; c.unexpected.push(...iv.map((r) => ({ type: 'infoview-dom', text: String(r.context || r.text).slice(0, 200), never: r.text }))); }
  return c;
}
export { consoleLine };

// ------------------------------------------------------------------ launch / sessions
let launchSeq = 0;
/**
 * Launch one browser (the only one on the host: the caller holds the host browser lock and every launch waits for the
 * §8.1 cooldown). profile: 'fresh' (new context: empty OPFS / HTTP cache), 'warm' (out/ux/profiles/ux-warm) or a
 * directory. Returns a Session.
 */
export async function launch(testInfo, { profile = 'fresh', viewport = { width: 1440, height: 900 }, colorScheme = 'light', headed = HEADED_ALL, isMobile = false, hasTouch = false, deviceScaleFactor = 1, label = null, channel = HEADED_ALL ? (CHANNEL || 'chromium') : undefined } = {}) {
  lockHeld();
  const cool = await cooldown();
  const t0 = Date.now();
  const opts = { viewport, colorScheme, deviceScaleFactor, isMobile, hasTouch };
  // A headed window rasterises glyphs for the scale of the DISPLAY it opens on, even with deviceScaleFactor 1 emulated
  // (last-mile lane: the same build gives the headed baselines on a 1x display and a 6.7 % different gallery on the 2x
  // Retina panel; tests/ux/tools/c13-dsf-probe.mjs, out/ux/last-mile/RESULTS.md). Headed launches therefore pin the
  // display scale to 1, so the headed baselines hold on any display. Headless launches are unchanged.
  const args = headed ? [...LAUNCH_ARGS, '--force-device-scale-factor=1'] : LAUNCH_ARGS;
  let browser = null; let context;
  if (profile === 'fresh') {
    browser = await chromium.launch({ args, headless: !headed, channel });
    context = await browser.newContext(opts);
  } else {
    const dir = profile === 'warm' ? WARM_PROFILE : profile;
    fs.mkdirSync(dir, { recursive: true });
    context = await chromium.launchPersistentContext(dir, { args, headless: !headed, channel, ...opts });
  }
  const s = new Session({ testInfo, browser, context, t0, label: label || `s${++launchSeq}`, profile, cool });
  await s.init();
  return s;
}

export class Session {
  constructor({ testInfo, browser, context, t0, label, profile, cool }) {
    Object.assign(this, { testInfo, browser, context, t0, label, profile, cool });
    this.reports = []; this.watches = []; this.pages = []; this.closed = false; this.bytes = {}; this.requests = [];
    this.stream = fs.openSync(path.join(RUN_DIR, 'tests', `${slug(testInfo)}.${label}.console.jsonl`), 'w');
  }
  log(kind, rec) { try { fs.writeSync(this.stream, `${JSON.stringify({ kind, ...rec })}\n`); } catch { /* ignore */ } }
  async init() {
    // no unbounded waits anywhere: every locator action / evaluate / navigation of this context times out
    this.context.setDefaultTimeout(45000);
    this.context.setDefaultNavigationTimeout(120000);
    await this.context.exposeBinding('__uxReport', (src, o) => { const r = { ...o, recvWall: Date.now(), frame: (() => { try { return src.frame.url(); } catch { return null; } })() }; this.reports.push(r); this.log('report', r); });
    await this.context.addInitScript({ content: TAP_SRC });
    await this.context.addInitScript({ content: IV_SRC });
    this.context.on('page', (p) => this.adopt(p));
    for (const p of this.context.pages()) this.adopt(p);
    // Tracing: @playwright/test instruments every context created during a test (also through the `playwright`
    // library), so the config's trace: 'retain-on-failure' already records these contexts and keeps the zip only for
    // failed tests (attached to the test, under out/ux/<run>/test-results/). Nothing to start here.
  }
  adopt(p) {
    if (this.pages.includes(p)) return;
    this.pages.push(p);
    const w = watchConsole(p, this.t0, (k, r) => this.log(k, r));
    this.watches.push(w);
    p.on('response', (r) => {
      try {
        const u = new URL(r.url()); if (!/^localhost$/.test(u.hostname)) return;
        const pre = u.pathname.startsWith('/snapshots/') ? (/\.snapz$/.test(u.pathname) ? 'snapz' : 'snapshots-index') : (u.pathname.split('/')[1] || 'root');
        if (r.request().method() !== 'GET') return; // the gallery preflight HEADs each .snapz (no body)
        r.request().sizes().then((sz) => { const b = this.bytes[pre] || (this.bytes[pre] = { n: 0, bytes: 0, s304: 0 }); b.n++; b.bytes += Math.max(0, sz.responseBodySize || 0); if (r.status() === 304) b.s304++; }).catch(() => {});
      } catch { /* ignore */ }
    });
  }
  async newPage() { const p = await this.context.newPage(); this.adopt(p); return p; }
  page() { return this.pages[0] || null; }
  watchOf(page) { return this.watches[this.pages.indexOf(page)]; }
  /** Console verdict over every page of this session. */
  verdict({ scenarios = [] } = {}) {
    const merged = { messages: [], pageErrors: [], crashed: false, loads: { top: 0, qed64: 0, infoview: 0 } };
    for (const w of this.watches) { merged.messages.push(...w.messages); merged.pageErrors.push(...w.pageErrors); merged.crashed ||= w.crashed; for (const k of Object.keys(merged.loads)) merged.loads[k] += w.loads[k]; }
    return classify(merged, this.reports, { scenarios });
  }
  async close() {
    if (this.closed) return; this.closed = true;
    await this.context.close().catch(() => {});
    if (this.browser) await this.browser.close().catch(() => {});
    try { fs.closeSync(this.stream); } catch { /* ignore */ }
  }
}
export const slug = (testInfo) => testInfo.title.split(' ')[0].replace(/[^A-Za-z0-9._-]/g, '_');

// ------------------------------------------------------------------ page drivers
/** Evaluate `fn(arg)` inside the QED64 page window (gallery: the iframe; stock: the page itself). */
export function qEval(page, kind, fn, arg) {
  if (kind === 'stock') return page.evaluate(fn, arg === undefined ? null : arg);
  return page.evaluate(([src, a]) => { const w = document.getElementById('qed64-frame').contentWindow; return new w.Function('arg', `return (${src})(arg);`)(a); }, [fn.toString(), arg === undefined ? null : arg]);
}
export async function until(fn, { timeoutMs = 30000, intervalMs = 200 } = {}) {
  const t0 = Date.now();
  for (;;) {
    const v = await fn().catch(() => null);
    if (v) return v;
    if (Date.now() - t0 > timeoutMs) return null;
    await sleep(intervalMs);
  }
}
/** Shared by Gallery and Stock: the QED64 page oracle. */
class QedDriver {
  constructor(session, page, kind) { Object.assign(this, { session, page, kind }); }
  q(fn, arg) { return qEval(this.page, this.kind, fn, arg); }
  get iv() { return this.kind === 'stock' ? this.page.frameLocator(SEL.infoview.frame) : this.page.frameLocator('#qed64-frame').frameLocator(SEL.infoview.frame); }
  get qframe() { return this.kind === 'stock' ? this.page : this.page.frameLocator('#qed64-frame'); }
  qstatus() {
    return this.q(() => { const q = window.qed64; if (!q) return null; const s = q.status(); const r = q.relay; return { phase: s.phase, version: s.version, header: s.header ? { mode: s.header.mode, missing: s.header.missing, key: s.header.key } : null, collision: s.collision || null, session: s.session, relay: s.relay, lastDeath: s.lastDeath, pool: s.pool, stats: { ...r.stats }, snapshots: r.session && r.session.snapshots, lastTextLen: r.lastText.length }; }).catch(() => null);
  }
  text() { return this.q(() => { try { return window.qed64.editor.getModel().getValue(); } catch (e) { return null; } }).catch(() => null); }
  setCursor(line0, char0) { return this.q((a) => { const e = window.qed64.editor; e.setPosition({ lineNumber: a[0] + 1, column: a[1] + 1 }); e.revealLineInCenter(a[0] + 1); return true; }, [line0, char0]); }
  focusEditor() { return this.q(() => { window.qed64.editor.focus(); return window.qed64.editor.hasTextFocus(); }); }
  async waitReady({ minVersion = -1, timeoutMs = 300000, text = null } = {}) {
    return until(async () => {
      const s = await this.qstatus();
      if (!s || s.phase !== 'ready' || !(s.version > minVersion)) return null;
      if (text !== null && (await this.text()) !== text) return null;
      return s;
    }, { timeoutMs, intervalMs: 150 });
  }
  /** The last publishDiagnostics of exactly `version` (waits for one; the server publishes progressively). */
  async diagnosticsOf(version, { settleMs = 600, timeoutMs = 30000 } = {}) {
    const get = () => this.q((v) => { const p = (window.__uxTap && window.__uxTap.pub || []).filter((x) => x.version === v); return p.length ? { n: p.length, last: p[p.length - 1] } : null; }, version);
    const first = await until(get, { timeoutMs, intervalMs: 150 });
    if (!first) return null;
    await sleep(settleMs);
    const d = await get();
    return d ? d.last.diags : null;
  }
  tap() { return this.q(() => window.__uxTap ? { pub: window.__uxTap.pub.length, errReplies: window.__uxTap.errReplies.slice(-50), calls: window.__uxTap.calls, installedAt: window.__uxTap.installedAt } : null).catch(() => null); }
  telemetry() {
    return this.q(() => {
      const r = window.qed64.relay;
      // the worker's telemetry reply carries the wasm memory report under .memory (tests/ux/bringup/memprobe.mjs)
      return Promise.race([r.session.lean.request('telemetry'), new Promise((res) => setTimeout(() => res(null), 5000))]).then((v) => { const m = v && (v.memory || (v.result && v.result.memory)); return m ? { session: r.session.id, currentBytes: m.currentBytes, initialBytes: m.initialBytes, maximumBytes: m.maximumBytes, regionBytes: m.regionBytes } : null; });
    }).catch((e) => ({ error: String(e.message).slice(0, 200) }));
  }
  ivText() { return this.iv.locator('body').innerText({ timeout: 5000 }).catch(() => ''); }
  async ivSettled({ timeoutMs = 60000 } = {}) {
    const t0 = Date.now();
    for (;;) {
      const gold = await this.iv.locator(SEL.infoview.updatingSummary).count().catch(() => 1);
      const err = await this.iv.locator(SEL.infoview.errorDiv, { hasText: 'Error updating' }).count().catch(() => 0);
      if (!gold && !err) return true;
      if (Date.now() - t0 > timeoutMs) return false;
      await sleep(200);
    }
  }
  /** Read the panel signature at a position (see domSignature). */
  signature(at, opts = {}) { return this.iv.locator('body').evaluate(domSignature, { at, ...opts }).catch((e) => ({ ok: false, reason: `evaluate failed: ${String(e.message).slice(0, 200)}` })); }
  /** Poll until the DOM signature at `at` equals `golden` (a golden panel object), or time out. */
  async expectPanel(at, golden, { timeoutMs = 30000, ...opts } = {}) {
    let last = null; const t0 = Date.now();
    const ok = await until(async () => {
      const d = await this.signature(at, { ...opts, panelTitle: golden.panelTitle || null, tagHint: golden.tagCounts });
      last = d.ok ? { dom: d, cmp: compareSignature(d.sig, golden) } : { dom: d, cmp: { equal: false, diffs: [d.reason] } };
      return last.cmp.equal ? last : null;
    }, { timeoutMs, intervalMs: 300 });
    return { equal: !!ok, ms: Date.now() - t0, diffs: last ? last.cmp.diffs : ['no signature'], at: last && last.dom ? last.dom.at : null, heads: last && last.dom ? last.dom.heads : null, sig: last && last.dom ? last.dom.sig : null };
  }
}
export class Gallery extends QedDriver {
  constructor(session, page) { super(session, page || session.page(), 'gallery'); }
  static async open(session, { hash = '', query = '', page = null, waitReady = true, origin = ORIGIN } = {}) {
    // UX_LIVENESS=observe|off|auto: the liveness probe's mode for every gallery the suite opens (a hang hunt runs
    // UX_LIVENESS=observe so that a real L7 is captured, not restarted); a test's own ?liveness= wins
    if (LIVENESS_MODE && !/[?&]liveness=/.test(query)) query = `${query || '?'}${query && query !== '?' ? '&' : ''}liveness=${LIVENESS_MODE}`;
    const p = page || session.page() || await session.newPage();
    const g = new Gallery(session, p);
    g.tNav = Date.now();
    await p.goto(`${origin}/showcase/${query}${hash ? `#${hash}` : ''}`, { waitUntil: 'domcontentloaded' });
    if (waitReady) g.boot = await g.waitGallery();
    return g;
  }
  status() { return this.page.evaluate(() => window.__showcase && window.__showcase.status()).catch(() => null); }
  bridge() { return this.page.evaluate(() => window.__showcase && window.__showcase.bridgeStats()).catch(() => null); }
  currentText() { return this.page.evaluate(() => window.__showcase && window.__showcase.currentText()).catch(() => null); }
  select(id) { return this.page.evaluate((i) => window.__showcase.select(i).then((s) => ({ ok: true, s }), (e) => ({ ok: false, code: e && e.code, message: String(e && e.message || e) })), id); }
  /**
   * Select an example the way a user does: a real mouse click on its card in the rail (UX audit minor 3a: C3/C4 went
   * through the page API). Resolves when the gallery has shown it (ready/refused) or failed, with the selection's own
   * outcome from the gallery's selection log.
   */
  async selectUI(id, { timeoutMs = 330000 } = {}) {
    const before = await this.status();
    const lastToken = before && before.selections.length ? before.selections[before.selections.length - 1].token : 0;
    await this.page.locator(`#card-${id}`).click();
    const t = Date.now();
    const s = await until(async () => {
      const st = await this.status(); if (!st) return null;
      const mine = st.selections.find((l) => l.token > lastToken && l.id === id);
      if (mine && mine.outcome) return { st, mine };
      return null;
    }, { timeoutMs, intervalMs: 100 });
    if (!s) return { ok: false, code: 'TIMEOUT', ms: Date.now() - t };
    return { ok: s.mine.outcome === 'ok', code: s.mine.outcome, s: s.st, ms: Date.now() - t };
  }
  async waitGallery({ timeoutMs = 400000 } = {}) {
    const t0 = Date.now();
    for (;;) {
      const s = await this.status();
      if (s && ['ready', 'refused', 'error', 'halted', 'unsupported'].includes(s.phase)) return { s, ms: Date.now() - t0 };
      if (Date.now() - t0 > timeoutMs) return { s, ms: Date.now() - t0, timedOut: true };
      await sleep(150);
    }
  }
  /**
   * Observe mode (?liveness=observe or __showcase.liveness('observe'), UX_LIVENESS=observe): when the gallery's
   * liveness probe has newly declared the checker wedged, take a hang capture (captureHang) BEFORE anything resets,
   * restarts or reloads it. Returns the capture record, or null when there is nothing new to capture.
   */
  async maybeCapture(context) {
    const st = await this.status(); const lv = st && st.liveness;
    if (!lv || lv.mode !== 'observe' || !lv.wedgedActive || lv.wedged <= (this.capturedWedges || 0)) return null;
    this.capturedWedges = lv.wedged;
    const c = await captureHang(this, { context });
    (this.captures ||= []).push(c);
    return c;
  }
  /** Reset through the real "Reset example" button; resolves when ready, not edited, text == example. A stall card
   * (QED64 L7) shown meanwhile is answered with its own "Restart Lean" button and recorded in `stalls`. */
  async resetUI(ex, { timeoutMs = 300000, stalls = null } = {}) {
    const t = Date.now();
    await this.maybeCapture('before-reset'); // a Reset on a stalled checker restarts it: capture first
    await this.page.locator('#reset-btn').click();
    const s = await until(async () => {
      await this.maybeCapture('reset');
      if (await this.stallCardVisible()) { const r = await this.recoverStall('reset'); if (stalls) stalls.push(r); }
      const st = await this.status(); const tx = await this.currentText(); const q = await this.qstatus();
      return st && st.phase === 'ready' && !st.edited && tx === ex.text && q && q.phase === 'ready' ? st : null;
    }, { timeoutMs, intervalMs: 150 });
    return s ? { ok: true, ms: Date.now() - t } : { ok: false, ms: Date.now() - t };
  }
  /**
   * Every card's thumbnail is wired and loads (bring-up audit r2 minor): `#card-<pkg> .card-thumb` (selectors.json
   * cardThumb) scrolled into view as a user would (the images are loading="lazy"), then visible, src thumbs/<pkg>.png
   * and naturalWidth 480. Returns [{id, src, hidden, complete, naturalWidth, naturalHeight, w, h, ok}].
   */
  thumbs() { return this.page.evaluate(THUMBS_CHECK, IDS); }
  // ---- the stall watchdog's card (gallery.js watchStall; QED64 limitation L7)
  stallCard() { return this.page.locator('#error-card'); }
  async stallCardVisible() {
    const st = await this.status();
    return !!(st && st.stall && st.stall.active && st.error && st.error.kind === 'stalled' && await this.stallCard().isVisible().catch(() => false));
  }
  /**
   * Answer a visible stall card the way a user does: check what it offers (role=alert, its title and the three
   * actions), then press "Restart Lean" with the real mouse. Returns a record: when the card appeared relative to
   * the last progress, QED64's status (pool, version) at that moment, and the restart that followed.
   */
  async recoverStall(context) {
    const t = Date.now();
    const st = await this.status(); const q = await this.qstatus();
    const card = this.stallCard();
    const rec = {
      context, at: new Date().toISOString(), galleryStall: st && st.stall, qed64: q && { phase: q.phase, version: q.version, relay: q.relay, session: q.session, pool: q.pool, lastDeath: q.lastDeath, stats: q.stats },
      card: {
        role: await card.getAttribute('role').catch(() => null),
        title: await this.page.locator('#error-title').textContent().catch(() => null),
        detail: await this.page.locator('#error-detail').textContent().catch(() => null),
        restart: await this.page.locator('#error-retry').textContent().catch(() => null),
        reset: await this.page.locator('#error-reset').isVisible().catch(() => false),
        keepWaiting: await this.page.locator('#error-dismiss').textContent().catch(() => null),
      },
    };
    rec.shownEvent = st && st.stall ? [...st.stall.events].reverse().find((e) => e.source === 'shown') || null : null;
    try { await this.page.screenshot({ path: path.join(SCREENS, `stall-${context}-${Date.now()}.png`) }); } catch { /* ignore */ }
    await this.page.locator('#error-retry').click();
    rec.clickedRestart = true;
    const after = await until(async () => { const s2 = await this.status(); return s2 && !s2.stall.active ? s2 : null; }, { timeoutMs: 10000, intervalMs: 100 });
    rec.restartEvent = after ? [...after.stall.events].reverse().find((e) => e.source === 'card') || null : null;
    rec.ms = Date.now() - t;
    return rec;
  }
}
/** In the gallery document: the card thumbnail check (Gallery.thumbs; tests/ux/bringup/widgets.mjs uses the same source). */
export const THUMBS_CHECK = async (ids) => {
  const out = [];
  for (const id of ids) {
    const img = document.querySelector(`#card-${id} .card-thumb`);
    if (!img) { out.push({ id, ok: false, why: 'no #card-<pkg> .card-thumb' }); continue; }
    img.scrollIntoView({ block: 'nearest' });
    const t0 = performance.now();
    while (!(img.complete && img.naturalWidth) && !img.hidden && performance.now() - t0 < 8000) await new Promise((r) => setTimeout(r, 50));
    const r = img.getBoundingClientRect(); const cs = getComputedStyle(img);
    const rec = { id, src: img.getAttribute('src'), fit: img.dataset.fit || null, hidden: img.hidden, complete: img.complete, naturalWidth: img.naturalWidth, naturalHeight: img.naturalHeight, w: Math.round(r.width), h: Math.round(r.height), display: cs.display, visibility: cs.visibility };
    rec.ok = rec.src === `thumbs/${id}.png` && !rec.hidden && rec.complete && rec.naturalWidth === 480 && rec.w > 0 && rec.h > 0 && rec.display !== 'none' && rec.visibility === 'visible';
    out.push(rec);
  }
  return out;
};
export class Stock extends QedDriver {
  constructor(session, page) { super(session, page || session.page(), 'stock'); }
  /** Seed localStorage['qed64.buffer'] (the page's boot document, main.ts:335-342) then open /?snapshots=… */
  static async open(session, { buffer = null, query = '?snapshots=snapshots/widgets8', page = null, origin = ORIGIN } = {}) {
    const p = page || session.page() || await session.newPage();
    await p.goto(`${origin}/showcase/pin.json`);
    await p.evaluate((b) => { if (b === null) localStorage.removeItem('qed64.buffer'); else localStorage.setItem('qed64.buffer', b); }, buffer);
    const s = new Stock(session, p); s.tNav = Date.now();
    await p.goto(`${origin}/${query}`, { waitUntil: 'domcontentloaded' });
    return s;
  }
  pageInfo() { return this.page.evaluate(() => ({ pill: (document.getElementById('ptext') || {}).textContent || null, bootcard: (document.getElementById('bootcard') || {}).className || null, bootlabel: (document.getElementById('bootlabel') || {}).textContent || null, action: (() => { const a = [...document.querySelectorAll('button, a')].find((b) => /Load exact imports/.test(b.textContent)); return a ? { text: a.textContent.trim(), visible: !!(a.offsetWidth || a.offsetHeight) } : null; })() })).catch(() => null); }
  /** Settles on ready / headerRefused / halted / dead / a failed boot card. */
  async settle({ timeoutMs = 300000 } = {}) {
    return until(async () => { const s = await this.qstatus(); const i = await this.pageInfo(); if (s && ['ready', 'headerRefused', 'halted', 'dead'].includes(s.phase)) return { s, i }; if (i && /failed/.test(i.bootcard || '')) return { s, i }; return null; }, { timeoutMs, intervalMs: 200 });
  }
}

// ------------------------------------------------------------------ hang capture (QED64 L7; docs/NEXT-STEPS.md, ROOT-CAUSE.md W4)
/**
 * Capture the state of a (possibly) frozen QED64 runtime BEFORE anything resets, restarts or reloads it. Called by
 * clickLink when a click is "not ready within … after the click", and by Gallery.maybeCapture when the gallery's
 * liveness probe declares the checker wedged in observe mode. Steps, in this order:
 *   (a) the gallery's status (stall + liveness), qed64.status() with the worker's pool counters, relay.stats, the tap;
 *   (b) `await qed64.relay.session.lean.telemetry()` raced against 10 s: the answered value, or did-NOT-answer;
 *   (c) every console line of the QED64 page's dedicated workers since the session started, plus the page's
 *       `[lean:stderr]` / `[lean:stdout]` / `[WASM …]` lines (LeanSession.onLog → console.debug), into a .log file;
 *   (d) the mailbox protocol from the QED64 session (its E1 fault-injection reference, ROOT-CAUSE.md W1/W4):
 *       1. in each dedicated worker where `typeof __emscripten_check_mailbox === 'function'`, call it ONCE (record the
 *          ms it took and PThread's pool) — only where `_pthread_self()` is non-zero, the glue's own guard in
 *          checkMailbox (an idle pool worker has no thread whose mailbox it could drain); a worker whose JS thread does
 *          not answer within 3 s (a Lean thread blocked in wasm) is recorded as blocked. Then watch 15 s for any
 *          qed64.status() phase/version change or LSP frame (the tap's frame counter);
 *       2. only if nothing moved: call the glue's `checkMailbox()` ONCE in the Emscripten main-thread worker (never on
 *          a timer: each call arms one more Atomics.waitAsync waiter) and watch 15 s again.
 *       Each step records resumed yes/no. Every worker call carries a deadline, so a call that a blocked worker only
 *       runs later (when its thread returns to the event loop) does nothing.
 * synthetic: the C21 freeze fixture (the session's output detached in the page; the runtime itself is healthy). Its
 * captures are labelled "SYNTHETIC — not L7 evidence": they prove the capture works, not anything about L7.
 * Writes out/hang/captures/<run>-<iso>.json and <run>-<iso>.worker-console.log; returns {file, log, summary}.
 */
export async function captureHang(g, { context = 'stall', synthetic = false, watchMs = 15000 } = {}) {
  const t0 = Date.now(); const iso = new Date(t0).toISOString();
  fs.mkdirSync(HANG_DIR, { recursive: true });
  const base = path.join(HANG_DIR, `${RUN_ID}-${iso.replace(/[:.]/g, '-')}`);
  const frozenFixture = await g.q(() => window.__uxFrozen || window.__uxFixture || null).catch(() => null); // C21 freeze / C23 forced death
  const isSynthetic = !!(synthetic || frozenFixture);
  const cap = {
    schema: 'qed64-showcase.hang-capture/v1', run: RUN_ID, at: iso, context, origin: ORIGIN,
    synthetic: isSynthetic, frozenFixture,
    evidence: isSynthetic ? 'SYNTHETIC: the C21 freeze fixture detached the session output inside the page; the Lean runtime itself was healthy. This capture proves the capture path only. It is NOT L7 evidence.'
      : 'REAL: captured on an unmodified runtime that stopped making progress (a possible L7).',
    steps: {},
  };
  const stamp = (k, v) => { cap.steps[k] = { atMs: Date.now() - t0, ...v }; };
  // (a)
  const gst = await g.status().catch(() => null);
  stamp('a_status', {
    gallery: gst && { phase: gst.phase, current: gst.current, qed64: gst.qed64, stall: gst.stall, liveness: gst.liveness, error: gst.error && { kind: gst.error.kind, title: gst.error.title } },
    qed64: await g.qstatus(),
    tap: await g.q(() => (window.__uxTap ? { frames: window.__uxTap.frames, lastFrameAt: window.__uxTap.lastFrameAt, pub: window.__uxTap.pub.length, probeReplies: window.__uxTap.probeReplies, calls: window.__uxTap.calls } : null)).catch(() => null),
  });
  // (b)
  const tel = await g.q(() => {
    const t = Date.now();
    let p; try { p = window.qed64.relay.session.lean.telemetry(); } catch (e) { return { answered: false, error: `telemetry() threw: ${String(e && e.message || e).slice(0, 200)}` }; }
    return Promise.race([
      p.then((v) => ({ answered: true, ms: Date.now() - t, value: v }), (e) => ({ answered: true, ms: Date.now() - t, rejected: String(e && e.message || e).slice(0, 200) })),
      new Promise((res) => setTimeout(() => res({ answered: false, ms: Date.now() - t, note: 'did NOT answer within 10 s' }), 10000)),
    ]);
  }).catch((e) => ({ answered: false, error: String(e.message).slice(0, 200) }));
  stamp('b_telemetry', tel);
  // (c)
  const all = g.session.watches.flatMap((w) => w.messages);
  const lines = all.filter((m) => m.worker || /\[lean:(stderr|stdout)\]|\[WASM/.test(m.text));
  const log = `${base}.worker-console.log`;
  fs.writeFileSync(log, `${lines.map((m) => `${String(m.t).padStart(9)} ms ${m.type.padEnd(7)} ${m.worker ? `[worker ${m.worker}]` : '[page]'} ${m.text.replace(/\n/g, '\\n')}`).join('\n')}\n`);
  stamp('c_workerConsole', { file: rel(log), lines: lines.length, fromWorkers: lines.filter((m) => m.worker).length, leanStderr: lines.filter((m) => /\[lean:stderr\]/.test(m.text)).length, wasm: lines.filter((m) => /\[WASM/.test(m.text)).length, last: lines.slice(-25).map((m) => `${m.t} ${m.type} ${m.worker ? 'worker' : 'page'} ${m.text.slice(0, 200)}`) });
  // (d)
  const probeState = async () => {
    const q = await g.qstatus();
    const f = await g.q(() => (window.__uxTap ? window.__uxTap.frames : null)).catch(() => null);
    return { phase: q && q.phase, version: q && q.version, session: q && q.session, frames: f };
  };
  const watch = async (from) => {
    const tw = Date.now(); let last = from;
    while (Date.now() - tw < watchMs) {
      await sleep(250);
      last = await probeState();
      if (last.phase !== from.phase || last.version !== from.version || last.session !== from.session || (last.frames !== null && from.frames !== null && last.frames > from.frames)) return { resumed: true, afterMs: Date.now() - tw, from, to: last };
    }
    return { resumed: false, watchedMs: Date.now() - tw, from, to: last };
  };
  const workers = g.page.workers();
  const classify = (w) => Promise.race([
    w.evaluate((deadline) => {
      if (Date.now() > deadline) return { late: true };
      const self0 = typeof _pthread_self === 'function' ? Number(_pthread_self()) : null;
      return {
        name: self.name || null, raw: typeof __emscripten_check_mailbox, glueCheck: typeof checkMailbox,
        isPthread: typeof ENVIRONMENT_IS_PTHREAD === 'undefined' ? null : !!ENVIRONMENT_IS_PTHREAD, pthreadSelf: self0,
        pool: typeof PThread === 'undefined' || !PThread.unusedWorkers ? null : { unused: PThread.unusedWorkers.length, running: Object.keys(PThread.pthreads || {}).length }, // as lean.worker.js poolSample
      };
    }, Date.now() + 3000).then((v) => ({ answered: true, ...v }), (e) => ({ answered: true, error: String(e.message).slice(0, 160) })),
    sleep(3000).then(() => ({ answered: false, note: 'no answer in 3 s (JS thread busy: a Lean thread blocked in wasm)' })),
  ]);
  const infos = await Promise.all(workers.map(async (w) => ({ w, url: w.url().replace(/^https?:\/\/localhost:\d+/, '').slice(0, 120), info: await classify(w) })));
  const kick = (w, fnName) => Promise.race([
    w.evaluate(([deadline, which]) => {
      if (Date.now() > deadline) return { late: true };
      const t = performance.now(); let error = null;
      try { if (which === 'raw') __emscripten_check_mailbox(); else checkMailbox(); } catch (e) { error = String(e && e.message || e).slice(0, 200); }
      return { ms: +(performance.now() - t).toFixed(3), error, pool: typeof PThread === 'undefined' || !PThread.unusedWorkers ? null : { unused: PThread.unusedWorkers.length, running: Object.keys(PThread.pthreads || {}).length } };
    }, [Date.now() + 3000, fnName]).catch((e) => ({ error: String(e.message).slice(0, 160) })),
    sleep(5000).then(() => ({ noAnswerIn5s: true })),
  ]);
  const before1 = await probeState();
  const raw = [];
  for (const x of infos) {
    if (!x.info.answered) { raw.push({ url: x.url, skipped: x.info.note }); continue; }
    if (x.info.raw !== 'function') { raw.push({ url: x.url, name: x.info.name, skipped: `typeof __emscripten_check_mailbox === '${x.info.raw}'` }); continue; }
    if (!x.info.pthreadSelf) { raw.push({ url: x.url, name: x.info.name, isPthread: x.info.isPthread, skipped: '_pthread_self() is 0 (idle pool worker: no thread mailbox; the glue\'s checkMailbox returns here too)' }); continue; }
    raw.push({ url: x.url, name: x.info.name, isPthread: x.info.isPthread, called: '__emscripten_check_mailbox()', ...(await kick(x.w, 'raw')) });
  }
  const w1 = await watch(before1);
  stamp('d1_rawCheckMailbox', {
    workers: workers.length, answered: infos.filter((x) => x.info.answered).length, blocked: infos.filter((x) => !x.info.answered).length,
    mainThread: infos.filter((x) => x.info.isPthread === false).map((x) => ({ url: x.url, ...x.info })),
    calls: raw.filter((r) => r.called), skipped: raw.filter((r) => r.skipped).reduce((a, r) => { a[r.skipped] = (a[r.skipped] || 0) + 1; return a; }, {}), ...w1,
  });
  if (!w1.resumed) {
    const main = infos.find((x) => x.info.answered && x.info.isPthread === false && x.info.glueCheck === 'function');
    if (!main) stamp('d2_checkMailbox', { called: false, why: 'no Emscripten main-thread worker with checkMailbox answered', resumed: false });
    else {
      const before2 = await probeState();
      const r = await kick(main.w, 'glue');
      const w2 = await watch(before2);
      stamp('d2_checkMailbox', { called: 'checkMailbox() once', url: main.url, ...r, ...w2 });
    }
  } else stamp('d2_checkMailbox', { called: false, why: 'not needed: the raw __emscripten_check_mailbox() call already resumed it' });
  cap.summary = {
    synthetic: isSynthetic, telemetryAnswered: !!tel.answered, workerConsoleLines: lines.length,
    rawKickWorkers: raw.filter((r) => r.called).length, rawKickResumed: w1.resumed,
    checkMailboxCalled: !!cap.steps.d2_checkMailbox.called, checkMailboxResumed: cap.steps.d2_checkMailbox.called ? !!cap.steps.d2_checkMailbox.resumed : null,
    tookMs: Date.now() - t0,
  };
  cap.tookMs = Date.now() - t0;
  const file = `${base}.json`;
  fs.writeFileSync(file, `${JSON.stringify(cap, null, 1)}\n`);
  console.log(`[hang-capture] ${rel(file)} ${JSON.stringify(cap.summary)}`);
  return { file: rel(file), log: rel(log), summary: cap.summary };
}

/**
 * POST-HOC record of an L7 occurrence that QED64 9fdf9b8+ handled itself (final audit, minor): its Lean-side liveness
 * declared the session wedged (died "wedged") and the relay rebooted it, about 22-25 s after the last server frame. That
 * comes BEFORE the gallery's observe-mode wedge (30 s deferral + 2 x 5 s), so captureHang never sees a QED64-handled hang
 * frozen: no pre-recovery state (telemetry, mailbox kicks) can be captured from outside. What remains is recorded here:
 * the gallery's view of QED64's liveness (lastReboot, the qed64-* events, counters), qed64.status() (lastDeath, stats,
 * liveness, pool) and every worker / [lean:...] console line, with the '[liveness]' lines (stall, rescue #n, "the Lean
 * side stopped") listed separately. Writes out/hang/captures/<run>-<iso>-qed64-wedged.json and .worker-console.log.
 */
export async function captureQed64Reboot(g, { context = 'qed64 wedged reboot' } = {}) {
  const t0 = Date.now(); const iso = new Date(t0).toISOString();
  fs.mkdirSync(HANG_DIR, { recursive: true });
  const base = path.join(HANG_DIR, `${RUN_ID}-${iso.replace(/[:.]/g, '-')}-qed64-wedged`);
  const frozenFixture = await g.q(() => window.__uxFrozen || window.__uxFixture || null).catch(() => null); // C21 freeze / C23 forced death
  const gst = await g.status().catch(() => null);
  const all = g.session.watches.flatMap((w) => w.messages);
  const lines = all.filter((m) => m.worker || /\[lean:(stderr|stdout)\]|\[WASM|\[liveness\]|\[boot\]/.test(m.text));
  const log = `${base}.worker-console.log`;
  fs.writeFileSync(log, `${lines.map((m) => `${String(m.t).padStart(9)} ms ${m.type.padEnd(7)} ${m.worker ? `[worker ${m.worker}]` : '[page]'} ${m.text.replace(/\n/g, '\\n')}`).join('\n')}\n`);
  const lv = gst && gst.liveness;
  const cap = {
    schema: 'qed64-showcase.qed64-reboot-capture/v1', run: RUN_ID, at: iso, context, origin: ORIGIN, postHoc: true,
    synthetic: !!frozenFixture, frozenFixture,
    evidence: frozenFixture ? `SYNTHETIC fixture present (${frozenFixture.fixture || 'test fixture'}): this record proves the post-hoc capture path only. It is NOT L7 evidence.`
      : 'REAL: QED64\'s own liveness declared this session wedged and rebooted it (an L7 occurrence handled upstream). Post-hoc: QED64 recovered it before the gallery\'s observe-mode wedge, so no pre-recovery capture (telemetry, mailbox kicks) exists.',
    qed64Liveness: lv ? { qed64: lv.qed64, events: lv.events.filter((e) => String(e.source).startsWith('qed64-')) } : null,
    gallery: gst && { phase: gst.phase, current: gst.current, qed64: gst.qed64, stall: gst.stall, notice: gst.notice },
    qed64: await g.qstatus().catch(() => null),
    workerConsole: { file: rel(log), lines: lines.length, liveness: lines.filter((m) => /\[liveness\]/.test(m.text)).map((m) => `${m.t} ${m.text.slice(0, 300)}`), last: lines.slice(-25).map((m) => `${m.t} ${m.type} ${m.worker ? 'worker' : 'page'} ${m.text.slice(0, 200)}`) },
  };
  cap.summary = { postHoc: true, synthetic: cap.synthetic, wedgedReboots: lv ? lv.qed64.wedgedReboots : null, lastReboot: lv ? lv.qed64.lastReboot : null, rescues: lv ? lv.qed64.totals.rescues : null, livenessLines: cap.workerConsole.liveness.length, tookMs: Date.now() - t0 };
  const file = `${base}.json`;
  fs.writeFileSync(file, `${JSON.stringify(cap, null, 1)}\n`);
  console.log(`[hang-capture] QED64-handled ${rel(file)} ${JSON.stringify(cap.summary)}`);
  return { file: rel(file), log: rel(log), summary: cap.summary };
}

// ------------------------------------------------------------------ the DOM signature (runs inside the InfoView frame)
/**
 * The info block of the position `at` {line, character} (0-based LSP; its summary reads `<file>.lean:<line+1>:<char>`,
 * not under a Messages section), and in it the widget panel: the nested <details> "HTML Display" for static panels
 * (panelTitle 'HTML Display': the Html root is that details' element child), else the rpc panel — a direct child of
 * the block's content (div.ml1) that is not the InfoView's own chrome (goal view, expected type, messages, HTML
 * Display). Returns {ok, at, heads, sig, candidates} where sig mirrors lean/goldens/lsp-golden.mjs signature():
 *   tagCounts / svgTagCounts: element tag multisets of the Html (MakeEditLink <a> and InteractiveCode subtrees are
 *   components, not tags); components: {MakeEditLink, InteractiveCode} counts; texts: non-blank text leaves in DOM
 *   order (InteractiveCode excluded, MakeEditLink children included, as the golden walks them); codeTexts: each
 *   InteractiveCode's text; links: [{linkText, title}] in DOM order (title '' -> null).
 * Elements are tagged data-ux-panel (the panel root) and data-ux-link="<i>" (i-th MakeEditLink) for later clicks.
 */
export function domSignature(body, a) {
  const norm = (s) => String(s).replace(/\s+/g, ' ').trim();
  const sumOf = (d) => { const s = d.querySelector(':scope > summary'); return s ? norm(s.textContent) : ''; };
  const isMsg = (d) => /^(All )?Messages/.test(sumOf(d));
  const underMsg = (el, stop) => { for (let p = el.parentElement; p && p !== stop; p = p.parentElement) if (p.tagName === 'DETAILS' && isMsg(p)) return true; return false; };
  for (const el of body.querySelectorAll('[data-ux-panel],[data-ux-link],[data-ux-apply]')) { el.removeAttribute('data-ux-panel'); el.removeAttribute('data-ux-link'); el.removeAttribute('data-ux-apply'); }
  const posRe = /^[\w.\-/ ]+\.lean:(\d+):(\d+)/;
  const blocks = [...body.querySelectorAll('details')].filter((d) => posRe.test(sumOf(d)) && !underMsg(d, body));
  const heads = blocks.map((d) => sumOf(d).match(posRe)[0]);
  const want = `:${a.at.line + 1}:${a.at.character}`;
  const block = blocks.find((d) => { const m = sumOf(d).match(posRe); return m && `:${m[1]}:${m[2]}` === want; });
  if (!block) return { ok: false, at: want, heads, reason: `no info block at ${want} (blocks: ${heads.join(', ') || 'none'})` };
  const content = block.querySelector(':scope > div.ml1') || block;
  const isIC = (el) => el.tagName === 'SPAN' && el.classList.contains('font-code') && !!el.querySelector('[data-has-tooltip-on-hover]') && !(el.parentElement && el.parentElement.closest('.font-code'));
  const isLink = (el) => el.localName === 'a' && el.classList.contains('link') && el.classList.contains('pointer') && el.classList.contains('dim') && !el.classList.contains('codicon');
  const sigOf = (root) => {
    const sig = { tagCounts: {}, svgTagCounts: {}, components: {}, texts: [], codeTexts: [], links: [] };
    const linkEls = [];
    const walk = (n, inSvg) => {
      if (n.nodeType === 3) { if (n.nodeValue.trim()) sig.texts.push(n.nodeValue); return; }
      if (n.nodeType !== 1) return;
      if (isIC(n)) { sig.components.InteractiveCode = (sig.components.InteractiveCode || 0) + 1; sig.codeTexts.push(n.textContent); return; }
      if (isLink(n)) { sig.components.MakeEditLink = (sig.components.MakeEditLink || 0) + 1; sig.links.push({ linkText: n.textContent, title: n.getAttribute('title') || null }); linkEls.push(n); for (const c of n.childNodes) walk(c, inSvg); return; }
      const tag = n.localName; const svg = inSvg || tag === 'svg';
      sig.tagCounts[tag] = (sig.tagCounts[tag] || 0) + 1; if (svg) sig.svgTagCounts[tag] = (sig.svgTagCounts[tag] || 0) + 1;
      for (const c of n.childNodes) walk(c, svg);
    };
    walk(root, false);
    return { sig, linkEls };
  };
  const chromeRe = /^(Tactic state|Expected type|Messages|All Messages|Term goal|No goals|HTML Display|Goals accomplished)/;
  let roots;
  if (a.panelTitle) {
    roots = [...content.children].filter((c) => c.tagName === 'DETAILS' && sumOf(c) === a.panelTitle && !underMsg(c, block))
      .map((d) => [...d.children].filter((c) => c.tagName !== 'SUMMARY')).filter((r) => r.length === 1).map((r) => r[0]);
  } else {
    roots = [...content.children].filter((c) => {
      if (c.tagName === 'DETAILS' && chromeRe.test(sumOf(c))) return false;
      const d = c.querySelector(':scope > details, :scope > div > details');
      if (d && chromeRe.test(sumOf(d)) && c.children.length === 1) return false;
      return true;
    });
  }
  if (!roots.length) return { ok: false, at: want, heads, reason: `info block ${want} has no ${a.panelTitle ? `“${a.panelTitle}”` : 'rpc'} panel` };
  // several candidates (should not happen: one panel per cursor in every golden): prefer the one whose tag multiset
  // matches the hint, else the first
  const cands = roots.map((r) => ({ r, ...sigOf(r) }));
  let pick = cands[0];
  if (a.tagHint && cands.length > 1) {
    const score = (s) => { let d = 0; for (const k of new Set([...Object.keys(s.tagCounts), ...Object.keys(a.tagHint)])) d += Math.abs((s.tagCounts[k] || 0) - (a.tagHint[k] || 0)); return d; };
    pick = cands.slice().sort((x, y) => score(x.sig) - score(y.sig))[0];
  }
  pick.r.setAttribute('data-ux-panel', '1');
  pick.linkEls.forEach((el, i) => el.setAttribute('data-ux-link', String(i)));
  const rect = pick.r.getBoundingClientRect();
  return {
    ok: true, at: want, heads, candidates: cands.length, sig: pick.sig, rect: { x: rect.x, y: rect.y, w: rect.width, h: rect.height },
    selectedCount: block.querySelectorAll('[class*=highlight-selected]').length,
  };
}

/** Field-by-field comparison with a golden panel (env-independent fields only). */
export function compareSignature(dom, gold) {
  const diffs = [];
  const eqObj = (name, x, y) => { for (const k of new Set([...Object.keys(x || {}), ...Object.keys(y || {})])) if ((x[k] || 0) !== (y[k] || 0)) diffs.push(`${name}.${k}: dom ${x[k] || 0} golden ${y[k] || 0}`); };
  eqObj('tagCounts', dom.tagCounts, gold.tagCounts || {});
  eqObj('svgTagCounts', dom.svgTagCounts, gold.svgTagCounts || {});
  eqObj('components', dom.components, gold.components || {});
  const eqArr = (name, x, y) => {
    if (x.length !== y.length) diffs.push(`${name}: dom ${x.length} golden ${y.length}`);
    const n = Math.min(x.length, y.length);
    for (let i = 0; i < n; i++) if (x[i] !== y[i]) { diffs.push(`${name}[${i}]: dom ${JSON.stringify(x[i]).slice(0, 120)} golden ${JSON.stringify(y[i]).slice(0, 120)}`); break; }
  };
  eqArr('texts', dom.texts, gold.texts || []);
  eqArr('codeTexts', dom.codeTexts, gold.codeTexts || []);
  eqArr('links', dom.links.map((l) => `${l.linkText}\u0001${l.title || ''}`), (gold.links || []).map((l) => `${l.linkText}\u0001${l.title || ''}`));
  return { equal: diffs.length === 0, diffs };
}

// ------------------------------------------------------------------ edits
export function applyEdit(text, r, newText) {
  const lines = text.split('\n');
  const off = (p) => lines.slice(0, p.line).reduce((n, l) => n + l.length + 1, 0) + p.character;
  return text.slice(0, off(r.start)) + newText + text.slice(off(r.end));
}
export const errorsWarnings = (diags) => (diags || []).filter((d) => d.sev === 1 || d.sev === 2);

// ------------------------------------------------------------------ metrics
export function writeTestMetrics(testInfo, obj) {
  // one file per test id (the first word of the title); a second test with the same id would overwrite it: refuse
  const p = path.join(RUN_DIR, 'tests', `${slug(testInfo)}.json`);
  if (fs.existsSync(p) && JSON.parse(fs.readFileSync(p, 'utf8')).title !== testInfo.title) throw new Error(`two tests share the id ${slug(testInfo)}: give each a unique first word`);
  const doc = { id: slug(testInfo), title: testInfo.title, file: path.basename(testInfo.file), startedAt: obj.startedAt || null, ...obj };
  fs.writeFileSync(p, `${JSON.stringify(doc, null, 2)}\n`);
  return p;
}
export function screenPath(name) { return path.join(SCREENS, name); }
export const rel = (p) => path.relative(SC, p);
export function gitless() { try { return execFileSync('date', ['-u', '+%Y-%m-%dT%H:%M:%SZ']).toString().trim(); } catch { return new Date().toISOString(); } }
