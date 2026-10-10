// C14 console hygiene across the whole suite: every test of this run classified its sessions' console with EXACTLY
// tests/ux/selectors.json consoleAllowlist (lib/fixtures.mjs; scenario entries only in the tests that deliberately
// restart or break the checker); this aggregates them. Record-only tests (C18) are listed, not counted.
// The network side (QED64 ask 1, #64): every session's network oracle (per-build index copies, unexpected 404s) is
// aggregated too, and the whole run's serve.mjs log (from run-meta.json serveLog.offset: network truth, independent of
// Playwright) must hold no per-build index copy. Both are ENFORCED only on a pin with hardening.pinnedIndexes; older pins
// record them. The serve log's 404 lines are recorded, never asserted (C8's /snapshots/nope/index.json is expected there).
import fs from 'node:fs';
import path from 'node:path';
import { test, expect } from '../lib/fixtures.mjs';
import { RUN_DIR, HARD } from '../lib/qed64.mjs';

/** The run's serve.mjs log lines since global-setup (run-meta.json serveLog {path, offset}); a log shorter than the offset was replaced: read it all. */
function runServeLog() {
  let meta; try { meta = JSON.parse(fs.readFileSync(path.join(RUN_DIR, 'run-meta.json'), 'utf8')); } catch (e) { return { error: `run-meta.json: ${e.message}` }; }
  const sl = meta.serveLog; if (!sl || !sl.path) return { error: 'run-meta.json has no serveLog (a run started before the network oracle)' };
  if (!fs.existsSync(sl.path)) return { error: `no ${sl.path}` };
  const size = fs.statSync(sl.path).size; const from = size >= (sl.offset || 0) ? (sl.offset || 0) : 0;
  const buf = Buffer.alloc(size - from); const fd = fs.openSync(sl.path, 'r');
  try { fs.readSync(fd, buf, 0, buf.length, from); } finally { fs.closeSync(fd); }
  return { path: sl.path, from, bytes: buf.length, lines: buf.toString('utf8').split('\n') };
}

test('C14 console hygiene across the suite: 0 unexpected page errors / console errors, 0 crashes, per-load limits held', async ({ ux }) => {
  const m = ux.metrics;
  const dir = path.join(RUN_DIR, 'tests');
  // C14 itself (and its --repeat-each copies C14.rNN) is not aggregated
  const docs = fs.readdirSync(dir).filter((f) => f.endsWith('.json') && !/^C14(\.r\d+)?\.json$/.test(f)).map((f) => JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')));
  const totals = {}; const bad = []; const recordOnly = []; let sessions = 0; let empty = 0; let cancels = 0;
  const net = { sessions: 0, indexCopies: [], notFound: [], bad: [], unrecorded: 0 };
  for (const d of docs) {
    for (const v of d.console || []) {
      sessions++;
      if (d.recordOnly) { recordOnly.push({ test: d.id, ok: v.ok, line: v.line }); continue; }
      for (const [k, n] of Object.entries(v.counts || {})) totals[k] = (totals[k] || 0) + n;
      if (v.emptyErrors) { empty += v.emptyErrors.count; cancels += v.emptyErrors.cancelReplies; }
      if (!v.ok) bad.push({ test: d.id, session: v.label, line: v.line });
      if (!v.network) { net.unrecorded++; continue; }
      net.sessions++;
      net.indexCopies.push(...v.network.indexCopies.map((x) => ({ test: d.id, session: v.label, ...x })));
      net.notFound.push(...v.network.notFound.map((x) => ({ test: d.id, session: v.label, path: x.path })));
      if (!v.network.ok) net.bad.push({ test: d.id, session: v.label, reasons: v.network.reasons });
    }
  }
  // the whole run's serve log: per-build index copies (asserted on a pinnedIndexes pin) and 404s (recorded)
  const log = runServeLog();
  const COPY_LINE = /^\S+Z (GET|HEAD) \/\S*(?:profiles-)?index\.wasm64-[0-9a-f]{16}\.json(\?\S*)? /;
  const serverCopies = log.lines ? log.lines.filter((l) => COPY_LINE.test(l)) : [];
  const server404 = log.lines ? log.lines.filter((l) => /^\S+Z (GET|HEAD) \S+ 404 /.test(l)) : [];
  // positive control: the suite's gallery loads must be in the log (a QUIET=1 serve.mjs, or another server on the port,
  // leaves no request lines, and "no copy line" would then prove nothing)
  const galleryLines = log.lines ? log.lines.filter((l) => /^\S+Z (GET|HEAD) \/showcase\//.test(l)).length : 0;
  m.network = {
    enforced: !!HARD.pinnedIndexes, sessions: net.sessions, unrecorded: net.unrecorded,
    indexCopies: net.indexCopies, notFound: net.notFound, bad: net.bad,
    serveLog: log.error ? { error: log.error } : { path: log.path, from: log.from, bytes: log.bytes, galleryLines, indexCopies: serverCopies.slice(0, 50), indexCopyLines: serverCopies.length, notFoundLines: server404.length, notFound: server404.slice(0, 50) },
  };
  Object.assign(m, { tests: docs.length, sessions, totals, emptyConsoleErrors: empty, cancelReplies: cancels, bad, recordOnly });
  console.log(`C14 ${docs.length} tests, ${sessions} sessions, totals ${JSON.stringify(totals)}, empty errors ${empty} (cancel replies ${cancels}), bad ${bad.length}`);
  console.log(`C14 network (${m.network.enforced ? 'enforced: hardening.pinnedIndexes' : 'recorded only'}): ${net.sessions} sessions, index copies ${net.indexCopies.length}, 404s ${net.notFound.length}, bad ${net.bad.length}; serve log ${log.error ? log.error : `${serverCopies.length} copy line(s), ${server404.length} 404 line(s) since offset ${log.from}`}`);
  expect(docs.length).toBeGreaterThan(10);
  expect(bad).toEqual([]);
  if (HARD.pinnedIndexes) {
    // QED64 #64: no per-build index copy anywhere in the run, by Playwright's record and by the server's own log
    expect(net.bad, '#64: every session\'s network oracle (no per-build index copy, no unexpected 404)').toEqual([]);
    expect(net.indexCopies, '#64: no per-build index copy requested by any session').toEqual([]);
    expect(log.error || null, 'the run\'s serve.mjs log is readable from run-meta.json serveLog').toBeNull();
    expect(galleryLines, 'serve log not recording (QUIET=1, or another server on the port?): no GET /showcase/ line since the run started').toBeGreaterThanOrEqual(1);
    expect(serverCopies, '#64: no per-build index copy reached serve.mjs during the run').toEqual([]);
  }
});
