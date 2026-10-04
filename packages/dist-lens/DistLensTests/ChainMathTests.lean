import DistLensTests.Helpers

/-! # Chain math tests

Exact pins for the stationary-distribution Gaussian elimination (the weather
chain's hand-computed `π = (2/3, 1/3)`, the triangle walk's uniform π, a
reducible chain reported non-unique), power iteration, and the chain
invariant checker.
-/

namespace DistLensTests

open DistLens

/-! ## Stationary distributions -/

-- Weather chain: balance at state 0 gives π₀·3/4 + π₁·1/2 = π₀, so
-- π₀ = 2·π₁; with π₀ + π₁ = 1: π = (2/3, 1/3).  Hand-computed, pinned.
#guard weatherM.stationary = .unique #[2/3, 1/3]

-- Triangle walk: doubly stochastic, so uniform is stationary; irreducible,
-- so it is the unique one.
#guard triangleM.stationary = .unique #[1/3, 1/3, 1/3]

-- The identity chain is reducible: every π is stationary — reported, never
-- silently resolved.
#guard identityM.stationary = .nonUnique

-- Two disconnected 1-loops inside a 3-state chain: also non-unique.
#guard (ChainModel.stationary
  { n := 3, matrix := #[#[1, 0, 0], #[0, 1, 0], #[0, 0, 1]] }) = .nonUnique

-- An absorbing chain: state 1 absorbs, so π = (0, 1) uniquely.
#guard (ChainModel.stationary
  { n := 2, matrix := #[#[1/2, 1/2], #[0, 1]] }) = .unique #[0, 1]

-- A 1-state chain: π = (1).
#guard (ChainModel.stationary { n := 1, matrix := #[#[1]] }) = .unique #[1]

-- Periodic two-cycle: unique π = (1/2, 1/2) (power iteration oscillates but
-- the stationary system still pins it).
#guard (ChainModel.stationary
  { n := 2, matrix := #[#[0, 1], #[1, 0]] }) = .unique #[1/2, 1/2]

-- Empty chain: flagged, not crashed.
#guard (ChainModel.stationary { n := 0, matrix := #[] }) = .inconsistent

/-! ## Verify π P = π exactly (self-check of the solver) -/

#guard weatherM.stepDist #[2/3, 1/3] = #[2/3, 1/3]
#guard triangleM.stepDist #[1/3, 1/3, 1/3] = #[1/3, 1/3, 1/3]

/-! ## Power iteration -/

#guard weatherM.pointMass 0 = #[1, 0]
#guard weatherM.uniformInit = #[1/2, 1/2]
#guard weatherM.stepDist #[1, 0] = #[3/4, 1/4]
#guard weatherM.powerFrames #[1, 0] 3
  = #[#[1, 0], #[3/4, 1/4], #[11/16, 5/16], #[43/64, 21/64]]
-- Frames preserve mass exactly.
#guard (weatherM.powerFrames #[1, 0] 8).all
  (fun f => f.foldl (· + ·) 0 == 1)
-- Zero steps: just the initial frame.
#guard weatherM.powerFrames #[1/2, 1/2] 0 = #[#[1/2, 1/2]]

/-! ## rref sanity -/

-- x + y = 3, x − y = 1  ⇒  x = 2, y = 1.
#guard rref #[#[1, 1, 3], #[1, -1, 1]] 2 = #[#[1, 0, 2], #[0, 1, 1]]
-- A dependent row reduces to zero.
#guard rref #[#[1, 1, 2], #[2, 2, 4]] 2 = #[#[1, 1, 2], #[0, 0, 0]]
-- Inconsistent system keeps a 0 = 1 row.
#guard rref #[#[1, 1, 2], #[1, 1, 3]] 2 = #[#[1, 1, 2], #[0, 0, 1]]

/-! ## Chain invariants -/

#guard weatherM.invariantViolations = #[]
#guard triangleM.invariantViolations = #[]
#guard badChain.invariantViolations
  = #["internal: row 0 sums to 5/4, not 1",
      "internal: entry -1/2 at (1, 0) is negative"]
-- Wrong shape: both the row count and a row length are flagged.
#guard (ChainModel.invariantViolations { n := 2, matrix := #[#[1]] })
  = #["internal: 1 rows for 2 states",
      "internal: row 0 has 1 entries, expected 2"]

end DistLensTests
