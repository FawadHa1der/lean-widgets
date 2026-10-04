# Last-mile verification: served pin C `5ac5d00`, gallery `921b0b6a…` (current then) (2026-10-03, 00:59–03:38 UTC)

Lane `lastmile`. Every browser command ran under `scripts/with-browser-lock.sh`; logs are `$W/logs/lastmile-*.log`
(`$W` = `/Users/fawadhaider/code/qed64-showcase-work`); run outputs are `out/ux/lastmile-*/`. Nothing under the QED64,
kernel, lean4game or widgets-v4.34 trees was written, and no system or security setting was changed. The macOS screen
was locked for the whole lane (`ioreg` `CGSSessionScreenIsLocked` true, locked since 00:06:22Z; it was checked at the
start, before each headed run (`lastmile-chrome-headed{1,2}.lockstate`) and at the end).

## Gate

| Item | Result |
|---|---|
| (1) Two consecutive full `showcase.sh ux` runs on that lane's gallery `921b0b6a…` | **VERDICT, VERDICT**: `lastmile-full1` (01:03–01:24Z) and `lastmile-full2` (01:24–01:45Z), each 33 passed, 1 skipped (C19); `showcase.sh gallery` → `UX CURRENT … lastmile-full2` |
| (2) Headed sign-off in the installed branded Google Chrome | **Not a sign-off. Exact reasons below.** Branded Chrome 154.0.8037.97 launched through Playwright channel `chrome` (nothing installed). Best run `lastmile-chrome-headed2`: 32/34, C19 included. The two failures are C13b (a 390 px mobile screenshot where Chrome 154 draws no classic scrollbars; the headed baseline, made with Chrome for Testing 151, has them) and C10 (settled renderer RSS 10.68 GB > the 10.5 GB line; 3 of 3 branded runs over it, 2 of 2 Chrome for Testing runs under it) |
| (3) Safari 26.6 | **Tried, refused, nothing changed.** `safaridriver` answered `/status` ready, `POST /session` → HTTP 500 `session not created: … You must enable 'Allow remote automation' in the Developer section of Safari Settings to control Safari via WebDriver.` One-time user action below. |
| (4) Throttled first visit | **Recorded.** 50 Mbit/s, 40 ms RTT: ready in 123.3 s, progress visible throughout, no error card. 10 Mbit/s: **defect**. The gallery's 360 s boot timeout shows "This is taking too long" at 467 s while QED64 is still downloading normally. QED64 is ready at 577 s, but the gallery never leaves the error state (watched to 1200 s). |
| (5) Soak ≥ 20 min | **PASS**: 22.1 min, 66 ticks (8 full cycles of all 8 widgets), 173 operations, 0 failed, no crash, no stall. Renderer RSS 8.14 → 8.23 GiB per-cycle max (cycle 2 → 8); slope +7 MB/min (R² 0.75) and flattening; the wasm heap held at 2.00 GiB |

## (1) Two verdicts on that lane's gallery `921b0b6a…`

`SHOWCASE_LANE=lastmile UX_RUN=lastmile-full{1,2} scripts/showcase.sh ux` (logs `lastmile-full1.log`,
`lastmile-full2.log`; chain rc in `lastmile-full-chain.log`: both rc=0). Records in `out/ux/showcase-ux-runs.jsonl`, judged
by `node scripts/lib/ux-record.mjs verdict` → `VERDICT`, `VERDICT` (`lastmile-verdicts.log`).

| Run | Window (UTC) | Tests | C3 peak | C10 | C20 |
|---|---|---|---|---|---|
| `lastmile-full1` | 01:03:10–01:24:17 | 33 passed, 1 skipped (C19) | 9.84 GB | no crash; transient peak 11.84 GB, settled 9.74 GB | 135/135, 0 stalls, 0 liveness restarts, 0 wedged |
| `lastmile-full2` | 01:24:17–01:45:23 | 33 passed, 1 skipped | 9.85 GB | no crash; peak 11.80 GB, settled 10.12 GB | 135/135, 0 / 0 / 0 |

Both runs: pin C `5ac5d00 wasm64-4b025db7729c5f89` served from start to end, gallery `921b0b6ac801e044…` local ==
served at start and end. Afterwards `showcase.sh verify` → `VERIFY: all checks OK` (1 known Docker DRIFT, rebuild-only)
and `showcase.sh gallery` → `CHECK-GALLERY OK 128 ok`, `SIM-GALLERY OK 101 ok`, gate GREEN, `UX CURRENT … lastmile-full2`
(`lastmile-verify-end.log`, `lastmile-gallery-end.log`). `node scripts/ux-tally.mjs` lists both runs as VERDICT
(`lastmile-ux-tally.txt`).

## (2) Headed run in the installed branded Google Chrome

**Harness additions (inert unless enabled).** `tests/ux/lib/qed64.mjs`: `UX_CHANNEL=chrome` (only with
`UX_HEADED_ALL=1`; anything else throws) makes every headed launch, and C19, use Playwright channel `chrome`.
`chromeRss()` then counts only the Chrome processes descended from the test process, because branded Chrome does not
live under `ms-playwright` and a visitor's own Chrome must never be counted. `global-setup.mjs` records `channel` in
`run-meta.json`. `showcase.sh ux` adds `channel` to the run record. Pre-edit copies are in `$W/lastmile/pre-edit/`.

Command: `SHOWCASE_LANE=lastmile UX_RUN=<run> UX_HEADED_ALL=1 UX_CHANNEL=chrome
UX_WARM_PROFILE=$PWD/out/ux/profiles/ux-warm-chrome-headed scripts/showcase.sh ux`. C19 records the UA
`… Chrome/154.0.0.0 …`. `ps` showed `/Applications/Google Chrome.app/…/154.0.8037.97/…` helpers during the run.

| Run | Tests | Failed |
|---|---|---|
| `lastmile-chrome-headed1` (01:46–02:08Z) | 29 passed, 5 failed | C4, C10, C11, C13a, C13b |
| `lastmile-chrome-headed2` (02:11–02:33Z), after the display-scale fix below | **32 passed, 2 failed** (C19 passed; C20 135/135; C14 hygiene passed) | C10, C13b |
| `lastmile-chrome-headed-c10c13` (03:34Z, `--grep "C10 \|C13"`) | 2 passed, 2 failed | C10, C13b |
| `lastmile-cft-headed-c10c13` (03:32Z, same subset, Chrome for Testing 151) | **4 passed** | – |

Root causes, each from a command or an image comparison in this lane:

* **C11 in headed1 was caused by this lane, not by Chrome.** C11 starts its own CHAOS server on :5191. I had started a
  plain `serve.mjs` on :5191 for my own experiments, so C11's `startServer` reported `already running pid 38986` and no
  cut happened (`once.cuts` 0). Its `stopServer` then stopped my server. All later experiments used :5197 and :5198.
  C11 passed in headed2.
* **C13a/C13b in headed1, and the earlier `v2mit-headed1` failures: the display scale, not the locked screen and not
  the browser build.** A headed window rasterises glyphs for the real display it opens on, even with
  `deviceScaleFactor: 1` emulated:
  * Branded Chrome 154's failing C13 images are pixel-identical (0 differing pixels) to Chrome for Testing 151's
    failing images in `v2mit-headed1`. A fixed text page renders identically in both headed builds
    (`out/ux/lastmile-envprobe/`).
  * With the screen locked, both report hardware-accelerated compositing and rasterisation (chrome://gpu), a 2x Retina
    real display (devicePixelRatio 2 in a context without emulation), rAF at 120 Hz and a 17 ms median
    `locator.click()` (`lastmile-timing.log`). So the locked-screen hypothesis is not supported.
  * Decisive: `tests/ux/tools/c13-dsf-probe.mjs` (same shots as C13a hasse-view, same masks). Without flags, the panel is
    443x629 and equals the failing runs' image exactly. With `--force-device-scale-factor=1`, the panel is 444x630 and
    **pixel-identical to the headed baseline**, and the gallery differs in 635 px (0.049 %) (`lastmile-c13dsf.log`,
    `out/ux/lastmile-c13dsf/`).
  * Inference, not proven: the headed baselines (written 2026-10-02 18:45Z) and the passing headed runs were made with
    the window on a 1x display.

  **Fix (headed only):** `launch()` adds `--force-device-scale-factor=1` to every headed launch, so the headed baselines
  hold on any display. The baselines and assertions are unchanged, and headless launches get exactly the arguments they
  had. Chrome for Testing 151 headed then passes C13a and C13b (`lastmile-cft-headed-c10c13`), and branded Chrome passes
  C13a.
* **C4 in headed1: the same display effect, via click timing.** The storm's clicks landed at 38/454/532/957/… ms
  (graph-scope settled `ok` before the 454 ms click). `v2mit-headed1` had the same ~420 ms gaps. In headed2, with the
  display pinned, they landed at 38/289/530/781/… ms and all 7 were `SUPERSEDED`. That matches the passing headed runs
  (`final-C-headed1` 76/351/801/…). The assertion is unchanged.
* **C13b in branded Chrome: a browser-build difference.** With the display pinned, the 390x844 mobile-emulated gallery
  differs from the headed baseline in 3,878 px (1.18 % > the 1 % limit). All glyphs match. The baseline has classic
  gray scrollbars at the right and bottom edges, and Chrome 154 draws none. Chrome for Testing 151 passes the same test
  in the same session (`lastmile-cft-headed-c10c13`), so this is Chrome 154 vs 151 under mobile emulation, not the host
  (my first guess, the macOS automatic scroller style, is refuted by that run). macOS's per-process override
  (`-AppleShowScrollBars Always`) cannot be passed: Playwright refuses a bare value argument ("Arguments can not specify
  page to be opened"). Not masked, which would weaken the assertion. Needs a baseline per browser build (owner
  decision).
* **C10 in branded Chrome: the settled renderer RSS is over the 10.5 GB fail line.** No crash in any run. Figures
  (`tests/C10.json` `after.rss`; sum = all renderers of the test's browser, page = the largest):

  | Run | Browser | settled sum | page renderer | renderers | transient peak |
  |---|---|---|---|---|---|
  | `lastmile-chrome-headed1` | Chrome 154 headed | **10.67 GB** | 10.38 GB | 3 | 12.28 GB |
  | `lastmile-chrome-headed2` | Chrome 154 headed | **10.68 GB** | 10.39 GB | 3 | 12.14 GB |
  | `lastmile-chrome-headed-c10c13` | Chrome 154 headed | **10.75 GB** | 10.45 GB | 3 | 10.75 GB |
  | `lastmile-cft-headed-c10c13` | Chrome for Testing 151 headed | 10.07 GB | 9.97 GB | 2 | 11.95 GB |
  | `final-C-headed1` (earlier lane) | Chrome for Testing 151 headed | 10.26 GB | 10.16 GB | 2 | 12.03 GB |
  | `lastmile-full1` / `-full2` | chrome-headless-shell 151 | 9.74 / 10.12 GB | same | 1 | 11.84 / 11.80 GB |

  Branded Chrome runs two small extra renderers (182 MB and 97 MB in `ps` during headed2), and its page renderer
  settles 0.3–0.4 GB higher than Chrome for Testing's. Both are measured, and C10's line applies to the summed figure as
  it always has. Not changed: this is a real memory difference of the visitor's browser, 0.17–0.25 GB over a line that
  sits about 0.5 GB below the macOS kill seen at about 11 GB.

**One-time action to finish a branded sign-off:** decide between (a) headed baselines per browser build, e.g. written
by `UX_HEADED_ALL=1 UX_CHANNEL=chrome … ux --grep C13 --update-snapshots` into a separate directory and viewed before
use, and (b) accepting C10's line for branded Chrome or raising it. Both are owner decisions, and neither was made here.

## (3) Safari 26.6.2 (macOS 26.6.2)

`tests/ux/tools/safari-probe.mjs` (under the lock; `lastmile-safari.log`, `out/ux/lastmile-safari/explore/safari-s1.json`).
It started `/usr/bin/safaridriver -p 4445`; `GET /status` → `{"ready": true}`; `POST /session` with
`browserName: safari` → HTTP 500 `session not created`, quoted above. Nothing else was tried: `safaridriver --enable`
and Safari's setting were not touched. A read-only `defaults read com.apple.Safari AllowRemoteAutomation` says the key
does not exist. The probe stopped the driver, and no `safaridriver` was left running.

**One-time user action:** Safari → Settings → Advanced → "Show features for web developers", then Developer →
"Allow remote automation" (and, if macOS asks, authorise once with `safaridriver --enable`, which needs an admin
password). Then run
`UX_RUN=lastmile-safari scripts/with-browser-lock.sh lastmile-safari node tests/ux/tools/safari-probe.mjs --url http://localhost:<port>/showcase/`
against a running `serve.mjs`.

**What a Safari visitor would most likely see (an inference, not observed in Safari):** the system JavaScriptCore shell
(`/System/Library/Frameworks/JavaScriptCore.framework/…/jsc`, macOS 26.6.2) rejects the gallery's own 13-byte Memory64
probe: `WebAssembly.validate` → `false`; `SharedArrayBuffer` exists; a `Memory` with `address: 'i64'` is silently
built as 32-bit (`lastmile-jsc-memory64.log`). The gallery's `checkCapabilities` would therefore show the card "This
browser cannot run the Lean widget gallery … your browser lacks WebAssembly Memory64" and fetch nothing.

## (4) Throttled first visit (fresh profile, chrome-headless-shell 151)

**CDP network emulation does not reach QED64's downloads.** First attempt, `throttle-t50`
(`tests/ux/tools/throttled-first-visit.mjs`): a raw CDP client on `--remote-debugging-port` auto-attached to all 29
targets and applied `Network.emulateNetworkConditions` (50 Mbit/s, 40 ms). The page target accepted it, and page
requests ran at 41–49 Mbit/s. Every worker session answered `Network.emulateNetworkConditions: Not supported`. QED64's
lean worker fetched the runtime and snapshots (556 MB) at 15,807–21,181 Mbit/s, so the page was "ready" in 35.1 s. That
run is not a 50 Mbit/s measurement. It is kept only as evidence of the limitation (`out/ux/lastmile-throttle/explore/throttle-t50.json`).

**The link was therefore shaped below the browser:** `tests/ux/tools/throttle-proxy.mjs` sits between the browser and
`serve.mjs` (:5198 → :5197). Every connection waits one RTT. Uplink bytes are delayed RTT/2. Downlink bytes are delayed
RTT/2 and paced by one token bucket shared by all connections, with backpressure. Headers pass through unchanged (COOP,
COEP, CORP and `X-Showcase-Pin` checked with curl). Check with curl at 50 Mbit/s: a 16 MiB chunk took 2.78 s =
48.3 Mbit/s, TTFB 103 ms. At 10 Mbit/s: 15.4 MB at 9.9 Mbit/s. CDP was then used only to time requests. Sampled every
1 s: the gallery veil, QED64's boot card in the iframe (`#boot`, `#bootlabel`, `#bootnums`, `#bootfill`), the error card
and the phases. Screenshots every 10 s (50 Mbit/s) or 30 s (10 Mbit/s).

| Link | Ready | What the visitor saw | Error card | Bytes |
|---|---|---|---|---|
| **50 Mbit/s, 40 ms** (`throttle-p50`, 02:46Z) | **123.3 s** (gallery ready; QED64 elaborating at 121.3 s) | 0 s: the gallery's "Loading the gallery…" card. 1–123 s: QED64's boot card with step list, label, MB / total, rate and time left (e.g. 80 s: "preparing the mathlib environment … 256 MB / 1.18 GB · 16.1 MB/s · ~59 s left"). Visible in 122 of 123 samples; the one miss is t = 0.145 s, when the veil was fading in (the 0 s screenshot shows the loading card). Longest stretch with no visible change: 5.0 s (Verifying lean.js) | none | 709.8 MB at 46.4 Mbit/s aggregate (page 135 MB, worker 573 MB; proxy: 727 MB, 45.2 Mbit/s over the transfer) |
| **10 Mbit/s, 40 ms** (`throttle-p10`, 02:49Z) | **never** (QED64 itself ready at 577.1 s) | 1–230 s: QED64's boot card with bytes, rate and time left. **231–466 s: the boot card is gone.** QED64 removes its overlay 120 s after an idle status starting with "ready" (bundle: `/^ready/.test(n)&&window.setTimeout(pX,12e4)`; the editor opened at about 115 s; inferred from code plus timing). Only the editor with an empty InfoView, QED64's top-bar pill (stage plus an elapsed timer, e.g. "preparing the mathlib environment (1.2 GiB — one-time) · 3m 37s") and the gallery status line ("Starting Lean in your browser… 330 s") remain. No bytes or percentage | **from 466.9 s to the end (1200 s):** "This is taking too long — timed out after 360 s waiting for ChartKit to be checked (first boot). The page may still be working; the status line keeps updating." The gallery stays in phase `error` with the chip "error" and the status "Something went wrong" after QED64 is `ready` at 577 s; it does not recover by itself | 708.4 MB at 9.9 Mbit/s over 574.5 s |

Screenshots: `out/ux/lastmile-throttle/screens/throttle-p50-*.png`, `throttle-p10-*.png` (e.g. `throttle-p10-0241s.png`:
editor, no boot card; `throttle-p10-error-467s.png`: the card over the editor). The console oracle was OK in both runs,
with no crash.

> **Update (boot-fix lane, 2026-10-03):** fixed in `gallery/gallery.js` (progress-aware first boot, notice instead of
> the card, late `ready` recovers); the same 10 Mbit/s run on the fixed gallery is ready at 565 s with no error card and
> the panel equal to its golden (`out/ux/bootfix-throttle/explore/throttle-p10b.json`; docs/UX-RESULTS.md "Boot-fix
> lane"). The text below is this lane's record as written.
>
> **Update (closure lane, 2026-10-03):** `throttle-proxy.mjs` could reorder bytes within one connection. Each 64 KiB
> slice had its own timer, and Node starts a timer from the cached loop time, so slices scheduled in different callbacks
> could fire out of order. The fix keeps a FIFO per connection. In the closure lane this corrupted one 50 Mbit/s first
> visit (QED64's raw prefetch: "invalid code lengths set", then it streamed the snapshot and still booted), and a
> small-write order test broke order in 6 of 6 runs. The p50/p10 runs below had the console oracle OK (no prefetch
> error), so their bytes arrived intact (inference). On the fixed proxy and the boot-fixed gallery `31f6d8d9…`, the
> closure lane measured 50 Mbit/s ready at 120.3 s (here: 123.3 s) and 10 Mbit/s ready at 565.1 s with no error card
> (`out/ux/closure/RESULTS.md` (3)).

**Defect (gallery, `gallery/gallery.js`):** `BOOT_TIMEOUT_MS = 360000` counts from the hook. Below about 16 Mbit/s,
QED64's own first-visit download (about 710 MB) needs longer, and `waitReady` throws `TIMEOUT` while QED64 is healthy
and still downloading. Once the error card is up, a later `ready` is not picked up. Suggested fix (not made; it changes
the gallery and voids the verdicts): while QED64's phase is `booting` and bytes are still arriving, keep waiting (or
re-arm the timeout on progress), and when QED64 later reaches `ready`, close the timeout card and finish the boot. A
test for it is the 10 Mbit/s run above. Also QED64's (stock) boot card disappears mid-download on slow links, and its
card text says "~3 GB of memory" while a tab measures 8–9 GB; both are QED64's to change.

## (5) Soak: one tab, 22 minutes, all eight widgets

`tests/ux/tools/soak.mjs --minutes 22` (chrome-headless-shell 151, fresh profile, `/showcase/` on :5197;
`lastmile-soak.log`, `out/ux/lastmile-soak/explore/soak-s22.json`, screenshots `screens/soak-s22-*.png`). Every 20 s, one
tick on the next widget in rail order: a real mouse click on its card. Then either one of its declared InfoView clicks
(rotating; real mouse, edit == the frozen edit, 0 errors / 0 warnings on the re-checked version) and "Reset example",
or, for ChartKit, ExprXRay and TreeScope (no declared clicks), the first-cursor panel compared with its golden.

* 22.09 min, 66 ticks = 8 full cycles (each widget visited 8–9 times), 173 operations, **0 failed**, slowest 3,056 ms
  (a DistLens click; the stall line was 60 s). **No crash**, no stall card, 0 gallery liveness restarts, 0 QED64
  `wedged` reboots, 0 worker deaths, 26 workers throughout, one wasm session, console oracle OK.
* Renderer RSS (every 5 s, 260 samples): 9.10 GiB at the first tick, then 8.07–8.23 GiB. Per-cycle max: 9.10 (cycle 1,
  boot), 8.14, 8.15, 8.21, 8.21, 8.19, 8.20, **8.23** GiB. OLS slope after cycle 1: **+7 MB/min** (R² 0.75; 0.42 GB/h if
  it went on linearly), concentrated in cycles 2–4 (+0.07 GiB) and +0.02 GiB over cycles 4–8. Assert "last-cycle max ≤
  1.10 × cycle-2 max": 8.23 ≤ 8.95, PASS. Not shown: behaviour beyond 22 min.
* Wasm heap (the worker's telemetry `memory.currentBytes`): 2.00 GiB at every tick, slope 0. (`performance.memory` in
  headless-shell is quantised and read 72.2 MB throughout; not informative.)

## Files changed or added by this lane

* `tests/ux/lib/qed64.mjs`: `UX_CHANNEL` (inert when unset); `chromeRss()` descendant counting under `UX_CHANNEL`;
  `--force-device-scale-factor=1` for **headed** launches only.
* `tests/ux/lib/global-setup.mjs`: `channel` in `run-meta.json`. `tests/ux/specs/50-misc.spec.mjs`: C19 uses
  `UX_CHANNEL` when set. `scripts/showcase.sh`: `channel` in the ux record.
* New tools in `tests/ux/tools/`: `throttled-first-visit.mjs`, `throttle-proxy.mjs`, `cdp-throttle-probe.mjs` (its
  blob-worker test stalled in every variant including the control, so it is inconclusive; the conclusion above rests on
  the real-page run `throttle-t50`), `soak.mjs`, `safari-probe.mjs`, `headed-env-probe.mjs`, `headed-timing-probe.mjs`,
  `c13-dsf-probe.mjs`.
* New: `out/ux/profiles/ux-warm-chrome-headed/` (2.0 G, branded Chrome's warm profile, regenerable).
* The verdict runs `lastmile-full1/2` ran before the `--force-device-scale-factor` edit. That edit changes only headed
  launches, so the headless path they used is unchanged. `gallery/` was not touched (hash `921b0b6a…` before and after).
