#!/usr/bin/env node
// judge-bake.mjs — BUILD-PLAN §5 C5 (+ §9 range for w8). bake-snapshot never fails on elaboration errors
// (bake-snapshot.mjs:122-133; Frontend.lean:410-416), so the bake is judged here. Requires ALL of:
//   J1 the bake log has no line matching  : error|PANIC|ABORT:|uncaught|RuntimeError|object compactor:
//   J2 "Loading N modules" with N == EXPECTED-N (from stage-trees.mjs) and an "N/N:" progress line
//   J3 a "baked …/widgets.<d16>.snapz (…) … runtime <the active pin's buildId>" line, and the bake exited 0
//   J4 raw bytes of <work>/widgets.snap == stock region + k x (.olean bytes of delta+own), k in [0.6, 1.2];
//      the plan's estimate range (w7 [1.13, 1.30] GB, w8 [1.35, 1.75] GB) is reported as INFO/WARN
//   J5 <out>/index.json: exactly {init (verbatim served entry), widgets}; widgets.bytes == raw size,
//      widgets.imports == BAKE-KEY lines, widgets.runtime == BID, widgets.url names an existing .snapz
//
//   node scripts/judge-bake.mjs w7|w8        exit 0 = GREEN
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { W } = await import(path.join(SC, 'scripts/lib/env.mjs')); // the work dir (QED64_SHOWCASE_WORK)
const { targetPinId, targetBuildId, releaseOf, storePath } = await import(path.join(SC, 'scripts/lib/pins.mjs'));
// the TARGET pin (SHOWCASE_PIN=<id>, else the active pin; scripts/lib/pins.mjs): its runtime, release and bake stores
const PIN = targetPinId();
const BID = targetBuildId();
const RELEASE = releaseOf(PIN);
const tag = process.argv[2];
const RANGE = { w7: [1.13e9, 1.30e9], w8: [1.35e9, 1.75e9] };
if (!RANGE[tag]) { console.error('usage: judge-bake.mjs w7|w8'); process.exit(2); }
const n = tag.slice(1);
const BL = storePath('bake-logs');
const log = fs.readFileSync(path.join(BL, `bake-widgets${n}.log`), 'utf8');
const expectedN = Number(fs.readFileSync(path.join(W, `tree-slim-${tag}.EXPECTED-N`), 'utf8').trim());
const key = fs.readFileSync(storePath(`BAKE-KEY-${tag}.txt`), 'utf8').split('\n').filter(Boolean).map((l) => l.replace(/^import\s+/, ''));
const work = storePath(`bake-work-${tag}`), out = storePath(`bake-out-${tag}`);
console.log(`     pin ${PIN}, runtime ${BID}: ${out}`);
let fails = 0;
const ok = (c, msg, d = '') => { console.log(`${c ? 'OK  ' : 'FAIL'} ${msg}${d ? ' — ' + d : ''}`); if (!c) fails++; };

// only the LAST attempt counts (bake.sh may rebake with a larger reserve)
// attempts start at bake.sh's "=== bake <tag> reserve=…" marker (the closing marker is "=== bake <tag> exit=…")
const starts = [...log.matchAll(/^=== bake \S+ reserve=/gm)].map((m) => m.index);
const last = starts.length ? log.slice(starts[starts.length - 1]) : log;
if (!starts.length) console.log('     (no bake.sh attempt marker; judging the whole log)');
const bad = last.split('\n').map((l, i) => [i + 1, l]).filter(([, l]) => /: error|PANIC|ABORT:|uncaught|RuntimeError|object compactor:/.test(l));
ok(!bad.length, 'J1 no error/PANIC/ABORT/uncaught/RuntimeError/compactor line in the bake log', bad.slice(0, 3).map(([i, l]) => `${i}: ${l.slice(0, 160)}`).join(' | '));
const loading = [...last.matchAll(/Loading (\d+) modules/g)].map((m) => Number(m[1]));
const N = loading[loading.length - 1];
ok(loading.length === 1 && N === expectedN, `J2 "Loading N modules" N=${N} == EXPECTED-N ${expectedN}`, `${loading.length} Loading line(s)`);
const done = new RegExp(`\\b${N}/${N}: (\\S+)`).exec(last);
ok(!!done, `J2 progress reached ${N}/${N}`, done ? `last module ${done[1]}` : 'no N/N line');
const baked = /^baked (\S+\/widgets\.([0-9a-f]{16})\.snapz) \((\d+) bytes transfer, (\d+) raw\); index updated \(imports: \[([^\]]*)\], runtime (\S+)\)/m.exec(last);
ok(!!baked && baked[6] === BID, `J3 baked widgets.<d16>.snapz line with runtime ${BID}`, baked ? `${path.basename(baked[1])} transfer ${baked[3]} raw ${baked[4]}` : 'no baked line');
const exit = /=== bake \S+ exit=(\d+)/.exec(last);
ok(exit && exit[1] === '0', 'J3 bake process exited 0', exit ? `exit=${exit[1]}` : 'no exit line');

const raw = path.join(work, 'widgets.snap');
const rawBytes = fs.existsSync(raw) ? fs.statSync(raw).size : -1;
// J4 is derived from what was staged: the region grows by k x (.olean bytes of the delta + own modules)
// over the stock region (1,127,272,685 bytes; same base tree, same probe prefix). Observed k: 0.81 (w7),
// 0.83 (w8); the stock region itself is 1.164 x its tree's .olean bytes. Accepting k in [0.6, 1.2]
// catches a region that silently lost or duplicated the delta. The plan's pre-bake estimate range
// (BUILD-PLAN §5 C5 / §9) is printed alongside; for w8 it was an over-estimate (WARN, not a gate).
// (the stock size comes from the pinned release's index: 1,127,272,685 B for both the 0034 and the 0035 runtime)
const STOCK = JSON.parse(fs.readFileSync(path.join(RELEASE, 'public/snapshots/index.json'), 'utf8')).snapshots.find((s) => s.name === 'mathlib').bytes;
const st = JSON.parse(fs.readFileSync(path.join(W, `logs/stage-trees-${tag}.json`), 'utf8'));
const tree = path.join(W, `tree-slim-${tag}`);
const dOlean = [...st.delta.dep, ...st.delta.core, ...st.own].reduce((a, m) => a + fs.statSync(path.join(tree, ...m.split('.')) + '.olean').size, 0);
const k = (rawBytes - STOCK) / dOlean;
ok(k >= 0.6 && k <= 1.2, `J4 raw bytes ${rawBytes} = stock ${STOCK} + k x delta .olean bytes ${dOlean}, k=${k.toFixed(3)} in [0.6, 1.2]`, `${(rawBytes / 1e9).toFixed(3)} GB; +${((rawBytes - STOCK) / 1e6).toFixed(1)} MB`);
const [lo, hi] = RANGE[tag];
console.log(`${rawBytes >= lo && rawBytes <= hi ? 'INFO' : 'WARN'} plan estimate range [${lo / 1e9}, ${hi / 1e9}] GB ${rawBytes >= lo && rawBytes <= hi ? 'holds' : 'MISSED'} (raw ${(rawBytes / 1e9).toFixed(3)} GB)`);

const idx = JSON.parse(fs.readFileSync(path.join(out, 'index.json'), 'utf8'));
const served = JSON.parse(fs.readFileSync(path.join(RELEASE, 'public/snapshots/index.json'), 'utf8'));
const sInit = served.snapshots.find((s) => s.name === 'init');
const init = idx.snapshots.find((s) => s.name === 'init'), wg = idx.snapshots.find((s) => s.name === 'widgets');
ok(idx.schema === 'qed64.snapshot-index/v1' && idx.snapshots.length === 2 && init && wg, 'J5 index.json holds exactly {init, widgets}', idx.snapshots.map((s) => s.name).join(','));
ok(JSON.stringify(init) === JSON.stringify(sInit), 'J5 init entry is the served entry verbatim', init?.url);
ok(wg && wg.bytes === rawBytes && wg.runtime === BID, `J5 widgets.bytes == raw size, runtime == ${BID}`, wg && `${wg.bytes} ${wg.runtime}`);
ok(wg && JSON.stringify(wg.imports) === JSON.stringify(key), 'J5 widgets.imports == BAKE-KEY', wg && wg.imports.join(','));
ok(wg && fs.existsSync(path.join(out, path.basename(wg.url))) && baked && wg.url.endsWith(path.basename(baked[1])), 'J5 widgets.url names the baked .snapz present in out/', wg?.url);

const metrics = (() => { try { return JSON.parse(fs.readFileSync(path.join(BL, `bake-widgets${n}.metrics.json`), 'utf8')); } catch { return null; } })();
if (metrics) console.log(`     metrics: wall ${metrics.wallSeconds}s, peak tree RSS ${(metrics.peakTreeRssKiB / 1048576).toFixed(2)} GiB, reserve ${(metrics.reserve / 2 ** 30).toFixed(1)} GiB, attempts ${metrics.attempts}`);
console.log(fails ? `JUDGE ${tag}: RED (${fails} FAIL)` : `JUDGE ${tag}: GREEN N=${N} raw=${rawBytes} ${wg.url}`);
process.exit(fails ? 1 : 0);
