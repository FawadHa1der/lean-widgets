import ExprXRay
import ExprXRayTests.TestUtil

/-!
# Showcase probe: expr-xray

Dumps the exact top-level panel `Html` the `#xray` / `#xray_diff` commands
attach (`xrayHtml`: all four preset trees + the `pp.explicit` sections;
`xrayCompareHtml`: side-by-side trees with the ranked, defeq-annotated
mismatch list) for the representative terms, serialized to
`../../showcase/dumps/expr-xray.json` for the showcase site's React verification
harness.  Elaboration runs in `TermElabM` inside `#eval`, mirroring the test
suite.

Run from the package directory (exactly how `showcase/build.sh` invokes it):

    cd packages/expr-xray && lake env lean "../../showcase/probes/expr-xray.lean"

MUST stay in sync with the package's React-contract tests
(`ExprXRayTests/RenderTests.lean`, "React style-contract check" section): the
entries dumped here are the `renderXRay`/`renderCompare` panels those tests
run `reactContractViolations` over — if a panel is added there, add its dump
here.
-/

open Lean Elab Term ProofWidgets ExprXRay ExprXRayTests

/-- Serialize `Html` to the showcase dump schema: elements as
`{tag, t: "el", children, attrs}`, text as `{t: "text", s}`, components as
`{t: "comp", props, name, children}`.  NOTE: at this ProofWidgets pin,
`Html.component` props are `LazyEncodable Json = StateM RpcObjectStore Json`;
they are materialized with a fresh store via `(props.run {}).1`. -/
private partial def probeHtmlJson : Html → Json
  | .element tag attrs children =>
    Json.mkObj [
      ("tag", Json.str tag),
      ("t", Json.str "el"),
      ("children", Json.arr (children.map probeHtmlJson)),
      ("attrs", Json.arr (attrs.map fun (k, v) => Json.arr #[Json.str k, v]))]
  | .text s => Json.mkObj [("t", Json.str "text"), ("s", Json.str s)]
  | .component _ exp props children =>
    Json.mkObj [
      ("t", Json.str "comp"),
      ("props", (props.run {}).1),
      ("name", Json.str exp),
      ("children", Json.arr (children.map probeHtmlJson))]

private def probeEntry (name : String) (h : Html) : Json :=
  Json.mkObj [("tree", probeHtmlJson h), ("name", Json.str name)]

private def probeDump (pkg : String) (entries : Array Json) : Json :=
  Json.mkObj [("package", Json.str pkg), ("entries", Json.arr entries)]

#eval show TermElabM Unit from do
  let mut entries : Array Json := #[]
  -- Full single-expression panel: all four preset sections plus the
  -- pp.explicit pre blocks.
  let e1 ← elabT (← `((1 + 1 : Nat)))
  entries := entries.push (probeEntry "xray-1plus1-nat" (← xrayHtml e1))
  -- Universe levels rendered after const names in the "everything" preset.
  let e2 ← elabT (← `(@id Nat 5))
  entries := entries.push (probeEntry "xray-id-nat-5-universes" (← xrayHtml e2))
  -- Coercion badges: `Nat.cast` head flagged `↑coe`.
  let e3 ← elabT (← `(((3 : Nat) : Int)))
  entries := entries.push (probeEntry "xray-coe-nat-to-int" (← xrayHtml e3))
  -- Depth limit 0: every preset elided at the root.
  entries := entries.push
    (probeEntry "xray-1plus1-depth-limit-0" (← xrayHtml e1 { maxDepth := 0 }))
  -- Compare view with a real highlighted instance mismatch (NOT defeq —
  -- ranked first as the rw blocker).
  let a ← elabT (← `(@ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0))
  let b ← elabT (← `(@ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0))
  entries := entries.push
    (probeEntry "compare-ite-instance-mismatch" (← xrayCompareHtml a b))
  -- The empty-diff compare view (banner-less path).
  entries := entries.push
    (probeEntry "compare-no-differences" (← xrayCompareHtml e1 e1))
  IO.FS.writeFile "../../showcase/dumps/expr-xray.json"
    (probeDump "expr-xray" entries).pretty
