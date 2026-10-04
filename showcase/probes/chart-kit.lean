import ChartKit

/-!
# Showcase probe: chart-kit

Dumps the exact top-level panel `Html` trees the `#chart` command attaches for
the six shipped demo charts (`renderChart` over `ChartKit.Demo`), serialized to
`../../showcase/dumps/chart-kit.json` for the showcase site's React verification
harness.

Run from the package directory (exactly how `showcase/build.sh` invokes it):

    cd packages/chart-kit && lake env lean "../../showcase/probes/chart-kit.lean"

MUST stay in sync with the package's React-contract tests
(`ChartKitTests/ContractTests.lean`): the entries dumped here are the demo
specs those tests run `reactContractViolations` over — if a panel is added
there, add its dump here.
-/

open Lean ProofWidgets ChartKit ChartKit.Demo

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

/-- `renderChart` through the real top-level entry point, failing the probe
loudly on a refused spec. -/
private def chartHtml (name : String) (s : ChartSpec) : IO Html :=
  match renderChart s with
  | .ok h => pure h
  | .error e => throw (IO.userError s!"chart-kit probe: {name}: {e}")

#eval show IO Unit from do
  let specs : Array (String × ChartSpec) := #[
    ("diceChart", diceChart),
    ("growthChart", growthChart),
    ("cdfChart", cdfChart),
    ("squaresChart", squaresChart),
    ("weekChart", weekChart),
    ("floatChart", floatChart)]
  let mut entries : Array Json := #[]
  for (name, spec) in specs do
    entries := entries.push (probeEntry name (← chartHtml name spec))
  IO.FS.writeFile "../../showcase/dumps/chart-kit.json"
    (probeDump "chart-kit" entries).pretty
