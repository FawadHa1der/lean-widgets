#!/usr/bin/env node
// check-gallery.mjs — static gate for the M2 gallery (no browser).
//
//   1. node --check on every gallery and script JS file
//   2. build-gallery.mjs --check (examples.json / pin.json up to date with lean/examples and QED64.lock.json)
//   3. examples.json against the specs: all eight present, text byte-equal to the .lean file, header/title/blurb,
//      first cursor = spec cursors[0], every hint position lands on a cursor/selection command line
//   4. pin.json against QED64.lock.json
//   5. HTML structure: unique ids; every id gallery.js looks up exists; label[for] / aria-* targets exist;
//      classes gallery.js queries exist in the template; local script/link files exist; tag balance;
//      iframe title, html lang, button types
//   6. CSS: every var(--x) is defined on :root; the dark block redefines only known tokens
//   7. lib.js unit tests (parseMem, rerootUrl, classifyStatus, preflight + chooseOverlay on a mock server)
//   8. qed64-bridge.js in a vm sandbox: idempotent install (one listener), D1 abortSignal strip + re-dispatch,
//      D2 applyEdit applied to the open model + reply
//   9. scripts/sim-gallery.mjs: the real gallery.js against a fake DOM and a modelled QED64 page
//  10. --live: start scripts/serve.mjs on a spare port (QUIET, Node only — no browser) and run the real preflight
//      against the served overlays, plus MIME/COOP/COEP checks on the gallery files.
// Usage: node scripts/check-gallery.mjs [--live] [--port 5199]
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import { spawnSync, spawn } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// the console allowlist names the QED64 main bundle as "@qed64-main-bundle"; resolved to the ACTIVE pin's bundle
const PINS = await import(path.join(SC, 'scripts/lib/pins.mjs'));
const MAIN_BUNDLE = PINS.mainBundle();
const G = path.join(SC, 'gallery');
const argv = process.argv.slice(2);
const LIVE = argv.includes('--live');
const PORT = Number(argv[argv.indexOf('--port') + 1]) || 5199;
let fails = 0, oks = 0;
const ok = (cond, msg) => { if (cond) { oks++; console.log(`ok    ${msg}`); } else { fails++; console.log(`FAIL  ${msg}`); } return !!cond; };
const section = (t) => console.log(`\n== ${t}`);
/** ok() on fn()'s result; a throw is reported as a named FAIL line, never as a crash of the whole gate. */
const okTry = (fn, msg) => { let v; try { v = fn(); } catch (e) { return ok(false, `${msg} — threw ${e && e.name}: ${e && e.message}`); } return ok(v, msg); };
const read = (p) => fs.readFileSync(p, 'utf8');

// ---------------------------------------------------------------- 1. syntax
section('1. node --check');
const jsFiles = [
  ...fs.readdirSync(G).filter((f) => f.endsWith('.js')).map((f) => path.join(G, f)),
  path.join(SC, 'scripts', 'build-gallery.mjs'), path.join(SC, 'scripts', 'check-gallery.mjs'),
];
for (const f of jsFiles) {
  const r = spawnSync(process.execPath, ['--check', f], { encoding: 'utf8' });
  ok(r.status === 0, `node --check ${path.relative(SC, f)}${r.status ? `\n${r.stderr}` : ''}`);
}

// ---------------------------------------------------------------- 2. build freshness
section('2. build-gallery --check');
{
  const r = spawnSync(process.execPath, [path.join(SC, 'scripts', 'build-gallery.mjs'), '--check'], { encoding: 'utf8' });
  const last = (r.stdout || '').trim().split('\n').pop();
  ok(r.status === 0, `build-gallery.mjs --check exit ${r.status}: ${last}`);
  if (r.status !== 0) console.log(r.stdout);
}

// ---------------------------------------------------------------- 3. examples.json vs specs
section('3. examples.json vs lean/examples');
const data = JSON.parse(read(path.join(G, 'examples.json')));
const WANT = ['chart-kit', 'dist-lens', 'expr-xray', 'graph-scope', 'hasse-view', 'interval-inspector', 'simp-lens', 'tree-scope'];
ok(JSON.stringify(data.examples.map((e) => e.id).sort()) === JSON.stringify(WANT) && data.count === 8, `all eight present: ${data.examples.map((e) => e.id).join(', ')}`);
for (const ex of data.examples) {
  const leanBytes = fs.readFileSync(path.join(SC, 'lean', 'examples', `${ex.id}.lean`));
  const spec = JSON.parse(read(path.join(SC, 'lean', 'examples', `${ex.id}.json`)));
  const byteEq = Buffer.compare(Buffer.from(ex.text, 'utf8'), leanBytes) === 0;
  const sha = crypto.createHash('sha256').update(leanBytes).digest('hex');
  ok(byteEq && ex.textSha256 === sha, `${ex.id}: text byte-equal to ${ex.id}.lean (${leanBytes.length} bytes, sha256 ${sha.slice(0, 12)})`);
  const lines = ex.text.split('\n');
  const c0 = spec.cursors[0];
  const fcOk = ex.firstCursor.line === c0.line && ex.firstCursor.character === c0.character && ex.firstCursor.lineNumber === c0.line + 1
    && ex.firstCursor.column === c0.character + 1 && lines[c0.line].slice(c0.character).startsWith(c0.command);
  const metaOk = ex.title === spec.title && ex.blurb === spec.blurb && JSON.stringify(ex.header) === JSON.stringify(spec.header)
    && lines[0] === spec.header[0] && lines[1] === spec.header[1] && ex.module === spec.header[1].replace(/^import\s+/, '');
  ok(fcOk && metaOk, `${ex.id}: title/blurb/header match the spec; first cursor L${ex.firstCursor.lineNumber}:${ex.firstCursor.column} on \`${c0.command.slice(0, 40)}\``);
  const commandLines = new Set([...spec.cursors.map((c) => c.line), ...(spec.selections || []).map((x) => x.line)]);
  const badHints = ex.tryThis.filter((h) => !commandLines.has(h.line) || h.lineNumber !== h.line + 1 || h.column !== h.character + 1 || !h.label || !h.detail);
  const n = { cursor: 0, click: 0, select: 0, hover: 0 }; for (const h of ex.tryThis) n[h.kind]++;
  const countsOk = n.cursor === spec.cursors.length && n.click === (spec.clicks || []).length && n.select === (spec.selections || []).length && n.hover === (spec.hovers || []).length;
  ok(badHints.length === 0 && countsOk, `${ex.id}: ${ex.tryThis.length} hints (${n.cursor} cursor, ${n.click} click, ${n.select} select, ${n.hover} hover) all on command lines`);
}

// ---------------------------------------------------------------- 4. pin.json
section('4. pin.json vs QED64.lock.json');
const pin = JSON.parse(read(path.join(G, 'pin.json')));
const lockBuf = fs.readFileSync(path.join(SC, 'QED64.lock.json'));
const lock = JSON.parse(lockBuf.toString('utf8'));
ok(pin.buildId === lock.qed64.buildId && pin.qed64.commit === lock.qed64.commit && pin.lockSha256 === crypto.createHash('sha256').update(lockBuf).digest('hex'),
  `pin.json buildId ${pin.buildId} == lock; commit ${pin.qed64.commit.slice(0, 12)}; lockSha256 matches`);
ok(JSON.stringify(pin.bundleBuildIds) === JSON.stringify([pin.buildId]), `release bundle names exactly [${pin.bundleBuildIds}]`);

// ---------------------------------------------------------------- 5. HTML structure
section('5. index.html structure');
const html = read(path.join(G, 'index.html'));
const js = read(path.join(G, 'gallery.js'));
const css = read(path.join(G, 'gallery.css'));
const ids = [...html.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]);
const dupIds = ids.filter((x, i) => ids.indexOf(x) !== i);
ok(dupIds.length === 0, `${ids.length} ids, unique${dupIds.length ? ` (dups: ${dupIds})` : ''}`);
const jsIds = new Set([...js.matchAll(/\$\('([^']+)'\)/g), ...js.matchAll(/getElementById\('([^']+)'\)/g)].map((m) => m[1]));
// ids gallery.js looks up inside the QED64 page document (not ours)
const PAGE_IDS = new Set(['bar', 'boot', 'bootcard', 'bootlabel', 'qed64-showcase-stack', 'qed64-showcase-page']); // ids in the QED64 page document, not in index.html
const missingIds = [...jsIds].filter((x) => !PAGE_IDS.has(x) && !ids.includes(x));
ok(missingIds.length === 0, `every id gallery.js references exists (${[...jsIds].filter((x) => !PAGE_IDS.has(x)).length} ids${missingIds.length ? `; missing: ${missingIds}` : ''})`);
const unusedIds = ids.filter((x) => !jsIds.has(x) && !html.includes(`#${x}"`) && !html.includes(`"${x}"`.replace(/^/, 'for=')));
console.log(`info  ids not referenced by gallery.js (CSS/ARIA/anchor use): ${unusedIds.join(', ') || 'none'}`);
const refAttrs = [...html.matchAll(/\s(for|aria-labelledby|aria-describedby|aria-controls)="([^"]+)"/g)];
const badRefs = refAttrs.flatMap((m) => m[2].split(/\s+/).filter((t) => !ids.includes(t)).map((t) => `${m[1]}=${t}`));
ok(badRefs.length === 0, `${refAttrs.length} label/aria references resolve${badRefs.length ? ` (bad: ${badRefs})` : ''}`);
const hrefTargets = [...html.matchAll(/href="#([^"]+)"/g)].map((m) => m[1]);
ok(hrefTargets.every((t) => ids.includes(t)), `in-page links resolve: ${hrefTargets.map((t) => '#' + t).join(', ')}`);
const tplMatch = /<template id="card-template">([\s\S]*?)<\/template>/.exec(html);
const tplClasses = new Set(tplMatch ? [...tplMatch[1].matchAll(/class="([^"]+)"/g)].flatMap((m) => m[1].split(/\s+/)) : []);
const jsQueried = new Set([...js.matchAll(/querySelector(?:All)?\('\.([a-z0-9-]+)/g), ...js.matchAll(/closest\('\.([a-z0-9-]+)/g)].map((m) => m[1]));
const missingCls = [...jsQueried].filter((c) => !tplClasses.has(c));
ok(tplMatch && missingCls.length === 0, `classes gallery.js queries exist in #card-template: ${[...jsQueried].join(', ')}${missingCls.length ? ` (missing: ${missingCls})` : ''}`);
const localRefs = [...html.matchAll(/\s(?:src|href)="([^"#:][^"]*)"/g)].map((m) => m[1]).filter((u) => !u.startsWith('/'));
ok(localRefs.every((u) => fs.existsSync(path.join(G, u))), `local script/link files exist: ${localRefs.join(', ')}`);
ok(/<html lang="en">/.test(html) && /<iframe[^>]*\stitle="[^"]+"/.test(html) && /<meta name="viewport"/.test(html), 'html lang, viewport meta, iframe title present');
const buttons = [...html.matchAll(/<button\b[^>]*>/g)].map((m) => m[0]);
ok(buttons.every((b) => /type="button"/.test(b)), `${buttons.length} buttons all type="button"`);
{ // tag balance (non-void elements), ignoring comments
  const VOID = new Set(['meta', 'link', 'br', 'img', 'input', 'hr', 'source', 'path', 'col', 'area', 'base', 'wbr', 'track', 'embed', 'param']);
  const stack = []; let bad = null;
  const body = html.replace(/<!--[\s\S]*?-->/g, '').replace(/<!doctype[^>]*>/i, '');
  for (const m of body.matchAll(/<(\/?)([a-zA-Z][a-zA-Z0-9-]*)\b[^>]*?(\/?)>/g)) {
    const [, close, tagRaw, self] = m; const tag = tagRaw.toLowerCase();
    if (VOID.has(tag) || self) continue;
    if (!close) stack.push(tag);
    else { const top = stack.pop(); if (top !== tag) { bad = `</${tag}> closes <${top}>`; break; } }
  }
  ok(!bad && stack.length === 0, `tags balanced${bad ? `: ${bad}` : stack.length ? `: unclosed ${stack}` : ''}`);
}
{ // JS ids used in CSS selectors exist; CSS ids exist
  const cssIds = [...new Set([...css.matchAll(/#([a-z][a-z0-9-]*)\b/g)].map((m) => m[1]))].filter((x) => !/^[0-9a-f]{3,8}$/i.test(x));
  const missing = cssIds.filter((x) => !ids.includes(x));
  ok(missing.length === 0, `ids used in gallery.css exist: ${cssIds.join(', ')}${missing.length ? ` (missing: ${missing})` : ''}`);
}

// ---------------------------------------------------------------- 6. CSS tokens
section('6. gallery.css tokens');
{
  const rootBlock = /:root\s*\{([\s\S]*?)\}/.exec(css)[1];
  const defined = new Set([...rootBlock.matchAll(/(--[a-z0-9-]+)\s*:/g)].map((m) => m[1]));
  const used = new Set([...css.matchAll(/var\((--[a-z0-9-]+)/g)].map((m) => m[1]));
  const undef = [...used].filter((v) => !defined.has(v));
  ok(undef.length === 0, `${used.size} tokens used, all defined on :root${undef.length ? ` (undefined: ${undef})` : ''}`);
  const dark = /@media \(prefers-color-scheme: dark\)\s*\{\s*:root\s*\{([\s\S]*?)\}/.exec(css);
  const darkDefs = dark ? [...dark[1].matchAll(/(--[a-z0-9-]+)\s*:/g)].map((m) => m[1]) : [];
  const colorTokens = [...defined].filter((t) => /#[0-9a-f]{3,8}|rgba?\(/i.test(new RegExp(`${t}\\s*:\\s*([^;]+);`).exec(rootBlock)[1]));
  const notRedefined = colorTokens.filter((t) => !darkDefs.includes(t));
  ok(dark && darkDefs.every((t) => defined.has(t)) && notRedefined.length === 0, `dark scheme redefines all ${colorTokens.length} color tokens${notRedefined.length ? ` (missing: ${notRedefined})` : ''}`);
  ok(/body\s*\{[^}]*background:\s*var\(--bg\)/.test(css), 'body has an explicit background');
  ok(/\[hidden\]\s*\{\s*display:\s*none\s*!important;?\s*\}/.test(css), '[hidden] beats component display rules (.notice flex, .btn inline-flex)');
  ok(/@media \(max-width: 720px\)[\s\S]*\.rail \{ display: none; \}[\s\S]*\.mobile-bar \{/.test(css), 'narrow layout: rail hidden, mobile select bar shown at <= 720px');
  // the hidden veil leaves rendering (and with it the accessibility tree) after its fade; gallery.js adds aria-hidden + inert
  ok(/\.veil\.is-hidden\s*\{[^}]*visibility:\s*hidden[^}]*visibility 0s linear \.3s/.test(css) && /function hideVeil\(\)[^\n]*aria-hidden', 'true'[^\n]*inert/.test(js) && /function showVeil\([^\n]*removeAttribute\('aria-hidden'\)[^\n]*removeAttribute\('inert'\)/.test(js),
    'the hidden veil: visibility hidden after the .3 s fade (CSS), aria-hidden="true" and inert (hideVeil), both removed by showVeil');
}

// ---------------------------------------------------------------- 7. lib.js
section('7. lib.js unit tests');
const L = await import(pathToFileURL(path.join(G, 'lib.js')).href);
{
  const GiB = 2 ** 30;
  const m = (x) => L.parseMem(x);
  ok(m(null).ok && m(null).bytes === null && m('3').bytes === 3 * GiB && m('2.5').bytes === 2.5 * GiB && m('9').bytes === 6 * GiB && m('0.1').bytes === GiB
    && !m('abc').ok && !m('-1').ok && m('3.1').bytes % (256 * 2 ** 20) === 0, 'parseMem: null, 3, 2.5, clamp 9→6, 0.1→1, rejects abc/-1, 256 MiB steps');
  ok(L.rerootUrl('/snapshots/init.35c8c5f5419e0c33.snapz', 'widgets7') === '/snapshots/widgets7/init.35c8c5f5419e0c33.snapz'
    && L.rerootUrl('https://x/y.snapz', 'w') === 'https://x/y.snapz' && L.frameUrl('widgets8') === '/?snapshots=snapshots/widgets8', 'rerootUrl / frameUrl mirror qed64-boot.ts');
  const cs = (st, r) => L.classifyStatus(st, r).kind;
  ok(cs(null, false) === 'none' && cs({ phase: 'ready' }, false) === 'ready' && cs({ phase: 'booting', relay: 'halted' }, true) === 'halted'
    && cs({ phase: 'booting', lastDeath: { reason: 'bootFailed', message: "snapshot 'init' failed to load" } }, false) === 'bootFailed'
    && L.classifyStatus({ phase: 'booting', lastDeath: { reason: 'crash' } }, false).soft
    && cs({ phase: 'dead', lastDeath: { reason: 'crash' } }, true) === 'dead' && cs({ phase: 'headerRefused', header: { missing: ['DistLens'] } }, true) === 'refused'
    && cs({ phase: 'elaborating' }, true) === 'busy', 'classifyStatus: none/ready/halted/bootFailed(soft)/dead/refused/busy');
  const ex = new Set(['EX']);
  const ps = (o) => L.planSave({ seedText: 'EX', exampleTexts: ex, saved: null, history: [], ...o });
  ok(ps({ prev: 'mine' }).action === 'saved' && ps({ prev: 'mine' }).saved === 'mine'
    && ps({ prev: 'other', saved: 'mine' }).saved === 'mine' && ps({ prev: 'other', saved: 'mine' }).history[0] === 'other'
    && ps({ prev: 'mine', saved: 'mine' }).action === 'known' && ps({ prev: 'EX', saved: 'mine' }).action === 'none' && ps({ prev: null }).action === 'none'
    && ps({ prev: `${L.MEM_PLACEHOLDER_PREFIX} x` }).action === 'none'
    && ps({ prev: 'n', saved: 'mine', history: ['a', 'b', 'c', 'd', 'e'] }).history.length === L.SAVED_HISTORY_MAX,
    'planSave: first user buffer saved, an existing saved value is never overwritten (bounded newest-first history), examples/placeholder ignored');
  { // edited examples never enter saved/history; the chooser lists kept buffers newest first
    const EXT = 'import Mathlib\nimport A\n\n/-! # A: title\nbody\n';
    const ex2 = new Set([EXT]);
    const p2 = L.planSave({ prev: `${EXT}-- my edit\n`, seedText: 'S', exampleTexts: ex2, saved: 'mine', history: ['h1', 'h2', 'h3', 'h4', 'h5'] });
    const p3 = L.planSave({ prev: `${EXT}-- my edit\n`, seedText: 'S', exampleTexts: ex2, saved: null, history: [] });
    const p4 = L.planSave({ prev: 'import Mathlib\nimport A\n\n-- my own file\n', seedText: 'S', exampleTexts: ex2, saved: null, history: [] });
    const se = L.savedEntries('first', ['newer', 'new']);
    ok(p2.action === 'example' && p2.exampleEdit.endsWith('-- my edit\n') && p2.history.join() === 'h1,h2,h3,h4,h5' && p2.saved === 'mine'
      && p3.action === 'example' && p3.saved === null && p4.action === 'saved'
      && se.map((e) => e.text).join() === 'newer,new,first' && /^newest: /.test(se[0].label) && /^first saved: /.test(se[2].label)
      && L.savedEntries('only', []).length === 1 && L.savedEntries(null, []).length === 0,
    'planSave: an edited example (same first 4 lines) goes to its own slot, never to saved/history; savedEntries newest first');
  }
  const ids = ['chart-kit', 'hasse-view'];
  // each case on its own line, inside okTry: a reverted fix (decodeURIComponent throwing) is a named FAIL, not a crash
  okTry(() => L.parseHash('#hasse-view', ids).id === 'hasse-view', 'parseHash: #hasse-view -> hasse-view');
  okTry(() => { const h = L.parseHash('#%', ids); return h.id === null && h.bad === '%'; }, 'parseHash: malformed escape #% -> {id: null, bad: "%"} (never throws)');
  okTry(() => L.parseHash('#%E0%A4%A', ids).id === null, 'parseHash: truncated UTF-8 escape #%E0%A4%A -> id null (never throws)');
  okTry(() => L.parseHash('#nope', ids).bad === 'nope', 'parseHash: unknown id #nope -> bad "nope"');
  okTry(() => L.parseHash('', ids).bad === null && L.parseHash('', ids).id === null, 'parseHash: empty hash -> no id, no notice');
  ok(L.memPlaceholder(3).split('\n').every((l) => !/^\s*import\s/.test(l)) && L.memPlaceholder(3).startsWith(L.MEM_PLACEHOLDER_PREFIX), 'mem placeholder has no import lines (boots [init] at 256 MiB)');
  { // checkCapabilities (the card before anything boots); the probe module is QED64's own (lean.worker.js MEMORY64_PROBE)
    const worker = read(path.join(SC, 'vendor', 'qed64', 'public', 'workers', 'lean.worker.js'));
    const wp = /const MEMORY64_PROBE = new Uint8Array\(\[([\s\S]*?)\]\)/.exec(worker);
    const wbytes = wp ? wp[1].replace(/\/\/[^\n]*/g, '').split(',').map((x) => x.trim()).filter(Boolean).map(Number) : null;
    ok(wbytes && wbytes.join() === L.MEMORY64_PROBE.join() && WebAssembly.validate(new Uint8Array(L.MEMORY64_PROBE)),
      `MEMORY64_PROBE equals the active pin's lean.worker.js probe (${L.MEMORY64_PROBE.length} bytes) and validates in this Node`);
    const full = { crossOriginIsolated: true, SharedArrayBuffer, WebAssembly, BigInt };
    const cc = (o) => L.checkCapabilities({ ...full, ...o });
    const all = cc({ deviceMemory: 8 }); const none = cc({ deviceMemory: undefined });
    ok(all.ok && all.missing.length === 0 && all.checks.map((c) => c.id).join() === 'coi,sab,memory64,memory' && none.ok && /does not report/.test(none.checks[3].detail),
      'checkCapabilities: a capable browser passes (deviceMemory 8 ok; not exposed = not judged)');
    const coi = cc({ crossOriginIsolated: false }); const sab = cc({ SharedArrayBuffer: undefined }); const m64 = cc({ WebAssembly: { validate: () => false, Memory: WebAssembly.Memory } });
    const nowa = cc({ WebAssembly: undefined }); const nosh = cc({ WebAssembly: { validate: WebAssembly.validate, Memory: function () { throw new Error('shared i64 unsupported'); } } });
    const mem = cc({ deviceMemory: 4 }); const thr = cc({ WebAssembly: { validate: () => { throw new Error('boom'); } } });
    ok(coi.hard.join() === 'coi' && sab.hard.join() === 'sab' && m64.hard.join() === 'memory64' && nowa.hard.join() === 'memory64' && /no WebAssembly/.test(nowa.checks[2].detail)
      && nosh.hard.join() === 'memory64' && /shared 64-bit/.test(nosh.checks[2].detail) && thr.hard.join() === 'memory64'
      && mem.ok === false && mem.hard.length === 0 && mem.soft.join() === 'memory' && mem.deviceMemory === 4,
      'checkCapabilities: each missing capability is named (coi, sab, memory64: no validate / no WebAssembly / no shared 64-bit memory / validate throws); low deviceMemory is soft');
    const many = cc({ crossOriginIsolated: false, SharedArrayBuffer: undefined, deviceMemory: 2 });
    ok(coi.lacks === 'cross-origin isolation' && many.lacks === 'cross-origin isolation, SharedArrayBuffer and enough memory' && many.hard.join() === 'coi,sab' && many.soft.join() === 'memory'
      && L.BROWSER_NEED === 'This showcase needs a Chromium-based desktop browser (Chrome, Edge, Brave, Arc) on a computer with 16 GB of RAM or more, one showcase tab at a time (a tab uses about 8–9 GB, about 12 GB on a reload)',
      `checkCapabilities: the card's words: "${L.BROWSER_NEED}; your browser lacks ${many.lacks}."`);
  }
}
// mock server
const BID = pin.buildId;
const T = { init: 32643645, region: 400000000 };
function mockFetch(files) {
  return async (url, init = {}) => {
    const u = new URL(url, 'http://mock');
    const f = files[u.pathname];
    const headers = new Map(Object.entries(f ? f.headers || {} : { 'content-type': 'text/plain' }).map(([k, v]) => [k.toLowerCase(), String(v)]));
    const body = f ? f.body ?? '' : 'not found';
    return { ok: !!f && (f.status || 200) < 300, status: f ? f.status || 200 : 404, headers: { get: (k) => headers.get(k.toLowerCase()) ?? null },
      text: async () => (init.method === 'HEAD' ? '' : body), json: async () => JSON.parse(body) };
  };
}
const goodIndex = (overlay, { runtime = BID, transfer = T.region, imports = ['QED64.Essential', 'ChartKit', 'HasseView'] } = {}) => JSON.stringify({ schema: L.SNAPSHOT_SCHEMA, snapshots: [
  { name: 'init', url: '/snapshots/init.35c8c5f5419e0c33.snapz', digest: `sha256:${'a'.repeat(64)}`, bytes: 1, transfer: T.init, imports: [], runtime: BID },
  { name: 'mathlib', url: '/snapshots/widgets.0123456789abcdef.snapz', digest: `sha256:${'b'.repeat(64)}`, bytes: 2, transfer, imports, runtime },
] });
const site = (overlay, opts = {}, headOverrides = {}) => ({
  [`/runtime/runtime-manifest.${BID}.json`]: { headers: { 'content-type': 'application/json' }, body: JSON.stringify({ buildId: BID, leanVersion: '4.34.0' }) },
  [`/snapshots/${overlay}/index.json`]: { headers: { 'content-type': 'application/json; charset=utf-8' }, body: goodIndex(overlay, opts) },
  [`/snapshots/${overlay}/init.35c8c5f5419e0c33.snapz`]: { headers: { 'content-type': 'application/octet-stream', 'content-length': T.init } },
  [`/snapshots/${overlay}/widgets.0123456789abcdef.snapz`]: { headers: { 'content-type': 'application/octet-stream', 'content-length': T.region, ...headOverrides } },
});
const modules = Object.fromEntries(data.examples.map((e) => [e.id, e.module]));
{
  const r = await L.preflightOverlay({ overlay: 'widgets7', buildId: BID, fetch: mockFetch(site('widgets7')), modules });
  ok(r.ok && r.availability['chart-kit'] === true && r.availability['dist-lens'] === false && r.checks.length >= 10, `preflight good overlay: ok, ${r.checks.length} checks, availability chart-kit=true dist-lens=false`);
  const bad = async (name, files, wantFail) => {
    const x = await L.preflightOverlay({ overlay: 'widgets7', buildId: BID, fetch: mockFetch(files), modules });
    const failed = x.checks.filter((c) => !c.ok).map((c) => c.id);
    ok(!x.ok && failed.includes(wantFail), `preflight rejects ${name}: failed [${failed.join(', ')}]`);
    return x;
  };
  await bad('unpaired runtime', site('widgets7', { runtime: 'wasm64-0000000000000000' }), 'entry-mathlib-runtime');
  await bad('content-length != transfer', site('widgets7', {}, { 'content-length': T.region - 1 }), 'entry-mathlib-head');
  await bad('HTML answer for .snapz (SPA fallback)', site('widgets7', {}, { 'content-type': 'text/html; charset=utf-8' }), 'entry-mathlib-head');
  await bad('content-encoding gzip', site('widgets7', {}, { 'content-encoding': 'gzip' }), 'entry-mathlib-head');
  const nf = await bad('missing index (404)', {}, 'index-http');
  ok(nf.notFound === true, 'missing index sets notFound');
  const s2 = site('widgets7'); s2[`/snapshots/widgets7/index.json`].headers['content-type'] = 'text/html';
  await bad('HTML index', s2, 'index-http');
  const s3 = site('widgets7'); delete s3[`/snapshots/widgets7/widgets.0123456789abcdef.snapz`];
  await bad('missing .snapz (404 on HEAD)', s3, 'entry-mathlib-head');
  const s4 = site('widgets7'); s4[`/runtime/runtime-manifest.${BID}.json`].body = JSON.stringify({ buildId: 'wasm64-ffffffffffffffff' });
  await bad('runtime manifest for another build', s4, 'runtime-manifest');
  const s5 = site('widgets7'); s5['/snapshots/widgets7/index.json'].body = JSON.stringify({ schema: L.SNAPSHOT_SCHEMA, snapshots: [JSON.parse(goodIndex('widgets7')).snapshots[0]] });
  await bad('index without a mathlib entry', s5, 'index-names');
  const bn = await L.preflightOverlay({ overlay: '../x', buildId: BID, fetch: mockFetch({}), modules });
  ok(!bn.ok && bn.checks[0].id === 'overlay-name' && bn.checks.length === 1, 'preflight rejects an unsafe overlay name without fetching');
  // chooseOverlay
  const c1 = await L.chooseOverlay({ requested: null, buildId: BID, fetch: mockFetch(site('widgets7')), modules });
  ok(c1.ok && c1.overlay === 'widgets7' && c1.fellBack && c1.attempts[0].overlay === 'widgets8' && c1.attempts[0].result.notFound, 'chooseOverlay: widgets8 404 → falls back to widgets7');
  const c2 = await L.chooseOverlay({ requested: null, buildId: BID, fetch: mockFetch({ ...site('widgets7'), ...site('widgets8', { imports: ['QED64.Essential', 'DistLens'] }) }), modules });
  ok(c2.ok && c2.overlay === 'widgets8' && !c2.fellBack && c2.result.availability['dist-lens'] === true, 'chooseOverlay: widgets8 preferred when paired');
  const c3 = await L.chooseOverlay({ requested: 'widgets8', buildId: BID, fetch: mockFetch(site('widgets7')), modules });
  ok(!c3.ok && c3.attempts.length === 1, 'chooseOverlay: explicit ?overlay= never falls back');
  const c4 = await L.chooseOverlay({ requested: null, buildId: BID, fetch: mockFetch({ ...site('widgets8', { runtime: 'wasm64-0000000000000000' }) }), modules });
  ok(!c4.ok && c4.overlay === 'widgets8', 'chooseOverlay: reports the unpaired widgets8 over the absent widgets7');
}

// ---------------------------------------------------------------- 8. bridge in a sandbox
section('8. qed64-bridge.js (vm sandbox)');
{
  const src = read(path.join(G, 'qed64-bridge.js'));
  const sandbox = { window: {}, JSON, setTimeout, clearTimeout };
  vm.createContext(sandbox);
  vm.runInContext(src, sandbox);
  const install = sandbox.window.installQed64Bridge;
  ok(typeof install === 'function', 'bridge defines window.installQed64Bridge');
  // a fake QED64 page window
  const listeners = [];
  const dispatched = [];
  const posted = [];
  const edits = [];
  const model = { uri: { toString: () => 'file:///project/Probe.lean' }, getLineContent: () => '', getLineCount: () => 3 };
  const page = {
    qed64: { editor: { getModel: () => model, pushUndoStop() {}, executeEdits: (src2, e) => edits.push(e), setSelection() {}, revealRangeInCenterIfOutsideViewport() {}, focus() {}, getPosition: () => ({ lineNumber: 1, column: 1 }) } },
    addEventListener: (type, fn, capture) => listeners.push({ type, fn, capture }),
    dispatchEvent: (ev) => dispatched.push(ev),
    MessageEvent: class { constructor(type, init) { this.type = type; Object.assign(this, init); } },
  };
  const a = install(page); const b = install(page); const c = install(page);
  ok(a === b && b === c && listeners.length === 1 && listeners[0].type === 'message' && listeners[0].capture === true, `idempotent: 3 installs → ${listeners.length} capture-phase message listener, same stats object`);
  const fire = (msg) => { let stopped = false; listeners[0].fn({ data: JSON.stringify(msg), origin: 'http://localhost:5190', source: { postMessage: (m) => posted.push(JSON.parse(m)) }, stopImmediatePropagation: () => { stopped = true; } }); return stopped; };
  const stopped1 = fire({ seqNum: 7, name: 'sendClientRequest', args: ['file:///project/Probe.lean', '$/lean/rpc/call', {}, { abortSignal: {} }] });
  const re = dispatched[0] && JSON.parse(dispatched[0].data);
  ok(stopped1 && a.stripped === 1 && re && !('abortSignal' in re.args[3]) && re.seqNum === 7, 'D1: abortSignal stripped, original stopped, clean message re-dispatched');
  const stopped2 = fire({ seqNum: 8, name: 'applyEdit', args: [{ changes: { 'file:///project/Probe.lean': [{ range: { start: { line: 2, character: 0 }, end: { line: 2, character: 0 } }, newText: '\nexample : True := trivial' }] } }] });
  ok(stopped2 && a.applied === 1 && edits.length === 1 && edits[0][0].range.startLineNumber === 3 && edits[0][0].text === '\nexample : True := trivial' && posted.some((p) => p.seqNum === 8),
    'D2: applyEdit for the open model applied via executeEdits (LSP 0-based → Monaco 1-based) and answered');
  const stopped3 = fire({ seqNum: 9, name: 'applyEdit', args: [{ changes: { 'file:///other.lean': [] } }] });
  ok(!stopped3 && a.passed === 1, 'applyEdit for another document passes through untouched');
  const stopped4 = fire({ seqNum: 10, name: 'sendClientRequest', args: ['u', 'm', {}, {}] });
  ok(!stopped4 && a.stripped === 1, 'sendClientRequest without abortSignal passes through');

  // D3: concurrent getWidgetSource for one hash -> one request to the page, duplicates answered from its reply
  const lsp = []; const toClientSeen = [];
  page.qed64.relay = { fromClient(m) { lsp.push(m); }, toClient(m) { toClientSeen.push(m); } };
  const ws = (seq, hash) => ({ seqNum: seq, name: 'sendClientRequest', args: ['file:///project/Probe.lean', '$/lean/rpc/call', { sessionId: '1', method: 'Lean.Widget.getWidgetSource', params: { pos: { line: 0, character: 0 }, hash } }, { abortSignal: {} }] });
  const d0 = dispatched.length;
  // re-dispatches go back through the listener, as they do on a real window
  page.dispatchEvent = (ev) => { dispatched.push(ev); listeners[0].fn({ data: ev.data, origin: ev.origin, source: ev.source, stopImmediatePropagation() {} }); };
  const s1 = fire(ws(20, '123')), s2 = fire(ws(21, '123')), s3 = fire(ws(22, '123')), s4 = fire(ws(23, '456'));
  const first = dispatched.slice(d0).map((e) => JSON.parse(e.data));
  ok(s1 && s2 && s3 && s4 && first.length === 2 && first[0].seqNum === 20 && first[1].seqNum === 23 && first.every((m) => !('abortSignal' in m.args[3])) && a.ws.fetched === 2 && a.ws.tapped === true,
    `D3: 3 concurrent getWidgetSource for one hash -> 1 forwarded (clean), 2 held; another hash forwarded (fetched ${a.ws.fetched})`);
  // the page's LSP traffic for the two first requests, then the server replies
  page.qed64.relay.fromClient({ jsonrpc: '2.0', id: 101, method: '$/lean/rpc/call', params: JSON.parse(JSON.stringify(ws(0, '123').args[2])) });
  page.qed64.relay.fromClient({ jsonrpc: '2.0', id: 102, method: '$/lean/rpc/call', params: JSON.parse(JSON.stringify(ws(0, '456').args[2])) });
  const p0 = posted.length;
  page.qed64.relay.toClient({ jsonrpc: '2.0', id: 101, result: { sourcetext: 'export default 1' } });
  const answered = posted.slice(p0);
  ok(answered.length === 2 && answered.map((p) => p.seqNum).sort().join() === '21,22' && answered.every((p) => p.result && p.result.sourcetext === 'export default 1') && a.ws.coalesced === 2 && toClientSeen.length === 1,
    'D3: the first reply answers both held duplicates with the same {sourcetext} and still reaches the language client');
  const s5 = fire(ws(24, '123'));
  ok(s5 && posted.at(-1).seqNum === 24 && a.ws.cached === 1, 'D3: a later request for a cached hash is answered without the server');
  const s6 = fire(ws(25, '456'));
  const d1 = dispatched.length;
  page.qed64.relay.toClient({ jsonrpc: '2.0', id: 102, error: { code: -32603, message: 'boom' } });
  const rel = dispatched.slice(d1).map((e) => JSON.parse(e.data));
  ok(s6 && rel.length === 1 && rel[0].seqNum === 25 && a.ws.released === 1, 'D3: an error reply releases the held duplicates to the page unchanged (no cache)');
}

// ---------------------------------------------------------------- 8b. selector contract + thumbnails
section('8b. tests/ux/selectors.json gallery contract; card thumbnails');
{
  const SELS = PINS.resolveSelectors(read(path.join(SC, 'tests', 'ux', 'selectors.json')));
  ok(SELS.gallery && SELS.showcaseApi && SELS.consoleAllowlist, 'selectors.json has gallery, showcaseApi and consoleAllowlist sections');
  const galIds = [...new Set(Object.values(SELS.gallery || {}).flatMap((v) => [...String(v).matchAll(/#([a-z][\w-]*)/g)].map((m) => m[1])))]
    .filter((x) => !x.startsWith('card-') && !x.startsWith('qed64-showcase-') && x !== 'examples'); // #examples is the QED64 page's menu
  const missing = galIds.filter((x) => !ids.includes(x));
  ok(galIds.length >= 15 && missing.length === 0, `every gallery id in selectors.json exists in index.html (${galIds.length}${missing.length ? `; missing ${missing}` : ''})`);
  const classes = ['card', 'card-main', 'chip', 'card-thumb', 'card-hints', 'hint', 'hints-toggle', 'is-hidden'];
  const missingCls = classes.filter((c) => !html.includes(`class="${c}`) && !html.includes(` ${c}"`) && !html.includes(` ${c} `) && !js.includes(`'${c}'`) && !js.includes(`.${c}`));
  ok(missingCls.length === 0, `gallery classes in the contract exist in index.html/gallery.js (${classes.length}${missingCls.length ? `; missing ${missingCls}` : ''})`);
  const apiKeys = Object.keys(SELS.showcaseApi || {}).filter((k) => k.endsWith(')')).map((k) => k.replace(/\(.*$/, ''));
  const apiBlock = (js.match(/\nwindow\.__showcase = \{([\s\S]*?)\n\};/) || [])[1] || ''; // the assignment at line start, not the header comment
  const missingApi = apiKeys.filter((k) => !apiBlock.includes(`\n  ${k}:`));
  const verOk = new RegExp(`version: ${SELS.showcaseApi && SELS.showcaseApi.version},`).test(apiBlock);
  ok(apiKeys.length >= 7 && missingApi.length === 0 && verOk, `window.__showcase implements the contract: ${apiKeys.join(', ')} (version ${SELS.showcaseApi && SELS.showcaseApi.version})${missingApi.length ? `; missing ${missingApi}` : ''}`);
  const ex = JSON.parse(read(path.join(G, 'examples.json'))).examples;
  const thumbs = ex.map((e) => {
    const f = path.join(G, 'thumbs', `${e.id}.png`);
    if (!fs.existsSync(f) || !e.thumb) return { id: e.id, ok: false, why: 'missing' };
    const b = fs.readFileSync(f);
    return { id: e.id, ok: b.length <= 60 * 1024 && b.readUInt32BE(16) === 480 && e.thumb.bytes === b.length && e.thumb.sha256 === crypto.createHash('sha256').update(b).digest('hex').slice(0, 16), bytes: b.length };
  });
  ok(thumbs.every((t) => t.ok), `card thumbnails: ${thumbs.filter((t) => t.ok).length}/8 present, 480 px wide, <= 60 KB, recorded in examples.json (${thumbs.map((t) => `${t.id} ${t.bytes || t.why}`).join(', ')})`);
  // ... and wired into the cards (bring-up audit r2 minor: a gallery.js that loaded thumbs/<pkg>.jpg passed every check
  // above): examples.json names exactly thumbs/<pkg>.png, and renderRail assigns that src unchanged. The browser half
  // (every card's thumbnail visible with naturalWidth 480) is tests/ux/bringup/widgets.mjs and UX suite C17.
  {
    const badSrc = ex.filter((e) => !e.thumb || e.thumb.src !== `thumbs/${e.id}.png`).map((e) => `${e.id}: ${e.thumb && e.thumb.src}`);
    const gjs = read(path.join(G, 'gallery.js'));
    const assigns = [...gjs.matchAll(/\bimg\.src\s*=\s*([^;]+);/g)].map((m) => m[1].trim());
    ok(!badSrc.length && assigns.length === 1 && assigns[0] === 'ex.thumb.src', `card thumbnails wired: examples.json thumb.src == thumbs/<pkg>.png for all ${ex.length}; gallery.js assigns img.src = ${assigns.join(' | ') || '(nothing)'}${badSrc.length ? `; bad ${badSrc}` : ''}`);
  }
  // cursor hint labels name the WHOLE command, or an elision of it at term boundaries that says so (bring-up audit r2
  // minor: labels were the spec's truncated prefix, e.g. "#interval_inspect ((3:ℝ) ∈", with no "…" and open brackets)
  {
    const { commandAt, balancedLabel } = await import(pathToFileURL(path.join(SC, 'scripts', 'lib', 'term-labels.mjs')).href);
    const bad = [];
    let whole = 0, elided = 0;
    for (const e of ex) {
      const lines = e.text.split('\n');
      for (const h of e.tryThis.filter((x) => x.kind === 'cursor')) {
        const m = /^Line (\d+) · (.*)$/.exec(h.label);
        const full = commandAt(lines, h.line, h.character);
        if (!m || Number(m[1]) !== h.lineNumber) { bad.push(`${e.id} L${h.lineNumber}: label ${JSON.stringify(h.label)}`); continue; }
        if (m[2] === full) { whole++; continue; }
        if (m[2].includes('…') && balancedLabel(m[2]) && m[2].length < full.length) { elided++; continue; }
        bad.push(`${e.id} L${h.lineNumber}: ${JSON.stringify(m[2])} is neither the whole command nor a balanced elision with "…" of ${JSON.stringify(full.slice(0, 80))}`);
      }
      for (const h of e.tryThis.filter((x) => x.kind === 'click')) {
        const q = /“(.*)”/.exec(h.label);
        if (q && !balancedLabel(q[1])) bad.push(`${e.id} click label ${JSON.stringify(h.label)}: unbalanced`);
      }
    }
    ok(!bad.length && whole + elided >= 46, `cursor hint labels: ${whole} whole commands, ${elided} balanced term-boundary elisions ending in "…"${bad.length ? `; BAD ${bad.slice(0, 4).join(' | ')}` : ''}`);
  }
  // drawings are never cropped (bring-up audit 5 minor: GraphScope's card showed 3 of 5 vertices): every example whose
  // first panel draws an svg (spec cursors[0].expect.svgTagCounts) has a letterboxed thumbnail (thumbs/thumbs.json
  // mode letterbox, 480x220) shown with object-fit: contain (thumb.fit, the gallery.css data-fit rule)
  {
    let man = {}; try { man = JSON.parse(read(path.join(G, 'thumbs', 'thumbs.json'))); } catch { man = {}; }
    const css = read(path.join(G, 'gallery.css'));
    const svgIds = ex.filter((e) => { try { return !!(JSON.parse(read(path.join(SC, 'lean', 'examples', `${e.id}.json`))).cursors[0].expect || {}).svgTagCounts; } catch { return false; } }).map((e) => e.id);
    const badLb = svgIds.filter((id) => { const e = ex.find((x) => x.id === id); return !(man[id] && man[id].mode === 'letterbox' && e.thumb && e.thumb.fit === 'contain' && e.thumb.height === 220); });
    ok(svgIds.length >= 4 && !badLb.length && /\.card-thumb\[data-fit="contain"\]\s*\{[^}]*object-fit:\s*contain/.test(css) && /dataset\.fit\s*=\s*ex\.thumb\.fit/.test(read(path.join(G, 'gallery.js'))),
      `svg-panel thumbnails are whole drawings (letterboxed 480x220, fit contain): ${svgIds.join(', ')}${badLb.length ? `; NOT: ${badLb}` : ''}`);
  }
  // every cursor hint is checkable against a panel bound to its own position (bring-up audit: no vacuous hints)
  const cur = ex.flatMap((e) => e.tryThis.filter((h) => h.kind === 'cursor').map((h) => ({ id: e.id, h })));
  const bad = cur.filter(({ h }) => {
    const p = h.expectPanel;
    if (!p || !p.at || p.at.lineNumber !== h.lineNumber || p.at.character !== h.character || !p.widget || !p.golden) return true;
    const shapes = Object.keys(p.svgTagCounts || {}).filter((k) => !['svg', 'g', 'text'].includes(k)).length;
    return !(p.texts.length || shapes) || /shows the widget panel for this command/.test(h.detail);
  });
  ok(cur.length >= 46 && bad.length === 0, `every cursor hint carries a position-bound golden panel expectation and a concrete claim (${cur.length - bad.length}/${cur.length}${bad.length ? `; bad ${bad.map((b) => `${b.id} L${b.h.lineNumber}`)}` : ''})`);
  // select hints (bring-up audit 2): a golden-backed selection expectation whose `appear` texts are claimed by the
  // card and checked absent-before / present-after by hints.mjs
  const sel = ex.flatMap((e) => e.tryThis.filter((h) => h.kind === 'select').map((h) => ({ id: e.id, h })));
  const badSel = sel.filter(({ h }) => { const p = h.expectSelectPanel; return !p || !p.golden || !p.squash || !p.at || p.at.lineNumber !== h.lineNumber || !p.appear.length || !p.appear.every((t) => p.texts.includes(t)) || p.picks !== h.expectSelect.length || !h.claimTexts.length || !h.claimTexts.every((t) => p.appear.includes(t) && h.detail.includes(`“${t}”`)); });
  ok(sel.length === 3 && badSel.length === 0, `every select hint carries a golden selection expectation; the card quotes only texts that appear with the selection (${sel.length - badSel.length}/${sel.length}${badSel.length ? `; bad ${badSel.map((b) => `${b.id} L${b.h.lineNumber}`)}` : ''})`);
  const hov = ex.flatMap((e) => e.tryThis.filter((h) => h.kind === 'hover').map((h) => ({ id: e.id, h })));
  const badHov = hov.filter(({ h }) => { const v = h.expectHover; return !v || !v.golden || !v.codeText || !v.tagText || v.popupText !== `${v.exprText} : ${v.typeText}` || !h.detail.includes(v.popupText); });
  ok(hov.length === 1 && badHov.length === 0, `every hover hint carries the golden popup text and the card states it (${hov.map(({ h }) => h.expectHover && h.expectHover.popupText).join(', ')})`);
  // card claims: every quoted text is checked by hints.mjs and quoted whole
  const all = ex.flatMap((e) => e.tryThis.map((h) => ({ id: e.id, h })));
  const unchecked = all.filter(({ h }) => h.kind === 'cursor' && !(h.claimTexts || []).every((t) => h.detail.includes(`“${t}”`) && [...h.expectTexts, ...h.expectPanel.texts].map((x) => x.replace(/\s+/g, ' ').trim()).some((x) => x.includes(t))));
  const truncated = all.filter(({ h }) => /“[^”]*…”/.test(h.detail) || (h.claimTexts || []).some((t) => t.includes('…')));
  const generic = all.filter(({ h }) => h.kind === 'cursor' && (h.claimTexts || []).some((t) => !/[ :._-]/.test(t)) && !(h.expectPanel.texts || []).includes((h.claimTexts || []).find((t) => !/[ :._-]/.test(t))));
  ok(unchecked.length === 0 && truncated.length === 0 && generic.length === 0, `card claims: every quoted text is checked, none truncated, no single generic spec word (${all.length} hints${unchecked.length ? `; unchecked ${unchecked.map((b) => `${b.id} L${b.h.lineNumber}`)}` : ''}${truncated.length ? `; truncated ${truncated.map((b) => `${b.id} L${b.h.lineNumber}`)}` : ''}${generic.length ? `; generic ${generic.map((b) => `${b.id} L${b.h.lineNumber}`)}` : ''})`);
  // the InfoView contract the bring-up checks rely on
  const iv = SELS.infoview || {};
  ok(/tooltip-code-content/.test(iv.hoverPopup || '') && /highlight-selected/.test(iv.selectedSubterm || '') && /expectSelectPanel/.test(iv.expectSelectPanel || '') && /popupText/.test(iv.expectHover || ''),
    'selectors.json infoview: hoverPopup, selectedSubterm, expectSelectPanel and expectHover contracts present');
}

// ---------------------------------------------------------------- 8c. console allowlist classifier (unit tests)
section('8c. tests/ux/bringup/console.mjs classifyConsole against selectors.json consoleAllowlist');
{
  const { classifyConsole } = await import(pathToFileURL(path.join(SC, 'tests', 'ux', 'bringup', 'console.mjs')).href);
  const SELS = PINS.resolveSelectors(read(path.join(SC, 'tests', 'ux', 'selectors.json')));
  const A = SELS.consoleAllowlist;
  ok(A && /classifyConsole/.test(A._enforcedBy || ''), 'consoleAllowlist names its enforcer (_enforcedBy)');
  const unsupported = { message: 'unsupported', stack: 'Error: unsupported\n    at $onExtensionActivationError (x)' };
  const T0 = 1_000_000;
  const empty = { type: 'error', text: '', url: MAIN_BUNDLE, line: 627, wall: T0 };
  const cancel = (dt) => ({ kind: 'errorReply', code: -32800, recvWall: T0 + dt });
  const R2 = [cancel(-1), cancel(-2)]; // two RequestCancelled replies just before the two empty errors
  const esms = { type: 'warning', text: 'TODO: catch JSON.parse failure:  SyntaxError: Unexpected token \'e\', "esms,true,"... is not valid JSON', url: '/infoview/webview.js', line: 0 };
  const W = (o) => ({ messages: [], pageErrors: [], crashed: false, loads: { top: 1, qed64: 1, infoview: 1 }, ...o });
  const c1 = classifyConsole(W({ pageErrors: [unsupported], messages: [empty, empty, esms, { type: 'log', text: 'whatever' }] }), A, { reports: R2 });
  ok(c1.ok && c1.counts['pageerror[0]'] === 1 && c1.counts['consoleError[0]'] === 2, 'a normal run (1 unsupported, empty errors at index:627 each with its -32800 reply, 1 esms warning, logs) is allowed');
  // pairWith (bring-up audit 5 minor): every allowlisted empty console.error needs its OWN LSP -32800 reply in [-3 s, +0.5 s]
  ok(A.consoleError[0].pairWith && A.consoleError[0].pairWith.lspErrorCode === -32800, 'the empty console.error entry declares pairWith -32800');
  ok(!classifyConsole(W({ messages: [empty] }), A).ok, 'pairWith is fail-closed: an empty console.error without tap reports fails');
  ok(!classifyConsole(W({ messages: [empty, empty] }), A, { reports: [cancel(-1)] }).ok, 'two empty console.errors with only one -32800 reply fail (one reply explains one error)');
  ok(!classifyConsole(W({ messages: [empty] }), A, { reports: [cancel(-5000)] }).ok && !classifyConsole(W({ messages: [empty] }), A, { reports: [cancel(+2000)] }).ok, 'a -32800 reply 5 s before or 2 s after does not explain it');
  ok(!classifyConsole(W({ messages: [empty] }), A, { reports: [{ kind: 'errorReply', code: -32603, recvWall: T0 }] }).ok, 'a reply with another code (-32603) does not explain it');
  ok(classifyConsole(W({ messages: [empty] }), A, { reports: [cancel(+300)] }).ok, 'a -32800 reply 0.3 s after (same tick ordering) explains it');
  ok(!classifyConsole(W({ pageErrors: [unsupported, unsupported] }), A).ok, 'two "unsupported" page errors in one QED64 page load fail (maxPerPageLoad 1)');
  ok(classifyConsole(W({ pageErrors: [unsupported, unsupported, unsupported], loads: { top: 3, qed64: 3, infoview: 3 } }), A).ok, 'three in three page loads are allowed');
  ok(!classifyConsole(W({ pageErrors: [{ message: 'Maximum call stack size exceeded.', stack: '' }] }), A).ok, 'an unknown page error ("Maximum call stack size exceeded.", bridge mutant A) fails');
  ok(!classifyConsole(W({ messages: [{ ...empty, text: 'boom' }] }), A).ok, 'a non-empty console.error at the allowed site fails');
  ok(!classifyConsole(W({ messages: [{ ...empty, line: 12 }] }), A).ok, 'an empty console.error at another line fails');
  ok(!classifyConsole(W({ messages: [esms, esms] }), A).ok, 'two esms warnings for one InfoView load fail (maxPerInfoviewLoad 1)');
  ok(!classifyConsole(W({ pageErrors: [{ message: 'unsupported', stack: 'at $tryShowTextDocument' }] }), A).ok, 'unsupported at $tryShowTextDocument (late bridge, D2) fails');
  const outdated = { type: 'error', text: 'Outdated RPC session', url: MAIN_BUNDLE, line: 627 };
  ok(!classifyConsole(W({ messages: [outdated] }), A).ok && classifyConsole(W({ messages: [outdated] }), A, { scenarios: ['relayRestartOrReboot'] }).ok, '"Outdated RPC session" only in the relayRestartOrReboot scenario');
  ok(!classifyConsole(W({ messages: [{ type: 'warning', text: "TODO: catch JSON.parse failure:  TypeError: Cannot read properties of undefined (reading 'resolve')", url: '/infoview/webview.js' }] }), A).ok, 'the double-reply warning (neverAllowed) fails');
  ok(!classifyConsole(W({ crashed: true }), A).ok, 'a renderer crash fails');
  // UX suite scenarios (tests/ux/specs/30-robustness.spec.mjs): allowed only inside the test that breaks the boot / cuts the network
  const died = { type: 'error', text: 'QED64: the Lean checker died (bootFailed)', url: MAIN_BUNDLE, line: 1317 };
  const diedPe = { message: 'QED64: the Lean checker died (bootFailed)\n\nError: QED64: the Lean checker died (bootFailed)', stack: '' };
  ok(!classifyConsole(W({ messages: [died], pageErrors: [diedPe] }), A).ok && classifyConsole(W({ messages: [died], pageErrors: [diedPe] }), A, { scenarios: ['bootFailure'] }).ok, 'bootFailed deaths only in the bootFailure scenario');
  const prefetch = { type: 'warning', text: '[qed64] raw prefetch error: network error — the checker will stream it instead', url: MAIN_BUNDLE, line: 1317 };
  const cut = { type: 'error', text: 'Failed to load resource: net::ERR_INTERNET_DISCONNECTED', url: null, line: null };
  ok(!classifyConsole(W({ messages: [prefetch, cut] }), A).ok && classifyConsole(W({ messages: [prefetch, cut] }), A, { scenarios: ['networkCut'] }).ok, 'network-cut messages only in the networkCut scenario');
  const exactFail = { type: 'warning', text: "[qed64] exact import failed: lean_wasm_compile returned an IO error: uncaught exception: object file '/lib/packs/essential/Mathlib.olean' of module Mathlib does not exist; serving the header from the preloaded library", url: MAIN_BUNDLE, line: 1322 };
  ok(!classifyConsole(W({ messages: [exactFail] }), A).ok && classifyConsole(W({ messages: [exactFail] }), A, { scenarios: ['exactImportsFallback'] }).ok, 'the exact-import fallback warning only in the exactImportsFallback scenario');
  const restartErr = { type: 'error', text: 'QED64: restarting with exact imports', url: MAIN_BUNDLE, line: 627 };
  const restartPe = { message: 'QED64: restarting with exact imports\n\nError: QED64: restarting with exact imports', stack: '' };
  {
    const obs = { type: 'warning', text: '[showcase] liveness: Lean answered none of 2 probes on s1 v12 (observe mode: not restarting)', url: '/showcase/gallery.js', line: 543 };
    const other = { ...obs, text: '[showcase] liveness: something else' };
    ok(!classifyConsole(W({ messages: [obs] }), A).ok && classifyConsole(W({ messages: [obs] }), A, { scenarios: ['livenessObserved'] }).ok && !classifyConsole(W({ messages: [other] }), A, { scenarios: ['livenessObserved'] }).ok,
      'the observe-mode liveness warning only in the livenessObserved scenario, and only that exact text');
  }
  ok(!classifyConsole(W({ messages: [restartErr] }), A).ok && !classifyConsole(W({ pageErrors: [restartPe] }), A).ok && classifyConsole(W({ messages: [restartErr, restartErr], pageErrors: [restartPe] }), A, { scenarios: ['stallRestart'] }).ok, 'the in-flight replies of a stall restart only in the stallRestart scenario');
  {
    // QED64 9fdf9b8+'s own "wedged" reboot (an L7 occurrence handled upstream): its in-flight replies, only in qed64WedgedReboot
    const wErr = { type: 'error', text: 'QED64: the Lean checker died (wedged)', url: MAIN_BUNDLE, line: 627 };
    const wPe = { message: 'QED64: the Lean checker died (wedged)\n\nError: QED64: the Lean checker died (wedged)', stack: '' };
    const crashErr = { ...wErr, text: 'QED64: the Lean checker died (crash)' };
    ok(!classifyConsole(W({ messages: [wErr], pageErrors: [wPe] }), A).ok && !classifyConsole(W({ messages: [wErr] }), A, { scenarios: ['stallRestart'] }).ok
      && classifyConsole(W({ messages: [wErr, wErr], pageErrors: [wPe] }), A, { scenarios: ['qed64WedgedReboot'] }).ok && !classifyConsole(W({ messages: [crashErr] }), A, { scenarios: ['qed64WedgedReboot'] }).ok,
      'QED64\'s "wedged" reboot replies only in the qed64WedgedReboot scenario (a "crash" death is not covered)');
  }
}

// ---------------------------------------------------------------- 9. the controller in a simulated page
section('9. scripts/sim-gallery.mjs (gallery.js against a fake DOM + modelled QED64 page)');
{
  const r = spawnSync(process.execPath, [path.join(SC, 'scripts', 'sim-gallery.mjs')], { encoding: 'utf8', timeout: 120000 });
  const lines = (r.stdout || '').trim().split('\n');
  for (const l of lines.filter((x) => /^FAIL/.test(x))) console.log(`      ${l}`);
  ok(r.status === 0, `sim-gallery exit ${r.status}: ${lines.pop()}`);
}

// ---------------------------------------------------------------- 10. live (Node server only)
if (LIVE) {
  section(`10. live preflight against scripts/serve.mjs on :${PORT} (no browser)`);
  const child = spawn(process.execPath, [path.join(SC, 'scripts', 'serve.mjs')], { env: { ...process.env, PORT: String(PORT), QUIET: '1', HOST: '127.0.0.1' }, stdio: ['ignore', 'pipe', 'pipe'] });
  try {
    const origin = `http://127.0.0.1:${PORT}`;
    await L.waitFor(async () => { try { return (await fetch(`${origin}/showcase/pin.json`)).ok; } catch { return false; } }, { timeoutMs: 10000, intervalMs: 100, label: 'serve.mjs' });
    for (const [f, mime] of [['index.html', 'text/html'], ['gallery.js', 'text/javascript'], ['lib.js', 'text/javascript'], ['qed64-bridge.js', 'text/javascript'], ['gallery.css', 'text/css'], ['examples.json', 'application/json'], ['pin.json', 'application/json']]) {
      const r = await fetch(`${origin}/showcase/${f}`);
      const h = (k) => r.headers.get(k) || '';
      ok(r.status === 200 && h('content-type').startsWith(mime) && h('cross-origin-opener-policy') === 'same-origin' && h('cross-origin-embedder-policy') === 'require-corp',
        `GET /showcase/${f} 200 ${h('content-type')} COOP ${h('cross-origin-opener-policy')} COEP ${h('cross-origin-embedder-policy')}`);
      await r.arrayBuffer();
    }
    const overlays = fs.existsSync(path.join(SC, 'out', 'overlay', 'snapshots')) ? fs.readdirSync(path.join(SC, 'out', 'overlay', 'snapshots')) : [];
    console.log(`info  overlays on disk: ${overlays.join(', ') || 'none'}`);
    for (const ov of [...new Set([...overlays, 'widgets8', 'widgets7', 'nope'])]) {
      const r = await L.preflightOverlay({ overlay: ov, buildId: pin.buildId, fetch: (u, i) => fetch(u, i), modules, origin });
      const expectOk = overlays.includes(ov);
      const avail = r.availability ? Object.entries(r.availability).filter(([, v]) => v).map(([k]) => k) : null;
      ok(r.ok === expectOk, `live preflight ${ov}: ${r.ok ? 'OK' : `refused (${r.checks.filter((c) => !c.ok).map((c) => c.id).join(', ')})`}${r.notFound ? ' [index 404]' : ''}${avail ? `; packages in region: [${avail.join(', ')}]` : ''}`);
      for (const c of r.checks) if (/head|runtime/.test(c.id)) console.log(`        ${c.ok ? '✓' : '✗'} ${c.detail}`);
    }
    const choice = await L.chooseOverlay({ requested: null, buildId: pin.buildId, fetch: (u, i) => fetch(u, i), modules, origin });
    console.log(`info  default overlay choice: ${choice.ok ? choice.overlay : 'none'} (attempts ${choice.attempts.map((a) => `${a.overlay}:${a.ok ? 'ok' : a.result.notFound ? '404' : 'bad'}`).join(' ')})`);
  } finally { child.kill('SIGTERM'); }
}

console.log(`\nCHECK-GALLERY ${fails ? 'FAIL' : 'OK'} ${oks} ok, ${fails} failed`);
process.exit(fails ? 1 : 0);
