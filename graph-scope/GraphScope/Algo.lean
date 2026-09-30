import GraphScope.Model

/-! # GraphScope: pure graph algorithms

All analysis shown by the widget is computed here, on a `GraphData`, in plain
executable code — no `Meta`, no `IO` — so every function is `#guard`-testable:

* degree sequence, min/max degree, isolated vertices;
* connected components (BFS; component ids numbered by first occurrence);
* a bipartiteness decision that returns *evidence* either way: a valid
  2-coloring, or an odd closed walk witness (`Bipartition`), together with the
  pure validators `isProperColoring` and `isValidOddCycle` used by the tests to
  check the evidence rather than trust it.
-/

namespace GraphScope

namespace GraphData

/-- Degrees of all vertices, in index order. -/
def degreeSequence (d : GraphData) : Array Nat :=
  (Array.range d.n).map d.degree

/-- Minimum degree (`none` for the empty graph). -/
def minDegree? (d : GraphData) : Option Nat :=
  (d.degreeSequence).foldl (init := none) fun acc x =>
    match acc with
    | none => some x
    | some m => some (Nat.min m x)

/-- Maximum degree (`none` for the empty graph). -/
def maxDegree? (d : GraphData) : Option Nat :=
  (d.degreeSequence).foldl (init := none) fun acc x =>
    match acc with
    | none => some x
    | some m => some (Nat.max m x)

/-- Vertices of degree `0`, ascending. -/
def isolatedVertices (d : GraphData) : Array Nat :=
  (Array.range d.n).filter fun i => d.degree i == 0

/-- Adjacency lists for all vertices (each list ascending, see
`GraphData.neighbors`). -/
def adjacencyLists (d : GraphData) : Array (Array Nat) := Id.run do
  let mut adj : Array (Array Nat) := Array.replicate d.n #[]
  for (a, b) in d.edges do
    adj := adj.set! a (adj[a]!.push b)
    adj := adj.set! b (adj[b]!.push a)
  return adj

/-- Component id of every vertex: BFS from each unvisited vertex in index order,
so ids are `0, 1, …` in order of each component's smallest vertex.  Deterministic
by construction. -/
def componentIds (d : GraphData) : Array Nat := Id.run do
  let adj := d.adjacencyLists
  let mut comp : Array (Option Nat) := Array.replicate d.n none
  let mut nextId := 0
  for s in [0:d.n] do
    if comp[s]!.isNone then
      comp := comp.set! s (some nextId)
      let mut queue := #[s]
      let mut head := 0
      while head < queue.size do
        let v := queue[head]!
        for w in adj[v]! do
          if comp[w]!.isNone then
            comp := comp.set! w (some nextId)
            queue := queue.push w
        head := head + 1
      nextId := nextId + 1
  return comp.map (·.getD 0)

/-- Number of connected components (`0` for the empty graph). -/
def componentCount (d : GraphData) : Nat :=
  d.componentIds.foldl (init := 0) fun acc c => Nat.max acc (c + 1)

/-- Is the graph connected?  Follows the Mathlib convention that the empty graph
is *not* connected (`SimpleGraph.Connected` requires `Nonempty`). -/
def isConnected (d : GraphData) : Bool :=
  d.n != 0 && d.componentCount == 1

/-- BFS distances from `s`: `dist[i] = some k` if vertex `i` is reachable from
`s` in `k` steps (shortest path), `none` for unreachable vertices (and every
entry `none` when `s` is out of range).  Deterministic: neighbors are visited
in ascending order. -/
def distancesFrom (d : GraphData) (s : Nat) : Array (Option Nat) := Id.run do
  if s >= d.n then
    return Array.replicate d.n none
  let adj := d.adjacencyLists
  let mut dist : Array (Option Nat) := Array.replicate d.n none
  dist := dist.set! s (some 0)
  let mut queue := #[s]
  let mut head := 0
  while head < queue.size do
    let v := queue[head]!
    let dv := dist[v]!.getD 0
    for w in adj[v]! do
      if dist[w]!.isNone then
        dist := dist.set! w (some (dv + 1))
        queue := queue.push w
    head := head + 1
  return dist

/-- Largest shortest-path distance between any two vertices of a common
component (`0` for empty and edgeless graphs).  For disconnected graphs this is
the maximum over the components. -/
def diameter (d : GraphData) : Nat := Id.run do
  let mut best := 0
  for s in [0:d.n] do
    for dv? in d.distancesFrom s do
      if let some dv := dv? then
        best := Nat.max best dv
  return best

/-- Evidence-carrying result of the bipartiteness test. -/
inductive Bipartition where
  /-- The graph is bipartite; `color[i]` is the side of vertex `i`
  (`false` = left part, `true` = right part). -/
  | parts (color : Array Bool)
  /-- The graph is not bipartite; `cycle` is an odd cycle: consecutive entries
  are adjacent, and so are the last and the first. -/
  | oddCycle (cycle : Array Nat)
  deriving Repr, BEq, Inhabited

/-- Is `color` a proper 2-coloring of `d` (endpoints of every edge differ)?
Requires one color per vertex. -/
def isProperColoring (d : GraphData) (color : Array Bool) : Bool :=
  color.size == d.n && d.edges.all fun (a, b) => color[a]! != color[b]!

/-- Is `cycle` a valid odd-cycle witness for non-bipartiteness of `d`?
Checks: odd length `≥ 3`, all vertices distinct and in range, consecutive
vertices adjacent, and the last vertex adjacent to the first. -/
def isValidOddCycle (d : GraphData) (cycle : Array Nat) : Bool :=
  cycle.size % 2 == 1 && cycle.size >= 3
    && cycle.all (· < d.n)
    && (List.range cycle.size).all (fun i =>
        (List.range i).all fun j => cycle[i]! != cycle[j]!)
    && (List.range (cycle.size - 1)).all (fun i => d.adjacent cycle[i]! cycle[i+1]!)
    && d.adjacent cycle[cycle.size - 1]! cycle[0]!

/-- Path `v, parent v, …` of `len` vertices up the BFS tree (includes `v`;
empty for `len = 0`). -/
private def ancestorPath (parent : Array Nat) (v : Nat) (len : Nat) : Array Nat :=
  Id.run do
    if len == 0 then
      return #[]
    let mut out := #[v]
    let mut cur := v
    for _ in [1:len] do
      cur := parent[cur]!
      out := out.push cur
    return out

/-- Given a BFS tree (`parent`) and a conflict edge `(u, v)` whose endpoints
received equal colors, assemble the odd cycle `u → … → lca → … → v` (closed by
the edge `v-u`).

`u` and `v` are necessarily at *equal* depth: in BFS every edge joins depths
differing by at most one, and equal colors mean equal depth parity — so the
difference is both `≤ 1` and even, hence zero. The endpoints can therefore
walk up in lockstep to their lowest common ancestor directly. -/
private def oddCycleFrom (parent : Array Nat) (u v : Nat) : Array Nat :=
  Id.run do
    let mut a := u
    let mut b := v
    let mut steps := 0
    while a != b do
      a := parent[a]!
      b := parent[b]!
      steps := steps + 1
    -- u-side path includes the lca; v-side path stops just below it.
    let pathU := ancestorPath parent u (steps + 1)
    let pathV := ancestorPath parent v steps
    return pathU ++ pathV.reverse

/-- Decide bipartiteness by BFS 2-coloring across all components.  Returns a
proper 2-coloring (`.parts`) or an odd-cycle witness (`.oddCycle`); the tests
validate both kinds of evidence with `isProperColoring` / `isValidOddCycle`. -/
def bipartition (d : GraphData) : Bipartition := Id.run do
  let adj := d.adjacencyLists
  let mut color : Array (Option Bool) := Array.replicate d.n none
  let mut parent : Array Nat := Array.replicate d.n 0
  for s in [0:d.n] do
    if color[s]!.isNone then
      color := color.set! s (some false)
      parent := parent.set! s s
      let mut queue := #[s]
      let mut head := 0
      while head < queue.size do
        let v := queue[head]!
        let cv := color[v]!.getD false
        for w in adj[v]! do
          match color[w]! with
          | none =>
            color := color.set! w (some !cv)
            parent := parent.set! w v
            queue := queue.push w
          | some cw =>
            if cw == cv then
              return .oddCycle (oddCycleFrom parent v w)
        head := head + 1
  return .parts (color.map (·.getD false))

/-- Is the graph bipartite?  (Boolean view of `bipartition`.) -/
def isBipartite (d : GraphData) : Bool :=
  match d.bipartition with
  | .parts _ => true
  | .oddCycle _ => false

/-! ## Overlay validation

The `#graph_scope` command accepts a walk (ordered vertex list) and a highlight
set (vertex list) as overlays; both are validated here, purely. -/

/-- First problem with `w` as a walk in `d`, or `none` if it is a valid walk:
every vertex in range and every consecutive pair adjacent.  A single vertex is a
valid (trivial) walk; the empty walk is rejected. -/
def walkError? (d : GraphData) (w : Array Nat) : Option String := Id.run do
  if w.isEmpty then
    return some "a walk needs at least one vertex"
  for v in w do
    if v >= d.n then
      return some s!"walk vertex {v} is out of range (the graph has {d.n} vertices)"
  for i in [0:w.size - 1] do
    let a := w[i]!
    let b := w[i+1]!
    if !d.adjacent a b then
      return some s!"walk step {i + 1}: vertices {a} and {b} are not adjacent"
  return none

/-- First problem with `hs` as a highlight set in `d`, or `none`:
every vertex must be in range. -/
def highlightError? (d : GraphData) (hs : Array Nat) : Option String := Id.run do
  for v in hs do
    if v >= d.n then
      return some s!"highlighted vertex {v} is out of range (the graph has {d.n} vertices)"
  return none

end GraphData

end GraphScope
