# L7 field capture: hang hunt on the 9fdf9b8 pin

> **Correction (docs lane, 2026-10-02; `node scripts/ux-tally.mjs`).** The C20 runs on 9fdf9b8 are **17**, not 16:
> the C20 of the first re-pin full run `repin-full1` (135/135) was not counted, so the total is 2,295 clean clicks.
> Rows 14–15 ("from its log only") have run directories after all: `out/ux/audit-cl3-full1` and `out/ux/audit-cl3-c20`
> (QED64 liveness 0 rescues and 0 `wedged` reboots in both files). Pin C `5ac5d00` (served since 2026-10-02) adds 7
> C20 runs (to `docs-full1`), all 135/135, with the same zeros. The hunt itself (8 observe-mode runs, 1,080 clicks) is unchanged.

Final lane, 2026-10-02 00:17–01:07Z. Pin: QED64 `9fdf9b85` / runtime `wasm64-2c18773ecfba45bb` / kernel `3ae65d36f9`. This
release contains QED64's L7 fix: a message-mode runtime mailbox, a 1 s raw mailbox kick with confirmed rescues, a
Lean-side liveness reboot (`wedged`), and kernel patch 0035. Gallery `7bbddf2e…`, overlay `widgets8`. Logs:
`work/logs/final-hunt.log` (driver) and `work/logs/final-final-hunt<N>.log` (one per run), with
`work` = `/Users/fawadhaider/code/qed64-showcase-work`. Run outputs: `out/ux/final-hunt<N>/tests/C20.json` and
`C20.c20-<pkg>.console.jsonl`.

**Verdict: no hang in 8 hunt runs (1,080 link clicks, 2,160 edits). Counting the two full runs of the same lane, none
in 10 C20 runs (1,350 clicks, 2,700 edits); counting also the final audit's two C20 runs and close-out 2's full run
(rows 11–13 below), none in 13 C20 runs (1,755 clicks, 3,510 edits); with the last audit's two C20 runs and close-out 3's
full run (rows 14–16), none in 16 C20 runs (2,160 clicks, 4,320 edits).** QED64's own liveness never acted: 0 rescues, 0 stalls, 0 `wedged`
reboots, and 0 `[liveness]` worker lines. The gallery's probe declared no wedge, and no capture was taken. There is
therefore no real hang to classify as A (lost mailbox wake) or B (not reached by a kick), and no field evidence for or
against hypothesis A. The sample is too small to show the fix works (see "What this does and does not show").

## Instrumentation

Every run was `UX_LIVENESS=observe UX_RUN=final-hunt<N> npm run test:ux -- --grep "C20 "` (driver
`work/logs/final-hunt.sh`: at most 8 runs, stop after 2 real hangs, 3 h budget; a lock or cooldown refusal is retried and
not counted). Each run took the host browser lock through `with-browser-lock.sh`, with a cooldown before every launch.
All 8 runs got the lock at once (`cooldown ok: 20.1–23.1 GiB reclaimable, no chrome-headless-shell`).

C20 clicks all 135 links the InfoView renders in the five examples that have links. Each click starts from the example
freshly reset through the gallery's Reset button, so every link is 2 edits. There is one warm-profile browser per
package (5 boots per run).

What would have recorded a hang, in the order it would fire on this pin:

1. **QED64's mailbox kick** (`lean.worker.js`, every 1 s). A lost runtime-mailbox wake that stays PENDING for the
   confirm window with nothing delivered is served by a raw kick and counted as a rescue. That is a hang of hypothesis
   A, caught and cured within about 1 s. It shows in two places:
   * `status().liveness.rescues`, which the gallery mirrors as `status().liveness.qed64.totals.rescues`. C20 now
     records it per package as `qed64Liveness` and in total as `m.qed64Liveness`.
   * The worker line `[lean:stderr] [liveness] a runtime-mailbox wakeup was lost … rescue #n` in the session's
     console log.
2. **QED64's Lean-side liveness.** It sends a probe after 6 s with no server frame while work is owed, declares a stall
   12 s later (`[liveness] probe unanswered …`, `stalls`), and dies `wedged` about 22–25 s after the last frame. The
   relay then reboots with `rebootReason: wedged`. That is an L7 occurrence that the kick did not reach (hypothesis B,
   or A with a C-level task), handled upstream. The gallery counts these reboots as `qed64.wedgedReboots`.
   **Since the close-out-2 lane** (after the final audit) C20 and W1–W8 accept such a reboot as an L7 occurrence
   handled upstream instead of failing on `relay.reboots ≠ 0`: each must be exactly one `wedged` death plus its
   reboot, it is printed (`C20 <pkg>: L7 OCCURRENCE handled by QED64 …`) and counted (`m.l7HandledUpstream`), and
   the link's click writes a **post-hoc** record, `out/hang/captures/<run>-<iso>-qed64-wedged.json`
   (`tests/ux/lib/qed64.mjs` `captureQed64Reboot`: the gallery's `qed64.lastReboot` and `qed64-*` events, QED64's
   counters, `qed64.status()` with `lastDeath`, and every worker / `[lean:…]` line with the `[liveness]` lines listed
   separately). **A hang QED64 handles yields no pre-recovery capture.** QED64 reboots about 22–25 s after the last
   frame, before the gallery's observe-mode wedge (30 s + 2 × 5 s), so by the time anything outside could look, the
   frozen runtime is gone: there is no telemetry race and no mailbox kick to record, only what QED64 itself logged.
3. **The gallery's own probe in observe mode.** On a page with QED64 liveness it waits for 30 s of `elaborating` with
   no progress (`probeDeferMs`). It never probes while QED64 reports a stall, and two unanswered hovers declare a wedge
   (action `observed`, no restart). After that, `captureHang` (`tests/ux/lib/qed64.mjs`) runs before anything is reset:
   * (a) the gallery and QED64 status, plus the pool;
   * (b) `telemetry()` raced against 10 s;
   * (c) the worker and `[lean:…]` console lines, written to a `.worker-console.log` file;
   * (d) one raw `__emscripten_check_mailbox()` in each eligible worker, with a 15 s watch, then one `checkMailbox()`
     in the main-thread worker, with another 15 s watch.

   The result is written to `out/hang/captures/<run>-<iso>.json`. A link that is "not ready within …" after its click is
   captured in any mode. On this pin, layer 3 fires only if QED64's own layers 1–2 both missed the freeze.

Per run, the table records:

* the C20 result and the click and edit counts (`docVersions`);
* card stalls and gallery wedges;
* QED64's rescues, stalls and `wedged` reboots;
* the `[liveness]` lines (`grep` over `C20.*.console.jsonl`);
* the boot line `[boot] runtime mailbox: message notifications (no Atomics.waitAsync); proxied calls counted; FileWorker
  exit hooked`, found once per boot, which proves the fix was live in every session and that worker stderr reaches the
  log the grep reads;
* relay deaths, reboots and restarts;
* the pthread pool maxima (`running` / `unused + running` / `parked` after each link).

## On this pin the hunt cannot produce a pre-recovery capture (close-out 3)

Stated plainly: **on QED64 9fdf9b8 no hang hunt run through the gallery can capture a real L7 before it is recovered.**
The capture steps (a)–(d) above, telemetry and the two mailbox kicks, can only ever run on the synthetic C21 fixture.
The reasons, each checked:

* **QED64 recovers first, and by design.** Its worker serves the runtime mailbox every 1 s, so a lost wake (hypothesis A)
  is healed within about 1.25 s (`tickMs` 1000 + `confirmMs` 250, `lean.worker.js` `LIVENESS`, line 351), before any
  outside observer could notice. What the kick does not reach is killed by QED64's Lean-side liveness about 22–25 s
  after the last server frame (`probeAfterMs` 6000 + `wedgeAfterMs` 12000 + `graceMs` 4000). The gallery's observe-mode
  wedge comes at about 40 s (30 s deferral + 2 × 5 s), so the session is already gone.
* **The page has no option to switch QED64's liveness off or slow it down.** The served bundle reads exactly three query
  parameters, `profiles`, `runtime` and `snapshots` (`grep -o 'URLSearchParams(location.search).get(...)'` on
  `release/wasm64-2c18773ecfba45bb/dist/assets/index-Jv35CWTg.js`: one each, nothing else; `qed64-boot.ts:58,74,100`).
  `dist/workers/lean.worker.js` reads no query string at all (0 matches), its `LIVENESS` constants are fixed, and
  `startLiveness()` runs on every loop open (line 676).
* **The only remaining lever is not used.** The harness could call `stopLiveness()` inside the worker
  (`worker.evaluate`; the worker is a classic script, so its top-level functions are globals, as C23 uses) after every
  session start. That removes two of the four layers of the fix under test, so a hang captured that way would be a hang
  of a modified runtime, not field evidence for this pin. It is listed for the owner as a possible drill, not done.

What a real QED64-handled L7 yields instead is the **post-hoc record** (`captureQed64Reboot`, layer 2 above): QED64's
`lastReboot` with its `lastDeath`, its liveness counters (rescues so far), the `qed64-*` events and every worker
`[liveness]` line. Until close-out 3 that path had only a console-classifier unit test. **It is now exercised in the
browser by UX test C23**, a labelled fixture: inside QED64's own `lean.worker.js` it runs what `livenessStep` runs when its
detector decides "dead" (`livenessLog(...)`, then `die(null, "wedged", ...)`) about 0.8 s after a declared HasseView
click; everything downstream is real (the relay's `failInFlight` and reboot with replay, the gallery's `qed64-wedged` /
`qed64-rebooted` events and notice, `clickLink` → `captureQed64Reboot`). Run `closeout3-c23b`
(`work/logs/closeout3-c23b.log`): the gallery counted 1 `wedged` reboot (s1 → s2, `lastDeath {reason: wedged}`) and
restarted nothing, the relay had 1 death, 1 reboot and 0 user restarts, the post-click text re-checked clean on s2 in
8.9 s, and `out/hang/captures/closeout3-c23b-2026-10-02T04-13-49-131Z-qed64-wedged.json` was written with
`synthetic: true` ("NOT L7 evidence") and the worker's `[liveness] [fixture] …` line. The same test found a harness bug
that would have failed C20 on its first real QED64-handled hang: `clickLink` required 0 worker deaths per click, so the
accepted `wedged` death marked the link failed (`ok: false`, misleading error "0 errors / 0 warnings after the click",
run `closeout3-c21c22c23`). It now allows exactly one death per `wedged` reboot the gallery saw during the click.

## Hunt table

Rows 1–2 are the C20 of the lane's two full runs (default `auto` mode, `docs/UX-RESULTS.md` "Final verification"); rows
3–10 are the hunt; rows 11–12 are the final audit's full run and its extra observe-mode C20 run, and row 13 is close-out 2's
full run, with close-out 2's gallery (proof of life besides the hover) and C20 accounting (a QED64 `wedged` reboot is
accepted and recorded post hoc); neither came into play in that run (0 gallery probes, 0 QED64 reboots). Rows 14–15 are
the last audit's two C20 runs; their run directories are no longer in `out/ux`, so they come from the `C20 …` summary
lines of `work/logs/audit-final-full1.log` and `work/logs/audit3-c20.log` (135/135, QED64 liveness all 0, captures
`[]`; the console columns are unknown). Row 16 is close-out 3's full run (proof of life from Lean frames only; C20's
`clickLink` now accepts the death of a QED64 `wedged` reboot), produced by `work/logs/closeout2-hunt-rows.mjs`.

| Run | C20 start | Liveness mode | Clean | Clicks | Edits | Card stalls | Gallery wedges | QED64 rescues | QED64 stalls | QED64 `wedged` reboots | `[liveness]` lines | Mailbox boot line | Relay deaths / reboots / restarts | Pool max running / total / parked | Captures | C20 wall |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| final-full1 | 23:21:58Z | auto | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 5/5 | 0/0/0 | 30 / 30 / 8 | 0 | 368.5 s |
| final-full2 | 23:56:40Z | auto | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 5/5 | 0/0/0 | 28 / 31 / 8 | 0 | 371.3 s |
| final-hunt1 | 00:17:32Z | observe | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 5/5 | 0/0/0 | 29 / 31 / 8 | 0 | 367.0 s |
| final-hunt2 | 00:23:41Z | observe | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 5/5 | 0/0/0 | 28 / 30 / 8 | 0 | 370.2 s |
| final-hunt3 | 00:29:53Z | observe | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 5/5 | 0/0/0 | 29 / 30 / 8 | 0 | 371.6 s |
| final-hunt4 | 00:36:07Z | observe | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 5/5 | 0/0/0 | 28 / 29 / 8 | 0 | 378.3 s |
| final-hunt5 | 00:42:28Z | observe | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 5/5 | 0/0/0 | 29 / 30 / 8 | 0 | 372.4 s |
| final-hunt6 | 00:48:43Z | observe | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 5/5 | 0/0/0 | 28 / 30 / 8 | 0 | 367.4 s |
| final-hunt7 | 00:54:52Z | observe | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 5/5 | 0/0/0 | 28 / 32 / 8 | 0 | 367.3 s |
| final-hunt8 | 01:01:02Z | observe | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 5/5 | 0/0/0 | 27 / 31 / 8 | 0 | 366.9 s |
| audit-final-full (final audit) | 01:17:06Z | auto | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 5/5 | 0/0/0 | 30 / 30 / 8 | 0 | 366.7 s |
| audit-final-c20 (final audit) | 01:37:46Z | observe | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 5/5 | 0/0/0 | 30 / 32 / 8 | 0 | 368.1 s |
| closeout2-full1 (close-out 2, gallery `7772c1eb…`) | 02:48:38Z | auto | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 5/5 | 0/0/0 | 28 / 30 / 8 | 0 | 368.5 s |
| audit-final-full1 (last audit; from its log only) | – | auto | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | – | – | – | 29 / 30 / 8 | 0 | 6.1 min |
| audit3-c20 (last audit; from its log only) | – | observe | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | – | – | – | 28 / 30 / 8 | 0 | 6.1 min |
| closeout3-full1 (close-out 3, gallery `92027286…`) | 04:18:51Z | auto | 135/135 | 135 | 270 | 0 | 0 | 0 | 0 | 0 | 0 | 5/5 | 0/0/0 | 30 / 32 / 8 | 0 | 365.8 s |
| **all 13 C20 runs on 9fdf9b8 with run files (rows 1–13)** | 2026-10-01 23:21Z – 10-02 02:55Z | | **1755/1755** | **1755** | **3510** | 0 | 0 | **0** | 0 | **0** | 0 | 65/65 | 0/0/0 | max 30 / 32 / 8 | 0 | |
| **all 16 C20 runs on 9fdf9b8** | to 10-02 04:25Z | | **2160/2160** | **2160** | **4320** | 0 | 0 | **0** | 0 | **0** | 0 (14 runs with files) | 70/70 (14 runs) | 0/0/0 (14 runs) | max 30 / 32 / 8 | 0 | |
| **hunt total** | 00:17–01:07Z | | **1080/1080** | **1080** | **2160** | 0 | 0 | **0** | 0 | **0** | 0 | 40/40 | 0/0/0 | max 29 / 32 / 8 | 0 | 49.7 min in all |

Generated from the C20.json files (`work/logs/final-hunt-table.md`; rows 11–13 by
`work/logs/closeout2-hunt-rows.mjs`, which reproduces rows 1 and 3 exactly). Each hunt log ends `1 passed (6.1m)`–`(6.3m)`, and
the driver ends `HUNT DONE runs-through=8 hangs=0 elapsed=2980s`. No `chrome-headless-shell` crash report was written
during the hunt: the last ones are 20:03:57 and 20:13:10 EDT, both from `final-full2`'s C21 and C10 (L9, not L7). QED64's
own probe count stayed at 0 throughout. This agrees with the re-pin lane's in-worker reading: during a busy gallery
session the editor and the InfoView keep frames flowing about once a second, so QED64's 6 s probe has no reason to fire.

## Real hangs

None. For each real hang the template asks: telemetry answered?, resumed after `__emscripten_check_mailbox()`?, resumed
after `checkMailbox()`?, last worker stderr, pool, and verdict A or B. None of these can be filled in. The only capture
this lane produced is **synthetic**:

* `out/hang/captures/final-full1-2026-10-01T23-29-53-764Z.json`, from C21 (b)'s fixture, which detaches the session's
  output inside the page. It is labelled `synthetic: true`, "NOT L7 evidence", and proves only that the capture path
  works on the new pin.
* Telemetry answered in 0 ms and reported the worker `ready`. 33 `[lean:stderr]` lines were captured.
* 26 workers: 10 answered and 16 were blocked. The raw `__emscripten_check_mailbox()` was called once in
  `/workers/lean.worker.js` (the Emscripten main thread, `pthreadSelf` 6770928, pool `{unused 8, running 16}`). The
  15 s watch showed no resume. `checkMailbox()` was then called once (0.01 ms), and the 15 s watch again showed no
  resume. That is expected for a JS-level freeze.
* The capture took 33.1 s.
* On this pin the gallery's observe-mode wedge came 40.75 s after the last progress: the 30 s deferral plus 2 × 5 s.

## What this does and does not show

* **The fix was live and quiet.** Every one of the 50 C20 sessions logged the message-mode mailbox boot line, so the
  instrumentation was on the code path where QED64 would have counted a lost wake. In 2,700 edits over 10 runs it never
  needed to: 0 rescues, 0 stalls, 0 reboots.
* **This is not proof that L7 is gone.** On the previous pin the rate was about 1 hang in 20 C20 runs (1 in 19
  recorded runs). If that rate still applied, 10 runs with no hang would happen with probability 0.95^10 ≈ 0.60 (13 runs:
  0.95^13 ≈ 0.51; 16 runs: 0.95^16 ≈ 0.44), so the result cannot tell "fixed" from "as before". The same holds for hypothesis A: under A, a lost wake on this pin shows
  up as a rescue instead of a hang. Seeing no rescues is likewise consistent with A, with the fix, or with the trigger
  simply not occurring in 10 runs. Telling them apart at the old rate needs on the order of 60 clean runs
  (0.95^60 ≈ 0.05), or the owner's own fault drills. Commit `0c4478a`, "rescues confirmed from the mailbox's own
  notification word; drills fixed", is the owner's evidence that the rescue counter fires on a dropped wake. This lane
  did not inject a fault into the stock runtime.
* **The pool now runs fuller.** Across the 10 C20 runs, the per-link samples show running 16–30 and total 24–32, with up
  to 8 parked (the parked dedicated threads of kernel 0035). On the previous pin, C20 showed running 9–22 and total 24–31
  (`closeout-full1`, `full6`, `full7`, `c20rep5`). Totals of 30–32 were the L2 crash band on the old pin. No C20 session crashed, but the same isolate pressure is the leading suspect
  for L9 (docs/UPSTREAM-REPORT-QED64.md).
* **How to extend the hunt:** run the driver again with `HUNT_START=9` (it numbers runs from there; edit the `-le 8`
  bound), or run `UX_LIVENESS=observe UX_RUN=huntN npm run test:ux -- --grep "C20 "` directly. Each run takes about
  6.2 min when the lock is free.
