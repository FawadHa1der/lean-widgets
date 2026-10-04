#!/usr/bin/env node
// build-shell.mjs — QED64's page ("the shell": release/<id>/dist) built FROM SOURCE, never copied (docs/ARCHITECTURE.md
// "Shell from source"). In the pin's QED64 source checkout (the submodule deps/qed64 at the active pin's commit, or the
// pin's git worktree; scripts/lib/qed64-src.mjs) it runs QED64's own build:
//
//   npm ci --prefix frontend          (frontend/package-lock.json, exact versions)
//   npm run build:site                (= npm --prefix frontend run build = vite build -> <source>/dist, QED64's gitignored output)
//
// then compares EVERY built file with the lock (pins/<id>/QED64.lock.json release.files dist/*: same file set, same size,
// same sha256). The build is deterministic: on 2026-10-04 fresh public clones of all five pinned commits rebuilt their
// 58 dist files byte-identical to the served releases (macOS, Node v26.3.0; and in node:26-bookworm on Linux, Node
// v26.7.0: docs/ARCHITECTURE.md). So the lock's sha256s ARE the check: nothing is installed unless every file matches,
// and a mismatch is reported file by file (never skipped, never "close enough").
//
//   node scripts/build-shell.mjs [--pin <id>] [--no-install] [--keep-going]
//     default       build, compare, and install into release/<id>/dist when every file matches (an existing dist that
//                   already matches is left as it is; one that does not is moved to dist.prev-<time>, never deleted)
//     --no-install  build and compare only
// Writes a provenance record to out/pins/shell-build-<id>.json (node/npm versions, source commit, per-file result).
// Exit: 0 every file == lock · 1 a build step failed or a file differs · 2 usage/setup.
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PINS = await import(path.join(SC, 'scripts/lib/pins.mjs'));
const QSRC = await import(path.join(SC, 'scripts/lib/qed64-src.mjs'));
const { cloneFile } = await import(path.join(SC, 'scripts/lib/platform.mjs'));

const argv = process.argv.slice(2);
const pi = argv.indexOf('--pin');
const ID = pi >= 0 ? argv[pi + 1] : PINS.targetPinId();
const NO_INSTALL = argv.includes('--no-install');
for (const a of argv) if (a.startsWith('--') && !['--pin', '--no-install'].includes(a)) { console.error(`build-shell: unknown argument ${a}`); process.exit(2); }
let DESC, LOCK;
try { DESC = PINS.pinDescriptor(ID); LOCK = PINS.lockOf(ID); } catch (e) { console.error(`build-shell: ${e.message}`); process.exit(2); }
const COMMIT = DESC.qed64.commit;
const R = PINS.releaseOf(ID);

const sha256 = (p) => createHash('sha256').update(fs.readFileSync(p)).digest('hex');
function walk(dir, base = dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, base, out); else if (e.isFile()) out.push(path.relative(base, p).split(path.sep).join('/'));
    else throw new Error(`unexpected non-file ${p}`);
  }
  return out.sort();
}
const want = Object.fromEntries(Object.entries(LOCK.release.files).filter(([f]) => f.startsWith('dist/')).map(([f, m]) => [f.slice(5), m]));

let src;
try { src = QSRC.ensureSrc(COMMIT, ID, (m) => console.log(m)); } catch (e) { console.error(`build-shell: ${e.message}`); process.exit(2); }
const mod = execFileSync('git', ['-C', src, 'status', '--porcelain', '--untracked-files=no']).toString().trim();
if (mod) { console.error(`build-shell: ${src} has modified tracked files; refusing to build a shell that is not the pinned commit:\n${mod}`); process.exit(2); }
const ver = (c) => { try { return execFileSync(c, ['--version']).toString().trim(); } catch { return null; } };
const prov = { pin: ID, commit: COMMIT, source: path.relative(SC, src).startsWith('..') ? src.replace(PINS.W, '$W') : path.relative(SC, src), node: process.version, npm: ver('npm'), platform: `${process.platform}-${process.arch}`, started: new Date().toISOString() };
console.log(`build-shell: pin ${ID} (QED64 ${COMMIT.slice(0, 12)}) in ${prov.source}; node ${prov.node}, npm ${prov.npm}, ${prov.platform}`);

const run = (what, cmd, args) => {
  const t0 = Date.now();
  console.log(`+ (cd ${prov.source} && ${cmd} ${args.join(' ')})`);
  const r = spawnSync(cmd, args, { cwd: src, stdio: 'inherit', env: { ...process.env, CI: process.env.CI || '1' } });
  prov[what] = { rc: r.status, ms: Date.now() - t0 };
  if (r.status !== 0) { console.error(`build-shell: ${what} failed rc=${r.status}`); finish(1); }
};
function finish(rc, extra = {}) {
  Object.assign(prov, extra, { ended: new Date().toISOString(), rc });
  fs.mkdirSync(path.join(SC, 'out', 'pins'), { recursive: true });
  fs.writeFileSync(path.join(SC, 'out', 'pins', `shell-build-${ID}.json`), JSON.stringify(prov, null, 2) + '\n');
  process.exit(rc);
}

run('npmCi', 'npm', ['ci', '--prefix', 'frontend', '--no-audit', '--no-fund']);
run('build', 'npm', ['run', 'build:site']);

// compare: the built dist/ against the lock, file by file
const D = path.join(src, 'dist');
const have = fs.existsSync(D) ? walk(D) : [];
const missing = Object.keys(want).filter((f) => !have.includes(f));
const extra = have.filter((f) => !(f in want));
const differ = [];
for (const f of have) if (f in want) { const st = fs.statSync(path.join(D, f)); const h = sha256(path.join(D, f)); if (st.size !== want[f].bytes || h !== want[f].sha256) differ.push({ f, bytes: st.size, want: want[f].bytes, sha256: h }); }
const same = have.length - extra.length - differ.length;
console.log(`compare: ${have.length} built files vs ${Object.keys(want).length} in the lock: ${same} byte-identical, ${differ.length} differ, ${missing.length} missing, ${extra.length} extra`);
for (const d of differ.slice(0, 20)) console.log(`  DIFFERS dist/${d.f}: ${d.bytes} B sha256 ${d.sha256.slice(0, 16)}… (lock ${d.want} B ${want[d.f].sha256.slice(0, 16)}…)`);
for (const f of missing.slice(0, 20)) console.log(`  MISSING dist/${f}`);
for (const f of extra.slice(0, 20)) console.log(`  EXTRA   dist/${f}`);
const result = { files: have.length, identical: same, differ, missing, extra };
if (differ.length || missing.length || extra.length) {
  console.log(`SHELL-FROM-SOURCE FAILED: the build of ${COMMIT.slice(0, 12)} is not byte-identical to the lock; nothing installed (see docs/ARCHITECTURE.md "Shell from source")`);
  finish(1, { result });
}
console.log(`SHELL-FROM-SOURCE OK: all ${same} dist files built from ${COMMIT.slice(0, 12)} == pins/${ID}/QED64.lock.json (sha256)`);
if (NO_INSTALL) finish(0, { result, installed: false });

// install: release/<id>/dist from the verified build (copy-on-write clones; new inodes, never hard links)
const RD = path.join(R, 'dist');
const current = fs.existsSync(RD) ? walk(RD) : null;
const currentOk = current && current.length === Object.keys(want).length && current.every((f) => f in want && fs.statSync(path.join(RD, f)).size === want[f].bytes && sha256(path.join(RD, f)) === want[f].sha256);
if (currentOk) { console.log(`release/${ID}/dist already holds exactly these ${current.length} files (sha256 == lock): left as it is`); finish(0, { result, installed: 'already-identical' }); }
const tmp = path.join(R, `dist.new-${process.pid}`);
fs.mkdirSync(tmp, { recursive: true });
for (const f of have) { fs.mkdirSync(path.dirname(path.join(tmp, f)), { recursive: true }); cloneFile(path.join(D, f), path.join(tmp, f)); }
for (const f of have) if (sha256(path.join(tmp, f)) !== want[f].sha256) { console.log(`FAIL copy of dist/${f} != lock`); finish(1, { result }); }
let prev = null;
if (fs.existsSync(RD)) { prev = `${RD}.prev-${new Date().toISOString().replace(/[:.]/g, '-')}`; fs.renameSync(RD, prev); }
fs.renameSync(tmp, RD);
console.log(`installed release/${ID}/dist (${have.length} files, sha256 == lock)${prev ? `; the previous dist (not matching the lock) moved to ${path.relative(SC, prev)}` : ''}`);
finish(0, { result, installed: true, previous: prev && path.relative(SC, prev) });
