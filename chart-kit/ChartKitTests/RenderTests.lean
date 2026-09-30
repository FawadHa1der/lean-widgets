import ChartKitTests.Helpers

/-! # Render tests

Pins over the *real* `renderChart` output trees: exact mark geometry (bar
rect positions/sizes, polyline point strings, staircase segments, scatter
circles), element counts, palette cycling and overrides, tick/axis/grid
counts, categorical labels, value labels, legend entries, title and axis
labels.  All coordinates are exact ℚ serialized by `ratStr`, so every pin is
byte-exact.
-/

namespace ChartKitTests

open ChartKit

/-- Rendered tree of a spec (tests only run it on specs that render). -/
def rendered (s : ChartSpec) : ProofWidgets.Html := okD (renderChart s)

/-- The rendered shared specs (evaluated once per pin, still cheap). -/
def lineH := rendered lineSpec
def barH := rendered barSpec
def stepH := rendered stepSpec
def scatterH := rendered scatterSpec
def catH := rendered catSpec
def paletteH := rendered paletteSpec
def fullH := rendered fullSpec

/-! ## Line mark -/

-- The polyline through (0,0), (1,1), (2,4) on the 200×150 frame, exactly.
#guard (firstWith? lineH "data-mark" "line").bind (attr? · "points")
  = some "48,94 117,74 186,14"
#guard countAttrVal lineH "data-mark" "line" = 1
#guard (firstWith? lineH "data-mark" "line").bind (attr? · "fill") = some "none"
#guard (firstWith? lineH "data-mark" "line").bind (attr? · "stroke")
  = some "var(--vscode-charts-blue, #3794ff)"

/-! ## Bar mark -/

-- Three bars + one legend swatch are ALL the rects.
#guard countTag barH "rect" = 4
#guard countAttrVal barH "data-mark" "bar" = 3
-- Bar 0: value 2 on y ∈ [0,4] → top at 54, height 40; slot width
-- (186−48)/3 = 46, bar width 46·3/5 = 27.6, centered on px(0) = 48.
#guard (firstWith? barH "data-pt" "0").map
    (fun a => (attr? a "x", attr? a "y", attr? a "width", attr? a "height"))
  = some (some "34.2", some "54", some "27.6", some "40")
#guard (firstWith? barH "data-pt" "1").map (fun a => (attr? a "y", attr? a "height"))
  = some (some "74", some "20")
#guard (firstWith? barH "data-pt" "2").map (fun a => (attr? a "y", attr? a "height"))
  = some (some "14", some "80")

-- A negative bar hangs DOWN from the baseline: y = 0 sits at pixel 14 (top
-- of the y range [−2, 0]), the bar extends to px(−2) = 94.
#guard (firstWith?
    (rendered { series := #[{ name := "neg", mark := .bar, data := #[(0, -2)] }],
                width := 200, height := 150 })
    "data-mark" "bar").map (fun a => (attr? a "y", attr? a "height"))
  = some (some "14", some "80")

/-! ## Step mark (CDF staircase) -/

-- Horizontal-then-vertical: 2·3 − 1 = 5 points, y changes only at the NEXT x.
#guard (firstWith? stepH "data-mark" "step").bind (attr? · "points")
  = some "48,94 117,94 117,74 186,74 186,14"
#guard countAttrVal stepH "data-mark" "step" = 1
-- A one-point step series degenerates to a single point, no segments.
#guard (firstWith?
    (rendered { series := #[{ name := "one", mark := .step, data := #[(1, 1)] }],
                width := 200, height := 150 })
    "data-mark" "step").bind (attr? · "points")
  = some "117,54"

/-! ## Scatter mark -/

#guard countAttrVal scatterH "data-mark" "scatter" = 3
#guard countTag scatterH "circle" = 3
#guard (firstWith? scatterH "data-pt" "2").map
    (fun a => (attr? a "cx", attr? a "cy", attr? a "r"))
  = some (some "186", some "14", some "3")

/-! ## Axes, ticks, gridlines -/

-- lineSpec: x axis [0,2] has 5 ticks, y axis [0,4] has 5 → 10 gridlines,
-- 2 axis lines, 10 tick marks; 22 <line> elements in total.
#guard countTag lineH "line" = 22
#guard countAttrVal lineH "data-grid" "x" = 5
#guard countAttrVal lineH "data-grid" "y" = 5
#guard (attrVals lineH "data-axis") = #["x", "y"]
-- Exact tick labels, in axis order.
#guard (allText lineH).take 5 = #["0", "0.5", "1", "1.5", "2"]
-- The x-axis line spans the plot rect exactly.
#guard (firstWith? lineH "data-axis" "x").map
    (fun a => (attr? a "x1", attr? a "y1", attr? a "x2", attr? a "y2"))
  = some (some "48", some "94", some "186", some "94")
-- Grid off ⇒ no data-grid elements at all (and 10 fewer lines).
#guard countAttrVal (rendered { lineSpec with showGrid := false }) "data-grid" "x" = 0
#guard countTag (rendered { lineSpec with showGrid := false }) "line" = 12

/-! ## Categorical labels and value labels -/

-- Categorical x ticks carry the labels, not numbers.
#guard (attrVals catH "data-ticklabel") = #["x0", "x1", "y0", "y1", "y2", "y3"]
#guard (firstWith? catH "data-ticklabel" "x0").isSome
#guard (allText catH).take 2 = #["a", "b"]
-- Two bars at the slot centers 82.5 and 151.5 (half-slot padding).
#guard (firstWith? catH "data-pt" "0").map (fun a => (attr? a "x", attr? a "width"))
  = some (some "61.8", some "41.4")
-- Value labels: exact y values, 6px above the bar tops.
#guard countAttrVal catH "data-vlabel" "0.0" = 1
#guard (firstWith? catH "data-vlabel" "0.0").map (fun a => (attr? a "x", attr? a "y"))
  = some (some "82.5", some "8")
#guard (allText catH).contains "3" && (allText catH).contains "1"
-- valueLabels off (the default) ⇒ none.
#guard (attrVals lineH "data-vlabel") = #[]
-- fullSpec has them for every point of every series.
#guard (attrVals fullH "data-vlabel") = #["0.0", "0.1", "1.0", "1.1"]

/-! ## Palette cycling and overrides -/

-- Seven series: colors cycle after 6; series 6 wraps to the first color.
#guard (firstWith? paletteH "data-series" "0").bind (attr? · "fill")
  = some "var(--vscode-charts-blue, #3794ff)"
#guard (firstWith? paletteH "data-series" "1").bind (attr? · "fill")
  = some "var(--vscode-charts-red, #e51400)"
#guard (firstWith? paletteH "data-series" "5").bind (attr? · "fill")
  = some "var(--vscode-charts-orange, #d18616)"
#guard (firstWith? paletteH "data-series" "6").bind (attr? · "fill")
  = some "var(--vscode-charts-blue, #3794ff)"
/-- A one-point scatter with a `color?` override. -/
def overrideSpec : ChartSpec :=
  { series := #[{ name := "o", mark := .scatter, data := #[(0, 0)], color? := some "hotpink" }] }

-- A color? override wins over the palette.
#guard (firstWith? (rendered overrideSpec) "data-mark" "scatter").bind
    (attr? · "fill") = some "hotpink"
-- The legend swatch uses the same override.
#guard (firstWith? (rendered overrideSpec) "data-legend-swatch" "0").bind
    (attr? · "fill") = some "hotpink"

/-! ## Legend -/

#guard countTag lineH "text" > 0  -- sanity: texts exist
#guard (attrVals paletteH "data-legend-name") = #["0", "1", "2", "3", "4", "5", "6"]
-- Legend names are the series names, in order (last 7 text nodes).
#guard ((allText paletteH).toList.reverse.take 7).reverse
  = ["s0", "s1", "s2", "s3", "s4", "s5", "s6"]
-- Legend items advance by 28 + 7·len(name): "s0" → 28 + 14 = 42px.
#guard (firstWith? paletteH "data-legend-swatch" "0").bind (attr? · "x") = some "48"
#guard (firstWith? paletteH "data-legend-swatch" "1").bind (attr? · "x") = some "90"
-- showLegend := false ⇒ no legend elements.
#guard (attrVals (rendered { lineSpec with showLegend := false })
  "data-legend-swatch") = #[]
-- …and the plot grows: the x axis moves down from 94 to 114.
#guard (firstWith? (rendered { lineSpec with showLegend := false })
    "data-axis" "x").bind (attr? · "y1") = some "114"

/-! ## Title and axis labels -/

#guard (firstWith? fullH "data-title" "1").isSome
#guard (allText fullH).contains "Full"
#guard (firstWith? lineH "data-title" "1").isNone
#guard (firstWith? fullH "data-label" "x").bind (attr? · "x") = some "227"
-- The y label is rotated about its anchor point.
#guard (firstWith? fullH "data-label" "y").bind (attr? · "transform")
  = some "rotate(-90 14 117)"
#guard (firstWith? lineH "data-label" "x").isNone

/-! ## Determinism -/

-- Byte-determinism: rendering the same spec twice gives the same tree.
#guard htmlToDebugString (rendered fullSpec) == htmlToDebugString (rendered fullSpec)
#guard htmlToDebugString lineH == htmlToDebugString (rendered {
  series := #[{ name := "f", mark := .line, data := #[(0, 0), (1, 1), (2, 4)] }],
  width := 200, height := 150 })

end ChartKitTests
