import HasseViewTests.Helpers

/-! # React-contract tests

The InfoView hands ProofWidgets `Html` attributes directly to React as props.
React requires the `style` prop to be a JSON *object* with camelCased keys —
a raw CSS string crashes the whole panel at runtime with minified React error
#62, and compile-time `#guard` tests never run React, so nothing else catches
it.  `HasseView.reactContractViolations` walks an `Html` tree and reports
every element whose `style` attribute is not a `Json.obj` (plus any attribute
literally named `class`, and any hyphenated SVG presentation attribute React
warns about — e.g. `stroke-width`, which React wants as `strokeWidth`).

These tests run the checker over the *real* top-level panels the `#hasse`
command attaches (`renderPanel` is exactly the `Html` passed to
`Widget.savePanelWidgetInfo` in `HasseView/Widget.lean`), across every
rendering mode: plain, highlight overlay, updown overlay, combined overlays,
warnings, and corner cases.
-/

namespace HasseViewTests

open HasseView

-- Plain panels over every shape.
#guard reactContractViolations (renderPanel (cubeP 3)) == []
#guard reactContractViolations (renderPanel (chainP 5)) == []
#guard reactContractViolations (renderPanel (antichainP 4)) == []
#guard reactContractViolations (renderPanel bowtieP) == []
#guard reactContractViolations (renderPanel divisor12P) == []

-- Overlay panels (extra legend lines and SVG markers).
#guard reactContractViolations (renderPanel (cubeP 3) (highlight? := some #[0, 7])) == []
#guard reactContractViolations (renderPanel (cubeP 3) (updown? := some 1)) == []
#guard reactContractViolations
  (renderPanel (cubeP 3) (highlight? := some #[0]) (updown? := some 1)) == []

-- Warning captions (invalid tables still render — with warning lines).
#guard reactContractViolations (renderPanel brokenP) == []
#guard reactContractViolations (renderPanel notAntisymP) == []

-- Corner cases: empty poset, single element, custom long labels.
#guard reactContractViolations (renderPanel (chainP 0)) == []
#guard reactContractViolations (renderPanel (chainP 1)) == []
#guard reactContractViolations
  (renderPanel (mkPoset 2 (· ≤ ·) #["(false, false)", "(false, true)"])) == []

/-! ## Interactive panels (click-to-insert links)

`MakeEditLink` component nodes are legal in the tree (the checker recurses
into their children); verified and rejected candidates alike must keep the
panel React-safe, with either link renderer. -/

#guard reactContractViolations (renderPanelWith (chainP 3) (links := fin3Links)
  (mkLink := editLink testDocMeta testInsertRange)) == []
#guard reactContractViolations (renderPanelWith (chainP 3) (links := rejectedLinks)
  (mkLink := editLink testDocMeta testInsertRange)) == []
#guard reactContractViolations (renderPanelWith (cubeP 3) (highlight? := some #[0])
  (updown? := some 1) (links := fin3Links)
  (mkLink := editLink testDocMeta testInsertRange)) == []
#guard reactContractViolations (renderPanelWith (chainP 3) (links := fin3Links)) == []

/-! ## The checker itself catches what it must

Sanity checks that the guards above are not vacuous: a string style (the
exact shape of the classic bug) and a `class` attribute are both flagged,
and the path label points into the tree. -/

/-- The buggy shape: a raw CSS string style. -/
private def badStringStyle : ProofWidgets.Html :=
  .element "div" #[("style", .str "font-family:monospace;color:red")]
    #[.element "span" #[] #[.text "hi"]]

#guard reactContractViolations badStringStyle ≠ []
#guard (reactContractViolations badStringStyle).all (·.startsWith "root/div")

-- Nested violations are found and path-labeled.
#guard reactContractViolations
  (.element "div" #[] #[.element "p" #[("style", .str "color:red")] #[]])
  == ["root/div/p: style attribute is not a Json object (\"color:red\")"]

-- A `class` attribute is flagged (React wants `className`).
#guard reactContractViolations (.element "div" #[("class", .str "x")] #[]) ≠ []

-- Object styles (as built by `Render.css`) pass.
#guard reactContractViolations
  (.element "div" #[("style", Render.css #[("fontFamily", "monospace")])] #[]) == []

-- A hyphenated SVG presentation attribute React warns about is flagged,
-- with the camelCase spelling React wants named in the message.
#guard reactContractViolations
  (.element "line" #[("stroke-width", .str "1.5")] #[]) ==
  ["root/line: hyphenated SVG attribute \"stroke-width\" — React wants camelCase \"strokeWidth\""]

-- Hyphenated font/text presentation attributes are flagged too: React warns
-- for ALL hyphenated SVG presentation attributes passed as props (verified
-- empirically on `<text>`); there is no whitelist for `text-anchor` etc.
#guard reactContractViolations
  (.element "text" #[("text-anchor", .str "middle")] #[]) ==
  ["root/text: hyphenated SVG attribute \"text-anchor\" — React wants camelCase \"textAnchor\""]
#guard reactContractViolations
  (.element "text" #[("font-family", .str "monospace")] #[]) ==
  ["root/text: hyphenated SVG attribute \"font-family\" — React wants camelCase \"fontFamily\""]
#guard reactContractViolations
  (.element "text" #[("font-size", .str "11")] #[]) ≠ []
#guard reactContractViolations
  (.element "text" #[("font-weight", .str "bold")] #[]) ≠ []

-- The camelCase spellings are clean, and `data-*`/`aria-*` attributes are
-- the only hyphenated names that legitimately stay hyphenated as props.
#guard reactContractViolations
  (.element "text" #[("strokeWidth", .str "4"), ("textAnchor", .str "middle"),
    ("fontSize", .str "11"), ("fontFamily", .str "monospace"),
    ("fontWeight", .str "bold"), ("data-foo", .str "bar")] #[]) == []

end HasseViewTests
