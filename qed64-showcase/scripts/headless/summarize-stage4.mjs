#!/usr/bin/env node
// Collect stage-4 results (E1, E2, E3, E3b) into out/headless/summary.json and print
// markdown tables for docs/HEADLESS-RESULTS.md. Reads only the JSON outputs of the tools and
// the E2 TSV written by run-e2.sh; it judges nothing new except aggregating the tools' own ok.
//   node scripts/headless/summarize-stage4.mjs [--out out/headless/summary.json]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { targetBuildId, targetPinId, storePath } from '../lib/pins.mjs';
// the TARGET pin (SHOWCASE_PIN=<id>, else the active pin; scripts/lib/pins.mjs) and its runtime's headless store
// (out/headless, the active link, or out/runtimes/<bid>/headless)
const BID = targetBuildId(), PIN = targetPinId(), HOUT = storePath('headless');

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const { W } = await import(path.join(SC, 'scripts/lib/env.mjs')); // the work dir (QED64_SHOWCASE_WORK)
const OUT = process.argv.includes('--out') ? process.argv[process.argv.indexOf('--out') + 1] : path.join(HOUT, 'summary.json');
const PK8 = ['chart-kit', 'expr-xray', 'graph-scope', 'hasse-view', 'interval-inspector', 'simp-lens', 'tree-scope', 'dist-lens'];
const BAKES = { w8: { snapset: 'widgets8', pkgs: PK8 }, w7: { snapset: 'widgets7', pkgs: PK8.slice(0, 7) } };
const rd = (f) => (fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : null);
const stats = (xs) => {
  const v = xs.filter((x) => typeof x === 'number').sort((a, b) => a - b);
  if (!v.length) return null;
  const q = (p) => v[Math.min(v.length - 1, Math.floor(p * (v.length - 1) + 0.5))];
  return { n: v.length, min: v[0], median: q(0.5), p90: q(0.9), max: v[v.length - 1] };
};
const gb = (b) => (b ? +(b / 1e9).toFixed(2) : null);

const summary = { generatedAt: new Date().toISOString(), tool: 'scripts/headless/summarize-stage4.mjs', runtime: BID, pin: PIN, bakes: {}, e2: null, gate: {} };
for (const [bake, { snapset, pkgs }] of Object.entries(BAKES)) {
  const rows = [];
  for (const p of pkgs) {
    const e1 = rd(path.join(HOUT, `${p}.${snapset}.e1.json`));
    const e3 = rd(path.join(HOUT, `${p}.${snapset}.rpc.json`));
    const rb = rd(path.join(HOUT, `${p}.${snapset}.react.json`));
    const pc = e3?.checks ?? [], cc = e3?.comparison?.checks ?? [];
    const curMs = (e3?.cursors ?? []).map((c) => c.cursorMs);
    const rpcMs = (e3?.cursors ?? []).flatMap((c) => c.panels.filter((x) => x.kind === 'rpc').map((x) => x.rpcMs));
    const gwMs = (e3?.cursors ?? []).map((c) => c.getWidgetsMs);
    const clicks = e3?.clicks ?? [];
    rows.push({
      pkg: p,
      e1: e1 && { ok: e1.ok, checks: `${e1.checks.filter((c) => c.ok).length}/${e1.checks.length}`, loadMs: e1.loadMs, compileMs: e1.compileMs,
        budgetMs: e1.budgetMs, seededKey: e1.seededKey, errors: e1.counts?.error ?? null, warnings: e1.counts?.warning ?? null,
        maxRssGB: gb(e1.maxRssBytes), peakFootprintGB: gb(e1.peakFootprintBytes), snapSha256: e1.snapSha256 },
      e3: e3 && { ok: e3.ok, probeChecks: `${pc.filter((c) => c.ok).length}/${pc.length}`, goldenChecks: `${cc.filter((c) => c.ok).length}/${cc.length}`,
        allChecks: `${pc.filter((c) => c.ok).length + cc.filter((c) => c.ok).length}/${pc.length + cc.length}`,
        failed: [...pc, ...cc].filter((c) => !c.ok).map((c) => `${c.what}: ${c.detail}`.slice(0, 300)),
        golden: e3.comparison?.golden ?? null, goldenHtml: e3.comparison?.goldenHtml ?? null, header: e3.headerStatus && { mode: e3.headerStatus.mode, key: e3.headerStatus.key, moduleCount: e3.headerStatus.moduleCount, missing: e3.headerStatus.missing },
        elaborationMs: e3.elaborationMs, cursors: (e3.cursors ?? []).length,
        panels: (e3.cursors ?? []).reduce((n, c) => n + c.panels.length, 0) + (e3.selections ?? []).reduce((n, s) => n + (s.panels?.length ?? 0), 0),
        selections: (e3.selections ?? []).length, hovers: (e3.hovers ?? []).length,
        clicks: clicks.length, clicksClean: clicks.filter((k) => k.verdict?.ok).length,
        clickDetail: clicks.map((k) => ({ kind: k.kind, link: k.linkTitle ?? k.linkText, reElaborationMs: k.reElaborationMs, settledMs: k.settledMs ?? null, verdict: k.verdict?.ok ? ('problems' in k.verdict ? 'clean' : 'designed-diagnostics-matched') : 'FAIL' })),
        codeActions: (e3.codeActions ?? []).length, codeActionMs: stats((e3.codeActions ?? []).map((c) => c.codeActionMs)),
        cursorMs: stats(curMs), getWidgetsMs: stats(gwMs), panelRpcMs: stats(rpcMs), reElaborationMs: stats(clicks.map((k) => k.reElaborationMs)), clickSettledMs: stats(clicks.map((k) => k.settledMs)), elaborationSettledMs: e3.elaborationSettledMs ?? null,
        maxRssGB: gb(e3.run?.maxRssBytes), totalMs: e3.totalMs },
      e3b: rb && { ok: rb.ok, panelsClean: `${rb.panels - rb.failed}/${rb.panels}`, failed: rb.failed },
      ok: !!(e1?.ok && e3?.ok && rb?.ok && rb.panels > 0),
    });
  }
  summary.bakes[bake] = { snapset, packages: rows };
}
// E2: run-e2.sh writes one TSV per runtime ($W/logs/s4-e2.<buildId>.tsv, since the pin D lane); rows of earlier runs
// are in the shared $W/logs/s4-e2.tsv, which has no runtime column, so it is read only when no per-runtime TSV exists
const tsvRt = path.join(W, `logs/s4-e2.${BID}.tsv`);
const tsv = fs.existsSync(tsvRt) ? tsvRt : path.join(W, 'logs/s4-e2.tsv');
summary.e2Tsv = tsv;
if (fs.existsSync(tsv)) {
  const [hdr, ...lines] = fs.readFileSync(tsv, 'utf8').trim().split('\n').map((l) => l.split('\t'));
  const last = new Map();
  for (const l of lines) { const o = Object.fromEntries(hdr.map((h, i) => [h, l[i]])); last.set(o.pkg, o); }
  summary.e2 = PK8.map((p) => { const o = last.get(p); if (!o) return { pkg: p, ran: false };
    // Demo.olean mtime - step start = runner boot + import + elaboration (wall also holds supervised-run's quiet/stable windows)
    const ol = path.join(W, 'run', p, 'Demo.olean');
    const startMs = Date.parse(o.when) - 1000 * +o.wall_s;
    const oleanAtS = fs.existsSync(ol) ? Math.round((fs.statSync(ol).mtimeMs - startMs) / 1000) : null;
    return { pkg: p, ran: true, ok: o.rc === '0' && o.warnings === '0' && +o.olean_bytes > 0, rc: +o.rc, verdict: o.verdict, wallS: +o.wall_s, oleanWrittenAfterS: oleanAtS,
      maxRssGB: gb(+o.maxrss_bytes), supervisorPeakFootprintGB: gb(+o.peak_footprint_bytes), warnings: +o.warnings, oleanBytes: +o.olean_bytes, demoSha256: o.demo_sha256, log: o.log, at: o.when }; });
}
const lim = rd(path.join(SC, 'scripts/headless/known-limitations.json'))?.limitations ?? [];
for (const r of summary.e2 ?? []) {
  if (!r.ran || r.ok) continue;
  const l = lim.find((x) => x.lane === 'E2' && x.pkg === r.pkg && r.verdict.includes(x.match));
  r.rootCaused = l ? l.id : null;
}
summary.knownLimitations = lim;
const w8 = summary.bakes.w8.packages, w7 = summary.bakes.w7.packages;
summary.gate = {
  E1: { w8: `${w8.filter((r) => r.e1?.ok).length}/${w8.length}`, w7: `${w7.filter((r) => r.e1?.ok).length}/${w7.length}` },
  E3: { w8: `${w8.filter((r) => r.e3?.ok).length}/${w8.length}`, w7: `${w7.filter((r) => r.e3?.ok).length}/${w7.length}` },
  E3b: { w8: `${w8.filter((r) => r.e3b?.ok).length}/${w8.length}`, w7: `${w7.filter((r) => r.e3b?.ok).length}/${w7.length}` },
  E2: summary.e2 ? `${summary.e2.filter((r) => r.ok).length}/${summary.e2.length} clean` : 'not run',
  E2rootCaused: summary.e2 ? summary.e2.filter((r) => r.rootCaused).map((r) => `${r.pkg}: ${r.rootCaused}`) : [],
};
summary.gate.E2Green = !!summary.e2 && summary.e2.every((r) => r.ran && (r.ok || r.rootCaused));
summary.gate.stage4Green = [...w8, ...w7].every((r) => r.ok);
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(summary, null, 1) + '\n');

// markdown
const md = [];
const s = (x) => (x ? `${x.median} / ${x.max}` : '–');
for (const [bake, { packages }] of Object.entries(summary.bakes)) {
  md.push(`\n### ${bake} (${summary.bakes[bake].snapset})\n`);
  md.push('| package | E1 | E1 load / compile ms | E3 checks (probe + golden) | header | open→settled ms | cursors / panels | cursor ms (median / max) | panel RPC ms (median / max) | clicks clean | click settle ms (median / max) | code actions | E3b panels clean | max RSS GB (E1 / E3) |');
  md.push('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|');
  for (const r of packages) {
    const e1 = r.e1, e3 = r.e3, rb = r.e3b;
    md.push(`| ${r.pkg} | ${e1 ? `${e1.ok ? 'PASS' : 'FAIL'} ${e1.checks}` : '–'} | ${e1 ? `${e1.loadMs} / ${e1.compileMs}` : '–'} | ${e3 ? `${e3.ok ? 'PASS' : 'FAIL'} ${e3.allChecks} (${e3.probeChecks} + ${e3.goldenChecks})` : '–'} | ${e3?.header ? `${e3.header.mode}, ${e3.header.moduleCount}` : '–'} | ${e3?.elaborationSettledMs ?? '–'} | ${e3 ? `${e3.cursors} / ${e3.panels}` : '–'} | ${s(e3?.cursorMs)} | ${s(e3?.panelRpcMs)} | ${e3 ? `${e3.clicksClean}/${e3.clicks}` : '–'} | ${s(e3?.clickSettledMs)} | ${e3?.codeActions ?? '–'} | ${rb ? `${rb.ok ? 'PASS' : 'FAIL'} ${rb.panelsClean}` : '–'} | ${e1?.maxRssGB ?? '–'} / ${e3?.maxRssGB ?? '–'} |`);
  }
}
if (summary.e2) {
  md.push('\n### E2 (Demo.lean verbatim, tree-fat)\n');
  md.push('| package | result | Demo.olean written after s (boot + import + elab) | wall s (incl. 60 s quiet / 30 s stable windows) | max RSS GB (child, via wait4) | warnings | Demo.olean bytes | supervised-run verdict |');
  md.push('|---|---|---|---|---|---|---|---|');
  for (const r of summary.e2) md.push(r.ran ? `| ${r.pkg} | ${r.ok ? 'PASS' : r.rootCaused ? `FAIL (${r.rootCaused})` : 'FAIL'} | ${r.oleanWrittenAfterS ?? '–'} | ${r.wallS} | ${r.maxRssGB} | ${r.warnings} | ${r.oleanBytes} | ${r.verdict.replace(/\|/g, '\\|').slice(0, 140)} |` : `| ${r.pkg} | not run | | | | | | |`);
}
console.log(md.join('\n'));
console.log(`\nGATE ${JSON.stringify(summary.gate)}`);
console.log(`-> ${path.relative(SC, OUT)}`);
