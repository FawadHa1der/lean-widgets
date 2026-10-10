#!/bin/bash
# upload-artifacts.sh — upload the showcase's R2 artifacts (the pinned runtime chunks, the profile packs, the stock
# snapshot pair and our widget overlays) "the lean4game way": into the R2 bucket QED64 already uses, under the
# showcase's own prefix, through the existing rclone remote (wasm64-lean4game/scripts/upload-artifacts.sh is the
# model). Guide: docs/DEPLOY-CLOUDFLARE.md.
#
#   scripts/upload-artifacts.sh                 the real upload (needs the R2 token in the rclone remote)
#   DRY_RUN=1 scripts/upload-artifacts.sh       the same, with rclone --dry-run (lists the bucket, writes nothing)
#   PHASES=1-objects,2-manifests scripts/upload-artifacts.sh
#                                               only those phases (below; default all three, in order). A SPLIT upload:
#                                               phases 1-2 before the Worker deploy, `PHASES=3-indexes` after it, so the
#                                               mutable shared indexes an older live shell reads (/snapshots/index.json,
#                                               /profiles/index.json, the bare overlay /snapshots/widgets{7,8}/index.json)
#                                               change only once the new shell is live (decision E1 of the pin I plan;
#                                               QED64 HARDENING #64). A per-runtime overlay index
#                                               (/snapshots/widgets{7,8}.<bid16>/index.json, pin.json v3) is a NEW key no
#                                               older shell reads: phase 2, so the new gallery has its overlays as soon
#                                               as the new Worker is live.
#                                               A phase is uploaded only when every EARLIER phase is selected too or was
#                                               uploaded by this remote's newest release records for the same R2 keys
#                                               (ALLOW_UNRECORDED_UPLOAD=1 skips that check deliberately). The release
#                                               record names its phases (target.env phases=...) and lists only their files.
#
# Target: infra/deploy.env (R2_REMOTE=qed64-r2, R2_BUCKET=qed64-artifacts, R2_PREFIX=qed64-showcase/); environment
# variables of the same name override it. MANIFEST_ARGS passes extra options to the manifest generator (smaller
# variants: "--overlays widgets8 --no-stock-snapshots --no-essential-pack"; --overlays takes the LOGICAL names, which
# deploy-manifest.mjs uploads under each pin's served directory, /snapshots/<dir>/ = scripts/lib/pins.mjs overlayDir: the
# bare name for pins A–H, '<o>.<bid16>' for a per-runtime pin). DEPLOY_OUT (default out/deploy).
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
#      phase 3 the index.json files that name the manifests (profiles, stock snapshots, each bare overlay directory)
#    (a per-build index copy, snapshots/index.<buildId>.json or snapshots/profiles-index.<buildId>.json, which
#    deploy-manifest.mjs adds for a pin with hardening.pinnedIndexes (R6, QED64 HARDENING #64), is not an index.json, and a per-runtime overlay
#    directory's index.json (snapshots/widgets8.<bid16>/, read only by the shell of that runtime) replaces nothing an
#    older shell reads: both phase 2, so the new shell's pinned indexes and its gallery's overlays are up before a split
#    upload's Worker deploy; each still goes up after the phase-1 objects it names. Keep phaseOf on ONE line:
#    ci/rehearse-deploy.sh (old-shell) evaluates it from this file)
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
ALL_PHASES=1-objects,2-manifests,3-indexes
PHASES=${PHASES:-$ALL_PHASES}
for p in ${PHASES//,/ }; do case "$p" in 1-objects|2-manifests|3-indexes) ;; *) die "PHASES: unknown phase '$p' (want a comma list of $ALL_PHASES)" ;; esac; done
# canonical order, no duplicates
sel=""
for p in 1-objects 2-manifests 3-indexes; do case ",$PHASES," in *",$p,"*) sel="$sel,$p" ;; esac; done
PHASES=${sel#,}
[ -n "$PHASES" ] || die "PHASES selects no phase"
export PHASES
[ "$PHASES" = "$ALL_PHASES" ] || echo "PHASES: uploading only $PHASES (of $ALL_PHASES)"

case " ${MANIFEST_ARGS:-} " in *" --from-lock "*) die "MANIFEST_ARGS has --from-lock: a shell-only manifest cannot upload (its R2 entries are the lock's values, not local files)" ;; esac
manifest_preflight
[ "$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).options.source || ""' "$DEPLOY_OUT/manifest.json")" = "" ] \
  || die "$DEPLOY_OUT/manifest.json is a --from-lock (shell-only) manifest: nothing to upload from"

# The phased, content-typed lists, straight from manifest.json (the generator already enforced every invariant).
PLAN="$DEPLOY_OUT/upload"
rm -rf "$PLAN"; mkdir -p "$PLAN"
node - "$DEPLOY_OUT/manifest.json" "$PLAN" "$PHASES" <<'EOF'
const fs = require('fs'), path = require('path');
const [mPath, plan, phasesCsv] = process.argv.slice(2);
const selected = new Set(phasesCsv.split(','));
const m = JSON.parse(fs.readFileSync(mPath, 'utf8'));
const phaseOf = (o) => (o.phase === 'immutable' ? '1-objects' : /\/index\.json$/.test(o.url) && !/^\/snapshots\/widgets[78]\.[0-9a-f]{16}\/index\.json$/.test(o.url) ? '3-indexes' : '2-manifests');
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
const all = [...lists.values()].sort((a, b) => (a.id < b.id ? -1 : 1));
const n = all.reduce((s, l) => s + l.files.length, 0);
if (n !== m.r2.length || new Set(all.flatMap((l) => l.files.map((f) => l.sub + f))).size !== n) throw new Error('lists do not partition the manifest');
// PHASES: the plan (plan.tsv: what is uploaded, verified and recorded) holds the selected phases' lists only
const rows = all.filter((l) => selected.has(l.phase));
fs.writeFileSync(path.join(plan, 'plan.tsv'), '');
for (const l of rows) {
  fs.writeFileSync(path.join(plan, `${l.id}.files`), l.files.join('\n') + '\n');
  fs.appendFileSync(path.join(plan, 'plan.tsv'), [l.id, `${l.id}.files`, l.root, l.sub, l.contentType, l.files.length, l.bytes].join('\t') + '\n');
}
const objs = m.r2.filter((o) => rows.some((l) => l.sub === o.url.slice(1, o.url.length - o.relPath.length) && l.files.includes(o.relPath)));
const skipped = all.filter((l) => !selected.has(l.phase));
console.log(`upload plan: ${rows.length} lists, ${objs.length} objects, ${(objs.reduce((s, o) => s + o.size, 0) / 1e9).toFixed(3)} GB, ${objs.filter((o) => o.multipart).length} multipart; phases ${[...new Set(rows.map((l) => l.phase))].join(' -> ') || 'none'}`
  + (skipped.length ? ` (NOT in this upload: ${skipped.reduce((s, l) => s + l.files.length, 0)} object(s) of phase ${[...new Set(skipped.map((l) => l.phase))].join(', ')})` : ''));
for (const l of rows) console.log(`  ${l.phase} ${l.sub}: ${l.files.length} file(s)${l.files.some((f) => /\.json$/.test(f)) ? ` [${l.files.join(', ')}]` : ''}`);
EOF
[ -s "$PLAN/plan.tsv" ] || die "PHASES=$PHASES selects no object of this manifest"

# A phase may only go up after every earlier one: selected now, or uploaded (same R2 keys + sha256) by this remote's newest
# release records. Uploading an index before the objects it names is exactly what the phase order exists to prevent.
missing_earlier=()
case ",$PHASES," in *,2-manifests,*|*,3-indexes,*) case ",$PHASES," in *,1-objects,*) ;; *) missing_earlier+=(1-objects) ;; esac ;; esac
case ",$PHASES," in *,3-indexes,*) case ",$PHASES," in *,2-manifests,*) ;; *) missing_earlier+=(2-manifests) ;; esac ;; esac
if [ ${#missing_earlier[@]} -gt 0 ]; then
  if ! node - "$DEPLOY_OUT/manifest.json" "$DEPLOY_OUT/published" "$R2_REMOTE" "$R2_BUCKET" "$R2_PREFIX" "${missing_earlier[@]}" <<'EOF'
// the union of the phases uploaded by this remote's newest consecutive release records whose target and R2 keys + sha256
// are this manifest's (a record written before PHASES existed has no phases= line: it uploaded all three)
const fs = require('fs'), path = require('path');
const [mPath, pubDir, remote, bucket, prefix, ...need] = process.argv.slice(2);
const sig = (m) => JSON.stringify(m.r2.map((o) => [o.key, o.sha256, o.size]).sort());
const cur = sig(JSON.parse(fs.readFileSync(mPath, 'utf8')));
const env = (d) => Object.fromEntries(fs.readFileSync(path.join(d, 'target.env'), 'utf8').trim().split('\n').map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
const recs = fs.existsSync(pubDir) ? fs.readdirSync(pubDir).sort().reverse().map((n) => path.join(pubDir, n))
  .filter((d) => fs.existsSync(path.join(d, 'target.env')) && fs.existsSync(path.join(d, 'manifest.json')) && env(d).remote === remote) : [];
const have = new Set(); const used = [];
for (const d of recs) {
  const t = env(d);
  if (t.bucket !== bucket || t.prefix !== prefix || t.rollback_of || sig(JSON.parse(fs.readFileSync(path.join(d, 'manifest.json'), 'utf8'))) !== cur) break;
  for (const p of (t.phases || '1-objects,2-manifests,3-indexes').split(',')) have.add(p);
  used.push(path.basename(d));
}
const gap = need.filter((p) => !have.has(p));
if (gap.length) { console.error(`PHASE ORDER: phase(s) ${gap.join(', ')} of this manifest were not uploaded through '${remote}' (newest matching release records: ${used.join(', ') || 'none'}); upload them first, e.g. PHASES=${[...gap, process.env.PHASES].join(',')}`); process.exit(1); }
console.log(`PHASE ORDER OK: earlier phase(s) ${need.join(', ')} were uploaded by release record(s) ${used.join(', ')} with exactly these R2 keys`);
EOF
  then
    [ "${ALLOW_UNRECORDED_UPLOAD:-0}" = 1 ] || die "refusing to upload $PHASES before ${missing_earlier[*]} (see above); set ALLOW_UNRECORDED_UPLOAD=1 only if you know the bucket already holds those objects"
    echo "WARNING: uploading $PHASES without a record of ${missing_earlier[*]} because ALLOW_UNRECORDED_UPLOAD=1" >&2
  fi
fi

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

if [ "${DRY_RUN:-0}" = 1 ]; then echo "UPLOAD DRY RUN OK: nothing written to $DEST_ROOT (phases $PHASES)"; exit 0; fi
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
printf '%s\n' "remote=$R2_REMOTE" "bucket=$R2_BUCKET" "prefix=$R2_PREFIX" "phases=$PHASES" > "$REC/target.env"
while IFS=$'\t' read -r id list root sub ctype count bytes; do
  case "$id" in 1-*) continue ;; esac
  mkdir -p "$REC/files/$sub"
  while IFS= read -r f; do mkdir -p "$(dirname "$REC/files/$sub$f")"; cp "$SC/$root/$f" "$REC/files/$sub$f"; done < "$PLAN/$list"
done < "$PLAN/plan.tsv"
echo "release record: ${REC#"$SC"/} (rollback: scripts/rollback-artifacts.sh ${REC#"$SC"/})"
echo "  out/ is gitignored and this tree has no git history: copy ${DEPLOY_OUT#"$SC"/}/published/ somewhere durable now (docs/DEPLOY-CLOUDFLARE.md section 5)"
case ",$PHASES," in
  *,3-indexes,*) echo "UPLOAD OK: $(wc -l < "$PLAN/plan.tsv" | tr -d ' ') lists -> $DEST_ROOT, phases $PHASES (copy only; nothing deleted). Next: scripts/deploy-app.sh" ;;
  *) echo "UPLOAD OK: $(wc -l < "$PLAN/plan.tsv" | tr -d ' ') lists -> $DEST_ROOT, phases $PHASES only (copy only; nothing deleted). Next (split upload, decision E1): deploy the shell, then PHASES=3-indexes scripts/upload-artifacts.sh. ALLOW_PARTIAL_UPLOAD=1 relaxes only deploy-app.sh's release-record check: its published check (PUBLISHED_ORIGIN, which the CI deploy sets) still compares the phase-3 indexes and refuses until they are uploaded" ;;
esac
