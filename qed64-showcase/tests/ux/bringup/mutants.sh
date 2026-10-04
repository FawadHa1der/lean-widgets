#!/usr/bin/env bash
# mutants.sh — prove the cursor-hint checks of hints.mjs are not vacuous (stage-B bring-up audit, major finding).
# For each mutant: copy gallery/ to $WORK/mutants/<name>/, replace ONE hinted command in that copy's examples.json
# (the line count is kept, so every other hint still points at its own command), serve the copy on PORT 5192
# (serve.mjs GALLERY_DIR), run the cursor hints of that example against it, and require that exactly the mutated
# hint FAILS and every other cursor hint of that example still passes. The real gallery/ is never touched.
#   M1 tree-scope L41  `#tree_evolve …` (static "HTML Display" panel) -> `#check (41 : Nat)`  (the audit's mutant)
#   M2 hasse-view L21  `#hasse (Fin 4)` (mk_rpc_widget% HassePanel)    -> `#check (Fin 4)`
#   M3 graph-scope L36 `#graph_scope (cycleGraph 6) layout layered`    -> `… (cycleGraph 5) …` (a panel renders, but
#      not the claimed one: wrong svg counts and texts)
# Select / hover (bring-up audit 2: those checks passed without any shift-click / hover). Every hint of the kind run
# must fail exactly as listed:
#   M4 simp-lens hover retargeted (in the copy's examples.json) to the panel's plain <code>simp only [add_zero,
#      zero_add]</code>, an element with no hover popup                                -> the hover hint fails
#   M5 fault no-hover: hints.mjs does everything but the hover (mouse moved away)      -> the hover hint fails
#   M6 fault no-select: hints.mjs does everything but the shift-clicks                 -> all 3 select hints fail
#   M7 expr-xray select #2 shift-clicks only the FIRST occurrence (one pick, not two)  -> that select hint fails
#      (the panel x-rays one subterm instead of comparing two), select #1 still passes
# Usage: tests/ux/bringup/mutants.sh [m1,m2,…]  (takes the browser lock per run; exit 0 iff every mutant is caught)
set -u
SC="$(cd "$(dirname "$0")/../../.." && pwd)"
. "$SC/scripts/lib/env.sh"   # W: scripts/lib/env.sh
LOGS="$W/logs"; mkdir -p "$LOGS" "$W/mutants"
PORT=5192; export PORT
rc_all=0
mutate() { # name pkg line(0-based) old-substring new-line [extra-line-0based new-extra]
  local name="$1" pkg="$2" line="$3" old="$4" new="$5" xline="${6:-}" xnew="${7:-}"
  local dir="$W/mutants/$name"
  rm -rf "$dir"; mkdir -p "$dir"; cp -R "$SC/gallery/." "$dir/"
  node -e '
    const fs = require("fs"); const [f, pkg, line, old, nw, xl, xn] = process.argv.slice(1);
    const j = JSON.parse(fs.readFileSync(f, "utf8")); const ex = j.examples.find((e) => e.id === pkg);
    const L = ex.text.split("\n"); if (!L[+line].includes(old)) { console.error(`mutant: line ${line} lacks ${old}`); process.exit(2); }
    L[+line] = nw; if (xl !== "") L[+xl] = xn; ex.text = L.join("\n");
    fs.writeFileSync(f, JSON.stringify(j, null, 2) + "\n"); console.log(`mutated ${pkg} line ${+line + 1}: ${nw}`);
  ' "$dir/examples.json" "$pkg" "$line" "$old" "$new" "$xline" "$xnew" || return 2
}
run() { # name pkg expect-failing-hint-index
  local name="$1" pkg="$2" want="$3" log="$LOGS/bringup-mutant-$1.log"
  GALLERY_DIR="$W/mutants/$name" "$SC/scripts/serve-start.sh" || return 2
  ORIGIN="http://localhost:$PORT" "$SC/scripts/with-browser-lock.sh" bringup node "$SC/tests/ux/bringup/hints.mjs" --only "$pkg" --kinds cursor --tag "mutant-$name" > "$log" 2>&1
  local hrc=$?
  "$SC/scripts/serve-stop.sh" >/dev/null
  grep -E '^(ok  |FAIL|HINTS)' "$log"
  node -e '
    const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); const want = +process.argv[3];
    const hs = r.examples[process.argv[2]] || []; const failed = hs.filter((h) => !h.ok).map((h) => h.i);
    const caught = failed.length === 1 && failed[0] === want;
    console.log(`MUTANT ${process.argv[4]}: ${caught ? "CAUGHT" : "MISSED"} (failing hints ${JSON.stringify(failed)}, want [${want}]; ${hs.length} cursor hints)`);
    const f = hs.find((h) => h.i === want); if (f) console.log(`  reason: ${f.error || JSON.stringify(f.panel)}`);
    process.exit(caught ? 0 : 1);
  ' "$SC/out/ux/bringup/mutant-$name.json" "$pkg" "$want" "$name" || return 1
  [ "$hrc" = 1 ] || { echo "hints.mjs exit $hrc, want 1"; return 1; }
}
# hint mutant: edit one tryThis entry of the copy's examples.json with a JS expression on `h`
mutate_hint() { # name pkg index js
  local name="$1" pkg="$2" i="$3" js="$4" dir="$W/mutants/$1"
  rm -rf "$dir"; mkdir -p "$dir"; cp -R "$SC/gallery/." "$dir/"
  node -e '
    const fs = require("fs"); const [f, pkg, i, js] = process.argv.slice(1);
    const j = JSON.parse(fs.readFileSync(f, "utf8")); const h = j.examples.find((e) => e.id === pkg).tryThis[+i];
    new Function("h", js)(h); fs.writeFileSync(f, JSON.stringify(j, null, 2) + "\n"); console.log(`mutated ${pkg} hint #${i}: ${JSON.stringify(h).slice(0, 300)}`);
  ' "$dir/examples.json" "$pkg" "$i" "$js" || return 2
}
# run2 name gallery-dir(or "") pkgs kinds want(JSON ["pkg#i", …]) [extra hints.mjs args…]: exactly `want` must fail
run2() {
  local name="$1" gdir="$2" pkgs="$3" kinds="$4" want="$5"; shift 5
  local log="$LOGS/bringup-mutant-$name.log"
  if [ -n "$gdir" ]; then GALLERY_DIR="$gdir" "$SC/scripts/serve-start.sh" || return 2; else "$SC/scripts/serve-start.sh" || return 2; fi
  # hint mutants: hints.mjs must read the mutated hints too (lib.mjs EXAMPLES honours GALLERY_DIR)
  if [ -n "$gdir" ]; then export GALLERY_DIR="$gdir"; else unset GALLERY_DIR; fi
  ORIGIN="http://localhost:$PORT" "$SC/scripts/with-browser-lock.sh" bringup node "$SC/tests/ux/bringup/hints.mjs" --only "$pkgs" --kinds "$kinds" --tag "mutant-$name" "$@" > "$log" 2>&1
  local hrc=$?
  unset GALLERY_DIR
  "$SC/scripts/serve-stop.sh" >/dev/null
  grep -E '^(ok  |FAIL|HINTS|CONSOLE)' "$log"
  node -e '
    const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); const want = JSON.parse(process.argv[2]).sort();
    const all = Object.entries(r.examples).flatMap(([id, hs]) => hs.map((h) => ({ ...h, key: `${id}#${h.i}` })));
    const failed = all.filter((h) => !h.ok).map((h) => h.key).sort();
    const caught = JSON.stringify(failed) === JSON.stringify(want) && !r.error;
    console.log(`MUTANT ${process.argv[3]}: ${caught ? "CAUGHT" : "MISSED"} (failing ${JSON.stringify(failed)}, want ${JSON.stringify(want)}; ${all.length} hints run${r.error ? `; run error ${r.error.slice(0, 200)}` : ""})`);
    for (const h of all.filter((x) => !x.ok)) console.log(`  ${h.key} reason: ${h.error}`);
    process.exit(caught ? 0 : 1);
  ' "$SC/out/ux/bringup/mutant-$name.json" "$want" "$name" || return 1
  [ "$hrc" = 1 ] || { echo "hints.mjs exit $hrc, want 1"; return 1; }
}
hidx() { node -e 'const j=require(process.argv[1]); const e=j.examples.find((x)=>x.id===process.argv[2]); console.log(e.tryThis.map((h,i)=>[h,i]).filter(([h])=>h.kind===process.argv[3]).map(([,i])=>i).join(" "))' "$SC/gallery/examples.json" "$1" "$2"; }
ONLY="${1:-m1,m2,m3,m4,m5,m6,m7}"
pick() { case ",$ONLY," in *",$1,"*) return 0;; *) return 1;; esac; }

idx() { node -e 'const j=require(process.argv[1]); const e=j.examples.find((x)=>x.id===process.argv[2]); console.log(e.tryThis.findIndex((h)=>h.kind==="cursor"&&h.line===+process.argv[3]))' "$SC/gallery/examples.json" "$1" "$2"; }

if pick m1; then mutate m1-tree-evolve tree-scope 40 '#tree_evolve' '#check (41 : Nat) -- MUTANT: no widget here' 41 '-- (mutant: continuation removed)' && run m1-tree-evolve tree-scope "$(idx tree-scope 40)" || rc_all=1; fi
if pick m2; then mutate m2-hasse-fin4 hasse-view 20 '#hasse (Fin 4)' '#check (Fin 4) -- MUTANT' && run m2-hasse-fin4 hasse-view "$(idx hasse-view 20)" || rc_all=1; fi
if pick m3; then mutate m3-graph-c5 graph-scope 35 '(cycleGraph 6)' '#graph_scope (cycleGraph 5) layout layered' && run m3-graph-c5 graph-scope "$(idx graph-scope 35)" || rc_all=1; fi
HV="$(hidx simp-lens hover)"; S1="$(hidx expr-xray select | cut -d' ' -f1)"; S2="$(hidx expr-xray select | cut -d' ' -f2)"; SI="$(hidx interval-inspector select)"
if pick m4; then mutate_hint m4-hover-nopopup simp-lens "$HV" 'h.expectHover.codeText = "simp only [add_zero, zero_add]"; h.expectHover.tagText = "simp only [add_zero, zero_add]";' \
  && run2 m4-hover-nopopup "$W/mutants/m4-hover-nopopup" simp-lens hover "[\"simp-lens#$HV\"]" || rc_all=1; fi
if pick m5; then run2 m5-fault-no-hover "" simp-lens hover "[\"simp-lens#$HV\"]" --fault no-hover || rc_all=1; fi
if pick m6; then run2 m6-fault-no-select "" expr-xray,interval-inspector select "[\"expr-xray#$S1\",\"expr-xray#$S2\",\"interval-inspector#$SI\"]" --fault no-select || rc_all=1; fi
if pick m7; then mutate_hint m7-select-one-pick expr-xray "$S2" 'h.expectSelect = h.expectSelect.slice(0, 1);' \
  && run2 m7-select-one-pick "$W/mutants/m7-select-one-pick" expr-xray select "[\"expr-xray#$S2\"]" || rc_all=1; fi
echo "MUTANTS $([ $rc_all = 0 ] && echo OK || echo FAIL)"
exit $rc_all
