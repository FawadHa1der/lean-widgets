# Closure lane: final verification of gallery `31f6d8d9…` on served pin C `5ac5d00` (2026-10-03, 09:15–14:49 UTC)

Lane `closure`. It ran on the gallery the boot-fix lane left (current then; a later lane changed it: `scripts/showcase.sh gallery` prints the current one) (content sha256 `31f6d8d9344864bd0ef5d16b9538b9e17f1e095e0cf2f70eb214ce386925774c`).
The gallery was the same at the start (`node scripts/lib/gallery-hash.mjs`), at every run record (local == served) and at the end
(`$W/logs/closure-gallery-end.log`). Pin C `5ac5d00` / `wasm64-4b025db7729c5f89` was served throughout.

Rules followed:
* Every browser command ran under `scripts/with-browser-lock.sh`.
* No Docker, no bakes, no `npm install`, no git commit, no system or security setting changed. No data deleted, except that the rehearsal's own steps reset their scratch state as they always do (below).
* Logs: `$W/logs/closure-*.log` (`$W` = `/Users/fawadhaider/code/qed64-showcase-work`); scripts `$W/closure/`; pre-edit copies `$W/closure/pre-edit/`.

## Gate

| Item | Result |
|---|---|
| (1) Two consecutive full `scripts/showcase.sh ux` runs | **VERDICT, VERDICT**: `closure-full1` (09:18–09:42Z, lock from 09:20:48Z) and `closure-full2` (09:42–10:03Z), each 33 passed, 1 skipped (C19) |
| (2) Full headed sign-off, Chrome for Testing, `UX_HEADED_ALL=1` | **HEADED SIGN-OFF**: `closure-headed1`, **34/34 passed, C19 included** (lock 11:03:35–11:25:17Z; the record starts at 10:03:32Z because it waited 60 min for the lock) |
| (3) Throttled first visit, fresh profiles | **10 Mbit/s: ready 565.1 s, 50 Mbit/s: ready 120.3 s**, error card in 0 samples, progress visible throughout, panel equal to its golden, console OK (fixed proxy; see (3) for the proxy defect found and fixed) |
| (4) 60-min headless soak | **PASS**: 60.09 min, 473 operations, 0 failed, no crash, no stall card, 0 liveness restarts, 0 `wedged` reboots, 0 worker deaths. Renderer RSS slope after cycle 1: **+4.5 MB/min** (R² 0.89). It slows down (9.2 → 3.9 → 2.7 MB/min over successive 20-min windows) but is **not yet level at 60 min** |
| (5) Deploy | manifest regenerated (byte-identical), `--check` OK with `G2 UX: verdict run closure-full2 … was on THIS gallery 31f6d8d9…`; `rehearse.sh all` rc 0 (second attempt; the first stopped on a sim-gallery timing race, root-caused and fixed, (5)); browser boot-check `BOOT-CHECK OK` |
| (6) `scripts/assert-untouched.sh check closure` | **VERDICT: CHANGED**, caused by other sessions' commits and builds in QED64 and lean4game during the lane (attribution, (6)). Kernel trees and widgets-v4.34: OK. This lane wrote nothing there |
| (7) Docs | this file; docs/UX-RESULTS.md "Closure lane"; README.md, docs/NEXT-STEPS.md, docs/DEPLOY-CLOUDFLARE.md, docs/HOUSEKEEPING.md, gallery/README.md, `out/ux/last-mile/RESULTS.md` (update note) |

## (1) Two verdicts

Command: `SHOWCASE_LANE=closure UX_RUN=closure-full{1,2} LOCK_WAIT_S=14400 scripts/showcase.sh ux`, chained by
`$W/closure/full-chain.sh` (`$W/logs/closure-full-chain.log`, `closure-full{1,2}.log`, the records in
`closure-full-records.jsonl`, the summary in `closure-full-summary.log`). Both records:
* rc 0, `listed` 34, report `expected 33, unexpected 0, skipped 1 (C19), flaky 0`;
* galleryStart == galleryEnd == servedStart == servedEnd = `31f6d8d9…`;
* served pin `5ac5d00 wasm64-4b025db7729c5f89` at start and end.

| Run | C3 renderer peak | C10 (5-reload storm) | C20 |
|---|---|---|---|
| `closure-full1` | 8.30 GiB | passed, no crash; settled renderer 9.84 GB, transient peak 11.31 GB | 135/135, 0 stalls, 0 liveness restarts, 0 wedged, QED64 rescues 0 |
| `closure-full2` | 9.23 GiB | passed, no crash; settled renderer 9.95 GB, transient peak 11.71 GB | 135/135, same |

No test record has `"crashed": true`. W4 passed in both (and in (2)); `node scripts/ux-tally.mjs` now counts W4 on C in 26
run directories with 1 crash (`bootfix-full1`; `$W/logs/closure-ux-tally.txt`).

## (2) Headed sign-off

`SHOWCASE_LANE=closure UX_RUN=closure-headed1 UX_HEADED_ALL=1 UX_WARM_PROFILE=$PWD/out/ux/profiles/ux-warm-headed
scripts/showcase.sh ux` (`$W/logs/closure-headed1.log`, record `closure-headed1-record.jsonl`):
* rc 0, `headed: true`, report `expected 34, unexpected 0, skipped 0`, judged **`HEADED SIGN-OFF (not a verdict)`**;
* gallery and served pin as in (1);
* C19 booted to ready in 14.2 s, panel equal, UA `Chrome/151.0.0.0`;
* C10: no crash, settled renderer 9.95 GB (2 renderers; 10.78 GB with the browser and GPU processes, which C10's line does not count), peak 11.99 GB;
* C20 135/135.

Headed launches pin `--force-device-scale-factor=1` (`tests/ux/lib/qed64.mjs` `launch`). The macOS screen was locked
(`ioreg` `CGSSessionScreenIsLocked` true at the start, `closure-chain2.log`). `showcase.sh gallery` then printed
`UX CURRENT: … run closure-full2 … ; headed sign-off closure-headed1 … on the same inputs`.

## (3) Throttled first visit (chrome-headless-shell 151.0.7922.34, fresh profile, link shaped by `throttle-proxy.mjs`)

`node tests/ux/tools/throttle-proxy.mjs --listen 5198 --upstream 5197 --mbps <m> --rtt 40` in front of a `serve.mjs` on
:5197 that served gallery `31f6d8d9…` and pin C (checked with `ux-record.mjs served|servedpin`). Then
`throttled-first-visit.mjs --origin http://localhost:5198 --no-cdp --mbps <m> --rtt 40 --max-s 1200` ran under the lock
(`$W/closure/inner3.sh`, `closure-throttlefix-p{50,10}.log`; JSON `out/ux/closure-throttle/explore/throttle-fp{50,10}.json`,
screenshots `out/ux/closure-throttle/screens/`).

| Run | Proxy | Ready | Error card | Visible progress before ready | Gallery notice | `status().boot` | Console | Panel |
|---|---|---|---|---|---|---|---|---|
| `fp10` (13:34Z) | fixed | **565.1 s** | 0 samples, none at end | 563/564 (the miss: t = 0.15 s, veil fading in) | from 231.5 s | stalls 0, notice shown 1, uiWrapped busy/progress/idle | ok | chart-kit EQUAL |
| `fp50` (13:32Z) | fixed | **120.3 s** | 0 | 119/120 | never (it arms at 120 s) | stalls 0 | ok | EQUAL |
| `cp10` (12:01Z) | original | 564.1 s | 0 | 562/563 | from 231.5 s | stalls 0 | ok | EQUAL |
| `cp50` (12:40Z) | original | 120.3 s | 0 | 119/120 | never | stalls 0 | **NOT ok** | EQUAL |

The longest stretch without a visible change was 19.0 s at 10 Mbit/s, against the 240 s stall window, and 3.0 s at 50 Mbit/s.

**`cp50`'s console oracle: a defect in the test proxy, root-caused and fixed.**
* **Symptom.** QED64 warned `[qed64] raw prefetch error: The compressed data was not valid: invalid code lengths set. — the checker will stream it instead` at 53.4 s. The worker's GET of `widgets8/init.35c8c5f5419e0c33.snapz` ended `net::ERR_ABORTED` at the same instant. `serve-5197.log` shows it as `499 11534336/32643645 … client-abort`, then a complete `200` 4 s later. The boot finished normally with the panel equal, so the file on disk was intact and the bytes were damaged in transit.
* **Cause.** `throttle-proxy.mjs` gave every 64 KiB slice its own `setTimeout(write(slice), end - Date.now())`. Node starts a timer from the cached loop time, not from `Date.now()`. Two slices scheduled in different callbacks can therefore expire out of order when their `end` times are closer than the loop lag between those callbacks, and the closured slice was then written out of order.
* **Order test.** `$W/closure/proxy-order-test.mjs` streams numbered 16-byte records in 128-byte writes through the proxy. With the original proxy, order broke in **6 of 6** runs, 3 plain and 3 with injected event-loop stalls (`closure-proxy-order-pre.log`).
* **Real file.** Downloading the 32.6 MB `init` snapshot with curl through it while the proxy's loop was stalled: 1 of 9 downloads corrupted (`closure-proxy-integrity.log`). `serve.mjs` sends large chunks, which is why this is rare in practice.
* **Fix** (`tests/ux/tools/throttle-proxy.mjs`). A FIFO per connection; each timer writes the oldest queued slice, and the pacing is unchanged.
* **After the fix.** Order kept in 6 of 6 runs (plain and stalled). 6 of 6 curl downloads were intact under stalls. 32.6 MB took 26.2 s at a 10 Mbit/s setting (9.97 Mbit/s) (`closure-proxy-order-post.log`). `fp50`/`fp10` re-ran on the fixed proxy.
* **Earlier runs with this proxy.** Last-mile `p50`/`p10` and the boot-fix lane's `p10b`/`stall50` all had the console oracle OK, i.e. no prefetch error, so their bytes most likely arrived intact. That is an inference: a reordering that happened not to break the gzip stream would not show.

## (4) Soak: one tab, 60 minutes, all eight widgets

The command, run under the lock: `UX_RUN=closure-soak node tests/ux/tools/soak.mjs --origin http://localhost:5197 --minutes 60 --tag s60`
(`closure-soak60.log`, `out/ux/closure-soak/explore/soak-s60.json`, analysis `closure-soak-analysis.log`).

**Summary:** 60.09 min, 180 ticks = 22 full cycles (each widget visited 22–23 times), 473 operations, **0 failed**, slowest
3,057 ms (a DistLens click; the stall line is 60 s), boot 12.9 s. No crash, no stall card, 0 liveness restarts, 0
`wedged` reboots, 0 worker deaths (26 workers throughout), one wasm session, console OK, every assertion passed (`ASSERT PASS`).

**Renderer RSS** (712 samples, every 5 s):

* **Range.** 9.02 GiB at the first tick, then 7.93–8.23 GiB.
* **Per-cycle max.** Cycle 1: 7.97 GiB. Cycles 4–10: 8.06 → 8.16 GiB. Cycles 15–21: 8.18 → 8.22 GiB.
* **Bounded-RSS assert.** The last cycle's max must be at most 1.10 × the tool's "cycle-2" max (7.97 GiB, the first cycle after boot): 8.22 ≤ 8.77 GiB, PASS.
* **OLS slope after cycle 1.** **+4.5 MB/min** (R² 0.893; 0.27 GB/h if it continued linearly). By window it falls: 2.9–20 min +9.2 MB/min, 20–40 min +3.9, 40–60 min +2.7; first half +7.8, second half +2.5.
* **10-minute means.** 8.66, 8.65, 8.72, 8.76, 8.78, 8.81 GB.
* **Levelling off.** The growth is levelling off but has **not stopped by 60 min**: about +2.5 MB/min, or about 0.15 GB/h, at the end. The last-mile soak saw the same over 22 min (+7 MB/min, "flattening"). Not shown: behaviour beyond 60 min.

The wasm heap held at 2.00 GiB (slope 0) and the JS heap slope was +0.1 MB/min (headless-shell's `performance.memory`
is quantised).

## (5) Deploy

* **Manifest.** `node scripts/deploy-manifest.mjs --overlays widgets8,widgets7` used the options recorded in the manifest (stock snapshots, essential pack, prefix ''). Result: `DEPLOY-MANIFEST OK 75 assets, 93 R2 objects`, and the output was **byte-identical** to the boot-fix lane's (`cmp`, `diff -r` of the rclone lists; previous copy `$W/closure/pre-edit/out-deploy/`). `--check` rc 0: `G1 … CHECK-GALLERY OK 128 ok`, `G2 UX: verdict run closure-full2 … was on THIS gallery 31f6d8d9…`, `DEPLOY-MANIFEST CHECK OK` (`closure-deploy-manifest-check{,2,-end}.log`).
* **First `rehearse.sh all` (10:38Z): rc 3.** `upload-dry` and `guard` passed. In `upload`, the manifest gate printed `FAIL G1 … SIM-GALLERY FAIL 108 ok, 1 failed`, so nothing was uploaded (`closure-rehearse-all.log`). Its `upload` step had already moved the previous fake bucket aside, to `$W/deploy-rehearsal/bucket.prev-20261003T104020Z` (93 objects from the final-gate rehearsal; listed in docs/HOUSEKEEPING.md §1).
* **Root cause, from code and runs.** The gallery renders its status line only on its 250 ms monitor tick. `sim-gallery.mjs` run 15a sends 20 progress calls 100 ms apart and sampled the status line once per call, so it saw "200 MB of 400 MB" only if a tick landed between the 20th call and the last sample. That tolerated about 100 ms of timer drift over the 2 s loop. G1 dropped the sim's own FAIL lines, so the rehearsal did not name the case; it was found as follows:
  * 15 reruns without injected stalls passed: 12 plain (3 in a row, 6 in `$W/closure/sim-loop.sh`, and 3 whose injector parameters a zsh word-splitting slip had turned into no-ops) and 3 under background QoS (`taskpolicy -c background`);
  * with an injected 200 ms event-loop stall every second (`$W/closure/stall-injector.mjs`, a `--import` preload, no repo change), the unmodified sim failed **4 of 4** times, always and only on this check (`108 ok, 1 failed`, the rehearsal's count; `closure-sim-inject200-pre-*.log`);
  * passing runs all print the status line at "2.0 s · 200 MB", i.e. that exact tick.

  That the rehearsal's failure was this case is an inference (same count, the only case that fails at that stall level). A 600 ms stall also fails run 15a's no-card and notice checks (`closure-sim-inject-600-2000.log`).
* **Fixes.**
  * `scripts/sim-gallery.mjs` run 15a keeps sampling until a tick has rendered the 20th call, at most 350 ms (more than one tick, less than the 500 ms stall window); the asserted text is unchanged. Results: 3 of 3 passed under the same injection, 2 of 2 plain runs passed, and the mutant whose booting status line drops the bytes still fails this check (`closure-sim-inject200-post-*.log`, `closure-sim-post-*.log`, `closure-sim-mutant-nobytes.log`).
  * `scripts/deploy-manifest.mjs` G1 now also keeps indented `FAIL` lines, so a sim failure names its case. Tested on the recorded `closeout-check-gallery-1.log`: the old filter gave only `sim-gallery exit 1…`, the new one names the case (`closure-g1-filter-test.log`).
  * The static gate afterwards: `SIM-GALLERY OK 109 ok`, `CHECK-GALLERY OK 128 ok`, gate GREEN (`closure-gallery-after-simfix.log`, `closure-gallery-end.log`).
* **Second `rehearse.sh all` (12:28–12:50Z): rc 0** (`closure-rehearse-all2.log`; step logs `out/deploy-rehearsal/logs/`).
  * `UPLOAD DRY RUN OK`;
  * `GUARD OK` (10 misuses refused, sentinel bucket unchanged);
  * `UPLOAD OK` and `FAKE-BUCKET OK: 93 objects … size + sha256 equal`;
  * `FAKE-S3 OK` (8 JSON + 85 octet-stream, 3 multipart);
  * `ROLLBACK DRY RUN OK`, `ROLLBACK OK`, and refusals for a missing object and for another remote;
  * `deploy-dry` refusals (no record, record mismatch), then `RECORD OK` and `DEPLOY DRY RUN OK`;
  * `LOAD-R2 OK: 93 objects, 2.420 GB`;
  * `SMOKE OK` (168 URLs).

  Every G1 in it passed. As always, the rehearsal's steps reset their own scratch state (`guard-bucket`, `guard-out`, `state`, `fake-s3.jsonl`) and overwrite `out/deploy-rehearsal/logs/`.
* **Browser boot-check (14:44Z, inside this lane's lock hold).** It ran the same command as `rehearse.sh browser` (line 175), `node scripts/deploy-rehearsal/boot-check.mjs http://localhost:8790 out/deploy-rehearsal`, called directly because the step takes the lock itself. Result: `BOOT-CHECK OK http://localhost:8790/showcase/#hasse-view`, QED64 ready after 14 s, cursor on line 18, cross-origin isolated, HasseView panel rendered, every request to localhost:8790 (66), 26 R2 GETs, 676.3 MB, all 200 (`closure-rehearse-browser.log`). Its "page errors 1" also appears in the final-gate and multipin boot-checks; QED64's N1 `Error: unsupported` is the likely source (inference; the tool does not print the text). Afterwards `rehearse.sh stop` → `nothing listens on 8790`.

## (6) Untouched check

`scripts/assert-untouched.sh stamp closure` at 09:15:38Z, the lane's first command (`closure`'s stamp; the earlier lanes'
`closure` stamps were replaced). `check closure` at 14:48:54Z: rc 1, **`VERDICT: CHANGED`** (`closure-untouched-check.log`). It was repeated as the lane's last command, at 14:52:29Z after the doc edits, with an identical result: the same HEAD moves and the same 122 + 54 paths (`closure-untouched-check-final.log`). The findings:

* `wasm64-lean-kernel-build-v4.34.0`, `wasm64-lean-kernel`, `widgets-v4.34`: **OK**, no file newer than the stamp; kernel HEAD and diff hash unchanged.
* **QED64** `wasm64-lean-fable/qed64`: HEAD `3b42714` → **`3e182ff`** ("boot card stays for the whole boot on slow links; memory figure measured (HARDENING #54, widgets S1)", committed 2026-10-03T10:17:52Z). Also changed: 122 working-tree paths, including `frontend/src/*`, a `dist/` rebuilt at 09:21:24Z, `tests/adversarial/boot-card.mjs`, `docs/HARDENING.md` and `work/…`; 54 git objects; worktrees `qed64-wt-v2`, `qed64-wt-v2base` and branch `fix/v2-reload-oom`.
* **lean4game**: HEAD `476e8b6` → **`22eda45`** (commits `7dab308` 09:50Z, `18cc7da` 10:20Z "Sync the qed64 closure to 3e182ff", `22eda45` 11:59Z "UX-PARITY …").

**Attribution (inference from timestamps, commit messages and process lists).** These are other sessions of the user, not this lane:
* **The QED64 "boot-card" session.** It held the browser lock as `qed64-bootcard-head` (09:14:59Z) and `qed64-bootcard-fix` (10:03Z), running `serve-dist.mjs` and `tests/adversarial/boot-card.mjs` from inside the QED64 tree. It also appended "QED64 3e182ff (local, 2026-10-03): boot-card fix #54" to docs/NEXT-STEPS.md at 10:18Z.
* **The `qed64-v2-*` storm sessions.**
* **The `lean4game` session.** It held the lock at 10:20Z, 10:45Z and 11:35Z.

Process and mtime snapshots: `closure-foreign-activity-{1,2}.log`; commits and reflogs: `closure-untouched-attribution.log`.

**This lane in those trees.** It ran only read-only commands there: `git --no-optional-locks` via `assert-untouched.sh`, and `showcase.sh verify`, whose QED64 reads are `git show`. It wrote nothing and committed nothing (rule 2). The served pin is unaffected, because pins are verified clones (`release/5ac5d00`). `showcase.sh verify` at the end printed `VERIFY: all checks OK` with the 1 known Docker `DRIFT` (`closure-verify-end.log`). The changes were left in place.

## Contention and changes by others to this repo during the lane

* **Lock waits.** The browser lock was held by other sessions for long stretches. The first full run waited 2.5 min, the headed sign-off 60 min, `cp10` 36 min and `cp50` 30 min. The last three steps (p50, p10, soak, boot-check) therefore ran in one lock hold (13:32:16–14:44:27Z, `closure-chain3.log`). This lane stopped only its own waiting processes (`closure-chain2.log`).
* **A foreign edit of `scripts/with-browser-lock.sh`** (mtime 09:44:40Z, not by this lane) added "defer to an older waiter". Its `older_waiter` recognises a waiter only when its command line is `bash <absolute path of the script> …`. A waiter started as `bash scripts/with-browser-lock.sh …` (relative path, as this lane started chain 3) is invisible to the others, so they do not defer to it. That waiter still defers to visible older waiters (13:04Z: `deferring to an older waiter (qed64-v2-A3)`). At about 13:28Z `ps` showed it as the oldest waiter (30 min), with four younger visible waiters. A younger one, `qed64-v2-A2-2` (waiting since about 13:07Z), had taken the lock at 13:22Z ahead of it. Not changed here; reported for the owner of that edit.
* **Other foreign edits** to `docs/UPSTREAM-REPORT-QED64.md` (09:33Z) and `docs/NEXT-STEPS.md` (10:18Z, the appended 3e182ff section). This lane kept them.

## Files changed by this lane

`gallery/` was **not** changed. Pre-edit copies are in `$W/closure/pre-edit/`.
* `scripts/sim-gallery.mjs`: run 15a's status-line sampling waits for the tick (at most 350 ms).
* `scripts/deploy-manifest.mjs`: G1 keeps indented FAIL lines (better failure detail; the pass/fail rule is unchanged).
* `tests/ux/tools/throttle-proxy.mjs`: a FIFO per connection (byte order).
* `out/deploy/` regenerated (byte-identical).
* Docs: this file; docs/UX-RESULTS.md, README.md, docs/NEXT-STEPS.md, docs/DEPLOY-CLOUDFLARE.md, docs/HOUSEKEEPING.md, gallery/README.md and `out/ux/last-mile/RESULTS.md`.
* New run directories: `out/ux/closure-full{1,2}`, `closure-headed1`, `closure-throttle`, `closure-soak`.
* Diagnosis-only scripts (not shipped): `$W/closure/{stall-injector.mjs, proxy-order-test.mjs, sim-loop.sh, full-chain.sh, chain2.sh, inner3.sh}`.
