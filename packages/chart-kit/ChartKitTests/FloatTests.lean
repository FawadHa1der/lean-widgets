import ChartKitTests.Helpers

/-! # Float-bridge tests

Pins of the exact IEEE-754 → ℚ decoder: dyadic values convert to exactly
themselves, decimal-looking doubles convert to their *true* binary values
(`0.1` is not `1/10`), subnormals and signed zeros work, and non-finite
values are refused — both by `floatToRat?` and by `Series.ofFloats` (with the
index-naming error message pinned).
-/

namespace ChartKitTests

open ChartKit

/-! ## pow2 -/

#guard pow2 0 = 1
#guard pow2 10 = 1024
#guard pow2 (-3) = 1/8

/-! ## Exactly representable values round-trip exactly -/

#guard floatToRat? 0.0 = some 0
#guard floatToRat? 1.0 = some 1
#guard floatToRat? (-1.0) = some (-1)
#guard floatToRat? 0.5 = some (1/2)
#guard floatToRat? 0.25 = some (1/4)
#guard floatToRat? (-0.75) = some (-3/4)
#guard floatToRat? 3.0 = some 3
#guard floatToRat? 1024.0 = some 1024
#guard floatToRat? 0.1 ≠ some (1/10)   -- the whole point
#guard floatToRat? (-0.0) = some 0     -- signed zero collapses

-- Large exact integers: 2^53 (the last contiguous integer) and a big power.
#guard floatToRat? 9007199254740992.0 = some 9007199254740992
#guard floatToRat? (Float.ofNat (2 ^ 60)) = some ((2 : Rat) ^ (60 : Nat))

/-! ## The true values of decimal literals -/

-- 0.1 as a double is exactly 3602879701896397 / 2^55.
#guard floatToRat? 0.1 = some (3602879701896397 / 36028797018963968)
-- 0.2 is exactly twice that (same mantissa, next exponent).
#guard floatToRat? 0.2 = some (3602879701896397 / 18014398509481984)
-- 0.1 + 0.2 ≠ 0.3 — visible exactly through the decoder.
#guard (floatToRat? (0.1 + 0.2)) ≠ (floatToRat? 0.3)

/-! ## Subnormals and extremes -/

-- The smallest positive subnormal double is exactly 2^-1074.
#guard floatToRat? 5e-324 = some (pow2 (-1074))
-- The largest finite double: (2^53 - 1) · 2^971.
#guard floatToRat? 1.7976931348623157e308
  = some ((2 ^ 53 - 1 : Nat) * pow2 971)

/-! ## Non-finite values are refused -/

#guard floatToRat? (1.0 / 0.0) = none
#guard floatToRat? (-1.0 / 0.0) = none
#guard floatToRat? (0.0 / 0.0) = none    -- NaN

/-! ## Series.ofFloats -/

-- Success: exact conversion of every point, in order.
#guard (okD (Series.ofFloats "s" #[(0.0, 0.5), (1.0, 0.25)])).data
  = #[(0, 1/2), (1, 1/4)]
#guard (okD (Series.ofFloats "s" #[] .bar)).mark = Mark.bar
#guard (okD (Series.ofFloats "s" #[(1.0, 1.0)] .line (some "red"))).color?
  = some "red"

-- Refusal names the series, the point index and the coordinate.
#guard errD (Series.ofFloats "bad" #[(0.0, 0.0), (1.0 / 0.0, 1.0)])
  = "series \"bad\" point 1: x = inf is not finite — ChartKit only charts \
     exact values"
#guard errD (Series.ofFloats "bad" #[(0.0, 0.0 / 0.0)])
  = "series \"bad\" point 0: y = NaN is not finite — ChartKit only charts \
     exact values"

end ChartKitTests
