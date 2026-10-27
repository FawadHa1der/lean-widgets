#!/usr/bin/env bash
# Build the native "browser-equivalent" golden environments (read-only on the
# widget trees; all output under $W/golden-env).
#
# The QED64 page resolves the header `import Mathlib` / `import <Pkg>` as
# "covered" by the overlay snapshot, whose environment is
#   QED64.Essential (the served modules: $K/mathlib/essential-modules.txt) + the package roots of the bake.
# Natively we reproduce that environment by compiling a SHADOW `Mathlib.olean`
# (an umbrella over exactly that module list) and putting its directory first
# on LEAN_PATH, so the unmodified browser text `import Mathlib` resolves to the
# same module set the browser region holds.
#   w7 = Essential + ChartKit ExprXRay GraphScope HasseView IntervalInspector SimpLens TreeScope
#   w8 = w7 + DistLens   (phase 2)
# Usage: golden-env.sh build        -> builds both umbrellas; both envs' BUILT-FROM stamps are removed before merge_pw
#                                     (pw-merged is what both compile against), and each env's (the sha256 of the
#                                     umbrella source it compiled) is written again only once its build succeeded
#        golden-env.sh check <w7|w8> -> REFUSED (exit 2, naming the rebuild) unless BUILT-FROM is the sha256 of that
#                                     env's source: a build that failed anywhere (merge_pw included) leaves no stamp,
#                                     and an env built before build wrote stamps has none (rebuild once). Run by
#                                     lsp-golden.mjs (superset) and, up front, run-all.sh
#        golden-env.sh path <w7|w8> -> prints LEAN_PATH for that env
#        golden-env.sh closure <pkg-dir-name> -> prints the package's own LEAN_PATH (no shadow)
# build and path refuse (exit 2) unless $TC runs the packages' Lean (need_tc_packages): it loads their .lake oleans.
set -euo pipefail
. "$(cd "$(dirname "$0")/../../scripts/lib" && pwd)/env.sh"   # W, WS (= <repo>/packages), TC, K: scripts/lib/env.sh
. "$(cd "$(dirname "$0")/../../scripts/lib" && pwd)/platform.sh"   # clone_file / clone_tree: cp -c on macOS, cp --reflink=auto on Linux
ESS="$K/mathlib/essential-modules.txt"   # needed by `build` only (need QED64_KERNEL_BUILD there: the target pin's)
sha256_() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$@"; else sha256sum "$@"; fi; }
PKGS7="chart-kit expr-xray graph-scope hasse-view interval-inspector simp-lens tree-scope"
ROOTS7="ChartKit ExprXRay GraphScope HasseView IntervalInspector SimpLens TreeScope"

union_path() {
  local p=""
  for k in $PKGS7 dist-lens; do p="$p:$WS/$k/.lake/build/lib/lean"; done
  # ProofWidgets is built per-module on demand, so no single package holds all
  # of it (SelectionPanel exists only in expr-xray's copy).  Lean resolves a
  # package by its first root dir, so we use a merged clone tree (clone_file)
  # (pw-merged; every overlapping .olean/.ir is byte-identical, only lake
  # .trace files differ -- checked by merge_pw).
  p="$p:$W/golden-env/pw-merged"
  for d in Cli batteries Qq aesop importGraph LeanSearchClient plausible mathlib; do
    p="$p:$WS/interval-inspector/.lake/packages/$d/.lake/build/lib/lean"
  done
  echo "${p#:}:$TC/lib/lean"
}

merge_pw() {
  local M="$W/golden-env/pw-merged"; rm -rf "$M"; mkdir -p "$M"
  for src in interval-inspector expr-xray lean-widget-kit graph-scope tree-scope hasse-view dist-lens chart-kit simp-lens; do
    local d="$WS/$src/.lake/packages/proofwidgets/.lake/build/lib/lean"; [ -d "$d" ] || continue
    ( cd "$d" && find . -type f ! -name '*.trace' ) | while read -r f; do
      if [ -f "$M/$f" ]; then cmp -s "$d/$f" "$M/$f" || { echo "MISMATCH $src $f" >&2; exit 1; }
      else mkdir -p "$M/$(dirname "$f")"; clone_file "$d/$f" "$M/$f"; fi
    done
  done
  echo "pw-merged: $(find "$M" -name '*.olean' | wc -l | tr -d ' ') oleans"
}

case "${1:-}" in
  build)
    need QED64_KERNEL_BUILD
    need_tc_packages
    # both stamps go first: merge_pw rewrites the pw-merged tree BOTH envs compile against (and a MISMATCH leaves it
    # half rebuilt), so a build that fails anywhere below leaves no env that `check` passes
    rm -f "$W/golden-env/w7/BUILT-FROM" "$W/golden-env/w8/BUILT-FROM"
    merge_pw
    for env in w7 w8; do
      mkdir -p "$W/golden-env/$env/src" "$W/golden-env/$env/lib"
      # the umbrella olean goes first too: a build that fails below never leaves an older olean by the rewritten source
      rm -f "$W/golden-env/$env/lib/Mathlib.olean"
      roots="$ROOTS7"; [ "$env" = w8 ] && roots="$ROOTS7 DistLens"
      { echo "-- SHADOW umbrella for golden env $env: QED64.Essential module list + package roots"
        sed 's/^/import /' "$ESS"
        for r in $roots; do echo "import $r"; done; } > "$W/golden-env/$env/src/Mathlib.lean"
      echo "== $env: $(grep -c '^import ' "$W/golden-env/$env/src/Mathlib.lean") imports"
      ( cd "$W/golden-env/$env/src" && LEAN_PATH="$(union_path)" "$TC/bin/lean" -R . \
          -o "$W/golden-env/$env/lib/Mathlib.olean" Mathlib.lean )
      # Lean resolves a module root by the FIRST search-path dir holding
      # `Mathlib/` or `Mathlib.olean`, so the shadow dir must also carry the
      # real `Mathlib/` subtree: a clone (clone_tree; never a hard link).
      rm -rf "$W/golden-env/$env/lib/Mathlib"
      clone_tree "$WS/interval-inspector/.lake/packages/mathlib/.lake/build/lib/lean/Mathlib" "$W/golden-env/$env/lib/Mathlib"
      ls -la "$W/golden-env/$env/lib/Mathlib.olean"
      echo "$env Mathlib/ subtree: $(find "$W/golden-env/$env/lib/Mathlib" -name '*.olean' | wc -l | tr -d ' ') oleans"
      ( cd "$W/golden-env/$env/src" && sha256_ Mathlib.lean ) > "$W/golden-env/$env/BUILT-FROM"
    done ;;
  check)
    case "${2:-}" in w7|w8) ;; *) echo "usage: $0 check <w7|w8>" >&2; exit 2 ;; esac
    d="$W/golden-env/$2"; re="rebuild it with lean/goldens/golden-env.sh build"
    [ -f "$d/src/Mathlib.lean" ] || { echo "REFUSED: $d/src/Mathlib.lean is missing: no golden env $2; $re" >&2; exit 2; }
    [ -f "$d/BUILT-FROM" ] || { echo "REFUSED: $d/BUILT-FROM is missing: no successful golden-env.sh build of this source (or one from before build wrote BUILT-FROM); $re" >&2; exit 2; }
    got=""; read -r got _ < "$d/BUILT-FROM" || true
    want="$(cd "$d/src" && sha256_ Mathlib.lean)"
    [ "$got" = "${want%% *}" ] || { echo "REFUSED: $d/BUILT-FROM is not the sha256 of $d/src/Mathlib.lean: no successful golden-env.sh build of this source; $re" >&2; exit 2; } ;;
  path)
    need_tc_packages
    echo "$W/golden-env/$2/lib:$(union_path)" ;;
  closure)
    ( cd "$WS/$2" && lake env printenv LEAN_PATH ) ;;
  *) echo "usage: $0 build | check <w7|w8> | path <w7|w8> | closure <pkg>" >&2; exit 2 ;;
esac
