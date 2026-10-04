#!/usr/bin/env node
// fetch-vendor.mjs — materialize pins/<id>/vendor-qed64 (the QED64 sources this project reads: the snapshot pipeline,
// the olean reader, the workers, the boot/session code) from a QED64 checkout, verified against the COMMITTED
// pins/<id>/QED64-PIN (sha256 of every file) and the lock's vendor.pinSha256. The vendored files are not committed:
// they are `git archive <QED64 commit> <lock.vendor.paths>` of the public QED64 repository, so a clone fetches them.
//
//   node scripts/fetch-vendor.mjs [--pin <id> | --all] [--check] [--into <dir>]
//     default: every registered pin whose vendor-qed64 is missing or does not verify
//     --check        write nothing; exit 0 iff every selected pin's vendor-qed64 verifies against its QED64-PIN
//     --into <dir>   write <dir>/<id>/vendor-qed64 instead of pins/<id>/ (a dry rehearsal; nothing in pins/ changes)
// Needs QED64_REPO (a QED64 clone that contains the pinned commits; read-only: git archive with --no-optional-locks).
// An existing vendor-qed64 that does not verify is MOVED aside (vendor-qed64.prev-<time>), never deleted.
import { execFileSync, spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { SC, need } from './lib/env.mjs';
import { listPins, repoPinDir, lockOf, ID_RE } from './lib/pins.mjs';

const args = process.argv.slice(2);
const flag = (f) => args.includes(f);
const val = (f) => { const i = args.indexOf(f); return i >= 0 ? args[i + 1] : null; };
const sha = (b) => createHash('sha256').update(b).digest('hex');
function walk(dir, base = dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, base, out); else if (e.isFile()) out.push(path.relative(base, p));
  }
  return out.sort();
}
/** Verify a vendor dir against pins/<id>/QED64-PIN and the lock: returns a list of problems (empty = OK). */
function verifyVendor(id, dir) {
  const pinFile = path.join(repoPinDir(id), 'QED64-PIN');
  const pinText = fs.readFileSync(pinFile, 'utf8');
  const lock = lockOf(id);
  const bad = [];
  if (sha(Buffer.from(pinText)) !== lock.vendor.pinSha256) bad.push(`QED64-PIN sha256 != lock vendor.pinSha256`);
  if (!fs.existsSync(dir)) return [...bad, `${path.relative(SC, dir)} missing`];
  const want = new Map(pinText.split('\n').filter((l) => l && !l.startsWith('#')).map((l) => { const [h, ...r] = l.split('  '); return [r.join('  '), h]; }));
  const have = walk(dir);
  for (const f of have) if (!want.has(f)) bad.push(`extra ${f}`);
  for (const [f, h] of want) if (!fs.existsSync(path.join(dir, f))) bad.push(`missing ${f}`); else if (sha(fs.readFileSync(path.join(dir, f))) !== h) bad.push(`sha256 ${f}`);
  if (want.size !== lock.vendor.files) bad.push(`QED64-PIN lists ${want.size} files, lock vendor.files ${lock.vendor.files}`);
  return bad;
}
async function archive(Q, commit, paths, into) {
  fs.mkdirSync(into, { recursive: true });
  await new Promise((res, rej) => {
    const ga = spawn('git', ['--no-optional-locks', '-C', Q, 'archive', commit, ...paths], { stdio: ['ignore', 'pipe', 'inherit'] });
    const tar = spawn('tar', ['-x', '-C', into], { stdio: ['pipe', 'inherit', 'inherit'] });
    ga.stdout.pipe(tar.stdin);
    let n = 0; const done = (c, who) => { if (c !== 0) rej(new Error(`${who} exit ${c}`)); else if (++n === 2) res(); };
    ga.on('close', (c) => done(c, 'git archive')); tar.on('close', (c) => done(c, 'tar'));
  });
}

const one = val('--pin');
if (one && !ID_RE.test(one)) { console.error(`--pin needs a 7-hex pin id (got ${one})`); process.exit(2); }
const ids = one ? [one] : listPins().map((p) => p.id);
const into = val('--into');
let fails = 0;
for (const id of ids) {
  const target = into ? path.join(path.resolve(into), id, 'vendor-qed64') : path.join(repoPinDir(id), 'vendor-qed64');
  const pre = verifyVendor(id, target);
  if (!pre.length) { console.log(`OK   pins/${id}: ${path.relative(SC, target)} verifies against QED64-PIN (${lockOf(id).vendor.files} files)`); continue; }
  if (flag('--check')) { console.log(`FAIL pins/${id}: ${pre.slice(0, 4).join('; ')}`); fails++; continue; }
  let Q;
  try { Q = need('QED64_REPO'); } catch (e) { console.error(`fetch-vendor: ${e.message}`); process.exit(2); }
  const lock = lockOf(id);
  const commit = lock.qed64.commit;
  try { execFileSync('git', ['--no-optional-locks', '-C', Q, 'cat-file', '-e', `${commit}^{commit}`]); }
  catch { console.log(`FAIL pins/${id}: QED64 commit ${commit} is not in ${Q} (git -C <QED64> fetch, then retry)`); fails++; continue; }
  const tmp = `${target}.new.${process.pid}`;
  await archive(Q, commit, lock.vendor.paths, tmp);
  const post = verifyVendor(id, tmp);
  if (post.length) { console.log(`FAIL pins/${id}: git archive ${commit.slice(0, 7)} does not match QED64-PIN: ${post.slice(0, 4).join('; ')} (left in ${tmp})`); fails++; continue; }
  if (fs.existsSync(target)) { const prev = `${target}.prev-${new Date().toISOString().replace(/[:.]/g, '-')}`; fs.renameSync(target, prev); console.log(`     moved the non-verifying ${path.relative(SC, target)} to ${prev}`); }
  fs.renameSync(tmp, target);
  console.log(`OK   pins/${id}: fetched ${lock.vendor.files} files (git archive ${commit.slice(0, 12)}) -> ${into ? target : path.relative(SC, target)}, sha256 == QED64-PIN`);
}
console.log(fails ? `FETCH-VENDOR FAILED (${fails})` : 'FETCH-VENDOR OK');
process.exit(fails ? 1 : 0);
