// deploy-env.mjs — the Cloudflare deploy target from infra/deploy.env, overridden by environment variables of the
// same name. One place for remote / bucket / prefix / worker name, so wrangler.toml, the upload commands and the
// manifest's R2 keys cannot disagree. scripts/lib/deploy-common.sh (bash) calls this file's CLI, so the shell scripts
// and the JS apply exactly the same rules:
//
//   node scripts/lib/deploy-env.mjs           prints R2_REMOTE=… R2_BUCKET=… R2_PREFIX=… WORKER_NAME=… (one per line)
//                                             or exits 3 with the reason (nothing is contacted, nothing is written)
//
// SHARED-BUCKET GUARD. The default bucket qed64-artifacts is SHARED: QED64 serves its production objects from the
// bucket ROOT (runtime/, profiles/, snapshots/ — QED64 infra/worker.js ARTIFACT_PREFIXES) and wasm64-lean4game from
// lean4game/. An empty or foreign R2_PREFIX there would make an upload overwrite another app's MUTABLE names
// (runtime-manifest.json, profiles/index.json, snapshots/index.json, *.manifest.json). lean4game falls back to its
// own prefix on an empty value (`PREFIX=${R2_PREFIX:-lean4game}`); here an empty or foreign prefix in the shared
// bucket is REFUSED instead, loudly, because it almost always means a half-applied own-bucket setup (R2_PREFIX=
// without R2_BUCKET=…) or a variable left over from another app's session:
//   * prefix '' or one inside a foreign namespace (lean4game/…, runtime/…, profiles/…, snapshots/…): always refused;
//   * any other prefix than qed64-showcase/ (e.g. a staging prefix qed64-showcase-staging/): refused unless
//     ALLOW_SHARED_PREFIX=1 is set deliberately.
// Own bucket (any other R2_BUCKET): any prefix, including '' — set R2_BUCKET and R2_PREFIX TOGETHER.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const KEYS = ['R2_REMOTE', 'R2_BUCKET', 'R2_PREFIX', 'WORKER_NAME'];
export const SHARED_BUCKET = 'qed64-artifacts';
export const SHARED_PREFIX = 'qed64-showcase/';
/** Namespaces of the other apps in the shared bucket: QED64's root artifact dirs and wasm64-lean4game's prefix. */
export const FOREIGN_NAMESPACES = ['runtime/', 'profiles/', 'snapshots/', 'lean4game/'];

/** "qed64-showcase" -> "qed64-showcase/", "" stays "" (own bucket), anything unsafe throws. */
export function normalisePrefix(p) {
  const v = p === '' || p.endsWith('/') ? p : `${p}/`;
  if (!/^(?:[A-Za-z0-9][A-Za-z0-9._-]*\/)*$/.test(v)) throw new Error(`R2_PREFIX ${JSON.stringify(p)}: want "" or segments of [A-Za-z0-9._-] ending in "/"`);
  return v;
}

/** Throws unless (bucket, prefix) is safe: see SHARED-BUCKET GUARD above. */
export function checkSharedBucket(bucket, prefix, env = process.env) {
  if (bucket !== SHARED_BUCKET || prefix === SHARED_PREFIX) return;
  if (prefix === '') {
    throw new Error(`R2_PREFIX is empty but R2_BUCKET is the SHARED bucket ${SHARED_BUCKET}, whose root holds QED64's production objects: `
      + `an upload would overwrite QED64's runtime-manifest.json and indexes. Own-bucket mode needs R2_BUCKET and R2_PREFIX changed TOGETHER `
      + `(e.g. R2_BUCKET=qed64-showcase-artifacts R2_PREFIX=); for the shared bucket unset R2_PREFIX (default ${SHARED_PREFIX})`);
  }
  const foreign = FOREIGN_NAMESPACES.find((n) => prefix === n || prefix.startsWith(n));
  if (foreign) {
    throw new Error(`R2_PREFIX ${JSON.stringify(prefix)} is inside ${JSON.stringify(foreign)}, another app's namespace in the shared bucket ${SHARED_BUCKET} `
      + `(${foreign === 'lean4game/' ? 'wasm64-lean4game' : "QED64's root"}); refused, no override. Unset R2_PREFIX (default ${SHARED_PREFIX})`);
  }
  if (env.ALLOW_SHARED_PREFIX !== '1') {
    throw new Error(`R2_PREFIX ${JSON.stringify(prefix)} in the shared bucket ${SHARED_BUCKET}: the showcase's prefix is ${SHARED_PREFIX}. `
      + `Unset R2_PREFIX, or set ALLOW_SHARED_PREFIX=1 deliberately (e.g. for a separate staging prefix)`);
  }
}

export function loadDeployEnv(env = process.env) {
  const file = path.join(SC, 'infra/deploy.env');
  const out = {};
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    const m = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
    if (m) out[m[1]] = m[2];
  }
  for (const k of KEYS) {
    if (env[k] !== undefined) out[k] = env[k];
    if (out[k] === undefined) throw new Error(`infra/deploy.env has no ${k}`);
  }
  out.R2_PREFIX = normalisePrefix(out.R2_PREFIX);
  for (const k of ['R2_REMOTE', 'R2_BUCKET', 'WORKER_NAME']) if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(out[k])) throw new Error(`${k} ${JSON.stringify(out[k])} is not a plain name`);
  checkSharedBucket(out.R2_BUCKET, out.R2_PREFIX, env);
  return Object.fromEntries(KEYS.map((k) => [k, out[k]]));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const E = loadDeployEnv();
    // every value matched [A-Za-z0-9._/-]* above, so these lines are safe to read back in the shell
    for (const k of KEYS) console.log(`${k}=${E[k]}`);
  } catch (e) {
    console.error(`deploy target refused: ${e.message}`);
    process.exit(3);
  }
}
