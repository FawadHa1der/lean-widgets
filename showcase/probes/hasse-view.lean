import HasseView
import HasseViewTests.Helpers

/-!
# Showcase probe: hasse-view

Dumps the exact top-level panel `Html` trees the `#hasse` command attaches —
plain panels for every poset shape, overlay panels, validity-warning panels,
plus the two interactive link panels (`renderPanelWith` over the `fin3Links` /
`rejectedLinks` fixtures with the real `editLink` renderer and the synthetic
`testDocMeta` document, exactly the `MakeEditLinkProps.ofReplaceRange` payloads
a click uses) — serialized to `../../showcase/dumps/hasse-view.json` for the
showcase site's React verification harness.

Run from the package directory (exactly how `showcase/build.sh` invokes it):

    cd packages/hasse-view && lake env lean "../../showcase/probes/hasse-view.lean"

MUST stay in sync with the package's React-contract tests
(`HasseViewTests/ContractTests.lean`): the entries dumped here are the panels
those tests run `reactContractViolations` over — if a panel is added there,
add its dump here.
-/

open Lean ProofWidgets HasseView HasseViewTests

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
    -- Plain panels over the demo shapes.
    probeEntry "powerset-cube" (renderPanel (cubeP 3)),
    probeEntry "divisors-of-12" (renderPanel divisor12P),
    probeEntry "bowtie-non-lattice" (renderPanel bowtieP),
    -- Overlay panels.
    probeEntry "updown-overlay-cube" (renderPanel (cubeP 3) (updown? := some 1)),
    probeEntry "highlight-overlay-cube"
      (renderPanel (cubeP 3) (highlight? := some #[0, 7])),
    probeEntry "combined-overlays-cube"
      (renderPanel (cubeP 3) (highlight? := some #[0]) (updown? := some 1)),
    -- Warning captions (invalid tables still render, with warning lines).
    probeEntry "validity-warning-broken" (renderPanel brokenP),
    probeEntry "validity-warning-not-antisym" (renderPanel notAntisymP),
    -- Interactive link panels (real MakeEditLink components over the
    -- synthetic test document — the fixtures pinned by the contract tests).
    probeEntry "links-panel-fin3-editlinks"
      (renderPanelWith (chainP 3) (links := fin3Links)
        (mkLink := editLink testDocMeta testInsertRange)),
    probeEntry "links-panel-rejected"
      (renderPanelWith (chainP 3) (links := rejectedLinks)
        (mkLink := editLink testDocMeta testInsertRange))]
  IO.FS.writeFile "../../showcase/dumps/hasse-view.json"
    (probeDump "hasse-view" entries).pretty
