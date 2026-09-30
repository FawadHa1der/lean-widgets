import IntervalInspector.OrderGraph

/-! # Interval Inspector: number-line layout

Assigns a deterministic x-coordinate in `[0, 1]` (as a `Rat`, so tests can compare
exactly) to every endpoint atom:

* If **every** atom is a numeric literal, positions are proportional to the values.
* Otherwise atoms are placed by *rank* in the order graph (length of the longest known
  chain strictly below the atom), evenly spaced.  Atoms whose order relative to some
  other atom is unknown share rank slots and are flagged `unordered` so the renderer
  can display them as parallel/unordered rather than guessing.

Same input always yields the same output: the algorithm is a pure function of the
graph, with no hashing or nondeterministic iteration.
-/

namespace IntervalInspector

/-- A positioned atom on the number line. -/
structure LayoutAtom where
  /-- Atom name (pretty-printed endpoint). -/
  name : String
  /-- Literal value, when the atom is a numeric literal. -/
  val? : Option Rat
  /-- Position in `[0, 1]`. -/
  x : Rat
  /-- `true` if this atom's order relative to some other atom is unknown
  (or the graph is inconsistent). -/
  unordered : Bool
  deriving Repr, BEq, Inhabited

/-- The computed number-line layout. -/
structure Layout where
  /-- Positioned atoms, in the graph's atom order. -/
  atoms : Array LayoutAtom
  /-- Were positions computed proportionally from literal values? -/
  proportional : Bool
  /-- Is the endpoint order fully determined (and consistent)? -/
  totallyOrdered : Bool
  /-- Was the order graph contradictory? -/
  inconsistent : Bool
  deriving Repr, BEq, Inhabited

namespace Layout

/-- Position of atom `name`, if present. -/
def x? (l : Layout) (name : String) : Option Rat :=
  (l.atoms.find? (·.name == name)).map (·.x)

/-- Is atom `name` flagged as unordered? (`false` when absent.) -/
def isUnordered (l : Layout) (name : String) : Bool :=
  ((l.atoms.find? (·.name == name)).map (·.unordered)).getD false

end Layout

/-- Compute the layout for the atoms of an order graph.  Deterministic. -/
def computeLayout (g : OrderGraph) : Layout := Id.run do
  let n := g.atoms.size
  if n == 0 then
    return { atoms := #[], proportional := false,
             totallyOrdered := !g.inconsistent, inconsistent := g.inconsistent }
  let allLits := g.vals.all (·.isSome)
  let unorderedFlag (i : Nat) : Bool :=
    g.inconsistent ||
      (List.range n).any fun j => j != i && !(g.le[i]![j]! || g.le[j]![i]!)
  if allLits then
    -- Proportional placement from literal values (literals are always comparable,
    -- so nothing is unordered).
    let vs := g.vals.map (·.getD 0)
    let vmin := vs.foldl (fun a b => if b < a then b else a) vs[0]!
    let vmax := vs.foldl (fun a b => if a < b then b else a) vs[0]!
    let span := vmax - vmin
    let atoms := Array.ofFn fun (i : Fin n) =>
      { name := g.atoms[i]!, val? := g.vals[i]!
        x := if span == 0 then (1 : Rat)/2 else (vs[i]! - vmin) / span
        unordered := false : LayoutAtom }
    return { atoms, proportional := true, totallyOrdered := !g.inconsistent,
             inconsistent := g.inconsistent }
  else
    -- Rank placement: longest known chain strictly below each atom.
    -- `strictlyBelow j i`: j is known ≤ i but not conversely (covers < and non-eq ≤).
    let strictlyBelow (j i : Nat) : Bool := g.le[j]![i]! && !g.le[i]![j]!
    let mut rank : Array Nat := .replicate n 0
    if !g.inconsistent then
      for _ in [0:n] do
        for i in [0:n] do
          for j in [0:n] do
            if strictlyBelow j i && rank[j]! + 1 > rank[i]! then
              rank := rank.set! i (rank[j]! + 1)
    let maxRank := rank.foldl Nat.max 0
    let atoms := Array.ofFn fun (i : Fin n) =>
      { name := g.atoms[i]!, val? := g.vals[i]!
        x := if maxRank == 0 then (1 : Rat)/2
             else (rank[i]! : Rat) / (maxRank : Rat)
        unordered := unorderedFlag i : LayoutAtom }
    return { atoms, proportional := false, totallyOrdered := g.totallyOrdered,
             inconsistent := g.inconsistent }

end IntervalInspector
