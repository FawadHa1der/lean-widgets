import TreeScope.Model
import Lean

/-! # TreeScope: reflection of concrete values into `TreeView`

The stage-1 universal fallback: turn *any* concrete inductive value into its
constructor tree, by recursively `whnf`-ing the value in `MetaM`.

This is genuine **term-structure reflection of evaluated values** — not `Repr`
(no `Repr` instance is ever used, so it works for types without one), and not
a syntax tree (unlike expr-xray-style widgets, the value is *evaluated*:
`#tree_scope (2 + 2)` shows the single node `4`, and `#tree_scope (deepN 5)`
unfolds the definition).

Shape of the reflected tree, per node:

* the node label is the constructor's short name (`cons`, `some`, `mk`, …);
* **explicit** constructor fields whose types are inductives become child
  subtrees, in field order;
* literal-like explicit fields fold into the node label instead of becoming
  children: `Nat` and `String` literals, `Char`s (as `'a'`), `Int`s (as
  `-3`), `Float`/`Float32`s (compiled-evaluated and printed with their
  `toString`, e.g. `1.500000`), and free variables (by name);
* other non-inductive explicit fields (e.g. functions) fold into the label as
  their pretty-printed form in `⟨…⟩`;
* implicit fields and proofs (`Prop`-typed fields) are skipped;
* when a folded field comes *after* a child field, all folded fields are shown
  positionally with `_` placeholders for children (`mk _ 3`), so the label
  never misrepresents the field order.

**Chain compaction**: a value that is a pure single-child constructor spine
(`List`/`Array`-like cons chains, nested `Option`s, …) deeper than `maxDepth`
would be refused as a 1-node-per-level spine; instead the *top-level* value is
rendered as the depth-2 sequence `chain · n=len` with one leaf per spine node
(`reflectValue` → `compactChain?`).  Chains that fit within the depth cap keep
their ordinary spine rendering, and over-deep chains that *branch* somewhere
are still refused (with a measured, actionable error).

Caps (checked during the traversal, with honest pinned errors):
`maxDepth = 64` levels and `maxNodes = 128` nodes.  Cap errors report the
measured quantity: exact node counts where known (compacted chains), a
measured lower bound on the nesting depth otherwise (via `probeSpine`).
-/

namespace TreeScope

open Lean Meta

/-- Hard cap on the reflection depth (levels of nesting). -/
def maxDepth : Nat := 64

/-- Hard cap on the number of reflected nodes. -/
def maxNodes : Nat := 128

/-- Fuel for the spine probe and chain compaction (how far along a
single-child spine TreeScope is willing to walk to *measure* a value). -/
def probeFuel : Nat := 1024

/-- Pretty-print an expression to a single line (deterministic error text). -/
def ppOneLine (e : Expr) : MetaM String := do
  return (← ppExpr e).pretty (width := 100000)

/-- Try to render an already-`whnf`-ed expression as a literal label fragment:
`Nat`/`String` literals, `Char`s, `Int`s, `Float`/`Float32`s, free variables
(see the module docstring).  Floats never `whnf` to constructor applications
(the type is a structure over an opaque spec), so they are compiled-evaluated
and printed via `toString` — deterministic for any concrete float.  Returns
`none` when the value is not literal-like. -/
def foldLit? (e : Expr) : MetaM (Option String) := do
  match e with
  | .lit (.natVal n) => return some (toString n)
  | .lit (.strVal s) => return some s.quote
  | .fvar id => return some (toString (← id.getUserName))
  | _ =>
    let ty ← whnf (← inferType e)
    if ty.isConstOf ``Char then
      let n ← whnf (mkApp (mkConst ``Char.toNat) e)
      if let .lit (.natVal n) := n then
        return some s!"'{Char.ofNat n}'"
      else return none
    else if ty.isConstOf ``Int then
      if e.isAppOfArity ``Int.ofNat 1 then
        if let .lit (.natVal n) := ← whnf e.appArg! then
          return some (toString n)
        else return none
      else if e.isAppOfArity ``Int.negSucc 1 then
        if let .lit (.natVal n) := ← whnf e.appArg! then
          return some s!"-{n + 1}"
        else return none
      else return none
    else if ty.isConstOf ``Float then
      try
        let f ← unsafe evalExpr' Float ``Float e
        return some (toString f)
      catch _ => return none
    else if ty.isConstOf ``Float32 then
      try
        let f ← unsafe evalExpr' Float32 ``Float32 e
        return some (toString f)
      catch _ => return none
    else return none

/-- Is `ty` (a type in whnf) an application of an inductive type constant? -/
def isInductiveApp (ty : Expr) : MetaM Bool := do
  match ty.getAppFn with
  | .const c _ =>
    match (← getEnv).find? c with
    | some (.inductInfo _) => return true
    | _ => return false
  | _ => return false

/-- The error thrown when the reflection traversal crosses the node cap (the
traversal aborts on the 129th node, so only the bound itself is known). -/
def nodeCapError : MessageData :=
  m!"#tree_scope: the value has more than {maxNodes} nodes — TreeScope refuses to draw it"

/-- Node-cap error with an exact measured count (semantic path, compacted
chains — matching GraphScope's message style). -/
def nodeCapExactError (n : Nat) : MessageData :=
  m!"#tree_scope: the value has {n} nodes, more than the limit of {maxNodes} — TreeScope refuses to draw it"

/-- Depth-cap error with an exact measured depth (semantic path). -/
def depthCapExactError (n : Nat) : MessageData :=
  m!"#tree_scope: the value nests {n} levels deep, more than the limit of {maxDepth} — TreeScope refuses to draw it"

/-- Depth-cap error on the reflection path: the traversal stops at the cap, so
only a measured *lower bound* (cap + spine probe) is known; the hint names the
usual culprit (cons chains count one level per element). -/
def depthCapReflectError (lower : Nat) : MessageData :=
  m!"#tree_scope: the value nests at least {lower} levels deep, more than the limit of {maxDepth} — chains count one level per element; render a shorter prefix — TreeScope refuses to draw it"

/-- Throw the honest "not a concrete value" error for `e` (the *un*-`whnf`-ed
expression, so the message shows what the user wrote / the field as stored). -/
private def throwNotConcrete (e : Expr) : MetaM α := do
  throwError "#tree_scope: `{← ppOneLine e}` does not reduce to a constructor \
      application — TreeScope can only reflect concrete inductive values"

/-- The reflection-relevant shape of one value (after `whnf`). -/
private inductive NodeShape where
  /-- The whole value folds into a single literal-like label. -/
  | folded (label : String)
  /-- A constructor application: the assembled node label (constructor short
  name, folded literal fields, the `_` placeholder rule) and the child field
  expressions in order. -/
  | ctor (label : String) (children : Array Expr)
  /-- Not a constructor application (not concrete). -/
  | stuck

/-- `whnf` a value and classify it for reflection: a folded literal, a
constructor application (label assembled, children collected in field order —
see the module docstring for the exact rules), or stuck. -/
private def classifyNode (e : Expr) : MetaM NodeShape := do
  let ew ← whnf e
  if let some lab ← foldLit? ew then
    return .folded lab
  let fn := ew.getAppFn
  let .const c _ := fn | return .stuck
  let some (.ctorInfo ci) := (← getEnv).find? c | return .stuck
  let args := ew.getAppArgs
  unless args.size == ci.numParams + ci.numFields do return .stuck
  -- Explicitness of each constructor argument, from the constructor's type.
  let explicitFlags ← forallTelescopeReducing ci.type fun xs _ =>
    xs.mapM fun x => do return (← x.fvarId!.getDecl).binderInfo.isExplicit
  -- Classify the explicit fields in order: `.inl` folds, `.inr` is a child.
  let mut parts : Array (Sum String Expr) := #[]
  for i in [ci.numParams : args.size] do
    let arg := args[i]!
    unless explicitFlags[i]?.getD true do continue
    let argTy ← whnf (← inferType arg)
    if ← isProp argTy then continue
    let argW ← whnf arg
    if let some lab ← foldLit? argW then
      parts := parts.push (.inl lab)
    else if ← isInductiveApp argTy then
      parts := parts.push (.inr arg)
    else
      parts := parts.push (.inl s!"⟨{← ppOneLine arg}⟩")
  -- Assemble label and children (see the module docstring for the `_` rule).
  let short := match c with | .str _ s => s | _ => c.toString
  let lits := parts.filterMap fun | .inl s => some s | _ => none
  let children := parts.filterMap fun | .inr t => some t | _ => none
  let misordered := Id.run do
    let mut seenChild := false
    for p in parts do
      match p with
      | .inr _ => seenChild := true
      | .inl _ => if seenChild then return true
    return false
  let label :=
    if lits.isEmpty then short
    else if misordered then
      short ++ parts.foldl (fun acc p =>
        acc ++ " " ++ (match p with | .inl s => s | .inr _ => "_")) ""
    else
      short ++ lits.foldl (fun acc s => acc ++ " " ++ s) ""
  return .ctor label children

/-- Walk the single-child spine from `e` for up to `fuel` steps, counting the
levels (including `e`'s own).  Returns the count and whether the walk reached
the end of that path (the count is then the exact remaining depth *along this
path* — the whole tree may still be deeper through siblings, so callers only
ever report a lower bound). -/
private def probeSpine (e : Expr) (fuel : Nat) : MetaM (Nat × Bool) := do
  let mut cur := e
  let mut cnt := 0
  for _ in [0:fuel] do
    match ← classifyNode cur with
    | .folded _ => return (cnt + 1, true)
    | .stuck => return (cnt + 1, true)
    | .ctor _ children =>
      cnt := cnt + 1
      if children.isEmpty then return (cnt, true)
      else if children.size == 1 then cur := children[0]!
      else return (cnt, false)
  return (cnt, false)

/-- Reflect the (concrete) value `e` at nesting level `depth`, counting emitted
nodes in the state.  See the module docstring for the exact shape produced. -/
private partial def reflectCore (e : Expr) (depth : Nat) :
    StateRefT Nat MetaM TreeView := do
  if (← get) ≥ maxNodes then throwError nodeCapError
  set ((← get) + 1)
  if depth ≥ maxDepth then
    let (extra, _) ← probeSpine e probeFuel
    throwError depthCapReflectError (depth + extra)
  match ← classifyNode e with
  | .folded lab => return .leaf lab
  | .stuck => throwNotConcrete e
  | .ctor label children =>
    return .make label (← children.mapM (reflectCore · (depth + 1)))

/-- When the top-level value is a *pure single-child constructor spine* deeper
than `maxDepth` (a `List`/`Array`-like cons chain, nested `Option`s, …),
render it as a compact depth-2 sequence instead of refusing: a synthetic
`chain` root (sublabel `n=len`) with one leaf child per spine node, each
carrying the label the node would have had in the spine rendering.  Returns
`none` for everything else — values that fit within the depth cap keep their
ordinary rendering, and chains that branch, get stuck, or run past `probeFuel`
fall through to `reflectCore` (which reports a measured error).  A chain whose
compact form still exceeds `maxNodes` is refused with the exact count. -/
def compactChain? (e : Expr) : MetaM (Option TreeView) := do
  let mut labels : Array String := #[]
  let mut cur := e
  for _ in [0:probeFuel] do
    match ← classifyNode cur with
    | .stuck => return none
    | .folded lab =>
      labels := labels.push lab
      return (← mkCompact labels)
    | .ctor label children =>
      labels := labels.push label
      if children.isEmpty then
        return (← mkCompact labels)
      else if children.size == 1 then
        cur := children[0]!
      else
        return none
  return none
where
  /-- The compact view of a completed spine — `none` when it fits the depth
  cap (so the ordinary rendering applies), the honest exact node-cap error
  when even the compact form is too large. -/
  mkCompact (labels : Array String) : MetaM (Option TreeView) := do
    if labels.size ≤ maxDepth then return none
    if labels.size + 1 > maxNodes then throwError nodeCapExactError (labels.size + 1)
    return some <| .mk "chain" (some s!"n={labels.size}") #[] .neutral false
      (labels.map .leaf)

/-- Reflect a fully elaborated, concrete value into its constructor tree
(the stage-1 `value → TreeView` step of the `#tree_scope` pipeline; stage 2
tries the semantic typeclass first and falls back to this).  Over-deep pure
chains are compacted (`compactChain?`) instead of refused. -/
def reflectValue (e : Expr) : MetaM TreeView := do
  if let some tv ← compactChain? e then return tv
  (reflectCore e 0).run' 0

end TreeScope
