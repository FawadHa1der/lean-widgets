// X1 — the server is correct: QED64's own preflight against serve.mjs (BUILD-PLAN §3 X1).
// preflight.mjs runs IN PLACE from the active pin's QED64 sources (the submodule deps/qed64); it is read-only without
// --run-dir (preflight.mjs:149-150),
// and its boot mode only launches Playwright's chromium (preflight.mjs:113-143) into a temp profile.
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { BID, ORIGIN, cooldown, writeResult } from './lib.mjs';
import { storePath, activePinId } from '../../scripts/lib/pins.mjs';
const Q = storePath('qed64', { id: activePinId() }); // QED64's sources at the active pin (source dependency)

const pre = path.join(Q, 'tests/adversarial/preflight.mjs');
const url = `${ORIGIN}/${process.argv[2] ? `?snapshots=${process.argv[2]}` : ''}`;
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
