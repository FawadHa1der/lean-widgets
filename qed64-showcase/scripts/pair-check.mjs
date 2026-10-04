#!/usr/bin/env node
// pair-check.mjs — BUILD-PLAN §5 C6 (offline half; the live half is QED64's read-only preflight).
//
//   node scripts/pair-check.mjs <snapshot dir with index.json> [--raw name=/abs/out.snap ...] [--cmp name=/abs/raw.snap ...]
//
// Checks, each OK/FAIL (exit 1 on any FAIL):
//   P1 buildIdOfArtifact(W/stage1) == BID (the vendored artifact-paths.mjs function the bake used)
//   P2 every index entry has runtime == BID
//   P3 per entry: sha256(file) == digest, size == transfer, gunzip byte count == bytes
//   --raw name=path   also writes that entry's inflated bytes to path (raw snapshot for the headless probes)
//   --cmp name=path   requires the inflated bytes to equal an existing raw file (e.g. the bake's widgets.snap)
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { createGunzip } from 'node:zlib';
import { fileURLToPath } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { W } = await import(path.join(SC, 'scripts/lib/env.mjs')); // the work dir (QED64_SHOWCASE_WORK)
const { targetBuildId, storePath } = await import(path.join(SC, 'scripts/lib/pins.mjs'));
const BID = targetBuildId(); // the TARGET pin's runtime (SHOWCASE_PIN=<id>, else the active pin; scripts/lib/pins.mjs)
const { buildIdOfArtifact } = await import(path.join(storePath('vendor'), 'pipeline/toolchain/artifact-paths.mjs'));

const argv = process.argv.slice(2);
const dir = argv[0];
if (!dir) { console.error('usage: pair-check.mjs <dir> [--raw name=path] [--cmp name=path]'); process.exit(2); }
const raw = {}, cmp = {};
for (let i = 1; i < argv.length; i++) {
  const [k, v] = (argv[i + 1] || '').split(/=(.*)/s);
  if (argv[i] === '--raw') raw[k] = v; else if (argv[i] === '--cmp') cmp[k] = v; else { console.error(`unknown ${argv[i]}`); process.exit(2); }
  i++;
}
let fails = 0;
const ok = (c, m, d = '') => { console.log(`${c ? 'OK  ' : 'FAIL'} ${m}${d ? ' — ' + d : ''}`); if (!c) fails++; };

const art = storePath('stage1');
ok(buildIdOfArtifact(art) === BID, `P1 buildIdOf(${art}) == ${BID}`, buildIdOfArtifact(art));
const idx = JSON.parse(fs.readFileSync(path.join(dir, 'index.json'), 'utf8'));
ok(idx.schema === 'qed64.snapshot-index/v1', 'index schema qed64.snapshot-index/v1');
for (const e of idx.snapshots) {
  ok(e.runtime === BID, `P2 ${e.name}: runtime == ${BID}`, e.runtime);
  const file = path.join(dir, path.basename(e.url));
  const gz = createHash('sha256');
  let inflated = 0; const rawHash = createHash('sha256');
  const sink = raw[e.name] ? fs.createWriteStream(raw[e.name]) : null;
  await pipeline(fs.createReadStream(file, { highWaterMark: 8 << 20 }),
    async function* (src) { for await (const c of src) { gz.update(c); yield c; } },
    createGunzip(),
    async function* (src) { for await (const c of src) { inflated += c.length; rawHash.update(c); if (sink && !sink.write(c)) await new Promise((r) => sink.once('drain', r)); } });
  if (sink) await new Promise((r) => sink.end(r));
  const size = fs.statSync(file).size;
  ok('sha256:' + gz.digest('hex') === e.digest, `P3 ${e.name}: sha256(${path.basename(file)}) == digest`, e.digest.slice(7, 23));
  ok(size === e.transfer, `P3 ${e.name}: size ${size} == transfer ${e.transfer}`);
  ok(inflated === e.bytes, `P3 ${e.name}: gunzip bytes ${inflated} == bytes ${e.bytes}`);
  const rh = rawHash.digest('hex');
  if (raw[e.name]) ok(fs.statSync(raw[e.name]).size === e.bytes, `RAW ${e.name} -> ${raw[e.name]} (${fs.statSync(raw[e.name]).size} B == index bytes)`, `sha256 ${rh.slice(0, 16)}`);
  if (cmp[e.name]) {
    const h = createHash('sha256');
    await pipeline(fs.createReadStream(cmp[e.name], { highWaterMark: 8 << 20 }), async function* (s) { for await (const c of s) h.update(c); });
    ok(h.digest('hex') === rh, `CMP ${e.name}: inflated bytes == ${cmp[e.name]}`, rh.slice(0, 16));
  }
}
console.log(fails ? `PAIRING RED ${dir} (${fails} FAIL)` : `PAIRING GREEN ${dir} (${idx.snapshots.map((s) => s.name).join(', ')})`);
process.exit(fails ? 1 : 0);
