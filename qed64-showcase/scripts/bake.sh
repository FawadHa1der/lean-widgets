#!/usr/bin/env bash
# bake.sh — BUILD-PLAN §5 C3/C4 (+ §9 step 2): bake the widgets superset region for the pinned runtime.
#
#   scripts/bake.sh w7 [--reserve BYTES]     QED64.Essential + 7 roots   -> work/bake-out-w7, work/bake-work-w7
#   scripts/bake.sh w8 [--reserve BYTES]     ... + DistLens              -> work/bake-out-w8, work/bake-work-w8
#
# Runs QED64's bake-snapshot.mjs from the pin's SOURCE dependency (the submodule deps/qed64 at the pin's commit, or
# the pin's worktree: scripts/lib/qed64-src.mjs; never another QED64 checkout) with absolute
# --artifact/--lib/--work/--out under W (no write can land in a QED64 tree). Steps:
#   0. refuse if another bake runs (pgrep bake-snapshot), a browser runs (chrome-headless-shell /
#      Chrome for Testing), a Docker container runs, or free+inactive memory < MIN_FREE_GB (vm_stat)
#   1. C3 seed: out dir = clone of the served init .snapz + index.json holding the init entry verbatim
#   2. write BAKE-KEY-<tag>.txt (the probe's import lines = the exact env-cache key E1 uses)
#   3. bake with QED64_ALLOW_LEGACY_IMPORTS=1 (harmless, C4) under /usr/bin/time -l, while a sampler
#      records the peak summed RSS of the bake's process tree every 2 s
#   4. on "object compactor: out of memory growing the region buffer" rebake once with reserve+512 MiB
#   5. write bake-logs/bake-widgets<7|8>.metrics.json (wall s, peak RSS, reserve, rc) — judging is
#      scripts/judge-bake.mjs, run separately
set -u
SC="$(cd "$(dirname "$0")/.." && pwd)"
. "$(cd "$(dirname "$0")" && pwd)/lib/env.sh"   # W: scripts/lib/env.sh
# the TARGET pin (scripts/lib/pins.mjs targetPinId: SHOWCASE_PIN=<id>, else the active pin): its runtime buildId, its
# release clone (release/<pin id>) and its stores ($W/stage1, bake-work-*, bake-out-*, BAKE-KEY-*, bake-logs: the active
# links into $W/runtimes/<buildId>/, or with SHOWCASE_PIN that pin's store paths themselves; the links are not touched)
P="$SC/scripts/lib/pins.mjs"
BID="$(node "$P" target-bid)" || { echo "REFUSED: no target pin (SHOWCASE_PIN=${SHOWCASE_PIN:-} / the active pin: scripts/showcase.sh pin current)"; exit 3; }
R="$(node "$P" release)" || { echo "REFUSED: the target pin has no release dir"; exit 3; }
store() { node "$P" store "$1"; }
MIN_FREE_GB=${MIN_FREE_GB:-12}

tag="${1:-}"; shift || true
case "$tag" in
  w7) ROOTS=(ChartKit ExprXRay GraphScope HasseView IntervalInspector SimpLens TreeScope); RESERVE=3758096384 ;;
  w8) ROOTS=(ChartKit ExprXRay GraphScope HasseView IntervalInspector SimpLens TreeScope DistLens); RESERVE=4294967296 ;;
  *) echo "usage: $0 w7|w8 [--reserve BYTES]"; exit 2 ;;
esac
while [ $# -gt 0 ]; do case "$1" in --reserve) RESERVE="$2"; shift 2 ;; *) echo "unknown arg $1"; exit 2 ;; esac; done
n="${tag#w}"
# the bake stores are pin links into $W/runtimes/<buildId>/: pass their REAL paths to the wasm tools (Node loads lean.js
# from its realpath, and the runtime's own file lookups must fall inside the mounted directory; see wasm-lsp.mjs)
real() { mkdir -p "$1" 2>/dev/null; (cd "$1" && pwd -P); }
LIB="$W/tree-slim-$tag"; WORK="$(real "$(store "bake-work-$tag")")"; OUT="$(real "$(store "bake-out-$tag")")"; ART="$(real "$(store stage1)")"
# the bake log, metrics and RSS samples belong to the runtime they bake against ($W/bake-logs is a pin link into
# $W/runtimes/<buildId>/bake-logs; judge-bake.mjs reads them there)
BL="$(real "$(store bake-logs)")"
KEYF="$(store "BAKE-KEY-$tag.txt")"; QSRC="$(store qed64)" || exit 2
echo "target pin $(node "$P" target) runtime $BID${SHOWCASE_PIN:+ (SHOWCASE_PIN: its own stores, not the active links)}: art $ART, out $OUT, work $WORK, logs $BL"
LOG="$BL/bake-widgets$n.log"; MET="$BL/bake-widgets$n.metrics.json"; RSSLOG="$BL/bake-widgets$n.rss.tsv"
mkdir -p "$W/logs"

# ---- 0. preconditions ----
# a real bake process is `[/usr/bin/time -l] node … bake-snapshot.mjs`; a bare `pgrep -fl bake-snapshot`
# also matches other sessions' shells whose command text merely mentions the name
if pgrep -fl '^(/usr/bin/time -l )?node .*bake-snapshot\.mjs'; then echo "REFUSED: a bake is already running (above)"; exit 3; fi
if pgrep -fl 'chrome-headless-shell|Google Chrome for Testing'; then echo "REFUSED: a browser session is running (above); bakes never overlap a browser"; exit 3; fi
if [ -n "$(docker ps -q 2>/dev/null)" ]; then echo "REFUSED: a Docker container is running"; docker ps; exit 3; fi
pg=$(vm_stat | awk '/page size of/ {print $8}')
fi_pages=$(vm_stat | awk '/Pages free/ {f=$3} /Pages inactive/ {i=$3} END {gsub(/\./,"",f); gsub(/\./,"",i); print f+i}')
free_gb=$(( fi_pages * pg / 1073741824 ))
echo "free+inactive: ${free_gb} GiB (need >= ${MIN_FREE_GB})"
if [ "$free_gb" -lt "$MIN_FREE_GB" ]; then echo "REFUSED: not enough free memory"; exit 3; fi
[ -f "$LIB.EXPECTED-N" ] || { echo "REFUSED: $LIB.EXPECTED-N missing (run stage-trees.mjs first)"; exit 3; }
bid_art="wasm64-$(shasum -a 256 "$ART/bin/lean.wasm" | cut -c1-16)"
[ "$bid_art" = "$BID" ] || { echo "REFUSED: $ART buildId $bid_art != $BID"; exit 3; }
[ -f "$ART/bin/package.json" ] || { echo "REFUSED: $ART/bin/package.json missing"; exit 3; }

# ---- 1. C3 seed the out dir with the served init ----
rm -rf "$OUT"; mkdir -p "$OUT"
INIT_URL=$(node -e 'const i=require(process.argv[1]);console.log(i.snapshots.find(s=>s.name==="init").url)' "$R/public/snapshots/index.json")
cp -c "$R/public${INIT_URL}" "$OUT/" || exit 4
node -e '
const fs=require("fs");const i=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
const init=i.snapshots.find(s=>s.name==="init");
fs.writeFileSync(process.argv[2], JSON.stringify({schema:"qed64.snapshot-index/v1",snapshots:[init]},null,2));' \
  "$R/public/snapshots/index.json" "$OUT/index.json" || exit 4
echo "seeded $OUT: $(ls "$OUT" | tr '\n' ' ')"

# ---- 2. probe + BAKE-KEY ----
PROBE="import QED64.Essential"
for r in "${ROOTS[@]}"; do PROBE="$PROBE"$'\n'"import $r"; done
KEY="$(printf '%s\n' "$PROBE")"
PROBE="$PROBE"$'\n'"#check (2 + 2 : Nat)"
printf '%s\n' "$KEY" > "$KEYF"; mkdir -p "$SC/out"; cp "$KEYF" "$SC/out/BAKE-KEY-$tag.txt"
echo "BAKE-KEY-$tag.txt: $(paste -sd' ' "$KEYF") ($KEYF)"

run_bake() {
  local reserve="$1"
  echo "=== bake $tag reserve=$reserve lib=$LIB work=$WORK out=$OUT $(date -u +%FT%TZ)" >> "$LOG"
  local t0; t0=$(date +%s)
  ( cd "$W" && QED64_ALLOW_LEGACY_IMPORTS=1 /usr/bin/time -l node --stack-size=8192 "$QSRC/pipeline/snapshot/bake-snapshot.mjs" \
      --name widgets --artifact "$ART" --lib "$LIB" --reserve "$reserve" \
      --work "$WORK" --out "$OUT" --probe "$PROBE" ) >> "$LOG" 2>&1 &
  local bpid=$!
  # sampler: peak summed RSS (KiB) of the bake's process tree
  local peak=0 peakproc=0
  : > "$RSSLOG"
  while kill -0 $bpid 2>/dev/null; do
    local pids="$bpid" frontier="$bpid" next
    while [ -n "$frontier" ]; do
      next=""; for p in $frontier; do next="$next $(pgrep -P "$p" | tr '\n' ' ')"; done
      next="$(echo $next)"; [ -n "$next" ] && pids="$pids $next"; frontier="$next"
    done
    local sum=0 maxp=0 r
    for p in $pids; do r=$(ps -o rss= -p "$p" 2>/dev/null | tr -d ' '); [ -n "$r" ] && { sum=$((sum + r)); [ "$r" -gt "$maxp" ] && maxp=$r; }; done
    [ "$sum" -gt "$peak" ] && peak=$sum; [ "$maxp" -gt "$peakproc" ] && peakproc=$maxp
    printf '%s\t%s\t%s\n' "$(( $(date +%s) - t0 ))" "$sum" "$maxp" >> "$RSSLOG"
    sleep 2
  done
  wait $bpid; local rc=$?
  local t1; t1=$(date +%s)
  BAKE_RC=$rc; BAKE_WALL=$((t1 - t0)); BAKE_PEAK_KIB=$peak; BAKE_PEAKPROC_KIB=$peakproc
  echo "=== bake $tag exit=$rc wall=${BAKE_WALL}s peakTreeRSS=${peak}KiB peakProcRSS=${peakproc}KiB" >> "$LOG"
}

: > "$LOG"
attempt=1; run_bake "$RESERVE"
if grep -q 'object compactor: out of memory growing the region buffer' "$LOG"; then
  RESERVE=$((RESERVE + 536870912)); attempt=2
  echo "compactor reserve exhausted; rebaking with reserve $RESERVE" | tee -a "$LOG"
  run_bake "$RESERVE"
fi
time_maxrss=$(grep -E 'maximum resident set size' "$LOG" | tail -1 | awk '{print $1}')
cat > "$MET" <<EOF
{"tag":"$tag","attempts":$attempt,"reserve":$RESERVE,"rc":$BAKE_RC,"wallSeconds":$BAKE_WALL,
 "peakTreeRssKiB":$BAKE_PEAK_KIB,"peakProcessRssKiB":$BAKE_PEAKPROC_KIB,"timeMaxRssBytes":${time_maxrss:-null},
 "lib":"$LIB","work":"$WORK","out":"$OUT","artifact":"$ART","log":"$LOG","rssSamples":"$RSSLOG"}
EOF
echo "bake $tag: rc=$BAKE_RC wall=${BAKE_WALL}s peak tree RSS $((BAKE_PEAK_KIB / 1024)) MiB (largest process $((BAKE_PEAKPROC_KIB / 1024)) MiB); time -l maxrss ${time_maxrss:-?} B; reserve $RESERVE"
tail -3 "$LOG" | grep -E '^baked|exit=' || true
exit $BAKE_RC
