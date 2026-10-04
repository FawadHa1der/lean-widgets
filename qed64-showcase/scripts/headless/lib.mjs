// Shared helpers for the headless wasm verifiers (plan §6 E1/E3/E3b).
// Nothing here writes outside $W or $SC/out; nothing touches the QED64 trees.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

export const SC = path.resolve(import.meta.dirname, '..', '..');
export const { W } = await import(path.join(SC, 'scripts/lib/env.mjs')); // the work dir (QED64_SHOWCASE_WORK)
// the TARGET pin (scripts/lib/pins.mjs: SHOWCASE_PIN=<id>, else the active pin) and its stores: without SHOWCASE_PIN the
// active links (QED64.lock.json, $W/stage1, out/headless), with it that pin's own store paths; QED64's own modules
// (artifact-paths, snapshot-probe, node-runner, lsp-frames) come from the pin's SOURCE dependency (submodule/worktree)
const PINS = await import(path.join(SC, 'scripts/lib/pins.mjs'));
export const PIN = PINS.targetPinId();
export const QED64_SRC = PINS.storePath('qed64');
export const LOCK = JSON.parse(fs.readFileSync(PINS.storePath('lock'), 'utf8'));
export const BID = LOCK.qed64.buildId; // the target pin's runtime
if (BID !== PINS.targetBuildId()) throw new Error(`lock ${PINS.storePath('lock')} names ${BID}, the pin descriptor ${PINS.targetBuildId()}`);
/** where the verifiers write their results: out/headless (the active runtime's link) or out/runtimes/<bid>/headless */
export const OUT_HEADLESS = PINS.storePath('headless');
// the target runtime's stage1 ($W/stage1 is a pin link), resolved to its real path: Node loads lean.js from the
// realpath, and the runtime's own file lookups (bin/) must match the mounted directory
export const DEFAULT_ARTIFACT = (() => { const s = PINS.storePath('stage1'); try { return fs.realpathSync(s); } catch { return s; } })();

export function parseArgs(argv, { flags = [], multi = [] } = {}) {
  const o = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) { o._.push(a); continue; }
    const k = a.slice(2);
    if (flags.includes(k)) { o[k] = true; continue; }
    const v = argv[++i];
    if (v === undefined) throw new Error(`missing value for ${a}`);
    if (multi.includes(k)) (o[k] ??= []).push(v); else o[k] = v;
  }
  return o;
}

/** buildId of a stage1-style artifact dir, via QED64's own identity function (pipeline/toolchain/artifact-paths.mjs). */
export async function buildIdOf(dir) {
  const { buildIdOfArtifact } = await import(path.join(QED64_SRC, 'pipeline/toolchain/artifact-paths.mjs'));
  return buildIdOfArtifact(dir);
}

export async function requirePairedArtifact(dir) {
  const id = await buildIdOf(dir);
  if (id !== BID) throw new Error(`artifact ${dir}: buildId ${id} != pinned ${BID}`);
  return id;
}

/** free+inactive (+speculative) bytes (macOS vm_stat; Linux MemAvailable): scripts/lib/platform.mjs. */
export const { reclaimableBytes: freeInactiveBytes } = await import(path.join(SC, 'scripts/lib/platform.mjs'));

/** Real bake processes only: executable `node` (or /usr/bin/time wrapping it) whose argv runs
 * bake-snapshot.mjs. `pgrep -f bake-snapshot` alone also matches any shell/monitor whose
 * command line merely mentions the name (including the pgrep caller itself). */
export function bakeRunning() {
  const ps = execFileSync('/bin/ps', ['-axo', 'pid=,comm=,args=']).toString().split('\n');
  return ps.filter((l) => /bake-snapshot\.mjs/.test(l) && /^\s*\d+\s+(\S*\/)?(node|time)\s/.test(l))
    .map((l) => l.trim().slice(0, 120)).join('\n');
}

/** Memory guard for one wasm Node process (measured peak footprint ≈ 10.5 GB with
 * mathlib.snap loaded; see README). Refuses below `minGb` free+inactive. */
export function memoryGuard(minGb, who) {
  const free = freeInactiveBytes();
  const bake = bakeRunning();
  const gb = (free / 1e9).toFixed(1);
  console.log(`[${who}] memory: ${gb} GB free+inactive (need ≥ ${minGb}); bake-snapshot running: ${bake ? 'yes' : 'no'}`);
  if (free < minGb * 1e9) throw new Error(`refusing to start: ${gb} GB free+inactive < ${minGb} GB`);
}

/** One wasm verifier at a time on this host (they each peak around 10 GB). */
export function acquireLock(who) {
  const dir = path.join(W, 'headless', '.lock');
  fs.mkdirSync(path.dirname(dir), { recursive: true });
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      fs.mkdirSync(dir);
      fs.writeFileSync(path.join(dir, 'owner'), `${process.pid} ${who} ${new Date().toISOString()}\n`);
      const release = () => { try { fs.rmSync(dir, { recursive: true, force: true }); } catch {} };
      process.on('exit', release);
      for (const s of ['SIGINT', 'SIGTERM']) process.on(s, () => { release(); process.exit(130); });
      return;
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      const owner = (() => { try { return fs.readFileSync(path.join(dir, 'owner'), 'utf8').trim(); } catch { return ''; } })();
      const pid = Number(owner.split(' ')[0]);
      let alive = false; try { if (pid) { process.kill(pid, 0); alive = true; } } catch {}
      if (alive) throw new Error(`another headless verifier holds ${dir}: ${owner}`);
      fs.rmSync(dir, { recursive: true, force: true }); // stale
    }
  }
  throw new Error(`could not acquire ${dir}`);
}

/** Leading import block of a Lean file: indices of the import lines. The block
 * ends at the first line that is neither blank, a `--` comment, nor an import. */
export const IMPORT_RE = /^\s*(?:public\s+|private\s+)?(?:meta\s+)?import\s+(\S+)/;
export function headerImports(text) {
  const lines = text.split('\n');
  const idx = [];
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (IMPORT_RE.test(l)) { idx.push(i); continue; }
    if (l.trim() === '' || l.trim().startsWith('--')) continue;
    break;
  }
  return { lines, idx, modules: idx.map((i) => IMPORT_RE.exec(lines[i])[1]) };
}

export const sha256 = async (s) => (await import('node:crypto')).createHash('sha256').update(s).digest('hex');
export const relSC = (p) => path.relative(SC, p);

/** Print a fixed-width table. rows: array of arrays. */
export function table(head, rows) {
  const all = [head, ...rows].map((r) => r.map((c) => String(c ?? '').replace(/\n/g, ' ⏎ ')));
  const w = head.map((_, i) => Math.min(90, Math.max(...all.map((r) => r[i].length))));
  const fmt = (r) => r.map((c, i) => (c.length > w[i] ? c.slice(0, w[i] - 1) + '…' : c.padEnd(w[i]))).join('  ');
  console.log(fmt(all[0])); console.log(w.map((n) => '-'.repeat(n)).join('  '));
  for (const r of all.slice(1)) console.log(fmt(r));
}

// ---------- raw snapshot provenance (audit: tie a headless PASS to a served .snapz digest) ----------
// A raw .snap is "paired" when its content provably equals the inflation of a .snapz whose
// sha256 is the digest in a qed64.snapshot-index/v1 index.json:
//   via 'index'   --index <index.json>: the entry with bytes == size is gunzipped now; its sha256
//                 must equal entry.digest, its inflated length entry.bytes, and its inflated sha256
//                 the raw file's sha256 (same as scripts/pair-check.mjs --cmp)
//   via 'sidecar' <raw>.provenance.json written by derive-raw.sh right after a digest-checked
//                 gunzip; the raw file's sha256 must equal sidecar.rawSha256
// A mismatch is always a failure; "unpaired" (no index entry / no sidecar) fails unless allowed.
const hashFile = async (file) => {
  const { createHash } = await import('node:crypto');
  const h = createHash('sha256');
  for await (const c of fs.createReadStream(file, { highWaterMark: 8 << 20 })) h.update(c);
  return h.digest('hex');
};
async function inflateDigests(snapz) {
  const { createHash } = await import('node:crypto');
  const { createGunzip } = await import('node:zlib');
  const { pipeline } = await import('node:stream/promises');
  const gz = createHash('sha256'), raw = createHash('sha256'); let inflated = 0;
  await pipeline(fs.createReadStream(snapz, { highWaterMark: 8 << 20 }),
    async function* (src) { for await (const c of src) { gz.update(c); yield c; } },
    createGunzip(),
    async function* (src) { for await (const c of src) { inflated += c.length; raw.update(c); } });
  return { snapzSha256: gz.digest('hex'), rawSha256: raw.digest('hex'), inflatedBytes: inflated };
}
export async function snapProvenance(snap, indexes = []) {
  const st = fs.statSync(snap);
  const rec = { snap, bytes: st.size, mtimeMs: st.mtimeMs, sha256: await hashFile(snap), paired: null, ok: false, detail: '' };
  let firstBad = null; // keep searching (several indexes may be given); report the first failure if nothing pairs
  for (const ix of indexes) {
    const idx = JSON.parse(fs.readFileSync(ix, 'utf8'));
    const cands = (idx.snapshots ?? []).filter((e) => e.bytes === st.size);
    for (const e of cands) {
      const snapz = path.join(path.dirname(ix), path.basename(e.url));
      const d = await inflateDigests(snapz);
      const want = String(e.digest).replace(/^sha256:/, '');
      const p = { via: 'index', index: ix, name: e.name, snapz, digest: want, runtime: e.runtime, snapzSha256: d.snapzSha256, inflatedSha256: d.rawSha256, inflatedBytes: d.inflatedBytes };
      if (d.snapzSha256 !== want) { firstBad ??= { paired: { ...p, mismatch: true }, detail: `${path.basename(snapz)}: sha256 ${d.snapzSha256.slice(0, 16)} != index digest ${want.slice(0, 16)}` }; continue; }
      if (e.runtime !== BID) { firstBad ??= { paired: { ...p, mismatch: true }, detail: `index entry ${e.name}: runtime ${e.runtime} != ${BID}` }; continue; }
      if (d.rawSha256 === rec.sha256 && d.inflatedBytes === st.size) {
        Object.assign(rec, { paired: p, ok: true, detail: `= gunzip(${path.basename(snapz)}) [${want.slice(0, 16)}] via ${relSC(ix).startsWith('..') ? ix : relSC(ix)}` }); return rec;
      }
      firstBad ??= { paired: { ...p, mismatch: true }, detail: `raw sha256 ${rec.sha256.slice(0, 16)} != gunzip(${path.basename(snapz)}) ${d.rawSha256.slice(0, 16)}` };
    }
  }
  if (firstBad) return Object.assign(rec, firstBad); // a same-size entry exists but its content differs
  const side = `${snap}.provenance.json`;
  if (!indexes.length && fs.existsSync(side)) {
    const s = JSON.parse(fs.readFileSync(side, 'utf8'));
    const p = { via: 'sidecar', sidecar: side, name: s.name, snapz: s.snapz, digest: s.snapzSha256, index: s.index };
    if (s.rawSha256 === rec.sha256 && s.rawBytes === st.size) Object.assign(rec, { paired: p, ok: true, detail: `sidecar: = gunzip(${path.basename(s.snapz)}) [${s.snapzSha256.slice(0, 16)}]` });
    else Object.assign(rec, { paired: { ...p, mismatch: true }, detail: `raw sha256 ${rec.sha256.slice(0, 16)} != sidecar rawSha256 ${String(s.rawSha256).slice(0, 16)}` });
    return rec;
  }
  rec.detail = indexes.length ? `no entry with bytes == ${st.size} in ${indexes.join(', ')}` : `no --index and no ${path.basename(side)}`;
  return rec;
}
/** Pre-flight provenance for every snap; returns records and pushes one check per snap. */
export async function checkSnapProvenance(snaps, { indexes = [], allowUnpaired = false, check, log = console.log }) {
  const recs = [];
  for (const s of snaps) {
    const t = Date.now();
    const r = await snapProvenance(s, indexes);
    r.verifyMs = Date.now() - t;
    const unpaired = !r.ok && !r.paired;
    if (unpaired && allowUnpaired) r.allowedUnpaired = true;
    log(`provenance ${path.basename(s)}: sha256 ${r.sha256.slice(0, 16)} ${r.ok ? 'PAIRED' : unpaired ? 'UNPAIRED' : 'MISMATCH'} ${r.detail} (${r.verifyMs} ms)`);
    check(r.ok || (unpaired && allowUnpaired), `raw ${path.basename(s)} content paired with a served .snapz digest${unpaired && allowUnpaired ? ' (UNPAIRED, allowed)' : ''}`,
      `sha256 ${r.sha256.slice(0, 16)}: ${r.detail}`);
    recs.push(r);
  }
  return recs;
}
