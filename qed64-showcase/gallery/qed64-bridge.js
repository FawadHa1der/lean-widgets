/* qed64-bridge.js — same-origin repair of two InfoView <-> editor RPC defects in QED64's shipped
 * page (lean4monaco 1.1.16 + @leanprover/infoview 0.11.1), with ZERO changes to QED64.
 * Found by experiment X4 (out/experiments/x4.json):
 *
 *  D1 abortSignal: lean4monaco's webview uses the raw Rpc proxy as its EditorApi and the page
 *     registers editorApiOfRpc(...) (lean4monaco/dist/infowebview.js:58; vscode-lean4 rpc.js:135),
 *     so `sendClientRequest(uri, method, params, {abortSignal})` crosses the iframe as
 *     JSON `{abortSignal:{}}` and the page throws "r.abortSignal.addEventListener is not a
 *     function". Every ProofWidgets OfRpcMethod panel (all `mk_rpc_widget%`, ofRpcMethod.tsx:28)
 *     therefore renders "Unrecognised error". Fix: strip the non-serialisable abortSignal before
 *     the page sees the message (cancellation degrades to "let the request finish").
 *  D2 applyEdit / showDocument: vscode-lean4's applyEdit awaits window.showTextDocument(...)
 *     before workspace.applyEdit (infoview.js:303-320); QED64's monaco-vscode-api setup has no
 *     editor-service override, so IEditorService.openEditor is the `unsupported` stub and the
 *     edit is never applied (MainThreadTextEditors.$tryShowTextDocument throws). Fix: apply
 *     applyEdit / showDocument / insertText for the open model directly on the Monaco editor
 *     (qed64.editor) and answer the iframe's RPC ourselves.
 *
 *  D3 widget-source storm (found by the M2 bring-up, out/ux/bringup/rt-hasse.json): @leanprover/infoview's
 *     importWidgetModule caches a module only AFTER its getWidgetSource reply arrives (index.production.min.js
 *     `fb`: `if(hb.has(n))…; await x(e,t,n)…; hb.set(n,…)`), so a panel with N MakeEditLinks fires N concurrent
 *     `Lean.Widget.getWidgetSource` RPCs for the SAME hash (14 for the HasseView cube). Each occupies a Lean task
 *     thread; past the glue's 24 pre-spawned pthread workers emscripten spawns a new Worker per thread, each a V8
 *     isolate holding the 49 MB lean.js glue, and the renderer dies with "V8 javascript OOM (CALL_AND_RETRY_LAST)"
 *     in a fresh pthread isolate. Fix: coalesce. The first request for a hash goes to the page as usual; while it is
 *     in flight, duplicates are held; its reply (seen on qed64.relay.toClient) is cached per hash (the hash IS the
 *     source's content address) and answers every held and later duplicate directly. A failed or lost first
 *     request (error reply, relay reboot, 15 s timeout) releases the held duplicates to the page unchanged.
 *
 * On a QED64 page that implements embedding contract v1 (deps/qed64/docs/EMBEDDING.md §2.1: capabilities.editorRpc
 * for D1/D2, capabilities.widgetSourceCache for D3) the gallery does NOT install this bridge: the page does the
 * repairs itself (HARDENING #56, §2.5), and its InfoView RPC no longer uses the message names matched here. The
 * expando is __showcaseBridge (the __qed64* namespace is QED64's own, §9).
 *
 * Usage (same origin only):  installQed64Bridge(qed64PageWindow[, {edits:false}])  — e.g. iframe.contentWindow
 * of the stock page, or `window` from an init script inside the page. Idempotent. Returns a
 * stats object {stripped, applied, shown, inserted, passed, ws:{fetched, cached, coalesced, released, tapped}} on
 * win.__showcaseBridge. {edits:false} repairs D1 only; {dedupe:false} turns D3 off (diagnostics).
 */
(function () {
  function install(win, opts) {
    if (!win || win.__showcaseBridge) return win && win.__showcaseBridge;
    const fixEdits = !(opts && opts.edits === false); // {edits:false}: repair D1 only (diagnostic mode)
    const dedupe = !(opts && opts.dedupe === false);   // {dedupe:false}: no D3 coalescing (diagnostic mode)
    const stats = { stripped: 0, applied: 0, shown: 0, inserted: 0, passed: 0, errors: [], ws: { fetched: 0, cached: 0, coalesced: 0, released: 0, tapped: false } };
    win.__showcaseBridge = stats;
    const editorOf = () => { try { return win.qed64 && win.qed64.editor; } catch (e) { return null; } };
    const toRange = (r) => ({ startLineNumber: r.start.line + 1, startColumn: r.start.character + 1, endLineNumber: r.end.line + 1, endColumn: r.end.character + 1 });
    const reply = (src, seqNum, result, exception) => {
      const m = { seqNum: seqNum };
      if (exception !== undefined) m.exception = exception; else if (result !== undefined) m.result = result;
      src.postMessage(JSON.stringify(m), '*');
    };
    /** LSP WorkspaceEdit -> edits for the open model, or null when it touches anything else. */
    function editsFor(we, uri) {
      const out = [];
      if (we && we.changes) {
        for (const k of Object.keys(we.changes)) { if (k !== uri) return null; for (const e of we.changes[k]) out.push(e); }
      }
      if (we && Array.isArray(we.documentChanges)) {
        for (const dc of we.documentChanges) {
          if (!dc.textDocument || !Array.isArray(dc.edits) || dc.textDocument.uri !== uri) return null;
          for (const e of dc.edits) out.push(e);
        }
      }
      return out.length ? out : null;
    }
    // ---- D3: getWidgetSource coalescing -------------------------------------------------------------------------
    const WS = 'Lean.Widget.getWidgetSource';
    const wsCache = new Map();     // hash -> result ({sourcetext}) of a successful reply
    const wsHeld = new Map();      // hash -> [{src, seqNum, data, origin}] duplicates waiting for the first reply
    const wsTimers = new Map();    // hash -> timeout releasing the held duplicates if the first reply never comes
    const wsLspIds = new Map();    // LSP request id -> hash (first requests only, seen on relay.fromClient)
    const wsPassing = new Set();   // seqNums of released duplicates: let them through on the re-dispatch
    let tappedRelay = null;
    const hashOf = (p) => (p && p.method === WS && p.params && (typeof p.params.hash === 'string' || typeof p.params.hash === 'number')) ? String(p.params.hash) : null;
    function release(hash) {
      const held = wsHeld.get(hash) || [];
      wsHeld.delete(hash); clearTimeout(wsTimers.get(hash)); wsTimers.delete(hash);
      for (const h of held) {
        stats.ws.released++;
        wsPassing.add(h.seqNum);
        win.dispatchEvent(new win.MessageEvent('message', { data: h.data, origin: h.origin, source: h.src }));
      }
    }
    function answer(hash, result) {
      const held = wsHeld.get(hash) || [];
      wsHeld.delete(hash); clearTimeout(wsTimers.get(hash)); wsTimers.delete(hash);
      for (const h of held) { stats.ws.coalesced++; reply(h.src, h.seqNum, result); }
    }
    /** Tap the relay (once per relay object) to learn the LSP id of each first getWidgetSource and see its reply. */
    function tapRelay() {
      let r = null; try { r = win.qed64 && win.qed64.relay; } catch (e) { r = null; }
      if (!r || typeof r.fromClient !== 'function' || typeof r.toClient !== 'function') return false;
      if (r === tappedRelay) return true;
      const fc = r.fromClient, tc = r.toClient;
      r.fromClient = function (msg) {
        try { if (msg && msg.id !== undefined && msg.method === '$/lean/rpc/call') { const h = hashOf(msg.params); if (h !== null && wsHeld.has(h)) wsLspIds.set(msg.id, h); } } catch (e) { /* never break the relay */ }
        return fc.apply(this, arguments);
      };
      r.toClient = function (msg) {
        try {
          if (msg && msg.id !== undefined && msg.method === undefined && wsLspIds.has(msg.id)) {
            const h = wsLspIds.get(msg.id); wsLspIds.delete(msg.id);
            if (msg.error === undefined && msg.result && typeof msg.result.sourcetext === 'string') { wsCache.set(h, msg.result); answer(h, msg.result); }
            else release(h);
          }
        } catch (e) { stats.errors.push(String(e && e.message || e).slice(0, 200)); }
        return tc.apply(this, arguments);
      };
      tappedRelay = r; stats.ws.tapped = true;
      return true;
    }
    /** true when the message was answered or held here (the caller stops it); false to let it through. */
    function coalesce(ev, m) {
      if (!dedupe || m.args[1] !== '$/lean/rpc/call') return false;
      const hash = hashOf(m.args[2]); if (hash === null) return false;
      if (wsPassing.has(m.seqNum)) { wsPassing.delete(m.seqNum); return false; }
      if (!tapRelay()) return false;
      if (wsCache.has(hash)) { stats.ws.cached++; reply(ev.source, m.seqNum, wsCache.get(hash)); return true; }
      const o = m.args[3];
      const hadSignal = !!(o && typeof o === 'object' && 'abortSignal' in o);
      if (hadSignal) delete o.abortSignal; // held and first copies are re-dispatched clean
      if (wsHeld.has(hash)) { wsHeld.get(hash).push({ src: ev.source, seqNum: m.seqNum, data: JSON.stringify(m), origin: ev.origin }); return true; }
      // the first request for this hash: hold the slot, and send it on to the page ourselves (clean, re-dispatched
      // once, marked so this handler lets the re-dispatch through)
      wsHeld.set(hash, []); stats.ws.fetched++;
      wsTimers.set(hash, setTimeout(() => release(hash), 15000));
      if (hadSignal) stats.stripped++;
      wsPassing.add(m.seqNum);
      win.dispatchEvent(new win.MessageEvent('message', { data: JSON.stringify(m), origin: ev.origin, source: ev.source }));
      return true;
    }

    function handle(ev) {
      if (typeof ev.data !== 'string' || ev.data.charCodeAt(0) !== 123 /* { */) return;
      let m; try { m = JSON.parse(ev.data); } catch (e) { return; }
      if (!m || m.seqNum === undefined || typeof m.name !== 'string' || !Array.isArray(m.args)) return;
      const ed = editorOf();
      const model = ed && ed.getModel && ed.getModel();
      const uri = model ? model.uri.toString() : null;
      try {
        if (m.name === 'sendClientRequest') {
          if (coalesce(ev, m)) { ev.stopImmediatePropagation(); return; }
          const o = m.args[3];
          if (o && typeof o === 'object' && 'abortSignal' in o) {
            delete o.abortSignal; stats.stripped++;
            ev.stopImmediatePropagation();
            win.dispatchEvent(new win.MessageEvent('message', { data: JSON.stringify(m), origin: ev.origin, source: ev.source }));
          }
          return;
        }
        if (!model || !fixEdits) return;
        if (m.name === 'applyEdit') {
          const edits = editsFor(m.args[0], uri);
          if (!edits) { stats.passed++; return; }
          ev.stopImmediatePropagation();
          ed.pushUndoStop();
          ed.executeEdits('qed64-showcase-bridge', edits.map((e) => ({ range: toRange(e.range), text: e.newText, forceMoveMarkers: true })));
          ed.pushUndoStop();
          stats.applied++;
          reply(ev.source, m.seqNum);
          return;
        }
        if (m.name === 'showDocument') {
          const s = m.args[0];
          if (!s || s.uri !== uri) { stats.passed++; return; }
          ev.stopImmediatePropagation();
          if (s.selection) { const r = toRange(s.selection); ed.setSelection(r); ed.revealRangeInCenterIfOutsideViewport(r); }
          ed.focus();
          stats.shown++;
          reply(ev.source, m.seqNum);
          return;
        }
        if (m.name === 'insertText') {
          const text = m.args[0], kind = m.args[1], tdpp = m.args[2];
          if (tdpp && tdpp.textDocument && tdpp.textDocument.uri !== uri) { stats.passed++; return; }
          ev.stopImmediatePropagation();
          const pos = tdpp ? { lineNumber: tdpp.position.line + 1, column: tdpp.position.character + 1 } : ed.getPosition();
          let range, t = text;
          if (kind === 'above') {
            const line = model.getLineContent(pos.lineNumber);
            const indent = (/^\s*/.exec(line) || [''])[0];
            range = { startLineNumber: pos.lineNumber, startColumn: 1, endLineNumber: pos.lineNumber, endColumn: 1 };
            t = indent + text + '\n';
          } else {
            range = { startLineNumber: pos.lineNumber, startColumn: pos.column, endLineNumber: pos.lineNumber, endColumn: pos.column };
          }
          ed.pushUndoStop(); ed.executeEdits('qed64-showcase-bridge', [{ range: range, text: t, forceMoveMarkers: true }]); ed.pushUndoStop();
          stats.inserted++;
          reply(ev.source, m.seqNum);
        }
      } catch (e) {
        stats.errors.push(String(e && e.message || e).slice(0, 200));
      }
    }
    // capture-phase at-target listeners run before lean4monaco's non-capture listener
    win.addEventListener('message', handle, true);
    return stats;
  }
  if (typeof window !== 'undefined') window.installQed64Bridge = install;
  if (typeof module !== 'undefined') module.exports = install;
})();
