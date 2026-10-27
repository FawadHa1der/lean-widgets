/-
Adapted from Mathlib (https://github.com/leanprover-community/mathlib4), file
`Mathlib/Probability/Distributions/Uniform.lean` at tag `v4.34.0`
(commit 5ed2965256430c3649e86755f9576b54eca72435), whose header reads:

  Copyright (c) 2024 Josha Dekker. All rights reserved.
  Released under Apache 2.0 license as described in the file LICENSE.
  Authors: Josha Dekker, Devon Tuma, Kexing Ying

("the file LICENSE" is Mathlib's: the Apache License, Version 2.0,
http://www.apache.org/licenses/LICENSE-2.0.)  This adaptation is distributed under
the same license, whose full text this package ships as `LICENSE-APACHE-2.0`; see also
this package's `NOTICE`.

Modifications (Fawad Haider, 2026-10-25, for the Mathlib v4.35.0 port of DistLens):
* namespace `PMF` → `DistLens` (Mathlib v4.35.0 took the `PMF` names over: see below);
* `noncomputable` written on both `def`s (Mathlib's file is a `noncomputable section`);
* the section `variable`s (`{s : Finset α} (hs : s.Nonempty)`, `[Fintype α] [Nonempty α]`)
  written as binders of the two lemmas, and the `open`s reduced to what these need;
* kept only `uniformOfFinset`, `uniformOfFinset_apply`, `uniformOfFintype` and
  `uniformOfFintype_apply` (bodies, proofs and `@[simp]` attributes unchanged), and
  dropped every other declaration of the file:
  - in namespace `MeasureTheory.pdf`: `IsUniform`; its lemmas `IsUniform.aemeasurable`,
    `IsUniform.map_eq`, `IsUniform.absolutelyContinuous`, `IsUniform.measure_preimage`,
    `IsUniform.isProbabilityMeasure`, `IsUniform.toMeasurable_iff`,
    `IsUniform.toMeasurable`, `IsUniform.hasPDF`,
    `IsUniform.pdf_eq_zero_of_measure_eq_zero_or_top`, `IsUniform.pdf_eq`,
    `IsUniform.pdf_toReal_ae_eq`, `IsUniform.mul_pdf_integrable`,
    `IsUniform.integral_eq` and `IsUniform.cond`; and `uniformPDF`,
    `uniformPDF_eq_pdf` and `uniformPDF_ite`;
  - in namespace `PMF`: `uniformOfFinset_apply_of_mem`, `uniformOfFinset_apply_of_notMem`,
    `support_uniformOfFinset`, `mem_support_uniformOfFinset_iff`,
    `toOuterMeasure_uniformOfFinset_apply`, `toMeasure_uniformOfFinset_apply`,
    `support_uniformOfFintype`, `mem_support_uniformOfFintype`,
    `toOuterMeasure_uniformOfFintype_apply`, `toMeasure_uniformOfFintype_apply`, and the
    whole `OfMultiset` section: `ofMultiset`, `ofMultiset_apply`, `support_ofMultiset`,
    `mem_support_ofMultiset_iff`, `ofMultiset_apply_of_notMem`,
    `toOuterMeasure_ofMultiset_apply` and `toMeasure_ofMultiset_apply`;
* not a `module` file (Mathlib's is: `module`, `@[expose] public section`, `public
  import`s), and imports only `Mathlib.Probability.ProbabilityMassFunction.Constructions`
  (Mathlib's also imports `Mathlib.Probability.ConditionalProbability` and
  `Mathlib.Probability.HasLaw`); docstrings extended with a pointer to the Mathlib
  original; this header and the module docstring below are new (they replace Mathlib's
  header comment and module docstring).
-/
import Mathlib.Probability.ProbabilityMassFunction.Constructions

/-! # DistLens: the uniform `PMF` constructors

Mathlib `v4.35.0` (#42909, "change uniformOfFinset and ofMultiset from PMF to
Measure", part of the `PMF` deprecation #42821) removed the `PMF`-valued
`PMF.uniformOfFinset` / `PMF.uniformOfFintype`: `MeasureTheory.Measure.uniformOfFinset
(s : Finset α) : Measure α` replaces both, and the name `PMF.uniformOfFintype` survives
only as a deprecated alias *of that Measure-valued definition* (so
`PMF.uniformOfFintype (Fin 6)` no longer elaborates).  A `Measure` cannot be fed to
`PMF.bind`/`PMF.map`, and the rest of the `PMF` API DistLens draws (`pure`, `bind`,
`map`, `ofFintype`, `bernoulli`, `binomial`) is unchanged at `v4.35.0`, so DistLens
keeps the two uniform constructors itself, under its own namespace.

The definitions and the two `_apply` lemmas are Mathlib `v4.34.0`'s
(`Mathlib/Probability/Distributions/Uniform.lean`, namespace `PMF`) verbatim, on top of
`PMF.ofFinset` (unchanged at `v4.35.0`): same arguments, same values, same `@[simp]`
attributes, same classical `if` in `uniformOfFinset_apply` — so `#dist`, the suggestions
and `pmf_num` behave exactly as they did on `PMF.uniformOfFintype`/`PMF.uniformOfFinset`.
The rest of Mathlib's file, none of which DistLens uses, is not carried over: the
`MeasureTheory.pdf` part (`IsUniform`, `uniformPDF`), the support/measure lemmas and
`ofMultiset` (the header names every dropped declaration and lists every other
modification).  `DistLensTests/UniformTests.lean` pins the lemma statements,
the two `@[simp]` attributes (plain `simp`) and `pmf_num`'s explicit use of both lemmas;
`DistLensTests/MathlibUniformTests.lean` pins how the names meet Mathlib's.
-/

namespace DistLens

open PMF
open scoped NNReal ENNReal

variable {α : Type*}

/-- Uniform distribution taking the same non-zero probability on the nonempty finset `s`
(Mathlib `v4.34.0`'s `PMF.uniformOfFinset`). -/
noncomputable def uniformOfFinset (s : Finset α) (hs : s.Nonempty) : PMF α := by
  classical
  refine ofFinset (fun a => if a ∈ s then s.card⁻¹ else 0) s ?_ ?_
  · simp only [Finset.sum_ite_mem, Finset.inter_self, Finset.sum_const, nsmul_eq_mul]
    have : (s.card : ℝ≥0∞) ≠ 0 := by
      simpa only [Ne, Nat.cast_eq_zero, Finset.card_eq_zero] using
        Finset.nonempty_iff_ne_empty.1 hs
    exact ENNReal.mul_inv_cancel this <| ENNReal.natCast_ne_top s.card
  · exact fun x hx => by simp only [hx, ite_false]

open scoped Classical in
@[simp]
theorem uniformOfFinset_apply {s : Finset α} (hs : s.Nonempty) (a : α) :
    uniformOfFinset s hs a = if a ∈ s then (s.card : ℝ≥0∞)⁻¹ else 0 :=
  rfl

/-- The uniform pmf taking the same uniform value on all of the fintype `α`
(Mathlib `v4.34.0`'s `PMF.uniformOfFintype`). -/
noncomputable def uniformOfFintype (α : Type*) [Fintype α] [Nonempty α] : PMF α :=
  uniformOfFinset Finset.univ Finset.univ_nonempty

@[simp]
theorem uniformOfFintype_apply [Fintype α] [Nonempty α] (a : α) :
    uniformOfFintype α a = (Fintype.card α : ℝ≥0∞)⁻¹ := by
  simp [uniformOfFintype, Finset.mem_univ, uniformOfFinset_apply]

end DistLens
