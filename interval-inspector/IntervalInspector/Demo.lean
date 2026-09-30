import IntervalInspector.Widget
import Mathlib.Data.Real.Basic
import Mathlib.Order.Interval.Set.LinearOrder

/-! # Interval Inspector: demos

Open this file in VS Code and put the cursor on a `#interval_inspect` command or on
an `interval_inspect?` tactic to see the inspector panel in the InfoView.
-/

namespace IntervalInspector.Demo

/-! ## 1. The motivating example: joining two `Ioc` bars

The inspector shows the two half-open bars meeting at the middle endpoint and
suggests `Set.Ioc_union_Ioc_eq_Ioc` with its ordering side conditions.  With literal
endpoints both conditions are ready (literals compare automatically): -/

#interval_inspect (Set.Ioc (1:ℝ) 2 ∪ Set.Ioc 2 3 = Set.Ioc 1 3)

/-- The same scenario as a tactic proof over symbolic endpoints: the panel reads the
hypotheses `h₁ h₂`, reports both side conditions ready, and clicking the suggestion
inserts the tactic text in place of `interval_inspect?`. -/
example {a b c : ℝ} (h₁ : a ≤ b) (h₂ : b ≤ c) :
    Set.Ioc a b ∪ Set.Ioc b c = Set.Ioc a c := by
  interval_inspect?
  exact Set.Ioc_union_Ioc_eq_Ioc h₁ h₂

/-! ## 2. Membership -/

#interval_inspect ((3:ℝ) ∈ Set.Icc 1 4)

/-- Membership with symbolic endpoints: suggests `Set.mem_Ioc.mpr ⟨?_, ?_⟩` with both
side conditions ready from `h₁ h₂`. -/
example {x a b : ℝ} (h₁ : a < x) (h₂ : x ≤ b) : x ∈ Set.Ioc a b := by
  interval_inspect?
  exact Set.mem_Ioc.mpr ⟨h₁, h₂⟩

/-! ## 3. Cross-kind subset: the open interval sits inside the closed one.
Hollow endpoint circles (open) on the top bar, filled (closed) on the bottom bar. -/

#interval_inspect (Set.Ioo (1:ℝ) 2 ⊆ Set.Icc 1 2)

example {a b : ℝ} : Set.Ioo a b ⊆ Set.Icc a b := by
  interval_inspect?
  exact Set.Ioo_subset_Icc_self

/-! ## 4. Unknown order: nothing relates `a` and `b`, so instead of guessing the
inspector flags both atoms with `?` and prints "order unknown between a, b". -/

#interval_inspect ∀ (a b : ℝ), Set.Icc a b ⊆ Set.Icc a b

/-! ## 5. A mismatch: `[0, 3]` is *not* inside `[1, 2]`; the regions left of `1` and
right of `2` are provably covered by the LHS but not by the RHS, so they are shaded
red as mismatch candidates. -/

#interval_inspect (Set.Icc (0:ℝ) 3 ⊆ Set.Icc 1 2)

/-! ## 6. Text mode (deterministic ASCII; this is what the test suite asserts on) -/

/-- info: Ioc a b ∪ Ioc b c = Ioc a c: (a───b] ∪ (b───c] = (a───c] -/
#guard_msgs in
#interval_inspect (text := true)
  ∀ (a b c : ℝ), Set.Ioc a b ∪ Set.Ioc b c = Set.Ioc a c

/-! ## 7. Theme-aware colors

Every color in the SVG (and in the suggestion badges) is a VS Code CSS variable with
a hex fallback — `var(--vscode-charts-blue, #3b82f6)`, axis and labels
`var(--vscode-editor-foreground, #333333)`, and so on.  Switch VS Code between light
and dark themes and re-render: the drawing follows the InfoView theme.  Any demo
shows it; this one exercises bars, glyphs, mismatch shading and the axis at once. -/

#interval_inspect (Set.Icc (0:ℝ) 3 ⊆ Set.Ioo 1 2)

/-! ## 8. Emptiness and nonemptiness

`Set.Nonempty s`, `s = ∅`, `∅ = s`, `s ≠ ∅` (also spelled `¬(s = ∅)`) and the
mirror `∅ ≠ s` draw the interval with a caption tying the shape to its order
condition (e.g. `Nonempty ↔ 1 < 2`), and suggest the verified `nonempty_Ixx` /
`Ixx_eq_empty` (+ `_iff`) / `Nonempty.ne_empty` lemmas (`.symm`-wrapped for the
mirror spelling) with their side conditions checked. -/

#interval_inspect (Set.Ioc (1:ℝ) 2).Nonempty

example {a b : ℝ} (h : a < b) : (Set.Ioc a b).Nonempty := by
  interval_inspect?
  exact Set.nonempty_Ioc.mpr h

example {a b : ℝ} (h : a ≤ b) : Set.Icc a b ≠ ∅ := by
  interval_inspect?
  exact (Set.nonempty_Icc.mpr h).ne_empty

example {a b : ℝ} (h : a < b) : (∅ : Set ℝ) ≠ Set.Ioo a b := by
  interval_inspect?
  exact ((Set.nonempty_Ioo.mpr h).ne_empty).symm

/-- info: Ioc 2 1 = ∅: (2───1] = ∅ -/
#guard_msgs in
#interval_inspect (text := true) (Set.Ioc (2:ℝ) 1 = ∅)

/-! ## 9. Set-builder intervals

Set-builder spellings of intervals — `{x | a ≤ x ∧ x < b}` and the other one- and
two-sided `≤`/`<` combinations, conjuncts in either order — are recognized as their
`Set.Ixx` kind (badged "from set-builder" in the SVG) and participate in the whole
pipeline: layout, order graph, mismatch shading and lemma suggestions.  The textbook
goal below lights up fully, suggesting `Set.Ico_subset_Icc_self`. -/

#interval_inspect ({x : ℝ | 0 ≤ x ∧ x < 1} ⊆ Set.Icc 0 1)

example : {x : ℝ | 0 ≤ x ∧ x < 1} ⊆ Set.Icc 0 1 := by
  interval_inspect?
  exact Set.Ico_subset_Icc_self

/-- info: Ici 5: [5───∞) -/
#guard_msgs in
#interval_inspect (text := true) ({x : ℝ | 5 ≤ x})

/-! ## 10. Honest output over discrete types (ℕ)

The inspector checks which order typeclasses the element type actually has
(`Meta.synthInstance?` during analysis) and gates every instance-dependent claim.

Over `ℕ` there is no `DenselyOrdered` instance, so the open segment between `1`
and `2` may be empty — and indeed `Set.Ico 0 2 ⊆ Set.Icc 0 1` is *true* over `ℕ`.
No red "mismatch" shading appears on the segment; a muted caption explains why. -/

#interval_inspect (Set.Ico (0:ℕ) 2 ⊆ Set.Icc (0:ℕ) 1)

example : Set.Ico (0:ℕ) 2 ⊆ Set.Icc (0:ℕ) 1 := by
  intro x hx; simp only [Set.mem_Ico] at hx; simp only [Set.mem_Icc]; omega

/-- `(Set.Iio (0:ℕ)).Nonempty` is *false* (`ℕ` has no `NoMinOrder`): the
`exact Set.nonempty_Iio` suggestion — valid over `ℝ` — is suppressed with an
explanatory note instead of being shown `ALL-READY`. -/
example : ¬ (Set.Iio (0:ℕ)).Nonempty := by simp

#interval_inspect (Set.Iio (0:ℕ)).Nonempty

/-! ## 11. Transitive chaining through intermediate hypotheses

`b` is not an endpoint of the goal, but `a ≤ b → b ≤ c` chains through it: both
side conditions of `Set.mem_Icc` are reported ready and no "order unknown"
caption appears. -/

example (a b c : ℝ) (h₁ : a ≤ b) (h₂ : b ≤ c) : a ∈ Set.Icc a c := by
  interval_inspect?
  exact Set.mem_Icc.mpr ⟨le_refl a, le_trans h₁ h₂⟩

/-! ## 12. Section variables

`#interval_inspect` elaborates like `#check`: section `variable`s are in scope,
and section hypotheses (`h : a ≤ b`) feed the side-condition readiness. -/

section
variable (a b : ℝ) (h : a ≤ b)

#interval_inspect (Set.Icc a b).Nonempty

/-- info: Icc a b: [a───b] -/
#guard_msgs in
#interval_inspect (text := true) Set.Icc a b

end

end IntervalInspector.Demo
