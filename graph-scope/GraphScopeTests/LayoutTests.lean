import GraphScopeTests.Helpers

/-! # Layout tests: circular layout determinism and pinned positions

The viewport is 360×360 with center (180, 180) and radius 140; vertex `i` of
`n` sits at angle `2πi/n` clockwise from 12 o'clock.
-/

namespace GraphScopeTests

open GraphScope

-- Byte-for-byte determinism: computing the layout twice gives equal results.
#guard Layout.circular 7 == Layout.circular 7
#guard Layout.circular 0 == Layout.circular 0

-- One position per vertex.
#guard (Layout.circular 0).positions.size == 0
#guard (Layout.circular 5).positions.size == 5
#guard (Layout.circular 64).positions.size == 64

-- The 12-o'clock start convention: vertex 0 is always at the top center.
#guard (Layout.circular 1).positions == #[(180, 40)]
#guard (Layout.circular 3).positions[0]! == (180, 40)
#guard (Layout.circular 17).positions[0]! == (180, 40)

-- Pinned full layouts for small n (clockwise from the top).
#guard (Layout.circular 2).positions == #[(180, 40), (180, 320)]
#guard (Layout.circular 3).positions == #[(180, 40), (301, 250), (59, 250)]
#guard (Layout.circular 4).positions == #[(180, 40), (320, 180), (180, 320), (40, 180)]
#guard (Layout.circular 6).positions
  == #[(180, 40), (301, 110), (301, 250), (180, 320), (59, 250), (59, 110)]

-- Clockwise means vertex 1 is in the right half-plane for every n ≥ 3.
#guard ((Array.range 62).map fun k => decide ((Layout.circular (k + 3)).positions[1]!.1 > 180))
  |>.all id

-- All positions pairwise distinct (for a representative n).
#guard Id.run do
  let ps := (Layout.circular 6).positions
  for i in [0:ps.size] do
    for j in [i+1:ps.size] do
      if ps[i]! == ps[j]! then
        return false
  return true

#guard Id.run do
  let ps := (Layout.circular 13).positions
  for i in [0:ps.size] do
    for j in [i+1:ps.size] do
      if ps[i]! == ps[j]! then
        return false
  return true

-- Out-of-range `pos` falls back to the viewport center.
#guard (Layout.circular 3).pos 7 == (180, 180)
#guard (Layout.circular 3).pos 2 == (59, 250)

/-! ## BFS-layered layout

Pure `Nat` arithmetic throughout: deterministic by construction (still pinned
byte-for-byte below).  Roots are the smallest vertex of each component; layer
`d` is BFS depth `d`; components sit side by side. -/

-- Byte-for-byte determinism.
#guard Layout.layered (path 5) == Layout.layered (path 5)
#guard Layout.layered twoPaths == Layout.layered twoPaths

-- One position per vertex; the empty graph has none.
#guard (Layout.layered (empty 0)).positions == #[]
#guard (Layout.layered (star 6)).positions.size == 6

-- A path is a single column: one slot wide, one row per vertex.
#guard (Layout.layered (path 5)).positions
  == #[(180, 40), (180, 110), (180, 180), (180, 250), (180, 320)]
-- Shallower trees are centered vertically (path 4: rows start at y = 75).
#guard (Layout.layered (path 4)).positions
  == #[(180, 75), (180, 145), (180, 215), (180, 285)]

-- A star is two layers: the root centered on top, leaves evenly spaced below.
#guard (Layout.layered (star 6)).positions
  == #[(180, 145), (68, 215), (124, 215), (180, 215), (236, 215), (292, 215)]

-- Two components lie side by side, each in its own column band.
#guard (Layout.layered twoPaths).positions
  == #[(110, 110), (110, 180), (110, 250), (250, 110), (250, 180), (250, 250)]

-- Isolated vertices: one single-vertex component per band, all on one row.
#guard (Layout.layered (empty 3)).positions == #[(86, 180), (179, 180), (272, 180)]
#guard (Layout.layered (empty 1)).positions == #[(180, 180)]

-- Layered layout of a *cyclic* graph is legal: BFS layers, non-tree edges
-- become chords (C₅: root, two depth-1, two depth-2 vertices).
#guard (Layout.layered (cycle 5)).positions
  == #[(180, 110), (110, 180), (110, 250), (250, 250), (250, 180)]

-- All positions pairwise distinct on a representative tree and forest.
#guard Id.run do
  let ps := (Layout.layered (star 6)).positions
  for i in [0:ps.size] do
    for j in [i+1:ps.size] do
      if ps[i]! == ps[j]! then
        return false
  return true

#guard Id.run do
  let ps := (Layout.layered twoPaths).positions
  for i in [0:ps.size] do
    for j in [i+1:ps.size] do
      if ps[i]! == ps[j]! then
        return false
  return true

-- Layer assignment: y strictly increases along a path (parent above child).
#guard ((Layout.layered (path 5)).positions.map (·.2)).toList.Pairwise (· < ·)

-- `LayoutMode.resolve`: auto picks layered exactly for forests.
#guard LayoutMode.resolve (path 5) .auto == Layout.layered (path 5)
#guard LayoutMode.resolve (cycle 5) .auto == Layout.circular 5
#guard LayoutMode.resolve (path 5) .circle == Layout.circular 5
#guard LayoutMode.resolve (cycle 5) .layered == Layout.layered (cycle 5)

end GraphScopeTests
