// Shared plumbing for the Stage-1 experiments (BUILD-PLAN §3, harness rules §8.1).
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

export const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const ENV = await import(path.join(SC, 'scripts/lib/env.mjs'));
export const BID = JSON.parse(fs.readFileSync(path.join(SC, 'QED64.lock.json'), 'utf8')).qed64.buildId; // the active pin's runtime
export const ORIGIN = process.env.ORIGIN || 'http://localhost:5190';
export const OUT = path.join(SC, 'out', 'experiments');
export const LOGS = ENV.LOGS;
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** free + inactive + speculative bytes (macOS vm_stat; Linux MemAvailable): scripts/lib/platform.mjs, the same measure
 *  as QED64's harness.mjs reclaimableBytes(). */
export const { reclaimableBytes } = await import(path.join(SC, 'scripts/lib/platform.mjs'));
export function strays() {
  return (spawnSync('pgrep', ['-fl', 'chrome-headless-shell'], { encoding: 'utf8' }).stdout || '').trim();
}
/** Refuse to boot unless >= 6 GB reclaimable and no chrome-headless-shell (docs/TESTING.md:85-90). */
export async function cooldown({ gb = 6, maxS = 180 } = {}) {
  const t0 = Date.now();
  for (;;) {
    const s = strays();
    const free = reclaimableBytes();
    if (!s && free >= gb * 2 ** 30) { console.log(`cooldown ok: ${(free / 2 ** 30).toFixed(1)} GiB reclaimable, no chrome-headless-shell`); return { reclaimableGiB: +(free / 2 ** 30).toFixed(2) }; }
    if (Date.now() - t0 > maxS * 1000) throw new Error(`cooldown refused: ${(free / 2 ** 30).toFixed(1)} GiB reclaimable; strays: ${s || 'none'}`);
    await sleep(2000);
  }
}

export const LAUNCH_ARGS = ['--enable-features=SharedArrayBuffer'];
export async function launch(opts = {}) {
  await cooldown();
  return chromium.launch({ args: LAUNCH_ARGS, ...opts });
}
export async function launchPersistent(userDataDir, opts = {}) {
  await cooldown();
  return chromium.launchPersistentContext(userDataDir, { args: LAUNCH_ARGS, ...opts });
}

/** Byte accounting per URL prefix from the page's network responses (bodies actually received). */
export function netMeter(page) {
  const m = { requests: [], byPrefix: {} };
  page.on('requestfinished', async (req) => {
    try {
      const res = await req.response();
      const sizes = await req.sizes();
      const u = new URL(req.url());
      const prefix = u.pathname.split('/').slice(0, 3).join('/');
      const rec = { url: u.pathname + u.search, status: res?.status(), body: sizes.responseBodySize, fromCache: res ? (res.fromServiceWorker() ? 'sw' : null) : null };
      m.requests.push(rec);
      const k = /\.snapz$/.test(u.pathname) ? 'snapz' : prefix;
      m.byPrefix[k] = (m.byPrefix[k] || 0) + (sizes.responseBodySize || 0);
    } catch {}
  });
  return m;
}

/** Poll qed64.status() until phase matches; returns {status, ms, phases:[{phase,t}]}. */
export async function waitPhase(target, re = /^ready$/, { timeoutMs = 240000, minVersion = -1, fail = /^(dead|halted|headerRefused)$/ } = {}) {
  const t0 = Date.now(); const phases = []; let last = null;
  for (;;) {
    const s = await target.evaluate(() => { try { return globalThis.qed64?.status?.() ?? null; } catch (e) { return { err: String(e) }; } }).catch((e) => ({ err: String(e) }));
    const ph = s?.phase ?? (s?.err ? 'evalError' : 'noHook');
    if (ph !== last) { phases.push({ phase: ph, t: Date.now() - t0 }); last = ph; }
    if (s && re.test(s.phase) && (s.version ?? 0) > minVersion) return { status: s, ms: Date.now() - t0, phases };
    if (s && fail.test(s.phase || '') && !re.test(s.phase)) return { status: s, ms: Date.now() - t0, phases, failed: true };
    if (Date.now() - t0 > timeoutMs) return { status: s, ms: Date.now() - t0, phases, timedOut: true };
    await sleep(250);
  }
}

/** Install the diagnostics/RPC tap on qed64.relay.toClient (§8.1 oracle). */
export async function installTap(target) {
  return target.evaluate(() => {
    const r = globalThis.qed64.relay;
    if (r.__tapped) return 'already';
    const o = r.toClient.bind(r);
    globalThis.__pub = []; globalThis.__rpc = []; globalThis.__srv = [];
    r.toClient = (m) => {
      try {
        if (m.method === 'textDocument/publishDiagnostics') globalThis.__pub.push(m.params);
        else if (m.method) globalThis.__srv.push({ method: m.method, params: JSON.stringify(m.params ?? null).slice(0, 400) });
        else if (m.id !== undefined) globalThis.__rpc.push({ id: m.id, ok: m.result !== undefined, err: m.error ?? null });
      } catch {}
      return o(m);
    };
    r.__tapped = true;
    return 'installed';
  });
}

export function consoleWatch(page) {
  const w = { errors: [], pageErrors: [], crashed: false, tail: [] };
  page.on('console', (m) => { const t = `${m.type()}: ${m.text().slice(0, 300)}`; w.tail.push(t); if (w.tail.length > 60) w.tail.shift(); if (m.type() === 'error') w.errors.push(t); });
  page.on('pageerror', (e) => w.pageErrors.push(String(e).slice(0, 300)));
  page.on('crash', () => { w.crashed = true; });
  return w;
}

export function writeResult(id, obj) {
  fs.mkdirSync(OUT, { recursive: true });
  const p = path.join(OUT, `${id}.json`);
  fs.writeFileSync(p, JSON.stringify({ id, at: new Date().toISOString(), origin: ORIGIN, ...obj }, null, 2) + '\n');
  console.log(`wrote ${path.relative(SC, p)}  pass=${obj.pass}`);
  return p;
}

/** Bytes served per path since `fromLine` in the server log (serve.mjs request log). */
export function serverLogSince(fromLine, port = 5190) {
  const p = path.join(LOGS, `serve-${port}.log`);
  const lines = fs.readFileSync(p, 'utf8').split('\n');
  return { lines: lines.slice(fromLine).filter(Boolean), end: lines.length - 1 };
}
export function serverLogLength(port = 5190) {
  return fs.readFileSync(path.join(LOGS, `serve-${port}.log`), 'utf8').split('\n').length - 1;
}
export function summarizeServerLog(lines) {
  const out = { requests: 0, bytes: 0, snapzBytes: 0, status: {}, snapz: [] };
  for (const l of lines) {
    const m = /^\S+ (GET|HEAD) (\S+) (\d+) (\d+)\/(\d+)/.exec(l);
    if (!m) continue;
    out.requests++; out.bytes += +m[4]; out.status[m[3]] = (out.status[m[3]] || 0) + 1;
    if (/\.snapz/.test(m[2])) { out.snapzBytes += +m[4]; out.snapz.push(`${m[1]} ${m[2]} ${m[3]} ${m[4]}`); }
  }
  return out;
}
