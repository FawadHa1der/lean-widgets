import HasseViewTests.Helpers

/-! # Render tests

Byte-exact pins of the deterministic text report, the caption/report line
helpers (badges, lattice verdict with witness, warnings), and the serialized
SVG (flipped y coordinates, cover edges, badge markers) via
`htmlToDebugString`.
-/

namespace HasseViewTests

open HasseView Render

/-! ## Full text reports, byte-exact -/

#guard textReport (chainP 3) ==
  "poset: 3 elements, 2 cover edges\n\
   rank 2: 2\n\
   rank 1: 1\n\
   rank 0: 0\n\
   ⊥ = 0, ⊤ = 2\n\
   atoms: 1\n\
   coatoms: 1\n\
   lattice ✓\n\
   height: 2 (longest chain: 3 elements)\n\
   antichain width ≥ 1 (largest rank layer; exact width not computed)"

-- Singular nouns for the 1-element poset; bot exists but has no covers.
#guard textReport (chainP 1) ==
  "poset: 1 element, 0 cover edges\n\
   rank 0: 0\n\
   ⊥ = 0, ⊤ = 0\n\
   atoms: (none)\n\
   coatoms: (none)\n\
   lattice ✓\n\
   height: 0 (longest chain: 1 element)\n\
   antichain width ≥ 1 (largest rank layer; exact width not computed)"

-- The empty poset: no rank lines, honest empty caption.
#guard textReport (chainP 0) ==
  "poset: 0 elements, 0 cover edges\n\
   ⊥ = (none), ⊤ = (none)\n\
   lattice ✓\n\
   height: 0 (empty poset)\n\
   antichain width ≥ 0 (largest rank layer; exact width not computed)"

-- A 2-antichain: no bounds, no atoms/coatoms lines, non-lattice witness.
#guard textReport (antichainP 2) ==
  "poset: 2 elements, 0 cover edges\n\
   rank 0: 0, 1\n\
   ⊥ = (none), ⊤ = (none)\n\
   not a lattice: 0, 1 have no join\n\
   height: 0 (longest chain: 1 element)\n\
   antichain width ≥ 2 (largest rank layer; exact width not computed)"

-- A non-antisymmetric preorder is drawn WITH warnings, never silently.
#guard textReport notAntisymP ==
  "poset: 2 elements, 0 cover edges\n\
   rank 0: 0, 1\n\
   ⊥ = (none), ⊤ = (none)\n\
   lattice ✓\n\
   height: 0 (longest chain: 1 element)\n\
   antichain width ≥ 2 (largest rank layer; exact width not computed)\n\
   warning: not a partial order — the diagram may be misleading\n\
   warning: not antisymmetric — 1 pair (e.g. 0 ≤ 1 and 1 ≤ 0)"

/-! ## Line helpers -/

#guard headerLine (cubeP 3) == "poset: 8 elements, 12 cover edges"
#guard headerLine (chainP 2) == "poset: 2 elements, 1 cover edge"
#guard boundsLine bowtieP == "⊥ = 0, ⊤ = (none)"
#guard boundsLine divisor12P == "⊥ = 1, ⊤ = 12"
#guard latticeLine bowtieP == "not a lattice: 1, 2 have no join"
#guard latticeLine (cubeP 3) == "lattice ✓"
-- A meet failure names the dual operation (top 2 over incomparable 0, 1).
#guard latticeLine (mkPoset 3 fun i j => i == j || j == 2)
  == "not a lattice: 0, 1 have no meet"
#guard heightLine divisor12P == "height: 3 (longest chain: 4 elements)"
#guard antichainLine (cubeP 3)
  == "antichain width ≥ 3 (largest rank layer; exact width not computed)"
#guard atomsLine? bowtieP == some "atoms: 1, 2"
#guard coatomsLine? bowtieP == none      -- no top ⇒ no coatoms line
#guard atomsLine? (antichainP 2) == none -- no bot ⇒ no atoms line
#guard rankLine divisor12P 2 == "rank 2: 4, 6"

/-! ## Warning lines with exact counterexamples -/

#guard warningLines (chainP 4) == #[]
#guard warningLines brokenP ==
  #["warning: not a partial order — the diagram may be misleading",
    "warning: not reflexive — 1 element (e.g. ¬ 2 ≤ 2)",
    "warning: not antisymmetric — 1 pair (e.g. 0 ≤ 1 and 1 ≤ 0)",
    "warning: not transitive — 1 triple (e.g. 0 ≤ 1 ≤ 2 but ¬ 0 ≤ 2)"]
#guard warningLines notReflP ==
  #["warning: not a partial order — the diagram may be misleading",
    "warning: not reflexive — 1 element (e.g. ¬ 0 ≤ 0)"]
#guard warningLines notTransP ==
  #["warning: not a partial order — the diagram may be misleading",
    "warning: not transitive — 1 triple (e.g. 0 ≤ 1 ≤ 2 but ¬ 0 ≤ 2)"]

/-! ## Badges -/

#guard badges (chainP 2) 0 == #["⊥", "coatom"]
#guard badges (chainP 2) 1 == #["⊤", "atom"]
#guard badges (cubeP 3) 0 == #["⊥"]
#guard badges (cubeP 3) 1 == #["atom"]
#guard badges (cubeP 3) 6 == #["coatom"]
#guard badges (cubeP 3) 7 == #["⊤"]
#guard badges (chainP 1) 0 == #["⊥", "⊤"]
#guard badges (antichainP 3) 0 == #[]

/-! ## SVG structure (hand-computed flipped coordinates)

Layout of `chainP 2`: centers `(42, 17)`, `(42, 87)`, bounds `84 × 104`.
With `margin = 12` the SVG is `108 × 128`; the y flip puts element 0 at
`cy = 12 + (104 − 17) = 99` (bottom) and element 1 at `cy = 29` (top). -/

private def chain2Svg : String :=
  htmlToDebugString (hasseSvg (chainP 2) (layoutPoset (chainP 2)))

#guard containsSubstr chain2Svg "viewBox=\"0 0 108 128\""
-- The single cover edge runs UPWARD: from the top of box 0 (y = 82) to the
-- bottom of box 1 (y = 46).
#guard containsSubstr chain2Svg
  "<line x1=\"54\" y1=\"82\" x2=\"54\" y2=\"46\""
#guard containsSubstr chain2Svg "data-cover=\"0-1\""
-- Node 0 box: x = 54 − 42 = 12, y = 99 − 17 = 82 (the LOWER box: min at bottom).
#guard containsSubstr chain2Svg "x=\"12\" y=\"82\" width=\"84\" height=\"34\""
-- Badge markers on both elements.
#guard containsSubstr chain2Svg "data-badges=\"⊥ coatom\""
#guard containsSubstr chain2Svg "data-badges=\"⊤ atom\""
-- One box per element, exactly.
#guard countOccurrences chain2Svg "data-node=" == 2
#guard countOccurrences (htmlToDebugString
  (hasseSvg (cubeP 3) (layoutPoset (cubeP 3)))) "data-cover=" == 12

/-! ## Caption block and panel -/

#guard containsSubstr (htmlToDebugString (captionBlock bowtieP))
  "not a lattice: 1, 2 have no join"
#guard containsSubstr (htmlToDebugString (captionBlock brokenP))
  "warning: not transitive — 1 triple (e.g. 0 ≤ 1 ≤ 2 but ¬ 0 ≤ 2)"
#guard containsSubstr (htmlToDebugString (renderPanel (cubeP 3))) "lattice ✓"
-- Custom labels flow through everywhere.
#guard containsSubstr (htmlToDebugString (renderPanel divisor12P)) ">12</text>"

/-! ## `ratPx` exact serialization -/

#guard ratPx 42 == "42"
#guard ratPx 0 == "0"
#guard ratPx (-3 : Rat) == "-3"
-- A non-integer is shown honestly as a fraction, never rounded.
#guard ratPx (85 / 2 : Rat) == "85/2"

end HasseViewTests
