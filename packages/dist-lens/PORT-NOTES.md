# PORT-NOTES — `dist-lens` from Lean v4.32.2 / Mathlib v4.32.2 to Lean v4.34.0 / Mathlib v4.34.0

Reference (read-only): `widgets/dist-lens` (toolchain `leanprover/lean4:v4.32.2`,
Mathlib `v4.32.2`, ProofWidgets `6e311e2a`).
Port: `widgets-v4.34/dist-lens` (toolchain `leanprover/lean4:v4.34.0`, Mathlib
`v4.34.0` = `5ed29652`, ProofWidgets `106ff4fa`, Batteries `f2effa3d`, Aesop
`355695d5`, Qq `6a489d9a`, plausible `118aa17e`, importGraph `e928b725`,
LeanSearchClient `ddf04cf3`, Cli `e92c9f15` — all taken from Mathlib's
manifest by the one `lake update` the harness ran; never run it again).

Status: `lake build` and `lake test` both exit 0 on v4.34.0 (the final
evidence run is transcribed in the "Verification transcript" section at the
bottom of this file — an earlier draft referred to a transcript that was
never actually pasted in).  Every test file, the demo file
and the whole library except one tactic macro are byte-identical to the
reference (`diff -ru` over the two trees excluding `.lake/`, `scratch/`,
`*.log` and the manifest shows exactly three files: `lean-toolchain`,
`lakefile.toml`, `DistLens/Verify.lean`).

## Changes

| File | What | Why |
|---|---|---|
| `lean-toolchain` | `leanprover/lean4:v4.32.2` → `leanprover/lean4:v4.34.0` | the port target (set by the harness, not edited by the port agents) |
| `lakefile.toml` | `mathlib` `rev = "v4.32.2"` → `rev = "v4.34.0"` | same |
| `lake-manifest.json` | every dependency rev bumped to the ones Mathlib `v4.34.0` pins; `Cli` inputRev `v4.32.0` → `v4.34.0` | produced by the harness's single `lake update`; ProofWidgets moves from `6e311e2a` to `106ff4fa` (no API this package uses changed — every panel/render/RPC test passes unmodified) |
| `DistLens/Verify.lean` | inside the `pmf_num` macro, the `simp` step is now wrapped as `(set_option backward.isDefEq.respectTransparency.types false in simp [...])`; the `try`, the lemma list, the `<;> ennreal_num` continuation and the outer `set_option linter.deprecated false in` are unchanged.  Comment added explaining the option (this session corrected its version claim: the default flipped at v4.33.0, not v4.34.0). | **Forced by the toolchain.**  `backward.isDefEq.respectTransparency.types` is registered in `Lean/Meta/ExprDefEq.lean` with `defValue := false` at v4.32.2 (`-- TODO: replace with true after we fix stage0`) and `defValue := true` at v4.33.0 and v4.34.0.  With `true`, when `simp` instantiates `PMF.uniformOfFinset_apply`'s `hs : s.Nonempty` metavariable with the user's proof term, the term's type is compared with the metavariable's type **without** bumping transparency to `.default`.  The natural spelling `⟨1, by simp⟩` (used by the demo, the tests, and every suggestion DistLens emits for `uniformOfFinset`) elaborates to an `Exists.intro` whose inferred type is `∃ x, x ∈ s`; `Finset.Nonempty s` is a semireducible `def` for exactly that proposition, so at implicit transparency the types do not match, the rewrite silently does not fire, and `pmf_num` ends in `ennreal_num: cannot close this ℝ≥0∞ goal ⊢ (uniformOfFinset {1, 2, 3} ⋯) 2 = 3⁻¹` — a refused *true* claim.  Verified by MWE at v4.34.0 (`scratch/Probe1.lean`, `scratch/Probe2.lean` from the first port agent, and this session's `ProbeOld.lean`): the v4.32.2 recipe verbatim fails on `uniformOfFinset`, `simp` reports `PMF.uniformOfFinset_apply` as an *unused* simp argument, and the same recipe still proves the `uniformOfFintype`, `bernoulli`, `binomial`, `ofFintype`, `bind`/`map` examples — only the `Finset.Nonempty` argument is affected.  The option is scoped to the single `simp` call, so nothing else in the recipe (and no user code) runs under the legacy behaviour; false claims still fail with the same deterministic message (pinned by `VerifyTests`' `#guard_msgs` negatives, which pass unchanged). |
| `README.md` | new "Versions" section; `pmf_num` section documents the scoped option; "Deprecated upstream API" bullet states the deprecations are still present (not removed) at `v4.34.0` and names the successors; "Tests" paragraph replaces the approximate "~237" with the explicit census below | documentation of the port |
| `PORT-NOTES.md` | this file | required deliverable |

Alternatives considered for the `Verify.lean` change and rejected:
* changing the *suggested* spelling (e.g. `(by simp)` instead of `⟨1, by simp⟩`,
  or `Finset.insert_nonempty _ _`) — would alter the generated suggestion
  text, the `#guard_msgs` pins and the demo, and would still leave a user's
  own `⟨_, _⟩` proof unprovable by `pmf_num`;
* adding `Finset.Nonempty` unfolding lemmas to the simp set — changes the
  recipe's normal forms and the pinned failure messages;
* setting the option globally — forbidden (global option suppression) and
  unnecessary.

## Pin updates

None.  No `#guard_msgs` block, no `#guard`, no byte-exact SVG/ASCII pin, no
suggestion text and no failure message changed between the reference and the
port — the test tree is byte-identical and green.  (The scoped option was
chosen precisely so that `pmf_num`'s observable behaviour, including the
deterministic failure messages pinned by `VerifyTests.lean`, is unchanged.)

## Deviations

None.  No test deleted, commented out or weakened; no `sorry`; no global
linter/option suppression; both whitelist entries (`PMF.bernoulli`,
`PMF.binomial`) and all 14 lemmas of the `pmf_num` simp set are retained
verbatim.

Risk list from the research, resolved:
* **`PMF.bernoulli`/`PMF.binomial` removed at v4.34.0?**  No.  At Mathlib
  `v4.34.0` they are still `@[deprecated ProbabilityTheory.bernoulliMeasure
  (since := "2026-04-07")]` / `@[deprecated ProbabilityTheory.binomial (since
  := "2026-04-07")]` with the same dates as at `v4.32.2`; `bernoulli_apply` →
  `bernoulliMeasure_apply`, `binomial_apply` →
  `binomial_real_singleton` are likewise still-present deprecations.  The
  whitelist, the simp set and the `set_option linter.deprecated false in`
  wrapper stay as they were.
* **PMF lemma names in the simp set.**  All 14 resolve unchanged
  (`PMF.bind_apply`, `map_apply`, `pure_apply`, `bernoulli_apply`,
  `uniformOfFintype_apply`, `uniformOfFinset_apply`, `binomial_apply`,
  `ofFintype_apply`, `tsum_fintype`, `tsum_bool`, `Fin.sum_univ_succ`,
  `Matrix.cons_val_zero`, `Matrix.cons_val_one`, `Matrix.head_cons`).
* **ENNReal / `finiteness` behaviour.**  Unchanged: all four `ennreal_num`
  branches close the same residues, all 38 `VerifyTests` examples and the 17
  demo examples compile, the negative pins match byte-for-byte.
* **Probability module moves.**  None of the five imports moved
  (`Mathlib.Probability.ProbabilityMassFunction.{Constructions,Binomial,Integrals}`,
  `Mathlib.Probability.Distributions.Uniform`, `Mathlib.Tactic.Finiteness`).
* **`Matrix.vecCons` literals.**  Unchanged: `![…]` weight vectors and
  `![…]`-vectors of PMFs still extract and still reduce under
  `Matrix.cons_val_*` (`ChainMathTests`, `ExtractTests`, the weather/triangle
  chains in `Demo.lean`).

## Counts

Method (reproducible with `grep` over the two trees; the test sources are
byte-identical so every number is the same on both sides):

| Category | Reference v4.32.2 | Port v4.34.0 |
|---|---|---|
| `#guard_msgs` blocks in `DistLensTests/` (36 Extract, 4 Verify, 4 Suggest) | 44 | 44 |
| `#guard` in `DistLensTests/` (46 Model, 43 Render, 24 Contract, 23 ChainMath, 20 Suggest, 18 Text, 9 Invariant, 21 ClickE2E, 1 driver root) | 205 | 205 |
| compiled `example`s in `DistLensTests/` (38 Verify, 5 Suggest, 1 ClickE2E) | 44 | 44 |
| ClickE2E runtime assertions (`check` 23, `checkClean` 15, `checkEq` 8, `checkFails` 6) across its 8 `#eval` suites | 52 | 52 |
| **Test-driver total (`lake test`)** | **345** | **345** |
| `DistLens/Demo.lean`: compiled `example`s / live panel commands (`lake build`) | 17 / 12 | 17 / 12 |

The README previously quoted "~237 pinned assertions" without stating a
counting method; it now quotes the census above with the method spelled out.

Exact commands (run from the package root; identical results on both trees):
`grep -rhE '^\s*#guard_msgs\b' DistLensTests DistLensTests.lean | wc -l` → 44;
`grep -rhE '^\s*#guard(\s|$)' DistLensTests DistLensTests.lean | wc -l` → 205;
`grep -rhE '^\s*example\b' DistLensTests DistLensTests.lean | wc -l` → 44;
ClickE2E call counts = occurrences of each `check*` identifier in
`DistLensTests/ClickE2E.lean` *excluding* the four `def check*` lines
(231/235/241/246) → 23 + 15 + 8 + 6 = 52. Correction (2026-09-30, audit
follow-up): an earlier draft said 45 `#guard_msgs` (37 Extract) and a
ClickE2E breakdown of 24/16/9/7 "= 52"; the `#guard_msgs` grep was
unanchored and matched the docstring mention at `ExtractTests.lean:6`, and
the breakdown had counted the four `def` lines. The totals above (44 and
345) are the anchored figures.

## 4.34 gotchas worth knowing for QED64

1. **`backward.isDefEq.respectTransparency.types` defaults to `true` from
   Lean v4.33.0.**  Per its `register_builtin_option` description, Lean no
   longer bumps transparency to `.default` "when checking whether the type
   of a metavariable matches the type of the term being assigned to it" —
   the check runs at whatever transparency the unifier is already in
   (reducible inside `simp`).  Any rewrite/simp lemma whose argument is a
   proof of a semireducible `def`-proposition (`Finset.Nonempty` is the
   verified case; `Set.Nonempty`-style defs are the same shape) stops
   firing when the user's proof term was elaborated through the unfolded
   form (anonymous constructor / `Exists.intro`).  Symptoms
   are silent: no error, `simp` just reports the lemma unused.  Fix at the
   call site with `set_option backward.isDefEq.respectTransparency.types false
   in` scoped to the one tactic, or spell the proof with a lemma that has the
   `def` as its stated type.  In an in-browser playground this is the kind of
   regression that turns a "verified" click-to-insert goal into a red
   squiggle, so every suggestion-emitting widget should compile its own
   suggestions in tests (DistLens does: `VerifyTests`, `SuggestTests`,
   `ClickE2E`, `Demo`).
2. **Tactic macros are not linted for unused simp args.**  The
   `linter.unusedSimpArgs` warning (present since before v4.32.2) fires on a
   user-written `simp [...]` but not on the `simp` inside the `pmf_num`
   macro, so inserted `by unfold …; pmf_num` lines stay warning-free
   (`ClickE2E`'s `checkClean` fixtures prove it at v4.34.0).  Keep tactic
   recipes behind a macro if their simp set is deliberately over-complete.
3. **`PMF.bernoulli`/`PMF.binomial` are deprecated-but-present** at Mathlib
   `v4.34.0` (since 2026-04-07).  Any widget that names them needs
   `set_option linter.deprecated false in` *inside* its macros (as `pmf_num`
   does), or every inserted proof will warn.  Successors are Measure-valued
   (`ProbabilityTheory.bernoulliMeasure`, `ProbabilityTheory.binomial`) and
   need a different lemma set and `MeasurableSet` side goals.
4. **No Probability module moves between v4.32.2 and v4.34.0** for the
   files this package imports; `Mathlib.Tactic.Finiteness` and
   `Mathlib.Tactic.NormNum` are unchanged.
5. **ProofWidgets `6e311e2a` → `106ff4fa`** (through Mathlib's manifest):
   `Html`, `MakeEditLink`, `mk_rpc_widget%`, `server_rpc_method`,
   `RequestM.readDoc` and the `LazyEncodable Json` component-props shape are
   all source-compatible for this package — zero changes in
   `Widget.lean`/`Render.lean`.
6. **Memory of the in-process ClickE2E harness.**  Compiling
   `DistLensTests.ClickE2E` imports a full Mathlib environment inside the
   elaborating `lean` process (~5 GB RSS at v4.34.0).  Running two such
   suites concurrently on a loaded machine got this one SIGKILLed (exit 137)
   once during the port; rerun alone it passes.  Not a toolchain regression,
   but worth a serial `lake test` in CI.
7. **`lake test` with a warm cache prints nothing.**  If every target is
   up to date the driver exits 0 silently; to see the suite actually run,
   delete `.lake/build/lib/lean/DistLensTests*` (and `ir/DistLensTests*`)
   first, as this port did for its evidence run.
8. **The `Verify.lean` fix has a horizon.**  It relies on the
   `backward.isDefEq.respectTransparency.types` compatibility option
   (verified still registered with `defValue := true` at v4.34.1 and
   v4.35.0-rc3).  Core eventually deletes `backward.*` options once the
   migration they cover is considered complete; when this one is removed,
   `set_option backward.isDefEq.respectTransparency.types false in` becomes
   an *unknown option* error and every `by pmf_num` on a `uniformOfFinset`
   goal (the demo, `VerifyTests`, every emitted suggestion) fails to
   elaborate.  The permanent fix will have to change what `pmf_num` does
   rather than how the unifier behaves: either emit/accept a proof whose
   *stated* type is `Finset.Nonempty s` (e.g. `Finset.insert_nonempty _ _`
   or a `show s.Nonempty from ⟨1, by simp⟩` spelling in the suggestion
   text — which changes the suggestion pins), or add a `Finset.Nonempty`-
   unfolding lemma / `Finset.nonempty_iff_exists_mem`-style rewrite to the
   simp set so the `hs` argument is matched after unfolding (which changes
   the recipe's normal forms and the pinned failure messages).  Neither was
   done in this port because both alter pinned behaviour; the scoped option
   is the zero-pin-change bridge.  Watch the Lean release notes for the
   option's removal.

## Verification transcript (2026-09-30, audit follow-up)

Run from the package root on `leanprover/lean4:v4.34.0` after deleting this
package's own outputs (`rm -rf .lake/build/lib/lean/DistLens*
.lake/build/ir/DistLens*`) so that every `DistLens.*` and `DistLensTests.*`
module was genuinely recompiled; Mathlib oleans came from the existing cache.
No source file was touched between the port's last edit and this run.

```
$ lake build
✔ [3081/3088] Built DistLens.Model (1.8s)
✔ [3082/3088] Built DistLens.Render (1.1s)
✔ [3083/3088] Built DistLens.Verify (5.6s)
✔ [3084/3088] Built DistLens.Extract (5.7s)
✔ [3085/3088] Built DistLens.Widget (2.3s)
✔ [3086/3088] Built DistLens.Demo (4.6s)
✔ [3087/3088] Built DistLens (1.8s)
Build completed successfully (3088 jobs).
exit 0            # 0 lines matching ⚠ / warning: / error:

$ lake test       # first attempt, while four other lake invocations ran concurrently
✔ [3088/3099] Built DistLensTests.Helpers (1.8s)
✔ [3089/3099] Built DistLensTests.TextTests (4.6s)
✔ [3090/3099] Built DistLensTests.RenderTests (4.6s)
✔ [3091/3099] Built DistLensTests.ContractTests (4.7s)
✔ [3092/3099] Built DistLensTests.InvariantTests (4.7s)
✔ [3093/3099] Built DistLensTests.ChainMathTests (4.9s)
✔ [3094/3099] Built DistLensTests.ModelTests (5.0s)
✔ [3095/3099] Built DistLensTests.ExtractTests (5.3s)
✔ [3096/3099] Built DistLensTests.SuggestTests (5.7s)
✔ [3097/3099] Built DistLensTests.VerifyTests (8.5s)
✖ [3098/3099] Building DistLensTests.ClickE2E (105s)
error: Lean exited with code 137
exit 1            # SIGKILL = gotcha 6 (memory), not a test failure

$ lake test       # rerun alone, nothing else building on the machine
✔ [3098/3099] Built DistLensTests.ClickE2E (146s)
✔ [3099/3099] Built DistLensTests (4.5s)
exit 0            # 0 lines matching ⚠ / warning: / error:
```

Net result: `lake build` exit 0 (3088 jobs); `lake test` exit 0 (3099 jobs,
all 12 `DistLensTests.*` modules + the driver rebuilt from scratch, zero
warnings). The exit-137 attempt is kept in the transcript on purpose: it is
the reproducible out-of-memory kill described in gotcha 6 (ClickE2E loads a
full Mathlib environment in-process) and goes away when the suite runs
alone — run `lake test` serially in CI.
