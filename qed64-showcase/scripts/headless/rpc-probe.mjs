#!/usr/bin/env node
// E3 (BUILD-PLAN §6): the FileWorker + RPC probe — the wasm twin of
// lean/goldens/lsp-golden.mjs (whose client logic this reuses verbatim where
// possible) and of the packages' *Tests/ClickE2E.lean.
//
//  1. boot `lean --worker` from the pinned QED64 runtime in Node and load the
//     raw snapshots in order via _lean_wasm_load_snapshot_mem (wasm-lsp.mjs);
//  2. initialize + didOpen with the BROWSER header (the example text verbatim);
//  3. assert $/qed64/headerStatus (mode, missing) and wait for diagnostics;
//  4. $/lean/rpc/connect; per spec cursor: Lean.Widget.getWidgets,
//     getWidgetSource for every hash (non-empty, imports @leanprover/infoview),
//     static HtmlDisplayPanel props.html, or the mk_rpc_widget% panel's own
//     @[server_rpc_method] with the InfoView's panel props (incl. the
//     ProofWidgets cancellable protocol) -> Html signature;
//  5. selections (shift-click), hovers (infoToInteractive);
//  6. clicks: MakeEditLink / Try-this edit applied UTF-16-correctly, full-text
//     didChange, post-click diagnostics checked, then reverted;
//  7. write out/headless/<name>.<snapset>.rpc.json (+ .html.json for E3b) and
//     compare with the native golden (lean/expect/<pkg>.json) ignoring the
//     environment-dependent fields (MakeEditLink textDocument uri/version and
//     the raw htmlSha256 of MakeEditLink panels — a uri/version-normalized
//     Html hash is compared instead —, selection mvarIds); print a per-check
//     PASS/FAIL table.
//
// usage:
//   node scripts/headless/rpc-probe.mjs (--pkg <pkg> | --example <f.lean> [--spec <f.json>])
//        --snap <raw.snap> [--snap <raw2.snap> …]   loaded in this order (browser: init, then the umbrella)
//        --lib <olean tree>  [--artifact <stage1>] [--snapset <label>]
//        [--expect-mode covered|exact|refused] [--expect-missing A,B]   (default: spec.headless, else covered)
//        [--golden-env w7|w8]   which frozen native golden set the run is judged against:
//                               w7 -> lean/expect/<pkg>.json (dist-lens: not in w7 -> usage error)
//                               w8 -> lean/expect/w8/<pkg>.json (dist-lens: lean/expect/dist-lens.json)
//                               default: the golden's own environment.golden (w7 for phase-1, w8 dist-lens)
//        [--golden <expect.json> | --golden none]   explicit golden (overrides --golden-env)
//        [--golden-html <html.json>]   golden Html dump; default: lean/expect/<sub>/x.json ->
//                               lean/expect/html/<sub>/x.json, <x>.rpc.json -> <x>.html.json.
//                               Missing while the golden has MakeEditLink panels = FAIL (never a skip).
//        [--index <index.json>]…  pair each --snap's CONTENT with a served .snapz (gunzip + sha256);
//                               without --index, <snap>.provenance.json (derive-raw.sh) is used;
//                               unpaired = FAIL unless [--allow-unpaired]
//        [--transport wasm|native]   native = stock `lean --server` + golden-env LEAN_PATH (control goldens only)
//        [--native-env w7|w8]  (default: --golden-env, else w7; dist-lens w8)
//        [--timeout-ms 300000]  [--min-free-gb 12]  [--out <json>]
// exit 0 = every check passed, 1 = some check failed, 2 = usage / setup / boot error.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { SC, W, BID, OUT_HEADLESS, DEFAULT_ARTIFACT, parseArgs, requirePairedArtifact, memoryGuard, acquireLock, headerImports, table, checkSnapProvenance } from './lib.mjs';
import { WasmLsp, NativeLsp } from './wasm-lsp.mjs';

const WHO = 'E3';
let o;
try { o = parseArgs(process.argv.slice(2), { multi: ['snap', 'index'], flags: ['allow-unpaired'] }); } catch (e) { console.error(e.message); process.exit(2); }
const transport = o.transport ?? 'wasm';
const example = o.example ? path.resolve(o.example) : o.pkg ? path.join(SC, 'lean/examples', `${o.pkg}.lean`) : null;
const specPath = o.spec ? path.resolve(o.spec) : example ? example.replace(/\.lean$/, '.json') : null;
if (!example || (transport === 'wasm' && (!o.snap?.length || !o.lib))) {
  console.error('usage: rpc-probe.mjs (--pkg <pkg> | --example <f.lean> [--spec f.json]) --snap <raw.snap>… --lib <tree> [--snapset s] [--expect-mode m] [--expect-missing A,B] [--golden-env w7|w8] [--golden f|none] [--golden-html f] [--index index.json]… [--allow-unpaired] [--transport wasm|native] [--native-env w7|w8] [--out f]');
  process.exit(2);
}
const name = o.pkg ?? path.basename(example, '.lean');
const snaps = (o.snap ?? []).map((s) => path.resolve(s));
const snapset = o.snapset ?? (transport === 'native' ? 'native' : snaps.map((s) => path.basename(s, '.snap')).join('+'));
const OUT = path.resolve(o.out ?? path.join(OUT_HEADLESS, `${name}.${snapset}.rpc.json`));
const HTML_OUT = OUT.replace(/\.rpc\.json$/, '') + '.html.json';
const TIMEOUT = Number(o['timeout-ms'] ?? (name === 'dist-lens' ? 900000 : 300000));
const t0 = Date.now();
const log = (...a) => console.log(`[${WHO} ${name}.${snapset} +${((Date.now() - t0) / 1000).toFixed(1)}s]`, ...a);

const spec = fs.existsSync(specPath) ? JSON.parse(fs.readFileSync(specPath, 'utf8')) : { cursors: [] };
const text = fs.readFileSync(example, 'utf8');
const hs = spec.headless ?? {};
const expectMode = o['expect-mode'] ?? hs.expectMode ?? 'covered';
const expectMissing = o['expect-missing'] != null ? o['expect-missing'].split(',').filter(Boolean) : hs.expectMissing ?? [];
const goldenEnv = o['golden-env'] ?? null;
if (goldenEnv && !['w7', 'w8'].includes(goldenEnv)) { console.error(`${WHO}: --golden-env must be w7 or w8`); process.exit(2); }
if (goldenEnv === 'w7' && o.pkg === 'dist-lens') { console.error(`${WHO}: dist-lens has no w7 golden (it exists only in the w8 bake)`); process.exit(2); }
const defaultGolden = (pkg, env) => (env === 'w8' && pkg !== 'dist-lens') ? path.join(SC, 'lean/expect/w8', `${pkg}.json`) : path.join(SC, 'lean/expect', `${pkg}.json`);
let goldenPath = o.golden === 'none' ? null : o.golden ? path.resolve(o.golden) : o.pkg ? defaultGolden(o.pkg, goldenEnv) : null;
if (goldenPath && !fs.existsSync(goldenPath)) { console.error(`${WHO}: golden ${goldenPath} not found`); process.exit(2); }
/** Golden Html dump next to a golden: lean/expect/[w8/]x.json -> lean/expect/html/[w8/]x.json; <x>.rpc.json -> <x>.html.json. */
function goldenHtmlPathFor(g) {
  if (o['golden-html']) return path.resolve(o['golden-html']);
  const EX = path.join(SC, 'lean/expect') + path.sep;
  if (g.startsWith(EX)) return path.join(SC, 'lean/expect/html', g.slice(EX.length));
  return g.replace(/\.rpc\.json$/, '').replace(/\.json$/, '') + '.html.json';
}
const nativeEnv = o['native-env'] ?? goldenEnv ?? (o.pkg === 'dist-lens' ? 'w8' : 'w7');

// ---------- text helpers (LSP positions are UTF-16 = JS string units) ----------
const lineStarts = (t) => { const s = [0]; for (let i = 0; i < t.length; i++) if (t[i] === '\n') s.push(i + 1); return s; };
const offsetOf = (t, p) => lineStarts(t)[p.line] + p.character;
const applyEdit = (t, r, newText) => t.slice(0, offsetOf(t, r.start)) + newText + t.slice(offsetOf(t, r.end));
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');
const big = (v) => (v && typeof v === 'object' && JSON.isRawJSON?.(v)) ? JSON.stringify(v) : String(v);

// ---------- Html / TaggedText walkers (verbatim from lsp-golden.mjs) ----------
function ttText(tt) {
  if (tt == null) return '';
  if ('text' in tt) return tt.text;
  if ('append' in tt) return tt.append.map(ttText).join('');
  if ('tag' in tt) {
    const [info, sub] = tt.tag;
    if (info && typeof info === 'object' && 'widget' in info) return ttText(info.widget.alt);
    if (info && typeof info === 'object' && 'expr' in info) return ttText(info.expr);
    return ttText(sub);
  }
  return '';
}
function htmlText(h) {
  if ('text' in h) return h.text;
  if ('element' in h) return h.element[2].map(htmlText).join('');
  if ('component' in h) {
    const [, , props, ch] = h.component;
    if (props?.fmt) return ttText(props.fmt);
    return ch.map(htmlText).join('');
  }
  return '';
}
function normRefs(v) {
  if (Array.isArray(v)) return v.map(normRefs);
  if (v && typeof v === 'object' && !JSON.isRawJSON(v)) {
    const ks = Object.keys(v);
    if (ks.length === 1 && ks[0] === 'p' && typeof v.p === 'string') return { p: '<rpc-ref>' };
    const out = {}; for (const k of ks) out[k] = normRefs(v[k]); return out;
  }
  return v;
}
/** Environment-independent Html hash: refs normalized (as the golden) AND every
 * `textDocument.{uri,version}` (MakeEditLink's WorkspaceEdit) and `mvarId` blanked. */
function normEnv(v) {
  if (Array.isArray(v)) return v.map(normEnv);
  if (v && typeof v === 'object' && !JSON.isRawJSON(v)) {
    const out = {};
    for (const [k, x] of Object.entries(v)) {
      if (k === 'textDocument' && x && typeof x === 'object') out[k] = { ...x, uri: '<uri>', version: '<version>' };
      else if (k === 'mvarId') out[k] = '<mvar>';
      else out[k] = normEnv(x);
    }
    return out;
  }
  return v;
}
const envSha = (normalizedHtml) => sha(JSON.stringify(normEnv(normalizedHtml)));
function signature(html) {
  const tagCounts = {}, svgTagCounts = {}, components = {}, texts = [], codeTexts = [], links = [];
  const walk = (h, inSvg) => {
    if ('text' in h) { if (h.text.trim()) texts.push(h.text); return; }
    if ('element' in h) {
      const [tag, , ch] = h.element; const svg = inSvg || tag === 'svg';
      tagCounts[tag] = (tagCounts[tag] ?? 0) + 1; if (svg) svgTagCounts[tag] = (svgTagCounts[tag] ?? 0) + 1;
      ch.forEach((c) => walk(c, svg)); return;
    }
    if ('component' in h) {
      const [, exp, props, ch] = h.component;
      const isEditLink = !!(props?.edit && Array.isArray(props.edit.edits));
      const label = isEditLink ? 'MakeEditLink' : props?.fmt ? 'InteractiveCode' : exp;
      components[label] = (components[label] ?? 0) + 1;
      if (props?.fmt) codeTexts.push(ttText(props.fmt));
      if (isEditLink) {
        const e = props.edit; const te = e?.edits?.[0];
        links.push({ kind: 'makeEditLink', linkText: ch.map(htmlText).join(''), title: props.title ?? null,
          edit: te ? { range: te.range, newText: te.newText } : null, editCount: e?.edits?.length ?? 0,
          documentVersion: e?.textDocument?.version ?? null, newSelection: props.newSelection ?? null });
      }
      ch.forEach((c) => walk(c, inSvg));
    }
  };
  walk(html, false);
  const sortObj = (x) => Object.fromEntries(Object.entries(x).sort(([a], [b]) => (a < b ? -1 : 1)));
  return { tagCounts: sortObj(tagCounts), svgTagCounts: sortObj(svgTagCounts), components: sortObj(components),
    texts, codeTexts, linkTexts: links.map((l) => l.linkText), links };
}
const SEV = { 1: 'error', 2: 'warning', 3: 'information', 4: 'hint' };
const diagView = (d) => ({ severity: SEV[d.severity ?? 1], line: d.range.start.line, character: d.range.start.character,
  endLine: d.range.end.line, message: d.message });
function checkDesigned(diags, declared) {
  const bad = diags.filter((d) => d.severity === 'error' || d.severity === 'warning');
  if (declared === 'clean') return { ok: bad.length === 0, problems: bad };
  const unmatched = [...bad]; const missing = [];
  for (const dd of declared) {
    const i = unmatched.findIndex((d) => d.severity === dd.severity && (dd.line == null || d.line === dd.line) &&
      (dd.contains == null || d.message.includes(dd.contains)));
    if (i < 0) missing.push(dd); else unmatched.splice(i, 1);
  }
  return { ok: missing.length === 0 && unmatched.length === 0, missing, unexpected: unmatched };
}

const checks = []; // own checks (header, provenance, declared expectations, gates)
const check = (ok, what, detail = '') => { checks.push({ ok: !!ok, what, detail: String(detail ?? '') }); return ok; };

// ---------- boot ----------
const runDir = path.join(W, 'headless', 'rpc', `${name}.${snapset}`);
fs.mkdirSync(runDir, { recursive: true }); fs.mkdirSync(path.join(W, 'logs'), { recursive: true });
let lsp, uri;
const artifact = path.resolve(o.artifact ?? DEFAULT_ARTIFACT);
const runInfo = { transport };
try {
  if (transport === 'wasm') {
    await requirePairedArtifact(artifact);
    for (const s of snaps) if (!fs.existsSync(s)) throw new Error(`snapshot ${s} not found`);
    // content provenance BEFORE the (≈10 GB) boot: a mismatched raw fails fast without booting
    runInfo.snapshotProvenance = await checkSnapProvenance(snaps, { indexes: (o.index ?? []).map((x) => path.resolve(x)), allowUnpaired: !!o['allow-unpaired'], check, log });
    if (runInfo.snapshotProvenance.some((r) => !r.ok && !r.allowedUnpaired)) {
      fs.mkdirSync(path.dirname(OUT), { recursive: true });
      fs.writeFileSync(OUT, JSON.stringify({ lane: 'E3', tool: 'scripts/headless/rpc-probe.mjs', package: name, snapset, generatedAt: new Date().toISOString(), run: runInfo, checks, ok: false }, null, 1) + '\n');
      table(['check', 'result', 'detail'], checks.map((c) => [c.what, c.ok ? 'PASS' : 'FAIL', c.detail]));
      console.log(`E3 FAIL ${name}.${snapset} (raw snapshot provenance; worker not booted) -> ${OUT}`); process.exit(1);
    }
    memoryGuard(Number(o['min-free-gb'] ?? 12), WHO);
    acquireLock(`${WHO} ${name}.${snapset}`);
    const wasmLog = path.join(W, 'logs', `e3-${name}.${snapset}.wasm.log`);
    log(`booting ${BID} from ${artifact}; lib ${o.lib}; snapshots ${snaps.map((s) => path.basename(s)).join(', ')}; wasm log ${wasmLog}`);
    lsp = await WasmLsp.boot({ artifact, lib: o.lib, snaps, log, wasmLog });
    uri = 'file:///workspace/Showcase.lean';
    Object.assign(runInfo, { buildId: BID, artifact, lib: path.resolve(o.lib), snapshots: lsp.loads, memory: lsp.memory, bootMs: lsp.timings.bootMs, wasmLog });
    for (const [i, ld] of lsp.loads.entries()) { // the bytes staged into wasm memory are the bytes that were paired
      const pv = runInfo.snapshotProvenance[i];
      check(ld.sha256 === pv.sha256 && ld.bytes === pv.bytes, `raw ${path.basename(ld.snap)}: bytes loaded into wasm == the verified file`, `${ld.sha256?.slice(0, 16)} vs ${pv.sha256.slice(0, 16)}`);
    }
  } else {
    const { TC } = await import(path.join(SC, 'scripts/lib/env.mjs')); // the stock v4.34.0 toolchain (LEAN_TOOLCHAIN_DIR)
    const leanPath = execFileSync(path.join(SC, 'lean/goldens/golden-env.sh'), ['path', nativeEnv]).toString().trim();
    fs.writeFileSync(path.join(runDir, 'Showcase.lean'), text);
    uri = 'file://' + path.join(runDir, 'Showcase.lean');
    lsp = new NativeLsp({ lean: `${TC}/bin/lean`, cwd: runDir, log, env: { ...process.env, LEAN_PATH: leanPath, LAKE: '/nonexistent/lake' } });
    Object.assign(runInfo, { toolchain: execFileSync(`${TC}/bin/lean`, ['--version']).toString().trim(), goldenEnv: nativeEnv, leanPath: leanPath.split(':') });
  }
} catch (e) { console.error(`${WHO}: setup failed: ${e.stack || e.message}`); process.exit(2); }

const finishAndExit = (code) => { process.exitCode = code; try { lsp.close(); } catch {} setTimeout(() => process.exit(code), 200); };
const budget = setTimeout(() => { console.error(`${WHO}: overall budget ${TIMEOUT * 4} ms exceeded`); process.exit(1); }, TIMEOUT * 4);
budget.unref();

let version = 1;
const initParams = { processId: null, rootUri: transport === 'native' ? 'file://' + runDir : null,
  capabilities: { textDocument: { publishDiagnostics: { relatedInformation: true } }, window: { workDoneProgress: false } },
  initializationOptions: { editDelay: 0, hasWidgets: true } };
await lsp.open(initParams, { uri, languageId: 'lean4', version, text });

/** Settle: waitForDiagnostics answered for `ver` AND fileProgress empty (or fatal) at ≥ ver.
 * A refused header never elaborates: resolve as soon as the refusal + fatal progress are in. */
async function settle(ver) {
  const ts = Date.now();
  let answered = false, settledMs = null; // settledMs: diagnostics answered + progress drained (100 ms polling), before the 300 ms grace
  lsp.request('textDocument/waitForDiagnostics', { uri, version: ver }, TIMEOUT).then(() => { answered = true; }, () => {});
  for (;;) {
    const p = lsp.progress.get(uri);
    const drained = p && p.textDocument.version >= ver && p.processing.every((q) => q.kind === 2);
    const fatal = p && p.textDocument.version >= ver && p.processing.some((q) => q.kind === 2);
    if (drained && (answered || (fatal && lsp.header?.mode === 'refused'))) { settledMs = Date.now() - ts; break; }
    if (lsp.dead) throw new Error(`server died while elaborating: ${lsp.dead}`);
    if (Date.now() - ts > TIMEOUT) throw new Error(`settle(v${ver}) timed out after ${TIMEOUT} ms (answered=${answered}, progress=${JSON.stringify(p?.processing ?? null)})`);
    await new Promise((r) => setTimeout(r, 100));
  }
  await new Promise((r) => setTimeout(r, 300));
  const d = lsp.diags.get(uri);
  return { ms: Date.now() - ts, settledMs, diagnostics: (d?.diagnostics ?? []).map(diagView), diagVersion: d?.version ?? null,
    fatalProgress: (lsp.progress.get(uri)?.processing ?? []).some((q) => q.kind === 2) };
}

const result = { lane: 'E3', tool: 'scripts/headless/rpc-probe.mjs', package: name, snapset, generatedAt: new Date().toISOString(),
  run: runInfo, example: path.relative(SC, example), spec: specPath && fs.existsSync(specPath) ? path.relative(SC, specPath) : null,
  exampleSha256: sha(text), header: headerImports(text).modules, uri, headerStatus: null, elaborationMs: null,
  documentDiagnostics: [], cursors: [], selections: [], hovers: [], clicks: [], checks, comparison: null };
const htmlDump = { package: name, mode: snapset, panels: [] };

let opened;
try { opened = await settle(version); } catch (e) {
  check(false, 'document settles', e.message); result.ok = false;
  fs.mkdirSync(path.dirname(OUT), { recursive: true }); fs.writeFileSync(OUT, JSON.stringify(result, null, 1) + '\n');
  table(['check', 'result', 'detail'], checks.map((c) => [c.what, c.ok ? 'PASS' : 'FAIL', c.detail]));
  console.log(`E3 FAIL ${name}.${snapset} -> ${OUT}`); finishAndExit(1); await new Promise(() => {});
}
result.elaborationMs = opened.ms; result.elaborationSettledMs = opened.settledMs; result.documentDiagnostics = opened.diagnostics;
log(`settled in ${opened.ms} ms; ${opened.diagnostics.length} diagnostics; header ${JSON.stringify(lsp.header)}`);

// ---------- header verdict ----------
if (transport === 'wasm') {
  result.headerStatus = lsp.header; result.headerHistory = lsp.headerHistory;
  const h = lsp.header;
  check(h != null, '$/qed64/headerStatus received', h ? JSON.stringify({ mode: h.mode, key: h.key, missing: h.missing, moduleCount: h.moduleCount }) : 'none');
  check(h?.mode === expectMode, `headerStatus.mode == ${expectMode}`, h?.mode);
  check(JSON.stringify([...(h?.missing ?? [])].sort()) === JSON.stringify([...expectMissing].sort()),
    `headerStatus.missing == ${JSON.stringify(expectMissing)}`, JSON.stringify(h?.missing));
}
if (expectMode === 'refused') {
  check(opened.fatalProgress, 'refused header: fileProgress carries the fatal entry (phase headerRefused)', opened.fatalProgress);
  check(opened.diagnostics.some((d) => d.severity === 'error'), 'refused header: an error diagnostic is published',
    opened.diagnostics.map((d) => d.message.slice(0, 100)).join(' | '));
  const sig = opened.diagnostics.map((d) => `${d.severity}@${d.line}: ${d.message.replace(/\n/g, ' ⏎ ').slice(0, 140)}`);
  log('diagnostics:', sig.join(' || '));
} else {
  check(!opened.diagnostics.some((d) => d.severity === 'error'), 'document elaborates with zero errors',
    opened.diagnostics.filter((d) => d.severity === 'error').map((d) => `L${d.line}: ${d.message.slice(0, 100)}`).join(' | '));
}

// ---------- RPC ----------
let rpc = null, keepAlive = null;
if (expectMode !== 'refused' && !lsp.dead) {
  const { sessionId } = await lsp.request('$/lean/rpc/connect', { uri });
  keepAlive = setInterval(() => lsp.notify('$/lean/rpc/keepAlive', { uri, sessionId }), 5000);
  rpc = (method, params, position, timeoutMs = TIMEOUT) =>
    lsp.request('$/lean/rpc/call', { textDocument: { uri }, position, sessionId, method, params }, timeoutMs);
  check(true, '$/lean/rpc/connect answered', `sessionId ${big(sessionId)}`);
}
const sourceCache = new Map();
async function widgetSource(hash, pos) {
  const k = big(hash); if (sourceCache.has(k)) return sourceCache.get(k);
  const s = (await rpc('Lean.Widget.getWidgetSource', { hash, pos }, pos)).sourcetext; sourceCache.set(k, s); return s;
}
async function panelsAt(pos, selectedLocations = []) {
  // timings (measurement only, never compared): what the InfoView waits for on a cursor move
  const tGw = Date.now();
  const gw = await rpc('Lean.Widget.getWidgets', pos, pos);
  const getWidgetsMs = Date.now() - tGw;
  const goals = await rpc('Lean.Widget.getInteractiveGoals', { textDocument: { uri }, position: pos }, pos);
  const termGoal = await rpc('Lean.Widget.getInteractiveTermGoal', { textDocument: { uri }, position: pos }, pos);
  const goalsMs = Date.now() - tGw - getWidgetsMs;
  const out = [];
  for (const wi of gw.widgets) {
    let js = '', jsError = null;
    const tJs = Date.now();
    try { js = await widgetSource(wi.javascriptHash, pos); } catch (e) { jsError = e.message; }
    const jsMs = Date.now() - tJs;
    const jsCheck = { bytes: js.length, sha256: sha(js), importsInfoview: js.includes('@leanprover/infoview'), error: jsError };
    const m = /const m="([^"]+)",g='(true|false)'/.exec(js);
    let kind, method = null, html = null, error = null;
    const t1 = Date.now();
    if (wi.id === 'ProofWidgets.HtmlDisplayPanel') { kind = 'static'; html = wi.props.html; }
    else if (m) {
      kind = 'rpc'; method = m[1];
      const props = { pos, goals: goals ? goals.goals : [], ...(termGoal ? { termGoal } : {}), selectedLocations, ...wi.props };
      try {
        if (m[2] === 'true') {
          const reqId = await rpc(method, props, pos);
          for (;;) {
            const r = await rpc('ProofWidgets.checkRequest', reqId, pos);
            if (r !== 'running') { html = r.done.result; break; }
            await new Promise((res) => setTimeout(res, 100));
          }
        } else html = await rpc(method, props, pos);
      } catch (e) { error = e.message; }
    } else kind = 'other';
    const sig = html ? signature(html) : null;
    const nh = html ? normRefs(html) : null;
    out.push({ id: wi.id, kind, method, range: wi.range ?? null, name: wi.name ?? null,
      panelTitle: kind === 'static' ? 'HTML Display' : null, firstText: sig?.texts[0] ?? null, js: jsCheck, jsMs, rpcMs: Date.now() - t1, error,
      ...(sig ?? {}), htmlSha256: nh ? sha(JSON.stringify(nh)) : null, htmlEnvSha256: nh ? envSha(nh) : null, _html: nh, _raw: html });
  }
  return { panels: out, goals, timing: { getWidgetsMs, goalsMs } };
}
async function tryThisLinks(line) {
  const pos = { line, character: 0 };
  const ds = await rpc('Lean.Widget.getInteractiveDiagnostics', { lineRange: { start: line, end: line + 1 } }, pos);
  const links = [];
  const walk = (tt, d) => {
    if (tt == null) return;
    if ('append' in tt) return tt.append.forEach((x) => walk(x, d));
    if ('tag' in tt) {
      const [info, sub] = tt.tag;
      if (info?.widget) {
        const wi = info.widget.wi; const p = wi.props;
        if (wi.id === 'Lean.Meta.Hint.textInsertionWidget' || wi.id === 'Lean.Meta.Hint.tryThisDiffWidget') {
          links.push({ kind: 'tryThis', widgetId: wi.id, linkText: p.acceptSuggestionProps?.linkText ?? ttText(info.widget.alt),
            suggestion: p.suggestion, edit: { range: p.range, newText: p.suggestion }, diagnosticLine: d.range.start.line, message: ttText(d.message) });
        }
        return walk(info.widget.alt, d);
      }
      return walk(sub, d);
    }
  };
  for (const d of ds) walk(d.message, d);
  return links;
}
const strip = ({ _html, _raw, ...p }) => p;
const lines = text.split('\n');
function locate(c, after = 0) {
  if (c.line != null) {
    if (!lines[c.line]?.includes(c.command)) throw new Error(`cursor line ${c.line} does not contain ${JSON.stringify(c.command)}: ${JSON.stringify(lines[c.line])}`);
    return c;
  }
  const i = lines.findIndex((l, k) => k >= after && l.trimStart().startsWith(c.command));
  if (i < 0) throw new Error(`command not found: ${c.command}`);
  c.line = i; c.character = lines[i].length - lines[i].trimStart().length; return c;
}

if (rpc) {
  let after = 0;
  for (const c of spec.cursors ?? []) {
    locate(c, after); after = c.line + 1;
    const pos = { line: c.line, character: c.character };
    const tCur = Date.now();
    const { panels, timing } = await panelsAt(pos);
    const cursorMs = Date.now() - tCur;
    result.cursors.push({ line: c.line, character: c.character, command: c.command, cursorMs, ...timing, panels: panels.map(strip) });
    panels.forEach((p, i) => htmlDump.panels.push({ line: c.line, index: i, id: p.id, html: p._html }));
    const e = c.expect ?? {};
    const all = panels.filter((p) => !p.error);
    check(panels.length > 0, `cursor ${c.line} (${c.command}): ≥1 panel widget`, panels.map((p) => p.id).join(', '));
    check(panels.length > 0 && panels.every((p) => p.js.bytes > 0 && p.js.importsInfoview && !p.js.error),
      `cursor ${c.line}: every panel's JS retrievable (getWidgetSource, imports @leanprover/infoview)`, panels.map((p) => `${p.js.bytes}B`).join(', '));
    check(panels.every((p) => !p.error && (p.kind !== 'rpc' || p._raw)), `cursor ${c.line}: every panel RPC answered`,
      panels.map((p) => p.kind === 'rpc' ? `${p.method}: ${p.error ?? `ok ${p.rpcMs} ms`}` : p.kind).join(', '));
    const texts = all.flatMap((p) => [...(p.texts ?? []), ...(p.codeTexts ?? [])]).join('\n');
    for (const t of e.texts ?? []) check(texts.includes(t), `cursor ${c.line}: text ${JSON.stringify(t)} present`);
    const lts = all.flatMap((p) => p.linkTexts ?? []);
    for (const t of e.linkTexts ?? []) check(lts.includes(t), `cursor ${c.line}: link ${JSON.stringify(t)} present`);
    if (e.panelTitle) check(all.some((p) => p.panelTitle === e.panelTitle || p.firstText?.includes(e.panelTitle)), `cursor ${c.line}: panel title ${e.panelTitle}`);
    for (const [tag, n] of Object.entries(e.svgTagCounts ?? {}))
      check(all.some((p) => (p.svgTagCounts?.[tag] ?? 0) === n), `cursor ${c.line}: svg <${tag}> × ${n}`);
    if (e.method) check(all.some((p) => p.method === e.method), `cursor ${c.line}: panel method ${e.method}`, all.map((p) => p.method).join(', '));
    log(`cursor ${c.line} ${c.command.slice(0, 40)}: ${panels.map((p) => `${p.kind}:${p.id}${p.error ? ' ERROR ' + p.error : ''} links=${p.links?.length ?? 0}`).join(', ')}`);
  }

  for (const s of spec.selections ?? []) {
    locate(s);
    const pos = { line: s.line, character: s.character };
    const goals = await rpc('Lean.Widget.getInteractiveGoals', { textDocument: { uri }, position: pos }, pos);
    const locs = [];
    for (const sel of s.select) {
      const g = goals.goals[sel.goal ?? 0];
      if (sel.hyp) {
        const h = g.hyps.find((x) => x.names.includes(sel.hyp));
        locs.push({ mvarId: g.mvarId, loc: { hyp: h.fvarIds[h.names.indexOf(sel.hyp)] } });
      } else if (sel.target) {
        const found = [];
        const walk = (tt) => { if (!tt) return; if ('append' in tt) tt.append.forEach(walk);
          if ('tag' in tt) { const [info, sub] = tt.tag; const tx = ttText(sub); if (tx === sel.target || tx === `(${sel.target})`) found.push(info.subexprPos); walk(sub); } };
        walk(g.type);
        const p = found[sel.occurrence ?? 0];
        if (p == null) throw new Error(`selection target not found: ${sel.target} (found ${found.length})`);
        locs.push({ mvarId: g.mvarId, loc: { target: p } });
      }
    }
    const { panels } = await panelsAt(pos, locs);
    result.selections.push({ line: s.line, character: s.character, command: s.command, select: s.select, selectedLocations: locs, panels: panels.map(strip) });
    panels.forEach((p, i) => htmlDump.panels.push({ line: s.line, selection: s.select, index: i, id: p.id, html: p._html }));
    const texts = panels.flatMap((p) => [...(p.texts ?? []), ...(p.codeTexts ?? [])]).join('\n');
    // a selection text may be a run of consecutive leaves (e.g. a section caption + the first tree row): the same rule as
    // lean/goldens/lsp-golden.mjs (which the spec's selection texts are authored against since 2026-10-01 03:25),
    // scripts/build-gallery.mjs selectExpectation and tests/ux/bringup/hints.mjs: leaves concatenated, whitespace removed
    const sq = (x) => String(x).replace(/\s+/g, '');
    const run = sq(panels.flatMap((p) => [...(p.texts ?? []), ...(p.codeTexts ?? [])]).join(''));
    for (const t of s.expect?.texts ?? []) check(texts.includes(t) || run.includes(sq(t)), `selection @${s.line} ${JSON.stringify(s.select)}: text ${JSON.stringify(t)}`);
    for (const t of s.expect?.linkTexts ?? []) check(panels.flatMap((p) => p.linkTexts ?? []).includes(t), `selection @${s.line}: link ${JSON.stringify(t)} present`);
    check(panels.length > 0 && panels.every((p) => !p.error), `selection @${s.line}: panels answered`, panels.map((p) => p.error ?? p.firstText).join(' | '));
    log(`selection ${s.line} ${JSON.stringify(s.select)}: ${panels.map((p) => p.firstText).join(' | ')}`);
  }

  for (const h of spec.hovers ?? []) {
    const cur = result.cursors.find((c) => c.line === h.cursorLine);
    const pos = { line: cur.line, character: cur.character };
    const { panels } = await panelsAt(pos);
    const codes = [];
    const walkH = (x) => { if ('element' in x) x.element[2].forEach(walkH);
      if ('component' in x) { const [, , props, ch] = x.component; if (props?.fmt) codes.push(props.fmt); ch.forEach(walkH); } };
    walkH(panels[h.panel ?? 0]._raw);
    const tags = [];
    const walkT = (tt) => { if (!tt) return; if ('append' in tt) tt.append.forEach(walkT);
      if ('tag' in tt) { const [info, sub] = tt.tag; if (ttText(sub) === h.tagText) tags.push(info); walkT(sub); } };
    walkT(codes[h.code ?? 0]);
    if (!tags.length) { check(false, `hover @${h.cursorLine} code#${h.code ?? 0} ${JSON.stringify(h.tagText)}: tag found`); continue; }
    const r = await rpc('Lean.Widget.InteractiveDiagnostics.infoToInteractive', tags[0].info, pos);
    const typeText = r?.type ? ttText(r.type) : null;
    result.hovers.push({ cursorLine: h.cursorLine, panel: h.panel ?? 0, code: h.code ?? 0, tagText: h.tagText,
      codeText: ttText(codes[h.code ?? 0]), subexprPos: tags[0].subexprPos ?? null, typeText,
      exprExplicitText: r?.exprExplicit ? ttText(r.exprExplicit) : null, doc: r?.doc ?? null });
    if (h.expect?.typeText) check(typeText === h.expect.typeText, `hover @${h.cursorLine} ${JSON.stringify(h.tagText)}: type ${JSON.stringify(h.expect.typeText)}`, typeText);
    log(`hover @${h.cursorLine} ${JSON.stringify(h.tagText)} : ${typeText}`);
  }

  for (const k of spec.clicks ?? []) {
    let link;
    if (k.kind === 'makeEditLink') {
      const src = k.selection != null ? result.selections[k.selection] : result.cursors.find((c) => c.line === k.cursorLine);
      if (!src) throw new Error(`click: no ${k.selection != null ? `selection #${k.selection}` : `cursor at line ${k.cursorLine}`}`);
      link = src.panels.flatMap((p) => p.links ?? []).find((l) => (k.linkTitle != null ? l.title === k.linkTitle : l.linkText === k.linkText));
    } else {
      link = (await tryThisLinks(k.cursorLine)).find((l) => l.linkText === k.linkText && (k.suggestion == null || l.suggestion === k.suggestion));
    }
    const label = `click @${k.cursorLine ?? `sel#${k.selection}`} ${k.kind} ${JSON.stringify(k.linkTitle ?? k.linkText)}`;
    if (!check(!!link, `${label}: link found`)) continue;
    if (k.expectedEdit) check(JSON.stringify(link.edit) === JSON.stringify(k.expectedEdit), `${label}: edit equals the declared expectedEdit`, JSON.stringify(link.edit));
    const edited = applyEdit(text, link.edit.range, link.edit.newText);
    lsp.notify('textDocument/didChange', { textDocument: { uri, version: ++version }, contentChanges: [{ text: edited }] });
    const afterC = await settle(version);
    check(afterC.diagVersion === version, `${label}: diagnostics are for the edited version ${version}`, afterC.diagVersion);
    const verdict = checkDesigned(afterC.diagnostics, k.postClickDiagnostics ?? 'clean');
    check(verdict.ok, `${label}: post-click diagnostics ${JSON.stringify(k.postClickDiagnostics ?? 'clean')}`, verdict.ok ? `${afterC.ms} ms` : JSON.stringify(verdict).slice(0, 200));
    const tag = `click${result.clicks.length + 1}`;
    fs.writeFileSync(path.join(runDir, `Showcase.${tag}.lean`), edited);
    result.clicks.push({ cursorLine: k.cursorLine ?? null, selection: k.selection ?? null, kind: k.kind, linkText: link.linkText, linkTitle: link.title ?? null,
      ...(link.suggestion ? { suggestion: link.suggestion } : {}), edit: link.edit, documentVersionInEdit: link.documentVersion ?? null,
      newSelection: link.newSelection ?? null, editedSha256: sha(edited), editedFile: path.join(runDir, `Showcase.${tag}.lean`),
      diagnosticsVersion: afterC.diagVersion, reElaborationMs: afterC.ms, settledMs: afterC.settledMs, postClickDiagnostics: afterC.diagnostics, verdict });
    log(`${label} -> ${verdict.ok ? 'OK' : 'FAIL ' + JSON.stringify(verdict).slice(0, 300)} (${afterC.ms} ms)`);
    lsp.notify('textDocument/didChange', { textDocument: { uri, version: ++version }, contentChanges: [{ text }] });
    await settle(version);
  }
}
// ---------- code actions (the lightbulb; spec codeActions[], same logic as lsp-golden.mjs) ----------
result.codeActions = [];
if (rpc) {
  for (const ca of spec.codeActions ?? []) {
    const range = ca.range ?? { start: { line: ca.line, character: ca.character }, end: { line: ca.line, character: ca.character } };
    const all = lsp.diags.get(uri)?.diagnostics ?? [];
    const overl = all.filter((d) => !(d.range.end.line < range.start.line || d.range.start.line > range.end.line));
    const tCa = Date.now();
    let acts = null, caError = null;
    try { acts = await lsp.request('textDocument/codeAction', { textDocument: { uri }, range, context: { diagnostics: overl } }, TIMEOUT); }
    catch (e) { caError = e.message; }
    const actions = [];
    for (let a of acts ?? []) {
      let resolved = false;
      if (!a.edit && a.data !== undefined) { a = await lsp.request('codeAction/resolve', a, TIMEOUT); resolved = true; }
      const ch = a.edit?.documentChanges?.[0]?.edits ?? a.edit?.changes?.[uri] ?? [];
      actions.push({ title: a.title, kind: a.kind ?? null, isPreferred: a.isPreferred ?? null, lazy: resolved,
        edits: ch.map((e) => ({ range: e.range, newText: e.newText })), documentVersion: a.edit?.documentChanges?.[0]?.textDocument?.version ?? null });
    }
    const entry = { line: range.start.line, character: range.start.character, range, actions, codeActionMs: Date.now() - tCa, error: caError };
    const label = `code action @${range.start.line}:${range.start.character}`;
    check(!caError && acts != null, `${label}: textDocument/codeAction answered`, caError ?? `${actions.length} action(s), ${entry.codeActionMs} ms`);
    if (ca.sameEditAsClick != null) {
      const k = spec.clicks[ca.sameEditAsClick];
      const live = (await tryThisLinks(k.cursorLine)).filter((l) => l.linkText === k.linkText).map((l) => JSON.stringify(l.edit));
      const hit = actions.find((a) => a.edits.length === 1 && live.includes(JSON.stringify(a.edits[0])));
      entry.sameEditAsClick = ca.sameEditAsClick; entry.matchingTitle = hit?.title ?? null;
      check(!!hit, `${label}: an action's edit equals the rendered Try-this link edit of click #${ca.sameEditAsClick}`, hit?.title ?? actions.map((a) => a.title).join(' | '));
    }
    for (const t of ca.expect?.titles ?? []) check(actions.some((a) => a.title.includes(t)), `${label}: title contains ${JSON.stringify(t)}`);
    result.codeActions.push(entry);
    log(`${label}: ${actions.map((a) => `${JSON.stringify(a.title)}${a.lazy ? ' (resolved)' : ''} edits=${a.edits.length}`).join(', ') || 'none'} (${entry.codeActionMs} ms)`);
  }
}
if (keepAlive) clearInterval(keepAlive);
if (transport === 'wasm') {
  check(!lsp.dead, 'worker alive at the end (no exit/abort)', lsp.dead ?? 'alive');
  result.run.frameStats = lsp.frameStats;
  result.run.serverRequests = [...new Set(lsp.serverRequests)];
  check((lsp.frameStats?.junkBytes ?? 0) === 0, 'no non-frame stdout bytes (decoder junk)', JSON.stringify(lsp.frameStats));
}
result.run.maxRssBytes = process.resourceUsage().maxRSS * 1024;

// ---------- compare with the native golden ----------
const cmp = [];
const cmpCheck = (ok, what, detail = '') => cmp.push({ ok: !!ok, what, detail: String(detail ?? '') });
const J = (x) => JSON.stringify(x);
const dKey = (d) => `${d.severity}@${d.line}:${d.character}-${d.endLine} ${d.message}`;
function diffList(a, b) { const A = a.map(dKey), B = b.map(dKey); return { onlyHere: A.filter((x) => !B.includes(x)), onlyGolden: B.filter((x) => !A.includes(x)) }; }
function comparePanels(where, mine, gold, mineHtml, goldHtml) {
  cmpCheck(mine.length === gold.length && mine.every((p, i) => p.id === gold[i]?.id), `${where}: panel ids`, `${mine.map((p) => p.id).join(',')} vs ${gold.map((p) => p.id).join(',')}`);
  gold.forEach((g, i) => {
    const m = mine[i]; if (!m || m.id !== g.id) return;
    const w = `${where} panel ${i} ${g.id}`;
    cmpCheck(m.kind === g.kind && m.method === g.method, `${w}: kind/method`, `${m.kind}/${m.method}`);
    cmpCheck(m.js.sha256 === g.js.sha256 && m.js.bytes === g.js.bytes, `${w}: widget JS identical`, `${m.js.bytes}B ${m.js.sha256.slice(0, 12)} vs ${g.js.bytes}B ${g.js.sha256.slice(0, 12)}`);
    cmpCheck(!m.error && !g.error, `${w}: RPC answered (both)`, m.error ?? g.error ?? '');
    for (const f of ['tagCounts', 'svgTagCounts', 'components', 'texts', 'codeTexts', 'linkTexts'])
      cmpCheck(J(m[f]) === J(g[f]), `${w}: ${f}`, J(m[f]) === J(g[f]) ? '' : `${J(m[f])?.slice(0, 120)} vs ${J(g[f])?.slice(0, 120)}`);
    const lk = (l) => J({ linkText: l.linkText, title: l.title, edit: l.edit, editCount: l.editCount, newSelection: l.newSelection }); // documentVersion ignored
    cmpCheck(J((m.links ?? []).map(lk)) === J((g.links ?? []).map(lk)), `${w}: links (text, title, edit, newSelection; uri/version ignored)`, `${m.links?.length ?? 0} vs ${g.links?.length ?? 0}`);
    if (!g.components?.MakeEditLink) cmpCheck(m.htmlSha256 === g.htmlSha256, `${w}: htmlSha256`, `${m.htmlSha256?.slice(0, 12)} vs ${g.htmlSha256?.slice(0, 12)}`);
    else { // never skipped: a MakeEditLink panel without its golden Html is a FAIL
      const gs = goldHtml?.[i] ? envSha(goldHtml[i]) : null;
      cmpCheck(gs != null && m.htmlEnvSha256 === gs, `${w}: Html hash with MakeEditLink uri/version normalized`,
        gs == null ? (goldHtml ? `golden Html dump has no panel ${i} here` : 'golden Html dump missing') : `${m.htmlEnvSha256?.slice(0, 12)} vs ${gs.slice(0, 12)}`);
    }
  });
}
if (goldenPath) {
  const golden = JSON.parse(fs.readFileSync(goldenPath, 'utf8'));
  const ghPath = goldenHtmlPathFor(goldenPath);
  const gh = fs.existsSync(ghPath) ? JSON.parse(fs.readFileSync(ghPath, 'utf8')) : null;
  const allGoldPanels = [...(golden.cursors ?? []), ...(golden.selections ?? [])].flatMap((x) => x.panels ?? []);
  const nMel = allGoldPanels.filter((p) => p.components?.MakeEditLink).length;
  cmpCheck(gh || nMel === 0, `golden Html dump present (${nMel} MakeEditLink panel(s) need it)`, gh ? path.relative(SC, ghPath) : `missing: ${ghPath}`);
  const gEnv = golden.environment?.golden ?? null; // lsp-golden.mjs goldens record w7|w8; ad-hoc rpc.json goldens record run.goldenEnv
  const gEnvAny = gEnv ?? golden.run?.goldenEnv ?? null;
  if (goldenEnv) cmpCheck(gEnvAny === goldenEnv, `golden environment == --golden-env ${goldenEnv}`, gEnvAny);
  const bakeTag = [...new Set(snaps.map((s) => /-(w[78])\//.exec(s)?.[1] ?? /widgets([78])\.snap$/.exec(s)?.[1]?.replace(/^/, 'w')).filter(Boolean))];
  if (gEnvAny && bakeTag.length) cmpCheck(bakeTag.length === 1 && bakeTag[0] === gEnvAny, `golden environment matches the bake under test`, `golden ${gEnvAny} vs snapshot ${bakeTag.join(',')}`);
  const ghFor = (line, selection) => gh ? gh.panels.filter((p) => p.line === line && J(p.selection ?? null) === J(selection ?? null)).sort((a, b) => a.index - b.index).map((p) => p.html) : null;
  const mhFor = (line, selection) => htmlDump.panels.filter((p) => p.line === line && J(p.selection ?? null) === J(selection ?? null)).map((p) => p.html);
  cmpCheck(golden.exampleSha256 === result.exampleSha256, 'same example text as the golden', `${result.exampleSha256.slice(0, 12)} vs ${golden.exampleSha256?.slice(0, 12)}`);
  const dd = diffList(result.documentDiagnostics, golden.documentDiagnostics ?? []);
  cmpCheck(!dd.onlyHere.length && !dd.onlyGolden.length, 'document diagnostics identical', J(dd).slice(0, 300));
  for (const gc of golden.cursors ?? []) {
    const mc = result.cursors.find((c) => c.line === gc.line && c.character === gc.character);
    if (!mc) { cmpCheck(false, `cursor ${gc.line}: probed`); continue; }
    comparePanels(`cursor ${gc.line}`, mc.panels, gc.panels, mhFor(gc.line), ghFor(gc.line));
  }
  for (const gs of golden.selections ?? []) {
    const ms = result.selections.find((s) => s.line === gs.line && J(s.select) === J(gs.select));
    if (!ms) { cmpCheck(false, `selection @${gs.line}: probed`); continue; }
    const locs = (x) => J(x.selectedLocations.map((l) => ({ ...l, mvarId: '<mvar>', loc: l.loc.hyp ? { hyp: '<fvar>' } : l.loc }))); // mvarIds/fvarIds ignored
    cmpCheck(locs(ms) === locs(gs), `selection @${gs.line}: selected locations (mvarIds ignored)`, locs(ms));
    comparePanels(`sel @${gs.line} [${gs.select.map((x) => x.hyp ?? x.target).join(', ')}]`, ms.panels, gs.panels, mhFor(gs.line, gs.select), ghFor(gs.line, gs.select));
  }
  for (const gv of golden.hovers ?? []) {
    const mv = result.hovers.find((h) => h.cursorLine === gv.cursorLine && h.tagText === gv.tagText);
    cmpCheck(mv && mv.typeText === gv.typeText && mv.codeText === gv.codeText, `hover @${gv.cursorLine} ${J(gv.tagText)}: type/code text`, mv ? `${mv.typeText} vs ${gv.typeText}` : 'missing');
  }
  for (const [i, gk] of (golden.clicks ?? []).entries()) {
    const mk = result.clicks[i];
    const w = `click ${i + 1} ${gk.kind} ${J(gk.linkTitle ?? gk.linkText)}`;
    if (!mk) { cmpCheck(false, `${w}: performed`); continue; }
    cmpCheck(mk.linkText === gk.linkText && J(mk.edit) === J(gk.edit), `${w}: same link and edit`, J(mk.edit).slice(0, 120));
    cmpCheck(mk.editedSha256 === gk.editedSha256, `${w}: edited text identical`);
    cmpCheck(mk.verdict.ok && gk.verdict?.ok, `${w}: post-click verdict ok (both)`);
    const cd = diffList(mk.postClickDiagnostics, gk.postClickDiagnostics ?? []);
    cmpCheck(!cd.onlyHere.length && !cd.onlyGolden.length, `${w}: post-click diagnostics identical`, J(cd).slice(0, 300));
  }
  for (const [i, gc] of (golden.codeActions ?? []).entries()) {
    const mc = result.codeActions.find((c) => c.line === gc.line && c.character === gc.character);
    const w = `code action ${i + 1} @${gc.line}:${gc.character}`;
    if (!mc) { cmpCheck(false, `${w}: requested`); continue; }
    const ak = (a) => J({ title: a.title, kind: a.kind, isPreferred: a.isPreferred, lazy: a.lazy, edits: a.edits }); // documentVersion ignored
    cmpCheck(J(mc.actions.map(ak)) === J(gc.actions.map(ak)), `${w}: actions (title, kind, edits; documentVersion ignored)`,
      `${mc.actions.map((a) => a.title).join(' | ').slice(0, 120)} vs ${gc.actions.map((a) => a.title).join(' | ').slice(0, 120)}`);
    if (gc.sameEditAsClick != null) cmpCheck(mc.matchingTitle != null && mc.matchingTitle === gc.matchingTitle, `${w}: same action matches click #${gc.sameEditAsClick} (both)`, `${J(mc.matchingTitle)} vs ${J(gc.matchingTitle)}`);
  }
  if (golden.ok === false) cmpCheck(false, 'golden itself was green', J(golden.failures));
  result.comparison = { golden: path.relative(SC, goldenPath), goldenEnv: gEnvAny, goldenHtml: gh ? path.relative(SC, ghPath) : null, goldenHtmlLooked: path.relative(SC, ghPath),
    ignored: ['MakeEditLink edit.textDocument.uri/version (env-dependent)', 'raw htmlSha256 of panels containing MakeEditLink (a uri/version-normalized Html hash is compared instead)', 'selection mvarIds/fvarIds', 'code action edit documentVersion', 'timings'],
    ok: cmp.every((c) => c.ok), checks: cmp };
}

// ---------- write + report ----------
result.ok = checks.every((c) => c.ok) && (!result.comparison || result.comparison.ok);
result.totalMs = Date.now() - t0;
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(result, null, 1) + '\n');
fs.writeFileSync(HTML_OUT, JSON.stringify(htmlDump) + '\n');
console.log(`\n== ${name}.${snapset}: probe checks ==`);
table(['check', 'result', 'detail'], checks.map((c) => [c.what, c.ok ? 'PASS' : 'FAIL', c.detail.replace(/\n/g, ' ⏎ ')]));
if (result.comparison) {
  console.log(`\n== ${name}.${snapset}: vs golden ${result.comparison.golden} ==`);
  table(['check', 'result', 'detail'], cmp.map((c) => [c.what, c.ok ? 'PASS' : 'FAIL', c.detail.replace(/\n/g, ' ⏎ ')]));
} else console.log(`(no golden comparison${goldenPath ? '' : ': --golden none / no lean/expect file'})`);
const nOk = checks.filter((c) => c.ok).length + cmp.filter((c) => c.ok).length;
console.log(`[${WHO}] max RSS ${(result.run.maxRssBytes / 1e9).toFixed(2)} GB; total ${result.totalMs} ms`);
console.log(`E3 ${result.ok ? 'PASS' : 'FAIL'} ${name}.${snapset} (${nOk}/${checks.length + cmp.length} checks) -> ${OUT}`);
finishAndExit(result.ok ? 0 : 1);
