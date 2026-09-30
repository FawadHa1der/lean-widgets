#!/bin/bash
# Build and test every widget package; print a summary table.
# Usage: ./test-all.sh   (from anywhere; resolves its own directory)
set -u
cd "$(dirname "$0")"
PKGS=(interval-inspector expr-xray simp-lens graph-scope tree-scope hasse-view dist-lens chart-kit lean-widget-kit)
declare -a RESULTS
FAIL=0
for p in "${PKGS[@]}"; do
  if [ ! -d "$p" ]; then
    RESULTS+=("$p: MISSING")
    FAIL=1
    continue
  fi
  start=$(date +%s)
  ok=1
  (cd "$p" && lake build >/dev/null 2>&1) || ok=0
  if [ $ok -eq 1 ] && grep -q '^testDriver' "$p/lakefile.toml" 2>/dev/null; then
    (cd "$p" && lake test >/dev/null 2>&1) || ok=0
  fi
  if [ $ok -eq 1 ]; then
    RESULTS+=("$p: GREEN ($(( $(date +%s) - start ))s)")
  else
    RESULTS+=("$p: FAILED")
    FAIL=1
  fi
done
echo "── widget suite ──────────────────"
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo "──────────────────────────────────"
exit $FAIL
