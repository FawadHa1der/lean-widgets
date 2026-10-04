#!/usr/bin/env node
// Cross-check: panels rendered by the LSP goldens (lean/expect/html/<pkg>.json,
// produced through the real getWidgets/RPC path) against the widget suite's
// own headless probe dumps (<repo>/showcase/dumps/<pkg>.json, produced by calling
// the pure renderers) for the panels that show the SAME input.  Compares the
// SVG tag multiset and the text-node sequence.  Prints one line per pair.
import fs from 'node:fs';
import path from 'node:path';

const SC = path.resolve(import.meta.dirname, '..', '..');
const { REPO_ROOT, W } = await import(path.join(SC, 'scripts/lib/env.mjs')); // the repository root (showcase/dumps) and the work dir
// [pkg, golden cursor command prefix, dump entry name]
// (only pairs whose input is identical; the dumps' subset/nonempty/weather entries use other inputs)
const PAIRS = [
  ['chart-kit', '#chart diceChart', 'diceChart'],
  ['chart-kit', '#chart cdfChart', 'cdfChart'],
  ['chart-kit', '#chart { title? := some "n^2/10 vs 2^n/10"', 'growthChart'],
  ['chart-kit', '#chart weekChart', 'weekChart'],
  ['expr-xray', '#xray (1 + 1 : Nat)', 'xray-1plus1-nat'],
  ['expr-xray', '#xray ((3 : Nat) : Int)', 'xray-coe-nat-to-int'],
  ['expr-xray', '#xray_diff @ite Nat (2 = 2)', 'compare-ite-instance-mismatch'],
  ['interval-inspector', '#interval_inspect (Set.Ioc (1:ℝ) 2 ∪', 'union_eq_real_with_suggestions'],
  ['interval-inspector', '#interval_inspect ((3:ℝ) ∈', 'membership_real'],
  ['interval-inspector', '#interval_inspect (Set.Ico (0:ℕ) 2', 'nat_subset_density_caveat'],
  ['hasse-view', '#hasse (Finset (Fin 3))', 'powerset-cube'],
  ['dist-lens', '#dist die', 'die6_dist_panel'],
  ['dist-lens', '#dist twoDice', 'two_dice_bind_result_panel'],
  ['dist-lens', '#dist_film twoDice', 'two_dice_bind_filmstrip'],
];
const count = (o, k) => { o[k] = (o[k] ?? 0) + 1; };
function sigLsp(h) { // RPC-encoded Html
  const svg = {}, texts = [];
  const walk = (x, inSvg) => {
    if ('text' in x) { if (x.text.trim()) texts.push(x.text); return; }
    if ('element' in x) { const [t, , ch] = x.element; const s = inSvg || t === 'svg'; if (s) count(svg, t); ch.forEach((c) => walk(c, s)); return; }
    if ('component' in x) x.component[3].forEach((c) => walk(c, inSvg));
  };
  walk(h, false); return { svg, texts };
}
function sigDump(h) { // showcase dump schema
  const svg = {}, texts = [];
  const walk = (x, inSvg) => {
    if (x.t === 'text') { if (x.s.trim()) texts.push(x.s); return; }
    if (x.t === 'el') { const s = inSvg || x.tag === 'svg'; if (s) count(svg, x.tag); x.children.forEach((c) => walk(c, s)); return; }
    if (x.t === 'comp') x.children.forEach((c) => walk(c, inSvg));
  };
  walk(h, false); return { svg, texts };
}
const norm = (o) => JSON.stringify(Object.fromEntries(Object.entries(o).sort()));
let agree = 0; const rows = [];
for (const [pkg, cmd, name] of PAIRS) {
  const exp = JSON.parse(fs.readFileSync(path.join(SC, 'lean/expect', `${pkg}.json`), 'utf8'));
  const html = JSON.parse(fs.readFileSync(path.join(SC, 'lean/expect/html', `${pkg}.json`), 'utf8'));
  const dump = JSON.parse(fs.readFileSync(path.join(REPO_ROOT, 'showcase/dumps', `${pkg}.json`), 'utf8'));
  const cur = exp.cursors.find((c) => c.command.startsWith(cmd));
  const panel = html.panels.find((p) => p.line === cur.line && p.selection === undefined);
  const entry = dump.entries.find((e) => e.name === name);
  const a = sigLsp(panel.html), b = sigDump(entry.tree);
  const svgEq = norm(a.svg) === norm(b.svg);
  const textEq = JSON.stringify(a.texts) === JSON.stringify(b.texts);
  const extra = a.texts.filter((t) => !b.texts.includes(t)), missing = b.texts.filter((t) => !a.texts.includes(t));
  if (svgEq && textEq) agree++;
  rows.push({ pkg, cmd, dump: name, svgEqual: svgEq, textsEqual: textEq, lspSvg: a.svg, dumpSvg: svgEq ? undefined : b.svg,
    onlyInLsp: extra.slice(0, 6), onlyInDump: missing.slice(0, 6) });
  console.log(`${svgEq && textEq ? 'SAME' : 'DIFF'}  ${pkg.padEnd(19)} ${name.padEnd(32)} svg ${svgEq ? '=' : '≠'} texts ${textEq ? '=' : '≠'}` +
    (svgEq ? '' : `  lsp=${norm(a.svg)} dump=${norm(b.svg)}`) +
    (textEq ? '' : `  onlyLsp=${JSON.stringify(extra.slice(0, 4))} onlyDump=${JSON.stringify(missing.slice(0, 4))}`));
}
console.log(`${agree}/${PAIRS.length} identical (svg multiset + text sequence)`);
fs.writeFileSync(path.join(W, 'goldens/crosscheck.json'), JSON.stringify(rows, null, 1));
