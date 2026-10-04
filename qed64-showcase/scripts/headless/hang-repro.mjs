#!/usr/bin/env node
// hang-repro.mjs — headless replay of the UX C20 hasse-view pattern against the pinned QED64 runtime
// (the active pin's runtime, scripts/lib/pins.mjs; the investigation in out/hang/ROOT-CAUSE.md ran it on
// kernel 0034), to look for QED64 limitation L7 ("the checker stops for good in
// `elaborating`") without a browser. Investigation tool for out/hang/ROOT-CAUSE.md.
//
// One cycle = what C20 does per link, from the client side the FileWorker sees:
//   1. Reset: full-text didChange back to lean/examples/hasse-view.lean (+ the editor's own
//      document requests: semanticTokens/full, documentSymbol, foldingRange, inlayHint);
//   2. Cursor on the link's #hasse line: the InfoView's requests (getWidgets, getInteractiveGoals,
//      getInteractiveTermGoal, getInteractiveDiagnostics, getWidgetSource, the panel's own
//      HasseView.HassePanel.rpc) + the editor's codeAction / documentHighlight;
//   3. Click: full-text didChange with the link's edit (lean/expect/click-all/w8/hasse-view.json), the
//      InfoView's re-requests for the new version, and (--cancel) a $/cancelRequest for every
//      request still in flight, as the editor does for its own requests on an edit;
//   4. Wait until $/lean/fileProgress drains at the new version.
// Variants: --cancel (cancel everything in flight right after the click's didChange; the bridge
// strips abortSignal, so in the browser panel RPCs are NOT cancelled — this is the opposite extreme),
// --storm K (K concurrent duplicate getWidgetSource for the MakeEditLink hash per version: the L2
// storm without the bridge's D3 coalescing), --panel-storm K (K concurrent HassePanel.rpc per version:
// uncancelled panel RPCs piling up).
//
// Instrumentation: Emscripten's PThread pool (unusedWorkers / pthreads, the same numbers as
// qed64.status().pool), a count of every pthread spawn (spawnThread) and exit (cleanupThread) — the
// glue is a classic script, so its top-level `var`s are globals and can be wrapped — and the server
// frames. A cycle that makes no progress for --hang-ms with no server frame for half of that is a
// HANG: the tool dumps the state, then runs two recovery probes, each followed by a 10 s watch for
// server frames: (1) a ring kick (a keepAlive notification: new bytes + Atomics.notify on the stdin
// ring's wake word — tests a lost stdin-ring wakeup), (2) checkMailbox() on the Emscripten main
// thread (this Node thread) — tests a lost main-thread mailbox notification, i.e. a pthread blocked
// forever in a synchronous proxy (pthread_create / fd_write) to the main thread.
//
// Host rules (binding for this lane): refuses to start while the host browser lock (scripts/lib/browser-lock.mjs) exists or when
// vm_stat free+inactive < --min-free-gb (default 20); one wasm verifier at a time ($W/headless/.lock);
// default budget 12 min; aborts if the browser lock appears or free+inactive falls under 3 GB.
//
// usage: node scripts/headless/hang-repro.mjs [--label L] [--minutes 12] [--iterations N] [--cancel]
//          [--storm K] [--panel-storm K] [--hang-ms 30000] [--links 1-47|30] [--jitter-ms 0]
//          [--snap $W/raw/init.snap --snap $W/raw/widgets8.snap] [--lib $W/tree-slim-w8]
//          [--index $W/bake-out-w8/index.json] [--min-free-gb 20]
// exit 0 = no hang in the budget, 1 = HANG reproduced (see the JSON), 2 = setup error, 3 = host rules.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { SC, W, BID, DEFAULT_ARTIFACT, parseArgs, requirePairedArtifact, acquireLock, checkSnapProvenance } from './lib.mjs';
import { WasmLsp } from './wasm-lsp.mjs';
import { browserLockFile } from '../lib/browser-lock.mjs';

let o;
try { o = parseArgs(process.argv.slice(2), { multi: ['snap', 'index'], flags: ['cancel'] }); } catch (e) { console.error(e.message); process.exit(2); }
const variant = { cancel: !!o.cancel, storm: Number(o.storm ?? 0), panelStorm: Number(o['panel-storm'] ?? 0), jitterMs: Number(o['jitter-ms'] ?? 0) };
const LABEL = o.label ?? `${variant.cancel ? 'cancel' : 'nocancel'}${variant.storm ? `-storm${variant.storm}` : ''}${variant.panelStorm ? `-pstorm${variant.panelStorm}` : ''}`;
const MINUTES = Number(o.minutes ?? 12);
const MAX_IT = Number(o.iterations ?? 1e9);
const HANG_MS = Number(o['hang-ms'] ?? 30000);
const MIN_FREE_GB = Number(o['min-free-gb'] ?? 20);
const snaps = (o.snap ?? [`${W}/raw/init.snap`, `${W}/raw/widgets8.snap`]).map((p) => path.resolve(p));
const lib = path.resolve(o.lib ?? `${W}/tree-slim-w8`);
const indexes = (o.index ?? [`${W}/bake-out-w8/index.json`]).map((p) => path.resolve(p));
const OUTDIR = path.join(SC, 'out/hang');
const OUT = path.join(OUTDIR, `hang-repro.${LABEL}.json`);
const BROWSER_LOCK = browserLockFile();
fs.mkdirSync(OUTDIR, { recursive: true });
const t0 = Date.now();
const log = (...a) => console.log(`[hang-repro ${LABEL} +${((Date.now() - t0) / 1000).toFixed(1)}s]`, ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------- host rules ----------
function freeInactiveGB() { // free + inactive only (the lane rule), not speculative
  const t = execFileSync('/usr/bin/vm_stat').toString();
  const page = Number(/page size of (\d+) bytes/.exec(t)[1]);
  const get = (k) => Number(new RegExp(`${k}:\\s+(\\d+)`).exec(t)?.[1] ?? 0);
  return ((get('Pages free') + get('Pages inactive')) * page) / 1e9;
}
if (fs.existsSync(BROWSER_LOCK)) { console.error(`refusing: browser lock present (${fs.readFileSync(BROWSER_LOCK, 'utf8').trim()})`); process.exit(3); }
const free0 = freeInactiveGB();
if (free0 < MIN_FREE_GB) { console.error(`refusing: free+inactive ${free0.toFixed(1)} GB < ${MIN_FREE_GB} GB`); process.exit(3); }
log(`host: free+inactive ${free0.toFixed(1)} GB, browser lock absent; variant ${JSON.stringify(variant)}; budget ${MINUTES} min`);

// ---------- inputs ----------
const text = fs.readFileSync(path.join(SC, 'lean/examples/hasse-view.lean'), 'utf8');
const clickAll = JSON.parse(fs.readFileSync(path.join(SC, 'lean/expect/click-all/w8/hasse-view.json'), 'utf8'));
let links = clickAll.links;
if (o.links) {
  const m = /^(\d+)(?:-(\d+))?$/.exec(o.links); const a = Number(m[1]), b = Number(m[2] ?? m[1]);
  links = links.filter((l) => l.n >= a && l.n <= b);
}
const lineStarts = (t) => { const s = [0]; for (let i = 0; i < t.length; i++) if (t[i] === '\n') s.push(i + 1); return s; };
const offsetOf = (t, p) => lineStarts(t)[p.line] + p.character;
const applyEdit = (t, r, nt) => t.slice(0, offsetOf(t, r.start)) + nt + t.slice(offsetOf(t, r.end));

// ---------- boot ----------
const result = { tool: 'scripts/headless/hang-repro.mjs', label: LABEL, variant, buildId: BID, startedAt: new Date(t0).toISOString(),
  host: { freeInactiveGBAtStart: +free0.toFixed(1) }, hangMs: HANG_MS, cycles: [], hang: null, summary: null };
const write = () => { result.wallMs = Date.now() - t0; fs.writeFileSync(OUT, JSON.stringify(result, null, 1) + '\n'); };
let lsp;
try {
  await requirePairedArtifact(DEFAULT_ARTIFACT);
  const checks = [];
  result.provenance = await checkSnapProvenance(snaps, { indexes, check: (ok, what, d) => checks.push({ ok, what, d }), log });
  if (result.provenance.some((r) => !r.ok)) throw new Error(`snapshot provenance failed: ${JSON.stringify(checks)}`);
  acquireLock(`hang-repro ${LABEL}`);
  lsp = await WasmLsp.boot({ artifact: DEFAULT_ARTIFACT, lib, snaps, log, wasmLog: path.join(OUTDIR, `hang-repro.${LABEL}.wasm.log`) });
} catch (e) { console.error(`setup failed: ${e.stack || e.message}`); result.setupError = String(e.message); write(); process.exit(2); }
result.bootMs = lsp.timings.bootMs;

// ---------- instrumentation ----------
const PT = globalThis.PThread;
const pool = () => ({ unused: PT ? PT.unusedWorkers.length : -1, running: PT ? Object.keys(PT.pthreads).length : -1 });
const th = { spawns: 0, cleanups: 0, spawnsFromEmptyPool: 0, maxRunning: 0, wrapped: { spawnThread: false, cleanupThread: false } };
if (typeof globalThis.spawnThread === 'function') {
  const orig = globalThis.spawnThread;
  globalThis.spawnThread = function (p) { th.spawns++; if (PT.unusedWorkers.length === 0) th.spawnsFromEmptyPool++; const r = orig.apply(this, arguments); th.maxRunning = Math.max(th.maxRunning, Object.keys(PT.pthreads).length); return r; };
  th.wrapped.spawnThread = true;
}
if (typeof globalThis.cleanupThread === 'function') {
  const orig = globalThis.cleanupThread;
  globalThis.cleanupThread = function () { th.cleanups++; return orig.apply(this, arguments); };
  th.wrapped.cleanupThread = true;
}
let frames = 0, lastFrameAt = Date.now();
const lastFrames = []; const frameCounts = {};
const od = lsp.dispatch.bind(lsp);
lsp.dispatch = (msg) => {
  frames++; lastFrameAt = Date.now();
  const k = msg.method ?? (msg.error ? `error ${msg.error.code}` : 'response');
  frameCounts[k] = (frameCounts[k] ?? 0) + 1;
  lastFrames.push({ t: Date.now() - t0, k, id: msg.id ?? null, v: msg.params?.textDocument?.version ?? msg.params?.version ?? null,
    processing: msg.method === '$/lean/fileProgress' ? msg.params.processing.map((p) => [p.range.start.line, p.range.end.line, p.kind]) : undefined });
  if (lastFrames.length > 60) lastFrames.shift();
  od(msg);
};
const inflight = new Map(); // id -> {method, rpc, t}
let reqSeq = 0; const reqCounts = {};
const latency = {}; // method -> {n, errors, cancelled, maxMs, sumMs}
function done(key, t, err) {
  const l = latency[key] ??= { n: 0, errors: 0, cancelled: 0, maxMs: 0, sumMs: 0 };
  const ms = Date.now() - t; l.n++; l.sumMs += ms; l.maxMs = Math.max(l.maxMs, ms);
  if (err) { l.errors++; if (err.lsp?.code === -32800) l.cancelled++; }
}
function req(method, params, timeoutMs = 600000) {
  const id = lsp.id + 1; // WasmLsp.request uses ++this.id
  const key = method === '$/lean/rpc/call' ? params.method : method;
  reqCounts[key] = (reqCounts[key] ?? 0) + 1; reqSeq++;
  const t = Date.now();
  inflight.set(id, { method: key, t });
  const p = lsp.request(method, params, timeoutMs);
  p.then(() => { inflight.delete(id); done(key, t, null); }, (e) => { inflight.delete(id); done(key, t, e); });
  return { id, p: p.catch((e) => ({ __error: e.lsp?.code ?? e.message })) };
}
result.instrumentation = { pthreadWrapped: th.wrapped, poolAfterBoot: pool() };
log(`booted in ${lsp.timings.bootMs} ms; pool ${JSON.stringify(pool())}; wrapped ${JSON.stringify(th.wrapped)}`);

// ---------- client ----------
const uri = 'file:///workspace/Showcase.lean';
let version = 1;
await lsp.open({ processId: null, rootUri: null, capabilities: { textDocument: { publishDiagnostics: { relatedInformation: true } }, window: { workDoneProgress: false } },
  initializationOptions: { editDelay: 0, hasWidgets: true } }, { uri, languageId: 'lean4', version, text });
async function settle(ver, label) {
  const ts = Date.now();
  for (;;) {
    const p = lsp.progress.get(uri);
    if (p && p.textDocument.version >= ver && p.processing.every((q) => q.kind === 2)) return { ms: Date.now() - ts };
    if (lsp.dead) throw Object.assign(new Error(`server died: ${lsp.dead}`), { dead: true });
    const now = Date.now();
    if (now - ts > HANG_MS && now - lastFrameAt > HANG_MS / 2) return { hang: true, ms: now - ts, label, quietMs: now - lastFrameAt };
    if (now - ts > 10 * 60000) return { hang: true, ms: now - ts, label, quietMs: now - lastFrameAt, slow: true };
    await sleep(50);
  }
}
const first = await settle(version, 'open');
if (first.hang) { log('the example never settled after open'); }
const { sessionId } = await lsp.request('$/lean/rpc/connect', { uri });
const keepAlive = setInterval(() => lsp.notify('$/lean/rpc/keepAlive', { uri, sessionId }), 10000);
const rpc = (method, params, pos) => req('$/lean/rpc/call', { textDocument: { uri }, position: pos, sessionId, method, params });
const editorDocRequests = () => {
  req('textDocument/semanticTokens/full', { textDocument: { uri } });
  req('textDocument/documentSymbol', { textDocument: { uri } });
  req('textDocument/foldingRange', { textDocument: { uri } });
  req('textDocument/inlayHint', { textDocument: { uri }, range: { start: { line: 0, character: 0 }, end: { line: 40, character: 0 } } });
};
const editorCursorRequests = (pos) => {
  req('textDocument/codeAction', { textDocument: { uri }, range: { start: pos, end: pos }, context: { diagnostics: [], triggerKind: 2 } });
  req('textDocument/documentHighlight', { textDocument: { uri }, position: pos });
};
const jsCache = new Map(); let makeEditLinkHash = null;
/** The InfoView's requests for a cursor at `pos`; resolves when the panel Html is in (the test waits for the link). */
async function infoview(pos) {
  const gw = await rpc('Lean.Widget.getWidgets', pos, pos).p;
  const goals = rpc('Lean.Widget.getInteractiveGoals', { textDocument: { uri }, position: pos }, pos);
  const term = rpc('Lean.Widget.getInteractiveTermGoal', { textDocument: { uri }, position: pos }, pos);
  rpc('Lean.Widget.getInteractiveDiagnostics', { lineRange: { start: 0, end: 40 } }, pos);
  if (!gw || gw.__error || !gw.widgets) return { error: gw?.__error ?? 'no widgets' };
  const wi = gw.widgets.find((w) => /Hasse/.test(String(w.id))) ?? gw.widgets[0];
  if (!wi) return { error: 'no panel' };
  const hk = JSON.stringify(wi.javascriptHash);
  if (!jsCache.has(hk)) { const s = await rpc('Lean.Widget.getWidgetSource', { hash: wi.javascriptHash, pos }, pos).p; jsCache.set(hk, s?.sourcetext ?? ''); }
  const m = /const m="([^"]+)",g='(true|false)'/.exec(jsCache.get(hk));
  if (!m) return { error: 'panel method not found' };
  const g = await goals.p; const tg = await term.p;
  const props = { pos, goals: g && !g.__error ? g.goals : [], ...(tg && !tg.__error && tg ? { termGoal: tg } : {}), selectedLocations: [], ...wi.props };
  for (let k = 0; k < variant.panelStorm; k++) rpc(m[1], props, pos);
  const html = await rpc(m[1], props, pos).p;
  if (!html || html.__error) return { error: `panel rpc: ${html?.__error}` };
  if (!makeEditLinkHash) {
    const walk = (h) => { if (makeEditLinkHash || !h || typeof h !== 'object') return; if (h.component) { const [hash, , pr, ch] = h.component; if (pr?.edit) { makeEditLinkHash = hash; return; } ch?.forEach(walk); } if (h.element) h.element[2].forEach(walk); };
    walk(html);
  }
  if (makeEditLinkHash) {
    if (!jsCache.has('mel')) { const s = await rpc('Lean.Widget.getWidgetSource', { hash: makeEditLinkHash, pos }, pos).p; jsCache.set('mel', s?.sourcetext ?? ''); }
    for (let k = 0; k < variant.storm; k++) rpc('Lean.Widget.getWidgetSource', { hash: makeEditLinkHash, pos }, pos);
  }
  return { ok: true };
}

// ---------- hang handling ----------
async function onHang(info, ctx) {
  const snap = () => ({ at: Date.now() - t0, frames, quietMs: Date.now() - lastFrameAt, pool: pool(), threads: { ...th, wrapped: undefined },
    inflight: [...inflight.entries()].map(([id, r]) => ({ id, method: r.method, ageMs: Date.now() - r.t })) });
  const h = { ...ctx, settle: info, atHang: snap(), lastFrames: lastFrames.slice(-40), progress: lsp.progress.get(uri) ?? null,
    latencySoFar: JSON.parse(JSON.stringify(latency)), wasmStderrTail: lsp.stderr.slice(-20) };
  log(`HANG at cycle ${ctx.cycle} (link #${ctx.n}, v${ctx.version}, ${ctx.phase}): ${JSON.stringify(h.atHang).slice(0, 400)}`);
  await sleep(10000); h.after10s = snap();
  // probe 1: ring kick
  const f1 = frames; lsp.notify('$/lean/rpc/keepAlive', { uri, sessionId }); await sleep(10000);
  h.probeRingKick = { framesAfter: frames - f1, ...snap() };
  // probe 2: service the main thread's mailbox by hand
  const f2 = frames; let err = null;
  try { if (typeof globalThis.checkMailbox === 'function') globalThis.checkMailbox(); else err = 'checkMailbox not global'; } catch (e) { err = String(e && e.message || e); }
  await sleep(10000);
  h.probeCheckMailbox = { error: err, framesAfter: frames - f2, ...snap(), progress: lsp.progress.get(uri) ?? null };
  log(`probes: ring kick -> ${h.probeRingKick.framesAfter} frames; checkMailbox -> ${h.probeCheckMailbox.framesAfter} frames (${err ?? 'ok'})`);
  return h;
}

// ---------- loop ----------
const deadline = t0 + MINUTES * 60000;
let it = 0; let hung = false; let abort = null;
outer: while (it < MAX_IT && Date.now() < deadline) {
  for (const link of links) {
    if (it >= MAX_IT || Date.now() >= deadline) break outer;
    if (fs.existsSync(BROWSER_LOCK)) { abort = 'browser lock appeared'; break outer; }
    if (it % 10 === 0) { const g = freeInactiveGB(); if (g < 3) { abort = `free+inactive fell to ${g.toFixed(1)} GB`; break outer; } }
    it++;
    const c = { i: it, n: link.n, sp0: th.spawns, cl0: th.cleanups, fr0: frames, rq0: reqSeq };
    const pos = { line: link.foundAt[0].line, character: link.foundAt[0].character ?? 0 };
    // 1. reset
    version++; lsp.notify('textDocument/didChange', { textDocument: { uri, version }, contentChanges: [{ text }] }); editorDocRequests();
    let s = await settle(version, 'reset');
    if (s.hang) { result.hang = await onHang(s, { cycle: it, n: link.n, version, phase: 'reset' }); hung = true; break outer; }
    c.resetMs = s.ms;
    // 2. cursor
    editorCursorRequests(pos);
    const iv = await infoview(pos);
    if (iv.error) c.ivError = iv.error;
    if (variant.jitterMs) await sleep(Math.floor(Math.random() * variant.jitterMs));
    // 3. click
    version++; lsp.notify('textDocument/didChange', { textDocument: { uri, version }, contentChanges: [{ text: applyEdit(text, link.edit.range, link.edit.newText) }] });
    c.inflightAtClick = [...inflight.values()].map((r) => r.method).join(',');
    if (variant.cancel) for (const id of [...inflight.keys()]) lsp.notify('$/cancelRequest', { id });
    editorDocRequests(); editorCursorRequests(pos); const ivp = infoview(pos);
    s = await settle(version, 'click');
    if (s.hang) { result.hang = await onHang(s, { cycle: it, n: link.n, version, phase: 'click', inflightAtClick: c.inflightAtClick }); hung = true; break outer; }
    await Promise.race([ivp, sleep(5000)]);
    c.clickMs = s.ms; c.v = version; c.spawns = th.spawns - c.sp0; c.cleanups = th.cleanups - c.cl0; c.frames = frames - c.fr0; c.requests = reqSeq - c.rq0;
    Object.assign(c, pool()); delete c.sp0; delete c.cl0; delete c.fr0; delete c.rq0;
    result.cycles.push(c);
    if (it % 20 === 0) { log(`cycle ${it} v${version}: reset ${c.resetMs} ms, click ${c.clickMs} ms, spawns/cycle ${c.spawns}, pool ${c.unused}/${c.running}, total spawns ${th.spawns}`); write(); }
  }
}
clearInterval(keepAlive);
const cyc = result.cycles;
const med = (a) => { const b = a.slice().sort((x, y) => x - y); return b.length ? b[Math.floor(b.length / 2)] : null; };
result.summary = { cycles: it, completedCycles: cyc.length, versions: version, hang: hung, abort, totalSpawns: th.spawns, totalCleanups: th.cleanups,
  spawnsFromEmptyPool: th.spawnsFromEmptyPool, maxRunning: th.maxRunning, poolEnd: pool(), spawnsPerCycleMedian: med(cyc.map((c) => c.spawns)),
  requestsPerCycleMedian: med(cyc.map((c) => c.requests)), framesPerCycleMedian: med(cyc.map((c) => c.frames)),
  resetMsMedian: med(cyc.map((c) => c.resetMs)), clickMsMedian: med(cyc.map((c) => c.clickMs)), requestCounts: reqCounts, frameCounts,
  latency: Object.fromEntries(Object.entries(latency).map(([k, l]) => [k, { n: l.n, errors: l.errors, cancelled: l.cancelled, maxMs: l.maxMs, meanMs: Math.round(l.sumMs / Math.max(1, l.n)) }])),
  inflightAtEnd: Object.entries([...inflight.values()].reduce((a, r) => { a[r.method] = (a[r.method] ?? 0) + 1; return a; }, {})),
  maxRssGB: +(process.resourceUsage().maxRSS / 1048576).toFixed(2) };
write();
log(`DONE ${JSON.stringify(result.summary).slice(0, 900)} -> ${OUT}`);
console.log(hung ? `HANG-REPRO HANG ${LABEL} after ${it} cycles` : `HANG-REPRO NO-HANG ${LABEL} ${it} cycles${abort ? ` (aborted: ${abort})` : ''}`);
try { lsp.close(); } catch {}
setTimeout(() => process.exit(hung ? 1 : 0), 300);
