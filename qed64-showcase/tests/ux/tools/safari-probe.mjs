// Safari probe (last-mile lane, 2026-10-03): can THIS host's Safari be driven over WebDriver WITHOUT changing any
// setting, and if so, what does a visitor of /showcase/ see in it? It starts /usr/bin/safaridriver -p <port> (starting
// it changes nothing; `safaridriver --enable` and Safari's "Allow Remote Automation" are settings and are NOT touched),
// asks it for a session with a tiny W3C WebDriver client (fetch), and:
//   * if the session is refused, records the driver's exact error and stops (the one-time user action is documented);
//   * if it is created, opens --url, polls __showcase.status() (phase, caps, error card, status line) every 2 s up to
//     --max-s, takes screenshots (start, every --shot-s, at the end), deletes the session and stops the driver.
// Writes out/ux/$UX_RUN/explore/safari-<tag>.json and out/ux/$UX_RUN/screens/safari-<tag>-*.png. Run it under the browser
// lock: UX_RUN=<run> scripts/with-browser-lock.sh <lane> node tests/ux/tools/safari-probe.mjs --url http://localhost:5191/showcase/
import fs from 'node:fs';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const RUN_DIR = path.join(SC, 'out', 'ux', process.env.UX_RUN || 'adhoc');
const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const PORT = Number(arg('--port', '4445'));
const URL_ = arg('--url', 'http://localhost:5191/showcase/');
const TAG = arg('--tag', 'probe');
const MAX_S = Number(arg('--max-s', '120'));
const SHOT_S = Number(arg('--shot-s', '20'));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
fs.mkdirSync(path.join(RUN_DIR, 'explore'), { recursive: true }); fs.mkdirSync(path.join(RUN_DIR, 'screens'), { recursive: true });
const out = { tag: TAG, url: URL_, startedAt: new Date().toISOString(), host: {} };
out.host.safariVersion = (spawnSync('defaults', ['read', '/Applications/Safari.app/Contents/Info', 'CFBundleShortVersionString'], { encoding: 'utf8' }).stdout || '').trim();
out.host.safaridriver = (spawnSync('/usr/bin/safaridriver', ['--version'], { encoding: 'utf8' }).stdout || '').trim();
out.host.os = (spawnSync('sw_vers', ['-productVersion'], { encoding: 'utf8' }).stdout || '').trim();
const save = () => fs.writeFileSync(path.join(RUN_DIR, 'explore', `safari-${TAG}.json`), `${JSON.stringify(out, null, 1)}\n`);

const drv = spawn('/usr/bin/safaridriver', ['-p', String(PORT)], { stdio: ['ignore', 'pipe', 'pipe'] });
let drvLog = ''; drv.stdout.on('data', (d) => { drvLog += d; }); drv.stderr.on('data', (d) => { drvLog += d; });
let drvExit = null; drv.on('exit', (c, sig) => { drvExit = { code: c, signal: sig }; });
const base = `http://127.0.0.1:${PORT}`;
const wd = async (method, p, body) => {
  const r = await fetch(`${base}${p}`, { method, headers: { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
  const txt = await r.text(); let j = null; try { j = JSON.parse(txt); } catch { j = { raw: txt.slice(0, 500) }; }
  return { status: r.status, value: j && 'value' in j ? j.value : j };
};
let sid = null;
try {
  for (let i = 0; i < 50; i++) { try { out.driverStatus = await wd('GET', '/status'); break; } catch { if (drvExit) break; await sleep(200); } }
  if (!out.driverStatus) throw new Error(`safaridriver did not answer on :${PORT} (exit ${JSON.stringify(drvExit)}; log: ${drvLog.slice(0, 300)})`);
  console.log(`[safari] /status ${JSON.stringify(out.driverStatus)}`);
  const t = Date.now();
  const ns = await wd('POST', '/session', { capabilities: { alwaysMatch: { browserName: 'safari' } } });
  out.newSession = { httpStatus: ns.status, ms: Date.now() - t, error: ns.value && ns.value.error ? ns.value.error : null, message: ns.value && ns.value.message ? ns.value.message : null, capabilities: ns.value && ns.value.capabilities ? ns.value.capabilities : null };
  console.log(`[safari] POST /session -> HTTP ${ns.status} ${out.newSession.error ? `${out.newSession.error}: ${out.newSession.message}` : `session ${ns.value.sessionId}`}`);
  if (ns.status !== 200 || !ns.value.sessionId) { out.result = 'session refused'; throw Object.assign(new Error('session refused'), { refused: true }); }
  sid = ns.value.sessionId; out.result = 'session created';
  const nav = await wd('POST', `/session/${sid}/url`, { url: URL_ }); out.navigate = { httpStatus: nav.status, error: nav.value && nav.value.error ? nav.value : null };
  const probe = `const g = window.__showcase && window.__showcase.status();
    const vis = (el) => !!el && !el.hidden && getComputedStyle(el).display !== 'none' && getComputedStyle(el).visibility !== 'hidden';
    const t = (id) => { const e = document.getElementById(id); return e ? e.textContent.replace(/\\s+/g, ' ').trim() : null; };
    let boot = null; try { const d = document.getElementById('qed64-frame').contentDocument; boot = d && d.getElementById('bootlabel') ? { text: d.getElementById('bootlabel').textContent.trim(), nums: (d.getElementById('bootnums') || {}).textContent || null } : null; } catch (e) { boot = { error: String(e) }; }
    return { ua: navigator.userAgent, coi: self.crossOriginIsolated, sab: typeof SharedArrayBuffer, phase: g ? g.phase : null, caps: g ? g.caps : null, qed64: g && g.qed64 ? g.qed64.phase : null,
      errorVisible: vis(document.getElementById('error-card')), errorTitle: t('error-title'), errorDetail: t('error-detail'), checks: [...document.querySelectorAll('#error-checks li')].map((li) => li.className + ' ' + li.textContent.replace(/\\s+/g, ' ').trim()),
      status: t('status-text'), veil: vis(document.getElementById('stage-veil')) && !document.getElementById('stage-veil').classList.contains('is-hidden') ? t('veil-text') : null, title: document.title, boot };`;
  const shot = async (n) => { const r = await wd('GET', `/session/${sid}/screenshot`); if (r.status === 200 && typeof r.value === 'string') { const f = path.join(RUN_DIR, 'screens', `safari-${TAG}-${n}.png`); fs.writeFileSync(f, Buffer.from(r.value, 'base64')); return path.relative(RUN_DIR, f); } return `screenshot failed: HTTP ${r.status} ${JSON.stringify(r.value).slice(0, 200)}`; };
  out.polls = []; out.shots = []; const t1 = Date.now(); let nextShot = 0; let settled = 0;
  for (;;) {
    const el = Date.now() - t1;
    const r = await wd('POST', `/session/${sid}/execute/sync`, { script: probe, args: [] });
    const v = r.status === 200 ? r.value : { error: r.value };
    out.polls.push({ t: el, ...v });
    if (el >= nextShot * 1000) { out.shots.push({ t: el, file: await shot(`${String(Math.round(el / 1000)).padStart(3, '0')}s`), phase: v.phase }); nextShot += SHOT_S; }
    console.log(`[safari] ${(el / 1000).toFixed(0)} s phase ${v.phase} qed64 ${v.qed64} error ${v.errorVisible ? `"${v.errorTitle}"` : 'none'} veil ${v.veil}`);
    if (['ready', 'unsupported', 'error', 'halted', 'refused'].includes(v.phase)) { if (++settled >= 3) break; }
    if (el > MAX_S * 1000) break;
    await sleep(2000);
  }
  out.shots.push({ t: Date.now() - t1, file: await shot('final'), phase: out.polls[out.polls.length - 1].phase });
  out.final = out.polls[out.polls.length - 1];
} catch (e) { if (!e.refused) out.error = String(e.message).slice(0, 400); }
finally {
  if (sid) { try { out.deleteSession = (await wd('DELETE', `/session/${sid}`)).status; } catch (e) { out.deleteSession = String(e.message); } }
  drv.kill('SIGTERM'); await sleep(500);
  out.driverLog = drvLog.slice(0, 2000); out.driverExit = drvExit;
  out.summary = `${TAG}: Safari ${out.host.safariVersion} (${out.host.safaridriver}), macOS ${out.host.os}: ${out.result || out.error}${out.newSession && out.newSession.error ? ` — ${out.newSession.error}: ${out.newSession.message}` : ''}${out.final ? `; phase ${out.final.phase}, error card ${out.final.errorVisible ? `"${out.final.errorTitle}"` : 'none'}, caps ${JSON.stringify(out.final.caps && { ok: out.final.caps.ok, missing: out.final.caps.missing })}` : ''}`;
  console.log(`SUMMARY ${out.summary}`);
  save();
}
