import SimpLens.Trace

/-!
# SimpLens.Film — the ordered filmstrip of rewrite frames

A `Film` is the ordered sequence of depth-0 rewrite steps of a traced `simp`
run, each wrapped in a numbered `Frame`, together with programmatically
checkable consistency invariants.

Honest scope note: each frame records the rewritten **subterm** before/after
(always available from the tracer). Whole-goal intermediate states are *not*
reconstructed — `simp` performs rewrites bottom-up inside congruence closures,
so the whole goal does not exist as a term at the time an inner rewrite fires.
This limitation is documented in the README.
-/

namespace SimpLens

open Lean Meta Simp

/-- A numbered frame of the filmstrip: one depth-0 rewrite of a traced run. -/
structure Frame where
  /-- 0-based position of the frame in the filmstrip. -/
  index : Nat
  /-- The traced step. -/
  step : TraceStep
  deriving Inhabited

/-- The filmstrip: ordered frames plus the underlying trace data. -/
structure Film where
  /-- The numbered depth-0 frames, in firing order. -/
  frames : Array Frame
  /-- All traced steps including side-condition (depth > 0) work. -/
  allSteps : Array TraceStep
  /-- Used-theorem set of the run (identical to plain `simp`'s). -/
  usedTheorems : UsedSimps
  deriving Inhabited

/-- Number the depth-0 steps of `steps` into frames. -/
def mkFrames (steps : Array TraceStep) : Array Frame :=
  (steps.filter (·.depth == 0)).mapIdx fun i s => { index := i, step := s }

/-- Build a `Film` from a `TraceResult`. -/
def Film.ofTrace (r : TraceResult) : Film :=
  { frames := mkFrames r.steps, allSteps := r.steps, usedTheorems := r.usedTheorems }

/-- One filmstrip section of a multi-location run: the film of a single
location, plus the location tag and whether this location closed the goal. -/
structure LocFilm where
  /-- The location this section belongs to. -/
  loc : LocTag
  /-- The filmstrip of this location's steps (frames renumbered from 0). -/
  film : Film
  /-- Whether simplifying this location closed the goal. -/
  closedGoal : Bool
  /-- Whether this location's expression changed. Can be `true` with an empty
  film: `simp` also makes progress via *definitional* reductions (beta, zeta,
  eta, proj) that have no lemma/simproc origin and hence record no step. -/
  changed : Bool
  deriving Inhabited

/-- `true` if this location changed but no lemma-driven rewrite was recorded:
the change was purely definitional (beta/zeta/eta/proj reductions, which have
no origin the tracer could attribute). -/
def LocFilm.definitionalOnly (lf : LocFilm) : Bool :=
  lf.changed && lf.film.frames.isEmpty

/-- Build one filmstrip section per processed location of a traced
`simp ... at ...` run, in processing order. Each section's frames are its
location's depth-0 steps, renumbered from 0; `usedTheorems` is the whole run's
set (frame principals of every location are recorded in it). -/
def GoalTraceResult.films (r : GoalTraceResult) : Array LocFilm :=
  r.locs.map fun l =>
    { loc := l.loc
      film := { frames := mkFrames l.steps, allSteps := l.steps, usedTheorems := r.usedTheorems }
      closedGoal := l.closedGoal
      changed := l.changed }

/-- Number of frames in the filmstrip. -/
def Film.length (f : Film) : Nat := f.frames.size

/--
Pure (syntactic) part of the chain-consistency invariant. Returns a list of
human-readable violations; the film is consistent iff the list is empty.

Checked properties:
1. frame indices are exactly `0, 1, 2, ...` in order;
2. every frame actually rewrote something (`before ≠ after` syntactically);
3. every frame has at least one recorded origin;
4. every frame is at discharge depth 0;
5. the principal origin of every frame occurs in the run's `usedTheorems`
   (depth-0 rewrites are never rolled back by `simp`).
-/
def Film.chainViolations (f : Film) : List String := Id.run do
  let mut errs : List String := []
  for h : i in [0:f.frames.size] do
    let fr := f.frames[i]
    if fr.index != i then
      errs := errs ++ [s!"frame at position {i} has index {fr.index}"]
    if fr.step.before == fr.step.after then
      errs := errs ++ [s!"frame {i}: before and after are syntactically equal"]
    if fr.step.origins.isEmpty then
      errs := errs ++ [s!"frame {i}: no origins recorded"]
    if fr.step.depth != 0 then
      errs := errs ++ [s!"frame {i}: depth {fr.step.depth} ≠ 0"]
    unless f.usedTheorems.contains fr.step.principal do
      errs := errs ++ [s!"frame {i}: principal origin {fr.step.principal.key} not in usedTheorems"]
  return errs

/-- `true` iff the pure chain-consistency invariant holds. -/
def Film.chainConsistent (f : Film) : Bool :=
  f.chainViolations.isEmpty

/--
Semantic part of the chain-consistency invariant, requiring `MetaM`: for every
frame, `before` and `after` must have definitionally equal types (they are the
two sides of an `Eq`/`Iff` rewrite, so this must hold for any correct trace).
Returns violations as strings.
-/
def Film.typeViolations (f : Film) : MetaM (List String) := do
  let mut errs : List String := []
  for fr in f.frames do
    let tb ← inferType fr.step.before
    let ta ← inferType fr.step.after
    unless (← withNewMCtxDepth <| isDefEq tb ta) do
      errs := errs ++ [s!"frame {fr.index}: type of before ({← ppExpr tb}) ≠ type of after ({← ppExpr ta})"]
  return errs

end SimpLens
