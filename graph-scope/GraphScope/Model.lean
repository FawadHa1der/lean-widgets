/-! # GraphScope: the pure graph model

`GraphData` is the pure, fully-evaluated snapshot of a finite simple graph that every
downstream GraphScope module (algorithms, layout, rendering, the `#graph_scope`
command) operates on: a vertex count, a normalized edge list over vertex *indices*
`0, …, n-1`, and one display label per vertex.

The elaboration layer (`GraphScope.Extract`) is the only impure code in the package;
it produces a `GraphData` and everything after that is `#guard`-testable.

Normalization invariants (established by the smart constructor `GraphData.ofEdges`
and checked by `GraphData.wellFormed`):

* every edge `(i, j)` satisfies `i < j < n` (simple graphs are irreflexive, so
  self-loops are dropped; out-of-range endpoints are dropped);
* the edge array is sorted lexicographically and duplicate-free;
* `labels.size = n`.
-/

namespace GraphScope

/-- A fully-evaluated finite simple graph on vertices `0, …, n-1`. -/
structure GraphData where
  /-- Number of vertices. -/
  n : Nat
  /-- Undirected edges as index pairs, normalized to `i < j`, sorted
  lexicographically, without duplicates. -/
  edges : Array (Nat × Nat)
  /-- One display label per vertex (`labels.size = n`). -/
  labels : Array String
  deriving Repr, BEq, Inhabited

namespace GraphData

/-- Lexicographic strict order on edge pairs (used to sort the edge list). -/
def edgeLt (p q : Nat × Nat) : Bool :=
  p.1 < q.1 || (p.1 == q.1 && p.2 < q.2)

/-- Normalize a raw edge list for a graph on `n` vertices: drop self-loops
(simple graphs are irreflexive) and edges with an out-of-range endpoint, orient
every edge as `(min, max)`, sort lexicographically, and remove duplicates. -/
def normalizeEdges (n : Nat) (raw : Array (Nat × Nat)) : Array (Nat × Nat) :=
  let oriented := raw.filterMap fun (a, b) =>
    if a == b || a >= n || b >= n then none
    else if a < b then some (a, b) else some (b, a)
  let sorted := oriented.qsort edgeLt
  sorted.foldl (init := #[]) fun acc e =>
    if acc.back? == some e then acc else acc.push e

/-- Default labels: the vertex indices themselves, `#["0", "1", …]`. -/
def defaultLabels (n : Nat) : Array String :=
  (Array.range n).map toString

/-- Smart constructor: normalize the edge list (see `normalizeEdges`) and pad or
truncate `labels` to exactly `n` entries, filling missing entries with the vertex
index. -/
def ofEdges (n : Nat) (raw : Array (Nat × Nat)) (labels : Array String := #[]) :
    GraphData :=
  { n
    edges := normalizeEdges n raw
    labels := (Array.range n).map fun i =>
      if h : i < labels.size then labels[i] else toString i }

/-- Are all normalization invariants satisfied?  `ofEdges` guarantees this; it is
re-checked as a property test on every extracted graph. -/
def wellFormed (d : GraphData) : Bool :=
  d.labels.size == d.n
    && d.edges.all (fun (a, b) => a < b && b < d.n)
    && (d.edges.zip (d.edges.extract 1 d.edges.size)).all fun (p, q) => edgeLt p q

/-- Number of edges. -/
def edgeCount (d : GraphData) : Nat := d.edges.size

/-- Are vertices `i` and `j` adjacent?  (`false` for `i = j` and out-of-range
indices, by the normalization invariants.) -/
def adjacent (d : GraphData) (i j : Nat) : Bool :=
  d.edges.contains (if i < j then (i, j) else (j, i))

/-- Degree of vertex `i`: the number of edges incident to it. -/
def degree (d : GraphData) (i : Nat) : Nat :=
  d.edges.foldl (init := 0) fun acc (a, b) =>
    if a == i || b == i then acc + 1 else acc

/-- Display label of vertex `i` (falls back to the index if out of range). -/
def label (d : GraphData) (i : Nat) : String :=
  d.labels[i]?.getD (toString i)

/-- Neighbors of vertex `i`, in ascending order (a consequence of the sorted
edge list: partners below `i` are scanned before partners above `i`). -/
def neighbors (d : GraphData) (i : Nat) : Array Nat :=
  d.edges.foldl (init := #[]) fun acc (a, b) =>
    if a == i then acc.push b
    else if b == i then acc.push a
    else acc

end GraphData

end GraphScope
