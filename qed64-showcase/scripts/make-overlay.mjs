#!/usr/bin/env node
// make-overlay.mjs — BUILD-PLAN §5 C7: the ?snapshots= overlay the STOCK page boots from.
//
//   node scripts/make-overlay.mjs w7|w8     -> out/overlay/snapshots/widgets7|widgets8/
//
// index.json has exactly two entries:
//   init     copied verbatim from the bake-out index (itself the served entry, see bake.sh / judge J5)
//   mathlib  the bake's `widgets` entry with name "mathlib"; url stays "/snapshots/widgets.<d16>.snapz",
//            which the page re-roots to /snapshots/widgets7/… (qed64-boot.ts:96-106)
// The stock page only loads the names init and mathlib (resident-session.ts:85,127; main.ts:361,386);
// its OPFS key becomes mathlib.<d16> and never collides with the stock mathlib.bf13acc4… key.
// Both .snapz files are APFS clones (cp -c) of the bake output, beside the index.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { targetPinId, targetBuildId, storePath } = await import(path.join(SC, 'scripts/lib/pins.mjs'));
const tag = process.argv[2];
if (!['w7', 'w8'].includes(tag)) { console.error('usage: make-overlay.mjs w7|w8'); process.exit(2); }
// the TARGET pin's runtime stores (SHOWCASE_PIN=<id>, else the active pin). The destination is the REAL store dir
// out/runtimes/<buildId>/overlay/widgetsN: removing and recreating the active LINK path out/overlay/snapshots/widgetsN
// would replace the pin link with a real directory (`pin current` FAIL "real"; found in the pin D lane)
const src = storePath(`bake-out-${tag}`);
const dst = storePath(`overlay/widgets${tag.slice(1)}`, { real: true });
console.log(`  pin ${targetPinId()}, runtime ${targetBuildId()}: ${src} -> ${dst}`);
const idx = JSON.parse(fs.readFileSync(path.join(src, 'index.json'), 'utf8'));
const init = idx.snapshots.find((s) => s.name === 'init');
const wg = idx.snapshots.find((s) => s.name === 'widgets');
if (!init || !wg || idx.snapshots.length !== 2) { console.error(`bake-out index must hold exactly init + widgets: ${idx.snapshots.map((s) => s.name)}`); process.exit(1); }
fs.rmSync(dst, { recursive: true, force: true });
fs.mkdirSync(dst, { recursive: true });
for (const e of [init, wg]) execFileSync('cp', ['-c', path.join(src, path.basename(e.url)), path.join(dst, path.basename(e.url))]);
const out = { schema: 'qed64.snapshot-index/v1', snapshots: [init, { ...wg, name: 'mathlib' }] };
fs.writeFileSync(path.join(dst, 'index.json'), JSON.stringify(out, null, 2));
for (const f of fs.readdirSync(dst)) {
  const st = fs.statSync(path.join(dst, f));
  console.log(`  ${f}  ${st.size} B  nlink ${st.nlink}`);
}
console.log(`OVERLAY ${dst}: init ${init.url} + mathlib ${wg.url} (raw ${wg.bytes} B, imports ${wg.imports.join(',')})`);
