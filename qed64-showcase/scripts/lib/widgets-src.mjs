// widgets-src.mjs — the widget sources the native build compiles: $W/widgets-src, a `git archive` export of this
// repository's packages/ at ONE commit (the prefix packages/ stripped, so the layout is <pkg>/…, as the clone's
// lakefile-append srcDirs "widgets/<pkg>" expect). Used by scripts/export-widgets.mjs (writes it) and
// scripts/pin-qed64.mjs (record-widgets-hash, verify).
//
// WIDGETS_SOURCE_HASH = sha256 over the concatenation of "<sha256>  <relpath>\n" for every file of the export except the
// metadata files (META), ordered by relpath in byte (LC_ALL=C) order. That is exactly the bytes of SOURCE-FILES.sha256,
// so sha256(SOURCE-FILES.sha256) == SOURCE-HASH.txt line 1. WIDGETS_COMMIT (SOURCE-COMMIT.txt line 1, and the lock) is
// the commit the export was archived from; verify re-derives every file's git blob id from the bytes and compares it
// with `git ls-tree -r <commit> packages/`.
import { execFileSync, spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { REPO_ROOT, W } from './env.mjs';

export const WIDGETS_SRC = path.join(W, 'widgets-src');
export const PREFIX = 'packages';
export const META = new Set(['SOURCE-HASH.txt', 'SOURCE-FILES.sha256', 'SOURCE-COMMIT.txt']);
export const ALGORITHM = 'sha256 of concatenated "<sha256>  <relpath>\\n" lines, relpaths in byte order, excluding SOURCE-HASH.txt, SOURCE-FILES.sha256 and SOURCE-COMMIT.txt';
export const UPSTREAM = 'https://github.com/FawadHa1der/lean-widgets';

export const git = (...a) => execFileSync('git', ['--no-optional-locks', '-C', REPO_ROOT, ...a], { maxBuffer: 1 << 30 });
const sha256Buf = (b) => createHash('sha256').update(b).digest('hex');
export const gitBlobId = (b) => createHash('sha1').update(`blob ${b.length}\0`).update(b).digest('hex');

export function walk(dir, base = dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, base, out);
    else if (e.isFile()) out.push(path.relative(base, p));
    else throw new Error(`unexpected non-file ${p}`);
  }
  return out;
}
const byteOrder = (a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b));

/** { hash, files, listing } over the export in `dir` (see the header). */
export function widgetsSourceHash(dir = WIDGETS_SRC) {
  const rels = walk(dir).filter((f) => !META.has(f)).sort(byteOrder);
  let listing = '';
  for (const f of rels) listing += `${sha256Buf(fs.readFileSync(path.join(dir, f)))}  ${f}\n`;
  return { hash: sha256Buf(Buffer.from(listing)), files: rels.length, listing };
}
export const recordedHash = (dir = WIDGETS_SRC) => fs.readFileSync(path.join(dir, 'SOURCE-HASH.txt'), 'utf8').split('\n')[0].trim();
export function recordedCommit(dir = WIDGETS_SRC) {
  const f = path.join(dir, 'SOURCE-COMMIT.txt');
  return fs.existsSync(f) ? fs.readFileSync(f, 'utf8').split('\n')[0].trim() : null;
}
/** The default commit to export: the newest commit that changed packages/ (commits elsewhere in the repo do not
 *  change what the native build compiles, so they do not move the pin). */
export const lastPackagesCommit = () => git('log', '-1', '--format=%H', '--', PREFIX).toString().trim();
export const resolveCommit = (rev) => git('rev-parse', '--verify', `${rev}^{commit}`).toString().trim();
export const packagesTree = (rev) => git('rev-parse', `${rev}:${PREFIX}`).toString().trim();

/** Compare the export in `dir` with `git ls-tree -r <commit> packages/`: same file set, same blob ids. */
export function compareWithCommit(commit, dir = WIDGETS_SRC) {
  const tree = new Map();
  for (const l of git('ls-tree', '-r', commit, '--', `${PREFIX}/`).toString().trim().split('\n').filter(Boolean)) {
    const [meta, p] = l.split('\t'); const [mode, type, id] = meta.split(' ');
    if (type !== 'blob') throw new Error(`${p}: ${type} entries are not supported in packages/`);
    tree.set(p.slice(PREFIX.length + 1), { id, mode });
  }
  const have = walk(dir).filter((f) => !META.has(f));
  const missing = [...tree.keys()].filter((f) => !have.includes(f));
  const extra = have.filter((f) => !tree.has(f));
  const differ = have.filter((f) => tree.has(f) && tree.get(f).id !== gitBlobId(fs.readFileSync(path.join(dir, f))));
  return { files: tree.size, missing, extra, differ, ok: !missing.length && !extra.length && !differ.length };
}

/** Write a fresh export of `commit` into `into` (must not exist): git archive | tar -x --strip-components=1. */
export async function exportInto(commit, into) {
  fs.mkdirSync(into, { recursive: false });
  await new Promise((res, rej) => {
    const ga = spawn('git', ['--no-optional-locks', '-C', REPO_ROOT, 'archive', '--format=tar', commit, `${PREFIX}/`], { stdio: ['ignore', 'pipe', 'inherit'] });
    const tar = spawn('tar', ['-x', '--strip-components=1', '-C', into], { stdio: ['pipe', 'inherit', 'inherit'] });
    ga.stdout.pipe(tar.stdin);
    let n = 0; const done = (c, who) => { if (c !== 0) rej(new Error(`${who} exit ${c}`)); else if (++n === 2) res(); };
    ga.on('close', (c) => done(c, 'git archive')); tar.on('close', (c) => done(c, 'tar'));
  });
  const { hash, files, listing } = widgetsSourceHash(into);
  fs.writeFileSync(path.join(into, 'SOURCE-FILES.sha256'), listing);
  fs.writeFileSync(path.join(into, 'SOURCE-HASH.txt'), `${hash}\n# sha256 over the LC_ALL=C-sorted list of "<sha256>  <relpath>" lines (SOURCE-FILES.sha256, ${files} files)\n# source: git archive ${commit} ${PREFIX}/ (prefix stripped) of ${UPSTREAM}\n`);
  fs.writeFileSync(path.join(into, 'SOURCE-COMMIT.txt'), `${commit}\n# the widget-repository commit this export was archived from (git archive ${commit} ${PREFIX}/); scripts/export-widgets.mjs\n`);
  return { hash, files };
}
