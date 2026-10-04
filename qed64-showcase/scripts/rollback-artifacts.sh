#!/bin/bash
# rollback-artifacts.sh <release record> — re-publish the mutable names (manifests, then indexes) of an earlier
# scripts/upload-artifacts.sh run, "the lean4game way": R2 is copy-only, so every digest-named object an earlier
# release pointed at is still in the bucket and rolling back is putting the old NAMES back
# (wasm64-lean4game/wasm/DEPLOY.md "Rollback"). Guide: docs/DEPLOY-CLOUDFLARE.md "Rollback".
#
#   ls out/deploy/published/                                      the release records (newest last)
#   DRY_RUN=1 scripts/rollback-artifacts.sh out/deploy/published/<UTC time>
#   scripts/rollback-artifacts.sh out/deploy/published/<UTC time>
#
# Refuses unless the record's remote/bucket/prefix equal the current target (infra/deploy.env + env;
# ALLOW_REMOTE_MISMATCH=1 lifts the remote check only), and unless every digest-named object the record's manifest
# lists is still in the bucket with its size (`rclone lsjson`, metadata only): re-publishing an index whose objects
# are gone would strand every visitor. Then copies the record's manifests and indexes with their Content-Type, and
# writes a new record <UTC time>-rollback (a copy) so that scripts/deploy-app.sh compares against what is live now.
# The SHELL must go back too: `npx --prefix infra wrangler versions list` (the version message names the pin and
# gallery) and `npx --prefix infra wrangler rollback <version-id>`.
# shellcheck disable=SC2016  # single-quoted node snippets use JS template literals on purpose
set -euo pipefail
SC="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SC"
# shellcheck source=scripts/lib/deploy-common.sh
. "$SC/scripts/lib/deploy-common.sh"
REC=${1:?usage: rollback-artifacts.sh <release record dir, e.g. out/deploy/published/20261001T120000Z>}
case "$REC" in /*) ;; *) REC="$SC/$REC" ;; esac
[ -f "$REC/manifest.json" ] && [ -f "$REC/upload/plan.tsv" ] && [ -d "$REC/files" ] || die "$REC is not a release record (manifest.json, upload/plan.tsv, files/)"
load_deploy_env
command -v rclone >/dev/null || { echo "rclone required: brew install rclone" >&2; exit 2; }
rclone listremotes | grep -qx "$R2_REMOTE:" || die "rclone remote '$R2_REMOTE:' is not configured (rclone listremotes)"
rr=$(sed -n 's/^remote=//p' "$REC/target.env"); rb=$(sed -n 's/^bucket=//p' "$REC/target.env"); rp=$(sed -n 's/^prefix=//p' "$REC/target.env")
[ "$rb" = "$R2_BUCKET" ] && [ "$rp" = "$R2_PREFIX" ] || die "record target bucket '$rb' prefix '$rp' != current '$R2_BUCKET' '$R2_PREFIX'"
# A record made through another rclone remote describes another account/bucket's state as far as this machine knows
# (in the rehearsal: the fake-s3 record vs the local fake). Refuse unless deliberately overridden.
if [ "$rr" != "$R2_REMOTE" ]; then
  [ "${ALLOW_REMOTE_MISMATCH:-0}" = 1 ] || die "record was uploaded through remote '$rr', current R2_REMOTE is '$R2_REMOTE': pick a record of this remote (grep remote= $DEPLOY_OUT/published/*/target.env) or set ALLOW_REMOTE_MISMATCH=1 deliberately"
  echo "WARNING: record remote '$rr' != R2_REMOTE '$R2_REMOTE'; proceeding because ALLOW_REMOTE_MISMATCH=1" >&2
fi
DRY=(); [ "${DRY_RUN:-0}" = 1 ] && DRY=(--dry-run)
DEST_ROOT="$R2_REMOTE:$R2_BUCKET/$R2_PREFIX"
node -p 'const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));`record: pin ${m.pin.id ? `${m.pin.id} (${m.pin.buildId})` : m.pin.buildId}, gallery ${m.gallery.contentSha256.slice(0,16)}…, ${m.r2.length} objects`' "$REC/manifest.json"

# 1. every digest-named object of the record must still be there, with its size
missing=0
while IFS=$'\t' read -r id list _root sub _ctype count _bytes; do
  case "$id" in 1-*) ;; *) continue ;; esac
  got=$(rclone lsjson -R --files-only --files-from-raw "$REC/upload/$list" "$DEST_ROOT$sub" 2>/dev/null || echo '[]')
  bad=$(node -e '
    const fs = require("fs"); const [listPath, sub] = process.argv.slice(1); const got = JSON.parse(process.argv[3]);
    const m = JSON.parse(fs.readFileSync(process.argv[4], "utf8"));
    const size = new Map(got.map((o) => [o.Path, o.Size]));
    const want = fs.readFileSync(listPath, "utf8").trim().split("\n");
    const bad = want.filter((f) => { const o = m.r2.find((x) => x.url === "/" + sub + f); return !o || size.get(f) !== o.size; });
    for (const f of bad.slice(0, 5)) console.error(`MISSING or wrong size in the bucket: ${sub}${f}`);
    console.log(bad.length);' "$REC/upload/$list" "$sub" "$got" "$REC/manifest.json")
  echo "objects $sub: $((count - bad))/$count present with their size"
  missing=$((missing + bad))
done < "$REC/upload/plan.tsv"
[ "$missing" = 0 ] || die "$missing object(s) of this release are not in the bucket: re-upload them first (scripts/upload-artifacts.sh from that release), nothing was changed"

# 2. manifests, then 3. indexes, from the record's copies
for phase in 2- 3-; do
  while IFS=$'\t' read -r id list _root sub ctype count _bytes; do
    case "$id" in "$phase"*) ;; *) continue ;; esac
    echo "== rollback ${id%%.*} ${id#*.}: $count file(s) -> $DEST_ROOT$sub"
    rclone copy --files-from-raw "$REC/upload/$list" "$REC/files/$sub" "$DEST_ROOT$sub" \
      --header-upload "Content-Type: $ctype" --checksum ${DRY[@]+"${DRY[@]}"}
  done < "$REC/upload/plan.tsv"
done
if [ "${DRY_RUN:-0}" = 1 ]; then echo "ROLLBACK DRY RUN OK: nothing written"; exit 0; fi
# A rollback changes what the bucket's mutable names say, so it leaves a record too: scripts/deploy-app.sh compares
# the shell it deploys with the NEWEST record of this remote, which is now this one.
NEW="$DEPLOY_OUT/published/$(date -u +%Y%m%dT%H%M%SZ)-rollback"
mkdir -p "$NEW"
cp "$REC/manifest.json" "$NEW/"; cp -R "$REC/upload" "$NEW/upload"; cp -R "$REC/files" "$NEW/files"
printf '%s\n' "remote=$R2_REMOTE" "bucket=$R2_BUCKET" "prefix=$R2_PREFIX" "rollback_of=${REC##*/}" > "$NEW/target.env"
echo "release record: ${NEW#"$SC"/} (a copy of ${REC##*/}; back it up with the others, docs/DEPLOY-CLOUDFLARE.md section 5)"
echo "ROLLBACK OK: the mutable names of ${REC#"$SC"/} are re-published. Now roll the shell back to the matching version:"
echo "  npx --prefix infra wrangler versions list      # pick the version whose message names this pin + gallery"
echo "  npx --prefix infra wrangler rollback <version-id>"
