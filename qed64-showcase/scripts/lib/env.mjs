// env.mjs — ONE place that says where everything lives (Node; scripts/lib/env.sh is the same for bash, same rules).
// Nothing machine-specific is hard-coded: the project root comes from this file's location, everything else from
// environment variables, optionally set in the gitignored qed64-showcase/.env.local (KEY=VALUE lines; template
// .env.example). A variable already set in the environment wins over .env.local. Importing this module applies
// .env.local to process.env, so child processes (bash scripts, node tools) see the same values.
//
//   SC  qed64-showcase/        REPO_ROOT  SC/..        WS  REPO_ROOT/packages (the widget packages)
//   W   QED64_SHOWCASE_WORK (default ~/.cache/lean-widgets/qed64-showcase-work)        LOGS  W/logs
//   Q   QED64_REPO (heavy path: pin, stage)   K  QED64_KERNEL_BUILD     KR  QED64_KERNEL_SRC     LG  LEAN4GAME_DIR   (read-only inputs)
//   TC  LEAN_TOOLCHAIN_DIR (default ~/.elan/toolchains/leanprover--lean4---v4.34.0)
//   DOCKER_IMAGE  QED64_TOOLCHAIN_IMAGE (default qed64-toolchain:emsdk-6.0.5)
// The read-only inputs are '' when unset; need('QED64_REPO') returns the path or throws a clear error.
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
export const TC = process.env.LEAN_TOOLCHAIN_DIR || path.join(process.env.ELAN_HOME || path.join(os.homedir(), '.elan'), 'toolchains', 'leanprover--lean4---v4.34.0');
export const DOCKER_IMAGE = process.env.QED64_TOOLCHAIN_IMAGE || 'qed64-toolchain:emsdk-6.0.5';

const HINTS = {
  QED64_REPO: "a QED64 checkout at the pinned commit with QED64's binaries built (only for pin and stage: the heavy path, docs/BUILD-FROM-SOURCE.md; QED64's sources are the submodule deps/qed64)",
  QED64_KERNEL_BUILD: 'the wasm64 kernel build dir (native/stage1, mathlib/, BUILT-COMMIT; built from https://github.com/FawadHa1der/lean4 branch qed64-wasm64)',
  QED64_KERNEL_SRC: 'the kernel source checkout (https://github.com/FawadHa1der/lean4, branch qed64-wasm64)',
  LEAN4GAME_DIR: 'a wasm64 lean4game checkout',
  LEAN_TOOLCHAIN_DIR: 'the stock Lean v4.34.0 toolchain (elan toolchain install leanprover/lean4:v4.34.0)',
};
/** The value of a required path variable; throws a clear error when it is unset or does not exist. */
export function need(name) {
  const v = name === 'LEAN_TOOLCHAIN_DIR' ? TC : (process.env[name] || '');
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
  const r = { SC, REPO_ROOT, WS, W, Q, K, KR, LG, TC, DOCKER_IMAGE, envLocal: fs.existsSync(ENV_LOCAL) ? ENV_LOCAL : null };
  console.log(process.argv.includes('--json') ? JSON.stringify(r, null, 2) : Object.entries(r).map(([k, v]) => `${k}=${v || '(unset)'}`).join('\n'));
}
