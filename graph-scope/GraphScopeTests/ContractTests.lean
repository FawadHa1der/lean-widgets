import GraphScopeTests.Helpers

/-! # React-contract tests

The InfoView hands ProofWidgets `Html` attributes directly to React as props.
React requires the `style` prop to be a JSON *object* with camelCased keys — a
raw CSS string crashes the whole panel at runtime with minified React error
#62, and compile-time `#guard` tests never run React, so nothing else catches
it.  `GraphScope.reactContractViolations` walks an `Html` tree and reports
every element whose `style` attribute is not a `Json.obj` (plus any attribute
literally named `class`, and any hyphenated SVG presentation attribute from
`GraphScope.warnedSvgAttrs` — React warns "Invalid DOM property" and wants
the camelCase spelling).

These tests run the checker over the *real* top-level panels the
`#graph_scope` command attaches (`renderPanel` is exactly the `Html` passed to
`Widget.savePanelWidgetInfo` in `GraphScope/Widget.lean`), across every
rendering mode: plain, walk overlay, highlight overlay, combined overlays,
forced layouts, and corner cases.  Before the `Render.css` fix, `renderPanel`
put string styles on the panel root div, the stats block and every stats line,
so each of these guards failed with three or more violations — they pin the
contract permanently.
-/

namespace GraphScopeTests

open GraphScope

-- Plain panel (previously: string styles on root div, stats block, 4 stat lines).
#guard reactContractViolations (renderPanel (path 4)) == []

-- Walk overlay panel (adds a walk legend line, previously also string-styled).
#guard reactContractViolations (renderPanel (path 4) (walk? := some #[0, 1, 2])) == []

-- Highlight overlay panel (adds a highlight legend line, previously string-styled).
#guard reactContractViolations (renderPanel (path 4) (highlight? := some #[0, 3])) == []

-- Combined overlays.
#guard reactContractViolations
  (renderPanel (path 4) (walk? := some #[0, 1]) (highlight? := some #[3])) == []

-- Forced layouts (circle for a tree, layered for a cycle).
#guard reactContractViolations (renderPanel (path 4) (mode := .circle)) == []
#guard reactContractViolations (renderPanel (cycle 5) (mode := .layered)) == []

-- Corner cases: empty graph, isolated vertices, long custom labels.
#guard reactContractViolations (renderPanel (empty 0)) == []
#guard reactContractViolations (renderPanel (empty 3)) == []
#guard reactContractViolations
  (renderPanel (GraphData.ofEdges 2 #[(0, 1)] #["Sum.inl 0", "Sum.inr 0"])) == []

/-! ## The checker itself catches what it must

Sanity checks that the guards above are not vacuous: a string style (the exact
shape of the old bug) and a `class` attribute are both flagged, and the path
label points into the tree. -/

/-- The old, buggy shape of the panel root: a raw CSS string style. -/
private def badStringStyle : ProofWidgets.Html :=
  .element "div" #[("style", .str "font-family:sans-serif;color:red")]
    #[.element "span" #[] #[.text "hi"]]

#guard reactContractViolations badStringStyle ≠ []
#guard (reactContractViolations badStringStyle).all (·.startsWith "root/div")

-- Nested violations are found and path-labeled.
#guard reactContractViolations
  (.element "div" #[] #[.element "p" #[("style", .str "color:red")] #[]])
  == ["root/div/p: style attribute is not a Json object (\"color:red\")"]

-- A `class` attribute is flagged.
#guard reactContractViolations (.element "div" #[("class", .str "x")] #[]) ≠ []

-- A hyphenated SVG presentation attribute React warns about (`stroke-width`)
-- is flagged, path-labeled, with the camelCase replacement named.
#guard reactContractViolations
  (.element "svg" #[] #[.element "line" #[("stroke-width", .str "3")] #[]])
  == ["root/svg/line: hyphenated SVG attribute \"stroke-width\" — React wants camelCase \"strokeWidth\""]

-- The font/text presentation attributes are flagged too: React warns for
-- *all* hyphenated SVG presentation attributes passed as props (empirically
-- including every font/text presentation attribute on `<text>`); the
-- camelCase props render to the correct hyphenated SVG attributes in the DOM.
#guard reactContractViolations
  (.element "text" #[("text-anchor", .str "middle")] #[])
  == ["root/text: hyphenated SVG attribute \"text-anchor\" — React wants camelCase \"textAnchor\""]
#guard reactContractViolations
  (.element "text" #[("font-size", .str "10")] #[])
  == ["root/text: hyphenated SVG attribute \"font-size\" — React wants camelCase \"fontSize\""]
#guard reactContractViolations
  (.element "text" #[("font-family", .str "monospace")] #[])
  == ["root/text: hyphenated SVG attribute \"font-family\" — React wants camelCase \"fontFamily\""]
#guard reactContractViolations
  (.element "text" #[("font-weight", .str "bold")] #[])
  == ["root/text: hyphenated SVG attribute \"font-weight\" — React wants camelCase \"fontWeight\""]

-- The camelCase spellings pass, and `data-*` attributes — genuinely
-- hyphenated in the DOM and passed through by React untouched — are
-- deliberately not flagged.
#guard reactContractViolations
  (.element "text" #[("strokeWidth", .str "4"), ("textAnchor", .str "middle"),
    ("fontSize", .str "10"), ("fontFamily", .str "monospace"),
    ("fontWeight", .str "bold"), ("data-foo", .str "bar")] #[]) == []

-- Object styles (as built by `Render.css`) pass.
#guard reactContractViolations
  (.element "div" #[("style", Render.css #[("fontFamily", "monospace")])] #[]) == []

end GraphScopeTests
