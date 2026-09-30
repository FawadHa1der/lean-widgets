import Lean
import ExprXRay.Types
import ExprXRay.Analyze

/-! # Expr X-Ray: the structural diff engine

Diffs two `Expr`s by descending simultaneously (after `instantiateMVars`,
alpha-aware under binders via shared fresh fvars; descent bounded by a
depth limit mirroring the analyzer's). Each mismatch is classified,
annotated with a *definitional-equality status* (are the two differing
subterms defeq at reducible transparency, at default transparency, not
at all — or undeterminable because they contain metavariables?).
Ancestor-level entries subsumed by a deeper entry on the same spine are
pruned, so one changed leaf yields one difference site, not one entry
per enclosing level. The remaining mismatches are ranked: everything
**not** certified definitionally equal (including failed and
undetermined checks) before everything defeq — a harmless syntactic
difference must never outrank the mismatch that actually blocks `rw` or
`exact` — and within each group instance-argument mismatches first, then
universe mismatches, then implicit-argument mismatches, then the rest.

The defeq check runs in the local context of the mismatch site and is
wrapped in `withoutModifyingState` + `withNewMCtxDepth`, so metavariable
assignments made by `Meta.isDefEq` can never escape into the caller's
state (diffing is pure: running it twice yields identical results).
Sides containing unassigned metavariables are never sent to `isDefEq`
at all: under `withNewMCtxDepth` they would come back "not defeq" even
when trivially unifiable, so they get the honest `undetermined` status
instead of a false blocking verdict.

The motivating use case: `rw` fails with "motive is not type correct"
because the two sides of an equation carry *different `Decidable`
instances*, invisible in default pretty-printing. `diffExprs` surfaces
exactly that as the top-ranked mismatch — and tells you whether the two
instances are at least definitionally equal.

`mdata` wrappers are stripped transparently before comparing, so diff
paths never contain steps for `mdata` nodes (see `XNode.get?` vs
`markMismatches` in `ExprXRay.Render` for how paths are mapped back
onto analysis trees, which do contain `mdata` nodes). -/

namespace ExprXRay

open Lean Meta

/-- Definitional-equality status of the two differing subterms at one
mismatch site. -/
inductive DefeqStatus where
  /-- Definitionally equal at *reducible* transparency (only `@[reducible]`
  definitions unfolded): an essentially cosmetic difference. -/
  | defeqReducible
  /-- Definitionally equal at *default* transparency only (requires
  unfolding non-reducible definitions). -/
  | defeqDefault
  /-- Not definitionally equal: this difference blocks defeq-transparent
  tactics (`exact`, `rfl`) as well as syntactic ones (`rw`). -/
  | notDefeq
  /-- The defeq check itself threw an exception (e.g. ill-scoped
  subterms); ranked together with `notDefeq` since nothing is certified. -/
  | checkFailed
  /-- At least one side contains unassigned (expression or universe)
  metavariables: `Meta.isDefEq` could only answer by assigning them, and
  the diff never assigns metavariables, so no verdict is certified either
  way. Ranked together with `notDefeq`/`checkFailed` since nothing is
  certified — but the wording never claims the difference blocks `rw`. -/
  | undetermined
  deriving Repr, BEq, Inhabited, DecidableEq

/-- `true` for the statuses that certify definitional equality. -/
def DefeqStatus.isDefeq : DefeqStatus → Bool
  | .defeqReducible | .defeqDefault => true
  | .notDefeq | .checkFailed | .undetermined => false

/-- Annotation suffix appended to mismatch descriptions. -/
def DefeqStatus.suffix : DefeqStatus → String
  | .defeqReducible => " (defeq at reducible transparency — syntactic only)"
  | .defeqDefault   => " (defeq at default transparency — syntactic only)"
  | .notDefeq       => " (NOT defeq — this blocks rw)"
  | .checkFailed    => " (defeq check failed)"
  | .undetermined   => " (defeq undetermined — contains metavariables)"

/-- Compact badge of a `DefeqStatus`, used by the renderer:
`≢` not defeq, `≈ʳ`/`≈ᵈ` defeq at reducible/default transparency,
`≟` check failed, `≟ₘ` undetermined (contains metavariables). -/
def DefeqStatus.badge : DefeqStatus → String
  | .defeqReducible => "≈ʳ"
  | .defeqDefault   => "≈ᵈ"
  | .notDefeq       => "≢"
  | .checkFailed    => "≟"
  | .undetermined   => "≟ₘ"

/-- Determine the `DefeqStatus` of `a` vs `b` in the current local
context: try `Meta.isDefEq` at reducible transparency, then at default
transparency. Each attempt is wrapped in `withoutModifyingState` (plus
`withNewMCtxDepth`), so metavariable assignments made during unification
never leak; exceptions collapse to `checkFailed`.

Sides containing unassigned metavariables short-circuit to
`undetermined` *without* consulting `isDefEq`: under `withNewMCtxDepth`
pre-existing metavariables are unassignable, so `isDefEq` would answer
`false` even for trivially unifiable sides (e.g. two fresh mvars of the
same type) and the mismatch would be misreported as *blocking* — see the
pinned `#xray_diff id, id` regression test. -/
def checkDefeq (a b : Expr) : MetaM DefeqStatus := do
  if a.hasMVar || b.hasMVar then
    return .undetermined
  match ← attempt (withReducible (isDefEq a b)) with
  | some true  => return .defeqReducible
  | none       => return .checkFailed
  | some false =>
    match ← attempt (isDefEq a b) with
    | some true  => return .defeqDefault
    | some false => return .notDefeq
    | none       => return .checkFailed
where
  /-- Run one leak-proof defeq attempt; `none` when it threw.
  `tryCatchRuntimeEx` (not plain `try/catch`) is required: on deep
  expressions `isDefEq` fails with a *runtime* exception (`maxRecDepth`
  / heartbeats), which ordinary `catch` in `MetaM` deliberately
  rethrows — the diff must degrade to `checkFailed`, not error out. -/
  attempt (check : MetaM Bool) : MetaM (Option Bool) :=
    tryCatchRuntimeEx
      (withoutModifyingState <| withNewMCtxDepth <| some <$> check)
      (fun _ => return none)

/-- Classification of a single mismatch site found by the diff engine. -/
inductive MismatchKind where
  /-- Two different constants at the same position. -/
  | differentConst
  /-- Same constant (or `Sort`) but different universe levels. -/
  | differentUniverse
  /-- An instance-implicit argument differs. -/
  | instanceArgMismatch
  /-- An implicit (or strict-implicit) argument differs. -/
  | implicitArgMismatch
  /-- An explicit argument differs. -/
  | explicitArgMismatch
  /-- Binder annotation or binder domain differs. -/
  | binderMismatch
  /-- Any other structural difference (different node kinds, different
  literals, different application shapes, ...). -/
  | structural
  deriving Repr, BEq, Inhabited, DecidableEq

/-- Rank used to order mismatches: instance arguments first (they are the
usual invisible culprit), then universes, then implicits, then the rest. -/
def MismatchKind.rank : MismatchKind → Nat
  | .instanceArgMismatch => 0
  | .differentUniverse   => 1
  | .implicitArgMismatch => 2
  | .differentConst      => 3
  | .explicitArgMismatch => 4
  | .binderMismatch      => 5
  | .structural          => 6

/-- Human-readable label of a `MismatchKind`. -/
def MismatchKind.label : MismatchKind → String
  | .differentConst      => "different constant"
  | .differentUniverse   => "different universe levels"
  | .instanceArgMismatch => "instance argument mismatch"
  | .implicitArgMismatch => "implicit argument mismatch"
  | .explicitArgMismatch => "explicit argument mismatch"
  | .binderMismatch      => "binder mismatch"
  | .structural          => "structural difference"

/-- One mismatch found between two expressions. -/
structure Mismatch where
  /-- Classification of the mismatch. -/
  kind : MismatchKind
  /-- Path of child indices from the root, in `XNode` child numbering
  (for applications: 0 is the head, argument *i* (1-based) is child *i*).
  `mdata` wrappers contribute no path step. -/
  path : List Nat
  /-- Short pretty string of the left-hand subterm at the mismatch site. -/
  lhs : String
  /-- Short pretty string of the right-hand subterm at the mismatch site. -/
  rhs : String
  /-- Human description of the site, e.g. `"instance argument #3 of ite"`. -/
  site : String := ""
  /-- Definitional-equality status of the two differing subterms,
  determined by `checkDefeq` in the local context of the site. -/
  defeq : DefeqStatus := .notDefeq
  deriving Repr, BEq, Inhabited

/-- One-line human summary of a mismatch (including its defeq
annotation), e.g.
`"instance argument #3 of ite differs: instDecidableEqNat 2 2 vs Classical.propDecidable (2 = 2) (NOT defeq — this blocks rw)"`. -/
def Mismatch.describe (m : Mismatch) : String :=
  let verb := if m.site.startsWith "universe levels" then "differ" else "differs"
  let site := if m.site.isEmpty then m.kind.label else s!"{m.site} {verb}"
  s!"{site}: {m.lhs} vs {m.rhs}{m.defeq.suffix}"

/-- Stable rank-sort of mismatches. Primary key: definitional equality —
every mismatch that is *not* defeq (or whose check failed) before every
defeq one, since only non-defeq differences can block defeq-transparent
tactics. Secondary key: `MismatchKind.rank` (instance arguments first,
then universes, then implicits, ...). Discovery order is preserved
within each (defeq, rank) group. -/
def rankMismatches (ms : Array Mismatch) : Array Mismatch :=
  byKind (ms.filter (!·.defeq.isDefeq)) ++ byKind (ms.filter (·.defeq.isDefeq))
where
  /-- Stable sort of one defeq group by `MismatchKind.rank`. -/
  byKind (ms : Array Mismatch) : Array Mismatch := Id.run do
    let mut out := #[]
    for r in List.range 7 do
      out := out ++ ms.filter (·.kind.rank == r)
    return out

/-- Is `p` a strict prefix of `q`? -/
def isStrictPrefixOf (p q : List Nat) : Bool :=
  p.length < q.length && p.isPrefixOf q

/-- Drop every mismatch whose path is a *strict* prefix of another
mismatch's path: when the diff walk manages to localize a difference
deeper, the ancestor-level entries recorded on the way down describe the
*same* difference site and are redundant (a single changed leaf nested
`N` levels deep would otherwise produce one entry per enclosing spine
level, all with near-identical truncated strings). Entries at the *same*
path (the arg-level classification plus its leaf-level `structural`
refinement) are all kept. -/
def pruneAncestors (ms : Array Mismatch) : Array Mismatch :=
  ms.filter fun m => !ms.any fun m' => isStrictPrefixOf m.path m'.path

/-- `true` when `ms` is nonempty and every mismatch is definitionally
equal — i.e. the two expressions differ only syntactically. -/
def allDefeq (ms : Array Mismatch) : Bool :=
  !ms.isEmpty && ms.all (·.defeq.isDefeq)

/-- Pinned headline used when every recorded mismatch is definitionally
equal. -/
def allDefeqSummary (n : Nat) : String :=
  let noun := if n == 1 then "mismatch" else "mismatches"
  s!"{n} {noun}, all definitionally equal — the discrepancy is syntactic only (defeq-transparent tactics like exact will succeed; syntactic tactics like rw may still fail)"

/-- Name of an application head for use in mismatch site descriptions. -/
private def headDescr : Expr → String
  | .const n _ => toString n
  | .fvar .. => "a local hypothesis"
  | .mvar .. => "a metavariable"
  | _ => "the application head"

/-- Alpha-aware equality used by the diff engine: ignores binder names and
`mdata` wrappers, but — unlike `Expr.eqv` — distinguishes binder
annotations (implicit vs explicit vs instance) so that `binderMismatch`
can be detected.

Recursion is fuel-bounded so that (interpreted) comparison of extremely
deep expressions cannot blow the stack: when `fuel` runs out — only
possible for a difference nested deeper than `fuel` levels, since the
`Expr.equal` fast path resolves equal subtrees without Lean-level
recursion — the comparison falls back to `Expr.eqv` (C++-implemented
alpha equivalence). The fallback ignores binder *annotations*, so an
annotation-only difference nested deeper than `fuel` levels may be
missed; the diff depth limit (see `diffExprs`) is far smaller than the
default fuel, so this cannot change any reported mismatch. -/
def exprMatches (a b : Expr) (fuel : Nat := 256) : Bool :=
  let a := a.consumeMData
  let b := b.consumeMData
  if a.equal b then true
  else match fuel with
  | 0 => a.eqv b
  | fuel + 1 =>
    match a, b with
    | .app f x, .app g y => exprMatches f g fuel && exprMatches x y fuel
    | .lam _ t u bi, .lam _ s v bi' =>
      bi == bi' && exprMatches t s fuel && exprMatches u v fuel
    | .forallE _ t u bi, .forallE _ s v bi' =>
      bi == bi' && exprMatches t s fuel && exprMatches u v fuel
    | .letE _ t v u _, .letE _ t' v' u' _ =>
      exprMatches t t' fuel && exprMatches v v' fuel && exprMatches u u' fuel
    | .proj s i e, .proj s' i' e' => s == s' && i == i' && exprMatches e e' fuel
    | .const n us, .const m vs => n == m && us == vs
    | .sort u, .sort v => u == v
    | .fvar i, .fvar j => i == j
    | .mvar i, .mvar j => i == j
    | .bvar i, .bvar j => i == j
    | .lit l, .lit l' => l == l'
    | _, _ => false

/-- Core diff walk. Both sides have mvars instantiated by `diffExprs`;
`mdata` is stripped at every step. Paths use `XNode` child numbering.
Every recorded mismatch carries the `checkDefeq` status of the two
differing subterms, determined in the local context of the site.

Descent is bounded by `maxDepth` (mirroring the analyzer's
`XRayConfig.maxDepth` guard): once the path is that long, a single
`structural` mismatch with site `"subterm at the diff depth limit"` and
status `checkFailed` is recorded instead of recursing, so diffing
arbitrarily deep expressions can never hit the interpreter's
uncatchable recursion limit. -/
private partial def diffCore (maxDepth : Nat) (a b : Expr) (path : Array Nat) :
    MetaM (Array Mismatch) := do
  let a := a.consumeMData
  let b := b.consumeMData
  if exprMatches a b then
    return #[]
  if path.size ≥ maxDepth then
    let (l, r) ← ppShortPair a b
    return #[{ kind := .structural, path := path.toList,
               lhs := l, rhs := r,
               site := "subterm at the diff depth limit",
               defeq := .checkFailed }]
  match a, b with
  | .const n us, .const m vs =>
    if n ≠ m then
      return #[{ kind := .differentConst, path := path.toList,
                 lhs := toString n, rhs := toString m,
                 defeq := ← checkDefeq a b }]
    else
      return #[{ kind := .differentUniverse, path := path.toList,
                 lhs := toString us, rhs := toString vs,
                 site := s!"universe levels of {n}",
                 defeq := ← checkDefeq a b }]
  | .sort u, .sort v =>
    return #[{ kind := .differentUniverse, path := path.toList,
               lhs := toString u, rhs := toString v,
               site := "sort level",
               defeq := ← checkDefeq a b }]
  | .lam n t body bi, .lam n' t' body' bi' =>
    diffBinder a b n t body bi n' t' body' bi'
  | .forallE n t body bi, .forallE n' t' body' bi' =>
    diffBinder a b n t body bi n' t' body' bi'
  | .letE n t v body _, .letE _ t' v' body' _ => do
    let mut out := #[]
    unless exprMatches t t' do
      out := out ++ (← diffCore maxDepth t t' (path.push 0))
    unless exprMatches v v' do
      out := out ++ (← diffCore maxDepth v v' (path.push 1))
    unless exprMatches body body' do
      out := out ++ (← withLetDecl n t v fun x =>
        diffCore maxDepth (body.instantiate1 x) (body'.instantiate1 x) (path.push 2))
    return out
  | .proj s i e, .proj s' i' e' =>
    if s == s' && i == i' then
      diffCore maxDepth e e' (path.push 0)
    else
      let (l, r) ← ppShortPair a b
      return #[{ kind := .structural, path := path.toList,
                 lhs := l, rhs := r,
                 site := "structure projection",
                 defeq := ← checkDefeq a b }]
  | _, _ =>
    if a.isApp && b.isApp then
      diffApp a b
    else
      let (l, r) ← ppShortPair a b
      return #[{ kind := .structural, path := path.toList,
                 lhs := l, rhs := r,
                 defeq := ← checkDefeq a b }]
where
  /-- Diff two binders of the same flavor (`lam`/`lam` or `forall`/`forall`):
  compare binder annotations, descend into domains (child 0) and, sharing a
  single fresh fvar for alpha-awareness, into bodies (child 1).
  `whole`/`whole'` are the two binder expressions themselves, used for the
  defeq check of an annotation mismatch. -/
  diffBinder (whole whole' : Expr) (n : Name) (t body : Expr) (bi : BinderInfo)
      (n' : Name) (t' body' : Expr) (bi' : BinderInfo) : MetaM (Array Mismatch) := do
    let mut out := #[]
    let nn := n.eraseMacroScopes
    let nn' := n'.eraseMacroScopes
    if bi != bi' then
      out := out.push { kind := .binderMismatch, path := path.toList,
                        lhs := s!"binder ({nn} : ...) [{repr bi}]",
                        rhs := s!"binder ({nn'} : ...) [{repr bi'}]",
                        site := s!"binder annotation of {nn}",
                        defeq := ← checkDefeq whole whole' }
    unless exprMatches t t' do
      let (l, r) ← ppShortPair t t'
      out := out.push { kind := .binderMismatch, path := (path.push 0).toList,
                        lhs := l, rhs := r,
                        site := s!"binder type of {nn}",
                        defeq := ← checkDefeq t t' }
      out := out ++ (← diffCore maxDepth t t' (path.push 0))
    unless exprMatches body body' do
      out := out ++ (← withLocalDecl n bi t fun x =>
        diffCore maxDepth (body.instantiate1 x) (body'.instantiate1 x) (path.push 1))
    return out
  /-- Diff two applications. When heads agree and arities match, each
  differing argument is classified by its `BinderRole` (via `getFunInfo` of
  the head). Instance arguments are reported whole; other arguments are
  additionally descended into so deeper (higher-ranked) mismatches are
  also collected.

  Explicit-argument sites are phrased with the *explicit-only* ordinal
  (`"explicit argument #2 of HAdd.hAdd"` for the second visible operand
  of `+`) — the number a user can map onto what they wrote — while
  instance/implicit sites keep the absolute spine position (the index
  one would use in an `@`-application). Mismatch *paths* always use the
  absolute position. -/
  diffApp (a b : Expr) : MetaM (Array Mismatch) := do
    let fa := a.getAppFn.consumeMData
    let as := a.getAppArgs
    let fb := b.getAppFn.consumeMData
    let bs := b.getAppArgs
    if as.size == bs.size then
      -- Heads compatible: identical, or same constant with different levels.
      let sameConstName := match fa, fb with
        | .const n _, .const m _ => n == m
        | _, _ => false
      if exprMatches fa fb || sameConstName then
        let mut out := #[]
        unless exprMatches fa fb do
          out := out ++ (← diffCore maxDepth fa fb (path.push 0))
        let roles ← argRoles fa as.size
        let head := headDescr fa
        let mut explicitIdx := 0
        for i in [0:as.size] do
          let ai := as[i]!
          let bi := bs[i]!
          let role := roles[i]?.getD .explicit
          if role == .explicit || role == .none then
            explicitIdx := explicitIdx + 1
          unless exprMatches ai bi do
            let p := path.push (i + 1)
            let (l, r) ← ppShortPair ai bi
            match role with
            | .instImplicit =>
              out := out.push { kind := .instanceArgMismatch, path := p.toList,
                                lhs := l, rhs := r,
                                site := s!"instance argument #{i + 1} of {head}",
                                defeq := ← checkDefeq ai bi }
            | .implicit | .strictImplicit =>
              out := out.push { kind := .implicitArgMismatch, path := p.toList,
                                lhs := l, rhs := r,
                                site := s!"implicit argument #{i + 1} of {head}",
                                defeq := ← checkDefeq ai bi }
              out := out ++ (← diffCore maxDepth ai bi p)
            | _ =>
              out := out.push { kind := .explicitArgMismatch, path := p.toList,
                                lhs := l, rhs := r,
                                site := s!"explicit argument #{explicitIdx} of {head}",
                                defeq := ← checkDefeq ai bi }
              out := out ++ (← diffCore maxDepth ai bi p)
        return out
      else
        -- Same arity but incompatible heads: classify the head mismatch.
        diffCore maxDepth fa fb (path.push 0)
    else
      let (l, r) ← ppShortPair a b
      return #[{ kind := .structural, path := path.toList,
                 lhs := l, rhs := r,
                 site := "application shape",
                 defeq := ← checkDefeq a b }]

/-- Diff two expressions: instantiate mvars, walk both structures
simultaneously (descent bounded by `maxDepth`; beyond it a single
`structural` mismatch with site `"subterm at the diff depth limit"` is
recorded), collect every mismatch (each annotated with its
`DefeqStatus`), prune ancestor-level entries subsumed by deeper ones
(`pruneAncestors`), and return the rest ranked: non-defeq mismatches
first, and within each defeq group instance arguments first, then
universes, then implicits, then the rest. -/
def diffExprs (a b : Expr) (maxDepth : Nat := 128) : MetaM (Array Mismatch) := do
  let ms ← diffCore maxDepth (← instantiateMVars a) (← instantiateMVars b) #[]
  return rankMismatches (pruneAncestors ms)

/-- One-line headline: the pinned all-defeq summary when every mismatch
is definitionally equal, otherwise the top-ranked mismatch's
description (with its defeq annotation). `none` when there are no
mismatches. -/
def diffSummary (ms : Array Mismatch) : Option String :=
  if allDefeq ms then some (allDefeqSummary ms.size)
  else ms[0]?.map (·.describe)

end ExprXRay
