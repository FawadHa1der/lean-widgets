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
#               size altered, against the live stand-in -> FAIL (the check can see a wrong upload)
#
#   ci/rehearse-deploy.sh [scenario…]       default: all of them, in the order above
# Env: REF (commit to clone, default HEAD), RUN_DIR (default $QED64_SHOWCASE_WORK/ci-rehearsal/<UTC time>),
# REHEARSAL_SRC_STATE (default $QED64_SHOWCASE_WORK/deploy-rehearsal/state), PORT (default 8792; PORT+10 = empty R2).
# macOS only (sandbox-exec), like scripts/deploy-rehearsal/rehearse.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SC="$ROOT/qed64-showcase"
# shellcheck source=SCRIPTDIR/../qed64-showcase/scripts/lib/env.sh
. "$SC/scripts/lib/env.sh"
die() { echo "rehearse-deploy: $*" >&2; exit 2; }
command -v sandbox-exec >/dev/null || die "needs macOS sandbox-exec (the wrangler shim runs offline under it)"
[ -d "$ROOT/ci/node_modules/yaml" ] || npm ci --prefix "$ROOT/ci" --no-audit --no-fund
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
cleanup() { env "${LIVE_ENV[@]}" "$SHIM" _stop || true; env "${EMPTY_ENV[@]}" "$SHIM" _stop || true; }
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
    node -e 'const fs=require("fs");const m=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
      const ix=m.r2.find(o=>o.url==="/snapshots/widgets8/index.json"); ix.sha256="0".repeat(64);
      const big=m.r2.find(o=>o.immutable&&o.url.endsWith(".snapz")); big.size+=1;
      fs.writeFileSync(process.argv[2],JSON.stringify(m));' "$M" "$RUN/tamper/out/manifest.json"
    local rc=0
    (cd "$(dirname "$(dirname "$(dirname "$M")")")" && node scripts/deploy-manifest.mjs --published "http://127.0.0.1:$PORT" --out "$RUN/tamper/out") > "$RUN/tamper.log" 2>&1 || rc=$?
    tail -4 "$RUN/tamper.log"
    if [ "$rc" = 1 ] && has tamper 'FAIL /snapshots/widgets8/index.json' && has tamper 'content-length [0-9]+ != [0-9]+' && has tamper 'PUBLISHED FAILED'; then
      pass tamper "--published caught a wrong index sha256 and a wrong object size"
    else fail tamper "expected two FAIL lines and PUBLISHED FAILED, rc 1 (got rc $rc; log $RUN/tamper.log)"; fi ;;
  *) die "unknown scenario $1" ;;
  esac
}
SCEN=("$@"); [ ${#SCEN[@]} -gt 0 ] || SCEN=(skip dry-run unpublished deploy first no-verdict tamper)
for s in "${SCEN[@]}"; do scenario "$s"; done
cleanup; trap - EXIT
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 || lsof -nP -iTCP:"$EMPTY_PORT" -sTCP:LISTEN >/dev/null 2>&1; then fail cleanup "a wrangler dev still listens"; fi
echo "run dir: $RUN"
[ "$FAILS" = 0 ] && { echo "REHEARSE-DEPLOY OK: ${SCEN[*]}"; exit 0; }
echo "REHEARSE-DEPLOY FAILED: $FAILS scenario(s)"; exit 1
