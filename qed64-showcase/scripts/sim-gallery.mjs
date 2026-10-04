#!/usr/bin/env node
// sim-gallery.mjs — drive the REAL gallery/gallery.js in Node against a fake DOM (parsed from gallery/index.html)
// and a fake QED64 page that models what the controller relies on (no browser):
//   * navigation commits ~5 ms after iframe.src is set; the page document is 'loading' until its module script
//     runs (~15 ms), which constructs the relay — the FIRST session is created (initialBytes fixed) before
//     globalThis.qed64 is assigned — then 'complete' + iframe 'load';
//   * relay: lastText (full-text didChange), state rebooting/serving/halted, makeSession (own property, called on
//     restart/rearm), restart(opts) only when serving, a halted relay re-arms on didChange;
//   * worker status: version bumps per received text; header covered when the session has 'mathlib' and every
//     non-Mathlib import is in the overlay region's imports, else headerRefused;
//   * Monaco: setValue always emits a change (also for identical text), setPosition/getPosition/focus/layout.
// It is a model, not QED64: it checks the gallery's own logic (ordering, waits, supersession, error paths).
// The browser bring-up must still confirm the model's assumptions (gallery/README.md open questions).
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const G = path.join(SC, 'gallery');
const ORIGIN = 'http://localhost:5190';
const GiB = 2 ** 30, MiB = 2 ** 20;
const PIN = JSON.parse(fs.readFileSync(path.join(G, 'pin.json'), 'utf8'));
const EX = JSON.parse(fs.readFileSync(path.join(G, 'examples.json'), 'utf8')).examples;
const byId = Object.fromEntries(EX.map((e) => [e.id, e]));
let fails = 0, oks = 0;
const ok = (c, m) => { if (c) { oks++; console.log(`ok    ${m}`); } else { fails++; console.log(`FAIL  ${m}`); } return !!c; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// the browser capabilities gallery.js checks before it boots (lib.js checkCapabilities): Node's own, restored per run
const REAL = { SharedArrayBuffer: globalThis.SharedArrayBuffer, WebAssembly: globalThis.WebAssembly, BigInt: globalThis.BigInt };
async function until(fn, ms = 8000, label = 'condition') { const t0 = Date.now(); for (;;) { const v = fn(); if (v) return v; if (Date.now() - t0 > ms) throw new Error(`sim timeout: ${label}`); await sleep(10); } }

// ---------------------------------------------------------------- a tiny DOM
const VOID = new Set(['meta', 'link', 'br', 'img', 'input', 'hr', 'source', 'path', 'col', 'area', 'base', 'wbr', 'track', 'embed', 'param']);
class El {
  constructor(tag, attrs = {}) {
    this.tagName = tag.toUpperCase(); this.localName = tag; this.attrs = { ...attrs }; this.children = []; this.parent = null; this.listeners = {};
    this.dataset = {}; for (const [k, v] of Object.entries(attrs)) if (k.startsWith('data-')) this.dataset[k.slice(5)] = v;
    this._classes = new Set((attrs.class || '').split(/\s+/).filter(Boolean));
    const el = this;
    this.classList = { add: (c) => el._classes.add(c), remove: (c) => el._classes.delete(c), contains: (c) => el._classes.has(c), toggle: (c, f) => { const on = f === undefined ? !el._classes.has(c) : !!f; if (on) el._classes.add(c); else el._classes.delete(c); return on; } };
    this.hidden = 'hidden' in attrs; this.style = {}; this._text = null; this.value = attrs.value ?? '';
    this.tabIndex = attrs.tabindex !== undefined ? Number(attrs.tabindex) : -1;
  }
  get id() { return this.attrs.id || ''; } set id(v) { this.attrs.id = v; }
  get className() { return [...this._classes].join(' '); } set className(v) { this._classes = new Set(String(v).split(/\s+/).filter(Boolean)); }
  get type() { return this.attrs.type; } set type(v) { this.attrs.type = v; }
  get href() { return this.attrs.href; } set href(v) { this.attrs.href = v; }
  get textContent() { return this._text !== null ? this._text : this.children.map((c) => c.textContent).join(''); }
  set textContent(v) { this.children = []; this._text = String(v); }
  get firstElementChild() { return this.children[0] || null; }
  get content() { return { firstElementChild: this.children[0] || null }; }
  setAttribute(k, v) { this.attrs[k] = String(v); if (k === 'id') this.attrs.id = String(v); }
  getAttribute(k) { return this.attrs[k] ?? null; }
  removeAttribute(k) { delete this.attrs[k]; }
  append(...xs) { for (const x of xs) { if (typeof x === 'string') { const t = new El('#text'); t._text = x; x = t; } if (x.parent) x.parent.children = x.parent.children.filter((c) => c !== x); x.parent = this; this._text = null; this.children.push(x); } }
  replaceChildren(...xs) { for (const c of this.children) c.parent = null; this.children = []; this._text = null; this.append(...xs); }
  remove() { if (this.parent) this.parent.children = this.parent.children.filter((c) => c !== this); this.parent = null; }
  cloneNode() { const c = new El(this.localName, { ...this.attrs, class: this.className }); c.hidden = this.hidden; c._text = this._text; c.dataset = { ...this.dataset }; c.tabIndex = this.tabIndex; for (const ch of this.children) c.append(ch.cloneNode(true)); return c; }
  addEventListener(t, fn) { (this.listeners[t] ||= []).push(fn); }
  dispatch(t, ev = {}) { const e = { type: t, target: this, preventDefault() { this.defaultPrevented = true; }, stopPropagation() {}, ...ev }; for (const fn of this.listeners[t] || []) fn(e); return e; }
  click() { this.dispatch('click'); }
  focus() { SIM.doc.activeElement = this; }
  select() {}
  matches(sel) {
    let m;
    if ((m = /^([a-z]+)?\[([a-z-]+)="([^"]*)"\]$/.exec(sel))) return (!m[1] || this.localName === m[1]) && (m[2] === 'value' ? String(this.value) === m[3] || this.attrs.value === m[3] : this.attrs[m[2]] === m[3]);
    if (sel.startsWith('.')) return this._classes.has(sel.slice(1));
    if (sel.startsWith('#')) return this.id === sel.slice(1);
    return this.localName === sel;
  }
  *walk() { for (const c of this.children) { if (c.localName === '#text') continue; yield c; yield* c.walk(); } }
  querySelector(sel) { for (const e of this.walk()) if (e.matches(sel)) return e; return null; }
  querySelectorAll(sel) { return [...this.walk()].filter((e) => e.matches(sel)); }
  closest(sel) { let e = this; while (e && e.localName !== '#doc') { if (e.matches && e.matches(sel)) return e; e = e.parent; } return null; }
}
function parseHtml(html) {
  const root = new El('#doc');
  const stack = [root];
  const src = html.replace(/<!--[\s\S]*?-->/g, '').replace(/<!doctype[^>]*>/i, '').replace(/<script[\s\S]*?<\/script>/g, '');
  for (const m of src.matchAll(/<(\/?)([a-zA-Z][\w-]*)([^>]*?)(\/?)>|([^<]+)/g)) {
    if (m[5] !== undefined) { if (m[5].trim()) { const t = new El('#text'); t._text = m[5]; stack[stack.length - 1].append(t); } continue; }
    const [, close, tag, rest] = m;
    if (close) { stack.pop(); continue; }
    const attrs = {}; for (const a of rest.matchAll(/([\w:-]+)(?:="([^"]*)")?/g)) attrs[a[1]] = a[2] ?? '';
    const el = new El(tag.toLowerCase(), attrs);
    stack[stack.length - 1].append(el);
    if (!VOID.has(tag.toLowerCase()) && !m[4]) stack.push(el);
  }
  return root;
}

// ---------------------------------------------------------------- the fake QED64 page
const SIM = {};
const needsMathlib = (t) => t.split('\n').some((l) => /^\s*import\s+(Mathlib|Batteries|MIL|QED64)\b/.test(l));
function makeQed(pw, bootText, overlay) {
  const region = (SIM.overlays[overlay] || {}).imports || [];
  const W = { phase: 'booting', version: null, header: null };
  const relay = { state: { kind: 'rebooting' }, lastText: '', lastDeath: null, stats: { rangedChanges: 0 } };
  let n = 0;
  const mk = (opts) => {
    const snaps = (opts && opts.snapshots) || (needsMathlib(relay.lastText || bootText) ? ['init', 'mathlib'] : ['init']);
    const s = { id: `s${++n}`, snapshots: snaps, initialBytes: snaps.includes('mathlib') ? 2048 * MiB : 256 * MiB, lean: { request: async () => ({ memory: { initialBytes: relay.session.initialBytes, currentBytes: relay.session.initialBytes } }) } };
    return s;
  };
  relay.makeSession = mk;
  const model = { text: bootText, getValue() { return this.text; }, setValue(t) { this.text = t; SIM.setValueCalls++; setTimeout(() => didChange(t), 10); setTimeout(() => SIM.storage.set('qed64.buffer', this.text), 50); }, getLineCount() { return this.text.split('\n').length; } };
  let pos = { lineNumber: 1, column: 1 };
  const editor = { getModel: () => model, setPosition(p) { pos = { ...p }; SIM.positions.push({ ...p }); }, getPosition: () => pos, revealLineInCenter() {}, focus() { SIM.editorFocus++; }, layout() { SIM.layouts++; }, pushUndoStop() {}, executeEdits() {} };
  function verdict(text, sess) {
    const mods = text.split('\n').filter((l) => /^\s*import\s/.test(l)).map((l) => l.trim().split(/\s+/)[1]);
    const covered = sess.snapshots.includes('mathlib') ? ['Mathlib', ...region] : [];
    const missing = mods.filter((m) => !covered.includes(m));
    return missing.length ? { phase: 'headerRefused', header: { mode: 'refused', missing } } : { phase: 'ready', header: { mode: mods.length ? 'covered' : 'exact', missing: [] } };
  }
  function elaborate(text) {
    if (relay.state.kind !== 'serving') return;
    W.phase = 'elaborating'; W.version = (W.version || 0) + 1;
    const sess = relay.session;
    if (SIM.stuck || SIM.busy) { SIM.stuckVersions.push(W.version); return; } // L7 model (stuck) / a slow command (busy): never finishes this version
    setTimeout(() => { if (relay.session === sess && relay.state.kind === 'serving') Object.assign(W, verdict(text, sess)); }, SIM.elabMs);
  }
  function bootSession(sess, delay, reason = 'boot') {
    relay.state = { kind: 'rebooting', reason }; W.phase = 'booting';
    const go = () => { if (relay.session !== sess) return; relay.state = { kind: 'serving' }; elaborate(relay.lastText); };
    if (SIM.holdBoot) { SIM.releaseBoot = go; return; } // a slow first visit: the test decides when the download is done
    setTimeout(go, delay);
  }
  function didChange(t) {
    relay.lastText = t;
    if (relay.state.kind === 'halted') { relay.lastDeath = null; relay.session = relay.makeSession(); SIM.rearms++; bootSession(relay.session, 30); return; }
    elaborate(t);
  }
  relay.restart = (opts) => { if (relay.state.kind !== 'serving') return; SIM.restarts.push({ opts, from: relay.session.id }); relay.session = relay.makeSession(opts); bootSession(relay.session, 60); };
  relay.toClient = (m) => { SIM.toClient.push(m && (m.method || `reply:${m.id}`)); }; // the gallery's progress tap wraps this
  // the liveness probe's path (lsp-relay.ts fromClient): the open document, and hover replies through toClient (the
  // gallery's tap must swallow them). SIM.stuck: no reply (L7 model); SIM.busy: elaborating forever, yet replies (alive)
  relay.doc = { uri: 'file:///Probe.lean', languageId: 'lean4', version: 1 };
  relay.fromClient = (m) => {
    SIM.fromClient.push(m);
    // the gallery's main-loop probe (an unknown method WITH params): Lean's FileWorker main loop answers MethodNotFound at
    // once, without a pool thread (so also when SIM.noHover models a saturated pool). SIM.stuck (L7) and SIM.noMain: no reply.
    if (m.method === '$/showcase/liveness' && m.id !== undefined) {
      if (!m.params || typeof m.params !== 'object') { SIM.badRequests++; return; } // a FileWorker would die here
      if (SIM.stuck || SIM.noMain) return;
      setTimeout(() => relay.toClient({ jsonrpc: '2.0', id: m.id, error: { code: -32601, message: `No request handler found for '${m.method}'` } }), SIM.mainMs);
      return;
    }
    if (m.method !== 'textDocument/hover' || m.id === undefined) return;
    const p = m.params;
    if (!p || !p.textDocument || typeof p.textDocument.uri !== 'string' || !p.position) { SIM.badRequests++; return; } // a FileWorker would die here
    if (SIM.stuck || SIM.noHover) return; // noHover: a saturated task pool (the hover waits for a free thread; Lean is alive)
    setTimeout(() => relay.toClient({ jsonrpc: '2.0', id: m.id, result: null }), SIM.hoverMs);
  };
  relay.status = () => ({ phase: relay.state.kind === 'halted' ? 'halted' : W.phase, version: W.version, header: W.header && { ...W.header, version: 1, key: [] }, session: relay.session.id, relay: relay.state.kind, lastDeath: relay.lastDeath, collision: null,
    // QED64 9fdf9b8+ (SIM.builtIn): the worker's own liveness counters and the relay's reboot reason (lsp-relay.ts)
    ...(SIM.builtIn ? { liveness: { ...SIM.qlive }, rebootReason: relay.state.kind === 'rebooting' ? relay.state.reason : null } : {}) });
  // QED64's own liveness declaring the session wedged: died "wedged", the relay reboots a fresh session and replays the text
  SIM.qedWedge = () => { const from = relay.session.id; relay.lastDeath = { reason: 'wedged', message: 'simulated: the Lean runtime stopped answering' }; relay.session = relay.makeSession(); SIM.qedReboots.push({ from, to: relay.session.id }); SIM.qlive = { probes: 0, answered: 0, stalls: 0, resumed: 0, rescues: 0 }; bootSession(relay.session, 700, 'wedged'); };
  // the relay constructor: first session (commit decided NOW, before globalThis.qed64 exists) + boot
  relay.lastText = bootText;
  relay.session = mk();
  SIM.firstSessions.push({ id: relay.session.id, initialBytes: relay.session.initialBytes, snapshots: relay.session.snapshots, qed64Assigned: !!pw.qed64 });
  bootSession(relay.session, SIM.bootMs);
  SIM.halt = () => { relay.state = { kind: 'halted' }; relay.lastDeath = { reason: 'crash', message: 'simulated' }; };
  // the page's status sink (bundle: globalThis.qed64.ui = the pill + boot card; resident-session.ts / the snapshot prefetch
  // call ui.progress(label, {phase, loaded, total, unit}) through the object, so a same-origin wrapper sees every call)
  const ui = { busy(l) { SIM.uiSeen.push(['busy', l]); }, progress(l, i) { SIM.uiSeen.push(['progress', l, i && i.loaded]); }, idle(l) { SIM.uiSeen.push(['idle', l]); } };
  return { relay, ui, artifacts: {}, status: () => relay.status(), get editor() { return editor; } };
}
function makePage(src) {
  const url = new URL(src, ORIGIN);
  const overlay = (url.searchParams.get('snapshots') || '').replace(/^snapshots\//, '');
  const listeners = [];
  const styles = [];
  const doc = {
    readyState: 'loading', head: { append: (el) => styles.push(el) },
    // #bar: the page's top bar (the gallery puts its slow-download notice below it); the frame fills the stage from its top
    getElementById: (id) => id === 'bar' ? { getBoundingClientRect: () => ({ top: 0, bottom: 35 }) } : id === 'bootcard' ? { classList: { contains: (c) => c === 'failed' && doc._failed } } : id === 'bootlabel' ? { textContent: 'runtime manifest: HTTP 404' } : /^qed64-showcase-/.test(id) ? styles.find((s) => s.id === id) || null : null,
    createElement: () => { const el = { id: '', textContent: '', remove: () => styles.splice(styles.indexOf(el), 1) }; return el; },
    _styles: styles, _failed: false,
  };
  const pw = {
    location: { href: url.href, pathname: url.pathname, search: url.search }, document: doc,
    addEventListener: (t, fn, cap) => listeners.push({ t, fn, cap }), dispatchEvent: (ev) => { for (const l of listeners) if (l.t === ev.type) l.fn(ev); },
    MessageEvent: class { constructor(t, i) { this.type = t; Object.assign(this, i); } }, focus() { SIM.pageFocus++; }, _listeners: listeners,
    // resource timing: the entries the test pushes into SIM.resources (a retry loop re-fetching one URL adds entries too)
    performance: { getEntriesByType: (t) => (t === 'resource' ? SIM.resources.slice() : []) },
  };
  const bootText = SIM.storage.get('qed64.buffer') ?? '-- stock EXAMPLES.mathlib\nimport Mathlib.Basic.Real.Basic\n';
  setTimeout(() => {
    doc.readyState = 'interactive';
    if (SIM.pageBootFail) { doc._failed = true; return; }
    pw.qed64 = makeQed(pw, bootText, overlay); // assigned right after the relay (and its first session) exist
  }, 15);
  setTimeout(() => { doc.readyState = 'complete'; SIM.frame.dispatch('load'); }, 25);
  return pw;
}

// ---------------------------------------------------------------- environment per run
function setupEnv({ search = '', hash = '', overlays = {}, storage = {}, narrow = false, bootMs = 60, elabMs = 40, pageBootFail = false, builtIn = false, caps = {}, holdBoot = false }) {
  const html = fs.readFileSync(path.join(G, 'index.html'), 'utf8');
  const root = parseHtml(html);
  const byIdEl = (id) => { for (const e of root.walk()) if (e.id === id) return e; return null; };
  const blank = { location: { href: 'about:blank' }, document: { readyState: 'complete' }, focus() {} };
  Object.assign(SIM, { overlays, storage: new Map(Object.entries(storage)), fetchLog: [], navigations: [], positions: [], setValueCalls: 0, rearms: 0, editorFocus: 0, pageFocus: 0, layouts: 0, firstSessions: [], clipboard: null, bootMs, elabMs, pageBootFail, page: null, stuck: false, busy: false, noHover: false, stuckVersions: [], restarts: [], toClient: [], fromClient: [], badRequests: 0, hoverMs: 20, noMain: false, mainMs: 5, builtIn, qlive: { probes: 0, answered: 0, stalls: 0, resumed: 0, rescues: 0 }, qedReboots: [], holdBoot, releaseBoot: null, uiSeen: [], resources: [] });
  const frame = byIdEl('qed64-frame');
  SIM.frame = frame; frame._win = blank;
  Object.defineProperty(frame, 'src', {
    get() { return frame._src || ''; },
    set(v) {
      frame._src = v; SIM.navigations.push({ src: v, fetchesBefore: SIM.fetchLog.length, buffer: SIM.storage.get('qed64.buffer') });
      if (v === 'about:blank') { if (SIM.page) SIM.page._unloaded = true; SIM.page = null; frame._win = blank; return; }
      setTimeout(() => { SIM.page = makePage(v); frame._win = SIM.page; }, 5);
    },
  });
  Object.defineProperty(frame, 'contentWindow', { get: () => frame._win, configurable: true });
  Object.defineProperty(frame, 'contentDocument', { get: () => frame._win && frame._win.document, configurable: true });
  const docListeners = {};
  const doc = {
    activeElement: null, title: '', body: new El('body'),
    getElementById: byIdEl, createElement: (t) => new El(t),
    addEventListener: (t, fn) => (docListeners[t] ||= []).push(fn), execCommand: () => true,
    _dispatch: (t, ev) => { for (const fn of docListeners[t] || []) fn({ type: t, preventDefault() {}, ...ev }); },
  };
  SIM.doc = doc; SIM.root = root; SIM.byIdEl = byIdEl;
  const winListeners = {};
  const loc = { origin: ORIGIN, pathname: '/showcase/', search, hash, href: `${ORIGIN}/showcase/${search}${hash}` };
  const g = globalThis;
  const def = (k, v) => Object.defineProperty(g, k, { value: v, configurable: true, writable: true });
  def('window', g); def('document', doc); def('location', loc);
  // browser capabilities (default: a capable Chromium; caps.coi/sab/m64/wasm false remove one, caps.deviceMemory sets it)
  def('crossOriginIsolated', caps.coi !== false);
  def('SharedArrayBuffer', caps.sab === false ? undefined : REAL.SharedArrayBuffer);
  def('WebAssembly', caps.wasm === false ? undefined : caps.m64 === false ? { ...REAL.WebAssembly, validate: () => false, Memory: REAL.WebAssembly.Memory } : REAL.WebAssembly);
  def('BigInt', REAL.BigInt);
  def('history', { replaceState: (_s, _t, u) => { if (u.startsWith('#')) loc.hash = u; } });
  def('localStorage', { getItem: (k) => SIM.storage.has(k) ? SIM.storage.get(k) : null, setItem: (k, v) => SIM.storage.set(k, String(v)) });
  def('navigator', { clipboard: { writeText: async (t) => { SIM.clipboard = t; } }, ...(caps.deviceMemory !== undefined ? { deviceMemory: caps.deviceMemory } : {}) });
  def('getComputedStyle', (el) => ({ display: el.id === 'rail' && narrow ? 'none' : 'flex' }));
  def('requestAnimationFrame', (fn) => setTimeout(fn, 16));
  g.matchMedia = () => ({ matches: narrow, addEventListener() {} });
  g.addEventListener = (t, fn) => (winListeners[t] ||= []).push(fn);
  g.focus = () => {};
  SIM.fireWin = (t) => { for (const fn of winListeners[t] || []) fn({ type: t }); };
  g.fetch = async (url, init = {}) => {
    const u = new URL(url, `${ORIGIN}/showcase/`);
    SIM.fetchLog.push({ path: u.pathname, method: init.method || 'GET', navigations: SIM.navigations.length });
    const res = (status, ct, body = '', extra = {}) => { const h = new Map(Object.entries({ 'content-type': ct, ...extra })); return { ok: status >= 200 && status < 300, status, headers: { get: (k) => h.get(k.toLowerCase()) ?? null }, text: async () => body, json: async () => JSON.parse(body) }; };
    if (u.pathname.startsWith('/showcase/')) { const f = path.join(G, u.pathname.slice(10)); return fs.existsSync(f) ? res(200, 'application/json', fs.readFileSync(f, 'utf8')) : res(404, 'text/plain'); }
    if (u.pathname === `/runtime/runtime-manifest.${PIN.buildId}.json`) return res(200, 'application/json', JSON.stringify({ buildId: PIN.buildId, leanVersion: '4.34.0' }));
    const m = /^\/snapshots\/([^/]+)\/(.*)$/.exec(u.pathname);
    const ov = m && overlays[m[1]];
    if (!ov) return res(404, 'text/plain');
    const index = { schema: 'qed64.snapshot-index/v1', snapshots: [
      { name: 'init', url: '/snapshots/init.35c8c5f5419e0c33.snapz', digest: `sha256:${'a'.repeat(64)}`, bytes: 1, transfer: 1000, imports: [], runtime: PIN.buildId },
      { name: 'mathlib', url: '/snapshots/widgets.0123456789abcdef.snapz', digest: `sha256:${'b'.repeat(64)}`, bytes: 2, transfer: 2000, imports: ov.imports, runtime: ov.runtime || PIN.buildId },
    ] };
    if (m[2] === 'index.json') return res(200, 'application/json', JSON.stringify(index));
    const e = index.snapshots.find((x) => x.url.split('/').pop() === m[2]);
    return e ? res(200, 'application/octet-stream', '', { 'content-length': String(e.transfer) }) : res(404, 'text/plain');
  };
  vm.runInThisContext(fs.readFileSync(path.join(G, 'qed64-bridge.js'), 'utf8'), { filename: 'qed64-bridge.js' });
}
let runN = 0;
async function loadGallery() { await import(`${pathToFileURL(path.join(G, 'gallery.js')).href}?run=${++runN}`); return globalThis.__showcase; }
const ALL7 = ['QED64.Essential', 'ChartKit', 'ExprXRay', 'GraphScope', 'HasseView', 'IntervalInspector', 'SimpLens', 'TreeScope'];
const st = () => globalThis.__showcase.status();
const settled = (p) => p.then((v) => ({ ok: true, v }), (e) => ({ ok: false, e }));

// ================================================================ run 1: default boot (widgets8 absent → widgets7), deep link, user buffer saved
console.log('\n== run 1: boot via fallback overlay, deep link #hasse-view, user buffer preserved');
setupEnv({ hash: '#hasse-view', overlays: { widgets7: { imports: ALL7 } }, storage: { 'qed64.buffer': 'theorem mine : True := trivial\n' } });
let api = await loadGallery();
await until(() => st().phase === 'ready', 8000, 'run1 ready');
let s = st();
const nav0 = SIM.navigations.find((n) => n.src !== 'about:blank');
ok(s.shown === 'hasse-view' && s.overlay === 'widgets7' && s.fellBack === true && /widgets8 is not built yet; using widgets7/.test(s.notice || ''), `deep link booted hasse-view on widgets7 (fallback), notice: "${s.notice}"`);
ok(nav0 && nav0.src === '/?snapshots=snapshots/widgets7' && SIM.fetchLog.slice(0, nav0.fetchesBefore).some((f) => f.method === 'HEAD') && SIM.fetchLog.slice(0, nav0.fetchesBefore).filter((f) => f.path.includes('/snapshots/')).length >= 4,
  `preflight (index + ${SIM.fetchLog.slice(0, nav0.fetchesBefore).filter((f) => f.method === 'HEAD').length} HEADs) ran before navigating to ${nav0 && nav0.src}`);
ok(SIM.storage.get('qed64-showcase:saved') === 'theorem mine : True := trivial\n' && nav0.buffer === byId['hasse-view'].text, 'user buffer saved under qed64-showcase:saved; qed64.buffer seeded with the example before navigation');
{ // the veil is out of the accessibility tree and the focus order once it is hidden (hardening lane)
  const v = SIM.byIdEl('stage-veil');
  ok(v.classList.contains('is-hidden') && v.getAttribute('aria-hidden') === 'true' && v.getAttribute('inert') === '' && v.inert === true && s.caps && s.caps.ok === true && s.caps.missing.length === 0,
    `ready: the veil is hidden with aria-hidden="true" and inert; capabilities ok (${s.caps && s.caps.checks.map((c) => `${c.id} ${c.ok ? 'ok' : 'x'}`).join(', ')})`);
}
const inst = s.bridge.installs[0];
ok(inst && inst.readyState === 'loading' && inst.qed64Present === false && s.bridge.installed, `bridge installed at readyState '${inst && inst.readyState}' before globalThis.qed64 existed (reason ${inst && inst.reason})`);
ok(SIM.firstSessions[0].initialBytes === 2048 * MiB && SIM.firstSessions[0].qed64Assigned === false, 'model check: the first session (2 GiB, [init,mathlib]) existed before globalThis.qed64');
ok(s.cursor && s.cursor.lineNumber === byId['hasse-view'].firstCursor.lineNumber && s.cursor.column === 1 && SIM.editorFocus > 0 && SIM.pageFocus > 0, `cursor at L${s.cursor && s.cursor.lineNumber}:${s.cursor && s.cursor.column} (= first @ux cursor) and editor focused`);
ok(api.currentText() === byId['hasse-view'].text && api.bridgeStats() && api.bridgeStats().stripped === 0, 'currentText() is the example; bridgeStats() readable');
const chips = Object.fromEntries(EX.map((e) => [e.id, SIM.byIdEl('card-list').querySelectorAll('.card').find((c) => c.dataset.id === e.id).querySelector('.chip').textContent]));
ok(chips['hasse-view'] === 'live' && chips['dist-lens'] === 'not in widgets7' && chips['chart-kit'] === 'available', `chips: hasse-view=${chips['hasse-view']}, dist-lens=${chips['dist-lens']}, chart-kit=${chips['chart-kit']}`);
ok(location.hash === '#hasse-view' && document.title.startsWith('HasseView'), 'hash and title follow the selection');

// switch
const v0 = SIM.setValueCalls;
let r = await api.select('simp-lens');
ok(r.shown === 'simp-lens' && api.currentText() === byId['simp-lens'].text && r.cursor.lineNumber === byId['simp-lens'].firstCursor.lineNumber && SIM.setValueCalls === v0 + 1 && r.lastSwitchMs != null,
  `select('simp-lens') → ready at L${r.cursor.lineNumber}, one setValue, switch ${Math.round(r.lastSwitchMs)} ms`);
// storm: 6 selections without waiting; the last wins
const storm = ['chart-kit', 'expr-xray', 'tree-scope', 'interval-inspector', 'chart-kit', 'graph-scope'].map((id) => settled(api.select(id)));
const out = await Promise.all(storm);
s = st();
ok(out[5].ok && s.shown === 'graph-scope' && api.currentText() === byId['graph-scope'].text && out.slice(0, 5).every((x) => !x.ok && x.e.code === 'SUPERSEDED'),
  `storm of 6: last (graph-scope) resolves, first 5 rejected SUPERSEDED; ${SIM.setValueCalls - v0 - 1} setValue calls`);
// refused header (DistLens not in widgets7)
r = await api.select('dist-lens');
ok(r.phase === 'refused' && /refused the header: DistLens is not in the widgets7 overlay/.test(r.notice || '') && r.qed64 && r.qed64.phase === 'headerRefused' && r.qed64.header.missing[0] === 'DistLens', `dist-lens on widgets7 → phase refused (live qed64 ${r.qed64 && r.qed64.phase}, missing ${r.qed64 && r.qed64.header.missing}), notice "${r.notice}"`);
r = await api.select('tree-scope');
ok(r.phase === 'ready' && r.notice === null, 'next available example clears the refusal notice');
// reset on identical text
const v1 = SIM.setValueCalls;
SIM.byIdEl('reset-btn').click();
await sleep(30);
await until(() => st().phase === 'ready', 5000, 'reset ready');
ok(SIM.setValueCalls === v1 + 1 && st().shown === 'tree-scope', 'Reset example: setValue on identical text, back to ready');
// halted relay: monitor shows the card; Reset re-arms
SIM.halt();
await until(() => st().phase === 'halted', 3000, 'halted card');
ok(!SIM.byIdEl('error-card').hidden && /stopped/.test(SIM.byIdEl('error-title').textContent), `halted relay → card "${SIM.byIdEl('error-title').textContent}"`);
SIM.byIdEl('reset-btn').click();
await sleep(30);
await until(() => st().phase === 'ready', 5000, 'ready after halted reset');
ok(SIM.rearms === 1 && SIM.byIdEl('error-card').hidden, 'Reset on a halted relay: didChange re-armed it (1 rearm), card closed');
// hint on another card: loads that example and puts the cursor on the hint line
const ivHint = byId['interval-inspector'].tryThis.find((h) => h.kind === 'select');
const ivCard = SIM.byIdEl('card-list').querySelectorAll('.card').find((c) => c.dataset.id === 'interval-inspector');
ivCard.querySelector('.card-main').click();
await until(() => st().phase === 'ready' && st().shown === 'interval-inspector', 5000, 'iv');
const hintBtn = ivCard.querySelectorAll('.hint').find((b) => b.textContent.includes(ivHint.label));
ok(!!hintBtn, `current card renders its hints (found “${ivHint.label}”)`);
hintBtn.click();
await sleep(20);
ok(st().cursor.lineNumber === ivHint.lineNumber, `hint button moves the cursor to L${ivHint.lineNumber}`);
// keyboard roving on the rail
const cards = SIM.byIdEl('card-list').querySelectorAll('.card-main');
const cur = cards.find((b) => b.dataset.id === 'interval-inspector');
SIM.byIdEl('card-list').dispatch('keydown', { key: 'ArrowDown', target: cur });
const next = cards[cards.indexOf(cur) + 1];
ok(document.activeElement === next && next.tabIndex === 0 && cur.tabIndex === -1, `ArrowDown moves focus to ${next.dataset.id} (roving tabindex)`);
SIM.byIdEl('card-list').dispatch('keydown', { key: 'End', target: next });
ok(document.activeElement === cards[cards.length - 1], 'End focuses the last card');
// copy
SIM.byIdEl('copy-btn').click();
await sleep(20);
ok(SIM.clipboard === byId['interval-inspector'].text && /Copied/.test(SIM.byIdEl('copy-label').textContent), 'Copy for VS Code copies the example text');
// hashchange deep link
location.hash = '#chart-kit'; SIM.fireWin('hashchange');
await until(() => st().phase === 'ready' && st().shown === 'chart-kit', 5000, 'hash');
ok(api.currentText() === byId['chart-kit'].text, 'hashchange #chart-kit switches the example');
// external reload (the page's own Reload button): the old page fires pagehide, the new one commits ~5 ms later
const navs = SIM.navigations.length, installs = st().bridge.installs.length;
await sleep(120); // let the 50 ms buffer save land, as the real page's 400 ms debounce would
SIM.page.dispatchEvent({ type: 'pagehide' });
SIM.frame._win = { location: { href: 'about:blank' }, document: { readyState: 'loading' }, focus() {} };
await sleep(5);
SIM.page = makePage(SIM.frame._src); SIM.frame._win = SIM.page;
await sleep(60);
await until(() => st().phase === 'ready' && st().booted, 5000, 'adopt');
const reIns = st().bridge.installs[installs];
ok(SIM.navigations.length === navs && st().bridge.installs.length === installs + 1 && reIns.readyState === 'loading' && reIns.reason === 'commit-poll' && st().shown === 'chart-kit',
  `external reload adopted: no new navigation; bridge reinstalled at readyState '${reIns && reIns.readyState}' (${reIns && reIns.reason}, started by pagehide); restored buffer recognised as ${st().shown}`);
await sleep(300); // the status line renders every 250 ms
// status line text
// visible text: plain words (the example, "is ready"), no internals; the tooltip and the test API keep the detail
{
  const vis = SIM.byIdEl('status-text').textContent; const tip = SIM.byIdEl('status-line').title || ''; const api2 = st().statusLine || {};
  ok(/ChartKit/.test(vis) && / is ready\b/.test(vis) && !/header|session|qed64|covered/.test(vis) && /header covered/.test(tip) && /session s\d/.test(tip)
    && api2.text === vis && api2.detail === tip && SIM.byIdEl('status-line').dataset.phase === 'ready',
  `status line: plain "${vis}"; tooltip "${tip}"`);
}

// ================================================================ run 2: explicit overlay missing → no navigation; Retry after it appears
console.log('\n== run 2: ?overlay=widgets9 missing → preflight card, no navigation; Retry once it exists');
setupEnv({ search: '?overlay=widgets9', overlays: {} });
api = await loadGallery();
await until(() => st().phase === 'error', 5000, 'run2 error');
s = st();
ok(SIM.navigations.length === 0 && s.error.kind === 'preflight' && /widgets9/.test(s.error.title) && s.error.checks.some((c) => !c.ok && c.id === 'index-http'), `no navigation; card "${s.error.title}" with failing check index-http`);
ok(!SIM.byIdEl('error-card').hidden && SIM.byIdEl('error-checks').children.length >= 2 && !SIM.byIdEl('error-retry').hidden && !SIM.byIdEl('error-dismiss').hidden && !SIM.byIdEl('error-stock').hidden
  && SIM.byIdEl('stage-veil').getAttribute('aria-hidden') === 'true', 'error card visible with the check list, Try again, Dismiss and the stock link; the veil behind it is aria-hidden');
SIM.overlays.widgets9 = { imports: ALL7 };
SIM.byIdEl('error-retry').click();
await until(() => st().phase === 'ready', 8000, 'run2 retry ready');
ok(st().overlay === 'widgets9' && SIM.navigations.length === 1 && SIM.byIdEl('error-card').hidden, 'Try again → preflight passes, boots, card hidden');

// ================================================================ run 3: unpaired runtime → refused before navigation
console.log('\n== run 3: unpaired widgets8 → refused before navigation');
setupEnv({ overlays: { widgets8: { imports: ALL7, runtime: 'wasm64-0000000000000000' } } });
api = await loadGallery();
await until(() => st().phase === 'error', 5000, 'run3 error');
s = st();
ok(SIM.navigations.length === 0 && s.preflight.attempts[0].failed.includes('entry-mathlib-runtime') && /not paired/.test(s.error.detail), `no navigation; failed [${s.preflight.attempts[0].failed}]; "${s.error.detail.slice(0, 80)}…"`);

// ================================================================ run 4: ?mem=3 → light first session, wrapped restart loads the region at 3 GiB
console.log('\n== run 4: ?mem=3 (X5 knob)');
setupEnv({ search: '?mem=3', hash: '#graph-scope', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } } });
api = await loadGallery();
await until(() => st().phase === 'ready', 8000, 'run4 ready');
s = st();
const navBuf = SIM.navigations[0].buffer;
ok(navBuf.startsWith('-- QED64 showcase:') && !/^\s*import/m.test(navBuf), 'seeded a placeholder with no import lines');
ok(SIM.firstSessions[0].initialBytes === 256 * MiB && SIM.firstSessions[0].snapshots.join() === 'init', 'first session boots light: [init] at 256 MiB');
ok(s.mem.wrapped && s.mem.applied === true && s.mem.sessions.length === 1 && s.mem.sessions[0].initialBytes === 3 * GiB && s.mem.sessions[0].snapshots.join() === 'init,mathlib' && s.qed64.session !== s.mem.light.session,
  `restarted session ${s.qed64.session} has initialBytes ${s.mem.sessions[0] && s.mem.sessions[0].initialBytes / GiB} GiB with [${s.mem.sessions[0] && s.mem.sessions[0].snapshots}]`);
ok(s.shown === 'graph-scope' && api.currentText() === byId['graph-scope'].text && s.cursor.lineNumber === byId['graph-scope'].firstCursor.lineNumber, 'then the example is checked on the wrapped session and the cursor set');
SIM.halt(); SIM.byIdEl('reset-btn').click(); await sleep(30);
await until(() => st().phase === 'ready', 5000, 'run4 rearm');
s = st();
ok(s.mem.applied !== false && globalThis.__showcase && SIM.rearms === 1 && SIM.frame._win.qed64.relay.session.initialBytes === 3 * GiB, 'a re-armed session after a halt also gets the 3 GiB commit (wrapper stays on the relay)');

// ================================================================ run 5: the page's own boot failure card; narrow layout stacking
console.log('\n== run 5: page boot failure (#bootcard.failed); narrow screen');
setupEnv({ overlays: { widgets8: { imports: ALL7 } }, pageBootFail: true, narrow: true });
api = await loadGallery();
await until(() => st().phase === 'error', 5000, 'run5 error');
s = st();
ok(s.error.kind === 'boot' && /could not start/.test(s.error.title) && /runtime manifest: HTTP 404/.test(s.error.detail), `page boot failure → card "${s.error.title}: ${s.error.detail.slice(0, 40)}…"`);
SIM.pageBootFail = false;
SIM.byIdEl('error-retry').click();
await until(() => st().phase === 'ready', 8000, 'run5 retry');
await sleep(300);
ok(SIM.navigations.filter((n) => n.src === 'about:blank').length === 1 && SIM.page && SIM.page.document._styles.some((x) => x.id === 'qed64-showcase-stack') && SIM.layouts > 0,
  'retry retired the old page via about:blank first; at narrow width the stack style is injected and Monaco re-laid out');
const sel = SIM.byIdEl('example-select');
sel.value = 'hasse-view'; sel.dispatch('change');
await until(() => st().phase === 'ready' && st().shown === 'hasse-view', 5000, 'select');
ok(api.currentText() === byId['hasse-view'].text && sel.children.length === 8, 'narrow select (8 options) switches the example');

// ================================================================ run 6: stage-B audit minors
console.log('\n== run 6: saved buffer never overwritten, malformed deep link, edited detection, restore, adopt lock');
const ORIG = 'theorem original : True := trivial\n', EDITED = 'theorem edited : True := trivial\n';
setupEnv({ hash: '#%', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } }, storage: { 'qed64.buffer': EDITED, 'qed64-showcase:saved': ORIG } });
api = await loadGallery();
await until(() => st().phase === 'ready', 8000, 'run6 ready');
s = st();
ok(s.shown === 'chart-kit' && /no example called “%”/.test(s.notice || ''), `malformed hash #% did not throw: booted ${s.shown}, notice "${s.notice}"`);
const hist = JSON.parse(SIM.storage.get('qed64-showcase:saved-history') || '[]');
ok(SIM.storage.get('qed64-showcase:saved') === ORIG && hist[0] === EDITED && s.seed.action === 'history', `existing qed64-showcase:saved kept; the displaced buffer went to the history (action ${s.seed.action}, ${hist.length} entry)`);
ok(SIM.byIdEl('restore-btn').hidden === false, '“Open my saved buffer” is offered');
SIM.page.qed64.editor.getModel().setValue(byId['chart-kit'].text + '\n-- my edit\n');
await until(() => st().edited === true, 3000, 'edited');
const chipEd = SIM.byIdEl('card-list').querySelectorAll('.card').find((c) => c.dataset.id === 'chart-kit').querySelector('.chip');
ok(chipEd.textContent === 'edited' && chipEd.dataset.state === 'edited', 'an edit is detected: the card chip reads “edited”');
await api.reset();
await sleep(300);
ok(st().edited === false && api.currentText() === byId['chart-kit'].text, 'Reset restores the example and clears “edited”');
ok(SIM.byIdEl('restore-pick').hidden === false && SIM.byIdEl('restore-pick').children.length === 2 && /^newest: theorem edited/.test(SIM.byIdEl('restore-pick').children[0].textContent),
  `two kept buffers: the chooser lists them newest first (${SIM.byIdEl('restore-pick').children.map((o) => o.textContent).join(' | ')})`);
SIM.byIdEl('restore-btn').click();
await sleep(60);
ok(api.currentText() === EDITED && st().custom === true && st().current === null, 'Open opens the NEWEST kept buffer (the history head), not the first one ever saved; no card is current');
ok(await api.restoreSaved(1) === true && api.currentText() === ORIG, 'restoreSaved(1) / the chooser reaches the first one ever saved');
// adopt lock: an external reload, then a selection while it is being adopted
const navs6 = SIM.navigations.length;
SIM.page.dispatchEvent({ type: 'pagehide' });
SIM.frame._win = { location: { href: 'about:blank' }, document: { readyState: 'loading' }, focus() {} };
await sleep(5);
SIM.page = makePage(SIM.frame._src); SIM.frame._win = SIM.page;
SIM.frame.dispatch('load');
await sleep(2);
const pSel = settled(api.select('tree-scope'));
try { await until(() => st().phase === 'ready' && st().shown === 'tree-scope', 8000, 'adopt then select'); } catch (e) { const x = st(); console.log('DEBUG', JSON.stringify({ phase: x.phase, current: x.current, shown: x.shown, booted: x.booted, op: x.op, err: x.error, q: x.qed64 })); throw e; }
const rSel = await pSel;
ok(rSel.ok && SIM.navigations.length === navs6, `a selection during an adopted reload waits for the adopted page (no second navigation: ${SIM.navigations.length - navs6})`);
// a second launch with the saved value present and a fresh user buffer: still never overwritten
setupEnv({ overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } }, storage: { 'qed64.buffer': 'theorem third : True := trivial\n', 'qed64-showcase:saved': ORIG, 'qed64-showcase:saved-history': JSON.stringify([EDITED]) } });
api = await loadGallery();
await until(() => st().phase === 'ready', 8000, 'run6b ready');
const hist2 = JSON.parse(SIM.storage.get('qed64-showcase:saved-history'));
ok(SIM.storage.get('qed64-showcase:saved') === ORIG && hist2.length === 2 && hist2[0] === 'theorem third : True := trivial\n' && hist2[1] === EDITED, 'third visit: saved still the original; history newest-first [third, edited]');
// a gallery-edited example persisted by the page is NOT a user buffer: its own slot, the history is untouched
const EXEDIT = `${byId['tree-scope'].text}\n-- my edit of the example\n`;
setupEnv({ overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } }, storage: { 'qed64.buffer': EXEDIT, 'qed64-showcase:saved': ORIG, 'qed64-showcase:saved-history': JSON.stringify([EDITED]) } });
api = await loadGallery();
await until(() => st().phase === 'ready', 8000, 'run6c ready');
const hist3 = JSON.parse(SIM.storage.get('qed64-showcase:saved-history'));
ok(st().seed.action === 'example' && SIM.storage.get('qed64-showcase:edited-example') === EXEDIT && hist3.length === 1 && hist3[0] === EDITED && SIM.storage.get('qed64-showcase:saved') === ORIG,
  `an edited example from the last visit goes to qed64-showcase:edited-example (action ${st().seed.action}); saved and history unchanged`);

// ================================================================ run 7: the stall watchdog (QED64 L7), ?stall=5, liveness probe in OBSERVE mode
console.log('\n== run 7: stall watchdog: card after the threshold, Keep waiting re-arms, Restart Lean keeps the text, Reset restarts (liveness observe)');
setupEnv({ search: '?stall=5&liveness=observe&probe=1&probeTimeout=0.5', hash: '#graph-scope', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } } });
api = await loadGallery();
await until(() => st().phase === 'ready', 8000, 'run7 ready');
ok(st().stall.thresholdMs === 5000 && st().stall.tapped === true && st().stall.shown === 0 && st().stall.active === false, `?stall=5: threshold ${st().stall.thresholdMs} ms, relay tapped, no card on a healthy boot`);
const card = () => SIM.byIdEl('error-card');
const EDIT7 = `${byId['graph-scope'].text}-- typed\n`;
SIM.stuck = true;
const tStuck = Date.now();
SIM.frame._win.qed64.editor.getModel().setValue(EDIT7);
await sleep(3000);
ok(st().stall.active === false && card().hidden, 'no card before the threshold (3 s of 5 s)');
await until(() => st().stall.active, 8000, 'stall card');
const shownAt = Date.now() - tStuck;
ok(!card().hidden && st().error.kind === 'stalled' && st().error.soft === true && /stopped making progress/.test(SIM.byIdEl('error-title').textContent) && SIM.byIdEl('error-retry').textContent === 'Restart Lean' && SIM.byIdEl('error-reset').hidden === false && SIM.byIdEl('error-dismiss').textContent === 'Keep waiting',
  `card after ${shownAt} ms stuck: "${SIM.byIdEl('error-title').textContent}" [${SIM.byIdEl('error-retry').textContent}] [Reset example] [${SIM.byIdEl('error-dismiss').textContent}]`);
ok(st().phase === 'ready' && st().edited === true && st().qed64.phase === 'elaborating', 'the gallery stays usable (ready · edited) while QED64 is stuck');
{
  const lv = st().liveness; const w = lv.events.find((e) => e.source === 'wedged');
  ok(lv.mode === 'observe' && lv.wedged === 1 && lv.wedgedActive === true && w && w.action === 'observed' && lv.restarts === 0 && SIM.restarts.length === 0 && lv.sent === 2 && lv.missed === 2,
    `observe mode: 2 probes missed -> wedged recorded (action ${w && w.action}, ${w && w.idleMs} ms idle), no restart (${SIM.restarts.length})`);
}
SIM.byIdEl('error-dismiss').click();
const tKeep = Date.now();
ok(card().hidden && st().stall.active === false && st().error === null, 'Keep waiting hides the card and re-arms the watchdog');
await until(() => st().stall.active, 9000, 'stall card again');
ok(Date.now() - tKeep >= 4800 && st().stall.shown === 2, `the card comes back after another threshold (${Date.now() - tKeep} ms; shown ${st().stall.shown}×)`);
SIM.stuck = false;
const sess7 = SIM.frame._win.qed64.relay.session.id;
SIM.byIdEl('error-retry').click();
await until(() => st().qed64.phase === 'ready' && st().qed64.session !== sess7, 8000, 'restart ready');
const ev7 = st().stall.events;
ok(SIM.restarts.length === 1 && JSON.stringify(SIM.restarts[0].opts) === JSON.stringify({ snapshots: ['init', 'mathlib'] }) && ev7.some((e) => e.source === 'card' && e.how === 'relay.restart') && api.currentText() === EDIT7 && card().hidden && st().stall.active === false,
  `Restart Lean: relay.restart(${JSON.stringify(SIM.restarts[0] && SIM.restarts[0].opts)}) on session ${sess7} → ${st().qed64.session}, the edited text kept, card gone`);
// stuck again; the toolbar's Reset example on a stalled checker restarts it on the example
SIM.stuck = true;
SIM.frame._win.qed64.editor.getModel().setValue(`${EDIT7}-- again\n`);
await until(() => st().stall.active, 8000, 'stall card 3');
SIM.stuck = false;
SIM.byIdEl('reset-btn').click();
await until(() => st().phase === 'ready' && !st().edited && st().qed64.phase === 'ready' && api.currentText() === byId['graph-scope'].text, 8000, 'reset after stall');
ok(SIM.restarts.length === 2 && st().stall.events.some((e) => e.source === 'reset' && e.how === 'relay.restart') && card().hidden,
  `Reset example on the stalled checker restarted it (${SIM.restarts.length} restarts) on the example; card gone`);
// a stall card never replaces a hard card, and a dead/halted relay is not a stall
SIM.stuck = true;
SIM.frame._win.qed64.editor.getModel().setValue(`${EDIT7}-- third\n`);
await sleep(200);
SIM.halt();
await sleep(6000);
ok(st().stall.active === false && st().error && st().error.kind === 'halted', 'a halted relay shows the halted card, never the stall card');
SIM.stuck = false;

// ================================================================ run 8: the liveness probe in its default (auto) mode
console.log('\n== run 8: liveness probe: an alive-but-slow checker is never restarted; a wedged one is restarted once, then the card (rate limit)');
setupEnv({ search: '?stall=5&probe=1&probeTimeout=0.5&restartGap=20', hash: '#graph-scope', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } } });
api = await loadGallery();
await until(() => st().phase === 'ready', 8000, 'run8 ready');
ok(st().liveness.mode === 'auto' && st().liveness.probeAfterMs === 1000 && st().liveness.probeTimeoutMs === 500 && st().liveness.restartGapMs === 20000 && st().liveness.sent === 0,
  `default mode auto; ?probe=1&probeTimeout=0.5&restartGap=20 -> ${st().liveness.probeAfterMs}/${st().liveness.probeTimeoutMs}/${st().liveness.restartGapMs} ms; no probe on a healthy boot`);
const model8 = () => SIM.frame._win.qed64.editor.getModel();
// (1) alive but slow: elaborating with no progress for 4 s, every probe answered -> no restart, no card
SIM.busy = true;
model8().setValue(`${byId['graph-scope'].text}-- slow\n`);
await sleep(4000);
let lv = st().liveness;
ok(lv.sent >= 2 && lv.answered === lv.sent - (lv.outstanding ? 1 : 0) && lv.missed === 0 && lv.wedged === 0 && SIM.restarts.length === 0 && st().stall.active === false,
  `alive but slow (4 s silent): ${lv.sent} probes, ${lv.answered} answered (last ${lv.lastAnswerMs} ms), 0 missed, no restart, no card`);
const probes = SIM.fromClient.filter((m) => m.method === 'textDocument/hover');
ok(probes.length === lv.sent && probes.every((m) => typeof m.id === 'string' && /^showcase-live-\d+$/.test(m.id) && m.params.textDocument.uri === 'file:///Probe.lean' && m.params.position.line === 0 && m.params.position.character === 0) && SIM.badRequests === 0,
  `every probe is textDocument/hover with a string id (${probes.map((m) => m.id).slice(0, 3).join(', ')}, …) and params {textDocument: {uri}, position: 0:0}`);
ok(!SIM.toClient.some((x) => /^reply:showcase-live-/.test(String(x))), 'every probe reply was swallowed by the tap (none reached the editor side)');
SIM.busy = false;
model8().setValue(byId['graph-scope'].text);
await until(() => st().qed64.phase === 'ready', 8000, 'run8 settle');
// (2) wedged: two probes unanswered -> relay.restart with the session's snapshots, the text kept, a notice
const EDIT8 = `${byId['graph-scope'].text}-- wedged\n`;
const sess8 = SIM.frame._win.qed64.relay.session.id;
SIM.stuck = true;
const t8 = Date.now();
model8().setValue(EDIT8);
await until(() => SIM.restarts.length === 1, 8000, 'auto restart');
const restartAfter = Date.now() - t8;
SIM.stuck = false;
await until(() => st().qed64.phase === 'ready' && st().qed64.session !== sess8, 8000, 'auto restart ready');
lv = st().liveness;
const w8 = lv.events.find((e) => e.source === 'wedged');
ok(lv.restarts === 1 && lv.wedged === 1 && w8 && w8.action === 'relay.restart' && JSON.stringify(SIM.restarts[0].opts) === JSON.stringify({ snapshots: ['init', 'mathlib'] }) && api.currentText() === EDIT8,
  `wedged after ${restartAfter} ms (2 missed probes) -> relay.restart(${JSON.stringify(SIM.restarts[0].opts)}) on ${sess8} -> ${st().qed64.session}, the text kept`);
ok(/Lean stopped responding and was restarted/.test(st().notice || '') && st().error === null && st().stall.shown === 0 && st().stall.events.some((e) => e.source === 'liveness' && e.how === 'relay.restart'),
  `non-blocking notice "${st().notice}", no card`);
// (3) wedged again within restartGap: rate-limited, the 5 s card is the fallback
SIM.stuck = true;
model8().setValue(`${EDIT8}-- again\n`);
await until(() => st().stall.active, 9000, 'run8 fallback card');
lv = st().liveness;
ok(SIM.restarts.length === 1 && lv.rateLimited === 1 && lv.events.filter((e) => e.source === 'wedged').pop().action === 'rate-limited' && st().error.kind === 'stalled',
  `a second wedge within restartGap is not restarted (rate-limited ${lv.rateLimited}); the stall card is shown instead`);
SIM.stuck = false;
SIM.byIdEl('error-retry').click();
await until(() => st().qed64.phase === 'ready' && SIM.restarts.length === 2, 8000, 'run8 card restart');
ok(st().stall.events.some((e) => e.source === 'card' && e.how === 'relay.restart'), 'the card\'s Restart Lean still works after a rate-limited wedge');
// (4) observe and off through the test API
api.liveness('observe');
SIM.stuck = true;
model8().setValue(`${EDIT8}-- observed\n`);
await until(() => st().liveness.wedged === 3, 8000, 'observe wedge');
ok(SIM.restarts.length === 2 && st().liveness.events.filter((e) => e.source === 'wedged').pop().action === 'observed', '__showcase.liveness(\'observe\') switches to observe: the wedge is recorded, nothing restarted');
SIM.stuck = false;
api.liveness('off');
const sentOff = st().liveness.sent;
SIM.busy = true;
model8().setValue(`${EDIT8}-- off\n`);
await sleep(2500);
ok(st().liveness.mode === 'off' && st().liveness.sent === sentOff, `__showcase.liveness('off'): no probe in 2.5 s of silence (sent stays ${sentOff})`);
SIM.busy = false;
let threw = false; try { api.liveness('bogus'); } catch { threw = true; }
ok(threw, '__showcase.liveness(<unknown mode>) throws');

// ================================================================ run 9: a QED64 page with its OWN liveness (9fdf9b8+): the gallery defers
console.log('\n== run 9: QED64 liveness built in (status().liveness): the gallery defers, observes QED64\'s rescues/stalls/wedged reboots, and stays a slower fallback');
setupEnv({ search: '?stall=9&probe=1&probeDefer=3&probeTimeout=0.5&restartGap=20', hash: '#graph-scope', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } }, builtIn: true });
api = await loadGallery();
await until(() => st().phase === 'ready', 8000, 'run9 ready');
await until(() => st().liveness.qed64.builtIn, 2000, 'run9 detect');
lv = st().liveness;
ok(lv.qed64.builtIn && lv.deferring && lv.effectiveProbeAfterMs === 3000 && lv.probeAfterMs === 1000 && lv.probeDeferMs === 3000 && lv.events.some((e) => e.source === 'qed64-detected'),
  `status().liveness present -> builtIn, deferring; effective probe after ${lv.effectiveProbeAfterMs} ms (?probeDefer=3) instead of ${lv.probeAfterMs} ms`);
const model9 = () => SIM.frame._win.qed64.editor.getModel();
// (1) QED64's mailbox kick rescued a lost wakeup: counted and reported, nothing else happens
SIM.qlive = { ...SIM.qlive, probes: 2, answered: 2, rescues: 1 };
await sleep(400);
lv = st().liveness;
ok(lv.qed64.totals.rescues === 1 && lv.qed64.counters.rescues === 1 && lv.events.some((e) => e.source === 'qed64-rescue' && e.rescues === 1) && SIM.restarts.length === 0,
  `a QED64 rescue is reported (totals.rescues ${lv.qed64.totals.rescues}, event qed64-rescue), nothing restarted`);
// (2) a frozen checker that QED64 itself declares wedged before the deferral ends: the gallery sends no probe and restarts nothing
const EDIT9 = `${byId['graph-scope'].text}-- wedged on 2c18773e\n`;
const sess9 = SIM.frame._win.qed64.relay.session.id; const sent9 = st().liveness.sent;
SIM.stuck = true;
model9().setValue(EDIT9);
await sleep(1600); // past the old 1 s probe threshold, inside the 3 s deferral
ok(st().liveness.sent === sent9, `deferring: no gallery probe 1.6 s into the silence (the non-deferred threshold is 1 s; sent stays ${sent9})`);
SIM.qlive = { ...SIM.qlive, probes: 3, stalls: 1 }; // QED64's probe unanswered: its stall (grace window)
await sleep(400);
SIM.qedWedge(); SIM.stuck = false;
await until(() => st().liveness.qed64.wedgedReboots === 1, 3000, 'run9 qed64 wedged seen');
ok(/QED64 is restarting it/.test(st().notice || '') && st().liveness.events.some((e) => e.source === 'qed64-stall') && st().liveness.events.some((e) => e.source === 'qed64-wedged' && e.lastDeath && e.lastDeath.reason === 'wedged'),
  `QED64's stall and "wedged" reboot are observed (events qed64-stall, qed64-wedged), notice "${st().notice}"`);
await until(() => st().qed64.phase === 'ready' && st().qed64.session !== sess9 && !st().liveness.qed64.rebooting, 8000, 'run9 qed64 reboot ready'); // (the observer runs on the 250 ms monitor tick)
lv = st().liveness;
ok(SIM.restarts.length === 0 && lv.sent === sent9 && lv.wedged === 0 && st().stall.shown === 0 && api.currentText() === EDIT9 && lv.qed64.rebooting === false && lv.events.some((e) => e.source === 'qed64-rebooted') && lv.qed64.lastReboot.from === sess9 && lv.qed64.lastReboot.to === st().qed64.session,
  `the gallery did not race QED64: 0 gallery probes, 0 relay.restart, no card; QED64 rebooted ${lv.qed64.lastReboot.from} -> ${lv.qed64.lastReboot.to} with the text kept` + ` [restarts ${SIM.restarts.length} sent ${lv.sent}/${sent9} wedged ${lv.wedged} card ${st().stall.shown} text ${api.currentText() === EDIT9} rebooting ${lv.qed64.rebooting}]`);
// (3) QED64 in its stall grace window past the deferral: the gallery still waits (no probe)
const sent9b = st().liveness.sent;
SIM.stuck = true;
model9().setValue(`${EDIT9}-- stalled\n`);
SIM.qlive = { ...SIM.qlive, probes: 1, stalls: 1, resumed: 0 };
await sleep(4200);
ok(st().liveness.sent === sent9b && SIM.restarts.length === 0, `QED64 reports a stall (stalls 1 > resumed 0): no gallery probe 4.2 s into the silence (deferral 3 s)`);
SIM.qlive = { ...SIM.qlive, resumed: 1 }; // the stall ended (output resumed) yet the checker stays silent: QED64 did not act
// (4) the fallback: QED64's liveness never acts (counters quiet): the gallery probes after the deferral and restarts
const t9 = Date.now();
await until(() => SIM.restarts.length === 1, 9000, 'run9 fallback restart');
const after9 = Date.now() - t9;
SIM.stuck = false;
await until(() => st().qed64.phase === 'ready', 8000, 'run9 fallback ready');
lv = st().liveness;
const w9 = lv.events.filter((e) => e.source === 'wedged').pop();
ok(lv.restarts === 1 && w9 && w9.action === 'relay.restart' && w9.qed64 && w9.qed64.stalled === false && /Lean stopped responding and was restarted/.test(st().notice || '') && st().stall.shown === 0,
  `fallback: QED64 never acted -> the gallery's probe (after the 3 s deferral) declared it wedged and restarted it ${after9} ms after the stall ended; no card`);
// (5) a gallery wedge while QED64 reports a stall: 'deferred', no restart (QED64 reboots it; the card is the fallback)
SIM.stuck = true;
model9().setValue(`${EDIT9}-- deferred\n`);
await until(() => st().liveness.sent > lv.sent, 6000, 'run9 probe 5');
SIM.qlive = { ...SIM.qlive, stalls: 2, resumed: 1 }; // QED64 enters a stall while our probes are out
await until(() => st().liveness.events.some((e) => e.source === 'wedged' && e.action === 'deferred'), 6000, 'run9 deferred');
ok(SIM.restarts.length === 1 && st().liveness.deferred === 1, `a gallery wedge during a QED64 stall is 'deferred' (deferred ${st().liveness.deferred}), not restarted`);
SIM.stuck = false;

// ================================================================ run 10: proof of life besides the hover (final audit major) and the card's wording
console.log('\n== run 10: a saturated pool (hovers unanswered, Lean alive) is never restarted; the card says "still working" while Lean answers');
setupEnv({ search: '?stall=5&probe=1&probeDefer=2&probeTimeout=0.5&restartGap=20', hash: '#graph-scope', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } }, builtIn: true });
api = await loadGallery();
await until(() => st().phase === 'ready' && st().liveness.qed64.builtIn, 8000, 'run10 ready');
const model10 = () => SIM.frame._win.qed64.editor.getModel();
// (1) hovers unanswered, QED64's own probe answered about every 0.6 s (its FileWorker main loop answers without a pool thread)
SIM.busy = true; SIM.noHover = true;
let ticker = setInterval(() => { SIM.qlive = { ...SIM.qlive, probes: SIM.qlive.probes + 1, answered: SIM.qlive.answered + 1 }; }, 600);
model10().setValue(`${byId['graph-scope'].text}-- 24 parallel sleeps\n`);
await until(() => st().stall.active, 9000, 'run10 card');
lv = st().liveness;
ok(lv.sent >= 1 && lv.alive >= 1 && lv.aliveVia['qed64-answered'] >= 1 && lv.missed === 0 && lv.wedged === 0 && SIM.restarts.length === 0 && lv.events.some((e) => e.source === 'alive' && e.via === 'qed64-answered'),
  `hovers unanswered but QED64's probe answered: ${lv.sent} probe(s) settled 'alive' ${lv.alive}x (via qed64-answered ${lv.aliveVia['qed64-answered']}), missed ${lv.missed}, wedged ${lv.wedged}, restarts ${SIM.restarts.length}`);
ok(st().stall.variant === 'alive' && /Lean is still working/.test(SIM.byIdEl('error-title').textContent) && /answered \d+ s ago/.test(SIM.byIdEl('error-detail').textContent) && SIM.byIdEl('error-retry').textContent === 'Restart Lean' && SIM.byIdEl('error-dismiss').textContent === 'Keep waiting'
  && st().stall.events.some((e) => e.source === 'shown' && e.variant === 'alive'),
  `the card after ${st().stall.thresholdMs} ms without progress says "${SIM.byIdEl('error-title').textContent}" (variant alive), same buttons`);
// (2) QED64's answers stop: the card re-words itself to "stopped making progress", then the fallback restarts it. QED64's
// probe and the gallery's main-loop probe go to the same FileWorker main loop, so when one stops being answered so does
// the other (SIM.noMain).
clearInterval(ticker); SIM.noMain = true;
await until(() => SIM.restarts.length === 1, 9000, 'run10 fallback restart');
{
  const ev = st().stall.events; const iRe = ev.findIndex((e) => e.source === 'reworded' && e.variant === 'stopped'); const iRs = ev.findIndex((e) => e.source === 'liveness' && e.how === 'relay.restart');
  ok(iRe >= 0 && iRs > iRe && st().liveness.events.filter((e) => e.source === 'wedged').pop().action === 'relay.restart',
    `no sign of life for ${4 * 0.5} s: the card was re-worded to "stopped" (event reworded), then 2 missed probes -> relay.restart (fallback)`);
}
SIM.busy = false; SIM.noHover = false; SIM.noMain = false;
await until(() => st().qed64.phase === 'ready' && !st().stall.active, 8000, 'run10 settle');
// (3) without QED64's answers, any server frame the page receives is proof of life too
SIM.busy = true; SIM.noHover = true;
const rs10 = SIM.restarts.length; const alive10 = st().liveness.aliveVia.frame;
ticker = setInterval(() => SIM.frame._win.qed64.relay.toClient({ jsonrpc: '2.0', id: 4242, result: null }), 400);
model10().setValue(`${byId['graph-scope'].text}-- frames only\n`);
await sleep(4000);
lv = st().liveness;
ok(lv.aliveVia.frame > alive10 && SIM.restarts.length === rs10 && lv.events.some((e) => e.source === 'alive' && e.via === 'frame') && lv.frames > 0,
  `hovers unanswered, QED64 quiet, server frames arriving: settled 'alive' via frame (${lv.aliveVia.frame - alive10}x), no restart (frames seen ${lv.frames})`);
clearInterval(ticker);
SIM.busy = false; SIM.noHover = false;

// ================================================================ run 11: frames QED64's JS layer makes itself are no proof of life (close-out 3, audit minor)
console.log('\n== run 11: a frozen Lean side on a page WITHOUT QED64 liveness (rollback): QED64-synthesized frames do not keep it "alive"');
setupEnv({ search: '?stall=30&probe=1&probeTimeout=0.5&restartGap=20', hash: '#graph-scope', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } } });
api = await loadGallery();
await until(() => st().phase === 'ready', 8000, 'run11 ready');
ok(st().liveness.qed64.builtIn === false && st().liveness.syntheticFrames === 0, 'a page without status().liveness (the rollback page): only the frame signal is proof of life');
const model11 = () => SIM.frame._win.qed64.relay;
const rel11 = SIM.frame._win.qed64.relay;
const frames11 = st().liveness.frames; const sess11 = rel11.session.id;
SIM.stuck = true;
let n11 = 0; let answeredProbe11 = null;
// what QED64's JS layer keeps producing while the Lean side is frozen: the front door's ContentModified replies to
// completions on an import line (lsp-front-door.js:288), a halted-style -32603 reply, the relay's halted note; and the
// first probe answered by failInFlight-style -32603 (never by Lean)
const synth11 = setInterval(() => {
  const r = SIM.frame._win.qed64.relay; n11++;
  r.toClient({ jsonrpc: '2.0', id: 9000 + n11, error: { code: -32801, message: 'QED64: import-path completion is answered client-side; the worker has no module inventory' } });
  if (n11 % 3 === 0) r.toClient({ jsonrpc: '2.0', id: 9500 + n11, error: { code: -32603, message: 'QED64: checker halted after repeated crashes; edit the file to restart it' } });
  if (n11 % 4 === 0) r.toClient({ jsonrpc: '2.0', method: 'textDocument/publishDiagnostics', params: { uri: 'file:///Probe.lean', diagnostics: [{ range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } }, severity: 1, source: 'QED64', message: 'halted' }] } });
  const pr = SIM.fromClient.filter((m) => m.method === 'textDocument/hover').pop();
  if (pr && !answeredProbe11 && st().liveness.outstanding && st().liveness.outstanding.id === pr.id) { answeredProbe11 = pr.id; r.toClient({ jsonrpc: '2.0', id: pr.id, error: { code: -32603, message: 'QED64: restarting' } }); }
}, 150);
const rs11 = SIM.restarts.length;
SIM.frame._win.qed64.editor.getModel().setValue(`${byId['graph-scope'].text}-- frozen, JS layer chatty\n`);
await until(() => SIM.restarts.length === rs11 + 1, 9000, 'run11 restart').catch((e) => { console.log(JSON.stringify({ lv: st().liveness, q: st().qed64, stall: st().stall.events }).slice(0, 3000)); throw e; });
clearInterval(synth11);
SIM.stuck = false;
{
  const lv11 = st().liveness;
  const w11 = lv11.events.filter((e) => e.source === 'wedged').pop();
  ok(w11 && w11.action === 'relay.restart' && lv11.aliveVia.frame === 0 && lv11.alive === 0 && lv11.syntheticFrames >= 5 && lv11.frames === frames11 && SIM.restarts[rs11].from === sess11,
    `frozen with ${lv11.syntheticFrames} QED64-synthesized frames arriving: not counted as frames (${lv11.frames - frames11} new), never settled alive, wedged -> relay.restart`);
  ok(answeredProbe11 && lv11.syntheticReplies >= 1 && lv11.events.some((e) => e.source === 'synthetic-reply' && e.id === answeredProbe11) && !lv11.events.some((e) => e.source === 'answered' && e.id === answeredProbe11),
    `the probe ${answeredProbe11} answered by QED64's JS layer ('QED64: restarting', -32603) is a synthetic-reply, not an answer`);
}
await until(() => st().qed64.phase === 'ready' && st().qed64.session !== sess11, 8000, 'run11 settle');
// and a frame from Lean (a non-QED64 reply / notification) still counts
{ const f0 = st().liveness.frames; SIM.frame._win.qed64.relay.toClient({ jsonrpc: '2.0', id: 4343, result: null }); SIM.frame._win.qed64.relay.toClient({ jsonrpc: '2.0', id: 4344, error: { code: -32801, message: 'ContentModified' } });
  ok(st().liveness.frames === f0 + 2, 'a Lean reply, and a Lean error reply without the QED64: prefix, still count as frames'); }

// ================================================================ run 12: a LATE but real hover answer is proof of life (multi-pin lane, critic's minor)
console.log('\n== run 12: a page WITHOUT QED64 liveness (pin 1859b83): hovers answered only after the probe timeout keep the session alive; late = by elapsed time');
setupEnv({ search: '?stall=30&probe=1&probeTimeout=0.6&restartGap=20', hash: '#graph-scope', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } } });
api = await loadGallery();
await until(() => st().phase === 'ready', 8000, 'run12 ready');
{
  const rs12 = SIM.restarts.length; const sess12 = SIM.frame._win.qed64.relay.session.id;
  // A busy pool: elaborating forever, no frames, no main-loop answer (SIM.noMain isolates this signal), and every hover
  // answered 0.65 s after it was sent: 50 ms past a 0.6 s timeout, which the gallery's 250 ms monitor tick (the probe is
  // sent on a tick) checks only at 0.75 s, so every answer arrives BEFORE the tick looks (Node runs expired timers in
  // expiry order, so this holds under host load too). The gallery classifies a reply by its ELAPSED time (hardening lane),
  // not by tick order, so every one of these answers is late, never on time. Before, an answer the tick had not yet timed
  // out counted as on time (here: every one; in the docs lane a ~200 ms delayed loop did it to a 0.7 s answer against a
  // 0.5 s timeout, "5 probes, 2 missed, 2 late answers, alive 0x", and this test had been widened to 0.9 s; that margin is
  // gone: the answer now lands 50 ms after the timeout, inside the tick window).
  SIM.busy = true; SIM.noMain = true; SIM.hoverMs = 650;
  SIM.frame._win.qed64.editor.getModel().setValue(`${byId['graph-scope'].text}-- busy pool, late hovers\n`);
  await sleep(6000);
  const lv12 = st().liveness;
  const lateEv = lv12.events.filter((e) => e.source === 'late');
  ok(lv12.qed64.builtIn === false && lv12.answered === 0 && lv12.lateAnswers >= 2 && lateEv.length >= 2 && lateEv.every((e) => e.proofOfLife === true && e.ms > 600)
    && lv12.aliveVia['late-answer'] >= 2 && lv12.wedged === 0 && SIM.restarts.length === rs12 && lv12.events.some((e) => e.source === 'alive' && e.via === 'late-answer') && SIM.frame._win.qed64.relay.session.id === sess12,
    `hovers answered 0.65 s after a 0.6 s timeout (checked by the tick at 0.75 s), no frames, no main-loop answer, no QED64 liveness: ${lv12.sent} probes, ${lv12.answered} counted on time (must be 0), ${lv12.missed} missed, ${lv12.lateAnswers} late answers (${lateEv.filter((e) => e.ms !== undefined).map((e) => `${e.ms} ms`).slice(0, 4).join(', ')}), settled alive via late-answer ${lv12.aliveVia['late-answer']}x, wedged ${lv12.wedged}, restarts ${SIM.restarts.length - rs12}`);
  // an answer inside the timeout still counts as on time (0.3 s < 0.6 s); over the whole run the split is by elapsed time
  SIM.hoverMs = 300;
  const a12 = st().liveness.answered;
  SIM.frame._win.qed64.editor.getModel().setValue(`${byId['graph-scope'].text}-- busy pool, timely hovers\n`);
  await sleep(3000);
  {
    const ev = st().liveness.events; const ans = ev.filter((e) => e.source === 'answered'); const late = ev.filter((e) => e.source === 'late' && !e.error);
    ok(st().liveness.answered > a12 && st().liveness.wedged === 0 && ans.length > 0 && ans.every((e) => e.ms <= 600) && late.every((e) => e.ms > 600),
      `hovers answered after 0.3 s (inside the 0.6 s timeout) count as on time (${st().liveness.answered - a12} more); every 'answered' event has ms <= 600 (${ans.map((e) => e.ms).slice(-4).join(', ')}) and every late one > 600 (${late.map((e) => e.ms).slice(-6).join(', ')})`);
  }
  // the same page with Lean truly frozen (no answer at all) is still declared wedged and restarted (the recovery is intact)
  SIM.stuck = true;
  SIM.frame._win.qed64.editor.getModel().setValue(`${byId['graph-scope'].text}-- now frozen\n`);
  await until(() => SIM.restarts.length === rs12 + 1, 9000, 'run12 frozen restart');
  ok(st().liveness.events.filter((e) => e.source === 'wedged').pop().action === 'relay.restart', 'then a frozen Lean side (no answer at all) on the same page: wedged -> relay.restart, as before');
  SIM.stuck = false; SIM.busy = false; SIM.hoverMs = 20; SIM.noMain = false;
}

// ================================================================ run 13: the main-loop probe (hardening lane: pin 1859b83's UX C22 (3))
console.log('\n== run 13: a page WITHOUT QED64 liveness, a saturated pool: the FileWorker main loop answers the gallery\'s main-loop probe, so a healthy session is never restarted');
setupEnv({ search: '?stall=5&probe=1&probeTimeout=0.5&restartGap=1', hash: '#graph-scope', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } } });
api = await loadGallery();
await until(() => st().phase === 'ready', 8000, 'run13 ready');
{
  const rs13 = SIM.restarts.length; const sess13 = SIM.frame._win.qed64.relay.session.id;
  // (1) 24 parallel sleeping proofs: every hover waits for a free task thread (no answer, no late answer within the
  // sequence), no frame, no QED64 liveness; only the main loop answers (MethodNotFound, at once)
  SIM.busy = true; SIM.noHover = true;
  SIM.frame._win.qed64.editor.getModel().setValue(`${byId['graph-scope'].text}-- 24 parallel sleeps on 1859b83\n`);
  await until(() => st().stall.active || SIM.restarts.length > rs13, 9000, 'run13 card (or a restart: then the checks below FAIL)');
  await sleep(1500);
  const lv = st().liveness; const mains = SIM.fromClient.filter((m) => m.method === '$/showcase/liveness');
  ok(lv.qed64.builtIn === false && lv.sent >= 2 && lv.answered === 0 && lv.lateAnswers === 0 && lv.aliveVia['main-loop'] >= 2 && lv.wedged === 0 && SIM.restarts.length === rs13 && SIM.frame._win.qed64.relay.session.id === sess13
    && lv.events.some((e) => e.source === 'alive' && e.via === 'main-loop'),
    `hovers unanswered, no frame, no QED64 liveness: ${lv.sent} probes settled alive via main-loop ${lv.aliveVia['main-loop']}x (main-loop probe ${lv.mainLoop.answered}/${lv.mainLoop.sent} answered, last ${lv.mainLoop.lastMs} ms), missed ${lv.missed}, wedged ${lv.wedged}, restarts ${SIM.restarts.length - rs13}`);
  ok(mains.length === lv.mainLoop.sent && mains.length >= 2 && mains.every((m) => typeof m.id === 'string' && /^showcase-main-\d+$/.test(m.id) && m.params && typeof m.params === 'object') && SIM.badRequests === 0
    && !SIM.toClient.some((x) => /^reply:showcase-main-/.test(String(x))) && lv.mainLoop.method === '$/showcase/liveness',
    `every main-loop probe is ${lv.mainLoop.method} with a string id (${mains.slice(0, 2).map((m) => m.id).join(', ')}, …) and params (an object: without params the FileWorker would die), sent with each hover; every reply swallowed by the tap`);
  ok(st().stall.variant === 'alive' && /Lean is still working/.test(SIM.byIdEl('error-title').textContent),
    `the 45 s card (5 s here) during this healthy saturation says "${SIM.byIdEl('error-title').textContent}" (a main-loop answer is a recent sign of life)`);
  // (2) replies QED64's JS layer makes (failInFlight 'QED64: restarting', the halted relay) are not answers: with the main
  // loop silent and only synthetic replies arriving, the session is declared wedged and restarted
  SIM.noMain = true;
  const synth13 = setInterval(() => {
    const pr = SIM.fromClient.filter((m) => m.method === '$/showcase/liveness').pop();
    if (pr && !pr.__answered) { pr.__answered = true; SIM.frame._win.qed64.relay.toClient({ jsonrpc: '2.0', id: pr.id, error: { code: -32603, message: 'QED64: restarting with exact imports' } }); }
  }, 50);
  await until(() => SIM.restarts.length === rs13 + 1, 9000, 'run13 synthetic restart');
  clearInterval(synth13);
  const lvS = st().liveness;
  ok(lvS.mainLoop.synthetic >= 1 && lvS.events.some((e) => e.source === 'main-synthetic') && lvS.events.filter((e) => e.source === 'wedged').pop().action === 'relay.restart',
    `main-loop probes answered only by QED64's JS layer (${lvS.mainLoop.synthetic} synthetic replies) are no proof of life: wedged -> relay.restart`);
  SIM.busy = false; SIM.noHover = false; SIM.noMain = false;
  SIM.frame._win.qed64.editor.getModel().setValue(byId['graph-scope'].text);
  await until(() => st().qed64.phase === 'ready' && !st().stall.active, 8000, 'run13 settle');
  // (3) the whole Lean side frozen (L7 model): neither probe is answered -> wedged -> restart (the recovery is intact)
  await sleep(1200); // past the 1 s restartGap of this run
  SIM.stuck = true;
  SIM.frame._win.qed64.editor.getModel().setValue(`${byId['graph-scope'].text}-- frozen on 1859b83\n`);
  await until(() => SIM.restarts.length === rs13 + 2, 9000, 'run13 frozen restart');
  ok(st().liveness.events.filter((e) => e.source === 'wedged').pop().action === 'relay.restart', 'a frozen Lean side answers neither probe: wedged -> relay.restart');
  SIM.stuck = false;
}

// ================================================================ run 14: browser capabilities, checked before anything boots (hardening lane)
console.log('\n== run 14: a browser without cross-origin isolation / SharedArrayBuffer / Memory64 / WebAssembly gets the capability card and boots nothing; low memory warns with "Try anyway"');
{
  const NEED = 'This showcase needs a Chromium-based desktop browser (Chrome, Edge, Brave, Arc) on a computer with 16 GB of RAM or more, one showcase tab at a time (a tab uses about 8–9 GB, about 12 GB on a reload); your browser lacks';
  const cases = [
    { caps: { coi: false }, id: 'coi', words: 'cross-origin isolation' },
    { caps: { sab: false }, id: 'sab', words: 'SharedArrayBuffer' },
    { caps: { m64: false }, id: 'memory64', words: 'WebAssembly Memory64' },
    { caps: { wasm: false }, id: 'memory64', words: 'WebAssembly Memory64' }, // no WebAssembly at all
    { caps: { coi: false, sab: false, deviceMemory: 4 }, id: 'coi,sab,memory', words: 'cross-origin isolation, SharedArrayBuffer and enough memory' }, // e.g. a page served without COOP/COEP on a small device
  ];
  for (const c of cases) {
    setupEnv({ hash: '#hasse-view', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } }, caps: c.caps });
    api = await loadGallery();
    await until(() => ['unsupported', 'ready', 'error'].includes(st().phase), 3000, `run14 ${JSON.stringify(c.caps)}`);
    await sleep(300); // nothing may happen after the card either
    s = st();
    const card = SIM.byIdEl('error-card');
    const rej = await settled(api.select('chart-kit'));
    location.hash = '#graph-scope'; SIM.fireWin('hashchange'); await sleep(50);
    ok(s.caps && s.caps.ok === false && s.caps.missing.join() === c.id && s.caps.hard.length > 0 && SIM.navigations.length === 0 && SIM.fetchLog.length === 0 && SIM.frame.src === ''
      && !card.hidden && s.error.kind === 'unsupported' && SIM.byIdEl('error-title').textContent === 'This browser cannot run the Lean widget gallery'
      && SIM.byIdEl('error-detail').textContent.startsWith(`${NEED} ${c.words}.`) && SIM.byIdEl('error-retry').hidden && SIM.byIdEl('error-dismiss').hidden && SIM.byIdEl('error-stock').hidden
      && SIM.byIdEl('error-checks').children.filter((li) => li.className === 'bad').length === c.id.split(',').length
      && SIM.byIdEl('stage-veil').getAttribute('aria-hidden') === 'true' && SIM.byIdEl('status-text').textContent === 'This browser cannot run the gallery'
      && !rej.ok && rej.e.code === 'UNSUPPORTED' && SIM.navigations.length === 0 && st().notice === null,
      `${JSON.stringify(c.caps)}: card "${SIM.byIdEl('error-title').textContent}" — "…lacks ${c.words}."; missing [${s.caps.missing}]; 0 fetches, 0 navigations; no Try again / Dismiss / stock link; select() rejects ${rej.e && rej.e.code}; a hash change boots nothing`);
  }
  // low memory alone (Chromium reports navigator.deviceMemory): a warning card with "Try anyway"; nothing boots until it is clicked
  setupEnv({ hash: '#hasse-view', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } }, caps: { deviceMemory: 4 } });
  api = await loadGallery();
  await until(() => ['unsupported', 'ready', 'error'].includes(st().phase), 3000, 'run14 memory');
  await sleep(300);
  s = st();
  ok(s.caps.missing.join() === 'memory' && s.caps.hard.length === 0 && s.caps.deviceMemory === 4 && SIM.navigations.length === 0 && !SIM.fetchLog.some((f) => /^\/(snapshots|runtime)\//.test(f.path))
    && SIM.byIdEl('error-title').textContent === 'This device may not have enough memory' && SIM.byIdEl('error-detail').textContent.startsWith(`${NEED} enough memory.`)
    && !SIM.byIdEl('error-retry').hidden && SIM.byIdEl('error-retry').textContent === 'Try anyway' && SIM.byIdEl('error-dismiss').hidden && s.error.soft === true
    && SIM.byIdEl('card-list').children.length === 8 && s.current === 'hasse-view',
    `deviceMemory 4: warning card "${SIM.byIdEl('error-title').textContent}" with "${SIM.byIdEl('error-retry').textContent}"; the rail is shown, nothing fetched from QED64, no navigation`);
  SIM.byIdEl('error-retry').click();
  await until(() => st().phase === 'ready', 8000, 'run14 try anyway').catch(() => null);
  s = st();
  ok(s.shown === 'hasse-view' && s.caps.override === true && SIM.navigations.length === 1 && SIM.byIdEl('error-card').hidden, `"Try anyway" boots as usual: ${s.shown} ready, override recorded`);
  // a capable browser that reports 8 GB (the threshold) passes every check
  setupEnv({ hash: '#chart-kit', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } }, caps: { deviceMemory: 8 } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run14 capable');
  ok(st().caps.ok && st().caps.deviceMemory === 8 && st().caps.checks.every((c) => c.ok), 'deviceMemory 8, isolated, SharedArrayBuffer, Memory64: every check passes and the gallery boots');
}

// ================================================================ run 15: a slow first visit (last-mile lane defect: 360 s boot timeout at 10 Mbit/s)
console.log('\n== run 15: slow first boot: progress re-arms the boot timeout (notice, no card); a true stall shows the card; a later ready closes it and finishes the boot');
{
  const W8 = { widgets8: { imports: [...ALL7, 'DistLens'] } };
  const KNOBS = '?bootTimeout=0.6&bootStall=0.5&bootNotice=0.3'; // 600 ms budget, 500 ms without progress = stall, early notice from 300 ms
  const LABEL = 'preparing the mathlib environment (0.4 GiB — one-time)';
  const TOTAL = 400e6;
  const card = () => SIM.byIdEl('error-card');
  const prog = (loaded) => SIM.page.qed64.ui.progress(LABEL, { phase: 'snapshot', loaded, total: TOTAL, unit: 'bytes' });
  // (a) slow but steady: 2 s of new bytes (> budget + stall window): never the card, a "still downloading" notice instead
  setupEnv({ search: KNOBS, hash: '#chart-kit', overlays: W8, holdBoot: true });
  api = await loadGallery();
  await until(() => st().phase === 'booting' && SIM.page && SIM.page.qed64 && st().boot.waiting, 3000, 'run15a booting');
  let sawCard = false; const notices = new Set(); const lines = new Set(); const t0 = Date.now();
  for (let i = 1; i <= 20; i++) {
    prog(i * 10e6);
    await sleep(100);
    if (!card().hidden || st().error) sawCard = true;
    if (st().notice) notices.add(st().notice);
    lines.add(SIM.byIdEl('status-text').textContent);
  }
  s = st();
  const firstNotice = s.boot.events.find((e) => e.source === 'notice');
  ok(!sawCard && s.phase === 'booting' && s.error === null && s.boot.stalls === 0 && Date.now() - t0 >= 2000 && s.boot.timeoutMs === 600 && s.boot.stallMs === 500 && s.boot.noticeMs === 300,
    `slow progress for ${Date.now() - t0} ms (budget ${s.boot.timeoutMs} ms, stall window ${s.boot.stallMs} ms): no error card, still booting, 0 stalls`);
  ok(s.notice === `Still downloading: ${LABEL} — 200 MB of 400 MB so far. A first visit downloads several hundred MB, which takes minutes on a slow connection; later visits start from this browser's storage.` && s.boot.noticeShown === 1 && !SIM.byIdEl('notice').hidden && firstNotice && firstNotice.elapsedMs < 600,
    `non-blocking notice "${(s.notice || '').slice(0, 72)}…" (shown once, first at ${firstNotice && firstNotice.elapsedMs} ms: QED64's own boot overlay is gone, so before the budget)`);
  ok(SIM.byIdEl('notice').classList.contains('is-slow') && SIM.byIdEl('notice').style.top === '43px',
    `the slow-download notice sits below the page's top bar (#bar bottom 35 px → top ${SIM.byIdEl('notice').style.top}), so it never covers QED64's status pill`);
  // The status line is rendered on the gallery's 250 ms monitor tick, not on each progress call, so the loop's last sample
  // (100 ms after the 20th call) saw "200 MB" only when a tick fell into those 100 ms: about 100 ms of timer drift over the
  // 2 s loop was tolerated, and one 200 ms event-loop stall on a loaded host lost it (closure lane, 2026-10-03: a deploy
  // rehearsal's G1 failed once with "108 ok, 1 failed"; 4 of 4 runs with an injected 200 ms stall per second failed here).
  // Keep sampling until a tick has rendered the 20th call: at most 350 ms (> one tick, < the 500 ms stall window).
  for (const tw = Date.now(); Date.now() - tw < 350 && ![...lines].some((l) => / · 200 MB of 400 MB$/.test(l)); await sleep(10)) lines.add(SIM.byIdEl('status-text').textContent);
  ok(s.boot.uiWrapped.join() === 'busy,progress,idle' && s.boot.bytes === 200e6 && s.boot.sources.bytes === 20 && SIM.uiSeen.filter((x) => x[0] === 'progress').length === 20 && [...lines].some((l) => /^Starting Lean in your browser… .* · 200 MB of 400 MB$/.test(l)),
    `the page's status sink is wrapped (${s.boot.uiWrapped}), the page's own sink still got all 20 calls; ${s.boot.bytes / 1e6} MB of progress counted; status line "${[...lines].pop()}"`);
  SIM.holdBoot = false; SIM.releaseBoot();
  await until(() => st().phase === 'ready', 5000, 'run15a ready');
  s = st();
  ok(s.shown === 'chart-kit' && s.error === null && s.notice === null && SIM.byIdEl('notice').hidden && card().hidden && s.cursor && s.cursor.lineNumber === byId['chart-kit'].firstCursor.lineNumber && s.bootMs >= 2000 && s.boot.waiting === null,
    `download done → ready: chart-kit at L${s.cursor && s.cursor.lineNumber}, the notice is gone, boot ${Math.round(s.bootMs)} ms`);
  ok(!SIM.byIdEl('notice').classList.contains('is-slow') && SIM.byIdEl('notice').style.top === '', 'the notice\'s slow-download placement is cleared with it (other notices keep the CSS position)');

  // (b) a true stall: some bytes, then only re-sent bytes of the same download (a retry is no progress) → the card
  setupEnv({ search: KNOBS, hash: '#chart-kit', overlays: W8, holdBoot: true, storage: {} });
  api = await loadGallery();
  await until(() => st().phase === 'booting' && SIM.page && SIM.page.qed64 && st().boot.waiting, 3000, 'run15b booting');
  const tb = Date.now();
  let tLast = 0;
  for (let i = 1; i <= 3; i++) { prog(i * 10e6); tLast = Date.now(); await sleep(100); } // tLast: the last NEW bytes
  let resent = 0;
  while (st().phase !== 'error' && Date.now() - tb < 4000) { prog(5e6); resent++; await sleep(100); }
  s = st();
  const stallEv = s.boot.events.find((e) => e.source === 'stalled');
  ok(s.phase === 'error' && s.error && s.error.kind === 'timeout' && !card().hidden && SIM.byIdEl('error-title').textContent === 'This is taking too long'
    && /^no download or start-up progress for .* while waiting for ChartKit to be checked \(first boot\)/.test(SIM.byIdEl('error-detail').textContent) && /closes by itself/.test(SIM.byIdEl('error-detail').textContent)
    && s.boot.stalls === 1 && stallEv && stallEv.idleMs >= 500 && Date.now() - tLast >= 450 && s.notice === null && s.boot.latePending === true && s.selections.slice(-1)[0].outcome === 'TIMEOUT',
    `no new bytes for ${stallEv && stallEv.idleMs} ms (${resent} re-sent progress calls ignored) → card "${SIM.byIdEl('error-title').textContent}": "${SIM.byIdEl('error-detail').textContent.slice(0, 90)}…"; selection TIMEOUT; late recovery armed`);

  // (c) late ready after the card: QED64 finishes on the same page → the card closes and the boot completes (cursor, panel)
  const pf = SIM.pageFocus, ef = SIM.editorFocus;
  SIM.holdBoot = false; SIM.releaseBoot();
  await until(() => st().phase === 'ready', 5000, 'run15c late ready');
  s = st();
  ok(s.shown === 'chart-kit' && s.error === null && card().hidden && s.booted && s.everReady && s.boot.recovered === 1 && s.boot.latePending === false
    && s.cursor && s.cursor.lineNumber === byId['chart-kit'].firstCursor.lineNumber && SIM.editorFocus > ef && SIM.pageFocus > pf && /^ChartKit is ready · Lean started in /.test(SIM.byIdEl('status-text').textContent),
    `late ready → card closed, recovered ${s.boot.recovered}, cursor L${s.cursor && s.cursor.lineNumber}, editor focused, status "${SIM.byIdEl('status-text').textContent}"`);
  r = await api.select('hasse-view');
  ok(r.phase === 'ready' && r.shown === 'hasse-view' && r.error === null, 'after the late recovery the gallery switches normally (hasse-view ready)');

  // (e) page resources: a NEW URL is progress, a page re-fetching one URL (retry loop, cache-busting query) is not → the card
  setupEnv({ search: KNOBS, hash: '#chart-kit', overlays: W8, holdBoot: true, storage: {} });
  api = await loadGallery();
  await until(() => st().phase === 'booting' && SIM.page && SIM.page.qed64 && st().boot.waiting, 3000, 'run15e booting');
  const te = Date.now(); let sawCardE = false;
  for (let i = 1; i <= 15; i++) { SIM.resources.push({ name: `${ORIGIN}/raw/part-${i}.bin` }); await sleep(100); if (!card().hidden || st().error) sawCardE = true; }
  s = st();
  const freshMarks = s.boot.sources.resource;
  ok(!sawCardE && s.phase === 'booting' && s.boot.stalls === 0 && Date.now() - te >= 1500 && freshMarks >= 10 && s.boot.resourceUrls === 15,
    `new page resources for ${Date.now() - te} ms (budget 600 ms, stall window 500 ms): no card; ${freshMarks} resource marks, ${s.boot.resourceUrls} URLs`);
  const tRetry = Date.now(); let retries = 0;
  while (st().phase !== 'error' && Date.now() - tRetry < 4000) { SIM.resources.push({ name: `${ORIGIN}/raw/part-15.bin${retries % 2 ? `?retry=${retries}` : ''}` }); retries++; await sleep(50); }
  s = st();
  const stallE = s.boot.events.find((e) => e.source === 'stalled');
  ok(s.phase === 'error' && s.error && s.error.kind === 'timeout' && !card().hidden && s.boot.stalls === 1 && stallE && stallE.idleMs >= 500 && s.boot.sources.resource === freshMarks && s.boot.resources === 15 + retries && s.boot.resourceUrls === 15,
    `a page re-fetching one URL (${retries} entries, half with a cache-busting query) is no progress: the card after ${Date.now() - tRetry} ms of retries (idle ${stallE && stallE.idleMs} ms); resource marks unchanged at ${s.boot.sources.resource}`);
  SIM.holdBoot = false; SIM.releaseBoot();
  await until(() => st().phase === 'ready', 5000, 'run15e late ready');
  ok(st().error === null && card().hidden && st().boot.recovered === 1, 'and a later ready still closes that card (recovered 1)');

  // (d) defaults, and a normal boot is untouched by the progress logic
  setupEnv({ hash: '#chart-kit', overlays: W8 });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run15d ready');
  s = st();
  ok(s.boot.timeoutMs === 360000 && s.boot.stallMs === 240000 && s.boot.noticeMs === 120000 && s.boot.noticeShown === 0 && s.boot.stalls === 0 && s.boot.recovered === 0 && s.notice === null && s.boot.uiTapped,
    `defaults: budget ${s.boot.timeoutMs / 1000} s, stall window ${s.boot.stallMs / 1000} s, early notice ${s.boot.noticeMs / 1000} s; a normal boot shows no notice and no card`);
}

console.log(`\nSIM-GALLERY ${fails ? 'FAIL' : 'OK'} ${oks} ok, ${fails} failed`);
process.exit(fails ? 1 : 0);
