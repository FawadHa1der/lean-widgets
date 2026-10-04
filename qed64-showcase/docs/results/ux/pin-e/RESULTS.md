# Pin E `33b0967`: storms on the visitor path, switch, gates, deploy check (2026-10-04, 01:40–07:30 UTC)

Lane `pin-e` (logs `$W/logs/pinE2-*`, tools `$W/pinE2/`; `$W` = `/Users/fawadhaider/code/qed64-showcase-work`). E is QED64
main `33b0967`: the merge of `fix/v2-reload-oom` (`9c00688`, HARDENING #55, runtime lifetime locks: a booting runtime waits
while a stopping one keeps more than 12 Workers alive; QED64's fix for L9 V2) over `3e182ff` (HARDENING #54, the boot card
stays until ready), plus in-chunk download progress (`5e94697`, `76be299`). E runs on D's runtime
`wasm64-3ab1c6a9da03bc29` and stores (registered and headless-checked by the pinE lane, docs/REPIN-LOG.md "pin E").

Current state is printed by `scripts/showcase.sh pin list`, `scripts/showcase.sh gallery` and
`node scripts/deploy-manifest.mjs --check`. The figures below are this lane's (history once written).

## Answer

* **Storms (visitor path, `/showcase/#hasse-view`, E vs C interleaved in the same windows):** headed Chrome for Testing
  **E 0/20, C 0/20**; chrome-headless-shell **E 0/8, C 1/8** (one V2). E's storms are at least as clean as C's, so by
  the rule E became the served pin. Fisher: headed p = 1.0; headless-shell two-sided p = 1.0, one-sided (C > E) p = 0.5;
  any crash pooled 0/28 vs 1/28, p = 1.0.
* **This does not confirm QED64's #55 fix on our side.** C itself had 0/20 headed V2 in these windows (v2-embed lane,
  2026-10-03, same tool and path: C 15/24). With C at 0/20 the experiment has no power to show a reduction; it shows
  only that E is not worse. QED64's own data (headed embedded storms 17/48 → 0/36) remains their measurement.
  Probable reason for the low C rate (inference, not shown): the host had about 15–17 GB reclaimable instead of
  20.7–22.9 GB (the user's desktop apps held about 10 GB in the compressor), and the renderer peaked at about 10 GB
  instead of about 12 GB. Earlier lanes already saw V2 most often on an idle host. The gallery also changed since
  v2-embed (`31f6d8d9…` → `b7aa521a…` → `bbdbc932…`), which is an untested second difference.
* **Switched:** `pin use 33b0967` (05:18:08Z) → `PIN SWITCHED 5ac5d00 -> 33b0967`, `PIN CURRENT OK 33b0967` (overlay runtime checks
  OK); `verify` → `VERIFY: all checks OK` (the known Docker DRIFT); `gallery` → gate GREEN on `bbdbc932…`
  (`CHECK-GALLERY OK 128 ok`, `SIM-GALLERY OK 114 ok`). The new `gallery/` is byte-identical to the copy the E storms
  were served from (`diff -r`, `$W/logs/pinE2-gallery-vs-storm.log`).
* **Gates on the served E and gallery `bbdbc932…`:** `pinE-full1` and `pinE-full2`, 33 passed, 1 skipped (C19), each
  **VERDICT**, back to back; `pinE-headed1` 34 passed (C19 included), **HEADED SIGN-OFF**; 10 Mbit/s first visit
  **`RESULT PASS`, rc 0**, ready 565.1 s, error card in 0 samples, panel equal to golden.
* **Deploy:** manifest regenerated (byte-identical to the one `pin use` wrote), `--stage-assets` OK,
  **`DEPLOY-MANIFEST CHECK OK`** with `G2 UX: verdict run pinE-full2 … was on THIS gallery bbdbc932…, lock
  fa3e31b06f1e…`. Rehearsal: `rehearse.sh all`, `browser` (`BOOT-CHECK OK`) and `stop`, rc 0 each.

## 1. Storms

| arm | runs | V2 | rate (Wilson 95 %) | other crashes | not ready after storm | quiet at launch | document as intended | first ready (median) | ready again (median) |
|---|---|---|---|---|---|---|---|---|---|
| E `33b0967`, headed | 20 | **0/20** | 0 % (0–16 %) | – | 0 | 19/20 | 20/20 | 14.64 s | 7.40 s |
| C `5ac5d00`, headed | 20 | **0/20** | 0 % (0–16 %) | – | 0 | 18/20 | 20/20 | 14.57 s | 7.24 s |
| E `33b0967`, headless-shell | 8 | **0/8** | 0 % (0–32 %) | – | 0 | 8/8 | 8/8 | 14.29 s | 7.25 s |
| C `5ac5d00`, headless-shell | 8 | **1/8** (`e08-C-hs`) | 12 % (2–47 %) | – | 0 | 8/8 | 8/8 | 14.15 s | 7.17 s |

Every run that did not crash was ready again after the storm (120 s budget). Table with all 56 rows (host state,
result, crash time, ready times, renderer peak, document sha, scale pin, browser): `out/ux/pin-e/storm-table.md` /
`.json`, from `$W/pinE2/tabulate.py` (`$W/logs/pinE2-storm-tabulate.log`).

* **The one crash** (`e08-C-hs`, 05:16:20Z): `V8 javascript OOM (MarkCompactCollector: young object promotion failed)`
  1885 ms after reload 3; the crashing isolate's last GC was `Scavenge 15.8 (16.3) -> 15.3 (16.2) MB` at 412 ms. That
  is the L9 V2 fingerprint.
* **Halves (headed):** reps 1–10 E 0/10, C 0/10; reps 11–20 E 0/10, C 0/10. By position in the rep: 0 crashes headed in
  either position; headless-shell C first 1/4.
* **Worker timing at the reloads** (from the tool's 250 ms samples, `$W/logs/pinE2-storm-worker-timing.log`): reload →
  first new worker, median 576 ms (E headed) vs 573 ms (C headed), 447 vs 414 ms headless-shell; the live-worker count
  drops to 0–1 within 3 s after every reload in all arms. Peak live workers 27 and 158 created / 132 closed in every run
  of both pins. So #55's wait is not visible at this granularity (inference: the old page's workers were already gone
  before the new runtime booted, so the lock had nothing to wait for). Ready again after the storm is 0.16 s slower on E
  (medians 7.40 vs 7.24 s headed).
* **Renderer peak** (RSS sampler on the run's own process tree): headed 9.4–11.1 GB, median 9.9 GB (E) and 10.0 GB (C);
  headless-shell 9.7–11.6 GB. The v2-embed lane measured medians of 11.8–12.1 GB.

### Design

* **Servers:** `SHOWCASE_PIN=33b0967 GALLERY_DIR=$W/pinE2/gallery-E PORT=5241 scripts/serve-start.sh` and
  `SHOWCASE_PIN=5ac5d00 GALLERY_DIR=$W/pinE2/gallery-C PORT=5243 …`; `:5190` was not touched. The gallery copies came
  from `$W/final-gate/pin-gallery.mjs` (`SELF-CHECK OK` for C; `diff -r` vs `gallery/`: C none, E only `pin.json`).
  `X-Showcase-Pin: 33b0967 wasm64-3ab1c6a9da03bc29` and `5ac5d00 wasm64-4b025db7729c5f89`. E's served bundle and
  `workers/lean.worker.js` contain `qed64-alive` / `qed64-wanted` (the #55 lock names); C's contain neither
  (`$W/logs/pinE2-served-content.log`). Both servers were stopped before the switch.
* **Tool:** `$W/v2embed/reload-storm-embed.mjs --entry showcase --path '/showcase/#hasse-view'`, the v2-embed lane's
  arm S unchanged (fresh profile, boot to ready, reloads at 0/3/6/9/12 s with `waitUntil: 'commit'`, 120 s for ready
  again, crash = the page `crash` event, `DEBUG=pw:browser` for the OOM line, the checked document recorded).
  Headed launches carry `--force-device-scale-factor=1` (40/40 runs). Browser 151.0.7922.34 in all 56 runs: Chrome for
  Testing (headed) and chrome-headless-shell.
* **Order:** per rep, both pins back to back, odd reps E first and even reps C first; 4 reps (8 runs) per batch, 8 s
  between runs. Headed reps 1–12 ran under `$W/pinE2/master.sh` (three lock holds, 02:52–03:20Z); headed 13–20 and
  headless-shell 1–8 ran under `$W/pinE2/master2.sh` (one lock hold, 04:34–05:17Z). Smoke runs `smoke-E-hd`,
  `smoke-C-hd` (no crash) validated the tool and are not counted.
* **Quiet streaks:** every batch began after a ≥ 300 s quiet streak (`out/ux/pin-e/explore/quiet-poll.tsv`). Each run's
  host state is in `explore/host-state.tsv`. Swap stayed at 509.75 MB in all 56 runs, and every run started within
  0–1 s.

### Deviations (each forced by the host, recorded as it happened)

1. **Quiet threshold 14 GB instead of 20 GB.** With no foreign process running, the host's idle baseline was a flat
   15.0 GB reclaimable (01:45–02:47Z, `quiet-poll.tsv`; `top`: the user's own Claude, VS Code Lean servers, Codex and
   other apps, about 10 GB in the compressor). The 20 GB rule of the earlier lanes could not be met, and those apps are
   not ours to stop. The first master (`$W/logs/pinE2-storm-master-hd-attempt1-20GB.log`) polled from 01:45Z without a
   streak and was stopped. Runs launched at 14.8–17.1 GB reclaimable. The E/C contrast is within-window and
   interleaved, so the threshold applies to both arms equally. The low C rate above may be its consequence (inference).
2. **Idle lock waiters are not "heavy".** `final-gate/host.sh` `foreign()` counts any process whose command line names
   `lv-live*`, including the lean4game session's `with-browser-lock.sh` wrappers that are only waiting for the lock.
   That session kept up to three hour-long jobs queued from 03:29Z, so no streak was possible. `master2.sh` queues FIFO
   for the lock like every other lane, takes the 300 s streak INSIDE the hold before each batch, and counts waiting
   wrappers (not the holder) separately (`$W/pinE2/host2.sh`; the column `waiters:` in both TSVs). A waiter cannot start
   a browser while this lane holds the lock.
   The rows `e11-C-hd`, `e12-C-hd` and `e12-E-hd` (first master, inside its own hold) list such lean4game names and are
   counted "not quiet" under the original rule. The lock was ours then, so they were waiters (inference from the lock
   file, which named pid 25269 as the next holder at 03:29:57Z).
3. **Own wait loops counted as foreign.** For about 10 minutes (02:30–02:44Z) the poll listed `lv-live4r2(…)` entries
   that were this lane's own shell wait loops (their command lines contained that string). They were stopped. No batch
   ran in that period.

## 2. Switch to E

`showcase.sh stop` was refused because there was no owner file: nothing listened on `:5190` (checked with `lsof` and
`curl`), so there was nothing to stop. `pin use 33b0967 --dry-run` listed the 15 links. Then `pin use 33b0967`
(`$W/logs/pinE2-pin-use.log`, rc 0):

* 15 links switched to `pins/33b0967` and `runtimes/wasm64-3ab1c6a9da03bc29`;
* `build-gallery` wrote `gallery/pin.json` (pin `33b0967`, buildId `wasm64-3ab1c6a9da03bc29`, lean 4.34.0) and
  `examples.json` unchanged in content;
* deploy inputs regenerated (`DEPLOY-MANIFEST OK 75 assets, 93 R2 objects; gallery bbdbc932…`, `STAGE-ASSETS OK`);
* `PIN CURRENT OK 33b0967`, both overlays `index runtime wasm64-3ab1c6a9da03bc29 == active lock runtime`.

`verify` (`pinE2-verify-after-switch.log`): `PIN CURRENT OK 33b0967`, `VERIFY OK (1 DRIFT in a rebuild-only input)`,
`PIN CHECK OK` for A, B, C and D, `VERIFY: all checks OK`. `gallery` (`pinE2-gallery-after-switch.log`): GREEN on
`bbdbc932cc4497bd…`, then `UX STALE` (expected before the runs).

## 3. Gates on the served pin (chain `$W/pinE2/gates.sh`, each step under the browser lock)

| run | when (UTC) | result | log |
|---|---|---|---|
| `pinE-full1` | 05:22–05:46 | 33 passed, 1 skipped (C19); **VERDICT** on `bbdbc932…`; C10 storm: no crash, transient peak 9.29 GB | `pinE2-ux-full1.log` |
| `pinE-full2` | 05:46–06:27 (lock wait behind lean4game first) | 33 passed, 1 skipped; **VERDICT**; C10: no crash, peak 12.69 GB, settled 9.92 GB | `pinE2-ux-full2.log` |
| `pinE-headed1` (`UX_HEADED_ALL=1`, warm headed profile) | 06:27–06:53 | **34 passed** (C19 included); **HEADED SIGN-OFF**; C10 headed: no crash | `pinE2-ux-headed1.log` |
| throttled first visit, 10 Mbit/s / 40 ms (`throttle-proxy.mjs` :5198 → serve :5197, `throttled-first-visit.mjs --no-cdp --max-s 1200 --tag pe10`) | 06:53–07:06 | **`RESULT PASS`, rc 0** | `pinE2-throttle10.log`, `out/ux/pinE-throttle/explore/throttle-pe10.json` |

**The throttled first visit on E, compared with C's (`postaudit-throttle/throttle-pa10`, same gallery code):**

| | C (post-audit lane) | E (this lane) |
|---|---|---|
| ready | 565.0 s | 565.1 s |
| error card | 0 samples | 0 samples |
| visible progress before ready | 563/564 samples | 563/564 samples |
| longest unchanged progress text/bar | 19.0 s | **6.0 s** (in-chunk progress, `5e94697`/`76be299`) |
| QED64's boot card | removed at about 231 s; from then on only the top-bar pill | **shown until ready** (#54): step, bytes, rate, time left |
| gallery notice "Still downloading …" | from 231.5 s (the early path: card gone and bytes recent) | from **466.9 s** |
| panel at ChartKit's first cursor | equal to golden | equal to golden |
| downloads | 693.0 MB at 9.8 Mbit/s | 693.0 MB at 9.8 Mbit/s |

Why the notice comes at 466.9 s (from `gallery/gallery.js` `bootNotice`, matched by the samples): the first-boot wait
starts when the page publishes `globalThis.qed64` (here at 107.3 s). The notice shows when the wait is 360 s old
(`BOOT_TIMEOUT_MS`) while progress continues, or already at 120 s (`BOOT_NOTICE_MS`) if QED64's own `#boot` overlay is
gone and bytes arrived within 30 s. On E the overlay stays, so only the 360 s path applies: 107 + 360 ≈ 467 s. This is
the intended behaviour, and the visitor sees progress throughout (QED64's card). The screenshot at 481 s
(`out/ux/pinE-throttle/screens/throttle-pe10-0481s.png`) shows both, with no overlap and the status pill uncovered.
The card's own text says "about 600 MB" for a first visit; with our widgets region it is about 693 MB (measured above).
That is QED64's text and not changed here.

## 4. Deploy

* `node scripts/deploy-manifest.mjs generate` rc 0 (`pinE2-deploy-manifest-generate.log`): `G1 … CHECK-GALLERY OK 128 ok`
  on `bbdbc932…`, `DEPLOY-MANIFEST OK 75 assets, 93 R2 objects`; `out/deploy/manifest.json` byte-identical to the one
  `pin use` wrote (`cmp`). `--stage-assets` → `STAGE-ASSETS OK out/deploy/assets (17.6 MiB)`.
* `--check` rc 0 (`pinE2-deploy-manifest-check.log`): `G2 UX: verdict run pinE-full2 (2026-10-04T06:27:19Z) was on THIS
  gallery bbdbc932cc4497bd…, lock fa3e31b06f1e… and overlays widgets8, widgets7`, `DEPLOY-MANIFEST CHECK OK`.
* Rehearsal (`pinE2-deploy-rehearsal-{all,browser,stop}.log`, rc 0 each): `rehearse.sh all` → `GUARD OK` (sentinel
  bucket unchanged), the previous fake bucket (93 files) moved aside to `$W/deploy-rehearsal/bucket.prev-20261004T071450Z`,
  `UPLOAD OK`, `FAKE-BUCKET OK: 93 objects`, `FAKE-S3 OK` (3 multipart), `ROLLBACK DRY RUN OK`, `ROLLBACK OK` (and the
  three negative controls refused as expected), `RECORD OK`, `DEPLOY DRY RUN OK`, `LOAD-R2 OK: 93 objects, 2.420 GB`,
  `SMOKE OK` (168 URLs, Range checks). `rehearse.sh browser` (one lock hold) → `BOOT-CHECK OK
  http://localhost:8790/showcase/#hasse-view`: QED64 ready with hasse-view after 14 s, panel rendered, every request to
  localhost:8790, 26 artifact GETs all 200, 1 page error (as in the earlier rehearsals; the tool does not print it, so
  it being QED64's N1 `Error: unsupported` is an inference). `rehearse.sh stop` → nothing listens on 8790.

## 5. Read-only trees

* **Stamp:** `scripts/assert-untouched.sh stamp pinE2` (01:40:36Z), then `stamp pinE` (01:40:43Z) as the brief asked
  (`$W/logs/pinE2-stamp.log`, `pinE-lane2-stamp.log`). Re-stamping `pinE` overwrote the pinE lane's
  `out/.stage-stamp-pinE.state` of 2026-10-04 00:34Z. That lane's stamp output and its `check pinE` result are still in
  `$W/logs/pinE-stamp.log` and `pinE-untouched-check.log`, and the empty marker file was copied to
  `$W/pinE2/stage-stamp-pinE.prev-lane`.
* **Check:** `check pinE` and `check pinE2` both give rc 1, **`VERDICT: CHANGED`** (`pinE2-untouched-check-pinE.log`,
  `pinE2-untouched-check-pinE2.log`). Attribution (`pinE2-untouched-attribution.log`, read-only `git
  --no-optional-locks`):
  * **QED64:** HEAD is still `33b09679077b…`, with 0 porcelain lines. The 11 paths newer than the stamp are all under
    `work/` (git-ignored, `.gitignore:6`): `work/lv-live4r2-{slow,slow-D5,offline,tabs,tabs-dwell,boot-D4,boot-D7,
    boot-landing}.mjs`, `work/lv-live4r2b-{offline,rag}.mjs` and the directory itself. These names are the scripts that
    the lean4game session ran under the browser lock as lane `lean4game` during this lane (`quiet-poll.tsv`, the lock
    file), so the writes are inferred to be that session's. This lane never wrote there: it read QED64 only through the
    `release/` clones and served them.
  * **wasm64-lean4game:** HEAD moved `0f2ecb7` → `4083fb4` through three commits by that session (2026-10-04 01:22 and
    02:57 local: "Prepare waits for the first service worker …", "UX-PARITY: round 2 …", "Boot banner: …"). The
    ` M .vscode/settings.json` line was already in the stamp.
  * Both kernel trees and `widgets-v4.34`: OK, no file newer than the stamp.

## Files

* `out/ux/pin-e/storm-table.{md,json}`, `out/ux/pin-e/explore/` (56 storm JSON + stdout + RSS files, 2 smoke runs,
  `host-state.tsv`, `quiet-poll.tsv`); `out/ux/pinE-full1/`, `pinE-full2/`, `pinE-headed1/`, `pinE-throttle/`.
* `pins/33b0967/pin.json` and `pins/5ac5d00/pin.json`: only the hand-written `status` role note changed (E active, C
  the fallback); the originals are in `$W/pinE2/pin-json-before/`. `verify` afterwards: all checks OK, `PIN CURRENT OK
  33b0967` (`pinE2-final-verify.log`).
* Deletable later (nothing was deleted): `$W/deploy-rehearsal/bucket.prev-20261004T071450Z` (the previous fake bucket,
  93 files) and `$W/pinE2/gallery-{C,E}`, once the storm evidence is no longer needed.
* Tools (work dir, not shipped): `$W/pinE2/{run-arm.sh, master.sh, master2.sh, host2.sh, tabulate.py, gates.sh}`; the
  gallery copies `$W/pinE2/gallery-{C,E}` (APFS clones, the evidence of what was served).
