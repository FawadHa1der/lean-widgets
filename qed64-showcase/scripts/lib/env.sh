# env.sh — ONE place that says where everything lives (bash; scripts/lib/env.mjs is the same for Node).
# Source it from any script:   . "<path to>/scripts/lib/env.sh"
#
# Locations are never hard-coded: the project root comes from this file's location, everything machine-specific comes
# from environment variables, optionally set in the gitignored file qed64-showcase/.env.local (KEY=VALUE lines, see
# .env.example). A variable already set in the environment wins over .env.local.
#
#   SC          qed64-showcase/ (this project)            REPO_ROOT  the repository root (SC/..)
#   WS          REPO_ROOT/packages (the widget packages, the source of the native widget build)
#   W           $QED64_SHOWCASE_WORK, default ~/.cache/lean-widgets/qed64-showcase-work (heavy work dir: clones, trees,
#               bakes, raw snapshots, logs; must not contain spaces)
#   LOGS        $W/logs
#   Q           $QED64_REPO           a QED64 checkout with its binaries built (read-only input: pin, stage only)
#   K           the TARGET pin's wasm64 kernel build (read-only input: native/, mathlib/, BUILT-COMMIT): $QED64_KERNEL_BUILD
#               names one kernel build dir or a ':'-separated list (one per Lean release); K is the first whose
#               native/NATIVE-COMMIT and mathlib/MATHLIB-COMMIT are the pin lock's, else '' and K_FROM names every rejected
#               one (need QED64_KERNEL_BUILD prints it). K_CANDIDATES: every one of them, ':'-joined (assert-untouched)
#   KR          $QED64_KERNEL_SRC     the kernel source checkout (read-only; only assert-untouched watches it)
#   LG          $LEAN4GAME_DIR        a wasm64 lean4game checkout (read-only; only assert-untouched watches it)
#   TC          $LEAN_TOOLCHAIN_DIR, default ${ELAN_HOME:-~/.elan}/toolchains/leanprover--lean4---v<the TARGET pin's Lean
#               version> (its runtime manifest's leanVersion; when unreadable, v4.34.0 only for a pin whose lock records the
#               lean-v4.34.0 native compiler, pins A–N; else '' and TC_FROM says why)
#   MATHLIB_CLONE  $MATHLIB_CLONE, default $W/mathlib4.<first 8 hex of the target pin lock's toolchain.mathlib.commit> when
#               it exists, else the legacy $W/mathlib4 when its HEAD is that commit; else '' and MATHLIB_CLONE_WHY says
#               why (need MATHLIB_CLONE prints it, naming the expected path). The clone `native` writes and `stage` reads.
#   QED64_TOOLCHAIN_IMAGE  the Docker image of QED64's toolchain (default qed64-toolchain:emsdk-6.0.5)
# The TARGET pin is $SHOWCASE_PIN, else the active pin. K, TC and MATHLIB_CLONE are derived from its files by
# scripts/lib/env.mjs (one implementation, asked once here with --sh; it needs node, as every entry point does; without
# an answer they stay '' and need refuses them).
# need <VAR>…: fail with a clear message when a required input is unset or missing (exit 2).
# need_tc_packages: fail (exit 2) unless TC runs the Lean the widget packages are built with (packages/*/lean-toolchain).
SC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="$(cd "$SC/.." && pwd)"
WS="$REPO_ROOT/packages"

# .env.local: KEY=VALUE (optionally "quoted"), # comments; only keys not already in the environment are taken.
if [ -f "$SC/.env.local" ]; then
  while IFS= read -r __l || [ -n "$__l" ]; do
    __l="${__l#"${__l%%[![:space:]]*}"}"; [ -z "$__l" ] && continue; [ "${__l:0:1}" = '#' ] && continue
    __l="${__l#export }"; __k="${__l%%=*}"; __v="${__l#*=}"
    [[ "$__k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    case "$__v" in \"*\") __v="${__v:1:${#__v}-2}" ;; \'*\') __v="${__v:1:${#__v}-2}" ;; esac
    __v="${__v//\$HOME/$HOME}"; [ "${__v:0:2}" = '~/' ] && __v="$HOME/${__v:2}"
    if [ -z "${!__k+x}" ]; then export "$__k=$__v"; fi
  done < "$SC/.env.local"
  unset __l __k __v
fi

export QED64_SHOWCASE_WORK="${QED64_SHOWCASE_WORK:-$HOME/.cache/lean-widgets/qed64-showcase-work}"
W="$QED64_SHOWCASE_WORK"
LOGS="$W/logs"
Q="${QED64_REPO:-}"
KR="${QED64_KERNEL_SRC:-}"
LG="${LEAN4GAME_DIR:-}"
# K, TC and MATHLIB_CLONE from env.mjs (asked unless TC and MATHLIB_CLONE are explicit and QED64_KERNEL_BUILD is empty);
# an explicit LEAN_TOOLCHAIN_DIR / MATHLIB_CLONE wins, also one this shell set without exporting it (env.mjs did not see
# that one), and QED64_KERNEL_BUILD is handed over explicitly for the same reason
__mc="${MATHLIB_CLONE:-}"; K=""; K_FROM=""; K_CANDIDATES=""; TC=""; TC_LEAN=""; TC_FROM=""; MATHLIB_CLONE=""; MATHLIB_CLONE_WHY=""
if [ -z "${LEAN_TOOLCHAIN_DIR:-}" ] || [ -z "$__mc" ] || [ -n "${QED64_KERNEL_BUILD:-}" ]; then
  __envsh="$(QED64_KERNEL_BUILD="${QED64_KERNEL_BUILD:-}" node "$SC/scripts/lib/env.mjs" --sh 2>/dev/null)" || __envsh=""
  eval "$__envsh"; unset __envsh
fi
if [ -n "${LEAN_TOOLCHAIN_DIR:-}" ]; then TC="$LEAN_TOOLCHAIN_DIR"; TC_FROM=LEAN_TOOLCHAIN_DIR; fi
if [ -n "$__mc" ]; then MATHLIB_CLONE="$__mc"; MATHLIB_CLONE_WHY=""; fi; unset __mc
# no answer from env.mjs: nothing is guessed (a wrong toolchain or kernel build fails late and obscurely), need refuses
__noenv="scripts/lib/env.mjs did not answer (is node on PATH?)"
[ -n "$TC" ] || [ -n "$TC_FROM" ] || TC_FROM="$__noenv; set LEAN_TOOLCHAIN_DIR"
[ -n "$MATHLIB_CLONE" ] || [ -n "$MATHLIB_CLONE_WHY" ] || MATHLIB_CLONE_WHY="$__noenv; set MATHLIB_CLONE"
if [ -z "$K" ] && [ -z "$K_FROM" ]; then
  if [ -n "${QED64_KERNEL_BUILD:-}" ]; then K_FROM="$__noenv: QED64_KERNEL_BUILD is not resolved"; else K_FROM="QED64_KERNEL_BUILD is not set"; fi
fi
unset __noenv
QED64_TOOLCHAIN_IMAGE="${QED64_TOOLCHAIN_IMAGE:-qed64-toolchain:emsdk-6.0.5}"

__env_hint() {
  case "$1" in
    QED64_REPO) echo "a QED64 checkout at the pinned commit with QED64's binaries built (only for pin and stage: the heavy path, docs/BUILD-FROM-SOURCE.md; QED64's sources are the submodule deps/qed64)" ;;
    QED64_KERNEL_BUILD) echo "the target pin's wasm64 kernel build dir, or a ':'-separated list of kernel builds that holds it (native/stage1, mathlib/, BUILT-COMMIT; built from https://github.com/FawadHa1der/lean4 branch qed64-wasm64)" ;;
    QED64_KERNEL_SRC) echo "the kernel source checkout (https://github.com/FawadHa1der/lean4, branch qed64-wasm64)" ;;
    LEAN4GAME_DIR) echo "a wasm64 lean4game checkout" ;;
    LEAN_TOOLCHAIN_DIR) if [ -n "$TC_LEAN" ]; then echo "the stock Lean v$TC_LEAN toolchain of the target pin (elan toolchain install leanprover/lean4:v$TC_LEAN; $TC_FROM)"
                        else echo "the stock Lean toolchain of the target pin, whose Lean version did not resolve: $TC_FROM"; fi ;;
    MATHLIB_CLONE) echo "${MATHLIB_CLONE_WHY:-the target pin's Mathlib clone (\$W/mathlib4.<first 8 hex of its lock's toolchain.mathlib.commit>, or the legacy \$W/mathlib4 at that commit)}" ;;
    *) echo "see qed64-showcase/.env.example" ;;
  esac
}
# need VAR… : every named variable must be set and name an existing path (LEAN_TOOLCHAIN_DIR: TC, its default included;
# QED64_KERNEL_BUILD: K, the target pin's kernel build among the ones it names)
need() {
  local v val
  for v in "$@"; do
    case "$v" in LEAN_TOOLCHAIN_DIR) val="$TC" ;; QED64_KERNEL_BUILD) val="$K" ;; *) val="${!v:-}" ;; esac
    if [ -z "$val" ] && [ "$v" = QED64_KERNEL_BUILD ] && [ -n "${QED64_KERNEL_BUILD:-}" ]; then echo "[env] ERROR: QED64_KERNEL_BUILD names no kernel build of the target pin: $K_FROM. Set it in the environment or in $SC/.env.local (template: .env.example)." >&2; exit 2; fi
    if [ -z "$val" ]; then echo "[env] ERROR: $v is not set: $(__env_hint "$v"). Set it in the environment or in $SC/.env.local (template: .env.example)." >&2; exit 2; fi
    if [ ! -e "$val" ]; then echo "[env] ERROR: $v=$val does not exist: $(__env_hint "$v")." >&2; exit 2; fi
  done
}
# need_tc_packages: TC must run the Lean the widget packages are built with (packages/*/lean-toolchain): stock Lean of
# another version cannot load their .lake oleans, so every consumer that loads them refuses before starting Lean
# (scripts/lib/env.mjs tcPackagesMismatch, the one implementation; exit 2). Only its answer TC-PACKAGES OK passes: a
# silent exit 0 is no answer
need_tc_packages() {
  local why
  need LEAN_TOOLCHAIN_DIR
  why="$(node "$SC/scripts/lib/env.mjs" --tc-packages "$TC" "$TC_FROM" 2>&1)" && [ "$why" = 'TC-PACKAGES OK' ] || { echo "[env] ERROR: ${why:-scripts/lib/env.mjs did not answer (is node on PATH?)}" >&2; exit 2; }
}
