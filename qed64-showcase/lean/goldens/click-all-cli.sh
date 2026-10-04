#!/usr/bin/env bash
# CLI cross-check of the --click-all results: every edited file recorded in
#   out/click-all/[<env>/]<pkg>.json   (links[].editedFile)
# is compiled with the superset CLI gate (native-gate.sh, plain `lean`, golden-env
# LEAN_PATH) and must give rc 0 and 0 warnings when the LSP run classified it
# `clean` (a `designed` link must give rc!=0 or warnings, i.e. agree with LSP).
#   [GOLDEN_ENV=w7|w8] click-all-cli.sh <pkg>      (parallel: CLICK_ALL_JOBS, default 4)
# Writes $W/goldens/click-all-cli.<pkg>[.<env>].tsv (n, classification, rc, warnings, agree)
# and exits 1 if any row disagrees.
set -uo pipefail
. "$(cd "$(dirname "$0")/../../scripts/lib" && pwd)/env.sh"   # SC, W: scripts/lib/env.sh
G="$SC/lean/goldens"
pkg="$1"
defenv=w7; [ "$pkg" = dist-lens ] && defenv=w8
env="${GOLDEN_ENV:-$defenv}"
sub=""; esuf=""; [ "$env" != "$defenv" ] && { sub="$env/"; esuf=".$env"; }
J="$SC/out/click-all/$sub$pkg.json"
[ -f "$J" ] || { echo "missing $J" >&2; exit 2; }
TSV="$W/goldens/click-all-cli.$pkg$esuf.tsv"; : > "$TSV"
export W G pkg env esuf
python3 -c '
import json, sys
for l in json.load(open(sys.argv[1]))["links"]:
    print(l["n"], l["classification"], l["editedFile"], sep="\t")' "$J" |
  xargs -P "${CLICK_ALL_JOBS:-4}" -L 1 bash -c '
    n="$0"; cls="$1"; f="$2"
    out=$(GATE_ENV=superset GOLDEN_ENV="$env" "$G/native-gate.sh" "$pkg" "$f" "clickall-link$n"); rc=$?
    log="$W/logs/examples-native-$pkg.clickall-link$n.superset$esuf.log"
    w=$(grep -c ": warning" "$log")
    if [ "$cls" = clean ]; then ok=$([ $rc -eq 0 ] && [ "$w" -eq 0 ] && echo yes || echo no)
    else ok=$([ $rc -ne 0 ] || [ "$w" -ne 0 ] && echo yes || echo no); fi
    printf "%s\t%s\t%s\t%s\t%s\n" "$n" "$cls" "$rc" "$w" "$ok"'  >> "$TSV"
rows=$(wc -l < "$TSV" | tr -d ' ')
bad=$(awk -F'\t' '$5 != "yes"' "$TSV" | wc -l | tr -d ' ')
echo "[click-all-cli/$env] $pkg: $rows edited files compiled, $((rows - bad)) agree with LSP, $bad disagree (tsv $TSV)"
[ "$bad" -eq 0 ]
