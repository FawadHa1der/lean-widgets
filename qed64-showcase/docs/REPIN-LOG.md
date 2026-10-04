# Re-pin log

One entry per change of the QED64 pin. Each entry says what the pin moved from and to, how the procedure in README.md
"Re-pin" was actually executed, the evidence for each gate, and how to switch back.

**Where it stands:** printed by `scripts/showcase.sh pin current` / `pin list` and `showcase.sh verify`, not written
here. *History (dated):* five pins registered, all with complete stores. The sequence of served pins: A `1859b83`
(first build) → B `9fdf9b8` (2026-10-01, QED64's L7 fix; L9 V1) → C `5ac5d00` (multi-pin lane, with the rehearsed
switches C→A→C→A→C→B→C) → D `3b42714` (2026-10-02 17:35–19:26Z, final gate) → C (19:26Z, final gate: D's reload storms
were not cleaner than C's) → **E `33b0967`** (2026-10-04 05:18Z, pin-e lane: its storms were at least as clean as C's;
gated while served, below). D stays staged; QED64 has not handed over `3b42714`.

Current verdict and sign-off counts per pin: `scripts/showcase.sh pin list` (this table's "Browser gates" column is
dated history: as of the final gate, 2026-10-02, and for E as of the pin-e lane, 2026-10-04).

| Pin | Runtime | Registered by | Browser gates (history, 2026-10-02) | Status |
|---|---|---|---|---|
| A `1859b83` | `wasm64-4b025db7729c5f89` (0034) | first build; re-keyed by the multi-pin lane | VERDICT `closeout-full1` (old gallery); C21 + C22 green with the hardening gallery code (`harden-A-c21c22`, gallery `894b9c51…`, own port); no full suite since | staged fallback |
| B `9fdf9b8` | `wasm64-2c18773ecfba45bb` (0035) | 2026-10-01 re-pin | 1 VERDICT, 6 red full runs, all on L9 V1 | evidence only, do not deploy |
| C `5ac5d00` | `wasm64-4b025db7729c5f89` (0034, #52 worker) | multi-pin lane | by the end of the final gate: 7 VERDICTs, the last two `final-C-full1/2` on `2081098d…`; headed sign-off `final-C-headed1` | served until 2026-10-04 05:18Z; staged since (the fallback) |
| D `3b42714` | `wasm64-3ab1c6a9da03bc29` (0035b) | pin D lane (stores without switching) | VERDICT `final-D-full1/2` on `eab4f147…`; headed sign-off `final-D-headed2`; storms V2 3/26 vs C 2/26 | staged, ready |
| E `33b0967` | `wasm64-3ab1c6a9da03bc29` (D's runtime and stores; #55 lifetime-lock worker, #54 boot card) | pinE lane, 2026-10-04 (below) | pin-e lane, 2026-10-04: storms on `/showcase/#hasse-view` E 0/20 vs C 0/20 headed, 0/8 vs 1/8 headless-shell; VERDICT `pinE-full1/2` and headed sign-off `pinE-headed1` on `bbdbc932…`; 10 Mbit/s first visit PASS | served since 2026-10-04 (current state: `pin current`) |

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
  lake test` of `packages/simp-lens` passed in the clone with the stock toolchain (`clone-lake-simp-lens.log`). The full
  UX run in the clone: see "UX" below.
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
