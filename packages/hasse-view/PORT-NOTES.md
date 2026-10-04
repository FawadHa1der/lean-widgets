# Port notes — hasse-view: Lean v4.32.2 → v4.34.0 (QED64 pairing)

Reference (read-only): `../../widgets/hasse-view` (lean4 v4.32.2, Mathlib
`v4.32.2` = `905b9581`, ProofWidgets `6e311e2a`). Ported tree: this directory
(lean4 v4.34.0, Mathlib `v4.34.0` = `5ed29652`, ProofWidgets
`106ff4fafc74ef4ac99d81dbf3ab399118f497a5`, fresh `lake-manifest.json`; no
`lake update` was run during the port, Mathlib oleans came from
`lake exe cache get`).

Result: `lake build` and `lake test` both exit 0 on a clean `.lake/build`
(`rm -rf .lake/build` before the final run), with **zero warnings** in either
log (`grep -c "⚠\|warning:"` = 0 on both). The package needed **no code
change at all**: every module of `HasseView/` and `HasseViewTests/` compiles
and every pin holds byte-for-byte on v4.34.0. The complete diff against the
reference (besides `lean-toolchain`, `lakefile.toml`, `lake-manifest.json`,
which were bumped before the port started) is three documentation edits.

Second verification pass (2026-09-30, after the first port agent was
interrupted): `diff -rq` against the reference re-confirmed the three
documentation-only edits; `rm -rf .lake/build && lake build && lake test`
both exited 0 with zero `warning:`/`⚠` lines and zero `Built Mathlib` jobs
(no Mathlib recompilation); the static census below was re-counted on both
trees with the stated greps (349 / 12 / 4 / 11, identical); and the 98
executed `check`/`checkEqStr` calls were re-measured with a fresh
instrumented copy of `ClickE2E.lean` run through `lake env lean`
(98 `E2E_MARK` lines, exit 0). One factual error in gotcha 1 was corrected
(see there).

Third pass (2026-09-30, audit follow-up): gotcha 1 corrected again after
re-grepping the vendored trees — the three new overrides on this package's
import path (`Divisors.lean:364,378`, `Fintype/Card.lean:273`) are the base
`respectTransparency false` form, not `.types`; the `.types` lines under
`Order/` number 24 (not 25) and live in eight files that do not include
`Atoms`; the approximate headline figures were replaced by exact counts
(4,567 / 2,416 / 5,589 / 1,978). Documentation only; no source, test or
pin was touched.

## Changes

| File | What | Why |
|---|---|---|
| `HasseView/Links.lean` (module docstring) | "Mathlib (v4.32.2 pin) only makes `· ⋖ ·` decidable for `Bool`" → "v4.34.0 pin". | The claim was re-verified against the vendored Mathlib: `Mathlib/Order/Cover.lean` still has only `instDecidableRelWCovBy` / `instDecidableRelCovBy` for `Bool` (lines 505/508), and a grep of all of `Mathlib/` finds no other `DecidableRel (· ⋖ ·)` instance. The package's `instDecidableRelCovByOfFintype` is therefore still needed and still unique. Version string only. |
| `HasseView/Extract.lean` (module docstring, item 2) | "in v4.32.2 `DecidableLE V` is a reducible abbreviation" → "in v4.34.0". | `Init/Prelude.lean:1302` in the v4.34.0 toolchain: `abbrev DecidableLE (α : Type u) [LE α] := DecidableRel (LE.le : α → α → Prop)` — unchanged from v4.32.2 (line 1296 there). Version string only. |
| `README.md` | Same `DecidableLE` version string; new paragraph under "Verifying" with the toolchain/Mathlib/ProofWidgets pins and the assertion-census method (the reference README states 463 but never says how it counts; the method is now written down, see Counts). | Versions changed; counts made reproducible. |
| `PORT-NOTES.md` | This file. | Required deliverable. |

Not changed (verified compiling and behaving identically under 4.34.0
without any edit): `HasseView/Model.lean`, `Layout.lean`, `Render.lean`,
`Gate.lean`, `Widget.lean`, `Demo.lean`, `HasseView.lean`,
`HasseViewTests.lean` and all ten test modules (`Helpers`, `ModelTests`,
`LayoutTests`, `RenderTests`, `OverlayTests`, `ContractTests`,
`PropertyTests`, `CommandTests`, `LinkTests`, `ClickE2E`). No `set_option`
was added anywhere, no lemma was renamed, no module import moved.

## Pin updates

None. All 29 `#guard_msgs` docstrings (26 in `CommandTests.lean`: the
`(text := true)` reports for `Fin 5` / `Bool` / `Bool × Bool` /
`Finset (Fin 3)` / `Div12` / `Bowtie` / the overlay variants, and every
user-facing error including the noncomputable-instance rejections that name
`Classical.propDecidable` and `HasseViewTests.ncFintype`; 3 in
`LinkTests.lean`: the `#links_report` gate verdicts for `Fin 3`, `Div12`,
`Bowtie`) pass unchanged, as do all byte-exact `#guard` pins (text reports,
SVG fragments, layout coordinates, serialized `MakeEditLink` component nodes
with their `newText`/uri/version/range JSON) and the five
`#compile_insertions … expecting n` acceptance counts (6 / 14 / 6 / 8 / 0).

## Deviations

None. No test was deleted, commented out or weakened; no feature was dropped
(the `⋖` instance, all three link kinds, the honesty gate, the 32-cover cap
and the 64-element cap are all intact); no `sorry`; no global or scoped
option/linter suppression; no behaviour change.

## Counts

Method (reconstructed so that it reproduces the reference README's own
"463 compile-time assertions (plus 11 statically compiled generated-example
texts)" and "`ClickE2E.lean` adds 114" exactly, and now written into the
README): lines starting with `#guard`, `#guard_msgs`, `#assert_*` or
`#compile_insertions` in `HasseViewTests/*.lean` and `HasseViewTests.lean`
excluding `ClickE2E.lean`, plus for `ClickE2E.lean` its `#guard` lines, the
`check`/`checkEqStr` calls its two `#eval` suites *execute*, and its
`let some … | throw` payload assertions. `#links_report` commands are not
counted separately (each is the subject of a counted `#guard_msgs`), and the
11 `example : … := by decide` lines of `LinkTests.lean` are reported
separately, as in the reference README.

Static part, counted with
`grep -cE '^#guard(\s|$)' …`, `grep -cE '^#guard_msgs' …`,
`grep -cE '^#assert_' …`, `grep -cE '^#compile_insertions' …`:

| | reference (v4.32.2) | ported (v4.34.0) |
|---|---|---|
| `#guard` (all files except `ClickE2E`) | 282 | 282 |
| `#guard_msgs` | 29 | 29 |
| `#assert_poset_invariants` / `#assert_extracts_to` / `#assert_label_*` / `#assert_stmt_*` | 33 | 33 |
| `#compile_insertions` | 5 | 5 |
| **static subtotal** | **349** | **349** |
| `ClickE2E`: `#guard` lines | 12 | 12 |
| `ClickE2E`: executed `check` / `checkEqStr` calls | 98 | 98 |
| `ClickE2E`: `let some … \| throw` payload assertions | 4 | 4 |
| **ClickE2E subtotal** | **114** | **114** |
| **Total** | **463** | **463** |
| (separately) static `example : … := by decide` lines | 11 | 11 |

The executed-call figure (98) was measured, not estimated: an instrumented
copy of `ClickE2E.lean` (only change: `check` and `checkEqStr` print a marker
line) was run through `lake env lean` on the ported tree and the marker was
counted (49 from `cubeSuite`, 49 from `uniSuite`). The static counts were
produced by the same command on both trees; per-file numbers are identical
line for line because the test sources are byte-identical.

## 4.34 gotchas worth knowing for QED64

Ground truth: `~/.elan/toolchains/leanprover--lean4---v4.34.0/src/lean/`
diffed against `…v4.32.2/src/lean/`, and this tree's
`.lake/packages/{mathlib,proofwidgets}` diffed against the reference's.

1. **`backward.isDefEq.respectTransparency.types` flipped `false` → `true`**
   (`Lean/Meta/ExprDefEq.lean:57`; the base
   `backward.isDefEq.respectTransparency` was already `true` on 4.32.2 and
   still is). Types during metavariable assignment are now compared at
   *implicit* transparency, and the transparency ladder gained a level
   (`none < reducible < instances < implicit < default < all`,
   `Init/MetaTypes.lean`). **Effect on this package: none observed.** The
   risk-list items — `instDecidableRelCovByOfFintype` resolution,
   `DecidableLE` resolution for `Fin n` / `Bool` / `Bool × Bool` /
   `Finset (Fin n)` / the hand-written `Div12` and `Bowtie` instances, and
   the `Fintype`/`DecidableEq` synthesis in `extractPosetData` — all resolve
   exactly as before: every `by decide` in `LinkTests.lean` closes, all five
   `#compile_insertions` counts hold, every `#assert_stmt_holds` /
   `#assert_stmt_rejected` (including the `Classical`-noncomputable
   rejection) holds, and all 14 + 8 ClickE2E insertions recompile clean.
   How much Mathlib itself had to bend (measured by grepping both vendored
   trees with `grep -rhE 'set_option backward\.isDefEq\.respectTransparency
   false'` / `…respectTransparency\.types false'` over `Mathlib/**/*.lean`;
   corrected in the second verification pass — an earlier draft of this
   note mislocated the overrides in `Order/Basic.lean` — and re-counted
   exactly in the third pass): the ported Mathlib carries 4,567 scoped
   `set_option backward.isDefEq.respectTransparency false in` lines and
   2,416 *new* `set_option backward.isDefEq.respectTransparency.types
   false in` lines (the reference has 5,589 of the former and zero of the
   latter), spread over 1,978 files. On this package's direct import path
   the overrides that are *new relative to the reference* are
   `Mathlib/NumberTheory/Divisors.lean:364,378`
   (`map_div_right_divisors` / `map_div_left_divisors`) and
   `Mathlib/Data/Fintype/Card.lean:273` (`card_range_le`) — all three are
   the **base** `set_option backward.isDefEq.respectTransparency false in`
   form, not the `.types` variant (the reference Mathlib has no override at
   all on these three lemmas; an earlier draft of this note wrongly called
   them `.types` lines). There is no override of either kind in
   `Order/Cover.lean`, `Data/Finset/Sort.lean`, `Data/Fintype/{Basic,
   Powerset,Prod}.lean`, `Data/Quot.lean` or `Data/Rat/Defs.lean`, and no
   `.types` override anywhere under `Data/Finset` or `Data/Fintype`. Under
   `Order/` there are 24 `.types` `set_option` lines in eight files —
   `PiLex` (14), `RelSeries` (2), `JordanHolder` (2),
   `DirectedInverseSystem` (2), `BourbakiWitt` (1, plus one comment
   mentioning the option at line 260), `Category/NonemptyFinLinOrd` (1),
   `SuccPred/LinearLocallyFinite` (1), `Lattice/Nat` (1) — none imported
   here (an earlier draft listed `Atoms`, which has none). So a QED64
   package with hand-rolled order
   instances should expect to add the same scoped override on individual
   declarations — never globally — if an `inferInstanceAs` or
   `decidable_of_iff` instance stops being found; Mathlib's own
   `#defeq_abuse in` command (`Mathlib/Tactic/DefEqAbuse.lean`) runs a
   tactic/command under both settings and reports which one it needs.
2. **Mathlib re-tagged `Fintype.subtype` and `Fintype.ofFinset` from
   `@[implicit_reducible]` to `@[instance_reducible]`**
   (`Mathlib/Data/Fintype/Defs.lean:268-277`), and likewise one declaration
   in `Mathlib/Data/Fintype/Prod.lean`. The `Div12` demo builds its
   `Fintype` via `.subtype (Nat.divisors 12) …`; extraction, labels and the
   `#assert_extracts_to Div12` byte-for-byte pin are unaffected because the
   package only ever *evaluates* these instances through `evalExpr`, never
   unfolds them in `isDefEq`. Packages that `rfl`/`decide` *through* a
   `Fintype.subtype` instance (rather than evaluating it) may see the new
   tag matter.
3. **New Mathlib instance in the `DecidableLE` search space:**
   `instance [∀ a, LE (β a)] [∀ a, DecidableLE (β a)] [Fintype α] :
   DecidableLE (∀ a, β a)` (`Mathlib/Data/Fintype/Defs.lean:217`). It
   widens what `#hasse` accepts (finite function types under the pointwise
   order now have a computable `DecidableLE`), and does not interfere with
   the existing resolutions. Not exercised by the suite; worth a demo/test
   in a future round rather than in a port.
4. **`Mathlib/Order/Cover.lean` renames** (none used here, but a QED64
   suggestion table built on cover lemmas will hit them):
   `not_covBy` (the `DenselyOrdered` version) is now
   `not_covBy_of_denselyOrdered`, and a *new* general
   `not_covBy : ¬a ⋖ b ↔ a < b → ∃ c, a < c ∧ c < b` took the old name;
   the `CovBy.irrefl : Std.Irrefl` instance was replaced by an anonymous
   `Std.Asymm (· ⋖ ·)` instance and `WCovBy.stdRefl` by an anonymous
   `Std.Refl` (plus a new `Std.Antisymm (· ⩿ ·)`); new
   `WCovBy.of_isLUB_Iio` / `top_wcovBy_iff`. The `Bool` decidability
   instances (the reason this package ships its own) are unchanged.
   `lt_iff_le_not_ge` (used by `instDecidableRelCovByOfFintype`) is still
   the canonical name (`Mathlib/Order/Defs/PartialOrder.lean:75`), not
   deprecated.
5. **Other Mathlib renames adjacent to this package's imports:**
   `Finset.setOf_mem` → `Finset.setOfPred_mem` (deprecated alias kept,
   since 2026-07-09); `Finset.isWellFounded_ssubset` is now stated with
   `@WellFounded` instead of `IsWellFounded`; `Nat.mem_divisors` (used by the
   `Div12` demo's `Fintype.subtype` proof) is unchanged at
   `Divisors.lean:108`; `Mathlib/Data/Fintype/Prod.lean` dropped the
   deprecated `toFinset_off_diag` alias. `Finset`'s unsafe `Repr` instance
   (`Mathlib/Data/Finset/Sort.lean:321`, `∅` for the empty set) is
   unchanged, so the `{0, 1}`-style labels and the round-trip gate results
   are identical.
6. **Core `evalExpr` / `evalExpr'` (`Lean/Meta/Eval.lean`) and
   `Lean/Widget/UserWidget.lean` (`savePanelWidgetInfo`) are byte-identical
   between the two toolchains** — the `safety := .unsafe` pattern, the
   noncomputable-instance rejection via `isNoncomputable` +
   `getUsedConstants`, and the panel-props storage need nothing.
7. **The in-process frontend used by `ClickE2E` still works unchanged**:
   `Parser.parseHeader` (`Lean/Parser/Module.lean`, unchanged) →
   `Elab.processHeader` (`Lean/Elab/Import.lean`: only the
   `deprecated_module` position bookkeeping changed) →
   `Elab.IO.processCommands` (`Lean/Elab/Frontend.lean`: the diff is the
   `.ir.sig` artifact chain and a `setMainModule` patch for loaded
   snapshots, neither on this path). `enableInitializersExecution` changed
   type from `IO Unit` to `BaseIO Unit` (`Lean/ImportingFlag.lean:31`) —
   harmless at a `do`-block call site inside `IO`, but a QED64 harness that
   stores it in a typed variable would need the new type.
   `Lean.Server.replaceLspRange` and `Lsp.Position.advance` moved into the
   `Lean.IO` / `Lean.String` / `Lean.Char` namespaces
   (`Lean/Server/Utils.lean`, `Lean/Data/Lsp/Utf16.lean`) but keep the same
   fully-qualified names this package uses; all seven UTF-16 pins (`ℝ`,
   `😀`, `⋖`, surrogate-pair `𝓑` type name) hold.
8. **ProofWidgets `106ff4fa` vs `6e311e2a`:** the only diff among the
   modules this package imports is in `Component/MakeEditLink.lean`, which
   now carries a private `ProofWidgets.Internal.utf16Size` instead of
   calling core's `Char.utf16Size` (a shim for core's namespace move in
   item 7). `MakeEditLinkProps.ofReplaceRange`'s cursor placement is
   unchanged — the `⟨7, 35⟩` hand-counted UTF-16 pin still holds.
   `OfRpcMethod.lean` (`mk_rpc_widget%`), `HtmlDisplay.lean`, `Data/Html.lean`
   and `Component/Basic.lean` are byte-identical.
9. **Zsh + paths with spaces.** Every `cd`/`diff`/`grep` in this port had to
   quote `…/lean questions/…`; `grep --include=*.lean` needs quoting too
   (`no matches found` otherwise). Not a Lean gotcha but it bit twice.
