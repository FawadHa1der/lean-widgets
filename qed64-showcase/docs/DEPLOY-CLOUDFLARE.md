# Deploying the showcase to Cloudflare, the lean4game way

> **Status: DEPLOYED 2026-10-05** at https://qed64-showcase.fawadworkaddress.workers.dev (see "First deploy — record" below). Before that date the kit was only rehearsed locally.
> Every script and command below was run against local fakes (an rclone `local` remote, a local S3 endpoint and
> `wrangler dev --local`) or as a dry run, inside a macOS sandbox that blocks all outbound traffic except to localhost.
> See [Rehearsal](#rehearsal). The GitHub Actions deploy (`.github/workflows/qed64-deploy.yml`, section 9) last ran on
> GitHub for pin H (the push of `d60b15e`, 2026-10-08); its job was also run on this machine in fresh clones by
> `ci/rehearse-deploy.sh` ([CI rehearsal](#ci-rehearsal)). **Start with the [first deploy checklist](#first-deploy-checklist).** Two kinds of
> command were not run here:
> * commands marked **[account]**, which need your Cloudflare login or R2 token;
> * the 3.1 preconditions `showcase.sh gallery` / `ux`, which the verification lanes run (the rehearsal below found
>   `final-full1` on pin B; the re-rehearsal on pin C found `multipin-C-full3-b`, the final-gate re-run `final-C-full2`).
>   `showcase.sh verify` was run here.
>
> **Release routing (2026-11-02, `f13d535` on the branch `release-routing`, with fixes up to `eca8f22`; on `main` since the push of `b24587d`, 2026-11-05).** This guide describes the
> deploy code at that commit: the Worker reads the runtime and the packs from the toolchain release, the upload is 12
> objects, 1.107 GB at pin O (9 objects, 0.745 GB from P2 on, with one overlay), and `deploy-app.sh` checks each new
> version on its preview URL before it takes traffic. O was deployed with it on 2026-11-05 (section 6); H, on the Worker
> from before that commit, is the rollback target (section 5). P1 and P2 (local branch `p1-p2`, not pushed) retire the
> pins A–L and the widgets7 overlay; nothing in this guide's deploy path changes for O. Both rehearsals of this code passed, 2026-11-02 to
> 11-04: [Rehearsal](#rehearsal) and [CI rehearsal](#ci-rehearsal) have the results. The other dated records in this file
> are from before that commit.
>
> **Current inputs: printed by the tools, not written here** (each later run or gallery edit would make a written name
> wrong). Before uploading, run:
> * `scripts/showcase.sh pin current` / `pin list`: the active pin, and per pin the full UX runs on its lock with the
>   VERDICT count and last VERDICT and the HEADED SIGN-OFF count and last sign-off;
> * `scripts/showcase.sh gallery`: the current gallery content sha256, then `UX CURRENT …` (the newest verdict run on
>   exactly this gallery + lock + overlays, plus a headed sign-off if one exists) or `UX STALE`;
> * `node scripts/deploy-manifest.mjs --check`: `G1 … CHECK-GALLERY OK`, the `G2 UX:` line (the verdict this deploy
>   relies on; it must name a run on THIS gallery) and `DEPLOY-MANIFEST CHECK OK`.
>
> Do not deploy pin B. Pins before `385a1ac` (A–H) cannot be deployed from this Worker: `deploy-manifest` refuses them
> (section 5 has the rollback to H). A switch to another pin from I on (for example N `58ebbad`) produces a new gallery
> hash, so it needs two new verdict `ux` runs on that gallery before G2 passes. Owner decisions before a public deploy (headed sign-off on the deployed
> gallery, branded-Chrome baselines, memory threshold): docs/NEXT-STEPS.md §4.
>
> *History (dated, not current state):* at the end of the final docs lane (2026-10-03 ~03:50Z) the served pin was C
> `5ac5d00` and the gallery `921b0b6a…`, with `deploy-manifest --check` OK (`$W/logs/finaldocs-deploy-manifest-check.log`).
> The boot-fix lane (2026-10-03, ~05:00Z) then changed `gallery/gallery.js` (the slow-link boot fix below), so every
> verdict on `921b0b6a…` stopped applying (`showcase.sh gallery` reported `UX STALE` until that lane's own `ux` runs,
> `$W/logs/bootfix-gallery.log`). That lane regenerated `out/deploy` for the new gallery (only `showcase/gallery.js`
> changed in the manifest) and `deploy-manifest --check` was OK with a G2 verdict on it
> (`$W/logs/bootfix-deploy-manifest-check.log`). The closure lane (2026-10-03, 09:15Z onward) regenerated the manifest (byte-identical,
> gallery `31f6d8d9…`), got `--check` OK with a G2 verdict on that gallery, and re-ran the fake-R2 rehearsal (`all`, then
> the browser boot-check) on it (`out/ux/closure/RESULTS.md` (5)). The post-audit fix lane (2026-10-03, from 16:28Z)
> changed `gallery.js` and `gallery.css` (gallery `b7aa521a…`), regenerated the manifest (only those two entries and the
> totals changed), got `--check` OK with a G2 verdict on that gallery, and re-ran `rehearse.sh all`, `browser`, `stop`
> (rc 0 each, `BOOT-CHECK OK`; docs/UX-RESULTS.md "Post-audit fix lane"). The pin-e lane (2026-10-04) switched the
> served pin to E `33b0967` (gallery `bbdbc932…`, same gallery code); `pin use` regenerated the manifest and the lane
> re-ran `generate` (byte-identical), got `--check` OK with a G2 verdict on that gallery, and re-ran `rehearse.sh all`,
> `browser`, `stop` (rc 0 each, `BOOT-CHECK OK`; `out/ux/pin-e/RESULTS.md` §4). Re-run `scripts/deploy-rehearsal/rehearse.sh
> all` on the gallery you deploy.
>
> **What visitors of the deployed site need (measured).**
> * **Browser:** a Chromium-based desktop browser. Tested: Chromium 151 (chrome-headless-shell for the verdicts, headed
>   Chrome for Testing for the sign-offs) and the installed branded Chrome 154, headed (32/34; not a sign-off: a
>   scrollbar baseline and C10's memory line). Edge, Brave, Arc: expected to work as Chromium, not tested. Safari
>   26.6.2 was not run (WebDriver refused because "Allow remote automation" is off); its JavaScriptCore rejects the
>   gallery's Memory64 probe, so Safari most likely gets the capability card (inference). The Worker's COOP/COEP/CORP
>   headers make the page cross-origin isolated; the gallery then checks SharedArrayBuffer and WebAssembly Memory64
>   before it fetches anything, and a browser without them gets a card saying what is missing instead of a broken page.
> * **Memory:** 16 GB of RAM or more, one showcase tab at a time. One tab's renderer is 8.2–9.0 GiB at ready, with
>   transient peaks of about 12 GB on a reload; two tabs or QED64's "Load exact imports" take about 17 GB or more
>   (README.md "Browsers and memory"; six final-gate suite runs). A device reporting under 8 GB gets a warning with
>   "Try anyway" (gallery/README.md "Boot flow" step 0).
> * **Network:** a first visit downloads about 710 MB in total (676 MB of R2 artifacts, 3.5, plus the app shell): about
>   2 min at 50 Mbit/s and about 9.5 min at 10 Mbit/s (ready at 565 s with the panel and no error card; a "Still
>   downloading …" notice from 231 s; boot-fix lane, `out/ux/bootfix-throttle/explore/throttle-p10b.json`). On E (QED64
>   #54; pin-e lane, 2026-10-04) QED64's own boot card, with step, bytes, rate and time left, stays until ready at
>   565.1 s; the gallery's notice comes from 467 s; `RESULT PASS`. Before that
>   fix the gallery's fixed 360 s boot timeout stranded such visitors on "This is taking too long" (last-mile lane).
>   Later visits load from OPFS and the HTTP cache.
> * **Reload storms (QED64 L9 V2): fixed upstream in the served pin E `33b0967` (HARDENING #55), not yet confirmed by our
>   storms.** On every pin before E, a visitor who reloaded several times in quick succession could lose the tab (the
>   renderer dies about 2 s after the 2nd–4th reload of a burst). QED64 measured its fix at 17/48 → 0/36 in headed
>   embedded storms. **Ours, on the visitor's path `/showcase/#hasse-view` (pin-e lane, 2026-10-04, interleaved with
>   C): E 0/20 headed and 0/8 in chrome-headless-shell; C 0/20 and 1/8.** E is therefore not worse than C, but C was
>   nearly clean in those windows too, so the storms do not show the reduction (`out/ux/pin-e/RESULTS.md`). For E on
>   that path, the headed rate is below 16 % (95 % upper bound of 0/20) in such a window. It has not been measured in a
>   high-rate window (docs/NEXT-STEPS.md §2).
>   *History, if the deploy falls back to pin C:* on C the visitor's path lost the tab in 24 of 56 storms (43 %, Wilson
>   95 % 31–56 %; the v2-embed lane's quiet-host window, 2026-10-03, 15 of 24, 62 %, 43–79 %). Plan for about one storm
>   in two there. The other paths on C were lower and must not be quoted for visitors: headed stock page with the
>   widgets overlay 8/80 = 10 %, headed plain `/` 2/5, chrome-headless-shell `/showcase/` 0/17, stock page 1/17. **The
>   main cause on C was embedding, not the gallery's code:** the stock page inside a script-free same-origin iframe
>   crashed in 16/48 storms against 4/48 at top level (Fisher p = 0.005); the gallery's JS on top added 62 % vs 42 %, not
>   significant (p = 0.25), and a gallery-side teardown did not help (10/24 with it, 8/24 without). Browser: Chrome for
>   Testing 151; branded Chrome and other reload rhythms were not stormed. Sources: `out/ux/pin-e/RESULTS.md`,
>   `out/ux/v2-embed/RESULTS.md`, `out/ux/final-storm/RESULTS.md`, `out/ux/v2mit-storm/RESULTS.md`,
>   `out/ux/l9-desktop/RESULTS.md`, `out/ux/l9-quiet/RESULTS.md`, `docs/UX-RESULTS.md` (`multipin-storm`); README.md
>   "Limitations".

This guide follows the same recipe as `wasm64-lean4game` (`wasm/DEPLOY.md`), which follows QED64's own production
setup:

* **App shell.** A Cloudflare Worker with static assets. The pinned QED64 `dist/` is served at `/` and the gallery at
  `/showcase/`, together 77 files and about 18.6 MB at O's upload (76 from P1 on: the gallery ships 16 files, without
  `qed64-bridge.js`).
* **Artifacts.** These live in the **R2 bucket `qed64-artifacts` that QED64 already uses**. The runtime and the packs
  are the kernel's published toolchain release under `lean4-wasm64/<release id>/` (`lean-v4.35.0-b081e7c` at pin O: 81
  objects, 1.260 GB), read in place and never uploaded by us. Our own objects (the stock snapshot pair, our overlays
  and the indexes: 12 objects, 1.107 GB at O's upload; 9 objects, 0.745 GB from P2 on) go under their own prefix `qed64-showcase/`, just as lean4game uses
  `lean4game/`. They are uploaded through the **existing rclone remote `qed64-r2`**, and the same bucket-scoped token
  serves all three apps.
* **One origin.** `infra/worker.js`, QED64's `createWorker` with the pin's toolchain record, puts COOP/COEP/CORP on
  every response. Without these headers the browser refuses SharedArrayBuffer and Memory64, and QED64 cannot start.
* **Uploads use `rclone copy`, never `sync`.** Phase order is digest-named objects, then the indexes no older shell
  reads, then the shared `index.json` files (`PHASES=` uploads a subset, for a split around the Worker deploy: 3.2).
  wrangler 4.125.0 is pinned in `infra/package.json`. `scripts/deploy-app.sh` stages the shell, runs `wrangler versions
  upload`, checks that version on its preview URL and only then runs `wrangler versions deploy` (3.3).

| URL | Served from | Content |
|---|---|---|
| `/showcase/` | Workers static assets | the gallery (`gallery/` without `*.md` and dotfiles) |
| `/` | Workers static assets | the pinned QED64 `dist/` (`release/<pin id>/dist`, byte-identical to `QED64.lock.json`). A bare `/` redirects to `/showcase/` (`ROOT_REDIRECT`). The gallery iframes `/?snapshots=snapshots/<dir>` (the pin's served overlay directory, below), which is never redirected. |
| `/runtime/…`, and `/profiles/…` except `/profiles/index.json` | R2 key `lean4-wasm64/<release id>/<path>`: the release in the pin's toolchain record `deps/qed64/toolchain/lean4-wasm64-release.json` (`hosting.mount`) | runtime chunks + manifests, core and mathlib-essential packs (81 objects at pin O). Never uploaded by us. A miss is a `no-store` 404 and never falls back to our prefix |
| `/profiles/index.json`, `/snapshots/…` | R2 key `qed64-showcase/<path>` (`hosting.siteOwned`) | the profile index, the stock snapshot pair, QED64's per-build index copies `snapshots/index.<buildId>.json` and `snapshots/profiles-index.<buildId>.json`, our overlay `snapshots/<dir>/`: `widgets8.<bid16>/` (`scripts/lib/pins.mjs` `overlayDir`; O: `widgets8.36d7f415704473d9/`; O's upload also put `widgets7.<bid16>/` there, which no pin reads after P2 and which stays while O is a rollback target, section 6), so a new runtime never overwrites the overlay an older live shell reads (pins A–H, which this Worker does not serve, used the bare `widgets8/` and `widgets7/`). The Worker does no alias or rewrite; `?overlay=widgets8` is mapped in the gallery |

The deploy target is set in one place, **`infra/deploy.env`**:

```
R2_REMOTE=qed64-r2
R2_BUCKET=qed64-artifacts
R2_PREFIX=qed64-showcase/
WORKER_NAME=qed64-showcase
```

`scripts/upload-artifacts.sh`, `scripts/deploy-app.sh` (through `scripts/lib/wrangler-config.mjs`, which writes and
checks `wrangler.toml`), `scripts/rollback-artifacts.sh` and `node scripts/deploy-manifest.mjs --commands` all read
this file through one loader, `scripts/lib/deploy-env.mjs` (`node scripts/lib/deploy-env.mjs` prints the resolved
target). An environment variable with the same name overrides a line. The bucket and prefix that the upload writes to
are therefore always the ones the Worker reads from.

**Shared-bucket guard.** The bucket `qed64-artifacts` is shared:
* QED64's site-owned objects sit at its root: `profiles/index.json` and `snapshots/`. Its root `runtime/` and
  `profiles/` copies were removed on 2026-10-23; the names stay refused.
* The lean4-wasm64 toolchain releases sit under **`lean4-wasm64/<release id>/`**, uploaded by the release's owner.
  Since QED64 `4b98279`, QED64's Worker reads `/runtime/*` and `/profiles/<not index.json>` *only* from there, with no
  fallback to the root, and lean4game serves the same objects. A release prefix holds the one copy QED64 and lean4game
  serve, and from release routing on the showcase's too: its Worker reads the pin's release from there in the same way
  and uploads nothing to it. The live H Worker, from before release routing, still serves its own copies under
  `qed64-showcase/`.
* lean4game's own objects sit under `lean4game/`.

A wrong prefix there would overwrite another app's *mutable* names (`runtime-manifest.json`, `profiles/index.json`,
`snapshots/index.json`, `*.manifest.json`) or a toolchain release. So in that bucket the loader accepts only
`R2_PREFIX=qed64-showcase/`:
* an **empty** prefix, or one inside `lean4game/`, `lean4-wasm64/`, `runtime/`, `profiles/` or `snapshots/`, is
  **always refused** (`deploy target refused: …`), with no override. lean4game falls back to its own prefix when
  `R2_PREFIX` is empty; here an empty value is refused instead, because it almost always means a half-applied
  own-bucket setup;
* any other prefix (for example a staging prefix `qed64-showcase-staging/`) needs `ALLOW_SHARED_PREFIX=1`, set
  deliberately.

Every script checks this before it runs rclone or wrangler. The rehearsal's `guard` step proves it on a fake bucket
seeded with stand-ins for QED64's root objects, a `lean4-wasm64/<release id>/` release and lean4game's manifests.


## First deploy — record (2026-10-05, done from this machine)

| Step | Result |
|---|---|
| Preconditions | `showcase.sh verify`: all checks OK; `gallery`: GREEN on `3b4dc8bb…`, `UX CURRENT` (run `r4-main-full4`); `deploy-manifest --check`: OK, G2 names `r4-main-full4`; `wrangler whoami`: logged in (OAuth, workers write) |
| Bucket before | `rclone size qed64-r2:qed64-artifacts`: 396 objects, 13.70 GiB (QED64 + lean4game; above the 10 GB free tier already, so storage is billed) |
| Upload | `DRY_RUN=1 scripts/upload-artifacts.sh`: UPLOAD DRY RUN OK; then `scripts/upload-artifacts.sh`: UPLOAD OK, 11 lists, 93 objects, 2.420 GB, 3 multipart, copy only; release record `out/deploy/published/20261005T152953Z` |
| Deploy | `DRY_RUN=1 scripts/deploy-app.sh`: RECORD OK (this shell's 93 keys == the record), DEPLOY DRY RUN OK; `scripts/deploy-app.sh`: 74 assets uploaded, Worker `qed64-showcase` version `ae781eae-35f9-49de-a739-440ffe587a69`, URL https://qed64-showcase.fawadworkaddress.workers.dev |
| Smoke | `--smoke <url> --all --range`: first run 3 FAIL (the edge serves HTML with `content-encoding: br` and no content-length on HEAD; the check was fixed to compare the decoded size for page assets, artifacts unchanged); then **SMOKE OK**: 168 URLs (75 assets + 93 R2 keys), isolation headers, cache rule, Range 206 / 416 / mismatched If-Range → 200 |
| Cold boot | `scripts/deploy-rehearsal/boot-check.mjs <url>` (headless Chrome, fresh profile, under the host browser lock): **BOOT-CHECK OK** — QED64 ready with hasse-view after 209 s, 26 artifact GETs (677.1 MB, all 200), HasseView panel rendered (`out/deploy-live/boot-hasse-view.png`); 1 page error = QED64's known boot-time `Error: unsupported` (N1) |
| Rollback | `scripts/rollback-artifacts.sh out/deploy/published/20261005T152953Z` + redeploy of the previous shell (section 5); **back up `out/deploy/published/`** |

Not done at that time: the GitHub repository had no Actions secrets, so the `qed64-deploy` workflow ran in skip mode
(as designed); `SHOWCASE_ORIGIN` was not set as a repository variable yet.

## First deploy checklist

For the owner, in this order. Every step marked **[account]** needs your Cloudflare login, an R2 token or the GitHub
repository's settings; nothing else contacts Cloudflare. Run the commands in `qed64-showcase/` of the checkout that
has the artifacts (`release/<pin>/public/`, `out/overlay/snapshots/`), i.e. the machine that baked them.

The Worker `qed64-showcase` and its repository secrets already exist (H went live through a `qed64-deploy` run on
2026-10-08), so deploying O over H needs only step 2, step 3, the Preview URLs of step 6, the push
(`git push origin release-routing:main`, not step 1's command, while the local `main` is behind that branch) and step 8.
docs/NEXT-STEPS.md gives the order. The other steps are for a new account or a new Worker.

1. **Push the repository** (`git push origin main`, plus `git push origin lean-v4.32.2` for the v4.32.2 tag).
   `lean-ci` runs; `qed64-deploy` runs and logs `CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID not set — skipping
   deploy`, because the secrets do not exist yet. Add them only after step 3: with the secrets in place, every push to
   `main` that touches `qed64-showcase/` deploys.
2. **Preconditions, local** (section 3.1): `scripts/showcase.sh verify`, `scripts/showcase.sh gallery` (GREEN, then
   `UX CURRENT …`), and `node scripts/deploy-manifest.mjs --check` (its `G2 UX:` line names a verdict run). A
   `out/deploy/manifest.json` written before release routing (`f13d535`: no `release` key) fails `--check` until it is
   regenerated: run `node scripts/deploy-manifest.mjs --prefix qed64-showcase/` first, or `DRY_RUN=1
   scripts/upload-artifacts.sh`, which regenerates and checks. The CI
   deploy's copy of that verdict is the committed `infra/ux-verdict.json` (`cat` it for the run, gallery, lock and
   overlays it names; `--check` prints whether it matches the current inputs). After any change to `gallery/`, the
   lock or the overlays, run `scripts/showcase.sh ux` again and re-record it, or the CI deploy refuses (`no verdict UX
   run for exactly this gallery …`):
   ```
   node scripts/deploy-manifest.mjs --record-verdict      # writes infra/ux-verdict.json; refuses a stale manifest or a later red run
   git add infra/ux-verdict.json && git commit -m "qed64-showcase: UX verdict for CI"
   ```
3. **Upload the artifacts** (section 3.2) **[account]**, then back up the release record (section 5). The runtime and
   the packs are not part of this: they are the toolchain release, already in the bucket under
   `lean4-wasm64/<release id>/`:
   ```
   rclone listremotes                       # must list qed64-r2: (reads only the local config)
   rclone size qed64-r2:qed64-artifacts/lean4-wasm64/<release id>/   # at least 81 objects, 1.260 GB at pin O; the upload does not check
   DRY_RUN=1 scripts/upload-artifacts.sh    # lists the bucket, writes nothing
   scripts/upload-artifacts.sh              # 9 objects, 0.745 GB at pin O from P2 on; copy only, never sync
   ```
4. **Create the Cloudflare API token** **[account]**: dashboard → My Profile → API Tokens → Create Token → Custom
   token. Permissions: **Account → Workers Scripts → Edit**. Account Resources: **Include → the account that holds
   `qed64-artifacts`**. No zone permission and **no R2 permission**: the Worker reads R2 through its binding, and a
   leaked CI token then cannot touch any bucket. This is the scope lean4game's and QED64's guides name for CI;
   it was not tried against a live account here with the two `wrangler versions` commands. If one of them stops in
   step 6 with an authentication error that names another permission, add exactly that one. Optionally set a TTL and
   IP filtering.
   The account ID: dashboard → Workers & Pages → Account ID (right-hand column), or `npx --prefix infra wrangler whoami`.
5. **Add two repository secrets** **[account]** on `github.com/FawadHa1der/lean-widgets` → Settings → Secrets and
   variables → Actions → Secrets → New repository secret:

   | Name | Value |
   |---|---|
   | `CLOUDFLARE_API_TOKEN` | the token from step 4 |
   | `CLOUDFLARE_ACCOUNT_ID` | the 32-hex account ID |

   No other secret is used. The R2 keys (S3 access key and secret) stay in your local rclone config and are never
   added to GitHub.
6. **First deploy.** One or two one-time things come first:
   * **Preview URLs [account]:** turn them on for the Worker `qed64-showcase` (dashboard: the Worker, Settings, Domains
     & Routes) before the first deploy of O. `deploy-app.sh` tests every new version on its preview URL before it takes
     traffic. With Preview URLs off, `wrangler versions upload` prints no `Version Preview URL:` line, and `deploy-app.sh`
     refuses with that reason and promotes nothing. The line `preview_urls = true` in `wrangler.toml.example` does not do
     this for an existing Worker: wrangler 4.125.0 applies that key in `wrangler deploy` and `wrangler triggers deploy`,
     not in `wrangler versions upload` (`subdomainDeploy` in `infra/node_modules/wrangler/wrangler-dist/cli.js`).
   * **A brand-new Worker only:** one `wrangler deploy`. `wrangler versions upload` refuses a Worker that does not exist
     yet ("You cannot upload a new version of a Worker that does not yet exist. Please run the `deploy` command first.",
     same file). `DRY_RUN=1 scripts/deploy-app.sh` stages the assets and writes `wrangler.toml`; then run
     `npx --prefix infra wrangler deploy --config wrangler.toml` **[account]**. That one deploy goes out without the
     pre-promotion check, on a Worker that has no visitors yet. This path was not rehearsed. The Worker `qed64-showcase`
     exists, so O does not need it.

   Then either way:
   * **From GitHub:** Actions → `qed64-deploy` → Run workflow, first with `dry_run` ticked (everything up to `wrangler
     versions upload --dry-run`; works even without the secrets), then without. The log must show `PRE-PROMOTION OK`,
     `DEPLOYED-URL https://qed64-showcase.<subdomain>.workers.dev` and `SMOKE OK`. A missing upload stops the run at the
     pre-promotion check with nothing promoted.
     Use Run workflow, on `main`, to deploy again, and not "Re-run jobs" on a run once `main` has moved on. A re-run keeps
     that run's commit and workflow file, and its committed verdict still matches. If the newer commit's upload replaced
     none of that run's indexes (a gallery or workflow change, or a re-pin that keeps the runtime and its indexes), the
     re-run's objects are all still in the bucket: its pre-promotion check passes and it promotes the older version over
     the newer one, and nothing refuses that. If the newer upload replaced `/profiles/index.json`, `/snapshots/index.json`
     or an overlay index, the check refuses the re-run with nothing promoted. A run from before release routing (H's run on
     `d60b15e`) has no pre-promotion check at all. (Read from the workflow, the scripts and GitHub's docs; not run.)
     `wrangler rollback` undoes a wrong promotion.
   * **From this machine:** `npx --prefix infra wrangler login` **[account]**, then `DRY_RUN=1 scripts/deploy-app.sh`
     and `scripts/deploy-app.sh` (section 3.3; it checks the release record of step 3), then the smoke of section 3.4.
7. **Set the repository variable** **[account]** Settings → Secrets and variables → Actions → Variables → New
   repository variable: `SHOWCASE_ORIGIN` = `https://qed64-showcase.<subdomain>.workers.dev` (or your custom domain,
   section 7), no trailing slash. It only names the origin of the post-deploy smoke; without it the smoke uses the URL
   `deploy-app.sh` derived from the preview URL. The check before promotion does not read it: every CI deploy runs
   `deploy-manifest.mjs --published` and `--smoke --all --range` on the new version's preview URL and refuses to promote
   a shell whose artifacts were not uploaded.
8. **Verify** (section 3.4/3.5): the workflow log's `SMOKE OK`; `curl -sI <origin>/showcase/ | grep -i cross-origin`
   shows the three `Cross-Origin-*` headers; open `<origin>/showcase/` in a Chromium-based browser; optionally the
   scripted cold boot under the browser lock (section 3.5).

Afterwards: a gallery-only change is a push (plus a new verdict record); a re-pin or rebake is `upload-artifacts.sh`
first, then the push (the pre-promotion check enforces that order).

## 1. Prerequisites

| What | Check (none of these contact Cloudflare) |
|---|---|
| A Cloudflare account. It already exists: it hosts QED64's bucket `qed64-artifacts`. | — |
| rclone with the remote `qed64-r2`, configured for QED64's `scripts/upload-artifacts.sh` and reused by lean4game | `rclone listremotes` prints `qed64-r2:`. This command only reads your local rclone config. |
| The remote's token scope: an R2 API token with **Object Read & Write on bucket `qed64-artifacts`** (QED64 `docs/DEPLOY.md`, "Security"). That covers every prefix in the bucket, including `qed64-showcase/`. | (Cloudflare dashboard → R2 → Manage API Tokens) **[account]** |
| Node ≥ 22 (wrangler 4.125.0's `engines`; rehearsed on v26.3.0), npm | `node --version` |
| wrangler 4.125.0, installed in `infra/` (apart from the root `package.json` the UX suite uses) | `npm ci --prefix infra` then `npx --prefix infra wrangler --version` → `4.125.0` |
| The showcase itself, green on the current pin | step 3.1 |

## 2. One-time setup

1. **Confirm that the remote exists**, without contacting R2:
   ```
   rclone listremotes            # must list: qed64-r2:
   ```
   Do not run `rclone ls qed64-r2:` just to check. Unlike `listremotes`, it authenticates against your account.
2. **Install wrangler** (pinned; this needs network access to the npm registry only):
   ```
   npm ci --prefix infra
   npx --prefix infra wrangler --version        # 4.125.0
   ```
3. **Log in to Cloudflare** **[account]**. This opens a browser:
   ```
   npx --prefix infra wrangler login
   npx --prefix infra wrangler whoami           # shows the account QED64 lives in
   ```
   If your account has several workers.dev subdomains, `whoami` and the dashboard (Workers → your subdomain) show which
   one is yours. The showcase will be at `https://qed64-showcase.<subdomain>.workers.dev`.
4. **Choose where the artifacts live.**
   * **Shared bucket (default, the lean4game way).** No change needed. You need no new bucket and no new token.
     QED64's site-owned objects stay at the bucket root, the toolchain release QED64, lean4game and the showcase serve
     under `lean4-wasm64/<release id>/`, lean4game's own under `lean4game/`, and the showcase's go under
     `qed64-showcase/`. The showcase's mutable files (`profiles/index.json`, `snapshots/index.json`) never collide with
     theirs: its Worker reads them from its own prefix, and the upload writes only there ("Shared-bucket guard" at the
     top of this file).
   * **Own bucket (alternative).** Create a bucket `qed64-showcase-artifacts` (R2 → Create bucket) **[account]**. Give the
     upload token access to it, by extending the existing token or by creating a new one and a new rclone remote
     (command below). Then edit **both lines together** in `infra/deploy.env`: `R2_BUCKET=qed64-showcase-artifacts` and
     `R2_PREFIX=` (empty), plus `R2_REMOTE` if you made a new remote. Change them in the file rather than with
     one-off environment variables. If you set only `R2_PREFIX=` and forget `R2_BUCKET`, the scripts refuse (shared-bucket
     guard above) instead of writing to QED64's root. Check the result with `node scripts/lib/deploy-env.mjs`. An own
     bucket also needs a copy of the release under `lean4-wasm64/<release id>/`: the Worker reads `/runtime/*` and
     `/profiles/*` from that key of the bucket it is bound to, and neither script uploads it: `upload-artifacts.sh` refuses such a
     bucket until it holds the record's `release.json`, and `deploy-app.sh`'s check on the preview URL refuses until every
     file is there. Never commit the keys:
     ```
     rclone config create showcase-r2 s3 provider=Cloudflare \
       access_key_id=$R2_ACCESS_KEY_ID secret_access_key=$R2_SECRET_ACCESS_KEY \
       endpoint=https://$CF_ACCOUNT_ID.r2.cloudflarestorage.com acl=private        # [account]
     ```
5. **Check the storage budget.** R2's free tier is 10 GB of storage with zero egress fees.

   | In `qed64-artifacts` | Size |
   |---|---|
   | QED64 (QED64 `docs/DEPLOY.md`) | 2.1 GB |
   | lean4game (`wasm/DEPLOY.md`: runtime 154 MB + profiles 121 MB + ten game snapshots 2,142 MB) | 2.42 GB |
   | **showcase, one release-routed runtime** (default: stock pair + widgets8 + the indexes) | **0.745 GB** (9 objects at pin O from P2 on; O's own upload with widgets7 was 12 objects, 1.107 GB, and stays while O is a rollback target) |
   | showcase, H's objects, kept while H is a rollback target (section 6) | 2.42 GB (93 objects, the record `20261005T152953Z`) |
   | showcase, small variant (below), instead of the default | 0.394 GB (5 objects at pin O) |
   | **Total with H's objects and O's default upload** | **≈ 8.0 GB of 10 GB** |

   Not counted: the release O reads (1.260 GB), which the kernel publishes whether or not we read it. These numbers come
   from each project's docs; the record of the first deploy measured 13.70 GiB in the bucket before its upload, so
   storage is billed anyway. **Measure the real usage before the first upload** **[account]**.
   QED64 has promoted at least once since this showcase was first pinned, and both QED64 and lean4game upload
   copy-only, so their old objects accumulate in the bucket too:
   ```
   # either: dashboard → R2 → qed64-artifacts → Metrics (storage)
   rclone size qed64-r2:qed64-artifacts                  # [account] lists every object (metadata only); prints total size
   rclone size qed64-r2:qed64-artifacts/lean4game/       # [account] one app's share
   ```
   If the measured total plus 0.745 GB is close to 10 GB, use the small variant below (0.394 GB). The showcase's own old
   objects stay while H is a rollback target (section 6). R2 bills storage above the free tier; it does not stop uploads.

   From release routing on, the showcase reads the runtime and the packs from the toolchain release and stores no copy
   of them. The stock snapshots are still byte-identical to QED64's when QED64 serves the same build, and are stored a
   second time anyway, because the showcase keeps its own mutable names. Uploads are copy-only, so every **re-pin or
   rebake adds** its new digest-named objects and the old ones stay. A re-pin to a new runtime adds up to about 0.75 GB;
   one overlay rebake adds about 0.4 GB. From pin I on every runtime's overlay lives in its own directory
   (`snapshots/widgets8.<bid16>/`; until P2 also `widgets7.<bid16>/`), about 394 MB per runtime that no upload deletes. Collect the old objects
   deliberately once no deployed shell and no rollback target needs them (see [Re-pin](#6-re-pin)).

   **Small variant.** Set `MANIFEST_ARGS="--no-stock-snapshots"` for the upload (and the same for `deploy-app.sh`).
   The gallery uses only `widgets8`, so it is unaffected. What you give up: the bare stock page at `/?…` without
   `snapshots=` cannot boot (no stock snapshots). Keep `ROOT_REDIRECT`. (Until P2 the small variant also dropped
   `widgets7`, and with it the gallery's fallback; since P2 there is no second overlay and no fallback.)

## 3. Per release

### 3.1 Preconditions (no account)

Everything must be green on **the current pin** (`QED64.lock.json`) and **one gallery revision**, with no edit to
`gallery/`, the overlays or the lock in between:

```
scripts/showcase.sh verify      # pin, QED64 sources (submodule), release files, overlays, pin-site inventory
scripts/showcase.sh gallery     # "gallery gate GREEN on gallery content sha256 <h>"
scripts/showcase.sh ux          # full UX suite, about 20 min under the browser lock; must end "…: VERDICT"
```

Both scripts below refuse to proceed unless the manifest's G2 line says
`G2 UX: verdict run … was on THIS gallery …, lock … and overlays …`. `ALLOW_NO_UX_VERDICT=1` overrides that, and only
that; use it for a rehearsal, not for a real release.

### 3.2 Upload the artifacts first

```
DRY_RUN=1 scripts/upload-artifacts.sh     # [account] read-only: rclone --dry-run LISTS the bucket, writes nothing
scripts/upload-artifacts.sh               # [account] the real upload
```

What the script does (each step was exercised in the rehearsals before release routing, and on this code by
`rehearse.sh all browser stop` on `dbfd000`, rc 0, with `UPLOAD OK` to both fakes ([Rehearsal](#rehearsal));
`dbfd000..eca8f22` changes no deploy script):
1. It reads the target from `infra/deploy.env` (refusing a shared-bucket prefix other than `qed64-showcase/`, see the
   guard at the top) and checks `rclone listremotes`.
2. It regenerates the manifest with `--prefix qed64-showcase/`, which hashes every file and runs every gate (A1–A5,
   L1, L2, R1–R6, G1; L2: the pin's toolchain record names this runtime, and every file the release serves is in it with
   this size and sha256; R5: each overlay is uploaded under the pin's served directory and nothing under the bare one
   for a per-runtime pin; R6: a pin with `hardening.pinnedIndexes` uploads QED64's per-build index copies), then runs
   `--check`. It refuses on any FAIL. It prints the G2 line and refuses unless it names a verdict run. `manifest.r2` is
   what this script uploads (12 objects, 1.107 GB at O's upload; 9 objects, 0.745 GB from P2 on). `manifest.release.objects` is what the release serves (81
   objects, 1.260 GB): never uploaded, but `--published` and `--smoke` go through those URLs too.
3. It writes the upload plan to `out/deploy/upload/plan.tsv`: one exact file list per phase, group and content type.
   It then runs one `rclone copy --files-from-raw` per list, **never sync**, with `--checksum` (already-uploaded
   digest-named files are skipped) and multipart in 64 MiB chunks. The three `.snapz` files over 300 MiB need
   multipart: wrangler's `r2 object put` cannot upload them. The phases run in this order:
   1. every digest-named object (the `.snapz` files, 4 at pin O from P2 on, 6 with widgets7), as `application/octet-stream`;
   2. every index no older shell reads, as `application/json` (3 at pin O from P2 on, 4 with widgets7): a per-runtime
      overlay's `snapshots/widgets8.<bid16>/index.json` and QED64's per-build copies `snapshots/index.<buildId>.json`,
      `snapshots/profiles-index.<buildId>.json`;
   3. the shared mutable `index.json` files `profiles/index.json` and `snapshots/index.json`, as `application/json`.

   A browser that revalidates an index halfway through the upload therefore never learns a name whose object is not
   there yet. The runtime chunks, the pack parts and their manifests are in none of these lists. (A release record of a
   pin before release routing, such as `20261005T152953Z`, still has them, and `scripts/rollback-artifacts.sh` reads them
   there.)

   **`PHASES=`** (default all three, in that order) uploads a subset, e.g. `PHASES=1-objects,2-manifests`. A phase goes
   up only after every earlier one, selected in the same run or uploaded with the same R2 keys by this remote's newest
   release records (`PHASE ORDER OK …`; `ALLOW_UNRECORDED_UPLOAD=1` skips that check deliberately). Each record names
   its phases (`target.env` `phases=`). This makes a **split upload** possible: phases 1–2 before the Worker deploy,
   `PHASES=3-indexes` after it, so the shared indexes an older live shell reads change only once the new shell is live
   (decision E1 of pin I, docs/REPIN-LOG.md pin I entry; QED64 hit this window on 2026-10-08, its HARDENING #64).

   **What is left of decision E1.** Release routing removed its pack-manifest half for the upload window. The pack and
   runtime manifests are the release's now, under per-release keys that change with the Worker's record, so no upload of
   ours replaces one under a live shell, and `upload-artifacts.sh` has no `E1 HAZARD` line any more. (Before release
   routing O's phase 2 would have replaced both pack manifests under the live H: docs/REPIN-LOG.md pin O has that
   measurement. An H tab left open past the promotion is the case left: section 6.) The other half remains: phase 3 replaces `/profiles/index.json` and `/snapshots/index.json`, which the live shell reads. There
   are two orders:
   * **Order A: upload everything, then push promptly** (QED64's "land, upload, then push", its `d5b46ff`, on its origin/main since
     `fd95a2a`). From phase 3 until the promotion, bare stock visits of H fail on the replaced
     indexes, while H's gallery should still boot from its overlay. The stock failure was measured on 2026-10-28, before
     release routing (docs/REPIN-LOG.md pin O). The gallery boot under release routing, where H reads O's
     `/profiles/index.json` with its own pack manifests (H does not compare `release`), was booted by the `old-shell`
     rehearsal on 2026-11-04: "A: the OLD gallery in the window: OK", and the bare stock boot failed again as measured. If a CI run stops before the promotion, the window stays open
     until the run is fixed or H's indexes are put back (docs/NEXT-STEPS.md, top section). **CI deploys are order A:** the CI job does not set `ALLOW_PARTIAL_UPLOAD`, so its pre-promotion check
     (3.3, section 9) compares the phase-3 indexes too and refuses until they are up.
   * **Order B: by hand.** `PHASES=1-objects,2-manifests scripts/upload-artifacts.sh`, then `ALLOW_PARTIAL_UPLOAD=1
     scripts/deploy-app.sh` (its checks on the preview URL then pass `--before-phase-3`, which leaves out those two
     indexes), then `PHASES=3-indexes scripts/upload-artifacts.sh`, and only then the smoke of 3.4 (before phase 3 it
     fails on every old index that differs from the new one: on its size, as O's `profiles/index.json`, 514 against
     513 B, or on its sha256, as O's `snapshots/index.json`, 701 B in both). The new shell is safe in that window because
     it reads its per-build copies. A later push to main runs the CI deploy again, with phase 3 up by then.

   `ci/rehearse-deploy.sh old-shell` measures both orders (section 9).
4. It sets the Content-Type explicitly with `--header-upload`. rclone's s3 backend would guess the same types from
   the file extension, but the guess depends on the host's MIME tables. The gallery refuses a snapshot typed as HTML.
   (The runtime manifest's type is the release's now, and this script does not put it: section 10.)
5. It runs `rclone check --one-way` on every list (size + hash; nothing is downloaded).
6. It writes a **release record** `out/deploy/published/<UTC time>/`, containing the manifest, the plan and a copy of
   every index it published (and, in a record from before release routing, every manifest), for [rollback](#5-rollback) and for `deploy-app.sh`'s record check. Back
   it up right away (section 5, "Keep the records").

The first upload of a pin is 9 objects, 0.745 GB at pin O from P2 on (O's own upload, with widgets7: 12 objects, 1.107 GB). Later runs transfer only files whose bytes changed
(`--checksum`). In the rehearsal, a second run of the same release transferred 0 B (every list ended with `0 B / 0 B`).

### 3.3 Deploy the shell

```
DRY_RUN=1 scripts/deploy-app.sh           # no account: everything up to `wrangler versions upload --dry-run` (after a real upload)
scripts/deploy-app.sh                     # [account] wrangler versions upload, the checks on its preview URL, wrangler versions deploy
```

Before your **first** real upload there is no release record yet, so the dry run stops at check 4 below with
`RECORD MISSING`. To dry-run the shell before ever uploading, say so explicitly:

```
ALLOW_UNRECORDED_UPLOAD=1 DRY_RUN=1 scripts/deploy-app.sh
```

The script:
1. regenerates and checks the manifest (same gates, same G2 rule);
2. runs `--stage-assets` into `out/deploy/assets` (S1/S2: exactly the manifest's files, checked against their sha256);
3. refuses any file over **25 MiB**, any `runtime/`, `profiles/` or `snapshots/` directory in the tree, and a
   missing required file (`index.html`, `workers/{lean.worker,lsp-front-door,lsp-frames,snapshot-prefetch.worker}.js`,
   `showcase/{index.html,gallery.js,lib.js,examples.json,pin.json}` (`qed64-bridge.js` until P1), and `workers/memory64-probe.js`
   (every registered pin's `lean.worker.js` loads it; until P1 only from QED64 385a1ac on)), and checks that the staged bundle and
   `showcase/pin.json` name the same runtime buildId;
4. **checks the release record.** The newest record in `out/deploy/published/` for the remote `R2_REMOTE` (written by
   `upload-artifacts.sh`, or by `rollback-artifacts.sh`) must have the same bucket and prefix, and exactly this
   manifest's R2 keys (`manifest.r2`, ours) with the same sha256. That includes the indexes. Otherwise the script
   stops with `RECORD MISSING … run scripts/upload-artifacts.sh first` or `RECORD MISMATCH …`. This catches the
   upload and the deploy running with different overrides or `MANIFEST_ARGS`, and a re-pinned shell deployed before
   its upload. The newest consecutive records with these keys must together have uploaded all three phases
   (`RECORD PARTIAL …` otherwise); `ALLOW_PARTIAL_UPLOAD=1` accepts phases 1–2 only, for the split upload in 3.2.
   `ALLOW_UNRECORDED_UPLOAD=1` skips the check deliberately, for example when the upload ran on another machine;
5. **writes `wrangler.toml` from `wrangler.toml.example`** when the file is absent, with the name, bucket, prefix and
   assets directory from `infra/deploy.env`. If the file exists, the script **refuses it unless it agrees**, including
   `run_worker_first = true`;
6. runs `npx --prefix infra wrangler versions upload --message "pin <id> (<buildId>) gallery <sha16> prefix qed64-showcase/"`
   (log `out/deploy/wrangler-upload.log`). The message is what `wrangler deployments list` shows when you pick a rollback
   target. The new version takes no traffic yet. If wrangler's output has no `Version Preview URL:` line (Preview URLs
   are off for the Worker: first deploy checklist, step 6), the script refuses with that reason, nothing is promoted and
   the live version keeps all the traffic;
7. **the pre-promotion check** on that preview URL: `deploy-manifest.mjs --published`, then `--smoke --all --range`, up
   to 3 attempts 20 s apart, since a new version can take a few seconds to reach every edge location. Both go through
   every object the shell needs, ours and the release's. With `ALLOW_PARTIAL_UPLOAD=1`, both checks also get
   `--before-phase-3` (3.2) when step 4's record check found phase 3 missing, and always with `DEPLOY_FROM_LOCK=1`. They do
   not get it when the records cover all three phases, or when the record check failed and `ALLOW_UNRECORDED_UPLOAD=1`
   let the deploy go on: then the phase-3 indexes are compared, and a split upload is refused.
   It must end `PRE-PROMOTION OK: version <id> on <url>`; if not, nothing is promoted. The check has to run on the new
   version: H's live Worker maps `/runtime/` and `/profiles/` to our prefix, this one to the release's, so H's cannot
   answer for it;
8. runs `wrangler versions deploy <id>@100% --yes`, which sends all traffic to that version. It then derives the
   Worker's own URL from the preview URL (`https://<8 hex>-qed64-showcase.<subdomain>.workers.dev` gives
   `https://qed64-showcase.<subdomain>.workers.dev`), prints it as `DEPLOYED-URL`, and prints the smoke command to run
   next.

Run the steps in this order: **artifacts first, shell second.** A shell-only change (gallery code) needs step 3.3
alone. A re-pin or an overlay rebake needs both, in order.

### 3.4 Smoke test the live Worker **[account: needs the deployed URL]**

```
node scripts/deploy-manifest.mjs --smoke https://qed64-showcase.<subdomain>.workers.dev --all --range
curl -sI https://qed64-showcase.<subdomain>.workers.dev/showcase/ | grep -i cross-origin
curl -s -o /dev/null -D - -H 'Range: bytes=1000000-1000099' https://qed64-showcase.<subdomain>.workers.dev/snapshots/<dir>/<widgets.….snapz>
```
(`<dir>`: `node scripts/lib/pins.mjs overlay-dir widgets8`, i.e. `widgets8` on pins A–H, then `widgets8.<runtime bid16>`:
`widgets8.f69cca24d0878a58` on pin I, `widgets8.36d7f415704473d9` on pin O.)

`--smoke --all` sends a HEAD request to every asset and every R2 key the shell needs, the release's included (170 URLs
at O's upload: 77 assets, 12 keys of ours and 81 of the release's; from P1/P2 on 166: 76 assets, 9 keys of ours and
81 of the release's). For each one it checks:
* status 200 and `content-length == size`;
* COOP `same-origin`, COEP `require-corp`, CORP `same-origin`;
* QED64's cache rule (digest-named files immutable, every index and manifest `must-revalidate`);
* a JSON type on every `*.json` and a non-HTML type on binaries;
* no `Content-Encoding` on artifacts;
* for every manifest and index (the R2 keys QED64's cache rule does not make immutable: 10 at O's upload, 6 of ours and 4 of
  the release's; 9 from P2 on, 5 of ours, about 12 MB, nearly all of it the two pack manifests), also a GET with `accept-encoding: identity`
  whose body must have the manifest's sha256, through the same helper as `--published` (section 9). These keep their URL from release to release, so a
  HEAD cannot tell an older one of the same length from this release's (`snapshots/index.json` is 701 B at H and at O:
  the HEAD-only smoke of `9eed0e9` passed the stale one in O's rehearsal, order B; since `dbacd2c` it fails it). A
  mismatch prints `FAIL GET <url> — published <n> B sha256 <16 hex>… != manifest <n> B <16 hex>…`. Immutable keys stay HEAD only: their URL names their content, and pack parts
  and snapshots reach hundreds of MB.

`--range` also sends single-range GETs to the largest `.snapz`. It expects 206 with `Content-Range bytes 0-99/<size>`,
416 past the end, and a full 200 for a mismatched `If-Range`. Every check must print `OK`, and the run must end with
`SMOKE OK`. The `curl` lines must show the three `Cross-Origin-*` headers, and the Range request must get
`HTTP/1.1 206`, `Content-Range: bytes 1000000-1000099/<size>` and `Content-Length: 100`. `--before-phase-3` leaves out
`/profiles/index.json` and `/snapshots/index.json`; only the check before a split upload's promotion uses it, and the
smoke after phase 3 runs without it.

### 3.5 Open it

Open `https://qed64-showcase.<subdomain>.workers.dev/showcase/` (a bare `/` redirects there). The gallery runs its
own pairing preflight, which checks that the overlay's index is JSON, its runtime equals the shell's buildId, and
every `.snapz` HEAD has `content-length == transfer`. Then it boots QED64 in the iframe.

A **first visit** downloads about 680 MB of artifacts: the runtime (159 MB), the core pack (121 MB), the
widgets8 snapshot (365 MB) and its `init` (33 MB). The rehearsal's cold boot measured 676.3 MB in 26 GETs; with the app
shell, the last-mile lane measured 709.8 MB through a shaped link (123 s at 50 Mbit/s; at 10 Mbit/s it is ready at
565 s, see the status block at the top). Later visits come from OPFS and the HTTP cache. If a
`.snapz` download is cut off, the browser resumes it with `Range` + `If-Range`, which the Worker supports.

You can also run the scripted cold boot against the live URL (Chrome, under the host's browser lock):
```
scripts/with-browser-lock.sh deploy-check node scripts/deploy-rehearsal/boot-check.mjs https://qed64-showcase.<subdomain>.workers.dev out/deploy-live
```

## 4. Smaller, faster iterations

* **Gallery-only change:** `scripts/deploy-app.sh` alone. It still regenerates the manifest. The R2 keys are
  unchanged, so nothing needs uploading.
* **See the exact commands without running them:** `node scripts/deploy-manifest.mjs --commands`. It prints
  `rclone copy` lines with `--header-upload` for this manifest and runs nothing. It is a review listing, not the
  upload path: after the digest-named lists it prints one `.mutable` line per group, so `profiles/index.json` (phase 3)
  comes before the per-build copies and overlay indexes of phase 2. Upload with `scripts/upload-artifacts.sh`, which
  keeps the three phases.

## 5. Rollback

R2 is copy-only, so every digest-named object of an earlier release is still in the bucket. Rolling back means putting
the earlier **names** back and redeploying the earlier **shell**.

1. **Artifacts.** Every real upload leaves a release record:
   ```
   ls out/deploy/published/                                          # one directory per upload, UTC time
   grep remote= out/deploy/published/*/target.env                    # which remote each record was made through
   DRY_RUN=1 scripts/rollback-artifacts.sh out/deploy/published/<time>   # [account]
   scripts/rollback-artifacts.sh out/deploy/published/<time>             # [account]
   ```
   The script refuses in three cases:
   * the record's bucket and prefix differ from the current target;
   * the record was made through another rclone remote than `R2_REMOTE`. Override this with
     `ALLOW_REMOTE_MISMATCH=1`, deliberately;
   * any digest-named object of that release is missing from the bucket or has the wrong size (`rclone lsjson`,
     metadata only; every immutable entry of the record's `manifest.r2`, not only the lists it uploaded, and from release
     routing on every object of `manifest.release`, the kernel's: `wrangler rollback` does not check them either, section
     6, retention). Re-publishing an index whose objects are gone would strand visitors.

   Otherwise it re-copies the record's phase 2 files (manifests, in a record from before release routing), then its
   phase 3 indexes, with their content types. It then writes a new
   record `<time>-rollback`, so that `deploy-app.sh` compares against what is live now. A record of a **split upload**
   (`phases=` naming fewer than all three phases, 3.2) holds only those phases' files; either record of such a release
   may be named, and the script joins its companion records (the consecutive records of this remote, bucket and prefix
   with the same R2 keys, sha256 and sizes, no rollback in between), re-publishing phase 2 and phase 3 from the newest
   record that uploaded each. If the companions do not cover all three phases it refuses unless
   `ALLOW_PARTIAL_ROLLBACK=1`.

   **Keep the records.** They are the only copy of what each release published. Unlike lean4game, whose rollback reads
   old indexes from git history, the published indexes here are build outputs in the gitignored `out/` (only QED64's
   own five manifests are in git, in the submodule). After every real upload or rollback, copy them somewhere durable,
   for example:
   ```
   rsync -a out/deploy/published/ ~/Backups/qed64-showcase-releases/    # or commit them to a private repo
   ```
   A record is the manifest, the upload plan and the indexes it published: under 1 MB from release routing on
   (`20261005T152953Z`, with its two pack manifests, is about 12 MB).
2. **Shell** **[account]**:
   ```
   npx --prefix infra wrangler deployments list     # versions that took traffic; each message names its pin + gallery
   npx --prefix infra wrangler rollback <version-id>
   ```
   A Worker version carries its static assets, so this should restore the earlier dist and gallery exactly.
   Confirm with the smoke in 3.4 against the manifest of that release:
   `node scripts/deploy-manifest.mjs --out <dir holding that manifest.json> --smoke <origin> --all`. The release record
   holds one, except for O to H: `20261005T152953Z` is E's upload and 11 of H's 59 `dist/` files differ from it, so the
   smoke with that manifest fails on the assets even after a good rollback. For H use the `manifest.json` in the
   `qed64-deploy-record` artifact of the run on `d60b15e`, if GitHub still keeps it; otherwise the `curl` lines of 3.4 and
   a look at `/showcase/`.
3. **Roll forward** the same way as a normal release: run steps 3.2 and 3.3 from the fixed state. Only what changed is
   transferred.

The order is the reverse of a release: put the old names back first, then the old shell. Each Worker version bundles
its own toolchain record, so between deployed release-routed pins (O and its successor) `wrangler rollback` restores
the routing with the shell. N was never deployed, so going from O to N is a normal deploy of N.

**Rollback to O.** O `521cf3f` is live (Worker version `476d6c11-a119-4b17-8545-65e0b9f34987`, deployed 2026-11-05 from
`b24587d`, upload record `out/deploy/published/20261105T200927Z`, backed up in `$W/published-backup/`). Once a later
version is deployed (the P1+P2 deploy first), that version id is a rollback target:
```
npx --prefix infra wrangler deployments list                                       # [account] confirm the id
npx --prefix infra wrangler rollback 476d6c11-a119-4b17-8545-65e0b9f34987          # [account]
```
A deploy that uploaded nothing (P1+P2 reuses O's objects, so a CI deploy of it uploads nothing) left R2's mutable names
as O's record published them, so the Worker rollback alone restores O. If an upload ran after O's, first put O's names
back with `scripts/rollback-artifacts.sh out/deploy/published/20261105T200927Z` **[account]**; it refuses while any
immutable object of that record is gone, which is why O's objects, its `widgets7.36d7f415704473d9/` ones included, stay
(section 6). The rollback reads the record and the deploy env, not a pin descriptor.

**Rollback from O to H.** H `bf9d947` (runtime `wasm64-3ab1c6a9da03bc29`) has no release routing: QED64 `391a075`, which
gave `createWorker` its `release` option, is in every pin from I on and not in H, and `deploy-manifest` refuses to
generate a manifest for a pin before `385a1ac`. So H comes back only as its own record and its own Worker version. It
needs no descriptor: H's `pins/bf9d947/` was retired in P1 (it is at the tag `pins-history-2026-11-07`), and
`rollback-artifacts.sh` reads only the record and the deploy env (`scripts/lib/deploy-env.mjs`, `deploy-common.sh`).
Working on H's own harness means a worktree at `d60b15e`, since HEAD refuses its v2 descriptor:
```
scripts/rollback-artifacts.sh out/deploy/published/20261005T152953Z    # [account] puts H's indexes back under qed64-showcase/
npx --prefix infra wrangler rollback 29176b6f-cc41-4a16-bed4-c8753c7bd5f2   # [account]
```
That is H's full version id (the log of the deploy run on `d60b15e`); `wrangler deployments list` shows it too. Use that
list, not `wrangler versions list`, for any later rollback: the latter holds only the 10 newest versions, and every
`wrangler versions upload` adds one, refused ones included. Ignore the script's closing hint here: it names the record's
pin E, whose version is `ae781eae`, and H's is `29176b6f`. Confirm the result as in step 2 above, not with this record's
manifest.

That record is E's upload, and H's 93 R2 objects were E's (H uploaded nothing). O's shell survives the window between
the two commands: its served indexes then name H's runtime, so it reads its per-build copies
`snapshots/index.<O bid>.json` and `snapshots/profiles-index.<O bid>.json` (QED64's `pairedCopyOr`, `lib/snapshots.ts`),
which the rollback leaves alone, and its runtime and pack manifests are in the release's prefix, which the rollback
does not touch either. H's Worker then reads `/runtime/*` and `/profiles/*` from `qed64-showcase/` again, so those
objects must still be there (section 6). An O tab left open after `wrangler rollback` asks H's Worker for O's files: O's
runtime and pack parts are not under our prefix (a 404), and the pack manifests there are H's, which O's release check
(HARDENING #81) refuses as `stale`, so the tab fails closed until it reloads. All of this is read from the code. The
rehearsal's `rollback` step runs the script against a fake bucket; O to H was not run.

## 6. Re-pin

A re-pin (README "Re-pin: adding a pin when QED64 sends a new commit") usually changes the runtime buildId. That has
these consequences:
* **Deploy only the active pin** (printed by `scripts/showcase.sh pin current`; the live site serves pin O `521cf3f`, Lean 4.35.0 on runtime `wasm64-36d7f415704473d9`, with release routing: deployed
2026-11-05 20:18Z by the qed64-deploy run on the push of `b24587d` to main, Worker version `476d6c11-a119-4b17-8545-65e0b9f34987`,
upload record `20261105T200927Z`. Before it, pin H `bf9d947` (deployed 2026-10-08 19:20Z from `d60b15e`, Worker version
`29176b6f`; its 93 R2 objects were E's): the rollback target, section 5. Pins I–N were never deployed). `pin use <id>` regenerates
  `out/deploy` for the new active pin, and `deploy-manifest --check` G2 then needs a verdict run on that pin's gallery.
  `deploy-manifest` refuses a pin before `385a1ac`: those pins have no release routing and are not deployed from this
  Worker (section 5).
* **Snapshots are binary-paired to the runtime.** The overlays must be rebaked against the new runtime before
  anything is uploaded. The R3 gate refuses an index entry whose `runtime` is not the lock's buildId, and the gallery
  refuses a mismatch with `SNAPSHOT_UNPAIRED`.
* **Upload before you deploy.** The new snapshots have new digest names, so phase 1 uploads them next to the old ones.
  Phase 2 adds the new runtime's overlay indexes and per-build index copies, and phase 3 switches `snapshots/index.json`
  and `profiles/index.json`. The new runtime and packs are not uploaded: `deploy-app.sh`'s check on the preview URL
  refuses unless they are in `lean4-wasm64/<release id>/` of the bucket, where the kernel's publish puts them. Only
  after all that does `deploy-app.sh` put the new shell live.
* **From pin I on, the overlays never switch under a live shell, and from release routing on no upload changes the
  runtime and pack manifests under one.** A per-runtime pin (`pin.json` v3) uploads its overlay to a new directory,
  `snapshots/widgets8.<bid16>/` (until P2 also `widgets7.<bid16>/`), index included, in phases 1–2; the old shell's bare `snapshots/widgets{7,8}/`
  objects are not touched (gate R5). What still changes under the old shell is phase 3, the stock and profile indexes:
  from then until the new Worker is live, bare `/?…` visits of the old stock page can fail (the gallery boots from its
  overlay). That is what is left of decision E1. Its two orders are in 3.2, and CI deploys are order A. After the
  deploy, a bookmark of `/?snapshots=snapshots/widgets8` gets the new shell with the old overlay and stops with QED64's
  named unpaired error; the gallery's `?overlay=widgets8` keeps working (it maps to the pin's directory). A gallery tab
  opened before the deploy that reboots its frame afterwards fails the same way until the page is reloaded.
* **Tabs left open.** After O's deploy, an H tab left open loses its chunks. The new Worker reads `/runtime/*` and
  `/profiles/*` from the release's prefix, so the tab's `/runtime/runtime-manifest.<H bid>.json`, and any H chunk or pack
  part it has to fetch again, is a `no-store` 404 (`createWorker`; `infra/worker.test.mjs`, "release-mapped paths"). A
  reload gets O's shell. `ci/rehearse-deploy.sh old-shell` records what that manifest fetch gets on an `E1 MEASURE` line,
  and on another the release `/profiles/lean-core.manifest.json` names; nothing else of this bullet is measured. Three names are the same in both releases and answer 200 with O's bytes:
  `/runtime/runtime-manifest.json` and the two `/profiles/*.manifest.json`. So not every path fails closed, and the two
  limits below are read from H's code and not measured. First, H's `resolveRuntimeManifest`
  (`bf9d947:frontend/src/qed64-boot.ts`) treats the 404 as a miss and tries `/runtime/runtime-manifest.json`. That code
  runs once per page load, so it takes an H document that was loaded just before the promotion: with H's bare overlay its
  worker then stops on `SNAPSHOT_UNPAIRED`, while a stock page reads O's indexes, which pair with that runtime, and
  nothing refuses it. Second, H has no release check on a pack install (QED64's HARDENING #81 is first in `521cf3f`), so an
  H tab whose chunks are still cached and which takes "Load exact imports", or reinstalls a pack on a restart in memory
  mode, fetches O's 4.35 pack and mounts it under its 4.34 runtime. What that runtime does with those oleans was not
  measured; #81 says they are misread. That piece of E1's pack-manifest half lasts until the tab reloads. A shell with
  QED64's release check (O on) still falls back to the new runtime manifest at a later deploy, but its pack install then
  refuses the new release's manifest as `stale`, so it fails closed.
* **Old objects stay.** Rollback needs them. Delete them only deliberately, after the new release has been live for a
  while and no rollback target needs them. Delete only keys of the old record's `manifest.r2` that are in no deployed or
  rollback-target record's `manifest.r2`. That never includes `qed64-showcase/profiles/index.json`,
  `qed64-showcase/snapshots/index.json` or any key of the live record: every record has the two indexes, and the live
  shell reads them, so deleting them stops every boot. Never take keys from `manifest.release.objects`: those are the
  kernel's release, and removing it is the owner's K4 decision. Each key already starts with `qed64-showcase/`, so the
  command is `rclone deletefile qed64-r2:qed64-artifacts/<key>` **[account]**. Never use `sync` or a prefix-wide
  delete in the shared bucket: QED64's and lean4game's objects are in it too.
* **While H is a rollback target** (section 5) keep every key of the record's `manifest.r2` under `qed64-showcase/` (93
  objects: `runtime/`, `profiles/`, the stock pair `snapshots/init.b6d945e398b4d55e.snapz` and
  `snapshots/mathlib.265cd10cbadd1313.snapz`, the bare `snapshots/widgets7/` objects and the bare `snapshots/widgets8/`
  ones, which H's gallery boots from), the record `out/deploy/published/20261005T152953Z` itself,
  `scripts/rollback-artifacts.sh` and `tests/ux/bringup/{lockfifo,lockrace}.sh`, its backup `$W/published-backup/`, and
  on this machine `$W/deploy-rehearsal` (H's old-shell rehearsal state, which `ci/rehearse-deploy.sh old-shell` reads).
  The rollback script refuses if any immutable object of the record is gone. None of this needs H's descriptor, which P1
  moved to the tag `pins-history-2026-11-07`.
* **While O is a rollback target** (section 5, "Rollback to O"; from the first deploy after O) keep every key of O's
  record `out/deploy/published/20261105T200927Z` `manifest.r2` under `qed64-showcase/` (12 objects), **including O's
  `snapshots/widgets7.36d7f415704473d9/` objects** (its index and two `.snapz`, 0.36 GB): P2 retired the widgets7 overlay,
  so no pin, lock or gallery reads them any more, but `rollback-artifacts.sh` on O's record refuses when any immutable
  object of it is gone. Keep the record and its backup, O's Worker version `476d6c11-a119-4b17-8545-65e0b9f34987`
  (`wrangler deployments list`), and O's rehearsal state. Deleting O's widgets7 objects is the owner's call, and only
  after O stops being a rollback target.
* **When to re-pin (decision D5, 2026-11-01; QED64 `d5b46ff`, on its origin/main since `fd95a2a`).** Re-pin QED64 only at a Lean/Mathlib import or a kernel
  release cut that QED64 adopts (one for a visitor-visible or wrong-verdict fix), for a QED64 fix that is visitor-visible
  or a wrong verdict for us, or at a monthly refresh. Keep the cheap headless checks of candidate pins that are not
  deployed. "Deploy within about a day, or don't gate it" applies only to the full 6–17 h gate. Ask the owner for one
  "push + upload + deploy pin X" approval per pin. Pin only QED64 commits that are pushed.
* **Retention (K4).** The showcase reads the release `lean-v4.35.0-b081e7c` (pin O) and `lean-v4.34.0-53cb11e` (pin N,
  for as long as it is kept), and since P1 no longer reads `lean-v4.34.0-e1a79c1` (the retired pins I–K). Keep those
  pins' records tracked on the deployed branch (`pins/521cf3f/`, `pins/58ebbad/`; on `origin/main` since O's push of
  `b24587d`): the kernel's retention rule reads them before any R2 or GitHub deletion, and a deletion is the owner's
  operation. O's Worker version `476d6c11-a119-4b17-8545-65e0b9f34987` is a rollback target once a later version is
  deployed (section 5), and H's `29176b6f-cc41-4a16-bed4-c8753c7bd5f2` stays one.
  `scripts/fetch-artifacts.mjs --qed64-origin` is also a reader.
* Run all of section 3 again: preconditions on the new pin (a new UX verdict), upload, deploy, smoke.

## 7. Custom domain **[account]**

The zone must be on Cloudflare. Either:
* in the dashboard: Workers & Pages → `qed64-showcase` → Settings → Domains & Routes → Add → Custom domain (the
  dashboard's wording may have changed), or
* in `wrangler.toml` (gitignored; `scripts/lib/wrangler-config.mjs check` does not touch extra keys), add
  ```
  routes = [{ pattern = "showcase.example.org", custom_domain = true }]
  ```
  and run `npx --prefix infra wrangler triggers deploy --config wrangler.toml`. `scripts/deploy-app.sh` does not apply
  routes any more: wrangler's own output for `versions upload` says that changes to routes and custom domains must be
  applied with `wrangler triggers deploy`.

The Worker sets the isolation headers itself, so they also apply on the custom domain. Do not add a Transform Rule or
another Worker on that hostname that strips or overrides `Cross-Origin-*` headers. After the change, repeat 3.4 with the
new origin. `workers_dev = true` keeps the `*.workers.dev` URL working as well. To retire it, set it to `false` and run
`npx --prefix infra wrangler triggers deploy --config wrangler.toml`: wrangler applies that key only in `wrangler deploy`
and `wrangler triggers deploy`, and `deploy-app.sh` runs neither. `DEPLOYED-URL` still names the workers.dev URL then, so
smoke the custom domain instead. Preview URLs are a separate setting, and `deploy-app.sh` needs them on.

## 8. Security

* **The shared token can write every app's objects in `qed64-artifacts`.** Two layers stop the showcase from touching
  the others: the shared-bucket guard (at the top of this guide) and the scripts writing only under
  `$R2_PREFIX`, from exact file lists, never deleting.
* **Two credentials, never one broad one** (QED64 `docs/DEPLOY.md`, "Security"):
  * the **R2 API token** (S3 keys) lives only in your local rclone config (`qed64-r2`). Its scope is Object Read &
    Write on `qed64-artifacts`, with an expiry;
  * **Workers deploys** use your `wrangler login`. For CI, use an API token with **Workers Scripts: Edit only, no R2
    permission**, so that a leaked CI secret cannot touch artifacts. The deploy workflow receives exactly two secrets,
    `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`, only in its deploy step; it runs on pushes to `main` and
    manual dispatch, never on pull requests, so a fork's code never sees them.
* Never commit keys or tokens. `wrangler.toml` holds no secrets and is gitignored anyway; `infra/deploy.env` holds only
  names.
* Do not enable the bucket's public `r2.dev` URL. Reads go through the Worker binding, and the Worker serves only
  `/runtime/` and `/profiles/` files from the pin's release prefix and `/profiles/index.json` and `/snapshots/` from its
  own prefix, so the showcase never exposes QED64's or lean4game's own keys. Path traversal and empty segments are
  refused (`createWorker`; QED64's `tests/unit/edge-worker.test.ts`; `infra/worker.test.mjs` runs the empty-segment case on
  our Worker).

## 9. CI: GitHub Actions

Two workflows at the repository root (`.github/workflows/`), both runnable locally (below):

* **`lean-ci.yml`** on every push and pull request: one job per widget package (elan, `lake exe cache get` where Mathlib
  is a dependency, `lake build`, `lake test`, the showcase probe), the static showcase (regenerated dumps == committed,
  assemble, React verification), and `qed64-static`: `check-portable`, the browser-lock tests, `qed64-src check`,
  QED64's page built from the submodule byte-identical to the lock, `fetch-artifacts --git-only`, the widget export,
  the Worker tests and the gallery gate. Every checkout uses `submodules: recursive`.
* **`qed64-deploy.yml`** on pushes to `main` that touch `qed64-showcase/`, `.gitmodules` or the workflow, and on manual
  dispatch. It deploys the **app shell only**, the lean4game way; the R2 artifacts are uploaded from your machine
  (section 3.2), never from CI.

**What the deploy job does**, in order (each step stops the job on failure):

1. **Gate.** Without the secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` it logs
   `CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID not set — skipping deploy` and every other step is skipped (green).
   A dispatch with `dry_run` runs everything up to `wrangler versions upload --dry-run` without them.
2. `qed64-src check`, then **QED64's page built from the submodule** (`scripts/build-shell.mjs`: every `dist/` file,
   58 on E, 59 on F–H, 60 on I, byte-identical to the lock, or nothing is installed), `fetch-artifacts --git-only` (QED64's five tracked manifests
   and indexes), the Worker tests.
3. **`DEPLOY_FROM_LOCK=1 scripts/deploy-app.sh`**, the same script as the manual path, with these differences:
   * the manifest is `deploy-manifest.mjs --from-lock`: the assets are hashed as usual, the R2 keys, sizes and sha256
     come from the committed lock. On this machine it was proved **identical to the full manifest** apart from
     `options.source = "lock"` (on pin E, before release routing: 93 R2 objects, 75 assets, and the same rclone lists;
     `$W/logs/r3/equiv-*.log`). R1, R2 and the stock R3 read QED64's tracked files (their sha256 must equal the lock's);
     the overlay indexes are not in git, so their R3 runs in `--published` on the preview URL;
   * **G2** comes from the committed `infra/ux-verdict.json` (written by `--record-verdict` on your machine) when the
     job has no `out/ux` record; it must name exactly this gallery, lock and overlay indexes. The dispatch input
     `allow_no_ux_verdict` sets `ALLOW_NO_UX_VERDICT=1`, deliberately;
   * the **release-record check** (a file of the machine that uploaded) does not apply; the **pre-promotion check** of
     3.3 asks the bucket itself. `wrangler versions upload --message "pin … gallery … prefix … ci <commit>"` with the
     pinned wrangler 4.125.0 (so `wrangler deployments list` tells versions apart for a rollback, section 5) puts the new
     version up with no traffic. Then `deploy-manifest.mjs --published` (every immutable object, the release's included:
     HEAD 200 with the manifest's size; every manifest and index: GET sha256 == the manifest's; R3 on the fetched overlay
     indexes) and `--smoke --all --range` run on its preview URL, up to 3 attempts 20 s apart, and only then
     `wrangler versions deploy <id>@100% --yes`. Without Preview URLs on for the Worker (first deploy checklist, step 6)
     the job refuses and promotes nothing. Because the check GETs the phase-3 indexes (`/snapshots/index.json`,
     `/profiles/index.json`) too, **every CI deploy is order A** (3.2): the check refuses until phase 3 is up, and a split
     upload deploys by hand, since this job does not set `ALLOW_PARTIAL_UPLOAD=1`.
4. **Smoke:** `deploy-manifest.mjs --smoke <origin> --all --range` against `SHOWCASE_ORIGIN`, which names only this
   step's origin, or the workers.dev URL `deploy-app.sh` derived from the preview URL (`DEPLOYED-URL …`). Up to 3 attempts
   20 s apart, for edge propagation.
5. The manifest, gate logs and wrangler output are kept as the run's artifact `qed64-deploy-record`.

**Secrets and variables** (first deploy checklist, steps 4, 5, 7): `CLOUDFLARE_API_TOKEN` (Account → Workers Scripts →
Edit only; release routing did not change that), `CLOUDFLARE_ACCOUNT_ID`, and the variable `SHOWCASE_ORIGIN`. Nothing
else. The Worker's Preview URLs are a dashboard setting, not a secret (step 6).

**What CI does not do.**
* **Upload artifacts.** Decided against, not just left out. A CI upload needs the 1.1 GB of bytes: QED64's stock
  snapshots could come from QED64's live origin only while it still serves that pairing (`fetch-artifacts` verifies each
  file against the lock), but our overlays exist only on
  the machine that baked them (or on this showcase's own origin, which is what the upload would fill). It would
  also need R2 S3 keys with write access to the **shared** bucket `qed64-artifacts` (QED64's and lean4game's objects
  too) as GitHub secrets, a much larger blast radius than a Workers-only token. Artifacts change only with a re-pin or
  rebake, which runs on your machine anyway.
* **Run the UX suite** (a 20-minute, memory-heavy Chrome run): G2 is the committed verdict instead.
* **Roll back.** Section 5 stays manual (`rollback-artifacts.sh`, `wrangler rollback`).

**GitHub Pages** (the static showcase, not the QED64 showcase). `lean-ci.yml`'s `pages` job publishes `showcase/site`
on a push to `main` only when both one-time settings exist **[account]**: Settings → Pages → Build and deployment →
Source = **GitHub Actions**, and the repository variable `DEPLOY_GITHUB_PAGES` = `true`. Without them the job is
skipped and nothing fails; the site is still built, verified and uploaded as the artifact `showcase-site` on every run.

**Running the workflows locally.** `ci/run-local.mjs` runs a workflow's jobs on this machine, each in a fresh clone of
a commit (`git clone` + `git submodule update --init --recursive`), executing every `run:` step as written with
GitHub's shell flags, working directories and environment. `uses:` steps are emulated (checkout, setup-node,
artifacts); the host is macOS with its own tool versions and warm caches, which the summary lists as deviations.
```
npm ci --prefix ci                                                        # the runner's YAML parser
node ci/run-local.mjs --workflow .github/workflows/lean-ci.yml --parallel 3
node ci/run-local.mjs --workflow .github/workflows/lean-ci.yml --job packages --matrix package=simp-lens
ci/rehearse-deploy.sh                                                     # the deploy job, 9 scenarios; old-shell needs OLD_REF (macOS)
OLD_REF=<live commit> ci/rehearse-deploy.sh old-shell                     # a runtime change against the live shell (below)
```
`ci/rehearse-deploy.sh` needs the fake R2 that `scripts/deploy-rehearsal/rehearse.sh upload-dry upload deploy-dry load`
leaves in `$QED64_SHOWCASE_WORK/deploy-rehearsal/state`: `upload` also stages the toolchain release at
`lean4-wasm64/<id>/` of the fake bucket, where the kernel's publish puts it in the real one. Its `wrangler` is
`scripts/deploy-rehearsal/wrangler-shim.sh`: `wrangler versions upload` becomes its `--dry-run` in the offline sandbox
with no token, the new version on its "preview URL" is `wrangler dev --local` on the generated `wrangler.toml` over a
copy of the fake R2, and `wrangler versions deploy` records the promotion. (A real upload leaves the old version serving
until the promotion; the stand-in has one server per port, so from `versions upload` on the new Worker answers there.)
[CI rehearsal](#ci-rehearsal) lists its nine scenarios. Since pin I the `tamper` scenario alters the overlay index at the
directory the manifest records (`options.overlayDirs`), and **`old-shell`** rehearses a runtime-changing deploy against
the live shell: the old Worker and shell (a fresh clone at `OLD_REF`, its old workflow run without `SHOWCASE_ORIGIN`)
must deploy over the live pin's objects alone (`OLD_STATE`) with their smoke OK; then the new pin's phases 1–2 and the
toolchain release are loaded on top under them (nothing deleted), and `OLD_MANIFEST`'s `--published` must pass without
any phase-2 key that replaces a live one, each of which must serve the new manifest's bytes (with release routing none should be a pack
manifest: the `E1 HAZARD` name stays for a rehearsal of a pin before it), every bare `snapshots/widgets{7,8}/` object
must be untouched, and one boot of the old gallery plus one bare `/` stock boot run under the browser lock, each
recording the `/profiles/` pack manifests and parts it fetched; then phase 3 and the new Worker in both orders (A: phase
3 before the deploy, B: after it, with `ALLOW_PARTIAL_UPLOAD=1`), printing `E1 MEASURE …` lines (evidence for decision
E1, not failures), the last two of each order being what an old tab's fetches get from the new Worker: its own runtime
manifest, and the release the pack manifest names. A boot the browser lock refuses started no browser: it waits outside
the lock and tries again, 24 h in all for the run (`OS_WAIT_S`), and past that it reads `NOT RUN` and fails the scenario,
a window boot too, because it measured nothing. It needs `OLD_REF` and a rehearsal state of the new pin built into another directory than `OLD_STATE`; without
`OLD_REF` it is skipped and named on the last line, never counted as OK. Before release routing it ran for pins J and K
against the live H (docs/REPIN-LOG.md: J's "Not done / running", K's "Gates (K)"), and for O (pin O, "CI mirror and deploy
rehearsal"): `REPLACED-KEYS OK 3`, two of them pack manifests, and in order B the new Worker's smoke before phase 3 failed
on the old `profiles/index.json`'s size (at J and K the old and new index had the same length). The smoke has since
compared the sha256 of every manifest and index too (3.4), so it no longer passes an old index of the same length.

## 10. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| QED64 says SharedArrayBuffer / cross-origin isolation is unavailable; `crossOriginIsolated` is false | COOP/COEP are missing. Check with `curl -sI <origin>/showcase/ \| grep -i cross-origin`. Possible causes: `run_worker_first` is not `true`, so assets are served without the Worker (`wrangler-config.mjs check` refuses that config); a custom-domain rule strips the headers; or an old deployment is still live. |
| The gallery card says "runtime manifest is not JSON", or the page stops after "fetching runtime manifest" | The manifest object has the wrong Content-Type. Check with `curl -sI <origin>/runtime/runtime-manifest.json \| grep -i content-type`. From release routing on that object is the release's: report a wrong type to the kernel's owner and do not re-put it. For our own JSON under `qed64-showcase/` (the indexes), `upload-artifacts.sh` sets `application/json` explicitly. An object uploaded earlier with another type keeps it, because `--checksum` skips identical bytes. Re-put it with `rclone copyto <local file> qed64-r2:qed64-artifacts/qed64-showcase/<key> --header-upload "Content-Type: application/json" --ignore-times` **[account]**. Rehearsed against the local S3 fake: with `--checksum` the object is skipped; with `--ignore-times` it is re-put with the new type. |
| `deploy-app.sh`: "files over the 25 MiB asset cap" | Workers static assets cap each file at 25 MiB. Today the largest asset is 8.3 MB (the QED64 bundle). A big file in `gallery/`, such as a thumbnail, must shrink; artifacts belong in R2. |
| Wrangler says "Read 82 files" but the manifest has 75 assets (pin E) | wrangler counts the 7 directories too (checked with `WRANGLER_LOG=debug`). Not a problem. |
| Gallery: `SNAPSHOT_UNPAIRED`, or the preflight refuses `entry-…-head` / `runtime` | An overlay index or snapshot belongs to another runtime than the shell. Typical causes: the shell was deployed before the upload, or the overlays were not rebaked after a re-pin. Fix: run `scripts/upload-artifacts.sh` (indexes revalidate at once), then `scripts/deploy-app.sh`. If the shell is old, check `wrangler versions list`. |
| `--smoke`: `content-length null` on assets | Fixed in the Worker, today in QED64's `createWorker`. The assets binding answers HEAD with no Content-Length, so the Worker takes the length from a GET of the same asset. Seen and fixed in the rehearsal. |
| `--smoke`: `status 307` on `/assets/….html` or `…/index.html` | Workers assets (`html_handling = "auto-trailing-slash"`, also QED64's production default) redirect `x.html` to `x`, keeping the query. The smoke checks canonical URLs and follows exactly that one redirect. |
| `--smoke --range` fails against `scripts/serve.mjs` | Expected: the local dev server has no Range support. Use `--range` only against the Worker (wrangler dev or deployed). |
| `upload-artifacts.sh`: "no verdict UX run …" | G2 found no verdict `showcase.sh ux` run for exactly this gallery + lock + overlays. Run `scripts/showcase.sh ux`. Set `ALLOW_NO_UX_VERDICT=1` only for a rehearsal. |
| `deploy target refused: R2_PREFIX is empty but R2_BUCKET is the SHARED bucket …`, or `… is inside "lean4game/" …` | The shared-bucket guard. An `R2_PREFIX` override is set (check with `env \| grep R2_`, for example one left over from a lean4game session), or only half of the own-bucket change was made. Unset it, or change `R2_BUCKET` and `R2_PREFIX` together in `infra/deploy.env`. `node scripts/lib/deploy-env.mjs` shows the resolved target. |
| `deploy-app.sh`: `RECORD MISSING` / `RECORD MISMATCH` | There is no release record for this remote, or the newest one published other R2 keys, bucket or prefix than this shell expects. Run `scripts/upload-artifacts.sh` with the same target and `MANIFEST_ARGS` first. If the upload ran on another machine, copy its record into `out/deploy/published/`, or set `ALLOW_UNRECORDED_UPLOAD=1` deliberately. |
| `FAIL G1 … CHECK-GALLERY FAIL 121 ok, 1 failed — sim-gallery exit 1` (or `108 ok, 1 failed`) while the gallery is unchanged | `sim-gallery.mjs` runs `gallery.js` on real timers, so a stalled Node event loop on a loaded host can fail a timing-tight case. Seen twice: once under a concurrent UX run (four standalone reruns passed), and in the closure lane's first `rehearse.sh all` on 2026-10-03 (`108 ok, 1 failed`). The second was traced to run 15a's status-line sample, which needed a 250 ms gallery tick to land within a 100 ms window; it failed 4 of 4 times with an injected 200 ms event-loop stall per second. The sample now waits up to 350 ms for the tick, and passed 3 of 3 times under the same injection (`out/ux/closure/RESULTS.md`). Since then G1 prints the sim's own FAIL lines (the case's name) after the `—`. Rerun the script: the step refused, so nothing was uploaded or deployed. If the same case repeats on an idle host, read it and fix the gallery. |
| `wrangler-config.mjs`: `WRANGLER-CONFIG MISMATCH` | `wrangler.toml` disagrees with `infra/deploy.env` (bucket, prefix, name, assets dir, `run_worker_first`). Fix the file, or delete it so `deploy-app.sh` regenerates it. |
| `wrangler dev` logs `Unable to fetch the Request.cf object` | `wrangler dev`, even with `--local`, fetches `Request.cf` from `workers.cloudflare.com`. In the rehearsal the sandbox blocked it and wrangler used a placeholder. Harmless. |
| CI: `CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID not set — skipping deploy` | Expected until the two repository secrets exist (first deploy checklist, step 5). The job is green and did nothing else. |
| CI: `no verdict UX run for exactly this gallery + lock + overlays` | `infra/ux-verdict.json` names other inputs: the gallery, the lock or an overlay changed since the last record. Run `scripts/showcase.sh ux` locally, then `node scripts/deploy-manifest.mjs --record-verdict` and commit the file. A dispatch with `allow_no_ux_verdict` deploys anyway, deliberately. |
| `PUBLISHED FAILED: … does not serve this manifest's artifacts`, then `version … fails on its preview URL` | The new version's R2 objects are not (all) in the bucket: a re-pin or rebake was pushed before its upload (phase 3 included, on a CI deploy), or the release's prefix `lean4-wasm64/<id>/` is missing. Run `scripts/upload-artifacts.sh` on the machine that has the artifacts, check the release, then run the workflow again (Actions → Run workflow on `main`, not Re-run jobs once `main` has moved on: see the first-deploy checklist). Nothing was promoted; the live version still has all the traffic. |
| `version … is uploaded but has no preview URL` | Preview URLs are off for the Worker, so wrangler printed no `Version Preview URL:` line. Turn them on (first deploy checklist, step 6) and run again. Nothing was promoted. |
| wrangler: `You cannot upload a new version of a Worker that does not yet exist` | A brand-new Worker needs one `wrangler deploy` first (first deploy checklist, step 6). |
| CI: `SHELL-FROM-SOURCE FAILED` | QED64's page built from the submodule differs from the lock: a different Node major, or the submodule is not at the lock's commit. `build-shell.mjs` lists every differing file; nothing is deployed. |
| First visit is slow | Expected: about 710 MB in total, see 3.5. The gallery shows the phases. A cut-off download resumes (Range). On a slow link the gallery shows "Still downloading: <QED64's step> — X of Y so far" while bytes arrive (10 Mbit/s: ready at 565 s, no card); its "This is taking too long" card means no progress at all for 4 min after the first 6 min, and it closes by itself if QED64 then becomes ready (gallery/README.md "Timeouts"). |

## Rehearsal

**Release routing, 2026-11-02, on `dbfd000`: `rehearse.sh all browser stop` rc 0** (state `$W/deploy-rehearsal-P3`, log
`$W/logs/p3-rh-state.log`): `UPLOAD DRY RUN OK`, `GUARD OK`, `UPLOAD OK` to both fakes (rclone and S3), `ROLLBACK OK`,
`RELEASE STAGED: 81 objects`, `DEPLOY DRY RUN OK` (`wrangler versions upload --dry-run`), `LOAD-R2 OK: 93 objects, 2.367
GB`, `SMOKE OK`, `BOOT-CHECK OK` (`/showcase/#hasse-view`). `dbfd000..eca8f22` changes no deploy script and no gallery
file: `ed8f781` changes the browser lock (which the CI rehearsal's ten boots below ran under), and `12aca96`, `eca8f22`
change `ci/rehearse-deploy.sh`. What it checks that the earlier runs did not: `upload` also stages the toolchain release in the fake bucket
(`RELEASE STAGED`, 81 objects at O); `load` loads our objects and the release's, and reads each one back; `deploy-dry`
runs `wrangler versions upload --dry-run`; the Worker under `serve` reads `/runtime/*` and `/profiles/*` from the
release's prefix; and `smoke`'s `curl` also asks for the runtime manifest of another runtime, which the release does not
have (its 404 is never cached). The rest of this section is from before that commit.

All of the above, without an account (2026-10-01; logs in `out/deploy-rehearsal/logs/`, screenshot
`out/deploy-rehearsal/boot-hasse-view.png`; the first run's logs are kept in `out/deploy-rehearsal/logs-run1/`):

```
scripts/deploy-rehearsal/rehearse.sh all       # upload-dry guard upload upload-s3 rollback deploy-dry load serve smoke
scripts/deploy-rehearsal/rehearse.sh browser
scripts/deploy-rehearsal/rehearse.sh stop
```

* **Isolation.** Every step except `browser` runs under `sandbox-exec -f scripts/deploy-rehearsal/offline.sb`, which
  denies all outbound connections except to localhost. Inside it, `curl https://1.1.1.1` fails to connect and DNS fails.
  rclone runs with `RCLONE_CONFIG` pointing at an **empty** config, so `qed64-r2` does not even exist for it. Its
  remotes are defined only by `RCLONE_CONFIG_*` environment variables:
  * `rehearsalr2` is the `local` backend (through an alias) at `work/deploy-rehearsal/bucket`;
  * `rehearsalguard` is the same at `work/deploy-rehearsal/guard-bucket`;
  * `rehearsals3` is the `s3` backend (provider Cloudflare) pointed at `scripts/deploy-rehearsal/fake-s3.mjs` on
    127.0.0.1.

  wrangler runs with `WRANGLER_SEND_METRICS=false` and no token. The rehearsal uses
  `DEPLOY_OUT=out/deploy-rehearsal/deploy`, so it never touches `out/deploy`.
* **Steps.**
  * `upload-dry` runs first (it writes the manifest the guard step reads). `guard`: negative controls of the shared-bucket guard, on a fake bucket seeded with stand-ins for QED64's root
    `runtime/runtime-manifest.json` and `snapshots/index.json` and lean4game's `lean4game/runtime/runtime-manifest.json`.
  * `upload-dry`: a dry run that writes nothing.
  * `upload`: every key lands in the fake bucket with the manifest's size and sha256, and nothing else is there; then
    the toolchain release is staged at `lean4-wasm64/<id>/`, where the kernel's publish puts it in the real bucket.
  * `upload-s3`: the real rclone s3 code path. Each object's Content-Type is checked against the manifest, objects over
    200 MiB must go multipart, and the phase order must hold.
  * `rollback`: an index overwritten with junk is restored. A record with a missing object is refused, and so is a
    record made through another remote.
  * `deploy-dry`: two negative controls of the release-record check, then the real dry run, which writes
    `wrangler.toml` and runs `wrangler versions upload --dry-run` (before `f13d535`: `wrangler deploy --dry-run`).
  * `load`: the fake bucket goes into wrangler dev's local R2, using a loader worker under `wrangler dev --local`.
    `wrangler r2 object put --local` refuses objects over about 300 MiB.
  * `serve`: the real `infra/worker.js` under `wrangler dev --local`, with the generated `wrangler.toml`.
  * `smoke`: `--smoke --all --range` plus the `curl` checks.
  * `browser`: one cold boot of `/showcase/#hasse-view` (`scripts/deploy-rehearsal/boot-check.mjs`).

**Re-run of record (history, 2026-10-04, pin-e lane): pin E `33b0967`, gallery `bbdbc932…`.** `all` rc 0: `UPLOAD DRY RUN
OK`, `GUARD OK` (sentinel bucket unchanged), `UPLOAD OK`, `FAKE-BUCKET OK: 93 objects`, `FAKE-S3 OK` (3 multipart),
`ROLLBACK DRY RUN OK`, `ROLLBACK OK`, the negative controls refused as expected, `RECORD OK`, `DEPLOY DRY RUN OK`,
`LOAD-R2 OK` (93 objects, 2.420 GB), `SMOKE OK` (168 URLs); `browser` rc 0 `BOOT-CHECK OK
http://localhost:8790/showcase/#hasse-view`; `stop` rc 0, nothing listens on 8790
(`$W/logs/pinE2-deploy-rehearsal-{all,browser,stop}.log`). The previous fake bucket was moved aside to
`$W/deploy-rehearsal/bucket.prev-20261004T071450Z`.

**Re-run of record (history, 2026-10-03, post-audit fix lane): pin C `5ac5d00`, gallery `b7aa521a…`.** `all` rc 0:
`UPLOAD DRY RUN OK`, `GUARD OK` (sentinel bucket unchanged), `UPLOAD OK`, `FAKE-BUCKET OK: 93 objects`, `FAKE-S3 OK` (3
multipart), `ROLLBACK OK`, both release-record negative controls refused, `RECORD OK`, `DEPLOY DRY RUN OK`, `LOAD-R2 OK`
(93 objects, 2.420 GB), `SMOKE OK` (168 URLs); `browser` rc 0 `BOOT-CHECK OK http://localhost:8790/showcase/#hasse-view`;
`stop` rc 0, nothing listens on 8790 (`$W/logs/postaudit-rehearse-{all,browser,stop}.log`). The previous fake bucket was
moved aside to `$W/deploy-rehearsal/bucket.prev-20261003T184953Z` (docs/HOUSEKEEPING.md §1).

**Re-run of record (history, 2026-10-03, closure lane): pin C `5ac5d00`, gallery `31f6d8d9…`.** `all` rc 0 on the second
attempt: `GUARD OK`, `FAKE-BUCKET OK: 93 objects`, `FAKE-S3 OK`, `ROLLBACK OK`, `DEPLOY DRY RUN OK`, `LOAD-R2 OK`, `SMOKE
OK` 168 URLs. The first attempt's `upload` refused on a G1 sim-gallery timing race, which has since been fixed
(troubleshooting table). The boot-check (the `browser` step's command, run inside the lane's own lock hold) gave
`BOOT-CHECK OK`, and `stop` rc 0. `deploy-manifest --check` → `DEPLOY-MANIFEST CHECK OK` with `G2 UX: verdict run
closure-full2 … was on THIS gallery 31f6d8d9…` (`out/ux/closure/RESULTS.md` (5)).

**Re-run of record (history, 2026-10-02, final-gate lane): pin C `5ac5d00`, gallery `2081098d…`.** `all`, `browser`, `stop`
all rc 0 (`GUARD OK`, `FAKE-BUCKET OK: 93 objects`, `FAKE-S3 OK`, `ROLLBACK OK`, `DEPLOY DRY RUN OK`, `LOAD-R2 OK`, `SMOKE
OK` 168 URLs, `BOOT-CHECK OK`), and `deploy-manifest --check` → `DEPLOY-MANIFEST CHECK OK` with `G2 UX: verdict run
final-C-full2 … was on THIS gallery 2081098daa7c9d72…` (docs/REPIN-LOG.md "final gate"). The detailed walk-through
below is from the earlier run on 9fdf9b8; the steps and their checks are the same.

Results of the second run, after the audit fixes, on QED64 9fdf9b8 (runtime `wasm64-2c18773ecfba45bb`, gallery
`7bbddf2e…`), 20:26–20:39 EDT, `RC=0` (`all.log`):

* **Gate.** No override was needed: G2 found a verdict, `G2 UX: verdict run final-full1 (2026-10-01T23:36:49Z, lane
  final) was on THIS gallery 7bbddf2e750c0fa2…, lock bb97785a4b24… and overlays widgets8, widgets7`. All 8 manifest
  runs (generate and `--check`, in each step) printed `OK   G1 … CHECK-GALLERY OK 122 ok, 0 failed`. In the first run,
  before that verdict existed, `upload-dry` refused without `ALLOW_NO_UX_VERDICT=1`
  (`logs-run1/upload-dry-no-verdict-refused.log`).
* **`guard`.** All 10 misuses were refused before rclone ran, among them:
  * `R2_PREFIX=` (with or without `ALLOW_SHARED_PREFIX=1`): `deploy target refused: R2_PREFIX is empty but R2_BUCKET is
    the SHARED bucket qed64-artifacts …`;
  * `lean4game/`, `lean4game`, `runtime/` and `snapshots/x/`: `… is inside "lean4game/" (or "runtime/", "snapshots/"),
    another app's namespace … refused, no override`;
  * `qed64-showcase-staging/` without the override;
  * `deploy-app.sh` and `--commands` with `R2_PREFIX=`;
  * `--commands` on a manifest generated with prefix `''`: `--commands refused (nothing printed)`;
  * `rollback-artifacts.sh` with `R2_PREFIX=lean4game/`.

  The own-bucket pair `R2_BUCKET=qed64-showcase-artifacts R2_PREFIX=` was accepted. Result:
  `GUARD OK: … sentinel bucket unchanged (3 files, tree sha256 c6e8bb2c7b92fab8)`. This is the audit's reproduction
  (an empty `R2_PREFIX` overwrote a stand-in for QED64's root `runtime-manifest.json` with `UPLOAD OK`), now refused.
* **`upload-dry`.** `upload plan: 11 lists, 93 objects, 2.420 GB, 3 multipart; phases 1-objects -> 2-manifests ->
  3-indexes`, then `UPLOAD DRY RUN OK`. The (emptied) fake bucket's file count stayed at 0 -> 0.
* **`upload`.** The full 2.42 GB went into an empty fake bucket: `UPLOAD OK: 11 lists`, `rclone check` 0 differences
  per list, release record `20261002T003032Z`, and
  `FAKE-BUCKET OK: 93 objects under qed64-showcase/, size + sha256 equal to the manifest, nothing else in the bucket`.
  In the first run, a second upload of the same release ended every list with `0 B / 0 B` (`logs-run1/upload-rerun.log`).
* **`upload-s3`.** `FAKE-S3 OK: 93 objects received; Content-Type {"application/json":8,"application/octet-stream":85} ==
  manifest; 3 multipart (widgets.a0c16868a07dfd68.snapz 5 parts, widgets.62e1f451c1940d1b.snapz 6 parts,
  mathlib.bf13acc48d0efb21.snapz 5 parts); phases objects -> manifests -> indexes in order`. A separate probe showed that
  `--header-upload "Content-Type: …"` sets the type on both PutObject and CreateMultipartUpload, and that rclone's own
  guess on this host is the same (`.json` -> `application/json`, `.snapz` / `.part-N` -> `application/octet-stream`).
* **`rollback`.** The step picked the newest `rehearsalr2` record, `20261002T003032Z`, not the newer `rehearsals3` one.
  `ROLLBACK DRY RUN OK: nothing written`, then `ROLLBACK OK` with the new record `20261002T003243Z-rollback`, and
  the junked `snapshots/widgets8/index.json` came back byte-identical. Two refusals followed:
  * with one pack part moved away: `1 object(s) of this release are not in the bucket … nothing was changed`;
  * for the `rehearsals3` record: `uploaded through remote 'rehearsals3', current R2_REMOTE is 'rehearsalr2'`.
* **`deploy-dry`.** The two negative controls refused:
  * `RECORD MISSING: no release record of remote 'rehearsalnorecord' …`;
  * the small variant: `RECORD MISMATCH vs 20261002T003243Z-rollback (rollback to 20261002T003032Z): 67 R2 key(s)
    differ …`.

  Neither wrote `wrangler.toml`. Then the dry run itself:
  * `RECORD OK: this shell's 93 R2 keys (pin wasm64-2c18773ecfba45bb, prefix 'qed64-showcase/') are what release
    record 20261002T003243Z-rollback … published to rehearsalr2:qed64-artifacts`;
  * `STAGE-ASSETS OK … (17.6 MiB)` and `staged shell and gallery both pinned to …`;
  * `WRANGLER-CONFIG OK … bucket qed64-artifacts, R2_PREFIX "qed64-showcase/" … run_worker_first`;
  * wrangler 4.125.0 `--dry-run: exiting now`, with bindings `env.ARTIFACTS (qed64-artifacts)`,
    `env.R2_PREFIX ("qed64-showcase/")` and `env.ROOT_REDIRECT ("/showcase/")`;
  * `DEPLOY DRY RUN OK`.
* **`load`.** `LOAD-R2 OK: 93 objects, 2.420 GB … 93/93 read back with the manifest's size and Content-Type; 21 s`.
* **`smoke`.** `SMOKE http://localhost:8790: 168 URLs (75 assets + 93/93 R2 keys) answer 200 …` and `SMOKE OK`. The
  range checks on `widgets.62e1f451c1940d1b.snapz`:
  * `bytes=0-99` -> 206, `content-range bytes 0-99/364676266`;
  * past the end -> 416, `content-range bytes */364676266`;
  * a mismatched `If-Range` -> 200.

  The `curl` checks:
  * the Range GET gave `HTTP/1.1 206 Partial Content`, `Content-Range: bytes 1000000-1000099/364676266` and
    `Content-Length: 100`, with the three `Cross-Origin-*` headers;
  * the three `Cross-Origin-*` headers are present on `/showcase/`;
  * `/` gives `302` to `/showcase/`;
  * `/runtime/runtime-manifest.json` is `application/json` with `must-revalidate`.
* **`browser`** (the lock was acquired at 21:07, after the other lanes' UX runs). `BOOT-CHECK OK
  http://localhost:8790/showcase/#hasse-view`:
  * the preflight passed on `widgets8`;
  * QED64 reached `ready` with hasse-view current after 14 s;
  * the cursor was on line 18;
  * the page was `crossOriginIsolated`;
  * the HasseView panel rendered with svg `{"rect":8,"line":12,"text":16}` and "Insertable examples (click to insert
    after the command)";
  * every request went to `localhost:8790` (66 requests);
  * there were 26 artifact GETs, 676.3 MB, all 200;
  * there was 1 page error, the `unsupported` one per page load that the UX suite's console allowlist expects.

  Screenshot: `out/deploy-rehearsal/boot-hasse-view.png`.
* **`stop`.** `stopped; nothing listens on 8790`. Afterwards `pgrep` found no wrangler, workerd or fake-s3 process.
* **CI option B** (history: that template and `stage-shell-from-tarball.mjs` were removed on 2026-10-04, when the
  page started being built from source; today's CI is section 9 and [CI rehearsal](#ci-rehearsal)), simulated in a
  clean copy of the tree (no `release/`, `out/`, `work/`, `node_modules/`) under
  `offline.sb`. The workflow's own `run:` blocks were extracted from the YAML; the only change was
  `wrangler deploy --dry-run`, and the dist URL was a `file://` tarball made with the then section 9's command
  (`logs/ci-sim.log`, `logs/ci-step8.log`):
  * worker tests 22/22;
  * `STAGE-SHELL OK … 58 dist files … + 17 gallery files`, including `OK   T5 … runtime-manifest….json matches the
    lock` and `OK   T6 release/… does not exist yet`;
  * `CHECK-GALLERY OK 122 ok, 0 failed` (G1);
  * `wrote wrangler.toml … bucket_name="qed64-artifacts" R2_PREFIX="qed64-showcase/" run_worker_first="true"`;
  * `wrangler deploy --dry-run … --message 'pin wasm64-2c18773ecfba45bb gallery 7bbddf2e750c0fa2 prefix
    qed64-showcase/ ci 0123456789ab'` -> `--dry-run: exiting now`.

  The first run also showed the T1 tamper control: one byte appended to `workers/lsp-frames.js` gave `FAIL T1`.
* **Found and fixed by the rehearsals.**
  1. The assets binding answers HEAD without a Content-Length. All 75 assets failed the smoke until `infra/worker.js`
     took the length from a GET (`serveAsset`, test added).
  2. `html_handling` redirects `….html` to its extension-less URL; the smoke now follows exactly that one redirect.
  3. rclone's one-line stats are logged at INFO, i.e. not at all, until `--stats-log-level NOTICE` was added.
  4. **`wrangler dev` reaches out to `workers.cloudflare.com`** to fetch the `Request.cf` object. The sandbox blocked it
     (`getaddrinfo ENOTFOUND workers.cloudflare.com`, `wrangler-dev.log`), and wrangler fell back to a placeholder. So
     even `wrangler dev --local` is not offline by itself. Run it under `offline.sb` when that matters.
  5. (audit) An empty or foreign `R2_PREFIX` in the shared bucket was accepted. It is now the shared-bucket guard.
  6. (audit) Nothing tied the deploy to the upload. `deploy-app.sh` now checks the release record, and
     `rollback-artifacts.sh` checks the remote and writes a record.
  7. `npm ci --prefix infra` in a copy whose `infra/node_modules` was a **symlink** emptied the target directory. It was
     reinstalled with `npm ci --prefix infra` (4.125.0). Never symlink `infra/node_modules` into another checkout.

What the rehearsal cannot show: Cloudflare's own edge, which may differ from `wrangler dev` (for example, a HEAD on an
asset); the real R2 multipart limits; your account's workers.dev subdomain; DNS for a custom domain; a real
`wrangler versions upload`'s output and preview URL (the stand-in prints its own). Step 3.3's check on the preview URL
and step 3.4 against the live URL cover these.

## CI rehearsal

**Release routing, 2026-11-03 15:29Z to 11-04 11:49Z, on `eca8f22`: `REHEARSE-DEPLOY OK`, all nine scenarios** (log
`$W/logs/p3b-rehearse-deploy.log`, run `$W/pinO/rehearse-deploy-P3-eca8f22`, E1 lines in its `old-shell/e1-measure.txt`;
the CI mirror's `qed64-static` on the same commit, rc 0). It took 20 h because its first browser boot waited for the
host's memory: 71 tries refused at the 16 GiB floor over about 19 h, with 6.2-12.8 GiB free (median 10.1) while other
sessions ran. When 19.4 GiB came free, the ten boots ran in about 35 minutes. A run on `dbfd000` before it went red only because six boots were refused by
the lock for good and never started a browser. `12aca96` and `eca8f22` make a refused boot wait outside the lock and try
again, one deadline for the run (`OS_WAIT_S`, 24 h), and report a boot that never ran as `NOT RUN`, which fails the
scenario. Its nine scenarios check: `skip` (push, no secrets: the skip line, every later step skipped); `dry-run`
(everything up to `wrangler versions upload --dry-run`, no smoke); `unpublished` (over an empty R2 the pre-promotion check
refuses, nothing is promoted); `no-preview` (wrangler prints no preview URL: refused with the reason, nothing promoted);
`deploy` (`SHOWCASE_ORIGIN` set: `PRE-PROMOTION OK`, the promotion, the workflow's smoke step on that origin); `no-origin` (no
`SHOWCASE_ORIGIN`: the same, with the smoke on the URL `deploy-app.sh` derived; there is no skip line any more);
`no-verdict` (a gallery change without a new verdict: G2 refuses); `tamper` (`--published` with one index sha256 and two
object sizes altered, ours and the release's, and `--smoke` on the same: FAIL); and `old-shell` (section 9), where a pack manifest replaced under the old shell, or an old
boot fetching a pack part of the new release, would show that the pack-manifest half of E1 is not gone for the upload
window. An old tab left open past the promotion is covered only for its runtime manifest and the release
`/profiles/lean-core.manifest.json` names, on two `E1 MEASURE` lines.

`old-shell` on `eca8f22`, with H's `d60b15e` as the live shell:
- **Phases 1-2:** no live object was replaced (`REPLACED-KEYS OK 0`, no `E1 HAZARD`). Every boot of the old shell fetched 8
  pack parts, all 8 of the live release and none of the new one. Before release routing, O1 and O2 fetched all 8 from the
  new release. So the pack-manifest half of E1 is gone.
- **Order A:** the old shell's bare stock boot in the window FAILED (its checker died at boot), as on O1, O2 and
  `dbfd000`; the old gallery in the window OK. Then the new workflow showed `PRE-PROMOTION OK`, promoted, `SMOKE OK`, and
  the new gallery and stock boots were OK.
- **Order B:** the CI pre-promotion check refused before phase 3, with nothing promoted. The new Worker's smoke before
  phase 3 failed, as expected. The new gallery and stock boots in the window were OK. After phase 3, `--published`,
  `--smoke --all --range` and both boots were OK.
- **An old tab, after either order:** its own runtime manifest gets a `no-store` 404, and `/profiles/lean-core.manifest.json`
  names O's release.

*History:* the two workflows, run on this machine before anything was pushed (2026-10-04, R3 lane; logs in `$W/logs/r3/`, run
directories in `$W/r3/ci/`). Every job ran in a fresh clone of a commit (`ci/run-local.mjs`), never in this checkout.

* **Lint.** `actionlint` 1.7.12 on all workflows: rc 0 (it runs shellcheck on every `run:` block); `shellcheck` on the
  new and changed shell scripts: rc 0 (`lint.log`).
* **`--from-lock` equivalence**, in the main checkout: the full manifest and the `--from-lock` manifest, both with
  prefix `qed64-showcase/`, are identical apart from `options.source = "lock"`, and their rclone lists are identical
  (`equiv-local.log`, `equiv-lock.log`): 75 assets, 93 R2 objects, every G/L/R gate OK in both.
* **`ci/rehearse-deploy.sh`**, run 1 on commit `3d78971` (`rehearse-deploy-1.log`; fake R2 = a copy-on-write copy of
  the 93-object state of the pin-E rehearsal). `REHEARSE-DEPLOY OK`, every scenario as expected:
  * `skip` (push, no secrets): the skip line; the 9 later steps skipped.
  * `dry-run` (dispatch `dry_run`, no secrets): `SHELL-FROM-SOURCE OK` (58/58 files == lock), Worker tests 22/22,
    `DEPLOY-MANIFEST OK` and `CHECK OK` with `G1 … CHECK-GALLERY OK 128 ok, 0 failed`, G2 from the committed record
    (`verdict run r2-main-full2 … (committed record infra/ux-verdict.json …)`), `PUBLISHED CHECK SKIPPED`,
    `STAGE-ASSETS OK (17.6 MiB)`, `WRANGLER-CONFIG OK`, wrangler 4.125.0 `--dry-run: exiting now` (6.50 KiB bundle,
    binding `env.ARTIFACTS (qed64-artifacts)`), `DEPLOY DRY RUN OK`; no smoke. No root `npm ci` was needed.
  * `unpublished` (origin = a wrangler dev over an EMPTY R2): `PUBLISHED FAILED`, every key 404; the job failed in the
    deploy step and wrangler was never called.
  * `deploy` (origin = the live stand-in over the fake R2): `PUBLISHED-OBJECTS … 93/93`, R3 OK on both fetched overlay
    indexes, `PUBLISHED OK`, then the stand-in "deploy" (`wrangler deploy --dry-run` + `wrangler dev --local` on the
    generated config), `DEPLOYED-URL http://127.0.0.1:8792`, and `SMOKE OK`: 168 URLs (75 assets + 93/93 R2 keys) with
    size, isolation, cache and content-type headers, Range 206 / 416 / If-Range 200.
  * `first` (no `SHOWCASE_ORIGIN`): `PUBLISHED CHECK SKIPPED`, the URL taken from the deploy's output, `SMOKE OK`.
  * `no-verdict` (a scratch commit that only appends a CSS comment to the gallery): G2 `NO verdict … infra/ux-verdict.json
    names other inputs`, `deploy-app.sh: no verdict UX run for exactly this gallery …`; wrangler never called.
  * `tamper`: `--published` with one overlay index sha256 and one `.snapz` size altered in the manifest: both caught
    (`91/93`), `PUBLISHED FAILED`, rc 1.
  * Afterwards nothing listened on 8792 or 8802.
* **`lean-ci.yml`**, run 1 on commit `3d78971` (`lean-ci-1.log`, `--parallel 3`): all 9 `packages` jobs green (ProofWidgets
  cloned and built in each; Mathlib `v4.34.0` from `lake exe cache get`, `Decompressed 8714 already-cached file(s)`
  from the host's warm `~/.cache/mathlib`, then `lake build`: dist-lens 3088 jobs, lean-widget-kit 3197, graph-scope
  1042, tree-scope 1035, hasse-view 938, interval-inspector 866, expr-xray 25, simp-lens 22, chart-kit 21; `lake
  test` green in the 8 packages with a test driver, skipped in lean-widget-kit). `showcase` green: `DUMPS OK: 8
  regenerated dumps == committed`, 60/60 panels clean. `qed64-static` **failed, not on a check**: `check-portable`
  printed `PORTABLE OK` and then its node process (v26.3.0) never exited. Its stacks (`node-exit-hang-sample.log`):
  the main thread in `process.exit` → `NodePlatform::Shutdown` joining the worker threads, one V8 worker in a Maglev
  compile job waiting in `CollectionBarrier::AwaitCollectionBackground` for a main-thread GC that cannot come. A
  deadlock inside Node/V8 at exit (inference from the stacks; not reproduced on demand). The process was stopped
  after 20 min (`FAIL(143)`). Every job now has `timeout-minutes`, and `ci/run-local.mjs` enforces them, so such a hang
  fails a job in bounded time on GitHub and here.
* **Run 2 on commit `3fc04e2`** (the job timeouts, the probe step that deletes the committed dump first, and the docs):
  `lean-ci-2.log` `RUN-LOCAL OK`: the 9 `packages` jobs, `showcase` (`DUMPS OK: 8 regenerated dumps == committed`,
  60/60 panels clean) and `qed64-static` (all 12 steps: `PORTABLE OK`, `LOCKFIFO OK`, `LOCKRACE OK`, `QED64-SRC OK`,
  `SHELL-FROM-SOURCE OK` 58 files, `FETCH-ARTIFACTS OK` 6 from git, the widget export (222 files), Worker tests 22/22,
  `CHECK-GALLERY OK 128 ok, 0 failed` with `SIM-GALLERY OK 114 ok`); `pages` skipped (no `DEPLOY_GITHUB_PAGES`).
  `rehearse-deploy-2.log` `REHEARSE-DEPLOY OK` with the same 7 scenarios and the same results as run 1 (`SMOKE OK` on
  168 URLs).
* **The manual path after these changes** (`local-path-regression.log`, fresh rehearsal and deploy-out dirs):
  `rehearse.sh upload-dry guard` rc 0 (`UPLOAD DRY RUN OK`, 93 objects in 11 lists; `GUARD OK`, all 10 misuses
  refused, sentinel bucket unchanged); `upload-artifacts.sh` with `--from-lock` in `MANIFEST_ARGS` refused (rc 3), and
  `--commands` on a `--from-lock` manifest refused (rc 3).
* What this does **not** show: GitHub's ubuntu runner itself (tool versions, cold caches, disk), Cloudflare's edge, a
  real token's permissions, and the workers.dev URL format of a real deployment. The first real run covers them
  (first deploy checklist, steps 6 and 8).

