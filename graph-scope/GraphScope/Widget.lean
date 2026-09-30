import GraphScope.Extract
import GraphScope.Render
import GraphScope.Gate
import ProofWidgets.Component.HtmlDisplay
import ProofWidgets.Component.MakeEditLink
import ProofWidgets.Component.OfRpcMethod

/-! # GraphScope: the `#graph_scope` command

```
#graph_scope g
#graph_scope (text := true) g
#graph_scope g walk [0, 1, 2]
#graph_scope g highlight [0, 2, 4]
#graph_scope g walk [0, 1] highlight [3]
#graph_scope g highlight [3] walk [0, 1]   -- clauses in any order
#graph_scope g layout circle               -- force the circular layout
#graph_scope g layout layered              -- force the BFS-layered layout
```

`#graph_scope g` evaluates the simple graph `g` (which needs `[Fintype V]`,
`[DecidableEq V]` and `[DecidableRel g.Adj]`) and renders it in the InfoView:
labeled vertices and degree/component/bipartiteness stats.  Forests are drawn
as BFS-layered rooted trees (root = smallest vertex of each component); other
graphs on a circle.

* `(text := true)` logs the deterministic ASCII report instead of the HTML
  panel — this mode is what the `#guard_msgs` tests pin.
* `walk [i, j, k]` overlays an ordered walk given by *vertex indices* into the
  `Fintype` enumeration (for `Fin n` graphs, the vertices themselves):
  traversed edges are emphasized and step numbers drawn.  Consecutive vertices
  must be adjacent; the command errors otherwise.
* `highlight [i, j]` overlays a highlight ring on the given vertex indices.
* `layout circle` / `layout layered` force a layout for the panel (the default
  is automatic: layered for forests, circular otherwise).  The clause is
  accepted and ignored in `(text := true)` mode.

The clauses may appear in any order, each at most once; a duplicate clause is
an error.

The graph argument parses at `term:max` precedence, so applications need
parentheses: `#graph_scope (SimpleGraph.pathGraph 5) walk [0, 1, 2]`.

Walks are given as index lists, not as `g.Walk a b` terms — see the README's
limitations section.
-/

namespace GraphScope

open Lean Meta Server Elab ProofWidgets

/-! ## The InfoView panel component

The panel is an RPC component (the `interval_inspect?` pattern): the command
stores the extracted `GraphData`, the verified insertion suggestions and the
zero-width range after the command; the RPC method runs at render time, where
`RequestM.readDoc` provides the *current* document uri and version, and only
then builds the `MakeEditLink` props.  Building the links at command time
instead would have to guess the uri from the file name (breaks for untitled
buffers) and either pin a stale document version or send unversioned edits —
the RPC hop is what keeps a click's edit tied to the live document. -/

deriving instance ToJson, FromJson for GraphData
deriving instance ToJson, FromJson for LayoutMode

/-- Props of the `#graph_scope` panel: the pure snapshot (graph, overlays,
layout), the gate-verified insertions, and where to insert (a zero-width range
at the end of the command). -/
structure PanelProps where
  /-- The extracted graph. -/
  d : GraphData
  /-- Walk overlay, if any. -/
  walk? : Option (Array Nat) := none
  /-- Highlight overlay, if any. -/
  highlight? : Option (Array Nat) := none
  /-- Requested layout. -/
  mode : LayoutMode := .auto
  /-- Gate-verified click-to-insert suggestions. -/
  links : LinkInfo := {}
  /-- Zero-width range at the command's end; insertions replace it with
  `"\n" ++ text`, so user text is never overwritten. -/
  insertRange : Lsp.Range
  deriving RpcEncodable

/-- RPC method behind the panel: reads the live document metadata and renders
the shared pure panel body with real `MakeEditLink` components. -/
@[server_rpc_method]
def GraphScopePanel.rpc (props : PanelProps) : RequestM (RequestTask Html) :=
  RequestM.asTask do
    let doc ← RequestM.readDoc
    let mkLink : MkLink := fun newText title inner =>
      .ofComponent MakeEditLink
        { MakeEditLinkProps.ofReplaceRange doc.meta props.insertRange newText
            with title? := some title }
        #[inner]
    return renderPanelInteractive props.d props.walk? props.highlight? props.mode
      props.links mkLink

/-- The `#graph_scope` panel component. -/
@[widget_module]
def GraphScopePanel : Component PanelProps :=
  mk_rpc_widget% GraphScopePanel.rpc

/-- Walk overlay clause: `walk [0, 1, 2]` (vertex indices). -/
syntax walkClause := &"walk" "[" num,* "]"

/-- Highlight overlay clause: `highlight [0, 2]` (vertex indices). -/
syntax highlightClause := &"highlight" "[" num,* "]"

/-- Layout clause: `layout circle` or `layout layered` (default: automatic —
layered for forests, circular otherwise). -/
syntax layoutClause := &"layout" (&"circle" <|> &"layered")

/-- Any `#graph_scope` clause: walk, highlight or layout, in any order. -/
syntax graphScopeClause := walkClause <|> highlightClause <|> layoutClause

/-- `#graph_scope g` renders the simple graph `g` in the InfoView; clicking a
drawn edge, a vertex, or the components stats line inserts a gate-verified
`example : … := by decide` on a new line after the command.
`#graph_scope (text := true) g` logs a deterministic ASCII report instead.
Optional clauses (any order, each at most once): `walk [i, …]` (ordered walk,
edges emphasized with step numbers, by vertex index), `highlight [i, …]`
(vertex rings, by vertex index) and `layout circle`/`layout layered` (force a
panel layout). -/
syntax (name := graphScopeCmd)
  "#graph_scope" (atomic("(" &"text" " := " &"true" ")"))? term:max
    (graphScopeClause)* : command

open Command in
@[command_elab graphScopeCmd]
def elabGraphScopeCmd : CommandElab := fun stx => do
  match stx with
  | `(#graph_scope $t:term $cs:graphScopeClause*) =>
    go stx t false cs
  | `(#graph_scope (text := true) $t:term $cs:graphScopeClause*) =>
    go stx t true cs
  | _ => throwUnsupportedSyntax
where
  /-- Shared elaboration: extract, sort/validate the clauses, then log text or
  attach the HTML panel. -/
  go (stx : Syntax) (t : Syntax.Term) (textMode : Bool)
      (cs : Array (TSyntax ``graphScopeClause)) : CommandElabM Unit := do
    -- Collect the clauses first (pure parsing concerns), so a malformed or
    -- duplicate clause errors before anything is extracted or rendered.
    let mut walk? : Option (Array Nat) := none
    let mut highlight? : Option (Array Nat) := none
    let mut mode : LayoutMode := .auto
    let mut sawLayout := false
    for c in cs do
      match c with
      | `(graphScopeClause| walk [$ns,*]) =>
        if walk?.isSome then
          throwErrorAt c "#graph_scope: duplicate `walk` clause"
        walk? := some (ns.getElems.map (·.getNat))
      | `(graphScopeClause| highlight [$ns,*]) =>
        if highlight?.isSome then
          throwErrorAt c "#graph_scope: duplicate `highlight` clause"
        highlight? := some (ns.getElems.map (·.getNat))
      | `(graphScopeClause| layout circle) =>
        if sawLayout then
          throwErrorAt c "#graph_scope: duplicate `layout` clause"
        sawLayout := true
        mode := .circle
      | `(graphScopeClause| layout layered) =>
        if sawLayout then
          throwErrorAt c "#graph_scope: duplicate `layout` clause"
        sawLayout := true
        mode := .layered
      | _ => throwUnsupportedSyntax
    let (d, g) ← liftTermElabM do
      let g ← Term.elabTerm t none
      Term.synthesizeSyntheticMVarsNoPostponing
      let g ← instantiateMVars g
      return (← extractGraphData g, g)
    if let some w := walk? then
      if let some err := d.walkError? w then
        throwError "#graph_scope: invalid walk — {err}"
    if let some hs := highlight? then
      if let some err := d.highlightError? hs then
        throwError "#graph_scope: invalid highlight — {err}"
    if textMode then
      logInfo (Render.textReport d walk? highlight?)
    else
      let fm ← getFileMap
      match fm.lspRangeOfStx? stx, t.raw.getRange? with
      | some cmdRange, some tRange =>
        -- The interactive panel: verbatim graph source for the inserted
        -- examples, gate-verified links, and a zero-width insertion range at
        -- the command's end (insertions go on a new line after the command
        -- and never replace user text).
        let gSrc := String.Pos.Raw.extract fm.source tRange.start tRange.stop
        let links ← liftTermElabM <| computeInsertions gSrc g d
        let props : PanelProps :=
          { d, walk?, highlight?, mode, links
            insertRange := { start := cmdRange.end, «end» := cmdRange.end } }
        liftCoreM <| Widget.savePanelWidgetInfo
          (hash GraphScopePanel.javascript) (rpcEncode props) stx
      | _, _ =>
        -- Synthesized syntax without a source range: no sound place to
        -- insert, so fall back to the display-only panel.
        let ht := renderPanel d walk? highlight? mode
        liftCoreM <| Widget.savePanelWidgetInfo
          (hash HtmlDisplayPanel.javascript)
          (return json% { html: $(← rpcEncode ht) })
          stx

end GraphScope
