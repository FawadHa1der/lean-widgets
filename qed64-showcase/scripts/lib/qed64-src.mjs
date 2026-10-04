// qed64-src.mjs — QED64 as a SOURCE dependency (docs/ARCHITECTURE.md "Source dependency"). This project never copies
// QED64's code: it reads QED64's sources at a pin's commit from
//
//   the git submodule  qed64-showcase/deps/qed64   checked out at the SERVED (active) pin's commit; its gitlink IS the
//                                                   served pin's source pin (`verify` checks gitlink == HEAD == lock)
//   a git worktree     $QED64_SHOWCASE_WORK/qed64-pins/<id>   for every other registered pin (staged pins), made on demand
//                                                   from the submodule's OWN repository (`git -C deps/qed64 worktree add`),
//                                                   so no other QED64 checkout on the machine is ever read or written
//
// srcDir(commit, id) answers "where are QED64's sources at this pin": the submodule when its HEAD is that commit, else
// the pin's worktree. Nothing here edits a tracked QED64 file; build outputs that QED64 itself ignores (dist/,
// node_modules/) may be created by `showcase.sh bootstrap` (npm ci + npm run build:site, QED64's own build).
//
// CLI: scripts/qed64-src.mjs (default pin: the target pin, i.e. SHOWCASE_PIN or the active pin):
//   node scripts/qed64-src.mjs dir [<id>]        print the source dir (exit 1 with a hint when it is not there)
//   node scripts/qed64-src.mjs ensure [<id>|--all]
//                                                    the submodule initialized (git submodule update --init) and, for a
//                                                    pin other than the submodule's commit, its worktree (fetching the
//                                                    commit from the submodule's origin when it is not present)
//   node scripts/qed64-src.mjs check [<id>|--all]
//                                                    OK/FAIL lines: HEAD == the pin's commit, no tracked file modified;
//                                                    for the active pin also gitlink (index) == HEAD == lock commit
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

import { SC, REPO_ROOT, W } from './env.mjs';

export const SUBMODULE = path.join(SC, 'deps', 'qed64');
export const SUBMODULE_REL = path.relative(REPO_ROOT, SUBMODULE).split(path.sep).join('/'); // qed64-showcase/deps/qed64
export const UPSTREAM = 'https://github.com/FawadHa1der/QED64.git';
export const WORKTREES = path.join(W, 'qed64-pins');
export const worktreeDir = (id) => path.join(WORKTREES, id);

const git = (dir, ...a) => execFileSync('git', ['-C', dir, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 1 << 30 }).trim();
const tryGit = (dir, ...a) => { try { return git(dir, ...a); } catch { return null; } };
const isCheckout = (dir) => fs.existsSync(path.join(dir, '.git'));

/** HEAD of a checkout, or null. */
export const headOf = (dir) => (isCheckout(dir) ? tryGit(dir, 'rev-parse', 'HEAD') : null);
/** The submodule's HEAD (null when not initialized). */
export const submoduleHead = () => headOf(SUBMODULE);
/** The commit the outer repository records for the submodule (the gitlink in the index; null if absent). */
export function gitlinkCommit() {
  const l = tryGit(REPO_ROOT, 'ls-files', '-s', '--', SUBMODULE_REL);
  const m = l && /^160000 ([0-9a-f]{40}) /.exec(l);
  return m ? m[1] : null;
}

/** Where QED64's sources at `commit` live: the submodule if its HEAD is that commit, else the worktree of pin `id`. */
export function srcDir(commit, id = commit.slice(0, 7)) {
  if (submoduleHead() === commit) return SUBMODULE;
  return worktreeDir(id);
}
/** srcDir, but throws a clear error when that checkout is missing or at another commit. */
export function requireSrc(commit, id = commit.slice(0, 7)) {
  const d = srcDir(commit, id);
  const h = headOf(d);
  if (h === commit) return d;
  const hint = d === SUBMODULE || !isCheckout(SUBMODULE)
    ? `run: git submodule update --init ${SUBMODULE_REL}  (or: scripts/showcase.sh bootstrap)`
    : `run: node scripts/qed64-src.mjs ensure ${id}  (or: scripts/showcase.sh bootstrap --pin ${id})`;
  throw new Error(`QED64 sources for pin ${id} (${commit.slice(0, 12)}) are not checked out: ${d} ${h ? `is at ${h.slice(0, 12)}` : 'does not exist'}; ${hint}`);
}

/** Make the sources of pin `id` (QED64 commit `commit`) available; returns the directory. Logs what it does. */
export function ensureSrc(commit, id = commit.slice(0, 7), log = console.log) {
  if (!isCheckout(SUBMODULE)) {
    log(`qed64-src: initializing the submodule ${SUBMODULE_REL} (git submodule update --init)`);
    execFileSync('git', ['-C', REPO_ROOT, 'submodule', 'update', '--init', '--', SUBMODULE_REL], { stdio: 'inherit' });
  }
  if (submoduleHead() === commit) return SUBMODULE;
  const d = worktreeDir(id);
  if (headOf(d) === commit) return d;
  if (fs.existsSync(d)) throw new Error(`${d} exists but is not a checkout of ${commit.slice(0, 12)} (HEAD ${headOf(d) || 'none'}); move it aside`);
  if (tryGit(SUBMODULE, 'cat-file', '-e', `${commit}^{commit}`) === null) {
    log(`qed64-src: fetching ${commit.slice(0, 12)} into the submodule's repository from its origin`);
    execFileSync('git', ['-C', SUBMODULE, 'fetch', '--quiet', 'origin', commit], { stdio: 'inherit' });
  }
  fs.mkdirSync(WORKTREES, { recursive: true });
  // QED64 scripts run from a worktree resolve their npm dependencies (e.g. tests/adversarial/preflight.mjs: playwright)
  // by walking up the directory tree, as they do from deps/qed64 (which reaches qed64-showcase/node_modules)
  const nm = path.join(WORKTREES, 'node_modules');
  if (!fs.existsSync(nm) && fs.existsSync(path.join(SC, 'node_modules'))) fs.symlinkSync(path.join(SC, 'node_modules'), nm);
  log(`qed64-src: git worktree add --detach ${d} ${commit.slice(0, 12)} (from the submodule's repository)`);
  execFileSync('git', ['-C', SUBMODULE, 'worktree', 'add', '--detach', d, commit], { stdio: 'inherit' });
  return d;
}

/** [{ok, msg}] for the sources of a pin: checkout at the commit, no tracked file modified; active: gitlink too. */
export function checkSrc(commit, id = commit.slice(0, 7), { active = false } = {}) {
  const out = [];
  const ok = (c, msg, d = '') => out.push({ ok: !!c, msg: `${msg}${d ? ' — ' + d : ''}` });
  const d = srcDir(commit, id);
  const rel = d.startsWith(SC + path.sep) ? path.relative(SC, d) : d.startsWith(W + path.sep) ? `$W/${path.relative(W, d)}` : d;
  const h = headOf(d);
  ok(h === commit, `QED64 sources ${rel}: HEAD == pin ${id} commit ${commit.slice(0, 12)}`, h ? h.slice(0, 12) : 'not checked out');
  if (h === commit) {
    const mod = tryGit(d, 'status', '--porcelain', '--untracked-files=no');
    ok(mod === '', `QED64 sources ${rel}: no tracked file modified (git status --untracked-files=no)`, mod === null ? 'git status failed' : mod.split('\n').slice(0, 3).join('; '));
  }
  if (active) {
    const g = gitlinkCommit();
    ok(g === commit && d === SUBMODULE, `submodule ${SUBMODULE_REL}: gitlink (index) == HEAD == the active pin's commit`, `gitlink ${g ? g.slice(0, 12) : 'none'}, served from ${rel}`);
  }
  return out;
}
