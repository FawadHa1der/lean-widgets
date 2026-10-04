/* qed64-showcase edge worker: the widget gallery + the PINNED QED64 page, on the showcase's OWN
 * origin. Same shape as QED64's infra/worker.js (whose cache rule it IMPORTS: ../deps/qed64/infra/worker.js, the
 * submodule at the served pin; wrangler bundles it) and the lean4game precedent:
 *
 *   static assets (Workers assets, binding ASSETS; each file ≤ 25 MiB)
 *     /                  the pinned QED64 dist (release/<buildId>/dist), unmodified
 *     /showcase/         gallery/ (index.html, gallery.js, lib.js, qed64-bridge.js, examples.json, pin.json …)
 *   R2 (binding ARTIFACTS), key = R2_PREFIX + path without the leading slash
 *     /runtime/          runtime manifests + lean.wasm/lean.js chunks of the pinned buildId
 *     /profiles/         core + mathlib-essential packs
 *     /snapshots/        the stock pair (index.json, init, mathlib) and our overlays
 *     /snapshots/widgets8/, /snapshots/widgets7/   overlay index.json + init + widgets.<d16>.snapz
 *
 * One origin, so COEP needs no CORS: cross-origin isolation headers go on every response (without
 * COOP/COEP the browser refuses SharedArrayBuffer/Memory64 and QED64 cannot start). Caching mirrors
 * QED64 exactly: digest/size-named files are immutable, every index and manifest revalidates.
 *
 * Differences from QED64's worker, each needed by the showcase:
 *   - R2_PREFIX (wrangler [vars]) lets the artifacts live under a prefix of a shared bucket
 *     (lean4game uses "lean4game/"); the default "" means a bucket of our own.
 *   - HEAD on an artifact is answered from ARTIFACTS.head() with an explicit Content-Length: the
 *     gallery's pairing preflight HEADs every overlay .snapz and requires content-length == the
 *     index's transfer size (gallery/lib.js preflightOverlay).
 *   - ROOT_REDIRECT (wrangler [vars], default unset): when set, a bare "/" (no query) redirects there
 *     (e.g. "/showcase/"). The gallery always iframes "/?snapshots=snapshots/<overlay>", which has a
 *     query and is never redirected.
 *   - Single-range GETs on artifacts (ported from wasm64-lean4game/infra/worker.js, 2026-10-01): every
 *     artifact response carries Accept-Ranges: bytes; one "bytes=a-b" / "a-" / "-n" range is answered
 *     206 with Content-Range and the partial Content-Length; If-Range is compared with the object's
 *     etag (a mismatch, a weak etag or a date gets the full 200); a range past the end gets 416 with
 *     the unsatisfied-range Content-Range (asterisk, slash, size) and no-store; multi-range or
 *     malformed headers are ignored (full 200). This lets the browser resume a .snapz download cut by a reload
 *     from its HTTP cache instead of pulling 300+ MB again. HEAD ignores Range.
 * Artifacts are never served with a Content-Encoding of our making: QED64's worker refuses runtime
 * chunks that were transformed (public/workers/lean.worker.js:594-596).
 */

// QED64's cache rule, imported (not copied) from the served pin's QED64 sources: every manifest and index revalidates,
// INCLUDING the per-build runtime-manifest.wasm64-<16hex>.json; digest- or size-named files never change under the same
// name. Re-exported for infra/worker.test.mjs.
import { isImmutable } from "../deps/qed64/infra/worker.js";
export { isImmutable };

const ARTIFACT_PREFIXES = ["/runtime/", "/profiles/", "/snapshots/"];

function withHeaders(response, pathname) {
  const headers = new Headers(response.headers);
  headers.set("Cross-Origin-Opener-Policy", "same-origin");
  headers.set("Cross-Origin-Embedder-Policy", "require-corp");
  headers.set("Cross-Origin-Resource-Policy", "same-origin");
  headers.set(
    "Cache-Control",
    isImmutable(pathname) ? "public, max-age=31536000, immutable" : "public, max-age=0, must-revalidate",
  );
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

/** R2 key for an artifact path: R2_PREFIX + path without the leading slash. Refuses traversal. */
export function artifactKey(pathname, prefix = "") {
  const rel = pathname.slice(1);
  if (rel.split("/").some((s) => s === ".." || s === "." || s === "")) return null;
  return prefix + rel;
}

/** A `Range` header this worker serves: exactly one `bytes` range (RFC 9110 §14.1.2). Anything else
 * (another unit, several ranges, a malformed or inverted spec) returns null and the request is answered
 * as if it carried no Range (a full 200, which the RFC allows), so R2 only ever sees a header this worker
 * has understood. Verbatim from wasm64-lean4game/infra/worker.js. */
export function parseRange(header) {
  if (header === null || header === undefined) return null;
  // Canonical spelling only (what browsers send), positions within the safe integers: the raw header
  // goes to R2, whose parser is not ours to guess.
  const match = /^bytes=(\d{0,15})-(\d{0,15})$/.exec(header.trim());
  if (match === null) return null;
  const [, first, last] = match;
  if (first === "") return last === "" ? null : { suffix: Number(last) };
  if (last === "") return { first: Number(first) };
  return Number(last) < Number(first) ? null : { first: Number(first), last: Number(last) };
}

/** `{offset, length}` of a parsed range within an object of `size` bytes, or null when no byte of the
 * object is selected (-> 416). */
export function resolveRange(spec, size) {
  if (spec.suffix !== undefined) {
    const length = Math.min(spec.suffix, size);
    return length > 0 ? { offset: size - length, length } : null;
  }
  if (spec.first >= size) return null;
  const end = spec.last === undefined ? size - 1 : Math.min(spec.last, size - 1);
  return { offset: spec.first, length: end - spec.first + 1 };
}

/** The range R2 reports having returned. The binding types it as any of `{offset, length?}`,
 * `{offset?, length}` or `{suffix}`; normalise all three to `{offset, length}`. */
function returnedRange(range, size) {
  if (range.suffix !== undefined) {
    const length = Math.min(range.suffix, size);
    return { offset: size - length, length };
  }
  const offset = range.offset ?? 0;
  return { offset, length: range.length ?? size - offset };
}

async function serveArtifact(request, env, pathname) {
  const key = artifactKey(pathname, env.R2_PREFIX ?? "");
  if (key === null) return withHeaders(new Response("not found", { status: 404 }), pathname);
  if (request.method !== "GET" && request.method !== "HEAD") {
    return withHeaders(new Response("method not allowed", { status: 405, headers: { allow: "GET, HEAD" } }), pathname);
  }
  // Range is defined for GET only (HEAD ignores it and answers from head()).
  let spec = request.method === "GET" ? parseRange(request.headers.get("range")) : null;
  if (spec !== null) {
    // Validators and size first: whether the range applies (If-Range) and whether it is satisfiable
    // are decided here, not inferred from how R2 reacts to a range it cannot serve.
    const meta = await env.ARTIFACTS.head(key);
    if (meta === null) return withHeaders(new Response("not found", { status: 404 }), pathname);
    const ifRange = request.headers.get("if-range");
    if (ifRange !== null && ifRange.trim() !== meta.httpEtag) {
      // The client's partial copy is of another version (or the validator is a date or a weak etag,
      // which can never strongly match): full 200.
      spec = null;
    } else if (resolveRange(spec, meta.size) === null) {
      const headers = new Headers();
      headers.set("accept-ranges", "bytes");
      headers.set("content-range", `bytes */${meta.size}`);
      const response = withHeaders(new Response("range not satisfiable", { status: 416, headers }), pathname);
      response.headers.set("Cache-Control", "no-store");
      return response;
    }
  }
  if (request.method === "HEAD") {
    const meta = await env.ARTIFACTS.head(key);
    if (meta === null) return withHeaders(new Response(null, { status: 404 }), pathname);
    const headers = new Headers();
    meta.writeHttpMetadata(headers);
    headers.set("etag", meta.httpEtag);
    headers.set("accept-ranges", "bytes");
    headers.set("content-length", String(meta.size));
    return withHeaders(new Response(null, { headers }), pathname);
  }
  const object = await env.ARTIFACTS.get(key, spec !== null ? { range: request.headers } : undefined);
  if (object === null) return withHeaders(new Response("not found", { status: 404 }), pathname);
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("accept-ranges", "bytes");
  if (spec !== null && object.range !== undefined && object.range !== null) {
    const { offset, length } = returnedRange(object.range, object.size);
    headers.set("content-range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
    headers.set("content-length", String(length));
    return withHeaders(new Response(object.body, { status: 206, headers }), pathname);
  }
  headers.set("content-length", String(object.size));
  return withHeaders(new Response(object.body, { headers }), pathname);
}

/** Static assets. GET passes straight through. The assets binding answers HEAD with a null body and NO
 * Content-Length (the asset-worker sets the length from the GET body stream only; seen under wrangler dev 4.125.0
 * in the 2026-10-01 rehearsal), so a HEAD here also fetches the same asset with GET, takes its length and cancels
 * the body: HEAD then carries the same headers as GET (RFC 9110 §9.3.2), which `deploy-manifest.mjs --smoke`
 * checks (content-length == size). Only HEADs pay for this; browsers GET assets. */
async function serveAsset(request, env) {
  const response = await env.ASSETS.fetch(request);
  if (request.method !== "HEAD" || response.status !== 200 || response.headers.has("content-length")) return response;
  const get = await env.ASSETS.fetch(new Request(request.url, { method: "GET", headers: request.headers }));
  let length = get.headers.get("content-length");
  if (length === null && get.body) {
    let n = 0;
    const reader = get.body.getReader();
    for (;;) { const { done, value } = await reader.read(); if (done) break; n += value.byteLength; }
    length = String(n);
  } else if (get.body) await get.body.cancel();
  if (get.status !== 200 || length === null) return response;
  const headers = new Headers(response.headers);
  headers.set("content-length", length);
  return new Response(null, { status: response.status, statusText: response.statusText, headers });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (ARTIFACT_PREFIXES.some((p) => url.pathname.startsWith(p))) {
      return serveArtifact(request, env, url.pathname);
    }
    if (env.ROOT_REDIRECT && url.pathname === "/" && url.search === "") {
      return withHeaders(Response.redirect(new URL(env.ROOT_REDIRECT, url).toString(), 302), url.pathname);
    }
    const asset = await serveAsset(request, env);
    return withHeaders(asset, url.pathname);
  },
};
