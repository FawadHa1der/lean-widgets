import SimpLens.Trace

/-!
# SimpLens.Minimize — minimal `simp only [...]` generation

Turns the `UsedSimps` of a traced run into a syntactically valid
`simp only [...]` call. We deliberately **reuse core's own
`Lean.Elab.Tactic.mkSimpOnly`** (the machinery behind `simp?`), so the
suggestion is byte-for-byte what `simp?` would produce: global lemmas by
(unresolved) name, local hypotheses by user-facing name, builtin simprocs by
name, `.stx` arguments verbatim, and unrepresentable `.other` origins skipped.
-/

namespace SimpLens

open Lean Meta Simp Elab

/-- How an `Origin` can be represented in a `simp only [...]` argument list. -/
inductive OriginClass where
  /-- A global declaration that exists in the environment. -/
  | global (name : Name)
  /-- A builtin or registered simproc. -/
  | simproc (name : Name)
  /-- A local hypothesis, by user-facing name. -/
  | localHyp (userName : Name)
  /-- A term argument that was passed to the original call (`.stx` origin). -/
  | stxArg (ref : Syntax)
  /-- Not representable in `simp only [...]` (e.g. `.other` origins created by
  internal machinery, or fvars with inaccessible names). -/
  | unrepresentable (key : Name)
  deriving Inhabited

/-- Human-readable label for an `OriginClass`. -/
def OriginClass.label : OriginClass → String
  | .global n => s!"global lemma {n}"
  | .simproc n => s!"simproc {n}"
  | .localHyp n => s!"local hypothesis {n}"
  | .stxArg _ => "explicit simp argument"
  | .unrepresentable k => s!"unrepresentable ({k})"

/-- `true` if the class can appear in a generated `simp only [...]` call. -/
def OriginClass.representable : OriginClass → Bool
  | .unrepresentable _ => false
  | _ => true

/-- Classify an origin the same way `Lean.Elab.Tactic.mkSimpOnly` does when it
decides whether/how to include it in the generated call. Must be called with
the goal's local context in scope. -/
def classifyOrigin (o : Origin) : MetaM OriginClass := do
  match o with
  | .decl declName _ _ =>
    if (← Simp.isSimproc declName) || (← Simp.isBuiltinSimproc declName) then
      return .simproc declName
    else if (← getEnv).contains declName then
      return .global declName
    else
      return .unrepresentable declName
  | .fvar fvarId =>
    let lctx ← getLCtx
    if let some ldecl := lctx.find? fvarId then
      if !ldecl.userName.isInaccessibleUserName && !ldecl.userName.hasMacroScopes &&
          (lctx.findFromUserName? ldecl.userName).any (·.fvarId == ldecl.fvarId) then
        return .localHyp ldecl.userName
    return .unrepresentable fvarId.name
  | .stx _ ref => return .stxArg ref
  | .other name => return .unrepresentable name

/-- Names of the global lemmas/simprocs in a `UsedSimps`, in firing order
(useful for assertions and display). -/
def usedDeclNames (used : UsedSimps) : Array Name :=
  used.toArray.filterMap fun o => match o with
    | .decl n _ _ => some n
    | _ => none

/--
Generate the minimal `simp only [...]` syntax for a traced run.

`call` must be the syntax of a *core* `simp` invocation (kind
`Lean.Parser.Tactic.simp`); its argument list is replaced by the used lemmas
via core's `mkSimpOnly`. Must run in the goal's local context so local
hypotheses resolve to their user-facing names.
-/
def minimalSimpOnly (call : Syntax) (used : UsedSimps) : MetaM (TSyntax `tactic) := do
  return ⟨← Elab.Tactic.mkSimpOnly call.unsetTrailing used⟩

/-- Pretty-print a generated tactic call to a single-line string. -/
def ppTacticCall (stx : TSyntax `tactic) : MetaM String := do
  let fmt ← PrettyPrinter.ppCategory `tactic stx
  return fmt.pretty (width := 1000000)

/-- Convenience: the minimal `simp only [...]` call as a string, generated
from a bare `simp` invocation. -/
def minimalSimpOnlyString (used : UsedSimps) : MetaM String := do
  let call ← `(tactic| simp)
  ppTacticCall (← minimalSimpOnly call used)

end SimpLens
