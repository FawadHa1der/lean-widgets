#!/usr/bin/env node
// run-local.mjs — run this repository's GitHub Actions jobs on this machine, each in a FRESH CLONE, with the workflow's
// own commands. It reads the workflow YAML and executes every `run:` step exactly as written (expressions substituted,
// the same shell flags GitHub uses, the same working directories and env), so a job that is green here ran the same
// command lines as on GitHub. What it cannot do is listed, and printed in every run's summary:
//
//   * `uses:` steps are EMULATED, only these: actions/checkout (a fresh `git clone` of --repo at --ref, then
//     `git submodule update --init --recursive`; a checkout without `submodules: recursive` is refused: every
//     checkout in this repository must fetch QED64), actions/setup-node (checks the host's node version and reports a
//     DEVIATION instead of installing another), actions/upload-artifact and actions/download-artifact (a local artifact
//     store under the run directory), actions/upload-pages-artifact (stored like an artifact). actions/deploy-pages is
//     never emulated. Any other action fails the step.
//   * the host is this machine (macOS here), not ubuntu-latest: RUNNER_OS is the real one, tools come from PATH, and
//     caches in $HOME (elan toolchains, ~/.cache/mathlib, the npm cache) are the host's, i.e. warm.
//   * secrets and vars are whatever --secret/--var pass (default: none, as in a fork); `--runner-env K=V` adds a
//     variable to every step's environment the way a self-hosted runner's environment would (used by
//     ci/rehearse-deploy.sh for its wrangler stand-in). Nothing else from the caller's environment reaches a step
//     except PATH, HOME, USER, LOGNAME, SHELL, LANG, LC_ALL, TMPDIR and TERM.
//   * `timeout-minutes` (job and step) is enforced: the step's process group gets SIGTERM, then SIGKILL 10 s later.
//   * not modelled: services, containers, reusable workflows, `exclude` in a matrix (`include` is: it extends matching combinations or adds new ones), concurrency,
//     permissions, continue-on-error, job-level `container`/`services`.
//
//   node ci/run-local.mjs --workflow .github/workflows/lean-ci.yml [--job <id>]… [--matrix <key>=<v1,v2>]…
//        [--event push|pull_request|workflow_dispatch] [--ref <commit-ish>] [--repo <path>] [--branch main]
//        [--input <k>=<v>]… [--secret <K>=<V>]… [--var <K>=<V>]… [--runner-env <K>=<V>]… [--out <dir>] [--parallel <n>]
//
//   --job        run these jobs (and the jobs they need); default all
//   --matrix     restrict a matrix key to these values
//   --ref        the commit to clone (default HEAD of --repo); the working tree's uncommitted changes are NOT used
//   --out        run directory (default ~/.cache/lean-widgets/ci-local/<UTC time>-<workflow>); must not exist yet
//   --parallel   matrix instances run at once (default 1)
// Writes <out>/summary.json and one log per step (<out>/<job>/logs/<n>-<step>.log). Exit 0 iff every job that ran
// succeeded (skipped jobs and steps are not failures).
import { spawn, execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
let YAML;
try { YAML = require(path.join(HERE, 'node_modules', 'yaml')); } catch {
  console.error('run-local: the YAML parser is not installed: npm ci --prefix ci'); process.exit(2);
}

// ------------------------------------------------------------------------------------------------ arguments
const argv = process.argv.slice(2);
const multi = {}; const single = {};
const MULTI = ['--job', '--matrix', '--input', '--secret', '--var', '--runner-env'];
const SINGLE = ['--workflow', '--event', '--ref', '--repo', '--out', '--parallel', '--branch'];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i]; const v = argv[i + 1];
  if (a === '--help' || a === '-h') { console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n')); process.exit(0); }
  if (![...MULTI, ...SINGLE].includes(a)) { console.error(`run-local: unknown argument ${a} (--help)`); process.exit(2); }
  if (v === undefined) { console.error(`run-local: ${a} needs a value`); process.exit(2); }
  if (MULTI.includes(a)) (multi[a] ||= []).push(v); else single[a] = v;
  i++;
}
const kv = (list = []) => Object.fromEntries(list.map((s) => { const i = s.indexOf('='); if (i < 1) { console.error(`run-local: want K=V, got ${s}`); process.exit(2); } return [s.slice(0, i), s.slice(i + 1)]; }));
const REPO = path.resolve(single['--repo'] || execFileSync('git', ['-C', HERE, 'rev-parse', '--show-toplevel']).toString().trim());
const WF_PATH = single['--workflow'];
if (!WF_PATH) { console.error('run-local: --workflow <path> is required'); process.exit(2); }
const EVENT = single['--event'] || 'push';
const BRANCH = single['--branch'] || 'main';
const SHA = execFileSync('git', ['-C', REPO, 'rev-parse', `${single['--ref'] || 'HEAD'}^{commit}`]).toString().trim();
const SECRETS = kv(multi['--secret']); const VARS = kv(multi['--var']); const RUNNER_ENV = kv(multi['--runner-env']);
const MATRIX_FILTER = Object.fromEntries(Object.entries(kv(multi['--matrix'])).map(([k, v]) => [k, v.split(',')]));
const PARALLEL = Math.max(1, Number(single['--parallel'] || 1));
// the workflow file is read from the commit being run, not from the working tree
const wfRel = path.relative(REPO, path.resolve(REPO, WF_PATH)).split(path.sep).join('/');
const WF = YAML.parse(execFileSync('git', ['-C', REPO, 'show', `${SHA}:${wfRel}`]).toString());
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const OUT = path.resolve(single['--out'] || path.join(os.homedir(), '.cache', 'lean-widgets', 'ci-local', `${stamp}-${path.basename(wfRel, '.yml')}`));
if (fs.existsSync(OUT)) { console.error(`run-local: ${OUT} exists; every run gets a fresh directory`); process.exit(2); }
fs.mkdirSync(OUT, { recursive: true });
const ARTIFACTS = path.join(OUT, '_artifacts');

// workflow_dispatch inputs: typed like GitHub (boolean inputs are booleans, defaults applied)
const inputDefs = (WF.on && WF.on.workflow_dispatch && WF.on.workflow_dispatch.inputs) || {};
const givenInputs = kv(multi['--input']);
const INPUTS = {};
if (EVENT === 'workflow_dispatch') {
  for (const [k, d] of Object.entries(inputDefs)) {
    const raw = k in givenInputs ? givenInputs[k] : d.default;
    INPUTS[k] = d.type === 'boolean' ? (raw === true || raw === 'true') : raw === undefined ? '' : String(raw);
  }
  for (const k of Object.keys(givenInputs)) if (!(k in inputDefs)) { console.error(`run-local: the workflow has no input '${k}'`); process.exit(2); }
} else if (Object.keys(givenInputs).length) { console.error('run-local: --input needs --event workflow_dispatch'); process.exit(2); }

// --------------------------------------------------------------------------------------------- expressions
// GitHub Actions expression subset: literals, contexts with . and [..], ! && || == != < <= > >=, parentheses, and the
// functions always success failure cancelled contains startsWith endsWith format join toJSON fromJSON.
function tokenize(src) {
  const t = []; let i = 0;
  while (i < src.length) {
    const c = src[i];
    if (/\s/.test(c)) { i++; continue; }
    if (c === "'") { let s = ''; i++; for (;;) { if (i >= src.length) throw new Error(`unterminated string in ${src}`); if (src[i] === "'") { if (src[i + 1] === "'") { s += "'"; i += 2; continue; } i++; break; } s += src[i++]; } t.push({ k: 'str', v: s }); continue; }
    const two = src.slice(i, i + 2);
    if (['==', '!=', '<=', '>=', '&&', '||'].includes(two)) { t.push({ k: 'op', v: two }); i += 2; continue; }
    if ('!<>().,[]*'.includes(c)) { t.push({ k: 'op', v: c }); i++; continue; }
    const m = /^(-?\d+(?:\.\d+)?)/.exec(src.slice(i)); if (m && !/[A-Za-z_]/.test(src[i])) { t.push({ k: 'num', v: Number(m[1]) }); i += m[1].length; continue; }
    const id = /^[A-Za-z_][A-Za-z0-9_-]*/.exec(src.slice(i)); if (id) { t.push({ k: 'id', v: id[0] }); i += id[0].length; continue; }
    throw new Error(`cannot parse expression near '${src.slice(i)}'`);
  }
  return t;
}
const truthy = (v) => !(v === false || v === 0 || v === '' || v === null || v === undefined || Number.isNaN(v));
const str = (v) => (v === null || v === undefined ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v));
function looseEq(a, b) {
  if (a === undefined) a = null; if (b === undefined) b = null;
  if (typeof a === 'string' && typeof b === 'string') return a.toLowerCase() === b.toLowerCase();
  if (typeof a === typeof b) return a === b;
  const num = (v) => (v === null ? 0 : typeof v === 'boolean' ? (v ? 1 : 0) : typeof v === 'string' ? (v.trim() === '' ? 0 : Number(v)) : NaN);
  return num(a) === num(b);
}
function evaluate(src, ctx) {
  const t = tokenize(src); let p = 0;
  const peek = (v) => t[p] && t[p].k === 'op' && t[p].v === v;
  const eat = (v) => { if (!peek(v)) throw new Error(`expected '${v}' in ${src}`); p++; };
  const orE = () => { let v = andE(); while (peek('||')) { p++; const r = andE(); v = truthy(v) ? v : r; } return v; };
  const andE = () => { let v = cmpE(); while (peek('&&')) { p++; const r = cmpE(); v = truthy(v) ? r : v; } return v; };
  const cmpE = () => {
    let v = unE();
    while (t[p] && t[p].k === 'op' && ['==', '!=', '<', '<=', '>', '>='].includes(t[p].v)) {
      const op = t[p++].v; const r = unE();
      v = op === '==' ? looseEq(v, r) : op === '!=' ? !looseEq(v, r) : op === '<' ? v < r : op === '<=' ? v <= r : op === '>' ? v > r : v >= r;
    }
    return v;
  };
  const unE = () => (peek('!') ? (p++, !truthy(unE())) : prim());
  const prim = () => {
    const x = t[p++];
    if (!x) throw new Error(`unexpected end of ${src}`);
    if (x.k === 'str' || x.k === 'num') return x.v;
    if (x.k === 'op' && x.v === '(') { const v = orE(); eat(')'); return v; }
    if (x.k !== 'id') throw new Error(`unexpected '${x.v}' in ${src}`);
    if (x.v === 'true') return true; if (x.v === 'false') return false; if (x.v === 'null') return null;
    if (peek('(')) {
      p++; const args = [];
      if (!peek(')')) { args.push(orE()); while (peek(',')) { p++; args.push(orE()); } }
      eat(')');
      return callFn(x.v, args, ctx);
    }
    let v = x.v in ctx ? ctx[x.v] : (() => { throw new Error(`unknown context '${x.v}' in ${src}`); })();
    for (;;) {
      if (peek('.')) { p++; const n = t[p++]; v = v === null || v === undefined ? null : n.v in Object(v) ? v[n.v] : lowerGet(v, n.v); continue; }
      if (peek('[')) { p++; const k = orE(); eat(']'); v = v === null || v === undefined ? null : lowerGet(v, str(k)); continue; }
      break;
    }
    return v === undefined ? null : v;
  };
  const v = orE();
  if (p !== t.length) throw new Error(`trailing tokens in ${src}`);
  return v;
}
const lowerGet = (o, k) => { if (typeof o !== 'object') return null; const f = Object.keys(o).find((x) => x.toLowerCase() === k.toLowerCase()); return f === undefined ? null : o[f]; };
function callFn(name, a, ctx) {
  switch (name) {
    case 'always': return true;
    case 'success': return ctx.__status === 'success';
    case 'failure': return ctx.__status === 'failure';
    case 'cancelled': return false;
    case 'contains': return Array.isArray(a[0]) ? a[0].some((x) => looseEq(x, a[1])) : str(a[0]).toLowerCase().includes(str(a[1]).toLowerCase());
    case 'startsWith': return str(a[0]).toLowerCase().startsWith(str(a[1]).toLowerCase());
    case 'endsWith': return str(a[0]).toLowerCase().endsWith(str(a[1]).toLowerCase());
    case 'format': return str(a[0]).replace(/\{(\d+)\}/g, (_, i) => str(a[1 + Number(i)]));
    case 'join': return (Array.isArray(a[0]) ? a[0] : [a[0]]).map(str).join(a.length > 1 ? str(a[1]) : ',');
    case 'toJSON': return JSON.stringify(a[0], null, 2);
    case 'fromJSON': return JSON.parse(str(a[0]));
    default: throw new Error(`function ${name}() is not supported by run-local`);
  }
}
const interpolate = (s, ctx) => (typeof s === 'string' ? s.replace(/\$\{\{([\s\S]*?)\}\}/g, (_, e) => str(evaluate(e, ctx))) : s);
function condition(expr, ctx) {
  if (expr === undefined || expr === null) return ctx.__status === 'success';
  if (typeof expr === 'boolean') return expr && ctx.__status === 'success';
  let e = String(expr).trim();
  const m = /^\$\{\{([\s\S]*)\}\}$/.exec(e); if (m) e = m[1];
  const statusFn = /\b(always|success|failure|cancelled)\s*\(/.test(e);
  return truthy(evaluate(statusFn ? e : `success() && (${e})`, ctx));
}

// ------------------------------------------------------------------------------------------------ helpers
const log = (job, m) => console.log(`[${job}] ${m}`);
const KEEP_ENV = ['PATH', 'HOME', 'USER', 'LOGNAME', 'SHELL', 'LANG', 'LC_ALL', 'TMPDIR', 'TERM'];
function parseKvFile(file) {
  const out = {}; if (!fs.existsSync(file)) return out;
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i]; if (!l) continue;
    const h = /^([^=<]+)<<(.+)$/.exec(l);
    if (h) { const end = h[2]; const vals = []; i++; while (i < lines.length && lines[i] !== end) vals.push(lines[i++]); out[h[1]] = vals.join('\n'); continue; }
    const j = l.indexOf('='); if (j > 0) out[l.slice(0, j)] = l.slice(j + 1);
  }
  return out;
}
function shellCmd(shell, file) {
  switch (shell || 'default') {
    case 'default': return ['bash', ['-e', file]];
    case 'bash': return ['bash', ['--noprofile', '--norc', '-eo', 'pipefail', file]];
    case 'sh': return ['sh', ['-e', file]];
    case 'python': return ['python3', [file]];
    default: throw new Error(`shell '${shell}' is not supported by run-local`);
  }
}
function runProcess(cmd, args, { cwd, env, logFile, prefix, timeoutMs = 0 }) {
  return new Promise((resolve) => {
    const out = fs.openSync(logFile, 'a');
    // its own process group, so a timeout reaches every child (GitHub cancels the whole step the same way)
    const ch = spawn(cmd, args, { cwd, env, stdio: ['ignore', 'pipe', 'pipe'], detached: true });
    let timer = null, killer = null;
    if (timeoutMs > 0) timer = setTimeout(() => {
      const m = `run-local: timeout-minutes reached after ${Math.round(timeoutMs / 60000)} min: SIGTERM to the step's process group`;
      fs.writeSync(out, `\n${m}\n`); console.log(`${prefix}${m}`);
      try { process.kill(-ch.pid, 'SIGTERM'); } catch {}
      killer = setTimeout(() => { try { process.kill(-ch.pid, 'SIGKILL'); } catch {} }, 10000);
    }, timeoutMs);
    const pipe = (s) => { let buf = ''; s.on('data', (d) => { fs.writeSync(out, d); buf += d.toString(); const parts = buf.split('\n'); buf = parts.pop(); for (const l of parts) console.log(`${prefix}${l}`); }); s.on('end', () => { if (buf) console.log(`${prefix}${buf}`); }); };
    pipe(ch.stdout); pipe(ch.stderr);
    ch.on('close', (code, sig) => { clearTimeout(timer); clearTimeout(killer); fs.closeSync(out); resolve(code === null ? 128 + (sig === 'SIGTERM' ? 15 : 9) : code); });
  });
}
const git = (args, opts = {}) => execFileSync('git', args, { stdio: ['ignore', 'pipe', 'pipe'], ...opts }).toString();
function copyInto(src, dst) { fs.mkdirSync(path.dirname(dst), { recursive: true }); fs.cpSync(src, dst, { recursive: true }); }

// ---------------------------------------------------------------------------------------------- uses: emulation
async function emulate(step, w, js) {
  const [action] = String(step.uses).split('@');
  const withs = Object.fromEntries(Object.entries(step.with || {}).map(([k, v]) => [k, interpolate(typeof v === 'string' ? v : String(v), w.ctx)]));
  const lf = w.logFile; const say = (m) => { fs.appendFileSync(lf, m + '\n'); log(js.name, m); };
  switch (action) {
    case 'actions/checkout': {
      if (withs.submodules !== 'recursive') { say(`REFUSED: actions/checkout without 'submodules: recursive' (every checkout in this repository must fetch QED64, the submodule qed64-showcase/deps/qed64)`); return 1; }
      if (fs.existsSync(w.ws) && fs.readdirSync(w.ws).length) { say(`REFUSED: ${w.ws} is not empty`); return 1; }
      say(`checkout (emulated): git clone ${REPO} -> ${w.ws}, detached at ${SHA.slice(0, 12)}; submodules: recursive`);
      // GitHub's actions/checkout fetches ONE commit unless fetch-depth: 0 — emulate that, so a job that needs history
      // (e.g. an older commit named in a lock) fails here as it would on GitHub. file:// makes --depth apply to a local repo.
      const depth = String(withs['fetch-depth'] ?? '1');
      const cloneArgs = depth === '0' ? ['clone', '--no-checkout', '--quiet', REPO, '.']
        : ['clone', '--no-checkout', '--quiet', '--depth', depth, '--no-single-branch', 'file://' + path.resolve(REPO), '.'];
      if (depth !== '0') say(`checkout: shallow (fetch-depth ${depth}), as actions/checkout does by default`);
      const rc1 = await runProcess('git', cloneArgs, { cwd: w.ws, env: w.baseEnv, logFile: lf, prefix: `[${js.name}]   ` });
      if (rc1) return rc1;
      if (depth !== '0') {   // a SHA that is not a branch tip is not in a shallow clone: fetch exactly it, as actions/checkout does
        const have = (() => { try { git(['-C', w.ws, 'cat-file', '-e', `${SHA}^{commit}`]); return true; } catch { return false; } })();
        if (!have) { const rcf = await runProcess('git', ['-c', 'protocol.version=2', 'fetch', '--quiet', '--depth', depth, 'origin', SHA], { cwd: w.ws, env: w.baseEnv, logFile: lf, prefix: `[${js.name}]   ` }); if (rcf) return rcf; }
      }
      const rc2 = await runProcess('git', ['-c', 'advice.detachedHead=false', 'checkout', '--quiet', SHA], { cwd: w.ws, env: w.baseEnv, logFile: lf, prefix: `[${js.name}]   ` });
      if (rc2) return rc2;
      const rc3 = await runProcess('git', ['submodule', 'update', '--init', '--recursive'], { cwd: w.ws, env: w.baseEnv, logFile: lf, prefix: `[${js.name}]   ` });
      if (rc3) return rc3;
      say(`checkout: HEAD ${git(['-C', w.ws, 'rev-parse', 'HEAD']).trim()}; ${git(['-C', w.ws, 'submodule', 'status', '--recursive']).trim() || 'no submodules'}`);
      return 0;
    }
    case 'actions/setup-node': {
      const want = withs['node-version'] || ''; const have = process.version.replace(/^v/, '');
      const match = want === have || (/^\d+$/.test(want) && have.split('.')[0] === want);
      say(`setup-node (emulated): requested ${want}, host node ${have}: ${match ? 'MATCH' : 'DEVIATION (the host node is used; GitHub would install the requested version)'}`);
      if (!match) js.deviations.push(`setup-node ${want} requested, host node ${have} used`);
      return 0;
    }
    case 'actions/upload-artifact':
    case 'actions/upload-pages-artifact': {
      const name = action === 'actions/upload-pages-artifact' ? (withs.name || 'github-pages') : withs.name;
      const lines = String(withs.path || '').split('\n').map((s) => s.trim()).filter(Boolean);
      const files = [];
      for (const l of lines) { const abs = path.resolve(w.ws, l); for (const f of (fs.globSync ? fs.globSync(abs) : [abs]).filter((x) => fs.existsSync(x))) files.push(f); }
      if (!files.length) {
        const how = withs['if-no-files-found'] || 'warn';
        say(`upload-artifact '${name}': no files for ${lines.join(', ')} (if-no-files-found: ${how})`);
        return how === 'error' ? 1 : 0;
      }
      // GitHub keeps paths relative to the least common ancestor of the matched paths
      const dirs = files.map((f) => (fs.statSync(f).isDirectory() ? f : path.dirname(f)));
      let base = dirs[0]; while (!dirs.every((d) => d === base || d.startsWith(base + path.sep))) base = path.dirname(base);
      const dst = path.join(ARTIFACTS, name);
      if (fs.existsSync(dst)) { say(`upload-artifact: an artifact named '${name}' already exists in this run`); return 1; }
      for (const f of files) copyInto(f, fs.statSync(f).isDirectory() ? dst : path.join(dst, path.relative(base, f)));
      say(`upload-artifact (emulated) '${name}': ${files.length} path(s) from ${path.relative(w.ws, base) || '.'}`);
      return 0;
    }
    case 'actions/download-artifact': {
      const dest = path.resolve(w.ws, withs.path || '.');
      const names = fs.existsSync(ARTIFACTS) ? fs.readdirSync(ARTIFACTS) : [];
      const re = withs.pattern ? new RegExp(`^${withs.pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.')}$`) : null;
      const pick = withs.name ? names.filter((n) => n === withs.name) : re ? names.filter((n) => re.test(n)) : names;
      if (!pick.length) { say(`download-artifact: nothing matches ${withs.name || withs.pattern || '*'}`); return 1; }
      const merge = withs.name || withs['merge-multiple'] === 'true';
      for (const n of pick) copyInto(path.join(ARTIFACTS, n), merge ? dest : path.join(dest, n));
      say(`download-artifact (emulated): ${pick.join(', ')} -> ${path.relative(w.ws, dest) || '.'}${merge ? '' : ' (one directory per artifact)'}`);
      return 0;
    }
    case 'actions/deploy-pages':
      say('NOT EMULATED: actions/deploy-pages publishes to GitHub Pages; nothing was deployed'); js.deviations.push('actions/deploy-pages not emulated'); return 0;
    default:
      say(`UNSUPPORTED action ${step.uses}: run-local emulates only checkout, setup-node, upload-artifact, download-artifact, upload-pages-artifact`); return 1;
  }
}

// -------------------------------------------------------------------------------------------------- jobs
const jobs = WF.jobs || {};
const needsOf = (id) => [].concat(jobs[id].needs || []);
const wanted = new Set();
const addJob = (id) => { if (!jobs[id]) { console.error(`run-local: no job '${id}' in ${wfRel}`); process.exit(2); } if (wanted.has(id)) return; for (const n of needsOf(id)) addJob(n); wanted.add(id); };
for (const id of multi['--job'] || Object.keys(jobs)) addJob(id);
const order = []; const seen = new Set();
const visit = (id) => { if (seen.has(id)) return; seen.add(id); for (const n of needsOf(id)) visit(n); order.push(id); };
for (const id of wanted) visit(id);

const results = {};   // job id -> { result, outputs }
const summary = { workflow: wfRel, repo: REPO, sha: SHA, event: EVENT, inputs: INPUTS, secrets: Object.keys(SECRETS), vars: VARS,
  runnerEnv: Object.keys(RUNNER_ENV), host: `${process.platform}-${process.arch}`, node: process.version, out: OUT, started: new Date().toISOString(), jobs: [] };

function expandMatrix(j) {
  const m = j.strategy && j.strategy.matrix;
  if (!m) return [null];
  if (typeof m === 'string') throw new Error('a matrix from an expression is not supported by run-local');
  if (m.exclude) throw new Error('matrix exclude is not supported by run-local');
  let combos = [{}];
  for (const [k, vals] of Object.entries(m)) {
    if (k === 'include') continue;
    const keep = MATRIX_FILTER[k] ? vals.filter((v) => MATRIX_FILTER[k].includes(String(v))) : vals;
    if (MATRIX_FILTER[k]) for (const f of MATRIX_FILTER[k]) if (!vals.map(String).includes(f)) throw new Error(`matrix ${k} has no value '${f}'`);
    combos = combos.flatMap((c) => keep.map((v) => ({ ...c, [k]: v })));
  }
  // `include` (GitHub's semantics, the subset run-local models): an entry whose matrix-key values match an existing
  // combination adds its other keys to that combination; an entry that matches none is a new combination.
  const keys = Object.keys(m).filter((k) => k !== 'include');
  for (const inc of Array.isArray(m.include) ? m.include : []) {
    const hits = combos.filter((c) => keys.every((k) => !(k in inc) || String(c[k]) === String(inc[k])));
    if (hits.length) {
      for (const c of hits) for (const [k, v] of Object.entries(inc)) if (!keys.includes(k)) c[k] = v;
    } else if (!keys.some((k) => k in inc && MATRIX_FILTER[k] && !MATRIX_FILTER[k].includes(String(inc[k])))) {
      combos.push({ ...inc });
    }
  }
  return combos;
}

async function runInstance(id, matrix) {
  const j = jobs[id];
  const name = matrix ? `${id}(${Object.values(matrix).join(',')})` : id;
  const dir = path.join(OUT, name.replace(/[^A-Za-z0-9._-]+/g, '_'));
  const ws = path.join(dir, 'lean-widgets');   // as on GitHub: <runner work dir>/lean-widgets/lean-widgets
  const temp = path.join(dir, '_temp'); const logs = path.join(dir, 'logs');
  for (const d of [temp, logs, ws]) fs.mkdirSync(d, { recursive: true });   // GitHub creates the (empty) workspace
  const js = { name, job: id, matrix, result: 'success', steps: [], deviations: [], dir: path.relative(OUT, dir) };
  const files = { GITHUB_OUTPUT: 'output', GITHUB_ENV: 'env', GITHUB_PATH: 'path', GITHUB_STEP_SUMMARY: 'summary.md' };
  const baseEnv = Object.fromEntries(KEEP_ENV.filter((k) => process.env[k] !== undefined).map((k) => [k, process.env[k]]));
  const needs = Object.fromEntries(needsOf(id).map((n) => [n, results[n] || { result: 'skipped', outputs: {} }]));
  const github = { event_name: EVENT, ref: `refs/heads/${BRANCH}`, ref_name: BRANCH, sha: SHA, workspace: ws, repository: 'FawadHa1der/lean-widgets',
    repository_owner: 'FawadHa1der', run_id: '0', run_number: '0', job: id, event: { inputs: INPUTS }, server_url: 'https://github.com', actor: 'run-local' };
  const ctx = { github, inputs: INPUTS, secrets: SECRETS, vars: VARS, matrix: matrix || {}, needs, steps: {}, env: {}, job: { status: 'success' },
    runner: { os: process.platform === 'darwin' ? 'macOS' : 'Linux', temp, arch: process.arch }, strategy: {}, __status: 'success' };
  // a job runs only if every job it needs succeeded, unless its `if:` says otherwise
  const needsFailed = Object.values(needs).some((n) => n.result !== 'success');
  ctx.__status = needsFailed ? 'failure' : 'success';
  if (!condition(j.if, ctx)) { js.result = 'skipped'; log(name, `SKIPPED (if: ${j.if === undefined ? 'success() of needs' : j.if})`); summary.jobs.push(js); return js; }
  ctx.__status = 'success';
  if (j.container || j.services || j.uses) { log(name, 'UNSUPPORTED: container/services/reusable workflow'); js.result = 'failure'; summary.jobs.push(js); return js; }
  log(name, `runs-on ${JSON.stringify(j['runs-on'])}: running on this host (${process.platform}-${process.arch}) in ${dir}`);
  let env = { ...Object.fromEntries(Object.entries(WF.env || {}).map(([k, v]) => [k, interpolate(String(v), ctx)])) };
  ctx.env = env;
  env = { ...env, ...Object.fromEntries(Object.entries(j.env || {}).map(([k, v]) => [k, interpolate(String(v), ctx)])) };
  ctx.env = env;
  const defaults = { ...((WF.defaults || {}).run || {}), ...((j.defaults || {}).run || {}) };
  const extraPath = [];
  const jobDeadline = j['timeout-minutes'] ? Date.now() + Number(j['timeout-minutes']) * 60000 : Infinity;
  const w = { ws, ctx, baseEnv: { ...baseEnv, ...RUNNER_ENV, HOME: process.env.HOME }, logFile: null };
  let n = 0;
  for (const step of j.steps || []) {
    n++;
    const sname = step.name || (step.uses ? `uses ${step.uses}` : String(step.run).split('\n')[0].slice(0, 60));
    const lf = path.join(logs, `${String(n).padStart(2, '0')}-${sname.replace(/[^A-Za-z0-9._-]+/g, '_').slice(0, 60)}.log`);
    w.logFile = lf;
    const rec = { n, name: sname, id: step.id || null, outcome: 'skipped', rc: null, log: path.relative(OUT, lf) };
    js.steps.push(rec);
    ctx.__status = js.result === 'success' ? 'success' : 'failure';
    let run;
    try { run = condition(step.if, ctx); } catch (e) { log(name, `step ${n} '${sname}': if: ${e.message}`); rec.outcome = 'failure'; js.result = 'failure'; continue; }
    if (!run) { log(name, `-- step ${n} SKIPPED: ${sname}${step.if !== undefined ? ` (if: ${step.if})` : ''}`); if (step.id) ctx.steps[step.id] = { outputs: {}, outcome: 'skipped', conclusion: 'skipped' }; continue; }
    log(name, `== step ${n}: ${sname}`);
    const t0 = Date.now(); let rc;
    try {
      const stepEnv = { ...env, ...Object.fromEntries(Object.entries(step.env || {}).map(([k, v]) => [k, interpolate(String(v), ctx)])) };
      for (const [k, f] of Object.entries(files)) { const p = path.join(temp, `${f}-${n}`); fs.writeFileSync(p, ''); stepEnv[k] = p; }
      Object.assign(stepEnv, { CI: 'true', GITHUB_ACTIONS: 'true', GITHUB_WORKSPACE: ws, GITHUB_SHA: SHA, GITHUB_REF: github.ref, GITHUB_REF_NAME: BRANCH,
        GITHUB_EVENT_NAME: EVENT, GITHUB_REPOSITORY: github.repository, GITHUB_JOB: id, GITHUB_RUN_ID: '0', RUNNER_TEMP: temp, RUNNER_OS: ctx.runner.os, RUN_LOCAL: '1' });
      const fullEnv = { ...w.baseEnv, ...stepEnv, PATH: [...extraPath, w.baseEnv.PATH].join(':') };
      if (step.uses) rc = await emulate(step, w, js);
      else {
        const script = interpolate(String(step.run), ctx);
        const wd = interpolate(step['working-directory'] || defaults['working-directory'] || '.', ctx);
        const cwd = path.resolve(ws, wd);
        if (!fs.existsSync(cwd)) { fs.appendFileSync(lf, `working-directory ${wd} does not exist\n`); log(name, `working-directory ${wd} does not exist`); rc = 1; }
        else {
          const sf = path.join(temp, `step-${n}.sh`); fs.writeFileSync(sf, script);
          const [cmd, args] = shellCmd(step.shell || defaults.shell, sf);
          fs.appendFileSync(lf, `# ${cmd} ${args.join(' ')}   (cwd ${cwd})\n${script}\n# ---- output\n`);
          const stepMs = step['timeout-minutes'] ? Number(step['timeout-minutes']) * 60000 : Infinity;
          const left = Math.min(stepMs, jobDeadline - Date.now());
          rc = left <= 0 ? 124 : await runProcess(cmd, args, { cwd, env: fullEnv, logFile: lf, prefix: `[${name}]   `, timeoutMs: Number.isFinite(left) ? left : 0 });
        }
        // GITHUB_ENV / GITHUB_PATH / GITHUB_OUTPUT written by the step
        Object.assign(env, parseKvFile(stepEnv.GITHUB_ENV)); ctx.env = env;
        for (const l of fs.readFileSync(stepEnv.GITHUB_PATH, 'utf8').split('\n').filter(Boolean).reverse()) extraPath.unshift(l);
      }
      const outputs = parseKvFile(stepEnv.GITHUB_OUTPUT);
      if (step.id) ctx.steps[step.id] = { outputs, outcome: rc === 0 ? 'success' : 'failure', conclusion: rc === 0 ? 'success' : 'failure' };
    } catch (e) { log(name, `step ${n} error: ${e.message}`); fs.appendFileSync(lf, `run-local error: ${e.stack}\n`); rc = 1; }
    rec.rc = rc; rec.outcome = rc === 0 ? 'success' : 'failure'; rec.seconds = Math.round((Date.now() - t0) / 1000);
    log(name, `   step ${n} ${rec.outcome.toUpperCase()} rc=${rc} (${rec.seconds}s): ${sname}`);
    if (rc !== 0) js.result = 'failure';
  }
  ctx.__status = js.result;
  js.outputs = Object.fromEntries(Object.entries(j.outputs || {}).map(([k, v]) => { try { return [k, interpolate(String(v), ctx)]; } catch { return [k, '']; } }));
  log(name, `JOB ${js.result.toUpperCase()}`);
  summary.jobs.push(js);
  return js;
}

let allOk = true;
for (const id of order) {
  let combos;
  try { combos = expandMatrix(jobs[id]); } catch (e) { console.error(`run-local: job ${id}: ${e.message}`); process.exit(2); }
  const done = [];
  for (let i = 0; i < combos.length; i += PARALLEL) done.push(...await Promise.all(combos.slice(i, i + PARALLEL).map((c) => runInstance(id, c))));
  const ran = done.filter((d) => d.result !== 'skipped');
  const result = !ran.length ? 'skipped' : ran.every((d) => d.result === 'success') ? 'success' : 'failure';
  results[id] = { result, outputs: Object.assign({}, ...done.map((d) => d.outputs || {})) };
  if (result === 'failure') allOk = false;
}
summary.ended = new Date().toISOString();
fs.writeFileSync(path.join(OUT, 'summary.json'), JSON.stringify(summary, null, 2) + '\n');
console.log(`\n==== run-local summary: ${wfRel} @ ${SHA.slice(0, 12)} (${EVENT}) on ${summary.host}, node ${process.version}`);
for (const js of summary.jobs) {
  const steps = js.steps.map((s) => (s.outcome === 'success' ? 'ok' : s.outcome === 'skipped' ? '-' : `FAIL(${s.rc})`));
  console.log(`  ${js.result.toUpperCase().padEnd(8)} ${js.name}  [${steps.join(' ')}]${js.deviations.length ? `  deviations: ${js.deviations.join('; ')}` : ''}`);
}
console.log(`  run dir: ${OUT}`);
console.log(allOk ? 'RUN-LOCAL OK' : 'RUN-LOCAL FAILED');
process.exit(allOk ? 0 : 1);
