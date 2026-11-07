#!/usr/bin/env node
// sim-gallery.mjs — drive the REAL gallery/gallery.js in Node against a fake DOM (parsed from gallery/index.html)
// and a fake QED64 page that models what the controller relies on (no browser):
//   * navigation commits ~5 ms after iframe.src is set; the page document is 'loading' until its module script
//     runs (~15 ms), which constructs the relay — the FIRST session is created (initialBytes fixed) before
//     globalThis.qed64 is assigned — then 'complete' + iframe 'load';
//   * relay: lastText (full-text didChange), state rebooting/serving/halted, makeSession (called on restart/rearm),
//     restart(opts) only when serving, a halted relay re-arms on didChange;
//   * worker status: version bumps per received text; header covered when the session has 'mathlib' and every
//     non-Mathlib import is in the overlay region's imports, else headerRefused;
//   * Monaco: setValue always emits a change (also for identical text), setPosition/getPosition/focus.
// It is a model, not QED64: it checks the gallery's own logic (ordering, waits, supersession, error paths).
// The browser bring-up must still confirm the model's assumptions (gallery/README.md open questions).
//
// THE PAGE MODEL (QED64 embedding contract v1, deps/qed64/docs/EMBEDDING.md; the legacy page model left with P1 C6): at
// module start the page defines a FROZEN globalThis.qed64.api and dispatches 'qed64:frame-api' {api, frame} on the parent,
// BEFORE it reads its boot document (#code= from the frame URL, read once and dropped; in embed mode a setDocument within
// 5 s, else ''; qed64.buffer is neither read nor written); setDocument/getDocument/status/settled/restart/setCursor/
// getCursor/focus/acceptOffer and the boot/status/ready/document/fileProgress/diagnostics/liveness/reboot/death/offer events
// with the contract's semantics. Every access to the INTERNAL members (qed64.relay / ui / editor / status()), to
// localStorage['qed64.buffer'] and to the page's own DOM ids is recorded (SIM.pages[*]._internalTouches, SIM.storageAccess,
// document._touches): every run asserts the gallery made none (§9). The tests reach the model through SIM.internals.
// gallery/pin.json is served with apiRevision unless setupEnv({v1: false}) serves one without it (the data card).
//
// OVERLAYS: setupEnv({overlays}) is keyed by LOGICAL name (widgets8) or a literal directory (widgets9, partial7, nope). The fake
// server serves a logical overlay ONLY at its served directory (setupEnv servedDirs; default: the pin.json overlays map the
// gallery sees, else the bare names), never at a bare logical name that is not its directory (serve.mjs's F7 rule); the
// gallery's pin.json carries PIN.overlays unless setupEnv({pinOverlays}) replaces (an object) or removes (null: the data card) it.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const G = path.join(SC, 'gallery');
const ORIGIN = 'http://localhost:5190';
const GiB = 2 ** 30, MiB = 2 ** 20;
const PIN = JSON.parse(fs.readFileSync(path.join(G, 'pin.json'), 'utf8'));
/** The active pin's served directory of logical overlay `o` (gallery/pin.json overlays; the bare name without the map). */
const PDIR = (o) => (PIN.overlays && typeof PIN.overlays[o] === 'string' ? PIN.overlays[o] : o);
const EX = JSON.parse(fs.readFileSync(path.join(G, 'examples.json'), 'utf8')).examples;
const byId = Object.fromEntries(EX.map((e) => [e.id, e]));
let fails = 0, oks = 0;
const ok = (c, m) => { if (c) { oks++; console.log(`ok    ${m}`); } else { fails++; console.log(`FAIL  ${m}`); } return !!c; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// the gallery's console warnings, recorded per run (SIM.warns) and still printed
{ const warn = console.warn.bind(console); console.warn = (...a) => { if (Array.isArray(SIM.warns)) SIM.warns.push(a.map(String).join(' ')); warn(...a); }; }
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
/** The fake server's view of /snapshots/<dir>/: the overlay key it serves there (SIM.servedDirs: logical name → directory), or
 *  null for a logical name that is not its own directory (404, as serve.mjs on a per-runtime pin); any other dir is literal. */
function overlayAtDir(dir) {
  const sd = SIM.servedDirs || {};
  for (const k of Object.keys(sd)) if (sd[k] === dir) return k;
  if (Object.prototype.hasOwnProperty.call(sd, dir)) return null;
  return dir;
}
const servedOverlay = (dir) => { const k = overlayAtDir(dir); return k !== null && Object.prototype.hasOwnProperty.call(SIM.overlays, k) ? SIM.overlays[k] : null; };
function makeQed(pw, bootText, overlay, hooks = {}) {
  const region = (servedOverlay(overlay) || {}).imports || [];
  const W = { phase: 'booting', version: null, header: null };
  const relay = { state: { kind: 'rebooting' }, lastText: '', lastDeath: null, stats: { rangedChanges: 0 } };
  let n = 0;
  const mk = (opts) => {
    const snaps = (opts && opts.snapshots) || (needsMathlib(relay.lastText || bootText) ? ['init', 'mathlib'] : ['init']);
    // ?memory=<GiB> is the initial commit of EVERY session (EMBEDDING.md §4); an explicit restart({initialBytes}) would win
    const commit = hooks.memoryBytes ? hooks.memoryBytes : snaps.includes('mathlib') ? 2048 * MiB : 256 * MiB;
    const s = { id: `s${++n}`, snapshots: snaps, initialBytes: commit, lean: { request: async () => ({ memory: { initialBytes: relay.session.initialBytes, currentBytes: relay.session.initialBytes } }) } };
    return s;
  };
  relay.makeSession = mk;
  // Monaco's version id, which the LSP client sends as the document version (page-api.ts whenForwarded)
  let modelVersion = 1;
  const model = { text: bootText, getValue() { return this.text; }, setValue(t) { this.text = t; SIM.setValueCalls++; const v = ++modelVersion; setTimeout(() => didChange(t, v), 10); }, getLineCount() { return this.text.split('\n').length; }, getVersionId: () => modelVersion };
  let pos = { lineNumber: 1, column: 1 };
  const editor = { getModel: () => model, setPosition(p) { pos = { ...p }; SIM.positions.push({ ...p }); }, getPosition: () => pos, revealLineInCenter() {}, focus() { SIM.editorFocus++; }, pushUndoStop() {}, executeEdits() {} };
  function verdict(text, sess) {
    const mods = text.split('\n').filter((l) => /^\s*import\s/.test(l)).map((l) => l.trim().split(/\s+/)[1]);
    const covered = sess.snapshots.includes('mathlib') ? ['Mathlib', ...region] : [];
    const missing = mods.filter((m) => !covered.includes(m));
    return missing.length ? { phase: 'headerRefused', header: { mode: 'refused', missing } } : { phase: 'ready', header: { mode: mods.length ? 'covered' : 'exact', missing: [] } };
  }
  function elaborate(text) {
    if (relay.state.kind !== 'serving') return;
    W.phase = 'elaborating'; W.version = relay.doc.version;
    const sess = relay.session;
    // the checker reports progress on the version it received (a $/lean/fileProgress frame the api turns into an event)
    relay.toClient({ jsonrpc: '2.0', method: '$/lean/fileProgress', params: { textDocument: { uri: relay.doc.uri, version: W.version }, processing: [{ range: { start: { line: 0, character: 0 }, end: { line: 1, character: 0 } }, kind: 1 }] } });
    if (SIM.stuck || SIM.busy) { SIM.stuckVersions.push(W.version); return; } // L7 model (stuck) / a slow command (busy): never finishes this version
    setTimeout(() => {
      if (!(relay.session === sess && relay.state.kind === 'serving')) return;
      Object.assign(W, verdict(text, sess));
      relay.toClient({ jsonrpc: '2.0', method: 'textDocument/publishDiagnostics', params: { uri: relay.doc.uri, version: W.version, diagnostics: [] } });
    }, SIM.elabMs);
  }
  function bootSession(sess, delay, reason = 'boot') {
    relay.state = { kind: 'rebooting', reason }; W.phase = 'booting';
    const go = () => { if (relay.session !== sess) return; relay.state = { kind: 'serving' }; elaborate(relay.lastText); };
    if (SIM.holdBoot) { SIM.releaseBoot = go; return; } // a slow first visit: the test decides when the download is done
    setTimeout(go, delay);
  }
  function didChange(t, v) {
    relay.lastText = t;
    relay.doc.version = v ?? modelVersion; SIM.didChanges++; if (hooks.onIn) hooks.onIn(relay.doc.uri, relay.doc.version, t);
    if (relay.state.kind === 'halted') { relay.lastDeath = null; relay.session = relay.makeSession(); SIM.rearms++; bootSession(relay.session, 30); return; }
    elaborate(t);
  }
  relay.rearm = () => { if (relay.state.kind !== 'halted') return false; relay.lastDeath = null; relay.session = relay.makeSession(); SIM.rearms++; bootSession(relay.session, 30); return true; };
  relay.restart = (opts) => { if (relay.state.kind !== 'serving') return; SIM.restarts.push({ opts, from: relay.session.id }); relay.session = relay.makeSession(opts); bootSession(relay.session, 60); };
  relay.toClient = (m) => { SIM.toClient.push(m && (m.method || `reply:${m.id}`)); if (hooks.onOut) hooks.onOut(m); }; // the api's taps
  // what reaches the relay from the client (lsp-relay.ts fromClient): the gallery sends nothing (its probe left in P1), so
  // every run that checks it finds SIM.fromClient empty. SIM.stuck: no verdict (L7 model); SIM.busy: elaborating forever
  relay.doc = { uri: 'file:///Probe.lean', languageId: 'lean4', version: 1 };
  relay.fromClient = (m) => { SIM.fromClient.push(m); };
  relay.status = () => ({ phase: relay.state.kind === 'halted' ? 'halted' : W.phase, version: W.version, header: W.header && { ...W.header, version: 1, key: [] }, session: relay.session.id, relay: relay.state.kind, lastDeath: relay.lastDeath, collision: null,
    rebootReason: relay.state.kind === 'rebooting' ? relay.state.reason : null });
  // QED64's own liveness declaring the session wedged: died "wedged", the relay reboots a fresh session and replays the text
  SIM.qedWedge = () => { const from = relay.session.id; relay.lastDeath = { reason: 'wedged', message: 'simulated: the Lean runtime stopped answering', seq: ++SIM.deathSeq, session: from }; relay.session = relay.makeSession(); SIM.qedReboots.push({ from, to: relay.session.id }); SIM.qlive = { probes: 0, answered: 0, stalls: 0, resumed: 0, rescues: 0 }; bootSession(relay.session, 700, 'wedged'); };
  // the relay constructor: first session (commit decided NOW, before globalThis.qed64 exists) + boot
  relay.lastText = bootText;
  relay.session = mk();
  SIM.firstSessions.push({ id: relay.session.id, initialBytes: relay.session.initialBytes, snapshots: relay.session.snapshots, qed64Assigned: !!pw.qed64 });
  bootSession(relay.session, SIM.bootMs);
  SIM.halt = () => { relay.state = { kind: 'halted' }; relay.lastDeath = { reason: 'crash', message: 'simulated', seq: ++SIM.deathSeq, session: relay.session.id }; };
  return { relay, _W: W, _model: model, _editor: editor, _modelVersion: () => modelVersion };
}

// ---------------------------------------------------------------- the V1 page API model (EMBEDDING.md §2–§3; mirrors page-api.ts)
const DEATH_KINDS = new Set(['crash', 'exit', 'abort', 'wedged', 'heartbeat', 'bootFailed']);
function makeApi(pw, { overlay, embed, hashCode, memoryBytes }) {
  const listeners = new Map();
  const emit = (type, payload) => { for (const fn of [...(listeners.get(type) || [])]) { try { fn(payload); } catch (e) { SIM.listenerThrows.push(String(e && e.message || e)); } } };
  let q = null; // the page's internals once the relay exists
  let mounted = false; let bootRead = false; let bootDoc = null; const bootDocWaiters = [];
  const readyWaiters = []; let failedBeforeUp = null;
  let boot = { stage: 'manifests', label: '', done: false, failed: false, message: null, overlay: true };
  let last = null; let lastDeathSeen = null; let deathSeq = 0; const readySeen = new Set();
  let liveCounters = null; let lastAnswerAt = null; let lastFrameAt = null; let liveSession = null;
  const onReady = (ok, fail) => { if (failedBeforeUp !== null) fail(Object.assign(new Error(failedBeforeUp), { code: 'BOOT_FAILED' })); else readyWaiters.push({ ok, fail }); };
  const isBound = () => !!q && mounted;
  const deathInfo = (d) => (d ? { kind: DEATH_KINDS.has(d.reason) ? d.reason : 'other', reason: d.reason, message: d.message, cause: null, seq: d.seq ?? 0, session: d.session ?? null, exitCode: null } : null);
  const noLive = () => !!(SIM.caps2 && SIM.caps2.liveness === false); // a page whose api lacks capabilities.liveness (§1.2)
  const livenessNow = () => (liveCounters && !noLive() ? { stalled: liveCounters.stalls > liveCounters.resumed, lastAnswerAgoMs: lastAnswerAt === null ? null : Date.now() - lastAnswerAt, lastFrameAgoMs: lastFrameAt === null ? null : Date.now() - lastFrameAt, probeAfterMs: 6000, wedgeAfterMs: 12000, graceMs: 4000 } : null);
  const project = (s) => ({
    phase: s ? (s.phase) : 'booting', relay: s ? s.relay : 'rebooting', rebootReason: s ? (s.rebootReason ?? null) : 'boot', session: s ? s.session : null, version: s ? s.version : null,
    header: s && s.header ? { mode: s.header.mode, missing: [...s.header.missing], moduleCount: 0 } : null, collision: null, lastDeath: deathInfo(s ? s.lastDeath : null),
    boot: { ...boot }, snapshots: q ? [...q.relay.session.snapshots] : null, liveness: livenessNow(),
    memory: q ? { initialBytes: q.relay.session.initialBytes, currentBytes: q.relay.state.kind === 'serving' ? q.relay.session.initialBytes : null, maximumBytes: 6 * GiB } : null,
    offer: SIM.offer ? { ...SIM.offer } : null,
  });
  const statusNow = () => project(q ? q.relay.status() : last);
  const whenForwarded = (version, unchanged) => new Promise((resolve) => {
    const d = q.relay.doc; if (d.version >= version) return resolve({ version: d.version, unchanged });
    const off = on('document', (ev) => { if (ev.version >= version) { off(); resolve({ version: ev.version, unchanged }); } });
  });
  function on(type, fn) { if (!listeners.has(type)) listeners.set(type, new Set()); listeners.get(type).add(fn); return () => off(type, fn); }
  function off(type, fn) { const s2 = listeners.get(type); if (s2) s2.delete(fn); }
  const clamp = (c) => { const m = q._model; const ln = Math.min(Math.max(1, Math.trunc(c.lineNumber)), m.getLineCount()); const lineLen = (m.text.split('\n')[ln - 1] || '').length; return { lineNumber: ln, column: Math.min(Math.max(1, Math.trunc(c.column)), lineLen + 1) }; };
  const api = Object.freeze({
    version: 1, revision: '1.0.0',
    capabilities: Object.freeze({ editorRpc: true, documents: true, events: true, restart: true, embedMode: true, snapshotRoots: true, postMessage: false, liveness: true, memory: true, widgetSourceCache: true, offers: true, ...(SIM.caps2 || {}) }),
    build: () => (q ? { buildId: PIN.buildId, leanVersion: '4.34.0', sourceRevision: null, shell: null } : null),
    status: statusNow,
    whenReady: () => (isBound() ? Promise.resolve(statusNow()) : new Promise((r, j) => onReady(() => r(statusNow()), j))),
    settled(opts = {}) {
      return new Promise((resolve, reject) => {
        const want = opts.version ?? (q && q.relay.doc ? q.relay.doc.version : null); const t0 = Date.now();
        const h = setInterval(() => {
          const st = statusNow();
          if (st.phase === 'halted') { clearInterval(h); reject(Object.assign(new Error('halted'), { code: 'HALTED' })); return; }
          if (opts.afterSession !== undefined && (st.session === null || st.session === opts.afterSession)) return;
          if ((st.phase === 'ready' || st.phase === 'headerRefused') && st.relay === 'serving' && (want === null || (st.version ?? -1) >= want)) { clearInterval(h); resolve(st); return; }
          if (opts.timeoutMs !== undefined && Date.now() - t0 > opts.timeoutMs) { clearInterval(h); reject(Object.assign(new Error('timeout'), { code: 'TIMEOUT' })); }
        }, 10);
      });
    },
    on, off,
    getDocument() { if (!q || !mounted) return null; return { uri: q.relay.doc.uri, version: q.relay.doc.version, text: q._model.text }; },
    setDocument(text, opts = {}) {
      SIM.setDocCalls.push({ t: Date.now(), length: text.length, opts: { ...opts }, preBoot: !bootRead, page: SIM.pages.indexOf(pw) });
      if (typeof text !== 'string') return Promise.reject(new TypeError('setDocument: text must be a string'));
      if (!bootRead) {
        bootDoc = text; for (const w of bootDocWaiters.splice(0)) w(text);
        return new Promise((resolve, reject) => onReady(() => { if (opts.cursor) api.setCursor(opts.cursor, { focus: opts.focus }); resolve({ version: q.relay.doc.version, unchanged: false }); }, reject));
      }
      if (!isBound()) return new Promise((resolve, reject) => onReady(() => api.setDocument(text, opts).then(resolve, reject), reject));
      const m = q._model;
      const unchanged = m.text === text;
      if (!unchanged) m.setValue(text); // the model: a change event ~10 ms later (undoable edits and setValue alike here)
      const forwarded = whenForwarded(m.getVersionId(), unchanged);
      if (opts.cursor) api.setCursor(opts.cursor, { focus: opts.focus }); else if (opts.focus) q._editor.focus();
      forwarded.then((r) => { SIM.lastSetDocResult = r; });
      return forwarded;
    },
    getCursor() { if (!q) return null; const p = q._editor.getPosition(); return p ? { lineNumber: p.lineNumber, column: p.column } : null; },
    setCursor(cursor, opts = {}) {
      if (!q || !mounted || !Number.isFinite(cursor && cursor.lineNumber) || !Number.isFinite(cursor && cursor.column)) return false;
      const c = clamp(cursor); q._editor.setPosition(c); SIM.setCursorCalls.push({ ...c, focus: opts.focus !== false });
      if (opts.focus !== false) q._editor.focus();
      return true;
    },
    focus() { if (!q || !mounted) return false; q._editor.focus(); return true; },
    restart(opts = {}) {
      const fromSession = q ? q.relay.session.id : null;
      SIM.apiRestarts.push({ t: Date.now(), opts: Object.keys(opts).length ? { ...opts } : undefined, from: fromSession, state: q ? q.relay.state.kind : null });
      if (q && q.relay.state.kind === 'halted' && opts.snapshots === undefined && opts.initialBytes === undefined) return { accepted: q.relay.rearm() === true, fromSession };
      if (!q || q.relay.state.kind !== 'serving' || SIM.refuseRestart) return { accepted: false, fromSession }; // refuseRestart models a boot in flight
      const unknown = (opts.snapshots || []).filter((nm) => !['init', 'mathlib'].includes(nm));
      if (unknown.length) throw new TypeError(`restart: unknown snapshot(s) ${unknown.join(', ')}`);
      q.relay.restart(opts.snapshots ? { snapshots: [...opts.snapshots] } : { snapshots: [...q.relay.session.snapshots] });
      return { accepted: true, fromSession };
    },
    acceptOffer(kind) { if (!SIM.offer || (kind !== undefined && kind !== SIM.offer.kind)) return false; SIM.offerRuns++; const o = SIM.offer; SIM.offer = null; emit('offer', null); return !!o; },
  });
  const emitBoot = (label, info, done, failed, message) => {
    boot = { stage: (info && info.stage) || (failed ? 'failed' : done ? 'done' : boot.stage), label, done, failed, message, overlay: boot.overlay };
    emit('boot', { stage: boot.stage, phase: info ? info.phase ?? null : null, subject: info ? info.subject ?? null : null, label, loaded: info ? info.loaded ?? null : null, total: info ? info.total ?? null : null, unit: info ? info.unit ?? null : null, done, failed, message, error: info && info.error ? { ...info.error } : null });
  };
  // the status ticker: every relay status change (the real page feeds relayStatus from the relay's sink) → status / reboot / death / ready
  let ticker = null; let lastKey = null;
  const tick = () => {
    if (!q) return;
    const s2 = q.relay.status();
    // liveness counters (SIM.qlive) → liveness events, as trackLiveness does
    if (s2.session !== liveSession) { liveSession = s2.session; liveCounters = null; lastAnswerAt = null; lastFrameAt = null; }
    const c = noLive() ? null : SIM.qlive;
    if (c) { const prev = liveCounters || { probes: 0, answered: 0, stalls: 0, resumed: 0, rescues: 0 }; liveCounters = { ...c }; for (const [k, kind] of [['answered', 'answered'], ['stalls', 'stall'], ['resumed', 'resumed'], ['rescues', 'rescue']]) if (c[k] > prev[k]) { if (kind === 'answered') lastAnswerAt = Date.now(); emit('liveness', { session: s2.session, kind }); } }
    const key = `${s2.phase}|${s2.relay}|${s2.session}|${s2.version}|${s2.lastDeath ? s2.lastDeath.seq : ''}`;
    if (key === lastKey) return;
    lastKey = key;
    const prev = last; last = s2;
    if (prev && prev.session !== s2.session) { readySeen.clear(); emit('reboot', { reason: s2.rebootReason ?? null, fromSession: prev.session, toSession: s2.session }); }
    if (s2.lastDeath && s2.lastDeath !== lastDeathSeen) { const d = deathInfo(s2.lastDeath); emit('death', { session: d.session, kind: d.kind, reason: d.reason, message: d.message, cause: null, seq: d.seq, exitCode: null, willReboot: s2.relay === 'rebooting', halted: s2.phase === 'halted' }); }
    lastDeathSeen = s2.lastDeath;
    emit('status', project(s2));
    if ((s2.phase === 'ready' || s2.phase === 'headerRefused') && s2.relay === 'serving') {
      if (!boot.done && !boot.failed) { emitBoot(boot.label, { stage: 'done' }, true, false, null); boot = { ...boot, overlay: false }; SIM.bootFinished++; }
      const k2 = `${s2.session}@${s2.version}`;
      if (!readySeen.has(k2)) { readySeen.add(k2); emit('ready', { session: s2.session, version: s2.version, refused: s2.phase === 'headerRefused', header: s2.header ? { ...s2.header } : null }); }
    }
  };
  const page = {
    api,
    /** the page's boot steps (ui.busy/progress with info.stage), for the slow-boot runs */
    bootStep(label, info) { emitBoot(label, info, false, false, null); },
    /** QED64's 30 s check fallback (at O): status().boot.done before a first verdict (the halt-after-serve case) */
    bootDone() { if (!boot.done && !boot.failed) { emitBoot(boot.label, { stage: 'done' }, true, false, null); boot = { ...boot, overlay: false }; } },
    bootFailed(message) { if (!isBound()) failedBeforeUp = message; emitBoot(message, { stage: 'failed' }, false, true, message); if (!isBound()) for (const w of readyWaiters.splice(0)) w.fail(Object.assign(new Error(message), { code: 'BOOT_FAILED' })); },
    /** the boot document (EMBEDDING.md §3.1): setDocument before it is read > #code= (same-origin frame only, read once) > embed: setDocument within 5 s, else '' */
    async bootDocument() {
      if (bootDoc !== null) { bootRead = true; return { text: bootDoc, source: 'setDocument' }; }
      if (hashCode !== null) { bootRead = true; return { text: hashCode, source: 'hash' }; }
      if (embed) {
        const text = await Promise.race([new Promise((r) => bootDocWaiters.push(r)), sleep(SIM.embedWaitMs).then(() => null)]);
        bootRead = true;
        return text !== null ? { text, source: 'setDocument' } : { text: '', source: 'empty' };
      }
      bootRead = true; const b = SIM.storage.get('qed64.buffer'); SIM.storageAccess.push({ by: 'page', key: 'qed64.buffer', op: 'get' });
      return { text: b ?? '-- stock EXAMPLES.mathlib\nimport Mathlib.Basic.Real.Basic\n', source: b != null ? 'buffer' : 'default' };
    },
    bind(internals) {
      q = internals;
      ticker = setInterval(tick, 20); SIM.timers.push(ticker);
      if (mounted) for (const w of readyWaiters.splice(0)) w.ok();
    },
    editorReady() { mounted = true; if (q) for (const w of readyWaiters.splice(0)) w.ok(); },
    hooks: {
      embed, memoryBytes,
      onIn(uri, version, text) { emit('document', { uri, version, length: text.length, text }); },
      onOut(m) {
        if (!m) return;
        const synthetic = (m.error && typeof m.error.message === 'string' && m.error.message.startsWith('QED64:')) || (m.method === 'textDocument/publishDiagnostics' && Array.isArray(m.params && m.params.diagnostics) && m.params.diagnostics.length > 0 && m.params.diagnostics.every((d) => d.source === 'QED64'));
        if (!synthetic) lastFrameAt = Date.now();
        if (m.method === 'textDocument/publishDiagnostics' && m.params && m.params.uri) emit('diagnostics', { uri: m.params.uri, version: m.params.version ?? null, diagnostics: JSON.parse(JSON.stringify(m.params.diagnostics || [])), origin: synthetic ? 'qed64' : 'lean' });
        else if (m.method === '$/lean/fileProgress' && m.params && m.params.textDocument) emit('fileProgress', { uri: m.params.textDocument.uri, version: m.params.textDocument.version ?? null, processing: JSON.parse(JSON.stringify(m.params.processing || [])) });
      },
    },
  };
  return page;
}
/** `#code=` of a frame URL (page-api.ts codeFromHash). */
function codeFromHash(hash) { const m = /^#(?:.*&)?code=([^&]*)/.exec(hash || ''); if (!m) return null; try { return decodeURIComponent(m[1]); } catch { return null; } }
function makePage(src) {
  const url = new URL(src, ORIGIN);
  const overlay = (url.searchParams.get('snapshots') || '').replace(/^snapshots\//, '');
  const listeners = [];
  const styles = [];
  const doc = {
    readyState: 'loading', head: { append: (el) => styles.push(el) },
    // the gallery's own <style> elements (qed64-showcase-*); any other id is the page's own DOM, internal (EMBEDDING.md §9):
    // recorded, and every run asserts none (noInternals)
    getElementById: (id) => {
      if (!/^qed64-showcase-/.test(id)) { doc._touches.push(id); return null; }
      return styles.find((s) => s.id === id) || null;
    },
    createElement: () => { const el = { id: '', textContent: '', remove: () => styles.splice(styles.indexOf(el), 1) }; return el; },
    _styles: styles, _touches: [],
  };
  const pw = {
    location: { href: url.href, pathname: url.pathname, search: url.search, hash: url.hash, reload() { SIM.pageReloads++; } }, document: doc, _internalTouches: [],
    addEventListener: (t, fn, cap) => listeners.push({ t, fn, cap }), dispatchEvent: (ev) => { for (const l of listeners) if (l.t === ev.type) l.fn(ev); },
    MessageEvent: class { constructor(t, i) { this.type = t; Object.assign(this, i); } }, focus() { SIM.pageFocus++; }, _listeners: listeners,
    // resource timing: the entries the test pushes into SIM.resources (a retry loop re-fetching one URL adds entries too)
    performance: { getEntriesByType: (t) => (t === 'resource' ? SIM.resources.slice() : []) },
  };
  // the page (EMBEDDING.md §2.1, §3.1): api frozen and announced at MODULE START (before the boot document is read); embed
  // mode never reads qed64.buffer; #code= is honoured (same-origin frame) and dropped from the URL (read once)
  const embed = url.searchParams.get('embed') === '1';
  const memParam = url.searchParams.get('memory');
  const memoryBytes = memParam !== null ? Math.min(6 * GiB, Math.max(GiB, Math.round((Number(memParam) * GiB) / (256 * MiB)) * 256 * MiB)) : null;
  const hashCode = codeFromHash(url.hash);
  const page = makeApi(pw, { overlay, embed, hashCode, memoryBytes });
  const internals = { get: null };
  // the public member, and the INTERNAL ones as recording getters (the tests reach them through SIM.internals)
  // globalThis.qed64 (api + the internal members) exists from MODULE START on (main.ts), not while the document is parsed
  const publish = () => {
    pw.qed64 = { api: page.api };
    for (const k of ['relay', 'ui', 'artifacts', 'editor', 'status', 'test']) Object.defineProperty(pw.qed64, k, { enumerable: true, configurable: true, get() { pw._internalTouches.push({ member: k, stack: String(new Error().stack).split('\n').slice(2, 4).join(' | ') }); return internals.get ? internals.get[k] : undefined; } });
  };
  pw._page = page; pw._internals = internals; SIM.pages.push(pw);
  const moduleMs = SIM.moduleDelayMs; // the module script's start (a slow bundle: SIM.moduleDelayMs, read at navigation)
  setTimeout(async () => {
    if (pw._unloaded) return; // retired (about:blank) before its module ran: nothing of this document runs
    doc.readyState = 'interactive';
    publish();
    SIM.frameApiDispatches++;
    globalThis.dispatchEvent({ type: 'qed64:frame-api', detail: { api: page.api, frame: pw } });
    if (hashCode !== null) { pw.location.hash = ''; pw.location.href = url.origin + url.pathname + url.search; SIM.hashDrops++; }
    if (SIM.pageBootFail) { page.bootFailed('refused ?snapshots=…: index.json not found'); return; }
    page.bootStep('fetching manifests…', { stage: 'manifests', phase: 'manifests' });
    const bd = await page.bootDocument();
    SIM.bootDocs.push({ ...bd, embed });
    const q = makeQed(pw, bd.text, overlay, page.hooks);
    internals.get = { relay: q.relay, artifacts: {}, status: () => q.relay.status(), editor: q._editor, test: {} };
    SIM.internals = q; // what a TEST may touch (never the gallery)
    page.bind(q);
    // pageBootFailLateDeath: session 1 died bootFailed first (lastDeath set, the relay rebooting on a new session), THEN main() threw
    if (SIM.pageBootFailLate && SIM.pageBootFailLateDeath) { const r = q.relay; r.lastDeath = { reason: 'bootFailed', message: SIM.pageBootFailLateDeath, seq: ++SIM.deathSeq, session: r.session.id }; r.session = r.makeSession(); r.state = { kind: 'rebooting', reason: 'bootFailed' }; }
    if (SIM.pageBootFailLate) { page.bootFailed(SIM.pageBootFailLate); return; } // main.ts main().catch after bind: boot.failed with a session, no death, nothing retries
    page.hooks.onIn(q.relay.doc.uri, q.relay.doc.version, bd.text); // the editor's didOpen: the first 'document' event
    setTimeout(() => page.editorReady(), 5);
  }, moduleMs);
  setTimeout(() => { if (pw._unloaded) return; doc.readyState = 'complete'; SIM.frame.dispatch('load'); }, moduleMs + 10);
  return pw;
}

// ---------------------------------------------------------------- environment per run
// v1: gallery/pin.json carries an apiRevision (default true; false = a pin.json without one: the gallery's data card)
// pinOverlays: gallery/pin.json's overlays map (undefined: PIN.overlays; null: a pin.json without it, refused; an object: that map);
// servedDirs: where the fake server serves each logical overlay (default: that map, else the bare names)
function setupEnv({ pinOverlays = undefined, servedDirs = undefined, search = '', hash = '', overlays = {}, storage = {}, narrow = false, bootMs = 60, elabMs = 40, pageBootFail = false, pageBootFailLate = null, pageBootFailLateDeath = null, caps = {}, holdBoot = false, v1 = true, caps2 = null, embedWaitMs = 5000 }) {
  for (const t of SIM.timers || []) clearInterval(t); // the previous run's page tickers
  const html = fs.readFileSync(path.join(G, 'index.html'), 'utf8');
  const root = parseHtml(html);
  const byIdEl = (id) => { for (const e of root.walk()) if (e.id === id) return e; return null; };
  const blank = { location: { href: 'about:blank' }, document: { readyState: 'complete' }, focus() {} };
  const pinOv = pinOverlays === undefined ? (PIN.overlays ?? null) : pinOverlays;
  Object.assign(SIM, { pinOverlays: pinOv, servedDirs: servedDirs ?? pinOv ?? { widgets8: 'widgets8' } });
  Object.assign(SIM, { overlays, storage: new Map(Object.entries(storage)), fetchLog: [], navigations: [], positions: [], setValueCalls: 0, rearms: 0, editorFocus: 0, pageFocus: 0, firstSessions: [], clipboard: null, bootMs, elabMs, pageBootFail, page: null, stuck: false, busy: false, stuckVersions: [], restarts: [], toClient: [], fromClient: [], qlive: { probes: 0, answered: 0, stalls: 0, resumed: 0, rescues: 0 }, qedReboots: [], holdBoot, releaseBoot: null, resources: [],
    // the page model's state and the §9 trackers
    v1, caps2, embedWaitMs, pageBootFailLate, pageBootFailLateDeath, timers: [], refuseRestart: false, deathSeq: 0, pages: [], internalTouches: [], storageAccess: [], pageDomTouches: [], setDocCalls: [], setCursorCalls: [], apiRestarts: [], didChanges: 0, bootDocs: [], hashDrops: 0, frameApiDispatches: 0, lastSetDocResult: null, internals: null, offer: null, offerRuns: 0, bootFinished: 0, listenerThrows: [], pageReloads: 0, moduleDelayMs: 15, storageThrow: new Set(), onlyCurrentRun: false, warns: [] });
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
  // the gallery's storage (the tests read SIM.storage directly, so every access here is the gallery's)
  def('localStorage', { getItem: (k) => { SIM.storageAccess.push({ by: 'gallery', key: k, op: 'get' }); return SIM.storage.has(k) ? SIM.storage.get(k) : null; }, setItem: (k, v) => {
    // onlyCurrentRun: an earlier gallery instance of this process (its module and timers outlive its setupEnv; a real
    // browser drops them with their document) never writes the storage of the case under test
    if (SIM.onlyCurrentRun) { const r = (/gallery\.js\?run=(\d+)/.exec(new Error().stack || '') || [])[1]; if (r !== String(runN)) { SIM.storageAccess.push({ by: 'stale-gallery', key: k, op: 'set-dropped', run: r }); return; } }
    SIM.storageAccess.push({ by: 'gallery', key: k, op: 'set' }); if (SIM.storageThrow.has(k)) throw new Error('QuotaExceededError (simulated)'); SIM.storage.set(k, String(v)); } });
  def('navigator', { clipboard: { writeText: async (t) => { SIM.clipboard = t; } }, ...(caps.deviceMemory !== undefined ? { deviceMemory: caps.deviceMemory } : {}) });
  def('getComputedStyle', (el) => ({ display: el.id === 'rail' && narrow ? 'none' : 'flex' }));
  def('requestAnimationFrame', (fn) => setTimeout(fn, 16));
  g.matchMedia = () => ({ matches: narrow, addEventListener() {} });
  g.addEventListener = (t, fn) => (winListeners[t] ||= []).push(fn);
  g.dispatchEvent = (ev) => { for (const fn of winListeners[ev.type] || []) fn(ev); return true; }; // the V1 page's 'qed64:frame-api' on its parent
  g.focus = () => {};
  SIM.fireWin = (t) => { for (const fn of winListeners[t] || []) fn({ type: t }); };
  g.fetch = async (url, init = {}) => {
    const u = new URL(url, `${ORIGIN}/showcase/`);
    SIM.fetchLog.push({ path: u.pathname, method: init.method || 'GET', navigations: SIM.navigations.length });
    const res = (status, ct, body = '', extra = {}) => { const h = new Map(Object.entries({ 'content-type': ct, ...extra })); return { ok: status >= 200 && status < 300, status, headers: { get: (k) => h.get(k.toLowerCase()) ?? null }, text: async () => body, json: async () => JSON.parse(body) }; };
    if (u.pathname === '/showcase/pin.json') { // the ACTIVE pin's view (build-gallery.mjs reads release/<pin>/dist/qed64-build.json); SIM.v1 false: without apiRevision
      const pj = { ...PIN, apiRevision: SIM.v1 ? (PIN.apiRevision ?? '1.0.0') : null, shell: SIM.v1 ? (PIN.shell ?? 'shell-0000000000000000') : null };
      if (SIM.pinOverlays === null) delete pj.overlays; else pj.overlays = SIM.pinOverlays;
      return res(200, 'application/json', JSON.stringify(pj), { 'x-showcase-pin': `${PIN.pin} ${PIN.buildId}` });
    }
    if (u.pathname.startsWith('/showcase/')) { const f = path.join(G, u.pathname.slice(10)); return fs.existsSync(f) ? res(200, 'application/json', fs.readFileSync(f, 'utf8')) : res(404, 'text/plain'); }
    if (u.pathname === `/runtime/runtime-manifest.${PIN.buildId}.json`) return res(200, 'application/json', JSON.stringify({ buildId: PIN.buildId, leanVersion: '4.34.0' }));
    const m = /^\/snapshots\/([^/]+)\/(.*)$/.exec(u.pathname);
    const ov = m && servedOverlay(m[1]);
    if (!ov) return res(404, 'text/plain');
    const index = { schema: 'qed64.snapshot-index/v1', snapshots: [
      { name: 'init', url: '/snapshots/init.35c8c5f5419e0c33.snapz', digest: `sha256:${'a'.repeat(64)}`, bytes: 1, transfer: 1000, imports: [], runtime: PIN.buildId },
      { name: 'mathlib', url: '/snapshots/widgets.0123456789abcdef.snapz', digest: `sha256:${'b'.repeat(64)}`, bytes: 2, transfer: 2000, imports: ov.imports, runtime: ov.runtime || PIN.buildId },
    ] };
    if (m[2] === 'index.json') return res(200, 'application/json', JSON.stringify(index));
    const e = index.snapshots.find((x) => x.url.split('/').pop() === m[2]);
    return e ? res(200, 'application/octet-stream', '', { 'content-length': String(e.transfer) }) : res(404, 'text/plain');
  };
}
let runN = 0;
async function loadGallery() { await import(`${pathToFileURL(path.join(G, 'gallery.js')).href}?run=${++runN}`); return globalThis.__showcase; }
const ALL7 = ['QED64.Essential', 'ChartKit', 'ExprXRay', 'GraphScope', 'HasseView', 'IntervalInspector', 'SimpLens', 'TreeScope'];
const st = () => globalThis.__showcase.status();
const settled = (p) => p.then((v) => ({ ok: true, v }), (e) => ({ ok: false, e }));
// V1 runs (the page API, QED64 embedding contract v1): the persisted document's key, and the §9 check every V1 run ends with
const DOC_KEY = 'qed64-showcase:document';
const noInternals = (what) => {
  const touches = SIM.pages.flatMap((p) => p._internalTouches); const dom = SIM.pages.flatMap((p) => p.document._touches);
  const buf = SIM.storageAccess.filter((a) => a.by === 'gallery' && a.key === 'qed64.buffer').length;
  return ok(touches.length === 0 && buf === 0 && dom.length === 0 && !SIM.pages.some((p) => Object.keys(p).some((k) => /^__qed64/.test(k))) && SIM.listenerThrows.length === 0,
    `${what}: the gallery touched no internal on ${SIM.pages.length} page document(s) (qed64.relay/ui/editor/status/test: ${touches.length}${touches.length ? ` — ${touches.slice(0, 3).map((t) => `${t.member} @ ${t.stack}`).join('; ')}` : ''}), never read or wrote qed64.buffer (${buf}), touched no page DOM id (${dom.join(',') || 'none'}), set no __qed64* name; no api listener threw (${SIM.listenerThrows.length})`);
};
const frameUrlOf = (nav) => nav.src;
let api, s, r; // the gallery's test API, its status and a select() result, reassigned by each run

// ================================================================ run 2 (V1): explicit overlay missing → no navigation; Retry after it appears
console.log('\n== run 2 (V1): ?overlay=widgets9 missing → preflight card, no navigation; Retry once it exists');
setupEnv({ v1: true, search: '?overlay=widgets9', overlays: {} });
api = await loadGallery();
await until(() => st().phase === 'error', 5000, 'run2 error');
s = st();
ok(SIM.navigations.length === 0 && s.error.kind === 'preflight' && /widgets9/.test(s.error.title) && s.error.checks.some((c) => !c.ok && c.id === 'index-http'), `no navigation; card "${s.error.title}" with failing check index-http`);
ok(!SIM.byIdEl('error-card').hidden && SIM.byIdEl('error-checks').children.length >= 2 && !SIM.byIdEl('error-retry').hidden && !SIM.byIdEl('error-dismiss').hidden && !SIM.byIdEl('error-stock').hidden
  && SIM.byIdEl('stage-veil').getAttribute('aria-hidden') === 'true', 'error card visible with the check list, Try again, Dismiss and the stock link; the veil behind it is aria-hidden');
SIM.overlays.widgets9 = { imports: ALL7 };
SIM.byIdEl('error-retry').click();
await until(() => st().phase === 'ready', 8000, 'run2 retry ready');
ok(st().overlay === 'widgets9' && st().mode === 'v1' && SIM.navigations.length === 1 && SIM.byIdEl('error-card').hidden, 'Try again → preflight passes, boots, card hidden');
noInternals('preflight card, Try again');

// ================================================================ run 3 (V1): unpaired runtime → refused before navigation
console.log('\n== run 3 (V1): unpaired widgets8 → refused before navigation');
setupEnv({ v1: true, overlays: { widgets8: { imports: ALL7, runtime: 'wasm64-0000000000000000' } } });
api = await loadGallery();
await until(() => st().phase === 'error', 5000, 'run3 error');
s = st();
ok(SIM.navigations.length === 0 && s.preflight.attempts[0].failed.includes('entry-mathlib-runtime') && /not paired/.test(s.error.detail), `no navigation; failed [${s.preflight.attempts[0].failed}]; "${s.error.detail.slice(0, 80)}…"`);

// ================================================================ run 5 (V1): narrow layout stacking
console.log('\n== run 5 (V1): narrow screen');
{ // narrow (V1): the stack style goes into the page document; Monaco follows the resize by itself (no relayout call)
  setupEnv({ v1: true, overlays: { widgets8: { imports: ALL7 } }, narrow: true });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run5 narrow ready');
  await sleep(300);
  ok(SIM.page && SIM.page.document._styles.some((x) => x.id === 'qed64-showcase-stack'), 'at narrow width the stack style is injected into the page');
  const sel = SIM.byIdEl('example-select');
  sel.value = 'hasse-view'; sel.dispatch('change');
  await until(() => st().phase === 'ready' && st().shown === 'hasse-view', 5000, 'select');
  ok(api.currentText() === byId['hasse-view'].text && sel.children.length === 8, 'narrow select (8 options) switches the example');
  noInternals('narrow');
}

// ================================================================ run 14: browser capabilities, checked before anything boots (hardening lane)
console.log('\n== run 14 (V1 boots): a browser without cross-origin isolation / SharedArrayBuffer / Memory64 / WebAssembly gets the capability card and boots nothing; low memory warns with "Try anyway"');
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
  setupEnv({ v1: true, hash: '#hasse-view', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } }, caps: { deviceMemory: 4 } });
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
  ok(s.shown === 'hasse-view' && s.mode === 'v1' && s.caps.override === true && SIM.navigations.length === 1 && SIM.byIdEl('error-card').hidden, `"Try anyway" boots as usual: ${s.shown} ready, override recorded`);
  noInternals('Try anyway');
  // a capable browser that reports 8 GB (the threshold) passes every check
  setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } }, caps: { deviceMemory: 8 } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run14 capable');
  ok(st().caps.ok && st().caps.deviceMemory === 8 && st().caps.checks.every((c) => c.ok) && st().mode === 'v1', 'deviceMemory 8, isolated, SharedArrayBuffer, Memory64: every check passes and the gallery boots');
  noInternals('capable boot');
}

// ================================================================ run 15 (V1): a slow first visit (last-mile lane defect: 360 s boot timeout at 10 Mbit/s)
console.log('\n== run 15 (V1): slow first boot: progress re-arms the boot timeout (notice, no card); a true stall shows the card; a later ready closes it and finishes the boot');
{
  const W8 = { widgets8: { imports: [...ALL7, 'DistLens'] } };
  const KNOBS = '?bootTimeout=0.6&bootStall=0.5&bootNotice=0.3'; // 600 ms budget, 500 ms without progress = stall, early notice from 300 ms
  const LABEL = 'preparing the mathlib environment (0.4 GiB — one-time)';
  const TOTAL = 400e6;
  const card = () => SIM.byIdEl('error-card');
  // the page's 'boot' events (EMBEDDING.md §2.4): QED64's own step label and figures, unit bytes
  const prog = (loaded) => SIM.frame._win._page.bootStep(LABEL, { stage: 'snapshot', subject: 'mathlib', phase: 'snapshot', loaded, total: TOTAL, unit: 'bytes' });
  // (a) slow but steady: 2 s of new bytes (> budget + stall window): never the card, a "still downloading" notice instead
  setupEnv({ v1: true, search: KNOBS, hash: '#chart-kit', overlays: W8, holdBoot: true });
  api = await loadGallery();
  await until(() => st().phase === 'booting' && SIM.internals && st().boot.waiting, 3000, 'run15a booting');
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
  ok(s.notice === `Still downloading: ${LABEL} — 200 MB of 400 MB so far. A first visit downloads several hundred MB, which takes minutes on a slow connection; later visits start from this browser's storage.` && s.boot.noticeShown === 1 && !SIM.byIdEl('notice').hidden && SIM.byIdEl('notice').classList.contains('is-slow')
    && firstNotice && firstNotice.elapsedMs >= 600 && s.boot.pageBootOverlay === true,
    `non-blocking notice "${(s.notice || '').slice(0, 72)}…" (shown once, first at ${firstNotice && firstNotice.elapsedMs} ms: QED64's own boot overlay is up (status().boot.overlay), so from the budget on)`);
  // The status line is rendered on the gallery's 250 ms monitor tick, not on each progress call, so the loop's last sample
  // (100 ms after the 20th call) saw "200 MB" only when a tick fell into those 100 ms: about 100 ms of timer drift over the
  // 2 s loop was tolerated, and one 200 ms event-loop stall on a loaded host lost it (closure lane, 2026-10-03: a deploy
  // rehearsal's G1 failed once with "108 ok, 1 failed"; 4 of 4 runs with an injected 200 ms stall per second failed here).
  // Keep sampling until a tick has rendered the 20th call: at most 350 ms (> one tick, < the 500 ms stall window).
  for (const tw = Date.now(); Date.now() - tw < 350 && ![...lines].some((l) => / · 200 MB of 400 MB$/.test(l)); await sleep(10)) lines.add(SIM.byIdEl('status-text').textContent);
  ok(s.boot.source === 'api-events' && s.boot.uiTapped === false && s.boot.apiBootEvents >= 21 && s.boot.bytes === 200e6 && s.boot.sources.bytes === 20 && [...lines].some((l) => /^Starting Lean in your browser… .* · 200 MB of 400 MB$/.test(l)),
    `progress from ${s.boot.apiBootEvents} 'boot' events (no ui wrap); ${s.boot.bytes / 1e6} MB of progress counted; status line "${[...lines].pop()}"`);
  SIM.holdBoot = false; SIM.releaseBoot();
  await until(() => st().phase === 'ready', 5000, 'run15a ready');
  s = st();
  ok(s.shown === 'chart-kit' && s.error === null && s.notice === null && SIM.byIdEl('notice').hidden && card().hidden && s.cursor && s.cursor.lineNumber === byId['chart-kit'].firstCursor.lineNumber && s.bootMs >= 2000 && s.boot.waiting === null,
    `download done → ready: chart-kit at L${s.cursor && s.cursor.lineNumber}, the notice is gone, boot ${Math.round(s.bootMs)} ms`);
  ok(!SIM.byIdEl('notice').classList.contains('is-slow'), 'the notice\'s slow-download placement is cleared with it');
  noInternals('slow but steady boot');

  // (b) a true stall: some bytes, then only re-sent bytes of the same download (a retry is no progress) → the card
  setupEnv({ v1: true, search: KNOBS, hash: '#chart-kit', overlays: W8, holdBoot: true, storage: {} });
  api = await loadGallery();
  await until(() => st().phase === 'booting' && SIM.internals && st().boot.waiting, 3000, 'run15b booting');
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
  noInternals('slow boot, stall, late ready');

  // (e) page resources: a NEW URL is progress, a page re-fetching one URL (retry loop, cache-busting query) is not → the card
  setupEnv({ v1: true, search: KNOBS, hash: '#chart-kit', overlays: W8, holdBoot: true, storage: {} });
  api = await loadGallery();
  await until(() => st().phase === 'booting' && SIM.internals && st().boot.waiting, 3000, 'run15e booting');
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
  noInternals('page resources');

  // (d) defaults, and a normal boot is untouched by the progress logic
  setupEnv({ v1: true, hash: '#chart-kit', overlays: W8 });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run15d ready');
  s = st();
  ok(s.boot.timeoutMs === 360000 && s.boot.stallMs === 240000 && s.boot.noticeMs === 120000 && s.boot.noticeShown === 0 && s.boot.stalls === 0 && s.boot.recovered === 0 && s.notice === null && s.boot.source === 'api-events',
    `defaults: budget ${s.boot.timeoutMs / 1000} s, stall window ${s.boot.stallMs / 1000} s, early notice ${s.boot.noticeMs / 1000} s; a normal boot shows no notice and no card`);
  noInternals('boot defaults');
}

// ================================================================ V1 runs: the page API (QED64 embedding contract v1)

// ================================================================ run 16: V1 boot (embed + #code=), switch, persistence, adopted reload
console.log('\n== run 16 (V1): frame-api at module start, embed mode + #code=, setDocument switches, document persistence, adopted reload re-seeded synchronously');
{
  const SENTINEL = '-- sentinel: embed mode must not read or write this\n';
  const ORIG = 'theorem original : True := trivial\n';
  // ?overlay=partial7: a literal directory holding the 7-root region (no DistLens), so the refused-header path below stays
  // covered now that the one default overlay, widgets8, serves all eight (P2)
  setupEnv({ v1: true, search: '?overlay=partial7', hash: '#hasse-view', overlays: { partial7: { imports: ALL7 } }, storage: { 'qed64.buffer': SENTINEL, 'qed64-showcase:saved': ORIG } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run16 ready');
  await sleep(300); // the 250 ms monitor renders the status line and mirrors the api projections
  s = st();
  const nav = SIM.navigations.find((n) => n.src !== 'about:blank');
  const HV = byId['hasse-view'];
  ok(nav && frameUrlOf(nav) === `/?embed=1&snapshots=snapshots/partial7#code=${encodeURIComponent(HV.text)}` && SIM.navigations.length === 1,
    `frame URL: ${frameUrlOf(nav).slice(0, 60)}… (embed=1, the overlay, #code= the example)`);
  ok(SIM.bootDocs.length === 1 && SIM.bootDocs[0].source === 'hash' && SIM.bootDocs[0].text === HV.text && SIM.bootDocs[0].embed === true && SIM.hashDrops === 1 && SIM.frame._win.location.hash === '' && SIM.frameApiDispatches === 1,
    `the page booted the #code= document (read once: the fragment was dropped, hashDrops ${SIM.hashDrops}), after dispatching qed64:frame-api at module start`);
  ok(SIM.storage.get('qed64.buffer') === SENTINEL && s.seed && s.seed.action === 'embed' && s.seed.saved === false && !SIM.storageAccess.some((a) => a.key === 'qed64.buffer'),
    `qed64.buffer untouched by page and gallery (sentinel kept; seed.action ${s.seed && s.seed.action})`);
  ok(s.mode === 'v1' && s.api.present === true && s.api.via === 'frame-api' && s.api.embed === true && s.api.revision === '1.0.0' && s.api.capabilities && s.api.capabilities.editorRpc === true && s.api.capabilities.widgetSourceCache === true && s.api.pinRevision === '1.0.0',
    `status().api = {present, via ${s.api.via}, embed ${s.api.embed}, revision ${s.api.revision}, capabilities …}`);
  ok(!('bridge' in s) && api.bridgeStats === undefined && api.version === 10 && !SIM.warns.some((w) => /widgetSourceCache/.test(w)),
    'no RPC bridge (status().bridge and bridgeStats() are gone, __showcase.version 10); editorRpc and widgetSourceCache are the page\'s own, no warning');
  ok(s.liveness.probe === 'stood-down' && s.liveness.sent === 0 && s.liveness.answered === 0 && s.liveness.missed === 0 && s.liveness.mode === 'auto' && s.liveness.qed64.builtIn === true && s.liveness.qed64.api === true && s.liveness.qed64.probeAfterMs === 6000 && s.liveness.qed64.wedgeAfterMs === 12000 && s.liveness.qed64.graceMs === 4000 && s.liveness.qed64.stalled === false && s.liveness.qed64.totals.probes === null && SIM.fromClient.length === 0,
    `the liveness probe stood down (probe ${s.liveness.probe}, sent ${s.liveness.sent}); status().liveness.qed64 mirrors the api projection (stalled ${s.liveness.qed64.stalled}, probeAfterMs ${s.liveness.qed64.probeAfterMs})`);
  ok(s.stall.tapped === true && s.stall.source === 'api-events' && s.stall.progressMsgs >= 2 && s.boot.source === 'api-events' && s.boot.uiTapped === false && s.boot.apiBootEvents >= 2 && s.boot.sources.status > 0,
    `progress from api events: stall ${s.stall.progressMsgs} msgs (fileProgress + diagnostics), boot ${s.boot.apiBootEvents} boot events, ${s.boot.sources.status} status marks; no relay tap, no ui wrap`);
  ok(s.qed64 && s.qed64.phase === 'ready' && JSON.stringify(s.qed64.snapshots) === JSON.stringify(['init', 'mathlib']) && s.qed64.boot && s.qed64.boot.done === true && s.qed64.boot.overlay === false && s.qed64.liveness && s.qed64.memory && s.qed64.memory.initialBytes === 2048 * MiB && s.qed64.offer === null,
    `status().qed64 carries the api projections: snapshots ${JSON.stringify(s.qed64.snapshots)}, boot done/overlay ${s.qed64.boot.done}/${s.qed64.boot.overlay}, memory ${s.qed64.memory.initialBytes / MiB} MiB, offer null`);
  ok(s.cursor && s.cursor.lineNumber === HV.firstCursor.lineNumber && s.cursor.column === 1 && SIM.setCursorCalls.length >= 1 && SIM.editorFocus > 0 && SIM.pageFocus > 0 && api.currentText() === HV.text,
    `cursor placed through api.setCursor at L${s.cursor && s.cursor.lineNumber} (focus); currentText() through api.getDocument()`);
  ok(s.document.version === SIM.internals.relay.doc.version && s.document.length === HV.text.length && s.document.persisted === true && SIM.storage.get(DOC_KEY) === HV.text && s.document.lastEventAgoMs !== null,
    `'document' events: status().document v${s.document.version} (${s.document.length} chars), persisted under ${DOC_KEY}`);
  { // the veil and the chips behave as in legacy mode
    const chips = Object.fromEntries(EX.map((e) => [e.id, SIM.byIdEl('card-list').querySelectorAll('.card').find((c) => c.dataset.id === e.id).querySelector('.chip').textContent]));
    ok(chips['hasse-view'] === 'live' && chips['dist-lens'] === 'not in partial7' && SIM.byIdEl('stage-veil').classList.contains('is-hidden'), `chips: hasse-view=${chips['hasse-view']}, dist-lens=${chips['dist-lens']}; veil hidden`);
  }
  noInternals('boot');
  // switch: setDocument(text, {cursor, focus}) → {version, unchanged:false} → ready at status.version >= that version
  const sd0 = SIM.setDocCalls.length; const v0 = SIM.setValueCalls;
  r = await api.select('simp-lens');
  const SL = byId['simp-lens'];
  const lastSet = SIM.setDocCalls[SIM.setDocCalls.length - 1];
  ok(r.shown === 'simp-lens' && api.currentText() === SL.text && SIM.setDocCalls.length === sd0 + 1 && lastSet.opts.cursor && lastSet.opts.cursor.lineNumber === SL.firstCursor.lineNumber && lastSet.opts.focus === false && lastSet.opts.undoable === false
    && SIM.lastSetDocResult && SIM.lastSetDocResult.unchanged === false && r.qed64.version >= SIM.lastSetDocResult.version && r.cursor.lineNumber === SL.firstCursor.lineNumber && SIM.setValueCalls === v0 + 1,
    `select('simp-lens'): one api.setDocument({cursor L${lastSet.opts.cursor && lastSet.opts.cursor.lineNumber}, focus false (shown() focuses after ready), undoable false}) → v${SIM.lastSetDocResult && SIM.lastSetDocResult.version}; ready at qed64 v${r.qed64.version} >= it; switch ${Math.round(r.lastSwitchMs)} ms`);
  // storm: the last wins, the rest SUPERSEDED (the setDocument promise is raced against the selection token)
  const storm = ['chart-kit', 'expr-xray', 'tree-scope', 'interval-inspector', 'chart-kit', 'graph-scope'].map((id) => settled(api.select(id)));
  const out = await Promise.all(storm);
  s = st();
  ok(out[5].ok && s.shown === 'graph-scope' && api.currentText() === byId['graph-scope'].text && out.slice(0, 5).every((x) => !x.ok && x.e.code === 'SUPERSEDED'),
    `storm of 6: last (graph-scope) resolves, first 5 rejected SUPERSEDED (${SIM.setDocCalls.length - sd0 - 1} setDocument calls)`);
  // identical text: setDocument resolves {unchanged:true} with no new change; ready at the current version; the cursor is placed
  const dc = SIM.didChanges; const sd1 = SIM.setDocCalls.length;
  r = await api.select('graph-scope');
  ok(r.phase === 'ready' && SIM.setDocCalls.length === sd1 + 1 && SIM.lastSetDocResult.unchanged === true && SIM.didChanges === dc && r.cursor.lineNumber === byId['graph-scope'].firstCursor.lineNumber,
    `the same example again: setDocument → {unchanged:true, v${SIM.lastSetDocResult.version}}, no didChange (${SIM.didChanges - dc}), ready, cursor placed`);
  // refused header (DistLens not in partial7)
  r = await api.select('dist-lens');
  ok(r.phase === 'refused' && /refused the header: DistLens is not in the partial7 overlay/.test(r.notice || '') && r.qed64.phase === 'headerRefused' && r.qed64.header.missing[0] === 'DistLens' && SIM.apiRestarts.length === 0,
    `dist-lens on partial7 → refused (live qed64 ${r.qed64.phase}, missing ${r.qed64.header.missing}); the session has mathlib, so no widening restart`);
  r = await api.select('tree-scope');
  ok(r.phase === 'ready' && r.notice === null, 'next available example clears the refusal notice');
  // edited detection through api.getDocument(), Reset through setDocument
  SIM.internals._model.setValue(`${byId['tree-scope'].text}\n-- my edit\n`);
  await until(() => st().edited === true, 3000, 'run16 edited');
  ok(st().edited === true && SIM.byIdEl('card-list').querySelectorAll('.card').find((c) => c.dataset.id === 'tree-scope').querySelector('.chip').textContent === 'edited', 'an edit is detected through api.getDocument(): chip “edited”');
  await until(() => SIM.storage.get(DOC_KEY) === `${byId['tree-scope'].text}\n-- my edit\n`, 3000, 'run16 persisted edit');
  ok(SIM.storage.get(DOC_KEY) === `${byId['tree-scope'].text}\n-- my edit\n`, `the edited text was persisted under ${DOC_KEY} within a second`);
  const sd2 = SIM.setDocCalls.length;
  await api.reset(); await sleep(300);
  ok(st().edited === false && api.currentText() === byId['tree-scope'].text && SIM.setDocCalls.length === sd2 + 1 && st().phase === 'ready', 'Reset restores the example through setDocument and clears “edited”');
  // halted relay: the card; Reset = api.restart() (re-arm) then setDocument
  SIM.internals.relay.state = { kind: 'halted' }; SIM.internals.relay.lastDeath = { reason: 'crash', message: 'simulated', seq: 1, session: SIM.internals.relay.session.id };
  await until(() => st().phase === 'halted', 3000, 'run16 halted');
  ok(!SIM.byIdEl('error-card').hidden && /stopped/.test(SIM.byIdEl('error-title').textContent) && st().liveness.events.some((e) => e.source === 'qed64-death' && e.kind === 'crash'),
    `halted relay → card "${SIM.byIdEl('error-title').textContent}"; the 'death' event was recorded (qed64-death)`);
  const ar0 = SIM.apiRestarts.length;
  SIM.byIdEl('reset-btn').click(); await sleep(30);
  await until(() => st().phase === 'ready', 5000, 'run16 ready after halted reset');
  ok(SIM.rearms === 1 && SIM.apiRestarts.length === ar0 + 1 && SIM.apiRestarts[ar0].opts === undefined && SIM.apiRestarts[ar0].state === 'halted' && st().stall.events.some((e) => e.source === 'reset-halted' && e.how === 'api.restart') && SIM.byIdEl('error-card').hidden,
    'Reset on a halted relay: api.restart() with no arguments re-armed it (1 rearm), then the example; card closed');
  // the saved-buffer UI of earlier (legacy) visits: restoreSaved goes through setDocument
  ok(SIM.byIdEl('restore-btn').hidden === false, '“Open my saved buffer” (a buffer kept by an earlier legacy visit) is offered');
  const sd3 = SIM.setDocCalls.length;
  SIM.byIdEl('restore-btn').click(); await sleep(80);
  ok(api.currentText() === ORIG && st().custom === true && st().current === null && SIM.setDocCalls.length === sd3 + 1 && SIM.setDocCalls[sd3].opts.cursor && SIM.setDocCalls[sd3].opts.cursor.lineNumber === 1 && SIM.setDocCalls[sd3].opts.undoable === false,
    'Open my saved buffer: api.setDocument(text, {cursor 1:1, undoable false}); no card is current');
  await until(() => SIM.storage.get(DOC_KEY) === ORIG, 3000, 'run16 persisted orig');
  // an adopted reload (the page's own Reload / a user reload of the frame): the new document has no #code= any more (dropped);
  // the gallery must call setDocument SYNCHRONOUSLY in the frame-api handler, else embed mode boots the empty document
  const navs = SIM.navigations.length; const sd4 = SIM.setDocCalls.length;
  SIM.page.dispatchEvent({ type: 'pagehide' });
  SIM.page = makePage(SIM.frame._win.location.href.replace(ORIGIN, '')); SIM.frame._win = SIM.page; // the reload: same URL, no fragment
  await until(() => SIM.bootDocs.length === 2, 3000, 'run16 reload boot doc');
  const bd = SIM.bootDocs[1];
  ok(bd.source === 'setDocument' && bd.text === ORIG && SIM.setDocCalls[sd4] && SIM.setDocCalls[sd4].preBoot === true && SIM.setDocCalls[sd4].length === ORIG.length,
    `adopted reload: setDocument(saved document) arrived BEFORE the page read its boot document (preBoot ${SIM.setDocCalls[sd4] && SIM.setDocCalls[sd4].preBoot}); the page booted it (source ${bd.source}), not the empty document`);
  await until(() => st().phase === 'ready' && st().booted, 5000, 'run16 adopt');
  s = st();
  ok(SIM.navigations.length === navs && s.api.adopted === 1 && s.api.adoptSet && s.api.adoptSet.from === 'saved' && s.api.docs === 2 && s.custom === true && s.current === null && api.currentText() === ORIG && s.op.label === 'reload',
    `adopted: no new navigation, api.adopted ${s.api.adopted} (from ${s.api.adoptSet && s.api.adoptSet.from}), docs ${s.api.docs}, the user buffer followed (custom), reload ${Math.round(s.bootMs)} ms`);
  // then an example again, and a reload while an example is shown re-seeds that example (its text was persisted)
  r = await api.select('chart-kit');
  ok(r.phase === 'ready' && api.currentText() === byId['chart-kit'].text && r.qed64.snapshots.join() === 'init,mathlib', `select('chart-kit') after the adopted reload: ready on [${r.qed64 && r.qed64.snapshots}]`);
  await until(() => SIM.storage.get(DOC_KEY) === byId['chart-kit'].text, 3000, 'run16 persisted chart-kit');
  SIM.page.dispatchEvent({ type: 'pagehide' });
  SIM.page = makePage(SIM.frame._win.location.href.replace(ORIGIN, '')); SIM.frame._win = SIM.page;
  await until(() => st().api.adopted === 2, 3000, 'run16 second frame-api'); // the new document's frame-api (the old page's api is retired)
  const pSel = settled(api.select('tree-scope')); // a selection during the adoption waits for the adopted page
  await until(() => st().phase === 'ready' && st().shown === 'tree-scope', 8000, 'run16 adopt then select');
  const rSel = await pSel;
  ok(rSel.ok && SIM.bootDocs[2].text === byId['chart-kit'].text && SIM.bootDocs[2].source === 'setDocument' && SIM.navigations.length === navs && st().api.adopted === 2,
    `a second adopted reload re-seeded the shown example (chart-kit) synchronously; a selection made meanwhile waited for it (tree-scope ready, no navigation) [sel ${rSel.ok}, bootDoc2 ${SIM.bootDocs[2] && SIM.bootDocs[2].source} ${SIM.bootDocs[2] && SIM.bootDocs[2].text === byId['chart-kit'].text}, navs ${SIM.navigations.length}/${navs}, adopted ${st().api.adopted}]`);
  { // persistDocument writes at most once per second: a 'document' text still in that throttle is what an adopted reload must re-seed
    const CK = byId['chart-kit'].text;
    r = await api.select('chart-kit');
    await until(() => SIM.storage.get(DOC_KEY) === CK, 3000, 'run16p persisted chart-kit');
    await sleep(1050); // past the throttle: the next forwarded text is written at once, the one after it waits
    const T1 = `${CK}-- first edit\n`; const T2 = `${CK}-- second edit\n`; const T3 = `${CK}-- third edit\n`;
    SIM.internals._model.setValue(T1);
    await until(() => SIM.storage.get(DOC_KEY) === T1, 2000, 'run16p T1 written');
    SIM.internals._model.setValue(T2);
    await until(() => st().document.length === T2.length, 2000, 'run16p T2 event');
    ok(SIM.storage.get(DOC_KEY) === T1 && st().document.length === T2.length, `two forwards within a second: the key holds the first edit, the second is throttled (status().document v${st().document.version} already reports it)`);
    const nb = SIM.bootDocs.length; const ad = st().api.adopted;
    SIM.page = makePage(SIM.frame._win.location.href.replace(ORIGIN, '')); SIM.frame._win = SIM.page; // a reload WITHOUT the old page's pagehide
    await until(() => SIM.bootDocs.length === nb + 1, 3000, 'run16p reload boot doc');
    ok(SIM.bootDocs[nb].text === T2 && SIM.bootDocs[nb].source === 'setDocument' && SIM.storage.get(DOC_KEY) === T2, 'the adopted reload re-seeded the NEWEST text (the throttled second edit), flushed to the key first');
    await until(() => st().phase === 'ready' && st().booted && st().api.adopted === ad + 1, 5000, 'run16p adopt');
    ok(api.currentText() === T2 && st().api.adoptSet.from === 'saved' && st().api.adoptSet.length === T2.length, `adopted: the page shows the second edit (adoptSet from ${st().api.adoptSet.from})`);
    // the frame's own pagehide flushes a throttled text as well (the gallery's listener on the framed window, §9)
    await until(() => st().document.length === T2.length && st().document.persisted, 2000, 'run16p T2 persisted on the new page');
    SIM.internals._model.setValue(T3);
    await until(() => st().document.length === T3.length, 2000, 'run16p T3 event');
    const wasPending = SIM.storage.get(DOC_KEY) !== T3;
    SIM.page.dispatchEvent({ type: 'pagehide' });
    ok(wasPending && SIM.storage.get(DOC_KEY) === T3, 'the frame\'s pagehide flushed the throttled third edit to the key before any new document could read it');
    const nb2 = SIM.bootDocs.length;
    SIM.page = makePage(SIM.frame._win.location.href.replace(ORIGIN, '')); SIM.frame._win = SIM.page;
    await until(() => SIM.bootDocs.length === nb2 + 1, 3000, 'run16p reload 2');
    await until(() => st().phase === 'ready' && st().booted && api.currentText() === T3, 5000, 'run16p adopt 2');
    ok(SIM.bootDocs[nb2].text === T3, 'and the reload after it booted the third edit');
    r = await api.select('tree-scope');
    ok(r.phase === 'ready' && api.currentText() === byId['tree-scope'].text, 'an example again after the edited reloads');
  }
  noInternals('switches, reset, restore, adopted reloads');
}

// ================================================================ run 17: V1 ?mem=3 → &memory=3 (no light session, no wrap)
console.log('\n== run 17 (V1): ?mem=3 is passed as &memory=3; applied = api.status().memory.initialBytes');
{
  setupEnv({ v1: true, search: '?mem=3', hash: '#graph-scope', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run17 ready');
  await sleep(300);
  s = st();
  const nav = SIM.navigations.find((n) => n.src !== 'about:blank');
  ok(nav.src.startsWith(`/?embed=1&snapshots=snapshots/${PDIR('widgets8')}&memory=3#code=`) && SIM.bootDocs[0].text === byId['graph-scope'].text && SIM.firstSessions.length === 1 && SIM.firstSessions[0].initialBytes === 3 * GiB && SIM.firstSessions[0].snapshots.join() === 'init,mathlib',
    `frame URL carries &memory=3; the FIRST session is the example's [init,mathlib] at ${SIM.firstSessions[0].initialBytes / GiB} GiB (no light session, no placeholder)`);
  ok(s.mem.requestedGiB === 3 && s.mem.bytes === 3 * GiB && s.mem.ok && s.mem.applied === true && s.mem.wrapped === false && s.mem.light === null && s.mem.sessions.length === 0 && s.mem.telemetry === null && s.mem.memory && s.mem.memory.initialBytes === 3 * GiB && s.qed64.memory.initialBytes === 3 * GiB,
    `status().mem = {requestedGiB 3, applied ${s.mem.applied} (api.status().memory.initialBytes ${s.mem.memory && s.mem.memory.initialBytes / GiB} GiB), wrapped false, light null, sessions []}`);
  ok(s.shown === 'graph-scope' && s.cursor.lineNumber === byId['graph-scope'].firstCursor.lineNumber && /mem 3 GiB ✓/.test(s.statusLine.detail), `the example is ready at L${s.cursor.lineNumber}; tooltip "${s.statusLine.detail}"`);
  noInternals('?mem');
}

// ================================================================ run 18: V1 stall watchdog, api.restart, QED64's own liveness through events
console.log('\n== run 18 (V1): stall card from api events, Restart Lean = api.restart, Reset on a stall = setDocument then restart, QED64 wedged reboot / liveness / death events');
{
  setupEnv({ v1: true, search: '?stall=5&probeTimeout=0.5', hash: '#graph-scope', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run18 ready');
  const card = () => SIM.byIdEl('error-card');
  const GS = byId['graph-scope'];
  ok(st().stall.thresholdMs === 5000 && st().stall.tapped === true && st().stall.shown === 0 && st().liveness.probe === 'stood-down', `?stall=5: threshold ${st().stall.thresholdMs} ms, api events attached, probe stood down`);
  // (1) QED64's own probe answers (liveness events) while the checker is slow: the card says "still working"; nothing restarted
  SIM.busy = true;
  let ticker = setInterval(() => { SIM.qlive = { ...SIM.qlive, probes: SIM.qlive.probes + 1, answered: SIM.qlive.answered + 1 }; }, 600);
  SIM.internals._model.setValue(`${GS.text}-- slow\n`);
  await until(() => st().stall.active, 9000, 'run18 card 1');
  s = st();
  ok(s.stall.variant === 'alive' && /Lean is still working/.test(SIM.byIdEl('error-title').textContent) && s.liveness.qed64.totals.answered >= 3 && s.liveness.qed64.lastAnsweredAgoMs < 2000 && s.liveness.qed64.lastAnswerAgoMs !== null && s.liveness.sent === 0 && SIM.apiRestarts.length === 0 && SIM.fromClient.filter((m) => m.method === 'textDocument/hover').length === 0 && s.api.events.liveness >= 3,
    `slow but answering: the card says "${SIM.byIdEl('error-title').textContent}" (variant ${s.stall.variant}); ${s.liveness.qed64.totals.answered} 'liveness' answered events, lastAnswerAgoMs ${s.liveness.qed64.lastAnswerAgoMs}; 0 gallery probes, 0 restarts`);
  clearInterval(ticker); SIM.busy = false;
  SIM.internals._model.setValue(GS.text);
  await until(() => st().qed64.phase === 'ready' && !st().stall.active, 8000, 'run18 settle 1');
  // (2) a frozen checker (L7): no event of any kind: the card says "stopped"; Restart Lean = api.restart() (no arguments) → how 'api.restart'
  SIM.stuck = true;
  const EDIT = `${GS.text}-- frozen\n`;
  SIM.internals._model.setValue(EDIT);
  await sleep(3000);
  ok(st().stall.active === false && card().hidden, 'no card before the threshold (3 s of 5 s)');
  await until(() => st().stall.active, 8000, 'run18 card 2');
  ok(st().stall.variant === 'stopped' && /stopped making progress/.test(SIM.byIdEl('error-title').textContent) && SIM.byIdEl('error-retry').textContent === 'Restart Lean' && st().error.kind === 'stalled' && st().liveness.sent === 0 && st().liveness.wedged === 0,
    `frozen: the card "${SIM.byIdEl('error-title').textContent}" after ${st().stall.thresholdMs} ms; the gallery's probe sent nothing (stood down)`);
  const sess = SIM.internals.relay.session.id; const ar = SIM.apiRestarts.length;
  SIM.stuck = false;
  SIM.byIdEl('error-retry').click();
  await until(() => st().qed64.phase === 'ready' && st().qed64.session !== sess, 8000, 'run18 restart ready');
  ok(SIM.apiRestarts.length === ar + 1 && SIM.apiRestarts[ar].opts === undefined && SIM.restarts.length === 1 && st().stall.events.some((e) => e.source === 'card' && e.how === 'api.restart' && e.accepted === true && e.fromSession === sess) && api.currentText() === EDIT && card().hidden && st().stall.restarts === 1
    && st().liveness.events.some((e) => e.source === 'qed64-reboot' && e.from === sess),
    `Restart Lean: api.restart() → {accepted, fromSession ${sess}} → session ${st().qed64.session}; event how 'api.restart'; text kept; a 'reboot' event (reason ${st().liveness.events.find((e) => e.source === 'qed64-reboot' && e.from === sess).reason}) recorded`);
  // (3) Reset example on a stalled checker: setDocument(example), then api.restart()
  SIM.stuck = true;
  SIM.internals._model.setValue(`${EDIT}-- again\n`);
  await until(() => st().stall.active, 8000, 'run18 card 3');
  SIM.stuck = false;
  const sd = SIM.setDocCalls.length; const ar2 = SIM.apiRestarts.length;
  SIM.byIdEl('reset-btn').click();
  await until(() => st().phase === 'ready' && !st().edited && st().qed64.phase === 'ready' && api.currentText() === GS.text, 8000, 'run18 reset after stall');
  ok(SIM.setDocCalls.length === sd + 1 && SIM.apiRestarts.length === ar2 + 1 && SIM.setDocCalls[sd].t <= SIM.apiRestarts[ar2].t && st().stall.events.some((e) => e.source === 'reset' && e.how === 'api.restart') && card().hidden,
    `Reset on the stalled checker: setDocument(example) then api.restart() (${SIM.restarts.length} relay restarts in all); event reset/api.restart; card gone`);
  // (4) QED64's own liveness declares the session wedged and reboots it: 'death' (kind wedged) + 'reboot' (reason wedged) events
  SIM.stuck = true;
  SIM.internals._model.setValue(`${GS.text}-- wedged\n`);
  await sleep(300);
  const sessW = SIM.internals.relay.session.id;
  SIM.qlive = { ...SIM.qlive, probes: SIM.qlive.probes + 1, stalls: SIM.qlive.stalls + 1 };
  await until(() => st().liveness.qed64.stalled === true, 2000, 'run18 stalled');
  ok(st().liveness.qed64.stalled === true && st().liveness.qed64.totals.stalls === 1 && st().liveness.events.some((e) => e.source === 'qed64-stall'), `QED64 reports a stall: liveness.qed64.stalled true (totals.stalls ${st().liveness.qed64.totals.stalls}), event qed64-stall`);
  SIM.qedWedge(); SIM.stuck = false;
  await until(() => st().liveness.qed64.wedgedReboots === 1, 3000, 'run18 wedged seen');
  await until(() => st().qed64.phase === 'ready' && st().qed64.session !== sessW && !st().liveness.qed64.rebooting, 8000, 'run18 wedged reboot ready');
  s = st();
  ok(s.liveness.qed64.wedgedReboots === 1 && s.liveness.qed64.lastReboot && s.liveness.qed64.lastReboot.from === sessW && s.liveness.qed64.lastReboot.to === s.qed64.session && s.liveness.events.some((e) => e.source === 'qed64-wedged' && e.from === sessW)
    && s.liveness.events.some((e) => e.source === 'qed64-death' && e.kind === 'wedged' && e.session === sessW) && /QED64 is restarting it/.test(s.notice || '') && SIM.apiRestarts.length === ar2 + 1 && s.liveness.sent === 0 && api.currentText() === `${GS.text}-- wedged\n`,
    `QED64's wedged reboot ${sessW} → ${s.qed64.session}: wedgedReboots 1, lastReboot {from,to}, events qed64-death(wedged) + qed64-wedged, notice "${s.notice}"; the gallery restarted nothing (api.restart calls unchanged) and probed nothing; text kept`);
  // (5) api.restart() refused ({accepted:false}: a boot in flight, §2.3): the card's page-reload fallback (how 'page-reload')
  {
    const ar3 = SIM.apiRestarts.length; const rl = SIM.pageReloads;
    SIM.stuck = true; SIM.refuseRestart = true;
    SIM.internals._model.setValue(`${GS.text}-- stuck again\n`);
    await until(() => st().stall.active, 8000, 'run18 card 5');
    SIM.byIdEl('error-retry').click();
    await sleep(50);
    ok(SIM.apiRestarts.length === ar3 + 1 && SIM.pageReloads === rl + 1 && st().stall.events.some((e) => e.source === 'card' && e.how === 'page-reload' && e.accepted === false) && !st().stall.active,
      `api.restart() refused ({accepted:false}: a boot in flight) → the card's page-reload fallback (how 'page-reload', ${SIM.pageReloads - rl} reload)`);
    SIM.stuck = false; SIM.refuseRestart = false;
    SIM.internals._model.setValue(GS.text);
    await until(() => st().qed64.phase === 'ready' && !st().stall.active, 8000, 'run18 settle 5');
  }
  noInternals('stall / restart / liveness');
}

// ================================================================ run 19: V1 boot failure, refused header without mathlib (widen restart), capability mismatch, offers, slow boot through boot events
console.log('\n== run 19 (V1): status().boot.failed → the boot card; a session without mathlib widens with api.restart({snapshots}); offers; boot events drive the slow-boot notice; a halt after QED64 served is adopted once it is ready');
{
  // (a) a boot that fails before the relay is bound (a refused parameter / a missing index): the hard card with the page's message
  setupEnv({ v1: true, overlays: { widgets8: { imports: ALL7 } }, pageBootFail: true });
  api = await loadGallery();
  await until(() => st().phase === 'error', 5000, 'run19a error');
  s = st();
  ok(s.error.kind === 'boot' && /could not start/.test(s.error.title) && /refused \?snapshots=/.test(s.error.detail) && s.qed64 && s.qed64.boot.failed === true && s.qed64.session === null && s.boot.pageBootOverlay === true && !SIM.byIdEl('error-card').hidden,
    `boot.failed before the relay → card "${s.error.title}: ${s.error.detail.slice(0, 40)}…" (status().boot.overlay ${s.boot.pageBootOverlay}: the page's own card is up)`);
  await sleep(300);
  ok(SIM.byIdEl('error-card').classList.contains('is-compact') && !SIM.byIdEl('error-note').hidden, 'our card is compact over the page\'s own failed boot card (status().boot.overlay, no DOM read)');
  SIM.pageBootFail = false;
  SIM.byIdEl('error-retry').click();
  await until(() => st().phase === 'ready', 8000, 'run19a retry');
  ok(st().shown === 'chart-kit' && SIM.navigations.filter((n) => n.src === 'about:blank').length === 1 && SIM.byIdEl('error-card').hidden && st().api.docs === 2, 'Try again: the old page retired via about:blank, a new document (frame-api again), ready');
  noInternals('boot failure');
  // (b) a session booted without mathlib (an adopted reload into an init-only user buffer) refuses an example's header: widen with api.restart({snapshots:['init','mathlib']}) and wait on the replacement session
  const MINE = 'theorem mine : True := trivial\n';
  await until(() => SIM.storage.get(DOC_KEY) === byId['chart-kit'].text && st().document.lastEventAgoMs > 1100, 4000, 'run19b chart-kit persisted'); // past the 1 s throttle: no 'document' write pending (it would be flushed over MINE)
  SIM.internals._model.setValue(MINE); // what the relay last forwarded — here a user's own init-only buffer (the adopted reload re-seeds it)
  await until(() => st().document.length === MINE.length && SIM.storage.get(DOC_KEY) === MINE, 3000, 'run19b MINE forwarded and persisted');
  const navs = SIM.navigations.length;
  SIM.page.dispatchEvent({ type: 'pagehide' });
  SIM.page = makePage(SIM.frame._win.location.href.replace(ORIGIN, '')); SIM.frame._win = SIM.page;
  await until(() => st().phase === 'ready' && st().booted && st().shown === null && st().api.adopted === 1, 8000, 'run19b adopt');
  ok(api.currentText() === MINE && st().qed64.snapshots.join() === 'init' && SIM.navigations.length === navs, `adopted reload into the user's init-only buffer: session [${st().qed64.snapshots}], no example shown`);
  const ar = SIM.apiRestarts.length;
  r = await api.select('hasse-view');
  const widen = SIM.apiRestarts[ar];
  ok(r.phase === 'ready' && r.shown === 'hasse-view' && widen && JSON.stringify(widen.opts) === JSON.stringify({ snapshots: ['init', 'mathlib'] }) && r.qed64.snapshots.join() === 'init,mathlib' && st().stall.events.some((e) => e.source === 'widen' && e.how === 'api.restart') && api.currentText() === byId['hasse-view'].text && r.notice === null,
    `the refused header widened: api.restart(${JSON.stringify(widen && widen.opts)}) → ready on [${r.qed64.snapshots}] (afterSession ${widen && widen.from}), notice cleared`);
  noInternals('widen');
  // (c) offers: __showcase.offer() mirrors api.status().offer; acceptOffer() runs it
  SIM.offer = { kind: 'exactImports', label: 'Load exact imports (about 1 min)' };
  await sleep(100);
  ok(api.offer() && api.offer().kind === 'exactImports' && st().qed64.offer && st().qed64.offer.label === SIM.offer.label, `offer(): ${JSON.stringify(api.offer())}`);
  ok(api.acceptOffer() === true && SIM.offerRuns === 1 && api.offer() === null && api.acceptOffer() === false, 'acceptOffer() ran the page\'s offer once; nothing offered afterwards → false');
  // (e) a slow first boot: 'boot' events (unit bytes) re-arm the progress-aware wait; the notice; a true stall; late ready
  const KNOBS = '?bootTimeout=0.6&bootStall=0.5&bootNotice=0.3';
  const LABEL = 'preparing the mathlib environment (0.4 GiB — one-time)';
  const TOTAL = 400e6;
  const prog = (loaded) => SIM.frame._win._page.bootStep(LABEL, { stage: 'snapshot', subject: 'mathlib', phase: 'snapshot', loaded, total: TOTAL, unit: 'bytes' });
  setupEnv({ v1: true, search: KNOBS, hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } }, holdBoot: true });
  api = await loadGallery();
  await until(() => st().phase === 'booting' && SIM.internals && st().boot.waiting, 3000, 'run19e booting');
  let sawCard = false; const t0 = Date.now();
  for (let i = 1; i <= 20; i++) { prog(i * 10e6); await sleep(100); if (!SIM.byIdEl('error-card').hidden || st().error) sawCard = true; }
  s = st();
  ok(!sawCard && s.phase === 'booting' && s.error === null && s.boot.stalls === 0 && Date.now() - t0 >= 2000 && s.boot.bytes === 200e6 && s.boot.sources.bytes === 20 && s.boot.source === 'api-events' && s.boot.uiTapped === false && s.boot.apiBootEvents >= 21 && s.boot.current && s.boot.current.loaded === 200e6,
    `slow progress through 'boot' events for ${Date.now() - t0} ms (budget 600 ms, stall 500 ms): no card; ${s.boot.bytes / 1e6} MB counted from ${s.boot.apiBootEvents} boot events`);
  ok(s.notice === `Still downloading: ${LABEL} — 200 MB of 400 MB so far. A first visit downloads several hundred MB, which takes minutes on a slow connection; later visits start from this browser's storage.` && s.boot.noticeShown === 1 && SIM.byIdEl('notice').style.top === '',
    `the notice "${(s.notice || '').slice(0, 60)}…" (CSS position: the page's #bar is not read in V1)`);
  let tLast = 0; let resent = 0;
  for (;;) { prog(5e6); resent++; await sleep(100); if (st().phase === 'error' || resent > 40) break; }
  s = st();
  ok(s.phase === 'error' && s.error && s.error.kind === 'timeout' && s.boot.stalls === 1 && s.boot.latePending === true && SIM.byIdEl('error-title').textContent === 'This is taking too long', `re-sent bytes of the same stage|subject|total are no progress (${resent} calls): the card "${SIM.byIdEl('error-title').textContent}"; late recovery armed`);
  void tLast;
  SIM.holdBoot = false; SIM.releaseBoot();
  await until(() => st().phase === 'ready', 5000, 'run19e late ready');
  s = st();
  ok(s.shown === 'chart-kit' && s.error === null && s.boot.recovered === 1 && s.cursor && s.cursor.lineNumber === byId['chart-kit'].firstCursor.lineNumber, `late ready → card closed, recovered ${s.boot.recovered}, cursor L${s.cursor && s.cursor.lineNumber}`);
  noInternals('slow boot');
  // (f) a boot that fails AFTER the relay is bound without a death (main() threw past pageApi.bind(): the editor mount): the
  //     page never retries it, so it is the hard card at once, not the soft "retries on its own" card and a 6 min wait
  setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } }, pageBootFailLate: 'the editor could not be mounted (simulated)' });
  const tf = Date.now();
  api = await loadGallery();
  await until(() => st().phase === 'error', 5000, 'run19f error');
  s = st();
  ok(s.error.kind === 'boot' && /could not start/.test(s.error.title) && /editor could not be mounted/.test(s.error.detail) && s.qed64 && s.qed64.session !== null && s.qed64.lastDeath === null && s.qed64.boot.failed === true && !SIM.byIdEl('error-card').hidden && Date.now() - tf < 2500 && s.boot.stalls === 0,
    `boot.failed after bind (session ${s.qed64 && s.qed64.session}, no death) → the hard card "${s.error.title}: ${s.error.detail.slice(0, 45)}…" after ${Date.now() - tf} ms (no soft card, no boot wait)`);
  noInternals('late boot failure');
  // (f2) the same after a retried bootFailed DEATH (lastDeath set, the relay rebooting): boot.failed is still main()'s, which
  //      nothing retries (a death never sets boot.failed at 84d594e), so it is the hard card at once, not the soft one
  setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } }, pageBootFailLate: 'the editor could not be mounted (simulated)', pageBootFailLateDeath: 'simulated: snapshot fetch failed' });
  const tf2 = Date.now();
  api = await loadGallery();
  await until(() => st().phase === 'error', 5000, 'run19f2 error');
  s = st();
  ok(s.error.kind === 'boot' && /could not start/.test(s.error.title) && /editor could not be mounted/.test(s.error.detail) && s.qed64 && s.qed64.session !== null && s.qed64.lastDeath && s.qed64.lastDeath.kind === 'bootFailed' && s.qed64.boot.failed === true && !SIM.byIdEl('error-card').hidden && Date.now() - tf2 < 2500 && s.boot.stalls === 0,
    `boot.failed after a retried death (lastDeath ${s.qed64 && s.qed64.lastDeath && s.qed64.lastDeath.kind}) → the hard card "${s.error.title}" after ${Date.now() - tf2} ms (no soft card, no boot wait)`);
  noInternals('late boot failure after a death');
  // (g) a v1 page WITHOUT capabilities.liveness: no stand-down claim — builtIn/api false, probe 'unavailable', nothing sent
  setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } }, caps2: { liveness: false } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run19g ready');
  await sleep(300);
  s = st();
  ok(s.api.capabilities.liveness === false && s.liveness.probe === 'unavailable' && s.liveness.qed64.builtIn === false && s.liveness.qed64.api === false && s.liveness.sent === 0 && s.liveness.deferring === false && s.qed64.liveness === null && s.liveness.qed64.stalled === null
    && SIM.fromClient.length === 0 && s.liveness.events.some((e) => e.source === 'qed64-detected' && e.liveness === false) && s.stall.tapped === true,
    `capabilities.liveness false → liveness.probe '${s.liveness.probe}', qed64 {builtIn ${s.liveness.qed64.builtIn}, api ${s.liveness.qed64.api}}, status().qed64.liveness ${s.qed64.liveness}; nothing sent; the stall card stays armed`);
  noInternals('no liveness capability');
  // (h) a halt AFTER QED64 served, during the first boot: QED64's 30 s check fallback marked status().boot done (not failed)
  //     before a first verdict, then the relay halted. The halted card shows, and the late adoption is armed as for a true
  //     stall: the visitor's edit re-arms the relay, QED64 reaches ready, the card hides and the gallery adopts the page
  setupEnv({ hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } } });
  SIM.stuck = true; // the first verdict never comes
  api = await loadGallery();
  await until(() => SIM.internals && SIM.internals.relay.state.kind === 'serving' && st().boot.waiting, 5000, 'run19h serving');
  SIM.frame._win._page.bootDone(); SIM.halt();
  await until(() => st().phase === 'error', 5000, 'run19h halted card');
  s = st();
  ok(s.error.kind === 'halted' && !SIM.byIdEl('error-card').hidden && s.boot.latePending === true && s.booted === false && s.qed64.boot.done === true && s.qed64.boot.failed === false && s.qed64.phase === 'halted' && s.selections.slice(-1)[0].outcome === 'error',
    `halt after serve (boot done ${s.qed64.boot.done}, failed ${s.qed64.boot.failed}) → the card "${s.error.title}", late adoption armed (latePending ${s.boot.latePending})`);
  const EDIT = `${byId['chart-kit'].text}-- typed after the halt\n`;
  SIM.stuck = false;
  SIM.internals._model.setValue(EDIT); // the visitor's edit: a didChange re-arms the halted relay
  await until(() => st().phase === 'ready' && st().booted, 5000, 'run19h adopted');
  s = st();
  ok(SIM.rearms === 1 && s.error === null && SIM.byIdEl('error-card').hidden && s.boot.recovered === 1 && s.boot.latePending === false && s.boot.events.some((e) => e.source === 'recovered' && e.kind === 'reload')
    && s.op.label === 'reload' && s.current === 'chart-kit' && s.shown === null && api.currentText() === EDIT && SIM.navigations.filter((n) => n.src !== 'about:blank').length === 1,
    `the edit re-armed the relay (rearms ${SIM.rearms}) → ready: the card hid, the page was adopted (recovered ${s.boot.recovered}, op ${s.op.label}, the visitor's text kept, no navigation)`);
  r = await api.select('hasse-view');
  ok(r.phase === 'ready' && r.shown === 'hasse-view' && api.currentText() === byId['hasse-view'].text, 'after the adoption the gallery switches normally (hasse-view ready)');
  noInternals('halt after serve');
  // (h2) the same halt BEFORE QED64's boot is done (before its 30 s check fallback): the late adoption is armed too, and once
  //     the fallback marks the boot done and the visitor's edit re-arms the relay, QED64 is ready and the gallery adopts it
  setupEnv({ hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } } });
  SIM.stuck = true;
  api = await loadGallery();
  await until(() => SIM.internals && SIM.internals.relay.state.kind === 'serving' && st().boot.waiting, 5000, 'run19h2 serving');
  SIM.halt();
  await until(() => st().phase === 'error', 5000, 'run19h2 halted card');
  s = st();
  ok(s.error.kind === 'halted' && s.qed64.boot.done === false && s.boot.latePending === true && s.booted === false,
    `a halt before QED64's boot is done → the halted card, late adoption armed (boot done ${s.qed64.boot.done}, latePending ${s.boot.latePending})`);
  await sleep(1500);
  ok(st().phase === 'error' && !SIM.byIdEl('error-card').hidden && st().booted === false && st().boot.recovered === 0,
    'while the page stays halted the card stays and nothing is adopted');
  SIM.frame._win._page.bootDone();
  SIM.stuck = false;
  SIM.internals._model.setValue(`${byId['chart-kit'].text}-- typed after the early halt\n`);
  await until(() => st().phase === 'ready' && st().booted, 5000, 'run19h2 adopted');
  s = st();
  ok(s.error === null && SIM.byIdEl('error-card').hidden && s.boot.recovered === 1 && s.boot.latePending === false && s.op.label === 'reload',
    `the early halt recovered too: the card hid and the page was adopted (recovered ${s.boot.recovered}, op ${s.op.label})`);
  noInternals('halt before boot done');
}

// ================================================================ run 20: V1 audit round 2 (document-bound api, in-memory re-seed, capabilities, served mode)
console.log('\n== run 20 (V1): the api is bound to its document; adopted reloads re-seed the newest text from memory; required capabilities; a page without widgetSourceCache boots and warns once');
{
  const CK = byId['chart-kit']; const TS = byId['tree-scope'];
  setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run20 ready');
  await sleep(300);
  ok(st().mode === 'v1' && st().api.pinRevision === st().api.revision && !('modeSource' in st()) && !('servedRevision' in st().api) && !SIM.fetchLog.some((f) => f.path === '/qed64-build.json'), `pin.json's apiRevision ${st().api.pinRevision} decides: no /qed64-build.json probe, no modeSource / servedRevision`);
  // (a) a reload whose new document has not run its module yet (a slow or failing bundle): the unloaded page's api must not
  //     answer — no stale 'ready', no setDocument on it — and a selection made in that window boots cleanly
  const oldIdx = SIM.pages.indexOf(SIM.frame._win); const sdA = SIM.setDocCalls.length; const navA = SIM.navigations.length;
  SIM.page.dispatchEvent({ type: 'pagehide' });
  SIM.moduleDelayMs = 1500; SIM.page = makePage(SIM.frame._win.location.href.replace(ORIGIN, '')); SIM.frame._win = SIM.page; SIM.moduleDelayMs = 15;
  await sleep(300); // two monitor ticks inside the window
  s = st();
  ok(s.api.present === false && s.qed64 === null && api.currentText() === null && api.offer() === null && api.acceptOffer() === false,
    `inside the window before the reloaded module runs: api.present ${s.api.present}, status().qed64 ${JSON.stringify(s.qed64)}, currentText ${api.currentText()} (the unloaded page's api answers nothing)`);
  const rA = await settled(api.select('tree-scope'));
  s = st();
  ok(rA.ok && s.phase === 'ready' && s.shown === 'tree-scope' && api.currentText() === TS.text && SIM.setDocCalls.slice(sdA).every((c) => c.page !== oldIdx) && s.api.adopted === 0 && SIM.navigations.length === navA + 2 && s.error === null,
    `a selection in that window: no setDocument on the old page (${SIM.setDocCalls.slice(sdA).filter((c) => c.page === oldIdx).length}), the loading document retired and tree-scope booted (navigations +${SIM.navigations.length - navA}, adopted ${s.api.adopted}, ${s.phase})`);
  noInternals('reload window');
  // (b) the newest forwarded text lives in memory: a failed write (quota, blocked storage) or another gallery tab's text under
  //     the shared key never replaces what an adopted reload re-seeds
  await sleep(1100); // past the persistence throttle
  const T = `${TS.text}-- an edit whose write fails\n`;
  SIM.storageThrow.add(DOC_KEY);
  SIM.internals._model.setValue(T);
  await until(() => st().document.length === T.length, 2000, 'run20b event');
  await sleep(1100);
  s = st();
  ok(s.document.persisted === false && /QuotaExceeded/.test(s.document.error || '') && SIM.storage.get(DOC_KEY) !== T, `the write failed (persisted ${s.document.persisted}, error ${JSON.stringify(s.document.error)}); the key still holds older text`);
  let nb = SIM.bootDocs.length; let ad = st().api.adopted;
  SIM.page.dispatchEvent({ type: 'pagehide' });
  SIM.page = makePage(SIM.frame._win.location.href.replace(ORIGIN, '')); SIM.frame._win = SIM.page;
  await until(() => SIM.bootDocs.length === nb + 1, 3000, 'run20b reload boot doc');
  await until(() => st().phase === 'ready' && st().booted && st().api.adopted === ad + 1, 5000, 'run20b adopt');
  s = st();
  ok(SIM.bootDocs[nb].text === T && SIM.bootDocs[nb].source === 'setDocument' && api.currentText() === T && s.api.adoptSet.from === 'saved' && s.api.adoptSet.via === 'memory',
    `adopted reload after a failed write re-seeded the edit from memory (adoptSet ${JSON.stringify(s.api.adoptSet && { from: s.api.adoptSet.from, via: s.api.adoptSet.via, length: s.api.adoptSet.length })})`);
  SIM.storageThrow.delete(DOC_KEY);
  await sleep(1100);
  const OTHER = 'theorem another_tab : True := trivial\n';
  SIM.storage.set(DOC_KEY, OTHER); // another gallery tab of the origin wrote the shared key
  nb = SIM.bootDocs.length; ad = st().api.adopted;
  SIM.page.dispatchEvent({ type: 'pagehide' });
  SIM.page = makePage(SIM.frame._win.location.href.replace(ORIGIN, '')); SIM.frame._win = SIM.page;
  await until(() => SIM.bootDocs.length === nb + 1, 3000, 'run20b2 reload boot doc');
  await until(() => st().phase === 'ready' && st().booted && st().api.adopted === ad + 1, 5000, 'run20b2 adopt');
  ok(SIM.bootDocs[nb].text === T && api.currentText() === T, `another tab's text under the shared key (${OTHER.length} chars) did not replace this tab's document on its adopted reload`);
  noInternals('in-memory re-seed');
  // (b3) a GALLERY reload (a new gallery load, F5) over a user's own text persisted under the document key: the boot displaces
  //      that key (it force-writes the example), so the text goes through the save plan like a displaced qed64.buffer
  {
    const MINE2 = 'theorem my_own_proof : 1 + 1 = 2 := rfl\n';
    setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } }, storage: { [DOC_KEY]: MINE2 } });
    api = await loadGallery();
    await until(() => st().phase === 'ready', 8000, 'run20b3 ready');
    s = st();
    ok(SIM.storage.get('qed64-showcase:saved') === MINE2 && s.seed.action === 'saved' && s.seed.saved === true && s.saved && s.saved.entries.length === 1 && SIM.storage.get(DOC_KEY) !== MINE2 && s.document.persisted === true && SIM.byIdEl('restore-btn').hidden === false,
      `the persisted user text displaced by a v1 boot was kept (seed ${JSON.stringify(s.seed)}, saved entries ${JSON.stringify(s.saved && s.saved.entries)}); the key was overwritten (the example; “Open my saved buffer” offers the kept text)`);
    const EXEDIT2 = `${byId['tree-scope'].text}-- edited in an earlier gallery load\n`;
    setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } }, storage: { [DOC_KEY]: EXEDIT2, 'qed64-showcase:saved': MINE2 } });
    api = await loadGallery();
    await until(() => st().phase === 'ready', 8000, 'run20b3 ready 2');
    s = st();
    ok(SIM.storage.get('qed64-showcase:edited-example') === EXEDIT2 && s.seed.action === 'example' && s.seed.saved === false && SIM.storage.get('qed64-showcase:saved') === MINE2 && !SIM.storage.has('qed64-showcase:saved-history'),
      `an edited example under the document key goes to qed64-showcase:edited-example (seed ${s.seed.action}); saved and history unchanged`);
    setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } }, storage: { [DOC_KEY]: byId['tree-scope'].text } });
    api = await loadGallery();
    await until(() => st().phase === 'ready', 8000, 'run20b3 ready 3');
    s = st();
    ok(s.seed.action === 'embed' && s.seed.saved === false && !SIM.storage.has('qed64-showcase:saved') && !SIM.storage.has('qed64-showcase:edited-example'), `a pristine example under the document key keeps nothing (seed ${s.seed.action})`);
    noInternals('gallery reload over a persisted document');
    // (b4) the displaced text CANNOT be kept (setItem on qed64-showcase:saved throws, e.g. QuotaExceededError on a large
    //      document): the document key is its only stored copy, so the boot must not overwrite it (memory only + a notice),
    //      not even through the page's later 'document' events or an adopted reload
    const MINE3 = 'theorem my_large_document : True := trivial\n';
    setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } }, storage: { [DOC_KEY]: MINE3 } });
    SIM.storageThrow.add('qed64-showcase:saved'); SIM.onlyCurrentRun = true;
    api = await loadGallery();
    await until(() => st().phase === 'ready', 8000, 'run20b4 ready');
    await sleep(1200); // past the persistence throttle: the page's 'document' events had their chance to write
    s = st();
    ok(/QuotaExceeded/.test(s.seed.error || '') && s.seed.saved === false && SIM.storage.get(DOC_KEY) === MINE3 && !SIM.storage.has('qed64-showcase:saved') && s.document.held && /QuotaExceeded/.test(s.document.held.error) && s.document.persisted === false && s.document.writes === 0
      && api.currentText() === byId['chart-kit'].text && /could not be saved/.test(s.notice || '') && SIM.byIdEl('notice').hidden === false,
      `the displaced text could not be kept (seed error ${JSON.stringify(s.seed.error)}): ${DOC_KEY} still holds it (${SIM.storage.get(DOC_KEY) === MINE3 ? 'unchanged' : 'OVERWRITTEN'}), writes ${s.document.writes}, held ${JSON.stringify(s.document.held)}, notice ${JSON.stringify(s.notice)}`);
    const nb4 = SIM.bootDocs.length; const ad4 = st().api.adopted;
    SIM.page.dispatchEvent({ type: 'pagehide' });
    SIM.page = makePage(SIM.frame._win.location.href.replace(ORIGIN, '')); SIM.frame._win = SIM.page;
    await until(() => SIM.bootDocs.length === nb4 + 1, 3000, 'run20b4 reload boot doc');
    await until(() => st().phase === 'ready' && st().booted && st().api.adopted === ad4 + 1, 5000, 'run20b4 adopt');
    await sleep(1200);
    s = st();
    ok(SIM.bootDocs[nb4].text === byId['chart-kit'].text && s.api.adoptSet.via === 'memory' && SIM.storage.get(DOC_KEY) === MINE3 && s.document.writes === 0,
      `held: an adopted reload re-seeds the example from memory (adoptSet ${JSON.stringify(s.api.adoptSet && { from: s.api.adoptSet.from, via: s.api.adoptSet.via })}) and ${DOC_KEY} still holds the user's text`);
    noInternals('held document');
    ok(!/reload the gallery to keep/.test(s.notice || '') && /kept only in memory/.test(s.notice || ''), `the hold notice says edits in this tab are memory-only and does not advise a reload (${JSON.stringify(s.notice)})`);
    // a "Try again" (a forced boot of the current example: the path every recovery boot takes)
    const forceBoot = async (label) => { const n = SIM.navigations.length; SIM.byIdEl('error-retry').click(); await until(() => SIM.navigations.length >= n + 2 && st().phase === 'ready' && st().booted, 8000, label); await sleep(50); };
    // (b5) while held, an EDITED EXAMPLE typed in this tab (memory only: persistDocument writes nothing) is offered to the save
    //      plan on the next boot, in its own write: it lands in qed64-showcase:edited-example although the stored text still fails
    const EX5 = `${byId['chart-kit'].text}-- edited while the document is held\n`;
    SIM.internals._model.setValue(EX5);
    await until(() => st().document.length === EX5.length, 2000, 'run20b5 event');
    await sleep(1200);
    const risk = { dp: false }; globalThis.dispatchEvent({ type: 'beforeunload', preventDefault() { risk.dp = true; } });
    ok(st().document.writes === 0 && SIM.storage.get(DOC_KEY) === MINE3 && risk.dp === true, `held: the edit is memory-only (writes ${st().document.writes}, key unchanged) and leaving the page asks first (beforeunload prevented ${risk.dp})`);
    await forceBoot('run20b5 boot');
    s = st();
    ok(s.document.held && SIM.storage.get(DOC_KEY) === MINE3 && SIM.storage.get('qed64-showcase:edited-example') === EX5 && s.document.unsaved === null && s.seed.keepFailed === 'key',
      `a boot while held kept this tab's edited example (edited-example ${SIM.storage.get('qed64-showcase:edited-example') === EX5 ? 'holds it' : 'MISSING'}) although the stored text still failed (held ${!!s.document.held}, key ${SIM.storage.get(DOC_KEY) === MINE3 ? 'unchanged' : 'OVERWRITTEN'}, seed ${JSON.stringify(s.seed)})`);
    // (b6) a user text typed while held whose own write fails too: kept in memory as unsaved, the notice offers to copy it
    const U6 = 'theorem typed_while_held : True := trivial\n';
    SIM.internals._model.setValue(U6);
    await until(() => st().document.length === U6.length, 2000, 'run20b6 event');
    await forceBoot('run20b6 boot');
    s = st();
    ok(s.document.held && s.document.unsaved && s.document.unsaved.length === U6.length && /QuotaExceeded/.test(s.document.unsaved.error) && /in no storage/.test(s.notice || '') && SIM.byIdEl('notice-action').hidden === false && SIM.storage.get(DOC_KEY) === MINE3,
      `a typed text that could not be kept is unsaved (${JSON.stringify(s.document.unsaved)}), the notice says it is in no storage and offers "${SIM.byIdEl('notice-action').textContent}"`);
    SIM.byIdEl('notice-action').click();
    await until(() => SIM.clipboard === U6, 2000, 'run20b6 copy');
    ok(SIM.clipboard === U6 && st().document.unsaved.copied === true, 'the notice action copied the unsaved text to the clipboard');
    // (b7) storage freed: the next retry (an edit, or the one timer a write inside the rate-limit window armed) keeps the stored
    //      text (no boot needed) and releases the hold, so the edit is written; a boot then retries the unsaved text too. Nothing is lost.
    SIM.storageThrow.delete('qed64-showcase:saved');
    await sleep(5100); // past HOLD_RETRY_MS since the hold
    const EX7 = `${byId['chart-kit'].text}-- edited after storage was freed\n`;
    SIM.internals._model.setValue(EX7);
    // (round 6: the retry the boot's own events armed may release the hold first, during the wait; the edit then lands within 1 s)
    await until(() => st().document.held === null && SIM.storage.get(DOC_KEY) === EX7, 3000, 'run20b7 release');
    await sleep(50);
    s = st();
    ok(SIM.storage.get('qed64-showcase:saved') === MINE3 && SIM.storage.get(DOC_KEY) === EX7 && s.document.persisted === true && s.document.unsaved && !/still in this browser's storage/.test(s.notice || '') && /in no storage/.test(s.notice || ''),
      `storage freed: the hold was released (saved = the stored text, key = the edit, persisted ${s.document.persisted}); the notice now speaks only of the unsaved text`);
    await forceBoot('run20b7 boot');
    s = st();
    let hist7 = []; try { hist7 = JSON.parse(SIM.storage.get('qed64-showcase:saved-history') || '[]'); } catch { /* none */ }
    ok(s.document.held === null && s.document.unsaved === null && hist7.includes(U6) && SIM.storage.get('qed64-showcase:edited-example') === EX7 && SIM.storage.get(DOC_KEY) === byId['chart-kit'].text && !/could not be saved/.test(s.notice || ''),
      `a boot then kept the unsaved text (history ${hist7.length} incl. it) and the edit (edited-example), key = the example, no storage notice (${JSON.stringify(s.notice)})`);
    noInternals('held document edits');
  }
  // (b8) blocked storage (the localStorage getter throws SecurityError, e.g. site data blocked): nothing is stored, so nothing is
  //      held and no "still in storage" notice; a user text that lived only in memory is reported as unsaved, accurately
  {
    setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } } });
    Object.defineProperty(globalThis, 'localStorage', { get() { throw new Error('SecurityError: access denied (simulated)'); }, configurable: true });
    api = await loadGallery();
    await until(() => st().phase === 'ready', 8000, 'run20b8 ready');
    await sleep(1200);
    s = st();
    ok(s.seed.blocked === true && s.seed.error === null && s.seed.keepFailed === null && s.document.held === null && s.document.unsaved === null && s.notice === null && SIM.byIdEl('notice').hidden === true && s.document.persisted === false,
      `blocked storage on a first visit: no hold, no notice (seed ${JSON.stringify(s.seed)}, notice ${JSON.stringify(s.notice)}, document.error ${JSON.stringify(s.document.error)})`);
    const forceBoot8 = async (label) => { const n = SIM.navigations.length; SIM.byIdEl('error-retry').click(); await until(() => SIM.navigations.length >= n + 2 && st().phase === 'ready' && st().booted, 8000, label); await sleep(50); };
    await forceBoot8('run20b8 boot');
    s = st();
    ok(s.document.held === null && s.notice === null, `blocked storage, a later boot (Try again): still no hold and no notice (${JSON.stringify(s.notice)})`);
    const U8 = 'theorem typed_without_storage : True := trivial\n';
    SIM.internals._model.setValue(U8);
    await until(() => st().document.length === U8.length, 2000, 'run20b8 event');
    await forceBoot8('run20b8 boot 2');
    s = st();
    ok(s.document.held === null && s.document.unsaved && s.document.unsaved.length === U8.length && /SecurityError/.test(s.document.unsaved.error) && /in no storage/.test(s.notice || '') && !/still in this browser's storage/.test(s.notice || ''),
      `blocked storage: a typed text a boot displaces is unsaved, never held (notice ${JSON.stringify(s.notice)})`);
    noInternals('blocked storage');
  }
  // (b9) round 6. NOT held: the shared key holds a text that differs from this tab's memory (another gallery tab wrote it) and
  //      neither can be kept: the stored text is its own candidate, so the boot HOLDS the key (its only stored copy) instead of
  //      overwriting it, and the memory text becomes unsaved. Then the notice: its × cannot dismiss an unsaved text, and hiding
  //      any other notice brings it back. Then the held retry: an edit inside the HOLD_RETRY_MS window arms one timer that
  //      retries with the newest text once storage is freed, with no further edit.
  {
    setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } } });
    SIM.onlyCurrentRun = true;
    api = await loadGallery();
    await until(() => st().phase === 'ready', 8000, 'run20b9 ready');
    await sleep(1100);
    const M9 = 'theorem typed_in_this_tab : True := trivial\n';
    SIM.internals._model.setValue(M9);
    await until(() => st().document.length === M9.length, 2000, 'run20b9 event');
    await sleep(1200);
    ok(SIM.storage.get(DOC_KEY) === M9, 'b9: this tab\'s text was persisted under the shared key');
    const K9 = 'theorem another_tab_wrote_this : True := trivial\n';
    SIM.storage.set(DOC_KEY, K9); // another gallery tab of the origin
    SIM.storageThrow.add('qed64-showcase:saved'); SIM.storageThrow.add('qed64-showcase:saved-history');
    const n9 = SIM.navigations.length; SIM.byIdEl('error-retry').click();
    await until(() => SIM.navigations.length >= n9 + 2 && st().phase === 'ready' && st().booted, 8000, 'run20b9 boot'); await sleep(50);
    s = st();
    ok(SIM.storage.get(DOC_KEY) === K9 && s.seed.keepFailed === 'key' && s.document.held && s.document.unsaved && s.document.unsaved.length === M9.length && /still in this browser's storage/.test(s.notice || '') && /in no storage/.test(s.notice || ''),
      `b9: key text ≠ memory and neither kept → the key is HELD (${SIM.storage.get(DOC_KEY) === K9 ? 'unchanged' : 'OVERWRITTEN'}), the memory text is unsaved (seed ${JSON.stringify(s.seed)})`);
    // the notice: × is hidden and inert while a text is unsaved
    SIM.byIdEl('notice-close').click();
    s = st();
    ok(SIM.byIdEl('notice-close').hidden === true && SIM.byIdEl('notice').hidden === false && /in no storage/.test(s.notice || '') && SIM.byIdEl('notice-action').hidden === false,
      `b9: the storage notice of an unsaved text keeps its "Copy it" (× hidden ${SIM.byIdEl('notice-close').hidden}, a click leaves it up)`);
    // another notice replaces it (a bad deep link: transient); dismissing that one, or a selection ending it, brings the storage notice back
    location.hash = '#no-such-example'; SIM.fireWin('hashchange');
    ok(/There is no example called/.test(st().notice || '') && SIM.byIdEl('notice-close').hidden === false, 'b9: a transient notice replaced the storage notice (its × is shown)');
    SIM.byIdEl('notice-close').click();
    s = st();
    ok(/in no storage/.test(s.notice || '') && SIM.byIdEl('notice').hidden === false && SIM.byIdEl('notice-action').hidden === false && SIM.byIdEl('notice-action').textContent === 'Copy it',
      `b9: dismissing the other notice re-shows the storage notice with "${SIM.byIdEl('notice-action').textContent}" (${JSON.stringify(s.notice)})`);
    location.hash = '#no-such-example-2'; SIM.fireWin('hashchange');
    const r9 = await settled(api.select('tree-scope'));
    s = st();
    ok(r9.ok && /in no storage/.test(s.notice || '') && SIM.byIdEl('notice-action').hidden === false, `b9: a selection that ends a transient notice re-shows the storage notice (${JSON.stringify(s.notice)})`);
    // the held retry: an edit INSIDE the rate-limit window (the boot held < 5 s ago), then storage freed and NO further edit:
    // the one armed timer retries when the window ends, with the newest text (before round 6 nothing retried: held for good)
    const E9 = `${byId['tree-scope'].text}-- edited inside the retry window\n`;
    SIM.internals._model.setValue(E9);
    await until(() => st().document.length === E9.length, 2000, 'run20b9 edit');
    ok(st().document.held && st().document.held.retriedAt === undefined && SIM.storage.get(DOC_KEY) === K9, `b9: the edit inside the first window (no retry yet: held ${JSON.stringify(st().document.held)}) is memory-only; the key still holds the stored text`);
    SIM.storageThrow.delete('qed64-showcase:saved'); SIM.storageThrow.delete('qed64-showcase:saved-history');
    await until(() => st().document.held === null, 7000, 'run20b9 timer release');
    await sleep(50);
    s = st();
    ok(SIM.storage.get('qed64-showcase:saved') === K9 && SIM.storage.get(DOC_KEY) === E9 && s.document.persisted === true && s.document.held === null,
      `b9: with no further edit the one armed retry kept the stored text (saved ${SIM.storage.get('qed64-showcase:saved') === K9 ? '= the key text' : 'MISSING'}) and wrote the newest edit (key ${SIM.storage.get(DOC_KEY) === E9 ? '= the edit' : 'stale'})`);
    noInternals('b9 key text differs from memory');
  }
  // (b10) NOT held, and the key holds this tab's OWN last successful write while memory has a newer text (here the newer write
  //       failed; a throttled write still pending is the same case): memory supersedes the key, so a boot keeps only the newest
  //       text (SAVED = it), not the stale version too (it would take the SAVED slot and push the newest text into history)
  {
    setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } } });
    SIM.onlyCurrentRun = true;
    api = await loadGallery();
    await until(() => st().phase === 'ready', 8000, 'run20b10 ready');
    await sleep(1100);
    const M10a = 'theorem my_first_version : True := trivial\n';
    SIM.internals._model.setValue(M10a);
    await until(() => st().document.length === M10a.length, 2000, 'run20b10 event a');
    await sleep(1200);
    ok(SIM.storage.get(DOC_KEY) === M10a && st().document.persisted === true, 'b10: this tab wrote its first version under the key');
    const M10b = 'theorem my_newer_version : 1 = 1 := rfl\n';
    SIM.storageThrow.add(DOC_KEY);
    SIM.internals._model.setValue(M10b);
    await until(() => st().document.length === M10b.length, 2000, 'run20b10 event b');
    await sleep(1200);
    ok(SIM.storage.get(DOC_KEY) === M10a && st().document.persisted === false && st().document.held === null, 'b10: the newer version\'s write failed (the key still holds this tab\'s own older write; not held)');
    SIM.storageThrow.delete(DOC_KEY);
    const n10 = SIM.navigations.length; SIM.byIdEl('error-retry').click();
    await until(() => SIM.navigations.length >= n10 + 2 && st().phase === 'ready' && st().booted, 8000, 'run20b10 boot'); await sleep(50);
    s = st();
    let hist10 = []; try { hist10 = JSON.parse(SIM.storage.get('qed64-showcase:saved-history') || '[]'); } catch { /* none */ }
    ok(SIM.storage.get('qed64-showcase:saved') === M10b && !hist10.includes(M10a) && !hist10.includes(M10b) && s.seed.action === 'saved' && s.seed.keepFailed === null && s.document.held === null && s.document.unsaved === null,
      `b10: the boot kept only the newest text (saved ${SIM.storage.get('qed64-showcase:saved') === M10b ? '= the newer version' : SIM.storage.get('qed64-showcase:saved') === M10a ? '= the STALE version' : 'other'}, history ${hist10.length}, seed ${JSON.stringify(s.seed)})`);
    noInternals('b10 own stale key');
  }
  // (c) a page API without a capability the gallery needs (§1.2): the hard card, not a silently degraded gallery
  setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } }, caps2: { events: false } });
  api = await loadGallery();
  await until(() => st().phase === 'error', 5000, 'run20c error');
  s = st();
  ok(s.error.kind === 'boot' && /lacks the embedding features/.test(s.error.title) && /events/.test(s.error.detail) && JSON.stringify(s.api.missing) === '["events"]',
    `capabilities.events false → "${s.error.title}" (${s.error.detail}); status().api.missing ${JSON.stringify(s.api.missing)}`);
  noInternals('no events capability');
  // (c2) a page without editorRpc (the InfoView's RPC across the iframe, HARDENING #56): every mk_rpc_widget panel would fail,
  //      and since P1 there is no bridge to repair it, so the hard "could not start" card, nothing silently degraded
  setupEnv({ hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } }, caps2: { editorRpc: false } });
  api = await loadGallery();
  await until(() => st().phase === 'error', 5000, 'run20c2 error');
  await sleep(300); // the page reaches ready meanwhile: nothing may adopt it
  s = st();
  ok(s.phase === 'error' && s.error.kind === 'boot' && s.error.soft === false && /lacks the embedding features/.test(s.error.title) && /editorRpc/.test(s.error.detail) && JSON.stringify(s.api.missing) === '["editorRpc"]'
    && !SIM.byIdEl('error-card').hidden && !SIM.byIdEl('error-card').classList.contains('is-soft') && s.booted === false && s.shown === null && s.selections.slice(-1)[0].outcome === 'error',
    `capabilities.editorRpc false → the hard card "${s.error.title}" (${s.error.detail}); status().api.missing ${JSON.stringify(s.api.missing)}; not booted`);
  noInternals('no editorRpc capability');
  // (d) editorRpc without widgetSourceCache: no repair exists for that page, so it boots, warns once, and claims nothing
  setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: ALL7 } }, caps2: { widgetSourceCache: false } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run20d ready');
  r = await api.select('hasse-view'); // a switch does not warn again
  s = st();
  const wsc = SIM.warns.filter((w) => /widgetSourceCache/.test(w));
  ok(r.phase === 'ready' && s.shown === 'hasse-view' && s.api.capabilities.widgetSourceCache === false && JSON.stringify(s.api.missing) === '[]' && wsc.length === 1 && !('bridge' in s) && s.error === null,
    `capabilities {editorRpc true, widgetSourceCache false} → boots and switches (${s.shown} ready), warned once (${wsc.length}: "${(wsc[0] || '').slice(0, 70)}…"), no status().bridge`);
  noInternals('no widgetSourceCache');
}

// ================================================================ run 21: served overlay directories (pin.json overlays)
console.log('\n== run 21: served overlay directories — per-runtime alias ?overlay=widgets8, explicit ?overlay=<dir>, bare-only site; a pin.json without its overlays map or apiRevision is the data card');
{
  const B16 = PIN.buildId.slice(7);
  const D = { widgets8: `widgets8.${B16}` };
  const bareHits = () => SIM.fetchLog.filter((f) => /^\/snapshots\/widgets8\//.test(f.path)).length;
  const navOf = () => SIM.navigations.find((n) => n.src !== 'about:blank');
  const badge = () => SIM.byIdEl('overlay-badge');
  // (b) a per-runtime pin, ?overlay=widgets8: the alias of the pin's directory (V1 page); the bare widgets8/ is never requested
  setupEnv({ v1: true, pinOverlays: D, search: '?overlay=widgets8', hash: '#dist-lens', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run21b ready');
  await sleep(300);
  s = st();
  const DL = byId['dist-lens'];
  ok(s.requestedOverlay === 'widgets8' && s.overlay === 'widgets8' && s.overlayDir === D.widgets8 && JSON.stringify(s.overlayDirs) === JSON.stringify(D)
    && navOf() && navOf().src === `/?embed=1&snapshots=snapshots/${D.widgets8}#code=${encodeURIComponent(DL.text)}` && SIM.navigations.filter((n) => n.src !== 'about:blank').length === 1,
    `?overlay=widgets8 on a per-runtime pin → frame /?embed=1&snapshots=snapshots/${D.widgets8}#code=… (overlay ${s.overlay}, dir ${s.overlayDir})`);
  ok(badge().textContent === 'snapshot widgets8' && badge().title.startsWith(`Snapshot overlay /snapshots/${D.widgets8}/ — region imports:`) && s.preflight.dir === D.widgets8 && s.preflight.attempts.length === 1 && s.preflight.attempts[0].dir === D.widgets8 && s.preflight.attempts[0].overlay === 'widgets8'
    && bareHits() === 0 && SIM.fetchLog.some((f) => f.path === `/snapshots/${D.widgets8}/index.json`) && s.shown === 'dist-lens' && s.preflight.availability['dist-lens'] === true && (s.statusLine.detail || '').includes(`overlay widgets8 @ ${D.widgets8}`),
    `badge "${badge().textContent}" (logical), title /snapshots/${D.widgets8}/; preflight at the directory only (bare requests ${bareHits()}); DistLens available`);
  noInternals('per-runtime overlay alias');
  // (c) ?overlay=<the directory itself> (V1 page): reads as widgets8
  const HV = byId['hasse-view'];
  setupEnv({ v1: true, pinOverlays: D, search: `?overlay=${D.widgets8}`, hash: '#hasse-view', overlays: { widgets8: { imports: ALL7 } } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run21c ready');
  s = st();
  ok(s.requestedOverlay === D.widgets8 && s.overlay === 'widgets8' && s.overlayDir === D.widgets8 && navOf() && navOf().src === `/?embed=1&snapshots=snapshots/${D.widgets8}#code=${encodeURIComponent(HV.text)}` && badge().textContent === 'snapshot widgets8' && bareHits() === 0,
    `?overlay=${D.widgets8} (explicit directory) → overlay ${s.overlay}, frame ${navOf() && navOf().src.slice(0, 70)}…`);
  noInternals('explicit overlay directory');
  // (d) a per-runtime pin whose site serves ONLY the bare widgets8/ (a stale deploy, a server without the directories):
  //     the preflight card, no navigation — never a silent fallback to the bare (another runtime's) overlay
  setupEnv({ v1: true, pinOverlays: D, servedDirs: { widgets8: 'widgets8' }, hash: '#hasse-view', overlays: { widgets8: { imports: ALL7 } } });
  api = await loadGallery();
  await until(() => st().phase === 'error', 5000, 'run21d error');
  s = st();
  ok(SIM.navigations.length === 0 && s.error.kind === 'preflight' && s.error.title === 'No usable widgets overlay' && s.error.detail.includes(`/snapshots/${D.widgets8}/index.json was not found`)
    && s.error.detail.includes(`Tried widgets8 (/snapshots/${D.widgets8}/). `) && !s.error.detail.includes(', then ') && s.preflight.attempts.length === 1 && s.preflight.attempts.every((a) => a.notFound) && bareHits() === 0
    && !SIM.byIdEl('error-card').hidden && SIM.byIdEl('error-stock').href === `/?snapshots=snapshots/${D.widgets8}`,
    `per-runtime pin, only bare directories served → card "${s.error.title}": ${s.error.detail.slice(0, 110)}…; stock link ${SIM.byIdEl('error-stock').href}; no navigation`);
  // (e) a malformed overlays map in pin.json: the data card, nothing fetched under /snapshots/
  setupEnv({ v1: true, pinOverlays: { widgets8: '../x' }, hash: '#hasse-view', overlays: { widgets8: { imports: ALL7 } } });
  api = await loadGallery();
  await until(() => st().phase === 'error', 5000, 'run21e error');
  s = st();
  ok(SIM.navigations.length === 0 && s.error.kind === 'data' && /pin\.json overlays\.widgets8/.test(s.error.detail) && !SIM.fetchLog.some((f) => f.path.startsWith('/snapshots/')),
    `pin.json overlays {widgets8: "../x"} → data card: ${s.error.detail.slice(0, 120)}`);
  // (e2) a pin.json without the overlays map (no registered pin's pin.json lacks it since P1): the data card, nothing fetched
  setupEnv({ pinOverlays: null, servedDirs: { widgets8: 'widgets8' }, hash: '#hasse-view', overlays: { widgets8: { imports: ALL7 } } });
  api = await loadGallery();
  await until(() => st().phase === 'error', 5000, 'run21e2 error');
  s = st();
  ok(SIM.navigations.length === 0 && s.error.kind === 'data' && /pin\.json has no overlays map/.test(s.error.detail) && !SIM.fetchLog.some((f) => f.path.startsWith('/snapshots/')),
    `pin.json without overlays → data card: ${s.error.detail.slice(0, 100)}`);
  // (e3) a pin.json without apiRevision (a QED64 page before the embedding contract v1): the data card, nothing navigates
  setupEnv({ v1: false, hash: '#hasse-view', overlays: { widgets8: { imports: ALL7 } } });
  api = await loadGallery();
  await until(() => st().phase === 'error', 5000, 'run21e3 error');
  s = st();
  ok(SIM.navigations.length === 0 && s.error.kind === 'data' && /pin\.json has no apiRevision/.test(s.error.detail) && !SIM.fetchLog.some((f) => f.path.startsWith('/snapshots/') || f.path === '/qed64-build.json') && !SIM.byIdEl('error-card').hidden,
    `pin.json apiRevision null → data card: ${s.error.detail.slice(0, 100)}`);
}

// ================================================================ runs 22–26 (V1): what only the legacy runs 1, 6, 7, 10 and 11 tested (deleted in P1 C5)
// The gallery ships these on V1 too; each check below is the V1 twin of the legacy one named in its run's heading.
console.log('\n== run 22 (V1, from run 1): veil and capabilities, chips, title and hash, hint button, roving keys, Copy, hashchange, status line');
{
  setupEnv({ v1: true, hash: '#hasse-view', overlays: { widgets8: { imports: ALL7 } } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run22 ready');
  s = st();
  { // the veil is out of the accessibility tree and the focus order once it is hidden (hardening lane)
    const v = SIM.byIdEl('stage-veil');
    ok(v.classList.contains('is-hidden') && v.getAttribute('aria-hidden') === 'true' && v.getAttribute('inert') === '' && v.inert === true && s.caps && s.caps.ok === true && s.caps.missing.length === 0,
      `ready: the veil is hidden with aria-hidden="true" and inert; capabilities ok (${s.caps && s.caps.checks.map((c) => `${c.id} ${c.ok ? 'ok' : 'x'}`).join(', ')})`);
  }
  const chips = Object.fromEntries(EX.map((e) => [e.id, SIM.byIdEl('card-list').querySelectorAll('.card').find((c) => c.dataset.id === e.id).querySelector('.chip').textContent]));
  ok(chips['hasse-view'] === 'live' && chips['dist-lens'] === 'not in widgets8' && chips['chart-kit'] === 'available', `chips: hasse-view=${chips['hasse-view']}, dist-lens=${chips['dist-lens']}, chart-kit=${chips['chart-kit']}`);
  ok(location.hash === '#hasse-view' && document.title.startsWith('HasseView'), 'hash and title follow the selection');
  // hint on another card: loads that example and puts the cursor on the hint line
  const ivHint = byId['interval-inspector'].tryThis.find((h) => h.kind === 'select');
  const ivCard = SIM.byIdEl('card-list').querySelectorAll('.card').find((c) => c.dataset.id === 'interval-inspector');
  ivCard.querySelector('.card-main').click();
  await until(() => st().phase === 'ready' && st().shown === 'interval-inspector', 5000, 'run22 iv');
  ok(location.hash === '#interval-inspector' && document.title.startsWith(byId['interval-inspector'].title), `a card click moves the hash and title too (${location.hash}, "${document.title.slice(0, 30)}")`);
  const hintBtn = ivCard.querySelectorAll('.hint').find((b) => b.textContent.includes(ivHint.label));
  ok(!!hintBtn, `current card renders its hints (found “${ivHint.label}”)`);
  const sc0 = SIM.setCursorCalls.length;
  hintBtn.click();
  await sleep(20);
  ok(st().cursor.lineNumber === ivHint.lineNumber && SIM.setCursorCalls.length > sc0, `hint button moves the cursor to L${ivHint.lineNumber} (api.setCursor)`);
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
  await until(() => st().phase === 'ready' && st().shown === 'chart-kit', 5000, 'run22 hash');
  ok(api.currentText() === byId['chart-kit'].text && document.title.startsWith('ChartKit'), 'hashchange #chart-kit switches the example (and the title)');
  await sleep(300); // the status line renders every 250 ms
  // visible text: plain words (the example, "is ready"), no internals; the tooltip and the test API keep the detail
  {
    const vis = SIM.byIdEl('status-text').textContent; const tip = SIM.byIdEl('status-line').title || ''; const api2 = st().statusLine || {};
    ok(/ChartKit/.test(vis) && / is ready\b/.test(vis) && !/header|session|qed64|covered/.test(vis) && /header covered/.test(tip) && /session s\d/.test(tip)
      && api2.text === vis && api2.detail === tip && SIM.byIdEl('status-line').dataset.phase === 'ready',
    `status line: plain "${vis}"; tooltip "${tip}"`);
  }
  noInternals('rail, hints, Copy, hashchange, status line');
}

console.log('\n== run 23 (V1, from run 6): two kept buffers: the chooser lists them newest first; Open opens the newest, restoreSaved(1) the first one ever saved');
{
  const ORIG = 'theorem original : True := trivial\n', EDITED = 'theorem edited : True := trivial\n';
  setupEnv({ v1: true, hash: '#chart-kit', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } }, storage: { 'qed64-showcase:saved': ORIG, 'qed64-showcase:saved-history': JSON.stringify([EDITED]) } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run23 ready');
  ok(SIM.byIdEl('restore-btn').hidden === false && SIM.byIdEl('restore-pick').hidden === false && SIM.byIdEl('restore-pick').children.length === 2 && /^newest: theorem edited/.test(SIM.byIdEl('restore-pick').children[0].textContent),
    `two kept buffers: the chooser lists them newest first (${SIM.byIdEl('restore-pick').children.map((o) => o.textContent).join(' | ')})`);
  SIM.byIdEl('restore-btn').click();
  await sleep(80);
  ok(api.currentText() === EDITED && st().custom === true && st().current === null, 'Open opens the NEWEST kept buffer (the history head), not the first one ever saved; no card is current');
  ok(await api.restoreSaved(1) === true && await until(() => api.currentText() === ORIG, 2000, 'run23 restoreSaved(1)'), 'restoreSaved(1) / the chooser reaches the first one ever saved');
  noInternals('saved-buffer chooser');
}

console.log('\n== run 24 (V1, from run 7): Keep waiting hides the stall card and re-arms the watchdog; a halted relay is never the stall card');
{
  setupEnv({ v1: true, search: '?stall=5', hash: '#graph-scope', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run24 ready');
  const card = () => SIM.byIdEl('error-card');
  const EDIT = `${byId['graph-scope'].text}-- typed\n`;
  SIM.stuck = true;
  SIM.internals._model.setValue(EDIT);
  await until(() => st().stall.active, 9000, 'run24 stall card');
  ok(!card().hidden && st().error.kind === 'stalled' && SIM.byIdEl('error-dismiss').textContent === 'Keep waiting', `the stall card is up with [${SIM.byIdEl('error-dismiss').textContent}]`);
  SIM.byIdEl('error-dismiss').click();
  const tKeep = Date.now();
  ok(card().hidden && st().stall.active === false && st().error === null, 'Keep waiting hides the card and re-arms the watchdog');
  await until(() => st().stall.active, 9000, 'run24 stall card again');
  ok(Date.now() - tKeep >= 4800 && st().stall.shown === 2, `the card comes back after another threshold (${Date.now() - tKeep} ms; shown ${st().stall.shown}×)`);
  // a fresh session (Restart Lean), then stuck again and the relay halts before the threshold: the halted card, never the stall card
  const sess = SIM.internals.relay.session.id;
  SIM.stuck = false;
  SIM.byIdEl('error-retry').click();
  await until(() => st().qed64.phase === 'ready' && st().qed64.session !== sess && !st().stall.active, 8000, 'run24 restart ready');
  SIM.stuck = true;
  SIM.internals._model.setValue(`${EDIT}-- third\n`);
  await sleep(200);
  SIM.halt();
  await sleep(6000);
  ok(st().stall.active === false && st().error && st().error.kind === 'halted' && st().stall.shown === 2, 'a halted relay shows the halted card, never the stall card');
  SIM.stuck = false;
  noInternals('Keep waiting, halted');
}

console.log('\n== run 25 (V1, from run 10): the stall card re-words itself from "still working" to "stopped" when QED64\'s answers stop');
{
  setupEnv({ v1: true, search: '?stall=5&probeTimeout=0.5', hash: '#graph-scope', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run25 ready');
  SIM.busy = true;
  const ticker = setInterval(() => { SIM.qlive = { ...SIM.qlive, probes: SIM.qlive.probes + 1, answered: SIM.qlive.answered + 1 }; }, 600);
  SIM.internals._model.setValue(`${byId['graph-scope'].text}-- 24 parallel sleeps\n`);
  await until(() => st().stall.active, 9000, 'run25 card');
  ok(st().stall.variant === 'alive' && /Lean is still working/.test(SIM.byIdEl('error-title').textContent), `QED64 answering: the card says "${SIM.byIdEl('error-title').textContent}" (variant alive)`);
  clearInterval(ticker);
  await until(() => st().stall.events.some((e) => e.source === 'reworded' && e.variant === 'stopped'), 6000, 'run25 reworded');
  ok(st().stall.variant === 'stopped' && /stopped making progress/.test(SIM.byIdEl('error-title').textContent) && st().error.kind === 'stalled' && SIM.apiRestarts.length === 0,
    `no sign of life for ${4 * 0.5} s: the card was re-worded to "${SIM.byIdEl('error-title').textContent}" (event reworded); the gallery restarted nothing`);
  SIM.busy = false;
  noInternals('reworded card');
}

console.log('\n== run 26 (V1, from run 11): diagnostics the page makes itself (origin qed64) are neither progress nor proof of life');
{
  setupEnv({ v1: true, search: '?stall=5&probeTimeout=0.5', hash: '#graph-scope', overlays: { widgets8: { imports: [...ALL7, 'DistLens'] } } });
  api = await loadGallery();
  await until(() => st().phase === 'ready', 8000, 'run26 ready');
  SIM.stuck = true;
  const t0 = Date.now();
  SIM.internals._model.setValue(`${byId['graph-scope'].text}-- frozen, the page chatty\n`);
  await sleep(100); // the frozen version's own fileProgress is a real frame
  const f0 = st().liveness.frames; const pm0 = st().stall.progressMsgs; const sy0 = st().liveness.syntheticFrames; const d0 = st().api.events.diagnostics || 0;
  // what the page's JS layer keeps sending while the Lean side is frozen: its own notes as diagnostics (source QED64)
  const synth = setInterval(() => {
    const r = SIM.internals.relay;
    r.toClient({ jsonrpc: '2.0', method: 'textDocument/publishDiagnostics', params: { uri: r.doc.uri, version: r.doc.version, diagnostics: [{ range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } }, severity: 1, source: 'QED64', message: 'halted' }] } });
  }, 150);
  await until(() => st().stall.active, 9000, 'run26 card');
  clearInterval(synth);
  s = st();
  ok(Date.now() - t0 >= 4800 && s.stall.variant === 'stopped' && s.liveness.syntheticFrames - sy0 >= 10 && s.api.events.diagnostics - d0 === s.liveness.syntheticFrames - sy0 && s.liveness.frames === f0 && s.stall.progressMsgs === pm0,
    `${s.liveness.syntheticFrames - sy0} QED64-made diagnostics (origin qed64) counted as synthetic, not as frames (${s.liveness.frames - f0} new) or progress (${s.stall.progressMsgs - pm0}): the card after ${Date.now() - t0} ms says "stopped"`);
  // a diagnostics frame from Lean still counts
  { const r = SIM.internals.relay; r.toClient({ jsonrpc: '2.0', method: 'textDocument/publishDiagnostics', params: { uri: r.doc.uri, version: r.doc.version, diagnostics: [] } }); }
  ok(st().liveness.frames === f0 + 1 && st().stall.progressMsgs === pm0 + 1, 'a Lean publishDiagnostics (origin lean) still counts as a frame and as progress');
  SIM.stuck = false;
  noInternals('synthetic diagnostics');
}

console.log(`\nSIM-GALLERY ${fails ? 'FAIL' : 'OK'} ${oks} ok, ${fails} failed`);
process.exit(fails ? 1 : 0);
