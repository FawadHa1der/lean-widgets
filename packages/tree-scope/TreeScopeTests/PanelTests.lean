import TreeScopeTests.Helpers

/-! # Panel-mode props tests: what `#tree_scope` / `#tree_evolve` actually store

The panel-mode `#guard_msgs` tests in `CommandTests`, `DispatchTests` and
`EvolveTests` only prove that panel mode elaborates without messages; they
would pass if the command put the wrong tree into the panel.  This file reads
the panel back out of the info tree.

`#capture_panels n in cmd` elaborates `cmd` (its messages pass through
unchanged, so `#guard_msgs` can wrap it) with info trees enabled, then
defines `n : Array StoredWidget` from every `UserWidgetInfo` leaf `cmd` saved:
the widget module name and javascript hash, the kind of the syntax the widget
is attached to and whether that syntax is `cmd` itself (same source range),
and the props forced with an empty RPC object store.

Each scenario then demands, with separate `#guard`s:

* exactly one widget, the `HtmlDisplayPanel` module, attached to the command;
* props exactly `{ html: rpcEncode h }`, where `h` is rendered from a
  **hand-written** expected `TreeView` (or filmstrip), never from the value;
* the stored `html` decodes through `HtmlDisplayProps`' own `RpcEncodable`
  instance (the panel's props type) to the same tree as `h`;
* user-visible text (stats line, invariant caption, step captions) is present
  in the decoded panel.

Scenarios: a core `Lean.RBMap` and a Mathlib `BinaryTree` (semantic path), a
`List` (reflection fallback), and a `#tree_evolve` `Lean.RBMap` filmstrip.
-/

namespace TreeScopeTests
namespace PanelProps

open Lean Elab Command Server TreeScope TreeScope.TreeView ProofWidgets

/-! ## Capturing stored widgets -/

/-- One `UserWidgetInfo` saved while elaborating a command, as stored. -/
structure StoredWidget where
  /-- Name of the `@[widget_module]` (`WidgetInstance.id`). -/
  id : Name
  /-- Javascript hash of the widget module (`WidgetInstance.javascriptHash`). -/
  hash : UInt64
  /-- Kind of the syntax the widget is attached to (`UserWidgetInfo.stx`). -/
  kind : SyntaxNodeKind
  /-- Is the attached syntax the captured command itself (same source range)? -/
  onCmd : Bool
  /-- The props, forced with an empty RPC object store, compressed. -/
  props : String
  deriving Inhabited, Repr

/-- Every `UserWidgetInfo` in an info tree, in tree order. -/
partial def storedWidgetsIn (cmd : Syntax) : InfoTree → Array StoredWidget
  | .context _ t => storedWidgetsIn cmd t
  | .node i cs =>
    let here := match i with
      | .ofUserWidgetInfo wi =>
        #[{ id := wi.id, hash := wi.javascriptHash, kind := wi.stx.getKind
            onCmd := wi.stx.getPos?.isSome && wi.stx.getPos? == cmd.getPos?
              && wi.stx.getTailPos? == cmd.getTailPos?
            props := (wi.props.run {}).1.compress }]
      | _ => #[]
    cs.foldl (fun acc c => acc ++ storedWidgetsIn cmd c) here
  | .hole _ => #[]

/-- `#capture_panels n in cmd`: elaborate `cmd` with info trees enabled and
define `n : Array StoredWidget` with every user widget `cmd` saved.  The
surrounding info state is restored afterwards. -/
syntax (name := capturePanelsCmd) "#capture_panels " ident " in" ppLine command : command

@[command_elab capturePanelsCmd]
def elabCapturePanels : CommandElab
  | `(#capture_panels $n:ident in $cmd:command) => do
    let saved ← getInfoState
    modifyInfoState fun _ => { enabled := true }
    withReader ({ · with snap? := none }) <| elabCommand cmd
    let trees := (← getInfoState).trees
    modifyInfoState fun _ => saved
    let ws := trees.toArray.flatMap (storedWidgetsIn cmd)
    let elems ← ws.mapM fun w =>
      `(StoredWidget.mk $(quote w.id) ($(Syntax.mkNumLit (toString w.hash)) : UInt64)
          $(quote w.kind) $(quote w.onCmd) $(quote w.props))
    elabCommand (← `(def $n : Array StoredWidget := #[$elems,*]))
  | _ => throwUnsupportedSyntax

/-! ## Expected props -/

/-- Exactly one widget was stored: the `HtmlDisplayPanel` module (name and
javascript hash), attached to the captured command itself, of kind `k`. -/
def onePanelOn (k : SyntaxNodeKind) (ws : Array StoredWidget) : Bool :=
  ws.size == 1 && ws.all fun w =>
    w.id == ``HtmlDisplayPanel && w.hash == hash HtmlDisplayPanel.javascript
      && w.kind == k && w.onCmd

/-- The props a TreeScope panel showing `h` must store: exactly
`{ html: rpcEncode h }` (forced with an empty RPC object store, like
`storedWidgetsIn`), compressed. -/
def expectedProps (h : Html) : String :=
  (Json.mkObj [("html", ((rpcEncode h).run {}).1)]).compress

/-- The stored props decoded through `HtmlDisplayProps`' own `RpcEncodable`
instance (the props type of `HtmlDisplayPanel`), the `html` field serialized
with `htmlToDebugString`; `none` when the props do not parse or decode. -/
def decodedHtml (w : StoredWidget) : Option String := do
  let j ← (Json.parse w.props).toOption
  let r : ExceptT String (ReaderT RpcObjectStore Id) HtmlDisplayProps := rpcDecode j
  let p ← (Id.run (r.run.run {})).toOption
  return htmlToDebugString p.html

/-! ## `#tree_scope`, semantic path: a core `Lean.RBMap` -/

/-- A 4-entry map: black root, black children, one red grandchild. -/
def rbm4 : Lean.RBMap Nat String compare :=
  Lean.RBMap.empty |>.insert 1 "a" |>.insert 2 "b" |>.insert 3 "c" |>.insert 4 "d"

/-- Its semantic view, written by hand (cf. step 4 of the `EvolveTests` pin). -/
def rbm4View : TreeView :=
  .mk "2:\"b\"" (some "bh=2") #[] .rbBlack false #[
    .mk "1:\"a\"" (some "bh=1") #[] .rbBlack false #[],
    .mk "3:\"c\"" (some "bh=1") #[] .rbBlack false #[
      .mk "4:\"d\"" (some "bh=0") #[] .rbRed false #[]]]

-- The hand-written view is the instance's view (pure).
#guard toTreeView rbm4 == rbm4View

#guard_msgs in
#capture_panels rbPanel in
#tree_scope rbm4

#guard onePanelOn ``TreeScope.treeScopeCmd rbPanel
#guard rbPanel[0]!.props == expectedProps (renderPanel rbm4View)
#guard decodedHtml rbPanel[0]! == some (htmlToDebugString (renderPanel rbm4View))
#guard containsSubstr ((decodedHtml rbPanel[0]!).getD "") "tree: 4 nodes, depth 3"
#guard containsSubstr ((decodedHtml rbPanel[0]!).getD "") "data-caption=\"invariants ok\""

/-! ## `#tree_scope`, semantic path: a Mathlib `BinaryTree`

The `MathlibTreeTests` text pin of the same value: both-`nil` children elided,
the single `nil` child of `3` drawn as a `∅` stub. -/

/-- The expected view of `node 2 (node 1 nil nil) (node 3 (node 4 nil nil) nil)`. -/
def binView : TreeView :=
  make "2" #[leaf "1", make "3" #[leaf "4", leaf "∅"]]

#guard toTreeView (BinaryTree.node 2 (.node 1 .nil .nil) (.node 3 (.node 4 .nil .nil) .nil))
  == binView

#guard_msgs in
#capture_panels binPanel in
#tree_scope (BinaryTree.node 2 (.node 1 .nil .nil) (.node 3 (.node 4 .nil .nil) .nil))

#guard onePanelOn ``TreeScope.treeScopeCmd binPanel
#guard binPanel[0]!.props == expectedProps (renderPanel binView)
#guard decodedHtml binPanel[0]! == some (htmlToDebugString (renderPanel binView))
#guard containsSubstr ((decodedHtml binPanel[0]!).getD "") "tree: 5 nodes, depth 3"

/-! ## `#tree_scope`, reflection fallback: a `List` (no instance)

The panel-mode command of `CommandTests`, whose comment says "the widget is
attached to stx": now checked. -/

/-- The constructor tree of `[1, 2]` (cf. the `(text := true)` pins). -/
def listView : TreeView := make "cons 1" #[make "cons 2" #[leaf "nil"]]

#guard_msgs in
#capture_panels listPanel in
#tree_scope [1, 2]

#guard onePanelOn ``TreeScope.treeScopeCmd listPanel
#guard listPanel[0]!.props == expectedProps (renderPanel listView)
#guard decodedHtml listPanel[0]! == some (htmlToDebugString (renderPanel listView))

/-! ## `#tree_evolve`: an `Lean.RBMap` filmstrip

Frame 0 is not diff-marked; step 1 replaces the `(empty)` placeholder
(`+1 new, −1 gone`); step 2 adds a red right child (`+1 new`).  Cf. the first
three frames of the `EvolveTests` 4-step pin. -/

/-- The expected frames, written by hand. -/
def evoFrames : Array Frame := #[
  ⟨"init", leaf "(empty)", 0, 0⟩,
  ⟨"(·.insert 1 \"a\")", .mk "1:\"a\"" (some "bh=0") #["new"] .rbRed false #[], 1, 1⟩,
  ⟨"(·.insert 2 \"b\")", .mk "1:\"a\"" (some "bh=1") #[] .rbBlack false #[
      .mk "2:\"b\"" (some "bh=0") #["new"] .rbRed false #[]], 1, 0⟩]

#guard_msgs in
#capture_panels evoPanel in
#tree_evolve (Lean.RBMap.empty : Lean.RBMap Nat String compare) [(·.insert 1 "a"), (·.insert 2 "b")]

#guard onePanelOn ``TreeScope.treeEvolveCmd evoPanel
#guard evoPanel[0]!.props == expectedProps (renderFilmstrip evoFrames)
#guard decodedHtml evoPanel[0]! == some (htmlToDebugString (renderFilmstrip evoFrames))
#guard countOccurrences ((decodedHtml evoPanel[0]!).getD "") "data-frame=" == 3
#guard containsSubstr ((decodedHtml evoPanel[0]!).getD "") "step 1: (·.insert 1 \"a\") (+1 new, −1 gone)"
#guard containsSubstr ((decodedHtml evoPanel[0]!).getD "") "step 2: (·.insert 2 \"b\") (+1 new)"

end PanelProps
end TreeScopeTests
