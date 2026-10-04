/* infra/worker.js against fake ASSETS / R2 bindings: `node --test infra/worker.test.mjs`.
 * Pattern from the lean4game precedent (wasm64-lean4game/infra/worker.test.mjs). No network, no account.
 *
 * Covers: COOP/COEP/CORP on every response; the cache rule IS QED64's isImmutable (imported from the submodule
 * deps/qed64/infra/worker.js; serve.mjs, deploy-manifest.mjs and worker.js keep no copy of its regexes);
 * artifact routing with and without R2_PREFIX; HEAD with an explicit Content-Length (the gallery's
 * preflight needs content-length == transfer); 404 for missing objects (never a fallback page);
 * path traversal refused; non-GET/HEAD refused on artifacts; assets pass through; ROOT_REDIRECT
 * only for a bare "/" without a query (the gallery's iframe URL "/?snapshots=…" is never redirected);
 * the R2 object's Content-Type is passed through on GET and HEAD (qed64-boot.ts:69 and gallery/lib.js
 * refuse a runtime manifest whose type is not JSON); each of /runtime/, /profiles/, /snapshots/ is
 * routed to R2 and never to ASSETS; single-range GETs (206 / If-Range / 416 / multi-range ignored), ported
 * with their tests from wasm64-lean4game/infra/worker.js.
 */
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import worker, { isImmutable, artifactKey, parseRange, resolveRange } from "./worker.js";

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ORIGIN = "https://showcase.example";
const SNAPZ = "/snapshots/widgets8/widgets.0880fd91b58098c0.snapz";
// the active pin's runtime manifest name and main bundle (scripts/lib/pins.mjs): routing fixtures only, any pin will do
const PINS = await import(path.join(SC, "scripts/lib/pins.mjs"));
const RTM = `runtime/runtime-manifest.${PINS.activeBuildId()}.json`;
const MAIN_BUNDLE = PINS.mainBundle();
const BYTES = Uint8Array.from({ length: 1000 }, (_, i) => (i * 7 + 3) % 256);

function fakeBucket(objects) {
  const calls = [];
  const meta = (key, e) => ({
    key, size: e.bytes.length, httpEtag: `"etag-${key}"`,
    writeHttpMetadata(h) { h.set("content-type", e.contentType ?? "application/octet-stream"); },
  });
  return {
    calls,
    async head(key) { calls.push({ op: "head", key }); const e = objects[key]; return e ? meta(key, e) : null; },
    // Range semantics as in wasm64-lean4game/infra/worker.test.mjs: get(key, {range: Headers}) returns the
    // selected bytes plus `range: {offset, length}`, and is STRICTER than R2 where the worker must not lean
    // on it (an unsatisfiable or unparsable range throws), so a test passes only if the worker settled
    // 416 / full-200 itself. The call is logged with `range` only when the worker asked for one.
    async get(key, options) {
      const rangeHeader = options?.range instanceof Headers ? options.range.get("range") : null;
      calls.push(options?.range !== undefined ? { op: "get", key, range: rangeHeader } : { op: "get", key });
      const e = objects[key];
      if (!e) return null;
      const size = e.bytes.length; let offset = 0; let length = size;
      if (options?.range !== undefined) {
        assert.ok(options.range instanceof Headers, "the worker passes the request's Headers as the range");
        const m = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader ?? "");
        if (m === null || (m[1] === "" && m[2] === "")) throw new Error("get: invalid range (fake R2)");
        if (m[1] === "") { length = Math.min(Number(m[2]), size); offset = size - length; }
        else { offset = Number(m[1]); const end = m[2] === "" ? size - 1 : Math.min(Number(m[2]), size - 1); length = end - offset + 1; }
        if (length <= 0 || offset >= size) throw new Error("get: The requested range is not satisfiable (10039)");
      }
      return { ...meta(key, e), range: { offset, length }, body: new Blob([e.bytes.slice(offset, offset + length)]).stream() };
    },
  };
}
function fakeAssets(files) {
  const calls = [];
  return {
    calls,
    async fetch(request) {
      const p = new URL(request.url).pathname; calls.push(p);
      const f = files[p.endsWith("/") ? p + "index.html" : p];
      if (f === undefined) return new Response("asset not found", { status: 404 });
      // like the real asset-worker: HEAD has a null body and no Content-Length
      return new Response(request.method === "HEAD" ? null : f, { headers: { "content-type": "text/html" } });
    },
  };
}
const env = (o = {}) => ({
  ARTIFACTS: fakeBucket({
    "snapshots/widgets8/index.json": { bytes: new TextEncoder().encode("{}"), contentType: "application/json" },
    "snapshots/widgets8/widgets.0880fd91b58098c0.snapz": { bytes: BYTES },
    "showcase-v1/snapshots/widgets8/widgets.0880fd91b58098c0.snapz": { bytes: BYTES },
    [RTM]: { bytes: new TextEncoder().encode("{}"), contentType: "application/json" },
    "profiles/index.json": { bytes: new TextEncoder().encode("{}"), contentType: "application/json" },
    "profiles/lean-core.pack.gzip.1016929d99bb0ba0e148.part-007": { bytes: BYTES },
  }),
  ASSETS: fakeAssets({ "/index.html": "<!doctype html>qed64", "/showcase/index.html": "<!doctype html>gallery" }),
  ...o,
});
const req = (p, init) => new Request(ORIGIN + p, init);
const isolation = (r) => {
  assert.equal(r.headers.get("cross-origin-opener-policy"), "same-origin");
  assert.equal(r.headers.get("cross-origin-embedder-policy"), "require-corp");
  assert.equal(r.headers.get("cross-origin-resource-policy"), "same-origin");
};

test("isImmutable IS QED64's rule (imported from the submodule's infra/worker.js, not a copy)", async () => {
  const { isImmutable: qed64 } = await import(new URL("../deps/qed64/infra/worker.js", import.meta.url).href);
  assert.equal(isImmutable, qed64, "infra/worker.js re-exports QED64's function object");
  for (const f of ["scripts/serve.mjs", "scripts/deploy-manifest.mjs", "infra/worker.js"])
    assert.ok(!fs.readFileSync(path.join(SC, f), "utf8").includes("\\.chunk\\.|[0-9a-f]{16,}"), `${f} has no local copy of QED64's rule`);
  const paths = ["/snapshots/index.json", "/snapshots/widgets8/index.json", SNAPZ, "/runtime/runtime-manifest.json",
    "/" + RTM, "/runtime/chunks/lean.wasm.0123456789abcdef0123.part-003",
    "/profiles/index.json", "/profiles/lean-core.manifest.json", "/profiles/lean-core.pack.gzip.1016929d99bb0ba0e148.part-007",
    MAIN_BUNDLE, "/showcase/gallery.js", "/showcase/examples.json", "/", "/index.html", "/infoview/webview.js"];
  for (const p of paths) assert.equal(isImmutable(p), qed64(p), p);
  assert.equal(isImmutable(SNAPZ), true);
  assert.equal(isImmutable("/snapshots/widgets8/index.json"), false);
  // an index under a digest-named directory must still revalidate (the index rule wins)
  assert.equal(isImmutable("/snapshots/bake-0880fd91b58098c0/index.json"), false);
});

test("artifact GET: R2 key without prefix, isolation + immutable + content-length", async () => {
  const e = env();
  const r = await worker.fetch(req(SNAPZ), e);
  assert.equal(r.status, 200); isolation(r);
  assert.equal(r.headers.get("cache-control"), "public, max-age=31536000, immutable");
  assert.equal(r.headers.get("content-length"), String(BYTES.length));
  assert.equal(r.headers.get("content-encoding"), null);
  assert.equal(r.headers.get("content-type"), "application/octet-stream", "R2 http metadata passed through on GET");
  assert.deepEqual(new Uint8Array(await r.arrayBuffer()), BYTES);
  assert.deepEqual(e.ARTIFACTS.calls, [{ op: "get", key: SNAPZ.slice(1) }]);
});

test("artifact HEAD: answered from head() with Content-Length == size (gallery preflight)", async () => {
  const e = env();
  const r = await worker.fetch(req(SNAPZ, { method: "HEAD" }), e);
  assert.equal(r.status, 200); isolation(r);
  assert.equal(r.headers.get("content-length"), String(BYTES.length));
  assert.equal(r.headers.get("content-type"), "application/octet-stream");
  assert.deepEqual(e.ARTIFACTS.calls, [{ op: "head", key: SNAPZ.slice(1) }]);
});

test("R2_PREFIX is prepended to the key", async () => {
  const e = env({ R2_PREFIX: "showcase-v1/" });
  const r = await worker.fetch(req(SNAPZ), e);
  assert.equal(r.status, 200);
  assert.deepEqual(e.ARTIFACTS.calls, [{ op: "get", key: "showcase-v1/" + SNAPZ.slice(1) }]);
});

test("indexes and manifests revalidate and keep their JSON content-type (GET and HEAD)", async () => {
  for (const p of ["/snapshots/widgets8/index.json", "/" + RTM, "/profiles/index.json"]) {
    for (const method of ["GET", "HEAD"]) {
      const r = await worker.fetch(req(p, { method }), env());
      assert.equal(r.status, 200, `${method} ${p}`); isolation(r);
      assert.equal(r.headers.get("cache-control"), "public, max-age=0, must-revalidate", `${method} ${p}`);
      assert.equal(r.headers.get("content-type"), "application/json", `${method} ${p}`);
    }
  }
});

test("every artifact prefix (/runtime/, /profiles/, /snapshots/) is routed to R2, never to ASSETS", async () => {
  for (const p of ["/" + RTM, "/profiles/lean-core.pack.gzip.1016929d99bb0ba0e148.part-007", SNAPZ]) {
    const e = env();
    const r = await worker.fetch(req(p), e);
    assert.equal(r.status, 200, p);
    assert.deepEqual(e.ARTIFACTS.calls, [{ op: "get", key: p.slice(1) }], p);
    assert.deepEqual(e.ASSETS.calls, [], p);
  }
  const e = env();   // a missing object under a prefix is an R2 404, not an asset lookup
  assert.equal((await worker.fetch(req("/profiles/missing.json"), e)).status, 404);
  assert.deepEqual(e.ASSETS.calls, []);
});

test("missing artifact: 404 with isolation headers, never a fallback page", async () => {
  for (const method of ["GET", "HEAD"]) {
    const r = await worker.fetch(req("/snapshots/nope/index.json", { method }), env());
    assert.equal(r.status, 404, method); isolation(r);
  }
});

test("path traversal and empty segments are refused without touching R2", async () => {
  for (const p of ["/snapshots/../runtime/x", "/snapshots//x", "/snapshots/./x"]) assert.equal(artifactKey(p), null, p);
  assert.equal(artifactKey("/snapshots/widgets8/index.json", "p/"), "p/snapshots/widgets8/index.json");
  const e = env();   // URL parsing already folds "..", so the reachable case is an empty segment
  const r = await worker.fetch(req("/snapshots//widgets8/index.json"), e);
  assert.equal(r.status, 404); isolation(r);
  assert.deepEqual(e.ARTIFACTS.calls, []);
});

test("non-GET/HEAD on artifacts: 405", async () => {
  const r = await worker.fetch(req(SNAPZ, { method: "POST", body: "x" }), env());
  assert.equal(r.status, 405); isolation(r);
});

test("assets pass through with isolation headers (shell and gallery)", async () => {
  const e = env();
  for (const [p, want] of [["/?snapshots=snapshots/widgets8", "qed64"], ["/showcase/", "gallery"]]) {
    const r = await worker.fetch(req(p), e);
    assert.equal(r.status, 200, p); isolation(r);
    assert.match(await r.text(), new RegExp(want));
  }
  const miss = await worker.fetch(req("/nope.js"), e);
  assert.equal(miss.status, 404); isolation(miss);
});

test("ROOT_REDIRECT: only a bare '/' redirects; the gallery's iframe URL never does", async () => {
  const e = env({ ROOT_REDIRECT: "/showcase/" });
  const r = await worker.fetch(req("/"), e);
  assert.equal(r.status, 302); isolation(r);
  assert.equal(r.headers.get("location"), ORIGIN + "/showcase/");
  const frame = await worker.fetch(req("/?snapshots=snapshots/widgets8"), e);
  assert.equal(frame.status, 200);
  const off = await worker.fetch(req("/"), env());
  assert.equal(off.status, 200, "no redirect when ROOT_REDIRECT is unset");
});

// ------------------------------------------------------------------ single-range GETs (lean4game parity)
const KEY = SNAPZ.slice(1);
const ETAG = `"etag-${KEY}"`;
const get = (p, headers = {}, e = env()) => worker.fetch(req(p, { headers }), e);
const bytesOf = async (r) => new Uint8Array(await r.arrayBuffer());

test("range: a full GET carries Accept-Ranges and asks R2 for no range", async () => {
  const e = env();
  const r = await get(SNAPZ, {}, e);
  assert.equal(r.status, 200); isolation(r);
  assert.equal(r.headers.get("accept-ranges"), "bytes");
  assert.equal(r.headers.get("content-range"), null);
  assert.equal(r.headers.get("etag"), ETAG);
  assert.deepEqual(e.ARTIFACTS.calls, [{ op: "get", key: KEY }]);
});

test("range: HEAD ignores Range and advertises Accept-Ranges", async () => {
  const e = env();
  const r = await worker.fetch(req(SNAPZ, { method: "HEAD", headers: { range: "bytes=0-99" } }), e);
  assert.equal(r.status, 200);
  assert.equal(r.headers.get("accept-ranges"), "bytes");
  assert.equal(r.headers.get("content-range"), null);
  assert.equal(r.headers.get("content-length"), String(BYTES.length));
  assert.deepEqual(e.ARTIFACTS.calls, [{ op: "head", key: KEY }]);
});

test("range: bytes=0-99 -> 206, Content-Range, partial Content-Length, isolation, immutable", async () => {
  const e = env();
  const r = await get(SNAPZ, { range: "bytes=0-99" }, e);
  assert.equal(r.status, 206); isolation(r);
  assert.equal(r.headers.get("content-range"), "bytes 0-99/1000");
  assert.equal(r.headers.get("content-length"), "100");
  assert.equal(r.headers.get("accept-ranges"), "bytes");
  assert.equal(r.headers.get("content-type"), "application/octet-stream");
  assert.equal(r.headers.get("cache-control"), "public, max-age=31536000, immutable");
  assert.deepEqual(await bytesOf(r), BYTES.slice(0, 100));
  assert.deepEqual(e.ARTIFACTS.calls, [{ op: "head", key: KEY }, { op: "get", key: KEY, range: "bytes=0-99" }]);
});

test("range: suffix, open-ended, clamped and whole-object suffix ranges", async () => {
  for (const [range, cr, len, slice] of [
    ["bytes=-100", "bytes 900-999/1000", "100", [900]],
    ["bytes=-5000", "bytes 0-999/1000", "1000", [0]],
    ["bytes=100-", "bytes 100-999/1000", "900", [100]],
    ["bytes=990-4999", "bytes 990-999/1000", "10", [990]],
  ]) {
    const r = await get(SNAPZ, { range });
    assert.equal(r.status, 206, range);
    assert.equal(r.headers.get("content-range"), cr, range);
    assert.equal(r.headers.get("content-length"), len, range);
    assert.deepEqual(await bytesOf(r), BYTES.slice(...slice), range);
  }
});

test("range: R2_PREFIX applies to the head() and the ranged get()", async () => {
  const e = env({ R2_PREFIX: "showcase-v1/" });
  const r = await get(SNAPZ, { range: "bytes=10-19" }, e);
  assert.equal(r.status, 206);
  assert.deepEqual(await bytesOf(r), BYTES.slice(10, 20));
  assert.deepEqual(e.ARTIFACTS.calls, [{ op: "head", key: "showcase-v1/" + KEY }, { op: "get", key: "showcase-v1/" + KEY, range: "bytes=10-19" }]);
});

test("range: If-Range == etag resumes (206); a mismatch, weak etag or date gets the full 200", async () => {
  const ok = await get(SNAPZ, { range: "bytes=500-", "if-range": ETAG });
  assert.equal(ok.status, 206);
  assert.equal(ok.headers.get("content-range"), "bytes 500-999/1000");
  assert.deepEqual(await bytesOf(ok), BYTES.slice(500));
  for (const validator of ['"some-older-version"', "W/" + ETAG, "Mon, 21 Sep 2026 10:00:00 GMT"]) {
    const e = env();
    const r = await get(SNAPZ, { range: "bytes=500-", "if-range": validator }, e);
    assert.equal(r.status, 200, validator);
    assert.equal(r.headers.get("content-range"), null, validator);
    assert.deepEqual(await bytesOf(r), BYTES, validator);
    assert.deepEqual(e.ARTIFACTS.calls, [{ op: "head", key: KEY }, { op: "get", key: KEY }], `${validator}: R2 never asked for a range`);
  }
  const stale = await get(SNAPZ, { range: "bytes=1000-", "if-range": '"older"' });   // mismatch wins over 416
  assert.equal(stale.status, 200);
});

test("range: past the end -> 416, Content-Range */size, no-store, isolation, no R2 get", async () => {
  for (const range of ["bytes=1000-", "bytes=1000-1001", "bytes=5000-6000", "bytes=-0"]) {
    const e = env();
    const r = await get(SNAPZ, { range }, e);
    assert.equal(r.status, 416, range); isolation(r);
    assert.equal(r.headers.get("content-range"), "bytes */1000", range);
    assert.equal(r.headers.get("accept-ranges"), "bytes", range);
    assert.equal(r.headers.get("cache-control"), "no-store", range);
    assert.deepEqual(e.ARTIFACTS.calls, [{ op: "head", key: KEY }], range);
  }
});

test("range: multi-range, other units, malformed or inverted specs are ignored (full 200, no R2 range)", async () => {
  for (const range of ["bytes=0-9,20-29", "items=0-9", "bytes=abc", "bytes=-", "bytes=9-0", "0-9", "BYTES=0-9", "bytes= 0-9", "bytes=0-99999999999999999999"]) {
    const e = env();
    const r = await get(SNAPZ, { range }, e);
    assert.equal(r.status, 200, range);
    assert.equal(r.headers.get("content-range"), null, range);
    assert.deepEqual(await bytesOf(r), BYTES, range);
    assert.deepEqual(e.ARTIFACTS.calls, [{ op: "get", key: KEY }], range);
  }
});

test("range: a missing artifact is a 404 with and without Range; assets never see Range handling", async () => {
  for (const headers of [{}, { range: "bytes=0-99" }]) {
    const e = env();
    const r = await get("/snapshots/widgets8/absent.0123456789abcdef.snapz", headers, e);
    assert.equal(r.status, 404); isolation(r);
    assert.deepEqual(e.ASSETS.calls, []);
  }
  const e = env();
  const a = await get("/showcase/", { range: "bytes=0-3" }, e);
  assert.equal(a.status, 200);
  assert.equal(a.headers.get("accept-ranges"), null);
  assert.deepEqual(e.ARTIFACTS.calls, []);
});

test("range: parseRange / resolveRange (lean4game's cases)", () => {
  assert.deepEqual(parseRange("bytes=0-99"), { first: 0, last: 99 });
  assert.deepEqual(parseRange(" bytes=100- "), { first: 100 });
  assert.equal(parseRange("Bytes = 100 - "), null);
  assert.equal(parseRange("bytes=0-99999999999999999999"), null);
  assert.deepEqual(parseRange("bytes=-100"), { suffix: 100 });
  assert.equal(parseRange(null), null);
  assert.equal(parseRange("bytes=0-1,3-4"), null);
  assert.deepEqual(resolveRange({ first: 0, last: 99 }, 1000), { offset: 0, length: 100 });
  assert.deepEqual(resolveRange({ first: 82182072, last: 82182072 }, 154373030), { offset: 82182072, length: 1 });
  assert.deepEqual(resolveRange({ suffix: 100 }, 1000), { offset: 900, length: 100 });
  assert.equal(resolveRange({ first: 1000 }, 1000), null);
  assert.equal(resolveRange({ suffix: 0 }, 1000), null);
  assert.equal(resolveRange({ suffix: 10 }, 0), null);
});

test("HEAD on a static asset carries the GET's Content-Length (the asset binding omits it on HEAD)", async () => {
  const e = env();
  const r = await worker.fetch(req("/showcase/", { method: "HEAD" }), e);
  assert.equal(r.status, 200); isolation(r);
  assert.equal(r.headers.get("content-length"), String(new TextEncoder().encode("<!doctype html>gallery").length));
  assert.equal(r.headers.get("content-type"), "text/html");
  assert.equal(r.body, null);
  assert.deepEqual(e.ASSETS.calls, ["/showcase/", "/showcase/"], "one HEAD, then one GET for the length");
  const g = env();   // GET is a single pass-through
  await (await worker.fetch(req("/showcase/"), g)).text();
  assert.deepEqual(g.ASSETS.calls, ["/showcase/"]);
  const miss = env();   // a 404 is not re-fetched
  assert.equal((await worker.fetch(req("/nope.js", { method: "HEAD" }), miss)).status, 404);
  assert.deepEqual(miss.ASSETS.calls, ["/nope.js"]);
});
