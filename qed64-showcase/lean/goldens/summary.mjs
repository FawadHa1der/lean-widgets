#!/usr/bin/env node
// Summary table over lean/expect/<pkg>.json (superset goldens, env w8: the one env since P2, 2026-11), the
// closure-mode sensitivity runs in $W/goldens/<pkg>.closure.json and the click-all runs
// (lean/expect/click-all/<pkg>.json, summarised into lean/expect/click-all/summary.json).
import fs from 'node:fs';
import path from 'node:path';

const SC = path.resolve(import.meta.dirname, '..', '..');
const { W } = await import(path.join(SC, 'scripts/lib/env.mjs')); // the work dir (QED64_SHOWCASE_WORK)
const PKGS = ['chart-kit', 'expr-xray', 'simp-lens', 'interval-inspector', 'graph-scope', 'tree-scope', 'hasse-view', 'dist-lens'];
const rows = [];
for (const p of PKGS) {
  const e = JSON.parse(fs.readFileSync(path.join(SC, 'lean/expect', `${p}.json`), 'utf8'));
  const spec = JSON.parse(fs.readFileSync(path.join(SC, 'lean/examples', `${p}.json`), 'utf8'));
  const lines = fs.readFileSync(path.join(SC, 'lean/examples', `${p}.lean`), 'utf8').split('\n').length - 1;
  const panels = e.cursors.flatMap((c) => c.panels);
  const kinds = [...new Set(panels.map((x) => x.kind === 'static' ? 'HtmlDisplayPanel' : `rpc:${x.method}`))];
  const links = panels.flatMap((x) => x.links ?? []).length;
  const linkKinds = [...new Set(e.clicks.map((k) => k.kind))];
  let closure = null;
  const cf = path.join(W, 'goldens', `${p}.closure.json`);
  if (fs.existsSync(cf)) {
    const c = JSON.parse(fs.readFileSync(cf, 'utf8'));
    const diffPanels = e.cursors.filter((cur, i) => {
      // compare the uri-independent signature (MakeEditLink props embed the document uri, which differs per run dir)
      const sigOf = (ps) => JSON.stringify((ps ?? []).map((x) => [x.svgTagCounts, x.texts, x.codeTexts, x.linkTexts, (x.links ?? []).map((l) => l.edit)]));
      const a = sigOf(cur.panels), b = sigOf(c.cursors[i]?.panels);
      return a !== b;
    }).map((cur) => cur.line);
    const diffEdits = c.clicks.filter((k) => k.editMatchesSupersetGolden === false).length;
    closure = { ok: c.ok, panelsDifferAtLines: diffPanels, clickEditsDiffer: diffEdits };
  }
  rows.push({ pkg: p, lines, cursors: e.cursors.length, panels: panels.length, panelKinds: kinds, linksRendered: links,
    selections: e.selections.length, hovers: (e.hovers ?? []).length, clicks: e.clicks.length, clickKinds: linkKinds,
    clicksOk: e.clicks.filter((k) => k.verdict.ok).length, checks: `${e.declaredChecks.filter((c) => c.ok).length}/${e.declaredChecks.length}`,
    elaborationMs: e.elaborationMs, docDiagnostics: e.documentDiagnostics.map((d) => d.severity).reduce((m, s) => (m[s] = (m[s] ?? 0) + 1, m), {}),
    ok: e.ok, closure, dropped: spec.dropped ?? [] });
}
console.log('| package | lines | cursors | panels (kinds) | links rendered | selections | hovers | clicks ok (kinds) | checks | doc diags | closure-env panels differ at | closure edits differ |');
console.log('|---|---|---|---|---|---|---|---|---|---|---|---|');
for (const r of rows) console.log(`| ${r.pkg} | ${r.lines} | ${r.cursors} | ${r.panels} (${r.panelKinds.join(', ')}) | ${r.linksRendered} | ${r.selections} | ${r.hovers} | ${r.clicksOk}/${r.clicks} (${r.clickKinds.join(', ') || '—'}) | ${r.checks} | ${JSON.stringify(r.docDiagnostics)} | ${r.closure ? (r.closure.panelsDifferAtLines.join(',') || 'none') : 'n/a'} | ${r.closure ? r.closure.clickEditsDiffer : 'n/a'} |`);
fs.writeFileSync(path.join(W, 'goldens', 'summary.json'), JSON.stringify(rows, null, 1));

// ---------- click-all ----------
const ca = [];
for (const p of PKGS) for (const env of ['w8']) {
  const f = path.join(SC, 'lean/expect/click-all', `${p}.json`);
  if (!fs.existsSync(f)) { ca.push({ pkg: p, env, missing: true }); continue; }
  const c = JSON.parse(fs.readFileSync(f, 'utf8'));
  let cli = null;
  const tsv = path.join(W, 'goldens', `click-all-cli.${p}.tsv`);
  if (fs.existsSync(tsv)) {
    const rows = fs.readFileSync(tsv, 'utf8').trim().split('\n').filter(Boolean).map((l) => l.split('\t'));
    cli = { compiled: rows.length, agree: rows.filter((r) => r[4] === 'yes').length };
  }
  ca.push({ pkg: p, env, ok: c.ok, links: c.counts.total, makeEditLink: c.counts.makeEditLink, tryThis: c.counts.tryThis,
    occurrences: c.counts.linkOccurrences, clean: c.counts.clean ?? 0, designed: c.counts.designed ?? 0, broken: c.counts.broken ?? 0,
    panelsRendered: c.panelsRendered, probes: c.probes, declaredClicksCovered: c.declaredClicksCovered, cli,
    brokenLinks: c.links.filter((l) => l.classification === 'broken').map((l) => ({ n: l.n, linkText: l.linkText, title: l.title, edit: l.edit, errorsWarnings: l.errorsWarnings })) });
}
console.log('\n| package | env | links (MakeEditLink + Try-this) | occurrences | clean | designed | broken | declared clicks covered | CLI agrees | panels | probes | ok |');
console.log('|---|---|---|---|---|---|---|---|---|---|---|---|');
for (const r of ca) console.log(r.missing ? `| ${r.pkg} | ${r.env} | missing |` :
  `| ${r.pkg} | ${r.env} | ${r.links} (${r.makeEditLink} + ${r.tryThis}) | ${r.occurrences} | ${r.clean} | ${r.designed} | ${r.broken} | ${r.declaredClicksCovered} | ${r.cli ? `${r.cli.agree}/${r.cli.compiled}` : '—'} | ${r.panelsRendered} | ${r.probes} | ${r.ok} |`);
const tot = (env) => ca.filter((r) => !r.missing && (env === 'primary' ? r.env === 'w8' : r.env === env));
const sum = (rs, k) => rs.reduce((a, r) => a + r[k], 0);
const prim = tot('primary');
const caSummary = { generatedAt: new Date().toISOString(), generator: 'lean/goldens/summary.mjs',
  primary: { packages: prim.length, links: sum(prim, 'links'), makeEditLink: sum(prim, 'makeEditLink'), tryThis: sum(prim, 'tryThis'), occurrences: sum(prim, 'occurrences'),
    clean: sum(prim, 'clean'), designed: sum(prim, 'designed'), broken: sum(prim, 'broken') },
  allEnvRuns: { runs: ca.filter((r) => !r.missing).length, missing: ca.filter((r) => r.missing).length, broken: sum(ca.filter((r) => !r.missing), 'broken') },
  gate: ca.every((r) => !r.missing && r.ok && r.broken === 0 && (!r.cli || r.cli.agree === r.cli.compiled)) ? 'PASS' : 'FAIL',
  rows: ca };
fs.mkdirSync(path.join(SC, 'lean/expect/click-all'), { recursive: true });
fs.writeFileSync(path.join(SC, 'lean/expect/click-all/summary.json'), JSON.stringify(caSummary, null, 1) + '\n');
console.log(`\nCLICK-ALL GATE: ${caSummary.gate} — primary env: ${caSummary.primary.links} links (${caSummary.primary.makeEditLink} MakeEditLink + ${caSummary.primary.tryThis} Try-this; ${caSummary.primary.occurrences} rendered occurrences): clean ${caSummary.primary.clean}, designed ${caSummary.primary.designed}, broken ${caSummary.primary.broken}; all ${caSummary.allEnvRuns.runs} env runs: broken ${caSummary.allEnvRuns.broken}, missing ${caSummary.allEnvRuns.missing}`);
