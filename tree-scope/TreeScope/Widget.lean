import TreeScope.Reflect
import TreeScope.Render
import TreeScope.ToTreeView
import ProofWidgets.Component.HtmlDisplay

/-! # TreeScope: the `#tree_scope` command

```
#tree_scope value
#tree_scope (text := true) value
#tree_scope (reflect := true) value
#tree_scope (reflect := true) (text := true) value
```

`#tree_scope value` evaluates the value and renders it in the InfoView.
Stage 2 dispatch: a `ToTreeView` instance for the value's type is tried
**first** (the semantic view, evaluated with the standard
`Lean.Meta.evalExpr` pattern); without one, the value is reflected into its
constructor tree (stage 1).  `(reflect := true)` forces reflection even when
an instance exists; `(text := true)` logs the deterministic text report
instead of the HTML panel (this mode is what the `#guard_msgs` tests pin).

Flags may appear in **any order**, each at most once, with an explicit
`true` or `false` value (`(text := false)` is the default panel mode).
Unknown or duplicated flags are rejected with a targeted error naming the
supported flags — not a parser error.

Both paths share the same pipeline and the same honest caps:

* `valueToTreeView` — elaborated value → `TreeView` (instance or reflection;
  the semantic result is re-checked against `maxNodes`/`maxDepth`, and cap
  errors report the measured size/depth);
* `showTreeView` — `TreeView` → InfoView panel or text log.

The value argument parses at `term:max` precedence, so applications need
parentheses: `#tree_scope (List.range 5)`.
-/

namespace TreeScope

open Lean Meta Server Elab ProofWidgets

/-- Turn an elaborated value into a `TreeView`:

1. unless `forceReflect`, try to synthesize `ToTreeView ty` for the value's
   type and evaluate `toTreeView value` (compiled, `safety := .unsafe`, the
   standard `evalExpr` pattern); the resulting tree is checked against the
   same `maxNodes`/`maxDepth` caps as reflection (with the measured size and
   depth in the error);
2. otherwise fall back to stage-1 constructor reflection (`reflectValue`).

Instance synthesis failures of any kind (including types outside `Type u`)
select the reflection path; errors *inside* an instance evaluation are
reported honestly, not swallowed. -/
def valueToTreeView (e : Expr) (forceReflect : Bool := false) : MetaM TreeView := do
  if forceReflect then
    return ← reflectValue e
  let ty ← instantiateMVars (← inferType e)
  let inst? ←
    try
      let u ← getDecLevel ty
      pure (← synthInstance? (mkApp (mkConst ``ToTreeView [u]) ty), u)
    catch _ => pure (none, Level.zero)
  match inst? with
  | (none, _) => reflectValue e
  | (some inst, u) =>
    let appE := mkApp3 (mkConst ``ToTreeView.toTreeView [u]) ty inst e
    let tv ← unsafe evalExpr' TreeView ``TreeView appE (safety := .unsafe)
    if tv.size > maxNodes then throwError nodeCapExactError tv.size
    if tv.depth > maxDepth then throwError depthCapExactError tv.depth
    return tv

/-- Elaborate the term of a `#tree_scope` command and turn the value into a
`TreeView` (semantic instance first, reflection fallback — or reflection
directly under `(reflect := true)`; see `valueToTreeView`). -/
def termToTreeView (t : Syntax.Term) (forceReflect : Bool := false) :
    Command.CommandElabM TreeView :=
  Command.liftTermElabM do
    let e ← Term.elabTerm t none
    Term.synthesizeSyntheticMVarsNoPostponing
    valueToTreeView (← instantiateMVars e) forceReflect

/-- Show a `TreeView` for the command syntax `stx`: log the deterministic text
report (`textMode`), or attach the HTML panel. -/
def showTreeView (stx : Syntax) (tv : TreeView) (textMode : Bool) :
    Command.CommandElabM Unit := do
  if textMode then
    logInfo (Render.textReport tv)
  else
    let ht := renderPanel tv
    Command.liftCoreM <| Widget.savePanelWidgetInfo
      (hash HtmlDisplayPanel.javascript)
      (return json% { html: $(← rpcEncode ht) })
      stx

/-! ## Flags

Both TreeScope commands take a leading group of `(name := true|false)`
flags, parsed generically and validated with real error messages (so a
reversed flag order or an explicit `:= false` never produces a cryptic
parser error). -/

/-- One command flag: `(name := true)` or `(name := false)`. -/
syntax tsFlag := atomic("(" ident " := " (&"true" <|> &"false") ")")

/-- The validated flag values of a TreeScope command. -/
structure Flags where
  /-- `(text := …)`: log the deterministic text report instead of the panel. -/
  text : Bool := false
  /-- `(reflect := …)`: force stage-1 reflection past a semantic instance. -/
  reflect : Bool := false
  deriving Repr, BEq, Inhabited

/-- Validate a parsed flag group for the command named `cmd` (`"#tree_scope"`
supports `text` and `reflect`; `"#tree_evolve"` only `text`).  Flags may come
in any order; unknown names and duplicates are rejected with an error naming
the supported flags. -/
def elabFlags (cmd : String) (allowReflect : Bool)
    (flags : Array (TSyntax ``tsFlag)) : Command.CommandElabM Flags := do
  let supported :=
    if allowReflect then "supported flags are (text := true|false) and (reflect := true|false)"
    else "the only supported flag is (text := true|false)"
  let mut out : Flags := {}
  let mut seen : Array String := #[]
  for f in flags do
    let (id, val) ←
      match f with
      | `(tsFlag| ($id:ident := true)) => pure (id, true)
      | `(tsFlag| ($id:ident := false)) => pure (id, false)
      | _ => throwUnsupportedSyntax
    let name := id.getId.toString
    if seen.contains name then
      throwErrorAt f "{cmd}: duplicate flag '{name}'"
    seen := seen.push name
    match name with
    | "text" => out := { out with text := val }
    | "reflect" =>
      if allowReflect then out := { out with reflect := val }
      else throwErrorAt f "{cmd}: unknown flag '{name}' — {supported}"
    | _ => throwErrorAt f "{cmd}: unknown flag '{name}' — {supported}"
  return out

/-- `#tree_scope value` renders the value in the InfoView — via its
`ToTreeView` instance when one exists, via constructor reflection otherwise.
`(text := true)` logs a deterministic text report instead; `(reflect := true)`
forces the reflection path.  Flags may come in any order. -/
syntax (name := treeScopeCmd) "#tree_scope" tsFlag* term:max : command

open Command in
@[command_elab treeScopeCmd]
def elabTreeScopeCmd : CommandElab := fun stx => do
  match stx with
  | `(#tree_scope $flags:tsFlag* $t:term) =>
    let fl ← elabFlags "#tree_scope" (allowReflect := true) flags
    showTreeView stx (← termToTreeView t (forceReflect := fl.reflect)) fl.text
  | _ => throwUnsupportedSyntax

end TreeScope
