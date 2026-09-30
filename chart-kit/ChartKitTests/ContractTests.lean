import ChartKitTests.Helpers

/-! # React-contract tests

The InfoView hands ProofWidgets `Html` attributes directly to React as props.
React requires the `style` prop to be a JSON *object* with camelCased keys — a
raw CSS string crashes the whole panel at runtime with minified React error
#62, and compile-time `#guard` tests never run React, so nothing else catches
it.  `ChartKit.reactContractViolations` walks an `Html` tree and reports every
element whose `style` attribute is not a `Json.obj` (plus any attribute
literally named `class`).

These tests run the checker over the *real* top-level panels the `#chart`
command attaches (`renderChart`'s output is exactly the `Html` passed to
`Widget.savePanelWidgetInfo` in `ChartKit/Widget.lean`), across every mark,
option combination and demo spec.
-/

namespace ChartKitTests

open ChartKit ChartKit.Demo

/-- Contract check through the real top-level entry point: `renderChart`
must succeed AND produce a violation-free tree. -/
def contractOk (s : ChartSpec) : Bool :=
  match renderChart s with
  | .ok h => reactContractViolations h == []
  | .error _ => false

-- Every mark, through the real panels.
#guard contractOk lineSpec
#guard contractOk barSpec
#guard contractOk stepSpec
#guard contractOk scatterSpec

-- Every option: categorical + value labels, title + labels + legend, grid
-- off, legend off, palette cycling.
#guard contractOk catSpec
#guard contractOk fullSpec
#guard contractOk { lineSpec with showGrid := false, showLegend := false }
#guard contractOk paletteSpec

-- Degenerate-but-valid specs.
#guard contractOk { series := #[{ name := "e" }] }
#guard contractOk { series := #[{ name := "p", data := #[(1, 1)] }] }

-- The shipped demo charts (exactly what `#chart` attaches on every build).
#guard contractOk diceChart
#guard contractOk growthChart
#guard contractOk cdfChart
#guard contractOk squaresChart
#guard contractOk weekChart
#guard contractOk floatChart

/-! ## The checker itself catches what it must

Sanity checks that the guards above are not vacuous: a string style (the
exact shape of the classic bug) and a `class` attribute are both flagged,
path-labeled. -/

/-- The classic buggy shape: a raw CSS string as the `style` prop. -/
private def badStringStyle : ProofWidgets.Html :=
  .element "div" #[("style", .str "font-family:sans-serif")]
    #[.element "span" #[] #[.text "hi"]]

#guard reactContractViolations badStringStyle ≠ []
#guard (reactContractViolations badStringStyle).all (·.startsWith "root/div")
#guard reactContractViolations
    (.element "div" #[] #[.element "p" #[("style", .str "color:red")] #[]])
  == ["root/div/p: style attribute is not a Json object (\"color:red\")"]
#guard reactContractViolations (.element "div" #[("class", .str "x")] #[]) ≠ []
-- Object styles (as built by `Render.css`) pass.
#guard reactContractViolations
    (.element "div" #[("style", Render.css #[("fontFamily", "monospace")])] #[])
  == []

-- A hyphenated SVG presentation attribute React warns about is flagged,
-- path-labeled, naming the camelCase spelling React wants.
#guard reactContractViolations
    (.element "svg" #[] #[.element "line" #[("stroke-width", .str "2")] #[]])
  == ["root/svg/line: hyphenated SVG attribute \"stroke-width\" — React \
      wants camelCase \"strokeWidth\""]
-- The hyphenated font/text presentation attributes are flagged too: React
-- warns for them on `<text>` just like every other hyphenated SVG
-- presentation attribute (verified against a fresh page — earlier
-- "whitelist" observations were an artifact of React's warning dedup).
#guard reactContractViolations
    (.element "svg" #[]
      #[.element "text" #[("text-anchor", .str "middle"),
          ("font-family", .str "monospace")] #[]])
  == ["root/svg/text: hyphenated SVG attribute \"text-anchor\" — React \
      wants camelCase \"textAnchor\"",
      "root/svg/text: hyphenated SVG attribute \"font-family\" — React \
      wants camelCase \"fontFamily\""]
#guard reactContractViolations
    (.element "text" #[("font-size", .str "10")] #[]) ≠ []
#guard reactContractViolations
    (.element "text" #[("font-weight", .str "bold")] #[]) ≠ []
-- The camelCase spellings and `data-*` attributes (the legitimately
-- hyphenated family) are clean.
#guard reactContractViolations
    (.element "svg" #[]
      #[.element "line" #[("strokeWidth", .str "2")] #[],
        .element "text" #[("textAnchor", .str "middle"),
          ("fontFamily", .str "monospace"), ("fontSize", .str "10"),
          ("fontWeight", .str "bold"), ("data-foo", .str "1")] #[]])
  == []

end ChartKitTests
