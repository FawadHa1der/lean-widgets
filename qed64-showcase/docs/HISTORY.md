# History: the lane-by-lane record behind README.md

README.md is a status page. This file keeps the lane-by-lane record it used to carry, **verbatim as of the end of the
multi-pin lane (2026-10-02, about 09:00Z)**, so nothing that was claimed and evidenced is lost. Statements here such as
"the current pin" or "now" mean the pin and gallery of the lane that wrote them, which the text names. The tallies
across all lanes are recomputed by `node scripts/ux-tally.mjs` from the recorded runs; where a running tally below
disagrees with it, the tool is right (docs/UX-RESULTS.md "Tallies" lists the corrections). Later lanes append below.

Pins in this file: A = QED64 `1859b83` (runtime `wasm64-4b025db7729c5f89`, the first pin, called "the previous pin" or
"the old pin" after 2026-10-01 20:35Z), B = `9fdf9b8` (runtime `wasm64-2c18773ecfba45bb`, "the current pin" or "the new
pin" from the re-pin until the multi-pin lane), C = `5ac5d00` (runtime `wasm64-4b025db7729c5f89`, served since
2026-10-02). Paths `release/wasm64-…/` became `release/<pin id>/` in the multi-pin lane.

## 2026-10-02, docs lane (status page, tallies, gallery polish)

* README.md became a status page; this file took the history below.
* `scripts/ux-tally.mjs`: the one source of the run tallies (read-only, from `out/ux/<run>/`, the
  `showcase-ux-runs.jsonl` records and the reload-storm files). Corrections it forced are listed in docs/UX-RESULTS.md
  "Tallies".
* Gallery polish (critic minors): plain-language status line (the technical line is its tooltip and
  `__showcase.status().statusLine`), no "phase 2" card badge, card hints say "draws a diagram" instead of SVG element
  counts, the rail footer and an error card lost internal jargon. Four C13 gallery baselines were re-approved on
  purpose (viewed). Results and the verdict run: docs/UX-RESULTS.md "Docs lane".

## Where QED64's trees were (the untouched check), as of 2026-10-01

Nothing under the QED64, kernel or lean4game trees is ever written. Every build stage ended with
`scripts/assert-untouched.sh check <stamp>` → `VERDICT: UNTOUCHED`. Since late morning on
2026-10-01 the check reports `CHANGED` for any stamp, because other sessions (the QED64 owner's
own work) commit in those trees. For example, at 14:30 EDT on 2026-10-01 the kernel's HEAD was
`6e28e4bd9d` (after `9fbb45afcb` → the patch 0035 draft `9af8a865` → `6b3a491f76` → `3ae65d36f9`),
and QED64's HEAD was `6833342` (the owner's liveness work, 13:07–13:18); at 16:33 EDT it was the promote
`9fdf9b85`, which is now the pin. `git --no-optional-locks -C <tree> log` shows where they are now. The pin does not
move with them: the showcase serves its own verified clone of the pinned commit.

## Results table, as of the end of the multi-pin lane

| What | Where | Result |
|---|---|---|
| Multiple pins keyed by QED64 commit; pin C `5ac5d00` served, 2026-10-02 | [docs/REPIN-LOG.md](docs/REPIN-LOG.md) "2026-10-02", [docs/UX-RESULTS.md](docs/UX-RESULTS.md) "Multiple pins" | Three pins registered and hash-verified (A `1859b83`, B `9fdf9b8`, C `5ac5d00`; `VERIFY OK` each, new check #10: `dist/` workers == git). No file hardcodes a pin. C's gates: reload storm 6/6 without a crash; headless `CONTROLS PASS`; **`multipin-C-full2-b` and `multipin-C-full3-b`: 32 passed, 1 skipped, VERDICT, VERDICT** (C10 passed, C20 135/135); one earlier red run root-caused to QED64 N2. Switching rehearsed A→C→A→C and to B (see the REPIN-LOG). |
| Re-pin to QED64 9fdf9b8 / `wasm64-2c18773ecfba45bb` (QED64's L7 fix), 2026-10-01 | [docs/REPIN-LOG.md](docs/REPIN-LOG.md) | Pin verified, native oleans proven reusable (core library byte-identical), both bakes judged GREEN and paired, QED64's preflight OK on both overlays, stage 4 green, the gallery's liveness probe defers to QED64's own, D1/D2 still present (bridge kept). |
| Headless verification in the wasm runtime (Node, no browser) | [docs/HEADLESS-RESULTS.md](docs/HEADLESS-RESULTS.md) | See the breakdown below. |
| Browser UX (Playwright, the gallery on the real page) | [docs/UX-RESULTS.md](docs/UX-RESULTS.md) "Final verification on the 9fdf9b8 pin", [out/hang/FIELD-CAPTURE.md](out/hang/FIELD-CAPTURE.md), [docs/REPIN-LOG.md](docs/REPIN-LOG.md) §9 | **On the served pin C (`5ac5d00`), gallery `a4b34ead…`: two consecutive VERDICTs, `multipin-C-full2-b` and `multipin-C-full3-b` (32 passed, 1 skipped each; C10 passed; C20 135/135), and 3 C20-only runs, 135/135 each; `showcase.sh gallery` → `UX CURRENT` (docs/UX-RESULTS.md "Multiple pins").** The history on pin B (9fdf9b8) follows: one VERDICT (previous gallery), never two green runs (L9). **Close-out 3** (after the last audit, gallery `92027286…`, 2026-10-02): the probe's proof of life counts only frames from Lean (frames QED64's JS layer synthesizes, which keep flowing during a freeze, no longer count; `sim-gallery` run 11, mutant caught); new **C23** exercises the post-hoc record of a QED64-handled `wedged` reboot in the browser (a forced-death fixture) and found a harness bug that would have failed C20 on a real one (fixed); `deploy-manifest.mjs --help` no longer rewrites `out/deploy`. One full run, **`closeout3-full1`: 30 passed, 2 failed, 1 skipped, NOT A VERDICT**: C10 crashed the renderer at its second reload (L9) and C14 aggregates it; C20 135/135, C21, C22 (1)–(3) and C23 passed. docs/UX-RESULTS.md "Close-out 3". **Close-out 2** (after the final audit, gallery `7772c1eb…`, 2026-10-02): the liveness probe now takes QED64's own probe answers and any server frame as proof of life, so a saturated task pool is no longer restarted (new C22 (3): 24 parallel sleeping proofs, pool `unused 0`, 0 restarts; mutant without it caught in the browser); a 45 s card on a live checker reads "Lean is still working"; C21 (b) runs in its own browser (mutant with observe mode disabled now caught in the browser); C20 and W1–W8 accept a QED64 `wedged` reboot as handled upstream. One full run, **`closeout2-full1`: 29 passed, 2 failed, 1 skipped, NOT A VERDICT**: C10 crashed the renderer at a reload (L9, `chrome-headless-shell-2026-10-01-230148.ips`) and C14 aggregates it; every liveness test passed. docs/UX-RESULTS.md "Close-out 2". The final lane ran two full suites through `showcase.sh ux` on gallery `7bbddf2e…`, lock `bb97785a…` and the widgets7/widgets8 overlays, in consecutive lock windows. **`final-full1`** (2026-10-01 23:18–23:37Z): **31 passed, 1 skipped (C19), VERDICT.** **`final-full2`** (23:53Z – 00:17Z): **28 passed, 3 failed, 1 skipped, NOT A VERDICT.** The three failures were C10 (reload storm) and C21 (b) (the boot after a relay restart), each crashing the renderer, and C14, which aggregates them. These are **L9** crashes (EXC_BREAKPOINT on a DedicatedWorker thread, 43–45 DedicatedWorker threads). The gallery cannot handle a renderer crash. C20 was 135/135 in both runs, and QED64's own liveness took no action (0 rescues, 0 stalls, 0 `wedged` reboots). **Hang hunt:** 8 observe-mode C20 runs (1,080 clicks, 2,160 edits) found 0 hangs, 0 QED64 rescues and 0 captures (FIELD-CAPTURE.md). That is too few runs to prove L7 fixed at the old rate of about 1 in 20 runs. On this pin C10 crashed in 4 of 6 full runs, C21 (b) in 3 of the 5 where it shared a renderer with (a) (0 of 3 since), and W4 in 1 of 6. With the final audit's two C20 runs and close-out 2's, 13 C20 runs on this pin showed 0 hangs and 0 QED64 rescues. The last VERDICT on the previous pin was `closeout-full1` (31 passed, gallery `c8492b70…`). |
| Defects in the pinned QED64 page and runtime, for the owner | [docs/UPSTREAM-REPORT-QED64.md](docs/UPSTREAM-REPORT-QED64.md) | D1, D2, L1, N1, P1, L7 and X1 (the `_proc_exit`/`onExit` side bug), each with a repro or trace, file:line evidence and a suggested fix. |
| Static gallery gate | `scripts/showcase.sh gallery` ([gallery/README.md](gallery/README.md)) | Green at 00:37 EDT on 2026-10-02 (close-out 3, `work/logs/closeout3-gallery-gate.log`) on gallery content sha256 `92027286640ca6ed5be5a083ba5ca8269224415ec70e7ebc574d83ae90a379fe` (`node scripts/lib/gallery-hash.mjs`, the shipped gallery files): `BUILD-GALLERY CHECK OK 8 examples`, `CHECK-GALLERY OK 123 ok, 0 failed`, `SIM-GALLERY OK 84 ok`. Freshness: `UX STALE: no verdict run on this gallery + lock + overlays (last verdict: 2026-10-01T23:36:49Z on 7bbddf2e750c0fa2…)`, which is truthful: the only full run on this gallery (`closeout3-full1`) is red (L9). The freshness line and deploy G2 both name any later failed full run on the same gallery, lock and overlays (`scripts/lib/ux-record.mjs` `laterFailures`), and the release preflight refuses such a G2 line. Any later edit to a shipped gallery file changes the sha256, and this row then no longer describes the tree. Re-run. |
| Hosting on its own origin, the lean4game way (rehearsed locally, not deployed; step-by-step guide [docs/DEPLOY-CLOUDFLARE.md](docs/DEPLOY-CLOUDFLARE.md)) | [docs/DEPLOY-CLOUDFLARE.md](docs/DEPLOY-CLOUDFLARE.md) §Rehearsal, [docs/DEPLOY.md](docs/DEPLOY.md) | **Re-rehearsed green on the served pin C `5ac5d00`** (2026-10-02, gallery `a4b34ead…`; docs/REPIN-LOG.md "Deploy kit on the active pin"): `deploy-manifest --check` OK with `G2 UX: verdict run multipin-C-full3-b … was on THIS gallery`; staged assets exactly C's 75 (the old shell's bundles gone); `rehearse.sh all` + `browser`: `GUARD OK`, `FAKE-BUCKET OK` 93 objects, `FAKE-S3 OK`, rollback and deploy-dry refusals, `SMOKE OK` 168 URLs, `BOOT-CHECK OK`. Deploy labels and the CI tarball now carry the pin id. Earlier: **Rehearsed green on the current pin with the previous gallery** (`wasm64-2c18773ecfba45bb`, gallery `7bbddf2e…`, before close-out 2), 2026-10-01 20:26–21:07 EDT, against local fakes only (sandboxed, no account): G1 OK and G2 `verdict run final-full1 … was on THIS gallery` (no override); shared-bucket guard refuses all 10 misuses (empty prefix, `lean4game/`, QED64's root dirs); `upload-artifacts.sh` 93 objects / 2.42 GB into a fake `qed64-artifacts/qed64-showcase/`, size + sha256 equal, nothing else written; the rclone s3 path types 8 JSON + 85 octet-stream, 3 multipart; rollback restores an index and refuses a missing object or a foreign remote; `deploy-app.sh` refuses without a matching release record, then `RECORD OK` and `wrangler deploy --dry-run` (4.125.0); the real `infra/worker.js` under `wrangler dev --local`: `SMOKE OK` 168 URLs, Range 206/416/If-Range, COOP/COEP/CORP; one browser boot of `/showcase/#hasse-view` `BOOT-CHECK OK` (ready in 14 s, HasseView panel rendered). Worker tests 22/22. Publishing needs the owner's account and go-ahead (the steps marked [account]). `out/deploy` was regenerated after close-out 3 on the current pin and gallery `92027286…`: `DEPLOY-MANIFEST OK 75 assets, 93 R2 objects`, `--check` `DEPLOY-MANIFEST CHECK OK`, with `G2 UX: NO verdict …` (no green full run on this gallery: L9), so the release preflight refuses it without `ALLOW_NO_UX_VERDICT=1`. **Do not deploy pin B (L9).** |
| Build history and evidence | [docs/STAGE-A-RESULTS.md](docs/STAGE-A-RESULTS.md), [docs/STAGE-B-RESULTS.md](docs/STAGE-B-RESULTS.md), [docs/TEST-PLAN-DELTAS.md](docs/TEST-PLAN-DELTAS.md) | Pin, native build, bakes, examples, goldens and the gallery code. |

Headless verification results, re-run on the current pin `wasm64-2c18773ecfba45bb` with its new bakes (docs/REPIN-LOG.md §7):

* **E1**: 8/8 packages pass on the `widgets8` bake, and 7/7 on `widgets7`.
* **E3**: every probe and golden check passes: 1167/1167 on w8 across all eight packages (1166 on the previous pin plus
  one added selection check) and 1038/1038 on w7.
* **E3b**: 49/49 panels are React-clean.
* **Clicks**: all 21 declared clicks (`lean/examples/*.json`) re-elaborate clean in wasm.
* **E2**: 7 of the 8 Demos compile verbatim. The eighth (tree-scope, line 104) fails because of
  the runtime limitation L1.
* **Native click-all**: all 135 rendered links apply clean.

## Testing of `scripts/showcase.sh` on 2026-10-01

**Testing on 2026-10-01** (logs `$W/logs/docs-fix-*.log`, `docs-fix3-*.log`, `showcase-docs-fix*-*.log` and, for the
close-out, `closeout-*.log` and `showcase-closeout*-*.log`).

* **Close-out (14:00–16:30 EDT)**, closing the docs audit r3 and bring-up audit r2 findings:
  * `showcase.sh ux` on the real gallery: run `closeout-full1`, 31 passed / 1 skipped, recorded `VERDICT`; then
    `gallery` → `UX CURRENT`, deploy `--check` → `G2 UX: verdict run closeout-full1 … was on THIS gallery`.
  * The served-gallery guard (docs audit r3 major 1), in a scratch copy whose path has a space and whose browser
    patterns match nothing (`closeout-scratch-ux-record.log`, stub runner writing a fake `report.json`): a green full run
    → `VERDICT` and `UX CURRENT`; 1 unexpected → `NOT A VERDICT: 1 unexpected; expected 30 + skipped 1 != listed 32`;
    a C5 skip → `skipped beyond C19: C5`; `--grep` → `a subset run`; `UX_ORIGIN` → `UX_ORIGIN=… (another origin)`;
    `gallery/` edited mid-run → `gallery/ changed …; the server did not serve the local gallery`; then, with the local
    gallery differing from what :5190 serves, `ux` is `REFUSED … it serves gallery 9cfb82a5…, not the local gallery/
    2362ff1c…` (rc 3), and `gallery` says `UX STALE`. A `GALLERY_DIR` mutant served on :5194 makes `PORT=5194
    showcase.sh serve` refuse (`it serves gallery 971f7e97…, not the local gallery/ 9cfb82a5…`, rc 3), while the real
    gallery on :5195 is accepted (`closeout-scratch-serve-mutant.log`).
  * `all`'s exit code (major 2; `closeout-scratch-all-A.log`): a stale buildId in `tests/experiments/lib.mjs` with a
    green ux → verify red, re-run after the stages, still red → `ALL: FAILED (verify still red after the build
    stages)`, exit 1; verify green and ux rc 1 → `ALL: FAILED (ux rc=1)`, exit 1; both green → `ALL: OK`, exit 0.
  * Skip rules (`closeout-scratch-all.log`): the widgets8 index's `mathlib.transfer` off by one → `overlay w8: FAIL … —
    rebuilding it` and `headless: a bake/overlay was redone in this run, so S4 re-runs`; `summary.json` snapSha256
    zeroed → `headless: summary.json does not describe the current bakes (w8: summary snapSha256 000000000000 !=
    84fc22d713fb …)`. The real `--dry-run all` still skips everything (`closeout-dryrun-all.log`).
  * Refusal lines: a live lock owner with `LOCK_WAIT_S=6` → only `REFUSED: probe: refused by the lock/preflight
    (rc=75 …)`, exit 3; a command exiting 3 → only `probe3: FAILED rc=3`, exit 3.
  * Bring-up: `widgets.mjs --dir closeout` → `THUMBS OK 8/8`, `WIDGETS OK 8/8`, `CONSOLE OK … paired 7/7`
    (`closeout-batch1.log`); check-gallery mutants (scratch): thumbnails loaded as `.jpg` → `FAIL card thumbnails
    wired`, the old truncated labels → `FAIL cursor hint labels`, each `CHECK-GALLERY FAIL 120 ok, 1 failed`.
  * `verify` rc 0 (`VERIFY: all checks OK`, the same 1 Docker DRIFT; `closeout-verify-final.log`); shellcheck clean.
Every green claim about the gallery names the gallery content sha256 it was made on, because the
gallery lane edits `gallery/` concurrently. Between 12:34 and 13:14 the gate was red: at 13:10,
`node scripts/check-gallery.mjs` gave `CHECK-GALLERY FAIL 116 ok, 3 failed`
(`BUILD-GALLERY STALE`, and thumbnails not yet recorded in `examples.json`), and the 12:41 manifest
packaged that red gallery. This was the audit's finding.

* Latest run, 13:20–13:23 local, after the gallery lane's last edit to a shipped file (13:14:48),
  all on gallery `2550fa1d10b093ae…` (re-hashed after each run, unchanged): `gallery` rc 0
  (`CHECK-GALLERY OK 119 ok, 0 failed`, `SIM-GALLERY OK 56 ok`,
  `gallery gate GREEN on gallery content sha256 2550fa1d…`, `UX STALE`); `gallery --live` rc 0
  (`CHECK-GALLERY OK 130 ok`); `deploy-manifest` generate `DEPLOY-MANIFEST OK 75 assets, 93 R2 objects; gallery 2550fa1d…`
  and `--check` `DEPLOY-MANIFEST CHECK OK` with `OK   G1 … CHECK-GALLERY OK 119 ok`; `--stage-assets`
  (`S1 … exactly the manifest's 75 assets`, `S2` OK); `--smoke http://localhost:5190 --all`
  (`168 URLs (75 assets + 93/93 R2 keys)`, against a `showcase.sh serve` this lane started and then
  stopped); `node --test infra/worker.test.mjs` 11/11; `verify` rc 0 (`VERIFY: all checks OK`, 1 DRIFT).
  The first `gallery` attempt at 13:20 stopped with
  `ERROR: gallery/ changed while the gate ran (885b8ec0… -> bc1f7a18…)`: the gallery lane was editing
  `gallery/README.md`. That edit made the guard switch the hash to the shipped files only.
* Earlier runs: `verify` (rc 0, `VERIFY: all checks OK`, with one `DRIFT` note, see
  below); `pin` (report mode, rc 0: QED64 HEAD equals the pin, but S0.2 does not hold right now
  because another session left one untracked file, `pipeline/snapshot/thread-storm-probe.mjs`, in
  the QED64 checkout, so `pin --yes` would refuse); `--dry-run all` (rc 0: SKIP lines for native,
  stage, bake w7/w8, overlay w7/w8 and now `SKIP headless: out/headless/summary.json (… wasm64-4b025db7729c5f89)
  has stage4Green and E2Green (E2 7/8 clean)`; with `--rebuild`, `headless: a bake/overlay was redone
  in this run, so S4 re-runs` and the controls/stage4/e2/summary plan), and `serve`/`stop` on :5194: start, second `serve` names the owner, `stop` by another
  lane and on another lane's :5191 are refused (rc 3), the owner's `stop` works, and :5191 keeps
  serving. `PORT=5197 serve` is refused (rc 3), because :5197 is a Vite app of another session
  (`no CORP same-origin header`).
* Exit-code mapping, in a scratch copy whose only changes are the browser and bake process patterns
  (`docs-fix3-rc-mapping.log`): `locked probe3 -- bash -c 'exit 3'` gives `probe3: FAILED rc=3` and
  **no** `REFUSED` line; a preflight refusal inside the lock (a process posing as a bake) gives
  `REFUSED: a snapshot bake is running`, `command exited rc=77`, then `REFUSED: probeB: refused by the
  lock/preflight (rc=77)` (exit 3); lock wait timeout 75 and cooldown 76 are still `REFUSED`.
  `ux`/`gallery` recording, with stub runners (`docs-fix3-ux-gallery-hash.log`): a green `--grep`
  subset run is recorded but leaves `UX STALE`; a green full run gives `UX CURRENT`; a green run during
  which `gallery/` changed prints `WARNING: gallery/ changed during the UX run` and is not a verdict;
  a failing `check-gallery` gives rc 1. `deploy-manifest` in an APFS-clone scratch copy: with the
  widgets8 index's `mathlib.runtime` mutated, generate gives `FAIL R3 … mathlib.runtime wasm64-1111111111111111`,
  `DEPLOY-MANIFEST FAILED (2 FAIL): nothing written`, and the sha256 over `manifest.json` plus the
  rclone lists is identical before and after (`b70af298…`). The second FAIL there was G1: the gallery was still red at that moment.
* Run in a scratch copy whose path contains a space, with stub stage scripts: `native` refused on
  the drifted Docker tag (rc 3) and ran (under `caffeinate -i`) once the scratch lock named the
  current image; `locked` against a live owner gave up after `LOCK_WAIT_S` (75 → rc 3), took over a
  dead owner's lock under the takeover mutex, and refused at the cooldown while another session's
  headless Chrome ran (76 → rc 3); three concurrent waiters (two `showcase.sh locked`, one direct
  `with-browser-lock.sh`) on a stale lock produced exactly one takeover and strictly serial holds;
  a server whose `pin.json` buildId differs from the lock is refused; the `verify` watchdog fired
  on a hanging stub (rc 142, one retry); a waiter killed with SIGTERM released its lock.
* The success path needs a moment with no headless Chrome on the host, and other sessions kept one
  running for 20+ minutes, so it was run in a second scratch copy whose only change is the process
  pattern (`browser_pids` and the cooldown's `pgrep`, shown by `diff`): `locked` (the probe ran
  inside the lock, and `pmset -g assertions` showed `caffeinate asserting on behalf of 'bash'` with
  the probe's own pid), `ux --grep "two words"` (argv arrived intact: `[--grep] [two words]`) and
  `bake w7` (bake under the lock, then judge and pair) all gave rc 0 and released the lock.
* Earlier (01:00–02:00): `headless controls` (`CONTROLS PASS`, 64 s) and `headless summary`; the
  pin-constants check was mutation-tested on a scratch copy (a stale id in a script, in
  `tests/experiments/lib.mjs`, in the `x1-preflight.mjs` regex or in `tests/ux/selectors.json`, a
  real pin replaced by the all-zero sentinel, a removed pin, a sentinel outside the sentinel files,
  and a changed lock all FAIL; a new pin site with the right value passes with a `NEW` note).
* Dry run only: `native`, `stage`, `bake`, `overlay --preflight`, `headless stage4`, `ux` and `all`.
* Not run: the native build and the bakes (they are done, and the close-out may not run Docker or a
  bake). The UX suite through `showcase.sh ux` was run at the close-out (above).

## Limitations, as written at the end of the multi-pin lane (with the L7 and L9 history)

* **D1 and D2 are bridged, not fixed.** On the stock page, without `gallery/qed64-bridge.js`,
  no `mk_rpc_widget%` panel renders (`abortSignal` arrives as `{}`) and no InfoView link edits the
  text (`openEditor` is `unsupported`). The bridge works only from the same origin. It drops RPC
  cancellation (requests run to completion), and it applies edits only to the open model. The
  defects and the suggested QED64 fixes are in
  [docs/UPSTREAM-REPORT-QED64.md](docs/UPSTREAM-REPORT-QED64.md).
* **L1, a QED64 runtime limitation.** Imports happen at `OLeanLevel.exported`, so definitions in
  core `module` files that are not exposed arrive as axioms. `whnf`, `decide`, `rfl` and
  reflection get stuck on them (`Lean.RBMap.ofList`: `AXIOM`). Visible effect:
  `#tree_scope (reflect := true)` on a `Lean.RBMap` fails in QED64; the semantic view works. No
  showcase example or declared click hits this.
* **L7, a QED64 runtime freeze: handled upstream on the served pin C (`5ac5d00`).** C serves the 0034 runtime (no kernel
  patch 0035) with all of QED64's #52 worker fixes (message-mode mailbox, 1 s kick, Lean-side liveness with a `wedged`
  reboot, exit hook); B (`9fdf9b8`) had all four layers; A (`1859b83`) has none, and there the gallery's probe is the
  primary recovery (10 s threshold, a late real hover answer counts as proof of life; a pool saturated for longer than its
  2 × 5 s probe sequence is still restarted there: UX C22 (3) on A, docs/REPIN-LOG.md). The history: On the previous pin (`wasm64-4b025db7…`), rarely
  (1 hang in the 19 recorded C20 runs, about 1 in 20) QED64's whole Lean runtime froze in `elaborating`: the Emscripten
  main-thread proxy path stopped (most likely one lost wake of the main-thread mailbox, permanent in Emscripten's
  `waitAsync` mode), and the thread pool froze because Lean's task manager called `pthread_create` while holding its
  global mutex; the worker's JS thread stayed alive, so QED64's heartbeat never noticed. QED64 9fdf9b8 (runtime
  `wasm64-2c18773ecfba45bb`, the current pin) fixes it in four layers: kernel patch 0035 (no `pthread_create` under the
  mutex, parked dedicated threads reused, `status().pool.parked`), a message-mode runtime mailbox, a 1 s raw mailbox kick
  with confirmed rescues (`status().liveness.rescues`), and a Lean-side liveness probe that reboots a wedged session
  (pill "the checker stopped responding — restarting"). The gallery detects that liveness (`status().liveness`) and
  defers to it: its own hover probe now starts only after 30 s without progress (10 s on the previous pin), never acts
  during QED64's stall grace window, reports QED64's rescues, stalls and `wedged` reboots (`status().liveness.qed64`),
  and stays a fallback for what QED64's worker cannot see; the 45 s stall card is unchanged. `?liveness=observe`
  records a wedge without restarting it, for hang hunts with the UX harness's hang capture (`out/hang/captures/`). A
  user `#eval (IO.Process.exit n : IO Unit)` is caught only by QED64's new FileWorker exit hook (died `exit`), not by any
  liveness probe. Besides a hover answer, the gallery's probe takes QED64's own probe answers and any server frame from Lean
  (not the frames QED64's JS layer makes itself) as proof of life, so a saturated task pool (all Lean threads busy, the hover queued) is not mistaken for a freeze (C22 (3));
  a 45 s card on a live checker reads "Lean is still working". C20 and W1–W8 accept a QED64 `wedged` reboot as an L7
  occurrence handled upstream and record it post hoc (no pre-recovery capture is possible on this pin: QED64 recovers first, and its page has no option
  to switch that off; the post-hoc path is exercised in the browser by C23). On
  the new pin, 16 C20 runs (the final lane's 10, the two audits' 4, close-out 2's and 3's; 4,320 edits) showed no hang, and
  QED64's rescue, stall and reboot counters all stayed at 0 (out/hang/FIELD-CAPTURE.md). At the old rate of about 1 in
  20 runs, that sample is too small to prove the fix. Details: gallery/README.md (Errors;
  L7), docs/UX-RESULTS.md (L7, C21, C22), the upstream report, `out/hang/ROOT-CAUSE.md` and docs/REPIN-LOG.md.
* **L9, pin B (`9fdf9b8`) only: a reload can crash the renderer.** QED64 traced it to kernel 0035's parked dedicated
  threads; the served pin C runs the 0034 runtime: 0 crashes in 6 stock reload storms and C10 passed in its 3 full runs
  (docs/UX-RESULTS.md "Multiple pins"). B stays registered for evidence. The history: Reloading a ready QED64 page (stock page or
  gallery), or a relay restart that boots a new worker, crashes the renderer with `V8 javascript OOM (Scavenger:
  semi-space copy)` most of the time on this host. In an A/B on the stock page, the 0034 release crashed 0 of 5 reload
  storms and the 0035 release crashed 3 of 5, each about 2 s after the first reload. In the UX suite on this pin, C10
  crashed in 6 of 8 full runs (`repin-full1`, `repin-crash1`, `final-full2`, `closeout2-full1`, the last audit's
  `audit-final-full1`, `closeout3-full1`; it passed in `final-full1`, the final audit's run and on the old pin), C21 (b) crashed after a restart in 3 of the 5 runs where it
  shared a renderer with (a) (it now runs in its own browser: 0 of 3), and W4 crashed in 1 of 6. Because of L9, the
  final lane got one green full run and one red one, and close-out 2's and close-out 3's full runs were red on C10. QED64's pool now sits at 18–20
  running (8 parked) instead of 10–11. The cause is inside QED64's release and cannot be worked around from the gallery;
  reported as L9 in docs/UPSTREAM-REPORT-QED64.md with the repro (`tests/ux/tools/reload-storm.mjs`). Rolling back
  (docs/REPIN-LOG.md) trades it for L7.
* **The dev-only `?snapshots=` override is pinned.** The showcase depends on it, but only through
  the pinned bundle, so it is immune to upstream removal until a deliberate re-pin.
* **DistLens is the expensive one.**
  * Its region adds 609 Mathlib modules: the w8 region is 1.27 GB raw and 364.7 MB transfer,
    against 1.13 GB / 321.5 MB stock.
  * Its clicks re-elaborate in up to 3.05 s in wasm, about 3.7× native, and the `twoDice` click
    is the slowest.
  * Opening the document settles in 5.2 s headless.
  * The gallery's switch timeout is 330 s, sized for the 300 s DistLens budget.
* **The stock page is always light-themed.** The QED64 bundle hard-wires "Visual Studio Light",
  so only the gallery chrome follows `prefers-color-scheme`.
* **Console noise.** Every stock boot logs one `Error: unsupported` pageerror and one empty
  `console.error` (N1 in the report). Console oracles allowlist exactly these.
* **Goldens are native.** Click-all coverage (135 links) is native. In wasm, the 21 declared
  clicks are re-elaborated, and every link's edit is compared with the native golden.

## docs/NEXT-STEPS.md as of the end of the multi-pin lane (superseded by the docs lane's rewrite)

(was the title: Pending follow-ups, orchestrator notes, 2026-10-01)

Run these after the UX audit (stage C) and the hang-capture lane finish, so no file under test changes mid-run.

### 1. Gallery liveness probe with automatic restart (L7 mitigation on the current runtime)

- **Trigger:** QED64 reports `elaborating` on a serving relay, and no progress has been seen for 10 s. Progress means any
  `$/lean/fileProgress` or `publishDiagnostics` frame, or a phase, version or session change.
- **Probe:** send `textDocument/hover` for the open document at 0:0 through the relay.
  - Use a **string** id (for example `"showcase-live-<n>"`) so it cannot collide with the client's numeric ids.
  - The request **must carry `params`** (textDocument + position). A Lean FileWorker request without params matches
    no case in mainLoop and ends in "Got invalid JSON-RPC message", which kills the worker. This comes from the QED64
    session.
  - Swallow the reply in the existing `relay.toClient` tap so the editor never sees it.
- **Decision:** an answer means Lean is alive (merely slow), so re-arm. Two consecutive probes with no answer within
  about 5 s each means wedged. Restart automatically with the session's own snapshots (`relay.restart`), keep the
  text, and show a small non-blocking notice: "Lean stopped responding and was restarted".
- **Keep the 45 s card as the fallback** if the restart itself fails.
- **Tests:** the existing C21 synthetic-freeze fixture must now show an automatic recovery within about 25 s. Also
  test a negative case: a legitimately slow elaboration (a ~40 s silent `#eval`, or the DistLens click at about 3 s)
  must NOT be restarted, because hover at 0:0 answers while elaboration is busy elsewhere. Verify that claim in the
  browser before relying on it.

**Status (close-out lane, 2026-10-01): done.** `gallery/gallery.js` (liveness probe, observe mode, `__showcase.liveness`),
UX tests C21 (auto restart 20.4 s after the click on the previous pin; about 41 s on the 9fdf9b8 pin, where the probe defers 30 s to QED64's own liveness; observe mode + synthetic hang capture) and C22 (a 38 s silent `#eval`
answered 3/3 probes in 1–3 ms, not restarted); see docs/UX-RESULTS.md. Verified in the browser first
(`tests/ux/tools/liveprobe.mjs`: hover at 0:0 answered in 1–2 ms during 40 s of silence).

**Amended (close-out 2, after the final audit, 2026-10-02).** The hover at 0:0 is answered during a busy elaboration
only while a Lean task thread is free. With every thread busy (24 parallel `sleep` proofs) it waits, and the probe used
to restart a healthy session. The probe now also takes any server frame, and on a page with QED64's own liveness any
answer to QED64's probe (its FileWorker main loop answers it without a pool thread), as proof of life
(gallery/README.md "Proof of life besides the hover"; C22 (3) in the browser: 1 probe settled `alive`, 0 restarts).

### 2. Rewrite the L7 entries (gallery/README.md, docs/UX-RESULTS.md, docs/UPSTREAM-REPORT-QED64.md)

Rewrite them per out/hang/ROOT-CAUSE.md "Verification, second pass":
- It is a runtime-wide freeze: the Emscripten main-thread proxy path stopped, and the pool froze because
  `pthread_create` runs under `m_mutex`.
- The -32800 cancels are routine, and the reporter ran.
- The rate is 1 hang in about 20 C20 runs, not 1 in 3.
- The likely trigger is a lost mailbox wake: one wake lost in waitAsync mode is permanent. The QED64 session's E1
  fault injection reproduced the signature.
- The QED64 owner is fixing it (postMessage mailbox mode, a periodic raw kick, a liveness reboot; patch 0035 reduces
  exposure).
- Also record the separate `_proc_exit`/`onExit` side bug.

**Status (close-out lane, 2026-10-01): done** in gallery/README.md, docs/UX-RESULTS.md, docs/UPSTREAM-REPORT-QED64.md
(with the `_proc_exit`/`onExit` side bug as X1) and README.md.

### 3. Re-pin when QED64 promotes the fix

When the QED64 session sends a commit and runtime id:
1. `pin-qed64.mjs refresh`, then verify.
2. Check whether the native64 compiler changed (patch 0035 touches `src/runtime/object.cpp`). If oleans are unaffected,
   only rebake. Otherwise rebuild the delta and the widgets in Docker.
3. Rebake widgets7 and widgets8 against the new runtime, then make-overlay, pair-check and preflight.
4. Headless stage 4: `run-stage4.sh`.
5. The full UX suite, plus at least 5 C20 runs. Expect 0 hangs, and expect automatic recovery labelled "wedged" if
   one occurs.

**Status (re-pin lane, 2026-10-01): steps 1–4 done, step 5 partly** (docs/REPIN-LOG.md). Pinned to QED64 `9fdf9b8` /
`wasm64-2c18773ecfba45bb` / kernel `3ae65d36f9`. Step 2: the core library is byte-identical, so no native rebuild was
needed. Steps 3–4: both bakes are GREEN, paired and preflighted; stage 4 and E2 are green. The gallery's liveness probe
now defers to QED64's own (§1 amended: 30 s on a page with `status().liveness`). Step 5: the full-suite result is in
docs/REPIN-LOG.md §9. The 5+ C20 runs on the new pin are still open: run them with `UX_LIVENESS=observe UX_RUN=huntN npm run
test:ux -- --grep C20` and watch `status().liveness.qed64` (`rescues`, `wedgedReboots`) as well as the gallery's own
wedges.

**Status (final lane, 2026-10-02): step 5 done; it does not pass.** Full suite twice through `showcase.sh ux`
(docs/UX-RESULTS.md "Final verification on the 9fdf9b8 pin"). `final-full1` gave 31 passed, 1 skipped: VERDICT.
`final-full2` gave 28 passed and 3 failed (C10, C21 (b), C14), all from QED64 L9 renderer crashes, which the gallery
cannot handle. C20 hang hunt: 8 observe-mode runs, `UX_LIVENESS=observe UX_RUN=final-hunt<N> npm run test:ux -- --grep
"C20 "` (driver `work/logs/final-hunt.sh`). It found 0 hangs in 1,080 clicks and 2,160 edits, with QED64's liveness at
0 rescues, 0 stalls and 0 `wedged` reboots, and no capture (out/hang/FIELD-CAPTURE.md). Open: L9 upstream, then two
green full runs; or the owner's rollback decision (docs/REPIN-LOG.md "Rollback").

**Status (close-out 3, 2026-10-02): the last audit's minors are fixed; the gate is still blocked by L9.** One full run on
the new gallery `92027286…`, `closeout3-full1`: 30 passed, 2 failed (C10 L9 crash, C14), 1 skipped, NOT A VERDICT
(docs/UX-RESULTS.md "Close-out 3"). Proof of life counts only frames from Lean; C23 exercises the post-hoc record of a
QED64-handled hang in the browser; on this pin no pre-recovery capture of a real L7 is possible (out/hang/FIELD-CAPTURE.md).
16 C20 runs on 9fdf9b8 in all: 0 hangs, 0 QED64 rescues.

**Status (close-out 2, 2026-10-02): the final audit's findings are fixed; the gate is still blocked by L9.** One full
run on the new gallery `7772c1eb…`, `closeout2-full1`: 29 passed, 2 failed (C10 L9 crash, C14), 1 skipped, NOT A
VERDICT (docs/UX-RESULTS.md "Close-out 2"). 13 C20 runs on 9fdf9b8 in all: 0 hangs, 0 QED64 rescues.

### Frozen copy of pin C (QED64 5ac5d00)

If the QED64 checkout has moved past 5ac5d00 before pin C was cloned, use `/Users/fawadhaider/code/qed64-showcase-work/frozen-qed64-5ac5d00` (see its FROZEN.txt): a git archive of 5ac5d00 plus APFS clones of its dist/ and public/{runtime,profiles,snapshots,workers}.

### Pin D (QED64 3b42714, runtime wasm64-3ab1c6a9da03bc29, kernel a8817d01f9: L7 fixed, parking off so no L9)

Promoted locally by the QED64 session on 2026-10-02. Packs are unchanged; the snapshots were rebaked with new digests, so the widget overlays need a real rebake against this runtime. The worker is byte-identical to 5ac5d00's. Frozen read-only copy, including the stage1 runtime and the bump-0035b base tree: `/Users/fawadhaider/code/qed64-showcase-work/frozen-qed64-3b42714` (see its FROZEN.txt). Plan: after the stabilise workflow, add it as pin D with the multi-pin tooling, prove native olean compatibility, rebake widgets7 and widgets8, run the headless stage, then gate it like C: reload storm with 0 crashes in at least 5 runs, two consecutive VERDICT full runs, at least 3 C20 runs, then make it the served default if green.

### 4. Multiple pins; serve C (5ac5d00) if it passes, else A (orchestrator, 2026-10-02)

**Status (multi-pin lane, 2026-10-02): done; C is served.** Pins are keyed by QED64 commit (`pins/<id>/`,
`release/<id>/`; runtime-paired stores shared per buildId in `out/runtimes/<bid>/` and `$W/runtimes/<bid>/`), one is
active through 15 symlinks, and no file hardcodes a pin (`scripts/lib/pins.mjs`, `scripts/showcase.sh pin
list|current|check|use|clone`; docs/REPIN-LOG.md "2026-10-02"). C's gates: reload storm 6/6 without a crash; headless
`CONTROLS PASS`; two consecutive VERDICT full runs (`multipin-C-full2-b`, `multipin-C-full3-b`); C20 135/135 in 6 runs.
Switching rehearsed A→C→A→C, C→B→C (verify, controls and a gallery boot each way; one boot refused by host contention).
The deploy kit names the verdict run (`G2 … multipin-C-full3-b`). Open:
* **When QED64 sends the final fix** (0035 with the parked cap 0; a new commit and runtime id; at the end of this lane
  QED64's HEAD had become `3b42714` "promote kernel 0035b … runtime wasm64-3ab1c6a9da03bc29 … dedicated-thread parking
  off by default", not yet handed over or pinned): register it as a new pin
  and follow README "Re-pin" (it is a new runtime: stage, bake, overlay, headless under `pin use <id>
  --allow-incomplete`), gate it the same way, and keep C as the fallback.
* **Pin A without QED64 liveness:** UX C22 (3) fails there (a saturated pool is restarted). If A must ever be served with
  a verdict, give the gallery a second probe the FileWorker's main loop answers without a pool thread (an unknown-method
  request with params, the mechanism QED64's own liveness uses), test it in `sim-gallery.mjs` and C22 (3) on A, and then
  re-run the full suite on the active pin (a `gallery.js` change voids existing verdicts).
* **QED64 N2** (the heap meter's unhandled rejection) is reported upstream; drop its allowlist entry when the pinned
  page has the fix.
