import DistLens.Uniform
import DistLens.Verify

/-! # The uniform-constructor shim's own contract (added after the v4.35.0 port's audit)

`DistLens/Uniform.lean` claims to be Mathlib `v4.34.0`'s `PMF.uniformOfFinset`/
`PMF.uniformOfFintype` with the same statements and the same `@[simp]` attributes, and
`pmf_num` names both `_apply` lemmas explicitly.  The audit's mutations showed neither
claim was pinned on its own: deleting the `@[simp]` on `uniformOfFintype_apply` left
every test green (`pmf_num` lists the lemma), and so did deleting
`DistLens.uniformOfFinset_apply` from `pmf_num`'s list (the lemma is `@[simp]`).  Here:

* the two lemma statements and the `uniformOfFintype` definition, used by name;
* plain `simp` (no lemma arguments) on both constructors — needs the attributes — with
  negative controls showing the same `simp` fails once the attribute is erased;
* `pmf_num` with each attribute erased — needs the explicit entries in its simp set.

Imports only the shim and the tactic (no Mathlib `Uniform` module: that interaction is
`MathlibUniformTests`).
-/

namespace DistLensTests.Uniform

open scoped ENNReal

/-! ## Statements, used by name -/

open scoped Classical in
example {α : Type*} (s : Finset α) (hs : s.Nonempty) (a : α) :
    DistLens.uniformOfFinset s hs a = if a ∈ s then (s.card : ℝ≥0∞)⁻¹ else 0 :=
  DistLens.uniformOfFinset_apply hs a

example {α : Type*} [Fintype α] [Nonempty α] (a : α) :
    DistLens.uniformOfFintype α a = (Fintype.card α : ℝ≥0∞)⁻¹ :=
  DistLens.uniformOfFintype_apply a

example : DistLens.uniformOfFintype (Fin 6) =
    DistLens.uniformOfFinset Finset.univ Finset.univ_nonempty := rfl

/-! ## The `@[simp]` attributes: plain `simp` -/

example : DistLens.uniformOfFintype (Fin 6) 0 = 6⁻¹ := by simp
example : DistLens.uniformOfFintype Bool true = 2⁻¹ := by simp
-- `Finset.insert_nonempty` states `Finset.Nonempty`, so plain `simp` (default
-- `respectTransparency.types`) can instantiate the lemma's `hs` with it; the
-- `⟨1, by simp⟩` spelling needs `pmf_num`'s scoped option (PORT-NOTES 4.35 gotcha 5).
example :
    DistLens.uniformOfFinset ({1, 2, 3} : Finset ℕ) (Finset.insert_nonempty _ _) 2 = 3⁻¹ := by
  simp
example :
    DistLens.uniformOfFinset ({1, 2, 3} : Finset ℕ) (Finset.insert_nonempty _ _) 7 = 0 := by
  simp

/-! ## Negative controls: the same `simp` without the attribute fails -/

/--
error: `simp` made no progress
-/
#guard_msgs in
attribute [-simp] DistLens.uniformOfFintype_apply in
example : DistLens.uniformOfFintype (Fin 6) 0 = 6⁻¹ := by simp

/--
error: `simp` made no progress
-/
#guard_msgs in
attribute [-simp] DistLens.uniformOfFinset_apply in
example :
    DistLens.uniformOfFinset ({1, 2, 3} : Finset ℕ) (Finset.insert_nonempty _ _) 7 = 0 := by
  simp

/-! ## `pmf_num` names both lemmas itself (works with the attributes erased) -/

attribute [-simp] DistLens.uniformOfFintype_apply in
example : (DistLens.uniformOfFintype (Fin 6)) 0 = 1/6 := by pmf_num

attribute [-simp] DistLens.uniformOfFinset_apply in
example : (DistLens.uniformOfFinset ({1, 2, 3} : Finset ℕ) ⟨1, by simp⟩) 2 = 1/3 := by
  pmf_num

attribute [-simp] DistLens.uniformOfFinset_apply in
example : (DistLens.uniformOfFinset ({1, 2, 3} : Finset ℕ) ⟨1, by simp⟩) 7 = 0 := by
  pmf_num

end DistLensTests.Uniform
