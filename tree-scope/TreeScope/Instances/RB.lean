import TreeScope.Render
import TreeScope.ToTreeView
import Lean

/-! # TreeScope instances: `Lean.RBNode` / `Lean.RBMap`

The red–black teaching view.  Every node is toned by its `RBColor`
(`rbRed`/`rbBlack`), labeled `key:value` (the value `Repr`-printed and
abbreviated to 12 characters), and sublabeled with its black-height `bh=k`.
Three invariants are checked *while the view is built*, and a broken one turns
the guilty node's tone to `violation` with a badge naming the invariant:

* `red-red` — a red node whose parent is red (badge on the guilty **child**);
* `bh` — the node's two subtrees disagree on black-height (badge on the
  lowest node where they disagree);
* `ord` — the key falls outside the BST bounds implied by its ancestors,
  w.r.t. a comparator.  For `Lean.RBMap α β cmp` the comparator **comes from
  the type**; for a raw `Lean.RBNode` no comparator is known, so the plain
  `RBNode` instance skips the order check (use `rbNodeView … (some cmp)`
  directly to order-check a raw node).

Black-height convention: `bh leaf = 0`, a black node adds 1; a node's
annotated `bh` uses the *max* of its subtrees (only meaningful when they
agree — disagreement is exactly the `bh` violation).

`Lean.RBNode.leaf` children are elided (an interior node shows only its
non-leaf children); the left/right position of a single shown child is
recoverable from the keys.  An entirely empty tree renders as the single
neutral node `(empty)`.

The combined health summary (`rbHealth`, also the panel caption and the last
text-mode line) is derived from the annotated view by the generic
`Render.healthCaption?`: `invariants ok`, or `⚠ path (badges), …`.

All functions here are pure and total; the pure checkers
(`hasRedRed`/`bhConsistent`/`ordered`) are re-used by the adversarial tests
against crafted raw trees.
-/

namespace TreeScope.RB

open Lean (RBNode RBColor)

universe u v

variable {α : Type u} {β : Type v} {γ : α → Type v}

/-- Maximum printed length of a value before abbreviation. -/
def abbrevLen : Nat := 12

/-- Truncate `s` to `abbrevLen` characters, appending `…` when it was longer.
A quote-delimited `s` (a `Repr`-printed string value) is re-closed before the
ellipsis (`"abcdefghi"…`), so abbreviation never cuts the syntax mid-quote. -/
def abbreviate (s : String) : String :=
  if s.length ≤ abbrevLen then s
  else if s.front == '"' && s.back == '"' then
    ((s.take (abbrevLen - 2)).toString.push '"').push '…'
  else (s.take (abbrevLen - 1)).toString.push '…'

/-- Is this color red? (`RBColor` has no `DecidableEq` in core.) -/
def colorIsRed : RBColor → Bool
  | .red => true
  | .black => false

/-! ## Pure invariant checkers (raw trees, dependent-`β` generic) -/

/-- Black-height: `0` at a leaf, `+1` per black node, taking the *max* over
subtrees (subtree disagreement is reported by `bhConsistent`, not here). -/
def blackHeight : RBNode α γ → Nat
  | .leaf => 0
  | .node c l _ _ r =>
    max (blackHeight l) (blackHeight r) + (if colorIsRed c then 0 else 1)

/-- Does the tree contain a red node with a red child? -/
def hasRedRed : RBNode α γ → Bool
  | .leaf => false
  | .node c l _ _ r =>
    (colorIsRed c && (l.isRed || r.isRed)) || hasRedRed l || hasRedRed r

/-- Do both subtrees of every node agree on black-height? -/
def bhConsistent : RBNode α γ → Bool
  | .leaf => true
  | .node _ l _ _ r =>
    blackHeight l == blackHeight r && bhConsistent l && bhConsistent r

/-- Is every key inside the open interval `(lo, hi)` w.r.t. `cmp`, recursively
(the BST property)? -/
def orderedWithin (cmp : α → α → Ordering) : RBNode α γ → Option α → Option α → Bool
  | .leaf, _, _ => true
  | .node _ l k _ r, lo, hi =>
    (lo.all fun a => cmp a k == .lt) && (hi.all fun b => cmp k b == .lt)
      && orderedWithin cmp l lo (some k) && orderedWithin cmp r (some k) hi

/-- Is the tree a binary search tree w.r.t. `cmp`? -/
def ordered (cmp : α → α → Ordering) (t : RBNode α γ) : Bool :=
  orderedWithin cmp t none none

/-! ## The annotated view -/

/-- Node label: `key:value`, the value abbreviated. -/
def nodeLabel (repK : α → String) (repV : β → String) (k : α) (v : β) : String :=
  s!"{repK k}:{abbreviate (repV v)}"

/-- The annotated view of one *non-leaf* subtree: `parentRed` and the open
key interval `(lo, hi)` come from the ancestors (see the module docstring for
the exact toning/badging rules).  The `.leaf` case is unreachable (children
are elided before recursing) and yields a plain stub. -/
def viewGo (repK : α → String) (repV : β → String)
    (cmp? : Option (α → α → Ordering)) :
    RBNode α (fun _ => β) → Bool → Option α → Option α → TreeView
  | .leaf, _, _, _ => .leaf "∅"
  | .node c l k v r, parentRed, lo, hi =>
    let isRed := colorIsRed c
    let bh := max (blackHeight l) (blackHeight r) + (if isRed then 0 else 1)
    let badges : Array String :=
      (if parentRed && isRed then #["red-red"] else #[])
      ++ (if blackHeight l != blackHeight r then #["bh"] else #[])
      ++ (match cmp? with
          | some cmp =>
            if (lo.all fun a => cmp a k == .lt) && (hi.all fun b => cmp k b == .lt)
            then #[] else #["ord"]
          | none => #[])
    let tone := if badges.isEmpty then (if isRed then NodeTone.rbRed else .rbBlack)
                else .violation
    let kids : Array TreeView :=
      (match l with
        | .leaf => #[]
        | l@(.node ..) => #[viewGo repK repV cmp? l isRed lo (some k)])
      ++ (match r with
        | .leaf => #[]
        | r@(.node ..) => #[viewGo repK repV cmp? r isRed (some k) hi])
    .mk (nodeLabel repK repV k v) (some s!"bh={bh}") badges tone false kids

/-- The annotated red–black view of a raw (non-dependent) `RBNode`: pass
`some cmp` to enable the BST order check (an `RBMap`'s own comparator, say),
`none` to skip it.  An empty tree is the single neutral node `(empty)`. -/
def rbNodeView (repK : α → String) (repV : β → String)
    (cmp? : Option (α → α → Ordering)) (t : RBNode α (fun _ => β)) : TreeView :=
  match t with
  | .leaf => .leaf "(empty)"
  | t@(.node ..) => viewGo repK repV cmp? t false none none

/-- The combined health summary of a raw tree — exactly the panel caption of
its annotated view: `"invariants ok"` or `"⚠ path (badges), …"`. -/
def rbHealth (repK : α → String) (repV : β → String)
    (cmp? : Option (α → α → Ordering)) (t : RBNode α (fun _ => β)) : String :=
  (Render.healthCaption? (rbNodeView repK repV cmp? t)).getD "invariants ok"

/-- Number of `violation`-toned nodes in a view (0 on healthy trees; used by
the library-produced-maps-are-healthy property tests). -/
def violationCount (t : TreeView) : Nat :=
  (Render.violationEntries t).size

end RB

open Lean in
/-- Raw `RBNode` semantic view: colors and black-heights, red-red and bh
checks — but no order check, since a raw node's type carries no comparator. -/
instance {α : Type u} {β : Type v} [Repr α] [Repr β] :
    ToTreeView (RBNode α (fun _ => β)) :=
  ⟨RB.rbNodeView reprStr reprStr none⟩

open Lean in
/-- `RBMap` semantic view: the full red–black check, including the BST order
check with the comparator **from the map's type**. -/
instance {α : Type u} {β : Type v} {cmp : α → α → Ordering} [Repr α] [Repr β] :
    ToTreeView (RBMap α β cmp) :=
  ⟨fun m => match m with
    | ⟨t, _⟩ => RB.rbNodeView reprStr reprStr (some cmp) t⟩

end TreeScope
