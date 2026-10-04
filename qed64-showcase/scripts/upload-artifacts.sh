#!/bin/bash
# upload-artifacts.sh — upload the showcase's R2 artifacts (the pinned runtime chunks, the profile packs, the stock
# snapshot pair and our widget overlays) "the lean4game way": into the R2 bucket QED64 already uses, under the
# showcase's own prefix, through the existing rclone remote (wasm64-lean4game/scripts/upload-artifacts.sh is the
# model). Guide: docs/DEPLOY-CLOUDFLARE.md.
#
#   scripts/upload-artifacts.sh                 the real upload (needs the R2 token in the rclone remote)
#   DRY_RUN=1 scripts/upload-artifacts.sh       the same, with rclone --dry-run (lists the bucket, writes nothing)
#
# Target: infra/deploy.env (R2_REMOTE=qed64-r2, R2_BUCKET=qed64-artifacts, R2_PREFIX=qed64-showcase/); environment
# variables of the same name override it. MANIFEST_ARGS passes extra options to the manifest generator (smaller
# variants: "--overlays widgets8 --no-stock-snapshots --no-essential-pack"). DEPLOY_OUT (default out/deploy).
# VERIFY=0 skips the post-upload `rclone check`.
#
# 1. Preflight = `node scripts/deploy-manifest.mjs --prefix $R2_PREFIX` (regenerate: every file hashed, every gate)
#    and `--check` (byte-identical regenerate, G1 the gallery gate). It refuses unless both are green and the G2 line
#    names a VERDICT UX run for exactly this gallery + lock + overlays (ALLOW_NO_UX_VERDICT=1 overrides G2 only).
# 2. `rclone copy` (NEVER sync: a promote must not delete what a deployed shell or a mid-session client still
#    points at) from the manifest's exact file lists, in three phases so a browser that revalidates an index
#    mid-upload never learns a name whose object is not there yet (R2 has no multi-object atomic publish):
#      phase 1 every digest-named object (runtime chunks, pack parts, .snapz)
#      phase 2 the manifests that name them (runtime-manifest*.json, *.manifest.json)
#      phase 3 the index.json files that name the manifests (profiles, stock snapshots, each overlay)
#    Every list is homogeneous in content type and is uploaded with an explicit
#    --header-upload "Content-Type: …" (application/json for *.json, application/octet-stream for .snapz /
#    .part-N): the pinned shell refuses a runtime manifest whose type is not JSON (qed64-boot.ts:67-70) and the
#    gallery's preflight refuses an HTML-typed snapshot. rclone's s3 backend already guesses these from the
#    extension, and --header-upload overrides the guess on both PutObject and CreateMultipartUpload (verified
#    against scripts/deploy-rehearsal/fake-s3.mjs), so the type no longer depends on the host's mime tables.
#    Objects over 200 MiB (rclone's --s3-upload-cutoff default) go multipart in 64 MiB chunks; wrangler's
#    `r2 object put` caps a single object at ~300 MiB, and three .snapz are larger.
# 3. `rclone check --one-way` of every list against the bucket (size + hash; nothing is downloaded).
set -euo pipefail
SC="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SC"
# shellcheck source=scripts/lib/deploy-common.sh
. "$SC/scripts/lib/deploy-common.sh"
load_deploy_env
command -v rclone >/dev/null || { echo "rclone required: brew install rclone" >&2; exit 2; }
# `rclone listremotes` reads the local rclone config (and RCLONE_CONFIG_* env remotes) only; it contacts nothing.
rclone listremotes | grep -qx "$R2_REMOTE:" || die "rclone remote '$R2_REMOTE:' is not configured (rclone listremotes); see docs/DEPLOY-CLOUDFLARE.md step 2"
DRY=()
if [ "${DRY_RUN:-0}" = 1 ]; then DRY=(--dry-run); echo "DRY RUN: rclone --dry-run (the bucket is listed, nothing is written)"; fi

manifest_preflight

# The phased, content-typed lists, straight from manifest.json (the generator already enforced every invariant).
PLAN="$DEPLOY_OUT/upload"
rm -rf "$PLAN"; mkdir -p "$PLAN"
node - "$DEPLOY_OUT/manifest.json" "$PLAN" <<'EOF'
const fs = require('fs'), path = require('path');
const [mPath, plan] = process.argv.slice(2);
const m = JSON.parse(fs.readFileSync(mPath, 'utf8'));
const phaseOf = (o) => (o.phase === 'immutable' ? '1-objects' : /\/index\.json$/.test(o.url) ? '3-indexes' : '2-manifests');
const lists = new Map();
for (const o of m.r2) {
  const sub = o.url.slice(1, o.url.length - o.relPath.length);            // e.g. "snapshots/widgets8/"
  if (`/${sub}${o.relPath}` !== o.url || o.key !== m.options.prefix + o.url.slice(1)) throw new Error(`inconsistent entry ${o.key}`);
  if (/\.json$/.test(o.url) !== (o.contentType === 'application/json')) throw new Error(`content type ${o.contentType} for ${o.url}`);
  if (phaseOf(o) === '1-objects' && o.contentType !== 'application/octet-stream') throw new Error(`phase-1 object ${o.url} typed ${o.contentType}`);
  const id = `${phaseOf(o)}.${o.group}.${o.contentType.replace(/\W+/g, '_')}`;
  const l = lists.get(id) || { id, phase: phaseOf(o), root: o.root, sub, contentType: o.contentType, files: [], bytes: 0 };
  if (l.root !== o.root || l.sub !== sub) throw new Error(`group ${o.group} mixes roots`);
  l.files.push(o.relPath); l.bytes += o.size; lists.set(id, l);
}
const rows = [...lists.values()].sort((a, b) => (a.id < b.id ? -1 : 1));
const n = rows.reduce((s, l) => s + l.files.length, 0);
if (n !== m.r2.length || new Set(rows.flatMap((l) => l.files.map((f) => l.sub + f))).size !== n) throw new Error('lists do not partition the manifest');
for (const l of rows) {
  fs.writeFileSync(path.join(plan, `${l.id}.files`), l.files.join('\n') + '\n');
  fs.appendFileSync(path.join(plan, 'plan.tsv'), [l.id, `${l.id}.files`, l.root, l.sub, l.contentType, l.files.length, l.bytes].join('\t') + '\n');
}
console.log(`upload plan: ${rows.length} lists, ${n} objects, ${(m.totals.r2Bytes / 1e9).toFixed(3)} GB, ${m.totals.r2Multipart} multipart; phases ${[...new Set(rows.map((l) => l.phase))].join(' -> ')}`);
EOF

# Live progress in a terminal; periodic one-line stats when logged to a file (a 350 MB .snapz otherwise shows
# nothing for minutes and looks stuck). Already-uploaded digest-named files are skipped (--checksum).
# (--stats-log-level NOTICE: rclone logs the one-line stats at INFO by default, i.e. not at all without -v; the
# final line of each list, e.g. "0 B / 0 B" on a re-run, then shows what was actually transferred)
if [ -t 1 ]; then STATS=(--progress); else STATS=(--stats 10s --stats-one-line --stats-log-level NOTICE); fi
COMMON=(--checksum --transfers 4 --s3-chunk-size 64M --s3-upload-concurrency 4 "${STATS[@]}")
DEST_ROOT="$R2_REMOTE:$R2_BUCKET/$R2_PREFIX"
while IFS=$'\t' read -r id list root sub ctype count bytes; do
  echo "== ${id%%.*} ${id#*.}: $count file(s), $(awk -v b="$bytes" 'BEGIN{printf "%.1f MB", b/1e6}'), Content-Type $ctype -> $DEST_ROOT$sub"
  rclone copy --files-from-raw "$PLAN/$list" "$SC/$root" "$DEST_ROOT$sub" \
    --header-upload "Content-Type: $ctype" "${COMMON[@]}" ${DRY[@]+"${DRY[@]}"}
done < "$PLAN/plan.tsv"

if [ "${DRY_RUN:-0}" = 1 ]; then echo "UPLOAD DRY RUN OK: nothing written to $DEST_ROOT"; exit 0; fi
if [ "${VERIFY:-1}" = 1 ]; then
  while IFS=$'\t' read -r id list root sub ctype count bytes; do
    rclone check --one-way --files-from-raw "$PLAN/$list" "$SC/$root" "$DEST_ROOT$sub" 2>&1 | tail -2
  done < "$PLAN/plan.tsv"
fi
# Release record (for scripts/rollback-artifacts.sh): this upload's manifest, plan, lists and a copy of every MUTABLE
# file it published (manifests + indexes, a few MB). Rolling back = re-publishing these names; the digest-named
# objects they point at stay in the bucket because the upload never deletes.
REC="$DEPLOY_OUT/published/$(date -u +%Y%m%dT%H%M%SZ)"
while [ -e "$REC" ]; do REC="$REC+"; done      # two uploads in the same second (sorts before a -rollback record)
mkdir -p "$REC/files"
cp "$DEPLOY_OUT/manifest.json" "$REC/"; cp -R "$PLAN" "$REC/upload"
printf '%s\n' "remote=$R2_REMOTE" "bucket=$R2_BUCKET" "prefix=$R2_PREFIX" > "$REC/target.env"
while IFS=$'\t' read -r id list root sub ctype count bytes; do
  case "$id" in 1-*) continue ;; esac
  mkdir -p "$REC/files/$sub"
  while IFS= read -r f; do mkdir -p "$(dirname "$REC/files/$sub$f")"; cp "$SC/$root/$f" "$REC/files/$sub$f"; done < "$PLAN/$list"
done < "$PLAN/plan.tsv"
echo "release record: ${REC#"$SC"/} (rollback: scripts/rollback-artifacts.sh ${REC#"$SC"/})"
echo "  out/ is gitignored and this tree has no git history: copy ${DEPLOY_OUT#"$SC"/}/published/ somewhere durable now (docs/DEPLOY-CLOUDFLARE.md section 5)"
echo "UPLOAD OK: $(wc -l < "$PLAN/plan.tsv" | tr -d ' ') lists -> $DEST_ROOT (copy only; nothing deleted). Next: scripts/deploy-app.sh"
