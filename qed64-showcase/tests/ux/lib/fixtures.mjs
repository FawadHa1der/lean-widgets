// The `ux` fixture: sessions launched through it are console-classified and closed in teardown; a test whose
// sessions logged anything outside the allowlist fails (C14 is enforced per test, and aggregated by 99-hygiene).
// Traces: @playwright/test records every context of a test (config trace: 'retain-on-failure').
import { test as base, expect } from '@playwright/test';
import { launch, writeTestMetrics, consoleLine, chromeRss } from './qed64.mjs';

export const test = base.extend({
  ux: async ({}, use, testInfo) => {
    const t0 = Date.now();
    const ctl = { sessions: [], verdicts: [], metrics: { startedAt: new Date().toISOString() }, scenarios: [], notes: [], recordOnly: false };
    ctl.launch = async (opts = {}) => { const s = await launch(testInfo, opts); ctl.sessions.push(s); return s; };
    /** Classify and close one session now (frees its memory before the next launch). */
    ctl.close = async (s, { scenarios = ctl.scenarios } = {}) => {
      if (s.closed) return s.verdictRec;
      const v = s.verdict({ scenarios });
      s.verdictRec = { label: s.label, ok: v.ok, line: consoleLine(v), counts: v.counts, loads: v.loads, unexpected: v.unexpected, overLimit: v.overLimit, conflicts: v.conflicts, emptyErrors: v.emptyErrors, crashed: v.crashed, scenarios: v.scenarios, bytes: s.bytes };
      ctl.verdicts.push(s.verdictRec);
      await s.close();
      return s.verdictRec;
    };
    await use(ctl);
    for (const s of ctl.sessions) if (!s.closed) await ctl.close(s);
    const bad = ctl.verdicts.filter((v) => !v.ok);
    // the test's own outcome goes under testStatus (C6/C7 record a QED64 `status` of their own)
    writeTestMetrics(testInfo, { ...ctl.metrics, testStatus: bad.length && !ctl.recordOnly ? 'failed (console)' : testInfo.status, recordOnly: !!ctl.recordOnly, durationMs: Date.now() - t0, console: ctl.verdicts, notes: ctl.notes, rssAtEnd: chromeRss() });
    for (const v of ctl.verdicts) console.log(`[${testInfo.title.split(' ')[0]}] ${v.label} ${v.line}`);
    // record-only tests (C18) keep their verdict in the metrics but do not fail on it
    if (bad.length && !ctl.recordOnly) throw new Error(`console oracle failed: ${bad.map((v) => v.line).join(' | ')}`);
  },
});
export { expect };
