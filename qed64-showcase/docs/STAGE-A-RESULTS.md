# Stage A results (pin + experiments, native64 build, examples) — 2026-09-30

All three lanes passed their gates and an adversarial audit (round 1, minors only).
The full lane reports follow verbatim. Key facts for later stages:

- **QED64 pin**: commit 1859b83, runtime wasm64-4b025db7729c5f89; vendored files in vendor/qed64
  (QED64-PIN), release clone in release/wasm64-4b025db7729c5f89 (cp -c), `scripts/pin-qed64.mjs verify`.
- **Local server**: scripts/serve.mjs on :5190 (serve-start.sh / serve-stop.sh); overlays under
  out/overlay/snapshots/<dir>/ are served at /snapshots/<dir>/.
- **Two defects in QED64's shipped page** (found by X4, fixed from outside by gallery/qed64-bridge.js):
  D1: every `mk_rpc_widget%` panel fails with "Unrecognised error … abortSignal.addEventListener is not a
  function" (lean4monaco passes the raw RPC proxy; abortSignal is JSON-serialised to {}).
  D2: applyEdit/showDocument from the InfoView throw `unsupported` (no editor-service override), so
  Try-this and MakeEditLink clicks never change the text. The bridge strips abortSignal and applies
  edits/showDocument/insertText directly on qed64.editor. Installing it from a parent onto
  iframe.contentWindow was confirmed by the auditor. Without the bridge, NO RPC widget panel renders.
- Stock page noise: one pageerror `Error: unsupported` from `$onExtensionActivationError` and one empty
  console.error on every boot, with or without the bridge — allowlist exactly these in console oracles.
- Memory knob: wrapping qed64.relay.makeSession changes initialBytes for the NEXT session (X5: 2 GiB→3 GiB
  after relay.restart). Stock region bytes 1,249,636,802 incl. init.
- Native build: /Users/fawadhaider/code/qed64-showcase-work/mathlib4 (APFS clone) holds all 512 newly compiled modules (38 phase-1 delta,
  402 phase-2 delta, 72 widget/LeanWidgetKit). Widget modules are legacy files: lib/lean has only
  .olean/.ilean (no .ir facet; IR is inside the olean). Header gate green; 0 GMP oleans in the closure.
- Examples: lean/examples/<pkg>.lean + .json specs; goldens lean/expect/<pkg>.json produced by
  lean/goldens/lsp-golden.mjs against a native superset env (golden-env.sh). Env-dependent fields:
  htmlSha256 of MakeEditLink panels, uri/version, selection mvarIds. Core Try-this in v4.34 renders as
  `[apply]` (message widget), GraphScope edge links have empty text (find by title).
- Known example issue: interval-inspector's rendered union/hx `refine` links break the file when clicked.


---

# pin-experiments gatePassed=True

## deliverables
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/scripts/pin-qed64.mjs (pin | verify; Node, no deps)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/QED64.lock.json (145 release files with sha256, git-blob anchors, toolchain pins; keeps keys owned by other stages such as WIDGETS_SOURCE_HASH)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/QED64-PIN (sha256 of the 24 vendored files)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/vendor/qed64/ (git archive 1859b83 of the S0.3 path list)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/release/wasm64-4b025db7729c5f89/{dist,public} (cp -c clones, nlink 1)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/scripts/assert-untouched.sh (stamp|check [NAME]; uses git --no-optional-locks)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/scripts/serve.mjs (§7.1; port 5190 / PORT; listens on 127.0.0.1 and ::1; ETag/304; CHAOS knob)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/scripts/serve-start.sh and scripts/serve-stop.sh (pid in out/serve.pid, log in work/logs/serve-<port>.log)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/package.json + package-lock.json (@playwright/test exact 1.62.1, installed)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/tests/experiments/{lib.mjs,x1-preflight.mjs,x2-rehearsal.mjs,x3-gallery-skeleton.mjs,x4-click-paths.mjs,x4-debug.mjs,x5-memory-knob.mjs}
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/gallery/x3.html (M2 skeleton, served at /showcase/x3.html)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/gallery/qed64-bridge.js (same-origin fix for the two InfoView RPC defects X4 found; required by M1/M2)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/tests/ux/selectors.json (frozen by X4)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/out/experiments/{x1.json,x1-snapshots-rehearsal.json,x2.json,x3.json,x3.png,x4.json,x4-debug.json,x4/*.png,x5.json}
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/out/overlay/snapshots/rehearsal/ (cp -c clones of the stock init and mathlib snapz, plus a copy of the stock index)
- Logs: /Users/fawadhaider/code/qed64-showcase-work/logs/{s0-pin,s0-verify,s0-verify-final,s0-npm-install,s0-untouched,x1,x1-rehearsal,x2,x3,x4*,x5,serve-5190}.log

## evidence
- S0.2: `pin` printed `S0.2 OK  QED64 HEAD=1859b830b3621dbacc1752a818634d06a1c94bd0 clean`, then `S0.3 OK  vendored 24 files`, `S0.4 OK  cloned 145 files (1.676 GB logical)`, and `PIN DONE` (rc=0).
- pin-qed64 verify (final, rc=0): 37 OK lines, 1 SKIP, `VERIFY OK`. The checks: #1 five tracked JSON files equal `git show QPIN:` byte for byte. #2 the per-build manifest is identical to the tracked one. #3 `reassembled lean.wasm sha256 == manifest — 4b025db7729c5f89d686b5cc… 109872982 B`. #4 core has 8 parts and essential has 61; the concatenated transport digests match (1013406798 B). #5 both snapz match their digests. #6 the release set matches the lock (145 files), nothing is a hard link, and `bundle buildIds in dist/assets/*.js == {wasm64-4b025db7729c5f89}`. #7 NATIVE-COMMIT 857544b439, BUILT-COMMIT 8d91aadcda, the lean and lake sha256s, docker id 8b6698bbf474, Mathlib 5ed2965, ProofWidgets 106ff4f, node v26.3.0, `@playwright/test exact 1.62.1`, `browser revision 1234 (chromium@1234, chromium-headless-shell@1234) and cached`. #8 vendor re-hashes to QED64-PIN, and its git blob ids equal `git ls-tree 1859b83` (24 entries).
- Playwright: in node_modules/playwright-core/browsers.json, chromium and chromium-headless-shell are both revision 1234 (151.0.7922.34). 1.62.1 maps to rev 1234, so no change was needed. The tip-of-tree entries (rev 1433) are not used.
- Server checks with curl: COOP, COEP and CORP on every response, including 404 and 301. `.part-N` and `.snapz` get `immutable`; index.json and the manifests get `max-age=0, must-revalidate`. HEAD returns Content-Length. `/nope` returns 404, not index.html. If-None-Match returns 304. Both 127.0.0.1 and [::1] answer 200. CHAOS test: the server log shows `CHAOS-CUT@1000000`, curl exited 18 (partial file), and the next request got all 32643645 B.
- X1 (out/experiments/x1.json, pass): `PREFLIGHT OK buildId=wasm64-4b025db7729c5f89 mode=resident snapshots=snapshots` with --no-boot, then again with boot (`boot smoke: ready in 14356 ms`). Before running it I read the preflight source: it writes only `if (dir)` from --run-dir (preflight.mjs:149-150), and boot mode only launches Playwright into a temp profile. I also ran it against ?snapshots=snapshots/rehearsal: PREFLIGHT OK, ready in 13315 ms.
- X2 (x2.json, pass). Visit 1: coi=true, phase ready, header covered with key [Init, Mathlib.Basic.Real.Basic] and moduleCount 5004, no SNAPSHOT_UNPAIRED. The snapz came from `/snapshots/rehearsal/init.35c8c5f5419e0c33.snapz` (32643645 B) and `/snapshots/rehearsal/mathlib.8df0689fbc323eab.snapz` (321484932 B). Boot took 12.8 s, with 649,763,293 B served in total. Visit 2 used the same persistent profile: snapzBytes 0 and total bytes 0 (25 responses, all 304). Boot took 8.4 s.
- X3 (x3.json, pass): parentCrossOriginIsolated=true and iframeCrossOriginIsolated=true. The seeded header booted snapshots [init, mathlib] in covered mode. Boot to ready took 6752 ms on the warm profile. `setValue` to an `import Mathlib.Order.Basic` document reached ready at version 2 in 407 ms, with the session unchanged (s1) and rangedChanges 0.
- X4 stock page, defect D2 (applyEdit). Case (a): clicking the core Try-this link sends the applyEdit RPC to the page; x4-debug.json caught `{"name":"applyEdit","args":[{"changes":{"file:///project/Probe.lean":[..."newText":"simp only [Nat.add_zero]"}]}}]}`. The page then throws `Error: unsupported at YL.$tryShowTextDocument`, and the text stays unchanged. The cause is in the bundle: monaco-vscode-api's default editor service has `this.openEditor=L` with `function L(){throw new Error("unsupported")}`, and lean4monaco/dist/leanmonaco.js:61-65 registers no editor-service override. vscode-lean4 infoview.js:318 awaits `window.showTextDocument` before `workspace.applyEdit`, so the edit never lands.
- X4 stock page, defect D1 (abortSignal). Case (b): the conv? panel never renders. The InfoView shows `Unrecognised error {... TypeError: r.abortSignal.addEventListener is not a function at sendClientRequest (index-CzXuAkOQ.js:1201:12747)`. The cause: lean4monaco's webview uses `s.getApi()` directly, while the page registers `editorApiOfRpc(...)` (infowebview.js:58) and messages are JSON.stringified, so ProofWidgets' `rs.call(RPC_METHOD, props, { abortSignal: ac.signal })` (ofRpcMethod.tsx:28) arrives as `{abortSignal:{}}`. Every mk_rpc_widget% panel is affected.
- X4 isolation run (b:strip, abortSignal repaired only): the panel renders and shift-click selects a subterm, but clicking Generate conv leaves the text unchanged (15 s timeout) and throws the same unsupported error. So MakeEditLink's applyEdit is also broken on the stock wiring.
- X4 with gallery/qed64-bridge.js (rerun on the final bridge, both pass). (a) The text became `... := by simp only [Nat.add_zero]`, ready at v2, 0 diagnostics, rangedChanges 0. (b) The panel shows `Conv 🔍️`; shift-click on `c + b` gave selectedCount 1; `Generate conv` produced `  conv =>\n    enter [2, 1, 1]\n    skip\n  omega`, ready at v2 with 0 diagnostics. revealLocation selected the `skip` (6:5-6:9). Bridge stats: stripped 2, applied 1, shown 1. This run also showed ProofWidgets JS import resolution and a Mathlib @[server_rpc_method] working from the baked region. Final x4.json verdict: `{applyEditStockPage: BROKEN, rpcPanelStockPage: BROKEN, applyEditWithBridge: works, makeEditLinkStockApplyEdit: BROKEN, makeEditLinkWithBridge: works}`.
- X5 (x5.json, pass): `relay.makeSession` is an own instance property. Baseline session s1 had initialBytes 2147483648 (`[mem] runtime-initialized: 2048 MiB`). With the wrapper, `relay.restart({snapshots:['init','mathlib']})` produced session s2 with initialBytes 3221225472, `[mem] runtime-initialized: 3072 MiB`, telemetry currentBytes 3221225472, and regionBytes 1249636802. It reached ready with userRestarts 1 and workerDeaths 0. chrome-headless-shell RSS went from 6.7 to 8.17 GiB.
- assert-untouched: I took the stamp at lane start (2026-10-01T02:50:04Z, stamp name s0). The final `check s0` (rc=0) printed `OK git HEAD/status/diff unchanged`, `OK no file newer than stamp` for qed64, the kernel build dir and the kernel repo, and `VERDICT: UNTOUCHED`. After the lane: the server was stopped (`stopped serve.mjs pid 99162`, nothing listening on 5190) and no chrome-headless-shell was left running. Before every boot, the cooldown check confirmed at least 15.5 GiB reclaimable.

## decisions
- S0.1 is not mine, so verify treats WIDGETS_SOURCE_HASH as SKIP when the lock lacks it and checks only that work/widgets-src exists when the lock has it.
- verify adds checks beyond S0.5: git blob-id anchoring of vendor/ against `git ls-tree QPIN`, nlink==1 on every release file, and the profile transport digest computed over the concatenated parts.
- assert-untouched takes an optional stamp NAME so concurrent lanes do not overwrite each other's stamp; this lane used `s0`. All git calls use --no-optional-locks, so the check itself never refreshes .git/index in the read-only trees.
- serve.mjs mirrors infra/worker.js isImmutable() exactly (`public, max-age=0, must-revalidate` for indexes and manifests) and adds ETag/304, which C2's 'only revalidations' needs. Overlay routing is generic: any /snapshots/<dir>/ whose out/overlay/snapshots/<dir> exists. I dropped X-Content-Type-Options so the headers match production.
- X4: definitive answer from raw, strip and bridge modes. The fix lives in gallery/qed64-bridge.js, not in QED64, so the zero-change rule holds.
- Playwright 1.62.1 kept: it maps to browser revision 1234; the reason is recorded in package.json `config`.

## openIssues
- BLOCKER-CLASS FINDING for S5/M1: on QED64's shipped page, every `mk_rpc_widget%` panel fails with "Unrecognised error … abortSignal". That covers all six widget packages. Applying an edit from the InfoView (Try-this or MakeEditLink) also does nothing. Neither can be fixed without either changing QED64 or installing gallery/qed64-bridge.js from the same origin. The bridge goes on the QED64 page window as a capture-phase message listener: it strips abortSignal (so cancellation is lost and requests run to completion), and it applies applyEdit, showDocument and insertText directly to qed64.editor. So M1 as 'the bare stock page plus an overlay' cannot show the panels. The M2 gallery must call installQed64Bridge(iframe.contentWindow) before any panel renders. Bridge installation from a parent onto iframe.contentWindow is not yet tested; X4 installed it through an init script inside the page. The owner should get an upstream report, covering lean4monaco's editorApiOfRpc/getApi inversion and the missing editor-service override.
- insertText handling in the bridge is implemented but untested: no X4 case uses it.
- Stock-page noise: every boot logs one pageerror `Error: unsupported` from `$onExtensionActivationError`, plus one empty `console.error`. This happens without the bridge too. The §8.1 console oracle has to allowlist it, or C14 will fail on the stock page.
- WIDGETS_SOURCE_HASH is not in QED64.lock.json yet; S0.1 owns it, so verify prints SKIP for it. `pin` keeps any keys it does not own, so a later re-pin will not erase it.
- Disk: out/ux/profiles/x2 holds an OPFS profile of about 1.8 GB, kept for warm reuse. Delete it per bake iteration (§10 risk). release/ shows 1.6 GB in du but is APFS clones.
- X9 and X6–X8 were not part of this lane.

## metrics
{
 "releaseFiles": 145,
 "releaseLogicalGB": 1.676,
 "vendorFiles": 24,
 "verifyOk": 37,
 "verifySkip": 1,
 "verifyFail": 0,
 "x1BootSmokeMs": 14356,
 "x1RehearsalBootSmokeMs": 13315,
 "x2ColdBootMs": 12760,
 "x2ColdSnapzBytes": 354128577,
 "x2ColdTotalBytes": 649763293,
 "x2WarmBootMs": 8434,
 "x2WarmSnapzBytes": 0,
 "x3WarmBootMs": 6752,
 "x3SwitchToReadyMs": 407,
 "x4aBridgeClickToEditMs": 102,
 "x4bBridgeClickToEditMs": 104,
 "x5BaselineInitialBytes": 2147483648,
 "x5WrappedInitialBytes": 3221225472,
 "x5RegionBytes": 1249636802,
 "x5RssGiBBaseline": 6.7,
 "x5RssGiBAfterRestart": 8.17,
 "rangedChangesAllRuns": 0
}

## audits
### round 1: pass
- [minor] The s0 stamp was taken about 2 minutes after the lane started, and it misses a write into the .git directories of all three read-only git trees made 25 s before it.
  - The project's .gitignore and the plan files are dated 22:48:04, but out/.stage-stamp-s0 is dated 22:50:04. `stat` shows /Users/fawadhaider/code/wasm64-lean-fable/qed64/.git, /Users/fawadhaider/code/wasm64-lean-kernel/.git and /Users/fawadhaider/code/wasm64-lean4game/.git all with mtime 22:49:39. `find -newer .gitignore` lists those .git dirs, while `find -newer stamp` prints nothing. No .git file under them (maxdepth 3) is newer than 22:00, so the index was not rewritten; this looks like a transient lock file from a git call without --no-optional-locks. HEAD, status and diff are identical to t
- [minor] WIDGETS_SOURCE_HASH is not in QED64.lock.json, even though the S0.1 export exists. When the key is present, verify only checks that the directory exists and never recomputes the hash, so S0.5 #7 is not actually enforced.
  - The lock's keys are [schema, pinnedAt, qed64, vendor, release, anchors, toolchain]. /Users/fawadhaider/code/qed64-showcase-work/widgets-src/SOURCE-HASH.txt holds 16cdb73b874adb2efb9fc611ccd3bd3421048c05513b26b672aec57851a5a6a0, exported at 02:50:10Z. My verify run prints `SKIP #7 WIDGETS_SOURCE_HASH not in lock yet`. pin-qed64.mjs:261-264 only does `ok(fs.existsSync(dir), ...)`.
- [minor] verify turns some missing inputs into non-failing SKIPs, so `VERIFY OK` can print without the Docker image or Playwright pins being checked.
  - pin-qed64.mjs:243 prints `skip(... docker not reachable)` if `docker image inspect` fails, and :252 prints `skip('#7 Playwright: ... not installed yet')`. SKIP lines never increment `fails`. In my run both were checked (OK for docker id 8b6698bbf474 and for Playwright 1.62.1 at rev 1234), so the gate held this time.
- [minor] X3 as written cannot show that the seeded qed64.buffer, rather than the default EXAMPLES.mathlib, set the boot header. The seed has the same header as the default, and only the first line was recorded.
  - x3.html DOC_A starts with `import Mathlib.Basic.Real.Basic`, the same header as main.ts:277 EXAMPLES.mathlib. x3.json records only `firstLine`. My rerun on a fresh profile against a separate server on :5199 settles it: the boot text equals the seed body (`bootTextIsSeed: true`, with the linarith example only and no `mul_comm c b`). The iframe was crossOriginIsolated, the switch reached ready in 411 ms, and X4's init-only seed booted ['init'] with exact mode. The claim holds; only the lane's own evidence was weak.
- [minor] x4.json merges runs made at different times (`{...prev, ...out}`), so its verdict can rest on runs made with older bridge or script versions. Also, when I installed the bridge from the parent window, three page errors appeared instead of one.
  - x4-click-paths.mjs reads prev runs from out/experiments/x4.json and spreads them in. The runs come from separate logs: x4-raw.log 23:03:39, x4-b-strip.log 23:04:24, x4-bridge-final.log 23:05:06. gallery/qed64-bridge.js has mtime 23:03. My independent rerun reproduces the verdict. With raw, the core Try-this click leaves the text unchanged (`changed:false`). With the bridge installed by init script, the text becomes `simp only [Nat.add_zero]`, ready at v2. Installing `installQed64Bridge(iframe.contentWindow)` from the parent also works (applied 1, text changed), which resolves the lane's open q

---

# native-build gatePassed=True

## deliverables
- /Users/fawadhaider/code/qed64-showcase-work/widgets-src (read-only export, 251 files, chmod a-w) + SOURCE-HASH.txt + SOURCE-FILES.sha256
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/lean/WIDGETS-SOURCE-HASH (16cdb73b874adb2efb9fc611ccd3bd3421048c05513b26b672aec57851a5a6a0)
- /Users/fawadhaider/code/qed64-showcase-work/mathlib4 (B0 APFS clone; now holds 38 phase-1 delta + 402 phase-2 delta + 72 widget/LeanWidgetKit native oleans)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/scripts/build-native.sh (subcommands identity, reuse-gate <tag> [list], delta, append, widgets, distlens, header-gate, lake)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/scripts/delta.py (closure/delta calculator from widget imports; nested-comment-aware header parser)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/scripts/header-gate.mjs
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/scripts/native-report.py
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/lean/lakefile-append.lean (9 lean_lib entries, no *Tests)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/out/delta-phase1.txt (38 modules), out/delta-phase2.txt (402 modules)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/out/native-build.json
- /Users/fawadhaider/code/qed64-showcase-work/logs/{steps.jsonl, b0-clone.log, b1-identity.log, b2-*.log, b3-delta.*, b4-widgets.*, s7-distlens-T4.*, header-gate-*.json, gmp-scan.json, closure-post-summary.json, delta-*.json}

## evidence
- Export: rsync excluding .lake .git /showcase/site *.log .DS_Store gave 251 files. cmp against the live widgets-v4.34 list printed 'export == live tree (same 251 files, same digests)'. WIDGETS_SOURCE_HASH=16cdb73b874adb2efb9fc611ccd3bd3421048c05513b26b672aec57851a5a6a0. Re-hashing at the end gave the same value.
- B0: cp -cpR took 13s with rc=0. Order/Basic.olean is src inode 68347678 nlink=5, clone inode 75988458 nlink=1. HtmlDisplay.olean is src 68395153 nlink=5, clone 75964573 nlink=1. 'clone files with nlink>1: 0' across 67040 files (the source has 16915 such files).
- Mount layout mirrors mathlib-tree.sh: the original mounted $BD/mathlib at /work with -w /work/mathlib4. build-native.sh mounts the clone at /work/mathlib4 and native at /native:ro, with the same PATH env. It adds --network none, LAKE_NO_CACHE=1, LAKE_ARTIFACT_CACHE=false, and widgets-src:ro at /work/mathlib4/widgets.
- B1: '/native/stage1/bin/lean', 'Lean (version 4.34.0, wasm64-unknown-emscripten, Release)', 'Lake version 5.0.0-src (Lean version 4.34.0)', 'githash=[]'.
- B2 pre (before any build): 'All targets up-to-date (3090 jobs).' rc=0. A stronger pre gate --no-build'ed all 2661 native deps in the 9-root closure: 'All targets up-to-date (2679 jobs).' rc=0. Negative control: --no-build SelectionPanel printed 'error: target is out-of-date and needs to be rebuilt' with rc=3, so the gate discriminates.
- Delta computed from widget imports with scripts/delta.py. Phase 1 closure: 64 own widget modules, 1140 native deps, 37 missing + 1 GMP (SelectionPanel) = 38 to compile: 28 SimpleGraph.*, Catalan.{Basic,Tree}, 7 Data/Order/Algebra modules, and SelectionPanel. The plan's six names were only the maximal roots. Phase-2 increment: 402 deps + 8 own.
- B3: 'Build completed successfully (1147 jobs).' rc=0, wall 134s, peak 1604 MiB, T=6. The 38 newly written oleans equal the predicted list exactly ('newly compiled == predicted 38').
- B4 append went to the clone lakefile only; the backup is mathlib4/lakefile.lean.pre-append. B2 post: 'All targets up-to-date (3090 jobs).' rc=0. Post-full over 2661 native + 38 delta: 'All targets up-to-date (2717 jobs).' rc=0. The only new olean was .lake/config/0/lakefile.olean (Lake config re-elaboration).
- B4 widgets (T=6): 'Build completed successfully (1263 jobs).' rc=0, wall 230s, peak 2933 MiB. 64 new oleans, all widget-own (ChartKit 7, ExprXRay 7, GraphScope 11, HasseView 9, IntervalInspector 9, SimpLens 8, TreeScope 13), equal to the predicted widgetOwn list. 0 warning lines. No Mathlib module was rebuilt.
- DistLens + LeanWidgetKit (T=4, no fallback needed): 'Build completed successfully (3189 jobs).' rc=0, wall 1363s, peak 3750 MiB. 410 new oleans: 402 Mathlib deps + DistLens 7 + LeanWidgetKit 1. 'predicted 410 got 410 equal True'.
- Final gate: --no-build on all 9 libs + the plan's 3 modules printed 'All targets up-to-date (3755 jobs).' rc=0.
- Header gate: b3-delta PASS (114 files, 38 modules, olean/server/private, all version 2, gmp=0). b4-widgets PASS (64 files; widgets are legacy, so .olean only). s7-distlens PASS (1214 files, 410 modules). closure-9-roots PASS (9954 files, 3366 modules including 193 core leaves from /native/stage1/lib/lean, failed=0, gmp=0, missing=0).
- GMP barrel scan: 448 GMP/githash facet files across 150 modules remain in the clone (batteries 352 files, importGraph 66, proofwidgets 30). ProofWidgets modules: umbrella ProofWidgets, Component.{ForceGraphDisplay,GraphDisplay,GraphvizDisplay,InteractiveSvg,Maximizable,Recharts,Panel.GoalTypePanel}, Data.Svg, Extra.CheckHighlight. 'of which in closure of 9 roots: 0'. SelectionPanel is now native.
- Untouched: find -newer lane-stamp printed nothing for wasm64-lean-kernel-build-v4.34.0, wasm64-lean-kernel, wasm64-lean-fable/qed64, wasm64-lean4game, or widgets-v4.34. docker ps showed nothing running at the end. No git commit or init. The only git command run was 'git status' on the clone.

## decisions
- Passed all 38 exact delta modules as B3 targets, computed from the widget import closure, instead of the plan's 6 maximal names. The build compiled exactly those 38.
- Added stronger B2 gates: all 2661 native closure deps before the build, the same set plus the 38 delta after the append, and all 9 libs at the end. Also ran a negative control proving that --no-build returns rc=3 when out of date.
- Mirrored mathlib-tree.sh's PATH env (/native/stage1/bin:/emsdk/node/current/bin:...) in addition to the plan template. The container path is /work/mathlib4, identical to the original.
- Newly compiled modules are measured by an in-container stamp file (.lake/showcase-stamps/<step>) plus 'find -newer', which is independent of Lake log verbosity.
- DistLens ran at T=4 and succeeded first time (peak 3750 MiB of 7.65 GiB), so no T=2 fallback was needed.
- widgets-src is chmod a-w after export, and SOURCE-HASH.txt / SOURCE-FILES.sha256 are excluded from the hash. QED64.lock.json was not touched.

## openIssues
- Other lanes wrote logs into /Users/fawadhaider/code/qed64-showcase-work/logs (examples-*, golden-*) between 23:00 and 23:25 while the DistLens build ran. Their logs show no use of Docker or /work/mathlib4. build-native.sh refuses to start while any other container runs, but it cannot stop another lane from starting during a build. Peak-memory figures are per-container (docker stats), so they remain valid.
- The export also excludes .DS_Store (1 file at the widgets root), beyond the listed exclusions, to keep the hash stable. This is recorded in SOURCE-HASH.txt.
- Widget oleans are legacy (non-module) files, so they have .olean/.ilean/.ir only, with no .olean.server/.private. The stage-trees lane should expect this.
- The B4 Lake config re-elaboration wrote .lake/config/0/lakefile.olean in the clone. It is not a module and is not to be staged.
- Docker created an empty mountpoint dir /Users/fawadhaider/code/qed64-showcase-work/mathlib4/widgets on the host (inside the clone, harmless). The clone also has an untracked lakefile.lean.pre-append backup.
- R5b raw 'lean -o' fallback was not needed and was not implemented, because Lake reuse held after the append.
- native-build.json predicted.phase2Increment lists 402 dep modules. The total phase-2 compile was 410 including 8 own-widget modules.

## metrics
{
 "widgetsSourceFiles": 251,
 "widgetsSourceHash": "16cdb73b874adb2efb9fc611ccd3bd3421048c05513b26b672aec57851a5a6a0",
 "b0CloneWallSeconds": 13,
 "b0CloneFiles": 67040,
 "b0CloneFilesNlinkGt1": 0,
 "b2PreWallSeconds": 14,
 "b3DeltaModules": 38,
 "b3WallSeconds": 134,
 "b3PeakMemMiB": 1604,
 "b4WidgetModules": 64,
 "b4WallSeconds": 230,
 "b4PeakMemMiB": 2933,
 "distlensPhaseModules": 410,
 "distlensDepModules": 402,
 "distlensWallSeconds": 1363,
 "distlensPeakMemMiB": 3750,
 "distlensThreads": 4,
 "totalNewlyCompiledModules": 512,
 "closure9RootsModules": 3366,
 "closureHeaderGateFiles": 9954,
 "gmpInClosure": 0,
 "gmpModulesElsewhereInClone": 150
}

## audits
### round 1: pass
- [minor] The B0 clone's evidence is not saved anywhere: no wall time, rc or inode/nlink proof. logs/b0-clone.log is 0 bytes, steps.jsonl has no b0 entry, and out/native-build.json has no b0 field. The brief's step 6 asked for wall times per step in logs/ and native-build.json. The lane's claims of 13s and 67040 files therefore have no record behind them.
  - `ls -la logs/b0-clone.log` shows 0 bytes. `grep -i b0 out/native-build.json` finds nothing. My own re-check confirms the substance. Order/Basic.olean is inode 68347678 with nlink 5 in K, and inode 75988458 with nlink 1 in the clone. `find $W -type f -links +1 | wc -l` gives 0. comm of the file lists gives 'missing-in-clone: 0' against K's 67040 files.
- [minor] WIDGETS_SOURCE_HASH is not in QED64.lock.json, although PLAN-AMENDMENTS §1 requires it there. It exists only in widgets-src/SOURCE-HASH.txt, lean/WIDGETS-SOURCE-HASH and native-build.json. The native lane was correctly told not to touch the lock file, so this is a gap between lanes that the pin lane or the orchestrator must close.
  - `grep -n -i widget QED64.lock.json` matches only an infoview .d.ts path and the proofwidgets commit. My recomputed hash over 251 files is 16cdb73b874adb2efb9fc611ccd3bd3421048c05513b26b672aec57851a5a6a0. That equals SOURCE-HASH.txt, and the live widgets-v4.34 tree with the same exclusions gives an identical file list ('LIVE==EXPORT').
- [minor] The report says the widget oleans have '.olean/.ilean/.ir only'. In fact lib/lean has no .ir or .ir.sig facet for any widget module, only .olean, .ilean, .hash and .trace; the C code is under build/ir. stage-trees (plan C1) clones the facets '.olean, .olean.server, .ir, .ir.sig'. For the 72 widget modules it must therefore treat .olean as the only facet and must not require .ir.
  - `ls .lake/build/lib/lean/ChartKit*` lists ChartKit.ilean, .ilean.hash, .olean, .olean.hash and .trace. build/ir/ holds ChartKit.c and ChartKit.setup.json. My header-gate run over the 512 modules reports 'olean 512, server 440, private 440', so the 72 widget modules have no server/private facets.
- [minor] The clone holds some harmless leftovers: an empty `mathlib4/widgets` mountpoint dir, an untracked `lakefile.lean.pre-append`, `.lake/showcase-stamps/*`, and a leftover `.lake/config/0/lakefile.olean.lock`. None of them block Lake. My read-only-mount runs succeeded, so no lock or write is needed for --no-build or `lake env lean`.
  - comm against K's file list shows 7612 extra files. Apart from build outputs, these are the 10 showcase-stamps, lakefile.olean.lock and lakefile.lean.pre-append. `git status --porcelain` on the clone shows ' M lakefile.lean', '?? .qed64-smoke.lean' (inherited from K, mtime 09:53) and '?? lakefile.lean.pre-append'.

---

# examples gatePassed=True

## deliverables
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/lean/examples/{chart-kit,expr-xray,simp-lens,interval-inspector,graph-scope,tree-scope,hasse-view,dist-lens}.lean — 8 showcase docs, header exactly 'import Mathlib'/'import <Pkg>', body in 'namespace Showcase.<Pkg>', ≤60 lines (60/42/37/49/38/48/34/35)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/lean/examples/<pkg>.json — specs: package/title/blurb/header/cursors(line,character,command,expect)/clicks(expectedEdit frozen, postClickDiagnostics)/selections/hovers/dropped
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/lean/expect/<pkg>.json — frozen goldens (panel signatures: tagCounts, svgTagCounts, texts, codeTexts, linkTexts, links with exact edits, JS-module checks, click verdicts, selections, hovers)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/lean/expect/html/<pkg>.json — full RPC-encoded Html of every panel (RPC refs normalized) for the React-contract check (E3b)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/lean/goldens/lsp-golden.mjs — golden generator: drives stock `lean --server` over LSP like the InfoView (getWidgets, getInteractiveGoals/TermGoal, getWidgetSource, the mk_rpc_widget% panel's own server_rpc_method incl. cancellable protocol, getInteractiveDiagnostics for Try-this, infoToInteractive for hovers, UTF-16 edit + didChange + diagnostics per click)
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/lean/goldens/golden-env.sh — builds the browser-equivalent native env: shadow Mathlib.olean umbrella = QED64.Essential's 4354 modules + bake roots (w7; w8 adds DistLens), APFS-cloned Mathlib/ subtree, merged ProofWidgets
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/lean/goldens/native-gate.sh (closure|superset CLI gate), run-all.sh, summary.mjs, crosscheck.mjs, mkspec.py
- /Users/fawadhaider/code/lean questions/infoview-widget-research/qed64-showcase/lean/README.md — example/spec/golden format and how goldens were produced
- Work outputs: /Users/fawadhaider/code/qed64-showcase-work/examples-native/<pkg>/ (closure + superset copies, click variants), /Users/fawadhaider/code/qed64-showcase-work/golden-run/<pkg>-{superset,closure}/Showcase.clickN.lean, /Users/fawadhaider/code/qed64-showcase-work/goldens/{run-all.tsv,summary.json,crosscheck.json,<pkg>.closure.json}, logs /Users/fawadhaider/code/qed64-showcase-work/logs/examples-*.log

## evidence
- run-all.sh (log /Users/fawadhaider/code/qed64-showcase-work/logs/examples-run-all.log) ended with 'REQUIRED-GATES: PASS' and exit 0
- Closure CLI gate (import Mathlib blanked to an empty line, `lake env lean` from each package's own tree): all 8 rc=0, errors=0, warnings=0, e.g. '[native-gate/closure] dist-lens rc=0 wall=15s errors=0 warnings=0'
- Superset CLI gate (unmodified browser text, shadow-Mathlib golden env): all 8 rc=0 errors=0 warnings=0
- LSP superset goldens: chart-kit 27/27, expr-xray 19/19, simp-lens 40/40, interval-inspector 32/32, graph-scope 26/26, tree-scope 16/16, hasse-view 31/31, dist-lens 29/29 declared checks PASS; zero error/warning diagnostics in every document (simp-lens has 6 designed `Try this:` infos)
- All 19 declared clicks clean: LSP post-click re-elaboration (diagnostics checked for the edited version) AND superset CLI compile of every edited file rc=0 with 0 warnings (run-all.tsv rows 'clickN | superset-cli | 0'): simp-lens 6 tryThis, interval-inspector 1, graph-scope 4 (edge via title, vertex '0', 'components: 1 (connected)', 'components: 2 (disconnected)'), hasse-view 5 (cover, ⊥, ⊤, Bowtie no-join witness, Bowtie cover), dist-lens 3 (die 0, twoDice 5, weather π0)
- Plan numbers reproduced: chart-kit diceChart svg rect 12/line 24/text 15; hasse-view powerset cube rect 8/line 12/text 16 with 14 links (12 covers + ⊥ + ⊤); expr-xray `#xray (1 + 1 : Nat)` 23 <details>
- Every panel's JS was retrieved via getWidgetSource (non-empty, imports @leanprover/infoview) and every RPC panel method answered (IntervalInspectorPanel.rpc, XRayPanel.rpc, GraphScopePanel.rpc, HassePanel.rpc, DistPanel.rpc, ChainPanel.rpc)
- crosscheck.mjs vs widgets-v4.34/showcase/dumps: 8/14 same-input pairs identical (all 4 ChartKit, 3 IntervalInspector, DistLens filmstrip); remaining 6 have identical SVG tag multisets, text diffs explained (ℕ vs Nat; namespace-qualified `unfold Showcase.DistLens.die`; hasse dump labels by index)
- Read-only trees: `find -newer <session marker>` = 0 files in qed64, wasm64-lean-kernel, wasm64-lean-kernel-build-v4.34.0, wasm64-lean4game and widgets-v4.34; `git -C qed64 status --porcelain` = 0 lines; `lake env printenv` in a widget tree wrote nothing
- Native timings (superset LSP, incl. ~2 s import): elaboration 2.1–7.0 s per example, max panel RPC 36 ms (hasse), click re-elaboration 0.5–0.9 s

## decisions
- Examples keep the two-line D2 header and wrap everything in namespace Showcase.<Pkg>. Heavy Demo items were trimmed; each spec's `dropped` field lists what was left out and why.
- The native closure gate blanks `import Mathlib` to an empty line instead of deleting it, so LSP line numbers stay identical between the browser text, the native copies and the goldens.
- Golden environment: a shadow `Mathlib.olean` umbrella over essential-modules.txt plus the bake roots, compiled with stock lean. It is placed first on LEAN_PATH next to an APFS-cloned `Mathlib/` subtree, because Lean resolves a module root at the first dir holding `Mathlib/` or `Mathlib.olean`. ProofWidgets is merged from the per-package partial builds (all overlapping oleans byte-identical; only .trace differs). All dependency revs equal the kernel pin.
- 'clean' means no error- or warning-severity diagnostic anywhere in the document; info messages are allowed (e.g. Try this).
- The LSP server runs in a lakefile-free work dir with LAKE=/nonexistent, so `lake setup-file` never touches a widget tree.
- Big UInt64 JSON values (sessionId, javascriptHash) are preserved via the JSON.parse source-text reviver plus JSON.rawJSON.

## openIssues
- DEVIATION: per-package `lean/goldens/<pkg>.probe.lean` were NOT written. In their place is one generic LSP driver (lsp-golden.mjs). An in-process Lean probe cannot run @[server_rpc_method] handlers, which need RequestM with a live document. It would have had to re-implement each RPC body, the way the showcase probes and ClickE2E call pure builders. The LSP driver runs the real methods and produces exactly the payloads the InfoView receives. It is also the native twin of plan E3 rpc-probe.mjs, and that script can reuse its client logic.
- Goldens are computed in the browser-equivalent superset environment (QED64.Essential + bake roots), not the closure-only one. This matters for 2 packages. expr-xray shows ℕ/ℤ notation and `PUnit.{1}` levels in the superset. simp-lens' minimal calls use `add_zero, zero_add`; in the closure env they use `Nat.add_zero, Nat.zero_add`, so 3 of 6 edits differ. As a result, the closure CLI compile of simp-lens post-click files 1, 3 and 4 fails by design (`add_zero` is a Mathlib name). This is recorded as information only; the required post-click gate is the superset one. The other 6 packages give identical signatures in both environments.
- Plan W3 needs updating. For the symbolic union goal, the interval-inspector panel suggests `refine Set.Ioc_union_Ioc_eq_Ioc ?_ ?_` (badges `a ≤ b ✓ ready`), not `exact …`. Clicking it would leave the two side goals open. The declared click is therefore on a set-builder goal: `exact Set.Ico_subset_Icc_self` replaces `interval_inspect?`, with a following `try exact …` line that keeps the file clean before and after the click. Pre-click is clean, not the designed 'unsolved goals' error W3 assumed. The union proof and the shift-click on `hx` (selection golden) are kept as cursor-only demos.
- Selector notes for the UX lane. Core Try-this in v4.34 is a message widget `Lean.Meta.Hint.textInsertionWidget` whose link text is `[apply]`; plan §8.1's `span.link.pointer.dim.font-code` may not match. GraphScope edge links have empty text and must be found by their `title` ('insert: example : …'). MakeEditLink's textDocument.uri/version will differ in the browser; compare range+newText only. Selection goldens use mvarIds from the native session; a browser test must shift-click the DOM, not replay locations.
- Native timings are only a proxy for browser cost (IR interpreter, ~1 MB stack); actual wasm cost of graph-scope/hasse-view gates and dist-lens pmf_num clicks is still to be measured in E1–E3 and the UX runs. dist-lens goldens use env w8 (phase 2).

## metrics
{
 "examplesCompilingClosureOnly": "8/8",
 "examplesCompilingSuperset": "8/8",
 "goldenChecksPassed": "220/220",
 "declaredClicks": 19,
 "clicksCleanLSP": "19/19",
 "clicksCleanSupersetCLI": "19/19",
 "clickKinds": {
  "tryThis": 6,
  "makeEditLink": 13
 },
 "selections": 3,
 "hovers": 1,
 "cursors": 46,
 "panelsRendered": 46,
 "makeEditLinksRendered": 129,
 "crosscheckIdentical": "8/14",
 "closureEnvSensitivePackages": [
  "expr-xray",
  "simp-lens"
 ],
 "exampleLines": {
  "chart-kit": 60,
  "expr-xray": 42,
  "simp-lens": 37,
  "interval-inspector": 49,
  "graph-scope": 38,
  "tree-scope": 48,
  "hasse-view": 34,
  "dist-lens": 35
 }
}

## audits
### round 1: pass
- [minor] The QED64 checkout's .git directory mtime moved after the lane's last write, so `scripts/assert-untouched.sh check s0` now reports CHANGED. The cause looks like the lane's own read-only check: a plain `git -C qed64 status --porcelain`, run without --no-optional-locks, creates and removes .git/index.lock. No content changed.
  - `assert-untouched.sh check s0` printed 'FAIL file newer than stamp under .../qed64: .../qed64/.git' and 'VERDICT: CHANGED' (rc=1). The same run printed 'OK git HEAD/status/diff unchanged'. `stat` shows qed64/.git modified at 'Sep 30 23:27:16 2026'. The lane's last output, crosscheck.json, is from 23:26:48, and my audit started at 23:28:21. .git/index is still at 16:20:10 and HEAD is 1859b83, unchanged. The kernel and lean4game .git directories are still at 22:49:39. Only qed64 matches the lane's claim '`git -C qed64 status --porcelain` = 0 lines'. find -newer prints nothing for the kernel repo
- [minor] In the interval-inspector example, the header comment tells the reader that every suggested tactic is a link to click. Clicking the rendered union suggestion (line 33), and very likely the `hx` one (line 45), leaves a broken file, because each example keeps its own closing `exact` line after `interval_inspect?`. Only the line-40 click is declared and verified.
  - I applied the golden link edit at L33 ({range L33 c2–19, newText 'refine Set.Ioc_union_Ioc_eq_Ioc ?_ ?_'}) and compiled with the superset env. Result: 'ii-union-click.lean:35:2: error: Type mismatch ... but is expected to have type a ≤ b', rc=1. The golden also renders the link 'refine Set.mem_Icc.mpr ⟨?_, ?_⟩' at L45, which follows the same pattern.
- [minor] `htmlSha256` in lean/expect/<pkg>.json depends on the run environment for every panel that holds a MakeEditLink, because the props include the document uri and version. Any later stage that compares htmlSha256 against a browser or wasm run will mismatch on 17 panels. The README describes htmlSha256 without this caveat.
  - I re-ran lsp-golden.mjs in a sandbox (same code, different W/run dir). The full signatures are IDENTICAL for chart-kit, expr-xray, simp-lens and tree-scope. For interval-inspector (L33/40/45), graph-scope (5 cursors), hasse-view (5 cursors) and dist-lens (L20/24/31/32), htmlSha256 is the only field that differs. Tag counts, texts, links, edits, click verdicts and declaredChecks are identical.
- [minor] The brief asked for per-package `lean/goldens/<pkg>.probe.lean`. These were not written. A generic LSP driver, lsp-golden.mjs, replaces them. The deviation is documented and the driver is arguably stronger, since it runs the real server_rpc_methods.
  - `ls lean/goldens` shows crosscheck.mjs, golden-env.sh, lsp-golden.mjs, mkspec.py, native-gate.sh, run-all.sh and summary.mjs, with no *.probe.lean. The lane's openIssues lists this as a DEVIATION.
- [minor] Some example claims and plan checks are not covered by any golden. The simp-lens header says the lightbulb code action does the same as the Try-this link (plan W4(c)), but no textDocument/codeAction request is made. Plan W6 (catalanGallery 4) and W7 (completeGraph (Fin 5)) were shrunk to n=3 and Fin 4. Both shrinks are recorded under `dropped`, but the plan's §8.2 table still references the originals.
  - `grep codeAction lsp-golden.mjs` finds nothing (no such request in the driver). tree-scope.json dropped: 'Catalan gallery n=4 (14 trees) shrunk to n=3 (5 trees)'. graph-scope.json dropped: 'K5 shrunk to K4'.
- [minor] Coordination risks for later stages. Plan E3 step 9 says to freeze the wasm results into lean/expect/<pkg>.json, which now holds the native goldens. The selection goldens carry native mvarIds (e.g. '_uniq.633.3'), so they cannot be replayed in the browser. dist-lens goldens are computed in env w8 (phase 2). Browser cost of graph-scope, tree-scope (7.0 s native), dist_film and the pmf_num clicks has not been measured.
  - BUILD-PLAN.md:337 says 'Freeze the results into `lean/expect/<pkg>.json`'. expect/expr-xray.json selections have selectedLocations [{'mvarId': '_uniq.633.3', ...}]. tree-scope elaborationMs is 6974.
