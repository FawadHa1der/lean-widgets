/* qed64-showcase edge worker: the widget gallery + the PINNED QED64 page, on the showcase's OWN origin. QED64's library
 * Worker (createWorker, ../deps/qed64/infra/edge-worker.js: the submodule at the served pin; wrangler bundles it) with
 * the pin's toolchain release:
 *
 *   static assets (Workers assets, binding ASSETS; each file ≤ 25 MiB)
 *     /                  the pinned QED64 dist (release/<buildId>/dist), unmodified
 *     /showcase/         gallery/ (index.html, gallery.js, lib.js, qed64-bridge.js, examples.json, pin.json …)
 *   R2 (binding ARTIFACTS)
 *     /runtime/*, /profiles/*   lean4-wasm64/<release id>/{runtime,profiles}/…: the kernel's published release, read in
 *                               place and never copied (hosting.mount in the record); errors there are never cached
 *     /profiles/index.json      R2_PREFIX + path: ours (hosting.siteOwned)
 *     /snapshots/*              R2_PREFIX + path: ours: the stock pair and our overlays /snapshots/<dir>/, with <dir> =
 *                               scripts/lib/pins.mjs overlayDir (no alias here: the gallery maps ?overlay=widgets8 to
 *                               the pin's directory)
 *
 * Which release is the pin's own record, so `wrangler rollback` restores the routing with the shell. Pins before 385a1ac
 * have no release routing (createWorker's `release` is 391a075): they are not deployed from this Worker, and a rollback
 * to one is `wrangler rollback` to its Worker version (docs/DEPLOY-CLOUDFLARE.md section 5).
 *
 * The rest is createWorker's hardened defaults, which came from this Worker and lean4game's: isolation headers on every
 * response, QED64's cache rule (isImmutable), HEAD from R2 metadata and asset HEAD with an explicit Content-Length (the
 * gallery's pairing preflight needs content-length == transfer; deploy-manifest --smoke too), single-range GETs, 405,
 * traversal refused, never a Content-Encoding of our making.
 *
 * From wrangler [vars]: R2_PREFIX (the showcase's prefix of the shared bucket; "" means a bucket of our own, which must
 * then hold the release too) and ROOT_REDIRECT (when set, a bare "/" without a query redirects there; the gallery's
 * iframe URL "/?snapshots=snapshots/<dir>" has a query and is never redirected).
 */
import { createWorker } from "../deps/qed64/infra/edge-worker.js";
import release from "../deps/qed64/toolchain/lean4-wasm64-release.json" with { type: "json" };

export default createWorker({
  r2Prefix: (env) => env.R2_PREFIX ?? "",
  rootRedirect: (env) => env.ROOT_REDIRECT ?? null,
  release,
});
