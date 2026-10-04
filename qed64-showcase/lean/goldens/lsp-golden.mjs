#!/usr/bin/env node
// Golden generator for the QED64 widget showcase examples.
//
// Drives the STOCK native Lean v4.34.0 language server (`lean --server`) over
// LSP exactly the way the InfoView drives QED64's wasm worker:
//   didOpen(example text) -> waitForDiagnostics -> $/lean/rpc/connect ->
//   per cursor: Lean.Widget.getWidgets, getInteractiveGoals/TermGoal,
//   getWidgetSource (JS must be non-empty and import @leanprover/infoview),
//   HtmlDisplayPanel props.html as-is, or the mk_rpc_widget% panel's own
//   @[server_rpc_method] called with the InfoView's panel props
//   {pos, goals, termGoal, selectedLocations, ...stored props}
//   (incl. the ProofWidgets cancellable protocol) -> Html JSON.
// Clicks: the MakeEditLink edit (props.edit.edits[0]) / core "Try this"
// textInsertionWidget edit ({range, newText: suggestion}) is applied UTF-16
// correctly, sent as a full-text didChange, and the resulting diagnostics are
// compared with the example's declared `postClickDiagnostics`.
//
// Environments (--mode):
//   superset : LEAN_PATH starts with the shadow `Mathlib.olean` umbrella built
//              by golden-env.sh (QED64.Essential module list + the bake's
//              package roots), so the UNMODIFIED browser header resolves to
//              the same module set as QED64's covered region.  -> the goldens.
//   closure  : `import Mathlib` blanked, LEAN_PATH = the package's own
//              `lake env` path (package closure only).  -> sensitivity check.
//
// Code actions: every spec `codeActions[]` entry issues textDocument/codeAction
// (+ codeAction/resolve for Lean's lazy actions) at the given range and records
// the action's title and WorkspaceEdit; `sameEditAsClick` asserts it equals that
// declared click's edit (the lightbulb does what the link does).
//
// --click-all: enumerate EVERY panel the InfoView can show (getWidgets probed at
// the start of every token of every line, plus the declared cursors/selections),
// collect EVERY MakeEditLink in their Html and EVERY core Try-this link in the
// document's interactive diagnostics, apply each (deduplicated by exact edit) to
// a fresh copy of the example, re-elaborate (full-text didChange) and classify:
//   clean    = no error/warning after re-elaboration
//   designed = matches a declared click whose postClickDiagnostics lists exactly them
//   broken   = anything else.
// Writes lean/expect/click-all/<pkg>.json; exit 1 iff any link is broken (or none found
// where the goldens rendered some).
//
// Usage: node lsp-golden.mjs --pkg <pkg> [--mode superset|closure]
//          [--env w7|w8] [--update-spec] [--click-all] [--out <file>]
import { spawn, execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const SC = path.resolve(import.meta.dirname, '..', '..');
const { W, TC } = await import(path.join(SC, 'scripts/lib/env.mjs')); // work dir (QED64_SHOWCASE_WORK), stock toolchain (LEAN_TOOLCHAIN_DIR)
const LEAN = `${TC}/bin/lean`;
const ENV_SH = path.join(SC, 'lean/goldens/golden-env.sh');

// ---------- args ----------
const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const flag = (k) => argv.includes(k);
const PKG = opt('--pkg');
const MODE = opt('--mode', 'superset');
const UPDATE_SPEC = flag('--update-spec');
// --click-all: click EVERY rendered MakeEditLink / Try-this link (not only the declared
// clicks) on a fresh copy of the example, re-elaborate, classify clean/designed/broken.
const CLICK_ALL = flag('--click-all');
if (!PKG) { console.error('--pkg required'); process.exit(2); }
const EXAMPLE = path.join(SC, 'lean/examples', `${PKG}.lean`);
const SPEC_PATH = path.join(SC, 'lean/examples', `${PKG}.json`);
// Golden environment: w7 (phase-1 bake: Essential + 7 roots) or w8 (phase-2 bake: + DistLens).
// Primary env = w7 for the 7 phase-1 packages, w8 for dist-lens (which does not exist in w7).
// Phase-1 packages are ALSO frozen in w8 (the phase-2 bake serves all eight) under expect/w8/.
const PRIMARY_ENV = PKG === 'dist-lens' ? 'w8' : 'w7';
const ENV = opt('--env', PRIMARY_ENV);
if (!['w7', 'w8'].includes(ENV) || (PKG === 'dist-lens' && ENV !== 'w8')) { console.error(`bad --env ${ENV} for ${PKG}`); process.exit(2); }
const ENV_SUB = ENV === PRIMARY_ENV ? '' : `${ENV}/`; // non-primary env outputs live in a subdirectory
const OUT = opt('--out', CLICK_ALL ? path.join(SC, 'lean/expect/click-all', `${ENV_SUB}${PKG}${MODE === 'superset' ? '' : '.' + MODE}.json`)
  : MODE === 'superset' ? path.join(SC, 'lean/expect', `${ENV_SUB}${PKG}.json`)
  : path.join(W, 'goldens', `${PKG}.closure.json`));
const HTML_OUT = MODE === 'superset'
  ? path.join(SC, 'lean/expect/html', `${ENV_SUB}${PKG}.json`)
  : path.join(W, 'goldens', `${PKG}.closure.html.json`);
const ELAB_TIMEOUT_MS = Number(opt('--timeout-ms', PKG === 'dist-lens' ? 900000 : 300000));
const log = (...a) => console.log(`[${PKG}/${MODE}${MODE === 'superset' ? '/' + ENV : ''}]`, ...a);

// ---------- JSON with lossless UInt64 (sessionId, javascriptHash) ----------
const parseJson = (s) => JSON.parse(s, (k, v, ctx) =>
  (typeof v === 'number' && Number.isInteger(v) && !Number.isSafeInteger(v)) ? JSON.rawJSON(ctx.source) : v);
const big = (v) => (v && typeof v === 'object' && JSON.isRawJSON?.(v)) ? JSON.stringify(v) : String(v);

// ---------- text helpers (LSP positions are UTF-16 = JS string units) ----------
const lineStarts = (t) => { const s = [0]; for (let i = 0; i < t.length; i++) if (t[i] === '\n') s.push(i + 1); return s; };
const offsetOf = (t, p) => lineStarts(t)[p.line] + p.character;
const applyEdit = (t, r, newText) => t.slice(0, offsetOf(t, r.start)) + newText + t.slice(offsetOf(t, r.end));
const sha = (s) => crypto.createHash('sha256').update(s).digest('hex');

// ---------- LSP client ----------
class Lsp {
  constructor(env, cwd) {
    this.proc = spawn(LEAN, ['--server'], { env, cwd, stdio: ['pipe', 'pipe', 'pipe'] });
    this.buf = Buffer.alloc(0); this.id = 0; this.pending = new Map();
    this.diags = new Map(); this.progress = new Map(); this.stderr = '';
    this.proc.stdout.on('data', (d) => this.onData(d));
    this.proc.stderr.on('data', (d) => { this.stderr += d.toString(); });
    this.proc.on('exit', (c, s) => { this.exited = { c, s }; for (const p of this.pending.values()) p.reject(new Error(`server exited ${c} ${s}`)); });
  }
  send(msg) {
    const body = Buffer.from(JSON.stringify({ jsonrpc: '2.0', ...msg }), 'utf8');
    this.proc.stdin.write(`Content-Length: ${body.length}\r\n\r\n`); this.proc.stdin.write(body);
  }
  onData(d) {
    this.buf = Buffer.concat([this.buf, d]);
    for (;;) {
      const h = this.buf.indexOf('\r\n\r\n'); if (h < 0) return;
      const m = /Content-Length: (\d+)/i.exec(this.buf.slice(0, h).toString()); const n = Number(m[1]);
      if (this.buf.length < h + 4 + n) return;
      const msg = parseJson(this.buf.slice(h + 4, h + 4 + n).toString('utf8'));
      this.buf = this.buf.slice(h + 4 + n); this.dispatch(msg);
    }
  }
  dispatch(msg) {
    if (msg.id !== undefined && msg.method) { this.send({ id: msg.id, result: null }); return; } // server->client request
    if (msg.id !== undefined) {
      const p = this.pending.get(msg.id); if (!p) return; this.pending.delete(msg.id);
      msg.error ? p.reject(Object.assign(new Error(`${p.method}: ${msg.error.message}`), { lsp: msg.error })) : p.resolve(msg.result);
      return;
    }
    if (msg.method === 'textDocument/publishDiagnostics') this.diags.set(msg.params.uri, msg.params);
    if (msg.method === '$/lean/fileProgress') this.progress.set(msg.params.textDocument.uri, msg.params);
    if (process.env.LSP_DEBUG && msg.method) console.error('<-', msg.method, JSON.stringify(msg.params).slice(0, 300));
  }
  request(method, params, timeoutMs = 600000) {
    const id = ++this.id;
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => { this.pending.delete(id); reject(new Error(`timeout ${method}`)); }, timeoutMs);
      this.pending.set(id, { method, resolve: (v) => { clearTimeout(t); resolve(v); }, reject: (e) => { clearTimeout(t); reject(e); } });
      this.send({ id, method, params });
    });
  }
  notify(method, params) { this.send({ method, params }); }
}

// ---------- Html / TaggedText walkers ----------
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
    const [, exp, props, ch] = h.component;
    if (props?.fmt) return ttText(props.fmt); // InteractiveCode (ProofWidgets exports it as `default`)
    return ch.map(htmlText).join('');
  }
  return '';
}
// Replace RPC refs ({"p": "..."}) by a stable marker so dumps are reproducible.
function normRefs(v) {
  if (Array.isArray(v)) return v.map(normRefs);
  if (v && typeof v === 'object' && !JSON.isRawJSON(v)) {
    const ks = Object.keys(v);
    if (ks.length === 1 && ks[0] === 'p' && typeof v.p === 'string') return { p: '<rpc-ref>' };
    const o = {}; for (const k of ks) o[k] = normRefs(v[k]); return o;
  }
  return v;
}
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
      // ProofWidgets exports its components as `default`; identify them by props shape.
      const isEditLink = !!(props?.edit && Array.isArray(props.edit.edits));
      const label = isEditLink ? 'MakeEditLink' : props?.fmt ? 'InteractiveCode' : exp;
      components[label] = (components[label] ?? 0) + 1;
      if (props?.fmt) codeTexts.push(ttText(props.fmt)); // InteractiveCode: rendered expression text
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
  const sortObj = (o) => Object.fromEntries(Object.entries(o).sort(([a], [b]) => a < b ? -1 : 1));
  return { tagCounts: sortObj(tagCounts), svgTagCounts: sortObj(svgTagCounts), components: sortObj(components),
    texts, codeTexts, linkTexts: links.map((l) => l.linkText), links };
}

// ---------- diagnostics ----------
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

// ---------- main ----------
const spec = JSON.parse(fs.readFileSync(SPEC_PATH, 'utf8'));
let text = fs.readFileSync(EXAMPLE, 'utf8');
if (!/^import Mathlib\n/.test(text)) throw new Error('example must start with `import Mathlib`');
let leanPath;
if (MODE === 'superset') {
  leanPath = execFileSync(ENV_SH, ['path', ENV]).toString().trim();
} else {
  leanPath = execFileSync(ENV_SH, ['closure', PKG]).toString().trim();
  text = text.replace(/^import Mathlib\n/, '\n'); // keep line numbering identical
}
const runDir = path.join(W, 'golden-run', `${PKG}-${MODE}${MODE === 'superset' && ENV !== PRIMARY_ENV ? '-' + ENV : ''}${CLICK_ALL ? '-clickall' : ''}`);
fs.mkdirSync(runDir, { recursive: true });
const docPath = path.join(runDir, 'Showcase.lean');
fs.writeFileSync(docPath, text);
const uri = 'file://' + docPath;
const env = { ...process.env, LEAN_PATH: leanPath, LAKE: '/nonexistent/lake' }; // no lakefile, no lake: LEAN_PATH rules
const lsp = new Lsp(env, runDir);
const t0 = Date.now();
await lsp.request('initialize', { processId: process.pid, rootUri: 'file://' + runDir, capabilities: {
  textDocument: { publishDiagnostics: { relatedInformation: true } }, window: { workDoneProgress: false } },
  initializationOptions: { editDelay: 0, hasWidgets: true } });
lsp.notify('initialized', {});
let version = 1;
lsp.notify('textDocument/didOpen', { textDocument: { uri, languageId: 'lean4', version, text } });

async function settle(ver) {
  const ts = Date.now();
  await lsp.request('textDocument/waitForDiagnostics', { uri, version: ver }, ELAB_TIMEOUT_MS);
  for (;;) { // also wait for the file-progress bar to be empty
    const p = lsp.progress.get(uri);
    if (p && p.textDocument.version >= ver && p.processing.every((q) => q.kind === 2)) break; // kind 2 = fatal error marker
    if (Date.now() - ts > ELAB_TIMEOUT_MS) throw new Error('fileProgress never emptied');
    await new Promise((r) => setTimeout(r, 100));
  }
  await new Promise((r) => setTimeout(r, 300));
  const d = lsp.diags.get(uri);
  return { ms: Date.now() - ts, diagnostics: (d?.diagnostics ?? []).map(diagView), diagVersion: d?.version ?? null };
}

const opened = await settle(version);
log(`elaborated in ${opened.ms} ms; ${opened.diagnostics.length} diagnostics`);
const { sessionId } = await lsp.request('$/lean/rpc/connect', { uri });
const keepAlive = setInterval(() => lsp.notify('$/lean/rpc/keepAlive', { uri, sessionId }), 5000);
const rpc = (method, params, position, timeoutMs) =>
  lsp.request('$/lean/rpc/call', { textDocument: { uri }, position, sessionId, method, params }, timeoutMs);

const sourceCache = new Map();
async function widgetSource(hash, pos) {
  const k = big(hash); if (sourceCache.has(k)) return sourceCache.get(k);
  const s = (await rpc('Lean.Widget.getWidgetSource', { hash, pos }, pos)).sourcetext; sourceCache.set(k, s); return s;
}

// Render every panel widget the InfoView would show at `pos`.
async function panelsAt(pos, selectedLocations = []) {
  const gw = await rpc('Lean.Widget.getWidgets', pos, pos);
  const goals = await rpc('Lean.Widget.getInteractiveGoals', { textDocument: { uri }, position: pos }, pos);
  const termGoal = await rpc('Lean.Widget.getInteractiveTermGoal', { textDocument: { uri }, position: pos }, pos);
  const out = [];
  for (const wi of gw.widgets) {
    const js = await widgetSource(wi.javascriptHash, pos);
    const jsCheck = { bytes: js.length, sha256: sha(js), importsInfoview: js.includes('@leanprover/infoview') };
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
    out.push({ id: wi.id, kind, method, range: wi.range ?? null, name: wi.name ?? null,
      panelTitle: kind === 'static' ? 'HTML Display' : null,
      firstText: sig?.texts[0] ?? null, js: jsCheck, rpcMs: Date.now() - t1, error,
      ...(sig ?? {}), htmlSha256: html ? sha(JSON.stringify(normRefs(html))) : null, _html: html ? normRefs(html) : null, _raw: html });
  }
  return { panels: out, goals };
}

// "Try this" links from interactive diagnostics (core textInsertionWidget).
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
            suggestion: p.suggestion, edit: { range: p.range, newText: p.suggestion },
            diagnosticLine: d.range.start.line, message: ttText(d.message) });
        }
        return walk(info.widget.alt, d);
      }
      return walk(sub, d);
    }
  };
  for (const d of ds) walk(d.message, d);
  return links;
}

const lines = text.split('\n');
const result = { package: PKG, mode: MODE, generatedAt: new Date().toISOString(), generator: 'lean/goldens/lsp-golden.mjs',
  toolchain: execFileSync(LEAN, ['--version']).toString().trim(),
  environment: MODE === 'superset'
    ? { header: text.split('\n').slice(0, 2), golden: ENV, resolvesTo: `shadow Mathlib umbrella ${ENV} = QED64.Essential (4354) + bake roots${ENV === 'w8' ? ' incl. DistLens' : ''}`, leanPath: leanPath.split(':') }
    : { header: ['', text.split('\n')[1]], resolvesTo: 'package closure only', leanPath: leanPath.split(':') },
  exampleSha256: sha(fs.readFileSync(EXAMPLE, 'utf8')), documentSha256: sha(text),
  elaborationMs: opened.ms, documentDiagnostics: opened.diagnostics, cursors: [], selections: [], clicks: [], declaredChecks: [] };
const htmlDump = { package: PKG, mode: MODE, panels: [] };
const failures = [];
const check = (ok, what) => { result.declaredChecks.push({ ok, what }); if (!ok) failures.push(what); };

// pre-click document must be error-free (warnings are listed)
check(!opened.diagnostics.some((d) => d.severity === 'error'), 'document elaborates with zero errors');

// resolve / verify cursor positions
function locate(c, after = 0) {
  if (c.line != null) {
    if (!lines[c.line]?.includes(c.command)) throw new Error(`cursor line ${c.line} does not contain ${JSON.stringify(c.command)}: ${JSON.stringify(lines[c.line])}`);
    return c;
  }
  const i = lines.findIndex((l, k) => k >= after && l.trimStart().startsWith(c.command));
  if (i < 0) throw new Error(`command not found: ${c.command}`);
  c.line = i; c.character = lines[i].length - lines[i].trimStart().length; return c;
}
let after = 0;
for (const c of spec.cursors) {
  locate(c, after); after = c.line + 1;
  const pos = { line: c.line, character: c.character };
  const { panels } = await panelsAt(pos);
  const entry = { line: c.line, character: c.character, command: c.command,
    panels: panels.map(({ _html, _raw, ...p }) => p) };
  result.cursors.push(entry);
  panels.forEach((p, i) => htmlDump.panels.push({ line: c.line, index: i, id: p.id, html: p._html }));
  const e = c.expect ?? {};
  const all = panels.filter((p) => !p.error);
  check(panels.length > 0 && panels.every((p) => !p.error && p.js.bytes > 0 && p.js.importsInfoview),
    `cursor ${c.line} (${c.command}): ≥1 panel, every panel JS retrievable (+@leanprover/infoview) and every RPC answered`);
  const texts = all.flatMap((p) => [...p.texts, ...p.codeTexts]).join('\n');
  for (const t of e.texts ?? []) check(texts.includes(t), `cursor ${c.line}: text ${JSON.stringify(t)} present`);
  const lts = all.flatMap((p) => p.linkTexts);
  for (const t of e.linkTexts ?? []) check(lts.includes(t), `cursor ${c.line}: link ${JSON.stringify(t)} present`);
  if (e.panelTitle) check(all.some((p) => p.panelTitle === e.panelTitle || p.firstText?.includes(e.panelTitle)), `cursor ${c.line}: panel title ${e.panelTitle}`);
  for (const [tag, n] of Object.entries(e.svgTagCounts ?? {}))
    check(all.some((p) => (p.svgTagCounts[tag] ?? 0) === n), `cursor ${c.line}: svg <${tag}> × ${n}`);
  log(`cursor ${c.line} ${c.command.slice(0, 40)}: ${panels.map((p) => `${p.kind}:${p.id}${p.error ? ' ERROR ' + p.error : ''} links=${p.links?.length ?? 0}`).join(', ')}`);
}

// selections (shift-click in the goal view)
for (const s of spec.selections ?? []) {
  locate(s);
  const pos = { line: s.line, character: s.character };
  const goals = await rpc('Lean.Widget.getInteractiveGoals', { textDocument: { uri }, position: pos }, pos);
  const locs = [];
  for (const sel of s.select) {
    const g = goals.goals[sel.goal ?? 0];
    if (sel.hyp) {
      const h = g.hyps.find((h) => h.names.includes(sel.hyp));
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
  result.selections.push({ line: s.line, character: s.character, command: s.command, select: s.select, selectedLocations: locs,
    panels: panels.map(({ _html, _raw, ...p }) => p) });
  panels.forEach((p, i) => htmlDump.panels.push({ line: s.line, selection: s.select, index: i, id: p.id, html: p._html }));
  const texts = panels.flatMap((p) => [...(p.texts ?? []), ...(p.codeTexts ?? [])]).join('\n');
  // a selection text may be a run of consecutive leaves (e.g. a section caption + the first tree row): matched like
  // scripts/build-gallery.mjs selectExpectation and tests/ux/bringup/hints.mjs, leaves concatenated, whitespace removed
  const sq = (x) => String(x).replace(/\s+/g, '');
  const run = sq(panels.flatMap((p) => [...(p.texts ?? []), ...(p.codeTexts ?? [])]).join(''));
  for (const t of s.expect?.texts ?? []) check(texts.includes(t) || run.includes(sq(t)), `selection @${s.line} ${JSON.stringify(s.select)}: text ${JSON.stringify(t)}`);
  check(panels.length > 0 && panels.every((p) => !p.error), `selection @${s.line}: panels answered`);
  log(`selection ${s.line} ${JSON.stringify(s.select)}: ${panels.map((p) => p.firstText).join(' | ')}`);
}

// hovers: what the InfoView's InteractiveCode popup asks the server for
// (Lean.Widget.InteractiveDiagnostics.infoToInteractive on the tag's info ref)
result.hovers = [];
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
  if (h.expect?.typeText) check(typeText === h.expect.typeText, `hover @${h.cursorLine} ${JSON.stringify(h.tagText)}: type ${JSON.stringify(h.expect.typeText)} (got ${JSON.stringify(typeText)})`);
  log(`hover @${h.cursorLine} ${JSON.stringify(h.tagText)} : ${typeText}`);
}

// code actions (the lightbulb): textDocument/codeAction (+ codeAction/resolve)
result.codeActions = [];
async function codeActionsAt(range) {
  const all = lsp.diags.get(uri)?.diagnostics ?? [];
  const overl = all.filter((d) => !(d.range.end.line < range.start.line || d.range.start.line > range.end.line));
  const acts = await lsp.request('textDocument/codeAction', { textDocument: { uri }, range, context: { diagnostics: overl } });
  const out = [];
  for (let a of acts ?? []) {
    let resolved = false;
    if (!a.edit && a.data !== undefined) { a = await lsp.request('codeAction/resolve', a); resolved = true; }
    const ch = a.edit?.documentChanges?.[0]?.edits ?? a.edit?.changes?.[uri] ?? [];
    out.push({ title: a.title, kind: a.kind ?? null, isPreferred: a.isPreferred ?? null, lazy: resolved,
      edits: ch.map((e) => ({ range: e.range, newText: e.newText })),
      documentVersion: a.edit?.documentChanges?.[0]?.textDocument?.version ?? null });
  }
  return out;
}
for (const ca of spec.codeActions ?? []) {
  const range = ca.range ?? { start: { line: ca.line, character: ca.character }, end: { line: ca.line, character: ca.character } };
  const actions = await codeActionsAt(range);
  const entry = { line: range.start.line, character: range.start.character, range, actions };
  if (ca.sameEditAsClick != null) {
    // the lightbulb must offer exactly the edit the rendered Try-this link applies in THIS run
    // (closure env: the minimal call differs), and in the superset env that is the frozen expectedEdit
    const k = spec.clicks[ca.sameEditAsClick];
    const live = (await tryThisLinks(k.cursorLine)).filter((l) => l.linkText === k.linkText).map((l) => JSON.stringify(l.edit));
    const hit = actions.find((a) => a.edits.length === 1 && live.includes(JSON.stringify(a.edits[0])));
    entry.sameEditAsClick = ca.sameEditAsClick; entry.matchingTitle = hit?.title ?? null;
    entry.equalsFrozenExpectedEdit = !!hit && JSON.stringify(hit.edits[0]) === JSON.stringify(k.expectedEdit);
    check(!!hit, `code action @${range.start.line}:${range.start.character}: an action's edit equals the rendered Try-this link edit of click #${ca.sameEditAsClick}`);
    if (MODE === 'superset') check(entry.equalsFrozenExpectedEdit, `code action @${range.start.line}:${range.start.character}: edit equals click #${ca.sameEditAsClick} frozen expectedEdit`);
  }
  for (const t of ca.expect?.titles ?? []) check(actions.some((a) => a.title.includes(t)), `code action @${range.start.line}: title contains ${JSON.stringify(t)}`);
  result.codeActions.push(entry);
  log(`codeAction @${range.start.line}:${range.start.character}: ${actions.map((a) => `${JSON.stringify(a.title)}${a.lazy ? ' (resolved)' : ''} edits=${a.edits.length}`).join(', ') || 'none'}`);
}

// ---------- --click-all ----------
if (CLICK_ALL) {
  const ca = { package: PKG, mode: MODE, generatedAt: new Date().toISOString(), generator: 'lean/goldens/lsp-golden.mjs --click-all',
    toolchain: result.toolchain, environment: result.environment, exampleSha256: result.exampleSha256,
    documentDiagnostics: opened.diagnostics, probes: 0, panelsRendered: 0, links: [], counts: {} };
  // 1. every panel at every token start of every line (+ declared cursors and selections)
  const seenPanel = new Set(); const found = new Map(); // edit-key -> link record
  const addLink = (l, where) => {
    const key = JSON.stringify([l.edit.range, l.edit.newText]);
    if (!found.has(key)) found.set(key, { kind: l.kind, linkText: l.linkText, title: l.title ?? null, edit: l.edit,
      ...(l.suggestion ? { suggestion: l.suggestion } : {}), ...(l.newSelection ? { newSelection: l.newSelection } : {}), foundAt: [] });
    const r = found.get(key);
    if (!r.foundAt.some((w) => JSON.stringify(w) === JSON.stringify(where))) r.foundAt.push(where);
  };
  const positions = [];
  lines.forEach((l, i) => { const re = /\S+/g; let m; while ((m = re.exec(l))) positions.push({ line: i, character: m.index }); });
  for (const c of spec.cursors) positions.push({ line: c.line, character: c.character });
  for (const pos of positions) {
    ca.probes++;
    const gw = await rpc('Lean.Widget.getWidgets', pos, pos);
    if (!gw.widgets.length) continue;
    const goals = await rpc('Lean.Widget.getInteractiveGoals', { textDocument: { uri }, position: pos }, pos);
    const gkey = JSON.stringify((goals?.goals ?? []).map((g) => [ttText(g.type), g.hyps.map((h) => [h.names, ttText(h.type)])]));
    const keys = gw.widgets.map((wi) => JSON.stringify([wi.id, wi.range ?? null, normRefs(wi.props), wi.id === 'ProofWidgets.HtmlDisplayPanel' ? '' : gkey]));
    if (keys.every((k) => seenPanel.has(k))) continue;
    const { panels } = await panelsAt(pos);
    panels.forEach((p, i) => {
      if (seenPanel.has(keys[i])) return; seenPanel.add(keys[i]); ca.panelsRendered++;
      if (p.error) { ca.panelErrors = [...(ca.panelErrors ?? []), { pos, id: p.id, error: p.error }]; return; }
      for (const l of p.links ?? []) addLink(l, { line: pos.line, character: pos.character, panel: p.id });
    });
  }
  for (const sel of result.selections) {
    const pos = { line: sel.line, character: sel.character };
    const { panels } = await panelsAt(pos, sel.selectedLocations);
    ca.panelsRendered += panels.length;
    for (const p of panels) for (const l of p.links ?? []) addLink(l, { line: pos.line, character: pos.character, panel: p.id, selection: sel.select });
  }
  // 2. every core Try-this link in the document's messages
  {
    const ds = await rpc('Lean.Widget.getInteractiveDiagnostics', { lineRange: { start: 0, end: lines.length + 1 } }, { line: 0, character: 0 });
    const lineSet = [...new Set(ds.map((d) => d.range.start.line))];
    for (const ln of lineSet) for (const l of await tryThisLinks(ln)) addLink(l, { line: l.diagnosticLine, message: l.message.slice(0, 120) });
  }
  // 3. click each on a fresh copy
  const declared = (spec.clicks ?? []).map((k) => ({ k, key: k.expectedEdit ? JSON.stringify([k.expectedEdit.range, k.expectedEdit.newText]) : null }));
  for (const f of fs.readdirSync(runDir)) if (/^Showcase\.link\d+\.lean$/.test(f)) fs.rmSync(path.join(runDir, f)); // no stale files
  let n = 0;
  for (const [key, link] of found) {
    n++;
    const edited = applyEdit(text, link.edit.range, link.edit.newText);
    const f = path.join(runDir, `Showcase.link${n}.lean`); fs.writeFileSync(f, edited);
    lsp.notify('textDocument/didChange', { textDocument: { uri, version: ++version }, contentChanges: [{ text: edited }] });
    const after = await settle(version);
    const bad = after.diagnostics.filter((d) => d.severity === 'error' || d.severity === 'warning');
    const dec = declared.find((d) => d.key === key);
    let cls;
    if (after.diagVersion !== version) cls = 'broken';
    else if (bad.length === 0) cls = 'clean';
    else if (dec && dec.k.postClickDiagnostics && dec.k.postClickDiagnostics !== 'clean' && checkDesigned(after.diagnostics, dec.k.postClickDiagnostics).ok) cls = 'designed';
    else cls = 'broken';
    ca.links.push({ n, ...link, declaredClick: dec ? declared.indexOf(dec) : null, classification: cls,
      diagnosticsVersion: after.diagVersion, editedVersion: version, reElaborationMs: after.ms,
      errorsWarnings: bad, infoCount: after.diagnostics.length - bad.length, editedSha256: sha(edited), editedFile: f });
    log(`link ${n}/${found.size} ${link.kind} ${JSON.stringify((link.linkText || link.title || '').slice(0, 50))} @${link.foundAt[0].line} -> ${cls}${bad.length ? ' ' + JSON.stringify(bad.map((d) => `${d.severity}@${d.line}: ${d.message.slice(0, 80)}`)) : ''} (${after.ms} ms)`);
  }
  for (const l of ca.links) ca.counts[l.classification] = (ca.counts[l.classification] ?? 0) + 1;
  ca.counts.total = ca.links.length;
  ca.counts.makeEditLink = ca.links.filter((l) => l.kind === 'makeEditLink').length;
  ca.counts.tryThis = ca.links.filter((l) => l.kind === 'tryThis').length;
  ca.counts.linkOccurrences = ca.links.reduce((s, l) => s + l.foundAt.length, 0);
  ca.declaredClicksCovered = declared.filter((d) => ca.links.some((l) => l.declaredClick === declared.indexOf(d))).length + '/' + declared.length;
  ca.ok = !ca.panelErrors && (ca.counts.broken ?? 0) === 0 && !opened.diagnostics.some((d) => d.severity === 'error' || d.severity === 'warning')
    && declared.every((d) => ca.links.some((l) => l.declaredClick === declared.indexOf(d)));
  ca.totalMs = Date.now() - t0;
  clearInterval(keepAlive);
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify(ca, null, 1) + '\n');
  try { await lsp.request('shutdown', null, 10000); lsp.notify('exit', null); } catch {}
  setTimeout(() => lsp.proc.kill('SIGKILL'), 2000).unref();
  log(`CLICK-ALL ${ca.ok ? 'PASS' : 'FAIL'} — ${JSON.stringify(ca.counts)}; panels ${ca.panelsRendered}; probes ${ca.probes}; declared clicks covered ${ca.declaredClicksCovered}; wrote ${OUT}`);
  process.exitCode = ca.ok ? 0 : 1;
} else {

// clicks
for (const k of spec.clicks ?? []) {
  const cur = result.cursors.find((c) => c.line === k.cursorLine);
  let link;
  if (k.kind === 'makeEditLink') {
    if (!cur) throw new Error(`click cursorLine ${k.cursorLine} is not a declared cursor`);
    // edge links have no text (an SVG <line>): they are identified by their `title`
    link = cur.panels.flatMap((p) => p.links ?? []).find((l) =>
      k.linkTitle != null ? l.title === k.linkTitle : l.linkText === k.linkText);
  } else {
    link = (await tryThisLinks(k.cursorLine)).find((l) => l.linkText === k.linkText && (k.suggestion == null || l.suggestion === k.suggestion));
  }
  if (!link) { check(false, `click @${k.cursorLine} ${k.kind} ${JSON.stringify(k.linkTitle ?? k.linkText)}: link found`); continue; }
  let editMatchesSpec = null;
  if (MODE === 'superset') {
    if (k.expectedEdit == null || (UPDATE_SPEC && ENV === PRIMARY_ENV)) k.expectedEdit = link.edit;
    check(JSON.stringify(link.edit) === JSON.stringify(k.expectedEdit), `click @${k.cursorLine} ${JSON.stringify(k.linkText)}: edit equals the declared expectedEdit`);
  } else editMatchesSpec = JSON.stringify(link.edit) === JSON.stringify(k.expectedEdit); // closure env: recorded, not enforced
  const edited = applyEdit(text, link.edit.range, link.edit.newText);
  const tag = `click${result.clicks.length + 1}`;
  fs.writeFileSync(path.join(runDir, `Showcase.${tag}.lean`), edited);
  lsp.notify('textDocument/didChange', { textDocument: { uri, version: ++version }, contentChanges: [{ text: edited }] });
  const after = await settle(version);
  check(after.diagVersion === version, `click @${k.cursorLine}: diagnostics are for the edited version ${version} (got ${after.diagVersion})`);
  const verdict = checkDesigned(after.diagnostics, k.postClickDiagnostics ?? 'clean');
  check(verdict.ok, `click @${k.cursorLine} ${JSON.stringify(k.linkText)}: post-click diagnostics ${JSON.stringify(k.postClickDiagnostics ?? 'clean')}`);
  result.clicks.push({ cursorLine: k.cursorLine, kind: k.kind, linkText: link.linkText, linkTitle: link.title ?? null, ...(link.suggestion ? { suggestion: link.suggestion } : {}),
    edit: link.edit, ...(editMatchesSpec === null ? {} : { editMatchesSupersetGolden: editMatchesSpec }), documentVersionInEdit: link.documentVersion ?? null, newSelection: link.newSelection ?? null,
    editedSha256: sha(edited), editedFile: path.join(runDir, `Showcase.${tag}.lean`), diagnosticsVersion: after.diagVersion, reElaborationMs: after.ms, postClickDiagnostics: after.diagnostics, verdict });
  log(`click @${k.cursorLine} ${JSON.stringify(k.linkText)} -> ${verdict.ok ? 'OK' : 'FAIL ' + JSON.stringify(verdict)} (${after.ms} ms)`);
  // revert
  lsp.notify('textDocument/didChange', { textDocument: { uri, version: ++version }, contentChanges: [{ text }] });
  await settle(version);
}

clearInterval(keepAlive);
result.ok = failures.length === 0; result.failures = failures;
result.totalMs = Date.now() - t0;
fs.mkdirSync(path.dirname(OUT), { recursive: true }); fs.mkdirSync(path.dirname(HTML_OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(result, null, 1) + '\n');
fs.writeFileSync(HTML_OUT, JSON.stringify(htmlDump) + '\n');
if (UPDATE_SPEC && MODE === 'superset' && ENV === PRIMARY_ENV && !CLICK_ALL) {
  const ord = (o, first) => Object.fromEntries([...first.filter((k) => k in o).map((k) => [k, o[k]]), ...Object.entries(o).filter(([k]) => !first.includes(k))]);
  spec.cursors = spec.cursors.map((c) => ord(c, ['line', 'character', 'command', 'expect']));
  if (spec.selections) spec.selections = spec.selections.map((c) => ord(c, ['line', 'character', 'command', 'select', 'expect']));
  if (spec.clicks) spec.clicks = spec.clicks.map((c) => ord(c, ['cursorLine', 'linkText', 'linkTitle', 'kind', 'suggestion', 'expectedEdit', 'postClickDiagnostics']));
  fs.writeFileSync(SPEC_PATH, JSON.stringify(spec, null, 2) + '\n');
}
try { await lsp.request('shutdown', null, 10000); lsp.notify('exit', null); } catch {}
setTimeout(() => lsp.proc.kill('SIGKILL'), 2000).unref();
log(`${result.ok ? 'PASS' : 'FAIL'} — ${result.declaredChecks.filter((c) => c.ok).length}/${result.declaredChecks.length} checks; wrote ${OUT}`);
if (!result.ok) for (const f of failures) log('  FAILED:', f);
process.exitCode = result.ok ? 0 : 1;
} // end !CLICK_ALL
