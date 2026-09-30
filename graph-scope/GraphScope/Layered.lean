import GraphScope.Algo
import GraphScope.Layout

/-! # GraphScope: deterministic BFS-layered layout

An alternative to the circular layout aimed at trees and forests, where the
circle turns parent–child structure into hard-to-read chords.

`Layout.layered` runs a BFS per component (components in id order, i.e. by
smallest vertex; the root of each component is its smallest vertex) and places

* layer `d` (BFS depth `d`) on a horizontal row `y = yStart + d · rowGap`;
* components side by side, each in a horizontal band as many slots wide as its
  widest layer; within a layer, vertices sit at evenly spaced slot centers in
  BFS discovery order (children of earlier parents first).

All arithmetic is on `Nat` (no floating point at all), so the layout is
byte-for-byte deterministic.  The row gap and slot widths adapt to the
`360 × 360` viewport: `rowGap = min 70 (280 / maxDepth)` and the horizontal
band `[40, 320]` is split evenly among the components' slots.

`LayoutMode` selects between the two layouts; `.auto` (the default of
`renderPanel`) picks `layered` exactly when the graph is a forest
(`GraphData.isForest`: `|E| + #components = n`) and `circular` otherwise.
-/

namespace GraphScope

/-- Is the graph a forest (i.e. acyclic)?  Characterization:
`edgeCount + componentCount = n`. -/
def GraphData.isForest (d : GraphData) : Bool :=
  d.edgeCount + d.componentCount == d.n

namespace Layout

/-- BFS layers of every component, components in id order (= order of smallest
vertex), each component's layer `d` listing its depth-`d` vertices in BFS
discovery order.  The BFS root of a component is its smallest vertex, and
neighbors are scanned in ascending order (`GraphData.adjacencyLists`), so the
result is deterministic. -/
def bfsLayers (d : GraphData) : Array (Array (Array Nat)) := Id.run do
  let adj := d.adjacencyLists
  let mut depth : Array (Option Nat) := Array.replicate d.n none
  let mut comps : Array (Array (Array Nat)) := #[]
  for s in [0:d.n] do
    if depth[s]!.isNone then
      depth := depth.set! s (some 0)
      let mut layers : Array (Array Nat) := #[#[s]]
      let mut queue := #[s]
      let mut head := 0
      while head < queue.size do
        let v := queue[head]!
        let dv := (depth[v]!).getD 0
        for w in adj[v]! do
          if depth[w]!.isNone then
            depth := depth.set! w (some (dv + 1))
            if layers.size == dv + 1 then
              layers := layers.push #[]
            layers := layers.set! (dv + 1) (layers[dv + 1]!.push w)
            queue := queue.push w
        head := head + 1
      comps := comps.push layers
  return comps

/-- Deterministic BFS-layered layout (see the module docstring for the exact
geometry).  Works for any graph — non-tree edges simply become chords between
rows — but is chosen automatically only for forests. -/
def layered (d : GraphData) : Layout := Id.run do
  if d.n == 0 then
    return ⟨#[]⟩
  let comps := bfsLayers d
  let widthSlots := comps.map fun layers =>
    layers.foldl (init := 1) fun w l => Nat.max w l.size
  let maxDepth := comps.foldl (init := 0) fun m layers => Nat.max m (layers.size - 1)
  let rowGap := if maxDepth == 0 then 0 else Nat.min 70 (280 / maxDepth)
  let yStart := Nat.max 40 (180 - (maxDepth * rowGap) / 2)
  let totalSlots := widthSlots.foldl (· + ·) 0
  let slotW := Nat.max 1 (280 / totalSlots)
  let mut pos : Array (Nat × Nat) := Array.replicate d.n (180, 180)
  let mut xOff := 40
  for c in [0:comps.size] do
    let layers := comps[c]!
    let width := widthSlots[c]! * slotW
    for dep in [0:layers.size] do
      let layer := layers[dep]!
      for t in [0:layer.size] do
        let x := xOff + ((2 * t + 1) * width) / (2 * layer.size)
        let y := yStart + dep * rowGap
        pos := pos.set! layer[t]! (x, y)
    xOff := xOff + width
  return ⟨pos⟩

end Layout

/-- Which layout `renderPanel` uses. -/
inductive LayoutMode where
  /-- Layered for forests (`GraphData.isForest`), circular otherwise. -/
  | auto
  /-- Always the circular layout. -/
  | circle
  /-- Always the BFS-layered layout (non-tree edges become chords). -/
  | layered
  deriving Repr, BEq, Inhabited

/-- Resolve a `LayoutMode` to a concrete `Layout` for the given graph. -/
def LayoutMode.resolve (d : GraphData) : LayoutMode → Layout
  | .circle => .circular d.n
  | .layered => .layered d
  | .auto => if d.isForest then .layered d else .circular d.n

end GraphScope
