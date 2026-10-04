// pins.mjs — the multi-pin model (docs/REPIN-LOG.md "Multiple pins"). ONE module that every script and test asks "which
// QED64 pin is active, and where do its files live", so no other file hardcodes a pin, a buildId or a release path.
//
// A PIN is keyed by its QED64 COMMIT (the first 7 hex digits, e.g. 1859b83), not by its runtime buildId: two pins can
// serve the same runtime with different shells and workers (1859b83 and 5ac5d00 both serve the kernel-0034 runtime, with
// different dist/ and public/workers/). Everything that depends on the shell or the vendored sources is per PIN;
// everything that depends only on the runtime (the binary pairing of snapshot regions to lean.wasm) is per RUNTIME and
// shared by every pin of that runtime:
//
//   per pin      pins/<id>/            pin.json (the descriptor: commit, promote, kernel, buildId, served base trees,
//                                      whether the page has QED64's built-in liveness, the expected main bundle),
//                                      QED64.lock.json, QED64-PIN, vendor-qed64/ (git archive of the pinned sources)
//                release/<id>/         the verified clone of QED64's dist/ + public/ at that commit
//   per runtime  out/runtimes/<bid>/   overlay/widgets7, overlay/widgets8 (the paired snapshot regions), headless/ (the
//                                      wasm verifiers' results: their inputs are the runtime, the raw regions and bakes,
//                                      and the vendored pipeline/snapshot probes, which are checked identical per runtime)
//                $W/runtimes/<bid>/    stage1/ (the runtime artifact), raw/, bake-out-w7|w8/, bake-work-w7|w8/,
//                                      BAKE-KEY-w7|w8.txt, bake-logs/ (the bake logs judge-bake.mjs reads)
//
// The ACTIVE pin is materialized by symlinks, switched by `scripts/showcase.sh pin use <id>` (scripts/pin-switch.mjs):
//   QED64.lock.json -> pins/<id>/QED64.lock.json      QED64-PIN -> pins/<id>/QED64-PIN
//   vendor/qed64 -> ../pins/<id>/vendor-qed64          out/headless -> runtimes/<bid>/headless
//   out/overlay/snapshots/widgets{7,8} -> ../../runtimes/<bid>/overlay/widgets{7,8}
//   $W/{stage1,raw,bake-out-w7,bake-out-w8,bake-work-w7,bake-work-w8,BAKE-KEY-w7.txt,BAKE-KEY-w8.txt,bake-logs} -> runtimes/<bid>/…
// and gallery/pin.json is regenerated from the active lock (scripts/build-gallery.mjs). So every existing path keeps
// working and always names the active pin; the active lock (its qed64.commit) is the single source of truth.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { W, expandPath } from './env.mjs';

export const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export { W };
export const ID_RE = /^[0-9a-f]{7}$/;
export const BID_RE = /^wasm64-[0-9a-f]{16}$/;
export const pinIdOf = (commit) => String(commit).slice(0, 7);

export const repoPinDir = (id) => path.join(SC, 'pins', id);
export const releaseDir = (id) => path.join(SC, 'release', id);
export const outRtDir = (bid) => path.join(SC, 'out', 'runtimes', bid);
export const wRtDir = (bid) => path.join(W, 'runtimes', bid);

// bake-logs: the bake's own log, metrics and RSS samples, which judge-bake.mjs reads (per runtime, like the bake itself)
export const W_ENTRIES = ['stage1', 'raw', 'bake-out-w7', 'bake-out-w8', 'bake-work-w7', 'bake-work-w8', 'BAKE-KEY-w7.txt', 'BAKE-KEY-w8.txt', 'bake-logs'];
export const OVERLAYS = ['widgets7', 'widgets8'];

const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));

/** Every registered pin descriptor (pins/<id>/pin.json), sorted by registration time. */
export function listPins() {
  const d = path.join(SC, 'pins');
  if (!fs.existsSync(d)) return [];
  return fs.readdirSync(d).filter((x) => ID_RE.test(x) && fs.existsSync(path.join(d, x, 'pin.json')))
    .map((x) => readJson(path.join(d, x, 'pin.json'))).sort((a, b) => String(a.registeredAt).localeCompare(String(b.registeredAt)));
}
export function pinDescriptor(id = activePinId()) {
  if (!ID_RE.test(String(id))) throw new Error(`pin id ${id} is not a 7-hex QED64 commit prefix (pins are keyed by commit)`);
  const f = path.join(repoPinDir(id), 'pin.json');
  if (!fs.existsSync(f)) throw new Error(`no pin descriptor ${path.relative(SC, f)} (registered pins: ${listPins().map((p) => p.id).join(', ') || 'none'})`);
  const p = readJson(f);
  if (p.id !== id || pinIdOf(p.qed64 && p.qed64.commit) !== id) throw new Error(`${path.relative(SC, f)} names id ${p.id} / commit ${p.qed64 && p.qed64.commit}, not ${id}`);
  if (!BID_RE.test(p.buildId || '')) throw new Error(`${path.relative(SC, f)}: buildId ${p.buildId} is not a wasm64 buildId`);
  return p;
}
export function lockOf(id) { return readJson(path.join(repoPinDir(id), 'QED64.lock.json')); }

/** The active links for pin `id`: [link path, target RELATIVE to the link's directory, absolute store path, kind]. */
export function activeLinks(id) {
  const bid = pinDescriptor(id).buildId;
  const L = [
    [path.join(SC, 'QED64.lock.json'), path.join('pins', id, 'QED64.lock.json'), path.join(repoPinDir(id), 'QED64.lock.json'), 'file'],
    [path.join(SC, 'QED64-PIN'), path.join('pins', id, 'QED64-PIN'), path.join(repoPinDir(id), 'QED64-PIN'), 'file'],
    [path.join(SC, 'vendor', 'qed64'), path.join('..', 'pins', id, 'vendor-qed64'), path.join(repoPinDir(id), 'vendor-qed64'), 'dir'],
    [path.join(SC, 'out', 'headless'), path.join('runtimes', bid, 'headless'), path.join(outRtDir(bid), 'headless'), 'dir'],
  ];
  for (const o of OVERLAYS) L.push([path.join(SC, 'out', 'overlay', 'snapshots', o), path.join('..', '..', 'runtimes', bid, 'overlay', o), path.join(outRtDir(bid), 'overlay', o), 'dir']);
  for (const e of W_ENTRIES) L.push([path.join(W, e), path.join('runtimes', bid, e), path.join(wRtDir(bid), e), e.endsWith('.txt') ? 'file' : 'dir']);
  return L;
}

/** The active lock (QED64.lock.json, a link into pins/<id>/). */
export function activeLock() { return readJson(path.join(SC, 'QED64.lock.json')); }

// ---- the TARGET pin of a build/verification tool (stage, bake, judge, pair-check, overlay, preflight, headless) ----
// SHOWCASE_PIN=<id> makes those tools act on a registered pin's OWN stores (pins/<id>/, release/<id>/,
// $W/runtimes/<bid>/, out/runtimes/<bid>/) without switching: the active links are then neither read nor written, so a
// staged pin (a new runtime) is brought up while another pin stays served (pin D lane, 2026-10-02). serve.mjs already
// used SHOWCASE_PIN the same way (serve a staged pin on another port). Without SHOWCASE_PIN the target is the active pin
// and every store is addressed through its active link, exactly as before.
export const TARGET_ENV = 'SHOWCASE_PIN';
export function targetPinId() {
  const e = process.env[TARGET_ENV];
  if (e) { pinDescriptor(e); return e; } // throws for a malformed or unregistered id
  return activePinId();
}
export const targetBuildId = () => pinDescriptor(targetPinId()).buildId;
/** true when SHOWCASE_PIN names a pin (then stores are addressed directly, never through the active links) */
export const targetIsExplicit = () => !!process.env[TARGET_ENV];
/** A store of the target pin. Per runtime: the W_ENTRIES ('stage1', 'raw', 'bake-out-w7', …, 'bake-logs'), 'headless'
 *  and 'overlay/widgets7|widgets8'; per pin: 'vendor' (vendor-qed64), 'lock' (QED64.lock.json), 'QED64-PIN'.
 *  Without SHOWCASE_PIN: the active link path (vendor/qed64, $W/stage1, out/headless, out/overlay/snapshots/widgets8 …);
 *  with it: the store path itself. `real: true` resolves links (the store path; for tools that delete-and-recreate). */
export function storePath(entry, { id = targetPinId(), real = false } = {}) {
  const viaLink = !targetIsExplicit() && !real;
  const bid = pinDescriptor(id).buildId;
  const pinStore = { vendor: ['vendor-qed64', path.join(SC, 'vendor', 'qed64')], lock: ['QED64.lock.json', path.join(SC, 'QED64.lock.json')],
    'QED64-PIN': ['QED64-PIN', path.join(SC, 'QED64-PIN')] };
  if (entry in pinStore) return viaLink ? pinStore[entry][1] : path.join(repoPinDir(id), pinStore[entry][0]);
  if (W_ENTRIES.includes(entry)) return viaLink ? path.join(W, entry) : path.join(wRtDir(bid), entry);
  if (entry === 'headless') return viaLink ? path.join(SC, 'out', 'headless') : path.join(outRtDir(bid), 'headless');
  const m = /^overlay\/(widgets[78])$/.exec(entry);
  if (m) return viaLink ? path.join(SC, 'out', 'overlay', 'snapshots', m[1]) : path.join(outRtDir(bid), 'overlay', m[1]);
  throw new Error(`storePath: unknown store '${entry}'`);
}
export function activePinId() {
  const c = activeLock().qed64.commit;
  const id = pinIdOf(c);
  if (!/^[0-9a-f]{40}$/.test(c || '') || !ID_RE.test(id)) throw new Error(`QED64.lock.json qed64.commit ${c} is not a commit`);
  return id;
}
export function activeBuildId() {
  const b = activeLock().qed64.buildId;
  if (!BID_RE.test(b || '')) throw new Error(`QED64.lock.json qed64.buildId ${b} is not a wasm64 buildId`);
  return b;
}
/** The release dir of a pin, from its lock (release.dir), which must be release/<id>. */
export function releaseOf(id = activePinId()) {
  const lock = lockOf(id);
  const want = path.join('release', id);
  if (!lock.release || lock.release.dir !== want) throw new Error(`pins/${id}/QED64.lock.json release.dir ${lock.release && lock.release.dir} != ${want}`);
  return path.join(SC, want);
}

/** The QED64 page's main module bundle (/assets/index-<hash>.js) of a pin's release: the one <script type="module"> in
 *  release/<id>/dist/index.html. Bundle names are content hashes, so they differ per pin (even per shell of one runtime). */
export function mainBundle(id = activePinId()) {
  const html = fs.readFileSync(path.join(releaseDir(id), 'dist', 'index.html'), 'utf8');
  const m = [...html.matchAll(/<script\b[^>]*type="module"[^>]*src="(\/assets\/[^"]+\.js)"/g)].map((x) => x[1]);
  if (m.length !== 1) throw new Error(`release/${id}/dist/index.html has ${m.length} module scripts, want exactly 1`);
  return m[0];
}
export const MAIN_BUNDLE_TOKEN = '@qed64-main-bundle';
/** tests/ux/selectors.json with every "@qed64-main-bundle" resolved to the active pin's main bundle (the console allowlist
 *  names the QED64 bundle by URL; the name is a content hash, so a literal would tie the tests to one pin). */
export function resolveSelectors(raw, id = activePinId()) {
  return JSON.parse(raw.split(`"${MAIN_BUNDLE_TOKEN}"`).join(JSON.stringify(mainBundle(id))));
}
export function loadSelectors(id = activePinId()) {
  return resolveSelectors(fs.readFileSync(path.join(SC, 'tests', 'ux', 'selectors.json'), 'utf8'), id);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [cmd, a, b] = process.argv.slice(2);
  // release / field / main-bundle default to the TARGET pin (SHOWCASE_PIN, else the active pin; see targetPinId)
  const id = () => a || targetPinId();
  try {
    if (cmd === 'active') console.log(activePinId());
    else if (cmd === 'active-bid') console.log(activeBuildId());
    else if (cmd === 'target') console.log(targetPinId());
    else if (cmd === 'target-bid') console.log(targetBuildId());
    else if (cmd === 'store') console.log(storePath(a, { real: b === '--real' })); // store <entry> [--real]
    else if (cmd === 'release') console.log(releaseOf(id()));
    else if (cmd === 'field') { // field <dotted.path> [id]: one descriptor field (served trees for showcase.sh, …)
      const v = String(a).split('.').reduce((o, k) => (o == null ? o : o[k]), pinDescriptor(b || targetPinId()));
      if (v === undefined || v === null) { console.error(`pin.json has no ${a}`); process.exit(1); }
      // a configured path may name its root by placeholder (servedTrees: ${QED64_REPO}/work/…): expanded from the env
      console.log(typeof v === 'object' ? JSON.stringify(v) : (typeof v === 'string' ? expandPath(v) : v));
    } else if (cmd === 'main-bundle') console.log(mainBundle(id()));
    else if (cmd === 'list') for (const p of listPins()) console.log(`${p.id} ${p.buildId}`);
    else { console.error('usage: pins.mjs active | active-bid | target | target-bid | store <entry> [--real] | release [id] | field <path> [id] | main-bundle [id] | list'); process.exit(2); }
  } catch (e) { console.error(`pins.mjs ${cmd}: ${e.message}`); process.exit(1); }
}
