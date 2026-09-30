import Mathlib.Probability.ProbabilityMassFunction.Constructions
import Mathlib.Probability.ProbabilityMassFunction.Binomial
import Mathlib.Probability.Distributions.Uniform
import Mathlib.Probability.ProbabilityMassFunction.Integrals
import Mathlib.Tactic.NormNum
import Mathlib.Tactic.Finiteness

/-! # DistLens: verified weight goals — the `pmf_num` tactic

The proof side of the picture+proof contract.  For every weight DistLens
displays, it offers the goal `p x = (a/b : ℝ≥0∞)` with the suggested proof
`by pmf_num`.  This file ships that tactic; the test suite *compiles* such
examples for every demo distribution, so the recipe is proven to work, not
just printed.

The recipe is exactly the probe-validated chain:

1. `simp` with the PMF application lemma set (`bind_apply`, `map_apply`,
   `pure_apply`, `bernoulli_apply`, `uniformOfFintype_apply`,
   `uniformOfFinset_apply`, `binomial_apply`, `ofFintype_apply`,
   `tsum_fintype`, `tsum_bool`, `Fin.sum_univ_succ`, plus the
   `Matrix.cons_val*` lemmas so `![…]`-literal weight functions and
   `![…]`-vectors of PMFs reduce), leaving a ground ℝ≥0∞ arithmetic residue;
2. `ennreal_num` closes the residue:
   * `done` — `simp` already closed it;
   * `norm_num` — for residues plain `norm_num` can do (e.g. after
     `binomial_apply`);
   * the `toReal` bridge — `ENNReal.toReal_eq_toReal_iff'` with `finiteness`
     side goals, push `toReal` through `+ * / ⁻¹ ^`, finish with `norm_num`
     in ℝ (there is **no** ENNReal `norm_num` extension in Mathlib, so this
     bridge is mandatory for goals like `6⁻¹ + 6⁻¹ + 6⁻¹ = 2⁻¹`);
   * the truncated-subtraction branch — `ENNReal.sub_eq_of_eq_add` first
     (for `bernoulli`'s `1 − p` residue at `false`), then the same bridge.

Every branch ends in `done`, so a partial simplification never "succeeds"
with goals left over; if no branch closes the goal, the tactic fails with a
deterministic message (pinned by the negative tests) — honest failure over
silent wrongness.

`ennreal_num` is exposed separately because it is also the right tool for
`PMF.ofFintype`'s sum-to-1 side goal (after `simp [Fin.sum_univ_succ]`).
-/

namespace DistLens

open ENNReal

/-- Close a ground ℝ≥0∞ arithmetic goal: `done` | `norm_num` | the
`toReal_eq_toReal_iff'`+`finiteness` bridge into ℝ | the
`ENNReal.sub_eq_of_eq_add` branch for truncated-subtraction residues
(`bernoulli`'s `1 − p`).  Fails with a deterministic message when no branch
applies — plain `norm_num` cannot decide most ℝ≥0∞ arithmetic, so the bridge
branches carry the real load. -/
syntax (name := ennrealNum) "ennreal_num" : tactic

macro_rules
  | `(tactic| ennreal_num) =>
    `(tactic| first
      | done
      | (norm_num; done)
      | (rw [← ENNReal.toReal_eq_toReal_iff' (by finiteness) (by finiteness)]
         simp (disch := finiteness) only [ENNReal.toReal_add, ENNReal.toReal_inv,
           ENNReal.toReal_mul, ENNReal.toReal_div, ENNReal.toReal_pow,
           ENNReal.toReal_ofNat, ENNReal.toReal_one, ENNReal.toReal_natCast]
         norm_num
         done)
      | (apply ENNReal.sub_eq_of_eq_add (by finiteness)
         rw [← ENNReal.toReal_eq_toReal_iff' (by finiteness) (by finiteness)]
         simp (disch := finiteness) only [ENNReal.toReal_add, ENNReal.toReal_inv,
           ENNReal.toReal_mul, ENNReal.toReal_div, ENNReal.toReal_pow,
           ENNReal.toReal_ofNat, ENNReal.toReal_one, ENNReal.toReal_natCast]
         norm_num
         done)
      | fail "ennreal_num: cannot close this ℝ≥0∞ goal")

/-- Prove a concrete PMF weight equality `p x = (a/b : ℝ≥0∞)` for the
DistLens-supported constructors (`pure`, `bind`, `map`, `uniformOfFintype`,
`uniformOfFinset`, `bernoulli`, `binomial`, `ofFintype` with `![…]`
literals): `simp` with the PMF application lemma set, then `ennreal_num` on
every residue.  Also proves the stationary-chain equalities
`(π.bind step) y = π y`.  Fails deterministically on goals outside this
shape — including *false* weight claims (pinned by the negative tests). -/
syntax (name := pmfNum) "pmf_num" : tactic

macro_rules
  | `(tactic| pmf_num) =>
    -- The simp set names `PMF.bernoulli_apply`/`PMF.binomial_apply`, which are
    -- deprecated at this pin; without the scoped option every `by pmf_num`
    -- inserted into a user file would emit deprecation warnings even for
    -- non-deprecated distributions.
    `(tactic|
      set_option linter.deprecated false in
      ((try simp [PMF.bind_apply, PMF.map_apply, PMF.pure_apply,
          PMF.bernoulli_apply, PMF.uniformOfFintype_apply,
          PMF.uniformOfFinset_apply, PMF.binomial_apply, PMF.ofFintype_apply,
          tsum_fintype, tsum_bool, Fin.sum_univ_succ,
          Matrix.cons_val_zero, Matrix.cons_val_one, Matrix.head_cons,
          Fin.isValue]) <;>
       ennreal_num))

end DistLens
