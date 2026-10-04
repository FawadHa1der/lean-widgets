#!/usr/bin/env bash
# preflight-overlays.sh — BUILD-PLAN §5 C6 live half: QED64's own read-only preflight against our overlays.
#
#   scripts/preflight-overlays.sh [widgets7 widgets8 ...]
#
# Memory discipline: waits (up to WAIT_S, default 900 s) until `pgrep -fl bake-snapshot` prints nothing
# (no bake may overlap a browser), requires >= 6 GiB free+inactive before each boot, then for each
# overlay starts scripts/serve-start.sh (if not already serving), runs
#   node $Q/tests/adversarial/preflight.mjs --url http://localhost:5190/?snapshots=snapshots/<dir> --no-boot
#   node $Q/tests/adversarial/preflight.mjs --url …same… (with the headless boot smoke)
# in place (read-only: no --run-dir) and stops the server it started. Logs: W/logs/preflight-<dir>-{noboot,boot}.log;
# the serve log slice of each boot is kept to show which .snapz files the boot fetched.
set -u
SC="$(cd "$(dirname "$0")/.." && pwd)"
. "$(cd "$(dirname "$0")" && pwd)/lib/env.sh"   # SC, W, Q (QED64_REPO): scripts/lib/env.sh
need QED64_REPO
PORT="${PORT:-5190}"
WAIT_S=${WAIT_S:-900}
# the TARGET pin (scripts/lib/pins.mjs: SHOWCASE_PIN=<id>, else the active pin). serve-start.sh passes SHOWCASE_PIN on to
# serve.mjs, which then serves that pin's release and overlays (X-Showcase-Pin). A staged pin is checked on its own PORT
# (never 5190, the active pin's port) with its own log names (LT), so the active pin's preflight logs stay as they are.
TPIN="$(node "$SC/scripts/lib/pins.mjs" target)" || exit 2
TBID="$(node "$SC/scripts/lib/pins.mjs" target-bid)" || exit 2
LT=""; if [ -n "${SHOWCASE_PIN:-}" ]; then LT="-$TPIN"
  [ "$PORT" != 5190 ] || { echo "REFUSED: SHOWCASE_PIN=$SHOWCASE_PIN needs its own PORT (5190 serves the active pin)"; exit 2; }; fi
served_pin() { curl -s -D - -o /dev/null --max-time 5 "http://localhost:$PORT/showcase/pin.json" | tr -d '\r' | sed -n 's/^[Xx]-[Ss]howcase-[Pp]in: *//p' | head -1; }
dirs=("$@"); [ ${#dirs[@]} -eq 0 ] && dirs=(widgets7 widgets8)
needle="bake-""snapshot"   # assembled so this script's own command text never matches

wait_no_bake() {
  local waited=0 hits
  while :; do
    hits="$(pgrep -fl "$needle" | grep -v -E "^($$|$PPID) " || true)"
    [ -z "$hits" ] && return 0
    if [ $waited -ge "$WAIT_S" ]; then echo "REFUSED: pgrep -fl $needle still prints after ${WAIT_S}s:"; echo "$hits" | cut -c1-200; return 1; fi
    [ $waited -eq 0 ] && { echo "waiting: pgrep -fl $needle prints:"; echo "$hits" | cut -c1-160; }
    sleep 5; waited=$((waited + 5))
  done
}
free_gib() { vm_stat | awk '/page size of/ {ps=$8} /Pages free/ {f=$3} /Pages inactive/ {i=$3} END {gsub(/\./,"",f); gsub(/\./,"",i); printf "%d", (f+i)*ps/1073741824}'; }

started=0
if ! curl -sf -o /dev/null "http://localhost:$PORT/"; then PORT="$PORT" "$SC/scripts/serve-start.sh" || exit 4; started=1; fi
sp="$(served_pin)"
echo "pin $TPIN ($TBID): :$PORT serves pin '${sp:-none}'"
[ "$sp" = "$TPIN $TBID" ] || { echo "REFUSED: :$PORT serves pin '${sp:-none}', not the target '$TPIN $TBID'"; [ $started -eq 1 ] && PORT="$PORT" "$SC/scripts/serve-stop.sh"; exit 4; }
rc_all=0
for d in "${dirs[@]}"; do
  url="http://localhost:$PORT/?snapshots=snapshots/$d"
  node "$Q/tests/adversarial/preflight.mjs" --url "$url" --no-boot > "$W/logs/preflight-$d$LT-noboot.log" 2>&1; rc=$?
  echo "[$d] --no-boot rc=$rc: $(tail -1 "$W/logs/preflight-$d$LT-noboot.log")"; [ $rc -ne 0 ] && rc_all=1
  wait_no_bake || { rc_all=1; continue; }
  fg=$(free_gib); echo "[$d] free+inactive ${fg} GiB"
  if [ "$fg" -lt 6 ]; then echo "[$d] REFUSED boot: < 6 GiB free+inactive"; rc_all=1; continue; fi
  slog="$W/logs/serve-$PORT.log"; before=$(wc -l < "$slog" 2>/dev/null || echo 0)
  node "$Q/tests/adversarial/preflight.mjs" --url "$url" > "$W/logs/preflight-$d$LT-boot.log" 2>&1; rc=$?
  echo "[$d] boot rc=$rc: $(grep -E 'boot smoke' "$W/logs/preflight-$d$LT-boot.log" | tail -1) | $(tail -1 "$W/logs/preflight-$d$LT-boot.log")"
  [ $rc -ne 0 ] && rc_all=1
  tail -n +"$((before + 1))" "$slog" > "$W/logs/preflight-$d$LT-boot.serve.log" 2>/dev/null
  echo "[$d] .snapz requests during boot: $(grep -o '/snapshots/[^ ]*\.snapz[^ ]*' "$W/logs/preflight-$d$LT-boot.serve.log" | sort | uniq -c | tr '\n' ';')"
done
[ $started -eq 1 ] && PORT="$PORT" "$SC/scripts/serve-stop.sh"
pgrep -fl chrome-headless-shell >/dev/null && echo "WARN chrome-headless-shell still running" || echo "no chrome-headless-shell left"
exit $rc_all
