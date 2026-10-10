// X1 — the server is correct: QED64's own preflight against serve.mjs (BUILD-PLAN §3 X1).
// preflight.mjs runs IN PLACE from the active pin's QED64 sources (the submodule deps/qed64): pipeline/release/preflight.mjs
// where it exists (QED64 385a1ac on), else tests/adversarial/preflight.mjs (pins up to bf9d947; at 385a1ac a one-cycle
// shim). It is read-only without --run-dir, and its boot mode only launches Playwright's chromium into a temp profile.
//   node tests/experiments/x1-preflight.mjs [snapshots]   e.g. snapshots/widgets8: a logical overlay name (with or without
//   the snapshots/ prefix) is mapped to the active pin's SERVED directory (scripts/lib/pins.mjs overlayDir: widgets8 for
//   pins A–H, widgets8.<bid16> for a per-runtime pin); the result name keeps the argument as given
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { BID, ORIGIN, cooldown, writeResult } from './lib.mjs';
import { storePath, activePinId, overlayDir, OVERLAYS } from '../../scripts/lib/pins.mjs';
const Q = storePath('qed64', { id: activePinId() }); // QED64's sources at the active pin (source dependency)

const pre = ['pipeline/release/preflight.mjs', 'tests/adversarial/preflight.mjs'].map((p) => path.join(Q, p)).find((p) => fs.existsSync(p));
if (!pre) { console.error(`x1: no preflight.mjs in ${Q} (pipeline/release/ or tests/adversarial/)`); process.exit(2); }
const served = (arg) => { // snapshots/widgets8 -> snapshots/<dir>; anything else unchanged
  const m = /^(snapshots\/)?([^/]+)$/.exec(arg);
  return m && OVERLAYS.includes(m[2]) ? `${m[1] || ''}${overlayDir(m[2], activePinId())}` : arg;
};
const url = `${ORIGIN}/${process.argv[2] ? `?snapshots=${served(process.argv[2])}` : ''}`;
const run = (args) => {
  const t0 = Date.now();
  const r = spawnSync('node', [pre, '--url', url, ...args], { encoding: 'utf8', timeout: 600000 });
  const out = (r.stdout || '') + (r.stderr || '');
  process.stdout.write(out);
  return { args, exit: r.status, ms: Date.now() - t0, okLine: (out.match(/^PREFLIGHT (OK|REFUSED).*$/m) || [null])[0], output: out.trim().split('\n') };
};
const noBoot = run(['--no-boot']);
await cooldown();
const boot = run([]);
const okRe = new RegExp(`^PREFLIGHT OK buildId=${BID}\\b`);
const pass = noBoot.exit === 0 && boot.exit === 0 && okRe.test(noBoot.okLine || '') && okRe.test(boot.okLine || '');
writeResult(process.argv[2] ? `x1-${process.argv[2].replace(/\W+/g, '-')}` : 'x1', { pass, url, noBoot, boot });
process.exit(pass ? 0 : 1);
