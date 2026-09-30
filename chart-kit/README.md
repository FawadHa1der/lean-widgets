# ChartKit

**Verified-exact charting primitives for the Lean 4 InfoView.**

ChartKit is a library first and a command second: it turns a `ChartSpec` —
plain, first-order data over **exact `ℚ`** — into a theme-aware SVG
(`renderChart : ChartSpec → Except String Html`) that any widget author can
embed, and it ships a `#chart` command that displays a spec directly from a
Lean file.

What makes it different from float-based plotting: **there is no `Float`
anywhere in the pipeline**. Data, bounds, nice ticks, and every pixel
coordinate are computed in `Rat` and serialized deterministically, so

* a chart is NaN-free and infinity-free *by construction*,
* the same spec always renders the byte-identical SVG tree, and
* every geometric fact about the output (tick positions, bar heights,
  polyline points) is pinned by compile-time `#guard` tests.

Floats can still get in — but only through `Series.ofFloats`, which decodes
IEEE 754 doubles **bit-for-bit** into their exact rational values (`0.1`
becomes `3602879701896397/36028797018963968`, because that is what the double
actually is) and honestly refuses NaN/±∞.

Built and tested against toolchain `leanprover/lean4:v4.32.2` and
ProofWidgets4 `6e311e2` (pinned in `lake-manifest.json`).

## Usage

```lean
import ChartKit

open ChartKit

-- A spec is plain data; every field has a default.
def myChart : ChartSpec := {
  title? := some "Sum of two dice",
  xLabel := "sum", yLabel := "probability",
  series := #[{ name := "P(sum)", mark := .bar, data := #[(2, 1/36), (3, 1/18) /- … -/] }] }

#chart myChart                  -- SVG panel in the InfoView
#chart (text := true) myChart   -- deterministic ASCII report (what tests pin)
#chart { series := #[{ name := "inline", data := #[(0, 0), (1, 2)] }] }
```

Marks: `.bar` (rectangles from the baseline `y = 0`), `.line` (polyline),
`.step` (staircase, **horizontal-then-vertical** — the CDF convention),
`.scatter` (circles). Options: `showLegend`, `showGrid`, `valueLabels`
(exact y value above every point), `color?` per series (else a six-color VS
Code theme palette, cycled), `width`/`height` (px, `[100, 2000]`).

Categorical charts: set `xTickLabels := #["Mon", …]`; the x axis then ticks
at `0, 1, …, n-1` with those labels, and every series must have exactly one
point per label with `x = index` (validated, honest error otherwise).

As a library:

```lean
match renderChart spec with        -- validation + axis self-checks + SVG
| .ok html => …                    -- embed in your own panel
| .error e => …                    -- full list of problems, honest sizes
```

`textReport spec` produces the deterministic ASCII summary; both refuse
invalid specs with the same message.

Exact floats:

```lean
-- .error names the offending index/coordinate if any value is NaN/±∞.
def s : Except String Series := Series.ofFloats "data" #[(0.0, 0.1), (1.0, 0.2)]
#guard floatToRat? 0.1 = some (3602879701896397 / 36028797018963968)
```

## Architecture

```
ChartKit/
  Model.lean        Mark, Series, ChartSpec; hard caps; validationErrors
                    (every problem, exact sizes — the single validation gate)
  Scale.lean        the mathematical heart, all exact ℚ:
                    natLog10 / ilog10 / pow10, niceStep (smallest {1,2,5}·10^k
                    ≥ raw), niceAxis (outward-widened bounds + tick
                    progression), categoricalAxis, Axis.selfCheck,
                    AffineMap (exact data→pixel), ratStr (decimal, 6-digit
                    truncation), dataBounds? / xAxisOf / yAxisOf
  FloatBridge.lean  floatToRat? (bit-exact IEEE 754 decode via Float.toBits),
                    Series.ofFloats
  Render.lean       htmlToDebugString, reactContractViolations, css/el
                    helpers, theme palette, frame geometry, per-mark
                    renderers, gridlines/ticks/labels/legend/title,
                    textReport, renderChart (top-level API)
  Widget.lean       the #chart command: elaborate → refuse mvars/sorry/
                    noncomputable → evalExpr → validate → panel or text
  Demo.lean         six realistic charts (dice pmf bars, growth lines, dice
                    CDF staircase, quadratic-residue scatter, categorical
                    weekdays, exact-double scatter), all elaborated on every
                    build, with #guard'd data ("the chart IS the theorem's
                    data")

ChartKitTests/      compile-time suite (#guard / #guard_msgs; building = running):
  ScaleTests        nice ticks pinned across magnitudes + monotonicity/
                    coverage properties over a range battery
  ModelTests        every validation rule with its exact message; degenerate
                    specs through the real API
  FloatTests        exact conversions pinned (0.1, 0.2, subnormals, max
                    double), refusal messages
  RenderTests       exact mark geometry (bar rects, polyline strings,
                    staircase, circles), palette cycling, legend, labels
  ContractTests     reactContractViolations == [] over every real panel
                    (all marks, all options, all demos) + checker sanity
  CommandTests      #guard_msgs pins of (text := true) output and every
                    user-facing error message
```

Renderer invariants worth knowing:

* **React contract**: every `style` attribute is a JSON object built by
  `Render.css` (a CSS *string* crashes the InfoView with React error #62);
  `reactContractViolations` re-checks every real panel in the test suite.
* **Self-checks**: `renderChart` re-validates the axis invariants
  (`Axis.selfCheck`) at render time; a violation is reported as an
  "internal invariant violated" error instead of drawing a wrong picture.
* **Fixed element order** (gridlines, axes, ticks, labels, marks, value
  labels, title, legend) so tests can pin the serialized tree.

## Limitations (honest)

* **`ratStr` truncates at 6 fractional digits.** All *layout* geometry stays
  exact until serialization, but a coordinate or tick label like `1/3`
  serializes as `0.333333` (truncated, not rounded), and `1/10^7` as `0`.
  Tick *positions* for nice axes are `{1,2,5}·10^k` multiples and thus exact
  well within 6 digits; pathological tick labels only arise from categorical
  or data values with huge denominators.
* **Multiple bar series overlap.** Bars are centered on their x position
  with width `3/5 · plotWidth / n` (n = points in that series). There is no
  side-by-side grouping or stacking; two bar series in one chart draw over
  each other (later series on top).
* **No sorting.** `line`/`step` connect points in array order. Unsorted data
  draws a zig-zag — deterministically, but probably not what you meant.
* **Bars need the baseline.** Any bar series forces `0` into the y range, so
  bar charts of values far from 0 waste vertical space (no broken-axis
  support).
* **The `#chart` argument is evaluated as one compiled call.** A `ChartSpec`
  is concrete data, but the term producing it may compute arbitrarily long;
  unlike row-by-row extraction in graph-scope there is no between-rows
  interrupt point inside that single evaluation (interrupt/heartbeat checks
  run before it). Caps (12 series, 512 points/series, size ≤ 2000²) are
  checked *after* evaluation — they bound rendering, not user computation.
* **No axis-label collision handling.** Long categorical labels or a large
  `width`-to-tick ratio can overlap visually; nothing detects that.
* **Long titles/labels are not truncated or measured.** Text metrics are
  approximated (7 px/char for legend advance) — a very long series name can
  push later legend entries off-canvas.
* **No log scales, no dates, no second y axis, no error bars.** v1 scope is
  the four marks above on linear exact axes.
* **`Series.ofFloats` is exact, which can surprise.** The chart shows the
  true double values: a "0.1" input yields ticks/labels for
  `0.100000000000000005…` truncated to `0.1`, but bounds/positions use the
  exact value. This is a feature (the alternative is silent lying), but
  labels can look off-by-nothing.
* **Panel rendering requires the InfoView.** `#chart` attaches HTML via
  `savePanelWidgetInfo`; on the command line, only `(text := true)` output is
  visible (and is what CI pins).

## Tests

`lake test` (or `lake build ChartKitTests`) — 230 `#guard` pins plus 18
message-exact `#guard_msgs` pins in the test library, all compile-time: the
suite passing *is* the build succeeding. The main library additionally
elaborates all six demo panels on every build, with 6 more `#guard`s of demo
data and 1 pinned demo text report (255 assertions in total).
