// r2-loader-worker.js — rehearsal only (scripts/deploy-rehearsal/load-r2.mjs runs it under `wrangler dev --local`).
// PUT /<key> streams the request body (known Content-Length) into the LOCAL R2 binding with the given Content-Type
// and sha256 (R2 verifies it); GET /<key> reports the stored size and Content-Type. Never deployed anywhere.
export default {
  async fetch(request, env) {
    const key = decodeURIComponent(new URL(request.url).pathname.slice(1));
    if (request.method === "PUT") {
      const o = await env.ARTIFACTS.put(key, request.body, {
        httpMetadata: { contentType: request.headers.get("x-content-type") },
        sha256: request.headers.get("x-sha256"),
      });
      return Response.json({ size: o.size });
    }
    const h = await env.ARTIFACTS.head(key);
    return Response.json(h ? { size: h.size, contentType: h.httpMetadata && h.httpMetadata.contentType } : null);
  },
};
