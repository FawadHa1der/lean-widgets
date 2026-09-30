import DistLensTests.Helpers

/-! # Pure model tests

Exact-value pins for `ratStr`/`ratPercentStr`, `DistModel` (mass, CDF,
support, expectation/variance — including the classic pips-die `E = 7/2`,
`Var = 35/12`), the ℚ distribution combinators (convolution = the two-dice
triangle over 36, pushforward with collisions, binomial weights), and
`FilmModel` diff marks.
-/

namespace DistLensTests

open DistLens

/-! ## Rational formatting -/

#guard ratStr (1/6) = "1/6"
#guard ratStr (3/4) = "3/4"
#guard ratStr 2 = "2"
#guard ratStr 0 = "0"
#guard ratStr (-1/2) = "-1/2"
#guard ratStr (6/4 : Rat) = "3/2"          -- always reduced
#guard ratPercentStr (1/6) = "16.7%"
#guard ratPercentStr (2/3) = "66.7%"
#guard ratPercentStr 1 = "100.0%"
#guard ratPercentStr 0 = "0.0%"
#guard ratPercentStr (1/2) = "50.0%"

/-! ## DistModel basics -/

#guard die6.size = 6
#guard die6.massTotal = 1
#guard die6.invariantViolations = #[]
#guard coin.invariantViolations = #[]
#guard die6.cdf = #[1/6, 1/3, 1/2, 2/3, 5/6, 1]
#guard coin.cdf = #[1/3, 1]
#guard die6.supportIdxs = #[0, 1, 2, 3, 4, 5]

-- A distribution with zero-weight outcomes: support and restriction.
def withZeros : DistModel :=
  { carrier := "Fin 4", labels := #["0", "1", "2", "3"]
    weights := #[0, 1/2, 0, 1/2], values? := some #[0, 1, 2, 3] }

#guard withZeros.supportIdxs = #[1, 3]
#guard withZeros.restrictToSupport.labels = #["1", "3"]
#guard withZeros.restrictToSupport.weights = #[1/2, 1/2]
#guard withZeros.restrictToSupport.values? = some #[1, 3]
#guard withZeros.restrictToSupport.massTotal = 1

/-! ## Moments -/

-- Canonical Fin-index values 0..5:
#guard die6.expectation? = some (5/2)
#guard die6.variance? = some (35/12)
-- The classic pips die (values 1..6): E = 7/2, Var = 35/12.
#guard die6.expectationWith #[1, 2, 3, 4, 5, 6] = 7/2
#guard die6.varianceWith #[1, 2, 3, 4, 5, 6] = 35/12
#guard coin.expectation? = some (2/3)
#guard coin.variance? = some (2/9)
-- A point mass has variance 0.
#guard (DistModel.varianceWith
  { carrier := "Fin 2", labels := #["0", "1"], weights := #[0, 1] }
  #[0, 1]) = 0

/-! ## Combinators: convolution, pushforward, binomial -/

-- Fair-coin convolution: two flips of ({0,1}, 1/2 each) = (1/4, 1/2, 1/4).
#guard convolve #[1/2, 1/2] #[#[(0, 1/2), (1, 1/2)], #[(1, 1/2), (2, 1/2)]]
  = #[(0, 1/4), (1, 1/2), (2, 1/4)]

-- The two-dice triangle: convolving a die with shifted dice gives k+1 over 36
-- ascending then descending — pin the full triangle.
def dieRow (shift : Nat) : Array (Nat × Rat) :=
  (Array.range 6).map fun b => (shift + b, (1 : Rat)/6)

#guard convolve #[1/6, 1/6, 1/6, 1/6, 1/6, 1/6]
    ((Array.range 6).map dieRow)
  = #[(0, 1/36), (1, 2/36), (2, 3/36), (3, 4/36), (4, 5/36), (5, 6/36),
      (6, 5/36), (7, 4/36), (8, 3/36), (9, 2/36), (10, 1/36)]

-- Convolution result mass is exactly 1.
#guard (convolve #[1/6, 1/6, 1/6, 1/6, 1/6, 1/6]
    ((Array.range 6).map dieRow)).foldl (fun s (_, w) => s + w) 0 = 1

-- Pushforward with collisions: die parity.
#guard pushforward #[1/6, 1/6, 1/6, 1/6, 1/6, 1/6] #[0, 1, 0, 1, 0, 1]
  = #[(0, 1/2), (1, 1/2)]
-- Pushforward to a single point.
#guard pushforward #[1/2, 1/2] #[7, 7] = #[(7, 1)]
-- Pushforward keys come out sorted even when hit out of order.
#guard pushforward #[1/4, 1/4, 1/2] #[9, 3, 5]
  = #[(3, 1/4), (5, 1/2), (9, 1/4)]

#guard binomialWeights (1/2) 2 = #[1/4, 1/2, 1/4]
#guard binomialWeights (1/3) 3 = #[8/27, 4/9, 2/9, 1/27]
#guard binomialWeights (1/2) 0 = #[1]
#guard (binomialWeights (1/3) 5).foldl (· + ·) 0 = 1
#guard uniformWeights 4 = #[1/4, 1/4, 1/4, 1/4]
#guard chooseQ 5 2 = 10

/-! ## Filmstrip diff marks -/

def filmAB : FilmModel :=
  ⟨#[("source", coin), ("result", { coin with weights := #[1/2, 1/2] })]⟩

-- Frame 0 is never marked; frame 1 marks both changed weights.
#guard filmAB.marks 0 = #[false, false]
#guard filmAB.marks 1 = #[true, true]
-- Out-of-range frame: no marks.
#guard filmAB.marks 5 = #[]

-- A frame with a brand-new outcome label marks it (and only it).
def filmGrow : FilmModel :=
  ⟨#[("a", { carrier := "ℕ", labels := #["0"], weights := #[1] }),
     ("b", { carrier := "ℕ", labels := #["0", "1"], weights := #[1, 0] })]⟩

#guard filmGrow.marks 1 = #[false, true]

end DistLensTests
