import Mathlib
import DistLens

/-! # DistLens: exact distributions and Markov chains, with verified goals
Cursor on `#dist p`: the panel draws the exact ℚ weights of a `PMF` as bars
with fraction labels, the CDF, `E[X]`/`Var[X]` — and lists every weight as
an insertable goal: click one to insert
`example : p x = a/b := by unfold p; pmf_num` after the command (the test
suite compiles these).  `#dist_film p` shows a filmstrip of how a `bind`
builds `p`.  Cursor on `#chain step`: the transition graph with exact edge
labels and the exact stationary distribution π, whose per-state equations
are insertable too; `init [i] steps n` adds a power-iteration filmstrip. -/

open PMF
open scoped ENNReal

namespace Showcase.DistLens

/-- A fair six-sided die (outcomes = `Fin 6` indices `0`–`5`). -/
noncomputable def die : PMF (Fin 6) := uniformOfFintype (Fin 6)
#dist die

/-- Sum of two independent die indices: the 1/36 … 6/36 … 1/36 triangle. -/
noncomputable def twoDice : PMF ℕ := die.bind fun a => die.map fun b => a.val + b.val
#dist twoDice
#dist_film twoDice

/-- Weather: sunny stays sunny w.p. 3/4; rain clears w.p. 1/2. -/
noncomputable def weather : Fin 2 → PMF (Fin 2) :=
  ![PMF.ofFintype ![3/4, 1/4] (by simp [Fin.sum_univ_succ]; ennreal_num),
    PMF.ofFintype ![1/2, 1/2] (by simp [Fin.sum_univ_succ]; ennreal_num)]
#chain weather
#chain weather init [0] steps 3

end Showcase.DistLens
