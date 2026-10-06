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
 * (epoch ms). The replies of one code form ONE pool shared by every pairWith entry of that code (a reply explains one line
 * over the run, whichever entry the line matched). Fail-closed: without `reports` every such record is unexplained. So a run that logs an empty
 * console.error for any other reason fails even though the entry has no count limit.
 * A pairWith may also narrow the replies that can explain its lines (pin G, C22's rpcKeepAliveStarved): `qed64Kind` (the tap's
 * error.data.qed64.kind; null = Lean's own reply, not one the relay made) and `message` (a regex on the reply's message). Entries
 * whose pairWith carries no such filter share the one pool of their code, as before; a filtered entry draws on its own pool of
 * exactly the replies its filter admits.
 * Scenario entries (onlyInScenarios) carry `line0` and `pairWith` the same way as the always-allowed entries.
 * Rules are tried in order and the FIRST match wins, so two scenarios whose entries overlap can loosen each other (an unpaired
 * entry ahead of a paired one switches the pairing off). `allow.exclusiveScenarios` lists groups that must never be declared
 * together: a verdict that declares two scenarios of one group is not ok (`conflicts`), whatever was logged.
 * Returns {ok, unexpected:[…], overLimit:[…], unpaired:[…], conflicts:[…], counts:{entryKey: n}, paired:{entryKey: {n, replies}}, loads, scenarios}.
 */
export function classifyConsole(watch, allow, { scenarios = [], reports = undefined } = {}) {
  const re = (x) => new RegExp(x);
  const never = (s) => (allow.neverAllowed || []).find((n) => String(s).includes(n)) || null;
  const conflicts = (allow.exclusiveScenarios || []).map((g) => g.scenarios.filter((x) => scenarios.includes(x))).filter((both) => both.length > 1);
  const rules = [];
  (allow.pageerror || []).forEach((r, i) => rules.push({ key: `pageerror[${i}]`, kind: 'pageerror', ...r }));
  (allow.consoleError || []).forEach((r, i) => rules.push({ key: `consoleError[${i}]`, kind: 'error', ...r }));
  (allow.consoleWarning || []).forEach((r, i) => rules.push({ key: `consoleWarning[${i}]`, kind: 'warning', ...r }));
  for (const sc of scenarios) {
    const list = (allow.onlyInScenarios || {})[sc];
    if (!list) throw new Error(`classifyConsole: unknown scenario ${sc}`);
    list.forEach((r, i) => {
      if (r.consoleError) rules.push({ key: `${sc}[${i}]`, kind: 'error', text: r.consoleError, url: r.url || null, ...(r.line0 !== undefined ? { line0: r.line0 } : {}), ...(r.pairWith ? { pairWith: r.pairWith } : {}) });
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
  // ONE reply pool per lspErrorCode, shared by every pairWith entry of that code (the empty -32800 line and pin G's
  // "client cancelled" -32800 line draw on the same replies): each LSP reply explains one line over the run, whichever entry
  // that line matched. The records of a code are paired in wall order, each within its own entry's window.
  const paired = {}; const pools = new Map();
  // a pool per code AND reply filter (qed64Kind, message): unfiltered entries of one code share one pool, as before
  const poolKey = (pw) => JSON.stringify([pw.lspErrorCode, Object.prototype.hasOwnProperty.call(pw, 'qed64Kind') ? ['kind', pw.qed64Kind] : null, pw.message || null]);
  const admits = (pw, x) => (!Object.prototype.hasOwnProperty.call(pw, 'qed64Kind') || (x.qed64Kind ?? null) === pw.qed64Kind) && (!pw.message || re(pw.message).test(String(x.message ?? '')));
  for (const { rule } of Object.values(pairedRecs)) {
    const pw = rule.pairWith; const k = poolKey(pw);
    if (!pools.has(k)) pools.set(k, { replies: (reports || []).filter((x) => x && x.kind === 'errorReply' && x.code === pw.lspErrorCode && Number.isFinite(x.recvWall) && admits(pw, x)).map((x) => ({ w: x.recvWall, used: false })), recs: [] });
  }
  for (const [key, { rule, recs: list }] of Object.entries(pairedRecs)) {
    const pool = pools.get(poolKey(rule.pairWith));
    for (const rec of list) pool.recs.push({ key, rule, rec });
    paired[key] = { n: list.length, replies: pool.replies.length };
  }
  for (const { replies, recs: list } of pools.values()) {
    for (const { key, rule, rec } of [...list].sort((a, b) => (a.rec.wall || 0) - (b.rec.wall || 0))) {
      const pw = rule.pairWith;
      const k = Number.isFinite(rec.wall) ? replies.find((x) => !x.used && x.w >= rec.wall - pw.beforeMs && x.w <= rec.wall + pw.afterMs) : null;
      if (k) k.used = true;
      else unpaired.push({ key, t: rec.t, url: rec.url || null, line: rec.line ?? null, why: !reports ? 'no LSP tap reports passed (fail-closed)' : !Number.isFinite(rec.wall) ? 'record has no wall time' : `no unused LSP ${pw.lspErrorCode} reply${Object.prototype.hasOwnProperty.call(pw, 'qed64Kind') ? ` (qed64Kind ${JSON.stringify(pw.qed64Kind)})` : ''}${pw.message ? ` (message /${pw.message}/)` : ''} within -${pw.beforeMs}/+${pw.afterMs} ms` });
    }
  }
  const loads = watch.loads || { qed64: 1, infoview: 1 };
  for (const r of rules) {
    const n = counts[r.key] || 0;
    if (r.maxPerPageLoad !== undefined && n > r.maxPerPageLoad * Math.max(1, loads.qed64)) overLimit.push({ key: r.key, n, max: r.maxPerPageLoad * Math.max(1, loads.qed64), per: 'QED64 page load' });
    if (r.maxPerInfoviewLoad !== undefined && n > r.maxPerInfoviewLoad * Math.max(1, loads.infoview)) overLimit.push({ key: r.key, n, max: r.maxPerInfoviewLoad * Math.max(1, loads.infoview), per: 'InfoView load' });
  }
  return { ok: !watch.crashed && !unexpected.length && !overLimit.length && !unpaired.length && !conflicts.length, crashed: !!watch.crashed, unexpected, overLimit, unpaired, conflicts, counts, paired, loads, scenarios };
}
/** One line for the log. */
export const consoleLine = (c) => `CONSOLE ${c.ok ? 'OK' : 'FAIL'} counts ${JSON.stringify(c.counts)} loads ${JSON.stringify(c.loads)}${c.scenarios.length ? ` scenarios ${c.scenarios}` : ''}${c.unexpected.length ? ` UNEXPECTED ${JSON.stringify(c.unexpected.slice(0, 5))}` : ''}${c.overLimit.length ? ` OVER-LIMIT ${JSON.stringify(c.overLimit)}` : ''}${c.unpaired && c.unpaired.length ? ` UNPAIRED ${c.unpaired.length} ${JSON.stringify(c.unpaired.slice(0, 3))}` : ''}${c.paired && Object.keys(c.paired).length ? ` paired ${JSON.stringify(c.paired)}` : ''}${c.conflicts && c.conflicts.length ? ` CONFLICTING-SCENARIOS ${JSON.stringify(c.conflicts)}` : ''}${c.crashed ? ' CRASHED' : ''}`;

