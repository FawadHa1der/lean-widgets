import Mathlib
import ChartKit

/-! # ChartKit: exact-rational charts in the InfoView
Put the cursor on a `#chart` line: an "HTML Display" panel shows the chart as
a theme-aware SVG (click its summary to fold it).  All data, ticks and pixel
coordinates are exact `ℚ`, so the `#guard`s below check that the plotted data
*is* the theorem.  Marks: bar, step (CDF), line, scatter; plus a categorical axis. -/

open ChartKit
namespace Showcase.ChartKit

/-- Ways two dice sum to `s ∈ [2, 12]`: `6 - |s - 7|`. -/
def diceWays (s : Nat) : Nat := 6 - ((s : Int) - 7).natAbs

/-- `(s, P(sum = s))` in exact 36ths. -/
def dicePmf : Array (Rat × Rat) :=
  (Array.range 11).map fun i => (((i + 2 : Nat) : Rat), (diceWays (i + 2) : Rat) / 36)

/-- The running sum of `dicePmf`: the CDF. -/
def diceCdf : Array (Rat × Rat) :=
  (Array.range 11).map fun i =>
    (((i + 2 : Nat) : Rat), (((List.range (i + 1)).map (diceWays ·.succ.succ)).sum : Rat) / 36)

#guard dicePmf.foldl (fun acc (_, p) => acc + p) 0 = 1   -- the masses sum to 1
#guard diceCdf.back?.map (·.2) = some 1                  -- the CDF ends at 1

def diceChart : ChartSpec := {
  title? := some "Sum of two dice", xLabel := "sum", yLabel := "probability",
  series := #[{ name := "P(sum)", mark := .bar, data := dicePmf }] }
#chart diceChart

def cdfChart : ChartSpec := {
  title? := some "CDF of two dice", xLabel := "sum", yLabel := "P(sum <= s)",
  series := #[{ name := "cdf", mark := .step, data := diceCdf }] }
#chart cdfChart

-- Two line series with a legend: n²/10 against 2ⁿ/10.
#chart { title? := some "n^2/10 vs 2^n/10", xLabel := "n",
         series := #[
           { name := "n^2/10", mark := .line,
             data := (Array.range 9).map fun (n : Nat) => ((n : Rat), ((n * n : Nat) : Rat) / 10) },
           { name := "2^n/10", mark := .line,
             data := (Array.range 9).map fun (n : Nat) => ((n : Rat), ((2 ^ n : Nat) : Rat) / 10) }] }

-- Scatter: the quadratic residues mod 11.
#chart { title? := some "n^2 mod 11", showLegend := false,
         series := #[
           { name := "n^2 mod 11", mark := .scatter,
             data := (Array.range 11).map fun (n : Nat) => ((n : Rat), ((n * n % 11 : Nat) : Rat)) }] }

-- Categorical x axis with exact value labels above the bars.
def weekChart : ChartSpec := {
  title? := some "Commits per weekday", yLabel := "commits",
  series := #[{ name := "commits", mark := .bar,
                data := #[(0, 12), (1, 17), (2, 8), (3, 21), (4, 5)] }],
  xTickLabels := #["Mon", "Tue", "Wed", "Thu", "Fri"], valueLabels := true, showLegend := false }
#chart weekChart

end Showcase.ChartKit
