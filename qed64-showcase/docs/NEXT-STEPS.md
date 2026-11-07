# Next steps (updated 2026-11-07, P1 and P2 committed locally)

This page lists only what remains. What is done is in README.md (status page), docs/UX-RESULTS.md, docs/REPIN-LOG.md
and docs/HISTORY.md.

## Release routing (P3), the deploy of O, then P1 and P2: decided 2026-11-01

**Where it stands (2026-11-07).** The live site serves pin O `521cf3f` with release routing: the owner uploaded its 12
objects (record `out/deploy/published/20261105T200927Z`, backed up in `$W/published-backup/`) and pushed `b24587d` to
`main`. The `qed64-deploy` run promoted Worker version `476d6c11-a119-4b17-8545-65e0b9f34987` at 2026-11-05 20:18Z after
`PRE-PROMOTION OK`, with `SMOKE OK` on the live URL. On 2026-11-07 `--published` and `--smoke --all --range` against the live
URL were OK, and a cold boot of `/showcase/#hasse-view` under the browser lock gave `BOOT-CHECK OK`. The previous version is
H `bf9d947` (Worker version `29176b6f-cc41-4a16-bed4-c8753c7bd5f2`, deployed from `d60b15e`, runtime `3ab1c6a9`): the
rollback target, docs/DEPLOY-CLOUDFLARE.md section 5. O is gated with the verdict `o-full2`, which P3 keeps because the
gallery, the lock and the overlays are unchanged. P3 is committed on the branch `release-routing` (`f13d535`, its review fixes `dbfd000`, then `ed8f781`: the
browser lock counts browsers by executable, and `12aca96`, `eca8f22`: the CI rehearsal's boots; on top of `port-lean-4.35`): `infra/worker.js` is QED64's `createWorker` with the pin's toolchain record, the upload falls from 93
objects, 2.367 GB to 12 objects, 1.107 GB at O, and `deploy-app.sh` checks each new version on its preview URL before it
takes traffic (docs/DEPLOY-CLOUDFLARE.md 3.2, 3.3). Both rehearsals passed: `scripts/deploy-rehearsal/rehearse.sh all browser
stop` on `dbfd000` (2026-11-02), and the CI mirror plus all 9 `ci/rehearse-deploy.sh` scenarios on `eca8f22` (2026-11-04;
docs/DEPLOY-CLOUDFLARE.md, Rehearsal and CI rehearsal). Pushed with O as `b24587d`.

**The owner's decisions (2026-11-01, in the QED64 session: QED64's report R14a and its hand-off
`work/arch-impl-2026-11-01/handoffs/sent/showcase-2026-11-02.md`).** Approved: P3, the deploy of O, then P1 and P2 in one
re-gate; C7 may become a substring match with one fresh G2 verdict; D1, D2, D5, D6 (a failing bake exits 1 after the flip,
not 3), D10, D11, D16, M3, and D3a (its retention follows K4). Not approved, so not acted on: D7, D8, D15. The P numbers
are from `$W/reports/architecture-review-widgets-2026-10-28.md`; the D, M and K numbers are QED64's report's.

**Deploying O (done 2026-11-05): the owner's steps, in this order, kept as the record.** Pushing, uploading and turning on Preview URLs
are the owner's acts.

1. Turn on Preview URLs for the Worker `qed64-showcase` (dashboard: the Worker, Settings, Domains & Routes). This is
   needed once; without it `deploy-app.sh` refuses and promotes nothing.
2. `DRY_RUN=1 scripts/upload-artifacts.sh` (regenerates `out/deploy/manifest.json`, checks it, lists the bucket, writes
   nothing; a manifest from before release routing fails `--check` until regenerated: this checkout's was regenerated on
   2026-11-05, `DEPLOY-MANIFEST CHECK OK` with G2 on `o-full2`), then the
   preconditions (docs/DEPLOY-CLOUDFLARE.md, first deploy checklist, step 2), and
   `rclone size qed64-r2:qed64-artifacts/lean4-wasm64/lean-v4.35.0-b081e7c/`: it must hold at least the release's 81 objects,
   1.260 GB. The upload does not check this.
3. `scripts/upload-artifacts.sh`: 12 objects, 1.107 GB. Then back up `out/deploy/published/` (a copy of the records so far
   is in `$W/published-backup/`). H's full version id, for a rollback, is `29176b6f-cc41-4a16-bed4-c8753c7bd5f2` (the deploy run's log).
4. `git push origin release-routing:main`, promptly, with the docs committed on that branch first (a fast-forward from
   `d60b15e`): a push to main deploys. The local `main` is still at `d60b15e`, so `git push origin main` pushes nothing and
   deploys nothing. From the end of step 3 until the promotion, bare stock visits of H fail while H's gallery should still
   boot. This is order A, the only order CI has (docs/DEPLOY-CLOUDFLARE.md 3.2).
5. Read the `qed64-deploy` run: it must show `PRE-PROMOTION OK`, `DEPLOYED-URL` and `SMOKE OK`. Then the checklist's step 8.
   If the run stops before the promotion, H keeps the traffic but bare stock visits keep failing. Fix the cause and run the
   workflow again (Actions, Run workflow; pushing the same commit again does nothing), or put H's indexes back with
   `scripts/rollback-artifacts.sh out/deploy/published/20261005T152953Z` (no `wrangler rollback`: H is still live) and
   repeat step 3 before the next run, because the pre-promotion check compares the phase-3 indexes.

A rollback to H after the promotion is docs/DEPLOY-CLOUDFLARE.md section 5.

**P1 and P2: implemented, waiting for their re-gate (2026-11-07).** Both change the inputs of G2, so they share one
re-gate of about 12 h. The plan is `$W/reports/p1-p2-plan-2026-11-02.md` (with the fd95a2a audit's amendments). The
commits C1–C10 are on the local branch `p1-p2` (from `c7b7e49`: `b24587d` plus 470dda3 and c7b7e49, unpushed), not pushed; the record is docs/REPIN-LOG.md "P1 and P2".

* **P1, done in code.** Only O and N are registered; the other 12 descriptors and locks are at the tag
  `pins-history-2026-11-07` (`b24587d`); the gallery's legacy mode, `gallery/qed64-bridge.js`, `gallery/x3.html` and the
  tools that read the bridge are deleted; X4 is raw only. A rollback to H does not need H's registration: it stays
  docs/DEPLOY-CLOUDFLARE.md section 5, `scripts/rollback-artifacts.sh out/deploy/published/20261005T152953Z`, then
  `wrangler rollback 29176b6f-cc41-4a16-bed4-c8753c7bd5f2`.
* **P2, done in code.** One overlay, `widgets8`; both kept locks lost their widgets7 block, so O's and N's recorded
  verdicts no longer match (`pin list` shows 0 until the re-gate).
* **C7's substring match** (`tests/ux/specs/30-robustness.spec.mjs:97`, "are not loaded in this session") went in with
  the safe-now edits (C9) and is proved by the same gate.
* **Next, in order:** the re-gate (the plan's section 6: static, G1, controls, stage4 w8, the click-all CLI on w8, X4 raw
  and `widgets.mjs` without `--thumbs`, the smoke, two full `ux` VERDICTs, C20 ×3, the headed sign-off, the 10 Mbit/s
  first visit, the manifest and the verdict commit, the CI mirror and the deploy rehearsal); then the owner's one push of
  the branch to `main` (no upload: the 9 objects are already in the bucket from O's upload). Rollback from that deploy is
  to O's Worker version `476d6c11-a119-4b17-8545-65e0b9f34987` (docs/DEPLOY-CLOUDFLARE.md section 5, "Rollback to O").

While H and O are rollback targets, what must stay is listed in docs/DEPLOY-CLOUDFLARE.md section 6.

**D11.** QED64 is retiring its release bundle (`39dee02`, on its origin/main since `fd95a2a`), so our steps 5 and 6 and
P7 "Later" are dropped. The submodule and `scripts/build-shell.mjs` stay. P7 "Now" no longer waits for anything of QED64's
(D2 is pushed), but the tools it wants reach us with the re-pin, so it rides the re-pin, not the P1+P2 re-gate.

**D5 and K4** (when to re-pin, which releases we read, and which pin records the kernel's retention rule reads) are in
docs/DEPLOY-CLOUDFLARE.md section 6. The pack-manifest question to QED64 in docs/UPSTREAM-REPORT-QED64.md (last section)
is superseded by release routing.

**Also now: M3 and D16.** M3: `scripts/pin-qed64.mjs` check #3 reads `org.lean-browser64.runtime/v2` and compares the pin's
schema with `runtime.manifestSchemas`, before the kernel's first v2 publish (`39ae6ac`; the kernel's own
`cli.mjs fetch --only runtime` still reads only v1, which fills our `stage1`: the kernel session knows). D16: QED64's lean4monaco
drafts (its `work/upstream/lean4monaco-2026-11-01/`) are reviewed in `$W/reports/d16-lean4monaco-review-2026-11-02.md`. QED64 applied the
review's wording fixes, and the browser check of 0002 (2026-11-02, pin O, headless Chromium) confirmed the editor reuse on
the plain page: `[apply]` edits the text and the fallback callback runs 0 times; the `?embed=1` run timed out before
`[apply]` appeared, so embed scroll is unmeasured. Whether to post is the owner's.

**At the next re-pin of a pushed QED64 SHA.** The target is `f2b623a`, QED64's origin/main since 2026-11-03, deployed: same
runtime and release as O, so no rebake. It comes after O's deploy and the P1+P2 re-gate. The checklist is
`$W/reports/repin-arch-batch-checklist-2026-11-02.md`, with its amendments from the audit at `fd95a2a`, which holds for `f2b623a` (`$W/reports/repin-fd95a2a-audit-2026-11-03.md`). `f2b623a` no longer has `tests/adversarial/preflight.mjs`, so the re-pin needs the lookup in `scripts/preflight-overlays.sh` from `release-routing` (on `main` since `b24587d`; since P1 it reads only `pipeline/release/preflight.mjs`).

## Pin O `521cf3f`: active and gated (Lean 4.35); the state on 2026-10-28 and what stays open from it

**Where it stands (2026-10-28 ~03:00Z).** The live site still serves pin H `bf9d947` (Lean 4.34.0, deployed 2026-10-08
from `d60b15e`, which is `origin/main`). The active pin of this checkout is **O `521cf3f`** since 2026-10-27: QED64 main on
the kernel release `lean-v4.35.0-b081e7c`, Lean 4.35.0, runtime `wasm64-36d7f415704473d9`, with the widgets ported to
Lean 4.35 (`1a61003`). It is gated: headless `CONTROLS PASS`, stage4 and E2 green (E2 7/8 on L1), VERDICTs `o-full1` and
`o-full2`, C20 405/405, the headed sign-off `o-headed4`, the 10 Mbit/s first visit (513.9 s), `deploy-manifest --check`
OK with `infra/ux-verdict.json` naming `o-full2` (docs/REPIN-LOG.md, pin O). Pins K, L and N came between J and O; I and
J are retired. Nothing is pushed: the branch `port-lean-4.35` holds pins I–O and the Lean 4.35 port on top of `origin/main`.

1. **Done:** the pin O work is committed on `port-lean-4.35` (O's harness `07d015b`, the review fixes and `NODE_TOOL`
   `0ab384a`, pin O `546d110`, the docs `9eed0e9`, the rehearsal record `6330f6d`, the smoke's sha256 of every manifest
   and index `dbacd2c` and its follow-ups `b939b10`). On `9eed0e9` and again on `dbacd2c` the qed64-static CI mirror is
   `JOB SUCCESS` (12/12, the shell from source byte-identical to O's lock) and `ci/rehearse-deploy.sh` is
   `REHEARSE-DEPLOY OK` with all eight scenarios; `old-shell` against the live H measured the pack-manifest window, and
   on `dbacd2c` order B's smoke before phase 3 fails on both stale indexes. On `b939b10`, `dry-run deploy first` are OK
   (docs/REPIN-LOG.md, pin O, "CI mirror and deploy rehearsal", "Rerun on `dbacd2c`" and "`b939b10`").
2. **The decisions as they stood on 2026-10-28** (the first is decided now and the second in part, top section):
   * **The push: decided.** O goes out from `release-routing` after P3, with 12 R2 objects, 1.107 GB instead of 93
     objects, 2.367 GB (`.github/workflows/qed64-deploy.yml`; G2 reads the committed `infra/ux-verdict.json`). N
     `58ebbad` is not deployed first.
   * **E1: the pack-manifest half is gone with release routing, for the upload window.** The window the rehearsal measured
     on 2026-10-28 (docs/REPIN-LOG.md, pin O) is gone: O's pack manifests are the release's, and no upload of ours replaces
     them under the live H. (An H tab left open past the promotion still gets O's pack manifests: docs/DEPLOY-CLOUDFLARE.md
     section 6.) What is left is phase 3's index window (3.2 there). The owner's list does not choose between the orders for
     it; the steps above use order A, the only one CI has. Order B is by hand and must run the smoke after phase 3
     (`deploy-app.sh`'s last line says so).
   * **`.env.local`:** its `QED64_KERNEL_BUILD` names `~/code/wasm64-lean-kernel-build-v4.34.0`, which no longer
     exists, so for O the kernel build resolves to unset (verify #7 N/A; native and stage refuse). Suggested:
     `QED64_KERNEL_BUILD=$HOME/code/qed64-showcase-work/kernel-build-native64-v4.35:$HOME/code/qed64-showcase-work/kernel-build-native64`
     (`.env.local` expands `$HOME` throughout the value): it resolves O's build for O and the 4.34 build for H–N.
   * **Alias policy and stale tabs:** as in pin I's list (docs/REPIN-LOG.md, pin I, "Open decisions" 3–4), now for
     `widgets{7,8}.36d7f415704473d9`.
   * **Old stores:** whether to keep N's and H's build stores (runtimes `5650321f`, `3ab1c6a9`), `$W/mathlib4` and
     `$W/kernel-build-native64` while N or H is a rollback target.
3. **Follow-up (ours, design):** move the staged trees, their reports and the native build record into per-runtime
   stores (`$W/runtimes/<bid>/`, as the bakes already are), so alternating pins needs no restage; today the provenance
   records make the sharing fail closed (an older pin's lanes refuse O's trees), and restaging an older pin needs that
   pin's branch (its native delta lists).
4. **Upstream, drafted, not sent:** an FYI on the node 26.3 exit deadlock (docs/UPSTREAM-REPORT-QED64.md, last section;
   the user relays it). The pack-manifest URL question in that section is superseded by release routing.

## Pin J `5e63edd` (history, 2026-10-10; J retired 2026-10-27): active and gated then; the evidence runs, the commit, then the user's decisions

**Where it stands (2026-10-10 ~05:30Z).** The live site serves pin H `bf9d947` (deployed 2026-10-08 19:20Z by the qed64-deploy run on the push of `d60b15e` to main, Worker version `29176b6f`; its 93 R2 objects were E's, nothing was uploaded). This checkout's active pin is J `5e63edd`
(since 2026-10-09 ~18:55Z, first as a staged test pin): QED64 main since ~20:30Z, a fast-forward of
`fix/stack-probe-headroom` = I `385a1ac` plus `lean.worker.js` setting `LEAN_WASM_STACK_PROBE_SLOTS=8192` at preRun
(HARDENING #67, QED64's interim for the kernel-0036 regression). Same runtime `wasm64-f69cca24d0878a58`, overlays
(`widgets{7,8}.f69cca24d0878a58`), main bundle and stock snapshots as I; lock `a6d481b782d9…`, gallery
`65279b0b4c27aa9f…`, shell `shell-f4c57699a033beda`. I stays registered as the record of the regression (DistLens
`pmf_num` clicks fail "stack is exhausted" in Chrome), superseded, not deployed. The work for I and J is uncommitted on
the local branch `qed64-pin-i` (based on H's `d60b15e`), not pushed. Evidence: docs/REPIN-LOG.md, pin I entry, "Pin J".

**Done (logs `$W/logs/pinJ-*.log`, chain log `pinJ-chain.log`):** `verify` OK (#7 N/A), `pin check --full`, shell from
source 60/60; smoke 23/23; `j-dl1` (W8, C20, C22) 3/3 with C20 135/135, DistLens 21/21; **VERDICTs `j-full1`** (19:37Z)
**and `j-full5`** (2026-10-10 00:51Z), 34 passed + C19 skipped each (red: `j-full2` C10 crash, `j-full3` C3 10.67 GB,
`j-full4` C3 10.50 GB and a C21 crash); `j-c20-1/2/3` 135/135 each (405/405), DistLens 21/21 each; `j-headed1` red (C3
10.51 GB, C10 crash), then **`j-headed2` HEADED SIGN-OFF 35/35** (03:35Z); the **10 Mbit/s / 40 ms first visit** through
`throttle-proxy.mjs` on `:5297`/`:5298` (`:5197` was taken by another project's vite server): `RESULT PASS`, ready at
565.1 s (H 565.6 s), 693.1 MB at 9.8 Mbit/s, progress visible in 563/564 samples, 0 error-card samples, no crash;
`deploy-manifest --check` OK (G2 → `j-full5` on gallery `65279b0b…`, lock `a6d481b7…`, overlays widgets8/widgets7; 95 R2
objects, 2.420 GB); `--record-verdict` wrote `infra/ux-verdict.json` naming `j-full5` (to be committed); **`j-c11h3`**
(C11 headed ×3, QED64's #63 ask) 3/3. The C3 memory A/B (H, I, `58ae6d2` guard off, J; 5 interleaved rounds) found no
runtime offset. **The crash finding (the kernel session):** the C10/C21 crashes of `i-full2`, `j-full2` and `j-full4`
were a PartitionAlloc OOM inside Chrome's DevTools protocol, caused by Playwright's tracing fetching every response body
(QED64's 1.27 GB snapshot included), a harness artifact; tracing is now off (`UX_TRACE` opts in). The two A/B crashes
were V8 OOMs at 31 Workers (the #55 cage) and read as chance across arms (docs/REPIN-LOG.md "The crash classification and
tracing").

1. **Running:** QED64's evidence run `j-c10x20` (C10 ×20, tracing off; `$W/logs/pinJ-ux-c10x20.log`, chain
   `$W/pinI/chainJ5.sh`). **Queued after it:** the pool-growth chain `$W/pinI/chainPG.sh` (8 interleaved rounds of the
   local measurement pins `27a4ba6` = J + QED64's #68 restart wait + a `[pool]` diagnostic, `0ff314c` and `3b804ea` =
   the same with parking 8 and 4; C3 + one C10 storm each, tracing off) for QED64 and the kernel; no results yet. The
   measurement pins (`58ae6d2`, `349b1b7`, `27a4ba6`, `0ff314c`, `3b804ea`) are never committed and are removed after
   their runs.
2. **Ours, next:** commit this work on `qed64-pin-i` (`pins/385a1ac/`, `pins/5e63edd/`, `infra/ux-verdict.json` → `j-full5`,
   the suite's tracing change); then, on that commit, the qed64-static CI mirror (`node ci/run-local.mjs --job
   qed64-static`) and `ci/rehearse-deploy.sh` with the `old-shell` scenario (E1's evidence). Add the `j-c10x20` tally
   and the pool-growth results to docs/UPSTREAM-REPORT-QED64.md when they exist.
3. **The user's decisions** (docs/REPIN-LOG.md, pin I entry, "Open decisions"): **E1**, how to deploy a runtime change
   (J replaces E's runtime): accept the window in which phase 3 has replaced the live stock and profile indexes before
   the new Worker is live, split the upload by hand with `PHASES=` and `ALLOW_PARTIAL_UPLOAD=1`, or change the CI
   published check, which compares the phase-3 indexes and so refuses a split upload. QED64's own DEPLOY.md says the
   first #64-reading shell goes out on the already-served pairing, or the indexes go up right after the deploy; none of
   our #64 pins is on E's runtime. **Pushing `qed64-pin-i`** (a push to `main` touching `qed64-showcase/` is a deploy),
   and **whether to merge and deploy H first** (E's runtime, no index window). The **alias policy** (gallery-only, so
   bookmarks of `/?snapshots=snapshots/widgets8` fail after a `f69cca24` deploy as a named unpaired error; or a Worker
   redirect); a **"site updated, reload" card** for stale tabs, now or later; **H's verdict record** (the committed one
   names `h-full4`, stale for a redeploy of H with this gallery code); **R2 growth** of about 762 MB per runtime (J adds
   nothing over I). The upload, the push and the deploy each need an explicit yes.
4. **Upstream, waiting:** kernel patch **0038** (the real 0036 fix: probe four times as often with a quarter of the
   headroom) waits for the user's OK in the kernel session; it means a new release, a QED64 promote and a re-pin with the
   full gate (TwoDice stays a browser regression case). QED64's **#68** (a page that replaces its own runtime waits for
   all of its Workers) was then the branch `fix/own-predecessor-wait`. It landed on QED64 main in `e8e6698`, pin O
   includes it, and QED64's F1 (`b9a222c`, in `fd95a2a`) deletes it again, so no re-pin waits for it.
5. **Follow-up: a Chrome-budget headless lane** (the kernel session's guidance, 2026-10-09): run E3's persistent path
   through the toolchain package's `snapshot-probe.mjs` (from the next kernel release QED64's
   `pipeline/snapshot/snapshot-probe.mjs`: the package drops its copy, kernel `408859aed0`, D4 (a); 2026-11-01)
   with `LEAN4_WASM64_PTHREAD_STACK_MB=0.68` (Node 0.68 MB = a macOS
   Chrome Worker; chrome-headless-shell measured within 1 % of it). The probe honours the knob only from kernel
   `0249065cc0` (release `-r3`, not yet published), and on runtime f69cca24 `lean_wasm_compile` starts with
   `Elab.async` off, so the probe file needs `set_option Elab.async true` for the proofs to run on the sized Workers.
   The one-shot equivalent is the package's `node-runner.mjs` with the same knob (the kernel gate's own setting).
   **But it would not have caught the 0036 case:** the kernel session ran the TwoDice proofs that way (Workers at
   0.68 MB, `Elab.async` on, our widgets8 snapshot) and they compile at every guard setting; the browser's FileWorker
   path starts deeper than the compile path. A headless Chrome-budget lane undercounts, so the browser gate (C20/W8)
   stays the judge.
6. **This host:** `.env.local` names the kernel build dir that another session deleted on 2026-10-09 ~12:48Z, so
   `pin-qed64.mjs verify` needs `QED64_KERNEL_BUILD=` here (then `#7` prints N/A) until the dir is rebuilt or the user
   updates or clears that line (rebuild-only inputs). `pin-qed64.mjs pin` now carries the native toolchain record from
   the active pin's lock when `QED64_KERNEL_BUILD` is unset.
7. **Optional:** record `servedTrees.baseSlimDigest` and `coreDigest` in `pins/385a1ac/pin.json` and
   `pins/5e63edd/pin.json` so the G0 tree check runs instead of printing SKIP; the Docker tag's `DRIFT #7` (now
   `0de79b891eb9`, the e1a79c1 release's image) stays unacted on while nothing native runs.


**History (2026-10-16): pin N `58ebbad` (runtime 5650321f, the kernel release lean-v4.34.0-53cb11e) was active and
gated** (docs/REPIN-LOG.md, pins L and N). K `62a06e2` stays committed and gated on runtime f69cca24. Open then: the push
(the user's; it would have deployed N), the E1 upload order, a `baseSlim` that does not point into QED64's scratch work dir.

**Next pin, revised (2026-10-12, the user's decision relayed by QED64):** stack-limit failures will be handled by a
QED64 library backstop (on a real engine-stack crash: the relay pauses after the FIRST death, `lastDeath.cause.code =
"ENGINE_STACK_OVERFLOW"`, one note diagnostic from source "QED64" at the line being checked, a stock-page pill, any edit
resumes), not by tuning Lean's stack: QED64 withdraws #67's 8192 probe and leaves the runtime default 16384. For the
showcase that means C20/W8/C22's DistLens links fall back to about 13/21 (the `twoDice 1…8` examples end in misleading
`ennreal_num: cannot close …` errors under sync elaboration, measured on `6fa2a16`), which the user accepted ("sometimes
it's better not to solve every issue so that the overall architecture is simpler"). The new candidate tip comes from
QED64 once gated; stay on J until then. **Our side needs a decision before that pin can get a VERDICT**, because C20, W8
and C22 require every DistLens link to elaborate cleanly and the descriptor's `knownLimitations` is text only (nothing
reads it): (a) a per-pin list of expected-failing links (descriptor field, read by C20/W8/C22, fail-closed: exactly
those links may fail, with a matching message, and nothing else), or (b) change the DistLens demo's generated examples to
stay under the stack limit (for example a shallower tactic than `unfold …; pmf_num` for `twoDice`), which keeps the suite
strict but changes the widget package. Also: the gallery's soft card may key on `ENGINE_STACK_OVERFLOW`, and
`tests/ux/selectors.json` needs the new note text (QED64 will send the exact strings).
**Resolved the same day with (b)** (the user: "go ahead with the DistLens tactic change"): `pmf_num`/`ennreal_num` became
elaborators (`6b31bba`), and on pin K (`62a06e2`, QED64 main with #71's 16384 and #72's backstop) DistLens is 21/21 in
the browser (`k-dl5`, `k-dl6`; no #72 pause in any run, so no soft card or allowlist entry was needed). K's entry in
docs/REPIN-LOG.md has the build, the C22 (3) change for sync elaboration and the gate.

**Next pin (2026-10-10):** QED64's recommended next main is `ebfb039` (branch fix/keep-probe-8192; its code is
byte-identical to `8f29630`, which the showcase already timed: DistLens 21/21 ×5, C20 5–8 % faster, ~0.6 GB less
renderer memory, no pool growth; docs/REPIN-LOG.md pin I entry, item 3b). Same runtime f69cca24, so the re-pin needs no
rebake: register the main SHA once the user ships it, the shell from source, `pin check --full`, then the browser gate.
The alternative QED64 measured, `6fa2a16` (probe back to 16384), would cost 8 of the 21 DistLens examples with misleading
`ennreal_num` errors.

## Pin I `385a1ac`: superseded by J on 2026-10-09 (the kernel-0036 regression record)

I (QED64 main on the kernel fork's release `lean-v4.34.0-e1a79c1`, runtime `wasm64-f69cca24d0878a58`, with QED64's #62,
#63 and #64; the first pin with per-runtime overlay directories) was the active pin from 2026-10-09 ~13:10Z. Its static
and headless gates were green; its first full run `i-full2` (17:36Z) was red on kernel patch 0036's engine-stack probe:
9 DistLens `twoDice … pmf_num` clicks (C20), W8 and C22 failed in Chrome with "the WebAssembly runtime's stack is
exhausted", while H's runtime passes the same clicks 21/21 (docs/REPIN-LOG.md, pin I entry, "The regression"; repro
`$W/pinI/repro-0036/`). #62, #63 and #64 held in that run. Its C10 crash was the tracing artifact above. Nothing is left
to do on I: it stayed registered, not deployed (`pin use 385a1ac` reproduced the regression; *historical*: I is retired since
P1, at the tag `pins-history-2026-11-07`).

## Pin H `bf9d947`: gated; superseded locally by I on 2026-10-09

**Where it stood (2026-10-08).** The live site serves E `33b0967` with the pre-v1 gallery, deployed 2026-10-05. This
checkout's active pin was H `bf9d947`, QED64 **main** (G `5c327c2` plus QED64's fix for the keep-alive starvation our C22
found on G), from 2026-10-06 ~20:03Z to 2026-10-09; G and F were staged. H is gated in the browser (docs/REPIN-LOG.md, pin H entry):
v1 smoke 22/22, VERDICTs `h-full1b`, `h-full3`, `h-full4` on gallery `d8a5bb6d…`, `C20` 135/135 in three runs, the
headed sign-off `h-headed2` (35/35), `deploy-manifest --check` OK, and `infra/ux-verdict.json` naming `h-full4` (the
record the CI deploy accepts). Three other runs each lost one test to a renderer crash during a QED64 boot, QED64's #55
residual (docs/UPSTREAM-REPORT-QED64.md "#55 residual"); the gallery's own heap share is about 65 MiB (`heap-share-1`).
Everything is committed on the local branch `qed64-embedding-v1` (`1c22222`, `d791b20`, `bd42150`), which is **not
pushed**.

1. **Done:** the proxy-shaped 10 Mbit/s first visit on H (`h-throttle-t10p`: ready at 565.6 s, no error card; the earlier
   `h-throttle-t10` throttled only the page through CDP, so the workers' downloads were not slowed and it verifies the boot
   UI only) and `ci/rehearse-deploy.sh` on `bd42150` (docs/REPIN-LOG.md, pin H entry).
2. **Done:** `node ci/run-local.mjs --job qed64-static` on `bd42150` (JOB SUCCESS, 12/12 steps) and the seven deploy-rehearsal
   scenarios (`REHEARSE-DEPLOY OK`).
3. **The user's decisions:** push the branch `qed64-embedding-v1`, then the
   deploy (the `qed64-deploy.yml` dispatch from GitHub, or `scripts/deploy-app.sh` locally). A deploy of H changes only
   the Worker and its assets: its 93 R2 objects are the live ones (same runtime and overlays). Fallbacks: G
   (`pin use 5c327c2`, one VERDICT, its keep-alive scenario), F (`pin use 84d594e`, no UX run), E (`pin use 33b0967`,
   legacy mode, live). *Historical:* those pins and the legacy mode are retired since P1 (tag `pins-history-2026-11-07`).
4. **Optional, ours: measure HARDENING #59 on H** (QED64 reports it fixed by `e4cffcc`, which G and H carry): type at
   150 ms/char above a slow `#eval` with the InfoView open, and compare the pool size and the absence of a crash.
5. **Docker tag drift, again (not acted on).** `qed64-toolchain:emsdk-6.0.5` now names `5708c2dbf5a1` (the kernel
   session's rebuild for its patches 0036/0037, per QED64), so `verify` prints `DRIFT #7` on H (`$W/logs/pinH-verify.log`).
   Rebuild-only: served artifacts are unaffected, and only `showcase.sh native` refuses. §1 says how to decide it.

## When QED64 publishes: the re-pins we owe (in this order)

* **#62 and #63: done as pin I** (`385a1ac`, with #64 too; registered 2026-10-09) **and gated on its successor J**
  (`5e63edd`, the same fixes; the section above). The UX suite asserts them on I and J through the descriptor's
  `hardening` flags (C9, C11, the network oracle).
* **QED64's #68: no re-pin is owed.** It landed on QED64 main in `e8e6698`, pin O includes it, and QED64's F1 (`b9a222c`, in
  `fd95a2a`) deletes it again. **Kernel patch 0038**, if the kernel session still wants it after 0040/0041 (docs/REPIN-LOG.md), would be a re-pin
  with the full gate once it is on QED64 main.
* **The next kernel release (expected with the v4.36 import; the kernel session's heads-up, 2026-11-01):**
  * the FileWorker's refused-header text becomes generic: it drops `use "Load exact imports"` and keeps
    `are not loaded in this session`. C7 (`tests/ux/specs/30-robustness.spec.mjs:97`) compares the whole text, so it
    must match the substring by then. That change goes in the P1 and P2 gate (top section), whose fresh G2 verdict covers
    it (the owner's OK);
  * the `lean4-wasm64` package no longer ships `snapshot-probe.mjs`, `bake-snapshot.mjs` or `snapshot-index.mjs`
    (kernel `408859aed0`, D4 (a)). Our scripts already use QED64's `pipeline/snapshot/` copies; only the step-5
    lane above named the package's probe.
* **QED64's D1 (retiring "Load exact imports"):** QED64 sets `capabilities.offers` to false (its `main.ts:33`), and
  C16 is rewritten on that flag in the re-pin that carries it ($W/reports/r1-review-showcase-2026-10-30.md).
* **Our steps 5 and 6** ("heavy path from a fetched release" and "drop the submodule and the source build") **and P7
  "Later" (pin a published bundle): dropped (D11).** QED64 is retiring its release bundle (`39dee02`, in `fd95a2a`). The submodule and
  `scripts/build-shell.mjs` stay. P7 "Now" (the lock's file list from QED64's `release-manifest.mjs --commit <pin>`, QED64's
  `fetch-artifacts` for the `public/` half) rides the re-pin: D2 is pushed, and O's own tools are still from before it. What remains from the earlier plan:
  * our R2 copy of the runtime and packs collapses onto the release's prefix: that is P3, top section (`lean4-wasm64/lean-v4.35.0-b081e7c/` at O);
    `/profiles/index.json` and `/snapshots/*` stay site-owned under `qed64-showcase/`;
  * done for pin I: `pin-qed64.mjs` reads the kernel from QED64's tracked `toolchain/lean4-wasm64-release.json`
    (`kernel.commit`, schema `lean4-wasm64.release/v1`) where it exists and falls back to `KERNEL-PIN` for older pins;
  * done for pin I: `scripts/check-gallery.mjs` reads the Memory64 probe from `public/workers/memory64-probe.js`, and
    `deploy-app.sh` requires `workers/memory64-probe.js` when the staged `lean.worker.js` loads it.
* **The toolchain-fork pointers: done with pin I** (QED64 `385a1ac` has no `pipeline/toolchain/build.sh`,
  `KERNEL-PIN` or `pipeline/toolchain/work/`). `scripts/showcase.sh` (the `docker_image_guard` comment and the stage1
  hint, which now names the release from the pin's record and the `cli.mjs fetch … --only runtime` command), README.md
  "Re-pin" and "Docker tag drift", scripts/headless/README.md and docs/BUILD-FROM-SOURCE.md name the release route for
  pin I on and keep the `pipeline/toolchain/work/` route for pins up to H. Pin I's stage1 and core library came from
  the release `lean-v4.34.0-e1a79c1`.

The audit ran six rounds on F and G (docs/REPIN-LOG.md, pin F entry for rounds 1–4, pin G entry for rounds 5–6), and
the first real runs on G added the `g-full1b` fixes (pin H entry). One residual from the audit: `classify()` in
`tests/ux/lib/qed64.mjs` has no unit test, so its emptyErrors change was checked by `node --check` only. The cancel
console entry, a fail-closed pre-allowance at the time, has since matched in every full run on G and H.

**On QED64's side:** our release-bundle asks are dropped with D11. The `qed64/edge` export they named is what P3 uses, as
`createWorker` from `deps/qed64/infra/edge-worker.js`. The #55 residual's margin is QED64's kernel side (a pool-size knob, a
smaller glue). HARDENING #59 is fixed per QED64 and not measured by us.

## Pins A–E (history and what is left on E)

**Current state is printed by commands, not written here** (a written run name or count goes stale with the next run):

* `scripts/showcase.sh pin list`: per pin, the full UX runs on its lock, the VERDICT count and last VERDICT, the HEADED
  SIGN-OFF count and last sign-off;
* `scripts/showcase.sh gallery`: the gate, the current gallery content sha256, and `UX CURRENT …` (the newest verdict on
  exactly this gallery + lock + overlays, plus a headed sign-off if there is one) or `UX STALE`;
* `node scripts/deploy-manifest.mjs --check`: the `G2 UX:` line a deploy relies on;
* `scripts/showcase.sh verify`: pins, sources, stores (the Docker drift of §1 was resolved on 2026-10-04 and is back since 2026-10-06).

*History (dated, not current state).* At the end of the final docs lane (2026-10-03 ~03:50Z) pin C `5ac5d00` was
served on gallery `921b0b6a…` with verdict runs on it, no headed sign-off on it, `verify` OK with 1 Docker `DRIFT`, and
D `3b42714` staged (logs `$W/logs/finaldocs-*.log`, `$W` = the work dir, `QED64_SHOWCASE_WORK`). The boot-fix
lane (2026-10-03, ~05:00Z) then changed `gallery/gallery.js` (§4, slow first visits), so those verdicts no longer apply
to the current gallery. Its own three full `ux` runs on the new gallery were one red (one W4 renderer crash, cause
unknown, not reproduced in 20 W4 repeats) then two VERDICTs (docs/UX-RESULTS.md "Boot-fix lane"). The closure lane
(2026-10-03, 09:15Z onward) then ran two more full `ux` runs, both VERDICTs, and a headed sign-off on the same gallery
`31f6d8d9…`. It also re-ran the throttled first visits, a 60-minute soak and the deploy rehearsal there, and fixed three
test-tool defects (a sim-gallery timing race, G1's missing failure detail, byte reordering in `throttle-proxy.mjs`).
Details are in `out/ux/closure/RESULTS.md`. The pin-e lane (2026-10-04) then stormed E against C, switched the served
pin to E `33b0967` and gated it there (two verdicts, a headed sign-off, the 10 Mbit/s first visit, the deploy check and
rehearsal; `out/ux/pin-e/RESULTS.md`). §2 and §4 say what is still needed.

**L9 V2 could not be fixed from `gallery/`, and the fix came from QED64** (v2-embed lane, `out/ux/v2-embed/RESULTS.md`:
the extra V2 on the visitor's path comes mainly from running the stock page in a same-origin iframe at all). QED64's
HARDENING #55 is in the served E. Our storms on E are consistent with it but do not confirm it (§2).

## 1. Docker image drift: resolved (2026-10-04, R2 lane)

The tag `qed64-toolchain:emsdk-6.0.5` now names `8228ea564e7b`, while the lock recorded `8b6698bbf474`, the image that
built the native oleans. The R2 lane rebuilt all 512 native modules in the current image in a scratch copy of the
Mathlib tree. All 7,616 output files are byte-identical to the originals, so every lock now records `8228ea564e7b`
under `toolchain.docker.equivalent`, `verify` prints no DRIFT, and `showcase.sh native` accepts the image
(docs/BUILD-FROM-SOURCE.md "Docker image drift", docs/REPIN-LOG.md R2 entry). If the tag moves again, the same
experiment decides it. *Exception (2026-10-05, resolved 2026-10-06):* pin F's lock was first generated without that `equivalent` record, so
`verify` printed the DRIFT again on F. `scripts/pin-qed64.mjs pin` now carries the record forward from the pin's previous
lock or from any registered pin's lock. F's lock got it back, and G's lock has it, so `verify` prints no DRIFT on either.
*Again (2026-10-06, open):* the kernel session rebuilt the tag (`sha256:5708c2dbf5a1`, for its patches 0036/0037 per
QED64), so `verify` prints `DRIFT #7` since 2026-10-06 (~18:36Z, first seen while G was active; on H:
`$W/logs/pinH-verify.log`); the same experiment decides it (top of this
page, item 5).

## 2. Confirm QED64's #55 on our side, in a high-rate window (optional)

The pin-e lane's storms (2026-10-04) had E 0/20 vs C 0/20 headed and 0/8 vs 1/8 in headless-shell on `/showcase/#hasse-view`.
That is enough to serve E (it is not worse than C), but not to show that #55 removes V2, because C was nearly clean in
those windows (it was 15/24 the day before). To confirm the fix:

1. Wait for an idle host with 20 GB or more reclaimable. On 2026-10-04 the desktop apps kept it at about 15 GB; the
   v2-embed lane had 20.7–22.9 GB.
2. Serve C on its own port, and the active E as well: `SHOWCASE_PIN=<id> GALLERY_DIR=<pin-gallery copy> PORT=<port>
   scripts/serve-start.sh`, with copies from `$W/final-gate/pin-gallery.mjs`.
3. Re-run `$W/pinE2/master2.sh hd:1-4 hd:5-8 …` with `QUIET_GB=20` and the ports in `$W/pinE2/run-arm.sh`. It queues FIFO
   for the lock and takes the 300 s quiet streak inside the hold.
4. E is confirmed if C shows its usual rate (around 1 in 2) while E stays near 0.

Other pins: D `3b42714` (E's runtime with the #52 worker only) and A stay staged; C is the fallback (`pin use 5ac5d00`,
then two `ux` runs on the gallery that produces). *Historical:* A–L are retired since P1 (tag `pins-history-2026-11-07`);
the local fallback is N `58ebbad`.

## 3. Pin the widget sources to a git commit, and add a `widgets-sync` command (pending the user's decision)

**Today.** `$W/widgets-src` is an rsync export of the `widgets-v4.34` working tree, made on 2026-10-01T02:50Z. It
excludes `.lake`, `.git`, `showcase/site`, `*.log` and `.DS_Store`, and holds 251 files. Every lock records its hash,
`WIDGETS_SOURCE_HASH` `16cdb73b…`. The export is tied to a hash, not to a commit.

This lane re-hashed the live tree read-only (`$W/logs/finaldocs-widgets-src.log`):

* The live tree is still identical to the export: 251 files, the same `SOURCE-FILES.sha256`, hash `16cdb73b…`.
* `git archive HEAD` would not reproduce the export. HEAD is `c812b91e` ("functioning widgets", 2026-09-30), and the
  working tree differs from it in four ways:
  * 55 tracked files are modified.
  * 8 `PORT-NOTES.md` files are untracked.
  * `.github/workflows/pages.yml` is in the export but ignored by `.gitignore`.
  * The tracked `showcase/site/*` files are left out of the export.

**Proposal (not implemented; it needs the user's decision and a commit in `widgets-v4.34` by the user, because this
project never writes there):**

1. Commit the ported widgets in `widgets-v4.34`.
2. Pin that commit in each lock (`WIDGETS_SOURCE.commit`).
3. Produce `widgets-src` with `git --no-optional-locks archive <commit>`, keeping the same exclusions, and check that
   its hash equals `16cdb73b…`. If it does, nothing is rebuilt.
4. Add `scripts/showcase.sh widgets-sync [<commit>]`, which:
   * re-exports the commit into a new directory;
   * compares hashes;
   * reports "unchanged", or lists the changed packages and the steps they need: native widgets, then stage, bake,
     overlay, headless, gallery, and two `ux` runs;
   * never switches automatically.

## 4. Deploy (owner)

Publishing needs the owner's Cloudflare account. Step by step: the **first deploy checklist** in
docs/DEPLOY-CLOUDFLARE.md (repository secrets, token scope, local artifact upload, first deploy from GitHub Actions or
from this machine, `SHOWCASE_ORIGIN`, verification); the GitHub Actions deploy (`.github/workflows/qed64-deploy.yml`)
was rehearsed in fresh clones by `ci/rehearse-deploy.sh` (R3 lane, 2026-10-04). The kit was rehearsed against local
fakes (history: on pin C by the post-audit fix lane on gallery `b7aa521a…`, 2026-10-03; on pin E by the pin-e lane on
gallery `bbdbc932…`, 2026-10-04, `rehearse.sh all`, `browser` and `stop` rc 0). Re-run
`scripts/deploy-rehearsal/rehearse.sh all` and `rehearse.sh browser` on the gallery you deploy. Never deploy pin B.

These owner decisions come before a public deploy. Each is measured in `out/ux/last-mile/RESULTS.md`:

* **Verdicts on the current gallery.** The gallery to deploy needs two full `ux` runs that are VERDICTs on it
  (`scripts/showcase.sh ux`, twice); `showcase.sh gallery` then prints `UX CURRENT`, and `deploy-manifest --check` G2
  names one. Check those commands for the current state. Also read `node scripts/ux-tally.mjs` for red full runs on
  the same gallery BEFORE the verdict: G2 reports only later ones (history: the boot-fix lane's `bootfix-full1` had a
  W4 renderer crash of unknown cause before its two verdicts; docs/UX-RESULTS.md "Boot-fix lane").
* **A headed sign-off on the gallery that will be deployed.** `pin list` prints the last HEADED SIGN-OFF per pin, and
  `showcase.sh gallery`'s `UX CURRENT` line names one when it is on exactly this gallery. Command:
  `UX_HEADED_ALL=1 UX_WARM_PROFILE=$PWD/out/ux/profiles/ux-warm-headed scripts/showcase.sh ux`. (History: none existed
  on `921b0b6a…`, and none on the boot-fix gallery `31f6d8d9…` as of that lane; the closure lane then recorded one on
  `31f6d8d9…`, 34/34 with C19, `out/ux/closure/RESULTS.md` (2).)
* **Slow first visits: fixed (boot-fix lane, 2026-10-03; on E also QED64's #54 boot card), one residual.** The boot wait re-arms on progress, shows
  "Still downloading …" instead of the card, and a later `ready` closes a stall card (gallery/README.md "Timeouts").
  Re-test after any gallery or pin change: `node tests/ux/tools/throttle-proxy.mjs --listen 5198 --upstream <serve
  port> --mbps 10 --rtt 40`, then under the lock `node tests/ux/tools/throttled-first-visit.mjs --origin
  http://localhost:5198 --no-cdp --mbps 10 --rtt 40 --max-s 1200 --tag <tag>`; pass = rc 0 and `RESULT PASS` (since
  the post-audit fix lane the tool judges itself: ready, no crash, `console ok`, no error card at all or at the end,
  visible progress after the first 5 s, panel EQUAL to its golden; rc 1 and `RESULT FAIL: <why>` otherwise; a deliberate
  stall test passes `--expect-card`). Use the proxy as fixed by the closure lane: the
  earlier version could reorder bytes within a connection, which once corrupted a snapshot download at 50 Mbit/s
  (`out/ux/closure/RESULTS.md` (3)). History: the closure lane's re-test on `31f6d8d9…` was 10 Mbit/s ready at 565.1 s
  and 50 Mbit/s at 120.3 s, both with no error card. On E (pin-e lane) at 10 Mbit/s: `RESULT PASS`, ready at 565.1 s,
  with QED64's card until ready and the gallery's notice from 467 s. The 50 Mbit/s run was not repeated on E. Residual, not measured: below about 3.2 Mbit/s (the widgets
  region's 365 MB download in 900 s) QED64's own snapshot prefetch gives up after 900 s and the checker streams the
  snapshot without progress events (inferred from the bundle); the gallery could then show its stall card after 240 s
  without progress, which still closes on a later `ready`. Measuring it needs a run of about 50 min at 2 Mbit/s.
* **Branded Chrome.** `lastmile-chrome-headed2` (Chrome 154) passed 32/34. Its C13b needs a headed baseline per
  browser build. Its C10 settles at 10.67–10.75 GB, over the 10.5 GB line; Chrome for Testing 151 settles at
  10.07–10.26 GB.
* **Memory threshold.** The texts ask for 16 GB of RAM, but the soft warning still triggers below 8 GB (`lib.js`
  `MIN_DEVICE_MEMORY_GB`). Raising it changes three tests and voids the verdicts.
* **Safari.** One-time user action: Safari → Settings → Advanced → "Show features for web developers", then Developer
  → "Allow remote automation". Then re-run `tests/ux/tools/safari-probe.mjs` (command in
  `out/ux/last-mile/RESULTS.md` (3)). Until then, the claim that Safari gets the capability card is an inference from
  JavaScriptCore.

## Pin E `33b0967`: what is left (E stays the live pin until a v1 pin, H or a fallback, is deployed)

E was registered by the pinE lane and gated and served by the pin-e lane (2026-10-04; docs/REPIN-LOG.md "pin E gated";
`out/ux/pin-e/RESULTS.md`). The current state comes from `pin list`, `showcase.sh gallery` and `deploy-manifest --check`.
Not done yet:

* **Three `ux --grep "C20 "` runs on E** (the D/C gate had them). C20 passed 135/135 inside each of E's three gate runs,
  but there is no separate C20 tally on E yet: `UX_RUN=<name> scripts/showcase.sh ux --grep "C20 "`, three times.
* **The 50 Mbit/s first visit on E** (§4 has the command, with `--mbps 50`).
* **#55 in a high-rate window** (§2).
* **Owner choice (optional):** on E the gallery's "Still downloading" notice (from 467 s at 10 Mbit/s) repeats what QED64's
  own boot card already shows. Suppressing it while `#boot` is visible would be a `gallery.js` change. It would void the
  verdicts and need its own gates, sim runs and throttled re-test. It was not made.
