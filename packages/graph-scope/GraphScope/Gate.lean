import GraphScope.Extract
import GraphScope.Insert
import Mathlib.Combinatorics.SimpleGraph.Connectivity.Finite
-- For the `hasse` / `pathGraph` instance names in `quantifyingDecidableConsts`
-- (already in the closure of `import GraphScope`, via `GraphScope.Demo`).
import Mathlib.Combinatorics.SimpleGraph.Hasse

/-! # GraphScope: the round-trip honesty gate

A click-to-insert link must never insert a misleading fact.  The vertex terms
in inserted texts are built from `Repr` labels, and a label that parses to a
*different* value than the drawn element would produce a compiling-but-wrong
example (e.g. two vertices sharing a label through a lossy `Repr`, or a label
that is not term syntax at all).  Therefore a link is attached **only when the
candidate label passes a verified round-trip at analysis time**:

1. parse the label as a term (`Parser.runParserCategory`);
2. elaborate it at the vertex type (errors → fail; leftover metavariables,
   e.g. `⟨0, _⟩` anonymous-constructor labels with proof holes → fail);
3. prove it *equal to the drawn element*: evaluate
   `elemMatchesIndex (parsed) i` — the type's own `DecidableEq` compared
   against position `i` of the same `Fintype` enumeration the extractor
   indexed the drawing by — through the same `evalExpr` bridge extraction
   uses.

Labels that fail the gate render as plain text with a muted note.

The connectivity link is decided by `connectivityCheck`: the walk-work
heartbeat estimate of `Insert.connectivityVerdict`, at the cost of one
adjacency decision *measured* on the graph's own instance ("The measured
adjacency cost" below), must stay within the budget, and the instance must
pass a second guard, `adjacencyCost` ("The adjacency-cost guard" below): the
estimate was calibrated only with instances that do not decide adjacency by
quantifying over a finite type, so such instances are refused.

`Mathlib.Combinatorics.SimpleGraph.Connectivity.Finite` is imported here (not
merely in the tests) so that every file using `#graph_scope` has the
`Decidable G.Connected` instance in scope — the inserted connectivity example
must compile *in the user's file*.
-/

namespace GraphScope

open Lean Meta Elab

/-- Does `v` sit at position `i` of the `Fintype` enumeration?  Decided by the
type's own `DecidableEq` against the exact enumeration (`enumVerts`) the
extractor indexed vertices by.  Unsafe for the same reason as `enumVerts`;
only ever run through `evalExpr (safety := .unsafe)`. -/
unsafe def elemMatchesIndex {V : Type u} [Fintype V] [DecidableEq V]
    (v : V) (i : Nat) : Bool :=
  match (enumVerts V)[i]? with
  | some w => decide (v = w)
  | none => false

/-- The round-trip honesty gate (see the module docstring): does `label` parse,
elaborate at `V` without leftover metavariables or `sorry`, and evaluate as
equal (by `V`'s own `DecidableEq`) to element `idx` of the `Fintype`
enumeration?  `finInst`/`deqInst` are the already-synthesized instances.
Interrupt and runtime exceptions propagate; every other failure means `false`
(the label renders as plain text, never as a link). -/
def labelRoundTrips (V finInst deqInst : Expr) (label : String) (idx : Nat) :
    TermElabM Bool := do
  match Parser.runParserCategory (← getEnv) `term label with
  | .error _ => return false
  | .ok stx =>
    try
      let ve ← Term.withoutErrToSorry do
        let ve ← Term.elabTerm stx (some V)
        Term.synthesizeSyntheticMVarsNoPostponing
        instantiateMVars ve
      if ve.hasExprMVar || ve.hasLevelMVar || ve.hasSorry then
        return false
      let e ← mkAppOptM ``elemMatchesIndex #[V, finInst, deqInst, ve, mkNatLit idx]
      unsafe evalExpr Bool (mkConst ``Bool) e (safety := .unsafe)
    catch ex =>
      if ex.isInterrupt || ex.isRuntime then
        throw ex
      return false

/-! ## The adjacency-cost guard

`Insert.connectivityVerdict` estimates the heartbeats of the walk
enumeration that Mathlib's `Decidable G.Connected` performs ("The
connectivity cost model" in `GraphScope/Insert.lean`) from the walk work and
the measured cost of one adjacency decision.  Its coefficients were
calibrated with adjacency instances whose single decision does not grow with
the vertex type: `decidable_of_iff` over a closed formula
(`GraphScope.Demo`), Mathlib's `⊥`/`⊤`/`cycleGraph`/`ᶜ` instances, `fromRel`
over closed relations (arithmetic, `List` literals, `Finset` `⊆`/`card`) and
`fromEdgeSet` over literals.

Mathlib v4.35.0 (mathlib4 #40728) added instances that decide adjacency by
*quantifying over the vertex type*: `Fintype.instDecidableRelCovByOfDecidableLT`
and `Fintype.instDecidableRelWCovByOfDecidableLE` decide `a ⋖ b` / `a ⩿ b` as
`a < b ∧ ∀ c, a < c → ¬c < b` (resp. `≤`) through
`Fintype.decidableForallFintype`, and `hasse α` (hence `pathGraph n`, absent
`GraphScope.Demo`'s instance) is decidable through them.  Every adjacency
decision of the walk enumeration then costs a pass over `V`; no such instance
was in the calibration sweep, so the estimate is not trusted for them.  (This
is not what made the audit's
`example : (hasse (Finset (Fin 4))).Connected := by decide` exhaust
`maxHeartbeats 200000`: `hasse (Finset (Fin 4))` is the 4-cube, whose walk
enumeration alone needs 328678 heartbeats with a cheap closed adjacency
(`Nat.xor` on `Fin 16`) — the v4.34 shape budget `diameter ≤ 4 && n ≤ 16`
was unsound for it with any instance, and the cost model refuses it for any
real adjacency cost.  The quantifying instance only makes it worse.)

So the connectivity link is offered only when the synthesized
`DecidableRel g.Adj` instance is in the calibrated class: `adjacencyCost`
searches the instance term and, transitively, the bodies of the definitions
it mentions for the constants in `quantifyingDecidableConsts`.  The search is
conservative: a hit, or a definitional closure larger than the search limit
(`adjCostSearchLimit`), withholds the link (a withheld link is merely a
missing suggestion; an offered one must compile).  Only definitions (`def`,
`instance`, `abbrev`) are unfolded; theorems, axioms and opaque constants are
not, since `decide` never evaluates a proof.  So a quantifier inside a proof
counts only where the proof term is inlined in a definition's value; tactic
proofs inside an instance body are abstracted into auxiliary theorems, which
the search does not unfold (sound: `decide` does not evaluate them either).
The closures are small (the suite's graphs reach 4–380 constants, well under
a millisecond).  Edge and degree links are not affected: they decide one
adjacency (resp. one row), and the test suite compiles every one offered for
`hasse (Fin 64)` and for `hasse (Finset (Fin 4))` with `Finset`-literal labels
(`GraphScopeTests/HasseLinkTests.lean`). -/

/-- Constants whose presence in (the definitional unfolding of) a
`DecidableRel g.Adj` instance means adjacency is decided by quantifying over a
finite type.  This is a deny-list of the library quantifier instances, not a
general cost analysis:

* Mathlib's `Fintype` quantifier instances — the route of every
  `Fintype`-generic decision procedure, Mathlib's `CovBy`/`WCovBy` included;
* core's bounded `Nat` quantifiers, which `∀ i : Fin n` / `∃ i : Fin n`
  (`Nat.decidableForallFin` / `Nat.decidableExistsFin`) reduce to;
* the concrete Mathlib v4.35.0 instances (`CovBy`, `WCovBy`, `hasse`,
  `pathGraph`), by name, so they are caught even where the search cannot see
  a definition's body.

A hand-written instance that iterates over the vertex type by other means
(its own recursion, a `List` of all vertices, …) is not detected; see the
README's limitations.  The double-backtick names are checked when this file
compiles, so a rename upstream breaks the build instead of silently disabling
the guard. -/
def quantifyingDecidableConsts : List Name :=
  [``Fintype.decidableForallFintype, ``Fintype.decidableExistsFintype,
   ``Nat.decidableForallFin, ``Nat.decidableExistsFin,
   ``Nat.decidableBallLT, ``Nat.decidableExistsLT, ``Nat.decidableExistsLT',
   ``Fintype.instDecidableRelCovByOfDecidableLT,
   ``Fintype.instDecidableRelWCovByOfDecidableLE,
   ``SimpleGraph.instDecidableRelAdjHasseOfFintypeOfDecidableLT,
   ``SimpleGraph.instDecidableRelFinAdjPathGraph]

/-- Upper bound on the number of constants `adjacencyCost` inspects; a larger
definitional closure counts as unvalidated. -/
def adjCostSearchLimit : Nat := 20000

/-- How a `DecidableRel g.Adj` instance relates to the cost model of
`Insert.connectivityVerdict` (see "The adjacency-cost guard"). -/
inductive AdjCost where
  /-- No constant of `quantifyingDecidableConsts` is reachable: the instance
  is in the class the connectivity cost model was calibrated for. -/
  | validated
  /-- Adjacency is decided by quantifying over a finite type; `c` is the
  nearest such constant found (breadth-first from the instance term). -/
  | quantifies (c : Name)
  /-- The definitional closure exceeded `adjCostSearchLimit` without a hit;
  treated like `quantifies` (conservative). -/
  | unknown
  deriving Repr, BEq, Inhabited

/-- May the connectivity link be offered under this verdict? Only for
`validated` instances. -/
def AdjCost.connectivityOk : AdjCost → Bool
  | .validated => true
  | _ => false

/-- Classify the (instantiated) adjacency instance `inst`: breadth-first
search over the constants of `inst` and, transitively, over the values of the
definitions (including instances) they name, for a constant of
`quantifyingDecidableConsts`.  A closure that grows past `limit` constants
before a hit is found yields `.unknown` (the default `limit` is
`adjCostSearchLimit`; tests pass a tiny one to reach that branch).
Deterministic: the same instance in the same environment always yields the
same verdict. -/
def adjacencyCost (inst : Expr) (limit : Nat := adjCostSearchLimit) : MetaM AdjCost := do
  let env ← getEnv
  let targets : NameSet := quantifyingDecidableConsts.foldl (·.insert ·) {}
  let mut seen : NameSet := {}
  let mut queue : Array Name := #[]
  for c in inst.getUsedConstants do
    unless seen.contains c do
      seen := seen.insert c
      queue := queue.push c
  let mut i := 0
  while i < queue.size do
    let c := queue[i]!
    i := i + 1
    if targets.contains c then
      return .quantifies c
    if queue.size > limit then
      return .unknown
    if let some (.defnInfo d) := env.find? c then
      for c' in d.value.getUsedConstants do
        unless seen.contains c' do
          seen := seen.insert c'
          queue := queue.push c'
  return .validated

/-- `adjacencyCost` of the graph's own `DecidableRel g.Adj` instance (the one
extraction and every inserted `by decide` use), or `none` when it cannot be
synthesized.  `limit` is passed to `adjacencyCost`. -/
def graphAdjacencyCost? (g : Expr) (limit : Nat := adjCostSearchLimit) :
    MetaM (Option AdjCost) := do
  let adjRel ← mkAppM ``SimpleGraph.Adj #[g]
  let some inst ← synthInstance? (← mkAppM ``DecidableRel #[adjRel]) | return none
  return some (← adjacencyCost (← instantiateMVars inst) limit)

/-! ## The measured adjacency cost

`Insert.connectivityVerdict` needs the cost of one adjacency decision of the
graph's own instance (see "The connectivity cost model" in
`GraphScope/Insert.lean`): it is the factor that separates the `Nat.xor`
spelling of the 3-cube (16091 heartbeats) from its `fromEdgeSet` literal
(61840).  It is measured with the reduction `decide` itself performs: `whnf`
at default transparency of `decide (∀ a b : V, ¬ (g.Adj a b ∧ False))`, whose
instance (`Fintype.decidableForallFintype` twice, then `instDecidableAnd`)
decides every adjacency exactly once and never reaches `False`.  The
measurement is capped at the largest per-decision cost the budget allows
(`Insert.maxAdjacencyCost?`), so it never costs more than the connectivity
example would be allowed to. -/

/-- `∀ a b : V, ¬ (g.Adj a b ∧ False)`: true, and deciding it decides every
adjacency of `g` once. -/
def adjacencyCostProp (g V : Expr) : MetaM Expr :=
  withLocalDeclD `a V fun a => withLocalDeclD `b V fun b => do
    let adj ← mkAppM ``SimpleGraph.Adj #[g, a, b]
    mkForallFVars #[a, b] (mkNot (mkAnd adj (mkConst ``False)))

/-- The cost of one adjacency decision of `g` (a graph on `n` vertices of
type `V`), in raw heartbeats (`IO.getNumHeartbeats` units), rounded up: the
heartbeats of `whnf` (default transparency, as `decide` runs it) of
`decide (adjacencyCostProp g V)` divided by its `n²` decisions.  `none` when
the `Decidable` instance cannot be synthesized, when the reduction does not
reach `true`, or when it needs more than `cap` per decision: the reduction is
cut off there (it runs under a local heartbeat limit of `cap · n²`; runtime
exceptions — heartbeats, recursion depth — are caught, interrupts
propagate).  The reduction starts from an empty `MetaM` cache (the previous
cache is restored afterwards), so the result is the same however often it is
measured within one command. -/
def adjacencyCostOf? (g V : Expr) (n cap : Nat) : MetaM (Option Nat) := do
  let limit := cap * n * n
  if limit == 0 then return none  -- `maxHeartbeats 0` would mean "no limit"
  let p ← adjacencyCostProp g V
  let some inst ← synthInstance? (mkApp (mkConst ``Decidable) p) | return none
  let e := mkApp2 (mkConst ``Decidable.decide) p inst
  -- Measure from an empty `MetaM` cache (restored afterwards), so that the
  -- result does not depend on what this command reduced before — a second
  -- measurement would otherwise hit the `whnf` cache and cost nothing.
  let savedCache := (← getThe Meta.State).cache
  modifyThe Meta.State fun st => { st with cache := {} }
  let start ← IO.getNumHeartbeats
  let reduced? ← tryCatchRuntimeEx
    (withTheReader Core.Context
      (fun ctx => { ctx with initHeartbeats := start, maxHeartbeats := limit }) do
        return some (← withAtLeastTransparency .default <| whnf e))
    (fun ex => do
      modifyThe Meta.State fun st => { st with cache := savedCache }
      if ex.isInterrupt then throw ex else return none)
  let used := (← IO.getNumHeartbeats) - start
  modifyThe Meta.State fun st => { st with cache := savedCache }
  match reduced? with
  | some r =>
    if r.isConstOf ``Bool.true && used ≤ limit then
      return some ((used + n * n - 1) / (n * n))
    else return none
  | none => return none

/-- Everything the connectivity link depends on (see `connectivityCheck`). -/
structure ConnectivityCheck where
  /-- The pure verdict at zero adjacency cost: the domain bounds and the walk
  work alone (a lower bound on the estimate). -/
  atZeroCost : Insert.ConnectivityVerdict
  /-- The adjacency-cost guard on the graph's own instance (`none`: no
  `DecidableRel` instance). -/
  guard : Option AdjCost
  /-- The largest adjacency cost the budget allows (`Insert.maxAdjacencyCost?`). -/
  cap : Option Nat
  /-- The measured cost of one adjacency decision; measured only when the
  zero-cost verdict offers the link and the guard is `validated`, and `none`
  when not measured or not within `cap`. -/
  adjCost : Option Nat
  deriving Repr, Inhabited

/-- The final verdict: at the measured adjacency cost, when there is one. -/
def ConnectivityCheck.verdict? (c : ConnectivityCheck) (d : GraphData) :
    Option Insert.ConnectivityVerdict :=
  c.adjCost.map (Insert.connectivityVerdict d ·)

/-- Is the connectivity link offered? -/
def ConnectivityCheck.offered (c : ConnectivityCheck) (d : GraphData) : Bool :=
  (c.verdict? d).any (·.isOffered)

/-- Decide the connectivity link for `g : SimpleGraph V` with extracted data
`d`: the walk work must fit the budget at zero adjacency cost (pure, cheap),
the instance must pass the adjacency-cost guard (`adjLimit` is its search
limit), and the measured adjacency cost must keep the estimate within the
budget (measured only when the first two hold). -/
def connectivityCheck (g V : Expr) (d : GraphData) (adjLimit : Nat := adjCostSearchLimit) :
    MetaM ConnectivityCheck := do
  let atZeroCost := Insert.connectivityVerdict d 0
  let guard ← graphAdjacencyCost? g adjLimit
  let cap := Insert.maxAdjacencyCost? d
  match cap with
  | some c =>
    if guard.any (·.connectivityOk) then
      return { atZeroCost, guard, cap, adjCost := ← adjacencyCostOf? g V d.n c }
    else return { atZeroCost, guard, cap, adjCost := none }
  | none => return { atZeroCost, guard, cap, adjCost := none }

/-- Compute the verified click-to-insert suggestions for an extracted graph:
gate every vertex label through `labelRoundTrips`, then build edge facts (both
endpoints gated), degree facts (endpoint gated) and the connectivity fact
(under `connectivityCheck`: the walk-work estimate at the measured adjacency
cost, and the adjacency-cost guard `adjacencyCost`) from the *pure* text
builders.  `gSrc` is the user's graph
term, verbatim from the source file; `g` the elaborated graph; `adjLimit` the
`adjacencyCost` search limit (tests lower it to reach the `.unknown` verdict).
Returns `{}` (no links, plain panel) when the term's shape or instances cannot
be re-derived. -/
def computeInsertions (gSrc : String) (g : Expr) (d : GraphData)
    (adjLimit : Nat := adjCostSearchLimit) : TermElabM LinkInfo := do
  let g ← instantiateMVars g
  let gty ← whnf (← inferType g)
  let some V := gty.app1? ``SimpleGraph | return {}
  let some finInst ← synthInstance? (← mkAppM ``Fintype #[V]) | return {}
  let some deqInst ← synthInstance? (← mkAppM ``DecidableEq #[V]) | return {}
  let mut okLabel : Array Bool := #[]
  let mut notInsertable : Array (Nat × String) := #[]
  for i in [0:d.n] do
    -- One parse + elaboration + compiled evaluation per vertex: allow editor
    -- cancellation between vertices, like extraction does between rows.
    Core.checkSystem "#graph_scope"
    let ok ← labelRoundTrips V finInst deqInst (d.label i) i
    okLabel := okLabel.push ok
    unless ok do
      notInsertable := notInsertable.push (i, d.label i)
  let mut edges : Array (Nat × Nat × String) := #[]
  for (a, b) in d.edges do
    if okLabel.getD a false && okLabel.getD b false then
      edges := edges.push (a, b, Insert.edgeExampleText gSrc (d.label a) (d.label b))
  let mut degrees : Array (Nat × String) := #[]
  for i in [0:d.n] do
    if okLabel.getD i false then
      degrees := degrees.push (i, Insert.degreeExampleText gSrc (d.label i) (d.degree i))
  -- The connectivity fact: walk work, adjacency-cost guard, measured
  -- adjacency cost (`connectivityCheck`).
  let connectivityOk := (← connectivityCheck g V d adjLimit).offered d
  let connected? : Option String :=
    if connectivityOk then
      some (if d.isConnected then Insert.connectedExampleText gSrc
            else Insert.notConnectedExampleText gSrc)
    else none
  return { edges, degrees, connected?, notInsertable }

end GraphScope
