# `gallery/` — the M2 gallery wrapper (BUILD-PLAN §7.3)

A two-pane page that shows the eight widget examples **inside the stock QED64 page**. QED64 is not
changed. The right pane is QED64's own `dist/index.html`, iframed from the same origin at
`/?snapshots=snapshots/<overlay>`. The left rail drives it through the page's embedding API when the pin has one
(`globalThis.qed64.api`, QED64 embedding contract v1, pins F, G and H: "Embedding API v1 (pins F, G and H)" below; the frame URL is then
`/?embed=1&snapshots=…#code=…`) and, on older pins, through the
hooks the page already exposed (`globalThis.qed64`, the `qed64.buffer` boot document).

**Status.** Which verdicts apply to the current gallery is printed, not written here: `scripts/showcase.sh gallery`
(gate, content sha256, `UX CURRENT …` / `UX STALE`) and `scripts/showcase.sh pin list`. *History (dated):* gallery
`921b0b6a…` (the final-gate gallery `2081098d…` with only the memory wording changed) had verdict runs from the v2mit
and last-mile lanes and no headed sign-off; a gallery-side L9 V2 mitigation (teardown on `pagehide`) was measured and
rejected (`out/ux/v2mit-storm/RESULTS.md`). The boot-fix lane (2026-10-03) changed `gallery.js` (gallery `31f6d8d9…`):
the first-boot wait is progress-aware, so a slow first visit gets a "Still downloading" notice instead of the error
card, and a later `ready` closes a stall card ("Timeouts"; 10 Mbit/s: ready at 565 s, no card). The closure lane
(2026-10-03) recorded two verdicts and a headed sign-off (34/34) on that gallery, and re-measured the throttled first
visits and a 60-min soak (`out/ux/closure/RESULTS.md`). The pin-e lane (2026-10-04) switched the served pin to E
`33b0967` (QED64 #54/#55), which regenerated `pin.json`. It recorded two verdicts and a headed sign-off on the resulting
gallery and a passing 10 Mbit/s first visit ("Timeouts"; `out/ux/pin-e/RESULTS.md`). The v1-adoption lane (2026-10-05/06) made pin F
`84d594e` (QED64 `feature/embedding-api`) active locally and moved the gallery onto QED64's embedding API v1 for it
("Embedding API v1 (pins F, G and H)"), keeping the legacy flow for pins A–E. The pin-G lane (2026-10-06) made pin G
`5c327c2` (F plus QED64's edit back-pressure, `e4cffcc`; API revision still `1.0.0`) the active pin and F a staged one;
its first full run found QED64's keep-alive starvation, and G got one VERDICT (`g-full1c`) on gallery `931c33a7…`.
**Since 2026-10-06 ~20:03Z the active pin is H `bf9d947`** (QED64 main: G plus QED64's keep-alive fix), and the
gallery is `d8a5bb6d…` (`pin use` regenerated `pin.json`). On it: VERDICTs `h-full1b`, `h-full3` and `h-full4`, the
headed sign-off `h-headed2` (35/35), `C20` 135/135 in three runs, and three runs that each lost one test to a renderer
crash during a QED64 boot ("QED64 limitations found", L9; docs/REPIN-LOG.md, pin H entry). F and G are staged; the live
site still serves E, and pushing and deploying are the user's decisions. **Browsers:** a Chromium-based desktop browser on a
computer with 16 GB of RAM or more, one showcase tab at a time (measured: 8.2–9.0 GiB per tab at ready, transient peaks
of about 12 GB on a reload, about 17 GB or more for two tabs or for QED64's "Load exact imports"; README.md "Browsers
and memory"); anything without cross-origin isolation, SharedArrayBuffer or WebAssembly Memory64 gets the capability
card ("Boot flow" step 0). Run: Chromium 151 (headless shell, headed Chrome for Testing) and branded Chrome 154 headed;
Safari 26.6.2 not run (WebDriver refused). A reload storm could crash the tab on every pin before E (QED64 L9 V2;
"QED64 limitations found"). QED64's #55 fix is in E. Our storms on E (0/28) were in windows where C was also nearly
clean, so they do not confirm it (`out/ux/pin-e/RESULTS.md`). On the v1 pins a residual remains, which QED64 reopened as
#55 on 2026-10-07: a reload during QED64's boot can still crash the renderer on some machines (C10 1 of 9 storms in
chrome-headless-shell on G and H; "QED64 limitations found", L9). The gallery never reloads a booting page on its own
except through the card's Restart Lean fallback, and its boots go through `about:blank`.

```
index.html         the shell: top bar (Reset, Copy for VS Code, live status line), rail, stage (iframe, notice,
                   error card), narrow-screen select bar, card <template>
gallery.css        tokens on :root, dark mode via prefers-color-scheme, two-pane ≥ 721 px, select bar ≤ 720 px
gallery.js         the controller (boot, preflight, seeding, bridge install, switching, errors, keyboard, test API)
lib.js             pure logic shared with the Node gate: pairing preflight, overlay choice, ?mem parser, status classes
qed64-bridge.js    the same-origin InfoView repair: D1 abortSignal, D2 applyEdit (stage A, X4) and D3 getWidgetSource
                   coalescing (this bring-up; without it the renderer dies, see "QED64 limitations"); pins A–E only,
                   not installed on pins F, G and H (fixed upstream)
favicon.svg        the page icon (without one a headed browser asks for /favicon.ico, a 404: UX suite C19)
thumbs/<pkg>.png   card thumbnails, 480 px wide, <= 60 KB, cropped from the REAL rendered panel by
                   tests/ux/bringup/widgets.mjs --thumbs (recorded with size and sha256 in examples.json)
examples.json      GENERATED by scripts/build-gallery.mjs from lean/examples/*.lean + *.json (+ thumbs/)
pin.json           GENERATED by scripts/build-gallery.mjs from QED64.lock.json (+ a check of the release bundle; + apiRevision
                   and shell from the release's dist/qed64-build.json, null on pins A–E)
x3.html            stage A's X3 skeleton (kept for the X3 experiment)
```

## Two modes: the v1 page API and the legacy hooks

`scripts/build-gallery.mjs` reads `release/<pin>/dist/qed64-build.json` (written by a QED64 build that implements
`deps/qed64/docs/EMBEDDING.md`) and records its `apiRevision` and `shell` in `gallery/pin.json` (`null` when the pin's
release has no such file; `scripts/check-gallery.mjs` #4 verifies both). The gallery decides its mode from that, with one
exception: when the local server serves another pin's release than `pin.json` describes (`SHOWCASE_PIN=<id> serve.mjs`: the
`X-Showcase-Pin` header of the `pin.json` response names that pin), the gallery follows the served release's own revision
(`status().modeSource 'served'`) and logs one `console.warn` naming both. `scripts/serve.mjs` reads that revision once at
start from the served release's `dist/qed64-build.json` and sends it on **every** response as `X-Showcase-Api`: the
revision, `none` (no such file: a legacy release) or `invalid` (a file that cannot be parsed or has another schema than
`qed64.build/v1`); the header always has a value. The gallery accepts only a revision (`API_REVISION_RE`) or `none`.
Any other value, `invalid` included, counts as absent, and the gallery then asks the served release for its own
`/qed64-build.json` (404 = legacy). That probe's checks fall back to `pin.json` for such a file. `serve.mjs` sends
`/showcase/pin.json` with `Cache-Control: no-store`, so a server restarted on another pin is never answered from a cached
`pin.json`; the rest of the gallery keeps `public, max-age=0, must-revalidate`. The deployed Worker sends neither
`X-Showcase-Pin` nor `X-Showcase-Api`, so production and the active pin never probe, and a legacy deploy logs no 404. The UX
suite's `API` follows the same rule (`tests/ux/lib/qed64.mjs` `GALLERY_PIN`), except that it refuses a server sending
`X-Showcase-Api: invalid` (the served page's mode is unknown), as it refuses a `qed64-build.json` of another schema.

* **V1 (`pin.apiRevision != null`, pins F `84d594e`, G `5c327c2` and H `bf9d947`, all `apiRevision` `1.0.0`).** The gallery drives the page through its
  declared API only. Next section.
* **Legacy (`pin.apiRevision == null`, pins A–E; E `33b0967` is what the live site serves).** Exactly the flow described
  in the rest of this document: the `qed64.buffer` seed, relay waits, the bridge, the liveness probe, the `?mem` session
  wrap. The sections below describe that flow; each says where V1 differs. The only legacy-visible differences are the
  bridge's expando name (`__showcaseBridge`) and test API version 9's additive fields ("Test API").

`scripts/sim-gallery.mjs` runs both page models (runs 1–15 legacy, 16–20 V1) and asserts that a V1 run touches no
internal; `check-gallery.mjs` runs it.

## Embedding API v1 (pins F, G and H)

The contract is QED64's `deps/qed64/docs/EMBEDDING.md` (§1–§5, §7.8, §8, §9). The code is `gallery.js`, whose helpers
(`api()`, `apiStatus()`, `docText()`, `placeCursor()`, `restartLean()`, …) branch on `S.v1` at the lowest level, so the
driver, the waits, the cards, the keyboard handling and the test API are shared by both modes. *Status (2026-10-08):* H
`bf9d947` is the active pin of this checkout only (G `5c327c2` and F `84d594e` are staged), browser-gated with three
VERDICTs and a headed sign-off (docs/REPIN-LOG.md, pin H entry; current counts: `scripts/showcase.sh pin list`). G
differs from F only inside the page (QED64's `e4cffcc`: the edit coalescer holds full-text changes while the worker pool
is under pressure, `?edithold=<n>`, at most 6 requests in flight, a `$/cancelRequest` for a still-queued request answered
locally; EMBEDDING.md §7.8). H differs from G only in that coalescer: `$/lean/rpc/keepAlive` never waits for a request
slot (QED64's fix for the starvation our C22 found on G). The gallery code is the same on all three; the console oracle
allows G's and H's cancel reply text, and on G only the keep-alive starvation lines ("Console messages").

* **The frame URL.** `/?embed=1&snapshots=snapshots/<overlay>[&memory=<GiB>]#code=<encodeURIComponent(example)>`
  (`lib.js` `frameUrl`). `embed=1` makes the gallery the owner of the document: the page neither reads nor writes
  `localStorage['qed64.buffer']` (a visitor's own buffer on the plain page is never touched) and hides its examples menu.
  The old page is still sent to `about:blank` first: that releases its runtime (one QED64 per page), and a change of
  only `#code=` would be a same-document navigation that boots nothing (§3.1).
* **The boot document.** `#code=` boots the selected example with no flash of other text. The page honours it only in a
  same-origin frame and reads it once (it drops the fragment with `history.replaceState`), so a reload does not
  resurrect it. A `setDocument` made before the boot document is read outranks it (§3.1).
* **The API.** The page defines the frozen `globalThis.qed64.api` at module start and dispatches `qed64:frame-api`
  `{api, frame}` on the gallery window. The gallery accepts it when `detail.frame === iframe.contentWindow` (fallback: a
  polled frozen `pageWin().qed64.api`) and binds it to the document that published it: while a reloaded document has
  not run its module, `status().api.present` is false and nothing is sent to the unloaded page. A page that lacks one of
  the capabilities `documents`, `events`, `embedMode`, `restart` gets the hard "could not start" card
  (`status().api.missing`).
* **Waits and switches.** Polling on `api.status()` (synchronous): ready = phase `ready` or `headerRefused` on relay
  `serving`, `api.getDocument().text` equal to the wanted text, and the version at least the one `setDocument` resolved
  with. A switch is `api.setDocument(text, {cursor, focus: false, undoable: false})`: not undoable (Ctrl+Z cannot revert
  the gallery's replacement), and keyboard focus moves only once the example is ready, via `api.setCursor(pos, {focus})`,
  as in legacy mode. Restarts are `api.restart()` (the relay's own rule for "Load exact imports" options; stall events'
  `how` is `'api.restart'`); a refused header on a session without `mathlib` (`status().snapshots`) is
  `api.restart({snapshots: ['init','mathlib']})`. `__showcase.offer()` / `acceptOffer()` wrap `status().offer` and
  `api.acceptOffer()`.
* **Events.** `boot` and `status` feed the progress-aware boot wait; `fileProgress` and `diagnostics` (except
  `origin: 'qed64'`, the page's own notes) are the stall watchdog's progress and the proof of life; `liveness`,
  `reboot` and `death` mirror QED64's own liveness into `status().liveness.qed64`; `offer` and `document` as below.
* **Persistence: `qed64-showcase:document`.** Every `document` event (the text the relay forwarded) goes to that key, at
  most once per second, flushed on the gallery's and the frame's `pagehide`. The newest forwarded text is also kept in
  memory (`S.doc.lastText`), including when a write fails (a quota error on a multi-MB document, blocked storage).
  On a gallery reload, the text the boot displaces from the key goes through `lib.js` `planSave` into the same kept-buffer
  slots as legacy mode (`qed64-showcase:saved`, `…:saved-history`, `…:edited-example`), so "Open my saved buffer"
  still offers it.
* **When storage is full or blocked: held and unsaved texts** (`gallery.js` `seedBuffer`, `keepDisplaced`, `holdDocument`,
  `persistDocument`, `storageNotice`). The boot's `seedBuffer` tries to keep up to three distinct texts, each in its own
  write: the text stored under the key, a text an earlier boot could not keep (`S.doc.unsaved`), and the newest text in
  memory. The stored text is skipped only when it is this tab's own last successful write (`S.doc.lastWritten`) and the
  tab is not held. In that case memory supersedes it, and keeping both would spend a saved slot on a stale version.
  Another tab's text under the shared key, or a key text this tab never wrote, is always a candidate.
  * **Held.** If the stored text cannot be kept (for example a `QuotaExceededError`), the key holds its only stored copy.
    The boot then **holds** it (`status().document.held`): this tab does not write the key again, and
    the example and later edits live in memory only. Every later write first retries keeping the stored text, at most
    once per `HOLD_RETRY_MS` (5 s). A write that the rate limit skips arms one timer for the rest of the window, and that
    timer retries with the newest text, so an edit made inside the window is not lost when storage is freed and no
    further edit follows. A failed retry arms nothing, so nothing polls. A retry that succeeds releases the hold, and
    the pending write goes to the key. The next boot also retries.
  * **Unsaved.** A text that existed only in this tab's memory and could not be kept becomes unsaved (`status().document.unsaved`). The newest
    such text wins the one slot. The next boot retries it.
  * **The storage notice.** While either state is set, the notice says where each text really is. Example: "It is
    still in this browser's storage under `qed64-showcase:document` … edits in this tab are kept only in memory" for
    held, and "… kept only in this tab's memory. Copy it before you leave the page." with a **Copy it** button (clipboard,
    with an `execCommand` fallback) for unsaved. While a text is unsaved, the notice's × is hidden and inert. When
    another notice is hidden (a dismissed or transient one, or the slow-download notice), the storage notice comes back
    if it still has something to say. When neither state is set, it hides itself. Leaving or reloading the page while an
    unsaved text exists, or while a held tab has edits only in memory, asks first (`beforeunload`).
  * Blocked storage (the `localStorage` getter or a read throws) stores nothing, so nothing is held; a memory-only user
    text still becomes unsaved. Tests: `sim-gallery.mjs` V1 cases b3 to b10 (a reload over a persisted text; a
    quota failure that holds the key; an edited example and an unsaved text while held; freed storage and the one retry
    timer; blocked storage; another tab's text in the key, the notice's × and its return; this tab's own stale key).
* **The adopted reload.** A frame document the gallery did not navigate to (the page's own Reload button, a user's frame
  reload) boots, in embed mode, the EMPTY document unless an embedder's `setDocument` arrives within 5 s of module start
  (§3.1). The gallery therefore calls `api.setDocument(…)` synchronously in its `qed64:frame-api` handler with the newest
  text it saw forwarded (memory first, then the key, then the current example; another gallery tab's text under the
  shared key never replaces this tab's), records it in `status().api.adopted` / `adoptSet`, and then follows the page
  as legacy mode did (the text may hold the user's edits: never overwritten).
* **What stands down.** The RPC bridge (`capabilities.editorRpc` and `widgetSourceCache`: `status().bridge.stoodDown`;
  "The RPC bridge"); the liveness probe (`capabilities.liveness`: `status().liveness.probe 'stood-down'`, "Errors"); the
  `?mem` session wrap (`&memory=`; "Memory knob").
* **What is internal, and why the gallery does not touch it.** §9 makes every other member of `globalThis.qed64`
  (`relay`, `ui`, `artifacts`, `editor`, `status()`), the `qed64.buffer` key, every DOM id, class and label string, and
  the `__qed64*` namespace internal: they may change in any commit. In V1 the gallery reads none of them, with one
  exception: the narrow-screen stacking `<style>` (and the `#examples` rule, a no-op under `embed=1`), runtime styling
  of the page document that never throws and never fails a boot when the ids are missing, kept because `layout=` is
  v1.1. The page's resource timing entries (a standard Web API, not QED64's) still count as boot progress, and the F6
  capture listener on the framed window is allowed by §9. The UX suite still uses internals for diagnostics and fault
  fixtures (relay counters, telemetry through the test hatch `qed64.test` when present, the LSP tap, `onLsp`/`onStatus`
  replacement, worker globals): docs/ARCHITECTURE.md "Integration points".

## Run it

```
node scripts/build-gallery.mjs            # after any change to lean/examples or QED64.lock.json
node scripts/serve.mjs                    # or scripts/serve-start.sh; port 5190
open http://localhost:5190/showcase/      # e.g. http://localhost:5190/showcase/?overlay=widgets7#hasse-view

# real-Chrome bring-up (one browser on the host at a time; the wrapper takes the host lock, --print-lock shows it)
scripts/with-browser-lock.sh bringup node tests/ux/bringup/widgets.mjs --dir after --thumbs   # panels, shots, thumbs
scripts/with-browser-lock.sh bringup node tests/ux/bringup/hints.mjs                          # every card hint
scripts/with-browser-lock.sh bringup node tests/ux/bringup/questions.mjs                      # resolved questions
node scripts/build-gallery.mjs && node scripts/check-gallery.mjs --live
```

| Parameter | Meaning |
|---|---|
| `?overlay=<dir>` | Snapshot overlay under `/snapshots/<dir>/`. Default: `widgets8`, and if that fails its preflight, `widgets7`. An explicit value is preflighted alone and never falls back. `rehearsal` works for wiring tests, but QED64 then refuses the widget headers. |
| `?mem=<GiB>` | Memory knob (stage A X5): the initial memory commit for the session that loads the widgets region. Rounded to 256 MiB and clamped to [1, 6] GiB. See "Memory knob". |
| `?stack=0\|1` | Narrow screens: stack the page's editor above its InfoView. The default is automatic at ≤ 720 px; `0` turns it off and `1` forces it on. |
| `?pagebar=full` | Keep the QED64 page's own example menu (`#examples`). By default the gallery hides it: it swaps in a stock document behind the gallery's back and its label ("Mathlib — real numbers") reads as if it named the current example. |
| `#<pkg>` | Deep link, e.g. `#simp-lens`. The gallery keeps the hash updated (`replaceState`), and editing it switches the example. |

## Boot flow (`gallery.js` `boot()`)

0. **Browser capabilities, before anything boots** (`lib.js` `checkCapabilities`, hardening lane 2026-10-02). The gallery
   checks `crossOriginIsolated`, `SharedArrayBuffer`, WebAssembly Memory64 (the same 13-byte module QED64's worker
   validates, `lean.worker.js` `MEMORY64_PROBE`, plus a shared 64-bit `WebAssembly.Memory` built the way the worker builds
   it) and, where the browser exposes it (Chromium only; approximate: Chrome 151 on this 36 GB host reports 32), `navigator.deviceMemory`. If one of the first three
   is missing the stage shows the card "This browser cannot run the Lean widget gallery": "This showcase needs a
   Chromium-based desktop browser (Chrome, Edge, Brave, Arc) on a computer with 16 GB of RAM or more, one showcase tab
   at a time (a tab uses about 8–9 GB, about 12 GB on a reload); your browser lacks X." (`lib.js` `BROWSER_NEED`) with the ✓/✗
   list, no Try again, no Dismiss, no stock-page link; nothing is fetched from QED64, the iframe never navigates, the
   phase is `unsupported`, and `select()` / deep links reject with `code: 'UNSUPPORTED'`. A device reporting less than
   8 GB gets a warning card ("This device may not have enough memory", same sentence, "lacks enough memory"; the check
   reads "the device reports only N GB of memory; a showcase tab uses about 8–9 GB, about 12 GB on a reload"; the
   threshold stays 8 GB although 16 GB is recommended, an owner decision) whose **Try
   anyway** boots as usual (`status().caps.override`). `status().caps` reports every check. Without JavaScript the veil
   shows a `<noscript>` line with the same requirement. Tests: `sim-gallery.mjs` run 14 (one case per missing capability,
   a combined case, low memory with Try anyway, a capable 8 GB browser), `check-gallery.mjs` 7 (the probe bytes equal the
   active pin's worker; every branch of `checkCapabilities`), UX C24 (real Chromium: a document served without COOP/COEP;
   Memory64 refused and low memory simulated by init scripts; Try anyway boots). No WebKit or Firefox Playwright build is
   cached on this host, so no other engine was run.
1. **Data.** Fetch `pin.json` and `examples.json` (`cache: no-cache`, both started before either is awaited). A failure
   shows the "gallery data is missing" card. `pin.json` decides the mode ("Two modes"); only when `X-Showcase-Pin` names
   another pin than `pin.json` does the served release's mode count: from `X-Showcase-Api`, and only when that header
   is absent or not a revision or `none`, from a fetch of the served `/qed64-build.json`.
2. **Pairing preflight** (`lib.js` `preflightOverlay`, run before any navigation). It mirrors lean4game
   `game-boot.ts:113-145` and plan §7.3, and every check appears in the error card:
   * the overlay name is safe (`^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`);
   * `/runtime/runtime-manifest.<buildId>.json` is JSON and names `pin.buildId`. This is the manifest the
     bundle fetches first (`qed64-boot.ts:62-66`);
   * `/snapshots/<overlay>/index.json` returns 200, is not HTML, parses, and has
     `schema == qed64.snapshot-index/v1`;
   * entries `init` and `mathlib` are both present. These are exactly the names the stock page boots for
     a Mathlib header (`resident-session.ts:85`);
   * every entry has `runtime == pin.buildId`, a `sha256:` digest, and an integer `transfer`;
   * `HEAD` on each re-rooted `.snapz` (`/snapshots/<overlay>/<file>`, re-rooted exactly as
     `qed64-boot.ts:96-106` does) returns 200, with `content-length == transfer`, a non-HTML content
     type and no `content-encoding`.
   * Availability: the `mathlib` entry's `imports` list says which packages the region contains. That
     drives the rail chips ("available" / "not in widgets7"). If `imports` is absent, availability is
     unknown and the chips show the phase instead.

   `pin.buildId` comes from `QED64.lock.json`. `build-gallery.mjs` fails unless
   `release/<BID>/dist/assets/*.js` names exactly that buildId (plan S0.5 #6).
3. **Seed.** If `localStorage['qed64.buffer']` holds a user buffer, it is kept (`lib.js` `planSave`): the
   FIRST one goes to `qed64-showcase:saved`, which is never overwritten; later distinct ones go to
   `qed64-showcase:saved-history` (newest first, at most 5). Not user buffers: our pristine example texts, the
   `?mem` placeholder, and **an example edited in the gallery** — QED64 persists the editor, so every edit you
   make to an example (e.g. any click hint) comes back as `qed64.buffer` on the next visit. A buffer whose first
   4 lines (the two-line header, the blank line, the `/-! # Title` line) equal an example's is such an edit; the
   latest one goes to its own slot `qed64-showcase:edited-example` (action `example`) and can never push a real
   user buffer out of the history. Then `qed64.buffer` is set to the selected example. That key is the page's boot
   document (`main.ts:335-342`). The rail footer shows "Open my saved buffer" when one buffer is kept; with two or
   more, a chooser (`#restore-pick`, newest first: "newest: …", "older N: …", "first saved: …") and "Open". It
   opens the chosen one — by default the NEWEST — in the editor; no card is then current and the status line says
   "Your saved buffer is ready". `__showcase.restoreSaved(i)` does the same for entry `i` (verified over real reloads by
   `questions.mjs` q14, `out/ux/bringup/questions-q13-q14.json`). Before a re-navigation (Retry), the old page is
   first sent to `about:blank`. Its `pagehide` handler then unloads the relay, which kills the worker
   and its multi-GiB heap. No pending 400 ms buffer save can then overwrite the seed.
   **V1:** nothing is written to `qed64.buffer` (`status().seed.action` `'embed'`); the example travels in `#code=`. The
   text the boot displaces from the gallery's own key `qed64-showcase:document` goes through the same `planSave` (action
   `saved`, `history` or `example` when something was kept). The `about:blank` step stays.
4. **Navigate.** `iframe.src = /?snapshots=snapshots/<overlay>`. **V1:**
   `/?embed=1&snapshots=snapshots/<overlay>[&memory=<GiB>]#code=<example>`.
5. **Bridge.** `qed64-bridge.js` is installed on the page window as early as possible. See below. **V1:** not
   installed (`status().bridge.stoodDown`).
6. **Ready.** Wait for `globalThis.qed64`, then for `qed64.status().phase === 'ready'` with
   `qed64.relay.lastText === example.text`. `headerRefused` also counts as settled; the gallery then
   shows a notice that the overlay lacks the package. **V1:** wait for the api (`qed64:frame-api`, within the same
   120 s hook budget; the capability check runs here), then poll `api.status()` for `ready`/`headerRefused` on relay
   `serving` with `api.getDocument().text === example.text`. The boot wait's progress comes from the `boot` and `status`
   events instead of the `qed64.ui` wraps, and the page's own boot card is `status().boot.overlay` instead of `#boot`.
7. **Cursor.** `editor.setPosition(firstCursor)`, `revealLineInCenter`, then `contentWindow.focus()`
   and `editor.focus()`, so the InfoView shows the panel straight away (verified: keyboard focus lands in
   Monaco, and the InfoView follows `setPosition` even without focus — "Resolved questions" 2). `firstCursor` is the spec's
   `cursors[0]`: the 0-based LSP position converted to Monaco's 1-based position. Monaco columns count
   UTF-16 units, as LSP characters do. **V1:** `api.setCursor(firstCursor, {focus: true})` (the page clamps and reveals)
   after `contentWindow.focus()`.

**Switching** (`switchTo()`): `editor.getModel().setValue(text)`, then wait for `ready` with
`status.version > versionBefore` and `relay.lastText === text`, then set the cursor. Only one operation
runs at a time, and the latest selection wins. A newer selection cancels the wait in flight
(`Superseded`), and the driver goes straight on to the newest one. The rail, the select, deep links, hint
buttons and the API all go through `choose()`. If the session was booted without Mathlib (the page reloaded
into a user's init-only buffer), QED64 refuses the example's header and does not widen by itself; the
gallery then calls `relay.restart({snapshots: ['init','mathlib']})` once and waits for the example on the
new session. **V1:** `api.setDocument(text, {cursor, focus: false, undoable: false})`, then the wait of step 6 with the
version `setDocument` resolved with; a halted relay is re-armed with `api.restart()` first, a stalled checker gets the
text and then `api.restart()`, and the widen is `api.restart({snapshots: ['init','mathlib']})` with the wait on the
replacement session.

**Edited.** The 250 ms monitor compares `relay.lastText` (V1: `api.getDocument().text`) with the shown example. When they differ (the
user typed, a widget link inserted text, or anything replaced the document) the card's chip reads
"edited", the status line says "<example> (edited) is ready", and Reset example restores the example.

**Deep links.** `#<pkg>` is parsed by `lib.js` `parseHash`, which never throws: a malformed escape (`#%`)
or an unknown id boots the first example with a notice ("There is no example called …"). Notices of
that kind are transient: the user's next selection dismisses them. An error card hides any notice.

**Reset example** calls `setValue(text)` even when the text is identical. A relay halted by the crash
breaker re-arms only on a `didChange` (`lsp-relay.ts` `fromClient`). If no version bump arrives within
3 s, `ready` on the same text is accepted. In Chrome the identical-text `setValue` does send a didChange
(version 5 → 6 in 255 ms), and it re-arms a halted relay (fresh session in 8.1 s). **V1:** `api.setDocument` with
identical text resolves `{unchanged: true}` and sends nothing, so a halted relay is re-armed by `api.restart()` (no
arguments) instead.

**Copy for VS Code** copies the pristine example text. It needs a VS Code project that depends on
Mathlib and on the package (`import Mathlib` / `import <Pkg>`, plan D2).

## The RPC bridge: when it is installed, and why that is early enough

`qed64-bridge.js` fixes three defects of the shipped page. D1 (stage A, X4) strips the
non-serialisable `abortSignal` from `sendClientRequest`; without that, every `mk_rpc_widget%` panel
shows "Unrecognised error". D2 (X4) applies `applyEdit`, `showDocument` and `insertText` to the open Monaco
model directly. D3 (this bring-up) coalesces concurrent `Lean.Widget.getWidgetSource` requests for one
hash: the first goes to the page, its reply (seen on a tap of `qed64.relay.toClient`) is cached per hash
and answers the held duplicates and later requests; an error reply, a lost reply or 15 s release the held
ones to the page unchanged. Why D3 is needed: "QED64 limitations" L2. The bridge works by intercepting the
messages that the InfoView iframe (`#infoview iframe`) posts to the **page window**; `bridgeStats().ws`
counts `{fetched, cached, coalesced, released}`.

**On pins F, G and H (v1) the bridge is not installed.** All three defects are fixed in the page: D1 and D2 by QED64's HARDENING #56
(`capabilities.editorRpc`: the InfoView's RPC now crosses the iframe as `startClientRequest`/`awaitClientRequest`/
`cancelClientRequest`, and the page implements `applyEdit`, `showDocument` and `insertText` on its one model), D3 by the
page's own widget-source cache (`capabilities.widgetSourceCache`, EMBEDDING.md §2.5). With both capabilities the gallery
records `status().bridge.stoodDown: true`, `installed: false`, no installs, and `bridgeStats()` is null; W1–W8 and C20
assert that, and that the RPC panels and link edits still work. For a v1 page that lacks a capability (none exists
today): without `editorRpc` the bridge is installed late with edits on and D3 on unless `widgetSourceCache`
(`capabilityMismatch.repair 'late'`); with `editorRpc` but no `widgetSourceCache` it is NOT installed, because its D3
path matches only the pre-#56 `sendClientRequest` name and would repair nothing (`repair 'unavailable'`, a
`console.warn`). Everything below describes pins A–E.

* **Install point.** Polling starts every 4 ms the moment `src` is set. The first tick that sees the
  committed page document installs the bridge (`pageWin()` ignores the initial `about:blank`). In Chrome
  the first tick that sees the committed document finds `readyState: 'interactive'` (not `loading`) with
  `qed64Present: false` and `alreadyInstalled: false` — every bring-up boot, e.g. `{t: 82, reason:
  'commit-poll', readyState: 'interactive', qed64Present: false}` in `out/ux/bringup/widgets-after.json`.
  `interactive` is after parsing but before the deferred module script runs, so the bridge's listener is
  registered before the page's own. The iframe's `load` event, every
  wait-loop poll, the 250 ms monitor and every cursor placement re-check the install.
* **Reloads the gallery did not start** (for example the page's own "Reload" button). Each installed
  page window also gets a `pagehide` listener that restarts the 4 ms commit poll. The next document is
  therefore caught while still `loading` too, not at `load`. The simulation shows this.
* **Why "before the page's own listener" matters.** The page's InfoView listener is a plain
  `window.addEventListener('message', …)` registered by its module script. Installed AFTER it, the bridge's
  `stopImmediatePropagation` does not stop the page's handler (listeners at the target fire in registration
  order in this Chrome), so both run: `out/ux/bringup/console-a.json` mode `parent-late` gives 3 page errors
  (activation `unsupported`; `unsupported` at `$tryShowTextDocument` from the page's own applyEdit; an
  unhandled rejection `Object`) and 2 InfoView warnings `Cannot read properties of undefined (reading
  'resolve')` (the iframe got two replies to one request), while `parent-early` and the gallery give 1 page
  error. With a widget panel the late install even shows "Unrecognised error" (`console-hasse.json`,
  `parent-late: unrec true`). This is why the stage-A auditor, who installed from the parent after the page
  was up, saw three page errors instead of one. The gallery records `qed64Present` per install; a late
  install raises a notice and counts in `status().bridge.late` (the UX suite asserts 0).
* **Why that precedes any widget RPC.** The InfoView iframe is created by lean4monaco only after the
  page's module script has run (module scripts are deferred until the document is parsed), the editor
  has started, and the LSP session has booted, which takes seconds. A widget RPC also needs the cursor
  on a widget, and the gallery sets the cursor only after `ready`, once it has asserted that the bridge
  is installed. Messages the bridge does not handle pass through untouched, so installing early does no
  harm.
* **Idempotence.** The bridge guards itself with `window.__showcaseBridge` (renamed from `__qed64Bridge`: the
  `__qed64*` namespace is QED64's own, EMBEDDING.md §9) and installs one capture-phase
  listener. The gallery also records each document it installed on (a `WeakSet`), with
  `{t, reason, readyState, qed64Present, alreadyInstalled}` in `__showcase.status().bridge.installs`.
  `scripts/check-gallery.mjs` installs the bridge three times on a fake window: the result is one
  listener and the same stats object.

## Memory knob (`?mem=<GiB>`)

**On pins F, G and H (v1)** the knob is a boot parameter of the page: `?mem=<GiB>` travels as `&memory=<GiB>` on the frame URL
(EMBEDDING.md §2.3, §4: rounded to 256 MiB, clamped to [1, 6] GiB and to the device's reservation ladder), so the FIRST
session gets the commit and no light boot, wrap or restart is needed. `status().mem` reports `{requestedGiB, bytes, ok,
applied, wrapped: false, light: null, sessions: []}`, with `applied` true when `api.status().memory.initialBytes` (the
commit the worker made) equals the request. UX C3 checks it on the v1 pins with a same-tab re-navigation to `?mem=3`. The rest of
this section is the legacy mechanism of pins A–E.

**Constraint.** The relay builds the *first* session inside its own constructor and calls `start()`
synchronously. `start()` passes `initialBytes` to `lean.boot()` before the page has even assigned
`globalThis.qed64`. The bundle shows this order: `s=new Jtn(...)` comes before `globalThis.qed64={...}`
(see `resident-session.ts:151-190` and `lsp-relay.ts` constructor). So no same-origin hook can change
the first session's commit.

**Approach.** The knob makes the first session **light**:

1. The seed is a comment with no import lines, so `EDITOR_POLICY` boots `['init']` at 256 MiB.
2. Once that session is ready, the gallery wraps `qed64.relay.makeSession`, the relay's own instance
   property; X5 confirmed `ownProperty: true`. The relay calls `this.makeSession(...)` on every reboot,
   and the wrapper sets the new session's `initialBytes` before its `start()` runs. `reboot()` awaits
   the 1.5 s settle first.
3. The gallery then calls `relay.restart({snapshots: ['init','mathlib']})` and `setValue(example)`.

**Result.** The session that loads the widgets region is the wrapped one, and so is every later crash
or heartbeat reboot. The cost is one light init boot, a few seconds. `__showcase.status().mem` reports:

* `light`: the first session and its commit;
* `sessions`: every wrapped session;
* `applied`: `relay.session.initialBytes === bytes`;
* `telemetry`: the worker's `memory` report, best effort.

**Rejected alternative.** Patching `Worker.prototype.postMessage` in the page before its module script
runs would race the navigation commit.

**Measured in Chrome** (`tests/ux/bringup/memprobe.mjs`, all eight examples in turn, 1440×900, one run each).
Each column pair uses ONE persistent profile: the first run on a fresh profile is *cold* (empty OPFS and HTTP
cache), the second run on the same profile is *warm*. Default and `?mem=3` use separate profiles, so neither warms
the other. (The first version of this table compared a warm default run, `mp-all-d3.json`, with a cold `?mem=3`
run, `mem3.json`; the "+2.9 GiB RSS, +12 s" it reported was that mismatch, not a cost of `?mem`.)

| | default, cold | default, warm | `?mem=3`, cold | `?mem=3`, warm |
|---|---|---|---|---|
| file (`out/ux/bringup/`) | `mem-def-cold.json` | `mem-def-warm.json` | `mem3-cold.json` | `mem3-warm.json` |
| sessions | s1 `[init, mathlib]` 2048 MiB | same | s1 light `[init]` 256 MiB → s2 `[init, mathlib]` 3072 MiB | same |
| worker log | `[mem] runtime-initialized: 2048 MiB` | same | `… 256 MiB`, then `[mem] runtime-initialized: 3072 MiB` | same |
| wasm heap peak (telemetry `currentBytes`) | 2147483648 (= the commit; the 1,390,198,690-byte region fits, no grow) | 2147483648 | 3221225472 (= the commit) | 3221225472 |
| boot to ready | 10.6 s | 6.6 s | 15.0 s | 11.0 s |
| headless-shell RSS peak (total / largest renderer) | 9.42 / 9.01 GiB | 9.45 / 9.06 GiB | 9.73 / 9.31 GiB | 9.46 / 9.06 GiB |
| examples ready / "Unrecognised error" / pthread pool peak / crash | 8/8 / 0 / 24 / no | 8/8 / 0 / 24 / no | 8/8 / 0 / 24 / no | 8/8 / 0 / 24 / no |
| crash reboot (`mem3.json`, `--crash`) | — | — | s3 again 3221225472 `[init, mathlib]` (wrapper stays on the relay; 10.4 s) | |

Like for like, `?mem=3` costs **+4.4 s of boot** (cold 10.6 → 15.0 s, warm 6.6 → 11.0 s: the extra light init boot
and the restart) and **no measurable RSS** (+0.31 GiB cold, +0.01 GiB warm; single runs, within run-to-run noise:
the cold default runs of `widgets.mjs` at deviceScaleFactor 2 peak anywhere in **8.9–12.3 GiB** total over five
cold runs: `widgets-after-audit5.json` 8.86, `widgets-audit5.json` (the auditor's) 11.28, `widgets-after-audit5b.json`
11.38, `widgets-rss-audit5c.json` 11.40, and 12.33 in the first `--thumbs` run of audit 5 whose file the second one
replaced; ps is sampled once a second, so a single peak is not a stable figure and no single-number RSS is quoted
any more). The 3 GiB commit is
reserved address space, mostly untouched, so it does not show up as resident memory.

**Decision: widgets8 does not need `?mem`.** Under the stock 2 GiB commit the heap never grew past
2048 MiB through every first cursor (`mem-def-*.json`, `mp-all-d3.json`), all 46 spec cursors
(`sp-all-cursors-d3.json`) and all 71 card hints (`hints.json`), with no worker death. `?mem=3` works end to end
but costs about 4.4 s of boot for no benefit here; keep it as an opt-in knob for heavier regions.

## Errors

* **Preflight failure.** A blocking card lists each check with ✓ / ✗. It also has "Try again", a link
  to the stock page, and the raw attempts under "Technical details". Nothing is loaded.
* **The page's own boot failure** (`#bootcard.failed`, for example a missing manifest or core pack)
  before `globalThis.qed64` exists. A blocking card shows the page's `#bootlabel` message. **V1:** `status().boot.failed`
  with its `message` gives the hard card at once, except while the relay is halted or when the message is the re-armed
  halt's own death report (`hardBootFailure`); a death the relay retries never sets `boot.failed` on a v1 pin.
* **A death before the first `ready`** (`status().lastDeath`). QED64 retries up to 3 deaths in 120 s,
  so this gets a soft card that closes by itself if the page recovers.
* **`halted`** (the crash breaker). A soft card "The Lean checker stopped" whose action button is
  "Reset example"; Reset re-arms the relay (8 s in Chrome). If the relay recovers to `ready`, the card
  closes. Screenshot: `out/ux/bringup/q3-halted.png`.
* **The page's own failed boot card is showing too** (for example a lasting network cut, UX suite C11). The gallery's
  card turns compact (`is-compact`: title, one line "QED64’s own card below says what failed", Try again / Dismiss)
  at the top of the stage, so it never covers QED64's card. C11 asserts no overlap (`out/ux/<run>/tests/C11.json`
  `lasting.layout`).
* **A frozen runtime (QED64 limitation L7): the liveness probe restarts it by itself.** QED64's whole Lean runtime can
  freeze: every Lean pthread stops, while the worker's JS thread stays alive and keeps the heartbeat going, so QED64
  never notices and keeps reporting `elaborating` on a serving relay with no death and no LSP message (see "QED64
  limitations found", L7). The gallery watches every edit, not only its own operations. While QED64 reports
  `elaborating` on a serving relay, any `$/lean/fileProgress` or `publishDiagnostics` message (counted by a wrapper on
  `qed64.relay.toClient`; V1: the API's `fileProgress` and `diagnostics` events, `status().stall.source 'api-events'`) or
  a new phase, version or session counts as progress.
  * **Liveness probe (default, `?liveness=auto`). The gallery works with any QED64 pin, and decides per page, not per
    build:** on a page WITH QED64's own liveness (pins `5ac5d00` and `9fdf9b8`, the #52 worker) **the probe starts after
    30 s without progress**, because it defers to QED64's liveness (below): a frozen runtime that QED64 does not see is
    restarted **about 41 s after the last progress and ready again about 49 s after it** (C21 (a) in `closeout2-full1`:
    restart 40.9 s, ready 49.0 s after the click). On a page WITHOUT it (pin `1859b83`) the gallery's probe is the
    primary recovery and starts after **10 s**. Which kind of page it is comes from `status().liveness` at run time
    (`status().liveness.qed64.builtIn`); the UX suite requires that to equal the active pin's descriptor
    (`pins/<id>/pin.json` `liveness.builtIn`). Either way the gallery then sends
    `textDocument/hover` for the open document at 0:0 through `relay.fromClient`, with a **string** id
    (`showcase-live-<n>`, which cannot collide with the editor's numeric ids) and full `params` (`textDocument` +
    `position`; a Lean FileWorker request without params ends in "Got invalid JSON-RPC message" and kills the
    worker). The reply is swallowed in the same `toClient` wrapper, so the editor never sees it. A hover answer needs a
    Lean task thread and a proxied `fd_write`, which is exactly the path that dies in L7, and Lean answers it while
    elaboration is busy elsewhere (UX suite C22: 3 probes answered in 1–3 ms during a 38 s silent `#eval`; verified first with a 40 s one, `tests/ux/tools/liveprobe.mjs`). An
    answer, or any progress, means alive and re-arms the probe. **Two consecutive probes unanswered within 5 s each**
    mean wedged: the gallery calls `relay.restart` with the session's own snapshots (a fresh worker on the same text)
    and shows a small non-blocking notice, "Lean stopped responding and was restarted. Your text is kept." On the
    previous pin (10 s threshold) that was about 20 s after the last progress (C21 then: restart 20.4 s after the click,
    ready on the new session at 28.6 s); on pin C (QED64 liveness; served until 2026-10-04) it is about 41 s / 49 s, as above (docs/UX-RESULTS.md).
    At most one automatic restart per **120 s**; a second wedge inside that window, or a restart that throws, is
    left to the card below.
  * **The main-loop probe (hardening lane, 2026-10-02; pin `1859b83`'s C22 (3)).** With every hover probe the gallery
    also sends `$/showcase/liveness` (string id `showcase-main-<n>`, `params: {}`): an unknown method, which Lean's
    FileWorker answers from its MAIN LOOP at once, without a pool thread (`FileWorker.lean` `handleRequest` →
    `emitRequestResponse`, the `Except.error` branch: MethodNotFound -32601 through the normal output path; without
    `params` the FileWorker would die). It is the same kind of request QED64's own liveness writes (`$/qed64/liveness`).
    Its reply is swallowed by the `toClient` tap; a reply QED64's JS layer makes (failInFlight, halted) is not an answer
    (`mainLoop.synthetic`, event `main-synthetic`). A Lean answer since the first probe of the sequence settles a timed-out
    hover `alive` via `main-loop` (checked after `frame`, `late-answer` and `qed64-answered`), and counts as a recent sign
    of life for the card's wording. `status().liveness.mainLoop` = `{method, sent, answered, synthetic, outstanding,
    lastAnsweredAgoMs, lastMs, maxMs}`. A real L7 freeze stops it too (the main loop's reply needs the same proxied output
    path), and C21's page-level freeze drops it like every other frame, so the recovery is unchanged. The hover stays the
    second signal.
  * **Late answers are classified by elapsed time (hardening lane).** A hover reply that arrives after `probeTimeoutMs`
    is a LATE answer even when the 250 ms monitor tick has not yet looked at the probe (before, such a reply counted as on
    time, so a host-delayed event loop could turn a late answer into an on-time one: the docs lane's one red sim run 12).
    A real late reply to the outstanding probe settles the sequence `alive` via `late-answer` at once; a late error reply
    is recorded (`late`, `proofOfLife: false`) and the probe still times out as a miss. `late` events carry `ms`.
  * **Proof of life besides the hover (final audit).** A hover waits for a free Lean task thread. When parallel proofs
    saturate the pool (24 parallel `theorem … := by sleep 45000; trivial`: pool `{unused 0, running 27}`) it goes
    unanswered while Lean is healthy, and the audit saw the gallery restart such a session (a false "Lean stopped
    responding", the work thrown away, ready at 140 s instead of about 50 s). So a probe that times out counts as
    **missed** only if, since the first probe of the sequence, the page has seen **no server frame at all** (the same
    `toClient` wrapper counts every non-probe message that comes from Lean) **and**, on a page with QED64's own liveness, **QED64's own
    probe was not answered** in the 10 s before that first probe or at any time since. QED64's probe is an unknown
    method the FileWorker's main loop answers at once, without a pool thread, and QED64 sends one after every 6 s
    without a frame, so a live Lean side answers one about every 6–10 s. Otherwise the probe is settled `alive`
    (event `alive`, `via` `frame`, `late-answer` or `qed64-answered`; `status().liveness.alive`, `aliveVia`) and
    re-arms. A real L7 stops every signal (and QED64 then stalls, so the gallery defers to it).
    **A late but real answer counts too (multi-pin lane, 2026-10-02; the critic's minor).** A hover that waited for a
    free task thread past the 5 s timeout and is then answered by Lean (a non-error reply that QED64's JS layer did not
    make) proves the Lean side alive just as a frame does: it is recorded (`status().liveness.lateAnswers`, event
    `late` with `proofOfLife: true`), and a probe sequence that saw one settles `alive` via `late-answer` instead of
    declaring the session wedged. This matters most on a page without QED64's liveness (pin `1859b83`), which has no
    `qed64-answered` signal: there, a pool saturated for the whole 2 × 5 s sequence with no frame and no late answer
    can still look wedged, and does in the browser: UX C22 (3) on pin `1859b83` (`multipin-A-liveness`, 2026-10-02) had
    hovers waiting about 55 s, no frame and no late answer within 10 s, and the gallery restarted the healthy session
    (`wedged 2, restarts 1`). **Fixed by the main-loop probe** (above): `harden-A-c21c22` (A on :5196) passes C22 (3),
    settled `alive` via `main-loop` 3×, 0 restarts; A still has no full-suite verdict with this gallery. `sim-gallery.mjs` run 12 models it (hovers answered 0.9 s after a 0.5 s timeout, i.e. after the next 250 ms tick: 0 restarts;
    the same page frozen: restarted), and fails with the `late-answer` line removed (2 FAIL).
    UX suite C22 (3) checks the saturated pool in the browser; `sim-gallery.mjs` run 10 models it.
    **Only frames from Lean count (close-out 3).** QED64's JS layer, which stays alive during an L7 freeze, makes some
    frames itself: the front door's ContentModified (-32801) replies to completions it fails fast on an import line
    (`lsp-front-door.js:288`), the relay's -32603 halted replies (`lsp-relay.ts:112`) and `failInFlight`'s -32603 /
    -32900 replies (`lsp-relay.ts:212`), all with a message starting `QED64:`, and the relay's halted note (a
    `publishDiagnostics` whose every diagnostic has source `QED64`). Those count neither as proof of life nor as
    progress (`status().liveness.syntheticFrames`), and such a reply to a probe is not an answer (event
    `synthetic-reply`, `syntheticReplies`). `sim-gallery.mjs` run 11 freezes a rollback-style page (no QED64
    liveness) while those frames keep arriving and requires the restart; with the filter removed (mutant E) it fails.
  * **On a QED64 page with its own liveness (pins `5ac5d00` and `9fdf9b8`): the gallery defers.** QED64 now fixes L7 itself (HARDENING #52; see "QED64 limitations found", L7): its worker serves the
    runtime mailbox every second (a lost wakeup is "rescued" and counted), probes the FileWorker after 6 s without a
    server frame, logs a stall when that probe stays unanswered for 12 s, and 4 s later kills the session (died
    `wedged`); the relay reboots it (`status().relay` `rebooting`, `rebootReason` `wedged`, the page's pill "the checker
    stopped responding — restarting") and replays the text. The gallery detects this from `status().liveness`
    (`{probes, answered, stalls, resumed, rescues}`) and then:
    * starts its own probe only after **30 s** without progress (`probeDeferMs`, `?probeDefer=<s>`) instead of 10 s,
      past QED64's worst-case window (6 + 12 + 4 s, each up to one 1 s tick late, about 25 s), so it never races
      QED64's reboot;
    * never probes or restarts while QED64 reports a stall in its grace window (`stalls > resumed`); a gallery wedge
      decided then is recorded with action `deferred`, and the card stays the fallback;
    * observes and reports QED64's own actions: `status().liveness.qed64` (`builtIn`, per-session `counters`, `totals`,
      `wedgedReboots`, `lastReboot {from, to, lastDeath}`) and the events `qed64-detected`, `qed64-rescue`,
      `qed64-stall`, `qed64-resumed`, `qed64-wedged` and `qed64-rebooted`; on a `wedged` reboot it shows the notice
      "Lean stopped responding; QED64 is restarting it. Your text is kept."
    * remains a fallback for what QED64's worker cannot see: a page-level freeze (C21's synthetic fixture: QED64's
      worker keeps seeing frames, so its liveness rightly does nothing, and the gallery restarts about 40 s after the
      click, before the 45 s card) or a QED64 liveness that never acts.
    On the previous pin (no `status().liveness`) the 10 s probe above applies unchanged.
  * **On pins F, G and H (v1): the probe stands down.** Its transport (`relay.fromClient` and a `toClient` filter) is internal
    (EMBEDDING.md §9), and QED64's liveness is declared (`capabilities.liveness`). `status().liveness.probe` is
    `'stood-down'` and `sent` stays 0 (W1–W8, C20–C23 assert it); without the capability it would read `'unavailable'`.
    The gallery mirrors QED64's projection `api.status().liveness` (`stalled`, `lastAnswerAgoMs`, `lastFrameAgoMs`,
    `probeAfterMs`, `wedgeAfterMs`, `graceMs`) and the `liveness`, `reboot` and `death` events into
    `status().liveness.qed64` and the `qed64-*` events, shows the same notice on a `wedged` reboot, and uses
    `lastAnswerAgoMs`/`lastFrameAgoMs` and the `fileProgress`/`diagnostics` events as the signs of life for the card's
    wording. The 45 s stall card is then the gallery's recovery for a freeze QED64's worker cannot see (C21's synthetic
    fixture), with Restart Lean = `api.restart()`.
  * **Observe mode (`?liveness=observe`, or `__showcase.liveness('observe')`).** For hang hunts: the probe detects
    and records the wedge (`status().liveness.events`, action `observed`) and never restarts anything, so the frozen
    runtime can be captured (the UX harness's hang capture, `tests/ux/lib/qed64.mjs` `captureHang`, writes
    `out/hang/captures/<run>-<iso>.json`). `?liveness=off` disables the probe. `?probe=<s>`, `?probeTimeout=<s>` and
    `?restartGap=<s>` change the timings (tests only). On a pin with QED64 liveness (C, B) QED64's own reboot (about 22–25 s after the
    last frame) comes before the gallery's observe-mode wedge (30 s + 2 × 5 s), so a hang QED64 handles is never seen
    frozen from outside: the harness then writes a post-hoc record instead (`captureQed64Reboot`,
    `out/hang/captures/<run>-<iso>-qed64-wedged.json`: QED64's `lastReboot`, its liveness counters and the worker's
    `[liveness]` lines; exercised in the browser by UX test C23 on a forced `die(null, "wedged")`), and C20 and W1–W8 accept such a reboot as an L7 occurrence handled upstream (one `wedged`
    death plus its reboot each; console scenario `qed64WedgedReboot`).
  * **Stall card (the fallback).** After **45 s** without progress (`?stall=<s>` overrides, ≥ 5) a soft `role=alert`
    card "Lean has stopped making progress" offers **Restart Lean** (`relay.restart(...)` with the session's own
    snapshots: a fresh worker on the same text, a few seconds; the page is reloaded instead if the relay is not
    serving), **Reset example** (restart on the example) and **Keep waiting** (hides the card and re-arms the
    watchdog). The toolbar's Reset on a stalled checker restarts it too (a didChange alone cannot reach a frozen
    runtime). The card closes by itself when QED64 is ready again. In the default mode it appears only when the
    automatic restart did not happen (rate limit, failed restart) or did not help, or when Lean keeps answering
    probes but makes no progress for 45 s (no example needs more than about 2.5 s per command). In that last case,
    i.e. when Lean gave a sign of life (a probe answer, a server frame including a late progress message, a QED64
    probe answer) since this version of the file started checking and within the last 20 s, the card is worded **"Lean is still working"** instead ("… but Lean answered N s ago, so
    this is most likely a long-running command, not a freeze"), with the same buttons; it re-words itself if that
    changes while it is up (`status().stall.variant` `alive` or `stopped`, events `shown` and `reworded` carry it).
  * **Tests (main-loop probe, hardening lane).** `sim-gallery.mjs` run 13: a page without QED64 liveness with a saturated
    pool (hovers unanswered, no frame) stays alive via `main-loop` and the card says "Lean is still working"; main-loop
    probes answered only by QED64's JS layer do not count (wedged → restart); a frozen Lean side answers neither (restart).
    Run 12 now answers the hovers 0.65 s after a 0.6 s timeout, i.e. before the tick that checks it at 0.75 s, and requires
    0 on-time answers (the old tick-order classification fails it: scratch mutant B, `SIM-GALLERY FAIL 99 ok, 2 failed`);
    the 0.9 s margin is gone. UX C22 (3) also asserts that a main-loop probe went out with every hover and that the main
    loop answered them during the saturation, and on a pin without QED64 liveness that the session was settled via
    `main-loop`.
  * **Tests.** UX suite C21 freezes the checker deterministically (synthetic, not L7 evidence) and checks the
    automatic restart in the default mode and, in observe mode, the recorded wedge, the hang capture, the card,
    Keep waiting and Reset. C22 is the negative: a legitimately slow elaboration is not restarted. W1–W8 and C20
    assert the probe and the card are armed at their defaults and account for every relay restart.
    On a pin with QED64 liveness (C, B) C21 (a) checks the deferred restart (between 39 and 45 s after the click, QED64 rebooting
    nothing), and C22 also checks that QED64's own liveness takes no action during the 38 s silent `#eval` (no stall,
    no reboot; it is normally not even probed, because the editor's and InfoView's requests keep server frames
    flowing: longest gap 1,066 ms, `tests/ux/tools/qed64-liveness.mjs`). `scripts/sim-gallery.mjs` runs 7 and 8 model all of it without a browser, and run 9 models a page
    with QED64's own liveness: deferral, QED64's rescue / stall / `wedged` reboot observed with no gallery probe and no
    `relay.restart`, no probe during a QED64 stall, the fallback restart when QED64 never acts, and `deferred`;
    run 10 models the saturated pool (settled `alive` via `qed64-answered` and via `frame`, no restart, the card's two
    wordings). C21 (b) runs in a fresh browser, so it is not a second runtime boot in one renderer (QED64 L9).
* **`headerRefused`.** A notice, not an error. The page stays usable.
* **Timeouts.** A card with the last status: switch 330 s (DistLens's 300 s budget plus slack), page hook 120 s.
  **The first boot is progress-aware** (boot-fix lane, 2026-10-03; it fixes the last-mile lane's defect: at 10 Mbit/s
  the old fixed 360 s budget showed "This is taking too long" at 467 s during QED64's normal ~710 MB download and never
  cleared, although QED64 was ready at 577 s):
  * **Progress** is anything the gallery can see from the same origin: byte progress QED64 reports to its own status
    sink (`globalThis.qed64.ui.progress(label, {phase, loaded, total, unit})`, wrapped once per page like the bridge;
    the page's own sink still gets every call), counted per step at its high-water mark so a retry that re-sends the
    same bytes is not progress; a stage label not seen before on this page; a QED64 phase/relay/session/version not seen
    before; a page resource (`performance` entries) from a URL (query and hash stripped) not seen before in this boot.
    Since the final audit (2026-10-03) a page that re-fetches the same file (a retry loop, a cache-busting query) adds
    entries but no progress, so it cannot keep re-arming the stall window (`status().boot.resourceUrls`).
  * **The card** ("This is taking too long … no download or start-up progress for N s …") shows only after
    `BOOT_TIMEOUT_MS` (360 s) **and** `BOOT_STALL_MS` (240 s) without any progress: a true stall.
  * **The notice** (non-blocking, the notice bar): "Still downloading: <QED64's current step> — X of Y so far. …",
    with QED64's own step label and figures (prepared bytes, the numbers its boot card shows, not network bytes). It
    sits just below the QED64 page's own top bar (the gallery reads that bar's height; 44 px if it cannot), so it never
    covers the page's status pill with its download figures (final audit, 2026-10-03; before, it covered the pill). It
    appears from 360 s while progress continues, and already from `BOOT_NOTICE_MS` (120 s) once QED64's own boot
    overlay (`#boot`) is gone and bytes arrived within the last 30 s (the stock page removes its overlay 120 s after its
    editor opens, long before a slow download ends). It goes at ready (a notice it replaced comes back). The status
    line adds "· X of Y" while it waits.
  * **Pin E `33b0967` (QED64 #54; measured by the pin-e lane, 2026-10-04).** On E, QED64's boot overlay stays until
    ready and shows the step, bytes, rate and time left, so the 120 s early-notice path (which needs `#boot` gone) does
    not fire. The notice comes from `BOOT_TIMEOUT_MS` after the first-boot wait began; the wait begins when the page
    publishes `globalThis.qed64`. At 10 Mbit/s / 40 ms that was 107.3 s, so the notice appeared at 466.9 s, below
    QED64's top bar and beside its card, with no overlap. Ready came at 565.1 s, with the error card in 0 of 575 samples,
    visible progress in 563 of 564 samples, the longest unchanged progress 6.0 s (C: 19.0 s; E reports progress inside
    runtime chunks and pack parts, `5e94697`/`76be299`), the panel equal to its golden, and `RESULT PASS`, rc 0
    (`out/ux/pinE-throttle/explore/throttle-pe10.json`, screenshot `…/screens/throttle-pe10-0481s.png`). No gallery
    change was needed. The notice now repeats what QED64's card already shows; dropping it while `#boot` is visible would
    be a gallery change with its own gates and was not made.
  * **Late ready.** If the stall card was shown and QED64 later reaches `ready` on the same page document (with the
    example's text), the card closes and the boot finishes as usual: cursor, focus, panel (`status().boot.recovered`).
    Another selection, Try again, or a new page document drops that.
  * The same progress-aware wait is used for `?mem` boots and for a page reload the gallery adopts; the late-ready
    recovery covers the normal first boot and adopted reloads, not `?mem` (its two-session boot is not resumed). `?bootTimeout`, `?bootStall`,
    `?bootNotice` (seconds) override the timings for tests; `status().boot` reports what the wait saw.
  * **Evidence.** `scripts/sim-gallery.mjs` run 15 (slow progress: notice, no card, ready; a true stall with re-sent
    bytes ignored: card; late ready: card closed, cursor, switching works; defaults); a mutant that ignores progress
    fails 4 checks and one without the late path times out (`$W/logs/bootfix-sim-mutant-*.log`). Browser (fresh
    profile, chrome-headless-shell 151, link shaped by `tests/ux/tools/throttle-proxy.mjs`, measured by
    `tests/ux/tools/throttled-first-visit.mjs`, which now also records the gallery's notice and checks the panel):
    10 Mbit/s / 40 ms ready at 565.0 s, the error card in 0 of 575 samples, visible progress in 563 of 564 samples
    before ready (the notice from 231.5 s), panel at ChartKit's first cursor equal to its golden
    (`out/ux/bootfix-throttle/explore/throttle-p10b.json`); with `?bootTimeout=10&bootStall=3` at 50 Mbit/s the stall
    card came at 56 s and closed by itself at ready (120 s), panel equal (`throttle-stall50.json`). Post-audit fix lane
    (2026-10-03): sim run 15e (15 new page URLs re-arm the wait, no card; then 10 re-fetches of one URL, half with a
    cache-busting query, are no progress: the card, and a later ready still closes it) and two notice-placement checks;
    mutants fail them (every resource entry counted as progress: 2 FAIL; no placement: 1 FAIL;
    `$W/logs/postaudit-sim-mutant-*.log`). Browser on the resulting gallery: 10 Mbit/s ready at 565.0 s, error card in
    0 samples, notice from 231.5 s below QED64's top bar (`out/ux/postaudit-throttle/screens/throttle-pa10-0481s.png`),
    panel equal, `RESULT PASS` rc 0 (`out/ux/postaudit-throttle/explore/throttle-pa10.json`).

## Accessibility and keyboard

* **Rail.** A list of card buttons with a roving `tabindex`. Arrow keys, Home and End move between
  cards, and Enter or Space opens one. The open card has `aria-current="true"`, and its "Things to try"
  buttons each move the cursor to their line.
* **F6** moves between the rail and the editor. Monaco keeps Tab for indentation, so Tab alone cannot
  leave the editor. A capture-phase F6 listener on the page window brings focus back to the rail.
* **Status line.** Plain words for a visitor: which example, whether Lean is ready or still checking, and how long the
  last step took ("HasseView is ready · opened in 1.4 s", "DistLens (edited): Lean is checking…", "Starting Lean in
  your browser… 5.2 s"). The technical detail it used to print (QED64's own phase and relay, header mode, session,
  `?mem`, overlay, the last operation) is the line's tooltip (`title`) and `__showcase.status().statusLine.detail`
  (`{text, detail}`; `sim-gallery.mjs` checks both, and that the visible text has none of the internals). Cards have no
  "phase" badge (it named the build phase of the widget, which meant nothing to a visitor); before the snapshot
  preflight a card's chip shows "…", then "available", "not in <overlay>", "loading…", "live" or "edited". The rail
  footer reads "QED64 <pin> · Lean 4.34.0" and "snapshot <overlay>" (runtime and region imports in their tooltips).
  Cursor hints say "draws a diagram" instead of SVG element counts; the counts stay in `expectPanel.svgTagCounts`,
  which the tests check.
* **Announcements.** The status line updates every 250 ms and is `aria-live="off"`. Phase changes are
  announced through a separate polite live region.
* **The veil leaves the accessibility tree once hidden (hardening lane).** The stage veil ("Loading the gallery…",
  "Checking the widgets overlay…") used to fade to `opacity: 0` and stay in the accessibility tree, so a screen reader
  could read a stale "Loading…" over the ready editor. Hidden, it now gets `aria-hidden="true"` and `inert`, and the CSS
  turns it `visibility: hidden` once the 0.3 s fade is over; `showVeil` removes all three. UX C17 checks this in the
  browser (computed `visibility: hidden`, nothing of it in `ariaSnapshot()`), plus the forward Tab order from the top of
  the gallery: skip link, Reset, Copy, the open card (the only card in the tab sequence: roving tabindex), its "Things to
  try" (folded to 4, then "Show all"), the kept-buffer controls when a buffer is kept, then the QED64 editor; every stop
  visible, named, never hidden or veiled. No axe
  build is in `node_modules`, so these are DOM assertions.
* **Other labels.** There is a skip link to the editor. The iframe has a `title`, the toolbar is a
  `role=toolbar` with a label, and the error card is `role=alert`.
* **Narrow screens (≤ 720 px, including 390 px).** The rail collapses to a labelled `<select>`, with
  the blurb and a "Things to try" disclosure, and the page's editor and InfoView are stacked
  (`?stack`).

## Test API (`window.__showcase`, for Playwright)

`__showcase.version` is 9 in both modes (9: the QED64 embedding contract v1: `status().mode` `'v1'`/`'legacy'` and `modeSource` (`'pin.json'`, or `'served'` when the server serves another pin's release than pin.json describes and the gallery followed that release's `/qed64-build.json`), `status().api` `{present, revision, embed, via, capabilities, missing, pinRevision, servedRevision, docs, adopted, adoptSet, events, deaths}`, `status().document`, `bridge.stoodDown` / `bridge.capabilityMismatch` (`repair` `'late'` or `'unavailable'`), `liveness.probe` (`'active'`, `'stood-down'`, `'unavailable'`), `stall.source` / `boot.source` / `boot.apiBootEvents`, `seed.action` `'embed'`, `offer()` and `acceptOffer()` (null / false in legacy mode); on a legacy pin these fields are present with their legacy values (`mode 'legacy'`, `api.present false`, `liveness.probe 'active'`, `stall.source 'relay-tap'`, `boot.source 'ui-tap'`); 8: the browser capability check `status().caps` and phase `unsupported`; the main-loop probe `status().liveness.mainLoop`, `aliveVia['main-loop']`, events `main-answered` / `main-synthetic`, `probe.main`; late answers by elapsed time with `ms`; 7: only frames from Lean are proof of life: `status().liveness.syntheticFrames`, `syntheticReplies`, event `synthetic-reply`; 6: proof of life besides the hover: `status().liveness` `frames`, `lastFrameAgoMs`, `alive`, `aliveVia`, `qed64.lastAnsweredAgoMs`, event `alive`; the card's wording, `status().stall.variant` and the `reworded` event; 5: `status().liveness.qed64` and the `qed64-*` events, `probeDeferMs`, `deferring`, `effectiveProbeAfterMs`, `deferred`, action `deferred`, `status().qed64.rebootReason`: the deferral to QED64's own liveness; 4: `liveness(mode)` and `status().liveness`, the L7 liveness probe; 3: `restoreSaved(i)` opens the newest kept buffer by default; `status().saved` lists the entries). The contract is frozen in `tests/ux/selectors.json` `showcaseApi` and checked by `check-gallery.mjs` 8b.

| Call | Returns |
|---|---|
| `select(pkg)` | A Promise that resolves with `status()` once the example is `ready` (or `refused`) with the cursor set. It rejects on failure or when a newer selection supersedes it (`code: 'SUPERSEDED'`). |
| `reset()` | Reset example through the driver (setValue even on identical text); resolves like `select`. |
| `restoreSaved(i = 0)` | Puts kept buffer `i` in the editor (`lib.js` `savedEntries`: the history newest first, then the first one ever saved; 0 = newest); resolves `true` if it did. |
| `status()` | `{phase, current, shown, overlay, requestedOverlay, fellBack, preflight:{ok, attempts, availability, regionImports}, booted, everReady, bootMs, lastSwitchMs, op, statusLine:{text, detail} (the visible status line and its technical tooltip; docs lane), error, notice, seed:{saved, action, error}, edited, custom, mode, modeSource, api:{…}, document:{…}, caps:{ok, hard, soft, missing, lacks, deviceMemory, checks, override}, saved:{present, history, entries, exampleEdit}, mem, bridge:{installed, installs, late}, cursor, qed64:{phase, version, header, session, relay, rebootReason, lastDeath, collision}, selections:[{token, id, source, outcome}], stall:{thresholdMs, active, variant, idleMs, shown, restarts, progressMsgs, tapped, events}, liveness:{…}}`. `selections` is how each of the last 20 selections settled (`ok`, `SUPERSEDED` or an error code), so a test can drive the real cards and still see supersession (C4). `stall` is the watchdog (see Errors). |
| `bridgeStats()` | A copy of the page window's `__showcaseBridge` (`{stripped, applied, shown, inserted, passed, errors, ws:{fetched, cached, coalesced, released, tapped}}`), or null (always null on a v1 pin: the bridge stands down). |
| `offer()` / `acceptOffer()` | V1: `api.status().offer` (`{kind:'exactImports', label}` or null) and `api.acceptOffer()` (true when something was offered); null / false on a legacy pin. |
| `currentText()` | The editor model's text, or null. |
| `examples()` | `[{id, title, module, phase, firstCursor, textSha256}]` |
| `liveness(mode?)` | The L7 liveness probe. With `'auto'`, `'observe'` or `'off'` it switches the mode (observe: detect and record, never restart). Returns `status().liveness`: `{mode, probeAfterMs, probeTimeoutMs, restartGapMs, misses, sent, answered, missed, late, wedged, wedgedActive, restarts, rateLimited, restartFailed, outstanding, lastAnswerMs, maxAnswerMs, unavailable, lateAnswers, frames, lastFrameAgoMs, alive, aliveVia, mainLoop:{method, sent, answered, synthetic, outstanding, lastAnsweredAgoMs, lastMs, maxMs}, probeDeferMs, deferring, effectiveProbeAfterMs, deferred, qed64:{builtIn, detectedAt, session, counters, totals, lastAnsweredAgoMs, wedgedReboots, rebooting, lastReboot}, events}`; `events` are `probe` (with `main`, the main-loop probe's id), `answered`, `alive` (with `via`: `frame`, `late-answer`, `qed64-answered` or `main-loop`), `missed`, `late` (with `ms` and `proofOfLife`), `main-answered`, `main-synthetic`, `wedged` (with `action` `relay.restart`, `observed`, `rate-limited`, `restart-failed` or `deferred`), `resumed`, `cleared`, `mode` and QED64's own `qed64-detected`, `qed64-rescue`, `qed64-stall`, `qed64-resumed`, `qed64-wedged`, `qed64-rebooted`. |

The gallery's `phase` is one of `starting`, `preflight`, `booting`, `switching`, `ready`, `refused`,
`halted`, `error` or `unsupported` (the capability card). The frozen contract (this table, every gallery
selector, the InfoView selectors the bring-up used, and the console allowlist) is
`tests/ux/selectors.json` (`gallery`, `showcaseApi`, `infoview`, `consoleAllowlist`);
`check-gallery.mjs` section 8b checks it against `index.html` and `gallery.js`.

## Static validation

```
node scripts/build-gallery.mjs --check     # examples.json / pin.json up to date (deterministic output)
node scripts/check-gallery.mjs [--live]    # the full static gate; --live starts serve.mjs on :5199 (Node only)
node scripts/sim-gallery.mjs               # gallery.js against a fake DOM + modelled QED64 page (also run by the gate)
```

`check-gallery.mjs` runs these checks:

* `node --check` on every JS file.
* Freshness of the generated files.
* `examples.json` against the specs:
  * all eight examples are present;
  * each text is byte-equal to its `.lean` file;
  * header, title and blurb match;
  * the first cursor equals `cursors[0]` and sits on its command;
  * every hint lands on a cursor or selection line.
* `pin.json` against the lock.
* Section 8b: every gallery id/class in `tests/ux/selectors.json` exists; `window.__showcase` implements
  the `showcaseApi` contract; all eight `thumbs/<pkg>.png` exist, are 480 px wide, ≤ 60 KB, and match the
  size and sha256 recorded in `examples.json`; every cursor hint has a position-bound `expectPanel`; every
  select hint has a golden `expectSelectPanel` whose `appear` texts are the only ones the card quotes; the
  hover hint carries the golden popup text and states it; every quoted card claim is checked by `hints.mjs`,
  whole (no `…`) and not a single generic spec word; the InfoView hover/selection contract is in
  `selectors.json`; every example whose first panel draws svg has a letterboxed whole-drawing thumbnail
  (`thumbs/thumbs.json` mode `letterbox`, 480×220, `thumb.fit` `contain`, and the `gallery.css` rule).
* Section 7 (`lib.js`): each `parseHash` case is its own line run inside `okTry`, so a reverted fix
  (`decodeURIComponent` throwing again) is reported as named `FAIL parseHash: malformed escape #% … — threw
  URIError: URI malformed` lines and the `CHECK-GALLERY FAIL` summary, not as a crash of the gate (audit 5 minor;
  scratch copy with the try/catch removed: `CHECK-GALLERY FAIL 115 ok, 3 failed`, the third being sim run 6).
* Section 8c: unit tests of the console classifier (`tests/ux/bringup/console.mjs`) against
  `selectors.json` `consoleAllowlist`: a normal run passes; two `unsupported` in one page load, an unknown
  page error, a non-empty or misplaced console.error, a second esms warning per InfoView, `unsupported` at
  `$tryShowTextDocument`, the double-reply warning, "Outdated RPC session" outside its scenario and a crash
  each fail; and the `pairWith` rule: an empty console.error without tap reports, two with one reply, one whose
  only reply is 5 s before / 2 s after it or has code -32603 each fail, a reply 0.3 s after passes.

The current result is whatever `scripts/showcase.sh gallery` prints. History: boot-fix lane (2026-10-03, gallery
`31f6d8d9…`, `work/logs/bootfix-gallery.log`): `CHECK-GALLERY OK 128 ok, 0 failed`, `SIM-GALLERY OK 109 ok, 0 failed`
(new: run 15, the progress-aware first boot; check-gallery 5 knows QED64's `#boot` id). Then the closure lane
(2026-10-03, same gallery, `work/logs/closure-gallery-end.log`) got the same counts after one test-only change.
`sim-gallery.mjs` runs `gallery.js` on real timers, and run 15a had sampled the status line once per 100 ms progress
call, while the gallery renders that line on its 250 ms tick. A 200 ms event-loop stall on a loaded host therefore failed
it (`108 ok, 1 failed`, 4 of 4 with an injected stall). It now waits up to 350 ms for the tick, with the same asserted
text (`out/ux/closure/RESULTS.md` (5)). Before the boot-fix lane, the final docs lane
re-ran the gate unchanged on 2026-10-03 (`work/logs/finaldocs-gallery.log`: `CHECK-GALLERY OK 128 ok, 0 failed`,
`SIM-GALLERY OK 101 ok, 0 failed`). Set by the v2mit lane (2026-10-02, gallery `921b0b6a…`: only the memory wording changed; `work/logs/v2mit-showcase-gallery.log`,
`v2mit-check-gallery-final.log`, `v2mit-sim-gallery-final.log`): `CHECK-GALLERY OK 128 ok, 0 failed`; `SIM-GALLERY OK 101
ok`; check-gallery 7 now compares `BROWSER_NEED` with the new sentence exactly, sim run 14 and UX C24 the card prefix.
Before it (hardening lane, 2026-10-02, gallery `2081098d…`; re-run unchanged by the final docs lane, `work/logs/docsfinal-gallery.log`,
which also prints `UX CURRENT … final-C-full2; headed sign-off final-C-headed1`): `CHECK-GALLERY OK 128 ok, 0 failed`; `SIM-GALLERY OK 101 ok`
(new: run 13 the main-loop probe, run 14 the capability card, the veil's aria checks in runs 1 and 2, run 12 by elapsed
time; check-gallery 6 the veil CSS/JS, 7 `checkCapabilities` and the probe bytes; `work/logs/harden-gallery-gate4.log`).
Docs lane (gallery `2f95d07c…`): `CHECK-GALLERY OK 123 ok, 0 failed`; `SIM-GALLERY OK 86 ok`
(runs 7–12 model the liveness probe, the deferral, proof of life, frames QED64's JS layer synthesizes, and late hover
answers; the status-line check now asserts plain visible text plus the technical tooltip, and a mutant printing the old
line fails it; `work/logs/docs-gallery-gate*.log`). Run 12's late hovers came 0.7 s after a 0.5 s timeout until the docs
lane, when one gate run failed with `5 probes, 2 missed, 2 late answers, alive 0x, wedged 0` (`docs-gallery-gate2.log`):
misses were reset without a wedge or a late-answer settle, i.e. some answers counted as on time. The gallery checks the
timeout on its 250 ms monitor tick and counts any answer that arrives before that check as on time, so an event loop
delayed by about 200 ms (host load) turns a 0.7 s answer into an on-time one. The late answer must land after the
first probe's timeout check (0.5–0.75 s) and before the second's (about 1.0–1.5 s); run 12 now answers at 0.9 s, the
middle of that window. Not reproduced in 11 reruns at 0.7 s (so the cause is inferred, not shown); at 0.9 s 4 reruns
and the final gate passed. Close-out 3 (gallery `92027286…`): `CHECK-GALLERY OK 123 ok`, `SIM-GALLERY OK 84 ok`. Earlier
(close-out, gallery `c8492b70…`): `--live`: `CHECK-GALLERY OK 133 ok, 0 failed` (not re-run). New since audit 5:
thumbnail wiring and cursor-label checks (8b), the `livenessObserved` and `qed64WedgedReboot` classifier tests (8c).
* The bridge sandbox also checks D3: three concurrent `getWidgetSource` for one hash → one forwarded
  (clean), two held and answered from the first reply; a cached hash is answered locally; an error reply
  releases the held ones.
* HTML:
  * ids are unique;
  * every id that `gallery.js` uses exists;
  * `label` and `aria-*` targets resolve;
  * the template classes exist;
  * local files exist;
  * tags balance;
  * the page has `lang`, a viewport meta and an iframe title, and every button has a `type`.
* CSS tokens: all are defined, the dark scheme redefines every colour token, and `[hidden]` wins over
  component display rules.
* `lib.js` unit tests:
  * the preflight rejects an unpaired runtime, a length mismatch, an HTML fallback, gzip encoding, a
    404 index or snapz, a foreign runtime manifest, and a missing `mathlib` entry;
  * overlay fallback works, and an explicit overlay does not fall back.
* The bridge in a `vm` sandbox: install idempotence, D1 strip and re-dispatch, D2 `applyEdit`, and
  pass-through.
* `sim-gallery.mjs`. This runs the **real** `gallery.js` against a DOM parsed from `index.html` and a
  fake QED64 page. The fake page models what the controller relies on:
  * when the navigation commits;
  * the `loading` → module-script → `complete` order;
  * the first session being created before `globalThis.qed64` is assigned;
  * `relay.lastText`, `makeSession`, `restart`, re-arming a halted relay on `didChange`;
  * versioned status, covered and refused headers;
  * buffer persistence.

  It checks these behaviours:
  * the preflight runs before navigation, and refusals mean no navigation;
  * the user buffer is saved, and the seed is in place before navigation;
  * the bridge goes in at `readyState: 'loading'` before `qed64` exists, including after an external
    reload;
  * the first cursor is placed and focused;
  * switching works, and a storm of 6 selections settles on the last (5 `SUPERSEDED`);
  * a refused header gives a notice;
  * Reset works on identical text and on a halted relay;
  * hint buttons, roving arrow keys, Copy, `hashchange`, and adopting an external reload all work;
  * Retry after a preflight or boot failure first retires the old page through `about:blank`;
  * on a narrow screen the stack style is applied and the select bar switches examples;
  * `?mem=3`: the light first session is 256 MiB `[init]`; the wrapped restart is 3 GiB
    `[init,mathlib]`, and so is the session re-armed after a halt.

  It is a *model* of QED64, so the open questions below are what the browser must confirm.
* With `--live`, the real preflight against the served overlays, plus MIME and COOP/COEP checks on the
  gallery files.

`examples.json` is generated output. **Rerun `build-gallery.mjs` after editing `lean/examples`.**
The gate fails (STALE) until you do.

## The UX suite (`tests/ux/`, `npm run test:ux`)

The exhaustive Playwright suite (BUILD-PLAN §8 with docs/TEST-PLAN-DELTAS.md) runs against this gallery and the stock
page. It covers W1–W8: every declared cursor's full DOM signature equals the golden, plus the declared clicks,
selections, hover and Monaco code actions. It also covers C20 (all 135 rendered links clicked in the browser) and C1–C19.
Results, metrics, root causes and QED64 limitations are in **docs/UX-RESULTS.md**. Two gallery defects it found are fixed:

* The skip link used to rewrite the `#<pkg>` deep link and raise "There is no example called “qed64-frame”" (C17). It
  now focuses Monaco and leaves the URL alone (`#skip-link` click handler in `gallery.js`).
* There was no page icon, so a headed browser requested `/favicon.ico` and got a 404 (C19). `favicon.svg` fixes this.
* (final-gate lane) The whole suite can run headed: `UX_HEADED_ALL=1` (project `headed`, own visual baselines in
  `tests/ux/__screenshots__/headed/`, recorded as a HEADED SIGN-OFF, never a verdict). The stock QED64 page has no icon
  either (QED64 N3), so headed stock-page loads log one `/favicon.ico` 404, which only the headed run allows.

After the UX audit, four more gallery changes:

* **Stall watchdog** for QED64 L7 (see Errors; C21; the audit's C20 run hung on a link click with no card at all).
* **Card claims are only what the panel renders by default.** `scripts/build-gallery.mjs` reads the frozen Html of
  every panel (`lean/expect/html[/w8]/<pkg>.json`) and quotes, and picks `expectPanel.texts` from, only leaves that
  are not inside a closed `<details>` (outside its `<summary>`) or `display:none`; a spec text that is hidden fails the
  build. Three cards changed: SimpLens L32 no longer quotes “h lands at:”, Expr X-Ray L21 no longer quotes
  “HAdd ℕ ℕ ℕ”, and L40 no longer quotes “Decidable (n = n)” (all inside folds the user must expand). The W tests
  assert every quoted text is in the panel's `innerText`, and the bring-up's `checkPanel` reads rendered text only.
* **Compact card** over QED64's own failed boot card (C11).
* **Selection log** in `status().selections` (C4 drives real card clicks).

## Browser bring-up (`tests/ux/bringup/`, real Chrome)

Playwright 1.62.1, chromium-headless-shell rev 1234, `--enable-features=SharedArrayBuffer`, server
`scripts/serve.mjs` on :5190, default overlay `widgets8`. Every run goes through
`scripts/with-browser-lock.sh <lane> <cmd>`: it takes the host-wide lock (`~/.cache/host-browser-lock/browser.lock`,
or `$BROWSER_LOCK_DIR/browser.lock`; until 2026-10-04 it was `out/.browser.lock` inside this project) atomically
(`noclobber`, owner pid, removal on exit; waiters are served first come, first served through a ticket queue,
`tests/ux/bringup/lockfifo.sh`; a stale lock — dead owner pid — is removed only under a takeover mutex, `mkdir
<lock>.takeover`, after re-reading it and finding the same dead owner line, so two waiters can never
both get in: `tests/ux/bringup/lockrace.sh`, 8 racers on a planted stale lock, `LOCKRACE OK: 8/8 ran, 0 overlapping
critical sections` ×3, while the previous plain `rm -f` takeover overlapped once in 3 tries,
`work/logs/bringup-lockrace*.log`), then refuses to start below 6 GiB free+inactive or with a stray
`chrome-headless-shell`. Outputs in `out/ux/bringup/`, logs in `work/logs/bringup-*.log`.

| script | what it proves | final result |
|---|---|---|
| `widgets.mjs --dir after --thumbs` | each card selected in turn (one cold boot); its first-cursor panel passes BOTH the position-bound golden check (below; svg counts compared over the whole draw-tag set, a missing kind = 0) AND the frozen `cursors[0].expect`, including `panelTitle` (the spec's "HTML Display", or none = an `mk_rpc_widget%` panel in the info block), texts, svg tag counts and link texts, all inside that panel; no "Unrecognised error"; console classified against the allowlist (exit 1 otherwise); full-page 1440×900 shots `after/gallery-<pkg>.png`, panel crops `after/panel-<pkg>.png`, thumbnails `gallery/thumbs/<pkg>.png` | latest (audit 5): `--dir after-audit5 --thumbs` (`work/logs/audit5-widgets-thumbs2.log`), `--dir after-audit5b` (screens with the new thumbnails, `audit5-widgets-after-audit5b.log`), `--dir rss-audit5c`: each `WIDGETS OK 8/8` (titles: 5× "HTML Display", 3× rpc block), boot 13.0–13.4 s cold, switches 0.4–2.2 s, bridge `stripped 3`, `unrecognised false` ×8, `CONSOLE OK` (1 `unsupported`, 1 esms warning, 6–7 empty errors, each paired with its own -32800 reply: `paired {n: 6, replies: 6}`; 1 QED64 load, 1 InfoView load) |
| `hints.mjs` | every "Things to try" button of every card, clicked in the real UI. **cursor**: the InfoView's info block must be the one for the hint's own position (summary `<file>.lean:<line>:<char>`), and inside it the golden panel `expectPanel` (`examples.json`, from `lean/expect/w8/<pkg>.json`: the "HTML Display" panel or the rpc block, EXACT svg tag counts over the whole draw-tag set, texts that occur in no other cursor's panel of that example) plus the spec's texts; **click**: the link exists and changes the document by exactly the frozen edit, QED64 re-checks with 0 errors / 0 warnings, the chip says "edited", Reset restores; **select** (`expectSelectPanel`): BEFORE, the unselected golden panel of that position has rendered, 0 subterms are selected and none of the `appear` texts is in the block; shift-click the subterm(s) / hypothesis; AFTER, ≥ 1 `[class*=highlight-selected]` per pick and every claimed text in the block (whitespace-insensitive leaf runs); then the picks are shift-clicked off and the count must be 0 again; **hover** (`expectHover`): BEFORE, no `.tooltip .tooltip-code-content` popup; hover the innermost element reading `tagText` inside the panel's code element reading `codeText` (of THIS position's panel); AFTER, a popup whose own text is exactly `n : ℕ`, gone again when the mouse leaves; console classified (exit 1 on anything outside the allowlist) | `HINTS OK 71/71` (46 cursor, 21 click incl. 6 Try-this and the GraphScope edge found by `title`, 3 select: before `selectedCount 0`, after 1 / 2 / 1, cleared; 1 hover: popups before `[]`, after `["n : ℕ"]`, closed); click-to-settled 0.64–2.63 s; `CONSOLE OK` (1 `unsupported`, 1 esms warning, 33 empty errors, `paired {n: 33, replies: 33}`) (audit 5 re-run with the new hint copy: `work/logs/audit5-hints.log`, `hints.json`) |
| `mutants.sh` | the checks are not vacuous. Cursor: a copy of the gallery with ONE hinted command replaced is served on :5192 (`serve.mjs GALLERY_DIR`), and exactly that hint must fail. M1 tree-scope L41 `#tree_evolve` → `#check (41 : Nat)`, M2 hasse-view L21 `#hasse (Fin 4)` → `#check (Fin 4)` (rpc panel), M3 graph-scope L36 `cycleGraph 6` → `cycleGraph 5` (a panel renders, but not the claimed one). Select / hover (audit 2), each must fail exactly as listed: M4 the hover retargeted (in the copy's `examples.json`, which `hints.mjs` then reads too) to the panel's plain `<code>simp only [add_zero, zero_add]</code>`, which has no popup; M5 `--fault no-hover` (everything but the hover); M6 `--fault no-select` (everything but the shift-clicks) on all 3 select hints; M7 expr-xray select #2 with only its first pick | `MUTANTS OK` (`work/logs/audit3-mutants-final.log`): M1 "info block :41:0 has no “HTML Display” panel"; M2 svg `{svg: want 1 got 0, rect: want 4 got 0, …}` and both texts missing; M3 svg `{g, line, circle, text: want 6 got 5}`, "bipartite: yes (parts: {0, 2, 4} / {1, 3, 5})" missing; M4 and M5 "no popup “n : ℕ” after the hover (popups: [])"; M6 all three fail with their `appear` texts missing; M7 "missing [mismatches (1, ranked), instance argument #3 of ite differs]" while select #1 passes; every other hint of those runs passes |
| `questions.mjs` | the open questions below. EVERY question (q2, q3, q4, q9–q14) and the malformed-hash case has an explicit `ok` predicate over exactly the fields the answer below cites, printed as `qN OK` or `qN FAIL (<failing parts>)`; the run passes only if every wanted question exists with `ok === true` (a question not reached fails). Console classified, with the breaker / relay-restart entries allowed because q3 runs; exit 1 on an error, a crash, a console failure or any failed question | `malformedHash OK`, `q2 OK` … `q14 OK`, `QUESTIONS OK`, `CONSOLE OK` (3 QED64 loads, 3 InfoView loads: 3 `unsupported`, 3 esms warnings, 7 empty errors each paired with its own -32800 reply, 4 "Outdated RPC session", 9+5 checker-halted) (`work/logs/audit5-questions.log`, `questions.json`). Mutant E (a gallery copy whose Reset handler returns at once, `:5193`): `q3 FAIL (identicalFinished, identicalBumped, afterResetReady, newSession, versionIncreased, relayServing, cardGone, freshPanelBack)`, `QUESTIONS FAIL`, exit 1 (`work/logs/audit5-mutE-fixed.log`, `questions-q3-mutE.json`) |
| `narrow.mjs --dir after` | 390×844 (mobile emulation) with stacking, with `?stack=0`, and dark mode at 1440 and 390 | no horizontal page scroll (`scrollWidth 390`), see 5 and 6 |
| `memprobe.mjs` | heap telemetry + RSS + pthread pool per example, `?mem`, crash reboot | see "Memory knob" and L2 |
| `stockprobe.mjs`, `rpctrace.mjs` | the stock page WITHOUT the gallery (top-level, bridge by init script or none), to attribute L2 | see L2 |
| `consoleprobe.mjs`, `emptyerr.mjs` | console census per bridge install mode, with stacks; the empty console.error's trigger | see "Console messages" |

**Correction (bring-up audit 2).** The second `HINTS OK 71/71` still counted 3 of its 4 select/hover hints
without checking them. The hover check looked for `: ℕ` anywhere in the InfoView, and the goal `⊢ ∀ (n : ℕ), …`
already shows that, so it passed with no hover. Two expr-xray select hints claimed “ite” and “Decidable”, and both
are in the X-Ray of the whole goal before anything is selected (`out/ux/audit2/vacuity.json`: `passesWithoutSelection
true`, `selectedCount 0`; screenshot `after-audit3/before-vacuity-select-expr-xray-1.png`). Only the
interval-inspector selection was real. Now:

* `build-gallery.mjs` derives each select expectation from the golden of that exact selection. It fails the build
  when a claimed text is missing from it, or when every claimed text is already in the no-selection golden at that
  position. That is how it rejected the old “ite” / “Decidable” specs.
* `lean/examples/expr-xray.json` now claims what only a selection produces. One pick gives “clean (explicit only)
  app if n = n then 1 else 0 : ℕ”: the X-Ray's root row is the selected subterm, not the goal. Two picks give
  “mismatches (1, ranked)” and “instance argument #3 of ite differs”: the two occurrences differ only in their
  Decidable instance. Both are verified against `lean/expect/w8/expr-xray.json` `selections[]`. `lsp-golden.mjs`
  matches such leaf runs the same way.
* `hints.mjs` checks before and after each hint, and clears the selection afterwards (see the table).
* `mutants.sh` M4–M7 show that each of these checks fails when the hover or selection is missing or wrong.

Also from this audit:

* the console allowlist is now enforced (see "Console messages");
* svg counts are compared over every draw tag;
* cards no longer quote single generic words or truncated texts. A cursor card quotes at most two whole texts, all
  checked: strong spec texts first, then golden texts unique to that position, with a type leaf's leading `: `
  dropped. check-gallery 8b enforces this.

**Correction (bring-up audit).** The first `HINTS OK 71/71` overstated what was checked: 14 of the 46 cursor
hints quoted no text, and for those `hints.mjs` only required some `svg, table, details summary` anywhere in the
InfoView, which the always-present `Probe.lean:L:C` and "All Messages" summaries satisfy; a cursor check also never
confirmed that the InfoView had moved to the hint's line. The audit's mutant (`#tree_evolve` replaced by `#check`)
passed. Now `scripts/build-gallery.mjs` gives EVERY cursor hint an `expectPanel` taken from the frozen golden of
that exact cursor (it fails the build if the golden is missing, stale — `exampleSha256` ≠ the example — or has no
position-specific text or svg shape), the card text states that concrete claim (e.g. tree-scope L41: "An “HTML
Display” panel draws 6 SVGs (16 rect, 10 line, 40 text) and shows “step 0: init”, “tree: 1 nodes, depth 1”"), the
check is bound to the hint's own info block (`lib.mjs` `checkPanel`), `check-gallery.mjs` 8b requires an
`expectPanel` on all 46 cursor hints, and `mutants.sh` shows the mutant, an rpc mutant and a wrong-panel mutant
are each caught. The 71/71 above is the re-run under these checks.

Before/after screenshots: `out/ux/bringup/before/` (first pass, before the UI fixes) and
`out/ux/bringup/after/`. UI fixes the screenshots drove: the 390 px layout was 531 px wide (body grid
column grew to the topbar's max-content, and the status text had no `min-width: 0`; `work/logs/bringup-narrow1.log`
`"scrollW":531`), now 390; compact "Reset"/"Copy" actions under 480 px (full `aria-label`s kept); hint copy
rewritten so the label and the detail no longer repeat each other and every claim is checkable; the page's
own example menu hidden; a stale notice no longer overlaps the error card; the halted card got a "Reset
example" action; the status line no longer prints "halted/halted"; the open card scrolls into view;
card thumbnails.
Bring-up audit 5: click hints name what is clicked when the link text alone does not say it (GraphScope: "Click
vertex 0 in the drawing", "Click the edge 0–1 in the drawing"; derived from the edit, `….degree (v)` /
`….Adj (a) (b)`), and the detail shows the WHOLE edit (no mid-term "…": HasseView's
`example : ∀ x : (Finset (Fin 3)), x ≤ ({0, 1, 2} : (Finset (Fin 3))) := by decide`, up to dist-lens's 151 chars;
`.hint-detail` wraps with `overflow-wrap: anywhere`); a long link text in a label is shortened only at term
boundaries (`build-gallery.mjs` `abbrevTerm`: drop the proof after ` := `, then elide the longest innermost
bracket group), e.g. "Click “example : ((PMF.ofFintype ![2/3, 1/3] (…)).bind weather) 0 = 2/3 := …” in the panel".
Bring-up audit r2 (close-out): cursor hint labels were the spec's truncated command prefix, cut mid-expression with no
"…" and open brackets ("Line 24 · #interval_inspect ((3:ℝ) ∈", "Line 24 · simp_lens [Nat.add_zero, Nat.zero_add"). They
are now the WHOLE command read from the example (`scripts/lib/term-labels.mjs` `commandAt`: the rest of the line, plus
continuation lines while a bracket is open or the next line is indented deeper), shortened only by the same
term-boundary `abbrevTerm` (a ` := ` proof is dropped only at bracket depth 0) to at most 64 characters: 38 of 46 are
whole ("Line 24 · #interval_inspect ((3:ℝ) ∈ Set.Icc 1 4)"), 8 are balanced elisions ending in "…" ("Line 24 ·
simp_lens […]", "Line 39 · #chart {…}"). `check-gallery.mjs` 8b checks every cursor label against `commandAt` (whole,
or "…" + balanced brackets and quotes) and every quoted click term for balance; the old labels fail it
(`CHECK-GALLERY FAIL 120 ok, 1 failed`, scratch copy). Card thumbnails are now also checked as WIRED: 8b requires
`thumb.src == thumbs/<pkg>.png` and `gallery.js` to assign `img.src = ex.thumb.src` (a copy that loads `.jpg` fails:
`CHECK-GALLERY FAIL 120 ok, 1 failed`), and `widgets.mjs` and UX test C1 require every `#card-<pkg> .card-thumb`,
scrolled into view (`loading="lazy"`), to be visible with `naturalWidth` 480.

## Resolved questions (evidence in `out/ux/bringup/`)

1. **Bridge timing.** `installs[0]` is `{reason: 'commit-poll', readyState: 'interactive', qed64Present:
   false, alreadyInstalled: false}` on every boot (`widgets-after.json`, `questions.json`, `mem3.json`),
   i.e. after parsing, before the page's deferred module script, never on a reused `about:blank` Window.
   `stripped > 0` (3 in `widgets-after.json`, 41 over the hints run) and no "Unrecognised error" in any
   `mk_rpc_widget%` panel (8/8 widgets, 71/71 hints). Why early matters: see the bridge section (late
   install = 3 page errors and broken panels).
2. **Focus.** After a selection the gallery's active element is `#qed64-frame`, the page's is Monaco's
   `textarea.inputarea`, `editor.hasTextFocus()` is true, and typed keys land in the document. The InfoView
   follows `setPosition` **without** focus or a click: with focus on a rail card, a programmatic
   `setPosition({lineNumber: 30})` switched the InfoView to `Probe.lean:30:0` and its panel
   (`questions.json` q2). No synthetic click is needed.
3. **Reset.** `setValue(sameText)` emits a didChange: version 5 → 6, same session, 221 ms. On a halted
   relay (breaker tripped by three deaths through the relay's own death path: `breakerTrips 1`, session s3) the
   card "The Lean checker stopped" appears, and Reset re-arms it: new session s4 ready in 7.8 s, document
   version 7 (> the last ready 6), card gone, and the first-cursor panel back 0.3 s later as a FRESH element
   (q3, `questions.json`). How "fresh" is proven (bring-up audit 5 major: the halted InfoView keeps its last
   render, so "panel text on screen" passed even when Reset did nothing): before Reset the stale panel element is
   tagged (`data-q3-stale`) and the cursor is moved off the widget line programmatically; the halted InfoView
   then shows `Probe.lean:1:0` "Error updating: … checker halted …" and no panel. After Reset the gallery puts the
   cursor back and the panel must pass the position-bound golden check (`checkPanel`, `:31:0`) on an UNTAGGED
   element. All of these are q3's `ok` predicate; mutant E fails eight of them.
4. **Text sync.** Real typing (`, 40` into `[10, 20, 30]`) keeps `relay.stats.rangedChanges` at 0 and
   `relay.lastText === model text` (lean4monaco sends full-text didChange); the panel shows the new 40; the
   card says "edited" and Reset clears it (q4). The `lastText` check stays.
5. **390×844.** The injected stack style gives `#split` `flex-direction: column`, editor 310 px over
   InfoView 311 px, Monaco re-laid out to the full 390 px width (`getLayoutInfo`), the page's `#bar` 35 px
   (no wrap), no horizontal scroll in the gallery or the page (`narrow-after.json`, `after/narrow-390*.png`).
   With `?stack=0` the panes are 214 + 176 px side by side and the InfoView scrolls sideways (340 > 175):
   auto-stacking stays the default. The narrow select switches examples; "Things to try" is a disclosure.
   The page's own floating controls (a keyboard button Monaco shows under touch emulation, "Restart File")
   overlay the panes; they are QED64's, left untouched.
6. **Dark mode — decision: acceptable as is.** Only the gallery chrome follows `prefers-color-scheme`
   (`body` `rgb(16, 18, 23)`); the QED64 page and its InfoView stay light (InfoView text `rgb(0, 0, 0)` on
   white) because the bundle hard-wires "Visual Studio Light". The widgets draw with that theme's
   `var(--vscode-…)` colours, so they are consistent with the editor beside them; a dark InfoView would need a
   QED64 change. The light page sits as a framed island in the dark shell (`after/dark-1440.png`,
   `after/dark-390.png`), which reads fine. C13's dark baselines therefore cover the gallery chrome only.
7. **`?mem` end to end.** Works: light s1 `[init]` 256 MiB, then s2 `[init, mathlib]` with
   `[mem] runtime-initialized: 3072 MiB`, telemetry 3221225472, `applied: true`; a crash reboot (s3) gets
   3 GiB again. Like-for-like cost (same profile, cold vs cold and warm vs warm): +4.4 s boot (10.6 → 15.0 s
   cold, 6.6 → 11.0 s warm) and no measurable RSS (+0.31 / +0.01 GiB). The earlier "+12 s, +2.9 GiB" compared
   a warm default run with a cold `?mem` run and is withdrawn. widgets8 does not need it: the heap stays at
   the 2147483648-byte commit in every default run (Memory knob table).
8. **Overlay `imports`.** `make-overlay.mjs` spreads the bake entry (`{ ...wg, name: 'mathlib' }`), so the
   imports survive: `widgets8/index.json` lists QED64.Essential and all eight packages, and in Chrome
   `preflight.availability` is `true` for all eight (`widgets-after.json`); the chips read "available".
9. **Clipboard.** With `clipboard-read/write` granted, "Copy for VS Code" shows "Copied ✓" and
   `navigator.clipboard.readText()` equals the example text. Without the grant the copy still succeeds
   (Chromium allows `writeText` on a user gesture); the grant is only needed to READ the clipboard back
   in a test (q9).
10. **F6.** From inside Monaco (focused by a click), F6 moves focus to the open rail card
    (`#card-tree-scope`), the document is unchanged (no keybinding fired), and F6 again returns to the
    editor (q10).
11. **The page's own `#examples` menu.** Choosing a stock example replaced the document behind the
    gallery (first line `inductive Tree (α : Type) where`). Decision: the gallery hides the menu by default
    (`#qed64-showcase-page` style; `?pagebar=full` keeps it) and detects any foreign replacement: the chip
    reads "edited" and Reset restores the example (q11).
12. **Switch storm.** 8 selections 250 ms apart: the first 7 reject `SUPERSEDED`, the last (dist-lens)
    resolves, its panel shows, no stale panel text, `workerDeaths 0`, no extra reboot, pool 24 (q12).
    Budgets: cold boot 14 s, warm 6–7 s, switches 0.4–2.2 s, the slowest click settle 2.8 s (dist-lens)
    — far inside 360 / 330 s.
13. **Saved buffer.** A pre-existing user buffer is saved under `qed64-showcase:saved` before seeding
    (`seed.action: 'saved'`); "Open my saved buffer" puts it back (`textIsOriginal: true`, QED64 ready).
    An existing saved value is never overwritten (later buffers go to the bounded history; sim run 6 and
    `planSave` unit tests). Over real reloads (q14, `questions-q13-q14.json`): an example edited in the gallery
    and persisted by the page comes back as `seed.action: 'example'`, lands in `qed64-showcase:edited-example`,
    and leaves saved/history untouched (history 0, chooser hidden); a second real user buffer goes to the history
    (`action: 'history'`); the chooser then lists "newest: theorem my_second_buffer …" and "first saved: theorem
    my_own_buffer …"; "Open" opens the newest, choosing the second entry opens the first one ever saved
    (`out/ux/bringup/q14-saved-chooser-rail.png`).
14. **Static previews.** Replaced by thumbnails cut from the real rendered panels (`thumbs/`, 480 px wide, ≤ 60 KB;
    how each was made: `thumbs/thumbs.json`). A panel that draws svg gets the WHOLE drawing — the union of every
    painted shape of all its svgs, padded 8 px — scaled to fit (never more than 1.5×) and letterboxed on white in
    a fixed 480×220 frame, shown with `object-fit: contain` (`examples.json` `thumb.fit`, `gallery.css`
    `[data-fit="contain"]`), so the folded (84 px) and open (132 px) cards both show all of it. (Bring-up audit 5
    minor: the old top crop, 480×300 shown with `object-fit: cover`, showed GraphScope's pentagon with only
    vertices 0, 4 and 1; `out/ux/bringup/after/gallery-graph-scope.png` vs `after-audit5/gallery-graph-scope.png`.)
    Panels without svg, and a drawing wider than the panel (interval-inspector's number line, which the InfoView
    clips itself), keep the top crop: from the topmost content, never above the bottom of the panel's own summary
    row, 480 px wide, at most 300 px, `object-fit: cover`. check-gallery 8b requires the letterbox for every
    example whose first panel draws svg (chart-kit, hasse-view, graph-scope, dist-lens).
15. **Malformed deep link.** `#%` no longer throws: the gallery boots ChartKit with the notice "There is no
    example called “%”; showing ChartKit instead." and no URIError page error.

## Console messages (the UX suite's allowlist)

Census with stacks (`consoleprobe.mjs`, `emptyerr.mjs`; `console-a.json`, `console-hasse.json`,
`emptyerr.json`). Machine-readable copy: `tests/ux/selectors.json` `consoleAllowlist`. Everything else
fails C14.

**Enforced, not just recorded (bring-up audit 2).** Before, the allowlist was only checked by hand: a bridge
mutant that threw 9 `Maximum call stack size exceeded.` page errors still let `interval-inspector` report ok.
Now `tests/ux/bringup/console.mjs` `classifyConsole` classifies every page error, `console.error` and
`console.warning` of a run (log/info/debug are not failures), and `widgets.mjs`, `hints.mjs` and
`questions.mjs` exit 1 on anything outside the list, on a `neverAllowed` substring, on a per-load limit
exceeded, or on a crash. Each run prints a `CONSOLE OK|FAIL counts … loads …` line. Loads are counted from the
browser: a QED64 page load is a document request of the QED64 frame (hash and history changes are not loads);
an InfoView load is a navigation to `about:srcdoc` two frames further down (QED64 page > `#infoview` iframe >
srcdoc webview). `questions.mjs` allows the `relayRestartOrReboot` and `crashBreakerTripped` entries only when
q3 (the breaker test) runs. Since bring-up audit 5 the empty NotificationService `console.error` is also paired
with its LSP `-32800` reply (`pairWith`; the bring-up runs install the UX suite's LSP tap through
`lib.mjs` `installTap`, and print `paired {"consoleError[0]": {n, replies}}`). `check-gallery.mjs` 8c unit-tests the classifier
(including: no reports → fail; two errors, one reply → fail; a reply 5 s before / 2 s after or with code -32603 → fail), and the recorded mutant-A run
(`widgets-audit2-mutA.json`) classifies as `CONSOLE FAIL` with 9 unexpected page errors.

| message | source | classification |
|---|---|---|
| pageerror `Error: unsupported` with `$onExtensionActivationError` in the stack | QED64 bundle (monaco-vscode-api reporting an extension activation error through an `unsupported` stub) | **allow, exactly 1 per page load.** Present with no bridge, with the init-script bridge, and in the gallery. |
| `console.error('')` from the QED64 main bundle (`"@qed64-main-bundle"` in `selectors.json`: `/assets/index-BvT6MV1R.js` on pin 5ac5d00, `index-CzXuAkOQ.js` on 1859b83, `index-Jv35CWTg.js` on 9fdf9b8) line 627 (0-based; `Xz.notify`) | monaco-vscode-api's NotificationService printing `showErrorMessage(e.message)`; `emptyerr.json`: it follows, by 1 ms, an LSP reply `{id: 2, error: {code: -32800, message: ''}}` (RequestCancelled) to `textDocument/codeAction` sent during boot; edits cancel later codeActions the same way | **allow**, only with empty text and that location, and only PAIRED: each one needs its own LSP `-32800` error reply seen by the LSP tap (`tests/ux/lib/lsp-tap.mjs`, shared by the UX suite and the bring-up runs) in the 3 s before it (or 0.5 s after). `selectors.json` `pairWith` encodes this and `console.mjs` enforces it fail-closed (no tap reports = unexplained), so an empty `console.error` from any other cause fails `widgets.mjs`, `hints.mjs`, `questions.mjs` and the UX suite even though the entry has no count limit (0 unpaired in every run since: widgets 6/6 paired, questions 7/7) |
| `console.warn('TODO: catch JSON.parse failure:  SyntaxError: Unexpected token \'e\', "esms,true,"…')` from `/infoview/webview.js` | the InfoView's message listener receiving es-module-shims' own non-JSON `esms,…` postMessage | **allow, 1 per InfoView load** |
| `console.error('Outdated RPC session')` (same `Xz.notify` site) | after a relay restart/reboot the InfoView's old RPC session is refused once per request | allow **only** in tests that restart or reboot (q3, `?mem`, crash) |
| pageerror and `console.error` `QED64: checker halted after repeated crashes; edit the file to restart it` | the relay answering requests while halted | allow **only** in the breaker test (and the UX suite's boot-failure tests C8, C9, C11, C12, whose boots halt after three deaths) |
| pageerror and `console.error` `QED64: the Lean checker died (bootFailed)`; `Failed to load resource: … 404 (Not Found)` | the relay's death path when a boot cannot load its snapshots (missing / unpaired / unreachable overlay); the missing file itself | allow **only** in the UX suite's `bootFailure` scenario (C8 missing overlay, C9 unpaired overlay, C11 lasting network cut, C12 unreachable overlay) |
| `console.error` `Error: ?snapshots=<dir>: Failed to fetch` or `Error: ?snapshots=<dir>: /<dir>/index.json: HTTP <status>` followed by its stack (the main bundle; matched on the first line only) | **v1 pins (F, G, H; seen in runs since g-full1b)**: a `?snapshots=` overlay index that is unreachable or missing is a named boot failure before Lean starts (EMBEDDING.md §4; `qed64-boot.ts` `fetchSnapshotIndexFor`), reported as `api.status().boot` and `console.error`ed once by `main()`'s catch (`frontend/src/main.ts:625-629`); it replaces the relay death lines above, which legacy pins print for the same fault | allow **only** in the `bootFailure` scenario (`bootFailure[4]`, added in `d791b20`); first seen in run g-full1b (C8 stock and C12 overlay-offline-stock), and since then exactly once in each of those two loads in every full run on H (all seven, `h-full1` … `h-headed2`); any other uncaught `main()` error fails |
| `console.error('Outdated RPC session')` (the main bundle, line0 627) with **no** session replaced | **pin G (5c327c2) only**, a QED64 defect (fixed in H `bf9d947`, which forwards the keep-alive without waiting for a slot; docs/UPSTREAM-REPORT-QED64.md K1): its edit coalescer's request cap (e4cffcc, `maxInFlightRequests` 6, EMBEDDING.md §7.8) makes the InfoView's `$/lean/rpc/keepAlive` wait behind waiting requests, so a silence over Lean's 30 s keep-alive window expires the RPC session and Lean answers the queued rpc calls `-32900` itself | allow **only** in C22's `rpcKeepAliveStarved` scenario, on the pins listed in `25-stall.spec.mjs` `KEEPALIVE_STARVED_PINS`, each line paired with its own Lean `-32900` reply (`qed64Kind` null, exact message; fail-closed without tap reports); C22 also requires each reply to end a phase silent for 30 s+, no relay-made `-32900`, and a reconnect (an `$/lean/rpc/connect` at or after the burst's first reply) plus the golden panel afterwards (seen in run g-full1b, C22: 9 lines). **H is strict**: `bf9d947` is not in `KEEPALIVE_STARVED_PINS`, so on H (and on every pin but `5c327c2`) one such line fails C22; strict C22 on H printed 0 (`h-c22-1`, and every full run on H). Never declared together with `relayRestartOrReboot`, whose unpaired entry for the same text would match first (`exclusiveScenarios`: such a verdict fails) |
| pageerror and `console.error` `QED64: restarting with exact imports` (the main bundle line 627) | QED64's `relay.restart()` answers every request still in flight with this hard-coded text (`lsp-relay.ts:127` `failInFlight`; -32603, rpc calls -32900), whatever the restart is for; lean4monaco logs each and leaves it unhandled. A stalled checker always has requests in flight, so the gallery's Restart Lean / Reset on one produces these | allow **only** in the UX suite's `stallRestart` scenario (C21; C20 and W1–W8 only when a real stall was recovered) |
| `console.warn` `[showcase] liveness: Lean answered none of 2 probes on s<N> v<N> (observe mode: not restarting)` (`/showcase/gallery.js`) | the gallery's own note when its liveness probe, in observe mode, declares a frozen checker wedged (one per wedge) | allow **only** in the UX suite's `livenessObserved` scenario (C21 (b); C20 and W1–W8 only when an observe-mode wedge was recorded, i.e. a hang hunt) |
| pageerror `Session disposed.` (stack through `….dispose (`) | QED64 N2 (every pin): the page's heap meter races `session.request('telemetry')` against 800 ms every 12 s with no rejection handler, so a session disposed while that request is pending (a death, reboot, restart or halt) leaves an unhandled rejection; seen once in 18 C12 stock runs (`multipin-C-full1`) | allow **only** in the scenarios in which a session is disposed (`bootFailure`, `crashBreakerTripped`, `relayRestartOrReboot`, `stallRestart`, `qed64WedgedReboot`), and only with that stack |
| pageerror and `console.error` `QED64: the Lean checker died (wedged)` (the main bundle) | QED64 9fdf9b8+'s own liveness declared a session wedged (an L7 occurrence it handles itself): its relay answers every request still in flight with this text (`lsp-relay.ts` `onDied` → `failInFlight`), logged at the same site as the restart replies | allow **only** in the UX suite's `qed64WedgedReboot` scenario (C20 and W1–W8, only when `status().liveness.qed64.wedgedReboots` > 0; never seen so far) |
| `console.warn` `[qed64] exact import failed: … serving the header from the preloaded library` | QED64's designed fallback after "Load exact imports" when the exact import cannot be compiled (`resident-session.ts:209-224`) | allow **only** in the UX suite's `exactImportsFallback` scenario (C16) |
| `console.error` `Failed to load resource: net::ERR_…` (aborted / truncated); `console.warn` `[qed64] raw prefetch error: network error — the checker will stream it instead` | Chromium reporting a resource the test cut on purpose; QED64's snapshot prefetcher falling back to streaming after a cut | allow **only** in the UX suite's `networkCut` scenario (C11 CHAOS cuts, C12 aborted routes) |
| `console.error` `QED64: the document changed before this request reached the checker` (the main bundle, line0 627, the same NotificationService site) | **pins F, G and H (v1) only**: QED64's edit coalescing (EMBEDDING.md §7.8, HARDENING #59) answers a semantic-tokens or completion request queued behind a full-text change that a newer change replaced with `ContentModified` (-32801, `error.data.qed64.kind` `'superseded'`); lean4monaco logs each such reply (typing with the suggest widget open prints one per superseding change) | **allow**, anchored to that exact text and site, and only PAIRED, like the `-32800` entry: each needs its own LSP `-32801` reply seen by the LSP tap in the 3 s before it (or 0.5 s after); fail-closed without tap reports; no count limit. Pins A–E print no such text, so the entry matches nothing there |
| `console.error` `QED64: the client cancelled this request before it reached the checker` (the main bundle, line0 627, the same NotificationService site) | **pin G (5c327c2) and later**: QED64's back-pressure (EMBEDDING.md §7.8, e4cffcc) answers a request still queued in its edit coalescer whose `$/cancelRequest` arrives with RequestCancelled (`-32800`, `error.data.qed64.kind` `'cancelled'`), through the relay's `toClient` (the LSP tap records it). The site logs every Error-severity notification, but an LSP reply reaches it only on the paths that hand the error to the notification service (the path that logs Lean's own empty `-32800` message, entry above). Added before any run on G, fail-closed; observed since in every full run on G and H (37–71 lines per run, e.g. 38 in 7 tests of g-full1b, 50 in h-full4), in tests such as C3, C4, C13a, C20, C22, W2, W4 and W7 | **allow**, anchored to that exact text and site, and only PAIRED: each needs its own LSP `-32800` reply seen by the LSP tap in the 3 s before it (or 0.5 s after); fail-closed without tap reports; no count limit. The `-32800` replies form ONE pool shared with the empty-text entry above (`console.mjs` `classifyConsole`: one pool per `lspErrorCode`, paired in wall order), so one reply never explains both an empty line and a cancel line. `tests/ux/lib/qed64.mjs` `classify()` also keeps QED64's local cancel replies (`qed64Kind` `'cancelled'`) out of the pool that explains empty errors. `check-gallery.mjs` unit-tests the entry and the shared pool. Pins A–F print no such text; G and H do |
| `console.warn` `[showcase] the server serves QED64 pin … but gallery/pin.json describes …: following the served page (… mode)` (`/showcase/gallery.js`); `Failed to load resource: … 404` for `/qed64-build.json` | the gallery following a staged pin's release whose mode differs from `pin.json` ("Two modes"); the 404 is that probe on a legacy release | allow at most once per page load, **only** under `UX_PIN` when the served mode differs (the warning) and on a staged legacy release (the 404); never in an ordinary run |
| `console.warn` `[showcase] QED64 page API has editorRpc but lacks widgetSourceCache …` / `… lacks editorRpc …: installing the InfoView repair late …` | a v1 page missing a capability the bridge decision reads ("The RPC bridge") | **never** (no such page exists; a run that logs it fails) |
| pageerror `unsupported` at `$tryShowTextDocument`; an unhandled rejection `Object` | the page's own applyEdit path ran: the bridge was missing or late (D2) | **never** |
| `console.warn('TODO: catch JSON.parse failure:  TypeError: Cannot read properties of undefined (reading \'resolve\')')` | the InfoView got two replies to one request: late bridge install | **never** |
| `Unrecognised error`, `abortSignal` in the InfoView | D1 not repaired | **never** |
| renderer crash / `V8 javascript OOM (CALL_AND_RETRY_LAST)` | L2 | **never** |

## QED64 limitations found (documented, fixed or worked around from outside QED64)

* **L2 — renderer crash when the pthread pool grows (worked around by D3).** The lean.js glue (48,971,853
  bytes) pre-spawns `pthreadPoolSize=24` Workers and spawns one more per extra concurrent Lean thread;
  each is a V8 isolate holding the glue. In Chrome all isolates of a renderer share one pointer-compression
  cage, and at about 30–32 pthread workers (31 and 32 crashed, 30 and once 32 survived) a freshly spawned one fails with `V8 javascript OOM
  (CALL_AND_RETRY_LAST)` at a 73 MB heap (`work/logs/bringup-mp-ck-hasse2.log`, `…hasse3.log`: the dying
  isolate is 0.9 s old = one of the 8 new `blob:` workers created 0.93 s earlier), taking the whole tab
  down. Trigger: a panel with N MakeEditLinks makes the InfoView fire N concurrent `getWidgetSource` for
  the SAME hash (`importWidgetModule` caches only after the reply); HasseView's cube fires 14, each holding
  a Lean task thread (`rt-hasse.json`: pool running 10 → 16, total 24 → 30). It is not the gallery's
  doing: the bare stock page with the X4 init-script bridge crashes the same way on chart-kit → hasse-view
  (`sp-ck-hasse.json`: pool 32, crashed) and on a fresh hasse cursor (`sp-all-cursors.json`: 31, crashed);
  without the bridge no panel RPC reaches Lean and the pool stays at 24 (`sp-ck-hasse-nobridge.json`). It is
  machine-dependent (Lean's task manager uses `navigator.hardwareConcurrency` = 14 here) and flaky near the
  edge (`rt-hasse.json`: 30 workers, survived). Fix in our repo: D3 coalescing in `qed64-bridge.js`; after
  it the pool stayed at 24 in those probes (`rt-hasse-d3.json` `coalesced 13`; `sp-all-cursors-d3.json`: all 46 spec
  cursors of all eight examples in one session, peak 24, 26 workers, no crash; `mp-all-d3.json` gallery
  sequence, one run; RSS varies 8.9–12.3 GiB between cold runs, see the Memory knob). Upstream report: @leanprover/infoview `importWidgetModule` should cache the
  promise; QED64 may want a bounded pool. Correction (UX audit): over a long session the pool can still grow by
  one; in the audit's C20 run that hung (L7) the total went 24 → 25 at document version 43, 17 versions before
  the hang (`out/ux/auditor-full` trace; docs/UX-RESULTS.md L7).
  **On pins F, G and H (2026-10-05/06)** the page coalesces `getWidgetSource` itself (per-session cache, an error reply
  releases the waiters; EMBEDDING.md §2.5, `capabilities.widgetSourceCache`), so the gallery no longer installs D3
  there. Whether the pool stays at 24 through the HasseView cube is for the browser gates on the active v1 pin to show
  (W1–W8, C20). A related limit is QED64's HARDENING #59: typing at a normal pace above a long uncancellable command
  grew the pool until the tab crashed, on every build up to F, because the edit coalescing capped bursts only. QED64
  reports it fixed in G by `e4cffcc` (back-pressure on the worker pool, at most 6 requests in flight). We have not
  measured it yet (docs/UPSTREAM-REPORT-QED64.md).
* **L7 — QED64's Lean runtime could freeze. Fixed upstream by QED64's #52 worker** (first in 9fdf9b8, runtime
  `wasm64-2c18773ecfba45bb`, kernel `3ae65d36f9`; pin C `5ac5d00` (served until 2026-10-04) has layers (2)–(4) on the 0034 runtime,
  without patch 0035; docs/REPIN-LOG.md). The fix has four layers:
  (1) kernel patch 0035: the task manager no longer calls `pthread_create` under its global mutex and reuses parked
  dedicated threads (`status().pool.parked`); (2) the runtime mailbox notifies by postMessage instead of
  `Atomics.waitAsync`, so a lost wakeup is no longer permanent; (3) a 1 s raw mailbox kick that serves a lost wakeup
  and counts it as a confirmed rescue (`status().liveness.rescues`, log line `[liveness] a runtime-mailbox wakeup was
  lost … rescue #n`, field evidence for the lost-wake hypothesis); (4) a Lean-side liveness probe that reboots a wedged
  session (pill "the checker stopped responding — restarting"). The gallery defers to it (Errors, above). A user
  `#eval (IO.Process.exit n : IO Unit)` is caught only by QED64's new FileWorker exit hook (died `exit`; upstream
  report X1), not by any liveness probe. The history below describes the freeze on the previous pin (`wasm64-4b025db7…`).
  Seen once,
  by the UX audit (`out/ux/auditor-full`, C20 hasse-view link #30, about 75 edits into one session): after an
  ordinary link click QED64 stayed in `elaborating` at v60 on a serving relay, with no death, no error card and no
  LSP message for 120 s, and the Reset (v61) stayed `elaborating` too. What the trace shows (`out/hang/ROOT-CAUSE.md`,
  "Verification, second pass"):
  * **It is a runtime-wide freeze**, not slow work and not a widget problem. Every Lean pthread stopped at once (pool
    `8/17` before and after the v61 edit, no thread created or ended for 450 s, no output), while the worker's JS
    thread, the Emscripten main thread, kept running and kept QED64's heartbeat alive. The Emscripten main-thread
    proxy path had stopped. The pool froze because Lean's task manager calls `pthread_create`, a synchronous proxy to
    that main thread under Emscripten, while it holds its global `m_mutex`: the creator waits forever with the lock
    held, and every other Lean thread blocks at its next task operation.
  * **The onset is an ordinary cycle.** The `-32800` cancel right after the click is routine (one per cycle in every
    run), and the v60 progress reporter did run (two fileProgress updates reached the editor).
  * **Likely trigger: one lost wake of the main-thread mailbox.** In Emscripten 6.0.5's `waitAsync` mode a single lost
    wake is permanent: senders notify only when the mailbox is not already marked pending, and only draining it clears
    the mark, so no later sender ever wakes it again. The QED64 owner's fault injection E1 reproduced the exact
    signature by dropping one wake (pool frozen, 0 frames for 180 s; only the glue's `checkMailbox()` revived it).
    What loses the wake in Chrome has not been observed.
  * **Rate:** 1 hang in 19 recorded C20 runs (about 2,200 link clicks, 4,400 edits), so about 1 in 20 C20 runs.
  * **The fix is the QED64 owner's, in progress:** postMessage mailbox notifications plus a periodic raw mailbox kick,
    and a Lean-level liveness reboot; kernel patch 0035 (no `pthread_create` under `m_mutex`) reduces the exposure.
  * **Here (previous pin):** the liveness probe restarted a frozen runtime after about 20 s, keeping the text; the 45 s
    card was the fallback; observe mode plus the UX harness's hang capture record the state of a real one for the
    owner (Errors; C21, C22). **On a pin with QED64's own liveness (the served E `33b0967`, C `5ac5d00`, D and B)** the probe defers to
    it and is a 30 s fallback: a freeze QED64 does not see is restarted about 41 s after the last progress (ready about
    49 s). On C (15 C20 runs), D (4) and B (17) no hang was seen and QED64's liveness never acted
    (`node scripts/ux-tally.mjs`).
* **L9 — a reload or a relay restart can crash the renderer** (a V8 OOM about 2 s after a new runtime starts booting
  in the same renderer). Tallies from `node scripts/ux-tally.mjs` (docs/UX-RESULTS.md "Status and tallies"):
  * **B `9fdf9b8` (kernel 0035, staged as evidence):** the classic form V1 (`Scavenger: semi-space copy`, after the first
    reload). Stock-page storms in chrome-headless-shell 3 of 8 (`repin-ab` 3/5, `multipin-storm` 0/3); in the UX suite
    C10 crashed in 6 of the 8 runs that ran it (5 of 7 full runs), C21 (b) 3 times while it shared a renderer with (a)
    (none since it runs in its own browser), W4 once. Every red full run on B had a renderer crash; only
    `final-full1` was green.
  * **E `33b0967` (served since 2026-10-04; QED64's #55 lifetime locks, its V2 fix, on D's runtime):** no crash in 28
    storms on `/showcase/#hasse-view` (headed 0/20, headless-shell 0/8), interleaved with C (0/20, 1/8 V2). C was nearly
    clean in those windows too, so this shows E is not worse but does not confirm the fix. C10 in its three gate runs: no
    crash (`out/ux/pin-e/RESULTS.md`).
  * **G `5c327c2` and H `bf9d947` (the v1 pins on E's runtime): QED64's #55 residual** (reopened by QED64 on 2026-10-07).
    A reload or a reboot during a QED64 boot can still crash the renderer on some machines. On H three runs each lost one
    test that way (docs/REPIN-LOG.md, pin H entry): `h-full1` C9 (the stock page's reboot loop on an unpaired overlay,
    crash after 9 runtime starts), `h-full2b` C10 (1.25 s after QED64 waited 132 ms for the previous runtime) and
    `h-headed1` C11 (the test's recovery reload, about 3.6 s after QED64 halted). Rates over every run on G and H:
    C10 1 of 9 storms in chrome-headless-shell (0 of 2 headed), C9's stock reboot loop 1 of 9, C11's recovery reload
    1 of 9. QED64's explanation (theirs): one booted runtime's ~25 glue isolates (~129 MiB each) fill most of the
    renderer's 4 GiB pointer cage, and the embedder's JS heap shifts the rate (their ballast storm: 0 MiB 0/8, 800 MiB
    8/8, 1600 MiB 8/8). The gallery's share is small: used JS heap 64.8 MiB with the gallery against 64.8 MiB for a
    trivial same-origin embed and 61.0 MiB for the stock page (`out/ux/heap-share-1/heap-share.json`, medians of 5).
    **What the gallery does:** its own boots (the first one, Try again, a switch that needs a boot) send the frame to
    `about:blank` and wait up to 10 s for the old page to unload (`boot()` step 2), so the old runtime is released before
    the new one starts; it never reloads a booting page itself, except the card's **Restart Lean** when QED64 refuses
    `api.restart()` because a boot is in flight (`restartLean`'s page-reload fallback). A visitor's own reload (F5)
    during a boot is the exposed path. The margin has to come from QED64's kernel side (a pool-size knob, a smaller
    glue); QED64's #62 and #63 (in progress) change the boot-failure paths of C9 and C11.
  * **C `5ac5d00` (served until 2026-10-04), A `1859b83` (runtime 0034) and D `3b42714` (QED64's 0035b candidate):** no V1, and no
    crash in the UX suite (C10: 0 crashes in 9 full runs on C, 4 on D, 11 runs on A). **A second form V2** (`MarkCompactCollector: young
    object promotion failed`, after reload 2–4) hits all of them: first in headed desktop Chrome (C 4/19, A 1/5, B 2/8,
    all in one 50-minute window, `out/ux/l9-desktop/RESULTS.md`; quiet slot A 1/8, C 2/10, D 0/5), then in the final
    gate's interleaved storms in both browsers (A 3/26, C 2/26, D 3/26; `out/ux/final-storm/RESULTS.md`). In the final
    gate's quiet round all 6 crashes were through `/showcase/` (0/9 on the stock page). Why the gallery entry is hit
    more often was measured by the v2-embed lane (2026-10-03, `out/ux/v2-embed/RESULTS.md`): mainly **embedding
    itself** (the stock page in a script-free same-origin iframe 16/48 vs 4/48 at top level, Fisher p = 0.005); the
    gallery's JS on top adds an increment that is not significant (15/24 vs 10/24, p = 0.25).
    So on these pins a desktop visitor who reloads repeatedly can lose the tab. **Per path on C** (README.md "Limitations"
    has the table): the visitor's path, headed Chrome through `/showcase/`, lost the tab in 24 of 56 five-reload storms
    (43 %, Wilson 95 % 31–56 %); the latest window (v2-embed arm S, 2026-10-03, quiet host, `#hasse-view`) had 15/24
    (62 %, 43–79 %), the earlier ones 9/32 (v2mit control arm 8/24, final-gate quiet round 1/3, interleaved rounds 0/5);
    headed stock page with the widgets overlay 8/80; chrome-headless-shell `/showcase/` 0/17. The pooled 2/26 above
    understates the visitor's risk. A gallery-side mitigation (QED64 teardown on the top window's `pagehide`) was measured and
    rejected: headed 10/24 with it, 8/24 without (`out/ux/v2mit-storm/RESULTS.md`).
  * Not caused by the gallery's code (both forms crash the bare stock page too, with no gallery and no bridge; the extra
    V2 on `/showcase/` comes mainly from running the page in an iframe at all, which is what the gallery is) and not fixable from it: the
    gallery's own restarts (liveness fallback, the card, Reset) boot a new worker in the same renderer and are exposed
    the same way. Evidence and repro: docs/UPSTREAM-REPORT-QED64.md L9, docs/REPIN-LOG.md §9 and "2026-10-02".
* **The page's own message listener wins over a late bridge** (bridge section): install before the module
  script. The gallery does; `status().bridge.late` must stay 0.
* **No widening from an init-only session**: a Mathlib header on a session booted for an import-free
  buffer is refused; the gallery restarts the relay on `[init, mathlib]` (switch section).
* **L1** (`docs/HEADLESS-RESULTS.md`): `(reflect := true)` on values built from non-exposed core `module`
  definitions (e.g. `Lean.RBMap.ofList`) fails in QED64 because imports happen at the exported level. The
  TreeScope example uses the semantic view of `rbSample`, which works in the gallery (hints run); a user who
  adds `#tree_scope (reflect := true) rbSample` would hit L1 (shown headlessly by E2; not re-run in the
  browser), so the card's "any concrete value by reflection" holds only for values whose definitions are
  exposed.
