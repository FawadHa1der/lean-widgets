#!/bin/bash
# wrangler-shim.sh — stands in for `wrangler` in the LOCAL rehearsal of the GitHub Actions deploy (ci/rehearse-deploy.sh
# sets WRANGLER_BIN to this file; scripts/deploy-app.sh then calls it where it would call `wrangler`). It never deploys:
#
#   wrangler-shim.sh deploy --config <toml> [args…]   = the real pinned wrangler's `deploy --config <toml> [args…] --dry-run`
#                                                      (bundles the Worker, uploads nothing), then (re)starts
#                                                      `wrangler dev --local` on the SAME config over the fake R2 state, so
#                                                      the workflow's post-deploy smoke has a "deployed" Worker to test.
#                                                      Prints the origin the way wrangler prints a deployment's URL.
#                                                      With the caller's own --dry-run: only that dry run, offline.
#   wrangler-shim.sh _serve --config <toml>            (driver only) start `wrangler dev --local` on that config
#   wrangler-shim.sh _stop                             (driver only) stop it; nothing may listen on the port afterwards
#   anything else                                      refused (exit 2)
#
# Every wrangler process runs under scripts/deploy-rehearsal/offline.sb (macOS sandbox-exec: no outbound network except
# localhost) with CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID unset and metrics off, so neither a dry run nor the dev
# server can reach Cloudflare even if a real token were in the environment.
# Env (set by ci/rehearse-deploy.sh): REHEARSAL_STATE (wrangler dev --persist-to dir holding the fake R2 bucket),
# REHEARSAL_PORT, REHEARSAL_RUN_DIR (pid file, logs, dry-run bundle).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SB="$HERE/offline.sb"
: "${REHEARSAL_STATE:?wrangler-shim: REHEARSAL_STATE not set (only ci/rehearse-deploy.sh runs this)}"
: "${REHEARSAL_PORT:?wrangler-shim: REHEARSAL_PORT not set}"
: "${REHEARSAL_RUN_DIR:?wrangler-shim: REHEARSAL_RUN_DIR not set}"
command -v sandbox-exec >/dev/null || { echo "wrangler-shim: needs macOS sandbox-exec (offline.sb)" >&2; exit 2; }
unset CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CF_API_TOKEN CF_ACCOUNT_ID
export WRANGLER_SEND_METRICS=false
mkdir -p "$REHEARSAL_RUN_DIR"
PID="$REHEARSAL_RUN_DIR/wrangler-dev.pid"

cmd=${1:-}; shift || true
CFG=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do [ "${args[$i]}" = --config ] && CFG=${args[$((i + 1))]:-}; done
# the pinned wrangler of the checkout the config belongs to (<qed64-showcase>/infra/node_modules), else this checkout's
wrangler_for() {
  local d; d="$(cd "$(dirname "$1")" && pwd)"
  if [ -x "$d/infra/node_modules/.bin/wrangler" ]; then echo "$d/infra/node_modules/.bin/wrangler"; else echo "$HERE/../../infra/node_modules/.bin/wrangler"; fi
}
stop_dev() {
  if [ -f "$PID" ]; then
    local p; p=$(cat "$PID")
    pkill -INT -P "$p" 2>/dev/null || true; kill -INT "$p" 2>/dev/null || true
    for _ in $(seq 1 20); do kill -0 "$p" 2>/dev/null || break; sleep 0.5; done
    rm -f "$PID"
  fi
  for _ in $(seq 1 20); do lsof -nP -iTCP:"$REHEARSAL_PORT" -sTCP:LISTEN >/dev/null 2>&1 || return 0; sleep 0.5; done
  echo "wrangler-shim: port $REHEARSAL_PORT still has a listener:" >&2; lsof -nP -iTCP:"$REHEARSAL_PORT" -sTCP:LISTEN >&2; return 1
}
start_dev() {
  local cfg=$1 wr; wr=$(wrangler_for "$cfg")
  stop_dev
  ( cd "$(dirname "$cfg")" && exec sandbox-exec -f "$SB" "$wr" dev --config "$cfg" --local --persist-to "$REHEARSAL_STATE" \
      --ip 127.0.0.1 --port "$REHEARSAL_PORT" --inspector-port $((REHEARSAL_PORT + 1)) --show-interactive-dev-session=false ) \
    >> "$REHEARSAL_RUN_DIR/wrangler-dev.log" 2>&1 < /dev/null &
  echo $! > "$PID"
  for _ in $(seq 1 120); do
    curl -s -o /dev/null "http://127.0.0.1:$REHEARSAL_PORT/runtime/runtime-manifest.json" && return 0
    kill -0 "$(cat "$PID")" 2>/dev/null || { echo "wrangler-shim: wrangler dev exited; tail of $REHEARSAL_RUN_DIR/wrangler-dev.log:" >&2; tail -20 "$REHEARSAL_RUN_DIR/wrangler-dev.log" >&2; return 1; }
    sleep 0.5
  done
  echo "wrangler-shim: wrangler dev did not answer on $REHEARSAL_PORT within 60 s" >&2; return 1
}

case "$cmd" in
  deploy)
    [ -n "$CFG" ] && [ -f "$CFG" ] || { echo "wrangler-shim: deploy needs --config <existing wrangler.toml>" >&2; exit 2; }
    for a in "$@"; do
      if [ "$a" = --dry-run ]; then   # the caller's own dry run (DRY_RUN=1): pass it through, offline; nothing is served
        echo "wrangler-shim: REHEARSAL — the caller's 'wrangler deploy --dry-run', run offline (sandbox, no token)"
        exec sandbox-exec -f "$SB" "$(wrangler_for "$CFG")" deploy "$@"
      fi
    done
    echo "wrangler-shim: REHEARSAL — 'wrangler deploy' becomes 'wrangler deploy --dry-run' (offline sandbox, no token)"
    sandbox-exec -f "$SB" "$(wrangler_for "$CFG")" deploy "$@" --dry-run --outdir "$REHEARSAL_RUN_DIR/wrangler-dry-run"
    echo "wrangler-shim: REHEARSAL — serving that config with 'wrangler dev --local' over the fake R2 state $REHEARSAL_STATE"
    start_dev "$CFG"
    echo "Deployed (rehearsal, nothing uploaded) to"
    echo "  http://127.0.0.1:$REHEARSAL_PORT"
    ;;
  _serve)
    [ -n "$CFG" ] && [ -f "$CFG" ] || { echo "wrangler-shim: _serve needs --config <wrangler.toml>" >&2; exit 2; }
    start_dev "$CFG"; echo "wrangler-shim: serving $CFG at http://127.0.0.1:$REHEARSAL_PORT (pid $(cat "$PID"))" ;;
  _stop) stop_dev; echo "wrangler-shim: stopped; nothing listens on $REHEARSAL_PORT" ;;
  *) echo "wrangler-shim: '$cmd' is not rehearsed (only deploy, _serve, _stop)" >&2; exit 2 ;;
esac
