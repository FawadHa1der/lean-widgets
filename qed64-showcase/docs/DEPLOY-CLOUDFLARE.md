# Deploying the showcase to Cloudflare, the lean4game way

> **Status: rehearsed locally, not deployed.** Nothing here has logged in to Cloudflare, uploaded to R2 or deployed.
> Every script and command below was run against local fakes (an rclone `local` remote, a local S3 endpoint and
> `wrangler dev --local`) or as a dry run, inside a macOS sandbox that blocks all outbound traffic except to localhost.
> See [Rehearsal](#rehearsal). Two kinds of command were not run here:
> * commands marked **[account]**, which need your Cloudflare login or R2 token;
> * the 3.1 preconditions `showcase.sh gallery` / `ux`, which the verification lanes run (the rehearsal below found
>   `final-full1` on pin B; the re-rehearsal on pin C found `multipin-C-full3-b`, the final-gate re-run `final-C-full2`).
>   `showcase.sh verify` was run here.
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
> Do not deploy pin B. A switch to another pin (back to C `5ac5d00`, to D `3b42714`, …) produces a new gallery hash, so it needs two new verdict
> `ux` runs on that gallery before G2 passes. Owner decisions before a public deploy (headed sign-off on the deployed
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
  `/showcase/`, together 75 files and about 18 MB.
* **Artifacts.** These live in the **R2 bucket `qed64-artifacts` that QED64 already uses**, under their own prefix
  `qed64-showcase/`, just as lean4game uses `lean4game/`. They are uploaded through the **existing rclone remote
  `qed64-r2`**, and the same bucket-scoped token serves all three apps.
* **One origin.** `infra/worker.js` puts COOP/COEP/CORP on every response. Without these headers the browser refuses
  SharedArrayBuffer and Memory64, and QED64 cannot start.
* **Uploads use `rclone copy`, never `sync`.** Phase order is digest-named objects, then manifests, then `index.json`.
  wrangler 4.125.0 is pinned in `infra/package.json`. `scripts/deploy-app.sh` stages the shell and runs `wrangler deploy`.

| URL | Served from | Content |
|---|---|---|
| `/showcase/` | Workers static assets | the gallery (`gallery/` without `*.md`, `x3.html`, dotfiles) |
| `/` | Workers static assets | the pinned QED64 `dist/` (`release/<pin id>/dist`, byte-identical to `QED64.lock.json`). A bare `/` redirects to `/showcase/` (`ROOT_REDIRECT`). The gallery iframes `/?snapshots=snapshots/widgets8`, which is never redirected. |
| `/runtime/…`, `/profiles/…`, `/snapshots/…` | R2 key `qed64-showcase/<path>` | runtime chunks + manifests, core and mathlib-essential packs, the stock snapshot pair, our overlays `snapshots/widgets8/`, `snapshots/widgets7/` |

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

**Shared-bucket guard.** The bucket `qed64-artifacts` also holds QED64's production objects at its root (`runtime/`,
`profiles/`, `snapshots/`) and lean4game's under `lean4game/`. A wrong prefix there would overwrite another app's
*mutable* names (`runtime-manifest.json`, `profiles/index.json`, `snapshots/index.json`, `*.manifest.json`). So in that
bucket the loader accepts only `R2_PREFIX=qed64-showcase/`:
* an **empty** prefix, or one inside `lean4game/`, `runtime/`, `profiles/` or `snapshots/`, is **always refused**
  (`deploy target refused: …`), with no override. lean4game falls back to its own prefix when `R2_PREFIX` is empty;
  here an empty value is refused instead, because it almost always means a half-applied own-bucket setup;
* any other prefix (for example a staging prefix `qed64-showcase-staging/`) needs `ALLOW_SHARED_PREFIX=1`, set
  deliberately.

Every script checks this before it runs rclone or wrangler. The rehearsal's `guard` step proves it on a fake bucket
seeded with stand-ins for QED64's and lean4game's manifests.

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
     QED64's objects stay at the bucket root and lean4game's under `lean4game/`, and the showcase's go under
     `qed64-showcase/`. The three sets of mutable files (`runtime-manifest.json`, `profiles/index.json`,
     `snapshots/index.json`) never collide, because each Worker reads only its own prefix.
   * **Own bucket (alternative).** Create a bucket `qed64-showcase-artifacts` (R2 → Create bucket) **[account]**. Give the
     upload token access to it, by extending the existing token or by creating a new one and a new rclone remote
     (command below). Then edit **both lines together** in `infra/deploy.env`: `R2_BUCKET=qed64-showcase-artifacts` and
     `R2_PREFIX=` (empty), plus `R2_REMOTE` if you made a new remote. Change them in the file rather than with
     one-off environment variables. If you set only `R2_PREFIX=` and forget `R2_BUCKET`, the scripts refuse (shared-bucket
     guard above) instead of writing to QED64's root. Check the result with `node scripts/lib/deploy-env.mjs`. Never
     commit the keys:
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
   | **showcase, full** (default: stock pair + widgets8 + widgets7 + both packs) | **2.42 GB** (93 objects) |
   | showcase, small variant (below) | 0.69 GB (26 objects) |
   | **Total with the full showcase** | **≈ 6.9 GB of 10 GB** |

   These numbers come from each project's docs. **Measure the real usage before the first upload** **[account]**.
   QED64 has promoted at least once since this showcase was first pinned, and both QED64 and lean4game upload
   copy-only, so their old objects accumulate in the bucket too:
   ```
   # either: dashboard → R2 → qed64-artifacts → Metrics (storage)
   rclone size qed64-r2:qed64-artifacts                  # [account] lists every object (metadata only); prints total size
   rclone size qed64-r2:qed64-artifacts/lean4game/       # [account] one app's share
   ```
   If the measured total plus 2.42 GB is close to 10 GB, use the small variant below (0.69 GB), or first collect the
   showcase's own old objects (section 6). R2 bills storage above the free tier; it does not stop uploads.

   The showcase's runtime, packs and stock snapshots are byte-identical to QED64's when QED64 serves the same build.
   They are stored a second time anyway, because the showcase must stay pinned to its own build and keep its own
   mutable names. Uploads are copy-only, so every **re-pin or rebake adds** its new digest-named objects and the old
   ones stay. A re-pin adds up to about 2.4 GB; one overlay rebake adds about 0.35 GB. Collect the old objects
   deliberately once no deployed shell needs them (see [Re-pin](#6-re-pin)).

   **Small variant.** Set `MANIFEST_ARGS="--overlays widgets8 --no-stock-snapshots --no-essential-pack"` for the upload
   (and the same for `deploy-app.sh`). The gallery uses only `widgets8`, so it is unaffected. What you give up:
   * the bare stock page at `/?…` without `snapshots=` cannot boot (no stock snapshots). Keep `ROOT_REDIRECT`;
   * QED64's on-demand **"Load exact imports"** fails, because it needs the 1 GB essential pack;
   * `widgets7` is not uploaded. The gallery's automatic fallback, used when `widgets8` fails its preflight, is
     therefore gone, and `?overlay=widgets7` fails (`gallery/README.md`, `?overlay=`).

## 3. Per release

### 3.1 Preconditions (no account)

Everything must be green on **the current pin** (`QED64.lock.json`) and **one gallery revision**, with no edit to
`gallery/`, the overlays or the lock in between:

```
scripts/showcase.sh verify      # pin, vendor, release files, pin-site inventory
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

What the script does (each step was exercised in the rehearsal):
1. It reads the target from `infra/deploy.env` (refusing a shared-bucket prefix other than `qed64-showcase/`, see the
   guard at the top) and checks `rclone listremotes`.
2. It regenerates the manifest with `--prefix qed64-showcase/`, which hashes every file and runs every gate (A1–A5,
   L1, R1–R4, G1), then runs `--check`. It refuses on any FAIL. It prints the G2 line and refuses unless it names a
   verdict run.
3. It writes the upload plan to `out/deploy/upload/plan.tsv`: one exact file list per phase, group and content type.
   It then runs one `rclone copy --files-from-raw` per list, **never sync**, with `--checksum` (already-uploaded
   digest-named files are skipped) and multipart in 64 MiB chunks. The three `.snapz` files over 300 MiB need
   multipart: wrangler's `r2 object put` cannot upload them. The phases run in this order:
   1. every digest-named object (runtime chunks, pack parts, `.snapz`), as `application/octet-stream`;
   2. the manifests that name them (`runtime-manifest*.json`, `*.manifest.json`), as `application/json`;
   3. the `index.json` files that name the manifests (profiles, stock snapshots, each overlay), as `application/json`.

   A browser that revalidates an index halfway through the upload therefore never learns a name whose object is not
   there yet.
4. It sets the Content-Type explicitly with `--header-upload`. rclone's s3 backend would guess the same types from
   the file extension, but the guess depends on the host's MIME tables. The pinned shell refuses a runtime manifest
   that is not typed JSON (`qed64-boot.ts:67-70`), and the gallery refuses a snapshot typed as HTML.
5. It runs `rclone check --one-way` on every list (size + hash; nothing is downloaded).
6. It writes a **release record** `out/deploy/published/<UTC time>/`, containing the manifest, the plan and a copy of
   every manifest and index it published, for [rollback](#5-rollback) and for `deploy-app.sh`'s record check. Back
   it up right away (section 5, "Keep the records").

The first run uploads about 2.42 GB. Later runs transfer only files whose bytes changed (`--checksum`). In
the rehearsal, a second run of the same release transferred 0 B (every list ended with `0 B / 0 B`).

### 3.3 Deploy the shell

```
DRY_RUN=1 scripts/deploy-app.sh           # no account: everything up to `wrangler deploy --dry-run` (after a real upload)
scripts/deploy-app.sh                     # [account] npx --prefix infra wrangler deploy
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
   `showcase/{index.html,gallery.js,lib.js,qed64-bridge.js,examples.json,pin.json}`), and checks that the staged
   bundle and `showcase/pin.json` name the same runtime buildId;
4. **checks the release record.** The newest record in `out/deploy/published/` for the remote `R2_REMOTE` (written by
   `upload-artifacts.sh`, or by `rollback-artifacts.sh`) must have the same bucket and prefix, and exactly this
   manifest's R2 keys with the same sha256. That includes the runtime manifest and the indexes. Otherwise the script
   stops with `RECORD MISSING … run scripts/upload-artifacts.sh first` or `RECORD MISMATCH …`. This catches the
   upload and the deploy running with different overrides or `MANIFEST_ARGS`, and a re-pinned shell deployed before
   its upload. `ALLOW_UNRECORDED_UPLOAD=1` skips the check deliberately, for example when the upload ran on another
   machine;
5. **writes `wrangler.toml` from `wrangler.toml.example`** when the file is absent, with the name, bucket, prefix and
   assets directory from `infra/deploy.env`. If the file exists, the script **refuses it unless it agrees**, including
   `run_worker_first = true`;
6. runs `npx --prefix infra wrangler deploy --message "pin <buildId> gallery <sha16> prefix qed64-showcase/"`. The
   message is what `wrangler versions list` shows when you pick a rollback target.

Run the steps in this order: **artifacts first, shell second.** A shell-only change (gallery code) needs step 3.3
alone. A re-pin or an overlay rebake needs both, in order.

### 3.4 Smoke test the live Worker **[account: needs the deployed URL]**

```
node scripts/deploy-manifest.mjs --smoke https://qed64-showcase.<subdomain>.workers.dev --all --range
curl -sI https://qed64-showcase.<subdomain>.workers.dev/showcase/ | grep -i cross-origin
curl -s -o /dev/null -D - -H 'Range: bytes=1000000-1000099' https://qed64-showcase.<subdomain>.workers.dev/snapshots/widgets8/<widgets.….snapz>
```

`--smoke --all` sends a HEAD request to every asset and every R2 key in the manifest (168 URLs). For each one
it checks:
* status 200 and `content-length == size`;
* COOP `same-origin`, COEP `require-corp`, CORP `same-origin`;
* QED64's cache rule (digest-named files immutable, every index and manifest `must-revalidate`);
* a JSON type on every `*.json` and a non-HTML type on binaries;
* no `Content-Encoding` on artifacts.

`--range` also sends single-range GETs to the largest `.snapz`. It expects 206 with `Content-Range bytes 0-99/<size>`,
416 past the end, and a full 200 for a mismatched `If-Range`. Every check must print `OK`, and the run must end with
`SMOKE OK`. The `curl` lines must show the three `Cross-Origin-*` headers, and the Range request must get
`HTTP/1.1 206`, `Content-Range: bytes 1000000-1000099/<size>` and `Content-Length: 100`.

### 3.5 Open it

Open `https://qed64-showcase.<subdomain>.workers.dev/showcase/` (a bare `/` redirects there). The gallery runs its
own pairing preflight, which checks that the overlay's index is JSON, its runtime equals the shell's buildId, and
every `.snapz` HEAD has `content-length == transfer`. Then it boots QED64 in the iframe.

A **first visit** downloads about 680 MB of artifacts: the runtime (159 MB), the core pack (121 MB), the
widgets8 snapshot (365 MB) and its `init` (33 MB). The rehearsal's cold boot measured 676.3 MB in 26 GETs; with the app
shell, the last-mile lane measured 709.8 MB through a shaped link (123 s at 50 Mbit/s; at 10 Mbit/s the gallery's boot
timeout fires first, see the status block at the top). Later visits come from OPFS and the HTTP cache. If a
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
  upload path: it prints one `.mutable` line per group, so within a group (for example `profiles/`) an `index.json`
  shares a copy with the `*.manifest.json` files it names. Upload with `scripts/upload-artifacts.sh`, which keeps
  lean4game's order (digest-named objects, then manifests, then indexes).

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
     metadata only). Re-publishing an index whose objects are gone would strand visitors.

   Otherwise it re-copies the record's manifests, then its indexes, with their content types. It then writes a new
   record `<time>-rollback`, so that `deploy-app.sh` compares against what is live now.

   **Keep the records.** They are the only copy of what each release published. Unlike lean4game, whose rollback reads
   old indexes from git history, this tree has no git history, and `out/` is gitignored. After every real upload or
   rollback, copy them somewhere durable, for example:
   ```
   rsync -a out/deploy/published/ ~/Backups/qed64-showcase-releases/    # or commit them to a private repo
   ```
   A record is a few MB: the manifest, the upload plan and the manifests and indexes it published.
2. **Shell** **[account]**:
   ```
   npx --prefix infra wrangler versions list        # each version's message names its pin + gallery
   npx --prefix infra wrangler rollback <version-id>
   ```
   A Worker version carries its static assets, so this should restore the earlier dist and gallery exactly.
   Confirm with the smoke in 3.4 against the manifest of that release:
   `node scripts/deploy-manifest.mjs --out <dir holding that manifest.json> --smoke <origin> --all`. The release record
   holds one.
3. **Roll forward** the same way as a normal release: run steps 3.2 and 3.3 from the fixed state. Only what changed is
   transferred.

The order is the reverse of a release: put the old names back first, then the old shell. The old shell's
`runtime-manifest.<buildId>.json` is immutable and still in the bucket.

## 6. Re-pin

A re-pin (README "Re-pin: adding a pin when QED64 sends a new commit") usually changes the runtime buildId. That has
these consequences:
* **Deploy only the active pin** (printed by `scripts/showcase.sh pin current`; C `5ac5d00` until 2026-10-04, E `33b0967` since). `pin use <id>` regenerates
  `out/deploy` for the new active pin, and `deploy-manifest --check` G2 then needs a verdict run on that pin's gallery.
* **Snapshots are binary-paired to the runtime.** The overlays must be rebaked against the new runtime before
  anything is uploaded. The R3 gate refuses an index entry whose `runtime` is not the lock's buildId, and the gallery
  refuses a mismatch with `SNAPSHOT_UNPAIRED`.
* **Upload before you deploy.** The new runtime chunks, packs and snapshots have new digest names, so phase 1 uploads
  them next to the old ones. Phase 2/3 then switches `runtime-manifest.json`, `snapshots/index.json` and the overlay
  indexes. Only after that does `deploy-app.sh` put the new shell live.
* **Old objects stay.** The previous shell, still open in visitors' tabs, needs its own chunks and
  `runtime-manifest.<old buildId>.json`, and rollback needs them too. Delete them only deliberately, after the new
  release has been live for a while. Use exact keys from the old release record's `manifest.json`
  (`rclone deletefile qed64-r2:qed64-artifacts/qed64-showcase/<key>` **[account]**). Never use `sync` or a prefix-wide
  delete in the shared bucket: QED64's and lean4game's objects are in it too.
* Run all of section 3 again: preconditions on the new pin (a new UX verdict), upload, deploy, smoke.

## 7. Custom domain **[account]**

The zone must be on Cloudflare. Either:
* in the dashboard: Workers & Pages → `qed64-showcase` → Settings → Domains & Routes → Add → Custom domain (the
  dashboard's wording may have changed), or
* in `wrangler.toml` (gitignored; `scripts/lib/wrangler-config.mjs check` does not touch extra keys), add
  ```
  routes = [{ pattern = "showcase.example.org", custom_domain = true }]
  ```
  and run `scripts/deploy-app.sh` again.

The Worker sets the isolation headers itself, so they also apply on the custom domain. Do not add a Transform Rule or
another Worker on that hostname that strips or overrides `Cross-Origin-*` headers. After the change, repeat 3.4 with the
new origin. `workers_dev = true` keeps the `*.workers.dev` URL working as well; set it to `false` to retire it.

## 8. Security

* **The shared token can write every app's objects in `qed64-artifacts`.** Two layers stop the showcase from touching
  the others: the shared-bucket guard (at the top of this guide) and the scripts writing only under
  `$R2_PREFIX`, from exact file lists, never deleting.
* **Two credentials, never one broad one** (QED64 `docs/DEPLOY.md`, "Security"):
  * the **R2 API token** (S3 keys) lives only in your local rclone config (`qed64-r2`). Its scope is Object Read &
    Write on `qed64-artifacts`, with an expiry;
  * **Workers deploys** use your `wrangler login`. For CI, use an API token with **Workers Scripts: Edit only, no R2
    permission**, so that a leaked CI secret cannot touch artifacts.
* Never commit keys or tokens. `wrangler.toml` holds no secrets and is gitignored anyway; `infra/deploy.env` holds only
  names.
* Do not enable the bucket's public `r2.dev` URL. Reads go through the Worker binding, and the Worker serves only
  `/runtime/`, `/profiles/` and `/snapshots/` under its own prefix, so the showcase never exposes QED64's or
  lean4game's keys. Path traversal and empty segments are refused (`infra/worker.test.mjs`).

## 9. CI (optional; manual deploys are recommended)

`.github/workflows/deploy-showcase.yml.example` is a template modelled on lean4game's `deploy.yml`. Copy it to `.yml`
to enable it. It only redeploys the shell, with a Workers-only token.

**The catch.** The shell includes the pinned QED64 `dist/` from `release/<pin id>/dist`, and `release/` is
gitignored (2.4 GB with the artifacts). A clean CI checkout cannot stage it. The manifest's R/G gates also need the
artifacts and the UX record, which exist only on your machine. There are two options:

* **A. Manual deploys from this machine (recommended).** Every gate runs. lean4game's artifacts already require
  manual uploads, and so do these: they change only with a re-pin or rebake, which runs on this machine.
* **B. CI with a pinned dist tarball.** Publish the dist where CI can download it. A GitHub release asset is the
  simplest place; the URL goes in the secret `SHOWCASE_DIST_URL`. Build the tarball with:
  ```
  ID=$(node scripts/lib/pins.mjs active); BID=$(node scripts/lib/pins.mjs active-bid)
  COPYFILE_DISABLE=1 tar --no-xattrs -C release/$ID -czf qed64-dist-$ID.tar.gz dist public/runtime/runtime-manifest.$BID.json
  ```
  (`COPYFILE_DISABLE=1 --no-xattrs`: macOS tar otherwise adds `._*` files, which are refused as extra files.) CI runs
  `node scripts/stage-shell-from-tarball.mjs <tarball> --out out/deploy/assets --release-dir`. The script refuses a
  tarball unless it holds exactly the lock's dist files, with their size and sha256, plus the lock's runtime manifest.
  It adds the checkout's gallery and runs the 25 MiB check. `--release-dir` also writes the verified files to
  `release/<pin id>/`, so that CI can then run the gallery gate **G1** (`node scripts/check-gallery.mjs`). After that,
  CI writes `wrangler.toml` with `scripts/lib/wrangler-config.mjs write` and runs
  `wrangler deploy --message "pin <pin id> (<buildId>) gallery <sha16> prefix <prefix> ci <commit>"`. This is the same label as
  the manual path, so `wrangler versions list` stays usable for rollback.

  Limits of option B:
  * a re-pin needs a new tarball;
  * CI can only redeploy shells whose artifacts a manual upload already published;
  * it skips the UX-verdict gate (G2) and the release-record check.

  Secrets: `CLOUDFLARE_API_TOKEN` (Workers Scripts: Edit), `CLOUDFLARE_ACCOUNT_ID`, `SHOWCASE_DIST_URL`. Without them
  the workflow only runs the worker tests.

## 10. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| QED64 says SharedArrayBuffer / cross-origin isolation is unavailable; `crossOriginIsolated` is false | COOP/COEP are missing. Check with `curl -sI <origin>/showcase/ \| grep -i cross-origin`. Possible causes: `run_worker_first` is not `true`, so assets are served without the Worker (`wrangler-config.mjs check` refuses that config); a custom-domain rule strips the headers; or an old deployment is still live. |
| The gallery card says "runtime manifest is not JSON", or the page stops after "fetching runtime manifest" | The manifest object has the wrong Content-Type. Check with `curl -sI <origin>/runtime/runtime-manifest.json \| grep -i content-type`. `upload-artifacts.sh` sets `application/json` explicitly. An object uploaded earlier with another type keeps it, because `--checksum` skips identical bytes. Re-put it with `rclone copyto <local file> qed64-r2:qed64-artifacts/qed64-showcase/<key> --header-upload "Content-Type: application/json" --ignore-times` **[account]**. Rehearsed against the local S3 fake: with `--checksum` the object is skipped; with `--ignore-times` it is re-put with the new type. |
| `deploy-app.sh`: "files over the 25 MiB asset cap" | Workers static assets cap each file at 25 MiB. Today the largest asset is 8.3 MB (the QED64 bundle). A big file in `gallery/`, such as a thumbnail, must shrink; artifacts belong in R2. |
| Wrangler says "Read 82 files" but the manifest has 75 assets | wrangler counts the 7 directories too (checked with `WRANGLER_LOG=debug`). Not a problem. |
| Gallery: `SNAPSHOT_UNPAIRED`, or the preflight refuses `entry-…-head` / `runtime` | An overlay index or snapshot belongs to another runtime than the shell. Typical causes: the shell was deployed before the upload, or the overlays were not rebaked after a re-pin. Fix: run `scripts/upload-artifacts.sh` (indexes revalidate at once), then `scripts/deploy-app.sh`. If the shell is old, check `wrangler versions list`. |
| `--smoke`: `content-length null` on assets | Fixed in `infra/worker.js`. The assets binding answers HEAD with no Content-Length, so the Worker takes the length from a GET of the same asset. Seen and fixed in the rehearsal. |
| `--smoke`: `status 307` on `/assets/….html` or `…/index.html` | Workers assets (`html_handling = "auto-trailing-slash"`, also QED64's production default) redirect `x.html` to `x`, keeping the query. The smoke checks canonical URLs and follows exactly that one redirect. |
| `--smoke --range` fails against `scripts/serve.mjs` | Expected: the local dev server has no Range support. Use `--range` only against the Worker (wrangler dev or deployed). |
| `upload-artifacts.sh`: "no verdict UX run …" | G2 found no verdict `showcase.sh ux` run for exactly this gallery + lock + overlays. Run `scripts/showcase.sh ux`. Set `ALLOW_NO_UX_VERDICT=1` only for a rehearsal. |
| `deploy target refused: R2_PREFIX is empty but R2_BUCKET is the SHARED bucket …`, or `… is inside "lean4game/" …` | The shared-bucket guard. An `R2_PREFIX` override is set (check with `env \| grep R2_`, for example one left over from a lean4game session), or only half of the own-bucket change was made. Unset it, or change `R2_BUCKET` and `R2_PREFIX` together in `infra/deploy.env`. `node scripts/lib/deploy-env.mjs` shows the resolved target. |
| `deploy-app.sh`: `RECORD MISSING` / `RECORD MISMATCH` | There is no release record for this remote, or the newest one published other R2 keys, bucket or prefix than this shell expects. Run `scripts/upload-artifacts.sh` with the same target and `MANIFEST_ARGS` first. If the upload ran on another machine, copy its record into `out/deploy/published/`, or set `ALLOW_UNRECORDED_UPLOAD=1` deliberately. |
| `FAIL G1 … CHECK-GALLERY FAIL 121 ok, 1 failed — sim-gallery exit 1` (or `108 ok, 1 failed`) while the gallery is unchanged | `sim-gallery.mjs` runs `gallery.js` on real timers, so a stalled Node event loop on a loaded host can fail a timing-tight case. Seen twice: once under a concurrent UX run (four standalone reruns passed), and in the closure lane's first `rehearse.sh all` on 2026-10-03 (`108 ok, 1 failed`). The second was traced to run 15a's status-line sample, which needed a 250 ms gallery tick to land within a 100 ms window; it failed 4 of 4 times with an injected 200 ms event-loop stall per second. The sample now waits up to 350 ms for the tick, and passed 3 of 3 times under the same injection (`out/ux/closure/RESULTS.md`). Since then G1 prints the sim's own FAIL lines (the case's name) after the `—`. Rerun the script: the step refused, so nothing was uploaded or deployed. If the same case repeats on an idle host, read it and fix the gallery. |
| `wrangler-config.mjs`: `WRANGLER-CONFIG MISMATCH` | `wrangler.toml` disagrees with `infra/deploy.env` (bucket, prefix, name, assets dir, `run_worker_first`). Fix the file, or delete it so `deploy-app.sh` regenerates it. |
| `wrangler dev` logs `Unable to fetch the Request.cf object` | `wrangler dev`, even with `--local`, fetches `Request.cf` from `workers.cloudflare.com`. In the rehearsal the sandbox blocked it and wrangler used a placeholder. Harmless. |
| First visit is slow | Expected: about 710 MB in total, see 3.5. The gallery shows the phases. A cut-off download resumes (Range). On a slow link the gallery shows "Still downloading: <QED64's step> — X of Y so far" while bytes arrive (10 Mbit/s: ready at 565 s, no card); its "This is taking too long" card means no progress at all for 4 min after the first 6 min, and it closes by itself if QED64 then becomes ready (gallery/README.md "Timeouts"). |

## Rehearsal

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
  * `upload`: every key lands in the fake bucket with the manifest's size and sha256, and nothing else is there.
  * `upload-s3`: the real rclone s3 code path. Each object's Content-Type is checked against the manifest, objects over
    200 MiB must go multipart, and the phase order must hold.
  * `rollback`: an index overwritten with junk is restored. A record with a missing object is refused, and so is a
    record made through another remote.
  * `deploy-dry`: two negative controls of the release-record check, then the real dry run, which writes
    `wrangler.toml` and runs `wrangler deploy --dry-run`.
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
* **CI option B**, simulated in a clean copy of the tree (no `release/`, `out/`, `work/`, `node_modules/`) under
  `offline.sb`. The workflow's own `run:` blocks were extracted from the YAML; the only change was
  `wrangler deploy --dry-run`, and the dist URL was a `file://` tarball made with the command in section 9
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
asset); the real R2 multipart limits; your account's workers.dev subdomain; DNS for a custom domain. Step 3.4 against
the live URL covers these.
