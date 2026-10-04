import HasseView.Extract
import HasseView.Render
import HasseView.Gate
import ProofWidgets.Component.HtmlDisplay
import ProofWidgets.Component.OfRpcMethod
import ProofWidgets.Component.MakeEditLink

/-! # HasseView: the `#hasse` command

```
#hasse V
#hasse (text := true) V
#hasse V highlight [0, 2]
#hasse V updown 3
#hasse V updown 3 highlight [0]      -- clauses in any order
#hasse V highlight [0] updown 3
```

`#hasse V` evaluates the order of the finite type `V` (which needs
`[Fintype V]`, `[DecidableEq V]`, `[LE V]` and `[DecidableLE V]`) and renders
its Hasse diagram in the InfoView: one row per rank, minimal elements at the
bottom, cover edges pointing upward, ⊥/⊤ and atom/coatom badges, and a
caption with the lattice verdict (with a concrete witness pair when the
verdict is negative), height, antichain lower bound and any partial-order
validity warnings — plus an **insertable examples** section whose links
insert gate-verified `example : … := by decide` commands on a new line after
the `#hasse` command (see `HasseView/Gate.lean` for the honesty gate).

* `(text := true)` logs the deterministic ASCII report instead of the HTML
  panel — this mode is what the `#guard_msgs` tests pin.
* `highlight [i, j]` overlays a highlight ring on the given *element indices*
  (positions in the `Fintype` enumeration; for `Fin n`, the elements
  themselves).
* `updown i` shades the upset of element `i` in one color and its downset in
  another, and emphasizes `i` itself.

The clauses may appear in any order, each at most once; a duplicate clause is
an error.  The type argument parses at `term:max` precedence, so
applications need parentheses: `#hasse (Fin 5)`.

## How the links get document context

`MakeEditLink` needs a `Lsp.TextDocumentEdit` naming the file's uri and
version — data that only the language *server* has (a command elaborates
against source text; the LSP document version is not part of the elaboration
context, and a version-stamped edit built from a guessed uri would go stale
on every keystroke).  So the command follows the proven RPC-panel pattern
(cf. interval-inspector): it stores plain-data props (`PosetData`, overlays,
gate-verified link texts, and the zero-width insertion range at the
command's end) via `savePanelWidgetInfo`, and the `HassePanel.rpc` method —
running in `RequestM` at render time, where `RequestM.readDoc` provides the
authoritative `DocumentMeta` — wraps the stored texts in `MakeEditLink`
components.  All *verification* already happened at command time; the RPC
layer only adds document plumbing, and the panel body itself is the pure
`renderPanelWith`, directly callable by tests.
-/

namespace HasseView

open Lean Meta Server Elab ProofWidgets

deriving instance ToJson, FromJson for PosetData

/-- Props of the interactive Hasse panel: everything the render needs, as
plain data.  Stored by the command via `savePanelWidgetInfo`; the document
context (uri/version) is added at render time by `HassePanel.rpc`. -/
structure HassePanelProps where
  /-- Zero-width range at the end of the `#hasse` command — the insertion
  point (every `newText` starts with `"\n"`, so nothing the user wrote is
  ever replaced). -/
  insertRange : Lsp.Range
  /-- The extracted poset. -/
  data : PosetData
  /-- `highlight [..]` overlay, if any. -/
  highlight? : Option (Array Nat) := none
  /-- `updown i` overlay, if any. -/
  updown? : Option Nat := none
  /-- The gate-verified insertable-example candidates. -/
  links : PanelLinks := .empty
  deriving ToJson, FromJson, Server.RpcEncodable

/-- The `MakeEditLink`-based link renderer: clicking inserts `newText` at
`range` (zero-width ⇒ pure insertion) and moves the cursor to the end of the
inserted example.  Factored out so tests can serialize the exact component
tree the RPC method returns. -/
def editLink (docMeta : DocumentMeta) (range : Lsp.Range) :
    String → String → Html := fun display newText =>
  .ofComponent MakeEditLink (.ofReplaceRange docMeta range newText)
    #[.text display]

/-- RPC method behind the interactive panel: reads the authoritative
document metadata and renders the pure panel body with clickable
`MakeEditLink`s for the gate-verified candidates. -/
@[server_rpc_method]
def HassePanel.rpc (props : HassePanelProps) : RequestM (RequestTask Html) :=
  RequestM.asTask do
    let doc ← RequestM.readDoc
    return renderPanelWith props.data props.highlight? props.updown?
      props.links (editLink doc.meta props.insertRange)

/-- The interactive Hasse panel component. -/
@[widget_module]
def HassePanel : Component HassePanelProps :=
  mk_rpc_widget% HassePanel.rpc

/-- Highlight overlay clause: `highlight [0, 2]` (element indices). -/
syntax highlightClause := &"highlight" "[" num,* "]"

/-- The user's original syntax for a term, verbatim (leading/trailing space
stripped), falling back to pretty-printing for synthetic syntax without
positions.  Single source of truth for the type text reused in inserted
examples — the command and the test helpers must use THIS function so the
compiled-insertion tests always verify the exact rule the command applies. -/
def userSyntaxString (t : Syntax.Term) : String :=
  ((t.raw.getSubstring? (withLeading := false)
      (withTrailing := false)).map (·.toString)).getD (toString t.raw.prettyPrint)

/-- Upset/downset overlay clause: `updown 3` (an element index). -/
syntax updownClause := &"updown" num

/-- Any `#hasse` clause: highlight or updown, in any order. -/
syntax hasseClause := highlightClause <|> updownClause

/-- `#hasse V` renders the Hasse diagram of the finite ordered type `V` in
the InfoView (with click-to-insert example links);
`#hasse (text := true) V` logs a deterministic ASCII report instead.
Optional clauses (any order, each at most once): `highlight [i, …]`
(element rings, by element index) and `updown i` (upset/downset shading of
element `i`). -/
syntax (name := hasseCmd)
  "#hasse" (atomic("(" &"text" " := " &"true" ")"))? term:max
    (hasseClause)* : command

open Command in
@[command_elab hasseCmd]
def elabHasseCmd : CommandElab := fun stx => do
  match stx with
  | `(#hasse $t:term $cs:hasseClause*) =>
    go stx t false cs
  | `(#hasse (text := true) $t:term $cs:hasseClause*) =>
    go stx t true cs
  | _ => throwUnsupportedSyntax
where
  /-- Shared elaboration: parse/validate the clauses (before anything is
  extracted), extract (and, in panel mode, run the link gate), validate
  overlay indices, then log text or attach the interactive panel. -/
  go (stx : Syntax) (t : Syntax.Term) (textMode : Bool)
      (cs : Array (TSyntax ``hasseClause)) : CommandElabM Unit := do
    -- Collect the clauses first (pure parsing concerns), so a malformed or
    -- duplicate clause errors before anything is extracted or rendered.
    let mut highlight? : Option (Array Nat) := none
    let mut updown? : Option Nat := none
    for c in cs do
      match c with
      | `(hasseClause| highlight [$ns,*]) =>
        if highlight?.isSome then
          throwErrorAt c "#hasse: duplicate `highlight` clause"
        highlight? := some (ns.getElems.map (·.getNat))
      | `(hasseClause| updown $n:num) =>
        if updown?.isSome then
          throwErrorAt c "#hasse: duplicate `updown` clause"
        updown? := some n.getNat
      | _ => throwUnsupportedSyntax
    -- The user's original type syntax, verbatim — reused in inserted texts.
    let tyStr := userSyntaxString t
    let (d, links) ← liftTermElabM do
      let V ← Term.elabTerm t none
      Term.synthesizeSyntheticMVarsNoPostponing
      let V ← instantiateMVars V
      let d ← extractPosetData V
      -- Text mode never shows links; skip the gate entirely.
      let links ← if textMode then pure PanelLinks.empty else buildLinks V tyStr d
      return (d, links)
    if let some hs := highlight? then
      if let some err := d.highlightError? hs then
        throwError "#hasse: invalid highlight — {err}"
    if let some f := updown? then
      if let some err := d.updownError? f then
        throwError "#hasse: invalid updown — {err}"
    if textMode then
      logInfo (Render.textReport d highlight? updown?)
    else
      match (← getFileMap).lspRangeOfStx? stx with
      | some cmdRange =>
        let props : HassePanelProps :=
          { insertRange := ⟨cmdRange.end, cmdRange.end⟩
            data := d, highlight?, updown?, links }
        liftCoreM <| Widget.savePanelWidgetInfo
          (hash HassePanel.javascript) (rpcEncode props) stx
      | none =>
        -- Synthetic syntax without positions (e.g. macro-generated): fall
        -- back to the link-free static panel rather than dropping the
        -- diagram.
        let ht := renderPanel d highlight? updown?
        liftCoreM <| Widget.savePanelWidgetInfo
          (hash HtmlDisplayPanel.javascript)
          (return json% { html: $(← rpcEncode ht) })
          stx

end HasseView
