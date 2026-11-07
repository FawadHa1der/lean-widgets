# How the showcase uses QED64

The showcase serves QED64's **stock, unmodified page** with our widget packages inside it. QED64 is a
dependency of four kinds. None of them is a copy of QED64's code:

| Kind | What | How it is pinned | How a clone gets it | Checked by |
|---|---|---|---|---|
| **Source** | QED64's git tree at the served pin's commit | the git **submodule** `qed64-showcase/deps/qed64`; its gitlink *is* the served pin's source pin. Each staged pin uses a `git worktree` of the submodule's own repository at `$QED64_SHOWCASE_WORK/qed64-pins/<id>` | `git clone --recursive`; `showcase.sh bootstrap` runs `git submodule update --init` and adds worktrees if they are missing | `pin-qed64.mjs verify` #8: HEAD == the lock's commit, no tracked file modified, and for the active pin gitlink == HEAD == lock |
| **Binary** | QED64's runtime chunks, library packs and stock snapshots. Their names are content addresses, and they are not in QED64's git | `release.files` in `pins/<id>/QED64.lock.json`: the sha256 and size of each of its files (145 for O and N; the retired pins had 145 to 147) | `scripts/fetch-artifacts.mjs` fetches them from an artifact origin by URL path, checking sha256 against the lock. The tracked manifests come from git instead | verify #1–#6 and #10 (every byte, plus the manifests' own digests) |
| **Toolchain** (heavy path only) | the kernel fork's native64 Lean/Lake, the Docker image it runs in, the Mathlib tree it built, QED64's slim base olean tree, and the runtime's `stage1/bin` (from pin I on fetched from the kernel fork's release that QED64's `toolchain/lean4-wasm64-release.json` names) | `toolchain` in the lock (native64 commits and binary sha256s, Docker image id and recorded equivalents, Mathlib and ProofWidgets commits, Node version) | You build or fetch them yourself: [BUILD-FROM-SOURCE.md](BUILD-FROM-SOURCE.md) | verify #7 when `QED64_KERNEL_BUILD` (one dir or a `:` list) holds the pin's own kernel build (matched by its NATIVE-COMMIT and MATHLIB-COMMIT; `scripts/lib/env.mjs`), and N/A otherwise, naming any candidate it rejected. `showcase.sh native` refuses a Docker image the lock does not record |
| **Page tier** (runtime) | the page's JavaScript globals, DOM and query knobs that the gallery drives (the declared embedding API v1, `qed64.api`, on every registered pin) | the pinned bundle itself. The gallery reads `gallery/pin.json` (generated from the lock), and the UX suite resolves the bundle name per pin | it arrives with the page, which is built from source | the gallery's static gate and the UX suite; the full list is under [Integration points](#integration-points) below |

Our own additions sit on top: the native widget oleans, the baked widget overlay `widgets8` (one overlay since P2; until
then also `widgets7`, without DistLens), the gallery at `/showcase/` (it drives the page through the page API; the
same-origin bridge and the legacy mode for the pre-v1 pins A–E went in P1), the Cloudflare Worker, and the tests. The
overlay keeps the logical name `widgets8` everywhere except in URLs: it is **served** at `/snapshots/<dir>/` with
`<dir>` = `scripts/lib/pins.mjs` `overlayDir` = `widgets8.<bid16>` for the schema v3 descriptor with `"overlayDirs":
"per-runtime"` (pin O: `widgets8.36d7f415704473d9`; the bare names of the retired v2 pins A–H are refused), so a new
runtime's overlay never replaces the ones an older live shell reads. The lock records the URL (`overlays.<o>.url`), `gallery/pin.json` the map (`overlays`), and the gallery
maps `?overlay=widgets8` to the directory; the Worker routes `/snapshots/*` generically, with no alias.

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
          ▲            ◄── ARTIFACT ORIGIN (our Worker: the deployed pin's runtime and packs, every uploaded pin's snapshots / serve.mjs of a built checkout / QED64's own site: its live release's files only)
          │                  /runtime/chunks/*  /profiles/*.part-*  /snapshots/*.snapz  <lock overlays.<o>.url>* (/snapshots/<dir>/*)
          └─────────────────► release/<id>/public/…   +   out/runtimes/<buildId>/overlay/widgets8/  (sha256 == lock)

   imports from the source:  infra/worker.js ── QED64 infra/edge-worker.js createWorker + toolchain/lean4-wasm64-release.json (the served pin's record)
                             serve.mjs, deploy-manifest.mjs ── QED64 infra/edge-worker.js isImmutable; deploy-manifest.mjs also its releaseRoutes
                             bake.sh ── pipeline/snapshot/bake-snapshot.mjs        stage-trees.mjs ── pipeline/artifacts/olean-imports.mjs
                             pair-check.mjs, headless/lib.mjs ── pipeline/toolchain/artifact-paths.mjs
                             headless/exact-header.mjs ── pipeline/snapshot/snapshot-probe.mjs   run-e2.sh ── supervised-run.mjs → node-runner.mjs
                             headless/wasm-lsp.mjs ── public/workers/lsp-frames.js
                             check-gallery.mjs ── public/workers/memory64-probe.js: the probe bytes
                             preflight-overlays.sh ── pipeline/release/preflight.mjs
                             pin-qed64.mjs ── toolchain/lean4-wasm64-release.json: the kernel
                             stage-trees.mjs --check-digest ── embedding/base-tree.json (385a1ac on): the served trees' digests

 one origin (serve.mjs locally, infra/worker.js on Cloudflare):  /  = release/<id>/dist (the stock page)   /runtime|profiles|snapshots/ = release/<id>/public
                                                                  /snapshots/<dir>/ = our overlay (<dir> = widgets8.<bid16>)
                                                                  /showcase/ = gallery/ (iframes "/?embed=1&snapshots=snapshots/<dir>#code=…")
 in R2 behind infra/worker.js:  /runtime/ and /profiles/ except /profiles/index.json = lean4-wasm64/<the pin's release id>/ (the kernel's, never uploaded by us)
                                /profiles/index.json and /snapshots/ = qed64-showcase/ (ours, scripts/upload-artifacts.sh)
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
  and indexes under `public/`; the kernel the pin serves (verify #9): `toolchain/lean4-wasm64-release.json`
  `kernel.commit` (QED64 `4f46477` on, so every registered pin; the `pipeline/toolchain/KERNEL-PIN` arm for the retired
  pins A–H went in P1); QED64's
  Worker library: our `infra/worker.js` is `createWorker` from `infra/edge-worker.js` with the served pin's
  `toolchain/lean4-wasm64-release.json`, both bundled by wrangler (the `release` option is QED64 `391a075`, in every pin
  from I on and not in H, whose Worker, the rollback target's, is our earlier one); QED64's cache rule `isImmutable`:
  `serve.mjs` and `deploy-manifest.mjs` import it from `infra/edge-worker.js` (every registered pin has it; the
  `infra/worker.js` fallback for pins before 84d594e went in P1), and the Worker has it inside `createWorker`; `pipeline/snapshot/*` (bake,
  probes, runner); `pipeline/artifacts/olean-imports.mjs`; `pipeline/toolchain/artifact-paths.mjs`;
  `public/workers/lsp-frames.js`; the Memory64 probe bytes the gallery gate compares (`public/workers/memory64-probe.js`
  from 385a1ac on, evaluated in a `vm` context; `public/workers/lean.worker.js` before, until P1); QED64's preflight
  (`pipeline/release/preflight.mjs` from 385a1ac on, where `tests/adversarial/preflight.mjs` is a one-cycle shim;
  `tests/adversarial/preflight.mjs` before, until P1); `embedding/base-tree.json` (the served trees' digests, 385a1ac on).
  `verify` #8 fails if a vendored copy (`pins/*/QED64-PIN`, `pins/*/vendor-qed64`, `vendor/qed64`) reappears.
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
  (`{index.json, init.<d>.snapz, widgets.<d>.snapz}` under the lock's `overlays.<o>.url`, `/snapshots/widgets8.<bid16>/`
  (O: `36d7f415704473d9`); a url that disagrees with `scripts/lib/pins.mjs` `overlayUrl` is refused before anything is
  fetched) are installed into `out/runtimes/<buildId>/overlay/widgets8/` and checked against the lock's `overlays`
  section.
* **Origins:** `--origin` (`ARTIFACT_ORIGIN`) is the showcase's own origin. It serves QED64's files and our overlays at
  exactly these paths: the deployed Worker, or `scripts/serve.mjs` of a checkout that has the files. `--qed64-origin`
  (`QED64_ARTIFACT_ORIGIN`) serves QED64's files only, and QED64's live site serves them for **one** release, the one
  it deploys now: since QED64 `4b98279` its Worker reads `/runtime/*` and `/profiles/<not index.json>` only from that
  release's prefix `lean4-wasm64/<id>/`, with no fallback to the bucket root (whose `runtime/` and `profiles/` copies
  were removed on 2026-10-23), and its R2 sweep of 2026-10-23 kept only the live and the previous pairing's
  `/snapshots/` (QED64 `docs/DEPLOY.md`, "Atomic deploys"). So it can bootstrap only the pin whose release QED64
  deploys now. Under release routing our deployed Worker has the same limit for the runtime and packs: it serves only
  the deployed pin's, from that pin's release. Bootstrapping or rolling back to any other pin (N, H or older) therefore
  needs `scripts/serve.mjs` of a checkout that has those files as `--origin`. Our prefix keeps every uploaded pin's
  `/snapshots/` objects, because our upload copies and never deletes and they are digest-named, and the deployed Worker
  serves them. Overlay indexes are the exception: an overlay's `index.json` is named only by its directory, the
  per-runtime one that same-runtime pins share (L and N; the bare `widgets{7,8}/` of the retired pins A–H, H's, stay
  untouched). That key holds the last upload's index, so an older pin whose index differs fails the lock check for that
  file; its digest-named `.snapz` stay. A file that QED64's origin, tried last, fails to deliver
  gets that advice in its error. These are plain GETs from Node; CORP/COEP do not apply to them. `--remote-check` HEADs
  every file first. QED64's Worker omits Content-Length on HEAD, so for it the tool reads the GET headers instead.
* **Proved on 2026-10-04:** a fresh clone fetched all 81 binary files of pin E (1.38 GB) from
  `https://qed64.fawadworkaddress.workers.dev` with sha256 equal to the lock (before QED64 `4b98279`: that origin served
  E's files then, and no longer does, see Origins above). That run was interrupted once deliberately after 30 s and
  resumed: 22 kept, 65 installed, 0 failed (`$W/logs/r2/clone-fetch-live-*.log`). The overlays (761.5 MB) came from a
  local origin (`serve.mjs` of the main checkout on :5297; `clone-bootstrap-1.log`). The Linux rehearsal fetched all 93
  files from the same local origin.

The deployed Worker has only the overlays uploaded to it (since 2026-11-05 O's `widgets8.36d7f415704473d9/`, beside
O's `widgets7.36d7f415704473d9/`, unused after P2 but kept while O is a rollback target, and H's bare `widgets{7,8}/`,
kept while H is). Any other pin's
overlays exist only on machines that baked them until they are uploaded. A cloner without such an
origin either points `--origin` at someone's served checkout or rebuilds the overlays ([BUILD-FROM-SOURCE.md](BUILD-FROM-SOURCE.md)).

## What a clone needs

| To … | Needs | Not needed |
|---|---|---|
| serve and test the showcase (`bootstrap`, `verify`, `gallery`, `serve`, `ux`) | git, Node 26 (the lock records v26.3.0; another 26.x is a DRIFT, see below), npm, network access to GitHub/npm and to an artifact origin, Playwright's Chromium (`npx playwright install chromium chromium-headless-shell`) for `ux`, a machine with 16 GB of RAM for the browser | `QED64_REPO`, the kernel build, Docker |
| rebuild the overlays | the kernel fork's native64 toolchain, its Docker image, the Mathlib tree it built, QED64's slim base tree, and about 36 GB of RAM: [BUILD-FROM-SOURCE.md](BUILD-FROM-SOURCE.md) | – |

A checkout that serves fetched artifacts has no build stores of its runtime (`$W/runtimes/<bid>/`, `out/headless`).
`pin current`, `pin check` and `verify` print them as **ABSENT**, and print a staged pin that was never bootstrapped as
**NOT MATERIALIZED**. Neither counts as a failure, because what is served is still checked file by file against the
lock. `verify` prints a pin whose `pin.json` carries `"retired": "<why>"` as **RETIRED**, also not a failure. Such a
pin's stores are known not to match its lock: pins I and J lost their overlay when K rebaked the runtime store they
share (both retired again in P1: no registered pin carries the field now, but N is the next to need it). `pin list`
and `pin check` name the reason, and `pin use` refuses the pin. **N/A** marks a rebuild-only
input that is missing on this host, such as the kernel build or a downloaded
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
| is a browser running | `ps -axo pid=,comm=` (argv[0]) | `/proc/<pid>/exe` |

The Linux side was proved in Docker `node:26-bookworm` (aarch64) on 2026-10-04 (`$W/logs/r2/linux-rehearsal-1.log`):
fresh `clone --recursive`, bootstrap from a local origin, `verify` and `gallery` all passed, and so did
`fetch-artifacts --check`, the worker tests, `lockfifo`/`lockrace`, `check-portable` and the deploy manifest. The CI job
(`qed64-static` in `.github/workflows/lean-ci.yml`; until 2026-10-04 `showcase-source.yml`) needs no artifact origin: it rebuilds the page from the submodule, installs the
tracked manifests with `fetch-artifacts --git-only`, and runs the worker tests and the gallery gate. Its steps passed
in the same image (`linux-ci-mirror-2.log`).

**macOS-only (stated plainly):** the heavy path's measurement wrappers. `bake.sh`, `headless/run-stage4.sh`,
`run-e2.sh`, `run-controls.sh` and `derive-raw.sh` run under `/usr/bin/time -l` and read `stat -f`. `build-native.sh`
checks the clone's link count with `stat -f %l`. `lean/goldens/golden-env.sh` uses `cp -c`, and
`scripts/assert-untouched.sh` uses `vm_stat` and `stat -f` (as `scripts/headless/hang-repro.mjs` did until P1). These steps rebuild
or diagnose the overlays and were only ever run on the 36 GB Mac this project was built on. Porting them is mechanical
(GNU `time -v`, `stat -c`), but nobody has done it or tested it. The UX suite's memory figures and baselines are from
macOS Chromium.

## Integration points

Every QED64 interface the gallery, the tools and the tests touch. Both registered pins, O `521cf3f` and N `58ebbad`,
implement the embedding contract v1 (`deps/qed64/docs/EMBEDDING.md`, revision `1.0.0`; first shipped in F `84d594e`,
G added the edit back-pressure `e4cffcc`, H the keep-alive fix), and the gallery drives the page through that declared
API only. `gallery/pin.json` `apiRevision`, which `scripts/build-gallery.mjs` reads from the pin release's
`dist/qed64-build.json`, is required. `/showcase/pin.json` is served `Cache-Control: no-store`. **Until P1
(2026-11-07)** the pre-v1 pins A–E ran the gallery in a **legacy mode** on QED64 internals (`contentWindow.qed64`,
`qed64.editor`, `relay` taps, `qed64.ui` wraps, the `qed64.buffer` seed, `relay.makeSession` for `?mem`, and
`gallery/qed64-bridge.js` for D1–D3), and `serve.mjs` sent `X-Showcase-Api` so the gallery could follow a staged pin's
release; P1 deleted all of it (the table's legacy column is in git history at the tag `pins-history-2026-11-07`).
[QED64-EMBEDDING-V1-REVIEW.md](QED64-EMBEDDING-V1-REVIEW.md) maps each row to the v1 draft (2026-10-04) and, in its
"Adoption" section, to what F's API became (G's and H's API keeps revision `1.0.0`; `e4cffcc` adds the `?edithold=<n>` boot parameter to §4, a note that a `telemetry` reply may follow a `status` event, and the back-pressure and local cancel replies to §7.8); the "Review rows" column refers to
its table. The gallery's side of v1 is described in gallery/README.md "Embedding API v1".

**Page tier: what the gallery uses.**

| Interface | The registered pins (v1) | Review rows |
|---|---|---|
| finding the page and its status | the frozen `qed64.api` from the `qed64:frame-api` CustomEvent on the gallery window (`detail.frame === iframe.contentWindow`; fallback a polled frozen `pageWin().qed64.api`), bound to the document that published it; `api.status()` (synchronous) polled the same way. `api.settled()`/`whenReady()` are not used: the waits stay polling-based so supersession and the progress-aware boot timeout keep working | 1, 3, 15, 16, 33, 34, 35, 43 |
| capabilities | required: `documents`, `events`, `embedMode`, `restart`, `editorRpc` (since P1; else the hard boot card, `status().api.missing`); `widgetSourceCache` (one `console.warn` without it); `liveness` (the gallery's own probe is gone, `status().liveness.probe 'stood-down'`) | 2 |
| the document and the cursor | `api.setDocument(text, {cursor, focus: false, undoable: false})` (resolves `{version, unchanged}`), `api.getDocument()`, `api.setCursor(pos, {focus})` after ready, `api.getCursor()`, `api.focus()` | 8, 9, 10, 11 |
| the boot document | `/?embed=1&snapshots=snapshots/<overlay>[&memory=<GiB>]#code=<example>`; the page neither reads nor writes `qed64.buffer`; `about:blank` first is kept (it releases the old runtime and a `#code=`-only change would not reboot) | 4, 5, 45 |
| persistence and frame reloads | the `document` event into our key `qed64-showcase:document` (at most once per second, flushed on `pagehide`); a reload the gallery did not start is adopted by a synchronous `api.setDocument(newest forwarded text)` in the `qed64:frame-api` handler (§3.1's 5 s window). When a boot cannot keep the text it displaces from the key (a quota error), the gallery **holds** the key instead of overwriting it, and edits stay in memory. A memory-only text that cannot be kept becomes **unsaved**. A storage notice says where each text is (with **Copy it** for an unsaved text, whose × is then hidden). A held tab retries at most every 5 s, with one timer and no polling, and `beforeunload` asks first while a text is at risk. All of this is ours, in `localStorage` (gallery/README.md "When storage is full or blocked") | 7, 18 |
| restart, widen, the offer | `api.restart()` (the relay's own header rule; stall events' `how` `'api.restart'`), `api.restart({snapshots:['init','mathlib']})` on `headerRefused` with `status().snapshots` lacking `mathlib`; `status().offer` / `api.acceptOffer()` | 17, 19 |
| progress, stall watchdog, proof of life | the `fileProgress` and `diagnostics` events (`origin: 'qed64'` = the page's own notes, not proof of life); `status().stall.source 'api-events'` | 12, 13 |
| liveness | the probe stands down (`status().liveness.probe 'stood-down'`); QED64's projection `status().liveness {stalled, lastAnswerAgoMs, lastFrameAgoMs, …}` and the `liveness`, `reboot` and `death` events; the 45 s card is the gallery's recovery | 14, 15, 16, 36 |
| boot progress and failures | the `boot` and `status` events, `status().boot {done, failed, message, overlay}`; the page's resource timing entries (a standard Web API of the frame window) still count as boot progress | 21, 22, 23, 24 |
| memory knob `?mem=` | `&memory=<GiB>` on the frame URL; `status().mem.applied` compares `status().memory.initialBytes` | 20 |
| the InfoView's postMessage protocol | not touched: the page repairs D1/D2 itself (HARDENING #56, `editorRpc`, required) and caches widget sources (§2.5, `widgetSourceCache`); the bridge that did this on pins A–E is gone | 2, 30, 31 |
| layout | **the one remaining internal dependency:** the same stacking `<style>` (Monaco follows the resize by itself; no `editor.layout()`); `embed=1` hides `#examples` (the gallery's rule stays as a no-op); the slow notice keeps its CSS position. Runtime styling only: it never throws and never fails a boot when the ids are missing. `layout=` is v1.1 | 25, 26, 27 |
| our listeners and expandos | the F6 listener and `__showcaseKeys` only (§9 allows an embedder's listeners on the framed window) | 28, 29 |
| timing facts | the hook within 120 s (`qed64:frame-api` fires at module start); the liveness window is QED64's own business | 35, 36, 37 |
| overlay and preflight | `?snapshots=<dir>` and its re-root rule; snapshot index `qed64.snapshot-index/v1`; `runtime-manifest.<buildId>.json`; the region named `mathlib`: §4 validates `snapshots`, and §8 declares the overlay index; our region still carries the name `mathlib` | 6, 7, 40, 58 |

**Tools and tests: what is still internal on the v1 pages** (none of it is shipped to visitors):

| Interface | Used by | On the v1 pages | Review rows |
|---|---|---|---|
| `qed64.relay` counters (`stats`), `relay.session.snapshots`, `relay.lastText.length`, `status().pool` | UX `QedDriver` (`tests/ux/lib/qed64.mjs`), W1–W8, C16, C20, C23 | still read from the relay: §9 lists `stats()` and `rawStatus()` in the unstable test hatch `qed64.test`, not yet adopted. The driver's status fields come from `api.status()` | 43, 54 |
| telemetry (wasm heap) | `Gallery.telemetry()`, hang capture step (b), memprobe | `qed64.test.telemetry()` (the hatch, §9: tests only) when present, else `relay.session.lean.request('telemetry')` | 44 |
| fault injection: `session.onLsp/onStatus` replaced (C21), worker `die()` (C23), `lean.died()` (bring-up) | C21, C23, `bringup/questions.mjs` | unchanged; `inject`/`freeze` are v1.1 | 50, 51, 53 |
| the LSP tap on `relay.toClient/fromClient` | `tests/ux/lib/lsp-tap.mjs` (console pairing of `-32800` and, on F, G and H, `-32801` replies; on G and H also QED64's local `-32800` cancel replies, `qed64Kind` `'cancelled'`; on G Lean's `-32900` replies for C22's keep-alive scenario; frame counts) | unchanged; on F, G and H it wraps the page's own taps (`relay-taps.ts`). `qed64.test.lsp.on()` is the sanctioned replacement, not yet adopted | 42, 55 |
| worker globals (`__emscripten_check_mailbox`, `PThread`, `__qed64TestExports`) | hang capture, `tools/qed64-liveness.mjs` | unchanged (§9 names `__qed64TestExports` the worker's test hook) | 49, 52 |
| page DOM and Monaco/InfoView DOM | UX specs (pill, boot card, action button, `.monaco-editor`, the InfoView iframe), throttled first visit, visual baselines | unchanged; the stock-page tests still seed `qed64.buffer` on the plain page | 46, 47, 48 |
| console labels and the main bundle's notify line (`@qed64-main-bundle`, line0 627, sha256 per pin in `pins/<id>/pin.json` `consoleSites`) | UX console oracle (`selectors.json`), `pin check` | unchanged, plus the v1 pins' `-32801` ContentModified entry (edit coalescing, §7.8) and, for G and H (`e4cffcc`, §7.8), the `-32800` entry `QED64: the client cancelled this request before it reached the checker`, paired from one `-32800` reply pool shared with the empty-text entry; on G only, C22's `rpcKeepAliveStarved` scenario; the notify line is line0 627 sha256 `46b0155c…` on G, `fc6ad361…` on H and `28b8d70e…` on I (`/assets/index-DDUZGVEB.js`); on I the `networkCut` warning also accepts #63's wording `the transfer of <file> ended early: received <n> of <m> bytes` | 56 |
| the wasm runtime ABI (`_lean_wasm_load_snapshot_mem`, the input ring, `$/qed64/headerStatus`) and `Qed64LspFrames` | headless/wasm-lsp.mjs, exact-header.mjs (and, until P1, hang-repro.mjs) | unchanged | 57 |
| pipeline CLIs and env (`bake-snapshot.mjs …` with `QED64_ALLOW_LEGACY_IMPORTS=1`, `snapshot-probe.mjs --via-mem`, `supervised-run.mjs`, `olean-imports.mjs --audit`, `artifact-paths.mjs`, the preflight: `pipeline/release/preflight.mjs`; `tests/adversarial/preflight.mjs` before I, whose arm went in P1) | bake.sh, stage-trees.mjs, pair-check.mjs, headless/*, preflight-overlays.sh | unchanged (§6 ships `./pipeline/*` as files, not their flags); at 385a1ac `bake-snapshot.mjs` also writes `index.<buildId>.json` into `--out`, which `make-overlay.mjs` and judge J5 ignore | 41, 57 |
| repository and dist layout; the build identity | build-shell.mjs, fetch-artifacts.mjs, pin-qed64.mjs, deploy-manifest.mjs, build-gallery.mjs | `dist/qed64-build.json` (`buildId`, `leanVersion`, `sourceRevision`, `commit`, `shell`, `apiRevision`) gives `gallery/pin.json` its `apiRevision` and `shell`; the buildId is still also checked in `dist/assets/*.js`; the layout is not declared | 38, 39 |
| `isImmutable` (`infra/edge-worker.js`) and the hosting headers | serve.mjs, deploy-manifest.mjs; infra/worker.js inside `createWorker` | unchanged; §5 now states the hosting facts (no Content-Encoding on chunks and `.snapz`, Range recommended, 404 not HTML); at 385a1ac the rule also revalidates the per-build index copies (`index.<bid>.json`, `profiles-index.<bid>.json`) | 32 |

## What still mirrors QED64 behaviour (each kept for a stated reason)

Nothing here copies a QED64 file. These pieces of our code restate a QED64 fact or re-implement a small piece of QED64
behaviour. Each has the reason it cannot import the original:

| Ours | What it mirrors | Why it is ours |
|---|---|---|
| `gallery/lib.js` `MEMORY64_PROBE` | the Memory64 probe bytes of `public/workers/memory64-probe.js` (`globalThis.Qed64Memory64.MEMORY64_PROBE`; the `lean.worker.js` literal of pins A–H is no longer read) | the gallery must refuse an incapable browser *before* loading QED64; `check-gallery` asserts byte equality with the source dependency by evaluating `memory64-probe.js` in a `vm` context |
| `gallery/lib.js` pairing preflight (`?snapshots=` re-root rule, snapshot index schema) | `qed64-boot.ts`, `resident-session.ts` | the v1 pages name the failure (§4, §7.2; the console entry `bootFailure[4]`; from I on #62 refuses an unpaired overlay before the runtime boots), but the gallery still preflights, so a broken overlay never boots (pins A–E failed silently; `BUFFER_KEY`, the legacy seed key, went in P1) |
| `scripts/lib/release-routing.mjs` `releaseKey` | which R2 key QED64's `createWorker` reads a URL path from (`infra/edge-worker.js` keeps its own function private) | `deploy-manifest.mjs` must list each file under the key the Worker reads; `infra/worker.test.mjs` runs the real Worker over every file of the active pin's lock against it. The Worker itself no longer mirrors anything: it is `createWorker` with our prefix, our root redirect and the pin's release |
| `scripts/serve.mjs` | QED64's `scripts/serve-dist.mjs` + the Worker's headers | one local origin for the page, our overlays and the gallery, with the pin header (`X-Showcase-Pin`) and `Cache-Control: no-store` for `/showcase/pin.json` (`X-Showcase-Api` went in P1) |
| `scripts/fetch-artifacts.mjs` | QED64's `pipeline/release/sync-artifacts.mjs` | QED64's tool copies from a local workspace into `public/` of its own checkout; ours fetches over HTTP into `release/<id>/`, verifies against *our* lock and installs our overlays too |
| `scripts/pin-qed64.mjs verify` #1–#5, `deploy-manifest.mjs` R1–R4 | QED64's `npm run verify:release` | they check the files *we* serve (in `release/<id>/`, against our lock); `verify:release` checks QED64's own `public/` |
| `scripts/lib/olean-entries.mjs` | the ModuleData layout reader of `pipeline/artifacts/olean-imports.mjs` | QED64 exports the import list only; we need the `entries` field (where a module's IR lives) |
| `scripts/headless/wasm-lsp.mjs` | the way `pipeline/snapshot/resident-probe.mjs`/`node-runner.mjs` drive the runtime | QED64 has no Node LSP-session API; our E1/E3 verifiers need one (it imports `lsp-frames.js` from the source dependency) |
| `scripts/make-overlay.mjs` | QED64's snapshot index writer | it renames our region to `mathlib` (the page boots only `init`/`mathlib`) |
| `scripts/sim-gallery.mjs` v1 page model | `page-api.ts` (the frozen api, `qed64:frame-api`, events, embed mode) | a Node simulation of the page contract the gallery assumes; every run asserts that no internal is touched (the legacy relay/ui/editor model went in P1) |
| `scripts/lib/platform.mjs` `reclaimableBytes` | QED64's `harness.mjs reclaimableBytes()` | the same host memory rule; QED64's harness is test code, not exported |

`vendor/react/` is React's UMD builds (for `scripts/headless/react-contract.mjs`). It is not QED64 code and is pinned by
`vendor/react/SHA256SUMS`.
