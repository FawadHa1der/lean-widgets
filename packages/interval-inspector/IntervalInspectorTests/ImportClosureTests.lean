import IntervalInspector

/-! # Import-closure tests

This file deliberately imports **only** `IntervalInspector` — the exact setup the
README's usage section shows.  Every tactic and every lemma constant mentioned in a
fallback suggestion (`IntervalInspector/Suggest.lean`, `fallbackSuggestions`) must
be available in this closure.  Before the fix, clicking a fallback containing
`linarith` in a file importing only the package failed with `unknown tactic` — the
confirmed repro is the first example below. -/

namespace IntervalInspectorTests.ImportClosure

-- The confirmed repro: `linarith` must be a known, working tactic here.
example (x y : ℚ) (h : x < y) : x ≤ y := by linarith
example {α : Type*} [Field α] [LinearOrder α] [IsStrictOrderedRing α]
    (x y : α) (h : x < y) : x ≤ y := by linarith

-- The subset-fallback script closing a real inclusion goal (near-verbatim: the
-- membership hypothesis arrives curried, so the `intro` binds two hypotheses).
example {a b c d : ℚ} (h₁ : c < a) (h₂ : b < d) : Set.Icc a b ⊆ Set.Ioo c d := by
  simp [Set.subset_def]; intro x hx₁ hx₂; constructor <;> linarith

-- The other tactics the fallback strings mention (`constructor`, `simp_all`,
-- `ext`, `simp only`, `intro`, `rw`, `apply`) are available and work too.
example (p q : Prop) (hp : p) (hq : q) : p ∧ q := by constructor <;> simp_all
example {s t : Set ℕ} (h : ∀ x, x ∈ s ↔ x ∈ t) : s = t := by
  ext x; simp only [h]
example {a b : ℚ} (h : (Set.Icc a b).Nonempty) : Set.Icc a b ≠ ∅ := by
  rw [← Set.nonempty_iff_ne_empty]; simp_all
example {a b : ℚ} (h : (Set.Icc a b).Nonempty) : (∅ : Set ℚ) ≠ Set.Icc a b := by
  apply Ne.symm; rw [← Set.nonempty_iff_ne_empty]; simp_all

-- The lemma constants the fallback strings rewrite with exist in this closure
-- (each `example` fails to elaborate if the constant is missing).
example := @Set.subset_def
example := @Set.mem_union
example := @Set.mem_inter_iff
example := @Set.nonempty_iff_ne_empty

end IntervalInspectorTests.ImportClosure
