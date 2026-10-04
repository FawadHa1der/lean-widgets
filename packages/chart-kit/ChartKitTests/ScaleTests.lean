import ChartKitTests.Helpers

/-! # Scale tests

Exhaustive pins of the exact-ℚ mathematical core: integer log10, nice steps,
nice axes across magnitudes (including degenerate single-value and empty
ranges), categorical axes, the affine pixel map, decimal serialization, and
data bounds — plus the tick monotonicity/coverage properties re-checked as
pure checkers over a battery of ranges.
-/

namespace ChartKitTests

open ChartKit

/-! ## natLog10 / pow10 / ilog10 -/

#guard natLog10 0 = 0
#guard natLog10 9 = 0
#guard natLog10 10 = 1
#guard natLog10 99 = 1
#guard natLog10 100 = 2
#guard natLog10 999999 = 5
#guard natLog10 1000000 = 6

#guard pow10 0 = 1
#guard pow10 3 = 1000
#guard pow10 (-2) = 1/100

#guard ilog10 1 = 0
#guard ilog10 5 = 0
#guard ilog10 10 = 1
#guard ilog10 99 = 1
#guard ilog10 (3/10) = -1
#guard ilog10 (2/3) = -1
#guard ilog10 (1/10) = -1
#guard ilog10 (1/1000) = -3
#guard ilog10 1000000 = 6
#guard ilog10 0 = 0          -- documented junk-guard for q ≤ 0

-- The defining property 10^k ≤ q < 10^(k+1), checked across a battery.
#guard (#[(1 : Rat)/7, 3/10, 2/3, 1, 3/2, 7, 10, 123, 999/10, 1/1000,
    1000000, 22/7] : Array Rat).all fun q =>
  let k := ilog10 q
  pow10 k ≤ q && q < pow10 (k + 1)

/-! ## niceStep -/

#guard niceStep (1/30) = 1/20
#guard niceStep (6/5) = 2
#guard niceStep 1 = 1
#guard niceStep 2 = 2
#guard niceStep 3 = 5
#guard niceStep 7 = 10
#guard niceStep (1/2) = 1/2
#guard niceStep (3/20) = 1/5
#guard niceStep 100 = 100
#guard niceStep 0 = 1        -- documented junk-guard for raw ≤ 0

-- niceStep is the SMALLEST {1,2,5}·10^k value ≥ raw: it is ≥ raw, nice, and
-- stepping one notch down in {1,2,5}·10^k goes below raw.
#guard (#[(1 : Rat)/30, 6/5, 1, 3, 7, 1/2, 3/20, 100, 22/7, 999/1000] :
    Array Rat).all fun raw =>
  let s := niceStep raw
  let k := ilog10 s
  let mantissa := s / pow10 k
  let down :=  -- the next nice value strictly below s
    if mantissa = 1 then pow10 (k - 1) * 5
    else if mantissa = 2 then pow10 k
    else pow10 k * 2
  raw ≤ s && (mantissa = 1 || mantissa = 2 || mantissa = 5) && down < raw

/-! ## niceAxis: pins across magnitudes -/

#guard niceAxis 0 6 5 = { lo := 0, hi := 6, step := 2, ticks := #[0, 2, 4, 6] }
#guard niceAxis 0 1 5 =
  { lo := 0, hi := 1, step := 1/5, ticks := #[0, 1/5, 2/5, 3/5, 4/5, 1] }
#guard niceAxis (-5) 5 5 =
  { lo := -6, hi := 6, step := 2, ticks := #[-6, -4, -2, 0, 2, 4, 6] }
#guard niceAxis (1/3) (2/3) 5 =
  { lo := 3/10, hi := 7/10, step := 1/10,
    ticks := #[3/10, 2/5, 1/2, 3/5, 7/10] }
#guard niceAxis 0 1000000 5 =
  { lo := 0, hi := 1000000, step := 200000,
    ticks := #[0, 200000, 400000, 600000, 800000, 1000000] }
#guard niceAxis 2 12 6 =
  { lo := 2, hi := 12, step := 2, ticks := #[2, 4, 6, 8, 10, 12] }

-- Degenerate: single value → symmetric pad to [v-1, v+1] first.
#guard niceAxis 3 3 5 =
  { lo := 2, hi := 4, step := 1/2, ticks := #[2, 5/2, 3, 7/2, 4] }
#guard niceAxis 0 0 5 =
  { lo := -1, hi := 1, step := 1/2, ticks := #[-1, -1/2, 0, 1/2, 1] }

-- Degenerate: inverted bounds (the no-data convention) → the [0, 1] default.
#guard niceAxis 1 0 5 = niceAxis 0 1 5

-- Degenerate: target 0 is treated as 1.
#guard niceAxis 0 1 0 = { lo := 0, hi := 1, step := 1, ticks := #[0, 1] }

/-! ## niceAxis: properties over a battery of ranges -/

/-- The ranges the property checks run over. -/
def ranges : Array (Rat × Rat × Nat) := #[
  (0, 1, 5), (0, 6, 5), (-5, 5, 5), (1/3, 2/3, 5), (0, 1000000, 5),
  (3, 3, 5), (1, 0, 5), (2, 12, 6), (-1/7, 22/7, 4), (999, 1001, 5),
  (0, 1/1000, 5), (-3, -2, 7), (0, 1, 0), (5/7, 5/7, 3)]

-- Every produced axis passes its own self-check (step > 0, lo < hi, ticks an
-- in-bounds arithmetic progression).
#guard ranges.all fun (lo, hi, t) => (niceAxis lo hi t).selfCheck.isNone

-- Coverage: the niced range contains the data range (when lo ≤ hi).
#guard ranges.all fun (lo, hi, t) =>
  lo > hi || ((niceAxis lo hi t).lo ≤ lo && hi ≤ (niceAxis lo hi t).hi)

-- Ticks are strictly monotone.
#guard ranges.all fun (lo, hi, t) =>
  let a := niceAxis lo hi t
  (Array.range (a.ticks.size - 1)).all fun i => a.ticks[i]! < a.ticks[i+1]!

-- Nice axes tick exactly at both bounds.
#guard ranges.all fun (lo, hi, t) =>
  let a := niceAxis lo hi t
  a.ticks[0]! = a.lo && a.ticks.back! = a.hi

-- The tick count stays civilized (bounded by ~2·target + 2).
#guard ranges.all fun (lo, hi, t) =>
  (niceAxis lo hi t).ticks.size ≤ 2 * max t 1 + 2

/-! ## categoricalAxis -/

#guard categoricalAxis 3 =
  { lo := -1/2, hi := 5/2, step := 1, ticks := #[0, 1, 2] }
#guard categoricalAxis 1 =
  { lo := -1/2, hi := 1/2, step := 1, ticks := #[0] }
#guard categoricalAxis 0 = niceAxis 0 1  -- documented fallback
#guard (categoricalAxis 5).selfCheck.isNone
#guard (categoricalAxis 1).selfCheck.isNone

/-! ## Axis.selfCheck catches what it must -/

#guard (niceAxis 0 6 5).selfCheck.isNone
#guard ({ lo := 0, hi := 1, step := 0, ticks := #[0] } : Axis).selfCheck
  = some "axis step 0 is not positive"
#guard ({ lo := 1, hi := 1, step := 1, ticks := #[1] } : Axis).selfCheck
  = some "axis bounds [1, 1] are not ascending"
#guard ({ lo := 0, hi := 1, step := 1, ticks := #[] } : Axis).selfCheck
  = some "axis has no ticks"
#guard ({ lo := 0, hi := 1, step := 1, ticks := #[0, 2] } : Axis).selfCheck
  = some "some tick lies outside the axis bounds [0, 1]"
#guard ({ lo := 0, hi := 3, step := 1, ticks := #[0, 2] } : Axis).selfCheck
  = some "ticks are not an arithmetic progression with the axis step"

/-! ## AffineMap: exact pixel mapping -/

#guard ({ domLo := 0, domHi := 10, pixLo := 48, pixHi := 406 } :
    AffineMap).apply 5 = 227
#guard ({ domLo := 0, domHi := 10, pixLo := 48, pixHi := 406 } :
    AffineMap).apply 0 = 48
#guard ({ domLo := 0, domHi := 10, pixLo := 48, pixHi := 406 } :
    AffineMap).apply 10 = 406
-- Inverted (y-style) map: data up is pixel down.
#guard ({ domLo := 0, domHi := 4, pixLo := 94, pixHi := 14 } :
    AffineMap).apply 1 = 74
#guard ({ domLo := 0, domHi := 4, pixLo := 94, pixHi := 14 } :
    AffineMap).apply 4 = 14
-- Exact fractions stay exact: 1/3 of the way across [0, 300].
#guard ({ domLo := 0, domHi := 1, pixLo := 0, pixHi := 300 } :
    AffineMap).apply (1/3) = 100
-- Out-of-domain values extrapolate linearly (no clamping).
#guard ({ domLo := 0, domHi := 1, pixLo := 0, pixHi := 100 } :
    AffineMap).apply 2 = 200
-- Axis.toPixels endpoints.
#guard ((niceAxis 0 6 5).toPixels 48 186).apply 6 = 186
#guard ((niceAxis 0 6 5).toPixels 48 186).apply 0 = 48

/-! ## ratStr: exact decimal serialization -/

#guard ratStr 38 = "38"
#guard ratStr (-77/2) = "-38.5"
#guard ratStr (1/3) = "0.333333"
#guard ratStr (22/7) = "3.142857"
#guard ratStr (1/8) = "0.125"
#guard ratStr (-1/8) = "-0.125"
#guard ratStr (1/1000000) = "0.000001"
#guard ratStr (1/10000000) = "0"       -- documented truncation
#guard ratStr (-1/10000000) = "0"      -- negative truncation must not print "-0"
#guard ratStr 0 = "0"
#guard ratStr (5/2) = "2.5"
#guard ratStr (-200000) = "-200000"

/-! ## dataBounds? / axis selection -/

#guard lineSpec.dataBounds? = some ((0, 2), (0, 4))
-- Bars force the baseline 0 into the y bounds (data y ∈ [1, 4] here).
#guard barSpec.dataBounds? = some ((0, 2), (0, 4))
#guard ({ series := #[{ name := "e", mark := .bar, data := #[(0, -2)] }] } :
    ChartSpec).dataBounds? = some ((0, 0), (-2, 0))
-- Without bars, bounds are exactly the data's.
#guard ({ series := #[{ name := "l", data := #[(1, 2), (3, 5)] }] } :
    ChartSpec).dataBounds? = some ((1, 3), (2, 5))
-- No points at all (series present but empty): no bounds.
#guard ({ series := #[{ name := "e" }] } : ChartSpec).dataBounds? = none
-- Bounds are the union across series.
#guard ({ series := #[{ name := "a", data := #[(0, 1)] },
    { name := "b", data := #[(5, -1)] }] } : ChartSpec).dataBounds?
  = some ((0, 5), (-1, 1))

#guard lineSpec.xAxisOf = niceAxis 0 2 6
#guard lineSpec.yAxisOf = { lo := 0, hi := 4, step := 1, ticks := #[0, 1, 2, 3, 4] }
#guard catSpec.xAxisOf = categoricalAxis 2
-- Empty-data spec: both axes fall back to [0, 1].
#guard ({ series := #[{ name := "e" }] } : ChartSpec).xAxisOf
  = niceAxis 0 1 xTickTarget
#guard ({ series := #[{ name := "e" }] } : ChartSpec).yAxisOf
  = niceAxis 0 1 yTickTarget

end ChartKitTests
