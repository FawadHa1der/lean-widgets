// The `ux` fixture: sessions launched through it are console-classified and closed in teardown; a test whose
// sessions logged anything outside the allowlist fails (C14 is enforced per test, and aggregated by 99-hygiene).
// The network oracle (lib/qed64.mjs networkVerdict: no per-build index copy, no unexpected 404) is taken per session the same
// way; it fails the test only on a pin with hardening.pinnedIndexes (QED64 #64), older pins record it.
// Traces: @playwright/test records every context of a test (config trace: 'retain-on-failure').
import { test as base, expect } from '@playwright/test';
import { launch, writeTestMetrics, consoleLine, chromeRss, networkVerdict } from './qed64.mjs';

export const test = base.extend({
  ux: async ({}, use, testInfo) => {
    const t0 = Date.now();
    const ctl = { sessions: [], verdicts: [], metrics: { startedAt: new Date().toISOString() }, scenarios: [], notes: [], recordOnly: false };
    ctl.launch = async (opts = {}) => { const s = await launch(testInfo, opts); ctl.sessions.push(s); return s; };
    /** Classify and close one session now (frees its memory before the next launch). */
    ctl.close = async (s, { scenarios = ctl.scenarios } = {}) => {
      if (s.closed) return s.verdictRec;
      const v = s.verdict({ scenarios });
      const ns = s.networkSummary();
      s.verdictRec = { label: s.label, ok: v.ok, line: consoleLine(v), counts: v.counts, loads: v.loads, unexpected: v.unexpected, overLimit: v.overLimit, conflicts: v.conflicts, emptyErrors: v.emptyErrors, crashed: v.crashed, scenarios: v.scenarios, bytes: s.bytes, network: { ...ns, ...networkVerdict(ns, scenarios) } };
      ctl.verdicts.push(s.verdictRec);
      await s.close();
      return s.verdictRec;
    };
    await use(ctl);
    for (const s of ctl.sessions) if (!s.closed) await ctl.close(s);
    const bad = ctl.verdicts.filter((v) => !v.ok);
    // the network oracle fails a test only where it is enforced (hardening.pinnedIndexes)
    const netBad = ctl.verdicts.filter((v) => v.network && v.network.enforced && !v.network.ok);
    // under its own key: `network` in the metrics belongs to the test (C1's ask-1 VERIFY record, C14's run aggregate)
    const networkSessions = ctl.verdicts.map((v) => ({ label: v.label, ok: v.network.ok, enforced: v.network.enforced, reasons: v.network.reasons, requests: v.network.requests, indexCopies: v.network.indexCopies.length, notFound: v.network.notFound.length }));
    // the test's own outcome goes under testStatus (C6/C7 record a QED64 `status` of their own)
    const testStatus = bad.length && !ctl.recordOnly ? 'failed (console)' : netBad.length && !ctl.recordOnly ? 'failed (network)' : testInfo.status;
    writeTestMetrics(testInfo, { ...ctl.metrics, testStatus, recordOnly: !!ctl.recordOnly, durationMs: Date.now() - t0, console: ctl.verdicts, networkSessions, notes: ctl.notes, rssAtEnd: chromeRss() });
    for (const v of ctl.verdicts) console.log(`[${testInfo.title.split(' ')[0]}] ${v.label} ${v.line} NETWORK ${v.network.ok ? 'OK' : `${v.network.enforced ? 'FAIL' : 'recorded'} ${v.network.reasons.join(' | ')}`}`);
    // record-only tests (C18) keep their verdict in the metrics but do not fail on it
    const fails = [];
    if (bad.length && !ctl.recordOnly) fails.push(`console oracle failed: ${bad.map((v) => v.line).join(' | ')}`);
    if (netBad.length && !ctl.recordOnly) fails.push(`network oracle failed: ${netBad.map((v) => `${v.label}: ${v.network.reasons.join('; ')}`).join(' | ')}`);
    if (fails.length) throw new Error(fails.join(' || '));
  },
});
export { expect };
