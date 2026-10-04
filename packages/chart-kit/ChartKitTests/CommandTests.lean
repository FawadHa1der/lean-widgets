import ChartKitTests.Helpers

/-! # `#chart` command tests

Message-exact `#guard_msgs` pins of the deterministic `(text := true)` mode —
the shared test specs, every shipped demo chart, degenerate specs — plus
every user-facing error message: invalid specs (with the full joined error
list), metavariables, `sorry`, and noncomputable constants.
-/

namespace ChartKitTests

open ChartKit ChartKit.Demo

/-! ## Text mode: shared specs -/

/--
info: chart (200x150): 1 series, 3 points
x [0, 2] step 0.5, ticks: 0 0.5 1 1.5 2
y [0, 4] step 1, ticks: 0 1 2 3 4
series 0 "f": line, 3 points
-/
#guard_msgs in
#chart (text := true) lineSpec

/--
info: chart (200x150): 1 series, 2 points
x [-0.5, 1.5] step 1, ticks: 0 1
y [0, 3] step 1, ticks: 0 1 2 3
x-labels: a, b
series 0 "n": bar, 2 points
-/
#guard_msgs in
#chart (text := true) catSpec

/--
info: chart "Full" (420x260): 2 series, 4 points
x [0, 1] step 0.2, ticks: 0 0.2 0.4 0.6 0.8 1
y [0, 2] step 0.5, ticks: 0 0.5 1 1.5 2
series 0 "l": line, 2 points
series 1 "b": bar, 2 points
-/
#guard_msgs in
#chart (text := true) fullSpec

/-! ## Text mode: the shipped demos -/

/--
info: chart "n^2/10 vs 2^n/10" (420x260): 2 series, 18 points
x [0, 8] step 2, ticks: 0 2 4 6 8
y [0, 30] step 10, ticks: 0 10 20 30
series 0 "n^2/10": line, 9 points
series 1 "2^n/10": line, 9 points
-/
#guard_msgs in
#chart (text := true) growthChart

/--
info: chart "CDF of two dice" (420x260): 1 series, 11 points
x [2, 12] step 2, ticks: 2 4 6 8 10 12
y [0, 1] step 0.2, ticks: 0 0.2 0.4 0.6 0.8 1
series 0 "cdf": step, 11 points
-/
#guard_msgs in
#chart (text := true) cdfChart

/--
info: chart "Commits per weekday" (420x260): 1 series, 5 points
x [-0.5, 4.5] step 1, ticks: 0 1 2 3 4
y [0, 25] step 5, ticks: 0 5 10 15 20 25
x-labels: Mon, Tue, Wed, Thu, Fri
series 0 "commits": bar, 5 points
-/
#guard_msgs in
#chart (text := true) weekChart

/--
info: chart "0.1*n as exact doubles" (420x260): 1 series, 6 points
x [0, 5] step 1, ticks: 0 1 2 3 4 5
y [0, 0.5] step 0.1, ticks: 0 0.1 0.2 0.3 0.4 0.5
series 0 "0.1*n (exact doubles)": scatter, 6 points
-/
#guard_msgs in
#chart (text := true) floatChart

/--
info: chart "n^2 mod 11" (420x260): 1 series, 11 points
x [0, 10] step 2, ticks: 0 2 4 6 8 10
y [0, 10] step 2, ticks: 0 2 4 6 8 10
series 0 "n^2 mod 11": scatter, 11 points
-/
#guard_msgs in
#chart (text := true) squaresChart

/-! ## Text mode: degenerate specs -/

/-- An empty series: valid, charts the default [0, 1] axes. -/
def emptySeriesSpec : ChartSpec := { series := #[{ name := "empty" }] }

/--
info: chart (420x260): 1 series, 0 points
x [0, 1] step 0.2, ticks: 0 0.2 0.4 0.6 0.8 1
y [0, 1] step 0.2, ticks: 0 0.2 0.4 0.6 0.8 1
series 0 "empty": line, 0 points
-/
#guard_msgs in
#chart (text := true) emptySeriesSpec

/-- One single point: both ranges degenerate, symmetric padding kicks in. -/
def onePointSpec : ChartSpec :=
  { series := #[{ name := "pt", mark := .scatter, data := #[(3, 7)] }] }

/--
info: chart (420x260): 1 series, 1 point
x [2, 4] step 0.5, ticks: 2 2.5 3 3.5 4
y [6, 8] step 0.5, ticks: 6 6.5 7 7.5 8
series 0 "pt": scatter, 1 point
-/
#guard_msgs in
#chart (text := true) onePointSpec

/-- A flat line: zero y-range, padded symmetrically. -/
def zeroRangeSpec : ChartSpec :=
  { series := #[{ name := "z", data := #[(0, 5), (1, 5)] }] }

/--
info: chart (420x260): 1 series, 2 points
x [0, 1] step 0.2, ticks: 0 0.2 0.4 0.6 0.8 1
y [4, 6] step 0.5, ticks: 4 4.5 5 5.5 6
series 0 "z": line, 2 points
-/
#guard_msgs in
#chart (text := true) zeroRangeSpec

-- Structure literals work directly (term:max), inline.
/--
info: chart (420x260): 1 series, 2 points
x [0, 1] step 0.2, ticks: 0 0.2 0.4 0.6 0.8 1
y [0, 2] step 0.5, ticks: 0 0.5 1 1.5 2
series 0 "inline": line, 2 points
-/
#guard_msgs in
#chart (text := true) { series := #[{ name := "inline", data := #[(0, 0), (1, 2)] }] }

/-! ## Honest errors -/

/--
error: #chart: invalid chart spec — the chart has no series — nothing to draw
-/
#guard_msgs in
#chart (text := true) ({} : ChartSpec)

-- Invalid specs are refused in panel mode too, with ALL problems listed.
/--
error: #chart: invalid chart spec — the chart has no series — nothing to draw; width 20 is outside the supported range [100, 2000]
-/
#guard_msgs in
#chart ({ width := 20 } : ChartSpec)

/-- A categorical spec whose series length disagrees with its labels. -/
def mismatchedSpec : ChartSpec :=
  { series := #[{ name := "c", data := #[(0, 1)] }], xTickLabels := #["a", "b"] }

/--
error: #chart: invalid chart spec — series "c" has 1 points but there are 2 x-tick labels — a categorical chart needs exactly one point per label
-/
#guard_msgs in
#chart mismatchedSpec

/--
error: #chart: the spec still contains metavariables (`_`) — fill in the underscores so the chart is fully determined
-/
#guard_msgs in
#chart _

/--
error: #chart: the spec contains `sorry` — fill it in so the chart is fully determined
-/
#guard_msgs in
#chart (sorry : ChartSpec)

/-- A noncomputable spec (the compiler could never evaluate it). -/
noncomputable def ncSpec : ChartSpec := Classical.choice ⟨{}⟩

/--
error: #chart: the spec uses the noncomputable constant `ChartKitTests.ncSpec` — ChartKit evaluates the spec with compiled code, so it must be computable
-/
#guard_msgs in
#chart ncSpec

end ChartKitTests
