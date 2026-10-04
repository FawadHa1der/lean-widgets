import IntervalInspectorTests.Helpers
import Mathlib.Order.Interval.Set.Basic
import Mathlib.Order.Interval.Set.LinearOrder
import Mathlib.Basic.Real.Basic

/-! # Suggestion-engine tests

For **every** table entry: (a) a firing test asserting the entry matches exactly its
intended shape, and (b) an `example` proving that the suggested Mathlib lemma really
closes that goal (so every lemma name in the table is verified against the pinned
Mathlib).  Plus side-condition readiness reporting and fallback behavior.
-/

namespace IntervalInspectorTests

open IntervalInspector

variable {α : Type*} [LinearOrder α] {a b c x a₁ a₂ b₁ b₂ : α}

/-! ## 1–3: same-kind union joins -/

#guard firingLemmas (.eq (.union (de .Ioc "a" "b") (de .Ioc "b" "c")) (de .Ioc "a" "c"))
    == #["Set.Ioc_union_Ioc_eq_Ioc"]
example (h₁ : a ≤ b) (h₂ : b ≤ c) : Set.Ioc a b ∪ Set.Ioc b c = Set.Ioc a c :=
  Set.Ioc_union_Ioc_eq_Ioc h₁ h₂

#guard firingLemmas (.eq (.union (de .Ico "a" "b") (de .Ico "b" "c")) (de .Ico "a" "c"))
    == #["Set.Ico_union_Ico_eq_Ico"]
example (h₁ : a ≤ b) (h₂ : b ≤ c) : Set.Ico a b ∪ Set.Ico b c = Set.Ico a c :=
  Set.Ico_union_Ico_eq_Ico h₁ h₂

#guard firingLemmas (.eq (.union (de .Icc "a" "b") (de .Icc "b" "c")) (de .Icc "a" "c"))
    == #["Set.Icc_union_Icc_eq_Icc"]
example (h₁ : a ≤ b) (h₂ : b ≤ c) : Set.Icc a b ∪ Set.Icc b c = Set.Icc a c :=
  Set.Icc_union_Icc_eq_Icc h₁ h₂

-- Endpoint discipline: mismatched middle endpoints must NOT fire the join.
#guard firingLemmas (.eq (.union (de .Ioc "a" "b") (de .Ioc "b'" "c")) (de .Ioc "a" "c"))
    == #[]
-- Wrong result endpoints must NOT fire either.
#guard firingLemmas (.eq (.union (de .Ioc "a" "b") (de .Ioc "b" "c")) (de .Ioc "a" "d"))
    == #[]

/-! ## 4–7: mixed joins, ray on the right -/

#guard firingLemmas (.eq (.union (de .Ioo "a" "b") (rayLo .Ici "b")) (rayLo .Ioi "a"))
    == #["Set.Ioo_union_Ici_eq_Ioi"]
example (h : a < b) : Set.Ioo a b ∪ Set.Ici b = Set.Ioi a := Set.Ioo_union_Ici_eq_Ioi h

#guard firingLemmas (.eq (.union (de .Ico "a" "b") (rayLo .Ici "b")) (rayLo .Ici "a"))
    == #["Set.Ico_union_Ici_eq_Ici"]
example (h : a ≤ b) : Set.Ico a b ∪ Set.Ici b = Set.Ici a := Set.Ico_union_Ici_eq_Ici h

#guard firingLemmas (.eq (.union (de .Ioc "a" "b") (rayLo .Ioi "b")) (rayLo .Ioi "a"))
    == #["Set.Ioc_union_Ioi_eq_Ioi"]
example (h : a ≤ b) : Set.Ioc a b ∪ Set.Ioi b = Set.Ioi a := Set.Ioc_union_Ioi_eq_Ioi h

#guard firingLemmas (.eq (.union (de .Icc "a" "b") (rayLo .Ioi "b")) (rayLo .Ici "a"))
    == #["Set.Icc_union_Ioi_eq_Ici"]
example (h : a ≤ b) : Set.Icc a b ∪ Set.Ioi b = Set.Ici a := Set.Icc_union_Ioi_eq_Ici h

/-! ## 8–10: mixed joins, ray on the left -/

#guard firingLemmas (.eq (.union (rayHi .Iio "a") (de .Ico "a" "b")) (rayHi .Iio "b"))
    == #["Set.Iio_union_Ico_eq_Iio"]
example (h : a ≤ b) : Set.Iio a ∪ Set.Ico a b = Set.Iio b := Set.Iio_union_Ico_eq_Iio h

#guard firingLemmas (.eq (.union (rayHi .Iic "a") (de .Ioc "a" "b")) (rayHi .Iic "b"))
    == #["Set.Iic_union_Ioc_eq_Iic"]
example (h : a ≤ b) : Set.Iic a ∪ Set.Ioc a b = Set.Iic b := Set.Iic_union_Ioc_eq_Iic h

#guard firingLemmas (.eq (.union (rayHi .Iio "a") (de .Icc "a" "b")) (rayHi .Iic "b"))
    == #["Set.Iio_union_Icc_eq_Iic"]
example (h : a ≤ b) : Set.Iio a ∪ Set.Icc a b = Set.Iic b := Set.Iio_union_Icc_eq_Iic h

/-! ## 11–14: whole-line covers -/

#guard firingLemmas (.eq (.union (rayHi .Iic "a") (rayLo .Ici "a")) univT)
    == #["Set.Iic_union_Ici"]
example : Set.Iic a ∪ Set.Ici a = Set.univ := Set.Iic_union_Ici
-- Different endpoints do NOT fire the no-hypothesis form.
#guard firingLemmas (.eq (.union (rayHi .Iic "a") (rayLo .Ici "b")) univT) == #[]

#guard firingLemmas (.eq (.union (rayHi .Iic "b") (rayLo .Ioi "a")) univT)
    == #["Set.Iic_union_Ioi_of_le"]
example (h : a ≤ b) : Set.Iic b ∪ Set.Ioi a = Set.univ := Set.Iic_union_Ioi_of_le h

#guard firingLemmas (.eq (.union (rayHi .Iio "b") (rayLo .Ici "a")) univT)
    == #["Set.Iio_union_Ici_of_le"]
example (h : a ≤ b) : Set.Iio b ∪ Set.Ici a = Set.univ := Set.Iio_union_Ici_of_le h

#guard firingLemmas (.eq (.union (rayHi .Iio "b") (rayLo .Ioi "a")) univT)
    == #["Set.Iio_union_Ioi_of_lt"]
example (h : a < b) : Set.Iio b ∪ Set.Ioi a = Set.univ := Set.Iio_union_Ioi_of_lt h

/-! ## 15–18: same-kind inclusion monotonicity -/

#guard firingLemmas (.subset (de .Icc "a₁" "b₁") (de .Icc "a₂" "b₂"))
    == #["Set.Icc_subset_Icc"]
example (ha : a₂ ≤ a₁) (hb : b₁ ≤ b₂) : Set.Icc a₁ b₁ ⊆ Set.Icc a₂ b₂ :=
  Set.Icc_subset_Icc ha hb

#guard firingLemmas (.subset (de .Ico "a₁" "b₁") (de .Ico "a₂" "b₂"))
    == #["Set.Ico_subset_Ico"]
example (ha : a₂ ≤ a₁) (hb : b₁ ≤ b₂) : Set.Ico a₁ b₁ ⊆ Set.Ico a₂ b₂ :=
  Set.Ico_subset_Ico ha hb

#guard firingLemmas (.subset (de .Ioc "a₁" "b₁") (de .Ioc "a₂" "b₂"))
    == #["Set.Ioc_subset_Ioc"]
example (ha : a₂ ≤ a₁) (hb : b₁ ≤ b₂) : Set.Ioc a₁ b₁ ⊆ Set.Ioc a₂ b₂ :=
  Set.Ioc_subset_Ioc ha hb

#guard firingLemmas (.subset (de .Ioo "a₁" "b₁") (de .Ioo "a₂" "b₂"))
    == #["Set.Ioo_subset_Ioo"]
example (ha : a₂ ≤ a₁) (hb : b₁ ≤ b₂) : Set.Ioo a₁ b₁ ⊆ Set.Ioo a₂ b₂ :=
  Set.Ioo_subset_Ioo ha hb

/-! ## 19–22: ray inclusion monotonicity (note the flipped directions) -/

#guard firingLemmas (.subset (rayHi .Iio "a") (rayHi .Iio "b")) == #["Set.Iio_subset_Iio"]
example (h : a ≤ b) : Set.Iio a ⊆ Set.Iio b := Set.Iio_subset_Iio h

#guard firingLemmas (.subset (rayLo .Ioi "b") (rayLo .Ioi "a")) == #["Set.Ioi_subset_Ioi"]
example (h : a ≤ b) : Set.Ioi b ⊆ Set.Ioi a := Set.Ioi_subset_Ioi h

#guard firingLemmas (.subset (rayHi .Iic "a") (rayHi .Iic "b")) == #["Set.Iic_subset_Iic"]
example (h : a ≤ b) : Set.Iic a ⊆ Set.Iic b := Set.Iic_subset_Iic.mpr h

#guard firingLemmas (.subset (rayLo .Ici "b") (rayLo .Ici "a")) == #["Set.Ici_subset_Ici"]
example (h : a ≤ b) : Set.Ici b ⊆ Set.Ici a := Set.Ici_subset_Ici.mpr h

-- Directions of the flipped ray conditions (Ioi/Ici compare RHS ≤ LHS).
#guard (suggest (.subset (rayLo .Ioi "p") (rayLo .Ioi "q")) (graphOf ["p", "q"] []))[0]!
    |>.conds[0]!.1.desc == "q ≤ p"
#guard (suggest (.subset (rayHi .Iio "p") (rayHi .Iio "q")) (graphOf ["p", "q"] []))[0]!
    |>.conds[0]!.1.desc == "p ≤ q"

/-! ## 23–29: cross-kind inclusions with identical endpoints -/

#guard firingLemmas (.subset (de .Ioo "a" "b") (de .Ico "a" "b"))
    == #["Set.Ioo_subset_Ico_self"]
example : Set.Ioo a b ⊆ Set.Ico a b := Set.Ioo_subset_Ico_self

#guard firingLemmas (.subset (de .Ioo "a" "b") (de .Ioc "a" "b"))
    == #["Set.Ioo_subset_Ioc_self"]
example : Set.Ioo a b ⊆ Set.Ioc a b := Set.Ioo_subset_Ioc_self

#guard firingLemmas (.subset (de .Ioo "a" "b") (de .Icc "a" "b"))
    == #["Set.Ioo_subset_Icc_self"]
example : Set.Ioo a b ⊆ Set.Icc a b := Set.Ioo_subset_Icc_self

#guard firingLemmas (.subset (de .Ioc "a" "b") (de .Icc "a" "b"))
    == #["Set.Ioc_subset_Icc_self"]
example : Set.Ioc a b ⊆ Set.Icc a b := Set.Ioc_subset_Icc_self

#guard firingLemmas (.subset (de .Ico "a" "b") (de .Icc "a" "b"))
    == #["Set.Ico_subset_Icc_self"]
example : Set.Ico a b ⊆ Set.Icc a b := Set.Ico_subset_Icc_self

#guard firingLemmas (.subset (rayLo .Ioi "a") (rayLo .Ici "a"))
    == #["Set.Ioi_subset_Ici_self"]
example : Set.Ioi a ⊆ Set.Ici a := Set.Ioi_subset_Ici_self

#guard firingLemmas (.subset (rayHi .Iio "a") (rayHi .Iic "a"))
    == #["Set.Iio_subset_Iic_self"]
example : Set.Iio a ⊆ Set.Iic a := Set.Iio_subset_Iic_self

-- Cross-kind with *different* endpoints must not fire the `_self` entries.
#guard firingLemmas (.subset (de .Ioo "a" "b") (de .Icc "a" "c")) == #[]

/-! ## 30–37: membership unfolding -/

#guard firingLemmas (.mem (ep "x") (de .Icc "a" "b")) == #["Set.mem_Icc"]
example (h₁ : a ≤ x) (h₂ : x ≤ b) : x ∈ Set.Icc a b := Set.mem_Icc.mpr ⟨h₁, h₂⟩

#guard firingLemmas (.mem (ep "x") (de .Ico "a" "b")) == #["Set.mem_Ico"]
example (h₁ : a ≤ x) (h₂ : x < b) : x ∈ Set.Ico a b := Set.mem_Ico.mpr ⟨h₁, h₂⟩

#guard firingLemmas (.mem (ep "x") (de .Ioc "a" "b")) == #["Set.mem_Ioc"]
example (h₁ : a < x) (h₂ : x ≤ b) : x ∈ Set.Ioc a b := Set.mem_Ioc.mpr ⟨h₁, h₂⟩

#guard firingLemmas (.mem (ep "x") (de .Ioo "a" "b")) == #["Set.mem_Ioo"]
example (h₁ : a < x) (h₂ : x < b) : x ∈ Set.Ioo a b := Set.mem_Ioo.mpr ⟨h₁, h₂⟩

#guard firingLemmas (.mem (ep "x") (rayLo .Ici "a")) == #["Set.mem_Ici"]
example (h : a ≤ x) : x ∈ Set.Ici a := Set.mem_Ici.mpr h

#guard firingLemmas (.mem (ep "x") (rayHi .Iic "b")) == #["Set.mem_Iic"]
example (h : x ≤ b) : x ∈ Set.Iic b := Set.mem_Iic.mpr h

#guard firingLemmas (.mem (ep "x") (rayLo .Ioi "a")) == #["Set.mem_Ioi"]
example (h : a < x) : x ∈ Set.Ioi a := Set.mem_Ioi.mpr h

#guard firingLemmas (.mem (ep "x") (rayHi .Iio "b")) == #["Set.mem_Iio"]
example (h : x < b) : x ∈ Set.Iio b := Set.mem_Iio.mpr h

-- Membership conditions carry the right strictness per side.
#guard ((suggest (.mem (ep "x") (de .Ioc "a" "b")) (graphOf ["x", "a", "b"] []))[0]!.conds.map
    (·.1.desc)) == #["a < x", "x ≤ b"]
#guard ((suggest (.mem (ep "x") (de .Ico "a" "b")) (graphOf ["x", "a", "b"] []))[0]!.conds.map
    (·.1.desc)) == #["a ≤ x", "x < b"]

/-! ## 38–39: univ and singleton membership -/

#guard firingLemmas (.mem (ep "x") univT) == #["Set.mem_univ"]
example : x ∈ (Set.univ : Set α) := Set.mem_univ x

#guard firingLemmas (.mem (ep "x") (singT "a")) == #["Set.mem_singleton_iff"]
example : x ∈ ({x} : Set α) := Set.mem_singleton_iff.mpr rfl

/-! ## 40–43: emptiness (each kind now also fires its `_iff` form, entries 49–52) -/

#guard firingLemmas (.eq (de .Icc "a" "b") emptyT)
    == #["Set.Icc_eq_empty", "Set.Icc_eq_empty_iff"]
example (h : b < a) : Set.Icc a b = ∅ := Set.Icc_eq_empty (not_le.mpr h)

#guard firingLemmas (.eq (de .Ico "a" "b") emptyT)
    == #["Set.Ico_eq_empty", "Set.Ico_eq_empty_iff"]
example (h : b ≤ a) : Set.Ico a b = ∅ := Set.Ico_eq_empty (not_lt.mpr h)

#guard firingLemmas (.eq (de .Ioc "a" "b") emptyT)
    == #["Set.Ioc_eq_empty", "Set.Ioc_eq_empty_iff"]
example (h : b ≤ a) : Set.Ioc a b = ∅ := Set.Ioc_eq_empty (not_lt.mpr h)

#guard firingLemmas (.eq (de .Ioo "a" "b") emptyT)
    == #["Set.Ioo_eq_empty", "Set.Ioo_eq_empty_iff"]
example (h : b ≤ a) : Set.Ioo a b = ∅ := Set.Ioo_eq_empty (not_lt.mpr h)

-- The Icc emptiness condition is strict (b < a); the Ioo one is not (b ≤ a).
#guard ((suggest (.eq (de .Icc "a" "b") emptyT) (graphOf ["a", "b"] []))[0]!.conds.map
    (·.1.desc)) == #["b < a"]
#guard ((suggest (.eq (de .Ioo "a" "b") emptyT) (graphOf ["a", "b"] []))[0]!.conds.map
    (·.1.desc)) == #["b ≤ a"]

/-! ## 44: degenerate closed interval -/

#guard firingLemmas (.eq (de .Icc "a" "a") (singT "a")) == #["Set.Icc_self"]
example : Set.Icc a a = {a} := Set.Icc_self a
-- Non-degenerate Icc = {a} must not fire.
#guard firingLemmas (.eq (de .Icc "a" "b") (singT "a")) == #[]

/-! ## 45–48: intersection normal forms -/

#guard firingLemmas (.eq (.inter (de .Icc "a₁" "b₁") (de .Icc "a₂" "b₂")) (de .Icc "u" "v"))
    == #["Set.Icc_inter_Icc"]
example : Set.Icc a₁ b₁ ∩ Set.Icc a₂ b₂ = Set.Icc (a₁ ⊔ a₂) (b₁ ⊓ b₂) := Set.Icc_inter_Icc

#guard firingLemmas (.term (.inter (de .Ico "a₁" "b₁") (de .Ico "a₂" "b₂")))
    == #["Set.Ico_inter_Ico"]
example : Set.Ico a₁ b₁ ∩ Set.Ico a₂ b₂ = Set.Ico (a₁ ⊔ a₂) (b₁ ⊓ b₂) := Set.Ico_inter_Ico

#guard firingLemmas (.term (.inter (de .Ioc "a₁" "b₁") (de .Ioc "a₂" "b₂")))
    == #["Set.Ioc_inter_Ioc"]
example : Set.Ioc a₁ b₁ ∩ Set.Ioc a₂ b₂ = Set.Ioc (a₁ ⊔ a₂) (b₁ ⊓ b₂) := Set.Ioc_inter_Ioc

#guard firingLemmas (.term (.inter (de .Ioo "a₁" "b₁") (de .Ioo "a₂" "b₂")))
    == #["Set.Ioo_inter_Ioo"]
example : Set.Ioo a₁ b₁ ∩ Set.Ioo a₂ b₂ = Set.Ioo (a₁ ⊔ a₂) (b₁ ⊓ b₂) := Set.Ioo_inter_Ioo

-- Mixed-kind intersections are not in the table.
#guard firingLemmas (.term (.inter (de .Icc "a₁" "b₁") (de .Ioo "a₂" "b₂"))) == #[]

/-! ## 49–52: emptiness `_iff` forms

Firing tests are the two-element lists in ## 40–43 above (implication + `_iff` fire
together on `Ixx a b = ∅`); here each `_iff` lemma is verified to close its goal.
`Ioo_eq_empty_iff` needs `DenselyOrdered`, so its example runs over `ℝ`. -/

example (h : b < a) : Set.Icc a b = ∅ := Set.Icc_eq_empty_iff.mpr (not_le.mpr h)
example (h : b ≤ a) : Set.Ico a b = ∅ := Set.Ico_eq_empty_iff.mpr (not_lt.mpr h)
example (h : b ≤ a) : Set.Ioc a b = ∅ := Set.Ioc_eq_empty_iff.mpr (not_lt.mpr h)
example {u v : ℝ} (h : v ≤ u) : Set.Ioo u v = ∅ := Set.Ioo_eq_empty_iff.mpr (not_lt.mpr h)

/-! ## 53: reversed emptiness `∅ = Ixx a b` (one entry, all four kinds) -/

#guard firingLemmas (.eq emptyT (de .Icc "a" "b")) == #["Eq.symm"]
#guard firingLemmas (.eq emptyT (de .Ico "a" "b")) == #["Eq.symm"]
#guard firingLemmas (.eq emptyT (de .Ioc "a" "b")) == #["Eq.symm"]
#guard firingLemmas (.eq emptyT (de .Ioo "a" "b")) == #["Eq.symm"]
example (h : b < a) : (∅ : Set α) = Set.Icc a b := (Set.Icc_eq_empty (not_le.mpr h)).symm
example (h : b ≤ a) : (∅ : Set α) = Set.Ico a b := (Set.Ico_eq_empty (not_lt.mpr h)).symm
example (h : b ≤ a) : (∅ : Set α) = Set.Ioc a b := (Set.Ioc_eq_empty (not_lt.mpr h)).symm
example (h : b ≤ a) : (∅ : Set α) = Set.Ioo a b := (Set.Ioo_eq_empty (not_lt.mpr h)).symm
-- Rays and rev-emptiness of non-de kinds are not matched.
#guard firingLemmas (.eq emptyT (rayLo .Ici "a")) == #[]

/-! ## 54–57: nonemptiness of bounded intervals -/

#guard firingLemmas (.nonempty (de .Icc "a" "b")) == #["Set.nonempty_Icc"]
example (h : a ≤ b) : (Set.Icc a b).Nonempty := Set.nonempty_Icc.mpr h

#guard firingLemmas (.nonempty (de .Ico "a" "b")) == #["Set.nonempty_Ico"]
example (h : a < b) : (Set.Ico a b).Nonempty := Set.nonempty_Ico.mpr h

#guard firingLemmas (.nonempty (de .Ioc "a" "b")) == #["Set.nonempty_Ioc"]
example (h : a < b) : (Set.Ioc a b).Nonempty := Set.nonempty_Ioc.mpr h

-- `nonempty_Ioo` is an iff only under `DenselyOrdered`: the example runs over `ℝ`.
#guard firingLemmas (.nonempty (de .Ioo "a" "b")) == #["Set.nonempty_Ioo"]
example {u v : ℝ} (h : u < v) : (Set.Ioo u v).Nonempty := Set.nonempty_Ioo.mpr h

/-! ## 58–61: nonemptiness of rays (no side conditions; `Ioi`/`Iio` need
`NoMaxOrder`/`NoMinOrder` instances, so those examples run over `ℝ`) -/

#guard firingLemmas (.nonempty (rayLo .Ici "a")) == #["Set.nonempty_Ici"]
example : (Set.Ici a).Nonempty := Set.nonempty_Ici

#guard firingLemmas (.nonempty (rayHi .Iic "b")) == #["Set.nonempty_Iic"]
example : (Set.Iic a).Nonempty := Set.nonempty_Iic

#guard firingLemmas (.nonempty (rayLo .Ioi "a")) == #["Set.nonempty_Ioi"]
example {u : ℝ} : (Set.Ioi u).Nonempty := Set.nonempty_Ioi

#guard firingLemmas (.nonempty (rayHi .Iio "b")) == #["Set.nonempty_Iio"]
example {u : ℝ} : (Set.Iio u).Nonempty := Set.nonempty_Iio

-- Nonemptiness of composites / univ / ∅ / {a} is not in the table.
#guard firingLemmas (.nonempty (.union (de .Icc "a" "b") (de .Icc "b" "c"))) == #[]
#guard firingLemmas (.nonempty univT) == #[]

/-! ## 62: `Ixx … ≠ ∅` via `Set.Nonempty.ne_empty` (one entry, all eight kinds) -/

#guard firingLemmas (.neEmpty (de .Icc "a" "b")) == #["Set.Nonempty.ne_empty"]
#guard firingLemmas (.neEmpty (de .Ico "a" "b")) == #["Set.Nonempty.ne_empty"]
#guard firingLemmas (.neEmpty (de .Ioc "a" "b")) == #["Set.Nonempty.ne_empty"]
#guard firingLemmas (.neEmpty (de .Ioo "a" "b")) == #["Set.Nonempty.ne_empty"]
#guard firingLemmas (.neEmpty (rayLo .Ici "a")) == #["Set.Nonempty.ne_empty"]
#guard firingLemmas (.neEmpty (rayHi .Iic "b")) == #["Set.Nonempty.ne_empty"]
#guard firingLemmas (.neEmpty (rayLo .Ioi "a")) == #["Set.Nonempty.ne_empty"]
#guard firingLemmas (.neEmpty (rayHi .Iio "b")) == #["Set.Nonempty.ne_empty"]
example (h : a ≤ b) : Set.Icc a b ≠ ∅ := (Set.nonempty_Icc.mpr h).ne_empty
example (h : a < b) : Set.Ico a b ≠ ∅ := (Set.nonempty_Ico.mpr h).ne_empty
example (h : a < b) : Set.Ioc a b ≠ ∅ := (Set.nonempty_Ioc.mpr h).ne_empty
example {u v : ℝ} (h : u < v) : Set.Ioo u v ≠ ∅ := (Set.nonempty_Ioo.mpr h).ne_empty
example : Set.Ici a ≠ ∅ := Set.nonempty_Ici.ne_empty
example : Set.Iic a ≠ ∅ := Set.nonempty_Iic.ne_empty
example {u : ℝ} : Set.Ioi u ≠ ∅ := Set.nonempty_Ioi.ne_empty
example {u : ℝ} : Set.Iio u ≠ ∅ := Set.nonempty_Iio.ne_empty
-- Singleton / univ / composite `≠ ∅` are not matched.
#guard firingLemmas (.neEmpty (singT "a")) == #[]
#guard firingLemmas (.neEmpty (.union (de .Icc "a" "b") (de .Icc "b" "c"))) == #[]

/-! ## Generated condition directions, pinned entry by entry

Distinct atom names on each side so a flipped condition direction changes the
pinned string.  These assert on the conditions the TABLE generates (via `suggest`),
not on hand-written hypotheses, so inverting any matcher's condition directions in
`Suggest.lean` fails here even though the lemma-verifying `example`s above still
compile. -/

/-- Pinned condition descriptions of the single suggestion firing on `s`. -/
private def condDescs (s : Shape) : Array String :=
  ((suggest s (graphOf [] []))[0]!).conds.map (·.1.desc)

-- monoSame (`Ixx p₁ q₁ ⊆ Ixx p₂ q₂` needs the OUTER interval to be wider:
-- `p₂ ≤ p₁` and `q₁ ≤ q₂`), all four kinds.
#guard condDescs (.subset (de .Icc "p₁" "q₁") (de .Icc "p₂" "q₂")) == #["p₂ ≤ p₁", "q₁ ≤ q₂"]
#guard condDescs (.subset (de .Ico "p₁" "q₁") (de .Ico "p₂" "q₂")) == #["p₂ ≤ p₁", "q₁ ≤ q₂"]
#guard condDescs (.subset (de .Ioc "p₁" "q₁") (de .Ioc "p₂" "q₂")) == #["p₂ ≤ p₁", "q₁ ≤ q₂"]
#guard condDescs (.subset (de .Ioo "p₁" "q₁") (de .Ioo "p₂" "q₂")) == #["p₂ ≤ p₁", "q₁ ≤ q₂"]

-- monoSame semantic readiness: correct-direction facts make it ready …
#guard (suggest (.subset (de .Icc "p₁" "q₁") (de .Icc "p₂" "q₂"))
    (graphOf ["p₁", "q₁", "p₂", "q₂"] [fLe "p₂" "p₁", fLe "q₁" "q₂"]))[0]!.ready == true
-- … and inverted-direction facts must NOT (this is the mutation that survived).
#guard (suggest (.subset (de .Ioc "p₁" "q₁") (de .Ioc "p₂" "q₂"))
    (graphOf ["p₁", "q₁", "p₂", "q₂"] [fLt "p₁" "p₂", fLt "q₂" "q₁"]))[0]!.ready == false
-- Half-flipped facts leave exactly the flipped half missing.
#guard ((suggest (.subset (de .Ioo "p₁" "q₁") (de .Ioo "p₂" "q₂"))
    (graphOf ["p₁", "q₁", "p₂", "q₂"] [fLe "p₂" "p₁", fLt "q₂" "q₁"]))[0]!.missing.map
    (·.desc)) == #["q₁ ≤ q₂"]

-- unionJoinSame cond directions and order, all three kinds (`p ≤ q` then `q ≤ r`).
#guard condDescs (.eq (.union (de .Ioc "p" "q") (de .Ioc "q" "r")) (de .Ioc "p" "r"))
    == #["p ≤ q", "q ≤ r"]
#guard condDescs (.eq (.union (de .Ico "p" "q") (de .Ico "q" "r")) (de .Ico "p" "r"))
    == #["p ≤ q", "q ≤ r"]
#guard condDescs (.eq (.union (de .Icc "p" "q") (de .Icc "q" "r")) (de .Icc "p" "r"))
    == #["p ≤ q", "q ≤ r"]

-- unionJoinRayRight: cond compares bar-lo against bar-hi (`p` vs `q`), strict only
-- for the Ioo ∪ Ici entry.
#guard condDescs (.eq (.union (de .Ioo "p" "q") (rayLo .Ici "q")) (rayLo .Ioi "p"))
    == #["p < q"]
#guard condDescs (.eq (.union (de .Ico "p" "q") (rayLo .Ici "q")) (rayLo .Ici "p"))
    == #["p ≤ q"]
#guard condDescs (.eq (.union (de .Ioc "p" "q") (rayLo .Ioi "q")) (rayLo .Ioi "p"))
    == #["p ≤ q"]
#guard condDescs (.eq (.union (de .Icc "p" "q") (rayLo .Ioi "q")) (rayLo .Ici "p"))
    == #["p ≤ q"]

-- unionJoinRayLeft: ray endpoint `p` ≤ bar-hi `q`, all three entries.
#guard condDescs (.eq (.union (rayHi .Iio "p") (de .Ico "p" "q")) (rayHi .Iio "q"))
    == #["p ≤ q"]
#guard condDescs (.eq (.union (rayHi .Iic "p") (de .Ioc "p" "q")) (rayHi .Iic "q"))
    == #["p ≤ q"]
#guard condDescs (.eq (.union (rayHi .Iio "p") (de .Icc "p" "q")) (rayHi .Iic "q"))
    == #["p ≤ q"]
-- unionJoinRayLeft semantic readiness: reversed fact must not satisfy it.
#guard (suggest (.eq (.union (rayHi .Iio "p") (de .Ico "p" "q")) (rayHi .Iio "q"))
    (graphOf ["p", "q"] [fLt "q" "p"]))[0]!.ready == false
#guard (suggest (.eq (.union (rayHi .Iio "p") (de .Ico "p" "q")) (rayHi .Iio "q"))
    (graphOf ["p", "q"] [fLe "p" "q"]))[0]!.ready == true

-- unionUniv: the high-ray endpoint `q` must sit at or below the low-ray endpoint
-- `p` (`q ≤ p` / `q < p`), and the no-hypothesis entry generates no conditions.
#guard condDescs (.eq (.union (rayHi .Iic "p") (rayLo .Ici "p")) univT) == #[]
#guard condDescs (.eq (.union (rayHi .Iic "p") (rayLo .Ioi "q")) univT) == #["q ≤ p"]
#guard condDescs (.eq (.union (rayHi .Iio "p") (rayLo .Ici "q")) univT) == #["q ≤ p"]
#guard condDescs (.eq (.union (rayHi .Iio "p") (rayLo .Ioi "q")) univT) == #["q < p"]
-- unionUniv semantic readiness: `p ≤ q` (rays pointing apart, gap in the middle)
-- must NOT make `Iio p ∪ Ioi q = univ` ready; `q < p` must.
#guard (suggest (.eq (.union (rayHi .Iio "p") (rayLo .Ioi "q")) univT)
    (graphOf ["p", "q"] [fLt "p" "q"]))[0]!.ready == false
#guard (suggest (.eq (.union (rayHi .Iio "p") (rayLo .Ioi "q")) univT)
    (graphOf ["p", "q"] [fLt "q" "p"]))[0]!.ready == true

-- memRay: bound on the correct side of `x`, with per-kind strictness.
#guard condDescs (.mem (ep "x") (rayLo .Ici "p")) == #["p ≤ x"]
#guard condDescs (.mem (ep "x") (rayLo .Ioi "p")) == #["p < x"]
#guard condDescs (.mem (ep "x") (rayHi .Iic "q")) == #["x ≤ q"]
#guard condDescs (.mem (ep "x") (rayHi .Iio "q")) == #["x < q"]
-- memRay semantic readiness: `x < p` must not satisfy `x ∈ Ioi p`.
#guard (suggest (.mem (ep "x") (rayLo .Ioi "p"))
    (graphOf ["x", "p"] [fLt "x" "p"]))[0]!.ready == false
#guard (suggest (.mem (ep "x") (rayLo .Ioi "p"))
    (graphOf ["x", "p"] [fLt "p" "x"]))[0]!.ready == true

-- memDe closed kind for completeness (open kinds pinned above at ## 30–37).
#guard condDescs (.mem (ep "x") (de .Icc "p" "q")) == #["p ≤ x", "x ≤ q"]
#guard condDescs (.mem (ep "x") (de .Ioo "p" "q")) == #["p < x", "x < q"]

-- Singleton membership: the element comes first (`x = p`).
#guard condDescs (.mem (ep "x") (singT "p")) == #["x = p"]

-- emptyOf: remaining two kinds (Icc/Ioo pinned at ## 40–43).
#guard condDescs (.eq (de .Ico "p" "q") emptyT) == #["q ≤ p"]
#guard condDescs (.eq (de .Ioc "p" "q") emptyT) == #["q ≤ p"]
-- emptyOf semantic readiness: `p < q` (non-empty interval) must not satisfy it.
#guard (suggest (.eq (de .Ioc "p" "q") emptyT)
    (graphOf ["p", "q"] [fLt "p" "q"]))[0]!.ready == false
#guard (suggest (.eq (de .Ioc "p" "q") emptyT)
    (graphOf ["p", "q"] [fLe "q" "p"]))[0]!.ready == true

-- emptyIff (suggestion [1] on `Ixx p q = ∅` shapes) generates the same reversed
-- conditions as emptyOf: strict `q < p` for Icc, `q ≤ p` for the other kinds.
#guard (suggest (.eq (de .Icc "p" "q") emptyT) (graphOf [] []))[1]!.lemmaName
    == "Set.Icc_eq_empty_iff"
#guard ((suggest (.eq (de .Icc "p" "q") emptyT) (graphOf [] []))[1]!.conds.map (·.1.desc))
    == #["q < p"]
#guard ((suggest (.eq (de .Ico "p" "q") emptyT) (graphOf [] []))[1]!.conds.map (·.1.desc))
    == #["q ≤ p"]
#guard ((suggest (.eq (de .Ioc "p" "q") emptyT) (graphOf [] []))[1]!.conds.map (·.1.desc))
    == #["q ≤ p"]
#guard ((suggest (.eq (de .Ioo "p" "q") emptyT) (graphOf [] []))[1]!.conds.map (·.1.desc))
    == #["q ≤ p"]

-- emptyOfRev (`∅ = Ixx p q`): same reversed conditions, `.symm`-wrapped tactic.
#guard condDescs (.eq emptyT (de .Icc "p" "q")) == #["q < p"]
#guard condDescs (.eq emptyT (de .Ico "p" "q")) == #["q ≤ p"]
#guard condDescs (.eq emptyT (de .Ioc "p" "q")) == #["q ≤ p"]
#guard condDescs (.eq emptyT (de .Ioo "p" "q")) == #["q ≤ p"]
#guard (suggest (.eq emptyT (de .Icc "p" "q")) (graphOf [] []))[0]!.tactic
    == "refine (Set.Icc_eq_empty (not_le.mpr ?_)).symm"
-- emptyOfRev semantic readiness: forward fact `p < q` must NOT satisfy it.
#guard (suggest (.eq emptyT (de .Ioc "p" "q"))
    (graphOf ["p", "q"] [fLt "p" "q"]))[0]!.ready == false
#guard (suggest (.eq emptyT (de .Ioc "p" "q"))
    (graphOf ["p", "q"] [fLe "q" "p"]))[0]!.ready == true

-- nonemptyDe: FORWARD conditions (`p ≤ q` / `p < q`) — the mirror image of the
-- emptiness family — with per-kind strictness.
#guard condDescs (.nonempty (de .Icc "p" "q")) == #["p ≤ q"]
#guard condDescs (.nonempty (de .Ico "p" "q")) == #["p < q"]
#guard condDescs (.nonempty (de .Ioc "p" "q")) == #["p < q"]
#guard condDescs (.nonempty (de .Ioo "p" "q")) == #["p < q"]
#guard (suggest (.nonempty (de .Ioc "p" "q")) (graphOf [] []))[0]!.tactic
    == "refine Set.nonempty_Ioc.mpr ?_"
-- nonemptyDe semantic readiness: reversed fact must NOT satisfy it …
#guard (suggest (.nonempty (de .Ioc "p" "q"))
    (graphOf ["p", "q"] [fLt "q" "p"]))[0]!.ready == false
#guard (suggest (.nonempty (de .Ioc "p" "q"))
    (graphOf ["p", "q"] [fLt "p" "q"]))[0]!.ready == true
-- … and non-strict `p ≤ q` is NOT enough for the strict kinds, but is for Icc.
#guard (suggest (.nonempty (de .Ioc "p" "q"))
    (graphOf ["p", "q"] [fLe "p" "q"]))[0]!.ready == false
#guard (suggest (.nonempty (de .Icc "p" "q"))
    (graphOf ["p", "q"] [fLe "p" "q"]))[0]!.ready == true

-- nonemptyRay: no conditions at all (always-ready).
#guard condDescs (.nonempty (rayLo .Ici "p")) == #[]
#guard condDescs (.nonempty (rayHi .Iio "q")) == #[]
#guard (suggest (.nonempty (rayLo .Ioi "p")) (graphOf [] []))[0]!.ready == true

-- neEmptyOf: forward conditions with per-kind strictness; rays condition-free.
#guard condDescs (.neEmpty (de .Icc "p" "q")) == #["p ≤ q"]
#guard condDescs (.neEmpty (de .Ico "p" "q")) == #["p < q"]
#guard condDescs (.neEmpty (de .Ioc "p" "q")) == #["p < q"]
#guard condDescs (.neEmpty (de .Ioo "p" "q")) == #["p < q"]
#guard condDescs (.neEmpty (rayLo .Ici "p")) == #[]
#guard (suggest (.neEmpty (de .Ioo "p" "q")) (graphOf [] []))[0]!.tactic
    == "refine (Set.nonempty_Ioo.mpr ?_).ne_empty"
#guard (suggest (.neEmpty (rayLo .Ioi "p")) (graphOf [] []))[0]!.tactic
    == "exact Set.nonempty_Ioi.ne_empty"
-- neEmptyOf semantic readiness: reversed fact must NOT satisfy it.
#guard (suggest (.neEmpty (de .Ico "p" "q"))
    (graphOf ["p", "q"] [fLt "q" "p"]))[0]!.ready == false
#guard (suggest (.neEmpty (de .Ico "p" "q"))
    (graphOf ["p", "q"] [fLt "p" "q"]))[0]!.ready == true

/-! ## Side-condition readiness reporting -/

private def joinShape : Shape :=
  .eq (.union (de .Ioc "a" "b") (de .Ioc "b" "c")) (de .Ioc "a" "c")

-- Both hypotheses present: ready.
#guard (suggest joinShape (graphOf ["a", "b", "c"] [fLe "a" "b", fLe "b" "c"]))[0]!.ready
    == true
-- No hypotheses: both conditions reported missing.
#guard ((suggest joinShape (graphOf ["a", "b", "c"] []))[0]!.missing.map (·.desc))
    == #["a ≤ b", "b ≤ c"]
-- One hypothesis: exactly the other is missing.
#guard ((suggest joinShape (graphOf ["a", "b", "c"] [fLe "a" "b"]))[0]!.missing.map (·.desc))
    == #["b ≤ c"]
-- Transitively derived facts count as ready: a ≤ m ≤ b makes a ≤ b ready.
#guard (suggest (.subset (rayHi .Iic "a") (rayHi .Iic "b"))
    (graphOf ["a", "b", "m"] [fLe "a" "m", fLe "m" "b"]))[0]!.ready == true
-- Literal endpoints are ready with no hypotheses at all (the motivating demo).
private def joinLit : Shape :=
  .eq (.union (dev .Ioc "1" 1 "2" 2) (dev .Ioc "2" 2 "3" 3)) (dev .Ioc "1" 1 "3" 3)
#guard (suggest joinLit (joinLit.orderGraph #[]))[0]!.ready == true
-- Strict conditions need strict facts: a ≤ b is NOT enough for Ioo ∪ Ici = Ioi.
private def strictShape : Shape :=
  .eq (.union (de .Ioo "a" "b") (rayLo .Ici "b")) (rayLo .Ioi "a")
#guard (suggest strictShape (graphOf ["a", "b"] [fLe "a" "b"]))[0]!.ready == false
#guard (suggest strictShape (graphOf ["a", "b"] [fLt "a" "b"]))[0]!.ready == true
-- The suggested tactic text is the refine skeleton with placeholders.
#guard (suggest joinShape (graphOf ["a", "b", "c"] []))[0]!.tactic
    == "refine Set.Ioc_union_Ioc_eq_Ioc ?_ ?_"
#guard (suggest (.subset (de .Ioo "a" "b") (de .Icc "a" "b")) (graphOf ["a", "b"] []))[0]!.tactic
    == "exact Set.Ioo_subset_Icc_self"

/-! ## Fallbacks fire exactly when no table entry applies -/

-- Mixed-kind subset with different endpoints: no entry, one subset fallback.
private def noHit : Shape := .subset (de .Icc "a" "b") (de .Ioo "c" "d")
#guard (suggest noHit (graphOf ["a", "b", "c", "d"] [])).map (·.isFallback) == #[true]
#guard (suggest noHit (graphOf [] []))[0]!.tactic
    == "simp [Set.subset_def]; intro x hx; constructor <;> linarith"
#guard (suggest noHit (graphOf [] []))[0]!.lemmaName == "(fallback)"
-- Unmatched equality: two fallbacks.
#guard ((suggest (.eq (de .Icc "a" "b") (de .Ico "a" "b")) (graphOf [] [])).map
    (·.isFallback)) == #[true, true]
-- Membership in a union: no unfolding entry, membership fallback.
#guard ((suggest (.mem (ep "x") (.union (de .Icc "a" "b") (de .Icc "c" "d")))
    (graphOf [] [])).map (·.tactic)) == #["constructor <;> simp_all"]
-- A bare recognized term needs no suggestion: empty, not fallback-spammed.
#guard suggest (.term (de .Icc "a" "b")) (graphOf [] []) == #[]
-- When a real entry applies, fallbacks are not mixed in.
#guard (suggest joinShape (graphOf [] [])).map (·.isFallback) == #[false]
-- Nonempty/≠∅ shapes outside the table get their dedicated fallbacks.
#guard ((suggest (.nonempty univT) (graphOf [] [])).map (·.tactic))
    == #["simp [Set.nonempty_iff_ne_empty]"]
#guard ((suggest (.neEmpty (singT "a")) (graphOf [] [])).map (·.isFallback)) == #[true]
#guard ((suggest (.neEmpty (singT "a")) (graphOf [] [])).map (·.tactic))
    == #["rw [← Set.nonempty_iff_ne_empty]; simp_all"]

/-! ## Integration: recognition → suggestion (via elaborated goals) -/

#assert_suggests ∀ (p q r : ℝ), Set.Ioc p q ∪ Set.Ioc q r = Set.Ioc p r
  => "Set.Ioc_union_Ioc_eq_Ioc"
#assert_suggests (Set.Ioc (1:ℝ) 2 ∪ Set.Ioc 2 3 = Set.Ioc 1 3)
  => "Set.Ioc_union_Ioc_eq_Ioc"
#assert_suggests ∀ (p q : ℝ), Set.Ioo p q ⊆ Set.Icc p q => "Set.Ioo_subset_Icc_self"
#assert_suggests ((3:ℝ) ∈ Set.Icc 1 4) => "Set.mem_Icc"
#assert_suggests ∀ (p q : ℝ), Set.Iic p ∪ Set.Ioi q = Set.univ => "Set.Iic_union_Ioi_of_le"
#assert_suggests ∀ (p : ℝ), Set.Icc p p = {p} => "Set.Icc_self"
#assert_suggests ∀ (p q : ℝ), Set.Ioo p q = (∅ : Set ℝ)
  => "Set.Ioo_eq_empty, Set.Ioo_eq_empty_iff"
#assert_suggests ∀ (p q : ℝ), (Set.Ioc p q).Nonempty => "Set.nonempty_Ioc"
#assert_suggests ∀ (p : ℝ), (Set.Ici p).Nonempty => "Set.nonempty_Ici"
#assert_suggests ∀ (p q : ℝ), Set.Icc p q ≠ ∅ => "Set.Nonempty.ne_empty"
#assert_suggests ∀ (p q : ℝ), ¬(Set.Ioo p q = ∅) => "Set.Nonempty.ne_empty"
#assert_suggests ∀ (p q : ℝ), (∅ : Set ℝ) = Set.Ico p q => "Eq.symm"
-- The set-builder payoff: a textbook goal lights up the whole pipeline.
#assert_suggests ({x : ℝ | 0 ≤ x ∧ x < 1} ⊆ Set.Icc 0 1) => "Set.Ico_subset_Icc_self"
#assert_suggests ∀ (p q : ℝ), ({x | p ≤ x ∧ x ≤ q}).Nonempty => "Set.nonempty_Icc"

/-! ## 62 (cont.): the mirror spelling `∅ ≠ Ixx …` fires the same entry with a
`.symm`-wrapped tactic, and each wrapped tactic term is verified below -/

#guard firingLemmas (.neEmpty (de .Icc "a" "b") true) == #["Set.Nonempty.ne_empty"]
#guard firingLemmas (.neEmpty (rayLo .Ici "a") true) == #["Set.Nonempty.ne_empty"]
#guard (suggest (.neEmpty (de .Icc "p" "q") true) (graphOf [] []))[0]!.tactic
    == "refine ((Set.nonempty_Icc.mpr ?_).ne_empty).symm"
#guard (suggest (.neEmpty (de .Ioo "p" "q") true) (graphOf [] []))[0]!.tactic
    == "refine ((Set.nonempty_Ioo.mpr ?_).ne_empty).symm"
#guard (suggest (.neEmpty (rayLo .Ici "p") true) (graphOf [] []))[0]!.tactic
    == "exact (Set.nonempty_Ici.ne_empty).symm"
-- Same forward conditions as the unreversed spelling.
#guard condDescs (.neEmpty (de .Ico "p" "q") true) == #["p < q"]
#guard condDescs (.neEmpty (de .Icc "p" "q") true) == #["p ≤ q"]
example (h : a ≤ b) : (∅ : Set α) ≠ Set.Icc a b := ((Set.nonempty_Icc.mpr h).ne_empty).symm
example (h : a < b) : (∅ : Set α) ≠ Set.Ico a b := ((Set.nonempty_Ico.mpr h).ne_empty).symm
example (h : a < b) : (∅ : Set α) ≠ Set.Ioc a b := ((Set.nonempty_Ioc.mpr h).ne_empty).symm
example {u v : ℝ} (h : u < v) : (∅ : Set ℝ) ≠ Set.Ioo u v :=
  ((Set.nonempty_Ioo.mpr h).ne_empty).symm
example : (∅ : Set α) ≠ Set.Ici a := (Set.nonempty_Ici.ne_empty).symm
example : (∅ : Set α) ≠ Set.Iic a := (Set.nonempty_Iic.ne_empty).symm
example {u : ℝ} : (∅ : Set ℝ) ≠ Set.Ioi u := (Set.nonempty_Ioi.ne_empty).symm
example {u : ℝ} : (∅ : Set ℝ) ≠ Set.Iio u := (Set.nonempty_Iio.ne_empty).symm
-- The reversed fallback (when nothing matches) starts by flipping the `≠`.
#guard ((suggest (.neEmpty (singT "a") true) (graphOf [] [])).map (·.tactic))
    == #["apply Ne.symm; rw [← Set.nonempty_iff_ne_empty]; simp_all"]

/-! ## Instance needs, pinned entry by entry

Each pinned array mirrors the pinned Mathlib statement's typeclass context
(grepped from `Mathlib/Order/Interval/Set/Basic.lean` / `LinearOrder.lean`):
`LinearOrder` for union joins and whole-line covers, `DenselyOrdered` for
`nonempty_Ioo` / `Ioo_eq_empty_iff`, `NoMaxOrder`/`NoMinOrder` for
`nonempty_Ioi`/`nonempty_Iio` (also inside `Set.Nonempty.ne_empty` compositions),
`PartialOrder` for `Icc_self`, `Lattice`/`LinearOrder` for the intersection
rewrites, nothing beyond `Preorder` for the rest. -/

private def needsOf (s : Shape) : Array (Array InstanceNeed) :=
  SuggestTable.table.filterMap fun e => (e.matcher s).map (·.needs)

#guard needsOf (.eq (.union (de .Ioc "p" "q") (de .Ioc "q" "r")) (de .Ioc "p" "r"))
    == #[#[.linearOrder]]
#guard needsOf (.eq (.union (de .Ioo "p" "q") (rayLo .Ici "q")) (rayLo .Ioi "p"))
    == #[#[.linearOrder]]
#guard needsOf (.eq (.union (rayHi .Iio "p") (de .Ico "p" "q")) (rayHi .Iio "q"))
    == #[#[.linearOrder]]
#guard needsOf (.eq (.union (rayHi .Iic "p") (rayLo .Ici "p")) univT) == #[#[.linearOrder]]
#guard needsOf (.subset (de .Icc "p₁" "q₁") (de .Icc "p₂" "q₂")) == #[#[]]
#guard needsOf (.subset (rayHi .Iio "p") (rayHi .Iio "q")) == #[#[]]
#guard needsOf (.subset (de .Ioo "p" "q") (de .Icc "p" "q")) == #[#[]]
#guard needsOf (.mem (ep "x") (de .Icc "p" "q")) == #[#[]]
#guard needsOf (.eq (de .Icc "p" "q") emptyT) == #[#[], #[]]
#guard needsOf (.eq (de .Ioo "p" "q") emptyT) == #[#[], #[.denselyOrdered]]
#guard needsOf (.eq emptyT (de .Ioo "p" "q")) == #[#[]]
#guard needsOf (.nonempty (de .Icc "p" "q")) == #[#[]]
#guard needsOf (.nonempty (de .Ioo "p" "q")) == #[#[.denselyOrdered]]
#guard needsOf (.nonempty (rayLo .Ici "p")) == #[#[]]
#guard needsOf (.nonempty (rayLo .Ioi "p")) == #[#[.noMaxOrder]]
#guard needsOf (.nonempty (rayHi .Iio "q")) == #[#[.noMinOrder]]
#guard needsOf (.neEmpty (de .Ioo "p" "q")) == #[#[.denselyOrdered]]
#guard needsOf (.neEmpty (rayLo .Ioi "p")) == #[#[.noMaxOrder]]
#guard needsOf (.neEmpty (rayHi .Iio "q") true) == #[#[.noMinOrder]]
#guard needsOf (.eq (de .Icc "p" "p") (singT "p")) == #[#[.partialOrder]]
#guard needsOf (.term (.inter (de .Icc "p" "q") (de .Icc "r" "s"))) == #[#[.lattice]]
#guard needsOf (.term (.inter (de .Ico "p" "q") (de .Ico "r" "s"))) == #[#[.linearOrder]]

/-! ## Instance gating: unmet needs suppress condition-free entries and mark the
rest (never ready), mirroring the confirmed false-ALL-READY bugs over ℕ / ℝ × ℝ -/

private def gABlt := graphOf ["a", "b"] [fLt "a" "b"]

-- `(Iio q).Nonempty` without `NoMinOrder`: the condition-free `exact` suggestion
-- would assert a possibly-false goal — suppressed, fallback offered, note recorded.
#guard ((suggest (.nonempty (rayHi .Iio "q")) (graphOf ["q"] []) { noMinOrder := false }).map
    (·.isFallback)) == #[true]
#guard (suggestFull (.nonempty (rayHi .Iio "q")) (graphOf ["q"] []) { noMinOrder := false }).2
    == #["Set.nonempty_Iio suppressed: needs NoMinOrder (no instance for this type)"]
-- With the instance, unchanged.
#guard (suggest (.nonempty (rayHi .Iio "q")) (graphOf ["q"] []))[0]!.ready == true
-- `Iic p ∪ Ici p = univ` without `LinearOrder` (e.g. over ℝ × ℝ): suppressed.
#guard (suggestFull (.eq (.union (rayHi .Iic "p") (rayLo .Ici "p")) univT)
    (graphOf ["p"] []) { linearOrder := false }).2
    == #["Set.Iic_union_Ici suppressed: needs LinearOrder (no instance for this type)"]
-- `(Ioo a b).Nonempty` without `DenselyOrdered` (e.g. over ℕ): kept, marked, and
-- NOT ready even though the order condition is a known fact.
#guard (suggest (.nonempty (de .Ioo "a" "b")) gABlt { denselyOrdered := false })[0]!.ready
    == false
#guard (suggest (.nonempty (de .Ioo "a" "b")) gABlt
    { denselyOrdered := false })[0]!.missingInsts == #["DenselyOrdered"]
#guard (suggest (.nonempty (de .Ioo "a" "b")) gABlt { denselyOrdered := false })[0]!.report
    == "Set.nonempty_Ioo [a < b (ready)] [missing instance: DenselyOrdered] — \
        refine Set.nonempty_Ioo.mpr ?_"
#guard (suggest (.nonempty (de .Ioo "a" "b")) gABlt)[0]!.ready == true
-- Union join without `LinearOrder`: kept with marker, not ready despite both facts.
#guard (suggest joinShape (graphOf ["a", "b", "c"] [fLe "a" "b", fLe "b" "c"])
    { linearOrder := false })[0]!.ready == false
#guard (suggest joinShape (graphOf ["a", "b", "c"] [fLe "a" "b", fLe "b" "c"])
    { linearOrder := false })[0]!.missingInsts == #["LinearOrder"]
-- `Icc a a = {a}` without `PartialOrder`: condition-free → suppressed → fallbacks.
#guard ((suggest (.eq (de .Icc "a" "a") (singT "a")) (graphOf [] [])
    { partialOrder := false }).map (·.isFallback)) == #[true, true]
-- `Icc ∩ Icc` rewrite without `Lattice`: suppressed; bare terms get no fallback.
#guard suggest (.term (.inter (de .Icc "a" "b") (de .Icc "c" "d"))) (graphOf [] [])
    { lattice := false } == #[]
#guard (suggestFull (.term (.inter (de .Icc "a" "b") (de .Icc "c" "d"))) (graphOf [] [])
    { lattice := false }).2
    == #["Set.Icc_inter_Icc suppressed: needs Lattice (no instance for this type)"]
-- No needs are violated when everything is available: nothing suppressed.
#guard (suggestFull joinShape (graphOf [] [])).2 == #[]

/-! ## Instance gating, end to end (the confirmed false-`ALL-READY` repros)

Each pin below elaborates the *actual* repro statement over the *actual* type and
runs the full pipeline (`analyzeWithLCtx?`), exactly like the command and the
panel.  Before the fix every one of these showed a green `ALL-READY` suggestion
for a false (or non-elaborating) statement. -/

-- `(Set.Iio (0:ℕ)).Nonempty` is FALSE (`Iio 0 = ∅` over ℕ); the condition-free
-- `exact Set.nonempty_Iio` is suppressed (ℕ has no `NoMinOrder`) with a note, and
-- only the honest fallback remains.
#assert_reports (Set.Iio (0:ℕ)).Nonempty
  => "(fallback) — simp [Set.nonempty_iff_ne_empty] [ALL-READY]"
#assert_suppressed (Set.Iio (0:ℕ)).Nonempty
  => "Set.nonempty_Iio suppressed: needs NoMinOrder (no instance for this type)"
example : ¬ (Set.Iio (0:ℕ)).Nonempty := by simp  -- the statement really is false
-- Over ℝ (which has `NoMinOrder`) the same statement keeps its ready suggestion.
#assert_reports (Set.Iio (0:ℝ)).Nonempty
  => "Set.nonempty_Iio — exact Set.nonempty_Iio [ALL-READY]"
#assert_suppressed (Set.Iio (0:ℝ)).Nonempty => "-"

-- `Iic p ∪ Ici p = univ` over `ℝ × ℝ` is FALSE (`(1,-1)` is in neither side);
-- `Set.Iic_union_Ici` needs `LinearOrder`, so it is suppressed.
#assert_reports (Set.Iic ((0,0) : ℝ × ℝ) ∪ Set.Ici ((0,0) : ℝ × ℝ) = Set.univ)
  => "(fallback) — constructor <;> simp_all [ALL-READY] | (fallback) — ext x; \
      simp only [Set.mem_union, Set.mem_inter_iff]; constructor <;> (intro h; \
      simp_all) <;> constructor <;> linarith [ALL-READY]"
#assert_suppressed (Set.Iic ((0,0) : ℝ × ℝ) ∪ Set.Ici ((0,0) : ℝ × ℝ) = Set.univ)
  => "Set.Iic_union_Ici suppressed: needs LinearOrder (no instance for this type)"
example : ¬ (Set.Iic ((0,0) : ℝ × ℝ) ∪ Set.Ici ((0,0) : ℝ × ℝ) = Set.univ) := by
  intro h
  have h1 : ((1,-1) : ℝ × ℝ) ∈ Set.Iic ((0,0) : ℝ × ℝ) ∪ Set.Ici ((0,0) : ℝ × ℝ) :=
    h ▸ Set.mem_univ _
  rcases h1 with h1 | h1
  · rw [Set.mem_Iic, Prod.mk_le_mk] at h1; exact absurd h1.1 (by norm_num)
  · rw [Set.mem_Ici, Prod.mk_le_mk] at h1; exact absurd h1.2 (by norm_num)

-- `(Set.Ioo (0:ℕ) 2).Nonempty` is TRUE but `Set.nonempty_Ioo` needs
-- `DenselyOrdered`: the (order-condition-carrying) match is kept, marked, and
-- never `ALL-READY`.
#assert_reports (Set.Ioo (0:ℕ) 2).Nonempty
  => "Set.nonempty_Ioo [0 < 2 (ready)] [missing instance: DenselyOrdered] — \
      refine Set.nonempty_Ioo.mpr ?_"
-- Over ℝ, no marker and fully ready.
#assert_reports (Set.Ioo (0:ℝ) 2).Nonempty
  => "Set.nonempty_Ioo [0 < 2 (ready)] — refine Set.nonempty_Ioo.mpr ?_ [ALL-READY]"

-- The `Ioc` union join over `ℝ × ℝ` (no `LinearOrder`): conditions can be ready
-- from the harvested binder facts, yet the missing instance keeps it un-`ALL-READY`.
#assert_reports ∀ (a b c : ℝ × ℝ), a ≤ b → b ≤ c →
    Set.Ioc a b ∪ Set.Ioc b c = Set.Ioc a c
  => "Set.Ioc_union_Ioc_eq_Ioc [a ≤ b (ready); b ≤ c (ready)] \
      [missing instance: LinearOrder] — refine Set.Ioc_union_Ioc_eq_Ioc ?_ ?_"

-- ℕ has `NoMaxOrder`: `(Set.Ioi (0:ℕ)).Nonempty` genuinely always holds and stays
-- ready (gating must not overshoot on discrete types).
#assert_reports (Set.Ioi (0:ℕ)).Nonempty
  => "Set.nonempty_Ioi — exact Set.nonempty_Ioi [ALL-READY]"

/-! ## Division literals over ℕ, end to end (the `1/3 < 1/2` repro)

`Set.Ico (1/3:ℕ) (1/2:ℕ)` is empty (`(1/3 : ℕ) = 0 = (1/2 : ℕ)`); the endpoints
must stay symbolic, so the strict condition is *missing* — before the fix the
fabricated rational values made it `ready`. -/

#assert_reports (Set.Ico (1/3:ℕ) (1/2:ℕ)).Nonempty
  => "Set.nonempty_Ico [1 / 3 < 1 / 2 (missing)] — refine Set.nonempty_Ico.mpr ?_"
example : Set.Ico ((1:ℕ)/3) (1/2) = ∅ := by norm_num  -- the set really is empty

/-! ## Transitive chaining through non-endpoint atoms, end to end

The confirmed repro: `a ≤ b → b ≤ c` fully determines `a ∈ Set.Icc a c` although
`b` is not an interval endpoint.  The order graph must chain through `b` (an
auxiliary node), leaving no unknown pairs and both conditions ready. -/

#assert_reports ∀ (a b c : ℝ), a ≤ b → b ≤ c → a ∈ Set.Icc a c
  => "Set.mem_Icc [a ≤ a (ready); a ≤ c (ready)] — \
      refine Set.mem_Icc.mpr ⟨?_, ?_⟩ [ALL-READY]"
#assert_unknown_pairs ∀ (a b c : ℝ), a ≤ b → b ≤ c → a ∈ Set.Icc a c => "-"
example (a b c : ℝ) (h₁ : a ≤ b) (h₂ : b ≤ c) : a ∈ Set.Icc a c :=
  Set.mem_Icc.mpr ⟨le_refl a, le_trans h₁ h₂⟩

/-! ## The table is as large as advertised -/

#guard SuggestTable.table.size == 62
#guard (SuggestTable.table.map (·.lemmaName)).toList.eraseDups.length == 62

end IntervalInspectorTests
