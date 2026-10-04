#!/usr/bin/env node
// Olean header gate (BUILD-PLAN.md §4 "Go/no-go S2"; format: wasm64-lean-kernel/src/library/module.cpp:109-146).
//
// Every checked file must have:
//   bytes[0:5] == "olean"        marker
//   byte[5] in {2, 3}            version
//   byte[6] == 0                 flags: bit0 = GMP; the wasm64 runtime has no GMP
//   bytes[40:80] all zero        githash: native64 is built with an empty githash
//
// usage:
//   header-gate.mjs --clone <W/mathlib4> [--core <K/native/stage1/lib/lean>]
//                   [--modules <file of module names>]...   resolve each module's facets in the clone
//                   [--files <file of paths, relative to --clone or absolute>]...
//                   [--label <name>] [--json <out.json>]
// For modules, .olean is required and .olean.server/.olean.private are checked when present.
// Exit 0 only if every file passes and no required .olean is missing.
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const opt = { modules: [], files: [] };
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--modules') opt.modules.push(args[++i]);
  else if (a === '--files') opt.files.push(args[++i]);
  else if (a === '--clone') opt.clone = args[++i];
  else if (a === '--core') opt.core = args[++i];
  else if (a === '--label') opt.label = args[++i];
  else if (a === '--json') opt.json = args[++i];
  else { console.error(`header-gate: unknown arg ${a}`); process.exit(2); }
}
if (!opt.clone) { console.error('header-gate: --clone required'); process.exit(2); }

const PKG = {
  Mathlib: '', Batteries: '.lake/packages/batteries', ProofWidgets: '.lake/packages/proofwidgets',
  Aesop: '.lake/packages/aesop', Qq: '.lake/packages/Qq', Plausible: '.lake/packages/plausible',
  ImportGraph: '.lake/packages/importGraph', LeanSearchClient: '.lake/packages/LeanSearchClient',
  Cli: '.lake/packages/Cli',
};
const CORE = new Set(['Init', 'Lean', 'Std', 'Lake']);

function oleanPath(mod) {
  const parts = mod.split('.');
  const top = parts[0];
  if (CORE.has(top)) {
    if (!opt.core) return null;
    return path.join(opt.core, ...parts) + '.olean';
  }
  const pkg = top in PKG ? PKG[top] : ''; // widget libs live in the root package's build dir
  return path.join(opt.clone, pkg, '.lake/build/lib/lean', ...parts) + '.olean';
}

function check(file) {
  const fd = fs.openSync(file, 'r');
  const h = Buffer.alloc(80);
  const n = fs.readSync(fd, h, 0, 80, 0);
  fs.closeSync(fd);
  const problems = [];
  if (n < 80) problems.push(`short file (${n} bytes)`);
  if (h.subarray(0, 5).toString('latin1') !== 'olean') problems.push('bad marker');
  if (h[5] !== 2 && h[5] !== 3) problems.push(`version ${h[5]}`);
  if (h[6] !== 0) problems.push(`flags 0x${h[6].toString(16)}${h[6] & 1 ? ' (GMP)' : ''}`);
  const gh = h.subarray(40, 80);
  if (gh.some((b) => b !== 0)) problems.push(`githash '${gh.toString('latin1').replace(/\0+$/, '')}'`);
  return { version: h[5], flags: h[6], problems };
}

const results = [];
const missing = [];
const skippedCore = [];
for (const f of opt.modules) {
  for (const mod of fs.readFileSync(f, 'utf8').split('\n').map((s) => s.trim()).filter(Boolean)) {
    const p = oleanPath(mod);
    if (p === null) { skippedCore.push(mod); continue; }
    if (!fs.existsSync(p)) { missing.push(mod); continue; }
    for (const facet of [p, p + '.server', p + '.private']) {
      if (facet !== p && !fs.existsSync(facet)) continue;
      results.push({ module: mod, file: path.relative(opt.clone, facet), ...check(facet) });
    }
  }
}
for (const f of opt.files) {
  for (const rel of fs.readFileSync(f, 'utf8').split('\n').map((s) => s.trim()).filter(Boolean)) {
    const p = path.isAbsolute(rel) ? rel : path.join(opt.clone, rel);
    if (!fs.existsSync(p)) { missing.push(rel); continue; }
    results.push({ module: null, file: path.relative(opt.clone, p), ...check(p) });
  }
}

const failed = results.filter((r) => r.problems.length);
const gmp = failed.filter((r) => r.flags & 1);
const byVersion = {};
for (const r of results) byVersion[r.version] = (byVersion[r.version] || 0) + 1;
const summary = {
  label: opt.label || null,
  checkedFiles: results.length,
  modules: new Set(results.filter((r) => r.module).map((r) => r.module)).size,
  facets: {
    olean: results.filter((r) => r.file.endsWith('.olean')).length,
    server: results.filter((r) => r.file.endsWith('.olean.server')).length,
    private: results.filter((r) => r.file.endsWith('.olean.private')).length,
  },
  versions: byVersion,
  missingRequired: missing,
  skippedCoreNoCorePath: skippedCore.length,
  failed: failed.map(({ file, problems }) => ({ file, problems })),
  gmp: gmp.map((r) => r.file),
  pass: failed.length === 0 && missing.length === 0,
};
if (opt.json) fs.writeFileSync(opt.json, JSON.stringify(summary, null, 1) + '\n');
console.log(`header-gate${opt.label ? ` [${opt.label}]` : ''}: ${summary.pass ? 'PASS' : 'FAIL'} ` +
  `files=${summary.checkedFiles} modules=${summary.modules} (olean ${summary.facets.olean}, server ${summary.facets.server}, private ${summary.facets.private}) ` +
  `versions=${JSON.stringify(byVersion)} failed=${failed.length} gmp=${gmp.length} missing=${missing.length}`);
for (const r of failed.slice(0, 50)) console.log(`  FAIL ${r.file}: ${r.problems.join(', ')}`);
for (const m of missing.slice(0, 50)) console.log(`  MISSING ${m}`);
process.exit(summary.pass ? 0 : 1);
