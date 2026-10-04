// Exploration probe (re-pin lane, docs/REPIN-LOG.md): what QED64's OWN liveness (lean.worker.js, HARDENING #52) sees while
// Lean runs a long, silent command. Read-only: it only READS the worker's test export
// (self.__qed64TestExports.liveness.state(), the same object QED64's unit tests drive) and the page's status; it never
// calls step(), kickMailbox() or any mailbox function. Run under the browser lock:
//   UX_RUN=explore-repin scripts/with-browser-lock.sh repin-explore node tests/ux/tools/qed64-liveness.mjs [--sleep 38000]
// Samples every second: the worker's silence (now - lastFrameAt), its outstanding forwarded requests, its probe and
// counters, the front door's phase; the page tap's server-frame count; the gallery's own liveness counters.
import fs from 'node:fs';
import path from 'node:path';
import { launch, Gallery, BY_ID, RUN_DIR, sleep } from '../lib/qed64.mjs';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const SLEEP_MS = Number(arg('--sleep', '38000'));
const ID = arg('--id', 'dist-lens');
const out = { startedAt: new Date().toISOString(), sleepMs: SLEEP_MS, id: ID, samples: [] };
const s = await launch({ title: 'qed64 liveness exploration', file: 'tools/qed64-liveness.mjs' }, { profile: 'warm', label: 'qlive' });
try {
  const g = await Gallery.open(s, { hash: ID });
  out.boot = { ms: g.boot.ms, phase: g.boot.s && g.boot.s.phase, builtIn: g.boot.s && g.boot.s.liveness && g.boot.s.liveness.qed64 && g.boot.s.liveness.qed64.builtIn };
  const leanWorker = () => s.page().workers().find((w) => /\/workers\/lean\.worker\.js/.test(w.url()));
  const readWorker = async () => {
    const w = leanWorker(); if (!w) return { error: 'no lean.worker.js' };
    return Promise.race([w.evaluate(() => {
      const T = self.__qed64TestExports; if (!T || !T.liveness) return { error: 'no __qed64TestExports.liveness' };
      const L = T.liveness.state(); const now = performance.now();
      const fd = T.frontDoor && typeof T.frontDoor.status === 'function' ? T.frontDoor.status() : null;
      return L ? { silentMs: Math.round(now - L.lastFrameAt), outstanding: [...L.outstanding.keys()].map(String).slice(0, 8), outstandingN: L.outstanding.size,
        probe: L.probe ? { id: L.probe.id, ageMs: Math.round(now - L.probe.sentAt) } : null, stalled: !!L.stalledAt, counters: { ...L.counters },
        mailbox: { mode: T.liveness.runtimeMailbox.mode, located: T.liveness.runtimeMailbox.mailboxPtr !== null, served: T.liveness.runtimeMailbox.served, notified: T.liveness.runtimeMailbox.notified },
        frontDoorPhase: fd && fd.phase || null } : { error: 'liveness not started (no resident loop)' };
    }).catch((e) => ({ error: String(e.message).slice(0, 160) })), sleep(3000).then(() => ({ noAnswerIn3s: true }))]);
  };
  out.beforeEdit = await readWorker();
  console.log(`boot ${g.boot.ms} ms; builtIn ${out.boot.builtIn}; worker before edit ${JSON.stringify(out.beforeEdit)}`);
  const ex = BY_ID[ID];
  await g.setCursor(ex.text.split('\n').length - 1, 0);
  await g.focusEditor();
  const frames = () => g.q(() => (window.__uxTap ? window.__uxTap.frames : null)).catch(() => null);
  const tap0 = await frames();
  await s.page().keyboard.insertText(`\n#eval IO.sleep ${SLEEP_MS}\n`);
  const t0 = Date.now();
  for (;;) {
    const [w, st, q, tapN] = await Promise.all([readWorker(), g.status(), g.qstatus(), frames()]);
    const smp = { t: Date.now() - t0, phase: q && q.phase, version: q && q.version, worker: w, tapFrames: tapN === null || tap0 === null ? null : tapN - tap0, galleryLiveness: { sent: st.liveness.sent, answered: st.liveness.answered, qed64: st.liveness.qed64.counters } };
    out.samples.push(smp);
    console.log(`${(smp.t / 1000).toFixed(1)}s ${smp.phase} v${smp.version} worker silent ${w.silentMs} ms outstanding ${w.outstandingN} [${(w.outstanding || []).join(',')}] probe ${JSON.stringify(w.probe)} counters ${JSON.stringify(w.counters)} tapFrames +${smp.tapFrames}`);
    if (q && q.phase === 'ready' && smp.t > 2000) break;
    if (smp.t > SLEEP_MS + 60000) { out.timedOut = true; break; }
    await sleep(1000);
  }
  out.after = await readWorker();
  const maxSilent = Math.max(...out.samples.map((x) => x.worker.silentMs || 0));
  out.summary = { maxWorkerSilentMs: maxSilent, probesDuring: (out.after.counters?.probes ?? 0) - (out.beforeEdit.counters?.probes ?? 0), outstandingMax: Math.max(...out.samples.map((x) => x.worker.outstandingN || 0)), mailbox: out.after.mailbox };
  console.log(`SUMMARY ${JSON.stringify(out.summary)}`);
} finally {
  const v = s.verdict({ scenarios: [] });
  out.console = { ok: v.ok, counts: v.counts, unexpected: v.unexpected.slice(0, 10), crashed: v.crashed };
  out.workerConsole = s.watches.flatMap((w) => w.messages).filter((m) => /\[liveness\]|\[boot\] (runtime mailbox|WARNING)/.test(m.text || '')).slice(0, 40);
  await s.close();
  const dir = path.join(RUN_DIR, 'explore'); fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'qed64-liveness.json'), `${JSON.stringify(out, null, 1)}\n`);
  console.log(`console ok ${out.console.ok} crashed ${out.console.crashed}; [liveness]/[boot] lines ${JSON.stringify(out.workerConsole.map((m) => m.text))}`);
  console.log(`wrote ${path.join(dir, 'qed64-liveness.json')}`);
}
