# shellcheck shell=bash
# deploy-common.sh — sourced by scripts/upload-artifacts.sh and scripts/deploy-app.sh (bash). Nothing here talks to
# Cloudflare or R2: it loads the deploy target and runs the manifest gates.
#
# Target: infra/deploy.env (R2_REMOTE, R2_BUCKET, R2_PREFIX, WORKER_NAME); an environment variable of the same name
# wins, subject to the shared-bucket guard (scripts/lib/deploy-env.mjs). Other knobs: DEPLOY_OUT (default
# out/deploy: manifest.json, rclone lists, assets/, published/ release records), MANIFEST_ARGS (extra options for
# `deploy-manifest.mjs` generate, e.g. "--overlays widgets8 --no-stock-snapshots --no-essential-pack"),
# ALLOW_NO_UX_VERDICT=1 (proceed although G2 found no verdict UX run for this gallery + lock + overlays).

die() { echo "$(basename "$0"): $*" >&2; exit 3; }

load_deploy_env() {
  # One implementation for bash and JS: scripts/lib/deploy-env.mjs reads infra/deploy.env, applies the environment
  # overrides, validates every value ([A-Za-z0-9._/-] only, so the lines are safe to read back here) and applies the
  # SHARED-BUCKET GUARD: in bucket qed64-artifacts an empty prefix (QED64's root) or one inside lean4game/, runtime/,
  # profiles/, snapshots/ is refused outright, and any prefix other than qed64-showcase/ needs ALLOW_SHARED_PREFIX=1.
  local resolved line
  resolved=$(node "$SC/scripts/lib/deploy-env.mjs") || die "deploy target refused (see above): nothing uploaded, deployed or rolled back"
  while IFS= read -r line; do
    [[ "$line" =~ ^(R2_REMOTE|R2_BUCKET|R2_PREFIX|WORKER_NAME)=([A-Za-z0-9._/-]*)$ ]] || die "unexpected deploy-env line '$line'"
    export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
  done <<< "$resolved"
  DEPLOY_OUT=${DEPLOY_OUT:-out/deploy}
  case "$DEPLOY_OUT" in /*) ;; *) DEPLOY_OUT="$SC/$DEPLOY_OUT" ;; esac
  export DEPLOY_OUT
  echo "deploy target: remote $R2_REMOTE, bucket $R2_BUCKET, prefix '${R2_PREFIX}', worker $WORKER_NAME; manifest dir ${DEPLOY_OUT#"$SC"/}"
}

# The newest release record (scripts/upload-artifacts.sh, or a rollback-artifacts.sh re-publish) for remote $1 under
# $DEPLOY_OUT/published, i.e. what that remote's mutable names currently say as far as this machine knows. Prints
# nothing when there is none. Record dirs are named <UTC yyyymmddThhmmssZ>[-rollback], so a plain sort is time order.
newest_record_for_remote() {
  local d
  [ -d "$DEPLOY_OUT/published" ] || return 0
  while IFS= read -r d; do      # (the project path has a space: no word-splitting for loop)
    [ -f "$d/target.env" ] && [ -f "$d/manifest.json" ] || continue
    if [ "$(sed -n 's/^remote=//p' "$d/target.env")" = "$1" ]; then echo "$d"; return 0; fi
  done < <(find "$DEPLOY_OUT/published" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort -r)
}

# Regenerate the manifest with the target's prefix, then the dry-run --check (G1 included); refuse unless both are
# green and G2 names a verdict UX run with no later red full run on the same inputs (ALLOW_NO_UX_VERDICT=1 overrides
# G2 only, never a FAIL).
manifest_preflight() {
  local log="$DEPLOY_OUT/preflight.log"
  mkdir -p "$DEPLOY_OUT"
  # shellcheck disable=SC2086  # MANIFEST_ARGS is a word list on purpose
  node "$SC/scripts/deploy-manifest.mjs" --out "$DEPLOY_OUT" --prefix "$R2_PREFIX" ${MANIFEST_ARGS:-} | tee "$log.generate" \
    || die "manifest generate FAILED (see above): nothing uploaded or deployed"
  node "$SC/scripts/deploy-manifest.mjs" --check --out "$DEPLOY_OUT" | tee "$log" \
    || die "manifest --check FAILED (see above): nothing uploaded or deployed"
  grep -q '^DEPLOY-MANIFEST CHECK OK' "$log" || die "no 'DEPLOY-MANIFEST CHECK OK' line"
  grep -q '^OK   G1 ' "$log" || die "no 'OK   G1' line (the gallery gate did not pass)"
  local prefix
  prefix=$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).options.prefix' "$DEPLOY_OUT/manifest.json")
  [ "$prefix" = "$R2_PREFIX" ] || die "manifest prefix '$prefix' != R2_PREFIX '$R2_PREFIX'"
  local g2
  g2=$(grep -m1 'G2 UX:' "$log" || true)
  echo "G2 verdict line: ${g2:-<none>}"
  case "$g2" in
    *"G2 UX: verdict run "*"; BUT "*)
       # a later full run on the same gallery + lock + overlays was red (ux-record.mjs laterFailures; final audit: L9)
       if [ "${ALLOW_NO_UX_VERDICT:-0}" = 1 ]; then echo "WARNING: a later full UX run on these inputs was NOT A VERDICT; proceeding because ALLOW_NO_UX_VERDICT=1" >&2
       else die "a later full UX run on exactly this gallery + lock + overlays was NOT A VERDICT (see the G2 line): resolve it, or set ALLOW_NO_UX_VERDICT=1 deliberately"; fi ;;
    *"G2 UX: verdict run "*) ;;
    *) if [ "${ALLOW_NO_UX_VERDICT:-0}" = 1 ]; then echo "WARNING: no verdict UX run for this gallery + lock + overlays; proceeding because ALLOW_NO_UX_VERDICT=1" >&2
       else die "no verdict UX run for exactly this gallery + lock + overlays (run 'scripts/showcase.sh ux'), or set ALLOW_NO_UX_VERDICT=1 deliberately"; fi ;;
  esac
}
