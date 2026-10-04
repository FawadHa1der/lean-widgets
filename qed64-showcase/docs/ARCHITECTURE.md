# How the showcase uses QED64

The showcase serves QED64's **stock, unmodified page** with our widget packages inside it. QED64 is a
dependency of four kinds. None of them is a copy of QED64's code:

| Kind | What | How it is pinned | How a clone gets it | Checked by |
|---|---|---|---|---|
| **Source** | QED64's git tree at the served pin's commit | the git **submodule** `qed64-showcase/deps/qed64`; its gitlink *is* the served pin's source pin. Each staged pin uses a `git worktree` of the submodule's own repository at `$QED64_SHOWCASE_WORK/qed64-pins/<id>` | `git clone --recursive`; `showcase.sh bootstrap` runs `git submodule update --init` and adds worktrees if they are missing | `pin-qed64.mjs verify` #8: HEAD == the lock's commit, no tracked file modified, and for the active pin gitlink == HEAD == lock |
| **Binary** | QED64's runtime chunks, library packs and stock snapshots. Their names are content addresses, and they are not in QED64's git | `release.files` in `pins/<id>/QED64.lock.json`: the sha256 and size of each of the 145 files | `scripts/fetch-artifacts.mjs` fetches them from an artifact origin by URL path, checking sha256 against the lock. The tracked manifests come from git instead | verify #1–#6 and #10 (every byte, plus the manifests' own digests) |
| **Toolchain** (heavy path only) | the kernel fork's native64 Lean/Lake, the Docker image it runs in, the Mathlib tree it built, and QED64's slim base olean tree | `toolchain` in the lock (native64 commits and binary sha256s, Docker image id and recorded equivalents, Mathlib and ProofWidgets commits, Node version) | You build them yourself: [BUILD-FROM-SOURCE.md](BUILD-FROM-SOURCE.md) | verify #7 when `QED64_KERNEL_BUILD` is set, and N/A otherwise. `showcase.sh native` refuses a Docker image the lock does not record |
| **Page tier** (runtime) | the page's JavaScript globals, DOM and query knobs that the gallery drives | the pinned bundle itself. The gallery reads `gallery/pin.json` (generated from the lock), and the UX suite resolves the bundle name per pin | it arrives with the page, which is built from source | the gallery's static gate and the UX suite; the full list is under [Integration points](#integration-points) below |

Our own additions sit on top: the native widget oleans, the baked widget overlays `widgets7`/`widgets8`, the gallery
at `/showcase/` with its same-origin bridge, the Cloudflare Worker, and the tests.

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
                                                                  /snapshots/widgets8/ = our overlay        /showcase/ = gallery/ (iframes "/?snapshots=snapshots/widgets8")
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
  `serve.mjs`, `deploy-manifest.mjs` and our Worker import, and which wrangler bundles); `pipeline/snapshot/*` (bake,
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
`fetch-artifacts --check`, the worker tests, `lockfifo`/`lockrace`, `check-portable` and the deploy manifest.

**macOS-only (stated plainly):** the heavy path's measurement wrappers. `bake.sh`, `headless/run-stage4.sh`,
`run-e2.sh`, `run-controls.sh` and `derive-raw.sh` run under `/usr/bin/time -l` and read `stat -f`. `build-native.sh`
checks the clone's link count with `stat -f %l`. `lean/goldens/golden-env.sh` uses `cp -c`, and
`scripts/headless/hang-repro.mjs` and `scripts/assert-untouched.sh` use `vm_stat` and `stat -f`. These steps rebuild
or diagnose the overlays and were only ever run on the 36 GB Mac this project was built on. Porting them is mechanical
(GNU `time -v`, `stat -c`), but nobody has done it or tested it. The UX suite's memory figures and baselines are from
macOS Chromium.

## Integration points

Every QED64 **internal** (not a declared API) that the gallery, the tools or the tests touch today, at pin E
`33b0967`. This table is the input for a modularization proposal to the QED64 owner. QED64 is building a supported
**embedding API** (branch `feature/embedding-api`, not yet released) that will replace most of these.
[QED64-EMBEDDING-V1-REVIEW.md](QED64-EMBEDDING-V1-REVIEW.md) maps each row to the v1 draft and cites line numbers. The
"review rows" column refers to that table.

| QED64 internal | Used by (ours) | For | Shipped / tools / tests | Embedding API v1 (draft) | Review rows |
|---|---|---|---|---|---|
| `contentWindow.qed64` and `qed64.status()` (phase, version, relay, liveness, pool, header, lastDeath, rebootReason) | gallery.js (find the page, poll every 250 ms, ready/stall/death classification), lib.js, UX `QedDriver` | boot, readiness, failure cards | shipped | `qed64.api`, `api.status()`, `whenReady()`, `settled()`, events | 1, 3, 15, 16, 33, 34, 35, 43 |
| `qed64.editor` (Monaco: `getModel().setValue/getValue/getLineCount`, `setPosition`, `revealLineInCenter`, `focus`, `getPosition`, `executeEdits`) | gallery.js (switch, reset, cursor), qed64-bridge.js (D2 applyEdit) | example switching, cursor on the widget line, link edits | shipped | `setDocument`/`getDocument`/`setCursor`; no `getCursor` | 8, 9, 10, 30 |
| `localStorage['qed64.buffer']` (the boot document) and its 400 ms debounced save | gallery.js (seed before navigation), UX stock-page tests | boot an example without a flash of the previous text | shipped | `?embed=1#code=…`; the plain page's key becomes internal | 4, 5, 45 |
| `?snapshots=<dir>` dev override and the re-root rule of entry URLs (`qed64-boot.ts`) | gallery (iframe `/?snapshots=snapshots/widgets8`), lib.js preflight, storm tools | boot the stock page on our overlay | shipped | §4 `snapshots` parameter (same rule, validated) | 6, 7, 58 |
| snapshot index schema `qed64.snapshot-index/v1`, `runtime-manifest.<buildId>.json` path, the header-widen rule (only `init`/`mathlib` names; the region must be called `mathlib`) | lib.js pairing preflight, make-overlay.mjs, deploy-manifest R1–R4 | serve our region as the page's `mathlib` | shipped + tools | §7.0 exports the type; §8 adds roots/label/initialBytes | 7, 40 |
| `qed64.relay.lastText`, `relay.state.kind`, `relay.restart(opts)`, `relay.restartOpts`, `relay.session.snapshots` | gallery.js (edited detection, Restart Lean, widen a light session) | restart and recovery | shipped | `api.restart({snapshots})`, `status().snapshots` | 11, 17, 19 |
| `relay.toClient` tap (an instance override of a private method) and `relay.fromClient` injection (`showcase-live-n` hover, `$/showcase/liveness`) | gallery.js (progress and liveness probe), qed64-bridge.js (D3), UX `lsp-tap.mjs`, bring-up probes | L7 stall watchdog, proof of life, RPC coalescing, test oracles | shipped + tests | `fileProgress`/`diagnostics` events; no LSP passthrough | 12, 13, 14, 31, 42, 55 |
| `relay.makeSession` wrapped to set `session.initialBytes` | gallery.js `?mem=` | initial memory commit knob | shipped | deferred to v1.1 | 20 |
| `qed64.ui` StatusSink (`busy/progress/idle`, ProgressInfo) and `performance.getEntriesByType('resource')` | gallery.js boot wait | progress-aware boot timeout on slow links | shipped | `boot` event / `status().boot` | 21, 22 |
| page DOM: `#boot(.done)`, `#bootcard(.failed)`, `#bootlabel`, `#bar`, `#examples`, `#split/#editor/#infoview`, `#ptext`, `#action` | gallery.js (notices, stacked layout, hide the examples menu), UX specs, throttled-first-visit | layout and boot UI coordination | shipped + tests | partly (`embed=1` hides the menu); layout knobs v1.1 | 23–27, 46, 48 |
| the InfoView `postMessage` protocol of lean4monaco (`sendClientRequest`, `applyEdit`, `showDocument`, `insertText`, `{seqNum,name,args}`) | qed64-bridge.js (D1 `abortSignal` strip, D2 edits, D3 getWidgetSource coalescing), check-gallery | make RPC widgets and link edits work in the shipped page | shipped | `capabilities.editorRpc` (D1/D2 fixed upstream); D3 has no equivalent | 2, 30, 31 |
| our expandos on QED64 objects (`window.__qed64Bridge`, `__showcaseKeys`, `relay.__showcaseMem`) and an F6 capture listener on the page window | gallery.js, bridge | idempotence, keyboard escape from Monaco | shipped | none (the `__qed64*` namespace is reserved upstream) | 28, 29 |
| timing facts: the hook appears ≤ 120 s, QED64's liveness window 6 + 12 + 4 s, the boot overlay's lifetime | gallery.js constants | never race QED64's own recovery | shipped | none documented | 35, 36, 37 |
| `relay.stats` (`workerDeaths/reboots/userRestarts`), `relay.session.lean.request('telemetry')`, fault injection (`lean.died`, `onLsp/onStatus` replaced), worker globals (`__emscripten_check_mailbox`, `PThread`, `die()`, `__qed64TestExports`) | UX suite, hang capture, bring-up probes | memory figures, fault fixtures, hang capture | tests | none | 44, 49–54 |
| console labels (`[liveness]`, `[boot]`, `[qed64] …`) and the main bundle's file name and line (`@qed64-main-bundle`, notify line 627) | UX console oracle (`selectors.json`), `pin check` | console allowlist | tests | none (labels are not API) | 56 |
| the wasm runtime ABI (`_lean_wasm_load_snapshot_mem`, `_lean_wasm_shell_mark_preinitialized`, the input ring, `callMain(['--worker'])`, `$/qed64/headerStatus`) and `Qed64LspFrames` | headless/wasm-lsp.mjs, exact-header.mjs, hang-repro.mjs | headless E1/E3 verifiers in Node | tools | none (§6 ships the files, not the ABI) | 57 |
| pipeline CLIs and env: `bake-snapshot.mjs --name/--artifact/--lib/--reserve/--work/--out/--probe` with `QED64_ALLOW_LEGACY_IMPORTS=1`, `snapshot-probe.mjs --via-mem`, `supervised-run.mjs`, `olean-imports.mjs --audit`, `artifact-paths.mjs buildIdOfArtifact`, `tests/adversarial/preflight.mjs --url --no-boot` | bake.sh, stage-trees.mjs, pair-check.mjs, headless/*, preflight-overlays.sh | bake, stage and gate the overlays | tools (heavy path) | §6 ships `./pipeline/*` as files, not their flags | 41, 57 |
| repository and dist layout: `dist/**`, `public/{runtime,profiles,snapshots}` manifests, `pipeline/toolchain/KERNEL-PIN`, the buildId embedded in `dist/assets/*.js`, `frontend/` build scripts | build-shell.mjs, fetch-artifacts.mjs, pin-qed64.mjs, deploy-manifest.mjs, build-gallery.mjs | pin, build, verify and deploy a QED64 release next to the gallery | tools | none (no declared layout or build-identity file) | 39 |
| `infra/worker.js` export `isImmutable` and the hosting headers (COOP/COEP/CORP, no Content-Encoding on chunks) | serve.mjs, infra/worker.js, deploy-manifest.mjs (imported) | QED64's cache rule on our origin | shipped | hosting facts §7 (partial) | 32 |

## What still mirrors QED64 behaviour (each kept for a stated reason)

Nothing here copies a QED64 file. These pieces of our code restate a QED64 fact or re-implement a small piece of QED64
behaviour. Each has the reason it cannot import the original:

| Ours | What it mirrors | Why it is ours |
|---|---|---|
| `gallery/lib.js` `MEMORY64_PROBE` | the Memory64 probe bytes of `public/workers/lean.worker.js` | the gallery must refuse an incapable browser *before* loading QED64; `check-gallery` asserts byte equality with the source dependency |
| `gallery/lib.js` pairing preflight (`?snapshots=` re-root rule, snapshot index schema, `BUFFER_KEY`) | `qed64-boot.ts`, `resident-session.ts`, `main.ts` | QED64 fails silently on a bad overlay index; the gallery checks before navigating. The embedding API (§4, §7.0) replaces it |
| `gallery/qed64-bridge.js` | lean4monaco's InfoView message handling | repairs defects D1/D2/D3 of the shipped page (docs/UPSTREAM-REPORT-QED64.md); D1/D2 are fixed upstream by `editorRpc` |
| `infra/worker.js` `withHeaders`, routing | QED64's `infra/worker.js` | QED64's Worker has no R2 key prefix, no HEAD with Content-Length (the gallery preflight needs it) and no Range. Its cache rule is imported, not copied. Candidate for a QED64 export (`createArtifactWorker({prefix, range, head})`) |
| `scripts/serve.mjs` | QED64's `scripts/serve-dist.mjs` + the Worker's headers | one local origin for the page, our overlays and the gallery, with the pin header (`X-Showcase-Pin`) |
| `scripts/fetch-artifacts.mjs` | QED64's `pipeline/release/sync-artifacts.mjs` | QED64's tool copies from a local workspace into `public/` of its own checkout; ours fetches over HTTP into `release/<id>/`, verifies against *our* lock and installs our overlays too |
| `scripts/pin-qed64.mjs verify` #1–#5, `deploy-manifest.mjs` R1–R4 | QED64's `npm run verify:release` | they check the files *we* serve (in `release/<id>/`, against our lock); `verify:release` checks QED64's own `public/` |
| `scripts/lib/olean-entries.mjs` | the ModuleData layout reader of `pipeline/artifacts/olean-imports.mjs` | QED64 exports the import list only; we need the `entries` field (where a module's IR lives) |
| `scripts/headless/wasm-lsp.mjs` | the way `pipeline/snapshot/resident-probe.mjs`/`node-runner.mjs` drive the runtime | QED64 has no Node LSP-session API; our E1/E3 verifiers need one (it imports `lsp-frames.js` from the source dependency) |
| `scripts/make-overlay.mjs` | QED64's snapshot index writer | it renames our region to `mathlib` (the page boots only `init`/`mathlib`) |
| `scripts/sim-gallery.mjs` relay/ui/editor model | `lsp-relay.ts`, the StatusSink, Monaco | a Node simulation of the page contract the gallery assumes (to be re-modelled on the embedding API) |
| `scripts/lib/platform.mjs` `reclaimableBytes` | QED64's `harness.mjs reclaimableBytes()` | the same host memory rule; QED64's harness is test code, not exported |

`vendor/react/` is React's UMD builds (for `scripts/headless/react-contract.mjs`). It is not QED64 code and is pinned by
`vendor/react/SHA256SUMS`.
