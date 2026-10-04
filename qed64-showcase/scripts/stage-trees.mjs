#!/usr/bin/env node
// stage-trees.mjs — BUILD-PLAN §5 C1/C2: build a bake (slim) or Demo-replay (fat) olean tree.
//
//   node scripts/stage-trees.mjs --base <served tree> --into <new tree> (--slim | --fat)
//        --roots QED64.Essential,ChartKit,...  [--root-headers <a.lean,b.lean>]
//        [--clone W/mathlib4] [--core-src <served core lib>] [--native-core <K/native/stage1/lib/lean>]
//        [--essential K/mathlib/essential-modules.txt] [--base-n 5004] [--report <json>] [--force]
//
// 1. APFS-clone the base tree (`cp -cR`; new inodes, never hard links) to --into.
// 2. Walk the import closure of --roots (plus the import lines of --root-headers) with QED64's
//    olean-imports.mjs reader; a module is read from the tree if present, else from its source:
//      widget libs (ChartKit … DistLens, LeanWidgetKit) and Mathlib  W/mathlib4/.lake/build/lib/lean
//      Batteries/ProofWidgets/Aesop/Qq/…                             W/mathlib4/.lake/packages/<p>/.lake/build/lib/lean
//      Init/Lean/Std/Lake                                            --core-src (the served core, exact bytes)
// 3. delta = closure − modules already in the tree. Clone each delta module's facets into the tree with
//    copyFileSync(COPYFILE_FICLONE: clonefile on APFS; FICLONE_FORCE is ENOSYS on darwin): module-system files carry .olean .olean.server .ir .ir.sig
//    (+ .olean.private with --fat), exactly the facet set the served slim tree holds for comparable
//    modules; legacy (non-`module`) widget files have only .olean, their IR decls live inside it
//    (Lean.IR.declMapExt entries), which is checked here.
// Gates (each prints OK/FAIL; any FAIL -> exit 1, report still written):
//   G1 header gate on every delta facet: "olean", version 2|3, flags 0 (no GMP), githash bytes 40..80
//      all zero (core delta: identical header to the served core instead, which carries a githash)
//   G2 byte identity, for every closure module already in the tree, of each facet the tree holds vs the
//      native build the delta was compiled against: full file for Mathlib/ProofWidgets/Batteries/Aesop/
//      Qq/…; bytes 80.. for core (headers differ only in githash). Mismatch = delta compiled against
//      different bytes: STOP.
//   G3 delta ∩ essential-modules.txt = ∅ (and own ∩ essential = ∅)
//   G4 closure completeness inside the staged tree alone (every import resolves to <tree>/<M>.olean)
//   G5 QED64's `olean-imports.mjs --audit <tree>`: no `import all` edge outside Init/Std/Lean/Lake that
//      the base tree does not already have
//   G6 EXPECTED-N = base-n + |delta| + |own| == |closure|; written to <into>.EXPECTED-N
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { cloneTree } from './lib/platform.mjs';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// the TARGET pin (scripts/lib/pins.mjs: SHOWCASE_PIN=<id>, else the active pin): QED64's olean reader at its commit (source dependency) and served trees
const PINS = await import(path.join(SC, 'scripts/lib/pins.mjs'));
const OLEAN_IMPORTS = path.join(PINS.storePath('qed64'), 'pipeline/artifacts/olean-imports.mjs');
const { oleanImportEntries } = await import(OLEAN_IMPORTS);
const { oleanExtEntryCounts } = await import(path.join(SC, 'scripts/lib/olean-entries.mjs'));

// locations: scripts/lib/env.mjs (W = QED64_SHOWCASE_WORK, K = QED64_KERNEL_BUILD, the read-only trees from the env)
const ENV = await import(path.join(SC, 'scripts/lib/env.mjs'));
const { W, Q, KR, LG, WS } = ENV;
let K;
try { K = ENV.need('QED64_KERNEL_BUILD'); } catch (e) { console.error(`REFUSED: ${e.message}`); process.exit(2); }
const READ_ONLY = [Q, K, KR, LG, WS].filter(Boolean);

const args = process.argv.slice(2);
// default --core-src / --base-n: the active pin's served core lib (pins/<id>/pin.json servedTrees; scripts/lib/pins.mjs)
const SERVED = PINS.pinDescriptor(PINS.targetPinId()).servedTrees;
const opt = { clone: path.join(W, 'mathlib4'), coreSrc: ENV.expandPath(SERVED.coreSrc),
  nativeCore: path.join(K, 'native/stage1/lib/lean'), essential: path.join(K, 'mathlib/essential-modules.txt'),
  baseN: SERVED.baseN, rootHeaders: [] };
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  const v = () => args[++i];
  if (a === '--base') opt.base = v(); else if (a === '--into') opt.into = v();
  else if (a === '--slim') opt.mode = 'slim'; else if (a === '--fat') opt.mode = 'fat';
  else if (a === '--roots') opt.roots = v().split(',').filter(Boolean);
  else if (a === '--root-headers') opt.rootHeaders = v().split(',').filter(Boolean);
  else if (a === '--clone') opt.clone = v(); else if (a === '--core-src') opt.coreSrc = v();
  else if (a === '--native-core') opt.nativeCore = v(); else if (a === '--essential') opt.essential = v();
  else if (a === '--base-n') opt.baseN = Number(v()); else if (a === '--report') opt.report = v();
  else if (a === '--force') opt.force = true;
  else { console.error(`stage-trees: unknown arg ${a}`); process.exit(2); }
}
if (!opt.base || !opt.into || !opt.mode || !opt.roots) {
  console.error('usage: stage-trees.mjs --base <tree> --into <tree> (--slim|--fat) --roots A,B,... [--root-headers f.lean,...] [--report out.json] [--force]');
  process.exit(2);
}
opt.into = path.resolve(opt.into);
for (const ro of READ_ONLY) if (opt.into === ro || opt.into.startsWith(ro + '/')) { console.error(`REFUSED: --into ${opt.into} is inside read-only ${ro}`); process.exit(2); }

const PKG = { Batteries: 'batteries', ProofWidgets: 'proofwidgets', Aesop: 'aesop', Qq: 'Qq', Plausible: 'plausible',
  ImportGraph: 'importGraph', LeanSearchClient: 'LeanSearchClient', Cli: 'Cli' };
const CORE = new Set(['Init', 'Lean', 'Std', 'Lake']);
const OWN = new Set(['ChartKit', 'ExprXRay', 'GraphScope', 'HasseView', 'IntervalInspector', 'SimpLens', 'TreeScope', 'DistLens', 'LeanWidgetKit']);
const FACETS_SLIM = ['.olean', '.olean.server', '.ir', '.ir.sig'];
const FACETS_FAT = ['.olean', '.olean.server', '.olean.private', '.ir', '.ir.sig'];
const FACETS = opt.mode === 'fat' ? FACETS_FAT : FACETS_SLIM;
const top = (m) => m.split('.')[0];
const kind = (m) => (CORE.has(top(m)) ? 'core' : OWN.has(top(m)) ? 'own' : 'dep');
const rel = (m) => path.join(...m.split('.'));
function srcBase(m) { // directory holding the native build output for m (source of delta facets)
  const t = top(m);
  if (CORE.has(t)) return opt.coreSrc;
  if (t in PKG) return path.join(opt.clone, '.lake/packages', PKG[t], '.lake/build/lib/lean');
  return path.join(opt.clone, '.lake/build/lib/lean'); // Mathlib + widget libs (root package)
}
function nativeBase(m) { return CORE.has(top(m)) ? opt.nativeCore : srcBase(m); } // G2 comparison side

let fails = 0;
const gate = (cond, msg, detail = '') => { console.log(`${cond ? 'OK  ' : 'FAIL'} ${msg}${detail ? ' — ' + detail : ''}`); if (!cond) fails++; return cond; };
const t0 = Date.now();

// ---- 1. clone the base tree ----
if (fs.existsSync(opt.into)) {
  if (!opt.force) { console.error(`REFUSED: ${opt.into} exists (pass --force to replace)`); process.exit(2); }
  fs.rmSync(opt.into, { recursive: true, force: true });
}
fs.mkdirSync(path.dirname(opt.into), { recursive: true });
cloneTree(opt.base, opt.into); // cp -cR on macOS, cp -R --reflink=auto on Linux (scripts/lib/platform.mjs)
const baseInventory = new Set();
(function walk(dir, prefix) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) walk(path.join(dir, e.name), prefix ? `${prefix}.${e.name}` : e.name);
    else if (e.name.endsWith('.olean')) baseInventory.add(prefix ? `${prefix}.${e.name.slice(0, -6)}` : e.name.slice(0, -6));
  }
})(opt.into, '');
const probe = path.join(opt.into, 'Mathlib/Order/Basic.olean');
const nlink = fs.existsSync(probe) ? fs.statSync(probe).nlink : null;
console.log(`cloned ${opt.base} -> ${opt.into} (cp -cR): ${baseInventory.size} modules; nlink(Mathlib/Order/Basic.olean)=${nlink}`);
gate(nlink === null || nlink === 1, 'clone has fresh inodes (nlink 1), no hard link into the base tree');

// ---- 2. closure walk ----
const roots = [...opt.roots];
for (const f of opt.rootHeaders) {
  for (const line of fs.readFileSync(f, 'utf8').split('\n')) {
    const mm = /^(?:public\s+|private\s+)?(?:meta\s+)?import\s+(?:all\s+)?([A-Za-z_][\w.«»]*)/.exec(line);
    if (mm) roots.push(mm[1].replace(/[«»]/g, ''));
  }
}
const rootSet = [...new Set(roots)];
const closure = new Map(); // module -> { inTree, imports, entries }
const missing = [];
const stack = [...rootSet];
while (stack.length) {
  const m = stack.pop();
  if (closure.has(m)) continue;
  const inTree = baseInventory.has(m);
  const file = path.join(inTree ? opt.into : srcBase(m), rel(m) + '.olean');
  if (!fs.existsSync(file)) { missing.push(`${m} (${file})`); closure.set(m, { inTree, imports: [], entries: [] }); continue; }
  const entries = oleanImportEntries(fs.readFileSync(file));
  if (!entries) { missing.push(`${m} (unreadable ${file})`); closure.set(m, { inTree, imports: [], entries: [] }); continue; }
  const imports = [...new Set(entries.map((e) => e.module))];
  closure.set(m, { inTree, imports, entries });
  for (const i of imports) if (!closure.has(i)) stack.push(i);
}
gate(!missing.length, `every closure module has an .olean (tree or native source) — closure ${closure.size} modules from ${rootSet.length} roots`, missing.slice(0, 5).join('; '));
const delta = [...closure.keys()].filter((m) => !closure.get(m).inTree).sort();
const deltaDep = delta.filter((m) => kind(m) === 'dep');
const deltaCore = delta.filter((m) => kind(m) === 'core');
const own = delta.filter((m) => kind(m) === 'own');
console.log(`closure ${closure.size}: in tree ${closure.size - delta.length}, delta ${deltaDep.length + deltaCore.length} (dep ${deltaDep.length}, core ${deltaCore.length}), own ${own.length}`);

// ---- 3. clone delta facets ----
const copied = [];
const facetReport = {};
const isModuleOf = (buf) => { // ModuleData scalar isModule: after the 5 object fields of the root ctor
  const base = buf.readBigUInt64LE(80); const root = Number(buf.readBigUInt64LE(88) - base);
  return buf.readUInt8(root + 8 + 8 * 5) !== 0;
};
const legacyIrCheck = [];
for (const m of delta) {
  const sb = srcBase(m);
  const present = FACETS_FAT.filter((f) => fs.existsSync(path.join(sb, rel(m) + f)));
  const olean = fs.readFileSync(path.join(sb, rel(m) + '.olean'));
  const isModule = isModuleOf(olean);
  const want = isModule ? FACETS : ['.olean'];
  const lacking = want.filter((f) => !present.includes(f));
  const unexpected = isModule ? [] : present.filter((f) => f !== '.olean'); // legacy must carry only .olean
  facetReport[m] = { kind: kind(m), isModule, sourceFacets: present, copied: want.filter((f) => present.includes(f)) };
  if (lacking.length) gate(false, `${m}: source lacks facet(s) ${lacking.join(',')}`);
  if (unexpected.length) gate(false, `${m}: legacy module unexpectedly has ${unexpected.join(',')}`);
  if (!isModule) {
    const { constNames, entries } = oleanExtEntryCounts(olean);
    legacyIrCheck.push({ m, constNames, irDecls: entries['Lean.IR.declMapExt'] ?? 0 });
  }
  for (const f of want) {
    const src = path.join(sb, rel(m) + f); const dst = path.join(opt.into, rel(m) + f);
    if (!fs.existsSync(src)) continue;
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(src, dst, fs.constants.COPYFILE_FICLONE | fs.constants.COPYFILE_EXCL);
    copied.push({ m, f, dst });
  }
}
const facetCounts = {};
for (const { f } of copied) facetCounts[f] = (facetCounts[f] ?? 0) + 1;
const modDelta = delta.filter((m) => facetReport[m].isModule);
const legDelta = delta.filter((m) => !facetReport[m].isModule);
console.log(`cloned ${copied.length} delta facet files ${JSON.stringify(facetCounts)}; module-system ${modDelta.length} (${[...new Set(modDelta.map(kind))].join('/') || '-'}), legacy ${legDelta.length} (${[...new Set(legDelta.map(kind))].join('/') || '-'})`);
gate(own.every((m) => !facetReport[m].isModule), `all ${own.length} widget modules are legacy (non-\`module\`) files with only .olean`);
const irless = legacyIrCheck.filter((x) => x.constNames > 0 && x.irDecls === 0);
gate(true, `legacy delta IR lives inside the .olean: ${legacyIrCheck.filter((x) => x.irDecls > 0).length}/${legacyIrCheck.length} carry Lean.IR.declMapExt entries (total ${legacyIrCheck.reduce((s, x) => s + x.irDecls, 0)})` +
  (irless.length ? `; ${irless.length} with consts but no IR decls (proof-only / noncomputable): ${irless.slice(0, 6).map((x) => x.m).join(', ')}` : ''));

// ---- G1 header gate ----
const servedCoreHeader = (() => { const b = Buffer.alloc(80); const fd = fs.openSync(path.join(opt.into, 'Init/Prelude.olean'), 'r'); fs.readSync(fd, b, 0, 80, 0); fs.closeSync(fd); return b; })();
const g1bad = [];
for (const { m, f, dst } of copied) {
  const h = Buffer.alloc(80); const fd = fs.openSync(dst, 'r'); const n = fs.readSync(fd, h, 0, 80, 0); fs.closeSync(fd);
  const p = [];
  if (n < 80 || h.toString('latin1', 0, 5) !== 'olean') p.push('marker');
  if (h[5] !== 2 && h[5] !== 3) p.push(`version ${h[5]}`);
  if (h[6] !== 0) p.push(`flags 0x${h[6].toString(16)}`);
  if (kind(m) === 'core') { if (Buffer.compare(h.subarray(0, 80), servedCoreHeader.subarray(0, 80)) !== 0 && h.subarray(40, 80).some((b) => b !== 0)) p.push('core header differs from served core'); }
  else if (h.subarray(40, 80).some((b) => b !== 0)) p.push('githash');
  if (p.length) g1bad.push(`${m}${f}: ${p.join(',')}`);
}
gate(!g1bad.length, `G1 header gate on ${copied.length} delta facet files (olean marker, v2|3, flags 0 = no GMP, empty githash)`, g1bad.slice(0, 5).join('; '));

// ---- G2 byte identity of closure modules already in the tree vs the native build ----
const g2 = { compared: 0, full: 0, tail80: 0, noNative: [], mismatch: [] };
const sameTail = (a, b, from) => a.length === b.length && Buffer.compare(a.subarray(from), b.subarray(from)) === 0;
for (const [m, info] of closure) {
  if (!info.inTree) continue;
  const nb = nativeBase(m);
  if (!fs.existsSync(path.join(nb, rel(m) + '.olean'))) { g2.noNative.push(m); continue; }
  for (const f of FACETS_FAT) {
    const tf = path.join(opt.into, rel(m) + f);
    if (!fs.existsSync(tf)) continue;
    const nf = path.join(nb, rel(m) + f);
    if (!fs.existsSync(nf)) { g2.mismatch.push(`${m}${f}: missing on native side`); continue; }
    const a = fs.readFileSync(tf), b = fs.readFileSync(nf);
    g2.compared++;
    if (kind(m) === 'core') { g2.tail80++; if (!sameTail(a, b, 80)) g2.mismatch.push(`${m}${f} (bytes 80..)`); }
    else { g2.full++; if (Buffer.compare(a, b) !== 0) g2.mismatch.push(`${m}${f}`); }
  }
}
gate(!g2.mismatch.length, `G2 byte identity tree vs native build for ${g2.compared} facet files of in-tree closure modules (${g2.full} full-file, ${g2.tail80} core bytes 80..)`,
  g2.mismatch.length ? `${g2.mismatch.length} mismatch: ${g2.mismatch.slice(0, 5).join('; ')}` : `no native counterpart: ${g2.noNative.join(', ') || 'none'}`);
gate(g2.noNative.every((m) => m.startsWith('QED64.')), 'G2 only QED64.* modules lack a native counterpart', g2.noNative.join(', '));

// ---- G3 disjointness ----
const essential = new Set(fs.readFileSync(opt.essential, 'utf8').split('\n').map((s) => s.trim()).filter(Boolean));
const inter = [...deltaDep, ...own].filter((m) => essential.has(m));
gate(!inter.length, `G3 delta ∩ ${path.basename(opt.essential)} (${essential.size}) = ∅`, inter.slice(0, 5).join(', '));

// ---- G4 closure completeness inside the staged tree alone ----
const seen = new Set(); const st4 = [...rootSet]; const unresolved = [];
while (st4.length) {
  const m = st4.pop(); if (seen.has(m)) continue; seen.add(m);
  const file = path.join(opt.into, rel(m) + '.olean');
  if (!fs.existsSync(file)) { unresolved.push(m); continue; }
  for (const e of oleanImportEntries(fs.readFileSync(file)) ?? []) if (!seen.has(e.module)) st4.push(e.module);
}
gate(!unresolved.length && seen.size === closure.size, `G4 closure complete inside ${path.basename(opt.into)}: ${seen.size} modules resolve`, unresolved.slice(0, 5).join(', '));
if (opt.mode === 'slim') {
  const priv = execFileSync('find', [opt.into, '-name', '*.olean.private']).toString().trim();
  gate(!priv, 'slim tree holds no *.olean.private');
}

// ---- G5 import-all audit (QED64's CLI at the pin's commit) ----
// Watchdog (300 s, one retry): on 2026-10-01 (re-pin lane) an audit of tree-slim-w8 finished its work and then never exited;
// `sample` showed node::Environment::Exit -> pthread_join on a V8 ConcurrentBaselineCompiler thread parked in
// __psynch_cvwait (logs/repin-stage-w8-audit-hang.sample.txt): the Node v26 exit deadlock README.md describes for verify's
// watchdog. An audit takes a few seconds; a timeout re-runs it once, and a second failure is still a failure.
const AUDIT_TIMEOUT_MS = 300000;
const audit = (tree) => {
  for (let attempt = 1; ; attempt++) {
    try { return execFileSync(process.execPath, [OLEAN_IMPORTS, '--audit', tree], { maxBuffer: 1 << 26, timeout: AUDIT_TIMEOUT_MS }).toString(); }
    catch (e) {
      if (e.signal === 'SIGTERM' && attempt < 2) { console.log(`   audit(${tree}) did not exit within ${AUDIT_TIMEOUT_MS / 1000} s (Node v26 exit deadlock); retrying once`); continue; }
      throw e;
    }
  }
};
const outsideCount = (txt) => Number(/outside Init\/Std\/Lean\/Lake: (\d+)/.exec(txt)?.[1]);
const aBase = audit(opt.base), aInto = audit(opt.into);
// exact outside edges (same rule as the CLI), to diff beyond the CLI's 40-line listing
const outsideEdges = (mods) => mods.filter((m) => !/^(Init|Std|Lean|Lake)(\.|$)/.test(m))
  .flatMap((m) => (closure.get(m)?.entries ?? []).filter((e) => e.importAll).map((e) => `${m} → import all ${e.module}`));
const newEdges = outsideEdges(delta);
console.log(`   audit(base): ${aBase.split('\n')[0]}\n   audit(into): ${aInto.split('\n')[0]}`);
gate(outsideCount(aInto) === outsideCount(aBase) && !newEdges.length, `G5 no new \`import all\` edge outside Init/Std/Lean/Lake (base ${outsideCount(aBase)}, staged ${outsideCount(aInto)})`, newEdges.slice(0, 5).join('; '));

// ---- G6 EXPECTED-N ----
const N = opt.baseN + deltaDep.length + deltaCore.length + own.length;
gate(baseInventory.size === opt.baseN, `G6 base tree holds base-n = ${opt.baseN} modules`, String(baseInventory.size));
gate(N === closure.size, `G6 EXPECTED-N = ${opt.baseN} + ${deltaDep.length + deltaCore.length} + ${own.length} = ${N} == |closure| ${closure.size}`);
fs.writeFileSync(`${opt.into}.EXPECTED-N`, `${N}\n`);

const report = {
  schema: 'qed64-showcase.stage-trees/v1', at: new Date().toISOString(), mode: opt.mode, base: opt.base, into: opt.into,
  roots: rootSet, closure: closure.size, baseN: opt.baseN, expectedN: N,
  delta: { dep: deltaDep, core: deltaCore }, own, facetCounts, facets: facetReport, legacyIr: legacyIrCheck,
  g2: { compared: g2.compared, full: g2.full, tail80: g2.tail80, noNative: g2.noNative, mismatch: g2.mismatch },
  audit: { base: aBase, into: aInto }, fails, seconds: Math.round((Date.now() - t0) / 1000),
};
if (opt.report) fs.writeFileSync(opt.report, JSON.stringify(report, null, 1) + '\n');
console.log(fails ? `STAGE-TREES FAILED (${fails} FAIL) ${opt.into}` : `STAGE-TREES OK ${opt.into} EXPECTED-N=${N} (${report.seconds}s)`);
process.exit(fails ? 1 : 0);
