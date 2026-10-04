#!/usr/bin/env bash
# Stage 4 (BUILD-PLAN §6): E1 + E3 + E3b for every package on the widget bakes, serially.
#
#   scripts/headless/run-stage4.sh [w8|w7|all] [pkg …]
#
# Every step is logged to $W/logs/s4-<step>.log (with /usr/bin/time -l), its exit code is
# collected, AND its verdict line is required (an uncaught crash that happens to exit 1/0
# never counts as a PASS). The script continues past a failing step so one run shows every
# result, and exits 1 if any step failed. A summary TSV is written to $W/logs/s4-steps.tsv.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$HERE/../lib/env.sh"   # W: scripts/lib/env.sh
cd "$ROOT" || exit 2
# the TARGET pin (scripts/lib/pins.mjs: SHOWCASE_PIN=<id>, else the active pin) and its runtime's stores: raw regions,
# bakes, bake keys and the headless results (the active links, or that pin's own store paths)
P="$ROOT/scripts/lib/pins.mjs"
RAW="$(node "$P" store raw)" || exit 2; HOUT="$(node "$P" store headless)" || exit 2
BW7="$(node "$P" store bake-work-w7)"; BW8="$(node "$P" store bake-work-w8)"; BO7="$(node "$P" store bake-out-w7)"; BO8="$(node "$P" store bake-out-w8)"
BK7="$(node "$P" store BAKE-KEY-w7.txt)"; BK8="$(node "$P" store BAKE-KEY-w8.txt)"
mkdir -p "$HOUT"
echo "stage 4 on pin $(node "$P" target) ($(node "$P" target-bid)): results $HOUT"
WHICH="${1:-all}"; shift || true
PKGS7=(chart-kit expr-xray graph-scope hasse-view interval-inspector simp-lens tree-scope)
PKGS8=("${PKGS7[@]}" dist-lens)
if [ $# -gt 0 ]; then PKGS7=("$@"); PKGS8=("$@"); fi
TSV=$W/logs/s4-steps.tsv
[ -f "$TSV" ] || printf 'when\tbake\tpkg\tstep\trc\tverdict\twall_s\tmaxrss_bytes\tpeak_footprint_bytes\tlog\n' > "$TSV"
FAILS=0

step() { # step <bake> <pkg> <E1|E3|E3b> <verdict-regex> -- cmd…
  local bake=$1 pkg=$2 kind=$3 want=$4; shift 5
  local log=$W/logs/s4-$kind-$pkg.$bake.log t0 t1 rc verdict rss foot
  # never overlap a bake (real bake processes only; see README "Memory")
  while pgrep -f '^(/usr/bin/time -l )?node .*bake-snapshot\.mjs' >/dev/null; do
    echo "[$(date +%T)] waiting: a bake-snapshot is running"; sleep 30; done
  echo "[$(date +%T)] $kind $pkg ($bake): $*"
  t0=$(date +%s)
  /usr/bin/time -l "$@" > "$log" 2>&1; rc=$?
  t1=$(date +%s)
  verdict=$(grep -E "$want" "$log" | tail -1)
  rss=$(awk '/maximum resident set size/{print $1}' "$log" | tail -1)
  foot=$(awk '/peak memory footprint/{print $1}' "$log" | tail -1)
  local ok=1
  [ "$rc" = 0 ] || ok=0
  echo "$verdict" | grep -qE ' PASS |panels clean$' || ok=0
  [ -n "$verdict" ] || ok=0
  [ $ok = 1 ] || FAILS=$((FAILS+1))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$bake" "$pkg" "$kind" "$rc" "${verdict:-<no verdict line>}" "$((t1-t0))" "${rss:-}" "${foot:-}" "$log" >> "$TSV"
  echo "[$(date +%T)]   rc=$rc  ${verdict:-<no verdict line>}  ($((t1-t0)) s, maxrss ${rss:-?})"
}

run_bake() { # run_bake w7|w8
  local b=$1 n snapset idx bw bk; n=${b#w}; snapset=widgets$n
  if [ "$b" = w8 ]; then idx=$BO8/index.json; bw=$BW8; bk=$BK8; else idx=$BO7/index.json; bw=$BW7; bk=$BK7; fi
  local -a pk; if [ "$b" = w8 ]; then pk=("${PKGS8[@]}"); else pk=("${PKGS7[@]}"); fi
  for p in "${pk[@]}"; do
    [ "$b" = w7 ] && [ "$p" = dist-lens ] && continue
    # stale outputs must never be judged: E1/E3/E3b rewrite them
    rm -f "$HOUT/$p.$snapset".{e1,rpc,html,react}.json
    local B=120000 T=300000
    [ "$p" = dist-lens ] && { B=900000; T=900000; }
    step $b $p E1 "^E1 (PASS|FAIL) " -- node "$HERE/exact-header.mjs" --pkg $p --bake-key "$bk" \
      --snap "$bw/widgets.snap" --index "$idx" --lib $W/tree-slim-$b --snapset $snapset --budget-ms $B
    step $b $p E3 "^E3 (PASS|FAIL) " -- node "$HERE/rpc-probe.mjs" --pkg $p --golden-env $b \
      --snap "$RAW/init.snap" --snap "$bw/widgets.snap" --index "$idx" \
      --lib $W/tree-slim-$b --snapset $snapset --timeout-ms $T
    if [ -f "$HOUT/$p.$snapset.html.json" ]; then
      step $b $p E3b "^react verification: " -- node "$HERE/react-contract.mjs" --in "$HOUT/$p.$snapset.html.json"
    else
      step $b $p E3b "^react verification: " -- sh -c "echo 'no html.json from E3 (E3 crashed?)'; exit 1"
    fi
  done
}

case "$WHICH" in
  w8) run_bake w8 ;;
  w7) run_bake w7 ;;
  all) run_bake w8; run_bake w7 ;;
  *) echo "usage: $0 [w8|w7|all] [pkg …]"; exit 2 ;;
esac
echo "STAGE4 $WHICH: $FAILS failing step(s)"
[ $FAILS = 0 ]
