#!/usr/bin/env bash
# Full regeneration + gate for the showcase examples (native, stock v4.34.0).
#   run-all.sh [pkg ...]      (default: all eight)
# Environments: w7 = phase-1 bake (Essential + 7 roots), w8 = phase-2 bake (+ DistLens).
# The primary env is w7 for the 7 phase-1 packages and w8 for dist-lens; phase-1
# packages are ALSO gated and frozen in w8, because the phase-2 bake serves all eight.
# Per package:
#   1. closure CLI gate   (import Mathlib blanked, package's own `lake env lean`)   -> must be 0 errors
#   2. superset CLI gate  (unmodified text) in every env of the package            -> must be 0 errors
#   3. LSP golden         per env (writes lean/expect/[w8/]<pkg>.json + expect/html/[w8/]<pkg>.json,
#                          incl. LSP post-click re-elaboration of every declared click and the
#                          declared code actions)
#   4. every declared click's edited file through the superset CLI gate, per env
#      (clean => rc 0, 0 warnings) and, for information, through the closure CLI gate
#   5. click-all (lsp-golden.mjs --click-all) per env: EVERY rendered MakeEditLink / Try-this
#      link applied to a fresh copy and re-elaborated -> 0 broken (lean/expect/click-all/[w8/]<pkg>.json)
#   6. click-all CLI cross-check (primary env): every click-all edited file through the
#      superset CLI gate must agree with the LSP classification
#   7. LSP closure-mode run (sensitivity: does the package closure alone give the same panels?)
# Writes $W/goldens/run-all.tsv (one row per gate) and exits non-zero if a REQUIRED gate failed.
set -uo pipefail
. "$(cd "$(dirname "$0")/../../scripts/lib" && pwd)/env.sh"   # SC, W: scripts/lib/env.sh
G="$SC/lean/goldens"
PKGS=("$@"); [ ${#PKGS[@]} -eq 0 ] && PKGS=(chart-kit expr-xray simp-lens interval-inspector graph-scope tree-scope hasse-view dist-lens)
mkdir -p "$W/goldens" "$W/logs"
TSV="$W/goldens/run-all.tsv"; : > "$TSV"
fail=0
row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$TSV"; echo "$1 | $2 | $3 | $4 | $5"; }
for p in "${PKGS[@]}"; do
  envs=(w7 w8); prim=w7; [ "$p" = dist-lens ] && { envs=(w8); prim=w8; }
  out=$(GATE_ENV=closure "$G/native-gate.sh" "$p"); rc=$?
  row "$p" example closure-cli "$rc" "$out"; [ $rc -ne 0 ] && fail=1
  for e in "${envs[@]}"; do
    esuf=""; [ "$e" != "$prim" ] && esuf=".$e"
    out=$(GATE_ENV=superset GOLDEN_ENV=$e "$G/native-gate.sh" "$p"); rc=$?
    row "$p" example "superset-cli-$e" "$rc" "$out"; [ $rc -ne 0 ] && fail=1
    node "$G/lsp-golden.mjs" --pkg "$p" --mode superset --env "$e" > "$W/logs/examples-golden-$p$esuf.log" 2>&1; rc=$?
    row "$p" golden "superset-lsp-$e" "$rc" "$(tail -1 "$W/logs/examples-golden-$p$esuf.log")"; [ $rc -ne 0 ] && fail=1
    sub=""; [ "$e" != "$prim" ] && sub="$e/"
    rdir="$W/golden-run/$p-superset"; [ "$e" != "$prim" ] && rdir="$rdir-$e"
    n=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['clicks']))" "$SC/lean/expect/$sub$p.json")
    for ((i = 1; i <= n; i++)); do
      f="$rdir/Showcase.click$i.lean"
      out=$(GATE_ENV=superset GOLDEN_ENV=$e "$G/native-gate.sh" "$p" "$f" "click$i"); rc=$?
      w=$(grep -c ': warning' "$W/logs/examples-native-$p.click$i.superset$esuf.log")
      ok=$([ $rc -eq 0 ] && [ "$w" -eq 0 ] && echo 0 || echo 1)
      row "$p" "click$i" "superset-cli-$e" "$ok" "$out"; [ "$ok" -ne 0 ] && fail=1
      if [ "$e" = "$prim" ]; then
        out=$(GATE_ENV=closure "$G/native-gate.sh" "$p" "$f" "click$i"); rc=$?
        row "$p" "click$i" closure-cli-info "$rc" "$out"
      fi
    done
    node "$G/lsp-golden.mjs" --pkg "$p" --mode superset --env "$e" --click-all > "$W/logs/clickall-$p$esuf.log" 2>&1; rc=$?
    row "$p" click-all "superset-lsp-$e" "$rc" "$(tail -1 "$W/logs/clickall-$p$esuf.log")"; [ $rc -ne 0 ] && fail=1
    if [ "$e" = "$prim" ]; then
      out=$(GOLDEN_ENV=$e "$G/click-all-cli.sh" "$p"); rc=$?
      row "$p" click-all "superset-cli-$e" "$rc" "$out"; [ $rc -ne 0 ] && fail=1
    fi
  done
  node "$G/lsp-golden.mjs" --pkg "$p" --mode closure > "$W/logs/examples-golden-$p.closure.log" 2>&1; rc=$?
  row "$p" golden closure-lsp-info "$rc" "$(tail -1 "$W/logs/examples-golden-$p.closure.log")"
done
echo "REQUIRED-GATES: $([ $fail -eq 0 ] && echo PASS || echo FAIL)"
exit $fail
