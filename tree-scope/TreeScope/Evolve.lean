import TreeScope.Widget

/-! # TreeScope: `#tree_evolve` filmstrips

```
#tree_evolve init [op1, op2, …]
#tree_evolve (text := true) init [op1, op2, …]
```

Elaborates `init : α` and each `opI : α → α`, folds the operations over the
initial value, and renders **one frame per step** — frame 0 is `init`, frame
`i` is `opI (… (op1 init))` — as a vertical filmstrip with step captions.
Every frame goes through the same value → `TreeView` pipeline as
`#tree_scope` (semantic instance first, reflection fallback, same
`maxNodes`/`maxDepth` caps per frame); a frame that fails is reported as a
`#tree_evolve` error naming the offending step.  The `(text := …)` flag
follows the same generic flag grammar as `#tree_scope`.

**Diff badging**: a node of frame `i` whose `(label, path)` pair does not
occur in frame `i−1` gets a `new` badge, and additionally the `added` tone
when it had no semantic tone of its own (semantic tones — RB colors,
violations — are never overwritten, so a recolored node keeps its color *and*
shows the badge).  The mirror count is also taken: nodes of frame `i−1`
whose `(label, path)` pair is absent from frame `i` are counted as *removed*,
so a shrinking step reads as `(+a new, −r gone)` in the caption, never as
pure growth.  Both per-frame counts appear in the captions and in text mode.

Caps: at most `maxSteps = 16` operations (pinned error beyond that).

Text mode prints, per frame, a `== step i: caption (+a new[, −r gone])` line
followed by the frame's full deterministic text report; the whole log is
pinned by `#guard_msgs` tests.
-/

namespace TreeScope

open Lean Meta Server Elab ProofWidgets

/-- Hard cap on the number of `#tree_evolve` operations. -/
def maxSteps : Nat := 16

/-- The error thrown when an evolution has more than `maxSteps` steps. -/
def stepCapError (n : Nat) : MessageData :=
  m!"#tree_evolve: {n} steps exceed the limit of {maxSteps} — TreeScope refuses to draw it"

/-! ## Pure diff marking -/

namespace TreeView

/-- Mark the nodes of `cur` that are *new* relative to the previous frame:
a node is new when the previous frame has no node at the same path with the
same label (`prev? = none` means the whole subtree's paths are absent).  New
nodes get a `new` badge, plus the `added` tone when currently `neutral`;
everything else is untouched.  Also returns the number of new nodes.
(Running it with the frames *swapped* counts the removed nodes — see
`diffCounts`.) -/
def diffMark (prev? : Option TreeView) : TreeView → TreeView × Nat
  | .mk l s b tn c cs =>
    let isNew := match prev? with
      | none => true
      | some p => p.label != l
    let pcs := match prev? with
      | none => #[]
      | some p => p.children
    let (cs', cnt, _) := cs.attach.foldl
      (fun (acc, cnt, i) ⟨ch, _⟩ =>
        let (ch', k) := diffMark pcs[i]? ch
        (acc.push ch', cnt + k, i + 1))
      ((#[] : Array TreeView), 0, (0 : Nat))
    let node := TreeView.mk l s b tn c cs'
    if isNew then
      (node.withTone (if tn == .neutral then .added else tn) |>.addBadge "new",
       cnt + 1)
    else (node, cnt)

/-- The number of `(label, path)` pairs of `prev` that are absent from `cur` —
the exact mirror of `diffMark`'s added count. -/
def removedCount (prev cur : TreeView) : Nat :=
  (diffMark (some cur) prev).2

end TreeView

/-- One filmstrip frame: caption (the reprinted operation source, or `init`),
the diff-marked view, and the added/removed node counts relative to the
previous frame (both 0 for frame 0). -/
structure Frame where
  /-- Step caption: `init` for frame 0, the operation's source text after. -/
  caption : String
  /-- The diff-marked view of this step's value. -/
  view : TreeView
  /-- Number of new `(label, path)` pairs relative to the previous frame. -/
  added : Nat
  /-- Number of `(label, path)` pairs of the previous frame absent from this
  one (the mirror diff) — a shrinking step is never shown as pure growth. -/
  removed : Nat
  deriving Repr, BEq, Inhabited

/-- The full caption line of frame `i`: `step 0: init` /
`step i: op (+a new)` / `step i: op (+a new, −r gone)` when nodes vanished. -/
def Frame.title (f : Frame) (i : Nat) : String :=
  if i == 0 then s!"step 0: {f.caption}"
  else if f.removed == 0 then s!"step {i}: {f.caption} (+{f.added} new)"
  else s!"step {i}: {f.caption} (+{f.added} new, −{f.removed} gone)"

/-! ## Rendering -/

/-- The vertical filmstrip panel: per frame a caption row (`data-frame`, with
the removed count also machine-readable as `data-removed`) and the frame's
full panel (SVG, legend, invariant caption, stats). -/
def renderFilmstrip (frames : Array Frame) : Html := Id.run do
  let mut rows : Array Html := #[]
  for h : i in [0:frames.size] do
    let f := frames[i]
    rows := rows.push <| .element "div"
      #[("style", Render.css #[("marginBottom", "10px")])]
      #[.element "div"
          #[("style", Render.css #[("fontFamily", "monospace"), ("fontSize", "12px"),
              ("fontWeight", "bold"), ("color", Render.fgColor), ("marginBottom", "2px")]),
            ("data-frame", .str (toString i)), ("data-removed", .str (toString f.removed))]
          #[.text (f.title i)],
        renderPanel f.view]
  return .element "div"
    #[("style", Render.css #[("fontFamily", "sans-serif"), ("color", Render.fgColor)])] rows

/-- The deterministic text report of a filmstrip: a header, then per frame
its caption line and full text report. -/
def filmstripReport (frames : Array Frame) : String := Id.run do
  let mut out := s!"filmstrip: {frames.size} frame{if frames.size == 1 then "" else "s"}"
  for h : i in [0:frames.size] do
    let f := frames[i]
    out := out ++ s!"\n== {f.title i}\n" ++ Render.textReport f.view
  return out

/-! ## The command -/

/-- Prefix `#tree_scope`-pipeline errors of frame `i` with the offending step
(`#tree_evolve: step i: …`), so a cap crossed mid-filmstrip names the right
command and the right step.  The inner `#tree_scope: ` prefix is stripped;
internal exceptions pass through untouched. -/
def rethrowAtStep (i : Nat) (ex : Exception) : Term.TermElabM α := do
  match ex with
  | .internal .. => throw ex
  | _ =>
    let msg ← ex.toMessageData.toString
    let inner := "#tree_scope: "
    let msg := if msg.startsWith inner then msg.drop inner.length else msg
    let step := if i == 0 then "step 0 (init)" else s!"step {i}"
    throwError "#tree_evolve: {step}: {msg}"

/-- Elaborate an evolution: `init : α`, each `opI : α → α`, fold and convert
every intermediate value (shared `#tree_scope` pipeline), diff-mark
consecutive frames (added *and* removed counts). -/
def evolveFrames (init : Syntax.Term) (ops : Array Syntax.Term) :
    Command.CommandElabM (Array Frame) :=
  Command.liftTermElabM <| Term.withoutErrToSorry do
    if ops.size > maxSteps then throwError stepCapError ops.size
    let e ← Term.elabTerm init none
    Term.synthesizeSyntheticMVarsNoPostponing
    let e ← instantiateMVars e
    let ty ← instantiateMVars (← inferType e)
    let opTy := mkForall `a .default ty ty
    let mut opEs : Array Expr := #[]
    for op in ops do
      let opE ← Term.elabTermEnsuringType op opTy
      Term.synthesizeSyntheticMVarsNoPostponing
      opEs := opEs.push (← instantiateMVars opE)
    let mut cur := e
    let mut prev? : Option TreeView := none
    let mut frames : Array Frame := #[]
    for i in [0:opEs.size + 1] do
      let caption := if i == 0 then "init"
        else ((ops[i-1]!).raw.reprint.getD "<op>").trimAscii.toString
      let tv ← try valueToTreeView cur catch ex => rethrowAtStep i ex
      let (marked, added, removed) := match prev? with
        | none => (tv, 0, 0)
        | some p =>
          let (m, a) := TreeView.diffMark (some p) tv
          (m, a, TreeView.removedCount p tv)
      frames := frames.push { caption, view := marked, added, removed }
      prev? := some tv
      if h : i < opEs.size then
        cur := mkApp opEs[i] cur
    return frames

/-- `#tree_evolve init [op1, op2, …]` folds the operations over `init` and
renders one frame per step as a vertical filmstrip, diff-badging new nodes
and counting removed ones; `(text := true)` logs the deterministic filmstrip
report instead. -/
syntax (name := treeEvolveCmd)
  "#tree_evolve" tsFlag* term:max "[" term,* "]" : command

open Command in
@[command_elab treeEvolveCmd]
def elabTreeEvolveCmd : CommandElab := fun stx => do
  match stx with
  | `(#tree_evolve $flags:tsFlag* $t:term [$ops:term,*]) =>
    let fl ← elabFlags "#tree_evolve" (allowReflect := false) flags
    let frames ← evolveFrames t (ops : Syntax.TSepArray `term ",").getElems
    if fl.text then
      logInfo (filmstripReport frames)
    else
      let ht := renderFilmstrip frames
      Command.liftCoreM <| Widget.savePanelWidgetInfo
        (hash HtmlDisplayPanel.javascript)
        (return json% { html: $(← rpcEncode ht) })
        stx
  | _ => throwUnsupportedSyntax

end TreeScope
