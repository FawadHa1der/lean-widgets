import HasseView.Model
import Mathlib.Data.Rat.Defs

/-! # HasseView: exact-ℚ layered layout

One row per rank, elements within a row evenly spaced in enumeration order,
all arithmetic exact in `Rat` — the layout is a byte-for-byte deterministic
function of the `PosetData`.

## Coordinate convention

`PLayout` positions live in **abstract "order" coordinates**: `y` *increases
with rank* (`y = nodeH/2 + rank · levelStep`), which is what the layout
property tests pin.  The **renderer flips the y axis** (`svgY = height − y`)
so that, per the classical Hasse convention, minimal elements are drawn at
the *bottom* of the picture and cover edges point upward.

All constants are even integers (and `levelStep = nodeH + vGap`), so every
computed center coordinate is an integer-valued `Rat` — the SVG serialization
is exact, no rounding anywhere.

Guaranteed properties (re-checked in `HasseViewTests.LayoutTests`):

(a) **determinism** — pure function, exact arithmetic;
(b) **distinct positions** — same-row centers are exactly `nodeW + hGap`
    apart, different ranks differ in `y`;
(c) **monotone rows** — `y` strictly increases with rank;
(d) **bounds containment** — every node box fits inside
    `[0, width] × [0, height]`.

## Not implemented (honest)

The single-pass **barycenter refinement** (reordering a row by the mean `x`
of each element's lower covers to reduce edge crossings) is NOT implemented —
rows are in plain enumeration order, so wide posets may show more crossings
than necessary.  See the README's limitations section.
-/

namespace HasseView

namespace Layout

/-- Node box width, px (exact, even). -/
def nodeW : Rat := 84
/-- Node box height, px (exact, even). -/
def nodeH : Rat := 34
/-- Horizontal gap between adjacent boxes in a row, px (even). -/
def hGap : Rat := 18
/-- Vertical gap between rows, px (even). -/
def vGap : Rat := 36
/-- Vertical distance between consecutive row centers: `nodeH + vGap`. -/
def levelStep : Rat := nodeH + vGap

end Layout

/-- Layout of a poset: exact center positions per element (index-aligned,
abstract coordinates — `y` increases with rank, the renderer flips) plus the
overall bounds. -/
structure PLayout where
  /-- `positions[i]` is the exact `(x, y)` center of element `i`'s box. -/
  positions : Array (Rat × Rat)
  /-- Total width (the widest row). -/
  width : Rat
  /-- Total height (`nodeH + height·levelStep` for a nonempty poset). -/
  height : Rat
  deriving Repr, BEq, Inhabited

namespace PLayout

/-- Center of element `i` (defaults to the origin if out of range). -/
def pos (l : PLayout) (i : Nat) : Rat × Rat :=
  l.positions[i]?.getD (0, 0)

end PLayout

/-- The exact width of a row of `k` node boxes: `k·nodeW + (k−1)·hGap`
(`0` for an empty row). -/
def rowWidth (k : Nat) : Rat :=
  if k == 0 then 0 else k * Layout.nodeW + (k - 1 : Nat) * Layout.hGap

/-- Layered layout (see the module docstring): one row per rank, rows
horizontally centered on the widest row, elements within a row in
enumeration order at even spacing, `y = nodeH/2 + rank · levelStep`. -/
def layoutPoset (d : PosetData) : PLayout := Id.run do
  if d.n == 0 then
    return { positions := #[], width := 0, height := 0 }
  let h := d.height
  let totalW := (List.range (h + 1)).foldl
    (fun acc r => max acc (rowWidth (d.layer r).size)) 0
  -- slot[i] := position of i within its rank row (enumeration order).
  let mut slot := Array.replicate d.n 0
  for r in [0:h + 1] do
    let row := d.layer r
    for s in [0:row.size] do
      slot := slot.set! (row.getD s 0) s
  let ranks := d.ranks
  let positions := (Array.range d.n).map fun i =>
    let r := ranks.getD i 0
    let k := (d.layer r).size
    let x0 := (totalW - rowWidth k) / 2
    let x := x0 + (slot.getD i 0 : Nat) * (Layout.nodeW + Layout.hGap)
      + Layout.nodeW / 2
    let y := Layout.nodeH / 2 + (r : Nat) * Layout.levelStep
    (x, y)
  return { positions
           width := totalW
           height := Layout.nodeH + (h : Nat) * Layout.levelStep }

end HasseView
