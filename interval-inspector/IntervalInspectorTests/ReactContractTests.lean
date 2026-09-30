import IntervalInspector.Widget
import IntervalInspectorTests.Helpers
import Mathlib.Data.Real.Basic

/-! # React attribute-contract tests

The InfoView renders `ProofWidgets.Html` by passing attributes directly as React
props.  React requires the `style` prop to be a JSON **object** with camelCased
property names — a raw CSS string (`"font-family:monospace"`) crashes the whole
panel at runtime with minified React error #62, which compile-time tests never
catch because they never run React.  `IntervalInspector.reactContractViolations`
walks an `Html` tree and reports every element whose `style` value is not a JSON
object, any attribute literally named `class`, and any hyphenated SVG
presentation attribute React warns about (`stroke-width` & co. — React wants the
camelCase spelling; see `warnedHyphenatedSvgAttrs`); these tests run it over the
**real top-level outputs** the panel produces and assert the list is empty.

Before the `Render.css` fix, `inspectorHtml` / `suggestionHtml` emitted string
styles like `("style", .str "font-family:sans-serif")` and the svg root carried
`("style", .str "background:…;border-radius:6px")`, so every non-checker test
below returned a non-empty violation list and FAILED. -/

namespace ReactContractTests

open Lean ProofWidgets IntervalInspector IntervalInspectorTests

/-! ## Checker sanity: it actually detects violations (would-be regressions) -/

-- A string style is a violation; an object style is not.
#guard (reactContractViolations
    (.element "div" #[("style", .str "color:red")] #[])).length == 1
#guard reactContractViolations
    (.element "div" #[("style", Render.css #[("color", "red")])] #[]) == []
-- `class` is flagged; violations in nested children are found and path-labeled.
#guard (reactContractViolations
    (.element "div" #[("class", .str "x")]
      #[.element "span" #[("style", .str "margin-top:2px")] #[]])).length == 2
-- Non-style string attributes (SVG geometry, data-*) are fine.
#guard reactContractViolations
    (.element "rect" #[("x", .str "8"), ("data-mismatch", .str "seg 1 2")] #[]) == []
-- Hyphenated SVG presentation attributes React warns about ("Invalid DOM
-- property") are flagged, naming the camelCase spelling React wants…
#guard reactContractViolations
    (.element "circle" #[("stroke-width", .str "2")] #[])
  == ["root/circle: hyphenated SVG attribute \"stroke-width\" — React wants camelCase \"strokeWidth\""]
-- …including the font/text presentation attributes on `<text>` (React warns for
-- these too — the earlier belief that React whitelists them was wrong)…
#guard (reactContractViolations
    (.element "text" #[("text-anchor", .str "middle"), ("font-family", .str "monospace"),
      ("font-size", .str "11"), ("font-weight", .str "bold")] #[])).length == 4
#guard reactContractViolations
    (.element "text" #[("text-anchor", .str "middle")] #[])
  == ["root/text: hyphenated SVG attribute \"text-anchor\" — React wants camelCase \"textAnchor\""]
-- …while the camelCase spellings and `data-*` hyphenated attributes are clean.
#guard reactContractViolations
    (.element "text" #[("strokeWidth", .str "2"), ("textAnchor", .str "middle"),
      ("fontFamily", .str "monospace"), ("fontSize", .str "11"),
      ("fontWeight", .str "bold"), ("data-foo", .str "bar")] #[]) == []

/-! ## Real top-level outputs (the same `Html` the widget command builds) -/

-- 1. Panel body for the literal union-equality (statement + svg + suggestion list
--    with ready badges) — previously full of string styles.
private def joinLit : Shape :=
  .eq (.union (dev .Ioc "1" 1 "2" 2) (dev .Ioc "2" 2 "3" 3)) (dev .Ioc "1" 1 "3" 3)

private def analysisLit : Analysis :=
  let g := joinLit.orderGraph #[]
  { shape := joinLit, graph := g, layout := computeLayout g, inst := .all
    suggestions := suggest joinLit g }

#guard reactContractViolations (inspectorHtml analysisLit plainTactic) == []

-- 2. Panel body for the symbolic variant (missing-condition badges take the other
--    style branch) — previously string styles too.
private def joinSym : Shape :=
  .eq (.union (de .Ioc "a" "b") (de .Ioc "b" "c")) (de .Ioc "a" "c")

private def analysisSym : Analysis :=
  let g := joinSym.orderGraph #[]
  { shape := joinSym, graph := g, layout := computeLayout g, inst := .all
    suggestions := suggest joinSym g }

#guard reactContractViolations (inspectorHtml analysisSym plainTactic) == []

-- 3. A single suggestion-list item, including the fallback marker and a
--    missing-instance badge (every badge/name style branch) — previously string
--    styles on all four spans.
#guard reactContractViolations
    (suggestionHtml { lemmaName := "(fallback)", tactic := "simp", isFallback := true,
                      conds := #[({ lhs := "a", rel := .le, rhs := "b" }, false)],
                      missingInsts := #["DenselyOrdered"] }
      plainTactic) == []

-- 4. The bare number-line SVG (the panel's drawing, also emitted on its own) —
--    previously carried the string style "background:…;border-radius:6px" on the
--    svg root.
#guard reactContractViolations
    (renderShapeSvg joinLit analysisLit.graph analysisLit.layout .all) == []
#guard reactContractViolations
    (renderShapeSvg (.subset (de .Icc "a" "b") (de .Ioo "a" "b"))
      (Shape.orderGraph (.subset (de .Icc "a" "b") (de .Ioo "a" "b")) #[])
      (computeLayout (Shape.orderGraph (.subset (de .Icc "a" "b") (de .Ioo "a" "b")) #[]))
      .all) == []

-- 5. The rpc fallback messages (no styles at all — must stay clean).
#guard reactContractViolations (Render.el "span" #[] #[.text "No goals."]) == []

/-! ## End to end over actual types: elaborate real statements and check the exact
panel `Html` the `#interval_inspect` command / `interval_inspect?` rpc build. -/

#assert_react_contract (Set.Ioc (1:ℝ) 2 ∪ Set.Ioc 2 3 = Set.Ioc 1 3)
#assert_react_contract (Set.Ico (0:ℕ) 2 ⊆ Set.Icc (0:ℕ) 1)
#assert_react_contract ((3:ℝ) ∈ Set.Icc 1 4)
#assert_react_contract (Set.Ioo (0:ℕ) 1 = ∅)

end ReactContractTests
