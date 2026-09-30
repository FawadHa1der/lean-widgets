import SimpLensTests.Helpers

/-!
# Trace tests — exact used-lemma sets, step counts, origins, before/after

All goals here are elaborated with their binders intro'd, so the traced run
sees the same goal `example ... := by simp` would. The toolchain is pinned,
so all values below are deterministic.
-/

set_option linter.unusedVariables false

namespace SimpLensTests.Trace

-- ## 0 + n = n
#lens_used ∀ n : Nat, 0 + n = n => [Nat.zero_add, eq_self]
#lens_steps ∀ n : Nat, 0 + n = n => 2
#lens_step ∀ n : Nat, 0 + n = n at 0 => Nat.zero_add, "0 + n" ~> "n"
#lens_step ∀ n : Nat, 0 + n = n at 1 => eq_self, "n = n" ~> "True"
#lens_closes ∀ n : Nat, 0 + n = n

-- ## n + 0 + 0 = n — the same lemma fires twice; both firings are frames
#lens_used ∀ n : Nat, n + 0 + 0 = n => [Nat.add_zero, eq_self]
#lens_steps ∀ n : Nat, n + 0 + 0 = n => 3
#lens_step ∀ n : Nat, n + 0 + 0 = n at 0 => Nat.add_zero, "n + 0" ~> "n"
#lens_step ∀ n : Nat, n + 0 + 0 = n at 1 => Nat.add_zero, "n + 0" ~> "n"
#lens_step ∀ n : Nat, n + 0 + 0 = n at 2 => eq_self, "n = n" ~> "True"
#lens_closes ∀ n : Nat, n + 0 + 0 = n

-- ## l ++ [] = l
#lens_used ∀ l : List Nat, l ++ [] = l => [List.append_nil, eq_self]
#lens_steps ∀ l : List Nat, l ++ [] = l => 2
#lens_step ∀ l : List Nat, l ++ [] = l at 0 => List.append_nil, "l ++ []" ~> "l"
#lens_closes ∀ l : List Nat, l ++ [] = l

-- ## if true then a else b — a simproc (`reduceIte`) as principal origin
#lens_used ∀ a b : Nat, (if true then a else b) = a => [eq_self, reduceIte]
#lens_steps ∀ a b : Nat, (if true then a else b) = a => 3
#lens_principal ∀ a b : Nat, (if true then a else b) = a at 1 => reduceIte
#lens_closes ∀ a b : Nat, (if true then a else b) = a

-- ## logic: (p ∧ True) ∨ False ↔ p
#lens_used ∀ p : Prop, (p ∧ True) ∨ False ↔ p => [and_true, or_false, iff_self]
#lens_steps ∀ p : Prop, (p ∧ True) ∨ False ↔ p => 3
#lens_step ∀ p : Prop, (p ∧ True) ∨ False ↔ p at 0 => and_true, "p ∧ True" ~> "p"
#lens_step ∀ p : Prop, (p ∧ True) ∨ False ↔ p at 1 => or_false, "p ∨ False" ~> "p"
#lens_step ∀ p : Prop, (p ∧ True) ∨ False ↔ p at 2 => iff_self, "p ↔ p" ~> "True"
#lens_closes ∀ p : Prop, (p ∧ True) ∨ False ↔ p

-- ## not/and/or normalization
#lens_used ∀ p : Prop, ¬(p ∨ False) ↔ ¬p => [or_false, iff_self]
#lens_lands ∀ n : Nat, n + 0 = 5 => "n = 5"

-- ## a goal simp leaves partially simplified (specific landing goal)
#lens_used ∀ (f : Nat → Nat) (n : Nat), f (n + 0) = f n => [Nat.add_zero, eq_self]
#lens_lands ∀ (f : Nat → Nat) (n : Nat), f (n + 0) = 7 => "f n = 7"

-- ## local hypothesis as a simp lemma (fvar origin)
#lens_used ∀ (n : Nat) (h : n = 5), n + 0 = 5 hyps [h] => [h, Nat.add_zero, eq_self]
#lens_steps ∀ (n : Nat) (h : n = 5), n + 0 = 5 hyps [h] => 3
#lens_step ∀ (n : Nat) (h : n = 5), n + 0 = 5 hyps [h] at 0 => h, "n" ~> "5"
#lens_closes ∀ (n : Nat) (h : n = 5), n + 0 = 5 hyps [h]

-- ## extra global lemma added to the set (a non-@[simp] lemma fires)
#lens_used ∀ (a b : Nat), a + b + 0 = b + a with [Nat.add_comm] => [Nat.add_zero, Nat.add_comm, Nat.add_left_cancel_iff, eq_self]

-- ## NEGATIVE cases: no rewrite happens at all
#lens_used ∀ p : Prop, p → p => []
#lens_steps ∀ p : Prop, p → p => 0
#lens_lands ∀ p : Prop, p → p => "p"

-- ## lemmas that do NOT fire are not recorded
#lens_used ∀ n : Nat, 0 + n = n with [Nat.mul_one, List.append_nil] => [Nat.zero_add, eq_self]

-- ## purely definitional progress (finding repro): beta reduction changes
-- the goal but has no lemma/simproc origin, so the trace records *zero*
-- steps while still making progress — the widget renders this as
-- "definitional reductions only", never as a bare "0 rewrites" contradiction
#lens_steps ∀ y : Nat, (fun x : Nat => x) 5 = y => 0
#lens_used ∀ y : Nat, (fun x : Nat => x) 5 = y => []
#lens_lands ∀ y : Nat, (fun x : Nat => x) 5 = y => "5 = y"
#lens_at_progress ∀ y : Nat, (fun x : Nat => x) 5 = y => true
#lens_at_defonly ∀ y : Nat, (fun x : Nat => x) 5 = y => ["⊢"]

-- a lemma-driven run is NOT flagged definitional-only
#lens_at_defonly ∀ n : Nat, n + 0 = n => []
-- a no-progress run is NOT flagged definitional-only (changed = false)
#lens_at_defonly ∀ p : Prop, p → p => []

-- ## chain-consistency invariants over every traced run above
#lens_chain ∀ n : Nat, 0 + n = n
#lens_chain ∀ n : Nat, n + 0 + 0 = n
#lens_chain ∀ l : List Nat, l ++ [] = l
#lens_chain ∀ a b : Nat, (if true then a else b) = a
#lens_chain ∀ p : Prop, (p ∧ True) ∨ False ↔ p
#lens_chain ∀ (n : Nat) (h : n = 5), n + 0 = 5 hyps [h]
#lens_chain ∀ (f : Nat → Nat) (n : Nat), f (n + 0) = 7
#lens_chain ∀ p : Prop, p → p
#lens_chain ∀ (l : List Nat), (l ++ []).length = l.length

end SimpLensTests.Trace

namespace SimpLensTests.TraceDiag

-- ## Simp.Stats capture: per-firing diagnostics counters (only when enabled)
-- Nat.add_zero fires twice on `n + 0 + 0 = n`: the diagnostics counter sees
-- both firings even though `usedTheorems` deduplicates.
set_option diagnostics true in
#lens_diag ∀ n : Nat, n + 0 + 0 = n => Nat.add_zero used 2 tried 2

set_option diagnostics true in
#lens_diag ∀ n : Nat, 0 + n = n => Nat.zero_add used 1 tried 1

-- with diagnostics off (the default), no counters are recorded
#lens_diag_empty ∀ n : Nat, n + 0 + 0 = n

end SimpLensTests.TraceDiag

namespace SimpLensTests.PhasesDepths

set_option linter.unusedVariables false

-- ## phase labels of frames, in order (post-rewrite, pre-simproc, post-close)
#lens_phases ∀ a b : Nat, (if true then a else b) = a => ["post", "pre", "post"]
#lens_phases ∀ n : Nat, n + 0 + 0 = n => ["post", "post", "post"]

-- ## a rewrite in a *dependent* argument position goes through dsimp:
-- Nat.add_zero (an rfl-theorem) fires in the `dpost` phase
#lens_phases ∀ (n : Nat) (f : (m : Nat) → Fin (m+1)), f (n + 0) = f n => ["dpost", "post"]
#lens_used ∀ (n : Nat) (f : (m : Nat) → Fin (m+1)), f (n + 0) = f n => [Nat.add_zero, eq_self]
#lens_equiv ∀ (n : Nat) (f : (m : Nat) → Fin (m+1)), f (n + 0) = f n
#lens_chain ∀ (n : Nat) (f : (m : Nat) → Fin (m+1)), f (n + 0) = f n

-- ## discharge depth: `Nat.div_self` needs `0 < n`, discharged by `h`
-- (a depth-1 step); the filmstrip keeps only the two depth-0 frames
#lens_depths ∀ (n : Nat) (h : 0 < n), n / n = 1 hyps [h] => [1, 0, 0]
#lens_steps ∀ (n : Nat) (h : 0 < n), n / n = 1 hyps [h] => 2
#lens_used ∀ (n : Nat) (h : 0 < n), n / n = 1 hyps [h] => [h, Nat.div_self, eq_self]
#lens_principal ∀ (n : Nat) (h : 0 < n), n / n = 1 hyps [h] at 0 => Nat.div_self
#lens_closes ∀ (n : Nat) (h : 0 < n), n / n = 1 hyps [h]
#lens_chain ∀ (n : Nat) (h : 0 < n), n / n = 1 hyps [h]
#lens_equiv ∀ (n : Nat) (h : 0 < n), n / n = 1 hyps [h]

-- ## depth recording: ordinary runs are all-zero
#lens_depths ∀ n : Nat, n + 0 + 0 = n => [0, 0, 0]

end SimpLensTests.PhasesDepths
