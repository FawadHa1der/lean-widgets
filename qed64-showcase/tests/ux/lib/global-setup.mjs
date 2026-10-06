// Global setup: the browser lock must be held (npm run test:ux wraps the run in scripts/with-browser-lock.sh), the
// server on :5190 must answer (started here, and stopped in teardown, only if nobody else runs it), the run dir exists.
// UX_ORIGIN=<origin> (+ UX_PIN=<id> for a STAGED pin served there by `SHOWCASE_PIN=<id> PORT=<p> scripts/serve-start.sh`):
// the suite tests that server instead, never starts one, and requires it to serve UX_PIN (default: the active pin). Such a
// run is recorded but never a verdict (scripts/lib/ux-record.mjs whyNotVerdict: UX_ORIGIN).
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { SC, RUN_DIR, RUN_ID, ORIGIN, UX_PIN, HEADED_ALL, CHANNEL, GALLERY_PIN, API, API_REVISION, lockHeld, serverUp, reclaimableGiB } from './qed64.mjs';
export default async function globalSetup() {
  const lock = lockHeld();
  const meta = { run: RUN_ID, startedAt: new Date().toISOString(), lock, origin: ORIGIN, uxPin: UX_PIN, headed: HEADED_ALL, ...(CHANNEL ? { channel: CHANNEL } : {}), startedServer: false, reclaimableGiB: +reclaimableGiB().toFixed(1) };
  if (process.env.UX_ORIGIN) {
    if (!serverUp(ORIGIN)) throw new Error(`UX_ORIGIN=${ORIGIN} does not answer /showcase/pin.json; start it first (e.g. SHOWCASE_PIN=<id> PORT=<port> scripts/serve-start.sh)`);
  } else if (!serverUp()) {
    const r = spawnSync(path.join(SC, 'scripts/serve-start.sh'), [], { encoding: 'utf8' });
    if (r.status !== 0 || !serverUp()) throw new Error(`could not start serve.mjs: ${r.stdout} ${r.stderr}`);
    meta.startedServer = true; meta.serverStart = r.stdout.trim();
  }
  // the pin.json the served gallery reads, and the mode the suite branches on (lib/qed64.mjs GALLERY_PIN / API: under UX_PIN
  // with the active pin's gallery, the staged release's own apiRevision, which the gallery follows too)
  const pin = GALLERY_PIN;
  meta.pin = { id: pin.pin, buildId: pin.buildId, qed64: pin.qed64 && pin.qed64.commit, apiRevision: API_REVISION, shell: pin.shell ?? null, mode: API ? 'v1' : 'legacy', modeSource: pin.modeSource || 'pin.json', ...(pin.pinJsonApiRevision !== undefined ? { pinJsonApiRevision: pin.pinJsonApiRevision } : {}), ...(pin.servedVia ? { servedVia: pin.servedVia } : {}) };
  // the server must serve the ACTIVE pin's release (serve.mjs fixes its pin at start: X-Showcase-Pin "<id> <buildId>"):
  // two pins can share a buildId, so a server left over from before a `showcase.sh pin use` would test the wrong shell
  const P = await import(path.join(SC, 'scripts/lib/pins.mjs'));
  const want = UX_PIN ? `${UX_PIN} ${P.pinDescriptor(UX_PIN).buildId}` : `${P.activePinId()} ${P.activeBuildId()}`;
  const h = spawnSync('curl', ['-sI', '--max-time', '5', `${meta.origin}/`], { encoding: 'utf8' }).stdout || '';
  meta.servedPin = ((/^x-showcase-pin:\s*(.+?)\s*$/im.exec(h) || [])[1]) || null;
  if (meta.servedPin !== want) throw new Error(`${meta.origin} serves pin '${meta.servedPin}', not the ${UX_PIN ? 'UX_PIN' : 'active'} pin '${want}': restart it (scripts/showcase.sh stop; scripts/showcase.sh serve)`);
  meta.node = process.version;
  fs.mkdirSync(RUN_DIR, { recursive: true });
  fs.writeFileSync(path.join(RUN_DIR, 'run-meta.json'), `${JSON.stringify(meta, null, 2)}\n`);
  console.log(`UX run ${RUN_ID} -> ${path.relative(SC, RUN_DIR)} (server ${meta.startedServer ? 'started by the suite' : 'already running'}; ${meta.reclaimableGiB} GiB reclaimable)`);
}
