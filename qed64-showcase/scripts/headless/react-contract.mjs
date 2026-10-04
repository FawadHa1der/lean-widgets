#!/usr/bin/env node
// E3b (BUILD-PLAN §6): the React contract for wasm-produced panels.
//
// A parameterised copy of widgets-v4.34/showcase/verify.mjs (sha256 9a28f527…):
// every panel's Html tree is rendered through React 18.3.1 DEVELOPMENT server
// rendering (the vendored UMD builds, cloned into vendor/react and checked
// against vendor/react/SHA256SUMS, loaded in a vm sandbox — no npm), and ANY
// React error or warning on ANY panel fails (string style props throw #62,
// invalid DOM properties warn, …). Element/text/component conversion is
// verify.mjs's toElement, unchanged; RPC-wire Html (`{element:[tag,attrs,ch]}`,
// `{text}`, `{component:[hash,export,props,ch]}`) is first mapped to the dump
// schema (`{t:"el",tag,attrs,children}`, `{t:"text",s}`, `{t:"comp",name,props,children}`)
// exactly as showcase/probes/*.lean's probeHtmlJson does.
//
// usage:
//   node scripts/headless/react-contract.mjs --in <file> [--in <file> …] [--out <json>] [--allow-empty]
//   node scripts/headless/react-contract.mjs --self-test
// <file> is any of: out/headless/<name>.<snapset>.html.json (rpc-probe), lean/expect/html/<pkg>.json
// (native goldens; same schema), or a showcase dump (widgets-v4.34/showcase/dumps/<pkg>.json).
// exit 0 = every panel clean, 1 = some panel failed (or nothing to check), 2 = usage error.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import { SC, OUT_HEADLESS, parseArgs, table } from './lib.mjs';

let o;
try { o = parseArgs(process.argv.slice(2), { flags: ['allow-empty', 'self-test'], multi: ['in'] }); } catch (e) { console.error(e.message); process.exit(2); }
if (!o.in?.length && !o['self-test']) { console.error('usage: react-contract.mjs --in <html.json>… [--out json] [--allow-empty] | --self-test'); process.exit(2); }
const REACT_DIR = path.resolve(o['react-dir'] ?? path.join(SC, 'vendor/react'));

// ---- vendored React, integrity-checked ----
for (const line of fs.readFileSync(path.join(REACT_DIR, 'SHA256SUMS'), 'utf8').trim().split('\n')) {
  const [want, f] = line.split(/\s+/);
  const got = crypto.createHash('sha256').update(fs.readFileSync(path.join(REACT_DIR, f))).digest('hex');
  if (got !== want) { console.error(`react-contract: ${f} sha256 ${got} != ${want}`); process.exit(2); }
}
function loadUmd(file, requireMap) { // verify.mjs, verbatim apart from the directory
  const code = fs.readFileSync(path.join(REACT_DIR, file), 'utf8');
  const module = { exports: {} };
  const sandbox = { module, exports: module.exports,
    require: (name) => { if (requireMap[name]) return requireMap[name]; throw new Error('unexpected require: ' + name); }, console, process };
  vm.runInNewContext(code, sandbox, { filename: file });
  return module.exports;
}
const React = loadUmd('react.development.js', {});
const ReactDOMServer = loadUmd('react-dom-server.development.js', { react: React });
if (React.version !== '18.3.1') {
  console.error(`react-contract: unexpected React ${React.version}`); process.exit(2);
}

// ---- conversion ----
function wireToDump(h) { // RPC-wire Html -> showcase dump schema (probeHtmlJson)
  if (h == null) return null;
  if ('text' in h) return { t: 'text', s: h.text };
  if ('element' in h) { const [tag, attrs, ch] = h.element; return { t: 'el', tag, attrs, children: ch.map(wireToDump) }; }
  if ('component' in h) { const [, exp, props, ch] = h.component; return { t: 'comp', name: exp, props, children: ch.map(wireToDump) }; }
  throw new Error(`unknown Html node: ${JSON.stringify(h).slice(0, 80)}`);
}
function toElement(node, key) { // verify.mjs, verbatim
  if (node.t === 'text') return node.s;
  if (node.t === 'el') {
    const props = { key };
    for (const [k, v] of node.attrs) props[k] = v;
    return React.createElement(node.tag, props, ...node.children.map((c, i) => toElement(c, i)));
  }
  return React.createElement('span', { key, 'data-component': node.name }, ...node.children.map((c, i) => toElement(c, i)));
}
function entriesOf(file) {
  const j = JSON.parse(fs.readFileSync(file, 'utf8'));
  const pkg = j.package ?? path.basename(file, '.json');
  if (Array.isArray(j.entries)) return j.entries.map((e) => ({ pkg, name: e.name, tree: e.tree }));
  if (Array.isArray(j.panels)) return j.panels.map((p) => ({ pkg,
    name: `L${p.line}${p.selection ? ' sel' + JSON.stringify(p.selection) : ''} #${p.index} ${p.id}`, tree: p.html ? wireToDump(p.html) : null }));
  throw new Error(`${file}: neither {entries} nor {panels}`);
}

// ---- render (verify.mjs's loop, with null-Html panels reported) ----
function verify(entries) {
  const results = []; let current = null;
  const origError = console.error, origWarn = console.warn;
  console.error = (...a) => { if (current) current.errors.push(a.map(String).join(' ').slice(0, 300)); else origError(...a); };
  console.warn = (...a) => { if (current) current.errors.push(a.map(String).join(' ').slice(0, 300)); else origWarn(...a); };
  try {
    for (const e of entries) {
      current = { pkg: e.pkg, name: e.name, errors: [], thrown: null, bytes: 0 };
      if (!e.tree) current.thrown = 'no Html (the panel produced none / RPC failed)';
      else try {
        const html = ReactDOMServer.renderToString(toElement(e.tree, 0));
        current.bytes = html.length;
        if (!html || html.length === 0) current.errors.push('rendered empty output');
      } catch (err) { current.thrown = String(err).slice(0, 300); }
      results.push(current); current = null;
    }
  } finally { console.error = origError; console.warn = origWarn; }
  return results;
}

if (o['self-test']) {
  // The checker must catch both failure classes verify.mjs exists for.
  const cases = [
    { name: 'clean svg', expect: 'clean', tree: wireToDump({ element: ['svg', [['width', '10'], ['style', { color: 'red' }]], [{ element: ['rect', [['x', '1'], ['strokeWidth', '2']], []] }]] }) },
    { name: 'string style prop (#62)', expect: 'fail', tree: wireToDump({ element: ['div', [['style', 'color: red']], [{ text: 'x' }]] }) },
    { name: 'invalid DOM property (class)', expect: 'fail', tree: wireToDump({ element: ['div', [['class', 'a']], [{ text: 'x' }]] }) },
    { name: 'unknown camel prop (stroke-width)', expect: 'fail', tree: wireToDump({ element: ['svg', [], [{ element: ['line', [['stroke-width', '2']], []] }]] }) },
  ];
  const res = verify(cases.map((c) => ({ pkg: 'self-test', name: c.name, tree: c.tree })));
  const rows = res.map((r, i) => { const failed = !!(r.thrown || r.errors.length); const ok = failed === (cases[i].expect === 'fail');
    return { ok, row: [r.name, cases[i].expect, failed ? 'flagged' : 'clean', ok ? 'PASS' : 'FAIL', (r.thrown || r.errors[0] || '').replace(/\n/g, ' ').slice(0, 90)] }; });
  table(['case', 'expected', 'got', 'result', 'first message'], rows.map((r) => r.row));
  const ok = rows.every((r) => r.ok);
  console.log(`E3b self-test ${ok ? 'PASS' : 'FAIL'} (${rows.filter((r) => r.ok).length}/${rows.length})`);
  process.exit(ok ? 0 : 1);
}

const entries = o.in.flatMap((f) => entriesOf(path.resolve(f)));
const results = verify(entries);
const bad = results.filter((r) => r.thrown || r.errors.length);
table(['package', 'panel', 'result', 'chars', 'first problem'], results.map((r) =>
  [r.pkg, r.name, r.thrown || r.errors.length ? 'FAIL' : 'PASS', r.bytes, (r.thrown || r.errors[0] || '').replace(/\n/g, ' ')]));
const ok = bad.length === 0 && (results.length > 0 || o['allow-empty']);
const out = path.resolve(o.out ?? path.join(OUT_HEADLESS, `${path.basename(o.in[0]).replace(/(\.html)?\.json$/, '')}.react.json`));
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify({ lane: 'E3b', tool: 'scripts/headless/react-contract.mjs', at: new Date().toISOString(),
  react: React.version, reactDir: REACT_DIR, inputs: o.in.map((f) => path.relative(SC, path.resolve(f))), ok, panels: results.length, failed: bad.length, results }, null, 1) + '\n');
console.log(`react verification: ${results.length - bad.length}/${results.length} panels clean${bad.length ? `, ${bad.length} FAILED` : ''}`);
console.log(`E3b ${ok ? 'PASS' : 'FAIL'} -> ${out}`);
process.exit(ok ? 0 : 1);
