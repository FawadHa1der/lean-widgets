#!/usr/bin/env node
// Headless React verification of every dumped widget panel — the CI-gate
// equivalent of site/verify.html. Renders each Html tree through React 18
// DEVELOPMENT server rendering (which performs the same dev-mode validation:
// string style props throw error #62, invalid DOM properties warn) and fails
// (exit 1) on ANY React error or warning on ANY panel.
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import vm from 'node:vm';

const HERE = dirname(fileURLToPath(import.meta.url));

// Load the vendored UMD builds inside a vm sandbox, wiring the CJS branch by
// hand so no node_modules is needed (self-contained, like the site itself).
function loadUmd(file, requireMap) {
  const code = readFileSync(join(HERE, 'vendor', file), 'utf8');
  const module = { exports: {} };
  const sandbox = {
    module, exports: module.exports,
    require: (name) => { if (requireMap[name]) return requireMap[name]; throw new Error('unexpected require: ' + name); },
    console, process,
  };
  vm.runInNewContext(code, sandbox, { filename: file });
  return module.exports;
}

const React = loadUmd('react.development.js', {});
const ReactDOMServer = loadUmd('react-dom-server.development.js', { react: React });

function toElement(node, key) {
  if (node.t === 'text') return node.s;
  if (node.t === 'el') {
    const props = { key };
    for (const [k, v] of node.attrs) props[k] = v;
    return React.createElement(node.tag, props, ...node.children.map((c, i) => toElement(c, i)));
  }
  return React.createElement('span', { key, 'data-component': node.name },
    ...node.children.map((c, i) => toElement(c, i)));
}

const results = [];
let current = null;
const origError = console.error.bind(console);
console.error = (...a) => { if (current) current.errors.push(a.map(String).join(' ').slice(0, 300)); };
console.warn = (...a) => { if (current) current.errors.push(a.map(String).join(' ').slice(0, 300)); };

for (const f of readdirSync(join(HERE, 'dumps')).filter(f => f.endsWith('.json')).sort()) {
  const dump = JSON.parse(readFileSync(join(HERE, 'dumps', f), 'utf8'));
  for (const entry of dump.entries) {
    current = { pkg: dump.package, name: entry.name, errors: [], thrown: null };
    try {
      const html = ReactDOMServer.renderToString(toElement(entry.tree, 0));
      if (!html || html.length === 0) current.errors.push('rendered empty output');
    } catch (e) { current.thrown = String(e).slice(0, 300); }
    results.push(current);
    current = null;
  }
}
console.error = origError;

const bad = results.filter(r => r.thrown || r.errors.length);
for (const r of bad) {
  origError(`FAIL ${r.pkg}/${r.name}: ${r.thrown || r.errors[0]}`);
}
const ok = results.length - bad.length;
console.log(`react verification: ${ok}/${results.length} panels clean${bad.length ? `, ${bad.length} FAILED` : ''}`);
process.exit(bad.length ? 1 : 0);
