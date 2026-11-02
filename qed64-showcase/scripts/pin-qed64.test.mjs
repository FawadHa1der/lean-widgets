/* scripts/pin-qed64.mjs's runtime manifest formats (verify #3, pin) against synthetic runtimes:
 * `node --test scripts/pin-qed64.test.mjs`. No release tree, no QED64 sources, no network; the parts are written under
 * os.tmpdir() (TMPDIR) and removed. The format: QED64 docs/EMBEDDING.md "Runtime manifest formats"; the same rules as its
 * pipeline/release/verify-release.mjs and fetch-artifacts.mjs.
 *
 * Covers: a v1 file prints exactly the lines #3 always printed; a v2 gzip file (each part as served, then inflated, the
 * whole-file check over the decoded bytes); a v2 identity file; a wrong part digest, decodedBytes or whole-file digest; the
 * format's rules, refused before any part is read; an encoding the schema does not allow; the pin's schema against
 * closure.json's runtime.manifestSchemas (absent list = v1 only, absent schema = v1, the release record's schema first); the
 * script still runs as a script now that it can be imported, also through a symlink.
 */
import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';
import { runtimeChecks, runtimeFileChecks, runtimeFileFault, runtimeSchemaCheck } from './pin-qed64.mjs';

const SCRIPT = fileURLToPath(new URL('./pin-qed64.mjs', import.meta.url));
const V1 = 'org.lean-browser64.runtime/v1';
const V2 = 'org.lean-browser64.runtime/v2';
const V3 = 'org.lean-browser64.runtime/v3';
const SLICE = 16 * 1024 * 1024; // the rule's number, spelled here on purpose: every v2 part but the last decodes to exactly this
const sha = (b) => createHash('sha256').update(b).digest('hex');

let root, decoded, fixtures;
const put = (url, bytes) => {
  const p = path.join(root, 'public', url);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, bytes);
};
/** A runtime file's manifest entry, its parts on disk: encoding undefined is a v1 file (it names none, its parts have no decodedBytes). */
function entry(name, bytes, encoding) {
  const chunks = [];
  for (let i = 0, n = 0; i < bytes.length; i += SLICE, n++) {
    const slice = bytes.subarray(i, i + SLICE);
    const wire = encoding === 'gzip' ? gzipSync(slice) : slice;
    const url = `/runtime/chunks/${name}.${encoding ?? 'v1'}.part-${String(n).padStart(3, '0')}`;
    put(url, wire);
    chunks.push({ url, bytes: wire.length, sha256: sha(wire), ...(encoding ? { decodedBytes: slice.length } : {}) });
  }
  return { bytes: bytes.length, sha256: sha(bytes), ...(encoding ? { encoding } : {}), chunks };
}
const get = (k) => structuredClone(fixtures[k]);
const run = (schema, f, name = 'lean.wasm') => runtimeFileChecks(root, schema, name, f);
const passes = (r) => !r.mismatches.length && r.checks.every((c) => c.good);

before(() => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), 'pin-qed64-test-'));
  // one full slice and a short last part; compressible, as a wasm is
  decoded = Buffer.alloc(SLICE + 1000);
  for (let i = 0; i + 4 <= decoded.length; i += 4096) decoded.writeUInt32LE(i, i);
  fixtures = { v1: entry('lean.wasm', decoded), gzip: entry('lean.wasm', decoded, 'gzip'), identity: entry('lean.wasm', decoded, 'identity') };
});
after(() => { fs.rmSync(root, { recursive: true, force: true }); });

// ---- the files, verify #3 ----
test('v1: passes with exactly the lines #3 always printed', () => {
  const f = get('v1');
  assert.equal(f.chunks.length, 2);
  assert.deepEqual(run(V1, f), {
    mismatches: [],
    checks: [
      { good: true, msg: '#3 lean.wasm: 2 chunks match manifest sha256/bytes', detail: '' },
      { good: true, msg: '#3 reassembled lean.wasm sha256 == manifest', detail: `${sha(decoded).slice(0, 24)}… ${decoded.length} B` },
    ],
  });
});

test('v1: a wrong chunk fails its line, as it did, and the whole-file line follows the bytes on disk', () => {
  const f = get('v1');
  f.chunks[0].sha256 = '0'.repeat(64);
  const r = run(V1, f);
  assert.deepEqual(r.mismatches, [f.chunks[0].url]);
  assert.deepEqual(r.checks.map((c) => c.good), [false, true]);
});

test('v2 gzip: each part as served, inflated, the whole file over the decoded bytes', () => {
  const f = get('gzip');
  assert.ok(f.chunks[0].bytes < SLICE, 'the fixture is compressed');
  assert.deepEqual(run(V2, f), {
    mismatches: [],
    checks: [
      { good: true, msg: '#3 lean.wasm: 2 chunks match manifest sha256/bytes as served, each inflates to its decodedBytes', detail: '' },
      { good: true, msg: '#3 reassembled lean.wasm (inflated) sha256 == manifest', detail: `${sha(decoded).slice(0, 24)}… ${decoded.length} B` },
    ],
  });
});

test('v2 identity: like v1, with decodedBytes', () => {
  assert.deepEqual(run(V2, get('identity')), {
    mismatches: [],
    checks: [
      { good: true, msg: '#3 lean.wasm: 2 chunks match manifest sha256/bytes as served (identity)', detail: '' },
      { good: true, msg: '#3 reassembled lean.wasm (identity) sha256 == manifest', detail: `${sha(decoded).slice(0, 24)}… ${decoded.length} B` },
    ],
  });
});

test('v2 gzip: a wrong part sha256 fails, and the part is not inflated', () => {
  const f = get('gzip');
  f.chunks[1].sha256 = '0'.repeat(64);
  const r = run(V2, f);
  assert.deepEqual(r.mismatches, [f.chunks[1].url], 'as served, no inflate report');
  assert.deepEqual(r.checks.map((c) => c.good), [false, false]);
  assert.match(r.checks[1].detail, new RegExp(` ${SLICE} B$`), 'the unverified part added no decoded bytes');
});

test('v2 gzip: a wrong part size as served fails', () => {
  const f = get('gzip');
  f.chunks[0].bytes += 1;
  const r = run(V2, f);
  assert.deepEqual(r.mismatches, [f.chunks[0].url]);
  assert.equal(passes(r), false);
});

test('v2 gzip: a part with bytes that verify as served and are not gzip fails', () => {
  const f = get('gzip');
  const notGzip = Buffer.from('this part is not a gzip member');
  const url = '/runtime/chunks/lean.wasm.notgzip.part-001';
  put(url, notGzip);
  Object.assign(f.chunks[1], { url, bytes: notGzip.length, sha256: sha(notGzip) });
  const r = run(V2, f);
  assert.equal(r.mismatches.length, 1);
  assert.match(r.mismatches[0], /does not inflate to its decodedBytes 1000/);
  assert.deepEqual(r.checks.map((c) => c.good), [false, false]);
});

test('v2 gzip: a decodedBytes below the inflated length fails, and the inflater stops at it', () => {
  const f = get('gzip');
  f.chunks[1].decodedBytes -= 1; // the format's rules still hold: the sum is the file's bytes
  f.bytes -= 1;
  assert.equal(runtimeFileFault(V2, f), null);
  const r = run(V2, f);
  assert.equal(r.mismatches.length, 1);
  assert.match(r.mismatches[0], /does not inflate to its decodedBytes 999/);
  assert.deepEqual(r.checks.map((c) => c.good), [false, false]);
});

test('v2 gzip: a decodedBytes above the inflated length fails', () => {
  const f = get('gzip');
  f.chunks[1].decodedBytes += 1;
  f.bytes += 1;
  assert.equal(runtimeFileFault(V2, f), null);
  const r = run(V2, f);
  assert.deepEqual(r.mismatches, [`${f.chunks[1].url} (inflates to 1000 bytes, its decodedBytes is 1001)`]);
  assert.deepEqual(r.checks.map((c) => c.good), [false, false]);
});

test('v2 gzip: a whole-file sha256 that is not the decoded file\'s fails, with every part good', () => {
  const f = get('gzip');
  // the digest a wrong release tool would write: over the concatenated parts as served
  const wire = createHash('sha256');
  for (const c of f.chunks) wire.update(fs.readFileSync(path.join(root, 'public', c.url)));
  f.sha256 = wire.digest('hex');
  const r = run(V2, f);
  assert.deepEqual(r.mismatches, []);
  assert.deepEqual(r.checks.map((c) => c.good), [true, false]);
});

test('v2: the format\'s rules are refused before any part is read', () => {
  // each break keeps the other rules true where it can, so the rule named is the one that refuses it
  const broken = [
    ['a part but the last that is not exactly the slice', (f) => { f.chunks[0].decodedBytes -= 1; f.bytes -= 1; }, /part 0 decodes to 16777215 bytes; every part but the last decodes to exactly 16777216/],
    ['a last part above the slice', (f) => { f.chunks[1].decodedBytes = SLICE + 1; f.bytes = 2 * SLICE + 1; }, /part 1 decodes to 16777217 bytes; .* the last to at most that/],
    ['decodedBytes that do not sum to the file', (f) => { f.bytes += 1; }, /its parts decode to 16778216 bytes, the file is 16778217/],
    ['a part with no decodedBytes', (f) => { delete f.chunks[1].decodedBytes; }, /part 1 has no usable decodedBytes \(none\)/],
    ['a part with decodedBytes 0', (f) => { f.chunks[1].decodedBytes = 0; f.bytes = SLICE; }, /part 1 has no usable decodedBytes \(0\)/],
    ['a part with fractional decodedBytes', (f) => { f.chunks[1].decodedBytes = 0.5; f.bytes = SLICE + 0.5; }, /part 1 has no usable decodedBytes \(0\.5\)/],
    ['an empty part list', (f) => { f.chunks = []; f.bytes = 0; }, /it has no parts/],
    ['no part list', (f) => { delete f.chunks; }, /it has no parts/],
  ];
  for (const [what, breakIt, why] of broken) {
    const f = get('gzip');
    breakIt(f);
    for (const c of f.chunks ?? []) c.url = '/runtime/chunks/never-read.part-000'; // does not exist: reading it would throw
    const r = run(V2, f);
    assert.deepEqual(r.mismatches, [], what);
    assert.deepEqual(r.checks.map((c) => c.good), [false], what);
    assert.equal(r.checks[0].msg, `#3 lean.wasm: its entry obeys ${V2}`, what);
    assert.match(r.checks[0].detail, why, what);
  }
});

test('v2 identity: decodedBytes that is not its bytes is refused', () => {
  const f = get('identity');
  f.chunks[1].bytes -= 1;
  assert.match(runtimeFileFault(V2, f), /part 1 is identity-encoded, but its decodedBytes 1000 is not its bytes 999/);
});

test('an encoding the schema does not allow is refused', () => {
  const br = get('gzip'); br.encoding = 'br';
  assert.match(run(V2, br).checks[0].detail, /encoding "br" is not one .*runtime\/v2 allows \(identity, gzip\)/);
  const none = get('gzip'); delete none.encoding;
  assert.match(run(V2, none).checks[0].detail, /encoding \(none\) is not one .*runtime\/v2 allows/);
  const v1Gzip = get('gzip');
  assert.match(run(V1, v1Gzip).checks[0].detail, /encoding "gzip" is not one .*runtime\/v1 allows \(identity\)/);
  const v1Br = get('v1'); v1Br.encoding = 'br';
  assert.equal(passes(run(V1, v1Br)), false);
  const v1Identity = get('v1'); v1Identity.encoding = 'identity';
  assert.equal(passes(run(V1, v1Identity)), true, 'a v1 file may name identity');
});

test('a schema this tool does not read is refused file by file', () => {
  for (const schema of [V3, 'constructor']) assert.match(run(schema, get('gzip')).checks[0].detail, /is not one this tool reads/);
});

// ---- the pin's schema against closure.json ----
const closure = (...schemas) => ({ runtime: { minKernelPatch: '0032', manifestSchemas: schemas } });
const noList = [null, {}, { runtime: { minKernelPatch: '0032' } }];

test('schema in runtime.manifestSchemas: accepted', () => {
  for (const [manifest, schema] of [[{ schema: V1 }, V1], [{ schema: V2 }, V2]]) {
    const r = runtimeSchemaCheck(manifest, null, closure(V1, V2));
    assert.deepEqual(r, { served: schema, schema, schemas: [V1, V2], listed: true, fault: null });
  }
});

test('schema not in runtime.manifestSchemas: refused', () => {
  assert.match(runtimeSchemaCheck({ schema: V2 }, null, closure(V1)).fault, /the pinned workers do not read schema .*runtime\/v2: .* lists .*runtime\/v1$/);
  assert.match(runtimeSchemaCheck({ schema: V3 }, null, closure(V1, V2)).fault, /the pinned workers do not read schema .*runtime\/v3/);
  assert.match(runtimeSchemaCheck({ schema: V1 }, null, closure(V2)).fault, /the pinned workers do not read schema .*runtime\/v1/);
  assert.match(runtimeSchemaCheck({ schema: V1 }, null, closure()).fault, /lists nothing$/);
});

test('a schema the workers list and this tool cannot read: refused', () => {
  assert.match(runtimeSchemaCheck({ schema: V3 }, null, closure(V1, V2, V3)).fault, /is not one this tool reads/);
});

test('absent runtime.manifestSchemas (or no closure.json) means v1 only', () => {
  for (const c of noList) {
    assert.deepEqual(runtimeSchemaCheck({ schema: V1 }, null, c), { served: V1, schema: V1, schemas: [V1], listed: false, fault: null });
    assert.match(runtimeSchemaCheck({ schema: V2 }, null, c).fault, /is absent, which means .*runtime\/v1 only$/);
  }
});

test('absent schema means v1', () => {
  for (const record of [null, {}, { runtime: { buildId: 'wasm64-0000000000000000' } }]) {
    const r = runtimeSchemaCheck({}, record, closure(V1, V2));
    assert.deepEqual([r.served, r.schema, r.fault], [V1, V1, null]);
    assert.equal(runtimeSchemaCheck({}, record, null).fault, null);
    assert.match(runtimeSchemaCheck({}, record, closure(V2)).fault, /do not read schema .*runtime\/v1/);
  }
});

test('the release record\'s runtime.schema first, else the manifest\'s; the two must agree', () => {
  const r = runtimeSchemaCheck({ schema: V2 }, { runtime: { schema: V2 } }, closure(V1, V2));
  assert.deepEqual([r.served, r.schema, r.fault], [V2, V2, null]);
  assert.equal(runtimeSchemaCheck({ schema: V2 }, { runtime: {} }, closure(V1, V2)).schema, V2, 'a record without it: the manifest\'s');
  assert.match(runtimeSchemaCheck({ schema: V2 }, { runtime: { schema: V1 } }, closure(V1, V2)).fault, /the release record names a runtime of schema .*runtime\/v1, the served manifest's is .*runtime\/v2/);
  assert.match(runtimeSchemaCheck({}, { runtime: { schema: V2 } }, closure(V1, V2)).fault, /the release record names a runtime of schema .*runtime\/v2, the served manifest's is .*runtime\/v1/);
});

test('a runtime.manifestSchemas that is not a list of strings: refused', () => {
  for (const bad of [V1, null, {}, [1]]) {
    assert.match(runtimeSchemaCheck({ schema: V1 }, null, { runtime: { manifestSchemas: bad } }).fault, /is not a list of schemas/);
  }
});

// ---- what verify prints: the schema line and the file lines together ----
test('runtimeChecks: a v1 runtime with no list prints no schema line; with the list it does; an unlisted v2 fails it', () => {
  const v1 = { files: { 'lean.wasm': get('v1') } };
  const v2 = { schema: V2, files: { 'lean.wasm': get('gzip') } };
  const msgs = (l) => l.filter((x) => x.msg).map((x) => x.msg);
  assert.ok(!msgs(runtimeChecks(root, v1, null, null)).some((m) => m.includes('runtime schema')));
  assert.ok(runtimeChecks(root, v1, null, null).every((x) => x.good));
  const listed = runtimeChecks(root, v2, null, { runtime: { manifestSchemas: [V1, V2] } });
  assert.match(listed[0].msg, /runtime schema .*\/v2 is one/);
  assert.ok(listed.every((x) => x.good), JSON.stringify(listed));
  const unlisted = runtimeChecks(root, v2, null, { runtime: {} });
  assert.equal(unlisted[0].good, false);
  assert.match(unlisted[0].detail, /do not read schema/);
  assert.equal(runtimeChecks(root, v2, { runtime: { schema: V1 } }, { runtime: { manifestSchemas: [V1, V2] } })[0].good, false, 'the record disagrees with the manifest');
  const broken = runtimeChecks(root, v1, null, null, 'closure.json at abc is not JSON');
  assert.equal(broken[0].good, false);
  assert.equal(broken[0].detail, 'closure.json at abc is not JSON');
  const bad = get('v1'); bad.chunks[0].sha256 = '0'.repeat(64);
  assert.ok(runtimeChecks(root, { files: { 'lean.wasm': bad } }, null, null).some((x) => x.mismatch === bad.chunks[0].url));
});

test('v2 gzip: a part with trailing bytes or several members fails, though each verifies as served', () => {
  const tail = Buffer.alloc(1000, 7);
  const cases = { nuls: Buffer.concat([gzipSync(tail), Buffer.alloc(8)]), members: Buffer.concat([gzipSync(tail.subarray(0, 400)), gzipSync(tail.subarray(400))]) };
  for (const [what, wire] of Object.entries(cases)) {
    const url = `/runtime/chunks/odd.${what}.part-000`;
    put(url, wire);
    const f = { bytes: tail.length, sha256: sha(tail), encoding: 'gzip', chunks: [{ url, bytes: wire.length, sha256: sha(wire), decodedBytes: tail.length }] };
    const r = run(V2, f);
    assert.equal(r.mismatches.length, 1, what);
    assert.match(r.mismatches[0], /not one gzip member/, what);
  }
});

test('v2: a null part is refused by the format check, not a crash', () => {
  const f = get('gzip'); f.chunks[0] = null;
  assert.match(runtimeFileFault(V2, f), /part 0 has no usable decodedBytes/);
});

// ---- importable, and still a script ----
test('run directly, or through a symlink, the script dispatches (usage, exit 2); imported, it does not', () => {
  const link = path.join(root, 'pin-qed64-link.mjs');
  fs.symlinkSync(SCRIPT, link);
  for (const p of [SCRIPT, link]) {
    const r = spawnSync(process.execPath, [p], { encoding: 'utf8' });
    assert.equal(r.status, 2, `${p}: ${r.stderr}`);
    assert.match(r.stderr, /^usage: pin-qed64\.mjs /);
  }
  // a checkout reached through a directory link, with the link kept in import.meta.url: must not print nothing and exit 0
  const dirLink = path.join(root, 'checkout-link');
  fs.symlinkSync(path.dirname(path.dirname(SCRIPT)), dirLink);
  const preserved = spawnSync(process.execPath, ['--preserve-symlinks-main', path.join(dirLink, 'scripts/pin-qed64.mjs')], { encoding: 'utf8' });
  assert.equal(preserved.status, 2, preserved.stderr);
});
