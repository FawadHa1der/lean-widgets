/-! # HasseView: the pure poset model

`PosetData` is the pure, fully-evaluated snapshot of a finite ordered type that
every downstream HasseView module (layout, rendering, the `#hasse` command)
operates on: an element count `n`, the full `≤` table over element *indices*
`0, …, n-1` (`le[i][j] = true` iff element `i ≤ element j` in the source
order), and one display label per element.

The elaboration layer (`HasseView.Extract`) is the only impure code in the
package; it produces a `PosetData` and everything after that is
`#guard`-testable.

## Conventions

* **Strict order**: `ltB i j := leB i j && !leB j i` (the strict part of the
  relation).  For a genuine partial order this agrees with `≤ ∧ ≠`; for a
  preorder that is not antisymmetric it quotients away 2-cycles, which keeps
  every derived notion (covers, ranks) well-behaved while the validity
  checkers report the violation honestly.
* **Covers** (`a ⋖ b`): `ltB a b` with no `c` strictly between — the edge set
  of the Hasse diagram and the mathematical heart of the package.
* **Rank**: the longest cover-path from a minimal element (DAG longest path,
  computed by bounded Bellman–Ford-style relaxation so even an invalid cyclic
  table terminates).
* **Height**: the number of cover steps in a longest chain (= the maximum
  rank; a chain with `k+1` elements has height `k`).
* **Antichain width**: `maxLayerSize` is only a LOWER bound on the width (the
  largest rank layer is an antichain in a valid poset); the exact width is a
  matching problem (Dilworth/König) and out of scope.

## Validity

The extracted table is *checked*, never trusted: `reflexivityViolations`,
`antisymmetryViolations` and `transitivityViolations` list concrete
counterexamples, and the renderer surfaces them as warnings — a preorder that
is not a partial order is reported, not silently drawn wrong.
-/

namespace HasseView

/-- A fully-evaluated finite ordered type on elements `0, …, n-1`:
the complete `≤` table plus display labels.  Built by `PosetData.ofTable`
(which normalizes shapes) or by extraction. -/
structure PosetData where
  /-- Number of elements. -/
  n : Nat
  /-- `le[i][j] = true` iff element `i ≤` element `j`.  Always `n` rows of
  `n` entries (normalized by `ofTable`). -/
  le : Array (Array Bool)
  /-- One display label per element (`labels.size = n`). -/
  labels : Array String
  deriving Repr, BEq, Inhabited

namespace PosetData

/-- Default labels: the element indices themselves, `#["0", "1", …]`. -/
def defaultLabels (n : Nat) : Array String :=
  (Array.range n).map toString

/-- Smart constructor: pad or truncate the table to exactly `n × n` (missing
entries default to `false`) and the labels to exactly `n` entries (missing
entries default to the index). -/
def ofTable (n : Nat) (le : Array (Array Bool)) (labels : Array String := #[]) :
    PosetData :=
  { n
    le := (Array.range n).map fun i =>
      let row := le[i]?.getD #[]
      (Array.range n).map fun j => row[j]?.getD false
    labels := (Array.range n).map fun i =>
      if h : i < labels.size then labels[i] else toString i }

/-- Shape invariants (`ofTable` guarantees them; re-checked on every
extraction): an `n × n` table and `n` labels. -/
def wellFormed (d : PosetData) : Bool :=
  d.le.size == d.n && d.le.all (·.size == d.n) && d.labels.size == d.n

/-- `i ≤ j`?  (`false` for out-of-range indices.) -/
def leB (d : PosetData) (i j : Nat) : Bool :=
  ((d.le[i]?).bind (·[j]?)).getD false

/-- `i < j` in the strict sense: `i ≤ j` but not `j ≤ i` (the strict part of
the relation — see the module docstring for why this spelling). -/
def ltB (d : PosetData) (i j : Nat) : Bool :=
  d.leB i j && !d.leB j i

/-- Display label of element `i` (falls back to the index if out of range). -/
def label (d : PosetData) (i : Nat) : String :=
  d.labels[i]?.getD (toString i)

/-! ## Validity: is the extracted table actually a partial order? -/

/-- Elements `i` with `¬ i ≤ i` (empty iff the table is reflexive). -/
def reflexivityViolations (d : PosetData) : Array Nat :=
  (Array.range d.n).filter fun i => !d.leB i i

/-- Pairs `i < j` (as indices) with `i ≤ j` and `j ≤ i` (empty iff the table
is antisymmetric — distinct mutually-related elements break it). -/
def antisymmetryViolations (d : PosetData) : Array (Nat × Nat) := Id.run do
  let mut out := #[]
  for i in [0:d.n] do
    for j in [i+1:d.n] do
      if d.leB i j && d.leB j i then
        out := out.push (i, j)
  return out

/-- Triples `(i, j, k)` with `i ≤ j`, `j ≤ k` but `¬ i ≤ k`, in lexicographic
order (empty iff the table is transitive). -/
def transitivityViolations (d : PosetData) : Array (Nat × Nat × Nat) := Id.run do
  let mut out := #[]
  for i in [0:d.n] do
    for j in [0:d.n] do
      if d.leB i j then
        for k in [0:d.n] do
          if d.leB j k && !d.leB i k then
            out := out.push (i, j, k)
  return out

/-- Is the table a genuine partial order (reflexive, antisymmetric,
transitive)?  When `false`, the violation arrays hold counterexamples and the
renderer shows warnings. -/
def isValidPoset (d : PosetData) : Bool :=
  d.reflexivityViolations.isEmpty
    && d.antisymmetryViolations.isEmpty
    && d.transitivityViolations.isEmpty

/-! ## Covers — the Hasse diagram edge set -/

/-- Does `a ⋖ b` (`a < b` with no element strictly between)?  This is the
covering relation whose graph *is* the Hasse diagram. -/
def coversB (d : PosetData) (a b : Nat) : Bool :=
  d.ltB a b && (Array.range d.n).all fun c => !(d.ltB a c && d.ltB c b)

/-- All cover pairs `(a, b)` with `a ⋖ b`, in lexicographic order. -/
def coverPairs (d : PosetData) : Array (Nat × Nat) := Id.run do
  let mut out := #[]
  for a in [0:d.n] do
    for b in [0:d.n] do
      if d.coversB a b then
        out := out.push (a, b)
  return out

/-- Number of cover edges. -/
def coverCount (d : PosetData) : Nat := d.coverPairs.size

/-! ## Extremal elements -/

/-- Is `i` minimal (no `j` strictly below it)? -/
def isMinimal (d : PosetData) (i : Nat) : Bool :=
  (Array.range d.n).all fun j => !d.ltB j i

/-- Is `i` maximal (no `j` strictly above it)? -/
def isMaximal (d : PosetData) (i : Nat) : Bool :=
  (Array.range d.n).all fun j => !d.ltB i j

/-- The minimal elements, ascending. -/
def minimals (d : PosetData) : Array Nat :=
  (Array.range d.n).filter d.isMinimal

/-- The maximal elements, ascending. -/
def maximals (d : PosetData) : Array Nat :=
  (Array.range d.n).filter d.isMaximal

/-- The bottom element: the unique `i` with `i ≤ j` for all `j`, if any.
(In a valid poset such an element is automatically unique; the uniqueness
check only matters for invalid tables, where we refuse to pick one.) -/
def bot? (d : PosetData) : Option Nat :=
  let bs := (Array.range d.n).filter fun i => (Array.range d.n).all (d.leB i ·)
  if bs.size == 1 then bs[0]? else none

/-- The top element: the unique `i` with `j ≤ i` for all `j`, if any. -/
def top? (d : PosetData) : Option Nat :=
  let ts := (Array.range d.n).filter fun i => (Array.range d.n).all (d.leB · i)
  if ts.size == 1 then ts[0]? else none

/-- The atoms: the covers of `⊥` (empty when there is no bottom). -/
def atoms (d : PosetData) : Array Nat :=
  match d.bot? with
  | some b => (Array.range d.n).filter (d.coversB b ·)
  | none => #[]

/-- The coatoms: the elements covered by `⊤` (empty when there is no top). -/
def coatoms (d : PosetData) : Array Nat :=
  match d.top? with
  | some t => (Array.range d.n).filter (d.coversB · t)
  | none => #[]

/-! ## Ranks and height -/

/-- `ranks[i]` is the length (in cover steps) of the longest cover-path from a
minimal element to `i` — the row of `i` in the layered drawing.  Computed by
`n` rounds of relaxation over the cover edges, so it terminates (with a
meaningless but finite answer) even on an invalid cyclic table. -/
def ranks (d : PosetData) : Array Nat := Id.run do
  let covers := d.coverPairs
  let mut r := Array.replicate d.n 0
  for _ in [0:d.n] do
    for (a, b) in covers do
      if r.getD b 0 < r.getD a 0 + 1 then
        r := r.set! b (r.getD a 0 + 1)
  return r

/-- The rank of element `i` (`0` out of range). -/
def rank (d : PosetData) (i : Nat) : Nat :=
  d.ranks[i]?.getD 0

/-- Height: the number of cover steps in a longest chain (= max rank; a
5-element chain has height 4; the empty and 1-element posets have height 0). -/
def height (d : PosetData) : Nat :=
  d.ranks.foldl max 0

/-- The elements of rank `r`, ascending — one row of the layered drawing.
In a valid poset every layer is an antichain (comparable elements always
differ in rank). -/
def layer (d : PosetData) (r : Nat) : Array Nat :=
  (Array.range d.n).filter fun i => d.rank i == r

/-- The size of the largest rank layer: a LOWER bound on the antichain width.
(The exact width is a matching problem — Dilworth — and out of scope; see the
README's limitations section.) -/
def maxLayerSize (d : PosetData) : Nat := Id.run do
  let mut best := 0
  for r in [0:d.height + 1] do
    best := max best (d.layer r).size
  return best

/-! ## Lattice analysis -/

/-- The common upper bounds of `i` and `j`, ascending. -/
def upperBounds (d : PosetData) (i j : Nat) : Array Nat :=
  (Array.range d.n).filter fun k => d.leB i k && d.leB j k

/-- The common lower bounds of `i` and `j`, ascending. -/
def lowerBounds (d : PosetData) (i j : Nat) : Array Nat :=
  (Array.range d.n).filter fun k => d.leB k i && d.leB k j

/-- The join (least upper bound) of `i` and `j`, if it exists: an upper bound
below every upper bound. -/
def joinOf? (d : PosetData) (i j : Nat) : Option Nat :=
  let ubs := d.upperBounds i j
  ubs.find? fun m => ubs.all (d.leB m ·)

/-- The meet (greatest lower bound) of `i` and `j`, if it exists. -/
def meetOf? (d : PosetData) (i j : Nat) : Option Nat :=
  let lbs := d.lowerBounds i j
  lbs.find? fun m => lbs.all (d.leB · m)

/-- Lattice verdict: every pair has a join and a meet, or a concrete witness
pair that fails. -/
inductive LatticeVerdict where
  /-- Every pair of elements has a join and a meet. -/
  | lattice
  /-- Elements `a` and `b` have no join (least upper bound). -/
  | noJoin (a b : Nat)
  /-- Elements `a` and `b` have no meet (greatest lower bound). -/
  | noMeet (a b : Nat)
  deriving Repr, BEq, Inhabited

/-- Scan all pairs `i < j` in lexicographic order (join checked before meet
for each pair) and return `.lattice`, or the FIRST failure with its concrete
witness pair.  The empty and 1-element posets are trivially lattices. -/
def latticeVerdict (d : PosetData) : LatticeVerdict := Id.run do
  for i in [0:d.n] do
    for j in [i+1:d.n] do
      if (d.joinOf? i j).isNone then
        return .noJoin i j
      if (d.meetOf? i j).isNone then
        return .noMeet i j
  return .lattice

/-- Is the poset a lattice (all pairwise joins and meets exist)? -/
def isLattice (d : PosetData) : Bool :=
  d.latticeVerdict == .lattice

/-! ## Upsets and downsets (overlay data) -/

/-- The upset (up-closure) `↑i = { j | i ≤ j }`, ascending; contains `i`
itself in a reflexive table. -/
def upset (d : PosetData) (i : Nat) : Array Nat :=
  (Array.range d.n).filter fun j => d.leB i j

/-- The downset (down-closure) `↓i = { j | j ≤ i }`, ascending; contains `i`
itself in a reflexive table. -/
def downset (d : PosetData) (i : Nat) : Array Nat :=
  (Array.range d.n).filter fun j => d.leB j i

/-! ## Overlay validation -/

/-- `none` if all highlight indices are in range; otherwise an error message
naming the first offender. -/
def highlightError? (d : PosetData) (hs : Array Nat) : Option String :=
  hs.findSome? fun i =>
    if i < d.n then none
    else some s!"highlighted element {i} is out of range (the poset has {d.n} elements)"

/-- `none` if the updown focus index is in range; otherwise an error message. -/
def updownError? (d : PosetData) (i : Nat) : Option String :=
  if i < d.n then none
  else some s!"updown element {i} is out of range (the poset has {d.n} elements)"

end PosetData

end HasseView
