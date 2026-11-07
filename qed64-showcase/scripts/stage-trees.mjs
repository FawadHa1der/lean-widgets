#!/usr/bin/env node
// stage-trees.mjs — BUILD-PLAN §5 C1/C2: build a bake (slim) or Demo-replay (fat) olean tree.
//
//   node scripts/stage-trees.mjs --base <served tree> --into <new tree> (--slim | --fat)
//        --roots QED64.Essential,ChartKit,...  [--root-headers <a.lean,b.lean>]
//        [--clone <Mathlib clone>] [--core-src <served core lib>] [--native-core <K/native/stage1/lib/lean>]
//        [--essential K/mathlib/essential-modules.txt] [--base-n 5004] [--report <json>] [--force]
//        --clone defaults to MATHLIB_CLONE (scripts/lib/env.mjs: the target pin's clone, W/mathlib4.<Mathlib commit 8> or
//        the legacy W/mathlib4; REFUSED with the expected path when it does not resolve)
//   node scripts/stage-trees.mjs --check-digest baseSlim|baseFat|coreSrc [--tree <dir>]
//        only G0 below for one served tree (default: the target pin's servedTrees.<key>; --tree checks a copy of it);
//        exit 0 OK or SKIP (no digest recorded), 1 FAIL, 2 setup error
//   node scripts/stage-trees.mjs --check-provenance <tree> [<tree>…]
//        is each staged tree the TARGET pin's? <tree>.STAGED.json (below) == its runtime, served base and widget export
//        (scripts/lib/staged-tree.mjs checkProvenance); one OK/REFUSED line per tree; exit 0 all OK, 3 refused, 2 usage.
//        bake.sh, judge-bake.mjs and headless stage4/e2 refuse a tree it refuses; `showcase.sh all`
//        restages it for its target pin
//   node scripts/stage-trees.mjs --check-native
//        N0's native build record check alone (below; scripts/lib/staged-tree.mjs checkNativeBuild, with --clone's
//        default): one OK/REFUSED line; exit 0 OK, 3 refused. `showcase.sh all` skips native only when it is OK
//   node scripts/stage-trees.mjs --stock-copy <dir>
//        run-controls.sh's W/tree-stock: cloned from the target pin's servedTrees.baseSlim when missing (with
//        <dir>.SOURCE.json: where from, for which pin; one left by a removed copy is removed first, so an interrupted
//        clone has none), then checked: G0 for a pin that records baseSlimDigest (a missing sidecar, or one naming
//        another pin or base, is rewritten once G0 passes), else the sidecar must name that baseSlim and the copy hold
//        baseN .olean (scripts/lib/staged-tree.mjs checkStockCopy); exit 0 OK, 1 G0 FAIL, 3 refused, 2 setup error; a
//        refusal prints the command that moves the copy aside with its sidecar
//
// The staged trees under W are ONE set shared by every pin (not per-runtime stores): staging for one pin replaces the
// trees another pin's lanes read. So --into gets <into>.STAGED.json {schema, tree, mode, pin, buildId, base,
// widgetsSourceHash, expectedN, report, stagedAt}: removed before the tree is replaced, written (tmp + rename) only when
// every gate below passed; readers refuse a tree without one, with one for another runtime / base / widget export, or
// whose EXPECTED-N or --report no longer is this tree's.
//
// N0 (before anything is cloned): the native inputs are the target pin's: --clone HEAD and QED64_KERNEL_BUILD
//    mathlib/MATHLIB-COMMIT == its lock's toolchain.mathlib.commit, QED64_KERNEL_BUILD BUILT-COMMIT ==
//    toolchain.native64.BUILT_COMMIT, and the native build record (the last COMPLETE `native all`'s in --clone,
//    <clone>/.lake/showcase-native-build.json, else out/native-build.json, the last one in any clone; a `showcase.sh
//    native` step that rewrites the clone removes both, and a clone-writing build step stamped in the clone after it
//    refuses) is --clone's, with the lock's Mathlib and native commits and WIDGETS_SOURCE_HASH: pins of one Mathlib
//    commit share a clone (the legacy W/mathlib4) and its record but not their widget export (A–J c2efe78f, K/L/N
//    b81f1b75), and the clone holds the widget oleans of the last native run, which no gate below compares (own modules
//    have no G2). Nothing else ties them to the pin (an overriding MATHLIB_CLONE / --clone, a kernel build of another
//    Lean release), and another pin's would surface only as G2 byte mismatches after the clone, or not at all; G1 also
//    compares every delta facet's Lean version with the served core's. The clone is read from the closure walk through
//    G2, and nothing stops a `showcase.sh native` step (another lane, another pin) from rewriting it meanwhile, so the
//    record check runs again after G6 ("N0 again", below).
// G0 (before anything is cloned; only for a pin whose descriptor records the digest, pins/<id>/pin.json
//    servedTrees.baseSlimDigest / baseFatDigest / coreDigest; 58ebbad records only coreDigest): the tree digest of --base (when it
//    is the pin's servedTrees.baseSlim for --slim, servedTrees.baseFat for --fat) and of --core-src (when it is
//    servedTrees.coreSrc) equals the recorded digest, and the recorded digest equals the pin's QED64
//    embedding/base-tree.json trees.lib-tree-slim / lib-tree / core-lib-slim digest where that file exists (QED64 385a1ac
//    on). Rule = QED64's treeDigest (pipeline/release/adopt-helper.mjs): sha256 over the lines
//    "<relpath>\0<sha256 hex>\n" of every file, relpath /-separated, sorted by byte order. About 5 s per GB.
// 1. APFS-clone the base tree (`cp -cR`; new inodes, never hard links) to --into.
// 2. Walk the import closure of --roots (plus the import lines of --root-headers) with QED64's
//    olean-imports.mjs reader; a module is read from the tree if present, else from its source:
//      widget libs (ChartKit … DistLens, LeanWidgetKit) and Mathlib  <clone>/.lake/build/lib/lean
//      Batteries/ProofWidgets/Aesop/Qq/…                             <clone>/.lake/packages/<p>/.lake/build/lib/lean
//      Init/Lean/Std/Lake                                            --core-src (the served core, exact bytes)
// 3. delta = closure − modules already in the tree. Clone each delta module's facets into the tree with
//    copyFileSync(COPYFILE_FICLONE: clonefile on APFS; FICLONE_FORCE is ENOSYS on darwin): module-system files carry .olean .olean.server .ir .ir.sig
//    (+ .olean.private with --fat), exactly the facet set the served slim tree holds for comparable
//    modules; legacy (non-`module`) widget files have only .olean, their IR decls live inside it
//    (Lean.IR.declMapExt entries), which is checked here.
// Gates (each prints OK/FAIL; any FAIL -> exit 1). A FAIL of G0/N0 before the clone writes nothing, so an existing
// --into, its EXPECTED-N, record and --report stay that tree's; from the clone on --into is replaced (its record removed
// first), and a FAIL there still writes the report:
//   G1 header gate on every delta facet: "olean", version 2|3, flags 0 (no GMP), Lean version (bytes 7..40) == the
//      served core's (the base tree's Init/Prelude.olean: a delta built by another pin's toolchain, e.g. 4.34 oleans
//      into a 4.35 tree, is refused), githash bytes 40..80 all zero (core delta: identical header to the served core
//      instead, which carries a githash)
//   G2 byte identity, for every closure module already in the tree, of each facet the tree holds vs the
//      native build the delta was compiled against: full file for Mathlib/ProofWidgets/Batteries/Aesop/
//      Qq/…; bytes 80.. for core (headers differ only in githash). Mismatch = delta compiled against
//      different bytes: STOP.
//   G3 delta ∩ essential-modules.txt = ∅ (and own ∩ essential = ∅)
//   G4 closure completeness inside the staged tree alone (every import resolves to <tree>/<M>.olean)
//   G5 QED64's `olean-imports.mjs --audit <tree>`: no `import all` edge outside Init/Std/Lean/Lake that
//      the base tree does not already have
//   G6 EXPECTED-N = base-n + |delta| + |own| == |closure|; written to <into>.EXPECTED-N
//   N0 again, just before the report and record: the native build record still passes N0's check AND is the very file
//      N0 read (same path, mtime and size): a step that rewrote the clone while it was read removed it (`showcase.sh
//      native`), stamped the clone after it (build-native.sh) or, as a complete `native all`, replaced it. A FAIL
//      removes nothing more (the tree stays replaced, without a record) and the report records it
// No FAIL: <into>.STAGED.json is written for the target pin (above).
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { cloneTree } from './lib/platform.mjs';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// the TARGET pin (scripts/lib/pins.mjs: SHOWCASE_PIN=<id>, else the active pin): QED64's olean reader at its commit (source dependency) and served trees
const PINS = await import(path.join(SC, 'scripts/lib/pins.mjs'));

// ---- G0: served-tree digests (see the header); also the --check-digest mode, which needs nothing else ----
const DIGEST_FIELDS = { baseSlim: { field: 'baseSlimDigest', tree: 'lib-tree-slim' }, baseFat: { field: 'baseFatDigest', tree: 'lib-tree' },
  coreSrc: { field: 'coreDigest', tree: 'core-lib-slim' } };
function treeDigest(dir) { // QED64 adopt-helper.mjs treeDigest, same rule
  const lines = [];
  let bytes = 0;
  const walk = (d, prefix) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const full = path.join(d, e.name), r = prefix ? `${prefix}/${e.name}` : e.name;
      if (e.isSymbolicLink()) throw new Error(`${full} is a symlink`);
      if (e.isDirectory()) walk(full, r);
      else if (e.isFile()) { const b = fs.readFileSync(full); bytes += b.length; lines.push(`${r}\0${createHash('sha256').update(b).digest('hex')}\n`); }
    }
  };
  walk(dir, '');
  lines.sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
  return { digest: `sha256:${createHash('sha256').update(lines.join('')).digest('hex')}`, files: lines.length, bytes };
}
/** G0 for one served tree of the target pin: {ok, skip, line, ...}. `dir` defaults to the descriptor's (expanded) path. */
function servedDigest(key, dir) {
  const id = PINS.targetPinId(), st = PINS.pinDescriptor(id).servedTrees || {};
  const { field, tree } = DIGEST_FIELDS[key];
  const want = st[field];
  if (!want) return { ok: true, skip: true, key, line: `G0 ${key}: pin ${id} records no servedTrees.${field}; not checked` };
  const t1 = Date.now();
  const errs = [];
  const btj = path.join(PINS.storePath('qed64', { id }), 'embedding/base-tree.json');
  let src = 'no embedding/base-tree.json at the pin\'s QED64 commit';
  if (fs.existsSync(btj)) {
    const qd = ((JSON.parse(fs.readFileSync(btj, 'utf8')).trees || {})[tree] || {}).digest;
    src = `${qd === want ? '==' : '!='} QED64 embedding/base-tree.json trees.${tree}`;
    if (qd !== want) errs.push(`pins/${id}/pin.json servedTrees.${field} ${want} != QED64 embedding/base-tree.json trees.${tree}.digest ${qd}`);
  }
  dir = dir || ENV.expandPath(st[key]);
  let got = null;
  if (!dir || !fs.existsSync(dir)) errs.push(`${dir} missing`);
  else { got = treeDigest(dir); if (got.digest !== want) errs.push(`tree digest ${got.digest} (${got.files} files) != servedTrees.${field} ${want}`); }
  const what = got ? `${got.files} files, ${got.bytes} B, ${((Date.now() - t1) / 1000).toFixed(1)} s` : 'not computed';
  return { ok: !errs.length, key, dir, want, got: got && got.digest, line: `G0 ${key} ${dir}: tree digest ${got && got.digest === want ? '==' : '!='} pins/${id}/pin.json servedTrees.${field} ${want.slice(0, 15)}… (${src}; ${what})`, detail: errs.join('; ') };
}
const ENV = await import(path.join(SC, 'scripts/lib/env.mjs'));
if (process.argv[2] === '--check-digest') {
  const [, key, flag, tree] = process.argv.slice(2);
  if (!(key in DIGEST_FIELDS) || (flag !== undefined && (flag !== '--tree' || !tree))) { console.error(`usage: stage-trees.mjs --check-digest ${Object.keys(DIGEST_FIELDS).join('|')} [--tree <dir>]`); process.exit(2); }
  let r;
  try { r = servedDigest(key, tree && path.resolve(tree)); } catch (e) { console.error(`REFUSED: ${e.message}`); process.exit(2); }
  console.log(`${r.skip ? 'SKIP' : r.ok ? 'OK  ' : 'FAIL'} ${r.line}${r.detail ? ' — ' + r.detail : ''}`);
  process.exit(r.ok ? 0 : 1);
}
// ---- the shared trees' records (scripts/lib/staged-tree.mjs; see the header): --check-provenance, --check-native and
// --stock-copy ----
const ST = await import(path.join(SC, 'scripts/lib/staged-tree.mjs'));
if (process.argv[2] === '--check-provenance') {
  const trees = process.argv.slice(3);
  if (!trees.length) { console.error('usage: stage-trees.mjs --check-provenance <tree> [<tree>…]'); process.exit(2); }
  let refused = 0;
  for (const t of trees) { const r = ST.checkProvenance(t); console.log(r.line); if (!r.ok) refused++; }
  process.exit(refused ? 3 : 0);
}
if (process.argv[2] === '--check-native') {
  if (process.argv.length > 3) { console.error('usage: stage-trees.mjs --check-native'); process.exit(2); }
  const r = ST.checkNativeBuild();
  console.log(r.line);
  process.exit(r.ok ? 0 : 3);
}
if (process.argv[2] === '--stock-copy') {
  const [, dir, extra] = process.argv.slice(2);
  if (!dir || extra !== undefined) { console.error('usage: stage-trees.mjs --stock-copy <dir>'); process.exit(2); }
  try {
    const id = PINS.targetPinId(), copy = path.resolve(dir);
    if (!fs.existsSync(copy)) {
      const base = ST.servedPath(id, 'baseSlim');
      if (!fs.existsSync(base)) throw new Error(`pin ${id}'s servedTrees.baseSlim ${base} is missing`);
      fs.rmSync(ST.sourcePath(copy), { force: true }); // a removed copy's sidecar never vouches for a clone that may not finish
      cloneTree(base, copy); // cp -cR on macOS, cp -R --reflink=auto on Linux (scripts/lib/platform.mjs)
      const s = ST.writeStockSource(copy, { id, base });
      console.log(`cloned ${base} -> ${copy}: ${s.n} .olean; ${path.basename(ST.sourcePath(copy))} records pin ${id}`);
    }
    const r = ST.checkStockCopy(copy, { id, g0: () => servedDigest('baseSlim', copy) });
    for (const l of r.lines) console.log(l);
    process.exit(r.rc);
  } catch (e) { console.error(`REFUSED: ${e.message}`); process.exit(2); }
}
const OLEAN_IMPORTS = path.join(PINS.storePath('qed64'), 'pipeline/artifacts/olean-imports.mjs');
const { oleanImportEntries } = await import(OLEAN_IMPORTS);
const { oleanExtEntryCounts } = await import(path.join(SC, 'scripts/lib/olean-entries.mjs'));

// locations: scripts/lib/env.mjs (K = QED64_KERNEL_BUILD, MATHLIB_CLONE, the read-only trees from the env)
const { Q, KR, LG, WS } = ENV;
let K;
try { K = ENV.need('QED64_KERNEL_BUILD'); } catch (e) { console.error(`REFUSED: ${e.message}`); process.exit(2); }
const READ_ONLY = [Q, K, KR, LG, WS].filter(Boolean);

const args = process.argv.slice(2);
// default --core-src / --base-n: the target pin's served core lib (pins/<id>/pin.json servedTrees; scripts/lib/pins.mjs);
// default --clone: its Mathlib clone (scripts/lib/env.mjs MATHLIB_CLONE; '' when it does not resolve, refused below)
const TARGET = PINS.targetPinId();
const SERVED = PINS.pinDescriptor(TARGET).servedTrees;
const opt = { clone: ENV.MATHLIB_CLONE, coreSrc: ENV.expandPath(SERVED.coreSrc),
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
  console.error('usage: stage-trees.mjs --base <tree> --into <tree> (--slim|--fat) --roots A,B,... [--root-headers f.lean,...] [--clone <Mathlib clone>] [--report out.json] [--force]');
  process.exit(2);
}
if (!opt.clone) { try { ENV.need('MATHLIB_CLONE'); } catch (e) { console.error(`REFUSED: ${e.message}`); process.exit(2); } }
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

// ---- G0 served-tree digests (only where the descriptor records them): --base against servedTrees.baseSlim (--slim) or
// servedTrees.baseFat (--fat), --core-src against servedTrees.coreSrc; a tree that is not the pin's served one (e.g. an
// overriding BASE_FAT or --core-src) is noted and not checked ----
const digests = [];
const samePath = (a, b) => { const r = (p) => { try { return fs.realpathSync(p); } catch { return path.resolve(p); } }; return !!a && !!b && r(a) === r(b); };
for (const [key, dir] of [[opt.mode === 'fat' ? 'baseFat' : 'baseSlim', opt.base], ['coreSrc', opt.coreSrc]]) {
  if (!SERVED[DIGEST_FIELDS[key].field]) continue; // the pin records no digest for it (58ebbad: no baseSlimDigest)
  if (!samePath(dir, ENV.expandPath(SERVED[key]))) { console.log(`note G0 ${key}: ${dir} is not the pin's servedTrees.${key}; its digest is not checked`); continue; }
  const r = servedDigest(key, dir);
  digests.push({ key: r.key, dir: r.dir, want: r.want, got: r.got, ok: r.ok });
  gate(r.ok, r.line, r.detail);
}
// ---- N0 native inputs == the target pin's lock (see the header) ----
let LOCK;
try { LOCK = PINS.lockOf(TARGET); } catch (e) { console.error(`REFUSED: pins/${TARGET}/QED64.lock.json unreadable (${e.message}): register the pin first (pin-qed64.mjs pin --pin ${TARGET})`); process.exit(2); }
const TOOLCHAIN = LOCK.toolchain || {};
const readTrim = (p) => { try { return fs.readFileSync(p, 'utf8').trim(); } catch { return null; } };
const sh = (v) => (v ? String(v).slice(0, 12) : 'missing');
let cloneHead = null;
try { cloneHead = execFileSync('git', ['--no-optional-locks', '-C', opt.clone, 'rev-parse', 'HEAD'], { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim(); } catch { /* null: FAIL below */ }
for (const [got, want, what, field] of [
  [cloneHead, TOOLCHAIN.mathlib && TOOLCHAIN.mathlib.commit, `--clone ${opt.clone} HEAD`, 'toolchain.mathlib.commit'],
  [readTrim(path.join(K, 'mathlib/MATHLIB-COMMIT')), TOOLCHAIN.mathlib && TOOLCHAIN.mathlib.commit, 'QED64_KERNEL_BUILD mathlib/MATHLIB-COMMIT', 'toolchain.mathlib.commit'],
  [readTrim(path.join(K, 'BUILT-COMMIT')), TOOLCHAIN.native64 && TOOLCHAIN.native64.BUILT_COMMIT, 'QED64_KERNEL_BUILD BUILT-COMMIT', 'toolchain.native64.BUILT_COMMIT'],
]) {
  gate(!!want && got === want, `N0 ${what} == pins/${TARGET}/QED64.lock.json ${field}`,
    `${sh(got)} vs ${sh(want)}${want && got === want ? '' : ` (a native build of another pin: point QED64_KERNEL_BUILD / MATHLIB_CLONE at pin ${TARGET}'s)`}`);
}
// the native build record N0 vouches for (ST.nativeBuildFile: --clone's own, else out/native-build.json), as read now:
// N0 again (after G6) requires the same file
const nbSeen = () => { const f = ST.nativeBuildFile(opt.clone); try { const s = fs.statSync(f); return `${f}\0${s.mtimeMs}/${s.size}`; } catch { return null; } };
const nbReadAtN0 = ST.nativeBuildFile(opt.clone), nbAtN0 = nbSeen();
{ const r = ST.checkNativeBuild({ id: TARGET, clone: opt.clone, file: nbReadAtN0 }); gate(r.ok, `N0 ${r.line.replace(/^(OK {3}|REFUSED: )/, '')}`); }
// a FAIL so far leaves everything as it was (no report either: --report is the existing tree's, which judge-bake J4 reads)
if (fails) {
  console.log(`STAGE-TREES FAILED (${fails} FAIL) before cloning ${opt.into}: a served tree or a native input is not the one the pin records; ${opt.into}, its EXPECTED-N, record and report are untouched`);
  process.exit(1);
}

// ---- 1. clone the base tree ----
if (fs.existsSync(opt.into) && !opt.force) { console.error(`REFUSED: ${opt.into} exists (pass --force to replace)`); process.exit(2); }
// the tree is replaced from here on: its provenance record goes first, and a new one is written only if every gate passes
ST.removeRecord(opt.into);
if (fs.existsSync(opt.into)) fs.rmSync(opt.into, { recursive: true, force: true });
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
const leanVersion = (h) => h.toString('latin1', 7, 40).replace(/\0+$/, ''); // header bytes 7..40, NUL-padded
const servedLean = leanVersion(servedCoreHeader);
const g1bad = [];
for (const { m, f, dst } of copied) {
  const h = Buffer.alloc(80); const fd = fs.openSync(dst, 'r'); const n = fs.readSync(fd, h, 0, 80, 0); fs.closeSync(fd);
  const p = [];
  if (n < 80 || h.toString('latin1', 0, 5) !== 'olean') p.push('marker');
  if (h[5] !== 2 && h[5] !== 3) p.push(`version ${h[5]}`);
  if (h[6] !== 0) p.push(`flags 0x${h[6].toString(16)}`);
  if (leanVersion(h) !== servedLean) p.push(`Lean ${leanVersion(h) || '?'} != served ${servedLean}`);
  if (kind(m) === 'core') { if (Buffer.compare(h.subarray(0, 80), servedCoreHeader.subarray(0, 80)) !== 0 && h.subarray(40, 80).some((b) => b !== 0)) p.push('core header differs from served core'); }
  else if (h.subarray(40, 80).some((b) => b !== 0)) p.push('githash');
  if (p.length) g1bad.push(`${m}${f}: ${p.join(',')}`);
}
gate(!g1bad.length, `G1 header gate on ${copied.length} delta facet files (olean marker, v2|3, flags 0 = no GMP, Lean ${servedLean} as the served core, empty githash)`, g1bad.slice(0, 5).join('; '));

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

// ---- N0 again (see the header): the clone was not rewritten while it was read ----
{ const r = ST.checkNativeBuild({ id: TARGET, clone: opt.clone }), same = nbSeen() === nbAtN0;
  gate(r.ok && same, `N0 again before the record: ${!r.ok ? r.line.replace(/^REFUSED: /, '')
    : same ? r.line.slice(5) : `${nbReadAtN0 === ST.NATIVE_BUILD ? path.relative(SC, nbReadAtN0) : nbReadAtN0} was replaced since N0 read it: a native step rewrote the clone while it was read; stage again`}`); }

const report = {
  schema: 'qed64-showcase.stage-trees/v1', at: new Date().toISOString(), mode: opt.mode, base: opt.base, into: opt.into,
  roots: rootSet, closure: closure.size, baseN: opt.baseN, expectedN: N, digests,
  delta: { dep: deltaDep, core: deltaCore }, own, facetCounts, facets: facetReport, legacyIr: legacyIrCheck,
  g2: { compared: g2.compared, full: g2.full, tail80: g2.tail80, noNative: g2.noNative, mismatch: g2.mismatch },
  audit: { base: aBase, into: aInto }, fails, seconds: Math.round((Date.now() - t0) / 1000),
};
if (opt.report) fs.writeFileSync(opt.report, JSON.stringify(report, null, 1) + '\n');
if (!fails) { // every gate passed: the tree is the target pin's (scripts/lib/staged-tree.mjs; its readers check this record)
  const rec = ST.writeRecord(opt.into, { mode: opt.mode, id: TARGET, base: opt.base, expectedN: N, report: opt.report || null });
  console.log(`provenance ${path.basename(ST.recordPath(opt.into))}: pin ${rec.pin}, runtime ${rec.buildId}, base ${rec.base}, WIDGETS_SOURCE_HASH ${String(rec.widgetsSourceHash).slice(0, 12)}…`);
}
console.log(fails ? `STAGE-TREES FAILED (${fails} FAIL) ${opt.into}` : `STAGE-TREES OK ${opt.into} EXPECTED-N=${N} (${report.seconds}s)`);
process.exit(fails ? 1 : 0);
