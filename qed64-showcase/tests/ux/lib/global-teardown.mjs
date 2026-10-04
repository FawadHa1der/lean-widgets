// Global teardown: merge out/ux/<run>/tests/*.json into out/ux/<run>/metrics.json; stop :5190 only if setup started it.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { SC, RUN_DIR, RUN_ID } from './qed64.mjs';
export default async function globalTeardown() {
  const metaP = path.join(RUN_DIR, 'run-meta.json');
  const meta = fs.existsSync(metaP) ? JSON.parse(fs.readFileSync(metaP, 'utf8')) : {};
  const dir = path.join(RUN_DIR, 'tests');
  const tests = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith('.json')).sort().map((f) => JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'))) : [];
  const out = { run: RUN_ID, meta, finishedAt: new Date().toISOString(), tests: Object.fromEntries(tests.map((t) => [t.id, t])) };
  fs.writeFileSync(path.join(RUN_DIR, 'metrics.json'), `${JSON.stringify(out, null, 2)}\n`);
  console.log(`wrote ${path.relative(SC, path.join(RUN_DIR, 'metrics.json'))} (${tests.length} tests)`);
  if (meta.startedServer) console.log(spawnSync(path.join(SC, 'scripts/serve-stop.sh'), [], { encoding: 'utf8' }).stdout.trim());
}
