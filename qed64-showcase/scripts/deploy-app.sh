#!/bin/bash
# deploy-app.sh — deploy the app shell (the pinned QED64 dist at "/" + the gallery at "/showcase/") as a Cloudflare
# Worker with static assets, "the lean4game way" (wasm64-lean4game/scripts/deploy-app.sh is the model). The R2
# artifacts are uploaded separately and rarely (scripts/upload-artifacts.sh): run that FIRST whenever the pin, the
# overlays or the packs changed, so the shell never points at objects that are not there yet.
# Guide: docs/DEPLOY-CLOUDFLARE.md.
#
#   scripts/deploy-app.sh [wrangler deploy args…]   npx --prefix infra wrangler deploy (needs `wrangler login` or
#                                                   CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID)
#   DRY_RUN=1 scripts/deploy-app.sh                 everything up to `wrangler deploy --dry-run` (bundles the worker,
#                                                   uploads nothing, needs no account)
#   DEPLOY_FROM_LOCK=1 scripts/deploy-app.sh        a checkout WITHOUT the artifacts (GitHub Actions, a fresh clone): the
#                                                   manifest is `deploy-manifest.mjs --from-lock` (shell hashed, R2 keys
#                                                   from the committed lock; the shell must be built from source first:
#                                                   scripts/build-shell.mjs + fetch-artifacts.mjs --git-only). The release
#                                                   record check (a file of the machine that uploaded) is replaced by the
#                                                   PUBLISHED_ORIGIN check below; G2 comes from the committed
#                                                   infra/ux-verdict.json when out/ux is absent.
#   PUBLISHED_ORIGIN=https://… scripts/deploy-app.sh  before deploying, `deploy-manifest.mjs --published <origin>`: every R2
#                                                   object this shell needs answers on the live origin (HEAD size; GET
#                                                   sha256 of every manifest and index). Unset with DEPLOY_FROM_LOCK=1 =
#                                                   the very first deploy (no origin yet): skipped with a log line; the
#                                                   post-deploy `--smoke --all` then checks every R2 key.
#   WRANGLER_BIN=<path>                             another wrangler executable (the local CI rehearsal's stand-in,
#                                                   scripts/deploy-rehearsal/wrangler-shim.sh); default the pinned
#                                                   infra/node_modules/.bin/wrangler (npx --prefix infra wrangler)
#
# Steps: regenerate + check the manifest with the target's prefix (scripts/lib/deploy-common.sh: G1 must pass, G2
# must name a verdict UX run unless ALLOW_NO_UX_VERDICT=1); compare it with the newest release record of R2_REMOTE
# under $DEPLOY_OUT/published (bucket, prefix and every R2 key + sha256 must be what that upload or rollback
# published; ALLOW_UNRECORDED_UPLOAD=1 skips this deliberately); `--stage-assets` into $DEPLOY_OUT/assets (S1/S2: exactly
# the manifest's files, sha256-checked); refuse any file over the 25 MiB Workers asset cap, any artifact directory
# in the tree, or a missing required file; write wrangler.toml from wrangler.toml.example when absent (same
# bucket/prefix as the upload; WRANGLER_CONFIG to use another path) or refuse one that disagrees; then deploy.
# shellcheck disable=SC2016  # single-quoted node snippets use JS template literals on purpose
set -euo pipefail
SC="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SC"
# shellcheck source=scripts/lib/deploy-common.sh
. "$SC/scripts/lib/deploy-common.sh"
load_deploy_env
WRANGLER_CONFIG=${WRANGLER_CONFIG:-$SC/wrangler.toml}
FROM_LOCK=${DEPLOY_FROM_LOCK:-0}
case "$FROM_LOCK" in 0|1) ;; *) die "DEPLOY_FROM_LOCK must be 0 or 1" ;; esac
# shell-only manifest of a checkout without the artifacts (MANIFEST_ARGS reaches the generator; --check reads the source
# back from manifest.json)
[ "$FROM_LOCK" = 1 ] && export MANIFEST_ARGS="--from-lock ${MANIFEST_ARGS:-}"
# wrangler 4.125.0 lives in infra/ (infra/package.json), apart from the root package.json the UX suite uses.
[ -x "$SC/infra/node_modules/.bin/wrangler" ] || npm ci --prefix "$SC/infra" --no-audit --no-fund
if [ -n "${WRANGLER_BIN:-}" ]; then WR=("$WRANGLER_BIN"); echo "wrangler: $WRANGLER_BIN (WRANGLER_BIN)"; else WR=(npx --prefix "$SC/infra" wrangler); fi

manifest_preflight

# The shell must read exactly what the last upload (or rollback) of this remote published: same bucket, same prefix,
# same R2 keys with the same sha256 (the mutable runtime manifest and indexes included). Running the two scripts with
# different env overrides, deploying a re-pinned shell before its upload, or after a rollback, would otherwise only
# show up in the post-deploy smoke as 404s or SNAPSHOT_UNPAIRED. ALLOW_UNRECORDED_UPLOAD=1 skips this deliberately
# (e.g. the upload ran on another machine whose release record you do not have).
REC=$(newest_record_for_remote "$R2_REMOTE")
if [ "$FROM_LOCK" = 1 ]; then
  echo "release-record check: not applicable with DEPLOY_FROM_LOCK=1 (the records live on the machine that uploaded); the published check below takes its place"
elif ! node - "$DEPLOY_OUT/manifest.json" "${REC:-}" "$R2_BUCKET" "$R2_PREFIX" "$R2_REMOTE" <<'JS'
const fs = require('fs'), path = require('path');
const [mPath, rec, bucket, prefix, remote] = process.argv.slice(2);
if (!rec) { console.error(`RECORD MISSING: no release record of remote '${remote}' in ${path.dirname(mPath)}/published: run scripts/upload-artifacts.sh first`); process.exit(1); }
const t = Object.fromEntries(fs.readFileSync(path.join(rec, 'target.env'), 'utf8').trim().split('\n').map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
const cur = JSON.parse(fs.readFileSync(mPath, 'utf8')); const up = JSON.parse(fs.readFileSync(path.join(rec, 'manifest.json'), 'utf8'));
const bad = [];
if (t.bucket !== bucket || t.prefix !== prefix) bad.push(`record target bucket '${t.bucket}' prefix '${t.prefix}' != this deploy's bucket '${bucket}' prefix '${prefix}'`);
const sig = (m) => new Map(m.r2.map((o) => [o.key, `${o.sha256}/${o.size}`]));
const a = sig(cur), b = sig(up);
const diff = [...new Set([...a.keys(), ...b.keys()])].filter((k) => a.get(k) !== b.get(k));
if (diff.length) bad.push(`${diff.length} R2 key(s) differ from what that upload published, e.g. ${diff.slice(0, 3).join(', ')} (pin ${cur.pin.buildId} vs uploaded ${up.pin.buildId})`);
const label = `${path.basename(rec)}${t.rollback_of ? ` (rollback to ${t.rollback_of})` : ''}`;
if (bad.length) { for (const x of bad) console.error(`RECORD MISMATCH vs ${label}: ${x}`); console.error('run scripts/upload-artifacts.sh with the same target and MANIFEST_ARGS first'); process.exit(1); }
console.log(`RECORD OK: this shell's ${a.size} R2 keys (pin ${cur.pin.buildId}, prefix '${prefix}') are what release record ${label} published to ${remote}:${bucket}`);
JS
then
  [ "${ALLOW_UNRECORDED_UPLOAD:-0}" = 1 ] || die "the shell does not match the newest upload of '$R2_REMOTE' (see above); set ALLOW_UNRECORDED_UPLOAD=1 only if you know that bucket holds exactly this manifest's objects"
  echo "WARNING: proceeding without a matching release record because ALLOW_UNRECORDED_UPLOAD=1" >&2
fi

# Are the R2 objects this shell needs already on the live origin? (The release record says what THIS machine uploaded;
# this asks the origin itself.)
if [ -n "${PUBLISHED_ORIGIN:-}" ]; then
  node "$SC/scripts/deploy-manifest.mjs" --published "$PUBLISHED_ORIGIN" --out "$DEPLOY_OUT" \
    || die "the artifacts this shell needs are not (all) published on $PUBLISHED_ORIGIN: upload them first (scripts/upload-artifacts.sh on the machine that has them), nothing deployed"
elif [ "$FROM_LOCK" = 1 ]; then
  echo "PUBLISHED CHECK SKIPPED: PUBLISHED_ORIGIN is not set, i.e. the very first deploy (no live origin to ask yet). The artifacts must have been uploaded with scripts/upload-artifacts.sh; the post-deploy smoke (--smoke --all) checks every R2 key on the new deployment."
fi

node "$SC/scripts/deploy-manifest.mjs" --stage-assets --out "$DEPLOY_OUT" || die "--stage-assets FAILED"
ASSETS="$DEPLOY_OUT/assets"

# Workers static assets cap every file at 25 MiB (`find -size +25M` = more than 25 MiB).
big=$(find "$ASSETS" -type f -size +25M | head -3)
[ -z "$big" ] || { echo "files over the 25 MiB asset cap:" >&2; echo "$big" >&2; exit 3; }
for d in runtime profiles snapshots; do [ ! -e "$ASSETS/$d" ] || die "assets/$d exists: the worker routes /$d/ to R2, it must not be an asset"; done
# The shell hangs at "starting Lean" without its workers, and the gallery cannot boot without its own files.
for f in index.html workers/lean.worker.js workers/lsp-front-door.js workers/lsp-frames.js workers/snapshot-prefetch.worker.js \
         showcase/index.html showcase/gallery.js showcase/lib.js showcase/qed64-bridge.js showcase/examples.json showcase/pin.json; do
  [ -f "$ASSETS/$f" ] || die "deploy tree incomplete: $f missing"
done
node - "$ASSETS" <<'EOF' || exit 3
// the gallery's pin and the bundle must name the same runtime (deploy-manifest A4 checked the sources; this is the staged tree)
const fs = require('fs'), path = require('path'); const a = process.argv[2];
const pin = JSON.parse(fs.readFileSync(path.join(a, 'showcase/pin.json'), 'utf8')).buildId;
const ids = new Set(); for (const f of fs.readdirSync(path.join(a, 'assets')).filter((f) => f.endsWith('.js'))) for (const m of fs.readFileSync(path.join(a, 'assets', f), 'utf8').match(/wasm64-[0-9a-f]{16}/g) || []) ids.add(m);
if (ids.size !== 1 || !ids.has(pin)) { console.error(`staged shell buildIds {${[...ids]}} != showcase/pin.json ${pin}`); process.exit(3); }
console.log(`staged shell and gallery both pinned to ${pin}`);
EOF
echo "shell: $(find "$ASSETS" -type f | wc -l | tr -d ' ') files, $(du -sh "$ASSETS" | cut -f1)"

if [ ! -f "$WRANGLER_CONFIG" ]; then node "$SC/scripts/lib/wrangler-config.mjs" write "$WRANGLER_CONFIG" --assets "$ASSETS"
else node "$SC/scripts/lib/wrangler-config.mjs" check "$WRANGLER_CONFIG" --assets "$ASSETS" || exit 3; fi

# The version message names the pin and the gallery, so `wrangler versions list` shows which shell is which when
# choosing a `wrangler rollback <version-id>` target (docs/DEPLOY-CLOUDFLARE.md, "Rollback").
MSG=$(node -p 'const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));`pin ${m.pin.id ? `${m.pin.id} (${m.pin.buildId})` : m.pin.buildId} gallery ${m.gallery.contentSha256.slice(0,16)} prefix ${m.options.prefix}`' "$DEPLOY_OUT/manifest.json")
# a CI deploy names its commit too (GitHub Actions sets GITHUB_SHA)
[ -n "${GITHUB_SHA:-}" ] && MSG="$MSG ci ${GITHUB_SHA:0:12}"
if [ "${DRY_RUN:-0}" = 1 ]; then
  "${WR[@]}" deploy --config "$WRANGLER_CONFIG" --message "$MSG" --dry-run --outdir "$DEPLOY_OUT/wrangler-dry-run" "$@"
  echo "DEPLOY DRY RUN OK: worker bundled into ${DEPLOY_OUT#"$SC"/}/wrangler-dry-run; nothing uploaded"
  exit 0
fi
rm -f "$DEPLOY_OUT/deployed-url.txt"
"${WR[@]}" deploy --config "$WRANGLER_CONFIG" --message "$MSG" "$@" 2>&1 | tee "$DEPLOY_OUT/wrangler-deploy.log"
# wrangler prints the workers.dev URL of the deployment; the smoke needs it (a custom domain: pass it yourself)
URL=$(grep -oE 'https?://[A-Za-z0-9.:-]+' "$DEPLOY_OUT/wrangler-deploy.log" | grep -E '\.workers\.dev$|^http://127\.0\.0\.1:' | tail -1 || true)
if [ -n "$URL" ]; then echo "$URL" > "$DEPLOY_OUT/deployed-url.txt"; echo "DEPLOYED-URL $URL"; fi
echo "DEPLOYED. Next: node scripts/deploy-manifest.mjs --out ${DEPLOY_OUT#"$SC"/} --smoke ${URL:-https://$WORKER_NAME.<your-subdomain>.workers.dev} --all --range"
