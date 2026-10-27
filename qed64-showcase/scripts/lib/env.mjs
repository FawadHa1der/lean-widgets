// env.mjs — ONE place that says where everything lives (Node; scripts/lib/env.sh is the same for bash, same rules).
// Nothing machine-specific is hard-coded: the project root comes from this file's location, everything else from
// environment variables, optionally set in the gitignored qed64-showcase/.env.local (KEY=VALUE lines; template
// .env.example). A variable already set in the environment wins over .env.local. Importing this module applies
// .env.local to process.env, so child processes (bash scripts, node tools) see the same values.
//
//   SC  qed64-showcase/        REPO_ROOT  SC/..        WS  REPO_ROOT/packages (the widget packages)
//   W   QED64_SHOWCASE_WORK (default ~/.cache/lean-widgets/qed64-showcase-work)        LOGS  W/logs
//   Q   QED64_REPO (heavy path: pin, stage)   K  QED64_KERNEL_BUILD     KR  QED64_KERNEL_SRC     LG  LEAN4GAME_DIR   (read-only inputs)
//   TC  LEAN_TOOLCHAIN_DIR (default ~/.elan/toolchains/leanprover--lean4---v<the TARGET pin's Lean version>, read from its
//       runtime manifest; v4.34.0 when that cannot be read, the version of every pin before 521cf3f)
//   MATHLIB_CLONE  the Mathlib clone `native` builds into and `stage` reads (default W/mathlib4.<first 8 hex of the target
//       pin lock's toolchain.mathlib.commit> when it exists, else the legacy W/mathlib4 when its HEAD is that commit)
//   DOCKER_IMAGE  QED64_TOOLCHAIN_IMAGE (default qed64-toolchain:emsdk-6.0.5)
// The TARGET pin is SHOWCASE_PIN, else the active pin (scripts/lib/pins.mjs targetPinId; that module imports this one, so the
// two defaults above are derived here from the pin's files alone: no git, no throw at import). scripts/lib/env.sh asks this
// module for them (--sh), so bash and Node agree.
// The read-only inputs are '' when unset, MATHLIB_CLONE '' when it does not resolve; need('QED64_REPO') returns the path
// or throws a clear error (for MATHLIB_CLONE: why it did not resolve, naming the expected path).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const REPO_ROOT = path.resolve(SC, '..');
export const WS = path.join(REPO_ROOT, 'packages');
export const ENV_LOCAL = path.join(SC, '.env.local');

/** Parse a .env.local text: KEY=VALUE, optional quotes and `export `, # comments, $HOME and leading ~/ expanded. */
export function parseEnvFile(text, home = os.homedir()) {
  const out = {};
  for (let l of text.split(/\r?\n/)) {
    l = l.trim();
    if (!l || l.startsWith('#')) continue;
    if (l.startsWith('export ')) l = l.slice(7);
    const i = l.indexOf('=');
    if (i < 0) continue;
    const k = l.slice(0, i);
    let v = l.slice(i + 1);
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(k)) continue;
    if (v.length >= 2 && ((v[0] === '"' && v.at(-1) === '"') || (v[0] === "'" && v.at(-1) === "'"))) v = v.slice(1, -1);
    v = v.split('$HOME').join(home);
    if (v.startsWith('~/')) v = path.join(home, v.slice(2));
    out[k] = v;
  }
  return out;
}
if (fs.existsSync(ENV_LOCAL)) {
  for (const [k, v] of Object.entries(parseEnvFile(fs.readFileSync(ENV_LOCAL, 'utf8')))) if (process.env[k] === undefined) process.env[k] = v;
}
if (!process.env.QED64_SHOWCASE_WORK) process.env.QED64_SHOWCASE_WORK = path.join(os.homedir(), '.cache', 'lean-widgets', 'qed64-showcase-work');

export const W = process.env.QED64_SHOWCASE_WORK;
export const LOGS = path.join(W, 'logs');
export const Q = process.env.QED64_REPO || '';
export const K = process.env.QED64_KERNEL_BUILD || '';
export const KR = process.env.QED64_KERNEL_SRC || '';
export const LG = process.env.LEAN4GAME_DIR || '';

// ---- defaults derived from the TARGET pin's files (SHOWCASE_PIN=<id>, else the active lock QED64.lock.json) ----
const readJsonOr = (p) => { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; } };
const relW = (p) => (p.startsWith(SC + path.sep) ? path.relative(SC, p) : p.startsWith(W + path.sep) ? `$W/${path.relative(W, p)}` : p);
/** The target pin's id, or null (SHOWCASE_PIN malformed, or unset with no readable active lock). */
function targetId() {
  const e = process.env.SHOWCASE_PIN;
  if (e) return /^[0-9a-f]{7}$/.test(e) ? e : null;
  const c = readJsonOr(path.join(SC, 'QED64.lock.json'))?.qed64?.commit;
  return /^[0-9a-f]{40}$/.test(c || '') ? c.slice(0, 7) : null;
}
/** The Lean version pin `id` serves: `leanVersion` of a runtime manifest whose buildId is the descriptor's (release/<id>/,
 *  else the pin's QED64 sources: its worktree W/qed64-pins/<id> or the submodule deps/qed64). The runtime fixes the
 *  version, so the buildId match is the whole check. {version, from, id} or {version: null, why}. */
export function pinLeanVersion(id = targetId()) {
  if (!id) return { version: null, why: 'no target pin (SHOWCASE_PIN unset or malformed, and no readable QED64.lock.json)' };
  const bid = readJsonOr(path.join(SC, 'pins', id, 'pin.json'))?.buildId;
  if (!bid) return { version: null, why: `pins/${id}/pin.json is missing or names no buildId` };
  for (const d of [path.join(SC, 'release', id), path.join(W, 'qed64-pins', id), path.join(SC, 'deps', 'qed64')]) {
    const f = path.join(d, 'public', 'runtime', 'runtime-manifest.json'), m = readJsonOr(f);
    if (m && m.buildId === bid && /^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$/.test(m.leanVersion || '')) return { version: m.leanVersion, from: f, id };
  }
  return { version: null, why: `no runtime manifest of pin ${id}'s runtime ${bid} with a leanVersion (release/${id}, $W/qed64-pins/${id}, deps/qed64)` };
}
/** HEAD commit of a git checkout, read from its files (a .git dir or gitdir file; a symbolic ref via refs/ or packed-refs). */
function gitHead(dir) {
  try {
    let g = path.join(dir, '.git');
    if (fs.statSync(g).isFile()) g = path.resolve(dir, fs.readFileSync(g, 'utf8').replace(/^gitdir:\s*/, '').trim());
    const h = fs.readFileSync(path.join(g, 'HEAD'), 'utf8').trim();
    if (/^[0-9a-f]{40}$/.test(h)) return h;
    const ref = /^ref:\s*(\S+)$/.exec(h)?.[1];
    if (!ref) return null;
    try { return fs.readFileSync(path.join(g, ref), 'utf8').trim(); } catch { /* packed */ }
    const l = fs.readFileSync(path.join(g, 'packed-refs'), 'utf8').split('\n').find((x) => x.endsWith(` ${ref}`));
    return l ? l.slice(0, 40) : null;
  } catch { return null; }
}
/** The Mathlib clone of pin `id` (its lock's toolchain.mathlib.commit: what the native delta and the staged trees are built
 *  against): W/mathlib4.<commit 8> when it exists (and is at that commit), else the legacy W/mathlib4 when its HEAD is that
 *  commit (the clone of pins up to 58ebbad). {dir} or {dir: '', why} naming the expected path. */
export function pinMathlibClone(id = targetId()) {
  if (!id) return { dir: '', why: 'no target pin (SHOWCASE_PIN unset or malformed, and no readable QED64.lock.json)' };
  const c = readJsonOr(path.join(SC, 'pins', id, 'QED64.lock.json'))?.toolchain?.mathlib?.commit;
  if (!/^[0-9a-f]{40}$/.test(c || '')) return { dir: '', why: `pins/${id}/QED64.lock.json records no toolchain.mathlib.commit (register the pin first: scripts/pin-qed64.mjs pin --pin ${id})` };
  const keyed = path.join(W, `mathlib4.${c.slice(0, 8)}`), legacy = path.join(W, 'mathlib4');
  if (fs.existsSync(keyed)) {
    const h = gitHead(keyed);
    return h === c ? { dir: keyed } : { dir: '', why: `${keyed} is at ${h ? h.slice(0, 12) : 'an unreadable HEAD'}, not pin ${id}'s Mathlib ${c.slice(0, 12)} (pins/${id}/QED64.lock.json toolchain.mathlib.commit); move it aside` };
  }
  const h = gitHead(legacy);
  if (h === c) return { dir: legacy };
  return { dir: '', why: `no Mathlib clone for pin ${id}'s Mathlib ${c.slice(0, 12)}: expected ${keyed}${h ? ` (the legacy ${legacy} is at ${h.slice(0, 12)})` : ''}; make it with B0: cp -cpR ${K || '$QED64_KERNEL_BUILD'}/mathlib/mathlib4 ${keyed} (a kernel build whose mathlib/MATHLIB-COMMIT is that commit; new inodes, nlink 1)` };
}
const LEGACY_LEAN = '4.34.0'; // every pin before 521cf3f
const LEAN = pinLeanVersion();
export const TC_LEAN = LEAN.version || LEGACY_LEAN;
export const TC_FROM = process.env.LEAN_TOOLCHAIN_DIR ? 'LEAN_TOOLCHAIN_DIR'
  : LEAN.version ? `Lean ${LEAN.version} of pin ${LEAN.id} (${relW(LEAN.from)} leanVersion)` : `fallback v${LEGACY_LEAN}: ${LEAN.why}`;
export const TC = process.env.LEAN_TOOLCHAIN_DIR || path.join(process.env.ELAN_HOME || path.join(os.homedir(), '.elan'), 'toolchains', `leanprover--lean4---v${TC_LEAN}`);
const MC = process.env.MATHLIB_CLONE ? { dir: process.env.MATHLIB_CLONE } : pinMathlibClone();
export const MATHLIB_CLONE = MC.dir;
export const MATHLIB_CLONE_WHY = MC.why || '';
export const DOCKER_IMAGE = process.env.QED64_TOOLCHAIN_IMAGE || 'qed64-toolchain:emsdk-6.0.5';

const HINTS = {
  QED64_REPO: "a QED64 checkout at the pinned commit with QED64's binaries built (only for pin and stage: the heavy path, docs/BUILD-FROM-SOURCE.md; QED64's sources are the submodule deps/qed64)",
  QED64_KERNEL_BUILD: 'the wasm64 kernel build dir (native/stage1, mathlib/, BUILT-COMMIT; built from https://github.com/FawadHa1der/lean4 branch qed64-wasm64)',
  QED64_KERNEL_SRC: 'the kernel source checkout (https://github.com/FawadHa1der/lean4, branch qed64-wasm64)',
  LEAN4GAME_DIR: 'a wasm64 lean4game checkout',
  LEAN_TOOLCHAIN_DIR: `the stock Lean v${TC_LEAN} toolchain of the target pin (elan toolchain install leanprover/lean4:v${TC_LEAN}; ${TC_FROM})`,
  MATHLIB_CLONE: MATHLIB_CLONE_WHY || "the target pin's Mathlib clone (W/mathlib4.<first 8 hex of its lock's toolchain.mathlib.commit>, or the legacy W/mathlib4 at that commit)",
};
/** The value of a required path variable; throws a clear error when it is unset or does not exist. */
export function need(name) {
  const v = name === 'LEAN_TOOLCHAIN_DIR' ? TC : name === 'MATHLIB_CLONE' ? MATHLIB_CLONE : (process.env[name] || '');
  const hint = HINTS[name] || 'see qed64-showcase/.env.example';
  if (!v) throw new Error(`${name} is not set: ${hint}. Set it in the environment or in ${ENV_LOCAL} (template: .env.example).`);
  if (!fs.existsSync(v)) throw new Error(`${name}=${v} does not exist: ${hint}.`);
  return v;
}
/** Expand ${VAR} placeholders in a configured path (e.g. pins/<id>/pin.json servedTrees); unset VAR -> clear error. */
export function expandPath(s) {
  return String(s).replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/g, (_, n) => {
    if (n === 'QED64_SHOWCASE_WORK') return W;
    if (n === 'LEAN_TOOLCHAIN_DIR') return TC;
    const v = process.env[n];
    if (!v) throw new Error(`${s}: ${n} is not set: ${HINTS[n] || 'see qed64-showcase/.env.example'}. Set it in the environment or in ${ENV_LOCAL}.`);
    return v;
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  // node scripts/lib/env.mjs [--json]: print the resolved locations (no secrets live here)
  // node scripts/lib/env.mjs --sh: the pin-derived ones as shell assignments, for scripts/lib/env.sh (always exit 0)
  const sq = (s) => `'${String(s).split("'").join("'\\''")}'`;
  if (process.argv.includes('--sh')) {
    console.log(Object.entries({ TC, TC_LEAN, TC_FROM, MATHLIB_CLONE, MATHLIB_CLONE_WHY }).map(([k, v]) => `${k}=${sq(v)}`).join('\n'));
  } else {
    const r = { SC, REPO_ROOT, WS, W, Q, K, KR, LG, TC, TC_FROM, MATHLIB_CLONE, ...(MATHLIB_CLONE_WHY ? { MATHLIB_CLONE_WHY } : {}), DOCKER_IMAGE, envLocal: fs.existsSync(ENV_LOCAL) ? ENV_LOCAL : null };
    console.log(process.argv.includes('--json') ? JSON.stringify(r, null, 2) : Object.entries(r).map(([k, v]) => `${k}=${v || '(unset)'}`).join('\n'));
  }
}
