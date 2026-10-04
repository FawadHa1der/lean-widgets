#!/usr/bin/env node
// pin-qed64.mjs — QED64 as a pinned dependency (BUILD-PLAN §2 S0.2–S0.5; docs/ARCHITECTURE.md). Node, no dependencies.
//
// Multiple pins (docs/REPIN-LOG.md "Multiple pins"): every command acts on ONE registered pin, `--pin <id>` (default: the
// active pin). Pins are keyed by QED64 COMMIT (id = its first 7 hex digits), because two commits can serve the same runtime
// buildId with different shells/workers. A pin's identity — QED64 commit, promote, buildId, kernel — is its descriptor
// pins/<id>/pin.json (scripts/lib/pins.mjs); its lock lives beside it in pins/<id>/, its served files in release/<id>/.
// QED64's SOURCES are never copied: they are the git submodule deps/qed64 (at the active pin's commit) or the pin's git
// worktree (scripts/lib/qed64-src.mjs); every `git show` / `ls-tree` below reads that checkout.
// Nothing here switches the active pin (`showcase.sh pin use <id>`).
//
//   node scripts/pin-qed64.mjs pin --pin <id>
//                                       REGISTER a pin's lock from a QED64 checkout that has QED64's binaries built
//                                       (QED64_REPO, read-only; e.g. the QED64 owner's checkout): S0.2 precondition
//                                       (its HEAD == the descriptor's commit, clean), S0.4 release clone (copy-on-write
//                                       per file) -> release/<id>, then write pins/<id>/QED64.lock.json (release file
//                                       sha256s, git anchors from the source dependency, the overlays of the pin's
//                                       runtime when they exist); S0.2 is re-checked after the clone. A cloner never
//                                       needs this: `showcase.sh bootstrap` rebuilds release/<id> from source + fetches.
//   node scripts/pin-qed64.mjs verify [--pin <id>] [--allow-skip] [--strict]
//                                       S0.5 chain of trust; one "OK"/"FAIL" line per check (N/A for a rebuild-only
//                                       input this checkout does not have: the kernel build, a downloaded browser);
//                                       exit 1 on any FAIL. A check that cannot run (docker not reachable, Playwright
//                                       not installed) is a FAIL unless --allow-skip is passed, in which case it prints
//                                       SKIP. Rebuild-only inputs that moved (the Docker image behind
//                                       qed64-toolchain:emsdk-6.0.5, a tag QED64's own toolchain build rewrites; the
//                                       Node version the bakes ran on) print DRIFT (not FAIL; `showcase.sh native`
//                                       refuses on the image) unless --strict.
//   node scripts/pin-qed64.mjs record-widgets-hash [--pin <id>]
//                                       recompute WIDGETS_SOURCE_HASH over $W/widgets-src, require it
//                                       to equal SOURCE-HASH.txt, check the export against its commit
//                                       (SOURCE-COMMIT.txt), and write hash + WIDGETS_COMMIT into that pin's lock
//   node scripts/pin-qed64.mjs record-overlays [--pin <id>]
//                                       write the sha256/bytes of the pin's runtime overlays (out/runtimes/<bid>/overlay/
//                                       widgets7|widgets8: index.json + both .snapz) into its lock (`overlays`), after
//                                       the cheap pairing check; the lock is what bootstrap verifies fetched overlays by
//
// The widget sources: $W/widgets-src is a `git archive` of this repository's packages/ at WIDGETS_COMMIT
// (scripts/export-widgets.mjs; scripts/lib/widgets-src.mjs). WIDGETS_SOURCE_HASH (amendment 1) = sha256 over the
// concatenation of "<sha256>  <relpath>\n" for every file of the export except its metadata files, ordered by relpath
// in byte (LC_ALL=C) order. That is exactly the bytes of SOURCE-FILES.sha256, so sha256(SOURCE-FILES.sha256) ==
// SOURCE-HASH.txt line 1; verify recomputes it from the file contents AND re-derives every file's git blob id against
// `git ls-tree -r WIDGETS_COMMIT packages/`.
//
// Locations (scripts/lib/env.mjs): QED64_REPO (only for `pin`), QED64_KERNEL_BUILD (the kernel build, read-only; `pin`
// needs it, `verify` checks it when set), QED64_SHOWCASE_WORK ($W). The lock records them as placeholders, never as
// this machine's paths.
//
// Every operation on a QED64 tree is read-only: git rev-parse / status / show / ls-tree (with --no-optional-locks on
// QED64_REPO), and copy-on-write file clones (new inodes, never hard links).
import { execFileSync, spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { activePinId, pinDescriptor, repoPinDir, releaseDir, ID_RE } = await import(path.join(SC, 'scripts/lib/pins.mjs'));
const ENV = await import(path.join(SC, 'scripts/lib/env.mjs'));
const WSRC = await import(path.join(SC, 'scripts/lib/widgets-src.mjs'));
const QSRC = await import(path.join(SC, 'scripts/lib/qed64-src.mjs'));
const { cloneFile } = await import(path.join(SC, 'scripts/lib/platform.mjs'));
const cmd0 = process.argv[2];
let Q = '', K = '';
try {
  if (cmd0 === 'pin') { Q = ENV.need('QED64_REPO'); K = ENV.need('QED64_KERNEL_BUILD'); }
  if (cmd0 === 'verify' && ENV.K) K = ENV.need('QED64_KERNEL_BUILD'); // optional for verify: set -> checked, unset -> N/A
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
const LOCK = path.join(STORE, 'QED64.lock.json');
// QED64's sources at QPIN: the submodule or the pin's worktree (never QED64_REPO, never a copy)
let SRC = '';
if (['pin', 'verify'].includes(cmd0)) {
  try { SRC = QSRC.requireSrc(QPIN, ID); } catch (e) { console.error(`pin-qed64: ${e.message}`); process.exit(2); }
}
const DOCKER_IMAGE = ENV.DOCKER_IMAGE;
const DOCKER_ID = '8b6698bbf474';
const PLAYWRIGHT = '1.62.1';
const BROWSER_REV = '1234';

// git-tracked JSON consumed from public/ (S0.5 #1)
const TRACKED_JSON = [
  'public/runtime/runtime-manifest.json', 'public/profiles/index.json',
  'public/profiles/lean-core.manifest.json', 'public/profiles/mathlib-essential.manifest.json',
  'public/snapshots/index.json',
];

const LOCK_SCHEMA = 'qed64-showcase.lock/v2';
// The dependency sections every lock carries (docs/ARCHITECTURE.md): how QED64's sources are consumed (a submodule /
// worktree at the commit, never a copy), how the page shell is rebuilt from them, and which release files come from git
// and which from an artifact origin.
function lockDependencySections(commit) {
  return {
    source: {
      kind: 'git-submodule', path: QSRC.SUBMODULE_REL, url: QSRC.UPSTREAM, commit,
      staged: 'a pin that is not the submodule\'s commit: git worktree of the submodule\'s repository at ${QED64_SHOWCASE_WORK}/qed64-pins/<id> (scripts/lib/qed64-src.mjs)',
    },
    shell: {
      dir: 'dist', build: 'npm ci --prefix frontend && npm run build:site (QED64\'s own build, in the source checkout)',
      verify: 'every built dist/ file byte-identical to release.files (sha256): the build is deterministic (docs/ARCHITECTURE.md "Shell from source")',
    },
    artifacts: {
      fromGit: [...TRACKED_JSON, `public/runtime/runtime-manifest.${BID} copy of public/runtime/runtime-manifest.json (verify #2)`],
      fetched: 'every other public/ file of release.files, by URL path (public/<p> is served at /<p>) from an artifact origin, sha256 == release.files (scripts/fetch-artifacts.mjs)',
    },
  };
}
const git = (...a) => execFileSync('git', ['-C', SRC, ...a], { maxBuffer: 1 << 30 });              // the source dependency
const gitQ = (...a) => execFileSync('git', ['--no-optional-locks', '-C', Q, ...a], { maxBuffer: 1 << 30 }); // QED64_REPO (pin)
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
  const head = gitQ('rev-parse', 'HEAD').toString().trim();
  const dirty = gitQ('status', '--porcelain').toString();
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

  // S0.4 release clone (copy-on-write clone per file: APFS clonefile / Linux reflink; never a hard link)
  const set = releaseSet();
  fs.rmSync(R, { recursive: true, force: true });
  const files = {};
  let bytes = 0;
  for (const rel of set) {
    const src = path.join(Q, rel), dst = path.join(R, rel);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    cloneFile(src, dst);
    const st = fs.statSync(dst);
    files[rel] = { bytes: st.size, sha256: await sha256File(dst) };
    bytes += st.size;
  }
  console.log(`S0.4 OK  cloned ${set.length} files (${(bytes / 1e9).toFixed(3)} GB logical) -> ${path.relative(SC, R)}`);
  const head1 = gitQ('rev-parse', 'HEAD').toString().trim(), dirty1 = gitQ('status', '--porcelain').toString();
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
  const { schema: _s, qed64: _q, vendor: _v, source: _sr, shell: _sh, artifacts: _ar, release: _r, anchors: _a, toolchain: _t, pinnedAt: _p, ...keep } = prev;
  const anchors = {};
  for (const p of TRACKED_JSON) anchors[p] = { gitBlob: git('rev-parse', `${QPIN}:${p}`).toString().trim(), sha256: files[p].sha256 };
  const lock = {
    schema: LOCK_SCHEMA,
    pinnedAt: new Date().toISOString(),
    qed64: { repo: QED64_UPSTREAM, commit: QPIN, promote: QPROMOTE, buildId: BID, kernel: KERNEL },
    ...lockDependencySections(QPIN),
    release: { dir: path.relative(SC, R), files },
    anchors,
    toolchain,
    ...keep,
  };
  fs.writeFileSync(LOCK, JSON.stringify(lock, null, 2) + '\n');
  console.log(`PIN DONE  ${path.relative(SC, LOCK)} (${Object.keys(files).length} release files); record the overlays once built (pin-qed64.mjs record-overlays --pin ${ID}); activate with: scripts/showcase.sh pin use ${ID}`);
}

async function verify({ allowSkip = false, strictToolchain = false } = {}) {
  let fails = 0, skips = 0, drifts = 0, nas = 0;
  // N/A: a rebuild-only input this checkout does not have (no kernel build, no downloaded browser). Printed, counted and
  // named in the summary; never a reason to pass a check on the served files.
  const na = (msg, why) => { nas++; console.log(`N/A  ${msg} — ${why}`); };
  const ok = (cond, msg, detail = '') => { console.log(`${cond ? 'OK  ' : 'FAIL'} ${msg}${detail ? ' — ' + detail : ''}`); if (!cond) fails++; };
  // a check that could not run is a FAIL unless --allow-skip
  const skip = (msg) => { if (allowSkip) { skips++; console.log(`SKIP ${msg} (--allow-skip)`); } else { fails++; console.log(`FAIL ${msg} (check could not run; pass --allow-skip to tolerate)`); } };
  // DRIFT: a rebuild-only input (the Docker image behind a tag QED64 owns) no longer matches the lock. The
  // served artifacts do not depend on it (they are verified by hash in #1-#6, #8); only re-running the
  // native build does, and `showcase.sh native` refuses on the same comparison. Not a FAIL unless --strict.
  const drift = (cond, msg, detail = '') => {
    if (cond) return ok(true, msg, detail);
    if (strictToolchain) return ok(false, msg, detail);
    drifts++; console.log(`DRIFT ${msg}${detail ? ' — ' + detail : ''} (rebuild-only input: served artifacts unaffected; 'showcase.sh native' refuses on the image; --strict makes this a FAIL)`);
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
  // 7. toolchain pins. The native64 toolchain, its Docker image, Mathlib and ProofWidgets are REBUILD-ONLY inputs (the
  // native widget oleans: `showcase.sh native`, `stage`); a checkout without QED64_KERNEL_BUILD cannot rebuild and does
  // not need them to serve (the served files are checked by #1-#6, #10 and the overlays by #11), so they print N/A.
  const tc = lock.toolchain;
  if (!K) {
    na(`#7 native64 toolchain (NATIVE-COMMIT ${tc.native64.NATIVE_COMMIT.slice(0, 10)}, stage1 lean/lake sha256), Docker image ${tc.docker.image} ${tc.docker.id}, Mathlib ${tc.mathlib.commit.slice(0, 7)}, ProofWidgets ${tc.mathlib.proofwidgets.slice(0, 7)}: QED64_KERNEL_BUILD is not set`,
      'rebuild-only inputs of the native widget oleans (docs/BUILD-FROM-SOURCE.md); set it to check them');
  } else {
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
      const ids = [tc.docker.id, ...((tc.docker.equivalent || []).map((e) => e.id))];
      const hit = ids.find((x) => did.replace(/^sha256:/, '').startsWith(x));
      drift(!!hit, `#7 docker ${DOCKER_IMAGE} id == ${tc.docker.id}${ids.length > 1 ? ` or a recorded equivalent (${ids.slice(1).join(', ')})` : ''}`, did ? `${did.slice(0, 19)}${hit && hit !== tc.docker.id ? ' (recorded equivalent: same oleans, byte for byte)' : ''}` : 'tag not present');
    }
    ok(fs.readFileSync(path.join(K, 'mathlib/MATHLIB-COMMIT'), 'utf8').trim() === tc.mathlib.commit, `#7 Mathlib commit == ${tc.mathlib.commit.slice(0, 7)}`);
    const pw = readJson(path.join(K, 'mathlib/mathlib4/lake-manifest.json')).packages.find((p) => p.name === 'proofwidgets');
    ok(pw.rev === tc.mathlib.proofwidgets, `#7 ProofWidgets rev == ${tc.mathlib.proofwidgets.slice(0, 7)}`);
  }
  // The Node that ran the bakes and recorded the lock. A rebuild-only input: the served files are hash-checked, and the
  // page shell builds byte-identically on other Node versions (docs/ARCHITECTURE.md "Shell from source").
  drift(process.version === tc.node, `#7 node ${process.version} == lock ${tc.node}`, process.version === tc.node ? '' : 'the Node the bakes ran on');
  const pkg = (() => { try { return readJson(path.join(SC, 'package.json')); } catch { return null; } })();
  const pwPkg = (() => { try { return readJson(path.join(SC, 'node_modules/playwright-core/package.json')); } catch { return null; } })();
  const brw = (() => { try { return readJson(path.join(SC, 'node_modules/playwright-core/browsers.json')); } catch { return null; } })();
  if (!pkg || !pwPkg || !brw) skip('#7 Playwright: package.json / node_modules not installed yet (npm ci)');
  else {
    ok(pkg.devDependencies?.['@playwright/test'] === tc.playwright.version && pwPkg.version === tc.playwright.version, `#7 @playwright/test exact ${pkg.devDependencies?.['@playwright/test']}, installed playwright-core ${pwPkg.version}`);
    const used = brw.browsers.filter((b) => b.name === 'chromium' || b.name === 'chromium-headless-shell');
    const revs = used.map((b) => `${b.name}@${b.revision}`);
    ok(used.length === 2 && used.every((b) => b.revision === tc.playwright.browserRevision), `#7 browser revision ${tc.playwright.browserRevision} (${revs.join(', ')})`);
    const home = process.env.HOME;
    // Playwright's browser cache: PLAYWRIGHT_BROWSERS_PATH, else ~/Library/Caches/ms-playwright (macOS) / ~/.cache/ms-playwright (Linux)
    const roots = [process.env.PLAYWRIGHT_BROWSERS_PATH, path.join(home, 'Library/Caches/ms-playwright'), path.join(home, '.cache/ms-playwright')].filter(Boolean);
    const cached = roots.some((r) => fs.existsSync(path.join(r, `chromium_headless_shell-${tc.playwright.browserRevision}`)));
    if (cached) ok(true, `#7 browser revision ${tc.playwright.browserRevision} downloaded on this host`);
    else na(`#7 browser revision ${tc.playwright.browserRevision} is not downloaded on this host`, 'only `showcase.sh ux` needs it: npx playwright install chromium chromium-headless-shell');
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
  // 8. QED64's sources: the source dependency (submodule or the pin's worktree) is exactly the pinned commit, with no
  // tracked file modified; for the active pin, the submodule's gitlink == HEAD == the lock's commit. (Until 2026-10-04
  // this was a vendored copy re-hashed against QED64-PIN; nothing of QED64 is copied any more.)
  for (const r of QSRC.checkSrc(QPIN, ID, { active: ID === act })) ok(r.ok, `#8 ${r.msg}`);
  ok(lock.source && lock.source.commit === QPIN && lock.source.path === QSRC.SUBMODULE_REL, `#8 lock source: ${lock.source && lock.source.kind} ${lock.source && lock.source.path} @ ${String(lock.source && lock.source.commit).slice(0, 12)} == QPIN`);
  ok(!fs.existsSync(path.join(STORE, 'QED64-PIN')) && !fs.existsSync(path.join(STORE, 'vendor-qed64')) && !fs.existsSync(path.join(SC, 'vendor', 'qed64')),
    '#8 no vendored copy of QED64 (pins/<id>/QED64-PIN, pins/<id>/vendor-qed64, vendor/qed64 absent)');

  // 10. dist/ copies of tracked files: Vite copies public/ into dist/ (public/workers/*.js -> dist/workers/*.js, the
  // infoview assets, …). dist/ itself is not tracked, so a stale or locally rebuilt dist would pass #6 (which only
  // compares with the lock). Every dist file whose path exists under public/ at QPIN must equal git show QPIN:public/<f>.
  const pubTracked = new Set(git('ls-tree', '-r', '--name-only', QPIN, '--', 'public').toString().trim().split('\n'));
  const dcopies = have.filter((f) => f.startsWith('dist/') && pubTracked.has('public/' + f.slice(5)));
  const dbad = dcopies.filter((f) => Buffer.compare(git('show', `${QPIN}:public/${f.slice(5)}`), fs.readFileSync(path.join(R, f))) !== 0);
  ok(dcopies.length > 0 && !dbad.length, `#10 the ${dcopies.length} dist/ copies of tracked public/ files == git show ${QPIN.slice(0, 7)}:public/<f> (incl. dist/workers/lean.worker.js)`, dbad.slice(0, 3).join(', '));
  ok(dcopies.includes('dist/workers/lean.worker.js'), '#10 dist/workers/lean.worker.js is among them');

  // 11. the pin's runtime overlays (what /snapshots/widgets7|8/ serve) == the lock's `overlays` sha256/bytes
  const ov = lock.overlays || {};
  if (!Object.keys(ov).length) ok(false, '#11 lock records the overlays', 'missing (run: pin-qed64.mjs record-overlays)');
  for (const [o, rec] of Object.entries(ov)) {
    const d = path.join(SC, rec.dir);
    const want = rec.files || {};
    const have = fs.existsSync(d) ? walk(d) : [];
    const missing = Object.keys(want).filter((f) => !have.includes(f)), extra = have.filter((f) => !(f in want));
    const bad = [];
    for (const f of Object.keys(want)) if (have.includes(f) && (fs.statSync(path.join(d, f)).size !== want[f].bytes || await sha256File(path.join(d, f)) !== want[f].sha256)) bad.push(f);
    ok(have.length && !missing.length && !extra.length && !bad.length, `#11 overlay ${o}: ${rec.dir} == lock (${Object.keys(want).length} files, sha256 and size)`,
      [!have.length && 'not present (scripts/showcase.sh bootstrap fetches it)', missing.length && `missing ${missing.slice(0, 3)}`, extra.length && `extra ${extra.slice(0, 3)}`, bad.length && `differ ${bad.slice(0, 3)}`].filter(Boolean).join('; '));
  }

  const notes = [skips ? `${skips} SKIP allowed by --allow-skip` : '', drifts ? `${drifts} DRIFT in a rebuild-only input` : '', nas ? `${nas} N/A (rebuild-only input not on this host)` : ''].filter(Boolean).join('; ');
  console.log(fails ? `VERIFY FAILED (${fails} FAIL${drifts ? `, ${drifts} DRIFT` : ''}${nas ? `, ${nas} N/A` : ''})` : (notes ? `VERIFY OK (${notes})` : 'VERIFY OK'));
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

async function recordOverlays() {
  const { OVERLAYS, outRtDir } = await import(path.join(SC, 'scripts/lib/pins.mjs'));
  const lock = readJson(LOCK);
  const overlays = {};
  for (const o of OVERLAYS) {
    const d = path.join(outRtDir(BID), 'overlay', o);
    if (!fs.existsSync(path.join(d, 'index.json'))) { console.error(`FAIL ${path.relative(SC, d)}/index.json missing: build the overlays first (showcase.sh overlay)`); process.exit(1); }
    const ix = readJson(path.join(d, 'index.json'));
    const files = {};
    for (const f of walk(d)) files[f] = { bytes: fs.statSync(path.join(d, f)).size, sha256: await sha256File(path.join(d, f)) };
    // the cheap pairing rules (also showcase.sh check_overlays_cheap): this runtime, exactly {init, mathlib}, the index
    // names exactly the files present, sizes == transfer, sha256 == digest
    const names = ix.snapshots.map((x) => x.name).sort().join(',');
    const errs = [];
    if (names !== 'init,mathlib') errs.push(`entries ${names}`);
    for (const e of ix.snapshots) {
      const f = path.basename(e.url);
      if (e.runtime !== BID) errs.push(`${e.name}.runtime ${e.runtime}`);
      if (!files[f]) errs.push(`${f} missing`);
      else if (files[f].bytes !== e.transfer || `sha256:${files[f].sha256}` !== e.digest) errs.push(`${f} != index (size/digest)`);
    }
    if (Object.keys(files).length !== ix.snapshots.length + 1) errs.push(`files ${Object.keys(files).join(',')}`);
    if (errs.length) { console.error(`FAIL overlay ${o}: ${errs.join('; ')}`); process.exit(1); }
    overlays[o] = { dir: path.relative(SC, d), url: `/snapshots/${o}/`, files };
  }
  lock.overlays = overlays;
  fs.writeFileSync(LOCK, JSON.stringify(lock, null, 2) + '\n');
  console.log(`RECORDED overlays ${Object.entries(overlays).map(([o, r]) => `${o} (${Object.keys(r.files).length} files)`).join(', ')} -> ${path.relative(SC, LOCK)}`);
}

const cmd = process.argv[2];
const allowSkip = process.argv.includes('--allow-skip');
if (cmd === 'pin') await pin();
else if (cmd === 'verify') await verify({ allowSkip, strictToolchain: process.argv.includes('--strict') });
else if (cmd === 'record-widgets-hash') await recordWidgetsHash();
else if (cmd === 'record-overlays') await recordOverlays();
else { console.error('usage: pin-qed64.mjs pin|verify [--allow-skip] [--strict]|record-widgets-hash|record-overlays  [--pin <id>]'); process.exit(2); }
