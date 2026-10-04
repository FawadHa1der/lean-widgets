# L9 in desktop Chrome: reload storm on pins A, B and C

Lane `l9-desktop`, 2026-10-02 (05:34–08:33 UTC). The questions were:

1. Does L9 (QED64 9fdf9b8 crashes the renderer on a reload or a second runtime boot) also happen in full desktop Chrome,
   or only in Playwright's chrome-headless-shell?
2. Is pin C (QED64 5ac5d00: runtime 4b025db7 plus the new #52 worker) free of it in desktop Chrome too?

## Answers

**(1) Yes, L9 also happens in full desktop Chrome, not only in chrome-headless-shell.** On pin B, **headed** Chrome for
Testing 151.0.7922.34 (a real window on the macOS desktop) crashed in 3/8 (Bh2, Bh3, b5) runs. One of them, **Bh3**, is the
classic L9 exactly as the headless shell shows it: the renderer died 2.13 s after the **first** reload of a page that
had just become ready, with `V8 javascript OOM (Scavenger: semi-space copy)` from a ~1 s old, ~49 MB isolate. That is
the same line, timing and GC trace as the headless-shell control on the same server (B headless-shell 4/11 (Bs1, Bs2, o4, o5)). The
other two (b5, Bh2) are the second variant described below. The same Chrome build in **new headless** mode did not
crash on pin B (0/8). So a user who reloads a ready pin-B tab in desktop Chrome can lose the tab.

**(2) No, pin C is not free of it in desktop Chrome.** Headed, pin C crashed in **4/19 (c3, c4, c5, c9)** runs, all with the
second variant (V2): ~2.0–2.3 s after reload 2, 3 or 4, `V8 javascript OOM (MarkCompactCollector: young object
promotion failed)` from brand-new 15.8 MB isolates. This happens although pin C has **no parked threads**: QED64's pool
at ready is `{unused 13–14, running 10–11, parked -1}`, against B's `{unused 4–6, running 18–20, parked 8}`. Pin C
never showed the classic L9 (V1): 0 crashes after reload 0, and 0 crashes in the two headless modes (headless-shell
0/6, new headless 0/6). That matches the QED64 owner's "4b025db7: 0/5", measured headless. So kernel
0035's parked threads are what V1 needs, and pin C fixes V1. But pin C passes our reload-storm gate (0 crashes in ≥5
runs) **only in the headless browsers**, not in headed desktop Chrome.

**V2 is not pin-specific and came in one time window.** Pin A (the fallback: QED64 1859b83, the same runtime 4b025db7,
the OLD worker) also crashed headed: 1/5 (g2), V2. All 7 V2 crashes (A, B and C) fell between 05:51 and 06:40
UTC. In that window (run starts 05:51:23–06:39:48), headed runs crashed in 7 of 19, while the
new-headless runs started in it did not crash (0 of 5: d3, a4, a5, Bn1, Cn1). Outside it, no headed run crashed with V2: 0 of 5 before it, and 0 of
8 after it (Ch3–Ch6, c11–c13 with the same tool as the crashing c-runs, and Bh3, whose crash was V1). The renderer RSS at ready was ~9 GiB
(8.95–9.34) in every crashing run that recorded it, and in most non-crashing runs since 05:46. We could not find what differed in that window (same
page, release, browser and tool; 13–25 GiB reclaimable at every launch). So V2's **rate** depends on something on
the host or in Chrome we do not control. Its **existence** is established on all three pins.

### Crash tallies (one row per arm; all runs, all tools)

| pin | browser | storm-desktop.mjs (seq 1–4, 7) | reload-storm.mjs unmodified (seq 3) | storm-desktop2.mjs (seq 5–6) | **all** | crashed runs |
|---|---|---|---|---|---|---|
| B | headless-shell | 0/3 | 2/5 | 2/3 | **4/11** | Bs1, Bs2, o4, o5 |
| B | new headless | 0/5 | – | 0/3 | **0/8** | – |
| B | HEADED | 1/5 | – | 2/3 | **3/8** | Bh2, Bh3, b5 |
| C | headless-shell | 0/3 | 0/3 | – | **0/6** | – |
| C | new headless | 0/3 | – | 0/3 | **0/6** | – |
| C | HEADED | 4/13 | – | 0/6 | **4/19** | c3, c4, c5, c9 |
| A | HEADED | 1/5 | – | – | **1/5** | g2 |

The rates are small samples. The point is presence or absence: a crash is a fact, and a 0/n is an upper bound, not a
proof of safety. V1 = the classic L9 (after reload 0, `Scavenger: semi-space copy`); V2 = after a later reload,
`MarkCompactCollector: young object promotion failed` (see "Crash fingerprint").

## What ran

* **Pins, each served by its own `serve.mjs` copy from an APFS-clone scratch tree** under
  `/Users/fawadhaider/code/qed64-showcase-work/l9-desktop/` (`cp -c`, no hard links: 0 files with link count > 1).
  The only edit in each copy is the `BID` line of `scripts/serve.mjs`. Nothing under the QED64 checkout or the main
  tree was written.
  * B = `:5193`, `new/release/wasm64-2c18773ecfba45bb` (QED64 9fdf9b8), overlay `widgets8` with runtime
    `wasm64-2c18773ecfba45bb` (`widgets.62e1f451…`).
  * C = `:5195`, `pinC/release/wasm64-4b025db7729c5f89`, cloned by `clone-pinC.mjs` from the QED64 checkout at HEAD
    5ac5d00 (clean tree; runtime-manifest, profiles and snapshots all `wasm64-4b025db7729c5f89`; dist rebuilt
    01:35:30). Overlay `widgets8` from the old-pin bake (runtime `wasm64-4b025db7729c5f89`, `widgets.0880fd91…`,
    sha256 checked against its index).
  * A = `:5194`, `old/release/wasm64-4b025db7729c5f89` (QED64 1859b83), the same overlay as C.
  * Identity checks (sha256 over every dist/ and public/ file, 145 files each): every scratch release is byte-identical
    to the main tree's `release/1859b83`, `release/5ac5d00` and `release/9fdf9b8`
    (`df774e03…`, `59b8ee72…`, `e754db72…`). C's `dist/workers/lean.worker.js` equals B's (`d12de571…`, the #52
    worker), and A's differs (`52958f9a…`). C's `runtime-manifest.json` equals A's (`c17285fd…`), and B's differs
    (`968e0eac…`). So C is exactly "A's runtime + B's worker".
* **Browsers** (Playwright 1.62.1, all under `~/Library/Caches/ms-playwright/`, all version 151.0.7922.34):
  chrome-headless-shell (`chromium_headless_shell-1234`, the UX suite's browser; renderer `--headless=old`); Chrome
  for Testing (`chromium-1234/…/Google Chrome for Testing.app`) as channel `chromium` = **new headless**
  (`--headless`); and the same app **headed** (no `--headless`, a real window).
* **Tools** (all derived from `tests/ux/tools/reload-storm.mjs`: fresh profile, boot `/?snapshots=snapshots/widgets8`
  to `qed64.status().phase === 'ready'`, then 5 reloads at 0/3/6/9/12 s with `waitUntil: 'commit'`, then up to 120 s
  for ready again; a crash is Playwright's `page.on('crash')`):
  * `storm-desktop.mjs` (seq. 1–4 and 7): adds `--channel` / `--headed` and samples renderer RSS **in-process** (sync `ps`
    every 250 ms, plus a `ps` right after ready).
  * `tests/ux/tools/reload-storm.mjs` **unmodified** (seq. 3, tags o*, p*): headless-shell only.
  * `storm-desktop2.mjs` (seq. 5–6, tags Bs/Bn/Bh/Ch/Cn): **the unmodified tool's hot path** (diff: only timestamp fields)
    plus `--channel` / `--headed`. RSS comes from a **separate** perl sampler process (`rss-sampler.pl`, `ps` every
    250 ms) started inside the lock window. It exists because in headless-shell the in-process sampler gave h 0/3,
    while the unmodified tool crashed 2/5. The likely reason is that the `ps` call between "ready" and reload 0 delays
    that reload, and the classic headless-shell crash comes 1.8–2.1 s after **reload 0**.
* **Host discipline:** every run went through `scripts/with-browser-lock.sh` (via `run-one.sh`, `run-orig.sh`,
  `run-two.sh`), with `DEBUG=pw:browser` so the browser's stderr (the V8 OOM line) is in each run's log. Runs were
  interleaved across arms (sequence scripts in the scratch dir). Lock waits behind other sessions (`qed64-l9-*`,
  `qed64-0035b-*`, `multipin-ux`) are contention, not results. Every launch passed the cooldown (13.2–24.9 GiB
  reclaimable, no other headless Chrome).
* An earlier start of this lane (01:28–01:36 local) produced a1 and b1 (included). Its a2 was stopped by that
  instance's teardown before it finished (`<will force kill>`, no SUMMARY, no JSON; the log is kept as
  `l9-desktop/interrupted-a2-0135.log`). It is excluded.

## Crash fingerprint: two variants, both a V8 OOM in a small isolate

Every crash is the renderer dying 1.83–2.27 s after a reload (`page.on('crash')` time minus that reload's time). In
each one, the browser's stderr has `[renderer pid] … v8_initializer.cc:969] V8 javascript OOM (…)`, raised by 1 to 5
isolates at once. Each run's log has the full line and the GC trace V8 prints with it:

| tag | pin | browser | reload | ms after it | variant | browser stderr | GC trace printed with the OOM (age of the isolate, heap MB) |
|---|---|---|---|---|---|---|---|
| c3 | C | HEADED | 4 | 2081 | V2 | 1x MarkCompactCollector: young object promotion failed | 343 ms old, Scavenge 15.8 (16.5) MB |
| c4 | C | HEADED | 3 | 2072 | V2 | 5x MarkCompactCollector: young object promotion failed | 345 ms old, Scavenge 15.8 (16.3) MB |
| b5 | B | HEADED | 4 | 1979 | V2 | 1x MarkCompactCollector: young object promotion failed | 365 ms old, Scavenge 15.8 (16.3) MB |
| c5 | C | HEADED | 2 | 2031 | V2 | 1x MarkCompactCollector: young object promotion failed | 308 ms old, Scavenge 15.8 (16.5) MB |
| o4 | B | headless-shell | 0 | ~2173 | V1 | 1x Scavenger: semi-space copy | 1269 ms old, Scavenge (during sweeping) 53.2 (54.8) MB |
| o5 | B | headless-shell | 0 | ~2058 | V1 | 1x Scavenger: semi-space copy | 1074 ms old, Incremental Mark-Compact 48.7 (50.7) MB |
| c9 | C | HEADED | 3 | 2269 | V2 | 1x MarkCompactCollector: young object promotion failed | 440 ms old, Scavenge 15.8 (16.3) MB |
| g2 | A | HEADED | 3 | 2103 | V2 | 1x MarkCompactCollector: young object promotion failed | 437 ms old, Scavenge 15.8 (16.3) MB |
| Bs1 | B | headless-shell | 0 | 1829 | V1 | 1x Scavenger: semi-space copy | 1102 ms old, Scavenge (during sweeping) 53.2 (54.8) MB |
| Bh2 | B | HEADED | 2 | 2166 | V2 | 1x MarkCompactCollector: young object promotion failed | 482 ms old, Scavenge 15.8 (16.3) MB |
| Bs2 | B | headless-shell | 0 | 1963 | V1 | 1x Scavenger: semi-space copy | 1238 ms old, Scavenge (during sweeping) 53.2 (54.8) MB |
| Bh3 | B | HEADED | 0 | 2132 | V1 | 1x Scavenger: semi-space copy | 1049 ms old, Incremental Mark-Compact 48.7 (50.6) MB |

* **V1, the classic L9** (`Scavenger: semi-space copy`): after **reload 0** of a page that has just become ready, at
  15.3–15.9 s into the run. The failing isolate is 1.05–1.27 s old with a 48.7–53.2 MB heap. This is exactly the
  `docs/UPSTREAM-REPORT-QED64.md` L9 A/B signature. It happened on **pin B only**: in chrome-headless-shell and also
  in **headed** desktop Chrome (Bh3). It only shows with the unmodified tool's hot path (o*, Bs*, Bh*).
  `storm-desktop.mjs` puts a `ps` call between "ready" and reload 0, and no run of that tool crashed at reload 0.
* **V2** (`MarkCompactCollector: young object promotion failed`): after reload 2, 3 or 4, so on the third to fifth
  boot. The new page's workers are already up at that point (c3: `alive 26, created 158` in the last sample before
  the crash). The failing isolates are **brand new: 0.29–0.48 s old, with 15.8 MB heaps**
  (`Scavenge 15.8 (16.3) -> 15.3 (16.2) MB … allocation failure`). It happened only in **headed** desktop Chrome, on
  **all three pins** (A g2; B b5, Bh2; C c3, c4, c5, c9).
* In both variants the dying isolate is small. It cannot get memory for its young generation even though its heap is
  tiny. That points to the renderer-wide V8 reservation (the shared pointer-compression cage) being exhausted, not to
  a large heap. It fits the mechanism the QED64 owner gave for L9: the old page's ~25 workers are still in the cage while
  the new page's workers start. Kernel 0035's parked threads keep more of them alive (V1 needs them: B only). Headed
  Chrome also reaches the limit without parked threads (V2 on A and C).
* **Renderer RSS** (largest `--type=renderer` process, `ps` RSS): 10,922–11,933 MiB in the last sample before each crash. But
  non-crashing runs peak at 7,726–12,141 MiB too, so RSS does not tell crashing from non-crashing runs. The host had
  13.2–24.9 GiB reclaimable at every launch (`browser-lock: cooldown ok` lines). The V8 OOM
  points to a limit inside the renderer, not to host memory pressure.
* **macOS crash reports** (`~/Library/Logs/DiagnosticReports`, compared by name AND by mtime):
  * Chrome for Testing (headed and new headless): **no report was created or modified** for any of its crashes.
  * chrome-headless-shell: Bs1 created **`chrome-headless-shell-2026-10-02-023626.ips`**: pid 74426 = the renderer of
    that run (browser pid 74421), `EXC_BREAKPOINT`/SIGTRAP, 73 threads, 45 `DedicatedWorker`. For o4 and Bs2, ReportCrash
    wrote no new file. It only updated the mtime of an older report of the same binary
    (o4: `…-2026-10-02-012855.ips`, mtime 02:08 local, content pid 99172 from 01:28; Bs2: `…-2026-10-01-184650.ips`,
    mtime 02:41, content pid 72606 from Oct 1; Bs1 also touched `…-012855.ips` at 02:36). For the desktop crashes of
    sequences 1–4 (01:50–02:33 local) no file in the folder has an mtime in that span. `run-two.sh` checks names and
    mtimes itself and recorded `new: none, modified: none` for Bh2 and Bh3 (`diag-<tag>.txt`). Counting `.ips` files therefore undercounts crashes. The page `crash` event plus the stderr OOM line are the
    reliable signals.

## What this means for the pin decision

* **C removes what B added.** C has no V1, the classic L9, in any mode (B has it in headless-shell and in headed
  desktop Chrome). B stays staged for evidence only.
* **The gate for C** ("our reload storm 0 crashes in ≥5 runs") is **met in the UX suite's browser** (chrome-headless-shell
  0/6) and in new headless (0/6). It is **not met in headed desktop Chrome** (4/19 (c3, c4, c5, c9), all V2),
  which is what visitors use.
* **Falling back to A does not avoid V2:** A crashed headed in the same window (g2, V2). In the headless shell, A
  behaved like C (A 0/5 in `out/ux/repin-ab`, old1–old5; C 0/6 here). Measured by this storm, A is no safer
  than C in the browsers where both were run (headless-shell, headed; A was not run in new headless). C additionally has QED64's own L7 healing, which A lacks.
* **Worth telling the QED64 owner** (new evidence beyond the parked-thread cap): in headed Chrome 151, runtime 4b025db7
  also crashes 2 s after a reload, with both the old worker (A) and the new one (C). It is the same OOM in a
  fresh, tiny isolate, i.e. the same cage exhaustion. A parked-cap of 0 (the planned final fix) should bring B down to
  C's level, which removes V1. On this evidence it will not remove V2. What would remove V2 is fewer live isolates
  across a reload: for example, tearing the pthreads/workers down on `pagehide` so they are gone before the new page
  boots, or fewer pthreads per page.
* Caveats. (i) Small samples. (ii) V2 came only in one 50-minute window (05:51–06:40 UTC), on all three pins, and not
  in the 13 headed runs before or after it. Its rate depends on something outside the page (host or Chrome state), so
  a later quiet hour can show 0/n for any pin. (iii) The storm is adversarial (a reload every 3 s). But V1 needs only
  one reload of a just-ready tab, on pin B, in headed Chrome too (Bh3).

## Per-run tables

### Sequences 1–4 and 7: `storm-desktop.mjs` (a/b/c/d/e/g/h; c11–c13 = sequence 7) and unmodified `reload-storm.mjs` (o/p)

Tags: h = B headless-shell, a = B new headless, b = B headed, c = C headed, d = C new headless, e = C headless-shell,
g = A headed, o = B headless-shell (unmodified tool), p = C headless-shell (unmodified tool). In the unmodified tool's
rows, "crash time" is approximate (`~`: its reload times are relative to the storm start), and it records no RSS.

| tag | pin | browser | version | headless flag | start (UTC) | first ready ms | pool at ready | result | crash time | largest renderer MiB, last live sample before crash | peak renderer MiB | peak live workers | workers created/closed | ready after storm ms | browser stderr OOM line | new DiagnosticReports | error |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| a1 | B 9fdf9b8/2c18773e | Chrome for Testing, new headless | 151.0.7922.34 | --headless | 05:34:07 | 20511 | {"unused": 6, "running": 18, "parked": 8} | no crash | - | - | 9379 | 27 | 158/132 | 8488 | - | none |  |
| b1 | B 9fdf9b8/2c18773e | Chrome for Testing, HEADED | 151.0.7922.34 | None | 05:35:12 | 14675 | {"unused": 6, "running": 18, "parked": 8} | no crash | - | - | 9510 | 27 | 158/132 | 7178 | - | none |  |
| h1 | B 9fdf9b8/2c18773e | chrome-headless-shell | 151.0.7922.34 | --headless | 05:40:02 | 15619 | {"unused": 6, "running": 18, "parked": 8} | no crash | - | - | 8249 | 27 | 158/132 | 8064 | - | none |  |
| c1 | C 5ac5d00/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 05:40:46 | 14930 | {"unused": 13, "running": 11, "parked": -1} | no crash | - | - | 7762 | 27 | 158/132 | 8926 | - | none |  |
| d1 | C 5ac5d00/4b025db7 | Chrome for Testing, new headless | 151.0.7922.34 | --headless | 05:41:30 | 16866 | {"unused": 14, "running": 10, "parked": -1} | no crash | - | - | 8165 | 27 | 158/132 | 8498 | - | none |  |
| e1 | C 5ac5d00/4b025db7 | chrome-headless-shell | 151.0.7922.34 | --headless | 05:42:16 | 14022 | {"unused": 14, "running": 10, "parked": -1} | no crash | - | - | 8029 | 27 | 158/132 | 7656 | - | none |  |
| h2 | B 9fdf9b8/2c18773e | chrome-headless-shell | 151.0.7922.34 | --headless | 05:42:58 | 13907 | {"unused": 6, "running": 18, "parked": 8} | no crash | - | - | 8314 | 27 | 158/132 | 7395 | - | none |  |
| a2 | B 9fdf9b8/2c18773e | Chrome for Testing, new headless | 151.0.7922.34 | --headless | 05:43:39 | 14723 | {"unused": 5, "running": 19, "parked": 8} | no crash | - | - | 8520 | 27 | 158/132 | 7124 | - | none |  |
| b2 | B 9fdf9b8/2c18773e | Chrome for Testing, HEADED | 151.0.7922.34 | None | 05:44:22 | 14221 | {"unused": 6, "running": 18, "parked": 8} | no crash | - | - | 8069 | 27 | 158/132 | 7471 | - | none |  |
| c2 | C 5ac5d00/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 05:45:06 | 14171 | {"unused": 14, "running": 10, "parked": -1} | no crash | - | - | 7854 | 27 | 158/132 | 7566 | - | none |  |
| d2 | C 5ac5d00/4b025db7 | Chrome for Testing, new headless | 151.0.7922.34 | --headless | 05:45:48 | 17857 | {"unused": 14, "running": 10, "parked": -1} | no crash | - | - | 7726 | 27 | 158/132 | 8524 | - | none |  |
| e2 | C 5ac5d00/4b025db7 | chrome-headless-shell | 151.0.7922.34 | --headless | 05:46:35 | 13741 | {"unused": 14, "running": 10, "parked": -1} | no crash | - | - | 10327 | 27 | 158/132 | 6486 | - | none |  |
| h3 | B 9fdf9b8/2c18773e | chrome-headless-shell | 151.0.7922.34 | --headless | 05:47:45 | 13223 | {"unused": 6, "running": 18, "parked": 8} | no crash | - | - | 10463 | 27 | 158/132 | 6717 | - | none |  |
| a3 | B 9fdf9b8/2c18773e | Chrome for Testing, new headless | 151.0.7922.34 | --headless | 05:48:57 | 13872 | {"unused": 5, "running": 19, "parked": 8} | no crash | - | - | 10264 | 27 | 158/132 | 7115 | - | none |  |
| b3 | B 9fdf9b8/2c18773e | Chrome for Testing, HEADED | 151.0.7922.34 | None | 05:50:11 | 14275 | {"unused": 6, "running": 18, "parked": 8} | no crash | - | - | 9533 | 27 | 158/132 | 7220 | - | none |  |
| c3 | C 5ac5d00/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 05:51:23 | 13577 | {"unused": 14, "running": 10, "parked": -1} | CRASH | reload 4 +2081 ms | 11933 (t=27614) | 11933 | 27 | 158/158 | None | V8 javascript OOM (MarkCompactCollector: young object promotion failed). | none |  |
| d3 | C 5ac5d00/4b025db7 | Chrome for Testing, new headless | 151.0.7922.34 | --headless | 05:52:34 | 13869 | {"unused": 14, "running": 10, "parked": -1} | no crash | - | - | 11938 | 27 | 158/132 | 6356 | - | none |  |
| e3 | C 5ac5d00/4b025db7 | chrome-headless-shell | 151.0.7922.34 | --headless | 05:53:45 | 13569 | {"unused": 13, "running": 11, "parked": -1} | no crash | - | - | 11318 | 27 | 158/132 | 6717 | - | none |  |
| a4 | B 9fdf9b8/2c18773e | Chrome for Testing, new headless | 151.0.7922.34 | --headless | 05:54:25 | 14377 | {"unused": 6, "running": 18, "parked": 8} | no crash | - | - | 9418 | 27 | 158/132 | 7020 | - | none |  |
| b4 | B 9fdf9b8/2c18773e | Chrome for Testing, HEADED | 151.0.7922.34 | None | 05:55:08 | 13851 | {"unused": 5, "running": 19, "parked": 8} | no crash | - | - | 10841 | 27 | 158/132 | 6492 | - | none |  |
| c4 | C 5ac5d00/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 05:55:48 | 13508 | {"unused": 13, "running": 11, "parked": -1} | CRASH | reload 3 +2072 ms | 11642 (t=24505) | 11642 | 27 | 132/132 | None | V8 javascript OOM (MarkCompactCollector: young object promotion failed). | none |  |
| a5 | B 9fdf9b8/2c18773e | Chrome for Testing, new headless | 151.0.7922.34 | --headless | 05:56:21 | 13752 | {"unused": 4, "running": 20, "parked": 8} | no crash | - | - | 10858 | 27 | 158/132 | 6749 | - | none |  |
| b5 | B 9fdf9b8/2c18773e | Chrome for Testing, HEADED | 151.0.7922.34 | None | 05:57:02 | 13578 | {"unused": 4, "running": 20, "parked": 8} | CRASH | reload 4 +1979 ms | 11454 (t=27655) | 11454 | 27 | 158/158 | None | V8 javascript OOM (MarkCompactCollector: young object promotion failed). | none |  |
| c5 | C 5ac5d00/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 05:57:38 | 13477 | {"unused": 14, "running": 10, "parked": -1} | CRASH | reload 2 +2031 ms | 11801 (t=21590) | 11801 | 27 | 106/106 | None | V8 javascript OOM (MarkCompactCollector: young object promotion failed). | none |  |
| o1 | B 9fdf9b8/2c18773e | chrome-headless-shell (unmodified reload-storm.mjs) | None | None | 05:58:18 | 13590 | {"unused": 4, "running": 20, "parked": 8} | no crash | - | - | None | 27 | 158/132 | 6774 | - | none |  |
| c6 | C 5ac5d00/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 05:58:56 | 13801 | {"unused": 14, "running": 10, "parked": -1} | no crash | - | - | 10993 | 27 | 158/132 | 6601 | - | none |  |
| o2 | B 9fdf9b8/2c18773e | chrome-headless-shell (unmodified reload-storm.mjs) | None | None | 06:02:54 | 14622 | {"unused": 6, "running": 18, "parked": 8} | no crash | - | - | None | 27 | 158/132 | 7164 | - | none |  |
| p1 | C 5ac5d00/4b025db7 | chrome-headless-shell (unmodified reload-storm.mjs) | None | None | 06:04:10 | 13596 | {"unused": 13, "running": 11, "parked": -1} | no crash | - | - | None | 27 | 158/132 | 7232 | - | none |  |
| o3 | B 9fdf9b8/2c18773e | chrome-headless-shell (unmodified reload-storm.mjs) | None | None | 06:05:20 | 13434 | {"unused": 5, "running": 19, "parked": 8} | no crash | - | - | None | 27 | 158/132 | 6533 | - | none |  |
| c7 | C 5ac5d00/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 06:06:58 | 14638 | {"unused": 13, "running": 11, "parked": -1} | no crash | - | - | 9819 | 27 | 158/132 | 6770 | - | none |  |
| o4 | B 9fdf9b8/2c18773e | chrome-headless-shell (unmodified reload-storm.mjs) | None | None | 06:07:41 | 13294 | {"unused": 6, "running": 18, "parked": 8} | CRASH | reload 0 +~2173 ms | - | None | 27 | 54/54 | None | V8 javascript OOM (Scavenger: semi-space copy). | none |  |
| p2 | C 5ac5d00/4b025db7 | chrome-headless-shell (unmodified reload-storm.mjs) | None | None | 06:08:03 | 13559 | {"unused": 14, "running": 10, "parked": -1} | no crash | - | - | None | 27 | 158/132 | 6767 | - | none |  |
| o5 | B 9fdf9b8/2c18773e | chrome-headless-shell (unmodified reload-storm.mjs) | None | None | 06:29:53 | 13291 | {"unused": 4, "running": 20, "parked": 8} | CRASH | reload 0 +~2058 ms | - | None | 27 | 54/54 | None | V8 javascript OOM (Scavenger: semi-space copy). | none |  |
| c8 | C 5ac5d00/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 06:30:15 | 13516 | {"unused": 13, "running": 11, "parked": -1} | no crash | - | - | 12067 | 27 | 158/132 | 6310 | - | none |  |
| p3 | C 5ac5d00/4b025db7 | chrome-headless-shell (unmodified reload-storm.mjs) | None | None | 06:30:55 | 13413 | {"unused": 14, "running": 10, "parked": -1} | no crash | - | - | None | 27 | 158/132 | 6335 | - | none |  |
| g1 | A 1859b83/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 06:31:37 | 13433 | {"unused": 14, "running": 10} | no crash | - | - | 9717 | 27 | 158/132 | 6829 | - | none |  |
| c9 | C 5ac5d00/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 06:32:17 | 13872 | {"unused": 13, "running": 11, "parked": -1} | CRASH | reload 3 +2269 ms | 10992 (t=25175) | 10992 | 27 | 132/132 | None | V8 javascript OOM (MarkCompactCollector: young object promotion failed). | none |  |
| g2 | A 1859b83/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 06:32:51 | 13732 | {"unused": 13, "running": 11} | CRASH | reload 3 +2103 ms | 11888 (t=24783) | 11888 | 27 | 132/132 | None | V8 javascript OOM (MarkCompactCollector: young object promotion failed). | none |  |
| g3 | A 1859b83/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 06:33:25 | 13824 | {"unused": 13, "running": 11} | no crash | - | - | 11892 | 27 | 158/132 | 6252 | - | none |  |
| c10 | C 5ac5d00/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 06:34:05 | 13581 | {"unused": 14, "running": 10, "parked": -1} | no crash | - | - | 11896 | 27 | 158/132 | 6307 | - | none |  |
| g4 | A 1859b83/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 06:34:45 | 13530 | {"unused": 14, "running": 10} | no crash | - | - | 11834 | 27 | 158/132 | 6204 | - | none |  |
| g5 | A 1859b83/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 06:35:25 | 13550 | {"unused": 14, "running": 10} | no crash | - | - | 12141 | 27 | 158/132 | 6188 | - | none |  |
| c11 | C 5ac5d00/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 08:30:38 | 13119 | {"unused": 14, "running": 10, "parked": -1} | no crash | - | - | 11615 | 27 | 158/132 | 6294 | - | none |  |
| c12 | C 5ac5d00/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 08:32:27 | 13458 | {"unused": 14, "running": 10, "parked": -1} | no crash | - | - | 11927 | 27 | 158/132 | 6183 | - | none |  |
| c13 | C 5ac5d00/4b025db7 | Chrome for Testing, HEADED | 151.0.7922.34 | None | 08:33:08 | 13368 | {"unused": 14, "running": 10, "parked": -1} | no crash | - | - | 11895 | 27 | 158/132 | 6368 | - | none |  |

### Sequences 5–6: `storm-desktop2.mjs` (unmodified hot path; RSS from a separate sampler process)

Sequence 5 was planned as 5 rounds × 5 arms. From 07:11 UTC another lane (`multipin-ux`, full UX suites) took the
lock again after each of our runs, so each run waited about 20 min. We stopped sequence 5 while Bh4 was still
waiting (no browser launched; Bh4–Bs5 never ran). Sequence 6 then ran only the arm that matters most for question
2: pin C headed (Ch4+).

| tag | pin | browser | start (UTC) | first ready ms | pool at ready | result | crash time (ms after the reload; t from page start) | largest renderer RSS, last sample before the crash | peak renderer RSS | workers created/closed | ready after storm ms | browser stderr V8 OOM | DiagnosticReports (new / modified during the run) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Bs1 | B | chrome-headless-shell | 06:36:07 | 13433 | {'unused': 5, 'running': 19, 'parked': 8} | CRASH | reload 0 +1829 ms (t=15519) | 10922 MiB (90 ms before) | 10922 MiB | 54/54 | None | 1x V8 javascript OOM (Scavenger: semi-space copy) | new: chrome-headless-shell-2026-10-02-023626.ips; modified: chrome-headless-shell-2026-10-02-023626.ips; chrome-headless-shell-2026-10-02-012855.ips |
| Bn1 | B | CfT new headless | 06:36:30 | 13842 | {'unused': 6, 'running': 18, 'parked': 8} | no crash | - | - | 10294 MiB | 158/132 | 6569 | - | new: none; modified: none |
| Bh1 | B | CfT HEADED | 06:37:09 | 13525 | {'unused': 6, 'running': 18, 'parked': 8} | no crash | - | - | 11766 MiB | 158/132 | 7345 | - | new: none; modified: none |
| Ch1 | C | CfT HEADED | 06:37:48 | 13902 | {'unused': 14, 'running': 10, 'parked': -1} | no crash | - | - | 10949 MiB | 158/132 | 6678 | - | new: none; modified: none |
| Cn1 | C | CfT new headless | 06:38:27 | 14802 | {'unused': 14, 'running': 10, 'parked': -1} | no crash | - | - | 8941 MiB | 158/132 | 7846 | - | new: none; modified: none |
| Ch2 | C | CfT HEADED | 06:39:09 | 14066 | {'unused': 14, 'running': 10, 'parked': -1} | no crash | - | - | 9358 MiB | 158/132 | 6567 | - | new: none; modified: none |
| Bh2 | B | CfT HEADED | 06:39:48 | 13605 | {'unused': 4, 'running': 20, 'parked': 8} | CRASH | reload 2 +2166 ms (t=22020) | 11336 MiB (211 ms before) | 11493 MiB | 106/106 | None | 1x V8 javascript OOM (MarkCompactCollector: young object promotion failed) | new: none; modified: none |
| Cn2 | C | CfT new headless | 06:40:17 | 13631 | {'unused': 14, 'running': 10, 'parked': -1} | no crash | - | - | 11127 MiB | 158/132 | 6815 | - | new: none; modified: none |
| Bs2 | B | chrome-headless-shell | 06:40:56 | 13411 | {'unused': 4, 'running': 20, 'parked': 8} | CRASH | reload 0 +1963 ms (t=15632) | 10934 MiB (72 ms before) | 10934 MiB | 54/54 | None | 1x V8 javascript OOM (Scavenger: semi-space copy) | new: none; modified: chrome-headless-shell-2026-10-01-184650.ips |
| Bn2 | B | CfT new headless | 06:41:18 | 13850 | {'unused': 5, 'running': 19, 'parked': 8} | no crash | - | - | 10702 MiB | 158/132 | 6546 | - | new: none; modified: none |
| Bn3 | B | CfT new headless | 06:41:58 | 13807 | {'unused': 6, 'running': 18, 'parked': 8} | no crash | - | - | 10577 MiB | 158/132 | 6898 | - | new: none; modified: none |
| Cn3 | C | CfT new headless | 06:42:37 | 14402 | {'unused': 13, 'running': 11, 'parked': -1} | no crash | - | - | 11798 MiB | 158/132 | 6711 | - | new: none; modified: none |
| Bs3 | B | chrome-headless-shell | 06:43:17 | 13340 | {'unused': 5, 'running': 19, 'parked': 8} | no crash | - | - | 11983 MiB | 158/132 | 6264 | - | new: none; modified: none |
| Ch3 | C | CfT HEADED | 07:33:37 | 13428 | {'unused': 14, 'running': 10, 'parked': -1} | no crash | - | - | 11954 MiB | 158/132 | 6309 | - | new: none; modified: none |
| Bh3 | B | CfT HEADED | 07:55:01 | 13480 | {'unused': 5, 'running': 19, 'parked': 8} | CRASH | reload 0 +2132 ms (t=15891) | 11370 MiB (338 ms before) | 11370 MiB | 54/54 | None | 1x V8 javascript OOM (Scavenger: semi-space copy) | new: none; modified: none |
| Ch4 | C | CfT HEADED | 08:17:28 | 13383 | {'unused': 14, 'running': 10, 'parked': -1} | no crash | - | - | 11665 MiB | 158/132 | 6340 | - | new: none; modified: none |
| Ch5 | C | CfT HEADED | 08:28:18 | 13422 | {'unused': 14, 'running': 10, 'parked': -1} | no crash | - | - | 11821 MiB | 158/132 | 6287 | - | new: none; modified: none |
| Ch6 | C | CfT HEADED | 08:29:11 | 13372 | {'unused': 14, 'running': 10, 'parked': -1} | no crash | - | - | 11724 MiB | 158/132 | 6330 | - | new: none; modified: none |

## Files

* This report: `out/ux/l9-desktop/RESULTS.md`, generated by `l9-desktop/gen-results.py` from the run files.
* Per run: `out/ux/l9-desktop/explore/storm-<tag>.json` (seq. 1–4, with 250 ms RSS samples),
  `reload-storm-<tag>.json` (unmodified tool), `storm2-<tag>.json` + `rss2-<tag>.txt` (seq. 5–6),
  `diag-<tag>.txt` (crash reports); console streams in `out/ux/l9-desktop/tests/`.
* Logs (with the browser's stderr): `/Users/fawadhaider/code/qed64-showcase-work/logs/l9-desktop-<tag>.log`,
  sequences `l9-desktop-sequence{,2,3,4,5,6,7}.log`, servers `l9-desktop-serve-519{3,4,5}.log`.
* Scratch (`/Users/fawadhaider/code/qed64-showcase-work/l9-desktop/`): `new/`, `old/`, `pinC/` (serving trees),
  `clone-pinC.mjs`, `storm-desktop.mjs`, `storm-desktop2.mjs`, `rss-sampler.pl`, `run-one.sh`, `run-orig.sh`,
  `run-two.sh`, `sequence{,2,3,4,5,6,7}.sh`, `tabulate.py`, `tabulate2.py`, `gen-results.py`.
