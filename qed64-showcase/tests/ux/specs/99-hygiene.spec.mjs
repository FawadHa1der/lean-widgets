// C14 console hygiene across the whole suite: every test of this run classified its sessions' console with EXACTLY
// tests/ux/selectors.json consoleAllowlist (lib/fixtures.mjs; scenario entries only in the tests that deliberately
// restart or break the checker); this aggregates them. Record-only tests (C18) are listed, not counted.
import fs from 'node:fs';
import path from 'node:path';
import { test, expect } from '../lib/fixtures.mjs';
import { RUN_DIR } from '../lib/qed64.mjs';

test('C14 console hygiene across the suite: 0 unexpected page errors / console errors, 0 crashes, per-load limits held', async ({ ux }) => {
  const m = ux.metrics;
  const dir = path.join(RUN_DIR, 'tests');
  const docs = fs.readdirSync(dir).filter((f) => f.endsWith('.json') && f !== 'C14.json').map((f) => JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')));
  const totals = {}; const bad = []; const recordOnly = []; let sessions = 0; let empty = 0; let cancels = 0;
  for (const d of docs) {
    for (const v of d.console || []) {
      sessions++;
      if (d.recordOnly) { recordOnly.push({ test: d.id, ok: v.ok, line: v.line }); continue; }
      for (const [k, n] of Object.entries(v.counts || {})) totals[k] = (totals[k] || 0) + n;
      if (v.emptyErrors) { empty += v.emptyErrors.count; cancels += v.emptyErrors.cancelReplies; }
      if (!v.ok) bad.push({ test: d.id, session: v.label, line: v.line });
    }
  }
  Object.assign(m, { tests: docs.length, sessions, totals, emptyConsoleErrors: empty, cancelReplies: cancels, bad, recordOnly });
  console.log(`C14 ${docs.length} tests, ${sessions} sessions, totals ${JSON.stringify(totals)}, empty errors ${empty} (cancel replies ${cancels}), bad ${bad.length}`);
  expect(docs.length).toBeGreaterThan(10);
  expect(bad).toEqual([]);
});
