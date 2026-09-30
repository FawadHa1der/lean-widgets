import DistLensTests.Helpers

/-! # React contract tests

`reactContractViolations` over **every** real top-level panel output: each
`style` attribute must be a Json object with camelCased keys (a CSS string
crashes the InfoView with minified React error #62), and no attribute may be
literally named `class`.  Plus positive checks that the checker itself
catches crafted violations (so an empty result means something).
-/

namespace DistLensTests

open DistLens ProofWidgets

/-! ## Every real panel is clean -/

#guard reactContractViolations (renderDistPanel die6) = []
#guard reactContractViolations (renderDistPanel coin) = []
#guard reactContractViolations
  (renderDistPanel die6 #["example : die 0 = 1/6 := by pmf_num"]) = []
-- Even a violating *model* renders a contract-clean panel (warnings shown).
#guard reactContractViolations (renderDistPanel badModel) = []
#guard reactContractViolations
  (renderDistPanel { carrier := "V", labels := #["a"], weights := #[1] }) = []

#guard reactContractViolations (renderFilmPanel
  ⟨#[("source", coin), ("result", { coin with weights := #[1/2, 1/2] })]⟩) = []
#guard reactContractViolations (renderFilmPanel ⟨#[]⟩) = []

#guard reactContractViolations (renderChainPanel weatherM) = []
#guard reactContractViolations (renderChainPanel identityM) = []
#guard reactContractViolations (renderChainPanel badChain) = []
#guard reactContractViolations
  (renderChainPanel weatherM
    ⟨#[("step 0", coin), ("step 1", coin)]⟩
    #["example : s := by pmf_num"]) = []
#guard reactContractViolations (renderChainPanel triangleM
  ⟨#[("step 0", die6)]⟩) = []

-- Bare chart pieces are clean too.
#guard reactContractViolations (Render.barChart die6) = []
#guard reactContractViolations (Render.cdfChart die6) = []
#guard reactContractViolations (Render.chainGraph triangleM) = []

/-! ## The checker itself fires on crafted violations -/

-- A string-valued style — the exact React error #62 crash shape.
#guard reactContractViolations
    (.element "div" #[("style", .str "color: red")] #[])
  = ["root/div: style attribute is not a Json object (\"color: red\")"]

-- `class` instead of `className`.
#guard reactContractViolations
    (.element "div" #[("class", .str "x")] #[])
  = ["root/div: attribute \"class\" should be \"className\""]

-- Violations nested under healthy elements are found, path-labeled.
#guard reactContractViolations
    (.element "div" #[("style", Render.css #[("color", "red")])]
      #[.element "span" #[("style", .num 3)] #[]])
  = ["root/div/span: style attribute is not a Json object (3)"]

-- A healthy tree with a css-built style passes.
#guard reactContractViolations
    (.element "div" #[("style", Render.css #[("fontFamily", "monospace")])]
      #[.text "ok"]) = []

-- A hyphenated SVG presentation attribute — React warns "Invalid DOM
-- property" and wants the camelCase prop name.
#guard reactContractViolations
    (.element "line" #[("stroke-width", .str "1")] #[])
  = ["root/line: hyphenated SVG attribute \"stroke-width\" — \
      React wants camelCase \"strokeWidth\""]

-- Font/text presentation attributes on `<text>` are no exception: React
-- warns for them hyphenated too, and wants the camelCase prop name.
#guard reactContractViolations
    (.element "text"
      #[("text-anchor", .str "middle"), ("font-family", .str "monospace")] #[])
  = ["root/text: hyphenated SVG attribute \"text-anchor\" — \
      React wants camelCase \"textAnchor\"",
     "root/text: hyphenated SVG attribute \"font-family\" — \
      React wants camelCase \"fontFamily\""]

#guard reactContractViolations
    (.element "text" #[("font-size", .str "10")] #[])
  = ["root/text: hyphenated SVG attribute \"font-size\" — \
      React wants camelCase \"fontSize\""]

#guard reactContractViolations
    (.element "text" #[("font-weight", .str "bold")] #[])
  = ["root/text: hyphenated SVG attribute \"font-weight\" — \
      React wants camelCase \"fontWeight\""]

-- The camelCase spellings are clean, and `data-*` attributes are the
-- legal hyphenated exception.
#guard reactContractViolations
    (.element "text"
      #[("strokeWidth", .str "2"), ("textAnchor", .str "middle"),
        ("fontSize", .str "10"), ("data-foo", .str "bar")] #[])
  = []

end DistLensTests
