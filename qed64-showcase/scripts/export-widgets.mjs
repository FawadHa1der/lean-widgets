#!/usr/bin/env node
// export-widgets.mjs — (re)create $W/widgets-src, the widget sources the native build compiles, as a `git archive` of
// this repository's packages/ at one commit (scripts/lib/widgets-src.mjs). Nothing is deleted: a previous export that
// differs is MOVED to $W/widgets-src.prev-<UTC time>.
//
//   node scripts/export-widgets.mjs [--commit <rev>] [--check]
//     --commit <rev>   the commit to export (default: the newest commit that changed packages/)
//     --check          write nothing; exit 0 iff $W/widgets-src is exactly that commit's packages/ (file set + blob ids)
//                      and its SOURCE-HASH.txt / SOURCE-COMMIT.txt match
// Refuses (exit 3) when packages/ has uncommitted changes and no --commit is given: the export is taken from git
// objects, so uncommitted edits would silently not be in it.
// After a new export, record it in a pin's lock: node scripts/pin-qed64.mjs record-widgets-hash [--pin <id>].
import fs from 'node:fs';
import path from 'node:path';
import { W } from './lib/env.mjs';
import { WIDGETS_SRC, PREFIX, git, lastPackagesCommit, resolveCommit, exportInto, compareWithCommit, widgetsSourceHash, recordedHash, recordedCommit } from './lib/widgets-src.mjs';

const args = process.argv.slice(2);
const ci = args.indexOf('--commit');
const check = args.includes('--check');
try {
  if (ci < 0 && !check) {
    const dirty = git('status', '--porcelain', '--', `${PREFIX}/`).toString().trim();
    if (dirty) { console.error(`REFUSED: ${PREFIX}/ has uncommitted changes (commit them first, or pass --commit <rev>):\n${dirty}`); process.exit(3); }
  }
  const commit = resolveCommit(ci >= 0 ? args[ci + 1] : lastPackagesCommit());
  const cur = fs.existsSync(WIDGETS_SRC) ? (() => {
    const cmp = compareWithCommit(commit);
    const h = widgetsSourceHash();
    let rh = null, rc = null; try { rh = recordedHash(); rc = recordedCommit(); } catch {}
    return { cmp, hash: h.hash, files: h.files, same: cmp.ok && rh === h.hash && rc === commit };
  })() : null;
  if (check) {
    if (!cur) { console.log(`EXPORT MISSING: ${WIDGETS_SRC}`); process.exit(1); }
    const { cmp } = cur;
    console.log(`${cur.same ? 'EXPORT OK' : 'EXPORT DIFFERS'}: ${WIDGETS_SRC} vs git archive ${commit.slice(0, 12)} ${PREFIX}/ (${cmp.files} files; missing ${cmp.missing.length}, extra ${cmp.extra.length}, differing ${cmp.differ.length}; recorded commit ${recordedCommit() || 'none'}), hash ${cur.hash.slice(0, 16)}…`);
    process.exit(cur.same ? 0 : 1);
  }
  if (cur && cur.same) { console.log(`EXPORT UNCHANGED: ${WIDGETS_SRC} already is git archive ${commit} ${PREFIX}/ (${cur.files} files, WIDGETS_SOURCE_HASH ${cur.hash})`); process.exit(0); }
  fs.mkdirSync(W, { recursive: true });
  const tmp = `${WIDGETS_SRC}.new.${process.pid}`;
  const { hash, files } = await exportInto(commit, tmp);
  const v = compareWithCommit(commit, tmp);
  if (!v.ok) throw new Error(`fresh export does not match git ls-tree ${commit}: ${JSON.stringify(v).slice(0, 300)}`);
  if (fs.existsSync(WIDGETS_SRC)) {
    const prev = `${WIDGETS_SRC}.prev-${new Date().toISOString().replace(/[:.]/g, '-')}`;
    fs.renameSync(WIDGETS_SRC, prev);
    console.log(`moved the previous export to ${prev}`);
  }
  fs.renameSync(tmp, WIDGETS_SRC);
  console.log(`EXPORTED ${WIDGETS_SRC}: git archive ${commit} ${PREFIX}/ (${files} files), WIDGETS_SOURCE_HASH ${hash}`);
  console.log(`next: node scripts/pin-qed64.mjs record-widgets-hash --pin <id>   (for every pin built from it)`);
} catch (e) { console.error(`export-widgets: ${e.message}`); process.exit(1); }
