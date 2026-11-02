// release-routing.mjs — which R2 key QED64's createWorker reads a URL path from, under the routes releaseRoutes() gives for
// a toolchain record (deps/qed64/infra/edge-worker.js keeps its own function private). null: a site path, R2_PREFIX + path.
// Used by scripts/deploy-manifest.mjs; infra/worker.test.mjs runs the real Worker over every file of the active pin's
// lock against it.
export function releaseKey(routes, urlPath) {
  if (routes.siteOwned.some((p) => (p.endsWith('/') ? urlPath.startsWith(p) : urlPath === p))) return null;
  for (const [url, dir] of routes.mount) if (urlPath.startsWith(url)) return routes.prefix + dir + urlPath.slice(url.length);
  return null;
}
