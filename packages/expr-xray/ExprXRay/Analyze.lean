import Lean
import ExprXRay.Types

/-! # Expr X-Ray: the analyzer

Converts a `Lean.Expr` into an `XNode` tree in `MetaM`. Per node we record
the syntactic kind, a truncated pretty string, the (guarded) inferred type,
the binder role of application arguments (classified via `Meta.getFunInfo`),
universe levels of constants/sorts, coercion heads and `mdata` markers.
Construction is depth-limited with an `elided` flag on cut branches.
-/

namespace ExprXRay

open Lean Meta

/-- Coercion heads that may not be registered in the `coeExt` environment
extension but should still be flagged as coercions. -/
def knownCoeHeads : List Name :=
  [``Nat.cast, ``Int.cast, ``NatCast.natCast, ``IntCast.intCast,
   ``Coe.coe, ``CoeTC.coe, ``CoeT.coe, ``CoeHTCT.coe, ``CoeHTC.coe,
   ``CoeHead.coe, ``CoeTail.coe, ``CoeSort.coe, ``CoeFun.coe,
   ``Int.ofNat]

/-- `true` if `n` names a coercion function: either registered via `@[coe]`
(query through `Meta.getCoeFnInfo?`) or a member of `knownCoeHeads`. -/
def isCoeName (n : Name) : CoreM Bool := do
  if (← getCoeFnInfo? n).isSome then
    return true
  return knownCoeHeads.contains n

/-- `true` if the head of `e` (after peeling applications) is a coercion
function in the sense of `isCoeName`. -/
def isCoeHead (e : Expr) : CoreM Bool :=
  match e.getAppFn with
  | .const n _ => isCoeName n
  | _ => return false

/-- Collapse the delaborator's own in-band failure text (emitted e.g. on
`maxRecDepth` for very deep terms: `"failed to pretty print expression
(use 'set_option pp.rawOnError true' for raw representation)"`) to the
compact `"⟨pp failed⟩"` marker used everywhere else. -/
def collapsePPFailure (s : String) : String :=
  if s.startsWith "failed to pretty print expression" then "⟨pp failed⟩" else s

/-- Pretty-print `e` to a single-line string of at most `limit` characters.
Never fails: pretty-printer errors — including *runtime* exceptions
(`maxRecDepth`/heartbeats on very deep terms), which a plain `try/catch`
in `MetaM` would rethrow — collapse to `"⟨pp failed⟩"`. -/
def ppShort (e : Expr) (limit : Nat := 60) : MetaM String :=
  tryCatchRuntimeEx
    (do return truncatePP (collapsePPFailure ((← Meta.ppExpr e).pretty (width := 1000000))) limit)
    (fun _ => return "⟨pp failed⟩")

/-- Pretty-print the two sides of a mismatch, truncating with
`truncatePPPair`: when the left-anchored truncations of the two sides
would be identical (a long shared prefix), the shown window is anchored
at the first differing character instead, so the pair always exhibits a
visible difference. Pretty-printer failures collapse to `"⟨pp failed⟩"`
per side. -/
def ppShortPair (a b : Expr) (limit : Nat := 60) : MetaM (String × String) := do
  let ppFull (e : Expr) : MetaM String :=
    tryCatchRuntimeEx
      (do return collapsePPFailure ((← Meta.ppExpr e).pretty (width := 1000000)))
      (fun _ => return "⟨pp failed⟩")
  return truncatePPPair (← ppFull a) (← ppFull b) limit

/-- Infer and pretty-print the type of `e`; `none` if `inferType` (or the
pretty-printer) fails, so analysis never aborts on ill-typed subterms. -/
def ppTypeShort? (e : Expr) (limit : Nat := 60) : MetaM (Option String) := do
  try
    let ty ← instantiateMVars (← inferType e)
    let fmt ← Meta.ppExpr ty
    return some (truncatePP (fmt.pretty (width := 1000000)) limit)
  catch _ =>
    return none

/-- Classify the roles of the first `nargs` arguments of `fn` using
`Meta.getFunInfoNArgs`. Missing information defaults to `.explicit`. -/
def argRoles (fn : Expr) (nargs : Nat) : MetaM (Array BinderRole) := do
  try
    let info ← getFunInfoNArgs fn nargs
    let known := info.paramInfo.map (roleOfBinderInfo ·.binderInfo)
    let pad := (List.replicate (nargs - known.size) BinderRole.explicit).toArray
    return known ++ pad
  catch _ =>
    return (List.replicate nargs BinderRole.explicit).toArray

/-- Convert `e` (with metavariables instantiated) into an `XNode` tree.

* Application children are ordered head-function first, then arguments in
  spine order; each argument carries its `BinderRole`.
* Binder bodies are analyzed under a fresh local fvar, so pretty strings
  show the user-facing binder names.
* Branches deeper than `cfg.maxDepth` are cut and flagged `elided`. -/
partial def analyzeExpr (e : Expr) (cfg : XRayConfig := {}) : MetaM XNode := do
  go (← instantiateMVars e) 0 .none
where
  /-- Analyze `e` at `depth` playing `role` for its parent. -/
  go (e : Expr) (depth : Nat) (role : BinderRole) : MetaM XNode := do
    let pp ← ppShort e cfg.ppMaxLength
    let type? ← ppTypeShort? e cfg.ppMaxLength
    let cut := depth ≥ cfg.maxDepth
    match e with
    | .const n us =>
      return { kind := .const, pp, type?, role,
               levels := us.map (toString ·), isCoe := ← isCoeName n }
    | .app .. =>
      let fn := e.getAppFn
      let args := e.getAppArgs
      let isCoe ← isCoeHead e
      if cut then
        return { kind := .app, pp, type?, role, isCoe, elided := true }
      let roles ← argRoles fn args.size
      let fnNode ← go fn (depth + 1) .none
      let argNodes ← args.mapIdxM fun i a => go a (depth + 1) (roles[i]?.getD .explicit)
      return { kind := .app, pp, type?, role, isCoe, children := #[fnNode] ++ argNodes }
    | .lam n t b bi =>
      if cut then
        return { kind := .lam, pp, type?, role, elided := true }
      let tNode ← go t (depth + 1) .none
      let bNode ← withLocalDecl n.eraseMacroScopes bi t fun x => go (b.instantiate1 x) (depth + 1) .none
      return { kind := .lam, pp, type?, role, children := #[tNode, bNode] }
    | .forallE n t b bi =>
      if cut then
        return { kind := .forallE, pp, type?, role, elided := true }
      let tNode ← go t (depth + 1) .none
      let bNode ← withLocalDecl n.eraseMacroScopes bi t fun x => go (b.instantiate1 x) (depth + 1) .none
      return { kind := .forallE, pp, type?, role, children := #[tNode, bNode] }
    | .letE n t v b _ =>
      if cut then
        return { kind := .letE, pp, type?, role, elided := true }
      let tNode ← go t (depth + 1) .none
      let vNode ← go v (depth + 1) .none
      let bNode ← withLetDecl n.eraseMacroScopes t v fun x => go (b.instantiate1 x) (depth + 1) .none
      return { kind := .letE, pp, type?, role, children := #[tNode, vNode, bNode] }
    | .mdata _ inner =>
      if cut then
        return { kind := .mdata, pp, type?, role, isMData := true, elided := true }
      let innerNode ← go inner (depth + 1) .none
      return { kind := .mdata, pp, type?, role, isMData := true, children := #[innerNode] }
    | .proj _ _ s =>
      if cut then
        return { kind := .proj, pp, type?, role, elided := true }
      let sNode ← go s (depth + 1) .none
      return { kind := .proj, pp, type?, role, children := #[sNode] }
    | .sort u =>
      return { kind := .sort, pp, type?, role, levels := [toString u] }
    | .fvar .. => return { kind := .fvar, pp, type?, role }
    | .mvar .. => return { kind := .mvar, pp, type?, role }
    | .lit ..  => return { kind := .lit, pp, type?, role }
    | .bvar .. => return { kind := .bvar, pp, type?, role }

/-- Pretty-print `e` with `pp.explicit := true` (and optionally
`pp.universes := true`) as a plain multi-line string. -/
def ppExplicitString (e : Expr) (universes : Bool := false) : MetaM String := do
  try
    withOptions (fun o =>
        (o.setBool `pp.explicit true).setBool `pp.universes universes) do
      return (← Meta.ppExpr e).pretty
  catch _ =>
    return "⟨pp failed⟩"

end ExprXRay
