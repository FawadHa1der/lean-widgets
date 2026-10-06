# Next steps (updated 2026-10-06, pin-G lane)

This page lists only what remains. What is done is in README.md (status page), docs/UX-RESULTS.md, docs/REPIN-LOG.md
and docs/HISTORY.md.

## Pin G `5c327c2`: the embedding API v1 pin to gate (first, in this order)

**Where it stands (2026-10-06).** The live site serves E `33b0967` (QED64 main) with the pre-v1 gallery, deployed
2026-10-05. This checkout's active pin is G `5c327c2` (QED64 `feature/embedding-api`, pushed by the user; merging it into
QED64 main is the user's decision). G is F `84d594e` plus QED64's `e4cffcc`: edit back-pressure on the worker pool for
HARDENING #59, `?edithold=<n>`, at most 6 requests in flight, and a `$/cancelRequest` for a still-queued request answered
locally with `-32800`. It also adds `5c327c2` (deploy.yml step order). Runtime and API revision (`1.0.0`) are F's. F is
staged. The gallery and the UX suite run on QED64's embedding API v1 on F and G and keep the legacy flow for pins A–E.
G is **not yet gated in the browser and not deployed**, and nothing is committed. The working tree holds `pins/84d594e/`,
`pins/5c327c2/`, the lock link, the staged gitlink, `gallery/`, `scripts/` (including the `pin-qed64.mjs` fix that carries
`toolchain.docker.equivalent` forward), `tests/ux/` and these docs (docs/REPIN-LOG.md, pin F and pin G entries). Static
gates after audit round 6 (re-run by the docs stage): `BUILD-GALLERY CHECK OK 8 examples`, `CHECK-GALLERY OK 132 ok, 0 failed`
with its embedded `SIM-GALLERY OK 236 ok, 0 failed`, and `Total: 35 tests in 8 files`. Measured on F before audit rounds
2 to 6 changed the gallery: `CONTROLS PASS` 11/11 and one v1 smoke 22/22. Neither counts for G. Every browser step goes
through the lock wrapper.

1. **The v1 smoke on G** (`tests/ux/tools/v1-smoke.mjs`, one browser). Read `complete` in `out/ux/v1-smoke/report.json`,
   not only the pass count, and its `console.wholeRun` (whole-run pairing). Exit 3 means interrupted or incomplete. Run
   it in the background or with a small `LOCK_WAIT_S`, because its worst case is about 30 min.
2. **Headless controls on G**: `scripts/showcase.sh locked controls-G -- scripts/showcase.sh headless controls`
   (`CONTROLS PASS` 11/11 expected; the headless tools read `lsp-frames.js`, `artifact-paths.mjs` and
   `snapshot-probe.mjs` from G's checkout). An attempt on 2026-10-06 (`$W/logs/pinG-controls.log`) was still waiting for
   the host browser lock held by another session when that log was last written, so it has no result.
3. **Two full UX VERDICTs** on G's gallery: `UX_RUN=g-full1 LOCK_WAIT_S=21600 scripts/showcase.sh ux`, twice
   (`showcase.sh gallery` then prints `UX CURRENT`). Watch the console oracle for G's new cancel line, `QED64: the client
   cancelled this request before it reached the checker`. It is allowed only when paired (gallery/README.md "Console
   messages") and has not been seen in a browser yet. G's back-pressure logs `[qed64] edit back-pressure: …` with
   `console.debug`, which the oracle does not classify (log, info and debug are not failures). Those lines show whether
   a run held edits at all.
4. **Three `ux --grep "C20 "` runs** (`UX_RUN=<name> scripts/showcase.sh ux --grep "C20 "`).
5. **A headed sign-off**: `UX_HEADED_ALL=1 UX_RUN=g-headed1 scripts/showcase.sh ux`.
6. **The throttled first visit** at 10 Mbit/s (§4 has the commands). On a v1 pin the boot document comes from `#code=`
   and the boot wait from the API's `boot` events, so this is a new path.
7. **`node scripts/deploy-manifest.mjs --check`** (G2 must name a verdict on exactly this gallery and lock) and
   **`ci/rehearse-deploy.sh`** (plus `node ci/run-local.mjs --workflow .github/workflows/lean-ci.yml --job qed64-static`:
   the shell is now 59 files).
8. **Optional, ours: measure HARDENING #59 on G.** QED64 reports it fixed by `e4cffcc`. Type at 150 ms/char above a slow
   line with the InfoView open, and compare the pool size and the absence of a crash (docs/UPSTREAM-REPORT-QED64.md #59).
9. **Commit** (pins/84d594e, pins/5c327c2, the lock link, the gitlink, gallery, scripts, tests, docs). The Docker DRIFT
   on F is resolved: `pin-qed64.mjs pin` now carries `toolchain.docker.equivalent` forward, F's lock got the record
   back, and `verify` prints no DRIFT on F or G.
10. **The user's decisions:** push, and deploy (the `qed64-deploy.yml` dispatch or `scripts/deploy-app.sh`). Serving a
   commit of a QED64 feature branch before QED64 merges it is part of that decision. Which v1 pin to deploy is part of
   it too. G is the one being gated; F stays staged as G's fallback (`scripts/showcase.sh pin use 84d594e`).

The audit ran six rounds (docs/REPIN-LOG.md, pin F entry for rounds 1–4, pin G entry for rounds 5–6). The round-6 fix
stages fixed every item they were given. Nothing is recorded as open from them, but two residuals are noted. First,
`classify()` in `tests/ux/lib/qed64.mjs` has no unit test, so its emptyErrors change was checked by `node --check` only.
Second, the new cancel console entry is a fail-closed pre-allowance that no browser run has exercised yet.


**On QED64's side (gates our steps 5 and 6, "heavy path from a fetched release" and "drop the submodule and the source
build", not the G gates above):** a release manifest per promote (every served file with sha256 and size, buildId,
kernel commit, shell id, `apiRevision`, commit, slim-tree identity), a shell tarball, the `qed64/edge` export
(`isImmutable`, artifact keys, range parsing, isolation headers; a Worker factory with a second static root, root
redirect, R2 prefix, HEAD Content-Length and Range), and the slim base trees as a hashed artifact or a deterministic
rebuild CLI. HARDENING #59 (typing above an uncancellable command crashes the tab; docs/UPSTREAM-REPORT-QED64.md "#59")
stays open upstream.

## Pins A–E (history and what is left on E)

**Current state is printed by commands, not written here** (a written run name or count goes stale with the next run):

* `scripts/showcase.sh pin list`: per pin, the full UX runs on its lock, the VERDICT count and last VERDICT, the HEADED
  SIGN-OFF count and last sign-off;
* `scripts/showcase.sh gallery`: the gate, the current gallery content sha256, and `UX CURRENT …` (the newest verdict on
  exactly this gallery + lock + overlays, plus a headed sign-off if there is one) or `UX STALE`;
* `node scripts/deploy-manifest.mjs --check`: the `G2 UX:` line a deploy relies on;
* `scripts/showcase.sh verify`: pins, sources, stores (the Docker drift of §1 is resolved).

*History (dated, not current state).* At the end of the final docs lane (2026-10-03 ~03:50Z) pin C `5ac5d00` was
served on gallery `921b0b6a…` with verdict runs on it, no headed sign-off on it, `verify` OK with 1 Docker `DRIFT`, and
D `3b42714` staged (logs `$W/logs/finaldocs-*.log`, `$W` = the work dir, `QED64_SHOWCASE_WORK`). The boot-fix
lane (2026-10-03, ~05:00Z) then changed `gallery/gallery.js` (§4, slow first visits), so those verdicts no longer apply
to the current gallery. Its own three full `ux` runs on the new gallery were one red (one W4 renderer crash, cause
unknown, not reproduced in 20 W4 repeats) then two VERDICTs (docs/UX-RESULTS.md "Boot-fix lane"). The closure lane
(2026-10-03, 09:15Z onward) then ran two more full `ux` runs, both VERDICTs, and a headed sign-off on the same gallery
`31f6d8d9…`. It also re-ran the throttled first visits, a 60-minute soak and the deploy rehearsal there, and fixed three
test-tool defects (a sim-gallery timing race, G1's missing failure detail, byte reordering in `throttle-proxy.mjs`).
Details are in `out/ux/closure/RESULTS.md`. The pin-e lane (2026-10-04) then stormed E against C, switched the served
pin to E `33b0967` and gated it there (two verdicts, a headed sign-off, the 10 Mbit/s first visit, the deploy check and
rehearsal; `out/ux/pin-e/RESULTS.md`). §2 and §4 say what is still needed.

**L9 V2 could not be fixed from `gallery/`, and the fix came from QED64** (v2-embed lane, `out/ux/v2-embed/RESULTS.md`:
the extra V2 on the visitor's path comes mainly from running the stock page in a same-origin iframe at all). QED64's
HARDENING #55 is in the served E. Our storms on E are consistent with it but do not confirm it (§2).

## 1. Docker image drift: resolved (2026-10-04, R2 lane)

The tag `qed64-toolchain:emsdk-6.0.5` now names `8228ea564e7b`, while the lock recorded `8b6698bbf474`, the image that
built the native oleans. The R2 lane rebuilt all 512 native modules in the current image in a scratch copy of the
Mathlib tree. All 7,616 output files are byte-identical to the originals, so every lock now records `8228ea564e7b`
under `toolchain.docker.equivalent`, `verify` prints no DRIFT, and `showcase.sh native` accepts the image
(docs/BUILD-FROM-SOURCE.md "Docker image drift", docs/REPIN-LOG.md R2 entry). If the tag moves again, the same
experiment decides it. *Exception (2026-10-05, resolved 2026-10-06):* pin F's lock was first generated without that `equivalent` record, so
`verify` printed the DRIFT again on F. `scripts/pin-qed64.mjs pin` now carries the record forward from the pin's previous
lock or from any registered pin's lock. F's lock got it back, and G's lock has it, so `verify` prints no DRIFT on either.

## 2. Confirm QED64's #55 on our side, in a high-rate window (optional)

The pin-e lane's storms (2026-10-04) had E 0/20 vs C 0/20 headed and 0/8 vs 1/8 in headless-shell on `/showcase/#hasse-view`.
That is enough to serve E (it is not worse than C), but not to show that #55 removes V2, because C was nearly clean in
those windows (it was 15/24 the day before). To confirm the fix:

1. Wait for an idle host with 20 GB or more reclaimable. On 2026-10-04 the desktop apps kept it at about 15 GB; the
   v2-embed lane had 20.7–22.9 GB.
2. Serve C on its own port, and the active E as well: `SHOWCASE_PIN=<id> GALLERY_DIR=<pin-gallery copy> PORT=<port>
   scripts/serve-start.sh`, with copies from `$W/final-gate/pin-gallery.mjs`.
3. Re-run `$W/pinE2/master2.sh hd:1-4 hd:5-8 …` with `QUIET_GB=20` and the ports in `$W/pinE2/run-arm.sh`. It queues FIFO
   for the lock and takes the 300 s quiet streak inside the hold.
4. E is confirmed if C shows its usual rate (around 1 in 2) while E stays near 0.

Other pins: D `3b42714` (E's runtime with the #52 worker only) and A stay staged; C is the fallback (`pin use 5ac5d00`,
then two `ux` runs on the gallery that produces).

## 3. Pin the widget sources to a git commit, and add a `widgets-sync` command (pending the user's decision)

**Today.** `$W/widgets-src` is an rsync export of the `widgets-v4.34` working tree, made on 2026-10-01T02:50Z. It
excludes `.lake`, `.git`, `showcase/site`, `*.log` and `.DS_Store`, and holds 251 files. Every lock records its hash,
`WIDGETS_SOURCE_HASH` `16cdb73b…`. The export is tied to a hash, not to a commit.

This lane re-hashed the live tree read-only (`$W/logs/finaldocs-widgets-src.log`):

* The live tree is still identical to the export: 251 files, the same `SOURCE-FILES.sha256`, hash `16cdb73b…`.
* `git archive HEAD` would not reproduce the export. HEAD is `c812b91e` ("functioning widgets", 2026-09-30), and the
  working tree differs from it in four ways:
  * 55 tracked files are modified.
  * 8 `PORT-NOTES.md` files are untracked.
  * `.github/workflows/pages.yml` is in the export but ignored by `.gitignore`.
  * The tracked `showcase/site/*` files are left out of the export.

**Proposal (not implemented; it needs the user's decision and a commit in `widgets-v4.34` by the user, because this
project never writes there):**

1. Commit the ported widgets in `widgets-v4.34`.
2. Pin that commit in each lock (`WIDGETS_SOURCE.commit`).
3. Produce `widgets-src` with `git --no-optional-locks archive <commit>`, keeping the same exclusions, and check that
   its hash equals `16cdb73b…`. If it does, nothing is rebuilt.
4. Add `scripts/showcase.sh widgets-sync [<commit>]`, which:
   * re-exports the commit into a new directory;
   * compares hashes;
   * reports "unchanged", or lists the changed packages and the steps they need: native widgets, then stage, bake,
     overlay, headless, gallery, and two `ux` runs;
   * never switches automatically.

## 4. Deploy (owner)

Publishing needs the owner's Cloudflare account. Step by step: the **first deploy checklist** in
docs/DEPLOY-CLOUDFLARE.md (repository secrets, token scope, local artifact upload, first deploy from GitHub Actions or
from this machine, `SHOWCASE_ORIGIN`, verification); the GitHub Actions deploy (`.github/workflows/qed64-deploy.yml`)
was rehearsed in fresh clones by `ci/rehearse-deploy.sh` (R3 lane, 2026-10-04). The kit was rehearsed against local
fakes (history: on pin C by the post-audit fix lane on gallery `b7aa521a…`, 2026-10-03; on pin E by the pin-e lane on
gallery `bbdbc932…`, 2026-10-04, `rehearse.sh all`, `browser` and `stop` rc 0). Re-run
`scripts/deploy-rehearsal/rehearse.sh all` and `rehearse.sh browser` on the gallery you deploy. Never deploy pin B.

These owner decisions come before a public deploy. Each is measured in `out/ux/last-mile/RESULTS.md`:

* **Verdicts on the current gallery.** The gallery to deploy needs two full `ux` runs that are VERDICTs on it
  (`scripts/showcase.sh ux`, twice); `showcase.sh gallery` then prints `UX CURRENT`, and `deploy-manifest --check` G2
  names one. Check those commands for the current state. Also read `node scripts/ux-tally.mjs` for red full runs on
  the same gallery BEFORE the verdict: G2 reports only later ones (history: the boot-fix lane's `bootfix-full1` had a
  W4 renderer crash of unknown cause before its two verdicts; docs/UX-RESULTS.md "Boot-fix lane").
* **A headed sign-off on the gallery that will be deployed.** `pin list` prints the last HEADED SIGN-OFF per pin, and
  `showcase.sh gallery`'s `UX CURRENT` line names one when it is on exactly this gallery. Command:
  `UX_HEADED_ALL=1 UX_WARM_PROFILE=$PWD/out/ux/profiles/ux-warm-headed scripts/showcase.sh ux`. (History: none existed
  on `921b0b6a…`, and none on the boot-fix gallery `31f6d8d9…` as of that lane; the closure lane then recorded one on
  `31f6d8d9…`, 34/34 with C19, `out/ux/closure/RESULTS.md` (2).)
* **Slow first visits: fixed (boot-fix lane, 2026-10-03; on E also QED64's #54 boot card), one residual.** The boot wait re-arms on progress, shows
  "Still downloading …" instead of the card, and a later `ready` closes a stall card (gallery/README.md "Timeouts").
  Re-test after any gallery or pin change: `node tests/ux/tools/throttle-proxy.mjs --listen 5198 --upstream <serve
  port> --mbps 10 --rtt 40`, then under the lock `node tests/ux/tools/throttled-first-visit.mjs --origin
  http://localhost:5198 --no-cdp --mbps 10 --rtt 40 --max-s 1200 --tag <tag>`; pass = rc 0 and `RESULT PASS` (since
  the post-audit fix lane the tool judges itself: ready, no crash, `console ok`, no error card at all or at the end,
  visible progress after the first 5 s, panel EQUAL to its golden; rc 1 and `RESULT FAIL: <why>` otherwise; a deliberate
  stall test passes `--expect-card`). Use the proxy as fixed by the closure lane: the
  earlier version could reorder bytes within a connection, which once corrupted a snapshot download at 50 Mbit/s
  (`out/ux/closure/RESULTS.md` (3)). History: the closure lane's re-test on `31f6d8d9…` was 10 Mbit/s ready at 565.1 s
  and 50 Mbit/s at 120.3 s, both with no error card. On E (pin-e lane) at 10 Mbit/s: `RESULT PASS`, ready at 565.1 s,
  with QED64's card until ready and the gallery's notice from 467 s. The 50 Mbit/s run was not repeated on E. Residual, not measured: below about 3.2 Mbit/s (the widgets
  region's 365 MB download in 900 s) QED64's own snapshot prefetch gives up after 900 s and the checker streams the
  snapshot without progress events (inferred from the bundle); the gallery could then show its stall card after 240 s
  without progress, which still closes on a later `ready`. Measuring it needs a run of about 50 min at 2 Mbit/s.
* **Branded Chrome.** `lastmile-chrome-headed2` (Chrome 154) passed 32/34. Its C13b needs a headed baseline per
  browser build. Its C10 settles at 10.67–10.75 GB, over the 10.5 GB line; Chrome for Testing 151 settles at
  10.07–10.26 GB.
* **Memory threshold.** The texts ask for 16 GB of RAM, but the soft warning still triggers below 8 GB (`lib.js`
  `MIN_DEVICE_MEMORY_GB`). Raising it changes three tests and voids the verdicts.
* **Safari.** One-time user action: Safari → Settings → Advanced → "Show features for web developers", then Developer
  → "Allow remote automation". Then re-run `tests/ux/tools/safari-probe.mjs` (command in
  `out/ux/last-mile/RESULTS.md` (3)). Until then, the claim that Safari gets the capability card is an inference from
  JavaScriptCore.

## Pin E `33b0967`: what is left (E stays the live pin until a v1 pin, F or G, is deployed)

E was registered by the pinE lane and gated and served by the pin-e lane (2026-10-04; docs/REPIN-LOG.md "pin E gated";
`out/ux/pin-e/RESULTS.md`). The current state comes from `pin list`, `showcase.sh gallery` and `deploy-manifest --check`.
Not done yet:

* **Three `ux --grep "C20 "` runs on E** (the D/C gate had them). C20 passed 135/135 inside each of E's three gate runs,
  but there is no separate C20 tally on E yet: `UX_RUN=<name> scripts/showcase.sh ux --grep "C20 "`, three times.
* **The 50 Mbit/s first visit on E** (§4 has the command, with `--mbps 50`).
* **#55 in a high-rate window** (§2).
* **Owner choice (optional):** on E the gallery's "Still downloading" notice (from 467 s at 10 Mbit/s) repeats what QED64's
  own boot card already shows. Suppressing it while `#boot` is visible would be a `gallery.js` change. It would void the
  verdicts and need its own gates, sim runs and throttled re-test. It was not made.
