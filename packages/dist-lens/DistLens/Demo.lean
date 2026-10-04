import DistLens.Widget

/-! # DistLens: demos

Realistic scenarios, all elaborated on every build.  Each `#dist`/`#chain`
below attaches a live InfoView panel; the `example :` blocks are exactly the
goals the panels offer as click-to-insert suggestions, compiled here to
prove the `pmf_num` recipe delivers on every advertised distribution.

`PMF.bernoulli` and `PMF.binomial` are deprecated at this Mathlib pin (in
favor of the new Measure-valued API) but fully functional; the demos disable
the deprecation linter around them on purpose — the PMF route is the one
DistLens can verify.
-/

namespace DistLens.Demo

open PMF
open scoped ENNReal NNReal

set_option linter.deprecated false

/-! ## The fair die -/

/-- A fair six-sided die (outcomes = `Fin 6` indices `0`–`5`). -/
noncomputable def die : PMF (Fin 6) := uniformOfFintype (Fin 6)

#dist die

-- The two verified weight examples the panel suggests:
example : die 0 = 1/6 := by unfold die; pmf_num
example : die 5 = 1/6 := by unfold die; pmf_num

/-! ## Two dice: the bind showpiece

`twoDice` is the sum of two independent die *indices* (`0`–`5` each), so the
outcome `5` corresponds to pip sum 7 — the classic `1/6`. -/

/-- Sum of two independent fair-die indices (pip sum − 2). -/
noncomputable def twoDice : PMF ℕ :=
  die.bind fun a => die.map fun b => a.val + b.val

#dist twoDice
#dist_film twoDice

-- P(pip sum 7) = P(index sum 5) = 1/6, fully verified:
example : twoDice 5 = 1/6 := by unfold twoDice die; pmf_num
-- The triangle tails:
example : twoDice 0 = 1/36 := by unfold twoDice die; pmf_num
example : twoDice 10 = 1/36 := by unfold twoDice die; pmf_num

/-! ## Parity of a die: map with collisions -/

/-- Parity of a fair die index: three even indices, three odd. -/
noncomputable def dieParity : PMF ℕ := die.map fun a => a.val % 2

#dist dieParity

example : dieParity 0 = 1/2 := by unfold dieParity die; pmf_num
example : dieParity 1 = 1/2 := by unfold dieParity die; pmf_num

/-! ## A biased coin: bernoulli 2/3

The `false` weight is the ℝ≥0∞ truncated-subtraction residue `1 − 2/3`,
closed by `pmf_num`'s `ENNReal.sub_eq_of_eq_add` branch. -/

/-- A biased coin: `P(true) = 2/3`. -/
noncomputable def biasedCoin : PMF Bool :=
  bernoulli (2/3) (by norm_num [div_le_one])

#dist biasedCoin

example : biasedCoin true = 2/3 := by unfold biasedCoin; pmf_num
example : biasedCoin false = 1/3 := by unfold biasedCoin; pmf_num

/-! ## Two coin flips: binomial (1/2) 2 -/

/-- Number of heads in two fair coin flips. -/
noncomputable def twoFlips : PMF (Fin 3) := binomial (1/2) (by norm_num) 2

#dist twoFlips

example : twoFlips 0 = 1/4 := by unfold twoFlips; pmf_num
example : twoFlips 1 = 1/2 := by unfold twoFlips; pmf_num

/-! ## A loaded die via ofFintype -/

/-- A loaded die: face 0 has probability 1/2, the rest 1/10 each. -/
noncomputable def loadedDie : PMF (Fin 6) :=
  PMF.ofFintype ![1/2, 1/10, 1/10, 1/10, 1/10, 1/10]
    (by simp [Fin.sum_univ_succ]; ennreal_num)

#dist loadedDie

example : loadedDie 0 = 1/2 := by unfold loadedDie; pmf_num
example : loadedDie 3 = 1/10 := by unfold loadedDie; pmf_num

/-! ## Uniform over a literal finset -/

#dist (uniformOfFinset ({1, 2, 3} : Finset ℕ) ⟨1, by simp⟩)

example : (uniformOfFinset ({1, 2, 3} : Finset ℕ) ⟨1, by simp⟩) 2 = 1/3 := by
  pmf_num

/-! ## ChainScope: a 2-state weather chain

State 0 = sunny, state 1 = rainy: `P(sunny → sunny) = 3/4`,
`P(rainy → sunny) = 1/2`.  The exact stationary distribution is
`π = (2/3, 1/3)`, and both stationary equations are verified below —
exactly the goals the `#chain` panel offers. -/

/-- The weather chain: sunny stays sunny w.p. 3/4; rain clears w.p. 1/2. -/
noncomputable def weather : Fin 2 → PMF (Fin 2) :=
  ![PMF.ofFintype ![3/4, 1/4] (by simp [Fin.sum_univ_succ]; ennreal_num),
    PMF.ofFintype ![1/2, 1/2] (by simp [Fin.sum_univ_succ]; ennreal_num)]

#chain weather
#chain weather init [0] steps 4

-- The stationary equations, per state — π = (2/3, 1/3):
example : ((PMF.ofFintype ![2/3, 1/3]
      (by simp [Fin.sum_univ_succ]; ennreal_num)).bind weather) 0 = 2/3 := by
  unfold weather; pmf_num
example : ((PMF.ofFintype ![2/3, 1/3]
      (by simp [Fin.sum_univ_succ]; ennreal_num)).bind weather) 1 = 1/3 := by
  unfold weather; pmf_num

/-! ## ChainScope: a 3-state cycle with drift

A lazy random walk on a triangle: stay w.p. 1/2, step clockwise w.p. 1/3,
counterclockwise w.p. 1/6.  By symmetry the stationary distribution is
uniform — DistLens computes it exactly, and the power-iteration filmstrip
from state 0 shows the convergence. -/

/-- Lazy triangle walk: stay 1/2, clockwise 1/3, counterclockwise 1/6. -/
noncomputable def triangle : Fin 3 → PMF (Fin 3) :=
  ![PMF.ofFintype ![1/2, 1/3, 1/6] (by simp [Fin.sum_univ_succ]; ennreal_num),
    PMF.ofFintype ![1/6, 1/2, 1/3] (by simp [Fin.sum_univ_succ]; ennreal_num),
    PMF.ofFintype ![1/3, 1/6, 1/2] (by simp [Fin.sum_univ_succ]; ennreal_num)]

#chain triangle init [0] steps 4

example : ((PMF.ofFintype ![1/3, 1/3, 1/3]
      (by simp [Fin.sum_univ_succ]; ennreal_num)).bind triangle) 0 = 1/3 := by
  unfold triangle; pmf_num

/-! ## An identity chain is reducible: reported, not resolved -/

/--
info: chain: 2 states
row 0: 1 0
row 1: 0 1
stationary: non-unique (reducible chain — the solution space has dimension > 1; DistLens picks no representative)
-/
#guard_msgs in
#chain (text := true) (fun i => PMF.pure i : Fin 2 → PMF (Fin 2))

end DistLens.Demo
