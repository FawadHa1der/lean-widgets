#!/usr/bin/env node
// pin-switch.mjs — multiple QED64 pins, one active: list the registered pins, show and check the active one, switch it.
// The model and the store layout are in scripts/lib/pins.mjs (pins are keyed by QED64 COMMIT; the runtime-paired stores
// are shared per runtime buildId); the procedure is in docs/REPIN-LOG.md "Multiple pins".
// `scripts/showcase.sh pin list|current|check|use` calls this.
//
//   node scripts/pin-switch.mjs list                 every registered pin: label, runtime, status, store completeness,
//                                                    UX verdicts on its lock (out/ux/showcase-ux-runs.jsonl)
//   node scripts/pin-switch.mjs current              the active pin and every active link (exit 1 if a link is missing,
//                                                    is a real file/dir, or points into another pin's/runtime's store)
//   node scripts/pin-switch.mjs check <id> [--full]  the CHEAP check of a pin's stores (what `showcase.sh verify` runs for
//                                                    every staged pin): descriptor == lock; release/<id> file set and
//                                                    sizes == lock; main bundle == descriptor; the console-allowlist site
//                                                    line is the same notify code; vendor file set == QED64-PIN; the
//                                                    runtime stores: stage1 buildId, raw and bake files, overlays paired
//                                                    (index runtime, {init, mathlib}, sizes, init == the pin's stock init,
//                                                    mathlib == this runtime's bake). --full adds the release and vendor
//                                                    sha256s (pin-qed64.mjs verify --pin <id> does the whole chain)
//   node scripts/pin-switch.mjs use <id> [--dry-run] [--allow-incomplete] [--no-deploy]
//                                                    make <id> the active pin. Guards: registered; complete stores
//                                                    (--allow-incomplete only for bringing up a new runtime, whose stage1,
//                                                    bakes and overlays are then made through the active links); no
//                                                    serve.mjs of this repo that follows the active pin (it serves the
//                                                    release it started with; servers started with SHOWCASE_PIN=<id> are
//                                                    pinned explicitly and allowed), no bake, no headless run, no browser
//                                                    lock held by a showcase UX run. Every link is switched by an atomic
//                                                    rename(2) of a fresh symlink over the old one, the lock link LAST,
//                                                    with a journal (out/pins/switch-journal.json) so an interrupted
//                                                    switch is visible to `current` and is finished by re-running `use`.
//                                                    Then gallery/pin.json is regenerated (build-gallery.mjs), and the
//                                                    deploy inputs too when out/deploy exists (deploy-manifest generate +
//                                                    --stage-assets, which refuse/report on their own gates).
// Exit: 0 ok · 1 a check failed · 2 usage · 3 refused by a guard.
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { SC, W, ID_RE, OVERLAYS, activeLinks, activePinId, listPins, pinDescriptor, lockOf, repoPinDir, releaseDir, outRtDir, wRtDir, mainBundle } from './lib/pins.mjs';
import { readRuns, whyNotVerdict, whyNotSignOff } from './lib/ux-record.mjs';
import { browserLockFile } from './lib/browser-lock.mjs';

const argv = process.argv.slice(2);
const cmd = argv[0];
const flag = (f) => argv.includes(f);
const rel = (p) => (p.startsWith(SC + path.sep) ? path.relative(SC, p) : p.startsWith(W + path.sep) ? '$W/' + path.relative(W, p) : p);
const sha256File = (p) => createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const sha = (b) => createHash('sha256').update(b).digest('hex');
const exists = (p) => { try { fs.statSync(p); return true; } catch { return false; } };
const isLink = (p) => { try { return fs.lstatSync(p).isSymbolicLink(); } catch { return false; } };
const lexists = (p) => { try { fs.lstatSync(p); return true; } catch { return false; } };
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));

/** The state of every active link for `id`: ok | missing | real (a file/dir where the link belongs) | other | dangling. */
function linkStates(id) {
  return activeLinks(id).map(([link, target, store, kind]) => {
    let state, now = null;
    if (!lexists(link)) state = 'missing';
    else if (!isLink(link)) state = 'real';
    else { now = fs.readlinkSync(link); state = now === target ? (exists(store) ? 'ok' : 'dangling') : 'other'; }
    return { link, target, store, kind, state, now };
  });
}

/** The console-allowlist sites pinned by line (selectors.json "line0" on the main-bundle token): [{line0, text}]. */
function allowlistLineSites() {
  const raw = fs.readFileSync(path.join(SC, 'tests', 'ux', 'selectors.json'), 'utf8');
  const out = [];
  const walk = (o) => { if (Array.isArray(o)) o.forEach(walk); else if (o && typeof o === 'object') { if (o.line0 !== undefined) out.push({ line0: o.line0, url: o.url }); Object.values(o).forEach(walk); } };
  walk(JSON.parse(raw));
  return out;
}

/** Store completeness + cheap consistency of one pin. Returns [{ok, msg}]. */
function checkPin(id, { full = false } = {}) {
  const out = [];
  const ok = (c, msg, d = '') => out.push({ ok: !!c, msg: `${msg}${d ? ' — ' + d : ''}` });
  let desc = null, lock = null;
  try { desc = pinDescriptor(id); ok(true, `pins/${id}/pin.json: ${desc.label}`); } catch (e) { ok(false, e.message); return out; }
  try { lock = lockOf(id); } catch (e) { ok(false, `pins/${id}/QED64.lock.json: ${e.message}`); return out; }
  const bid = desc.buildId, q = lock.qed64 || {};
  ok(q.buildId === bid && q.commit === desc.qed64.commit && q.promote === desc.qed64.promote && q.kernel === desc.qed64.kernel,
    'lock qed64 {commit, promote, buildId, kernel} == descriptor', `${String(q.commit).slice(0, 12)} ${q.buildId} kernel ${String(q.kernel).slice(0, 10)}`);
  ok(lock.release && lock.release.dir === `release/${id}`, `lock release.dir == release/${id}`, lock.release && lock.release.dir);
  // release clone: the file set and sizes the lock records (full: sha256 too); nothing extra
  const R = releaseDir(id);
  const want = lock.release && lock.release.files ? lock.release.files : {};
  const bad = [];
  for (const [f, m] of Object.entries(want)) {
    const p = path.join(R, f);
    if (!exists(p)) { bad.push(`${f} missing`); continue; }
    if (fs.statSync(p).size !== m.bytes) bad.push(`${f} size`);
    else if (full && sha256File(p) !== m.sha256) bad.push(`${f} sha256`);
  }
  ok(Object.keys(want).length > 0 && !bad.length, `release/${id}: ${Object.keys(want).length} files present with the lock's sizes${full ? ' and sha256' : ''}`, bad.slice(0, 3).join(', '));
  let mb = null; try { mb = mainBundle(id); } catch (e) { mb = `ERR ${e.message}`; }
  ok(mb === desc.mainBundle, `main bundle ${mb} == descriptor mainBundle`, desc.mainBundle);
  // the console allowlist names its "line0" sites in the main bundle by line: each must be the same notify code in this pin
  for (const s of allowlistLineSites()) {
    let line = null; try { line = fs.readFileSync(path.join(R, 'dist', mb), 'utf8').split('\n')[s.line0]; } catch { /* below */ }
    ok(line != null && line.includes('notify({severity:') && sha(line) === desc.consoleSites?.[String(s.line0)],
      `console-allowlist site line ${s.line0} of ${mb} is the recorded notify line`, line == null ? 'no such line' : `sha256 ${sha(line).slice(0, 12)} vs descriptor ${String(desc.consoleSites?.[String(s.line0)]).slice(0, 12)}`);
  }
  // vendor: the file set QED64-PIN lists (full: sha256)
  const pinText = exists(path.join(repoPinDir(id), 'QED64-PIN')) ? fs.readFileSync(path.join(repoPinDir(id), 'QED64-PIN'), 'utf8') : '';
  const pinFiles = pinText.split('\n').filter((l) => l && !l.startsWith('#')).map((l) => { const [h, ...r] = l.split('  '); return [r.join('  '), h]; });
  const V = path.join(repoPinDir(id), 'vendor-qed64');
  const vbad = pinFiles.filter(([f, h]) => !exists(path.join(V, f)) || (full && sha256File(path.join(V, f)) !== h)).map(([f]) => f);
  ok(pinFiles.length > 0 && !vbad.length && sha(pinText) === (lock.vendor || {}).pinSha256,
    `pins/${id}/vendor-qed64: the ${pinFiles.length} files QED64-PIN lists${full ? ' (sha256 ==)' : ''}; QED64-PIN sha256 == lock`, vbad.slice(0, 3).join(', '));
  // per-runtime $W store: stage1 identity (wasm64-sha256(lean.wasm)[0:16]), raw regions, bakes
  const WR = wRtDir(bid);
  const s1 = path.join(WR, 'stage1', 'bin', 'lean.wasm');
  const s1id = exists(s1) ? `wasm64-${sha256File(s1).slice(0, 16)}` : 'missing';
  ok(s1id === bid, `$W/runtimes/${bid}/stage1 buildId == ${bid}`, s1id);
  const need = ['raw/init.snap', 'raw/mathlib.snap', 'raw/widgets7.snap', 'raw/widgets8.snap', 'bake-out-w7/index.json', 'bake-out-w8/index.json',
    'bake-work-w7/widgets.snap', 'bake-work-w8/widgets.snap', 'BAKE-KEY-w7.txt', 'BAKE-KEY-w8.txt', 'bake-logs/bake-widgets7.log', 'bake-logs/bake-widgets8.log'];
  const miss = need.filter((f) => !exists(path.join(WR, f)));
  ok(!miss.length, `$W/runtimes/${bid}: raw/{init,mathlib,widgets7,widgets8}.snap, bake-out/bake-work w7+w8, BAKE-KEY w7+w8, bake logs w7+w8 present`, miss.join(', '));
  for (const n of [7, 8]) {
    const f = path.join(WR, `raw/widgets${n}.snap`), g = path.join(WR, `bake-work-w${n}/widgets.snap`);
    if (exists(f) && exists(g)) ok(fs.statSync(f).size === fs.statSync(g).size, `raw/widgets${n}.snap size == bake-work-w${n}/widgets.snap`, `${fs.statSync(f).size} B`);
  }
  // overlays (per runtime): paired with this runtime, exactly {init, mathlib}, sizes == transfer, init == THIS pin's stock
  // init entry (same digest), mathlib == this runtime's bake (bake-out widgets entry: same digest)
  let stockInit = null;
  try { stockInit = readJson(path.join(R, 'public/snapshots/index.json')).snapshots.find((s) => s.name === 'init'); } catch { /* below */ }
  for (const o of OVERLAYS) {
    const d = path.join(outRtDir(bid), 'overlay', o), ix = path.join(d, 'index.json');
    if (!exists(ix)) { ok(false, `out/runtimes/${bid}/overlay/${o}/index.json missing`); continue; }
    const j = readJson(ix); const errs = [];
    if (j.schema !== 'qed64.snapshot-index/v1') errs.push(`schema ${j.schema}`);
    if (j.snapshots.map((s) => s.name).sort().join(',') !== 'init,mathlib') errs.push('entries');
    for (const s of j.snapshots) {
      if (s.runtime !== bid) errs.push(`${s.name}.runtime ${s.runtime}`);
      const f = path.join(d, path.basename(s.url));
      if (!exists(f)) errs.push(`${path.basename(s.url)} missing`); else if (fs.statSync(f).size !== s.transfer) errs.push(`${s.name} size != transfer`);
    }
    const i = j.snapshots.find((s) => s.name === 'init');
    if (!stockInit || !i || i.digest !== stockInit.digest || i.url !== stockInit.url) errs.push(`init entry != release/${id} stock init`);
    const bo = path.join(WR, `bake-out-w${o.slice(-1)}`, 'index.json');
    if (exists(bo)) {
      const w = readJson(bo).snapshots.find((s) => s.name === 'widgets');
      const m = j.snapshots.find((s) => s.name === 'mathlib');
      if (!w || !m || w.digest !== m.digest) errs.push('mathlib digest != bake-out widgets digest');
    }
    ok(!errs.length, `out/runtimes/${bid}/overlay/${o}: runtime == ${bid}, {init, mathlib}, sizes == transfer, init == this pin's stock init, mathlib == this runtime's bake`, errs.join('; '));
  }
  ok(exists(path.join(outRtDir(bid), 'headless')), `out/runtimes/${bid}/headless exists`);
  // audit: the overlays' runtime == this pin's LOCK runtime (not only the descriptor's); for the active pin also the
  // overlay links (what is served) against the active lock
  for (const o of OVERLAYS) {
    const ix = path.join(outRtDir(bid), 'overlay', o, 'index.json');
    let rts = []; try { rts = [...new Set(readJson(ix).snapshots.map((x) => x.runtime))]; } catch { /* reported above */ }
    ok(rts.length === 1 && rts[0] === q.buildId, `out/runtimes/${bid}/overlay/${o}: index runtime ${rts.join(',') || '-'} == pins/${id}/QED64.lock.json runtime ${q.buildId}`);
  }
  if (activeOrNull() === id) for (const r of overlayLinksMatchLock()) ok(r.ok, `active ${r.msg}`);
  return out;
}

/** Audit (pin D lane): the ACTIVE overlay links (out/overlay/snapshots/widgets7|8, what serve.mjs, the UX suite and the
 *  deploy manifest read) must hold regions paired with the runtime the ACTIVE LOCK (QED64.lock.json) names: every entry of
 *  the index.json reached through the link has runtime == lock qed64.buildId. Catches a lock link and overlay links that
 *  disagree (an interrupted or hand-made switch, an overlay rebuilt for another runtime through the link). [{ok, msg}] */
function overlayLinksMatchLock() {
  const out = [];
  let lockBid = null;
  try { lockBid = readJson(path.join(SC, 'QED64.lock.json')).qed64.buildId; } catch (e) { return [{ ok: false, msg: `QED64.lock.json unreadable: ${e.message}` }]; }
  for (const o of OVERLAYS) {
    const link = path.join(SC, 'out', 'overlay', 'snapshots', o), ix = path.join(link, 'index.json');
    let rts = null;
    try { rts = [...new Set(readJson(ix).snapshots.map((x) => x.runtime))]; } catch (e) { out.push({ ok: false, msg: `${rel(link)}/index.json: ${e.code || e.message} (overlay runtime vs lock ${lockBid})` }); continue; }
    out.push({ ok: rts.length === 1 && rts[0] === lockBid, msg: `${rel(link)} (-> ${isLink(link) ? fs.readlinkSync(link) : 'not a link'}): index runtime ${rts.join(',')} == active lock runtime ${lockBid}` });
  }
  return out;
}

function verdicts(id) {
  try {
    const lockSha = sha(fs.readFileSync(path.join(repoPinDir(id), 'QED64.lock.json')));
    const runs = readRuns().filter((x) => x.lockSha256 === lockSha && !(x.args || []).length && !x.uxOrigin);
    const v = runs.filter((x) => whyNotVerdict(x).length === 0);
    const headed = runs.filter((x) => x.headed); const so = headed.filter((x) => whyNotSignOff(x).length === 0);
    return { full: runs.length, verdicts: v.length, headed: headed.length, signOffs: so.length, last: runs.length ? runs[runs.length - 1] : null, lastVerdict: v.length ? v[v.length - 1] : null, lastSignOff: so.length ? so[so.length - 1] : null };
  } catch (e) { return { error: e.message }; }
}

/** This repo's serve.mjs processes that follow the ACTIVE pin (no SHOWCASE_PIN in their environment). */
function ourFollowingServers() {
  const me = path.join(SC, 'scripts', 'serve.mjs');
  let pids = [];
  try { pids = execFileSync('pgrep', ['-f', 'scripts/serve\\.mjs']).toString().trim().split('\n').filter(Boolean); } catch { return []; }
  const mine = [];
  for (const pid of pids) {
    let args = '', cwd = '', env = '';
    try { args = execFileSync('ps', ['-o', 'args=', '-p', pid]).toString().trim(); } catch { continue; }
    try { cwd = (execFileSync('lsof', ['-a', '-p', pid, '-d', 'cwd', '-Fn']).toString().split('\n').find((l) => l.startsWith('n')) || 'n').slice(1); } catch { /* gone */ }
    try { env = execFileSync('ps', ['eww', '-o', 'command=', '-p', pid]).toString(); } catch { /* gone */ }
    const m = /(\S*scripts\/serve\.mjs)/.exec(args);
    const script = args.includes(me) ? me : m ? path.resolve(cwd || '/', m[1]) : null;
    if (script === me && !/\bSHOWCASE_PIN=[0-9a-f]{7}\b/.test(env)) mine.push({ pid, args: args.slice(0, 160) });
  }
  return mine;
}
const busy = (re) => { try { return execFileSync('pgrep', ['-fl', re]).toString().trim(); } catch { return ''; } };
function printChecks(rows) { for (const r of rows) console.log(`${r.ok ? 'OK  ' : 'FAIL'} ${r.msg}`); return rows.every((r) => r.ok); }
const activeOrNull = () => { try { return activePinId(); } catch { return null; } };

if (cmd === 'list') {
  const act = activeOrNull();
  for (const p of listPins()) {
    const c = checkPin(p.id); const v = verdicts(p.id);
    // a headed run (UX_HEADED_ALL=1) is never a verdict: it is judged as a HEADED SIGN-OFF (scripts/lib/ux-record.mjs)
    const judge = (x) => (x.headed ? (whyNotSignOff(x).length ? 'NOT A HEADED SIGN-OFF' : 'HEADED SIGN-OFF') : (whyNotVerdict(x).length ? 'NOT A VERDICT' : 'VERDICT'));
    const vt = v.error ? `ux: ${v.error}` : `full UX runs on its current lock: ${v.full} (${v.headed} headed), VERDICT ${v.verdicts}${v.lastVerdict ? ` (last ${v.lastVerdict.run} ${v.lastVerdict.end})` : ''}, HEADED SIGN-OFF ${v.signOffs}${v.lastSignOff ? ` (last ${v.lastSignOff.run} ${v.lastSignOff.end})` : ''}${v.last && v.last !== v.lastVerdict && v.last !== v.lastSignOff ? `; newest ${v.last.run}: ${judge(v.last)}` : ''}`;
    console.log(`${p.id === act ? '* ACTIVE' : '  staged'} ${p.id}  QED64 ${p.qed64.commit.slice(0, 12)}  runtime ${p.buildId}  ${p.label}`);
    // pin.json's status is hand-written when a lane registers or re-chooses a pin: a dated role note, never the current verdict
    // state (final audit, 2026-10-03); the verdicts and sign-offs on the pin's lock are COMPUTED on the line after it
    console.log(`         role (hand-written note, history): ${p.status || '-'}; liveness builtIn=${p.liveness && p.liveness.builtIn}; stores ${c.every((r) => r.ok) ? 'complete' : `INCOMPLETE (${c.filter((r) => !r.ok).length} FAIL: ${c.filter((r) => !r.ok).map((r) => r.msg.slice(0, 70)).join('; ')})`}`);
    console.log(`         computed now: ${vt}`);
  }
  process.exit(0);
} else if (cmd === 'current') {
  const id = activeOrNull();
  if (!id) { console.log('FAIL no active pin (QED64.lock.json missing or not a lock)'); process.exit(1); }
  let desc; try { desc = pinDescriptor(id); } catch (e) { console.log(`FAIL ${e.message}`); process.exit(1); }
  const j = path.join(SC, 'out', 'pins', 'switch-journal.json');
  const jr = exists(j) ? readJson(j) : null;
  const st = linkStates(id);
  console.log(`active pin ${id} (QED64 ${desc.qed64.commit.slice(0, 12)}, runtime ${desc.buildId}): ${desc.label}`);
  for (const s of st) console.log(`${s.state === 'ok' ? 'OK  ' : 'FAIL'} ${rel(s.link)} -> ${s.now ?? '(none)'}${s.state === 'ok' ? '' : ` [${s.state}; want ${s.target}]`}`);
  let gp = null; try { gp = readJson(path.join(SC, 'gallery', 'pin.json')); } catch { /* none */ }
  const gpOk = gp && gp.pin === id && gp.buildId === desc.buildId && gp.lockSha256 === sha(fs.readFileSync(path.join(SC, 'QED64.lock.json')));
  console.log(`${gpOk ? 'OK  ' : 'FAIL'} gallery/pin.json pin ${gp && gp.pin}, buildId ${gp && gp.buildId} and lockSha256 == the active lock${gpOk ? '' : ' (run: node scripts/build-gallery.mjs)'}`);
  const ovl = overlayLinksMatchLock();
  const ovlOk = printChecks(ovl);
  if (jr && jr.state !== 'done') console.log(`FAIL an interrupted switch ${jr.from} -> ${jr.to} (${jr.started}); re-run: scripts/showcase.sh pin use ${jr.to}`);
  const good = st.every((s) => s.state === 'ok') && gpOk && ovlOk && !(jr && jr.state !== 'done');
  console.log(good ? `PIN CURRENT OK ${id}` : `PIN CURRENT FAILED ${id}`);
  process.exit(good ? 0 : 1);
} else if (cmd === 'check') {
  const id = argv[1];
  if (!ID_RE.test(id || '')) { console.error('usage: pin-switch.mjs check <pin id: 7-hex QED64 commit> [--full]'); process.exit(2); }
  const good = printChecks(checkPin(id, { full: flag('--full') }));
  console.log(good ? `PIN CHECK OK ${id}${flag('--full') ? ' (full)' : ' (cheap)'}` : `PIN CHECK FAILED ${id}`);
  process.exit(good ? 0 : 1);
} else if (cmd === 'use') {
  const to = argv[1]; const dry = flag('--dry-run');
  if (!ID_RE.test(to || '')) { console.error('usage: pin-switch.mjs use <pin id> [--dry-run] [--allow-incomplete] [--no-deploy]'); process.exit(2); }
  const refuse = (m) => { console.log(`REFUSED: ${m}`); process.exit(3); };
  const from = activeOrNull();
  try { pinDescriptor(to); } catch (e) { refuse(e.message); }
  const rows = checkPin(to);
  const incomplete = rows.filter((r) => !r.ok);
  if (incomplete.length) {
    printChecks(incomplete);
    if (!flag('--allow-incomplete')) refuse(`pin ${to}'s stores are incomplete (above); --allow-incomplete only when bringing up a new runtime`);
    console.log('WARN switching to an incomplete pin (--allow-incomplete): build its missing parts through the active links');
  }
  const srv = ourFollowingServers();
  if (srv.length) refuse(`this repo's serve.mjs is running without SHOWCASE_PIN (${srv.map((s) => `pid ${s.pid}`).join(', ')}): it serves the release it started with; stop it first (scripts/showcase.sh stop)`);
  const bake = busy('^(/usr/bin/time -l )?node .*bake-snapshot\\.mjs');
  if (bake) refuse(`a snapshot bake is running (${bake.split('\n')[0]}): it writes the active runtime's bake stores`);
  if (exists(path.join(W, 'headless', '.lock'))) refuse('a headless run holds $W/headless/.lock: it reads the active stage1/raw/bakes');
  const bl = browserLockFile();
  // showcase.sh ux locks as '<lane>-ux', npm run test:ux as 'ux-suite'
  if (exists(bl) && /^(\S*-)?(ux|ux-suite)\s/.test(fs.readFileSync(bl, 'utf8'))) refuse(`a showcase browser run holds the browser lock (${fs.readFileSync(bl, 'utf8').trim()}): it tests the active pin`);
  const plan = linkStates(to);
  for (const s of plan) if (s.state === 'real') refuse(`${rel(s.link)} is a real ${fs.lstatSync(s.link).isDirectory() ? 'directory' : 'file'}, not a pin link: move it into a pin's store first (docs/REPIN-LOG.md "Multiple pins")`);
  console.log(`pin use ${to}: from ${from || '(none)'}; ${plan.filter((s) => s.state === 'ok').length}/${plan.length} links already point at it`);
  for (const s of plan) if (s.state !== 'ok') console.log(`  ${dry ? 'would link' : 'link'} ${rel(s.link)} -> ${s.target}`);
  if (dry) { console.log('dry run: nothing changed'); process.exit(0); }
  const jf = path.join(SC, 'out', 'pins', 'switch-journal.json');
  fs.mkdirSync(path.dirname(jf), { recursive: true });
  const journal = { from, to, started: new Date().toISOString(), state: 'switching', lane: process.env.SHOWCASE_LANE || null };
  fs.writeFileSync(jf, JSON.stringify(journal, null, 2) + '\n');
  // the lock link LAST: until it flips, every reader still sees the old pin's identity
  const order = [...plan.filter((s) => !s.link.endsWith('QED64.lock.json')), ...plan.filter((s) => s.link.endsWith('QED64.lock.json'))];
  for (const s of order) {
    if (s.state === 'ok') continue;
    fs.mkdirSync(path.dirname(s.link), { recursive: true });
    const tmp = `${s.link}.pin-switch-${process.pid}`;
    fs.rmSync(tmp, { force: true });
    fs.symlinkSync(s.target, tmp);
    fs.renameSync(tmp, s.link); // atomic replace of the old symlink (rename(2) never follows the destination link)
  }
  const after = linkStates(to);
  if (!after.every((s) => s.state === 'ok')) { for (const s of after.filter((x) => x.state !== 'ok')) console.log(`FAIL ${rel(s.link)} ${s.state}`); process.exit(1); }
  // audit: what is now served (the overlay links) is paired with the runtime the new active lock names
  const ovl = overlayLinksMatchLock();
  if (!printChecks(ovl) && !flag('--allow-incomplete')) { console.log(`FAIL pin use ${to}: the active overlay links' runtime != the active lock's (journal left at 'switching'; fix the stores, then re-run pin use)`); process.exit(1); }
  // gallery/pin.json (the gallery's runtime pairing) from the new lock
  const bg = spawnSync(process.execPath, [path.join(SC, 'scripts', 'build-gallery.mjs')], { cwd: SC, encoding: 'utf8' });
  process.stdout.write(bg.stdout.split('\n').filter((l) => /^(pin|BUILD-GALLERY|wrote|FAIL)/.test(l)).map((l) => `  build-gallery: ${l}\n`).join(''));
  if (bg.status !== 0) { console.log(`FAIL build-gallery.mjs rc=${bg.status}: ${(bg.stderr || '').slice(0, 400)}`); process.exit(1); }
  journal.state = 'done'; journal.done = new Date().toISOString();
  fs.writeFileSync(jf, JSON.stringify(journal, null, 2) + '\n');
  fs.appendFileSync(path.join(SC, 'out', 'pins', 'history.jsonl'), JSON.stringify(journal) + '\n');
  console.log(`PIN SWITCHED ${from || '(none)'} -> ${to}`);
  // deploy inputs: regenerate for the new pin when a deploy staging exists (its own gates decide; a red one writes nothing)
  if (exists(path.join(SC, 'out', 'deploy', 'manifest.json')) && !flag('--no-deploy')) {
    for (const a of [[], ['--stage-assets']]) {
      const r = spawnSync(process.execPath, [path.join(SC, 'scripts', 'deploy-manifest.mjs'), ...a], { cwd: SC, encoding: 'utf8' });
      const lines = (r.stdout + r.stderr).split('\n').filter((l) => /^(DEPLOY-MANIFEST|STAGE|S1|S2|G2|FAIL)/.test(l));
      console.log(`  deploy-manifest ${a.join(' ') || 'generate'} rc=${r.status}: ${lines.join(' | ').slice(0, 600)}`);
    }
  }
  process.exit(0);
} else {
  console.error('usage: pin-switch.mjs list | current | check <id> [--full] | use <id> [--dry-run] [--allow-incomplete] [--no-deploy]');
  process.exit(2);
}
