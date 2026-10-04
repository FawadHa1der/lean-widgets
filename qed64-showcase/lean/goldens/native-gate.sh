#!/usr/bin/env bash
# Native CLI gate for one showcase example (or an edited/post-click variant).
#   [GATE_ENV=closure|superset] native-gate.sh <pkg> [<source.lean> [<tag>]]
#
# closure (default): the source is copied to $W/examples-native/<pkg>/<pkg>[.<tag>].lean
#   with the `import Mathlib` line blanked (kept as an EMPTY line so every LSP
#   line number is unchanged) and compiled with `lake env lean` from the
#   package's own built tree (read-only use) on the stock v4.34.0 toolchain:
#   proves every name the example uses lives inside the package closure,
#   hence inside the bake superset.
# superset: the source is copied UNMODIFIED (header `import Mathlib`) to
#   ...<name>.superset.lean and compiled with plain `lean` and the golden-env
#   LEAN_PATH (shadow Mathlib umbrella = QED64.Essential + bake roots), i.e.
#   the browser-equivalent environment (see golden-env.sh).  GOLDEN_ENV=w7|w8 picks
#   the umbrella (default: w7, dist-lens w8); a non-default env adds `.<env>` to the
#   copy/log names.
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
  defenv=w7; [ "$pkg" = dist-lens ] && defenv=w8
  envname="${GOLDEN_ENV:-$defenv}"
  [ "$pkg" = dist-lens ] && [ "$envname" != w8 ] && { echo "dist-lens exists only in w8" >&2; exit 91; }
  esuf=""; [ "$envname" != "$defenv" ] && esuf=".$envname"
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
