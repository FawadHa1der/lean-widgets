#!/usr/bin/env node
// ux-tally.mjs — the ONE source of the run tallies the docs quote (README, docs/UX-RESULTS.md, docs/REPIN-LOG.md,
// docs/UPSTREAM-REPORT-QED64.md, gallery/README.md, docs/DEPLOY*.md). Read-only; it recomputes everything from the
// recorded runs, so a doc that disagrees with it is wrong:
//   * every UX run directory out/ux/<run>/ with run-meta.json + report.json (the pin is run-meta.pin.qed64, mapped to
//     the registered pins/<id>/pin.json; a test crashed when its tests/<id>.json records "crashed": true OR one of its
//     session streams tests/<id>.<label>.console.jsonl has a {"kind":"crash"} line, i.e. the renderer died:
//     Playwright's page 'crash' event. The stream is needed because that event can arrive after the test already
//     failed on the dead page (Playwright's own "Assertion error") and after the fixture computed the session's console
//     verdict, so tests/<id>.json then says "crashed": false: r2-main-full1 and r4-main-full2, both C10),
//   * tests/C20.json of each run (clean links, card stalls, gallery wedges, QED64's own liveness counters),
//   * out/ux/showcase-ux-runs.jsonl, judged by scripts/lib/ux-record.mjs whyNotVerdict (the VERDICT rule),
//   * the stock-page reload storms tests/ux/tools/reload-storm.mjs wrote (out/ux/{repin-ab,multipin-storm}/explore/),
//   * the desktop-Chrome storm lane's own generated table (out/ux/l9-desktop/RESULTS.md, built from its run files),
//   * the final-gate lane's interleaved storms (out/ux/final-storm/explore: tests/ux/tools/reload-storm-desktop.mjs, tags
//     <round>-<pin letter>-<hs|hd>-<st|sc>; the variant from the browser stderr in stdout-<tag>.log: V1 'semi-space copy',
//     V2 'young object promotion failed'; quiet/loaded from host-state.tsv as tabulated in storm-table.json).
// Usage: node scripts/ux-tally.mjs [--json]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readRuns, whyNotVerdict } from './lib/ux-record.mjs';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const UX = path.join(SC, 'out', 'ux');
const readJson = (f) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return null; } };

// pins: id -> letter (from the descriptor's label "A: …")
const PINS = {};
for (const id of fs.existsSync(path.join(SC, 'pins')) ? fs.readdirSync(path.join(SC, 'pins')) : []) {
  const p = readJson(path.join(SC, 'pins', id, 'pin.json'));
  if (p && p.id) PINS[p.id] = { id: p.id, letter: (String(p.label || '').match(/^([A-Z]):/) || [])[1] || p.id, buildId: p.buildId };
}
const BY_LETTER = Object.fromEntries(Object.values(PINS).map((p) => [p.letter, p.id]));
const pinName = (id) => (PINS[id] ? `${PINS[id].letter} ${id}` : String(id));

// ---------------------------------------------------------------- UX run directories
function testsOf(rep) {
  const out = [];
  const walk = (s) => { for (const sp of s.specs || []) for (const t of sp.tests || []) { const r = (t.results || [])[t.results.length - 1] || {}; out.push({ id: sp.title.split(' ')[0], status: r.status || t.status, expected: t.expectedStatus }); } for (const c of s.suites || []) walk(c); };
  for (const s of rep.suites || []) walk(s);
  return out;
}
const runs = [];
for (const d of fs.readdirSync(UX)) {
  const dir = path.join(UX, d);
  if (!fs.statSync(dir).isDirectory()) continue;
  const meta = readJson(path.join(dir, 'run-meta.json')); const rep = readJson(path.join(dir, 'report.json'));
  if (!meta || !rep || !meta.pin || !meta.pin.qed64) continue;
  const pin = String(meta.pin.qed64).slice(0, 7);
  const tests = testsOf(rep);
  const crashed = [];
  const tdir = path.join(dir, 'tests'); const tfiles = fs.existsSync(tdir) ? fs.readdirSync(tdir) : [];
  for (const t of tests) {
    const f = path.join(tdir, `${t.id}.json`);
    const recorded = fs.existsSync(f) && /"crashed":\s*true/.test(fs.readFileSync(f, 'utf8'));
    const streamed = tfiles.some((n) => n.startsWith(`${t.id}.`) && n.endsWith('.console.jsonl') && /"kind":"crash"/.test(fs.readFileSync(path.join(tdir, n), 'utf8')));
    if (recorded || streamed) crashed.push(t.id);
  }
  const res = (id) => { const t = tests.find((x) => x.id === id); if (!t) return null; if (crashed.includes(id)) return 'crashed'; return t.status === 'passed' ? 'passed' : t.status; };
  const c20 = readJson(path.join(dir, 'tests', 'C20.json'));
  const st = rep.stats || {};
  runs.push({
    run: d, start: meta.startedAt, pin, listed: tests.length, full: tests.length >= 30,
    passed: st.expected, failed: st.unexpected, skipped: st.skipped, flaky: st.flaky,
    failedIds: tests.filter((t) => t.status !== 'passed' && t.status !== 'skipped').map((t) => t.id), crashed,
    C10: res('C10'), C21: res('C21'), W4: res('W4'),
    C20: c20 && typeof c20.total === 'number' && !c20.recordOnly ? {
      clean: c20.clean ?? Object.values(c20.packages || {}).reduce((n, p) => n + (p.ok || 0), 0), total: c20.total,
      stalls: c20.stalls ?? 0, wedges: c20.livenessWedged ?? 0, restarts: c20.livenessRestarts ?? 0,
      rescues: c20.qed64Liveness ? c20.qed64Liveness.rescues : null, wedgedReboots: c20.qed64Liveness ? c20.qed64Liveness.wedgedReboots : null,
      status: res('C20'), testStatus: c20.testStatus || c20.status || null,
    } : null,
  });
}
runs.sort((a, b) => String(a.start).localeCompare(String(b.start)));

// ---------------------------------------------------------------- verdicts (showcase.sh ux records)
const recs = readRuns();
const verdicts = recs.filter((x) => whyNotVerdict(x).length === 0).map((x) => ({ run: x.run, start: x.start, end: x.end, pin: x.pin ? x.pin.split(' ')[0] : null, gallery: x.galleryEnd, lock: x.lockSha256 }));
const fullRecs = recs.filter((x) => !(x.args || []).length && !x.uxOrigin).map((x) => ({ run: x.run, start: x.start, rc: x.rc, pin: x.pin ? x.pin.split(' ')[0] : null, gallery: x.galleryEnd, why: whyNotVerdict(x) }));

// ---------------------------------------------------------------- reload storms (stock page, chrome-headless-shell)
const STORM_SETS = [
  { dir: 'repin-ab', letterOf: (tag) => ({ old: 'A', new: 'B' })[tag.replace(/\d+$/, '')] },
  { dir: 'multipin-storm', letterOf: (tag) => tag.split('-')[0] },
];
const storms = [];
for (const s of STORM_SETS) {
  const ex = path.join(UX, s.dir, 'explore');
  if (!fs.existsSync(ex)) continue;
  for (const f of fs.readdirSync(ex).filter((x) => /^reload-storm-.*\.json$/.test(x)).sort()) {
    const j = readJson(path.join(ex, f)); if (!j) continue;
    storms.push({ set: s.dir, tag: j.tag, pin: BY_LETTER[s.letterOf(j.tag)] || null, start: j.startedAt, crashed: j.crashedAtMs != null, pool: j.atFirstReady && j.atFirstReady.status && j.atFirstReady.status.pool });
  }
}

// ---------------------------------------------------------------- per pin
const by = (xs, k) => xs.reduce((m, x) => ((m[x[k]] = m[x[k]] || []).push(x), m), {});
const perPin = {};
for (const [pin, rs] of Object.entries(by(runs, 'pin'))) {
  const full = rs.filter((r) => r.full && r.passed + r.failed > 0);
  const c10 = rs.filter((r) => r.C10 && r.C10 !== 'skipped');
  const c20 = rs.filter((r) => r.C20 && r.C20.status && r.C20.status !== 'skipped');
  const c21 = rs.filter((r) => r.C21 && r.C21 !== 'skipped');
  perPin[pin] = {
    fullRuns: full.map((r) => ({ run: r.run, start: r.start, passed: r.passed, failed: r.failed, skipped: r.skipped, failedIds: r.failedIds, crashed: r.crashed })),
    C10: { runs: c10.length, full: c10.filter((r) => r.full).length, crashed: c10.filter((r) => r.C10 === 'crashed').map((r) => r.run), passed: c10.filter((r) => r.C10 === 'passed').map((r) => r.run), other: c10.filter((r) => !['crashed', 'passed'].includes(r.C10)).map((r) => `${r.run}:${r.C10}`) },
    C21: { runs: c21.length, crashed: c21.filter((r) => r.C21 === 'crashed').map((r) => r.run) },
    W4crashed: rs.filter((r) => r.W4 === 'crashed').map((r) => r.run), W4runs: rs.filter((r) => r.W4 && r.W4 !== 'skipped').length,
    C20: {
      runs: c20.length, clean135: c20.filter((r) => r.C20.clean === r.C20.total).length,
      notClean: c20.filter((r) => r.C20.clean !== r.C20.total).map((r) => `${r.run}:${r.C20.clean}/${r.C20.total}${r.C20.testStatus ? ` ${r.C20.testStatus}` : ''}`),
      clicks: c20.reduce((n, r) => n + r.C20.clean, 0), stalls: c20.reduce((n, r) => n + (r.C20.stalls || 0), 0),
      galleryWedges: c20.reduce((n, r) => n + (r.C20.wedges || 0), 0),
      qed64Rescues: c20.every((r) => r.C20.rescues == null) ? null : c20.reduce((n, r) => n + (r.C20.rescues || 0), 0),
      qed64WedgedReboots: c20.every((r) => r.C20.wedgedReboots == null) ? null : c20.reduce((n, r) => n + (r.C20.wedgedReboots || 0), 0),
      qed64Recorded: c20.filter((r) => r.C20.rescues != null).length, // runs whose C20.json records QED64's liveness counters
      list: c20.map((r) => r.run),
    },
    storms: (() => { const ss = storms.filter((s) => s.pin === pin); return { runs: ss.length, crashed: ss.filter((s) => s.crashed).map((s) => `${s.set}/${s.tag}`), tags: ss.map((s) => `${s.set}/${s.tag}`) }; })(),
  };
}
// the desktop lane's table (it computed it from its own run files; quoted, not recomputed here)
let desktop = null;
const l9 = path.join(UX, 'l9-desktop', 'RESULTS.md');
if (fs.existsSync(l9)) {
  const rows = [...fs.readFileSync(l9, 'utf8').matchAll(/^\| ([ABC]) \| ([^|]+?) \|.*\| \*\*(\d+)\/(\d+)\*\* \| ([^|]*) \|$/gm)];
  desktop = rows.map((m) => ({ pin: BY_LETTER[m[1]], browser: m[2].trim(), crashed: +m[3], runs: +m[4], crashedRuns: m[5].trim() }));
}

// the final-gate interleaved storms (recomputed from the run files)
const finalStorms = [];
const fsx = path.join(UX, 'final-storm', 'explore');
if (fs.existsSync(fsx)) {
  for (const f of fs.readdirSync(fsx).filter((x) => /^reload-storm-[rq]\d+-[A-D]-(hs|hd)-(st|sc)\.json$/.test(x)).sort()) {
    const j = readJson(path.join(fsx, f)); if (!j) continue;
    const [, set, letter, mode, entry] = /^([rq]\d+)-([A-D])-(hs|hd)-(st|sc)$/.exec(j.tag);
    let log = ''; try { log = fs.readFileSync(path.join(fsx, `stdout-${j.tag}.log`), 'utf8'); } catch { /* none */ }
    const crashed = j.crashedAtMs != null;
    const variant = !crashed ? null : /semi-space copy/.test(log) ? 'V1' : /young object promotion failed/.test(log) ? 'V2' : 'other';
    finalStorms.push({ tag: j.tag, quietRound: set[0] === 'q', pin: BY_LETTER[letter], mode: mode === 'hd' ? 'headed' : 'headless-shell', entry: entry === 'st' ? 'stock' : 'showcase', crashed, variant });
  }
}
const out = { generatedAt: new Date().toISOString(), pins: PINS, verdicts, fullRecords: fullRecs, perPin, desktopStorms: desktop, finalStorms };
if (process.argv.includes('--json')) { console.log(JSON.stringify(out, null, 1)); process.exit(0); }

const L = (s = '') => console.log(s);
L(`UX TALLY (node scripts/ux-tally.mjs; ${runs.length} run directories with a report, ${recs.length} showcase.sh ux records, ${storms.length} stock reload storms)`);
L('');
L('VERDICT runs (showcase-ux-runs.jsonl, ux-record whyNotVerdict):');
for (const v of verdicts) L(`  ${v.run.padEnd(22)} ${v.start} – ${v.end}  pin ${v.pin ? pinName(v.pin) : '(before pins: lock ' + String(v.lock).slice(0, 8) + ')'}  gallery ${String(v.gallery).slice(0, 8)}…`);
L('');
L('Full-suite records that were NOT a verdict:');
for (const f of fullRecs.filter((x) => x.why.length)) L(`  ${f.run.padEnd(22)} ${f.start}  rc ${f.rc}  ${f.pin ? pinName(f.pin) : ''}  ${f.why.join('; ').slice(0, 150)}`);
for (const pin of Object.keys(perPin).sort((a, b) => (PINS[a] ? PINS[a].letter : a).localeCompare(PINS[b] ? PINS[b].letter : b))) {
  const p = perPin[pin];
  L('');
  L(`== pin ${pinName(pin)} (${PINS[pin] ? PINS[pin].buildId : '?'})`);
  L(`  full runs: ${p.fullRuns.length}`);
  for (const r of p.fullRuns) L(`    ${r.run.padEnd(22)} ${String(r.start).slice(0, 16)}Z  ${r.passed} passed, ${r.failed} failed, ${r.skipped} skipped${r.failedIds.length ? `  failed: ${r.failedIds.join(' ')}` : ''}${r.crashed.length ? `  RENDERER CRASH in ${r.crashed.join(' ')}` : ''}`);
  L(`  C10 (reload storm in the suite): ran in ${p.C10.runs} runs (${p.C10.full} full); crashed ${p.C10.crashed.length}${p.C10.crashed.length ? ` (${p.C10.crashed.join(', ')})` : ''}; passed ${p.C10.passed.length}${p.C10.other.length ? `; other ${p.C10.other.join(', ')}` : ''}`);
  L(`  C21: ran in ${p.C21.runs} runs; crashed ${p.C21.crashed.length}${p.C21.crashed.length ? ` (${p.C21.crashed.join(', ')})` : ''}`);
  L(`  W4: ran in ${p.W4runs} runs; crashed ${p.W4crashed.length}${p.W4crashed.length ? ` (${p.W4crashed.join(', ')})` : ''}`);
  L(`  C20: ${p.C20.runs} runs, ${p.C20.clean135} at 135/135${p.C20.notClean.length ? `; not clean: ${p.C20.notClean.join(', ')}` : ''}; ${p.C20.clicks} clean link clicks; card stalls ${p.C20.stalls}; gallery wedges ${p.C20.galleryWedges}; QED64 rescues ${p.C20.qed64Rescues ?? 'n/a (no QED64 liveness)'}, wedged reboots ${p.C20.qed64WedgedReboots ?? 'n/a'}${p.C20.qed64Rescues != null ? ` (recorded in ${p.C20.qed64Recorded} of ${p.C20.runs} runs)` : ''}`);
  L(`  stock reload storms (chrome-headless-shell): ${p.storms.runs} runs, crashed ${p.storms.crashed.length}${p.storms.crashed.length ? ` (${p.storms.crashed.join(', ')})` : ''}`);
}
if (desktop) {
  L('');
  L('Desktop-Chrome reload storms (out/ux/l9-desktop/RESULTS.md, generated by that lane from its run files):');
  for (const d of desktop) L(`  ${pinName(d.pin).padEnd(10)} ${d.browser.padEnd(16)} ${d.crashed}/${d.runs}${d.crashedRuns && d.crashedRuns !== '–' ? `  (${d.crashedRuns})` : ''}`);
}
if (finalStorms.length) {
  L('');
  L('Final-gate interleaved reload storms (out/ux/final-storm; normal rounds + the quiet round, both entries):');
  const keyOf = (s) => `${pinName(s.pin).padEnd(10)} ${s.mode.padEnd(15)} ${s.entry.padEnd(9)}${s.quietRound ? ' quiet round' : ''}`;
  const g = {}; for (const s of finalStorms) (g[keyOf(s)] ||= []).push(s);
  for (const k of Object.keys(g).sort()) { const ss = g[k]; const c = ss.filter((s) => s.crashed); L(`  ${k.padEnd(48)} ${c.length}/${ss.length}${c.length ? `  (${c.map((s) => `${s.tag} ${s.variant}`).join(', ')})` : ''}`); }
}
