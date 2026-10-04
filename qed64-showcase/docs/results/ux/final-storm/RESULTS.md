# L9 final gate: interleaved reload storms on pins A, C, D and B (2026-10-02, 14:55–16:59 UTC)

Lane `final-gate`. The question: with the time confound removed (all pins in the same window, rotated run by run), is
D `3b42714` (QED64's L9 fix candidate: runtime `wasm64-3ab1c6a9da03bc29`, kernel 0035b, parked dedicated threads off) at
least as clean as the served C `5ac5d00` under a reload storm, in the UX suite's browser and in headed desktop Chrome, on
the stock page and on the visitor's path `/showcase/`?

## Answer

| pin | interleaved rounds (5 × 4 arms, 14:55–16:59Z) | dedicated quiet round (headed, 19:12–19:24Z) | all |
|---|---|---|---|
| A `1859b83` (0034, old worker) | 0/20 | 3/6 (V2: all three `/showcase/` runs) | **3/26** V2 |
| C `5ac5d00` (0034, #52 worker; served) | 1/20 (V2, headless-shell, stock) | 1/6 (V2, `/showcase/`) | **2/26** V2 |
| D `3b42714` (0035b, parking off) | 1/20 (V2, headless-shell, stock) | 2/6 (V2, `/showcase/`) | **3/26** V2 (+1 V2 in the tool's smoke run: 4/27) |
| B `9fdf9b8` (0035, parked threads; positive control) | 3/20 (V1, after reload 0) | not run | **3/20** V1 |

* **V1 (the classic L9) only on B**: r2-B-hs-st, r3-B-hs-sc, r2-B-hd-st, 1.9–2.4 s after **reload 0**, `Scavenger:
  semi-space copy`, QED64's pool at ready `parked 7–8`. D has `parked 0` at every ready and no V1 in 27 runs, so D does
  remove V1, like C and A.
* **V2 hits A, C and D alike**, in both browsers: `MarkCompactCollector: young object promotion failed` 1.7–2.15 s after
  reload 2, 3 or 4, from 1–4 isolates 300–355 ms old with 15.8 MB heaps (the l9-desktop fingerprint). New: V2 also
  in chrome-headless-shell (r1-D-hs-st, r2-C-hs-st); before today it had been seen only headed.
* **V2 does not need a loaded host; in this lane it was more frequent on a quiet one.** The quiet round (5 consecutive
  quiet minutes before it, every run launched at 22.7–23.6 GB reclaimable with swap flat and no foreign heavy process)
  had 6 V2 crashes in 18 headed runs, all on the `/showcase/` entry (A 3/3, D 2/3, C 1/3; stock entry 0/9). The headed
  runs of the interleaved rounds, launched at 13.6–22.3 GB with other sessions' jobs between rounds, had 0 V2 in 40
  (B's one headed crash there was V1). By
  host state at launch (one sample per run): headed quiet A 3/7, C 1/7, D 2/7; headed loaded 0/9 each (inferred, not
  shown: faster boots on an idle host put more of the new page's workers into the overlap with the old page's).
* **Decision (served pin): C stays.** The rule was "D if its storms are at least as clean as C's". Over the same
  windows D has 3 V2 crashes in 26 runs against C's 2 (4/27 with the smoke run), so D is not at least as clean, although
  the difference is one crash and not significant. D passed the whole gate while it was served (two VERDICTs, a headed
  sign-off; docs/UX-RESULTS.md "Final gate"); it stays staged, and V2 is reported upstream as not fixed by 0035b.
* **Quiet-host slot.** The first polling stint (14:53–17:33Z, 319 checks, 105 outside our own rounds) found no quiet
  window: outside our rounds reclaimable memory was 10.3–22.1 GB (about 11 GB sat in the macOS compressor:
  673,681 pages at about 17:00Z) and other sessions ran chrome-headless-shell, cypress and `lake build`. The second
  stint (from 18:21Z) saw ≥ 20 GB as soon as our own UX runs paused; the quiet round was triggered at 19:12:39Z after a
  301 s streak (`quiet-poll.tsv`).

## What ran

* Servers (each its own `serve.mjs`, `SHOWCASE_PIN`, plus `GALLERY_DIR` = an APFS clone of `gallery/` whose `pin.json` was
  derived from that pin's lock by build-gallery's rule, self-checked byte-equal to `gallery/pin.json` for the then active
  C; `$W/final-gate/pin-gallery.mjs`): A `:5211`, B `:5212`, C `:5213`, D `:5214`; each answered `X-Showcase-Pin <id>
  <buildId>` and served its own `widgets8` overlay (index runtime == the pin's buildId).
* Tool: `tests/ux/tools/reload-storm-desktop.mjs` (new; the unchanged hot path of `reload-storm.mjs` plus `--headed` /
  `--channel` from l9-desktop's `storm-desktop2/3.mjs` and `--entry stock|showcase`). Stock = `/?snapshots=snapshots/widgets8`;
  showcase = `/showcase/`, ready = `__showcase.status().phase === 'ready'` (QED64 ready and the first example
  elaborated). Fresh profile, boot to ready, reloads at 0/3/6/9/12 s (`waitUntil: 'commit'`), then 120 s for ready
  again; a crash is the page `crash` event; `DEBUG=pw:browser` puts the browser stderr (the V8 OOM line) in
  `explore/stdout-<tag>.log`.
* Browsers: chrome-headless-shell 151.0.7922.34 (the UX suite's browser) and Chrome for Testing 151.0.7922.34 headed (a
  real window).
* Rounds (`$W/final-gate/master.sh`, `round-inner.sh`, `run-arm.sh`): 5 rounds × 16 arms (A C D B × headless-shell/headed
  × stock/showcase), each round in ONE browser-lock hold, the pin order and the arm order rotated every round, so every
  4 consecutive runs cover all 4 pins. Per run, before launch: wait up to 45 s for ≥ 20 GB reclaimable (recorded as
  `waited=`), then reclaimable GB (`vm_stat` free+inactive+speculative), swap used (`sysctl vm.swapusage`), foreign heavy
  processes (not descendants of our master: bake-snapshot, node-runner, thread-storm, *storm*/*probe* scripts,
  chrome-headless-shell or Chrome for Testing, docker builds, lv-live, cypress, lake build, lean --run) in
  `explore/host-state.tsv`; renderer RSS every 250 ms of this run's own process tree only (`rss-sampler2.pl`,
  `explore/rss-<tag>.txt`).
* Quiet poller: `explore/quiet-poll.tsv` (utc, reclaimable, swap, foreign, ownRound, quiet, streak).
* Logs: `$W/logs/final-gate-master.log` (every run's summary line), `$W/logs/final-gate-smoke.log`. Tables:
  `$W/final-gate/tabulate.py` → `out/ux/final-storm/storm-table.json` and this file's tables. `node scripts/ux-tally.mjs`
  recomputes the per-arm counts from the JSONs and logs.

## Tables (generated by tabulate.py from the run files)

| pin | browser | entry | runs | crashed | variants | crashed runs |
|---|---|---|---|---|---|---|
| A 1859b83 | headless-shell | stock | 5 | **0/5** | - | - |
| A 1859b83 | headless-shell | showcase | 5 | **0/5** | - | - |
| A 1859b83 | headed | stock | 5 | **0/5** | - | - |
| A 1859b83 | headed | showcase | 5 | **0/5** | - | - |
| C 5ac5d00 | headless-shell | stock | 5 | **1/5** | V2 1 | r2-C-hs-st |
| C 5ac5d00 | headless-shell | showcase | 5 | **0/5** | - | - |
| C 5ac5d00 | headed | stock | 5 | **0/5** | - | - |
| C 5ac5d00 | headed | showcase | 5 | **0/5** | - | - |
| D 3b42714 | headless-shell | stock | 5 | **1/5** | V2 1 | r1-D-hs-st |
| D 3b42714 | headless-shell | showcase | 5 | **0/5** | - | - |
| D 3b42714 | headed | stock | 5 | **0/5** | - | - |
| D 3b42714 | headed | showcase | 5 | **0/5** | - | - |
| B 9fdf9b8 | headless-shell | stock | 5 | **1/5** | V1 1 | r2-B-hs-st |
| B 9fdf9b8 | headless-shell | showcase | 5 | **1/5** | V1 1 | r3-B-hs-sc |
| B 9fdf9b8 | headed | stock | 5 | **1/5** | V1 1 | r2-B-hd-st |
| B 9fdf9b8 | headed | showcase | 5 | **0/5** | - | - |

By pin and browser (normal rounds, both entries):

| pin | headless-shell | headed |
|---|---|---|
| A 1859b83 | 0/10 (-) | 0/10 (-) |
| C 5ac5d00 | 1/10 (V2 1) | 0/10 (-) |
| D 3b42714 | 1/10 (V2 1) | 0/10 (-) |
| B 9fdf9b8 | 2/10 (V1 2) | 1/10 (V1 1) |

By host state at launch (all sets; quiet = reclaimable >= 20 GB, no foreign heavy process, swap not grown > 32 MB since the previous run; loaded = anything else):

| pin | browser | quiet: crashed (V2) | loaded: crashed (V2) |
|---|---|---|---|
| A 1859b83 | headless-shell | 0/1 (V2 0/1) | 0/9 (V2 0/9) |
| A 1859b83 | headed | 3/7 (V2 3/7) | 0/9 (V2 0/9) |
| C 5ac5d00 | headless-shell | 0/1 (V2 0/1) | 1/9 (V2 1/9) |
| C 5ac5d00 | headed | 1/7 (V2 1/7) | 0/9 (V2 0/9) |
| D 3b42714 | headless-shell | 1/1 (V2 1/1) | 0/9 (V2 0/9) |
| D 3b42714 | headed | 2/7 (V2 2/7) | 0/9 (V2 0/9) |
| B 9fdf9b8 | headless-shell | 0/1 (V2 0/1) | 2/9 (V2 0/9) |
| B 9fdf9b8 | headed | 0/1 (V2 0/1) | 1/9 (V2 0/9) |

The dedicated quiet round (A, C, D headed):

| pin | entry | runs | crashed | variants | runs that were quiet at launch |
|---|---|---|---|---|---|
| A 1859b83 | stock | 3 | **0/3** | - | 3/3 |
| A 1859b83 | showcase | 3 | **3/3** | V2 3 | 3/3 |
| C 5ac5d00 | stock | 3 | **0/3** | - | 3/3 |
| C 5ac5d00 | showcase | 3 | **1/3** | V2 1 | 3/3 |
| D 3b42714 | stock | 3 | **0/3** | - | 3/3 |
| D 3b42714 | showcase | 3 | **2/3** | V2 2 | 3/3 |

Per run (UTC start; reclaimable GB; swap used MB and its change since the previous run; renderer RSS MiB of this run's largest renderer at ready, in the last sample before a crash, and at peak):

| tag | utc | pin | mode | entry | recl | swap | swapDelta | foreign | quiet | result | variant | crashAt | oomLines | firstReadyMs | pool | rssReady | rssBeforeCrash | rssPeak | readyAfterMs | workers |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| r1-A-hs-st | 14:55:13 | A | headless-shell | stock | 21.7 | 1518.12 | 0.0 | - | True | no crash | - | - | 0 | 13507 | {"unused": 14, "running": 10} | 9295 | None | 12024 | 6439 | 158/132 |
| r1-C-hs-st | 14:55:54 | C | headless-shell | stock | 22.2 | 1518.12 | 0.0 | - | True | no crash | - | - | 0 | 13785 | {"unused": 14, "running": 10, "parked": -1} | 9213 | None | 11820 | 6458 | 158/132 |
| r1-D-hs-st | 14:56:35 | D | headless-shell | stock | 22.3 | 1518.12 | 0.0 | - | True | CRASH | V2 | reload 2 +1711 ms | 2 | 13504 | {"unused": 14, "running": 10, "parked": 0} | 9282 | 0 | 11712 | None | 106/106 |
| r1-B-hs-st | 14:57:07 | B | headless-shell | stock | 21.6 | 1518.12 | 0.0 | - | True | no crash | - | - | 0 | 13359 | {"unused": 5, "running": 19, "parked": 8} | 9312 | None | 11952 | 6503 | 158/132 |
| r1-A-hd-st | 14:57:48 | A | headed | stock | 22.3 | 1518.12 | 0.0 | - | True | no crash | - | - | 0 | 13493 | {"unused": 14, "running": 10} | 9401 | None | 11070 | 6709 | 158/132 |
| r1-C-hd-st | 14:58:30 | C | headed | stock | 21.3 | 1518.12 | 0.0 | - | True | no crash | - | - | 0 | 13913 | {"unused": 13, "running": 11, "parked": -1} | 9296 | None | 11454 | 6972 | 158/132 |
| r1-D-hd-st | 14:59:12 | D | headed | stock | 20.7 | 1518.12 | 0.0 | lake build(57273) | False | no crash | - | - | 0 | 14023 | {"unused": 14, "running": 10, "parked": 0} | 9469 | None | 11706 | 6769 | 158/132 |
| r1-B-hd-st | 14:59:55 | B | headed | stock | 20.9 | 1518.12 | 0.0 | - | True | no crash | - | - | 0 | 13530 | {"unused": 4, "running": 20, "parked": 8} | 9415 | None | 11165 | 6639 | 158/132 |
| r1-A-hs-sc | 15:00:37 | A | headless-shell | showcase | 19.9 | 1518.12 | 0.0 | - | False | no crash | - | - | 0 | 18945 | {"unused": 13, "running": 11} | 6311 | None | 8022 | 8168 | 158/132 |
| r1-C-hs-sc | 15:01:26 | C | headless-shell | showcase | 15.8 | 1510.12 | -8.0 | - | False | no crash | - | - | 0 | 14918 | {"unused": 11, "running": 13, "parked": -1} | 3630 | None | 9397 | 6475 | 158/132 |
| r1-D-hs-sc | 15:02:53 | D | headless-shell | showcase | 13.2 | 1510.12 | 0.0 | - | False | no crash | - | - | 0 | 14189 | {"unused": 12, "running": 12, "parked": 0} | 8995 | None | 9509 | 6533 | 158/132 |
| r1-B-hs-sc | 15:04:21 | B | headless-shell | showcase | 16.6 | 1510.12 | 0.0 | - | False | no crash | - | - | 0 | 13987 | {"unused": 5, "running": 19, "parked": 7} | 9414 | None | 9700 | 6749 | 158/132 |
| r1-A-hd-sc | 15:05:48 | A | headed | showcase | 17.3 | 1510.12 | 0.0 | - | False | no crash | - | - | 0 | 14399 | {"unused": 11, "running": 13} | 9123 | None | 9129 | 6695 | 158/132 |
| r1-C-hd-sc | 15:07:16 | C | headed | showcase | 16.0 | 1510.12 | 0.0 | - | False | no crash | - | - | 0 | 14131 | {"unused": 11, "running": 13, "parked": -1} | 9345 | None | 9763 | 6738 | 158/132 |
| r1-D-hd-sc | 15:08:44 | D | headed | showcase | 17.8 | 1510.12 | 0.0 | - | False | no crash | - | - | 0 | 13803 | {"unused": 11, "running": 13, "parked": 0} | 9522 | None | 9647 | 6488 | 158/132 |
| r1-B-hd-sc | 15:10:11 | B | headed | showcase | 17.7 | 1510.12 | 0.0 | - | False | no crash | - | - | 0 | 13839 | {"unused": 5, "running": 19, "parked": 7} | 8541 | None | 9436 | 6884 | 158/132 |
| r2-C-hd-st | 15:15:59 | C | headed | stock | 16.2 | 1510.12 | 0.0 | - | False | no crash | - | - | 0 | 14188 | {"unused": 14, "running": 10, "parked": -1} | 8772 | None | 9776 | 7238 | 158/132 |
| r2-D-hd-st | 15:16:43 | D | headed | stock | 20.1 | 1510.12 | 0.0 | - | True | no crash | - | - | 0 | 13954 | {"unused": 14, "running": 10, "parked": 0} | 9332 | None | 10484 | 6965 | 158/132 |
| r2-B-hd-st | 15:18:11 | B | headed | stock | 17.8 | 1510.12 | 0.0 | - | False | CRASH | V1 | reload 0 +2377 ms | 1 | 14041 | {"unused": 4, "running": 20, "parked": 8} | 9371 | 88 | 10957 | None | 54/54 |
| r2-A-hd-st | 15:19:22 | A | headed | stock | 16.1 | 1502.12 | -8.0 | - | False | no crash | - | - | 0 | 14161 | {"unused": 14, "running": 10} | 7837 | None | 9660 | 7139 | 158/132 |
| r2-C-hs-sc | 15:20:51 | C | headless-shell | showcase | 16.4 | 1502.12 | 0.0 | - | False | no crash | - | - | 0 | 13520 | {"unused": 12, "running": 12, "parked": -1} | 9390 | None | 9986 | 6630 | 158/132 |
| r2-D-hs-sc | 15:22:17 | D | headless-shell | showcase | 14.6 | 1502.12 | 0.0 | - | False | no crash | - | - | 0 | 15075 | {"unused": 13, "running": 11, "parked": 0} | 5257 | None | 9433 | 6772 | 158/132 |
| r2-B-hs-sc | 15:23:46 | B | headless-shell | showcase | 17.1 | 1502.12 | 0.0 | - | False | no crash | - | - | 0 | 14088 | {"unused": 3, "running": 21, "parked": 7} | 8965 | None | 9272 | 6831 | 158/132 |
| r2-A-hs-sc | 15:25:13 | A | headless-shell | showcase | 17.8 | 1502.12 | 0.0 | - | False | no crash | - | - | 0 | 13408 | {"unused": 11, "running": 13} | 9365 | None | 11584 | 6477 | 158/132 |
| r2-C-hd-sc | 15:26:39 | C | headed | showcase | 18.2 | 1502.12 | 0.0 | - | False | no crash | - | - | 0 | 13882 | {"unused": 11, "running": 13, "parked": -1} | 9383 | None | 9853 | 6671 | 158/132 |
| r2-D-hd-sc | 15:28:07 | D | headed | showcase | 17.8 | 1502.12 | 0.0 | - | False | no crash | - | - | 0 | 14078 | {"unused": 11, "running": 13, "parked": 0} | 9487 | None | 10003 | 6693 | 158/132 |
| r2-B-hd-sc | 15:29:34 | B | headed | showcase | 17.6 | 1502.12 | 0.0 | - | False | no crash | - | - | 0 | 13970 | {"unused": 5, "running": 19, "parked": 7} | 9388 | None | 10098 | 6506 | 158/132 |
| r2-A-hd-sc | 15:31:02 | A | headed | showcase | 17.6 | 1502.12 | 0.0 | - | False | no crash | - | - | 0 | 13739 | {"unused": 11, "running": 13} | 9474 | None | 9926 | 6549 | 158/132 |
| r2-C-hs-st | 15:32:29 | C | headless-shell | stock | 17.8 | 1502.12 | 0.0 | - | False | CRASH | V2 | reload 4 +1699 ms | 4 | 13444 | {"unused": 14, "running": 10, "parked": -1} | 9178 | 10732 | 10898 | None | 158/158 |
| r2-D-hs-st | 15:33:50 | D | headless-shell | stock | 17.4 | 1502.12 | 0.0 | - | False | no crash | - | - | 0 | 13345 | {"unused": 14, "running": 10, "parked": 0} | 9221 | None | 11160 | 6855 | 158/132 |
| r2-B-hs-st | 15:35:17 | B | headless-shell | stock | 16.5 | 1502.12 | 0.0 | - | False | CRASH | V1 | reload 0 +1931 ms | 1 | 13595 | {"unused": 6, "running": 18, "parked": 8} | 9254 | 0 | 10480 | None | 54/54 |
| r2-A-hs-st | 15:36:28 | A | headless-shell | stock | 16.1 | 1502.12 | 0.0 | - | False | no crash | - | - | 0 | 13481 | {"unused": 14, "running": 10} | 9450 | None | 11620 | 6818 | 158/132 |
| r3-D-hs-sc | 15:41:55 | D | headless-shell | showcase | 15.5 | 1494.12 | -8.0 | - | False | no crash | - | - | 0 | 13613 | {"unused": 11, "running": 13, "parked": 0} | 9187 | None | 10369 | 6690 | 158/132 |
| r3-B-hs-sc | 15:43:22 | B | headless-shell | showcase | 16.3 | 1494.12 | 0.0 | - | False | CRASH | V1 | reload 0 +2018 ms | 1 | 13458 | {"unused": 5, "running": 19, "parked": 7} | 9280 | 10800 | 10800 | None | 54/54 |
| r3-A-hs-sc | 15:44:32 | A | headless-shell | showcase | 16.0 | 1494.12 | 0.0 | - | False | no crash | - | - | 0 | 13317 | {"unused": 12, "running": 12} | 9350 | None | 10779 | 6891 | 158/132 |
| r3-C-hs-sc | 15:45:59 | C | headless-shell | showcase | 16.0 | 1494.12 | 0.0 | - | False | no crash | - | - | 0 | 13541 | {"unused": 11, "running": 13, "parked": -1} | 9216 | None | 10673 | 6382 | 158/132 |
| r3-D-hd-sc | 15:47:25 | D | headed | showcase | 18.0 | 1494.12 | 0.0 | - | False | no crash | - | - | 0 | 13768 | {"unused": 10, "running": 14, "parked": 0} | 8634 | None | 9234 | 6800 | 158/132 |
| r3-B-hd-sc | 15:48:53 | B | headed | showcase | 16.9 | 1494.12 | 0.0 | - | False | no crash | - | - | 0 | 13875 | {"unused": 5, "running": 19, "parked": 7} | 9359 | None | 10076 | 6593 | 158/132 |
| r3-A-hd-sc | 15:50:20 | A | headed | showcase | 16.3 | 1486.12 | -8.0 | - | False | no crash | - | - | 0 | 14344 | {"unused": 12, "running": 12} | 8014 | None | 9806 | 6535 | 158/132 |
| r3-C-hd-sc | 15:51:48 | C | headed | showcase | 16.4 | 1486.12 | 0.0 | - | False | no crash | - | - | 0 | 14454 | {"unused": 12, "running": 12, "parked": -1} | 7756 | None | 9578 | 6480 | 158/132 |
| r3-D-hs-st | 15:53:15 | D | headless-shell | stock | 16.5 | 1486.12 | 0.0 | - | False | no crash | - | - | 0 | 13373 | {"unused": 14, "running": 10, "parked": 0} | 9398 | None | 10773 | 6906 | 158/132 |
| r3-B-hs-st | 15:54:42 | B | headless-shell | stock | 14.6 | 637.81 | -848.3 | - | False | no crash | - | - | 0 | 13776 | {"unused": 6, "running": 18, "parked": 8} | 4149 | None | 8833 | 6760 | 158/132 |
| r3-A-hs-st | 15:56:09 | A | headless-shell | stock | 16.2 | 637.81 | 0.0 | - | False | no crash | - | - | 0 | 13582 | {"unused": 13, "running": 11} | 9153 | None | 9503 | 7086 | 158/132 |
| r3-C-hs-st | 15:57:37 | C | headless-shell | stock | 17.0 | 637.81 | 0.0 | - | False | no crash | - | - | 0 | 13540 | {"unused": 13, "running": 11, "parked": -1} | 9343 | None | 10924 | 6664 | 158/132 |
| r3-D-hd-st | 15:59:03 | D | headed | stock | 17.2 | 637.81 | 0.0 | - | False | no crash | - | - | 0 | 13661 | {"unused": 14, "running": 10, "parked": 0} | 9338 | None | 9338 | 6978 | 158/132 |
| r3-B-hd-st | 16:00:31 | B | headed | stock | 15.5 | 637.81 | 0.0 | - | False | no crash | - | - | 0 | 13918 | {"unused": 5, "running": 19, "parked": 8} | 7271 | None | 8288 | 7541 | 158/132 |
| r3-A-hd-st | 16:02:00 | A | headed | stock | 15.9 | 637.81 | 0.0 | - | False | no crash | - | - | 0 | 14163 | {"unused": 14, "running": 10} | 8596 | None | 9321 | 6709 | 158/132 |
| r3-C-hd-st | 16:03:28 | C | headed | stock | 15.5 | 637.81 | 0.0 | - | False | no crash | - | - | 0 | 14298 | {"unused": 14, "running": 10, "parked": -1} | 9114 | None | 9487 | 6739 | 158/132 |
| r4-B-hd-sc | 16:08:56 | B | headed | showcase | 14.5 | 629.81 | -8.0 | - | False | no crash | - | - | 0 | 14404 | {"unused": 5, "running": 19, "parked": 7} | 9226 | None | 9509 | 6795 | 158/132 |
| r4-A-hd-sc | 16:10:24 | A | headed | showcase | 17.4 | 629.81 | 0.0 | - | False | no crash | - | - | 0 | 14455 | {"unused": 11, "running": 13} | 9420 | None | 9570 | 6913 | 158/132 |
| r4-C-hd-sc | 16:11:52 | C | headed | showcase | 17.4 | 629.81 | 0.0 | - | False | no crash | - | - | 0 | 14628 | {"unused": 11, "running": 13, "parked": -1} | 9183 | None | 9542 | 6565 | 158/132 |
| r4-D-hd-sc | 16:13:20 | D | headed | showcase | 17.2 | 629.81 | 0.0 | - | False | no crash | - | - | 0 | 14741 | {"unused": 12, "running": 12, "parked": 0} | 8775 | None | 9463 | 6868 | 158/132 |
| r4-B-hs-st | 16:14:49 | B | headless-shell | stock | 16.8 | 629.81 | 0.0 | - | False | no crash | - | - | 0 | 14033 | {"unused": 6, "running": 18, "parked": 8} | 9296 | None | 9545 | 7202 | 158/132 |
| r4-A-hs-st | 16:16:17 | A | headless-shell | stock | 16.5 | 629.81 | 0.0 | - | False | no crash | - | - | 0 | 14585 | {"unused": 14, "running": 10} | 9068 | None | 9421 | 6974 | 158/132 |
| r4-C-hs-st | 16:17:45 | C | headless-shell | stock | 15.5 | 629.81 | 0.0 | - | False | no crash | - | - | 0 | 14266 | {"unused": 15, "running": 9, "parked": -1} | 6703 | None | 8993 | 7383 | 158/132 |
| r4-D-hs-st | 16:19:13 | D | headless-shell | stock | 15.8 | 629.81 | 0.0 | - | False | no crash | - | - | 0 | 14163 | {"unused": 15, "running": 9, "parked": 0} | 9088 | None | 9297 | 6893 | 158/132 |
| r4-B-hd-st | 16:20:40 | B | headed | stock | 17.0 | 629.81 | 0.0 | - | False | no crash | - | - | 0 | 14881 | {"unused": 5, "running": 19, "parked": 8} | 5559 | None | 8457 | 7322 | 158/132 |
| r4-A-hd-st | 16:22:10 | A | headed | stock | 16.5 | 629.81 | 0.0 | - | False | no crash | - | - | 0 | 14376 | {"unused": 14, "running": 10} | 7345 | None | 8564 | 6972 | 158/132 |
| r4-C-hd-st | 16:23:38 | C | headed | stock | 15.3 | 629.81 | 0.0 | - | False | no crash | - | - | 0 | 14366 | {"unused": 14, "running": 10, "parked": -1} | 7844 | None | 8514 | 7311 | 158/132 |
| r4-D-hd-st | 16:25:07 | D | headed | stock | 16.8 | 629.81 | 0.0 | - | False | no crash | - | - | 0 | 14781 | {"unused": 13, "running": 11, "parked": 0} | 6934 | None | 8387 | 7393 | 158/132 |
| r4-B-hs-sc | 16:26:36 | B | headless-shell | showcase | 14.4 | 629.81 | 0.0 | - | False | no crash | - | - | 0 | 14777 | {"unused": 3, "running": 21, "parked": 8} | 5315 | None | 9633 | 6771 | 158/132 |
| r4-A-hs-sc | 16:28:04 | A | headless-shell | showcase | 14.5 | 621.81 | -8.0 | - | False | no crash | - | - | 0 | 14477 | {"unused": 13, "running": 11} | 5217 | None | 9477 | 7164 | 158/132 |
| r4-C-hs-sc | 16:29:32 | C | headless-shell | showcase | 15.4 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 15418 | {"unused": 11, "running": 13, "parked": -1} | 5443 | None | 8790 | 7354 | 158/132 |
| r4-D-hs-sc | 16:31:01 | D | headless-shell | showcase | 11.6 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 16263 | {"unused": 13, "running": 11, "parked": 0} | 6809 | None | 7736 | 8075 | 158/132 |
| r5-A-hs-st | 16:36:32 | A | headless-shell | stock | 13.2 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 14163 | {"unused": 13, "running": 11} | 5863 | None | 9519 | 6589 | 158/132 |
| r5-C-hs-st | 16:38:00 | C | headless-shell | stock | 12.3 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 14790 | {"unused": 13, "running": 11, "parked": -1} | 3681 | None | 9329 | 6738 | 158/132 |
| r5-D-hs-st | 16:39:28 | D | headless-shell | stock | 14.4 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 13827 | {"unused": 14, "running": 10, "parked": 0} | 8822 | None | 9352 | 6694 | 158/132 |
| r5-B-hs-st | 16:40:55 | B | headless-shell | stock | 14.0 | 621.81 | 0.0 | lake build(24501) lake build(24795) | False | no crash | - | - | 0 | 14503 | {"unused": 5, "running": 19, "parked": 8} | 5288 | None | 7889 | 7409 | 158/132 |
| r5-A-hd-st | 16:42:24 | A | headed | stock | 15.6 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 14585 | {"unused": 14, "running": 10} | 6779 | None | 8592 | 7016 | 158/132 |
| r5-C-hd-st | 16:43:53 | C | headed | stock | 13.9 | 621.81 | 0.0 | lake build(27669) lake build(28672) | False | no crash | - | - | 0 | 14970 | {"unused": 14, "running": 10, "parked": -1} | 5568 | None | 9539 | 7063 | 158/132 |
| r5-D-hd-st | 16:45:22 | D | headed | stock | 13.6 | 621.81 | 0.0 | lake build(31489) lake build(31669) | False | no crash | - | - | 0 | 15471 | {"unused": 14, "running": 10, "parked": 0} | 5491 | None | 7881 | 7689 | 158/132 |
| r5-B-hd-st | 16:46:52 | B | headed | stock | 15.4 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 14182 | {"unused": 4, "running": 20, "parked": 8} | 9406 | None | 9707 | 6599 | 158/132 |
| r5-A-hs-sc | 16:48:20 | A | headless-shell | showcase | 16.7 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 13638 | {"unused": 12, "running": 12} | 9408 | None | 9885 | 6435 | 158/132 |
| r5-C-hs-sc | 16:49:47 | C | headless-shell | showcase | 16.6 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 13629 | {"unused": 12, "running": 12, "parked": -1} | 9314 | None | 10108 | 6798 | 158/132 |
| r5-D-hs-sc | 16:51:14 | D | headless-shell | showcase | 16.5 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 13920 | {"unused": 12, "running": 12, "parked": 0} | 9309 | None | 10365 | 6690 | 158/132 |
| r5-B-hs-sc | 16:52:41 | B | headless-shell | showcase | 16.8 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 13662 | {"unused": 4, "running": 20, "parked": 8} | 9198 | None | 10246 | 6828 | 158/132 |
| r5-A-hd-sc | 16:54:07 | A | headed | showcase | 16.6 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 14266 | {"unused": 12, "running": 12} | 8781 | None | 9270 | 6555 | 158/132 |
| r5-C-hd-sc | 16:55:35 | C | headed | showcase | 16.2 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 14201 | {"unused": 12, "running": 12, "parked": -1} | 9415 | None | 9489 | 6583 | 158/132 |
| r5-D-hd-sc | 16:57:03 | D | headed | showcase | 16.0 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 14354 | {"unused": 12, "running": 12, "parked": 0} | 9142 | None | 9513 | 6630 | 158/132 |
| r5-B-hd-sc | 16:58:31 | B | headed | showcase | 16.5 | 621.81 | 0.0 | - | False | no crash | - | - | 0 | 14089 | {"unused": 4, "running": 20, "parked": 8} | 9389 | None | 9389 | 6732 | 158/132 |
| q1-A-hd-st | 19:12:39 | A | headed | stock | 23.6 | 605.81 | -16.0 | - | True | no crash | - | - | 0 | 13118 | {"unused": 13, "running": 11} | 9139 | None | 11729 | 6077 | 158/132 |
| q1-C-hd-st | 19:13:20 | C | headed | stock | 23.3 | 605.81 | 0.0 | - | True | no crash | - | - | 0 | 13349 | {"unused": 14, "running": 10, "parked": -1} | 9293 | None | 11846 | 6321 | 158/132 |
| q1-D-hd-st | 19:14:01 | D | headed | stock | 22.8 | 605.81 | 0.0 | - | True | no crash | - | - | 0 | 13490 | {"unused": 13, "running": 11, "parked": 0} | 9476 | None | 11856 | 6332 | 158/132 |
| q1-A-hd-sc | 19:14:42 | A | headed | showcase | 23.0 | 605.81 | 0.0 | - | True | CRASH | V2 | reload 4 +2128 ms | 1 | 13582 | {"unused": 11, "running": 13} | 9336 | 96 | 11775 | None | 158/158 |
| q1-C-hd-sc | 19:15:19 | C | headed | showcase | 23.1 | 605.81 | 0.0 | - | True | no crash | - | - | 0 | 13676 | {"unused": 11, "running": 13, "parked": -1} | 9261 | None | 11945 | 6158 | 158/132 |
| q1-D-hd-sc | 19:16:00 | D | headed | showcase | 22.8 | 605.81 | 0.0 | - | True | CRASH | V2 | reload 3 +2074 ms | 1 | 13751 | {"unused": 11, "running": 13, "parked": 0} | 9710 | 96 | 12149 | None | 132/132 |
| q2-C-hd-st | 19:16:35 | C | headed | stock | 23.0 | 605.81 | 0.0 | - | True | no crash | - | - | 0 | 13694 | {"unused": 14, "running": 10, "parked": -1} | 9363 | None | 11982 | 6252 | 158/132 |
| q2-D-hd-st | 19:17:16 | D | headed | stock | 23.0 | 605.81 | 0.0 | - | True | no crash | - | - | 0 | 13696 | {"unused": 14, "running": 10, "parked": 0} | 9432 | None | 11947 | 6369 | 158/132 |
| q2-A-hd-st | 19:17:58 | A | headed | stock | 22.9 | 605.81 | 0.0 | - | True | no crash | - | - | 0 | 13542 | {"unused": 13, "running": 11} | 9414 | None | 11809 | 6195 | 158/132 |
| q2-C-hd-sc | 19:18:39 | C | headed | showcase | 23.0 | 605.81 | 0.0 | - | True | CRASH | V2 | reload 3 +2087 ms | 2 | 13836 | {"unused": 9, "running": 15, "parked": -1} | 9230 | 96 | 11992 | None | 132/132 |
| q2-D-hd-sc | 19:19:14 | D | headed | showcase | 22.7 | 605.81 | 0.0 | - | True | no crash | - | - | 0 | 13715 | {"unused": 12, "running": 12, "parked": 0} | 9497 | None | 11824 | 6215 | 158/132 |
| q2-A-hd-sc | 19:19:55 | A | headed | showcase | 22.8 | 605.81 | 0.0 | - | True | CRASH | V2 | reload 4 +2078 ms | 1 | 13758 | {"unused": 12, "running": 12} | 9318 | 12032 | 12032 | None | 158/158 |
| q3-D-hd-st | 19:20:33 | D | headed | stock | 22.9 | 605.81 | 0.0 | - | True | no crash | - | - | 0 | 13379 | {"unused": 14, "running": 10, "parked": 0} | 9206 | None | 11699 | 6138 | 158/132 |
| q3-A-hd-st | 19:21:14 | A | headed | stock | 22.8 | 605.81 | 0.0 | - | True | no crash | - | - | 0 | 13527 | {"unused": 13, "running": 11} | 9143 | None | 11606 | 6062 | 158/132 |
| q3-C-hd-st | 19:21:55 | C | headed | stock | 22.8 | 605.81 | 0.0 | - | True | no crash | - | - | 0 | 13651 | {"unused": 14, "running": 10, "parked": -1} | 9434 | None | 11927 | 6297 | 158/132 |
| q3-D-hd-sc | 19:22:36 | D | headed | showcase | 22.8 | 605.81 | 0.0 | - | True | CRASH | V2 | reload 4 +2081 ms | 1 | 13694 | {"unused": 12, "running": 12, "parked": 0} | 9122 | 97 | 11926 | None | 158/158 |
| q3-A-hd-sc | 19:23:13 | A | headed | showcase | 22.8 | 605.81 | 0.0 | - | True | CRASH | V2 | reload 4 +2148 ms | 1 | 13695 | {"unused": 10, "running": 14} | 9300 | 96 | 12066 | None | 158/158 |
| q3-C-hd-sc | 19:23:51 | C | headed | showcase | 22.8 | 605.81 | 0.0 | - | True | no crash | - | - | 0 | 13735 | {"unused": 13, "running": 11, "parked": -1} | 9197 | None | 11866 | 6280 | 158/132 |

## Notes

* The dedicated quiet round: `master.sh` with `ROUNDS=0` (polling only), `quiet_round`: A C D × headed × stock/showcase,
  3 runs each, pin order rotated per repetition (A C D, C D A, D A C), in ONE lock hold.
* `smoke1-D-hs-sc` never launched (a `set -u` bug in `run-arm.sh` with an empty flag array, fixed before the rounds);
  `smoke2-D-hd-st` is the smoke crash above. Neither is in the tables.
* "Quiet at launch" in the host-state table is ONE sample per run (≥ 20 GB reclaimable, no foreign heavy process, swap
  not grown by > 32 MB since the previous run), not the 5-minute window the dedicated quiet round required; with one run
  per cell it shows that V2 does not need a loaded host (r1-D-hs-st launched at 22.3 GB with no foreign process), not a rate.
* `rssBeforeCrash` 0 means the last 250 ms sample before the crash found no renderer in this run's process tree (the
  renderer was being replaced across the reload at that moment; inferred from the sample, not shown otherwise).
* Earlier evidence, other windows: l9-desktop (05:34–08:33Z) headed C 4/19, A 1/5, B 3/8; the quiet slot (11:03–11:21Z)
  headed A 1/8, C 2/10, D 0/5, B 1/2 (`out/ux/l9-quiet/RESULTS.md`). Today's interleaved rounds put D and C level.

## Deletable (nothing was deleted)

* `$W/final-gate/gallery-{1859b83,9fdf9b8,5ac5d00,3b42714}/` (564K each; APFS clones of `gallery/` for the per-pin
  servers), `$W/final-gate/pre-edit/` (484K; pre-edit copies of the files this lane changed).
* `out/ux/final-D-headed1/` (238M: traces of the 7 failures, kept as the evidence of the headed root causes).
* `out/ux/profiles/ux-warm-headed/` (3.5G; the headed sign-off's warm profile, needed only for the next headed run).
* `$W/deploy-rehearsal/bucket.prev-20261002T205606Z` (2.3G) and the older `bucket.prev-20261002T091605Z` (3.4G).
