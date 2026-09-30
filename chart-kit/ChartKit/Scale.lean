import ChartKit.Model

/-! # ChartKit: exact scales, nice ticks and pixel mapping

The mathematical heart of the package — **everything here is exact `ℚ`; there
is no `Float` anywhere in ChartKit**.

* `natLog10` / `ilog10` — integer base-10 logarithm, on `ℕ` and on positive
  `ℚ` (`ilog10 q` is the unique `k : ℤ` with `10^k ≤ q < 10^(k+1)`);
* `niceStep` — the *smallest* value of the form `{1, 2, 5} · 10^k` (`k : ℤ`)
  that is `≥` the raw step, computed exactly;
* `niceAxis` — nice bounds and ticks: the data range is widened outward to
  multiples of the nice step, and ticks placed at every multiple in between
  (so the first tick is exactly `lo`, the last exactly `hi`, and consecutive
  ticks differ by exactly `step`);
* `categoricalAxis` — the fixed axis `[-1/2, n - 1/2]` with integer ticks
  `0, …, n-1` used when `xTickLabels` is set;
* `AffineMap` — the exact affine `ℚ → ℚ` data-to-pixel map;
* `ratStr` — deterministic decimal serialization of a `Rat` (truncated at 6
  fractional digits, trailing zeros stripped) used for every SVG coordinate
  and tick label;
* `ChartSpec.dataBounds?` / `xAxisOf` / `yAxisOf` — the bounds and axes of a
  chart (degenerate ranges get the documented fallbacks).

Every function is total and deterministic; `Axis.selfCheck` re-checks the
axis invariants at render time so an extraction/scale bug turns into an honest
error instead of a silently wrong picture.
-/

namespace ChartKit

/-- Number of decimal digits of `n` minus one: `natLog10 n = k` iff
`10^k ≤ n < 10^(k+1)` (for `n ≥ 1`; `natLog10 0 = 0` by convention). -/
def natLog10 (n : Nat) : Nat :=
  if n < 10 then 0 else natLog10 (n / 10) + 1
decreasing_by exact Nat.div_lt_self (by omega) (by omega)

/-- `10^k : ℚ` for `k : ℤ` (exact; negative exponents give exact fractions). -/
def pow10 (k : Int) : Rat :=
  (10 : Rat) ^ k

/-- Integer base-10 logarithm of a positive rational: the unique `k : ℤ` with
`10^k ≤ q < 10^(k+1)`.  Total: returns `0` for `q ≤ 0` (never meaningful —
callers only pass positive values, and `niceStep` guards on its own). -/
def ilog10 (q : Rat) : Int :=
  if q ≤ 0 then 0
  else if 1 ≤ q then
    (natLog10 q.floor.toNat : Int)
  else
    -- 0 < q < 1: with r = 1/q > 1 and t = ⌊log10 r⌋, the answer is -t when
    -- r is exactly a power of 10 and -(t+1) otherwise.
    let r := 1 / q
    let t := natLog10 r.floor.toNat
    if pow10 (t : Int) = r then -(t : Int) else -((t : Int) + 1)

/-- The smallest *nice* step `≥ raw`: nice steps are `1·10^k`, `2·10^k` and
`5·10^k` for `k : ℤ`.  Total: returns `1` for `raw ≤ 0` (callers only pass
positive raw steps). -/
def niceStep (raw : Rat) : Rat :=
  if raw ≤ 0 then 1
  else
    let b := pow10 (ilog10 raw)  -- b ≤ raw < 10b
    if raw ≤ b then b
    else if raw ≤ 2 * b then 2 * b
    else if raw ≤ 5 * b then 5 * b
    else 10 * b

/-- An axis: exact bounds `lo < hi`, the tick step, and the tick positions —
an arithmetic progression with difference `step`, contained in `[lo, hi]`.
For nice axes (`niceAxis`) the first tick is exactly `lo` and the last
exactly `hi`; the categorical axis pads its bounds half a slot beyond the
first/last tick.  The shared invariants are re-checkable via
`Axis.selfCheck`. -/
structure Axis where
  /-- Lower bound (also the first tick). -/
  lo : Rat
  /-- Upper bound (also the last tick). -/
  hi : Rat
  /-- Tick step (positive). -/
  step : Rat
  /-- Tick positions, an ascending arithmetic progression within `[lo, hi]`. -/
  ticks : Array Rat
  deriving Repr, DecidableEq, Inhabited

/-- Nice axis over a data range: the step is `niceStep ((hi - lo)/target)`,
the bounds are the data range widened *outward* to multiples of the step, and
ticks sit at every multiple in between.

Degenerate inputs (documented fallbacks, all exercised by tests):
* `dataLo = dataHi = v` — the range is first widened to `[v - 1, v + 1]`;
* `dataLo > dataHi` (no data) — the range `[0, 1]` is used;
* `target = 0` is treated as `1`.

Guaranteed (re-checked by `Axis.selfCheck` and pinned by tests):
`lo ≤ dataLo ≤ dataHi ≤ hi`, `lo < hi`, `step > 0`, `ticks.head = lo`,
`ticks.last = hi`, consecutive ticks differ by exactly `step`. -/
def niceAxis (dataLo dataHi : Rat) (target : Nat := 5) : Axis :=
  let (lo, hi) :=
    if dataLo > dataHi then ((0 : Rat), (1 : Rat))
    else if dataLo = dataHi then (dataLo - 1, dataLo + 1)
    else (dataLo, dataHi)
  let t : Rat := ((max target 1 : Nat) : Rat)
  let step := niceStep ((hi - lo) / t)
  let lo' := step * (((lo / step).floor : Int) : Rat)
  let hi' := step * (((hi / step).ceil : Int) : Rat)
  -- (hi' - lo') / step is a nonnegative integer by construction.
  let count := ((hi' - lo') / step).floor.toNat
  { lo := lo', hi := hi', step
    ticks := (Array.range (count + 1)).map fun i => lo' + step * ((i : Nat) : Rat) }

/-- The categorical x axis for `n` labels: bounds `[-1/2, n - 1/2]` (a half
slot of padding on each side, so bars centered on integer positions fit), step
`1`, ticks at `0, 1, …, n-1`.  For `n = 0` (never produced: categorical means
non-empty labels) falls back to `niceAxis 0 1`. -/
def categoricalAxis (n : Nat) : Axis :=
  if n = 0 then niceAxis 0 1
  else
    { lo := -(1/2 : Rat), hi := ((n : Nat) : Rat) - (1/2 : Rat), step := 1
      ticks := (Array.range n).map fun i => ((i : Nat) : Rat) }

/-- `none` if the axis invariants hold; otherwise a message naming the first
violated invariant.  Used by `renderChart` as a self-check: a `some` result
means a ChartKit bug, reported honestly instead of drawing a wrong picture. -/
def Axis.selfCheck (a : Axis) : Option String :=
  if a.step ≤ 0 then some s!"axis step {a.step} is not positive"
  else if a.hi ≤ a.lo then some s!"axis bounds [{a.lo}, {a.hi}] are not ascending"
  else if a.ticks.isEmpty then some "axis has no ticks"
  else if a.ticks.any (fun t => t < a.lo || a.hi < t) then
    some s!"some tick lies outside the axis bounds [{a.lo}, {a.hi}]"
  else if (Array.range (a.ticks.size - 1)).any
      (fun i => a.ticks[i+1]! - a.ticks[i]! ≠ a.step) then
    some "ticks are not an arithmetic progression with the axis step"
  else none

/-- An exact affine map from a data interval to a pixel interval (for the y
axis, `pixLo > pixHi`: SVG pixel y grows downward). -/
structure AffineMap where
  /-- Domain lower endpoint (must differ from `domHi`). -/
  domLo : Rat
  /-- Domain upper endpoint. -/
  domHi : Rat
  /-- Pixel image of `domLo`. -/
  pixLo : Rat
  /-- Pixel image of `domHi`. -/
  pixHi : Rat
  deriving Repr, DecidableEq, Inhabited

/-- Apply the affine map: `domLo ↦ pixLo`, `domHi ↦ pixHi`, linear (exact)
in between.  Total: for the degenerate `domLo = domHi` (never produced —
axes guarantee `lo < hi`) core's `x / 0 = 0` makes the result `pixLo`. -/
def AffineMap.apply (m : AffineMap) (v : Rat) : Rat :=
  m.pixLo + (v - m.domLo) * (m.pixHi - m.pixLo) / (m.domHi - m.domLo)

/-- The affine map sending an axis onto a pixel interval. -/
def Axis.toPixels (a : Axis) (pixLo pixHi : Rat) : AffineMap :=
  { domLo := a.lo, domHi := a.hi, pixLo, pixHi }

/-! ## Exact decimal serialization -/

/-- Render an exact `Rat` as a decimal string: sign, integer part, then up to
**6 fractional digits by long division, truncated** (not rounded), trailing
zeros stripped (`38 → "38"`, `-77/2 → "-38.5"`, `1/3 → "0.333333"`).
Deterministic; exact for every rational whose reduced denominator divides
`10^6` (in particular for all chart geometry, which only ever divides by
axis ranges, `2`, `5` and tick counts — non-exact cases are tick labels of
thirds and the like, documented in the README). -/
def ratStr (q : Rat) : String := Id.run do
  let sign := if q.num < 0 then "-" else ""
  let n := q.num.natAbs
  let d := q.den
  let ip := n / d
  let mut r := n % d
  let mut digits : Array Nat := #[]
  for _ in [0:6] do
    if r == 0 then break
    r := r * 10
    digits := digits.push (r / d)
    r := r % d
  while digits.back? == some 0 do
    digits := digits.pop
  if digits.isEmpty then
    -- A negative value whose digits all truncated away must not print "-0".
    return if ip == 0 then "0" else s!"{sign}{ip}"
  return s!"{sign}{ip}." ++ digits.foldl (fun acc k => acc ++ toString k) ""

/-! ## Chart bounds and axes -/

/-- The exact data bounds of a spec across all series, as
`((xLo, xHi), (yLo, yHi))`, or `none` when there are no points at all.
When any series is a `bar`, the y bounds are widened to include the baseline
`0` (bars rise from `y = 0`, which must therefore be on the axis). -/
def ChartSpec.dataBounds? (spec : ChartSpec) :
    Option ((Rat × Rat) × (Rat × Rat)) := Id.run do
  let mut acc : Option ((Rat × Rat) × (Rat × Rat)) := none
  for s in spec.series do
    for (x, y) in s.data do
      acc := some <| match acc with
        | none => ((x, x), (y, y))
        | some ((xlo, xhi), (ylo, yhi)) =>
          ((min xlo x, max xhi x), (min ylo y, max yhi y))
  if spec.hasBars then
    if let some ((xlo, xhi), (ylo, yhi)) := acc then
      acc := some ((xlo, xhi), (min ylo 0, max yhi 0))
  return acc

/-- Default number of x ticks aimed for by `xAxisOf`. -/
def xTickTarget : Nat := 6

/-- Default number of y ticks aimed for by `yAxisOf`. -/
def yTickTarget : Nat := 5

/-- The x axis of a spec: `categoricalAxis` when `xTickLabels` is set,
otherwise a nice axis over the x data bounds (`[0, 1]` when there is no
data). -/
def ChartSpec.xAxisOf (spec : ChartSpec) : Axis :=
  if spec.isCategorical then categoricalAxis spec.xTickLabels.size
  else match spec.dataBounds? with
    | some ((xlo, xhi), _) => niceAxis xlo xhi xTickTarget
    | none => niceAxis 0 1 xTickTarget

/-- The y axis of a spec: a nice axis over the y data bounds — which include
the baseline `0` when any series is a bar (`ChartSpec.dataBounds?`) — or over
`[0, 1]` when there is no data. -/
def ChartSpec.yAxisOf (spec : ChartSpec) : Axis :=
  match spec.dataBounds? with
  | some (_, (ylo, yhi)) => niceAxis ylo yhi yTickTarget
  | none => niceAxis 0 1 yTickTarget

end ChartKit
