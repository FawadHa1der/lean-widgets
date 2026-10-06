// The LSP tap init script shared by the UX suite (tests/ux/lib/qed64.mjs) and the gallery bring-up runs
// (tests/ux/bringup/lib.mjs installTap): one source, so both console oracles pair the empty NotificationService
// console.error with the same LSP RequestCancelled (-32800) replies (bring-up audit 5 minor).
// ------------------------------------------------------------------ the tap (diagnostics + LSP error replies)
// Installed by an init script into every frame; it only acts in the QED64 page document (pathname '/'). It wraps
// qed64.relay.toClient as soon as the page assigns globalThis.qed64 (before the editor starts, so even the boot-time
// codeAction cancellation is seen). The relay calls this.toClient dynamically (lsp-relay.ts:137,218). Records
// publishDiagnostics per document version (window.__uxTap.pub), the page-clock time of every $/lean/rpc/connect the editor
// sends (tap.connectAt: C22's reconnect-after-the-burst witness, compared with the error replies' own page-clock `t`), and reports every LSP error reply to Node through
// the exposed binding __uxReport (survives reloads): RequestCancelled (-32800) and, since QED64's edit coalescing
// (EMBEDDING.md §7.8), ContentModified (-32801, error.data.qed64.kind 'superseded') alike — both pair with lean4monaco's
// logged console.error lines (selectors.json consoleAllowlist pairWith, fail-closed without these reports); the reply's
// error.data.qed64.kind travels with the report. Counts every other frame (tap.frames, tap.lastFrameAt: the hang
// capture's "did any LSP frame arrive" signal). On a v1 page the relay's toClient/fromClient are already the page's own
// wrappers (frontend/src/relay-taps.ts); this tap wraps those, so it sees what the editor receives. Never throws into the relay.
export const TAP_SRC = `(() => {
  try { if (location.pathname !== '/' || window.__uxTapInstalled) return; } catch (e) { return; }
  window.__uxTapInstalled = true;
  const tap = window.__uxTap = { pub: [], errReplies: [], calls: {}, connectAt: [], installedAt: null, frames: 0, lastFrameAt: null, probeReplies: 0 };
  const rep = (o) => { try { if (typeof window.__uxReport === 'function') window.__uxReport(o); } catch (e) {} };
  let wrapped = null;
  const tryInstall = () => {
    let r = null; try { r = window.qed64 && window.qed64.relay; } catch (e) { r = null; }
    if (!r || r === wrapped || typeof r.toClient !== 'function' || typeof r.fromClient !== 'function') return false;
    const tc = r.toClient, fc = r.fromClient;
    r.toClient = function (m) {
      try {
        // the gallery's liveness probe (string ids showcase-live-<n>; gallery.js swallows the reply): not editor traffic,
        // so it is neither an LSP frame for the hang capture nor an error reply the console oracle could pair with
        if (m && typeof m.id === 'string' && m.id.indexOf('showcase-live-') === 0 && m.method === undefined) { tap.probeReplies++; return tc.apply(this, arguments); }
        tap.frames++; tap.lastFrameAt = Date.now();
        if (m && m.method === 'textDocument/publishDiagnostics') {
          tap.pub.push({ t: Date.now(), version: m.params.version, diags: (m.params.diagnostics || []).map((d) => ({ sev: d.severity == null ? 1 : d.severity, line: d.range.start.line, character: d.range.start.character, msg: String(d.message).slice(0, 400) })) });
          if (tap.pub.length > 600) tap.pub.splice(0, 300);
        } else if (m && m.id !== undefined && m.error) {
          // error.data.qed64.kind: 'superseded' on a -32801 (§7.8), 'restart' | 'halted' | 'orphaned' on the relay's own. Carried as
          // qed64Kind: the report's own kind stays 'errorReply' (classifyConsole pairWith and classify() select on it)
          const qk = m.error.data && m.error.data.qed64 ? m.error.data.qed64.kind : undefined;
          const e = { t: Date.now(), id: m.id, code: m.error.code, message: String(m.error.message || '').slice(0, 200), qed64Kind: qk === undefined ? null : String(qk) };
          tap.errReplies.push(e); if (tap.errReplies.length > 600) tap.errReplies.splice(0, 300);
          rep({ kind: 'errorReply', ...e });
        }
      } catch (e) {}
      return tc.apply(this, arguments);
    };
    r.fromClient = function (m) { try { if (m && m.method) { const k = typeof m.id === 'string' && m.id.indexOf('showcase-live-') === 0 ? 'showcase-live' : m.method; tap.calls[k] = (tap.calls[k] || 0) + 1; if (k === '$/lean/rpc/connect') { tap.connectAt.push(Date.now()); if (tap.connectAt.length > 200) tap.connectAt.splice(0, 100); } } } catch (e) {} return fc.apply(this, arguments); };
    wrapped = r; tap.installedAt = Date.now(); rep({ kind: 'tapInstalled', t: Date.now() });
    return true;
  };
  const fast = setInterval(() => { if (tryInstall()) { clearInterval(fast); setInterval(tryInstall, 1000); } }, 2);
})();`;
