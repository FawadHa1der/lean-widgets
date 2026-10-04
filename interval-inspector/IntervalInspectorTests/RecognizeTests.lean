import IntervalInspectorTests.Helpers
import Mathlib.Basic.Real.Basic
import Mathlib.Order.Interval.Finset.Defs
import Mathlib.Order.Interval.Finset.Nat

/-! # Recognition tests

Every interval kind over both `ℝ` and `ℕ`, all statement shapes, `∪`/`∩` trees,
endpoint literal extraction, binder-fact harvesting — and negatives: things that are
*not* interval shapes must return `none`.
-/

namespace IntervalInspectorTests

/-! ## The eight kinds over ℝ (symbolic endpoints) -/

#assert_shape ∀ (a b : ℝ), Set.Icc a b ⊆ Set.Icc a b => "subset(Icc(a,b),Icc(a,b))"
#assert_shape (fun (a b : ℝ) => Set.Icc a b) => "term(Icc(a,b))"
#assert_shape (fun (a b : ℝ) => Set.Ico a b) => "term(Ico(a,b))"
#assert_shape (fun (a b : ℝ) => Set.Ioc a b) => "term(Ioc(a,b))"
#assert_shape (fun (a b : ℝ) => Set.Ioo a b) => "term(Ioo(a,b))"
#assert_shape (fun (a : ℝ) => Set.Ici a) => "term(Ici(a))"
#assert_shape (fun (a : ℝ) => Set.Iic a) => "term(Iic(a))"
#assert_shape (fun (a : ℝ) => Set.Ioi a) => "term(Ioi(a))"
#assert_shape (fun (a : ℝ) => Set.Iio a) => "term(Iio(a))"

/-! ## The eight kinds over ℕ (literal endpoints) -/

#assert_shape (Set.Icc (2:ℕ) 7) => "term(Icc(2,7))"
#assert_shape (Set.Ico (2:ℕ) 7) => "term(Ico(2,7))"
#assert_shape (Set.Ioc (2:ℕ) 7) => "term(Ioc(2,7))"
#assert_shape (Set.Ioo (2:ℕ) 7) => "term(Ioo(2,7))"
#assert_shape (Set.Ici (3:ℕ)) => "term(Ici(3))"
#assert_shape (Set.Iic (3:ℕ)) => "term(Iic(3))"
#assert_shape (Set.Ioi (3:ℕ)) => "term(Ioi(3))"
#assert_shape (Set.Iio (3:ℕ)) => "term(Iio(3))"

/-! ## univ / empty / singleton -/

#assert_shape (Set.univ : Set ℝ) => "term(univ)"
#assert_shape (∅ : Set ℝ) => "term(empty)"
#assert_shape ({(3:ℝ)} : Set ℝ) => "term(sing(3))"
#assert_shape ∀ (a : ℝ), Set.Icc a a = {a} => "eq(Icc(a,a),sing(a))"

/-! ## Statement shapes -/

#assert_shape ((3:ℝ) ∈ Set.Icc 1 4) => "mem(3,Icc(1,4))"
#assert_shape ∀ (x a : ℝ), x ∈ Set.Ioi a => "mem(x,Ioi(a))"
#assert_shape ∀ (a b : ℝ), Set.Ioo a b ⊆ Set.Icc a b => "subset(Ioo(a,b),Icc(a,b))"
#assert_shape ∀ (a b : ℝ), Set.Ioo a b ⊂ Set.Icc a b => "ssubset(Ioo(a,b),Icc(a,b))"
#assert_shape ∀ (a b : ℝ), Set.Icc a b = Set.Icc a b => "eq(Icc(a,b),Icc(a,b))"
#assert_shape (Set.Ioc (1:ℝ) 2 ∪ Set.Ioc 2 3 = Set.Ioc 1 3)
  => "eq(union(Ioc(1,2),Ioc(2,3)),Ioc(1,3))"

/-! ## Union / intersection trees, including nesting -/

#assert_shape (fun (a b c : ℝ) => Set.Ioc a b ∪ Set.Ioc b c)
  => "term(union(Ioc(a,b),Ioc(b,c)))"
#assert_shape (fun (a b c d : ℝ) => Set.Icc a b ∩ Set.Icc c d)
  => "term(inter(Icc(a,b),Icc(c,d)))"
#assert_shape (fun (a b c d : ℝ) => (Set.Icc a b ∪ Set.Ico b c) ∩ Set.Iio d)
  => "term(inter(union(Icc(a,b),Ico(b,c)),Iio(d)))"
#assert_shape (fun (a b : ℝ) => Set.Iic a ∪ (Set.Ioo a b ∪ Set.Ici b))
  => "term(union(Iic(a),union(Ioo(a,b),Ici(b))))"
#assert_shape ∀ (x a b c : ℝ), x ∈ Set.Icc a b ∩ Set.Ioi c
  => "mem(x,inter(Icc(a,b),Ioi(c)))"

/-! ## Endpoint literal extraction (values as rationals) -/

#assert_atoms (Set.Icc (1:ℝ) 4) => "1=1, 4=4"
#assert_atoms (Set.Ioc (-3:ℝ) 2) => "-3=-3, 2=2"
#assert_atoms (Set.Icc (1/2:ℝ) (3/4:ℝ)) => "1 / 2=1/2, 3 / 4=3/4"
#assert_atoms (Set.Icc (2:ℕ) 7) => "2=2, 7=7"
#assert_atoms ∀ (a : ℝ), Set.Icc a 4 ⊆ Set.Ici 0 => "a, 4=4, 0=0"
#assert_atoms ((3:ℝ) ∈ Set.Icc 1 4) => "3=3, 1=1, 4=4"

/-! ## Division literals only get rational values over division rings

Over `ℕ`/`ℤ`, `1/3` is truncating division (`(1/3 : ℕ) = 0 = (1/2 : ℕ)`), so
assigning rational values would fabricate false ordering facts like `1/3 < 1/2`
(provably false over `ℕ`: `example : ¬((1:ℕ)/3 < 1/2) := by decide`).  Such
endpoints stay symbolic. -/

#assert_atoms (Set.Ico (1/3:ℕ) (1/2:ℕ)) => "1 / 3, 1 / 2"
#assert_atoms (Set.Ico (1/3:ℤ) 2) => "1 / 3, 2=2"
-- Over ℝ (a DivisionRing) the values are still extracted (see also the fractions
-- test above).
#assert_atoms (Set.Ico (1/3:ℝ) (1/2:ℝ)) => "1 / 3=1/3, 1 / 2=1/2"
-- Plain (non-division) ℕ literals keep their values.
#assert_atoms (Set.Ico (0:ℕ) 2) => "0=0, 2=2"
-- Negation still evaluates (ℤ has no misleading Neg on naturals to worry about).
#assert_atoms (Set.Ioc (-3:ℤ) 2) => "-3=-3, 2=2"

/-! ## Binder-fact harvesting -/

#assert_facts ∀ (a b c : ℝ), a ≤ b → b < c → Set.Icc a b ⊆ Set.Iio c
  => "a ≤ b; b < c"
#assert_facts ∀ (a b : ℝ), a ≥ b → Set.Icc b a = Set.Icc b a => "b ≤ a"
#assert_facts ∀ (a b : ℝ), a > b → Set.Icc b a = Set.Icc b a => "b < a"
#assert_facts ∀ (a b : ℝ), a = b → Set.Icc a b = Set.Icc a b => "a = b"

/-! ## Negatives: NOT interval shapes (must return none) -/

-- Finset intervals are deliberately unsupported (a Finset is not a continuum).
#assert_no_shape (Finset.Icc (2:ℕ) 7)
#assert_no_shape ∀ (x : ℕ), x ∈ Finset.Icc (2:ℕ) 7
-- Set.range is not recognized (matching is syntactic).
#assert_no_shape (Set.range (fun (n : ℕ) => n))
-- Plain set variables: no interval structure.
#assert_no_shape ∀ (s t : Set ℝ), s ⊆ t
#assert_no_shape ∀ (s : Set ℝ) (x : ℝ), x ∈ s
-- Membership in a non-Set collection.
#assert_no_shape ((1:ℕ) ∈ [1, 2, 3])
-- A bare comparison of scalars is a fact, not a shape.
#assert_no_shape ∀ (a b : ℝ), a ≤ b
-- Complements are not supported.
#assert_no_shape (fun (a b : ℝ) => (Set.Icc a b)ᶜ)
-- A union with one unrecognized operand is rejected as a whole.
#assert_no_shape ∀ (s : Set ℝ) (a b : ℝ), Set.Icc a b ∪ s = s
-- Non-Prop, non-Set terms.
#assert_no_shape (42 : ℕ)

/-! ## Nonemptiness / emptiness shapes -/

#assert_shape (Set.Ioc (1:ℝ) 2).Nonempty => "nonempty(Ioc(1,2))"
#assert_shape ∀ (a b : ℝ), (Set.Icc a b).Nonempty => "nonempty(Icc(a,b))"
#assert_shape ∀ (a : ℝ), (Set.Ici a).Nonempty => "nonempty(Ici(a))"
#assert_shape ∀ (a b c : ℝ), (Set.Icc a b ∪ Set.Icc b c).Nonempty
  => "nonempty(union(Icc(a,b),Icc(b,c)))"
#assert_shape ∀ (a b : ℝ), Set.Icc a b ≠ ∅ => "neEmpty(Icc(a,b))"
#assert_shape ∀ (a b : ℝ), ¬(Set.Ioo a b = ∅) => "neEmpty(Ioo(a,b))"
#assert_shape ∀ (a : ℝ), Set.Ioi a ≠ ∅ => "neEmpty(Ioi(a))"
-- The mirror spellings `∅ ≠ s` / `¬(∅ = s)` are recognized too (marked `Rev`, so
-- suggestions get a `.symm` wrapper).
#assert_shape ∀ (a b : ℝ), (∅ : Set ℝ) ≠ Set.Icc a b => "neEmptyRev(Icc(a,b))"
#assert_shape ∀ (a b : ℝ), ¬((∅ : Set ℝ) = Set.Ioo a b) => "neEmptyRev(Ioo(a,b))"
#assert_shape ∀ (a : ℝ), (∅ : Set ℝ) ≠ Set.Ioi a => "neEmptyRev(Ioi(a))"
-- `s = ∅` / `∅ = s` remain `eq` shapes (handled by the existing machinery).
#assert_shape ∀ (a b : ℝ), Set.Ioc a b = ∅ => "eq(Ioc(a,b),empty)"
#assert_shape ∀ (a b : ℝ), (∅ : Set ℝ) = Set.Ioc a b => "eq(empty,Ioc(a,b))"
-- Negatives: nonemptiness/disequality without interval structure.
#assert_no_shape ∀ (s : Set ℝ), s.Nonempty
#assert_no_shape ∀ (s : Set ℝ), s ≠ ∅
-- A disequality of two non-empty intervals carries no emptiness content.
#assert_no_shape ∀ (a b : ℝ), Set.Icc a b ≠ Set.Ico a b
-- `≠` on scalars is a fact, not a shape.
#assert_no_shape ∀ (a b : ℝ), a ≠ b
-- Degenerate `∅ ≠ ∅` is rejected rather than drawn.
#assert_no_shape ((∅ : Set ℝ) ≠ (∅ : Set ℝ))

/-! ## Instance availability per element type (feeds suggestion gating and shading)

Pins of `instAvailFor` through full recognition: `ℕ` is discrete and bounded below
(no `DenselyOrdered`, no `NoMinOrder` — but `NoMaxOrder` holds); `ℤ` is unbounded
but still discrete; `ℝ`/`ℚ` have everything; `ℝ × ℝ` (product order) has everything
*except* `LinearOrder`.  These are exactly the types of the confirmed
false-`ALL-READY` repros.  The trailing-instance classes (`DenselyOrdered`,
`NoMinOrder`, `NoMaxOrder` take a `[LT α]` argument) are the regression for the
under-applied-class bug in `hasInstance`: they must be *found* for `ℝ`. -/

#assert_insts (Set.Icc (0:ℕ) 2) => "PartialOrder LinearOrder Lattice NoMaxOrder"
#assert_insts (Set.Icc (0:ℤ) 2) => "PartialOrder LinearOrder Lattice NoMinOrder NoMaxOrder"
#assert_insts (Set.Icc (0:ℝ) 2)
  => "PartialOrder LinearOrder Lattice DenselyOrdered NoMinOrder NoMaxOrder"
#assert_insts (Set.Icc ((0,0) : ℝ × ℝ) (1,1))
  => "PartialOrder Lattice DenselyOrdered NoMinOrder NoMaxOrder"

/-! ## Distinct atoms that print identically stay distinct (`′` disambiguation)

The confirmed repro: two distinct fvars both named `a` (as produced by shadowed
binders after the RPC panel's `sanitizeNames` + dagger stripping).  With pp-string
keying they merged into one atom and `Set.Icc x x ⊆ Set.Icc y y` — false in
general — was reported `ALL-READY` (`a ≤ a` twice).  Expression-identity keying
must keep them apart (`a` / `a′`) and leave both conditions missing. -/

open Lean Meta Elab in
run_cmd Command.liftTermElabM do
  let real := Lean.mkConst ``Real
  Meta.withLocalDeclD `a real fun x =>
  Meta.withLocalDeclD `a real fun y => do
    let lhs ← mkAppM ``Set.Icc #[x, x]
    let rhs ← mkAppM ``Set.Icc #[y, y]
    let stmt ← mkAppM ``LE.le #[lhs, rhs]   -- the Set-order `⊆` spelling
    let some r ← IntervalInspector.recognizeWithBindersM? stmt
      | throwError "collision repro: expected recognition, got none"
    unless r.shape.debugString == "subset(Icc(a,a),Icc(a′,a′))" do
      throwError "collision repro: atoms merged or mis-keyed: {r.shape.debugString}"
    let g := r.shape.orderGraph r.facts
    let sugs := IntervalInspector.suggest r.shape g r.inst
    let reports := sugs.map fun s => s.report ++ (if s.ready then " [ALL-READY]" else "")
    unless reports == #["Set.Icc_subset_Icc [a′ ≤ a (missing); a ≤ a′ (missing)] — \
        refine Set.Icc_subset_Icc ?_ ?_"] do
      throwError "collision repro: expected both conditions missing, got: {reports}"

/-! ## Set-builder interval spellings (marked `*` = `fromSetBuilder` provenance) -/

-- All eight `≤`/`<` combinations, literal endpoints.
#assert_shape ({x : ℝ | 1 ≤ x ∧ x ≤ 2}) => "term(Icc*(1,2))"
#assert_shape ({x : ℝ | 1 ≤ x ∧ x < 2}) => "term(Ico*(1,2))"
#assert_shape ({x : ℝ | 1 < x ∧ x ≤ 2}) => "term(Ioc*(1,2))"
#assert_shape ({x : ℝ | 1 < x ∧ x < 2}) => "term(Ioo*(1,2))"
#assert_shape ({x : ℝ | 1 ≤ x}) => "term(Ici*(1))"
#assert_shape ({x : ℝ | 1 < x}) => "term(Ioi*(1))"
#assert_shape ({x : ℝ | x ≤ 2}) => "term(Iic*(2))"
#assert_shape ({x : ℝ | x < 2}) => "term(Iio*(2))"
-- Symbolic endpoints, and swapped conjunct order.
#assert_shape (fun (a b : ℝ) => {x | a ≤ x ∧ x < b}) => "term(Ico*(a,b))"
#assert_shape ({x : ℝ | x ≤ 2 ∧ 1 ≤ x}) => "term(Icc*(1,2))"
#assert_shape ({x : ℝ | x < 2 ∧ 1 ≤ x}) => "term(Ico*(1,2))"
-- The deprecated `setOf` alias (Mathlib 2026-07-09; a distinct constant from
-- `Set.ofPred`) must still be recognized, so terms spelled against older sources
-- keep working.  Scoped: only this line uses the deprecated name on purpose.
set_option linter.deprecated false in
#assert_shape (setOf fun x : ℝ => 1 ≤ x ∧ x < 2) => "term(Ico*(1,2))"
-- Endpoint literal values are extracted as for `Set.Ixx`.
#assert_atoms ({x : ℝ | 1 ≤ x ∧ x < 2}) => "1=1, 2=2"
-- Set-builder intervals participate in every statement shape and tree.
#assert_shape ({x : ℝ | 0 ≤ x ∧ x < 1} ⊆ Set.Icc 0 1) => "subset(Ico*(0,1),Icc(0,1))"
#assert_shape ∀ (a b : ℝ), ({x | a ≤ x} ∩ Set.Iio b) = Set.Ico a b
  => "eq(inter(Ici*(a),Iio(b)),Ico(a,b))"
#assert_shape ((1:ℝ) ∈ {x : ℝ | 0 ≤ x ∧ x ≤ 2}) => "mem(1,Icc*(0,2))"
#assert_shape ∀ (a b : ℝ), ({x | a ≤ x ∧ x < b}).Nonempty => "nonempty(Ico*(a,b))"
-- Negatives: bodies that are NOT one- or two-sided `≤`/`<` bounds on the binder.
#assert_no_shape ({x : ℝ | x ≤ 1 ∨ 2 ≤ x})              -- disjunction
#assert_no_shape ({_x : ℝ | (1:ℝ) ≤ 2})                 -- binder absent
#assert_no_shape (fun (y : ℝ) => {_x : ℝ | y ≤ y})      -- wrong variable compared
#assert_no_shape ({x : ℝ | x ≤ x})                      -- binder on both sides
#assert_no_shape ({x : ℝ | x + 1 ≤ x})                  -- bound mentions the binder
#assert_no_shape ({x : ℝ | x = 1})                      -- non-comparison body
#assert_no_shape ({x : ℝ | 1 ≤ x ∧ x ≤ 2 ∧ 1 ≤ x})     -- triple conjunction
#assert_no_shape ({x : ℝ | 1 ≤ x ∧ 2 ≤ x})             -- two lower bounds
#assert_no_shape ({x : ℝ | x ≥ 1})                      -- `≥` spelling unsupported
#assert_no_shape ({p : ℝ × ℝ | p.1 ≤ p.2})              -- not a comparison of the binder

end IntervalInspectorTests
