import ChartKit.Model

/-! # ChartKit: exact `Float → ℚ` conversion

Core Lean (checked on v4.32.2 and v4.34.0) has no ready-made exact
`Float → Rat` (there is no `Float.toRatParts`; `Float.frExp` returns the
mantissa as another `Float`).
But `Float.toBits : Float → UInt64` is a **bit-for-bit** view of the IEEE 754
double, and every finite double is by definition an exact rational
`±(2^52 + mantissa) · 2^(exponent - 1075)` (or `±mantissa · 2^-1074` for
subnormals).  `floatToRat?` decodes those bits directly, so the conversion is

* **exact** — the resulting `Rat` is the precise real number the double
  represents (e.g. `0.1` becomes `3602879701896397/36028797018963968`, *not*
  `1/10` — the double never was `1/10`); and
* **honest** — NaN and ±∞ have no rational value and return `none`.

`Series.ofFloats` builds a `Series` from float pairs, refusing (with the
offending index and coordinate) if any value is non-finite.
-/

namespace ChartKit

/-- `2^k : ℚ` for `k : ℤ` (exact). -/
def pow2 (k : Int) : Rat :=
  (2 : Rat) ^ k

/-- Exact rational value of a `Float`: `none` for NaN and ±∞, otherwise
`some q` where `q` is *precisely* the real number the IEEE 754 double
represents (decoded bit-for-bit from `Float.toBits`; see the module
docstring).  `-0.0` maps to `0`. -/
def floatToRat? (x : Float) : Option Rat :=
  let bits := x.toBits.toNat
  let sign := bits >>> 63
  let expo := (bits >>> 52) % 2048        -- 11 exponent bits
  let mant := bits % 2 ^ 52               -- 52 mantissa bits
  if expo = 2047 then none                -- NaN / ±∞
  else
    let mag : Rat :=
      if expo = 0 then
        -- Subnormal (or zero): no implicit leading bit, exponent −1074.
        ((mant : Nat) : Rat) * pow2 (-1074)
      else
        -- Normal: implicit leading bit, value (2^52 + mant) · 2^(expo − 1075).
        (((2 ^ 52 + mant : Nat) : Rat)) * pow2 ((expo : Int) - 1075)
    some (if sign = 1 then -mag else mag)

/-- Build a series from float data by **exact** conversion (`floatToRat?`).
Fails honestly, naming the point index and coordinate, if any value is NaN or
±∞.  Remember the values are the exact doubles: `0.1` is
`3602879701896397/36028797018963968`. -/
def Series.ofFloats (name : String) (data : Array (Float × Float))
    (mark : Mark := .line) (color? : Option String := none) :
    Except String Series := do
  let mut pts : Array (Rat × Rat) := #[]
  for i in [0:data.size] do
    let (x, y) := data[i]!
    let some qx := floatToRat? x
      | throw s!"series \"{name}\" point {i}: x = {x} is not finite — \
          ChartKit only charts exact values"
    let some qy := floatToRat? y
      | throw s!"series \"{name}\" point {i}: y = {y} is not finite — \
          ChartKit only charts exact values"
    pts := pts.push (qx, qy)
  return { name, mark, data := pts, color? }

end ChartKit
