# Re-pin log

One entry per change of the QED64 pin. Each entry says what the pin moved from and to, how the procedure in README.md
"Re-pin" was actually executed, the evidence for each gate, and how to switch back.

**Where it stands:** printed by `scripts/showcase.sh pin current` / `pin list` and `showcase.sh verify`, not written
here. *History (dated):* fourteen pins registered (A–H by 2026-10-06, I and J on 2026-10-09, K on 2026-10-12, L and N on 2026-10-16, O on 2026-10-27; there is no M; I and J retired on 2026-10-27), all with complete stores except I and J, whose widgets8 overlay K replaced in the f69cca24 store they share (the
pin-J lane's measurement pins `58ae6d2`, `349b1b7`, `27a4ba6`, `0ff314c`, `3b804ea` are registered locally only, never
committed, and removed after their runs). The sequence of served pins: A `1859b83`
(first build) → B `9fdf9b8` (2026-10-01, QED64's L7 fix; L9 V1) → C `5ac5d00` (multi-pin lane, with the rehearsed
switches C→A→C→A→C→B→C) → D `3b42714` (2026-10-02 17:35–19:26Z, final gate) → C (19:26Z, final gate: D's reload storms
were not cleaner than C's) → **E `33b0967`** (2026-10-04 05:18Z, pin-e lane: its storms were at least as clean as C's;
gated while served, below). D stays staged; QED64 has not handed over `3b42714`. **F `84d594e`** (QED64
`feature/embedding-api`, the embedding contract v1) was registered on 2026-10-05 and made the **active pin locally**
(E → F) with the gallery moved to the v1 page API. **G `5c327c2`** (2026-10-06: F plus QED64's edit back-pressure)
replaced it, and **H `bf9d947`** (QED64 main: G plus the keep-alive fix) was the active pin locally from 2026-10-06
~20:03Z, gated in the browser on 2026-10-06/07 (three VERDICTs, a headed sign-off; pin H entry). F, G and H are committed
on the local branch `qed64-embedding-v1`, which is not pushed. **I `385a1ac`** (QED64 main on the kernel fork's release
`lean-v4.34.0-e1a79c1`, runtime `wasm64-f69cca24d0878a58`, with QED64's #62/#63/#64) was the active pin locally from
2026-10-09 ~13:10Z, the first pin whose overlays are served from per-runtime directories; its first full run found the
kernel-0036 regression in Chrome. **J `5e63edd`** (QED64 main since 2026-10-09 ~20:30Z: I plus the worker's engine-stack
probe at 8192 slots, HARDENING #67, the interim for 0036; same runtime and overlays) was the active pin locally from
~18:55Z, gated in the browser (two VERDICTs, a headed sign-off, C20 405/405, the 10 Mbit/s first visit;
pin I entry, "Pin J"). **K `62a06e2`** (QED64 main with #68–#72, I's runtime, the widgets8 overlay rebaked for the
widgets at `6b31bba`, widgets7 unchanged) followed on 2026-10-12, then **L `37ff491`** and **N `58ebbad`** on runtime
`wasm64-5650321f3f58aeb0` (2026-10-16), and **O `521cf3f`** (QED64 main on the kernel release `lean-v4.35.0-b081e7c`,
**Lean 4.35.0**, runtime `wasm64-36d7f415704473d9`; the widgets ported to 4.35 first) is the **active pin locally**
since 2026-10-27 and gated (last entry). None of I–O is deployed. The live site serves pin H `bf9d947` (deployed 2026-10-08 19:20Z by the qed64-deploy run on the push of `d60b15e` to main, Worker version `29176b6f`; its 93 R2 objects were E's, nothing was uploaded).

Current verdict and sign-off counts per pin: `scripts/showcase.sh pin list` (this table's "Browser gates" column is
dated history: as of the final gate, 2026-10-02, for E as of the pin-e lane, 2026-10-04, for F–H as of
2026-10-07, for I as of 2026-10-09 ~18:00Z, for J as of 2026-10-10 ~03:55Z, and for K, L, N and O as of their entries).

| Pin | Runtime | Registered by | Browser gates (history, 2026-10-02) | Status |
|---|---|---|---|---|
| A `1859b83` | `wasm64-4b025db7729c5f89` (0034) | first build; re-keyed by the multi-pin lane | VERDICT `closeout-full1` (old gallery); C21 + C22 green with the hardening gallery code (`harden-A-c21c22`, gallery `894b9c51…`, own port); no full suite since | staged fallback |
| B `9fdf9b8` | `wasm64-2c18773ecfba45bb` (0035) | 2026-10-01 re-pin | 1 VERDICT, 6 red full runs, all on L9 V1 | evidence only, do not deploy |
| C `5ac5d00` | `wasm64-4b025db7729c5f89` (0034, #52 worker) | multi-pin lane | by the end of the final gate: 7 VERDICTs, the last two `final-C-full1/2` on `2081098d…`; headed sign-off `final-C-headed1` | served until 2026-10-04 05:18Z; staged since (the fallback) |
| D `3b42714` | `wasm64-3ab1c6a9da03bc29` (0035b) | pin D lane (stores without switching) | VERDICT `final-D-full1/2` on `eab4f147…`; headed sign-off `final-D-headed2`; storms V2 3/26 vs C 2/26 | staged, ready |
| E `33b0967` | `wasm64-3ab1c6a9da03bc29` (D's runtime and stores; #55 lifetime-lock worker, #54 boot card) | pinE lane, 2026-10-04 (below) | pin-e lane, 2026-10-04: storms on `/showcase/#hasse-view` E 0/20 vs C 0/20 headed, 0/8 vs 1/8 headless-shell; VERDICT `pinE-full1/2` and headed sign-off `pinE-headed1` on `bbdbc932…`; 10 Mbit/s first visit PASS | served since 2026-10-04 (current state: `pin current`) |
| F `84d594e` | `wasm64-3ab1c6a9da03bc29` (E's runtime and stores; the v1 page: `qed64.api`, `?embed=1`, `#code=`, #56 editor RPC, widget-source cache, #57, #59 coalescing) | v1-adoption lane, 2026-10-05 | `CONTROLS PASS` 11/11 and a v1 smoke 22/22 on an earlier gallery; no UX run (pin F entry) | staged since 2026-10-06 (active locally 2026-10-05/06); not deployed |
| G `5c327c2` | `wasm64-3ab1c6a9da03bc29` (F + QED64's edit back-pressure `e4cffcc`, HARDENING #59) | pin-G lane, 2026-10-06 | `CONTROLS PASS` 11/11, smoke 22/22; `g-full1b` red with 7 failures, all diagnosed (one a QED64 defect: the keep-alive starvation); VERDICT `g-full1c` on `931c33a7…` (pin G entry) | staged since 2026-10-06 ~20:03Z; not deployed |
| H `bf9d947` | `wasm64-3ab1c6a9da03bc29` (G + QED64's keep-alive fix; QED64 main) | v1-adoption session, 2026-10-06 (pin H entry) | smoke 22/22; VERDICT `h-full1b`, `h-full3`, `h-full4` on `d8a5bb6d…`; `C20` 135/135 ×3; headed sign-off `h-headed2`; 3 renderer crashes (QED64 #55 residual) in `h-full1`, `h-full2b`, `h-headed1` (pin H entry) | active locally 2026-10-06 ~20:03Z to 2026-10-09 ~13:10Z; staged since; verdict record `infra/ux-verdict.json` → `h-full4` (stale for a redeploy of H with the pin I gallery code, pin I entry); not deployed (the live site serves E) |
| I `385a1ac` | `wasm64-f69cca24d0878a58` (kernel `e1a79c1ce9`, release `lean-v4.34.0-e1a79c1`, patch 0037; QED64 main with #62/#63/#64); new stores, overlays served at `/snapshots/widgets{7,8}.f69cca24d0878a58/` (descriptor `qed64-showcase.pin/v3`) | pin-I re-pin, 2026-10-09 (last entry) | static and headless gates green; browser gates on hold (smoke 23/23; `i-full2` red on a kernel-0036 regression: DistLens `pmf_num` clicks fail "stack is exhausted" in Chrome) (pin I entry, "Gates") | active locally 2026-10-09 ~13:10Z to ~18:55Z; **superseded by J**; **retired** 2026-10-27 (K rebaked the f69cca24 overlay store); stays registered as the record of the 0036 regression; not deployed |
| J `5e63edd` | `wasm64-f69cca24d0878a58` (I's runtime, stock snapshots, profiles, main bundle and overlay directories; only `dist/workers/lean.worker.js` and `dist/qed64-build.json` differ: `LEAN_WASM_STACK_PROBE_SLOTS=8192` at preRun, HARDENING #67; QED64 main, a fast-forward of `fix/stack-probe-headroom`) | first a staged test pin from our worktree (2026-10-09 ~18:50Z), promoted when QED64 pushed the commit to main (~20:30Z) (pin I entry, "Pin J") | smoke 23/23; `j-dl1` 3/3; VERDICT `j-full1`, `j-full5` on `65279b0b…` (red: `j-full2`, `j-full3`, `j-full4`); `C20` 135/135 ×3; headed sign-off `j-headed2` (35/35); 10 Mbit/s first visit PASS (565.1 s); C11 headed ×3 3/3 | active locally 2026-10-09 ~18:55Z to 2026-10-12; not deployed; **retired** 2026-10-27 (K rebaked the f69cca24 overlay store) |
| K `62a06e2` | `wasm64-f69cca24d0878a58` (I's runtime; widgets8 rebaked for the widgets at `6b31bba`, widgets7 unchanged; QED64 main with #68–#72) | pin K entry, 2026-10-12 | VERDICT `k-full1`, `k-full5`; C20 405/405; headed `k-headed1`; 10 Mbit/s PASS | gated 2026-10-13; active locally to 2026-10-16; not deployed |
| L `37ff491` | `wasm64-5650321f3f58aeb0` (kernel release `lean-v4.34.0-53cb11e`: native Wasm exceptions + 0041); new stores | pins L and N entry, 2026-10-16 | no VERDICT (`l-full1`/`l-full2` red on C3, QED64's, fixed upstream as #76, and on C10/C23, ours, fixed in `d8fe1c6`) | registered as the first pin on this runtime; superseded by N |
| N `58ebbad` | `wasm64-5650321f3f58aeb0` (L's runtime and stores; QED64 main with #74–#76) | pins L and N entry, 2026-10-16 | VERDICT `n-full1`, `n-full2`; C20 405/405; headed `n-headed1`; 10 Mbit/s PASS (519.0 s) | gated 2026-10-16; active locally to 2026-10-27; not deployed |
| O `521cf3f` | `wasm64-36d7f415704473d9` (kernel release `lean-v4.35.0-b081e7c`, patch 0042; **Lean 4.35.0**, Mathlib `56a00585`; QED64 main with #77–#81; the widgets ported to 4.35, `1a61003`); new stores, overlays at `/snapshots/widgets{7,8}.36d7f415704473d9/` | pin O entry, 2026-10-25..27 | smoke 23/23; VERDICT `o-full1`, `o-full2` on `047aa584…`; C20 405/405; headed `o-headed4` (35/35); 10 Mbit/s PASS (513.9 s) | **active locally** since 2026-10-27; verdict record `infra/ux-verdict.json` → `o-full2`; not deployed |

## 2026-10-01: QED64 1859b830 / wasm64-4b025db7… → 9fdf9b85 / wasm64-2c18773ecfba45bb (QED64's L7 fix)

| | Old pin | New pin |
|---|---|---|
| QED64 commit | `1859b830b3621dbacc1752a818634d06a1c94bd0` (promote `965c2494`) | `9fdf9b8581d3d4a71b8f79e45b1858dd906bcb85` (it is the promote: "promote kernel 0035 (HARDENING #52 fix)") |
| Runtime buildId | `wasm64-4b025db7729c5f89` | `wasm64-2c18773ecfba45bb` |
| Kernel (`pipeline/toolchain/KERNEL-PIN`, `sourceRevision`) | `9fbb45afcb` (0034) | `3ae65d36f96b2434881f27fffe9f03d608d974f0` (0035) |
| Stock snapshots | `init.35c8c5f5419e0c33`, `mathlib.8df0689fbc323eab` | `init.7cf361eb941eda2c`, `mathlib.bf13acc48d0efb21` (raw sizes identical: 122,364,117 and 1,127,272,685 B) |
| Packs | lean-core, mathlib-essential | unchanged (69/69 part files byte-identical) |
| Main bundle | `dist/assets/index-CzXuAkOQ.js` | `dist/assets/index-Jv35CWTg.js` |
| Widget overlays | `widgets.3619cfd519e6f82d` (w7), `widgets.0880fd91b58098c0` (w8) | `widgets.a0c16868a07dfd68` (w7), `widgets.62e1f451c1940d1b` (w8) |
| Native toolchain (native64 `857544b439`, BUILT `8d91aadcda`, Mathlib `5ed2965`, ProofWidgets `106ff4f`) | – | unchanged; no native rebuild |

Logs are under `$W/logs/` (`$W` = `/Users/fawadhaider/code/qed64-showcase-work`), named `repin-*` unless stated.
The rule header for this lane said "no snapshot bake"; its own step 5 required the two widget bakes, and they ran
under the browser lock as `bake.sh` requires.

### 1. Preconditions (read-only on the QED64 checkout)

`repin-preconditions.log` (20:33:47Z): `HEAD 9fdf9b8581d3d4a71b8f79e45b1858dd906bcb85`, `porcelain lines: 0`, manifest
buildId `wasm64-2c18773ecfba45bb`, `dist bundle ids: 1 wasm64-2c18773ecfba45bb`, 58 dist files. The dist was QED64's
own rebuild (`dist/index.html` and `index-Jv35CWTg.js` 16:09:44 EDT, two minutes after the 16:07:33 commit;
`qed64/work/bump-0035/build-site.log` "built in 10.23s"), and it contains the new pill text "the checker stopped
responding". No shell build of our own was needed.

### 2. Native oleans: compatible, reused (done before touching any pin)

`repin-olean-compat.log`, a byte comparison of the served core library, new `pipeline/toolchain/work/build/stage1/lib/lean`
against the kept old `stage1-4.34-4b025db7/lib/lean`: 32,798 files on each side, **32,795 identical**. All 2,520
`.olean` and 2,520 `.ilean`, and all 2,518 `.ir`, `.ir.sig`, `.olean.server` and `.olean.private` are identical (with
their `.hash`/`.trace` files). The three that differ are link-time C++ runtime archives, which go into `lean.wasm`
itself and are not read when oleans load: `libleanrt.a` (members `object.cpp.o`, `io.cpp.o`, `platform.cpp.o`: patch
0035), `libleanshared.so`, and `libleancpp.a` (the embedded githash string `9fbb45afcb…` → `3ae65d36f9…`). The same
holds for QED64's slim inputs: `bump-0035/slim/core-lib-slim` vs `bump-51` (same three files differ), and
`bump-0035/slim/lib-tree-slim` vs `bump-51` **20,014/20,014 identical**. The native compiler pins are unchanged
(`NATIVE-COMMIT 857544b439`, `BUILT-COMMIT 8d91aadcda`, `stage1/bin/lean` / `lake` sha256 equal to the lock). So the
delta and widget oleans compiled natively against these bytes stay valid; stage-trees' G2 confirms it below (20,012
facet files byte-identical to the native build). No Docker job was needed or started.

### 3. Rollback snapshot (before any edit)

* `rollback/wasm64-4b025db7729c5f89/`: `QED64.lock.json`, `QED64-PIN`, `vendor-qed64/` (APFS clone), `overlay/widgets7`,
  `overlay/widgets8`, `out-headless/summary.json`, `out-experiments/x4{,-debug}.json`, and `files/<path>`: the
  pre-edit copy of every file this re-pin edited (scripts, tests, gallery, infra, docs).
* `$W/rollback-wasm64-4b025db7729c5f89/`: `stage1/`, `tree-slim-w7`, `tree-slim-w8` (+ `EXPECTED-N`), `bake-out-w7/w8`,
  `bake-work-w7/w8`, `raw/` (init, mathlib, widgets7, widgets8 + provenance), `BAKE-KEY-*`, and the old bake, stage and
  stage-4 logs.
* `release/wasm64-4b025db7729c5f89/` stays where it is (`pin-qed64.mjs pin` only replaces `release/<new buildId>`).

### 4. Pin constants and the pin

Edited (each also listed by `showcase.sh verify`):

* `scripts/pin-qed64.mjs`: `QPIN`, `QPROMOTE` (both `9fdf9b85…`), `BID`, and a new `KERNEL` (`3ae65d36f9…`). `pin` now
  writes `qed64.kernel` into the lock and refuses when QED64's `pipeline/toolchain/KERNEL-PIN` at the pin names another
  kernel; `verify` gained check #9 (the same comparison, plus the lock).
* `showcase.sh verify` pin-constants now also checks `QPROMOTE`, `BID` and `KERNEL` against the lock, and that every
  `/assets/*.js` named in `tests/ux/selectors.json` exists in the pinned dist (the bundle names are content hashes; the
  allowlist named the old `index-CzXuAkOQ.js`, and lines 1–874 of the old and new bundle are identical, so the
  allowlisted `notify` site, line 627, is unchanged).
* The buildId in the 16 `PIN_SITES` (scripts, headless tools, experiments, `selectors.json`, `infra/worker.test.mjs`;
  `gallery/pin.json` regenerated by `build-gallery.mjs`). `judge-bake.mjs` now reads the stock region size from the
  pinned release index instead of a constant.
* The served base trees: `BASE_SLIM` / `CORE_SRC` in `showcase.sh`, the `stage-trees.mjs` default, and
  `run-controls.sh`'s `tree-stock` source now point at `qed64/work/bump-0035/slim` (byte-identical olean content, above).
* The console allowlist's bundle URL (`selectors.json`, `check-gallery.mjs` fixtures, `infra/worker.test.mjs`).

`showcase.sh pin --yes` (`repin-pin.log`, 20:35Z): `S0.2 OK QED64 HEAD=9fdf9b85… clean`, `S0.3 OK vendored 26 files`,
`S0.4 OK cloned 145 files (1.676 GB logical) -> release/wasm64-2c18773ecfba45bb`, `RECORDED WIDGETS_SOURCE_HASH
16cdb73b…` (unchanged), `VERIFY OK (1 DRIFT in a rebuild-only input)` (the known Docker tag drift), with `OK #9
pipeline/toolchain/KERNEL-PIN at QPIN == KERNEL == lock qed64.kernel — 3ae65d36f9`.

**What changed in the vendored sources** (`repin-vendor-diff.log`; 24 files → 26):

* `public/workers/lean.worker.js` (+354 lines): the L7 fix's worker half. A message-mode runtime mailbox
  (`instrumentRuntimeMailbox`, `waitAsyncPolyfilled = true` before `initRuntime`), a 1 s mailbox kick with confirmed
  rescues (`kickMailbox`, `mailboxWatchFired`, log `[liveness] a runtime-mailbox wakeup was lost … rescue #n`), the
  Lean-side liveness probe (`LIVENESS` {tick 1 s, probe after 6 s, wedge after 12 s, grace 4 s}, `$/qed64/liveness`,
  died `wedged`), the FileWorker exit hook (died `exit`), `pool.parked`, and `status().liveness` counters.
* `frontend/src/lsp-relay.ts`: reboot reason `wedged`, `status().rebootReason`.
* `src/runtime/client.ts`: `pool.parked`, `liveness` in `WorkerStatus`.
* New: `pipeline/snapshot/fileworker-exit-probe.mjs`, `pipeline/snapshot/thread-storm-probe.mjs`.
* Unchanged: the other 21, including `qed64-boot.ts` (the `?snapshots=` override), `resident-session.ts`,
  `bake-snapshot.mjs`, `artifact-paths.mjs`, `lsp-front-door.js` and `frontend/package-lock.json`.

**What changed in the release set:** dist 52 same, 2 changed (`index.html`, `workers/lean.worker.js`), 4 bundles renamed;
runtime manifest + 10 chunks new; `profiles/index.json` changed (runtime id), 69/69 pack parts identical; both stock
snapshots new.

`$W/stage1` refreshed with `cp -Rc` from QED64's served `stage1/bin`: `buildIdOfArtifact wasm64-2c18773ecfba45bb`,
`lean.js` sha256 `d712b44e…` = the manifest.

### 5. The served base tree of the new region

QED64's `work/bump-0035/stage.sh` baked with `QED64_SLIM=work/bump-0035/slim` (`repin-base-tree.log`): 5,004 `.olean`
in `lib-tree-slim`, the bake log `Loading 5004 modules … 5004/5004: QED64.Essential`, and the raw region bytes:
`$W/raw/mathlib.snap` (gunzip of the served `mathlib.bf13acc48d0efb21.snapz`) sha256 `f41f35dc…` **equals**
`bump-0035/snapshot/mathlib.snap` and `work/snapshot/mathlib.snap`; init `21139348…` likewise. The new raw regions
differ from the 0034 ones in 208,425 (init) and 374,997 (mathlib) bytes, so the widget regions must be rebaked
(binary pairing).

### 6. Trees, bakes, overlays, preflight

* `stage w7` (`repin-stage-w7.log`): `STAGE-TREES OK … EXPECTED-N=5107` (delta 39, own 64; G1–G6 OK; G2 20,012 facet files
  byte-identical to the native build). `stage w8 --force` (`repin-stage-w8b.log`): `STAGE-TREES OK … EXPECTED-N=5684`
  (delta 609, own 71). The new trees are byte-identical to the 0034 bake trees (20,234 and 22,521 files): the runtime is
  the only changed bake input. `tree-fat` was kept (its base `qed64/work/lib-tree` has no file newer than its staging).
* The first w8 staging hung in the vendored `olean-imports.mjs --audit`: its work was done, but `sample` showed
  `node::Environment::Exit` → `pthread_join` on a V8 `ConcurrentBaselineCompiler` thread in `__psynch_cvwait`
  (`repin-stage-w8-audit-hang.sample.txt`), the Node v26 exit deadlock README.md records for `verify`. The audit call
  now has the same kind of watchdog (300 s, one retry); I stopped my own hung child, and the re-run passed.
* Bakes (`repin-bake-retry.log`; under the browser lock; refused 2× and 6× while other sessions' browsers ran, which is
  host contention):
  * w7: `bake w7: rc=0 wall=368s`, `time -l maxrss 14029619200 B`; `JUDGE w7: GREEN N=5107 raw=1163657293
    /snapshots/widgets.a0c16868a07dfd68.snapz` (J4 k=0.811); `PAIRING GREEN … bake-out-w7`.
  * w8: `bake w8: rc=0 wall=370s`, maxrss 13,034,995,712 B; `JUDGE w8: GREEN N=5684 raw=1267834573
    /snapshots/widgets.62e1f451c1940d1b.snapz` (k=0.831; the plan-range WARN is the same known over-estimate as the
    original bake); `PAIRING GREEN … bake-out-w8`.
  * Raw sizes equal the 0034 bakes'; the bytes differ (w7: 378,510 bytes).
* Overlays (`repin-overlay-w7.log`, `repin-overlay-w8.log`): `PAIRING GREEN` with `CMP mathlib: inflated bytes ==
  bake-work-wN/widgets.snap` (`73b367c3…`, `d2422676…`); `$W/raw/widgets{7,8}.snap` are APFS clones of those files.
* QED64's read-only preflight on both overlays (`repin-inlock-browser.log`, under the lock, 21:17Z):
  `PREFLIGHT OK buildId=wasm64-2c18773ecfba45bb mode=resident snapshots=snapshots/widgets7` (no-boot and boot; `boot
  smoke: ready in 13274 ms`) and the same for widgets8 (`ready in 14278 ms`); each boot fetched exactly our
  `init.7cf361eb…` and `widgets.<d16>` snapz.

### 7. Headless stage 4

`showcase.sh headless all` on the new runtime and bakes (`repin-headless-all-2.log`, 17:28–17:45 EDT; summary
`out/headless/summary.json`, `runtime wasm64-2c18773ecfba45bb`):

* Controls: `CONTROLS PASS` (E1 positive/negative on the stock region, the stock `conv?` E3, the refused header, the
  provenance negatives).
* Stage 4: `STAGE4 all: 0 failing step(s)`, 45/45 steps rc 0 with their verdict lines. **E1 8/8 on w8 and 7/7 on w7.**
  **E3 1167/1167 checks on w8** (1166 on the old pin plus one added selection check, below) **and 1038/1038 on w7**.
  **E3b 49/49 panels clean on w8, 44/44 on w7.**
* E2: 7/8 Demos clean; the eighth is tree-scope `Demo.lean:104` (`#tree_scope: rbSample does not reduce to a
  constructor application`), which is L1 exactly as on the old pin. The summary gate reads `{"E1":{"w8":"8/8","w7":"7/7"},
  "E3":{"w8":"8/8","w7":"7/7"},"E3b":{"w8":"8/8","w7":"7/7"},"E2":"7/8 clean","E2rootCaused":["tree-scope:
  L1-exported-level-imports"],"E2Green":true,"stage4Green":true}`. (`headless all` exits 1 at E2 by design; the summary
  was run after it: `repin-headless-summary.log`.)
* **One failure on the first pass, root-caused and fixed in our repo** (`repin-headless-all.log`): `E3 FAIL
  expr-xray.widgets8 (144/145)` and the same on w7. The failing check was `selection @39 … text "clean (explicit only)
  app if n = n then 1 else 0 : ℕ"`. The panel did render that text, as consecutive leaves (`"clean (explicit only)",
  "app ", "if n = n then 1 else 0", " : ℕ"`). At 03:25 EDT another lane had changed that expectation in
  `lean/examples/expr-xray.json` (it was `"ite"`) to a run of consecutive leaves and taught the native golden tool
  (`lean/goldens/lsp-golden.mjs:410-414`: `texts.includes(t) || run.includes(sq(t))`, leaves concatenated, whitespace
  removed; also `build-gallery.mjs` and `hints.mjs`), but not the wasm E3 probe. That change came after the old pin's
  stage 4 (00:26–00:58, 144/144). Applying the E3 rule (`texts.includes(t)` only) to the **native** output also gives
  false, so it was not a runtime difference. `scripts/headless/rpc-probe.mjs` now uses the golden tool's rule. It accepts the
  native and wasm outputs and rejects two mutants of the native panel (one leaf removed; the wrong subterm).
  Re-run: `E3 PASS expr-xray.widgets8 (145/145 checks)`, the same on w7.

### 8. Gallery: the liveness probe defers to QED64's own; D1/D2 re-checked

* **QED64's liveness** (`lean.worker.js`): mailbox kick every 1 s; a probe after 6 s without a server frame; a stall
  12 s later; died `wedged` 4 s after that, about 22 s after the last frame (up to about 25 s with tick lag); the relay
  reboots (`rebootReason` `wedged`) and replays the text. `status().liveness` = `{probes, answered, stalls, resumed,
  rescues}` is carried on every status once published.
* **The gallery** (`gallery/gallery.js`, API version 5) detects `status().liveness` and then defers. Its hover probe
  starts after `probeDeferMs` = 30 s without progress instead of 10 s, past QED64's window. It never probes or restarts
  while QED64 reports a stall (`stalls > resumed`), and a wedge it decides then is `deferred`. It observes and reports
  QED64's rescues, stalls and `wedged` reboots (`status().liveness.qed64`, `qed64-*` events, the notice "Lean stopped
  responding; QED64 is restarting it. Your text is kept."). It remains a fallback for a freeze QED64's worker cannot
  see, such as a page-level one. On a page without `status().liveness` nothing changed.
* `scripts/sim-gallery.mjs` run 9 models a page with QED64's liveness: `SIM-GALLERY OK 76 ok, 0 failed`
  (`repin-sim-gallery.log`). It covers deferral (no probe at 1.6 s where the old threshold was 1 s), a QED64 rescue
  reported, a QED64 stall + `wedged` reboot observed with 0 gallery probes, 0 `relay.restart` and the text kept, no
  probe during a QED64 stall, the fallback restart when QED64 never acts, and `deferred`. `check-gallery.mjs`:
  `CHECK-GALLERY OK 122 ok, 0 failed`.
* UX tests C21/C22 were updated for the pin: C21 (a) expects the deferred restart 39–45 s after the click (30 s + 2 × 5 s,
  before the 45 s card) with QED64 rebooting nothing; C22 (2) also requires QED64's own liveness to take no action during
  the 38 s silent `#eval` (0 stalls, 0 reboots; any probe answered).
* **D1 and D2 without the bridge, on the new page** (X4 under the lock, 21:19Z, `out/experiments/x4.json`): verdict
  identical to the old pin. `applyEditStockPage` BROKEN; `rpcPanelStockPage` BROKEN (`TypeError: r.abortSignal.addEventListener
  is not a function` at `sendClientRequest`, `/assets/index-Jv35CWTg.js:1201:12747`); `makeEditLinkStockApplyEdit` BROKEN;
  with the bridge, both work. **The bridge stays.**

### 9. Browser UX on the new pin, and a new QED64 limitation (L9)

**D1/D2, the liveness evidence and the gallery gate.** `showcase.sh gallery` (17:46 EDT): `gallery gate GREEN on
gallery content sha256 7bbddf2e750c0fa29cc7b82171dda555163643cd4d9be21bb707512ded338f96`, `CHECK-GALLERY OK 122`,
`SIM-GALLERY OK 76`, `UX STALE` (expected: new lock and overlays). QED64's own liveness, read inside its worker during
a 38 s silent `#eval` (`tests/ux/tools/qed64-liveness.mjs`, `out/ux/repin-explore/explore/qed64-liveness.json`):
boot line `[boot] runtime mailbox: message notifications (no Atomics.waitAsync); proxied calls counted; FileWorker exit
hooked`, mailbox word located, 29,076 proxied calls served, 0 rescues. The longest gap between server frames was
1,066 ms (+185 frames in 38 s), so its 6 s probe never fired: in a gallery session the editor's and InfoView's requests
keep frames flowing, and QED64's probe only acts when every frame stops.

**Full suite** `showcase.sh ux`, run `repin-full1` (started 21:54Z, 24.5 min of tests, gallery `7bbddf2e…`): **24 passed, 7 failed, 1 skipped**,
`NOT A VERDICT`. C20 passed: **135/135 clean, 0 stalls, 0 liveness wedges**. Each failure, root-caused:

| test | cause | fix / status |
|---|---|---|
| C1 | stale pin constant in the test: it expected exactly `32643645 + 364676234` bytes (the old overlay's transfers); the new overlay is 397,319,930 B | `00-boot.spec.mjs` reads the expected bytes from the served `widgets8/index.json`. **Passes** (`repin-subset1`) |
| C2 | the warm profile's "primed" mark (`.ux-primed`) was not tied to the snapshots, so after the re-pin the profile held only the 0034 snapshots and the "warm" boot downloaded the new ones (397,319,930 B) | the mark records the overlay's digests and the profile is re-primed when they change. **Passes** |
| C22 | wrong premise in my update: it required QED64's probe to fire at least 3 times during the 38 s `#eval`; measured in the worker, it never needs to (above) | it now requires that QED64's liveness took no action (0 stalls, 0 reboots, any probe answered). **Passes** (gallery probe 1/1 answered in 2 ms, 0 restarts) |
| C21 | (a) passed its new assertions: the deferred restart 40.4 s after the click, `probe, missed, probe, missed, wedged`, no card, QED64 rebooting nothing; (b) the renderer crashed 1.8 s after a relay restart (L9) | **passes** on the re-run: (a) 40.7 s; (b) observe-mode wedge, synthetic capture `out/hang/captures/repin-subset1-2026-10-01T22-49-24-856Z.json`, card, Keep waiting, Reset |
| C10 | the renderer crashed during the reload storm (L9), 2/2 (`repin-full1`, `repin-crash1`); it passed on the old pin | **open: QED64 L9** |
| W4 | the renderer crashed once in normal use (L9); it passed on the re-run (`repin-crash1`) | **open: QED64 L9 (intermittent)** |
| C14 | aggregates the three crashes | follows L9 |

**L9: on this host, the 9fdf9b8 release crashes the renderer on a reload or a relay restart.** With `DEBUG=pw:browser`
the browser reports `V8 javascript OOM (Scavenger: semi-space copy)` (`repin-explore-1.log`). The decisive A/B ran on the
stock page, with no gallery and no bridge, so the showcase is excluded. `tests/ux/tools/reload-storm.mjs` was run
against two scratch copies of `serve.mjs` in the scratchpad: the old one serves `release/wasm64-4b025db7…` with the
rollback overlay, the new one `release/wasm64-2c18773e…`; it boots a fresh profile to ready and reloads every 3 s,
alternating old and new (`repin-ab-{1,2}.log`, `out/ux/repin-ab/explore/`). Result: **old 0/5 crashed, new 3/5
crashed**, each about 2.1 s after the first reload of a ready page. Playwright counts the same 26–27 live workers on
both releases. QED64's own pool at ready differs: old `{unused 13–14, running 10–11}`, new `{unused 4–6, running
18–20, parked 8}`. The crash reports of these runs are `EXC_BREAKPOINT` with 36–46 `DedicatedWorker` threads. This is
reported upstream as L9 (docs/UPSTREAM-REPORT-QED64.md), with the repro and next steps. Nothing in the gallery can
prevent it. It makes the 9fdf9b8 pin a trade: L7 is fixed upstream, and L9 is new. Rolling back (below) returns to L7
with no L9.


**Final lane (2026-10-01/02).** Two full suites on this pin through `showcase.sh ux`:

* `final-full1`: 31 passed, 1 skipped, VERDICT.
* `final-full2`: 28 passed, 3 failed. C10 and C21 (b) crashed the renderer (L9), and C14 aggregates the two crashes.

The C20 hang hunt (8 observe-mode runs) found 0 hangs and 0 QED64 rescues (docs/UX-RESULTS.md "Final verification on
the 9fdf9b8 pin", out/hang/FIELD-CAPTURE.md). The pin therefore has one verdict but not two green runs. The keep-or-roll-
back decision above still stands.

### Rollback: switching back to wasm64-4b025db7729c5f89

1. Restore the code: `cp -p rollback/wasm64-4b025db7729c5f89/files/<path> <path>` for every file under `files/`
   (they are the exact pre-re-pin copies), **except** `scripts/headless/rpc-probe.mjs` (the E3 selection rule fix) and
   keep the watchdog hunk of `scripts/stage-trees.mjs`. Those two fixes do not depend on the pin (for stage-trees,
   restore only the `coreSrc` default to `work/bump-51/slim/core-lib-slim`). The gallery's deferral is also harmless
   on the old page, because it applies only when `status().liveness` is present. Restoring `gallery/gallery.js` is
   optional; `selectors.json` and `25-stall.spec.mjs` must match whichever `gallery.js` you keep.
2. Restore the pin: `cp -p rollback/wasm64-4b025db7729c5f89/QED64.lock.json rollback/wasm64-4b025db7729c5f89/QED64-PIN .`;
   `rm -rf vendor/qed64 && cp -Rc rollback/wasm64-4b025db7729c5f89/vendor-qed64 vendor/qed64`. `release/wasm64-4b025db7729c5f89/`
   is still in place. Do **not** run `pin --yes`, which needs QED64's HEAD at 1859b830.
3. Restore the overlays: `rm -rf out/overlay/snapshots/widgets{7,8} && cp -Rc rollback/wasm64-4b025db7729c5f89/overlay/widgets{7,8} out/overlay/snapshots/`.
4. Restore `$W`: move `stage1`, `tree-slim-w7/w8` (+ `EXPECTED-N`), `bake-out-*`, `bake-work-*`, `BAKE-KEY-*` and
   `raw/*` back from `$W/rollback-wasm64-4b025db7729c5f89/` (move the current ones aside first).
5. `node scripts/build-gallery.mjs` (rewrites `gallery/pin.json` from the restored lock), then `scripts/showcase.sh
   verify` must print `VERIFY: all checks OK` against `wasm64-4b025db7729c5f89`.

Switching forward again is the reverse, or a re-run of this procedure.

## 2026-10-02: multiple pins keyed by QED64 commit; pin C (5ac5d00) gated and served

Logs are under `$W/logs/multipin-*` (and `showcase-multipin-*`). The lane's decision rule (orchestrator): three candidate
pins, A = `1859b83` / runtime `wasm64-4b025db7729c5f89` (old shell and worker; L7 recovered only by the gallery),
B = `9fdf9b8` / `wasm64-2c18773ecfba45bb` (L9; staged for evidence only), C = `5ac5d00` / `wasm64-4b025db7729c5f89`
(QED64's interim local main: the 0034 runtime served again with the #52 worker). Serve C by default if it passes our
gates (reload storm 0 crashes in at least 5 runs, two consecutive VERDICT full runs, at least 3 clean C20 runs);
otherwise serve A; keep B staged.

### Why pins are keyed by commit, not by buildId

A and C serve **the same runtime** (`wasm64-4b025db7729c5f89`: identical `lean.wasm`, stock snapshots, packs; C's
`public/snapshots/index.json` is byte-identical to A's) with **different shells and workers**: `dist/` differs (main
bundle `index-CzXuAkOQ.js` vs `index-BvT6MV1R.js`, 4 bundles renamed) and so do `public/workers/lean.worker.js`,
`frontend/src/lsp-relay.ts` and `src/runtime/client.ts` (C has the 9fdf9b8 versions; 23 of the 26 vendored files are
identical, `multipin` comparison of the three `QED64-PIN`s). A release dir or lock keyed by buildId cannot hold both.
So everything that depends on the shell or the vendored sources is **per pin** (`pins/<id>/`, `release/<id>/`, id = the
first 7 hex digits of the QED64 commit), and everything that depends only on the binary pairing with `lean.wasm` is
**per runtime** and shared: the widget overlays, stage1, raw regions, bakes and the headless results. The headless
verifiers read only the runtime, the raw regions, the bakes and four vendored files (`pipeline/snapshot/snapshot-probe.mjs`,
`supervised-run.mjs`, `pipeline/toolchain/artifact-paths.mjs`, `public/workers/lsp-frames.js`), all identical in A and C.

### The model (scripts/lib/pins.mjs)

| Store | Per | Path |
|---|---|---|
| descriptor, lock, `QED64-PIN`, vendored sources | pin | `pins/<id>/{pin.json, QED64.lock.json, QED64-PIN, vendor-qed64/}` |
| release clone (dist + public) | pin | `release/<id>/` (the lock's `release.dir`) |
| widget overlays, headless results | runtime | `out/runtimes/<buildId>/{overlay/widgets7, overlay/widgets8, headless/}` |
| stage1, raw regions, bakes, bake keys, bake logs | runtime | `$W/runtimes/<buildId>/{stage1, raw, bake-out-w7/w8, bake-work-w7/w8, BAKE-KEY-w7/w8.txt, bake-logs/}` |

The **active** pin is a set of 15 symlinks at the old paths, so every existing script, test and doc path keeps working:
`QED64.lock.json`, `QED64-PIN`, `vendor/qed64`, `out/headless`, `out/overlay/snapshots/widgets{7,8}`, and in `$W`
`stage1`, `raw`, `bake-out-w7/w8`, `bake-work-w7/w8`, `BAKE-KEY-w7/w8.txt`, `bake-logs`. The descriptor `pins/<id>/pin.json` records
the commit, promote, kernel, buildId, the main bundle, the sha256 of the console-allowlist's notify line (line 627, the
same in all three pins), the served base trees (bump-51 for A and C, bump-0035 for B) and `liveness.builtIn` (A no, B
and C yes).

**No file hardcodes a pin any more.** The 16 former pin sites now ask `pins.mjs` (or the active lock): `serve.mjs`,
`bake.sh`, `judge-bake.mjs`, `pair-check.mjs`, `derive-raw.sh`, `run-controls.sh`, `summarize-stage4.mjs`,
`stage-trees.mjs` (default core lib and base N), `showcase.sh` (`BASE_SLIM`, `CORE_SRC`, `BASE_N`), the experiments'
`lib.mjs` and `x1-preflight.mjs`, `infra/worker.test.mjs`, and the console allowlist (`tests/ux/selectors.json` names
the QED64 bundle as `"@qed64-main-bundle"`, resolved by `pins.mjs resolveSelectors` in the UX lib, the bring-up lib,
`check-gallery.mjs` and X4). `showcase.sh verify`'s pin-constants check now FAILs on any real buildId outside
`gallery/pin.json` (generated, must equal the active pin's), on any hashed `/assets/index-<8>.js` name and on any
`release/wasm64-…` path (mutation-tested: a B buildId in a test file, a hashed bundle name, `gallery/pin.json` naming
another runtime: each FAIL; restored: OK).

**A running server keeps its pin.** `serve.mjs` resolves its pin once at start (the active pin, or `SHOWCASE_PIN=<id>`
to serve a staged pin on another port without switching; used for the reload storms below) and answers every request
with `X-Showcase-Pin: <id> <buildId>`. `showcase.sh serve`/`ux` and the UX suite's global setup refuse a server whose
header is not the active pin (two pins can share a buildId, so `pin.json` alone cannot tell). Every `showcase.sh ux`
record now carries `pin`, `pinEnd`, `servedPinStart` and `servedPinEnd`, and `ux-record.mjs whyNotVerdict` refuses a
record whose server did not serve the active pin throughout.

### Commands

* `scripts/showcase.sh pin list` — every registered pin, its status, store completeness and the UX verdicts on its lock.
* `scripts/showcase.sh pin current` — the active pin and all 15 links (FAIL on a missing, real or foreign link, a stale
  `gallery/pin.json`, or an interrupted switch).
* `scripts/showcase.sh pin check <id> [--full]` — the cheap store check `verify` runs for every **staged** pin
  (descriptor == lock; release file set and sizes == lock, `--full` adds sha256; main bundle; the allowlist's notify
  line; vendor file set == `QED64-PIN`; the runtime's stage1 buildId, raw and bake files; overlays: runtime, entries,
  sizes, init == this pin's stock init, mathlib == this runtime's bake).
* `scripts/showcase.sh pin use <id> [--dry-run] [--no-deploy]` — switch. Guards: registered; complete stores; no
  `serve.mjs` of this repo that follows the active pin; no bake; no headless run; no showcase UX run holding the
  browser lock. Each link is replaced by an atomic `rename(2)` of a fresh symlink, the lock link last, with a journal
  (`out/pins/switch-journal.json`, history in `out/pins/history.jsonl`); then `gallery/pin.json` is regenerated and,
  when `out/deploy/manifest.json` exists, the deploy manifest and staged assets too. Ends with `pin current`.
* `scripts/showcase.sh pin clone <id> [--yes]` — S0 for a registered pin: `pin-qed64.mjs pin --pin <id>` (QED64 HEAD
  must be the pin's commit and clean; S0.2 is re-checked after the clone, including that `dist/` was not rebuilt
  meanwhile), `record-widgets-hash`, `verify`. Writes only `pins/<id>/` and `release/<id>/`.
* `scripts/showcase.sh verify` — the **active** pin fully (`pin current`; `pin-qed64.mjs verify`: every release file's
  sha256, the git anchors, and the new **#10**: every `dist/` copy of a tracked `public/` file, including
  `dist/workers/lean.worker.js`, equals `git show <commit>:public/<f>`, so a stale or locally rebuilt dist is caught),
  then every **staged** pin cheaply (`pin check`), then pin constants, stage1, overlays, gallery freshness.

### What was done

1. **Inventory** (read-only, before any move). A's files were intact and never overwritten: `release/wasm64-4b025db7…`
   (145 files), `rollback/wasm64-4b025db7…/{QED64.lock.json, QED64-PIN, vendor-qed64, overlay/widgets7 (widgets.3619cfd5…),
   overlay/widgets8 (widgets.0880fd91…), out-headless/summary.json}`, `$W/rollback-wasm64-4b025db7…/{stage1 (lean.wasm →
   4b025db7…), raw, bake-out-w7/w8, bake-work-w7/w8, BAKE-KEY-*}`. B's were the live paths (overlays `widgets.a0c16868…`,
   `widgets.62e1f451…`, `$W/stage1` → 2c18773e…). So **no rebake was needed**: A's paired overlays exist, and C uses
   them because its stock index is byte-identical to A's.
2. **Migration** (`multipin-migrate.log`; a one-time script, guards: no showcase server, bake, headless run or
   showcase browser run). Moves on one filesystem (and APFS clones from `rollback/`, which stays intact as history):
   `release/<bid>` → `release/1859b83`, `release/9fdf9b8`; locks, `QED64-PIN`s and vendor trees into `pins/<id>/`;
   overlays and headless into `out/runtimes/<bid>/`; stage1, raw, bakes, keys into `$W/runtimes/<bid>/`. Each lock's
   `release.dir` was rewritten to `release/<id>`, and A's lock gained `qed64.kernel` (`9fbb45afcb…`, the first token of
   `git show 1859b83:pipeline/toolchain/KERNEL-PIN`; A was pinned before that field existed).
   So the locks' sha256 changed: A `ddf1a234…` (rollback copy) → `4954c633…`, B `bb97785a…` → `c05a7494…`; C's is
   `6d2cbd20…`. UX records name the lock by sha256, so the earlier B and A verdicts no longer match a current lock
   (`pin list` shows 0 runs on A's and B's current locks); none of them was on the current gallery anyway. The buildId-keyed
   descriptors of an interrupted earlier attempt went to `$W/multipin-migrate-backup/`.
3. **Pin C** (`multipin-pin-C.log`): QED64 HEAD `5ac5d00f99f7…`, `status --porcelain` empty, serving
   `wasm64-4b025db7729c5f89`: `S0.2 OK`, `S0.3 OK vendored 26 files`, `S0.4 OK cloned 145 files (1.676 GB logical) ->
   release/5ac5d00`, `S0.4 OK QED64 HEAD, status and dist/ unchanged during the clone`; widgets hash `16cdb73b…`
   recorded.
4. **All three pins hash-verified** (`multipin-verify-{1859b83,5ac5d00,9fdf9b8}.log`): `VERIFY OK (1 DRIFT in a
   rebuild-only input)` each (the known Docker tag drift), with `#9` (kernel) and the new `#10` OK on each.
5. **The gallery** (`gallery/gallery.js`): a late but real hover answer from Lean is now proof of life (gallery/README.md
   "Proof of life besides the hover"; `sim-gallery.mjs` run 12: `SIM-GALLERY OK 86 ok`; the mutant without the
   `late-answer` line: `SIM-GALLERY FAIL 84 ok, 2 failed`). The UX suite branches on the active pin's descriptor
   (`PIN.liveness.builtIn`) and requires the gallery's detection to agree: C21 (a) deferral and timing (30 s and about
   40 s with QED64's liveness, 10 s and about 20 s without), C22, and C23 (on a pin without QED64 liveness it asserts that
   the page has none instead of forcing a QED64 reboot; never a skip, which would end the verdict).
6. **A bug the migration exposed, root-caused and fixed.** The first headless controls on C hung in `b-e3-conv-wasm`
   with `error: no such file or directory (error code: 44) file: $W/runtimes/wasm64-4b025db7729c5f89/stage1/bin` in the
   wasm log: Node loads `lean.js` from its **real** path, and the runtime's own file lookups go there, while
   `wasm-lsp.mjs` mounted the **link** path `$W/stage1`. `wasm-lsp.mjs`, `headless/lib.mjs` (`DEFAULT_ARTIFACT`),
   `bake.sh` and `run-e2.sh` now pass real paths. (The probe process then waited forever instead of exiting; I stopped my
   own process. That pre-existing behaviour is noted, not changed.)
7. **A second store the first layout missed: the bake logs.** `showcase.sh --dry-run all` on C planned to rebake w7
   and w8: `judge-bake.mjs w7` was `RED (2 FAIL)` (J3 found the B runtime's "baked" line, J5 the B bake's
   `widgets.a0c16868…` url) because `bake.sh` wrote, and `judge-bake.mjs` read, `$W/logs/bake-widgets{7,8}.*`, which
   held the last bake (B's). Bake logs are now a per-runtime store too (`$W/runtimes/<bid>/bake-logs`, active link
   `$W/bake-logs`; `pin check` requires them), seeded by `cp -p` from `$W/rollback-wasm64-4b025db7…/logs/` (A's runtime)
   and `$W/logs/` (B's).

### Gating C (decision: C is served by default)

| Gate (orchestrator's rule) | Result on C `5ac5d00` |
|---|---|
| Reload storm, at least 5 runs, 0 crashes | **6/6 no crash** (`multipin-storm-C-{1..6}.log`; C served unswitched on :5196 with `SHOWCASE_PIN=5ac5d00`; `DEBUG=pw:browser`: 0 `V8 javascript OOM` lines; no new DiagnosticReport). QED64's pool at first ready `{unused 14, running 10, parked -1}` in all 6, peak 27 live workers, ready 6.1–8.0 s after the storm. Positive control on B (:5199, `SHOWCASE_PIN=9fdf9b8`) the same hour: **0/3 crashed** with `{running 18–20, parked 8}`; earlier A/Bs had 3/5. So the storm alone did not separate the arms that hour; C10 in the full runs below is the other half of the evidence. |
| Headless controls | `CONTROLS PASS` 11/11 (`multipin-headless-controls-C2.log`, under the browser lock, after the §6 fix) |
| Two consecutive VERDICT full runs | **`multipin-C-full2-b` and `multipin-C-full3-b`: 32 passed, 1 skipped (C19), VERDICT, VERDICT** (06:44–07:55Z; C10 passed in both). Before them, `multipin-C-full1` failed C12 + C14 on a new pageerror, root-caused to QED64 N2 (the page's heap meter; docs/UPSTREAM-REPORT-QED64.md N2, docs/UX-RESULTS.md "Multiple pins") and allowlisted only where a session is disposed; `multipin-C-full2` was refused before any test because the QED64 owner's snapshot bake was running (rc 3, recorded, never a result) |
| At least 3 clean C20 runs | **135/135 in 6 runs**: the three full runs and `multipin-C-c20-{1,2,3}` (`showcase.sh ux --grep "C20 "`), each 6.1 min, 0 stalls, 0 gallery wedges; QED64's own liveness 0 probes, 0 rescues, 0 stalls, 0 `wedged` reboots; pool max running 21–24 of 30, parked 0 |

**Later the same day: the reload-storm gate in desktop Chrome** (the l9-desktop lane, `out/ux/l9-desktop/RESULTS.md`;
docs/UPSTREAM-REPORT-QED64.md L9 "L9 in desktop Chrome"). The gate above was measured in chrome-headless-shell, the UX
suite's browser. Repeated in three builds of Chrome 151: C crashed 0/6 in headless-shell and 0/6 in new headless, but
**4/19 headed** (all V2, `MarkCompactCollector: young object promotion failed`, after reload 2–4); A crashed 1/5 headed
(V2); B 4/11 headless-shell (V1), 0/8 new headless, 3/8 headed (V1 and V2). **Decision (orchestrator rule applied by the
docs lane): C stays served.** The rule's fallback A does not avoid V2 (same runtime, also crashed headed), has no
QED64 L7 healing, and cannot reach a verdict with the current gallery (C22 (3), below); C removes V1 everywhere. V2 is
reported upstream with a suggested fix; the README status page states it as a known limitation for desktop visitors.

`scripts/showcase.sh pin list` (after the rehearsal): `* ACTIVE 5ac5d00 … stores complete … full UX runs on its
current lock: 4, VERDICT 2 (last multipin-C-full3-b)`; `node scripts/lib/ux-record.mjs freshness` → `UX CURRENT … run
multipin-C-full3-b`.

### Switch rehearsal (the fallback, rehearsed)

`multipin-rehearse-driver.log`; each step `pin use` → `verify` → `headless controls` (under the browser lock) → one gallery
boot (UX C1 cold boot through `showcase.sh ux --grep "C1 cold boot"`, i.e. under the lock, with the served-pin check):

| Switch | use | verify | controls | boot |
|---|---|---|---|---|
| r1 C → A (`1859b83`) | `PIN SWITCHED`, `PIN CURRENT OK` | `VERIFY: all checks OK` | `CONTROLS PASS` | passed, 13.2 s to ready, `CONSOLE OK` with the A bundle `index-CzXuAkOQ.js` |
| r2 A → C | OK | OK | PASS | passed |
| r3 C → A | OK | OK | PASS | **refused before the boot**: another session's Chrome was running (`REFUSED: chrome-headless-shell … already running … not ours to kill`): contention, not a result; A booted in r1 and again in the check below |
| r4 A → C | OK | OK | PASS | passed |
| r5 C → B (`9fdf9b8`) | OK | OK | PASS | passed (one boot, no crash) |
| r6 B → C | OK | OK | PASS | passed |

Each switch regenerated `gallery/pin.json` (A `e1affe4b…`, C `82ca43c1…`, byte-identical each time) and, because
`out/deploy` exists, the deploy manifest and staged assets (`DEPLOY-MANIFEST OK 75 assets, 93 R2 objects`,
`STAGE-ASSETS OK`). Every switch is in `out/pins/history.jsonl` (each took about 0.1 s). Refusals exercised:
`pin use 1859b83 --dry-run` while `showcase.sh ux`'s server ran → `REFUSED: this repo's serve.mjs is running without
SHOWCASE_PIN (pid 52546)` rc 3; an unregistered id → `REFUSED: no pin descriptor pins/abcdef0/pin.json` rc 3; a buildId
instead of an id → usage, rc 2.

**The liveness tests on the fallback A, in the browser** (`multipin-A-liveness.log`: `pin use 1859b83`, `showcase.sh ux
--grep "C2[123] "`, `pin use 5ac5d00`): **C21 passed with A's timings** (no QED64 liveness detected; probe after 10 s;
restart 20.4 s after the click; then the observe-mode part), **C23 passed its no-liveness branch** (worker has no
liveness functions, `status().liveness` absent, gallery `builtIn false`, `effectiveProbeAfterMs 10000`). **C22 (3) failed
on A**, as the README's L7 note predicts for a page without QED64's liveness: with 24 sleeping proofs the hover waits
about 55 s, no frame arrives and no late answer comes within the 2 × 5 s sequence, so the gallery restarted a healthy
session at about 21 s (`wedged 2, restarts 1`; then the restart's `QED64: restarting with exact imports` replies, which
C22 does not allow). The late-answer proof of life does not reach this case. **So A cannot reach a VERDICT with this
gallery; it remains a working fallback (verify, controls, boots, C21, C23 green), with that limitation.** A fix for A
would need a second probe the FileWorker's main loop answers without a pool thread (an unknown-method request with
params, as QED64's own liveness uses); not done in this lane, because changing `gallery.js` would void C's two
verdicts.

### Deploy kit on the active pin

After the last switch back to C: `node scripts/deploy-manifest.mjs --check` → `OK G1 … CHECK-GALLERY OK 123 ok`,
`info G2 UX: verdict run multipin-C-full3-b … was on THIS gallery a4b34ead…, lock 6d2cbd20… and overlays widgets8,
widgets7`, `DEPLOY-MANIFEST CHECK OK`; the manifest's pin is `{id: 5ac5d00, buildId: wasm64-4b025db7729c5f89, releaseDir:
release/5ac5d00}`, 75 assets, 93 R2 objects; `out/deploy/assets/assets/` holds only C's bundles (`index-BvT6MV1R.js`,
`index-CIBXteGo.js`, `index-CUNytiDm.js`): `--stage-assets` re-clones the directory from scratch, so the previous shell's
files are gone (S1 "exactly the manifest's 75 assets"). Deploy labels now carry the pin id (`pin 5ac5d00
(wasm64-4b025db7729c5f89) gallery …`), and the CI tarball is per pin id (`qed64-dist-<id>.tar.gz` from `release/<id>`).

**Deploy rehearsal re-run on C** (`scripts/deploy-rehearsal/rehearse.sh all`, then `browser`, `stop`; local fakes only,
sandboxed; `multipin-deploy-rehearsal-all2.log`, `-browser2.log`, about 16 min): `GUARD OK` (every shared-bucket misuse
refused, sentinel bucket unchanged), `FAKE-BUCKET OK: 93 objects under qed64-showcase/ … nothing else in the bucket`,
`FAKE-S3 OK` (8 JSON + 85 octet-stream, 3 multipart), `ROLLBACK DRY RUN OK`, `ROLLBACK OK` with its two refusals,
`DEPLOY DRY RUN OK` with its two refusals, `LOAD-R2 OK: 93 objects, 2.420 GB`, `SMOKE OK` (168 URLs, Range 206/416/If-Range
200), `BOOT-CHECK OK http://localhost:8790/showcase/#hasse-view` under the browser lock. **The first attempt failed, and
the cause was the rehearsal itself:** `FAKE-BUCKET FAILED` with 17 `unexpected object`s, all the 9fdf9b8 release's
digest-named objects left in the fake bucket by the previous rehearsal (B's runtime chunks, manifest and snapz); the
check "nothing else in the bucket" assumes a first upload. `rehearse.sh upload` now moves a non-empty fake bucket aside
(`$W/deploy-rehearsal/bucket.prev-<utc>`, 110 files this time) and uploads into an empty one; the second run is the
green one above. (In R2 the older pin's objects would simply stay; they are digest-named and harmless, and they are
what a rollback to that pin needs.)


## 2026-10-02: pin D (3b42714 / wasm64-3ab1c6a9da03bc29) registered and its stores built, without switching

Logs: `$W/logs/pinD-*` and `$W/logs/showcase-pinD-*` (`$W` = `/Users/fawadhaider/code/qed64-showcase-work`). The served
pin stayed C `5ac5d00` throughout (`pin current` → `PIN CURRENT OK 5ac5d00` before and after; no `pin use` was run).
D is QED64's candidate L9 fix: `3b42714` "promote kernel 0035b", runtime `wasm64-3ab1c6a9da03bc29`, kernel `a8817d01f9`
(0035 with the parked dedicated-thread cap at 0). The owner has not handed it over, so D is **staged**, not gated in the
browser.

| | C `5ac5d00` (served) | D `3b42714` |
|---|---|---|
| Runtime / kernel | `wasm64-4b025db7729c5f89` / 0034 `9fbb45afcb` | `wasm64-3ab1c6a9da03bc29` / 0035b `a8817d01f9` |
| Stock snapshots | `init.35c8c5f5…`, `mathlib.8df0689f…` | `init.b6d945e3…`, `mathlib.265cd10c…` (raw sizes identical) |
| Main bundle | `index-BvT6MV1R.js` | `index--2zyppQV.js` (console notify line 627: same sha256 `5b1d6aa8…`) |
| Workers, vendored sources | – | `public/workers/*` 4/4 and the 26 vendored files byte-identical to C's |
| Release set (145 files) | – | 124 identical; changed: `dist/index.html` and the three tracked indexes; 17 renamed (bundles, runtime chunks, manifest, snapz); profile packs 71/72 identical (`profiles/index.json` names the runtime) |
| Widget overlays | `widgets.3619cfd5…` (w7), `widgets.0880fd91…` (w8) | `widgets.7772b36c…` (w7), `widgets.07e4514f…` (w8) |

### What was done (in order)

1. **Preconditions** (read-only): QED64 `HEAD` = `3b42714df6ec…`, `status --porcelain` 0 lines, `runtime-manifest.json`
   and the one `dist/assets` bundle name `wasm64-3ab1c6a9da03bc29`; QED64's `dist/` and `public/workers/` equal the
   frozen copy's (`diff -rq`). The checkout was at the commit and clean, so the clone ran from QED64 itself; the
   frozen copy `$W/frozen-qed64-3b42714` served as a second witness (below) and as the stage1 source. No frozen-source
   clone path was needed or added.
2. **Registered** `pins/3b42714/pin.json` (label `D:`, `servedTrees` = `qed64/work/bump-0035b/slim`, `liveness.builtIn`
   true, `consoleSites` computed from line 627 of the bundle, which is the notify line).
3. **Clone** (`pinD-pin-clone.log`): `showcase.sh pin clone 3b42714 --yes` → `S0.2 OK … clean, serves
   wasm64-3ab1c6a9da03bc29`, `S0.3 OK vendored 26 files`, `S0.4 OK cloned 145 files (1.676 GB logical)`, `S0.4 OK QED64
   HEAD, status and dist/ unchanged during the clone`, `RECORDED WIDGETS_SOURCE_HASH 16cdb73b…`, `VERIFY OK (1 DRIFT in a
   rebuild-only input)`. The Docker tag `qed64-toolchain:emsdk-6.0.5` now points at `8228ea564e7b` (it drifted again;
   rebuild-only, `native` refuses; no Docker job was run).
4. **Native olean compatibility** (`pinD-olean-compat.log`, the earlier lanes' `cmptree.mjs`): D's served core library
   (`stage1/lib/lean`, frozen copy) vs C's runtime's (`stage1-4.34-4b025db7/lib/lean`): 32,798 files each, **32,795
   identical**: every `.olean`, `.ilean` (2,520 each), `.ir`, `.ir.sig`, `.olean.server`, `.olean.private` (2,518 each)
   with their hash/trace files. The three that differ are the link-time C++ runtime archives (`libleanrt.a`,
   `libleanshared.so`, and `libleancpp.a`, whose only difference is the embedded githash `9fbb45afcb…` → `a8817d01f9…`,
   shown by `dd`). The same holds for the slim inputs: `bump-0035b/slim/core-lib-slim` vs `bump-51` (the same three
   differ), `bump-0035b/slim/lib-tree-slim` vs `bump-51` **20,014/20,014 identical**. QED64's live `stage1` (47,927 files)
   and `work/bump-0035b` (50,316 files) are byte-identical to the frozen copy. The native pins are unchanged (verify #7
   OK). So the native delta and widget oleans are reused; no native rebuild.
5. **D's served base tree** (`pinD-base-tree.log`): `bump-0035b/stage.sh` bakes with `QED64_SLIM=work/bump-0035b/slim`;
   gunzip of D's served `init.b6d945e3….snapz` = `bump-0035b/snapshot/init.snap` (sha256 `800bb744…`, live and frozen)
   and gunzip of `mathlib.265cd10c….snapz` = `bump-0035b/snapshot/mathlib.snap` (`21637667…`); 5,004 `.olean` in the
   slim tree.
6. **Bringing up a staged pin without switching (new code).** The documented route (`pin use <id> --allow-incomplete`,
   then build through the active links) switches the served pin. Instead, every build and verification tool now takes
   a target pin, `SHOWCASE_PIN=<id>` (the convention `serve.mjs` already used): `scripts/lib/pins.mjs`
   `targetPinId()`/`targetBuildId()`/`storePath(entry)` (without `SHOWCASE_PIN`: the active link paths, unchanged; with
   it: that pin's own `pins/<id>/`, `release/<id>/`, `$W/runtimes/<bid>/`, `out/runtimes/<bid>/`), used by `bake.sh`,
   `judge-bake.mjs`, `pair-check.mjs`, `make-overlay.mjs`, `stage-trees.mjs` (vendored olean reader, default served
   trees), `preflight-overlays.sh` (its `PORT`, its own log names, and a refusal unless the port serves the target pin;
   never :5190 for a staged pin), `headless/lib.mjs` (lock, vendor, stage1, results dir `OUT_HEADLESS`),
   `rpc-probe.mjs`, `exact-header.mjs`, `react-contract.mjs`, `derive-raw.sh`, `run-controls.sh`, `run-stage4.sh`,
   `run-e2.sh` and `summarize-stage4.mjs`. `showcase.sh` refuses `ux`, `gallery`, `all` (they test the active pin) and
   `serve`/`stop` on :5190 for a target that is not the active pin (`pinD-guards.log`: rc 3 each), and refuses `stage`
   while a headless verifier holds `$W/headless/.lock` (the trees are shared by all runtimes). E2 rows now go to one TSV
   per runtime (`$W/logs/s4-e2.<bid>.tsv`; the summary falls back to the old shared `s4-e2.tsv`). **A latent bug fixed on
   the way:** `make-overlay.mjs` removed and recreated `out/overlay/snapshots/widgetsN`, which since the multi-pin layout
   is a pin link, so it would have replaced the link with a real directory; it now writes the store dir itself.
   Regression on the active pin: `judge-bake.mjs w7/w8` GREEN on C's bakes, `pair-check` of C's widgets7 overlay GREEN
   (`P1 buildIdOf($W/stage1)`), `pins.mjs store …` returns the link paths; on B, the summary regenerated with
   `SHOWCASE_PIN=9fdf9b8` has a `bakes` section equal to B's stored `summary.json` (`pinD-active-regress.log`).
7. **Stage1 store**: `cp -Rc` of the frozen `pipeline-stage1/bin` to `$W/runtimes/wasm64-3ab1c6a9da03bc29/stage1/bin`:
   buildId `wasm64-3ab1c6a9da03bc29`, `lean.wasm`/`lean.js` sha256 = the release manifest, nlink 1, `diff -rq` equal to
   QED64's live `stage1/bin` (`pinD-stage1.log`).
8. **Trees** (`SHOWCASE_PIN=3b42714 showcase.sh stage w7|w8 --force`; C's trees APFS-cloned to
   `$W/pinD-backup/trees/` first): `STAGE-TREES OK … EXPECTED-N=5107` (delta 39, own 64) and `EXPECTED-N=5684` (delta
   609, own 71), G1–G6 OK, G2 20,012 facet files byte-identical to the native build. The new trees are **byte-identical
   to C's** (20,234 and 22,521 files, `pinD-stage-cmp-w{7,8}.log`), so C's bakes and headless inputs are unaffected.
9. **Bakes** (`SHOWCASE_PIN=3b42714 showcase.sh bake w7|w8`, under the browser lock, queued behind other lanes;
   `pinD-bake-w{7,8}-attempt1.log`): w7 `rc=0 wall=367s`, `time -l maxrss 15,907,373,056 B`, `JUDGE w7: GREEN N=5107
   raw=1163657293 /snapshots/widgets.7772b36c004872af.snapz` (J4 k=0.811), `PAIRING GREEN`; w8 `rc=0 wall=368s`, maxrss
   13,532,233,728 B, `JUDGE w8: GREEN N=5684 raw=1267834573 /snapshots/widgets.07e4514f22d85756.snapz` (k=0.831; the
   known plan-range WARN), `PAIRING GREEN`. Raw sizes equal C's, bytes differ (binary pairing).
10. **Overlays** (`pinD-overlay.log`): `out/runtimes/wasm64-3ab1c6a9da03bc29/overlay/widgets{7,8}`, `PAIRING GREEN` with
    `CMP mathlib: inflated bytes == bake-work-wN/widgets.snap` (`5d225e7e…`, `50c6b02e…`); `raw/widgets{7,8}.snap` are
    APFS clones of the bake-work files.
11. **QED64's preflight** (`PORT=5196 SHOWCASE_PIN=3b42714 showcase.sh locked preflight-D -- bash
    scripts/preflight-overlays.sh widgets7 widgets8`, 12:26Z; `showcase-pinD-locked-preflight-D.log`): the server on :5196
    answered `X-Showcase-Pin: 3b42714 wasm64-3ab1c6a9da03bc29`; `PREFLIGHT OK buildId=wasm64-3ab1c6a9da03bc29
    mode=resident snapshots=snapshots/widgets7` (no-boot and boot, `ready in 12410 ms`) and the same for widgets8 (`ready
    in 13304 ms`); each boot fetched exactly `init.b6d945e3…` and its `widgets.<d16>` snapz.
12. **Headless** (`showcase.sh locked headless-D -- … headless all`, under the browser lock, 12:27–12:44Z;
    `pinD-headless-all-attempt1.log`, summary `out/runtimes/wasm64-3ab1c6a9da03bc29/headless/summary.json`):
    `CONTROLS PASS` 11/11 (raw init/mathlib derived from D's snapz into D's store); `STAGE4 all: 0 failing step(s)`:
    **E1 8/8 (w8), 7/7 (w7); E3 1167/1167 checks on w8 and 1038/1038 on w7; E3b 49/49 and 44/44 panels clean**; E2 7/8
    (tree-scope `Demo.lean:104` is L1, as on every pin; `headless all` exits 1 there by design). `headless summary`:
    `GATE {… "E2Green":true,"stage4Green":true}`, and its `e1.snapSha256` equal D's `bake-work` snaps.
13. **Checks after** (`pinD-final-checks.log`, `pinD-verify.log`): `pin check 3b42714 --full` → `PIN CHECK OK`;
    `pin-qed64.mjs verify --pin 3b42714` → `VERIFY OK (1 DRIFT …)`; `showcase.sh verify` → `VERIFY: all checks OK`
    (C fully, A, B and D cheaply); `pin current` → `PIN CURRENT OK 5ac5d00`; C's `summary.json` and bakes unchanged
    (`JUDGE` GREEN on C's `widgets.3619cfd5…`/`widgets.0880fd91…`).

### The overlay-runtime audit (pin use / current / check)

`pin current` (and so `verify`) now also checks that each active overlay link's `index.json` names the runtime the
active lock names; `pin check <id>` checks the pin's overlay stores against its own lock (for the active pin, the links
too); `pin use` re-checks the links after the switch. Mutation-tested on a sandbox copy (`pinD-audit-mutants.log`):
widgets8's index naming D's runtime behind an intact link → `current` rc 1 (`FAIL … index runtime
wasm64-3ab1c6a9da03bc29 == active lock runtime wasm64-4b025db7729c5f89`), `check` rc 1, `use` refused rc 3; a missing
widgets7 `index.json` → `current` rc 1; restored → OK.

### Not done in this lane (the remaining gates for D)

Nothing was switched, so no browser gate ran on D in this lane: the reload storms, the switch, two VERDICT full runs
and the C20 runs. **All of them were done by the final-gate lane (next section):** D passed every gate while served,
but its storms were not cleaner than C's, so C was re-chosen.

## 2026-10-02: final gate — D gated while served, C re-chosen as the served pin

Lane `final-gate` (logs `$W/logs/final-*` and `final-gate-*`; `$W` = `/Users/fawadhaider/code/qed64-showcase-work`).

**Storms first, without switching** (`out/ux/final-storm/RESULTS.md`). A, B, C and D were served at the same time on
their own ports (`SHOWCASE_PIN` + `GALLERY_DIR`: `:5211` A, `:5212` B, `:5213` C, `:5214` D; each gallery copy's
`pin.json` derived from that pin's lock with build-gallery's rule, self-checked byte-equal to `gallery/pin.json` for C).
Five interleaved rounds of 16 runs (pins × chrome-headless-shell / headed Chrome for Testing × stock page /
`/showcase/`), then a dedicated 18-run headed round on a quiet host (A, C, D):

| pin | rounds | quiet round | all |
|---|---|---|---|
| A `1859b83` | 0/20 | 3/6 | 3/26 V2 |
| C `5ac5d00` | 1/20 | 1/6 | 2/26 V2 |
| D `3b42714` | 1/20 | 2/6 | 3/26 V2 (+1 V2 in the tool's smoke run) |
| B `9fdf9b8` | 3/20 V1 | – | 3/20 V1 |

**Switch to D and gate** (17:35Z, before the quiet round had run; at that point D and C were level at 1/20):
`showcase.sh stop` (nothing on :5190), `pin use 3b42714` → `PIN SWITCHED 5ac5d00 -> 3b42714`, deploy inputs regenerated
(gallery `eab4f147…`), `PIN CURRENT OK 3b42714`; `verify` → `VERIFY: all checks OK` (1 Docker DRIFT, rebuild-only);
`headless controls` under the lock → `CONTROLS PASS`; `gallery` → `CHECK-GALLERY OK 128 ok`, `SIM-GALLERY OK 101 ok`.
Then `final-D-full1` (17:38–17:59Z) and `final-D-full2` (17:59–18:20Z): **33 passed, 1 skipped (C19), VERDICT each**,
pin `3b42714` served from start to end, lock `6e59e283…`. The headed sign-off: `final-D-headed1` failed 7 (root causes
in docs/UX-RESULTS.md "Final gate": the stock page's favicon 404 in desktop Chrome (QED64 N3), glyph rasterisation
against the headless baselines, one C4 timing race), then, after headed-only baselines and the N3 allowance,
`final-D-headed2` **34 passed (C19 included): HEADED SIGN-OFF**.

**The quiet round then put D behind C** (19:12–19:24Z: D 2/6, C 1/6, A 3/6, all V2 on `/showcase/`). The rule was "D if
its storms are at least as clean as C's"; over all windows D has 3/26 against C's 2/26, so **C stays served** (the
difference is one crash; D removes V1 but not V2, like C). `pin use 5ac5d00` (19:26Z) → `PIN SWITCHED 3b42714 -> 5ac5d00`, deploy
inputs regenerated (gallery `2081098d…`, the gallery of `harden-C-full1`), `PIN CURRENT OK 5ac5d00`; `verify` → all
checks OK (the same DRIFT); `headless controls` → `CONTROLS PASS`; `gallery` → `CHECK-GALLERY OK 128 ok`, `SIM-GALLERY
OK 101 ok`, `UX CURRENT … harden-C-full1`. Then on C and gallery `2081098d…`: `final-C-full1` (19:29–19:50Z) and
`final-C-full2` (19:50–20:11Z), **33 passed, 1 skipped (C19), VERDICT each**, back to back; `final-C-headed1`
(20:12–20:34Z) **34 passed: HEADED SIGN-OFF**; `final-C-c20-{1,2,3}` 135/135 each (docs/UX-RESULTS.md "Final gate").
`pins/5ac5d00/pin.json` and `pins/3b42714/pin.json` `status` said so then (since the final audit, 2026-10-03, `status` is a
hand-written role note and `pin list` computes the verdicts and sign-offs).

**Deploy rehearsal on C and that day's gallery `2081098d…`** (`scripts/deploy-rehearsal/rehearse.sh all`, then `browser`, `stop`;
`$W/logs/final-deploy-rehearsal-{all,browser,stop}.log`, rc 0 each): `GUARD OK` (sentinel bucket unchanged), the
previous fake bucket (93 files) moved aside to `$W/deploy-rehearsal/bucket.prev-20261002T205606Z`, `FAKE-BUCKET OK: 93
objects`, `FAKE-S3 OK` (3 multipart), `ROLLBACK DRY RUN OK`, `ROLLBACK OK`, `DEPLOY DRY RUN OK`, `LOAD-R2 OK: 93 objects,
2.420 GB`, `SMOKE OK` (168 URLs), `BOOT-CHECK OK http://localhost:8790/showcase/#hasse-view` (26 artifact GETs, all 200;
1 page error, the allowlisted N1), `stopped; nothing listens on 8790`. Then `node scripts/deploy-manifest.mjs --check`
→ `G1 … CHECK-GALLERY OK 128 ok`, `G2 UX: verdict run final-C-full2 … was on THIS gallery 2081098daa7c9d72…, lock
6d2cbd20b8b6… and overlays widgets8, widgets7`, `DEPLOY-MANIFEST CHECK OK` (`final-deploy-manifest-check.log`).

**Bring-up note:** `pin use` regenerates `gallery/pin.json`, so each switch changes the gallery hash (D: `eab4f147…`; C:
`2081098d…`); verdicts are per gallery, which is why C needed its own two runs after the switch back.

## 2026-10-04: pin E (33b0967 / wasm64-3ab1c6a9da03bc29) registered without switching; shares D's runtime stores

Lane `pinE` (logs `$W/logs/pinE-*` and `$W/logs/showcase-pinE-*`; `$W` = `/Users/fawadhaider/code/qed64-showcase-work`).
Nothing was switched: the served pin stayed what `pin current` printed before the lane. E is QED64 main `33b0967`, the
merge of `fix/v2-reload-oom` (`9c00688`, HARDENING #55: runtime lifetime locks, QED64's fix for L9 V2) over `3e182ff`
(HARDENING #54: the boot card stays until ready on slow links, "about 8–9 GB"), plus `5e94697`/`76be299` (download
progress reported inside runtime chunks and core pack parts). The user pushed `3e182ff` and `fix/v2-reload-oom`.

| | D `3b42714` | E `33b0967` |
|---|---|---|
| Runtime / kernel / promote | `wasm64-3ab1c6a9da03bc29` / `a8817d01f9` / `3b42714` | the same (`3b42714` is still the last commit that changed `public/runtime/runtime-manifest.json`) |
| Tracked JSON (snapshot index, runtime manifest, 3 profile indexes) | – | the same git blobs at both commits; release sha256 equal |
| Release set (145 files) | – | 138 identical (all 87 `public/` files); changed: `dist/index.html`, `dist/workers/lean.worker.js`, `dist/workers/snapshot-prefetch.worker.js`; 4 renamed bundles |
| Main bundle | `index--2zyppQV.js` | `index-DpYTUbic.js`; console notify line0 627: new sha256 `d7af4642…`, but the same code (below) |
| Vendored sources (26) | – | 6 differ: `frontend/index.html`, `qed64-boot.ts`, `lean.worker.js`, `snapshot-prefetch.worker.js`, `src/install/profiles.ts`, `src/runtime/client.ts` |

### What was done (in order)

1. **Preconditions** (read-only; `$W/logs/pinE-precond.log`). At 20:30 local QED64's `dist/` was stale (no
   lifetime-lock code). It was rebuilt by the QED64 session at 20:33:57 local; this lane found it at 00:34Z: `HEAD`
   = `33b09679077b3fea245123e261a7f0942918469f`, `status --porcelain` 0 lines, no build process running. The 4 `dist/`
   copies of tracked `public/` files equal `git show HEAD:public/<f>` (including `dist/workers/lean.worker.js`).
   `qed64-alive`/`qed64-wanted` occur in `dist/workers/lean.worker.js` and the main bundle, and in D's release in
   neither. The only bundle buildId is `wasm64-3ab1c6a9da03bc29`, which equals `public/runtime/runtime-manifest.json`.
   `dist/index.html` carries the #54 text "about 8&ndash;9&nbsp;GB". `public/embed-host.html` (new, tracked) is not
   in `dist/`, by design: it is dev-only, and the production build copies only `public/workers/*`. So the self-build
   fallback (git archive + `npm ci` outside QED64) was not needed and not added.
2. **Registered** `pins/33b0967/pin.json` (label `E:`, `servedTrees` = D's `bump-0035b`, `liveness.builtIn` true). The
   console notify line (`selectors.json` line0 627) has a new sha256 because the minifier renamed identifiers: a token
   diff against D's line shows 2195 tokens each, an identical non-identifier skeleton and 15 consistent renames
   (`Xz→Zz`, `vUt→wUt`, …), and the line still contains `notify({severity:` (`$W/logs/pinE-notify-line.log`).
3. **Clone** (`pinE-pin-clone.log`, rc 0): `S0.2 OK … clean, serves wasm64-3ab1c6a9da03bc29`, `S0.3 OK vendored 26
   files`, `S0.4 OK cloned 145 files (1.676 GB logical)`, `S0.4 OK QED64 HEAD, status and dist/ unchanged during the
   clone`, `RECORDED WIDGETS_SOURCE_HASH 16cdb73b…`, `VERIFY OK (1 DRIFT in a rebuild-only input)` (the known Docker tag
   drift).
4. **Same runtime as D, by digest** (`pinE-vs-D-digests.log`): the lock's sha256 of `public/snapshots/index.json`
   (`12c670a3…`), `public/runtime/runtime-manifest.json` (`5cfa0488…`) and `public/profiles/index.json` (`66e77ad3…`)
   are equal in E's and D's locks. All 87 `public/` release files, the anchors, the toolchain block and
   `WIDGETS_SOURCE_HASH` are also equal. So D's runtime stores (`$W/runtimes/wasm64-3ab1c6a9da03bc29/` with stage1, raw,
   bakes and keys; `out/runtimes/wasm64-3ab1c6a9da03bc29/` with overlays and headless) serve E unchanged. Nothing was
   rebaked.
5. **`pin check 33b0967 --full`** → `PIN CHECK OK 33b0967 (full)` (`pinE-pin-check-full.log`): 145 release files
   sha256 == lock, main bundle and notify line == descriptor, the 26 vendored files, stage1 buildId, raw regions and
   bakes, and overlays `widgets7`/`widgets8` (runtime == lock, init == this pin's stock init).
6. **Headless controls on E** (`SHOWCASE_PIN=33b0967 showcase.sh locked controls-E -- … headless controls`, under the
   browser lock, queued FIFO behind four lean4game jobs; ran 01:07Z; `pinE-controls.log`, `=== exit=0`):
   **`CONTROLS PASS` 11/11**. Its outputs (in the runtime's shared headless store; D's copies were APFS-cloned first
   to `$W/pinE/backup-*/`) equal D's of 2026-10-02 except timestamps, timings, memory figures, paths (`raw/` link vs
   store path, `release/33b0967`), a session id and an LSP frame count (109 → 105; inferred: timing-dependent
   notifications). No verdict or check changed (`pinE-controls-vs-D.log`).
7. **Headless stage 4 on E** (`… locked stage4-E -- … headless stage4 all`; `pinE-stage4.log`): under the lock 01:32–01:39Z, after a FIFO wait behind
   lean4game jobs; `=== exit=0`; **`STAGE4 all: 0 failing step(s)`**, 45 steps, all rc 0 (`pinE-stage4-tally.log`):
   **E1 8/8 (w8) and 7/7 (w7); E3 1167/1167 checks on w8 and 1038/1038 on w7; E3b 93/93 panels clean** (49 + 44).
   These are D's figures exactly. `headless summary --out $W/pinE/summary-E.json` (a separate file; the runtime's shared
   `summary.json` was not rewritten) → `GATE {… "E2Green":true,"stage4Green":true}`. Its E2 rows are the runtime's
   (`s4-e2.wasm64-3ab1c6a9da03bc29.tsv`, D's run): E2 was not re-run, because it uses the same runtime and the same
   tree-fat region.

8. **Checks after** (`pinE-final-pin-list.log`, `pinE-final-verify.log`, `pinE-untouched-check.log`). `pin list`
   shows `staged 33b0967` with 0 UX runs. `showcase.sh verify` → `PIN CURRENT OK 5ac5d00`, `VERIFY: all checks OK`,
   the same Docker DRIFT, and `PIN CHECK OK` for A, B, D and E (cheap). `assert-untouched.sh check pinE` → `CHANGED`,
   and only `wasm64-lean4game`: its HEAD moved `22eda45` → `0f2ecb7`, four commits at 2026-10-03 21:35 local (01:35Z) by
   the concurrent lean4game session ("Sync the qed64 closure to 76be299 …"), which held the browser lock between this
   lane's jobs. QED64 (HEAD `33b0967`, clean), both kernel trees and `widgets-v4.34`: OK, no file newer than the stamp.

### Do the headless tools exercise the new Web Locks code? No (shown, not assumed)

HARDENING #55's lifetime locks are `navigator.locks.request("qed64-alive:<id>" | "qed64-wanted:<id>")` in
`public/workers/lean.worker.js` (and its pthread prelude) and in `src/runtime/client.ts`, which is bundled into the page.
**Node v26.3.0 ships `navigator.locks` natively** (a `LockManager`; a request is granted and `query()` answers), so no
shim was needed or added. The headless verifiers, however, never load those files. They boot `lean.js` from the stage1
store in Node and take only three files from the vendored QED64 tree: `pipeline/toolchain/artifact-paths.mjs`,
`public/workers/lsp-frames.js` and `pipeline/snapshot/snapshot-probe.mjs`. All three are byte-identical at D and E.
Runtime evidence: the controls and stage 4 ran with an **observation-only** preload,
`NODE_OPTIONS=--import $W/pinE/trace-preload.mjs`. It lives in the work dir, not in the repo's tools, and changes no
behaviour. It records module resolutions, fs reads of QED64-derived paths and every `navigator.locks.request/query`
call, per Node process. A self-test confirmed that it records all three. The controls produced 41 traces, covering
`exact-header`, `rpc-probe`, `snapshot-probe`, `react-contract`, `pins.mjs` and 96 `lean.js` pthread starts. In every
process `navigator.locks` was available, it was called **0 times**, and the QED64-derived files touched were exactly the
three above plus E's stock snapshot index and two snapz (`pinE-controls-trace.log`). Stage 4 gave the same result over 86 traces (15 each of
`exact-header`, `snapshot-probe`, `rpc-probe` and `react-contract`, and 720 `lean.js` pthread starts): 0
`navigator.locks` calls, and only the same three vendored files (`pinE-stage4-trace.log`).
So headless green on E says the same as on D (the runtime and the snapshots). It says nothing about #55. The lifetime
locks only act in a browser, between a stopping and a booting runtime, and need the browser gates below.

### Not done in this lane (the remaining gates for E; done by the pin-e lane, next section)

E was staged. QED64 reports that #55 removes L9 V2 in its own headed embedded storms (17/48 → 0/36). We have not
measured that. The next steps are README "Re-pin" steps 5–8: storm E interleaved with C (and D) on both entries,
including `/showcase/` on a quiet host and the v2-embed iframe arm. Switch only if E's V2 count is at most C's in the
same windows. Then `pin use 33b0967`, `verify`, `headless controls`, `gallery`, two full `ux` VERDICTs, a headed sign-off,
three C20 runs, and the throttled first visits, because the #54 boot card now stays until ready (gallery/README.md
"Timeouts").

## 2026-10-04: pin E gated on the visitor path and served (C → E)

Lane `pin-e` (logs `$W/logs/pinE2-*`, tools `$W/pinE2/`; full record `out/ux/pin-e/RESULTS.md`).

**Storms first, without switching.** E and C were served on their own ports (`SHOWCASE_PIN` + `GALLERY_DIR`: `:5241` E,
`:5243` C; gallery copies by `$W/final-gate/pin-gallery.mjs`), and both pins were stormed on the visitor's path
`/showcase/#hasse-view`, interleaved per rep, each batch after a 300 s quiet streak. The tool was the v2-embed lane's arm
S (`$W/v2embed/reload-storm-embed.mjs`).

| | headed Chrome for Testing 151 | chrome-headless-shell 151 |
|---|---|---|
| E `33b0967` | **0/20** | **0/8** |
| C `5ac5d00` | **0/20** | **1/8** (V2) |

E was at least as clean as C, so it was switched in. **This does not confirm #55:** C itself had 0/20 headed in these
windows (15/24 in the v2-embed lane on 2026-10-03), so the storms show only that E is not worse. Host-forced deviations,
all recorded in RESULTS.md: a 14 GB quiet threshold (the idle baseline was 15.0 GB, held by the user's desktop apps), and
idle lock waiters of the lean4game session not counted as heavy.

**Switch** (05:18:08Z): `showcase.sh stop` had nothing to stop (nothing on `:5190`). `pin use 33b0967` → `PIN SWITCHED
5ac5d00 -> 33b0967`, `gallery/pin.json` regenerated (gallery `bbdbc932…`, byte-identical to E's storm copy), deploy
inputs regenerated, `PIN CURRENT OK 33b0967` with both overlays' runtime == lock. `verify` → `VERIFY: all checks OK` (the
known Docker DRIFT; `PIN CHECK OK` A, B, C, D). `gallery` → GREEN (`CHECK-GALLERY OK 128 ok`, `SIM-GALLERY OK 114 ok`).
`headless controls` was not re-run: it ran on E (`CONTROLS PASS` 11/11) in the pinE lane, and nothing it reads changed.

**Gates on E and gallery `bbdbc932…`:** `pinE-full1` (05:22–05:46Z) and `pinE-full2` (05:46–06:27Z): 33 passed, 1 skipped
(C19), **VERDICT** each, back to back. `pinE-headed1` (06:27–06:53Z): **34 passed, HEADED SIGN-OFF**. Throttled first visit
at 10 Mbit/s / 40 ms (`throttle-proxy.mjs` → serve `:5197`): **`RESULT PASS`, rc 0**, ready at 565.1 s, error card in 0
samples, panel equal to golden. QED64's boot card (#54) stayed visible until ready, and the gallery's notice came at
466.9 s (gallery/README.md "Timeouts").

**Deploy:** manifest regenerated (byte-identical to `pin use`'s), `deploy-manifest --check` → `G2 UX: verdict run
pinE-full2 … was on THIS gallery bbdbc932…, lock fa3e31b06f1e…`, `DEPLOY-MANIFEST CHECK OK`. `scripts/deploy-rehearsal/rehearse.sh all`, `browser` (`BOOT-CHECK OK http://localhost:8790/showcase/#hasse-view`) and `stop`, rc 0 each.

**Not done:** three `ux --grep "C20 "` runs on E. The full runs' C20 passed in each (135 links per run), and E has no
separate C20 tally yet. Also not done: the 50 Mbit/s first visit.

**Switch back:** `scripts/showcase.sh stop && scripts/showcase.sh pin use 5ac5d00`, then `verify`, `gallery`, and two
`ux` runs on the gallery that produces (C's pin.json gives back C's gallery hash for the same gallery code).


## 2026-10-04: repository move and portability (R1 lane) — no pin change, every lock rewritten

The project moved from a stand-alone directory next to the widget tree into the widgets repository
(github.com/FawadHa1der/lean-widgets) as `qed64-showcase/`; the widget packages moved to the repository's `packages/`.
The served pin stays E `33b0967` (runtime `wasm64-3ab1c6a9da03bc29`); no bake, overlay, release file or store changed.
Logs: `$W/logs/r1/`.

* **Widget sources.** `$W/widgets-src` was an rsync copy of the widget working tree (251 files, WIDGETS_SOURCE_HASH
  `16cdb73b…`). It is now `git archive <WIDGETS_COMMIT> packages/` (`scripts/export-widgets.mjs`; 222 files,
  `c2efe78f…`, WIDGETS_COMMIT `90e415c`, the commit that moved the packages). The old export's nine package directories
  are byte-identical to the new export (`diff -r`, `widgets-src-old-vs-new-packages.log`; `export-widgets.mjs --check`
  on the old export: missing 0, differing 0, extra 29 = the top-level README/test-all.sh/showcase/.github files the
  native build never read), so the served build's widget inputs are unchanged. The old export was moved to
  `$W/widgets-src.prev-2026-10-04T16-39-56-372Z`, not deleted. Every lock records `WIDGETS_COMMIT` beside the hash
  (`record-widgets-hash`), keeps the old hash under `WIDGETS_SOURCE.history`, and `verify` re-derives every exported
  file's git blob id against `git ls-tree WIDGETS_COMMIT packages/` (plus a DRIFT line when `HEAD:packages` moved on).
* **Machine paths out of the locks and descriptors.** `qed64.repo` is the upstream URL (`checkout: ${QED64_REPO}`),
  `toolchain.native64.dir` is `${QED64_KERNEL_BUILD}/native`, `WIDGETS_SOURCE.dir` is `${QED64_SHOWCASE_WORK}/widgets-src`,
  and `pin.json servedTrees.{baseSlim,coreSrc}` start with `${QED64_REPO}` (expanded by `scripts/lib/pins.mjs field`).
  The values resolve to the same paths on this machine (`.env.local`).
* **Consequences.** All five locks changed bytes, so every `lockSha256` changed: `gallery/pin.json` was regenerated
  (gallery `bbdbc932…` → `98ad69f6…`, same code), the earlier UX verdicts no longer match the current gallery + lock, and
  staged pins show 0 verdicts on their current lock in `pin list` (their history is unchanged in
  `out/ux/showcase-ux-runs.jsonl`). The deploy manifest differs from the written one only in the lock sha256, the gallery
  hash and `gallery/pin.json` (R2 objects identical).
* **Vendored QED64 sources** (`pins/*/vendor-qed64/`) are no longer meant to be committed: `scripts/fetch-vendor.mjs`
  re-creates them from a QED64 checkout and checks them against the committed `QED64-PIN` (rehearsed into a scratch dir:
  all five byte-identical to the existing copies).
* **Browser lock** is host-wide (`~/.cache/host-browser-lock/browser.lock`, FIFO ticket queue); the old location keeps a
  compatibility stub `scripts/with-browser-lock.sh` that execs the new wrapper.
* **Re-run in the new location (2026-10-04, lane r1, logs `$W/logs/r1/`).** `showcase.sh verify` OK (1 Docker DRIFT,
  as before), `gallery` gate GREEN on `98ad69f6…`, `pin current` OK, `check-portable` OK on a clean clone. UX:
  `r1-relocated-full1` (17:00–17:24Z) was red, 32 passed / 1 skipped / **1 failed: C10's driver-timing assertion
  "5 reloads within 15 s"** (reloads issued at 12, 4912, 6618, 9041, 15989 ms; `page.reload` waited ~7 s for the 4th
  commit; everything else in C10 held: ready, panel equal, no crash, 26 workers alive, settled 9.86 GB < 10.5 GB). On
  pin E that budget was already tight: earlier E runs put the 5th reload at 12886–13412 ms (pinE-headed1, pinE-full1),
  against ≈12020 ms on C; a slower reload commit on E's lifetime-lock shell is the likely cause (inference, not
  traced). The assertion was not changed. `r1-relocated-full2` (17:50–18:13Z) was a **VERDICT**: 33 passed, 1 skipped
  (C19), C10 5th reload at 12015 ms. `deploy-manifest.mjs` regenerated `out/deploy` (previous manifest and rclone lists
  copied to `$W/logs/r1/out-deploy-pre-r1/`); `--check` OK with G2 naming `r1-relocated-full2`.

## 2026-10-04: QED64 as a submodule, the page built from source, binaries fetched by hash (R2 lane) — no pin change

The served pin stays E `33b0967`. Nothing that is served changed: the same 145 release files and the same overlays,
all verified against the locks. Logs: `$W/logs/r2/`.

* **Source dependency.** QED64 is the git submodule `qed64-showcase/deps/qed64` (https://github.com/FawadHa1der/QED64.git),
  checked out at E's commit; its gitlink is the served pin's source pin. The staged pins A, B, C and D are git worktrees
  of the submodule's own repository in `$W/qed64-pins/<id>` (`scripts/qed64-src.mjs ensure --all`). All five pin
  commits are on QED64's `origin/main`. Every vendored copy is gone: `pins/*/QED64-PIN`, the `vendor/qed64` link and
  `scripts/fetch-vendor.mjs` were removed from git, and `pins/*/vendor-qed64/` was moved to
  `$W/r2-moved-aside/vendor-qed64/`. Before that, all 128 vendored files were proved byte-identical to `git show
  <commit>:<path>` in the submodule repository (`vendor-vs-submodule.log`). The following now read QED64's modules from
  the pin's checkout: `bake.sh`, `stage-trees.mjs`, `pair-check.mjs`, `headless/{lib,exact-header,wasm-lsp}.mjs`,
  `run-e2.sh`, `preflight-overlays.sh`, `check-gallery.mjs` and `tests/experiments/x1`. `serve.mjs`,
  `deploy-manifest.mjs` and `infra/worker.js` import QED64's `isImmutable` instead of copying it, and wrangler bundles
  the import. verify #8 is now "sources == commit, unmodified; gitlink == HEAD == lock; no vendored copy".
* **Locks v2** (every lock rewritten again; the earlier copies are in `$W/logs/r2/locks-before/`). `vendor` and
  `qed64.checkout` were dropped. The new `source`, `shell` and `artifacts` sections say how each part is obtained, and
  `overlays` records the sha256 and size of the six overlay files of the pin's runtime (`pin-qed64.mjs
  record-overlays`; verify #11). `toolchain.docker.equivalent` records image `8228ea564e7b` (below).
* **Shell from source.** `scripts/build-shell.mjs` runs QED64's `npm ci --prefix frontend && npm run build:site` in the
  pin's checkout. Fresh public clones of all five pin commits rebuilt their 58 dist files byte-identical to the served
  releases (macOS, Node v26.3.0: `shell-det-*.log`), and so did Linux (`node:26-bookworm`, Node v26.7.0:
  `linux-rehearsal-1.log`). The lock's sha256s are therefore the check, and nothing is installed unless all 58 files
  match.
* **Binaries fetched by hash.** `scripts/fetch-artifacts.mjs` takes the five tracked manifests from git and fetches
  every other `public/` file and the overlays from an artifact origin, checking sha256 against the lock. It is
  resumable, and a mismatch is kept as `.rejected-<time>` and never installed. QED64's live origin served all 81 files
  of pin E with the lock's sizes (`live-qed64-remote-check.log`). A fresh clone fetched them from it, 1.38 GB, after a
  deliberate interruption at 30 s (`clone-fetch-live-*.log`). The overlays came from a local origin (`serve.mjs` on
  :5297).
* **`showcase.sh bootstrap`** makes a clone a working showcase: sources, `npm ci`, widget export, shell, artifacts, the
  serve links (`pin use`), verify. A checkout that serves fetched artifacts reports its runtime's build stores as
  ABSENT. A staged pin it never bootstrapped is NOT MATERIALIZED, a missing kernel build or browser is N/A, and the Node
  version is a DRIFT. All of these are printed and counted. `pin use` now also moves the submodule and stages the
  switch (the lock link, `gallery/pin.json` and the gitlink).
* **Fresh-clone proof.** `git clone --recursive` of this repository into
  `$W/clone-test/lean-widgets` (and into `$W/clone-test/clone with spaces/lean widgets`), each with a fresh work dir
  and no `QED64_REPO` or kernel build. Bootstrap was OK and `verify` all OK (1 N/A). The `gallery` gate was GREEN on
  `49d06172…`. Serving on :5298 gave the same served gallery hash, pin header and COEP. Staged pin C was bootstrapped
  into a worktree and passed `pin-qed64 verify --pin 5ac5d00`. The pin switch E → C → E kept verify OK. `lake build &&
  lake test` of `packages/simp-lens` passed in the clone with the stock toolchain (`clone-lake-simp-lens.log`).
* **UX.** The full suite ran in the fresh clone (commit `5290c80`, lock v2 `74f96787…`, gallery `49d06172…`) through
  the host browser lock: `r2-clone-full1`, 19:05–19:52Z, browser from 19:28:55Z. It was a **VERDICT**: 33 passed, 1
  skipped (C19), 0 unexpected, the served gallery equal to the local one from start to end, pin `33b0967`
  (`clone-ux-full1.log`, `clone-ux-full1.record.json`). The image-equivalent commit then changed every lock again, so
  the main checkout ran the suite on the final lock `190f09de…` and gallery `3b4dc8bb…`:
  * `r2-main-full1` (browser 20:09–20:31Z) was red: 32 passed, 1 skipped, **1 failed (C10)**. The renderer crashed
    during the reload storm (`tests/C10.s14.console.jsonl`: `{"kind":"crash","t":10403}`, renderers 0). That was about
    1 s after QED64 logged `[qed64] starting Lean` following the second reload, at 3003 ms. Playwright then failed the
    next `page.reload` ("Target page, context or browser has been closed"). The timing fits L9 V2, a crash about 2 s
    after reloads 2–4; that is an inference, since the crash reason is not captured. It is the first renderer crash in
    C10 on pin E, after 0 in 6 earlier E runs (including the clone's). QED64 reports #55 as the V2 fix (README "L9"), so
    this is evidence for the upstream report, not a defect of this lane: the served bytes were the same verified files.
    Tool gap found: the run's `tests/C10.json` records `"crashed": false`, because the spec threw before recording the
    crash, so `scripts/ux-tally.mjs` counts this run as "failed", not "crashed" (`ux-tally-after-main-full1.txt`).
  * `r2-main-full2` (browser 20:34–20:57Z) was a **VERDICT**: 33 passed, 1 skipped (C19), C10's 5th reload at
    12017 ms (`main-ux-full2.log`, `main-ux-full2.record.json`). `deploy-manifest.mjs --check` is OK, and its G2 names
    `r2-main-full2` (`main-deploy-manifest-check-final.log`).
* **CI.** `.github/workflows/showcase-source.yml` runs on Linux without any artifact origin: sources check, the page
  built from source, `fetch-artifacts --git-only` (the tracked manifests), the widget export, the worker tests, the
  gallery gate. The first mirror run in `node:26-bookworm` found the gallery data STALE without the runtime manifest,
  which led to `--git-only`. The second ran all 9 steps rc 0, plus a serve smoke (`linux-ci-mirror-{1,2}.log`).
  `actionlint` passes. `wrangler deploy --dry-run --outdir` bundles `infra/worker.js` with QED64's `isImmutable`
  tree-shaken in from `deps/qed64/infra/worker.js` (6.72 KiB; `wrangler-dry-run.log`).
* **Linux.** `scripts/lib/platform.{sh,mjs}` provide the memory probe (`vm_stat` / MemAvailable), copy-on-write clones
  (`cp -c` / `cp --reflink=auto`) and caffeinate (macOS only). The browser-lock wrapper, `showcase.sh`,
  `preflight-overlays.sh`, `pin-qed64.mjs`, `deploy-manifest.mjs`, `make-overlay.mjs`, `stage-trees.mjs`,
  `build-native.sh` (nlink) and the Node memory helpers use them. In `node:26-bookworm`, the following all exited 0:
  clone, bootstrap, verify, gallery, `fetch-artifacts --check`, the worker tests, lockfifo, lockrace, `check-portable`
  and `deploy-manifest` generate/`--check`/`--stage-assets` (`linux-rehearsal-1.log`). The steps that remain macOS-only
  are listed in docs/ARCHITECTURE.md "Platforms". `lockrace.sh` now copies the platform helper and skips the host
  cooldown, which fixes audit a1.
* **Docker image drift resolved.** The 512 native modules (7,616 output files) were rebuilt in the current
  `qed64-toolchain:emsdk-6.0.5` = `8228ea564e7b` (the kernel fork's `docker-wasm64/Dockerfile` at `974ee228b0`) in a
  fresh copy of the Mathlib tree. Every file is byte-identical to the originals built in `8b6698bbf474`
  (`drift-compare.log`). The image is recorded as equivalent: verify #7 prints OK and `native` accepts it.
* **Also committed:** the native click-all goldens (`lean/expect/click-all/`, which the UX suite reads; until now they
  lived only in the gitignored `out/`), the native delta lists (`lean/native/`), docs/ARCHITECTURE.md (with the
  integration-points table), docs/BUILD-FROM-SOURCE.md, docs/QED64-EMBEDDING-V1-REVIEW.md (paths made relative), and
  `.github/workflows/showcase-source.yml`.
* **Consequences.** The locks changed twice in this lane (v2, then the image equivalent), so `gallery/pin.json` and the
  gallery hash changed: `98ad69f6…` → `49d06172…` (lock v2) → `3b4dc8bb…` (image equivalent). Earlier verdicts
  no longer match. `out/deploy` was regenerated; the only differences are the lock sha256, the gallery hash,
  `gallery.js`/`lib.js` (comments) and `pin.json`, and the 93 R2 objects are identical.

## 2026-10-04: CI and the Cloudflare deploy pipeline (R3 lane) — no pin change, no lock change

The served pin stays E `33b0967`; no lock, release file or overlay changed. Logs: `$W/logs/r3/`; guide:
docs/DEPLOY-CLOUDFLARE.md (first deploy checklist, section 9 and "CI rehearsal").

* **Workflows** at the repository root: `lean-ci.yml` (one job per widget package, the static showcase from the
  regenerated dumps, the qed64-showcase static gates, GitHub Pages behind `vars.DEPLOY_GITHUB_PAGES`) replaces
  `pages.yml`, `portability.yml` and `showcase-source.yml`; `qed64-deploy.yml` deploys the app shell to the Worker
  `qed64-showcase` on pushes to `main` and on dispatch, and skips with a log line until `CLOUDFLARE_API_TOKEN` and
  `CLOUDFLARE_ACCOUNT_ID` exist. R2 uploads stay local (`upload-artifacts.sh`); the reasons are in section 9.
* **`deploy-manifest.mjs`**: `--from-lock` (the shell-only manifest of a checkout without the artifacts; equal to the
  full manifest apart from `options.source`), `--published <origin>` (are this shell's R2 objects live?) and
  `--record-verdict` (the committed G2 record `infra/ux-verdict.json`, which G2 accepts when `out/ux` has no record of
  these inputs). The record names run `r2-main-full2` on gallery `3b4dc8bb…`, lock `190f09de…`.
* **`deploy-app.sh`**: `DEPLOY_FROM_LOCK=1` (CI), `PUBLISHED_ORIGIN`, `WRANGLER_BIN`, and the deployed URL in
  `out/deploy/deployed-url.txt`. `upload-artifacts.sh` and `--commands` refuse a shell-only manifest. `rehearse.sh`
  takes its work dir from `QED64_SHOWCASE_WORK` instead of the `work` symlink.
* **Removed**: the inactive `deploy-showcase.yml.example` and `stage-shell-from-tarball.mjs` (the page is built from
  source now).
* **Local proof** (nothing pushed): `ci/run-local.mjs` runs a workflow's jobs in fresh clones; `ci/rehearse-deploy.sh`
  runs the deploy job against `wrangler deploy --dry-run`, `wrangler dev --local` and a fake R2 through
  `scripts/deploy-rehearsal/wrangler-shim.sh`. Results: DEPLOY-CLOUDFLARE.md "CI rehearsal". One node v26.3.0 exit
  deadlock (V8 Maglev worker vs. platform shutdown) hung `check-portable` after `PORTABLE OK`; every job now has a
  timeout.


## 2026-10-05/06: pin F (84d594e / wasm64-3ab1c6a9da03bc29, QED64 feature/embedding-api) registered from our own worktree and adopted locally (E -> F), the gallery moved to embedding API v1

Lane: the v1-adoption session (logs `$W/logs/pinF-*.log`; `$W` = `/Users/fawadhaider/code/qed64-showcase-work`; the
procedure in short: `$W/HANDOVER-2026-10-05.md` §2 and §6). **F is the active pin of this checkout only.** The live site
(`qed64-showcase.fawadworkaddress.workers.dev`) still serves E `33b0967` with the pre-v1 gallery; nothing was committed,
pushed or deployed.

**What F is.** `84d594e3dc8e75d0a327b6b8999423d8a205c525` is a commit of QED64's **`feature/embedding-api`** branch
(pushed by the user; `git branch -a --contains 84d594e` in the submodule names only `origin/feature/embedding-api`). It
is 52 commits after E `33b0967`, which is still QED64 **main**. Merging the branch into QED64 main is the user's
decision, not ours. F carries the embedding contract v1 (`deps/qed64/docs/EMBEDDING.md`, revision `1.0.0`): the frozen
`globalThis.qed64.api` with its `qed64:frame-api` event, `?embed=1`, the `#code=` boot document, the native InfoView
editor RPC (HARDENING #56, our D1/D2), the page's own `getWidgetSource` cache (our D3, EMBEDDING §2.5), validated boot
parameters (#57), edit coalescing (#59, §7.8) and `dist/qed64-build.json`. The runtime is E's.

| | E `33b0967` | F `84d594e` |
|---|---|---|
| Runtime / kernel / promote | `wasm64-3ab1c6a9da03bc29` / `a8817d01f9` / `3b42714` | the same |
| Runtime-dependent tracked files (git blobs at both commits) | `public/runtime/runtime-manifest.json` `6f72f11a…`, `public/snapshots/index.json` `3d9b20fc…`, `public/profiles` tree `ddbef779…` | identical blobs, so E's runtime stores (stage1, raw regions, bakes, overlays, headless) serve F unchanged; nothing was rebaked |
| Release set | 145 files | 146: the 59 `dist/` files of a source build (one more than E: `dist/qed64-build.json`, schema `qed64.build/v1`, `apiRevision` `1.0.0`, `shell` `shell-9bee85ba3f604dbe`) plus E's `public/` files |
| Main bundle; console notify site | `index-DpYTUbic.js`, line0 627 `d7af4642…` | `/assets/index-Da0NIljc.js`, line0 627 sha256 `53713dad…` (descriptor `consoleSites`) |

### What was done (in order; 2026-10-05, log times 21:00–21:08Z)

1. **Descriptor** `pins/84d594e/pin.json` (label `F:`; E's `servedTrees` `bump-0035b`; `liveness.builtIn` true, now the
   API's projection `status().liveness` and the `liveness` event; `knownLimitations` empty). `mainBundle` and
   `consoleSites` were filled after the build (step 4).
2. **Our own worktree** `$W/qed64-pins/84d594e` (`scripts/qed64-src.mjs ensure 84d594e`, a detached worktree of the
   submodule's repository). Every QED64 checkout of the QED64 sessions stayed read-only.
3. **The page from source in that worktree**: `npm ci --prefix frontend` and `npm run build:site`
   (`pinF-npm-ci.log`, `pinF-build-site.log`, built in 9.4 s).
4. **Public binaries cloned from E's release**, not fetched or rebuilt, because the runtime-dependent blobs are
   identical (table above): `release/33b0967/public` into the worktree's gitignored paths. Then
   `QED64_REPO=$W/qed64-pins/84d594e node scripts/pin-qed64.mjs pin --pin 84d594e` (`QED64_REPO` pointed at the
   worktree for this command only; `pinF-pin.log`): `S0.2 OK QED64 HEAD=84d594e3dc8e… clean, serves
   wasm64-3ab1c6a9da03bc29`, `S0.4 OK cloned 146 files (1.676 GB logical) -> release/84d594e`, `S0.4 OK QED64 HEAD,
   status and dist/ unchanged during the clone`, `PIN DONE`. Main bundle `/assets/index-Da0NIljc.js`; the notify
   line (`notify({severity:`) is line0 627 with sha256 `53713dad…`.
5. **`record-widgets-hash`** → `RECORDED WIDGETS_SOURCE_HASH c2efe78f… (222 files) + WIDGETS_COMMIT 90e415cc…`
   (`pinF-record-widgets-hash.log`). **`record-overlays`** → `widgets7 (3 files), widgets8 (3 files)`
   (`pinF-record-overlays.log`; E's overlays, same runtime).
6. **`pin-qed64.mjs verify --pin 84d594e`** → `VERIFY OK (1 DRIFT in a rebuild-only input)` (`pinF-verify.log`): the
   Docker tag drift `8b6698bbf474` vs `8228ea564e7b`. It is the known drift, but it reappeared because F's lock was
   generated without the `toolchain.docker.equivalent` record that the R2 lane added to E's lock on 2026-10-04 (E's
   lock carries it, F's does not); copying that record into `pins/84d594e/QED64.lock.json` would silence it. Served
   artifacts are unaffected; `showcase.sh native` refuses the image on F until then. *(Resolved 2026-10-06: `pin-qed64.mjs pin` now carries the record forward, and F's lock has it again; pin G entry.)*
7. **`pin-switch.mjs check 84d594e --full`** → `PIN CHECK OK 84d594e (full)` (`pinF-pin-check-full.log`: 146 release
   files == lock, main bundle and notify line == descriptor, sources HEAD == pin with no tracked file modified, stage1,
   raw regions and bakes, overlays `widgets7`/`widgets8` == lock).
8. **`node scripts/build-shell.mjs --pin 84d594e --no-install`** → `SHELL-FROM-SOURCE OK: all 59 dist files built from
   84d594e3dc8e == pins/84d594e/QED64.lock.json (sha256)` (`pinF-build-shell-det.log`: 59 byte-identical, 0 differ).
9. **`scripts/showcase.sh pin use 84d594e`** (`pinF-pin-use.log`): `PIN SWITCHED 33b0967 -> 84d594e`; the lock link,
   the submodule checked out at 84d594e (gitlink staged), `gallery/pin.json` regenerated, `out/deploy` regenerated
   (`DEPLOY-MANIFEST OK 76 assets, 93 R2 objects`), `PIN CURRENT OK 84d594e`. `showcase.sh verify` after it:
   `VERIFY: all checks OK` with the same Docker DRIFT note, `BUILD-GALLERY CHECK OK 8 examples`
   (`pinF-verify-after-use.log`).

### The code change: the gallery and the UX suite on embedding API v1

`gallery/pin.json` now carries `apiRevision` and `shell`, read by `scripts/build-gallery.mjs` from
`release/<pin>/dist/qed64-build.json` (`null` when a pin's release has none, i.e. pins A–E). The gallery is in **V1 mode**
when `apiRevision != null` and in **legacy mode** otherwise; legacy is the flow of pins A–E unchanged. In V1 it drives the
page only through `qed64.api` and its events, the RPC bridge and the liveness probe stand down on capabilities, `?mem=`
travels as `&memory=`, and persistence is the `document` event into `qed64-showcase:document`. The details are in
gallery/README.md "Embedding API v1 (pins F, G and H)" and docs/ARCHITECTURE.md "Integration points"; the contract between the
gallery and the tests was written once in the workflow script (`CONTRACT`, items 1–11). Changed: `gallery/{gallery.js,
lib.js,qed64-bridge.js,pin.json}`, `scripts/{build-gallery,check-gallery,sim-gallery}.mjs`, `tests/ux/{lib,specs,
bringup}/*`, `tests/ux/selectors.json` (test API version 9), new `tests/ux/tools/v1-smoke.mjs` (a one-browser smoke of
the v1 path that writes `out/ux/v1-smoke/report.json` with `complete`).

**Audit** (four adversarial lenses per round: contract, races, legacy fallback, test validity; read-only, each finding
CONFIRMED only with a traced failing scenario):

* **Round 1: 17 findings, all fixed** (2 major, 15 minor; e.g. the W1–W8 v1 stall check was a tautology, C23 v1
  dropped the death's identity, the adopted reload ignored the throttled pending `document` text, v1 switches were
  undoable with Ctrl+Z, the probe stand-down was not gated on `capabilities.liveness`).
* **Round 2: 19 findings (1 blocker, 4 major, 14 minor): 18 fixed, 1 accepted.** Among them: C25 waited for a new
  session id although every new page starts again at `s1` (blocker; now a per-document marker); C16 v1 required the
  exact-imports offer to be gone although the fallback session still collides (the page offers again); the gallery's
  mode came from the active pin's `pin.json` even when `SHOWCASE_PIN` served another pin's release (now
  `status().modeSource`, `'served'` after a `/qed64-build.json` probe made only when `X-Showcase-Pin` differs); the
  adopted reload now prefers the newest forwarded text kept in memory over the shared storage key; `api()` is bound to
  the document that published it; the late bridge is not installed (`repair: 'unavailable'`) for a page with
  `editorRpc` but no `widgetSourceCache`; a v1 page must report `documents`, `events`, `embedMode` and `restart`; the
  smoke tool reports `complete` and exits 3 when interrupted. Accepted: test API version 9 with additive fields on
  legacy pins too (documented in gallery/README.md "Test API").
* **Round 3: 11 findings; the 7 CONFIRMED fixed** (V1 boot overwrote a user's persisted document without keeping it,
  now kept through `planSave` as in legacy; the hard/soft boot-failure rule on F; parallel `pin.json`/`examples.json`
  fetches; the served-mode console warning under `UX_PIN`; three tests that could not fail: C1's embed-menu check, C10
  on v1, C22's `lastAnswerAgoMs`). The 4 PLAUSIBLE minor ones were not acted on (the workflow fixes CONFIRMED or
  non-minor findings).
* **Round 4: 9 minor findings (6 CONFIRMED, 3 PLAUSIBLE), not fixed in this workflow** (the fix budget was used up):
  the contract lens found nothing; open are a storage-quota case in which V1 boot still overwrites the document key
  after `seedBuffer` failed to keep the displaced text, `liveness.probe` reading `'active'` under `?liveness=off` on a
  legacy pin, the staged-lane `/qed64-build.json` 404 being allowed only by the UX suite (PLAUSIBLE), C3 v1 allowing
  `relayRestartOrReboot` for the whole test, the suite's `API` under `UX_PIN` not checking the `qed64-build.json` schema
  (PLAUSIBLE), and four `v1-smoke.mjs` gaps (the console scenario allowed for the whole run, `overLimit`/`unpaired`/
  `emptyErrors` missing from the report, two persistence checks that pass without a `document` event, an unbounded
  `close()` in the signal handler, PLAUSIBLE).

Static gates on the final tree (re-run 2026-10-06 by the docs stage): `BUILD-GALLERY CHECK OK 8 examples`,
`SIM-GALLERY OK 204 ok, 0 failed` (runs 1–15 legacy, 16–20 V1), `CHECK-GALLERY OK 130 ok, 0 failed`, `npx playwright
test --config tests/ux/playwright.config.mjs --list` → `Total: 35 tests in 8 files`. One browser smoke of the v1 path ran
before the round-1 fixes (`out/ux/v1-smoke/report.json`, 17/18); round 2 showed that run had been cut off before its
reload steps, so it is not evidence for F.

### Browser gates on F

*Filled 2026-10-08 from the logs.* F was replaced as the candidate by G (2026-10-06) before its UX gate, so F has no UX
run of its own.

| Gate | Result | Evidence |
|---|---|---|
| `headless controls` (2026-10-06, through the lock) | `CONTROLS PASS` 11/11 | `$W/logs/pinF-controls.log` |
| v1 smoke on `:5235` (2026-10-06) | `v1-smoke: 22/22 pass`; ready 16.4 s, reload step at 28.0 s | `$W/logs/v1smoke-run1.log`; report moved to `out/ux/v1-smoke.F-20261006` |
| full `ux`, `C20` ×3, headed sign-off, throttled first visit | not run on F | G, then H, took its place (entries below) |

Both measurements ran before audit rounds 2–6 changed the gallery, so they describe F's page and an earlier gallery, not
the gallery that was later committed. F stays registered and staged (`pin use 84d594e`: a V1 pin without the edit
back-pressure).

### Not done (in order)

*(2026-10-08: overtaken. Controls and the smoke ran on F, above; the rest ran on H instead: pin H entry.)* The v1 smoke, `headless controls` on F, two full `ux` VERDICTs, three `ux --grep "C20 "` runs, a headed sign-off, the
throttled first visit, `deploy-manifest --check` and `ci/rehearse-deploy.sh`, then a commit (pins/84d594e, the lock link,
the gitlink, gallery, scripts, tests, docs). Pushing and deploying are the user's decisions (docs/NEXT-STEPS.md). Back to
E: `scripts/showcase.sh stop && scripts/showcase.sh pin use 33b0967`, which sets `gallery/pin.json` `apiRevision` back
to `null`, so the gallery runs its legacy flow there.

## 2026-10-06: pin G (5c327c2 / wasm64-3ab1c6a9da03bc29, QED64 feature/embedding-api) registered like F and adopted locally (F -> G); audit rounds 5–6

Lane: the pin-G lane (logs `$W/logs/pinG-*.log`; `$W` = `/Users/fawadhaider/code/qed64-showcase-work`). **G is the
active pin of this checkout only; F is staged.** The live site (`qed64-showcase.fawadworkaddress.workers.dev`) still
serves E `33b0967` with the pre-v1 gallery. Nothing was committed, pushed or deployed.

**What G is.** `5c327c216aa31bf3880041b3e3a3b26fcb6d5a45` is the head of QED64's **`feature/embedding-api`** (pushed by
the user; QED64 main is still E `33b0967`, and merging is the user's decision). It is F `84d594e` plus two commits:
**`e4cffcc`**, which adds edit back-pressure on the worker pool (QED64 HARDENING #59 addendum, EMBEDDING.md §4 and §7.8),
and `5c327c2`, which orders the deploy.yml steps. With `e4cffcc`, the edit coalescer holds full-text changes while fewer
than `minFreeWorkers` (default 6, `?edithold=<n>`, 0 to 24, 0 = off) preallocated Workers are free. A hold lasts for a
1 s pressure memory and is capped at 5 s, with telemetry polled every 250 ms while it holds. At most 6 requests are at the
worker unanswered. A `$/cancelRequest` for a request still queued is answered locally with RequestCancelled (`-32800`,
message `QED64: the client cancelled this request before it reached the checker`, `error.data.qed64.kind`
`'cancelled'`). Each hold, release and cap logs one `console.debug` `[qed64] edit back-pressure: …`. The runtime is F's
and E's, and the embedding API revision stays `1.0.0`.

| | F `84d594e` | G `5c327c2` |
|---|---|---|
| Runtime / kernel / promote | `wasm64-3ab1c6a9da03bc29` / `a8817d01f9` / `3b42714` | the same |
| Runtime-dependent tracked files | runtime manifest, snapshot index, `public/profiles` tree, `KERNEL-PIN` | the same git blobs, so E's and F's runtime stores serve G unchanged; nothing was rebaked |
| Release set | 146 files (59 `dist/` + E's `public/`) | 146; of the 59 `dist/` files 52 are identical to F's. Changed: the bundles, `index.html`, `qed64-build.json` (`shell-6d9ca6f8b71443d9`, `apiRevision` `1.0.0`) and `workers/lean.worker.js`. `public/` is identical |
| Main bundle; console notify site | `/assets/index-Da0NIljc.js`, line0 627 `53713dad…` | `/assets/index-DcBRSfza.js`, line0 627 sha256 `46b0155c…` (descriptor `consoleSites`) |

### What was done (in order; 2026-10-06, log times about 14:42–14:52Z)

The procedure was F's (pin F entry, steps 1–9), in our own worktree `$W/qed64-pins/5c327c2`:

1. **Descriptor** `pins/5c327c2/pin.json` (label `G:`, F's `servedTrees` and `liveness`, `knownLimitations` empty;
   `mainBundle` and `consoleSites` filled after the build).
2. **The page from source**: `npm ci --prefix frontend && npm run build:site` (`pinG-npm-ci.log`,
   `pinG-build-site.log`), giving 59 `dist/` files.
3. **Public binaries cloned from F's release** (`release/84d594e`; 82 files), not fetched or rebuilt, because the
   runtime-dependent blobs are identical. Then `QED64_REPO=<worktree> node scripts/pin-qed64.mjs pin --pin 5c327c2`
   (`pinG-pin.log`): `S0.2 OK QED64 HEAD=5c327c216aa3… clean, serves wasm64-3ab1c6a9da03bc29`, `S0.4 OK cloned 146 files
   (1.676 GB logical) -> release/5c327c2`, `PIN DONE`.
4. **`record-widgets-hash`** (`c2efe78f…`, 222 files, `WIDGETS_COMMIT 90e415cc…`) and **`record-overlays`**
   (`widgets7`, `widgets8`, 3 files each: F's overlays, same runtime).
5. **`verify --pin 5c327c2`** → `VERIFY OK` with **no Docker DRIFT** (`pinG-verify.log`). The orchestrator first fixed
   `scripts/pin-qed64.mjs`: `pin` now carries `toolchain.docker.equivalent` forward from the pin's previous lock or from
   any registered pin's lock. Registering F had dropped E's record, which is why `verify` printed the resolved DRIFT
   again on F (pin F entry, step 6). F's lock got the record back, and `verify --pin 84d594e` is OK with no DRIFT.
6. **`pin-switch.mjs check 5c327c2 --full`** → `PIN CHECK OK 5c327c2 (full)` (`pinG-pin-check-full.log`).
7. **`build-shell.mjs --pin 5c327c2 --no-install`** → `SHELL-FROM-SOURCE OK: all 59 dist files built from 5c327c216aa3
   == pins/5c327c2/QED64.lock.json (sha256)` (`pinG-build-shell-det.log`: 59 byte-identical).
8. **`scripts/showcase.sh pin use 5c327c2`** (`pinG-pin-use.log`) → `PIN SWITCHED 84d594e -> 5c327c2`, `DEPLOY-MANIFEST OK
   76 assets, 93 R2 objects`, `PIN CURRENT OK 5c327c2`. Then `showcase.sh verify` (`pinG-verify-after-use.log`) →
   `VERIFY OK`, `BUILD-GALLERY CHECK OK 8 examples`, `[showcase] VERIFY: all checks OK`. `gallery/pin.json` now names
   `5c327c2`, `apiRevision` `1.0.0`, `shell-6d9ca6f8b71443d9`, so the gallery runs in V1 mode on G as on F.

### The code change for G, and audit rounds 5–6

The gallery code is the same for F and G (both V1). G's only new page behaviour the suite sees is the local cancel
reply. Rounds 5 and 6 continued the four-lens audit (contract, races, legacy fallback, test validity) from round 4
(pin F entry). Its fixes concentrated on one storage-quota edge case in V1 persistence.

* **Round 4's 9 minor findings were fixed, followed by audit rounds 5 and 6** (workflow `wf_ef07189d-8ae`; round 5's
  itemised findings are not reproduced here). By the end of that workflow the V1 boot no longer overwrote
  `qed64-showcase:document` when it could not keep the displaced text. Instead it **holds** the key (`holdDocument`). A memory-only text that could not be kept becomes
  **unsaved**, the storage notice says where each text is (`storageNotice`, with "Copy it"), and a held tab retries at
  most every `HOLD_RETRY_MS` (5 s) and heals without a boot when storage is freed. `serve.mjs` sends `X-Showcase-Api`.
  Static gates at the end of that workflow: `SIM-GALLERY OK 221`. Round 6's findings went to a separate fix stage.
* **Round 6 fix stage: 7 items, all fixed, none rejected.**
  1. `seedBuffer` keeps the stored key text as its own candidate, deduplicated by text, whether or not the tab is held.
     If keeping it fails, the boot holds the key instead of dropping that text when memory differs (another tab's text
     under the shared key). Sim case b9.
  2. Hiding any other notice brings the storage notice back while a text is held or unsaved (`hideNotice`). The notice
     of an unsaved text hides its ×, and the × does nothing (`unsavedNotice`), so "Copy it" stays.
  3. A held retry skipped by the 5 s rate limit arms one timer (`S.doc.holdTimer`) that retries with the newest text, so
     an edit made inside the window is not lost when storage is freed and no further edit follows. A failed retry arms
     nothing (no polling). Sim b9, and b7's wait was adjusted.
  4. `v1-smoke.mjs` exits 3 at once when interrupted, and its final exit is `interrupted ? 3 : failed ? 1 : complete ?
     0 : 3`.
  5. `v1-smoke.mjs` adds a whole-run console classification (`report.console.wholeRun`). It requires no unpaired line
     and no unexplained empty error over the whole run, and is ANDed into the console verdict.
  6. `X-Showcase-Api` is always a value (a revision, `none` or `invalid`) on every `serve.mjs` response, and
     `/showcase/pin.json` is `Cache-Control: no-store` (a cached `pin.json` could otherwise come back 304 without the
     headers). The gallery accepts only a revision or `none` (`API_REVISION_RE`) and otherwise probes
     `/qed64-build.json`. The UX suite's `GALLERY_PIN` refuses `invalid`. Sim cases for `invalid` and a garbage value.
  7. **The console entry for G's cancel reply** (`tests/ux/selectors.json` `consoleError[2]`). The text
     `^QED64: the client cancelled this request before it reached the checker$`, at `@qed64-main-bundle` line0 627, is
     allowed only when paired with its own LSP `-32800` reply (3 s before, 0.5 s after) and fails closed without tap
     reports. It is a pre-allowance: no browser run has printed that line yet. The check behind it: G's line 627 has
     exactly one `console.error`, monaco-vscode-api's `StandaloneNotificationService.notify`. The reply reaches the LSP
     tap on the same path as F's `-32801` superseded reply (`lsp-tap.mjs` records `{kind: 'errorReply', code: -32800,
     qed64Kind: 'cancelled'}`). A `check-gallery.mjs` unit test and a gallery/README.md "Console messages" row were
     added.
* **Round-6 verification follow-up: 2 items fixed.**
  1. `seedBuffer` no longer keeps this tab's **own** stale key text. `S.doc.lastWritten` records the last successful
     write. When the key still holds it and the tab is not held, memory supersedes it, so a stale version does not
     take a saved or history slot. Sim case b10.
  2. `console.mjs` `classifyConsole` builds **one reply pool per `lspErrorCode`**, shared by every `pairWith` entry of
     that code and paired in wall order, so one `-32800` reply can no longer explain both an empty line and a cancel
     line. `tests/ux/lib/qed64.mjs` `classify()` leaves QED64's local cancel replies out of the pool that explains empty
     errors. New `check-gallery` 8c cases.
  Not covered: `classify()` has no unit test under `check-gallery`, so that change was checked by `node --check` only.

Changed in rounds 5–6: `gallery/{gallery.js,README.md}`, `scripts/{serve,sim-gallery,check-gallery}.mjs`,
`tests/ux/{lib/qed64.mjs,bringup/console.mjs,tools/v1-smoke.mjs,selectors.json}`, plus `scripts/pin-qed64.mjs` (the
orchestrator's Docker-record fix). Static gates on the final tree (reported by the fix stages and re-run by the docs stage on 2026-10-06 with the same results):
`BUILD-GALLERY CHECK OK 8 examples (pin qed64 5c327c216aa3, api 1.0.0)`, `CHECK-GALLERY OK 132 ok, 0 failed` with its
embedded `SIM-GALLERY OK 236 ok, 0 failed` (232 after round 6, plus b10's 4), and `npx playwright test --config
tests/ux/playwright.config.mjs --list` → `Total: 35 tests in 8 files`. A serve smoke on port 5244 (round 6, pin
`5c327c2`) showed `/showcase/pin.json` with `X-Showcase-Pin: 5c327c2 wasm64-3ab1c6a9da03bc29`, `X-Showcase-Api: 1.0.0`
and `Cache-Control: no-store`. `/showcase/gallery.js` kept `public, max-age=0, must-revalidate`, and a 404 also carried
`X-Showcase-Api`.

**Measured on F, not on G** (handover §12): `headless controls` → `CONTROLS PASS` 11/11 (`$W/logs/pinF-controls.log`),
and one v1 smoke → 22/22 (`$W/logs/v1smoke-run1.log`). Both ran before the round-2 to round-6 fixes changed the gallery,
so neither is evidence for G's gallery.

### Browser gates on G

*Filled 2026-10-08 from the logs and `out/ux/showcase-ux-runs.jsonl`.* The steps ran as detached chains through the
lock (`$W/pinG/chain{,3}.sh`, progress in `$W/logs/pinG-chain{,3}.log`; times are UTC from those logs and the run
records, lock queueing included).

| Step | When | Result | Evidence |
|---|---|---|---|
| `g-full1` | 2026-10-06 15:39–15:40Z | rc 130: aborted while it waited for the lock; recorded `NOT A VERDICT`, all 35 skipped. The name is used up | run record |
| `headless controls` | 15:40–16:27Z | `CONTROLS PASS` 11/11 | `$W/logs/pinG-controls.log` |
| CI mirror on commit `1c22222` | ~16:03Z (log time) | `node ci/run-local.mjs --job qed64-static --job showcase`: the qed64-static job SUCCESS (12/12 steps, the shell from source == G's lock); 6 of 7 packages jobs SUCCESS, then stopped by hand during packages (dist-lens) to leave memory to the browser chain; the showcase job not run | `$W/logs/pinG-ci-local-1.log` (handover §15) |
| v1 smoke on `:5235` | 16:27–17:05Z | `v1-smoke: 22/22 pass; complete`; ready 14.7 s, reload step at 25.4 s | `$W/logs/v1smoke-G.log`; `out/ux/v1-smoke.G-20261006` |
| `g-full1b` | 17:04–17:40Z | 27 passed, 1 skipped (C19), **7 failed** (C1, C8, C10, C12, C22, C25 and the C14 aggregate): `NOT A VERDICT`. Each failure was root-caused (table in the pin H entry, "The g-full1b diagnosis"); C22 was a QED64 defect, the rest were test expectations or allowlist gaps | `$W/logs/pinG-ux-full1b.log`, `out/ux/g-full1b` |
| `g-fix1` | 18:26–18:31Z | `--grep "C1 \|C8 \|C10 \|C12 \|C22 \|C25 "`: 5 of 6 passed (C22 with the interim `rpcKeepAliveStarved` scenario). C10 failed only its new per-reload 1 s commit bound (commits of 97, 1131, 15, 4122 and 23 ms while QED64 started a runtime); the claim was restored (pin H entry) | `$W/logs/pinG-ux-fix1.log` |
| `g-fix2` | 18:32–18:38Z | `--grep "C10 "`: 1/1 | `$W/logs/pinG-ux-fix2.log` |
| `g-full1c` | 18:38–19:59Z | **VERDICT**: 34 passed, C19 skipped (gallery `931c33a7…`, lock `81c71b63…`) | `$W/logs/pinG-ux-full1c.log` |
| `g-full2c` | from 19:59Z | stopped on purpose while it waited for the lock (chain 3 stopped for the switch to H); the log ends at `waiting`, and no run record was written | `$W/logs/pinG-ux-full2c.log` |

`C20` ×3, the headed sign-off and the throttled first visit were not run on G: QED64 fixed the keep-alive starvation
that `g-full1b` found (bf9d947), and H took G's place as the candidate (pin H entry). G's one VERDICT (`g-full1c`) is on
gallery `931c33a7…`, which the switch to H replaced. G stays registered and staged; it was committed in `1c22222` on the
local branch `qed64-embedding-v1`.

### Not done (in order)

*(2026-10-08: overtaken. The controls, the smoke and a VERDICT ran on G, above; the remaining gates ran on H, and the
commit is `1c22222`: pin H entry.)* The v1 smoke on G (read `complete` and `console.wholeRun`), `headless controls` on G (an attempt was queued behind the
host browser lock with no result yet: `$W/logs/pinG-controls.log`), two full `ux` VERDICTs, three `ux --grep "C20 "`
runs, a headed sign-off, the throttled first visit, `deploy-manifest --check` and `ci/rehearse-deploy.sh`. Optionally, our
own measurement of HARDENING #59 on G (typing at 150 ms/char above a slow `#eval`; QED64 reports it fixed by `e4cffcc`;
docs/UPSTREAM-REPORT-QED64.md #59). Then a commit (pins/84d594e, pins/5c327c2, the lock link, the gitlink, gallery,
scripts, tests, docs). Pushing and deploying are the user's decisions (docs/NEXT-STEPS.md "Pin H"). Back to F:
`scripts/showcase.sh stop && scripts/showcase.sh pin use 84d594e` (V1 as well). Back to E: `pin use 33b0967`, which sets
`gallery/pin.json` `apiRevision` back to `null`, so the gallery runs its legacy flow there.

## 2026-10-06/07: pin H (bf9d947 / wasm64-3ab1c6a9da03bc29, QED64 main) — the keep-alive fix; H gated and active

Lane: the v1-adoption session (logs `$W/logs/pinH-*.log`, chain logs `$W/logs/pinH-chain{4,5,6,7,8,9}.log`, scripts
`$W/pinG/chain*.sh`; `$W` = `/Users/fawadhaider/code/qed64-showcase-work`; the timeline in `$W/HANDOVER-2026-10-05.md`
§18–§28). **H is the active pin of this checkout since 2026-10-06 ~20:03Z** (`pinH-pin-use.log`); G and F are staged.
The live site (`qed64-showcase.fawadworkaddress.workers.dev`) still serves E `33b0967` with the pre-v1 gallery. The work
is committed on the local branch `qed64-embedding-v1` (`1c22222` F and G, `d791b20` H active plus the suite fixes,
`bd42150` H gated and the verdict record), which is not pushed. Pushing and deploying are the user's decisions.

**What H is.** `bf9d94788100235fe9c64f653a11d98a915d2a16` is G `5c327c2` plus one QED64 commit, "Edit coalescing:
$/lean/rpc/keepAlive never waits for a request slot (the InfoView lost its RPC session after 30 s of a busy checker)"
(`frontend/src/embed/edit-coalescer.ts`, with tests and docs). QED64 fast-forwarded its **main** onto it over `5c327c2`
and deployed it, so H is the first v1 pin on QED64 main. The runtime, its stores and the API revision (`1.0.0`) are G's.

| | G `5c327c2` | H `bf9d947` |
|---|---|---|
| Runtime / kernel / promote | `wasm64-3ab1c6a9da03bc29` / `a8817d01f9` / `3b42714` | the same; the same runtime manifest, snapshot index, profiles tree and `KERNEL-PIN`, so nothing was rebaked |
| Release set | 146 files | 146 (`S0.4 OK cloned 146 files (1.676 GB logical) -> release/bf9d947`, `pinH-pin.log`) |
| Shell (`dist/qed64-build.json`) | `shell-6d9ca6f8b71443d9` | `shell-7d85e161da8a56e4`, equal to the shell of the live QED64 site when it was checked (handover §22) |
| Main bundle; console notify site | `/assets/index-DcBRSfza.js`, line0 627 `46b0155c…` | `/assets/index-CQnzGd9k.js`, line0 627 sha256 `fc6ad361…` (descriptor `consoleSites`) |
| Gallery content; lock | `931c33a7…`; `81c71b63…` | `d8a5bb6d…` (after `pin use` regenerated `gallery/pin.json`); `22eb45f5…` |

### The keep-alive starvation: found by C22 on G, fixed by QED64 in bf9d947

* **Found.** In `g-full1b` (pin G, 2026-10-06 17:28Z) C22 failed its console verdict on 9 `console.error('Outdated RPC
  session')` lines at the notify site, in two bursts: 5 at t 55.06 s, right after the 38 s silent `#eval`, and 4 at
  t 166.8 s, right after the 55 s saturated-pool phase (`out/ux/g-full1b/tests/C22.s10.console.jsonl`). Every functional
  assertion held: the session never changed (`sessionSame` true), no restart, no card.
* **Root cause** (diagnosis `g-full1b-diag-C22.txt`, read from the pinned sources). G's `e4cffcc` caps the requests at
  the worker at 6 (`edit-coalescer.ts` `maxInFlightRequests`). During a silent elaboration longer than 30 s, the
  InfoView's position-bound requests fill the 6 slots and wait on the snapshot. Every frame behind them waits in order,
  and only `$/cancelRequest` was exempt, so the InfoView's `$/lean/rpc/keepAlive` (sent every 10 s) queued too. Lean 4.34
  drops an RPC session after 30 s without a keep-alive (`RpcSession.keepAliveTimeMs := 30000`). When the elaboration
  finishes, the queued `$/lean/rpc/call`s reach a worker without that session, Lean answers each with `-32900`
  "Outdated RPC session", lean4monaco logs it, and the InfoView reconnects.
* **Reported** to the QED64 session with the evidence and a fix proposal: forward `keepAlive` (and `release`) without
  waiting for a slot. **Interim** (commit `d791b20`): C22 allows those lines only in the scenario `rpcKeepAliveStarved`,
  pushed only for pin `5c327c2`, each line paired with its own Lean `-32900` reply (`qed64Kind` null), each reply ending a
  phase silent for 30 s or more, then a reconnect and the golden panel (gallery/README.md "Console messages"). On every
  other pin C22 is strict.
* **Fixed** by QED64 in `bf9d947`. QED64's own A/B: 7 "Outdated RPC session" with the bug, 0 with the fix (QED64's
  measurement). Ours: strict C22 on a staged test copy of H, run **`h-c22-1`** (2026-10-06 19:31Z, our `serve.mjs` on
  `:5236` serving `bf9d947`): **0 lines against 9 on G**, `$/lean/rpc/connect` count 1 before and still 1 after each silent phase (no reconnect),
  `CONSOLE OK` with no scenario, and the 3 local `-32800` cancel lines of G's back-pressure paired
  (`out/ux/h-c22-1/tests/C22.json`: `keepAlive` for the connects, `console` for the cancels, `consoleError[2]` n 3,
  paired). It is a subset run on another origin, so by the rule it is `NOT A
  VERDICT`; the full gate below repeats C22 strictly in every full run.

### Registration

1. **Staged first, from the owner's commit.** While `bf9d947` existed only in QED64's local `feature/embedding-api`, it was
   fetched read-only into the submodule's repository (`refs/remotes/local-qed64-embed/feature-embedding-api`) and
   registered as a staged test pin `pins/bf9d947` (descriptor `registeredAt` 2026-10-06 18:45Z), not committed and not
   switched to. It was served on its own port for `h-c22-1` only.
2. **Confirmed pushed.** QED64 then put `bf9d947` itself on origin **main**. The QED64 site's live
   `qed64-build.json` named `shell-7d85e161da8a56e4`, the shell of ours. The descriptor's label and status were updated
   (`pins/bf9d947/pin.json`: "registered 2026-10-06 (first as a staged test pin from the owner worktree, then confirmed
   …)"). The confirmation changed only the descriptor's label and status; the build was the staged one of step 3.
3. **The pin (done during the staging, 2026-10-06 18:33Z, before step 2).** The procedure was G's, in our worktree `$W/qed64-pins/bf9d947` (`pinH-npm-ci.log`, `pinH-build-site.log`):
   `pin-qed64.mjs pin --pin bf9d947` → `S0.2 OK QED64 HEAD=bf9d94788100… clean, serves wasm64-3ab1c6a9da03bc29`,
   `PIN DONE` (`pinH-pin.log`).
4. **Shell from source 59/59.** Recorded in commit `d791b20` ("shell from source 59/59 == lock == the live QED64 build");
   that build's log is not in `$W/logs`. The deploy rehearsal on `bd42150` built it again:
   `SHELL-FROM-SOURCE OK: all 59 dist files built from bf9d94788100 == pins/bf9d947/QED64.lock.json (sha256)`
   (`$W/pinG/rehearse-deploy-H1/dry-run.log`).
5. **`pin use bf9d947`** (`pinH-pin-use.log`): `PIN SWITCHED 5c327c2 -> bf9d947`, `BUILD-GALLERY OK 8 examples` (`api 1.0.0
   shell shell-7d85e161da8a56e4`), `DEPLOY-MANIFEST OK 76 assets, 93 R2 objects; gallery d8a5bb6d…`, `PIN CURRENT OK
   bf9d947`. The 93 R2 objects are the live ones (same runtime and overlays), so a deploy of H changes only the Worker and
   its assets (handover §25).
6. **Pin check and verify** (`pinH-verify.log`): `PIN CURRENT OK bf9d947`, `PIN CHECK OK` (cheap) for every other
   registered pin, and `VERIFY OK (1 DRIFT in a rebuild-only input)`. The pin check of H itself is recorded as OK in
   commit `d791b20`. The DRIFT is new and not H's: `DRIFT #7 docker qed64-toolchain:emsdk-6.0.5 … sha256:5708c2dbf5a1`.
   The kernel session rebuilt that tag on 2026-10-06 for its patches 0036/0037 (QED64's report), so neither the
   recorded image nor its recorded equivalent is what the tag names now. Served artifacts are unaffected (they are
   verified by hash); only `showcase.sh native` refuses the image. Nothing was changed for it (docs/NEXT-STEPS.md).

### The g-full1b diagnosis (pin G, 7 failures)

One read-only investigator per failure compared `out/ux/g-full1b` with the legacy baseline `out/ux/r4-main-full4`; one
fix agent and an adversarial verifier followed (workflow `wf_7cb773b4-b31`; diagnoses in the session scratchpad
`g-full1b-diag-*.txt`). The fixes are in commit `d791b20`.

| Test | What failed | Category | Fix | Re-run |
|---|---|---|---|---|
| C1 | `toEqual` on `status().seed`: the three fields round 5 added (`blocked`, `keepFailed`, `unsaved`), with their correct clean-boot values | test expectation | the expected object has the round-5 shape (`00-boot.spec.mjs`) | `g-fix1` pass |
| C8 | (1) the v1 page's named boot failure `Error: ?snapshots=snapshots/nope: /snapshots/nope/index.json: HTTP 404` (one `console.error` from `main()`'s catch) had no allowlist entry; (2) the assertion expected `#bootlabel` to equal `boot.message`, but the page prefixes `FAILED: ` | allowlist gap, plus a test expectation | new entry `bootFailure[4]`, only in the `bootFailure` scenario; the assertion accepts the prefix | `g-fix1` pass |
| C10 | the storm missed "5 reloads in 15 s" because of the test's own probes: a `page.evaluate` before each reload cannot finish while QED64 starts a runtime, and the synchronous `ps` sampler stalled Node for 2–3 s; the reloads themselves committed in 14–155 ms | test harness | reloads through CDP `Page.reload` timed by `frameNavigated`, an asynchronous `ps` sampler. `g-fix1` then failed only the new per-reload 1 s commit bound; the claim was restored: the last reload commits within 15 s, no storm reload hits a page the poller saw ready, commit latency and phases recorded (`m.commitLatency`) | `g-fix2` pass |
| C12 | the same named boot failure on `overlay-offline-stock` (`Error: ?snapshots=snapshots/widgets8: Failed to fetch`); every functional assertion passed | allowlist gap | `bootFailure[4]` | `g-fix1` pass |
| C22 | 9 "Outdated RPC session" (above) | **QED64 defect** in `5c327c2` (`e4cffcc`) | reported; the scenario `rpcKeepAliveStarved` for `5c327c2` only; fixed by QED64 in `bf9d947` | `g-fix1` pass with the scenario; `h-c22-1` strict on H |
| C25 | after the adopted reload of an EDITED buffer the panel was expected at the example's first cursor, but nothing puts the cursor there (the gallery places it only when the text equals an example, by design) | test expectation | the test sets the cursor itself | `g-fix1` pass |
| C14 | the suite's aggregate console verdict over the failures above | follows from them | none of its own | – |

Also in `d791b20`: `console.mjs` builds one reply pool per error code. `check-gallery.mjs` gained unit tests for the new
entries (`CHECK-GALLERY OK 140/0`, `SIM 236/0`, 35 tests listed; handover §18).

### Browser gates on H

Through the lock, as detached chains 4–8 (`$W/logs/pinH-chain{4,5,6,7,8}.log`). Times are UTC from the run records
(`out/ux/showcase-ux-runs.jsonl`, lock queueing included). Every full run is on gallery `d8a5bb6d…`, lock `22eb45f5…`,
overlays `widgets7`/`widgets8` unchanged from G. Memory floor from chain 5 on: `MIN_BROWSER_GB=16 MIN_FREE_GB=16`.

| Run | When | Result | Evidence |
|---|---|---|---|
| v1 smoke on `:5235` | 2026-10-06 20:06–20:07Z | `v1-smoke: 22/22 pass; complete`; ready 15.7 s, reload step at 26.9 s; console `allowlist verdict ok` | `$W/logs/pinH-smoke.log`, `out/ux/v1-smoke/report.json` |
| `h-full1` | 20:07–20:36Z | 32 passed, 1 skipped, **2 failed**: C9 (a renderer crash of the stock page, below) and the C14 aggregate. `NOT A VERDICT` | `$W/logs/pinH-ux-full1.log` |
| `h-full1b` | 20:37–21:53Z | **VERDICT**: 34 passed, C19 skipped | `$W/logs/pinH-ux-full1b.log` |
| `h-full2b` | 21:53–22:24Z | 32 passed, 1 skipped, **2 failed**: C10 (a renderer crash after the storm, below) and C14. `NOT A VERDICT` | `$W/logs/pinH-ux-full2b.log` |
| `h-full3` | 22:24–23:46Z | **VERDICT**: 34 passed, C19 skipped | `$W/logs/pinH-ux-full3.log` |
| `h-full4` | 23:46Z–2026-10-07 01:03Z | **VERDICT**: 34 passed, C19 skipped (`h-full3` and `h-full4` consecutive) | `$W/logs/pinH-ux-full4.log` |
| `h-c20-1`, `h-c20-2`, `h-c20-3` | 2026-10-07 01:03–03:06Z | `--grep "C20 "`: 1/1 each, **135/135 clean** in each (405/405) | `$W/logs/pinH-ux-c20-{1,2,3}.log` |
| `h-headed1` (headed Chrome for Testing) | 03:06–04:35Z | 33 passed, **2 failed**: C11 (a renderer crash in the recovery reload, below) and C14. `NOT A HEADED SIGN-OFF` | `$W/logs/pinH-ux-headed1.log` |
| `h-headed2` (headed) | 04:36–06:19Z | **HEADED SIGN-OFF**: 35/35, C19 included | `$W/logs/pinH-ux-headed2.log` |
| `h-throttle-t10` (`throttled-first-visit.mjs`, CDP throttling only) | 06:18–06:56Z | `RESULT PASS`, ready at 119.2 s, progress visible in 118 of 119 samples, longest unchanged progress 6.0 s, no error card, panel EQUAL. **Not a 10 Mbit/s visit:** CDP throttled the page only (`targets {"page":1,"worker (NOT throttled)":28}`); the downloads (the page and its 28 unthrottled workers) totalled 693.1 MB at 46.7 Mbit/s aggregate. It verifies the v1 boot UI (QED64's card with bytes, rate and time left while the gallery shows no notice), not the slow-link timing | `$W/logs/pinH-throttle-t10.log` |
| `heap-share-1` (`tests/ux/tools/heap-share.mjs`, `:5237`) | 06:55–07:00Z | 15/15 samples (below) | `$W/logs/heap-share-1.log`, `out/ux/heap-share-1/heap-share.json` |
| `deploy-manifest --check` | 2026-10-06 after `h-full1b` | OK; G2 names `h-full1b` (handover §25) | – |
| `deploy-manifest --record-verdict` | 2026-10-07 06:39Z | `infra/ux-verdict.json` names **`h-full4`** (gallery `d8a5bb6d…`, lock `22eb45f5…`, both overlays, pin `bf9d947`), the G2 record a checkout without `out/ux` (the CI deploy) accepts; committed in `bd42150` | `infra/ux-verdict.json` |

**10 Mbit/s first visit, link shaped outside the browser** (run `h-throttle-t10p`, 2026-10-08 18:03–18:13Z; `throttle-proxy.mjs --listen 5198 --upstream 5197 --mbps 10 --rtt 40` in front of `serve.mjs :5197`, `throttled-first-visit.mjs --no-cdp --mbps 10 --rtt 40`; `$W/logs/pinH-tp-t10.log`, `$W/logs/pinH-tp-proxy.log`, `out/ux/h-throttle-t10p/explore/throttle-t10p.json`): **`RESULT PASS`**, ready at **565.6 s** (pin E: 565.1 s), visible progress in 564 of 565 samples before ready, the error card in 0 samples, longest unchanged progress 6.0 s, the gallery's slow-download notice from 368.4 s, the panel equal to the golden at ready, no crash, console OK. The proxy measured 693.6 MB down at 9.8 Mbit/s over 565.9 s and 28 connections, so the page and all 29 worker targets were shaped this time.

**Deploy rehearsal** (`ci/rehearse-deploy.sh` on `bd42150`, 2026-10-08, fresh clones, local fakes only; `$W/logs/pinH-rehearse-deploy.log`, run dir `$W/pinG/rehearse-deploy-H1`): **`REHEARSE-DEPLOY OK`**, all seven scenarios: `skip` (no secrets: the skip line, every later step skipped), `dry-run` (up to `wrangler deploy --dry-run`), `unpublished` (the published check refused an origin without the artifacts; wrangler never called), `deploy` (G2 from the committed verdict `h-full4`, published check OK, `wrangler deploy --dry-run` + `wrangler dev`, SMOKE OK), `first` (published check skipped, smoke on the printed URL), `no-verdict` (G2 refused a gallery `infra/ux-verdict.json` does not name), `tamper` (`--published` caught a wrong index sha256 and a wrong object size).

**CI mirror on `bd42150`** (`node ci/run-local.mjs --workflow .github/workflows/lean-ci.yml --job qed64-static`, fresh clone, 2026-10-08; `$W/logs/pinH-ci-local.log`): **JOB SUCCESS**, 12/12 steps, among them the shell built from source byte-identical to H's lock (59 files), the Worker tests and the gallery gate (CHECK-GALLERY OK).

**The three crash runs: QED64 HARDENING #55's residual, not the gallery.** Each lost one test to a renderer crash while a
new QED64 runtime started in the same renderer:

* **`h-full1` C9** (the stock-page half; the gallery half refused the unpaired fixture with 0 QED64 loads, as designed).
  On the unpaired fixture the stock page reboots after each `bootFailed`. The renderer died at t 12.2 s after 9
  `[qed64] starting Lean`, before the breaker halted (`out/ux/h-full1/tests/C9.stock.console.jsonl`). The host had
  14.1 GiB reclaimable at the start of the run (lock cooldown, `pinH-ux-full1.log:8`; nothing measured it at the crash). G passed the same test in `g-full1b` and `g-full1c` (13 starts, halted, no crash). H differs
  from G only in the keep-alive forwarding.
* **`h-full2b` C10** (five reloads in 15 s on a warm profile). At first ready the renderer held 8.9 GiB with 26
  Workers. After the last reload, QED64 logged `[boot] waited 132 ms for 1 stopping runtime(s) (24 → 5 Workers alive)`
  and the renderer died 1.25 s later (`C10.s14.console.jsonl`, t 22.10 s and 23.35 s).
* **`h-headed1` C11** (a lasting network cut through `serve.mjs` CHAOS). QED64 halted after 3 deaths (first
  "checker halted" at t 23.1 s; `C11.json` `lasting.ms` 22816). The test's recovery reload, about 3.6 s later (load at
  t 26.7 s, after the spec's 2.5 s wait, screenshot and server restart), crashed the renderer at t 30.1 s
  (`C11.cut-lasting.console.jsonl`). The spec then failed on a null status (a `TypeError` at
  `30-robustness.spec.mjs:313`); since `bd42150`, C9 and C11 report a renderer crash as such, with the same pass/fail.

QED64's explanation (QED64's analysis, after our evidence): one booted runtime's ~25 glue isolates (~129 MiB each) fill
most of the renderer's 4 GiB pointer-compression cage, so a reload that starts a new runtime before the old isolates
are gone can exceed it. The embedder's own JS heap shifts the rate. QED64's "ballast" storm, an embedder holding extra
heap: 0 MiB 0/8 crashes, 800 MiB 8/8, 1600 MiB 8/8. QED64 reopened #55 as a residual; the margin has to come from the
kernel side (a pool-size knob, a smaller glue).

**Our share of that heap: `heap-share-1`** (5 interleaved rounds, a fresh profile per sample, `chart-kit` on `widgets8`,
measured at ready + 5 s; same-origin frames share one isolate, so the figure is the gallery, the QED64 page and the
InfoView together):

| | used JS heap, median (min–max) | renderer RSS, median |
|---|---|---|
| stock page at top level | 61.0 MiB (61.0–64.8) | 9194.7 MiB |
| a trivial same-origin embed host | 64.8 MiB (64.8–68.9) | 9316.3 MiB |
| the gallery | 64.8 MiB (64.8–64.8) | 9391.4 MiB |

`performance.measureUserAgentSpecificMemory` was not available, and `performance.memory` took only three distinct
values (61.0, 64.8 and 68.9 MiB), so the resolution is a few MiB. Within it, the gallery adds no JS heap over a trivial
embed (+0 MiB median; the embed +3.8 MiB over the stock page) and about 75 MiB of renderer RSS. At about 65 MiB the
gallery is not a heavy embedder next to QED64's 800 MiB threshold, and there is nothing material to cut on our side.
Since `bd42150`, C10 also records the page's JS heap before each storm reload (data only).

**Crash rate in our runs (G and H, counted from the per-test records):** C10 crashed in 1 of 9 headless-shell storms
(`g-full1b`, `g-fix1`, `g-fix2`, `g-full1c`, `h-full1`, `h-full1b`, `h-full2b`, `h-full3`, `h-full4`) and 0 of 2 headed;
C9's stock reboot loop in 1 of 9 runs; C11's recovery reload in 1 of 9. The gallery's own boots retire the old page
through `about:blank` instead of reloading it; its one reload path is the card's Restart Lean when QED64 refuses
`api.restart()` during a boot (gallery/README.md "QED64 limitations found", L9).

**QED64 work in progress that keeps our assertions** (QED64's): **#62**, an early pairing check, keeps C9's projection
exactly, with no new console text; **#63**, a network-kind boot failure downloads the snapshot before starting a new
runtime, keeps C11's assertions (C9 and C11 assert no death count). Both mean a re-pin and a re-gate when they land.
**#59** is fixed in G and H per QED64 (`e4cffcc`); we have not measured it.

Back to G: `scripts/showcase.sh stop && scripts/showcase.sh pin use 5c327c2` (its `rpcKeepAliveStarved` scenario
applies there). Back to F: `pin use 84d594e`. Back to E (legacy mode): `pin use 33b0967`.

### Not done (in order)

1. Done since: the proxy-shaped 10 Mbit/s first visit (`h-throttle-t10p`, PASS, above) and `ci/rehearse-deploy.sh` on
   `bd42150` (above).
2. Done since: `node ci/run-local.mjs --job qed64-static` on `bd42150` (JOB SUCCESS, above).
3. The user's decisions: push the branch `qed64-embedding-v1`, and deploy H (docs/NEXT-STEPS.md).
4. Our own measurement of #59 (optional).

## 2026-10-09: pin I (385a1ac / wasm64-f69cca24d0878a58, QED64 main) — the kernel release lean-v4.34.0-e1a79c1, per-runtime overlay directories, QED64's #62/#63/#64; I superseded by J (5e63edd, the 0036 interim), J gated

*Status 2026-10-10 ~03:55Z:* **I is superseded by J `5e63edd`** (QED64 main since 2026-10-09 ~20:30Z; "Pin J" under
"Gates" below). I stays registered as the record of the kernel-0036 regression ("The regression" below) and is not
deployed. J is the active pin, with two VERDICTs, a headed sign-off and the 10 Mbit/s first visit; QED64's C10 ×20
evidence run is running ("Not done / running" at the end of this entry). The paragraphs that follow are dated as
written.

Lane: the pin-I re-pin (plan `$W/pinI/plan.md`, investigations `$W/pinI/map-{register,heavy,overlays,asks}.md`, logs
`$W/logs/pinI-*.log`, gate chain `$W/pinI/chain1.sh` logging to `$W/logs/pinI-chain1.log`; `$W` =
`/Users/fawadhaider/code/qed64-showcase-work`). **I is the active pin of this checkout since 2026-10-09 ~13:10Z**
(`pinI-use.log`); H `bf9d947` is staged and is the last pin with a complete browser gate. The live site
(`qed64-showcase.fawadworkaddress.workers.dev`) serves pin H `bf9d947` (deployed 2026-10-08 19:20Z by the qed64-deploy run on the push of `d60b15e` to main, Worker version `29176b6f`; its 93 R2 objects were E's, nothing was uploaded) (corrected 2026-10-10: this entry first said E). The work is on the local branch `qed64-pin-i`,
not pushed. A push to `main` that touches `qed64-showcase/` **is** a deploy (`.github/workflows/qed64-deploy.yml`), so
the upload, the push and the deploy are each the user's decision ("Open decisions" below).

**What I is.** `385a1ac5f3bc33cd607c1cc2d03f4d8979ef4684` is QED64 main ("snapshot-probe: set the runtime's environment
at preRun, where getenv reads it (HARDENING #66)"). Its promote is `fc945e4` ("Adopt lean-v4.34.0-e1a79c1: runtime
wasm64-f69cca24d0878a58 (kernel patch 0037, HARDENING #61 fixed)"), the last commit since H that touches
`public/runtime|snapshots|profiles` or the release record (map-register §1). Between H and I QED64 also landed the fixes
for our three asks: **#62** an unpaired snapshot refused before the runtime boots (`9045b86`), **#63** a network failure before
boot is one named death (`cause.kind` network) instead of a runtime start per retry (`e10454b`, `3524618`), **#64** per-build index copies, read only when
the mutable index names another runtime (`5952e32`, `3bd5521`). Each is an ancestor of `385a1ac` and of no pin up to
`bf9d947` (`git merge-base --is-ancestor`; verify #12 below). Three QED64 changes forced code changes here:

* **`pipeline/toolchain/KERNEL-PIN` is gone** (deleted in `4f46477`, "KERNEL-PIN retired"). QED64 names the kernel it
  serves in its tracked release record `toolchain/lean4-wasm64-release.json`: id `lean-v4.34.0-e1a79c1`, digest
  `sha256:bd71636b…`, `kernel.commit` = `gate.commit` = `e1a79c1ce9…` with `gate.passed`, `runtime.buildId`
  `wasm64-f69cca24d0878a58`. `pin-qed64.mjs` (`kernelAt`) reads the record where it exists, checks the schema, the
  kernel commit, the buildId, the gate on that commit and `gate.wasmSha256` against the buildId, and falls back to
  `KERNEL-PIN` for pins A–H (S0.2 and verify #9).
* **The Memory64 probe moved** out of `lean.worker.js` into `public/workers/memory64-probe.js` (a classic script that
  sets `globalThis.Qed64Memory64`, loaded with `importScripts`). `check-gallery.mjs` evaluates it in a `vm` context where
  it exists (else the old `lean.worker.js` regex), and `deploy-app.sh` requires `workers/memory64-probe.js` in the deploy
  tree when the staged `lean.worker.js` names it. I's `dist/` has 60 files (H: 59).
* **A new runtime cannot share the bare overlay directories with the live shell.** The live shell (E, like H) reads only
  `/snapshots/<dir>/index.json` for an overlay and has no per-build fallback, so f69cca24 overlays uploaded to
  `/snapshots/widgets8/` would break every live gallery boot until the deploy (map-heavy, map-overlays F6; QED64 had the
  same outage on its stock indexes on 2026-10-08, HARDENING #64). Hence the per-runtime directories below.

| | H `bf9d947` | I `385a1ac` |
|---|---|---|
| Runtime / kernel / promote | `wasm64-3ab1c6a9da03bc29` / `a8817d01f9` / `3b42714` | `wasm64-f69cca24d0878a58` / `e1a79c1ce9` (release `lean-v4.34.0-e1a79c1`, patch 0037) / `fc945e4` |
| Kernel named by | `pipeline/toolchain/KERNEL-PIN` | `toolchain/lean4-wasm64-release.json` `kernel.commit` |
| Release set | 146 files | 147 (`S0.4 OK cloned 147 files (1.676 GB logical) -> release/385a1ac`, `pinI-pin.log`): `dist/` 60 files, H's 59 plus `workers/memory64-probe.js` |
| Stock snapshots | `init.b6d945e398b4d55e`, `mathlib.265cd10cbadd1313` | `init.fcbe485fbee5ea21`, `mathlib.6ca0fa64efdf4705` (raw 122,364,117 and 1,127,272,685 B, as before) |
| Packs | lean-core, mathlib-essential | the same blobs: the 69 part files were cloned from `release/bf9d947` (verify #4 OK on both packs) |
| Shell; main bundle; console notify site | `shell-7d85e161da8a56e4`; `/assets/index-CQnzGd9k.js`, line0 627 `fc6ad361…` | `shell-d96be803c9315cde`; `/assets/index-DDUZGVEB.js`, line0 627 sha256 `28b8d70e…` (descriptor `consoleSites`; `pin check` OK) |
| Widget overlays | `widgets.7772b36c004872af` (w7), `widgets.07e4514f22d85756` (w8), served at `/snapshots/widgets{7,8}/` | `widgets.9eb6987f65d3aba1` (w7), `widgets.ebd0fc1b6fe9f4e7` (w8), served at `/snapshots/widgets{7,8}.f69cca24d0878a58/` |
| Descriptor | `qed64-showcase.pin/v2` | `qed64-showcase.pin/v3`, `"overlayDirs": "per-runtime"`, `hardening` `{earlyUnpaired, networkPreboot, pinnedIndexes}` all `true` |
| Lock; gallery content | `22eb45f5…` (unchanged); `d8a5bb6d…` | `97742ccd…`; `3da79ea2…` (after `pin use`) |
| R2 objects (`deploy-manifest`) | 93 | 95: H's layout of 93 objects (with I's own files) plus the two per-build index copies (R6 below) |
| Native toolchain | native64 `857544b439`, Mathlib `5ed2965`, ProofWidgets `106ff4f` | unchanged (the release record names the same native64 and Mathlib commits); no native rebuild, no restage |

### The code change: per-runtime overlay directories, and QED64's asks in the suite

* **One naming rule** (`scripts/lib/pins.mjs`). `overlayDir(o, id)` is `o` for a `qed64-showcase.pin/v2` descriptor
  (pins A–H, frozen) and `<o>.<bid16>` for `qed64-showcase.pin/v3` with `"overlayDirs": "per-runtime"` (pin I:
  `widgets8.f69cca24d0878a58`); anything else throws, and `pinDescriptor` accepts only those two shapes. `overlayDirs(id)`
  and `overlayUrl(o, id)` (`/snapshots/<dir>/`) derive from it; the CLI `node scripts/lib/pins.mjs overlay-dir <name>
  [id]` maps a logical name and echoes any other name. The logical names `widgets7`/`widgets8` stay the names of the
  stores, the active links, the lock keys, the `ux-verdict` keys and the UI; only URLs carry the directory. Checked on
  2026-10-09: `overlay-dir widgets8 <id>` prints `widgets8` for all eight pins A–H and `widgets8.f69cca24d0878a58` for I;
  nothing under `pins/` of A–H changed (`git diff` empty; `pins/bf9d947/QED64.lock.json` still `22eb45f5…`).
* **The lock carries the URL as checked data.** `record-overlays` writes `overlays.<o>.url = overlayUrl(o, id)`; verify
  #11 checks the url and the store dir; `pin check`, `pin current` and `showcase.sh verify` (`check_overlays_cheap`)
  compare it with the rule; `fetch-artifacts.mjs` fetches from it and refuses a url that disagrees.
* **The alias lives in the gallery only.** `build-gallery.mjs` writes `gallery/pin.json` `overlays` (logical name →
  directory; the identity on pins A–H) and fails unless each lock url is `/snapshots/<dir>/`. The gallery maps
  `?overlay=widgets8` to the pin's directory (`lib.js` `overlayDirOf`, `overlayNameOf`, `parseOverlayDirs`); any other
  value is a literal directory, and a `pin.json` without the map means the bare names. Badges, chips and notices keep the
  logical name; the frame URL, the badge title and `status().overlayDir` carry the directory. **No Worker rewrite:** the
  Worker's routing is generic, so the bare objects of earlier pins stay where they are and stay verifiable
  (`fetch-artifacts --pin bf9d947`, `--published` of an older manifest).
* **`serve.mjs`** keys the pin's overlays by the served directory and never serves a bare logical name through its
  fixture route, so on a v3 pin `/snapshots/widgets{7,8}/index.json` is a 404 locally, as it is in production for a
  per-runtime pin's gallery (map-overlays F7: otherwise a gallery that still framed the bare path would pass locally and
  fail live). `check-gallery` §10 asserts the 404 live.
* **`deploy-manifest.mjs`.** Each overlay is uploaded under its directory (`options.overlayDirs`); G2,
  `--record-verdict` and `--published` find the overlay indexes through that map. New **R5**: each served directory ==
  `pins.mjs overlayDir` == the lock's url, and a per-runtime pin uploads nothing under the bare `/snapshots/<o>/`. New
  **R6** (a pin with `hardening.pinnedIndexes`, QED64 HARDENING #64): QED64's per-build index copies
  `/snapshots/index.<bid>.json` and `/snapshots/profiles-index.<bid>.json` are uploaded, mutable, byte-identical to
  `/snapshots/index.json` and `/profiles/index.json`, and name only this buildId. `serve.mjs` and `deploy-manifest.mjs`
  import QED64's `isImmutable` from `infra/edge-worker.js` where the pin has it (84d594e on), else `infra/worker.js`
  (pins A–E); our Worker keeps importing `deps/qed64/infra/worker.js`, which exports it at every pin. At 385a1ac the rule
  revalidates `/snapshots/widgets8.f69cca24d0878a58/index.json` and the per-build copies, and keeps the `.snapz` in such
  a directory immutable (Worker tests 26/26 in the integration run, `$W/pinI/scratch/integ3/worker-test.log`).
* **Upload phases** (`upload-artifacts.sh` `PHASES`, default all three). A per-runtime overlay index and the per-build
  copies go up in phase 2 (`2-manifests`): they replace nothing an older shell reads. Only the mutable shared indexes
  `/snapshots/index.json` and `/profiles/index.json` (and a bare overlay's `index.json`, pins A–H) stay in phase 3. A
  phase is uploaded only after every earlier one, selected in the same run or recorded by this remote's newest release
  records for the same keys; each record names its phases (`target.env phases=`). `deploy-app.sh` refuses a shell whose
  records did not upload all three phases unless `ALLOW_PARTIAL_UPLOAD=1`, and `rollback-artifacts.sh` joins the
  companion records of such a split upload. Whether the split can be used for the deploy is decision E1 below.
* **`ci/rehearse-deploy.sh`**: the tamper scenario alters the overlay index at the directory the manifest records; a new
  `old-shell` scenario (needs `OLD_REF`) loads the new pin's phases 1–2 over the live pin's fake R2 under the old Worker
  and shell, boots the old gallery and the bare stock page, then measures phase 3 before and after the new Worker (orders
  A and B; `E1 MEASURE` lines, evidence rather than failures).
* **Heavy path.** `preflight-overlays.sh` and `tests/experiments/x1-preflight.mjs` use QED64's
  `pipeline/release/preflight.mjs` where it exists (385a1ac on; `tests/adversarial/preflight.mjs` there is a one-cycle
  shim that prints a deprecation warning), else `tests/adversarial/preflight.mjs`; the arguments stay logical names and
  map through `overlay-dir`. `showcase.sh`'s stage1 hint names the release from the pin's record and the `cli.mjs fetch`
  command. `stage-trees.mjs --check-digest baseSlim|coreSrc` (G0, also run by `run-controls.sh` on `$W/tree-stock`)
  compares a served tree with `servedTrees.baseSlimDigest`/`coreDigest` and QED64's `embedding/base-tree.json`; pin I
  records neither field, so it prints SKIP (`pinI-hl-controls.log`). `make-overlay.mjs` prints the served directory.
* **The UX suite enforces QED64's asks only through the descriptor's `hardening` flags** (pins up to H carry none and keep
  their assertions): **C9** (#62, `earlyUnpaired`): halted within 30 s, 0 `[mem] runtime-initialized` lines, 0 `.snapz`
  GETs in the serve log and in the browser, 0 `lean.wasm` chunk requests, at most 3 checker deaths, no crash; **C11** (#63,
  `networkPreboot`): exactly one runtime start for the single and the lasting cut, `lastDeath {bootFailed, cause.kind
  network}`, relay `halted`; the **network oracle** (#64, `pinnedIndexes`): per session no per-build index copy requested
  and no unexpected 404 (`<test>.<label>.network.jsonl`), and C14 cross-checks the whole run's serve log from the
  `run-meta.json` offset; C1 writes `C1.cold.network.jsonl` and `C1.cold.server.log` (the boot network log for QED64).
  C10 and C11 record crash timing against the `[boot] waited` and runtime-start lines; `--repeat-each` gives each repeat
  its own record (slug suffix `.rNN`); a crashed page short-circuits `waitGallery`. The `networkCut` allowlist accepts
  QED64's #63 wording `the transfer of <file> ended early: received <n> of <m> bytes` beside `network error`.
* **verify #12** (`pin-qed64.mjs`): each `hardening` flag must agree with QED64's history at the pin: a flag `true` needs
  every fix commit to be an ancestor of the pin's commit, and a fix that is an ancestor with the flag absent is a FAIL
  too (the suite would otherwise record a VERDICT with the ask unenforced). On pins A–H all three print OK as absent.

### Registration

1. **Descriptor** `pins/385a1ac/pin.json` (v3, as in the table; `servedTrees.baseSlim` and `baseN` 5004 are H's,
   `coreSrc` is `${QED64_SHOWCASE_WORK}/core-lib-slim.f69cca24d0878a58`, "Heavy path" below; `liveness.builtIn` true;
   `knownLimitations` empty).
2. **Our worktree** `$W/qed64-pins/385a1ac` (`qed64-src.mjs ensure`), the page built there (`npm ci` +
   `npm run build:site`, `pinI-build-site.log`; main bundle `index-DDUZGVEB.js`). The public binaries went into its
   gitignored paths as APFS clones: the 10 runtime chunks from the kernel fork's release directory
   `~/code/wasm64-lean-kernel-release/lean-v4.34.0-e1a79c1` (its `SHA256SUMS` 140/140 OK), each `cmp`-equal to QED64's
   public chunks; the 69 pack parts from `release/bf9d947`; the two stock `.snapz` from the owner's checkout (their
   digests are verify #5). The base release, not its `-r2`/`-r3` revisions (same buildId, other digests).
3. **`pin-qed64.mjs pin --pin 385a1ac`** (12:32Z, `pinI-pin.log`): `S0.2 OK  QED64 HEAD=385a1ac5f3bc… clean, kernel
   e1a79c1ce9 from toolchain/lean4-wasm64-release.json kernel.commit (lean-v4.34.0-e1a79c1), serves
   wasm64-f69cca24d0878a58`, `S0.4 OK  cloned 147 files`, `PIN DONE`.
4. **Shell from source** (`pinI-build-shell.log`): `SHELL-FROM-SOURCE OK: all 60 dist files built from 385a1ac5f3bc ==
   pins/385a1ac/QED64.lock.json (sha256)`.
5. **First verify** (12:33Z, `pinI-verify1.log`): every check OK, `#9 toolchain/lean4-wasm64-release.json kernel.commit
   (lean-v4.34.0-e1a79c1) at QPIN == KERNEL == lock qed64.kernel` and the three #12 lines among them, except the expected
   `FAIL #11 lock records the overlays — missing` and `DRIFT #7 docker qed64-toolchain:emsdk-6.0.5 … sha256:0de79b891eb9`
   (the tag now names the image the e1a79c1 release record names; a third id, rebuild-only). The kernel build's native
   inputs (#7) were still on this host then and matched. `pin check 385a1ac --full` (`pinI-check1.log`) was OK on the
   descriptor, the lock, the 147 release files, the main bundle and the notify line, and FAILed only on the runtime
   stores and overlays not yet built.

### Heavy path: stage1 from the release, the core library, bakes, overlays, preflight, headless

No native rebuild and no restage (map-heavy (b), (c)): the base trees are digest-identical to H's (`lib-tree-slim`
`8c247f41…`, 20,014 files; `lib-tree` `57adeb5f…`; equal to 385a1ac's `embedding/base-tree.json`), the staged trees'
core delta is 0, the kernel change `a8817d0` → `e1a79c1` touches only runtime files (`Lean/CoreM.lean`,
`Lean/Shell.lean`, the exports seed, `runtime/interrupt.cpp`, `runtime/stackinfo.{cpp,h}`), and native64 and Mathlib are
unchanged. The bakes and the headless run were one detached chain (`$W/logs/pinI-heavy1.log`), each heavy step under the
browser lock with `MIN_FREE_GB=16`.

* **Stage1** (10:41Z, `pinI-stage1-fetch.log`). The release's `tools/lean4-wasm64-4.34.0-e1a79c1.tgz` (sha256
  `65445d21bc64…`, as in the record's `files[]` and `SHA256SUMS`) unpacked into `$W/tools/lean4-wasm64-4.34.0-e1a79c1`;
  `node <package>/cli.mjs fetch --from <release dir> --id lean-v4.34.0-e1a79c1 --digest sha256:bd71636b… --out
  $W/toolchains/lean-v4.34.0-e1a79c1 --only runtime` → `FETCH VERIFIED`; its `bin/` cloned to
  `$W/runtimes/wasm64-f69cca24d0878a58/stage1/bin`, byte-identical to QED64's adopted bin
  (`qed64-wt-modular/work/adopt/lean-v4.34.0-e1a79c1/artifact/bin`). This is the first pin whose runtime comes from the
  kernel fork's release instead of QED64's `pipeline/toolchain/work/` tree.
* **Core library** (10:41Z). `cli.mjs fetch … --only lean-lib` (`36 files verified`, `FETCH VERIFIED`,
  `pinI-corelib-fetch.log`), then `unpack --slim` into `$W/core-lib-slim.f69cca24d0878a58`: 10,074 files, 0.77 GB, 2,518
  `*.olean.private` left out (`pinI-corelib-unpack.log`); tree digest `sha256:e442c951…93ab` == 385a1ac's
  `embedding/base-tree.json` `core-lib-slim`. H's `coreSrc` differs in content (it is the runtime's own library, which
  patches 0036/0037 changed); with core delta 0 `stage-trees` never copies from it, but it must resolve.
* **Bakes** (`SHOWCASE_PIN=385a1ac scripts/showcase.sh bake w7|w8`; `pinI-bake-w{7,8}.log`). Both one attempt, rc 0,
  `JUDGE … GREEN` and `PAIRING GREEN` with `CMP` against `bake-work`:

  | Bake | Lock acquired | N | Raw bytes | `.snapz` (transfer) | Wall | Peak tree RSS | `time -l` maxrss | free+inactive at start |
  |---|---|---|---|---|---|---|---|---|
  | w7 | 12:34:55Z | 5107 | 1,163,657,293 | `widgets.9eb6987f65d3aba1.snapz` (331,578,461) | 369 s | 15,821 MiB (15.45 GiB) | 16,623,058,944 B | 19 GiB |
  | w8 | 12:41:08Z | 5684 | 1,267,834,573 | `widgets.ebd0fc1b6fe9f4e7.snapz` (364,676,295) | 370 s | 17,273 MiB (16.87 GiB) | 18,115,411,968 B | 22 GiB |

  The raw sizes equal those of runtime 3ab1c6a9 (D–H) with new digests. The peaks are the highest of any runtime so far
  (3ab1c6a9: maxrss 15.9 GB w7, 13.5 GB w8) and the w8 peak is above the 16 GiB floor the chains use; it started with
  22 GiB free+inactive. w8's informational plan-estimate line prints `WARN … [1.35, 1.75] GB MISSED (raw 1.268 GB)`; it
  is not one of the judge's checks (J1–J5 all OK). `raw/widgets{7,8}.snap` were then made as APFS clones of
  `bake-work-w{7,8}/widgets.snap`, by hand as in pin D (`pin check`: sizes equal).
* **Overlays** (12:47Z, `pinI-overlay.log`): `out/runtimes/wasm64-f69cca24d0878a58/overlay/widgets{7,8}` (index 854 and
  874 B), each `served as /snapshots/widgets{7,8}.f69cca24d0878a58/`, `PAIRING GREEN` with `CMP` against `bake-work`.
* **Preflight** (12:47:29–12:48:08Z, `pinI-preflight.log`; `serve.mjs` on :5196 with `SHOWCASE_PIN=385a1ac`): `preflight
  pipeline/release/preflight.mjs`; for both, `PREFLIGHT OK buildId=wasm64-f69cca24d0878a58 mode=resident
  snapshots=snapshots/widgets{7,8}.f69cca24d0878a58`; boot smoke ready in **13,264 ms** (w7) and **14,277 ms** (w8); each
  boot fetched only its own directory's two `.snapz`.
* **Headless** (12:48:09–13:05:21Z, about 17 min; `pinI-hl-{controls,stage4,e2,summary}.log`). `CONTROLS PASS` (11/11);
  stage 4 `STAGE4 all: 0 failing step(s)`: E1 15/15 PASS (9/9 checks each, so no warning: patch 0037's async-message
  reporting did not surface one), E3 15/15, E3b 15/15, max RSS 12.22 GB; E2 7/8 with tree-scope on L1 (`#tree_scope:
  rbSample does not reduce to a constructor application`), 0 warnings in all eight, max RSS 14.24 GB (dist-lens). Summary:
  `GATE {"E1":{"w8":"8/8","w7":"7/7"},"E3":{…},"E3b":{…},"E2":"7/8 clean","E2rootCaused":["tree-scope:
  L1-exported-level-imports"],"E2Green":true,"stage4Green":true}`.

### Record, verify, activate

1. **`record-overlays --pin 385a1ac`** (13:05:21Z, `pinI-record.log`): `RECORDED overlays widgets7 (3 files, served at
   /snapshots/widgets7.f69cca24d0878a58/), widgets8 (3 files, served at /snapshots/widgets8.f69cca24d0878a58/)`.
2. **Verify, without the kernel build.** The chain's verify refused at once (`pinI-verify2.log`:
   `QED64_KERNEL_BUILD=…/wasm64-lean-kernel-build-v4.34.0 does not exist`): the native kernel build dir that `.env.local`
   names was deleted on this host by another session between 12:33Z (verify 1 still read it) and 13:05Z, around 12:48Z.
   Re-run with `QED64_KERNEL_BUILD=` (an empty value wins over `.env.local`; this is what CI sees): **`VERIFY OK (1 N/A
   (rebuild-only input not on this host))`** (`pinI-verify2b.log`): #7's native inputs N/A, #9 from the release record,
   #11 url and dir OK for both overlays, #12 three OK. #7 checks rebuild-only inputs; nothing native ran for pin I. The
   gate chain exports the same empty value.
3. **`pin check 385a1ac --full`** (`pinI-check2.log`): `PIN CHECK OK 385a1ac (full)`.
4. **`pin use 385a1ac`** (13:10Z, `pinI-use.log`): 13 links moved, the gitlink staged, `build-gallery: pin   overlays
   widgets7 -> /snapshots/widgets7.f69cca24d0878a58/, widgets8 -> /snapshots/widgets8.f69cca24d0878a58/`,
   `BUILD-GALLERY OK 8 examples` (api `1.0.0`, shell `shell-d96be803c9315cde`), `PIN SWITCHED bf9d947 -> 385a1ac`,
   `DEPLOY-MANIFEST OK 77 assets, 95 R2 objects; gallery 3da79ea2…`, `PIN CURRENT OK 385a1ac`.
5. **Live gallery gate** (13:13Z, `pinI-check-gallery-live.log`): `CHECK-GALLERY OK 170 ok, 0 failed`, with `SIM-GALLERY OK
   244 ok, 0 failed`; among the checks `pin.json overlays == pins.mjs overlayDirs(385a1ac)`, the alias, literal and legacy
   cases, the live preflight of `widgets8` at its directory, and `per-runtime pin: GET /snapshots/widgets{7,8}/index.json
   → 404`.
6. **`scripts/showcase.sh verify`** (13:13Z, `pinI-verify-showcase.log`): `VERIFY: all checks OK` (I in full; the eight
   staged pins' cheap checks OK with their bare `/snapshots/widgets{7,8}/`).
7. **`deploy-manifest --check`** (13:16Z, `pinI-dm-check1.log`): `DEPLOY-MANIFEST CHECK OK`, 77 assets 17.7 MiB, 95 R2
   objects 2.420 GB, R5 OK for both overlays, R6 OK for both copies, `G1 … CHECK-GALLERY OK 157 ok, 0 failed`; G2 `NO
   verdict … for this gallery 3da79ea2…` (expected before the UX runs).

**What an upload of I would add to the live bucket** (`out/deploy/manifest.json` against the live release record
`out/deploy/published/20261005T152953Z`, compared by URL path): 71 of I's 95 objects are already live with the same
sha256 (the packs); 21 are new, 1,274.5 MB (the 10 runtime chunks, `runtime-manifest.wasm64-f69cca24d0878a58.json`, the
two stock `.snapz`, the two per-build index copies and the six overlay files, 761.5 MB of them overlays); 3 replace a
live object: `/runtime/runtime-manifest.json` (phase 2) and `/profiles/index.json`, `/snapshots/index.json` (phase 3).
No object under the bare `snapshots/widgets{7,8}/` changes.

### Gates

**Done (static, headless, no browser):** registration and verify as above; shell from source 60/60; `pin check --full`
OK; headless controls 11/11, stage 4 green, E2 7/8 (L1) with `E2Green` and `stage4Green`; preflight of both overlays;
`check-gallery` live 170/0 with sim-gallery 244/0; `showcase.sh verify` all OK; `deploy-manifest --check` OK with R5 and
R6. Before registration (2026-10-09 ~12:09Z, H still active, `$W/pinI/scratch/integ3/`): `pin-qed64.mjs verify` on
each of A–H `VERIFY OK (1 DRIFT in a rebuild-only input)`, the Worker tests 26/26, `CHECK-GALLERY OK 157 ok` with
`SIM-GALLERY OK 244 ok`, and Playwright listing 35 tests.

**Browser gates: ON HOLD after the first full run (a runtime regression, kernel patch 0036).** The chain
(`$W/pinI/chain1.sh`, then `chain2.sh`/`chain3.sh`, which wait for memory and for other sessions' bakes OUTSIDE the host
lock instead of holding it idle; log `$W/logs/pinI-chain1.log`) started 2026-10-09 13:16Z. The host sat at ~10 GiB
reclaimable (a VM, then the compressor) for hours, and another session baked outside the lock 16:06–17:37Z, so the runs
`i-full1` and `i-full1-b` were refused before any test ran (their names are taken; the full runs continue as `i-full2…`).

| Run | When | Result | Evidence |
|---|---|---|---|
| v1 smoke on `:5235` (H's 22 checks plus the network check) | 2026-10-09 16:01Z | **23/23 pass**; the network check: 248 requests, 0 per-build index copies, 0 404s; console allowlist OK, whole-run pairing OK | `$W/logs/pinI-smoke.log`, `out/ux/v1-smoke/report.json` |
| `i-full2` | 2026-10-09 17:36–17:57Z | **RED, NOT A VERDICT**: 29 passed, 5 failed (W8, C20, C22, C10, C14), 1 skipped. W8/C20/C22: the kernel 0036 regression below. C10: a renderer crash on the 4th storm reload (the #55 residual; peak renderer 14.29 GB transient 1.6 s into the storm). C14 fails on that crash. **C9 (#62), C11 (#63) and the C1 network oracle (#64) passed** | `$W/logs/pinI-ux-full2.log`, `out/ux/i-full2/tests/{W8,C20,C22,C10,C9,C11,C1}.json` |
| `i-full3…`, `i-c20-{1,2,3}`, `i-headed1`, `i-throttle-t10p`, `i-c11h3`, `i-c10x20` | not run | on hold: W8/C20/C22 fail deterministically on this runtime; never run on I (superseded: the same gates ran on J, "Pin J" below) | – |
| `deploy-manifest --record-verdict`, `ci/rehearse-deploy.sh` (+ `old-shell`), qed64-static CI mirror | not run | on hold (no VERDICT to record); on J: `--record-verdict` done, the rest pending ("Not done / running") | – |

**The regression: kernel patch 0036's engine-stack probe rejects proofs Chrome ran before.** On runtime f69cca24 the
C20 click-all is DistLens 12/21 (hasse-view 47/47, graph-scope 58/58, simp-lens 6/6, interval-inspector 3/3): all 9
failures are the inserted `example : twoDice k = … := by unfold Showcase.DistLens.twoDice Showcase.DistLens.die; pmf_num`
(k = 1..9), each with the fork's new error "maximum recursion depth has been reached: the WebAssembly runtime's stack is
exhausted (…)" (`src/Lean/CoreM.lean:513` at e1a79c1); native re-elaboration of each takes 0.65–0.9 s. W8 fails on the
same `twoDice 5` click and on the weather example with `ennreal_num: cannot close this ℝ≥0∞ goal` (a probe error caught
inside a tactic, as it reads); C22's slow-click case is the same `twoDice 5`. On H's runtime 3ab1c6a9 (kernel a8817d0, no
0036) the same 21 clicks are 21/21 in four runs (`h-full4`, `h-c20-1`, `-2`, `-3`), and our headless E3 in Node (a
larger stack) passes them on f69cca24 — the headless gate does not model a Chrome Worker's stack. 0036 (`41ec56530d`,
"deep recursion fails with an error at the engine's stack limit", for QED64 HARDENING #60) makes `Core.checkSystem`
require 16384 free argument slots (128 KiB) of the Worker's engine stack (~500 KiB in Chrome) on every 16th call, so an
elaboration needing roughly 370–500 KiB of engine stack — which used to complete — now fails. Reported to the kernel and
QED64 sessions on 2026-10-09 with the repro `$W/pinI/repro-0036/{TwoDice.lean,README.md}`.

**For QED64 (asks), from `i-full2`.** #64: the C1 cold boot made 123 requests, 0 per-build index copies, 0 404s, and the
browser saw 2 `.snapz` GETs = serve.mjs's 2 (`C1.cold.network.jsonl`, `C1.cold.server.log`): Playwright does see the
dedicated workers' requests. #62 (C9): halted 4.9 s after navigation, 0 runtime starts, 0 `.snapz` (server and browser),
0 `lean.wasm` chunks, 3 worker deaths (7 died lines in 2 bursts), no crash. #63 (C11): the lasting cut made exactly one
runtime start and ended `lastDeath {bootFailed, cause {stage snapshot, kind network}}` with the relay halted at 13.3 s;
the recovery reload (0.49 s after the halt) did not crash and was ready in 13.7 s with the right panel; the single cut was
absorbed (one start, ready in 18.2 s).

**The interim fix, as the staged test pin `5e63edd` (2026-10-09 ~18:50Z).** QED64 answered 0036 with branch
`fix/stack-probe-headroom` `5e63edd` (unpushed when staged; HARDENING #67): `public/workers/lean.worker.js` sets
`LEAN_WASM_STACK_PROBE_SLOTS=8192` at preRun, on the same runtime f69cca24. Registered as a v3 test pin from our own
worktree (`$W/qed64-pins/5e63edd`, fetched from QED64's local repository), like H before its push: only
`dist/workers/lean.worker.js` and `dist/qed64-build.json` differ from I; same main bundle (notify site hash unchanged),
runtime, stock snapshots, profiles and overlays (I's per-runtime directories, nothing rebaked); `S0.2 OK`, `verify` OK
(#7 N/A), `SHELL-FROM-SOURCE OK 60/60`, `pin check --full` OK, active since ~18:55Z. `pin-qed64.mjs pin` now carries the
native toolchain record from the active pin's lock when `QED64_KERNEL_BUILD` is unset (this host's kernel build directory
was removed; the record is a rebuild-only fact, printed as `S0.5 NOTE … carried from pin 385a1ac's lock`). **Run `j-dl1`
(W8, C20, C22 only; 19:00–19:10Z): 3/3 passed — C20 135/135 with DistLens 21/21 (I: 12/21), W8's three clicks clean
(the weather `ennreal_num` failure gone too), C22's slow `twoDice 5` click ok** — the interim recovers every case we
hit. The full gate on `5e63edd` runs as `$W/pinI/chainJ2.sh` (log `$W/logs/pinJ-chain.log`, runs `j-*`); it counts for
QED64 main only if main is this same SHA (else re-register and re-run).

**Pin J = `5e63edd` (2026-10-09 ~20:30Z: QED64 pushed the staged commit to main as a fast-forward, CI and deploy green).**
The descriptor was promoted (label/status only: lock `a6d481b7…` and gallery `65279b0b…` unchanged), so every run on
the test pin counts. J serves the same runtime `f69cca24`, overlays (`widgets{7,8}.f69cca24d0878a58`), main bundle and
stock snapshots as I; shell `shell-f4c57699a033beda`; lock sha256 `a6d481b782d9…`; gallery content `65279b0b4c27aa9f…`.
Gates (`$W/logs/pinJ-chain.log`; per-step logs `$W/logs/pinJ-*.log`; chains `$W/pinI/chainJ{2,3,4,5}.sh`, which wait
for memory, other sessions' bakes and headless Chrome OUTSIDE the host lock; times 2026-10-09 to 2026-10-10 UTC):

| Run | When | Result | Evidence |
|---|---|---|---|
| `j-dl1` (W8, C20, C22 only) | 10-09 19:00–19:10Z | 3/3; C20 135/135, DistLens 21/21 (I: 12/21) | `pinJ-ux-dl1.log` |
| `v1-smoke` | 19:12–19:13Z | 23/23; network 248 requests, 0 per-build index copies, 0 404s | `pinJ-smoke.log` |
| `j-full1` | 19:15–19:37Z | **VERDICT** (34 passed, C19 skipped) | `pinJ-ux-full1.log` |
| `j-full2` | 19:39–20:01Z | red: C10 renderer crash (+ C14); the crash is PA-OOM-CDP (below) | `pinJ-ux-full2.log` |
| `j-full3` | 20:03–20:26Z | red: C3 renderer RSS 10.67 GB (line 10.5 GB; tracing on, below) | `pinJ-ux-full3.log` |
| `j-full4` | 10-10 00:03–00:27Z | red: C3 10.50 GB (peak 10.51), C21 renderer crash during the stall card's restart (+ C14); the crash is PA-OOM-CDP | `pinJ-ux-full4.log` |
| `j-full5` | 00:29–00:51Z | **VERDICT** (34 passed, C19 skipped); the recorded verdict | `pinJ-ux-full5.log` |
| `j-c20-1/2/3` | 00:53–01:18Z | 135/135 each (405/405), DistLens 21/21 each (in 64.7, 65.0, 65.8 s) | `pinJ-ux-c20-{1,2,3}.log` |
| `j-headed1` (headed Chrome for Testing) | 01:20–01:43Z | red: C3 10.51 GB, C10 renderer crash (+ C14); no `.ips` left | `pinJ-ux-headed1.log` |
| `j-headed2` (headed) | 03:11–03:35Z | **HEADED SIGN-OFF** 35/35 (C19 included); started before tracing was turned off, so it ran with tracing | `pinJ-ux-headed2.log` |
| `j-throttle-t10p`: 10 Mbit/s / 40 ms first visit, `throttle-proxy.mjs --listen 5298 --upstream 5297` (`:5197` was taken by another project's vite server) | 03:37–03:47Z | **`RESULT PASS`**, ready at **565.1 s** (H 565.6 s, E 565.1 s); the proxy measured 693.6 MB down at 9.8 Mbit/s (the visit 693.1 MB; page and 29 worker targets shaped); progress visible in 563 of 564 samples, error card in 0, longest unchanged progress 6.0 s, the gallery's notice from 368.7 s, panel EQUAL to golden, no crash, console OK | `pinJ-tp-t10.log`, `pinJ-tp-proxy.log`, `out/ux/j-throttle-t10p/explore/throttle-t10p.json` |
| `deploy-manifest --check` | 03:50Z | `DEPLOY-MANIFEST CHECK OK`: G2 `verdict run j-full5 … on THIS gallery 65279b0b…, lock a6d481b782d9… and overlays widgets8, widgets7`; 77 assets 17.7 MiB, 95 R2 objects 2.420 GB; R5 and R6 OK; G1 157 ok | `pinJ-dm-check.log` |
| `deploy-manifest --record-verdict` | 03:50:44Z | `infra/ux-verdict.json` names `j-full5` (gallery `65279b0b…`, lock `a6d481b7…`, both overlays, pin `5e63edd`); not yet committed | `infra/ux-verdict.json` |
| `j-c11h3` (C11 headed ×3, QED64's #63 ask; tracing off) | 03:51–03:53Z | 3/3 passed: the single cut absorbed each time (1 runtime start, ready 13.5–13.9 s); the lasting cut 1 runtime start, 3 deaths, `cause.kind` network, relay halted at 10.8–10.9 s; the recovery reload (0.51–0.52 s after the halt) never crashed and was ready in 11.7–12.2 s with the panel equal | `pinJ-ux-c11h3.log` |
| `j-c10x20` (C10 ×20, the #55-residual tally; tracing off, `DEBUG=pw:browser`) | 03:55–04:05Z | **20/20 green, 0 renderer crashes**: renderer peak 10.00–11.64 GB (median 11.18; the tracing-on full runs peaked at 12.57–14.29), ready 21.8–22.7 s after the storm start, panel equal every time, 3–4 runtime starts and 2–5 `[boot] waited` lines per storm. The C10 crashes counted before (2 in 4 on f69cca24, about 1 in 9 on H) were the tracing artifact (`h-full2b`'s C10 crash on 2026-10-06 also classifies as PA-OOM-CDP) | `pinJ-ux-c10x20.log`, `out/ux/j-c10x20/tests/C10*.json` |

**The C3 memory A/B (the kernel's design; 5 interleaved rounds of H `bf9d947`, I `385a1ac` (guard 16384), D `58ae6d2`
(QED64's measurement-only commit: guard off, registered here as an uncommitted staged pin) and J (guard 8192), C3 only,
2026-10-10 01:44–03:08Z).** Renderer GB at ready → after the 8 panels: H 9.55 → 10.50 (n = 5), I 9.52 → 10.45 (4), D
9.44 → 10.25 (5), J 9.48 → 10.39 (4); pool max 14–16 running everywhere; 0 error diagnostics everywhere; the page JS
heap (`performance.memory`, quantized by Chrome) flat at 68.9/92.9 MiB. **Interleaved there is no runtime offset**: the
earlier "+0.3 GB on f69cca24" compared with H runs from days before (host drift), and every arm crosses C3's 10.5 GB line
on some runs today (H 10.87 and 10.51). Renderer crashes: I r1 (at the DistLens open, 10.63 GB before it) and J r5 (at
the graph-scope open), none on H or D — 2/10 guard on vs 0/10 off (not significant alone, p ≈ 0.47). Vectors sent to
QED64/the kernel; logs `$W/logs/pinAB-c3-{h,i,d,j}-{1..5}.log`. All four arms ran before tracing was turned off (next
paragraph), so the comparison is like for like but the absolute figures include the trace recorder's cost. *Revised
2026-10-10 (next paragraph):* the guard-on split reads as chance, and the full-suite crashes it was first read against
(`i-full2`, `j-full2`, `j-full4` C21) were a harness artifact.

**The crash classification and tracing (the kernel session, 2026-10-10).** macOS ReportCrash writes
`~/Library/Logs/DiagnosticReports/chrome-headless-shell-*.ips` for every renderer crash of chrome-headless-shell; the
kernel's classifier (copy: `$W/pinI/crash/crash-sig.py`, frame offsets valid for Playwright's chromium_headless_shell
build only) sorts them by the faulting stack:

| Crash | `.ips` capture time | Class | DedicatedWorker threads |
|---|---|---|---|
| `i-full2` C10 | 2026-10-09 17:52:57Z | **PA-OOM-CDP** | 26 |
| `j-full2` C10 | 19:57:32Z | **PA-OOM-CDP** | 26 |
| `j-full4` C21 | 2026-10-10 00:15:03Z | **PA-OOM-CDP** | 26 |
| C3 A/B I r1 (`i-c3ab-1`) | 01:49:31Z | **V8-OOM** | 31 |
| C3 A/B J r5 (`j-c3ab-5`) | 02:58:19Z | **V8-OOM** | 31 |
| `j-headed1` C10 (headed Chrome for Testing) | – | no `.ips` left | – |

**PA-OOM-CDP** is a PartitionAlloc OOM in `DevToolsSession::SendProtocolResponse` while serializing a
`Network.getResponseBody` reply: Playwright's tracing (our `tests/ux/playwright.config.mjs` had `trace:
'retain-on-failure'`) fetches EVERY response body over CDP (its HarTracer, whatever the content mode), so a QED64 Worker
re-fetching the 1.27 GB snapshot on a reload or restart had it base64'd inside the renderer. That is a **harness
artifact** (users never run DevTools), and it also inflated every renderer-RSS figure taken with tracing on: C3's 10.5 GB
line failures (`j-full3` 10.67, `j-full4` 10.50, `j-headed1` 10.51 GB) and C10's transient peaks (12.57–13.78 GB in
J's full runs, 14.29 GB in `i-full2`). The two A/B crashes are **V8-OOM** (a Scavenge could not grow the heap after the
pool had grown to 31 DedicatedWorkers: the #55 cage). Pool growth past 24 Workers happens in every arm (H, I, D, J), so
the guard-on 2/10 vs off 0/10 split reads as chance, not as a 0036 effect. **Fix (ours):** `tests/ux/playwright.config.mjs` now has
`trace: process.env.UX_TRACE || 'off'` (`UX_TRACE=retain-on-failure` opts in to debug one failure; the file changed at
~03:23Z). The headed sign-off `j-headed2` started at 03:11Z, before the change, so it ran with tracing; any later
`chainJ4` retry (`j-headed3` on), the 10 Mbit/s visit, `j-c11h3`, `j-c10x20` and every later measurement run are
tracing-off. Also new in the suite: `UX_CRASH_DIAG=1` (opt-in) adds Chrome `--enable-logging=stderr --v=0` (printed
under `DEBUG=pw:browser`); C3 records the page JS heap per panel (data) and, with `UX_C3_DIAGS=1` (the A/B only, never a
verdict run), per-panel diagnostics; C10 records a crash that CDP reports first (`Target crashed`) and no longer fails
on an unhandled rejection from the raced `Page.reload` send.

### Open decisions (the user's; refreshed 2026-10-10 for J)

1. **E1, the deploy window** (a runtime change: J, like I, replaces E's runtime `3ab1c6a9` with `f69cca24`). Phase 3
   replaces the live `/snapshots/index.json` and `/profiles/index.json`, which E's shell reads; from then until the new
   Worker is live, bare `/?…` visits of the stock page fail (the gallery uses overlays and is not affected by the stock
   index; QED64's own window on 2026-10-08 was about 10 minutes). The scripts allow a split upload by hand
   (`PHASES=1-objects,2-manifests scripts/upload-artifacts.sh`, `ALLOW_PARTIAL_UPLOAD=1 scripts/deploy-app.sh` without
   `PUBLISHED_ORIGIN`, then `PHASES=3-indexes scripts/upload-artifacts.sh`). **It is not possible through the CI deploy:**
   `qed64-deploy.yml` runs `deploy-app.sh` with the published check (`PUBLISHED_ORIGIN` = `SHOWCASE_ORIGIN`), and
   `deploy-manifest --published` compares the phase-3 indexes too, so it refuses until phase 3 is up, which opens the
   window. QED64's own `docs/DEPLOY.md` (at `5e63edd`, "Once, for the shell deployed before HARDENING #64") gives the
   same two routes: deploy the first #64-reading shell on the pairing that is already served (nothing to upload, no
   window) and change runtime only after it is live, or upload the `.snapz` and per-build copies before the deploy and
   the mutable indexes right after it. None of our pins is a #64 shell on E's runtime (the #64 pins I and J are on
   `f69cca24`), so for us the choice stays: accept the window, deploy by hand with the split, or change the CI published
   check. The `old-shell` rehearsal (not run yet; after J's evidence runs, on the commit) measures both orders.
2. **Push `qed64-pin-i`** (the local branch, based on H's `d60b15e`; I and J still to be committed on it). A push to
   `main` that touches `qed64-showcase/` **is** a deploy (`.github/workflows/qed64-deploy.yml`, G2 from the committed
   `infra/ux-verdict.json`, which will name `j-full5`). Also: whether to merge and deploy H first (branch
   `qed64-embedding-v1`, E's runtime: no index window, its committed record `h-full4`) or go straight to J.
3. **Alias policy.** The alias is in the gallery only (`?overlay=widgets8` → `widgets8.f69cca24d0878a58`), no Worker
   redirect, so older pins' bare objects stay verifiable. Consequence: a bookmark of the stock page
   `/?snapshots=snapshots/widgets8` fails after a `f69cca24` pin (I or J) is deployed, as QED64's named unpaired error
   (#62's early halt); gallery links keep working. Accept, or add a Worker redirect.
4. **Stale open tabs.** A gallery opened before the deploy that reboots its frame afterwards gets the new shell with the
   old overlay and fails as unpaired; a page reload fixes it. Optional: compare `/qed64-build.json`'s buildId with
   `pin.buildId` and show a "site updated, reload" card. Now or later.
5. **H's verdict record.** `--record-verdict` has replaced `infra/ux-verdict.json` with J's (`j-full5`, not committed);
   the committed record (`bd42150`) names H's `h-full4` on gallery `d8a5bb6d…`, which `pin use bf9d947` no longer
   reproduces (it regenerates `pin.json` with the `overlays` map and the new `gallery.js`/`lib.js`), so a redeploy of H
   with this gallery code needs new H verdicts. H's R2 objects and the live record stay valid; `pin use bf9d947` still
   works locally.
6. **R2 growth.** Each runtime adds its own overlay directories, about 762 MB (I: 761.5 MB; J adds nothing over I: same
   overlays, 95 objects, 2.420 GB in all); uploads are copy-only and never delete. Pruning is manual, and only after
   every pin that uses them is retired.
7. **Upstream, waiting on the user (2026-10-10):** kernel patch **0038**, the real 0036 fix (probe four times as often
   with a quarter of the headroom), waits for the user's OK in the kernel session; it means a new release, a QED64
   promote and a re-pin. QED64's **#68** (a page that replaces its own runtime waits for all of its Workers) is the
   branch `fix/own-predecessor-wait` (our measurement arm `27a4ba6`), **not on QED64 main**; a re-pin only once it lands.

### Not done / running (pin J, 2026-10-10 ~03:55Z)

1. **Done:** QED64's evidence runs `j-c11h3` (3/3) and `j-c10x20` (20/20, 0 crashes, tracing off; table above).
2. **Done: the pool-growth measurement** (`$W/pinI/chainPG.sh`, 2026-10-10 04:05–05:21Z; analysis
   `$W/pinI/pg-analysis.txt`, script `$W/pinI/pg-analyze.py`): 8 interleaved rounds of `27a4ba6` (G: 5e63edd + #68 + the
   `[pool]` growth/lifetime diagnostic; a ship candidate, not on main), `0ff314c` (P8: parking 8) and `3b804ea` (P4:
   parking 4), each one fresh C3 + one C10 storm, tracing off: **0 crashes in 24 runs, no `.ips`**; pool growths G 11, P8
   8, P4 9, every one a burst with F = 0 (finished-unreturned 0) to N = 25 or 26, none during any reload storm; growth
   threads returned after a median 515 ms (G), 5.9 s (P8: parked), 579 ms (P4); thread starts by the end of C3 G ~1,230,
   P8 ~45, P4 ~90 (parking cuts the churn about 25×); renderer peak in the C10 storm G 10.94–11.81 GB vs P8 9.84–10.18
   and P4 9.99–10.17; C10 reload-to-ready medians G 22.26 s, P8 21.82 s, P4 21.88 s. (QED64's accounting note: `parked` is
   a subset of `running`, so a per-panel unused + running + parked double-counts parked threads.) Sent to QED64, which
   asked the kernel about parking 8 as QED64's default. The measurement pins (`27a4ba6`, `0ff314c`, `3b804ea`, `58ae6d2` =
   guard off, `349b1b7` = probe 256) stay registered locally, never committed, until QED64 says they can go.
3. **Done: the commit** `f6f2c8c` on `qed64-pin-i` (60 files; `infra/ux-verdict.json` → `j-full5`, `pins/385a1ac/`,
   `pins/5e63edd/`; not the measurement pins), local only. **qed64-static CI mirror on `f6f2c8c`** (fresh clone,
   2026-10-10 05:15Z; `$W/logs/pinJ-ci-local.log`, run dir `$W/pinJ/ci-local-J1`): **JOB SUCCESS**, 12/12 steps (the shell
   from source byte-identical to J's lock, the Worker tests, CHECK-GALLERY + SIM-GALLERY). **Deploy rehearsal on `f6f2c8c`** (`$W/pinI/chainRH.sh`, 2026-10-10 05:26–08:21Z, fresh clones, local fakes only;
   J's rehearsal state `$W/deploy-rehearsal-J` (95 objects), run dir `$W/pinJ/rehearse-deploy-J1`, log
   `$W/logs/pinJ-rehearse-deploy.log`): **`REHEARSE-DEPLOY OK: skip dry-run unpublished deploy first no-verdict tamper
   old-shell`** (tamper on the per-runtime index `widgets8.f69cca24d0878a58/index.json`: 93/95 published, FAIL as it must).
   **`old-shell` against the LIVE shell (H, `d60b15e`; OLD_STATE = the live objects) measured decision E1**
   (`old-shell/e1-measure.txt`): phases 1–2 under the live shell: its published check OK without the one replaced
   phase-2 key (`REPLACED-KEYS OK 1`), every bare `snapshots/widgets{7,8}/` object untouched, the old gallery and stock
   boots OK. **Order A** (phase 3 BEFORE the deploy, today's order): in the window the OLD shell's bare `/` stock boot
   FAILS (it reads the replaced `snapshots/index.json` and `profiles/index.json`), **the OLD gallery boots OK** (its
   overlays are the untouched bare directories); then the new workflow, its published check, deploy and smoke, and the new
   gallery + stock boots are OK. **Order B** (phase 3 AFTER the deploy): the CI published check REFUSES the deploy before
   phase 3 (rc 1), as predicted; a Worker deployed without that check smokes OK, and in the window the NEW gallery and the
   NEW shell's `/` stock boot are both OK (QED64's per-build index copies, #64); after phase 3 everything is OK. **So the
   showcase gallery has no window in either order**; only the plain QED64 page at our origin's `/` fails between the
   indexes' upload and the deploy in order A (minutes), and order B removes that too but needs the CI published check
   to skip phase-3 keys (or a manual deploy).
3b. **Done: the thread-budget / sync-elaboration timing A/B for QED64** (`$W/pinI/chainTB2.sh`, `chainTB3.sh`;
   analysis `$W/pinI/tb2-analysis.txt`, script `$W/pinI/tb-analyze.py`; tracing off; C3 + the full C20 per run). **J
   5e63edd vs `8f29630`** (QED64's fix/own-predecessor-wait: #68 restart wait + pool diagnostics + #69 thread budget, task
   manager min(cores, 8) and 4 parked threads + #70 `-DElab.async=false`, probe 8192), 5 interleaved rounds: DistLens
   21/21 in all 10 runs, no crash; C20 wall median J vs 8f29630 hasse-view 117.6 / 107.7 s, graph-scope 102.8 / 97.7 s,
   DistLens 63.3 / 59.5 s; DistLens click→ready median 1259 / 998 ms; C3 renderer peak 10.04–10.37 / 9.46–9.70 GB; the
   pool never grew past 24 on 8f29630 (J 26). So n = 8 + sync elaboration is not slower on the showcase and uses less
   memory. **`6fa2a16`** (= 8f29630 + #71, the probe back to the runtime's 16384), 2 rounds before QED64 decided:
   **DistLens 13/21 and 14/21**, every failure (`twoDice 1…8`) ending in `ennreal_num: cannot close this ℝ≥0∞ goal …` —
   under sync elaboration the stack guard's error is caught inside the tactic, so the user sees a false mathematical
   failure instead of "stack is exhausted". QED64 therefore recommends keeping 8192 (branch fix/keep-probe-8192, tip
   `ebfb039`, code byte-identical to `8f29630`; not shipped: the user's decision). `8f29630` stays registered locally
   (uncommitted) as the staged candidate; `eb49fe7` and `6fa2a16` were removed. The per-item results are in the kernel's
   0038 calibration corpus `$W/pinI/corpus-0038/INDEX.md` (read in place by the kernel session).
4. The user's decisions above; the upload, the push and the deploy each need an explicit yes.
5. `.env.local` still names the deleted kernel build dir (`QED64_KERNEL_BUILD`, removed by another session on
   2026-10-09 ~12:48Z): verify on this host needs `QED64_KERNEL_BUILD=` (then `#7` prints N/A) until it is rebuilt or the
   user updates or clears that line. `pin-qed64.mjs pin` carries the native toolchain record from the active pin's lock
   meanwhile (`S0.5 NOTE`). Rebuild-only inputs; the served files are unaffected.
6. Optional: record `servedTrees.baseSlimDigest` (`8c247f41…`) and `coreDigest` (`e442c951…`) in the I and J
   descriptors so G0 checks the trees instead of printing SKIP.
7. Docker tag drift: `DRIFT #7` names `0de79b891eb9` (rebuild-only, not acted on; docs/BUILD-FROM-SOURCE.md).

Back to I (the 0036 regression; evidence only): `scripts/showcase.sh stop && scripts/showcase.sh pin use 385a1ac`.
Back to H: `pin use bf9d947` (bare overlay directories; a redeploy of H needs new UX verdicts on the regenerated
gallery, decision 5). Back to E (legacy mode, live): `pin use 33b0967`.

## 2026-10-12: pin K (62a06e2 / wasm64-f69cca24d0878a58, QED64 main) — QED64 #68–#72, DistLens's tactics as elaborators; K active

*Status 2026-10-13 ~02:25Z:* **K is the active pin of this checkout and fully gated**: DistLens 21/21 in the browser at
QED64's default probe, two VERDICTs (`k-full1`, `k-full5`), C20 405/405, the headed sign-off `k-headed1` 35/35, the
10 Mbit/s first visit PASS, `DEPLOY-MANIFEST CHECK OK`, `infra/ux-verdict.json` → `k-full5` ("Gates (K)" below). J `5e63edd` stays registered (gated,
committed in `f6f2c8c`) but **shares K's runtime and therefore its per-runtime overlay directories**: the `widgets8`
overlay there is now K's (the DistLens change), so `pin use 5e63edd` would need J's artifacts back from
`$W/backup-J-20261012` (a CoW copy of mathlib4, widgets-src, the staged trees, runtime f69cca24's bake-out/bake-work/raw/
BAKE-KEY/bake-logs for w8, `out/runtimes/…/overlay/widgets8` and `…/headless`; 145,883 files). The live site still serves
H `bf9d947`; nothing is pushed. Lane: chains `$W/pinI/chainK{1..7}.sh`, notes in `$W/logs/pinK-chain.log`, step logs
`$W/logs/pinK-*.log`.

**What K is.** `62a06e2632b5` is QED64 main as pushed on 2026-10-12, on the same runtime and promote as I and J
(`wasm64-f69cca24d0878a58`, `fc945e4`, kernel `e1a79c1ce9`). Since J: **#68** a page that replaces its own runtime waits
for all of its Workers; the `[pool]` growth diagnostic; **#69** a thread budget (task manager min(cores, 8), 4 parked
dedicated threads); **#70** the resident worker runs `-DElab.async=false` (a file of ~20 Mathlib theorems crashed the tab
under async elaboration: blocked pool tasks start standard workers that never exit); **#71** Lean's stack probe back at
the runtime default 16384 (#67's 8192 withdrawn); **#72** the stack backstop: on a real engine-stack death the relay
pauses after the FIRST death, `lastDeath.cause.code = "ENGINE_STACK_OVERFLOW"`, one note diagnostic from source "QED64",
any edit resumes (the strings are in `$W/pinI/backstop-62a06e2.md`). Main bundle `/assets/index-DMfixaZP.js`, console
notify site line0 627 `d5c84e1f…`; release set 147 files; lock `9e041ead…`; gallery content `1454d28e…`.

**Why the widgets changed (the user's choice (b), NEXT-STEPS 2026-10-12).** At 16384 the DistLens click examples
`twoDice 1…8 … := by unfold …; pmf_num` failed in the browser (13/21 on `6fa2a16`), each with DistLens's own fallback
"ennreal_num: cannot close this ℝ≥0∞ goal" for a TRUE claim: the WebAssembly stack guard (kernel patch 0036) tripped
inside instance synthesis, which converts runtime errors into "failed to synthesize", and `first` restored the state and
printed the fixed fallback (`$W/pinI/why-ennreal-num.md`; a flat hand-written sequence of the same steps passed at 16384,
`$W/pinI/stackexp/`). The depth came from the nested macro layers (`pmf_num` → `<;>` → `ennreal_num` → `first` → branch).
**`6b31bba`** rewrites both as `@[tactic]` elaborators running the same recipe in the same branch order as flat
`evalTactic` steps (`packages/dist-lens/DistLens/Verify.lean`; PORT-NOTES 2026-10-12): native stack for `twoDice 5`
(`lean --tstack`, `Elab.async=false`) 265 → 197 KB, the same as the flat sequence. False goals keep the byte-identical
"cannot close" message; a branch whose error or logged messages carry the guard's text now ends in "ennreal_num: Lean ran
out of stack while checking this goal, so it could not decide it (the claim may well be true)" with the guard's message
quoted (`DistLensTests/StackGuardTests.lean`, 6 `#guard_msgs` cases). Natively: `lake build`, VerifyTests, ClickE2E,
StackGuardTests green.

**Native toolchain.** The kernel build directory named by `.env.local` (`QED64_KERNEL_BUILD`) was deleted on this host
by another session (2026-10-09); it was rebuilt at `$W/kernel-build-native64` from the kernel release's
`native64.tar.gz` (`bin/lean` `42a5c2b0…` and `lake` `5b44c751…` == the lock) plus NATIVE-COMMIT, BUILT-COMMIT,
`mathlib/MATHLIB-COMMIT`, `mathlib/mathlib4` → `$W/mathlib4`, and `mathlib/essential-modules.txt` from the release lists
(`2194a774…`, identical across releases). The chains export that path; `.env.local` is the user's to update. The Docker
tag `qed64-toolchain:emsdk-6.0.5` now names `0de79b891eb9` (the kernel release's `docker.imageId`): the r3 drift proof
rebuilt 512 modules in it with 7,616 files byte-IDENTICAL (`$W/pinI/r3-drift.sh`, `$W/r3-drift/`), recorded as
`toolchain.docker.equivalent[1]` in K's lock.

**Build (2026-10-12; `pinK-*.log`).** `pin use 62a06e2`; export of the widgets at `6b31bba` (223 files, hash `b81f1b75…`,
the history keeps `c2efe78f…` at `90e415c`); native incremental rebuild: 5 new oleans (DistLens, its Demo, Verify,
Widget, LeanWidgetKit), header gate OK (`showcase.sh` `native_gate` now skips an incremental step that built no new
oleans: its oleans were gated when built); stage `all --force` (the J trees are backed up): STAGE-TREES OK, slim w8 5684
modules, fat 5685; **bake w8** `JUDGE w8: GREEN N=5684 raw=1272279733 /snapshots/widgets.557ea1a8a9d806c9.snapz`,
PAIRING GREEN, `CMP widgets` `cd6e6304…` (w7 is not rebuilt: DistLens is w8-only, the w7 overlay stays
`widgets.9eb6987f…`); overlay w8 (`widgets8.f69cca24d0878a58/`: `index.json` 874 B, `widgets.557ea1a8…snapz` 364.8 MB);
preflight OK (ready in 13.3 s); headless controls PASS; stage 4 30/30 PASS (DistLens E1 9/9, E3 129/129, E3b clean);
e2 7/8 (tree-scope `Demo.lean:104`, L1, as on every pin; dist-lens PASS in 80 s); record-overlays; `VERIFY OK`;
**`pin check 62a06e2 --full` FAILED once** on `raw/widgets8.snap size == bake-work-w8/widgets.snap`: `raw/widgets{7,8}.snap`
were by-hand APFS clones of the bake (pins D and I), so a rebake on the same runtime left J's copy behind. Re-cloned
(J's copy is in the backup), then `PIN CHECK OK 62a06e2 (full)`; `cmd_bake` now refreshes `raw/widgetsN.snap` itself.
Gallery gate GREEN `1454d28e…`, `CHECK-GALLERY OK 157 ok`.

**The DistLens validation in the browser (W8 + C20 + C22, `--grep "W8 DistLens|C20 |C22 "`).**

| Run | Result | Notes |
|---|---|---|
| `k-dl1` | refused (rc 3) | another session's precompile jobs held the lock; 15 GiB < 16 inside it |
| `k-dl1-b` | W8 ✓, C20 ✓ **135/135, DistLens 21/21 clean in 60.4 s**, C22 ✘ in (3) | (3)'s 24 `sleep 55000` proofs never reached ready in 235 s: under #70 they elaborate one after another (24 × 55 s) |
| `k-dl3` | W8 ✓, C20 ✓ 135/135 (DistLens 21/21, 57.7 s), C22 ✘ on its premise only | with `set_option Elab.async true`: 3 waves, 166.4 s, 0 probes, 0 restarts, card "Lean is still working"; `poolSaturated` false (running ≤ 21, unused ≥ 3) |
| **`k-dl5`** | **3/3** | DistLens 21/21 in 58.7 s; C20 135/135; C22 (3) 166.7 s |
| **`k-dl6`** | **3/3** | DistLens 21/21 in 64.4 s; C20 135/135; C22 (3) 166.7 s |

**C22 (3) on a sync-elaboration pin.** The case needs every Lean task thread busy. `tests/ux/specs/25-stall.spec.mjs`
now (a) opens the block with `set_option Elab.async true`, QED64 #70's documented opt-in (on a pin without #70 it
restates the server's default), (b) waits `SAT_WAVES = 3` sleeps plus 180 s (J at n = 14: 2 waves, 111 s; #69's n = 8: 3
waves), and (c) takes the queue as the premise, `editToReadyMs ≥ 2 × SAT_MS`, since with #69's budget the 24-thread
pthread pool no longer runs out (`poolSaturated` stays in the record as data). Every liveness assertion is unchanged.
Measured for QED64 (sent): even with async elaboration opted back in, 24 blocked proofs never grew the pool (J: running
26–27, unused 0).

### Gates (K)

| Run | When | Result | Evidence |
|---|---|---|---|
| `v1-smoke` | 10-12 21:19–21:33Z | 23/23; ready 14.8 s | `pinK-smoke.log` |
| `k-full1` | 21:35–21:55Z | **VERDICT** (34 passed, C19 skipped) | `pinK-ux-full1.log` |
| `k-full2` | 22:00–22:31Z | red: C4 only (below) | `pinK-ux-full2.log` |
| `k-full3` | 22:33–23:27Z (lock held by the kernel's 0039b gate until ~23:07Z) | red: C4 only | `pinK-ux-full3.log` |
| `k-c4a-b` (C4 only, the new assertion; `k-c4a` refused at 15 GiB) | 10-13 00:42–00:52Z | 1/1; tree-scope `ok` before the 3rd click, 6/7 SUPERSEDED | `pinK-ux-c4a.log` |
| `k-full5` | 00:54–01:14Z | **VERDICT** (34 passed, C19 skipped); the recorded verdict | `pinK-ux-full5.log` |
| `k-c20-1/2/3` | 01:15–01:40Z | 135/135 each (405/405), DistLens 21/21 each (57.5, 58.8, 58.8 s) | `pinK-ux-c20-{1,2,3}.log` |
| `k-headed1` (headed Chrome for Testing) | 01:41–02:02Z | **HEADED SIGN-OFF** 35/35 (C19 included) | `pinK-ux-headed1.log` |
| `k-throttle-t10p`: 10 Mbit/s / 40 ms, `throttle-proxy.mjs --listen 5298 --upstream 5297` | 02:02–02:14Z | **`RESULT PASS`**, ready at **565.1 s** (J 565.1, H 565.6); progress visible in 563 of 564 samples, error card in 0, longest unchanged progress 6.0 s; 693.3 MB at 9.8 Mbit/s | `pinK-tp-t10.log`, `pinK-tp-proxy.log` |
| `deploy-manifest --check` | 02:16Z | FAILED: `out/deploy/manifest.json` was still J's (C1: `widgets.ebd0fc1b…` vs K's `widgets.557ea1a8…`; C2 the overlay-widgets8 list). Regenerated (`generate --overlays widgets8,widgets7`: `DEPLOY-MANIFEST OK 77 assets, 95 R2 objects`), then **`DEPLOY-MANIFEST CHECK OK`**, G2 `verdict run k-full5 … on THIS gallery 1454d28e…, lock 9e041ead… and overlays widgets8, widgets7`; 95 R2 objects 2.420 GB | `pinK-dm-check.log`, `pinK-dm-generate.log`, `pinK-dm-check2.log` |
| `deploy-manifest --record-verdict` | 02:22:52Z | `infra/ux-verdict.json` names `k-full5` (gallery `1454d28e…`, lock `9e041ead…`, overlays widgets8 `21c48b5c…` and widgets7, pin `62a06e2`) | `pinK-dm-record.log` |

**C4's storm on K.** C4 clicks 8 cards 250 ms apart and required the first 7 selections to settle SUPERSEDED. Playwright's
third click has always come ~400 ms after the second (its actionability wait; `h-full4` 693 ms, `j-full1` 679 ms, every K
run ~690 ms), and K's switches are faster: tree-scope (clicked at ~285 ms) finished inside that gap in `k-full2` and
`k-full3`, a correct `ok` (the gallery settles a selection `ok` only if it is still the wanted one when its switch ends)
that the premise called a failure; `k-full1` passed by a margin. Before K the race was a rare headed flake (5 of 84 runs;
docs/UX-RESULTS.md kept the assertion strict). `tests/ux/specs/00-boot.spec.mjs` now records what the page saw: a
capture-phase click listener on the document runs synchronously before the card's own handler and reads the earlier storm
selections' outcomes at that instant; each early selection must be SUPERSEDED exactly when it was still loading as the
next click arrived, `ok` otherwise, at least 4 of 7 must be SUPERSEDED (the storm overlapped), the last `ok` and shown.
`k-c4a-b`, `k-full5` and `k-headed1` each saw tree-scope `ok` before the third click and 6/7 SUPERSEDED.

**Commit, CI mirror, deploy rehearsal.** K is committed as **`3b6c385`** on `qed64-pin-i` (a fast-forward of the live
`d60b15e`; not pushed). **CI mirror on `3b6c385`** (`node ci/run-local.mjs --workflow .github/workflows/lean-ci.yml --job
qed64-static --job packages --matrix package=dist-lens`, fresh clone, 2026-10-13 02:23–02:40Z; `$W/logs/pinK-ci-local.log`,
run dir `$W/pinK/ci-local-K1`): **qed64-static JOB SUCCESS** (the shell from source == K's lock, the Worker tests,
BUILD-GALLERY CHECK OK, SIM-GALLERY 244 ok, CHECK-GALLERY 157 ok); **packages(dist-lens) JOB SUCCESS** (`lake build`, every
test module but ClickE2E, the showcase probe), and the regenerated `showcase/dumps/dist-lens.json` is **byte-identical** to
the committed one (`721c3406…`), so the `showcase` job's DUMPS check holds for the DistLens change. **Deploy rehearsal on
`3b6c385`** (`$W/pinI/chainRHK.sh`, 02:43–04:23Z; K's rehearsal state `$W/deploy-rehearsal-K`, 95 objects 2.420 GB; run
dir `$W/pinK/rehearse-deploy-K1`, log `$W/logs/pinK-rehearse-deploy.log`): **`REHEARSE-DEPLOY OK: skip dry-run unpublished
deploy first no-verdict tamper old-shell`**; `old-shell` against the live H (`d60b15e`) measured E1 exactly as for J: order
A, the OLD shell's bare `/` stock boot FAILS in the window and the OLD gallery boots OK; order B, the CI published check
REFUSES the deploy before phase 3, and in the window the NEW gallery and the NEW shell's `/` both boot OK
(`old-shell/e1-measure.txt`). (Its old-gallery boot waited ~33 min in the lock's cooldown at 15.0–15.2 GiB reclaimable,
no one queued, then ran.)

### Not done / running (pin K, 2026-10-13 ~04:30Z)

1. **Done:** the gate (chains `$W/pinI/chainK4..8.sh`; K4–K7 were stopped by hand for the three test fixes above), the
   commit `3b6c385`, the CI mirror and the deploy rehearsal (above).
2. Nothing runs. Pushing `qed64-pin-i` deploys K (H's bare overlay objects stay; K uploads its per-runtime directories and
   the two per-build index copies, then replaces the stock indexes, decision E1).
3. The user's decisions are unchanged from J's list above (E1, the push, alias policy, stale tabs, R2 growth, kernel
   0038), plus `.env.local`'s `QED64_KERNEL_BUILD` (suggested: `$W/kernel-build-native64`).

## 2026-10-16: pins L (37ff491) and N (58ebbad), runtime wasm64-5650321f3f58aeb0 (the kernel release lean-v4.34.0-53cb11e: native Wasm exceptions + 0041) — N active and gated

*Status 2026-10-16 ~19:15Z:* **N `58ebbad` is the active pin of this checkout and fully gated** (two VERDICTs `n-full1`,
`n-full2`; C20 405/405; headed `n-headed1` 35/35; the 10 Mbit/s first visit PASS; `DEPLOY-MANIFEST CHECK OK`;
`infra/ux-verdict.json` → `n-full2`). L `37ff491` is registered as the record of the first pin on this runtime (no
VERDICT, below). K `62a06e2` stays committed and gated (`3b6c385`); its f69cca24 stores are untouched (a new runtime has
its own per-runtime stores and overlay directories). The live site still serves H `bf9d947`; nothing is pushed. Lane:
chains `$W/pinI/chainL1*.sh`, `chainL2.sh`, `chainL3.sh`, `chainN1b.sh`, `chainN2.sh`, `chainNS*.sh`; notes in
`$W/logs/pinL-chain.log` and `pinN-chain.log`.

**The runtime.** The kernel published `lean-v4.34.0-53cb11e` (digest `sha256:61628fa4…`; patch 0040, the C++ runtime on
the engine's own Wasm exception handling instead of Emscripten's JS trampolines, plus 0041, the `lean_apply_16`/
`lean_apply_m` stack fix; it replaced `64d6ebb`, which never shipped). Packs, native64 and the lists are e1a79c1's bytes;
only `runtime/`, `lean-lib` and the tools are new. QED64 adopted it in `d1646ae` (L's promote). Measured here against K
(f69cca24): w8 bake peak tree RSS 8.9 GB (16–17 GB), boot smoke 8.2 s (13.3 s), DistLens 21/21 in 41–42 s (58–64 s), C20
135/135 in 4.2 min (5.3), v1-smoke ready 9.1 s (14.8), the 10 Mbit/s first visit ready at 519.0 s (565.1 s), C10's
renderer peak 4.2 GB (10–11 GB).

**Registration (both pins by hand, from our own worktrees).** QED64's commits were fetched read-only into the submodule's
repository (`git -C deps/qed64 fetch <QED64 checkout> <full sha>`; `qed64-src.mjs ensure` fetches only from GitHub, where
`37ff491` was not yet), the page built in `$W/qed64-pins/<id>` (`npm ci --prefix frontend && npm run build:site`), the
binaries cloned into its gitignored paths: the 8 runtime chunks from the kernel release directory (its `SHA256SUMS`
11/11 OK and QED64's runtime manifest 8/8; QED64's own checkout no longer holds runtime chunks: it serves the runtime from
the shared R2 prefix), the per-build runtime manifest copy (== the tracked one), the 69 pack parts from K's release (the
pack manifests are unchanged; only `profiles/index.json`'s buildId moved) and QED64's stock `init.ecf69553…` /
`mathlib.b1ffb871…` snapz (digests == the index). `QED64_REPO=<worktree> pin-qed64.mjs pin --pin <id>`: 145 release files
(K: 147, the new runtime has 1 JS chunk instead of 3); `SHELL-FROM-SOURCE OK` 60/60; verify OK with one DRIFT (#7: the
`qed64-toolchain:emsdk-6.0.5` tag now names `208b22bcfd16`, the kernel's 0040 image; rebuild-only, no native rebuild was
needed). Stage1 and the core library came from the release's tools (`lean4-wasm64-4.34.0-53cb11e.tgz`, sha512 ==
QED64's): `cli.mjs fetch --only runtime` / `--only lean-lib` (`FETCH VERIFIED`), `unpack --slim` into
`$W/core-lib-slim.5650321f3f58aeb0` (10,074 files; tree digest `87d3af25…` == QED64's `embedding/base-tree.json`, now
recorded as `servedTrees.coreDigest`). `servedTrees.baseSlimDigest` is not recorded: the `baseSlim` path every
descriptor since I names (`${QED64_REPO}/work/bump-0035b/slim/lib-tree-slim`) is an old QED64 scratch tree that now
holds three Finder `.DS_Store` files (20,017 files against base-tree.json's 20,014; the oleans unchanged); a future
restage should point `baseSlim` at a tree unpacked from the published packs. No native rebuild, no restage (the fat and
slim base trees are byte-identical to e1a79c1's).

**Bakes etc. (L, `SHOWCASE_PIN=37ff491`, 13:55–14:58Z).** `JUDGE w7: GREEN N=5107 raw=1163620685
widgets.740686ccc783ec13.snapz` (334 s, peak 8.7 GB), `JUDGE w8: GREEN N=5684 raw=1272243125
widgets.58629e25172586e9.snapz` (334 s, peak 8.9 GB), PAIRING GREEN; overlays `widgets{7,8}.5650321f3f58aeb0/`; preflight
OK (8.3 / 8.2 s); headless controls PASS, stage 4 30/30 (DistLens E1 9/9, E3 129/129), E2 7/8 (tree-scope L1 as always;
dist-lens 71 s); record-overlays; verify OK. Two harness fixes on the way: `cmd_bake` creates the runtime's raw store
before cloning `raw/widgetsN.snap` (a new runtime's is otherwise made later, by headless controls), and the chains'
prewait now measures free+inactive (`free_inactive_gib`, what `showcase.sh`'s in-lock check uses: with speculative pages
counted the prewait passed at 16 GiB while `showcase.sh` saw 14 and refused stage 4 twice) and `gated` retries rc 3
(showcase.sh's "refused").

**L: what the gate found.** `l-dl1`/`l-dl2` (W8 + C20 + C22 + C4) 4/4 each. `l-full1` and `l-full2` red on three tests:

* **C3** (`api.status().memory` `{initialBytes 2 GiB, currentBytes null, maximumBytes null}`): a QED64 defect. The page fed
  `pageApi.memory()` only from the heap meter's 12 s `setInterval`, so the projection stayed null until the first tick;
  boots on f69cca24 took 13+ s, so C3 read after the tick, while 5650321f is ready in ~8 s. (My first diagnosis,
  `M.wasmMemory` missing, was wrong; QED64 measured it.) Fixed upstream as **HARDENING #76**: the sampler also runs on the
  relay's transition into ready (`58ebbad`, with a page-api lane assertion).
* **C10** (reload storm, "no reload of the storm waited for ready"): on 5650321f a warm reload's runtime initializes
  ~0.5 s after the commit (f69cca24 ~2.7 s) and the page is ready before 3 s, so the 0/3/6/9/12 s storm reloaded ready pages.
  C10 now reloads each page 200 ms after its `[mem] runtime-initialized` line (at most 3 s after it landed): `l-fix1`
  reloads at 0, 0.72, 1.49, 2.31, 3.10 s, each `booting`.
* **C23** (QED64-handled wedged reboot, fixture): the synthetic death fired 800 ms after arming, but the hasse-view click
  was ready in 668 ms. It now fires once the click's edit is in the document (new `clickLink` `afterEdit` hook): `l-fix1`
  recorded the reboot (`wedged`) during the click.

The C10/C23 fixes and the lock's Playwright-Firefox stray pattern (`chrome-headless-shell|ms-playwright/firefox-`, QED64
#75's Firefox lane) are `d8fe1c6`. C4's page-observed storm held on the faster switches (5 of 7 SUPERSEDED, graph-scope
and tree-scope settled before the next click).

**N `58ebbad`** = QED64 main with #74 (a lost own chunk during a deploy is a stale page), #75 (Firefox: the install no
longer waits for `navigator.storage.persist()`), #76 and the adversarial `--browser` switch; same runtime, packs,
snapshots and overlays as L (no rebake). A first registration `180b223` (the fix before QED64's rebase; the served page
byte-identical) was dropped once `58ebbad` was on GitHub. Main bundle `/assets/index-D_GaJuPp.js`; the console notify site
line 627 changed content (`fa255508…`); the allowlist still matches (every CONSOLE OK).

| Run | When | Result | Evidence |
|---|---|---|---|
| `m-t1` (on `180b223`, byte-identical page) | 16:49–16:58Z | 7/7: C3 `{2 GiB, 2 GiB, 6 GiB}` at ready, C10 every reload `booting` (renderer peak 4.24 GB), C23 reboot recorded, DistLens 21/21 in 41.4 s | `pinM-ux-t1.log` |
| `n-t1` (C3, C4, C10, C23, W8, C20, C22) | 17:09–17:18Z | 7/7 | `pinN-ux-t1.log` |
| `v1-smoke` | 17:19–17:22Z | 21/23: at the FIRST ready QED64's liveness projection was still empty (`probeAfterMs` null, `status().qed64.liveness` absent) | `pinN-smoke.log` |
| smoke A/B (N, L via `SHOWCASE_PIN`, N) | 17:23–17:30Z | 23/23 each (`lastFrameAgoMs` 51–81, `probeAfterMs` 6000) | `out/ux/v1-smoke.{N1,L1,N2}` |
| `n-full1` | 17:32–17:47Z | **VERDICT** (34 passed, C19 skipped; 14.8 min) | `pinN-ux-full1.log` |
| `n-full2` | 17:49–18:04Z | **VERDICT**; the recorded verdict | `pinN-ux-full2.log` |
| `n-c20-1/2/3` | 18:04–18:23Z | 135/135 each (405/405), 4.2–4.3 min | `pinN-ux-c20-{1,2,3}.log` |
| `v1-smoke` (the liveness read waits for the projection) | 18:24–18:26Z | 23/23; the projection present 2 ms after ready | `out/ux/v1-smoke.N3` |
| `n-headed1` | 18:28–18:44Z | **HEADED SIGN-OFF** 35/35 (C19 included) | `pinN-ux-headed1.log` |
| `n-throttle-t10p` (10 Mbit/s / 40 ms) | 18:57–19:06Z | **`RESULT PASS`**, ready at **519.0 s**; progress visible in 517 of 518 samples, error card in 0, longest unchanged progress 6.0 s; 640.9 MB at 9.9 Mbit/s | `pinN-tp-t10.log` |
| `deploy-manifest --check` / `--record-verdict` | 19:09–19:12Z | `DEPLOY-MANIFEST CHECK OK`, G2 `verdict run n-full2 … on THIS gallery bf85fcb5…, lock 0be2db46…`; 77 assets 17.8 MiB, **93 R2 objects 2.368 GB**; `infra/ux-verdict.json` → `n-full2` | `pinN-dm-check.log`, `pinN-dm-record.log` |

**The smoke's liveness read.** QED64's `status().liveness` is null until the page has seen the worker's first liveness
counters (EMBEDDING: `liveness: LivenessInfo | null`, null until the session's loop is open), which can land a tick after
the first ready status (1 smoke in 3 on `58ebbad`, a pre-existing race per QED64). `tests/ux/tools/v1-smoke.mjs` now
reads the two checks that need it once it is present (at most 10 s after ready) and records the delay.

### Not done (pins L/N, 2026-10-16 ~19:15Z)

1. The commit (`pins/58ebbad/`, `pins/37ff491/`, the active pin state, `infra/ux-verdict.json`, the smoke change, these
   docs), then the qed64-static CI mirror on it and the deploy rehearsal (a new rehearsal state: runtime 5650321f,
   93 objects; `old-shell` against the live H).
2. The user's decisions: the push (it would deploy N; R2 gains runtime 5650321f's per-runtime overlay directories and
   the stock objects), and the E1 upload order. Whether kernel patch 0038 is still wanted after 0040/0041 is the kernel
   session's question, not this log's.

## 2026-10-27: pin O (521cf3f / wasm64-36d7f415704473d9, QED64 main) — Lean 4.35.0: the kernel release lean-v4.35.0-b081e7c, the widgets ported to 4.35

*Status 2026-10-27 ~23:10Z:* **O `521cf3f` is the active pin of this checkout and fully gated** (headless
`CONTROLS PASS`, stage4 and E2 green; two VERDICTs `o-full1`, `o-full2`; C20 405/405; headed `o-headed4` 35/35; the
10 Mbit/s first visit PASS at 513.9 s; `DEPLOY-MANIFEST CHECK OK`; `infra/ux-verdict.json` → `o-full2`). Not pushed, not
deployed: the live site serves H `bf9d947`. N `58ebbad` stays registered (its stores intact); I and J are retired.

**What moved.** QED64 `521cf3f` (main) adopts the kernel release `lean-v4.35.0-b081e7c` (digest `sha256:5450ccc0…`,
kernel patch 0042) in its promote `add01f8`, with HARDENING #77–#81 over N: Lean **4.35.0**, Mathlib `56a00585`,
ProofWidgets `df72b022`, runtime `wasm64-36d7f415704473d9`, toolchain image `qed64-toolchain:emsdk-6.0.5`
`9563286ca922` (from the release record's `docker.imageId`). Unlike every earlier re-pin, the Lean version changes,
so the widgets were ported first: the nine packages build and test on Lean 4.35.0 / Mathlib v4.35.0
(`1a61003`, `WIDGETS_COMMIT`; test-all GREEN 9/9; `WIDGETS_SOURCE_HASH` `4a1f4902…`, 232 files). The port's
gotchas are in `packages/*/PORT-NOTES.md`; the user-visible changes are DistLens's example header
(`lean/examples/dist-lens.lean` line 14: `open PMF DistLens`) and the graph-scope example's doc comment and card blurb
(its components link is now offered only when the calibrated cost model fits).

**Harness changes the new Lean version needed.**

* The stock Lean toolchain (`TC`) is derived from the target pin's runtime `leanVersion` instead of a fixed v4.34
  path, and the Mathlib clone is per Mathlib commit (`MATHLIB_CLONE=$W/mathlib4.<8 hex of the lock's mathlib commit>`;
  4.34 keeps the legacy `$W/mathlib4`). Explicit env vars still beat `.env.local`.
* `pin-qed64.mjs`: the docker image id comes from the release record, the release's `.so` hashes are checked, the
  record is cross-checked against the pin, and `pin` refuses without `QED64_KERNEL_BUILD`.
* `stage-trees.mjs` stages and G0-checks the fat base tree too (`baseFatDigest`); the native goldens' Essential count
  comes from `$K/mathlib/essential-modules.txt`.
* The headless lane reads the resident worker's argv from the pin's `public/workers/lean.worker.js`
  (`RESIDENT_ARGV`), never a copy.
* The native delta lists were regenerated: phase 1 38 modules (two Mathlib renames: `Data.Fin.SuccPredOrder` →
  `Order.SuccPred.Fin`, `Data.Setoid.Partition` → `Order.Setoid.Partition`), phase 2 404.

**Registration (by hand, from our own worktree).** `$W/qed64-pins/521cf3f`; page built from source; binaries cloned
into its gitignored paths and checked against its tracked manifests (a by-hand script, `stage-pin-binaries.py`, kept in the session's scratch directory and not committed: the runtime chunks from
the kernel release directory, the per-build runtime manifest, the 69 pack parts, QED64's stock snapz).
`pin-qed64.mjs pin --pin 521cf3f`: 145 release files; main bundle `/assets/index-BcCr_hPg.js`; console notify site
line 627 with new content (`47afccc…`). `servedTrees`: core `d42722f8…` (10,175 files), slim base `58113bce…`
(20,365), fat base `a33a51a8…` (25,456), baseN 5092.

**Heavy path (`SHOWCASE_PIN=521cf3f`, its own runtime stores; N stays active, but the shared staged trees `$W/tree-*`,
`out/native-build.json` and the goldens are now O's).**

| Step | Result |
|---|---|
| goldens (`lean/goldens/`) | REQUIRED-GATES PASS; CLICK-ALL GATE PASS: 135 links (129 MakeEditLink + 6 Try-this), clean 135, all 15 env runs broken 0; 31 goldens regenerated (`lean/expect/**`) |
| native | widgets header gate 64/64 modules; DistLens closure 413 modules (1,221 files) PASS; reuse gate 0 new oleans |
| stage | G0–G6 OK: `tree-slim-w7` 5,195, `tree-slim-w8` 5,758, `tree-fat` 5,759 |
| bake w7 | `JUDGE w7: GREEN N=5195 raw=1151111821 widgets.4f02caae6eb88d1d.snapz` (335 s, peak tree RSS 8.43 GiB) |
| bake w8 | `JUDGE w8: GREEN N=5758 raw=1255464357 widgets.37b2f0a943e8307c.snapz` (337 s, peak 8.68 GiB); PAIRING GREEN both |
| preflight | `PREFLIGHT OK buildId=wasm64-36d7f415704473d9` for widgets7 and widgets8 (boot smoke 8.3 s each) |
| headless | `CONTROLS PASS` 11/11 (chain 2, 48 s); stage4 `0 failing`: E1 8/8 + 7/7, E3 1167/1167 (w8) + 1038/1038 (w7), E3b 49/49 + 44/44; E2 7/8, tree-scope `Demo.lean:104` on L1 (root-caused; native 4.35 builds that Demo); gate `stage4Green`, `E2Green` (headless floor 12 GiB, the user's call 2026-10-27) |
| record-overlays, verify | `RECORDED overlays widgets7 … widgets8 …`; `pin-qed64.mjs verify --pin 521cf3f` VERIFY OK (62 OK, #7 docker included); `pin-switch check 521cf3f --full` PIN CHECK OK |
| switch | `showcase.sh pin use 521cf3f`: PIN CURRENT OK; `showcase.sh gallery` GREEN on `047aa584…` (examples.json regenerated for the dist-lens/graph-scope edits); `showcase.sh verify` all checks OK (I/J RETIRED); `deploy-manifest generate --overlays widgets8,widgets7` OK, 77 assets / 93 R2 objects |

**Browser gate (pin O active, `SHOWCASE_LANE=pinO`, floor 16 GiB; gallery `047aa584…`).**

| Run | When | Result | Evidence |
|---|---|---|---|
| thumbnails (`bringup/widgets.mjs --thumbs`) | 19:14Z | WIDGETS OK 8/8, THUMBS OK 8/8; all eight PNGs **byte-identical** to the 2026-10-01 set, so `thumbs.json`'s new `madeAt`/`run` were reverted (gallery hash unchanged) | `pinO-thumbs.log` |
| X4 (`tests/experiments/x4-click-paths.mjs`) | 19:19–19:20Z | `pass`; **D1 and D2 no longer reproduce on the plain stock page**: `a:raw` core Try-this applies in 102 ms, `b:raw` the `conv?` panel renders and Generate-conv applies in 101 ms (on 1859b83/9fdf9b8 both were BROKEN); bridge modes work; `b:strip` (bridge with edits off) does not apply. The verdict rule `makeEditLinkStockApplyEdit` read `b:strip` only and said BROKEN; it now reads `b:raw` once its panel renders | `out/experiments/x4.json`, previous `$W/logs/x4.before-pinO.json` |
| `o-c13` (`--grep C13`) | 19:22Z | 2/3: `C13-gallery-graph-scope.png` differed, every changed pixel in the editor's doc-comment lines 4–13 and the card blurb (this re-pin's graph-scope edit); re-approved | `pinO-ux-c13.log` |
| `o-c13b` | 19:26–19:27Z | 3/3 | `pinO-ux-c13b.log` |
| `o-t1` (C3, C4, C10, C23, W8, C20, C22) | 19:29–19:37Z | 7/7; C10 storm peak renderer 4.45 GB, `panelEqual`; the gallery on embedding v1 (`editorRpc`, `widgetSourceCache`: bridge stood down) | `pinO-ux-t1.log` |
| `v1-smoke` | 19:39–19:40Z | 23/23, ready 9.6 s | `out/ux/v1-smoke.O1` |
| `o-full1` | 19:42–19:57Z | **VERDICT** (34 passed, C19 skipped; 15.1 min) | `pinO-ux-full1.log` |
| `o-full2` | 19:59–20:14Z | **VERDICT**; the recorded verdict | `pinO-ux-full2.log` |
| `o-c20-1/2/3` | 20:16–20:33Z | 135/135 each (405/405), 4.2–4.3 min | `pinO-ux-c20-{1,2,3}.log` |
| `o-headed1..3` | 20:35–21:26Z | 34/35 each: C13a, the HEADED baseline `headed/C13-gallery-graph-scope.png` (not re-approved with the headless one; the three captures byte-identical, the same two regions); re-approved | `pinO-ux-headed{1,2,3}.log` |
| `o-headed4` | 21:29–21:45Z | **HEADED SIGN-OFF** 35/35 (C19 included) | `pinO-ux-headed4.log` |
| `o-throttle-t10p` (10 Mbit/s / 40 ms) | 21:47–21:56Z | **`RESULT PASS`**, ready at **513.9 s** (N 519.0 s); progress visible in 512 of 513 samples, error card in 0, longest unchanged progress 6.0 s; 635.8 MB at 9.9 Mbit/s | `pinO-tp-t10.log` |
| `deploy-manifest generate` / `--check` / `--record-verdict` | 21:56–22:01Z | `DEPLOY-MANIFEST CHECK OK`, G2 `verdict run o-full2 … on THIS gallery 047aa584…, lock ffb9bb09…`; 77 assets, 93 R2 objects; `infra/ux-verdict.json` → `o-full2` | `pinO-dm-*.log` |

**Incidents.**

* *A node exit deadlock held the headless lane for 2 h 16 min.* The control `e-e1-flipped-index` printed its expected
  verdict (E1 FAIL, exit 1 wanted) and then hung in `process.exit`: the main thread joined a V8 background baseline
  compiler job that was waiting for a GC only the main thread could run (`sample`: `DisposePlatform` →
  `WorkerThreadsTaskRunner::Shutdown` → `uv_thread_join`, the worker in `CollectionBarrier::AwaitCollectionBackground`;
  node 26.3.0). Killed by PID; `run-controls.sh` now runs each control under `CONTROL_LIMIT_S` (default 900 s; each
  takes seconds), so a hang costs minutes.
* *`showcase.sh verify` had been red since K.* L and N gated on `pin-qed64.mjs verify` + `pin check --full`, so two
  things went unseen: (1) cleanup round 1 (2026-10-25) trashed ten registered pins' QED64 worktrees, whose source
  checks then fail; recreated with `qed64-src.mjs ensure` (sources only, ≈20 MB each); (2) pins I `385a1ac` and J
  `5e63edd` cannot be switched to any more: K rebaked the f69cca24 overlay store they share for K's widgets
  (`widgets.557ea1a8…`, `WIDGETS_COMMIT 6b31bba`, 2026-10-12), replacing their `widgets.ebd0fc1b…` (`90e415c`). New
  optional `pin.json` field `"retired"`: `pin-switch check --if-materialized` reports such a pin as `RETIRED` (exit 0)
  and `pin use` refuses it; I and J carry it.
* *The host lock (`with-browser-lock.sh`), eight rounds of fixes with adversarial verification (`78306aa`).* Two pin O
  lanes sat in a FIFO that a waiter could overtake, and a takeover paused between its read and its check could remove the
  next owner's live lock. Now: FIFO tickets that a waiter without a ps start time re-files at every poll; a takeover
  (`TAKEOVER_PL`) that decides staleness under a flock plus the old directory and removes the lock only if it is unchanged
  (dev, inode, line); a release (`RELEASE_PL`) that checks and unlinks in one process while the wrapper is its parent;
  every catchable terminating signal except the synchronous faults (SEGV, BUS, ILL, FPE) and the real-time signals
  trapped once the lock is held (an untrapped HUP/USR1/ABRT released it while the
  command ran on). What remains is in the script's header limits (1)–(6): SIGKILL or an untrapped fault of the wrapper alone, pid reuse,
  and what older copies of the script can still do. `tests/ux/bringup/lockfifo.sh` (fault and takeover cases, each failing on
  the mutant it was written for) and `lockrace.sh`.
* *Two memory meters.* The user lowered the headless floor to 12 GiB (2026-10-27). The chain's prewait read
  `reclaimable_gib` (free + inactive + speculative, rounded: 13), the in-lock guard `free_inactive_gib` (no speculative
  pages, truncated: 11), so stage4 was refused inside the lock after the prewait passed. The chain now waits on the guard's
  figure; the two differ by up to 2 GiB on this host (0–2 in the chain log, usually 1). The browser lanes kept 16 GiB.
* *Docker Desktop's engine was down with the app up* (API 500, no VM process): `docker desktop restart`, then `pin-qed64.mjs
  verify --pin 521cf3f` passed #7.

**The review of this re-pin's harness changes, and what it changed.** An adversarial review of the uncommitted pin O
diff (five dimensions, each finding verified by a second agent; read-only) confirmed 15 of 18 findings, one high: the
staged trees `$W/tree-slim-w7|w8` and `$W/tree-fat` (and the controls' `$W/tree-stock`) are shared by every pin with no
record of whom they were staged for. O is the first pin whose base trees and module counts differ (K's restage changed only widget oleans, at the same N, and J's trees were backed up by hand), so after O's stage a `showcase.sh all` for N
would have skipped stage, seen a red judge and let `bake.sh` delete N's green bake before baking N's runtime against O's
4.35 tree. The fixes (a 29-file patch, three verify rounds per group, then a fresh three-lens review of the whole patch:
9 findings, 6 confirmed and fixed; tests on macOS bash 3.2 and Linux bash 5.2 in the local `node:26-bookworm` image):

* each staged tree carries `<tree>.STAGED.json` (pin, runtime, served base, `WIDGETS_SOURCE_HASH`, EXPECTED-N), written
  only after every gate passed; `bake.sh` (before anything is deleted), `judge-bake.mjs`, headless stage4/e2,
  `hang-repro.mjs` and `all` refuse a tree whose record is not the target pin's (`stage-trees.mjs --check-provenance`);
  `all` restages instead of baking; `$W/tree-stock` gets a `.SOURCE.json` sidecar (`--stock-copy`);
* stage's new N0 gate: the clone, the kernel build and the native build record (`out/native-build.json`, plus a per-clone
  `.lake/showcase-native-build.json`) must be the target pin's, re-checked before the record is written;
* `QED64_KERNEL_BUILD` may be a `:` list; the env layer picks the target pin's build like TC and `MATHLIB_CLONE`, and
  `verify` says N/A for a build of another release instead of FAIL; a TC whose Lean differs from the packages'
  `lean-toolchain` is refused; no silent v4.34 TC fallback for a non-legacy pin; golden envs carry a `BUILT-FROM` stamp;
  `verify` and `pin use` name the `$W/widgets-src` restore command; the deploy guide states the E1 pack-manifest hazard.

Applied 22:21Z with nothing running. After it, on pin O: `stage all --force` restaged the three trees with records and
**byte-identical** content (a sha256 over every file, before and after), `judge-bake w7|w8` GREEN on the same `.snapz`, the
golden envs rebuilt with stamps, `tree-stock.SOURCE.json` backfilled after G0, `verify`, `pin check --full` and
`deploy-manifest --check` OK. A consequence: an older pin cannot be restaged on this branch (its native delta lists are
O's), so restaging N needs N's branch; serving or rolling back to N is unaffected (its overlay stores are intact).

**The node exit deadlock, root-caused.** The first post-patch controls run hung again on `e-e1-flipped-index` (the
900 s bound ended it: `CONTROLS FAIL`, `neg-got-142`). `sample` showed the same two stacks as in chain 1: the main thread
in `node::DisposePlatform` → `WorkerThreadsTaskRunner::Shutdown` → `uv_thread_join`, the joined thread V8's
`ConcurrentBaselineCompiler` (Sparkplug) in `CollectionBarrier::AwaitCollectionBackground`. The control alone, 30 runs
each: plain `node` hung in **14 of 30**, `node --no-concurrent-sparkplug` in **0 of 30**. `scripts/lib/platform.sh`
`NODE_TOOL` now runs the headless tools that way (run-controls, run-stage4); the 900 s bound stays as the backstop.
Then: controls ×3 `CONTROLS PASS` (49 s, 44 s, 44 s), stage4 `0 failing` through the patched runner (22:51–22:55Z), E2 7/8 on L1 (22:55–23:04Z), and the
summary's gate `stage4Green`, `E2Green` (`$W/logs/pinO-pf2-*.log`).

**CI mirror and deploy rehearsal on `9eed0e9`** (`$W/pinI/chainRHO.sh`, 2026-10-27 23:27Z – 10-28 00:50Z, fresh
clones, local fakes only). **qed64-static** (`node ci/run-local.mjs --workflow .github/workflows/lean-ci.yml --job
qed64-static`, `$W/logs/pinO-ci-local.log`): **JOB SUCCESS**, 12/12 steps, among them QED64's page built from source
byte-identical to O's lock (60/60 files), the Worker tests, CHECK-GALLERY OK 157 and SIM-GALLERY OK 244. **O's
rehearsal state** (`$W/deploy-rehearsal-O`, `$W/logs/pinO-rh-state.log`): `UPLOAD OK` in three phases, `FAKE-BUCKET OK:
93 objects`, `LOAD-R2 OK: 93 objects, 2.367 GB`; the upload printed the `E1 HAZARD` line for both pack manifests.
**`ci/rehearse-deploy.sh`** (run dir `$W/pinO/rehearse-deploy-O1`, `$W/logs/pinO-rehearse-deploy.log`):
**`REHEARSE-DEPLOY OK: skip dry-run unpublished deploy first no-verdict tamper old-shell`** (tamper on
`/snapshots/widgets8.36d7f415704473d9/index.json`). **`old-shell` against the live H** (`d60b15e`, OLD_STATE the live
objects, E's 93) measured E1 (`old-shell/e1-measure.txt`, `old-shell/pack-fetches.txt`):

* phases 1–2 under the live shell: H's published check OK without the replaced keys, `REPLACED-KEYS OK 3` (the runtime
  manifest, as at J and K, and **both pack manifests, each an E1 HAZARD**: `/profiles/lean-core.manifest.json` now
  serves O's release `lean-core-4.35.0-wasm64-36d7f415704473d9`, `/profiles/mathlib-essential.manifest.json` O's
  `mathlib-essential-56a0058-wasm64-36d7f415704473d9`); the 6 bare `snapshots/widgets{7,8}/` objects untouched;
* in that window **H's boots fetch O's pack**: the old gallery and the old bare `/` stock page each fetched the new
  `lean-core.manifest.json` and 8 pack parts, all 8 of O's release, none of H's. Both still booted (stock ready in
  13 s; the gallery's HasseView panel rendered), because a boot elaborates from its own snapshot. What H's 4.34 runtime
  does when it later reads one of those 4.35 oleans (an import outside the snapshot, "Load exact imports") was not
  measured; QED64's #81 says such oleans are misread (the olean githash gate is compiled off);
* **order A** (phase 3 before the deploy): as at J and K, H's bare `/` stock boot FAILS in the window (the replaced
  `snapshots/index.json` and `profiles/index.json`; `bootFailed`, halted after 420 s), the old gallery boots OK; then
  the new workflow (published check, deploy, smoke) succeeds and the new gallery and stock boots are OK;
* **order B** (phase 3 after the deploy): the CI published check refuses the deploy before phase 3 (rc 1), as at J and
  K; a Worker deployed without it now **fails its smoke** before phase 3: `HEAD /profiles/index.json — content-length
  514 != 513`. H's (and every earlier pin's) `profiles/index.json` is 514 B and O's 513 B; at J and K the old and new
  index had the same length, so the smoke, which until `dbacd2c` compared only the size of a mutable object, passed on the
stale index.
  `snapshots/index.json` is 701 B in both H and O, so the smoke of `9eed0e9` passed it in the window; the smoke now
  also GETs every manifest and index and compares its sha256 (DEPLOY-CLOUDFLARE 3.4), so it fails there too. In the window the new
  gallery and the new shell's `/` stock boot are OK (#64's per-build copies), and after phase 3 the published check and
  the smoke are OK.

So the gallery still boots in the window in either order (it has no index window), but every boot of an H page, the
gallery's included, between phase 2 and the deploy now fetches O's pack (E1, DEPLOY-CLOUDFLARE 3.2), and a split
deploy must run the smoke after phase 3.

**Rerun on `dbacd2c`** (the smoke's GET sha256 of every manifest and index; `$W/pinI/chainRHO2.sh`, 2026-10-28
01:10–02:34Z, fresh clones, local fakes only). qed64-static **JOB SUCCESS** 12/12 (`$W/logs/pinO-ci-local2.log`: 60/60
byte-identical, CHECK-GALLERY OK 157, SIM-GALLERY OK 244, the Worker tests 27/27 with the new one, "an index of the
manifest's size with other bytes FAILS"); O's rehearsal state rebuilt (`pinO-rh-state2.log`: `FAKE-BUCKET OK: 93
objects`, `LOAD-R2 OK: 93 objects, 2.367 GB`); **`REHEARSE-DEPLOY OK: skip dry-run unpublished deploy first no-verdict
tamper old-shell`** (`pinO-rehearse-deploy2.log`, run dir `$W/pinO/rehearse-deploy-O2`). `old-shell/e1-measure.txt` is
the one above line for line (only the run dir differs). What changed is order B's smoke before phase 3, which now fails
on both indexes (`old-shell-B-new.log`): `FAIL GET /profiles/index.json — published 514 B … != manifest 513 B …` and
`FAIL GET /snapshots/index.json — published 701 B sha256 12c670a3b176e981… != manifest 701 B 52fc2caa68ea856e… (not
this release's upload)`, "8/10 manifests and indexes GET with the manifest's sha256; 2 bad". The second is the stale
index the size-only smoke of `9eed0e9` had passed.

**`b939b10`** (the two follow-ups of the `dbacd2c` review): after a split deploy (`ALLOW_PARTIAL_UPLOAD=1`, order B)
`scripts/deploy-app.sh` records the missing phases in `out/deploy/record-gap.txt`, and its last line names them first:
`DEPLOYED (split upload). Next: PHASES=3-indexes scripts/upload-artifacts.sh, then node scripts/deploy-manifest.mjs …
--smoke … (until then the smoke fails on the old indexes: not this release's upload)`. A full deploy prints the line it
printed before, and so does CI (`DEPLOY_FROM_LOCK=1` skips the record check, so no gap is recorded). The workflow's
header and its smoke step name now mention the sha256 (the new name still matches `ci/rehearse-deploy.sh`'s
`step N SUCCESS.*Smoke` check, the only other reader of it). `bash -n`, the Worker tests 27/27, `check-portable` and
`showcase.sh verify` OK; `ci/rehearse-deploy.sh dry-run deploy first` on `b939b10` (`$W/logs/pinO-rehearse-deploy3.log`,
run dir `$W/pinO/rehearse-deploy-O3`, 02:35–02:53Z): **`REHEARSE-DEPLOY OK: dry-run deploy first`**, the deploy printing
`DEPLOYED. Next: node scripts/deploy-manifest.mjs --out out/deploy --smoke http://127.0.0.1:8792 --all --range`. No
rehearsal scenario deploys with `ALLOW_PARTIAL_UPLOAD=1`, so the split line was checked on a copy of the script's tail
(gap, no gap and no URL each print the expected line; the record check's new write line, given the gap `3-indexes`,
writes `3-indexes`).

### Not done (pin O, 2026-10-28 ~03:00Z)

1. Committed on `port-lean-4.35` (not pushed): the Lean 4.35 port `1a61003`, the host lock `78306aa`, the control bound `61ed105`, the I/J retirement
   `5660c6d`, O's harness `07d015b`, the review fixes and `NODE_TOOL` `0ab384a`, pin O itself `546d110`, the docs
   `9eed0e9`, the rehearsal record `6330f6d`, the smoke's sha256 `dbacd2c` (the smoke-fix session), its follow-ups
   `b939b10`, and this record. Done since: the qed64-static CI mirror and the deploy rehearsal on `9eed0e9`, rerun on
   `dbacd2c`, and the deploy scenarios on `b939b10` (above).
2. The user's decisions: the push (it deploys O over H; or N first); E1, now including the pack manifests (above and
   docs/DEPLOY-CLOUDFLARE.md 3.2; a question to QED64 about per-release manifest URLs is drafted in docs/UPSTREAM-REPORT-QED64.md, last section, for the user to relay); `.env.local`'s `QED64_KERNEL_BUILD`
   (it names a deleted dir; suggested the list `$HOME/code/qed64-showcase-work/kernel-build-native64-v4.35:$HOME/code/qed64-showcase-work/kernel-build-native64`; `.env.local` expands `$HOME`, not `$W`);
   alias policy and stale tabs as for I; whether to keep N's and H's build stores.
3. Follow-up: per-runtime trees and native records (docs/NEXT-STEPS.md, pin O, item 3).
