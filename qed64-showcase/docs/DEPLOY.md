# Deploying the showcase on its own origin (kit only — nothing is deployed)

> **Status: not deployed.** Nothing in this repo has uploaded, deployed or logged in anywhere.
> Publishing needs the owner's Cloudflare account and an explicit go-ahead. This kit makes the
> deployment reviewable before that: exactly which files go where, with sizes and sha256, plus
> a dry-run check and a post-deploy smoke test.
>
> **Step-by-step guide: [DEPLOY-CLOUDFLARE.md](DEPLOY-CLOUDFLARE.md)** ("the lean4game way": scripts
> `upload-artifacts.sh`, `deploy-app.sh`, `rollback-artifacts.sh`, rehearsed end to end against local fakes).
> This page remains the reference for the manifest, its gates and the dry run.

The showcase deploys as **its own Worker on its own origin** (`qed64-showcase.<subdomain>.workers.dev`). It never
touches QED64's Worker. Since 2026-10-01 its R2 artifacts default to **the bucket QED64 already uses, under the prefix
`qed64-showcase/`**, the way lean4game uses `lean4game/` in the same bucket. The target is set in `infra/deploy.env`,
and a bucket of its own (`qed64-showcase-artifacts`, prefix `""`) is the documented alternative. The prefix keeps the
mutable index names apart, so QED64's objects are never overwritten and stay untouched in production. The layout
follows QED64's own production setup (`qed64/docs/DEPLOY.md`, `qed64/infra/worker.js`,
`qed64/wrangler.toml` @1859b83) and the lean4game precedent (`wasm64-lean4game/infra/worker.js`,
`wrangler.toml`):

| URL | Served from | Content |
|---|---|---|
| `/` (and `/assets/*`, `/infoview/*`, `/workers/*`) | Workers static assets | the **pinned** QED64 `dist/` (`release/<pin id>/dist`, where `<buildId>` is `QED64.lock.json`'s `qed64.buildId`), byte-identical to the lock |
| `/showcase/` | Workers static assets | `gallery/`, without `*.md` and the stage-A `x3.html` |
| `/runtime/…` | R2 | runtime manifests + the 10 `lean.js`/`lean.wasm` chunks of the lock's buildId |
| `/profiles/…` | R2 | the core pack (8 parts) and the mathlib-essential pack (61 parts) |
| `/snapshots/index.json`, `init…`, `mathlib…` | R2 | the stock pair, so the stock page still works at `/?…` |
| `/snapshots/widgets8/…`, `/snapshots/widgets7/…` | R2 | our overlays: `index.json` + `init` + `widgets.<d16>.snapz` |

The gallery iframes `/?snapshots=snapshots/widgets8` from the same origin. That `?snapshots=`
override is a dev-only knob in QED64's boot code (`frontend/src/qed64-boot.ts:96-106`). It ships
in the bundle **we pinned**, so a later upstream removal cannot affect this deployment. Only a
deliberate re-pin could change it (README "Re-pin").

## Files

| File | Role |
|---|---|
| `infra/worker.js` | The edge worker. It is QED64's `infra/worker.js`, with the same headers and the same `isImmutable` rule, plus three additions. **R2_PREFIX** puts the artifacts under a key prefix, for a shared bucket. **HEAD with an explicit `Content-Length`** from `ARTIFACTS.head()` is needed because the gallery's pairing preflight requires `content-length == transfer` (`gallery/lib.js`). **ROOT_REDIRECT** sends a bare `/` to the gallery. Added 2026-10-01 for lean4game parity: **single-range GETs** on artifacts (206 + `Content-Range`, `If-Range` against the etag, 416 past the end, multi-range ignored; ported from `wasm64-lean4game/infra/worker.js`), and a **Content-Length on HEAD for static assets**, which the assets binding omits (found in the `wrangler dev` rehearsal). |
| `infra/worker.test.mjs` | `node --test infra/worker.test.mjs` runs the worker against fake ASSETS/R2 bindings (no network, no account). It also checks that `isImmutable` agrees with the verbatim QED64 copy in `scripts/serve.mjs`. Since 2026-10-01 it has 22 tests: lean4game's range cases on a strict fake R2, and HEAD on assets. |
| `wrangler.toml.example` | The Worker config template. `scripts/deploy-app.sh` writes `./wrangler.toml` (gitignored) from it with the values of `infra/deploy.env`, or refuses an existing one that disagrees. |
| `scripts/deploy-manifest.mjs` | The upload manifest generator, the dry-run check, asset staging, the command printer and the smoke test. |
| `out/deploy/manifest.json` | Generated output: every asset and every R2 object with its local source, size, sha256, content type, cache class and upload phase. |
| `out/deploy/rclone/<group>.<immutable\|mutable>.files` | Generated output: one exact file list per upload group, which `rclone --files-from-raw` consumes. |
| `infra/deploy.env` | The deploy target in one place: `R2_REMOTE=qed64-r2`, `R2_BUCKET=qed64-artifacts`, `R2_PREFIX=qed64-showcase/`, `WORKER_NAME=qed64-showcase`. Environment variables of the same name override it, subject to the shared-bucket guard in `scripts/lib/deploy-env.mjs` (in `qed64-artifacts` only `qed64-showcase/`; an empty prefix or one inside `lean4game/`, `runtime/`, `profiles/`, `snapshots/` is always refused; another prefix needs `ALLOW_SHARED_PREFIX=1`). |
| `infra/package.json` | Pins wrangler 4.125.0 (as lean4game does), apart from the root `package.json`: `npm ci --prefix infra`, `npx --prefix infra wrangler …`. |
| `scripts/upload-artifacts.sh`, `scripts/deploy-app.sh`, `scripts/rollback-artifacts.sh` | The lean4game-style release scripts (guide: DEPLOY-CLOUDFLARE.md). `scripts/lib/deploy-common.sh` holds the shared target loading, the manifest gates and the release-record lookup; `scripts/lib/wrangler-config.mjs` writes and checks `wrangler.toml`. Every real upload or rollback leaves a release record in `out/deploy/published/` (back it up: `out/` is gitignored). |
| `scripts/stage-shell-from-tarball.mjs`, `.github/workflows/deploy-showcase.yml.example` | Optional CI (shell-only redeploys from a pinned dist tarball); manual deploys are recommended. |
| `scripts/deploy-rehearsal/` | The local rehearsal: `rehearse.sh` (steps), `offline.sb` (no outbound network), `fake-s3.mjs`, `load-r2.mjs` + `r2-loader-worker.js` (wrangler dev's local R2), `boot-check.mjs` (one browser boot). |

## Dry run (no account needed; all of this has been run)

```
scripts/showcase.sh gallery                       # the gallery's own static gate; prints the gallery content sha256
node scripts/deploy-manifest.mjs                  # generate + validate (+ G1 gallery gate) -> out/deploy/manifest.json
node scripts/deploy-manifest.mjs --check          # re-hash everything, byte-compare, re-validate (+ G1, G2)
node scripts/deploy-manifest.mjs --stage-assets   # cp -c every manifest asset into out/deploy/assets
node --test infra/worker.test.mjs                 # the worker against fake bindings
scripts/showcase.sh serve                         # or PORT=5191 scripts/showcase.sh serve
node scripts/deploy-manifest.mjs --smoke http://localhost:5190 --all
```

`node scripts/deploy-manifest.mjs --help` prints the usage. Arguments are strict (close-out 3): an unknown argument, a
value flag without its value, or two modes print the usage and exit 2 before anything is read or written (it used to
fall through to generate and rewrite `out/deploy`). Generate stays the default and may also be named (`generate`).

The last command checks the URL→file mapping against `scripts/serve.mjs`, which uses the same
routes and header rules as the worker.

Two gates tie the manifest to the gallery it packages (added after the audit found a green
manifest packaging a gallery whose own gate was red):

* **G1** (`generate` and `--check`): `scripts/check-gallery.mjs` must exit 0 (600 s watchdog). A
  red gallery therefore cannot get a green manifest or a green `--check`.
* **G2** (`generate` and `--check`, information only): is there a **verdict** UX run for exactly what
  this manifest packages? The runs are recorded in `out/ux/showcase-ux-runs.jsonl` by `scripts/showcase.sh ux`,
  and the rule is `scripts/lib/ux-record.mjs` `whyNotVerdict` (close-out of the docs audit r3, which found that a
  run could be recorded for a gallery it never tested). A run is a verdict only if it is the full suite (no
  args, no `UX_ORIGIN`), rc 0, its `report.json` has 0 unexpected, 0 flaky and `expected + skipped == listed`
  (`playwright test --list`; `forbidOnly` is on) with nothing skipped but C19, the local gallery hash is
  unchanged from start to end, and the server under test **served** exactly that gallery at the start and at
  the end (the same content hash over the bytes fetched from it). G2 then matches the run's gallery content
  sha256 (`scripts/lib/gallery-hash.mjs`: the shipped gallery files, i.e. exactly the `showcase/` assets:
  everything under `gallery/` except `*.md`, `x3.html` and dotfiles), its `QED64.lock.json` sha256 and its
  overlay index sha256s against `manifest.gallery`, `manifest.pin.lockSha256` and the uploaded
  `/snapshots/<overlay>/index.json`. It prints `G2 UX: verdict run <run> … was on THIS gallery …, lock … and
  overlays …` or `G2 UX: NO verdict 'showcase.sh ux' run for this gallery + lock + overlays`. "Publishing" step 2
  requires the first. G2 is not a FAIL because a run started directly with `npm run test:ux` leaves no record.
  **Since the final audit** G2 applies the same later-failure rule as `showcase.sh gallery`'s freshness line
  (`ux-record.mjs` `laterFailures`): when a full-suite run on the same gallery, lock and overlays came after the
  verdict run and was not a verdict, the line ends `; BUT n later full run(s) on the same inputs were NOT A VERDICT
  (<run>: <why>): not a clean bill of health, resolve before publishing`, and the release scripts' preflight
  (`scripts/lib/deploy-common.sh` `manifest_preflight`) refuses such a line just as it refuses a missing verdict
  (`ALLOW_NO_UX_VERDICT=1` overrides both, deliberately).

`generate` writes `manifest.json` and the rclone lists **only when every invariant is OK**.
On any FAIL it prints `DEPLOY-MANIFEST FAILED (n FAIL): nothing written` and leaves the previous
outputs byte-identical. Before this fix it wrote them unconditionally.

The counts below are a snapshot of one regenerate. The authoritative figures are always the
`totals` of `out/deploy/manifest.json` (printed by every `generate` and `--check` as
`info totals: …`), so this page does not have to change when the gallery does.

**Docs lane (2026-10-02 06:15 EDT), active pin C `5ac5d00` (`wasm64-4b025db7729c5f89`), gallery
`2f95d07c24cc76e0144f2697089ddab3dd0f3512558aae6aa30ba7bc9569b4df`:** `out/deploy` regenerated after the gallery polish:
`DEPLOY-MANIFEST OK 75 assets, 93 R2 objects; gallery 2f95d07c…`; `--check`: `OK   G1 … CHECK-GALLERY OK 123 ok, 0
failed`, `info G2 UX: verdict run docs-full1 (2026-10-02T10:11:55Z, lane docs) was on THIS gallery 2f95d07c24cc76e0…,
lock 6d2cbd20b8b6… and overlays widgets8, widgets7`, `DEPLOY-MANIFEST CHECK OK (dry run: nothing uploaded)`
(`$W/logs/docs-deploy-{generate,check}.log`). The local rehearsal (`rehearse.sh`) was last run on pin C with the previous
gallery `a4b34ead…` (docs/REPIN-LOG.md "Deploy kit on the active pin"); only gallery files changed since. The entries
below are earlier states (pin B, then called "the current pin").

**Close-out 3 (after the last audit, 2026-10-02 00:38 EDT), then-current pin B `wasm64-2c18773ecfba45bb`, gallery
`92027286640ca6ed5be5a083ba5ca8269224415ec70e7ebc574d83ae90a379fe`:** `out/deploy` regenerated for the changed gallery:
`DEPLOY-MANIFEST OK 75 assets, 93 R2 objects; gallery 92027286…`; `--check`: `OK   G1 … CHECK-GALLERY OK 123 ok, 0
failed`, `info G2 UX: NO verdict 'showcase.sh ux' run for this gallery 92027286640ca6ed… + lock + overlays (last
verdict: 2026-10-01T23:36:49Z on 7bbddf2e750c0fa2…)`, `DEPLOY-MANIFEST CHECK OK (dry run: nothing uploaded)`
(`$W/logs/closeout3-deploy-{generate,check}.log`). The only full UX run on this gallery, `closeout3-full1`, is red on L9
(C10), so publishing step 2 does not hold: do not deploy this pin as is.

**Close-out 2 (after the final audit, 2026-10-01 23:05–23:16 EDT), previous gallery, then-current pin B `wasm64-2c18773ecfba45bb`, gallery
`7772c1eb7000720216fd12f8dbca59b64a7abb5c4e4bc766847f77fc7346a047`:** `out/deploy` regenerated (it had still packaged
the previous pin; the final audit's `--check` failed C1 with 52 differing entries and C2 on five rclone lists). `generate`:
`DEPLOY-MANIFEST OK 75 assets, 93 R2 objects; gallery 7772c1eb…`. `--check`: `OK   G1 … CHECK-GALLERY OK 123 ok, 0
failed`, `info G2 UX: NO verdict 'showcase.sh ux' run for this gallery 7772c1eb70007202… + lock + overlays (last verdict:
2026-10-01T23:36:49Z on 7bbddf2e750c0fa2…)`, `DEPLOY-MANIFEST CHECK OK (dry run: nothing uploaded)`
(`$W/logs/closeout2-deploy-{generate,check}.log`). The only full UX run on this gallery, `closeout2-full1`, is red on L9
(C10), so publishing step 2 does not hold, and this pin should not be deployed as is. The later-failure note was checked
in a scratch clone with a fake green record followed by the real red one: `info G2 UX: verdict run SCRATCH-fake-green …
was on THIS gallery 7772c1eb70007202…, lock bb97785a4b24… and overlays widgets8, widgets7; BUT 1 later full run(s) on the
same inputs were NOT A VERDICT (closeout2-full1: rc 1, 2 unexpected, expected 29 + skipped 1 != listed 32): not a clean
bill of health, resolve before publishing`; the preflight's case statement refuses that line (and passes a plain verdict
line, and refuses a missing verdict) unless `ALLOW_NO_UX_VERDICT=1`.

Results recorded on 2026-10-01, last re-run at the close-out, 16:03–16:26 EDT, on gallery content sha256
`c8492b7078f49b564aa3455bb632c2c98b7ee5cd0d9052555c2cb1857f76b87d` (the liveness probe, the label and thumbnail
fixes). Logs are in `$W/logs/closeout-deploy-{generate,check,check-2,stage,smoke}.log`:

* `generate`: `DEPLOY-MANIFEST OK 75 assets, 93 R2 objects; gallery c8492b70…`, `info totals: 75 assets 17.6 MiB; 93 R2
  objects 2.420 GB`, `OK   G1 …`.
* `--check` after the close-out UX run: `OK   C1 … byte-identical`, `OK   G1 scripts/check-gallery.mjs exit 0 on gallery
  c8492b7078f49b56… (44 s): CHECK-GALLERY OK 122 ok, 0 failed`, `info G2 UX: verdict run closeout-full1
  (2026-10-01T20:24:08Z, lane closeout) was on THIS gallery c8492b7078f49b56…, lock ddf1a2340791… and overlays widgets8,
  widgets7`, `DEPLOY-MANIFEST CHECK OK (dry run: nothing uploaded)`. Publishing step 2 therefore holds on this gallery.
* `--stage-assets`: `S1 out/deploy/assets holds exactly the manifest's 75 assets`, `S2 every staged asset matches its manifest sha256`.
* `--smoke http://localhost:5190 --all` (the close-out lane's `showcase.sh serve`):
  `168 URLs (75 assets + 93/93 R2 keys) answer 200 …`, `SMOKE OK`.
* `node --test infra/worker.test.mjs`: tests 11, pass 11, fail 0.
* Earlier (13:21–13:23, gallery `2550fa1d…`): the same counts, with `G2 … NO green full-suite run`.
* Write-only-on-green, negative control, in an APFS-clone scratch copy with the widgets8 index's
  `mathlib.runtime` set to `wasm64-1111111111111111`: `FAIL R3 … mathlib.runtime wasm64-1111111111111111`,
  `DEPLOY-MANIFEST FAILED (2 FAIL): nothing written; …unchanged`. The sha256 over `manifest.json`
  plus the rclone lists was `b70af298…` both before and after. The second FAIL was G1: the gallery
  was red at 13:00.
* G1 negative, live: at 13:00 the real gallery was mid-edit (`BUILD-GALLERY STALE`; thumbnails
  `2/8 … recorded in examples.json`). generate gave `FAIL G1 … CHECK-GALLERY FAIL 116 ok, 3 failed`,
  wrote nothing, and left the 12:41 manifest in place.

History. The audit found that the 12:41 manifest below was "green" while `showcase.sh gallery` was
red from 12:34 to 13:14 (the gallery lane's edits). Nothing tied the manifest to the gallery gate,
so G1 and the gallery sha256 were added. Earlier record, 12:41 local, logs
`$W/logs/docs-fix-deploy-{generate2,check2,stage2,smoke3}.log`. The gallery lane was still editing:
`--check` on the 02:05 manifest failed with `FAIL C1 … 8 entries differ: asset
showcase/examples.json | … gallery.js | … thumbs/expr-xray.png | … favicon.svg` (the audit's run);
a regenerate at 12:13 was green, and `--check` on it failed again with `FAIL C1 regenerated
manifest … is byte-identical to the written manifest.json` after `gallery/{gallery.css,gallery.js}`
(12:34) and `gallery/{examples.json,pin.json}` (12:36) changed; the 12:41 regenerate was green on its
own invariants, but it packaged a gallery that failed its own gate (see above):

* `generate`: `DEPLOY-MANIFEST OK 74 assets, 93 R2 objects`. Every gate passed (A1–A5, L1, R1–R4), including:
  * A1: the largest asset is 8,269,331 B, under the 25 MiB cap;
  * L1: all 145 files taken from the release match `QED64.lock.json`;
  * R1: all 10 runtime chunks are present with their sha256;
  * R2: the core pack has 8 parts and the essential pack 61, all with digests;
  * R3: the stock index and both overlay indexes have `runtime ==` the lock's buildId (at that time the previous pin), `sha256 == digest` and `size == transfer`.
* Totals: `info totals: 74 assets 17.6 MiB; 93 R2 objects 2.420 GB`. Three objects are larger than 300 MiB and need a multipart upload: the stock `mathlib` snapz (307 MiB), `widgets7` (316 MiB) and `widgets8` (348 MiB).
* `--check`: `DEPLOY-MANIFEST CHECK OK (dry run: nothing uploaded)`. Earlier it correctly failed because the gallery had changed after the manifest was written: the audit saw `FAIL C1 … 10 entries differ: asset showcase/examples.json | asset showcase/gallery.js | asset showcase/thumbs/chart-kit.png …`, and this lane's later run saw `3 entries differ: asset showcase/gallery.css | asset showcase/gallery.js | asset showcase/index.html`. **Regenerate the manifest after any gallery change.** Two negative controls fail as they should: a tampered sha256 in `manifest.json` gives `FAIL C1 … 1 entries differ: r2 snapshots/widgets8/widgets.0880fd91b58098c0.snapz`, and an extra line in an rclone list gives `FAIL C2`.
* `--stage-assets`: `STAGE-ASSETS OK out/deploy/assets (17.6 MiB)`. S1 confirms the directory holds exactly the manifest's 74 files, and S2 confirms their sha256 (`OK   S2 every staged asset matches its manifest sha256`).
* `--smoke http://localhost:5190 --all`, against a running `serve.mjs` of this repo (another lane's; `showcase.sh serve` confirmed it is the showcase): `167 URLs (74 assets + 93/93 R2 keys) answer 200 with size, isolation, cache and content-type headers`. Against a foreign dev server (a Vite app on :5197) it gives `SMOKE FAILED`, and against a port whose server had just stopped (:5191) `SMOKE FAILED … 167 bad`. The smoke requires a JSON content type on every `*.json` (the pinned shell, `qed64-boot.ts:69`, and the gallery's preflight, `gallery/lib.js`, refuse a runtime manifest that is not JSON), `javascript` on `.js`, `text/css` on `.css`, `text/html` on pages, and a type that is neither HTML nor JSON on `.snapz`, `.part-N`, `.wasm` and `.gz`. Negative controls through a header-rewriting proxy: runtime manifests served as `text/plain` give `FAIL HEAD /runtime/runtime-manifest.json — content-type text/plain (want a JSON type)` and `SMOKE FAILED`; `.snapz` served as `text/html` gives `FAIL HEAD /snapshots/init.35c8c5f5419e0c33.snapz — content-type text/html; charset=utf-8 (binary artifact must not be HTML/JSON)`. With no server running the smoke gives `SMOKE FAILED`, as it should.
* `node --test infra/worker.test.mjs`: 11/11 pass (re-run 12:13, `$W/logs/docs-fix-worker-test.log`). All 13 worker mutants are killed (log `$W/logs/docs-lane-worker-mutants.log`):
  * dropping `writeHttpMetadata` (the R2 Content-Type) on GET → 2 fail; on HEAD → 2 fail;
  * removing `/profiles/` or `/runtime/` from the R2 routes → 2 fail each; removing `/snapshots/` → 6 fail;
  * dropping CORP or COEP → 8 fail each;
  * dropping the HEAD or the GET `Content-Length` → 1 fail each;
  * making indexes immutable, redirecting `/` even with a query, skipping the traversal check, or ignoring `R2_PREFIX` → 1 fail each.

### Smaller variants

```
node scripts/deploy-manifest.mjs --overlays widgets8 --no-stock-snapshots --no-essential-pack
```

This variant needs 26 objects and 0.688 GB in R2 (measured, with `--check` green). It gives up
two things:

* The bare stock page cannot boot without the stock snapshots. Keep `ROOT_REDIRECT`.
* QED64's on-demand "Load exact imports" needs the essential pack (1 GB), so that action fails.

The gallery only ever uses an overlay, so it is unaffected. `--prefix <p>/` puts every key under
a prefix of a shared bucket. Set the same value as `R2_PREFIX` in `wrangler.toml`.

## Publishing (owner only, after an explicit go-ahead)

**Use [DEPLOY-CLOUDFLARE.md](DEPLOY-CLOUDFLARE.md).** It is the numbered, copy-pasteable procedure, in this order:

```
DRY_RUN=1 scripts/upload-artifacts.sh       # [account] read-only listing of the bucket
scripts/upload-artifacts.sh                 # [account] artifacts first (copy only, phased, typed)
scripts/deploy-app.sh                       # [account] then the shell (npx --prefix infra wrangler deploy)
node scripts/deploy-manifest.mjs --smoke https://qed64-showcase.<subdomain>.workers.dev --all --range
```

The default target is the shared bucket `qed64-artifacts` under the prefix `qed64-showcase/`, through the existing
rclone remote `qed64-r2` (`infra/deploy.env`). The scripts refuse an empty or foreign prefix in that bucket (QED64's
root, `lean4game/`), refuse without a verdict UX run on this gallery (G2), and `deploy-app.sh` refuses a shell whose R2
keys are not what the newest upload published (release record). wrangler is pinned at 4.125.0 in `infra/` and always
runs as `npx --prefix infra wrangler …`; a bare `npx wrangler` in the repo root would fetch an unpinned wrangler,
because the root `node_modules` holds only Playwright.

`node scripts/deploy-manifest.mjs --commands` prints the equivalent raw `rclone copy` / wrangler lines for the current
manifest without running them (and refuses to print commands that would write into another app's namespace). The
preconditions are the same in both paths, on one gallery revision (`node scripts/lib/gallery-hash.mjs`), with no
edit to `gallery/` in between:

* `scripts/showcase.sh gallery` ends with `gallery gate GREEN on gallery content sha256 <h>`;
* a full UX suite run on that gallery is a verdict: `scripts/showcase.sh ux` (about 20 min, browser lock) ends with
  `… recorded in out/ux/showcase-ux-runs.jsonl): VERDICT`, after which `scripts/showcase.sh gallery` prints
  `UX CURRENT`;
* `node scripts/deploy-manifest.mjs --prefix qed64-showcase/`, then `--check`: `DEPLOY-MANIFEST CHECK OK … gallery <h>`
  with `OK   G1` and `info G2 UX: verdict run … was on THIS gallery …, lock … and overlays …`.

The rules the scripts implement, for review: `rclone copy`, never `sync` (older digest-named files must stay available
to clients mid-session, QED64's rule); digest-named objects first, then manifests, then `index.json`; multipart for the
three `.snapz` over 300 MiB (wrangler's `r2 object put` caps a single object at about 300 MiB); an explicit
`Content-Type` per list, `application/json` for `*.json` (the pinned shell accepts `runtime-manifest.<buildId>.json`
only with a JSON type, `qed64-boot.ts:67-70`) and `application/octet-stream` for `.snapz` / `.part-N` (the gallery's
preflight refuses HTML); the smoke then checks every URL for status 200, `content-length == size`, COOP/COEP/CORP, the
QED64 cache rule, a JSON type on JSON and no `Content-Encoding` on artifacts (QED64's worker refuses transformed runtime
chunks, `public/workers/lean.worker.js:594-596`, and the gallery refuses content-encoded snapz). Then open `/showcase/`;
the gallery runs its own pairing preflight before it navigates.

## Consistency rules (carried over from QED64)

* **Snapshots are binary-paired to the runtime.** Never upload a runtime without its snapshots,
  or the reverse. The R3 gate requires `runtime == buildId` on every index entry, and the shell
  is pinned to the lock's buildId (`node -p 'require("./QED64.lock.json").qed64.buildId'`).
* **Digest-named files are immutable** (`max-age=31536000, immutable`). Every `index.json` and
  `runtime-manifest*.json` revalidates (`max-age=0, must-revalidate`). This is QED64's
  `isImmutable` verbatim, and `infra/worker.test.mjs` checks it against the copy in
  `scripts/serve.mjs`.
* **The manifest is a snapshot of one gallery revision.** Regenerate it right before publishing,
  and after any change to `gallery/`, the overlays or the pin. `--check` catches drift: C1 compares the
  re-hashed files and `manifest.gallery.contentSha256`, and G1 re-runs the gallery gate. At 01:40 on 2026-10-01 it failed
  with `FAIL C1 … 6 entries differ: asset showcase/examples.json | … gallery.js | …` after the
  gallery lane edited those files, and a regenerate brought it back to green.
* **After a re-pin**, regenerate the manifest, then rerun `--check` and the smoke test. A new
  buildId means new chunk names. The old ones can stay in the bucket, because clients pinned to
  the previous shell still need them.

## Costs and limits (from QED64's DEPLOY.md, not re-measured)

R2's free tier has 10 GB of storage and zero egress fees. The full set here is 2.42 GB; the
smallest variant is 0.69 GB.

A first visit to the gallery downloads about 0.4 GB of snapshots (`widgets8` 364.7 MB transfer
plus `init` 32.6 MB), plus the runtime and the core pack. After that, OPFS caching applies:
stage-A X2 measured 0 snapz bytes on a warm revisit.

Workers static assets cap each file at 25 MiB (gate A1). They also cap the file count per
version. A5 checks against 20,000, the limit at the time of writing; confirm the current number
in Cloudflare's documentation before publishing.
