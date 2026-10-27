// env.mjs — ONE place that says where everything lives (Node; scripts/lib/env.sh is the same for bash, same rules).
// Nothing machine-specific is hard-coded: the project root comes from this file's location, everything else from
// environment variables, optionally set in the gitignored qed64-showcase/.env.local (KEY=VALUE lines; template
// .env.example). A variable already set in the environment wins over .env.local. Importing this module applies
// .env.local to process.env, so child processes (bash scripts, node tools) see the same values.
//
//   SC  qed64-showcase/        REPO_ROOT  SC/..        WS  REPO_ROOT/packages (the widget packages)
//   W   QED64_SHOWCASE_WORK (default ~/.cache/lean-widgets/qed64-showcase-work)        LOGS  W/logs
//   Q   QED64_REPO (heavy path: pin, stage)   KR  QED64_KERNEL_SRC     LG  LEAN4GAME_DIR   (read-only inputs)
//   K   the TARGET pin's kernel build (read-only): QED64_KERNEL_BUILD names one kernel build dir or a ':'-separated list
//       of them (one per Lean release); K is the first whose native/NATIVE-COMMIT and mathlib/MATHLIB-COMMIT are the pin
//       lock's toolchain.native64.NATIVE_COMMIT and toolchain.mathlib.commit, else '' and K_FROM names every rejected one;
//       K_CANDIDATES all of them (scripts/assert-untouched.sh watches every one, not only K)
//   TC  LEAN_TOOLCHAIN_DIR (default ~/.elan/toolchains/leanprover--lean4---v<the TARGET pin's Lean version>, read from its
//       runtime manifest; when that cannot be read, v4.34.0 only for a pin whose lock records the lean-v4.34.0 native
//       compiler (pins A–N), else '' and TC_FROM says why). Consumers that load the packages' .lake oleans with it refuse
//       unless it runs the packages' Lean (packages/*/lean-toolchain: tcPackagesMismatch)
//   MATHLIB_CLONE  the Mathlib clone `native` builds into and `stage` reads (default W/mathlib4.<first 8 hex of the target
//       pin lock's toolchain.mathlib.commit> when it exists, else the legacy W/mathlib4 when its HEAD is that commit)
//   DOCKER_IMAGE  QED64_TOOLCHAIN_IMAGE (default qed64-toolchain:emsdk-6.0.5)
// The TARGET pin is SHOWCASE_PIN, else the active pin (scripts/lib/pins.mjs targetPinId; that module imports this one, so the
// three defaults above are derived here from the pin's files alone: no git, no throw at import). scripts/lib/env.sh asks
// this module for them (--sh), so bash and Node agree.
// The read-only inputs are '' when unset; K, TC and MATHLIB_CLONE '' when they do not resolve. need('QED64_REPO') returns
// the path or throws a clear error (for K, TC and MATHLIB_CLONE: why it did not resolve, naming what was expected).
import { execFileSync } from 'node:child_process';
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
export const KR = process.env.QED64_KERNEL_SRC || '';
export const LG = process.env.LEAN4GAME_DIR || '';

// ---- defaults derived from the TARGET pin's files (SHOWCASE_PIN=<id>, else the active lock QED64.lock.json) ----
const readJsonOr = (p) => { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; } };
const readTrimOr = (p) => { try { return fs.readFileSync(p, 'utf8').trim(); } catch { return null; } };
const relW = (p) => (p.startsWith(SC + path.sep) ? path.relative(SC, p) : p.startsWith(W + path.sep) ? `$W/${path.relative(W, p)}` : p);
/** The target pin's id, or null (SHOWCASE_PIN malformed, or unset with no readable active lock: noTarget() says which). */
function targetId() {
  const e = process.env.SHOWCASE_PIN;
  if (e) return /^[0-9a-f]{7}$/.test(e) ? e : null;
  const c = readJsonOr(path.join(SC, 'QED64.lock.json'))?.qed64?.commit;
  return /^[0-9a-f]{40}$/.test(c || '') ? c.slice(0, 7) : null;
}
const noTarget = () => (process.env.SHOWCASE_PIN ? `SHOWCASE_PIN=${process.env.SHOWCASE_PIN} is not a pin id (the 7-hex prefix of a QED64 commit)`
  : 'no target pin (SHOWCASE_PIN unset, and no readable QED64.lock.json)');
/** What pin `id`'s native toolchain was built from: its lock's toolchain.native64.NATIVE_COMMIT and toolchain.mathlib.commit
 *  ({native, mathlib, from}), or null when the lock records none (a pin not registered yet). */
export function pinToolchain(id) {
  const tc = id ? readJsonOr(path.join(SC, 'pins', id, 'QED64.lock.json'))?.toolchain : null;
  const native = tc?.native64?.NATIVE_COMMIT, mathlib = tc?.mathlib?.commit;
  return /^[0-9a-f]{40}$/.test(native || '') && /^[0-9a-f]{40}$/.test(mathlib || '') ? { native, mathlib, from: `pins/${id}/QED64.lock.json` } : null;
}
// The native64 compiler of every lean-v4.34.0-* release (pins A–N). native64 and the runtime a pin serves are one Lean
// version (the runtime loads the oleans it writes), so a lock that records it proves Lean 4.34.0 without the manifest.
const LEGACY_LEAN = '4.34.0', LEGACY_NATIVE = '857544b439aa51633344d638dacc03d304b9ea96';
/** The Lean version pin `id` serves: `leanVersion` of a runtime manifest whose buildId is the descriptor's (release/<id>/,
 *  else the pin's QED64 sources: its worktree W/qed64-pins/<id> or the submodule deps/qed64). The runtime fixes the
 *  version, so the buildId match is the whole check. Without one, v4.34.0 only when the pin's lock records
 *  LEGACY_NATIVE; any other pin is never guessed. {version, from, id} or {version: null, why}. */
export function pinLeanVersion(id = targetId()) {
  if (!id) return { version: null, why: noTarget() };
  const bid = readJsonOr(path.join(SC, 'pins', id, 'pin.json'))?.buildId;
  if (!bid) return { version: null, why: `pins/${id}/pin.json is missing or names no buildId` };
  for (const d of [path.join(SC, 'release', id), path.join(W, 'qed64-pins', id), path.join(SC, 'deps', 'qed64')]) {
    const f = path.join(d, 'public', 'runtime', 'runtime-manifest.json'), m = readJsonOr(f);
    if (m && m.buildId === bid && /^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$/.test(m.leanVersion || '')) return { version: m.leanVersion, from: `${relW(f)} leanVersion`, id };
  }
  const why = `no runtime manifest of pin ${id}'s runtime ${bid} with a leanVersion (release/${id}, $W/qed64-pins/${id}, deps/qed64)`;
  const n = pinToolchain(id)?.native;
  if (n === LEGACY_NATIVE) return { version: LEGACY_LEAN, from: `fallback: ${why}; pins/${id}/QED64.lock.json records the lean-v${LEGACY_LEAN} native compiler ${n.slice(0, 10)}`, id };
  return { version: null, why: `${why}, and pins/${id}/QED64.lock.json does not record the lean-v${LEGACY_LEAN} native compiler (NATIVE_COMMIT ${n ? n.slice(0, 10) : 'missing'}): bootstrap the pin (scripts/showcase.sh bootstrap --pin ${id}) or set LEAN_TOOLCHAIN_DIR` };
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
  if (!id) return { dir: '', why: noTarget() };
  const c = readJsonOr(path.join(SC, 'pins', id, 'QED64.lock.json'))?.toolchain?.mathlib?.commit;
  if (!/^[0-9a-f]{40}$/.test(c || '')) return { dir: '', why: `pins/${id}/QED64.lock.json records no toolchain.mathlib.commit (register the pin first: scripts/pin-qed64.mjs pin --pin ${id})` };
  const keyed = path.join(W, `mathlib4.${c.slice(0, 8)}`), legacy = path.join(W, 'mathlib4');
  if (fs.existsSync(keyed)) {
    const h = gitHead(keyed);
    return h === c ? { dir: keyed } : { dir: '', why: `${keyed} is at ${h ? h.slice(0, 12) : 'an unreadable HEAD'}, not pin ${id}'s Mathlib ${c.slice(0, 12)} (pins/${id}/QED64.lock.json toolchain.mathlib.commit); move it aside` };
  }
  const h = gitHead(legacy);
  if (h === c) return { dir: legacy };
  // B0's source: pin id's own kernel build, never the raw QED64_KERNEL_BUILD (a list is no directory)
  const kb = pinToolchain(id) ? pinKernelBuild(id).dir : '';
  return { dir: '', why: `no Mathlib clone for pin ${id}'s Mathlib ${c.slice(0, 12)}: expected ${keyed}${h ? ` (the legacy ${legacy} is at ${h.slice(0, 12)})` : ''}; make it with B0: cp -cpR ${kb || `<the kernel build whose mathlib/MATHLIB-COMMIT is ${c.slice(0, 12)}: add it to QED64_KERNEL_BUILD>`}/mathlib/mathlib4 ${keyed} (new inodes, nlink 1)` };
}
/** The kernel build of pin `id` among the QED64_KERNEL_BUILD candidates `cands`: the first whose native/NATIVE-COMMIT and
 *  mathlib/MATHLIB-COMMIT are `want`'s (default: the pin's lock, pinToolchain; pin-qed64.mjs `pin` passes its release
 *  record's). With nothing to compare against, a registered pin (pins/<id>/pin.json, which `pin` requires: it checks the
 *  dir against the release record) takes a single candidate unchecked and refuses a list; no target pin or an
 *  unregistered one refuses both, as TC and MATHLIB_CLONE do. {dir, from}, or {dir: '', why}; {dir: '', why: ''} when
 *  none is given. */
export function pinKernelBuild(id = targetId(), want = pinToolchain(id), cands = K_CANDIDATES) {
  if (!cands.length) return { dir: '', why: '' };
  const pin = id ? `pin ${id}` : 'the target pin', sh = (c) => (c ? c.slice(0, 10) : 'missing');
  if (!want) {
    if (!id) return { dir: '', why: noTarget() };
    if (!fs.existsSync(path.join(SC, 'pins', id, 'pin.json'))) return { dir: '', why: `pins/${id}/pin.json is missing (no registered pin ${id})` };
    const none = `pins/${id}/QED64.lock.json records no toolchain.native64.NATIVE_COMMIT / toolchain.mathlib.commit`;
    return cands.length === 1 ? { dir: cands[0], from: `QED64_KERNEL_BUILD, unchecked (${none})` }
      : { dir: '', why: `QED64_KERNEL_BUILD lists ${cands.length} kernel builds, and ${none}: nothing to choose ${pin}'s by` };
  }
  const rejected = [];
  for (const c of cands) {
    const n = readTrimOr(path.join(c, 'native', 'NATIVE-COMMIT')), m = readTrimOr(path.join(c, 'mathlib', 'MATHLIB-COMMIT'));
    if (n === want.native && m === want.mathlib) return { dir: c, from: `the QED64_KERNEL_BUILD candidate built from ${pin}'s NATIVE-COMMIT ${sh(n)} and Mathlib ${sh(m)} (${want.from})` };
    rejected.push(fs.existsSync(c) ? `${c} (NATIVE-COMMIT ${sh(n)}, MATHLIB-COMMIT ${sh(m)})` : `${c} (does not exist)`);
  }
  return { dir: '', why: `no QED64_KERNEL_BUILD candidate is ${pin}'s kernel build (NATIVE-COMMIT ${sh(want.native)}, MATHLIB-COMMIT ${sh(want.mathlib)}, ${want.from}); rejected: ${rejected.join('; ')}` };
}
// one dir or a ':'-separated list (a path holding ':' cannot be given; empty entries are dropped); each entry's leading ~/
// is expanded here (the .env.local parsers expand only the value's, i.e. the first entry's)
export const K_CANDIDATES = (process.env.QED64_KERNEL_BUILD || '').split(':').filter(Boolean).map((p) => (p.startsWith('~/') ? path.join(os.homedir(), p.slice(2)) : p));
const KB = pinKernelBuild();
export const K = KB.dir;
export const K_FROM = KB.dir ? KB.from : KB.why || 'QED64_KERNEL_BUILD is not set';
const LEAN = pinLeanVersion();
export const TC_LEAN = LEAN.version || '';
export const TC_FROM = process.env.LEAN_TOOLCHAIN_DIR ? 'LEAN_TOOLCHAIN_DIR' : LEAN.version ? `Lean ${LEAN.version} of pin ${LEAN.id} (${LEAN.from})` : LEAN.why;
export const TC = process.env.LEAN_TOOLCHAIN_DIR || (TC_LEAN ? path.join(process.env.ELAN_HOME || path.join(os.homedir(), '.elan'), 'toolchains', `leanprover--lean4---v${TC_LEAN}`) : '');
const MC = process.env.MATHLIB_CLONE ? { dir: process.env.MATHLIB_CLONE } : pinMathlibClone();
export const MATHLIB_CLONE = MC.dir;
export const MATHLIB_CLONE_WHY = MC.why || '';
export const DOCKER_IMAGE = process.env.QED64_TOOLCHAIN_IMAGE || 'qed64-toolchain:emsdk-6.0.5';

const HINTS = {
  QED64_REPO: "a QED64 checkout at the pinned commit with QED64's binaries built (only for pin and stage: the heavy path, docs/BUILD-FROM-SOURCE.md; QED64's sources are the submodule deps/qed64)",
  QED64_KERNEL_BUILD: "the target pin's wasm64 kernel build dir, or a ':'-separated list of kernel builds that holds it (native/stage1, mathlib/, BUILT-COMMIT; built from https://github.com/FawadHa1der/lean4 branch qed64-wasm64)",
  QED64_KERNEL_SRC: 'the kernel source checkout (https://github.com/FawadHa1der/lean4, branch qed64-wasm64)',
  LEAN4GAME_DIR: 'a wasm64 lean4game checkout',
  LEAN_TOOLCHAIN_DIR: TC_LEAN ? `the stock Lean v${TC_LEAN} toolchain of the target pin (elan toolchain install leanprover/lean4:v${TC_LEAN}; ${TC_FROM})`
    : `the stock Lean toolchain of the target pin, whose Lean version did not resolve: ${TC_FROM}`,
  MATHLIB_CLONE: MATHLIB_CLONE_WHY || "the target pin's Mathlib clone (W/mathlib4.<first 8 hex of its lock's toolchain.mathlib.commit>, or the legacy W/mathlib4 at that commit)",
};
/** The value of a required path variable; throws a clear error when it is unset (or, for QED64_KERNEL_BUILD, names no
 *  kernel build of the target pin: K_FROM) or does not exist. */
export function need(name) {
  const v = name === 'LEAN_TOOLCHAIN_DIR' ? TC : name === 'MATHLIB_CLONE' ? MATHLIB_CLONE : name === 'QED64_KERNEL_BUILD' ? K : (process.env[name] || '');
  const hint = HINTS[name] || 'see qed64-showcase/.env.example';
  if (!v && name === 'QED64_KERNEL_BUILD' && K_CANDIDATES.length) throw new Error(`QED64_KERNEL_BUILD names no kernel build of the target pin: ${K_FROM}. Set it in the environment or in ${ENV_LOCAL} (template: .env.example).`);
  if (!v) throw new Error(`${name} is not set: ${hint}. Set it in the environment or in ${ENV_LOCAL} (template: .env.example).`);
  if (!fs.existsSync(v)) throw new Error(`${name}=${v} does not exist: ${hint}.`);
  return v;
}

// ---- the widget packages' Lean: stock Lean of another version cannot load their .lake oleans ----
/** The Lean version every widget package is built with (packages/<pkg>/lean-toolchain: one shared
 *  `leanprover/lean4:v<x>`). {version} or {version: null, why}. */
export function packagesLeanVersion(ws = WS) {
  const by = new Map();
  let pkgs = [];
  try { pkgs = fs.readdirSync(ws).filter((p) => fs.existsSync(path.join(ws, p, 'lean-toolchain'))).sort(); } catch { /* none */ }
  for (const p of pkgs) {
    const t = readTrimOr(path.join(ws, p, 'lean-toolchain')) || '';
    const v = /^leanprover\/lean4:v(\S+)$/.exec(t)?.[1] || `'${t}'`;
    by.set(v, [...(by.get(v) || []), p]);
  }
  if (!by.size) return { version: null, why: `no ${ws}/*/lean-toolchain` };
  if (by.size > 1 || !/^\d/.test([...by.keys()][0])) return { version: null, why: `${ws}/*/lean-toolchain do not name one leanprover/lean4:v<version>: ${[...by].map(([v, ps]) => `${v} (${ps.join(', ')})`).join('; ')}` };
  return { version: [...by.keys()][0] };
}
/** The Lean version toolchain dir `tc` runs (`<tc>/bin/lean --version`: "Lean (version 4.35.0, …)"), or null. */
export function toolchainLeanVersion(tc) {
  try {
    const out = execFileSync(path.join(tc, 'bin', 'lean'), ['--version'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 30000 });
    return /^Lean \(version ([^,\s)]+)/m.exec(out)?.[1] || null;
  } catch { return null; }
}
/** null when toolchain `tc` runs the Lean the widget packages are built with, else why not. Every consumer that loads the
 *  packages' .lake oleans (or Mathlib under them) with TC refuses on it before starting Lean: lean/goldens/lsp-golden.mjs,
 *  and through env.sh need_tc_packages golden-env.sh build|path, native-gate.sh superset, run-all.sh. */
export function tcPackagesMismatch(tc = TC, from = TC_FROM) {
  const want = packagesLeanVersion();
  if (!want.version) return `the widget packages' Lean version is unknown: ${want.why}`;
  const got = toolchainLeanVersion(tc);
  if (got === want.version) return null;
  let on = [];
  try {
    on = fs.readdirSync(path.join(SC, 'pins')).filter((id) => /^[0-9a-f]{7}$/.test(id) && !readJsonOr(path.join(SC, 'pins', id, 'pin.json'))?.retired)
      .filter((id) => pinLeanVersion(id).version === want.version).sort();
  } catch { /* no pins */ }
  return `the widget packages on this branch are built for Lean ${want.version} (packages/*/lean-toolchain), but LEAN_TOOLCHAIN_DIR=${tc} ${got ? `runs Lean ${got}` : 'has no runnable bin/lean'} (${from}): stock Lean cannot load another version's .lake oleans. Target a pin on Lean ${want.version} (${on.length ? on.map((id) => `SHOWCASE_PIN=${id}`).join(', ') : 'none registered here'}) or set LEAN_TOOLCHAIN_DIR to a v${want.version} toolchain`;
}
/** Expand ${VAR} placeholders in a configured path (e.g. pins/<id>/pin.json servedTrees); unset VAR -> clear error. */
export function expandPath(s) {
  return String(s).replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/g, (_, n) => {
    if (n === 'QED64_SHOWCASE_WORK') return W;
    const v = n === 'LEAN_TOOLCHAIN_DIR' ? TC : n === 'QED64_KERNEL_BUILD' ? K : process.env[n]; // K: never the raw list
    if (!v) throw new Error(`${s}: ${n} is not set: ${n === 'QED64_KERNEL_BUILD' && K_CANDIDATES.length ? K_FROM : HINTS[n] || 'see qed64-showcase/.env.example'}. Set it in the environment or in ${ENV_LOCAL}.`);
    return v;
  });
}

// run as a script: import.meta.url is the real path, argv[1] the one given (env.sh's SC is a logical `pwd`, so a checkout
// reached through a symlink, e.g. /tmp or a symlinked ~/code, would otherwise print nothing and exit 0)
const SELF = (() => { try { return fs.realpathSync(process.argv[1] || ''); } catch { return path.resolve(process.argv[1] || ''); } })();
if (process.argv[1] && SELF === fileURLToPath(import.meta.url)) {
  // node scripts/lib/env.mjs [--json]: print the resolved locations (no secrets live here)
  // node scripts/lib/env.mjs --sh: the pin-derived ones (and K_CANDIDATES, ':'-joined) as shell assignments, for
  //   scripts/lib/env.sh (always exit 0)
  // node scripts/lib/env.mjs --tc-packages [<toolchain dir> [<where it came from>]]: print TC-PACKAGES OK and exit 0 when
  //   it (default TC) runs the packages' Lean, else print why not and exit 2 (scripts/lib/env.sh need_tc_packages, which
  //   passes only on that answer)
  const sq = (s) => `'${String(s).split("'").join("'\\''")}'`;
  const tp = process.argv.indexOf('--tc-packages');
  if (tp > 0) {
    const why = tcPackagesMismatch(process.argv[tp + 1] || TC, process.argv[tp + 2] || TC_FROM);
    if (why) { console.log(why); process.exit(2); }
    console.log('TC-PACKAGES OK');
  } else if (process.argv.includes('--sh')) {
    console.log(Object.entries({ K, K_FROM, K_CANDIDATES: K_CANDIDATES.join(':'), TC, TC_LEAN, TC_FROM, MATHLIB_CLONE, MATHLIB_CLONE_WHY }).map(([k, v]) => `${k}=${sq(v)}`).join('\n'));
  } else {
    const r = { SC, REPO_ROOT, WS, W, Q, K, K_FROM, KR, LG, TC, TC_FROM, MATHLIB_CLONE, ...(MATHLIB_CLONE_WHY ? { MATHLIB_CLONE_WHY } : {}), DOCKER_IMAGE, envLocal: fs.existsSync(ENV_LOCAL) ? ENV_LOCAL : null };
    console.log(process.argv.includes('--json') ? JSON.stringify(r, null, 2) : Object.entries(r).map(([k, v]) => `${k}=${v || '(unset)'}`).join('\n'));
  }
}
