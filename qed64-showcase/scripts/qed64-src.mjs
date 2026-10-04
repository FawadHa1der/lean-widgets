#!/usr/bin/env node
// qed64-src.mjs — CLI of scripts/lib/qed64-src.mjs (QED64 as a SOURCE dependency: the submodule deps/qed64 at the active
// pin's commit, a git worktree $W/qed64-pins/<id> for every other pin). Default pin: SHOWCASE_PIN, else the active pin.
//   node scripts/qed64-src.mjs dir [<id>]              the source dir (exit 1 with a hint when it is not checked out)
//   node scripts/qed64-src.mjs ensure [<id>|--all]     init the submodule / add the pin's worktree when missing
//   node scripts/qed64-src.mjs check [<id>|--all]      OK/FAIL: HEAD == commit, no tracked file modified, active: gitlink
import { requireSrc, ensureSrc, checkSrc, worktreeDir } from './lib/qed64-src.mjs';
const P = await import('./lib/pins.mjs');
const [cmd, arg] = process.argv.slice(2);
const ids = arg === '--all' ? P.listPins().map((p) => p.id) : [arg || P.targetPinId()];
let act = null; try { act = P.activePinId(); } catch { /* none */ }
try {
  if (cmd === 'dir') { const id = ids[0]; console.log(requireSrc(P.pinDescriptor(id).qed64.commit, id)); }
  else if (cmd === 'ensure') for (const id of ids) console.log(`pin ${id}: ${ensureSrc(P.pinDescriptor(id).qed64.commit, id)}`);
  else if (cmd === 'check') {
    let bad = 0;
    const fs = await import('node:fs');
    for (const id of ids) {
      const c = P.pinDescriptor(id).qed64.commit;
      // --all in a checkout that never bootstrapped a staged pin (no release dir, no worktree): reported, not a failure
      if (arg === '--all' && id !== act && !fs.existsSync(P.releaseDir(id)) && !fs.existsSync(worktreeDir(id))) { console.log(`NOT MATERIALIZED pin ${id} (no release/${id}, no worktree): scripts/showcase.sh bootstrap --pin ${id}`); continue; }
      for (const r of checkSrc(c, id, { active: id === act })) { console.log(`${r.ok ? 'OK  ' : 'FAIL'} ${r.msg}`); if (!r.ok) bad++; }
    }
    console.log(bad ? `QED64-SRC FAILED (${bad})` : 'QED64-SRC OK');
    process.exit(bad ? 1 : 0);
  } else { console.error('usage: qed64-src.mjs dir [<id>] | ensure [<id>|--all] | check [<id>|--all]'); process.exit(2); }
} catch (e) { console.error(`qed64-src ${cmd}: ${e.message}`); process.exit(1); }
