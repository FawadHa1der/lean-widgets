#!/usr/bin/env bash
# Start scripts/serve.mjs in the background; log in work/logs/serve-<port>.log.
# Pid file: out/serve.pid for the default port 5190 (unchanged), out/serve-<port>.pid for any other
# PORT, so a second server on e.g. PORT=5191 is not mistaken for the one already on 5190.
set -eu
SC="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-5190}"
PIDF="$SC/out/serve.pid"; [ "$PORT" = 5190 ] || PIDF="$SC/out/serve-$PORT.pid"
. "$(cd "$(dirname "$0")" && pwd)/lib/env.sh"   # W: scripts/lib/env.sh
LOG="$W/logs/serve-$PORT.log"
mkdir -p "$SC/out" "$(dirname "$LOG")"
if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then echo "already running pid $(cat "$PIDF") port $PORT"; exit 0; fi
PORT="$PORT" nohup node "$SC/scripts/serve.mjs" >> "$LOG" 2>&1 &
echo $! > "$PIDF"
for _ in $(seq 1 50); do curl -sf -o /dev/null "http://localhost:$PORT/" && { echo "serve.mjs up pid $(cat "$PIDF") port $PORT log $LOG"; exit 0; }; sleep 0.1; done
echo "serve.mjs failed to start; see $LOG"; exit 1
