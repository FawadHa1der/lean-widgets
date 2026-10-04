# Next steps (updated 2026-10-04, pin-e lane)

This page lists only what remains. What is done is in README.md (status page), docs/UX-RESULTS.md, docs/REPIN-LOG.md
and docs/HISTORY.md.

**Current state is printed by commands, not written here** (a written run name or count goes stale with the next run):

* `scripts/showcase.sh pin list`: per pin, the full UX runs on its lock, the VERDICT count and last VERDICT, the HEADED
  SIGN-OFF count and last sign-off;
* `scripts/showcase.sh gallery`: the gate, the current gallery content sha256, and `UX CURRENT …` (the newest verdict on
  exactly this gallery + lock + overlays, plus a headed sign-off if there is one) or `UX STALE`;
* `node scripts/deploy-manifest.mjs --check`: the `G2 UX:` line a deploy relies on;
* `scripts/showcase.sh verify`: pins, stores and the Docker `DRIFT` (§1).

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

## 1. Decide about the Docker image drift (owner)

`showcase.sh verify` prints one `DRIFT`. The lock records image `8b6698bbf474` for `qed64-toolchain:emsdk-6.0.5`, and
that is the image that built the native oleans. The tag now points at `sha256:8228ea564e7b`
(`$W/logs/finaldocs-verify.log`). QED64's own `pipeline/toolchain/build.sh` re-tags this image, and the old image is
gone.

The served artifacts do not depend on the image, because they are verified by hash. The drift matters only for a native
rebuild, and `showcase.sh native` refuses to run until it is resolved. There are two ways to resolve it (README.md
"Docker tag drift" has the commands):

* **Accept the current image.** Set `DOCKER_ID`, run `pin --yes`, then `native all` and everything after it: stage,
  bake, overlay, headless, gallery and two `ux` runs.
* **Restore the intended image.** Rebuild or re-tag it yourself. QED64's tree is read-only for this project.

Leaving it as it is costs nothing until widget sources or the toolchain change (see §3).

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

Publishing needs the owner's Cloudflare account (docs/DEPLOY-CLOUDFLARE.md §2–§3). The kit was rehearsed against local
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

## Pin E `33b0967`: what is left after the switch

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
