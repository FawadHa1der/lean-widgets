#!/bin/bash
# rehearse.sh — the Cloudflare deploy path (docs/DEPLOY-CLOUDFLARE.md) end to end against LOCAL fakes only.
# No Cloudflare account, no R2, no login: every step except `browser` runs under scripts/deploy-rehearsal/offline.sb
# (sandbox-exec: outbound network denied except localhost), rclone runs with RCLONE_CONFIG pointing at an EMPTY
# config file (the real remotes, e.g. qed64-r2, do not even exist for it) and remotes defined only by
# RCLONE_CONFIG_* environment variables, and wrangler runs with metrics off and no API token.
#
#   scripts/deploy-rehearsal/rehearse.sh <step>…     steps, in order:
#     guard        negative controls of the SHARED-BUCKET GUARD: a fake bucket 'rehearsalguard' seeded with sentinel
#                  QED64 root and lean4game/ objects; upload (real, not dry), deploy-app, rollback and --commands with
#                  R2_PREFIX= / R2_PREFIX=lean4game/ / a foreign prefix must all refuse and leave the bucket untouched
#     upload-dry   DRY_RUN=1 scripts/upload-artifacts.sh -> fake remote (must write nothing)
#     upload       scripts/upload-artifacts.sh -> fake remote 'rehearsalr2' = rclone local backend (via an alias) at
#                  $REHEARSAL_DIR/bucket, i.e. objects land at bucket/<R2_BUCKET>/<R2_PREFIX>…
#     upload-s3    scripts/upload-artifacts.sh -> fake remote 'rehearsals3' = rclone s3 backend (provider Cloudflare)
#                  pointed at scripts/deploy-rehearsal/fake-s3.mjs on 127.0.0.1; checks every object's Content-Type
#                  and which ones went multipart against the manifest
#     rollback     scripts/rollback-artifacts.sh on the newest release record of rehearsalr2: a junked index is
#                  restored, the dry run writes nothing, a record whose digest-named object is missing is refused, and
#                  a record made through another remote (rehearsals3) is refused
#     deploy-dry   DRY_RUN=1 scripts/deploy-app.sh with WRANGLER_CONFIG=$REHEARSAL_DIR/wrangler.toml (written from
#                  wrangler.toml.example + infra/deploy.env; `wrangler deploy --dry-run`), after two negative controls
#                  of its release-record cross-check: no record for the remote, and a manifest (small variant) whose
#                  R2 keys differ from the newest upload's
#     load         scripts/deploy-rehearsal/load-r2.mjs: fake bucket -> wrangler dev's local R2 ($REHEARSAL_DIR/state)
#     serve        `wrangler dev --local --persist-to $REHEARSAL_DIR/state` on that same wrangler.toml (background)
#     smoke        deploy-manifest --smoke --all --range, plus curl of a Range GET and of the COOP/COEP headers
#     browser      one boot of /showcase/#hasse-view through scripts/with-browser-lock.sh (no sandbox: Chrome talks
#                  to 127.0.0.1 only)
#     stop         stop the background wrangler dev
#   all = upload-dry guard upload upload-s3 rollback deploy-dry load serve smoke (browser and stop are separate on purpose;
#         upload-dry runs first because it writes \$DEPLOY_OUT/manifest.json, which guard reads)
#
# Env: REHEARSAL_DIR (default work/deploy-rehearsal), DEPLOY_OUT (default out/deploy-rehearsal/deploy, so the
# rehearsal never touches out/deploy), PORT (8790), ALLOW_NO_UX_VERDICT (passed through), MANIFEST_ARGS.
set -euo pipefail
SC="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SC"
RD=${REHEARSAL_DIR:-$(cd "$SC/work" && pwd -P)/deploy-rehearsal}
export DEPLOY_OUT=${DEPLOY_OUT:-out/deploy-rehearsal/deploy}
case "$DEPLOY_OUT" in /*) DO_ABS=$DEPLOY_OUT ;; *) DO_ABS=$SC/$DEPLOY_OUT ;; esac
PORT=${PORT:-8790}
SB="$SC/scripts/deploy-rehearsal/offline.sb"
LOGS="$SC/out/deploy-rehearsal/logs"
mkdir -p "$RD/bucket" "$LOGS"
: > "$RD/empty-rclone.conf"
export RCLONE_CONFIG="$RD/empty-rclone.conf"
export RCLONE_CONFIG_REHEARSALLOCAL_TYPE=local
export RCLONE_CONFIG_REHEARSALR2_TYPE=alias RCLONE_CONFIG_REHEARSALR2_REMOTE="rehearsallocal:$RD/bucket"
export RCLONE_CONFIG_REHEARSALGUARD_TYPE=alias RCLONE_CONFIG_REHEARSALGUARD_REMOTE="rehearsallocal:$RD/guard-bucket"
export RCLONE_CONFIG_REHEARSALS3_TYPE=s3 RCLONE_CONFIG_REHEARSALS3_PROVIDER=Cloudflare \
  RCLONE_CONFIG_REHEARSALS3_ENDPOINT=http://127.0.0.1:9799 RCLONE_CONFIG_REHEARSALS3_ACCESS_KEY_ID=rehearsal \
  RCLONE_CONFIG_REHEARSALS3_SECRET_ACCESS_KEY=rehearsal RCLONE_CONFIG_REHEARSALS3_NO_CHECK_BUCKET=true
export WRANGLER_SEND_METRICS=false
unset CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID
export WRANGLER_CONFIG="$RD/wrangler.toml"
offline() { sandbox-exec -f "$SB" "$@"; }
say() { echo "[rehearsal $(date +%H:%M:%S)] $*"; }
guard_remote() { case "$1" in rehearsalr2|rehearsals3|rehearsalguard) ;; *) echo "refusing: remote '$1' is not a rehearsal fake" >&2; exit 2 ;; esac; }
# Every other knob comes from infra/deploy.env (bucket qed64-artifacts, prefix qed64-showcase/, worker qed64-showcase).
bucket() { node --input-type=module -e "import { loadDeployEnv } from '$SC/scripts/lib/deploy-env.mjs'; console.log(loadDeployEnv().$1)"; }
newest_record() {   # newest release record of rclone remote $1 (the same rule deploy-app.sh uses)
  DEPLOY_OUT="$DO_ABS" bash -c '. "$1/scripts/lib/deploy-common.sh"; newest_record_for_remote "$2"' _ "$SC" "$1"; }
tree_sum() { ( cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s  %s\n' "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$f"; done | shasum -a 256 | cut -d' ' -f1 ); }
# must_refuse <log name> <grep pattern> <command…>: the command must fail and its output must match the pattern
must_refuse() {
  local name=$1 pat=$2; shift 2
  if "$@" > "$LOGS/$name.log" 2>&1; then echo "REHEARSAL FAIL: '$name' was accepted:"; tail -5 "$LOGS/$name.log"; exit 1; fi
  grep -qE -e "$pat" "$LOGS/$name.log" || { echo "REHEARSAL FAIL: '$name' failed for another reason:"; tail -5 "$LOGS/$name.log"; exit 1; }
  local re="$pat.{0,110}" hit      # (a variable: bash 3.2 brace-expands {0,110} inside "$( )")
  hit=$(grep -m1 -oE -e "$re" "$LOGS/$name.log")
  echo "refused as expected ($name): $hit"
}

step() {
  case "$1" in
  guard)
    # The demonstrated hazard: in the SHARED bucket an empty prefix (QED64's root) or lean4game/ would let an upload
    # overwrite another app's runtime-manifest.json / indexes. Sentinels stand in for those production objects.
    guard_remote rehearsalguard
    G="$RD/guard-bucket/$(bucket R2_BUCKET)"
    rm -rf "$RD/guard-bucket"; mkdir -p "$G/runtime" "$G/snapshots" "$G/lean4game/runtime"
    echo '{"who":"QED64 production runtime manifest (sentinel)"}' > "$G/runtime/runtime-manifest.json"
    echo '{"who":"QED64 production snapshots index (sentinel)"}' > "$G/snapshots/index.json"
    echo '{"who":"lean4game runtime manifest (sentinel)"}' > "$G/lean4game/runtime/runtime-manifest.json"
    before=$(tree_sum "$RD/guard-bucket")
    : > "$LOGS/guard.log"
    for pfx in '' 'lean4game/' 'lean4game' 'runtime/' 'snapshots/x/'; do
      tag=${pfx//\//_}; tag=${tag:-empty}
      must_refuse "guard-upload-$tag" 'deploy target refused' env R2_REMOTE=rehearsalguard R2_PREFIX="$pfx" ALLOW_SHARED_PREFIX=1 \
        sandbox-exec -f "$SB" scripts/upload-artifacts.sh | tee -a "$LOGS/guard.log"
    done
    must_refuse guard-upload-other 'ALLOW_SHARED_PREFIX=1 deliberately' env R2_REMOTE=rehearsalguard R2_PREFIX=qed64-showcase-staging/ \
      sandbox-exec -f "$SB" scripts/upload-artifacts.sh | tee -a "$LOGS/guard.log"
    must_refuse guard-deploy-empty 'deploy target refused' env R2_REMOTE=rehearsalguard R2_PREFIX= DRY_RUN=1 \
      sandbox-exec -f "$SB" scripts/deploy-app.sh | tee -a "$LOGS/guard.log"
    must_refuse guard-commands-empty 'deploy target refused' env R2_PREFIX='' node scripts/deploy-manifest.mjs --out "$DEPLOY_OUT" --commands | tee -a "$LOGS/guard.log"
    # a manifest generated with the generator's default prefix '' (QED64's root): --commands must not print commands
    # that would write it into the shared bucket, even with the default target
    [ -f "$DO_ABS/manifest.json" ] || { echo "REHEARSAL FAIL: guard needs $DO_ABS/manifest.json — run 'scripts/deploy-rehearsal/rehearse.sh upload-dry' first (the 'all' step order does this)"; exit 2; }
    rm -rf "$RD/guard-out"; mkdir -p "$RD/guard-out"
    node -e 'const fs=require("fs");const m=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));m.options.prefix="";fs.writeFileSync(process.argv[2],JSON.stringify(m))' \
      "$DO_ABS/manifest.json" "$RD/guard-out/manifest.json"
    must_refuse guard-commands-root-manifest '--commands refused' node scripts/deploy-manifest.mjs --out "$RD/guard-out" --commands | tee -a "$LOGS/guard.log"
    REC0=$(newest_record rehearsalr2)
    if [ -n "$REC0" ]; then
      must_refuse guard-rollback-lean4game 'deploy target refused' env R2_REMOTE=rehearsalguard R2_PREFIX=lean4game/ \
        sandbox-exec -f "$SB" scripts/rollback-artifacts.sh "$REC0" | tee -a "$LOGS/guard.log"
    fi
    # own-bucket mode (R2_BUCKET and R2_PREFIX changed together) is accepted by the same loader
    R2_BUCKET=qed64-showcase-artifacts R2_PREFIX='' node scripts/lib/deploy-env.mjs | tr '\n' ' ' | sed 's/^/own bucket accepted: /' | tee -a "$LOGS/guard.log"; echo
    after=$(tree_sum "$RD/guard-bucket")
    [ "$before" = "$after" ] || { echo "REHEARSAL FAIL: the guard bucket changed"; exit 1; }
    say "GUARD OK: every shared-bucket misuse refused before rclone ran; sentinel bucket unchanged ($(find "$RD/guard-bucket" -type f | wc -l | tr -d ' ') files, tree sha256 ${after:0:16})" | tee -a "$LOGS/guard.log" ;;
  upload-dry)
    guard_remote rehearsalr2
    before=$(find "$RD/bucket" -type f 2>/dev/null | wc -l | tr -d ' ')
    R2_REMOTE=rehearsalr2 DRY_RUN=1 offline scripts/upload-artifacts.sh 2>&1 | tee "$LOGS/upload-dry.log"
    after=$(find "$RD/bucket" -type f 2>/dev/null | wc -l | tr -d ' ')
    [ "$before" = "$after" ] || { echo "REHEARSAL FAIL: the dry run wrote $((after - before)) file(s)"; exit 1; }
    say "upload-dry: fake bucket file count unchanged ($before -> $after)" ;;
  upload)
    guard_remote rehearsalr2
    # A rehearsal is a FIRST upload into an empty fake bucket: the check below ("nothing else in the bucket") proves the
    # upload writes exactly the manifest's keys, which a bucket left over from a rehearsal of another pin (its
    # digest-named objects stay, as they would in R2) cannot show. So the previous fake bucket is moved aside, never
    # reused (multi-pin lane, 2026-10-02: the 9fdf9b8 rehearsal's 17 objects made the 5ac5d00 one fail this check).
    if [ -d "$RD/bucket" ] && [ -n "$(find "$RD/bucket" -type f -print -quit)" ]; then
      prev="$RD/bucket.prev-$(date -u +%Y%m%dT%H%M%SZ)"; mv "$RD/bucket" "$prev"; mkdir -p "$RD/bucket"
      say "upload: the previous fake bucket ($(find "$prev" -type f | wc -l | tr -d ' ') files) moved aside to $prev; uploading into an empty one"
    fi
    R2_REMOTE=rehearsalr2 offline scripts/upload-artifacts.sh 2>&1 | tee "$LOGS/upload.log"
    node - "$DO_ABS" "$RD/bucket/$(bucket R2_BUCKET)" <<'EOF'
// every manifest key is in the fake bucket with its size and sha256, nothing else is there, and the phase order held
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const [out, root] = process.argv.slice(2); const m = JSON.parse(fs.readFileSync(path.resolve(out, 'manifest.json'), 'utf8'));
const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]));
const have = new Set(walk(root).map((f) => path.relative(root, f)));
let bad = 0;
for (const o of m.r2) {
  const f = path.join(root, o.key);
  if (!fs.existsSync(f)) { bad++; console.log(`FAIL missing ${o.key}`); continue; }
  const h = crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
  if (h !== o.sha256 || fs.statSync(f).size !== o.size) { bad++; console.log(`FAIL ${o.key} differs`); }
  have.delete(o.key);
}
for (const k of have) { bad++; console.log(`FAIL unexpected object ${k}`); }
console.log(`${bad ? 'FAKE-BUCKET FAILED' : 'FAKE-BUCKET OK'}: ${m.r2.length} objects under ${m.options.prefix}, size + sha256 equal to the manifest, nothing else in the bucket`);
process.exit(bad ? 1 : 0);
EOF
    ;;
  upload-s3)
    guard_remote rehearsals3
    rm -f "$RD/fake-s3.jsonl"
    offline node scripts/deploy-rehearsal/fake-s3.mjs 9799 "$RD/fake-s3.jsonl" & FS=$!
    sleep 1
    # sandbox-exec runs node as a CHILD, so stop the listener itself, not just $FS
    stop_fake_s3() { kill "$FS" 2>/dev/null || true; pkill -f "fake-s3.mjs 9799 $RD/fake-s3.jsonl" 2>/dev/null || true; }
    R2_REMOTE=rehearsals3 offline scripts/upload-artifacts.sh 2>&1 | tee "$LOGS/upload-s3.log" || { stop_fake_s3; exit 1; }
    stop_fake_s3
    node - "$DO_ABS" "$RD/fake-s3.jsonl" <<'EOF'
// what rclone's s3 backend actually sent: Content-Type per object (== the manifest's), multipart for > 200 MiB, and
// the phase order (no index.json before the last object it could name)
const fs = require('fs'), path = require('path');
const [out, logPath] = process.argv.slice(2); const m = JSON.parse(fs.readFileSync(path.resolve(out, 'manifest.json'), 'utf8'));
const ev = fs.readFileSync(logPath, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const done = new Map(); const order = [];
for (const e of ev) if (e.op === 'PutObject' || e.op === 'CompleteMultipartUpload') { done.set(e.key, e); order.push(e.key); }
const ctOf = new Map(ev.filter((e) => e.op === 'CreateMultipartUpload').map((e) => [e.key, e.contentType]));
let bad = 0; const byType = {};
for (const o of m.r2) {
  const e = done.get(o.key);
  if (!e) { bad++; console.log(`FAIL not uploaded ${o.key}`); continue; }
  const ct = e.contentType ?? ctOf.get(o.key);
  byType[ct] = (byType[ct] || 0) + 1;
  if (ct !== o.contentType) { bad++; console.log(`FAIL ${o.key}: Content-Type ${ct}, want ${o.contentType}`); }
  if (e.size !== o.size) { bad++; console.log(`FAIL ${o.key}: ${e.size} B, want ${o.size}`); }
  if ((e.op === 'CompleteMultipartUpload') !== (o.size > 200 * 1024 * 1024)) { bad++; console.log(`FAIL ${o.key}: multipart ${e.op === 'CompleteMultipartUpload'} for ${o.size} B`); }
}
const pos = (k) => order.indexOf(k);
const lastObject = Math.max(...m.r2.filter((o) => o.phase === 'immutable').map((o) => pos(o.key)));
const firstManifest = Math.min(...m.r2.filter((o) => o.phase === 'mutable').map((o) => pos(o.key)));
const lastManifest = Math.max(...m.r2.filter((o) => o.phase === 'mutable' && !/\/index\.json$/.test(o.url)).map((o) => pos(o.key)));
const firstIndex = Math.min(...m.r2.filter((o) => /\/index\.json$/.test(o.url)).map((o) => pos(o.key)));
if (!(lastObject < firstManifest && lastManifest < firstIndex)) { bad++; console.log(`FAIL phase order: last object #${lastObject}, first manifest #${firstManifest}, last manifest #${lastManifest}, first index #${firstIndex}`); }
const mp = ev.filter((e) => e.op === 'CompleteMultipartUpload');
console.log(`${bad ? 'FAKE-S3 FAILED' : 'FAKE-S3 OK'}: ${done.size} objects received; Content-Type ${JSON.stringify(byType)} == manifest; ${mp.length} multipart (${mp.map((e) => `${e.key.split('/').pop()} ${e.parts} parts`).join(', ')}); phases objects -> manifests -> indexes in order`);
process.exit(bad ? 1 : 0);
EOF
    ;;
  rollback)
    # a bad publish (an index overwritten with junk) is undone from the newest release record, a dry run changes
    # nothing, and a record whose objects are missing from the bucket is refused
    guard_remote rehearsalr2
    REC=$(newest_record rehearsalr2)
    [ -n "$REC" ] || { echo "no release record of rehearsalr2: run upload first"; exit 1; }
    say "rollback: record ${REC##*/} ($(tr '\n' ' ' < "$REC/target.env"))"
    B="$RD/bucket/$(bucket R2_BUCKET)/$(bucket R2_PREFIX)"
    IDX=$(cd "$REC/files" && find . -name index.json | sed 's|^\./||' | sort | tail -1)
    echo "junk" > "$B$IDX"
    R2_REMOTE=rehearsalr2 DRY_RUN=1 offline scripts/rollback-artifacts.sh "$REC" 2>&1 | tee "$LOGS/rollback-dry.log"
    [ "$(cat "$B$IDX")" = junk ] || { echo "REHEARSAL FAIL: the rollback dry run wrote"; exit 1; }
    R2_REMOTE=rehearsalr2 offline scripts/rollback-artifacts.sh "$REC" 2>&1 | tee "$LOGS/rollback.log"
    cmp "$B$IDX" "$REC/files/$IDX" && say "rollback: $IDX restored byte-identical from ${REC##*/}"
    PART=$(cd "$B" && find . -name '*.part-*' | sed 's|^\./||' | sort | head -1)
    mv "$B$PART" "$RD/held-out.part"
    if R2_REMOTE=rehearsalr2 offline scripts/rollback-artifacts.sh "$REC" > "$LOGS/rollback-missing.log" 2>&1; then
      mv "$RD/held-out.part" "$B$PART"; echo "REHEARSAL FAIL: rollback accepted a record whose object $PART is missing"; exit 1; fi
    mv "$RD/held-out.part" "$B$PART"
    grep -E "MISSING|not in the bucket" "$LOGS/rollback-missing.log" | head -3
    say "rollback: refused while $PART was missing (negative control), object put back"
    REC3=$(newest_record rehearsals3)
    if [ -n "$REC3" ]; then
      must_refuse rollback-other-remote "uploaded through remote 'rehearsals3'" env R2_REMOTE=rehearsalr2 DRY_RUN=1 \
        sandbox-exec -f "$SB" scripts/rollback-artifacts.sh "$REC3"
    fi ;;
  deploy-dry)
    rm -f "$WRANGLER_CONFIG"
    # release-record cross-check, negative controls first (each regenerates the manifest; the positive run below
    # regenerates the full one again): no record for the remote at all, then R2 keys that differ from the upload's
    must_refuse deploy-dry-no-record 'RECORD MISSING' env R2_REMOTE=rehearsalnorecord DRY_RUN=1 sandbox-exec -f "$SB" scripts/deploy-app.sh
    must_refuse deploy-dry-record-mismatch 'RECORD MISMATCH' env R2_REMOTE=rehearsalr2 DRY_RUN=1 \
      MANIFEST_ARGS="--overlays widgets8 --no-stock-snapshots --no-essential-pack" sandbox-exec -f "$SB" scripts/deploy-app.sh
    [ ! -f "$WRANGLER_CONFIG" ] || { echo "REHEARSAL FAIL: a refused deploy-app wrote $WRANGLER_CONFIG"; exit 1; }
    R2_REMOTE=rehearsalr2 DRY_RUN=1 offline scripts/deploy-app.sh 2>&1 | tee "$LOGS/deploy-dry.log" ;;
  load)
    rm -rf "$RD/state"
    offline node scripts/deploy-rehearsal/load-r2.mjs --bucket-dir "$RD/bucket" --bucket "$(bucket R2_BUCKET)" --persist-to "$RD/state" \
      --manifest "$DO_ABS/manifest.json" 2>&1 | tee "$LOGS/load-r2.log" ;;
  serve)
    [ -f "$WRANGLER_CONFIG" ] || { echo "no $WRANGLER_CONFIG: run deploy-dry first"; exit 1; }
    if [ -f "$RD/wrangler-dev.pid" ] && kill -0 "$(cat "$RD/wrangler-dev.pid")" 2>/dev/null; then say "wrangler dev already running (pid $(cat "$RD/wrangler-dev.pid"))"; return; fi
    ( cd "$RD" && exec sandbox-exec -f "$SB" "$SC/infra/node_modules/.bin/wrangler" dev --config "$WRANGLER_CONFIG" --local \
        --persist-to "$RD/state" --ip 127.0.0.1 --port "$PORT" --inspector-port $((PORT + 1)) --show-interactive-dev-session=false ) \
      > "$LOGS/wrangler-dev.log" 2>&1 < /dev/null &
    echo $! > "$RD/wrangler-dev.pid"
    for _ in $(seq 1 120); do curl -s -o /dev/null "http://127.0.0.1:$PORT/showcase/" && break; sleep 0.5; done
    curl -s -o /dev/null -w "serve: GET /showcase/ -> %{http_code}\n" "http://127.0.0.1:$PORT/showcase/"
    say "wrangler dev (pid $(cat "$RD/wrangler-dev.pid")) serving infra/worker.js at http://127.0.0.1:$PORT (log $LOGS/wrangler-dev.log)" ;;
  smoke)
    O="http://localhost:$PORT"
    node scripts/deploy-manifest.mjs --out "$DEPLOY_OUT" --smoke "$O" --all --range 2>&1 | tee "$LOGS/smoke.log"
    Z=$(node -p 'const m=require(process.argv[1]);m.r2.filter(o=>o.url.endsWith(".snapz")).sort((a,b)=>b.size-a.size)[0].url' "$DO_ABS/manifest.json")
    { echo "\$ curl -s -o /dev/null -D - -H 'Range: bytes=1000000-1000099' $O$Z"
      curl -s -o /dev/null -D - -H 'Range: bytes=1000000-1000099' "$O$Z"
      echo "\$ curl -sI $O/showcase/ | grep -i cross-origin"
      curl -sI "$O/showcase/" | grep -i cross-origin
      echo "\$ curl -sI $O/ (ROOT_REDIRECT)"
      curl -sI "$O/" | grep -iE '^HTTP|^location|cross-origin-embedder'
      echo "\$ curl -sI $O/runtime/runtime-manifest.json"
      curl -sI "$O/runtime/runtime-manifest.json" | grep -iE '^HTTP|content-type|cache-control|accept-ranges'
    } 2>&1 | tee "$LOGS/curl.log" ;;
  browser)
    scripts/with-browser-lock.sh deploy-rehearsal node scripts/deploy-rehearsal/boot-check.mjs "http://localhost:$PORT" "$SC/out/deploy-rehearsal" 2>&1 | tee "$LOGS/browser.log" ;;
  stop)
    if [ -f "$RD/wrangler-dev.pid" ]; then
      pid=$(cat "$RD/wrangler-dev.pid"); pkill -INT -P "$pid" 2>/dev/null || true; kill -INT "$pid" 2>/dev/null || true; sleep 2
      pkill -f "wrangler-dist/cli.js dev --config $WRANGLER_CONFIG" 2>/dev/null || true
      rm -f "$RD/wrangler-dev.pid"
    fi
    sleep 1
    if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then echo "port $PORT still has a listener:"; lsof -nP -iTCP:"$PORT" -sTCP:LISTEN; exit 1; fi
    say "stopped; nothing listens on $PORT" ;;
  *) echo "unknown step $1" >&2; exit 2 ;;
  esac
}
[ $# -gt 0 ] || { sed -n '2,30p' "$0"; exit 2; }
for s in "$@"; do
  if [ "$s" = all ]; then for t in upload-dry guard upload upload-s3 rollback deploy-dry load serve smoke; do say "== $t"; step "$t"; done
  else say "== $s"; step "$s"; fi
done
