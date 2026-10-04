#!/usr/bin/env bash
# E2 (BUILD-PLAN §6): every package's Demo.lean, verbatim, compiled by the pinned wasm runtime
# (QED64's supervised-run.mjs -> node-runner.mjs, from the pin's source dependency) against $W/tree-fat. Serial.
#
#   scripts/headless/run-e2.sh [pkg …]
#
# Per package: $W/run/<pkg>/Demo.lean is an APFS clone of widgets-src/<pkg>/<Lib>/Demo.lean
# (sha256 recorded and re-checked against the source), the log is $W/logs/s4-E2-<pkg>.log
# (with /usr/bin/time -l), and a TSV row goes to $W/logs/s4-e2.tsv. supervised-run fails on
# ": error|PANIC|ABORT|RuntimeError|uncaught exception"; this wrapper additionally fails on
# any Lean "warning:" line or "#guard" failure text in the log, and requires Demo.olean.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$HERE/../lib/env.sh"   # W: scripts/lib/env.sh
# the TARGET pin (scripts/lib/pins.mjs: SHOWCASE_PIN=<id>, else the active pin): QED64's runner at its commit and its stage1
P="$ROOT/scripts/lib/pins.mjs"
SR="$(node "$P" store qed64)/pipeline/snapshot/supervised-run.mjs" || exit 2
ART="$(cd "$(node "$P" store stage1)" && pwd -P)" || exit 2
BIDT="$(node "$P" target-bid)" || exit 2
echo "E2 on pin $(node "$P" target) ($BIDT): artifact $ART"
PKGS=(chart-kit expr-xray graph-scope hasse-view interval-inspector simp-lens tree-scope dist-lens)
[ $# -gt 0 ] && PKGS=("$@")
TSV=$W/logs/s4-e2.$BIDT.tsv   # one TSV per runtime (summarize-stage4.mjs reads the target runtime's)
[ -f "$TSV" ] || printf 'when\tpkg\trc\tverdict\twall_s\tmaxrss_bytes\tpeak_footprint_bytes\tdemo_sha256\tolean_bytes\twarnings\tlog\n' > "$TSV"
FAILS=0
for p in "${PKGS[@]}"; do
  src=$(ls "$W"/widgets-src/$p/*/Demo.lean 2>/dev/null | head -1)
  [ -n "$src" ] || { echo "no Demo.lean for $p"; FAILS=$((FAILS+1)); continue; }
  d=$W/run/$p; mkdir -p "$d"; rm -f "$d/Demo.lean" "$d/Demo.olean" "$d"/Demo.ilean
  cp -c "$src" "$d/Demo.lean"
  s1=$(shasum -a 256 "$src" | cut -c1-64); s2=$(shasum -a 256 "$d/Demo.lean" | cut -c1-64)
  [ "$s1" = "$s2" ] || { echo "copy mismatch for $p"; FAILS=$((FAILS+1)); continue; }
  while pgrep -f '^(/usr/bin/time -l )?node .*bake-snapshot\.mjs' >/dev/null; do
    echo "[$(date +%T)] waiting: a bake-snapshot is running"; sleep 30; done
  while [ -e "$W/headless/.lock" ]; do echo "[$(date +%T)] waiting: headless lock held"; sleep 30; done
  free_gb=$(vm_stat | awk '/page size of/{ps=$8} /Pages free/{f=$3} /Pages inactive/{i=$3} END{gsub(/\./,"",f);gsub(/\./,"",i);printf "%d", (f+i)*ps/1073741824}')
  if [ "$free_gb" -lt 12 ]; then echo "[$(date +%T)] E2 $p: only ${free_gb} GiB free+inactive, waiting"; sleep 60; fi
  log=$W/logs/s4-E2-$p.log
  echo "[$(date +%T)] E2 $p (${free_gb} GiB free+inactive): $src"
  t0=$(date +%s)
  /usr/bin/time -l node "$SR" --target "$d/Demo.olean" --quiet-ms 60000 --stable-ms 30000 --give-up-ms 5400000 -- \
    --artifact "$ART" --lib "$W/tree-fat" --work "$d" -- -o /work/Demo.olean /work/Demo.lean > "$log" 2>&1
  rc=$?; t1=$(date +%s)
  verdict=$(grep -E '^supervised-run: ' "$log" | tail -1)
  rss=$(awk '/maximum resident set size/{print $1}' "$log" | tail -1)
  foot=$(awk '/peak memory footprint/{print $1}' "$log" | tail -1)
  warns=$(grep -cE '(: warning[:( ]|^warning:)' "$log")
  ob=$(stat -f %z "$d/Demo.olean" 2>/dev/null || echo 0)
  ok=1; [ "$rc" = 0 ] || ok=0; [ "$warns" = 0 ] || ok=0; [ "$ob" -gt 0 ] || ok=0
  grep -qE '#guard|guard_msgs.*(fail|mismatch)|Stack overflow|stack overflow|unreachable' "$log" && ok=0
  [ $ok = 1 ] || FAILS=$((FAILS+1))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$p" "$rc" "${verdict:-<none>}" "$((t1-t0))" "${rss:-}" "${foot:-}" "$s1" "$ob" "$warns" "$log" >> "$TSV"
  echo "[$(date +%T)]   E2 $p rc=$rc ok=$ok warnings=$warns olean=$ob  ${verdict:-<none>}  ($((t1-t0)) s, maxrss ${rss:-?})"
done
echo "E2: $FAILS failing Demo(s)"
[ $FAILS = 0 ]
