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
# The object check reads the record's manifest.json (every immutable R2 entry), never only the uploaded lists.
# A record of a SPLIT upload (target.env phases= naming fewer than all three phases: scripts/upload-artifacts.sh PHASES,
# decision E1: `PHASES=1-objects,2-manifests`, the Worker deploy, then `PHASES=3-indexes`) holds only those phases' lists
# and files. Either record of such a release may be named: its COMPANION records are joined, i.e. the consecutive records
# of this remote/bucket/prefix (no rollback in between) whose manifest.json has the same R2 keys + sha256 + size (the
# union rule of deploy-app.sh / upload-artifacts.sh). When their phases cover all three, phase 2 is re-published from the
# newest companion that uploaded it, then phase 3 from the newest that uploaded that, and the new record holds the union
# (no phases= line: a complete release). When they do not, refused unless ALLOW_PARTIAL_ROLLBACK=1; the new record then
# keeps the record's phases= line, so deploy-app.sh / upload-artifacts.sh never count it as a complete upload.
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
while [ "${REC%/}" != "$REC" ]; do REC=${REC%/}; done # a tab-completed dir/ : the companion join and rollback_of= need the bare name
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
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rollback-artifacts.XXXXXX"); trap 'rm -rf "$WORK"' EXIT
# a split upload's record (PHASES, scripts/upload-artifacts.sh) covers only some phases: join its companions (header)
SRC="$REC"; JOINED=""
rph=$(sed -n 's/^phases=//p' "$REC/target.env")
if [ -n "$rph" ] && [ "$rph" != 1-objects,2-manifests,3-indexes ]; then
  # (the script goes to a file first: bash 3.2, macOS's /bin/bash, misparses a here-document inside $(...))
  cat > "$WORK/join.js" <<'EOF'
// the companion records of a split upload: the consecutive records (same remote/bucket/prefix, no rollback in between)
// around REC with REC's R2 keys + sha256 + size; per phase the newest one that uploaded it. Writes the merged record
// (manifest.json, upload/plan.tsv + lists, files/) to OUT; prints "name(phases) + ..." or exits 1 naming the gap.
const fs = require('fs'), path = require('path');
const [rec, out] = process.argv.slice(2).map((p) => path.resolve(p));
const ALL = ['1-objects', '2-manifests', '3-indexes'];
const env = (d) => Object.fromEntries(fs.readFileSync(path.join(d, 'target.env'), 'utf8').trim().split('\n').map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
const sig = (d) => JSON.stringify(JSON.parse(fs.readFileSync(path.join(d, 'manifest.json'), 'utf8')).r2.map((o) => [o.key, o.sha256, o.size]).sort());
const t0 = env(rec); const s0 = sig(rec); const pub = path.dirname(rec);
const recs = fs.readdirSync(pub).sort().map((n) => path.join(pub, n))
  .filter((d) => fs.existsSync(path.join(d, 'target.env')) && fs.existsSync(path.join(d, 'manifest.json')) && fs.existsSync(path.join(d, 'upload/plan.tsv')))
  .filter((d) => { const t = env(d); return t.remote === t0.remote && t.bucket === t0.bucket && t.prefix === t0.prefix; });
const i0 = recs.indexOf(rec);
if (i0 < 0) { console.error(`split upload: ${rec} is not among the release records of ${pub}`); process.exit(1); }
const same = (d) => !env(d).rollback_of && sig(d) === s0;
let a = i0, b = i0;
while (a > 0 && same(recs[a - 1])) a--;
while (b + 1 < recs.length && same(recs[b + 1])) b++;
const run = recs.slice(a, b + 1);
const phasesOf = (d) => (env(d).phases || ALL.join(',')).split(',');
const pick = Object.fromEntries(ALL.map((p) => [p, [...run].reverse().find((d) => phasesOf(d).includes(p))]));
const gap = ALL.filter((p) => !pick[p]);
const label = run.map((d) => `${path.basename(d)}(${phasesOf(d).join(',')})`).join(' + ');
if (gap.length) { console.error(`split upload: the companion records ${label} cover no ${gap.join(', ')} of these R2 keys`); process.exit(1); }
fs.mkdirSync(path.join(out, 'upload'), { recursive: true }); fs.mkdirSync(path.join(out, 'files'), { recursive: true });
fs.copyFileSync(path.join(rec, 'manifest.json'), path.join(out, 'manifest.json'));
let plan = '';
for (const p of ALL) {
  const d = pick[p];
  for (const row of fs.readFileSync(path.join(d, 'upload/plan.tsv'), 'utf8').split('\n').filter(Boolean)) {
    const [id, list, , sub] = row.split('\t');
    if (!id.startsWith(`${p}.`)) continue;
    plan += row + '\n';
    fs.copyFileSync(path.join(d, 'upload', list), path.join(out, 'upload', list));
    if (p === '1-objects') continue;
    for (const f of fs.readFileSync(path.join(d, 'upload', list), 'utf8').split('\n').filter(Boolean)) {
      const to = path.join(out, 'files', sub, f); fs.mkdirSync(path.dirname(to), { recursive: true });
      fs.copyFileSync(path.join(d, 'files', sub, f), to);
    }
  }
}
fs.writeFileSync(path.join(out, 'upload/plan.tsv'), plan);
console.log(`${label}; phase 2 from ${path.basename(pick['2-manifests'])}, phase 3 from ${path.basename(pick['3-indexes'])}`);
EOF
  if JOINED=$(node "$WORK/join.js" "$REC" "$WORK/merged"); then
    SRC="$WORK/merged"; rph=""
    echo "split upload: ${REC##*/} records phase(s) $(sed -n 's/^phases=//p' "$REC/target.env") only; joined with its companion records: $JOINED"
  else
    [ "${ALLOW_PARTIAL_ROLLBACK:-0}" = 1 ] || die "$REC records a split upload of phase(s) $rph only and its companion records do not cover all three phases (above): roll back to a record set that uploaded all three (grep phases= $DEPLOY_OUT/published/*/target.env; a record without phases= uploaded all three; either record of a split upload may be named), or set ALLOW_PARTIAL_ROLLBACK=1 deliberately"
    echo "WARNING: rolling back a split-upload record (phases $rph only) because ALLOW_PARTIAL_ROLLBACK=1" >&2
  fi
fi
DRY=(); [ "${DRY_RUN:-0}" = 1 ] && DRY=(--dry-run)
DEST_ROOT="$R2_REMOTE:$R2_BUCKET/$R2_PREFIX"
node -p 'const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));`record: pin ${m.pin.id ? `${m.pin.id} (${m.pin.buildId})` : m.pin.buildId}, gallery ${m.gallery.contentSha256.slice(0,16)}…, ${m.r2.length} objects`' "$REC/manifest.json"

# 1. every digest-named object of the record's manifest.json (each immutable R2 entry; not only the lists a split
# upload's record holds) must still be there, with its size
missing=0
node - "$SRC/manifest.json" "$WORK/check" <<'EOF'
const fs = require('fs'), path = require('path');
const [mPath, out] = process.argv.slice(2);
const bySub = new Map();
for (const o of JSON.parse(fs.readFileSync(mPath, 'utf8')).r2) {
  if (!o.immutable) continue;
  const sub = o.url.slice(1, o.url.length - o.relPath.length);
  (bySub.get(sub) || bySub.set(sub, []).get(sub)).push(o.relPath);
}
fs.mkdirSync(out, { recursive: true });
let tsv = ''; let i = 0;
for (const [sub, files] of [...bySub].sort()) { i++; fs.writeFileSync(path.join(out, `${i}.files`), files.join('\n') + '\n'); tsv += `${i}\t${i}.files\t-\t${sub}\t-\t${files.length}\t-\n`; }
fs.writeFileSync(path.join(out, 'check.tsv'), tsv);
EOF
while IFS=$'\t' read -r _id list _root sub _ctype count _bytes; do
  got=$(rclone lsjson -R --files-only --files-from-raw "$WORK/check/$list" "$DEST_ROOT$sub" 2>/dev/null || echo '[]')
  bad=$(node -e '
    const fs = require("fs"); const [listPath, sub] = process.argv.slice(1); const got = JSON.parse(process.argv[3]);
    const m = JSON.parse(fs.readFileSync(process.argv[4], "utf8"));
    const size = new Map(got.map((o) => [o.Path, o.Size]));
    const want = fs.readFileSync(listPath, "utf8").trim().split("\n");
    const bad = want.filter((f) => { const o = m.r2.find((x) => x.url === "/" + sub + f); return !o || size.get(f) !== o.size; });
    for (const f of bad.slice(0, 5)) console.error(`MISSING or wrong size in the bucket: ${sub}${f}`);
    console.log(bad.length);' "$WORK/check/$list" "$sub" "$got" "$SRC/manifest.json")
  echo "objects $sub: $((count - bad))/$count present with their size"
  missing=$((missing + bad))
done < "$WORK/check/check.tsv"
[ "$missing" = 0 ] || die "$missing object(s) of this release are not in the bucket: re-upload them first (scripts/upload-artifacts.sh from that release), nothing was changed"

# 2. manifests, then 3. indexes, from the record's copies
for phase in 2- 3-; do
  while IFS=$'\t' read -r id list _root sub ctype count _bytes; do
    case "$id" in "$phase"*) ;; *) continue ;; esac
    echo "== rollback ${id%%.*} ${id#*.}: $count file(s) -> $DEST_ROOT$sub"
    rclone copy --files-from-raw "$SRC/upload/$list" "$SRC/files/$sub" "$DEST_ROOT$sub" \
      --header-upload "Content-Type: $ctype" --checksum ${DRY[@]+"${DRY[@]}"}
  done < "$SRC/upload/plan.tsv"
done
if [ "${DRY_RUN:-0}" = 1 ]; then echo "ROLLBACK DRY RUN OK: nothing written"; exit 0; fi
# A rollback changes what the bucket's mutable names say, so it leaves a record too: scripts/deploy-app.sh compares
# the shell it deploys with the NEWEST record of this remote, which is now this one.
NEW="$DEPLOY_OUT/published/$(date -u +%Y%m%dT%H%M%SZ)-rollback"
mkdir -p "$NEW"
cp "$SRC/manifest.json" "$NEW/"; cp -R "$SRC/upload" "$NEW/upload"; cp -R "$SRC/files" "$NEW/files"
printf '%s\n' "remote=$R2_REMOTE" "bucket=$R2_BUCKET" "prefix=$R2_PREFIX" "rollback_of=${REC##*/}" ${rph:+"phases=$rph"} ${JOINED:+"joined=${JOINED%%;*}"} > "$NEW/target.env"
echo "release record: ${NEW#"$SC"/} (a copy of ${REC##*/}${JOINED:+ joined with its companion records}; back it up with the others, docs/DEPLOY-CLOUDFLARE.md section 5)"
echo "ROLLBACK OK: the mutable names of ${REC#"$SC"/} are re-published. Now roll the shell back to the matching version:"
echo "  npx --prefix infra wrangler versions list      # pick the version whose message names this pin + gallery"
echo "  npx --prefix infra wrangler rollback <version-id>"
