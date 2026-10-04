# The lean4game port (/Users/fawadhaider/code/wasm64-lean4game) as the precedent for a project that depends on QED64 without changing it. I read it on 2026-09-30, read-only. Its working tree has uncommitted edits (git status shows M on client/src/wasm/game-boot.ts, games-api.ts, game-cache.ts, level.tsx, typewriter.tsx, index.tsx, sw.template.js and wasm/UX-PARITY.md), so the line numbers below are from that working tree. Branch: wasm64-port, HEAD 4c7a416. The files in the task list were all read. NOTES.md and README.md are upstream lean4game hosting docs (nginx, pm2, bubblewrap) and say nothing about wasm.

## Facts
- (1a) QED64 is NOT a git submodule. The only submodule is the kernel fork at wasm/kernel. It is marked update=none, so a plain clone leaves it empty.
  - EVIDENCE: .gitmodules: [submodule "wasm/kernel"] url=https://github.com/FawadHa1der/lean4.git, branch=qed64-wasm64, update=none. `git ls-tree HEAD wasm/kernel` → 160000 commit 992dc94b2de491878cca61aca382ed31286f3a86. wasm/KERNEL.md:249-263 and :257 say the former wasm/qed64 submodule is gone. Commit 3c1aee0 (2026-09-04): 'Independent of the qed64 checkout: vendor the pipeline, drop the qed64 submodule'.
- (1b) The port vendors exactly 10 QED64 browser files into client/src/wasm/vendor/qed64/, keeping their QED64 relative paths.
  - EVIDENCE: scripts/sync-qed64.sh:30-33 PATHS = frontend/src/{qed64-boot,resident-session,lsp-relay}.ts, src/install/profiles.ts, src/runtime/{client,snapshots}.ts, public/workers/{lean.worker,lsp-frames,lsp-front-door,snapshot-prefetch.worker}.js. Lines (wc -l): 186+225+219 TS frontend, 642+425+71 src, 1489+203+474+174 workers = 4108.
- (1c) It also vendors 12 QED64 pipeline scripts into a separate root, wasm/vendor/qed64-pipeline/. The separate root keeps the pipeline's work/ scratch dirs out of client/src.
  - EVIDENCE: scripts/sync-qed64.sh:38-43 PIPELINE = pipeline/toolchain/{chunk-runtime.mjs,artifact-paths.mjs,gen-exports.py,gate.mjs}, pipeline/snapshot/{persistent-probe,bake-snapshot,node-runner,snapshot-probe}.mjs, pipeline/artifacts/{pack,unpack,inspect}.mjs, pipeline/release/verify-release.mjs (+ optional artifact-paths.d.mts).
- (1d) The vendored commit is qed64 32e5e62566826a1042a916af67681754d1ff12d0 (2026-09-07, 'plan: post-removal pyramid numbers'). The pin lives in client/src/wasm/vendor/QED64-PIN: full commit, date, subject, and a sha256[:16] for every file.
  - EVIDENCE: client/src/wasm/vendor/QED64-PIN:1-27. It is written by scripts/sync-qed64.sh:79-85. Commit 13d4faa (2026-09-07) 'Substrate: qed64 closure 32e5e62 (resident transport), kernel 0032, new pairing wasm64-d77d34b97592d014'.
- (1e) How the pin is enforced:
- The sync script extracts with `git archive <sha>`, never from a working tree (sync-qed64.sh:55,60).
- It validates every path before touching anything (:47-49).
- It fails if a relative import inside the vendored .ts files does not resolve (:64-78).
- build-from-source.sh preflight only WARNS when a QED64_DIR checkout differs from the pin (:162, :257).
- No script or CI step re-hashes the vendored files against the hashes in QED64-PIN; only 4 files reference QED64-PIN at all. I re-hashed all 10 by hand: all match.
  - EVIDENCE: `grep -rln QED64-PIN` → wasm/build-from-source.sh, wasm/KERNEL.md, scripts/sync-qed64.sh, client/vite.config.ts only. .github/workflows/{deploy,test}.yml contain no pin check. Manual shasum: 10/10 OK.
- (1f) The import specifier `qed64/...` resolves to the vendored tree through a vite alias plus a tsconfig path. The vite `define` __QED64_BUILD_ID__ is taken from the shipped runtime manifest, so the shell asks for the immutable runtime-manifest.<buildId>.json first.
  - EVIDENCE: client/vite.config.ts:128-136 (alias qed64 → ./src/wasm/vendor/qed64), :41-48 and :87-94 (define). client/tsconfig.json:21-22 paths 'qed64/*'. The vendored qed64-boot.ts:46,57-66 reads __QED64_BUILD_ID__, then ?runtime=, then the mutable manifest.
- (1g) The worker scripts are copied from the vendored closure into client/public/workers/ by scripts/stage-workers.sh. That directory is gitignored. The deploy script refuses a tree without them.
  - EVIDENCE: scripts/stage-workers.sh:9-22. client/.gitignore:8 'public/workers/'. scripts/deploy-app.sh:13,26-29. UX-PARITY.md:249-262 (item 19: the first CI deploy shipped no workers and hung at 'starting Lean').
- (1h) The QED64 closure the port vendors is almost identical to QED64 HEAD (1859b83, one commit after promote 965c249):
- Unchanged since 32e5e62: the 4 worker scripts, resident-session.ts, lsp-relay.ts, client.ts and snapshots.ts (same sha256[:16] as the pin).
- Changed: qed64-boot.ts (adds the ?profiles= reroot) and profiles.ts (installProfile gains a reroot arg).
- In the pipeline: bake-snapshot.mjs gained `--work`, and pack.mjs now imports ./olean-imports.mjs, which is NOT in the sync script's PIPELINE list.
  - EVIDENCE: `git -C qed64 diff --stat 32e5e62 HEAD` over the closure paths. `git show HEAD:pipeline/artifacts/pack.mjs | grep ^import` → line 40 `import { oleanImports } from "./olean-imports.mjs"`. HEAD bake-snapshot.mjs diff: `const work = path.resolve(root, arg("work", "work/snapshot"))`.
- (1i) The port runs on an OLDER pairing than the one the widgets need. The port serves Lean 4.33.0-pre, runtime wasm64-d77d34b97592d014, kernel 992dc94 and Mathlib pack de3a9cf. QED64 serves Lean 4.34.0, runtime wasm64-4b025db7729c5f89, kernel 9fbb45afcb and Mathlib 5ed2965. The port's artifacts, Mathlib pack and compat lane therefore cannot be reused for the widgets.
  - EVIDENCE: client/public/runtime/runtime-manifest.json: buildId wasm64-d77d34b97592d014, leanVersion 4.33.0-pre, sourceRevision qed64-wasm64@992dc94b2. wasm/KERNEL-PIN:1. wasm/PORTING.md:14-21. qed64 public/runtime/runtime-manifest.json: wasm64-4b025db7729c5f89, 4.34.0, qed64-wasm64@9fbb45afcb. qed64 pipeline/toolchain/KERNEL-PIN (HEAD).
- (2a) The port subclasses ResidentSession as GameSession. It calls super.start() and then writes the gamedata JSON into the worker FS through the private LeanSession.request('write-files'). Because the relay awaits start() on every boot and on every crash reboot, the files exist before the loop is armed.
  - EVIDENCE: client/src/wasm/game-boot.ts:236-245 (class GameSession extends ResidentSession). WORKER_GAMEDATA_DIR=/workspace/.lake/gamedata at :188-189 region ("Worker cwd is /workspace").
- (2b) The boot policy is plain data: snapshotsFor always returns [<game snapshot>], so the init snapshot is not loaded. initialBytesFor is sized from the served index region bytes, and there is a maximumBytes cap. The formula: initial = max(1 GiB, ceil(1.1×region / 256 MiB)×256 MiB); cap = max(3 GiB, initial+1 GiB).
  - EVIDENCE: game-boot.ts:247-271 gamePolicy(). client/src/wasm/games-api.ts:238-243 gameMemoryPolicy(). The vendored ResidentPolicy interface is at resident-session.ts:27-40 and the defaults at :101-110 (EDITOR_POLICY, DEFAULT_MAXIMUM_BYTES 6 GiB).
- (2c) The port supplies its own artifacts instead of the vendored installArtifacts. installGameArtifacts returns { runtime, index, installed: new Map(), snapshots }: no core profile pack, so leanPath is "", and a missing profile index is tolerated. Before any byte moves, checkSnapshotPairing checks three things: the snapshot is in the index, entry.runtime === the shell's buildId, and the object exists (HEAD; a 404 or an HTML SPA-fallback response means missing).
  - EVIDENCE: game-boot.ts:113-145 (checkSnapshotPairing), :147-182 (installGameArtifacts, with the rationale). UX-PARITY.md:481-500 measures the pack skip: 582 MB vs 702 MB on the wire.
- (2d) Relay wiring: `new LspRelay((opts) => new GameSession({artifacts, ui, policy, headerText: relay?.lastText ?? ''}, files, opts ?? {}), {status}, networkAwareSettle)`. Then `pagehide → relay.unload()` and `translation.attachServer(relay.clientPort)`, plus globalThis.qed64GameRelay as the test oracle. QED64's own page does the same with ResidentSession plus EDITOR_POLICY and `headerText: relay?.lastText || initialText`.
  - EVIDENCE: game-boot.ts:912-946. qed64 frontend/src/main.ts:340-344 (initialText from localStorage 'qed64.buffer' or EXAMPLES.mathlib), :395-400 (LspRelay), :401 (pagehide), :418-439 (LeanMonaco WorkerDirect messagePort, editor.start(editorEl, '/project/Probe.lean', initialText)).
- (2e) The initial document in the port is NOT a QED64 boot input. The editor (lean4monaco) opens a synthetic level uri. GameTranslation is a MessagePort middleman that rewrites every didOpen and full-text didChange into `import <level module> import GameServer.Runner \nRunner ... := by\n<player text>` and shifts positions by 2 lines. lean4monaco is pointed at the port through LeanMonacoOptions.websocket = {$type:'WorkerDirect', messagePort: gameLspPort()}.
  - EVIDENCE: client/src/wasm/game-translation.ts:1-30 and :326-331. client/src/store/editor-atoms.ts:21-44. client/src/app.tsx:54-74. client/src/wasm/level-uri.ts.
- (2f) The port does NOT use the stock InfoView. It renders its own EditorConnection and sets lean4.infoview.autoOpen=false. It strips widget embeds to their alt text (L3 fix, msg-embed.ts). Its npm tree has lean4monaco 1.1.9 with a nested @leanprover/infoview 0.8.5. QED64's frontend uses lean4monaco 1.1.16 with @leanprover/infoview 0.11.1 and the real InfoView iframe. So the port is a precedent for the substrate and deployment, NOT for rendering widgets.
  - EVIDENCE: editor-atoms.ts:39-42. app.tsx:58-62. UX-PARITY.md:751 (L3) and :787. node_modules versions read from package.json files. qed64 frontend/package.json (lean4monaco 1.1.16) and frontend/package-lock.json:1175-1178 (infoview 0.11.1). qed64 frontend/vite.config.ts:47-56 copies @leanprover/infoview/dist/* and lean4monaco webview.js to /infoview.
- (3a) Bake mechanics. bake-snapshot.mjs writes `--probe` text as work/probe.lean, runs node-runner.mjs (the exact wasm runtime under Node) with `--incr-header-save=/work/<name>.snap`, gzips the result to `<name>.<sha16>.snapz`, and upserts an index entry {name,url,digest,bytes,transfer,imports,runtime}.
- `imports` = the probe's import lines. That is how the header is chosen.
- `runtime` = sha256(lean.wasm)[:16] of --artifact.
- It refuses to mix runtimes in one index and refuses an --out inside public/.
  - EVIDENCE: wasm/vendor/qed64-pipeline/pipeline/snapshot/bake-snapshot.mjs:15 (usage), :31-44 (artifact/buildId), :50-64 (mixed-index refusal), :66-82 (probe.lean, runner args), :88 (reserve default 3.5 GiB), :160-195 (entry and importsOf).
- (3b) The port's bake lane calls `bake_one <name> <lib-tree> <reserve> [probe]` → `QED64_ALLOW_LEGACY_IMPORTS=1 node --stack-size=8192 bake-snapshot.mjs --name --artifact $S1 --lib <tree> --reserve --out $STG/snapshots [--probe]`. --verify-snapshots then runs `snapshot-probe.mjs --via-mem --artifact --snap work/snapshot/<name>.snap --lib <tree> --workspace <src> --probe-file <pf> --budget-ms 600000`.
  - EVIDENCE: wasm/build-from-source.sh:493-498 and :573. QED64_ALLOW_LEGACY_IMPORTS is kernel patch 0030 (tolerate legacy non-module oleans): qed64 pipeline/toolchain/PATCHES.md:203-212, node-runner.mjs:119-120.
- (3c) The pipeline is run from a COPY. The vendored pipeline is rsynced to wasm/out/pipeline on every run, because the 32e5e62 bake-snapshot.mjs hardcodes its work dir under its own root and nothing may be written under wasm/vendor. Setting QED64_DIR runs a QED64 checkout in place. For us that would write into the read-only QED64 repo.
  - EVIDENCE: wasm/KERNEL.md:287-292. build-from-source.sh:56-63 (QED64_DIR doc) and :127. HEAD bake-snapshot.mjs now accepts --work (diff in fact 1h).
- (3d) Olean trees are hard-linked overlays:
- overlay = `rsync -a --link-dest=<base> <base>/ <new>/` plus package dirs on top.
- Slim per-game trees drop *.olean.private (SLIM_TREES=1), which makes snapshots about 60% smaller.
- Packages are compiled without Lake by wasm/scripts/compile-pkg.py: `lean <src> -o <olean> --root <src> $LEAN_OPTS` in import order, incremental, with the native compiler inside Docker.
  - EVIDENCE: build-from-source.sh:207-217 (overlay, overlay_game) and :199-205 (docker_run, compile_pkg). wasm/scripts/compile-pkg.py:1-46. KERNEL.md:150-162 (stg4 slim 665 MB raw vs nng4 fat 1,466 MB).
- (3e) Pairing a bake with a runtime without rebuilding the kernel is documented, in prose only. Reassemble the pinned runtime from the sha256-verified served chunks into an artifact dir with bin/lean.{js,wasm}, then run bake-snapshot --artifact <that dir>. No script automates this. The build id is sha256(lean.wasm)[:16], so the reassembled binary is the paired one by construction.
- QED64's served manifest lists only lean.js (3 chunks) and lean.wasm, sha256 4b025db7729c5f89…, 109,872,982 bytes.
- QED64 REBUILD notes: the Node glue needs bin/package.json = {"type":"commonjs"} when the parent package is type:module.
  - EVIDENCE: wasm/KERNEL.md:102-110. qed64 public/runtime/runtime-manifest.json files{lean.js,lean.wasm}. qed64 commit a5bf7a7 docs/REBUILD.md hunk (bin/package.json commonjs marker). node-runner.mjs:17,68-79,140-146 (needs bin/lean.js + bin/lean.wasm and lib/lean or --lib; loads with vm.runInThisContext and createRequire).
- (3f) Staging: stage-snapshots.py copies the named .snapz files from a staging index into client/public/snapshots, merges index.json, and unlinks superseded files. preflight-artifacts.mjs refuses a tree whose files are missing or whose snapshot/profile runtimes differ from the manifest buildId.
  - EVIDENCE: scripts/stage-snapshots.py:1-25. scripts/preflight-artifacts.mjs (body, lines ~5-30).
- (4a) Local development:
- `npm --workspace client run dev` (vite; CLIENT_PORT default 3000) with a middleware setting COOP same-origin, COEP require-corp and CORP cross-origin on dev and preview.
- Artifacts are served from client/public/{runtime,profiles,snapshots,workers}.
- `?snapshots=<dir>` and `?runtime=<buildId>` re-root to unpromoted sets (dev only).
- Production-like local: `node scripts/serve-dist.mjs` on :3006. It does no transforms and no gzip (vite preview gzip broke the chunk digests), sends COOP/COEP/CORP, and falls back to index.html.
  - EVIDENCE: client/vite.config.ts:13-38, :95-126. scripts/serve-dist.mjs:1-41. vendored qed64-boot.ts:64-66, :86-94. games-api.ts:141-160 (devSnapshotsDir). wasm/DEPLOY.md:153-155.
- (4b) Deployment: a Cloudflare Worker with static assets (wasm/out/deploy, i.e. client/dist minus runtime/ profiles/ snapshots/; every file ≤25 MiB) and run_worker_first=true so COOP/COEP apply to the shell. R2 binding ARTIFACTS → bucket qed64-artifacts (shared with QED64) under prefix lean4game/. infra/worker.js maps /runtime/, /profiles/ and /snapshots/ to the R2 key 'lean4game/'+path and serves single-range GETs (206/416, If-Range). Digest-named files are immutable; manifests and index.json files revalidate. QED64's own worker reads the bucket ROOT (no prefix) and sets CORP same-origin.
  - EVIDENCE: wrangler.toml:1-24. infra/worker.js:19-20 (ARTIFACT_PREFIXES, R2_PREFIX), :22-42 (isImmutable, withHeaders), :89-127 (serveArtifact). qed64 infra/worker.js:27-29 and :40-43 (key = pathname.slice(1)). qed64 wrangler.toml (bucket qed64-artifacts).
- (4c) Publish order: scripts/upload-artifacts.sh first (preflight; rclone `copy`, never `sync`; per directory, digest objects first, then manifests, then index.json; R2_REMOTE/R2_BUCKET/R2_PREFIX env with default prefix lean4game). Then scripts/deploy-app.sh (stage-workers, vite build, rsync excluding the artifact dirs, 25 MiB check, required-files check, sw.js precache check, `npx wrangler deploy`). Rollback = re-copy the previous index/manifests from git (objects are never deleted).
  - EVIDENCE: wasm/DEPLOY.md:20-48, :85-117. scripts/upload-artifacts.sh:1-30, :49-55. scripts/deploy-app.sh:1-40.
- (4d) All runtime paths are root-absolute: /workers/lean.worker.js (LeanSession default), /runtime/..., /snapshots/index.json, /profiles/index.json, and /infoview/* for lean4monaco's webview. The shell must therefore be mounted at the origin root. OPFS caches (qed64-snapshots/, qed64-packs) are per-origin, which is why the port runs on its own origin (lean4game.<account>.workers.dev).
  - EVIDENCE: vendored src/runtime/client.ts:188-189. snapshots.ts:38. profiles.ts:241. qed64-boot.ts:58-66. qed64 frontend/vite.config.ts:24-26 ('the shell must stay mounted at the origin root'). UX-PARITY.md:494-497 (OPFS qed64-snapshots/).
- (5a) Testing:
- Cypress: 24 tests in cypress/e2e/{01-basic-interface,game-features}.cy.ts. Passes only in real Chrome (`npx cypress run --browser chrome --config baseUrl=http://localhost:3006`). Under Cypress's Electron, every checker test fails with 'Missing capability' because the Cypress proxy strips COOP/COEP and Electron ignores --enable-features=SharedArrayBuffer.
- The heavy UX/E2E harnesses are Playwright scripts that live in the QED64 checkout's work/ (games-smoke.mjs, live-matrix.sh, lv-*.mjs, reload-storm-probe.mjs, chaos proxies), not in the port's repo.
- Unit tests: client/src/wasm/*.test.ts and infra/worker.test.mjs (`node --test`).
  - EVIDENCE: cypress.config.ts:1-18. UX-PARITY.md:450-457, :306-313, :713-721, :780-792. wasm/DEPLOY.md:75-77, :129-131, :178. PORTING.md:351-355.
- (5b) Memory needs:
- Browser: the renderer peaks at about 8–9 GB during a first visit (3.6 GB at 'Starting the Emscripten runtime', 7.4 GB at 'Initializing the Lean runtime' before any snapshot, 8.3 GB at ready). Two tabs reached 9.1 GB combined. This floor is V8's lazily generated code for the 106 MB module, and no client knob moves it.
- Build: the Docker VM needs ≥10 GiB for the runtime link. On 7.6 GiB, concurrent `lean` compiles get OOM-killed silently (exit 137, no message), so compiles must run one at a time. The bake needs about 40 GB scratch disk.
  - EVIDENCE: UX-PARITY.md:347-375 and :734-737. KERNEL.md:186-191. PORTING.md:338-350. build-from-source.sh:71-74 and :265-270.
- (6) Lessons from the port that apply to a widgets showcase:
(a) One LeanClient per parent folder in lean4monaco. A second document folder steals the single MessagePort and RPC sessions hang. Keep every showcase document in one folder (fix 14, level-uri.ts).
(b) A status sink that republishes on every progress event re-renders the infoview at about 1.2 kHz, and every render opens an RPC session that fails ('No connection to Lean'). Publish only on change (fix 15).
(c) An RPC session created a few ms before the client reports running is rejected. Retries must re-render into a fresh session, not reuse a closure holding the dead one (fix 17).
(d) Boot must not depend on a hashchange event (fix 18).
(e) Stage the worker scripts, and preflight them with HEAD. A 404 Worker hangs at 'starting Lean' with no error, and failing worker-script fetches during an outage produce three message-less deaths that trip the relay breaker before any settle can hold (fix 19, D1).
(f) `pagehide → relay.unload()` is mandatory. Reload storms stack multi-GiB heaps and crash the renderer (fix 10, fix 20, Open).
(g) Check the snapshot↔runtime pairing before downloading. An unpaired snapshot makes the worker refuse, and the relay reboots it three times before saying anything (game-boot.ts:113-145).
(h) Serve artifacts byte-exact with no edge recompression (DEPLOY.md:150-155).
(i) The QED64 pin goes stale: the port is two runtimes behind QED64. A runtime bump forces a full rebake (KERNEL.md:81-85, :316-320, :333-339).
(j) The probe is the acceptance test: --verify-snapshots plus a negative control (PORTING.md:269-298).
  - EVIDENCE: wasm/UX-PARITY.md:133-137, :174-198, :199-206, :215-232, :233-248, :249-262, :263-288, :830-856, :794-812. client/src/wasm/game-boot.ts:497-545 (WORKER_SCRIPTS preflight).

## Recipes
### (7) Minimal file set to vendor from QED64 for a widget showcase page, without touching QED64
1. Vendor these 10 files by `git -C /Users/fawadhaider/code/wasm64-lean-fable/qed64 archive <commit> <paths> | tar -x -C <widgets>/showcase/src/vendor/qed64`. This is a read-only git operation that writes only into the widgets project:
- frontend/src/qed64-boot.ts
- frontend/src/resident-session.ts
- frontend/src/lsp-relay.ts
- src/install/profiles.ts
- src/runtime/client.ts
- src/runtime/snapshots.ts
- public/workers/lean.worker.js
- public/workers/lsp-frames.js
- public/workers/lsp-front-door.js
- public/workers/snapshot-prefetch.worker.js
Pin to a commit paired with runtime wasm64-4b025db7729c5f89, i.e. 965c249 or HEAD 1859b83. The workers, session, relay and runtime client there are byte-identical to the lean4game pin 32e5e62; only qed64-boot.ts and profiles.ts differ.
1. Write a QED64-PIN file the way sync-qed64.sh:79-85 does (commit, date, subject, sha256[:16] per file). Add a verify step to build/CI that re-hashes the vendored files against it. lean4game lacks this step.
1. For the editor host, do NOT reuse lean4game's custom infoview. Write our own page modeled on qed64 frontend/src/main.ts:395-439 and frontend/vite.config.ts:27-63: lean4monaco 1.1.16 + @leanprover/infoview 0.11.1 (the versions QED64 runs), the WorkerDirect messagePort = relay.clientPort, and viteStaticCopy of @leanprover/infoview/dist/* and lean4monaco/dist/webview/webview.js to /infoview. Copy only the patterns, not main.ts itself (it has QED64-specific UI such as widen-for-Mathlib, exact-imports and the memory meter).
1. Optional, only if baking in-repo: vendor the pipeline subset bake-snapshot.mjs, node-runner.mjs, snapshot-probe.mjs and toolchain/artifact-paths.mjs (bake-snapshot imports it). Add supervised-run.mjs only if HEAD's snapshot-probe imports it (unverified). Skip pack.mjs, or also vendor artifacts/olean-imports.mjs, which HEAD's pack.mjs imports and lean4game's PIPELINE list omits.
Evidence: 

### (2) Boot a showcase session the lean4game way (subclass or configure ResidentSession, supply our own snapshot and initial document)
1. Build artifacts like installGameArtifacts (game-boot.ts:166-182): fetch the runtime manifest (pinned __QED64_BUILD_ID__ first) and /snapshots/index.json; use an empty `installed` map so no 120 MB core pack is installed; tolerate a missing profile index.
1. Before any download, check pairing like game-boot.ts:113-145: the index has a 'showcase' entry, entry.runtime === manifest.buildId, and HEAD on entry.url returns non-HTML, non-404.
1. Policy: `{ snapshotsFor: () => ['showcase'], initialBytesFor: (_h, names) => sized from index bytes, maximumBytes }`. Use gameMemoryPolicy (games-api.ts:238-243) as the starting formula. Consider a cap above 3 GiB for Mathlib-heavy widget elaboration (QED64's editor default is 6 GiB, resident-session.ts:101). This is untested for widgets.
1. A subclass is only needed for extra files in the worker FS (GameSession.start → request('write-files'), game-boot.ts:236-245). Plain ResidentSession is enough otherwise.
1. Relay: `relay = new LspRelay((opts) => new ResidentSession({artifacts, ui, policy, headerText: relay?.lastText || initialText}, opts ?? {}), {status}, settle)`. Use `||`, not `??`, as qed64 main.ts:388-397 explains. Add `window.addEventListener('pagehide', () => relay.unload())`.
1. Initial document: the chosen widget example's text passed to editor.start(el, '/showcase/Example.lean', initialText). Keep every example in ONE folder (lesson 6a). Switching examples = a full-text model change, which the kernel resolver serves from the resident snapshot, as level switches do in lean4game (KERNEL.md:41-53).
Evidence: 

### (3) Bake a showcase snapshot paired with QED64's served runtime, without writing into QED64
1. Reassemble the runtime (KERNEL.md:102-110):
- Read qed64/public/runtime/runtime-manifest.json.
- Concatenate each file's chunks from qed64/public/runtime/chunks, verifying each chunk's sha256, into <widgets>/out/runtime-4b025db/bin/lean.{js,wasm}.
- Assert sha256(lean.wasm)[:16] == 4b025db7729c5f89.
- Add bin/package.json {"type":"commonjs"} (qed64 a5bf7a7, REBUILD.md).
1. Lib tree: `rsync -a --link-dest=/Users/fawadhaider/code/wasm64-lean-fable/qed64/work/lib-tree-slim <src>/ <widgets>/out/lib-tree-showcase/`, then rsync the widget oleans on top (the overlay pattern, build-from-source.sh:207-217). Caution: hard links share inodes, so never edit files in place in the new tree; this keeps QED64 safe. Compile the widget oleans with the native64 compiler in Docker via a compile-pkg.py-style loop (wasm/scripts/compile-pkg.py) with LEAN_PATH pointing at the overlay. QED64's KERNEL-PIN states that oleans built natively at 8d91aadcda are layout-compatible with runtime 9fbb45afcb.
1. Run the VENDORED bake-snapshot.mjs from a copy inside the widgets project, never a QED64 checkout in place (KERNEL.md:287-292). If vendored from HEAD, also pass --work:
`QED64_ALLOW_LEGACY_IMPORTS=1 node --stack-size=8192 bake-snapshot.mjs --name showcase --artifact <out/runtime-4b025db> --lib <out/lib-tree-showcase> --probe $'import Mathlib...\nimport IntervalInspector\n...\n#check 0' --reserve <bytes> --out <out/staging/snapshots> --work <out/bake-work>`
1. Acceptance: `snapshot-probe.mjs --via-mem --artifact ... --snap <work>/showcase.snap --lib ... --probe-file <one widget example>` (the build-from-source.sh:573 shape). Pair it with a negative control.
1. Stage: copy the .snapz and index.json into the showcase public/snapshots (stage-snapshots.py pattern). Every entry must carry runtime wasm64-4b025db7729c5f89. Run a preflight-artifacts.mjs-style check before upload.
Evidence: 

### (4) Serve locally and deploy, the lean4game way
1. Dev: vite with a COOP same-origin / COEP require-corp middleware (client/vite.config.ts:20-38) and publicDir holding runtime/, snapshots/, workers/ and infoview/ at the root. runtime/ can be a symlink or copy of QED64's public/runtime: a symlink inside our project only reads QED64. Set the vite define __QED64_BUILD_ID__ from that manifest.
1. Built: a transform-free static server like scripts/serve-dist.mjs (no gzip, COOP/COEP/CORP, SPA fallback) on its own port.
1. Deploy:
- wrangler.toml as in lean4game: assets dir = dist minus artifact dirs, run_worker_first=true, R2 binding ARTIFACTS on bucket qed64-artifacts.
- Add a worker.js with R2_PREFIX 'widgets/' (or a separate bucket) plus range support (infra/worker.js:19-127).
- Option to avoid re-uploading the 154 MB runtime: map /runtime/ to the bucket root (QED64's objects, read-only) and /snapshots/ to widgets/. Unverified; this couples us to QED64's mutable runtime-manifest.json, so prefer the immutable runtime-manifest.<buildId>.json.
1. Upload with rclone copy (never sync), digest objects first, then manifests, then indexes (upload-artifacts.sh:49-55). Then deploy the shell with the required-files checks (deploy-app.sh:20-40).
Evidence: 

### (5) Exhaustive UX testing patterned on lean4game
1. Use Playwright with real Chromium/Chrome. Cypress's Electron has no SharedArrayBuffer under its proxy (UX-PARITY.md:450-457).
1. Oracle: expose globalThis.<name> = {relay, status: () => relay.status()} like game-boot.ts:926-934 or qed64 main.ts:403-409. Wait for relay phase serving/ready, then assert widget panels in the infoview iframe.
1. Run one browser at a time: about 8–9 GB per renderer (UX-PARITY.md:347-375), and this Mac has 36 GB.
1. Matrix to copy from lean4game:
- cold first visit (fresh profile)
- warm return (persistent profile)
- example switch storm
- reload storm with pagehide
- network cut mid-snapshot via a chaos proxy (setOffline does not reach the prefetch worker, UX-PARITY.md:717-718)
- unknown example route
- offline reload
- mobile 390×844
- dark/light
Evidence: 


## Risks
- The vendored QED64 closure must come from a commit paired with runtime 4b025db (965c249 or 1859b83), not lean4game's 32e5e62. The core files are identical, but HARDENING #51 (a non-module buffer elaborated as a module, found by the first user-widget test, qed64 commit 928ccf4) is fixed only in kernel 0034, i.e. runtime 4b025db. A bake against the older 36a96239 runtime would hit it.
- sync-qed64.sh's import-resolution check only scans .ts files (sync-qed64.sh:65-78). Vendoring HEAD's pack.mjs without olean-imports.mjs would break silently.
- Running any QED64 pipeline script in place (QED64_DIR=<qed64 checkout>) writes work/ under the QED64 repo: bake-snapshot.mjs:66-68 at 32e5e62, and the default --work at HEAD. That violates the read-only rule. Always run from a copy.
- Hard-linked overlay trees (rsync --link-dest from qed64/work/lib-tree-slim) share inodes with QED64's files. Any in-place write in the overlay would modify QED64's tree. Use only rsync replace semantics (new inode) or a full copy if in doubt.
- The lean4game pin discipline is manual: nothing re-verifies the QED-PIN hashes, and its pin is now two runtimes behind QED64. A QED64 runtime promote does not break our shell if we bundle our own runtime copy. But the snapshot must be rebaked for any runtime we switch to, because snapshots are binary-paired (KERNEL.md:333-339).
- Memory: the 3 GiB cap of lean4game's game policy (games-api.ts:241) may be too tight for a Mathlib + DistLens environment of about 1.3–1.5 GB raw plus widget RPC elaboration. QED64's editor uses a 6 GiB cap. A renderer at about 9 GB at ready means a test machine can run only a few browsers concurrently.
- The infoview version gap: lean4game's tree pins infoview 0.8.5 and replaces it anyway. Using lean4game's client deps would not render ProofWidgets panels. Use QED64's frontend dependency set (lean4monaco 1.1.16, infoview 0.11.1).
- Docker VM is 8 GB (task context) vs lean4game's documented ≥10 GiB for runtime links. Fine for compiles if sequential, but parallel lean compiles of Mathlib-heavy widget modules will be OOM-killed with no message (PORTING.md:338-350).
- Per-origin OPFS and HTTP caches: a showcase on its own origin re-downloads the runtime (~154 MB) and its snapshot even for QED64 users (06-qed64-showcase-options.md Option 2 notes about 500 MB).

## Open questions
- Does a ProofWidgets user widget's JS (from the env via the widget-module RPC) load inside lean4monaco 1.1.16's infoview iframe under COEP require-corp when the page is served by OUR shell rather than QED64's? This is untested in lean4game, which strips widgets.
- Does the in-kernel header resolver serve a showcase document whose import list is a strict subset of the snapshot's baked imports (the covered mode), for every widget example header? lean4game relies on this for `import Game.Levels.X` (UX-PARITY.md:435-437), but I did not verify it for Mathlib-rooted headers that are not under QED64's umbrella roots (UMBRELLA_ROOTS = Mathlib, Batteries, MIL, QED64 in resident-session.ts:74).
- Which widget packages are legacy vs `module` files, and does the 0034 fix plus QED64_ALLOW_LEGACY_IMPORTS behave for them in the bake? Unknown.
- Does qed64/work/lib-tree-slim contain every Mathlib module the eight widget packages import (including the ~559-module Probability/MeasureTheory closure for DistLens)? It is a slim tree, and its exact module set was not enumerated here.
- Does HEAD's snapshot-probe.mjs import pipeline/snapshot/supervised-run.mjs (new since 32e5e62)? I did not check; vendor it if so.
- Can the showcase Worker read QED64's runtime objects at the R2 bucket root (shared bucket, no re-upload)? Is that acceptable to the owner, given that it is a read-only reference into QED64's namespace, not a change to it?
- lean4game's working tree has uncommitted changes to game-boot.ts and related files. The cited line numbers may shift once they are committed.
