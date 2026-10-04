# Why the gallery entry raises L9 V2: a three-arm (plus two) headed reload-storm experiment (2026-10-03, 06:55–09:12 UTC)

Lane `v2-embed`. Background: V2 (`MarkCompactCollector: young object promotion failed` about 2 s after a reload) hit
`/showcase/` much more often than the stock page. In the final gate's quiet round it was 6/9 through `/showcase/` and 0/9 on
the stock page, with the same `widgets8` overlay (`out/ux/final-storm/RESULTS.md`). The v2mit control arm (headed
`/showcase/`) had 8/24 (`out/ux/v2mit-storm/RESULTS.md`). The question here: is the cause **embedding per se** (the stock
page running inside a same-origin iframe), so that I ≈ S > P, or the **gallery's own code**, so that S > I ≈ P?

## Answer

| arm | what the top-level page is | boot document | runs | **V2** | rate (Wilson 95 %) |
|---|---|---|---|---|---|
| **S** | the gallery `/showcase/#hasse-view` | hasse-view example (seeded by the gallery) | 24 | **15/24** (+1 other OOM) | 62 % (43–79 %) |
| **P** | the stock page `/?snapshots=snapshots/widgets8` | QED64's default document | 24 | **2/24** | 8 % (2–26 %) |
| **I** | test page: one `<iframe>` of the stock page, no script | QED64's default document | 24 | **6/24** | 25 % (12–45 %) |
| Is | the same test page as I | hasse-view example (seeded) | 24 | **10/24** | 42 % (24–61 %) |
| Ps | the stock page, as P | hasse-view example (seeded) | 24 | **2/24** | 8 % (2–26 %) |

All 120 runs: headed Chrome for Testing 151.0.7922.34, `--force-device-scale-factor=1` (the harness pin), pin C `5ac5d00`.
All 120 were quiet at launch, and each of the 12 batches started right after a ≥ 300 s quiet streak (see "Host state").

**Decision: mainly embedding per se. Gallery code adds at most an increment that this experiment did not show to be real.**

* **Embedding raises V2 when the boot document is held equal.**
  * With the gallery's document, the test page vs the stock page: Is 10/24 vs Ps 2/24. Fisher two-sided p = 0.017.
  * Pooled over both documents: embedded (I+Is) 16/48 vs top level (P+Ps) 4/48. p = 0.005; Mantel–Haenszel odds ratio by
    half 7.9 for Is vs Ps.
  * The test page has no script at all. It is ten lines (`$W/v2embed/gallery-embed/embed-test.html`), so nothing of the
    gallery runs in it.
* **Gallery code on top of embedding: not significant.**
  * S 15/24 vs Is 10/24: same embedding, same document, only the gallery's JS and layout differ. Two-sided p = 0.25,
    one-sided p = 0.12.
  * Counting the one extra non-V2 OOM in S (any crash): 16/24 vs 10/24, one-sided p = 0.07.
  * The two halves disagree. Reps 1–12: S 9/12, Is 4/12. Reps 13–24: S 6/12, Is 6/12.
  * So a gallery-code effect of roughly +20 points is neither shown nor excluded. Embedding accounts for about 33 of the
    54 points between S and Ps.
* **The three arms in the lane's question alone would mislead.** S 15/24, I 6/24, P 2/24 reads as "S > I ≈ P":
  * S vs I: p = 0.019.
  * I vs P: p = 0.25.
  * This reading is confounded. The gallery seeds `localStorage['qed64.buffer']` (the stock page's boot document) with
    the example. A plain iframe of `/?snapshots=snapshots/widgets8` boots QED64's default document instead (`import
    Mathlib.Basic.Real.Basic`, 252 chars, sha12 `9f943fb19cbe`, vs hasse-view's `import Mathlib` / `import HasseView`,
    1396 chars, `b474a9cc8345`). The two seeded arms Is and Ps were added to remove this confound (deviation from the
    brief, see "Design").
* **The document alone does nothing at top level.** Ps 2/24 = P 2/24.
  * Inside the iframe the hasse document gave more V2 than the default one: Is 10/24 vs I 6/24, p = 0.36, not
    significant.
  * So there may be an interaction: a heavier boot document matters only when embedded. That is an inference, not shown.
* **What this means for the project (inference).**
  * A gallery-side change cannot remove the main factor, because the gallery is defined as the stock page in an iframe.
  * The v2mit A/B (a gallery `pagehide` teardown: 10/24 vs 8/24) is consistent with this.
  * For QED64 the result gives a **repro without our gallery**: the stock page inside a script-free same-origin iframe
    has 3–5× the V2 rate of the same page at top level under the same reload storm. docs/UPSTREAM-REPORT-QED64.md (L9) does
    not yet say this. This lane did not edit it (lane scope: this file only).

## Fisher tests (V2; `$W/v2embed/tabulate.py`, exact two-sided, plus one-sided for the named direction)

| contrast | what it isolates | V2 | two-sided p | one-sided p |
|---|---|---|---|---|
| S vs P | everything (the lane's original gap) | 15/24 vs 2/24 | < 0.001 | < 0.001 |
| I vs P | embedding, default document | 6/24 vs 2/24 | 0.245 | 0.122 |
| **Is vs Ps** | **embedding, gallery document** | **10/24 vs 2/24** | **0.017** | 0.009 |
| **I+Is vs P+Ps** | **embedding, pooled** | **16/48 vs 4/48** | **0.005** | 0.002 |
| **S vs Is** | **gallery code (embedding and document equal)** | **15/24 vs 10/24** | **0.248** | 0.124 |
| S vs I | gallery code + document | 15/24 vs 6/24 | 0.019 | 0.009 |
| S vs I+Is | gallery code vs the script-free embed (both documents) | 15/24 vs 16/48 | 0.024 | 0.018 |
| Ps vs P | document, top level | 2/24 vs 2/24 | 1.000 | 0.696 |
| Is vs I | document, embedded | 10/24 vs 6/24 | 0.359 | 0.179 |
| Is+Ps vs I+P | document, pooled | 12/48 vs 8/48 | 0.452 | 0.226 |

Any crash, counting S's one non-V2 OOM: S vs Is 16/24 vs 10/24 (p = 0.147 two-sided, 0.073 one-sided); S vs I 16/24 vs
6/24 (p = 0.008).

## Crash fingerprint and timings (`$W/logs/v2embed-arm-stats.log`)

* **Every crash is the L9 V2 fingerprint**, in all arms, with one exception (below).
  * 1998–2360 ms after reload 1, 2, 3 or 4.
  * The crashing isolate's last GC was a `Scavenge` at 15.8 MB in all 35 V2 crashes, 285–419 ms after the isolate
    started (the final gate's "300–355 ms old, 15.8 MB").
  * Reload index of the crashes: S 3/8/5 crashes after reloads 2/3/4; Is 1/3/6; I 0/2/4; P one after reload 1, one after
    reload 3; Ps one after reload 3, one after reload 4.
* **One S run (`e11-S`) died differently.** It was `V8 javascript OOM (CALL_AND_RETRY_LAST)`, 2125 ms after reload 4, from
  an isolate 1074 ms old: two last-resort `Mark-Compact (reduce)` GCs at 18.4 → 18.0 MB. It is not counted as V2 and is
  reported separately. It is the same moment and the same kind of per-isolate heap exhaustion (inference).
* **Boot to first ready (median):**

  | arm | median |
  |---|---|
  | S | 14.43 s |
  | Is | 14.22 s |
  | Ps | 14.07 s |
  | I | 13.78 s |
  | P | 13.63 s |

* Ready again after a storm that did not crash: S 7.12 s, Is 6.80, Ps 6.73, I 6.51, P 6.32 (medians).
* Renderer RSS peak medians were 11.8–12.1 GB in all arms.
* Every run had at most 27 live workers.
* No non-crash failure in 120 runs: every run that did not crash was ready again after the storm.
* V2 by a run's position inside its rep (each rep runs 5 arms; the order rotates per rep, so every arm sits in every
  position 4–5 times): 5/24, 6/24, 6/24, 9/24 and 9/24 for positions 0 to 4. That is a mild drift towards later positions
  that is balanced across arms.

## Design and what ran

* **Server.** One `serve.mjs` on `:5231` for all arms:
  * `SHOWCASE_PIN=5ac5d00 GALLERY_DIR=$W/v2embed/gallery-embed PORT=5231 scripts/serve-start.sh`.
  * It answered `X-Showcase-Pin: 5ac5d00 wasm64-4b025db7729c5f89`.
  * The copy was made by `$W/final-gate/pin-gallery.mjs 5ac5d00` (SELF-CHECK OK); `diff -r` against `gallery/` differs only
    in the added `embed-test.html`.
  * Served gallery content `31f6d8d9…` == local (`ux-record.mjs served`; `$W/logs/v2embed-served-hash.log`).
  * Stopped at the end (`$W/logs/v2embed-serve-stop.log`).
* **Test page (arm I/Is), test-only and not shipped.** `$W/v2embed/gallery-embed/embed-test.html`, served at
  `/showcase/embed-test.html`.
  * It holds one full-window `<iframe src="/?snapshots=snapshots/widgets8">` with the gallery iframe's own attributes
    (`allow="clipboard-read; clipboard-write"`), and no script.
  * It is not a shipped gallery file (not in the content hash). `gallery/` was not changed: still `31f6d8d9…`
    (`$W/logs/v2embed-gallery-unchanged.log`).
* **Tool.** `$W/v2embed/reload-storm-embed.mjs`, a copy of `tests/ux/tools/reload-storm-desktop.mjs`. The diff is in
  `$W/logs/v2embed-tool-diff.log`.
  * The storm itself is unchanged: fresh profile, boot to ready, reloads at 0/3/6/9/12 s with `waitUntil: 'commit'`,
    120 s for ready again, crash = the page `crash` event, `DEBUG=pw:browser`.
  * Added `--entry frame`: ready = the iframe's `qed64.status().phase === 'ready'`, the same read as the showcase entry's
    `qed64Phase`.
  * Added `--seed <example>`: one `page.addInitScript` that writes `localStorage['qed64.buffer']` in frames at `/` if the
    key is absent. It is a no-op script in unseeded arms, so every arm has exactly one init script.
  * Added a record of the checked document (`relay.lastText` length/sha12) at first ready and after the storm. All 120
    runs booted the intended document (column `docOk`).
  * The repo tool is untouched.
* **Arms (`$W/v2embed/run-arm.sh`).**
  * S `--entry showcase --path '/showcase/#hasse-view'`.
  * P `--entry stock`.
  * I `--entry frame --path /showcase/embed-test.html`.
  * Is = I `--seed hasse-view`.
  * Ps = P `--seed hasse-view`.
  * All `--headed` (Chrome for Testing; `launch()` adds `--force-device-scale-factor=1` headed, confirmed in every run's
    stderr: column `dsf1`).
* **Order (`$W/v2embed/master.sh`).**
  * Batches of 2 reps × 5 arms, interleaved arm by arm, in ONE `with-browser-lock.sh` hold per batch.
  * Arm order rotated per rep.
  * 12 batches = 24 reps per arm: reps 1–12 in `$W/logs/v2embed-master.log`, reps 13–24 in
    `$W/logs/v2embed-master-ext.log`.
  * The brief asked for ≥ 12 per arm. After 12 reps the gallery-code contrast was borderline (S 9/12 vs Is 4/12), so the
    same master ran 12 more reps with the arms and rules unchanged.
  * Smoke runs `smoke-*` (one per arm, `$W/logs/v2embed-smoke.log`) validated the tool and are not in any table.
* **Deviation from the brief: two more arms, and no G arm.**
  * Is and Ps were added because the gallery seeds the boot document (above).
  * G (the gallery with its liveness probe and bridge polling off) was not run:
    * The only existing switch is `?liveness=off`. No query option disables the bridge or the 250 ms `monitor()` loop.
    * On pin C, QED64 has its own liveness, so the gallery's probe defers (`PROBE_DEFER_MS` 30 s) and acts only while
      `elaborating` without progress. It cannot send a probe inside a storm with a 3 s cadence (inference from the code).
    * G would therefore have tested close to nothing.
* **Host state.**
  * Every batch started after a ≥ 300 s quiet streak (≥ 20 GB reclaimable, no foreign heavy process, swap not growing;
    the final-gate rule, `explore/quiet-poll.tsv`).
  * The lock was obtained 0 s after each streak, with no contention.
  * Per run (`explore/host-state.tsv`): 20.7–22.9 GB reclaimable, swap 517.8–533.8 MB, no foreign heavy process; 113 runs
    waited 0 s for memory, 7 waited 1 s.
* **Tables.** `$W/v2embed/tabulate.py` → `storm-table.json`, `storm-table.md` (all 120 rows: host state, result, variant,
  crash time, OOM lines, ready times, renderer peak, document sha, scale pin); output in `$W/logs/v2embed-tabulate.log`.

## Caveats

* **The absolute rates are not comparable with earlier windows.** Today S (headed `/showcase/#hasse-view`) is 15/24. The
  v2mit control was 8/24, and the final-gate quiet round 1/3, both through plain `/showcase/`, which opens `chart-kit`
  first.
  * The document, the day and the host's state differ.
  * Only the within-window, interleaved contrasts above are evidence.
* **Headed only.** Earlier lanes found V2 rare in chrome-headless-shell (`/showcase/` 0/17). This lane did not re-test
  headless.
* **The mechanism stays an inference.** Possible candidates are the iframe's own document lifetime across a top-level
  reload (two documents' teardown in one renderer) and extra boot work in the frame. The v2mit probe showed that worker
  `close` events come 100+ ms before the new page's first worker, so the overlap is not visible at that level.

## Read-only trees: the check reports CHANGED, from a write outside this lane

* **Stamp and check.** The stamp was taken first: `scripts/assert-untouched.sh stamp closure` rc=0, 06:44:59Z
  (`$W/logs/v2embed-untouched-stamp.log`). The closing `check closure` gave rc=1, **`VERDICT: CHANGED`**
  (`$W/logs/v2embed-untouched-check.log`).
* **What changed is in QED64's tree only.** Kernel trees, lean4game and widgets-v4.34 are OK.
  * HEAD is unchanged (`3b42714`).
  * There is one new untracked file, `tests/adversarial/boot-card.mjs`. Its header reads "Boot card (S1, 2026-10-03;
    HARDENING #54)", i.e. QED64's own hardening work.
  * 67 paths under the git-ignored `dist/` and `frontend/node_modules/.vite-temp` are new: a vite build.
  * `.git` directory mtime churn.
* **All of it is dated 09:13:23–09:13:40Z.** That is after this lane's last storm (09:11:52Z), its server stop
  (09:12:34Z) and its last log write before the check (`stat` of the logs). No command of this lane ran in or against
  that tree:
  * the storms were served from `release/5ac5d00` through `serve.mjs`;
  * the only reads were of the `release/` bundle;
  * no process of this lane was running at 09:13Z.
* **Inference: another session working on QED64 made these writes.** This lane neither reverted nor touched them (rule 1).
  The owner should know that QED64's working tree moved during this window.

## Deletable (nothing was deleted)

* `$W/v2embed/gallery-embed/`: an APFS clone of `gallery/` plus `embed-test.html`, about 0.6 MB. This is the evidence of
  what was served; keep it if the repro is to be handed upstream.
* `out/ux/v2-embed/tests/`: 6.4 MB of console records of the storm sessions.
* Keep `explore/` (2.0 MB) and the tables.
