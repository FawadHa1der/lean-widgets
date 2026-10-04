// browser-lock.mjs — where the HOST-WIDE browser lock lives (the same resolution as scripts/with-browser-lock.sh
// --print-lock): BROWSER_LOCK_FILE (tests only), else <BROWSER_LOCK_DIR>/browser.lock, default
// ~/.cache/host-browser-lock/browser.lock. A command run by the wrapper also gets HOST_BROWSER_LOCK_FILE, which wins.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export function browserLockFile(env = process.env) {
  if (env.HOST_BROWSER_LOCK_FILE) return env.HOST_BROWSER_LOCK_FILE;
  if (env.BROWSER_LOCK_FILE) return env.BROWSER_LOCK_FILE;
  return path.join(env.BROWSER_LOCK_DIR || path.join(os.homedir(), '.cache', 'host-browser-lock'), 'browser.lock');
}
/** The lock's owner line ("<lane> <pid> <iso-time>"), or null when the lock is free. */
export function browserLockOwner(env = process.env) {
  try { return fs.readFileSync(browserLockFile(env), 'utf8').trim(); } catch { return null; }
}
