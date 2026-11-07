#!/usr/bin/env bash
# Native CLI gate for one showcase example (or an edited/post-click variant).
#   [GATE_ENV=closure|superset] native-gate.sh <pkg> [<source.lean> [<tag>]]
#
# closure (default): the source is copied to $W/examples-native/<pkg>/<pkg>[.<tag>].lean
#   with the `import Mathlib` line blanked (kept as an EMPTY line so every LSP
#   line number is unchanged) and compiled with `lake env lean` from the
#   package's own built tree (read-only use) on the package's own toolchain (its lean-toolchain, via
#   elan's `lake`; superset mode uses $TC and refuses, exit 2, unless it is that version: need_tc_packages):
#   proves every name the example uses lives inside the package closure,
#   hence inside the bake superset.
# superset: the source is copied UNMODIFIED (header `import Mathlib`) to
#   ...<name>.superset.lean and compiled with plain `lean` and the golden-env
#   LEAN_PATH (shadow Mathlib umbrella = QED64.Essential + bake roots), i.e.
#   the browser-equivalent environment (see golden-env.sh).  GOLDEN_ENV=w8 is the one
#   umbrella (one overlay since P2, 2026-11; any other name is refused by golden-env.sh path).
# Output: $W/logs/examples-native-<name>[.superset].log ; exit code = lean's.
set -uo pipefail
. "$(cd "$(dirname "$0")/../../scripts/lib" && pwd)/env.sh"   # SC, W, WS (= <repo>/packages), TC: scripts/lib/env.sh
mode="${GATE_ENV:-closure}"
pkg="$1"; src="${2:-$SC/lean/examples/$pkg.lean}"; tag="${3:-}"
name="$pkg${tag:+.$tag}"
mkdir -p "$W/examples-native/$pkg" "$W/logs"
grep -qx 'import Mathlib' "$src" || { echo "no 'import Mathlib' line in $src" >&2; exit 90; }
start=$(date +%s)
if [ "$mode" = superset ]; then
  need_tc_packages   # before starting Lean: stock Lean of another version cannot load the packages' oleans
  envname="${GOLDEN_ENV:-w8}"
  [ "$envname" = w8 ] || { echo "GOLDEN_ENV=$envname: only w8 (one overlay since P2)" >&2; exit 91; }
  esuf=""
  dst="$W/examples-native/$pkg/$name.superset$esuf.lean"; log="$W/logs/examples-native-$name.superset$esuf.log"
  cp "$src" "$dst"
  LP="$("$SC/lean/goldens/golden-env.sh" path "$envname")"
  ( cd "$W/examples-native/$pkg" && LEAN_PATH="$LP" "$TC/bin/lean" "$dst" ) > "$log" 2>&1
  rc=$?
else
  dst="$W/examples-native/$pkg/$name.lean"; log="$W/logs/examples-native-$name.log"
  sed 's/^import Mathlib$//' "$src" > "$dst"
  ( cd "$WS/$pkg" && lake env lean "$dst" ) > "$log" 2>&1
  rc=$?
fi
end=$(date +%s)
echo "[native-gate/$mode${envname:+/$envname}] $name rc=$rc wall=$((end-start))s errors=$(grep -c ': error' "$log") warnings=$(grep -c ': warning' "$log") log=$log"
exit $rc
