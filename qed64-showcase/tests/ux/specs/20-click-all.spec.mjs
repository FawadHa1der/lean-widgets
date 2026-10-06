// C20 (new): the in-browser twin of lean/expect/click-all. EVERY link the InfoView renders in the eight examples (135 distinct
// links: 129 MakeEditLink + 6 Try this, lean/expect/click-all/w8/<pkg>.json and lean/expect/click-all/dist-lens.json, the widgets8
// environment the gallery serves) is clicked with the real mouse in the real InfoView, each from a freshly reset
// example (the gallery's Reset button). For each link: the panel it lives in equals its golden first (so the link
// exists where the native run found it), the post-click document equals the native click-all edit (applyEdit of the
// frozen range/newText AND the sha256 of the native edited file), and QED64 re-checks that version with 0 errors and
// 0 warnings. One warm-profile boot per package (packages with no links are skipped: chart-kit, expr-xray,
// tree-scope have 0 in click-all).
import { test, expect } from '../lib/fixtures.mjs';
import { Gallery, EXAMPLES, CLICKALL, GOLDENS, LIVENESS_MODE, API, RESTART_HOW, rel, clickAllPath, sleep } from '../lib/qed64.mjs';
import { clickLink, goldenCursor } from '../lib/actions.mjs';

const withLinks = EXAMPLES.filter((e) => CLICKALL[e.id].links.length > 0);
const total = withLinks.reduce((n, e) => n + CLICKALL[e.id].links.length, 0);

test(`C20 click-all in the browser: all ${total} rendered links, each from a freshly reset example`, async ({ ux }) => {
  test.setTimeout(150 * 60 * 1000);
  const m = ux.metrics; m.total = total; m.packages = {};
  m.source = Object.fromEntries(EXAMPLES.map((e) => [e.id, rel(clickAllPath(e.id))]));
  const fail = [];
  const tAll = Date.now();
  for (const ex of withLinks) {
    const id = ex.id; const ca = CLICKALL[id];
    expect(ca.exampleSha256, `${id}: click-all was run on this exact example`).toBe(ex.textSha256);
    const s = await ux.launch({ profile: 'warm', label: `c20-${id}` });
    const g = await Gallery.open(s, { hash: id });
    expect(g.boot.s.phase).toBe('ready');
    const q0 = await g.qstatus();
    const pk = { links: ca.links.length, ok: 0, failed: [], bootMs: g.boot.ms, clickToEditMs: [], clickToReadyMs: [], offCentreClicks: 0, results: [], stalls: [], poolTotals: {} };
    // v1: the watchdog's progress comes from the API's fileProgress/diagnostics events, not a relay tap; the gallery's own
    // liveness probe is stood down on capabilities.liveness (QED64's worker liveness is projected by the API instead)
    if (API) {
      expect(g.boot.s.stall, 'the stall watchdog is armed at its default (v1: fed by API events, tapped = the api is held)').toMatchObject({ thresholdMs: 45000, tapped: true, source: 'api-events', shown: 0 });
      expect(g.boot.s.liveness, 'the gallery probe is stood down on capabilities.liveness (its defaults still reported)').toMatchObject({ mode: LIVENESS_MODE || 'auto', probe: 'stood-down', probeAfterMs: 10000, probeTimeoutMs: 5000, sent: 0, wedged: 0, restarts: 0 });
      expect(g.boot.s.bridge, 'no bridge in v1').toMatchObject({ installed: false, stoodDown: true, late: 0 });
    } else {
      expect(g.boot.s.stall, 'the stall watchdog is armed at its default').toMatchObject({ thresholdMs: 45000, tapped: true, shown: 0 });
      expect(g.boot.s.liveness, 'the liveness probe is armed at its defaults (UX_LIVENESS=observe for hang hunts)').toMatchObject({ mode: LIVENESS_MODE || 'auto', probeAfterMs: 10000, probeTimeoutMs: 5000, wedged: 0 });
    }
    pk.captures = [];
    const t0 = Date.now();
    for (const link of ca.links) {
      const fa = link.foundAt[0];
      const at = { line: fa.line, character: fa.character ?? 0 };
      const panel = link.kind === 'makeEditLink' ? goldenCursor(id, at.line, at.character).panels[0] : null;
      const r = await clickLink(g, ex, { kind: link.kind, linkText: link.linkText, title: link.title, edit: link.edit, editedSha256: link.editedSha256 }, at, panel, { elabTimeoutMs: id === 'dist-lens' ? 300000 : 120000 });
      r.n = link.n; r.nativeReElabMs = link.reElaborationMs;
      for (const sr of r.stalls || []) pk.stalls.push({ n: link.n, linkText: link.linkText || link.title, ...sr });
      for (const c of r.captures || []) pk.captures.push({ n: link.n, file: c.file, summary: c.summary });
      if (r.liveness && (r.liveness.wedged || r.liveness.restarts)) (pk.livenessEvents ||= []).push({ n: link.n, ...r.liveness });
      if (r.qed64WedgedReboots) (pk.qed64Handled ||= []).push({ n: link.n, linkText: link.linkText || link.title, reboots: r.qed64WedgedReboots, lastReboot: r.qed64LastReboot, ok: r.ok, clickToReadyMs: r.clickToReadyMs });
      if (r.pool) { const tot = r.pool.unused + r.pool.running; pk.poolTotals[tot] = (pk.poolTotals[tot] || 0) + 1; }
      if (r.ok) { pk.ok++; pk.clickToEditMs.push(r.clickToEditMs); pk.clickToReadyMs.push(r.clickToReadyMs); } else pk.failed.push({ n: link.n, linkText: link.linkText, title: link.title, error: r.error });
      if (r.clickMode === 'mouse-at-point') pk.atPointClicks = (pk.atPointClicks || 0) + 1;
      if (r.clickPoint && !/^(centre|line t=0\.5) /.test(r.clickPoint)) pk.offCentreClicks++;
      pk.results.push({ n: r.n, ok: r.ok, at: r.at, stalls: (r.stalls || []).length, recoveredFromStall: r.recoveredFromStall || false, pool: r.pool, kind: r.kind, linkText: r.linkText, title: r.title, index: r.index, clickMode: r.clickMode, clickPoint: r.clickPoint, editExact: r.editExact, nativeSha: r.nativeSha, errors: r.errors, warnings: r.warnings, clickToEditMs: r.clickToEditMs, clickToReadyMs: r.clickToReadyMs, resetBeforeMs: r.resetBeforeMs, nativeReElabMs: r.nativeReElabMs, error: r.error || null });
      console.log(`C20 ${id} #${link.n} ${r.ok ? 'ok  ' : 'FAIL'} ${link.kind} “${link.linkText || link.title}” edit ${r.editExact} sha ${r.nativeSha} err ${r.errors} warn ${r.warnings} ${r.clickToReadyMs} ms${r.liveness && r.liveness.wedged ? ` WEDGED×${r.liveness.wedged} (liveness ${r.liveness.restarts ? `auto-restart → ${r.recoveredFromStall ? 'recovered' : 'NOT recovered'}` : 'observed'})` : ''}${r.stalls && r.stalls.length ? ` STALL×${r.stalls.length} (card shown after ${r.stalls.map((x) => x.shownEvent && x.shownEvent.idleMs).join(',')} ms idle; Restart Lean → ${r.recoveredFromStall ? 'recovered' : 'NOT recovered'})` : ''}${(r.captures || []).length ? ` CAPTURED ${r.captures.map((c) => c.file).join(', ')}` : ''}${r.error ? ` — ${r.error}` : ''}`);
    }
    const rs = await g.resetUI(ex, { stalls: pk.stalls }); pk.finalReset = rs.ok;
    const q1 = await g.qstatus();
    pk.relay = { workerDeaths: q1.stats.workerDeaths - q0.stats.workerDeaths, reboots: q1.stats.reboots - q0.stats.reboots, rangedChanges: q1.stats.rangedChanges - q0.stats.rangedChanges, userRestarts: q1.stats.userRestarts - q0.stats.userRestarts };
    const gsEnd = await g.status();
    pk.galleryStall = gsEnd.stall;
    pk.liveness = { mode: gsEnd.liveness.mode, sent: gsEnd.liveness.sent, answered: gsEnd.liveness.answered, alive: gsEnd.liveness.alive, aliveVia: gsEnd.liveness.aliveVia, missed: gsEnd.liveness.missed, late: gsEnd.liveness.late, wedged: gsEnd.liveness.wedged, restarts: gsEnd.liveness.restarts, rateLimited: gsEnd.liveness.rateLimited, restartFailed: gsEnd.liveness.restartFailed, maxAnswerMs: gsEnd.liveness.maxAnswerMs };
    // record only (hang hunts on the 9fdf9b8 pin): QED64's own liveness as the gallery observed it (rescues = lost
    // runtime-mailbox wakes QED64 served, field evidence for L7 hypothesis A; wedgedReboots = an L7 occurrence handled
    // upstream) and the document versions this session went through (edits)
    const ql = gsEnd.liveness.qed64 || null;
    pk.qed64Liveness = ql ? { builtIn: ql.builtIn, totals: { ...ql.totals }, wedgedReboots: ql.wedgedReboots, counters: ql.counters ? { ...ql.counters } : null } : null;
    pk.docVersions = { start: q0.version ?? null, end: q1.version ?? null };
    pk.ms = Date.now() - t0;
    const st = (a) => (a.length ? { min: Math.min(...a), median: a.slice().sort((x, y) => x - y)[Math.floor(a.length / 2)], max: Math.max(...a) } : null);
    pk.clickToEditStats = st(pk.clickToEditMs); pk.clickToReadyStats = st(pk.clickToReadyMs);
    delete pk.clickToEditMs; delete pk.clickToReadyMs;
    m.packages[id] = pk;
    // QED64 9fdf9b8+ handles an L7 itself (its liveness: died "wedged", the relay reboots and replays the text): such a
    // reboot is an L7 occurrence HANDLED UPSTREAM, recorded (pk.qed64Handled, a post-hoc capture) and accepted; every
    // other death or reboot fails, and each accepted one must be exactly one "wedged" death plus its reboot
    const handled = pk.qed64Liveness ? pk.qed64Liveness.wedgedReboots : 0;
    pk.l7HandledUpstream = handled;
    if (pk.relay.workerDeaths !== handled || pk.relay.reboots !== handled) fail.push(`${id}: relay ${JSON.stringify(pk.relay)} (QED64 "wedged" reboots: ${handled})`);
    if (handled) console.log(`C20 ${id}: L7 OCCURRENCE handled by QED64 (${handled} "wedged" reboot(s)): ${JSON.stringify(pk.qed64Handled || [])}`);
    // QED64 L7: a stall is acceptable only when the gallery surfaced it (the card, role=alert, offering Restart Lean /
    // Reset example / Keep waiting, shown >= 45 s after the last progress) and Restart Lean recovered it; the user's
    // restarts are exactly the stalls answered
    for (const x of pk.stalls) {
      // the card's wording: 'stopped making progress', or 'still working' when Lean answered within 20 s (gallery.js ALIVE_RECENT_MS)
      const okCard = x.card && x.card.role === 'alert' && /stopped making progress|Lean is still working/.test(x.card.title || '') && x.card.restart === 'Restart Lean' && x.card.reset === true && x.card.keepWaiting === 'Keep waiting';
      if (!okCard) fail.push(`${id} #${x.n}: stall card not as designed ${JSON.stringify(x.card)}`);
      if (!(x.shownEvent && x.shownEvent.idleMs >= 45000)) fail.push(`${id} #${x.n}: stall card shown after ${x.shownEvent && x.shownEvent.idleMs} ms idle (< 45 s)`);
      if (!(x.restartEvent && x.restartEvent.how === RESTART_HOW)) fail.push(`${id} #${x.n}: Restart Lean did not restart the checker (how ${RESTART_HOW}) ${JSON.stringify(x.restartEvent)}`);
    }
    // a wedge the liveness probe restarted by itself (default mode) needs no card; every relay restart is accounted for
    if (pk.liveness.restartFailed) fail.push(`${id}: a liveness restart failed ${JSON.stringify(pk.liveness)}`);
    if (pk.relay.userRestarts !== pk.stalls.length + pk.liveness.restarts) fail.push(`${id}: ${pk.relay.userRestarts} relay restarts for ${pk.stalls.length} card stalls + ${pk.liveness.restarts} liveness restarts`);
    for (const f of pk.failed) fail.push(`${id} #${f.n} “${f.linkText || f.title}”: ${f.error}`);
    console.log(`C20 ${id}: ${pk.ok}/${pk.links} clean in ${(pk.ms / 1000).toFixed(1)} s; stalls ${pk.stalls.length}; liveness ${JSON.stringify(pk.liveness)}; captures ${pk.captures.length}; pthread pool totals ${JSON.stringify(pk.poolTotals)}`);
    // a stall answered by Restart Lean (or restarted by the liveness probe) restarts the relay: the InfoView's old RPC
    // session is refused once per request
    const sc = pk.stalls.length || pk.liveness.restarts ? [...ux.scenarios, 'stallRestart', 'relayRestartOrReboot'] : [...ux.scenarios];
    if (pk.liveness.mode === 'observe' && pk.liveness.wedged) sc.push('livenessObserved'); // hang hunts: the observe-mode warning
    if (handled) sc.push('qed64WedgedReboot', 'relayRestartOrReboot'); // QED64's own reboot answers the requests in flight
    await ux.close(s, { scenarios: sc });
    await sleep(500);
  }
  m.clean = Object.values(m.packages).reduce((n, p) => n + p.ok, 0);
  m.stalls = Object.values(m.packages).reduce((n, p) => n + p.stalls.length, 0);
  m.stallLinks = Object.entries(m.packages).flatMap(([k, p]) => p.stalls.map((x) => `${k} #${x.n}`));
  m.livenessRestarts = Object.values(m.packages).reduce((n, p) => n + p.liveness.restarts, 0);
  m.livenessWedged = Object.values(m.packages).reduce((n, p) => n + p.liveness.wedged, 0);
  m.captures = Object.values(m.packages).flatMap((p) => p.captures.map((c) => c.file));
  m.l7HandledUpstream = Object.values(m.packages).reduce((n, p) => n + (p.l7HandledUpstream || 0), 0);
  m.qed64Liveness = Object.values(m.packages).reduce((a, p) => { const q = p.qed64Liveness; if (!q) return a; a.builtIn = a.builtIn || q.builtIn; for (const k of ['probes', 'answered', 'stalls', 'resumed', 'rescues']) a[k] += q.totals[k] || 0; a.wedgedReboots += q.wedgedReboots || 0; return a; }, { builtIn: false, probes: 0, answered: 0, stalls: 0, resumed: 0, rescues: 0, wedgedReboots: 0 });
  m.poolMax = Object.values(m.packages).reduce((a, p) => { for (const r of p.results) if (r.pool) { a.running = Math.max(a.running, r.pool.running || 0); a.total = Math.max(a.total, (r.pool.unused || 0) + (r.pool.running || 0)); a.parked = Math.max(a.parked, r.pool.parked || 0); } return a; }, { running: 0, total: 0, parked: 0 });
  m.wallMs = Date.now() - tAll;
  m.perPackage = Object.fromEntries(Object.entries(m.packages).map(([k, p]) => [k, `${p.ok}/${p.links} in ${(p.ms / 1000).toFixed(1)} s`]));
  console.log(`C20 ${m.clean}/${total} clean in ${(m.wallMs / 60000).toFixed(1)} min ${JSON.stringify(m.perPackage)}; stalls ${m.stalls} ${JSON.stringify(m.stallLinks)}; liveness wedged ${m.livenessWedged}, restarted ${m.livenessRestarts}; L7 handled by QED64 ${m.l7HandledUpstream}; qed64 liveness ${JSON.stringify(m.qed64Liveness)}; pool max ${JSON.stringify(m.poolMax)}; captures ${JSON.stringify(m.captures)}`);
  expect(fail, 'C20 failures').toEqual([]);
  expect(m.clean).toBe(135);
});
