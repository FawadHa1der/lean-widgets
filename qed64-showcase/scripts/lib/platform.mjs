// platform.mjs — the host facilities that differ between macOS and Linux, for Node (scripts/lib/platform.sh is the same
// for bash; see there for the rules).
//
//   PLATFORM                 'darwin' | 'linux' | other (process.platform)
//   reclaimableBytes()       macOS: free + inactive + speculative pages (vm_stat), as QED64's harness measures it;
//                            Linux: MemAvailable (/proc/meminfo); elsewhere 0 (callers then refuse, never guess)
//   cloneFile(src, dst)      a copy-on-write clone where the file system can (APFS clonefile on macOS, FICLONE/reflink on
//                            Linux), else a plain copy; always a new inode (never a hard link). fs.copyFileSync with
//                            COPYFILE_FICLONE is libuv's portable form of `cp -c` / `cp --reflink=auto`.
//   cloneTree(src, dst)      the same for a directory tree (files cloned, directories and symlinks re-created)
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const PLATFORM = process.platform;

export function reclaimableBytes() {
  if (PLATFORM === 'darwin') {
    const t = execFileSync('/usr/bin/vm_stat').toString();
    const page = Number((/page size of (\d+) bytes/.exec(t) || [])[1] || 16384);
    const get = (k) => Number(new RegExp(`${k}:\\s+(\\d+)`).exec(t)?.[1] ?? 0);
    return (get('Pages free') + get('Pages inactive') + get('Pages speculative')) * page;
  }
  if (PLATFORM === 'linux') {
    const m = /^MemAvailable:\s+(\d+)\s+kB/m.exec(fs.readFileSync('/proc/meminfo', 'utf8'));
    return m ? Number(m[1]) * 1024 : 0;
  }
  return 0;
}

export function cloneFile(src, dst) {
  fs.copyFileSync(src, dst, fs.constants.COPYFILE_FICLONE);
}

export function cloneTree(src, dst) {
  if (fs.existsSync(dst)) throw new Error(`cloneTree: ${dst} exists`);
  if (PLATFORM === 'darwin') { execFileSync('cp', ['-cR', src, dst]); return; }              // APFS clonefile per file
  if (PLATFORM === 'linux') { execFileSync('cp', ['-R', '--reflink=auto', src, dst]); return; } // reflink where supported
  const walk = (s, d) => {
    const st = fs.lstatSync(s);
    if (st.isSymbolicLink()) { fs.symlinkSync(fs.readlinkSync(s), d); return; }
    if (st.isDirectory()) {
      fs.mkdirSync(d, { mode: st.mode & 0o7777 });
      for (const e of fs.readdirSync(s)) walk(path.join(s, e), path.join(d, e));
      return;
    }
    if (st.isFile()) { cloneFile(s, d); fs.chmodSync(d, st.mode & 0o7777); fs.utimesSync(d, st.atime, st.mtime); return; }
    throw new Error(`cloneTree: unsupported file type ${s}`);
  };
  walk(src, dst);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  // node scripts/lib/platform.mjs: what this host reports (used by the Linux rehearsal log)
  console.log(JSON.stringify({ platform: PLATFORM, reclaimableGiB: +(reclaimableBytes() / 2 ** 30).toFixed(1), node: process.version }));
}
