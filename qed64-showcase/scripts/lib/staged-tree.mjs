// staged-tree.mjs — which pin a SHARED olean tree under $W belongs to. The staged trees $W/tree-slim-w7, tree-slim-w8 and
// tree-fat (scripts/stage-trees.mjs, with their .EXPECTED-N and $W/logs/stage-trees-*.json) and the controls' stock copy
// $W/tree-stock (scripts/headless/run-controls.sh) are ONE set for every pin, not per-runtime stores like
// $W/runtimes/<bid>/ (scripts/lib/pins.mjs W_ENTRIES), and so, for the pins of one Mathlib commit, is the native build they
// are staged from (that Mathlib clone's .lake oleans, described by its record below). Pins of one Mathlib commit and widget
// export stage identical trees, which made sharing harmless, but pins differ in either: K's w8 and fat (62a06e2, the
// b81f1b75 widget export) differ from I/J's (c2efe78f), and 521cf3f's trees are Lean 4.35. So `stage` for one pin replaces
// the trees another pin's lanes read, each tree carries a record of what it was made for, and every reader checks that
// record against the TARGET pin (SHOWCASE_PIN, else the active pin) before use: a tree made for another pin is refused,
// never read and never baked against.
//
//   <tree>.STAGED.json   {schema, tree, mode, pin, buildId, base, widgetsSourceHash, expectedN, report, stagedAt}: written by
//                        stage-trees.mjs (writeRecord, tmp + rename) only after every gate of that tree passed, and removed
//                        before the tree is replaced, so a failed or interrupted stage leaves none. checkProvenance: the
//                        target pin's buildId, its expanded served base for the record's mode (servedBase) and its lock's
//                        WIDGETS_SOURCE_HASH; <tree>.EXPECTED-N == expectedN and the stage report (judge-bake J4 reads it)
//                        still this tree's; a missing or unreadable record refuses. The pin named in the record is not
//                        compared: pins of one runtime, base and widget export (58ebbad and 37ff491) share their trees.
//                        widgetsSourceHash is the lock's; stage's N0 (checkNativeBuild) is what ties the clone's widget
//                        oleans to it.
//   <clone>/.lake/showcase-native-build.json  the last COMPLETE `native all`'s record IN that Mathlib clone, for whichever
//                        pin (scripts/native-report.py, which writes the same record to out/native-build.json, the last one
//                        in ANY clone; nativeBuildFile falls back to that only for a clone without its own, one whose last
//                        native all predates per-clone records). Per clone, next to the stamps it is compared with: a native
//                        run in another clone (another Mathlib commit) never revokes it, while the pins that share a clone
//                        (one Mathlib commit, the legacy W/mathlib4) still replace each other's. Any `showcase.sh native`
//                        step that rewrites the clone removes both. checkNativeBuild requires its clone, Mathlib and native
//                        commits and widget export to be the target pin's, and no clone-writing build step stamped in the
//                        clone after it, before stage reads the clone and again (the same file) before it writes the
//                        record (stage-trees.mjs N0), and `showcase.sh all` skips native only then.
//   <copy>.SOURCE.json   {schema, base, pin, n, clonedAt}: written when stage-trees.mjs --stock-copy clones the stock copy
//                        (a sidecar left without its copy is removed before the clone, so an interrupted clone has none).
//                        checkStockCopy: a pin that records servedTrees.baseSlimDigest has the copy G0-checked instead (and a
//                        missing sidecar, or one naming another pin or base, rewritten once that passes); any other pin
//                        needs a sidecar whose base is its expanded servedTrees.baseSlim and an .olean count == its
//                        servedTrees.baseN. A refusal prints the mv that moves the copy aside WITH its sidecar.
// Moving the trees into $W/runtimes/<bid>/ (behind the pin links) is the follow-up; these records make sharing fail closed.
import fs from 'node:fs';
import path from 'node:path';

import { ENV_LOCAL, MATHLIB_CLONE, SC, W, expandPath } from './env.mjs';
import { lockOf, pinDescriptor, targetPinId } from './pins.mjs';

export const STAGED_SCHEMA = 'qed64-showcase.staged-tree/v1';
export const STOCK_SCHEMA = 'qed64-showcase.tree-stock/v1';
/** The staged trees under $W (showcase.sh stage w7 | w8 | fat). */
export const STAGED_TREES = { w7: 'tree-slim-w7', w8: 'tree-slim-w8', fat: 'tree-fat' };
export const recordPath = (tree) => `${path.resolve(tree)}.STAGED.json`;
export const sourcePath = (copy) => `${path.resolve(copy)}.SOURCE.json`;
export const NATIVE_BUILD = path.join(SC, 'out/native-build.json');
/** <clone>/.lake/showcase-native-build.json: the clone's own native build record (see the header) */
export const cloneNativeBuild = (clone) => path.join(clone, '.lake', 'showcase-native-build.json');
/** The native build record N0 reads for `clone`: its own, else out/native-build.json (see the header) */
export const nativeBuildFile = (clone) => (clone && fs.existsSync(cloneNativeBuild(clone)) ? cloneNativeBuild(clone) : NATIVE_BUILD);

// .native: also the on-disk letter case on a case-insensitive volume (APFS), which fs.realpathSync keeps as it was given
const real = (p) => { try { return fs.realpathSync.native(p); } catch { return path.resolve(p); } };
export const samePath = (a, b) => !!a && !!b && real(a) === real(b);
/** The staged tree of W that `dir` is (its real path), also when named through a symlink, an alias of W (/tmp vs
 *  /private/tmp) or another letter case on a case-insensitive volume; else null. */
export const stagedTreeOf = (dir, w = W) => { const r = real(dir); return Object.values(STAGED_TREES).includes(path.basename(r)) && samePath(path.dirname(r), w) ? r : null; };
const short = (h) => (h ? String(h).slice(0, 12) : String(h));
const writeAtomic = (f, obj) => { const tmp = `${f}.tmp-${process.pid}`; fs.writeFileSync(tmp, JSON.stringify(obj, null, 1) + '\n'); fs.renameSync(tmp, f); };
/** `showcase.sh stage` names a tree by w7 | w8 | fat; any other tree: all */
const stageArg = (tree) => Object.keys(STAGED_TREES).find((k) => STAGED_TREES[k] === path.basename(tree)) || 'all';
const restage = (id, tree) => `SHOWCASE_PIN=${id} scripts/showcase.sh stage ${stageArg(tree)} --force`;

const noQ = (id, what) => new Error(`QED64_REPO is not set, and pin ${id}'s ${what}: the readers of its shared trees need it (as stage does) to expand the served base they are compared with; set it in the environment or in ${ENV_LOCAL}`);
/** Pin `id`'s servedTrees.<field>, expanded. One under QED64_REPO (every pin before 521cf3f) needs it set for every reader
 *  of the shared trees, not only for stage (env.mjs's hint names only pin and stage): this says so. Throws. */
export function servedPath(id, field) {
  const v = (pinDescriptor(id).servedTrees || {})[field];
  if (!process.env.QED64_REPO && String(v).includes('${QED64_REPO}')) throw noQ(id, `servedTrees.${field} ${v} lies under it`);
  return path.resolve(expandPath(v));
}
/** The served base tree `stage` clones for `mode` (slim | fat) of pin `id`, expanded, as showcase.sh picks it: BASE_SLIM /
 *  BASE_FAT when set, else servedTrees.baseSlim / baseFat; a pin without baseFat (pins up to 58ebbad): QED64_REPO's
 *  work/lib-tree. Throws when it does not resolve. */
export function servedBase(mode, id = targetPinId()) {
  if (mode === 'slim') return process.env.BASE_SLIM ? path.resolve(process.env.BASE_SLIM) : servedPath(id, 'baseSlim');
  if (mode !== 'fat') throw new Error(`servedBase: mode ${mode} is not slim or fat`);
  if (process.env.BASE_FAT) return path.resolve(process.env.BASE_FAT);
  if ((pinDescriptor(id).servedTrees || {}).baseFat) return servedPath(id, 'baseFat');
  if (!process.env.QED64_REPO) throw noQ(id, 'fat base is its work/lib-tree (the pin records no servedTrees.baseFat)');
  return path.join(process.env.QED64_REPO, 'work', 'lib-tree');
}

/** <tree>.STAGED.json for pin `id`, written atomically. stage-trees.mjs calls it only after every gate passed; `report` is
 *  the stage report it wrote (null without --report). */
export function writeRecord(tree, { mode, id = targetPinId(), base, expectedN, report = null }) {
  tree = path.resolve(tree);
  const rec = { schema: STAGED_SCHEMA, tree: path.basename(tree), mode, pin: id, buildId: pinDescriptor(id).buildId, base: path.resolve(base),
    widgetsSourceHash: lockOf(id).WIDGETS_SOURCE_HASH || null, expectedN, report: report && path.resolve(report), stagedAt: new Date().toISOString() };
  writeAtomic(recordPath(tree), rec);
  return rec;
}
export const removeRecord = (tree) => fs.rmSync(recordPath(tree), { force: true });

/** Is `tree` (a staged tree) the target pin's? {ok, line, rec}: one OK/REFUSED line; a REFUSED line names the pin the tree
 *  was staged for and the restage command. Never throws (anything unreadable refuses). */
export function checkProvenance(tree, { id } = {}) {
  tree = path.resolve(tree);
  const name = path.basename(tree), f = path.basename(recordPath(tree));
  let rec = null;
  const refused = (why, note = '') => ({ ok: false, rec, line: `REFUSED: ${tree} ${why}; restage it for the target pin${note}: ${restage(id || '<id>', tree)}` });
  try {
    id = id || targetPinId();
    try { rec = JSON.parse(fs.readFileSync(recordPath(tree), 'utf8')); } catch (e) {
      return refused(e.code === 'ENOENT'
        ? `has no provenance record ${f} (staged before records existed, by a stage that failed or was interrupted, or not at all), so the pin it was staged for is unknown`
        : `has an unreadable provenance record ${f} (${e.message})`);
    }
    if (!rec || rec.schema !== STAGED_SCHEMA || rec.tree !== name || !['slim', 'fat'].includes(rec.mode)) return refused(`has a provenance record ${f} that is not a ${STAGED_SCHEMA} record of ${name} (schema ${rec && rec.schema}, tree ${rec && rec.tree}, mode ${rec && rec.mode})`);
    if (!fs.existsSync(tree)) return refused(`is missing (its record says pin ${rec.pin})`);
    const want = { buildId: pinDescriptor(id).buildId, base: servedBase(rec.mode, id), hash: lockOf(id).WIDGETS_SOURCE_HASH || null };
    const diffs = [], stale = []; // stale: what stage wrote next to the tree no longer matches its record
    if (rec.buildId !== want.buildId) diffs.push(`runtime ${rec.buildId} != ${want.buildId}`);
    if (!samePath(rec.base, want.base)) diffs.push(`base ${rec.base} != ${want.base}`);
    if ((rec.widgetsSourceHash ?? null) !== want.hash) diffs.push(`WIDGETS_SOURCE_HASH ${short(rec.widgetsSourceHash)}… != pins/${id}/QED64.lock.json ${short(want.hash)}…`);
    let n = null; try { n = Number(fs.readFileSync(`${tree}.EXPECTED-N`, 'utf8').trim()); } catch { /* compared below */ }
    if (n !== rec.expectedN) stale.push(`${name}.EXPECTED-N ${n} != the record's ${rec.expectedN}`);
    if (rec.report) { // the report judge-bake J4 reads the delta from: a later stage-trees run may have written another tree's
      let r = null; try { r = JSON.parse(fs.readFileSync(rec.report, 'utf8')); } catch { /* compared below */ }
      if (!r || !samePath(r.into, tree) || r.expectedN !== rec.expectedN || r.fails !== 0) stale.push(`its stage report ${rec.report} is not this tree's (${r ? `into ${r.into}, expectedN ${r.expectedN}, fails ${r.fails}, ${r.at}` : 'missing or unreadable'})`);
    }
    if (diffs.length) return refused(`was staged for pin ${rec.pin} (${rec.stagedAt}), not for the target pin ${id}: ${[...diffs, ...stale].join('; ')}`,
      ` (this replaces the tree pin ${rec.pin}'s lanes read: they then refuse until it restages)`);
    if (stale.length) return refused(`was staged for pin ${rec.pin} (${rec.stagedAt}), but what stage wrote with it changed since: ${stale.join('; ')}`);
    const what = `(${rec.stagedAt}; runtime ${rec.buildId}, base ${rec.base}, WIDGETS_SOURCE_HASH ${short(rec.widgetsSourceHash)}…, EXPECTED-N ${rec.expectedN})`;
    return { ok: true, rec, line: rec.pin === id ? `OK   ${tree}: staged for the target pin ${id} ${what}`
      : `OK   ${tree}: staged for pin ${rec.pin} ${what}, whose runtime, base and widget export are the target pin ${id}'s` };
  } catch (e) { // not a verdict on the tree (a restage would not help): the record cannot be compared
    return { ok: false, rec, line: `REFUSED: ${tree} cannot be checked against the target pin ${id || '(unresolved)'}: ${e.message}` };
  }
}

// ---- the native build stage reads (its clone's record, else out/native-build.json; see the header) ----
/** build-native.sh's container steps that cannot write the clone's oleans (B1 identity, B2 `lake build --no-build`); every
 *  other step it stamps (delta, widgets, distlens, an adhoc `lake`) may */
const NO_WRITE_STEP = /^(b1-identity|b2-reuse-gate-.*)$/;
/** Is the native build record `file` (default nativeBuildFile(clone)) the target pin's native build, made in `clone`
 *  (stage's --clone; default MATHLIB_CLONE)? {ok, line}: its clone == `clone`, toolchain.mathlibCommit / nativeCommit ==
 *  the lock's toolchain.mathlib.commit / native64.NATIVE_COMMIT, widgetsSourceHash == the lock's WIDGETS_SOURCE_HASH, and
 *  no clone-writing step ran in the clone after it: build-native.sh touches <clone>/.lake/showcase-stamps/<step> as each
 *  container starts, so a writing step's stamp newer than the record (build-native.sh run directly; `showcase.sh native
 *  <step>` removes the records itself) refuses, and so does a clone without stamps (replaced since: every `native all`
 *  leaves them). Pins of one Mathlib commit can share a clone (the legacy W/mathlib4) but not their widget export, and the
 *  clone holds the widget oleans of the last native run only. Never throws. */
export function checkNativeBuild({ id, clone = MATHLIB_CLONE, file = nativeBuildFile(clone) } = {}) {
  const rel = path.relative(SC, file).startsWith('..') ? file : path.relative(SC, file);
  // the fallback (another clone's native all may have replaced it since): a refusal says the clone has no record of its own
  const own = clone && file === NATIVE_BUILD && !fs.existsSync(cloneNativeBuild(clone)) ? ` (${clone} has no .lake/showcase-native-build.json of its own)` : '';
  const refused = (why) => ({ ok: false, line: `REFUSED: ${rel} ${why}${own}; with $W/widgets-src exported at pin ${id || '<id>'}'s WIDGETS_COMMIT, run \`SHOWCASE_PIN=${id || '<id>'} scripts/showcase.sh native all\` first (it rebuilds the clone's widget oleans and its record)` });
  try {
    id = id || targetPinId();
    let nb; try { nb = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) {
      return refused(e.code === 'ENOENT' ? 'is missing: nothing says which pin\'s native build the Mathlib clone holds' : `is unreadable (${e.message})`);
    }
    const lock = lockOf(id), tc = lock.toolchain || {}, t = nb.toolchain || {};
    const diffs = [];
    if (!clone || !samePath(nb.clone, clone)) diffs.push(`clone ${nb.clone} != ${clone || `(MATHLIB_CLONE does not resolve for pin ${id})`}`);
    for (const [what, got, want, field] of [['toolchain.mathlibCommit', t.mathlibCommit, tc.mathlib && tc.mathlib.commit, 'toolchain.mathlib.commit'],
      ['toolchain.nativeCommit', t.nativeCommit, tc.native64 && tc.native64.NATIVE_COMMIT, 'toolchain.native64.NATIVE_COMMIT'],
      ['widgetsSourceHash', nb.widgetsSourceHash, lock.WIDGETS_SOURCE_HASH, 'WIDGETS_SOURCE_HASH']]) {
      if (!want || got !== want) diffs.push(`${what} ${short(got)}… != pins/${id}/QED64.lock.json ${field} ${short(want)}…`);
    }
    if (diffs.length) return refused(`is not pin ${id}'s native build: ${diffs.join('; ')}`);
    const sd = path.join(clone, '.lake/showcase-stamps'), at = fs.statSync(file).mtimeMs;
    let later; try { later = fs.readdirSync(sd).filter((s) => !NO_WRITE_STEP.test(s) && fs.statSync(path.join(sd, s)).mtimeMs > at); } catch (e) {
      return refused(`names ${clone}, which has no readable ${sd} (${e.code || e.message}): whether its oleans were rebuilt since is unknown`);
    }
    if (later.length) return refused(`is older than the build step${later.length > 1 ? 's' : ''} ${later.join(', ')} in its clone (${sd}): the clone's oleans may have changed since the last complete native all`);
    return { ok: true, line: `OK   ${rel}: pin ${id}'s native build (clone ${nb.clone}, Mathlib ${short(t.mathlibCommit)}…, native ${short(t.nativeCommit)}…, widget export ${short(nb.widgetsSourceHash)}…)` };
  } catch (e) { return { ok: false, line: `REFUSED: ${rel} cannot be checked against the target pin ${id || '(unresolved)'}: ${e.message}` }; }
}

// ---- the controls' stock copy ($W/tree-stock) ----
/** Number of .olean files under `dir`. */
export function countOleans(dir) {
  let n = 0;
  const walk = (d) => { for (const e of fs.readdirSync(d, { withFileTypes: true })) { if (e.isDirectory()) walk(path.join(d, e.name)); else if (e.name.endsWith('.olean')) n++; } };
  walk(dir);
  return n;
}
/** <copy>.SOURCE.json: the served tree `base` the copy was cloned from for pin `id`, written atomically. */
export function writeStockSource(copy, { id = targetPinId(), base }) {
  const rec = { schema: STOCK_SCHEMA, base: path.resolve(base), pin: id, n: countOleans(copy), clonedAt: new Date().toISOString() };
  writeAtomic(sourcePath(copy), rec);
  return rec;
}
/** The exact command that moves the copy aside (to a name not in use) together with its sidecar, so the sidecar stays with
 *  the copy it describes (a copy moved back brings its own) and the next run clones the copy again. */
export function asideCommand(copy, pin) {
  copy = path.resolve(copy);
  const stem = `${copy}.prev-${pin || 'unrecorded'}`;
  let dest = stem;
  for (let i = 2; fs.existsSync(dest) || fs.existsSync(sourcePath(dest)); i++) dest = `${stem}-${i}`;
  const mv = `mv "${copy}" "${dest}"`;
  return fs.existsSync(sourcePath(copy)) ? `${mv} && mv "${sourcePath(copy)}" "${sourcePath(dest)}"` : mv;
}
/** The stock copy before use, for pin `id`: {rc, lines}, rc 0 OK, 1 the G0 digest FAILs, 3 refused. `g0()` is the G0
 *  check of the copy (stage-trees.mjs servedDigest('baseSlim', copy)); it is called only for a pin that records
 *  servedTrees.baseSlimDigest. Every refusal names the pin the copy was cloned for and the command that moves it aside. */
export function checkStockCopy(copy, { id = targetPinId(), g0 } = {}) {
  copy = path.resolve(copy);
  const st = pinDescriptor(id).servedTrees || {};
  const want = servedPath(id, 'baseSlim');
  const sf = sourcePath(copy), sname = path.basename(sf);
  let src = null, unreadable = '';
  try { src = JSON.parse(fs.readFileSync(sf, 'utf8')); } catch (e) { if (e.code !== 'ENOENT') unreadable = e.message; }
  if (src && (src.schema !== STOCK_SCHEMA || !src.base)) { unreadable = `not a ${STOCK_SCHEMA} record`; src = null; }
  const from = src ? ` (cloned for pin ${src.pin} from ${src.base}, ${sname})` : unreadable ? ` (${sname} unreadable: ${unreadable})` : ` (no ${sname})`;
  const aside = `move it aside and rerun, which clones it again from pin ${id}'s servedTrees.baseSlim ${want}: ${asideCommand(copy, src && src.pin)}`;
  if (st.baseSlimDigest) {
    const r = g0();
    if (!r.ok) return { rc: 1, lines: [`FAIL ${r.line}${r.detail ? ' — ' + r.detail : ''}`, `REFUSED: ${copy} is not pin ${id}'s base tree${from}; ${aside}`] };
    const lines = [`OK   ${r.line}`];
    // the digest proves the copy is this pin's base: a sidecar that is missing or names another pin / base (a copy moved
    // back, or one that predates sidecars) would mislead the next pin's refusal, so it is (re)written for this pin
    if (!src || src.pin !== id || !samePath(src.base, want)) {
      const s = writeStockSource(copy, { id, base: want });
      lines.push(`OK   ${sname} ${src ? `rewritten after G0 (it said pin ${src.pin}, base ${src.base})` : 'backfilled after G0'}: pin ${id}, base ${s.base}, ${s.n} .olean`);
    }
    return { rc: 0, lines };
  }
  if (!src) return { rc: 3, lines: [`REFUSED: ${copy} cannot be tied to pin ${id}${from}: the pin records no servedTrees.baseSlimDigest (no G0), so only the record of the tree the copy was cloned from can tell; ${aside}`] };
  const n = countOleans(copy), errs = [];
  if (!samePath(src.base, want)) errs.push(`base ${src.base} != pin ${id}'s servedTrees.baseSlim ${want}`);
  if (n !== st.baseN) errs.push(`${n} .olean != servedTrees.baseN ${st.baseN}`);
  if (errs.length) return { rc: 3, lines: [`REFUSED: ${copy}${from} is not pin ${id}'s base tree: ${errs.join('; ')}; ${aside}`] };
  return { rc: 0, lines: [`OK   ${copy}: cloned for pin ${src.pin} from ${src.base} (${sname}) == pin ${id}'s servedTrees.baseSlim; ${n} .olean == baseN (the pin records no baseSlimDigest: no G0)`] };
}
