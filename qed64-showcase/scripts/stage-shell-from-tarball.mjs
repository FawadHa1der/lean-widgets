#!/usr/bin/env node
// stage-shell-from-tarball.mjs — build the Worker's static-assets tree WITHOUT release/ (option B of the CI template,
// .github/workflows/deploy-showcase.yml.example; docs/DEPLOY-CLOUDFLARE.md "CI"). A clean checkout has no release/
// (gitignored, 2.4 GB with the artifacts), so CI gets only the pinned QED64 dist/ (plus the pinned runtime manifest,
// a few KB, which the gallery gate needs) as a tarball made on the owner's machine, exactly as in the guide (section 9):
//   ID=$(node scripts/lib/pins.mjs active); BID=$(node scripts/lib/pins.mjs active-bid)
//   COPYFILE_DISABLE=1 tar --no-xattrs -C release/$ID -czf qed64-dist-$ID.tar.gz dist public/runtime/runtime-manifest.$BID.json
// (COPYFILE_DISABLE=1 --no-xattrs: macOS tar otherwise adds ._* AppleDouble files, which T1 refuses as extra files)
// and this script stages it:
//   node scripts/stage-shell-from-tarball.mjs <dist tarball> [--out out/deploy/assets] [--release-dir]
// --release-dir also writes the verified dist/ and runtime manifest to the lock's release dir (release/<pin id>/,
// which must not exist yet), so that `node scripts/check-gallery.mjs` (the G1 gallery gate: build-gallery --check
// reads the pinned bundle and the runtime manifest from there) can run in a clean checkout before the deploy.
// Every dist file must have the size and sha256 QED64.lock.json (release.files["dist/…"]) records, and the tarball must
// hold exactly the lock's dist files: a stale or tampered tarball cannot be deployed. The gallery is copied from the
// checkout with the same shipped-file rule as deploy-manifest.mjs (scripts/lib/gallery-hash.mjs). Then: the 25 MiB
// per-file cap, no runtime/ profiles/ snapshots/ in the tree, gallery/pin.json buildId == lock buildId. The result is
// byte-identical to `deploy-manifest.mjs --stage-assets` for the same lock and gallery (checked in the rehearsal).
// It does NOT run the manifest's R/G gates (they need the artifacts and the UX record): CI can only redeploy a shell
// whose artifacts a manual scripts/upload-artifacts.sh already published.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { galleryFiles, isShippedGalleryFile, galleryContentHash } from './lib/gallery-hash.mjs';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const argv = process.argv.slice(2);
const tarball = argv.find((a) => !a.startsWith('--') && argv[argv.indexOf(a) - 1] !== '--out');
if (!tarball) { console.error('usage: stage-shell-from-tarball.mjs <dist tarball> [--out out/deploy/assets] [--release-dir]'); process.exit(2); }
const withRelease = argv.includes('--release-dir');
const out = path.resolve(SC, argv.includes('--out') ? argv[argv.indexOf('--out') + 1] : 'out/deploy/assets');
const lock = JSON.parse(fs.readFileSync(path.join(SC, 'QED64.lock.json'), 'utf8'));
const BID = lock.qed64.buildId;
let bad = 0;
const ok = (c, m) => { console.log(`${c ? 'OK  ' : 'FAIL'} ${m}`); if (!c) bad++; };
const sha = (p) => createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const walk = (d, b = d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(path.join(d, e.name), b) : e.isFile() ? [path.relative(b, path.join(d, e.name)).split(path.sep).join('/')] : []));

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'showcase-dist-'));
try {
  execFileSync('tar', ['-xzf', path.resolve(tarball), '-C', tmp]);
  const dist = path.join(tmp, 'dist');
  const want = Object.entries(lock.release.files).filter(([k]) => k.startsWith('dist/')).map(([k, v]) => [k.slice(5), v]);
  const have = new Set(fs.existsSync(dist) ? walk(dist) : []);
  const wrong = want.filter(([r, v]) => !have.has(r) || fs.statSync(path.join(dist, r)).size !== v.bytes || sha(path.join(dist, r)) !== v.sha256).map(([r]) => r);
  const extra = [...have].filter((r) => !want.some(([w]) => w === r));
  ok(!wrong.length && !extra.length, `T1 the tarball's dist/ is exactly the lock's ${want.length} dist files of ${BID} (size + sha256)${wrong.length ? `; wrong/missing: ${wrong.slice(0, 5).join(', ')}` : ''}${extra.length ? `; extra: ${extra.slice(0, 5).join(', ')}` : ''}`);
  const pin = JSON.parse(fs.readFileSync(path.join(SC, 'gallery/pin.json'), 'utf8'));
  ok(pin.buildId === BID, `T2 gallery/pin.json buildId ${pin.buildId} == lock buildId ${BID}`);
  const rmRel = `public/runtime/runtime-manifest.${BID}.json`;
  // pins are keyed by QED64 commit (scripts/lib/pins.mjs): the lock names its release dir, release/<pin id>
  if (!lock.release || !/^release\/[0-9a-f]{7}$/.test(lock.release.dir || '')) throw new Error(`QED64.lock.json release.dir ${lock.release && lock.release.dir} is not release/<pin id>`);
  const releaseDir = path.join(SC, lock.release.dir);
  if (withRelease) {
    const v = lock.release.files[rmRel]; const f = path.join(tmp, rmRel);
    ok(!!v && fs.existsSync(f) && fs.statSync(f).size === v.bytes && sha(f) === v.sha256, `T5 the tarball's ${rmRel} matches the lock (size + sha256)`);
    ok(!fs.existsSync(releaseDir), `T6 ${path.relative(SC, releaseDir)} does not exist yet (--release-dir never overwrites a real release clone)`);
  }
  if (bad) throw new Error('refusing to stage');
  if (withRelease) {
    for (const r of want.map(([w]) => w)) { const to = path.join(releaseDir, 'dist', r); fs.mkdirSync(path.dirname(to), { recursive: true }); fs.copyFileSync(path.join(dist, r), to); }
    fs.mkdirSync(path.dirname(path.join(releaseDir, rmRel)), { recursive: true }); fs.copyFileSync(path.join(tmp, rmRel), path.join(releaseDir, rmRel));
    console.log(`release dir ${path.relative(SC, releaseDir)}: ${want.length} dist files + ${rmRel} (for scripts/check-gallery.mjs)`);
  }
  fs.rmSync(out, { recursive: true, force: true });
  for (const r of want.map(([w]) => w)) { const to = path.join(out, r); fs.mkdirSync(path.dirname(to), { recursive: true }); fs.copyFileSync(path.join(dist, r), to); }
  const gal = galleryFiles(path.join(SC, 'gallery')).filter(isShippedGalleryFile);
  for (const r of gal) { const to = path.join(out, 'showcase', r); fs.mkdirSync(path.dirname(to), { recursive: true }); fs.copyFileSync(path.join(SC, 'gallery', r), to); }
  const staged = walk(out);
  const big = staged.filter((r) => fs.statSync(path.join(out, r)).size > 25 * 1024 * 1024);
  ok(!big.length, `T3 every staged file ≤ 25 MiB (${staged.length} files)${big.length ? `: ${big.join(', ')}` : ''}`);
  ok(!staged.some((r) => /^(runtime|profiles|snapshots)\//.test(r)), 'T4 no runtime/, profiles/ or snapshots/ in the tree (the worker routes them to R2)');
  console.log(bad ? 'STAGE-SHELL FAILED' : `STAGE-SHELL OK ${path.relative(SC, out)}: ${want.length} dist files (${BID}) + ${gal.length} gallery files (gallery ${galleryContentHash(path.join(SC, 'gallery')).contentSha256.slice(0, 16)}…)`);
} catch (e) {
  if (!bad) console.log(`FAIL ${e.message}`);
  console.log('STAGE-SHELL FAILED');
  bad = bad || 1;
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
process.exit(bad ? 1 : 0);
