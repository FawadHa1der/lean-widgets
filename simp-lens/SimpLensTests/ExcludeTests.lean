import SimpLensTests.Helpers

/-!
# Exclusion tests — re-running with one lemma erased

`#lens_exclude` pins the exact landing goal when a used lemma is erased from
the simp set; `#lens_essential` pins the essentiality classification;
`#lens_exclude_closes` asserts redundancy (goal closes anyway).
-/

namespace SimpLensTests.Exclude

set_option linter.unusedVariables false

-- ## essential lemma: without it the goal is stuck at a specific point
-- (note: `0 + n = n` still closes without `Nat.zero_add` — the default simp
-- set has alternate routes — so it is asserted below as *redundant*)
#lens_exclude_closes ∀ n : Nat, 0 + n = n without Nat.zero_add
#lens_essential ∀ n : Nat, 0 + n = n without Nat.zero_add => false
#lens_exclude ∀ n : Nat, n + 0 + 0 = n without Nat.add_zero => "n + 0 + 0 = n"
#lens_exclude ∀ n : Nat, n + 0 + 0 = n without eq_self => "n = n"
#lens_exclude_closes ∀ l : List Nat, l ++ [] = l without List.append_nil
#lens_exclude_closes ∀ p : Prop, (p ∧ True) ∨ False ↔ p without and_true
#lens_exclude_closes ∀ p : Prop, (p ∧ True) ∨ False ↔ p without or_false
#lens_exclude ∀ p : Prop, (p ∧ True) ∨ False ↔ p without iff_self => "p ↔ p"

-- ## a local hypothesis can be excluded too (fvar erasure)
#lens_exclude ∀ (n : Nat) (h : n = 5), n + 0 = 5 hyps [h] without h => "n = 5"

-- ## a simproc can be excluded (erased from the simproc set); the default
-- simp set still closes this via the `if_pos`/`ite_true` lemma route
#lens_essential ∀ a b : Nat, (if true then a else b) = a without reduceIte => false
#lens_exclude_closes ∀ a b : Nat, (if true then a else b) = a without reduceIte

-- ## essentiality classification
#lens_essential ∀ n : Nat, n + 0 + 0 = n without eq_self => true

-- ## redundant lemma: an alternate simp path still closes the goal
-- (without List.append_nil, simp uses List.length_append + List.length_nil +
-- Nat.add_zero to close `(l ++ []).length = l.length`)
#lens_exclude_closes ∀ (l : List Nat), (l ++ []).length = l.length without List.append_nil
#lens_essential ∀ (l : List Nat), (l ++ []).length = l.length without List.append_nil => false

/-! ## containment: a preview that blows up is reported, never propagated

Regression tests for the escaped-timeout bug: heartbeat/recursion-limit
exceptions are *runtime* exceptions, which `Core.tryCatch` (and hence a plain
`catch _`) rethrows — a pathological exclusion re-run used to hard-fail the
whole tactic. `runExclusion` must contain them (`tryCatchRuntimeEx`) and
report a `timedOut` outcome instead. -/

-- a rewriting system whose exclusion re-run *diverges*: with `exc_stop`
-- erased, `exc_succ` rewrites `excF n ~> excF (n+1)` forever. Excluding the
-- stopper must yield a contained `timedOut` outcome (under the same
-- per-preview budget the tactic derives), not a tactic failure.
/-- Constant function used by the divergence regression tests. -/
def excF (_ : Nat) : Nat := 0
/-- Diverging rewrite: `excF n ~> excF (n + 1)` applies forever. -/
theorem exc_succ (n : Nat) : excF n = excF (n + 1) := rfl
/-- The stopper: rewrites any `excF n` to `0` outright. -/
theorem exc_stop (n : Nat) : excF n = 0 := rfl

-- (`eq_self` is genuinely recorded: after `exc_stop` rewrites the LHS the
-- goal is `0 = 0`, which simp closes via `eq_self` — verified against the
-- traced run and plain `simp`'s own used-theorem list)
#lens_used excF 0 = 0 with [exc_stop, exc_succ] => [exc_stop, eq_self]
#lens_exclude_status excF 0 = 0 with [exc_stop, exc_succ] without exc_stop
  budget 2000000 => timedOut

-- a tiny budget cuts off even an ordinary re-run — containment is
-- unconditional, whatever the goal
#lens_exclude_status ∀ n : Nat, n + 0 + 0 = n without Nat.add_zero
  budget 1 => timedOut

-- a comfortable budget leaves ordinary re-runs untouched (status ok, same
-- landing the unbudgeted preview reports)
#lens_exclude_status ∀ n : Nat, n + 0 + 0 = n without Nat.add_zero
  budget 100000000 => ok

end SimpLensTests.Exclude
