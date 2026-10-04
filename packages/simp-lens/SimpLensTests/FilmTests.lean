import SimpLensTests.Helpers

/-!
# Film tests — pure `#guard` tests for filmstrip data structures

These exercise the pure logic (`mkFrames`, `Film.chainViolations`,
`TraceStep.principal`, `mergeUsed`, `stepResultExpr?`, ...) on synthetic
data, independent of the elaborator.
-/

namespace SimpLensTests.Film

open Lean Meta Simp SimpLens

/-! ## Phase labels -/

#guard Phase.pre.label == "pre"
#guard Phase.post.label == "post"
#guard Phase.dpre.label == "dpre"
#guard Phase.dpost.label == "dpost"

/-! ## Synthetic steps -/

/-- Synthetic step: `a --foo--> b` at depth 0 (post). -/
def stA : TraceStep :=
  { origins := #[.decl `foo], before := mkConst `a, after := mkConst `b,
    phase := .post, depth := 0 }

/-- Synthetic step: `b --side,bar--> c` at depth 0 (pre), with a
side-condition origin first. -/
def stB : TraceStep :=
  { origins := #[.decl `side, .decl `bar], before := mkConst `b, after := mkConst `c,
    phase := .pre, depth := 0 }

/-- Synthetic step at discharge depth 2 (must not become a frame). -/
def stDeep : TraceStep :=
  { origins := #[.decl `deep], before := mkConst `x, after := mkConst `y,
    phase := .post, depth := 2 }

/-! ## principal: last origin wins; empty origins fall back -/

#guard stA.principal == .decl `foo
#guard stB.principal == .decl `bar
#guard (({ stA with origins := #[] } : TraceStep)).principal == .other `SimpLens.unknown

/-! ## mkFrames: filters depth ≠ 0 and numbers 0.. in order -/

#guard (mkFrames #[stA, stDeep, stB]).size == 2
#guard (mkFrames #[stA, stDeep, stB]).map (·.index) == #[0, 1]
#guard (mkFrames #[stA, stDeep, stB])[0]!.step.before == mkConst `a
#guard (mkFrames #[stA, stDeep, stB])[1]!.step.after == mkConst `c
#guard (mkFrames #[stDeep]).size == 0
#guard (mkFrames #[]).size == 0

/-! ## step-result extraction -/

#guard stepResultExpr? (.done { expr := mkConst `a }) == some (mkConst `a)
#guard stepResultExpr? (.visit { expr := mkConst `b }) == some (mkConst `b)
#guard stepResultExpr? (.continue (some { expr := mkConst `c })) == some (mkConst `c)
#guard stepResultExpr? (.continue none) == none
#guard dstepResultExpr? (.done (mkConst `a)) == some (mkConst `a)
#guard dstepResultExpr? (.visit (mkConst `b)) == some (mkConst `b)
#guard dstepResultExpr? (.continue (some (mkConst `c))) == some (mkConst `c)
#guard dstepResultExpr? (.continue none) == none

/-! ## mergeUsed: order-preserving, idempotent union -/

/-- `{foo, bar}` in that insertion order. -/
def usedFooBar : UsedSimps := (({} : UsedSimps).insert (.decl `foo)).insert (.decl `bar)
/-- `{bar, baz}` in that insertion order. -/
def usedBarBaz : UsedSimps := (({} : UsedSimps).insert (.decl `bar)).insert (.decl `baz)

#guard (mergeUsed usedFooBar usedBarBaz).toArray.map (·.key) == #[`foo, `bar, `baz]
#guard (mergeUsed usedBarBaz usedFooBar).toArray.map (·.key) == #[`bar, `baz, `foo]
#guard (mergeUsed {} usedFooBar).toArray.map (·.key) == #[`foo, `bar]
#guard (mergeUsed usedFooBar {}).toArray.map (·.key) == #[`foo, `bar]
#guard (mergeUsed usedFooBar usedFooBar).toArray.map (·.key) == #[`foo, `bar]
#guard (mergeUsed usedFooBar usedBarBaz).size == 3

/-! ## chain violations on synthetic films -/

/-- A consistent synthetic film. -/
def goodFilm : Film :=
  { frames := mkFrames #[stA, stB],
    allSteps := #[stA, stB],
    usedTheorems := (({} : UsedSimps).insert (.decl `foo)).insert (.decl `bar) }

#guard goodFilm.chainConsistent
#guard goodFilm.chainViolations == []
#guard goodFilm.length == 2

/-- Violation: a frame whose before/after are equal. -/
def noopFilm : Film :=
  { goodFilm with frames := mkFrames #[{ stA with after := stA.before }] }

#guard !noopFilm.chainConsistent
#guard noopFilm.chainViolations.length == 1

/-- Violation: frame with no origins (2 violations: empty origins + principal
fallback not in usedTheorems). -/
def noOriginFilm : Film :=
  { goodFilm with frames := mkFrames #[{ stA with origins := #[] }] }

#guard !noOriginFilm.chainConsistent
#guard noOriginFilm.chainViolations.length == 2

/-- Violation: principal origin not recorded in usedTheorems. -/
def missingUsedFilm : Film :=
  { goodFilm with usedTheorems := ({} : UsedSimps).insert (.decl `foo) }

#guard !missingUsedFilm.chainConsistent
#guard missingUsedFilm.chainViolations.length == 1

/-- Violation: indices out of order (frames tampered with by hand). -/
def badIndexFilm : Film :=
  { goodFilm with frames := #[{ index := 1, step := stA }, { index := 0, step := stB }] }

#guard !badIndexFilm.chainConsistent
#guard badIndexFilm.chainViolations.length == 2

/-- Violation: a depth > 0 step smuggled into the frames. -/
def deepFrameFilm : Film :=
  { goodFilm with
    frames := #[{ index := 0, step := { stDeep with origins := #[.decl `foo] } }] }

#guard !deepFrameFilm.chainConsistent
#guard deepFrameFilm.chainViolations.length == 1

/-! ## TraceResult.mainSteps -/

/-- Synthetic trace result mixing depths. -/
def mixedResult : SimpLens.TraceResult :=
  { goal? := none, steps := #[stA, stDeep, stB], usedTheorems := goodFilm.usedTheorems,
    diag := {}, target := mkConst `a, progress := true }

#guard mixedResult.mainSteps.size == 2
#guard (Film.ofTrace mixedResult).length == 2
#guard (Film.ofTrace mixedResult).allSteps.size == 3
#guard (Film.ofTrace mixedResult).chainConsistent

/-! ## OriginClass pure helpers -/

#guard (OriginClass.global `foo).representable
#guard (OriginClass.simproc `reduceIte).representable
#guard (OriginClass.localHyp `h).representable
#guard !(OriginClass.unrepresentable `x).representable
#guard (OriginClass.global `Nat.add_zero).label == "global lemma Nat.add_zero"
#guard (OriginClass.localHyp `h).label == "local hypothesis h"
#guard (OriginClass.simproc `reduceIte).label == "simproc reduceIte"
#guard (OriginClass.unrepresentable `k).label == "unrepresentable (k)"

/-! ## usedDeclNames -/

#guard usedDeclNames usedFooBar == #[`foo, `bar]
#guard usedDeclNames (usedFooBar.insert (.other `weird)) == #[`foo, `bar]
#guard usedDeclNames {} == #[]

/-! ## definitional-only detection (finding: "0 rewrites" on beta-only
progress) — a location that changed with an empty film is definitional-only;
a lemma-driven or unchanged location is not -/

#guard ({ loc := .target, film := { frames := #[], allSteps := #[], usedTheorems := {} },
          closedGoal := false, changed := true } : LocFilm).definitionalOnly
#guard !({ loc := .target, film := { frames := #[], allSteps := #[], usedTheorems := {} },
           closedGoal := false, changed := false } : LocFilm).definitionalOnly
#guard !({ loc := .target, film := goodFilm,
           closedGoal := false, changed := true } : LocFilm).definitionalOnly

-- the empty-film note is honest about the cause
#guard emptyFilmNote true ==
  "No lemma-driven rewrites — the change was purely definitional (beta/zeta/eta/proj reductions, which have no lemma origin to record)."
#guard emptyFilmNote false == "No rewrite steps were recorded."

/-! ## render frame cap (finding: filmstrip rendering of a huge film can blow
the heartbeat budget) — `framesBlockHtml` renders at most `maxRenderedFrames`
frames and summarizes the tail in a note -/

/-- All text leaves of an `Html` tree, in document order. -/
partial def htmlTexts : ProofWidgets.Html → Array String
  | .text s => #[s]
  | .element _ _ children => children.flatMap htmlTexts
  | .component _ _ _ children => children.flatMap htmlTexts

open Lean Elab in
run_cmd Command.liftTermElabM do
  -- synthetic film with maxRenderedFrames + 5 frames
  let step : TraceStep :=
    { origins := #[.decl `Nat.add_zero], before := mkNatLit 1, after := mkNatLit 2,
      phase := .post, depth := 0 }
  let n := maxRenderedFrames + 5
  let frames := (Array.range n).map fun i => ({ index := i, step } : Frame)
  let film : Film := { frames, allSteps := frames.map (·.step), usedTheorems := {} }
  let texts := htmlTexts (← framesBlockHtml film true)
  -- the last rendered frame is number maxRenderedFrames; the tail is a note
  unless texts.contains s!"{maxRenderedFrames}." do
    throwError "frame {maxRenderedFrames} not rendered; texts: {texts}"
  if texts.contains s!"{maxRenderedFrames + 1}." then
    throwError "frame {maxRenderedFrames + 1} rendered beyond the cap"
  unless texts.contains
      s!"(+5 more rewrites not rendered — filmstrip capped at {maxRenderedFrames} frames)" do
    throwError "truncation note missing; texts: {texts}"
  -- a small film renders in full, no note
  let small : Film := { film with frames := frames.take 3, allSteps := #[] }
  let smallTexts := htmlTexts (← framesBlockHtml small true)
  unless smallTexts.contains "3." do
    throwError "small film frame 3 not rendered"
  if smallTexts.any (·.startsWith "(+") then
    throwError "small film unexpectedly truncated"

open Lean Elab in
run_cmd Command.liftTermElabM do
  -- the definitional-only empty-film note reaches the rendered Html
  let film : Film := { frames := #[], allSteps := #[], usedTheorems := {} }
  let texts := htmlTexts (← framesBlockHtml film true)
  unless texts.contains (emptyFilmNote true) do
    throwError "definitional-only note missing; texts: {texts}"
  let texts ← pure (htmlTexts (← framesBlockHtml film false))
  unless texts.contains (emptyFilmNote false) do
    throwError "generic empty note missing; texts: {texts}"

/-! ## exclusion-preview rendering: each status renders a distinct marker
naming the cause, and `-previews` renders the disabled note -/

open Lean Elab in
run_cmd Command.liftTermElabM do
  let mkOutcome (status : PreviewStatus) (essential : Bool) : ExclusionOutcome :=
    { origin := .decl `Nat.add_zero, landingGoal? := none, essential, status }
  let report : ExclusionReport :=
    { outcomes := #[mkOutcome .ok true, mkOutcome .ok false,
                    mkOutcome .timedOut true, mkOutcome .errored true],
      truncated := false }
  let texts := htmlTexts (← exclusionsHtml report)
  for marker in [ "● essential ", "○ redundant ", "⏱ timed out ", "⚠ errored " ] do
    unless texts.contains marker do
      throwError "marker '{marker}' missing from previews rendering; texts: {texts}"
  unless texts.any (fun t =>
      t.startsWith "preview unavailable — re-run timed out") do
    throwError "timed-out explanation missing; texts: {texts}"
  unless texts.contains "preview unavailable — re-run errored" do
    throwError "errored explanation missing; texts: {texts}"
  -- disabled report (simp_lens -previews)
  let disabledTexts := htmlTexts (← exclusionsHtml { outcomes := #[], truncated := false,
                                                     disabled := true })
  unless disabledTexts.contains "Exclusion previews disabled (-previews)." do
    throwError "disabled note missing; texts: {disabledTexts}"

-- a non-ok status always counts as errored (the panel and callers treat any
-- non-ok preview as "no landing available")
#guard (({ origin := .decl `x, landingGoal? := none, essential := true,
           status := .timedOut } : ExclusionOutcome)).errored
#guard (({ origin := .decl `x, landingGoal? := none, essential := true,
           status := .errored } : ExclusionOutcome)).errored
#guard !(({ origin := .decl `x, landingGoal? := none, essential := false,
            status := .ok } : ExclusionOutcome)).errored

end SimpLensTests.Film

/-! ## exclusion cap constant -/
#guard SimpLens.maxExclusions == 12

/-! ## render cap constant is nontrivial -/
#guard SimpLens.maxRenderedFrames == 100

/-! ## preview budget: monotone in the traced cost, with a fixed floor -/
#guard SimpLens.previewBudgetOf 0 == 1000000
#guard SimpLens.previewBudgetOf 500000 == 2000000
#guard SimpLens.previewBudgetOf 1 > SimpLens.previewBudgetOf 0
