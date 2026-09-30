import IntervalInspector.OrderGraph
import IntervalInspector.Model
import Mathlib.Tactic.Linarith

/-! # Interval Inspector: suggestion engine

A curated table of real Mathlib lemmas keyed by recognized shape patterns.  Every
lemma name in the table has been verified against the pinned Mathlib revision, and
the test suite (`IntervalInspectorTests/SuggestTests.lean`) contains, for **every**
entry, both a firing test and an `example` proving the suggested lemma actually
closes its intended goal.

Each entry carries the required ordering side conditions (e.g. `a ≤ b`) *and* the
typeclass instances the lemma needs beyond `Preorder` (e.g. `LinearOrder`,
`DenselyOrdered`).  Side conditions are checked against the order graph and reported
as ready (a known fact) or missing.  Instance needs are checked against the
`InstAvail` computed during recognition: an entry with an unmet instance need is

* **suppressed** (with an explanatory note) when it has *no* ordering side
  conditions — such an entry would otherwise assert the goal outright
  (`exact Set.nonempty_Iio` over `ℕ` claims a false statement is closed), and
* **kept with a `missing instance` marker** (never ready) when it does have side
  conditions — the pattern match is still informative, but the lemma cannot apply
  to this type as-is.

When no table entry applies (or every match was suppressed), generic fallback
suggestions are produced instead (marked as fallbacks — they are heuristics, not
verified lemma applications).  Every tactic mentioned in a fallback is importable
from `IntervalInspector` itself (hence the `Mathlib.Tactic.Linarith` import above).
-/

namespace IntervalInspector

/-- A required ordering side condition of a suggested lemma. -/
structure Cond where
  /-- Left-hand atom (pretty-printed). -/
  lhs : String
  /-- Right-hand atom (pretty-printed). -/
  rhs : String
  /-- Required relation between them. -/
  rel : OrderRel := .le
  deriving Repr, BEq, Inhabited

namespace Cond

/-- `a ≤ b` shorthand. -/
def le (a b : String) : Cond := { lhs := a, rhs := b, rel := .le }
/-- `a < b` shorthand. -/
def lt (a b : String) : Cond := { lhs := a, rhs := b, rel := .lt }
/-- `a = b` shorthand. -/
def eq (a b : String) : Cond := { lhs := a, rhs := b, rel := .eq }

/-- Human-readable form, e.g. `"a ≤ b"`. -/
def desc (c : Cond) : String :=
  match c.rel with
  | .le => s!"{c.lhs} ≤ {c.rhs}"
  | .lt => s!"{c.lhs} < {c.rhs}"
  | .eq => s!"{c.lhs} = {c.rhs}"

/-- Is the condition a known fact of the order graph? -/
def holds (c : Cond) (g : OrderGraph) : Bool :=
  match c.rel with
  | .le => g.knownLe c.lhs c.rhs
  | .lt => g.knownLt c.lhs c.rhs
  | .eq => g.knownEq c.lhs c.rhs

end Cond

/-- A concrete suggestion produced for a recognized shape. -/
structure Suggestion where
  /-- Mathlib lemma name (or `"(fallback)"` for heuristic fallbacks). -/
  lemmaName : String
  /-- Tactic text to insert. -/
  tactic : String
  /-- Side conditions, each paired with its readiness (known in the order graph?). -/
  conds : Array (Cond × Bool) := #[]
  /-- Names of required typeclass instances that the element type does *not* have
  (e.g. `"DenselyOrdered"`).  Nonempty means the lemma cannot apply as-is. -/
  missingInsts : Array String := #[]
  /-- `true` for heuristic fallbacks (not verified lemma applications). -/
  isFallback : Bool := false
  deriving Repr, BEq, Inhabited

namespace Suggestion

/-- Are all side conditions known facts and all required instances available? -/
def ready (s : Suggestion) : Bool := s.conds.all (·.2) && s.missingInsts.isEmpty

/-- Side conditions that are not yet known facts. -/
def missing (s : Suggestion) : Array Cond :=
  (s.conds.filter (!·.2)).map (·.1)

/-- One-line report, e.g.
`"Set.Ioc_union_Ioc_eq_Ioc [a ≤ b (ready); b ≤ c (missing)] — refine …"`, with a
`[missing instance: …]` marker when the element type lacks a required instance. -/
def report (s : Suggestion) : String :=
  let condStr :=
    if s.conds.isEmpty then ""
    else
      let parts := s.conds.map fun (c, ok) =>
        s!"{c.desc} ({if ok then "ready" else "missing"})"
      s!" [{String.intercalate "; " parts.toList}]"
  let instStr :=
    if s.missingInsts.isEmpty then ""
    else s!" [missing instance: {String.intercalate ", " s.missingInsts.toList}]"
  s!"{s.lemmaName}{condStr}{instStr} — {s.tactic}"

end Suggestion

/-- Result of a successful table-entry match: side conditions, tactic text, and the
typeclass instances the lemma requires beyond `Preorder`. -/
structure EntryMatch where
  /-- Ordering side conditions of the suggested lemma. -/
  conds : Array Cond
  /-- Tactic text to insert. -/
  tactic : String
  /-- Instances the lemma requires beyond `Preorder` (checked against `InstAvail`). -/
  needs : Array InstanceNeed := #[]
  deriving Repr, BEq, Inhabited

/-- A suggestion-table entry: a lemma name and an applicability matcher returning
side conditions, tactic text and instance requirements when the shape fits. -/
structure Entry where
  /-- Fully qualified Mathlib lemma name. -/
  lemmaName : String
  /-- Applicability predicate. -/
  matcher : Shape → Option EntryMatch

namespace SuggestTable

/-- Leaf of a tree, when the tree is a single leaf. -/
def leaf? : Tree → Option Leaf
  | .leaf l => some l
  | _ => none

/-- Double-ended leaf as `(kind, lo, hi)`. -/
def de? (t : Tree) : Option (IntervalKind × String × String) := do
  let l ← leaf? t
  if l.kind.isDoubleEnded then
    return (l.kind, (← l.lo?).pp, (← l.hi?).pp)
  else none

/-- Left-bounded ray leaf (`Ici`/`Ioi`) as `(kind, lo)`. -/
def ray? (t : Tree) : Option (IntervalKind × String) := do
  let l ← leaf? t
  match l.kind with
  | .Ici | .Ioi => return (l.kind, (← l.lo?).pp)
  | .Iic | .Iio => return (l.kind, (← l.hi?).pp)
  | _ => none

/-- Union of two trees, when the tree is a union. -/
def union? : Tree → Option (Tree × Tree)
  | .union a b => some (a, b)
  | _ => none

/-- Same-kind two-piece union join `Ixx a b ∪ Ixx b c = Ixx a c` (`LinearOrder`). -/
def unionJoinSame (k : IntervalKind) (lemmaName : String) : Entry where
  lemmaName := lemmaName
  matcher
    | .eq l r => do
      let (t₁, t₂) ← union? l
      let (k₁, a, b) ← de? t₁
      let (k₂, b', c) ← de? t₂
      let (k₃, a', c') ← de? r
      if k₁ == k && k₂ == k && k₃ == k && b == b' && a == a' && c == c' then
        return { conds := #[.le a b, .le b c], tactic := s!"refine {lemmaName} ?_ ?_"
                 needs := #[.linearOrder] }
      else none
    | _ => none

/-- Mixed join `Ixx a b ∪ ray b = ray' a` (e.g. `Ioc a b ∪ Ioi b = Ioi a`;
`LinearOrder`). -/
def unionJoinRayRight (kBar kRay kRes : IntervalKind) (strict : Bool)
    (lemmaName : String) : Entry where
  lemmaName := lemmaName
  matcher
    | .eq l r => do
      let (t₁, t₂) ← union? l
      let (k₁, a, b) ← de? t₁
      let (k₂, b') ← ray? t₂
      let (k₃, a') ← ray? r
      if k₁ == kBar && k₂ == kRay && k₃ == kRes && b == b' && a == a' then
        return { conds := #[if strict then .lt a b else .le a b]
                 tactic := s!"refine {lemmaName} ?_", needs := #[.linearOrder] }
      else none
    | _ => none

/-- Mixed join `ray a ∪ Ixx a b = ray' b` (e.g. `Iio a ∪ Ico a b = Iio b`;
`LinearOrder`). -/
def unionJoinRayLeft (kRay kBar kRes : IntervalKind) (lemmaName : String) : Entry where
  lemmaName := lemmaName
  matcher
    | .eq l r => do
      let (t₁, t₂) ← union? l
      let (k₁, a) ← ray? t₁
      let (k₂, a', b) ← de? t₂
      let (k₃, b') ← ray? r
      if k₁ == kRay && k₂ == kBar && k₃ == kRes && a == a' && b == b' then
        return { conds := #[.le a b], tactic := s!"refine {lemmaName} ?_"
                 needs := #[.linearOrder] }
      else none
    | _ => none

/-- Whole-line cover `low-ray b ∪ high-ray a = univ` (`LinearOrder`). -/
def unionUniv (kLo kHi : IntervalKind) (strict : Bool) (needsCond : Bool)
    (lemmaName : String) : Entry where
  lemmaName := lemmaName
  matcher
    | .eq l r => do
      let (t₁, t₂) ← union? l
      let lLo ← leaf? t₁
      let lHi ← leaf? t₂
      let lr ← leaf? r
      if lLo.kind == kLo && lHi.kind == kHi && lr.kind == .univ then
        let b := (← lLo.hi?).pp
        let a := (← lHi.lo?).pp
        if needsCond then
          return { conds := #[if strict then .lt a b else .le a b]
                   tactic := s!"refine {lemmaName} ?_", needs := #[.linearOrder] }
        else if a == b then
          return { conds := #[], tactic := s!"exact {lemmaName}"
                   needs := #[.linearOrder] }
        else none
      else none
    | _ => none

/-- Same-kind bounded-interval inclusion monotonicity (`Icc_subset_Icc` etc.;
plain `Preorder`). -/
def monoSame (k : IntervalKind) (lemmaName : String) : Entry where
  lemmaName := lemmaName
  matcher
    | .subset l r => do
      let (k₁, a₁, b₁) ← de? l
      let (k₂, a₂, b₂) ← de? r
      if k₁ == k && k₂ == k then
        return { conds := #[.le a₂ a₁, .le b₁ b₂], tactic := s!"refine {lemmaName} ?_ ?_" }
      else none
    | _ => none

/-- One-sided-ray inclusion monotonicity (plain `Preorder`).  `viaIff` selects the
`.mpr` form.  `flip = false` for lower rays (`Iio a ⊆ Iio b` needs `a ≤ b`),
`flip = true` for upper rays (`Ioi b ⊆ Ioi a` needs `a ≤ b`). -/
def monoRay (k : IntervalKind) (flip viaIff : Bool) (lemmaName : String) : Entry where
  lemmaName := lemmaName
  matcher
    | .subset l r => do
      let (k₁, x) ← ray? l
      let (k₂, y) ← ray? r
      if k₁ == k && k₂ == k then
        let cond := if flip then Cond.le y x else Cond.le x y
        let tac := if viaIff then s!"refine {lemmaName}.mpr ?_" else s!"refine {lemmaName} ?_"
        return { conds := #[cond], tactic := tac }
      else none
    | _ => none

/-- Cross-kind inclusion with identical endpoints (`Ioo a b ⊆ Icc a b` etc.),
no side conditions, plain `Preorder`. -/
def crossSelf (kSub kSup : IntervalKind) (lemmaName : String) : Entry where
  lemmaName := lemmaName
  matcher
    | .subset l r => do
      let ll ← leaf? l
      let lr ← leaf? r
      if ll.kind == kSub && lr.kind == kSup
          && (ll.lo?.map (·.pp)) == (lr.lo?.map (·.pp))
          && (ll.hi?.map (·.pp)) == (lr.hi?.map (·.pp)) then
        return { conds := #[], tactic := s!"exact {lemmaName}" }
      else none
    | _ => none

/-- Membership unfolding for a double-ended kind: `x ∈ Ixx a b` (plain `Preorder`). -/
def memDe (k : IntervalKind) (lemmaName : String) : Entry where
  lemmaName := lemmaName
  matcher
    | .mem x t => do
      let (k', a, b) ← de? t
      if k' == k then
        let c₁ := if k.closedLeft then Cond.le a x.pp else Cond.lt a x.pp
        let c₂ := if k.closedRight then Cond.le x.pp b else Cond.lt x.pp b
        return { conds := #[c₁, c₂], tactic := s!"refine {lemmaName}.mpr ⟨?_, ?_⟩" }
      else none
    | _ => none

/-- Membership unfolding for a ray kind: `x ∈ Ici a` etc. (plain `Preorder`). -/
def memRay (k : IntervalKind) (lemmaName : String) : Entry where
  lemmaName := lemmaName
  matcher
    | .mem x t => do
      let l ← leaf? t
      if l.kind != k then none else
      let tac := s!"refine {lemmaName}.mpr ?_"
      match k with
      | .Ici => return { conds := #[.le (← l.lo?).pp x.pp], tactic := tac }
      | .Ioi => return { conds := #[.lt (← l.lo?).pp x.pp], tactic := tac }
      | .Iic => return { conds := #[.le x.pp (← l.hi?).pp], tactic := tac }
      | .Iio => return { conds := #[.lt x.pp (← l.hi?).pp], tactic := tac }
      | _ => none
    | _ => none

/-- Emptiness `Ixx a b = ∅` from reversed endpoints (plain `Preorder`). -/
def emptyOf (k : IntervalKind) (strict : Bool) (lemmaName tac : String) : Entry where
  lemmaName := lemmaName
  matcher
    | .eq l r => do
      let (k₁, a, b) ← de? l
      let lr ← leaf? r
      if k₁ == k && lr.kind == .empty then
        return { conds := #[if strict then .lt b a else .le b a], tactic := tac }
      else none
    | _ => none

/-- Reversed emptiness `∅ = Ixx a b`: flip with `.symm` around the kind's emptiness
lemma (plain `Preorder`).  One entry covers all four double-ended kinds (conditions
mirror `emptyOf`: strict `b < a` for `Icc`, `b ≤ a` otherwise). -/
def emptyOfRev : Entry where
  lemmaName := "Eq.symm"
  matcher
    | .eq l r => do
      let ll ← leaf? l
      guard (ll.kind == .empty)
      let (k, a, b) ← de? r
      let (cond, tac) ←
        match k with
        | .Icc => some (Cond.lt b a, "refine (Set.Icc_eq_empty (not_le.mpr ?_)).symm")
        | .Ico => some (Cond.le b a, "refine (Set.Ico_eq_empty (not_lt.mpr ?_)).symm")
        | .Ioc => some (Cond.le b a, "refine (Set.Ioc_eq_empty (not_lt.mpr ?_)).symm")
        | .Ioo => some (Cond.le b a, "refine (Set.Ioo_eq_empty (not_lt.mpr ?_)).symm")
        | _ => none
      return { conds := #[cond], tactic := tac }
    | _ => none

/-- Emptiness `Ixx a b = ∅` via the `_iff` characterization (same side condition as
`emptyOf`; `Ioo_eq_empty_iff` additionally needs `DenselyOrdered` — passed as
`needs`). -/
def emptyIff (k : IntervalKind) (strict : Bool) (lemmaName tac : String)
    (needs : Array InstanceNeed := #[]) : Entry where
  lemmaName := lemmaName
  matcher
    | .eq l r => do
      let (k₁, a, b) ← de? l
      let lr ← leaf? r
      if k₁ == k && lr.kind == .empty then
        return { conds := #[if strict then .lt b a else .le b a], tactic := tac, needs }
      else none
    | _ => none

/-- Nonemptiness `(Ixx a b).Nonempty` from the order condition on its endpoints:
`a ≤ b` for `Icc`, `a < b` for `Ico`/`Ioc`/`Ioo` (`nonempty_Ioo` additionally needs
`DenselyOrdered` — passed as `needs`). -/
def nonemptyDe (k : IntervalKind) (strict : Bool) (lemmaName : String)
    (needs : Array InstanceNeed := #[]) : Entry where
  lemmaName := lemmaName
  matcher
    | .nonempty t => do
      let (k₁, a, b) ← de? t
      if k₁ == k then
        return { conds := #[if strict then .lt a b else .le a b]
                 tactic := s!"refine {lemmaName}.mpr ?_", needs }
      else none
    | _ => none

/-- Nonemptiness of rays: no order side conditions, but `nonempty_Ioi` /
`nonempty_Iio` need `NoMaxOrder` / `NoMinOrder` instances — passed as `needs`. -/
def nonemptyRay (k : IntervalKind) (lemmaName : String)
    (needs : Array InstanceNeed := #[]) : Entry where
  lemmaName := lemmaName
  matcher
    | .nonempty t => do
      let l ← leaf? t
      if l.kind == k then return { conds := #[], tactic := s!"exact {lemmaName}", needs }
      else none
    | _ => none

/-- Non-emptiness as a disequality `Ixx … ≠ ∅` (or the mirror `∅ ≠ Ixx …`) via
`Set.Nonempty.ne_empty` composed with the kind's nonemptiness lemma (`.symm`-wrapped
for the mirror).  One entry covers all four double-ended kinds and the four rays;
side conditions mirror `nonemptyDe`/`nonemptyRay`, and so do the instance needs
(`DenselyOrdered` for `Ioo`, `NoMaxOrder`/`NoMinOrder` for `Ioi`/`Iio`). -/
def neEmptyOf : Entry where
  lemmaName := "Set.Nonempty.ne_empty"
  matcher
    | .neEmpty t rev => do
      let l ← leaf? t
      -- `.symm`-wrap for the reversed `∅ ≠ s` spelling.
      let refineTac (core : String) : String :=
        if rev then s!"refine ({core}).symm" else s!"refine {core}"
      let exactTac (core : String) : String :=
        if rev then s!"exact ({core}).symm" else s!"exact {core}"
      match l.kind with
      | .Icc => do
        let (_, a, b) ← de? t
        return { conds := #[.le a b]
                 tactic := refineTac "(Set.nonempty_Icc.mpr ?_).ne_empty" }
      | .Ico | .Ioc | .Ioo => do
        let (k, a, b) ← de? t
        return { conds := #[.lt a b]
                 tactic := refineTac s!"(Set.nonempty_{k.name}.mpr ?_).ne_empty"
                 needs := if k == .Ioo then #[.denselyOrdered] else #[] }
      | .Ici | .Ioi | .Iic | .Iio =>
        return { conds := #[]
                 tactic := exactTac s!"Set.nonempty_{l.kind.name}.ne_empty"
                 needs := match l.kind with
                   | .Ioi => #[.noMaxOrder]
                   | .Iio => #[.noMinOrder]
                   | _ => #[] }
      | _ => none
    | _ => none

/-- Intersection normal form `Ixx a₁ b₁ ∩ Ixx a₂ b₂ = Ixx (a₁ ⊔ a₂) (b₁ ⊓ b₂)`
suggested as a rewrite; matches an intersection at the head of an `=` or a bare
term.  `Icc_inter_Icc` needs `Lattice`, the open/half-open forms need
`LinearOrder` — passed as `needs`. -/
def interRw (k : IntervalKind) (lemmaName : String)
    (needs : Array InstanceNeed := #[]) : Entry where
  lemmaName := lemmaName
  matcher s := do
    let t ← match s with
      | .eq l _ => some l
      | .term t => some t
      | _ => none
    match t with
    | .inter a b => do
      let (k₁, _, _) ← de? a
      let (k₂, _, _) ← de? b
      if k₁ == k && k₂ == k then
        return { conds := #[], tactic := s!"rw [{lemmaName}]", needs }
      else none
    | _ => none

/-- The curated table.  Every lemma name is verified against the pinned Mathlib by
`IntervalInspectorTests/SuggestTests.lean`, and every instance requirement mirrors
the pinned Mathlib statement's context (`LinearOrder` for the union joins and
whole-line covers, `DenselyOrdered` for `nonempty_Ioo`/`Ioo_eq_empty_iff`,
`NoMaxOrder`/`NoMinOrder` for `nonempty_Ioi`/`nonempty_Iio`, `PartialOrder` for
`Icc_self`, `Lattice`/`LinearOrder` for the intersection normal forms). -/
def table : Array Entry := #[
  -- Same-kind union joins (the motivating scenario).
  unionJoinSame .Ioc "Set.Ioc_union_Ioc_eq_Ioc",
  unionJoinSame .Ico "Set.Ico_union_Ico_eq_Ico",
  unionJoinSame .Icc "Set.Icc_union_Icc_eq_Icc",
  -- Mixed joins with rays on the right.
  unionJoinRayRight .Ioo .Ici .Ioi true  "Set.Ioo_union_Ici_eq_Ioi",
  unionJoinRayRight .Ico .Ici .Ici false "Set.Ico_union_Ici_eq_Ici",
  unionJoinRayRight .Ioc .Ioi .Ioi false "Set.Ioc_union_Ioi_eq_Ioi",
  unionJoinRayRight .Icc .Ioi .Ici false "Set.Icc_union_Ioi_eq_Ici",
  -- Mixed joins with rays on the left.
  unionJoinRayLeft .Iio .Ico .Iio "Set.Iio_union_Ico_eq_Iio",
  unionJoinRayLeft .Iic .Ioc .Iic "Set.Iic_union_Ioc_eq_Iic",
  unionJoinRayLeft .Iio .Icc .Iic "Set.Iio_union_Icc_eq_Iic",
  -- Whole-line covers.
  unionUniv .Iic .Ici false false "Set.Iic_union_Ici",
  unionUniv .Iic .Ioi false true  "Set.Iic_union_Ioi_of_le",
  unionUniv .Iio .Ici false true  "Set.Iio_union_Ici_of_le",
  unionUniv .Iio .Ioi true  true  "Set.Iio_union_Ioi_of_lt",
  -- Same-kind inclusion monotonicity.
  monoSame .Icc "Set.Icc_subset_Icc",
  monoSame .Ico "Set.Ico_subset_Ico",
  monoSame .Ioc "Set.Ioc_subset_Ioc",
  monoSame .Ioo "Set.Ioo_subset_Ioo",
  monoRay .Iio false false "Set.Iio_subset_Iio",
  monoRay .Ioi true  false "Set.Ioi_subset_Ioi",
  monoRay .Iic false true  "Set.Iic_subset_Iic",
  monoRay .Ici true  true  "Set.Ici_subset_Ici",
  -- Cross-kind inclusions with identical endpoints.
  crossSelf .Ioo .Ico "Set.Ioo_subset_Ico_self",
  crossSelf .Ioo .Ioc "Set.Ioo_subset_Ioc_self",
  crossSelf .Ioo .Icc "Set.Ioo_subset_Icc_self",
  crossSelf .Ioc .Icc "Set.Ioc_subset_Icc_self",
  crossSelf .Ico .Icc "Set.Ico_subset_Icc_self",
  crossSelf .Ioi .Ici "Set.Ioi_subset_Ici_self",
  crossSelf .Iio .Iic "Set.Iio_subset_Iic_self",
  -- Membership unfolding.
  memDe .Icc "Set.mem_Icc",
  memDe .Ico "Set.mem_Ico",
  memDe .Ioc "Set.mem_Ioc",
  memDe .Ioo "Set.mem_Ioo",
  memRay .Ici "Set.mem_Ici",
  memRay .Iic "Set.mem_Iic",
  memRay .Ioi "Set.mem_Ioi",
  memRay .Iio "Set.mem_Iio",
  { lemmaName := "Set.mem_univ"
    matcher := fun
      | .mem _ (.leaf { kind := .univ, .. }) =>
        some { conds := #[], tactic := "exact Set.mem_univ _" }
      | _ => none },
  { lemmaName := "Set.mem_singleton_iff"
    matcher := fun
      | .mem x (.leaf l@({ kind := .singleton, .. })) =>
        (l.lo?.map fun a =>
          { conds := #[Cond.eq x.pp a.pp]
            tactic := "refine Set.mem_singleton_iff.mpr ?_" })
      | _ => none },
  -- Emptiness.
  emptyOf .Icc true  "Set.Icc_eq_empty" "refine Set.Icc_eq_empty (not_le.mpr ?_)",
  emptyOf .Ico false "Set.Ico_eq_empty" "refine Set.Ico_eq_empty (not_lt.mpr ?_)",
  emptyOf .Ioc false "Set.Ioc_eq_empty" "refine Set.Ioc_eq_empty (not_lt.mpr ?_)",
  emptyOf .Ioo false "Set.Ioo_eq_empty" "refine Set.Ioo_eq_empty (not_lt.mpr ?_)",
  -- Emptiness, `_iff` forms (Ioo's iff needs `DenselyOrdered`).
  emptyIff .Icc true  "Set.Icc_eq_empty_iff" "refine Set.Icc_eq_empty_iff.mpr (not_le.mpr ?_)",
  emptyIff .Ico false "Set.Ico_eq_empty_iff" "refine Set.Ico_eq_empty_iff.mpr (not_lt.mpr ?_)",
  emptyIff .Ioc false "Set.Ioc_eq_empty_iff" "refine Set.Ioc_eq_empty_iff.mpr (not_lt.mpr ?_)",
  emptyIff .Ioo false "Set.Ioo_eq_empty_iff" "refine Set.Ioo_eq_empty_iff.mpr (not_lt.mpr ?_)"
    #[.denselyOrdered],
  -- Reversed emptiness `∅ = Ixx a b` (all four kinds in one entry).
  emptyOfRev,
  -- Nonemptiness (Ioo's iff needs `DenselyOrdered`; Ioi/Iio need
  -- `NoMaxOrder`/`NoMinOrder`).
  nonemptyDe .Icc false "Set.nonempty_Icc",
  nonemptyDe .Ico true  "Set.nonempty_Ico",
  nonemptyDe .Ioc true  "Set.nonempty_Ioc",
  nonemptyDe .Ioo true  "Set.nonempty_Ioo" #[.denselyOrdered],
  nonemptyRay .Ici "Set.nonempty_Ici",
  nonemptyRay .Iic "Set.nonempty_Iic",
  nonemptyRay .Ioi "Set.nonempty_Ioi" #[.noMaxOrder],
  nonemptyRay .Iio "Set.nonempty_Iio" #[.noMinOrder],
  -- Non-emptiness as a disequality (all eight kinds, both `≠` orientations, in one
  -- entry).
  neEmptyOf,
  -- Degenerate closed interval (`Icc_self` needs antisymmetry: `PartialOrder`).
  { lemmaName := "Set.Icc_self"
    matcher := fun
      | .eq (.leaf l) (.leaf r) => do
        if l.kind == .Icc && r.kind == .singleton
            && (l.lo?.map (·.pp)) == (l.hi?.map (·.pp))
            && (l.lo?.map (·.pp)) == (r.lo?.map (·.pp)) then
          return { conds := #[], tactic := "exact Set.Icc_self _"
                   needs := #[.partialOrder] }
        else none
      | _ => none },
  -- Intersection normal forms.
  interRw .Icc "Set.Icc_inter_Icc" #[.lattice],
  interRw .Ico "Set.Ico_inter_Ico" #[.linearOrder],
  interRw .Ioc "Set.Ioc_inter_Ioc" #[.linearOrder],
  interRw .Ioo "Set.Ioo_inter_Ioo" #[.linearOrder]
]

end SuggestTable

/-- Fallback suggestions used when no table entry applies (or every match was
suppressed for a missing instance).  Heuristics, labeled as such; every tactic
mentioned is importable from `IntervalInspector` itself. -/
def fallbackSuggestions (s : Shape) : Array Suggestion :=
  let mk (t : String) : Suggestion :=
    { lemmaName := "(fallback)", tactic := t, isFallback := true }
  match s with
  | .mem _ _ => #[mk "constructor <;> simp_all"]
  | .subset _ _ | .ssubset _ _ =>
    #[mk "simp [Set.subset_def]; intro x hx; constructor <;> linarith"]
  | .eq _ _ =>
    #[mk "constructor <;> simp_all",
      mk "ext x; simp only [Set.mem_union, Set.mem_inter_iff]; constructor <;> \
          (intro h; simp_all) <;> constructor <;> linarith"]
  | .nonempty _ => #[mk "simp [Set.nonempty_iff_ne_empty]"]
  | .neEmpty _ false => #[mk "rw [← Set.nonempty_iff_ne_empty]; simp_all"]
  | .neEmpty _ true =>
    #[mk "apply Ne.symm; rw [← Set.nonempty_iff_ne_empty]; simp_all"]
  | .term _ => #[]

/-- All suggestions for a shape, together with notes about matches that were
*suppressed*: table entries whose lemma requires a typeclass instance the element
type does not have and which carry no ordering side conditions (so displaying them
would assert the goal outright).  Matches with unmet instance needs that *do* carry
side conditions are kept, marked `missingInsts` (never ready).  Falls back when no
match survives. -/
def suggestFull (s : Shape) (g : OrderGraph) (inst : InstAvail := .all) :
    Array Suggestion × Array String := Id.run do
  let mut kept : Array Suggestion := #[]
  let mut suppressed : Array String := #[]
  for entry in SuggestTable.table do
    if let some m := entry.matcher s then
      let unmet := m.needs.filter fun n => !inst.has n
      if unmet.isEmpty then
        kept := kept.push { lemmaName := entry.lemmaName, tactic := m.tactic
                            conds := m.conds.map fun c => (c, c.holds g) }
      else
        let names := unmet.map (·.name)
        if m.conds.isEmpty then
          suppressed := suppressed.push
            s!"{entry.lemmaName} suppressed: needs {String.intercalate ", " names.toList} \
               (no instance for this type)"
        else
          kept := kept.push { lemmaName := entry.lemmaName, tactic := m.tactic
                              conds := m.conds.map fun c => (c, c.holds g)
                              missingInsts := names }
  if kept.isEmpty then return (fallbackSuggestions s, suppressed)
  else return (kept, suppressed)

/-- All suggestions for a shape: matching table entries with side-condition readiness
checked against the order graph and instance needs checked against `inst`, or
fallbacks when nothing (surviving) applies.  See `suggestFull` for the suppression
notes. -/
def suggest (s : Shape) (g : OrderGraph) (inst : InstAvail := .all) : Array Suggestion :=
  (suggestFull s g inst).1

/-- Names of the table entries firing on a shape (readiness and instance
availability ignored) — test helper. -/
def firingLemmas (s : Shape) : Array String :=
  SuggestTable.table.filterMap fun e => (e.matcher s).map fun _ => e.lemmaName

end IntervalInspector
