import IntervalInspector.Model

/-! # Interval Inspector: endpoint order graph

A pure, deterministic representation of what is *known* about the ordering of the
endpoint atoms.  Facts come from two sources (assembled by the caller):

* local-context hypotheses `a ≤ b`, `a < b`, `a = b` (and `≥`/`>`, swapped), and
* numeric literal comparison, added automatically by `OrderGraph.build` whenever both
  atoms carry a literal value.

The graph stores the *transitive closure* of the facts, so queries are O(1) lookups.
Contradictory inputs (a strict cycle) are detected and flagged: the graph then answers
"unknown" to every query rather than panicking or returning nonsense.
-/

namespace IntervalInspector

/-- An ordering relation between two atoms. -/
inductive OrderRel where
  | le | lt | eq
  deriving Repr, BEq, DecidableEq, Inhabited

/-- A single ordering fact between two atoms, keyed by their pretty-printed forms. -/
structure OrderFact where
  /-- Left-hand atom (pretty-printed form). -/
  lhs : String
  /-- Right-hand atom (pretty-printed form). -/
  rhs : String
  /-- The relation: `lhs ≤ rhs`, `lhs < rhs` or `lhs = rhs`. -/
  rel : OrderRel
  /-- Literal value of the left-hand atom, when it is a numeric literal.  Lets
  hypothesis atoms that are not shape endpoints (e.g. the `2` in `a ≤ 2`) join the
  automatic literal comparisons when they are added as auxiliary graph nodes. -/
  lhsVal? : Option Rat := none
  /-- Literal value of the right-hand atom, when it is a numeric literal. -/
  rhsVal? : Option Rat := none
  deriving Repr, BEq, Inhabited

/-- Atoms mentioned by a fact, as `(name, literal value?)` pairs. -/
def OrderFact.atomsWithVals (f : OrderFact) : Array (String × Option Rat) :=
  #[(f.lhs, f.lhsVal?), (f.rhs, f.rhsVal?)]

/-- Transitive closure of ordering knowledge over a fixed set of atoms.

`le[i][j] = true` means `atom i ≤ atom j` is known; likewise `lt`.  Known equality is
`le` in both directions.  If `inconsistent` is set the input facts contained a strict
cycle; all queries then report unknown. -/
structure OrderGraph where
  /-- The atoms, keyed by pretty-printed form (deduplicated, insertion order). -/
  atoms : Array String
  /-- Literal value of each atom, when it is a numeric literal. -/
  vals : Array (Option Rat)
  /-- `le[i][j]`: is `atoms[i] ≤ atoms[j]` known? Reflexive, transitively closed. -/
  le : Array (Array Bool)
  /-- `lt[i][j]`: is `atoms[i] < atoms[j]` known? Transitively closed with `le`. -/
  lt : Array (Array Bool)
  /-- Whether the input facts were contradictory (contained a strict cycle). -/
  inconsistent : Bool
  deriving Repr, Inhabited

namespace OrderGraph

/-- Build the order graph for `atoms` (name, optional literal value) from `facts`.
Facts mentioning atoms outside the list are ignored.  Literal comparisons between
atoms that both carry values are added automatically.  The result is transitively
closed and contradiction-checked. -/
def build (atoms : Array (String × Option Rat)) (facts : Array OrderFact) : OrderGraph :=
  Id.run do
    -- Deduplicate atoms by name, first occurrence wins.
    let mut names : Array String := #[]
    let mut vals : Array (Option Rat) := #[]
    for (n, v) in atoms do
      if !names.contains n then
        names := names.push n
        vals := vals.push v
    let n := names.size
    let idx? (s : String) : Option Nat := names.idxOf? s
    let mut le : Array (Array Bool) :=
      .ofFn fun (i : Fin n) => .ofFn fun (j : Fin n) => i == j
    let mut lt : Array (Array Bool) :=
      .replicate n (.replicate n false)
    let set2 (m : Array (Array Bool)) (i j : Nat) : Array (Array Bool) :=
      m.modify i (·.set! j true)
    -- Literal comparisons.
    for i in [0:n] do
      for j in [0:n] do
        if i != j then
          match vals[i]!, vals[j]! with
          | some vi, some vj =>
            if vi < vj then
              lt := set2 lt i j
              le := set2 le i j
            else if vi == vj then
              le := set2 le i j
              le := set2 le j i
          | _, _ => pure ()
    -- Hypothesis facts.
    for f in facts do
      match idx? f.lhs, idx? f.rhs with
      | some i, some j =>
        match f.rel with
        | .le => le := set2 le i j
        | .lt => lt := set2 lt i j; le := set2 le i j
        | .eq => le := set2 le i j; le := set2 le j i
      | _, _ => pure ()
    -- Transitive closure: n rounds of full propagation (n is small).
    for _ in [0:n] do
      for k in [0:n] do
        for i in [0:n] do
          for j in [0:n] do
            if le[i]![k]! && le[k]![j]! && !le[i]![j]! then
              le := set2 le i j
            if ((lt[i]![k]! && le[k]![j]!) || (le[i]![k]! && lt[k]![j]!)) && !lt[i]![j]! then
              lt := set2 lt i j
              le := set2 le i j
    let inconsistent := (List.range n).any fun i => lt[i]![i]!
    return { atoms := names, vals, le, lt, inconsistent }

/-- Index of atom `a` in the graph, if present. -/
def idx? (g : OrderGraph) (a : String) : Option Nat := g.atoms.idxOf? a

/-- Restrict the graph to the atoms in `keep` (in `keep` order; names not in the graph
are dropped).  The kept relations are those of the input graph — which is transitively
closed — so facts derived *through* dropped atoms (`a ≤ b ≤ c` with `b` dropped)
survive as direct edges.  The `inconsistent` flag is inherited: a contradiction
anywhere in the input facts taints every query. -/
def restrict (g : OrderGraph) (keep : Array String) : OrderGraph := Id.run do
  let idxs : Array Nat := keep.filterMap g.idx?
  let atoms := idxs.map (g.atoms[·]!)
  let vals := idxs.map (g.vals[·]!)
  let le := idxs.map fun i => idxs.map fun j => g.le[i]![j]!
  let lt := idxs.map fun i => idxs.map fun j => g.lt[i]![j]!
  return { atoms, vals, le, lt, inconsistent := g.inconsistent }

/-- Is `a ≤ b` known?  `false` if either atom is missing, the pair is unknown,
or the graph is inconsistent. -/
def knownLe (g : OrderGraph) (a b : String) : Bool :=
  if g.inconsistent then false
  else match g.idx? a, g.idx? b with
    | some i, some j => g.le[i]![j]!
    | _, _ => false

/-- Is `a < b` known?  `false` if unknown or the graph is inconsistent. -/
def knownLt (g : OrderGraph) (a b : String) : Bool :=
  if g.inconsistent then false
  else match g.idx? a, g.idx? b with
    | some i, some j => g.lt[i]![j]!
    | _, _ => false

/-- Is `a = b` known (i.e. `a ≤ b` and `b ≤ a`)? -/
def knownEq (g : OrderGraph) (a b : String) : Bool :=
  g.knownLe a b && g.knownLe b a

/-- Is the pair related at all (in either direction)? -/
def related (g : OrderGraph) (a b : String) : Bool :=
  g.knownLe a b || g.knownLe b a

/-- Is the ordering of the pair unknown? (Also `true` for missing atoms and
inconsistent graphs.) -/
def unknown (g : OrderGraph) (a b : String) : Bool := !g.related a b

/-- Literal value of atom `a`, if any. -/
def val? (g : OrderGraph) (a : String) : Option Rat :=
  match g.idx? a with
  | some i => g.vals[i]!
  | none => none

/-- Is every pair of atoms related?  `false` for inconsistent graphs. -/
def totallyOrdered (g : OrderGraph) : Bool :=
  !g.inconsistent &&
    (List.range g.atoms.size).all fun i =>
      (List.range g.atoms.size).all fun j =>
        g.le[i]![j]! || g.le[j]![i]!

/-- All unordered pairs `(a, b)` with `a` before `b` in atom order.
Empty when the graph is inconsistent (everything is suspect, reported separately). -/
def unknownPairs (g : OrderGraph) : Array (String × String) := Id.run do
  if g.inconsistent then return #[]
  let mut out := #[]
  for i in [0:g.atoms.size] do
    for j in [i+1:g.atoms.size] do
      if !(g.le[i]![j]! || g.le[j]![i]!) then
        out := out.push (g.atoms[i]!, g.atoms[j]!)
  return out

end OrderGraph
end IntervalInspector
