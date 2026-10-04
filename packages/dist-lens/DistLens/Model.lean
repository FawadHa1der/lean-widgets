import Mathlib.Data.Rat.Defs
import Mathlib.Data.Nat.Choose.Basic

/-! # DistLens: the pure model

Exact-ℚ models of finite probability distributions and finite Markov chains.
Everything in this file is pure and `#guard`-testable: no `Expr`, no `MetaM`,
no floating point anywhere.

* `DistModel` — a finite distribution as parallel arrays of outcome labels and
  exact ℚ weights, with an optional canonical ℚ value per outcome (used for
  expectation/variance).  `invariantViolations` is the self-check overlay: a
  model produced by the extractor should always pass; any violation flags an
  extractor bug rather than being silently rendered.
* CDF prefix sums, expectation and variance in ℚ, support filtering.
* `ChainModel` — an `n`-state Markov chain as an exact ℚ transition matrix
  (row = from-state), with row-sum self-checks, exact matrix-vector power
  iteration, and the stationary distribution `π P = π`, `Σ π = 1` solved by
  exact Gaussian elimination — reporting a unique `π`, a non-unique solution
  space (reducible chain), or inconsistency (which would flag a bug, since a
  genuine stochastic matrix always has a stationary vector).
-/

namespace DistLens

/-! ## Rational formatting -/

/-- Render a rational exactly: `"1/6"`, `"3/4"`, `"2"`, `"0"`, `"-1/2"`.
Deterministic (no scientific notation, no rounding); used by both the SVG
labels and the text reports. -/
def ratStr (q : Rat) : String :=
  if q.den == 1 then toString q.num else s!"{q.num}/{q.den}"

/-- Percent approximation for captions: `q·1000` rounded half-up to an
integer per-mille, rendered as `"16.7%"`.  Display-only sugar next to an
exact label, never used in computation. -/
def ratPercentStr (q : Rat) : String :=
  let scaled := q * 1000 + 1/2
  let perMille : Int := scaled.floor
  let whole := perMille / 10
  let tenth := (perMille % 10).natAbs
  s!"{whole}.{tenth}%"

/-! ## Finite distributions -/

/-- A finite distribution: outcome labels with exact ℚ weights, plus an
optional canonical ℚ value per outcome (e.g. `Fin`/`ℕ` outcomes value
themselves, `Bool` values `false ↦ 0`, `true ↦ 1`) used for expectation and
variance.  `carrier` is a display name for the outcome type. -/
structure DistModel where
  /-- Display name of the outcome type, e.g. `"Fin 6"`, `"ℕ"`, `"Bool"`. -/
  carrier : String
  /-- One label per outcome, e.g. `"0"`, `"true"`. -/
  labels : Array String
  /-- One exact ℚ weight per outcome, same order as `labels`. -/
  weights : Array Rat
  /-- Canonical ℚ value per outcome for expectation/variance, when the
  carrier has one (`Fin`/`ℕ`: the number itself; `Bool`: 0/1). -/
  values? : Option (Array Rat) := none
  deriving Repr, BEq, Inhabited

namespace DistModel

/-- Number of outcomes. -/
def size (d : DistModel) : Nat := d.weights.size

/-- Total mass `Σ weights` (should be exactly 1). -/
def massTotal (d : DistModel) : Rat :=
  d.weights.foldl (· + ·) 0

/-- Invariant self-check: label/weight/value array lengths agree, every weight
is `≥ 0`, and the total mass is exactly 1.  Returns one human-readable line
per violation; a non-empty result flags an *extractor bug* (the extractor
computes weights itself, so a bad model is never the user's fault) and is
rendered as a warning overlay, never silently dropped. -/
def invariantViolations (d : DistModel) : Array String := Id.run do
  let mut out : Array String := #[]
  if d.labels.size != d.weights.size then
    out := out.push
      s!"internal: {d.labels.size} labels but {d.weights.size} weights"
  if let some vs := d.values? then
    if vs.size != d.weights.size then
      out := out.push
        s!"internal: {vs.size} values but {d.weights.size} weights"
  for i in [0:d.weights.size] do
    if d.weights[i]! < 0 then
      out := out.push
        s!"internal: weight {ratStr d.weights[i]!} at outcome {i} is negative"
  let m := d.massTotal
  if m != 1 then
    out := out.push s!"internal: total mass is {ratStr m}, not 1"
  return out

/-- CDF prefix sums: `cdf[i] = Σ_{j ≤ i} weights[j]` (same length as
`weights`; the last entry is the total mass). -/
def cdf (d : DistModel) : Array Rat :=
  (d.weights.foldl (init := (#[], (0 : Rat))) fun (acc, s) w =>
    (acc.push (s + w), s + w)).1

/-- Indices of the support (outcomes with weight `> 0`), ascending. -/
def supportIdxs (d : DistModel) : Array Nat :=
  (Array.range d.size).filter fun i => d.weights[i]! > 0

/-- Restrict the model to its support (drops zero-weight outcomes). -/
def restrictToSupport (d : DistModel) : DistModel :=
  let idxs := d.supportIdxs
  { carrier := d.carrier
    labels := idxs.map (d.labels[·]!)
    weights := idxs.map (d.weights[·]!)
    values? := d.values?.map fun vs => idxs.map (vs[·]!) }

/-- Expectation `E[X] = Σ w_i v_i` against an explicit ℚ value map. -/
def expectationWith (d : DistModel) (vs : Array Rat) : Rat :=
  (d.weights.zip vs).foldl (init := (0 : Rat)) fun s (w, v) => s + w * v

/-- Variance `Var[X] = E[X²] − E[X]²` against an explicit ℚ value map. -/
def varianceWith (d : DistModel) (vs : Array Rat) : Rat :=
  let e := d.expectationWith vs
  let e2 := (d.weights.zip vs).foldl (init := (0 : Rat)) fun s (w, v) => s + w * v * v
  e2 - e * e

/-- Expectation against the canonical value map, when there is one. -/
def expectation? (d : DistModel) : Option Rat :=
  d.values?.map d.expectationWith

/-- Variance against the canonical value map, when there is one. -/
def variance? (d : DistModel) : Option Rat :=
  d.values?.map d.varianceWith

end DistModel

/-! ## Filmstrips -/

/-- A filmstrip: captioned frames, each a full `DistModel` (used by the
`#dist_film` bind view and the `#chain` power iteration). -/
structure FilmModel where
  /-- `(caption, distribution)` per frame, in order. -/
  frames : Array (String × DistModel)
  deriving Repr, BEq, Inhabited

namespace FilmModel

/-- Diff marks of frame `i` against frame `i − 1`, by outcome label: outcome
`j` is marked when the previous frame has no outcome with the same label, or
has it with a *different* weight.  Frame 0 (and out-of-range indices) get no
marks — a filmstrip never badges its opening frame. -/
def marks (f : FilmModel) (i : Nat) : Array Bool :=
  match i, f.frames[i]? with
  | 0, _ | _, none => (f.frames[i]?.map
      (fun (_, d) => d.labels.map fun _ => false)).getD #[]
  | i + 1, some (_, cur) =>
    match f.frames[i]? with
    | none => cur.labels.map fun _ => false
    | some (_, prev) =>
      (Array.range cur.labels.size).map fun j =>
        match prev.labels.findIdx? (· == cur.labels[j]!) with
        | none => true
        | some pj => prev.weights[pj]! != cur.weights[j]!

end FilmModel

/-! ## Markov chains -/

/-- A finite Markov chain: `n` states, transitions as an `n × n` exact ℚ
matrix, `matrix[i][j] = P(i → j)` (rows are from-states and should each sum
to 1). -/
structure ChainModel where
  /-- Number of states. -/
  n : Nat
  /-- Row-stochastic transition matrix, `matrix[i][j] = P(i → j)`. -/
  matrix : Array (Array Rat)
  deriving Repr, BEq, Inhabited

namespace ChainModel

/-- Invariant self-check: the matrix is `n × n`, entries are `≥ 0`, and every
row sums to exactly 1.  Non-empty ⇒ extractor bug (the extractor computes the
entries itself); rendered as a warning overlay. -/
def invariantViolations (c : ChainModel) : Array String := Id.run do
  let mut out : Array String := #[]
  if c.matrix.size != c.n then
    out := out.push s!"internal: {c.matrix.size} rows for {c.n} states"
  for i in [0:c.matrix.size] do
    let row := c.matrix[i]!
    if row.size != c.n then
      out := out.push s!"internal: row {i} has {row.size} entries, expected {c.n}"
    for j in [0:row.size] do
      if row[j]! < 0 then
        out := out.push
          s!"internal: entry {ratStr row[j]!} at ({i}, {j}) is negative"
    let s := row.foldl (· + ·) 0
    if s != 1 then
      out := out.push s!"internal: row {i} sums to {ratStr s}, not 1"
  return out

/-- One exact step of the chain: `(step π)[j] = Σ_i π_i · P_{i j}`. -/
def stepDist (c : ChainModel) (π : Array Rat) : Array Rat :=
  (Array.range c.n).map fun j =>
    (Array.range c.n).foldl (init := (0 : Rat)) fun s i =>
      s + π[i]! * (c.matrix[i]!)[j]!

/-- Exact power-iteration filmstrip: `k + 1` frames `π, πP, πP², …, πPᵏ`. -/
def powerFrames (c : ChainModel) (π : Array Rat) (k : Nat) : Array (Array Rat) :=
  (List.range k).foldl (init := #[π]) fun acc _ =>
    acc.push (c.stepDist acc.back!)

/-- The point-mass initial distribution concentrated on state `i`. -/
def pointMass (c : ChainModel) (i : Nat) : Array Rat :=
  (Array.range c.n).map fun j => if j == i then 1 else 0

/-- The uniform initial distribution. -/
def uniformInit (c : ChainModel) : Array Rat :=
  (Array.range c.n).map fun _ => (1 : Rat) / c.n

end ChainModel

/-! ## Exact linear algebra: the stationary distribution -/

/-- Outcome of solving `π P = π`, `Σ π = 1` exactly. -/
inductive StationaryResult where
  /-- A unique stationary distribution. -/
  | unique (π : Array Rat)
  /-- The solution space has dimension `> 1` (reducible chain): DistLens
  reports the situation instead of silently picking a representative. -/
  | nonUnique
  /-- The system is inconsistent — impossible for a genuine row-stochastic
  matrix, so this flags an extraction/model bug. -/
  | inconsistent
  deriving Repr, BEq, DecidableEq, Inhabited

/-- Reduced row-echelon form of an augmented matrix (`rows × (m + 1)`, last
column = right-hand side) by exact Gauss–Jordan elimination.  Returns the
reduced rows.  Pure and deterministic: pivots are the first nonzero entry in
column order. -/
def rref (rows : Array (Array Rat)) (m : Nat) : Array (Array Rat) := Id.run do
  let mut a := rows
  let mut pivotRow := 0
  for col in [0:m] do
    -- Find a pivot in this column at or below `pivotRow`.
    let mut sel : Option Nat := none
    for r in [pivotRow:a.size] do
      if sel.isNone && (a[r]!)[col]! != 0 then
        sel := some r
    match sel with
    | none => pure ()
    | some r =>
      -- Swap into position and normalize.
      let tmp := a[pivotRow]!
      a := a.set! pivotRow a[r]!
      a := a.set! r tmp
      let p := (a[pivotRow]!)[col]!
      a := a.set! pivotRow ((a[pivotRow]!).map (· / p))
      -- Eliminate the column everywhere else.
      for r' in [0:a.size] do
        if r' != pivotRow then
          let f := (a[r']!)[col]!
          if f != 0 then
            let base := a[pivotRow]!
            a := a.set! r' ((a[r']!).zipWith (fun x y => x - f * y) base)
      pivotRow := pivotRow + 1
  return a

/-- Solve the stationary system `π P = π`, `Σ π = 1` by exact Gauss–Jordan
elimination over ℚ.  Equations: for every state `j`, `Σ_i π_i P_{i j} − π_j = 0`,
plus the normalization `Σ_i π_i = 1`.  A unique solution is returned exactly;
a solution space of dimension `≥ 1` is reported as `nonUnique` (reducible
chain); inconsistency (impossible for a genuine stochastic matrix) as
`inconsistent`. -/
def ChainModel.stationary (c : ChainModel) : StationaryResult := Id.run do
  let n := c.n
  if n == 0 then return .inconsistent
  -- Augmented rows: n balance equations + 1 normalization, over n unknowns.
  let mut rows : Array (Array Rat) := #[]
  for j in [0:n] do
    let mut row : Array Rat := #[]
    for i in [0:n] do
      let coeff := (c.matrix[i]!)[j]! - (if i == j then 1 else 0)
      row := row.push coeff
    rows := rows.push (row.push 0)
  rows := rows.push (((Array.range n).map fun _ => (1 : Rat)).push 1)
  let a := rref rows n
  -- Inconsistent row: all-zero coefficients with nonzero RHS.
  for r in a do
    if (Array.range n).all (fun j => r[j]! == 0) && r[n]! != 0 then
      return .inconsistent
  -- Count pivots (rank).
  let mut rank := 0
  for r in a do
    if (Array.range n).any (fun j => r[j]! != 0) then
      rank := rank + 1
  if rank < n then return .nonUnique
  -- Unique: after Gauss–Jordan the first n nonzero rows are the identity.
  let mut π : Array Rat := (Array.range n).map fun _ => 0
  for r in a do
    let mut piv : Option Nat := none
    for j in [0:n] do
      if piv.isNone && r[j]! != 0 then piv := some j
    if let some j := piv then
      π := π.set! j r[n]!
  return .unique π

/-! ## Pure distribution combinators (the extractor's ℚ interpreter) -/

/-- Uniform weights `1/n` over `n` outcomes. -/
def uniformWeights (n : Nat) : Array Rat :=
  (Array.range n).map fun _ => (1 : Rat) / n

/-- Binomial coefficient `n.choose k` as ℚ. -/
def chooseQ (n k : Nat) : Rat := (n.choose k : Nat)

/-- The binomial weight vector: outcome `k ∈ [0, n]` gets
`C(n,k) pᵏ (1−p)ⁿ⁻ᵏ`. -/
def binomialWeights (p : Rat) (n : Nat) : Array Rat :=
  (Array.range (n + 1)).map fun k => chooseQ n k * p ^ k * (1 - p) ^ (n - k)

/-- Pushforward with collision summing: given source weights and, per source
outcome, its image key, sum the weights landing on each key.  Returns the
`(key, weight)` pairs sorted by key ascending — byte-deterministic. -/
def pushforward (weights : Array Rat) (imageKeys : Array Nat) : Array (Nat × Rat) := Id.run do
  let mut acc : Array (Nat × Rat) := #[]
  for i in [0:weights.size] do
    let k := imageKeys[i]!
    let w := weights[i]!
    match acc.findIdx? (·.1 == k) with
    | some j => acc := acc.set! j (k, acc[j]!.2 + w)
    | none => acc := acc.push (k, w)
  return acc.qsort (·.1 < ·.1)

/-- Convolution for `bind`: given source weights and, per source outcome, the
`(key, weight)` rows of its conditional distribution, mix them:
`w(b) = Σ_a p(a) · f_a(b)`.  Sorted by key ascending — byte-deterministic. -/
def convolve (weights : Array Rat) (conditionals : Array (Array (Nat × Rat))) :
    Array (Nat × Rat) := Id.run do
  let mut acc : Array (Nat × Rat) := #[]
  for i in [0:weights.size] do
    let w := weights[i]!
    for (k, wk) in conditionals[i]! do
      match acc.findIdx? (·.1 == k) with
      | some j => acc := acc.set! j (k, acc[j]!.2 + w * wk)
      | none => acc := acc.push (k, w * wk)
  return acc.qsort (·.1 < ·.1)

end DistLens
