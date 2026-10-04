// Render the results matrix of one or more UX runs as Markdown (for docs/UX-RESULTS.md).
// Usage: node tests/ux/tools/report.mjs <run> [<run> ...]   (runs are out/ux/<run>/ with report.json + metrics.json)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const runs = process.argv.slice(2);
if (!runs.length) { console.error('usage: report.mjs <run> [<run> ...]'); process.exit(2); }
const load = (run) => {
  const dir = path.join(SC, 'out/ux', run);
  const rep = JSON.parse(fs.readFileSync(path.join(dir, 'report.json'), 'utf8'));
  const met = fs.existsSync(path.join(dir, 'metrics.json')) ? JSON.parse(fs.readFileSync(path.join(dir, 'metrics.json'), 'utf8')) : { tests: {} };
  const rows = [];
  const walk = (suite) => { for (const s of suite.suites || []) walk(s); for (const sp of suite.specs || []) for (const t of sp.tests) { const r = t.results[t.results.length - 1] || {}; rows.push({ title: sp.title, id: sp.title.split(' ')[0], status: r.status || t.status, ms: r.duration || 0, error: r.error ? String(r.error.message || '').split('\n')[0].slice(0, 160) : null }); } };
  for (const s of rep.suites) walk(s);
  return { run, rows, stats: rep.stats, met };
};
const data = runs.map(load);
const ids = [...new Set(data.flatMap((d) => d.rows.map((r) => r.title)))];
const head = `| ID | Test | ${runs.map((r) => `${r} result | ${r} time`).join(' | ')} |`;
const sep = `|---|---|${runs.map(() => '---|---').join('|')}|`;
console.log(head); console.log(sep);
for (const title of ids) {
  const id = title.split(' ')[0];
  const cells = data.map((d) => { const r = d.rows.find((x) => x.title === title); return r ? `${r.status === 'passed' ? 'pass' : r.status}${r.error ? ` (${r.error.replace(/\|/g, '\\|')})` : ''} | ${(r.ms / 1000).toFixed(1)} s` : '— | —'; });
  console.log(`| ${id} | ${title.slice(id.length + 1).replace(/\|/g, '\\|')} | ${cells.join(' | ')} |`);
}
for (const d of data) console.log(`\n${d.run}: ${JSON.stringify(d.stats)}`);
