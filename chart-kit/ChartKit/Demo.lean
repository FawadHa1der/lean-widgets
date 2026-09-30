import ChartKit.Widget
import ChartKit.FloatBridge

/-! # ChartKit: demos

Realistic charts, each elaborated (and its panel attached) on every build.
All data is exact `ℚ` computed *in Lean* — including `#guard`'d examples
where the charted data is literally the statement being verified ("the chart
IS the theorem's data").

Open this file in the editor and put the cursor on a `#chart` line to see the
panel; the `(text := true)` variant shows the deterministic report the test
suite pins.
-/

namespace ChartKit.Demo

open ChartKit

/-! ## 1. Bar chart: distribution of the sum of two dice (exact 36ths) -/

/-- Number of ways two dice sum to `s` (for `s ∈ [2, 12]`): `6 - |s - 7|`. -/
def diceWays (s : Nat) : Nat := 6 - ((s : Int) - 7).natAbs

/-- Points `(s, P(sum = s))` for `s = 2, …, 12`, exact 36ths. -/
def dicePmf : Array (Rat × Rat) :=
  (Array.range 11).map fun i =>
    let s : Nat := i + 2
    ((s : Rat), ((diceWays s : Nat) : Rat) / 36)

-- The pmf is a probability distribution: the exact masses sum to 1.
#guard dicePmf.foldl (fun acc (_, p) => acc + p) 0 = 1

/-- Bar chart of the two-dice distribution. -/
def diceChart : ChartSpec := {
  title? := some "Sum of two dice",
  xLabel := "sum", yLabel := "probability",
  series := #[{ name := "P(sum)", mark := .bar, data := dicePmf }] }

#chart diceChart

/-! ## 2. Two-series line chart: quadratic vs. exponential growth -/

/-- Points `(n, n²/10)` for `n = 0, …, 8`, exact. -/
def squaresData : Array (Rat × Rat) :=
  (Array.range 9).map fun (n : Nat) => ((n : Rat), ((n * n : Nat) : Rat) / 10)

/-- Points `(n, 2ⁿ/10)` for `n = 0, …, 8`, exact. -/
def powersData : Array (Rat × Rat) :=
  (Array.range 9).map fun (n : Nat) => ((n : Rat), ((2 ^ n : Nat) : Rat) / 10)

/-- Line chart comparing `n²/10` with `2ⁿ/10` on `n = 0, …, 8` (exact). -/
def growthChart : ChartSpec := {
  title? := some "n^2/10 vs 2^n/10",
  xLabel := "n",
  series := #[
    { name := "n^2/10", mark := .line, data := squaresData },
    { name := "2^n/10", mark := .line, data := powersData }] }

#chart growthChart

/-! ## 3. CDF staircase: the two-dice sum, cumulative -/

/-- Points `(s, P(sum ≤ s))`, the exact running sum of `dicePmf`.  Drawn with
the `step` mark: horizontal-then-vertical, the CDF convention. -/
def diceCdf : Array (Rat × Rat) := Id.run do
  let mut acc : Rat := 0
  let mut out : Array (Rat × Rat) := #[]
  for (s, p) in dicePmf do
    acc := acc + p
    out := out.push (s, acc)
  return out

-- The chart IS the theorem's data: the CDF is monotone and reaches exactly 1.
#guard diceCdf.back?.map (·.2) = some 1
#guard (Array.range (diceCdf.size - 1)).all fun i =>
  diceCdf[i]!.2 ≤ diceCdf[i+1]!.2

/-- Staircase chart of the two-dice CDF. -/
def cdfChart : ChartSpec := {
  title? := some "CDF of two dice",
  xLabel := "sum", yLabel := "P(sum <= s)",
  series := #[{ name := "cdf", mark := .step, data := diceCdf }] }

#chart cdfChart

/-! ## 4. Scatter plot: squares modulo 11 -/

/-- Points `(n, n² mod 11)` for `n = 0, …, 10`, exact. -/
def residueData : Array (Rat × Rat) :=
  (Array.range 11).map fun (n : Nat) =>
    ((n : Rat), (((n * n) % 11 : Nat) : Rat))

/-- Scatter of `(n, n² mod 11)` for `n = 0, …, 10` — the quadratic-residue
pattern, symmetric about `n = 11/2`. -/
def squaresChart : ChartSpec := {
  title? := some "n^2 mod 11",
  xLabel := "n",
  series := #[{ name := "n^2 mod 11", mark := .scatter, data := residueData }],
  showLegend := false }

#chart squaresChart

/-! ## 5. Categorical bar chart with labels -/

/-- Commits per weekday, with categorical x labels (points must sit at
`x = 0, 1, …` — one per label; validated). -/
def weekData : Array (Rat × Rat) := #[(0, 12), (1, 17), (2, 8), (3, 21), (4, 5)]

/-- The categorical weekday bar chart itself. -/
def weekChart : ChartSpec := {
  title? := some "Commits per weekday",
  yLabel := "commits",
  series := #[{ name := "commits", mark := .bar, data := weekData }],
  xTickLabels := #["Mon", "Tue", "Wed", "Thu", "Fri"],
  valueLabels := true,
  showLegend := false }

#chart weekChart

/-! ## 6. Exact floats: charting doubles without lying about them -/

/-- The exact rational values of the doubles `0.1 · n` for `n = 0, …, 5` —
note these are the *true* IEEE 754 values, not tenths: `floatToRat? 0.1` is
`3602879701896397/36028797018963968`.  Falls back to an empty marker series
if conversion failed (it cannot: the inputs are finite — pinned by the
`#guard`s below). -/
def floatSeries : Series :=
  match Series.ofFloats "0.1*n (exact doubles)"
      ((Array.range 6).map fun n => (Float.ofNat n, 0.1 * Float.ofNat n)) with
  | .ok s => s
  | .error _ => { name := "unreachable" }

-- The double 0.1 really is not 1/10 — and ChartKit charts the truth.
#guard floatToRat? 0.1 = some (3602879701896397 / 36028797018963968)
#guard floatSeries.data.size = 6
#guard (floatSeries.data[1]?.map (·.2)) ≠ some (1/10)

/-- Scatter chart of the exact double values. -/
def floatChart : ChartSpec := {
  title? := some "0.1*n as exact doubles",
  series := #[{ floatSeries with mark := .scatter }],
  showLegend := false }

#chart floatChart

/-! ## Text mode -/

/--
info: chart "Sum of two dice" (420x260): 1 series, 11 points
x [2, 12] step 2, ticks: 2 4 6 8 10 12
y [0, 0.2] step 0.05, ticks: 0 0.05 0.1 0.15 0.2
series 0 "P(sum)": bar, 11 points
-/
#guard_msgs in
#chart (text := true) diceChart

end ChartKit.Demo
