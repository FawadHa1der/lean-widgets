import ExprXRay
import ExprXRayTests.TestUtil

/-! # Tests for `ExprXRay.Render`

Contains-assertions on the deterministic `Html.toStringCompact`
serialization: dim markers, `[inst]` badges, coercion badges, preset
filtering, compare-mode highlighting, and the `XNode.toText` rendering. -/

namespace ExprXRayTests.RenderTests

open Lean Elab Term ExprXRay ExprXRayTests ProofWidgets

/-! ## Pure preset semantics -/

-- "clean" shows only explicit/none roles
#guard ViewPreset.clean.showsRole .explicit
#guard ViewPreset.clean.showsRole .none
#guard !ViewPreset.clean.showsRole .implicit
#guard !ViewPreset.clean.showsRole .strictImplicit
#guard !ViewPreset.clean.showsRole .instImplicit
-- "+implicit" adds implicits but still hides instances
#guard ViewPreset.withImplicit.showsRole .implicit
#guard ViewPreset.withImplicit.showsRole .strictImplicit
#guard !ViewPreset.withImplicit.showsRole .instImplicit
-- "+instances" and "everything" show everything
#guard ViewPreset.withInstances.showsRole .instImplicit
#guard ViewPreset.everything.showsRole .instImplicit
-- only "everything" shows universes
#guard ViewPreset.everything.showsUniverses
#guard !ViewPreset.clean.showsUniverses
#guard !ViewPreset.withInstances.showsUniverses

/-! ## Html.toStringCompact serializer -/

#guard Html.toStringCompact (.text "hi") == "hi"
#guard Html.toStringCompact (.element "div" #[] #[.text "x"]) == "<div>x</div>"
#guard Html.toStringCompact
    (.element "span" #[("style", Lean.Json.mkObj [("opacity", "0.55")])] #[.text "d"])
  == "<span style={\"opacity\":\"0.55\"}>d</span>"
#guard Html.toStringCompact
    (.element "ul" #[] #[.element "li" #[] #[.text "a"], .element "li" #[] #[.text "b"]])
  == "<ul><li>a</li><li>b</li></ul>"

/-! ## Rendering real expressions -/

#eval show TermElabM Unit from do
  let n ← analyzeT (← `((1 + 1 : Nat)))
  let everything := Html.toStringCompact (renderNode .everything n)
  let clean := Html.toStringCompact (renderNode .clean n)
  let withImp := Html.toStringCompact (renderNode .withImplicit n)
  -- [inst] badge present when instances are shown
  assertContains "render: [inst] badge" everything "[inst]"
  -- dim marker (opacity style) present on hidden-role nodes
  assertContains "render: dim marker" everything "\"opacity\":\"0.55\""
  -- instance pp visible in "everything"
  assertContains "render: instHAdd shown" everything "instHAdd"
  -- ... but the "clean" preset really removes implicit and instance nodes
  assertNotContains "render clean: no [inst] badge" clean "[inst]"
  assertNotContains "render clean: no instHAdd" clean "instHAdd"
  assertNotContains "render clean: no dimmed nodes" clean "\"opacity\":\"0.55\""
  -- the explicit operands survive the clean filter
  assertContains "render clean: keeps operands" clean "1 + 1"
  assertContains "render clean: keeps head" clean "HAdd.hAdd"
  -- "+implicit" shows implicits but still no instance badge
  assertNotContains "render +implicit: no [inst]" withImp "[inst]"
  assertNotContains "render +implicit: no instHAdd" withImp "instHAdd"
  assertContains "render +implicit: dimmed implicits present" withImp "\"opacity\":\"0.55\""
  -- structure: nested details/summary with native expand/collapse
  assertContains "render: details element" everything "<details open=true"
  assertContains "render: summary element" everything "<summary>"

#eval show TermElabM Unit from do
  -- coercion badge
  let n ← analyzeT (← `(((3 : Nat) : Int)))
  let out := Html.toStringCompact (renderNode .everything n)
  assertContains "render: coe badge" out "↑coe"
  -- negative: no coe badge on a plain application
  let n2 ← analyzeT (← `(Nat.succ 3))
  let out2 := Html.toStringCompact (renderNode .everything n2)
  assertNotContains "render: no coe badge on succ" out2 "↑coe"

#eval show TermElabM Unit from do
  -- universe levels rendered small after const names, only in "everything"
  let n ← analyzeT (← `(@id Nat 5))
  let everything := Html.toStringCompact (renderNode .everything n)
  let inst := Html.toStringCompact (renderNode .withInstances n)
  assertContains "render: universe suffix in everything" everything ".{1}"
  assertNotContains "render: no universe suffix in +instances" inst ".{1}"

#eval show TermElabM Unit from do
  -- types shown after pp; elided marker on cut branches
  let n ← analyzeT (← `((1 + 1 : Nat))) { maxDepth := 0 }
  let out := Html.toStringCompact (renderNode .everything n)
  assertContains "render: type suffix" out " : Nat"
  assertContains "render: elision marker" out "⋯(depth limit)"

/-! ## markMismatches path mapping -/

#eval show TermElabM Unit from do
  let a ← elabT (← `(@ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0))
  let b ← elabT (← `(@ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0))
  let ms ← diffExprs a b
  let na ← analyzeExpr a
  let marked := markMismatches na (ms.toList.map (·.path))
  -- the instance argument (child 3) is highlighted...
  assertTrue "mark: instance arg highlighted"
    ((marked.get? [3]).map (·.highlighted) == some true)
  -- ...and nothing else is
  assertEq "mark: exactly one highlight" (marked.count (·.highlighted)) 1
  -- an empty path list highlights nothing
  let unmarked := markMismatches na []
  assertEq "mark: no paths, no highlights" (unmarked.count (·.highlighted)) 0

#eval show TermElabM Unit from do
  -- mdata wrappers are transparent for mark paths: a diff path that was
  -- computed on mdata-stripped exprs still lands on the right node
  let inner ← elabT (← `(Nat.succ Nat.zero))
  let wrapped := Expr.mdata {} inner
  let other ← elabT (← `(Nat.succ (Nat.succ Nat.zero)))
  let ms ← diffExprs wrapped other
  assertTrue "mark mdata: mismatch found" !ms.isEmpty
  let n ← analyzeExpr wrapped
  assertEq "mark mdata: tree root is mdata" n.kind .mdata
  let marked := markMismatches n (ms.toList.map (·.path))
  -- path [1] addresses the arg BELOW the mdata wrapper: node [0, 1]
  assertTrue "mark mdata: node under wrapper highlighted"
    ((marked.get? [0, 1]).map (·.highlighted) == some true)

/-! ## Compare-mode rendering -/

#eval show TermElabM Unit from do
  let a ← elabT (← `(@ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0))
  let b ← elabT (← `(@ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0))
  let na ← analyzeExpr a
  let nb ← analyzeExpr b
  let ms ← diffExprs a b
  let out := Html.toStringCompact (renderCompare na nb ms)
  -- ranked summary list on top
  assertContains "compare: mismatch count in summary" out "mismatches (1, ranked)"
  assertContains "compare: describe line" out
    "instance argument #3 of ite differs: instDecidableEqNat 2 2 vs Classical.propDecidable (2 = 2)"
  -- side-by-side flex row
  assertContains "compare: flex row" out "\"display\":\"flex\""
  assertContains "compare: row direction" out "\"flexDirection\":\"row\""
  -- highlighted mismatch node markers (background + ≠ badge)
  assertContains "compare: highlight style" out "\"backgroundColor\":\"rgba(255, 90, 90, 0.22)\""
  assertContains "compare: ≠ badge" out "≠"
  -- both instances visible in the two trees
  assertContains "compare: left instance" out "instDecidableEqNat"
  assertContains "compare: right instance" out "Classical.propDecidable"

#eval show TermElabM Unit from do
  -- compare mode with NO differences renders the fixed empty message
  let a ← elabT (← `((1 + 1 : Nat)))
  let na ← analyzeExpr a
  let out := Html.toStringCompact (renderCompare na na #[])
  assertContains "compare empty: message" out "no structural differences found"
  assertContains "compare empty: zero count" out "mismatches (0, ranked)"
  assertNotContains "compare empty: no ≠ badge" out "≠"

/-! ## renderXRay full view -/

#eval show TermElabM Unit from do
  let e ← elabT (← `((1 + 1 : Nat)))
  let n ← analyzeExpr e
  let out := Html.toStringCompact (renderXRay n "EXPLICIT_TXT" "EXPLICIT_UNIV_TXT")
  -- all four preset sections present
  assertContains "xray: clean section" out "clean (explicit only)"
  assertContains "xray: +implicit section" out "+implicit"
  assertContains "xray: +instances section" out "+instances"
  assertContains "xray: everything section" out "everything (with universes)"
  -- pp.explicit section renders both texts as selectable pre blocks
  assertContains "xray: pp.explicit section" out "pp.explicit"
  assertContains "xray: explicit text" out "EXPLICIT_TXT"
  assertContains "xray: explicit+universes text" out "EXPLICIT_UNIV_TXT"
  assertContains "xray: selectable text" out "\"userSelect\":\"text\""

/-! ## React style-contract check

The InfoView passes attributes directly as React props; `style` must be a
JSON object with camelCased keys — a CSS string crashes the panel at runtime
with React error #62 (which no compile-time test can see). These run
`reactContractViolations` over the REAL top-level panel outputs the `#xray`
command produces (`renderXRay`, `renderCompare`), so any future string-style
regression anywhere in the render pipeline fails `lake test`. -/

-- checker sanity: a raw CSS-string style — the exact live-bug shape — IS flagged...
#guard !(reactContractViolations
    (.element "div" #[("style", Lean.Json.str "font-family:monospace;color:red")]
      #[.text "x"])).isEmpty
-- ...including when it is nested below clean elements...
#guard (reactContractViolations
    (.element "div" #[]
      #[.element "span" #[("style", Lean.Json.str "color:red")] #[]])).length == 1
-- ...a `class` attribute is flagged (React requires `className`)...
#guard !(reactContractViolations (.element "span" #[("class", Lean.Json.str "dim")] #[])).isEmpty
-- ...and object styles / style-free trees are clean.
#guard reactContractViolations
    (.element "div" #[("style", Lean.Json.mkObj [("fontFamily", "monospace")])] #[.text "x"]) == []
#guard reactContractViolations (.element "ul" #[] #[.element "li" #[] #[.text "a"]]) == []

#eval show TermElabM Unit from do
  -- full single-expression panel: all four preset sections (badges, dim
  -- styles, indent guides) plus the pp.explicit pre blocks
  let n ← analyzeT (← `((1 + 1 : Nat)))
  assertEq "react contract: renderXRay"
    (reactContractViolations (renderXRay n "EXPLICIT_TXT" "EXPLICIT_UNIV_TXT")) []

#eval show TermElabM Unit from do
  -- compare view with a real highlighted mismatch: exercises the
  -- `mergeObj` dim+highlight style, defeq badges and the flex-row layout
  let a ← elabT (← `(@ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0))
  let b ← elabT (← `(@ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0))
  let na ← analyzeExpr a
  let nb ← analyzeExpr b
  let ms ← diffExprs a b
  assertEq "react contract: renderCompare"
    (reactContractViolations (renderCompare na nb ms)) []
  -- and the empty-diff compare view (banner-less path)
  assertEq "react contract: renderCompare (no diffs)"
    (reactContractViolations (renderCompare na na #[])) []

/-! ## XNode.toText -/

#eval show TermElabM Unit from do
  let n ← analyzeT (← `(@id Nat 5))
  let txt := n.toText .everything
  assertContains "toText: root line" txt "app «id 5» : Nat"
  assertContains "toText: implicit tag" txt "{imp}"
  assertContains "toText: universe suffix" txt "«@id».{1}"
  -- indentation: children indented by two spaces
  assertContains "toText: indented child" txt "\n  const «Nat» : Type {imp}"
  -- clean preset removes the implicit line entirely
  let cleanTxt := n.toText .clean
  assertNotContains "toText clean: no {imp}" cleanTxt "{imp}"
  assertNotContains "toText clean: no universes" cleanTxt ".{1}"

#eval show TermElabM Unit from do
  let n ← analyzeT (← `((1 + 1 : Nat)))
  let txt := n.toText .everything
  assertContains "toText: [inst] tag" txt "[inst]"
  let cleanTxt := n.toText .clean
  assertNotContains "toText clean: no [inst]" cleanTxt "[inst]"

end ExprXRayTests.RenderTests
