import IntervalInspectorTests.Helpers
import Mathlib.Data.Real.Basic

/-! # Render tests

Contains-assertions on the deterministic serialization (`htmlToDebugString`) of the
SVG output: glyph convention (filled = closed, hollow = open), stacked rows for
subset shapes, mismatch shading presence/absence, unknown-order captions — plus unit
tests of the provable-coverage semantics feeding the mismatch computation.
-/

namespace IntervalInspectorTests

open IntervalInspector

/-- Render a shape (building graph and layout from the given facts), with
everything-available instances (`InstAvail.all`). -/
private def rendered (s : Shape) (facts : List OrderFact := []) : String :=
  let g := s.orderGraph facts.toArray
  htmlToDebugString (renderShapeSvg s g (computeLayout g))

/-- Render a shape under a restricted `InstAvail` (discrete / partial types). -/
private def renderedI (s : Shape) (inst : InstAvail) (facts : List OrderFact := []) :
    String :=
  let g := s.orderGraph facts.toArray
  htmlToDebugString (renderShapeSvg s g (computeLayout g) inst)

/-! ## Glyph convention: filled circle = closed endpoint, hollow = open -/

-- Themed color strings (VS Code CSS variables with hex fallbacks), as emitted.
private def blueC := "var(--vscode-charts-blue, #3b82f6)"
private def greenC := "var(--vscode-charts-green, #10b981)"
private def bgC := "var(--vscode-editor-background, #ffffff)"

-- Icc [1,2]: both endpoints filled (fill = bar color); no hollow circle anywhere.
private def sIcc := rendered (.term (dev .Icc "1" 1 "2" 2))
#guard strContains sIcc s!"<circle cx=\"40\" cy=\"26\" r=\"5\" fill=\"{blueC}\""
#guard strContains sIcc s!"<circle cx=\"520\" cy=\"26\" r=\"5\" fill=\"{blueC}\""
#guard !strContains sIcc s!"fill=\"{bgC}\""

-- Ioo (1,2): both hollow (background fill, colored stroke); no filled circle.
private def sIoo := rendered (.term (dev .Ioo "1" 1 "2" 2))
#guard strContains sIoo s!"<circle cx=\"40\" cy=\"26\" r=\"5\" fill=\"{bgC}\" stroke=\"{blueC}\""
#guard strContains sIoo s!"<circle cx=\"520\" cy=\"26\" r=\"5\" fill=\"{bgC}\" stroke=\"{blueC}\""
#guard !strContains sIoo s!"<circle cx=\"40\" cy=\"26\" r=\"5\" fill=\"{blueC}\""

-- Ioc (1,2]: hollow left, filled right.
private def sIoc := rendered (.term (dev .Ioc "1" 1 "2" 2))
#guard strContains sIoc s!"<circle cx=\"40\" cy=\"26\" r=\"5\" fill=\"{bgC}\""
#guard strContains sIoc s!"<circle cx=\"520\" cy=\"26\" r=\"5\" fill=\"{blueC}\""

-- Ico [1,2): filled left, hollow right.
private def sIco := rendered (.term (dev .Ico "1" 1 "2" 2))
#guard strContains sIco s!"<circle cx=\"40\" cy=\"26\" r=\"5\" fill=\"{blueC}\""
#guard strContains sIco s!"<circle cx=\"520\" cy=\"26\" r=\"5\" fill=\"{bgC}\""

/-! ## Rays, univ, empty, singleton -/

-- Ici a: one filled glyph at the center, bar runs to the right edge.
private def sIci := rendered (.term (rayLo .Ici "a"))
#guard strContains sIci "<rect x=\"280\" y=\"22\" width=\"272\""
#guard strContains sIci s!"<circle cx=\"280\" cy=\"26\" r=\"5\" fill=\"{blueC}\""

-- Iio b: bar from the left edge, hollow glyph at the center.
private def sIio := rendered (.term (rayHi .Iio "b"))
#guard strContains sIio "<rect x=\"8\" y=\"22\" width=\"272\""
#guard strContains sIio s!"<circle cx=\"280\" cy=\"26\" r=\"5\" fill=\"{bgC}\""

-- univ: full-width bar, no glyphs.
private def sUniv := rendered (.term univT)
#guard strContains sUniv "<rect x=\"8\" y=\"22\" width=\"544\""
#guard !strContains sUniv "<circle"

-- ∅ renders as the ∅ symbol, no bar.
private def sEmpty := rendered (.term emptyT)
#guard strContains sEmpty ">∅</text>"
#guard !strContains sEmpty "<rect"

-- {a}: a single filled point, no bar rect.
private def sSing := rendered (.term (singT "a"))
#guard strContains sSing s!"<circle cx=\"280\" cy=\"26\" r=\"5\" fill=\"{blueC}\""
#guard !strContains sSing "<rect"

/-! ## Stacked rows for subset/eq shapes, aligned coordinates -/

private def sSub := rendered (.subset (dev .Icc "0" 0 "3" 3) (dev .Icc "1" 1 "2" 2))
#guard strContains sSub ">⊆ L</text>"
#guard strContains sSub ">⊇ R</text>"
-- LHS row at y = 22, RHS row at y = 48; both use the shared axis coordinates.
#guard strContains sSub s!"<rect x=\"40\" y=\"22\" width=\"480\" height=\"8\" fill=\"{blueC}\""
#guard strContains sSub s!"<rect x=\"200\" y=\"48\" width=\"160\" height=\"8\" fill=\"{greenC}\""

/-! ## Mismatch shading: [0,3] ⊆ [1,2] shades exactly what LHS covers beyond RHS -/

#guard strContains sSub "data-mismatch=\"point 0\""
#guard strContains sSub "data-mismatch=\"seg 0 1\""
#guard strContains sSub "data-mismatch=\"seg 2 3\""
#guard strContains sSub "data-mismatch=\"point 3\""
#guard !strContains sSub "data-mismatch=\"point 1\""
#guard !strContains sSub "data-mismatch=\"seg 1 2\""
#guard strContains sSub "fill=\"var(--vscode-charts-red, #ef4444)\""

-- The motivating correct equality has NO mismatch shading.
private def sJoin := rendered
  (.eq (.union (dev .Ioc "1" 1 "2" 2) (dev .Ioc "2" 2 "3" 3)) (dev .Ioc "1" 1 "3" 3))
#guard !strContains sJoin "#ef4444"
#guard !strContains sJoin "data-mismatch"
-- ... and shows the union operator marker.
#guard strContains sJoin ">∪</text>"

-- Intersection marker.
#guard strContains (rendered (.term (.inter (dev .Icc "0" 0 "2" 2) (dev .Icc "1" 1 "3" 3))))
  ">∩</text>"

/-! ## Unknown order: caption instead of guessing; mismatch shading suppressed -/

private def sUnk := rendered (.subset (de .Icc "a" "b") (de .Ioo "a" "b"))
#guard strContains sUnk "order unknown between a, b"
#guard strContains sUnk ">a?</text>"
#guard strContains sUnk ">b?</text>"
-- Even though [a,b] ⊄ (a,b), no shading: the order is not fully determined.
#guard !strContains sUnk "data-mismatch"

-- With facts ordering the atoms, the caption disappears and shading appears.
private def sOrd := rendered (.subset (de .Icc "a" "b") (de .Ioo "a" "b")) [fLt "a" "b"]
#guard !strContains sOrd "order unknown"
#guard strContains sOrd "data-mismatch=\"point a\""
#guard strContains sOrd "data-mismatch=\"point b\""
#guard !strContains sOrd "data-mismatch=\"seg a b\""

/-! ## Contradictory hypotheses caption -/

#guard strContains (rendered (.subset (de .Icc "a" "b") (de .Icc "a" "b"))
    [fLt "a" "b", fLt "b" "a"])
  "contradictory order hypotheses"

/-! ## Membership marker -/

private def sMem := rendered (.mem (epv "3" 3) (dev .Icc "1" 1 "4" 4))
#guard strContains sMem "fill=\"var(--vscode-charts-purple, #8b5cf6)\""

/-! ## Axis and determinism -/

#guard strContains sIcc "<line x1=\"8\""
#guard rendered (.term (dev .Icc "1" 1 "2" 2)) == sIcc

/-! ## Coverage-semantics unit tests (what the mismatch shading is built on) -/

private def gLit : OrderGraph :=
  OrderGraph.build #[("1", some 1), ("2", some 2), ("3", some 3)] #[]

-- Point coverage respects open/closed sides.
#guard (dev .Ioc "1" 1 "2" 2).coversPoint gLit "2" == true
#guard (dev .Ioc "1" 1 "2" 2).coversPoint gLit "1" == false
#guard (dev .Ico "1" 1 "2" 2).coversPoint gLit "1" == true
#guard (dev .Ico "1" 1 "2" 2).coversPoint gLit "2" == false
-- Union/intersection combine coverage.
#guard (Tree.union (dev .Ioc "1" 1 "2" 2) (dev .Ioc "2" 2 "3" 3)).coversSeg gLit "2" "3" == true
#guard (Tree.inter (dev .Icc "1" 1 "2" 2) (dev .Icc "2" 2 "3" 3)).coversPoint gLit "2" == true
#guard (Tree.inter (dev .Icc "1" 1 "2" 2) (dev .Icc "2" 2 "3" 3)).coversSeg gLit "1" "2" == false
-- Rays cover outer regions; bounded intervals do not.
#guard (rayHi .Iio "1").coversLeftOuter gLit "1" == true
#guard (dev .Icc "1" 1 "3" 3).coversLeftOuter gLit "1" == false
#guard (rayLo .Ioi "3").coversRightOuter gLit "3" == true
-- Mismatch is one-directional (LHS beyond RHS only).
private def layLit := computeLayout gLit
#guard mismatchRegions gLit layLit (dev .Icc "1" 1 "2" 2) (dev .Icc "1" 1 "3" 3) == #[]
#guard mismatchRegions gLit layLit (dev .Icc "1" 1 "3" 3) (dev .Icc "1" 1 "2" 2)
    == #[.seg "2" "3", .point "3"]

/-! ## Equality shapes shade BOTH directions (`R-only` marks the reverse)

The confirmed repro: `Icc 0 1 = Icc 0 2` (false, RHS strictly larger) rendered with
*zero* red before the fix.  Now the RHS-beyond-LHS regions are shaded too, tagged
`R-only` in `data-mismatch`; the mirror statement keeps its untagged (L-beyond-R)
regions; subset shapes stay one-directional. -/

private def sEqRev := rendered (.eq (dev .Icc "0" 0 "1" 1) (dev .Icc "0" 0 "2" 2))
#guard strContains sEqRev "data-mismatch=\"R-only seg 1 2\""
#guard strContains sEqRev "data-mismatch=\"R-only point 2\""
#guard !strContains sEqRev "data-mismatch=\"seg 1 2\""      -- no untagged L-only region
private def sEqFwd := rendered (.eq (dev .Icc "0" 0 "2" 2) (dev .Icc "0" 0 "1" 1))
#guard strContains sEqFwd "data-mismatch=\"seg 1 2\""
#guard strContains sEqFwd "data-mismatch=\"point 2\""
#guard !strContains sEqFwd "R-only"
-- A correct equality still shows no shading in either direction (see sJoin above),
-- and subset mismatches are never tagged `R-only`.
#guard !strContains sSub "R-only"

/-! ## Discrete types: possibly-empty regions are not shaded

`Region.knownInhabited` gates the mismatch candidates: point regions always count,
open segments need `DenselyOrdered`, outer rays need `NoMinOrder`/`NoMaxOrder`.
The confirmed repro (`Set.Ico (0:ℕ) 2 ⊆ Set.Icc (0:ℕ) 1`, TRUE over ℕ) must not
shade `seg 1 2`, and a muted caption explains why. -/

#guard Region.knownInhabited .all (.seg "1" "2") == true
#guard Region.knownInhabited { denselyOrdered := false } (.seg "1" "2") == false
#guard Region.knownInhabited { denselyOrdered := false } (.point "1") == true
#guard Region.knownInhabited { noMinOrder := false } (.leftOuter "1") == false
#guard Region.knownInhabited { noMaxOrder := false } (.rightOuter "1") == false
#guard Region.knownInhabited .all (.leftOuter "1") == true

-- `mismatchRegions` drops exactly the possibly-empty candidates.
#guard mismatchRegions gLit layLit (dev .Icc "1" 1 "3" 3) (dev .Icc "1" 1 "2" 2)
    { denselyOrdered := false } == #[.point "3"]

-- Rendered: the discrete Ico/Icc repro shades no segment; the caption appears.
private def natInst : InstAvail :=
  { denselyOrdered := false, noMinOrder := false }  -- ℕ: discrete, bounded below
private def sDiscrete :=
  renderedI (.subset (dev .Ico "0" 0 "2" 2) (dev .Icc "0" 0 "1" 1)) natInst
#guard !strContains sDiscrete "data-mismatch=\"seg"
#guard strContains sDiscrete
  "open segments not shaded: no DenselyOrdered instance (they may be empty)"
-- Over a dense type the same shape shades `seg 1 2` and shows no such caption.
private def sDense := rendered (.subset (dev .Ico "0" 0 "2" 2) (dev .Icc "0" 0 "1" 1))
#guard strContains sDense "data-mismatch=\"seg 1 2\""
#guard !strContains sDense "open segments not shaded"

/-! ## Instance-gated emptiness captions

Density/unboundedness-dependent iffs are dropped when the element type lacks the
instance (the confirmed `= ∅ ↔ 1 ≤ 0 (DenselyOrdered)`-over-ℕ repro), and the
`= ∅` captions (which negate the nonemptiness iff) need `LinearOrder`. -/

#guard emptinessCaption? (.nonempty (de .Ioo "a" "b")) { denselyOrdered := false } == none
#guard emptinessCaption? (.eq (de .Ioo "a" "b") emptyT) { denselyOrdered := false } == none
#guard emptinessCaption? (.nonempty (rayHi .Iio "b")) { noMinOrder := false } == none
#guard emptinessCaption? (.nonempty (rayLo .Ioi "a")) { noMaxOrder := false } == none
#guard emptinessCaption? (.eq (de .Icc "a" "b") emptyT) { linearOrder := false } == none
-- Non-density-dependent captions survive on discrete types.
#guard emptinessCaption? (.nonempty (de .Icc "a" "b")) natInst == some "Nonempty ↔ a ≤ b"
#guard !strContains (renderedI (.eq (dev .Ioo "0" 0 "1" 1) emptyT) natInst) "= ∅ ↔"

/-! ## End-to-end SVG pins over actual types (the same path the panel takes) -/

-- ℕ discrete repro: no segment shading, caption present (statement is TRUE).
#assert_svg_lacks (Set.Ico (0:ℕ) 2 ⊆ Set.Icc (0:ℕ) 1) => "data-mismatch=\"seg"
#assert_svg_has (Set.Ico (0:ℕ) 2 ⊆ Set.Icc (0:ℕ) 1)
  => "open segments not shaded: no DenselyOrdered instance (they may be empty)"
example : Set.Ico (0:ℕ) 2 ⊆ Set.Icc (0:ℕ) 1 := by
  intro x hx; simp only [Set.mem_Ico] at hx; simp only [Set.mem_Icc]; omega
-- ℕ `Ioo 0 1 = ∅` repro: the density-dependent `= ∅ ↔ 1 ≤ 0` iff is gone.
#assert_svg_lacks (Set.Ioo (0:ℕ) 1 = ∅) => "= ∅ ↔"
example : Set.Ioo (0:ℕ) 1 = ∅ := by
  ext x; simp only [Set.mem_Ioo, Set.mem_empty_iff_false, iff_false]; omega
-- ℕ nonempty-Iio repro: no "always holds (NoMinOrder)" caption (statement is FALSE)…
#assert_svg_lacks (Set.Iio (0:ℕ)).Nonempty => "always holds"
-- … but ℕ *does* have `NoMaxOrder`, and ℝ has both: captions stay.
#assert_svg_has (Set.Ioi (0:ℕ)).Nonempty => "Nonempty always holds (NoMaxOrder)"
#assert_svg_has (Set.Iio (0:ℝ)).Nonempty => "Nonempty always holds (NoMinOrder)"
-- ℝ equality repro end to end: both directions shaded.
#assert_svg_has (Set.Icc (0:ℝ) 1 = Set.Icc (0:ℝ) 2) => "data-mismatch=\"R-only seg 1 2\""
#assert_svg_has (Set.Icc (0:ℝ) 2 = Set.Icc (0:ℝ) 1) => "data-mismatch=\"seg 1 2\""
#assert_svg_lacks (Set.Icc (0:ℝ) 2 = Set.Icc (0:ℝ) 1) => "R-only"

/-! ## Theme-aware colors: every themed element is a `var(--vscode-…)` expression
with its fallback hex *inside* the `var()` -/

-- Bars/glyphs use the charts palette variables (fallback hex inside the var()).
#guard strContains sIcc "var(--vscode-charts-blue, #3b82f6)"
#guard strContains sSub "var(--vscode-charts-green, #10b981)"
#guard strContains sSub "var(--vscode-charts-red, #ef4444)"
#guard strContains sMem "var(--vscode-charts-purple, #8b5cf6)"
-- Unordered-atom labels and the unknown-order caption use the warning color.
#guard strContains sUnk "var(--vscode-charts-yellow, #f59e0b)"
-- Axis and tick labels use the editor foreground.
#guard strContains sIcc "stroke=\"var(--vscode-editor-foreground, #333333)\""
#guard strContains sIcc "fill=\"var(--vscode-editor-foreground, #333333)\""
-- Hollow glyphs are filled with the editor background; the panel background is
-- themed (the svg `style` is a React-style JSON object, serialized as JSON).
#guard strContains sIoo "fill=\"var(--vscode-editor-background, #ffffff)\""
#guard strContains sIcc "\"background\":\"var(--vscode-editorWidget-background, #fafafa)\""
-- No un-themed hard-coded palette color survives outside a var() fallback.
#guard !strContains sIcc "fill=\"#3b82f6\""
#guard !strContains sSub "fill=\"#10b981\""
#guard !strContains sSub "fill=\"#ef4444\""
#guard !strContains sMem "fill=\"#8b5cf6\""
#guard !strContains sIoo "fill=\"#ffffff\""
#guard !strContains sIcc "\"background\":\"#fafafa\""

/-! ## Emptiness / nonemptiness shapes: single bar row + order-condition caption -/

private def sNonempty := rendered (.nonempty (dev .Ioc "1" 1 "2" 2))
#guard strContains sNonempty ">Nonempty ↔ 1 < 2</text>"
#guard strContains sNonempty "<rect x=\"40\" y=\"22\""  -- the interval bar is drawn
#guard strContains (rendered (.nonempty (de .Icc "a" "b"))) ">Nonempty ↔ a ≤ b</text>"
#guard strContains (rendered (.nonempty (de .Ioo "a" "b")))
    ">Nonempty ↔ a < b (DenselyOrdered)</text>"
#guard strContains (rendered (.nonempty (rayLo .Ici "a"))) ">Nonempty always holds</text>"
#guard strContains (rendered (.nonempty (rayLo .Ioi "a")))
    ">Nonempty always holds (NoMaxOrder)</text>"
#guard strContains (rendered (.nonempty (rayHi .Iio "b")))
    ">Nonempty always holds (NoMinOrder)</text>"
#guard strContains (rendered (.neEmpty (de .Ico "a" "b"))) ">≠ ∅ ↔ a < b</text>"
#guard strContains (rendered (.eq (de .Icc "a" "b") emptyT)) ">= ∅ ↔ b < a</text>"
#guard strContains (rendered (.eq emptyT (de .Ioc "a" "b"))) ">= ∅ ↔ b ≤ a</text>"

-- Caption unit tests (the pure function feeding the SVG captions).
#guard emptinessCaption? (.nonempty (de .Icc "a" "b")) == some "Nonempty ↔ a ≤ b"
#guard emptinessCaption? (.nonempty (de .Ioc "a" "b")) == some "Nonempty ↔ a < b"
#guard emptinessCaption? (.neEmpty (de .Ioo "a" "b"))
    == some "≠ ∅ ↔ a < b (DenselyOrdered)"
#guard emptinessCaption? (.neEmpty (rayHi .Iic "b")) == some "≠ ∅ always holds"
#guard emptinessCaption? (.eq (de .Ico "a" "b") emptyT) == some "= ∅ ↔ b ≤ a"
#guard emptinessCaption? (.eq emptyT (de .Icc "a" "b")) == some "= ∅ ↔ b < a"
-- No caption for shapes without an emptiness reading or for composite trees.
#guard emptinessCaption? (.term (de .Icc "a" "b")) == none
#guard emptinessCaption? (.eq (de .Icc "a" "b") (de .Icc "a" "b")) == none
#guard emptinessCaption? (.nonempty (.union (de .Icc "a" "b") (de .Icc "c" "d"))) == none
#guard emptinessCaption? (.nonempty emptyT) == none
-- Rays `= ∅` have no order condition on two endpoints: no caption, no guessing.
#guard emptinessCaption? (.eq (rayLo .Ici "a") emptyT) == none

/-! ## Set-builder provenance badge -/

private def sSB := rendered (.subset (devSB .Ico "0" 0 "1" 1) (dev .Icc "0" 0 "1" 1))
#guard strContains sSB ">from set-builder</text>"
-- Badge appears once even with a set-builder leaf inside a union …
#guard strContains
    (rendered (.term (.union (devSB .Ico "0" 0 "1" 1) (dev .Icc "1" 1 "2" 2))))
    ">from set-builder</text>"
-- … and never for ordinary `Set.Ixx` leaves.
#guard !strContains sSub "from set-builder"
#guard !strContains sIcc "from set-builder"

end IntervalInspectorTests
