import TreeScope.Render
import TreeScope.ToTreeView
import Batteries.Data.BinomialHeap.Basic

/-! # TreeScope instances: `Batteries.BinomialHeap`

`Batteries.BinomialHeap α le` is a subtype `{ h : Imp.Heap α // h.WF le 0 }`
over two **public** inductives (verified in
`Batteries/Data/BinomialHeap/Basic.lean`):

* `Imp.Heap`: `nil | cons (rank : Nat) (val : α) (node : HeapNode α) (next)`
  — the top-level forest, one binomial tree per `cons`;
* `Imp.HeapNode`: `nil | node (a : α) (child sibling : HeapNode α)` — `child`
  is a node's first child and `sibling` its next *sibling*, so a `HeapNode`
  encodes the sibling list of a node's children.

The semantic view renders the whole forest under one synthetic root labeled
`heap` (sublabel `n=size`, counted honestly via `realSize`); each binomial
tree's root carries its stored rank as the sublabel `rank=r`.  Invariants are
checked with the `le` **from the heap's type**:

* `heap` badge + `violation` tone on any child `c` of a parent `p` with
  `le p c = false` (the heap property, checked on every edge);
* `rank` badge on a top-level root whose stored rank differs from the
  structural rank of its `HeapNode` forest;
* `rank-order` badge on a top-level root whose stored rank is not strictly
  larger than its predecessor's.

The pure checkers (`heapOrdered`, `ranksValid`) are re-used by the tests on
crafted raw `Heap`/`HeapNode` values that could never carry a `WF` proof.
-/

namespace TreeScope.HeapView

open Batteries.BinomialHeap.Imp (Heap HeapNode)

universe u

variable {α : Type u}

/-! ## Pure invariant checkers (raw trees) -/

/-- Does every parent/child edge of the sibling-encoded forest satisfy `le`?
`parent?` is the value of the node whose child list this is. -/
def heapNodeLE (le : α → α → Bool) (parent? : Option α) : HeapNode α → Bool
  | .nil => true
  | .node a c s =>
    (parent?.all fun p => le p a) && heapNodeLE le (some a) c && heapNodeLE le parent? s

/-- Does every edge of the whole heap satisfy `le`? -/
def heapOrdered (le : α → α → Bool) : Heap α → Bool
  | .nil => true
  | .cons _ a n next => heapNodeLE le (some a) n && heapOrdered le next

/-- Are the stored top-level ranks consistent (each equals its forest's
structural rank) and strictly increasing, starting at ≥ `minRank`? -/
def ranksValidFrom (minRank : Nat) : Heap α → Bool
  | .nil => true
  | .cons r _ n next => r ≥ minRank && n.rank == r && ranksValidFrom (r + 1) next

/-- Are the stored top-level ranks consistent (each equals its forest's
structural rank) and strictly increasing? -/
def ranksValid : Heap α → Bool := ranksValidFrom 0

/-! ## The annotated view -/

/-- Views of the trees in a sibling-encoded child forest, each checked
against its parent value `parent?`. -/
def forestViews (rep : α → String) (le : α → α → Bool) (parent? : Option α) :
    HeapNode α → Array TreeView
  | .nil => #[]
  | .node a c s =>
    let bad := !(parent?.all fun p => le p a)
    let tv : TreeView :=
      .mk (rep a) none (if bad then #["heap"] else #[])
        (if bad then .violation else .neutral) false
        (forestViews rep le (some a) c)
    #[tv] ++ forestViews rep le parent? s

/-- Views of the top-level binomial trees: rank sublabels plus the `rank` /
`rank-order` root checks (see the module docstring). -/
def rootViews (rep : α → String) (le : α → α → Bool) (minRank : Nat) :
    Heap α → Array TreeView
  | .nil => #[]
  | .cons r a n next =>
    let badges : Array String :=
      (if n.rank != r then #["rank"] else #[])
      ++ (if r < minRank then #["rank-order"] else #[])
    let tv : TreeView :=
      .mk (rep a) (some s!"rank={r}") badges
        (if badges.isEmpty then .neutral else .violation) false
        (forestViews rep le (some a) n)
    #[tv] ++ rootViews rep le (r + 1) next

/-- The annotated forest view of a raw heap: synthetic `heap` root (sublabel
`n=realSize`), one child per binomial tree.  A **non-empty** heap whose forest
passed every check gets the `ok` tone on the synthetic root, so the generic
`Render.healthCaption?` captions it `invariants ok` exactly like a clean RB
tree; an empty heap stays neutral (nothing was checked — mirroring the RB
`(empty)` convention), and any violation leaves the root neutral (the guilty
nodes carry the violation tone themselves). -/
def heapView (rep : α → String) (le : α → α → Bool) (h : Heap α) : TreeView :=
  let kids := rootViews rep le 0 h
  let tone : NodeTone :=
    match h with
    | .nil => .neutral
    | .cons .. => if kids.any (·.hasTone .violation) then .neutral else .ok
  .mk "heap" (some s!"n={h.realSize}") #[] tone false kids

end HeapView

/-- `BinomialHeap` semantic view: the forest with rank sublabels, every edge
checked against the `le` **from the heap's type**. -/
instance {α : Type u} {le : α → α → Bool} [Repr α] :
    ToTreeView (Batteries.BinomialHeap α le) :=
  ⟨fun h => match h with
    | ⟨raw, _⟩ => HeapView.heapView reprStr le raw⟩

end TreeScope
