# How the showcase uses QED64

The showcase serves QED64's **stock, unmodified page** with our widget packages inside it. QED64 is a
dependency of four kinds. None of them is a copy of QED64's code:

| Kind | What | How it is pinned | How a clone gets it | Checked by |
|---|---|---|---|---|
| **Source** | QED64's git tree at the served pin's commit | the git **submodule** `qed64-showcase/deps/qed64`; its gitlink *is* the served pin's source pin. Each staged pin uses a `git worktree` of the submodule's own repository at `$QED64_SHOWCASE_WORK/qed64-pins/<id>` | `git clone --recursive`; `showcase.sh bootstrap` runs `git submodule update --init` and adds worktrees if they are missing | `pin-qed64.mjs verify` #8: HEAD == the lock's commit, no tracked file modified, and for the active pin gitlink == HEAD == lock |
| **Binary** | QED64's runtime chunks, library packs and stock snapshots. Their names are content addresses, and they are not in QED64's git | `release.files` in `pins/<id>/QED64.lock.json`: the sha256 and size of each of its files (145 for E, 146 for F, G and H: their `dist/` adds `qed64-build.json`) | `scripts/fetch-artifacts.mjs` fetches them from an artifact origin by URL path, checking sha256 against the lock. The tracked manifests come from git instead | verify #1–#6 and #10 (every byte, plus the manifests' own digests) |
| **Toolchain** (heavy path only) | the kernel fork's native64 Lean/Lake, the Docker image it runs in, the Mathlib tree it built, and QED64's slim base olean tree | `toolchain` in the lock (native64 commits and binary sha256s, Docker image id and recorded equivalents, Mathlib and ProofWidgets commits, Node version) | You build them yourself: [BUILD-FROM-SOURCE.md](BUILD-FROM-SOURCE.md) | verify #7 when `QED64_KERNEL_BUILD` is set, and N/A otherwise. `showcase.sh native` refuses a Docker image the lock does not record |
| **Page tier** (runtime) | the page's JavaScript globals, DOM and query knobs that the gallery drives (on F, G and H, the v1 pins: the declared embedding API v1, `qed64.api`) | the pinned bundle itself. The gallery reads `gallery/pin.json` (generated from the lock), and the UX suite resolves the bundle name per pin | it arrives with the page, which is built from source | the gallery's static gate and the UX suite; the full list is under [Integration points](#integration-points) below |

Our own additions sit on top: the native widget oleans, the baked widget overlays `widgets7`/`widgets8`, the gallery
at `/showcase/` (with its same-origin bridge on pins A–E; on F, G and H (the v1 pins) the gallery uses the page API instead), the
Cloudflare Worker, and the tests.

```
                      github.com/FawadHa1der/QED64 (public)
                                   │ git submodule (gitlink = served pin's commit)
                                   ▼
 lean-widgets repo ── qed64-showcase/deps/qed64 ──git worktree──► $W/qed64-pins/<staged id>
   packages/ (8 widget packages)   │
   qed64-showcase/                 │ SOURCE (read in place, never copied)
     pins/<id>/QED64.lock.json ◄───┼──────────────────────────────── the trust anchor: commit + sha256 of every
                                   │                                  served file and overlay
   build-shell.mjs ── npm ci --prefix frontend && npm run build:site ──► release/<id>/dist   (byte-identical to the lock
                                   │                                                          or nothing is installed)
   fetch-artifacts.mjs ◄── git show <commit>:public/{runtime,profiles,snapshots}/*.json (tracked manifests)
          ▲            ◄── ARTIFACT ORIGIN (our Worker / serve.mjs of a built checkout / QED64's own site for its files)
          │                  /runtime/chunks/*  /profiles/*.part-*  /snapshots/*.snapz  /snapshots/widgets{7,8}/*
          └─────────────────► release/<id>/public/…   +   out/runtimes/<buildId>/overlay/widgets{7,8}/  (sha256 == lock)

   imports from the source:  serve.mjs, infra/worker.js, deploy-manifest.mjs ── QED64 infra/worker.js isImmutable
                             bake.sh ── pipeline/snapshot/bake-snapshot.mjs        stage-trees.mjs ── pipeline/artifacts/olean-imports.mjs
                             pair-check.mjs, headless/lib.mjs ── pipeline/toolchain/artifact-paths.mjs
                             headless/exact-header.mjs ── pipeline/snapshot/snapshot-probe.mjs   run-e2.sh ── supervised-run.mjs → node-runner.mjs
                             headless/wasm-lsp.mjs ── public/workers/lsp-frames.js   check-gallery.mjs ── public/workers/lean.worker.js (probe bytes)
                             preflight-overlays.sh, tests/experiments/x1 ── tests/adversarial/preflight.mjs

 one origin (serve.mjs locally, infra/worker.js on Cloudflare):  /  = release/<id>/dist (the stock page)   /runtime|profiles|snapshots/ = release/<id>/public
                                                                  /snapshots/widgets8/ = our overlay        /showcase/ = gallery/ (iframes "/?snapshots=snapshots/widgets8";
                                                                  on F/G "/?embed=1&snapshots=snapshots/widgets8#code=…")
```

## Source dependency

* **Served pin.** The submodule is checked out at the active pin's commit; `scripts/lib/qed64-src.mjs` answers "where
  are QED64's sources at this pin". `showcase.sh pin use <id>` moves the submodule to the new pin's commit and refuses
  if a tracked file in it is modified. It then stages the switch: the lock link, `gallery/pin.json` and the gitlink,
  `git add`ed together, so a commit records it and the index stays consistent. The previous pin keeps its sources as a
  worktree. Rehearsed on a fresh clone (E → C → E, `$W/logs/r2/clone-spaced-pin-switch-2.log`).
* **Staged pins.** These are git worktrees of the submodule's own repository (`git -C deps/qed64 worktree add --detach
  $W/qed64-pins/<id> <commit>`). If the commit is not present, it is fetched from the submodule's origin. No other QED64
  checkout on the machine is read or written. `node scripts/qed64-src.mjs ensure|check|dir [<id>|--all]`.
* **What is read from the sources.** QED64's page build (`frontend/`, `npm run build:site`); the five tracked manifests
  and indexes under `public/`; `pipeline/toolchain/KERNEL-PIN` (verify #9); `infra/worker.js` (`isImmutable`, which
  `serve.mjs`, `deploy-manifest.mjs` and our Worker import; `wrangler deploy --dry-run` bundles just that function
  into the Worker, `$W/logs/r2/wrangler-dry-run.log`); `pipeline/snapshot/*` (bake,
  probes, runner); `pipeline/artifacts/olean-imports.mjs`; `pipeline/toolchain/artifact-paths.mjs`;
  `public/workers/lsp-frames.js`; `public/workers/lean.worker.js` (the gallery gate compares the Memory64 probe bytes
  with it); `tests/adversarial/preflight.mjs`. `verify` #8 fails if a vendored copy (`pins/*/QED64-PIN`,
  `pins/*/vendor-qed64`, `vendor/qed64`) reappears.
* **History.** Until 2026-10-04 these files were a vendored `git archive` per pin, hashed in `pins/<id>/QED64-PIN`. All
  128 vendored files were byte-identical to `git show <commit>:<path>` in the submodule repository at their pins
  (`$W/logs/r2/vendor-vs-submodule.log`). The copies were moved to `$W/r2-moved-aside/vendor-qed64/` and are no longer
  used.

## Shell from source

`scripts/build-shell.mjs` (and `showcase.sh bootstrap`) runs QED64's own build in the pin's source checkout:
`npm ci --prefix frontend` (exact versions from `frontend/package-lock.json`), then `npm run build:site` (Vite builds
into the checkout's gitignored `dist/`). It then compares every built file with `release.files` in the lock: the same
file set, size and sha256. Only if all of them match does it install `release/<id>/dist`. An existing dist that already
matches is left in place; one that does not match is moved to `dist.prev-<time>`.

**The build is deterministic, so the lock's hashes are the check.** Measured on 2026-10-04:

| Build | Result |
|---|---|
| Fresh public clone of QED64 at 33b0967, macOS arm64, Node v26.3.0, npm 11.16.0 | all 58 dist files byte-identical to `release/33b0967/dist` (`$W/logs/r2/shell-det-compare-33b0967.log`) |
| The same clone's worktrees at 1859b83, 9fdf9b8, 5ac5d00 and 3b42714 | each 58/58 byte-identical to its `release/<id>/dist` (`$W/logs/r2/shell-det-other-pins.log`) |
| The submodule in this repository (`build-shell.mjs`) | 58/58 (`$W/logs/r2/build-shell-main-33b0967.log`) |
| A fresh `git clone --recursive` of this repository (`showcase.sh bootstrap`) | 58/58 (`$W/logs/r2/clone-bootstrap-1.log`) |
| Linux, Docker `node:26-bookworm` (aarch64), Node v26.7.0, npm 11.19.0, fresh clone | 58/58 (`$W/logs/r2/linux-rehearsal-1.log`) |

The served releases were copied from the QED64 owner's own `dist/` builds. QED64's build is therefore reproducible
across machines, operating systems and Node patch versions. Nothing about it is normalized: there is no build id or
timestamp in the output, and the runtime buildId is taken from the tracked `public/runtime/runtime-manifest.json`
(`frontend/vite.config.ts`). If a future pin does not rebuild identically, `build-shell.mjs` prints every differing,
missing or extra file and installs nothing. The fix is then to find the source of the difference and record it here,
never to skip the check.

## Binary dependency

QED64's runtime chunks (`/runtime/chunks/*`), library pack parts (`/profiles/*.part-NNN`) and stock snapshots
(`/snapshots/*.snapz`) are not in QED64's git; QED64's own manifests name them by digest. Our overlays come from our
own bakes. `scripts/fetch-artifacts.mjs` installs a pin's binaries as follows:

* **From git, not fetched:** `public/runtime/runtime-manifest.json`, `public/profiles/{index,lean-core.manifest,
  mathlib-essential.manifest}.json` and `public/snapshots/index.json` (`git show <commit>:<path>`), plus
  `runtime-manifest.<buildId>.json`, which is the same bytes (verify #2). These are the digest roots and are the same
  files QED64 itself commits.
* **Fetched by URL path** (`public/<p>` is served at `/<p>`) from an artifact origin, and checked against the lock's
  sha256 and size before it is renamed into place. A mismatch is kept as `<file>.rejected-<time>` and the run fails.
  The fetch is resumable. A complete, verified file is kept. An interrupted download continues from `<file>.partial`
  with a `Range` request when the origin answers 206 (our Worker does); otherwise that one file restarts. The overlays
  (`/snapshots/widgets{7,8}/{index.json, init.<d>.snapz, widgets.<d>.snapz}`) are installed into
  `out/runtimes/<buildId>/overlay/` and checked against the lock's `overlays` section.
* **Origins:** `--origin` (`ARTIFACT_ORIGIN`) is the showcase's own origin. It serves QED64's files and our overlays at
  exactly these paths: the deployed Worker, or `scripts/serve.mjs` of a checkout that has the files. `--qed64-origin`
  (`QED64_ARTIFACT_ORIGIN`) serves QED64's files only; QED64's live site serves the same paths. These are plain GETs
  from Node; CORP/COEP do not apply to them. `--remote-check` HEADs every file first. QED64's Worker omits
  Content-Length on HEAD, so for it the tool reads the GET headers instead.
* **Proved on 2026-10-04:** a fresh clone fetched all 81 binary files of pin E (1.38 GB) from
  `https://qed64.fawadworkaddress.workers.dev` with sha256 equal to the lock. That run was interrupted once
  deliberately after 30 s and resumed: 22 kept, 65 installed, 0 failed (`$W/logs/r2/clone-fetch-live-*.log`). The
  overlays (761.5 MB) came from a local origin (`serve.mjs` of the main checkout on :5297; `clone-bootstrap-1.log`). The
  Linux rehearsal fetched all 93 files from the same local origin.

Until the showcase's Worker is deployed, the overlays exist only on machines that baked them. A cloner without such an
origin either points `--origin` at someone's served checkout or rebuilds the overlays ([BUILD-FROM-SOURCE.md](BUILD-FROM-SOURCE.md)).

## What a clone needs

| To … | Needs | Not needed |
|---|---|---|
| serve and test the showcase (`bootstrap`, `verify`, `gallery`, `serve`, `ux`) | git, Node 26 (the lock records v26.3.0; another 26.x is a DRIFT, see below), npm, network access to GitHub/npm and to an artifact origin, Playwright's Chromium (`npx playwright install chromium chromium-headless-shell`) for `ux`, a machine with 16 GB of RAM for the browser | `QED64_REPO`, the kernel build, Docker |
| rebuild the overlays | the kernel fork's native64 toolchain, its Docker image, the Mathlib tree it built, QED64's slim base tree, and about 36 GB of RAM: [BUILD-FROM-SOURCE.md](BUILD-FROM-SOURCE.md) | – |

A checkout that serves fetched artifacts has no build stores of its runtime (`$W/runtimes/<bid>/`, `out/headless`).
`pin current`, `pin check` and `verify` print them as **ABSENT**, and print a staged pin that was never bootstrapped as
**NOT MATERIALIZED**. Neither counts as a failure, because what is served is still checked file by file against the
lock. **N/A** marks a rebuild-only input that is missing on this host, such as the kernel build or a downloaded
browser. **DRIFT** marks a rebuild-only input that differs from the lock: the Docker image behind a tag that QED64
rewrites (unless its id is a recorded equivalent: the current `8228ea564e7b` rebuilt all 7,616 native output files
byte for byte, BUILD-FROM-SOURCE.md), or the Node version the bakes ran on. All of these are printed, counted and named in the verify summary.
None of them is ever silent.

## Platforms

Everything a cloner or CI runs works on **macOS and Linux**: bootstrap, `build-shell`, `fetch-artifacts`, `pin-qed64
verify`, `pin current/check/use`, the gallery's static gates (`check-gallery`, `sim-gallery`), `check-portable`, the
deploy manifest (generate, `--check`, `--stage-assets`), `infra/worker.test.mjs` and the browser-lock wrapper with its
tests. The platform-specific parts are in `scripts/lib/platform.{sh,mjs}`:

| | macOS | Linux |
|---|---|---|
| memory a heavy process can get | `vm_stat`: free + inactive (+ speculative) pages | `/proc/meminfo` MemAvailable |
| copy-on-write clone | `cp -c` / `cp -cR` (APFS clonefile) | `cp --reflink=auto` / `cp -R --reflink=auto` (reflink where the file system supports it, else a copy) |
| no idle sleep during long runs | `caffeinate -i` (process-scoped) | nothing (not needed) |

The Linux side was proved in Docker `node:26-bookworm` (aarch64) on 2026-10-04 (`$W/logs/r2/linux-rehearsal-1.log`):
fresh `clone --recursive`, bootstrap from a local origin, `verify` and `gallery` all passed, and so did
`fetch-artifacts --check`, the worker tests, `lockfifo`/`lockrace`, `check-portable` and the deploy manifest. The CI job
(`qed64-static` in `.github/workflows/lean-ci.yml`; until 2026-10-04 `showcase-source.yml`) needs no artifact origin: it rebuilds the page from the submodule, installs the
tracked manifests with `fetch-artifacts --git-only`, and runs the worker tests and the gallery gate. Its steps passed
in the same image (`linux-ci-mirror-2.log`).

**macOS-only (stated plainly):** the heavy path's measurement wrappers. `bake.sh`, `headless/run-stage4.sh`,
`run-e2.sh`, `run-controls.sh` and `derive-raw.sh` run under `/usr/bin/time -l` and read `stat -f`. `build-native.sh`
checks the clone's link count with `stat -f %l`. `lean/goldens/golden-env.sh` uses `cp -c`, and
`scripts/headless/hang-repro.mjs` and `scripts/assert-untouched.sh` use `vm_stat` and `stat -f`. These steps rebuild
or diagnose the overlays and were only ever run on the 36 GB Mac this project was built on. Porting them is mechanical
(GNU `time -v`, `stat -c`), but nobody has done it or tested it. The UX suite's memory figures and baselines are from
macOS Chromium.

## Integration points

Every QED64 interface the gallery, the tools and the tests touch, in two states. **Pins A–E** (E `33b0967` is what the
live site serves) have no page API: the gallery runs in **legacy mode** on QED64 internals. **F, G and H (the v1 pins)**,
F `84d594e` and G `5c327c2` (QED64's `feature/embedding-api`; G = F + `e4cffcc`, the edit back-pressure) and H `bf9d947`
(QED64 main; H = G + the keep-alive fix: `$/lean/rpc/keepAlive` never waits for a request slot; **H active locally since
2026-10-06 and browser-gated**, G and F staged; none deployed: docs/REPIN-LOG.md, pin H entry), implement the
embedding contract v1 (`deps/qed64/docs/EMBEDDING.md`, revision `1.0.0`), and the gallery runs in **v1 mode** on its
declared API. The mode comes from `gallery/pin.json` `apiRevision`, which `scripts/build-gallery.mjs` reads from the pin
release's `dist/qed64-build.json` (`null` without one), except that a server serving another pin's release than
`pin.json` describes (`X-Showcase-Pin`) makes the gallery follow that release's own revision
(`status().modeSource 'served'`). `serve.mjs` sends it as `X-Showcase-Api` on every response (a revision, `none` or
`invalid`); only when that header is not a revision or `none` does the gallery probe the release's `/qed64-build.json`.
`/showcase/pin.json` is served `Cache-Control: no-store`. The deployed Worker sends neither header. Both modes are kept: legacy mode is exactly the earlier flow, for the fallback pins.
[QED64-EMBEDDING-V1-REVIEW.md](QED64-EMBEDDING-V1-REVIEW.md) maps each row to the v1 draft (2026-10-04) and, in its
"Adoption" section, to what F's API became (G's and H's API keeps revision `1.0.0`; `e4cffcc` adds the `?edithold=<n>` boot parameter to §4, a note that a `telemetry` reply may follow a `status` event, and the back-pressure and local cancel replies to §7.8); the "Review rows" column refers to
its table. The gallery's side of v1 is described in gallery/README.md "Embedding API v1 (pins F, G and H)".

**Page tier: what the gallery uses.**

| Interface | Pins A–E (legacy mode) | F, G and H, the v1 pins (v1 mode) | Review rows |
|---|---|---|---|
| finding the page and its status | `contentWindow.qed64`, `qed64.status()` polled every 250 ms (phase, version, relay, liveness, pool, header, lastDeath, rebootReason) | the frozen `qed64.api` from the `qed64:frame-api` CustomEvent on the gallery window (`detail.frame === iframe.contentWindow`; fallback a polled frozen `pageWin().qed64.api`), bound to the document that published it; `api.status()` (synchronous) polled the same way. `api.settled()`/`whenReady()` are not used: the waits stay polling-based so supersession and the progress-aware boot timeout keep working | 1, 3, 15, 16, 33, 34, 35, 43 |
| capabilities | none (a late-install heuristic `!!qed64`) | required: `documents`, `events`, `embedMode`, `restart` (else the hard boot card, `status().api.missing`); `editorRpc` + `widgetSourceCache` stand the bridge down; `liveness` stands the probe down | 2 |
| the document and the cursor | `qed64.editor` (Monaco `setValue/getValue/getLineCount`, `setPosition`, `revealLineInCenter`, `focus`, `getPosition`) and `relay.lastText` | `api.setDocument(text, {cursor, focus: false, undoable: false})` (resolves `{version, unchanged}`), `api.getDocument()`, `api.setCursor(pos, {focus})` after ready, `api.getCursor()`, `api.focus()` | 8, 9, 10, 11 |
| the boot document | `localStorage['qed64.buffer']` seeded before navigation; the page's 400 ms debounced save; `about:blank` first | `/?embed=1&snapshots=snapshots/<overlay>[&memory=<GiB>]#code=<example>`; the page neither reads nor writes `qed64.buffer`; `about:blank` first is kept (it releases the old runtime and a `#code=`-only change would not reboot) | 4, 5, 45 |
| persistence and frame reloads | the page restores `qed64.buffer`; the gallery adopts what it shows | the `document` event into our key `qed64-showcase:document` (at most once per second, flushed on `pagehide`); a reload the gallery did not start is adopted by a synchronous `api.setDocument(newest forwarded text)` in the `qed64:frame-api` handler (§3.1's 5 s window). When a boot cannot keep the text it displaces from the key (a quota error), the gallery **holds** the key instead of overwriting it, and edits stay in memory. A memory-only text that cannot be kept becomes **unsaved**. A storage notice says where each text is (with **Copy it** for an unsaved text, whose × is then hidden). A held tab retries at most every 5 s, with one timer and no polling, and `beforeunload` asks first while a text is at risk. All of this is ours, in `localStorage` (gallery/README.md "When storage is full or blocked") | 7, 18 |
| restart, widen, the offer | `relay.restart(relay.restartOpts \|\| {snapshots})`, `relay.state.kind`, `relay.session.snapshots`; `restart({snapshots:['init','mathlib']})` on a refused header; button-text matching | `api.restart()` (the relay's own header rule; stall events' `how` `'api.restart'`), `api.restart({snapshots:['init','mathlib']})` on `headerRefused` with `status().snapshots` lacking `mathlib`; `status().offer` / `api.acceptOffer()` | 17, 19 |
| progress, stall watchdog, proof of life | a wrapper on `relay.toClient` (fileProgress, publishDiagnostics, every frame); synthetic frames told apart by the `QED64:` label | the `fileProgress` and `diagnostics` events (`origin: 'qed64'` = the page's own notes, not proof of life); `status().stall.source 'api-events'` | 12, 13 |
| liveness | the gallery's hover/main-loop probe through `relay.fromClient`, deferring to QED64's counters in `status().liveness` | the probe stands down (`status().liveness.probe 'stood-down'`); QED64's projection `status().liveness {stalled, lastAnswerAgoMs, lastFrameAgoMs, …}` and the `liveness`, `reboot` and `death` events; the 45 s card is the gallery's recovery | 14, 15, 16, 36 |
| boot progress and failures | wraps of `qed64.ui` `busy/progress/idle`; `#boot(.done)`, `#bootcard.failed`, `#bootlabel` | the `boot` and `status` events, `status().boot {done, failed, message, overlay}`; the page's resource timing entries (a standard Web API of the frame window) still count as boot progress | 21, 22, 23, 24 |
| memory knob `?mem=` | `relay.makeSession` wrapped (`relay.__showcaseMem`), a light `init` boot, then a restart | `&memory=<GiB>` on the frame URL; `status().mem.applied` compares `status().memory.initialBytes` | 20 |
| the InfoView's postMessage protocol | `qed64-bridge.js` (D1 `abortSignal` strip, D2 edits on `qed64.editor`, D3 `getWidgetSource` coalescing through `relay` taps), installed before the page's module | not installed: the page repairs D1/D2 itself (HARDENING #56) and caches widget sources (§2.5) (`status().bridge.stoodDown`). A v1 page without `editorRpc` would get it late with edits on; one with `editorRpc` but no `widgetSourceCache` gets nothing, because the bridge only matches the pre-#56 message names (`capabilityMismatch.repair 'unavailable'`) | 2, 30, 31 |
| layout | `<style id=qed64-showcase-stack>` on `#split/#editor/#infoview` at ≤ 720 px plus `editor.layout()`; `<style id=qed64-showcase-page>#examples{display:none}`; the slow notice placed below `#bar` | **the one remaining internal dependency:** the same stacking `<style>` (Monaco follows the resize by itself; no `editor.layout()`); `embed=1` hides `#examples` (the gallery's rule stays as a no-op); the slow notice keeps its CSS position. Runtime styling only: it never throws and never fails a boot when the ids are missing. `layout=` is v1.1 | 25, 26, 27 |
| our listeners and expandos | an F6 capture `keydown` and `__showcaseKeys` on the page window; `window.__showcaseBridge` (renamed from `__qed64Bridge`: `__qed64*` is reserved, §9); `relay.__showcaseMem` | the F6 listener and `__showcaseKeys` only (§9 allows an embedder's listeners on the framed window) | 28, 29 |
| timing facts | the hook within 120 s; QED64's liveness window 6 + 12 + 4 s (`PROBE_DEFER_MS` 30 s) | the hook within 120 s (`qed64:frame-api` fires at module start); the liveness window is QED64's own business | 35, 36, 37 |
| overlay and preflight | `?snapshots=<dir>` and its re-root rule; snapshot index `qed64.snapshot-index/v1`; `runtime-manifest.<buildId>.json`; the region named `mathlib` | unchanged: §4 validates `snapshots`, and §8 declares the overlay index; our region still carries the name `mathlib` | 6, 7, 40, 58 |

**Tools and tests: what is still internal on F, G and H** (none of it is shipped to visitors):

| Interface | Used by | On F, G and H | Review rows |
|---|---|---|---|
| `qed64.relay` counters (`stats`), `relay.session.snapshots`, `relay.lastText.length`, `status().pool` | UX `QedDriver` (`tests/ux/lib/qed64.mjs`), W1–W8, C16, C20, C23 | still read from the relay: §9 lists `stats()` and `rawStatus()` in the unstable test hatch `qed64.test`, not yet adopted. The driver's status fields come from `api.status()` | 43, 54 |
| telemetry (wasm heap) | `Gallery.telemetry()`, hang capture step (b), memprobe | `qed64.test.telemetry()` (the hatch, §9: tests only) when present, else `relay.session.lean.request('telemetry')` | 44 |
| fault injection: `session.onLsp/onStatus` replaced (C21), worker `die()` (C23), `lean.died()` (bring-up) | C21, C23, `bringup/questions.mjs` | unchanged; `inject`/`freeze` are v1.1 | 50, 51, 53 |
| the LSP tap on `relay.toClient/fromClient` | `tests/ux/lib/lsp-tap.mjs` (console pairing of `-32800` and, on F, G and H, `-32801` replies; on G and H also QED64's local `-32800` cancel replies, `qed64Kind` `'cancelled'`; on G Lean's `-32900` replies for C22's keep-alive scenario; frame counts) | unchanged; on F, G and H it wraps the page's own taps (`relay-taps.ts`). `qed64.test.lsp.on()` is the sanctioned replacement, not yet adopted | 42, 55 |
| worker globals (`__emscripten_check_mailbox`, `PThread`, `__qed64TestExports`) | hang capture, `tools/qed64-liveness.mjs` | unchanged (§9 names `__qed64TestExports` the worker's test hook) | 49, 52 |
| page DOM and Monaco/InfoView DOM | UX specs (pill, boot card, action button, `.monaco-editor`, the InfoView iframe), throttled first visit, visual baselines | unchanged; the stock-page tests still seed `qed64.buffer` on the plain page | 46, 47, 48 |
| console labels and the main bundle's notify line (`@qed64-main-bundle`, line0 627, sha256 per pin in `pins/<id>/pin.json` `consoleSites`) | UX console oracle (`selectors.json`), `pin check` | unchanged, plus the v1 pins' `-32801` ContentModified entry (edit coalescing, §7.8) and, for G and H (`e4cffcc`, §7.8), the `-32800` entry `QED64: the client cancelled this request before it reached the checker`, paired from one `-32800` reply pool shared with the empty-text entry; on G only, C22's `rpcKeepAliveStarved` scenario; the notify line is line0 627 sha256 `46b0155c…` on G and `fc6ad361…` on H | 56 |
| the wasm runtime ABI (`_lean_wasm_load_snapshot_mem`, the input ring, `$/qed64/headerStatus`) and `Qed64LspFrames` | headless/wasm-lsp.mjs, exact-header.mjs, hang-repro.mjs | unchanged | 57 |
| pipeline CLIs and env (`bake-snapshot.mjs …` with `QED64_ALLOW_LEGACY_IMPORTS=1`, `snapshot-probe.mjs --via-mem`, `supervised-run.mjs`, `olean-imports.mjs --audit`, `artifact-paths.mjs`, `tests/adversarial/preflight.mjs`) | bake.sh, stage-trees.mjs, pair-check.mjs, headless/*, preflight-overlays.sh | unchanged (§6 ships `./pipeline/*` as files, not their flags) | 41, 57 |
| repository and dist layout; the build identity | build-shell.mjs, fetch-artifacts.mjs, pin-qed64.mjs, deploy-manifest.mjs, build-gallery.mjs | `dist/qed64-build.json` (`buildId`, `leanVersion`, `sourceRevision`, `commit`, `shell`, `apiRevision`) gives `gallery/pin.json` its `apiRevision` and `shell`; the buildId is still also checked in `dist/assets/*.js`; the layout is not declared | 38, 39 |
| `infra/worker.js` `isImmutable` and the hosting headers | serve.mjs, infra/worker.js, deploy-manifest.mjs | unchanged; §5 now states the hosting facts (no Content-Encoding on chunks and `.snapz`, Range recommended, 404 not HTML) | 32 |

## What still mirrors QED64 behaviour (each kept for a stated reason)

Nothing here copies a QED64 file. These pieces of our code restate a QED64 fact or re-implement a small piece of QED64
behaviour. Each has the reason it cannot import the original:

| Ours | What it mirrors | Why it is ours |
|---|---|---|
| `gallery/lib.js` `MEMORY64_PROBE` | the Memory64 probe bytes of `public/workers/lean.worker.js` | the gallery must refuse an incapable browser *before* loading QED64; `check-gallery` asserts byte equality with the source dependency |
| `gallery/lib.js` pairing preflight (`?snapshots=` re-root rule, snapshot index schema, `BUFFER_KEY`) | `qed64-boot.ts`, `resident-session.ts`, `main.ts` | QED64 fails silently on a bad overlay index on pins A–E; the gallery checks before navigating. F, G and H name the failure (§4, §7.2; the console entry `bootFailure[4]`), but the gallery still preflights, so a broken overlay never boots; `BUFFER_KEY` is legacy-only |
| `gallery/qed64-bridge.js` | lean4monaco's InfoView message handling | repairs defects D1/D2/D3 of the shipped page on pins A–E (docs/UPSTREAM-REPORT-QED64.md); on F, G and H all three are fixed upstream (`editorRpc`, HARDENING #56; `widgetSourceCache`, EMBEDDING §2.5) and the bridge is not installed |
| `infra/worker.js` `withHeaders`, routing | QED64's `infra/worker.js` | QED64's Worker has no R2 key prefix, no HEAD with Content-Length (the gallery preflight needs it) and no Range. Its cache rule is imported, not copied. Candidate for a QED64 export (`createArtifactWorker({prefix, range, head})`) |
| `scripts/serve.mjs` | QED64's `scripts/serve-dist.mjs` + the Worker's headers | one local origin for the page, our overlays and the gallery, with the pin header (`X-Showcase-Pin`), the served release's API revision (`X-Showcase-Api`: revision, `none` or `invalid`, on every response) and `Cache-Control: no-store` for `/showcase/pin.json` |
| `scripts/fetch-artifacts.mjs` | QED64's `pipeline/release/sync-artifacts.mjs` | QED64's tool copies from a local workspace into `public/` of its own checkout; ours fetches over HTTP into `release/<id>/`, verifies against *our* lock and installs our overlays too |
| `scripts/pin-qed64.mjs verify` #1–#5, `deploy-manifest.mjs` R1–R4 | QED64's `npm run verify:release` | they check the files *we* serve (in `release/<id>/`, against our lock); `verify:release` checks QED64's own `public/` |
| `scripts/lib/olean-entries.mjs` | the ModuleData layout reader of `pipeline/artifacts/olean-imports.mjs` | QED64 exports the import list only; we need the `entries` field (where a module's IR lives) |
| `scripts/headless/wasm-lsp.mjs` | the way `pipeline/snapshot/resident-probe.mjs`/`node-runner.mjs` drive the runtime | QED64 has no Node LSP-session API; our E1/E3 verifiers need one (it imports `lsp-frames.js` from the source dependency) |
| `scripts/make-overlay.mjs` | QED64's snapshot index writer | it renames our region to `mathlib` (the page boots only `init`/`mathlib`) |
| `scripts/sim-gallery.mjs` relay/ui/editor model and v1 page model | `lsp-relay.ts`, the StatusSink, Monaco; `page-api.ts` (the frozen api, `qed64:frame-api`, events, embed mode) | a Node simulation of both page contracts the gallery assumes: runs 1–15 legacy, 16–20 v1 (a v1 run asserts that no internal is touched) |
| `scripts/lib/platform.mjs` `reclaimableBytes` | QED64's `harness.mjs reclaimableBytes()` | the same host memory rule; QED64's harness is test code, not exported |

`vendor/react/` is React's UMD builds (for `scripts/headless/react-contract.mjs`). It is not QED64 code and is pinned by
`vendor/react/SHA256SUMS`.
