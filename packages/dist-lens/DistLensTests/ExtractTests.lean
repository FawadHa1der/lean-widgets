import DistLensTests.Helpers
import DistLens

/-! # Extraction tests

Message-exact `#guard_msgs` pins of the deterministic `(text := true)` modes
— extraction through real Mathlib `PMF` terms for every whitelisted
constructor — plus every user-facing refusal message.
-/

namespace DistLensTests

open PMF DistLens DistLens.Demo
open scoped ENNReal NNReal

set_option linter.deprecated false

/-! ## Whitelisted constructors, exact weights pinned -/

/--
info: dist: 6 outcomes over Fin 6
outcomes: 0 1 2 3 4 5
weights: 1/6 1/6 1/6 1/6 1/6 1/6
cdf: 1/6 1/3 1/2 2/3 5/6 1
moments: E[X] = 5/2, Var[X] = 35/12
-/
#guard_msgs in
#dist (text := true) (uniformOfFintype (Fin 6))

-- Through a user `def` (resolveHead unfolds it):
/--
info: dist: 6 outcomes over Fin 6
outcomes: 0 1 2 3 4 5
weights: 1/6 1/6 1/6 1/6 1/6 1/6
cdf: 1/6 1/3 1/2 2/3 5/6 1
moments: E[X] = 5/2, Var[X] = 35/12
-/
#guard_msgs in
#dist (text := true) die

/--
info: dist: 2 outcomes over Bool
outcomes: false true
weights: 1/2 1/2
cdf: 1/2 1
moments: E[X] = 1/2, Var[X] = 1/4
-/
#guard_msgs in
#dist (text := true) (uniformOfFintype Bool)

-- Opaque carrier: displayed with `Repr` labels, no canonical value map.
/--
info: dist: 4 outcomes over Fin 2 × Bool
outcomes: (0, true) (0, false) (1, true) (1, false)
weights: 1/4 1/4 1/4 1/4
cdf: 1/4 1/2 3/4 1
-/
#guard_msgs in
#dist (text := true) (uniformOfFintype (Fin 2 × Bool))

/--
info: dist: 3 outcomes over ℕ
outcomes: 1 2 3
weights: 1/3 1/3 1/3
cdf: 1/3 2/3 1
moments: E[X] = 2, Var[X] = 2/3
-/
#guard_msgs in
#dist (text := true) (uniformOfFinset ({1, 2, 3} : Finset ℕ) ⟨1, by simp⟩)

-- Duplicated literal elements are deduplicated (Finset semantics).
/--
info: dist: 2 outcomes over ℕ
outcomes: 1 2
weights: 1/2 1/2
cdf: 1/2 1
moments: E[X] = 3/2, Var[X] = 1/4
-/
#guard_msgs in
#dist (text := true) (uniformOfFinset ({1, 2, 1} : Finset ℕ) ⟨1, by simp⟩)

-- Out-of-order literals are sorted ascending: the outcome listing (and hence
-- the CDF) honors `XDist.keys`' contract regardless of insertion order.
/--
info: dist: 3 outcomes over ℕ
outcomes: 1 2 3
weights: 1/3 1/3 1/3
cdf: 1/3 2/3 1
moments: E[X] = 2, Var[X] = 2/3
-/
#guard_msgs in
#dist (text := true) (uniformOfFinset ({3, 1, 2} : Finset ℕ) ⟨1, by simp⟩)

/--
info: dist: 2 outcomes over Bool
outcomes: false true
weights: 1/3 2/3
cdf: 1/3 1
moments: E[X] = 2/3, Var[X] = 2/9
-/
#guard_msgs in
#dist (text := true) biasedCoin

/--
info: dist: 3 outcomes over Fin 3
outcomes: 0 1 2
weights: 1/4 1/2 1/4
cdf: 1/4 3/4 1
moments: E[X] = 1, Var[X] = 1/2
-/
#guard_msgs in
#dist (text := true) twoFlips

/--
info: dist: 4 outcomes over Fin 4
outcomes: 0 1 2 3
weights: 8/27 4/9 2/9 1/27
cdf: 8/27 20/27 26/27 1
moments: E[X] = 1, Var[X] = 2/3
-/
#guard_msgs in
#dist (text := true) (binomial (1/3) (by norm_num [div_le_one]) 3)

-- `pure` over a `Fin` carrier draws the full range (zero bars included).
/--
info: dist: 6 outcomes over Fin 6
outcomes: 0 1 2 3 4 5
weights: 0 0 0 1 0 0
cdf: 0 0 0 1 1 1
moments: E[X] = 3, Var[X] = 0
-/
#guard_msgs in
#dist (text := true) (PMF.pure (3 : Fin 6))

-- `pure` over ℕ: singular noun, support only.
/--
info: dist: 1 outcome over ℕ
outcomes: 5
weights: 1
cdf: 1
moments: E[X] = 5, Var[X] = 0
-/
#guard_msgs in
#dist (text := true) (PMF.pure (5 : ℕ))

/--
info: dist: 2 outcomes over Bool
outcomes: false true
weights: 0 1
cdf: 0 1
moments: E[X] = 1, Var[X] = 0
-/
#guard_msgs in
#dist (text := true) (PMF.pure true)

-- The bind showpiece: the two-dice triangle over 36, exact.
/--
info: dist: 11 outcomes over ℕ
outcomes: 0 1 2 3 4 5 6 7 8 9 10
weights: 1/36 1/18 1/12 1/9 5/36 1/6 5/36 1/9 1/12 1/18 1/36
cdf: 1/36 1/12 1/6 5/18 5/12 7/12 13/18 5/6 11/12 35/36 1
moments: E[X] = 5, Var[X] = 35/6
-/
#guard_msgs in
#dist (text := true) twoDice

-- Map with collisions: die parity.
/--
info: dist: 2 outcomes over ℕ
outcomes: 0 1
weights: 1/2 1/2
cdf: 1/2 1
moments: E[X] = 1/2, Var[X] = 1/4
-/
#guard_msgs in
#dist (text := true) dieParity

/--
info: dist: 6 outcomes over Fin 6
outcomes: 0 1 2 3 4 5
weights: 1/2 1/10 1/10 1/10 1/10 1/10
cdf: 1/2 3/5 7/10 4/5 9/10 1
moments: E[X] = 3/2, Var[X] = 13/4
-/
#guard_msgs in
#dist (text := true) loadedDie

-- A bind that ignores its argument still convolves correctly.
/--
info: dist: 6 outcomes over Fin 6
outcomes: 0 1 2 3 4 5
weights: 1/6 1/6 1/6 1/6 1/6 1/6
cdf: 1/6 1/3 1/2 2/3 5/6 1
moments: E[X] = 5/2, Var[X] = 35/12
-/
#guard_msgs in
#dist (text := true) (die.bind fun _ => die)

/-! ## Filmstrips -/

/--
info: == source
dist: 2 outcomes over Bool
outcomes: false true
weights: 1/3 2/3
cdf: 1/3 1
moments: E[X] = 2/3, Var[X] = 2/9
== branch false (weight 1/3)
dist: 1 outcome over ℕ
outcomes: 0
weights: 1
cdf: 1
moments: E[X] = 0, Var[X] = 0
== branch true (weight 2/3)
dist: 1 outcome over ℕ
outcomes: 1
weights: 1
cdf: 1
moments: E[X] = 1, Var[X] = 0
== result
dist: 2 outcomes over ℕ
outcomes: 0 1
weights: 1/3 2/3
cdf: 1/3 1
moments: E[X] = 2/3, Var[X] = 2/9
-/
#guard_msgs in
#dist_film (text := true) (biasedCoin.bind fun b => PMF.pure (cond b 1 0 : ℕ))

-- A bind whose branches are bernoullis with `cond`-selected parameters:
-- P(true) = 1/3 · 1/4 + 2/3 · 1/2 = 5/12.
/--
info: == source
dist: 2 outcomes over Bool
outcomes: false true
weights: 1/3 2/3
cdf: 1/3 1
moments: E[X] = 2/3, Var[X] = 2/9
== branch false (weight 1/3)
dist: 2 outcomes over Bool
outcomes: false true
weights: 3/4 1/4
cdf: 3/4 1
moments: E[X] = 1/4, Var[X] = 3/16
== branch true (weight 2/3)
dist: 2 outcomes over Bool
outcomes: false true
weights: 1/2 1/2
cdf: 1/2 1
moments: E[X] = 1/2, Var[X] = 1/4
== result
dist: 2 outcomes over Bool
outcomes: false true
weights: 7/12 5/12
cdf: 7/12 1
moments: E[X] = 5/12, Var[X] = 35/144
-/
#guard_msgs in
#dist_film (text := true) (biasedCoin.bind fun b =>
  bernoulli (cond b (1/2) (1/4)) (by cases b <;> norm_num [div_le_one]))

/-! ## Chains -/

/--
info: chain: 2 states
row 0: 3/4 1/4
row 1: 1/2 1/2
stationary: unique
π: 2/3 1/3
-/
#guard_msgs in
#chain (text := true) weather

/--
info: chain: 2 states
row 0: 3/4 1/4
row 1: 1/2 1/2
stationary: unique
π: 2/3 1/3
step 0: 1 0
step 1: 3/4 1/4
step 2: 11/16 5/16
step 3: 43/64 21/64
-/
#guard_msgs in
#chain (text := true) weather init [0] steps 3

-- `steps` without `init` powers up from the uniform distribution.
/--
info: chain: 2 states
row 0: 3/4 1/4
row 1: 1/2 1/2
stationary: unique
π: 2/3 1/3
step 0: 1/2 1/2
step 1: 5/8 3/8
step 2: 21/32 11/32
-/
#guard_msgs in
#chain (text := true) weather steps 2

/--
info: chain: 3 states
row 0: 1/2 1/3 1/6
row 1: 1/6 1/2 1/3
row 2: 1/3 1/6 1/2
stationary: unique
π: 1/3 1/3 1/3
-/
#guard_msgs in
#chain (text := true) triangle

-- Reducible chain: reported, never silently resolved.
/--
info: chain: 2 states
row 0: 1 0
row 1: 0 1
stationary: non-unique (reducible chain — the solution space has dimension > 1; DistLens picks no representative)
-/
#guard_msgs in
#chain (text := true) (fun i => PMF.pure i : Fin 2 → PMF (Fin 2))

/-! ## Honest refusals, every message pinned -/

/-- An opaque (non-literal) bernoulli parameter. -/
noncomputable def symbolicP : NNReal := 2/3

/--
error: #dist: the bernoulli parameter `symbolicP` is not a rational literal — symbolic parameters are refused rather than guessed at
-/
#guard_msgs in
#dist (text := true) (bernoulli symbolicP (by unfold symbolicP; norm_num [div_le_one]))

/--
error: #dist: the map function builds `Fin.mk`/`Subtype.mk` values — refused, because the `pmf_num` verification recipe provably hits `maxRecDepth` on subtype-mk images; use a `ℕ`-valued map instead (e.g. `.val` arithmetic)
-/
#guard_msgs in
#dist (text := true) (die.map fun a => (⟨a.val % 3, by omega⟩ : Fin 3))

/--
error: #dist: the carrier has 100 outcomes, more than the limit of 64 — DistLens refuses to draw it
-/
#guard_msgs in
#dist (text := true) (uniformOfFintype (Fin 100))

/--
error: #dist: expected a term of type `PMF α`, but `3` has type `ℕ`
-/
#guard_msgs in
#dist (text := true) (3 : ℕ)

/--
error: #dist: `@Subtype.mk` is not a supported PMF constructor — DistLens matches PMF.pure, PMF.bind, PMF.map, PMF.uniformOfFintype, PMF.uniformOfFinset, PMF.bernoulli, PMF.binomial and PMF.ofFintype (with `![…]` literal weights); symbolic or monadic spellings are refused rather than guessed at
-/
#guard_msgs in
#dist (text := true)
  (PMF.normalize (fun _ => 1/6 : Fin 6 → ℝ≥0∞) (by norm_num) (by norm_num))

/--
error: #dist: `map` from a distribution over `Fin 2 × Bool` is not supported — DistLens can only follow outcomes of `Fin n`, `Bool` and `ℕ` carriers
-/
#guard_msgs in
#dist (text := true) ((uniformOfFintype (Fin 2 × Bool)).map fun a => a.1.val)

/--
error: #dist_film: expected a `PMF.bind` term to film — `uniformOfFintype (Fin 6)` does not resolve to one
-/
#guard_msgs in
#dist_film (text := true) die

/--
error: #chain: expected a term of type `Fin n → PMF (Fin n)` with a literal `n`, but `3` has type `ℕ`
-/
#guard_msgs in
#chain (text := true) (3 : ℕ)

/--
error: #chain: initial state 5 is out of range for 2 states
-/
#guard_msgs in
#chain (text := true) weather init [5]

/--
error: #chain: 99 steps exceed the limit of 16
-/
#guard_msgs in
#chain (text := true) weather steps 99

/--
error: #chain: duplicate `init` clause
-/
#guard_msgs in
#chain (text := true) weather init [0] init [1]

/--
error: #chain: duplicate `steps` clause
-/
#guard_msgs in
#chain (text := true) weather steps 1 steps 2

end DistLensTests
