// W1–W8 (BUILD-PLAN §8.2 as amended by docs/TEST-PLAN-DELTAS.md §2), lane L-isolated: one warm-profile gallery boot
// per widget (#<pkg>), then in the REAL InfoView DOM:
//   * every declared cursor (lean/examples/<pkg>.json cursors[]): the panel's full env-independent signature equals
//     the frozen golden (lean/expect/w8/<pkg>.json; dist-lens: lean/expect/dist-lens.json);
//   * every declared click (MakeEditLink / Try this) by a real mouse click: the document changes by exactly the frozen
//     edit (and equals the native post-click file, sha256) and re-checks with 0 errors / 0 warnings; Reset restores;
//   * selections by real shift-clicks (expr-xray 1 and 2 picks, interval-inspector hx): the golden of that selection;
//   * the simp-lens hover popup; the simp-lens code actions through Monaco's quick-fix UI (lightbulb and Cmd/Ctrl+.);
//   * W1/W5 summary toggles; W6 the SVG colour variables (dark InfoView: documented QED64 limitation).
// The L-switch lane (one boot, all widgets via the gallery's setValue) is C3/C4 in 00-boot.spec.mjs.
import { test, expect } from '../lib/fixtures.mjs';
import { Gallery, EXAMPLES, SPECS, GOLDENS, CLICKALL, LIVENESS_MODE, API, RESTART_HOW, screenPath, rel, sleep } from '../lib/qed64.mjs';
import { checkCursor, clickLink, checkSelection, checkHover, checkCodeAction, checkToggle, cursorOfLine, goldenCursor } from '../lib/actions.mjs';

const W = { 'chart-kit': 'W1', 'hasse-view': 'W2', 'interval-inspector': 'W3', 'simp-lens': 'W4', 'expr-xray': 'W5', 'tree-scope': 'W6', 'graph-scope': 'W7', 'dist-lens': 'W8' };

for (const ex of EXAMPLES) {
  const id = ex.id; const spec = SPECS[id]; const gold = GOLDENS[id];
  test(`${W[id]} ${ex.title}: declared cursors, clicks, selections, hovers, code actions in the real InfoView`, async ({ ux }) => {
    const m = ux.metrics; m.widget = id; m.golden = gold.environment && gold.environment.golden;
    const fail = [];
    const resetStalls = [];
    const s = await ux.launch({ profile: 'warm' });
    const g = await Gallery.open(s, { hash: id });
    m.boot = { ms: g.boot.ms, phase: g.boot.s && g.boot.s.phase, shown: g.boot.s && g.boot.s.shown, overlay: g.boot.s && g.boot.s.overlay, bridgeLate: g.boot.s && g.boot.s.bridge.late, installs: g.boot.s && g.boot.s.bridge.installs.map((i) => ({ reason: i.reason, readyState: i.readyState, qed64Present: i.qed64Present })) };
    expect(g.boot.s.phase, 'gallery ready').toBe('ready');
    expect(g.boot.s.shown).toBe(id);
    if (API) {
      // v1 (EMBEDDING.md §2.1, §2.5): the InfoView's editor RPC is native and getWidgetSource is coalesced by the page, so the
      // gallery's D1/D2/D3 bridge stands down on capabilities.editorRpc && widgetSourceCache: never installed, nothing late
      expect(g.boot.s.bridge, 'the bridge stood down on the v1 capabilities').toMatchObject({ installed: false, stoodDown: true, installs: [], late: 0, capabilityMismatch: null });
      expect(g.boot.s.api, 'the gallery obtained the v1 API').toMatchObject({ present: true, embed: true });
      expect(g.boot.s.api.capabilities).toMatchObject({ editorRpc: true, widgetSourceCache: true });
    } else expect(g.boot.s.bridge.late, 'bridge installed before the page module script').toBe(0);
    const q0 = await g.qstatus();
    m.qed64 = { header: q0.header, collision: q0.collision, snapshots: q0.snapshots };

    // ---- cursors
    m.cursors = [];
    for (const c of spec.cursors) {
      const r = await checkCursor(g, id, c);
      m.cursors.push(r);
      if (!r.ok) fail.push(`cursor ${c.line}:${c.character} ${r.unrecognised ? 'Unrecognised error' : r.diffs.slice(0, 3).join('; ')}`);
      if (c === spec.cursors[0]) {
        await g.page.screenshot({ path: screenPath(`W-${id}-gallery.png`) });
        await g.iv.locator('[data-ux-panel]').first().screenshot({ path: screenPath(`W-${id}-panel.png`) }).catch(() => {});
      }
    }
    m.cursorsOk = `${m.cursors.filter((r) => r.ok).length}/${m.cursors.length}`;

    // ---- every text the card quotes for this cursor must be RENDERED (innerText of the panel), not merely present in
    // the DOM (e.g. inside a closed <details>): bring-up audit 4 major / UX audit 1 major. scripts/build-gallery.mjs
    // quotes only leaves the frozen Html renders by default; this asserts it in the real InfoView.
    m.cardClaims = [];
    for (const h of ex.tryThis.filter((x) => x.kind === 'cursor' && (x.claimTexts || []).length)) {
      await g.setCursor(h.line, h.character);
      const pc = await g.expectPanel({ line: h.line, character: h.character }, goldenCursor(id, h.line, h.character).panels[0], { timeoutMs: 30000 });
      const v = pc.equal ? await g.iv.locator('[data-ux-panel]').evaluate((el, claims) => {
        const n = (t) => String(t).replace(/\s+/g, '');
        const vis = n(el.innerText); const dom = n(el.textContent);
        return claims.map((t) => ({ text: t, rendered: vis.includes(n(t)), inDom: dom.includes(n(t)) }));
      }, h.claimTexts) : null;
      m.cardClaims.push({ line: h.lineNumber, character: h.character, claims: v });
    }
    m.hiddenCardClaims = m.cardClaims.flatMap((c) => (c.claims || []).filter((x) => !x.rendered).map((x) => ({ line: c.line, text: x.text, inDom: x.inDom })));
    m.cardClaimsChecked = m.cardClaims.reduce((n, c) => n + (c.claims ? c.claims.length : 0), 0);
    for (const c of m.cardClaims) if (!c.claims) fail.push(`card claims L${c.line}: the panel never equalled its golden`);
    for (const h of m.hiddenCardClaims) fail.push(`card L${h.line} quotes “${h.text}”, which the panel does not render (inDom ${h.inDom})`);

    // ---- W1 / W5 toggles
    if (id === 'chart-kit') { m.toggle = await checkToggle(g, id, spec.cursors[0], 'panel'); if (!m.toggle.ok) fail.push(`toggle ${m.toggle.error}`); }
    if (id === 'expr-xray') {
      m.toggle = await checkToggle(g, id, spec.cursors[0], 'inner'); if (!m.toggle.ok) fail.push(`toggle ${m.toggle.error}`);
      m.togglePanel = await checkToggle(g, id, spec.cursors[0], 'panel'); if (!m.togglePanel.ok) fail.push(`toggle panel ${m.togglePanel.error}`);
    }

    // ---- selections (golden selections[] of this environment, by real shift-clicks)
    m.selections = [];
    for (const gs of gold.selections) {
      const r = await checkSelection(g, id, gs);
      m.selections.push(r);
      if (!r.ok) fail.push(`selection ${r.at} ${JSON.stringify(gs.select)}: ${r.error}`);
      await g.page.screenshot({ path: screenPath(`W-${id}-selection-${m.selections.length}.png`) });
    }

    // ---- hovers
    m.hovers = [];
    for (const gh of gold.hovers) {
      const hint = ex.tryThis.find((h) => h.kind === 'hover');
      const popup = hint && hint.expectHover ? hint.expectHover.popupText : `${gh.exprExplicitText} : ${gh.typeText}`;
      const r = await checkHover(g, id, gh, popup);
      m.hovers.push(r);
      if (!r.ok) fail.push(`hover ${gh.tagText}: ${r.error}`);
    }

    // ---- declared clicks (real mouse), each from the pristine example
    m.clicks = [];
    const ca = CLICKALL[id];
    for (let i = 0; i < gold.clicks.length; i++) {
      const gc = gold.clicks[i];
      const cur = cursorOfLine(id, gc.cursorLine);
      const at = { line: cur.line, character: cur.character };
      const panel = gc.kind === 'makeEditLink' ? goldenCursor(id, at.line, at.character).panels[0] : null;
      const native = ca.links.find((l) => l.kind === gc.kind && l.linkText === gc.linkText && (l.title || null) === (gc.linkTitle || null) && JSON.stringify(l.edit) === JSON.stringify(gc.edit));
      const r = await clickLink(g, ex, { kind: gc.kind, linkText: gc.linkText, title: gc.linkTitle || null, edit: gc.edit, editedSha256: gc.editedSha256 }, at, panel, { elabTimeoutMs: id === 'dist-lens' ? 300000 : 120000 });
      r.goldenEditedSha = !!gc.editedSha256; r.nativeClickAll = native ? native.n : null;
      const st = await g.status(); r.chipEdited = st.edited === true;
      if (i === 0) await g.page.screenshot({ path: screenPath(`W-${id}-after-click.png`) });
      const rs = await g.resetUI(ex, { stalls: resetStalls }); r.resetMs = rs.ms; r.reset = rs.ok;
      if (!(r.ok && r.chipEdited && r.reset)) fail.push(`click ${i} “${gc.linkText || gc.linkTitle}”: ${r.error || (!r.chipEdited ? 'chip not “edited”' : 'reset failed')}`);
      m.clicks.push(r);
    }

    // ---- W4 code actions through Monaco's quick-fix UI
    m.codeActions = [];
    for (let i = 0; i < gold.codeActions.length; i++) {
      const c = gold.codeActions[i];
      const link = gold.clicks[c.sameEditAsClick];
      const r = await checkCodeAction(g, ex, c, { via: i === 0 ? 'lightbulb' : 'keyboard', linkEditedSha256: link && link.editedSha256 });
      m.codeActions.push(r);
      if (i === 0 && r.ok) await g.page.screenshot({ path: screenPath(`W-${id}-codeaction.png`) });
      const rs = await g.resetUI(ex, { stalls: resetStalls }); r.reset = rs.ok;
      if (!(r.ok && r.reset)) fail.push(`code action ${c.line}:${c.character} (${r.via}): ${r.error || 'reset failed'}`);
    }

    // ---- W6: TreeScope colours come from the theme variables (light InfoView; dark is a QED64 limitation)
    if (id === 'tree-scope') {
      await g.setCursor(spec.cursors[0].line, spec.cursors[0].character);
      await g.expectPanel({ line: spec.cursors[0].line, character: spec.cursors[0].character }, goldenCursor(id, spec.cursors[0].line, spec.cursors[0].character).panels[0]);
      m.colours = await g.iv.locator('[data-ux-panel]').evaluate((root) => {
        const shapes = [...root.querySelectorAll('svg circle, svg rect, svg line, svg path, svg text')];
        const attr = shapes.map((e) => `${e.getAttribute('fill') || ''} ${e.getAttribute('stroke') || ''} ${e.getAttribute('style') || ''}`);
        return { shapes: shapes.length, usesVscodeVars: attr.filter((a) => /var\(--vscode-/.test(a)).length, sample: [...new Set(attr.map((a) => (a.match(/var\(--vscode-[\w-]+/g) || []).join(',')))].slice(0, 8), bodyBg: getComputedStyle(document.body).backgroundColor };
      });
      if (!(m.colours.usesVscodeVars > 0)) fail.push('tree-scope draws no shape with a var(--vscode-…) colour');
    }

    const q1 = await g.qstatus();
    m.relay = { workerDeaths: q1.stats.workerDeaths - q0.stats.workerDeaths, reboots: q1.stats.reboots - q0.stats.reboots, rangedChanges: q1.stats.rangedChanges - q0.stats.rangedChanges, userRestarts: q1.stats.userRestarts - q0.stats.userRestarts };
    // a QED64 9fdf9b8+ "wedged" reboot (QED64's own liveness handled an L7; as in C20) is recorded and accepted
    m.l7HandledUpstream = ((await g.status()).liveness.qed64 || {}).wedgedReboots || 0;
    if (m.relay.workerDeaths !== m.l7HandledUpstream || m.relay.reboots !== m.l7HandledUpstream || m.relay.rangedChanges) fail.push(`relay ${JSON.stringify(m.relay)} (QED64 "wedged" reboots: ${m.l7HandledUpstream})`);
    if (m.l7HandledUpstream) ux.scenarios.push('qed64WedgedReboot', 'relayRestartOrReboot');
    // the stall watchdog (QED64 L7): armed at its default, and no false alarm during everything above; a real stall
    // during a click is accepted only when the card surfaced it and Restart Lean recovered it (as in C20)
    const sg = (await g.status()).stall;
    m.stall = { thresholdMs: sg.thresholdMs, tapped: sg.tapped, shown: sg.shown, restarts: sg.restarts, progressMsgs: sg.progressMsgs };
    m.stalls = [...m.clicks.flatMap((c) => c.stalls || []), ...resetStalls];
    // v1: the watchdog's progress comes from the API's fileProgress/diagnostics events (progressMsgs counts them; every ready
    // verdict above delivered a `diagnostics` event, so the count must be > 0), source 'api-events', tapped = the api is held
    if (API ? (sg.thresholdMs !== 45000 || !sg.tapped || sg.source !== 'api-events' || !(sg.progressMsgs > 0)) : (sg.thresholdMs !== 45000 || !sg.tapped)) fail.push(`stall watchdog not armed at 45 s ${JSON.stringify({ ...m.stall, source: sg.source })}`);
    // the liveness probe (L7 mitigation): armed at its defaults; a wedge it declares is restarted by itself (auto) or
    // captured and left to the card (observe); every relay restart is accounted for by a card stall or a liveness restart.
    // v1 (capabilities.liveness): the gallery's own probe is STOOD DOWN (QED64's worker liveness is projected by the API,
    // EMBEDDING.md §2.2): nothing sent, nothing missed, no wedge of its own; the mode is still reported
    const lvw = (await g.status()).liveness;
    m.liveness = { mode: lvw.mode, probe: lvw.probe ?? null, probeAfterMs: lvw.probeAfterMs, sent: lvw.sent, answered: lvw.answered, missed: lvw.missed, late: lvw.late, wedged: lvw.wedged, restarts: lvw.restarts, rateLimited: lvw.rateLimited, restartFailed: lvw.restartFailed, maxAnswerMs: lvw.maxAnswerMs, captures: [...m.clicks.flatMap((c) => (c.captures || []).map((x) => x.file))] };
    if (lvw.mode !== (LIVENESS_MODE || 'auto') || lvw.probeAfterMs !== 10000) fail.push(`liveness probe not armed at its defaults ${JSON.stringify(m.liveness)}`);
    if (API && (lvw.probe !== 'stood-down' || lvw.sent !== 0 || lvw.answered !== 0 || lvw.missed !== 0 || lvw.wedged !== 0 || lvw.restarts !== 0 || !(lvw.qed64 && lvw.qed64.api === true))) fail.push(`v1: the gallery probe did not stand down on capabilities.liveness ${JSON.stringify(m.liveness)}`);
    if (lvw.restartFailed) fail.push(`a liveness restart failed ${JSON.stringify(m.liveness)}`);
    if (sg.shown !== m.stalls.length || m.relay.userRestarts !== m.stalls.length + lvw.restarts) fail.push(`stall card shown ${sg.shown}×, recovered ${m.stalls.length}, liveness restarts ${lvw.restarts}, relay restarts ${m.relay.userRestarts}`);
    for (const x of m.stalls) if (!(x.card && x.card.role === 'alert' && x.restartEvent && x.restartEvent.how === RESTART_HOW)) fail.push(`stall not handled by the card (how ${RESTART_HOW}) ${JSON.stringify(x.card)} ${JSON.stringify(x.restartEvent)}`);
    if (m.stalls.length || lvw.restarts) ux.scenarios.push('stallRestart', 'relayRestartOrReboot');
    if (lvw.mode === 'observe' && lvw.wedged) ux.scenarios.push('livenessObserved');
    m.bridge = await g.bridge();
    if (API) {
      // never installed in v1: bridgeStats() is null and status().bridge keeps saying so after every click and reset
      const bst = (await g.status()).bridge;
      if (m.bridge !== null || !bst || bst.installed !== false || bst.stoodDown !== true || bst.late !== 0 || bst.capabilityMismatch !== null) fail.push(`v1: the bridge was installed after all ${JSON.stringify({ bridgeStats: m.bridge, bridge: bst })}`);
    } else if (m.bridge && m.bridge.errors && m.bridge.errors.length) fail.push(`bridge errors ${m.bridge.errors}`);
    m.screens = [`W-${id}-gallery.png`, `W-${id}-panel.png`].map((f) => rel(screenPath(f)));
    m.summary = { cursors: m.cursorsOk, clicks: `${m.clicks.filter((r) => r.ok).length}/${m.clicks.length}`, selections: `${m.selections.filter((r) => r.ok).length}/${m.selections.length}`, hovers: `${m.hovers.filter((r) => r.ok).length}/${m.hovers.length}`, codeActions: `${m.codeActions.filter((r) => r.ok).length}/${m.codeActions.length}` };
    console.log(`${W[id]} ${id} ${JSON.stringify(m.summary)} boot ${m.boot.ms} ms`);
    await sleep(100);
    expect(fail, `${W[id]} failures`).toEqual([]);
  });
}
