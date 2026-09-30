import GraphScope
import GraphScopeTests.InsertTests

/-!
# Showcase probe: graph-scope

Dumps the exact top-level panel `Html` trees the `#graph_scope` command
attaches — plain panels across every rendering mode/overlay/corner case, plus
the two interactive `MakeEditLink` panels (`path3Panel`, `gateFailPanel`: the
real link renderer over the synthetic `testDocMeta` document, exactly the
`MakeEditLinkProps.ofReplaceRange` payloads a click uses) — serialized to
`../showcase/dumps/graph-scope.json` for the showcase site's React
verification harness.

Run from the package directory (exactly how `showcase/build.sh` invokes it):

    cd widgets/graph-scope && lake env lean "../showcase/probes/graph-scope.lean"

MUST stay in sync with the package's React-contract tests
(`GraphScopeTests/ContractTests.lean` for the display panels,
`GraphScopeTests/InsertTests.lean` for the interactive fixtures): the entries
dumped here are the panels those tests run `reactContractViolations` over —
if a panel is added there, add its dump here.
-/

open Lean ProofWidgets GraphScope GraphScopeTests

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

#eval show IO Unit from do
  let entries : Array Json := #[
    -- Plain panel, auto BFS-layered layout for a tree.
    probeEntry "plain_path4_auto_layered" (renderPanel (path 4)),
    -- Forced layouts.
    probeEntry "plain_circle_path4_forced" (renderPanel (path 4) (mode := .circle)),
    probeEntry "layered_cycle5_forced" (renderPanel (cycle 5) (mode := .layered)),
    -- Overlays.
    probeEntry "walk_overlay_path4" (renderPanel (path 4) (walk? := some #[0, 1, 2])),
    probeEntry "highlight_overlay_path4" (renderPanel (path 4) (highlight? := some #[0, 3])),
    probeEntry "combined_overlays_path4"
      (renderPanel (path 4) (walk? := some #[0, 1]) (highlight? := some #[3])),
    -- Corner cases.
    probeEntry "empty_graph_0" (renderPanel (empty 0)),
    probeEntry "empty_graph_3_isolated" (renderPanel (empty 3)),
    probeEntry "custom_labels_sum"
      (renderPanel (GraphData.ofEdges 2 #[(0, 1)] #["Sum.inl 0", "Sum.inr 0"])),
    -- Interactive link panels (real MakeEditLink components over the
    -- synthetic test document — the fixtures pinned by InsertTests).
    probeEntry "interactive_path3_links" path3Panel,
    probeEntry "interactive_gate_fail" gateFailPanel]
  IO.FS.writeFile "../showcase/dumps/graph-scope.json"
    (probeDump "graph-scope" entries).pretty
