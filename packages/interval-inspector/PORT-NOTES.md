# Port notes — interval-inspector: Lean v4.32.2 → v4.34.0 → v4.35.0 (QED64 pairing)

Two ports, newest first: v4.34.0 → v4.35.0 (next section) and the earlier
v4.32.2 → v4.34.0 (last section).

## Lean 4.34.0 → 4.35.0 (2026-10-25)

Result: **no source change was needed.** `lake build` and `lake test` both exit
0 on Lean v4.35.0 / Mathlib v4.35.0 with the tree exactly as it was at
`qed64-pin-i` (apart from the harness's pin bump). Every `#guard_msgs`
docstring, every ClickE2E pin (inserted tactic text, edited-file pin, cursor
`line:char`, exact unsolved-goals reports) and both negative controls pass
unchanged. The only new build output is Lake's per-import module-system warning
(below), which is expected and was left alone.

### Pins (set by the harness, not by this port)

| | 4.34 port (`qed64-pin-i`) | this port |
|---|---|---|
| `lean-toolchain` | `leanprover/lean4:v4.34.0` | `leanprover/lean4:v4.35.0` |
| Mathlib (`lakefile.toml` rev / manifest) | `v4.34.0` = `5ed29652` | `v4.35.0` = `56a005855ea17e0b0958f73ec801ae140b0a1679` |
| ProofWidgets (transitive, via Mathlib) | `106ff4fafc74ef4ac99d81dbf3ab399118f497a5` | `df72b022e558978a1c50264cfc4d7fec86fa8e04` |
| Batteries / Aesop / Qq / plausible / importGraph / LeanSearchClient / Cli | Mathlib v4.34.0's | `66e46918…` / `4a174c49…` / `dce0ad79…` / `dfa4f381…` / `a41f0e9a…` / `d6b4c7be…` / `c24fe607…` (v4.35.0) — equal to Mathlib v4.35.0's own manifest |

The harness ran one `lake update` and then one `lake exe cache get`; nothing in
this port changed dependencies. The 9031 Mathlib v4.35.0 cache files were
downloaded and decompressed by the `lake update` step, through Mathlib's
post-update hook (`port435/interval-inspector.update.log`: "Attempting to
download 9031 file(s)" … "Decompressed 9031 file(s)"). This was the first
Mathlib-dependent package in the harness order. The explicit `cache get` that
followed then had nothing to do (`port435/interval-inspector.cache.log`: "No
files to download" / "Already decompressed 9031 file(s)").

### Changes

| File | What | Why |
|---|---|---|
| `README.md` ("Toolchain" section; one clause in the assertion-census paragraph) | Pins updated to Lean v4.35.0 / Mathlib v4.35.0 (`56a00585`) / ProofWidgets `df72b022`; a paragraph stating the 4.35 port needed no source change; census marked identical on v4.34.0 and v4.35.0. Post-audit: the module-system warning sentence now names its cause. | Required deliverable; versions changed. |
| `PORT-NOTES.md` | This section (and a heading separating the earlier 4.32.2 → 4.34.0 notes below it). Post-audit: the title, the *Pins* cache sentence, gotcha 1, and the old notes' heading levels. See *Post-audit fixes*. | Required deliverable. |

The port itself edited no `.lean` file: at the port, `git diff qed64-pin-i --
packages/interval-inspector` showed only `lean-toolchain`, `lakefile.toml`,
`lake-manifest.json` (harness) and the two Markdown files above. The later
gap-closing pass (*Gap-closing tests* below) added tests to
`IntervalInspectorTests/SuggestTests.lean` and
`IntervalInspectorTests/CommandTests.lean`. No library file changed.

### Golden / expected-output changes

None. All 24 `#guard_msgs` docstrings (20 in `CommandTests`, 4 in `Demo.lean`)
and all ClickE2E pins are byte-identical to `qed64-pin-i`. The module-system
warning does not reach any of them (see gotcha 1), so no test-harness-side
handling was needed either.

### Deviations

None. The port touched no test, assertion or scenario; no `sorry`, no option, no
`module` conversion (house rule: the files stay non-`module` for the
showcase's QED64 embedding). The later gap-closing pass only added tests.

### Counts

Same method as the 4.34 section below (and the README):

```
grep -rhoE '^\s*(#guard_msgs|#guard|#assert_[a-z_]+|example)\b' IntervalInspector IntervalInspectorTests | sed 's/^ *//' | sort | uniq -c
```

Before = the `qed64-pin-i` tree (extracted with `git archive qed64-pin-i …`);
after = this tree. Per-command tallies are identical:

| | before (v4.34.0) | after (v4.35.0) |
|---|---|---|
| `#guard` | 552 | 552 |
| `#guard_msgs` | 24 | 24 |
| `#assert_*` (16 kinds; incl. 60 `#assert_shape`, 25 `#assert_no_shape`, 14 ClickE2E happy-path = 1 `_file` + 10 `_goals` + 3 `_closes`, 2 `_broken` negative controls) | 162 | 162 |
| `example` | 108 | 108 |
| **Total** | **846** | **846** |

After the gap-closing tests (same command, working tree): 552 `#guard`,
24 `#guard_msgs`, 172 `#assert_*` (17 kinds: `#assert_reports` 10 → 16, new
`#assert_panel_items` × 4) and 109 `example`, for a total of **857**.

Plus, unchanged on both sides, the 3 `throwError` checks of the
shadowed-binder `run_cmd` repro in `RecognizeTests.lean` and the internal checks
of the 16 ClickE2E click simulations.

### 4.35 gotchas (for a future porter)

1. **The "imports `X` from package `mathlib`, which is designed for use with
   the module system; consider adding `module`" warning is emitted by Lake, not
   by Lean** (`lake/Lake/Build/Module.lean:416-424` in the v4.35.0 toolchain:
   one `logWarning` per direct Mathlib import of a non-`module` file, because
   Mathlib's lakefile sets `requiresModuleSystem := true`). The check is not
   new in 4.35. It is byte-identical in v4.34.0 (`Module.lean:404-411`), and
   `requiresModuleSystem` / `allowNonModules` already existed there
   (`Lake/Config/LeanConfig.lean`). Lake warns whenever a non-`module` file
   imports a module of *any* package or library that sets the option. What is
   new is Mathlib's side: its v4.35.0 `lakefile.lean:69` adds
   `requiresModuleSystem := true` to `package mathlib`, and its v4.34.0
   lakefile (`5ed29652`) did not have it. No other dependency here (Batteries,
   ProofWidgets `df72b022`, Aesop, Qq, plausible, importGraph,
   LeanSearchClient, Cli) sets it. The warning never enters
   Lean's `MessageLog`, so `#guard_msgs` blocks and ClickE2E's in-process
   frontend (`Parser.parseHeader` → `Elab.processHeader` →
   `Elab.IO.processCommands`) do not see it: the user files ClickE2E recompiles
   import `Mathlib.Basic.Real.Basic` without the warning showing up in their
   messages (ClickE2E pins errors only in any case). Here: 10 such warnings in
   `lake build` (Model 1, Recognize 5, Suggest 1, Widget 1, Demo 2), 19 in
   `lake test` (those 10 replayed + CommandTests 1, ReactContractTests 1,
   RecognizeTests 3, RenderTests 1, SuggestTests 3). The opt-out is
   `allowNonModules := true` on the importing package/library — a
   `lakefile.toml` change, deliberately not made here (lakefiles are
   harness-owned).
2. **ProofWidgets `106ff4fa` → `df72b022` has no source change at all**: the
   seven commits between the pins only bump `lean-toolchain` (rc1 … v4.35.0)
   and CI workflow files (`git diff --stat` touches `.github/workflows/build.yml`
   and `lean-toolchain` only). `Html`/`MakeEditLink`/`savePanelWidgetInfo`/
   `mk_rpc_widget%` behave identically.
3. **The core frontend APIs ClickE2E uses are byte-identical between v4.34.0
   and v4.35.0**: `Lean/Elab/Import.lean`, `Lean/Parser/Module.lean`,
   `Lean/ImportingFlag.lean` (`enableInitializersExecution : BaseIO Unit`
   unchanged), `Lean/Data/Lsp/Utf16.lean`, `Lean/Elab/InfoTree/Main.lean`.
   `Lean/Elab/Frontend.lean` only gained code-quality-log merging in
   `runFrontend` (not used here); `Lean/Server/Utils.lean` only swapped an
   import (`DocumentMeta` fields unchanged). `Lean/Widget/UserWidget.lean`
   changed the duplicate-widget-hash warning text from `hash(JS source code)`
   to `hash (JS source code)` — irrelevant here (nothing pins it), but a
   `#guard_msgs` that pins that warning elsewhere would need the new spacing.
4. **4.34's Mathlib facts still hold at v4.35.0**: `{x | p x}` still
   elaborates to `Set.ofPred` and `setOf` is still a
   `@[deprecated (since := "2026-07-09")] alias`
   (`Mathlib/Data/Set/Defs.lean:65, 68, 141-145`), so `isSetBuilderApp` and the
   `setOf` fallback test keep working; `Mathlib.Data.Real.Basic` is still the
   `deprecated_module` shim for `Mathlib.Basic.Real.Basic`. None of the 61
   distinct `Set.*` lemma names in `Suggest.lean` has a deprecated alias in
   `Mathlib/Order` or `Mathlib/Data/Set` at v4.35.0, and the elaborating
   `SuggestTests` examples plus the 16 ClickE2E recompiles produced no
   `linter.deprecated` warning.
5. The QED64-relayed 4.35 changes (`@[inherit_doc]` no longer warning, enum
   `deriving Fintype` still needing `backward.isDefEq.respectTransparency
   false`, the 87 dropped modules) do not touch this package: it uses no
   `inherit_doc`, derives no `Fintype`, and imports none of the dropped modules.
6. Timing: the whole `lake test` (library already built) took 1 m 02 s wall on
   4.35, of which ClickE2E was 55 s (≈85 s on 4.34 in a clean run).

### Post-audit fixes (2026-10-25)

The adversarial audit passed this package. All 7 source mutations were caught,
the clean rebuild was green, and the counts matched (846 = 846). It raised
three minor findings. This pass edited only this file and `README.md`; no
`.lean` file, test or expected output was touched.

| Finding | Fix |
|---|---|
| The H1 title named only the v4.32.2 → v4.34.0 port, although the file now starts with the 4.35 section. | Retitled to cover both ports, with a one-line guide below it. Also, the previous port's own subheadings (`Changes`, `Pin updates`, `Deviations`, `Counts`, `4.34 gotchas …`) were demoted from `##` to `###`. They now sit under "Lean 4.32.2 → 4.34.0 (previous port)" instead of beside it, so the file no longer has two `Changes` / `Deviations` / `Counts` sections at different levels. |
| *Pins* said the harness's `cache get` downloaded 9031 Mathlib files, but the cache log reads "No files to download". | Rewritten from the harness logs. The 9031 files *were* downloaded, but by the `lake update` step: Mathlib's post-update hook runs `cache get` (`port435/interval-inspector.update.log`), and this was the first Mathlib-dependent package in the harness order. The explicit `cache get` that ran afterwards found nothing to do (`interval-inspector.cache.log`). The audit's reading ("already in the cache") is right for that explicit step only. |
| `SuggestTests`: the `DenselyOrdered` gate on the `Ioo` branch of the `≠ ∅` suggestion is pinned by a single pure `#guard` (mutation M7). No end-to-end test runs an ℕ statement such as `Set.Ioo (0:ℕ) 2 ≠ ∅` through the pipeline. | **Fixed by the gap-closing pass below** (the gap predates the port). New end-to-end tests run `Set.Ioo (0:ℕ) 2 ≠ ∅` in three spellings through the pipeline (`#assert_reports`) and through the real `#interval_inspect` panel (`#assert_panel_items`), against `Ico`-over-ℕ and ℚ/ℝ controls. M7 now fails 5 more assertions. |

Two related edits:

- Gotcha 1 now states the cause of the module-system warning precisely: Lake's
  check is unchanged since v4.34.0, and Mathlib v4.35.0 newly sets
  `requiresModuleSystem := true`. The README's warning sentence says the same.
- Counts were recounted mechanically with the method above on the
  `qed64-pin-i` tree, the working tree and the v4.32.2 original (repository
  tag `lean-v4.32.2`, extracted with `git archive`): 552 `#guard`,
  24 `#guard_msgs`, 162 `#assert_*` and 108 `example`, giving 846 on both 4.34
  and 4.35 (845 at v4.32.2). A second, comment- and string-aware count (block
  comments, docstrings and `--` comments stripped first) agrees. The method
  covers the two directories only, so the root `IntervalInspectorTests.lean`
  is not in the 846. That file holds one more `#guard`
  (`IntervalInspector.version = "0.1.0"`) in all three trees.

### Verification transcript

Lake invocations, all through the shared lock wrapper (`BROWSER_LOCK_DIR=$HOME/.cache/lean-widgets-build-lock MIN_FREE_GB=10 LOCK_WAIT_S=43200 COOLDOWN_WAIT_S=7200 bash ".../widgets-v4.34/qed64-showcase/scripts/with-browser-lock.sh" <tag> bash -c 'cd ".../packages/interval-inspector" && <cmd>'`):

- Harness, `port435-build-interval-inspector`, `lake build` (first 4.35 build;
  all 9 `IntervalInspector*` modules compiled fresh, "Built", not replayed):
  `Build completed successfully (895 jobs).` / `browser-lock: command exited rc=0`.
- `port435-interval-inspector-build`, `lake build`:
  ```
  ⚠ [893/895] Replayed IntervalInspector.Demo
  Build completed successfully (895 jobs).
  browser-lock: command exited rc=0
  ```
  exit 0; 10 Lake module-system warnings, 0 other warnings/errors.
- `port435-interval-inspector-test`, `time lake test` (all 11 test modules and
  the `IntervalInspectorTests` root compiled fresh on 4.35, "Built"):
  ```
  ✔ [1014/1025] Built IntervalInspectorTests.ImportClosureTests (3.4s)
  ✔ [1024/1025] Built IntervalInspectorTests.ClickE2E (55s)
  ✔ [1025/1025] Built IntervalInspectorTests (1.4s)
  real	1m2.311s
  browser-lock: command exited rc=0
  ```
  exit 0; 19 Lake module-system warnings, 0 other warnings/errors
  (`grep -iE 'warning|error|deprecat' | grep -v 'designed for use with the module system'`
  is empty over both logs).

- **Post-audit verification (2026-10-25)**, through the same wrapper (`BROWSER_LOCK_DIR=$HOME/.cache/lean-widgets-build-lock MIN_FREE_GB=<10|20> LOCK_WAIT_S=43200 COOLDOWN_WAIT_S=7200 bash ".../widgets-v4.34/qed64-showcase/scripts/with-browser-lock.sh" <lane> …`):
  1. Lane `port435-fix-interval-inspector-buildtest` (`MIN_FREE_GB=20`): `lake build`
     printed `Build completed successfully (895 jobs).` with rc 0, and `lake test` gave
     rc 0. Everything was replayed, with the expected 10 + 19 module-system warnings.
  2. Lane `port435-fix-ii-ts-ex-ck-cleanfinal` (`MIN_FREE_GB=20`) first deleted this
     package's own outputs, `.lake/build/{lib/lean,ir}/IntervalInspector*`, leaving
     0 entries; `.lake/packages` was not touched. It then ran `lake build` and
     `time lake test`. All 21 own modules were rebuilt: the 9 library modules, the 11 test
     modules and the test root, including ClickE2E's 16 recompiles.
     ```
     ✔ [894/895] Built IntervalInspector (763ms)
     Build completed successfully (895 jobs).
     ### lake build rc=0
     ✔ [1024/1025] Built IntervalInspectorTests.ClickE2E (49s)
     ✔ [1025/1025] Built IntervalInspectorTests (1.2s)
     real	0m52.753s
     ### lake test rc=0
     browser-lock: command exited rc=0
     ```
     The log has 29 module-system warnings (10 in the build, 19 in the test, as in gotcha 1)
     and 0 other warning, error or deprecation lines.

  Both runs were made after the documentation edits. Any later edit in this pass touched only Markdown files, which are not Lake inputs. `git status` lists no change under this package besides `PORT-NOTES.md`, `README.md` and the three harness files.

### Gap-closing tests (2026-10-25)

This pass closes the audit's one test-coverage gap (the `DenselyOrdered` gate on
the `Ioo` branch of `neEmptyOf`, `Suggest.lean:398`, covered only by the pure
`#guard` at `SuggestTests.lean:648`). It only adds tests. No library file, existing
test or expected output changed; `shasum` of `IntervalInspector/*.lean` is
unchanged.

Added (11 counted assertions, 846 → 857):

- `SuggestTests.lean` (instance gating, end to end, after the
  `(Set.Ioo (0:ℕ) 2).Nonempty` repro): 6 `#assert_reports` on the real pipeline
  (`analyzeWithLCtx?`). Over ℕ, `Set.Ioo (0:ℕ) 2 ≠ ∅`, `(∅ : Set ℕ) ≠ Set.Ioo 0 2`
  and `¬(Set.Ioo (0:ℕ) 2 = ∅)` must report `[missing instance: DenselyOrdered]`
  and no `[ALL-READY]`. The controls `Set.Ico (0:ℕ) 2 ≠ ∅` (the gate is `Ioo`-only),
  `Set.Ioo (0:ℚ) 2 ≠ ∅` and `Set.Ioo (0:ℝ) 2 ≠ ∅` must be unmarked and
  `[ALL-READY]`. There is also 1 `example`: the ℕ statement is true, but
  `fail_if_success` shows that `(Set.nonempty_Ioo.mpr _).ne_empty` cannot prove
  it over ℕ.
- `CommandTests.lean` (new namespace `CommandPanelTests`): a local
  `#assert_panel_items` command runs the real panel-mode `#interval_inspect e`
  through a nested `elabCommand`. It reads the single stored `HtmlDisplayPanel`
  widget out of the info tree, decodes its `html` prop with `RpcEncodable`, and
  pins the suggestion rows. There are 4 uses: ℕ `Ioo` in both orientations (the
  rows must include `[missing instance: DenselyOrdered ✗]`), and ℕ `Ico` and ℝ
  `Ioo` (no badge).

Mutation proofs. For each mutation: copy the file, apply one exact replacement,
run `lake build IntervalInspectorTests.SuggestTests IntervalInspectorTests.CommandTests`
under the lock, restore from the copy, and check that `shasum` matches. All five
files were restored byte-identical.

| Mutation | Build | Failing assertions |
|---|---|---|
| **M7 (the surviving one)**: `Suggest.lean:398` `needs := if k == .Ioo then #[.denselyOrdered] else #[] }` → `needs := #[] }` | rc 1 | new `SuggestTests` 749, 752, 755 (ℕ: actual `… — refine (Set.nonempty_Ioo.mpr ?_).ne_empty [ALL-READY]`) and new `CommandTests` 248, 251 (badge gone), plus the old `#guard` at 648. The controls stay green. |
| Gate overshoot: same line → `needs := #[.denselyOrdered] }` (also gates `Ico`/`Ioc`) | rc 1 | only the new `SuggestTests` 764 and `CommandTests` 255 (ℕ `Ico`). No older test catches this mutation. |
| Gate ignores availability: `Suggest.lean:571` `let unmet := m.needs.filter fun n => !inst.has n` → `let unmet := m.needs` | rc 1 | the new dense controls `SuggestTests` 768 (ℚ) and 771 (ℝ) and `CommandTests` 258 (ℝ), plus 11 older `SuggestTests` assertions |
| Panel drops instance badges: `Widget.lean:94` `… ++ condBadges ++ instBadges)` → `… ++ condBadges)` | rc 1 | only the new `CommandTests` 248 and 251. No older test catches this mutation. |
| Test-side vacuity check on the new `example`: statement type `ℕ` → `ℝ` | rc 1 | `SuggestTests.lean:760:2`: "The tactic provided to `fail_if_success` succeeded but was expected to fail" |

The first build of the edited test modules (lane `gaps-interval-inspector-build1`)
succeeded with all pins exactly as written. It produced 14 module-system warnings
(10 replayed + CommandTests 1 + SuggestTests 3) and no other warning or error, so
the new tests add no warning.

Final run after all `.lean` edits and restores: lane
`gaps-interval-inspector-finaltest` (`MIN_FREE_GB=20`), `lake build && time lake test`.
```
Build completed successfully (895 jobs).
### lake build rc=0
⚠ [1023/1025] Built IntervalInspectorTests.CommandTests (1.0s)
⚠ [1024/1025] Built IntervalInspectorTests.SuggestTests (1.7s)
✔ [1025/1025] Built IntervalInspectorTests (909ms)
real	0m3.547s
### lake test rc=0
browser-lock: command exited rc=0
```
The library modules were replayed: the last mutation-check builds had already
rebuilt `Suggest`/`Widget`/`Demo` from the restored sources. The test modules
that import neither edited file were replayed too, ClickE2E included (it was not
rebuilt during any mutation). The log has 29 module-system warnings (10 + 19, as
in gotcha 1) and 0 other warning, error or deprecation lines.


## Lean 4.32.2 → 4.34.0 (previous port)

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

### Changes

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

### Pin updates

None. All 24 `#guard_msgs` docstrings (20 `CommandTests`, 4 `Demo.lean`) are
byte-identical to the reference, and so are every ClickE2E
position pin, unsolved-goals pin and tactic-text pin. The only string edits in
the tree are the `Mathlib.Data.Real.Basic` → `Mathlib.Basic.Real.Basic`
replacements inside the ClickE2E user-file sources, which are inputs, not
expected outputs.

### Deviations

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

### Counts

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

### 4.34 gotchas worth knowing for QED64

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
