#!/usr/bin/env node
// load-r2.mjs — fill wrangler dev's LOCAL R2 (Miniflare) from the rehearsal's fake bucket, so the real
// infra/worker.js can be served by `wrangler dev --local` against exactly what scripts/upload-artifacts.sh wrote.
// No account, no network beyond 127.0.0.1.
//
//   node scripts/deploy-rehearsal/load-r2.mjs --bucket-dir <dir> --bucket <name> --persist-to <state dir> \
//        --manifest <DEPLOY_OUT>/manifest.json [--port 8799]
//
// <bucket-dir> is the directory the fake rclone remote wrote "<bucket>/<prefix>…" into; every file under
// <bucket-dir>/<bucket>/ is one object whose key is its relative path. Why not `wrangler r2 object put --local`?
// It refuses objects over ~300 MiB (the same cap as the remote command) and three .snapz are larger. Instead this
// runs a 15-line loader worker (r2-loader-worker.js) under `wrangler dev --local --persist-to <persist-to>` with
// the same R2 binding (bucket_name = <bucket>) and streams each file into env.ARTIFACTS.put() over 127.0.0.1 with a
// known Content-Length, the manifest's sha256 (R2 verifies it) and the manifest's Content-Type (what
// upload-artifacts.sh sets with --header-upload; the local rclone backend keeps no metadata). The real worker,
// served later by `wrangler dev --local --persist-to <persist-to>`, then reads the same local bucket.
// (Miniflare's JS API changes shape between versions; wrangler's CLI is the supported, pinned interface.)
// Every object must be a manifest key; every manifest key must be loaded. Prints LOAD-R2 OK / FAILED.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const argv = process.argv.slice(2);
const val = (n) => { const i = argv.indexOf(n); if (i < 0 || !argv[i + 1]) { console.error(`missing ${n}`); process.exit(2); } return argv[i + 1]; };
const bucketDir = path.resolve(val('--bucket-dir')); const bucket = val('--bucket');
const persist = path.resolve(val('--persist-to')); const manifest = JSON.parse(fs.readFileSync(val('--manifest'), 'utf8'));
const byKey = new Map(manifest.r2.map((o) => [o.key, o]));

const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(path.join(d, e.name)) : e.isFile() ? [path.join(d, e.name)] : []));
const root = path.join(bucketDir, bucket);
const files = walk(root).map((f) => ({ f, key: path.relative(root, f).split(path.sep).join('/') })).sort((a, b) => (a.key < b.key ? -1 : 1));

// The loader runs under the same `wrangler dev --local --persist-to` the rehearsal serves the real worker with, so the
// on-disk layout (<persist-to>/v3/r2, namespace id = bucket_name) is wrangler's own, whatever Miniflare version it ships.
const work = path.dirname(persist);
const cfg = path.join(work, 'r2-loader.wrangler.toml');
fs.writeFileSync(cfg, [
  '# rehearsal only: written by scripts/deploy-rehearsal/load-r2.mjs',
  'name = "rehearsal-r2-loader"',
  `main = ${JSON.stringify(path.join(SC, 'scripts/deploy-rehearsal/r2-loader-worker.js'))}`,
  'compatibility_date = "2026-08-01"',
  '[[r2_buckets]]', 'binding = "ARTIFACTS"', `bucket_name = ${JSON.stringify(bucket)}`, '',
].join('\n'));
const port = Number(argv.includes('--port') ? val('--port') : 8799);
const dev = spawn(path.join(SC, 'infra/node_modules/.bin/wrangler'), ['dev', '--config', cfg, '--local', '--persist-to', persist, '--ip', '127.0.0.1', '--port', String(port), '--inspector-port', String(port + 1), '--show-interactive-dev-session=false'],
  { cwd: work, env: { ...process.env, WRANGLER_SEND_METRICS: 'false', CLOUDFLARE_API_TOKEN: '', CI: '1' }, stdio: ['ignore', 'pipe', 'pipe'] });
let devLog = ''; dev.stdout.on('data', (c) => (devLog += c)); dev.stderr.on('data', (c) => (devLog += c));
const url = `http://127.0.0.1:${port}/`;
for (let i = 0; ; i++) {
  try { await fetch(url + '__ready'); break; } catch {}
  if (i > 120 || dev.exitCode !== null) { console.log(devLog); console.log('LOAD-R2 FAILED: the loader wrangler dev did not start'); dev.kill(); process.exit(1); }
  await new Promise((r) => setTimeout(r, 500));
}
const stop = async () => { dev.kill('SIGINT'); await new Promise((r) => { dev.once('exit', r); setTimeout(r, 5000); }); if (dev.exitCode === null) dev.kill('SIGKILL'); };
const put = (f, key, o) => new Promise((resolve, reject) => {
  const size = fs.statSync(f).size;
  const req = http.request(new URL(encodeURIComponent(key).replace(/%2F/g, '/'), url), {
    method: 'PUT', headers: { 'content-length': size, 'x-content-type': o.contentType, 'x-sha256': o.sha256 },
  }, (res) => { let b = ''; res.on('data', (c) => (b += c)); res.on('end', () => (res.statusCode === 200 ? resolve(JSON.parse(b)) : reject(new Error(`${key}: ${res.statusCode} ${b.slice(0, 200)}`)))); });
  req.on('error', reject);
  fs.createReadStream(f).pipe(req);
});

let bad = 0; let bytes = 0; const t0 = Date.now();
for (const { f, key } of files) {
  const o = byKey.get(key);
  if (!o) { console.log(`FAIL ${key}: in the fake bucket but not in the manifest`); bad++; continue; }
  try {
    const r = await put(f, key, o);
    if (r.size !== o.size) { console.log(`FAIL ${key}: stored ${r.size} B, manifest ${o.size}`); bad++; }
    bytes += r.size;
  } catch (e) { console.log(`FAIL ${e.message}`); bad++; }
}
const loaded = new Set(files.map((x) => x.key));
const missing = manifest.r2.filter((o) => !loaded.has(o.key));
for (const o of missing.slice(0, 10)) console.log(`FAIL ${o.key}: in the manifest but not in the fake bucket`);
bad += missing.length;
// read back every object's size and Content-Type through the binding
let typed = 0;
for (const o of manifest.r2) {
  const r = await (await fetch(new URL(encodeURIComponent(o.key).replace(/%2F/g, '/'), url))).json();
  if (!r || r.size !== o.size || r.contentType !== o.contentType) { console.log(`FAIL read-back ${o.key}: ${JSON.stringify(r)}`); bad++; } else typed++;
}
await stop();
console.log(`${bad ? 'LOAD-R2 FAILED' : 'LOAD-R2 OK'}: ${files.length} objects, ${(bytes / 1e9).toFixed(3)} GB from ${root} into ${persist}/v3 (bucket ${bucket}); ${typed}/${manifest.r2.length} read back with the manifest's size and Content-Type; ${((Date.now() - t0) / 1000).toFixed(0)} s`);
process.exit(bad ? 1 : 0);
