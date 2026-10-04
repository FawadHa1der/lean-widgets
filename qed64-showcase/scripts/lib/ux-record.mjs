#!/usr/bin/env node
// ux-record.mjs — the UX-run record and the ONE rule for when a run is a verdict (docs audit r3: a run could be stamped
// for a gallery it never tested). Used by scripts/showcase.sh (ux, gallery) and scripts/deploy-manifest.mjs (G2).
//
// A record (one JSON line in out/ux/showcase-ux-runs.jsonl, appended by `showcase.sh ux`):
//   {start, end, lane, rc, args, run, origin, uxOrigin,
//    galleryStart, galleryEnd   the LOCAL shipped-gallery content sha256 (scripts/lib/gallery-hash.mjs) before / after,
//    servedStart, servedEnd     the same hash over the files the origin under test actually SERVED (fetched over HTTP),
//    lockSha256, overlays       sha256 of QED64.lock.json and of each out/overlay/snapshots/<o>/index.json (at the start;
//                               *End copies at the end), i.e. which pin and which snapshot regions were under test,
//    pin                        "<pin id> <buildId>" of the active pin at the start (scripts/lib/pins.mjs; since 2026-10-02),
//    servedPinStart/End         the X-Showcase-Pin header the origin answered with before / after (serve.mjs fixes its pin
//                               at start, and two pins can share one buildId, so the lock alone cannot say what was served),
//    listed                     `playwright test --list` total for the same args (forbidOnly is on in the config),
//    report                     report.json stats {expected, unexpected, skipped, flaky} and the skipped test ids}
// A record is a VERDICT for (gallery, lock, overlays) only if ALL of these hold: rc 0; no args (the full suite); no
// UX_ORIGIN; galleryStart == galleryEnd == servedStart == servedEnd; lock and overlays unchanged during the run; for a
// record with `pin`: servedPinStart == servedPinEnd == pin (the server served the active pin's release); the
// report exists with 0 unexpected, 0 flaky, expected + skipped == listed, and nothing skipped except C19 (the optional
// headed run, which skips unless UX_HEADED=1); and the run was not headed.
// A record with `headed: true` (UX_HEADED_ALL=1: every test in a real Chrome for Testing window, the 'headed' project;
// final-gate lane) is NEVER a verdict: it is judged as a HEADED SIGN-OFF by the same checks, with C19 required to run
// (nothing skipped). Headed records are left out of laterFailures (they are a different browser, reported on their own).
//
// CLI:  served <origin>          print the served gallery content sha256 (exit 1 if any shipped file does not answer 200)
//       inputs                   print {lockSha256, overlays, pin} now
//       servedpin <origin>       print the origin's X-Showcase-Pin header ("<id> <buildId>"; exit 1 when absent)
//       report <run dir>         print {expected, unexpected, skipped, flaky, skippedIds} of <run dir>/report.json
//       verdict <record json>    print "VERDICT" or "NOT A VERDICT: <why>" (exit 0 either way)
//       freshness <gallery sha>  print the UX CURRENT / UX STALE line for that gallery (with the current lock + overlays)
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { galleryFiles, isShippedGalleryFile } from './gallery-hash.mjs';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const UX_RUNS = path.join(SC, 'out', 'ux', 'showcase-ux-runs.jsonl');
export const OVERLAYS = ['widgets7', 'widgets8'];
export const ALLOWED_SKIPS = ['C19'];
const sha = (b) => createHash('sha256').update(b).digest('hex');

/** The gallery content sha256 over what `origin` serves at /showcase/<file> for every LOCAL shipped file. */
export async function servedGalleryHash(origin) {
  const list = galleryFiles(path.join(SC, 'gallery')).filter(isShippedGalleryFile).sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
  const h = createHash('sha256'); const bad = [];
  for (const r of list) {
    let res;
    try { res = await fetch(`${origin.replace(/\/$/, '')}/showcase/${r.split('/').map(encodeURIComponent).join('/')}`, { headers: { 'accept-encoding': 'identity' }, cache: 'no-store' }); } catch (e) { bad.push(`${r}: ${e.message}`); continue; }
    if (res.status !== 200) { bad.push(`${r}: HTTP ${res.status}`); continue; }
    h.update(`${sha(Buffer.from(await res.arrayBuffer()))}  ${r}\n`);
  }
  return { contentSha256: bad.length ? null : h.digest('hex'), files: list.length, bad };
}
export async function inputs() {
  const ov = {};
  for (const o of OVERLAYS) { const f = path.join(SC, 'out', 'overlay', 'snapshots', o, 'index.json'); ov[o] = fs.existsSync(f) ? sha(fs.readFileSync(f)) : null; }
  let pin = null;
  try { const P = await import('./pins.mjs'); pin = `${P.activePinId()} ${P.activeBuildId()}`; } catch { /* no active pin: recorded as null */ }
  return { lockSha256: sha(fs.readFileSync(path.join(SC, 'QED64.lock.json'))), overlays: ov, pin };
}
/** The pin an origin serves: serve.mjs's X-Showcase-Pin header ("<id> <buildId>"), or null. */
export async function servedPin(origin) {
  try { const r = await fetch(`${origin.replace(/\/$/, '')}/`, { method: 'HEAD', cache: 'no-store' }); return r.headers.get('x-showcase-pin'); } catch { return null; }
}
export function reportOf(runDir) {
  const f = path.join(runDir, 'report.json');
  if (!fs.existsSync(f)) return null;
  let r; try { r = JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { return { error: `report.json: ${e.message}` }; }
  const tests = [];
  const walk = (s) => { for (const sp of s.specs || []) for (const t of sp.tests || []) tests.push({ id: sp.title.split(' ')[0], status: t.status }); for (const c of s.suites || []) walk(c); };
  for (const s of r.suites || []) walk(s);
  const st = r.stats || {};
  return { expected: st.expected, unexpected: st.unexpected, skipped: st.skipped, flaky: st.flaky, skippedIds: tests.filter((t) => t.status === 'skipped').map((t) => t.id), total: tests.length, errors: (r.errors || []).length };
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
/** [] when the record is a verdict, else the reasons it is not. */
export function whyNotVerdict(x) {
  const why = [];
  if (x.headed) why.push('a headed sign-off run (UX_HEADED_ALL=1): judged by whyNotSignOff, never a verdict');
  if (x.rc !== 0) why.push(`rc ${x.rc}`);
  if ((x.args || []).length) why.push(`a subset run (args ${JSON.stringify(x.args)})`);
  if (x.uxOrigin) why.push(`UX_ORIGIN=${x.origin} (another origin)`);
  if (!x.galleryStart || x.galleryStart !== x.galleryEnd) why.push('gallery/ changed during the run (or no hash)');
  if (!x.servedStart || x.servedStart !== x.galleryStart || x.servedEnd !== x.galleryEnd) why.push(`the server did not serve the local gallery (served ${String(x.servedStart).slice(0, 12)}…/${String(x.servedEnd).slice(0, 12)}… vs local ${String(x.galleryStart).slice(0, 12)}…)`);
  if (!x.lockSha256 || (x.lockSha256End && x.lockSha256End !== x.lockSha256)) why.push('QED64.lock.json changed during the run (or not recorded)');
  if (!x.overlays || (x.overlaysEnd && !same(x.overlaysEnd, x.overlays))) why.push('an overlay index changed during the run (or not recorded)');
  if (x.pin !== undefined && (!x.pin || x.servedPinStart !== x.pin || x.servedPinEnd !== x.pin || (x.pinEnd !== undefined && x.pinEnd !== x.pin)))
    why.push(`the server did not serve the active pin throughout (active ${x.pin}${x.pinEnd !== undefined && x.pinEnd !== x.pin ? ` -> ${x.pinEnd}` : ''}; served ${x.servedPinStart} / ${x.servedPinEnd})`);
  const r = x.report;
  if (!r || r.error) why.push(`no usable report.json (${r && r.error || 'missing'})`);
  else {
    if (r.unexpected !== 0) why.push(`${r.unexpected} unexpected`);
    if (r.flaky !== 0) why.push(`${r.flaky} flaky`);
    if (!(x.listed > 0) || r.expected + r.skipped !== x.listed) why.push(`expected ${r.expected} + skipped ${r.skipped} != listed ${x.listed}`);
    const extra = (r.skippedIds || []).filter((id) => !ALLOWED_SKIPS.includes(id));
    if (extra.length) why.push(`skipped beyond ${ALLOWED_SKIPS}: ${extra}`);
  }
  return why;
}
/** [] when a headed record (UX_HEADED_ALL=1) is a clean headed sign-off: every verdict check, and C19 ran (no skips). */
export function whyNotSignOff(x) {
  if (!x.headed) return ['not a headed run'];
  const why = whyNotVerdict({ ...x, headed: false });
  if (x.report && !x.report.error && (x.report.skippedIds || []).length) why.push(`skipped ${x.report.skippedIds} (a headed sign-off runs C19 too)`);
  return why;
}
/** The newest clean headed sign-off on exactly these inputs, or null. */
export function signOffFor({ gallery, lockSha256 = null, overlays = null }, runs = readRuns()) {
  return runs.filter((x) => x.headed && whyNotSignOff(x).length === 0 && x.galleryEnd === gallery && (!lockSha256 || x.lockSha256 === lockSha256)
    && (!overlays || Object.entries(overlays).every(([k, h]) => x.overlays && x.overlays[k] === h))).pop() || null;
}
export function readRuns(file = UX_RUNS) {
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean) : [];
}
/** The newest verdict run for exactly this gallery (and, when given, this lock and these overlay indexes). */
export function verdictFor({ gallery, lockSha256 = null, overlays = null }, runs = readRuns()) {
  const v = runs.filter((x) => whyNotVerdict(x).length === 0);
  const m = v.filter((x) => x.galleryEnd === gallery && (!lockSha256 || x.lockSha256 === lockSha256) && (!overlays || Object.entries(overlays).every(([k, h]) => x.overlays && x.overlays[k] === h))).pop() || null;
  return { match: m, last: v.pop() || null, recorded: runs.length };
}
/** Full-suite runs (no args, no UX_ORIGIN) on exactly these inputs that came AFTER `after` and were not verdicts: a green
 *  run followed by a red one on the same gallery + lock + overlays is not a clean bill of health (final lane: L9). */
export function laterFailures(after, { gallery, lockSha256, overlays }, runs = readRuns()) {
  const i = runs.indexOf(after);
  return runs.slice(i + 1).filter((x) => !x.headed && !(x.args || []).length && !x.uxOrigin && x.galleryEnd === gallery && x.lockSha256 === lockSha256
    && Object.entries(overlays).every(([k, h]) => x.overlays && x.overlays[k] === h)).map((x) => ({ run: x.run, why: whyNotVerdict(x) })).filter((x) => x.why.length);
}
export async function freshnessLine(gallery) {
  const { pin: _p, ...cur } = await inputs();
  const runs = readRuns();
  const { match, last, recorded } = verdictFor({ gallery, ...cur }, runs);
  const later = match ? laterFailures(match, { gallery, ...cur }, runs) : [];
  const note = later.length ? `; BUT ${later.length} later full run(s) on the same inputs were NOT A VERDICT (${later.map((x) => `${x.run}: ${x.why.join(', ')}`).join('; ')})` : '';
  const so = signOffFor({ gallery, ...cur }, runs);
  const soNote = so ? `; headed sign-off ${so.run} (${so.end}) on the same inputs` : '';
  return match ? `UX CURRENT: green full-suite showcase.sh ux run ${match.start}..${match.end} (lane ${match.lane}, run ${match.run}) was on this gallery, served as such, with this lock and these overlays${note}${soNote}`
    : `UX STALE: no verdict run on this gallery + lock + overlays (last verdict: ${last ? `${last.end} on ${String(last.galleryEnd).slice(0, 16)}…` : `none among ${recorded} recorded runs in out/ux/showcase-ux-runs.jsonl`}); run showcase.sh ux`;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [cmd, a] = process.argv.slice(2);
  if (cmd === 'served') { const r = await servedGalleryHash(a); if (!r.contentSha256) { console.error(`served gallery: ${r.bad.slice(0, 5).join('; ')}`); process.exit(1); } console.log(r.contentSha256); }
  else if (cmd === 'inputs') console.log(JSON.stringify(await inputs()));
  else if (cmd === 'servedpin') { const p = await servedPin(a); if (!p) { console.error(`no X-Showcase-Pin from ${a}`); process.exit(1); } console.log(p); }
  else if (cmd === 'report') console.log(JSON.stringify(reportOf(a)));
  else if (cmd === 'verdict') {
    const x = JSON.parse(a);
    if (x.headed) { const w = whyNotSignOff(x); console.log(w.length ? `NOT A HEADED SIGN-OFF (and never a verdict): ${w.join('; ')}` : 'HEADED SIGN-OFF (not a verdict)'); }
    else { const w = whyNotVerdict(x); console.log(w.length ? `NOT A VERDICT: ${w.join('; ')}` : 'VERDICT'); }
  }
  else if (cmd === 'freshness') console.log(await freshnessLine(a));
  else { console.error('usage: ux-record.mjs served <origin> | servedpin <origin> | inputs | report <run dir> | verdict <record json> | freshness <gallery sha256>'); process.exit(2); }
}
