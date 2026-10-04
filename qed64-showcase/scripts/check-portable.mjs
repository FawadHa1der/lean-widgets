#!/usr/bin/env node
// check-portable.mjs — fail when a committed file carries a machine-specific absolute path.
//
//   node qed64-showcase/scripts/check-portable.mjs [--verbose]
//
// Scans every file git would commit in this repository (tracked + untracked-not-ignored: `git ls-files -co
// --exclude-standard`), the whole repository, not only qed64-showcase/. A MACHINE PATH is a home directory
// (/Users/<name>, /home/<name>, C:\Users\<name>, and this machine's $HOME), a temp/volume path (/private/tmp,
// /private/var, /var/folders, /Volumes), or an absolute symlink target. Code and configuration must resolve locations
// at run time instead (scripts/lib/env.sh, scripts/lib/env.mjs, the gitignored .env.local).
//
// RECORDS are exempt, by explicit list below (each with its reason): historical evidence documents that quote the
// paths of the machine that produced them, and generated goldens that record the search path of the run. A record
// must not be code: an exempt path with a code extension still fails.
// Exit: 0 clean, 1 violations, 2 usage/git error.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const REPO = path.resolve(SC, '..');
const VERBOSE = process.argv.includes('--verbose');

const RECORDS = [
  ['qed64-showcase/docs/results/', 'curated lane RESULTS copied from out/ (run records)', ['.md']],
  ['qed64-showcase/docs/research/', 'research-phase notes (records of what was read where)', ['.md']],
  ['qed64-showcase/docs/STAGE-A-RESULTS.md', 'stage A results record', ['.md']],
  ['qed64-showcase/docs/STAGE-B-RESULTS.md', 'stage B results record', ['.md']],
  ['qed64-showcase/docs/HEADLESS-RESULTS.md', 'headless verification results record', ['.md']],
  ['qed64-showcase/docs/UX-RESULTS.md', 'UX results record', ['.md']],
  ['qed64-showcase/docs/REPIN-LOG.md', 're-pin history', ['.md']],
  ['qed64-showcase/docs/HISTORY.md', 'project history', ['.md']],
  ['qed64-showcase/docs/CLOSEOUT-INPUT.json', 'closeout input record (data)', ['.json']],
  ['qed64-showcase/lean/expect/', 'generated native goldens: record the search path of the golden run (data)', ['.json']],
];
const CODE_EXT = new Set(['.sh', '.mjs', '.js', '.cjs', '.ts', '.py', '.toml', '.yml', '.yaml', '.lean', '.html', '.css', '.sb']);

const home = os.homedir();
const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const PATTERNS = [
  ['home dir', /(?<![A-Za-z0-9_$])\/Users\/(?!<|\$|\{|you\b|me\b|name\b|USER\b)[A-Za-z0-9._-]+/],
  ['home dir', /(?<![A-Za-z0-9_$])\/home\/(?!<|\$|\{)[A-Za-z0-9._-]+/],
  ['home dir', /[A-Za-z]:\\Users\\[A-Za-z0-9._-]+/],
  ['temp/volume', /(?<![A-Za-z0-9_$])\/(private\/(tmp|var)|var\/folders|Volumes)\//],
  ['this $HOME', new RegExp(esc(home) + '(?![A-Za-z0-9._-])')],
];

let files;
try { files = execFileSync('git', ['-C', REPO, 'ls-files', '-co', '--exclude-standard', '-z']).toString().split('\0').filter(Boolean); }
catch (e) { console.error(`check-portable: git ls-files failed: ${e.message}`); process.exit(2); }
files = [...new Set(files)].sort();

const violations = []; const recordHits = new Map(); let scanned = 0;
for (const rel of files) {
  const abs = path.join(REPO, rel);
  let st; try { st = fs.lstatSync(abs); } catch { continue; } // deleted in the working tree
  if (st.isSymbolicLink()) {
    const t = fs.readlinkSync(abs);
    if (path.isAbsolute(t)) violations.push({ rel, line: 0, kind: 'absolute symlink', text: `-> ${t}` });
    continue;
  }
  if (!st.isFile()) continue;
  const buf = fs.readFileSync(abs);
  if (buf.includes(0)) continue; // binary (screenshots, images)
  scanned++;
  const rec = RECORDS.find(([p]) => (p.endsWith('/') ? rel.startsWith(p) : rel === p));
  const ext = path.extname(rel);
  const lines = buf.toString('utf8').split('\n');
  for (let i = 0; i < lines.length; i++) {
    for (const [kind, re] of PATTERNS) {
      const m = re.exec(lines[i]);
      if (!m) continue;
      if (rec && rec[2].includes(ext) && !CODE_EXT.has(ext)) { recordHits.set(rec[0], (recordHits.get(rec[0]) || 0) + 1); }
      else violations.push({ rel, line: i + 1, kind, text: lines[i].trim().slice(0, 160) });
      break;
    }
  }
}
for (const [p, why] of RECORDS) {
  const exists = p.endsWith('/') ? files.some((f) => f.startsWith(p)) : files.includes(p);
  if (!exists) violations.push({ rel: p, line: 0, kind: 'stale exemption', text: `exempted (${why}) but not in the repository` });
}
if (VERBOSE || violations.length === 0) for (const [p, n] of recordHits) console.log(`record  ${p}: ${n} machine-path line(s) (exempt: ${RECORDS.find((r) => r[0] === p)[1]})`);
for (const v of violations) console.log(`FAIL    ${v.rel}${v.line ? `:${v.line}` : ''} [${v.kind}] ${v.text}`);
console.log(violations.length
  ? `PORTABLE FAILED: ${violations.length} machine path(s) in committed files (${scanned} text files scanned in ${files.length} paths)`
  : `PORTABLE OK: no machine path in code or configuration (${scanned} text files scanned in ${files.length} paths; ${[...recordHits.values()].reduce((a, b) => a + b, 0)} lines in ${recordHits.size} exempt record sets)`);
process.exit(violations.length ? 1 : 0);
