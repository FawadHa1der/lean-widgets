#!/usr/bin/env bash
# Prove the headless verifiers on CONTROLS (the stock QED64 snapshots), serially.
#   (a) E1  exact-header on `import QED64.Essential` vs stock mathlib.snap (+ a designed-error negative)
#   (b) E3  conv? positive control vs init.snap + mathlib.snap, compared with a native golden
#   (c) E3  `import HasseView` with only init.snap -> refused, missing=[HasseView]
#   (d) E3b React contract self-test + the wasm-produced control Html
#   (e) provenance negatives: a byte-flipped APFS clone of init.snap is refused by E3 (sidecar and
#       --index paths) and E1 BEFORE any worker boots; the golden-Html resolver fails (not skips)
#       when the golden Html dump of a MakeEditLink golden is missing (native, ≈0.3 GB)
# Each wasm step is one Node process with a ~10–12 GB peak footprint; they run one
# at a time (scripts/headless/lib.mjs lock + memory guard). Logs: $W/logs/controls-*.log.
# Exit 0 only if every control behaves as specified.
set -uo pipefail
SC="$(cd "$(dirname "$0")/../.." && pwd)"
. "$SC/scripts/lib/env.sh"   # W: scripts/lib/env.sh
H="$SC/scripts/headless"; C="$H/controls"
# the TARGET pin (scripts/lib/pins.mjs: SHOWCASE_PIN=<id>, else the active pin): its served stock index, the tree its stock
# region was baked from, its runtime's raw regions and headless store (the active links, or that pin's own stores)
IX="$(node "$SC/scripts/lib/pins.mjs" release)/public/snapshots/index.json" || exit 2
STOCK_TREE="$(node "$SC/scripts/lib/pins.mjs" field servedTrees.baseSlim)" || exit 2
RAW="$(node "$SC/scripts/lib/pins.mjs" store raw)" || exit 2
HOUT="$(node "$SC/scripts/lib/pins.mjs" store headless)" || exit 2
mkdir -p "$W/logs" "$HOUT"
echo "controls on pin $(node "$SC/scripts/lib/pins.mjs" target) ($(node "$SC/scripts/lib/pins.mjs" target-bid)): index $IX, raw $RAW, results $HOUT"
"$H/derive-raw.sh" || exit 2
# $W/tree-stock is a clone of the served base tree; bump-51, bump-0035 and bump-0035b slim trees are byte-identical
# (docs/REPIN-LOG.md 2026-10-01 §2 and 2026-10-02 pin D: 20,014/20,014 files), so one copy serves every pin so far (made
# from the target pin's tree when missing)
[ -d "$W/tree-stock" ] || cp -Rc "$STOCK_TREE" "$W/tree-stock" || exit 2

declare -a NAMES RCS
step() { local name="$1"; shift; echo "== $name: $*"; "$@" > "$W/logs/controls-$name.log" 2>&1; local rc=$?
  tail -n 1 "$W/logs/controls-$name.log"; NAMES+=("$name"); RCS+=("$rc"); }

step a-e1-essential node "$H/exact-header.mjs" --example "$C/e1-essential.lean" --bake-key "$C/stock-mathlib.BAKE-KEY.txt" \
  --snap "$RAW/mathlib.snap" --index "$IX" --lib "$W/tree-stock" --snapset stock
step a-e1-essential-bad node "$H/exact-header.mjs" --example "$C/e1-essential-bad.lean" --bake-key "$C/stock-mathlib.BAKE-KEY.txt" \
  --snap "$RAW/mathlib.snap" --index "$IX" --lib "$W/tree-stock" --snapset stock --expect fail
step b-e3-conv-native node "$H/rpc-probe.mjs" --transport native --example "$C/conv-control.lean" --golden none
step b-e3-conv-wasm node "$H/rpc-probe.mjs" --example "$C/conv-control.lean" --snap "$RAW/init.snap" --snap "$RAW/mathlib.snap" \
  --index "$IX" --lib "$W/tree-stock" --snapset stock --golden "$HOUT/conv-control.native.rpc.json"
step c-e3-hasse-refused node "$H/rpc-probe.mjs" --example "$C/hasse-refused.lean" --snap "$RAW/init.snap" \
  --lib "$W/tree-stock" --snapset init --golden none
step d-e3b-self-test node "$H/react-contract.mjs" --self-test
step d-e3b-control-html node "$H/react-contract.mjs" --in "$HOUT/conv-control.stock.html.json"

# (e) negatives: each must exit 1 (a FAIL verdict), never 0 and never 2 (setup error)
M="$W/headless/mut"; rm -rf "$M"; mkdir -p "$M"
cp -c "$RAW/init.snap" "$M/init.snap" && cp "$RAW/init.snap.provenance.json" "$M/" &&
  printf '\x2f' | dd of="$M/init.snap" bs=1 seek=60000000 conv=notrunc 2>/dev/null
expect1() { local name="$1"; shift; echo "== $name (expect exit 1): $*"; "$@" > "$W/logs/controls-$name.log" 2>&1; local rc=$?
  tail -n 1 "$W/logs/controls-$name.log"; NAMES+=("$name"); [ "$rc" = 1 ] && RCS+=(0) || RCS+=("neg-got-$rc"); }
expect1 e-e3-flipped-sidecar node "$H/rpc-probe.mjs" --example "$C/hasse-refused.lean" --snap "$M/init.snap" \
  --lib "$W/tree-stock" --snapset mut-sidecar --golden none --out "$W/headless/mut/hasse.mut-sidecar.rpc.json"
expect1 e-e3-flipped-index node "$H/rpc-probe.mjs" --example "$C/hasse-refused.lean" --snap "$M/init.snap" --index "$IX" \
  --lib "$W/tree-stock" --snapset mut-index --golden none --out "$W/headless/mut/hasse.mut-index.rpc.json"
expect1 e-e1-flipped-index node "$H/exact-header.mjs" --example "$C/e1-essential.lean" --bake-key "$C/stock-mathlib.BAKE-KEY.txt" \
  --snap "$M/init.snap" --index "$IX" --lib "$W/tree-stock" --snapset mut --out "$W/headless/mut/e1.mut.e1.json"
expect1 e-e3-golden-html-missing node "$H/rpc-probe.mjs" --transport native --native-env w8 --pkg graph-scope \
  --golden "$SC/lean/expect/w8/graph-scope.json" --golden-html "$M/no-such-html.json" --snapset nohtml --out "$W/headless/mut/graph-scope.nohtml.rpc.json"
rm -rf "$M"

echo; fail=0
for i in "${!NAMES[@]}"; do r=PASS; [ "${RCS[$i]}" = 0 ] || { r=FAIL; fail=1; }; printf '%-24s %s (exit %s)\n' "${NAMES[$i]}" "$r" "${RCS[$i]}"; done
echo "CONTROLS $([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
