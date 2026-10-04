import IntervalInspector
import IntervalInspectorTests.Helpers
import Mathlib.Basic.Real.Basic

/-!
# Showcase probe: interval-inspector

Dumps the exact top-level panel `Html` the `#interval_inspect` command /
`interval_inspect?` tactic build (`inspectorHtml … plainTactic` over the full
`elabAnalysis` pipeline: recognition, instance availability, order graph,
layout, suggestions) for six end-to-end statements over real types,
serialized to `../../showcase/dumps/interval-inspector.json` for the showcase
site's React verification harness.  Elaboration runs in `TermElabM` inside
`#eval`, mirroring the test helper commands.

Run from the package directory (exactly how `showcase/build.sh` invokes it):

    cd packages/interval-inspector && lake env lean "../../showcase/probes/interval-inspector.lean"

MUST stay in sync with the package's React-contract tests
(`IntervalInspectorTests/ReactContractTests.lean`): the entries dumped here
are the panels those tests run `reactContractViolations` over — if a panel
is added there, add its dump here.
-/

open Lean Elab Term ProofWidgets IntervalInspector IntervalInspectorTests

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

/-- Full pipeline (`elabAnalysis`, the same path the command and rpc panel
use) to the panel `Html`, failing the probe loudly on a non-recognized
statement. -/
private def panelEntry (name : String) (t : Syntax.Term) : TermElabM Json := do
  match ← elabAnalysis t with
  | some a => pure (probeEntry name (inspectorHtml a plainTactic))
  | none => throwError "interval-inspector probe: {name}: recognition returned none"

#eval show TermElabM Unit from do
  let mut entries : Array Json := #[]
  -- Literal union-equality over ℝ: statement + svg + suggestion list with
  -- ready badges.
  entries := entries.push (← panelEntry "union_eq_real_with_suggestions"
    (← `(Set.Ioc (1:ℝ) 2 ∪ Set.Ioc 2 3 = Set.Ioc 1 3)))
  -- Membership over ℝ.
  entries := entries.push (← panelEntry "membership_real"
    (← `((3:ℝ) ∈ Set.Icc 1 4)))
  -- Nonempty over ℝ (DenselyOrdered caption).
  entries := entries.push (← panelEntry "nonempty_real_with_caption"
    (← `((Set.Ioo (1:ℝ) 2).Nonempty)))
  -- Subset mismatch over ℝ (shaded both directions, fallback suggestions).
  entries := entries.push (← panelEntry "subset_mismatch_shaded_real"
    (← `(Set.Icc (0:ℝ) 1 ⊆ Set.Ioo 0 1)))
  -- ℕ subset: discrete-type density caveat on open segments.
  entries := entries.push (← panelEntry "nat_subset_density_caveat"
    (← `(Set.Ico (0:ℕ) 2 ⊆ Set.Icc (0:ℕ) 1)))
  -- ℕ `Ioo = ∅`: discrete carrier, missing-condition badge.
  entries := entries.push (← panelEntry "nat_ioo_eq_empty_discrete"
    (← `(Set.Ioo (0:ℕ) 1 = ∅)))
  IO.FS.writeFile "../../showcase/dumps/interval-inspector.json"
    (probeDump "interval-inspector" entries).pretty
