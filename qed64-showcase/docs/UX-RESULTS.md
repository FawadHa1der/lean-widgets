# UX results: the exhaustive Playwright suite (BUILD-PLAN §8, with TEST-PLAN-DELTAS applied)

Written 2026-10-01 by the UX-suite lane, and revised the same day after an adversarial audit (see "Audit
response"). The suite runs against the brought-up M2 gallery (`/showcase/`, overlay `widgets8`) and against the stock
QED64 page. Pins (keyed by QED64 commit since 2026-10-02). The SERVED pin is whatever `scripts/showcase.sh pin current`
prints (on 2026-10-04 that is E `33b0967`, runtime `wasm64-3ab1c6a9da03bc29`, QED64 main with the #54 boot-card and
#55 reload-OOM fixes; see out/ux/pin-e/RESULTS.md). C `5ac5d00` (runtime `wasm64-4b025db7729c5f89`) was served from
2026-10-02 to 2026-10-04; A `1859b83` (the same runtime, the first pin: every run before 2026-10-01 20:35Z) is the
fallback; B `9fdf9b8` (runtime `wasm64-2c18773ecfba45bb`, served from the 2026-10-01 re-pin until the multi-pin lane)
is kept as L9 evidence; D `3b42714` (runtime `wasm64-3ab1c6a9da03bc29`, QED64's 0035b L9 candidate; served 17:35–19:26Z
on 2026-10-02 by the final-gate lane) is staged. Sections below are dated and say which pin they ran on; "the current pin" inside a section means
that section's pin. The QED64 repo was not changed. Every number below comes from a run whose files are named here. Logs
are in `work/logs/` (`work` = `/Users/fawadhaider/code/qed64-showcase-work`). Run outputs are in `out/ux/<run>/`.

## Current state: run the tools

This file does not name the latest verdict or count the verdicts as current state; every later run would make such a
line wrong. The current state is printed by:

* `scripts/showcase.sh gallery`: the gate, the current gallery content sha256, and `UX CURRENT …` (the newest verdict run
  on exactly this gallery + lock + overlays, plus a headed sign-off if one exists) or `UX STALE`;
* `scripts/showcase.sh pin list`: per pin, the full runs on its lock, the VERDICT count and last VERDICT, and the HEADED
  SIGN-OFF count and last sign-off (headed runs are judged as sign-offs, never as verdicts);
* `node scripts/deploy-manifest.mjs --check`: the `G2 UX:` line a deploy relies on;
* `node scripts/ux-tally.mjs`: every tally in the table below, recomputed.

The boot-fix lane (2026-10-03, "Boot-fix lane" below) changed `gallery/gallery.js`, so the verdicts on gallery
`921b0b6a…` listed in the snapshot below no longer apply to the current gallery. The post-audit fix lane (2026-10-03,
"Post-audit fix lane" below) changed `gallery.js` and `gallery.css` again (gallery `b7aa521a…`), so the closure lane's
verdicts on `31f6d8d9…` stopped applying too.

## Status and tallies: history snapshot (2026-10-03 ~03:50Z, final docs lane)

**Source of truth.** `node scripts/ux-tally.mjs` recomputes every tally below from the recorded runs (each
`out/ux/<run>/{run-meta.json, report.json, tests/*.json}`; a test "crashed" when its record has `"crashed": true`, i.e.
Playwright saw the renderer die), judges `out/ux/showcase-ux-runs.jsonl` with the one VERDICT rule
(`scripts/lib/ux-record.mjs`), and reads the reload-storm files. Its output at the end of the final docs lane
(2026-10-03, after the last-mile lane's last run at 03:35Z) is `work/logs/finaldocs-ux-tally.txt`: 118 run directories
with a report, 57 `showcase.sh ux` records, 16 VERDICT runs, 19 stock reload storms (the 2026-10-02 figures, 106 / 45 /
11, are in `work/logs/docsfinal-ux-tally.txt`). Where an older section's running tally differs, this table is right.
Per-record judgments re-run by this lane (`node scripts/lib/ux-record.mjs verdict`, `work/logs/finaldocs-verdicts.log`):
`final-C-full1`, `final-C-full2`, `final-D-full1`, `final-D-full2`, `auditF-C-full1`, `v2mit-full1`, `v2mit-full2`,
`lastmile-full1`, `lastmile-full2` VERDICT; `final-C-headed1`, `final-D-headed2` HEADED SIGN-OFF; `v2mit-headed1`
(3 unexpected), `lastmile-chrome-headed1` (5), `lastmile-chrome-headed2` (2) and the two `--grep "C10 |C13"` subsets not
a sign-off. The tool attributes a run to the pin in its `run-meta.json` (the active pin), so the two A subset runs
`harden-A-c21c22` and `auditF-A-c21c22`, which served A through `UX_ORIGIN`, are counted under C below
(`work/logs/finaldocs-tally-attribution.log`).

| | A `1859b83` (fallback) | B `9fdf9b8` (L9 evidence) | C `5ac5d00` (served) | D `3b42714` (staged) |
|---|---|---|---|---|
| VERDICT runs | `closeout-full1` (gallery `c8492b70…`) | `final-full1` (gallery `7bbddf2e…`) | `multipin-C-full2-b`, `multipin-C-full3-b` (gallery `a4b34ead…`); `docs-full1`, `audit-full1` (`2f95d07c…`); `harden-C-full1`, `final-C-full1`, `final-C-full2`, `auditF-C-full1` (`2081098d…`); **`v2mit-full1`, `v2mit-full2`, `lastmile-full1`, `lastmile-full2` (gallery `921b0b6a…`, current at that snapshot)** | `final-D-full1`, `final-D-full2` (gallery `eab4f147…`) |
| Headed sign-off (`UX_HEADED_ALL=1`, never a verdict) | – | – | **`final-C-headed1`** (34/34, `2081098d…`); none on `921b0b6a…`: `v2mit-headed1` 31/34, branded Chrome 154 `lastmile-chrome-headed1` 29/34, `lastmile-chrome-headed2` 32/34 ("Last-mile lane") | `final-D-headed2` (34/34); `final-D-headed1` 27/34 (root-caused, "Final gate") |
| Full runs (≥ 30 tests) | 8 (`full1`, `full3`–`full7`, `auditor-full`, `closeout-full1`); 0 failed tests in all of them (`auditor-full` was interrupted by the L7 hang in C20) | 7: 1 green (`final-full1`), 6 red, **every red one with a renderer crash** | 17: `multipin-C-full1` (C12 + C14 on QED64 N2, root-caused); 13 green (`multipin-C-full2-b`, `multipin-C-full3-b`, `docs-full1`, `audit-full1`, `harden-C-full1`, `final-C-full1`, `final-C-full2`, headed `final-C-headed1`, `auditF-C-full1`, `v2mit-full1`, `v2mit-full2`, `lastmile-full1`, `lastmile-full2`); 3 headed red without a crash (`v2mit-headed1`: C4, C13a, C13b; `lastmile-chrome-headed1`: C4, C10, C11, C13a, C13b; `lastmile-chrome-headed2`: C10, C13b) | 4: `final-D-full1`, `final-D-full2`, `final-D-headed2` green; `final-D-headed1` red (headed-only causes) |
| C10 (reload storm in the suite) | 0 crashes in 11 runs (7 full) | **crashed in 6 of the 8 runs that ran it**: 5 of 7 full runs (`repin-full1`, `final-full2`, `closeout2-full1`, `closeout3-full1`, `audit-cl3-full1`) plus the W4 + C10 rerun `repin-crash1`; passed in `final-full1`, `audit-final-full` | 0 crashes in 19 runs (17 full); 3 failed without a crash, all branded Chrome 154 (settled RSS over the 10.5 GB line) | 0 crashes in 4 runs (4 full) |
| C21 crashes | 0 in 10 runs | 4 (`repin-full1`, `final-full2`, `audit-final-full`, the audit mutant `audit-final-mut-mutC`), all before (b) got its own browser in close-out 2; 0 since | 0 in 19 runs | 0 in 4 runs |
| W4 crashes | 0 in 14 runs | 1 of 8 (`repin-full1`) | 0 in 17 runs | 0 in 4 runs |
| C20 (click-all, 135 links) | 21 recorded runs: 14 at 135/135; not clean: the L7 hang (`auditor-full`, interrupted), four runs from the suite's development (`dev5`, `dev7`–`dev9`), the audit mutant `auditor-mutCD`, and `c20rep4` (aborted after 56 clean links by host contention) | **17 runs, all 135/135** (2,295 clicks), 0 card stalls, 0 gallery wedges; QED64 rescues 0 and `wedged` reboots 0 in the 16 runs that record them (`repin-full1` predates the counters) | **23 runs, all 135/135** (3,105 clicks), 0 card stalls, 0 gallery wedges, QED64 rescues 0, `wedged` reboots 0 | **4 runs, all 135/135** (540 clicks), 0 card stalls, 0 gallery wedges, QED64 rescues 0, `wedged` reboots 0 |
| Stock reload storm, chrome-headless-shell (`reload-storm.mjs`) | 0/5 (`repin-ab` old1–5) | 3/8 (`repin-ab` new2, new3, new5; `multipin-storm` B-1..3 0/3) | 0/6 (`multipin-storm` C-1..6) | not run with this tool (see the final gate) |
| Same storm in desktop Chrome 151 (`out/ux/l9-desktop/RESULTS.md`) | headed 1/5 (V2) | headless-shell 4/11 (V1), new headless 0/8, headed 3/8 (V1 + V2) | headless-shell 0/6, new headless 0/6, **headed 4/19 (V2)** | not run |
| Quiet slot, headed (`out/ux/l9-quiet/RESULTS.md`) | 1/8 (V2) | 1/2 (V1) | 2/10 (V2) | 0/5 |
| **Final-gate interleaved storms** (`out/ux/final-storm/RESULTS.md`; table in "Final gate") | **3/26 V2** | **3/20 V1** | **2/26 V2** | **3/26 V2** (+1 V2 in the tool's smoke run) |

**Gates at the end of this lane** (gallery `921b0b6ac801e044…`, current then, pin C, nothing changed under `gallery/`, `tests/`
or `scripts/` by this lane): `scripts/showcase.sh verify` → `VERIFY: all checks OK` with 1 `DRIFT` (the Docker tag,
rebuild-only); `scripts/showcase.sh gallery` → `CHECK-GALLERY OK 128 ok, 0 failed`, `SIM-GALLERY OK 101 ok, 0 failed`,
gate GREEN, `UX CURRENT … lastmile-full2`; `node scripts/deploy-manifest.mjs --check` → `DEPLOY-MANIFEST CHECK OK`
(`work/logs/finaldocs-{verify,gallery,deploy-manifest-check}.log`).

**Corrections the 2026-10-02 final docs lane made to older text** (each now matches the tool):
* "C10 crashed in 6 of 8 **full** runs on 9fdf9b8": `repin-crash1` ran only W4 and C10, so it is 6 of the 8 runs that
  ran C10, and 5 of 7 full runs. The same wording was fixed for the earlier "4 of 6" and "3 of 4" (they counted
  `repin-crash1` as a full run too).
* "The last audit's `audit-final-full1` … its run directory is no longer in `out/ux`": the run directory is
  `out/ux/audit-cl3-full1` (its log is `work/logs/audit-final-full1.log`); the last audit's C20-only run is
  `out/ux/audit-cl3-c20` (log `audit3-c20.log`).
* "16 C20 runs on 9fdf9b8 (2,160 clicks, 4,320 edits)": 17 runs and 2,295 clicks; the C20 of the first re-pin full run
  `repin-full1` (135/135) had not been counted. The hang-hunt figures (8 observe-mode runs, 1,080 clicks, 2,160 edits)
  were right.
* "W4 crashed in 1 of 6": 1 of the 8 runs on B that ran W4.
* README and docs/UPSTREAM-REPORT-QED64.md still said B was the served pin in places; fixed.

## Post-audit fix lane: the final audit's findings (2026-10-03, 16:28Z onward, pin C, gallery `b7aa521a…`)

Dated record; which verdicts apply now is printed by the tools ("Current state: run the tools"). Logs
`work/logs/postaudit-*.log`; pre-edit copies `work/postaudit/pre-edit/`; chain scripts `work/postaudit/{chain,inner}.sh`.

* **Gallery changes** (`gallery/gallery.js`, `gallery/gallery.css`; content sha256 `b7aa521aba05ac48…`, was
  `31f6d8d9…`): (1) a page resource counts as boot progress only when its URL (query and hash stripped) was not seen
  before in this boot, so a page re-fetching one file cannot keep re-arming the 240 s stall window (`status().boot.
  resourceUrls`); (2) the "Still downloading" notice sits just below the QED64 page's own top bar, so it no longer
  covers the page's status pill (`throttle-pa10-0481s.png` shows the pill free; the notice still covers part of the
  editor's top lines and can be dismissed). `check-gallery.mjs` lists the page id `bar`. Sim run 15e and two placement
  checks: `SIM-GALLERY OK 114 ok`; mutants fail them (resource dedupe removed: 2 FAIL; placement removed: 1 FAIL).
* **Tools.** `showcase.sh ux` refuses (rc 3, before any server or lock) a `UX_RUN` whose `out/ux/<run>/` exists or
  that the run log already records (`postaudit-runname-refuse1.log`: `audit-full1` refused; predicate checked on the
  real jsonl, `postaudit-runname-predicate.log`). `throttled-first-visit.mjs` now prints `RESULT PASS|FAIL: <why>` and
  exits 0/1 (`--expect-card` for a deliberate stall test, `--grace-s`). `pin list` labels `pin.json`'s `status` as a
  hand-written role note (history) and the verdict line as `computed now`; the three stale status texts no longer
  name verdicts as current state.
* **Browser proof on `b7aa521a…`** (fresh profiles, fixed `throttle-proxy.mjs`, under the lock): 10 Mbit/s
  `pa10` ready 565.0 s, error card in 0 samples, notice from 231.5 s, panel EQUAL, `RESULT PASS` rc 0; forced stall
  (`?bootTimeout=10&bootStall=3`, 50 Mbit/s): without `--expect-card` rc 1 `RESULT FAIL: error card in 64 samples`,
  with it rc 0 (card at 56.2 s, closed at ready 120.3 s, panel EQUAL). Full suites: `postaudit-full1` and
  `postaudit-full2` VERDICT (33 passed, 1 skipped each; C10 no crash, settled renderer 9.84 / 9.65 GB; C20 135/135);
  `postaudit-headed1` (Chrome for Testing, `UX_HEADED_ALL=1`) 34 passed, HEADED SIGN-OFF (C10 9.85 GB, C20 135/135).
  0 test records with `crashed: true` in the three.
* **Deploy.** `deploy-manifest.mjs --overlays widgets8,widgets7` regenerated `out/deploy` (only `showcase/gallery.js`,
  `showcase/gallery.css` and the totals changed); `--check` OK with `G2 UX: verdict run postaudit-full1 … on THIS
  gallery` right after the first verdict; `rehearse.sh all`, `browser` (`BOOT-CHECK OK`), `stop` rc 0.
* **A run started by mistake.** A refusal test of this lane ran `showcase.sh ux` with an empty `UX_RUN` (the lookup
  for a jsonl-only name found none), so it started a full run under the default name
  `showcase-showcase.sh-20261003T163558Z` on the pre-final gallery. It could not be stopped from this lane, the gallery
  CSS comment was then corrected during it, and it is recorded as rc 0, 33 passed, **NOT A VERDICT (gallery changed
  during the run)**. It is no evidence for or against `b7aa521a…`.
* **Docs.** The undated "Verdict" section of this file is now a dated history table; L9's visitor-path risk in
  README.md, docs/DEPLOY-CLOUDFLARE.md, gallery/README.md and open issue 1 includes the v2-embed lane (headed
  `/showcase/` 24/56 = 43 %, latest window 15/24 = 62 %; cause mainly embedding); docs/UPSTREAM-REPORT-QED64.md L9 has the
  gallery-free repro; docs/NEXT-STEPS.md says a gallery-side fix cannot remove it.

## v2-embed lane: why the gallery entry raises L9 V2 (2026-10-03, 06:55–09:12Z, pin C, gallery `31f6d8d9…`)

Full write-up: `out/ux/v2-embed/RESULTS.md` (per-run table `storm-table.md`/`.json`, logs `work/logs/v2embed-*.log`).
120 headed storms in Chrome for Testing 151 with the harness's device-scale pin, 24 per arm, interleaved arm by arm in 12
batches, each after a ≥ 300 s quiet streak, all quiet at launch. One storm = fresh profile, boot to ready, 5 reloads 3 s
apart (`reload-storm-desktop.mjs`, a variant copy in `$W/v2embed/`). V2 per arm:

| arm | top-level page | boot document | V2 |
|---|---|---|---|
| S | the gallery `/showcase/#hasse-view` | hasse-view (the gallery seeds it) | **15/24** (+1 non-V2 OOM) |
| Is | test page: the stock page in a script-free iframe (not shipped) | hasse-view (seeded) | 10/24 |
| I | the same test page | QED64's default document | 6/24 |
| Ps | the stock page `/?snapshots=snapshots/widgets8` | hasse-view (seeded) | 2/24 |
| P | the stock page | QED64's default document | 2/24 |

Fisher two-sided: embedding with the document equal Is vs Ps p = 0.017, pooled I+Is vs P+Ps 16/48 vs 4/48 p = 0.005;
gallery code S vs Is p = 0.25 (halves 9/12 vs 4/12, then 6/12 vs 6/12); document at top level Ps vs P p = 1.0. Decision:
**mainly embedding per se**; a gallery-code increment of about 20 points is neither shown nor excluded. Recounted from
`storm-table.json` by the post-audit fix lane (`work/logs/postaudit-v2embed-check.log`) and from the raw files by the final
audit (`work/logs/audit-v2embed-recompute.log`). Arm G (the gallery with probe and bridge off) was not run: no query option
turns the bridge off. The lane changed nothing in `gallery/`.

## Closure lane: final verification (2026-10-03, 09:15–14:49Z, pin C, gallery `31f6d8d9…`)

Full write-up with every command and number: `out/ux/closure/RESULTS.md`. Logs `work/logs/closure-*.log`. `gallery/` was
not changed (`31f6d8d9…` from start to end).

| Check | Result |
|---|---|
| `closure-full1` (09:18–09:42Z), `closure-full2` (09:42–10:03Z), full suite | 33 passed, 1 skipped each: **VERDICT, VERDICT**; C10 no crash (settled renderer 9.84 / 9.95 GB); C20 135/135; W4 passed |
| `closure-headed1` (`UX_HEADED_ALL=1`, Chrome for Testing 151; lock 11:03–11:25Z) | **34/34 including C19: HEADED SIGN-OFF**; C10 settled renderer 9.95 GB; C20 135/135 |
| Throttled first visit, fresh profile, fixed `throttle-proxy.mjs` | 10 Mbit/s **ready 565.1 s**, notice from 231.5 s; 50 Mbit/s **ready 120.3 s**; error card in 0 samples, console OK, panel equal (`fp10`, `fp50`) |
| `soak.mjs --minutes 60` | 473 operations, 0 failed, no crash, no stall or restart; renderer RSS +4.5 MB/min after cycle 1 (R² 0.89), slowing (9.2 → 3.9 → 2.7 MB/min per 20 min) but not level at 60 min |
| Deploy | manifest regenerated byte-identical, `--check` OK (G2 names a verdict on this gallery); `rehearse.sh all` rc 0 on the second attempt; `BOOT-CHECK OK` |
| `assert-untouched.sh check closure` | **CHANGED**: other sessions committed and built in QED64 (`3e182ff`, HARDENING #54) and lean4game during the lane (attribution in the write-up); kernel trees and widgets-v4.34 OK |

Three defects in the test tools were found and fixed. None of them is in the gallery:
* **`throttle-proxy.mjs` could reorder bytes** within a connection, because each slice had its own timer started from the cached loop time. It corrupted one 50 Mbit/s snapshot download: QED64's raw prefetch failed with "invalid code lengths set", then the snapshot was streamed and the boot still succeeded. Before the fix, an order test broke order in 6 of 6 runs; after the fix (a FIFO per connection), 6 of 6 kept order.
* **`sim-gallery.mjs` run 15a sampled the status line once per 100 ms progress call.** The line is rendered on the gallery's 250 ms tick, so the check passed only if a tick fell into a ~100 ms window. A 200 ms event-loop stall failed it 4 of 4 times (`108 ok, 1 failed`, as in the first rehearsal's G1). It now waits up to 350 ms for the tick and passed 3 of 3 times under the same stall; a mutant still fails it.
* **`deploy-manifest.mjs` G1 dropped check-gallery's indented sim FAIL lines.** They are now kept, so a G1 failure names its case.

## Boot-fix lane: slow first visits (2026-10-03, pin C, gallery `31f6d8d9…`)

The last-mile lane's defect (a fixed 360 s first-boot budget stranded a healthy 10 Mbit/s visitor on "This is taking
too long", and a later `ready` never closed it) is fixed in `gallery/gallery.js`: the boot wait re-arms on progress
(QED64's byte progress to its `qed64.ui` sink, new stage labels, phase/relay/session/version, page resources), shows a
non-blocking "Still downloading: <QED64's step> — X of Y so far" notice, errors only after 360 s and 240 s without
progress, and a later `ready` closes the card and finishes the boot (gallery/README.md "Timeouts"). Logs
`work/logs/bootfix-*.log`; pre-edit copies `work/bootfix/pre-edit/`.

| Check | Result |
|---|---|
| `scripts/sim-gallery.mjs` run 15 | slow progress 2 s past budget + stall window: no card, notice, ready, notice gone; true stall (re-sent bytes ignored): card, selection `TIMEOUT`; late ready: card closed, cursor, focus, switch works; defaults 360/240/120 s. Mutants: progress ignored → 4 FAIL; late path removed → run 15c times out |
| `throttled-first-visit.mjs`, 10 Mbit/s / 40 ms, fresh profile, `throttle-proxy.mjs` (`throttle-p10b`, final code) | **ready 565.0 s, error card in 0 of 575 samples**, visible progress in 563 of 564 samples before ready (QED64's boot card until 231 s, then the gallery's notice), longest unchanged 19.0 s, 693.0 MB at 9.8 Mbit/s, console oracle OK, **panel at ChartKit's first cursor equal to its golden**. Before the fix (`lastmile-throttle/throttle-p10`): card at 466.9 s, never cleared |
| same, draft notice wording (`throttle-p10-draft1`) | ready 564.0 s, 0 card samples, panel equal; its notice summed QED64's prepared bytes into "so far" (1.56 GB against 693 MB on the wire), so the wording now quotes QED64's current step only |
| `?bootTimeout=10&bootStall=3`, 50 Mbit/s (`throttle-stall50`) | the stall card at 56.2 s ("no download or start-up progress for 3.0 s …"), QED64 ready at 118 s, the card closed by itself, gallery ready at 120.3 s, `boot.recovered` 1, panel equal |
| `scripts/showcase.sh gallery` (before the runs below) | `CHECK-GALLERY OK 128 ok`, `SIM-GALLERY OK 109 ok`, gate GREEN on `31f6d8d9…`, `UX STALE` |
| `bootfix-full1` (05:20–05:42Z), full suite | 31 passed, 2 failed, 1 skipped: **not a verdict**. W4 (Simp Lens): renderer crash ("Target crashed") 145 ms after a quiet `[qed64] ready` during its 5th code action, after 4 code actions passed; no worker death or relay restart before it; C14 failed only by aggregating that crash. No browser stderr was captured and macOS kept no crash report for the renderer (pid 9817; `work/logs/bootfix-w4-crash-syslog.log`), so the crash class is unknown |
| `bootfix-full2` (05:42–06:03Z), full suite | 33 passed, 1 skipped (C19): **VERDICT**; C1 cold boot, C11 network cut (both boot-error paths) and W4 passed |
| `bootfix-w4x5`, `bootfix-w4x15` (`--grep "W4 " --repeat-each`, `DEBUG=pw:browser`) | **20/20 passed, no crash**: the W4 crash did not reproduce |
| `bootfix-full3` (06:15–06:36Z), full suite with `DEBUG=pw:browser` | 33 passed, 1 skipped: **VERDICT**, no crash |

**The W4 crash.** One renderer crash in 23 W4 executions on this gallery (3 full runs + 20 repeats); 0 crashes in the 18
run directories with W4 on C before it (`node scripts/ux-tally.mjs`, `work/logs/bootfix-ux-tally.txt`; it counts a
repeat run once). Not root-caused: there is no V8 line or crash report. Inference, not shown: it is unrelated to the boot fix,
because after `ready` the new code only runs two no-op checks per 250 ms tick (`tapUi` returns at once once the sink is
wrapped; `lateBootCheck` returns while nothing is pending) and the wrapped sink adds bounded bookkeeping per QED64 status
call. G2 of `deploy-manifest --check` only reports red runs that come AFTER the verdict it names, so it does not show
`bootfix-full1`; this table does.

The tool now also records the gallery's notice (as visible progress), its `status().boot`, and the panel after ready
(`--no-panel` skips). `pin list` now judges headed records as `HEADED SIGN-OFF` / `NOT A HEADED SIGN-OFF` instead of
`NOT A VERDICT`, and counts them separately.

## Last-mile lane: verdicts, branded Chrome headed, Safari, throttled first visit, soak (2026-10-03, pin C)

Full write-up with every number and command: `out/ux/last-mile/RESULTS.md`. In short:

| Run | Pin / gallery | Result |
|---|---|---|
| `lastmile-full1` (01:03–01:24Z) | C, `921b0b6a…` | 33 passed, 1 skipped: **VERDICT** (C10 no crash, settled 9.74 GB; C20 135/135) |
| `lastmile-full2` (01:24–01:45Z) | C, `921b0b6a…` | 33 passed, 1 skipped: **VERDICT** (C10 settled 10.12 GB; C20 135/135); `showcase.sh gallery` then → `UX CURRENT … lastmile-full2` |
| `lastmile-chrome-headed1` | C, headed **branded Chrome 154** (`UX_CHANNEL=chrome`) | 29/34: C4, C13a, C13b (the display scale, below), C11 (this lane's own server held :5191), C10 |
| `lastmile-chrome-headed2` | same, headed launches pinned to DSF 1 | **32/34** (C19, C4, C11, C13a, C20 135/135 pass): C13b (Chrome 154 draws no classic scrollbars at 390 px), C10 (settled 10.68 GB > 10.5 GB). Not a sign-off |
| `lastmile-cft-headed-c10c13` / `lastmile-chrome-headed-c10c13` | `--grep "C10 \|C13"`, Chrome for Testing 151 / Chrome 154 | 4/4 (C10 settled 10.07 GB) / 2/4 (C10 10.75 GB, C13b) |

**Headed root cause (supersedes the v2mit lane's locked-screen inference):** a headed window rasterises for the scale
of the real display even with `deviceScaleFactor: 1` emulated. With `--force-device-scale-factor=1`, C13a's hasse-view
panel is pixel-identical to the headed baseline. Without it, on the 2x Retina panel, it equals the failing runs'
image exactly (`tests/ux/tools/c13-dsf-probe.mjs`). With the screen locked, both headed builds report hardware
raster, a 2x display, 120 Hz rAF and 17 ms clicks. `tests/ux/lib/qed64.mjs` now adds that flag to headed launches only.

**Safari 26.6.2:** WebDriver refused ("Allow remote automation" off; not changed). **Throttled first visit**
(`tests/ux/tools/throttle-proxy.mjs`; CDP emulation answers "Not supported" in QED64's workers): 50 Mbit/s ready in
123.3 s with progress throughout; at 10 Mbit/s the gallery's 360 s boot timeout fired at 467 s and never cleared,
although QED64 was ready at 577 s (fixed since: "Boot-fix lane" above). **Soak** (`tests/ux/tools/soak.mjs`, 22 min): 173 operations on all 8 widgets,
0 failed, no crash or stall, per-cycle max RSS 8.14 → 8.23 GiB, wasm heap flat at 2.00 GiB.

## v2mit lane: a gallery-side L9 V2 mitigation (rejected) and the measured memory wording (2026-10-02/03, pin C)

**(A) L9 V2 mitigation: measured, rejected, never shipped** (`out/ux/v2mit-storm/RESULTS.md`, generated tables in
`out/ux/v2mit-storm/storm-table.md`). Treatment = the gallery plus a `pagehide` handler that calls
`qed64.relay.unload()` and removes the iframe; control = the unchanged gallery; both on pin C via `SHOWCASE_PIN` +
`GALLERY_DIR` (`:5221`, `:5222`), `/showcase/` reload storms with `tests/ux/tools/reload-storm-desktop.mjs`, arms
interleaved, all 72 runs launched on a quiet host (22.5–22.9 GB reclaimable, no foreign heavy process):

| | headed Chrome for Testing 151 | chrome-headless-shell 151 |
|---|---|---|
| control (the then-current gallery `2081098d…`) | **8/24** V2 | 0/12 |
| teardown on `pagehide` | **10/24** V2 | 0/12 |

The rule written before the headed extension (`$W/logs/v2mit-decision-rule.log`) kept it only if it had fewer V2 crashes
with one-sided p < 0.10; it had more (two-sided Fisher p = 0.77). A probe (`$W/v2mit/teardown-probe.mjs`,
`out/ux/v2mit/explore/`) shows why: the old page's 26 workers report `close` 7–40 ms after `page.reload()` in both arms,
the top `beforeunload` fires at 4–7 ms and `pagehide` at 9–16 ms, the new page's first worker appears at 113–185 ms.
`gallery/gallery.js` is unchanged.

**(B) Memory wording.** `lib.js` `BROWSER_NEED` is now "This showcase needs a Chromium-based desktop browser (Chrome,
Edge, Brave, Arc) on a computer with 16 GB of RAM or more, one showcase tab at a time (a tab uses about 8–9 GB, about
12 GB on a reload)"; the low-memory check reads "the device reports only N GB of memory; a showcase tab uses about
8–9 GB, about 12 GB on a reload"; the `<noscript>` line says the same. Figures from the six final-gate suite runs
(`$W/logs/memtext-measured.log`): C3 at ready 8.2–9.0 GiB, C10 transient peak 11.8–12.2 GB, C18 two tabs 16.9–17.8
GiB, C16 "Load exact imports" 15.5–16.6 GiB. The warning threshold stays 8 GB (an owner decision, docs/NEXT-STEPS.md).
check-gallery 7, sim-gallery run 14 and UX C24 assert the new sentence (the old card text quoted in "Hardening lane"
below is that lane's).

| Run | Pin / gallery | Result |
|---|---|---|
| `v2mit-c24` | C, `921b0b6a…`, `--grep "C24 "` | 1 passed: the card shows the new sentence in real Chromium (`screens/C24-low-memory.png`) |
| `v2mit-full1` (23:40–00:01Z) | **C `5ac5d00`**, `921b0b6a…` | 33 passed, 1 skipped (C19): **VERDICT**. C10 no crash (transient peak 11.76 GB); C20 135/135 |
| `v2mit-full2` (00:01–00:22Z) | C, `921b0b6a…` | 33 passed, 1 skipped: **VERDICT**; C20 135/135; `showcase.sh gallery` then → `UX CURRENT … v2mit-full2` (later replaced by newer verdict runs) |
| `v2mit-headed1` (00:29–00:52Z) | C, headed | 31 passed, 3 failed (C4, C13a, C13b): **not a headed sign-off**. C4: the known headed race (`results.slice(0, 7)` not all `SUPERSEDED`). C13a/b: anti-aliasing differences on every baseline, also the unchanged QED64 panels (`test-results/*-diff.png`: edges and glyphs only); the macOS screen had been locked since 00:06:22Z (`ioreg` `CGSSessionScreenLockedTime`), inferred cause. **Superseded by the last-mile lane:** the cause is the window opening on the 2x display, not the lock (section above) |

`node scripts/ux-tally.mjs` after this lane (`$W/logs/v2mit-ux-tally.txt`): 112 run directories with a report, 51
`showcase.sh ux` records; VERDICT runs then included `v2mit-full1`, `v2mit-full2`.

## Final gate: storms on four pins, D gated while served, C re-chosen (2026-10-02)

**Storms** (`out/ux/final-storm/RESULTS.md`, new tool `tests/ux/tools/reload-storm-desktop.mjs`): 5 interleaved rounds
× 16 runs (A, C, D, B × chrome-headless-shell / headed Chrome for Testing × stock page / `/showcase/`) and one 18-run
headed round on a quiet host. All crashes: A 3/26 V2, C 2/26 V2, D 3/26 V2 (+1 V2 smoke run), B 3/20 V1. D removes V1
but not V2 and was not at least as clean as C, so **C `5ac5d00` stays served** (docs/REPIN-LOG.md "final gate").

Storm table (crashed / runs per arm; recomputed by `node scripts/ux-tally.mjs` "Final-gate interleaved reload storms",
`work/logs/docsfinal-ux-tally.txt`; per-run rows in `out/ux/final-storm/RESULTS.md`). hs = chrome-headless-shell 151,
hd = headed Chrome for Testing 151; stock = `/?snapshots=snapshots/widgets8`, sc = `/showcase/`:

| pin | hs stock | hs sc | hd stock | hd sc | quiet hd stock | quiet hd sc | total |
|---|---|---|---|---|---|---|---|
| A `1859b83` (0034, old worker) | 0/5 | 0/5 | 0/5 | 0/5 | 0/3 | **3/3** V2 | **3/26** V2 |
| C `5ac5d00` (0034, #52 worker; served) | **1/5** V2 | 0/5 | 0/5 | 0/5 | 0/3 | **1/3** V2 | **2/26** V2 |
| D `3b42714` (0035b, parking off) | **1/5** V2 | 0/5 | 0/5 | 0/5 | 0/3 | **2/3** V2 | **3/26** V2 (+1 smoke) |
| B `9fdf9b8` (0035, parked threads) | **1/5** V1 | **1/5** V1 | **1/5** V1 | 0/5 | – | – | **3/20** V1 |

Crashed runs: A q1/q2/q3-A-hd-sc; C r2-C-hs-st, q2-C-hd-sc; D r1-D-hs-st, q1-D-hd-sc, q3-D-hd-sc (smoke2-D-hd-st not in
the table); B r2-B-hs-st, r3-B-hs-sc, r2-B-hd-st. Every V2 was 1.7–2.15 s after reload 2, 3 or 4; every V1 after reload
0. The difference between C and D (and A) is one crash: not significant.

**Headed sign-off, in short:** `final-C-headed1` on the served pin and that lane's gallery `2081098d…` passed all 34 tests including C19
(`node scripts/lib/ux-record.mjs verdict …` → `HEADED SIGN-OFF (not a verdict)`; `showcase.sh gallery` names it in
`UX CURRENT`); on D, `final-D-headed2` did the same after `final-D-headed1`'s three root-caused headed-only causes below.

**New: a headed sign-off run.** `UX_HEADED_ALL=1` (`tests/ux/lib/qed64.mjs` `HEADED_ALL`, the Playwright project
`headed`) makes every `launch()` a real Chrome for Testing window and runs C19; `showcase.sh ux` records it with
`headed: true`, and `scripts/lib/ux-record.mjs` judges it as **HEADED SIGN-OFF** (every verdict check, nothing skipped),
never as a verdict, and leaves it out of the "later failures" note. Two headed-only differences, both root-caused in
`final-D-headed1`, are handled for headed runs only:
* **QED64 N3:** desktop Chrome requests `/favicon.ico` for a top-level page without an icon link; the stock page has
  none, so every headed stock-page load logs one `Failed to load resource … 404` (C6, C7, C15 and C14's aggregate).
  chrome-headless-shell never requests it. Allowed once per QED64 page load, headed only (`HEADED_ALLOWLIST`; unit
  check: headed favicon OK, other URL or twice per load FAIL, headless still FAIL).
* **Glyph rasterisation:** headed Chrome anti-aliases text differently from chrome-headless-shell; against the headless
  baselines C13a's hasse-view panel and C13b (390 px, 5,094 px = 2 %) failed with diffs on glyph edges only (layout
  identical; diff images viewed). Headed runs compare with their own baselines `tests/ux/__screenshots__/headed/`,
  written by `final-D-headed-c13base` (`--grep C13 --update-snapshots`, 3 passed) and viewed before use; the headless
  baselines are unchanged.
* The third `final-D-headed1` failure, **C4**, was a timing race in the test's premise, not a gallery fault: the storm's
  first click landed at 93 ms and the second at 399 ms (Playwright's headed click is slower), and graph-scope's switch
  finished in between, so the first selection settled `ok`, not `SUPERSEDED`. In `final-D-headed2` (82/358 ms) all 7
  were `SUPERSEDED`; in `final-C-headed1` too. Not changed (the assertion stays strict); a rare headed flake.

| Run | Pin / gallery | Result |
|---|---|---|
| `final-D-full1` (17:38–17:59Z) | **D `3b42714`**, `eab4f147…` | 33 passed, 1 skipped (C19): **VERDICT**. C10 no crash; C20 135/135, 0 stalls, QED64 liveness 0 probes / 0 rescues / 0 `wedged` reboots, pool max running 24 of 30, parked 0; C21 (a) ready 49.1 s after the click; C22 (3) settled `alive` via `qed64-answered`, main-loop probe 2/2, 0 restarts; C3 peak 9.76 GB |
| `final-D-full2` (17:59–18:20Z) | D, `eab4f147…` | 33 passed, 1 skipped: **VERDICT** (C20 135/135, C21 (a) 48.6 s, C22 (3) 0 restarts) |
| `final-D-headed1` (18:21–18:43Z) | D, headed | 27 passed, 7 failed (C4, C6, C7, C13a, C13b, C15, C14): NOT A HEADED SIGN-OFF; root causes above |
| `final-D-headed-c13base` | D, headed, `--grep C13 --update-snapshots` | 3 passed; headed baselines written and viewed |
| `final-D-headed2` (18:46–19:07Z) | D, headed | **34 passed (C19 included): HEADED SIGN-OFF**. C10 no crash, C20 135/135, C19 ready, panel equal |
| `final-C-full1` (19:29–19:50Z) | **C `5ac5d00`**, `2081098d…` (after `pin use 5ac5d00`) | 33 passed, 1 skipped (C19): **VERDICT**. C10 no crash; C20 135/135, 0 stalls, QED64 liveness 0 probes / 0 rescues / 0 `wedged` reboots; C21 (a) 48.7 s; C22 (3) `qed64-answered`, 0 restarts; C3 peak 9.14 GB |
| `final-C-full2` (19:50–20:11Z) | C, `2081098d…` | 33 passed, 1 skipped: **VERDICT** (C20 135/135, C21 (a) 48.9 s, C22 (3) 0 restarts, C3 peak 9.95 GB) |
| `final-C-headed1` (20:12–20:34Z) | C, headed | **34 passed (C19 included): HEADED SIGN-OFF** (C20 135/135) |
| `final-C-c20-1`, `-2`, `-3` | C, `--grep "C20 "` | 1 passed each (6.1–6.2 min): **135/135 each**, 0 stalls, 0 gallery wedges, QED64 rescues 0, `wedged` reboots 0 |

The suite changes of this lane (`HEADED_ALL`, the headed project and baselines, `HEADED_ALLOWLIST`, C19's skip
condition) do nothing without `UX_HEADED_ALL=1`; the D verdicts ran before `HEADED_ALLOWLIST` and the headed baseline
path existed, the C verdicts after.

## Hardening lane: capability card, accessibility, main-loop probe, deterministic late answers (2026-10-02)

**What changed in the shipped gallery** (gallery `2f95d07c…` → `2081098daa7c9d72…`, `__showcase.version` 8; details in
gallery/README.md):
* **Browser capability check before anything boots** (`lib.js` `checkCapabilities`): `crossOriginIsolated`,
  `SharedArrayBuffer`, WebAssembly Memory64 (QED64's own 13-byte probe plus a shared 64-bit memory) and, where exposed,
  `navigator.deviceMemory`. A missing one shows "This browser cannot run the Lean widget gallery" ("This showcase needs a
  Chromium-based desktop browser (Chrome, Edge, Brave, Arc) with ~8 GB free memory; your browser lacks X.") and nothing
  is fetched from QED64; under 8 GB reported memory a warning card offers "Try anyway". New UX test **C24**.
* **The veil leaves the accessibility tree once hidden** (`aria-hidden`, `inert`, `visibility: hidden` after the fade);
  **C17** now also checks that and the forward Tab order (no axe build in `node_modules`: DOM assertions).
* **Main-loop probe** (`$/showcase/liveness`, sent with every hover; the FileWorker main loop answers MethodNotFound
  without a pool thread): fixes pin A's C22 (3) false restart. **C22 (3)** asserts it.
* **Late hover answers are classified by elapsed time**, not by the 250 ms tick (sim run 12 tightened to 0.65 s against a
  0.6 s timeout; the 0.9 s margin is gone).
* **Layout fix found by C24's screenshot:** with the mobile bar `display: none`, auto-placement put `.layout` in the body
  grid's `auto` row, which reached the bottom only when the rail's content was taller than the window; the capability
  card (empty rail) sat in a 280 px stage and was clipped. `.layout` is now pinned to the `1fr` row (`grid-row: 3`); C13's
  16 baselines still match without re-approval, so no baseline was updated (the approval flow was not needed).
* The harness can test a STAGED pin served on another port: `UX_ORIGIN=<origin> UX_PIN=<id>` (global-setup checks
  `X-Showcase-Pin`; never a verdict).

Static gate: `CHECK-GALLERY OK 128 ok, 0 failed`, `SIM-GALLERY OK 101 ok` (`work/logs/harden-gallery-gate{1..4}.log`; the sim
4× in parallel under load: 4/4 OK, `harden-sim-rep{1..4}.log`). Scratch mutants (`harden-mutant-{A..D}.log`), each red:
A (no `main-loop` in proofOfLife) 3 FAIL in run 13; B (tick-order classification) 2 FAIL in run 12; C (capability env
not read) 5 FAIL in run 14; D (veil without aria-hidden/inert) 7 FAIL (runs 1, 2, 14).

| Run | Pin / args | Result |
|---|---|---|
| `harden-C-subset1` | C `5ac5d00`, `--grep "C8 \|C17\|C24 "` (gallery `894b9c51…`) | 2 passed, **C17 failed on the new test's own premise**: Chrome starts the next Tab after a blurred element (so the walk now starts by focusing the skip link), and the warm profile's kept buffer shows "Open my saved buffer" (now expected when visible). The veil checks passed. C24 passed; its screenshot showed the clipped card (layout fix above) |
| `harden-C-subset2` | `--grep "C13\|C17\|C24 "` | **REFUSED** (lock wait 3600 s timed out: other lanes held the lock; contention, not a result) |
| **`harden-C-full1`** | full suite, `scripts/showcase.sh ux`, pin C, gallery `2081098d…` (13:50–14:24Z) | **33 passed, 1 skipped (C19), 0 failed: VERDICT** (34 listed). C13a/b/c match the existing baselines; C17: veil `aria-hidden`/`inert`/`visibility: hidden`, nothing of it in `ariaSnapshot()`, Tab order skip link → Reset → Copy → open card → 4 hints → "Show all 10" → "Open my saved buffer" → editor, capability check ok (Chrome reports `deviceMemory` 32); C24 (a)–(c) as designed, stage fills the window, card not clipped, 0 runtime/snapshot requests before "Try anyway", 29 after; C21 (a) restart 40.4 s after the click (QED64 liveness took no action; the main-loop probes answered only by the restart's failInFlight: `main-synthetic`); **C22 (3) on C: QED64's own probe 14/14 answered, 0 stalls, 0 `wedged` reboots, settled `alive` via `qed64-answered`, main-loop probe 2/2 answered (526 ms): no disturbance of QED64's liveness**; C20 135/135, 0 stalls, QED64 liveness 0 probes; C10 no crash. Then `showcase.sh gallery` → `UX CURRENT … run harden-C-full1` (`harden-gallery-gate4.log`) |
| `harden-A-c21c22` | **A `1859b83`** served on :5196 (`SHOWCASE_PIN`), `UX_ORIGIN` + `UX_PIN=1859b83`, `--grep "C2[12] "` | **2 passed** (5.0 min; recorded, not a verdict: subset, other origin). C21 (a) restart 20.7 s after the click (A's timings; the two main-loop probes answered only by the restart's failInFlight: `main-synthetic`, not counted); C22 (2) 3/3 hovers answered; **C22 (3)**: 24 sleeping proofs, pool saturated (`unusedMin 0`, running 30), 8 probes, **main-loop 8/8 answered (0–493 ms), settled `alive` via `main-loop` 3×, 0 missed, 0 wedged, 0 restarts, same session**, card "Lean is still working". Before (`multipin-A-liveness`, old gallery): `wedged 2, restarts 1` |

## Docs lane: gallery polish and the verdict on that day's gallery (2026-10-02, pin C)

**What changed in the shipped gallery** (gallery `a4b34ead…` → `2f95d07c24cc76e0…`): the status line speaks plain
language ("HasseView is ready · opened in 1.4 s", "DistLens (edited): Lean is checking…"; the old technical line is its
tooltip and `__showcase.status().statusLine.detail`); the unexplained "phase 2" card badge is gone (and the "phase 1/2"
placeholder chip text); cursor hints say "draws a diagram" instead of SVG element counts (the counts stay in
`expectPanel.svgTagCounts`, still checked); the rail footer reads "QED64 5ac5d00 · Lean 4.34.0" and "snapshot
widgets8"; the bad-overlay card no longer cites "plan C7". `gallery.js`'s liveness, switching and boot logic is
unchanged. Static gate: `CHECK-GALLERY OK 123 ok`, `SIM-GALLERY OK 86 ok`; the new status-line assertion fails on a
mutant that prints the old line (`SIM-GALLERY FAIL 85 ok, 1 failed`). One gate run failed sim run 12 (late hover answers)
on a timing margin, fixed in the test (gallery/README.md "Static validation").

| Run | Args | Result |
|---|---|---|
| `docs-c13-update` | `--grep "C13a\|C13b" --update-snapshots` | 2 passed; **re-approved on purpose** `C13-gallery-{chart-kit,dist-lens,graph-scope,tree-scope}.png` (the cards' new hint text and the removed badge; the other 4 gallery, 8 panel and the 390 px baselines stayed within `maxDiffPixelRatio 0.01`). The new images were viewed |
| `docs-subset1` | `--grep "C1 \|C4 \|C5 \|C8 \|C13\|C17\|W2 \|W8 "` (the changed UI: status line, chips, cards, error card, visual baselines, keyboard) | **10 passed**, 0 failed (2.8 min), against the re-approved baselines |
| **`docs-full1`** | full suite, `scripts/showcase.sh ux` (09:51:17–10:11:55Z) | **32 passed, 1 skipped (C19), 0 failed, 0 flaky: VERDICT** (20.6 min, `expected 32 + skipped 1 == listed 33`); pin `5ac5d00 wasm64-4b025db7729c5f89` active and served from start to end; served gallery == local `2f95d07c…`; lock `6d2cbd20…`. C10 no crash (peak 12.7 GB); C20 135/135, 0 stalls, QED64 liveness 0 probes / 0 rescues / 0 `wedged` reboots, pool max running 20 of 32; C21 (a) the gallery's probe declared the wedge after 40.3 s without progress (`relay.restart`, QED64's liveness took no action), ready again 48.6 s after the click, (b) card after 16.2 s and an observe-mode wedge, capture taken; C22 (1)–(3) 0 restarts, (3) settled `alive` via `qed64-answered`; C23 one QED64 `wedged` reboot recorded post hoc. Then `showcase.sh gallery` → `UX CURRENT … run docs-full1` |

`node scripts/ux-tally.mjs` after the run: `work/logs/docs-ux-tally-final.txt`.


## Earlier lane summaries (as each lane wrote them; "the current pin" means that lane's pin)

**Re-pin (2026-10-01, after 20:35Z): every run below was on the previous pin** (QED64 `1859b830`, runtime
`wasm64-4b025db7729c5f89`). The showcase is now pinned to QED64 `9fdf9b8` / `wasm64-2c18773ecfba45bb`, QED64's L7 fix
(docs/REPIN-LOG.md), with new widget bakes, a gallery that defers its liveness probe to QED64's own (C21/C22 updated
accordingly) and the console allowlist pointed at the renamed bundle `index-Jv35CWTg.js`. The lock and the overlays
changed, so the close-out VERDICT below no longer describes the served tree (`showcase.sh gallery` prints `UX STALE`).
On the new pin, the full suite (`repin-full1`) gave 24 passed, 7 failed, 1 skipped, with C20 135/135 clean. C1, C2 and C22
were harness issues; they are fixed and pass with C21 in `repin-subset1`. C10, W4 and C21 (b) hit L9, a renderer V8 OOM
on a reload or relay restart that is new in QED64's 9fdf9b8 release (A/B on the stock page: 0/5 old vs 3/5 new). See
docs/REPIN-LOG.md §9 and docs/UPSTREAM-REPORT-QED64.md L9. The C20 hang hunt on the new pin (NEXT-STEPS §3) was done
by the final lane: 8 observe-mode runs, no hang (out/hang/FIELD-CAPTURE.md).

**Multiple pins, pin C `5ac5d00` served (2026-10-02 06:08–07:55Z; gallery `a4b34ead…`): see "Multiple pins" below.**
QED64 is now pinned by commit with several pins registered (A `1859b83`, B `9fdf9b8`, C `5ac5d00`; docs/REPIN-LOG.md);
C (QED64's interim main: the 0034 runtime with the #52 worker and its own liveness) is the active pin. Two full runs back
to back through `showcase.sh ux`, **`multipin-C-full2-b` and `multipin-C-full3-b`: 32 passed, 1 skipped (C19), 0 failed
each, both VERDICT**, with C10 (the reload storm) passing in both and C20 135/135 clean. The first full run on C,
`multipin-C-full1`, failed C12 (and C14, which aggregates it) on a new unexpected pageerror `Session disposed.`:
root-caused to QED64 defect N2 (the page's heap meter, every pin), allowlisted only where a session is disposed.

**Final verification on the 9fdf9b8 pin (2026-10-01 22:56Z – 2026-10-02): two full runs and a C20 hang hunt; see
"Final verification on the 9fdf9b8 pin" below.** `final-full1`: **31 passed, 1 skipped (C19), 0 failed, VERDICT**.
`final-full2`, started straight after it (the next lock window): **28 passed, 3 failed, 1 skipped, NOT A VERDICT**. All
three failures are one renderer crash each from QED64's L9 (C10, C21 (b), and C14, which aggregates them). The gallery
does not handle L9, so **the two-green gate is not met on this pin**. C20 was 135/135 clean in both runs, and QED64's
own liveness took no action (0 rescues, 0 stalls, 0 `wedged` reboots). The hang hunt is in `out/hang/FIELD-CAPTURE.md`.

**Close-out 3, after the last audit (2026-10-02 03:55–04:40Z; gallery `92027286…`): see "Close-out 3" below.** Proof of
life now counts only frames from Lean (QED64's JS layer synthesizes some frames that keep flowing during a freeze); the
post-hoc record of a QED64-handled L7 is exercised in the browser for the first time (new **C23**, a forced
`die(null, "wedged")` fixture), which found and fixed a harness bug that would have failed C20 on its first real
QED64-handled hang; `deploy-manifest.mjs` rejects unknown arguments. One full run, `closeout3-full1`: **30 passed,
2 failed, 1 skipped, NOT A VERDICT**: C10 crashed the renderer on its second reload (L9; C14 aggregates it); every other
test passed, including C20 135/135, C21, C22 (1)–(3) and C23. **The two-green gate stays unmet on this pin because of
L9** (C10 has now crashed in 6 of the 8 runs that ran it on that pin, 5 of 7 full runs; "Status and tallies").

**Close-out 2, after the final audit (2026-10-02 02:24–03:11Z; gallery `7772c1eb…`): see "Close-out 2" below.** The
liveness probe now accepts QED64's own probe answers and any server frame as proof of life, so a saturated task pool is
no longer restarted (new C22 (3), in the browser: 24 parallel sleeping proofs, pool `{unused 0}`, the hover unanswered,
settled `alive` via `qed64-answered`, 0 restarts); a 45 s card on a live checker reads "Lean is still working"; C21 (b)
runs in a fresh browser (no longer exposed to L9); C20 and W1–W8 accept a QED64 `wedged` reboot as an L7 occurrence
handled upstream, with a post-hoc record. One full run, `closeout2-full1`: **29 passed, 2 failed, 1 skipped, NOT A
VERDICT**. The failures are C10 (`page.reload: Page crashed`, an L9 renderer crash, EXC_BREAKPOINT on a DedicatedWorker
thread with 46 of them, `chrome-headless-shell-2026-10-01-230148.ips`) and C14, which aggregates it. **The two-green gate
stays unmet on this pin because of L9**; it is the owner's decision (wait for an upstream L9 fix, or roll back).

**Close-out (2026-10-01, 20:00–20:24Z): `closeout-full1`, the full suite through `scripts/showcase.sh ux` on the current
gallery (content sha256 `c8492b7078f49b56…`): 31 passed, 1 skipped (C19), 0 failed, 0 flaky in 18.0 min, recorded as a
VERDICT** (see the first Verdict row). It is the first full run with the liveness probe (C21 rewritten, C22 new), the
hang capture, the thumbnail and label checks, and the bring-up lane's shared console-oracle change (LSP tap in
`tests/ux/lib/lsp-tap.mjs`, `pairWith`). Everything below that names full6/full7 describes the gallery as of 09:23.

The pre-close-out evidence is the post-audit runs **full6** and **full7** (two full suites, back to back) and
**c20rep1–c20rep5** (five more C20-only runs straight after them). The earlier runs full1–full5 used the pre-audit
code. They are kept as history, and the figures quoted from them are labelled.

### Verdict table (history: written by the final-gate lane, 2026-10-02 ~20:35Z; not current state)

This table is a dated record. Its rows name the verdicts of their day; later galleries superseded them. The verdicts
that apply to the current gallery are printed by `scripts/showcase.sh gallery` and `scripts/showcase.sh pin list`
("Current state: run the tools", top of this file).

| Gate | Result | Evidence |
|---|---|---|
| **Two full runs on the served pin C `5ac5d00`, gallery `2081098d…` (final-gate lane, 2026-10-02; the verdict of that day)** | **pass: two consecutive VERDICTs.** `final-C-full1` (19:29–19:50Z) and `final-C-full2` (19:50–20:11Z): 33 passed, 1 skipped (C19), 0 failed, 0 flaky each, 34 listed; pin C served from start to end; C10 no crash; C20 135/135; C21 (a) 48.7 / 48.9 s; C22 (3) 0 restarts. Earlier on this gallery: `harden-C-full1` | `out/ux/final-C-full{1,2}/`, `work/logs/final-C-full{1,2}.log`, `out/ux/showcase-ux-runs.jsonl`; "Final gate" |
| **Headed sign-off on C, gallery `2081098d…` (final-gate lane, 2026-10-02)** | **pass**: `final-C-headed1` (20:12–20:34Z) 34 passed, C19 included, `HEADED SIGN-OFF (not a verdict)` | `out/ux/final-C-headed1/`, `work/logs/final-C-headed1.log`; "Final gate" |
| Two full runs on D `3b42714` while it was served (gallery `eab4f147…`) | pass: `final-D-full1`, `final-D-full2` VERDICT; headed sign-off `final-D-headed2` | "Final gate" |
| **Two full runs on pin C `5ac5d00` (gallery `a4b34ead…`, lock `6d2cbd20…`)** | **pass: two consecutive VERDICTs.** `multipin-C-full2-b` (06:44–07:32Z, waited 20 min for the browser lock) and `multipin-C-full3-b` (07:32–07:55Z): 32 passed, 1 skipped (C19), 0 failed, 0 flaky each (20.9 and 20.7 min); served gallery == local, and the server served pin `5ac5d00 wasm64-4b025db7729c5f89` from start to end (`servedPinStart/End`). C10 passed in both (no renderer crash; transient peak 10.2 and 11.8 GB); C20 135/135 in both; C21 (a) restart 40.8 / 40.6 s after the click (deferred to QED64's liveness); C22 (3) settled `alive` via `qed64-answered`, 0 restarts; C23 1 QED64 `wedged` reboot recorded post hoc. Before them: `multipin-C-full1` 30 passed, 2 failed (C12 N2, C14), and `multipin-C-full2` refused before any test (a QED64 snapshot bake of the owner's was running: rc 3, recorded, not a test result) | `out/ux/multipin-C-full{1,2-b,3-b}/`, `work/logs/multipin-C-full*.log`, `out/ux/showcase-ux-runs.jsonl` |
| **Close-out 3 full run on the 9fdf9b8 pin (gallery `92027286…`)** | **not a verdict (L9).** `closeout3-full1` 30 passed, **2 failed** (C10: L9 renderer crash at the second reload; C14 aggregates it), 1 skipped (C19), 20.4 min, 33 tests listed. C21 (a) restart 41.0 s / ready 49.3 s after the click; (b) observe wedge, synthetic capture, no crash; C22 (1)–(3), 0 restarts; **C23** QED64-handled `wedged` reboot recorded post hoc; C20 135/135; W1–W8 0 probes, 0 restarts | `work/logs/closeout3-ux-full1.log`; `out/ux/closeout3-full1/report.json`; `out/ux/showcase-ux-runs.jsonl` (run `closeout3-full1`). See "Close-out 3" |
| **Close-out 2 full run on the 9fdf9b8 pin (gallery `7772c1eb…`)** | **not a verdict (L9).** `closeout2-full1` 29 passed, **2 failed** (C10: L9 renderer crash; C14 aggregates it), 1 skipped (C19), 20.1 min. Every liveness test passed: C21 (a) restart 40.9 s after the click, (b) in a fresh browser, observe-mode wedge recorded, capture taken, no crash; C22 (1)–(3) including the saturated pool, 0 restarts; C20 135/135; W1–W8 0 probes, 0 restarts | `work/logs/closeout2-ux-full1.log`; `out/ux/closeout2-full1/report.json`; `out/ux/showcase-ux-runs.jsonl` (run `closeout2-full1`); `work/logs/closeout2-report-matrix.md`. See "Close-out 2" |
| **Two full runs on the 9fdf9b8 pin (final lane)** | **not met.** `final-full1` 31 passed, 1 skipped, **VERDICT**. `final-full2` 28 passed, **3 failed** (C10, C21, C14), 1 skipped: each failure is an L9 renderer crash, which the gallery cannot prevent or recover from | `work/logs/final-ux-full1.log`, `final-ux-full2.log`; `out/ux/final-full{1,2}/report.json`; `out/ux/showcase-ux-runs.jsonl` (runs `final-full1`, `final-full2`); crash reports `chrome-headless-shell-2026-10-01-{200357,201310}.ips`. See "Final verification on the 9fdf9b8 pin" |
| **Close-out full run (previous pin `wasm64-4b025db7…`, gallery `c8492b70…`)** | **pass, VERDICT**: `closeout-full1` 31 passed, 1 skipped (C19), 0 failed, 0 flaky, 18.0 min; `expected 31 + skipped 1 == listed 32`; served gallery == local `c8492b70…` from start to end; lock `ddf1a234…`, overlays widgets7/widgets8 unchanged. C20 135/135, 0 stalls, 0 liveness wedges or restarts; W1–W8: probe armed, 0 probes needed, 0 restarts; C21 auto restart 20.6 s after the click (ready 28.9 s); C22 3/3 probes answered (≤ 2 ms) during a 38 s silent `#eval`, not restarted; C1 8/8 thumbnails loaded (naturalWidth 480); C14 31 tests / 39 sessions, 0 unexpected | `work/logs/closeout-ux-full-1.log` (`31 passed`, `… VERDICT`); `out/ux/closeout-full1/report.json`; `out/ux/showcase-ux-runs.jsonl` (run `closeout-full1`); `scripts/showcase.sh gallery` → `UX CURRENT` |
| Every test green in two full runs, back to back | **pass**. `full6` (12:50:35–13:06:56Z) and `full7` (13:06:56–13:23:28Z) each gave **30 passed, 1 skipped, 0 failed, 0 flaky** in 16.3 and 16.5 min. The skip is C19, the optional headed run | `work/logs/gates.log` (`full6 end … rc=0`, `full7 end … rc=0`); `work/logs/ux-full6.log`, `ux-full7.log` (`30 passed`); `out/ux/full6/report.json`, `out/ux/full7/report.json` (`"expected":30,"skipped":1,"unexpected":0,"flaky":0`) |
| C20: 135/135 clean | **pass in all 7 post-audit C20 runs** (full6, full7, c20rep1–5): 135/135 each, **0 stalls** in 945 link clicks | `out/ux/<run>/tests/C20.json` (`"clean": 135`, `"stalls": 0`); see "C20 stability and the hang rate" |
| The audit's hang (QED64 L7) | A genuine QED64 runtime freeze (L7 below, rewritten at close-out from the second verification pass). **On the current pin (9fdf9b8)** QED64 handles a real L7 itself (a 1 s mailbox kick; its Lean-side liveness reboots a wedged session about 22–25 s after its last frame), and the gallery **defers**: its **liveness probe** starts after 30 s of silence, so on a freeze QED64 does not see it restarts the runtime by itself **about 41 s after the click, ready again about 49 s after it** (C21 (a): 40.9 s / 49.0 s in `closeout2-full1`), keeping the text. (On the previous pin, without QED64's liveness, the probe started after 10 s: restart about 20 s after the last progress, ready about 29 s.) the 45 s **stall card** (Restart Lean, Reset example, Keep waiting) is the fallback; **observe mode** + the harness's **hang capture** record a real one. **C21** proves the automatic restart and, in observe mode, the capture and the card on a deterministically frozen checker; **C22** proves a slow, silent elaboration is not restarted | `out/ux/closeout-full1/tests/C21.json`, `C22.json`; `out/ux/closeout-c21c22-3/`; `out/hang/captures/closeout-full1-2026-10-01T20-17-06-824Z.json` (synthetic) |
| Card claims the user cannot see (audit major) | **fixed**. 0 hidden claims among the 79 quoted texts checked per run in W1–W8, and the W tests now **assert** this | `out/ux/full6/tests/W*.json` and `out/ux/full7/tests/W*.json` (`hiddenCardClaims: []`, `cardClaimsChecked` 8/9/16/11/10/8/8/9) |
| C19 headed sign-off (optional) | passed before the audit (`out/ux/headed2`); superseded by the full headed sign-offs `final-D-headed2` and `final-C-headed1` (final-gate lane, rows above) | `work/logs/ux-headed2.log` |
| Bring-up card-hint check with rendered text only | `HINTS OK 71/71` | `work/logs/ux-hints-uxaudit.log` |
| `?mem` run | not run, as the bring-up lane recommended. C3 again shows heap `currentBytes` 2147483648 at ready and after all 8 widgets | `out/ux/full6/tests/C3.json` |
| QED64 untouched by this lane | no write by this lane. The stamp check reports `CHANGED` because **other sessions** are writing in `wasm64-lean-fable/qed64/work/` and `wasm64-lean4game` at the same time (see the hygiene section) | `work/logs/ux-untouched-final.log` |

## Multiple pins: pin C `5ac5d00` (2026-10-02, gallery `a4b34ead…`)

Gallery content sha256 `a4b34ead305b5f9bf5450e919612f4f375e09cc19ccf3f6b89eff188673bf23f` (the late-answer proof of
life is in it; `gallery/pin.json` names pin `5ac5d00`), lock `6d2cbd20…` (`pins/5ac5d00/QED64.lock.json`), overlays the
runtime `wasm64-4b025db7729c5f89` ones (`widgets.3619cfd5…`, `widgets.0880fd91…`). Logs `work/logs/multipin-*`.

**What changed in the suite.** The suite is pin-agnostic: the console allowlist names the QED64 bundle as
`"@qed64-main-bundle"` (resolved per pin), the liveness tests branch on the active pin's descriptor
(`PIN.liveness.builtIn`) and require the gallery's detection to agree (C21 (a) deferral 30 s and restart about 40 s
with QED64's liveness, 10 s and about 20 s without; C23 on a pin without it checks that there is none), and the global
setup refuses a server whose `X-Showcase-Pin` is not the active pin.

**Gate results on C.**

| Gate | Result |
|---|---|
| Reload storm on the stock page (`tests/ux/tools/reload-storm.mjs`, C served on :5196 with `SHOWCASE_PIN`), at least 5 runs, 0 crashes | **6/6 no crash**, 0 `V8 javascript OOM` lines, no new crash report; pool at ready `{unused 14, running 10, parked -1}` in all 6; ready 6.1–8.0 s after the storm. Positive control on B the same hour: 0/3 crashed (pool `{running 18–20, parked 8}`), so the storm alone did not separate the arms that hour (docs/UPSTREAM-REPORT-QED64.md L9) |
| Headless controls on C | `CONTROLS PASS` (11/11) on the second attempt; the first exposed the stage1-link mount bug (docs/REPIN-LOG.md 2026-10-02 §6), fixed in our repo |
| Two consecutive VERDICT full runs | **`multipin-C-full2-b`, `multipin-C-full3-b`: VERDICT, VERDICT** (Verdict table) |
| C20 at least 3 clean runs | 135/135 in each of the three full runs (`multipin-C-full1`, `-full2-b`, `-full3-b`; QED64 liveness 0 probes, 0 rescues, 0 stalls, 0 `wedged` reboots; pool max running 21–24 of 30, parked 0); and in each of the three C20-only runs `multipin-C-c20-{1,2,3}` (6.1 min each, the same zeros): **6/6 clean** |
| Pin switching, with one gallery boot each way | C1 cold boot passed on A (r1), C (r2, r4, r6) and B (r5); r3's boot on A was refused by the lock preflight (another session's Chrome running), contention not a result (docs/REPIN-LOG.md "Switch rehearsal") |
| The liveness tests on the fallback A (`multipin-A-liveness`, `--grep "C2[123] "`) | C21 passed with A's timings (restart 20.4 s after the click, no QED64 liveness), C23 passed its no-liveness branch; **C22 (3) failed**: on a page without QED64's liveness a pool saturated for 55 s gives no frame and no late answer within the 2 × 5 s sequence, and the gallery restarted a healthy session (`wedged 2, restarts 1`). A remains a working fallback without a verdict (docs/REPIN-LOG.md) |

**The failure, root-caused (`multipin-C-full1`).** C12's stock session with the overlay index cut off logged a pageerror
`Error: Session disposed.` at the third failed boot (the crash breaker tripping): stack `….dispose ← ….dispose ←
….onDied ← ….boot` in `/assets/index-BvT6MV1R.js`. The session's `dispose()` rejects every pending request; the only
request QED64 does not await is the page's heap meter (`frontend/src/main.ts` `startMemoryMeter`: every 12 s,
`void Promise.race([session.request("telemetry", {}), timeout 800 ms]).then(…)` with no rejection handler), so a
disposal inside that 800 ms window leaves an unhandled rejection. The code is in all three pins' bundles; it was seen
once in 18 recorded C12 stock runs. Reported as **N2** (docs/UPSTREAM-REPORT-QED64.md). The allowlist accepts exactly
that pageerror, with a stack through `.dispose (`, only in the scenarios in which a session is disposed (`bootFailure`,
`crashBreakerTripped`, `relayRestartOrReboot`, `stallRestart`, `qed64WedgedReboot`); the classifier was checked to
still reject it outside those scenarios and with another stack. It did not recur in the two verdict runs.

## Close-out 3: the last audit's findings (2026-10-02, gallery `92027286…`)

Gallery content sha256 `92027286640ca6ed5be5a083ba5ca8269224415ec70e7ebc574d83ae90a379fe`, lock and overlays unchanged
since the re-pin. Logs `work/logs/closeout3-*.log`; pre-edit copies in `work/closeout3-backup/`.

**What changed.**
* **Only frames from Lean are proof of life (audit minor).** QED64's JS layer, which stays alive during an L7 freeze,
  makes some frames itself: the front door's -32801 replies to completions on an import line
  (`vendor/qed64/public/workers/lsp-front-door.js:288`), the relay's -32603 halted replies (`frontend/src/lsp-relay.ts:112`)
  and `failInFlight`'s -32603 / -32900 replies (`lsp-relay.ts:212`), all with a message starting `QED64:`, and the
  halted note (`publishDiagnostics` with every diagnostic's source `QED64`). `gallery.js` `qed64Synthetic()` excludes
  them from proof of life **and from progress** (a synthesized `publishDiagnostics` used to count as elaboration
  progress), counts them (`status().liveness.syntheticFrames`), and a probe answered that way is not an answer (event
  `synthetic-reply`, `syntheticReplies`). API v7. `sim-gallery.mjs` run 11 freezes a page without QED64 liveness (the
  rollback page) while those frames keep arriving and requires the restart: `SIM-GALLERY OK 84 ok`. Mutant E (filter
  removed, `work/closeout3-mutE`) fails it: `sim timeout: run11 restart`, `syntheticFrames 92`, `sent 0`
  (`work/logs/closeout3-sim-mutE.log`). In the browser C21 (a)'s event sequence now reads `probe, missed, probe, missed,
  wedged, synthetic-reply, synthetic-reply, cleared`: the two post-wedge replies that close-out 2 counted as `late` were
  the relay's `failInFlight` answers to the outstanding probes, not Lean.
* **The post-hoc record of a QED64-handled L7, in the browser (audit minor).** New **C23** (`25-stall.spec.mjs`): inside
  QED64's own `lean.worker.js` it runs what `livenessStep` runs when its detector decides "dead" (`livenessLog`, then
  `die(null, "wedged", …)`) 0.8 s after HasseView's first declared click; everything downstream is real. Labelled
  synthetic (`window.__uxFixture`). It asserts the gallery's `qed64-wedged` / `qed64-rebooted` events, notice and
  counters, 0 gallery restarts and no card, the relay's 1 death / 1 reboot / 0 user restarts, the post-click text clean
  on the new session, and the record's contents. **It found a harness bug:** `clickLink` required 0 worker deaths per
  click, so the accepted `wedged` death marked the link failed with the misleading error "0 errors / 0 warnings after
  the click" (`closeout3-c21c22c23`: C23 `click.ok false`); C20 would have failed on its first real QED64-handled hang.
  `clickLink` now allows exactly one death per `wedged` reboot the gallery saw during the click and names any other
  death. The same run also corrected a premise of the new test: QED64 clears `status().lastDeath` once the new session
  serves, so the death's reason is read from the gallery's `lastReboot`, sampled while the relay was `rebooting`.
  `closeout3-c23b`: 1 passed (20 s). FIELD-CAPTURE.md now says plainly that the hunt cannot produce a pre-recovery
  capture on this pin and why (no page option: the bundle reads only `?profiles`, `?runtime`, `?snapshots`).
* **Docs (audit minor).** The current-pin recovery timing comes first everywhere (30 s deferral, restart about 41 s,
  ready about 49 s); the 10 s / about 20 s numbers are labelled as the previous pin. This file's intro names the pin.
* **`deploy-manifest.mjs` arguments (audit minor).** `--help` / `-h` print the usage; an unknown argument, a value flag
  without its value, or two modes print it and exit 2 before anything is read or written. Before and after the 10 cases
  in `work/logs/closeout3-deploy-args.log`, `out/deploy` mtimes and `manifest.json` sha256 were unchanged.

**Targeted runs.** `closeout3-c21c22c23` (`work/logs/closeout3-c21c22c23.log`): C21 and C22 passed (2.9 m, 2.8 m); C23
failed on the two defects above. `closeout3-c23b`: C23 passed.

**Full run `closeout3-full1`** (`SHOWCASE_LANE=closeout3 UX_RUN=closeout3-full1 scripts/showcase.sh ux`, tests
04:15:20–04:35:42Z, `work/logs/closeout3-ux-full1.log`): **30 passed, 2 failed, 1 skipped (C19), 20.4 min, NOT A
VERDICT** (`expected 30 + skipped 1 != listed 33`), on gallery `92027286…`, served == local.
* **C10, L9.** `Error: page.reload: Page crashed` at the second reload, 3.0 s after the first (11.1 s in all). Crash report
  `~/Library/Logs/DiagnosticReports/chrome-headless-shell-2026-10-01-181551.ips`, written 00:32:18 EDT on 10-02 (=
  04:32:18Z, 11 s after C10 started; the name and its internal `captureTime` carry a skewed 2026-10-01 18:15 -0400):
  EXC_BREAKPOINT / SIGTRAP, faulting thread "DedicatedWorker thread", 44 of 71 threads DedicatedWorker: the L9
  signature. C14 fails only on that session's `CRASHED`.
* **L9 tally on 9fdf9b8 (runs that ran C10):** C10 crashed in **6 of 8** (`repin-full1`, `repin-crash1` (W4 + C10
  only), `final-full2`, `closeout2-full1`, the last audit's `audit-cl3-full1` (log `work/logs/audit-final-full1.log`),
  `closeout3-full1`; passed `final-full1` and the final audit's `audit-final-full`): 5 of 7 full runs.
* **Liveness.** C21 (a): `relay.restart` 41.0 s after the click, ready 49.3 s, events `probe, missed, probe, missed,
  wedged, synthetic-reply, synthetic-reply, cleared`, QED64 rebooted nothing. C21 (b), in its own browser: card after
  16.2 s worded "stopped", observe-mode wedge 40.3 s after the last progress (`observed`, 0 restarts), synthetic capture
  `out/hang/captures/closeout3-full1-2026-10-02T04-26-54-732Z.json`. C22 (2): 1 probe answered in 2 ms, ready 39.4 s;
  (3): pool saturated (unused 0, running ≤ 30), 2 gallery probes (1 answered, 1 `alive` via `qed64-answered`), QED64
  14/14 probes answered, 0 restarts, one card worded "Lean is still working". **C23**: 1 QED64 `wedged` reboot (s1 → s2,
  `lastDeath {reason: wedged}`), the click clean on s2 in 9.0 s, 0 gallery wedges or restarts, no card, record
  `out/hang/captures/closeout3-full1-2026-10-02T04-30-56-052Z-qed64-wedged.json` (`postHoc`, `synthetic`, the
  `[liveness] [fixture]` line). W1–W8: 0 probes, 0 wedges, 0 restarts, 0 deaths, 0 reboots.
* **C20** 135/135 in 6.1 min, 0 stalls, 0 wedges, QED64 probes/rescues/stalls/`wedged` reboots 0/0/0/0, pool max running
  30 / total 32 / parked 8. The suite's only `[liveness]` line is C23's fixture; the mailbox boot line appears in 38
  sessions.
* **Gates afterwards.** `showcase.sh gallery` rc 0: `BUILD-GALLERY CHECK OK 8 examples`, `SIM-GALLERY OK 84 ok`,
  `CHECK-GALLERY OK 123 ok`, `gallery gate GREEN on … 92027286…`, `UX STALE: no verdict run on this gallery + lock +
  overlays` (truthful). `showcase.sh verify` rc 0 (`VERIFY: all checks OK`, the known Docker DRIFT #7).
  `deploy-manifest` generate `DEPLOY-MANIFEST OK 75 assets, 93 R2 objects; gallery 92027286…`, `--check`
  `DEPLOY-MANIFEST CHECK OK` with `G1 … CHECK-GALLERY OK 123 ok` and `info G2 UX: NO verdict …`. Worker tests 22/22.

## Close-out 2: the final audit's findings (2026-10-02, gallery `7772c1eb…`)

Gallery content sha256 `7772c1eb7000720216fd12f8dbca59b64a7abb5c4e4bc766847f77fc7346a047`, lock `bb97785a…`, overlays
widgets7/widgets8 unchanged since the re-pin. Logs `work/logs/closeout2-*.log`.

**What changed.**
* **Proof of life besides the hover (audit major).** `gallery/gallery.js` `proofOfLife`: a timed-out probe is a miss only
  if, since the first probe of the sequence, the page saw no server frame at all and (on a page with QED64's liveness)
  QED64's own probe was not answered in the 10 s before that first probe or since. Otherwise it is settled `alive`
  (event `alive`, `via`), no miss. API v6 (`status().liveness.frames`, `alive`, `aliveVia`, `qed64.lastAnsweredAgoMs`).
* **The card's wording (audit minor).** With a sign of life in the last 20 s of this version, the 45 s card reads "Lean is
  still working" (`status().stall.variant` `alive`), and it re-words itself if that changes.
* **C21 (b) in a fresh browser (audit minor)**, so it is not a second runtime boot in one renderer (L9).
* **QED64-handled L7 (audit minor).** C20 and W1–W8 accept a QED64 `wedged` reboot (one `wedged` death plus its reboot
  each), print it, and write a post-hoc record (`captureQed64Reboot`); console scenario `qed64WedgedReboot`
  (check-gallery 8c unit test). None occurred.
* **Deploy (audit minor).** `out/deploy` regenerated on this gallery and pin; G2 names later red full runs
  (`laterFailures`), and the release preflight refuses such a line (`scripts/lib/deploy-common.sh`).

**Targeted browser runs.**
* `closeout2-c21c22` (02:24–02:31Z): C21 passed (2.9 min). C22 failed on two test defects, both fixed: Mathlib's
  `unusedTactic` linter warns on each `sleep` (24 warnings; the test now silences it per theorem, as a user would), and
  the card was briefly re-worded "stopped" when progress arrived while it was up (the wording rule now counts progress
  as life and ignores signs from before the edit). Its liveness numbers were already right: 2 probes, 1 answered,
  1 `alive` via `qed64-answered`, 0 missed, 0 restarts, same session.
* `closeout2-c22b` (02:34–02:37Z): **C22 passed** (2.8 min). (3): pool saturated (`unused` 0, running up to 30), edit to
  ready 111.7 s (two waves of sleeping proofs), max silence 54.6 s, gallery probes 2 (1 answered in 1 ms, 1 settled
  `alive` via `qed64-answered`, its hover answered late), QED64 probes 14/14 answered, 0 stalls, 0 wedges, 0 restarts,
  same session, 0 errors / 0 warnings; the card was shown once, worded "Lean is still working"
  (`out/ux/closeout2-c22b/screens/C22-still-working-card.png`, viewed).
* **Mutants in the browser** (scratch galleries on :5198/:5199 via `GALLERY_DIR`, `UX_ORIGIN`, 02:37–02:45Z; `work/closeout2-mut{C,D}`):
  mutant D (`proofOfLife` returns null, the pre-audit rule) → C22 **failed**: (3) `wedged` 2, `restarts` 1, session
  changed, "every gallery probe answered or settled alive … Expected: >= 4, Received: 1", plus the restart's
  unallowlisted console errors (`work/logs/closeout2-mutD.log`). Mutant C (the observe branch disabled) → C21 **failed**
  in (b): `action` `relay.restart` instead of `observed` (`work/logs/closeout2-mutC.log`); the final audit could not catch
  this mutant in the browser because (b) crashed first (L9).
* Simulator: `SIM-GALLERY OK 80 ok` (run 10: saturated pool settled `alive` via `qed64-answered` and via `frame`, both card
  wordings and the re-wording, the fallback restart once QED64's answers stop); the two sim mutants (proof of life off;
  wording fixed to "stopped") fail it.

**Full run `closeout2-full1`** (`SHOWCASE_LANE=closeout2 UX_RUN=closeout2-full1 scripts/showcase.sh ux`, tests
02:45:06–03:05:14Z, 20.1 min): `2 failed`, `1 skipped`, `29 passed (20.1m)`, `[showcase] UX rc=1 on gallery
7772c1eb… : NOT A VERDICT: rc 1; 2 unexpected; expected 29 + skipped 1 != listed 32`.

| ID | Test | closeout2-full1 result | closeout2-full1 time |
|---|---|---|---|
| C1 | cold boot: fresh profile (empty OPFS and HTTP cache) to ready, phase timeline, bytes per prefix | pass | 13.5 s |
| C2 | warm boot: persistent profile, 0 .snapz bytes, only revalidations | pass | 7.0 s |
| C3 | memory + L-switch lane + C16: one boot, all 8 widgets by card clicks, RSS and wasm heap, no collision offer | pass | 19.8 s |
| C4 | switching through the UI: 8 sequential card clicks, then a storm of 8 card clicks in 2 s | pass | 19.7 s |
| W1 | ChartKit: declared cursors, clicks, selections, hovers, code actions in the real InfoView | pass | 10.7 s |
| W2 | HasseView: declared cursors, clicks, selections, hovers, code actions in the real InfoView | pass | 23.7 s |
| W3 | Interval Inspector: declared cursors, clicks, selections, hovers, code actions in the real InfoView | pass | 17.8 s |
| W4 | Simp Lens: declared cursors, clicks, selections, hovers, code actions in the real InfoView | pass | 33.1 s |
| W5 | Expr X-Ray: declared cursors, clicks, selections, hovers, code actions in the real InfoView | pass | 14.6 s |
| W6 | TreeScope: declared cursors, clicks, selections, hovers, code actions in the real InfoView | pass | 11.2 s |
| W7 | GraphScope: declared cursors, clicks, selections, hovers, code actions in the real InfoView | pass | 19.0 s |
| W8 | DistLens: declared cursors, clicks, selections, hovers, code actions in the real InfoView | pass | 21.8 s |
| C20 | click-all in the browser: all 135 rendered links, each from a freshly reset example | pass | 368.6 s |
| C21 | stall handling (QED64 L7) on a frozen checker: the liveness probe restarts it by itself; observe mode records it, the hang capture runs, and the card still works | pass | 175.9 s |
| C22 | liveness probe, negative: a legitimately slow elaboration (the slowest DistLens click; a ~38 s silent #eval; a saturated task pool) is never restarted | pass | 164.9 s |
| C5 | edit, break, fix: a typo gives an error and the panel degrades without a page error; the fix brings the same panel back | pass | 13.8 s |
| C6 | refused header (stock page): import HasseView without Mathlib is refused, missing [HasseView], no widening; the gallery never emits it | pass | 11.2 s |
| C7 | unknown module (stock page): import Mathlib.NotAModule is refused with the stock diagnostic | pass | 14.6 s |
| C8 | bad overlay: the stock page shows its boot-failure card; the gallery refuses before navigation with a friendly card | pass | 14.9 s |
| C9 | unpaired fixture (temp overlay with an altered runtime): the gallery refuses; the stock page fails its boot | pass | 14.2 s |
| C10 | reload storm: 5 reloads in 15 s, then ready with the right panel; no crash; workers released on pagehide | **failed: `page.reload: Page crashed` (L9)** | 11.2 s |
| C11 | network cut mid-.snapz (serve.mjs CHAOS on our own :5191 server): a single cut is absorbed; a lasting cut is surfaced and a reload recovers | pass | 47.5 s |
| C12 | offline warm reload: snapshots come from the warm profile (no .snapz download); a cut-off overlay index is a QED64 limitation the gallery reports | pass | 31.0 s |
| C13a | visual baselines: 8 widget panels and the gallery at 1440x900 (light) | pass | 24.7 s |
| C13b | visual baseline: the gallery at 390x844 (mobile emulation, stacked page) | pass | 15.3 s |
| C13c | dark scheme (evidence, no baseline): gallery chrome follows prefers-color-scheme, the QED64 InfoView stays light | pass | 8.3 s |
| C15 | stock regression: the page’s own EXAMPLES.mathlib text on the widgets8 superset is ready with 0 errors | pass | 14.3 s |
| C16 | forced collision: a name the covered superset already declares gets the stock note and offer; “Load exact imports” degrades gracefully | pass | 32.5 s |
| C17 | gallery accessibility: keyboard-only walkthrough, roles, names, iframe title | pass | 10.2 s |
| C18 | two tabs at once (record only): renderer RSS with two QED64 sessions | pass | 17.0 s |
| C19 | headed Chrome-for-Testing sign-off (optional; UX_HEADED=1) | skipped | 0.0 s |
| C14 | console hygiene across the suite: 0 unexpected page errors / console errors, 0 crashes, per-load limits held | **failed: aggregates the C10 crash** | 0.0 s |

(`node tests/ux/tools/report.mjs closeout2-full1`, saved as `work/logs/closeout2-report-matrix.md`.)

* **C10, L9.** The second reload crashed the renderer (`Error: page.reload: Page crashed`, 11.2 s). Crash report
  `chrome-headless-shell-2026-10-01-230148.ips` (23:01:48 EDT = 03:01:48Z): EXC_BREAKPOINT / SIGTRAP, faulting thread
  "DedicatedWorker thread", 46 DedicatedWorker threads: the L9 signature. C14 fails only on that session's `CRASHED`.
* **L9 tally on 9fdf9b8 (runs that ran C10; `repin-crash1` ran only W4 and C10):** C10 crashed in 4 of 6
  (`repin-full1`, `repin-crash1`, `final-full2`, `closeout2-full1`; passed `final-full1` and the audit's `audit-final-full`); C21 (b) crashed in 3 of the 5 runs where it
  shared a renderer with (a) and in none of the 3 runs since it gets its own browser (`closeout2-c21c22`,
  `closeout2-full1`, and mutant C, which failed on its assertion, not a crash); W4 in 1 of 6 runs.
* **Liveness.** C21 (a): `relay.restart` 40.9 s after the click (events probe, missed, probe, missed, wedged, late, late,
  cleared), ready 49.0 s, QED64 rebooted nothing. C21 (b): card after 16.2 s worded "stopped", observe-mode wedge recorded
  40.3 s after the last progress (action `observed`, 0 restarts), synthetic capture
  `out/hang/captures/closeout2-full1-2026-10-02T02-56-44-388Z.json` (telemetry answered, raw kick and `checkMailbox()`
  not resumed), Keep waiting brought the card back after 15.2 s, Reset recovered in 8.4 s. C22 (2): 1 probe answered,
  ready 38.8 s; (3): the same as `closeout2-c22b` (1 `alive` via `qed64-answered`, 15/15 QED64 probes answered,
  0 restarts, the card "Lean is still working"). W1–W8: 0 probes, 0 wedges, 0 restarts, 0 deaths, 0 reboots.
* **C20** 135/135, 270 edits, 0 stalls, 0 wedges, QED64 rescues/stalls/`wedged` reboots 0/0/0, 0 `[liveness]` lines,
  pool max running 28 / total 30 / parked 8 (hunt row in `out/hang/FIELD-CAPTURE.md`).
* **Gates afterwards.** `showcase.sh gallery` rc 0: `CHECK-GALLERY OK 123 ok`, `SIM-GALLERY OK 80 ok`, `BUILD-GALLERY CHECK
  OK 8 examples`, `gallery gate GREEN on … 7772c1eb…`, `UX STALE: no verdict run on this gallery + lock + overlays`
  (truthful: the only full run on it is red). `showcase.sh verify` rc 0 (`VERIFY: all checks OK`, the known Docker DRIFT
  #7). `deploy-manifest` generate `DEPLOY-MANIFEST OK 75 assets, 93 R2 objects; gallery 7772c1eb…`, `--check`
  `DEPLOY-MANIFEST CHECK OK`, `info G2 UX: NO verdict …` (`work/logs/closeout2-deploy-{generate,check}.log`).

## Final verification on the 9fdf9b8 pin (final lane, 2026-10-01/02)

**What was tested.** QED64 `9fdf9b85` / runtime `wasm64-2c18773ecfba45bb` / kernel `3ae65d36f9`. Gallery content sha256
`7bbddf2e750c0fa2…`, served unchanged from start to end of both runs. Lock `bb97785a4b243ca0…`. Overlay indexes widgets7
`eadb095d…` and widgets8 `5d91f179…`. These are the `out/ux/showcase-ux-runs.jsonl` records of `final-full1` and
`final-full2`. Both runs went through `SHOWCASE_LANE=final UX_RUN=<run> scripts/showcase.sh ux`, which is `npm run
test:ux` under `with-browser-lock.sh` plus the run record.

One change was made to the test sources before either run started: C20 now also records QED64's own liveness as the
gallery sees it (`status().liveness.qed64`: totals of probes, answered, stalls, resumed and rescues, plus
`wedgedReboots`), the document versions per package, and the pool maxima (`qed64Liveness`, `docVersions`, `poolMax`).
These fields are record only, and no assertion changed. The pre-change copy is in
`work/final-lane-backup/20-click-all.spec.mjs.orig`.

**Windows.** `final-full1`: its lock wait ran 22:56:50–23:18:24Z while another session's `lean4game` run held the lock,
and its tests ran 23:18:25–23:36:49Z (18.4 min). `final-full2` started as soon as `final-full1` ended (23:36:54Z).
Another session took the lock in that gap, so its tests ran 23:53:07Z – 2026-10-02 00:16:35Z (23.5 min, including
C21's 7.9 min wait after the crash). "Back to back" therefore means "consecutive lock windows of this lane".

| ID | final-full1 | time | final-full2 | time |
|---|---|---|---|---|
| C1 cold boot | pass | 13.8 s | pass | 14.0 s |
| C2 warm boot | pass | 7.4 s | pass | 7.3 s |
| C3 memory, 8 widgets by card clicks | pass | 19.3 s | pass | 19.2 s |
| C4 switching through the UI | pass | 20.2 s | pass | 19.8 s |
| W1 ChartKit | pass | 10.9 s | pass | 10.9 s |
| W2 HasseView | pass | 23.7 s | pass | 24.0 s |
| W3 Interval Inspector | pass | 17.7 s | pass | 17.8 s |
| W4 Simp Lens | pass | 32.8 s | pass | 32.4 s |
| W5 Expr X-Ray | pass | 14.6 s | pass | 14.8 s |
| W6 TreeScope | pass | 11.2 s | pass | 11.2 s |
| W7 GraphScope | pass | 19.4 s | pass | 19.3 s |
| W8 DistLens | pass | 21.9 s | pass | 22.1 s |
| C20 click-all, 135 links | pass | 368.6 s | pass | 371.4 s |
| C21 frozen checker: auto restart; observe + capture + card | pass | 164.8 s | **failed: L9 crash in (b)** | 471.2 s |
| C22 slow elaboration not restarted | pass | 53.3 s | pass | 53.4 s |
| C5 edit, break, fix | pass | 14.2 s | pass | 13.9 s |
| C6 refused header (stock) | pass | 11.1 s | pass | 11.2 s |
| C7 unknown module (stock) | pass | 14.9 s | pass | 15.0 s |
| C8 bad overlay | pass | 14.9 s | pass | 15.1 s |
| C9 unpaired fixture | pass | 14.4 s | pass | 14.4 s |
| C10 reload storm | pass | 28.7 s | **failed: L9 crash (`page.reload: Page crashed`)** | 11.3 s |
| C11 network cut | pass | 48.0 s | pass | 48.5 s |
| C12 offline warm reload | pass | 31.8 s | pass | 31.5 s |
| C13a visual baselines | pass | 24.8 s | pass | 24.5 s |
| C13b mobile baseline | pass | 15.4 s | pass | 15.4 s |
| C13c dark scheme | pass | 8.1 s | pass | 8.2 s |
| C15 stock regression | pass | 14.2 s | pass | 14.1 s |
| C16 forced collision | pass | 32.5 s | pass | 32.7 s |
| C17 accessibility | pass | 9.9 s | pass | 10.1 s |
| C18 two tabs (record only) | pass | 17.3 s | pass | 17.1 s |
| C19 headed (optional) | skipped | — | skipped | — |
| C14 console hygiene | pass | 0.0 s | **failed: aggregates the 2 crashes** | 0.0 s |
| **stats** | **31 passed, 1 skipped, 0 failed, 0 flaky: VERDICT** | 18.4 min | **28 passed, 3 failed, 1 skipped: NOT A VERDICT** | 23.5 min |

(`node tests/ux/tools/report.mjs final-full1 final-full2`, saved as `work/logs/final-report-matrix.md`;
`[showcase] UX rc=0 … VERDICT` and `[showcase] UX rc=1 … NOT A VERDICT: rc 1; 3 unexpected; expected 28 + skipped 1 !=
listed 32`.)

**The three failures in final-full2 are one QED64 limitation, L9** (a renderer V8 OOM when a new runtime boots in a
renderer right after the previous one; docs/UPSTREAM-REPORT-QED64.md L9):

* **C10.** It started at 00:12:59.3Z. The first reload came 5 ms after a ready page (`phaseBefore: ready`). At the
  second reload, 3.0 s later, Playwright reported `page.reload: Page crashed`. The macOS report
  `chrome-headless-shell-2026-10-01-201310.ips` (20:13:10 EDT = 00:13:10Z) shows `EXC_BREAKPOINT` (SIGTRAP), with the
  triggering thread a `DedicatedWorker thread` and 45 `DedicatedWorker` threads in the process. This is the re-pin
  lane's L9 signature: EXC_BREAKPOINT with 36–46 DedicatedWorker threads, about 2 s after the first reload of a ready
  page.
* **C21.** Part (a) passed every assertion: `probe, missed, probe, missed, wedged, late, late, cleared`,
  `relay.restart` 40.9 s after the click, ready on s2 at 49.2 s, edit exact, 0 errors, no card. Part (b) then navigates
  the same page to `?stall=15&liveness=observe`, the first boot after (a)'s relay restart, and the renderer crashed:
  `chrome-headless-shell-2026-10-01-200357.ips` (00:03:57Z), `EXC_BREAKPOINT`, triggering thread `DedicatedWorker`,
  43 `DedicatedWorker` threads. `g2.boot.s` was null, which gave `TypeError: Cannot read properties of null (reading
  'phase')` at `25-stall.spec.mjs:111`.
* **C14** fails on the two `CRASHED` console verdicts above, and on nothing else.
* **L9 tally on this pin** (every run that ran C10; `repin-crash1` ran only W4 and C10): C10 crashed in 3 of 4 runs (`repin-full1`, `repin-crash1`, `final-full2`;
  it passed in `final-full1`), C21 (b) in 2 of 4 (`repin-full1`, `final-full2`), and W4 in 1 of 4. On the previous pin
  `closeout-full1`, `full6` and `full7` had no crash. No `chrome-headless-shell` crash report exists for the
  `final-full1` window. The other report in this period, 19:17:01 EDT (`SIGILL`, with a `ServiceWorker thread`),
  predates `final-full1`'s tests and comes from the lock holder at that time (another session).
* **Not handled by the gallery.** A renderer crash takes the whole tab down: the gallery, the QED64 frame and its
  workers share one renderer process. Nothing in the gallery can survive or prevent it, so the
  "documented limitation that the gallery handles" exception does not apply. This is the owner's trade (README "Known
  limitations", L9): keep 9fdf9b8 (L7 fixed, L9 new) or roll back (docs/REPIN-LOG.md "Rollback").

**L7 and liveness in the two full runs.**

* C20 was 135/135 clean in both runs, with 0 stalls, 0 gallery wedges and 0 restarts. Each run made 270 edits (2 per
  link, from `docVersions`).
* QED64's own liveness was present (`builtIn: true`) and did nothing: probes 0, rescues 0, stalls 0, `wedgedReboots` 0.
  There were **0 `[liveness]` worker lines** in any console log of either run (`grep -c '\[liveness\]'` over
  `out/ux/final-full{1,2}/tests/*.jsonl`).
* In W1–W8 the gallery probe ran in auto mode and sent 0 probes, with 0 wedges and 0 restarts. The relay showed
  `workerDeaths 0, reboots 0`.
* **The only automatic restarts in either run are C21 (a)'s on the synthetic freeze fixture** (40.3 s and 40.9 s after
  the click, the 30 s deferral plus 2 × 5 s). They are not L7 occurrences. Their capture is
  `out/hang/captures/final-full1-2026-10-01T23-29-53-764Z.json`, labelled `synthetic: true`.
* The C20 pthread pool maxima were running 30, total 30, parked 8 (`final-full1`) and running 28, total 31, parked 8
  (`final-full2`).

**Metrics (final-full1 / final-full2).**

* C1 cold boot: 13.1 / 13.5 s, with all 8 thumbnails at naturalWidth 480.
* C2 warm boot: 6.7 / 6.9 s, with 0 .snapz GETs (every showcase GET was a 304).
* C3 renderer peak: 9.60 / 9.71 GB, below the 10.5 GB line, and the wasm heap stayed at 2147483648.
* C22: the 38 s silent `#eval` went edit→ready in 39.3 / 39.4 s, with a maximum silence of 37.3 / 37.5 s. The gallery
  probe sent 1 and got 1 answer in 3 ms; QED64 sent 0 probes; there were 0 restarts and no card. The slowest DistLens
  click took 2.5 / 2.6 s.
* C10 (`final-full1` only): renderer at first ready 9.07 GB, **transient peak 11.81 GB** (2.5 s over 10.5 GB: L8, larger
  than the old pin's 10.08–10.92 GB), settled 9.86 GB.

Screens: `out/ux/final-full1/screens/` (51 files). `C21-auto-restart-notice.png` and `C10-after-storm.png` were viewed:
the notice "Lean stopped responding and was restarted. Your text is kept." on session s2, and GraphScope's golden panel
after the storm.

**The hang hunt** (C20 alone, observe mode) is reported in `out/hang/FIELD-CAPTURE.md`; its table is repeated here:

| Run | Mode | Clean | Clicks / edits | Card stalls | Gallery wedges | QED64 rescues / stalls / `wedged` reboots | `[liveness]` lines | Pool max running / total / parked | Captures |
|---|---|---|---|---|---|---|---|---|---|
| final-hunt1–8 (each) | observe | 135/135 | 135 / 270 | 0 | 0 | 0 / 0 / 0 | 0 | 27–29 / 29–32 / 8 | 0 |
| **8 hunt runs** (00:17–01:07Z) | observe | **1080/1080** | **1080 / 2160** | 0 | 0 | **0 / 0 / 0** | 0 | max 29 / 32 / 8 | 0 |
| with the two full runs' C20 | auto + observe | 1350/1350 | 1350 / 2700 | 0 | 0 | 0 / 0 / 0 | 0 | max 30 / 32 / 8 | 0 |

**No hang in 10 C20 runs (2,700 edits) on the 9fdf9b8 pin, and QED64's liveness never had to act.** At the old rate of
about 1 in 20 runs, 10 clean runs happen with probability about 0.6, so this cannot show the fix works. It does show the
fix runs quietly: the message-mode mailbox boot line appeared in all 50 sessions, with no rescue, stall or reboot.
There is no real capture to classify as A or B (out/hang/FIELD-CAPTURE.md).

## Audit response

| Audit finding | What was wrong | What changed | Evidence after the change |
|---|---|---|---|
| **Blocker: an ordinary link click hung for good (C20), with no card and no recovery** | QED64 can stall in `elaborating` with no death (L7 below). The gallery watched only its own operations: after a click it had no watchdog at all, and Reset waited 330 s. Earlier runs avoided the hang by chance | **Gallery stall watchdog** (`gallery/gallery.js` `tapProgress`, `watchStall`, `restartLean`). It wraps `qed64.relay.toClient` and counts elaboration progress: `$/lean/fileProgress`, `publishDiagnostics`, or a new phase, version or session. While QED64 reports `elaborating` on a serving relay with no progress for **45 s**, it shows a soft `role=alert` card, "Lean has stopped making progress", with **Restart Lean** (`relay.restart` on the same text), **Reset example** and **Keep waiting**. The toolbar's Reset on a stalled checker also restarts it. New test **C21** freezes the checker deterministically. C20 and W1–W8 answer a real stall through the card and assert its form, its 45 s threshold and the recovery. The rule is: a stall is acceptable only if it was surfaced and recovered. **Five more C20 runs** followed the two full runs | C21 passes in full6 and full7. In 7 post-audit C20 runs (945 clicks), 0 stalls happened. W1–W8 report `stall.shown 0` (no false alarm) and `thresholdMs 45000`. Simulator: `SIM-GALLERY OK 56 ok` (run 7 = watchdog) |
| **Major: cards quoted text inside a closed `<details>`** | `scripts/build-gallery.mjs` chose claims from the golden text leaves, which include folded rows | build-gallery reads the frozen Html of every panel (`lean/expect/html[/w8]/<pkg>.json`). It quotes, and takes `expectPanel.texts` from, only leaves that are rendered by default. A spec text that is not rendered fails the build. The W tests now **assert** `hiddenCardClaims == []`. The bring-up `checkPanel` reads rendered text only | `BUILD-GALLERY CHECK OK 8 examples`. Changed cards: SimpLens L32, Expr X-Ray L21 and L40 (gallery README). 0 hidden claims in full6 and full7. The C13 expr-xray gallery baseline was re-approved (only that image changed: one hint is a line shorter) |
| Minor: memory fail line in GiB | 10.5 GiB is 11.27 GB, above the plan's line | `MEM_FAIL_BYTES = 10.5e9` (`tests/ux/lib/qed64.mjs`). Every memory assertion now compares bytes. C10 keeps its RSS timeline and reports the transient peak against the line. That transient peak is documented as L8, with the kill risk | C3 peak 9.94 / 9.27 GB (full6 / full7) < 10.5 GB. C10 settled 9.83 / 9.76 GB < 10.5 GB. C10 transient peak 10.92 GB (over the line for one 0.5 s sample) / 10.08 GB |
| Minor: D1 renders in the InfoView but is never logged | The console oracle could not see it | An init script in the QED64 page scans the InfoView document every 300 ms for every `neverAllowed` string. Any hit fails the test's console verdict | Mutant A (bridge abortSignal strip disabled, served on :5192): **C17 now FAILS** with `infoview-dom … Unrecognised error {"stack":"TypeError: r.abortSignal.addEventListener is not a function` (`work/logs/ux-fix-mutA2.log`). Before, C17 passed on the same mutant, and W3 logged `CONSOLE OK` while failing on panels (`ux-fix-mutA.log`) |
| Minor: C3/C4 switched through the page API | not the UI a user drives | C3 and C4 switch by **real mouse clicks on the cards**. The storm is 8 card clicks in 1.77 s. The outcome of each selection is read from the new `status().selections` log | C4: 7× `SUPERSEDED`, last `ok`, final panel equal to the golden, 0 deaths (full6, full7) |
| Minor: C2 wording | "every other request a 304" did not match full5 | reworded from the server log of each run | full6 and full7: every GET was a 304 (0 bytes); the only non-304 lines are the 2 preflight `HEAD`s of the .snapz files |
| Minor: the C11 cards overlapped | the gallery card covered QED64's own failed boot card | **compact card**: title, one line and the actions, at the top of the stage, while the page's boot card shows. C11 asserts no overlap | `out/ux/full7/screens/C11-cut-lasting.png`; `C11.json lasting.layout {compact: 1, overlap: false}` |
| Minor: the auditor's mutants grew the warm profile | `UX_ORIGIN` runs shared `out/ux/profiles/ux-warm` | `UX_WARM_PROFILE` points such runs at their own profile. The mutant runs here used `work/profiles/mutant-warm`, which was removed afterwards | — |

Found while re-running (the Mac's idle sleep). The first C21 attempt (`fix2`) "took" 995 s. `pmset -g log` shows
`08:15:11 -0400 Sleep Entering Sleep state due to 'Idle Sleep' … 988 secs` in the middle of the test: a headless
Chrome holds no idle-sleep assertion. `scripts/with-browser-lock.sh` now runs the command under `caffeinate -i`, a
process-scoped assertion that changes no setting. Every later run logs `running under caffeinate -i`.

## Run it

```
npm run test:ux                       # = scripts/with-browser-lock.sh ux-suite npx playwright test -c tests/ux/playwright.config.mjs
UX_RUN=myrun npm run test:ux -- --grep "W4|C20"     # one run dir out/ux/myrun/, a subset
UX_HEADED=1 npm run test:ux -- --grep C19           # the optional headed sign-off (opens a browser window)
npm run test:ux -- --grep C13a --update-snapshots   # re-approve visual baselines (tests/ux/__screenshots__/)
node tests/ux/tools/report.mjs full6 full7          # the results matrix below
UX_LIVENESS=observe UX_RUN=hunt1 npm run test:ux -- --grep C20   # a hang hunt: wedges are recorded and captured, not restarted
scripts/showcase.sh ux                              # the full suite AND a record in out/ux/showcase-ux-runs.jsonl (VERDICT or why not)
```

`UX_LIVENESS=observe|off|auto` sets the gallery's liveness probe mode for every gallery the suite opens (a test's own
`?liveness=` wins). In observe mode a wedge the probe declares is captured by `captureHang` before the card's Restart
Lean answers it; a click that is "not ready within … after the click" is captured in any mode. Captures go to
`out/hang/captures/<run>-<iso>.json` with a `.worker-console.log` beside them.

The suite needs `scripts/serve.mjs` on :5190. Global setup starts it when it is not running, and stops it afterwards
only in that case. The suite takes `out/.browser.lock` for the whole run through `with-browser-lock.sh`, and runs under
`caffeinate -i`. Before every browser launch it also waits for the §8.1 cooldown: ≥ 6 GiB free+inactive+speculative
and no `chrome-headless-shell`.

Outputs in `out/ux/<run>/`:

* `metrics.json`
* `tests/<id>.json` and `tests/<id>.<session>.console.jsonl`
* `screens/`
* `report.json`
* `test-results/`: traces, for failed tests only

## Environment

* Playwright 1.62.1, `chromium-headless-shell` rev 1234 (Chrome 151.0.7922.34), `--enable-features=SharedArrayBuffer`.
* `workers: 1`, `retries: 0`, `trace: 'retain-on-failure'`, default action and evaluate timeout 45 s.
* Host: macOS 25.6, 36 GB RAM, Node 26.3.
* Server `scripts/serve.mjs` on :5190, overlay `widgets8`. C11 starts its own CHAOS server on :5191 and stops it.
* Profiles: `fresh` is a new context. `warm` is the persistent `out/ux/profiles/ux-warm`, primed by C2.

## The harness (`tests/ux/`)

| File | What it is |
|---|---|
| `playwright.config.mjs` | `workers: 1`, `retries: 0`, `trace: 'retain-on-failure'`, `maxDiffPixelRatio 0.01`, global setup and teardown, run dir `out/ux/$UX_RUN` |
| `lib/qed64.mjs` | **Hang capture** (`captureHang`, `Gallery.maybeCapture`; close-out): status + pool, `telemetry()` raced against 10 s, the worker and `[lean:…]` console lines, then the QED64 session's mailbox protocol (one raw `__emscripten_check_mailbox()` per eligible worker, 15 s watch; if nothing moved, one `checkMailbox()` in the main-thread worker, 15 s watch), written to `out/hang/captures/`. **Thumbnails** (`Gallery.thumbs`, C1). **launch + cooldown**. **Tap**: an init script wraps `qed64.relay.toClient`, records `publishDiagnostics` per version and reports LSP error replies through `exposeBinding`. **InfoView DOM oracle**: an init script in the QED64 page scans the InfoView every 300 ms for the `neverAllowed` strings. **Status oracle**. **InfoView** `frameLocator`. **DOM signature**. **Console oracle**. **RSS sampler**, in bytes, with `MEM_FAIL_BYTES = 10.5e9`. **Server-log byte accounting** (network truth). **Stall-card driver**: `stallCardVisible`, `recoverStall`. `selectUI`: a real card click with the selection's own outcome. **Metrics writer** |
| `lib/actions.mjs` | real-UI interactions: cursor check, link click (it answers a stall card through "Restart Lean" and records it), shift-click selection, hover, Monaco quick fix, summary toggle |
| `lib/fixtures.mjs` | the `ux` fixture. It classifies and closes every session. A test with an unexpected console message, or a `neverAllowed` string in the InfoView, **fails** (except record-only C18) |
| `specs/00-boot`, `10-widgets`, `20-click-all`, `25-stall`, `30-robustness`, `40-visual`, `50-misc`, `99-hygiene` | the tests (matrix below) |
| `tools/report.mjs` | the Markdown matrix. `tools/{domprobe,caprobe,stockcases}.mjs` are exploration probes |

**DOM signature (W1–W8, C3, C4, C5, C10–C17, C20, C21).** `domSignature` finds the info block whose summary reads
`Probe.lean:<line+1>:<char>`. In it, it takes the "HTML Display" details or the rpc panel, and walks the DOM as
`lean/goldens/lsp-golden.mjs signature()` walks the Html. It yields:

* the element tag and svg tag multisets;
* the components, where `MakeEditLink` = `a.link.pointer.dim` and `InteractiveCode` = the outer `span.font-code` with hover tags;
* the text leaves;
* the InteractiveCode texts;
* the `[linkText, title]` list.

`compareSignature` requires **every** env-independent field to equal the golden. It skips `htmlSha256` and the
MakeEditLink `textDocument`/`version` (TEST-PLAN-DELTAS §1).

**Console oracle.** `tests/ux/bringup/console.mjs classifyConsole` runs with exactly `tests/ux/selectors.json
consoleAllowlist`. Scenario entries are allowed only in the test that deliberately breaks or restarts something.
On top of that come two stricter rules:

* every allowlisted empty `console.error` must follow, within 3 s, an LSP `-32800` reply seen by the tap;
* the InfoView DOM oracle (above).

There is one new scenario, `stallRestart`. QED64's `relay.restart()` answers every request still in flight with the
hard-coded text "QED64: restarting with exact imports" (`lsp-relay.ts:127`), whatever the restart is for. A stalled
checker always has requests in flight. The scenario is allowed only in C21, and in C20/W1–W8 only after a real stall
was recovered. `check-gallery.mjs` 8c unit-tests it (`CHECK-GALLERY OK 108 ok, 0 failed`).

## Results matrix (full6 and full7, back to back)

| ID | Test | full6 | full6 time | full7 | full7 time |
|---|---|---|---|---|---|
| C1 | cold boot: fresh profile to ready, phase timeline, bytes per prefix | pass | 14.7 s | pass | 14.9 s |
| C2 | warm boot: persistent profile, 0 .snapz bytes, only revalidations | pass | 7.5 s | pass | 8.0 s |
| C3 | memory + L-switch lane + no-collision: one boot, all 8 widgets **by card clicks**, RSS (bytes) and wasm heap | pass | 20.0 s | pass | 20.7 s |
| C4 | switching **through the UI**: 8 sequential card clicks, then a storm of 8 card clicks in 2 s | pass | 20.1 s | pass | 20.4 s |
| W1 | ChartKit | pass | 10.9 s | pass | 11.3 s |
| W2 | HasseView | pass | 23.7 s | pass | 24.2 s |
| W3 | Interval Inspector | pass | 18.1 s | pass | 17.8 s |
| W4 | Simp Lens | pass | 32.9 s | pass | 33.0 s |
| W5 | Expr X-Ray | pass | 15.0 s | pass | 15.3 s |
| W6 | TreeScope | pass | 11.4 s | pass | 11.6 s |
| W7 | GraphScope | pass | 19.6 s | pass | 19.9 s |
| W8 | DistLens | pass | 22.3 s | pass | 22.2 s |
| C20 | click-all in the browser: all 135 rendered links, each from a freshly reset example | pass | 376.4 s | pass | 376.9 s |
| **C21** | **stall watchdog (QED64 L7): a frozen checker is surfaced by a card; Restart Lean, Keep waiting and Reset work** | pass | 76.5 s | pass | 76.7 s |
| C5 | edit, break, fix | pass | 14.3 s | pass | 14.6 s |
| C6 | refused header (stock page) | pass | 11.6 s | pass | 11.5 s |
| C7 | unknown module (stock page) | pass | 15.7 s | pass | 16.0 s |
| C8 | bad overlay (stock card; gallery refuses before navigation) | pass | 15.6 s | pass | 15.8 s |
| C9 | unpaired fixture (temp overlay, altered runtime) | pass | 14.9 s | pass | 14.9 s |
| C10 | reload storm: 5 reloads in 15 s | pass | 29.5 s | pass | 29.9 s |
| C11 | network cut mid-.snapz (CHAOS): one cut absorbed; lasting cut surfaced (compact card, no overlap); reload recovers | pass | 49.7 s | pass | 49.5 s |
| C12 | offline warm reload; unreachable overlay index | pass | 31.8 s | pass | 32.8 s |
| C13a | visual baselines: 8 panels and the gallery at 1440×900, light | pass | 24.7 s | pass | 25.2 s |
| C13b | visual baseline: the gallery at 390×844 | pass | 15.7 s | pass | 16.1 s |
| C13c | dark scheme (evidence, no baseline) | pass | 8.1 s | pass | 8.5 s |
| C15 | stock-text regression (EXAMPLES.mathlib on the superset) | pass | 14.4 s | pass | 14.9 s |
| C16 | forced collision: note + offer; "Load exact imports" degrades gracefully | pass | 34.1 s | pass | 36.4 s |
| C17 | gallery accessibility: keyboard-only walkthrough, aria | pass | 9.9 s | pass | 10.2 s |
| C18 | two tabs at once (record only) | pass | 18.0 s | pass | 17.9 s |
| C19 | headed Chrome-for-Testing sign-off (optional, `UX_HEADED=1`) | skipped | — | skipped | — |
| C14 | console hygiene across the suite | pass | 0.0 s | pass | 0.0 s |

**Close-out run `closeout-full1`** (same 30 tests plus the new C22; C21 rewritten): every row passed, C19 skipped.
Durations: C1 14.5 s, C2 7.2 s, C3 19.8 s, C4 22.1 s, W1–W8 11.2 / 24.3 / 17.7 / 33.0 / 15.2 / 11.3 / 20.0 / 22.7 s,
C20 371.1 s, **C21 125.5 s**, **C22 53.5 s** (new), C5 14.5 s, C6 11.3 s, C7 15.2 s, C8 15.2 s, C9 14.7 s, C10 29.2 s,
C11 48.3 s, C12 31.9 s, C13a 24.9 s, C13b 15.8 s, C13c 8.5 s, C15 14.5 s, C16 33.8 s, C17 10.1 s, C18 17.2 s
(`out/ux/closeout-full1/report.json`). Six C13a gallery baselines were re-approved before it on purpose
(`work/logs/closeout-batch1.log`, viewed): the old ones predated the bring-up lane's letterboxed thumbnails and whole-edit
hint details, and the close-out's whole-command hint labels (e.g. "Line 18 · #interval_inspect (Set.Ioc (1:ℝ) 2 ∪
Set.Ioc 2 3 = Set.Ioc 1 3)" instead of the cut "… 2 ∪"). The 8 panel baselines and C13b are unchanged.

## W1–W8: the widgets in the real InfoView (lane L-isolated: one warm boot per widget)

Every count below is identical in full6 and full7.

| ID | Widget | Declared cursors (full signature = golden) | Card claims rendered | Declared clicks (real mouse, = frozen edit and native sha256, 0 err / 0 warn) | Other interactions | Screens (`out/ux/full7/screens/`) |
|---|---|---|---|---|---|---|
| W1 | ChartKit | 5/5 | 8/8 | — | "HTML Display" collapse/expand by mouse | [gallery](../out/ux/full7/screens/W-chart-kit-gallery.png), [panel](../out/ux/full7/screens/W-chart-kit-panel.png) |
| W2 | HasseView | 5/5 | 9/9 | 5/5 | — | [gallery](../out/ux/full7/screens/W-hasse-view-gallery.png), [panel](../out/ux/full7/screens/W-hasse-view-panel.png), [after click](../out/ux/full7/screens/W-hasse-view-after-click.png) |
| W3 | Interval Inspector | 8/8 | 16/16 | 3/3 | shift-click `hx`: 0 → 1 selected, golden selection panel, cleared | [gallery](../out/ux/full7/screens/W-interval-inspector-gallery.png), [selection](../out/ux/full7/screens/W-interval-inspector-selection-1.png) |
| W4 | Simp Lens | 6/6 | 11/11 | 6/6 Try-this `[apply]` | hover popup exactly `n : ℕ`; **6/6 code actions through Monaco's quick-fix UI** (1 lightbulb, 5 Cmd+.), each edit equal to `[apply]` by sha256 | [gallery](../out/ux/full7/screens/W-simp-lens-gallery.png), [code action](../out/ux/full7/screens/W-simp-lens-codeaction.png) |
| W5 | Expr X-Ray | 6/6 | 10/10 | — | summary toggles; 1 pick and 2 picks, each the golden selection panel, both cleared | [gallery](../out/ux/full7/screens/W-expr-xray-gallery.png), [selection 1](../out/ux/full7/screens/W-expr-xray-selection-1.png), [selection 2](../out/ux/full7/screens/W-expr-xray-selection-2.png) |
| W6 | TreeScope | 6/6 | 8/8 | — | drawn shapes take their colour from `var(--vscode-…)` (dark InfoView: L6) | [gallery](../out/ux/full7/screens/W-tree-scope-gallery.png), [panel](../out/ux/full7/screens/W-tree-scope-panel.png) |
| W7 | GraphScope | 5/5 | 8/8 | 4/4 | — | [gallery](../out/ux/full7/screens/W-graph-scope-gallery.png), [after click](../out/ux/full7/screens/W-graph-scope-after-click.png) |
| W8 | DistLens | 5/5 | 9/9 | 3/3 | — | [gallery](../out/ux/full7/screens/W-dist-lens-gallery.png), [after click](../out/ux/full7/screens/W-dist-lens-after-click.png) |
| | **total** | **46/46** | **79/79** | **21/21** | 3/3 selections, 1/1 hover, 6/6 code actions | |

Every W test also asserts the following:

* the gallery reached ready on its example, and the bridge install was not late;
* the header is `covered` with no collision;
* no "Unrecognised error" in the panel, and none anywhere in the InfoView (the DOM oracle);
* after each click the chip reads "edited", and Reset restores the example;
* `relay.stats`: `workerDeaths 0, reboots 0, rangedChanges 0`;
* `bridgeStats().errors` is empty;
* **every card claim is in the panel's `innerText`**;
* **the stall watchdog is armed** (`thresholdMs 45000`, relay tapped) and **raised no card**. Shown 0 times in every W test, with `progressMsgs` 64–1165 per test, so it was counting progress the whole time.

## C20: click-all in the browser (the twin of `out/click-all`)

Every link in `out/click-all/w8/<pkg>.json` (and `out/click-all/dist-lens.json`) is clicked with the real mouse in the
real InfoView. Each click starts from the example freshly reset by the gallery's **Reset example** button. For each link:

1. the panel equals its golden;
2. the post-click document equals `applyEdit(example, range, newText)` **and** the native `editedSha256`;
3. QED64 re-checks that version with 0 errors and 0 warnings.

New since the audit:

* The test waits for **ready or the gallery's stall card**. A stall is answered through the card's own "Restart Lean"
  button, and the link is then judged on the re-check of the same post-click text.
* Each stall must show the designed card (`role=alert`, the title, Restart Lean / Reset example / Keep waiting), be
  shown only after ≥ 45 s without progress, and be recovered by `relay.restart`. The number of relay restarts must
  equal the number of stalls answered.
* The pthread pool total after each link is recorded (`poolTotals`).

| Package | Links | full6 | full7 | full6 time | full7 time | click→edit median / max (full6) | click→clean ready median / max (full6) |
|---|---|---|---|---|---|---|---|
| hasse-view | 47 | 47 | 47 | 110.3 s | 111.0 s | 30 / 88 ms | 652 / 1142 ms |
| interval-inspector | 3 | 3 | 3 | 5.1 s | 4.9 s | 49 / 73 ms | 212 / 232 ms |
| simp-lens (Try this) | 6 | 6 | 6 | 9.8 s | 9.7 s | 32 / 48 ms | 496 / 517 ms |
| graph-scope | 58 | 58 | 58 | 102.4 s | 102.0 s | 30 / 82 ms | 325 / 1580 ms |
| dist-lens | 21 | 21 | 21 | 61.6 s | 62.3 s | 30 / 72 ms | 1158 / 2518 ms |
| **total** | **135** | **135** | **135** | 376 s | 377 s | | |

In both runs: `workerDeaths 0`, `reboots 0`, `userRestarts 0` per package, and 0 stalls.

### C20 stability and the hang rate

The audit asked for at least 5 more C20 runs and a hang rate. After the two full runs, `work/logs/run-gates.sh` ran
C20 alone 5 times, back to back. One of those runs was interrupted by another program (below) and repeated as
`c20rep6`.

| Run | Window (UTC) | Clean | Stalls (card shown) | Max pthread pool total | Evidence |
|---|---|---|---|---|---|
| full6 (in the full suite) | 12:50–13:07 | 135/135 | 0 | 29 | `out/ux/full6/tests/C20.json` |
| full7 (in the full suite) | 13:07–13:23 | 135/135 | 0 | 31 | `out/ux/full7/tests/C20.json` |
| c20rep1 | 13:23–13:32 | 135/135 | 0 | 29 | `out/ux/c20rep1/tests/C20.json` |
| c20rep2 | 13:32–13:44 | 135/135 | 0 | 29 | `out/ux/c20rep2/tests/C20.json` |
| c20rep3 | 13:44–13:52 | 135/135 | 0 | 33 | `out/ux/c20rep3/tests/C20.json` |
| c20rep4 | 13:52–13:58 | **aborted** after 56/56 clean links (hasse-view, interval-inspector, simp-lens) | 0 | 29 | `work/logs/ux-c20rep4.log`: `cooldown refused after 180000 ms: 16.0 GiB reclaimable, strays: 343 …chrome-headless-shell … --user-data-dir=/private/tmp/claude-501/-Users-fawadhaider-code-wasm64-lean-fable/…/lv-profiles/r2/fx-budget` |
| c20rep5 | 13:58–14:10 | 135/135 | 0 | 31 | `out/ux/c20rep5/tests/C20.json` |
| c20rep6 (repeats rep4) | 14:11–14:18 | 135/135 | 0 | 32 | `out/ux/c20rep6/tests/C20.json` |

**Result: 7 complete runs plus a partial one: 1001 link clicks in the browser, all clean, 0 stalls, 0 worker
deaths.** Counting every recorded C20 run (`out/ux/*/tests/C20.json`: 19 before the close-out, about 2,200 link
clicks), the hang has been seen **once, so about 1 in 20 C20 runs** (corrected at close-out; this section earlier
said "once in about 14 C20 sessions"). The close-out's `closeout-full1` C20 added 135 more clean clicks, with 0
liveness wedges. That one was
the auditor's `auditor-full`, which also ran C1–C4 and W1–W8 in the same suite before C20. This is small-sample
evidence of a rare, intermittent QED64 fault, not proof that it is absent. What *is* established:

* **when it happens, the gallery now surfaces it.** C21 does this in both full runs. In C20 and W1–W8 a stall
  without the card, or one recovered by anything other than the card's Restart Lean, fails the test;
* **the watchdog raises no false alarms.** `stall.shown 0` in every W test and every C20 package of every run above.

c20rep4's abort was not a suite failure. The suite's own host rule held: at the next launch it found a
`chrome-headless-shell` that is not ours (another Claude session working on wasm64-lean-fable, outside
`out/.browser.lock`) and refused to start a second browser. It waited the full 180 s cooldown and then failed
loudly. The same foreign browsers stretched c20rep1, rep2 and rep5 (534–657 s against 370–418 s), because each launch
waited for them to exit. The bring-up re-check below was refused once for the same reason (`rc=76`).

## C21: the gallery's handling of a frozen checker (rewritten at close-out: liveness probe, observe mode, hang capture)

**The numbers in this section are from the previous pin** (no QED64 liveness: probe after 10 s, restart about 20 s,
ready about 29 s). On the 9fdf9b8 pin the probe defers 30 s to QED64's own liveness: restart about 41 s and ready about
49 s after the click (Close-out 2 and 3 above).

The audit's hang is intermittent and cannot be summoned on demand. C21 therefore **freezes** the checker in a
deterministic way that has the same observable symptoms. Right before an edit it detaches the current session's
output inside the QED64 page:

* `session.onLsp` drops every LSP message;
* `session.onStatus` drops every `ready`.

The page then keeps reporting `elaborating` at the edited version on a serving relay, with no death and no LSP
traffic, exactly as in the audit trace. A relay restart replaces the session, as it would replace a frozen worker.
**Everything this fixture produces is synthetic**: it proves the gallery's handling and the hang capture, never
anything about L7 itself (the worker underneath stays healthy; the capture's `telemetry()` even reports the worker
`ready`).

Close-out run `closeout-c21c22-3` (2026-10-01 19:52–19:55Z, `work/logs/closeout-ux-c21c22-3.log`,
`out/ux/closeout-c21c22-3/tests/C21.json`), first on the default settings, then in observe mode with `?stall=15`:

| Step (real UI) | Result |
|---|---|
| (a) default mode (`liveness` auto, 45 s card): HasseView's first declared link clicked on a frozen checker | the probe ran at 10 s of silence, missed twice (5 s each), then declared it wedged with QED64 alone showing `{phase: elaborating, relay: serving, lastDeath: null, session: s1}`; event sequence `probe, missed, probe, missed, wedged, late, late, cleared` (the two `late` are the probes answered by the restart's own `failInFlight`) |
| automatic restart | `relay.restart` issued **20.4 s** after the click (asserted 19–25 s), no card (`stall.shown 0`), notice “Lean stopped responding and was restarted. Your text is kept.”; the post-click text re-checked clean on session s2 (**click→ready 28.6 s**: 20.4 s detection, then the restart's settle, warm boot and re-check), edit exact, native sha256 equal, 0 errors / 0 warnings, `userRestarts 1, workerDeaths 0`. Screen: `out/ux/closeout-c21c22-3/screens/C21-auto-restart-notice.png` |
| (b) observe mode (`?liveness=observe&stall=15`): a real keystroke on a frozen checker | every sample until the card: `elaborating`, relay `serving`, no death; card after 16.2 s; the probe recorded the wedge 20.5 s after the last progress with action `observed`, **no restart** (`restarts 0`, same session s1) |
| hang capture, before anything was reset | `out/hang/captures/closeout-c21c22-3-2026-10-01T19-54-09-253Z.json` (+ `.worker-console.log`), labelled `synthetic: true`, “NOT L7 evidence”: status + pool, `telemetry()` answered at once, 30 `[lean:…]` console lines, the raw `__emscripten_check_mailbox()` called once in the one eligible worker (the Emscripten main thread, `/workers/lean.worker.js`; 15 idle pool workers skipped because `_pthread_self()` is 0, 9 busy ones did not answer in 3 s), 15 s watched: not resumed; then `checkMailbox()` once: not resumed (both expected for a JS-level freeze); 33 s in all |
| the card after the capture | still up; Keep waiting hid it and it came back after 15.4 s; the toolbar's Reset example restarted the checker on the example (8.4 s), panel equal to the golden, 0 errors / 0 warnings; observe mode never restarted anything; relay `userRestarts 1, workerDeaths 0, reboots 0` |
| console | OK with the `stallRestart`, `relayRestartOrReboot` and new `livenessObserved` scenarios (the observe-mode `console.warn`, allowed only there; unit-tested in check-gallery 8c) |

The same behaviour is unit-tested without a browser (`scripts/sim-gallery.mjs` runs 7 and 8: observe mode records and
never restarts; auto restarts once with the text kept and a notice; an alive-but-slow checker answering every probe
is never restarted; a second wedge inside the 120 s gap falls back to the card; every probe is a `textDocument/hover`
with a string id and `params`; every reply is swallowed; `liveness('observe'|'off')` switch; `SIM-GALLERY OK 68 ok`).

### The 10 s / 5 s / 5 s numbers and why ~20 s (previous pin; 30 s / 5 s / 5 s and ~41 s on 9fdf9b8)

Trigger after 10 s of `elaborating` with no progress; two probes, 5 s each. Recovery is therefore ~20 s to the
restart plus ~8 s for the restart itself (the relay's 1.5 s settle, a warm boot of the 1.39 GB region and the
re-check). The stall card stays at 45 s and is now the fallback (rate limit: one automatic restart per 120 s; a
restart that throws; or a checker that answers probes but makes no progress for 45 s).

## C22: the negative, a legitimately slow elaboration is not restarted (new)

Verified first in the browser (`tests/ux/tools/liveprobe.mjs`, run `explore-live`, `out/ux/explore-live/liveprobe.json`,
`work/logs/closeout-liveprobe-1.log`): with `#eval IO.sleep 40000` appended to the DistLens example, QED64 stayed
`elaborating` with **no progress message for 40 s** (idle 0 → 40.0 s), and the gallery's hover probe at 0:0 was
answered at 10.3, 20.5 and 30.8 s of silence in **2, 1 and 1 ms**: Lean answers the hover on the header snapshot
while the elaboration thread sleeps. So the probe design holds; no other request was needed.

C22 (same run `closeout-c21c22-3`, default settings, `out/ux/closeout-c21c22-3/tests/C22.json`):

| Case | Result |
|---|---|
| the slowest DistLens declared click (`twoDice 5 = 1/6`, native re-elaboration 897 ms) | clean, click→ready 2.7 s; 0 probes sent (progress kept arriving), 0 wedged, 0 restarts |
| `#eval IO.sleep 38000` appended (one input event) | edit→ready 39.3 s, max silence 37.5 s; **3 probes, 3 answered in 3 / 1 / 1 ms**, 0 missed, 0 wedged, 0 restarts, card not shown, same session, 0 deaths, 0 errors / 0 warnings |

38 s rather than 40 s keeps the silence under the 45 s card with a margin (the exploration's 40 s sleep peaked at
40.0 s of silence).

## Metrics

| Metric | full6 | full7 | Notes |
|---|---|---|---|
| C1 cold boot to gallery ready | 13.9 s | 14.2 s | budget ≤ 180 s; timeline: QED64 booting 2.1 s → elaborating 11.8 s → ready 13.9 s; the server sent the 2 snapshots, 397,319,879 B |
| C2 warm boot | 6.8 s | 7.6 s | budget ≤ 20 s. Server log: **0 .snapz bytes**. Every GET was a 304 with 0 bytes (showcase 15/15, assets 10/10, infoview 7/7, …). The only other lines are the 2 preflight `HEAD`s of the .snapz files. No .snapz GET from the page |
| C3 renderer RSS at ready / after all 8 / peak | 9.55 / 9.94 / **9.94 GB** | 9.24 / 9.24 / **9.27 GB** | fail line **10.5 GB = 10.5e9 B** (§8.3); 1 renderer |
| C3 wasm heap (`currentBytes`) | 2147483648 → 2147483648 | same | no growth across 8 widgets |
| C3 card click → panel | 0.06–2.6 s | similar | dist-lens is the slowest |
| C4 switch (`lastSwitchMs`, card clicks) | 0.31–2.12 s | 0.31–2.22 s | storm: 8 clicks in 1.77 s; 7× SUPERSEDED, last ok; settled 2.7 / 2.6 s |
| W boots (warm, per widget) | 6.6–9.2 s | similar | |
| C20 click→edit / click→clean ready | 9–88 ms / 0.17–2.52 s | similar | 135 links |
| C21 stall card | at 15.0 s idle; 16.2 s after the keystroke | at 15.0 s idle; 16.1 s after the keystroke | threshold 15 s in C21; 45 s by default |
| C10 renderer: first ready / transient peak / settled | 9.57 / **10.92** / 9.83 GB | 9.41 / 10.08 / 9.76 GB | full6 is over 10.5 GB in one 0.5 s sample (L8) |
| C16 renderer peak during "Load exact imports" | 11.26 GB | 9.75 GB | L5 |
| C18 two tabs (record only), peak | 12.91 GB | 12.75 GB | both tabs ready, no crash |
| C14 tests / sessions / empty console.errors explained | 30 / 38 / 135 of 135 | 30 / 38 / 121 of 121 | 0 unexpected |

## Cross-cutting tests: what each asserts and what it showed (full6; full7 the same unless stated)

* **C1, C2.** As above. C2 is now worded from the server log of each run (audit minor 3c). In full5 the showcase prefix
  had 14 of 15 GETs as 304 and 6029 bytes sent, because the gallery files had changed since the profile was primed. In
  full6 and full7 all 15 were 304.
* **C3 (card clicks).** All 8 examples selected by a real click on their card. Every first panel equals its golden,
  with `collision: null` and no "Load exact imports" control. The peak renderer is below 10.5e9 B.
* **C4 (card clicks).** 8 sequential clicks, each panel equal to its golden with no "No connection". Then 8 clicks
  250 ms apart: the gallery's selection log shows 7× `SUPERSEDED` and the last `ok`. The final panel is chart-kit's
  golden, with no stale text and 0 deaths or reboots.
* **C5 edit, break, fix (hasse-view, real keystrokes).** A typo gives the two expected errors and the panel disappears
  without a page error. Backspace brings back 0 errors and the golden panel.
* **C6 / C7 (stock).** `import HasseView` alone is refused (`missing [HasseView]`, no widening). `import
  Mathlib.NotAModule` is refused with the stock text `modules #[Mathlib.NotAModule] are not loaded in this session`.
* **C8 / C9.** The gallery refuses before navigation (0 QED64 loads): "The “nope” overlay is not usable"; for the
  unpaired fixture, `entry-init-runtime`. The stock page fails its boot (C9 without naming the cause: L4).
* **C10 reload storm (graph-scope).** 5 reloads at 0/3/6/9/12 s, then:
  * ready, with the panel equal to the golden and no crash;
  * 156 workers created, 130 closed, 26 alive;
  * bridge `late 0`.
  The **settled** renderer is asserted below 10.5e9 B. The transient peak is recorded with the full 0.5 s timeline (L8).
* **C11 network cut.**
  * (a) One cut is absorbed (prefetch → stream).
  * (b) A lasting cut gives 3 boot deaths. The gallery's card is **compact** and does not cover QED64's own failed
    boot card: `{compact: 1, overlap: false}`, card y 104–223, page card from y 260
    ([screenshot](../out/ux/full7/screens/C11-cut-lasting.png)).
  * The server comes back, and a reload is ready with the panel equal to the golden.
* **C12.** A warm reload with every .snapz GET aborted boots from the profile (0 aborted). With the overlay unreachable,
  the gallery shows its preflight card and the stock page cannot boot (L3).
* **C13.** Baselines match within `maxDiffPixelRatio 0.01`. `C13-gallery-expr-xray.png` was re-approved on purpose
  after the card fix: its L21 hint is now one line shorter, so the rail moves up. The new image was viewed and is
  identical otherwise. The other 16 baselines are unchanged.
* **C14.** 30 tests and 38 sessions; 0 unexpected messages and 0 crashes. Scenario entries appear only inside their
  tests. full6: `stallRestart` 21 + 5 (C21 only), `relayRestartOrReboot` 4, `bootFailure` 50, `crashBreakerTripped`
  83, `networkCut` 7, `exactImportsFallback` 1.
* **C15.** `EXAMPLES.mathlib` on widgets8 is ready with 0 errors (2 designed warnings).
* **C16.** The forced collision gives the stock note, the error and the offer. The offer restarts QED64; the exact
  import fails (L5) and falls back to covered, with 0 deaths. Afterwards the gallery still shows ChartKit's golden panel.
* **C17 accessibility (keyboard only).** Landmarks, names and roles are checked. F6, arrows, Home/End and Enter work,
  with a visible focus ring, and hints are reachable by Tab. The skip link keeps `#hasse-view`. Under mutant A, C17 now
  fails on the InfoView DOM oracle (audit response).
* **C18 (record only).** Two tabs, both ready, peak 12.75–12.91 GB, no crash.

## Failures found, root-caused and fixed (all in our repo)

Rows 1–16 are from building the suite (pre-audit; evidence in the runs named). Rows 17–23 come from the audit and its
re-runs.

| # | Seen | Root cause | Fix |
|---|---|---|---|
| 1 | `tracing.start: Tracing has been already started` (`ux-dev1.log`) | Playwright Test also instruments library-launched contexts | the harness's own tracing was removed |
| 2 | dev1 W4 hung 20+ min | no default timeout in library-launched contexts | `setDefaultTimeout(45000)`, navigation 120 s, `actionTimeout` |
| 3 | W4 code action: `context-view-pointerBlock intercepts pointer events` | Monaco's action widget overlay goes away on the first mousemove | the mouse moves onto the item first, then clicks |
| 4 | W4 code action 2: label differs | Monaco renders a multi-line title on one line | compare with `\n` replaced by a space |
| 5 | C20 graph-scope K4 `Adj 0 2`: wrong edit | the diagonals cross at their midpoints | a hit-tested point on the edge |
| 6 | C20 graph-scope #4: `element is not visible` | horizontal and vertical edges have a zero-size box | a real mouse at the hit-tested point |
| 7 | C20 dist-lens 3/21 "click did not change the document" with bare `page.mouse` | no stability wait | hybrid: an actionable click, or a point re-verified 300 ms later |
| 8 | C4 storm's first select resolved `ok` | the storm began on the shown example | the storm starts elsewhere |
| 9 | C7 stock text not matched | Lean prints `#[…]` | exact text |
| 10 | C10 5th reload at 15.02 s | schedule drift | reloads at 0/3/6/9/12 s |
| 11 | C11 v1: no death after one cut | QED64 absorbs one cut | (a) asserts absorption; (b) tests a lasting cut |
| 12 | C2 "397 MB" on a warm boot | HEAD Content-Length counted as body | GETs only; the server log is the truth |
| 13 | designed failure messages outside the allowlist | no scenario entries | `bootFailure`, `networkCut`, `exactImportsFallback`, each unit-tested |
| 14 | C17: the skip link broke the deep link (`dev12`) | `href="#qed64-frame"` changed the hash | the skip link focuses Monaco without touching the URL |
| 15 | C19 headed: `/favicon.ico 404` | no page icon | `gallery/favicon.svg` |
| 16 | full1: C13 tests shared one metrics file | id slug | C13a/b/c; duplicate ids refused |
| 17 | **audit: C20 hung after a link click, with no card** (`auditor-full`) | QED64 L7, and the gallery had no watchdog after edits | **stall watchdog + C21** (audit response) |
| 18 | **audit: 3 cards quoted folded text** | claims came from DOM leaves, including closed `<details>` | visibility from the frozen Html; asserted in W1–W8 |
| 19 | audit: the memory line was 11.27 GB | GiB vs GB | `MEM_FAIL_BYTES = 10.5e9` |
| 20 | audit: D1 invisible to the console oracle | rendered, not logged | InfoView DOM oracle. The first version, an init script in the srcdoc frame, **did not run there** (`fix-mutA`: W3 `CONSOLE OK` on the mutant). It now scans from the QED64 page (`fix-mutA2`: C17 fails as it must) |
| 21 | fix1 C21: `QED64: restarting with exact imports` pageerror ×5 and console.error ×21 | `relay.restart` answers in-flight requests with that fixed text | `stallRestart` scenario, justified, documented and unit-tested |
| 22 | fix2 C21: "click to ready 995 s", no card | **the Mac slept 988 s** mid-test (`pmset -g log`: `08:15:11 … 'Idle Sleep' … 988 secs`); headless Chrome holds no sleep assertion | `with-browser-lock.sh` runs the command under `caffeinate -i` |
| 23 | fix2 C13a: expr-xray gallery differs | the intended card-text change (row 18) | that one baseline re-approved and viewed |

## QED64 limitations found (documented with evidence; the gallery handles each)

* **L7: QED64's Lean runtime can freeze for good in `elaborating`. It was the audit's blocker.** Rewritten on
  2026-10-01 (close-out) from `out/hang/ROOT-CAUSE.md`, "Verification, second pass", which corrects the first
  analysis.
  * **Seen in** `out/ux/auditor-full` (work/logs/auditor-ux-full.log), C20 hasse-view link #30 (“{0} ⋖ {0, 2}”),
    about 75 edits into the session. The click made v60, which went to `elaborating` and never left it; the Reset
    120 s later made v61, also `elaborating`; the last status was `{phase: elaborating, relay: serving, lastDeath:
    null, workerDeaths: 0, reboots: 0}`.
  * **What it is: a runtime-wide freeze.** Every Lean pthread stopped at the same moment, about 83.0 s into the
    session: the pool read `8/17` before and after the v61 edit, no thread was created or ended for 450 s, and no
    output frame left the worker after 83.008 s, although the v61 bytes reached Lean's input ring. The worker's JS
    thread, which is the Emscripten main thread, kept running and kept sending status, so QED64's heartbeat
    (`src/runtime/client.ts` `armHeartbeat`, driven from that thread) never fired. The Emscripten main-thread proxy
    path had stopped servicing proxied calls. The pool froze because Lean's task manager calls `pthread_create`,
    which under Emscripten is a synchronous proxy to the main thread, while holding its global `m_mutex`: that
    creator waits forever with the lock held, and every other Lean thread blocks at its next task operation.
  * **The onset is an ordinary cycle.** The `-32800` (RequestCancelled) reply 29 ms after the click is routine: every
    run shows one per cycle (20–39 per session). The v60 progress reporter did run: two v60 `fileProgress` updates
    reached the editor at 82.85 and 83.0 s. There was no `[lean:stderr]` line, no death and no exception, which rules
    out a FileWorker error, exit or panic (each prints first).
  * **Likely trigger: one lost wake of the main-thread mailbox** (rated *likely*; the browser trigger is not
    observed). In Emscripten 6.0.5's `waitAsync` notification mode a single lost wake is permanent: a sender notifies
    only when the mailbox is not already marked pending, and only draining the mailbox clears that mark, so after one
    lost wake no later sender ever wakes it. The QED64 owner's fault injection E1 dropped exactly one wake and
    reproduced the signature (pool frozen at `12/12` for 180 s, 0 frames). A raw `__emscripten_check_mailbox()` did
    not revive it; the glue's `checkMailbox()`, which re-arms the waiter, did.
  * **Rate: 1 hang in about 20 C20 runs.** 1 in the 19 recorded C20 runs (`out/ux/*/tests/C20.json`, about 2,200 link
    clicks and 4,400 edits). The earlier "1 of 3" counted only the auditor's three attempts.
  * **Not caused by the widgets or the bridge** (ROOT-CAUSE §6): the panel RPCs are 1–3 of the 22–32 requests per
    cycle, the bridge's abortSignal strip creates no blocked task, and the same inserted text was clicked earlier in
    the same session without trouble.
  * **The fix is the QED64 owner's, in progress:** postMessage mailbox notifications with a periodic raw mailbox kick
    (a lost wake becomes a hiccup of at most about 1 s), and a Lean-level liveness reboot. Kernel patch 0035 (no
    `pthread_create` while holding `m_mutex`, parked-thread reuse) reduces the exposure but is not a cure: output still
    needs a proxied `fd_write`.
  * **How the gallery handles it now** (close-out): a **liveness probe** (`textDocument/hover` at 0:0, string id, full
    params, reply swallowed) runs after 10 s without progress; two probes unanswered within 5 s each mean wedged, and
    the gallery restarts the relay itself, keeping the text, with a small notice. The **45 s stall card** (Restart
    Lean, Reset example, Keep waiting) remains as the fallback. **Observe mode** (`?liveness=observe`,
    `UX_LIVENESS=observe` for the suite) records a wedge without restarting, and the harness's **hang capture** then
    records the frozen runtime for the owner (see "Liveness probe and hang capture"). The stock page's "Restart File"
    sends a document change, which a frozen runtime never processes.
  * **Pthread pool growth** past 24 in long sessions (25 from v43 in the hang session; 29–33 in the post-audit runs
    with 0 stalls) is common and is not by itself a hang.
* **L8: transient renderer peak in a reload storm. NEW, from the bytes fail line.**
  * C10 reloads the gallery 5 times in 12 s. While the dying page's heap is torn down and the next boot maps its own,
    one renderer briefly holds both.
  * Peaks: 10.92 GB (full6, over 10.5 GB for one 0.5 s sample, at 4.7 s) and 10.08 GB (full7). The pre-audit runs
    peaked at 11.17 GiB = 12.0 GB.
  * The settled value, 9.76–9.83 GB, is asserted below the line.
  * **Kill risk:** on a host where macOS kills the renderer at about 11 GB (the plan's figure), a storm of reloads
    during boot can reach that line: 10.9–12.0 GB were measured. A single reload (C2, C12) does not. On this 36 GB host
    no run crashed.
  * QED64 already terminates the old worker synchronously on `pagehide` (`relay.unload()` → `LeanSession.terminate()`).
    The remaining overlap is Chrome's asynchronous release of the dead isolates.
* **L3: no offline boot when the overlay index is unreachable** (C12b). Unchanged.
* **L4: the stock page does not surface SNAPSHOT_UNPAIRED**, and downloads the 32.6 MB init snapshot before refusing
  it (C9). Unchanged.
* **L5: "Load exact imports" cannot succeed for an `import Mathlib` header.** `Mathlib.olean` is not in the essential
  pack, so QED64 falls back to covered (C16). Renderer peak 9.75–11.26 GB on the way. Unchanged.
* **L6: no dark InfoView** (C13c). Unchanged.
* **Stock UX quirks.**
  * A refused header's diagnostic says `use "Load exact imports"`, but that button appears only for collisions.
  * `relay.restart()` reports "restarting with exact imports" for every restart, including the gallery's stall
    restarts.
  * In C11(b) the stock pill shows a green dot next to "could not start".

L1 (`reflect := true` on non-exposed core definitions) and L2 (pthread pool growth, worked around by D3) are unchanged
(`docs/HEADLESS-RESULTS.md`, gallery README). L2 now carries the correction above.

## Open issues

Updated by the final docs lane, the boot-fix lane and the closure lane (2026-10-03); docs/NEXT-STEPS.md is the list of what remains to
be done.

1. **L9 V2 on every pin, including the served C** ("Final gate"; docs/UPSTREAM-REPORT-QED64.md L9). The gallery cannot
   handle a renderer crash, and a gallery-side teardown on `pagehide` did not reduce it (v2mit A/B: headed 10/24 with
   it, 8/24 without). The UX suite's C10 (one 5-reload storm per run) has not crashed on C (19 runs, 17 full) or D (4),
   but the dedicated storms show V2 on A, C and D. **Per path on C** (README.md "Limitations", L9): the visitor's path,
   headed Chrome through `/showcase/`, 24/56 storms (43 %, Wilson 95 % 31–56 %), of which the latest window (v2-embed
   arm S, 2026-10-03, quiet host) 15/24 (62 %, 43–79 %) and the earlier ones 9/32; headed stock page 8/80; headless
   `/showcase/` 0/17. The pooled "2–3 per 26" of the final gate understates the visitor's risk. The extra V2 on the
   gallery entry comes mainly from embedding the page in an iframe at all (v2-embed lane below: 16/48 vs 4/48,
   p = 0.005), not significantly from the gallery's code (15/24 vs 10/24, p = 0.25), so a gallery-side fix cannot remove
   it. Upstream fix needed.
   *Historical:* L9 V1 blocked a two-green result on the 9fdf9b8 pin B (C10 crashed in 6 of the 8 runs that ran it, 5
   of 7 full runs); B is kept as evidence only and must not be deployed.
2. **L7 is QED64's**; C, B and D carry the owner's fix. No hang and no QED64 rescue in 23 C20 runs on C (3,105 clicks),
   4 on D (540) and 17 on B (2,295): too few to prove the fix. No pre-recovery capture of a real L7 is possible on these
   pins (QED64 recovers first; out/hang/FIELD-CAPTURE.md); the post-hoc record is exercised by C23. On A (no QED64
   liveness) the gallery's probe is the recovery; since the hardening lane its main-loop probe keeps a saturated pool
   from being restarted (C22 (3) green on A, `harden-A-c21c22`). A hang hunt is
   `UX_LIVENESS=observe npm run test:ux -- --grep C20`, repeated.
3. **Slow first visits: fixed by the boot-fix lane** (the 360 s boot timeout used to fire below about 16 Mbit/s and
   never clear; "Boot-fix lane" below). Because the fix changed `gallery/`, the new gallery needed its own verdicts and
   headed sign-off; whether they exist now is printed by `showcase.sh gallery` (history: the closure lane recorded both
   on `31f6d8d9…` and re-measured 10 Mbit/s ready at 565.1 s, "Closure lane" above). Residual, not measured: below about
   3.2 Mbit/s (docs/NEXT-STEPS.md §4).
4. **Headed sign-off on the deployed gallery: check with `showcase.sh gallery` / `pin list`.** History: none existed on
   `921b0b6a…`; Chrome for Testing passed C10 and C13 after the display-scale pin (`lastmile-cft-headed-c10c13`, 4/4),
   but no full headed run followed before the boot-fix lane changed the gallery; the closure lane's `closure-headed1`
   (34/34) is the first headed sign-off on `31f6d8d9…`. Branded Chrome 154 fails C13b
   (no per-build baseline) and C10's 10.5 GB settled line (10.67–10.75 GB).
5. **L8 kill risk** on hosts smaller than this one, during reload storms (documented, not fixable from the gallery
   without delaying every reload): C10's transient renderer peak was 11.8–12.2 GB in the final-gate runs, 11.80–11.84
   GB in `lastmile-full1/2`. The texts ask visitors for 16 GB of RAM; the soft warning still triggers below 8 GB.
6. The other bring-up audit 4 minors are unchanged: `questions.mjs` qN without `ok`, the one-slot edited-example
   store, and evidence files overwritten by default re-runs.
7. C4 can race in headed mode (the first card switch can finish before Playwright's slower headed second click). With
   the window on the 2x display the clicks came about 420 ms apart; with headed launches pinned to
   `--force-device-scale-factor=1` all 7 were `SUPERSEDED` again (`lastmile-chrome-headed2`). The assertion stays strict.
   The plan's new-headless project is still not configured; headed is a project (`UX_HEADED_ALL=1`).
8. Visual baselines are specific to this host's fonts and Chrome for Testing 151 (headless and headed sets); headed
   ones assume device scale 1 (now pinned).
9. Small known items, none blocking (moved here from docs/NEXT-STEPS.md):
   * QED64 N2 (`Session disposed.` rejection) and N3 (no favicon) are allowlisted narrowly; drop each entry when a
     pinned page has the fix.
   * `pin list` prints a headed sign-off as "NOT A VERDICT" (true, but it could say HEADED SIGN-OFF;
     `scripts/pin-switch.mjs` uses `whyNotVerdict` only).
   * The final-gate run records carry lane `showcase.sh` (`showcase.sh` reads `SHOWCASE_LANE`, not `LANE`); cosmetic.
   * `node scripts/ux-tally.mjs` counts runs by the active pin in `run-meta.json`, so A subset runs served through
     `UX_ORIGIN` count under C (Status, above).
   * On the hard capability card the rail footer badges keep their placeholder text ("QED64 …", "snapshot …");
     cosmetic, and a fix would have voided that gallery's verdicts.
   * `rpc-probe` hangs instead of exiting when the wasm runtime throws a filesystem error.
   * C's runtime headless store (`out/runtimes/wasm64-4b025db7729c5f89/headless`) holds only the control outputs and
     the summary, no per-package E1/E3 JSONs; run `showcase.sh headless all` on C (under the browser lock) if fresh
     per-package results are wanted.
   * Frozen read-only copies of QED64 exist for re-cloning after QED64 moves on: `$W/frozen-qed64-5ac5d00` (pin C) and
     `$W/frozen-qed64-3b42714` (pin D, including stage1 and the bump-0035b base tree).
10. Disk: run directories, traces and warm profiles take most of `out/ux` (58G by `du -sh out/ux` on 2026-10-03,
    logical size); docs/HOUSEKEEPING.md lists every large deletable item with its size and the exact command. Nothing
    was deleted.

## Static gates, bring-up re-check, hygiene (UX-suite lane, 2026-10-01; the counts have grown since)

* **Current (final docs lane, 2026-10-03, gallery `921b0b6a…`):** `BUILD-GALLERY CHECK OK 8 examples`,
  `CHECK-GALLERY OK 128 ok, 0 failed`, `SIM-GALLERY OK 101 ok, 0 failed` (`work/logs/finaldocs-gallery.log`,
  `finaldocs-verify.log`). The counts by lane: 108 / 56 (UX-suite lane, below), 123 / 80–86 (close-outs, docs lane), 128 /
  101 (hardening lane onward; the v2mit lane changed only check 7's expected string).
* As the UX-suite lane recorded it on 2026-10-01: `node scripts/build-gallery.mjs --check` → `BUILD-GALLERY CHECK OK 8
  examples`. `node scripts/check-gallery.mjs` → `CHECK-GALLERY OK 108 ok, 0 failed` (one new 8c test, `stallRestart`).
  `node scripts/sim-gallery.mjs` → `SIM-GALLERY OK 56 ok, 0 failed` (9 new checks: run 7, the watchdog).
* **The bring-up hints check, re-run with the rendered-text `checkPanel`:**
  `scripts/with-browser-lock.sh bringup-recheck node tests/ux/bringup/hints.mjs --tag hints-uxaudit` gave
  `HINTS OK 71/71`, `CONSOLE OK` (`work/logs/ux-hints-uxaudit.log`, `out/ux/bringup/hints-uxaudit.json`). It used a
  new tag, so the bring-up's own `hints.json` evidence is not overwritten. Two attempts before it did not test
  anything: one was refused by the foreign browser (`rc=76`); in the other I had not started the server
  (`HINTS FAIL 0/0`, `qed64 loads 0`).
* **No browser lock is left, and no server or browser of ours is running.** `out/.browser.lock` is absent;
  `curl :5190` returns `000`; the :5191/:5192 servers were stopped by C11 and by me. The mutant gallery copy and its
  profile (`work/mutantA-gallery`, `work/profiles/mutant-warm`, 2.0 GB) were removed.
* **Protected repos.** `scripts/assert-untouched.sh check s4` now reports `VERDICT: CHANGED`
  (`work/logs/ux-untouched-final.log`). This lane wrote nothing there. The changed paths belong to other sessions
  running on this host at the same time:
  * `wasm64-lean-fable/qed64/work/lv-r2-*.mjs` (25 paths). These are the scripts of the Claude session whose
    headless Chrome profiles are `…/-Users-fawadhaider-code-wasm64-lean-fable/d0d9da98-…/scratchpad/lv-profiles/r2/…`,
    the same foreign browsers that interrupted c20rep4;
  * the `wasm64-lean4game` working tree (2310 paths, mostly `client/dist/data/g/…`, a game-data build), plus its git
    diff.

  `wasm64-lean-kernel`, `wasm64-lean-kernel-build-v4.34.0` and `widgets-v4.34`: `OK no file newer than stamp`. Every
  write this lane made was under `qed64-showcase/` (gallery/, scripts/, tests/ux/, docs/, out/ux/) or in
  `/Users/fawadhaider/code/qed64-showcase-work/`.

