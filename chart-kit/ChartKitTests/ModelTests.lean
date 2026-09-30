import ChartKitTests.Helpers

/-! # Model / validation tests

Pins of `ChartSpec.validationErrors` — every rule, with the exact honest
message (naming the offending series and the actual/limit sizes) — plus the
degenerate-spec behavior of the top-level renderers (`renderChart` /
`textReport` refuse invalid specs and accept degenerate-but-valid ones).
-/

namespace ChartKitTests

open ChartKit

/-! ## Fixtures -/

/-- `n` collinear points `(i, 0)`. -/
def manyPoints (n : Nat) : Array (Rat × Rat) :=
  (Array.range n).map fun (i : Nat) => ((i : Rat), 0)

/-- `n` empty series. -/
def manySeries (n : Nat) : Array Series :=
  (Array.range n).map fun i => { name := s!"s{i}" }

/-- A single-series spec with `n` points. -/
def bigSpec (n : Nat) : ChartSpec :=
  { series := #[{ name := "big", data := manyPoints n }] }

/-- Categorical spec: one point, two labels (wrong count). -/
def catMismatchSpec : ChartSpec :=
  { series := #[{ name := "c", data := #[(0, 1)] }], xTickLabels := #["a", "b"] }

/-- Categorical spec: two points but the second at `x = 5` (wrong position). -/
def catMisplacedSpec : ChartSpec :=
  { series := #[{ name := "c", data := #[(0, 1), (5, 2)] }],
    xTickLabels := #["a", "b"] }

/-- A flat three-point line (zero y-range). -/
def flatSpec : ChartSpec :=
  { series := #[{ name := "z", data := #[(0, 5), (1, 5), (2, 5)] }] }

/-- Two points at the same x (zero x-range). -/
def verticalSpec : ChartSpec :=
  { series := #[{ name := "v", data := #[(3, 0), (3, 1)] }] }

/-! ## Mark and simple accessors -/

#guard Mark.bar.name = "bar"
#guard Mark.line.name = "line"
#guard Mark.step.name = "step"
#guard Mark.scatter.name = "scatter"

#guard lineSpec.pointCount = 3
#guard fullSpec.pointCount = 4
#guard ({} : ChartSpec).pointCount = 0
#guard catSpec.isCategorical = true
#guard lineSpec.isCategorical = false
#guard barSpec.hasBars = true
#guard lineSpec.hasBars = false

/-! ## Validation: the valid ones -/

#guard lineSpec.validationErrors = #[]
#guard barSpec.validationErrors = #[]
#guard catSpec.validationErrors = #[]
#guard paletteSpec.validationErrors = #[]
-- Degenerate but valid: an empty series, a one-point series.
#guard ({ series := #[{ name := "e" }] } : ChartSpec).isValid
#guard ({ series := #[{ name := "p", data := #[(1, 1)] }] } : ChartSpec).isValid

/-! ## Validation: each rule, with its exact message -/

-- No series at all.
#guard ({} : ChartSpec).validationErrors
  = #["the chart has no series — nothing to draw"]

-- Too many series (13 > 12).
#guard ({ series := manySeries 13 } : ChartSpec).validationErrors
  = #["the chart has 13 series, more than the limit of 12"]

-- Too many points in one series (513 > 512).
#guard (bigSpec 513).validationErrors
  = #["series \"big\" has 513 points, more than the limit of 512"]

-- Size bounds, both axes, both directions.
#guard ({ series := #[{ name := "s" }], width := 99 } :
    ChartSpec).validationErrors
  = #["width 99 is outside the supported range [100, 2000]"]
#guard ({ series := #[{ name := "s" }], width := 2001 } :
    ChartSpec).validationErrors
  = #["width 2001 is outside the supported range [100, 2000]"]
#guard ({ series := #[{ name := "s" }], height := 50 } :
    ChartSpec).validationErrors
  = #["height 50 is outside the supported range [100, 2000]"]

-- Categorical: wrong point count.
#guard catMismatchSpec.validationErrors
  = #["series \"c\" has 1 points but there are 2 x-tick labels — a \
      categorical chart needs exactly one point per label"]

-- Categorical: right count, wrong x position.
#guard catMisplacedSpec.validationErrors
  = #["series \"c\" point 1 has x = 5, but a categorical chart requires \
      x = 1 (the point's index)"]

-- Multiple problems are ALL reported, in order.
#guard ({ width := 20, height := 3000 } : ChartSpec).validationErrors
  = #["the chart has no series — nothing to draw",
      "width 20 is outside the supported range [100, 2000]",
      "height 3000 is outside the supported range [100, 2000]"]

-- Boundary sizes are accepted.
#guard ({ series := #[{ name := "s" }], width := 100, height := 2000 } :
    ChartSpec).isValid
-- The caps themselves are accepted (512 points, 12 series).
#guard ({ series := manySeries 12 } : ChartSpec).isValid
#guard (bigSpec 512).isValid

/-! ## Degenerate specs through the top-level API -/

-- Invalid specs are refused by renderChart AND textReport with the same
-- honest message (the full joined list).
#guard errD (renderChart {})
  = "invalid chart spec — the chart has no series — nothing to draw"
#guard errD (textReport {})
  = "invalid chart spec — the chart has no series — nothing to draw"
#guard errD (renderChart { width := 20, height := 3000 })
  = "invalid chart spec — the chart has no series — nothing to draw; \
     width 20 is outside the supported range [100, 2000]; \
     height 3000 is outside the supported range [100, 2000]"
#guard errD (renderChart catMismatchSpec)
  = "invalid chart spec — series \"c\" has 1 points but there are 2 x-tick \
     labels — a categorical chart needs exactly one point per label"

-- Degenerate but valid specs render fine (no error).
#guard (renderChart { series := #[{ name := "e" }] }).isOk
#guard (renderChart { series := #[{ name := "p", data := #[(1, 1)] }] }).isOk
#guard (renderChart flatSpec).isOk       -- zero y-range
#guard (renderChart verticalSpec).isOk   -- zero x-range

end ChartKitTests
