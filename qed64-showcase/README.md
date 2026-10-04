# qed64-showcase

Eight Lean InfoView widget packages run live in the **stock, unmodified QED64 page** (in-browser wasm64 Lean 4.34.0, a
pinned dependency), driven by a gallery at `/showcase/`.

**Current state is printed by commands, not written in this file** (a written run name or count is wrong after the
next run): `scripts/showcase.sh pin list` (per pin: full UX runs on its lock, the VERDICT count and last VERDICT, the
HEADED SIGN-OFF count and last sign-off), `scripts/showcase.sh gallery` (the static gate, the current gallery content
sha256, then `UX CURRENT …` naming the newest verdict on exactly this gallery + lock + overlays, or `UX STALE`) and
`node scripts/deploy-manifest.mjs --check` (the `G2 UX:` line a deploy relies on). Run records:
`out/ux/showcase-ux-runs.jsonl`, judged by `scripts/lib/ux-record.mjs`; tallies: `node scripts/ux-tally.mjs`. Dated
figures below are history. **Status 2026-10-04:**

* **Open it:** `scripts/showcase.sh verify && scripts/showcase.sh serve`, then <http://localhost:5190/showcase/>.
* **Served: pin E `33b0967`** (QED64 main with HARDENING #55, the runtime lifetime locks that QED64 reports fix L9 V2,
  and #54, the boot card that stays until ready; runtime `wasm64-3ab1c6a9da03bc29`, D's runtime and stores). **Why:**
  on the visitor's path `/showcase/#hasse-view`, interleaved with C in the same windows, its reload storms were at least
  as clean as C's (headed E 0/20 vs C 0/20, chrome-headless-shell 0/8 vs 1/8). Then two full `ux` VERDICTs, a headed
  sign-off, a 10 Mbit/s first visit `RESULT PASS` and the deploy check on its gallery (pin-e lane, 2026-10-04,
  `out/ux/pin-e/RESULTS.md`; current counts: `pin list`). **Staged:** C `5ac5d00` (served until 2026-10-04: the
  fallback, runtime `wasm64-4b025db7729c5f89`, QED64's L7 liveness), D `3b42714` (0035b; E's runtime with the older
  worker), A `1859b83` (old fallback), B `9fdf9b8` (evidence).
* **Gallery, dated history.** Gallery `921b0b6a…` had verdict runs from the v2mit and last-mile lanes (2026-10-02/03)
  and no headed sign-off (the last headed sign-off on C, `final-C-headed1`, 34/34, was on `2081098d…`). The boot-fix
  lane (2026-10-03) changed `gallery/gallery.js` (slow first visits, below), so those verdicts stopped applying;
  which runs are verdicts on the current gallery: `showcase.sh gallery` (history of that lane's own full runs:
  docs/UX-RESULTS.md "Boot-fix lane"). The closure lane (2026-10-03, 09:15–14:49Z) then recorded two more verdicts and
  the first headed sign-off on that gallery `31f6d8d9…`, plus the throttled first visits, a 60-min soak and the deploy
  rehearsal (`out/ux/closure/RESULTS.md`). The post-audit fix lane (2026-10-03, from 16:28Z) changed `gallery.js` and
  `gallery.css` again (gallery `b7aa521a…`: page resources re-fetched from one URL no longer count as boot progress;
  the slow-download notice no longer covers QED64's status pill) and recorded two verdicts and a headed sign-off on it
  (docs/UX-RESULTS.md "Post-audit fix lane"). The pin-e lane (2026-10-04) switched to E; `pin use` regenerated
  `gallery/pin.json`, so the gallery is `bbdbc932…` (same code as `b7aa521a…`). It recorded two verdicts and a headed
  sign-off on it (`out/ux/pin-e/RESULTS.md`).
* **Browsers tested:** Chromium 151 (chrome-headless-shell: every verdict; headed Chrome for Testing: the sign-offs);
  installed **branded Chrome 154** headed, `lastmile-chrome-headed2` 32/34, not a sign-off (C13b lacks a Chrome 154
  baseline; C10 settles at 10.68 GB > its 10.5 GB line). **Safari 26.6.2 not run:** WebDriver refused ("Allow remote
  automation" off, left off); its JavaScriptCore rejects the Memory64 probe, so it should get the "cannot run" card
  (inferred). Edge, Brave, Arc, Firefox untested. Missing isolation, SharedArrayBuffer or Memory64 → a card, no load.
* **Memory (measured):** a tab takes 8.2–9.0 GiB at ready, ~12 GB on a reload, ~17 GB+ for two tabs or "Load exact
  imports": visitors need **16 GB of RAM, one showcase tab at a time** (soak: 22 min, 173 operations, 0 failures).
  **First visit ~710 MB:** 123 s at 50 Mbit/s; **10 Mbit/s: ready at 565 s with the panel, no error card**, a
  "Still downloading …" notice from 231 s (boot-fix lane, 2026-10-03, on C; before it the fixed 360 s boot timeout showed
  "This is taking too long" at 467 s and never cleared). On E (pin-e lane, 2026-10-04): ready at 565.1 s, no error card,
  and QED64's own boot card (step, bytes, rate, time left) stays until ready (#54). The gallery's notice comes from
  467 s.
* **L9 V2, fixed upstream in QED64 #55 (in the served E); our storms are consistent with that but cannot confirm it.**
  V2 is a renderer crash about 2 s after reload 2–4 of a reload storm. It hit every pin before E. In the pin-e lane's
  storms on the visitor's path (2026-10-04, `out/ux/pin-e/RESULTS.md`), E had 0 crashes in 28 storms and C had 1 V2 in
  28 (headed 0/20 each). In those windows, however, C itself almost never crashed. The day before, the v2-embed lane
  measured C at 15/24 on the same path and tool (62 %, 43–79 %), and 24/56 over all windows. Our numbers therefore show
  that E is not worse; the reduction is QED64's own measurement (their headed embedded storms: 17/48 → 0/36). A likely
  reason for the low rate on 2026-10-04 is a host with about 15 GB reclaimable instead of about 21 GB; that is an
  inference. What we can say for visitors: E's headed rate on that path was 0/20 (95 % upper bound 16 %, about 1 in 6)
  in windows where C was also 0/20; in a high-rate window like v2-embed's, E has not been measured. **Why the gallery entry was worse
  on C: mainly embedding itself.** The stock page inside a script-free same-origin iframe crashed in 16/48 storms
  against 4/48 at top level (Fisher p = 0.005), and the gallery's own code added a further 62 % vs 42 %, which is not
  significant (p = 0.25) (`out/ux/v2-embed/RESULTS.md`). The gallery *is* the stock page in an iframe, so the fix had to
  come from QED64.
* **Switch pins:** `scripts/showcase.sh stop && scripts/showcase.sh pin use <id>`, then `verify`, `gallery`, two `ux`
  (back to C: `pin use 5ac5d00`).
  **Deploy:** owner's Cloudflare account, [docs/DEPLOY-CLOUDFLARE.md](docs/DEPLOY-CLOUDFLARE.md) (rehearsed on fakes).
  **Next:** [docs/NEXT-STEPS.md](docs/NEXT-STEPS.md). **Details:** "Results", "Limitations" below; docs/HISTORY.md.

## Clone and build from source

This project lives in the widgets repository (github.com/FawadHa1der/lean-widgets) at `qed64-showcase/`. The widget
packages it serves are the repository's `packages/`. **QED64 is a dependency, never a copy**
([docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)):

* its **sources** are the git submodule `deps/qed64`, at the served pin's commit. Staged pins use git worktrees of it.
* its **page** is built from those sources with QED64's own build. It is byte-identical to the lock, so the lock's
  sha256s are the check.
* its **binaries** (runtime, packs, stock snapshots) and our widget overlays are fetched by content hash from an
  artifact origin.

```
git clone --recursive https://github.com/FawadHa1der/lean-widgets.git
cd lean-widgets/qed64-showcase
scripts/showcase.sh bootstrap --origin <showcase origin> [--qed64-origin https://qed64.fawadworkaddress.workers.dev]
scripts/showcase.sh gallery && scripts/showcase.sh serve          # http://localhost:5190/showcase/
npx playwright install chromium chromium-headless-shell && scripts/showcase.sh ux
```

`bootstrap` needs neither QED64_REPO, the kernel build nor Docker. It works on macOS and Linux and is described step
by step in [docs/BUILD-FROM-SOURCE.md](docs/BUILD-FROM-SOURCE.md), together with the heavy path (rebuilding the
overlays from the kernel fork's toolchain). Until the showcase's Worker is deployed, the overlays live only where they
were baked: `--origin` can be the `serve.mjs` of such a checkout. Nothing in code or configuration names a machine
path (`node scripts/check-portable.mjs` proves it). Every location is resolved at run time by `scripts/lib/env.sh` /
`scripts/lib/env.mjs` from environment variables, optionally kept in the gitignored `.env.local` (template:
`.env.example`; `node scripts/lib/env.mjs` prints what is resolved):

| Variable | What | Needed by |
|---|---|---|
| `QED64_SHOWCASE_WORK` | heavy work dir (no spaces); default `~/.cache/lean-widgets/qed64-showcase-work` | everything that builds |
| `ARTIFACT_ORIGIN`, `QED64_ARTIFACT_ORIGIN` | artifact origins (`--origin`, `--qed64-origin`) | `bootstrap`, `scripts/fetch-artifacts.mjs` |
| `QED64_REPO` | a QED64 checkout with QED64's binaries and `work/` trees built; read-only | heavy path only: `pin clone` (registering a new pin), `stage` |
| `QED64_KERNEL_BUILD` | the wasm64 kernel build dir (`native/stage1`, `mathlib/`, `BUILT-COMMIT`; from github.com/FawadHa1der/lean4 branch `qed64-wasm64`); read-only | heavy path: `native`, `stage`, golden env; `verify` checks it when set (else N/A) |
| `QED64_KERNEL_SRC`, `LEAN4GAME_DIR` | further read-only trees watched by `scripts/assert-untouched.sh` (optional; reported when unset) | `assert-untouched` |
| `LEAN_TOOLCHAIN_DIR` | stock Lean v4.34.0 (default `~/.elan/toolchains/leanprover--lean4---v4.34.0`) | goldens, native E3 |
| `BROWSER_LOCK_DIR` | the host-wide browser lock (default `~/.cache/host-browser-lock`) | every browser run |

`release/`, `out/`, `rollback/`, `node_modules/`, `.env.local` and the work dir are machine-local and gitignored.
Curated run records from `out/` are copied to `docs/results/` (same relative paths). The committed files are
`pins/<id>/{pin.json,QED64.lock.json}` (lock schema v2: QED64 commit, source/shell/artifacts, the sha256 of every
served file and overlay), the active lock link `QED64.lock.json`, the native click-all goldens
(`lean/expect/click-all/`) and the native delta lists (`lean/native/`). A lock records the kernel build and the work dir
as placeholders (`${QED64_KERNEL_BUILD}`, `${QED64_SHOWCASE_WORK}`), never as a path.

## What it is

The packages are ChartKit, HasseView, IntervalInspector, SimpLens, ExprXRay, TreeScope, GraphScope and DistLens. Every
widget renders in the real QED64 InfoView, the same one VS Code uses. QED64's `dist/`, runtime and workers are
served byte for byte from a verified clone of a pinned QED64 commit; pins are keyed by **QED64 commit**, several can be
registered, and one is active ("Pins" below). The showcase adds three things around that page: a snapshot region that
contains the widgets; a gallery page that iframes the stock QED64 page from the same origin; and a small same-origin
bridge for two InfoView defects of the shipped page. Nothing under the QED64, kernel or lean4game trees is ever written
(reads use `git --no-optional-locks`; the untouched-check history is in docs/HISTORY.md).

## Results

| What | Result | Where |
|---|---|---|
| Browser UX (Playwright, gallery and stock page, 34 tests) | **Current verdicts are printed, not listed here:** `scripts/showcase.sh gallery` (`UX CURRENT …` / `UX STALE` for the current gallery), `scripts/showcase.sh pin list` (VERDICT and HEADED SIGN-OFF counts and the last of each per pin). *History (dated):* on gallery `921b0b6a…` the v2mit and last-mile lanes (2026-10-02/03) recorded four verdict runs (33 passed, 1 skipped each; C10 no crash; C20 135/135) and no headed sign-off (headed: `v2mit-headed1` 31/34, display scale, since fixed in the harness; `lastmile-cft-headed-c10c13` 4/4 subset; branded Chrome 154 `lastmile-chrome-headed2` 32/34); on `2081098d…` `final-C-full1/2` and the headed sign-off `final-C-headed1` (34/34); on D while served (`eab4f147…`) `final-D-full1/2` and sign-off `final-D-headed2`. The boot-fix lane's gallery change (2026-10-03) made those runs stop applying; its own three full runs on the new gallery were one red (one W4 renderer crash, cause unknown, not reproduced in 20 W4 repeats) then two verdicts (docs/UX-RESULTS.md "Boot-fix lane") | [docs/UX-RESULTS.md](docs/UX-RESULTS.md), `out/ux/showcase-ux-runs.jsonl`, `node scripts/ux-tally.mjs`, `$W/logs/finaldocs-verdicts.log` |
| Run tallies per pin (C10 crashes, C20 runs, storms) | one tool: `node scripts/ux-tally.mjs` prints the current counts. *History, final docs lane 2026-10-03 ~03:50Z* (`$W/logs/finaldocs-ux-tally.txt`; the figures below are from that snapshot): B: C10 crashed in 6 of the 8 runs that ran it (5 of 7 full runs); C20 17 runs, all 135/135. C: C10 ran in 19 runs (17 full), 0 crashes (the 3 branded-Chrome runs failed its 10.5 GB settled-memory line, no crash); C20 23 runs, all 135/135. D: C10 0 crashes in 4 full runs; C20 4 runs, all 135/135. A: C10 0 crashes in 11 runs; 1 L7 hang in its C20 history | docs/UX-RESULTS.md "Tallies" |
| Pins and switching | A, B, C, D, E registered (E 33b0967 added 2026-10-04 and served since then), hash-verified and with complete stores (`pin list`, `verify`: all checks OK with 1 known Docker `DRIFT`, `$W/logs/finaldocs-{pin-list,verify}.log`); switching rehearsed C→A→C→A→C→B→C, then C→D→C in the final gate, then C→E on 2026-10-04 (pin-E lane) | [docs/REPIN-LOG.md](docs/REPIN-LOG.md) "2026-10-02" sections |
| L9 in desktop Chrome (before the final gate) | l9-desktop (05:34–08:33Z): B V1 in headless-shell and headed; V2 headed on A 1/5, B 2/8, C 4/19, all in 05:51–06:40Z. Quiet slot (11:03–11:21Z, headed): V2 A 1/8, C 2/10, D 0/5 | `out/ux/l9-desktop/RESULTS.md`, `out/ux/l9-quiet/RESULTS.md`, docs/UPSTREAM-REPORT-QED64.md L9 |
| L9 final gate (interleaved A/C/D/B, both browsers, stock page and `/showcase/`, plus a quiet-host round) | V1 only on B (3/20); V2 on A 3/26, C 2/26, D 3/26 (headless-shell too); C stays served | `out/ux/final-storm/RESULTS.md` (generated), `node scripts/ux-tally.mjs` |
| L9 V2 gallery-side mitigation (v2mit A/B on C, `/showcase/`, quiet host) | teardown on the gallery's `pagehide` rejected: headed V2 10/24 with it vs 8/24 without (Fisher p = 0.77), headless-shell 0/12 each; old workers already close 7–40 ms after a reload in both arms | `out/ux/v2mit-storm/RESULTS.md` |
| Last mile on C and `921b0b6a…` (2026-10-03) | branded Chrome 154 headed 32/34 (C13b baseline, C10 memory line); Safari 26.6.2 refused by WebDriver (not changed); throttled first visit 123 s at 50 Mbit/s, boot-timeout defect at 10 Mbit/s (fixed by the boot-fix lane, next row); soak 22 min, 173 operations, 0 failed, no crash | `out/ux/last-mile/RESULTS.md` |
| Boot-fix lane (2026-10-03): slow first visits | `gallery.js` boot wait re-arms on progress (QED64's byte progress via its `qed64.ui` sink, new stage labels, phase/relay/session/version, page resources); notice instead of the card while progress continues; card only after 360 s AND 240 s without progress; a later `ready` closes the card and finishes the boot. Sim run 15 (slow progress, true stall, late ready, defaults; two mutants killed). Browser, fresh profile, link shaped by `throttle-proxy.mjs`: **10 Mbit/s ready at 565.0 s, error card in 0 samples, notice from 231.5 s, panel equal to golden** (`throttle-p10b.json`, final code; `throttle-p10-draft1.json`, a draft notice wording: 564.0 s, same results); with `?bootTimeout=10&bootStall=3` at 50 Mbit/s the stall card showed at 56 s and closed itself when QED64 was ready (120 s), panel equal (`stall50`) | `out/ux/bootfix-throttle/explore/throttle-p10.json`, gallery/README.md "Timeouts" |
| Post-audit fix lane (2026-10-03): the final audit's findings, gallery `b7aa521a…` on C | two full `ux` runs, both VERDICT (33 passed, 1 skipped each); headed sign-off in Chrome for Testing, 34/34; 10 Mbit/s first visit ready at 565.0 s, no error card, `RESULT PASS`; sim 114 ok; `ux` refuses a reused `UX_RUN`; `throttled-first-visit.mjs` exits 0/1; docs: no current-state verdict names, L9 visitor path with the v2-embed result. One run started by mistake on the pre-final gallery is recorded as NOT A VERDICT | docs/UX-RESULTS.md "Post-audit fix lane" |
| Closure lane (2026-10-03): final verification of gallery `31f6d8d9…` on C | two full `ux` runs, both VERDICT (33 passed, 1 skipped each); a full headed sign-off in Chrome for Testing, 34/34 with C19; throttled first visit on a fresh profile: 10 Mbit/s ready at 565.1 s, 50 Mbit/s at 120.3 s, no error card, panel equal; 60-min soak: 473 operations, 0 failed, no crash, renderer RSS +4.5 MB/min and slowing, not level at 60 min; manifest `--check` OK, `rehearse.sh all` and `BOOT-CHECK OK`. Fixed three test-tool defects: byte reordering in `throttle-proxy.mjs`, a timing race in `sim-gallery.mjs` run 15a, and G1's missing failure detail. `assert-untouched` CHANGED by other sessions' QED64/lean4game commits (attributed) | `out/ux/closure/RESULTS.md`, docs/UX-RESULTS.md "Closure lane" |
| Pin-e lane (2026-10-04): pin E gated and served | storms on `/showcase/#hasse-view`, E vs C interleaved: headed 0/20 vs 0/20, chrome-headless-shell 0/8 vs 1/8 (V2), so E is not worse (C's own rate was low in these windows, so this is not a confirmation of #55); `pin use 33b0967` → gallery `bbdbc932…`; `pinE-full1/2` VERDICT (33 passed, 1 skipped each); `pinE-headed1` 34/34 HEADED SIGN-OFF; 10 Mbit/s first visit `RESULT PASS` (565.1 s, QED64's boot card until ready, gallery notice from 467 s); `deploy-manifest --check` OK, `rehearse.sh all` and `BOOT-CHECK OK` | `out/ux/pin-e/RESULTS.md`, docs/REPIN-LOG.md "pin E gated" |
| Headless verification in wasm (Node, no browser) | runtime `wasm64-4b025db7729c5f89` (A and C): E1 8/8 (w8) and 7/7 (w7), E3 and E3b green, E2 7/8 (the 8th is L1), 135 native click-all links; `CONTROLS PASS` 11/11 on C. Runtime `wasm64-3ab1c6a9da03bc29` (D): the same (E3 1167/1167 and 1038/1038, E3b 49/49 and 44/44), `CONTROLS PASS` | [docs/HEADLESS-RESULTS.md](docs/HEADLESS-RESULTS.md), `out/headless/summary.json`, `out/runtimes/<buildId>/headless/summary.json`, docs/REPIN-LOG.md "pin D" |
| Static gallery gate | `scripts/showcase.sh gallery` prints the current result. *History:* final docs lane on `921b0b6a…` `CHECK-GALLERY OK 128 ok`, `SIM-GALLERY OK 101 ok` (`$W/logs/finaldocs-gallery.log`); boot-fix lane on its gallery `31f6d8d9…` `CHECK-GALLERY OK 128 ok`, `SIM-GALLERY OK 109 ok`, gate GREEN (`$W/logs/bootfix-gallery.log`, before its `ux` runs; `bootfix-gallery-end.log` after them) | [gallery/README.md](gallery/README.md) |
| Hosting on its own origin (Worker + R2) | rehearsed green against local fakes on pin C and gallery `2081098d…` (final-gate lane), then on gallery `31f6d8d9…` (closure lane, 2026-10-03: `rehearse.sh all` rc 0 and `BOOT-CHECK OK`; its first attempt stopped on a sim-gallery timing race, since fixed, `out/ux/closure/RESULTS.md` (5)), then on gallery `b7aa521a…` (post-audit fix lane, 2026-10-03: `all`, `browser`, `stop` rc 0, `BOOT-CHECK OK`); `node scripts/deploy-manifest.mjs --check` prints whether the current gallery has the verdict G2 needs (history: OK on `921b0b6a…` at the final docs lane, and on `31f6d8d9…` at the closure lane, `$W/logs/closure-deploy-manifest-check-end.log`); not deployed: publishing needs the owner's account | [docs/DEPLOY-CLOUDFLARE.md](docs/DEPLOY-CLOUDFLARE.md), [docs/DEPLOY.md](docs/DEPLOY.md) |
| Defects in the pinned QED64 page and runtime | D1, D2, L1, N1, N2, N3, P1, L7, L9 (V1, V2), X1, each with evidence and a suggested fix | [docs/UPSTREAM-REPORT-QED64.md](docs/UPSTREAM-REPORT-QED64.md) |
| Build history and evidence | pin, native build, bakes, examples, goldens, gallery code; the lane-by-lane record | [docs/HISTORY.md](docs/HISTORY.md), [docs/STAGE-A-RESULTS.md](docs/STAGE-A-RESULTS.md), [docs/STAGE-B-RESULTS.md](docs/STAGE-B-RESULTS.md) |


## Architecture

```
 read-only inputs                       this repo / $W (= $QED64_SHOWCASE_WORK, no spaces; scripts/lib/env.sh)
 ───────────────────────────────        ──────────────────────────────────────────────────────────────────────────────
 QED64 @<pin commit> = git submodule deps/qed64 (staged pins: git worktrees $W/qed64-pins/<id>); read in place, never copied
            ├─npm ci + build:site─►  release/<id>/dist     byte-identical to pins/<id>/QED64.lock.json (scripts/build-shell.mjs)
 artifact origin ──fetch by path────►  release/<id>/public   sha256 == the lock (scripts/fetch-artifacts.mjs; manifests from git)
 ../packages @WIDGETS_COMMIT ─git archive─► $W/widgets-src  WIDGETS_SOURCE_HASH c2efe78f… (222 files; scripts/export-widgets.mjs)
 kernel-build Mathlib tree ─cp -cpR─►  $W/mathlib4              APFS clone, new inodes
                                          │ scripts/build-native.sh: native64 lean/lake in Docker (qed64-toolchain:emsdk-6.0.5,
                                          │   --network none), Lake reuse gate, then only the delta: 38 + 402 Mathlib/ProofWidgets
                                          ▼   modules + 72 widget modules; header gate (no GMP, empty githash)
 QED64 served slim tree (5004 mods) ─►  $W/tree-slim-w7 (5107) · $W/tree-slim-w8 (5684) · $W/tree-fat     scripts/stage-trees.mjs (G1–G6)
   (per pin: pin.json servedTrees)
                                          │ scripts/bake.sh: deps/qed64's bake-snapshot.mjs + the pinned runtime ($W/stage1)
                                          ▼ judge-bake.mjs (N == EXPECTED-N, no errors) · pair-check.mjs (digest, runtime == buildId)
                                       $W/runtimes/<buildId>/bake-out-w{7,8}/widgets.<d16>.snapz   paired with that runtime
                                          │ make-overlay.mjs: entry renamed "mathlib", served init cloned beside it
                                          ▼
                                       out/runtimes/<buildId>/overlay/widgets7|widgets8/{index.json, init.….snapz, widgets.….snapz}
                                       (the active pin's are linked at out/overlay/snapshots/widgets7|widgets8)

 one origin: scripts/serve.mjs :5190 (COOP/COEP/CORP on every response; QED64's cache rules)
   /                       → release/…/dist        the STOCK QED64 page, unmodified
   /runtime|profiles|snapshots/ → release/…/public  the pinned artifacts
   /snapshots/widgets8/    → out/overlay/…          our region (the page re-roots it: ?snapshots=snapshots/widgets8)
   /showcase/              → gallery/               rail of 8 examples ── iframe "/?snapshots=snapshots/widgets8"
                                                      ├─ pairing preflight before navigating (runtime == pin, sizes, no HTML)
                                                      ├─ seeds qed64.buffer, drives contentWindow.qed64 (setValue, cursor)
                                                      └─ installs gallery/qed64-bridge.js on the page window (D1 abortSignal, D2 applyEdit)
```

The headers are plain `import Mathlib` / `import <Pkg>`. QED64 treats `Mathlib` as an alias
covered by any region containing `QED64.Essential`. So the same example file also works
unchanged in VS Code, and no `QED64.Widgets.*` shims are needed.

## Quick start

These are the cheap commands. `verify`, `gallery`, `gallery-hash`, `pin list` and `ux` were last run on 2026-10-04 by
the pin-e lane (logs `$W/logs/pinE2-*.log`); `serve`/`stop` by earlier lanes. `open`
starts a desktop browser outside the browser lock, so no lane ran it.

```
scripts/showcase.sh verify            # pin chain of trust, pin constants, stage1 buildId, overlays, gallery freshness
scripts/showcase.sh gallery           # regenerate gallery data only if stale, then the static gate (check-gallery + sim-gallery);
                                      #   prints the gallery content sha256 it judged and whether a green full UX run exists for it
node scripts/lib/gallery-hash.mjs     # that sha256 alone: the shipped gallery files (= the /showcase/ assets; not *.md, x3.html)
scripts/showcase.sh serve             # scripts/serve.mjs on :5190 (PORT=5191 for a second one)
open http://localhost:5190/showcase/  # e.g. …/showcase/#hasse-view, …/showcase/?overlay=widgets7
scripts/showcase.sh stop              # stops only a server this lane started via `serve`
```

Prerequisites (docs/BUILD-FROM-SOURCE.md): macOS or Linux; Node 26 (the lock records v26.3.0, another 26.x is a
DRIFT); `npm ci` (`@playwright/test` 1.62.1; `bootstrap` runs it when `node_modules/` is missing); for `ux`, Playwright's
Chromium (browser revision 1234: `npx playwright install chromium chromium-headless-shell`) and 16 GB of RAM. The
release, the overlays and `$W` are gitignored outputs: `scripts/showcase.sh bootstrap` recreates the first two from
source and fetched artifacts, and the heavy path (below and BUILD-FROM-SOURCE.md) rebuilds the overlays.

`scripts/showcase.sh --help` lists every subcommand. These cheap checks were also run:

```
scripts/showcase.sh verify --deep --untouched <stamp>   # + gunzip/digest every overlay snapz; assert-untouched
scripts/showcase.sh --dry-run all                       # the whole pipeline's plan; guards that would refuse print WARN
scripts/showcase.sh headless controls                   # wasm controls: E1 ±, conv? E3 stock, refused header, E3b, provenance negatives (~1 min, ~12 GB peak)
scripts/showcase.sh headless summary --out <file.json>  # rebuild the Stage-4 summary from the logs (default: out/headless/summary.json)
node --test infra/worker.test.mjs                       # the deploy worker against fake bindings
node scripts/deploy-manifest.mjs && node scripts/deploy-manifest.mjs --check
```

## One-command workflow: `scripts/showcase.sh`

| Subcommand | What it runs, in order | Guards |
|---|---|---|
| `pin list` / `pin current` / `pin check <id> [--full]` | `pin-switch.mjs` (read-only): the registered pins (keyed by QED64 commit, see "Pins" below) with status, store completeness and UX verdicts; the active pin and its 15 links; the cheap store check of one pin. All three (and `pin use`, after the switch) also check that the active overlay links' `index.json` runtime equals the active lock's runtime (`pin check`: the pin's overlays vs its own lock) | – |
| `pin use <id> [--dry-run] [--no-deploy]` | `pin-switch.mjs use`: atomic switch of the 15 active links (lock link last, journaled), `gallery/pin.json`, and the deploy inputs when `out/deploy` exists; then `pin current` | Refused (3) for an unregistered or incomplete pin, while a `serve.mjs` of this repo that follows the active pin runs, during a bake, a headless run or a showcase browser run. |
| `pin clone <id> [--yes]` (`pin [--yes]` = the active pin) | `pin-qed64.mjs pin --pin <id>` → `record-widgets-hash` → `verify --pin <id>` | Without `--yes` it only reports QED64 HEAD/clean against the pin's commit, and writes nothing. Writes only `pins/<id>/` and `release/<id>/`; never switches. |
| `verify [--deep] [--untouched NAME]` | `pin current`; `pin-qed64.mjs verify` of the **active** pin (full sha256 chain, #1–#10); `pin check` of every **staged** pin (cheap); the pin-constants check (no hardcoded pin anywhere under `scripts/`, `tests/`, `gallery/`, `infra/`; see "Pins"); stage1 buildId; overlay indexes; `build-gallery --check`; optionally `pair-check` and `assert-untouched` | – |
| `native [all\|<step>]` | `build-native.sh`: identity → reuse-pre → delta → gate-delta → append → reuse-post → widgets → gate-widgets → distlens (T=4) → gate-distlens → reuse-final → `native-report.py` | One Docker job at a time; refused while a bake runs; refused when the `qed64-toolchain:emsdk-6.0.5` image is not the one the lock records (see "Docker tag drift"). Runs under `caffeinate -i`. |
| `stage [w7\|w8\|fat\|all] [--force]` | `stage-trees.mjs` with the exact roots of the original run (a w7 rerun into a scratch tree reproduced delta 39, own 64, EXPECTED-N 5107) | Refused while a bake runs. |
| `bake [w7\|w8\|all]` | `bake.sh` (under the browser lock) → `judge-bake.mjs` → `pair-check.mjs --cmp` | `bake.sh` runs under `with-browser-lock.sh`, so no browser lane can start during it. Refused while a browser, a Docker container or another bake runs (checked before queueing and again inside the lock). `bake.sh` also needs at least 12 GiB free. |
| `overlay [w7\|w8\|all] [--preflight]` | `make-overlay.mjs` → `pair-check.mjs --cmp`; with `--preflight`, QED64's own read-only `preflight.mjs` | `--preflight` boots a browser, so it runs under the browser lock after the browser preflight. |
| `headless [all\|controls\|stage4 …\|e2 …\|summary]` | `scripts/headless/run-controls.sh`, `run-stage4.sh`, `run-e2.sh`, `summarize-stage4.mjs` | The tools' own single-runner lock and 12 GiB memory guard; the long steps run under `caffeinate -i`. |
| `gallery [--live]` | `build-gallery.mjs` (only when `--check` says stale) → `check-gallery.mjs`; then prints `gallery gate GREEN on gallery content sha256 <h>` and `UX CURRENT` / `UX STALE` (is there a **verdict** `showcase.sh ux` run, see `ux`, on gallery `<h>` with the current lock and overlay indexes?) | Fails if `gallery/` changed while the gate ran (the result would describe neither revision). Note that a stale gallery is rebuilt, which writes `gallery/examples.json` and `pin.json`: while another lane is editing `gallery/`, run the read-only `node scripts/check-gallery.mjs` instead. |
| `serve` / `stop [--force]` | `serve-start.sh` / `serve-stop.sh` on `PORT` | `serve` accepts a server already on `PORT` only if it is this showcase for the local gallery: `pin.json` buildId == lock, COEP/CORP, **and** the content sha256 of the gallery files it serves equals the local one (a `GALLERY_DIR=<mutant>` server is refused). `stop` refuses to stop a server another lane started. |
| `ux [args]` | the UX lane's suite: the same command as `npm run test:ux` (`with-browser-lock.sh` + `npx playwright test -c tests/ux/playwright.config.mjs`), with `args` passed through (e.g. `--grep C20`), in run dir `out/ux/$UX_RUN` (default `showcase-<lane>-<utc>`). Every run appends a record to `out/ux/showcase-ux-runs.jsonl`: `{start, end, lane, rc, args, run, origin, uxOrigin, galleryStart/End` (local) `, servedStart/End` (the same hash over what the server returned) `, lockSha256(End), overlays(End), listed, report}`, and prints `VERDICT` or `NOT A VERDICT: <why>`. The rule (`scripts/lib/ux-record.mjs` `whyNotVerdict`): full suite, no `UX_ORIGIN`, rc 0, `report.json` 0 unexpected / 0 flaky with `expected + skipped == listed` and only C19 skipped (`forbidOnly` is on), local == served gallery from start to end, lock and overlays unchanged |  The browser lock, its cooldown and `caffeinate -i` (all from `with-browser-lock.sh`), then the browser preflight inside the lock. Refused if :5190 is held by anything other than this showcase's `serve.mjs` serving the local gallery; if nothing is up, `ux` starts `serve.mjs` itself (with `GALLERY_DIR` unset), hashes what it serves before and after, and stops it. `UX_ORIGIN` runs are recorded but never a verdict. |
| `UX_HEADED_ALL=1 UX_WARM_PROFILE=$PWD/out/ux/profiles/ux-warm-headed ux` | the **headed sign-off** (final-gate lane): every test, C19 included, in a real Chrome for Testing window (Playwright project `headed`); its own visual baselines `tests/ux/__screenshots__/headed/`; the stock page's favicon 404 (QED64 N3) allowed once per load. Headed launches pin `--force-device-scale-factor=1` (last-mile lane: headed glyphs follow the real display's scale). `UX_CHANNEL=chrome` (only with `UX_HEADED_ALL=1`) uses the installed branded Google Chrome instead and records `channel`. Recorded with `headed: true` and judged `HEADED SIGN-OFF`, never a verdict (`scripts/lib/ux-record.mjs whyNotSignOff`); `UX CURRENT` names it | same as `ux`; a separate warm profile so the headless suite's `ux-warm` is never opened by another browser binary |
| `locked <what> -- <cmd…>` | any command under the browser lock | The same lock, cooldown, `caffeinate -i` and browser preflight as `ux`. |
| `all [--rebuild]` | verify → native → stage → bake → overlay → headless → gallery → ux | Without `--rebuild` it skips: `native` when `out/native-build.json` exists; `stage` when the three trees exist; `bake w7`/`w8` when `judge-bake` is GREEN; `overlay w7`/`w8` when the overlay passes the cheap overlay check (index schema, exactly `{init, mathlib}`, runtime == lock, every snapz present with size == transfer), not merely when `index.json` exists; `headless` when `out/headless/summary.json` is for the lock's buildId with `gate.stage4Green` and `gate.E2Green`, every package's `e1.snapSha256` equals the sha256 of the current `$W/bake-work-w{7,8}/widgets.snap`, **and** no bake or overlay was redone in this run (a redone bake re-runs S4, about 20 min with 12 GB+ RSS peaks). `verify`, `gallery` and `ux` always run. A red first `verify` does not stop the build stages, but `verify` then runs again after them, and `all` ends with `ALL: FAILED (verify still red …)` and exit 1 if it is still red; a failing `ux` also makes `all` exit 1 (`ALL: FAILED (ux rc=N)`). |

**`SHOWCASE_PIN=<id>`** (a registered pin) makes `stage`, `bake`, `overlay`, `headless` (and the scripts behind them)
act on that pin's own stores instead of the active links, without switching; `ux`, `gallery` and `all` refuse it unless
it is the active pin, and `serve`/`stop` refuse it on :5190 (README "Re-pin" step 4).

Every subcommand also accepts `--dry-run` (`-n`). It prints the plan and runs only the read-only
guards. Each step tees into `$W/logs/showcase-<lane>-<sub>-<step>.log` (`<lane>` is
`SHOWCASE_LANE`, so concurrent lanes never overwrite each other's logs), and the exit status
checked is the step's own. Exit codes: `0` ok, `1` a step failed, `2` usage, `3` refused by a guard.
A locked step is reported as `REFUSED` (exit 3) only for `with-browser-lock.sh`'s `75` (lock wait
timed out) and `76` (cooldown refused) and for `77`, the code `_inlock` exits with when its own
preflight refuses inside the lock. Any other rc is the locked command's own and passes through
unchanged, so `locked x -- cmd` exiting 3 means `cmd` exited 3: a refusal prints only the
`[showcase] REFUSED:` line, a command failure only `<what>: FAILED rc=N` (until the close-out, a
refusal printed both). In
`--dry-run`, a guard that would refuse prints `dry-run WARN` and the rest of the plan is still
printed. The cheap `verify` steps have a 600 s watchdog with one retry (`VSTEP_TIMEOUT_S`): once on
2026-10-01, `build-gallery.mjs --check` printed `CHECK OK` and never exited, and `sample` showed
Node's exit path joining a V8 baseline-compiler thread stuck in allocation (a Node v26 exit
deadlock, not this repo's code; 0 of 6 immediate reruns hung).

**Browser lock.** There is one implementation, `scripts/with-browser-lock.sh`, shared by
`npm run test:ux` and every locked `showcase.sh` step (`ux`, `locked`, `bake`,
`overlay --preflight`). The lock is HOST-WIDE, outside any repository: `~/.cache/host-browser-lock/browser.lock`
(`$BROWSER_LOCK_DIR/browser.lock`; `with-browser-lock.sh --print-lock` prints it; until 2026-10-04 it was
`out/.browser.lock` in this project). It holds `<lane> <pid> <time>`, created atomically with
`noclobber`; only one browser runs on this host at a time, and waiters are served first come, first served through a
ticket queue (`<lock>.queue/`, `tests/ux/bringup/lockfifo.sh`). A lock whose owner pid is dead is
replaced only under the takeover mutex `<lock>.takeover`, after re-reading the lock and
finding the same dead owner line, so a waiter can never delete a lock another waiter has just
taken. After taking the lock it waits (cooldown, `COOLDOWN_WAIT_S`) for at least 6 GiB
free+inactive+speculative and no `chrome-headless-shell`, and runs the command under
`caffeinate -i` (this host idles to sleep after 1 minute; an unattended UX run once slept 988 s
mid-test). `showcase.sh` passes it `bash showcase.sh _inlock <kind> -- <cmd>`, which re-runs
this script's preflight inside the lock (no bake; or, for a bake, no browser and no Docker) and
then execs the command.

**Testing.** The tests of `showcase.sh` itself (refusals, exit codes, the browser lock, the served-gallery guard, the
skip rules of `all`) are recorded in [docs/HISTORY.md](docs/HISTORY.md) "Testing of `scripts/showcase.sh` on 2026-10-01".

## Dependency and pin model

### Pins (several registered, one active)

QED64 is pinned by **commit**. Several pins can be registered at once, and exactly one is **active** (served, tested,
deployed). A pin's id is the first 7 hex digits of its QED64 commit, because two commits can serve the same runtime
with different shells and workers (1859b83 and 5ac5d00 both serve `wasm64-4b025db7729c5f89`). The model is
`scripts/lib/pins.mjs`; the procedure and its evidence are in [docs/REPIN-LOG.md](docs/REPIN-LOG.md) "2026-10-02:
multiple pins".

| Pin | QED64 commit | Runtime | Shell / worker | Status |
|---|---|---|---|---|
| A `1859b83` | `1859b830` (promote `965c2494`) | `wasm64-4b025db7729c5f89` (kernel 0034, `9fbb45afcb`) | old shell, no QED64 liveness | staged: the fallback |
| B `9fdf9b8` | `9fdf9b85` | `wasm64-2c18773ecfba45bb` (kernel 0035, `3ae65d36f9`) | #52 worker (QED64 liveness) | staged for evidence only (L9) |
| C `5ac5d00` | `5ac5d00f` (QED64's interim local main) | `wasm64-4b025db7729c5f89` (kernel 0034) | #52 worker (QED64 liveness) | staged: the fallback (served 2026-10-02 to 2026-10-04; re-chosen by the final gate) |
| D `3b42714` | `3b42714d` ("promote kernel 0035b"; QED64's L9 fix candidate, not handed over yet) | `wasm64-3ab1c6a9da03bc29` (kernel 0035b, `a8817d01f9`: parking off by default) | #52 worker, byte-identical to C's | staged; served and fully gated 17:35–19:26Z on 2026-10-02 (two VERDICTs, headed sign-off), switched back because its storms were not cleaner than C's (docs/REPIN-LOG.md "final gate") |
| E `33b0967` | `33b09679` (QED64 main: merge of `fix/v2-reload-oom` over `3e182ff`; pushed 2026-10-03) | `wasm64-3ab1c6a9da03bc29` (D's runtime; promote `3b42714`; D's stores, equal by digest) | #52 worker + #55 runtime lifetime locks (QED64's L9 V2 fix), #54 boot card, in-chunk download progress | **active** since 2026-10-04 (pin-e lane: storms at least as clean as C's, two VERDICTs, headed sign-off, slow-link PASS, deploy check; docs/REPIN-LOG.md "pin E gated"; current state: `scripts/showcase.sh pin list`) |

| Store | Keyed by | Where |
|---|---|---|
| descriptor (`pin.json`: commit, promote, kernel, buildId, main bundle, served base trees, `liveness.builtIn`), lock | pin | `pins/<id>/` |
| QED64's sources at the pin's commit | pin | the submodule `deps/qed64` (active pin) or the worktree `$W/qed64-pins/<id>` |
| release clone (QED64's `dist/` + `public/`) | pin | `release/<id>/` |
| widget overlays, headless results | runtime | `out/runtimes/<buildId>/` |
| stage1, raw regions, bakes, bake keys, bake logs | runtime | `$W/runtimes/<buildId>/` |

The active pin is 13 symlinks at the familiar paths (`QED64.lock.json`, `out/headless`,
`out/overlay/snapshots/widgets{7,8}`, `$W/{stage1, raw, bake-out-w7/w8, bake-work-w7/w8, BAKE-KEY-w7/w8.txt, bake-logs}`;
the build-store links exist only in a checkout that built them) plus the submodule's checkout, so
every script reads the active pin through them or through `pins.mjs`; **no file hardcodes a pin** (`verify` FAILs on a
runtime buildId outside the generated `gallery/pin.json`, on a hashed QED64 bundle name and on a `release/wasm64-…`
path). The console allowlist names the QED64 bundle as `"@qed64-main-bundle"`. `serve.mjs` fixes its pin at start
(`SHOWCASE_PIN=<id>` serves a staged pin on another port) and says which in `X-Showcase-Pin`; `serve`, `ux` and the UX
suite refuse a server that serves another pin than the active one, and a UX run is a verdict only if the server served
the active pin from start to end.

### Switching pins (the fallback)

```
scripts/showcase.sh stop                      # a running serve.mjs keeps serving the pin it started with
scripts/showcase.sh pin use 5ac5d00           # or 33b0967 / 3b42714 / 1859b83 / 9fdf9b8: guards, atomic links, gallery/pin.json, deploy inputs
scripts/showcase.sh verify                    # the new active pin fully, the staged ones cheaply
scripts/showcase.sh headless controls         # optional: the wasm controls on the new active runtime
scripts/showcase.sh gallery                   # then `ux` for a verdict on the new pin
```

`pin use` also moves the submodule `deps/qed64` to the pin's commit and stages the switch (the lock link,
`gallery/pin.json`, the gitlink): commit them to record the served pin. It refuses (rc 3) for an unregistered or
incomplete pin, while this repo's `serve.mjs` (without `SHOWCASE_PIN`)
runs, during a bake, a headless run or a showcase browser run; an interrupted switch is reported by `pin current` and
finished by re-running `pin use`. The switches A→C→A→C, C→B→C and C→D→C were rehearsed, and C→E is the current one
(docs/REPIN-LOG.md). Each
switch regenerates `gallery/pin.json`, so the gallery hash changes (C `921b0b6a…`, before the v2mit lane's memory
wording `2081098d…`; D `eab4f147…` with the older wording) and a pin needs its own verdicts on its gallery (D's
`final-D-full1/2` were on `eab4f147…`; since `gallery/` changed, D needs two new `ux` runs after `pin use 3b42714`).

### Other pins

| Pin | Where | Checked by |
|---|---|---|
| The QED64 commit, promote, runtime buildId and kernel of each pin | `pins/<id>/pin.json` and `pins/<id>/QED64.lock.json` `qed64` | `pin-qed64.mjs verify` (S0.5 #1–#10): the tracked JSON equals `git show`, the reassembled `lean.wasm` sha256 equals the manifest, the profile parts and snapz digests match, the bundle names exactly this buildId, (#9) QED64's own `pipeline/toolchain/KERNEL-PIN` at the pin names the kernel, (#10) every `dist/` copy of a tracked `public/` file (the workers) equals `git show`; `pin check`: descriptor == lock |
| QED64's sources (no copies since 2026-10-04: the submodule `deps/qed64` / worktrees) | `.gitmodules` gitlink, the lock's `source` | `verify` #8: HEAD == commit, no tracked file modified, gitlink == HEAD == lock; no vendored copy present |
| 145 release files per pin (`dist/` built from source, runtime chunks, packs, stock snapshots fetched or cloned), nlink 1 | `release/<id>/`, the lock's `release.files` | `verify` #6; `scripts/build-shell.mjs`, `scripts/fetch-artifacts.mjs --check`; `deploy-manifest.mjs` L1 |
| the overlays of the pin's runtime (index + init + widgets `.snapz`) | `out/runtimes/<bid>/overlay/`, the lock's `overlays` | `verify` #11; `pin check`; `fetch-artifacts.mjs` |
| Widget sources `16cdb73b…` | each lock's `WIDGETS_SOURCE_HASH`, `$W/widgets-src` | `verify` #7 recomputes it |
| Toolchain: native64 `857544b439`, Docker image `8b6698bbf474` (the image the native oleans were built in; recorded equivalents in `toolchain.docker.equivalent`), Mathlib `5ed2965`, ProofWidgets `106ff4f`, Node v26.3.0, Playwright 1.62.1 / rev 1234 | each lock's `toolchain` | `verify` #7 (N/A without `QED64_KERNEL_BUILD`). The Docker image and the Node version are rebuild-only inputs: a mismatch prints `DRIFT` (a `FAIL` with `pin-qed64.mjs verify --strict`), and `showcase.sh native` refuses an image the lock does not record |
| The QED64 bundle the UX console allowlist names | `tests/ux/selectors.json` `"@qed64-main-bundle"`, resolved per pin; the allowlisted `notify` site (line 627) is recorded per pin in `pin.json` `consoleSites` | `verify` pin-constants (the token resolves to a bundle present in the active release); `pin check` (the line is the recorded notify line in every pin) |

Snapshots are **binary-paired** to the runtime. The worker refuses a mismatch with
`SNAPSHOT_UNPAIRED`, so any new runtime needs a rebake. The `?snapshots=` override the gallery
uses is a dev-only knob in QED64's boot code (`qed64-boot.ts:96-106`). It is part of the bundle
we pinned, so removing it upstream cannot break the showcase. Only a deliberate re-pin could.

### Re-pin: adding a pin when QED64 sends a new commit

With multiple pins a re-pin no longer edits code: it **registers** a new pin next to the others and switches to it only
after it passes the gates (procedure as executed for `5ac5d00` on 2026-10-02; the 1859b830 → 9fdf9b85 re-pin of
2026-10-01, before pins were keyed by commit, is the earlier entry in [docs/REPIN-LOG.md](docs/REPIN-LOG.md)).

1. **Preconditions (read-only).** The QED64 checkout is at the new commit and clean
   (`git --no-optional-locks rev-parse HEAD`, `status --porcelain`); `public/runtime/runtime-manifest.json` names the
   runtime; `dist/assets/*.js` embeds exactly that buildId; `dist/workers/*` equal the commit's `public/workers/*`
   (verify #10 checks it after the clone). If QED64's `dist/` is stale, wait for the owner's rebuild.
2. **Register.** Write `pins/<id>/pin.json` (`id` = the first 7 hex digits of the commit; `qed64.{commit, promote,
   kernel}` (kernel = the first token of `git show <commit>:pipeline/toolchain/KERNEL-PIN`), `buildId`, `mainBundle`
   (the one module script of `dist/index.html`), `consoleSites` (sha256 of line 627 of the main bundle, which must
   still be the `notify` line), `servedTrees`, `liveness.builtIn` (does the page's `status()` carry `liveness`?)).
   Copy an existing descriptor and change what differs.
3. **Clone.** `scripts/showcase.sh pin clone <id>` (report), then `pin clone <id> --yes`: release clone, lock,
   widgets hash, full verify. Writes only `pins/<id>/` and `release/<id>/`. `pin list` shows it staged.
4. **Same runtime as a registered pin?** (C shares A's: identical `public/snapshots/index.json`.) Then its stores exist:
   `pin check <id>` is OK and nothing is rebuilt. **A new runtime** needs its stores in `out/runtimes/<bid>/` and
   `$W/runtimes/<bid>/`:
   * native olean compatibility first: compare the new served core library (`pipeline/toolchain/work/build/stage1/lib/lean`)
     with the previous one file by file; if every `.olean`/`.ir`/`.ir.sig`/`.olean.server`/`.olean.private` is identical
     and the native toolchain pins are unchanged, the delta and widget oleans are reused, else stop: `showcase.sh native all`
     (Docker);
   * **without switching** (since the pin D lane): every build and verification step takes `SHOWCASE_PIN=<id>` and then
     works on that pin's own stores (`pins/<id>/`, `release/<id>/`, `$W/runtimes/<bid>/`, `out/runtimes/<bid>/`), never
     on the active links (`scripts/lib/pins.mjs` `targetPinId`/`storePath`; `ux`, `gallery`, `all` and `serve` on :5190
     refuse a target that is not the active pin). So: `cp -Rc` QED64's `pipeline/toolchain/work/build/stage1/bin` to
     `$W/runtimes/<bid>/stage1/bin`, then with `SHOWCASE_PIN=<id>`: `showcase.sh stage w7` / `w8` (`--force`; the trees
     are shared by all runtimes, so check they come out byte-identical), `bake all` (under the browser lock; a
     `REFUSED` because another session's browser runs is contention: retry), `overlay all`, the preflight
     (`PORT=5196 showcase.sh locked <what> -- bash scripts/preflight-overlays.sh widgets7 widgets8`; a staged pin is
     never preflighted on :5190), clone `bake-work-w{7,8}/widgets.snap` to `raw/widgets{7,8}.snap` in its store,
     `headless all` (under the browser lock) then `headless summary` (exits 1 at E2 because of the known L1 Demo; the
     gate is `stage4Green` and `E2Green`), and `pin check <id>` must print `PIN CHECK OK`. (The older route,
     `pin use <id> --allow-incomplete` and building through the active links, still works but switches the served pin.)
5. **Gate it while it is staged** (nothing switched yet): storm it interleaved with C (and A, B) in both browsers and
   on both entries, as the final-gate lane did: per-pin servers `SHOWCASE_PIN=<id> GALLERY_DIR=<copy from
   $W/final-gate/pin-gallery.mjs> PORT=<p> scripts/serve-start.sh`, then `ROUNDS=5 $W/final-gate/master.sh` (tool
   `tests/ux/tools/reload-storm-desktop.mjs`: chrome-headless-shell and headed Chrome for Testing, stock page and
   `/showcase/`, rotated pin order, plus a quiet-host round; tables by `$W/final-gate/tabulate.py`). The rule: switch
   only if its storms are at least as clean as C's in the same windows (docs/NEXT-STEPS.md §1). A single-pin smoke is
   `node tests/ux/tools/reload-storm.mjs --origin http://localhost:<p> --tag <t>` under `with-browser-lock.sh`.
6. **Switch and gate.** `showcase.sh stop` (if serving), `pin use <id>`, `verify`, `headless controls` (run it under the
   browser lock so no browser shares the host's memory), `gallery`, then two full `showcase.sh ux` runs back to back
   (both VERDICT), one headed sign-off (`UX_HEADED_ALL=1 UX_WARM_PROFILE=$PWD/out/ux/profiles/ux-warm-headed
   scripts/showcase.sh ux`) and at least 3 C20 runs (`showcase.sh ux --grep "C20 "`). Re-check D1/D2 without the bridge
   (`tests/experiments/x4-click-paths.mjs` under `showcase.sh locked`) when the shell changed. If a gate fails, `pin use`
   the previous pin (the fallback) and record why.
7. **Deploy inputs.** `pin use` regenerates `out/deploy` when it exists; check `node scripts/deploy-manifest.mjs --check`
   (its G2 must name a verdict run on this pin and gallery).
8. **Docs.** Record the old → new pin and the evidence in docs/REPIN-LOG.md; update this README, the upstream report
   and gallery/README.md.
9. **Deploy**, if publishing ([docs/DEPLOY-CLOUDFLARE.md](docs/DEPLOY-CLOUDFLARE.md) §3 and §6): artifacts first,
    then the shell: `DRY_RUN=1 scripts/upload-artifacts.sh`, `scripts/upload-artifacts.sh`, then
    `scripts/deploy-app.sh` (it refuses a shell whose R2 keys the newest upload did not publish), then
    `node scripts/deploy-manifest.mjs --smoke https://qed64-showcase.<subdomain>.workers.dev --all --range`. Back up
    `out/deploy/published/` (the release records rollback needs).

**Docker tag drift** (no QED64 promote needed). The native build runs in
`qed64-toolchain:emsdk-6.0.5`, a tag that QED64's own `pipeline/toolchain/build.sh` re-creates
with `docker build -t`. Another session can therefore move it. This happened on 2026-10-01, twice:
at 11:50:12 local `docker events` shows `create` + `tag` of `sha256:03d1d33bfb67…`, and by 12:41
the tag pointed at `sha256:30170d13e0f7…` (both report `Created 2026-08-25 15:26:43`). The image
`8b6698bbf474` that built our oleans is gone. The served artifacts do
not depend on the image (they are verified by hash), so `verify` prints `DRIFT` and stays green,
and only `native` refuses. Before re-running `native`:

1. Decide whether the current image is the intended toolchain, e.g. `docker history --no-trunc
   qed64-toolchain:emsdk-6.0.5` against `pipeline/toolchain/work/lean4/docker-wasm64/Dockerfile` in
   the QED64 checkout (read only). Native64 Lean and Lake come from the kernel build tree
   (`-v $K/native:/native:ro`), not from the image; the image supplies the Linux userland,
   including the C compiler (`LEAN_CC=/usr/bin/gcc`), so it does matter for the native oleans.
2. If it is: set `DOCKER_ID` in `scripts/pin-qed64.mjs` to the first 12 hex digits of the new id,
   then `scripts/showcase.sh pin --yes` (rewrites the lock; needs the S0.2 precondition), then
   `scripts/showcase.sh native all` and everything after it in the re-pin list (the new image
   built new oleans, so stage, bake, overlay, headless and UX follow).
3. If it is not: rebuild or re-tag the intended image yourself (QED64's tree is read only for
   this project), and re-run `verify` until `#7 docker` is `OK` again.

## Resources

| Stage | Memory | Wall time (measured) |
|---|---|---|
| Native build (Docker Desktop VM 8 GB = 7.65 GiB usable; settings never changed) | Container peaks: 1.6 GiB (B3, T=6), 2.9 GiB (widgets, T=6), 3.75 GiB (DistLens, T=4) | 134 s + 230 s + 1363 s |
| Bake (host Node, `bake-snapshot.mjs` from `deps/qed64`) | About 11 GB RSS (`time -l` maxrss 11.18 GB for w7, 10.30 GB for w8). `bake.sh` needs at least 12 GiB free+inactive. Never alongside a browser or Docker. | 385 s / 398 s |
| Headless wasm probes (E1/E3; E2) | 10.6–12.2 GB; 11.2–14.0 GB max RSS per Node process, one at a time | Stage 4: about 8 min per pass; controls 64 s |
| Browser (Playwright, gallery + page) | One tab about 8–9 GB at ready (renderer 8.2–9.0 GiB, UX C3), transient peaks about 12 GB on a reload (C10 11.8–12.2 GB), two tabs or "Load exact imports" about 17 GB or more ("Browsers and memory"). The lock requires at least 6 GB free+inactive before boot. | Boot to ready: 13–14 s (preflight boot smoke) |
| Disk (`du`; APFS clones share blocks) | – | `$W/mathlib4` 5.5 G, tree-slim-w7/w8 1.5/1.7 G, tree-fat 4.2 G, raw snaps 3.4 G, bake-work 1.1/1.2 G, overlays 0.36/0.40 G, `release/` 1.68 GB logical |

The host has 36 GB of RAM. Only one heavy job runs at a time. Large deletable artifacts, with sizes and commands:
[docs/HOUSEKEEPING.md](docs/HOUSEKEEPING.md).

## Limitations

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
* **L7, a rare QED64 runtime freeze.** The whole Lean runtime can stop in `elaborating` with its JS thread alive (a lost
  wake of the Emscripten main-thread mailbox; about 1 hang in 20 C20 runs on A). On the served E (and on C and D), QED64's own #52 worker
  heals it (message-mode mailbox, 1 s kick, Lean-side liveness with a `wedged` reboot); the gallery detects that and its
  own hover probe waits 30 s as a fallback. On A the gallery's probe is the recovery (restart about 20 s after the last
  progress); a pool saturated for longer than its probes is no longer restarted on A, because the gallery's main-loop probe
  is answered without a pool thread (UX C22 (3) green on A, `harden-A-c21c22`; A still has no full-suite verdict).
  No hang has been seen on C (23 C20 runs), D (4) or B (17); that sample is too small to prove the fix
  (`node scripts/ux-tally.mjs`). Details: gallery/README.md (L7), docs/UPSTREAM-REPORT-QED64.md L7, docs/HISTORY.md.
* **L9, a renderer crash about 2 s after a reload (or a relay restart that boots a new runtime).** A V8 OOM in a small
  isolate, most likely the renderer's shared V8 pointer-compression cage filling while the old page's ~25 workers are
  still alive (inferred; the binary is stripped). Two forms:
  * **V1** (after the *first* reload, `Scavenger: semi-space copy`) needs kernel 0035's parked threads: B only (C10
    crashed in 6 of the 8 runs that ran it on B; final-gate storms B 3/20). QED64's 0035b candidate D removes it (pool
    `parked 0` at every ready, 0 V1 in 27 storms); A and C never showed it.
  * **V2** (after reload 2–4, `MarkCompactCollector: young object promotion failed`, from isolates ~0.3 s old with
    15.8 MB heaps) hit **every pin before E**. QED64 fixed it in HARDENING #55 (runtime lifetime locks: a booting
    runtime waits while a stopping one keeps more than 12 Workers alive), and that fix is in the served E `33b0967`.
    QED64 measured 17/48 → 0/36 in headed embedded storms. Ours (pin-e lane, 2026-10-04, visitor path, E vs C
    interleaved): headed 0/20 vs 0/20, headless-shell 0/8 vs 1/8. That shows E is not worse, but C was rare in those
    windows too, so it does not confirm the fix (`out/ux/pin-e/RESULTS.md`). The windows below are the pre-E history
    (on C and the other pins). Each is a separate measurement, and they are not summed because the conditions
    differed:

    | window (2026-10-02, UTC) | browser | A `1859b83` | C `5ac5d00` | D `3b42714` | B `9fdf9b8` |
    |---|---|---|---|---|---|
    | l9-desktop 05:34–08:33 (all 7 V2 in 05:51–06:40) | headed | 1/5 | 4/19 | – | 2/8 (+1 V1) |
    | l9-desktop, same window | headless-shell / new headless | – | 0/6 / 0/6 | – | V1 only |
    | quiet slot 11:03–11:21 (owner kept the host free) | headed | 1/8 | 2/10 | 0/5 | V1 1/2 |
    | **final gate, 5 interleaved rounds 14:55–16:59** | both, both entries | 0/20 | 1/20 | 1/20 | V1 3/20 |
    | **final gate, quiet round 19:12–19:24** | headed, both entries | 3/6 | 1/6 | 2/6 | – |
    | **final gate total** | | **3/26** | **2/26** | **3/26** (+1 smoke) | V1 3/20 |
    | v2mit A/B 22:37–23:33, quiet, `/showcase/` only, the then-current gallery `2081098d…` | headed / headless-shell | – | 8/24 / 0/12 | – | – |

    In the final gate all 6 quiet-round crashes were through `/showcase/` (0/9 on the stock page in that round), and
    the headed runs of the loaded rounds had 0 V2 in 40; V2 also appeared in chrome-headless-shell for the first time
    (one C, one D run). So V2 does not need host pressure; the time clustering in the l9-desktop window (13–25 GiB
    reclaimable at every launch) is unexplained. That a fast idle host and the gallery's extra document put more of the
    new page's workers into the overlap is an inference, not shown. The UX suite's C10 (one 5-reload storm per full
    run) did not crash in 19 runs on C (17 full) or 4 on D. Sources: `out/ux/final-storm/RESULTS.md`,
    `out/ux/l9-desktop/RESULTS.md`, `out/ux/l9-quiet/RESULTS.md`, `node scripts/ux-tally.mjs`.

  **A gallery-side mitigation was tried and rejected** (`out/ux/v2mit-storm/RESULTS.md`): tearing QED64 down from the
  gallery's own `pagehide` (`qed64.relay.unload()`, then removing the iframe) gave headed V2 10/24 against 8/24 for the
  then-current gallery in the same quiet window (headless-shell 0/12 each), and a probe showed the old page's 26 workers
  already close 7–40 ms after a reload in both arms, 100+ ms before the new page creates its first worker; so the
  gallery's document order is not what overlaps. That lane left `gallery/gallery.js` unchanged.

  **What a visitor risked on C (per path; do not quote the pooled figures above for visitors).** Pin C, one storm = a fresh
  profile, boot, 5 reloads 3 s apart, Chrome for Testing 151 or chrome-headless-shell 151. The rate of one path differs
  between windows (host state, time of day; the windows are not comparable with each other, only arms interleaved in
  one window are), so each row gives its windows:

  | path | storms crashed (V2) | where |
  |---|---|---|
  | **headed Chrome through `/showcase/` (the visitor's path)** | **24/56 = 43 % (Wilson 95 % 31–56 %)**; latest window **15/24 = 62 % (43–79 %)** | **v2-embed arm S 15/24** (2026-10-03, quiet host, entry `/showcase/#hasse-view`); v2mit control arm 8/24 (quiet host, `/showcase/`); final-gate quiet round 1/3; final-gate interleaved rounds 0/5 (busier host) |
  | headed, test page: the stock page in a script-free same-origin iframe (not shipped; the cause test) | 16/48 = 33 % (22–47 %) | v2-embed arms I 6/24 (QED64's default document) and Is 10/24 (the hasse-view document) |
  | headed, stock page with the widgets overlay | 8/80 = 10 % (5–19 %) | l9-desktop 4/19, l9-quiet 0/5, final gate 0/8, v2-embed arms P 2/24 and Ps 2/24 |
  | headed, plain stock page `/` | 2/5 | l9-quiet |
  | chrome-headless-shell through `/showcase/` | 0/17 | final gate 0/5, v2mit control arm 0/12 |
  | chrome-headless-shell, stock page | 1/17 | final gate 1/5, l9-desktop 0/6, `multipin-storm` 0/6 |

  Branded Chrome and other reload rhythms were not stormed. **Why `/showcase/` is the worst path** (v2-embed lane,
  2026-10-03, 120 headed storms interleaved arm by arm after 300 s quiet streaks, `out/ux/v2-embed/RESULTS.md`):
  mainly **embedding itself**. With the boot document held equal, the stock page in a script-free iframe crashed in 10/24
  storms against 2/24 at top level (p = 0.017; pooled over both documents 16/48 vs 4/48, p = 0.005). The gallery's own
  JS and layout on top of that: 15/24 vs 10/24, p = 0.25, so an increment of about 20 points is neither shown nor
  excluded. The hasse-view boot document alone changes nothing at top level (2/24 = 2/24). Consequence (inference): the
  gallery cannot remove the main factor, because it is defined as the stock page in an iframe; the remedy is QED64's
  (docs/UPSTREAM-REPORT-QED64.md L9 now has the gallery-free repro).

  The gallery cannot prevent or survive a renderer crash. On C and the older pins, a visitor who reloads repeatedly can
  lose the tab; on E that is QED64's fix to deliver, with our storms not yet showing it in a high-rate window.
  Reported upstream (docs/UPSTREAM-REPORT-QED64.md L9, with the A/B as a hint for the follow-up: the old workers are
  already gone before the new page starts its own, so tearing them down earlier from a page script is not enough;
  inferred, the remedy is fewer isolates per page or a boot that waits for the previous runtime's memory to be released).
* **Slow links: first visits (fixed by the boot-fix lane, 2026-10-03).** A first visit downloads about 710 MB
  (runtime 159 MB, core packs 121 MB, the widgets8 region 397 MB, assets). Through a shaped link
  (`tests/ux/tools/throttle-proxy.mjs`; CDP emulation does not reach QED64's worker downloads) the gallery is ready in
  123 s at 50 Mbit/s / 40 ms (last-mile lane). At 10 Mbit/s the old fixed 360 s `BOOT_TIMEOUT_MS` showed "This is taking
  too long" at 467 s and never cleared, although QED64 was ready at 577 s; and from 231 s QED64's own boot card is gone
  (it removes it 120 s after its editor opens), so the visitor saw only timers. Now the boot wait is progress-aware
  (gallery/README.md "Timeouts"): at 10 Mbit/s the gallery is **ready at 565 s with the panel equal to its golden and
  no error card**, and a non-blocking notice "Still downloading: <QED64's step> — X of Y so far" covers 231–565 s
  (`out/ux/bootfix-throttle/explore/throttle-p10b.json`). **On E (QED64 #54, pin-e lane, 2026-10-04)** QED64's own
  boot card stays until ready with step, bytes, rate and time left. So the gallery's early-notice path never fires, and
  its notice comes from 467 s: 360 s after its first-boot wait began at 107 s. The run was ready at 565.1 s, with no
  error card, the panel equal, and the longest unchanged progress 6.0 s (19.0 s on C); `RESULT PASS`
  (`out/ux/pinE-throttle/explore/throttle-pe10.json`). Limits: the notice's figures are QED64's own (prepared bytes,
  e.g. a snapshot's raw 1.27 GB while 365 MB are downloaded); below about 3.2 Mbit/s QED64's 900 s snapshot prefetch gives up
  and QED64 streams the region without progress events (inferred from the bundle, not measured), where the 240 s stall
  rule could show the card, which then still closes on a later `ready`.
* **Browsers and memory.** The gallery checks cross-origin isolation, SharedArrayBuffer and WebAssembly Memory64 before
  anything boots; a browser missing one gets the card "This browser cannot run the Lean widget gallery" and nothing is
  fetched (UX C24, real Chromium for the no-isolation case; Memory64 and low memory simulated). A device reporting
  less than 8 GB (`navigator.deviceMemory`, Chromium only and approximate) gets a warning with "Try anyway". Measured
  need, renderer RSS in the six final-gate suite runs (`final-C-full1/2`, `final-D-full1/2`, `final-C-headed1`,
  `final-D-headed2`; extracted from their `tests/C{3,10,16,18}.json` into `$W/logs/memtext-measured.log`):
  * one tab at ready: renderer 8.2–9.0 GiB = 8.8–9.7 GB (UX C3), so **about 8–9 GB per tab**;
  * a reload (C10's 5-reload storm): transient renderer peak 11.8–12.2 GB, so **about 12 GB**;
  * two tabs (C18): 16.9–17.8 GiB = 18.1–19.2 GB; QED64's "Load exact imports" (C16, its restart with the exact
    imports): peak 15.5–16.6 GiB = 16.6–17.8 GB, so **about 17 GB or more** for either.

  The card, the `<noscript>` line and this page therefore ask for **a computer with 16 GB of RAM or more and one
  showcase tab at a time**. On a 16 GB machine a second tab or "Load exact imports" can still run out of memory; the
  device-memory warning threshold stays at 8 GB (a soft check; raising it is an owner decision). Browsers actually run:
  Chromium 151 (chrome-headless-shell for every verdict, headed Chrome for Testing for the sign-offs) and, in the
  last-mile lane, the installed branded Chrome 154 headed (32/34; its settled renderer after C10's storm is 10.67–10.75
  GB, 0.4–0.7 GB over Chrome for Testing's 10.07–10.26 GB, partly two extra small renderers). Safari 26.6.2 was not
  run: safaridriver refused the session because "Allow remote automation" is off, and no setting was changed; the
  system JavaScriptCore rejects the gallery's Memory64 probe (`WebAssembly.validate` false), so Safari most likely gets
  the capability card (inference). `ls ~/Library/Caches/ms-playwright` has no WebKit or Firefox build; Edge, Brave and
  Arc are expected to work as Chromium browsers but were not tested.
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

## Layout

```
QED64.lock.json               the ACTIVE pin's lock (a link into pins/<id>/; see "Pins")
pins/<id>/                    one registered QED64 pin each (id = 7-hex commit): pin.json, QED64.lock.json
deps/qed64                    git submodule: QED64 at the active pin's commit (staged pins: worktrees $W/qed64-pins/<id>)
scripts/showcase.sh           one entry point (this README)
scripts/                      bootstrap: qed64-src · build-shell · fetch-artifacts; lib/platform.{sh,mjs} (macOS/Linux)
                              pin-qed64 · assert-untouched · build-native · delta.py · header-gate · stage-trees · bake ·
                              judge-bake · pair-check · make-overlay · preflight-overlays · serve(.mjs|-start|-stop) ·
                              build-gallery · check-gallery · sim-gallery · deploy-manifest · headless/ (E1/E2/E3/E3b, controls)
vendor/react/                 React's UMD builds for the headless React contract check (not QED64 code)
release/<id>/                 (gitignored) dist/ (QED64's page built from the submodule) + public/{runtime,profiles,snapshots} (fetched)
rollback/wasm64-4b025db7…/    history: the 2026-10-01 re-pin's pre-edit copies (superseded by pins/1859b83; kept as is)
scripts/lib/pins.mjs          the pin model; scripts/pin-switch.mjs: pin list | current | check | use
lean/                         examples/<pkg>.{lean,json}, expect/ (native goldens), goldens/ (generator + gates) — lean/README.md
gallery/                      the M2 gallery wrapper + qed64-bridge.js — gallery/README.md
tests/                        experiments/ (X1–X5), ux/ (Playwright, UX lane)
infra/, wrangler.toml.example deploy kit for an own-origin Worker + R2 (shared bucket qed64-artifacts, prefix qed64-showcase/;
                              infra/deploy.env, infra/package.json = wrangler 4.125.0) — docs/DEPLOY-CLOUDFLARE.md (guide), docs/DEPLOY.md
out/                          (gitignored) runtimes/<buildId>/{overlay,headless} (per runtime; active links overlay/snapshots/widgets{7,8},
                              headless), pins/ (switch journal, history), click-all/, ux/, deploy/
work -> $QED64_SHOWCASE_WORK  (optional local symlink, gitignored) clones, trees, bakes, raw snaps, logs
docs/                         results, the upstream report, DEPLOY.md, research/ (BUILD-PLAN.md, PLAN-AMENDMENTS.md, maps)
```

Until 2026-10-04 this project was a stand-alone, uncommitted directory next to the widget tree (PLAN-AMENDMENTS 1–2);
it then moved into the widgets repository as `qed64-showcase/` (docs/REPIN-LOG.md "Repository move"). The design
study it implements (`06-qed64-showcase-options.md` of the research notes) is not part of the repository.
