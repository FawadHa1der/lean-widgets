#!/usr/bin/env node
// E1 (BUILD-PLAN §6): compile an example through the worker's batch compile
// path on the EXACT bake key.
//
// snapshot-probe / lean_wasm_compile only hits the env cache on an exact key
// (plan C2), so the example's import lines are replaced by the BAKE-KEY file's
// imports. Nothing else is stripped or changed (the replacement sits where the
// first import line was; diagnostics are mapped back to the example's lines).
// Then the vendored snapshot-probe runs with --via-mem (the browser worker's
// _lean_wasm_load_snapshot_mem path) and --dump-messages, and its PASS/FAIL,
// the key the snapshot seeded, the compile time, and every message are parsed.
//
// usage:
//   node scripts/headless/exact-header.mjs (--pkg <pkg> | --example <file.lean>)
//        --bake-key <BAKE-KEY.txt> --snap <raw .snap> --lib <olean tree>
//        [--snapset <label>]          label for output names (default: snap basename)
//        [--artifact <stage1 dir>]    default $W/stage1 (buildId must be the pinned one)
//        [--budget-ms 120000]         compile budget; overrun = silent re-import = wrong key
//        [--allow-warnings]           warnings do not fail the gate (default: they do)
//        [--expect fail]              negative control: gate passes iff the compile
//                                     reports ≥1 error (and nothing else went wrong)
//        [--index <index.json>]…      pair the --snap CONTENT with a served .snapz (gunzip + sha256);
//                                     without --index, <snap>.provenance.json (derive-raw.sh) is used
//        [--allow-unpaired]           an unpaired raw does not fail the gate (a mismatch always does)
//        [--min-free-gb 12] [--out <json>]
// exit 0 = gate passed, 1 = gate failed, 2 = usage / setup error.
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import {
  SC, W, VENDOR, BID, OUT_HEADLESS, DEFAULT_ARTIFACT, parseArgs, requirePairedArtifact, memoryGuard, acquireLock,
  headerImports, IMPORT_RE, sha256, table, checkSnapProvenance,
} from './lib.mjs';

const WHO = 'E1';
let o;
try { o = parseArgs(process.argv.slice(2), { flags: ['allow-warnings', 'allow-unpaired'], multi: ['index'] }); } catch (e) { console.error(e.message); process.exit(2); }
const example = o.example ? path.resolve(o.example) : o.pkg ? path.join(SC, 'lean/examples', `${o.pkg}.lean`) : null;
if (!example || !o['bake-key'] || !o.snap || !o.lib) {
  console.error('usage: exact-header.mjs (--pkg <pkg> | --example <f.lean>) --bake-key <file> --snap <raw.snap> --lib <tree> [--snapset s] [--artifact d] [--budget-ms n] [--allow-warnings] [--expect fail] [--index index.json]… [--allow-unpaired] [--out json]');
  process.exit(2);
}
const name = o.pkg ?? path.basename(example, '.lean');
const snap = path.resolve(o.snap), lib = path.resolve(o.lib), artifact = path.resolve(o.artifact ?? DEFAULT_ARTIFACT);
const snapset = o.snapset ?? path.basename(snap, '.snap');
const budgetMs = Number(o['budget-ms'] ?? 120000);
const expectFail = o.expect === 'fail';
const out = path.resolve(o.out ?? path.join(OUT_HEADLESS, `${name}.${snapset}.e1.json`));
for (const [k, p] of [['example', example], ['bake-key', o['bake-key']], ['snap', snap], ['lib', lib]])
  if (!fs.existsSync(p)) { console.error(`${WHO}: --${k} ${p} does not exist`); process.exit(2); }

// ---- build the exact-key document -------------------------------------------------
const original = fs.readFileSync(example, 'utf8');
const keyText = fs.readFileSync(o['bake-key'], 'utf8');
const keyLines = keyText.split('\n').filter((l) => IMPORT_RE.test(l)).map((l) => l.trim());
if (!keyLines.length) { console.error(`${WHO}: ${o['bake-key']} has no import lines`); process.exit(2); }
const hdr = headerImports(original);
if (!hdr.idx.length) { console.error(`${WHO}: ${example} has no leading import block`); process.exit(2); }
const first = hdr.idx[0], last = hdr.idx[hdr.idx.length - 1];
// Replace ONLY the import lines; anything interleaved (blank lines / comments) is kept.
const kept = hdr.lines.slice(first, last + 1).filter((_, j) => !hdr.idx.includes(first + j));
const outLines = [...hdr.lines.slice(0, first), ...keyLines, ...kept, ...hdr.lines.slice(last + 1)];
const exactText = outLines.join('\n');
const delta = keyLines.length - hdr.idx.length; // lines after the header block shift by this much
const bodyStartExact = first + keyLines.length + kept.length; // 0-based first body line in exactText
const toOriginalLine = (line1) => { // 1-based exact line -> 1-based example line (null inside the header)
  const z = line1 - 1;
  if (z < first) return line1;
  if (z < bodyStartExact) return null;
  return z - delta + 1;
};
// invariant: nothing but the import lines changed
if (outLines.slice(bodyStartExact).join('\n') !== hdr.lines.slice(last + 1).join('\n')) throw new Error('internal: body changed');

const workDir = path.join(W, 'headless');
fs.mkdirSync(workDir, { recursive: true }); fs.mkdirSync(path.join(W, 'logs'), { recursive: true });
const exactFile = path.join(workDir, `${name}.${snapset}.exact.lean`);
fs.writeFileSync(exactFile, exactText);
const logFile = path.join(W, 'logs', `e1-${name}.${snapset}.log`);

// ---- raw snapshot provenance (before the ≈10 GB probe; a mismatch fails fast) ------
const checks = [];
const check = (ok, what, detail = '') => checks.push({ ok: !!ok, what, detail: String(detail) });
const [prov] = await checkSnapProvenance([snap], { indexes: (o.index ?? []).map((x) => path.resolve(x)), allowUnpaired: !!o['allow-unpaired'], check, log: (m) => console.log(`[${WHO}] ${m}`) });
if (!prov.ok && !prov.allowedUnpaired) {
  const result = { lane: 'E1', tool: 'scripts/headless/exact-header.mjs', at: new Date().toISOString(), name, snapset, ok: false, snap, snapProvenance: prov, checks };
  fs.mkdirSync(path.dirname(out), { recursive: true }); fs.writeFileSync(out, JSON.stringify(result, null, 1) + '\n');
  table(['check', 'result', 'detail'], checks.map((c) => [c.what, c.ok ? 'PASS' : 'FAIL', c.detail]));
  console.log(`E1 FAIL ${name}.${snapset} (raw snapshot provenance; probe not run) -> ${out}`); process.exit(1);
}

// ---- run the vendored snapshot-probe ----------------------------------------------
try {
  await requirePairedArtifact(artifact);
  memoryGuard(Number(o['min-free-gb'] ?? 12), WHO);
  acquireLock(`${WHO} ${name}.${snapset}`);
} catch (e) { console.error(`${WHO}: ${e.message}`); process.exit(2); }

const probe = path.join(VENDOR, 'pipeline/snapshot/snapshot-probe.mjs');
const args = ['-l', process.execPath, '--stack-size=8192', probe, '--via-mem', '--artifact', artifact, '--lib', lib,
  '--snap', snap, '--probe-file', exactFile, '--budget-ms', String(budgetMs), '--dump-messages'];
console.log(`[${WHO}] ${name} on ${snapset}: header ${JSON.stringify(hdr.modules)} -> ${JSON.stringify(keyLines)}`);
console.log(`[${WHO}] /usr/bin/time ${args.map((a) => (/\s/.test(a) ? JSON.stringify(a) : a)).join(' ')}`);
console.log(`[${WHO}] log: ${logFile}`);
const t0 = Date.now();
const logFd = fs.openSync(logFile, 'w');
const child = spawn('/usr/bin/time', args, { stdio: ['ignore', logFd, logFd], cwd: SC });
const exitCode = await new Promise((r) => child.on('exit', (c, s) => r(c ?? (s ? 128 : 1))));
fs.closeSync(logFd);
const wallMs = Date.now() - t0;
const log = fs.readFileSync(logFile, 'utf8');

// ---- parse ----------------------------------------------------------------------------
const SEV = { error: 1, warning: 2, information: 3 };
const messages = [];
for (const m of log.matchAll(/^\[lean:stdout\] (\{.*\})$/gm)) {
  try {
    const v = JSON.parse(m[1]);
    messages.push({ severity: v.severity, line: toOriginalLine(v.pos?.line), exactLine: v.pos?.line, column: v.pos?.column,
      endLine: v.endPos ? toOriginalLine(v.endPos.line) : null, message: v.data });
  } catch {}
}
const num = (re) => { const m = re.exec(log); return m ? Number(m[1]) : null; };
const parsed = {
  probeVerdict: /SNAPSHOT PROBE PASS/.test(log) ? 'PASS' : /SNAPSHOT PROBE FAIL/.test(log) ? 'FAIL' : 'NONE',
  probeFailReason: /SNAPSHOT PROBE FAIL: (.*)/.exec(log)?.[1] ?? null,
  abort: /^ABORT: (.*)$/m.exec(log)?.[1] ?? null,
  loadMs: num(/^load: tag=0 scalar=\S+ elapsed=(\d+)ms/m),
  seededKey: /cached env for #\[([^\]]*)\]/.exec(log)?.[1]?.split(',').map((s) => s.trim()) ?? null,
  compileMs: num(/^compile: tag=\d+ elapsed=(\d+)ms/m),
  compileErrorsReported: num(/^compile: tag=\d+ elapsed=\d+ms errors=(\d+)/m),
  maxRssBytes: num(/(\d+)\s+maximum resident set size/),
  peakFootprintBytes: num(/(\d+)\s+peak memory footprint/),
};
const errors = messages.filter((m) => m.severity === 'error');
const warnings = messages.filter((m) => m.severity === 'warning');
const keyModules = keyLines.map((l) => IMPORT_RE.exec(l)[1]);
const expectedKey = ['Init', ...keyModules.filter((m) => m !== 'Init')];

const after = fs.statSync(snap);
check(after.size === prov.bytes && after.mtimeMs === prov.mtimeMs, 'raw snapshot unchanged while the probe read it (size + mtime)', `${after.size} B, mtime ${new Date(after.mtimeMs).toISOString()}`);
check(parsed.loadMs !== null, 'snapshot loaded via _lean_wasm_load_snapshot_mem (tag 0)', parsed.loadMs !== null ? `${parsed.loadMs} ms` : parsed.probeFailReason);
check(parsed.seededKey && JSON.stringify(parsed.seededKey) === JSON.stringify(expectedKey),
  'snapshot seeded exactly the bake key', `seeded #[${parsed.seededKey?.join(', ')}] vs key #[${expectedKey.join(', ')}]`);
check(parsed.compileMs !== null && parsed.compileMs <= budgetMs, `compile within budget (${budgetMs} ms; overrun = re-import = wrong key)`, parsed.compileMs);
check(!parsed.abort, 'no wasm abort', parsed.abort ?? '');
if (!expectFail) {
  check(parsed.probeVerdict === 'PASS' && exitCode === 0, 'snapshot-probe prints SNAPSHOT PROBE PASS (exit 0)', `${parsed.probeVerdict}, exit ${exitCode}`);
  check(errors.length === 0, 'zero error messages', errors.map((e) => `L${e.line}: ${e.message.slice(0, 80)}`).join(' | '));
  if (!o['allow-warnings']) check(warnings.length === 0, 'zero warning messages', warnings.map((e) => `L${e.line}: ${e.message.slice(0, 80)}`).join(' | '));
} else {
  check(parsed.probeVerdict === 'FAIL' && /probe compile failed/.test(parsed.probeFailReason ?? ''), 'negative control: probe FAILs on the compile (not on load/budget)', parsed.probeFailReason);
  check(errors.length > 0, 'negative control: ≥1 error message', errors.map((e) => `L${e.line}: ${e.message.slice(0, 80)}`).join(' | '));
}
const ok = checks.every((c) => c.ok);
const result = {
  lane: 'E1', tool: 'scripts/headless/exact-header.mjs', at: new Date().toISOString(), name, snapset, ok, expect: expectFail ? 'fail' : 'pass',
  example: path.relative(SC, example), exampleSha256: await sha256(original), exactFile, exactSha256: await sha256(exactText),
  header: { original: hdr.modules, key: keyModules, lineDelta: delta },
  runtime: { artifact, buildId: BID }, snap, snapBytes: prov.bytes, snapSha256: prov.sha256, snapProvenance: prov, lib, budgetMs, exitCode, wallMs, log: logFile,
  ...parsed, counts: { error: errors.length, warning: warnings.length, information: messages.length - errors.length - warnings.length },
  messages, checks,
};
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify(result, null, 1) + '\n');

table(['check', 'result', 'detail'], checks.map((c) => [c.what, c.ok ? 'PASS' : 'FAIL', c.detail]));
if (messages.length) table(['sev', 'line', 'message'], messages.map((m) => [m.severity, m.line ?? `hdr(${m.exactLine})`, m.message.replace(/\n/g, ' ⏎ ')]));
console.log(`[${WHO}] load ${parsed.loadMs} ms, compile ${parsed.compileMs} ms, max RSS ${(parsed.maxRssBytes / 1e9).toFixed(2)} GB, peak footprint ${(parsed.peakFootprintBytes / 1e9).toFixed(2)} GB, wall ${wallMs} ms`);
console.log(`E1 ${ok ? 'PASS' : 'FAIL'} ${name}.${snapset} (${checks.filter((c) => c.ok).length}/${checks.length} checks) -> ${out}`);
process.exit(ok ? 0 : 1);
