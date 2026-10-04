import ExprXRay
import ExprXRayTests.TestUtil

/-! # Tests for the defeq-aware diff

`DefeqStatus` semantics, `checkDefeq` on curated pairs (reducible-only,
default-only, not-defeq, check-failed), the defeq-first re-ranking, the
pinned all-defeq summary wording, purity (no metavariable-state leaks),
and the compare-mode badges. All defeq verdicts below were discovered by
experiment on the v4.32.2 toolchain, re-verified unchanged on v4.34.0, and are pinned as ground truth. -/

namespace ExprXRayTests.DefeqTests

open Lean Elab Term Meta ExprXRay ExprXRayTests ProofWidgets

/-- A `@[reducible]` wrapper around `5`: defeq to `(5 : Nat)` already at
reducible transparency. -/
@[reducible] def redFive : Nat := 5

/-- A non-reducible wrapper around `5`: defeq to `(5 : Nat)` only at
default transparency. -/
def plainFive : Nat := 5

/-! ## Pure `DefeqStatus` properties -/

#guard DefeqStatus.defeqReducible.isDefeq
#guard DefeqStatus.defeqDefault.isDefeq
#guard !DefeqStatus.notDefeq.isDefeq
#guard !DefeqStatus.checkFailed.isDefeq
#guard !DefeqStatus.undetermined.isDefeq

-- pinned annotation suffixes
#guard DefeqStatus.notDefeq.suffix == " (NOT defeq — this blocks rw)"
#guard DefeqStatus.defeqReducible.suffix == " (defeq at reducible transparency — syntactic only)"
#guard DefeqStatus.defeqDefault.suffix == " (defeq at default transparency — syntactic only)"
#guard DefeqStatus.checkFailed.suffix == " (defeq check failed)"
-- mvar-containing sides get honest wording, never a blocking claim
#guard DefeqStatus.undetermined.suffix == " (defeq undetermined — contains metavariables)"

-- pinned badges
#guard DefeqStatus.notDefeq.badge == "≢"
#guard DefeqStatus.defeqReducible.badge == "≈ʳ"
#guard DefeqStatus.defeqDefault.badge == "≈ᵈ"
#guard DefeqStatus.checkFailed.badge == "≟"
#guard DefeqStatus.undetermined.badge == "≟ₘ"

/-! ## Pure re-ranking: non-defeq (and check-failed) before defeq,
kind rank within each group, discovery order within each (group, rank) -/

#guard
  let mk (k : MismatchKind) (d : DefeqStatus) (tag : String) : Mismatch :=
    { kind := k, path := [], lhs := tag, rhs := tag, defeq := d }
  let ranked := rankMismatches #[mk .instanceArgMismatch .defeqDefault "iD",
                                 mk .explicitArgMismatch .notDefeq "eN1",
                                 mk .structural .checkFailed "sF",
                                 mk .instanceArgMismatch .notDefeq "iN",
                                 mk .explicitArgMismatch .notDefeq "eN2",
                                 mk .explicitArgMismatch .defeqReducible "eD"]
  ranked.map (·.lhs) == #["iN", "eN1", "eN2", "sF", "iD", "eD"]

-- allDefeq: empty is NOT "all defeq"; one non-defeq entry poisons it
#guard
  let mk (d : DefeqStatus) : Mismatch := { kind := .structural, path := [], lhs := "l", rhs := "r", defeq := d }
  !allDefeq #[] && allDefeq #[mk .defeqReducible, mk .defeqDefault]
    && !allDefeq #[mk .defeqReducible, mk .notDefeq]
    && !allDefeq #[mk .defeqReducible, mk .checkFailed]

-- the all-defeq summary wording is pinned exactly (singular and plural)
#guard allDefeqSummary 1 ==
  "1 mismatch, all definitionally equal — the discrepancy is syntactic only (defeq-transparent tactics like exact will succeed; syntactic tactics like rw may still fail)"
#guard allDefeqSummary 3 ==
  "3 mismatches, all definitionally equal — the discrepancy is syntactic only (defeq-transparent tactics like exact will succeed; syntactic tactics like rw may still fail)"

-- diffSummary switches to the all-defeq headline exactly when all are defeq
#guard
  let mk (d : DefeqStatus) : Mismatch := { kind := .structural, path := [], lhs := "l", rhs := "r", defeq := d }
  diffSummary #[mk .defeqDefault] == some (allDefeqSummary 1)
    && diffSummary #[mk .notDefeq] == some ((mk .notDefeq).describe)
    && diffSummary #[] == none

/-! ## checkDefeq on curated pairs -/

#eval show TermElabM Unit from do
  -- reducible-transparency defeq: @[reducible] def vs the bare numeral
  assertEq "checkDefeq: reducible wrapper"
    (← checkDefeq (← elabT (← `(redFive))) (← elabT (← `((5 : Nat))))) .defeqReducible
  -- eta-expanded head vs the bare head: defeq at reducible (eta is structural)
  assertEq "checkDefeq: eta"
    (← checkDefeq (← elabT (← `(fun (n : Nat) => Nat.succ n))) (← elabT (← `(Nat.succ))))
    .defeqReducible
  -- default-only defeq: non-reducible def must be unfolded
  assertEq "checkDefeq: plain def"
    (← checkDefeq (← elabT (← `(plainFive))) (← elabT (← `((5 : Nat))))) .defeqDefault
  -- not defeq at any transparency
  assertEq "checkDefeq: distinct values"
    (← checkDefeq (← elabT (← `(Nat.zero))) (← elabT (← `(Nat.succ Nat.zero)))) .notDefeq
  -- the motivating instances: NOT defeq (Classical.propDecidable is opaque)
  assertEq "checkDefeq: ite instances not defeq"
    (← checkDefeq (← elabT (← `(instDecidableEqNat 2 2)))
                  (← elabT (← `(Classical.propDecidable (2 = 2))))) .notDefeq
  -- two instances that ARE defeq, but only by unfolding the instance def
  assertEq "checkDefeq: decEq instances defeq at default"
    (← checkDefeq (← elabT (← `(instDecidableEqNat 1 1)))
                  (← elabT (← `(Nat.decEq 1 1)))) .defeqDefault
  -- REGRESSION (bughunt2): a side containing an unassigned mvar is
  -- `undetermined` — under `withNewMCtxDepth` isDefEq would answer
  -- `false` even though the pair is trivially unifiable, and the
  -- mismatch used to be misreported as "NOT defeq — this blocks rw"
  let m ← mkFreshExprMVar (some (mkConst ``Nat))
  assertEq "checkDefeq: mvar side undetermined"
    (← checkDefeq m (← elabT (← `((2 : Nat))))) .undetermined
  assertFalse "checkDefeq: mvar probe leaked no assignment" (← m.mvarId!.isAssigned)

/-! ## Reducible-only defeq pair through the full diff -/

#eval show TermElabM Unit from do
  let ms ← diffT (← `(Nat.succ redFive)) (← `(Nat.succ (5 : Nat)))
  assertTrue "red diff: nonempty" !ms.isEmpty
  assertTrue "red diff: all defeq" (allDefeq ms)
  assertEq "red diff: arg mismatch annotated reducible"
    (ms.filter (·.kind == .explicitArgMismatch) |>.map (·.defeq))
    #[.defeqReducible]
  assertEq "red diff: all-defeq headline"
    (diffSummary ms) (some (allDefeqSummary ms.size))

/-! ## Default-only defeq pair through the full diff -/

#eval show TermElabM Unit from do
  -- plainFive (a const) vs the OfNat application: one structural mismatch,
  -- defeq only after unfolding the non-reducible def
  let ms ← diffT (← `(plainFive)) (← `((5 : Nat)))
  assertEq "plain diff: kinds" (ms.map (·.kind)) #[.structural]
  assertEq "plain diff: annotated default" ms[0]!.defeq .defeqDefault
  assertEq "plain diff: describe"
    ms[0]!.describe "structural difference: plainFive vs 5 (defeq at default transparency — syntactic only)"
  assertEq "plain diff: all-defeq headline" (diffSummary ms) (some (allDefeqSummary 1))

#eval show TermElabM Unit from do
  -- `id` is NOT reducible on this toolchain: unwrapping it needs default
  -- transparency (pinned toolchain fact)
  let ms ← diffT (← `(@id Nat 5)) (← `((5 : Nat)))
  assertEq "id diff: one application-shape mismatch"
    (ms.map (·.kind)) #[.structural]
  assertEq "id diff: site" ms[0]!.site "application shape"
  assertEq "id diff: annotated default" ms[0]!.defeq .defeqDefault

/-! ## The motivating notDefeq instance pair stays ranked first -/

#eval show TermElabM Unit from do
  let ms ← diffT
    (← `(@ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0))
    (← `(@ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0))
  assertEq "ite notDefeq: one mismatch" ms.size 1
  assertEq "ite notDefeq: annotation" ms[0]!.defeq .notDefeq
  assertFalse "ite notDefeq: not all defeq" (allDefeq ms)
  assertContains "ite notDefeq: summary carries the blocking note"
    (diffSummary ms).get! "(NOT defeq — this blocks rw)"

/-! ## An all-defeq instance mismatch gets the all-defeq headline -/

#eval show TermElabM Unit from do
  let ms ← diffT
    (← `(@ite Nat (1 = 1) (instDecidableEqNat 1 1) Nat.zero Nat.zero))
    (← `(@ite Nat (1 = 1) (Nat.decEq 1 1) Nat.zero Nat.zero))
  assertEq "inst defeq: one mismatch" ms.size 1
  assertEq "inst defeq: kind" ms[0]!.kind .instanceArgMismatch
  assertEq "inst defeq: annotation" ms[0]!.defeq .defeqDefault
  assertTrue "inst defeq: all defeq" (allDefeq ms)
  assertEq "inst defeq: headline" (diffSummary ms) (some (allDefeqSummary 1))

/-! ## The reordering case: a notDefeq explicit argument now outranks a
defeq instance argument -/

#eval show TermElabM Unit from do
  let ms ← diffT
    (← `(@ite Nat (1 = 1) (instDecidableEqNat 1 1) Nat.zero Nat.zero))
    (← `(@ite Nat (1 = 1) (Nat.decEq 1 1) (Nat.succ Nat.zero) Nat.zero))
  assertTrue "reorder: several mismatches" (ms.size > 1)
  -- the headline is the explicit argument that actually blocks rw ...
  assertEq "reorder: explicit notDefeq wins" ms[0]!.kind .explicitArgMismatch
  assertEq "reorder: headline annotation" ms[0]!.defeq .notDefeq
  assertContains "reorder: headline text" ms[0]!.describe "explicit argument #2 of ite"
  -- ... while the defeq instance mismatch is still collected, but demoted
  let idxInst := ms.findIdx? (·.kind == .instanceArgMismatch)
  assertTrue "reorder: instance mismatch still collected" idxInst.isSome
  assertEq "reorder: instance annotated defeq" ms[idxInst.get!]!.defeq .defeqDefault
  assertTrue "reorder: instance no longer first" (idxInst.get! > 0)
  -- every non-defeq mismatch ranks before every defeq one
  let firstDefeq := ms.findIdx? (·.defeq.isDefeq)
  let lastBlocking := ms.size - 1 - (ms.reverse.findIdx? (!·.defeq.isDefeq)).get!
  assertTrue "reorder: blocking group strictly first" (lastBlocking < firstDefeq.get!)

/-! ## Universe mismatches get level-aware defeq (isLevelDefEq normalizes) -/

#eval show TermElabM Unit from do
  -- Sort (max 1 2) vs Sort 2: syntactically different levels, defeq
  let ms ← diffExprs (Expr.sort (Level.max 1 2)) (Expr.sort 2)
  assertEq "level defeq: kinds" (ms.map (·.kind)) #[.differentUniverse]
  assertEq "level defeq: annotation" ms[0]!.defeq .defeqReducible
  assertTrue "level defeq: all defeq" (allDefeq ms)
  -- PUnit.{1} vs PUnit.{2}: genuinely different universes, not defeq
  let ms ← diffT (← `(@PUnit.{1})) (← `(@PUnit.{2}))
  assertEq "level notDefeq: annotation" ms[0]!.defeq .notDefeq

/-! ## checkFailed: ill-scoped subterms make the check throw, not crash -/

#eval show TermElabM Unit from do
  -- a projection of an unknown fvar: isDefEq needs to type it and throws
  let bogus := Expr.proj ``Prod 0 (Expr.fvar ⟨`bogus⟩)
  let five ← elabT (← `((5 : Nat)))
  assertEq "checkFailed: direct" (← checkDefeq bogus five) .checkFailed
  -- through the full diff: recorded as structural + checkFailed
  let ms ← diffExprs bogus five
  assertEq "checkFailed: kinds" (ms.map (·.kind)) #[.structural]
  assertEq "checkFailed: annotation" ms[0]!.defeq .checkFailed
  assertFalse "checkFailed: not all defeq" (allDefeq ms)
  assertContains "checkFailed: describe" ms[0]!.describe "(defeq check failed)"

/-! ## Purity: no metavariable state escapes the defeq checks -/

#eval show TermElabM Unit from do
  -- running the same diff twice yields byte-identical results
  let a ← elabT (← `(@ite Nat (1 = 1) (instDecidableEqNat 1 1) Nat.zero Nat.zero))
  let b ← elabT (← `(@ite Nat (1 = 1) (Nat.decEq 1 1) (Nat.succ Nat.zero) Nat.zero))
  let ms₁ ← diffExprs a b
  let ms₂ ← diffExprs a b
  assertEq "purity: identical reruns" ms₁ ms₂

#eval show TermElabM Unit from do
  -- a pair containing an unassigned mvar still diffs, is NOT certified
  -- defeq (nothing is: the status is `undetermined`), and the mvar
  -- stays unassigned
  let m ← mkFreshExprMVar (some (mkConst ``Nat))
  let a := mkApp (mkConst ``Nat.succ) m
  let b := mkApp (mkConst ``Nat.succ) (mkConst ``Nat.zero)
  let ms ← diffExprs a b
  assertTrue "purity mvar: mismatch found"
    (ms.any fun mm => mm.kind == .explicitArgMismatch && mm.path == [1])
  assertTrue "purity mvar: nothing certified defeq" (ms.all (!·.defeq.isDefeq))
  assertTrue "purity mvar: annotated undetermined" (ms.all (·.defeq == .undetermined))
  assertFalse "purity mvar: mvar not assigned" (← m.mvarId!.isAssigned)
  assertEq "purity mvar: identical rerun" ms (← diffExprs a b)

#eval show TermElabM Unit from do
  -- checkDefeq alone leaves an assignable mvar unassigned — it reports
  -- `undetermined` without ever consulting isDefEq
  let m ← mkFreshExprMVar (some (mkConst ``Nat))
  assertEq "purity check: mvar vs const" (← checkDefeq m (mkConst ``Nat.zero)) .undetermined
  assertFalse "purity check: no assignment leaked" (← m.mvarId!.isAssigned)

/-! ## Compare-mode rendering: badges and the all-defeq banner -/

#eval show TermElabM Unit from do
  -- blocking pair: red ≢ badge, no defeq badge, no banner
  let a ← elabT (← `(@ite Nat (2 = 2) (instDecidableEqNat 2 2) 1 0))
  let b ← elabT (← `(@ite Nat (2 = 2) (Classical.propDecidable (2 = 2)) 1 0))
  let out := Html.toStringCompact (renderCompare (← analyzeExpr a) (← analyzeExpr b) (← diffExprs a b))
  assertContains "render defeq: ≢ badge" out "≢"
  assertNotContains "render defeq: no ≈ᵈ badge" out "≈ᵈ"
  assertContains "render defeq: annotation in summary" out "(NOT defeq — this blocks rw)"
  assertNotContains "render defeq: no banner" out "all definitionally equal"

#eval show TermElabM Unit from do
  -- all-defeq pair: green ≈ᵈ badge plus the pinned banner
  let a ← elabT (← `(@ite Nat (1 = 1) (instDecidableEqNat 1 1) Nat.zero Nat.zero))
  let b ← elabT (← `(@ite Nat (1 = 1) (Nat.decEq 1 1) Nat.zero Nat.zero))
  let out := Html.toStringCompact (renderCompare (← analyzeExpr a) (← analyzeExpr b) (← diffExprs a b))
  assertContains "render banner: ≈ᵈ badge" out "≈ᵈ"
  assertContains "render banner: green badge color" out "var(--vscode-charts-green, green)"
  assertContains "render banner: pinned wording" out (allDefeqSummary 1)
  -- an empty diff shows neither badges nor banner
  let na ← analyzeExpr a
  let empty := Html.toStringCompact (renderCompare na na #[])
  assertNotContains "render banner: none on empty (badge)" empty "≢"
  assertNotContains "render banner: none on empty (banner)" empty "all definitionally equal"

/-! ## Text mode pins everything (`#guard_msgs`) -/

/--
info: 2 mismatches, all definitionally equal — the discrepancy is syntactic only (defeq-transparent tactics like exact will succeed; syntactic tactics like rw may still fail)
explicit argument #1 of Nat.succ differs: redFive vs 5 (defeq at reducible transparency — syntactic only)
structural difference: redFive vs 5 (defeq at reducible transparency — syntactic only)
-/
#guard_msgs in
#xray_diff (text := true) Nat.succ redFive, Nat.succ (5 : Nat)

/--
info: 1 mismatch, all definitionally equal — the discrepancy is syntactic only (defeq-transparent tactics like exact will succeed; syntactic tactics like rw may still fail)
instance argument #3 of ite differs: instDecidableEqNat 1 1 vs Nat.decEq 1 1 (defeq at default transparency — syntactic only)
-/
#guard_msgs in
#xray_diff (text := true) @ite Nat (1 = 1) (instDecidableEqNat 1 1) Nat.zero Nat.zero,
                          @ite Nat (1 = 1) (Nat.decEq 1 1) Nat.zero Nat.zero

/--
info: explicit argument #2 of ite differs: Nat.zero vs Nat.zero.succ (NOT defeq — this blocks rw)
structural difference: Nat.zero vs Nat.zero.succ (NOT defeq — this blocks rw)
instance argument #3 of ite differs: instDecidableEqNat 1 1 vs Nat.decEq 1 1 (defeq at default transparency — syntactic only)
-/
#guard_msgs in
#xray_diff (text := true) @ite Nat (1 = 1) (instDecidableEqNat 1 1) Nat.zero Nat.zero,
                          @ite Nat (1 = 1) (Nat.decEq 1 1) (Nat.succ Nat.zero) Nat.zero

/-! ## Metavariable-containing sides: undetermined, never "blocks rw"

REGRESSION (bughunt2): elaborating `id` alone leaves fresh universe and
type metavariables on each side; the two sides are trivially unifiable,
yet the diff used to report three "NOT defeq — this blocks rw"
mismatches for the *identical* user input. -/

-- pinned wording for expression metavariables (their `?m.N` display
-- names are stable per command, unlike raw universe-mvar names)
/--
info: structural difference: ?m.1 vs 2 (defeq undetermined — contains metavariables)
-/
#guard_msgs in
#xray_diff (text := true) (_ : Nat), (2 : Nat)

/--
info: structural difference: ?m.1 vs ?m.2 (defeq undetermined — contains metavariables)
-/
#guard_msgs in
#xray_diff (text := true) (_ : Nat), (_ : Nat)

#eval show TermElabM Unit from do
  -- the full `id, id` shape, robust against metavariable numbering:
  -- three mismatches (fresh universe mvars, fresh implicit-type mvars,
  -- and their structural refinement), every one `undetermined`, none
  -- claiming to block rw
  let e₁ ← Term.elabTerm (← `(id)) none
  let e₂ ← Term.elabTerm (← `(id)) none
  Term.synthesizeSyntheticMVarsNoPostponing
  let ms ← diffExprs e₁ e₂
  assertEq "id id: kinds" (ms.map (·.kind))
    #[.differentUniverse, .implicitArgMismatch, .structural]
  assertTrue "id id: every entry undetermined" (ms.all (·.defeq == .undetermined))
  assertFalse "id id: not certified defeq either" (allDefeq ms)
  for m in ms do
    assertNotContains "id id: no blocking verdict" m.describe "NOT defeq"
  assertContains "id id: plural verb for universe levels"
    ms[0]!.describe "universe levels of id differ:"

end ExprXRayTests.DefeqTests
