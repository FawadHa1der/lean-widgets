import Mathlib.Data.Rat.Defs

/-! # Interval Inspector: pure data model

This module defines the *pure* (no `Expr`, no monads) model produced by recognition
(`IntervalInspector/Recognize.lean`) and consumed by the order graph, layout, rendering
and suggestion engines.  Keeping the model pure makes every downstream stage
deterministically testable with `#guard`.
-/

namespace IntervalInspector

/-- Which interval-like set constructor a recognized leaf is.

The eight `Set.Ixx` kinds follow Mathlib naming (`i` = infinite, `o` = open, `c` = closed);
`univ`, `empty` and `singleton` cover `Set.univ`, `∅` and `{a}`. -/
inductive IntervalKind where
  | Icc | Ico | Ioc | Ioo | Ici | Iic | Ioi | Iio
  | univ | empty | singleton
  deriving Repr, BEq, DecidableEq, Inhabited, Hashable

namespace IntervalKind

/-- Display name of the kind, matching the Mathlib constant's last component. -/
def name : IntervalKind → String
  | .Icc => "Icc" | .Ico => "Ico" | .Ioc => "Ioc" | .Ioo => "Ioo"
  | .Ici => "Ici" | .Iic => "Iic" | .Ioi => "Ioi" | .Iio => "Iio"
  | .univ => "univ" | .empty => "empty" | .singleton => "singleton"

/-- Does the kind have a (finite) left endpoint? -/
def boundedLeft : IntervalKind → Bool
  | .Icc | .Ico | .Ioc | .Ioo | .Ici | .Ioi | .singleton => true
  | .Iic | .Iio | .univ | .empty => false

/-- Does the kind have a (finite) right endpoint? -/
def boundedRight : IntervalKind → Bool
  | .Icc | .Ico | .Ioc | .Ioo | .Iic | .Iio | .singleton => true
  | .Ici | .Ioi | .univ | .empty => false

/-- Is the left endpoint included (when it exists)?  Convention: closed = included. -/
def closedLeft : IntervalKind → Bool
  | .Icc | .Ico | .Ici | .singleton => true
  | _ => false

/-- Is the right endpoint included (when it exists)?  Convention: closed = included. -/
def closedRight : IntervalKind → Bool
  | .Icc | .Ioc | .Iic | .singleton => true
  | _ => false

/-- Kinds that take two endpoint arguments (`Set.Ixx a b`). -/
def isDoubleEnded : IntervalKind → Bool
  | .Icc | .Ico | .Ioc | .Ioo => true
  | _ => false

end IntervalKind

/-- A typeclass prerequisite (beyond the ambient `Preorder`) that a suggested lemma
or caption may require of the endpoint type. -/
inductive InstanceNeed where
  | partialOrder | linearOrder | lattice | denselyOrdered | noMinOrder | noMaxOrder
  deriving Repr, BEq, DecidableEq, Inhabited

/-- Display name of the required class, e.g. `"DenselyOrdered"`. -/
def InstanceNeed.name : InstanceNeed → String
  | .partialOrder => "PartialOrder"
  | .linearOrder => "LinearOrder"
  | .lattice => "Lattice"
  | .denselyOrdered => "DenselyOrdered"
  | .noMinOrder => "NoMinOrder"
  | .noMaxOrder => "NoMaxOrder"

/-- Which instances are actually available for the recognized element type.  Computed
with `Meta.synthInstance?` during analysis; the default (`.all`, everything available)
is what the pure tests use and what pre-instance-checking behavior corresponded to. -/
structure InstAvail where
  /-- Is `PartialOrder α` available? -/
  partialOrder : Bool := true
  /-- Is `LinearOrder α` available? -/
  linearOrder : Bool := true
  /-- Is `Lattice α` available? -/
  lattice : Bool := true
  /-- Is `DenselyOrdered α` available? -/
  denselyOrdered : Bool := true
  /-- Is `NoMinOrder α` available? -/
  noMinOrder : Bool := true
  /-- Is `NoMaxOrder α` available? -/
  noMaxOrder : Bool := true
  deriving Repr, BEq, Inhabited

/-- Everything available (identity element for gating; the pure-test default). -/
def InstAvail.all : InstAvail := {}

/-- Is the given need satisfied? -/
def InstAvail.has (i : InstAvail) : InstanceNeed → Bool
  | .partialOrder => i.partialOrder
  | .linearOrder => i.linearOrder
  | .lattice => i.lattice
  | .denselyOrdered => i.denselyOrdered
  | .noMinOrder => i.noMinOrder
  | .noMaxOrder => i.noMaxOrder

/-- A recognized endpoint: its pretty-printed form and, when it is a numeric literal
in normal form (natural / integer / rational), its value. -/
structure Endpoint where
  /-- Pretty-printed form of the endpoint expression, e.g. `"a"` or `"2"`.  Recognition
  keys atoms by expression identity and disambiguates colliding display strings with
  `′` marks (`"a"`, `"a′"`), so within one recognized statement `pp` is a unique key. -/
  pp : String
  /-- Rational value when the endpoint is a numeric literal in normal form. -/
  val? : Option Rat := none
  deriving Repr, BEq, Inhabited

/-- A single recognized interval set.  `lo?`/`hi?` are `none` exactly when the kind is
unbounded on that side (`univ`, `empty`, and the corresponding side of `Ici`/`Iic`/etc.).
For `singleton a` both `lo?` and `hi?` are `some a`. -/
structure Leaf where
  /-- The interval constructor this leaf was recognized as. -/
  kind : IntervalKind
  /-- Left endpoint, when the kind is bounded below. -/
  lo? : Option Endpoint := none
  /-- Right endpoint, when the kind is bounded above. -/
  hi? : Option Endpoint := none
  /-- Provenance: `true` when the leaf was recognized from set-builder notation
  (e.g. `{x | a ≤ x ∧ x < b}` ↦ `Ico a b`) rather than a `Set.Ixx` application.
  The renderer badges such leaves "from set-builder". -/
  fromSetBuilder : Bool := false
  deriving Repr, BEq, Inhabited

namespace Leaf

/-- Human-readable description, e.g. `"Ioc a b"`, `"Ici a"`, `"univ"`, `"∅"`, `"{a}"`. -/
def desc (l : Leaf) : String :=
  match l.kind with
  | .univ => "univ"
  | .empty => "∅"
  | .singleton => s!"\{{(l.lo?.map (·.pp)).getD "?"}}"
  | k =>
    let lo := (l.lo?.map (·.pp)).getD ""
    let hi := (l.hi?.map (·.pp)).getD ""
    if k.isDoubleEnded then s!"{k.name} {lo} {hi}"
    else if k.boundedLeft then s!"{k.name} {lo}"
    else s!"{k.name} {hi}"

/-- Deterministic one-line ASCII picture of the leaf, e.g. `Ioc a b ↦ "(a───b]"`.
Convention: `[`/`]` = closed (endpoint included), `(`/`)` = open (excluded),
`-∞`/`∞` for unbounded sides. -/
def ascii (l : Leaf) : String :=
  match l.kind with
  | .empty => "∅"
  | .singleton => s!"\{{(l.lo?.map (·.pp)).getD "?"}}"
  | k =>
    let lo := if k.boundedLeft then (l.lo?.map (·.pp)).getD "?" else "-∞"
    let hi := if k.boundedRight then (l.hi?.map (·.pp)).getD "?" else "∞"
    let lbr := if k.boundedLeft then (if k.closedLeft then "[" else "(") else "("
    let rbr := if k.boundedRight then (if k.closedRight then "]" else ")") else ")"
    s!"{lbr}{lo}───{hi}{rbr}"

/-- Endpoints of the leaf, left before right. -/
def endpoints (l : Leaf) : Array Endpoint :=
  match l.kind, l.lo?, l.hi? with
  | .singleton, some a, _ => #[a]
  | _, some a, some b => #[a, b]
  | _, some a, none => #[a]
  | _, none, some b => #[b]
  | _, none, none => #[]

end Leaf

/-- An interval *expression*: a leaf, or a union / intersection of interval expressions. -/
inductive Tree where
  /-- A single recognized interval set. -/
  | leaf (l : Leaf)
  /-- Union `s ∪ t` of two interval expressions. -/
  | union (a b : Tree)
  /-- Intersection `s ∩ t` of two interval expressions. -/
  | inter (a b : Tree)
  deriving Repr, BEq, Inhabited

namespace Tree

/-- All leaves of the tree, left to right. -/
partial def leaves : Tree → Array Leaf
  | .leaf l => #[l]
  | .union a b | .inter a b => a.leaves ++ b.leaves

/-- Human-readable description, e.g. `"Ioc a b ∪ Ioc b c"`. Nested composites are
parenthesized. -/
partial def desc : Tree → String
  | .leaf l => l.desc
  | .union a b => s!"{descP a} ∪ {descP b}"
  | .inter a b => s!"{descP a} ∩ {descP b}"
where
  /-- Parenthesize non-leaf children. -/
  descP : Tree → String
    | .leaf l => l.desc
    | t => s!"({desc t})"

/-- Deterministic ASCII picture, leaves joined by the set operation. -/
partial def ascii : Tree → String
  | .leaf l => l.ascii
  | .union a b => s!"{ascii a} ∪ {ascii b}"
  | .inter a b => s!"{ascii a} ∩ {ascii b}"

/-- All endpoints appearing in the tree, in traversal order, deduplicated by
pretty-printed form. -/
def endpoints (t : Tree) : Array Endpoint := Id.run do
  let mut out : Array Endpoint := #[]
  for l in t.leaves do
    for e in l.endpoints do
      if !out.any (·.pp == e.pp) then
        out := out.push e
  return out

/-- Compact machine-oriented description used by tests, e.g.
`"union(Ioc(a,b),Ioc(b,c))"`.  Leaves recognized from set-builder notation carry a
`*` suffix on the kind name, e.g. `"Ico*(a,b)"`, so tests can pin provenance. -/
partial def debugString : Tree → String
  | .leaf l =>
    match l.kind with
    | .univ => "univ"
    | .empty => "empty"
    | .singleton => s!"sing({(l.lo?.map (·.pp)).getD "?"})"
    | k =>
      let nm := if l.fromSetBuilder then s!"{k.name}*" else k.name
      if k.isDoubleEnded then
        s!"{nm}({(l.lo?.map (·.pp)).getD "?"},{(l.hi?.map (·.pp)).getD "?"})"
      else if k.boundedLeft then s!"{nm}({(l.lo?.map (·.pp)).getD "?"})"
      else s!"{nm}({(l.hi?.map (·.pp)).getD "?"})"
  | .union a b => s!"union({debugString a},{debugString b})"
  | .inter a b => s!"inter({debugString a},{debugString b})"

/-- Does any leaf of the tree come from set-builder notation? -/
def anyFromSetBuilder (t : Tree) : Bool := t.leaves.any (·.fromSetBuilder)

end Tree

/-- The recognized statement shape: a goal or hypothesis about interval expressions. -/
inductive Shape where
  /-- Membership `x ∈ s`. -/
  | mem (x : Endpoint) (s : Tree)
  /-- Inclusion `s ⊆ t`. -/
  | subset (lhs rhs : Tree)
  /-- Strict inclusion `s ⊂ t`. -/
  | ssubset (lhs rhs : Tree)
  /-- Set equality `s = t`. -/
  | eq (lhs rhs : Tree)
  /-- Nonemptiness `Set.Nonempty s`. -/
  | nonempty (s : Tree)
  /-- Non-emptiness as a disequality: `s ≠ ∅` (also `¬(s = ∅)`); `rev := true` for the
  mirror spellings `∅ ≠ s` / `¬(∅ = s)` (suggestions then get a `.symm` wrapper). -/
  | neEmpty (s : Tree) (rev : Bool := false)
  /-- A bare interval expression (not a proposition). -/
  | term (s : Tree)
  deriving Repr, BEq, Inhabited

namespace Shape

/-- Human-readable description of the shape, e.g. `"Ioc a b ∪ Ioc b c = Ioc a c"`. -/
def desc : Shape → String
  | .mem x s => s!"{x.pp} ∈ {s.desc}"
  | .subset l r => s!"{l.desc} ⊆ {r.desc}"
  | .ssubset l r => s!"{l.desc} ⊂ {r.desc}"
  | .eq l r => s!"{l.desc} = {r.desc}"
  | .nonempty s => s!"({s.desc}).Nonempty"
  | .neEmpty s false => s!"{s.desc} ≠ ∅"
  | .neEmpty s true => s!"∅ ≠ {s.desc}"
  | .term s => s.desc

/-- Deterministic ASCII rendering used by `#interval_inspect (text := true)`.
For a bare term: `"Ioc a b: (a───b]"`. -/
def ascii : Shape → String
  | .mem x s => s!"{x.pp} ∈ {s.desc}: {x.pp} ∈ {s.ascii}"
  | .subset l r => s!"{l.desc} ⊆ {r.desc}: {l.ascii} ⊆ {r.ascii}"
  | .ssubset l r => s!"{l.desc} ⊂ {r.desc}: {l.ascii} ⊂ {r.ascii}"
  | .eq l r => s!"{l.desc} = {r.desc}: {l.ascii} = {r.ascii}"
  | .nonempty s => s!"({s.desc}).Nonempty: {s.ascii} ≠ ∅"
  | .neEmpty s false => s!"{s.desc} ≠ ∅: {s.ascii} ≠ ∅"
  | .neEmpty s true => s!"∅ ≠ {s.desc}: ∅ ≠ {s.ascii}"
  | .term s => s!"{s.desc}: {s.ascii}"

/-- Compact machine-oriented description used by tests, e.g.
`"eq(union(Ioc(a,b),Ioc(b,c)),Ioc(a,c))"`. -/
def debugString : Shape → String
  | .mem x s => s!"mem({x.pp},{s.debugString})"
  | .subset l r => s!"subset({l.debugString},{r.debugString})"
  | .ssubset l r => s!"ssubset({l.debugString},{r.debugString})"
  | .eq l r => s!"eq({l.debugString},{r.debugString})"
  | .nonempty s => s!"nonempty({s.debugString})"
  | .neEmpty s false => s!"neEmpty({s.debugString})"
  | .neEmpty s true => s!"neEmptyRev({s.debugString})"
  | .term s => s!"term({s.debugString})"

/-- All endpoints (atoms) appearing in the shape, traversal order, deduplicated by
pretty-printed form.  For `mem` shapes this includes the member `x`. -/
def atoms (s : Shape) : Array Endpoint := Id.run do
  let trees : Array Tree :=
    match s with
    | .mem _ t => #[t]
    | .subset l r | .ssubset l r | .eq l r => #[l, r]
    | .nonempty t | .neEmpty t _ => #[t]
    | .term t => #[t]
  let mut out : Array Endpoint :=
    match s with
    | .mem x _ => #[x]
    | _ => #[]
  for t in trees do
    for e in t.endpoints do
      if !out.any (·.pp == e.pp) then
        out := out.push e
  return out

end Shape

/-- `strContains h n`: does `h` contain `n` as a substring? (`n` must be nonempty.)
Used by rendering tests. -/
def strContains (h n : String) : Bool := (h.splitOn n).length > 1

end IntervalInspector
