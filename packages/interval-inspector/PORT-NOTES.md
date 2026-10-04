# Port notes — interval-inspector: Lean v4.32.2 → v4.34.0 (QED64 pairing)

Reference (read-only): `../../widgets/interval-inspector` (lean4 v4.32.2,
Mathlib `v4.32.2` = `905b9581`, ProofWidgets `6e311e2a`). Ported tree: this
directory (lean4 v4.34.0, Mathlib `v4.34.0` = `5ed29652`, ProofWidgets
`106ff4fafc74ef4ac99d81dbf3ab399118f497a5`, fresh `lake-manifest.json`; no
`lake update` was run during the port, no Mathlib module was compiled locally).

Result: `lake build` and `lake test` both exit 0 on a clean `.lake/build`
(`rm -rf .lake/build` before the verification run), with **zero warnings** in
either log (`grep -iE 'warning|error|deprecat'` over both logs is empty).
Everything below is the *complete* diff against the reference apart from
`lean-toolchain`, `lakefile.toml` and `lake-manifest.json` (bumped before the
port started). Two harness logs (`cache.log`, `update.log`) that the setup
step left in the package root were removed in the audit follow-up (2026-09-30);
the warning/error grep above was run on them before deletion.

A previous port agent made the three source changes in the "Changes" table
(rows 1–3) and was interrupted before writing this file; every one of them was
re-verified against the pinned sources below, and row 4 (a new test) was added
in this pass.

## Changes

| File | What | Why |
|---|---|---|
| `IntervalInspector/Demo.lean`, `IntervalInspectorTests/CommandTests.lean`, `ReactContractTests.lean`, `RecognizeTests.lean`, `RenderTests.lean`, `SuggestTests.lean` (one `import` line each) and `IntervalInspectorTests/ClickE2E.lean` (`userHeader` plus the 16 embedded user-file sources of the `#assert_click_*` cases) | `import Mathlib.Data.Real.Basic` → `import Mathlib.Basic.Real.Basic`. | Mathlib moved the file on 2026-08-27: `.lake/packages/mathlib/Mathlib/Data/Real/Basic.lean` is now a 4-line shim (`module`, `public import Mathlib.Basic.Real.Basic`, `deprecated_module (since := "2026-08-27")`). The shim still imports, but every importing module — and, in ClickE2E, every recompiled user file — would log a `linter.deprecated.module` warning. The task prefers the new canonical name over deprecated shims. Pure rename; the ClickE2E position pins (`"5:100"`, `"4:73"`, …) are line:column of the *theorem* line and are unchanged (the edited import line is a different line). |
| `IntervalInspector/Recognize.lean` (new `isSetBuilderApp` before `recognizeSetBuilder?`; used there and in the tree recognizer's set-builder branch; two docstrings reworded `setOf` → `Set.ofPred`) | `e.isAppOfArity ``setOf 2` → `isSetBuilderApp e` = `e.isAppOfArity ``Set.ofPred 2 \|\| e.isAppOfArity `setOf 2`. | Mathlib 2026-07-09 renamed `setOf` to `Set.ofPred` (`Mathlib/Data/Set/Defs.lean:67`: `def Set.ofPred …`; line 70: `@[deprecated (since := "2026-07-09")] alias setOf := Set.ofPred`; the `{x \| p x}` term elaborator at lines 143–147 now produces `Set.ofPred fun x ↦ p`). `setOf` is a *distinct* constant (an alias, not a notation), so the old matcher never fires on freshly elaborated terms and all set-builder recognition — the 8 bound mappings, swapped conjuncts, set-builder leaves inside `∪`/`∩`, `∈`/`⊆`/`=`/`Nonempty` forms, the "from set-builder" badge — would have silently returned `none` (≈20 `RecognizeTests` assertions and the dependent Render/Command tests fail). The single-backquote `` `setOf `` fallback is a raw name (no resolution, hence no deprecation warning) and keeps terms spelled with the old constant matching. Behaviour for `{x \| …}` is identical to 4.32.2; the recognizer is strictly more permissive (it additionally accepts explicit `setOf` applications). |
| `IntervalInspectorTests/ClickE2E.lean` (lines 36–42) | `opaque enableInitializersExecutionSafe : IO Unit` → `: BaseIO Unit`; docstring extended. | Core changed `Lean/ImportingFlag.lean:31` from `unsafe def enableInitializersExecution : IO Unit` (4.32.2) to `: BaseIO Unit` (4.34.0). `@[implemented_by]` requires the two types to agree exactly, so the old declaration no longer compiles. The call site is in `IO` and needs no change (`BaseIO` lifts). |
| `IntervalInspectorTests/RecognizeTests.lean` (after the swapped-conjunct `Ico` case, line ~210) | New test: `set_option linter.deprecated false in #assert_shape (setOf fun x : ℝ => 1 ≤ x ∧ x < 2) => "term(Ico*(1,2))"` with a comment. | Covers the `setOf` fallback branch of `isSetBuilderApp`, which no existing test reaches any more (every `{x \| …}` now elaborates to `Set.ofPred`). Verified non-vacuous with a scratch `run_cmd`: `setOf fun x : ℝ => …` elaborates to head constant `setOf` (arity 2) while `{x : ℝ \| …}` elaborates to `Set.ofPred` (arity 2). The `set_option … in` is scoped to this one command, which is the only place the deprecated name is used on purpose. |
| `README.md` | Toolchain pins; `RecognizeTests` bullet mentions the new test; the assertion-census paragraph now states its counting command and the verified numbers; a short "ported from" paragraph. | Versions/counts changed; the old headline numbers (528/141/25/97, "810+") were from an earlier snapshot of the reference and did not state a method. |
| `PORT-NOTES.md` | This file. | Required deliverable. |

Not changed (verified compiling and behaving identically under 4.34.0 without
any edit): `IntervalInspector/Model.lean`, `OrderGraph.lean`, `Layout.lean`,
`Render.lean`, `Suggest.lean` (all 62 table entries and their strings),
`Widget.lean` (`runTermElabM` command, `mk_rpc_widget%` panel,
`interval_inspect?` tactic, `#allow_unused_tactic!` registration),
`IntervalInspector.lean`, `IntervalInspectorTests.lean`,
`IntervalInspectorTests/Helpers.lean`, `ModelTests.lean`, `OrderGraphTests.lean`,
`LayoutTests.lean`, `ImportClosureTests.lean`.

## Pin updates

None. All 24 `#guard_msgs` docstrings (20 `CommandTests`, 4 `Demo.lean`) are
byte-identical to the reference, and so are every ClickE2E
position pin, unsolved-goals pin and tactic-text pin. The only string edits in
the tree are the `Mathlib.Data.Real.Basic` → `Mathlib.Basic.Real.Basic`
replacements inside the ClickE2E user-file sources, which are inputs, not
expected outputs.

## Deviations

None. No test was deleted, commented out or weakened; no feature was dropped
(the 62-entry suggestion table and every whitelist/fallback entry are intact);
no `sorry`; no global option or linter suppression (the single
`set_option linter.deprecated false in` is scoped to one new test command whose
whole point is the deprecated name).

Disposition of the research risk list:

- **62 lemma-name strings in `Suggest.lean`**: all 62 still exist and none is
  deprecated. Proof: `SuggestTests.lean`'s 84 `example`s (one per entry plus
  the instance-gating repros) and the 16 ClickE2E recompiles all elaborate the
  names, and the clean rebuild log carries no `linter.deprecated` warning. A
  textual grep is *not* sufficient on 4.34 Mathlib: e.g. `Set.Ioc_eq_empty`
  has no `theorem` line of its own any more — it is generated by
  `@[to_dual (attr := simp)]` on `Set.Ico_eq_empty`
  (`Mathlib/Order/Interval/Set/Basic.lean:198`). The 2026-06-03 Mathlib rename
  `Iic_diff_Ioc_self_of_le → Iic_sdiff_Ioc_self_of_le` is Finset-side and not in
  the table.
- **Interval-set lemma renames/deprecations at v4.34.0**: none affecting the
  table or the tests' imports (`Mathlib.Order.Interval.Set.{Defs,Basic,LinearOrder}`,
  `Mathlib.Order.Interval.Finset.{Defs,Nat}` carry no `deprecated_module`).
- **InstAvail / `Meta.synthInstance?` gating**: signature unchanged between the
  toolchains; the pinned `#assert_insts` results for ℕ/ℤ/ℝ/ℝ×ℝ and the
  suppression/missing-instance tests pass unchanged.
- **`runTermElabM`**: unchanged; the section-`variable` `#guard_msgs` cases in
  `CommandTests` pass unchanged.
- **ClickE2E frontend APIs**: only the `BaseIO` change above.
  `Parser.parseHeader`, `Elab.processHeader`, `Elab.IO.processCommands`,
  `importModules (loadExts := true)`, the `Lsp.Range` UTF-16 edit application
  and the in-process recompile are source-compatible. The 16 recompiles take
  about 85 s in a clean run.

## Counts

Method (the README's own, now stated there explicitly): count lines that begin
with a compile-time assertion command across `IntervalInspector/` and
`IntervalInspectorTests/`:

```
grep -rhoE '^\s*(#guard_msgs|#guard|#assert_[a-z_]+|example)\b' IntervalInspector IntervalInspectorTests | sed 's/^ *//' | sort | uniq -c
```

| | reference (v4.32.2) | ported (v4.34.0) |
|---|---|---|
| `#guard` | 552 | 552 |
| `#guard_msgs` | 24 | 24 |
| `#assert_shape` | 59 | **60** |
| `#assert_no_shape` | 25 | 25 |
| `#assert_atoms` / `#assert_facts` / `#assert_insts` | 12 / 4 / 4 | 12 / 4 / 4 |
| `#assert_suggests` / `#assert_reports` / `#assert_suppressed` / `#assert_unknown_pairs` | 14 / 10 / 3 / 1 | 14 / 10 / 3 / 1 |
| `#assert_svg_has` / `#assert_svg_lacks` / `#assert_react_contract` | 5 / 4 / 4 | 5 / 4 / 4 |
| `#assert_click_file` / `_goals` / `_closes` / `_broken` | 1 / 10 / 3 / 2 | 1 / 10 / 3 / 2 |
| `example` | 108 | 108 |
| **Total** | **845** | **846** |

Per-file breakdown is identical between the trees except for the one added
`#assert_shape` in `RecognizeTests.lean`. Not in the table but present
identically on both sides: the 3 `throwError` checks of the shadowed-binder
`run_cmd` repro in `RecognizeTests.lean`, and the internal checks of each
ClickE2E command (pin compare, recompile, zero-messages / pinned-error /
negative-control). The reference README's older headline (528 `#guard`, 141
`#assert_*`, 25 `#guard_msgs`, 97 `example`, "810+") reproduces for
`#assert_*` and `example` only after excluding `ReactContractTests`, ClickE2E
and `Demo.lean`, over-counted `#guard_msgs` by one (a prose mention of the
command in `CommandTests`' module docstring; the real figure is 20 + 4 = 24 on
both sides), and did not state its method; the README now does. The
`CommandTests` bullet in the README was corrected from 21 to 20 accordingly.

## 4.34 gotchas worth knowing for QED64

Ground truth: `~/.elan/toolchains/leanprover--lean4---v4.34.0/src/lean/` diffed
against `…v4.32.2/src/lean/`, and the vendored Mathlib under
`.lake/packages/mathlib/`.

1. **`{x | p x}` elaborates to `Set.ofPred`, not `setOf`** (Mathlib
   2026-07-09, `Mathlib/Data/Set/Defs.lean:67-70, 143-147`). `setOf` survives
   as a `@[deprecated] alias`, i.e. a *different constant*. Any `Expr` matcher
   keyed on ``` ``setOf ``` stops matching silently — the pretty-printer still
   shows `{x | …}` (there is an `@[app_unexpander Set.ofPred]`), so nothing in
   the InfoView reveals the mismatch. Match `Set.ofPred` and, if you need to
   accept older terms, add the raw-name fallback `` `setOf `` (single
   backquote: no resolution, no deprecation warning).
2. **New transparency level `implicit`.** `Init/MetaTypes.lean`'s
   `TransparencyMode` gains an `implicit` constructor in 4.34.0 (4.32.2:
   `all | default | reducible | instances | none`), and
   `Lean/ReducibilityAttrs.lean`'s `ReducibilityStatus` gains a distinct
   `instanceReducible` (`[instance_reducible]`, which on 4.32.2 was merely an
   alias of `[implicit_reducible]`). Mathlib marks `Set.ofPred` and `Set.Mem`
   `@[implicit_reducible]` (`Mathlib/Data/Set/Defs.lean:66, 75`). Purely
   syntactic matching (this package) is unaffected, but code that relied on
   `setOf`/membership *not* unfolding at a given transparency may see different
   `whnf`/`isDefEq` results.
3. **`backward.isDefEq.respectTransparency.types` now defaults to `true`**
   (`Lean/Meta/ExprDefEq.lean:57-62`; it was `false` with a "fix stage0" TODO
   in 4.32.2): the check that a metavariable's type matches its assignment's
   type no longer bumps to `.default` transparency. The implicit-argument bump
   logic in `isDefEqArgs` (lines 379–416) was also reworded around
   `implicitBump` for non-instance implicits. `respectTransparency` itself was
   already `true` on 4.32.2. No effect observed here, but it is the first
   place to look if a Mathlib-backed `isDefEq`/unification-heavy tool regresses.
4. **Mathlib module moves ship as `deprecated_module` shims**:
   `Mathlib.Data.Real.Basic` → `Mathlib.Basic.Real.Basic` (2026-08-27). The
   old path still compiles but warns via `linter.deprecated.module`
   (`Lean/DeprecatedModule.lean:20`). For a playground that compiles
   user-supplied files, every template/snippet that says
   `import Mathlib.Data.Real.Basic` needs the new name — here the 16 user
   files embedded in ClickE2E did.
5. **`Lean.enableInitializersExecution : BaseIO Unit`** (was `IO Unit`,
   `Lean/ImportingFlag.lean:31`). An `@[implemented_by]` mirror must match the
   type exactly; callers in `IO` are unaffected. Still required before a nested
   `importModules (loadExts := true)` (`Lean/Compiler/InitAttr.lean:201`).
6. **`to_dual` generates many interval lemmas** in 4.34 Mathlib
   (`@[to_dual]` on `Set.Ico_eq_empty` yields `Set.Ioc_eq_empty`, etc.). Lemma
   whitelists held as strings must be verified by elaboration (`example`s),
   not by grepping for `theorem <name>`.
7. **Mathlib is in the `module` system** (`module` / `public import` headers,
   `meta def` for unexpanders, e.g. `Mathlib/Data/Set/Defs.lean:152`). A
   non-`module` package importing Mathlib — and `lake env lean` on a scratch
   file importing both the package and Mathlib — works as before; nothing had
   to change here.
8. **ProofWidgets `106ff4fa` on 4.34.0** needed no source changes: the `Html`
   DSL, `mk_rpc_widget%`, `MakeEditLink`, `savePanelWidgetInfo` and the panel
   RPC are source-compatible with the `6e311e2a` pin.
9. **`Meta.synthInstance?`, `runTermElabM`, `#allow_unused_tactic!`** are
   unchanged in signature and behaviour on this package's instance pins
   (ℕ/ℤ/ℝ/ℝ×ℝ availability of `DenselyOrdered`/`NoMinOrder`/`NoMaxOrder`/
   `DivisionRing`).
