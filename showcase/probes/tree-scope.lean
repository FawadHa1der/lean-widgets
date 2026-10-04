import TreeScope

/-!
# Showcase probe: tree-scope

Dumps the exact top-level panel `Html` trees the `#tree_scope` /
`#tree_evolve` commands attach — the plain and fully-annotated single-tree
panels, the forest grid, the Catalan gallery, the two-frame diff filmstrip,
and the real 4-step RBMap evolution (elaborated through the same
`evolveFrames` pipeline the `#tree_evolve` command uses, so the rotation at
step 3 carries its genuine diff badges) — serialized to
`../../showcase/dumps/tree-scope.json` for the showcase site's React
verification harness.

Run from the package directory (exactly how `showcase/build.sh` invokes it):

    cd packages/tree-scope && lake env lean "../../showcase/probes/tree-scope.lean"

MUST stay in sync with the package's React-contract tests
(`TreeScopeTests/RenderTests.lean`, `CatalanTests.lean`, `EvolveTests.lean`):
the entries dumped here are the panels those tests run
`reactContractViolations` over — if a panel is added there, add its dump
here.  The `tA`/`tB`/`strip` fixtures are private in the test lib, so they
are re-defined here verbatim.
-/

open Lean Elab ProofWidgets TreeScope TreeScope.TreeView TreeScope.Render TreeScope.BinTree

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

/-- Root with two leaves (`RenderTests.tB`). -/
private def tB : TreeView := make "r" #[leaf "a", leaf "b"]

/-- One child per non-neutral tone, plus a collapsed subtree hiding 2 nodes
(`RenderTests.tA`). -/
private def tA : TreeView :=
  make "root" (sublabel := "h=3") (children := #[
    leaf "r" |>.withTone .rbRed,
    leaf "b" |>.withTone .rbBlack,
    leaf "o" |>.withTone .ok,
    leaf "v" |>.withTone .violation |>.addBadge "dup",
    leaf "h" |>.withTone .highlight,
    leaf "n" |>.withTone .added,
    make "z" (collapsed := true) (children := #[leaf "z1", leaf "z2"])])

/-- Two-leaf sample (`EvolveTests.dA`). -/
private def dA : TreeView := make "a" #[leaf "b", leaf "c"]
/-- Same shape, one child relabeled (`EvolveTests.dB`). -/
private def dB : TreeView := make "a" #[leaf "b", leaf "x"]

/-- A tiny two-frame strip (`EvolveTests.strip`). -/
private def strip : Array Frame :=
  #[⟨"init", dA, 0, 0⟩, ⟨"op", (diffMark (some dA) dB).1, 1, 1⟩]

/-- Run the real `#tree_evolve` pipeline (`evolveFrames`) on the given source
syntax — so op captions are the genuine `reprint`ed source text — and write
the full dump.  Defined as a command so the evolution arguments are parsed
unhygienically, exactly like a user's `#tree_evolve`. -/
elab "#tree_scope_probe_dump " t:term:max "[" ops:term,* "]" : command => do
  let frames ← evolveFrames t (ops : Syntax.TSepArray `term ",").getElems
  let entries : Array Json := #[
    probeEntry "panel-plain-tB" (renderPanel tB),
    probeEntry "panel-annotated-tA" (renderPanel tA),
    probeEntry "forest-grid-tB-tA-tB" (renderForest #[tB, tA, tB] (maxRowWidth := 400)),
    probeEntry "forest-catalan-gallery-n4"
      (renderForest (catalanGallery 4) (maxRowWidth := 900)),
    probeEntry "filmstrip-two-frame-strip" (renderFilmstrip strip),
    probeEntry "filmstrip-rbmap-evolution-4-steps" (renderFilmstrip frames)]
  IO.FS.writeFile "../../showcase/dumps/tree-scope.json"
    (probeDump "tree-scope" entries).pretty

#tree_scope_probe_dump (Lean.RBMap.empty : Lean.RBMap Nat String compare) [
  (·.insert 1 "a"), (·.insert 2 "b"), (·.insert 3 "c"), (·.insert 4 "d")]
