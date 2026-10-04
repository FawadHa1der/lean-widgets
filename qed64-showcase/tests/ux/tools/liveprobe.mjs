// Exploration probe (close-out lane, docs/NEXT-STEPS.md §1): is `textDocument/hover` at 0:0 answered while Lean is busy
// with a long, silent elaboration? And what do the QED64 page's dedicated workers expose (for the hang capture)?
// Read-only on the runtime: no mailbox call is made here. Run under the browser lock:
//   UX_RUN=explore-live scripts/with-browser-lock.sh closeout-explore node tests/ux/tools/liveprobe.mjs [--sleep 40000]
// The gallery runs in OBSERVE mode (?liveness=observe) so that an unanswered probe is recorded, never acted on.
import fs from 'node:fs';
import path from 'node:path';
import { launch, Gallery, BY_ID, RUN_DIR, sleep } from '../lib/qed64.mjs';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const SLEEP_MS = Number(arg('--sleep', '40000'));
const ID = arg('--id', 'dist-lens');
const out = { startedAt: new Date().toISOString(), sleepMs: SLEEP_MS, id: ID };
const testInfo = { title: 'liveprobe exploration', file: 'tools/liveprobe.mjs' };
const s = await launch(testInfo, { profile: 'warm', label: 'live' });
try {
  const g = await Gallery.open(s, { hash: ID, query: '?liveness=observe' });
  out.boot = { ms: g.boot.ms, phase: g.boot.s && g.boot.s.phase, liveness: g.boot.s && g.boot.s.liveness };
  console.log(`boot ${g.boot.ms} ms ${g.boot.s && g.boot.s.phase}; liveness ${JSON.stringify(g.boot.s && g.boot.s.liveness && { mode: g.boot.s.liveness.mode, probeAfterMs: g.boot.s.liveness.probeAfterMs })}`);
  // the page's dedicated workers (read only)
  const ws = s.page().workers();
  out.workers = await Promise.all(ws.map(async (w) => {
    const info = await Promise.race([w.evaluate(() => ({
      name: self.name, checkMailboxRaw: typeof __emscripten_check_mailbox, checkMailbox: typeof checkMailbox, pthreadSelf: typeof _pthread_self === 'function' ? String(_pthread_self()) : null,
      isPthread: typeof ENVIRONMENT_IS_PTHREAD === 'undefined' ? null : ENVIRONMENT_IS_PTHREAD,
      pool: typeof PThread === 'undefined' || !PThread.unusedWorkers ? null : { unused: PThread.unusedWorkers.length, running: Object.keys(PThread.pthreads || {}).length },
    })).catch((e) => ({ error: String(e.message).slice(0, 160) })), sleep(3000).then(() => ({ noAnswerIn3s: true }))]);
    return { url: w.url().replace(/^https?:\/\/localhost:\d+/, '').slice(0, 100), ...info };
  }));
  const kinds = {}; for (const w of out.workers) { const k = `${w.url.slice(0, 40)} raw=${w.checkMailboxRaw} pthread=${w.isPthread} self=${w.pthreadSelf !== null && w.pthreadSelf !== '0'}${w.noAnswerIn3s ? ' NO-ANSWER' : ''}`; kinds[k] = (kinds[k] || 0) + 1; }
  console.log(`workers ${ws.length}: ${JSON.stringify(kinds, null, 1)}`);
  console.log(`main-thread worker(s): ${JSON.stringify(out.workers.filter((w) => w.isPthread === false))}`);
  // a long, silent command at the end of the example (one input event = one didChange)
  const ex = BY_ID[ID];
  const q0 = await g.qstatus();
  const lines = ex.text.split('\n').length;
  await g.setCursor(lines - 1, 0);
  await g.focusEditor();
  await g.page.keyboard.insertText(`\n#eval IO.sleep ${SLEEP_MS}\n`);
  const t0 = Date.now();
  out.timeline = [];
  let ready = null; let lastPm = null;
  for (;;) {
    await sleep(500);
    const st = await g.status(); const q = await g.qstatus();
    const lv = st.liveness;
    const row = { t: Date.now() - t0, phase: q.phase, version: q.version, session: q.session, pool: q.pool, progressMsgs: st.stall.progressMsgs, idleMs: st.stall.idleMs, sent: lv.sent, answered: lv.answered, missed: lv.missed, wedged: lv.wedged, lastAnswerMs: lv.lastAnswerMs, card: st.stall.active };
    out.timeline.push(row);
    if (row.progressMsgs !== lastPm || row.t % 5000 < 500) console.log(JSON.stringify(row));
    lastPm = row.progressMsgs;
    if (q.phase === 'ready' && q.version > q0.version && row.t > 2000) { ready = row; break; }
    if (Date.now() - t0 > SLEEP_MS + 120000) break;
  }
  const st = await g.status();
  out.ready = ready; out.liveness = st.liveness; out.stall = st.stall;
  out.diagnostics = ready ? await g.diagnosticsOf(ready.version) : null;
  console.log(`ready ${ready ? `${ready.t} ms after the edit` : 'NOT reached'}; liveness sent ${st.liveness.sent} answered ${st.liveness.answered} missed ${st.liveness.missed} wedged ${st.liveness.wedged} maxAnswerMs ${st.liveness.maxAnswerMs}; card shown ${st.stall.shown}; diagnostics ${JSON.stringify(out.diagnostics)}`);
  console.log(`liveness events ${JSON.stringify(st.liveness.events.map((e) => `${e.t} ${e.source}${e.ms !== undefined ? ` ${e.ms}ms` : ''}${e.idleMs !== undefined ? ` idle ${e.idleMs}` : ''}`))}`);
} finally {
  const v = s.verdict({ scenarios: [] });
  out.console = { ok: v.ok, counts: v.counts, unexpected: v.unexpected.slice(0, 10) };
  out.workerConsole = s.watches.flatMap((w) => w.messages).filter((m) => m.worker || /\[lean:|\[WASM/.test(m.text)).slice(0, 80);
  await s.close();
  const f = path.join(RUN_DIR, 'liveprobe.json');
  fs.writeFileSync(f, `${JSON.stringify(out, null, 1)}\n`);
  console.log(`wrote ${f}; console ok ${out.console.ok}; worker/lean console lines ${out.workerConsole.length}`);
}
