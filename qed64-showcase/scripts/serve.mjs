#!/usr/bin/env node
// serve.mjs — local origin for the QED64 showcase (BUILD-PLAN §7.1). Node http, no dependencies.
//
// Routes, first match wins:
//   1. /showcase/...             -> $SC/gallery/...                     (/showcase/ -> index.html)
//   2. /snapshots/<dir>/...      -> the pin's runtime store out/runtimes/<buildId>/overlay/<o>/ for the pin's SERVED overlay
//                                   directories <dir> = overlayDir(<o>, pin) of widgets7 and widgets8 (scripts/lib/pins.mjs:
//                                   '<o>.<bid16>', the pin.json v3 "per-runtime" directory; resolved
//                                   ONCE at start), else $SC/out/overlay/snapshots/<dir>/... (only when that dir exists: the
//                                   UX suite's own fixture overlays, e.g. ux-unpaired-<pid>). A bare logical name
//                                   (widgets7, widgets8) is NEVER served through that fixture route: for a per-runtime pin
//                                   out/overlay/snapshots/widgets8 is the active link, possibly of another pin, and
//                                   production serves that path from whatever R2 holds there, so a gallery that still
//                                   framed /snapshots/widgets8/ would pass locally and fail live. It falls through to
//                                   route 3 (a 404 unless the release ships such a file).
//   3. /runtime/ /profiles/ /snapshots/ -> $R/public/...
//   4. everything else           -> $R/dist/...                         (/ -> index.html)
// Every response: COOP same-origin, COEP require-corp, CORP same-origin; Content-Length; no
// Content-Encoding; Cache-Control by QED64's own isImmutable() (imported from the served pin's QED64 sources, the
// submodule deps/qed64 or the pin's worktree, scripts/lib/qed64-src.mjs: infra/edge-worker.js, the library
// infra/worker.js imports). HEAD answered; missing
// files are 404 (never an SPA fallback). ETag + If-None-Match -> 304 (revalidation, like production).
//
// The pin (scripts/lib/pins.mjs; pins are keyed by QED64 commit) is fixed when the server starts: the active pin, or
// SHOWCASE_PIN=<id> to serve a staged pin (e.g. to gate a candidate on another port without switching). Every response
// carries `X-Showcase-Pin: <id> <buildId>`, so `showcase.sh serve/ux` can refuse a server that serves another pin than the
// active one (a pin switch never changes what a running server serves), and `X-Showcase-Api: <apiRevision>|none|invalid`
// (the served release's dist/qed64-build.json, read at start; see API_HEADER). /showcase/pin.json is sent with
// Cache-Control: no-store, so the headers the gallery reads from it never come from a cached response (no 304).
// Env: PORT (default 5190), HOST (default: listen on 127.0.0.1 and ::1), QUIET=1 (no request log), SHOWCASE_PIN=<id>,
//      GALLERY_DIR=<dir>  serve /showcase/ from <dir> instead of gallery/ (tests/ux/bringup/mutants.sh serves mutated copies)
//      CHAOS=<regex>:<afterBytes>:<times>  cut the first <times> responses whose path matches <regex>
//      after <afterBytes> body bytes (socket destroyed mid-stream).
// Log: one line per response: ISO time, method, path, status, bytes sent/Content-Length, ms, [route].
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { activePinId, pinDescriptor, releaseOf, outRtDir, storePath, overlayDir, OVERLAYS: PIN_OVERLAYS } = await import(path.join(SC, 'scripts/lib/pins.mjs'));
const PIN = process.env.SHOWCASE_PIN || activePinId();
const BID = pinDescriptor(PIN).buildId;
const R = releaseOf(PIN);
const PIN_HEADER = `${PIN} ${BID}`;
// The served release's embedding-contract revision, read ONCE here like the pin: QED64 writes dist/qed64-build.json (schema
// qed64.build/v1; apiRevision since the embedding contract v1, deps/qed64/docs/EMBEDDING.md §4); releases of pins A–E have
// none. Every response carries `X-Showcase-Api: <apiRevision>` (or `none`: a legacy page), so the gallery (gallery.js
// servedBuild) and the UX suite (tests/ux/lib/qed64.mjs GALLERY_PIN) learn the served page's mode from the pin.json response
// without probing /qed64-build.json (a 404 on a legacy release). A file of another schema, or one that cannot be parsed:
// `X-Showcase-Api: invalid` (ALWAYS a value, so a response never lacks the header: the gallery treats anything but a revision
// or 'none' as absent and probes, whose fallback ignores such a file too: pin.json decides; the UX suite refuses it).
// The deployed Worker sends neither header.
const API_HEADER = (() => {
  const f = path.join(R, 'dist', 'qed64-build.json');
  if (!fs.existsSync(f)) return 'none';
  let b; try { b = JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { console.error(`WARNING: ${f} is not JSON (${e.message}): X-Showcase-Api invalid`); return 'invalid'; }
  if (!b || b.schema !== 'qed64.build/v1') { console.error(`WARNING: ${f} schema ${JSON.stringify(b && b.schema)}, want qed64.build/v1: X-Showcase-Api invalid`); return 'invalid'; }
  return typeof b.apiRevision === 'string' && b.apiRevision ? b.apiRevision : 'none';
})();
// the pin's paired overlays, resolved now (the active links may be switched later; this server keeps serving its pin),
// keyed by the SERVED directory (pins.mjs overlayDir: widgets8.<bid16>, the per-runtime directory)
const PINNED_OVERLAYS = Object.fromEntries(PIN_OVERLAYS.map((o) => [overlayDir(o, PIN), path.join(outRtDir(BID), 'overlay', o)]));
const GALLERY = process.env.GALLERY_DIR ? path.resolve(process.env.GALLERY_DIR) : path.join(SC, 'gallery'); // GALLERY_DIR: mutation tests only
const OVERLAYS = path.join(SC, 'out', 'overlay', 'snapshots');
const PORT = Number(process.env.PORT || 5190);
const HOSTS = process.env.HOST ? [process.env.HOST] : ['127.0.0.1', '::1']; // loopback only, both stacks
const QUIET = process.env.QUIET === '1';

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8', '.map': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm', '.snapz': 'application/octet-stream', '.ttf': 'font/ttf', '.woff': 'font/woff',
  '.woff2': 'font/woff2', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8', '.lean': 'text/plain; charset=utf-8', '.md': 'text/plain; charset=utf-8',
};
function mimeOf(p) {
  if (/\.part-\d+$/.test(p)) return 'application/octet-stream';
  return MIME[path.extname(p).toLowerCase()] || 'application/octet-stream';
}
// QED64's cache rule, not a copy: imported from the served pin's QED64 sources. infra/edge-worker.js (QED64's library,
// 84d594e on, so every registered pin) exports it with no other import; QED64's infra/worker.js also imports the
// toolchain release record and builds its Worker at load, so it is never imported here.
const QED64_INFRA = path.join(storePath('qed64', { id: PIN }), 'infra');
const ISIMMUTABLE_SRC = 'edge-worker.js';
const { isImmutable } = await import(pathToFileURL(path.join(QED64_INFRA, ISIMMUTABLE_SRC)).href);
if (typeof isImmutable !== 'function') throw new Error(`${path.join(QED64_INFRA, ISIMMUTABLE_SRC)} exports no isImmutable`);

let chaos = null;
if (process.env.CHAOS) {
  const s = process.env.CHAOS; const b = s.lastIndexOf(':'); const a = s.lastIndexOf(':', b - 1);
  chaos = { re: new RegExp(s.slice(0, a)), after: Number(s.slice(a + 1, b)), times: Number(s.slice(b + 1)) };
  if (!(chaos.after >= 0) || !(chaos.times >= 0)) throw new Error(`bad CHAOS=${s} (want <regex>:<afterBytes>:<times>)`);
}

function resolve(pathname) {
  const segs = pathname.split('/');
  if (segs.some((s) => s === '..' || s.includes('\0') || s.includes('\\'))) return null;
  if (pathname === '/showcase') return { redirect: '/showcase/' };
  if (pathname.startsWith('/showcase/')) return { route: 'showcase', file: path.join(GALLERY, pathname.slice('/showcase/'.length)) };
  const m = /^\/snapshots\/([^/]+)\/(.*)$/.exec(pathname);
  if (m && PINNED_OVERLAYS[m[1]] && fs.existsSync(PINNED_OVERLAYS[m[1]])) return { route: `overlay:${m[1]}`, file: path.join(PINNED_OVERLAYS[m[1]], m[2]) };
  // fixture overlays: any other directory under out/overlay/snapshots/, but never a bare logical name (F7: see route 2)
  if (m && !PINNED_OVERLAYS[m[1]] && !PIN_OVERLAYS.includes(m[1]) && fs.existsSync(path.join(OVERLAYS, m[1])) && fs.statSync(path.join(OVERLAYS, m[1])).isDirectory())
    return { route: `overlay:${m[1]}`, file: path.join(OVERLAYS, m[1], m[2]) };
  if (/^\/(runtime|profiles|snapshots)\//.test(pathname)) return { route: 'public', file: path.join(R, 'public', pathname) };
  return { route: 'dist', file: path.join(R, 'dist', pathname) };
}

function baseHeaders(pathname) {
  return {
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'require-corp',
    'Cross-Origin-Resource-Policy': 'same-origin',
    'X-Showcase-Pin': PIN_HEADER,
    'X-Showcase-Api': API_HEADER,
    'Cache-Control': pathname === '/showcase/pin.json' ? 'no-store' : isImmutable(pathname) ? 'public, max-age=31536000, immutable' : 'public, max-age=0, must-revalidate',
  };
}

function handler(req, res) {
  const t0 = Date.now();
  let sent = 0; let route = '-';
  const url = new URL(req.url, 'http://x');
  let pathname;
  try { pathname = decodeURIComponent(url.pathname); } catch { pathname = null; }
  const log = (status, len, note = '') => {
    if (!QUIET) console.log(`${new Date().toISOString()} ${req.method} ${req.url} ${status} ${sent}/${len} ${Date.now() - t0}ms [${route}]${note}`);
  };
  const plain = (status, body, extra = {}) => {
    const b = Buffer.from(body);
    res.writeHead(status, { ...baseHeaders(pathname || '/'), 'Content-Type': 'text/plain; charset=utf-8', 'Content-Length': b.length, 'Cache-Control': 'no-store', ...extra });
    if (req.method !== 'HEAD') { res.end(b); sent = b.length; } else res.end();
    log(status, b.length);
  };
  if (req.method !== 'GET' && req.method !== 'HEAD') return plain(405, 'method not allowed\n', { Allow: 'GET, HEAD' });
  if (!pathname) return plain(400, 'bad path\n');
  const r = resolve(pathname);
  if (!r) return plain(400, 'bad path\n');
  if (r.redirect) { res.writeHead(301, { ...baseHeaders(pathname), Location: r.redirect, 'Content-Length': 0 }); res.end(); return log(301, 0); }
  route = r.route;
  let file = r.file; let st;
  try { st = fs.statSync(file); if (st.isDirectory()) { file = path.join(file, 'index.html'); st = fs.statSync(file); } } catch { st = null; }
  if (!st || !st.isFile()) return plain(404, `not found: ${pathname}\n`);
  const etag = `"${st.size.toString(16)}-${Math.floor(st.mtimeMs).toString(16)}"`;
  const headers = { ...baseHeaders(pathname), 'Content-Type': mimeOf(file), 'Content-Length': st.size, ETag: etag, 'Last-Modified': st.mtime.toUTCString() };
  if (req.headers['if-none-match'] === etag) {
    const { 'Content-Length': _cl, 'Content-Type': _ct, ...h304 } = headers;
    res.writeHead(304, h304); res.end(); return log(304, 0);
  }
  res.writeHead(200, headers);
  if (req.method === 'HEAD') { res.end(); return log(200, st.size, ' HEAD'); }
  const cut = chaos && chaos.times > 0 && chaos.re.test(pathname) ? (chaos.times--, chaos.after) : -1;
  const stream = fs.createReadStream(file, { highWaterMark: 1 << 20 });
  stream.on('data', (d) => {
    if (cut >= 0 && sent + d.length > cut) {
      const part = d.subarray(0, Math.max(0, cut - sent));
      stream.destroy(); sent += part.length;
      // flush the bytes before the cut, then kill the socket (client sees a truncated body)
      res.write(part, () => setTimeout(() => { log(200, st.size, ` CHAOS-CUT@${sent}`); res.socket?.destroy(); }, 50)); return;
    }
    sent += d.length;
    if (!res.write(d)) { stream.pause(); res.once('drain', () => stream.resume()); }
  });
  stream.on('end', () => { res.end(); log(200, st.size); });
  stream.on('error', (e) => { res.destroy(e); log(500, st.size, ` ${e.code}`); });
  res.on('close', () => { if (!res.writableFinished && !stream.destroyed) { stream.destroy(); log(499, st.size, ' client-abort'); } });
}
const servers = HOSTS.map((h) => http.createServer(handler).listen(PORT, h));
servers[0].on('listening', () => {
  console.log(`serve.mjs pid=${process.pid} listening on ${HOSTS.join(',')} port ${PORT} (http://localhost:${PORT}/)  pin=${PIN} (${BID}${process.env.SHOWCASE_PIN ? ', SHOWCASE_PIN' : ', active'}) api=${API_HEADER} release=${path.relative(SC, R)} gallery=${path.relative(SC, GALLERY)} overlays=${path.relative(SC, path.join(outRtDir(BID), 'overlay'))}[${Object.keys(PINNED_OVERLAYS).join(',')}]+${path.relative(SC, OVERLAYS)} cache-rule=${ISIMMUTABLE_SRC}${chaos ? ` CHAOS=${chaos.re}:${chaos.after}:${chaos.times}` : ''}`);
  if (!fs.existsSync(path.join(R, 'dist', 'index.html'))) console.log(`WARNING: ${R}/dist/index.html missing — run scripts/pin-qed64.mjs pin`);
});
for (const s of servers) s.on('error', (e) => { console.error(`listen error: ${e.message}`); process.exit(1); });
for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => { for (const s of servers) s.close(); process.exit(0); });
