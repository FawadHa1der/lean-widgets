import DistLensTests.Helpers
import DistLens

/-! # Verified weight goal tests

Every test here **compiles** a `pmf_num` (or `ennreal_num`) proof of a
specific weight equality — exactly the goals the panels offer as
click-to-insert suggestions — proving the recipe works, not just prints.
Includes the truncated-subtraction bernoulli residue, bind/map convolutions,
stationary chain equations, and pinned *failures* on false claims.
-/

namespace DistLensTests

open PMF DistLens DistLens.Demo
open scoped ENNReal NNReal

set_option linter.deprecated false

/-! ## ennreal_num: ground ℝ≥0∞ arithmetic -/

example : (6⁻¹ + 6⁻¹ + 6⁻¹ : ℝ≥0∞) = 2⁻¹ := by ennreal_num
example : (2⁻¹ * 2⁻¹ * 2 : ℝ≥0∞) = 2⁻¹ := by ennreal_num
example : (1 - 2/3 : ℝ≥0∞) = 1/3 := by ennreal_num
example : (3/4 + 1/4 : ℝ≥0∞) = 1 := by ennreal_num
example : ((1/2) ^ 2 * 2 : ℝ≥0∞) = 1/2 := by ennreal_num
example : (0 : ℝ≥0∞) = 0 := by ennreal_num

/-! ## Uniform weights -/

example : (uniformOfFintype (Fin 6)) 0 = 1/6 := by pmf_num
example : (uniformOfFintype (Fin 6)) 5 = 6⁻¹ := by pmf_num
example : (uniformOfFintype (Fin 9)) 7 = 1/9 := by pmf_num
example : (uniformOfFintype Bool) true = 1/2 := by pmf_num
example : (uniformOfFinset ({1, 2, 3} : Finset ℕ) ⟨1, by simp⟩) 2 = 1/3 := by
  pmf_num
example : (uniformOfFinset ({1, 2, 3} : Finset ℕ) ⟨1, by simp⟩) 7 = 0 := by
  pmf_num

/-! ## pure -/

example : (PMF.pure (3 : Fin 6)) 3 = 1 := by pmf_num
example : (PMF.pure (3 : Fin 6)) 0 = 0 := by pmf_num
example : (PMF.pure (5 : ℕ)) 5 = 1 := by pmf_num

/-! ## bernoulli — including the 1 − p residue at false -/

example : biasedCoin true = 2/3 := by unfold biasedCoin; pmf_num
example : biasedCoin false = 1/3 := by unfold biasedCoin; pmf_num
example : (bernoulli (1/2) (by norm_num)) true = 1/2 := by pmf_num

/-! ## binomial -/

example : twoFlips 0 = 1/4 := by unfold twoFlips; pmf_num
example : twoFlips 1 = 1/2 := by unfold twoFlips; pmf_num
example : twoFlips 2 = 1/4 := by unfold twoFlips; pmf_num
example : (binomial (1/3) (by norm_num [div_le_one]) 3) 0 = 8/27 := by pmf_num

/-! ## bind / map -/

example : twoDice 5 = 1/6 := by unfold twoDice die; pmf_num
example : twoDice 0 = 1/36 := by unfold twoDice die; pmf_num
example : twoDice 10 = 1/36 := by unfold twoDice die; pmf_num
example : twoDice 3 = 1/9 := by unfold twoDice die; pmf_num
example : dieParity 0 = 1/2 := by unfold dieParity die; pmf_num
example : dieParity 1 = 1/2 := by unfold dieParity die; pmf_num
-- Bind through pure (the coin-negate pattern):
example : ((uniformOfFintype Bool).bind fun b => PMF.pure !b) true = 1/2 := by
  pmf_num

/-! ## ofFintype ![…] literals -/

example : loadedDie 0 = 1/2 := by unfold loadedDie; pmf_num
example : loadedDie 5 = 1/10 := by unfold loadedDie; pmf_num

/-! ## Stationary chain equations (the ChainScope crown) -/

example : ((PMF.ofFintype ![2/3, 1/3]
      (by simp [Fin.sum_univ_succ]; ennreal_num)).bind weather) 0 = 2/3 := by
  unfold weather; pmf_num
example : ((PMF.ofFintype ![2/3, 1/3]
      (by simp [Fin.sum_univ_succ]; ennreal_num)).bind weather) 1 = 1/3 := by
  unfold weather; pmf_num
example : ((PMF.ofFintype ![1/3, 1/3, 1/3]
      (by simp [Fin.sum_univ_succ]; ennreal_num)).bind triangle) 1 = 1/3 := by
  unfold triangle; pmf_num

/-! ## Negative tests: false claims FAIL, with the pinned message -/

/--
error: ennreal_num: cannot close this ℝ≥0∞ goal
⊢ False
-/
#guard_msgs in
example : (uniformOfFintype (Fin 6)) 0 = 1/3 := by pmf_num

/--
error: ennreal_num: cannot close this ℝ≥0∞ goal
⊢ 2 / 3 = 2⁻¹
-/
#guard_msgs in
example : biasedCoin true = 1/2 := by unfold biasedCoin; pmf_num

/--
error: ennreal_num: cannot close this ℝ≥0∞ goal
⊢ 6⁻¹ + 6⁻¹ = 1
-/
#guard_msgs in
example : (6⁻¹ + 6⁻¹ : ℝ≥0∞) = 1 := by ennreal_num

/--
error: ennreal_num: cannot close this ℝ≥0∞ goal
⊢ 6⁻¹ * 6⁻¹ + (6⁻¹ * 6⁻¹ + (6⁻¹ * 6⁻¹ + (6⁻¹ * 6⁻¹ + (6⁻¹ * 6⁻¹ + 6⁻¹ * 6⁻¹)))) = 7⁻¹
-/
#guard_msgs in
example : twoDice 5 = 1/7 := by unfold twoDice die; pmf_num

end DistLensTests
