/-! # GraphScope: deterministic circular layout

Vertex `i` of an `n`-vertex graph is placed on a circle at angle `2πi/n`,
**starting at 12 o'clock and proceeding clockwise** (so vertex `0` is always at
the top).  `Float` is used only to compute the final pixel coordinates, which
are immediately rounded to `Nat`, so a `Layout` — and everything rendered from
it — is a byte-for-byte deterministic function of `n`.  Vertex ordering and all
graph analysis stay exact (`Nat`-indexed); no ordering decision depends on
floating point.
-/

namespace GraphScope

/-- Pixel positions of the vertices of an `n`-vertex graph (index-aligned). -/
structure Layout where
  /-- `positions[i]` is the `(x, y)` pixel center of vertex `i`. -/
  positions : Array (Nat × Nat)
  deriving Repr, BEq, Inhabited

namespace Layout

/-- Side length of the square SVG viewport, in px. -/
def viewSize : Nat := 360

/-- Center coordinate of the viewport (both axes), in px. -/
def center : Float := 180.0

/-- Radius of the vertex circle, in px. -/
def radius : Float := 140.0

/-- `2π`. -/
def twoPi : Float := 6.283185307179586

/-- Round a nonnegative pixel coordinate to `Nat` (negative rounding noise
saturates to `0` via `UInt32`). -/
def toPx (f : Float) : Nat :=
  f.round.toUInt32.toNat

/-- Circular layout of `n` vertices: vertex `i` at angle `2πi/n` measured
clockwise from 12 o'clock, i.e.
`(center + radius·sin θ, center - radius·cos θ)` rounded to whole pixels. -/
def circular (n : Nat) : Layout :=
  { positions := (Array.range n).map fun i =>
      let θ := twoPi * i.toFloat / n.toFloat
      (toPx (center + radius * θ.sin), toPx (center - radius * θ.cos)) }

/-- Position of vertex `i` (defaults to the viewport center if out of range). -/
def pos (l : Layout) (i : Nat) : Nat × Nat :=
  l.positions[i]?.getD (180, 180)

end Layout

end GraphScope
