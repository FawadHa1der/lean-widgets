// dist-assets.mjs — which files of a pinned release's dist/ become Workers static assets, and check A2's rule over the
// asset paths. Used by scripts/deploy-manifest.mjs (build, validate); tested over a fake dist by scripts/pin-qed64.test.mjs
// (the script itself reads the active pin's release and cannot take one).
//
// D2 (QED64 14562fa on): QED64's build copies public/profiles/index.json and public/snapshots/index.json into dist/
// (its frontend/vite.config.ts, build only), and its docs/EMBEDDING.md lets an embedder that routes /profiles/ and
// /snapshots/ to its own store drop them. infra/worker.js sends those paths to R2 first, so the copies would never be
// served; kept as assets, A2 refuses them and with it every upload and deploy. So exactly those two paths, relative to
// dist/, are not assets. Anything else under runtime/, profiles/ or snapshots/ stays an asset and A2 names it; a file of
// the same name deeper down (assets/snapshots/index.json) stays an asset and is not A2's business. pin-qed64.mjs
// verify #10 holds each dist copy byte-equal to public/. O 521cf3f and N 58ebbad ship neither file: a no-op there.
import path from 'node:path';

/** The dist/ paths (relative, '/'-separated) that are not assets. */
export const DIST_NOT_ASSETS = Object.freeze(['profiles/index.json', 'snapshots/index.json']);

/** A dist/ file path relative to dist/ ('/'-separated, as in the asset path). */
const relOf = (dist, f) => path.relative(dist, f).split(path.sep).join('/');

/** The asset files of `dist`: [[absolute file, asset path]] for each of `files` (absolute paths under `dist`, e.g. a walk
 *  of it), in their order, without the DIST_NOT_ASSETS paths. Compared on the path relative to dist, never on `f`. */
export function distAssetFiles(dist, files) {
  return files.map((f) => [f, relOf(dist, f)]).filter(([, r]) => !DIST_NOT_ASSETS.includes(r));
}

/** Check A2: the asset paths under runtime/, profiles/ or snapshots/ (the Worker routes those to R2, so an asset there
 *  is never served). [] passes. */
export const a2Shadowed = (assetPaths) => assetPaths.filter((p) => /^(runtime|profiles|snapshots)\//.test(p));
