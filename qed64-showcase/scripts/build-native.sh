#!/usr/bin/env bash
# Native64 build of the Mathlib/ProofWidgets delta and the widget libraries, inside
# Docker, writing ONLY into the APFS clone $W/mathlib4 (BUILD-PLAN.md §4 B0-B4, §9.1).
#
#   scripts/build-native.sh identity          B1  lean/lake identity inside the container
#   scripts/build-native.sh reuse-gate <tag> [list]  B2  lake build --no-build (plan's 3 modules, or a module list)
#   scripts/build-native.sh delta             B3  phase-1 Mathlib/ProofWidgets delta (out/delta-phase1.txt)
#   scripts/build-native.sh append            B4a append lean/lakefile-append.lean to the CLONE's lakefile (idempotent)
#   scripts/build-native.sh widgets           B4  the seven phase-1 widget libraries (T=6)
#   scripts/build-native.sh distlens          §9.1 DistLens + LeanWidgetKit (T=4; rerun with T=2 on rc 137)
#   scripts/build-native.sh header-gate       S2  olean header gate (host side, node)
#   scripts/build-native.sh lake '<cmd>'      any command in the same container (debugging)
#
# Mount layout mirrors wasm64-lean-kernel/wasm64-build/mathlib-tree.sh run(): the
# workspace is at /work/mathlib4 and the native compiler at /native (read-only), so
# Lake traces recorded by the original build (paths, lean githash '') still match.
# Additions (no effect on traces): --network none, LAKE_NO_CACHE, LAKE_ARTIFACT_CACHE=false,
# the read-only widget sources at /work/mathlib4/widgets.
#
# Every step logs into $W/logs/<step>.log, samples `docker stats` into
# $W/logs/<step>.stats, and appends one JSON line to $W/logs/steps.jsonl.
# Exit status is the container's (never masked by a pipe).
set -uo pipefail

SC="$(cd "$(dirname "$0")/.." && pwd)"
. "$(cd "$(dirname "$0")" && pwd)/lib/env.sh"   # W, K (QED64_KERNEL_BUILD), QED64_TOOLCHAIN_IMAGE
need QED64_KERNEL_BUILD
IMG="$QED64_TOOLCHAIN_IMAGE"
LOGS="$W/logs"
mkdir -p "$LOGS"

PHASE1_LIBS="ChartKit ExprXRay GraphScope HasseView IntervalInspector SimpLens TreeScope"
PHASE2_LIBS="DistLens LeanWidgetKit"
GATE_MODULES="Mathlib.Order.Basic Mathlib.Tactic ProofWidgets.Component.HtmlDisplay"

die() { echo "build-native: $*" >&2; exit 2; }

# Refuse to run if a read-only tree could be the write target.
[ -d "$W/mathlib4/.lake/build/lib/lean/Mathlib" ] || die "no clone at $W/mathlib4 (run B0: cp -cpR $K/mathlib/mathlib4 $W/mathlib4)"
[ "$(stat -f %l "$W/mathlib4/.lake/build/lib/lean/Mathlib/Order/Basic.olean")" = 1 ] || die "clone shares inodes (nlink != 1): refusing"
[ -f "$W/widgets-src/SOURCE-HASH.txt" ] || die "no widget export at $W/widgets-src"

# run <step-name> <bash command>  — one container, logged, stats-sampled, timed.
run() {
  local step="$1" cmd="$2" name="qed64sc-$1-$$"
  local log="$LOGS/$step.log" stats="$LOGS/$step.stats"
  local stamp="/work/mathlib4/.lake/showcase-stamps/$step"
  if docker ps --format '{{.Names}}' | grep -q .; then
    die "another container is running (one Docker job at a time): $(docker ps --format '{{.Names}}' | tr '\n' ' ')"
  fi
  : > "$stats"
  echo "=== $step T=${T:-6} $(date -u +%FT%TZ)" > "$log"
  echo "--- cmd: $cmd" >> "$log"
  local t0; t0=$(date +%s)
  ( while sleep 2; do
      docker stats --no-stream --format '{{.MemUsage}}' "$name" 2>/dev/null | sed "s/^/$(date +%s) /" >> "$stats"
    done ) &
  local sampler=$!
  docker run --rm --name "$name" --network none \
    -e LEAN_CC=/usr/bin/gcc -e "LEAN_NUM_THREADS=${T:-6}" \
    -e LAKE_NO_CACHE=1 -e LAKE_ARTIFACT_CACHE=false \
    -e "PATH=/native/stage1/bin:/emsdk/node/current/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    -v "$K/native":/native:ro \
    -v "$W/mathlib4":/work/mathlib4 \
    -v "$W/widgets-src":/work/mathlib4/widgets:ro \
    -w /work/mathlib4 "$IMG" \
    bash -lc "export PATH=/native/stage1/bin:\$PATH; git config --global --add safe.directory '*'; mkdir -p /work/mathlib4/.lake/showcase-stamps && touch $stamp; $cmd" \
    >> "$log" 2>&1
  local rc=$?
  kill "$sampler" 2>/dev/null; wait "$sampler" 2>/dev/null
  local t1; t1=$(date +%s)
  # peak MemUsage ("1.234GiB / 7.653GiB") in MiB
  local peak
  peak=$(awk '{u=$2; v=u+0; if (u ~ /GiB/) v*=1024; else if (u ~ /KiB/) v/=1024; else if (u ~ /B$/ && u !~ /MiB/) v/=1048576; if (v>m) m=v} END{printf "%.0f", m+0}' "$stats")
  # oleans written by this step (newer than the in-container stamp)
  local new="$LOGS/$step.new-oleans.txt"
  if [ -f "$W/mathlib4/.lake/showcase-stamps/$step" ]; then
    find "$W/mathlib4/.lake" -name '*.olean' -newer "$W/mathlib4/.lake/showcase-stamps/$step" \
      | sed -e "s|^$W/mathlib4/||" | LC_ALL=C sort > "$new"
  else
    : > "$new"
  fi
  local nnew; nnew=$(wc -l < "$new" | tr -d ' ')
  echo "--- rc=$rc wall=$((t1-t0))s peakMiB=$peak newOleans=$nnew" >> "$log"
  printf '{"step":"%s","T":%s,"rc":%d,"wallSeconds":%d,"peakMemMiB":%s,"newOleans":%d,"start":%d,"end":%d,"cmd":"%s"}\n' \
    "$step" "${T:-6}" "$rc" "$((t1-t0))" "${peak:-null}" "$nnew" "$t0" "$t1" "$(printf '%s' "$cmd" | sed 's/"/\\"/g')" >> "$LOGS/steps.jsonl"
  echo "$step: rc=$rc wall=$((t1-t0))s peakMiB=$peak newOleans=$nnew (log $log)"
  return $rc
}

append_lakefile() {
  local lf="$W/mathlib4/lakefile.lean" ap="$SC/lean/lakefile-append.lean"
  [ -f "$ap" ] || die "missing $ap"
  if grep -q '^-- qed64-showcase: widget libraries' "$lf"; then
    echo "append: already present in $lf"
  else
    [ -f "$W/mathlib4/lakefile.lean.pre-append" ] || cp -p "$lf" "$W/mathlib4/lakefile.lean.pre-append"
    { printf '\n'; cat "$ap"; } >> "$lf"
    echo "append: appended $ap to $lf"
  fi
  diff "$W/mathlib4/lakefile.lean.pre-append" "$lf"
  return 0
}

step="${1:-}"; shift || true
case "$step" in
  identity)
    run b1-identity 'which lean lake; lean --version; lake --version; printf "githash=[%s]\n" "$(lean --githash)"; lean --print-prefix; env | grep -E "^(LEAN|LAKE|ELAN)" | sort' ;;
  reuse-gate)
    # reuse-gate <tag> [module-list-file]: the plan's three modules, or every module in the file
    tag="${1:-pre}"; mods="$GATE_MODULES"
    if [ -n "${2:-}" ]; then mods="$(tr '\n' ' ' < "$2")"; fi
    run "b2-reuse-gate-$tag" "lake build --no-build $mods" ;;
  delta)
    list="$SC/out/delta-phase1.txt"; [ -s "$list" ] || die "missing $list (scripts/delta.py)"
    run b3-delta "lake build $(tr '\n' ' ' < "$list")" ;;
  append)
    append_lakefile ;;
  widgets)
    grep -q '^-- qed64-showcase: widget libraries' "$W/mathlib4/lakefile.lean" || die "run 'append' first"
    run "b4-widgets${1:+-$1}" "lake build $PHASE1_LIBS" ;;
  distlens)
    grep -q '^-- qed64-showcase: widget libraries' "$W/mathlib4/lakefile.lean" || die "run 'append' first"
    T="${T:-4}" run "s7-distlens-T${T:-4}" "lake build $PHASE2_LIBS" ;;
  header-gate)
    node "$SC/scripts/header-gate.mjs" "$@" ;;
  lake)
    run "adhoc-$(date +%s)" "$*" ;;
  *)
    sed -n '2,20p' "$0"; exit 2 ;;
esac
