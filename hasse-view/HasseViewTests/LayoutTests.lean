import HasseViewTests.Helpers

/-! # Layout tests

Exact-ℚ pins of the layered layout (hand-computed from the constants
`nodeW = 84`, `nodeH = 34`, `hGap = 18`, `vGap = 36`, `levelStep = 70`) plus
the property checker `layoutOk` (integrality, y monotone in rank, distinct
positions, bounds containment) over every test poset.
-/

namespace HasseViewTests

open HasseView

/-! ## Hand-computed exact pins -/

-- Chain of 3: a single column, x = 42, rows at y = 17, 87, 157.
#guard (layoutPoset (chainP 3)).positions == #[(42, 17), (42, 87), (42, 157)]
#guard (layoutPoset (chainP 3)).width == 84
#guard (layoutPoset (chainP 3)).height == 174

-- Antichain of 2: one row, evenly spaced (spacing nodeW + hGap = 102).
#guard (layoutPoset (antichainP 2)).positions == #[(42, 17), (144, 17)]
#guard (layoutPoset (antichainP 2)).width == 186
#guard (layoutPoset (antichainP 2)).height == 34

-- The 3-cube: widest rows have 3 boxes (width 288), narrow rows centered.
#guard (layoutPoset (cubeP 3)).width == 288
#guard (layoutPoset (cubeP 3)).height == 244
#guard (layoutPoset (cubeP 3)).positions ==   -- index-aligned:
  #[(144, 17),                          -- 0 = ∅      rank 0, centered
    (42, 87), (144, 87),                -- 1 = {0}, 2 = {1}    rank 1
    (42, 157),                          -- 3 = {0,1}  rank 2, slot 0
    (246, 87),                          -- 4 = {2}    rank 1, slot 2
    (144, 157), (246, 157),             -- 5 = {0,2}, 6 = {1,2}  rank 2
    (144, 227)]                         -- 7 = ⊤      rank 3, centered
-- Same-rank neighbors are exactly 102 px apart; rank rows 70 px apart.
#guard ((layoutPoset (cubeP 3)).pos 2).1 - ((layoutPoset (cubeP 3)).pos 1).1 == 102
#guard ((layoutPoset (cubeP 3)).pos 3).2 - ((layoutPoset (cubeP 3)).pos 1).2 == 70

-- Bowtie: rank rows of sizes 1, 2, 2 — width from the 2-rows.
#guard (layoutPoset bowtieP).width == 186
#guard (layoutPoset bowtieP).positions ==
  #[(93, 17), (42, 87), (144, 87), (42, 157), (144, 157)]

-- Empty poset: empty layout with zero bounds.
#guard (layoutPoset (chainP 0)).positions == #[]
#guard (layoutPoset (chainP 0)).width == 0
#guard (layoutPoset (chainP 0)).height == 0

-- One element: a single centered box.
#guard (layoutPoset (chainP 1)).positions == #[(42, 17)]

-- Out-of-range `pos` defaults to the origin.
#guard (layoutPoset (chainP 2)).pos 9 == (0, 0)

/-! ## Row-width helper -/

#guard rowWidth 0 == 0
#guard rowWidth 1 == 84
#guard rowWidth 3 == 288

/-! ## Properties over every test poset

`layoutOk` re-checks: index alignment, integer-valued exact coordinates,
`y` strictly increasing with rank (in layout coordinates — the renderer
flips for the min-at-bottom convention), distinct positions, and every box
inside `[0, width] × [0, height]`. -/

#guard layoutOk (chainP 5)
#guard layoutOk (chainP 1)
#guard layoutOk (chainP 0)
#guard layoutOk (antichainP 4)
#guard layoutOk (cubeP 3)
#guard layoutOk (cubeP 4)
#guard layoutOk diamondP
#guard layoutOk bowtieP
#guard layoutOk divisor12P
-- Layouts stay lawful even for invalid tables (the renderer still draws
-- them, with warnings).
#guard layoutOk notAntisymP
#guard layoutOk brokenP

end HasseViewTests
