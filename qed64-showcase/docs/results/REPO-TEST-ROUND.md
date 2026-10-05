# Repository test round R4 (2026-10-04 22:14Z to 2026-10-05 14:39Z (finished by the orchestrator after a session usage limit stopped the lane))

A dated record of one full test round over the whole repository, in the main checkout and in a fresh clone. It is
history once written. **Current state is printed by commands, not by this file:** `./test-all.sh`,
`node showcase/verify.mjs`, and in `qed64-showcase/` `scripts/showcase.sh verify`, `scripts/showcase.sh gallery`
(`UX CURRENT …` or `UX STALE`), `scripts/showcase.sh pin list`, `node scripts/deploy-manifest.mjs --check` and
`node scripts/ux-tally.mjs`.

* **Tested commit:** `b10bcc5` (main checkout and fresh clone). It is `c19f9ff` (R3's last commit) plus this round's
  first commit: the README rewrite, the verdict-record fix (2.1 below) and a checklist wording change. The commit that
  adds this file also contains the `ux-tally.mjs` fix (2.2), the re-recorded `infra/ux-verdict.json`, the L9 note in
  docs/UPSTREAM-REPORT-QED64.md and doc updates; none of them changes what is built, served or tested.
* **Served pin:** E `33b0967` (QED64 main), runtime `wasm64-3ab1c6a9da03bc29`, lock `190f09de…`, gallery `3b4dc8bb…`,
  overlays widgets8 `a2306040…` and widgets7 `f3f7e694…`. These inputs did not change in this round.
* **Host:** macOS 26.6.2 on arm64 (Mac16,5, 36 GB), Node v26.3.0, elan 4.1.2, Chromium 151 (Playwright 1.62.1).
* **Logs:** `$W/logs/r4/` (`$W` = `/Users/fawadhaider/code/qed64-showcase-work`). UX run directories are under
  `out/ux/<run>/` of the checkout that ran them (machine-local).
* **Safety:** no push, no GitHub write, no Cloudflare login, deploy or R2 call. wrangler ran only as `--dry-run` and
  `dev --local`, rclone only against fake remotes. Every browser run went through the host browser lock (FIFO, shared
  with other sessions on this host). Nothing was deleted; see "Deletable" at the end.

## Result

| Area | Check | Result | Log (`$W/logs/r4/`) |
|---|---|---|---|
| Widget packages | `./test-all.sh` (9 packages, stock v4.34.0) | all 9 GREEN, rc 0 (16 s: the builds were up to date; the fresh builds are the CI run below) | `test-all.log` |
| Static showcase | `./showcase/build.sh` (dumps regenerated from the probes) + `node showcase/verify.mjs` | 8 packages, 60 panels; regenerated dumps == committed (`git status` clean); `react verification: 60/60 panels clean`, rc 0 | `static-showcase.log` |
| QED64 showcase | `showcase.sh verify` | **first FAILED** (pin-constants: a runtime buildId in `infra/ux-verdict.json`), fixed (2.1), then `VERIFY: all checks OK` | `main-verify.log`, `main-verify-2.log` |
| | `showcase.sh gallery` | GREEN on `3b4dc8bb…`: `CHECK-GALLERY OK 128 ok`, `SIM-GALLERY OK 114 ok` | `main-gallery.log` |
| | `showcase.sh pin list` / `pin current` | 5 pins (A–D staged, E active), rc 0; `PIN CURRENT OK 33b0967` (submodule HEAD == gitlink == pin, no modified file) | `main-pin-list.log`, `main-pin-current.log` |
| | `showcase.sh headless controls` (wasm runtime in Node) | `CONTROLS PASS`, 11/11 (4 of them negative controls that must fail, and did) | `main-headless-controls.log` |
| | `node scripts/check-portable.mjs` | `PORTABLE OK` (539 text files in 583 paths) | `check-portable.log` |
| | `node scripts/deploy-manifest.mjs --check` | `DEPLOY-MANIFEST CHECK OK`; at the end G2 named `r4-main-full4` (`deploy-manifest-check-final`: re-run by the orchestrator on 2026-10-05 after the session limit; `DEPLOY-MANIFEST CHECK OK`, `G2 UX: verdict run r4-main-full4 … was on THIS gallery 3b4dc8bb…, lock 190f09de…`) | `deploy-manifest-check-1.log`, `deploy-manifest-check-final.log` |
| | `node --test infra/worker.test.mjs` | 22/22 | (console; rerun in the CI job) |
| Browser, main | two consecutive full `ux` VERDICTs | **`r4-main-full3` and `r4-main-full4`, VERDICT each** (33 passed, 1 skipped). Before them: `r4-main-full1` VERDICT, then `r4-main-full2` **red: renderer crash in C10** (section 3) | `main-ux-full{1,2,3,4}.log` |
| | headed sign-off (`UX_HEADED_ALL=1`, Chrome for Testing) | **`r4-main-headed2`: 34 passed, HEADED SIGN-OFF**. Before it: `r4-main-headed1` **red: renderer crash in C10** (C14 failed with it) | `main-ux-headed{1,2}.log` |
| | 10 Mbit/s / 40 ms first visit, fresh profile | **`RESULT PASS`**, ready 565.1 s, error card in 0 samples, progress visible in 563/564 samples, 693.0 MB at 9.8 Mbit/s | `main-throttle10.log`, `out/ux/r4-throttle/explore/throttle-r4t10.json` |
| Deploy rehearsal | `rehearse.sh all` (fakes, offline sandbox) | rc 0: `GUARD OK`, `UPLOAD DRY RUN OK`, `UPLOAD OK` + `FAKE-BUCKET OK` (93 objects), `FAKE-S3 OK` (3 multipart), `ROLLBACK DRY RUN OK`, `ROLLBACK OK`, `RECORD OK`, `DEPLOY DRY RUN OK`, `LOAD-R2 OK` (2.420 GB), `SMOKE OK` (168 URLs) | `rehearse-all.log` |
| | `rehearse.sh browser` + `stop` | `BOOT-CHECK OK http://localhost:8790/showcase/#hasse-view` (ready after 14 s, 26 artifact GETs all 200, 676.3 MB); `stop`: nothing listens on 8790 | `rehearse-browser.log`, `rehearse-stop.log` |
| Fresh clone | `git clone --recursive` of `b10bcc5` | clean tree; submodule `deps/qed64` at `33b09679077b` (fetched from GitHub) | `clone-1.log` |
| | `showcase.sh bootstrap --origin http://localhost:5297` (the main checkout's `serve.mjs`), fresh work dir | `BOOTSTRAP OK` in 21 s: `SHELL-FROM-SOURCE OK` (58/58 files == lock), `FETCH-ARTIFACTS OK` (93 files, 2407.9 MB, every sha256 == lock), `VERIFY: all checks OK` | `clone-bootstrap.log` |
| | `showcase.sh verify`, `gallery`, `check-portable` | `VERIFY OK (1 N/A …)` (the kernel build is not set); gate GREEN on `3b4dc8bb…`; `PORTABLE OK` | `clone-verify.log`, `clone-gallery.log` |
| | one full `ux` run (the clone's own `serve.mjs` on :5190) | **`r4-clone-full1`: VERDICT** (33 passed, 1 skipped (C19), 23.1 min; served gallery == local `3b4dc8bb…` at start and end, origin the clone's own `serve.mjs` on :5190) | `clone-ux-full1.log` |
| | local CI runner, `lean-ci.yml`, every job in a fresh clone of `b10bcc5` | **`RUN-LOCAL OK`**: all 9 `packages` jobs, `showcase` and `qed64-static` SUCCESS; `pages` skipped by its condition | `clone-ci-lean-ci.log` |
| | `ci/rehearse-deploy.sh` (the `qed64-deploy.yml` job, 7 scenarios, fakes) | first attempt **failed** at its first step (a rehearsal-script defect, 2.3), fixed in `6ada0a1`; re-run in the clone updated to `6ada0a1`: 6 of 7 scenarios OK at once (`skip`, `dry-run`, `unpublished`, `deploy` incl. `SMOKE OK`, `first`, `tamper`); `no-verdict` failed only because GitHub was unreachable for 75 s while that scenario cloned the QED64 submodule (`curl 56 … Connection reset by peer`, then `Failed to connect to github.com port 443`), so it never reached G2; re-run alone once GitHub answered (`clone-ci-rehearse-deploy-3.log`, run dir `$W/r4/ci/rehearse-deploy-3`): `SCENARIO OK no-verdict: G2 refused a gallery that infra/ux-verdict.json does not name; wrangler was never called`. **All 7 scenarios OK** in the fresh clone. | `clone-ci-rehearse-deploy.log` |

Gate: green, with two defects found and fixed (section 2) and one upstream crash root-caused as far as this host
allows (section 3).

## 1. Main checkout

All commands ran in `widgets-v4.34/` (the repository root) or its `qed64-showcase/`, lane `r4`
(`SHOWCASE_LANE=r4`). Browser steps ran from `$W/r4/gates.sh`, `gates2.sh` and `gates3.sh`, each step through
`showcase.sh ux` or `with-browser-lock.sh`.

### Full UX runs on the served pin

| Run | When (UTC) | Result | C10 (reload storm) renderer | Reclaimable at start |
|---|---|---|---|---|
| `r4-main-full1` | 10-04 22:43–23:05 | 33 passed, 1 skipped (C19); **VERDICT** | peak 13.23 GB, settled 9.97 GB | 24.7 GiB |
| `r4-main-full2` | 23:05–23:28 | 32 passed, **1 failed (C10, renderer crash)**, 1 skipped; NOT A VERDICT | crashed | 26.5 GiB |
| `r4-main-headed1` (headed) | 23:28–23:59 | 32 passed, **2 failed (C10 renderer crash; C14 because of it)**; NOT A HEADED SIGN-OFF | crashed | 26.4 GiB |
| `r4-main-full3` | 10-05 00:36–00:59 | 33 passed, 1 skipped; **VERDICT** | peak 14.67 GB, settled 9.95 GB | 18.6 GiB |
| `r4-main-full4` | 00:59–01:22 | 33 passed, 1 skipped; **VERDICT** | peak 11.57 GB, settled 10.03 GB | 25.5 GiB |
| `r4-main-headed2` (headed) | 01:22–01:55 | **34 passed** (C19 included); **HEADED SIGN-OFF** | peak 13.79 GB, settled 10.35 GB | 24.2 GiB |

Every run was on gallery `3b4dc8bb…`, lock `190f09de…`, served pin `33b0967 wasm64-3ab1c6a9da03bc29`, and the served
gallery equalled the local one at start and end (`out/ux/showcase-ux-runs.jsonl`). `full3`, `full4` and `headed2` ran
with `DEBUG=pw:browser` so that a crash's V8 message would reach the log; none of them crashed. The throttled first
visit and the rehearsal's boot-check came between `headed1` and `full3`; other sessions held the lock for about 31 min
in between (`qed64-embed-editprobe`, `qed64-smoke`, `lean4game`), which only delayed the queue.

`infra/ux-verdict.json` was then re-recorded (`--record-verdict`): it names `r4-main-full4` on the same gallery, lock
and overlays as before (`record-verdict.log`). The CI deploy's G2 reads this file.

## 2. Defects found and fixed

### 2.1 `showcase.sh verify` failed on R3's tree (fixed in `b10bcc5`)

`verify` stopped at pin-constants with `FAIL runtime buildIds outside the generated pin sites (or != the active pin):
infra/ux-verdict.json:14: wasm64-3ab1c6a9da03bc29 (hardcoded runtime buildId: ask scripts/lib/pins.mjs)`
(`main-verify.log`). **Root cause:** R3's `deploy-manifest.mjs --record-verdict` (commit `71ba9ad`) wrote the active
runtime buildId into the committed record. The pin-constants scan, which allows a real buildId only in
`gallery/pin.json`, covers `infra/`. R3's own checks (the CI jobs, check-portable, the deploy rehearsal) do not run
`verify`, so nothing caught it. The failure matters for a clone: `bootstrap` ends with `verify`, so a fresh clone of
`c19f9ff` would have ended its bootstrap with `VERIFY: FAILED` (inferred from the same check; R2's clone proof predates
the record). **Fix:** G2 never reads the field (it compares gallery, lock and overlays), so the writer no longer emits
`buildId` and the committed record drops it. The scanner is unchanged. Evidence: `main-verify-2.log` (`VERIFY: all
checks OK`), the fresh clone's bootstrap (`VERIFY: all checks OK`), and the re-recorded file has no `buildId`.

### 2.2 `ux-tally.mjs` undercounted renderer crashes

R2 noted that `r2-main-full1`'s C10 crash was counted as "failed", not "crashed". `r4-main-full2` showed the same.
**Root cause:** the crash event and the failure race. The renderer dies, Playwright's next call on the page throws its
own `Assertion error`, the test fails, and the fixture computes the session's console verdict, all before the page's
`crash` event is delivered. The event then still reaches the session stream (`tests/C10.s14.console.jsonl`:
`{"kind":"crash","t":22639,…}`), but `tests/C10.json` says `"crashed": false`. **Fix:** `ux-tally.mjs` also counts a
test as crashed when one of its session streams has a `{"kind":"crash"}` line. Across all runs under `out/ux/`, the
two flags disagree only for `r2-main-full1` and `r4-main-full2` (both C10), and the tally's output changed only for
those two (`ux-tally-before-fix.txt` vs `ux-tally-after-fix.txt`). The suite itself is unchanged: the crash already
fails the test, so no run became a verdict through this gap.

### 2.3 `ci/rehearse-deploy.sh` failed in a fresh clone (fixed in `6ada0a1`)

Found when the session limit cut this round short and the orchestrator finished it. The rehearsal's first step starts
the wrangler stand-in (`scripts/deploy-rehearsal/wrangler-shim.sh`), which runs the pinned wrangler from
`infra/node_modules/.bin/`. In R3 the checkout that ran the rehearsal already had `infra/` installed; a fresh clone
does not, so the stand-in failed (`sandbox-exec: execvp() … infra/node_modules/.bin/wrangler … No such file`). The real
workflow was never affected: `deploy-app.sh` runs `npm ci --prefix infra` when wrangler is missing. **Fix:** the
rehearsal runs the same install before it starts the stand-in.

## 3. C10 crashes on E

`node scripts/ux-tally.mjs` (with the 2.2 fix) for pin E: C10 ran in 14 full runs of the main checkout; **crashed 3** (`r2-main-full1`, `r4-main-full2`, `r4-main-headed1`), passed 10, and 1 failed without a crash (`r1-relocated-full1`: the 5th reload landed at 16.0 s, over the test's 15 s budget). The fresh clone's `r4-clone-full1` (its own checkout, not in this tally) passed C10: first ready 9.4 GB, transient peak 14.81 GB, settled 9.9 GB, no crash.

The timelines from the session streams (times in ms since the session started):

* `r4-main-full2` (chrome-headless-shell): reloads at 4, 5019, 6016, 11184 and 12018 ms; the last load of the QED64
  frame at 20898; `[qed64] starting Lean` at 20947; `[lean:stderr] [boot] waited 314 ms for 1 stopping runtime(s)
  (25 → 12 Workers alive)` at 21478; further `starting Lean` lines at 21055, 21168 and 21653; **crash at 22639**.
* `r4-main-headed1` (Chrome for Testing 151, headed): reloads at 5, 4633, 6018, 11380 and 12016 ms; QED64 frame loads
  at 20680 and 21311; `[boot] waited 444 ms for 1 stopping runtime(s) (25 → 9 Workers alive)` at 21917; last
  `starting Lean` at 22149; **crash at 23573**.

Both crashes come 1.0–1.4 s after the last `starting Lean` (1.7 s and 2.2 s after the first one that followed the
last load), which is the L9 V2 timing
(docs/UPSTREAM-REPORT-QED64.md L9). Both happen after QED64's #55 lifetime lock waited for a stopping runtime, so the
wait ran and did not prevent the crash. The crash reason itself is not recorded: Playwright's `crash` event carries
none, macOS wrote no crash report for these two, and the three runs with `DEBUG=pw:browser` did not crash. R2's crash
(`r2-main-full1`, 2026-10-04 20:27Z) has a macOS report, `chrome-headless-shell-2026-10-04-162712.ips`: `SIGTRAP` on
thread 40, `DedicatedWorker thread`. That fits a V8 fatal error in a worker isolate, and V2 is a V8 OOM; that it was V2
is an inference. The two R4 crashes were the two runs that started with the most reclaimable memory (26.5 and 26.4
GiB, against 18.6–25.5 GiB), consistent with earlier lanes' "V2 on an idle host", but four non-crashing runs are not
evidence. This is QED64's defect; it is now in docs/UPSTREAM-REPORT-QED64.md L9. No assertion was changed: C10's
"no crash" stays, and the round's verdicts are the runs that passed it.

## 4. Fresh clone

`git clone --recursive "<main checkout>" $W/r4/clone/lean-widgets` at `b10bcc5`, with a fresh work dir
`QED64_SHOWCASE_WORK=$W/r4/clone/work`, no `.env.local`, no `QED64_REPO` and no kernel build; the commands are the
README's.

* **Bootstrap** (`clone-bootstrap.log`): sources (the submodule at the pin), `npm ci` (4 packages), the widget export,
  QED64's page built from the submodule with QED64's own `npm ci --prefix frontend && npm run build:site` (vite, 2932
  modules, 10.2 s) and installed because all 58 files equal the lock, 93 artifacts fetched from the main checkout's
  `serve.mjs` on :5297 and checked against the lock, the pin's serve links, then `verify`. `verify` lists the heavy
  path's build stores as ABSENT, the staged pins A–D as NOT MATERIALIZED and the kernel-build check as N/A, as
  documented.
* **UX** (`clone-ux-full1.log`): `r4-clone-full1` (2026-10-05 01:55–02:40Z, lane `r4clone`), the README's `scripts/showcase.sh ux`: 33 passed, 1 skipped (C19), **VERDICT**; served gallery == local `3b4dc8bb…` at start and end. C10 passed (no crash; peak 14.81 GB, settled 9.9 GB).
* **CI, `lean-ci.yml`** (`clone-ci-lean-ci.log`, run dir `$W/r4/ci/lean-ci-1`): `node ci/run-local.mjs --workflow .github/workflows/lean-ci.yml` (each job in a fresh clone of the clone's HEAD `b10bcc5`): `RUN-LOCAL OK`. The 9 `packages` jobs (8 widget packages + lean-widget-kit) SUCCESS; `showcase` SUCCESS (`DUMPS OK: 8 regenerated dumps == committed`, `react verification: 60/60 panels clean`; deviation logged: setup-node 22 requested, host node 26.3.0 used); `qed64-static` SUCCESS, 12/12 steps (`PORTABLE OK`, `LOCKFIFO OK` 7/7 FIFO, worker tests 22/22, the gallery gate `CHECK-GALLERY OK 128`); `pages` skipped by its condition.
* **CI, `qed64-deploy.yml`** (`clone-ci-rehearse-deploy.log`, run dir `$W/r4/ci/rehearse-deploy-1`): attempt 1 (`clone-ci-rehearse-deploy.log`) stopped at its first step: the wrangler stand-in starts `infra/node_modules/.bin/wrangler`, which a fresh clone does not have yet (2.3). After the fix, attempt 2 in the clone updated to `6ada0a1` (`clone-ci-rehearse-deploy-2.log`, run dir `$W/r4/ci/rehearse-deploy-2`): 6 of 7 scenarios OK at once (`skip`, `dry-run`, `unpublished`, `deploy` incl. `SMOKE OK`, `first`, `tamper`); `no-verdict` failed only because GitHub was unreachable for 75 s while that scenario cloned the QED64 submodule (`curl 56 … Connection reset by peer`, then `Failed to connect to github.com port 443`), so it never reached G2; re-run alone once GitHub answered (`clone-ci-rehearse-deploy-3.log`, run dir `$W/r4/ci/rehearse-deploy-3`): `SCENARIO OK no-verdict: G2 refused a gallery that infra/ux-verdict.json does not name; wrangler was never called`. **All 7 scenarios OK** in the fresh clone.

## 5. Not covered, and open points

* The workflows still have never run on GitHub (nothing was pushed). The local runner runs their `run:` steps on
  macOS arm64 with the host's warm caches (elan toolchains, `~/.cache/mathlib`, npm), not on `ubuntu-latest`.
* The light path was proven from a local origin. Until the showcase Worker is deployed, the widget overlays can only be
  fetched from a checkout that has them.
* `showcase.sh ux` starts its `serve.mjs` on :5190 before it queues for the browser lock and stops it after the lock is
  released. A second checkout that starts a `ux` run in that window finds :5190 answering; `server_is_showcase`
  accepts it when the served gallery and pin equal its own, so it would test the other checkout's server. The clone
  run here avoided this by waiting until :5190 was free, and its server's working directory was the clone's.
  Not changed in this round.
* The CI `qed64-static` job does not run `showcase.sh verify` (it needs the fetched binaries), so a regression like
  2.1 is caught only by a local `verify` or `bootstrap`. Not changed in this round.
* The renderer crash in C10 (section 3) remains QED64's. A pin whose runtime fixes it would need new storms and gates.

## Deletable (nothing was deleted)

This round's own directories (also see docs/HOUSEKEEPING.md for earlier lanes):

| Path | Size | What |
|---|---|---|
| `$W/r4/ci/lean-ci-1` | 49G | the local CI runner's job clones (mostly Mathlib `.lake`) |
| `$W/r4/ci/rehearse-deploy-1` | 2.3G | attempt 1 of the deploy rehearsal (APFS-clone state) |
| `$W/r4/ci/rehearse-deploy-2` | (APFS-clone state) | attempt 2 of the deploy rehearsal |
| `$W/r4/clone` | 4.8G | the fresh clone, its work dir and its UX run |

Keep `$W/r4/clone/lean-widgets/qed64-showcase/out/ux/r4-clone-full1` if the clone's verdict should stay inspectable.
