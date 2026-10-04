// Console classification for the bring-up runs (widgets.mjs, hints.mjs, questions.mjs) and the unit tests in
// scripts/check-gallery.mjs. Pure: no Playwright, no file access. The allowlist is tests/ux/selectors.json
// consoleAllowlist (justified in gallery/README.md "Console messages").
/**
 * Classify every recorded console message / page error against tests/ux/selectors.json consoleAllowlist (the
 * gallery README's "Console messages" table). Only `error` and `warning` console messages and page errors are
 * classified (log/info/debug are not failures). A record is allowed iff it matches an allowlist entry (always
 * allowed, or one of `scenarios`: e.g. 'relayRestartOrReboot', 'crashBreakerTripped') and contains no `neverAllowed`
 * substring; per-load limits (maxPerPageLoad per QED64 page load, maxPerInfoviewLoad per InfoView load) are then
 * enforced. A crash always fails.
 * Pairing (bring-up audit 5 minor): an entry with `pairWith: {lspErrorCode, beforeMs, afterMs}` (the empty
 * NotificationService console.error) is allowed only when EACH such record is explained by its own LSP error reply
 * with that code seen by the LSP tap (tests/ux/lib/lsp-tap.mjs; `reports` = the tap's __uxReport records
 * {kind:'errorReply', code, recvWall}) with recvWall in [rec.wall - beforeMs, rec.wall + afterMs]. Records need `wall`
 * (epoch ms). Fail-closed: without `reports` every such record is unexplained. So a run that logs an empty
 * console.error for any other reason fails even though the entry has no count limit.
 * Returns {ok, unexpected:[…], overLimit:[…], unpaired:[…], counts:{entryKey: n}, paired:{entryKey: {n, replies}}, loads, scenarios}.
 */
export function classifyConsole(watch, allow, { scenarios = [], reports = undefined } = {}) {
  const re = (x) => new RegExp(x);
  const never = (s) => (allow.neverAllowed || []).find((n) => String(s).includes(n)) || null;
  const rules = [];
  (allow.pageerror || []).forEach((r, i) => rules.push({ key: `pageerror[${i}]`, kind: 'pageerror', ...r }));
  (allow.consoleError || []).forEach((r, i) => rules.push({ key: `consoleError[${i}]`, kind: 'error', ...r }));
  (allow.consoleWarning || []).forEach((r, i) => rules.push({ key: `consoleWarning[${i}]`, kind: 'warning', ...r }));
  for (const sc of scenarios) {
    const list = (allow.onlyInScenarios || {})[sc];
    if (!list) throw new Error(`classifyConsole: unknown scenario ${sc}`);
    list.forEach((r, i) => {
      if (r.consoleError) rules.push({ key: `${sc}[${i}]`, kind: 'error', text: r.consoleError, url: r.url || null });
      if (r.pageerror) rules.push({ key: `${sc}[${i}]`, kind: 'pageerror', message: r.pageerror, stackIncludes: r.stackIncludes || null });
      if (r.consoleWarning) rules.push({ key: `${sc}[${i}]`, kind: 'warning', text: r.consoleWarning, url: r.url || null });
    });
  }
  const matches = (r, rec) => {
    if (r.kind === 'pageerror') return re(r.message).test(rec.message) && (!r.stackIncludes || String(rec.stack || '').includes(r.stackIncludes));
    if (r.kind !== rec.type) return false;
    if (!re(r.text).test(rec.text)) return false;
    if (r.url && !String(rec.url || '').startsWith(r.url)) return false;
    if (r.line0 !== undefined && rec.line !== r.line0) return false;
    return true;
  };
  const counts = {}; const unexpected = []; const overLimit = []; const unpaired = []; const pairedRecs = {};
  const recs = [
    ...watch.pageErrors.map((p) => ({ ...p, type: 'pageerror' })),
    ...watch.messages.filter((m) => m.type === 'error' || m.type === 'warning'),
  ];
  for (const rec of recs) {
    const body = rec.type === 'pageerror' ? `${rec.message}\n${rec.stack || ''}` : rec.text;
    const nv = never(body);
    const r = nv ? null : rules.find((x) => matches(x, rec));
    if (!r) { unexpected.push({ type: rec.type, t: rec.t, text: String(rec.type === 'pageerror' ? rec.message : rec.text).slice(0, 200), url: rec.url || null, line: rec.line ?? null, never: nv }); continue; }
    counts[r.key] = (counts[r.key] || 0) + 1;
    if (r.pairWith) (pairedRecs[r.key] || (pairedRecs[r.key] = { rule: r, recs: [] })).recs.push(rec);
  }
  const paired = {};
  for (const [key, { rule, recs: list }] of Object.entries(pairedRecs)) {
    const pw = rule.pairWith;
    const replies = (reports || []).filter((x) => x && x.kind === 'errorReply' && x.code === pw.lspErrorCode && Number.isFinite(x.recvWall)).map((x) => ({ w: x.recvWall, used: false }));
    for (const rec of [...list].sort((a, b) => (a.wall || 0) - (b.wall || 0))) {
      const k = Number.isFinite(rec.wall) ? replies.find((x) => !x.used && x.w >= rec.wall - pw.beforeMs && x.w <= rec.wall + pw.afterMs) : null;
      if (k) k.used = true;
      else unpaired.push({ key, t: rec.t, url: rec.url || null, line: rec.line ?? null, why: !reports ? 'no LSP tap reports passed (fail-closed)' : !Number.isFinite(rec.wall) ? 'record has no wall time' : `no unused LSP ${pw.lspErrorCode} reply within -${pw.beforeMs}/+${pw.afterMs} ms` });
    }
    paired[key] = { n: list.length, replies: replies.length };
  }
  const loads = watch.loads || { qed64: 1, infoview: 1 };
  for (const r of rules) {
    const n = counts[r.key] || 0;
    if (r.maxPerPageLoad !== undefined && n > r.maxPerPageLoad * Math.max(1, loads.qed64)) overLimit.push({ key: r.key, n, max: r.maxPerPageLoad * Math.max(1, loads.qed64), per: 'QED64 page load' });
    if (r.maxPerInfoviewLoad !== undefined && n > r.maxPerInfoviewLoad * Math.max(1, loads.infoview)) overLimit.push({ key: r.key, n, max: r.maxPerInfoviewLoad * Math.max(1, loads.infoview), per: 'InfoView load' });
  }
  return { ok: !watch.crashed && !unexpected.length && !overLimit.length && !unpaired.length, crashed: !!watch.crashed, unexpected, overLimit, unpaired, counts, paired, loads, scenarios };
}
/** One line for the log. */
export const consoleLine = (c) => `CONSOLE ${c.ok ? 'OK' : 'FAIL'} counts ${JSON.stringify(c.counts)} loads ${JSON.stringify(c.loads)}${c.scenarios.length ? ` scenarios ${c.scenarios}` : ''}${c.unexpected.length ? ` UNEXPECTED ${JSON.stringify(c.unexpected.slice(0, 5))}` : ''}${c.overLimit.length ? ` OVER-LIMIT ${JSON.stringify(c.overLimit)}` : ''}${c.unpaired && c.unpaired.length ? ` UNPAIRED ${c.unpaired.length} ${JSON.stringify(c.unpaired.slice(0, 3))}` : ''}${c.paired && Object.keys(c.paired).length ? ` paired ${JSON.stringify(c.paired)}` : ''}${c.crashed ? ' CRASHED' : ''}`;

