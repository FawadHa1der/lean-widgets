import DistLens

/-! # DistLens test helpers

Shared fixture models (pure ℚ, no `Expr`) used across the test files, plus
the demo distributions re-exported for command-level tests.
-/

namespace DistLensTests

open DistLens

/-- The fair die as a pure model (canonical `Fin` values `0`–`5`). -/
def die6 : DistModel :=
  { carrier := "Fin 6"
    labels := #["0", "1", "2", "3", "4", "5"]
    weights := #[1/6, 1/6, 1/6, 1/6, 1/6, 1/6]
    values? := some #[0, 1, 2, 3, 4, 5] }

/-- A biased coin (`P(true) = 2/3`) as a pure model. -/
def coin : DistModel :=
  { carrier := "Bool"
    labels := #["false", "true"]
    weights := #[1/3, 2/3]
    values? := some #[0, 1] }

/-- A deliberately broken model: mass 7/6, one negative weight, a label
mismatch — the invariant tests check each violation fires. -/
def badModel : DistModel :=
  { carrier := "Fin 3"
    labels := #["0", "1"]
    weights := #[1/2, -1/3, 1]
    values? := some #[0, 1, 2] }

/-- The weather chain `[[3/4, 1/4], [1/2, 1/2]]` (stationary `(2/3, 1/3)`). -/
def weatherM : ChainModel := { n := 2, matrix := #[#[3/4, 1/4], #[1/2, 1/2]] }

/-- The identity chain (reducible: every distribution is stationary). -/
def identityM : ChainModel := { n := 2, matrix := #[#[1, 0], #[0, 1]] }

/-- The lazy triangle walk (stationary uniform by symmetry). -/
def triangleM : ChainModel :=
  { n := 3
    matrix := #[#[1/2, 1/3, 1/6], #[1/6, 1/2, 1/3], #[1/3, 1/6, 1/2]] }

/-- A broken chain: row 0 sums to 5/4, entry (1,0) negative. -/
def badChain : ChainModel :=
  { n := 2, matrix := #[#[1, 1/4], #[-1/2, 3/2]] }

end DistLensTests
