/* infra/worker.js against fake ASSETS / R2 bindings: `node --test infra/worker.test.mjs`.
 * Pattern from the lean4game precedent (wasm64-lean4game/infra/worker.test.mjs). No network, no account.
 *
 * The Worker is QED64's createWorker (tests/unit/edge-worker.test.ts there covers the library, ranges included), so this
 * file is what the SHOWCASE relies on from it, with the pin's own record: every file of the active pin's lock is read
 * from the key deploy-manifest records (scripts/lib/release-routing.mjs); a release-mapped path never falls back to our
 * prefix and its errors are never cached; COOP/COEP/CORP on every response; the cache rule IS QED64's isImmutable (no
 * copy of its regexes here, in serve.mjs or in deploy-manifest.mjs); R2_PREFIX and ROOT_REDIRECT from wrangler [vars];
 * HEAD with an explicit Content-Length (the gallery's preflight needs content-length == transfer); the R2 object's
 * Content-Type passed through (qed64-boot.ts:69 and gallery/lib.js refuse a runtime manifest whose type is not JSON);
 * one resumed range and one past the end (deploy-manifest --smoke --range checks both); per-runtime overlay directories
 * (/snapshots/widgets8.<bid16>/, scripts/lib/pins.mjs overlayDir) with no alias to the bare one.
 */
import test from "node:test";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import worker from "./worker.js";
import { isImmutable, releaseRoutes } from "../deps/qed64/infra/edge-worker.js";
import { releaseKey } from "../scripts/lib/release-routing.mjs";

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ORIGIN = "https://showcase.example";
const IMMUTABLE = "public, max-age=31536000, immutable";
const REVALIDATE = "public, max-age=0, must-revalidate";
const RECORD = JSON.parse(fs.readFileSync(path.join(SC, "deps/qed64/toolchain/lean4-wasm64-release.json"), "utf8"));
const ROUTES = releaseRoutes(RECORD);
const SNAPZ = "/snapshots/widgets8/widgets.0880fd91b58098c0.snapz";
// a per-runtime overlay directory (pin.json v3, "overlayDirs": "per-runtime"; pin I's runtime as the fixture)
const RT_DIR = "widgets8.f69cca24d0878a58";
const RT_INDEX = `/snapshots/${RT_DIR}/index.json`;
const RT_SNAPZ = `/snapshots/${RT_DIR}/widgets.1b2c3d4e5f60718a.snapz`;
const RT_BYTES = Uint8Array.from({ length: 777 }, (_, i) => (i * 13 + 5) % 256);
const PINS = await import(path.join(SC, "scripts/lib/pins.mjs"));
const RTM = `/runtime/runtime-manifest.${PINS.activeBuildId()}.json`;
const PACK_PART = "/profiles/lean-core.pack.gzip.1016929d99bb0ba0e148.part-007";
const BYTES = Uint8Array.from({ length: 1000 }, (_, i) => (i * 7 + 3) % 256);
const json = (t) => ({ bytes: new TextEncoder().encode(t), contentType: "application/json" });

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
    "snapshots/widgets8/index.json": json("{}"),
    [SNAPZ.slice(1)]: { bytes: BYTES },
    ["showcase-v1/" + SNAPZ.slice(1)]: { bytes: BYTES },
    [RT_INDEX.slice(1)]: json('{"per":"runtime"}'),
    [RT_SNAPZ.slice(1)]: { bytes: RT_BYTES },
    ["showcase-v1/" + RT_SNAPZ.slice(1)]: { bytes: RT_BYTES },
    "profiles/index.json": json("{}"),
    "showcase-v1/profiles/index.json": json("{}"),
    [ROUTES.prefix + RTM.slice(1)]: json("{}"),
    [ROUTES.prefix + PACK_PART.slice(1)]: { bytes: BYTES },
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

test("the cache rule is QED64's, with no copy of its regexes; per-runtime overlay directories keep it", () => {
  for (const f of ["scripts/serve.mjs", "scripts/deploy-manifest.mjs", "infra/worker.js"])
    assert.ok(!fs.readFileSync(path.join(SC, f), "utf8").includes("\\.chunk\\.|[0-9a-f]{16,}"), `${f} has no local copy of QED64's rule`);
  assert.equal(isImmutable(SNAPZ), true);
  assert.equal(isImmutable("/snapshots/widgets8/index.json"), false);
  // the hex in the directory name must not make the index immutable
  assert.equal(isImmutable(RT_INDEX), false, RT_INDEX);
  assert.equal(isImmutable(RT_SNAPZ), true, RT_SNAPZ);
  assert.equal(isImmutable(RTM), false, RTM);
});

test("every file of the active pin's lock: the Worker reads the key deploy-manifest records", async () => {
  const lock = JSON.parse(fs.readFileSync(path.join(SC, "QED64.lock.json"), "utf8"));
  const pub = Object.keys(lock.release.files).filter((k) => k.startsWith("public/")).map((k) => `/${k.slice("public/".length)}`);
  const n = { release: 0, site: 0 };
  assert.ok(pub.length > 10);
  for (const url of pub) {
    const mapped = releaseKey(ROUTES, url);
    const want = mapped ?? `showcase-v1/${url.slice(1)}`;
    n[mapped === null ? "site" : "release"]++;
    const e = env({ R2_PREFIX: "showcase-v1/" });
    await worker.fetch(req(url), e);
    assert.deepEqual(e.ARTIFACTS.calls, [{ op: "get", key: want }], url);
  }
  assert.ok(n.release > 0 && n.site > 0, JSON.stringify(n));
  assert.equal(releaseKey(ROUTES, "/profiles/index.json"), null, "the profile index is ours");
  assert.equal(releaseKey(ROUTES, RTM), `lean4-wasm64/${RECORD.id}${RTM}`);
});

test("release-mapped paths: from the release's prefix, whatever R2_PREFIX says; a miss is a no-store 404 and never falls back to our prefix", async () => {
  const e = env({ R2_PREFIX: "showcase-v1/" });
  const r = await worker.fetch(req(PACK_PART), e);
  assert.equal(r.status, 200); isolation(r);
  assert.equal(r.headers.get("cache-control"), IMMUTABLE);
  assert.deepEqual(e.ARTIFACTS.calls, [{ op: "get", key: ROUTES.prefix + PACK_PART.slice(1) }]);
  const old = "/runtime/runtime-manifest.wasm64-0000000000000000.json";
  for (const method of ["GET", "HEAD"]) {
    const m = env({ R2_PREFIX: "", ARTIFACTS: fakeBucket({ [old.slice(1)]: json("{}") }) });
    const miss = await worker.fetch(req(old, { method }), m);
    assert.equal(miss.status, 404, `${method}: an older pin's file under our prefix is not served`); isolation(miss);
    assert.equal(miss.headers.get("cache-control"), "no-store", method);
    assert.equal(m.ARTIFACTS.calls.length, 1, method);
  }
});

test("our paths: artifact GET, isolation + immutable + content-length, R2 metadata passed through", async () => {
  const e = env();
  const r = await worker.fetch(req(SNAPZ), e);
  assert.equal(r.status, 200); isolation(r);
  assert.equal(r.headers.get("cache-control"), IMMUTABLE);
  assert.equal(r.headers.get("content-length"), String(BYTES.length));
  assert.equal(r.headers.get("content-encoding"), null);
  assert.equal(r.headers.get("content-type"), "application/octet-stream");
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

test("R2_PREFIX is prepended to our keys", async () => {
  const e = env({ R2_PREFIX: "showcase-v1/" });
  assert.equal((await worker.fetch(req(SNAPZ), e)).status, 200);
  assert.equal((await worker.fetch(req("/profiles/index.json"), e)).status, 200);
  assert.deepEqual(e.ARTIFACTS.calls, [{ op: "get", key: "showcase-v1/" + SNAPZ.slice(1) }, { op: "get", key: "showcase-v1/profiles/index.json" }]);
});

test("indexes and manifests revalidate and keep their JSON content-type (GET and HEAD)", async () => {
  for (const p of ["/snapshots/widgets8/index.json", RTM, "/profiles/index.json"]) {
    for (const method of ["GET", "HEAD"]) {
      const r = await worker.fetch(req(p, { method }), env());
      assert.equal(r.status, 200, `${method} ${p}`); isolation(r);
      assert.equal(r.headers.get("cache-control"), REVALIDATE, `${method} ${p}`);
      assert.equal(r.headers.get("content-type"), "application/json", `${method} ${p}`);
    }
  }
});

test("every artifact prefix is routed to R2, never to ASSETS; a miss is a 404, never a fallback page", async () => {
  for (const p of [RTM, PACK_PART, SNAPZ, "/profiles/missing.json", "/snapshots/nope/index.json"]) {
    const e = env();
    const r = await worker.fetch(req(p), e);
    assert.equal(r.status, p.includes("missing") || p.includes("nope") ? 404 : 200, p); isolation(r);
    assert.deepEqual(e.ASSETS.calls, [], p);
  }
});

test("empty segments are refused without touching R2; non-GET/HEAD is a 405", async () => {
  for (const p of ["/snapshots//widgets8/index.json", "/runtime//x"]) {   // URL parsing already folds ".."
    const e = env();
    const r = await worker.fetch(req(p), e);
    assert.equal(r.status, 404, p); isolation(r);
    assert.deepEqual(e.ARTIFACTS.calls, [], p);
  }
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
  assert.equal((await worker.fetch(req("/?snapshots=snapshots/widgets8"), e)).status, 200);
  assert.equal((await worker.fetch(req(`/?snapshots=snapshots/${RT_DIR}`), e)).status, 200);
  assert.equal((await worker.fetch(req("/"), env())).status, 200, "no redirect when ROOT_REDIRECT is unset");
});

test("HEAD on a static asset carries the GET's Content-Length (the asset binding omits it on HEAD)", async () => {
  const e = env();
  const r = await worker.fetch(req("/showcase/", { method: "HEAD" }), e);
  assert.equal(r.status, 200); isolation(r);
  assert.equal(r.headers.get("content-length"), String(new TextEncoder().encode("<!doctype html>gallery").length));
  assert.equal(r.headers.get("content-type"), "text/html");
  assert.equal(r.body, null);
});

test("range: a resumed GET is a 206 with Content-Range; past the end is a no-store 416 (deploy-manifest --smoke --range)", async () => {
  const r = await worker.fetch(req(SNAPZ, { headers: { range: "bytes=0-99" } }), env());
  assert.equal(r.status, 206); isolation(r);
  assert.equal(r.headers.get("content-range"), "bytes 0-99/1000");
  assert.equal(r.headers.get("content-length"), "100");
  assert.equal(r.headers.get("accept-ranges"), "bytes");
  assert.equal(r.headers.get("cache-control"), IMMUTABLE);
  assert.deepEqual(new Uint8Array(await r.arrayBuffer()), BYTES.slice(0, 100));
  const p = await worker.fetch(req(SNAPZ, { headers: { range: "bytes=1000-" } }), env());
  assert.equal(p.status, 416); isolation(p);
  assert.equal(p.headers.get("content-range"), "bytes */1000");
  assert.equal(p.headers.get("cache-control"), "no-store");
  const stale = await worker.fetch(req(SNAPZ, { headers: { range: "bytes=0-99", "if-range": '"other"' } }), env());
  assert.equal(stale.status, 200, "a mismatched If-Range gets the full object");
});

test("per-runtime overlay dir: index revalidates, .snapz immutable with HEAD Content-Length, and no alias to the bare directory", async () => {
  const e = env();
  const ix = await worker.fetch(req(RT_INDEX), e);
  assert.equal(ix.status, 200); isolation(ix);
  assert.equal(ix.headers.get("cache-control"), REVALIDATE);
  assert.equal(await ix.text(), '{"per":"runtime"}');
  const h = await worker.fetch(req(RT_SNAPZ, { method: "HEAD" }), env({ R2_PREFIX: "showcase-v1/" }));
  assert.equal(h.status, 200); isolation(h);
  assert.equal(h.headers.get("content-length"), String(RT_BYTES.length));
  assert.equal(h.headers.get("cache-control"), IMMUTABLE);
  for (const p of ["/snapshots/widgets8.0000000000000000/index.json", "/snapshots/widgets8/widgets.1b2c3d4e5f60718a.snapz"]) {
    const m = env();
    const miss = await worker.fetch(req(p), m);
    assert.equal(miss.status, 404, p); isolation(miss);
    assert.deepEqual(m.ARTIFACTS.calls, [{ op: "get", key: p.slice(1) }], `${p}: asked R2 for exactly that key`);
  }
});

// scripts/deploy-manifest.mjs --smoke against this Worker (the fake R2 behind a local HTTP server). A manifest or index
// is replaced in place under the same URL, so the stale one an origin still serves can have this release's size: pin
// O's deploy rehearsal (order B) passed the old snapshots/index.json, 701 B at H and at O, on its HEAD content-length.
test("deploy-manifest --smoke: an index of the manifest's size with other bytes FAILS (GET + sha256); immutable keys stay HEAD-only", async () => {
  const INDEX = "/profiles/index.json";
  const fresh = new TextEncoder().encode('{"release":"new"}');   // this manifest's upload
  const stale = new TextEncoder().encode('{"release":"old"}');   // what the origin still serves: same length, other bytes
  assert.equal(stale.length, fresh.length);
  const sha = (b) => createHash("sha256").update(b).digest("hex");
  const out = fs.mkdtempSync(path.join(os.tmpdir(), "deploy-manifest-smoke-"));
  fs.writeFileSync(path.join(out, "manifest.json"), JSON.stringify({
    pin: { buildId: PINS.activeBuildId() }, options: { overlays: [] }, assets: [],
    r2: [{ url: INDEX, key: INDEX.slice(1), size: fresh.length, sha256: sha(fresh), immutable: false },
      { url: SNAPZ, key: SNAPZ.slice(1), size: BYTES.length, sha256: sha(BYTES), immutable: true }],
  }));
  const serve = (e) => new Promise((resolve) => {
    const srv = http.createServer(async (rq, rs) => {
      const headers = Object.fromEntries(Object.entries(rq.headers).filter(([k]) => k !== "host" && k !== "connection"));
      const r = await worker.fetch(new Request(ORIGIN + rq.url, { method: rq.method, headers }), e);
      rs.writeHead(r.status, Object.fromEntries(r.headers));
      rs.end(rq.method === "HEAD" ? undefined : Buffer.from(await r.arrayBuffer()));
    });
    srv.listen(0, "127.0.0.1", () => resolve(srv));
  });
  // async (the server answers in this process); --no-concurrent-sparkplug as NODE_TOOL (scripts/lib/platform.sh)
  const smoke = (origin) => new Promise((resolve) => execFile(process.execPath,
    ["--no-concurrent-sparkplug", path.join(SC, "scripts/deploy-manifest.mjs"), "--out", out, "--smoke", origin, "--all"],
    { timeout: 60_000 }, (err, stdout, stderr) => resolve({ code: err ? err.code : 0, stdout, stderr })));
  try {
    for (const served of [fresh, stale]) {
      const e = env({ ARTIFACTS: fakeBucket({
        [INDEX.slice(1)]: { bytes: served, contentType: "application/json" },
        [SNAPZ.slice(1)]: { bytes: BYTES },
      }) });
      const srv = await serve(e);
      const r = await smoke(`http://127.0.0.1:${srv.address().port}`);
      srv.closeAllConnections(); srv.close();
      const log = `${r.stdout}${r.stderr}`;
      assert.ok(!log.includes(`FAIL HEAD ${INDEX}`), `the HEAD passes either way (same size):\n${log}`);
      if (served === fresh) {
        assert.equal(r.code, 0, log);
        assert.match(r.stdout, /1\/1 manifests and indexes GET with the manifest's sha256/, log);
        assert.match(r.stdout, /^SMOKE OK$/m, log);
      } else {
        assert.equal(r.code, 1, log);
        assert.ok(r.stdout.includes(`FAIL GET ${INDEX} — published ${stale.length} B sha256 ${sha(stale).slice(0, 16)}… != manifest ${fresh.length} B ${sha(fresh).slice(0, 16)}…`), log);
        assert.match(r.stdout, /^SMOKE FAILED$/m, log);
      }
      const ops = (k) => e.ARTIFACTS.calls.filter((c) => c.key === k.slice(1)).map((c) => c.op);
      assert.deepEqual(ops(INDEX), ["head", "get"], "the index: HEAD for the headers, then GET for the sha256");
      assert.deepEqual(ops(SNAPZ), ["head"], "an immutable key is never fetched by the smoke");
    }
  } finally { fs.rmSync(out, { recursive: true, force: true }); }
});
