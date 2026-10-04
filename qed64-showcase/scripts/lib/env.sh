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
#   Q           $QED64_REPO           a QED64 checkout (read-only input: pin, verify, stage, overlay preflight)
#   K           $QED64_KERNEL_BUILD   the wasm64 kernel build dir (read-only input: native/, mathlib/, BUILT-COMMIT)
#   KR          $QED64_KERNEL_SRC     the kernel source checkout (read-only; only assert-untouched watches it)
#   LG          $LEAN4GAME_DIR        a wasm64 lean4game checkout (read-only; only assert-untouched watches it)
#   TC          $LEAN_TOOLCHAIN_DIR, default ${ELAN_HOME:-~/.elan}/toolchains/leanprover--lean4---v4.34.0
#   QED64_TOOLCHAIN_IMAGE  the Docker image of QED64's toolchain (default qed64-toolchain:emsdk-6.0.5)
# need <VAR>…: fail with a clear message when a required input is unset or missing (exit 2).
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
K="${QED64_KERNEL_BUILD:-}"
KR="${QED64_KERNEL_SRC:-}"
LG="${LEAN4GAME_DIR:-}"
TC="${LEAN_TOOLCHAIN_DIR:-${ELAN_HOME:-$HOME/.elan}/toolchains/leanprover--lean4---v4.34.0}"
QED64_TOOLCHAIN_IMAGE="${QED64_TOOLCHAIN_IMAGE:-qed64-toolchain:emsdk-6.0.5}"

__env_hint() {
  case "$1" in
    QED64_REPO) echo "a QED64 checkout at the pinned commit (git clone https://github.com/FawadHa1der/QED64; built dist/ and public/ for pin/verify)" ;;
    QED64_KERNEL_BUILD) echo "the wasm64 kernel build dir (native/stage1, mathlib/, BUILT-COMMIT; built from https://github.com/FawadHa1der/lean4 branch qed64-wasm64)" ;;
    QED64_KERNEL_SRC) echo "the kernel source checkout (https://github.com/FawadHa1der/lean4, branch qed64-wasm64)" ;;
    LEAN4GAME_DIR) echo "a wasm64 lean4game checkout" ;;
    LEAN_TOOLCHAIN_DIR) echo "the stock Lean v4.34.0 toolchain (elan toolchain install leanprover/lean4:v4.34.0)" ;;
    *) echo "see qed64-showcase/.env.example" ;;
  esac
}
# need VAR… : every named variable must be set and name an existing path
need() {
  local v val
  for v in "$@"; do
    val="${!v:-}"
    if [ -z "$val" ]; then echo "[env] ERROR: $v is not set: $(__env_hint "$v"). Set it in the environment or in $SC/.env.local (template: .env.example)." >&2; exit 2; fi
    if [ ! -e "$val" ]; then echo "[env] ERROR: $v=$val does not exist: $(__env_hint "$v")." >&2; exit 2; fi
  done
}
