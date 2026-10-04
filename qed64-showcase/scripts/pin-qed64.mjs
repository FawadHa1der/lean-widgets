#!/usr/bin/env node
// pin-qed64.mjs — QED64 as a pinned dependency (BUILD-PLAN §2 S0.2–S0.5). Node, no dependencies.
//
// Multiple pins (docs/REPIN-LOG.md "Multiple pins"): every command acts on ONE registered pin, `--pin <id>` (default: the
// active pin). Pins are keyed by QED64 COMMIT (id = its first 7 hex digits), because two commits can serve the same runtime
// buildId with different shells/workers. A pin's identity — QED64 commit, promote, buildId, kernel — is its descriptor
// pins/<id>/pin.json (scripts/lib/pins.mjs); its lock, QED64-PIN and vendored sources live beside it in pins/<id>/, its
// release clone in release/<id>/. Nothing here switches the active pin (`showcase.sh pin use <id>`).
//
//   node scripts/pin-qed64.mjs pin --pin <id>
//                                       S0.2 precondition (QED64 HEAD == the descriptor's commit, clean), S0.3 vendor
//                                       (git archive) -> pins/<id>/vendor-qed64, S0.4 release clone (cp -c per file)
//                                       -> release/<id>, then write pins/<id>/QED64.lock.json + QED64-PIN; S0.2 is
//                                       re-checked after the clone (HEAD unchanged, still clean, dist/ not rewritten)
//   node scripts/pin-qed64.mjs verify [--pin <id>] [--allow-skip] [--strict]
//                                       S0.5 chain of trust; one "OK"/"FAIL" line per check;
//                                       exit 1 on any FAIL. A check that cannot run (docker not
//                                       reachable, Playwright not installed) is a FAIL unless
//                                       --allow-skip is passed, in which case it prints SKIP.
//                                       The Docker image behind qed64-toolchain:emsdk-6.0.5 (a tag QED64's
//                                       own toolchain build rewrites) is a rebuild-only input: a mismatch
//                                       prints DRIFT (not FAIL; `showcase.sh native` refuses on it) unless
//                                       --strict.
//   node scripts/pin-qed64.mjs record-widgets-hash [--pin <id>]
//                                       recompute WIDGETS_SOURCE_HASH over $W/widgets-src, require it
//                                       to equal SOURCE-HASH.txt, check the export against its commit
//                                       (SOURCE-COMMIT.txt), and write hash + WIDGETS_COMMIT into that pin's lock
//
// The widget sources: $W/widgets-src is a `git archive` of this repository's packages/ at WIDGETS_COMMIT
// (scripts/export-widgets.mjs; scripts/lib/widgets-src.mjs). WIDGETS_SOURCE_HASH (amendment 1) = sha256 over the
// concatenation of "<sha256>  <relpath>\n" for every file of the export except its metadata files, ordered by relpath
// in byte (LC_ALL=C) order. That is exactly the bytes of SOURCE-FILES.sha256, so sha256(SOURCE-FILES.sha256) ==
// SOURCE-HASH.txt line 1; verify recomputes it from the file contents AND re-derives every file's git blob id against
// `git ls-tree -r WIDGETS_COMMIT packages/`.
//
// Locations (scripts/lib/env.mjs): QED64_REPO (the QED64 checkout, read-only), QED64_KERNEL_BUILD (the kernel build,
// read-only), QED64_SHOWCASE_WORK ($W). The lock records them as placeholders, never as this machine's paths.
//
// Every operation on the QED64 tree is read-only: git rev-parse / status --no-optional-locks /
// archive / show / ls-tree, and cp -c (APFS clonefile; new inodes, never hard links).
import { execFileSync, spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { activePinId, pinDescriptor, repoPinDir, releaseDir, ID_RE } = await import(path.join(SC, 'scripts/lib/pins.mjs'));
const ENV = await import(path.join(SC, 'scripts/lib/env.mjs'));
const WSRC = await import(path.join(SC, 'scripts/lib/widgets-src.mjs'));
const cmd0 = process.argv[2];
let Q = '', K = '';
try {
  if (cmd0 === 'pin' || cmd0 === 'verify') { Q = ENV.need('QED64_REPO'); K = ENV.need('QED64_KERNEL_BUILD'); }
} catch (e) { console.error(`pin-qed64: ${e.message}`); process.exit(2); }
const QED64_UPSTREAM = 'https://github.com/FawadHa1der/QED64';
// --pin <id> (default: the active pin). Its descriptor names the QED64 commit (QPIN), the promote, the runtime buildId and
// the kernel commit that built the served lean.wasm (QED64's tracked pipeline/toolchain/KERNEL-PIN at QPIN, first token;
// recorded in the lock as qed64.kernel and re-checked by verify #9).
const pinArg = process.argv.indexOf('--pin');
const ID = pinArg > 0 ? process.argv[pinArg + 1] : activePinId();
if (!ID_RE.test(ID || '')) { console.error(`--pin needs a pin id: the 7-hex prefix of the QED64 commit (got ${ID})`); process.exit(2); }
const DESC = pinDescriptor(ID);
const BID = DESC.buildId;
const QPIN = DESC.qed64.commit;
const QPROMOTE = DESC.qed64.promote;
const KERNEL = DESC.qed64.kernel;
const KERNEL_PIN_PATH = 'pipeline/toolchain/KERNEL-PIN';
const R = releaseDir(ID);
const STORE = repoPinDir(ID);
const VENDOR = path.join(STORE, 'vendor-qed64');
const LOCK = path.join(STORE, 'QED64.lock.json');
const PIN = path.join(STORE, 'QED64-PIN');
const DOCKER_IMAGE = ENV.DOCKER_IMAGE;
const DOCKER_ID = '8b6698bbf474';
const PLAYWRIGHT = '1.62.1';
const BROWSER_REV = '1234';

const VENDOR_PATHS = [
  'pipeline/snapshot', 'pipeline/toolchain/artifact-paths.mjs', 'pipeline/artifacts/olean-imports.mjs',
  'pipeline/artifacts/unpack.mjs', 'public/workers', 'frontend/src/qed64-boot.ts',
  'frontend/src/resident-session.ts', 'frontend/src/lsp-relay.ts', 'src/install/profiles.ts',
  'src/runtime/client.ts', 'src/runtime/snapshots.ts', 'frontend/package.json',
  'frontend/package-lock.json', 'frontend/vite.config.ts', 'frontend/index.html',
];
// git-tracked JSON consumed from public/ (S0.5 #1)
const TRACKED_JSON = [
  'public/runtime/runtime-manifest.json', 'public/profiles/index.json',
  'public/profiles/lean-core.manifest.json', 'public/profiles/mathlib-essential.manifest.json',
  'public/snapshots/index.json',
];

const git = (...a) => execFileSync('git', ['--no-optional-locks', '-C', Q, ...a], { maxBuffer: 1 << 30 });
const sha256File = (p) => new Promise((res, rej) => {
  const h = createHash('sha256');
  fs.createReadStream(p, { highWaterMark: 8 << 20 }).on('data', (d) => h.update(d)).on('error', rej).on('end', () => res(h.digest('hex')));
});
const sha256Buf = (b) => createHash('sha256').update(b).digest('hex');
const gitBlobId = (b) => createHash('sha1').update(`blob ${b.length}\0`).update(b).digest('hex');
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
function walk(dir, base = dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, base, out);
    else if (e.isFile()) out.push(path.relative(base, p));
    else throw new Error(`unexpected non-file ${p}`);
  }
  return out.sort();
}
const urlToPublic = (u) => 'public' + u;
const kernelPinAt = (rev) => git('show', `${rev}:${KERNEL_PIN_PATH}`).toString().split(/\s+/)[0];
// WIDGETS_SOURCE_HASH recompute (see header; scripts/lib/widgets-src.mjs). Returns { hash, files, listing }.
const WIDGETS_SRC = WSRC.WIDGETS_SRC;
const widgetsSourceHash = async (dir = WIDGETS_SRC) => WSRC.widgetsSourceHash(dir);
const recordedWidgetsHash = (dir = WIDGETS_SRC) => WSRC.recordedHash(dir);
 // "/runtime/chunks/x" -> "public/runtime/chunks/x"

// ---- the consumed file set (relative to $Q, and to $R with the same relative path) ----
function releaseSet() {
  const files = walk(path.join(Q, 'dist')).map((f) => 'dist/' + f);
  const rm = readJson(path.join(Q, 'public/runtime/runtime-manifest.json'));
  files.push('public/runtime/runtime-manifest.json', `public/runtime/runtime-manifest.${BID}.json`);
  for (const f of Object.values(rm.files)) for (const c of f.chunks) files.push(urlToPublic(c.url));
  files.push('public/profiles/index.json');
  const pidx = readJson(path.join(Q, 'public/profiles/index.json'));
  for (const p of pidx.profiles) {
    files.push(urlToPublic(p.manifest));
    const m = readJson(path.join(Q, urlToPublic(p.manifest)));
    for (const part of m.content.pack.transport.parts) files.push(urlToPublic(part.url));
  }
  files.push('public/snapshots/index.json');
  for (const s of readJson(path.join(Q, 'public/snapshots/index.json')).snapshots) files.push(urlToPublic(s.url));
  return [...new Set(files)];
}

async function pin() {
  // S0.2 precondition (read-only)
  const head = git('rev-parse', 'HEAD').toString().trim();
  const dirty = git('status', '--porcelain').toString();
  if (head !== QPIN) throw new Error(`QED64 HEAD ${head} != QPIN ${QPIN}`);
  const kpin = kernelPinAt(QPIN);
  if (kpin !== KERNEL) throw new Error(`QED64 ${KERNEL_PIN_PATH} at QPIN names kernel ${kpin}, not KERNEL ${KERNEL}`);
  if (dirty.trim()) throw new Error(`QED64 tree not clean:\n${dirty}`);
  const qbid = readJson(path.join(Q, 'public/runtime/runtime-manifest.json')).buildId;
  if (qbid !== BID) throw new Error(`QED64 serves runtime ${qbid}, the descriptor pins/${ID}/pin.json names ${BID}`);
  // dist/ is built, not tracked: snapshot its file list and mtimes so a rebuild DURING the clone is detected (S0.2 again)
  const distStamp = () => walk(path.join(Q, 'dist')).map((f) => `${f} ${fs.statSync(path.join(Q, 'dist', f)).mtimeMs} ${fs.statSync(path.join(Q, 'dist', f)).size}`).join('\n');
  const stamp0 = distStamp();
  console.log(`S0.2 OK  QED64 HEAD=${head} clean, serves ${qbid}`);

  // S0.3 vendor via git archive (object store read only)
  fs.rmSync(VENDOR, { recursive: true, force: true });
  fs.mkdirSync(VENDOR, { recursive: true });
  await new Promise((res, rej) => {
    const ga = spawn('git', ['--no-optional-locks', '-C', Q, 'archive', QPIN, ...VENDOR_PATHS], { stdio: ['ignore', 'pipe', 'inherit'] });
    const tar = spawn('tar', ['-x', '-C', VENDOR], { stdio: ['pipe', 'inherit', 'inherit'] });
    ga.stdout.pipe(tar.stdin);
    let n = 0; const done = (c, who) => { if (c !== 0) rej(new Error(`${who} exit ${c}`)); else if (++n === 2) res(); };
    ga.on('close', (c) => done(c, 'git archive')); tar.on('close', (c) => done(c, 'tar'));
  });
  const vfiles = walk(VENDOR);
  const pinLines = [];
  for (const f of vfiles) pinLines.push(`${await sha256File(path.join(VENDOR, f))}  ${f}`);
  fs.writeFileSync(PIN, `# QED64-PIN: sha256 of every file in vendor/qed64 (git archive ${QPIN})\n` + pinLines.join('\n') + '\n');
  console.log(`S0.3 OK  vendored ${vfiles.length} files -> ${path.relative(SC, VENDOR)} (vendor/qed64 when this pin is active), ${path.relative(SC, PIN)} written`);

  // S0.4 release clone (cp -c = clonefile per file; never a hard link)
  const set = releaseSet();
  fs.rmSync(R, { recursive: true, force: true });
  const files = {};
  let bytes = 0;
  for (const rel of set) {
    const src = path.join(Q, rel), dst = path.join(R, rel);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    execFileSync('cp', ['-c', src, dst]);
    const st = fs.statSync(dst);
    files[rel] = { bytes: st.size, sha256: await sha256File(dst) };
    bytes += st.size;
  }
  console.log(`S0.4 OK  cloned ${set.length} files (${(bytes / 1e9).toFixed(3)} GB logical) -> ${path.relative(SC, R)}`);
  const head1 = git('rev-parse', 'HEAD').toString().trim(), dirty1 = git('status', '--porcelain').toString();
  if (head1 !== QPIN || dirty1.trim() || distStamp() !== stamp0) throw new Error(`QED64 changed during the clone (HEAD ${head1}, ${dirty1.trim() ? 'dirty' : 'clean'}, dist ${distStamp() === stamp0 ? 'same' : 'REWRITTEN'}): re-run pin`);
  console.log('S0.4 OK  QED64 HEAD, status and dist/ unchanged during the clone');

  // toolchain pins (S0.5 #7)
  const lm = readJson(path.join(K, 'mathlib/mathlib4/lake-manifest.json'));
  const pw = lm.packages.find((p) => p.name === 'proofwidgets');
  const toolchain = {
    native64: {
      dir: '${QED64_KERNEL_BUILD}/native',
      NATIVE_COMMIT: fs.readFileSync(path.join(K, 'native/NATIVE-COMMIT'), 'utf8').trim(),
      BUILT_COMMIT: fs.readFileSync(path.join(K, 'BUILT-COMMIT'), 'utf8').trim(),
      'stage1/bin/lean': await sha256File(path.join(K, 'native/stage1/bin/lean')),
      'stage1/bin/lake': await sha256File(path.join(K, 'native/stage1/bin/lake')),
    },
    docker: { image: DOCKER_IMAGE, id: DOCKER_ID },
    mathlib: { commit: fs.readFileSync(path.join(K, 'mathlib/MATHLIB-COMMIT'), 'utf8').trim(), proofwidgets: pw.rev },
    node: process.version,
    playwright: { version: PLAYWRIGHT, browserRevision: BROWSER_REV },
  };

  // preserve keys other stages own (e.g. WIDGETS_SOURCE_HASH from S0.1)
  let prev = {};
  try { prev = readJson(LOCK); } catch {}
  const { schema: _s, qed64: _q, vendor: _v, release: _r, anchors: _a, toolchain: _t, pinnedAt: _p, ...keep } = prev;
  const anchors = {};
  for (const p of TRACKED_JSON) anchors[p] = { gitBlob: git('rev-parse', `${QPIN}:${p}`).toString().trim(), sha256: files[p].sha256 };
  const lock = {
    schema: 'qed64-showcase.lock/v1',
    pinnedAt: new Date().toISOString(),
    qed64: { repo: QED64_UPSTREAM, checkout: '${QED64_REPO}', commit: QPIN, promote: QPROMOTE, buildId: BID, kernel: KERNEL },
    vendor: { dir: 'vendor/qed64', paths: VENDOR_PATHS, files: vfiles.length, pinFile: 'QED64-PIN', pinSha256: sha256Buf(fs.readFileSync(PIN)) },
    release: { dir: path.relative(SC, R), files },
    anchors,
    toolchain,
    ...keep,
  };
  fs.writeFileSync(LOCK, JSON.stringify(lock, null, 2) + '\n');
  console.log(`PIN DONE  ${path.relative(SC, LOCK)} (${Object.keys(files).length} release files) + QED64-PIN (${vfiles.length} vendor files); activate with: scripts/showcase.sh pin use ${ID}`);
}

async function verify({ allowSkip = false, strictToolchain = false } = {}) {
  let fails = 0, skips = 0, drifts = 0;
  const ok = (cond, msg, detail = '') => { console.log(`${cond ? 'OK  ' : 'FAIL'} ${msg}${detail ? ' — ' + detail : ''}`); if (!cond) fails++; };
  // a check that could not run is a FAIL unless --allow-skip
  const skip = (msg) => { if (allowSkip) { skips++; console.log(`SKIP ${msg} (--allow-skip)`); } else { fails++; console.log(`FAIL ${msg} (check could not run; pass --allow-skip to tolerate)`); } };
  // DRIFT: a rebuild-only input (the Docker image behind a tag QED64 owns) no longer matches the lock. The
  // served artifacts do not depend on it (they are verified by hash in #1-#6, #8); only re-running the
  // native build does, and `showcase.sh native` refuses on the same comparison. Not a FAIL unless --strict.
  const drift = (cond, msg, detail = '') => {
    if (cond) return ok(true, msg, detail);
    if (strictToolchain) return ok(false, msg, detail);
    drifts++; console.log(`DRIFT ${msg}${detail ? ' — ' + detail : ''} (rebuild-only input: affects 'showcase.sh native', which refuses; served artifacts unaffected; --strict makes this a FAIL)`);
  };
  const lock = readJson(LOCK);
  let act = null; try { act = activePinId(); } catch { /* no active pin yet */ }
  console.log(`     pin ${ID} = QED64 ${QPIN.slice(0, 12)}, runtime ${BID} (${ID === act ? 'ACTIVE' : 'staged'}): ${path.relative(SC, STORE)}/, ${path.relative(SC, R)}/`);
  ok(lock.qed64.commit === QPIN && lock.qed64.buildId === BID && lock.qed64.promote === QPROMOTE, 'lock pins the descriptor\'s commit, promote and buildId', `${lock.qed64.commit.slice(0, 12)} ${lock.qed64.buildId}`);
  // 9. the kernel that built the served lean.wasm (QED64's own KERNEL-PIN at QPIN) == KERNEL == lock
  let kpin = null; try { kpin = kernelPinAt(QPIN); } catch {}
  ok(kpin === KERNEL && lock.qed64.kernel === KERNEL, `#9 ${KERNEL_PIN_PATH} at QPIN == KERNEL == lock qed64.kernel`, `${String(kpin).slice(0, 10)} / lock ${String(lock.qed64.kernel).slice(0, 10)}`);
  let objOk = true; try { git('cat-file', '-e', `${QPIN}^{commit}`); } catch { objOk = false; }
  ok(objOk, `QPIN ${QPIN.slice(0, 12)} present in QED64 object store`);

  // 1. tracked JSON == git show QPIN:<path>, byte for byte
  for (const p of TRACKED_JSON) {
    const g = git('show', `${QPIN}:${p}`);
    const local = fs.readFileSync(path.join(R, p));
    ok(Buffer.compare(g, local) === 0, `#1 ${p} == git show QPIN:${p}`, `sha256 ${sha256Buf(local).slice(0, 16)}`);
  }
  // 2. per-build manifest identical to tracked one
  const rmBuf = fs.readFileSync(path.join(R, 'public/runtime/runtime-manifest.json'));
  const rmBid = fs.readFileSync(path.join(R, `public/runtime/runtime-manifest.${BID}.json`));
  const rm = JSON.parse(rmBuf);
  ok(Buffer.compare(rmBuf, rmBid) === 0 && rm.buildId === BID, `#2 runtime-manifest.${BID}.json identical to tracked manifest; buildId=${rm.buildId}`);
  // 3. runtime chunks + reassembled files
  for (const [name, f] of Object.entries(rm.files)) {
    const whole = createHash('sha256'); let total = 0; let chunkOk = true;
    for (const c of f.chunks) {
      const b = fs.readFileSync(path.join(R, urlToPublic(c.url)));
      const good = b.length === c.bytes && sha256Buf(b) === c.sha256;
      if (!good) { chunkOk = false; console.log(`     chunk mismatch ${c.url}`); }
      whole.update(b); total += b.length;
    }
    ok(chunkOk, `#3 ${name}: ${f.chunks.length} chunks match manifest sha256/bytes`);
    const d = whole.digest('hex');
    ok(d === f.sha256 && total === f.bytes, `#3 reassembled ${name} sha256 == manifest`, `${d.slice(0, 24)}… ${total} B`);
  }
  ok(rm.files['lean.wasm'].sha256.startsWith(BID.slice('wasm64-'.length)), `#3 buildId == wasm64-sha256(lean.wasm)[0:16]`);
  // 4. profile parts (+ transport digest over the concatenation)
  const pidx = readJson(path.join(R, 'public/profiles/index.json'));
  ok(pidx.runtime.buildId === BID, `#4 profiles/index.json runtime.buildId == ${BID}`);
  for (const p of pidx.profiles) {
    const m = readJson(path.join(R, urlToPublic(p.manifest)));
    const t = m.content.pack.transport; const whole = createHash('sha256'); let partsOk = true; let total = 0;
    for (const part of t.parts) {
      const fp = path.join(R, urlToPublic(part.url));
      const h = createHash('sha256');
      await new Promise((res, rej) => fs.createReadStream(fp, { highWaterMark: 8 << 20 })
        .on('data', (d) => { h.update(d); whole.update(d); total += d.length; }).on('error', rej).on('end', res));
      const dg = 'sha256:' + h.digest('hex');
      if (dg !== part.digest || fs.statSync(fp).size !== part.byteLength) { partsOk = false; console.log(`     part mismatch ${part.url}`); }
    }
    ok(partsOk, `#4 ${p.id}: ${t.parts.length} parts match manifest digests/byteLength`);
    ok('sha256:' + whole.digest('hex') === t.digest && total === t.byteLength, `#4 ${p.id}: concatenated transport digest == manifest`, `${total} B`);
  }
  // 5. snapz
  const sidx = readJson(path.join(R, 'public/snapshots/index.json'));
  for (const s of sidx.snapshots) {
    const fp = path.join(R, urlToPublic(s.url));
    const d = 'sha256:' + await sha256File(fp);
    ok(d === s.digest && fs.statSync(fp).size === s.transfer && s.runtime === BID, `#5 ${path.basename(s.url)} sha256 == index digest, size == transfer, runtime == BID`, d.slice(7, 23));
  }
  // 6. dist + every release file vs lock; clones, not hard links
  const want = lock.release.files;
  const have = walk(R);
  const missing = Object.keys(want).filter((f) => !have.includes(f));
  const extra = have.filter((f) => !(f in want));
  ok(!missing.length && !extra.length, `#6 release file set == lock (${have.length} files)`, [missing.length && `missing ${missing.slice(0, 3)}`, extra.length && `extra ${extra.slice(0, 3)}`].filter(Boolean).join('; '));
  let bad = [], linked = [];
  for (const f of have) {
    if (!(f in want)) continue;
    const st = fs.statSync(path.join(R, f));
    if (st.nlink !== 1) linked.push(f);
    if (st.size !== want[f].bytes || await sha256File(path.join(R, f)) !== want[f].sha256) bad.push(f);
  }
  ok(!bad.length, `#6 every release file sha256 == lock (dist/ ${have.filter((f) => f.startsWith('dist/')).length} files + public/)`, bad.slice(0, 3).join(', '));
  ok(!linked.length, '#6 no release file is a hard link (nlink == 1 everywhere)', linked.slice(0, 3).join(', '));
  const ids = new Set();
  for (const f of have.filter((f) => /^dist\/assets\/.*\.js$/.test(f))) for (const m of fs.readFileSync(path.join(R, f), 'latin1').matchAll(/wasm64-[0-9a-f]{16}/g)) ids.add(m[0]);
  ok(ids.size === 1 && ids.has(BID), `#6 bundle buildIds in dist/assets/*.js == {${[...ids].join(',')}}`);
  // 7. toolchain pins
  const tc = lock.toolchain;
  ok(fs.readFileSync(path.join(K, 'native/NATIVE-COMMIT'), 'utf8').trim() === tc.native64.NATIVE_COMMIT, `#7 NATIVE-COMMIT == ${tc.native64.NATIVE_COMMIT.slice(0, 10)}`);
  ok(fs.readFileSync(path.join(K, 'BUILT-COMMIT'), 'utf8').trim() === tc.native64.BUILT_COMMIT, `#7 BUILT-COMMIT == ${tc.native64.BUILT_COMMIT.slice(0, 10)}`);
  for (const b of ['lean', 'lake']) ok(await sha256File(path.join(K, `native/stage1/bin/${b}`)) === tc.native64[`stage1/bin/${b}`], `#7 native/stage1/bin/${b} sha256 == lock`, tc.native64[`stage1/bin/${b}`].slice(0, 16));
  // `docker image inspect <repo:tag>` intermittently answers "No such image" on this Docker Desktop
  // (28.5.1) while `docker images` lists the tag and `docker run` resolves it; so resolve the tag
  // through `docker image ls`, which is what run uses. Daemon unreachable -> skip(); tag absent -> FAIL.
  let dls = null;
  try { dls = execFileSync('docker', ['image', 'ls', '--no-trunc', '--format', '{{.Repository}}:{{.Tag}} {{.ID}}'], { stdio: ['ignore', 'pipe', 'ignore'], timeout: 20000 }).toString(); } catch {}
  if (dls === null) skip(`#7 docker image ${DOCKER_IMAGE}: docker daemon not reachable`);
  else {
    const did = (dls.split('\n').find((l) => l.split(' ')[0] === DOCKER_IMAGE) || '').split(' ')[1] || '';
    drift(did.replace(/^sha256:/, '').startsWith(tc.docker.id), `#7 docker ${DOCKER_IMAGE} id == ${tc.docker.id}`, did ? did.slice(0, 19) : 'tag not present');
  }
  ok(fs.readFileSync(path.join(K, 'mathlib/MATHLIB-COMMIT'), 'utf8').trim() === tc.mathlib.commit, `#7 Mathlib commit == ${tc.mathlib.commit.slice(0, 7)}`);
  const pw = readJson(path.join(K, 'mathlib/mathlib4/lake-manifest.json')).packages.find((p) => p.name === 'proofwidgets');
  ok(pw.rev === tc.mathlib.proofwidgets, `#7 ProofWidgets rev == ${tc.mathlib.proofwidgets.slice(0, 7)}`);
  ok(process.version === tc.node, `#7 node ${process.version} == lock ${tc.node}`);
  const pkg = (() => { try { return readJson(path.join(SC, 'package.json')); } catch { return null; } })();
  const pwPkg = (() => { try { return readJson(path.join(SC, 'node_modules/playwright-core/package.json')); } catch { return null; } })();
  const brw = (() => { try { return readJson(path.join(SC, 'node_modules/playwright-core/browsers.json')); } catch { return null; } })();
  if (!pkg || !pwPkg || !brw) skip('#7 Playwright: package.json / node_modules not installed yet');
  else {
    ok(pkg.devDependencies?.['@playwright/test'] === tc.playwright.version && pwPkg.version === tc.playwright.version, `#7 @playwright/test exact ${pkg.devDependencies?.['@playwright/test']}, installed playwright-core ${pwPkg.version}`);
    const used = brw.browsers.filter((b) => b.name === 'chromium' || b.name === 'chromium-headless-shell');
    const revs = used.map((b) => `${b.name}@${b.revision}`);
    const home = process.env.HOME;
    // Playwright's browser cache: PLAYWRIGHT_BROWSERS_PATH, else ~/Library/Caches/ms-playwright (macOS) / ~/.cache/ms-playwright (Linux)
    const roots = [process.env.PLAYWRIGHT_BROWSERS_PATH, path.join(home, 'Library/Caches/ms-playwright'), path.join(home, '.cache/ms-playwright')].filter(Boolean);
    const cached = roots.some((r) => fs.existsSync(path.join(r, `chromium_headless_shell-${tc.playwright.browserRevision}`)));
    ok(used.length === 2 && used.every((b) => b.revision === tc.playwright.browserRevision) && cached, `#7 browser revision ${tc.playwright.browserRevision} (${revs.join(', ')}) and cached`);
  }
  // WIDGETS_SOURCE_HASH: recomputed from the bytes of every file in $W/widgets-src; WIDGETS_COMMIT: the export is
  // exactly `git archive WIDGETS_COMMIT packages/` (file set + git blob ids re-derived from the bytes)
  if (!lock.WIDGETS_SOURCE_HASH) ok(false, '#7 WIDGETS_SOURCE_HASH present in QED64.lock.json', 'missing (run: pin-qed64.mjs record-widgets-hash)');
  else if (!fs.existsSync(WIDGETS_SRC)) ok(false, `#7 ${WIDGETS_SRC} exists`, 'run: node scripts/export-widgets.mjs');
  else {
    const { hash, files } = await widgetsSourceHash();
    ok(hash === lock.WIDGETS_SOURCE_HASH, `#7 WIDGETS_SOURCE_HASH recomputed over $W/widgets-src (${files} files) == lock`, `${hash.slice(0, 16)}… vs lock ${String(lock.WIDGETS_SOURCE_HASH).slice(0, 16)}…`);
    const rec = recordedWidgetsHash();
    ok(rec === lock.WIDGETS_SOURCE_HASH, '#7 widgets-src/SOURCE-HASH.txt == lock WIDGETS_SOURCE_HASH', rec.slice(0, 16));
    const wc = lock.WIDGETS_COMMIT;
    if (!/^[0-9a-f]{40}$/.test(wc || '')) ok(false, '#7 WIDGETS_COMMIT (a full commit id) present in QED64.lock.json', `${wc || 'missing'} (run: node scripts/export-widgets.mjs; pin-qed64.mjs record-widgets-hash)`);
    else {
      let present = true; try { WSRC.git('cat-file', '-e', `${wc}^{commit}`); } catch { present = false; }
      ok(present, `#7 WIDGETS_COMMIT ${wc.slice(0, 12)} present in the repository's object store`);
      ok(WSRC.recordedCommit() === wc, '#7 widgets-src/SOURCE-COMMIT.txt == lock WIDGETS_COMMIT', String(WSRC.recordedCommit()).slice(0, 12));
      if (present) {
        const c = WSRC.compareWithCommit(wc);
        ok(c.ok, `#7 $W/widgets-src == git archive ${wc.slice(0, 7)} packages/ (${c.files} files: same set, every blob id re-derived from the bytes)`,
          [c.missing.length && `missing ${c.missing.slice(0, 3)}`, c.extra.length && `extra ${c.extra.slice(0, 3)}`, c.differ.length && `differ ${c.differ.slice(0, 3)}`].filter(Boolean).join('; '));
        // the checkout's packages/ moved on since the build: the served overlays no longer come from HEAD's sources
        let head = null, at = null; try { head = WSRC.packagesTree('HEAD'); at = WSRC.packagesTree(wc); } catch {}
        drift(head !== null && head === at, `#7 HEAD:packages == WIDGETS_COMMIT:packages (the checkout's widget sources are the built ones)`, `${String(head).slice(0, 12)} vs ${String(at).slice(0, 12)}`);
      }
    }
  }
  // 8. vendor re-hash against QED64-PIN, and blob ids against git ls-tree QPIN
  const pinText = fs.readFileSync(PIN, 'utf8');
  ok(sha256Buf(Buffer.from(pinText)) === lock.vendor.pinSha256, '#8 QED64-PIN sha256 == lock.vendor.pinSha256');
  const pinMap = new Map(pinText.split('\n').filter((l) => l && !l.startsWith('#')).map((l) => { const [h, ...r] = l.split('  '); return [r.join('  '), h]; }));
  const vfiles = walk(VENDOR);
  let vbad = vfiles.filter((f) => !pinMap.has(f));
  for (const [f, h] of pinMap) { if (!fs.existsSync(path.join(VENDOR, f)) || await sha256File(path.join(VENDOR, f)) !== h) vbad.push(f); }
  ok(!vbad.length && vfiles.length === pinMap.size, `#8 ${path.relative(SC, VENDOR)} (${vfiles.length} files) re-hashes to QED64-PIN`, vbad.slice(0, 3).join(', '));
  const tree = new Map(git('ls-tree', '-r', QPIN, '--', ...lock.vendor.paths).toString().trim().split('\n').map((l) => { const [meta, p] = l.split('\t'); return [p, meta.split(' ')[2]]; }));
  let gbad = vfiles.filter((f) => tree.get(f) !== gitBlobId(fs.readFileSync(path.join(VENDOR, f))));
  ok(!gbad.length && tree.size === vfiles.length, `#8 ${path.relative(SC, VENDOR)} git blob ids == git ls-tree ${QPIN.slice(0, 7)} (${tree.size} entries)`, gbad.slice(0, 3).join(', '));

  // 10. dist/ copies of tracked files: Vite copies public/ into dist/ (public/workers/*.js -> dist/workers/*.js, the
  // infoview assets, …). dist/ itself is not tracked, so a stale or locally rebuilt dist would pass #6 (which only
  // compares with the lock). Every dist file whose path exists under public/ at QPIN must equal git show QPIN:public/<f>.
  const pubTracked = new Set(git('ls-tree', '-r', '--name-only', QPIN, '--', 'public').toString().trim().split('\n'));
  const dcopies = have.filter((f) => f.startsWith('dist/') && pubTracked.has('public/' + f.slice(5)));
  const dbad = dcopies.filter((f) => Buffer.compare(git('show', `${QPIN}:public/${f.slice(5)}`), fs.readFileSync(path.join(R, f))) !== 0);
  ok(dcopies.length > 0 && !dbad.length, `#10 the ${dcopies.length} dist/ copies of tracked public/ files == git show ${QPIN.slice(0, 7)}:public/<f> (incl. dist/workers/lean.worker.js)`, dbad.slice(0, 3).join(', '));
  ok(dcopies.includes('dist/workers/lean.worker.js'), '#10 dist/workers/lean.worker.js is among them');

  const notes = [skips ? `${skips} SKIP allowed by --allow-skip` : '', drifts ? `${drifts} DRIFT in a rebuild-only input` : ''].filter(Boolean).join('; ');
  console.log(fails ? `VERIFY FAILED (${fails} FAIL${drifts ? `, ${drifts} DRIFT` : ''})` : (notes ? `VERIFY OK (${notes})` : 'VERIFY OK'));
  process.exit(fails ? 1 : 0);
}

async function recordWidgetsHash() {
  const { hash, files } = await widgetsSourceHash();
  const rec = recordedWidgetsHash();
  if (hash !== rec) { console.error(`FAIL recomputed ${hash} != SOURCE-HASH.txt ${rec}`); process.exit(1); }
  const commit = WSRC.recordedCommit();
  if (!/^[0-9a-f]{40}$/.test(commit || '')) { console.error(`FAIL ${WIDGETS_SRC}/SOURCE-COMMIT.txt names no commit (re-export: node scripts/export-widgets.mjs)`); process.exit(1); }
  const c = WSRC.compareWithCommit(commit);
  if (!c.ok) { console.error(`FAIL ${WIDGETS_SRC} is not git archive ${commit} packages/: ${JSON.stringify(c).slice(0, 300)}`); process.exit(1); }
  const lock = readJson(LOCK);
  const prev = lock.WIDGETS_SOURCE_HASH && lock.WIDGETS_SOURCE_HASH !== hash ? { hash: lock.WIDGETS_SOURCE_HASH, commit: lock.WIDGETS_COMMIT || null } : null;
  lock.WIDGETS_SOURCE_HASH = hash;
  lock.WIDGETS_COMMIT = commit;
  lock.WIDGETS_SOURCE = { dir: '${QED64_SHOWCASE_WORK}/widgets-src', files, algorithm: WSRC.ALGORITHM, repo: WSRC.UPSTREAM, export: `git archive ${commit} packages/ (prefix packages/ stripped): scripts/export-widgets.mjs`,
    ...(lock.WIDGETS_SOURCE && lock.WIDGETS_SOURCE.history ? { history: lock.WIDGETS_SOURCE.history } : {}) };
  if (prev) lock.WIDGETS_SOURCE.history = [...(lock.WIDGETS_SOURCE.history || []), { ...prev, replacedAt: new Date().toISOString(), note: process.env.WIDGETS_HISTORY_NOTE || null }];
  fs.writeFileSync(LOCK, JSON.stringify(lock, null, 2) + '\n');
  console.log(`RECORDED WIDGETS_SOURCE_HASH ${hash} (${files} files) + WIDGETS_COMMIT ${commit} -> ${path.relative(SC, LOCK)}${prev ? ` (previous ${prev.hash.slice(0, 16)}… kept under WIDGETS_SOURCE.history)` : ''}`);
}

const cmd = process.argv[2];
const allowSkip = process.argv.includes('--allow-skip');
if (cmd === 'pin') await pin();
else if (cmd === 'verify') await verify({ allowSkip, strictToolchain: process.argv.includes('--strict') });
else if (cmd === 'record-widgets-hash') await recordWidgetsHash();
else { console.error('usage: pin-qed64.mjs pin|verify [--allow-skip] [--strict]|record-widgets-hash  [--pin <id>]'); process.exit(2); }
