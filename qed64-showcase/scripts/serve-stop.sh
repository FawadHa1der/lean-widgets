#!/usr/bin/env bash
# Stop the background scripts/serve.mjs that serve-start.sh started on PORT (default 5190).
# Pid file: out/serve.pid for 5190, out/serve-<port>.pid for any other PORT (see serve-start.sh).
SC="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-5190}"
PIDF="$SC/out/serve.pid"; [ "$PORT" = 5190 ] || PIDF="$SC/out/serve-$PORT.pid"
if [ -f "$PIDF" ]; then
  pid="$(cat "$PIDF")"
  if kill "$pid" 2>/dev/null; then echo "stopped serve.mjs pid $pid port $PORT"; else echo "pid $pid not running"; fi
  rm -f "$PIDF"
else echo "no $(basename "$PIDF")"; fi
sleep 0.2
left="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null || true)"; [ -n "$left" ] && echo "WARNING port $PORT still has a listener: $left" || true
