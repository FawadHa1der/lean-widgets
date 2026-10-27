#!/usr/bin/env node
// fetch-artifacts.mjs — QED64's BINARY dependency and our overlays, fetched by content from an artifact origin and
// verified against the pin's lock (docs/ARCHITECTURE.md "Binary dependency"). Nothing here trusts an origin: every byte
// written is checked against the sha256 the committed lock records, and a file that does not match is never installed.
//
// What a pin serves (pins/<id>/QED64.lock.json):
//   release.files  public/<p>  QED64's runtime chunks, profile packs and stock snapshots (content-addressed names) plus
//                              five tracked manifests/indexes. The TRACKED ones (lock.artifacts.fromGit) are taken from
//                              QED64's git at the pin (`git show`, the source dependency deps/qed64 or the pin's
//                              worktree); every other public/ file is FETCHED: URL path /<p> on the origin.
//                  dist/<p>    QED64's page: built from source by scripts/build-shell.mjs, never fetched.
//   overlays       our widget snapshot regions (index.json + init + widgets .snapz) at <overlays.<o>.url><file>, i.e.
//                              /snapshots/<dir>/<file> with <dir> = scripts/lib/pins.mjs overlayDir(<o>, pin): widgets8 for
//                              pins A–H, widgets8.<bid16> for a per-runtime pin (pin.json v3); the lock's url must say
//                              exactly that (else the run refuses before fetching anything). Installed into
//                              out/runtimes/<buildId>/overlay/<o>/ (the per-runtime overlay store, by logical name).
//
// Origins (an origin serves the deployed layout: /runtime/…, /profiles/…, /snapshots/…, /snapshots/<dir>/…):
//   --origin <url>         (ARTIFACT_ORIGIN)        the showcase's own origin: our deployed Worker (the upload copies,
//                                                   never deletes, so every pin uploaded to its prefix keeps its QED64
//                                                   files and .snapz, all digest-named; an overlay's index.json is one
//                                                   per /snapshots/<dir>/, the last upload's: bare for pins A–H, shared
//                                                   by same-runtime pins from I on), or scripts/serve.mjs of a checkout
//                                                   that has the files. Serves QED64's files AND overlays. The source
//                                                   for any pin QED64's live site does not deploy now.
//   --qed64-origin <url>   (QED64_ARTIFACT_ORIGIN)  an origin serving QED64's own files only; tried after --origin for
//                                                   QED64's files. QED64's live site serves them for ONE release, the
//                                                   one it deploys now: since QED64 4b98279 its Worker reads /runtime/*
//                                                   and /profiles/<not index.json> only from that release's prefix (no
//                                                   fallback to the bucket root, whose runtime/ and profiles/ copies
//                                                   were removed on 2026-10-23), and its R2 sweep of 2026-10-23 kept
//                                                   only the live and the previous pairing's /snapshots/. Bootstrapping
//                                                   or rolling back to any other pin (N, H, …) from it gets 404s: use
//                                                   --origin.
//   Plain HTTP(S) GETs from Node: CORP/COEP apply to browsers, not to this client.
//
//   node scripts/fetch-artifacts.mjs [--pin <id>] [--origin <url>] [--qed64-origin <url>] [--only public|overlays]
//                                    [--jobs 4] [--check] [--remote-check] [--git-only]
//     default        install what is missing or wrong; resumable: a complete file whose size and sha256 match the lock
//                    is kept; an interrupted download continues from <file>.partial with a Range request when the
//                    origin answers 206 (else it restarts that file); a finished download whose sha256 differs from the
//                    lock is moved to <file>.rejected-<time> (never installed, never deleted) and the run fails.
//     --check        write nothing: exit 0 iff every file of the pin is present with the lock's size and sha256
//     --git-only     install only the files that come from QED64's git (the tracked manifests and indexes); no network,
//                    no origin (CI: the gallery data and gates need the runtime manifest, not the binaries)
//     --remote-check write nothing: HEAD every file to be fetched on the origins (or GET it and read only the headers,
//                    when the origin's HEAD has no Content-Length) and compare Content-Length with the lock
// Exit: 0 ok · 1 a file failed (missing on every origin, a sha256 mismatch, an HTTP error) · 2 usage/setup.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PINS = await import(path.join(SC, 'scripts/lib/pins.mjs'));
const QSRC = await import(path.join(SC, 'scripts/lib/qed64-src.mjs'));

const argv = process.argv.slice(2);
const val = (f, d) => { const i = argv.indexOf(f); if (i < 0) return d; const v = argv[i + 1]; if (!v || v.startsWith('--')) usage(`${f} needs a value`); return v; };
function usage(why) {
  if (why) console.error(`fetch-artifacts: ${why}`);
  console.error(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(1).filter((l) => l.startsWith('//')).map((l) => l.replace(/^\/\/ ?/, '')).join('\n'));
  process.exit(2);
}
const KNOWN = ['--pin', '--origin', '--qed64-origin', '--only', '--jobs', '--check', '--remote-check', '--git-only', '--help'];
for (const a of argv) if (a.startsWith('--') && !KNOWN.includes(a)) usage(`unknown argument ${a}`);
if (argv.includes('--help')) usage();
const ID = val('--pin', PINS.targetPinId());
const DESC = PINS.pinDescriptor(ID);
const BID = DESC.buildId;
const LOCK = PINS.lockOf(ID);
const ONLY = val('--only', '');
if (ONLY && !['public', 'overlays'].includes(ONLY)) usage('--only public|overlays');
const JOBS = Math.max(1, Number(val('--jobs', '4')));
const CHECK = argv.includes('--check'), REMOTE = argv.includes('--remote-check');
const norm = (u) => (u ? u.replace(/\/+$/, '') : '');
const ORIGIN = norm(val('--origin', process.env.ARTIFACT_ORIGIN || ''));
const QORIGIN = norm(val('--qed64-origin', process.env.QED64_ARTIFACT_ORIGIN || ''));
const R = PINS.releaseOf(ID);
const UA = 'qed64-showcase-fetch-artifacts (https://github.com/FawadHa1der/lean-widgets)';

const sha256File = (p) => new Promise((res, rej) => {
  const h = createHash('sha256');
  fs.createReadStream(p, { highWaterMark: 8 << 20 }).on('data', (d) => h.update(d)).on('error', rej).on('end', () => res(h.digest('hex')));
});
const sha256Buf = (b) => createHash('sha256').update(b).digest('hex');
const relSC = (p) => path.relative(SC, p);
const fmtMB = (b) => `${(b / 1e6).toFixed(1)} MB`;

// ---------------------------------------------------------------- the plan: [{dest, url, bytes, sha256, from}]
const tracked = new Set((LOCK.artifacts && LOCK.artifacts.fromGit || []).filter((p) => p.startsWith('public/') && p.endsWith('.json') && !p.includes(' ')));
const perBuildManifest = `public/runtime/runtime-manifest.${BID}.json`;
const plan = [];
if (ONLY !== 'overlays') {
  for (const [rel, m] of Object.entries(LOCK.release.files)) {
    if (!rel.startsWith('public/')) continue;
    const from = tracked.has(rel) ? 'git' : rel === perBuildManifest ? 'git-copy' : 'origin';
    plan.push({ dest: path.join(R, rel), rel: `release/${ID}/${rel}`, url: rel.slice('public'.length), bytes: m.bytes, sha256: m.sha256, from, kind: 'qed64' });
  }
}
if (ONLY !== 'public') {
  if (!LOCK.overlays || !Object.keys(LOCK.overlays).length) { console.error(`fetch-artifacts: pins/${ID}/QED64.lock.json records no overlays`); process.exit(2); }
  for (const [o, rec] of Object.entries(LOCK.overlays)) {
    const want = path.join('out', 'runtimes', BID, 'overlay', o);
    if (rec.dir !== want) { console.error(`fetch-artifacts: lock overlays.${o}.dir ${rec.dir} != ${want}`); process.exit(2); }
    // the served URL comes from the lock, checked against the one naming rule (fail closed: never guess a directory)
    let wantUrl = null;
    try { wantUrl = PINS.overlayUrl(o, ID); } catch (e) { console.error(`fetch-artifacts: overlay ${o}: ${e.message}`); process.exit(2); }
    if (rec.url !== wantUrl) { console.error(`fetch-artifacts: lock overlays.${o}.url ${rec.url} != ${wantUrl} (scripts/lib/pins.mjs overlayUrl for pin ${ID})`); process.exit(2); }
    for (const [f, m] of Object.entries(rec.files)) plan.push({ dest: path.join(SC, rec.dir, f), rel: `${rec.dir}/${f}`, url: `${rec.url}${f}`, bytes: m.bytes, sha256: m.sha256, from: 'origin', kind: 'overlay' });
  }
}
if (argv.includes('--git-only')) { if (ONLY === 'overlays') usage('--git-only installs public/ manifests; not with --only overlays'); plan.splice(0, plan.length, ...plan.filter((x) => x.from !== 'origin')); }
/* QED64's files: the showcase's origin first, then QED64's, which answers only for the release it deploys now (header:
   since 4b98279 no bucket-root fallback), so for any other pin it is a 404 and only --origin can deliver; every byte is
   checked against the lock either way. The overlays exist only on the showcase's origin. A file that no origin delivered
   fails with each origin's own last error, in the order tried (errs), not only the last origin's (a 503 of --origin
   would hide behind QED64's 404). qedOriginHint: what it adds when QED64's origin was the last one tried: --origin
   when none was given, else that --origin (always tried first) failed too, and what a 404 there means. (Block
   comments: the usage text is every line that starts with //.) */
const origins = (it) => (it.kind === 'overlay' ? [ORIGIN] : [ORIGIN, QORIGIN]).filter(Boolean);
const qedOriginHint = (it, errs) => (it.kind === 'qed64' && QORIGIN && String(errs[errs.length - 1]).startsWith(QORIGIN)
  ? ` — QED64's origin serves only what its live site deploys now (/runtime/ and /profiles/<not index.json> of ONE release since QED64 4b98279; its 2026-10-23 sweep kept only the live and the previous pairing's /snapshots/): ${ORIGIN
    ? `the showcase's own origin ${ORIGIN}, tried first, did not deliver it either (its error is the first one on this line; a 404 there means pin ${ID}'s files are not under that Worker's prefix: was pin ${ID} uploaded to it?)`
    : `fetch pin ${ID}'s files from the showcase's own origin (--origin)`}` : '');

async function have(it) {
  try { const st = fs.statSync(it.dest); return st.isFile() && st.size === it.bytes && (await sha256File(it.dest)) === it.sha256; } catch { return false; }
}

// ---------------------------------------------------------------- --check / --remote-check
if (CHECK) {
  let bad = 0;
  for (const it of plan) if (!(await have(it))) { bad++; if (bad <= 10) console.log(`MISSING/DIFFERS ${it.rel}`); }
  console.log(bad ? `FETCH-ARTIFACTS CHECK FAILED: ${bad} of ${plan.length} files missing or != lock (pin ${ID})` : `FETCH-ARTIFACTS CHECK OK: all ${plan.length} files of pin ${ID} present with the lock's size and sha256`);
  process.exit(bad ? 1 : 0);
}
if (REMOTE) {
  let bad = 0, n = 0;
  for (const it of plan.filter((x) => x.from === 'origin')) {
    const os = origins(it);
    if (!os.length) { console.log(`NO ORIGIN ${it.url}`); bad++; continue; }
    let good = null; const errs = [];
    for (const o of os) {
      try {
        let r = await fetch(o + it.url, { method: 'HEAD', headers: { 'user-agent': UA } });
        let how = 'HEAD';
        // an origin may answer HEAD without Content-Length (QED64's own worker does): then the GET's headers, body unread
        if (r.status === 200 && r.headers.get('content-length') === null) {
          r = await fetch(o + it.url, { headers: { 'user-agent': UA, 'accept-encoding': 'identity' } }); how = 'GET headers';
          await r.body?.cancel();
        }
        const len = Number(r.headers.get('content-length'));
        if (r.status === 200 && len === it.bytes) { good = o; break; }
        errs.push(`${o}: ${how} ${r.status} content-length ${r.headers.get('content-length')}`);
      } catch (e) { errs.push(`${o}: ${e.message}`); }
    }
    n++;
    if (!good) { bad++; console.log(`FAIL ${it.url} (lock ${it.bytes} B): ${errs.join('; ')}${qedOriginHint(it, errs)}`); }
  }
  console.log(bad ? `REMOTE-CHECK FAILED: ${bad} of ${n}` : `REMOTE-CHECK OK: all ${n} files to fetch answer 200 with the lock's size (${[ORIGIN, QORIGIN].filter(Boolean).join(', ')})`);
  process.exit(bad ? 1 : 0);
}

// ---------------------------------------------------------------- install
let src = null;
if (plan.some((x) => x.from !== 'origin')) {
  try { src = QSRC.requireSrc(DESC.qed64.commit, ID); } catch (e) { console.error(`fetch-artifacts: ${e.message}`); process.exit(2); }
}
const needOrigin = plan.some((x) => x.from === 'origin');
if (needOrigin && !ORIGIN && !QORIGIN) usage('no origin: pass --origin <showcase origin> and/or --qed64-origin <QED64 origin> (or ARTIFACT_ORIGIN / QED64_ARTIFACT_ORIGIN)');
if (plan.some((x) => x.kind === 'overlay') && !ORIGIN) usage("the overlays come only from the showcase's own origin: pass --origin (our deployed Worker, or scripts/serve.mjs of a checkout that has them), or --only public");

const stamp = () => new Date().toISOString().replace(/[:.]/g, '-');
function reject(it, file, why) {
  const to = `${it.dest}.rejected-${stamp()}`;
  fs.renameSync(file, to);
  throw new Error(`${why}; kept as ${relSC(to)} (not installed)`);
}
async function install(it) {
  fs.mkdirSync(path.dirname(it.dest), { recursive: true });
  if (it.from === 'git' || it.from === 'git-copy') {
    const gp = it.from === 'git' ? it.rel.slice(`release/${ID}/`.length) : 'public/runtime/runtime-manifest.json';
    const b = execFileSync('git', ['-C', src, 'show', `${DESC.qed64.commit}:${gp}`], { maxBuffer: 1 << 30 });
    if (b.length !== it.bytes || sha256Buf(b) !== it.sha256) throw new Error(`git show ${DESC.qed64.commit.slice(0, 7)}:${gp} != lock (sha256 ${sha256Buf(b).slice(0, 12)}…)`);
    const tmp = `${it.dest}.tmp-${process.pid}`; fs.writeFileSync(tmp, b); fs.renameSync(tmp, it.dest);
    return { how: `git ${gp}`, bytes: 0 };
  }
  const part = `${it.dest}.partial`;
  const errs = [];
  for (const o of origins(it)) {
    let lastErr = ''; // this origin's, after up to 3 attempts
    for (let attempt = 1; attempt <= 3; attempt++) {
      let have0 = 0; try { have0 = fs.statSync(part).size; } catch { /* fresh */ }
      if (have0 > it.bytes) { fs.renameSync(part, `${part}.oversize-${stamp()}`); have0 = 0; }
      const headers = { 'user-agent': UA, 'accept-encoding': 'identity' };
      if (have0 > 0 && have0 < it.bytes) headers.range = `bytes=${have0}-`;
      let res;
      try { res = await fetch(o + it.url, { headers }); } catch (e) { lastErr = `${o}${it.url}: ${e.message}`; continue; }
      if (res.status === 404) { lastErr = `${o}${it.url}: 404`; await res.body?.cancel(); break; } // next origin
      if (res.headers.get('content-encoding') && res.headers.get('content-encoding') !== 'identity') { lastErr = `${o}${it.url}: content-encoding ${res.headers.get('content-encoding')}`; await res.body?.cancel(); break; }
      let append = false;
      if (res.status === 206 && headers.range && (res.headers.get('content-range') || '').startsWith(`bytes ${have0}-`)) append = true;
      else if (res.status !== 200) { lastErr = `${o}${it.url}: HTTP ${res.status}`; await res.body?.cancel(); continue; }
      const fd = fs.openSync(part, append ? 'a' : 'w');
      let got = 0;
      try {
        for await (const chunk of res.body) { fs.writeSync(fd, chunk); got += chunk.length; }
      } catch (e) { lastErr = `${o}${it.url}: stream cut after ${got} B (${e.message}); resuming`; continue; }
      finally { fs.closeSync(fd); }
      const size = fs.statSync(part).size;
      if (size < it.bytes) { lastErr = `${o}${it.url}: ${size} of ${it.bytes} B; resuming`; continue; }
      if (size !== it.bytes) reject(it, part, `${it.url}: ${size} B, lock says ${it.bytes} B`);
      const h = await sha256File(part);
      if (h !== it.sha256) reject(it, part, `${it.url}: sha256 ${h.slice(0, 16)}… != lock ${it.sha256.slice(0, 16)}…`);
      fs.renameSync(part, it.dest);
      return { how: `${append ? `resumed at ${have0} B from` : 'from'} ${o}`, bytes: got };
    }
    errs.push(lastErr);
  }
  throw new Error(`no origin delivered ${it.url}: ${errs.join('; ')}${qedOriginHint(it, errs)}`);
}

const t0 = Date.now();
console.log(`fetch-artifacts: pin ${ID} (QED64 ${DESC.qed64.commit.slice(0, 12)}, runtime ${BID}): ${plan.length} files${ONLY ? ` (--only ${ONLY})` : ''}; origins: ${[ORIGIN && `showcase ${ORIGIN}`, QORIGIN && `qed64 ${QORIGIN}`].filter(Boolean).join(', ') || 'none (git only)'}`);
let done = 0, kept = 0, failed = 0, bytes = 0;
const queue = [...plan];
const worker = async () => {
  for (let it; (it = queue.shift());) {
    if (await have(it)) { kept++; continue; }
    try {
      const r = await install(it); done++; bytes += r.bytes;
      console.log(`OK   ${it.rel} (${fmtMB(it.bytes)}) ${r.how}`);
    } catch (e) { failed++; console.log(`FAIL ${it.rel}: ${e.message}`); }
  }
};
await Promise.all(Array.from({ length: JOBS }, worker));
const s = ((Date.now() - t0) / 1000).toFixed(1);
console.log(`${failed ? 'FETCH-ARTIFACTS FAILED' : 'FETCH-ARTIFACTS OK'}: pin ${ID}: ${done} installed (${fmtMB(bytes)} downloaded), ${kept} already present and verified, ${failed} failed; every installed file sha256 == the lock (${s} s)`);
process.exit(failed ? 1 : 0);
