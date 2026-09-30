import DistLens.Model
import Mathlib.Probability.ProbabilityMassFunction.Constructions
import Mathlib.Probability.ProbabilityMassFunction.Binomial
import Mathlib.Probability.Distributions.Uniform
import Mathlib.Lean.Expr.Rat

/-! # DistLens: extraction

The impure layer: a **whitelist matcher** over elaborated `PMF` terms that
computes the exact ℚ weight vector Lean-side (its own tiny interpreter:
pointwise for `uniformOfFintype`/`uniformOfFinset`/`bernoulli`/`binomial`/
`pure`/`ofFintype`, convolution for `bind`, pushforward with collision
summing for `map`).  **No ℝ≥0∞ value is ever evaluated numerically** — PMF
applications are noncomputable (`#eval` fails with
`dependsOnNoncomputable`), so the weights come from the *parameters* of the
whitelisted constructors, all parsed as exact ℚ.

Supported carriers for outcome-level work (`pure`, `bind`, `map` sources and
targets, verification keys): `Fin n`, `Bool`, `ℕ`.  `uniformOfFintype` over
any other `Fintype` carrier is still displayed (cardinality and `Repr`
labels obtained through compiled evaluation, exactly like GraphScope), but
such "opaque" distributions refuse `bind`/`map` honestly.

Honest refusals (each names the exact reason, pinned by tests): symbolic
parameters, non-literal finsets/weight vectors, subtype-`mk`-producing
`map`/`bind` functions (the probe report shows `simp` hits `maxRecDepth` on
them, so the verification recipe would break its promise), carriers beyond
`Fin`/`Bool`/`ℕ`, caps exceeded (with the actual sizes), and any head that
is not a whitelisted constructor.

Caps are checked **before** any evaluation: `maxOutcomes = 64` per
distribution, `maxBindDepth = 8` constructor nesting, `maxChainStates = 16`.
-/

namespace DistLens

open Lean Meta Elab PMF

/-- Hard cap on the number of outcomes DistLens will extract and draw. -/
def maxOutcomes : Nat := 64

/-- Hard cap on `bind`/`map` constructor nesting depth. -/
def maxBindDepth : Nat := 8

/-- Hard cap on the number of Markov-chain states (`n × n` matrix). -/
def maxChainStates : Nat := 16

/-- Outcome carrier of an extracted distribution.  Only `fin`/`bool`/`nat`
support outcome-level work (`bind`/`map`, verification keys); `opaqueTy` is
display-only (`uniformOfFintype` over an arbitrary `Fintype`). -/
inductive Carrier where
  /-- `Fin n` with a literal `n`. -/
  | fin (n : Nat)
  /-- `Bool` (keys: `false ↦ 0`, `true ↦ 1`). -/
  | bool
  /-- `ℕ` (infinite type, finite reachable support). -/
  | nat
  /-- Any other `Fintype` carrier, display-only. -/
  | opaqueTy (name : String)
  deriving Repr, BEq, Inhabited

/-- Display name of a carrier. -/
def Carrier.name : Carrier → String
  | .fin n => s!"Fin {n}"
  | .bool => "Bool"
  | .nat => "ℕ"
  | .opaqueTy s => s

/-- An extracted distribution: carrier, outcome keys (ascending; `Fin`/`Bool`
carriers list the *full* range including zero-weight outcomes, `ℕ` lists the
reachable support), labels and exact ℚ weights. -/
structure XDist where
  /-- The outcome carrier. -/
  carrier : Carrier
  /-- Outcome keys, ascending (`Fin`/`ℕ`: the value; `Bool`: 0/1). -/
  keys : Array Nat
  /-- One display label per outcome. -/
  labels : Array String
  /-- One exact ℚ weight per outcome. -/
  weights : Array Rat
  deriving Repr, BEq, Inhabited

/-- Label of key `k` in carrier `c`. -/
def Carrier.keyLabel (c : Carrier) (k : Nat) : String :=
  match c with
  | .bool => if k == 0 then "false" else "true"
  | _ => toString k

/-- The canonical ℚ value of key `k` (`Fin`/`ℕ`: itself; `Bool`: 0/1). -/
def Carrier.keyValue (_ : Carrier) (k : Nat) : Rat := (k : Nat)

/-- Convert to the pure `DistModel` (labels, weights, canonical values for
`fin`/`bool`/`nat`; no values for opaque carriers). -/
def XDist.toModel (d : XDist) : DistModel :=
  { carrier := d.carrier.name
    labels := d.labels
    weights := d.weights
    values? := match d.carrier with
      | .opaqueTy _ => none
      | c => some (d.keys.map c.keyValue) }

/-- Build an `XDist` from a carrier and sorted `(key, weight)` rows:
`Fin`/`Bool` carriers are padded to the full range (zero-weight outcomes
included), `ℕ` keeps just the given support. -/
def XDist.ofPairs (c : Carrier) (pairs : Array (Nat × Rat)) : XDist :=
  let keys : Array Nat :=
    match c with
    | .fin n => Array.range n
    | .bool => #[0, 1]
    | _ => pairs.map (·.1)
  let weights := keys.map fun k =>
    match pairs.find? (·.1 == k) with
    | some (_, w) => w
    | none => 0
  { carrier := c, keys, labels := keys.map c.keyLabel, weights }

/-! ## Expr utilities -/

/-- Pretty-print an expression to a single line (deterministic error text). -/
def ppOneLine (e : Expr) : MetaM String := do
  return (← ppExpr e).pretty (width := 100000)

/-- Parse an exact rational from a numeral expression over `ℝ≥0` / `ℝ≥0∞`:
`OfNat` literals (via `Expr.rat?`), `HDiv.hDiv`, `Inv.inv`, `Neg.neg` and
`Nat.cast` of numerals, applied recursively (the probe-documented shapes of
`(2/3 : ℝ≥0)` and friends).  `none` for anything symbolic. -/
partial def parseQ? (e : Expr) : Option Rat :=
  let e := e.consumeMData
  if e.isAppOfArity ``HDiv.hDiv 6 then do
    let n ← parseQ? (e.getArg! 4)
    let d ← parseQ? (e.getArg! 5)
    guard (d ≠ 0)
    pure (n / d)
  else if e.isAppOfArity ``Inv.inv 3 then do
    let d ← parseQ? (e.getArg! 2)
    guard (d ≠ 0)
    pure (1 / d)
  else if e.isAppOfArity ``Neg.neg 3 then do
    let n ← parseQ? (e.getArg! 2)
    pure (-n)
  else if e.isAppOfArity ``Nat.cast 3 then
    parseQ? (e.getArg! 2)
  else if e.isAppOfArity ``cond 4 then
    -- `bif b then p else q` with a literal `b` (bernoulli parameters built
    -- by case-splitting continuations).
    let c := (e.getArg! 1).consumeMData
    if c.isConstOf ``Bool.true then parseQ? (e.getArg! 2)
    else if c.isConstOf ``Bool.false then parseQ? (e.getArg! 3)
    else none
  else
    e.rat?

/-- Parse a literal `ℕ` from an expression: raw literal, `OfNat` numeral, or
`Nat.succ` chains (the spelling `Fin (Nat.succ 1)` produced by `![…]`
vector types). -/
partial def parseNatLit? (e : Expr) : Option Nat := do
  let e := e.consumeMData
  if e.isAppOfArity ``Nat.succ 1 then
    let n ← parseNatLit? (e.getArg! 0)
    pure (n + 1)
  else
    let q ← parseQ? e
    guard (q.den == 1 && q.num ≥ 0)
    pure q.num.toNat

/-- Recognize a carrier type expression (after `whnf`): `Fin n` with literal
`n`, `Bool`, or `ℕ`.  `none` for everything else. -/
def carrierOf? (ty : Expr) : MetaM (Option Carrier) := do
  let ty ← whnf ty
  if ty.isConstOf ``Bool then return some .bool
  else if ty.isConstOf ``Nat then return some .nat
  else if ty.isAppOfArity ``Fin 1 then
    match parseNatLit? (ty.getArg! 0) with
    | some n => return some (.fin n)
    | none => return none
  else return none

/-- Run one compiled-evaluation step, rebranding any failure as a `cmd` error
(interrupts and runtime errors pass through untouched). -/
def evalOrExplain (cmd what : String) (act : MetaM α) : MetaM α := do
  try
    act
  catch ex =>
    if ex.isInterrupt || ex.isRuntime then
      throw ex
    throwError "{cmd}: failed to {what} — {ex.toMessageData}"

/-- Evaluate an outcome expression of carrier `c` to its key, through
compiled code (`Fin` values via `Fin.val`, so the compiled term is always
`ℕ`- or `Bool`-typed).  The expressions this is applied to are closed
applications of user functions to literals, e.g. `(2 : Fin 6).val % 2`. -/
def evalKey (cmd : String) (c : Carrier) (e : Expr) : MetaM Nat := do
  match c with
  | .nat =>
    evalOrExplain cmd s!"evaluate `{← ppOneLine e}`" <|
      unsafe evalExpr' Nat ``Nat e
  | .fin _ =>
    let v ← mkAppM ``Fin.val #[e]
    evalOrExplain cmd s!"evaluate `{← ppOneLine e}`" <|
      unsafe evalExpr' Nat ``Nat v
  | .bool =>
    let b ← evalOrExplain cmd s!"evaluate `{← ppOneLine e}`" <|
      unsafe evalExpr' Bool ``Bool e
    return if b then 1 else 0
  | .opaqueTy n =>
    throwError "{cmd}: internal: cannot key outcomes of opaque carrier `{n}`"

/-- Build the outcome expression of key `k` in carrier `c` (`Fin` keys become
`OfNat` numerals through the synthesized instance). -/
def mkKeyExpr (cmd : String) (c : Carrier) (k : Nat) : MetaM Expr := do
  match c with
  | .nat => return mkNatLit k
  | .bool => return mkConst (if k == 0 then ``Bool.false else ``Bool.true)
  | .fin n =>
    let finTy := mkApp (mkConst ``Fin) (mkNatLit n)
    let ofNatCls ← mkAppM ``OfNat #[finTy, mkRawNatLit k]
    match ← synthInstance? ofNatCls with
    | some inst => mkAppOptM ``OfNat.ofNat #[finTy, mkRawNatLit k, inst]
    | none => throwError "{cmd}: internal: no `OfNat (Fin {n}) {k}` instance"
  | .opaqueTy n =>
    throwError "{cmd}: internal: cannot build outcomes of opaque carrier `{n}`"

/-- The constructor whitelist: heads `resolveHead` must *not* unfold. -/
def whitelistHeads : List Name :=
  [``PMF.uniformOfFintype, ``PMF.uniformOfFinset, ``PMF.bernoulli,
   ``PMF.binomial, ``PMF.pure, ``PMF.bind, ``PMF.map, ``PMF.ofFintype,
   ``Matrix.vecCons, ``Matrix.vecEmpty]

/-- Resolve a term to a whitelisted head: repeatedly beta-reduce and unfold
non-whitelisted definitions (so `noncomputable def die := uniformOfFintype …`
and `(fun a => …) 3` both resolve).  Stops at whitelisted heads, at
irreducible terms, and after a fuel bound. -/
partial def resolveHead (e : Expr) : MetaM Expr := do
  go (e.consumeMData) 32
where
  go (e : Expr) (fuel : Nat) : MetaM Expr := do
    if fuel == 0 then return e
    let e' := e.headBeta.consumeMData
    if e' != e then return ← go e' (fuel - 1)
    let f := e.getAppFn
    if let .const n _ := f then
      if whitelistHeads.contains n then return e
      match ← unfoldDefinition? e with
      | some e' => go e' (fuel - 1)
      | none => return e
    else
      return e

/-- The standard honest refusal for a non-whitelisted head. -/
def unsupportedHead (cmd : String) (e : Expr) : MetaM α :=
  throwError "{cmd}: `{e.getAppFn}` is not a supported PMF constructor — \
    DistLens matches PMF.pure, PMF.bind, PMF.map, PMF.uniformOfFintype, \
    PMF.uniformOfFinset, PMF.bernoulli, PMF.binomial and PMF.ofFintype \
    (with `![…]` literal weights); symbolic or monadic spellings are \
    refused rather than guessed at"

/-! ## Literal container parsers -/

/-- Parse a literal `Finset` expression (`{1, 2, 3}` = `insert`/`singleton`
chains) into its element expressions.  `none` for non-literal finsets. -/
partial def parseFinsetLit? (e : Expr) : Option (Array Expr) := do
  let e := e.consumeMData
  if e.isAppOfArity ``Insert.insert 5 then
    let rest ← parseFinsetLit? (e.getArg! 4)
    pure (#[e.getArg! 3] ++ rest)
  else if e.isAppOfArity ``Singleton.singleton 4 then
    pure #[e.getArg! 3]
  else
    none

/-- Parse a `![w₀, …, wₙ₋₁]` literal (a `Matrix.vecCons` chain ending in
`vecEmpty`) into its entry expressions.  `none` for anything else. -/
partial def parseVecLit? (e : Expr) : Option (Array Expr) := do
  let e := e.consumeMData
  if e.isAppOfArity ``Matrix.vecCons 4 then
    let rest ← parseVecLit? (e.getArg! 3)
    pure (#[e.getArg! 2] ++ rest)
  else if e.isAppOfArity ``Matrix.vecEmpty 1 then
    pure #[]
  else
    none

/-- Does the expression mention `Fin.mk` or `Subtype.mk` (an anonymous-
constructor-with-proof value)?  Such `map`/`bind` targets are refused: the
probe report shows the verification `simp` recipe hits `maxRecDepth` on
subtype-mk images, so extraction would show a picture whose proof action is
broken. -/
def mentionsSubtypeMk (e : Expr) : Bool :=
  Option.isSome <| e.find? fun sub =>
    match sub with
    | .const n _ => n == ``Fin.mk || n == ``Subtype.mk
    | _ => false

/-! ## Opaque `uniformOfFintype` support (GraphScope-style evaluation) -/

/-- `Repr` labels of every element of `V` in `Fintype` enumeration order.
Unsafe because it reveals the runtime representative of the `elems` multiset
— exactly the deterministic enumeration order the display indexes by.  Only
ever run through `evalExpr (safety := .unsafe)`. -/
unsafe def rawFintypeLabels (V : Type u) [Fintype V] [Repr V] : Array String :=
  (((Fintype.elems (α := V)).val.unquot).toArray).map fun v => reprStr v

/-- Synthesize an instance or fail with a `cmd`-branded error naming exactly
the missing instance.  Rejects noncomputable synthesized instances (they
would crash compiled evaluation later with raw compiler advice). -/
def synthOrExplain (cmd : String) (type : Expr) : MetaM Expr := do
  match ← synthInstance? type with
  | none => throwError "{cmd}: cannot synthesize `{← ppOneLine type}`"
  | some inst =>
    let inst ← instantiateMVars inst
    let env ← getEnv
    if let some c := inst.getUsedConstants.find? (isNoncomputable env ·) then
      throwError "{cmd}: the instance synthesized for `{← ppOneLine type}` is \
        noncomputable (it uses `{c}`) — DistLens evaluates carrier data with \
        compiled code, so it needs computable instances"
    return inst

/-- Extract a display-only `XDist` for `uniformOfFintype V` over an arbitrary
(non-`Fin`/`Bool`) carrier: evaluate `Fintype.card` (cap-checked), label
outcomes via `Repr` when available (indices otherwise). -/
def extractOpaqueUniform (cmd : String) (V : Expr) : MetaM XDist := do
  let finInst ← synthOrExplain cmd (← mkAppM ``Fintype #[V])
  let cardE ← mkAppOptM ``Fintype.card #[V, finInst]
  let card ← evalOrExplain cmd "evaluate the carrier cardinality" <|
    unsafe evalExpr' Nat ``Nat cardE
  if card > maxOutcomes then
    throwError "{cmd}: the carrier has {card} outcomes, more than the limit \
      of {maxOutcomes} — DistLens refuses to draw it"
  if card == 0 then
    throwError "{cmd}: internal: `uniformOfFintype` over an empty carrier"
  let labels ← do
    match ← synthInstance? (← mkAppM ``Repr #[V]) with
    | some reprInst =>
      let reprInst ← instantiateMVars reprInst
      if reprInst.getUsedConstants.any (isNoncomputable (← getEnv) ·) then
        pure ((Array.range card).map toString)
      else
        let labE ← mkAppOptM ``rawFintypeLabels #[V, finInst, reprInst]
        let labTy := mkApp (mkConst ``Array [.zero]) (mkConst ``String)
        evalOrExplain cmd "evaluate the outcome labels" <|
          unsafe evalExpr (Array String) labTy labE (safety := .unsafe)
    | none => pure ((Array.range card).map toString)
  return { carrier := .opaqueTy (← ppOneLine V)
           keys := Array.range card
           labels
           weights := uniformWeights card }

/-! ## The main extractor -/

/-- Extract an `XDist` from an elaborated `PMF` term by whitelist matching
(see the module docstring for the exact contract, refusals and caps). -/
partial def extractDist (cmd : String) (e : Expr) (depth : Nat := 0) :
    MetaM XDist := do
  if depth > maxBindDepth then
    throwError "{cmd}: PMF constructor nesting exceeds the depth limit of \
      {maxBindDepth} — DistLens refuses to extract it"
  Core.checkSystem "DistLens"
  let e ← resolveHead (← instantiateMVars e)
  if e.hasExprMVar then
    throwError "{cmd}: the PMF term still contains metavariables (`_`) — \
      fill in the underscores so the distribution is fully determined"
  -- `uniformOfFintype α _ _`
  if e.isAppOfArity ``PMF.uniformOfFintype 3 then
    let α := e.getArg! 0
    match ← carrierOf? α with
    | some (.fin n) =>
      if n > maxOutcomes then
        throwError "{cmd}: the carrier has {n} outcomes, more than the limit \
          of {maxOutcomes} — DistLens refuses to draw it"
      return XDist.ofPairs (.fin n)
        ((Array.range n).map fun k => (k, (1 : Rat) / n))
    | some .bool =>
      return XDist.ofPairs .bool #[(0, 1/2), (1, 1/2)]
    | some .nat =>
      throwError "{cmd}: internal: `uniformOfFintype ℕ` cannot occur"
    | some (.opaqueTy _) | none => extractOpaqueUniform cmd α
  -- `uniformOfFinset α s h`
  else if e.isAppOfArity ``PMF.uniformOfFinset 3 then
    let α := e.getArg! 0
    let some c ← carrierOf? α
      | throwError "{cmd}: `uniformOfFinset` is supported over `Fin n`, \
          `Bool` and `ℕ` carriers only, not `{← ppOneLine α}`"
    let some elems := parseFinsetLit? (e.getArg! 1)
      | throwError "{cmd}: the finset `{← ppOneLine (e.getArg! 1)}` is not a \
          literal `\{a, b, …}` — symbolic finsets are refused rather than \
          guessed at"
    if elems.size > maxOutcomes then
      throwError "{cmd}: the finset has {elems.size} listed elements, more \
        than the limit of {maxOutcomes} — DistLens refuses to draw it"
    let mut keys : Array Nat := #[]
    for el in elems do
      let k ← evalKey cmd c el
      unless keys.contains k do
        keys := keys.push k
    -- Finset literals carry insertion order (`{3, 1, 2}`); sort so the
    -- rendered outcome listing and the CDF honor `XDist.keys`' ascending
    -- contract regardless of how the user wrote the literal.
    keys := keys.qsort (· < ·)
    let card := keys.size
    return XDist.ofPairs c (keys.map fun k => (k, (1 : Rat) / card))
  -- `bernoulli p h`
  else if e.isAppOfArity ``PMF.bernoulli 2 then
    let some p := parseQ? (e.getArg! 0)
      | throwError "{cmd}: the bernoulli parameter `{← ppOneLine (e.getArg! 0)}` \
          is not a rational literal — symbolic parameters are refused rather \
          than guessed at"
    if p < 0 || p > 1 then
      throwError "{cmd}: internal: bernoulli parameter {ratStr p} outside [0, 1]"
    return XDist.ofPairs .bool #[(0, 1 - p), (1, p)]
  -- `binomial p h n`
  else if e.isAppOfArity ``PMF.binomial 3 then
    let some p := parseQ? (e.getArg! 0)
      | throwError "{cmd}: the binomial parameter `{← ppOneLine (e.getArg! 0)}` \
          is not a rational literal — symbolic parameters are refused rather \
          than guessed at"
    let some n := parseNatLit? (e.getArg! 2)
      | throwError "{cmd}: the binomial count `{← ppOneLine (e.getArg! 2)}` is \
          not a numeral"
    if p < 0 || p > 1 then
      throwError "{cmd}: internal: binomial parameter {ratStr p} outside [0, 1]"
    if n + 1 > maxOutcomes then
      throwError "{cmd}: binomial with {n + 1} outcomes exceeds the limit of \
        {maxOutcomes} — DistLens refuses to draw it"
    let ws := binomialWeights p n
    return XDist.ofPairs (.fin (n + 1))
      ((Array.range (n + 1)).map fun k => (k, ws[k]!))
  -- `PMF.pure a`
  else if e.isAppOfArity ``PMF.pure 2 then
    let a := e.getArg! 1
    let some c ← carrierOf? (← inferType a)
      | throwError "{cmd}: `PMF.pure` is supported over `Fin n`, `Bool` and \
          `ℕ` carriers only, not `{← ppOneLine (← inferType a)}`"
    if let .fin n := c then
      if n > maxOutcomes then
        throwError "{cmd}: the carrier has {n} outcomes, more than the limit \
          of {maxOutcomes} — DistLens refuses to draw it"
    let k ← evalKey cmd c a
    return XDist.ofPairs c #[(k, 1)]
  -- `PMF.bind p f`
  else if e.isAppOfArity ``PMF.bind 4 then
    let β := e.getArg! 1
    let p := e.getArg! 2
    let f := e.getArg! 3
    let src ← extractDist cmd p (depth + 1)
    if let .opaqueTy nm := src.carrier then
      throwError "{cmd}: `bind` from a distribution over `{nm}` is not \
        supported — DistLens can only follow outcomes of `Fin n`, `Bool` \
        and `ℕ` carriers"
    let some tgt ← carrierOf? β
      | throwError "{cmd}: `bind` into carrier `{← ppOneLine β}` is not \
          supported — DistLens follows `Fin n`, `Bool` and `ℕ`-valued \
          continuations only (subtype-valued ones would break the `pmf_num` \
          verification recipe)"
    if mentionsSubtypeMk f then
      throwError "{cmd}: the bound function builds `Fin.mk`/`Subtype.mk` \
        values — refused, because the `pmf_num` verification recipe provably \
        hits `maxRecDepth` on subtype-mk images; use a `ℕ`-valued map \
        instead (e.g. `.val` arithmetic)"
    let supp := (Array.range src.keys.size).filter fun i => src.weights[i]! > 0
    let mut condls : Array (Array (Nat × Rat)) := #[]
    for i in supp do
      Core.checkSystem "DistLens"
      let x ← mkKeyExpr cmd src.carrier src.keys[i]!
      let branch ← extractDist cmd (mkApp f x).headBeta (depth + 1)
      unless branch.carrier == tgt do
        throwError "{cmd}: internal: bind branch carrier \
          `{branch.carrier.name}` differs from `{tgt.name}`"
      condls := condls.push (branch.keys.zip branch.weights)
    let pairs := convolve (supp.map fun i => src.weights[i]!) condls
    if pairs.size > maxOutcomes then
      throwError "{cmd}: the bind result has {pairs.size} outcomes, more than \
        the limit of {maxOutcomes} — DistLens refuses to draw it"
    if let .fin n := tgt then
      if n > maxOutcomes then
        throwError "{cmd}: the carrier has {n} outcomes, more than the limit \
          of {maxOutcomes} — DistLens refuses to draw it"
    return XDist.ofPairs tgt pairs
  -- `PMF.map f p`
  else if e.isAppOfArity ``PMF.map 4 then
    let β := e.getArg! 1
    let f := e.getArg! 2
    let p := e.getArg! 3
    let src ← extractDist cmd p (depth + 1)
    if let .opaqueTy nm := src.carrier then
      throwError "{cmd}: `map` from a distribution over `{nm}` is not \
        supported — DistLens can only follow outcomes of `Fin n`, `Bool` \
        and `ℕ` carriers"
    let some tgt ← carrierOf? β
      | throwError "{cmd}: `map` into carrier `{← ppOneLine β}` is not \
          supported — DistLens follows `Fin n`, `Bool` and `ℕ`-valued maps \
          only (subtype-valued ones would break the `pmf_num` verification \
          recipe)"
    if mentionsSubtypeMk f then
      throwError "{cmd}: the map function builds `Fin.mk`/`Subtype.mk` \
        values — refused, because the `pmf_num` verification recipe provably \
        hits `maxRecDepth` on subtype-mk images; use a `ℕ`-valued map \
        instead (e.g. `.val` arithmetic)"
    let supp := (Array.range src.keys.size).filter fun i => src.weights[i]! > 0
    let mut imageKeys : Array Nat := #[]
    for i in supp do
      Core.checkSystem "DistLens"
      let x ← mkKeyExpr cmd src.carrier src.keys[i]!
      imageKeys := imageKeys.push (← evalKey cmd tgt (mkApp f x).headBeta)
    let pairs := pushforward (supp.map fun i => src.weights[i]!) imageKeys
    if let .fin n := tgt then
      if n > maxOutcomes then
        throwError "{cmd}: the carrier has {n} outcomes, more than the limit \
          of {maxOutcomes} — DistLens refuses to draw it"
    return XDist.ofPairs tgt pairs
  -- `ofFintype f h`
  else if e.isAppOfArity ``PMF.ofFintype 4 then
    let f := e.getArg! 2
    let some entries := parseVecLit? f
      | throwError "{cmd}: the `ofFintype` weight function \
          `{← ppOneLine f}` is not a `![…]` literal vector — symbolic weight \
          functions are refused rather than guessed at"
    if entries.size > maxOutcomes then
      throwError "{cmd}: the weight vector has {entries.size} entries, more \
        than the limit of {maxOutcomes} — DistLens refuses to draw it"
    let mut ws : Array Rat := #[]
    for ent in entries do
      let some w := parseQ? ent
        | throwError "{cmd}: the weight `{← ppOneLine ent}` is not a rational \
            literal — symbolic weights are refused rather than guessed at"
      if w < 0 then
        throwError "{cmd}: internal: parsed a negative weight {ratStr w}"
      ws := ws.push w
    return XDist.ofPairs (.fin entries.size)
      ((Array.range entries.size).map fun k => (k, ws[k]!))
  else
    unsupportedHead cmd e

/-! ## Bind filmstrips -/

/-- A `#dist_film` filmstrip: the source distribution, one frame per source
outcome (its conditional distribution), and the convolved result. -/
structure BindFilm where
  /-- The source distribution `p` of `p.bind f`. -/
  source : XDist
  /-- Per support outcome of `p` (label order): the extracted `f a`. -/
  branches : Array (String × XDist)
  /-- The convolved result (extracted from the whole `bind` term). -/
  result : XDist
  deriving Repr, Inhabited

/-- Extract a `BindFilm` from a term whose head resolves to `PMF.bind`
(honest refusal otherwise: `#dist_film` is only meaningful for binds). -/
def extractBindFilm (cmd : String) (e : Expr) : MetaM BindFilm := do
  let e ← resolveHead (← instantiateMVars e)
  unless e.isAppOfArity ``PMF.bind 4 do
    throwError "{cmd}: expected a `PMF.bind` term to film — \
      `{← ppOneLine e}` does not resolve to one"
  let p := e.getArg! 2
  let f := e.getArg! 3
  let src ← extractDist cmd p 1
  if let .opaqueTy nm := src.carrier then
    throwError "{cmd}: `bind` from a distribution over `{nm}` is not \
      supported — DistLens can only follow outcomes of `Fin n`, `Bool` \
      and `ℕ` carriers"
  let supp := (Array.range src.keys.size).filter fun i => src.weights[i]! > 0
  let mut branches : Array (String × XDist) := #[]
  for i in supp do
    Core.checkSystem "DistLens"
    let x ← mkKeyExpr cmd src.carrier src.keys[i]!
    let branch ← extractDist cmd (mkApp f x).headBeta 1
    branches := branches.push (src.labels[i]!, branch)
  let result ← extractDist cmd e
  return { source := src, branches, result }

/-! ## Markov chains -/

/-- An extracted chain: the exact model plus per-state row distributions
(used by the transition-graph renderer's labels). -/
structure ChainData where
  /-- The exact ℚ chain model. -/
  model : ChainModel
  deriving Repr, Inhabited

/-- Extract a `ChainModel` from `step : Fin n → PMF (Fin n)` (literal `n`,
capped at `maxChainStates`): resolve `step`, then extract row `i` from
`step i` — via syntactic `![…]` entry selection when `step` is a vector
literal, via application otherwise.  Every row must be a full distribution
over `Fin n`. -/
def extractChain (cmd : String) (e : Expr) : MetaM ChainModel := do
  let orig ← instantiateMVars e
  let e ← resolveHead orig
  let ty ← whnf (← inferType e)
  let tyErr : MessageData :=
    m!"{cmd}: expected a term of type `Fin n → PMF (Fin n)` with a \
      literal `n`, but `{← ppOneLine orig}` has type `{← ppOneLine ty}`"
  let .forallE _ dom img _ := ty | throwError tyErr
  let some (.fin n) ← carrierOf? dom | throwError tyErr
  -- NB `whnf` would unfold `PMF` itself (it is a `def`, not an inductive),
  -- so reduce only *until* the `PMF` head.
  let imgOk ← do
    match ← whnfUntil img ``PMF with
    | some img =>
      if img.isAppOfArity ``PMF 1 then
        pure ((← carrierOf? (img.getArg! 0)) == some (.fin n))
      else pure false
    | none => pure false
  unless imgOk do throwError tyErr
  if n == 0 then
    throwError "{cmd}: a chain needs at least one state"
  if n > maxChainStates then
    throwError "{cmd}: the chain has {n} states, more than the limit of \
      {maxChainStates} — DistLens refuses to draw it"
  let entries? := parseVecLit? e
  let mut rows : Array (Array Rat) := #[]
  for i in [0:n] do
    Core.checkSystem "DistLens"
    let rowTerm ← do
      match entries? with
      | some ents =>
        if h : i < ents.size then pure ents[i]
        else throwError "{cmd}: internal: vector literal too short at row {i}"
      | none =>
        let x ← mkKeyExpr cmd (.fin n) i
        pure (mkApp e x).headBeta
    let row ← extractDist cmd rowTerm 1
    unless row.carrier == .fin n && row.weights.size == n do
      throwError "{cmd}: internal: row {i} extracted over \
        `{row.carrier.name}` with {row.weights.size} outcomes, expected \
        `Fin {n}`"
    rows := rows.push row.weights
  return { n, matrix := rows }

end DistLens
