import ChartKit.Scale
import ProofWidgets.Data.Html

/-! # ChartKit: rendering

Two pure renderers over a validated `ChartSpec`:

* `textReport` — a deterministic multi-line ASCII summary (size, axes with
  exact tick positions, per-series mark and point counts), used by
  `#chart (text := true)` and pinned exactly by `#guard_msgs` tests;
* `renderChart` — the InfoView HTML: a theme-aware SVG with axes, ticks,
  optional gridlines, the per-series marks (bars / polyline / staircase /
  circles), optional exact value labels, title and legend.  All colors are VS
  Code theme variables with hex fallbacks, so charts follow light/dark themes.

Both refuse invalid specs (`ChartSpec.validationErrors`) with the full list of
problems, and both re-check the axis invariants (`Axis.selfCheck`) so a scale
bug becomes an honest "internal invariant violated" error, never a silently
wrong picture.

Every SVG coordinate is computed in exact `ℚ` and serialized with `ratStr`
(truncating decimal, 6 fractional digits), so the output HTML tree is
byte-deterministic: the same spec always renders the same tree.

`htmlToDebugString` serializes any `Html` tree deterministically for tests;
`reactContractViolations` checks the React style contract (see its docstring).
-/

namespace ChartKit

open ProofWidgets

/-- Deterministic serialization of an `Html` tree for tests:
`<tag k="v">children</tag>`; components render as `<component:HASH>`. -/
partial def htmlToDebugString : Html → String
  | .text s => s
  | .element tag attrs cs =>
    let attrStr := attrs.foldl (init := "") fun acc (k, v) =>
      let vs := match v with
        | .str s => s
        | j => j.compress
      acc ++ s!" {k}=\"{vs}\""
    let body := cs.foldl (init := "") fun acc c => acc ++ htmlToDebugString c
    s!"<{tag}{attrStr}>{body}</{tag}>"
  | .component h _ _ cs =>
    let body := cs.foldl (init := "") fun acc c => acc ++ htmlToDebugString c
    s!"<component:{h}>{body}</component:{h}>"

/-- Hyphenated SVG presentation attributes that React rejects as element
props with an "Invalid DOM property" warning, each paired with the camelCase
spelling React wants (React converts the camelCase prop back to the correct
hyphenated attribute in the DOM, so rendering is unchanged).  React warns for
hyphenated SVG presentation attributes passed as props — empirically
including all font/text presentation attributes on `<text>` (`font-size`,
`text-anchor`, `font-family`, `font-weight`).  `data-*`/`aria-*` attributes
and camelCased style-OBJECT keys are the only hyphenated-family things that
legitimately stay out of this table. -/
def reactWarnedSvgAttrs : List (String × String) := [
  ("stroke-width", "strokeWidth"),
  ("stroke-dasharray", "strokeDasharray"),
  ("stroke-linecap", "strokeLinecap"),
  ("stroke-linejoin", "strokeLinejoin"),
  ("stroke-opacity", "strokeOpacity"),
  ("fill-opacity", "fillOpacity"),
  ("fill-rule", "fillRule"),
  ("paint-order", "paintOrder"),
  ("dominant-baseline", "dominantBaseline"),
  ("letter-spacing", "letterSpacing"),
  ("clip-path", "clipPath"),
  ("font-size", "fontSize"),
  ("text-anchor", "textAnchor"),
  ("font-family", "fontFamily"),
  ("font-weight", "fontWeight")]

/-- React-contract checker over an `Html` tree.  The InfoView passes
attributes straight through as React props, and React requires the `style`
prop to be a JSON *object* with camelCased keys — a raw CSS string crashes the
whole panel at runtime with minified React error #62.  Returns one
path-labeled entry for every element whose `style` attribute value is not a
`Json.obj`, for any attribute literally named `class` (React wants
`className`), and for any hyphenated SVG presentation attribute React warns
about (`reactWarnedSvgAttrs` — React wants the camelCase spelling).  An empty
result means the tree is safe to hand to React. -/
partial def reactContractViolations : Html → List String :=
  go "root"
where
  /-- Walk the tree accumulating the element path for messages. -/
  go (path : String) : Html → List String
    | .text _ => []
    | .element tag attrs cs =>
      let path := s!"{path}/{tag}"
      let here := attrs.toList.flatMap fun (k, v) =>
        if k == "style" then
          match v with
          | .obj _ => []
          | _ => [s!"{path}: style attribute is not a Json object ({v.compress})"]
        else if k == "class" then
          [s!"{path}: attribute \"class\" should be \"className\""]
        else match reactWarnedSvgAttrs.lookup k with
          | some camel =>
            [s!"{path}: hyphenated SVG attribute \"{k}\" — React wants \
              camelCase \"{camel}\""]
          | none => []
      cs.foldl (init := here) fun acc c => acc ++ go path c
    | .component _ _ _ cs =>
      cs.foldl (init := []) fun acc c => acc ++ go s!"{path}/component" c

namespace Render

/-! ## Theme-aware colors

Every color is a VS Code CSS variable with an explicit hex fallback, so the
SVG adapts to the editor theme and still renders standalone. -/

/-- Main foreground (axis lines, title, value labels). -/
def fgColor : String := "var(--vscode-editor-foreground, #333333)"
/-- Secondary text (tick labels, axis labels, legend names). -/
def mutedColor : String := "var(--vscode-descriptionForeground, #717171)"
/-- Gridlines. -/
def gridColor : String := "var(--vscode-widget-border, #d4d4d4)"

/-- The series color palette, cycled by series index (an override via
`Series.color?` wins).  Six VS Code chart colors with hex fallbacks. -/
def palette : Array String := #[
  "var(--vscode-charts-blue, #3794ff)",
  "var(--vscode-charts-red, #e51400)",
  "var(--vscode-charts-green, #388a34)",
  "var(--vscode-charts-purple, #b180d7)",
  "var(--vscode-charts-yellow, #cca700)",
  "var(--vscode-charts-orange, #d18616)"]

/-- The color of series `i` of a spec: its `color?` override if set, else
`palette[i % 6]`. -/
def seriesColor (spec : ChartSpec) (i : Nat) : String :=
  match spec.series[i]? >>= (·.color?) with
  | some c => c
  | none => palette[i % palette.size]!

/-- Shorthand for an element with string attributes.  Never pass a `style`
attribute through this helper: it coerces every value to `Json.str`, and a
string-valued `style` prop crashes the InfoView with React error #62 — use
`.element` with `css #[…]` for styles instead (enforced suite-wide by
`reactContractViolations` tests). -/
def el (tag : String) (attrs : Array (String × String))
    (children : Array Html := #[]) : Html :=
  .element tag (attrs.map fun (k, v) => (k, .str v)) children

/-- Build a React-compatible style object.  React requires the style prop to
be a JSON OBJECT with camelCased property names — a CSS string crashes the
InfoView with React error #62, so never pass a string style. -/
def css (props : Array (String × String)) : Lean.Json :=
  Lean.Json.mkObj (props.toList.map fun (k, v) => (k, Lean.Json.str v))

/-- An SVG `<text>` element at exact `ℚ` coordinates (serialized via
`ratStr`), monospace, centered by default. -/
def svgText (x y : Rat) (fill content : String) (size : String := "10")
    (anchor : String := "middle") (extra : Array (String × String) := #[]) :
    Html :=
  el "text" (#[("x", ratStr x), ("y", ratStr y), ("fill", fill),
      ("fontSize", size), ("textAnchor", anchor),
      ("fontFamily", "monospace")] ++ extra) #[.text content]

/-- An SVG `<line>` at exact `ℚ` coordinates. -/
def svgLine (x1 y1 x2 y2 : Rat) (stroke : String) (width : String := "1")
    (extra : Array (String × String) := #[]) : Html :=
  el "line" (#[("x1", ratStr x1), ("y1", ratStr y1), ("x2", ratStr x2),
      ("y2", ratStr y2), ("stroke", stroke), ("strokeWidth", width)] ++ extra)

/-! ## Frame geometry (all exact `ℚ`) -/

/-- Left margin: room for y tick labels and the rotated y-axis label. -/
def padLeft : Rat := 48
/-- Right margin. -/
def padRight : Rat := 14
/-- Top margin without a title. -/
def padTopPlain : Rat := 14
/-- Top margin with a title. -/
def padTopTitle : Rat := 30
/-- Base bottom margin: x tick labels + x-axis label. -/
def padBottomBase : Rat := 36
/-- Extra bottom margin for the legend row. -/
def legendHeight : Rat := 20

/-- Whether the legend row is drawn: `showLegend` and at least one series. -/
def _root_.ChartKit.ChartSpec.legendShown (spec : ChartSpec) : Bool :=
  spec.showLegend && !spec.series.isEmpty

/-- The pixel frame of a chart: the plot rectangle and the two exact
data→pixel affine maps (`yMap` is inverted: data-up is pixel-down). -/
structure Frame where
  /-- Plot rectangle, left edge. -/
  plotL : Rat
  /-- Plot rectangle, right edge. -/
  plotR : Rat
  /-- Plot rectangle, top edge. -/
  plotT : Rat
  /-- Plot rectangle, bottom edge. -/
  plotB : Rat
  /-- x data → pixel map. -/
  xMap : AffineMap
  /-- y data → pixel map (inverted). -/
  yMap : AffineMap
  deriving Repr, Inhabited

/-- Compute the frame of a spec from its axes: margins per the `pad*`
constants (title and legend presence widen top/bottom margins). -/
def frameOf (spec : ChartSpec) (xA yA : Axis) : Frame :=
  let plotL := padLeft
  let plotR : Rat := ((spec.width : Nat) : Rat) - padRight
  let plotT := if spec.title?.isSome then padTopTitle else padTopPlain
  let plotB : Rat := ((spec.height : Nat) : Rat) - padBottomBase
    - (if spec.legendShown then legendHeight else 0)
  { plotL, plotR, plotT, plotB
    xMap := xA.toPixels plotL plotR
    yMap := yA.toPixels plotB plotT }

/-! ## Marks -/

/-- Bar width for a series of `n` points: `3/5` of the slot width
`plotWidth / n` (bars of a multi-bar-series chart share slots and may
overlap — see README limitations). -/
def barWidth (f : Frame) (n : Nat) : Rat :=
  if n = 0 then 0 else (f.plotR - f.plotL) / ((n : Nat) : Rat) * (3/5)

/-- The polyline `points` string of a line series: mapped points in data
order, `"x,y"` pairs separated by spaces (coordinates via `ratStr`). -/
def linePoints (f : Frame) (data : Array (Rat × Rat)) : String :=
  " ".intercalate (data.toList.map fun (x, y) =>
    s!"{ratStr (f.xMap.apply x)},{ratStr (f.yMap.apply y)}")

/-- The polyline `points` string of a step series (CDF convention:
**horizontal segment first, then vertical** — the value at `xᵢ` extends
rightward until `xᵢ₊₁`): `2n - 1` points for `n` data points. -/
def stepPoints (f : Frame) (data : Array (Rat × Rat)) : String := Id.run do
  let mut pts : Array String := #[]
  for i in [0:data.size] do
    let (x, y) := data[i]!
    let px := ratStr (f.xMap.apply x)
    let py := ratStr (f.yMap.apply y)
    if i > 0 then
      -- Horizontal first: previous height extended to this x.
      let (_, y0) := data[i-1]!
      pts := pts.push s!"{px},{ratStr (f.yMap.apply y0)}"
    pts := pts.push s!"{px},{py}"
  return " ".intercalate pts.toList

/-- The mark elements of series `i` (validated spec assumed).  Bars are
rectangles from the baseline `y = 0` (guaranteed on-axis by
`ChartSpec.dataBounds?` whenever bars are present); line/step are single
polylines; scatter is one circle per point.  Every element carries
`data-series` (index) and `data-mark` attributes for tests. -/
def seriesMarks (spec : ChartSpec) (f : Frame) (i : Nat) : Array Html := Id.run do
  let some s := spec.series[i]? | return #[]
  let color := seriesColor spec i
  let common := #[("data-series", toString i), ("data-mark", s.mark.name)]
  match s.mark with
  | .bar =>
    let w := barWidth f s.data.size
    let base := f.yMap.apply 0
    let mut out : Array Html := #[]
    for j in [0:s.data.size] do
      let (x, y) := s.data[j]!
      let px := f.xMap.apply x
      let py := f.yMap.apply y
      let top := min py base
      let h := (py - base).abs
      out := out.push <| el "rect"
        (#[("x", ratStr (px - w / 2)), ("y", ratStr top),
           ("width", ratStr w), ("height", ratStr h),
           ("fill", color), ("data-pt", toString j)] ++ common)
    return out
  | .line =>
    return #[el "polyline"
      (#[("points", linePoints f s.data), ("fill", "none"),
         ("stroke", color), ("strokeWidth", "2")] ++ common)]
  | .step =>
    return #[el "polyline"
      (#[("points", stepPoints f s.data), ("fill", "none"),
         ("stroke", color), ("strokeWidth", "2")] ++ common)]
  | .scatter =>
    let mut out : Array Html := #[]
    for j in [0:s.data.size] do
      let (x, y) := s.data[j]!
      out := out.push <| el "circle"
        (#[("cx", ratStr (f.xMap.apply x)), ("cy", ratStr (f.yMap.apply y)),
           ("r", "3"), ("fill", color), ("data-pt", toString j)] ++ common)
    return out

/-- The exact-value labels of series `i`: the y value (via `ratStr`) drawn 6px
above each point.  Emitted only when `spec.valueLabels`. -/
def seriesValueLabels (spec : ChartSpec) (f : Frame) (i : Nat) : Array Html :=
  match spec.series[i]? with
  | none => #[]
  | some s =>
    s.data.mapIdx fun j (x, y) =>
      svgText (f.xMap.apply x) (f.yMap.apply y - 6) fgColor (ratStr y)
        (extra := #[("data-vlabel", s!"{i}.{j}")])

/-! ## Axes, decorations, legend -/

/-- Gridlines: one vertical line per x tick and one horizontal per y tick,
spanning the plot rectangle. -/
def gridlines (f : Frame) (xA yA : Axis) : Array Html :=
  (xA.ticks.map fun t =>
    let px := f.xMap.apply t
    svgLine px f.plotT px f.plotB gridColor "0.5" #[("data-grid", "x")])
  ++ (yA.ticks.map fun t =>
    let py := f.yMap.apply t
    svgLine f.plotL py f.plotR py gridColor "0.5" #[("data-grid", "y")])

/-- The two axis lines (bottom and left edges of the plot rectangle). -/
def axisLines (f : Frame) : Array Html :=
  #[svgLine f.plotL f.plotB f.plotR f.plotB fgColor "1" #[("data-axis", "x")],
    svgLine f.plotL f.plotT f.plotL f.plotB fgColor "1" #[("data-axis", "y")]]

/-- x-axis ticks: a 4px tick mark and a label under each tick.  Labels are
the exact tick values via `ratStr`, or the categorical `xTickLabels` when
set. -/
def xTicks (spec : ChartSpec) (f : Frame) (xA : Axis) : Array Html := Id.run do
  let mut out : Array Html := #[]
  for i in [0:xA.ticks.size] do
    let t := xA.ticks[i]!
    let px := f.xMap.apply t
    let label := if spec.isCategorical then (spec.xTickLabels[i]?).getD (ratStr t)
      else ratStr t
    out := out.push <| svgLine px f.plotB px (f.plotB + 4) fgColor "1"
      #[("data-tick", s!"x{i}")]
    out := out.push <| svgText px (f.plotB + 16) mutedColor label
      (extra := #[("data-ticklabel", s!"x{i}")])
  return out

/-- y-axis ticks: a 4px tick mark and a right-anchored exact label left of
each tick. -/
def yTicks (f : Frame) (yA : Axis) : Array Html := Id.run do
  let mut out : Array Html := #[]
  for i in [0:yA.ticks.size] do
    let t := yA.ticks[i]!
    let py := f.yMap.apply t
    out := out.push <| svgLine (f.plotL - 4) py f.plotL py fgColor "1"
      #[("data-tick", s!"y{i}")]
    out := out.push <| svgText (f.plotL - 7) (py + 3) mutedColor (ratStr t)
      (anchor := "end") (extra := #[("data-ticklabel", s!"y{i}")])
  return out

/-- The axis labels: `xLabel` centered under the x ticks, `yLabel` rotated
−90° along the left edge.  Empty strings produce no element. -/
def axisLabels (spec : ChartSpec) (f : Frame) : Array Html := Id.run do
  let mut out : Array Html := #[]
  if spec.xLabel ≠ "" then
    out := out.push <| svgText ((f.plotL + f.plotR) / 2) (f.plotB + 30)
      mutedColor spec.xLabel (extra := #[("data-label", "x")])
  if spec.yLabel ≠ "" then
    let midY := (f.plotT + f.plotB) / 2
    out := out.push <| svgText 14 midY mutedColor spec.yLabel
      (extra := #[("transform", s!"rotate(-90 14 {ratStr midY})"),
                  ("data-label", "y")])
  return out

/-- The title, centered at the top (only when `title?` is set). -/
def titleEl (spec : ChartSpec) : Array Html :=
  match spec.title? with
  | none => #[]
  | some t => #[svgText (((spec.width : Nat) : Rat) / 2) 18 fgColor t
      (size := "13") (extra := #[("fontWeight", "bold"), ("data-title", "1")])]

/-- The legend row along the bottom edge: a 10×10 color swatch plus the
series name per series, laid out left to right (item advance
`28 + 7·name.length` px, deterministic). -/
def legend (spec : ChartSpec) (f : Frame) : Array Html := Id.run do
  if !spec.legendShown then return #[]
  let y : Rat := ((spec.height : Nat) : Rat) - 8
  let mut out : Array Html := #[]
  let mut x := f.plotL
  for i in [0:spec.series.size] do
    let s := spec.series[i]!
    let color := seriesColor spec i
    out := out.push <| el "rect"
      #[("x", ratStr x), ("y", ratStr (y - 9)), ("width", "10"),
        ("height", "10"), ("fill", color), ("data-legend-swatch", toString i)]
    out := out.push <| svgText (x + 14) y mutedColor s.name (anchor := "start")
      (extra := #[("data-legend-name", toString i)])
    x := x + 28 + 7 * ((s.name.length : Nat) : Rat)
  return out

/-! ## Text report -/

/-- `"2 series"` / `"1 series"`. -/
def seriesNoun (n : Nat) : String := s!"{n} series"

/-- `"7 points"` / `"1 point"`. -/
def pointsNoun (n : Nat) : String :=
  if n = 1 then "1 point" else s!"{n} points"

/-- One axis line of the text report:
`"x [0, 6] step 1, ticks: 0 1 2 3 4 5 6"` (exact values via `ratStr`). -/
def axisLine (name : String) (a : Axis) : String :=
  s!"{name} [{ratStr a.lo}, {ratStr a.hi}] step {ratStr a.step}, ticks: "
    ++ " ".intercalate (a.ticks.toList.map ratStr)

/-- The deterministic ASCII report of a validated chart: header (title, size,
series/point counts), both axes with exact ticks, the categorical labels when
set, then one line per series (name, mark, point count). -/
def textReportCore (spec : ChartSpec) (xA yA : Axis) : String :=
  let title := match spec.title? with
    | some t => s!"chart \"{t}\""
    | none => "chart"
  let header := s!"{title} ({spec.width}x{spec.height}): \
    {seriesNoun spec.series.size}, {pointsNoun spec.pointCount}"
  let catLine := if spec.isCategorical then
      ["x-labels: " ++ ", ".intercalate spec.xTickLabels.toList]
    else []
  let seriesLines := spec.series.toList.zipIdx.map fun (s, i) =>
    s!"series {i} \"{s.name}\": {s.mark.name}, {pointsNoun s.data.size}"
  "\n".intercalate ([header, axisLine "x" xA, axisLine "y" yA]
    ++ catLine ++ seriesLines)

end Render

/-! ## Top-level API -/

/-- Validate a spec and compute its two axes, running the axis self-checks:
`.error` carries either the full validation-error list or an
"internal invariant violated" message (a ChartKit bug, reported honestly). -/
def ChartSpec.axes (spec : ChartSpec) : Except String (Axis × Axis) := do
  let errs := spec.validationErrors
  if !errs.isEmpty then
    throw ("invalid chart spec — " ++ "; ".intercalate errs.toList)
  let xA := spec.xAxisOf
  let yA := spec.yAxisOf
  if let some bug := xA.selfCheck then
    throw s!"internal invariant violated (x axis): {bug} — this is a ChartKit \
      bug, please report it"
  if let some bug := yA.selfCheck then
    throw s!"internal invariant violated (y axis): {bug} — this is a ChartKit \
      bug, please report it"
  return (xA, yA)

/-- The chart SVG of a validated spec (total; called through `renderChart`,
which validates first).  Fixed element order, pinned by tests: gridlines,
axis lines, x ticks, y ticks, axis labels, series marks (series order), value
labels, title, legend. -/
def chartSvg (spec : ChartSpec) (xA yA : Axis) : ProofWidgets.Html :=
  let f := Render.frameOf spec xA yA
  let sIdx := Array.range spec.series.size
  Render.el "svg"
    #[("xmlns", "http://www.w3.org/2000/svg"),
      ("width", toString spec.width), ("height", toString spec.height),
      ("viewBox", s!"0 0 {spec.width} {spec.height}")]
    ((if spec.showGrid then Render.gridlines f xA yA else #[])
      ++ Render.axisLines f
      ++ Render.xTicks spec f xA
      ++ Render.yTicks f yA
      ++ Render.axisLabels spec f
      ++ (sIdx.flatMap fun i => Render.seriesMarks spec f i)
      ++ (if spec.valueLabels then
            sIdx.flatMap fun i => Render.seriesValueLabels spec f i
          else #[])
      ++ Render.titleEl spec
      ++ Render.legend spec f)

/-- Render a spec to the InfoView panel `Html` (the SVG in a styled root
div), or an honest error: the full validation-error list for invalid specs,
or an "internal invariant violated" message if an axis self-check fails
(a ChartKit bug — never a silently wrong picture). -/
def renderChart (spec : ChartSpec) : Except String ProofWidgets.Html := do
  let (xA, yA) ← spec.axes
  return .element "div"
    #[("style", Render.css #[("fontFamily", "sans-serif")])]
    #[chartSvg spec xA yA]

/-- The deterministic ASCII report of a spec (see `Render.textReportCore` for
the format), or the same honest errors as `renderChart`. -/
def textReport (spec : ChartSpec) : Except String String := do
  let (xA, yA) ← spec.axes
  return Render.textReportCore spec xA yA

end ChartKit
