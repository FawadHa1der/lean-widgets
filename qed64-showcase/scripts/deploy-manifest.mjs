#!/usr/bin/env node
// deploy-manifest.mjs — what a deployment of the showcase on its OWN origin uploads, exactly (docs/DEPLOY.md).
// It never uploads, deploys or logs in anywhere; publishing needs the owner's account and go-ahead.
//
//   node scripts/deploy-manifest.mjs [generate] [--overlays widgets8,widgets7] [--no-stock-snapshots]
//                                    [--prefix <r2 key prefix>] [--out out/deploy] [--from-lock]
//       --overlays takes LOGICAL names (widgets7, widgets8; any other name is a literal directory). Each is uploaded under
//       its SERVED directory, /snapshots/<dir>/ with <dir> = scripts/lib/pins.mjs overlayDir(<o>, pin): the bare name
//       for pins A–H (pin.json v2), '<o>.<bid16>' for a per-runtime pin (v3, pin I on); options.overlayDirs records the
//       map, and every lookup of an overlay index goes through it.
//       Enumerate every file, hash it (sha256), validate the invariants below, and write
//       <out>/manifest.json (deterministic: no timestamps) plus one rclone file list per upload group
//       (<out>/rclone/<group>.<immutable|mutable>.files, paths relative to that group's local root).
//       What the release serves is listed apart, never uploaded: manifest.release.objects are the pin's /runtime/ and
//       /profiles/ files, which infra/worker.js reads from the toolchain release's own prefix lean4-wasm64/<id>/ (the
//       pin's toolchain/lean4-wasm64-release.json, hosting.mount); manifest.r2 is what the showcase owns and uploads
//       (hosting.siteOwned: /profiles/index.json, /snapshots/*).
//       --from-lock: the SHELL-ONLY manifest of a checkout without the artifacts (CI, a fresh clone): the assets are
//       hashed as usual (release/<id>/dist from scripts/build-shell.mjs + gallery/), but every R2 entry's size and
//       sha256 come from the committed lock (release.files public/*, overlays.*.files; overlays.*.url must be
//       /snapshots/<dir>/) instead of local files. Same keys, sizes and sha256 as the full manifest (options.source =
//       "lock" is the only addition). R1, R2 and the stock
//       R3 read the five manifests/indexes QED64 tracks in git (scripts/fetch-artifacts.mjs --git-only installs them;
//       their sha256 must equal the lock's); the overlay indexes are not in git, so their R3 runs in --published.
//       Such a manifest can stage and deploy the shell; scripts/upload-artifacts.sh refuses it.
//   node scripts/deploy-manifest.mjs --check [--out out/deploy]
//       Dry run: regenerate in memory with the options recorded in manifest.json, require it to be
//       byte-identical to the written one (every file re-hashed), and re-run every invariant. Uploads nothing.
//   node scripts/deploy-manifest.mjs --published <origin> [--out out/deploy] [--before-phase-3]
//       Are this manifest's R2 objects (ours and the release's) published on <origin>? <origin> must run THIS shell's
//       Worker: the new version's preview URL, or wrangler dev; an older Worker maps /runtime/ and /profiles/ elsewhere.
//       HEAD every immutable key (status 200, content-length == size); GET every manifest and index (status 200,
//       body sha256 == the manifest's), and run R3 on each fetched overlay index. Writes nothing. deploy-app.sh runs it
//       between `wrangler versions upload` and `wrangler versions deploy`, so no visitor is sent to a shell whose
//       artifacts are not there. --before-phase-3 (with --smoke too) leaves out the shared indexes of upload phase 3,
//       /profiles/index.json and /snapshots/index.json: a split upload (decision E1) has not replaced them yet.
//   node scripts/deploy-manifest.mjs --record-verdict [--out out/deploy]
//       Write infra/ux-verdict.json (committed): the G2 verdict run for this manifest's gallery + lock + overlays, from
//       out/ux/showcase-ux-runs.jsonl. Refuses unless the manifest is current and G2 names a verdict with no later red
//       full run on the same inputs. A checkout without the UX records (CI) accepts G2 from this file.
//   node scripts/deploy-manifest.mjs --stage-assets [--out out/deploy]
//       Clone (copy-on-write where the file system can: scripts/lib/platform.mjs cloneFile) exactly the manifest's asset files into <out>/assets — the directory wrangler deploys —
//       and verify every staged file's sha256 against the manifest.
//   node scripts/deploy-manifest.mjs --commands [--out out/deploy] [--bucket <bucket>] [--remote <rclone remote>]
//       Print the upload and deploy commands for the owner, for review (not in upload-phase order: upload with
//       scripts/upload-artifacts.sh). Prints only; runs nothing. Bucket and remote
//       default to infra/deploy.env (R2_BUCKET / R2_REMOTE, overridable by those environment variables).
//   node scripts/deploy-manifest.mjs --smoke <origin> [--out out/deploy] [--all] [--range] [--before-phase-3]
//       HEAD the manifest's URLs on a live origin (the deployed Worker, or scripts/serve.mjs locally) and
//       check status 200, content-length == size, COOP/COEP/CORP, the QED64 cache rule, and no
//       Content-Encoding on artifacts; also GET every index/manifest (the mutable keys) and compare its sha256 with
//       the manifest's, as --published does (an older one of the same length passes a HEAD); immutable keys are
//       HEAD only. Default: every index/manifest, every .snapz, every asset, and
//       one runtime chunk and profile part per file; --all checks every key. --range (the Worker, not
//       scripts/serve.mjs) also checks single-range GETs on the largest .snapz: bytes=0-99 -> 206 with
//       Content-Range and Content-Length 100, a range past the end -> 416, a mismatched If-Range -> 200.
//   node scripts/deploy-manifest.mjs --help
//       Print this usage. An unknown argument, a value flag without its value, or two modes print it and
//       exit 2 before anything is read or written.
//
// Layout (one origin; infra/worker.js): assets = the pinned QED64 dist at "/" + gallery/ at "/showcase/";
// R2 key = <prefix> + URL path without the leading "/" for /snapshots/ and /profiles/index.json, and
// lean4-wasm64/<release id>/ + URL path without the leading "/" for every other file of /runtime/ and /profiles/.
// Invariants (each prints OK/FAIL; any FAIL -> exit 1):
//   A1 every asset ≤ 25 MiB (Workers static-assets per-file cap)   A2 no asset under runtime/ profiles/ snapshots/
//   A3 dist/index.html, showcase/index.html and every file index.html references are present
//   A4 bundle buildIds in dist/assets/*.js == {lock buildId}; gallery/pin.json buildId == lock buildId
//   A5 asset count ≤ 20000 (Workers static-assets file-count limit at the time of writing)
//   L1 every file taken from release/<BID>/ has the size and sha256 QED64.lock.json records
//   L2 the pin's toolchain record (the one infra/worker.js routes by) names runtime BID, and every release-served file
//      is in it with that size and sha256: the pinned shell reads the kernel's published bytes, not a copy of ours
//   R1 runtime-manifest.json == runtime-manifest.<BID>.json (bytes), buildId == BID, every chunk present
//      with the manifest's size and sha256
//   R2 every profile the index lists has its manifest and every transport part present with its digest
//      and size; the index entry
//      names a release and it == the manifest's content.release, and the manifest's content.lean.version == the
//      index's runtime.leanVersion (fail closed: a pack manifest has the same URL in every release, QED64 HARDENING #81)
//   R3 every snapshot index uploaded (stock + overlays): schema, runtime == BID, every entry's URL (re-rooted
//      to /snapshots/<dir>/ for overlays, as qed64-boot.ts:96-106 does) present with sha256 == digest
//      and size == transfer; overlays hold exactly {init, mathlib}
//   R4 R2 keys unique; objects > 300 MiB are flagged multipart (wrangler's single put cannot take them)
//   R6 (a pin with hardening.pinnedIndexes, QED64 HARDENING #64) this runtime's per-build index copies
//      /snapshots/index.<BID>.json and /snapshots/profiles-index.<BID>.json are uploaded, mutable (upload phase 2),
//      byte-identical to the stock /snapshots/index.json and /profiles/index.json, and name only BID
//   R5 each logical overlay's served directory (options.overlayDirs) == pins.mjs overlayDir(<o>, pin) == the lock's
//      overlays.<o>.url, and a per-runtime pin uploads nothing under the bare /snapshots/<o>/ (an older live shell
//      reads that directory)
//   G1 (generate and --check) the gallery's own static gate, scripts/check-gallery.mjs, exits 0 (600 s watchdog):
//      a manifest is never written for, and --check never passes on, a gallery that fails its own gate
//   G2 (info) is there a VERDICT `scripts/showcase.sh ux` run (out/ux/showcase-ux-runs.jsonl; the rule is
//      scripts/lib/ux-record.mjs whyNotVerdict) for this manifest's gallery content sha256, its lock sha256 and its
//      overlay index sha256s? (docs/DEPLOY.md "Publishing" requires that there is)
// generate writes manifest.json and the rclone lists ONLY when every invariant is OK (else nothing is written).
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { cloneFile } from './lib/platform.mjs';
import { galleryContentHash, isShippedGalleryFile } from './lib/gallery-hash.mjs';
import { verdictFor, laterFailures, readRuns } from './lib/ux-record.mjs';
import { loadDeployEnv, checkSharedBucket } from './lib/deploy-env.mjs';
import { OVERLAYS, overlayDir, pinIdOf, pinDescriptor } from './lib/pins.mjs';
import { releaseKey } from './lib/release-routing.mjs';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const MiB = 1024 * 1024;
const ASSET_CAP = 25 * MiB;
const ASSET_COUNT_CAP = 20000;
const MULTIPART_OVER = 300 * MiB;

const argv = process.argv.slice(2);
// Strict arguments (close-out 3, audit minor: `--help` used to fall through to generate and rewrite out/deploy).
// generate is the default mode and may also be named; anything unknown prints the usage and exits 2 before any write.
const MODES = { '--check': 'check', '--stage-assets': 'stage', '--commands': 'commands', '--smoke': 'smoke', '--published': 'published', '--record-verdict': 'record-verdict', generate: 'generate' };
const ORIGIN_MODES = ['--smoke', '--published'];
const BOOL_FLAGS = ['--all', '--range', '--no-stock-snapshots', '--from-lock', '--before-phase-3'];
const VALUE_FLAGS = ['--out', '--overlays', '--prefix', '--bucket', '--remote']; // --smoke / --published take the origin as their value
function usage(code, why) {
  if (why) console.error(`deploy-manifest: ${why}`);
  const head = fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(1).filter((l) => l.startsWith('//'));
  const end = head.findIndex((l) => /^\/\/ Layout/.test(l));
  (code ? console.error : console.log)(head.slice(0, end > 0 ? end : head.length).map((l) => l.replace(/^\/\/ ?/, '')).join('\n'));
  process.exit(code);
}
{
  const modes = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--help' || a === '-h') usage(0);
    if (a in MODES) { modes.push(a); if (ORIGIN_MODES.includes(a)) { if (argv[i + 1] === undefined || argv[i + 1].startsWith('--')) usage(2, `${a} needs an origin`); i++; } continue; }
    if (BOOL_FLAGS.includes(a)) continue;
    if (VALUE_FLAGS.includes(a)) { if (argv[i + 1] === undefined || argv[i + 1].startsWith('--')) usage(2, `${a} needs a value`); i++; continue; }
    usage(2, `unknown argument '${a}' (nothing was written)`);
  }
  if (modes.length > 1) usage(2, `more than one mode: ${modes.join(' ')}`);
}
const flag = (n) => argv.includes(n);
const val = (n, d) => (argv.includes(n) ? argv[argv.indexOf(n) + 1] : d);
const MODE = flag('--check') ? 'check' : flag('--stage-assets') ? 'stage' : flag('--commands') ? 'commands' : flag('--smoke') ? 'smoke'
  : flag('--published') ? 'published' : flag('--record-verdict') ? 'record-verdict' : 'generate';
if (flag('--from-lock') && MODE !== 'generate') usage(2, '--from-lock applies to generate only (--check reads it from manifest.json)');
if (flag('--before-phase-3') && MODE !== 'published' && MODE !== 'smoke') usage(2, '--before-phase-3 applies to --published and --smoke only');
// The committed G2 record (--record-verdict): what a checkout without out/ux (CI, a fresh clone) accepts as the verdict.
const VERDICT_FILE = path.join(SC, 'infra', 'ux-verdict.json');
const OUT = path.resolve(SC, val('--out', 'out/deploy'));

let fails = 0;
const ok = (c, m, d = '') => { console.log(`${c ? 'OK  ' : 'FAIL'} ${m}${d ? ` — ${d}` : ''}`); if (!c) fails++; return !!c; };
const info = (m) => console.log(`info ${m}`);
const rel = (p) => path.relative(SC, p);
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
function sha256File(p) {
  const h = createHash('sha256'); const fd = fs.openSync(p, 'r'); const buf = Buffer.allocUnsafe(8 * MiB);
  try { for (;;) { const n = fs.readSync(fd, buf, 0, buf.length, null); if (!n) break; h.update(buf.subarray(0, n)); } } finally { fs.closeSync(fd); }
  return h.digest('hex');
}
function walk(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p)); else if (e.isFile()) out.push(p);
  }
  return out;
}
const CT = { '.json': 'application/json', '.snapz': 'application/octet-stream', '.js': 'text/javascript' };
const contentType = (p) => (/\.part-\d+$/.test(p) ? 'application/octet-stream' : CT[path.extname(p)] || 'application/octet-stream');
// Smoke rule for the served Content-Type. The pinned shell (qed64-boot.ts:69) and the gallery's
// preflight (gallery/lib.js) refuse a runtime manifest / index whose type is not JSON, and a binary
// artifact served as HTML means a fallback page answered instead of the object.
function contentTypeProblem(url, ct) {
  const p = url.split('?')[0];
  const want = /\.json$/.test(p) ? [/json/, 'a JSON type']
    : /\.m?js$/.test(p) ? [/javascript/, 'a JavaScript type']
    : /\.css$/.test(p) ? [/^text\/css/, 'text/css']
    : /(\.html|\/)$/.test(p) ? [/^text\/html/, 'text/html']
    : null;
  if (want) return want[0].test(ct || '') ? null : `content-type ${ct} (want ${want[1]})`;
  if (/(\.snapz|\.part-\d+|\.wasm|\.gz)$/.test(p) && (!ct || /text\/html|json/.test(ct))) return `content-type ${ct} (binary artifact must not be HTML/JSON)`;
  return null;
}
// QED64's cache rule, not a copy: imported from the active pin's QED64 sources (the submodule deps/qed64;
// scripts/lib/qed64-src.mjs): infra/edge-worker.js, QED64's dependency-free library (84d594e on), where the pin has it
// (from 385a1ac on QED64's infra/worker.js also imports the toolchain release record and builds its Worker at load),
// else infra/worker.js (pins A–E). If the sources are not checked out, every use fails with the reason.
let qedIsImmutable = null, qedSrcError = null, qedIsImmutableSrc = 'deps/qed64/infra/edge-worker.js', qedReleaseRoutes = null;
try {
  const PINS = await import('./lib/pins.mjs');
  const infra = path.join(PINS.storePath('qed64', { id: PINS.activePinId() }), 'infra');
  const f = fs.existsSync(path.join(infra, 'edge-worker.js')) ? 'edge-worker.js' : 'worker.js';
  qedIsImmutableSrc = `${rel(infra)}/${f}`;
  ({ isImmutable: qedIsImmutable, releaseRoutes: qedReleaseRoutes } = await import(pathToFileURL(path.join(infra, f)).href));
  if (typeof qedIsImmutable !== 'function') throw new Error(`${qedIsImmutableSrc} exports no isImmutable`);
} catch (e) { qedIsImmutable = null; qedSrcError = e; }
function isImmutable(pathname) {
  if (!qedIsImmutable) throw new Error(`QED64's isImmutable (${qedIsImmutableSrc}) is not available: ${qedSrcError && qedSrcError.message}`);
  return qedIsImmutable(pathname);
}

// What infra/worker.js does with the same record: QED64's releaseRoutes checks it and gives {id, prefix, mount,
// siteOwned}; scripts/lib/release-routing.mjs says where a path lands. The submodule's record, the one the Worker bundles
// (`qed64-src check` holds its gitlink to the lock).
const RELEASE_RECORD = path.join(SC, 'deps/qed64/toolchain/lean4-wasm64-release.json');
function loadRelease(pinId) {
  if (qedSrcError) throw new Error(`pin ${pinId}: ${qedSrcError.message}`);
  if (typeof qedReleaseRoutes !== 'function') throw new Error(`pin ${pinId}: QED64's ${qedIsImmutableSrc} has no release routing, so infra/worker.js cannot serve it (pins before 385a1ac: a rollback to one is 'wrangler rollback' to its Worker version, docs/DEPLOY-CLOUDFLARE.md section 5)`);
  if (!fs.existsSync(RELEASE_RECORD)) throw new Error(`${rel(RELEASE_RECORD)} missing: the Worker bundles it to route /runtime/ and /profiles/`);
  const record = readJson(RELEASE_RECORD);
  return { record, routes: qedReleaseRoutes(record) };
}
// Everything the shell needs from R2: what we upload, then what the release serves (a record of a pin before release
// routing has only r2).
const servedObjects = (m) => [...m.r2, ...(m.release ? m.release.objects : [])];
// The shared indexes of upload phase 3 (upload-artifacts.sh phaseOf; a per-runtime overlay's index is phase 2)
const isPhase3 = (o) => /\/index\.json$/.test(o.url) && !/^\/snapshots\/widgets[78]\.[0-9a-f]{16}\/index\.json$/.test(o.url);

// ------------------------------------------------------------------------------------------ build
function build(opts) {
  const lock = readJson(path.join(SC, 'QED64.lock.json'));
  const BID = lock.qed64.buildId;
  const R = path.join(SC, lock.release.dir);
  const lockFiles = lock.release.files;
  const pinId = pinIdOf(lock.qed64.commit);
  // the SERVED directory of each overlay (pins.mjs overlayDir; a non-logical name is a literal directory)
  const overlayDirs = Object.fromEntries(opts.overlays.map((o) => [o, OVERLAYS.includes(o) ? overlayDir(o, pinId) : o]));
  const { record: releaseRecord, routes } = loadRelease(pinId);
  const assets = []; const r2 = []; const releaseObjects = [];
  const addAsset = (src, apath) => { const st = fs.statSync(src); assets.push({ path: apath, src: rel(src), size: st.size, sha256: sha256File(src) }); };
  // Local mode hashes the file; --from-lock takes size + sha256 from the lock (`known`) and never reads the binary.
  const addR2 = (src, urlPath, group, root, known = null) => {
    const size = known ? known.bytes : fs.statSync(src).size;
    const sha256 = known ? known.sha256 : sha256File(src);
    const key = releaseKey(routes, urlPath);
    if (key !== null) { releaseObjects.push({ key, url: urlPath, src: rel(src), size, sha256, contentType: contentType(src), immutable: isImmutable(urlPath) }); return; }
    r2.push({ key: opts.prefix + urlPath.slice(1), url: urlPath, src: rel(src), group, root: rel(root), relPath: path.relative(root, src),
      size, sha256, contentType: contentType(src), immutable: isImmutable(urlPath),
      phase: isImmutable(urlPath) ? 'immutable' : 'mutable', multipart: size > MULTIPART_OVER });
  };
  // assets: pinned dist at "/", gallery at "/showcase/" (docs and the X3 experiment page are not shipped)
  if (!fs.existsSync(path.join(R, 'dist'))) throw new Error(`${rel(path.join(R, 'dist'))} missing: build it from source with 'node scripts/build-shell.mjs'`);
  for (const f of walk(path.join(R, 'dist'))) addAsset(f, path.relative(path.join(R, 'dist'), f));
  for (const f of walk(path.join(SC, 'gallery'))) {
    const r = path.relative(path.join(SC, 'gallery'), f);
    if (!isShippedGalleryFile(r.split(path.sep).join('/'))) continue;   // same rule as the gallery content hash
    addAsset(f, `showcase/${r}`);
  }
  // R2: the pinned release's public/ (runtime, profiles, stock snapshots) + our overlays
  const pub = path.join(R, 'public');
  // the files of public/<dir>: walked locally, or (--from-lock) the lock's release.files entries public/<dir>/…
  const pubFiles = (dir) => (opts.fromLock
    ? Object.keys(lockFiles).filter((k) => k.startsWith(`public/${dir}/`)).sort().map((k) => [path.join(R, k), lockFiles[k]])
    : walk(path.join(pub, dir)).map((f) => [f, null]));
  for (const [f, k] of pubFiles('runtime')) addR2(f, `/${path.relative(pub, f)}`, 'runtime', path.join(pub, 'runtime'), k);
  for (const [f, k] of pubFiles('profiles')) addR2(f, `/${path.relative(pub, f)}`, 'profiles', path.join(pub, 'profiles'), k);
  if (opts.stockSnapshots) for (const [f, k] of pubFiles('snapshots')) addR2(f, `/${path.relative(pub, f)}`, 'snapshots-stock', path.join(pub, 'snapshots'), k);
  // QED64 HARDENING #64 (a pin whose descriptor sets hardening.pinnedIndexes): this runtime's per-build index copies, as
  // QED64's own upload writes them (its scripts/upload-artifacts.sh: step 2 up to 58ebbad; from 4b93459 on step 3, after
  // every .snapz and before the mutable indexes): /snapshots/index.<BID>.json = the stock
  // snapshot index's bytes, /snapshots/profiles-index.<BID>.json = profiles/index.json's. This runtime's shell reads a copy
  // only while the served mutable index names another runtime (a split upload's window, decision E1; a later runtime's
  // indexes once that is deployed), so the copies go up in upload phase 2 and stay. QED64's git tracks
  // neither, so they are materialized under <out>/pinned-indexes/snapshots (rclone --files-from needs source name == key
  // name); --from-lock takes size + sha256 from the lock's entry of the index they copy. Pins A–H have no flag: unchanged.
  const pinnedIndexes = !!(pinDescriptor(pinId).hardening || {}).pinnedIndexes;
  if (pinnedIndexes) {
    const pdir = path.join(OUT, 'pinned-indexes', 'snapshots');
    const copies = [['profiles/index.json', `profiles-index.${BID}.json`], ...(opts.stockSnapshots ? [['snapshots/index.json', `index.${BID}.json`]] : [])];
    for (const [from, name] of copies) {
      if (r2.some((o) => o.url === `/snapshots/${name}`)) continue;   // the release ships the copy itself (R6 checks it)
      const known = opts.fromLock ? lockFiles[`public/${from}`] : null;
      if (opts.fromLock && !known) throw new Error(`hardening.pinnedIndexes: public/${from} is not in QED64.lock.json release.files`);
      if (!opts.fromLock) {
        const src = path.join(pub, from); const to = path.join(pdir, name);
        if (!fs.existsSync(src)) throw new Error(`hardening.pinnedIndexes: ${rel(src)} missing (the per-build copy ${name} is made from it)`);
        fs.mkdirSync(pdir, { recursive: true });
        if (!fs.existsSync(to) || !fs.readFileSync(to).equals(fs.readFileSync(src))) fs.copyFileSync(src, to);
      }
      addR2(path.join(pdir, name), `/snapshots/${name}`, 'snapshots-pinned', pdir, known);
    }
  }
  for (const o of opts.overlays) {
    const d = path.join(SC, 'out/overlay/snapshots', o);   // the store (active link), always by its logical name
    const dir = overlayDirs[o];                             // the served directory: /snapshots/<dir>/
    if (opts.fromLock) {
      const lo = lock.overlays && lock.overlays[o];
      if (!lo || !lo.files || !lo.files['index.json']) throw new Error(`overlay ${o}: not recorded in QED64.lock.json overlays (scripts/pin-qed64.mjs record-overlays)`);
      if (lo.url !== `/snapshots/${dir}/`) throw new Error(`overlay ${o}: lock overlays.${o}.url ${lo.url} != /snapshots/${dir}/ (pins.mjs overlayDir for pin ${pinId}; re-record with scripts/pin-qed64.mjs record-overlays)`);
      for (const n of Object.keys(lo.files).sort()) addR2(path.join(d, n), `/snapshots/${dir}/${n}`, `overlay-${o}`, d, lo.files[n]);
      continue;
    }
    if (!fs.existsSync(path.join(d, 'index.json'))) throw new Error(`overlay ${o}: ${rel(d)}/index.json missing (scripts/showcase.sh overlay)`);
    for (const f of walk(d)) addR2(f, `/snapshots/${dir}/${path.relative(d, f)}`, `overlay-${o}`, d);
  }
  assets.sort((a, b) => (a.path < b.path ? -1 : 1)); r2.sort((a, b) => (a.key < b.key ? -1 : 1)); releaseObjects.sort((a, b) => (a.key < b.key ? -1 : 1));
  const sum = (xs) => xs.reduce((s, x) => s + x.size, 0);
  const groups = {};
  for (const o of r2) { const g = (groups[o.group] ||= { root: o.root, files: 0, bytes: 0 }); g.files++; g.bytes += o.size; }
  return {
    manifest: {
      schema: 'qed64-showcase.deploy-manifest/v1',
      note: 'Generated by scripts/deploy-manifest.mjs. Nothing is uploaded by this tool; publishing needs the owner\'s Cloudflare account and explicit go-ahead (docs/DEPLOY.md).',
      pin: { id: String(lock.qed64.commit).slice(0, 7), buildId: BID, qed64Commit: lock.qed64.commit, lockSha256: sha256File(path.join(SC, 'QED64.lock.json')), releaseDir: lock.release.dir },
      gallery: galleryContentHash(path.join(SC, 'gallery')),
      options: { overlays: opts.overlays, overlayDirs, stockSnapshots: opts.stockSnapshots, prefix: opts.prefix, ...(opts.fromLock ? { source: 'lock' } : {}) },
      totals: { assets: assets.length, assetBytes: sum(assets), r2Objects: r2.length, r2Bytes: sum(r2), r2Multipart: r2.filter((o) => o.multipart).length, groups, releaseObjects: releaseObjects.length, releaseBytes: sum(releaseObjects) },
      assets, r2, release: { id: routes.id, prefix: routes.prefix, objects: releaseObjects },
    },
    ctx: { lock, BID, R, lockFiles, fromLock: !!opts.fromLock, pinnedIndexes, releaseRecord },
  };
}

// ------------------------------------------------------------------------------------------ validate
function validate({ manifest: m, ctx }) {
  const { BID, R, lockFiles, fromLock } = ctx;
  // The JSON an R2 entry names. Local mode: the file (its sha256 is the manifest's by construction). --from-lock: the
  // file must be the one QED64 tracks in git (fetch-artifacts --git-only) with the lock's sha256; an overlay index is
  // not in git, so it returns null there and R3 for it runs in --published against the origin.
  const jsonOf = (o, label) => {
    const p = path.join(SC, o.src);
    if (!fromLock) return readJson(p);
    if (!fs.existsSync(p)) {
      if (o.group?.startsWith('overlay-')) return null;
      ok(false, `${label}: ${o.src} present (a file QED64 tracks in git: run 'node scripts/fetch-artifacts.mjs --git-only')`); return undefined;
    }
    if (!ok(sha256File(p) === o.sha256, `${label}: ${o.src} sha256 == the lock's`)) return undefined;
    return readJson(p);
  };
  const byUrl = new Map(servedObjects(m).map((o) => [o.url, o]));
  const assetPaths = new Set(m.assets.map((a) => a.path));
  // A1–A5
  const big = m.assets.filter((a) => a.size > ASSET_CAP);
  ok(!big.length, `A1 every asset ≤ 25 MiB (${m.assets.length} files, largest ${Math.max(...m.assets.map((a) => a.size))} B)`, big.map((a) => `${a.path} ${a.size}`).join(', '));
  const shadow = m.assets.filter((a) => /^(runtime|profiles|snapshots)\//.test(a.path));
  ok(!shadow.length, 'A2 no asset under runtime/, profiles/ or snapshots/ (the worker routes those to R2)', shadow.map((a) => a.path).join(', '));
  const refs = [...fs.readFileSync(path.join(SC, 'gallery/index.html'), 'utf8').matchAll(/(?:src|href)="([^"#:]+)"/g)].map((x) => x[1]).filter((x) => !x.startsWith('/'));
  const missingRefs = refs.filter((r) => !assetPaths.has(`showcase/${r}`));
  ok(assetPaths.has('index.html') && assetPaths.has('showcase/index.html') && !missingRefs.length,
    `A3 dist/index.html, showcase/index.html and the ${refs.length} local files gallery/index.html references are assets`, missingRefs.join(', '));
  const ids = new Set();
  for (const a of m.assets.filter((x) => /^assets\/.*\.js$/.test(x.path))) for (const id of fs.readFileSync(path.join(SC, a.src), 'utf8').match(/wasm64-[0-9a-f]{16}/g) || []) ids.add(id);
  const pin = readJson(path.join(SC, 'gallery/pin.json'));
  ok(ids.size === 1 && ids.has(BID) && pin.buildId === BID, `A4 bundle buildIds {${[...ids].join(', ')}} == {${BID}} and gallery/pin.json buildId ${pin.buildId}`);
  ok(m.assets.length <= ASSET_COUNT_CAP, `A5 asset count ${m.assets.length} ≤ ${ASSET_COUNT_CAP}`);
  // L1: release files equal the lock
  // (--from-lock: the R2 entries ARE the lock's values, so L1 can only say something about the hashed dist files)
  const fromRelease = [...m.assets.filter((a) => a.src.startsWith(`${m.pin.releaseDir}/`)), ...(fromLock ? [] : servedObjects(m).filter((o) => o.src.startsWith(`${m.pin.releaseDir}/`)))];
  const lockBad = fromRelease.filter((x) => { const l = lockFiles[x.src.slice(m.pin.releaseDir.length + 1)]; return !l || l.sha256 !== x.sha256 || l.bytes !== x.size; });
  ok(!lockBad.length, `L1 all ${fromRelease.length} files taken from ${m.pin.releaseDir}/ match QED64.lock.json (size + sha256)${fromLock ? '; the R2 entries are the lock\'s own values (--from-lock)' : ''}`, lockBad.slice(0, 5).map((x) => x.src).join(', '));
  // L2: what the release serves is what the kernel published (the toolchain record lists every file with its digest)
  const relFiles = new Map(ctx.releaseRecord.files.map((f) => [m.release.prefix + f.path, f]));
  const relBad = m.release.objects.filter((o) => { const f = relFiles.get(o.key); return !f || f.bytes !== o.size || f.sha256 !== o.sha256; });
  ok(ctx.releaseRecord.runtime.buildId === BID && m.release.objects.length > 0 && !relBad.length,
    `L2 toolchain record ${m.release.id} names runtime ${ctx.releaseRecord.runtime.buildId}; all ${m.release.objects.length} release-served files are in it with this size and sha256`,
    relBad.slice(0, 5).map((o) => o.key).join(', '));
  // R1 runtime
  const rtMut = byUrl.get('/runtime/runtime-manifest.json'); const rtPin = byUrl.get(`/runtime/runtime-manifest.${BID}.json`);
  const rt = ok(!!rtMut && !!rtPin && rtMut.sha256 === rtPin.sha256, `R1 runtime-manifest.json == runtime-manifest.${BID}.json (the pinned shell fetches the latter first)`)
    ? jsonOf(rtPin, 'R1') : undefined;
  if (rt) {
    const bad = []; let n = 0;
    for (const f of Object.values(rt.files || {})) for (const c of f.chunks || []) { n++; const o = byUrl.get(c.url); if (!o || o.size !== c.bytes || o.sha256 !== c.sha256) bad.push(c.url); }
    ok(rt.buildId === BID && n > 0 && !bad.length, `R1 runtime buildId ${rt.buildId}; all ${n} chunks present with the manifest's size and sha256`, bad.join(', '));
  }
  // R2 profiles
  const pidx = byUrl.get('/profiles/index.json');
  const pj = ok(!!pidx, 'R2 profiles/index.json uploaded') ? jsonOf(pidx, 'R2') : undefined;
  if (pj) {
    for (const p of pj.profiles) {
      const mo = byUrl.get(p.manifest);
      if (!ok(!!mo, `R2 profile ${p.id}: manifest ${p.manifest} uploaded`)) continue;
      const mj = jsonOf(mo, `R2 profile ${p.id}`);
      if (!mj) continue;
      // The pairing of index and manifest (QED64 HARDENING #81): a manifest's URL is the same in every release, so only
      // the index entry's `release` says which one this pin's shell pairs with; a shell from #81 on refuses a mismatch as
      // stale ("reload"), an older one installs the other release's pack. QED64 skips an entry that names no release;
      // here both must name one and agree (every pin's tracked index and manifests do), and the manifest's Lean
      // version must be the index runtime's.
      const relIdx = p.release, relMan = mj.content && mj.content.release;
      const leanIdx = pj.runtime && pj.runtime.leanVersion, leanMan = mj.content && mj.content.lean && mj.content.lean.version;
      ok(!!relIdx && relIdx === relMan && !!leanIdx && leanIdx === leanMan,
        `R2 profile ${p.id}: index release ${relIdx} == ${p.manifest} content.release, Lean ${leanMan} == index runtime.leanVersion ${leanIdx}`,
        [!relIdx ? 'the index entry names no release' : '', relIdx && relIdx !== relMan ? `the manifest is release ${relMan} (a pack manifest of another release under the same URL: the shell would refuse it as stale, or an older one install it)` : '',
          !leanIdx ? 'the index records no runtime.leanVersion' : '', leanIdx && leanIdx !== leanMan ? `the manifest is Lean ${leanMan}` : ''].filter(Boolean).join('; '));
      const parts = mj.content.pack.transport.parts;
      const bad = parts.filter((x) => { const o = byUrl.get(x.url); return !o || o.size !== x.byteLength || `sha256:${o.sha256}` !== x.digest; });
      ok(!bad.length, `R2 profile ${p.id}: all ${parts.length} transport parts present with digest and size`, bad.slice(0, 3).map((x) => x.url).join(', '));
    }
  }
  // R3 snapshot indexes
  const indexes = m.r2.filter((o) => /^\/snapshots\/(?:[^/]+\/)?index\.json$/.test(o.url));
  for (const ix of indexes) {
    const j = jsonOf(ix, `R3 ${ix.url}`);
    if (j === null) { info(`R3 ${ix.url}: not tracked in git, its sha256 is the lock's (record-overlays); its content is checked by --published on the origin`); continue; }
    if (j) r3Index(m, BID, ix, j);
  }
  ok(indexes.length === m.options.overlays.length + (m.options.stockSnapshots ? 1 : 0), `R3 ${indexes.length} snapshot index(es) uploaded (stock: ${m.options.stockSnapshots}, overlays: ${m.options.overlays.join(', ')})`);
  // R6 the per-build index copies of a pinnedIndexes pin (QED64 HARDENING #64): present, mutable (phase 2 of
  // upload-artifacts.sh; QED64's isImmutable revalidates them), the bytes of the index they copy, naming only BID
  if (ctx.pinnedIndexes) {
    for (const [from, name, runtimesOf] of [['/profiles/index.json', `profiles-index.${BID}.json`, (j) => [j.runtime && j.runtime.buildId]],
      ...(m.options.stockSnapshots ? [['/snapshots/index.json', `index.${BID}.json`, (j) => (Array.isArray(j.snapshots) ? j.snapshots.map((e) => e.runtime) : [])]] : [])]) {
      const c = byUrl.get(`/snapshots/${name}`); const src = byUrl.get(from);
      if (!ok(!!c && !!src, `R6 /snapshots/${name} uploaded (hardening.pinnedIndexes) beside ${from}`)) continue;
      const j = jsonOf(src, `R6 ${from}`);
      const rts = j ? runtimesOf(j) : [];
      ok(c.sha256 === src.sha256 && c.size === src.size && !c.immutable && j && rts.length > 0 && rts.every((r) => r === BID),
        `R6 /snapshots/${name}: mutable, == ${from} (size + sha256), names only ${BID}`,
        [c.sha256 !== src.sha256 || c.size !== src.size ? 'bytes differ' : '', c.immutable ? 'immutable under QED64\'s isImmutable (a pin before HARDENING #64?)' : '', j && !(rts.length > 0 && rts.every((r) => r === BID)) ? `runtimes ${JSON.stringify(rts)}` : ''].filter(Boolean).join('; '));
    }
  } else {
    const stray = m.r2.filter((o) => o.group === 'snapshots-pinned').map((o) => o.url);
    if (stray.length) ok(false, 'R6 no per-build index copy uploaded (no hardening.pinnedIndexes)', stray.join(', '));
  }
  // R4
  ok(new Set(servedObjects(m).map((o) => o.key)).size === servedObjects(m).length, `R4 ${servedObjects(m).length} R2 keys unique (${m.r2.length} ours, ${m.release.objects.length} the release's)`);
  const mp = m.r2.filter((o) => o.multipart);
  info(`R4 ${mp.length} object(s) > 300 MiB need a multipart upload (rclone): ${mp.map((o) => `${o.key} ${(o.size / MiB).toFixed(0)} MiB`).join(', ') || 'none'}`);
  // R5 served overlay directories (scripts/lib/pins.mjs is the one naming rule; the lock records the URL it gave)
  for (const o of m.options.overlays) {
    const dir = (m.options.overlayDirs || {})[o];
    const ixs = m.r2.filter((x) => x.group === `overlay-${o}`);
    const under = ixs.every((x) => x.url.startsWith(`/snapshots/${dir}/`));
    if (!OVERLAYS.includes(o)) { ok(dir === o && under, `R5 overlay ${o}: not a logical overlay, served at its literal directory /snapshots/${dir}/ (${ixs.length} objects)`); continue; }
    let want = null, why = '';
    try { want = overlayDir(o, m.pin.id); } catch (e) { why = e.message; }
    const lockUrl = ctx.lock.overlays && ctx.lock.overlays[o] && ctx.lock.overlays[o].url;
    const bare = dir !== o ? m.r2.filter((x) => x.url.startsWith(`/snapshots/${o}/`)).map((x) => x.url) : [];
    ok(dir === want && lockUrl === `/snapshots/${dir}/` && under && !bare.length,
      `R5 overlay ${o}: served at /snapshots/${dir}/ == pins.mjs overlayDir(${o}, ${m.pin.id}) == lock overlays.${o}.url (${ixs.length} objects${dir !== o ? `; nothing under the bare /snapshots/${o}/` : ''})`,
      [why, dir !== want ? `overlayDir ${want}` : '', lockUrl !== `/snapshots/${dir}/` ? `lock url ${lockUrl}` : '', under ? '' : 'an object outside the directory', bare.length ? `bare keys ${bare.slice(0, 3).join(', ')}` : ''].filter(Boolean).join('; '));
  }
  info(`totals: ${m.totals.assets} assets ${(m.totals.assetBytes / MiB).toFixed(1)} MiB; ${m.totals.r2Objects} R2 objects to upload ${(m.totals.r2Bytes / 1e9).toFixed(3)} GB; ${m.totals.releaseObjects} served from ${m.release.prefix} ${(m.totals.releaseBytes / 1e9).toFixed(3)} GB`);
}

// The URL of logical overlay o's index in manifest m: /snapshots/<dir>/index.json with the directory the manifest
// recorded (options.overlayDirs; a manifest written before it existed served the bare name).
const ovIndexUrl = (m, o) => `/snapshots/${(m.options.overlayDirs || {})[o] || o}/index.json`;

// R3 on one snapshot index (parsed JSON j of the R2 entry ix): schema, runtime, entries present with digest and size.
function r3Index(m, BID, ix, j) {
  const byUrl = new Map(m.r2.map((o) => [o.url, o]));
  const dir = /^\/snapshots\/([^/]+)\/index\.json$/.exec(ix.url)?.[1] || null;
  const errs = [];
  if (j.schema !== 'qed64.snapshot-index/v1') errs.push(`schema ${j.schema}`);
  const snaps = Array.isArray(j.snapshots) ? j.snapshots : [];
  const names = snaps.map((s) => s.name).sort().join(',');
  if (dir && names !== 'init,mathlib') errs.push(`entries ${names} (overlay must be exactly init,mathlib)`);
  for (const s of snaps) {
    const url = dir ? s.url.replace(/^\/snapshots\//, `/snapshots/${dir}/`) : s.url;
    const o = byUrl.get(url);
    if (s.runtime !== BID) errs.push(`${s.name}.runtime ${s.runtime}`);
    if (!o) { errs.push(`${s.name}: ${url} not uploaded`); continue; }
    if (`sha256:${o.sha256}` !== s.digest) errs.push(`${s.name}: sha256 != digest`);
    if (o.size !== s.transfer) errs.push(`${s.name}: size ${o.size} != transfer ${s.transfer}`);
  }
  return ok(!errs.length, `R3 ${ix.url}: runtime == ${BID}, ${snaps.length} entries [${names}] present with sha256 == digest, size == transfer`, errs.join('; '));
}

// GET one mutable R2 object o (a manifest or index: replaced in place under the same URL by each release, so a HEAD's
// content-length cannot tell an older one of the same length from this release's) on origin, with accept-encoding:
// identity, and compare its bytes with the manifest's entry. { body } when they match, else { why }. --published and
// --smoke share it.
async function getMutable(origin, o) {
  const r = await fetch(origin + o.url, { headers: { 'accept-encoding': 'identity' }, redirect: 'manual' }).catch((e) => ({ status: `ERR ${e.message}` }));
  if (r.status !== 200) return { why: `status ${r.status}` };
  let body;
  try { body = Buffer.from(await r.arrayBuffer()); } catch (e) { return { why: `body ERR ${e.message}` }; }
  const h = createHash('sha256').update(body).digest('hex');
  if (body.length !== o.size || h !== o.sha256) return { why: `published ${body.length} B sha256 ${h.slice(0, 16)}… != manifest ${o.size} B ${o.sha256.slice(0, 16)}… (not this release's upload)` };
  return { body };
}

// The committed G2 record (infra/ux-verdict.json) when it names exactly these inputs, else null.
function committedVerdict({ gallery, lockSha256, overlays }) {
  if (!fs.existsSync(VERDICT_FILE)) return null;
  let v; try { v = readJson(VERDICT_FILE); } catch { return null; }
  const same = v.schema === 'qed64-showcase.ux-verdict/v1' && v.gallery === gallery && v.lockSha256 === lockSha256
    && JSON.stringify(Object.entries(v.overlays || {}).sort()) === JSON.stringify(Object.entries(overlays).sort());
  return same ? v : null;
}

// G1: the gallery's static gate (no browser). G2: is the last green UX run recorded for this exact gallery?
function galleryGate(m) {
  const t0 = Date.now();
  const r = spawnSync(process.execPath, [path.join(SC, 'scripts/check-gallery.mjs')], { cwd: SC, encoding: 'utf8', timeout: 600e3, killSignal: 'SIGKILL', maxBuffer: 64 * MiB });
  const lines = `${r.stdout || ''}${r.stderr || ''}`.trim().split('\n');
  const last = lines.filter((l) => /CHECK-GALLERY/.test(l)).pop() || lines.pop() || '';
  // check-gallery indents the FAIL lines it relays from sim-gallery ("      FAIL  …"): match them too, so a G1 failure names
  // the failing case (closure lane: a sim-gallery timing failure in a rehearsal printed only "108 ok, 1 failed")
  const failed = lines.filter((l) => /^\s*FAIL/.test(l)).map((l) => l.replace(/^\s*FAIL\s+/, '').slice(0, 160));
  ok(r.status === 0, `G1 scripts/check-gallery.mjs exit 0 on gallery ${m.gallery.contentSha256.slice(0, 16)}… (${((Date.now() - t0) / 1000).toFixed(0)} s): ${last}`,
    r.error ? `${r.error.code || r.error.message}${r.signal ? ` ${r.signal}` : ''} (600 s watchdog)` : failed.slice(0, 4).join(' | '));
  // the verdict rule is scripts/lib/ux-record.mjs whyNotVerdict (full suite, rc 0, clean report with expected + skipped
  // == listed and only C19 skipped, no UX_ORIGIN, the local gallery served from start to end), and the run must have
  // tested THIS manifest's gallery, lock (pin.lockSha256) and overlay indexes (the uploaded /snapshots/<dir>/index.json,
  // keyed by the logical name: the directory is bound through the lock's overlays.<o>.url, i.e. lockSha256)
  const overlays = Object.fromEntries(m.options.overlays.map((o) => [o, (m.r2.find((x) => x.url === ovIndexUrl(m, o)) || {}).sha256 || null]));
  const runs = readRuns();
  const inputsNow = { gallery: m.gallery.contentSha256, lockSha256: m.pin.lockSha256, overlays };
  const { match, last: lastV, recorded } = verdictFor(inputsNow, runs);
  // the same rule as the freshness line (ux-record.mjs laterFailures): a later red full run on the same inputs is named
  const later = match ? laterFailures(match, inputsNow, runs) : [];
  const note = later.length ? `; BUT ${later.length} later full run(s) on the same inputs were NOT A VERDICT (${later.map((x) => `${x.run}: ${x.why.join(', ')}`).join('; ')}): not a clean bill of health, resolve before publishing` : '';
  // No local UX record of these inputs (CI, a fresh clone): the committed record written by --record-verdict, which
  // refused to record a verdict that a later red run on the same inputs contradicted.
  const rec = match ? null : committedVerdict(inputsNow);
  const what = `THIS gallery ${m.gallery.contentSha256.slice(0, 16)}…, lock ${m.pin.lockSha256.slice(0, 12)}… and overlays ${Object.keys(overlays).join(', ')}`;
  info(match ? `G2 UX: verdict run ${match.run} (${match.end}, lane ${match.lane}) was on ${what}${note}`
    : rec ? `G2 UX: verdict run ${rec.run} (${rec.end}, lane ${rec.lane}) was on ${what} (committed record ${rel(VERDICT_FILE)}, recorded ${rec.recordedAt})`
      : `G2 UX: NO verdict 'showcase.sh ux' run for this gallery ${m.gallery.contentSha256.slice(0, 16)}… + lock + overlays (last verdict: ${lastV ? `${lastV.end} on ${String(lastV.galleryEnd).slice(0, 16)}…` : `none among ${recorded} recorded runs`}; ${rel(VERDICT_FILE)} ${fs.existsSync(VERDICT_FILE) ? 'names other inputs' : 'absent'}); run 'scripts/showcase.sh ux' before publishing, then 'node scripts/deploy-manifest.mjs --record-verdict' for CI`);
  return { match, later, rec, overlays };
}

function writeOut(m) {
  fs.mkdirSync(path.join(OUT, 'rclone'), { recursive: true });
  for (const f of fs.readdirSync(path.join(OUT, 'rclone'))) fs.rmSync(path.join(OUT, 'rclone', f));
  fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify(m, null, 1) + '\n');
  const lists = {};
  for (const o of m.r2) (lists[`${o.group}.${o.phase}`] ||= []).push(o.relPath);
  for (const [k, v] of Object.entries(lists)) fs.writeFileSync(path.join(OUT, 'rclone', `${k}.files`), v.join('\n') + '\n');
  return Object.keys(lists).sort();
}
const optsFromArgv = () => ({
  overlays: val('--overlays', 'widgets8,widgets7').split(',').filter(Boolean),
  stockSnapshots: !flag('--no-stock-snapshots'), prefix: val('--prefix', ''),
  fromLock: flag('--from-lock'),
});
const optsFromManifest = (m) => ({ overlays: m.options.overlays, stockSnapshots: m.options.stockSnapshots, prefix: m.options.prefix, fromLock: m.options.source === 'lock' });
const loadManifest = () => { const p = path.join(OUT, 'manifest.json'); if (!fs.existsSync(p)) { console.error(`no ${rel(p)}: run 'node scripts/deploy-manifest.mjs' first`); process.exit(2); } return readJson(p); };

// ------------------------------------------------------------------------------------------ modes
if (MODE === 'generate') {
  const opts = optsFromArgv();
  for (const o of opts.overlays) if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(o)) { console.error(`bad overlay name ${o}`); process.exit(2); }
  let b;
  try { b = build(opts); } catch (e) { console.log(`FAIL ${e.message}`); console.log('DEPLOY-MANIFEST FAILED: nothing written'); process.exit(1); }
  validate(b);
  galleryGate(b.manifest);
  if (fails) {
    console.log(`DEPLOY-MANIFEST FAILED (${fails} FAIL): nothing written; ${rel(path.join(OUT, 'manifest.json'))} and the rclone lists are unchanged`);
    process.exit(1);
  }
  const lists = writeOut(b.manifest);
  info(`wrote ${rel(path.join(OUT, 'manifest.json'))} and ${lists.length} rclone lists: ${lists.join(', ')}`);
  console.log(`DEPLOY-MANIFEST OK ${b.manifest.totals.assets} assets, ${b.manifest.totals.r2Objects} R2 objects; gallery ${b.manifest.gallery.contentSha256}`);
  process.exit(0);
}
if (MODE === 'check') {
  const written = loadManifest();
  let b;
  try { b = build(optsFromManifest(written)); } catch (e) { console.log(`FAIL ${e.message}`); console.log('DEPLOY-MANIFEST CHECK FAILED'); process.exit(1); }
  const same = JSON.stringify(b.manifest, null, 1) + '\n' === fs.readFileSync(path.join(OUT, 'manifest.json'), 'utf8');
  if (!ok(same, 'C1 regenerated manifest (every file re-hashed) is byte-identical to the written manifest.json')) {
    const was = new Map([...written.assets.map((a) => [`asset ${a.path}`, a.sha256]), ...servedObjects(written).map((o) => [`r2 ${o.key}`, o.sha256])]);
    const now = new Map([...b.manifest.assets.map((a) => [`asset ${a.path}`, a.sha256]), ...servedObjects(b.manifest).map((o) => [`r2 ${o.key}`, o.sha256])]);
    const diff = [...new Set([...was.keys(), ...now.keys()])].filter((k) => was.get(k) !== now.get(k));
    // and the non-entry sections that differ (e.g. options.overlayDirs, new with the per-runtime overlay contract)
    const sect = [...new Set([...Object.keys(written), ...Object.keys(b.manifest)])].filter((k) => k !== 'assets' && k !== 'r2' && k !== 'release')
      .flatMap((k) => (k === 'options' ? [...new Set([...Object.keys(written.options || {}), ...Object.keys(b.manifest.options || {})])].map((o) => `options.${o}`) : [k]))
      .filter((k) => { const g = (m) => k.split('.').reduce((v, x) => (v == null ? v : v[x]), m); return JSON.stringify(g(written)) !== JSON.stringify(g(b.manifest)); });
    console.log(`     ${diff.length} entries differ: ${diff.slice(0, 8).join(' | ')}${sect.length ? `; ${sect.join(', ')} differ` : diff.length ? '' : ' (totals or formatting)'}`);
  }
  for (const [k, list] of Object.entries(b.manifest.r2.reduce((a, o) => ((a[`${o.group}.${o.phase}`] ||= []).push(o.relPath), a), {}))) {
    const p = path.join(OUT, 'rclone', `${k}.files`);
    ok(fs.existsSync(p) && fs.readFileSync(p, 'utf8') === list.join('\n') + '\n', `C2 rclone list ${k}.files lists exactly the manifest's ${list.length} file(s)`);
  }
  validate(b);
  galleryGate(b.manifest);
  console.log(fails ? `DEPLOY-MANIFEST CHECK FAILED (${fails} FAIL)` : `DEPLOY-MANIFEST CHECK OK (dry run: nothing uploaded); gallery ${b.manifest.gallery.contentSha256}`);
  process.exit(fails ? 1 : 0);
}
if (MODE === 'stage') {
  const m = loadManifest(); const dst = path.join(OUT, 'assets');
  fs.rmSync(dst, { recursive: true, force: true });
  for (const a of m.assets) {
    const to = path.join(dst, a.path); fs.mkdirSync(path.dirname(to), { recursive: true });
    cloneFile(path.join(SC, a.src), to);
  }
  const staged = walk(dst).map((f) => path.relative(dst, f)).sort();
  ok(JSON.stringify(staged) === JSON.stringify(m.assets.map((a) => a.path).sort()), `S1 ${rel(dst)} holds exactly the manifest's ${m.assets.length} assets`);
  const bad = m.assets.filter((a) => sha256File(path.join(dst, a.path)) !== a.sha256);
  ok(!bad.length, 'S2 every staged asset matches its manifest sha256', bad.map((a) => a.path).join(', '));
  console.log(fails ? 'STAGE-ASSETS FAILED' : `STAGE-ASSETS OK ${rel(dst)} (${(m.totals.assetBytes / MiB).toFixed(1)} MiB) — the [assets] directory of wrangler.toml`);
  process.exit(fails ? 1 : 0);
}
if (MODE === 'commands') {
  let E; try { E = loadDeployEnv(); } catch (e) { console.error(`deploy target refused: ${e.message}`); process.exit(3); }
  const m = loadManifest(); const bucket = val('--bucket', E.R2_BUCKET); const remote = val('--remote', E.R2_REMOTE);
  if (m.options.source === 'lock') { console.error('--commands refused (nothing printed): this is a --from-lock (shell-only) manifest; the upload needs the full manifest of a checkout that has the artifacts'); process.exit(3); }
  // the shared-bucket guard on what the printed commands would ACTUALLY write: this manifest's prefix in that bucket
  try { checkSharedBucket(bucket, m.options.prefix); } catch (e) { console.error(`--commands refused (nothing printed): ${e.message}. Regenerate with --prefix ${E.R2_PREFIX || "''"}`); process.exit(3); }
  if (!m.release) { console.error(`--commands refused (nothing printed): ${rel(path.join(OUT, 'manifest.json'))} predates release routing: regenerate it`); process.exit(3); }
  const q = (s) => (/[^A-Za-z0-9_./:=@,-]/.test(s) ? `'${s.replace(/'/g, `'\\''`)}'` : s);
  console.log('# NOT RUN. Publishing needs the owner\'s Cloudflare account and explicit go-ahead (docs/DEPLOY.md).');
  console.log(`# pin ${m.pin.buildId} (QED64 ${m.pin.qed64Commit.slice(0, 12)}), ${m.totals.r2Objects} R2 objects, ${m.totals.assets} assets; ${m.totals.releaseObjects} runtime and pack files come from the published release ${m.release.prefix}, not from this upload.`);
  const g = m.gallery ? m.gallery.contentSha256 : '(manifest predates the gallery hash: regenerate)';
  console.log(`# gallery content sha256 in this manifest: ${g}`);
  console.log(`# Scripted path (docs/DEPLOY-CLOUDFLARE.md): DRY_RUN=1 scripts/upload-artifacts.sh; scripts/upload-artifacts.sh; scripts/deploy-app.sh`);
  if (m.options.prefix !== E.R2_PREFIX) console.log(`# WARNING: this manifest's prefix ${JSON.stringify(m.options.prefix)} != R2_PREFIX ${JSON.stringify(E.R2_PREFIX)} (infra/deploy.env): regenerate with --prefix ${E.R2_PREFIX || "''"}`);
  console.log('scripts/showcase.sh gallery                         # static gate GREEN on that same gallery sha256');
  console.log('scripts/showcase.sh ux                              # full UX suite green on it (then `showcase.sh gallery` says UX CURRENT)');
  console.log('node scripts/deploy-manifest.mjs --check            # dry run green first (G1 OK, G2 "was on THIS gallery")');
  console.log('node scripts/deploy-manifest.mjs --stage-assets     # out/deploy/assets');
  console.log('# 1. immutable (digest-named) artifacts first, then 2. mutable indexes, then 3. the Worker.');
  console.log('#    (a review listing: scripts/upload-artifacts.sh splits the mutable lists into phases 2 and 3)');
  for (const phase of ['immutable', 'mutable']) {
    for (const [g, info0] of Object.entries(m.totals.groups)) {
      const list = path.join(OUT, 'rclone', `${g}.${phase}.files`);
      if (!fs.existsSync(list)) continue;
      const o = m.r2.find((x) => x.group === g);
      const sub = o.url.slice(1, o.url.length - o.relPath.length);   // e.g. "snapshots/widgets8/"
      console.log(`rclone copy --files-from-raw ${q(rel(list))} --checksum --transfers 4 --s3-chunk-size 64M --header-upload ${q(`Content-Type: ${phase === 'immutable' ? 'application/octet-stream' : 'application/json'}`)} ${q(info0.root)} ${q(`${remote}:${bucket}/${m.options.prefix}${sub}`)}`);
    }
  }
  console.log(`node scripts/lib/wrangler-config.mjs write wrangler.toml   # bucket_name ${bucket}, R2_PREFIX ${JSON.stringify(m.options.prefix)} (or 'check' an existing one)`);
  console.log('scripts/deploy-app.sh   # wrangler versions upload, the checks on the preview URL, wrangler versions deploy');
  console.log('node scripts/deploy-manifest.mjs --smoke https://<your-worker-host> --all --range');
  process.exit(0);
}
if (MODE === 'record-verdict') {
  const m = loadManifest();
  // the manifest must describe the checkout as it is now: same gallery content and the same lock bytes
  const g = galleryContentHash(path.join(SC, 'gallery')).contentSha256; const l = sha256File(path.join(SC, 'QED64.lock.json'));
  if (g !== m.gallery.contentSha256 || l !== m.pin.lockSha256) { console.error(`record-verdict refused: ${rel(path.join(OUT, 'manifest.json'))} is stale (gallery ${g.slice(0, 16)}… vs ${m.gallery.contentSha256.slice(0, 16)}…, lock ${l.slice(0, 12)}… vs ${m.pin.lockSha256.slice(0, 12)}…): regenerate it first`); process.exit(1); }
  const overlays = Object.fromEntries(m.options.overlays.map((o) => [o, (m.r2.find((x) => x.url === ovIndexUrl(m, o)) || {}).sha256 || null]));
  const runs = readRuns(); const inputsNow = { gallery: g, lockSha256: l, overlays };
  const { match } = verdictFor(inputsNow, runs);
  if (!match) { console.error(`record-verdict refused: no verdict 'showcase.sh ux' run on this gallery + lock + overlays in out/ux/showcase-ux-runs.jsonl (run scripts/showcase.sh ux)`); process.exit(1); }
  const later = laterFailures(match, inputsNow, runs);
  if (later.length) { console.error(`record-verdict refused: ${later.length} later full run(s) on the same inputs were NOT A VERDICT (${later.map((x) => x.run).join(', ')}): resolve first`); process.exit(1); }
  const rec = { schema: 'qed64-showcase.ux-verdict/v1', note: 'Written by node scripts/deploy-manifest.mjs --record-verdict: the G2 verdict a checkout without out/ux (CI) accepts. Commit it with the gallery/lock it names.',
    gallery: g, lockSha256: l, overlays, run: match.run, end: match.end, lane: match.lane, pin: m.pin.id, recordedAt: new Date().toISOString() };
  fs.writeFileSync(VERDICT_FILE, JSON.stringify(rec, null, 1) + '\n');
  console.log(`RECORD-VERDICT OK: ${rel(VERDICT_FILE)} names run ${match.run} (${match.end}) on gallery ${g.slice(0, 16)}…, lock ${l.slice(0, 12)}…, overlays ${Object.keys(overlays).join(', ')}; commit it`);
  process.exit(0);
}
if (MODE === 'published') {
  const origin = val('--published', '').replace(/\/$/, '');
  if (!/^https?:\/\//.test(origin)) { console.error('usage: --published <http(s)://origin>'); process.exit(2); }
  const m = loadManifest(); const BID = m.pin.buildId;
  let bad = 0, n = 0; const t0 = Date.now();
  const fail = (u, why) => { bad++; if (bad <= 20) console.log(`FAIL ${u} — ${why}`); };
  const head = (u) => fetch(origin + u, { method: 'HEAD', headers: { 'accept-encoding': 'identity' }, redirect: 'manual' }).catch((e) => ({ status: `ERR ${e.message}`, headers: new Headers() }));
  const fetched = new Map();
  const skipPhase3 = flag('--before-phase-3');
  if (skipPhase3) info(`--before-phase-3: not comparing ${servedObjects(m).filter(isPhase3).map((o) => o.url).join(', ')}`);
  for (const o of servedObjects(m)) {
    if (skipPhase3 && isPhase3(o)) continue;
    n++;
    if (o.immutable) {
      const r = await head(o.url);
      if (r.status !== 200) fail(o.url, `status ${r.status}`);
      else if (Number(r.headers.get('content-length')) !== o.size) fail(o.url, `content-length ${r.headers.get('content-length')} != ${o.size}`);
      continue;
    }
    const g = await getMutable(origin, o);
    if (g.why) { fail(o.url, g.why); continue; }
    fetched.set(o.url, g.body);
  }
  ok(!bad, `PUBLISHED-OBJECTS ${origin}: ${n - bad}/${n} R2 objects of this manifest (the release's included) are published (immutable: HEAD status 200 + content-length; manifests and indexes: GET sha256 == manifest) in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
  // R3 on the overlay indexes, which a --from-lock manifest could not read locally (they are not tracked in git)
  for (const o of m.options.overlays) {
    const ix = m.r2.find((x) => x.url === ovIndexUrl(m, o));
    if (ix && fetched.has(ix.url)) r3Index(m, BID, ix, JSON.parse(fetched.get(ix.url).toString('utf8')));
  }
  console.log(fails ? `PUBLISHED FAILED: ${origin} does not serve this manifest's artifacts; upload them first (scripts/upload-artifacts.sh)` : `PUBLISHED OK ${origin}`);
  process.exit(fails ? 1 : 0);
}
if (MODE === 'smoke') {
  const origin = val('--smoke', '').replace(/\/$/, '');
  if (!/^https?:\/\//.test(origin)) { console.error('usage: --smoke <http(s)://origin>'); process.exit(2); }
  const m = loadManifest(); const all = flag('--all'); const seen = new Set();
  const pool = servedObjects(m).filter((o) => !(flag('--before-phase-3') && isPhase3(o)));
  const pick = all ? pool : pool.filter((o) => {
    if (!o.immutable || o.url.endsWith('.snapz')) return true;
    const fam = o.url.replace(/\.[0-9a-f]{20}\.part-\d+$/, '').replace(/\.part-\d+$/, '');
    if (seen.has(fam)) return false; seen.add(fam); return true;
  });
  // An index.html is requested at its canonical URL, the way the gallery and browsers reach it: Workers static assets
  // (html_handling = "auto-trailing-slash") answer ".../index.html" with a redirect to ".../", and a bare "/" is
  // ROOT_REDIRECTed to the gallery, so the root page is checked at "/?smoke=1" (a query, like the gallery's
  // "/?snapshots=…" iframe). Redirects are not followed: a 3xx is reported, never measured on its target.
  const assetUrl = (p) => (p === 'index.html' ? '/?smoke=1' : p.endsWith('/index.html') ? `/${p.slice(0, -'index.html'.length)}` : `/${p}`);
  const targets = [...m.assets.map((a) => ({ url: assetUrl(a.path), size: a.size, artifact: false })), ...pick.map((o) => ({ url: o.url, size: o.size, artifact: true, r2: o }))];
  const nMutable = pick.filter((o) => !o.immutable).length;
  let bad = 0, mutableOk = 0;
  for (const t of targets) {
    const head = (u) => fetch(origin + u, { method: 'HEAD', headers: { 'accept-encoding': 'identity' }, redirect: 'manual' }).catch((e) => ({ status: `ERR ${e.message}`, headers: new Headers() }));
    let r = await head(t.url);
    // Workers static assets (html_handling = "auto-trailing-slash", QED64's production setting too) redirect
    // "/x/name.html" to its canonical "/x/name" (query kept): accept exactly that one redirect for a .html asset
    // and check the canonical URL instead (scripts/serve.mjs serves the .html directly, without a redirect).
    if (/\.html$/.test(t.url) && [301, 302, 307, 308].includes(r.status)) {
      const loc = new URL(r.headers.get('location') || '', origin + t.url);
      if (loc.origin === new URL(origin).origin && loc.pathname === t.url.replace(/\.html$/, '')) r = await head(loc.pathname + loc.search);
    }
    const h = r.headers; const errs = [];
    if (r.status !== 200) errs.push(`status ${r.status}`);
    if (h.get('cross-origin-opener-policy') !== 'same-origin' || h.get('cross-origin-embedder-policy') !== 'require-corp' || h.get('cross-origin-resource-policy') !== 'same-origin') errs.push('isolation headers');
    const wantCc = isImmutable(t.url.split('?')[0]) ? 'public, max-age=31536000, immutable' : 'public, max-age=0, must-revalidate';
    if (h.get('cache-control') !== wantCc) errs.push(`cache-control ${h.get('cache-control')}`);
    // Artifacts must arrive byte-exact: content-length == size and no content-encoding (QED64's worker and the
    // gallery refuse transformed chunks). A page asset (HTML/JS/CSS) is compressed by the edge (Cloudflare serves
    // `content-encoding: br` and omits content-length on HEAD even for accept-encoding: identity): for those, GET it
    // and compare the decoded body's length with the asset's size instead.
    if (t.artifact) {
      if (Number(h.get('content-length')) !== t.size) errs.push(`content-length ${h.get('content-length')} != ${t.size}`);
      if (h.get('content-encoding')) errs.push(`content-encoding ${h.get('content-encoding')}`);
    } else if (h.get('content-encoding') || h.get('content-length') === null) {
      const g = await fetch(origin + (r.url ? new URL(r.url).pathname + new URL(r.url).search : t.url), { headers: { 'accept-encoding': 'identity' }, redirect: 'follow' }).catch((e) => null);
      const n = g ? (await g.arrayBuffer()).byteLength : -1;   // fetch decodes br/gzip; n is the original size
      if (n !== t.size) errs.push(`decoded body ${n} B != ${t.size} (content-encoding ${h.get('content-encoding')})`);
    } else if (Number(h.get('content-length')) !== t.size) errs.push(`content-length ${h.get('content-length')} != ${t.size}`);
    const ctErr = contentTypeProblem(t.url, h.get('content-type'));
    if (ctErr) errs.push(ctErr);
    const lines = errs.length ? [`FAIL HEAD ${t.url} — ${errs.join('; ')}`] : [];
    // A manifest or index answers HEAD with the right size whenever an older one of the same length is still up (the
    // deploy rehearsal of pin O, order B: snapshots/index.json, 701 B at H and at O), so GET it and compare its sha256
    // as --published does. Immutable keys stay HEAD-only: their URL names their content, and packs reach hundreds of MB.
    if (t.r2 && !t.r2.immutable && r.status === 200) {
      const g = await getMutable(origin, t.r2);
      if (g.why) lines.push(`FAIL GET ${t.url} — ${g.why}`); else mutableOk++;
    }
    if (lines.length) { bad++; if (bad <= 20) for (const l of lines) console.log(l); }
  }
  if (flag('--range')) {
    // single-range GETs on the largest .snapz (infra/worker.js; lean4game parity). Bodies are tiny or aborted.
    const z = m.r2.filter((o) => o.url.endsWith('.snapz')).sort((a, b) => b.size - a.size)[0];
    const rget = async (headers) => {
      const ac = new AbortController();
      const r = await fetch(origin + z.url, { headers: { 'accept-encoding': 'identity', ...headers }, signal: ac.signal }).catch((e) => ({ status: `ERR ${e.message}`, headers: new Headers() }));
      const small = r.status === 206 || r.status === 416 ? new Uint8Array(await r.arrayBuffer()) : null;
      if (r.body && small === null) ac.abort();
      return { r, small };
    };
    const iso = (h) => h.get('cross-origin-opener-policy') === 'same-origin' && h.get('cross-origin-embedder-policy') === 'require-corp' && h.get('cross-origin-resource-policy') === 'same-origin';
    const a = await rget({ range: 'bytes=0-99' });
    ok(a.r.status === 206 && a.r.headers.get('content-range') === `bytes 0-99/${z.size}` && Number(a.r.headers.get('content-length')) === 100 && a.small?.length === 100
      && a.r.headers.get('accept-ranges') === 'bytes' && iso(a.r.headers) && !a.r.headers.get('content-encoding'),
      `RANGE GET ${z.url} bytes=0-99 -> ${a.r.status}, content-range ${a.r.headers.get('content-range')}, content-length ${a.r.headers.get('content-length')} (${a.small?.length ?? '-'} B body), isolation headers`);
    const b = await rget({ range: `bytes=${z.size}-` });
    ok(b.r.status === 416 && b.r.headers.get('content-range') === `bytes */${z.size}` && iso(b.r.headers), `RANGE GET bytes=${z.size}- (past the end) -> ${b.r.status}, content-range ${b.r.headers.get('content-range')}`);
    const c = await rget({ range: 'bytes=0-99', 'if-range': '"not-this-version"' });
    ok(c.r.status === 200 && Number(c.r.headers.get('content-length')) === z.size, `RANGE GET with a mismatched If-Range -> ${c.r.status} (full object, content-length ${c.r.headers.get('content-length')})`);
  }
  ok(!bad, `SMOKE ${origin}: ${targets.length} URLs (${m.assets.length} assets + ${pick.length}/${servedObjects(m).length} R2 keys, the release's included) answer 200 with size, isolation, cache and content-type headers, and ${mutableOk}/${nMutable} manifests and indexes GET with the manifest's sha256${bad ? `; ${bad} bad` : ''}`);
  console.log(fails ? 'SMOKE FAILED' : 'SMOKE OK');
  process.exit(fails ? 1 : 0);
}
