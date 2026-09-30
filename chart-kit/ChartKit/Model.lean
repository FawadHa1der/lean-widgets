/-! # ChartKit: the chart model

The pure data model of a chart, exactly as a caller writes it down:

* `Mark` — how one series is drawn (`bar`, `line`, `step`, `scatter`);
* `Series` — a named array of exact `Rat × Rat` points with a mark and an
  optional color override;
* `ChartSpec` — the whole chart: optional title, axis labels, series, size,
  legend/grid/value-label switches, and optional categorical x-tick labels.

Everything is first-order concrete data over `ℚ` — no `Float` anywhere, so a
`ChartSpec` is NaN-free and infinity-free *by construction* and every derived
quantity downstream (bounds, ticks, pixel positions) is exact.

`ChartSpec.validationErrors` is the single validation gate: it returns *every*
problem (honest, sized error messages naming the offending series), and both
`renderChart` and `textReport` refuse specs with a non-empty error list.  The
hard caps (`maxSeries`, `maxPointsPerSeries`, size bounds) are enforced here,
before any geometry is computed.
-/

namespace ChartKit

/-- How a series is drawn.

* `bar` — one rectangle per point, rising (or hanging) from the baseline `y = 0`;
* `line` — one polyline through the points in data order;
* `step` — a staircase through the points in data order, **horizontal segment
  first, then vertical** at each transition (the CDF convention: the value at
  `xᵢ` extends rightward until `xᵢ₊₁`);
* `scatter` — one circle per point. -/
inductive Mark where
  | bar
  | line
  | step
  | scatter
  deriving Repr, DecidableEq, Inhabited

/-- Lower-case name of a mark, used in reports and error messages. -/
def Mark.name : Mark → String
  | .bar => "bar"
  | .line => "line"
  | .step => "step"
  | .scatter => "scatter"

/-- One data series: a name (shown in the legend), a mark, the data points as
exact rationals in the order they should be drawn (line/step connect them in
this order — ChartKit never re-sorts data), and an optional CSS color that
overrides the palette. -/
structure Series where
  /-- Series name (legend entry; also used in error messages). -/
  name : String
  /-- How the series is drawn. -/
  mark : Mark := .line
  /-- The data points, exact.  Drawn (and connected) in array order. -/
  data : Array (Rat × Rat) := #[]
  /-- Optional CSS color overriding the theme palette for this series. -/
  color? : Option String := none
  deriving Repr, Inhabited

/-- A complete chart specification.  All fields have defaults, so
`{ series := #[…] }` is a valid literal. -/
structure ChartSpec where
  /-- Optional title drawn above the plot. -/
  title? : Option String := none
  /-- x-axis label (empty string = no label). -/
  xLabel : String := ""
  /-- y-axis label (empty string = no label; drawn rotated). -/
  yLabel : String := ""
  /-- The data series, drawn in array order (later series draw on top). -/
  series : Array Series := #[]
  /-- Total SVG width in px. -/
  width : Nat := 420
  /-- Total SVG height in px. -/
  height : Nat := 260
  /-- Draw the legend row (only when there is at least one series). -/
  showLegend : Bool := true
  /-- Draw the exact y-value above every point/bar. -/
  valueLabels : Bool := false
  /-- Draw gridlines at every tick. -/
  showGrid : Bool := true
  /-- Categorical x-tick labels.  When non-empty the x axis becomes
  categorical: ticks sit at `x = 0, 1, …, n-1` carrying these labels, and
  every series must have exactly one point per label with `x = index`
  (enforced by `validationErrors`). -/
  xTickLabels : Array String := #[]
  deriving Repr, Inhabited

/-- Hard cap on the number of series ChartKit will draw. -/
def maxSeries : Nat := 12

/-- Hard cap on the number of points in a single series. -/
def maxPointsPerSeries : Nat := 512

/-- Minimum chart width/height in px (smaller leaves no plot area). -/
def minSize : Nat := 100

/-- Maximum chart width/height in px. -/
def maxSize : Nat := 2000

/-- Total number of data points across all series. -/
def ChartSpec.pointCount (spec : ChartSpec) : Nat :=
  spec.series.foldl (fun acc s => acc + s.data.size) 0

/-- Is the x axis categorical (non-empty `xTickLabels`)? -/
def ChartSpec.isCategorical (spec : ChartSpec) : Bool :=
  !spec.xTickLabels.isEmpty

/-- Does any series use the `bar` mark?  (Bars force the y axis to include the
baseline `y = 0`.) -/
def ChartSpec.hasBars (spec : ChartSpec) : Bool :=
  spec.series.any (·.mark = .bar)

/-- Every problem with the spec, as honest error messages naming the offending
series and the actual/limit sizes.  Empty ⟺ the spec is drawable; both
`renderChart` and `textReport` refuse specs with a non-empty result.

Checks, in order: at least one series, `maxSeries`, per-series
`maxPointsPerSeries`, width/height within `[minSize, maxSize]`, and (when
`xTickLabels` is non-empty) that every series has exactly one point per label
with `x` equal to the point's index. -/
def ChartSpec.validationErrors (spec : ChartSpec) : Array String := Id.run do
  let mut errs : Array String := #[]
  if spec.series.isEmpty then
    errs := errs.push "the chart has no series — nothing to draw"
  if spec.series.size > maxSeries then
    errs := errs.push
      s!"the chart has {spec.series.size} series, more than the limit of {maxSeries}"
  for s in spec.series do
    if s.data.size > maxPointsPerSeries then
      errs := errs.push
        s!"series \"{s.name}\" has {s.data.size} points, more than the limit \
          of {maxPointsPerSeries}"
  if spec.width < minSize || spec.width > maxSize then
    errs := errs.push
      s!"width {spec.width} is outside the supported range [{minSize}, {maxSize}]"
  if spec.height < minSize || spec.height > maxSize then
    errs := errs.push
      s!"height {spec.height} is outside the supported range [{minSize}, {maxSize}]"
  if spec.isCategorical then
    let n := spec.xTickLabels.size
    for s in spec.series do
      if s.data.size ≠ n then
        errs := errs.push
          s!"series \"{s.name}\" has {s.data.size} points but there are {n} \
            x-tick labels — a categorical chart needs exactly one point per label"
      else
        for i in [0:s.data.size] do
          let (x, _) := s.data[i]!
          if x ≠ (i : Rat) then
            errs := errs.push
              s!"series \"{s.name}\" point {i} has x = {x}, but a categorical \
                chart requires x = {i} (the point's index)"
  return errs

/-- Is the spec drawable (no validation errors)? -/
def ChartSpec.isValid (spec : ChartSpec) : Bool :=
  spec.validationErrors.isEmpty

end ChartKit
