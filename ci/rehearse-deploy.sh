#!/bin/bash
# rehearse-deploy.sh — the qed64-deploy workflow (.github/workflows/qed64-deploy.yml) run on this machine, job by job,
# in FRESH CLONES (ci/run-local.mjs), against local fakes only. Nothing contacts Cloudflare:
#   * `wrangler` is scripts/deploy-rehearsal/wrangler-shim.sh (WRANGLER_BIN, a runner-level variable): `wrangler deploy`
#     becomes `wrangler deploy --dry-run` under the offline sandbox with no token, and the "deployed" Worker is
#     `wrangler dev --local` on the same generated wrangler.toml over a fake R2 (a copy of the state that
#     scripts/deploy-rehearsal/rehearse.sh `load` filled with the full release's 93 objects);
#   * the secrets are placeholders that never reach wrangler (the shim unsets them);
#   * the "live showcase" (vars.SHOWCASE_ORIGIN) is a wrangler dev serving a placeholder shell over that fake R2, and
#     an "origin without artifacts" is a wrangler dev over an empty R2.
# Scenarios (each a separate fresh clone; expectations are checked, not just printed):
#   skip        push, no secrets                        -> the skip line; every later step skipped
#   dry-run     dispatch dry_run=true, no secrets        -> everything up to `wrangler deploy --dry-run`
#   unpublished push, SHOWCASE_ORIGIN = the empty R2     -> the published check refuses; wrangler never runs
#   deploy      push, SHOWCASE_ORIGIN = the live stand-in -> published check OK, "deploy", smoke OK on the new Worker
#   first       push, no SHOWCASE_ORIGIN                 -> published check skipped (first deploy); smoke on the URL the
#                                                           deploy printed
#   no-verdict  push of a commit that changes the gallery without a new infra/ux-verdict.json -> G2 refuses
#   tamper      `deploy-manifest --published` of the deploy scenario's manifest with one index sha256 and one object
#               size altered, against the live stand-in -> FAIL (the check can see a wrong upload). The index is the
#               widgets8 overlay's at the directory the manifest records (options.overlayDirs: bare for pins A–H,
#               widgets8.<bid16> for a per-runtime pin)
#   old-shell   a runtime-changing deploy against the LIVE shell (pin I plan, D7). The fake R2 is OLD_STATE (the live
#               pin's published objects) plus the new manifest's upload phases 1-2 (scripts/upload-artifacts.sh's phase
#               rule) loaded on top; nothing is deleted. Checked: no digest-named object changes and no bare overlay
#               object is rewritten (the phase-2 manifests that replace live ones are listed). Real order of events:
#               the OLD Worker and shell (the workflow run at OLD_REF, a fresh clone) deploy over a pristine OLD_STATE
#               with their published check and smoke OK, THEN phases 1-2 are loaded under them; OLD_MANIFEST's
#               --published without the replaced phase-2 keys is OK, and each replaced key serves exactly the new
#               manifest's bytes: a runtime manifest is "REPLACED (expected)" (the old shell reads its per-build copy
#               first), a pack manifest /profiles/<p>.manifest.json (the same URL in every release; another release's
#               content when the packs change, as at QED64 521cf3f) is an E1 HAZARD: an "E1 MEASURE" line names it and its
#               window (from phase 2 until the new Worker is deployed, in either order; an old tab left open after it
#               too); every bare snapshots/widgets{7,8}/ object is untouched; one boot of
#               the old gallery (/showcase/#hasse-view, the old clone's boot-check.mjs) and one bare "/" stock boot,
#               both under the browser lock. Every boot also records which /profiles/ pack manifests and parts it fetched,
#               read from the old-shell origin's request log (wrangler dev logs each request; server-side, so an old
#               clone's boot scripts need not record it), classified against OLD_MANIFEST and NEW_MANIFEST: for the old
#               shell's boots an "E1 MEASURE" line says whether it fetched NEW-release pack parts (<run>/old-shell/
#               pack-fetches.txt has every boot). Then phase 3 and the NEW Worker (the workflow at REF), in both orders, to
#               MEASURE decision E1 rather than assume it:
#                 order A  phase 3 BEFORE the deploy (today's upload): measure the old shell's stock and gallery boots in
#                          the window; then the new workflow (published check, deploy, SMOKE) and the new gallery + stock
#                          boots must be OK
#                 order B  phase 3 AFTER the deploy (PHASES=1-objects,2-manifests, deploy, PHASES=3-indexes): measure
#                          whether the CI published check refuses before phase 3, the new Worker deployed without it (its
#                          smoke), and the new gallery + stock boots in the window; after phase 3 the new manifest's
#                          --published and --smoke --all --range and the new gallery + stock boots must be OK
#               The window results are printed as "E1 MEASURE …" lines (and <run>/old-shell/e1-measure.txt); they are
#               evidence, not failures. Needs OLD_REF; skipped (named on the last line, never counted as OK) without it.
#
#   ci/rehearse-deploy.sh [scenario…]       default: all of them, in the order above
# Env: REF (commit to clone, default HEAD), RUN_DIR (default $QED64_SHOWCASE_WORK/ci-rehearsal/<UTC time>),
# REHEARSAL_SRC_STATE (default $QED64_SHOWCASE_WORK/deploy-rehearsal/state), PORT (default 8792; PORT+10 = empty R2).
# old-shell only: OLD_REF (required: the commit the LIVE shell was deployed from), OLD_STATE (a wrangler dev state
# holding exactly the live pin's objects, default $QED64_SHOWCASE_WORK/deploy-rehearsal/state, which must not be
# REHEARSAL_SRC_STATE: rebuild the new pin's rehearsal state into another REHEARSAL_DIR first), OLD_MANIFEST (default the
# newest release record's manifest.json under qed64-showcase/out/deploy/published), NEW_MANIFEST (the full manifest the
# new pin's rehearsal uploaded, default qed64-showcase/out/deploy-rehearsal/deploy/manifest.json), NEW_BUCKET_DIR (that
# rehearsal's fake bucket, default <dirname REHEARSAL_SRC_STATE>/bucket), OLD_SHELL_ORDERS (default "A B"); ports
# PORT+20 (the old-shell origin) and PORT+30 (the R2 loader). Several GB of local R2 state under <run>/old-shell.
# macOS only (sandbox-exec), like scripts/deploy-rehearsal/rehearse.sh.
# shellcheck disable=SC2016  # single-quoted node snippets use JS template literals on purpose
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SC="$ROOT/qed64-showcase"
# shellcheck source=SCRIPTDIR/../qed64-showcase/scripts/lib/env.sh
. "$SC/scripts/lib/env.sh"
die() { echo "rehearse-deploy: $*" >&2; exit 2; }
command -v sandbox-exec >/dev/null || die "needs macOS sandbox-exec (the wrangler shim runs offline under it)"
[ -d "$ROOT/ci/node_modules/yaml" ] || npm ci --prefix "$ROOT/ci" --no-audit --no-fund
# the wrangler stand-in starts the pinned wrangler (infra/) before deploy-app.sh would install it: install it here so a
# fresh clone works (the real workflow gets it from deploy-app.sh, which runs the same npm ci when it is missing)
[ -x "$SC/infra/node_modules/.bin/wrangler" ] || npm ci --prefix "$SC/infra" --no-audit --no-fund
REF=$(git -C "$ROOT" rev-parse "${REF:-HEAD}^{commit}")
RUN=${RUN_DIR:-$W/ci-rehearsal/$(date -u +%Y%m%dT%H%M%SZ)}
[ ! -e "$RUN" ] || die "$RUN exists"
SRC_STATE=${REHEARSAL_SRC_STATE:-$W/deploy-rehearsal/state}
[ -d "$SRC_STATE" ] || die "no fake R2 state at $SRC_STATE: run scripts/deploy-rehearsal/rehearse.sh upload-dry upload deploy-dry load (macOS) first"
PORT=${PORT:-8792}; EMPTY_PORT=$((PORT + 10))
SHIM="$SC/scripts/deploy-rehearsal/wrangler-shim.sh"
WF=.github/workflows/qed64-deploy.yml
mkdir -p "$RUN"
echo "rehearse-deploy: commit $REF, run dir $RUN"
cp -cR "$SRC_STATE" "$RUN/state"            # a copy-on-write clone: wrangler dev writes to its state
mkdir -p "$RUN/empty-state" "$RUN/live/assets"
echo '<!doctype html><title>previous shell (rehearsal stand-in)</title>' > "$RUN/live/assets/index.html"
node "$SC/scripts/lib/wrangler-config.mjs" write "$RUN/live/wrangler.toml" --assets "$RUN/live/assets" >/dev/null
LIVE_ENV=(REHEARSAL_STATE="$RUN/state" REHEARSAL_PORT="$PORT" REHEARSAL_RUN_DIR="$RUN/server")
EMPTY_ENV=(REHEARSAL_STATE="$RUN/empty-state" REHEARSAL_PORT="$EMPTY_PORT" REHEARSAL_RUN_DIR="$RUN/empty-server")
OLD_PORT=$((PORT + 20)); LOADER_PORT=$((PORT + 30))
cleanup() {
  env "${LIVE_ENV[@]}" "$SHIM" _stop || true; env "${EMPTY_ENV[@]}" "$SHIM" _stop || true
  local d; for d in "$RUN"/old-shell/*/server; do [ -d "$d" ] || continue
    env REHEARSAL_STATE="$(dirname "$d")/state" REHEARSAL_PORT="$OLD_PORT" REHEARSAL_RUN_DIR="$d" "$SHIM" _stop || true; done
}
trap cleanup EXIT
env "${LIVE_ENV[@]}" "$SHIM" _serve --config "$RUN/live/wrangler.toml"
env "${EMPTY_ENV[@]}" "$SHIM" _serve --config "$RUN/live/wrangler.toml"

FAILS=0
pass() { echo "SCENARIO OK   $1: $2"; }
fail() { echo "SCENARIO FAIL $1: $2"; FAILS=$((FAILS + 1)); }
# runlocal <scenario> <expected rc> <run-local args…>: the runner's own output goes to <run>/<scenario>.log
runlocal() {
  local name=$1 want=$2 rc=0; shift 2
  echo "== scenario $name: node ci/run-local.mjs --workflow $WF $*"
  node "$ROOT/ci/run-local.mjs" --workflow "$WF" --ref "$REF" --out "$RUN/$name" "$@" > "$RUN/$name.log" 2>&1 || rc=$?
  tail -3 "$RUN/$name.log"
  [ "$rc" = "$want" ] || { fail "$name" "run-local rc $rc, expected $want (log $RUN/$name.log)"; return 1; }
}
has() { grep -qE -e "$2" "$RUN/$1.log"; }
# the wrangler stand-in as runner-level variables (an array: the shim's path has a space)
shim_env() { SHIM_ENV=(--runner-env "WRANGLER_BIN=$SHIM" --runner-env "REHEARSAL_STATE=$1" --runner-env "REHEARSAL_PORT=$2" --runner-env "REHEARSAL_RUN_DIR=$3"); }
SECRETS=(--secret CLOUDFLARE_API_TOKEN=rehearsal-placeholder-not-a-token --secret CLOUDFLARE_ACCOUNT_ID=rehearsal-placeholder)


# ------------------------------------------------------------------ old-shell (pin I plan D7: a runtime change vs the live shell)
SKIPPED=()
SB="$SC/scripts/deploy-rehearsal/offline.sb"
# oserve <order dir> <wrangler.toml>: (re)start wrangler dev on the old-shell port over <order dir>/state with that config
oserve() { env REHEARSAL_STATE="$1/state" REHEARSAL_PORT="$OLD_PORT" REHEARSAL_RUN_DIR="$1/server" "$SHIM" _serve --config "$2" >> "$1/serve.log" 2>&1; }
ostop() { env REHEARSAL_STATE="$1/state" REHEARSAL_PORT="$OLD_PORT" REHEARSAL_RUN_DIR="$1/server" "$SHIM" _stop >> "$1/serve.log" 2>&1; }
# oload <state> <subset name>: load the new manifest's <subset> objects (prepared by old_shell_prep) into a STOPPED state
oload() {
  local O="$RUN/old-shell" rc=0
  sandbox-exec -f "$SB" node "$SC/scripts/deploy-rehearsal/load-r2.mjs" --bucket-dir "$O/$2-bucket" --bucket "$OS_BUCKET" \
    --persist-to "$1" --manifest "$O/$2-manifest.json" --port "$LOADER_PORT" > "$O/load-$2-$(basename "$(dirname "$1")").log" 2>&1 || rc=$?
  tail -1 "$O/load-$2-$(basename "$(dirname "$1")").log"
  [ "$rc" = 0 ] && grep -q '^LOAD-R2 OK' "$O/load-$2-$(basename "$(dirname "$1")").log"
}
# the wrangler.toml a run-local deploy of <scenario> generated in its fresh clone (deploy-app.sh writes it next to the clone's
# qed64-showcase/), and that clone's qed64-showcase/ directory
oconfig() { find "$RUN/$1" -path '*/lean-widgets/qed64-showcase/wrangler.toml' 2>/dev/null | head -1; }
# The request log of the server on the old-shell port in the current order (oserve and the shim's deploy both run it
# with REHEARSAL_RUN_DIR=<order dir>/server; set per order in old_shell), and its line count before a boot.
OS_SRVLOG=""
osrvlines() { local n=0; [ -f "$OS_SRVLOG" ] && n=$(wc -l < "$OS_SRVLOG"); echo $((n + 1)); }
# opacks <tag> <first log line>: the /profiles/ pack manifests and parts the boot <tag> fetched (its slice of OS_SRVLOG:
# wrangler dev logs "[wrangler:info] GET <path> <status> …" per request), each part classified by the deploy manifests
# that name it: NEW_MANIFEST only (the new release's bytes), OLD_MANIFEST only, or both. Observation only: it never
# changes a boot's result. An old shell's boot (a tag with "old-") gets an E1 MEASURE line; every boot is listed in
# <run>/old-shell/pack-fetches.txt.
opacks() {
  local tag=$1 from=$2 line
  if [ ! -f "$OS_SRVLOG" ]; then line="not measured: no server log ${OS_SRVLOG:-(none)}"
  else line=$(tail -n +"$from" "$OS_SRVLOG" | node -e 'const fs=require("fs");
    const urls=(p)=>new Set(JSON.parse(fs.readFileSync(p,"utf8")).r2.map((o)=>o.url));const om=urls(process.argv[1]),nm=urls(process.argv[2]);
    let s="";process.stdin.on("data",(d)=>(s+=d)).on("end",()=>{
      if(!/\[wrangler:info\] [A-Z]+ \//.test(s)){console.log("not measured: no request lines in the server log for this boot");return;}
      const got=[...s.matchAll(/\[wrangler:info\] GET (\/profiles\/[^\s?]+)\S* (\d{3})/g)].map((m)=>({u:m[1],st:m[2]}));
      const mans=[...new Set(got.filter((r)=>/\.manifest\.json$/.test(r.u)).map((r)=>`${r.u.split("/").pop()} ${r.st}`))];
      const parts=[...new Set(got.filter((r)=>/\.part-\d+$/.test(r.u)).map((r)=>r.u))];
      const of=(f)=>parts.filter(f).length;
      const nNew=of((u)=>nm.has(u)&&!om.has(u)),nOld=of((u)=>om.has(u)&&!nm.has(u)),nBoth=of((u)=>om.has(u)&&nm.has(u)),nNone=parts.length-nNew-nOld-nBoth;
      console.log(`pack manifests fetched: ${mans.join(", ")||"none"}; ${parts.length} pack part(s): ${nNew} of the NEW release only, ${nOld} of the live release only, ${nBoth} in both${nNone?`, ${nNone} in neither manifest`:""}${nNew?" (NEW-release pack parts fetched)":""}`);});' \
    "$OS_OLD_MANIFEST" "$OS_NEW_MANIFEST" 2>&1) || line="not measured: classifying $OS_SRVLOG failed (${line:0:200})"
  fi
  echo "$tag: $line" >> "$RUN/old-shell/pack-fetches.txt"
  case "$tag" in
    *old-*) measure "$tag: the OLD shell's /profiles/ fetches: $line" ;;
    *) echo "pack fetches $tag: $line" ;;
  esac
}
# boots, each under the host-wide browser lock (one Chrome at a time on this host)
ogallery() {   # <checkout qed64-showcase dir> <tag>: boot-check.mjs of THAT checkout (its examples.json) on the old-shell origin
  local c=$1 tag=$2 rc=0 b="$RUN/old-shell/bootsc-$2" n0
  # boot-check.mjs reads <its ../..>/gallery/examples.json and imports playwright: a scaffold with the checkout's two files
  # and this checkout's node_modules (a fresh clone has none)
  mkdir -p "$b/scripts/deploy-rehearsal" "$b/gallery"
  cp "$c/scripts/deploy-rehearsal/boot-check.mjs" "$b/scripts/deploy-rehearsal/" && cp "$c/gallery/examples.json" "$b/gallery/" || return 1
  [ -e "$b/node_modules" ] || ln -s "$SC/node_modules" "$b/node_modules"
  n0=$(osrvlines)
  (cd "$SC" && scripts/with-browser-lock.sh "rehearse-$tag" node "$b/scripts/deploy-rehearsal/boot-check.mjs" "http://localhost:$OLD_PORT" "$RUN/old-shell/boot-$tag") \
    > "$RUN/old-shell/boot-$tag.log" 2>&1 || rc=$?
  tail -1 "$RUN/old-shell/boot-$tag.log"
  opacks "$tag" "$n0"
  [ "$rc" = 0 ] && grep -q '^BOOT-CHECK OK' "$RUN/old-shell/boot-$tag.log"
}
ostock() {     # <tag>: one cold boot of the stock page "/" without ?snapshots= (the shell's default indexes)
  local tag=$1 rc=0 n0
  n0=$(osrvlines)
  (cd "$SC" && scripts/with-browser-lock.sh "rehearse-$tag" node "$RUN/old-shell/stock-boot.cjs" "$SC" "http://localhost:$OLD_PORT" "$RUN/old-shell/boot-$tag" "$tag") \
    > "$RUN/old-shell/boot-$tag.log" 2>&1 || rc=$?
  tail -1 "$RUN/old-shell/boot-$tag.log"
  opacks "$tag" "$n0"
  [ "$rc" = 0 ] && grep -q '^STOCK-BOOT OK' "$RUN/old-shell/boot-$tag.log"
}
measure() { echo "E1 MEASURE $*" | tee -a "$RUN/old-shell/e1-measure.txt"; }

# Prepare: the inputs, the phase split of the new manifest (upload-artifacts.sh's own rule), the overlap checks against the
# live manifest, and the subset buckets/manifests load-r2.mjs takes (hard links into the new rehearsal's fake bucket).
old_shell_prep() {
  local O="$RUN/old-shell" rule
  rule=$(grep -m1 '^const phaseOf = ' "$SC/scripts/upload-artifacts.sh") || { echo "no phaseOf rule in scripts/upload-artifacts.sh"; return 1; }
  node - "$OS_OLD_MANIFEST" "$OS_NEW_MANIFEST" "$OS_NEW_BUCKET/$OS_BUCKET" "$O" "$rule" <<'EOF'
const fs = require('fs'), path = require('path');
const [oldPath, newPath, bucketRoot, O, rule] = process.argv.slice(2);
const phaseOf = eval(rule.replace(/^const phaseOf = /, '').replace(/;\s*$/, ''));   // scripts/upload-artifacts.sh's rule
const om = JSON.parse(fs.readFileSync(oldPath, 'utf8')), nm = JSON.parse(fs.readFileSync(newPath, 'utf8'));
let bad = 0; const fail = (m) => { bad++; console.log(`FAIL ${m}`); };
if (om.options.prefix !== nm.options.prefix) fail(`prefix: live ${om.options.prefix} != new ${nm.options.prefix}`);
console.log(`live: pin ${om.pin.id} ${om.pin.buildId}, ${om.r2.length} objects; new: pin ${nm.pin.id} ${nm.pin.buildId}, ${nm.r2.length} objects${om.pin.buildId === nm.pin.buildId ? ' (SAME runtime: not the case this scenario is for)' : ''}`);
const live = new Map(om.r2.map((o) => [o.key, o]));
const by = { '1-objects': [], '2-manifests': [], '3-indexes': [] };
for (const o of nm.r2) by[phaseOf(o)].push(o);
const p12 = [...by['1-objects'], ...by['2-manifests']], p3 = by['3-indexes'];
// phases 1-2 go up while the old shell is live. A digest-named object (phase 1) can never change under its name; a
// phase-2 manifest that replaces a live one (runtime/runtime-manifest.json on a runtime change: the old shell fetches its
// per-build runtime-manifest.<bid>.json first) is listed, and the old boots below are what decides whether it matters.
// A replaced PACK manifest (profiles/<p>.manifest.json: one URL for every release, so a release that changes the packs
// replaces it) is the E1 hazard itself: from phase 2 until the new Worker is deployed, an old shell that installs the
// pack reads the new release's manifest and parts (a shell before QED64 HARDENING #81 checks no release). Listed apart.
const changed12 = p12.filter((o) => live.has(o.key) && live.get(o.key).sha256 !== o.sha256);
for (const o of changed12.filter((x) => phaseOf(x) === '1-objects')) fail(`phase 1 would change the live digest-named object ${o.key}`);
const replaced2 = changed12.filter((o) => phaseOf(o) === '2-manifests').map((o) => o.key);
fs.writeFileSync(path.join(O, 'p12-replaced-keys.txt'), replaced2.join('\n') + '\n');
const hazard2 = changed12.filter((o) => phaseOf(o) === '2-manifests' && /^\/profiles\/[^/]+\.manifest\.json$/.test(o.url)).map((o) => o.key);
fs.writeFileSync(path.join(O, 'p12-e1-hazard-keys.txt'), hazard2.join('\n') + '\n');
const bareRe = new RegExp(`^${(nm.options.prefix || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}snapshots/widgets[78]/`);
for (const o of nm.r2.filter((x) => bareRe.test(x.key) && live.has(x.key) && live.get(x.key).sha256 !== x.sha256)) fail(`the new manifest rewrites the live bare overlay object ${o.key}`);
const window3 = p3.filter((o) => live.has(o.key) && live.get(o.key).sha256 !== o.sha256).map((o) => o.key);
const shared = p12.filter((o) => live.has(o.key)).length;
console.log(`phases 1-2: ${p12.length} objects (${shared - changed12.length} already live with the same sha256, ${p12.length - shared} new keys); live objects they REPLACE: ${replaced2.join(', ') || 'none'} (phase-2 manifests only)`);
if (hazard2.length) console.log(`phase 2 REPLACES ${hazard2.length} live pack manifest(s) under the same URL (E1 hazard, window: phase 2 -> the new Worker deploy): ${hazard2.join(', ')}`);
console.log(`phase 3: ${p3.length} indexes; the ones that REPLACE a live object (the E1 window): ${window3.join(', ') || 'none'}`);
fs.writeFileSync(path.join(O, 'window-keys.txt'), window3.join('\n') + '\n');
for (const [name, list] of [['p12', p12], ['p3', p3]]) {
  const root = path.join(O, `${name}-bucket`, path.basename(bucketRoot));
  for (const o of list) {
    const src = path.join(bucketRoot, o.key), dst = path.join(root, o.key);
    let st = null; try { st = fs.statSync(src); } catch { /* missing */ }
    if (!st || st.size !== o.size) { fail(`${src}: ${st ? `${st.size} B` : 'missing'} (want ${o.size}; rebuild the new pin's rehearsal bucket: scripts/deploy-rehearsal/rehearse.sh upload)`); continue; }
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    try { fs.linkSync(src, dst); } catch { fs.copyFileSync(src, dst, fs.constants.COPYFILE_FICLONE); }
  }
  fs.writeFileSync(path.join(O, `${name}-manifest.json`), JSON.stringify({ ...nm, r2: list }));
}
console.log(bad ? `OLD-SHELL PREP FAILED (${bad})` : `OLD-SHELL PREP OK: subsets p12 (${p12.length}) and p3 (${p3.length}) under ${O}`);
process.exit(bad ? 1 : 0);
EOF
}

# The stock-page boot check (CommonJS, playwright resolved from the checkout's node_modules)
write_stock_boot() {
  cat > "$RUN/old-shell/stock-boot.cjs" <<'EOF'
// written by ci/rehearse-deploy.sh (old-shell): ONE cold boot of the stock QED64 page at "/?rehearsal=stock" (a query, so
// ROOT_REDIRECT never applies; no ?snapshots=, so the shell reads its DEFAULT indexes) in a fresh profile. Waits for
// globalThis.qed64.status().phase ready (or dead / headerRefused, or 420 s). Prints STOCK-BOOT OK / FAILED.
const fs = require('fs'), path = require('path');
const [sc, origin, outDir, tag] = process.argv.slice(2);
const { chromium } = require(require.resolve('playwright', { paths: [sc] }));
(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const out = { origin, tag, startedAt: new Date().toISOString(), indexes: [], hosts: {}, consoleErrors: [], pageErrors: [] };
  const browser = await chromium.launch({ headless: true, args: ['--enable-features=SharedArrayBuffer'] });
  let s = null;
  try {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    ctx.on('request', (q) => { try { const h = new URL(q.url()).host; if (h) out.hosts[h] = (out.hosts[h] || 0) + 1; } catch { /* data: */ } });
    ctx.on('response', (r) => { try { const u = new URL(r.url()); if (/\.json$/.test(u.pathname) && /^\/(snapshots|profiles|runtime)\//.test(u.pathname)) out.indexes.push(`${r.status()} ${u.pathname}`); } catch { /* ignore */ } });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => out.pageErrors.push(String(e.message).slice(0, 200)));
    page.on('console', (m) => { if (m.type() === 'error' && out.consoleErrors.length < 10) out.consoleErrors.push(m.text().slice(0, 300)); });
    const t0 = Date.now();
    await page.goto(`${origin}/?rehearsal=stock`, { waitUntil: 'domcontentloaded', timeout: 120000 });
    for (;;) {
      s = await page.evaluate(() => { const q = globalThis.qed64; if (!q || typeof q.status !== 'function') return null; const x = q.status(); return { phase: x.phase, version: x.version || null }; }).catch(() => null);
      if (s && ['ready', 'dead', 'headerRefused'].includes(s.phase)) break;
      if (Date.now() - t0 > 420000) break;
      await new Promise((r) => setTimeout(r, 500));
    }
    out.bootMs = Date.now() - t0; out.status = s;
    out.isolated = await page.evaluate(() => globalThis.crossOriginIsolated).catch(() => null);
    await page.screenshot({ path: path.join(outDir, 'stock.png') }).catch(() => {});
  } finally { await browser.close().catch(() => {}); }
  const host = new URL(origin).host;
  const ok = !!(s && s.phase === 'ready' && out.isolated && Object.keys(out.hosts).every((h) => h === host));
  fs.writeFileSync(path.join(outDir, 'stock.json'), JSON.stringify(out, null, 1) + '\n');
  console.log(`indexes: ${out.indexes.join(', ')}; console errors: ${out.consoleErrors.slice(0, 3).join(' | ') || 'none'}`);
  console.log(`${ok ? 'STOCK-BOOT OK' : 'STOCK-BOOT FAILED'} ${origin}/?rehearsal=stock: phase ${s && s.phase} after ${(out.bootMs / 1000).toFixed(0)} s, crossOriginIsolated ${out.isolated}`);
  process.exit(ok ? 0 : 1);
})().catch((e) => { console.log(`STOCK-BOOT FAILED ${e.message}`); process.exit(1); });
EOF
}

old_shell() {
  local O="$RUN/old-shell" errs=() oref newsc oldsc cfg_old cfg_new t
  [ -n "${OLD_REF:-}" ] || { echo "SCENARIO SKIP old-shell: OLD_REF is not set (the commit the LIVE shell was deployed from)"; SKIPPED+=(old-shell); return 0; }
  oref=$(git -C "$ROOT" rev-parse "${OLD_REF}^{commit}" 2>/dev/null) || { fail old-shell "OLD_REF $OLD_REF is not a commit of $ROOT"; return 0; }
  OS_STATE=${OLD_STATE:-$W/deploy-rehearsal/state}
  OS_OLD_MANIFEST=${OLD_MANIFEST:-}
  if [ -z "$OS_OLD_MANIFEST" ]; then
    t=$(find "$SC/out/deploy/published" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort | tail -1)
    OS_OLD_MANIFEST=${t:+$t/manifest.json}
  fi
  OS_NEW_MANIFEST=${NEW_MANIFEST:-$SC/out/deploy-rehearsal/deploy/manifest.json}
  OS_NEW_BUCKET=${NEW_BUCKET_DIR:-$(dirname "$SRC_STATE")/bucket}
  OS_BUCKET=$(cd "$SC" && node --input-type=module -e "import { loadDeployEnv } from './scripts/lib/deploy-env.mjs'; console.log(loadDeployEnv().R2_BUCKET)")
  [ -d "$OS_STATE" ] || { fail old-shell "no OLD_STATE $OS_STATE (a wrangler dev state holding the live pin's objects)"; return 0; }
  [ "$(cd "$OS_STATE" && pwd -P)" != "$(cd "$SRC_STATE" && pwd -P)" ] || { fail old-shell "OLD_STATE is REHEARSAL_SRC_STATE ($SRC_STATE): rebuild the new pin's rehearsal state into another REHEARSAL_DIR, keep the live one"; return 0; }
  [ -f "$OS_OLD_MANIFEST" ] || { fail old-shell "no OLD_MANIFEST (${OS_OLD_MANIFEST:-none under $SC/out/deploy/published})"; return 0; }
  [ -f "$OS_NEW_MANIFEST" ] || { fail old-shell "no NEW_MANIFEST $OS_NEW_MANIFEST (scripts/deploy-rehearsal/rehearse.sh upload for the new pin)"; return 0; }
  mkdir -p "$O"
  echo "== scenario old-shell: live shell at ${oref:0:12} (OLD_STATE $OS_STATE, OLD_MANIFEST ${OS_OLD_MANIFEST#"$SC"/}), new at ${REF:0:12} (NEW_MANIFEST ${OS_NEW_MANIFEST#"$SC"/}), orders ${OLD_SHELL_ORDERS:-A B}"
  old_shell_prep > "$O/prep.log" 2>&1 || { tail -5 "$O/prep.log"; fail old-shell "prep (log $O/prep.log)"; return 0; }
  tail -4 "$O/prep.log"
  write_stock_boot
  # the live objects + the new phases 1-2 on top (nothing deleted): one state, cloned per order
  cp -cR "$OS_STATE" "$O/state-12" || { fail old-shell "cannot clone OLD_STATE"; return 0; }
  oload "$O/state-12" p12 || { fail old-shell "loading phases 1-2 on top of OLD_STATE (log $O/load-p12-old-shell.log)"; return 0; }
  local order first=1
  for order in ${OLD_SHELL_ORDERS:-A B}; do
    case "$order" in A|B) ;; *) errs+=("OLD_SHELL_ORDERS: unknown order $order (A, B)"); continue ;; esac
    local D="$O/$order"; mkdir -p "$D"
    OS_SRVLOG="$D/server/wrangler-dev.log"   # every server of this order (oserve, the shim's deploys) logs requests there
    echo "-- old-shell order $order: $([ "$order" = A ] && echo 'phase 3 BEFORE the new Worker' || echo 'phase 3 AFTER the new Worker')"
    cfg_old=""; oldsc=""
    if [ "$first" = 1 ] || [ "$order" = A ]; then
      # 1. the OLD Worker and shell are live BEFORE the upload starts (the real order of events): the old commit's own
      #    workflow (fresh clone at OLD_REF) deploys over a pristine clone of OLD_STATE, its published check and smoke
      #    against exactly the live objects. The live stand-in (placeholder shell, this checkout's Worker) gives it an origin.
      cp -cR "$OS_STATE" "$D/state" || { errs+=("$order: cannot clone OLD_STATE"); continue; }
      oserve "$D" "$RUN/live/wrangler.toml" || { errs+=("$order: stand-in did not start"); continue; }
      shim_env "$D/state" "$OLD_PORT" "$D/server"
      if runlocal "old-shell-$order-old" 0 --ref "$oref" --event push "${SECRETS[@]}" --var "SHOWCASE_ORIGIN=http://127.0.0.1:$OLD_PORT" "${SHIM_ENV[@]}"; then
        has "old-shell-$order-old" 'PUBLISHED OK' && has "old-shell-$order-old" 'Deployed \(rehearsal' && has "old-shell-$order-old" 'SMOKE OK' \
          || errs+=("$order: the old workflow did not show PUBLISHED OK, the deploy and SMOKE OK on the live objects ($RUN/old-shell-$order-old.log)")
      else errs+=("$order: the old workflow failed on the live objects ($RUN/old-shell-$order-old.log)"); fi
      cfg_old=$(oconfig "old-shell-$order-old"); oldsc=${cfg_old%/wrangler.toml}
      [ -n "$cfg_old" ] || { errs+=("$order: no wrangler.toml from the old deploy"); ostop "$D" || true; continue; }
      # then phases 1-2 go up under the running old Worker: the old Worker stopped, its state swapped for OLD_STATE + p12
      ostop "$D" || true
      rm -rf "$D/state"
    fi
    cp -cR "$O/state-12" "$D/state" || { errs+=("$order: cannot clone the phase 1-2 state"); continue; }
    # the old Worker (or, for a later order B, the stand-in) serves OLD_STATE + the new phases 1-2
    oserve "$D" "${cfg_old:-$RUN/live/wrangler.toml}" || { errs+=("$order: the $([ -n "$cfg_old" ] && echo 'old Worker' || echo stand-in) did not start over phases 1-2"); continue; }
    if [ "$first" = 1 ]; then   # once: the state is the same in both orders up to here
      # 2. the live manifest's own --published (every bare snapshots/widgets{7,8}/ object included) WITHOUT the phase-2
      #    manifests that replace live ones (p12-replaced-keys.txt, e.g. runtime/runtime-manifest.json on a runtime change:
      #    it names the new buildId by design; profiles/<p>.manifest.json when the release changes the packs: the E1
      #    hazard, p12-e1-hazard-keys.txt); those are checked separately to serve exactly the NEW manifest's bytes
      mkdir -p "$O/published-old"
      node -e 'const fs=require("fs");const m=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
        const drop=new Set(fs.readFileSync(process.argv[2],"utf8").split("\n").filter(Boolean));
        const r2=m.r2.filter(o=>!drop.has(o.key)); fs.writeFileSync(process.argv[3],JSON.stringify({...m,r2},null,1)+"\n");
        console.log(`OLD_MANIFEST without the ${m.r2.length-r2.length} phase-2 key(s) phases 1-2 replace: ${r2.length} objects`)' \
        "$OS_OLD_MANIFEST" "$O/p12-replaced-keys.txt" "$O/published-old/manifest.json" > "$O/published-old.log" 2>&1 \
        || errs+=("cannot write the filtered OLD_MANIFEST ($O/published-old.log)")
      if (cd "$SC" && node scripts/deploy-manifest.mjs --published "http://127.0.0.1:$OLD_PORT" --out "$O/published-old") >> "$O/published-old.log" 2>&1; then
        tail -1 "$O/published-old.log"
      else errs+=("OLD_MANIFEST --published (without the replaced phase-2 keys) FAILED with phases 1-2 on top ($O/published-old.log)"); fi
      # A replaced pack manifest is not "expected": it is printed as an E1 HAZARD with the release it now serves and the
      # one the LIVE /profiles/index.json (phase 3, not replaced yet) still names, and becomes an E1 MEASURE line below
      node -e 'const fs=require("fs"),{createHash}=require("crypto");
        const [oldP,newP,keysP,origin]=process.argv.slice(1);const om=JSON.parse(fs.readFileSync(oldP,"utf8")),nm=JSON.parse(fs.readFileSync(newP,"utf8"));
        const keys=fs.readFileSync(keysP,"utf8").split("\n").filter(Boolean);let bad=0,hz=0,idx;
        const liveIndex=async()=>(idx??=await fetch(origin+"/profiles/index.json").then((r)=>r.json()).catch(()=>null));
        (async()=>{for(const k of keys){const o=om.r2.find(x=>x.key===k),n=nm.r2.find(x=>x.key===k);
          if(!o||!n){bad++;console.log(`FAIL replaced ${k}: not in both manifests`);continue;}
          const r=await fetch(origin+n.url,{headers:{"accept-encoding":"identity"}}).catch(e=>({status:`ERR ${e.message}`,arrayBuffer:async()=>new ArrayBuffer(0)}));
          const body=Buffer.from(await r.arrayBuffer());const h=createHash("sha256").update(body).digest("hex");
          if(!(r.status===200&&h===n.sha256)){bad++;console.log(`FAIL replaced ${n.url}: status ${r.status} sha256 ${h.slice(0,16)}… != new ${n.sha256.slice(0,16)}…`);continue;}
          if(/^\/profiles\/[^/]+\.manifest\.json$/.test(n.url)){hz++;let rel="?";try{rel=JSON.parse(body.toString("utf8")).content.release;}catch{}
            const li=await liveIndex();const e=li&&Array.isArray(li.profiles)?li.profiles.find((p)=>p.manifest===n.url):null;
            console.log(`E1 HAZARD ${n.url}: replaced under the same URL by phase 2, serves the NEW manifest sha256 ${h.slice(0,16)}… (release ${rel}; live was ${o.sha256.slice(0,16)}…) while the live /profiles/index.json names release ${e?e.release:"(no entry)"}`);}
          else console.log(`REPLACED (expected) ${n.url}: serves the new manifest sha256 ${h.slice(0,16)}… (live was ${o.sha256.slice(0,16)}…)`);}
          console.log(bad?`REPLACED-KEYS FAILED (${bad})`:`REPLACED-KEYS OK ${keys.length}${hz?` (${hz} of them an E1 HAZARD: a pack manifest)`:""}`);process.exit(bad?1:0);})()' \
        "$OS_OLD_MANIFEST" "$O/p12-manifest.json" "$O/p12-replaced-keys.txt" "http://127.0.0.1:$OLD_PORT" >> "$O/published-old.log" 2>&1 \
        && tail -1 "$O/published-old.log" || errs+=("a replaced phase-2 key does not serve the new manifest's bytes ($O/published-old.log)")
      { grep '^E1 HAZARD ' "$O/published-old.log" || true; } | while IFS= read -r l; do
        measure "phase 2 hazard (window: from phase 2 until the new Worker is deployed, in either order; an old tab left open after the deploy too): ${l#E1 HAZARD }"
      done
      node -e 'const m=require(process.argv[1]);const re=new RegExp("^/snapshots/widgets[78]/");const b=m.r2.filter(o=>re.test(o.url));
        console.log(`bare overlay objects of the live manifest: ${b.length} (${b.map(o=>o.url.split("/").slice(2).join("/")).join(", ")}), each checked by the --published above`)' "$OS_OLD_MANIFEST" | tee -a "$O/published-old.log"
      # 3. the old gallery and the old stock page boot with the new phases 1-2 present
      ogallery "$oldsc" "old-gallery-p12" || errs+=("the old gallery did not boot with phases 1-2 present ($O/boot-old-gallery-p12.log)")
      ostock "old-stock-p12" || errs+=("the old stock page did not boot with phases 1-2 present ($O/boot-old-stock-p12.log)")
      first=0
    fi
    if [ "$order" = A ]; then
      # 4A. phase 3 while the OLD Worker still serves (what a non-split upload does): measure the window
      ostop "$D" || true
      if oload "$D/state" p3; then
        oserve "$D" "$cfg_old" || errs+=("A: the old Worker did not restart")
        if ostock "A-window-old-stock"; then measure "A (phase 3 before the deploy): the OLD shell's bare / stock boot in the window: OK"
        else measure "A (phase 3 before the deploy): the OLD shell's bare / stock boot in the window: FAILED (indexes replaced: $(tr '\n' ' ' < "$O/window-keys.txt"); $O/boot-A-window-old-stock.log)"; fi
        if ogallery "$oldsc" "A-window-old-gallery"; then measure "A: the OLD gallery in the window: OK"
        else measure "A: the OLD gallery in the window: FAILED ($O/boot-A-window-old-gallery.log)"; fi
      else errs+=("A: loading phase 3 failed"); fi
      # 5A. the NEW workflow: published check (everything is up), deploy, smoke
      shim_env "$D/state" "$OLD_PORT" "$D/server"
      if runlocal "old-shell-A-new" 0 --event push "${SECRETS[@]}" --var "SHOWCASE_ORIGIN=http://127.0.0.1:$OLD_PORT" "${SHIM_ENV[@]}"; then
        has old-shell-A-new 'PUBLISHED OK' && has old-shell-A-new 'Deployed \(rehearsal' && has old-shell-A-new 'SMOKE OK' \
          || errs+=("A: the new workflow did not show PUBLISHED OK, the deploy and SMOKE OK ($RUN/old-shell-A-new.log)")
      else errs+=("A: the new workflow failed ($RUN/old-shell-A-new.log)"); fi
      cfg_new=$(oconfig old-shell-A-new); newsc=${cfg_new%/wrangler.toml}
      [ -n "$newsc" ] && { ogallery "$newsc" "A-new-gallery" || errs+=("A: the new gallery did not boot ($O/boot-A-new-gallery.log)"); }
      ostock "A-new-stock" || errs+=("A: the new stock page did not boot ($O/boot-A-new-stock.log)")
    else
      # 4B. split upload: the new Worker first. Does the CI published check accept the missing phase 3? (measured)
      shim_env "$D/state" "$OLD_PORT" "$D/server"   # (should the check pass, its deploy replaces the server like any other)
      local rcci=0
      node "$ROOT/ci/run-local.mjs" --workflow "$WF" --ref "$REF" --out "$RUN/old-shell-B-ci" --event push "${SECRETS[@]}" \
        --var "SHOWCASE_ORIGIN=http://127.0.0.1:$OLD_PORT" "${SHIM_ENV[@]}" > "$RUN/old-shell-B-ci.log" 2>&1 || rcci=$?
      if [ "$rcci" != 0 ] && has old-shell-B-ci 'PUBLISHED FAILED'; then measure "B (phase 3 after the deploy): the CI published check REFUSES the deploy before phase 3 (rc $rcci): a split upload needs that check relaxed for phase-3 objects, or a manual deploy"
      else measure "B: the CI published check before phase 3: rc $rcci ($(grep -m1 -oE 'PUBLISHED (OK|FAILED)' "$RUN/old-shell-B-ci.log" || echo 'no PUBLISHED line'); $RUN/old-shell-B-ci.log)"; fi
      # the new Worker deployed without the published check (the "first deploy" path), its smoke measured
      shim_env "$D/state" "$OLD_PORT" "$D/server"
      local rcnew=0
      node "$ROOT/ci/run-local.mjs" --workflow "$WF" --ref "$REF" --out "$RUN/old-shell-B-new" --event push "${SECRETS[@]}" "${SHIM_ENV[@]}" \
        > "$RUN/old-shell-B-new.log" 2>&1 || rcnew=$?
      has old-shell-B-new 'Deployed \(rehearsal' || errs+=("B: the new Worker was not deployed ($RUN/old-shell-B-new.log)")
      measure "B: the new Worker's post-deploy smoke before phase 3: $(has old-shell-B-new 'SMOKE OK' && echo OK || echo "FAILED (rc $rcnew)")"
      cfg_new=$(oconfig old-shell-B-new); newsc=${cfg_new%/wrangler.toml}
      [ -n "$cfg_new" ] || { errs+=("B: no wrangler.toml from the new deploy"); ostop "$D" || true; continue; }
      if ogallery "$newsc" "B-window-new-gallery"; then measure "B: the NEW gallery in the window (no phase 3 yet): OK"
      else measure "B: the NEW gallery in the window (no phase 3 yet): FAILED ($O/boot-B-window-new-gallery.log)"; fi
      if ostock "B-window-new-stock"; then measure "B: the NEW shell's bare / stock boot in the window: OK"
      else measure "B: the NEW shell's bare / stock boot in the window: FAILED ($O/boot-B-window-new-stock.log)"; fi
      # 5B. phase 3, then everything must be OK
      ostop "$D" || true
      oload "$D/state" p3 || errs+=("B: loading phase 3 failed")
      oserve "$D" "$cfg_new" || errs+=("B: the new Worker did not restart")
      if (cd "$SC" && node scripts/deploy-manifest.mjs --published "http://127.0.0.1:$OLD_PORT" --out "$newsc/out/deploy") > "$D/published-new.log" 2>&1 \
         && (cd "$SC" && node scripts/deploy-manifest.mjs --smoke "http://127.0.0.1:$OLD_PORT" --out "$newsc/out/deploy" --all --range) > "$D/smoke-new.log" 2>&1; then
        tail -1 "$D/published-new.log"; tail -1 "$D/smoke-new.log"
      else errs+=("B: after phase 3 the new manifest's --published / --smoke failed ($D/published-new.log, $D/smoke-new.log)"); fi
      ogallery "$newsc" "B-new-gallery" || errs+=("B: the new gallery did not boot after phase 3 ($O/boot-B-new-gallery.log)")
      ostock "B-new-stock" || errs+=("B: the new stock page did not boot after phase 3 ($O/boot-B-new-stock.log)")
    fi
    ostop "$D" || true
  done
  if [ ${#errs[@]} = 0 ]; then
    pass old-shell "phases 1-2 changed no digest-named or bare overlay object (replaced manifests: $(tr '\n' ' ' < "$O/p12-replaced-keys.txt")$(grep -q . "$O/p12-e1-hazard-keys.txt" 2>/dev/null && echo "; of them E1 hazards, pack manifests: $(tr '\n' ' ' < "$O/p12-e1-hazard-keys.txt")")); old workflow + OLD_MANIFEST published OK; old gallery + stock boot OK; after phase 3 + the new Worker: published, SMOKE and new boots OK (orders ${OLD_SHELL_ORDERS:-A B}); E1 measured ($O/e1-measure.txt)"
  else
    local e; for e in "${errs[@]}"; do echo "  old-shell: $e"; done
    fail old-shell "${#errs[@]} check(s) failed (see above; E1 measurements in $O/e1-measure.txt)"
  fi
}

scenario() {
  case "$1" in
  skip)
    runlocal skip 0 --event push || return 0
    if has skip 'CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID not set — skipping deploy' \
       && [ "$(grep -c 'SKIPPED' "$RUN/skip.log")" -ge 8 ] && ! has skip 'step ([2-9]|[1-9][0-9]) (SUCCESS|FAILURE)'; then
      pass skip "the skip line, and every step after the gate skipped"
    else fail skip "expected the skip line and no further step (log $RUN/skip.log)"; fi ;;
  dry-run)
    shim_env "$RUN/state" "$PORT" "$RUN/dry-run-shim"
    runlocal dry-run 0 --event workflow_dispatch --input dry_run=true "${SHIM_ENV[@]}" || return 0
    if has dry-run 'DEPLOY DRY RUN OK' && has dry-run 'deploy mode: dry-run' && has dry-run 'PUBLISHED CHECK SKIPPED' && ! has dry-run 'step [0-9]+ SUCCESS.*Smoke'; then
      pass dry-run "everything up to wrangler deploy --dry-run, without secrets; no smoke"
    else fail dry-run "expected DEPLOY DRY RUN OK and no smoke (log $RUN/dry-run.log)"; fi ;;
  unpublished)
    shim_env "$RUN/empty-state" "$EMPTY_PORT" "$RUN/unpublished-shim"
    runlocal unpublished 1 --event push "${SECRETS[@]}" --var "SHOWCASE_ORIGIN=http://127.0.0.1:$EMPTY_PORT" \
      "${SHIM_ENV[@]}" || return 0
    if has unpublished 'PUBLISHED FAILED' && has unpublished 'are not \(all\) published' && [ ! -e "$RUN/unpublished-shim/wrangler-dry-run" ]; then
      pass unpublished "the published check refused an origin without the artifacts; wrangler was never called"
    else fail unpublished "expected PUBLISHED FAILED before any wrangler call (log $RUN/unpublished.log)"; fi ;;
  deploy)
    shim_env "$RUN/state" "$PORT" "$RUN/server"
    runlocal deploy 0 --event push "${SECRETS[@]}" --var "SHOWCASE_ORIGIN=http://127.0.0.1:$PORT" "${SHIM_ENV[@]}" || return 0
    if has deploy 'PUBLISHED OK http://127.0.0.1:'"$PORT" && has deploy 'Deployed \(rehearsal' && has deploy 'SMOKE OK' \
       && has deploy 'G2 UX: verdict run .*committed record infra/ux-verdict.json' && [ -d "$RUN/server/wrangler-dry-run" ]; then
      pass deploy "G2 from the committed verdict, published check OK, wrangler deploy --dry-run + wrangler dev, SMOKE OK"
    else fail deploy "expected PUBLISHED OK, the rehearsal deploy and SMOKE OK (log $RUN/deploy.log)"; fi ;;
  first)
    shim_env "$RUN/state" "$PORT" "$RUN/server"
    runlocal first 0 --event push "${SECRETS[@]}" "${SHIM_ENV[@]}" || return 0
    if has first 'PUBLISHED CHECK SKIPPED' && has first "DEPLOYED-URL http://127.0.0.1:$PORT" && has first 'SMOKE OK'; then
      pass first "published check skipped (no SHOWCASE_ORIGIN), smoke on the URL the deploy printed"
    else fail first "expected the skip line, DEPLOYED-URL and SMOKE OK (log $RUN/first.log)"; fi ;;
  no-verdict)
    # a scratch clone with ONE extra commit that changes the gallery (a CSS comment) and nothing else
    local S="$RUN/no-verdict-repo"
    git clone --quiet --no-checkout "$ROOT" "$S" && git -C "$S" checkout --quiet "$REF"
    printf '\n/* rehearsal: a gallery change without a new UX verdict */\n' >> "$S/qed64-showcase/gallery/gallery.css"
    git -C "$S" -c user.name=rehearsal -c user.email=rehearsal@localhost commit --quiet -am "rehearsal: gallery change without a verdict"
    shim_env "$RUN/state" "$PORT" "$RUN/no-verdict-shim"
    runlocal no-verdict 1 --repo "$S" --ref "$(git -C "$S" rev-parse HEAD)" --event push "${SECRETS[@]}" --var "SHOWCASE_ORIGIN=http://127.0.0.1:$PORT" \
      "${SHIM_ENV[@]}" || return 0
    if has no-verdict 'no verdict UX run for exactly this gallery' && [ ! -e "$RUN/no-verdict-shim/wrangler-dry-run" ]; then
      pass no-verdict "G2 refused a gallery that infra/ux-verdict.json does not name; wrangler was never called"
    else fail no-verdict "expected the G2 refusal (log $RUN/no-verdict.log)"; fi ;;
  tamper)
    local M; M=$(find "$RUN/deploy" -path '*qed64-showcase/out/deploy/manifest.json' | head -1)
    [ -n "$M" ] || { fail tamper "no manifest from the deploy scenario"; return 0; }
    mkdir -p "$RUN/tamper/out"
    # the widgets8 overlay index at the directory THIS manifest serves it from (options.overlayDirs, deploy-manifest.mjs;
    # a manifest written before that field existed served the bare name)
    local IXU
    IXU=$(node -e 'const fs=require("fs");const m=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
      const u=`/snapshots/${(m.options.overlayDirs||{}).widgets8||"widgets8"}/index.json`;
      const ix=m.r2.find(o=>o.url===u); if(!ix){console.error(`no ${u} in the manifest`);process.exit(1);} ix.sha256="0".repeat(64);
      const big=m.r2.find(o=>o.immutable&&o.url.endsWith(".snapz")); big.size+=1;
      fs.writeFileSync(process.argv[2],JSON.stringify(m)); console.log(u);' "$M" "$RUN/tamper/out/manifest.json") \
      || { fail tamper "the deploy scenario's manifest has no widgets8 overlay index"; return 0; }
    local rc=0
    (cd "$(dirname "$(dirname "$(dirname "$M")")")" && node scripts/deploy-manifest.mjs --published "http://127.0.0.1:$PORT" --out "$RUN/tamper/out") > "$RUN/tamper.log" 2>&1 || rc=$?
    tail -4 "$RUN/tamper.log"
    if [ "$rc" = 1 ] && grep -qF "FAIL $IXU" "$RUN/tamper.log" && has tamper 'content-length [0-9]+ != [0-9]+' && has tamper 'PUBLISHED FAILED'; then
      pass tamper "--published caught a wrong index sha256 ($IXU) and a wrong object size"
    else fail tamper "expected two FAIL lines (one for $IXU) and PUBLISHED FAILED, rc 1 (got rc $rc; log $RUN/tamper.log)"; fi ;;
  old-shell)
    old_shell ;;
  *) die "unknown scenario $1" ;;
  esac
}
SCEN=("$@"); [ ${#SCEN[@]} -gt 0 ] || SCEN=(skip dry-run unpublished deploy first no-verdict tamper old-shell)
for s in "${SCEN[@]}"; do scenario "$s"; done
cleanup; trap - EXIT
# the old-shell ports only when that scenario ran (it creates <run>/old-shell; skipped without OLD_REF): a default run on a
# shared host must not fail on someone else's listener on PORT+20 / PORT+30
OS_PORTS=(); [ -d "$RUN/old-shell" ] && OS_PORTS=("$OLD_PORT" "$LOADER_PORT")
for p in "$PORT" "$EMPTY_PORT" ${OS_PORTS[@]+"${OS_PORTS[@]}"}; do
  if lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then fail cleanup "a wrangler dev still listens on $p"; fi
done
echo "run dir: $RUN"
[ -f "$RUN/old-shell/e1-measure.txt" ] && { echo "E1 measurements (old-shell):"; sed 's/^/  /' "$RUN/old-shell/e1-measure.txt"; }
DONE=(); for s in "${SCEN[@]}"; do case " ${SKIPPED[*]-} " in *" $s "*) ;; *) DONE+=("$s") ;; esac; done
[ "$FAILS" = 0 ] && { echo "REHEARSE-DEPLOY OK: ${DONE[*]-}${SKIPPED[*]+ (SKIPPED, not rehearsed: ${SKIPPED[*]})}"; exit 0; }
echo "REHEARSE-DEPLOY FAILED: $FAILS scenario(s)"; exit 1
