# QED64: defects and limitations found while building the widget showcase

**To:** the QED64 owner. **From:** the qed64-showcase build, 2026-10-01 (updated 2026-10-02, 2026-10-03, 2026-10-04 and 2026-10-06).
**Pins (keyed by QED64 commit; docs/REPIN-LOG.md "2026-10-02: multiple pins"; which one is served now: `scripts/showcase.sh
pin current`):** since 2026-10-04 the showcase **serves E `33b0967`** (your main with #55 and #54, on runtime
`wasm64-3ab1c6a9da03bc29`; L9 V2 and S1 below). Until then it served C `5ac5d00` (your interim local main: runtime
`wasm64-4b025db7729c5f89`, `sourceRevision` `qed64-wasm64@9fbb45afcb`, with the #52 worker). A `1859b83` (the first pin, same runtime, old worker) is the fallback; B `9fdf9b8` (runtime
`wasm64-2c18773ecfba45bb`, `sourceRevision` `qed64-wasm64@3ae65d36f9`, kernel 0035) stays registered as L9 evidence;
**D `3b42714`** (your 0035b promote: runtime `wasm64-3ab1c6a9da03bc29`, kernel `a8817d01f9`, parked dedicated threads off)
is registered, rebaked and fully gated, but **staged**: it removes L9 V1 but not V2, and under interleaved reload storms
it was not cleaner than C (V2: D 3/26, C 2/26, A 3/26), so C stayed served then (L9 below; docs/REPIN-LOG.md "final gate").
**E `33b0967`** (your main with #55 lifetime locks and #54, on D's runtime) was registered on 2026-10-04, stormed against
C on our visitor path, gated, and is served (L9 V2 and S1 below; `out/ux/pin-e/RESULTS.md`).
**F `84d594e`** (your `feature/embedding-api` at the commit you named final; embedding contract v1 revision `1.0.0`, on
E's runtime) was registered on 2026-10-05 and was the active pin of our local checkout until 2026-10-06 (now staged),
with the gallery on your page API; it is not browser-gated or deployed, the live site still serves E, and merging the branch into your main is
the user's decision (docs/REPIN-LOG.md, pin F entry).
**G `5c327c2`** (your `feature/embedding-api`: F plus `e4cffcc`, the edit back-pressure on the worker pool and the cap of
6 requests in flight, plus `5c327c2`, the deploy.yml step order; API revision still `1.0.0`, F's runtime) was registered
on 2026-10-06 and is now the **active pin of our local checkout**. F is staged. G is not browser-gated or deployed yet
(docs/REPIN-LOG.md, pin G entry).

**Status as of G `5c327c2` (2026-10-06).** **D1 and D2 are fixed upstream** by your HARDENING #56 (the InfoView's RPC
wrapped inside the webview, `capabilities.editorRpc`; `applyEdit`/`insertText`/`showDocument` implemented on the one
model). **D3**, our `getWidgetSource` coalescing (the workaround for L2, gallery/README.md "QED64 limitations"), **is
fixed upstream** by the page's widget-source cache (EMBEDDING.md §2.5, `capabilities.widgetSourceCache`). On F and G our
bridge stands down completely: the gallery does not install it (`status().bridge.stoodDown`), and the UX suite asserts
that and that the RPC panels and link edits work. That last part awaits the browser gates on G. Pins A–E keep the bridge.
**L9 V2** is unchanged in this report: your #55 is in E, F and G, and our storms are consistent with it but do not confirm
it (L9). **Your HARDENING #59** (below the table) is **fixed in G by `e4cffcc` by your measurement**. We have not
measured it yet.
Every run tally in this report is recomputed by `node scripts/ux-tally.mjs` from the recorded runs.
**The findings below were made on the first pin (A):** QED64 commit `1859b830b3621dbacc1752a818634d06a1c94bd0`
(promote `965c2494`), runtime `wasm64-4b025db7729c5f89` (`sourceRevision` `qed64-wasm64@9fbb45afcb`). That release
is kept as pin A in `release/1859b83/` (until 2026-10-02 `release/wasm64-4b025db7729c5f89/`), so the line references
into it still resolve. The front
end is lean4monaco 1.1.16 with @leanprover/infoview 0.11.1 on both pins (`frontend/package-lock.json` is unchanged).

> **QED64 was not modified.** Nothing was written, built, installed, committed or hard-linked
> under `wasm64-lean-fable/qed64`, `wasm64-lean-kernel`, `wasm64-lean-kernel-build-v4.34.0` or
> `wasm64-lean4game`. All reads used `git --no-optional-locks`, and every build stage was closed with
> `scripts/assert-untouched.sh check <stamp>` → `VERDICT: UNTOUCHED` (later checks say `CHANGED` only
> because your own sessions committed in those trees on 2026-10-01). The showcase runs QED64's
> own `dist/` byte for byte (a pinned clone, verified against `QED64.lock.json`) and works around
> the defects below from outside the page. Line references below point into the pinned sources or
> the pinned bundle (`release/1859b83/dist/assets/index-CzXuAkOQ.js`, which is
> minified, so references are `line:column`). Kernel references are pinned to the runtime's
> `sourceRevision` and written `wasm64-lean-kernel@9fbb45afcb:<path>:<line>` (read with
> `git --no-optional-locks show 9fbb45afcb:<path>`), because that working tree moves on with your
> sessions' commits (at 14:30 EDT on 2026-10-01 its HEAD was `6e28e4bd9d`, after the patch 0035
> draft `9af8a865` and the commits `6b3a491f76` and `3ae65d36f9`; it will have moved again).

**Still present on the new pin (9fdf9b8):** D1 and D2. X4 re-run on the re-pinned stock page at 21:19Z on 2026-10-01
(`out/experiments/x4.json`; the old result is in `rollback/wasm64-4b025db7729c5f89/out-experiments/x4.json`) gives the
same verdict as on the old pin: `applyEditStockPage` BROKEN, `rpcPanelStockPage` BROKEN (`TypeError:
r.abortSignal.addEventListener is not a function` at `sendClientRequest`, `/assets/index-Jv35CWTg.js:1201:12747`),
`makeEditLinkStockApplyEdit` BROKEN; with the bridge both work. The showcase keeps `gallery/qed64-bridge.js`. N1, P1
and L1 were not re-tested in a browser on the new pin; the front end and the packs are unchanged.

| # | What | Severity for users | Our workaround | Suggested fix size |
|---|---|---|---|---|
| D1 | `abortSignal` crosses the InfoView RPC as `{}` → every ProofWidgets `mk_rpc_widget%` panel shows "Unrecognised error" | high: no RPC widget panel renders | `gallery/qed64-bridge.js` strips `abortSignal` (pins A–E) | two lines: move `editorApiOfRpc` to the webview side (lean4monaco). **Fixed upstream in `84d594e` (HARDENING #56, `capabilities.editorRpc`); our bridge stands down on F and G** |
| D2 | `applyEdit`/`showDocument` reach `IEditorService.openEditor` = the `unsupported` stub → Try-this, MakeEditLink and `insertText` never change the text | high: no InfoView link edits the document | the bridge applies the edits on `qed64.editor` (pins A–E) | register an editor-service override (lean4monaco), or intercept in QED64. **Fixed upstream in `84d594e` (HARDENING #56); our bridge stands down on F and G** |
| D3 | N concurrent `Lean.Widget.getWidgetSource` for one hash (a HasseView panel fires 14) each hold a Lean thread, and the pthread pool grows past the renderer's isolate ceiling (L2 in gallery/README.md) | high on the panels that trigger it: the tab crashes | the bridge coalesces them per hash (pins A–E) | cache per hash in the page. **Fixed upstream in `84d594e` (EMBEDDING.md §2.5, `capabilities.widgetSourceCache`); our bridge stands down on F and G** |
| L1 | wasm imports at `OLeanLevel.exported` → non-exposed core `module` defs become axioms (`whnf`/`decide`/`rfl`/reflection stuck, e.g. `Lean.RBMap.ofList`) | medium: wrong-looking failures for specific programs | none possible from outside; documented | runtime policy decision (kernel) |
| N1 | boot console noise: one `Error: unsupported` pageerror and one empty `console.error` per boot | low: breaks strict console oracles | allowlisted in tests | drop `extensionDependencies` from the registered manifest |
| P1 | `ProofWidgets.Component.HtmlDisplay`, `…Panel.SelectionPanel`, SimpleGraph, Catalan and Probability are absent from the served region and the essential pack | medium: `#html` / `with_panel_widgets` / graph and probability demos are refused | our own overlay region | add the two ProofWidgets modules to `QED64.Essential` (and optionally the rest) |
| L7 | the whole Lean runtime can freeze in `elaborating`: the Emscripten main-thread proxy path stops (likely one lost mailbox wake, permanent in `waitAsync` mode) and the pool freezes because `pthread_create` runs under `m_mutex`; the JS thread stays alive, so no death is detected | medium: rare (about 1 hang in 20 C20 runs) but unrecoverable from the stock UI | on the previous pin the gallery's liveness probe restarted the relay after ~20 s; on 9fdf9b8 it defers to yours and is a 30 s fallback; the 45 s stall card stays | **fixed upstream in 9fdf9b8 / `wasm64-2c18773ecfba45bb`** (kernel 0035, message-mode mailbox, 1 s mailbox kick with confirmed rescues, Lean-side liveness reboot); see the L7 status below |
| X1 | `_proc_exit` calls `Module.onExit` only when `!keepRuntimeAlive()`, but resident mode keeps the runtime alive, so a FileWorker exit is never reported as a death | low today (no exit was seen), but it would turn any FileWorker fatal error into an L7-like freeze | none needed so far | **fixed upstream in 9fdf9b8**: the worker's proxied-function table hooks `_proc_exit` / `exitOnMainThread` and reports died `exit` |
| L9 | **new on 9fdf9b8**: reloading a ready page (or a relay restart booting a new worker) crashes the renderer with `V8 javascript OOM (Scavenger: semi-space copy)` (V1) about 2 s after the first reload; the 0034 runtime never did. **A second variant (V2, `MarkCompactCollector: young object promotion failed`, after a later reload) hits every pin we have, 0034 with either worker and 0035b included, in headed Chrome and in chrome-headless-shell** | high for users who reload: the renderer (the tab) dies | none possible from outside the page | yours: see L9 below. V1 needs 0035's parked threads: **your 3b42714 (0035b, cap 0) removes it** (0 V1 in 27 storms); V2 is unchanged by it (D 3/26 = A 3/26 ≈ C 2/26, also in headless-shell) and is not reached by an earlier teardown from a page script (our A/B: your workers already close 7–40 ms after a reload; "Hint for your V2 follow-up" in L9). V2 is 3–5× as frequent when your page runs inside a script-free same-origin iframe (16/48 vs 4/48, p = 0.005; "A repro without our gallery" in L9). **V2: fixed in your 33b0967 (#55)** by your measurement (17/48 → 0/36); ours on our visitor path, E vs C interleaved: 0/28 vs 1/28, consistent with the fix, but C was rare in those windows too, so it does not confirm it ("Your candidate arrived" in L9) |
| N3 | the stock page has no favicon: headed desktop Chrome logs one 404 for `/favicon.ico` per load | cosmetic: breaks strict console checks in a real browser | allowed once per load in our headed run only | ship a favicon or `<link rel="icon" href="data:,">` |
| #59 | **your HARDENING #59**: typing at a normal pace (150 ms/char) above a long uncancellable command (`#eval (IO.sleep 3000 : IO Unit)`, a long kernel check) with the InfoView open grew the pthread pool until the tab crashed, on every build up to F `84d594e`; the edit coalescing window (§7.8) caps bursts, not a sustained pace | medium for the gallery: a visitor who edits above a slow line can lose the tab; none of our eight examples has such a line | none from outside the page | yours (HARDENING #59). **Fixed in G `5c327c2` by your `e4cffcc` per your measurement** (back-pressure keyed on the worker's pool sample, at most 6 requests in flight, a queued request's cancel answered locally); **not yet measured by us** (#59 below) |
| S1 | slow first visits: the boot card is removed 120 s after an idle `ready…` status while the mathlib download still runs, so a 10 Mbit/s visitor sees only elapsed timers for minutes; the card says "~3 GB of memory" while a tab measures 8–9 GB | low–medium: slow links and small machines | none (our gallery has its own boot-timeout defect on such links) | keep the card while bytes arrive; update the memory figure. **Fixed in your 3e182ff (#54), in 33b0967; confirmed by us at 10 Mbit/s** (S1 below) |

---

## D1 — `abortSignal` is serialised across the webview RPC; every `mk_rpc_widget%` panel fails

**Status (2026-10-06): fixed upstream in `84d594e`** (`feature/embedding-api`, HARDENING #56: the webview wraps the
proxy with `editorApiOfRpc`, `capabilities.editorRpc`). On pins F and G the gallery does not install the bridge. The text below
is the original report (pin A).

**Symptom.** Putting the cursor on any `mk_rpc_widget%` panel makes the InfoView render this
instead of the panel:

```
Unrecognised error {"stack":"TypeError: r.abortSignal.addEventListener is not a function
  at sendClientRequest (…/assets/index-CzXuAkOQ.js:1201:12747) …
```

That was captured verbatim by stage-A experiment X4 (`out/experiments/x4.json`, run `b:raw`).
On the stock page this hits Mathlib's own `conv?` panel and all six of our widget modules.

The browser UX suite re-proved it with a mutant: the gallery served with the bridge's
`abortSignal` strip disabled (mutant A, on :5192) makes test C17 (the keyboard walkthrough, whose
console verdict includes an InfoView-DOM scan for forbidden strings) fail with the InfoView DOM text
`Unrecognised error {"stack":"TypeError: r.abortSignal.addEventListener is not a function`
(`$W/logs/ux-fix-mutA2.log`, `1 failed`; `docs/UX-RESULTS.md`, "Audit response"). With the strip
in place the same suite is green (below).

**Minimal repro** (stock page and stock snapshots, no showcase code):

```lean
import Mathlib.Tactic.Widget.Conv

example (a b c : Nat) : a + (b + c) = (c + b) + a := by
  conv?
  omega
```

Put the cursor on `conv?`. Expected: the "Conv 🔍️" selection panel. Actual: the error above.
The script is `tests/experiments/x4-click-paths.mjs` case (b), mode `raw`.

**Root cause.** The InfoView-side and editor-side halves of vscode-lean4's RPC wrapper are
swapped in lean4monaco.

* `@leanprover/infoview` calls `editorApi.sendClientRequest(uri, method, params, {abortSignal})`.
  The call site is ProofWidgets `widget/src/ofRpcMethod.tsx:28`: `rs.call(…, { abortSignal: ac.signal })`.
* vscode-lean4's `editorApiOfRpc` turns a *remote* `EditorRpcApi` (`startClientRequest` /
  `awaitClientRequest`) into a local `EditorApi`. It keeps the `AbortSignal` local and sends only
  ids across. It is documented as "Wrap EditorRpcApi in the more convenient EditorApi. Called
  during infoview initialization." (`lean4monaco/dist/vscode-lean4/vscode-lean4/src/rpc.js:131-160`;
  `addEventListener('abort', …)` is at :158).
* lean4monaco does the opposite.
  * The **webview** hands the raw RPC proxy to the InfoView: `const a=s.getApi() … renderInfoview(a, o)`.
    This is `lean4monaco/dist/webview/webview.js`, single minified line, offset 39273. The served copy
    is `dist/infoview/webview.js`.
  * The **page** wraps its own local `EditorRpcApi` with `editorApiOfRpc` and registers that:
    `rpc.register(editorApiOfRpc(editorRpcApi))` (`lean4monaco/dist/infowebview.js:61`).
  * The messages are `JSON.stringify`'d (`infowebview.js:55`), so the `AbortSignal` arrives on the
    page as `{}`.
  * `editorApiOfRpc`'s `sendClientRequest` then runs `r.abortSignal.addEventListener(…)` on that
    plain object. That is bundle line `index-CzXuAkOQ.js:1201:12747`, verified against the pinned
    bundle text `return r?.abortSignal&&r.abortSignal.addEventListener("abort",…)`.

**Our workaround (shipped, `gallery/qed64-bridge.js`).** A capture-phase `message` listener on the
QED64 page window rewrites `sendClientRequest` messages from the InfoView iframe before
lean4monaco sees them:

* it deletes `args[3].abortSignal` and re-dispatches the cleaned message;
* the cost is that cancellation degrades to "let the request finish".

The gallery installs it on `iframe.contentWindow` while the page is still `loading`. With the
bridge, X4(b) rendered the panel, a shift-click selected `c + b`, and the stats were `stripped 2`.

**Suggested fix in QED64.** QED64 owns lean4monaco through its `package-lock.json`.

* **Upstream fix (lean4monaco):** the webview wraps and the page registers the raw API.
  * `webview.ts`: `const api = editorApiOfRpc(rpc.getApi())`
  * `infowebview.ts`: `rpc.register(editorRpcApi)`

  Both halves move together. With only one of them changed, `startClientRequest` would have no
  receiver.
* **QED64-local, until upstream ships:** a `patch-package` patch of those two lines. Or, smallest
  of all, do in `frontend/src/main.ts` what our bridge does: strip a non-function `abortSignal`
  from `sendClientRequest` before `rpc.messageReceived`.

**Blast radius.** Every ProofWidgets component built on `OfRpcMethod` / `mk_rpc_widget%`
(Mathlib `conv?`, the SelectionPanel family, all user widgets of that shape), plus any InfoView
code that passes `abortSignal` to `sendClientRequest`. The upstream fix also restores real
cancellation, which the InfoView relies on when the cursor moves quickly. Risk is low, because
it restores vscode-lean4's own design. It probably affects every lean4monaco 1.1.16 embedder;
we observed it only in QED64.

---

## D2 — `applyEdit` / `showDocument` hit the `unsupported` editor-service stub; no InfoView link edits the text

**Status (2026-10-06): fixed upstream in `84d594e`** (HARDENING #56: `frontend/src/editor/infoview-edits.ts` implements
the three actions on the one model). On pins F and G the gallery does not install the bridge. The text below is the original
report (pin A).

**Symptom.** Clicking core "Try this" `[apply]`, any ProofWidgets `MakeEditLink` (`conv?`'s
"Generate conv", every widget suggestion), or an `insertText` action changes nothing. The page
logs `Error: unsupported` with a stack through `$tryShowTextDocument`.

**Minimal repro** (stock page, init only):

```lean
example (n : Nat) : n + 0 = n := by simp?
```

Click `[apply]` in the "Try this" message. Expected text: `… := by simp only [Nat.add_zero]`.
Actual: unchanged.

X4 (`out/experiments/x4.json`) shows:

* run `a:raw`: `textChanged False`;
* `x4-debug.json`: the applyEdit RPC did arrive, with
  `{"name":"applyEdit","args":[{"changes":{"file:///project/Probe.lean":[…"newText":"simp only [Nat.add_zero]"}]}}]}`;
* `$W/logs/x4-debug.log`: the stack
  `at Object.L (…index-CzXuAkOQ.js:686:2087) at YL.$tryShowTextDocument (…index-CzXuAkOQ.js:912:21056)`.

The same happens with MakeEditLink (run `b:strip`: D1 repaired, "Generate conv" clicked,
`textChanged False`).

**Root cause.**

* vscode-lean4's InfoView provider implements `applyEdit` as follows
  (`lean4monaco/dist/vscode-lean4/vscode-lean4/src/infoview.js:303-320`). It finds the visible
  Lean editor, then awaits `window.showTextDocument(…)` (:318) *before*
  `workspace.applyEdit(we)` (:319). `showDocument` goes through `revealEditorSelection` the same
  way (:321-327).
* In monaco-vscode-api, `showTextDocument` becomes `MainThreadTextEditors.$tryShowTextDocument`,
  which calls `this._editorService.openEditor(…)`. That call is at bundle `912:21056`, verified
  as `o=await this._editorService.openEditor(r,…)`.
* Without an editor-service override, `openEditor` is the default stub
  `this.openEditor=L` with `function L(){throw new Error("unsupported")}` (bundle `686:2081` and
  `686:2980`).
* lean4monaco's `initialize({...})` registers textmate, theme, configuration, languages and model
  overrides, but **no editor-service override** (`lean4monaco/dist/leanmonaco.js:60-66`). So the
  `await` throws and `workspace.applyEdit` is never reached.
* `LeanMonaco.start()` has no hook for extra service overrides (`leanmonaco.d.ts`,
  `LeanMonacoOptions`), so QED64 cannot add one without patching.

**Our workaround (shipped, `gallery/qed64-bridge.js`).** The same listener answers `applyEdit`,
`showDocument` and `insertText` itself:

* it converts the LSP edits for the open model's URI to Monaco ranges (0-based to 1-based) and
  calls `executeEdits` on `qed64.editor`;
* it then replies to the InfoView's RPC with the same `seqNum`;
* edits for any other URI pass through untouched.

With the bridge:

* X4(a) changed the text to `simp only [Nat.add_zero]` and reached ready at v2 with 0 diagnostics.
* X4(b) produced `conv => enter [2, 1, 1] skip`, with 0 diagnostics.
* Headless, all 135 rendered links in the eight examples apply clean natively (`out/click-all/`),
  and the 21 declared clicks re-elaborate clean in wasm (`docs/HEADLESS-RESULTS.md`).

**Suggested fix in QED64.**

* **Upstream fix (lean4monaco):** add
  `...getEditorServiceOverride(openEditor)` from `@codingame/monaco-vscode-editor-service-override`.
  Version 8.0.4 is already in QED64's `node_modules`, so this needs no new dependency. Pass an
  `openEditor` callback that returns the existing Monaco editor when the requested resource is its
  model (and selects `options.selection`), and `undefined` otherwise.
* **QED64-local:** apply that as a patch, or intercept `applyEdit` / `showDocument` /
  `insertText` in `main.ts` the way the bridge does. The whole bridge, D1 included, is
  `gallery/qed64-bridge.js`: 198 lines, 156 of them code (`wc -l`; comment and blank lines
  excluded by `grep -cvE '^\s*(//|\*|/\*|$)'`), and could be copied directly.

**Blast radius.** Every InfoView-initiated edit or navigation:

* core `Try this` (`Lean.Meta.Hint.textInsertionWidget`: `simp?`, `exact?`, `apply?` and the like);
* every ProofWidgets `MakeEditLink` (`conv?`, `Generate conv`, all six of our RPC widgets' suggestions);
* `insertText` and the InfoView's "go to definition" style `showDocument`.

The editor-service override is the larger change of the two fixes, because other workbench
features may start calling `openEditor`. The callback only needs to handle the single-model case.
The Monaco quick-fix (lightbulb) path is a separate code path, which this report does not cover.

---

## L1 — wasm imports at `OLeanLevel.exported`: non-exposed core definitions become axioms

**Symptom.** Anything that must *unfold* a definition from a core `module` file that is not
`@[expose]`d gets stuck in QED64, though the same file works natively. Our case is TreeScope's
own `Demo.lean` (lines 95-104, run verbatim):

```lean
def rbSample : Lean.RBMap Nat String compare :=
  Lean.RBMap.ofList [(5, "e"), (2, "b"), (8, "h"), (1, "a"), (4, "d"),
                     (7, "g"), (3, "c"), (6, "f")]
#tree_scope rbSample                    -- works in QED64 (semantic view: evaluation, no whnf)
#tree_scope (reflect := true) rbSample  -- QED64: Demo.lean:104:0: error: #tree_scope: `rbSample`
                                        --   does not reduce to a constructor application
                                        -- native Lean v4.34.0: rc 0, 0 errors, 0 warnings
```

These results come from `$W/logs/s4-E2-tree-scope.log` (wasm) and
`$W/logs/s4-E2native-tree-scope.log` (native).

**Repro without the widget.** The probe `$W/headless/rb-whnf.widgets8.exact.lean` prints the
`ConstantInfo` kind of the RBMap functions and runs `whnf rbSample`:

* wasm (w8 snapshot), `$W/logs/s4-diag-rb-whnf.w8.log`:
  * `Lean.RBMap.ofList: AXIOM`, `Lean.RBMap.insert: AXIOM`, `Lean.RBNode.ins: AXIOM`;
  * `whnf rbSample head = @RBMap.ofList`.
* native: `Lean.RBMap.ofList: defn … regular=6`, `whnf rbSample head = @Subtype.mk`.
* The same holds with a fresh wasm import from a tree that **does** contain
  `Lean/Data/RBMap.olean.private` (`s4-diag-rb-whnf.fat.log`). So staging the private facet
  cannot fix it.

**Root cause.**

* `wasm64-lean-kernel@9fbb45afcb:src/Lean/Elab/Import.lean:162-164`: on Emscripten the import
  level is always `.exported` ("Emscripten/WASM builds only have .exported level files, so always
  use that"). The resident cache does the same
  (`wasm64-lean-kernel@9fbb45afcb:src/Lean/Shell.lean:87,102`, `level := .exported`).
* `wasm64-lean-kernel@9fbb45afcb:wasm64-build/PATCHES.md:290` (§0034): "on Emscripten every import
  happens at `OLeanLevel.exported` … the wasm `.exported` policy is ours".
* At `.exported` level, a non-exposed definition of a `module` file is imported as an axiom.
  `wasm64-lean-kernel@9fbb45afcb:src/Lean/Data/RBMap.lean:6` is `module`; only `RBMap` itself is
  `@[expose]` (:264), while `ofList` (:340) is not.
* The worker also hides `.olean.private` facets (`public/workers/lean.worker.js:742`,
  `HIDE_PRIVATE_FACETS = true`, to halve resident import memory).

**Our workaround.** None is possible from outside the runtime. The showcase example avoids
`reflect := true` on core module-system values, and E2 records the Demo's line 104 as the one
root-caused failure (`scripts/headless/known-limitations.json`). The Demo with that line removed
compiles clean in wasm (`$W/logs/s4-diag-tree-scope-no104.log`).

**Suggested fix (a policy decision for you).**

* Import at `.server` level, or at `.private` for the core library only, when the facet exists.
  That costs memory: `.olean.private` is about 60% of pack bytes per the comment at
  `lean.worker.js:735-741`.
* Or keep the policy and document it: in QED64, `decide` / `rfl` / `whnf` / `#reduce` / reflection
  cannot see through non-exposed definitions of core `module` files.

**Blast radius.** QED64-wide, not widget-specific: `decide`, `rfl`, `simp` with `decide := true`,
`#reduce`, and any metaprogram that unfolds core-library definitions (RBMap, HashMap internals,
Std data structures). Mathlib at `5ed2965` is module-system code too: the stage-trees log
classifies the delta as "module-system 39 (dep)". So a Mathlib definition is affected exactly
when its body is not exposed. We did not survey how many are.

---

## N1 — boot console noise: one `Error: unsupported` pageerror and one empty `console.error` per boot

**Symptom.** Every boot of the stock page logs one `pageerror` `Error: unsupported` and one
`console.error` whose text is empty. This happens with or without our bridge (X4 runs `a:raw` and
`a:bridge` both show `pageErrors: ["Error: unsupported…"]`, `errors: ["error: "]`). Strict
console oracles, such as BUILD-PLAN C14 "0 page errors", therefore have to allowlist both.

**Root cause** (the pageerror; the empty `console.error` was not traced).

* The stack (`$W/logs/x4-debug.log`) is
  `at Object.L (index-CzXuAkOQ.js:686:2087) at WQe.$onExtensionActivationError (index-CzXuAkOQ.js:927:12740)`.
  Column 12740 is `await this._extensionsWorkbenchService.queryLocal()`, inside the
  "missing dependency" branch of `$onExtensionActivationError`, and `queryLocal` is the same
  `unsupported` stub.
* The registered extension manifest is vscode-lean4's `package.json`, spread unchanged by
  `LeanMonaco.getExtensionManifest()` (`lean4monaco/dist/leanmonaco.js:182-194`). It declares
  `"extensionDependencies": ["tamasfe.even-better-toml"]`
  (`lean4monaco/dist/vscode-lean4/vscode-lean4/package.json:10-12`), and that extension is never
  registered.
* So activation reports a missing dependency, and the error handler then trips the stub. This
  chain is inferred from the stack and the bundle; we did not step through it.

**Suggested fix.** Override `extensionDependencies: []` in `getExtensionManifest()` (lean4monaco),
or patch it in QED64. This is harmless: the Lean client is started by lean4monaco itself, not by
extension activation.

**Blast radius.** Cosmetic, but every embedder that asserts a clean console has to carry an
allowlist. Separately, the page logs `[qed64] <phase>` on every status change, about 15 lines per
X4 run, which crowds out real errors in captured logs.

---

## N2 — the heap meter leaves an unhandled rejection ("Session disposed.") when a session dies during its probe

**Found by** the showcase's multi-pin lane on 2026-10-02 (UX run `multipin-C-full1`, test C12 on the stock page
`/?snapshots=snapshots/widgets8` with the overlay index cut off, pin `5ac5d00`). **Present in every pin** (1859b83,
9fdf9b8, 5ac5d00: the same code is in all three bundles); rare: 1 of the 18 recorded C12 stock runs.

**Trace.** The third failed boot trips the crash breaker; at that moment the page logs a pageerror
`Error: Session disposed.` whose stack is `ein.dispose (/assets/index-BvT6MV1R.js:1320:8145) ← din.dispose (1321:1295) ←
Jtn.onDied (1320:3044) ← Jtn.boot`, i.e. `LeanSession.dispose()` (`src/runtime/client.ts:388` at 5ac5d00) rejecting
every pending request, called from `LspRelay.onDied` (`frontend/src/lsp-relay.ts:170`) from `boot()`'s catch (:156).
Every request the relay itself issues is awaited. The one that is not is the page's heap meter,
`frontend/src/main.ts` `startMemoryMeter` (:489–513 at 5ac5d00): every 12 s it runs
`void Promise.race([session.request("telemetry", {}), new Promise((r) => setTimeout(() => r(null), 800))]).then(…)`
with **no rejection handler**. When the session is disposed (any death, reboot, restart or halt) within the 800 ms
while that telemetry request is pending, the race rejects and the rejection is unhandled.

**Effect.** Only a console pageerror (no functional effect: the meter just skips a tick). But it is an unexpected page
error for any client that treats unhandled rejections as failures (our UX suite does).

**Suggested fix.** `.catch(() => {})` (or a second `then` argument) on that race, as the heartbeat probe already does
(`client.ts:230`, `this.telemetry().then(…, () => {})`).

**Our handling.** The UX console allowlist accepts exactly this pageerror (`^Session disposed\.$`, stack containing
`.dispose (`) only in the scenarios in which a session is disposed (`bootFailure`, `crashBreakerTripped`,
`relayRestartOrReboot`, `stallRestart`, `qed64WedgedReboot`); anywhere else it still fails the run.

## P1 — widget-critical modules absent from the served region and the essential pack

**Symptom.** On the stock page, a document importing any of these is refused with
`modules [...] are not loaded in this session — use "Load exact imports"`
(`wasm64-lean-kernel@9fbb45afcb:src/Lean/Server/FileWorker.lean:451-452`):

* `ProofWidgets.Component.HtmlDisplay`, needed for `#html` and every static widget panel;
* `ProofWidgets.Component.Panel.SelectionPanel`, needed for `with_panel_widgets [SelectionPanel]`;
* `Mathlib.Combinatorics.SimpleGraph.*`, `Mathlib.Combinatorics.Enumerative.Catalan.*`, `Mathlib.Probability.*`.

"Load exact imports" cannot succeed for them either, because the essential pack does not contain them.

**Minimal repro:**

```lean
import Mathlib
import ProofWidgets.Component.HtmlDisplay
```

**Evidence.**

* The served region's only import is `QED64.Essential` (`public/snapshots/index.json`, mathlib
  entry `"imports": ["QED64.Essential"]`), and its closure is 5,004 modules
  (`bump-51/slim/lib-tree-slim`, stage-trees log `in tree 5004`).
* `wasm64-lean-kernel-build-v4.34.0/mathlib/essential-modules.txt` has 4,354 modules. It contains
  0 `Mathlib.Combinatorics.SimpleGraph|Catalan|Probability` lines, and its ProofWidgets entries
  stop at `Cancellable, Compat, Component.{Basic, FilterDetails, MakeEditLink, OfRpcMethod,
  Panel.Basic, RefreshComponent}, Data.Html, Util`.
* The served `profiles/mathlib-essential.manifest.json` contains 0 occurrences of `HtmlDisplay`,
  `SelectionPanel`, `SimpleGraph`, `Catalan` or `Probability`, against 13 of `MakeEditLink`.
* Our stage-trees delta over the served tree is 39 modules for the seven phase-1 widgets:
  * 28 `SimpleGraph.*`;
  * 2 `Catalan.*`;
  * 7 Data/Order/Algebra helpers;
  * `HtmlDisplay` and `SelectionPanel`.

  It is 609 for all eight, including 61 `Mathlib.Probability.*` and 183 `MeasureTheory.*`
  (`$W/logs/stage-trees-w7.json`, `-w8.json`).
* In the kernel build's Mathlib tree, `SelectionPanel` is a GMP "barrel" olean (official
  toolchain build), which the wasm64 runtime cannot load. It had to be rebuilt with native64
  (`docs/STAGE-A-RESULTS.md`).

**Our workaround.** The showcase bakes its own superset region from QED64.Essential plus the
widget roots, through the vendored `bake-snapshot.mjs`. It serves that region as a `?snapshots=`
overlay, renamed `mathlib`. Measured cost over the stock region:

* w7: +39 delta + 64 own modules; raw 1,163,657,293 B (+36.4 MB), transfer 331,578,421 B (+10.1 MB);
* w8: +609 + 71; raw 1,267,834,573 B (+140.6 MB), transfer 364,676,234 B (+43.2 MB).

(Stock `mathlib` region: raw 1,127,272,685 B, transfer 321,484,932 B; all figures are the `bytes` /
`transfer` fields of the three `snapshots/index.json` files.)

**Suggested fix.**

* Add `ProofWidgets.Component.HtmlDisplay` and `ProofWidgets.Component.Panel.SelectionPanel` to
  `QED64.Essential`. They are tiny, and they are the standard entry points for user widgets. A
  native64 rebuild of SelectionPanel is required, because of the GMP barrel.
* Optionally add `Mathlib.Combinatorics.SimpleGraph.*` and `Catalan`. Our phase-1 numbers are an
  upper bound for these plus the widgets themselves.
* Probability (+MeasureTheory) is the expensive one.

**Blast radius.** Additive: a rebake of the essential region, with the runtime unchanged.

---

## L7 — the whole Lean runtime can freeze in `elaborating` (found by the browser UX suite)

**Status: fixed upstream in QED64 `9fdf9b8` (runtime `wasm64-2c18773ecfba45bb`, kernel `3ae65d36f9`); the showcase is
re-pinned to it** (docs/REPIN-LOG.md). Your fix has four layers, each visible in the pinned sources
(`vendor/qed64/public/workers/lean.worker.js` at 9fdf9b8):

1. **Kernel patch 0035** (`pipeline/toolchain/patches/0035-wasm-task-manager-no-spawn-under-mutex-parked-dedicated-threads.patch`):
   the task manager no longer creates a thread while holding its global mutex, and dedicated tasks reuse parked threads
   (cap 8). The served glue exports `_lean_wasm_task_manager_parked_threads` (absent from the 0034 glue), and the
   worker reports it as `status().pool.parked` (`lean.worker.js:630`; subtract it from `running` for load).
2. **Message-mode runtime mailbox** (`instrumentRuntimeMailbox`, `lean.worker.js:464`, `self.waitAsyncPolyfilled = true`
   at :483 before `initRuntime`): pthreads notify the Emscripten main thread by postMessage, so a served mailbox
   notifies normally again instead of staying dead after one lost wake (our W3 finding).
3. **A 1 s raw mailbox kick with confirmed rescues** (`kickMailbox` :541, `mailboxWatchFired` :585): a notification word
   still `PENDING` 250 ms later with nothing delivered is served and counted (`status().liveness.rescues`; log line
   `[liveness] a runtime-mailbox wakeup was lost … — rescue #n`, :593). A rescue in the field is direct evidence for our
   hypothesis A (a lost wake).
4. **A Lean-side liveness probe** (`LIVENESS` :351, `livenessTick` :397): while work is owed and no server frame has
   arrived for 6 s, the worker writes a `$/qed64/liveness` request the FileWorker answers at once; unanswered for 12 s
   is a stall, and 4 s later the session dies `wedged` (:615); the relay reboots it (`lsp-relay.ts:27,173`, the new
   `rebootReason`) with the pill "the checker stopped responding — restarting (~15 s)" and replays the text.

Also new: the FileWorker exit hook (X1 below) reports died `exit`. A user `#eval (IO.Process.exit n : IO Unit)` is
caught only by that hook, not by any liveness probe.

**What we verified on the new pin** (docs/REPIN-LOG.md): the release, vendor and lock verify against 9fdf9b8; the core
library is byte-identical (2,520 `.olean`, 2,518 `.ir`/`.ir.sig`/`.olean.server`/`.olean.private`; only `libleanrt.a`
members `object.cpp.o`, `io.cpp.o`, `platform.cpp.o` and the githash string in `libleancpp.a` changed), so our natively
built delta and widget oleans are reused; both widget regions were rebaked on the new runtime, judged, paired and
preflighted; the headless stage 4 is green. The gallery detects your liveness (`status().liveness`) and defers to it
(its own probe waits 30 s instead of 10 s, never acts during your stall grace window, and reports your rescues, stalls
and `wedged` reboots). **Field rate on the new pin, measured (2026-10-01/02):** 13 C20 runs (8 observe-mode hunt runs
and 2 full runs of the final lane, the final audit's full run and its extra observe-mode run, and our close-out 2 full
run; 1,755 link clicks, 3,510 edits) showed **0 hangs**, **0 rescues** (`status().liveness.rescues`), 0 stalls, 0 `wedged` reboots and 0
`[liveness]` worker lines (`out/hang/FIELD-CAPTURE.md`; `out/ux/final-hunt1..8`, `final-full1/2`, `audit-final-full`,
`audit-final-c20`, `closeout2-full1`). That sample is **too small to prove the fix**: at the old rate of about 1 hang in
20 C20 runs, 13 clean runs happen with probability 0.95^13 ≈ 0.51; telling "fixed" from "as before" needs on the order of 60 clean runs,
or your fault drills (`0c4478a`). **Totals as of 2026-10-02** (`node scripts/ux-tally.mjs`): **17 C20 runs on 9fdf9b8**
(the 13 above, the first re-pin full run `repin-full1`, the last audit's `audit-cl3-full1` and `audit-cl3-c20`, and
close-out 3's `closeout3-full1`; 2,295 link clicks), **15 on 5ac5d00** (2,025 link clicks) and **4 on 3b42714** (540;
updated by the final docs lane): every one 135/135, 0 card stalls, 0 gallery wedges, and 0 rescues and 0 `wedged`
reboots in every run that records your counters (all but `repin-full1`, which predates them). 36 clean runs happen with
probability 0.95^36 ≈ 0.16 at the old rate, so this is still not proof. It is also not evidence for or against hypothesis A (no rescue was ever needed).
Note for your own liveness: with every Lean task thread busy (24 parallel `sleep` proofs, pool `{unused 0, running 27}`)
a `textDocument/hover` waits for a free thread, while your `$/qed64/liveness` probe is answered at once; our gallery now
takes your probe's answers as proof of life (gallery/README.md "Proof of life besides the hover").

The rest of this section is the analysis on the previous pin.

**Symptom.** After an ordinary InfoView link click (C20, HasseView link #30, about 75 edits into a session) the page
stayed in `elaborating` forever. The Reset 120 s later produced a new version, v61, that also stayed `elaborating`. The
last status was `{phase: elaborating, relay: serving, lastDeath: null, workerDeaths: 0, reboots: 0}`. The stock page's
"Restart File" sends a document change, which a frozen runtime never processes, so the user has no way out but a
reload.

**What it is: a runtime-wide freeze** (`out/hang/ROOT-CAUSE.md`, "Verification, second pass", which corrects our first
analysis). Every Lean pthread stopped at the same moment, about 83.0 s into the session: `pool` read `8/17` before and
after the v61 edit, no thread was created or ended for 450 s, and no output frame left the worker after 83.008 s,
although the v61 bytes reached the stdin ring. The worker's own JS thread, which is the Emscripten main thread, kept
running and kept sending status, so `armHeartbeat` (`src/runtime/client.ts`) never fired. The Emscripten main-thread
proxy path had stopped servicing proxied calls. The pool froze because Lean's task manager calls `pthread_create`,
which under Emscripten is a synchronous proxy to the main thread (`pthreadCreateProxied` → `proxyToMainThread`),
while it holds its global `task_manager::m_mutex` (`wasm64-lean-kernel@9fbb45afcb:src/runtime/object.cpp`
`enqueue_core` :789 → `spawn_dedicated_worker` :873): the creator waits forever with the lock held, and every other
Lean thread blocks at its next task operation.

**The onset is an ordinary cycle.** The `-32800` (RequestCancelled) reply 29 ms after the click is routine: one per
cycle in every run (20–39 per session). The v60 progress reporter did run: two v60 `fileProgress` updates reached the
editor at 82.85 and 83.0 s. No `[lean:stderr]` line followed and nothing died, which rules out a FileWorker error,
exit or panic (each prints first).

**Likely trigger: one lost wake of the main-thread mailbox** (rated *likely*; the Chrome-side cause is not observed).
In Emscripten 6.0.5's `waitAsync` notification mode a single lost wake is permanent: `em_task_queue_send` and
`emscripten_thread_mailbox_send` notify only when the previous notification state was not `NOTIFICATION_PENDING`, and
only `_emscripten_check_mailbox` clears it, so after one lost wake no later sender ever notifies. Your fault injection
E1 (`qed64/work/storm/e1-waitasync-drop.{log,json}`) dropped one wake and reproduced the signature: the pool frozen at
`12/12` for 180 s, 0 frames. A raw `__emscripten_check_mailbox()` brought back 0 frames, because it drains once but does
not re-arm the `waitAsync` chain; the glue's `checkMailbox()` revived it at once.

**Rate.** 1 hang in the 19 recorded C20 runs (about 2,200 link clicks, about 4,400 edits): about 1 in 20 C20 runs. Our
headless replay (271 cycles, 42,016 thread creations) and your Node burst run (771,228 creations) froze 0 times, which
disfavours a host-independent race and points at the browser host layer (Chrome's `Atomics.waitAsync` and the nested
worker's event loop); this is unproven.

**Not caused by the widgets or the bridge** (ROOT-CAUSE.md §6): the panel RPCs are 1–3 of the 22–32 requests per
cycle, the bridge's abortSignal strip creates no blocked task, and the identical inserted text was clicked earlier in
the same session without trouble.

**Your fix (in progress, from your session):** postMessage mailbox notifications (`waitAsyncPolyfilled`) with a
periodic raw `_emscripten_check_mailbox()` kick, which turns a lost wake into a hiccup of at most about 1 s; a
Lean-level liveness reboot (a cheap request through the ring while `elaborating` and silent; no answer means reboot);
and kernel patch 0035 (no `pthread_create` while holding `m_mutex`, parked-thread reuse), which reduces exposure but is
not a cure on its own: every output frame still needs a proxied `fd_write`. Do not ship `setInterval(checkMailbox,
1000)` in `waitAsync` mode: each call arms one more waiter (ROOT-CAUSE W4).

**Our workaround (shipped, `gallery/gallery.js`).** A liveness probe. **On your 9fdf9b8 page it defers to your
liveness**: it starts only after 30 s of `elaborating` with no progress, never acts while your liveness reports a stall,
and reports your rescues, stalls and `wedged` reboots; a freeze your worker cannot see (a page-level one, C21's fixture)
is then restarted about 41 s after the last progress, ready again about 49 s after it. On a page without your liveness
(the previous pin) it starts after 10 s (restart about 20 s after the last progress). Either way the gallery then sends `textDocument/hover` at 0:0 through `relay.fromClient` with a string id (`showcase-live-<n>`) and full
params, and swallows the reply. Two probes unanswered within 5 s each mean wedged, and the gallery calls
`relay.restart` with the session's snapshots (the text is kept) and shows a small notice; at most once per 120 s. The
45 s stall card (Restart Lean, Reset example, Keep waiting) is the fallback. UX test C21 proves both on a
deterministically frozen checker; C22 shows that a legitimately slow, silent 38 s `#eval` answers the probe and is not
restarted. In observe mode (`?liveness=observe`) the gallery only records the wedge, and our UX harness then captures
the frozen runtime before anything restarts it: status and pool, `telemetry()` raced against 10 s, every worker console
line and `[lean:stderr]` line since session start, and your mailbox protocol (one raw `__emscripten_check_mailbox()`
per eligible worker, watch 15 s; if nothing moved, one `checkMailbox()` in the main-thread worker, watch 15 s), written
to `out/hang/captures/<run>-<iso>.json`. A real capture would name the browser trigger, with E1 as the reference
signature; so far only the synthetic fixture has been captured (labelled as such).

**No pre-recovery capture is possible on 9fdf9b8, and a small request.** Your kick heals a lost wake within about
1.25 s and your liveness reboots a wedged session about 22–25 s after its last frame, both before our observe-mode wedge
(about 40 s). The page has no switch for this: the bundle reads only `?profiles`, `?runtime` and `?snapshots`, and the
worker reads no query string. So our hunts can only record a hang you handled after the fact (the post-hoc record,
now exercised in the browser by our C23 on a forced `die(null, "wedged")`), never its frozen state. If you want field
captures of what the kick does not reach, a dev-only parameter that delays or disables the reboot (not the kick), for
example `?liveness=observe`, would let our capture run first. We did not switch it off from outside (calling
`stopLiveness()` in the worker would test a modified runtime). The fields we collect from your side for every
`wedged` reboot are listed in `out/hang/FIELD-CAPTURE.md`.

**Our liveness only trusts frames from Lean.** Your JS layer answers some requests itself (the front door's -32801
completion replies, the relay's -32603 halted and `failInFlight` replies, all prefixed `QED64:`, and the halted note
with source `QED64`). Our proof of life ignores those, because they keep flowing during a freeze. If you add more
synthesized frames, a stable marker (the `QED64:` prefix, or a field) keeps third-party watchdogs honest.

**Blast radius.** Every QED64 session, not widget-specific; long sessions with many edits and InfoView requests are the
exposed case.

## L9 — new on 9fdf9b8: a reload (or a relay restart) can crash the renderer with a V8 OOM

**Found by** the showcase's re-pin lane on 2026-10-01 (docs/REPIN-LOG.md §9). It is not caused by the showcase: the
decisive A/B below uses the stock page, with no gallery and no bridge.

**A/B on one host and browser** (`tests/ux/tools/reload-storm.mjs`: a fresh profile, boot
`/?snapshots=snapshots/widgets8` to ready, then reload every 3 s, as UX test C10 does). Each release was served by its
own `serve.mjs` on its own port, with its own paired widget overlay, alternating old/new, under the host browser lock;
results in `out/ux/repin-ab/explore/reload-storm-*.json` and `$W/logs/repin-ab-{1,2}.log`:

| release | runs | crashed | where |
|---|---|---|---|
| 1859b83 / `wasm64-4b025db7…` (0034) | 5 | **0** | – (158 workers created, 132 closed, ready 6.0–6.4 s after the storm) |
| 9fdf9b8 / `wasm64-2c18773e…` (0035) | 5 | **3** | each about 2.1 s after the **first** reload of a ready page (15.4–15.6 s into the run), while the second page instance boots |

The UX suite agrees. C10 (the gallery's reload storm) passed on the old pin (`closeout-full1`) and crashed 2/2 on the new
one (`repin-full1`, `repin-crash1`). C21 (b) crashed 1.8 s after a relay restart, while the replacement worker printed
`[packs] core#0 …`. W4 crashed once in normal use and passed on its re-run. With `DEBUG=pw:browser` the browser reports
`ERROR:…/v8_initializer.cc:969] V8 javascript OOM (Scavenger: semi-space copy)`. The macOS crash reports of these runs
(`~/Library/Logs/DiagnosticReports/chrome-headless-shell-2026-10-01-{175726,180622,181551,182812,184323,184454,184650}.ips`:
W4, C21 (b), C10 twice, and the three A/B crashes) are all `EXC_BREAKPOINT` with 36–46 `DedicatedWorker` threads in
the renderer (the 18:35 report in the same folder belongs to another session's lock window and is not counted).

**What differs between the releases at that moment.** Playwright counts the same live dedicated workers on both (26 at
ready, peak 27 during the storm). QED64's own pool sample at ready does differ: 0034 `{unused 13–14, running 10–11}`,
0035 `{unused 4–6, running 18–20, parked 8}` (the same in the UX suite: W2–W4 on the old pin 10–13 running / 11–14
unused, on the new pin 19–20 running / 4–5 unused; C20 pool totals now reach 32 where they peaked at 30). We cannot see
the faulting isolate (the binary is stripped), so we cannot say whether the parked dedicated threads (kernel 0035) or
the worker changes (message-mode mailbox, the 1 s tick) are responsible. The OOM is the renderer's V8 heap, not
the wasm memory, and it hits when a new runtime boots in the same renderer process right after the previous one was
torn down. Chrome's pointer-compression cage is shared by every isolate of a renderer, which L2 already showed to be
the tight resource.

**More data, from the showcase's final lane (2026-10-01/02).** Two full suites ran on 9fdf9b8 in consecutive lock
windows. `final-full1` had no crash. `final-full2` crashed twice:

* in C10, after the first reload of a ready page (`page.reload: Page crashed`);
* in C21 (b), at the first boot after a relay restart.

Both crash reports (`chrome-headless-shell-2026-10-01-200357.ips` and `…-201310.ips`) are again `EXC_BREAKPOINT`, with
a `DedicatedWorker thread` as the triggering thread and 43 and 45 `DedicatedWorker` threads in the renderer. Tally on
9fdf9b8 over the four runs that included C10 (three full runs and the W4 + C10 rerun `repin-crash1`): C10 3/4, C21 (b)
2/3 full runs, W4 1/4. Eight C20-only sessions of about 6 min each (fresh
contexts, no reload) did not crash. So the exposure is the second runtime boot inside one renderer, not long sessions.

**Two more full runs (2026-10-02).** The final audit's `audit-final-full` crashed in C21 (b) (`…-212418.ips`, 43
`DedicatedWorker` threads; C10 passed). Our close-out 2 run `closeout2-full1` crashed in C10 at the second reload
(`…-230148.ips`, EXC_BREAKPOINT / SIGTRAP, faulting thread `DedicatedWorker thread`, 46 of them). Since then C21 (b) runs
in its own browser and did not crash in 3 runs. Tally on 9fdf9b8 over the six runs that included C10 (five full runs and
`repin-crash1`): **C10 4/6**, C21 (b) 3/5 while it shared a renderer with (a) (0/3 since), W4 1/6. The suite cannot give two consecutive green runs on this release
while C10 (a reload storm, by design) crashes this often.

**Two more (2026-10-02, later).** The last audit's full run (`out/ux/audit-cl3-full1`, log `audit-final-full1.log`) and
our close-out 3 run `closeout3-full1` both crashed in C10 at the second reload (`page.reload: Page crashed`). The close-out 3 crash report was written at
04:32:18Z, 11 s after C10 started (file `chrome-headless-shell-2026-10-01-181551.ips`: its name and internal
`captureTime` carry a skewed clock): EXC_BREAKPOINT / SIGTRAP, faulting thread `DedicatedWorker thread`, 44 of 71
threads `DedicatedWorker`. In both runs every other test passed except C14, which aggregates the crash. **Final tally on 9fdf9b8**
(`node scripts/ux-tally.mjs`): C10 crashed in **6 of the 8 runs that included it** (5 of 7 full runs: `repin-full1`,
`final-full2`, `closeout2-full1`, `closeout3-full1`, `audit-cl3-full1`; plus `repin-crash1`; it passed in `final-full1`
and `audit-final-full`); C21 crashed in 4 runs, all before (b) got its own browser (`repin-full1`, `final-full2`,
`audit-final-full` and the audit mutant `audit-final-mut-mutC`); W4 in 1 of 8 (`repin-full1`). Every one of the 6 red full
runs on 9fdf9b8 had a renderer crash; only `final-full1` was green.

**To reproduce:** `UX_RUN=x scripts/with-browser-lock.sh x node tests/ux/tools/reload-storm.mjs --origin <origin> --tag t`
(from this repo; any server that serves the release with COOP/COEP and a `snapshots/widgets8` overlay, or change the
URL to the stock `/`). Suggested next steps for you: the same A/B with `?snapshots=` unset; with the dedicated-thread
cap set to 0 (no parking) on 0035; and with the mailbox left in `waitAsync` mode, to separate the two candidates.

**Your interim 5ac5d00 on our side (2026-10-02, showcase multi-pin lane).** We registered your unpushed local main
`5ac5d00` (the 0034 runtime `wasm64-4b025db7729c5f89` served again, with all of the #52 worker) as a pin of its own (our
pins are now keyed by QED64 commit, because 1859b83 and 5ac5d00 share a buildId but not a shell or worker), served it
unmodified from our verified clone (`release/5ac5d00`, 145 files, sha256-verified against the lock; `dist/workers/lean.worker.js`
== `git show 5ac5d00:public/workers/lean.worker.js`) with our paired widgets8 overlay, and ran the same reload storm
(`tests/ux/tools/reload-storm.mjs`, fresh profile, boot to ready, reloads at 0/3/6/9/12 s, `DEBUG=pw:browser`, under
the host browser lock): **0 of 6 crashed**, 0 `V8 javascript OOM` lines, no new crash report; QED64's pool at ready
`{unused 14, running 10, parked -1}` in all 6 (no parked-thread export on the 0034 glue), peak 27 live workers, ready
6.1–8.0 s after the storm (`$W/logs/multipin-storm-C-{1..6}.log`, `out/ux/multipin-storm/explore/`). **Caveat, in fairness
to the numbers:** a positive control on 9fdf9b8 right after (3 runs, same tool, host and hour) also did **not** crash
(pool `{unused 4–6, running 18–20, parked 8}`), where your and our earlier A/Bs had 3/5. So today's storm alone cannot
separate the arms on this host; the UX suite's C10 (reload storm in the gallery) in our full runs on 5ac5d00 is the other
evidence (docs/UX-RESULTS.md "Multiple pins").

**L9 in desktop Chrome (2026-10-02, 05:34–08:33Z; full report `out/ux/l9-desktop/RESULTS.md`, generated from its run
files).** Everything above was measured in Playwright's chrome-headless-shell. We repeated the stock-page reload storm
(the same hot path as `tests/ux/tools/reload-storm.mjs`) on all three pins in three builds of the same Chrome 151.0.7922.34:
chrome-headless-shell, Chrome for Testing in new headless mode, and Chrome for Testing **headed** (a real window on the
macOS desktop). Each pin was served by its own `serve.mjs` from a byte-identical APFS clone of our pinned release (sha256
over all 145 files equal), every run under the host browser lock with `DEBUG=pw:browser`:

| pin | chrome-headless-shell | new headless | **headed desktop Chrome** |
|---|---|---|---|
| B `9fdf9b8` (0035, #52 worker) | 4/11 crashed (Bs1, Bs2, o4, o5: all V1) | 0/8 | **3/8** (Bh3 V1; b5, Bh2 V2) |
| C `5ac5d00` (0034, #52 worker) | 0/6 | 0/6 | **4/19** (c3, c4, c5, c9: all V2) |
| A `1859b83` (0034, old worker) | 0/5 (the 2026-10-01 A/B above) | not run | **1/5** (g2, V2) |

* **V1, the classic L9:** the renderer dies 1.8–2.2 s after the **first** reload of a page that has just become ready,
  `V8 javascript OOM (Scavenger: semi-space copy)` from an isolate about 1.05–1.27 s old with a 48.7–53.2 MB heap. Only
  on B, and **also in headed desktop Chrome** (Bh3), so a visitor who reloads a ready 9fdf9b8 tab can lose it.
* **V2, new:** the renderer dies 1.98–2.27 s after reload 2, 3 or 4, `V8 javascript OOM (MarkCompactCollector: young
  object promotion failed)` from **brand-new isolates 0.31–0.48 s old with 15.8 MB heaps** (c4: five at once). In this
  window only in headed Chrome (the final gate later saw it in chrome-headless-shell too, below), on **all three pins, including the 0034 runtime with either worker** (A and C), although C's pool at
  ready is `{unused 13–14, running 10–11, parked -1}` (no parked threads).
* In both variants the dying isolate is tiny, so the limit is most likely the renderer's shared V8 pointer-compression
  cage, not a large heap or host memory (13.2–24.9 GiB were reclaimable at every launch; largest renderer RSS in the last
  sample before a crash, 10,922–11,933 MiB, overlaps the non-crashing runs' peaks of 7,726–12,141 MiB). This fits your mechanism for L9: the old page's
  ~25 workers are still in the cage while the new page's workers start; 0035's parked threads keep more of them alive.
* **V2 clustered in time:** all 7 V2 crashes came from runs started 05:51–06:40Z (7 of the 19 headed runs in that window);
  0 of 5 headed runs before it and 0 of 8 after it crashed with V2 (c11–c13 used the same tool as the crashing runs). We
  did not find what differed in that window (same page, release, browser and tool), so V2's rate depends on host or
  Chrome state; its existence on all three pins is established.
* **Crash reports undercount:** Chrome for Testing wrote no macOS crash report for any of its crashes, and ReportCrash
  often only touched an older report of the same binary. Count the page's `crash` event and the stderr OOM line.

**What this means for your fix.** A parked-thread cap of 0 (your planned final 0035) should bring 9fdf9b8 down to the 0034
level, which removes V1 in every browser we tried. On this evidence it will not remove V2, which the 0034 runtime shows
in headed Chrome with the old worker and with the new one. What would: fewer live isolates across a reload, for example
terminating the pthread workers on `pagehide` (before the next page's runtime boots) or fewer pthreads per page.
(Update 2026-10-03: the `pagehide` part does not help, see "Hint for your V2 follow-up" at the end of L9.)
On our side, C stayed served then (2026-10-02): it removes V1, has your L7 healing, and A (the only alternative without
0035) also shows V2. (Since 2026-10-04 E `33b0967` is served; see the end of L9.)

**Quiet-host slot (2026-10-02, 11:03–11:21 UTC; `out/ux/l9-quiet/RESULTS.md`).** In a window the QED64 owner kept
free of heavy jobs (20–26 GB reclaimable, no foreign heavy process in any run), headed Chrome for Testing, interleaved:
V2 hit A 1859b83 1/8 and C 5ac5d00 2/10 (widgets8 overlay and stock page combined), D 3b42714 0/5 (stock page), and
B 9fdf9b8 showed V1 1/2 (control). So V2 does not need host pressure: it is a background rate of headed Chrome 151 on
runtime 4b025db7 with either worker, roughly 10–20 % per 5-reload storm. D's 0/5 is promising but not yet significant.

**Status of the candidate fix (2026-10-02, pin D lane; superseded by the next paragraph).** QED64 `3b42714` (kernel
0035b, parked dedicated threads off by default, runtime `wasm64-3ab1c6a9da03bc29`) is registered here as pin D and passes
every non-browser gate on our widget regions (rebaked, paired, QED64's preflight OK, headless stage 4 green;
docs/REPIN-LOG.md "pin D"). The browser results follow.

**Your candidate 3b42714 under interleaved reload storms (2026-10-02, final-gate lane; `out/ux/final-storm/RESULTS.md`,
generated from its run files).** To remove the time confound, all four pins ran in the same windows, rotated run by
run: five rounds of 16 runs (A, C, D and B × chrome-headless-shell / headed Chrome for Testing 151 × your stock page
`/?snapshots=snapshots/widgets8` / our `/showcase/` gallery, which iframes your page from the same origin), 14:55–16:59Z,
then one round of 18 headed runs (A, C, D × both entries × 3) started only after 5 consecutive quiet minutes on the host
(≥ 20 GB reclaimable, swap flat, no other session's bake, storm, probe, browser or build), 19:12–19:24Z. Same tool hot
path as `reload-storm.mjs` (fresh profile, ready, reloads at 0/3/6/9/12 s), `DEBUG=pw:browser` for the OOM line:

| pin | interleaved rounds | quiet round (headed) | all |
|---|---|---|---|
| A `1859b83` (0034, old worker) | 0/20 | 3/6 | 3/26, all V2 |
| C `5ac5d00` (0034, #52 worker) | 1/20 (headless-shell) | 1/6 | 2/26, all V2 |
| **D `3b42714` (0035b, parking off)** | 1/20 (headless-shell) | 2/6 | **3/26, all V2** (+1 V2 in a smoke run) |
| B `9fdf9b8` (0035, parked threads) | 3/20, all **V1** | – | 3/20 V1 |

* **0035b removes V1.** B still shows V1 (after reload 0, `Scavenger: semi-space copy`, pool `parked 7–8`) in both
  browsers and on both entries; D, at `parked 0` in every run, showed no V1 in 27 runs.
* **0035b does not change V2.** D's V2 rate equals the 0034 runtime's with either worker (A 3/26, C 2/26, D 3/26). V2 now
  also shows in chrome-headless-shell (one D run and one C run: 1.7 s after reload 2/4, 2–4 isolates 331–355 ms old with
  15.8 MB heaps), so it is not specific to headed Chrome.
* **V2 does not need host pressure; it was more frequent on the quiet host**, and all 6 quiet-round crashes were on the
  gallery entry (A 3/3, D 2/3, C 1/3; your stock page 0/9 in that round). The headed runs of the earlier rounds, on a
  host with 13.6–22.3 GB reclaimable, had 0 V2 in 40. Our reading (inferred): what matters is how much of the new
  page's runtime boots while the old page's ~25 workers are still in the renderer, which a fast idle host and the
  gallery's extra same-origin document make more likely; host memory is not the limit.
* What would remove V2 is still fewer live isolates across a reload, for example a page-level pool that starts after
  the previous one is gone. (We first also suggested terminating the pthread workers on `pagehide`; the v2mit A/B
  below shows the workers are already closed 7–40 ms after a reload, so that alone does not help.) We keep C served: D was not cleaner
  than C under this storm, although D passed every other gate of ours when served (two VERDICT full UX runs, a headed
  sign-off, `CONTROLS PASS`).

**V2, all windows side by side (2026-10-02, UTC; crashed / runs; V2 unless marked).** Each window is its own measurement
(different tools, host states and entries), so the rows are not summed:

| window | browser, entry | A `1859b83` | C `5ac5d00` | D `3b42714` | B `9fdf9b8` |
|---|---|---|---|---|---|
| l9-desktop 05:34–08:33 | headed, stock | 1/5 | 4/19 | – | 2/8 (+1 V1) |
| l9-desktop 05:34–08:33 | headless-shell / new headless, stock | – | 0/6 / 0/6 | – | V1 4/11 / 0/8 |
| quiet slot 11:03–11:21 | headed, stock page with and without our region | 1/8 | 2/10 | 0/5 | V1 1/2 |
| final gate, 5 interleaved rounds 14:55–16:59 | both browsers, stock and `/showcase/` | 0/20 | 1/20 | 1/20 | V1 3/20 |
| final gate, quiet round 19:12–19:24 | headed, stock and `/showcase/` | 3/6 | 1/6 | 2/6 | – |
| v2mit A/B 22:37–23:33 (quiet), control arm (the then-current gallery `2081098d…`) | headed / headless-shell, `/showcase/` | – | 8/24 / 0/12 | – | – |

What is established: V2 exists on the 0034 runtime with either worker and on 0035b; it appears in headed Chrome and
chrome-headless-shell; it does not need host memory pressure (it hit runs launched at ≥ 20 GB reclaimable with no other
heavy process). What is not: its rate. It came in bursts (all 7 l9-desktop V2 crashes in 05:51–06:40Z, 7 of 19 headed
runs in that window, 0 of 13 outside it; 6 of 9 `/showcase/` runs in the final quiet round, 0 of 40 headed runs in the
loaded rounds), and we could not tie a burst to anything we measured (reclaimable memory, swap, foreign processes,
renderer RSS). The causal story (old page's workers still in the renderer's V8 cage while the new page's workers start)
is our inference from the fingerprint, not shown.

**What our side tried: tearing your page down from the gallery first (2026-10-02, v2mit lane;
`out/ux/v2mit-storm/RESULTS.md`).** Hypothesis: through `/showcase/` the outer document plus your iframe document delay
the teardown of your ~26 workers. A treatment gallery called `qed64.relay.unload()` (your `dispose()` + synchronous
`terminate()`) from the gallery's own `pagehide` and then removed the iframe; A/B against the unchanged gallery on pin C,
`/showcase/` only, arms interleaved, every run on a quiet host: **headed V2 10/24 with the teardown vs 8/24 without**
(headless-shell 0/12 each). A probe explains why: after `page.reload()` all 26 old workers report `close` 7–40 ms after
the reload call in both arms (the top `pagehide` fires at 9–16 ms, `beforeunload` at 4–7 ms), and the new page creates
its first worker 113–185 ms after it. So the worker targets are gone before any new worker exists, whoever tears them
down; what is still alive ~2 s later (inference: the old isolates' or wasm memories' release behind the closed worker
targets) is not reachable from a page script. We did not ship the change. A fix needs to be on your side (fewer
isolates per page, or a boot that waits until the previous runtime's memory is released), or in Chromium.

**Hint for your V2 follow-up (2026-10-03, from the A/B above; facts measured, the remedies are our inferences).**
* *Do not expect much from an earlier teardown.* Your relay's `unload()` (`dispose()` + synchronous `terminate()`,
  `frontend/src/lsp-relay.ts:132-133` at our pins) already runs in the unload turn, and the browser reports every old
  worker closed 7–40 ms after the reload, 100+ ms before the new page's first worker. Calling it from the outer
  document's `pagehide` as well changed nothing (headed V2 10/24 vs 8/24, two-sided Fisher p = 0.77).
* *What the fingerprint points at.* The isolates that die are the new page's, 0.3–0.5 s old with 15.8 MB heaps, about
  2 s after reload 2–4, with 20 GB or more of host memory reclaimable. So the shared resource is most likely
  the renderer's V8 pointer-compression cage (or wasm memory reservations) still holding what the closed workers left
  behind. Levers on your side: fewer isolates created at boot (your pool at ready is about 25 workers: `unused 13–14,
  running 10–11`), a pool that grows lazily, or a runtime boot that waits briefly after a navigation. A delayed boot
  is untested; it would slow every reload and needs its own A/B.
* *A faster repro.* V2 is most frequent through a same-origin wrapper page on an idle host, in headed Chrome: 8/24
  (control arm) and 6/9 through `/showcase/` against 0/9 on your stock page in the final-gate quiet round. Our harness:
  `tests/ux/tools/reload-storm-desktop.mjs --entry showcase` (fresh profile, boot to ready, 5 reloads 3 s apart; crash
  = page `crash` event plus the `V8 javascript OOM` stderr line under `DEBUG=pw:browser`), interleaved arms with a
  300 s quiet streak before each batch (`$W/v2mit/master.sh`, `$W/v2mit/tabulate.py` for the Fisher test). The
  per-run tables are in `out/ux/v2mit-storm/storm-table.md`. It is not the wrapper delaying your teardown.
* *A repro without our gallery (2026-10-03, v2-embed lane, `out/ux/v2-embed/RESULTS.md`).* Your stock page
  `/?snapshots=snapshots/widgets8` inside a **script-free same-origin page that only holds one `<iframe>`** (the
  gallery iframe's attributes, `allow="clipboard-read; clipboard-write"`, nothing else) loses the tab 3–5× as often as
  the same page at top level under the same storm: 16/48 vs 4/48 pooled over two boot documents (Fisher p = 0.005), 10/24
  vs 2/24 with the same document (p = 0.017); headed Chrome for Testing 151, pin C, 120 storms interleaved arm by arm on a
  quiet host. Our gallery's code on top adds an increment that is not significant (15/24 vs 10/24, p = 0.25). Every
  crash had the V2 fingerprint (last GC a `Scavenge` at 15.8 MB, 285–419 ms after the isolate started, 2.0–2.4 s after
  reload 1–4). So the embedding is the main factor, and a fix has to come from the page or the runtime; an inference we
  have not tested: the nested browsing context changes how the renderer schedules teardown and reuse of the old page's
  isolates. Tool: `$W/v2embed/reload-storm-embed.mjs --entry frame --path /showcase/embed-test.html`.
* If a candidate commit arrives, we will storm it interleaved with C on both entries and switch only if its V2 count is
  at most C's in the same windows (docs/NEXT-STEPS.md §2).
* **Your candidate arrived: main `33b0967` (HARDENING #55, `9c00688` runtime lifetime locks, merged over #54).** It was
  registered here as pin E `33b0967` (2026-10-04, docs/REPIN-LOG.md "pin E"). It runs on your unchanged runtime
  `wasm64-3ab1c6a9da03bc29`, so our D stores serve it, and `CONTROLS PASS` there. Our Node-based headless verifiers do not
  reach the lock code: they never load `lean.worker.js` or `client.ts`, and a trace showed 0 `navigator.locks` calls,
  although Node 26 has the API.
* **Our storms on E (pin-e lane, 2026-10-04, `out/ux/pin-e/RESULTS.md`): consistent with your fix, not a confirmation.**
  E and C were served on their own ports and stormed on our visitor's path `/showcase/#hasse-view`. The tool was the
  v2-embed lane's arm S. Pins were interleaved per rep, each batch after a 300 s quiet streak:

  | | headed Chrome for Testing 151 | chrome-headless-shell 151 |
  |---|---|---|
  | E `33b0967` (#55) | 0/20 | 0/8 |
  | C `5ac5d00` | 0/20 | 1/8 (V2: `Scavenge 15.8 MB` at 412 ms, OOM 1885 ms after reload 3) |

  Fisher tests: headed p = 1.0; any crash pooled 0/28 vs 1/28, p = 1.0. The day before, C had 15/24 on the same path
  and tool (v2-embed), but in these windows it was nearly clean too. So the storms show that E is not worse, not that
  #55 removes V2. Your 17/48 → 0/36 stays your measurement. What differed (inference): our host had about 15–17 GB
  reclaimable instead of about 21 GB (other desktop apps), and the renderer peaked at about 10 GB instead of about 12 GB.
  At Playwright's 250 ms sampling, the new page's first worker came 576 ms (E) vs 573 ms (C) after a reload, so the
  lock's wait is not visible there. On that evidence we switched to E: it was at least as clean as C, and it passed our
  full gate (two UX verdicts, a headed sign-off, the slow-link first visit, the deploy rehearsal). A high-rate window
  (an idle host with 20 GB or more reclaimable) would be the place to confirm the fix on our side.
* **Renderer crashes in the UX suite's C10 on E, with #55's wait visible (2026-10-04/05, R2 and R4 lanes).** C10 opens
  `/showcase/#graph-scope` on a warm profile, waits for ready and reloads at 0, 3, 6, 9 and 12 s. On E it crashed the
  renderer in 3 of 9 full runs from 19:52Z on 2026-10-04: `r2-main-full1` (chrome-headless-shell), `r4-main-full2`
  (chrome-headless-shell) and `r4-main-headed1` (headed Chrome for Testing 151). Before that, E's full runs had 0 C10
  crashes in 7 (`node scripts/ux-tally.mjs`, which since R4 also counts a crash that only the session stream recorded).
  The R4 crashes have the V2 timing: after the 5th reload, 1.0 s and 1.4 s after the page's last `[qed64] starting
  Lean`. In both, your lock's message appears just before: `[boot] waited 314 ms for 1 stopping runtime(s) (25 → 12
  Workers alive)` (`r4-main-full2`, crash 1.16 s later) and `[boot] waited 444 ms for 1 stopping runtime(s) (25 → 9
  Workers alive)` (`r4-main-headed1`, crash 1.66 s later). So the wait ran and the renderer still died. The crash reason is not captured: the suite's crash event has no OOM line, and macOS wrote no
  crash report for the R4 crashes. The R2 crash's report (`chrome-headless-shell-2026-10-04-162712.ips`) shows a
  `SIGTRAP` on a `DedicatedWorker thread`, which matches a V8 fatal error in a worker isolate; that it was V2's
  `young object promotion failed` is an inference. The host had 26.4–26.5 GiB reclaimable at the start of the two R4
  runs that crashed, against 18.6–25.5 GiB for the five R4 runs that did not, which fits "idle host, more V2" but is
  far too few runs to show it. Runs with `DEBUG=pw:browser` (which would log the OOM line) did not crash. The runs,
  timelines and logs are in `docs/results/REPO-TEST-ROUND.md` "C10 crashes on E".

## S1 — slow first visits and the boot card's memory figure (2026-10-03, last-mile lane)

Measured through a link-shaping proxy (`tests/ux/tools/throttle-proxy.mjs`), because Chrome's CDP network emulation
does not reach your workers (`Network.emulateNetworkConditions: Not supported` on every worker session; the worker
then fetched 556 MB at 15–21 Gbit/s). Fresh profile, chrome-headless-shell 151, pin C, our `/showcase/` entry
(`out/ux/last-mile/RESULTS.md` (4)):

* 50 Mbit/s, 40 ms: ready in 123 s; your boot card showed the step, bytes, rate and time left throughout.
* 10 Mbit/s, 40 ms: your boot card showed progress until 230 s, then disappeared while the 1.2 GiB mathlib environment
  was still downloading; from 231 s to ready at 577 s only the top-bar pill with an elapsed timer remained (no bytes or
  percentage). The bundle removes the overlay 120 s after an idle status starting with `ready`
  (`/^ready/.test(n)&&window.setTimeout(pX,12e4)` in `release/5ac5d00/dist/assets/index-BvT6MV1R.js`); the editor
  opened at about 115 s, so the timing fits (inferred from code plus timing).
* Your boot card (`dist/index.html` line 114 at pin C) says the full Mathlib environment needs "~3 GB of memory". We
  measure 8.2–9.0 GiB of renderer RSS per tab at ready, about 12 GB transiently on a reload and about 17 GB or more for
  two tabs or "Load exact imports" (README.md "Browsers and memory"). The card also says a first visit downloads about
  600 MB; that matches your stock region (ours, with the widget region, is about 710 MB).

Suggested: keep the boot card (or a compact progress line) while snapshot bytes are still arriving, and state the
memory figure as measured. Evidence of the facts above: `$W/logs/lastmile-throttle-p10.log`,
`out/ux/lastmile-throttle/screens/throttle-p10-0241s.png`, `$W/logs/finaldocs-qed64-bundle-facts.log`.

**Fixed in your `3e182ff` (HARDENING #54), shipped in `33b0967`; confirmed by us on 2026-10-04 (pin-e lane,
`out/ux/pinE-throttle/explore/throttle-pe10.json`).** Same setup: fresh profile, chrome-headless-shell 151,
`throttle-proxy.mjs` at 10 Mbit/s / 40 ms, our `/showcase/` entry, served pin E.
* Your boot card stayed visible from 1.2 s until ready at 565.1 s, with the step, bytes, rate and time left (for
  example "preparing the mathlib environment … 757 MB / 1.18 GB · 4.7 MB/s · ~2 min left" at 481 s). It now says
  "about 8–9 GB of memory".
* With your in-chunk progress (`5e94697`, `76be299`), the longest stretch without a change of the visible progress was
  6.0 s (19.0 s on C).
* 693 MB were downloaded at 9.8 Mbit/s, with no error and the panel correct.
* One remaining detail: the card still says a first visit downloads "about 600 MB". That fits your stock region; a
  page with a larger region (ours: about 693 MB) downloads more.

## N3 — the stock page has no favicon; desktop Chrome logs a 404 per load

Found by the final-gate lane's headed sign-off (2026-10-02). `dist/index.html` declares no `<link rel="icon">` and
`dist/` has no `favicon.ico`, so headed desktop Chrome requests `/favicon.ico` for every top-level load of the stock page
and logs `Failed to load resource: the server responded with a status of 404 (Not Found)` (chrome-headless-shell never
requests it, which is why our headless suite never saw it). Harmless, but it breaks strict console checks in a real
browser. Suggested fix: ship a favicon (or `<link rel="icon" href="data:,">`). Our headed UX run allows exactly this one
message once per stock-page load (`tests/ux/lib/qed64.mjs` `HEADED_ALLOWLIST`); the gallery has its own `favicon.svg`.

## X1 — a FileWorker exit is never reported in resident mode (`_proc_exit` / `onExit`; latent, not L7)

**Status: fixed upstream in 9fdf9b8.** `instrumentRuntimeMailbox` wraps entries 0 and 1 of the glue's proxied-function
table (`_proc_exit`, `exitOnMainThread`) and calls `die(code, "exit", …)` before the glue swallows the `ExitStatus`
(`vendor/qed64/public/workers/lean.worker.js:476`; `kickMailbox` does the same for an `ExitStatus` thrown while it serves
the mailbox). The boot log reads `[boot] runtime mailbox: message notifications …; FileWorker exit hooked`. Your commit
cf3b97b measures it against the real glue and worker under Node (`pipeline/snapshot/fileworker-exit-probe.mjs`, vendored).
The analysis below is for the previous pin.

**Found by** the second verification pass of the L7 analysis (ROOT-CAUSE.md W5), by reading the pinned glue and worker;
it was not seen in a run.

* The glue's `_proc_exit` (pinned `lean.js`, sha256 `3662dd66…`) is
  `if (ENVIRONMENT_IS_PTHREAD) return proxyToMainThread(0,0,1,code); EXITSTATUS=code; if (!keepRuntimeAlive()) {
  PThread.terminateAllThreads(); Module["onExit"]?.(code); ABORT=true } quit_(code, new ExitStatus(code))`.
* QED64 keeps the runtime alive on purpose: `public/workers/lean.worker.js:1015-1016` pushes a keepalive at boot, and
  `callMain` pushes another.
* `IO.Process.forceExit` is `std::_Exit` → `__wasi_proc_exit` (musl `_Exit.c`), which from a pthread is the synchronous
  proxy `(0,0,1)` to the main thread.
* So on the main thread `keepRuntimeAlive()` is true, `onExit` is skipped, `quit_` throws `ExitStatus`, and
  `callUserCallback` swallows it. `onExit: (code) => die(code, "exit", …)` (`lean.worker.js:970`) never fires, and the
  exiting FileWorker pthread waits forever for the proxy's answer.

**What a user would see.** A FileWorker fatal error (`workerMain` prints `err.toString` and calls
`IO.Process.forceExit 1`) would look like L7 plus one `[lean:stderr]` line and one error diagnostic: `elaborating`
forever, no death. The comment at `lean.worker.js:966-969` ("main returning … is a death FACT") does not hold in
resident mode. This was not the cause of the captured L7 hang (no `[lean:stderr]` line followed it).

**Suggested fix.** Report the exit independently of the keepalive in resident mode, for example by wrapping `quit_` (or
overriding `_proc_exit` in the worker) so that an `ExitStatus` on the main thread calls `die(code, "exit", …)`.

---

Other stock-page behaviours the UX suite documented (L3 no offline boot when the overlay index is
unreachable, L4 `SNAPSHOT_UNPAIRED` not surfaced and the 32.6 MB init snapshot downloaded before the
refusal, L5 "Load exact imports" cannot succeed for `import Mathlib`, L6 no dark InfoView, L8 a
10.9–12.0 GB transient renderer peak in a reload storm, and three UI quirks) are listed with
evidence in `docs/UX-RESULTS.md` § "QED64 limitations found". They are smaller, and the gallery
handles each.

---

## #59 — sustained typing above an uncancellable command crashes the tab (your HARDENING #59; fixed in G by `e4cffcc` per QED64, not yet measured by us)

**Found by** your edit-storm lane (`pageslow`, 2026-10-05); recorded here because it bears on the gallery. On the stock
page, typing at 150 ms/char on the line above `#eval (IO.sleep 3000 : IO Unit)` with the InfoView open grew the pool
24 → 61–64 and crashed the renderer on every build you measured (fd6c2ae, f150f47); your HARDENING.md at F `84d594e` still
lists it as open. At that pace no two changes share a 300 ms window, so each keystroke is forwarded and starts a 3 s
elaboration, and its InfoView requests wait as Lean tasks on a snapshot the sleep never finishes, each holding a
dedicated thread (a ~129 MiB Worker; about 30 is the ceiling, our L2). The coalescer caps bursts, not a sustained pace.

**For the gallery.** None of our eight examples has a long uncancellable command, so a visitor reaches it only by writing
one. The gallery cannot prevent it from outside (it neither sees the pool on a v1 pin nor may hold the page's frames). The
fix is yours: (a) back-pressure keyed on the worker's pool sample, or (b) the cap on live dedicated threads that #55
named.

**Status (2026-10-06): fixed in G `5c327c2` by your `e4cffcc` per your measurement; not yet measured by us.** Your fix is
(a) plus a cap on requests in flight. The coalescer holds full-text changes while fewer than `minFreeWorkers` (default 6,
`?edithold=<n>`) preallocated Workers are free. The hold lasts for a 1 s pressure memory and at most 5 s, polling
telemetry every 250 ms. At most 6 requests are at the worker unanswered, and a `$/cancelRequest` for a request still
queued is answered locally with RequestCancelled (`-32800`, `error.data.qed64.kind` `'cancelled'`) (EMBEDDING.md §4 and
§7.8; HARDENING.md #59 addendum). Your addendum reports, in edit-storm with two runs per scenario on the production
build, `pageslow` passing with the pool at 24 → 24/25. The same build with `?edithold=0` crashed (24 → 32). We registered
G on 2026-10-06 (docs/REPIN-LOG.md, pin G entry). Our side so far is static only. The UX console oracle allows the new
cancel reply text at the notify site (line0 627), paired with its own `-32800` reply (gallery/README.md "Console
messages"; no browser run has seen it yet). Our own measurement is still open: a C20-style typing run at 150 ms/char
above a slow `#eval` on G (docs/NEXT-STEPS.md "Pin G").

---

## How to re-check any of this

From the showcase repo:

* `scripts/showcase.sh verify` checks the pin and the overlays.
* `node tests/experiments/x4-click-paths.mjs` runs D1/D2, raw against bridge. It boots a browser,
  so run it through `scripts/showcase.sh locked x4 -- node tests/experiments/x4-click-paths.mjs`:
  `locked` takes the browser lock (`scripts/with-browser-lock.sh`) and then refuses unless at
  least 6 GB is free+inactive, no headless Chrome is running and no bake is running.
* `scripts/showcase.sh headless controls` runs the wasm controls, including `conv?` through the
  stock snapshots.
* `docs/HEADLESS-RESULTS.md` covers L1.
* `npm run test:ux` (or `scripts/showcase.sh ux`) runs the browser suite.

**Browser verdict with the bridge** (`docs/UX-RESULTS.md`, written by the UX lane on 2026-10-01):
two full runs back to back, `full6` and `full7`, each gave **30 passed, 1 skipped (C19, the
optional headed run), 0 failed, 0 flaky**. That includes W1–W8 (every widget panel in the real
InfoView), C20 (135/135 InfoView links apply clean through the D2 bridge, in all 7 post-audit C20
runs). No test's console verdict failed, and that verdict includes the InfoView-DOM scan for the
D1 error text (the scan that fails C17 on the bridge-less mutant above).

**Caveat (added 2026-10-03).** The mechanism probe's worker timings are Playwright Worker `close` events, i.e. CDP target detach, not proof that the worker's V8 isolate was freed. Blink force-terminates a worker that is busy in wasm only after a ~2 s grace (`worker_thread.cc`, per the QED64 V2 session), and every V2 hit lands 2.0–2.16 s after a reload. So this negative result rules out only the page-side teardown ORDER we tried (relay.unload + removing the iframe on pagehide); it does not rule out late isolate death as the mechanism.
