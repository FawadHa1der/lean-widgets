# Port notes: `tree-scope` (lib `TreeScope`): Lean v4.32.2 → v4.34.0 → v4.35.0

Two ports, newest first: v4.34.0 → v4.35.0 (next section) and the earlier
v4.32.2 → v4.34.0 (last section).

## Lean 4.34.0 → 4.35.0 (2026-10-25)

Result: **`lake build` exit 0, `lake test` exit 0, zero Lean source changes, zero
expected-output changes.** All 476 test assertions pass with their v4.34.0 text. The only new
build output is two expected module-system warnings in `TreeScope/Instances/MathlibTree.lean`
(see *Deviations*), and no test pins them. After the audit, a tests-only pass added
`TreeScopeTests/PanelTests.lean` (24 assertions; 500 in total now), see *Gap-closing tests*.

### Pins (set by the harness; not edited here)

| What | Value |
|---|---|
| `lean-toolchain` | `leanprover/lean4:v4.35.0` (`lean --version`: 4.35.0, commit `eb6cafb7290e`) |
| `lakefile.toml` | mathlib `rev = "v4.35.0"` → manifest `56a005855ea17e0b0958f73ec801ae140b0a1679` |
| Inherited (equal to Mathlib v4.35.0's own manifest) | ProofWidgets `df72b022e558978a1c50264cfc4d7fec86fa8e04`, Batteries `66e469188fe0`, Aesop `4a174c490d87`, Qq `dce0ad79c486`, plausible `dfa4f38190d0`, importGraph `a41f0e9a4dea`, LeanSearchClient `d6b4c7be5be7`, Cli `c24fe6078c63` (`v4.35.0`) |
| Dependency step | one `lake update` plus `lake exe cache get` by the harness (`No files to download`, `Already decompressed 9031 file(s)`). Neither was run again here. |

tree-scope does not require ProofWidgets directly. It gets ProofWidgets through Mathlib.

### Changes

| File | What | Why |
|---|---|---|
| `lean-toolchain` | `v4.34.0` → `v4.35.0` | set by the harness |
| `lakefile.toml` | mathlib `rev` `v4.34.0` → `v4.35.0` | set by the harness |
| `lake-manifest.json` | regenerated for the new revs | set by the harness |
| `README.md` | "Built against" paragraph → Lean v4.35.0 / Mathlib v4.35.0 / ProofWidgets `df72b022`, plus one sentence on the two module-system warnings; the `Lean.RBMap` limitation bullet now says the module is still deprecated, and unchanged, in v4.35.0 | versions changed |
| `PORT-NOTES.md` | this section; the 4.34 notes moved under their own heading below. Post-audit changes: the title now names both ports, the 4.34 notes' subheadings are one level lower, and the 4.34 notes carry one erratum and a one-word fix ("below" → "above"). See *Post-audit fixes*. | required deliverable |
| `TreeScope/**`, `TreeScope.lean`, the 13 existing `TreeScopeTests/*.lean` | **unchanged** | every API the package uses still works at the 4.35 pins (checked against the sources below) |
| `TreeScopeTests/PanelTests.lean` (new), `TreeScopeTests.lean` (one `import` line) | tests only, added after the audit | closes the panel-props test gap; see *Gap-closing tests* |

#### API checks against the pinned 4.35 sources

1. **Core `Lean.RBNode` / `Lean.RBMap`.** `Lean/Data/RBMap.lean`, `Lean/Data/RBTree.lean` and
   `Lean/Data.lean` are **byte-identical** in toolchains v4.34.0 and v4.35.0 (`diff` is empty).
   That includes the `deprecated_module` line and the umbrella's
   `public import Lean.Data.RBMap -- deprecated_module: ignore`, so `import Lean` still reaches
   the module without a warning.
2. **`Std.TreeMap` / `Std.DTreeMap.Internal.Impl`.** These files are byte-identical:
   `Std/Data/DTreeMap/Internal/Def.lean`, `Internal/Balanced.lean`, `Internal/Operations.lean`,
   `Std/Data/DTreeMap/Basic.lean`, `Std/Data/TreeMap/Basic.lean` and `Std/Data/TreeMap.lean`.
   The `Impl.inner`/`Impl.leaf` shape and the `TreeMap.inner`/`DTreeMap.inner` fields are
   unchanged.
3. **Batteries `BinomialHeap`** (`f2effa3d` → `66e46918`, `Batteries/Data/BinomialHeap/Basic.lean`).
   - The inductives `Imp.Heap` and `Imp.HeapNode`, their constructors, `HeapNode.rank` and
     `Heap.merge` are unchanged.
   - The **file-wide `@[expose] public section` became `public section`**. `@[expose]` is now
     put on individual definitions: `HeapNode.realSize`, `Heap.realSize`, `Heap.size`,
     `rankGT`, `length`, `headD`, `head?`, `findMin`, `deleteMin`, `HeapNode.WF`, `Heap.WF` and
     `BinomialHeap`. Every other definition, such as `merge`, `insert` and `singleton`, is no
     longer exposed.
   - This does not affect this package. Its files are not `module`s, and a non-module importer
     loads the `.private` olean level, so it sees all definition bodies. See
     `Lean/Environment.lean:1640`: "without `import all`, `OLeanLevel.exported` is imported,
     else `OLeanLevel.private`". The level is chosen in `Lean/Elab/Import.lean:150-155`,
     which is byte-identical in v4.34.0. The instance runs compiled through `evalExpr`, so
     exposure does not matter for it either. This is about bodies. The 4.34 gotcha "Module
     system everywhere" (below) is about *names* of private-by-default declarations, and
     its erratum explains why the two do not conflict.
   - `HeapTests` (29 `#guard` + 4 `#guard_msgs`) pass verbatim.
4. **Mathlib `BinaryTree` / Catalan** (`5ed29652` → `56a00585`).
   - `Mathlib/Data/Tree/Basic.lean` only dropped `import Batteries.Tactic.Alias`.
   - `Mathlib/Combinatorics/Enumerative/Catalan/Tree.lean` dropped three `public import`s:
     `Algebra.BigOperators.Group.Finset.Defs`, `Data.Finset.NatAntidiagonal` and
     `Data.Nat.Choose.Central`.
   - The declarations are unchanged. The package uses only the canonical `BinaryTree.*` names
     and `catalan`. The deprecated `Tree` shims (since 2026-06-07) are still present and still
     unused.
   - Neither module is in QED64's `dropped-434-to-435.txt`.
5. **Meta and widget plumbing.**
   - `Lean/Meta/Eval.lean` (`evalExpr'`) and `Lean/Server/Rpc/Basic.lean` are identical.
   - `Lean/Meta/WHNF.lean` lost `reduceNative?`: `whnf` no longer evaluates
     `Lean.reduceBool`/`Lean.reduceNat` natively. The package's reflection never produces
     these.
   - `Lean/Widget/UserWidget.lean` changed only a duplicate-hash warning text
     (`hash(JS source code)` → `hash (JS source code)`) and the signature of
     `findInfoTreeAtPos`. The package neither pins nor calls either.
   - All 26 reflection `#guard_msgs` (`ReflectTests.lean`) reproduce byte-for-byte, as do the
     4 Float folds.

### Golden / expected-output changes

**None.** All 72 `#guard_msgs` blocks and all 404 `#guard`s pass unchanged with their v4.34.0
(= v4.32.2) expected outputs. No docstring, golden string or pinned message was edited.

### Deviations

None in behaviour or in the test suite. Three notes for readers:

* **New build warnings (expected, rule 5).** `lake build` now prints two warnings for
  `TreeScope/Instances/MathlibTree.lean`: "imports `Mathlib.Data.Tree.Basic` from package
  `mathlib`, which is designed for use with the module system; consider adding `module` to the
  start of this file", and the same warning for `Mathlib.Combinatorics.Enumerative.Catalan.Tree`.
  This is the only file that imports Mathlib directly. Lake replays the warnings on every
  later build or test. The file was **not** converted to `module`. The warnings do not reach
  any test: no test file imports Mathlib directly, and no `#guard_msgs` covers an `import`.
  Both test runs here built all 13 `TreeScopeTests.*` modules without a `⚠` line.
  `TreeScope/Instances/Heap.lean` imports Batteries, a module-system package, and gets no such
  warning, because Batteries' lakefile does not set `requiresModuleSystem`. For the cause, see
  the first *4.35 gotcha*: it is Mathlib v4.35.0's lakefile, not a Lean or Lake change.
* **Forced reflection of a `BinomialHeap` fails, as it did before (not a regression).** A
  scratch probe outside the package ran
  `#tree_scope (text := true) (reflect := true) ([3, 1, 2].foldl (·.insert ·) .empty : BinomialHeap Nat (· ≤ ·))`.
  It reports the package's honest error, "`…Heap.merge … (Heap.singleton 2) …` does not reduce
  to a constructor application". The cause is that `Heap.merge` is defined by well-founded
  recursion (`termination_by s₁.length + s₂.length`), and `whnf` does not unfold such
  definitions. The definition is identical at both Batteries pins. The probe was not re-run on
  4.34, but by that reasoning 4.34 behaved the same. No test or demo uses this path.
  - The default semantic path is unaffected. It prints `heap · n=3 <ok>` with `rank=0`/`rank=1`
    roots and `invariants ok`.
* **`Lean.RBMap` is still a deprecated module in v4.35.0**, with the same text and the same
  "since" date. It has not been removed yet, so the `RBNode`/`RBMap` instances still ship
  unchanged.

### Counts

Method: the README census, anchored to the line start. For `#guard`:
`grep -E '^\s*#guard\b' | grep -vc '#guard_msgs'`. For `#guard_msgs`:
`grep -cE '^\s*#guard_msgs\b'`. Both run per file over `TreeScopeTests/*.lean` +
`TreeScopeTests.lean`. "Before" was read with `git show qed64-pin-i:<path>`
(`qed64-pin-i` = `4d93a28`); "after" is the working tree. The last column is the working
tree after the tests-only gap-closing pass (recounted with the same commands).

| | Before (v4.34.0, `qed64-pin-i`) | After (v4.35.0 port) | After gap-closing tests |
|---|---|---|---|
| `#guard` (test lib) | 404 | 404 | 424 |
| `#guard_msgs` (test lib) | 72 | 72 | 76 |
| **Total test assertions** | **476** | **476** | **500** |
| `#guard` / `#guard_msgs` in `TreeScope/**` | 0 | 0 | 0 |

Per file (`#guard` / `#guard_msgs`), the same before and after the port: Catalan 16/0,
Command 0/12, Dispatch 1/9, Evolve 34/10, Heap 29/4, Helpers 0/0, Layout 92/0,
MathlibTree 11/4, Model 41/0, RB 60/5, Reflect 0/26, Render 98/0, StdTreeMap 21/2, and
`TreeScopeTests.lean` 1/0. The gap-closing pass adds Panel 20/4 (new file) and changes no
other file's count.

### 4.35 gotchas (for the next porter)

* **Module-system import warning.** At the 4.35 pins, a non-`module` file that directly
  imports a Mathlib module gets "…designed for use with the module system; consider adding
  `module`…".
  - **Cause.** The warning comes from Lake's `requiresModuleSystem` check in
    `fetchImportInfo` (`lake/Lake/Build/Module.lean`). That check is byte-identical in
    v4.34.0 (lines 404-411) and v4.35.0 (lines 416-423), and the `requiresModuleSystem` /
    `allowNonModules` options already existed in v4.34.0's `Lake/Config/LeanConfig.lean`.
    What changed is **Mathlib v4.35.0's lakefile**, which adds `requiresModuleSystem := true`
    to `package mathlib` (`lakefile.lean:69`). Mathlib v4.34.0's lakefile (`5ed29652`) did
    not set it (`git diff 5ed29652 56a00585 -- lakefile.lean`). Lake fires the warning for a
    non-module file that imports a module of *any* package or library setting the option.
    Batteries, ProofWidgets and the rest of this package's dependencies do not set it.
  - **Scope.** The warning is per importing file and only for direct imports. Files that
    import Batteries or core do not get it, and files that reach Mathlib only through this
    package's own modules do not either. Lake *replays* it on every later build, so it shows
    up in `lake test` logs as `⚠ … Replayed TreeScope.Instances.MathlibTree`. It is a Lake log
    line, not a Lean message, so `#guard_msgs` cannot see it. But a harness that pins a
    file's Lake build output would see it.
  - **Opt-out.** Set `allowNonModules := true` on the importing package or `lean_lib`
    (`Lake/Config/LeanConfig.lean:283-299`). Mathlib itself does this for `lean_lib
    MathlibTest` and its scripts. Here that would be a `lakefile.toml` change, and the
    lakefile is harness-owned, so it was not made.
* **Batteries `BinomialHeap` exposure was narrowed** (see API check 3). Non-module consumers
  such as this package and QED64's showcase files are unaffected. A *`module`* consumer can no
  longer see the bodies of `merge`, `insert`, `singleton`, `HeapNode.rank` and the like. For
  example, `decide` or `rfl` on concrete heaps inside a `module` file would get stuck there.
* **`whnf` lost native `reduceBool`/`reduceNat`** (`Lean/Meta/WHNF.lean`). Reflection code that
  relied on `whnf` evaluating `Lean.reduceBool c` must now evaluate `c` itself. In fact the
  constants are gone too: v4.35.0's `Init/Core.lean` no longer defines `Lean.reduceBool`,
  `Lean.reduceNat` or `Lean.ofReduceBool`. In v4.34.0 they were
  `@[deprecated "in-kernel native reduction is deprecated…" (since := "2026-02-01")]`
  (`Init/Core.lean:2361` ff.). Code that names them no longer compiles.
* **Mathlib `Catalan/Tree.lean` no longer re-exports** `Finset.NatAntidiagonal`,
  `Nat.Choose.Central` or `BigOperators.Group.Finset.Defs`. If code got those names only
  through this import, it now needs explicit imports. This package's build is unaffected.
* **Nothing tree-related moved.** The RBMap/RBTree, `Std.TreeMap`/`DTreeMap` and `Impl`
  sources are byte-identical between v4.34.0 and v4.35.0, so the internals-reading instances
  (`StdTreeMap`, `RB`) needed no change.
* `UserWidget`'s duplicate-hash warning now reads `hash (JS source code)` (with a space). Any
  golden that pinned the old text needs updating. This package has none.

### Post-audit fixes (2026-10-25)

The adversarial audit passed this package. A clean rebuild was green, the counts matched
(404 + 72 = 476 on both sides), and 6 of 7 source mutations were caught. It raised three
minor findings. This pass edited only this file and `README.md`; no `.lean` file, test or
expected output was touched.

| Finding | Fix |
|---|---|
| The panel content of `#tree_scope` / `#tree_evolve` is not tested. Mutation M7 (`renderPanel tv` → `renderPanel (.leaf "x")` at `TreeScope/Widget.lean:90`) survived `lake test`, because the panel-mode tests only assert that there are no messages. | **Fixed by the later tests-only pass** (see *Gap-closing tests*). The gap predated the port. New test: `TreeScopeTests/PanelTests.lean` reads the panel props that `#tree_scope` and `#tree_evolve` store in the info tree and compares them with panels rendered from hand-written expected trees. M7 now fails 9 `#guard`s. |
| 4.35 gotcha 1 said "In 4.35, a non-module file that directly imports a Mathlib module warns" without naming the cause. | Rewritten. Lake's `requiresModuleSystem` check is byte-identical in v4.34.0 and v4.35.0. The new ingredient is Mathlib v4.35.0's `requiresModuleSystem := true` (`lakefile.lean:69`). Batteries does not set it, which is why `Heap.lean` gets no warning (also added under *Deviations*). The `allowNonModules := true` opt-out is now named, and so is Mathlib's own use of it for `MathlibTest`. The old closing sentence was also wrong: it said a test pinning the messages of a Mathlib-importing file would see the warning. The warning is a Lake log line, not a Lean message, so a Lean-level message pin cannot see it (interval-inspector's ClickE2E recompiles confirm this). The README's warning sentence now names the cause too. |
| The retained 4.34 gotcha ("a private-by-default `def` … is invisible to non-module consumers") contradicts, without comment, API check 3 ("a non-module importer … sees all definition bodies"). Also, the 4.34 section's own subheadings were `##`, the same level as the 4.34 section heading, so the file had two `Changes` / `Deviations` / `Counts` sections at different levels. | An erratum under that 4.34 gotcha explains, from the sources, that the two statements concern different things: bodies are visible at the `.private` level, while private *names* are not resolvable by a non-module importer. Both hold on both toolchains. API check 3 now points to it. A probe confirmed the erratum on both toolchains (see *Verification transcript*). The 4.34 section's subheadings were demoted one level (`##` → `###`, `###` → `####`), and the H1 now names both ports. |

Two further corrections were made while checking the above:

- The `whnf`/`reduceBool` gotcha now says that v4.35.0 removed the `Lean.reduceBool` /
  `Lean.reduceNat` / `Lean.ofReduceBool` constants themselves, not only their native
  reduction.
- The 4.34 "Second-pass verification" text said "see the third-pass correction below" for a
  paragraph that sits above it. It now says "above".

The counts were recounted mechanically on the v4.32.2 original (repository tag
`lean-v4.32.2`), on `qed64-pin-i` and on this tree, with the method in *Counts*. All three
give 404 `#guard` + 72 `#guard_msgs` = 476, and 0 in `TreeScope/**`. A second count, which
strips comments and docstrings first, gives the same numbers.

### Gap-closing tests (2026-10-25)

A later tests-only pass closed the first audit finding (panel content untested). It added
`TreeScopeTests/PanelTests.lean` (20 `#guard` + 4 `#guard_msgs`) and one `import` line in
`TreeScopeTests.lean`. No library file, existing test or expected output changed:
`git diff -- TreeScope/ TreeScope.lean` is empty, and the 13 existing test files are untouched.

What the test does:

* `#capture_panels n in cmd` is a test-only command defined in the file. It elaborates `cmd`
  with info trees enabled (messages pass through, so `#guard_msgs` can wrap it) and defines
  `n : Array StoredWidget` from every `UserWidgetInfo` leaf `cmd` saved. Each entry holds the
  module name, the javascript hash, the kind of the attached syntax, whether that syntax is
  `cmd` itself (same source range), and the props forced with an empty RPC object store.
* There are four scenarios, each under `#guard_msgs` (panel mode stays silent):
  `#tree_scope rbm4` (core `Lean.RBMap`, semantic path);
  `#tree_scope (BinaryTree.node 2 …)` (Mathlib, semantic path); `#tree_scope [1, 2]`
  (reflection fallback); and `#tree_evolve` over an empty `Lean.RBMap` with two inserts.
* For each scenario the test checks that there is exactly one `HtmlDisplayPanel` widget on
  the command. The props must be exactly `{ html: rpcEncode h }`, where `h` is rendered from a
  hand-written expected `TreeView` (or `Frame` array). The hand-written semantic views are
  also `#guard`ed equal to `toTreeView`. The stored `html` must decode, through
  `HtmlDisplayProps`' own `RpcEncodable` instance, to the same tree. The user-visible text
  (stats line, caption, step captions) must be present.

Mutation proofs. Each one: copy the file, apply one mutation, build, restore, then check that
`shasum` matches the copy.

| Mutation | Build | Result |
|---|---|---|
| M7 (the audit's survivor), `Widget.lean:90`: `renderPanel tv` → `renderPanel (.leaf "x")` | `lake build TreeScopeTests.PanelTests` | **failed**: 9 `#guard`s (lines 131–134, 153–155, 170–171), i.e. the props, decode and text checks of all three `#tree_scope` scenarios |
| E1, `Evolve.lean:202`: `renderFilmstrip frames` → `renderFilmstrip frames.pop` | `lake build TreeScopeTests` | the 13 existing test modules all built green, so `#tree_evolve` had the same gap; `PanelTests` **failed** 4 `#guard`s (lines 191–193, 195) |
| A1, `Widget.lean:155`: `showTreeView stx …` → `showTreeView t …` (widget attached to the term, not the command) | `lake build TreeScopeTests` | the 13 existing modules green; `PanelTests` **failed** the 3 `onePanelOn` `#guard`s (lines 130, 152, 169) |

All three were restored byte-identical (`Widget.lean` `6ee444b2…`, `Evolve.lean`
`533a9f64…`), and `git diff -- TreeScope/` is empty.

Lanes (same wrapper as below): `gaps-tree-scope-panel-build1` (first build of
`PanelTests`, green), `gaps-tree-scope-mutM7`, `gaps-tree-scope-mutEvolve`,
`gaps-tree-scope-mutAttach`, then `gaps-tree-scope-test-final` (`MIN_FREE_GB=20`, after the
last restore): `lake build` → `Build completed successfully (1061 jobs).`,
`LAKE_BUILD_RC=0`; `lake test` built all 14 test modules with no `⚠` in any of them
(`✔ [1074/1075] Built TreeScopeTests.PanelTests (4.7s)`,
`✔ [1075/1075] Built TreeScopeTests (985ms)`), `LAKE_TEST_RC=0`. The only warnings are the
two replayed `MathlibTree.lean` module-system warnings.

### Verification transcript

All lake invocations ran through the shared lock wrapper:
```
BROWSER_LOCK_DIR=$HOME/.cache/lean-widgets-build-lock MIN_FREE_GB=10 LOCK_WAIT_S=43200 COOLDOWN_WAIT_S=7200 \
  bash ".../widgets-v4.34/qed64-showcase/scripts/with-browser-lock.sh" port435-tree-scope-<purpose> \
  bash -c 'cd ".../widgets-v4.34/packages/tree-scope" && <lake command>'
```

1. **Harness `lake build` on 4.35** (`port435/tree-scope.build0.log`, a fresh build of all 13
   `TreeScope*` modules): `⚠ [1055/1061] Built TreeScope.Instances.MathlibTree (2.1s)` plus the
   two warnings above, then `Build completed successfully (1061 jobs).` and
   `browser-lock: command exited rc=0`.
2. **`lake test`** (`port435-tree-scope-test1`, run in the background): built all 13
   `TreeScopeTests.*` modules fresh with no `⚠`. Final lines:
   `✔ [1074/1074] Built TreeScopeTests (1.3s)`, `LAKE_TEST_RC=0`,
   `browser-lock: command exited rc=0`.
3. **Heap reflection probe** (`port435-tree-scope-probe`,
   `lake env lean <scratchpad>/HeapReflectProbe.lean`, outside the package): output as
   described under *Deviations*.
4. **Final `lake build`** (`port435-tree-scope-build-final`, after the doc edits): the two
   replayed warnings (`⚠ [1054/1061] Replayed TreeScope.Instances.MathlibTree`), then
   `Build completed successfully (1061 jobs).`, `LAKE_BUILD_RC=0`,
   `browser-lock: command exited rc=0`.
5. **Final `lake test`** (`port435-tree-scope-test-final`, run in the background): the same two
   replayed warnings (`⚠ [1054/1074] Replayed TreeScope.Instances.MathlibTree`). Everything
   else was up to date, so Lake printed nothing more. Then `LAKE_TEST_RC=0` and
   `browser-lock: command exited rc=0`.

6. **Post-audit verification (2026-10-25)**, through the same wrapper (`BROWSER_LOCK_DIR=$HOME/.cache/lean-widgets-build-lock MIN_FREE_GB=<10|20> LOCK_WAIT_S=43200 COOLDOWN_WAIT_S=7200 bash ".../widgets-v4.34/qed64-showcase/scripts/with-browser-lock.sh" <lane> …`):
   - Lane `port435-fix-tree-scope-buildtest` (`MIN_FREE_GB=20`) ran the first visibility
     probe on both toolchains, then `lake build` (the two replayed warnings and
     `Build completed successfully (1061 jobs).`, rc 0) and `lake test` (rc 0). The probe's
     non-module importer lacked `import Lean` for its environment dump, so the probe was
     re-run, extended with the two `module` importers, in lane
     `port435-fix-expr-xray-tree-scope-probes2`. The results are under the 4.34 gotcha's
     erratum. The first run had already shown "Unknown identifier `VisA.hidden`" and a
     working `rfl` on both toolchains.
   - Lane `port435-fix-ii-ts-ex-ck-cleanfinal` (`MIN_FREE_GB=20`) first deleted this
     package's own outputs, `.lake/build/{lib/lean,ir}/TreeScope*`, leaving 0 entries;
     `.lake/packages` was not touched. It then ran `lake build` and `time lake test`. All 27
     own modules (13 library modules, 13 test modules, the test root) were rebuilt:
     ```
     ✔ [1060/1061] Built TreeScope (981ms)
     Build completed successfully (1061 jobs).
     ### lake build rc=0
     ✔ [1073/1074] Built TreeScopeTests.EvolveTests (4.1s)
     ✔ [1074/1074] Built TreeScopeTests (1.0s)
     real	0m7.232s
     ### lake test rc=0
     browser-lock: command exited rc=0
     ```
     The only warnings are the two `MathlibTree.lean` module-system warnings, built once and
     replayed once. There are 0 other warning or error lines, and no `⚠` in any
     `TreeScopeTests.*` module.

   Both runs were made after the documentation edits. Any later edit in this pass touched only Markdown files, which are not Lake inputs. `git status` lists no change under this package besides `PORT-NOTES.md`, `README.md` and the three harness files.


## Lean v4.32.2 → v4.34.0 / Mathlib v4.34.0 (previous port)

Reference (read-only): `widgets/tree-scope` (leanprover/lean4:v4.32.2, Mathlib v4.32.2).
Ported tree: `widgets-v4.34/tree-scope` (leanprover/lean4:v4.34.0, Mathlib `v4.34.0` =
`5ed2965256430c3649e86755f9576b54eca72435`; Batteries `f2effa3d`, ProofWidgets `106ff4fa`,
all on toolchain v4.34.0 per their `lean-toolchain`).

Result: **`lake build` exit 0, `lake test` exit 0, zero Lean source changes.**
A forced rebuild of every `TreeScope.*` and `TreeScopeTests.*` module (build outputs
deleted first) produced no `⚠` lines at all — no deprecation warnings, no linter notes.
`diff -r` against the reference differs only in `lean-toolchain`, the Mathlib `rev` in
`lakefile.toml`, and the regenerated `lake-manifest.json` (all pre-set by the harness).

### Changes

| File | What | Why |
|---|---|---|
| `lean-toolchain` | `v4.32.2` → `v4.34.0` | pre-set by the harness (not edited here) |
| `lakefile.toml` | mathlib `rev = "v4.34.0"` | pre-set by the harness (not edited here) |
| `lake-manifest.json` | regenerated for the new revs | pre-set by the harness (`lake update` was **not** run again) |
| `README.md` | "Built against" line → v4.34.0; test-count sentence made exact (476); new limitation bullet about `Lean.RBMap` being a deprecated module | versions/limitations changed |
| `PORT-NOTES.md` | this file | required deliverable |
| `TreeScope/**`, `TreeScopeTests/**`, `TreeScope.lean`, `TreeScopeTests.lean` | **unchanged** | every API the package touches is byte-identical in the pinned v4.34.0 sources (verified below) |

#### Risk-list items, verified against the pinned sources (not guessed)

1. **`Lean.RBNode` / `Lean.RBMap`** (`~/.elan/toolchains/leanprover--lean4---v4.34.0/src/lean/Lean/Data/RBMap.lean`)
   - Shape unchanged: `inductive RBNode α β | leaf | node (color) (lchild) (key) (val) (rchild)`;
     `RBMap.empty/ofList/insert/erase`, `RBNode.isRed` all present, no per-declaration
     `@[deprecated]` attributes.
   - **New in 4.34:** the *module* now carries
     `deprecated_module "`Lean.RBMap` is deprecated; use `Std.TreeMap` instead" (since := "2026-06-01")`
     (line 14); `Lean/Data/RBTree.lean` likewise (→ `Std.TreeSet`).
   - `Lean/Elab/Import.lean` `checkDeprecatedImports` only warns on a **direct** `import` of a
     deprecated module. The package imports the umbrella `Lean` → `Lean.Data`, whose own
     `public import Lean.Data.RBMap -- deprecated_module: ignore` (`Lean/Data.lean:30`)
     suppresses it. Hence no warning, and the `RBNode`/`RBMap` instances keep working
     unchanged. Reported under *Deviations* as a forward-looking note, not a behaviour change.
2. **`Std.DTreeMap.Internal.Impl`** (`src/lean/Std/Data/DTreeMap/Internal/Def.lean:27`)
   - Still `inductive Impl α β | inner (size : Nat) (k : α) (v : β k) (l r : Impl α β) | leaf`;
     `TreeMap.inner : DTreeMap`, `DTreeMap.inner : Internal.Impl`, `DTreeMap.wf` unchanged and
     public. `Instances/StdTreeMap.lean` pattern-matches exactly this shape — untouched.
3. **`Batteries.BinomialHeap` internals** (`.lake/packages/batteries/Batteries/Data/BinomialHeap/Basic.lean`)
   - `Imp.HeapNode | nil | node (a) (child sibling)`, `Imp.Heap | nil | cons (rank) (val) (node) (next)`,
     `HeapNode.rank`, `Heap.size/deleteMin/WF` unchanged; no `deprecated` markers in the file.
4. **Mathlib Tree / Catalan module locations** (`.lake/packages/mathlib/Mathlib/`)
   - `Data/Tree/Basic.lean` and `Combinatorics/Enumerative/Catalan/Tree.lean` still exist at
     the paths the package imports (no module move, no `deprecated_module`).
   - Mathlib v4.34.0 did rename the *declarations*: `Tree` → `BinaryTree`, with
     `@[deprecated (since := "2026-06-07")]` shims `Tree`, `Tree.nil/node/map/numNodes/...` and
     `Tree.treesOfNumNodesEq`. The package **already uses the canonical `BinaryTree.*` names**
     (`BinaryTree.nil/node/treesOfNumNodesEq`, `catalan`), so no shim is hit and no rename
     was needed. Verified with `grep` over `Instances/MathlibTree.lean` and the tests.
5. **Reflection `whnf` behaviour** — `Reflect.lean` uses plain `Meta.whnf` at the ambient
   (default) transparency plus `evalExpr'` for floats. The v4.34 transparency change is
   `backward.isDefEq.respectTransparency` (default `true`), which governs `isDefEq`'s implicit
   argument checking, **not** `whnf`. All 26 `#guard_msgs` reflection pins (incl. `2 + 2 ↦ 4`,
   def unfolding, Fin proof skipping, chain compaction, cap errors) reproduce byte-for-byte.
6. **Float folding** — `Float.toString`/`Float32.toString` output is unchanged
   (`1.500000`, `3.140000`, `-2.500000`); the four Float pins in `ReflectTests.lean` pass verbatim.

### Pin updates

None. Every `#guard_msgs` block (72, all in the test lib) and every
`#guard` (404) passes with its v4.32.2 expected output; the new toolchain produces exactly the
same messages, so no old→new pin edits were required.

### Deviations

None in behaviour or in the test suite. Two forward-looking notes (not deviations, but the
honest things a reader should know):

* **`Lean.RBMap` is a deprecated module in v4.34.0.** The `RBNode`/`RBMap` instances (a shipped
  feature; forbidden to drop) survive because the package reaches the module through
  `import Lean`. A QED64 consumer that imports `Lean.Data.RBMap` *directly* will get a
  deprecation warning unless it annotates the import with `-- deprecated_module: ignore`.
  When upstream removes the module the instance will have to go; the `Std.TreeMap` instance is
  the designated successor and is already shipped.
* **Mathlib's `Tree` shims** (`Tree`, `Tree.nil`, …, `Tree.treesOfNumNodesEq`) are deprecated
  since 2026-06-07. The package never used them, but downstream code written against older
  Mathlib docs may.

### Counts

Census method from the README: count `#guard` (excluding `#guard_msgs`) and `#guard_msgs`
across `TreeScopeTests/*.lean` + `TreeScopeTests.lean` with
`grep -rhE '^\s*#guard\b' … | grep -vc '#guard_msgs'` and
`grep -rhE '^\s*#guard_msgs\b' … | wc -l` — both anchored to the start of the line so that
only commands are counted. (An earlier draft used an unanchored `grep -rh '#guard_msgs'`,
which also matched the two module-docstring mentions at `CommandTests.lean:6` and
`ReflectTests.lean:5` and therefore reported 74 / 478; the audit caught this. The anchored
figures below were re-counted on both trees on 2026-09-30.)

| | Reference (v4.32.2) | Ported (v4.34.0) |
|---|---|---|
| `#guard` (test lib) | 404 | 404 |
| `#guard_msgs` (test lib) | 72 | 72 |
| **Total test assertions** | **476** | **476** |
| `#guard` / `#guard_msgs` in `TreeScope/**` (lib, built by `lake build`) | 0 | 0 |

Per test file (`#guard` / `#guard_msgs`), identical on both sides: Catalan 16/0,
Command 0/12, Dispatch 1/9, Evolve 34/10, Heap 29/4, Layout 92/0, MathlibTree 11/4,
Model 41/0, RB 60/5, Reflect 0/26, Render 98/0, StdTreeMap 21/2, plus the
`#guard TreeScope.version = "0.2.0"` in `TreeScopeTests.lean`.

(The reference README said "~460"; the exact figure by its own method is 476. The README now
states the exact number.)

### 4.34 gotchas worth knowing for QED64

* **`deprecated_module`** (new toolchain command; `Lean/Elab/BuiltinCommand.lean:734`,
  `Lean/Elab/Import.lean:checkDeprecatedImports`): warns only on *direct* imports; suppress
  per-import with a trailing `-- deprecated_module: ignore` comment, or file-wide by putting it
  on the `module` keyword, or with `set_option linter.deprecated.module false`.
  `#show_deprecated_modules` lists them. Currently deprecated in core: `Lean.Data.RBMap`,
  `Lean.Data.RBTree` (both since 2026-06-01, successors `Std.TreeMap` / `Std.TreeSet`).
* **`backward.isDefEq.respectTransparency`** (`Lean/Meta/ExprDefEq.lean:47`) now defaults to
  `true`: `isDefEq` no longer bumps implicit-argument checks to `.default` transparency;
  companions `backward.isDefEq.respectTransparency.types` (default `true`) and
  `backward.isDefEq.implicitBump` (default `true`, unfolds `[implicit_reducible]` on top of
  `[reducible]`/`[instance_reducible]` for non-instance implicits). Affects unification-heavy
  meta code and tactic proofs, not `whnf`-based reflection.
* **Mathlib `Tree` → `BinaryTree`** rename (2026-06-07): module paths
  `Mathlib.Data.Tree.Basic` and `Mathlib.Combinatorics.Enumerative.Catalan.Tree` are
  unchanged; only declaration names moved, with `@[deprecated]` shims. Use `BinaryTree.*`.
* **Module system everywhere**: core, Batteries, Mathlib files now start with `module` and use
  `public import` / `@[expose] public section`. Everything this package relies on
  (`Impl` constructors, `TreeMap.inner`, `HeapNode`/`Heap` constructors, `BinaryTree`
  constructors) is still exposed publicly — but a private-by-default `def` in a
  `module`-mode upstream file is invisible to non-module consumers, so future breakage of
  internals-peeking instances (StdTreeMap, Heap) will show up as "unknown constant" rather
  than a shape change.
  - **Erratum (2026-10-25, 4.35 post-audit).** This bullet appears to contradict API check 3
    of the 4.35 section, which says a non-module importer sees all definition bodies. In
    fact the two statements are about different things. Both hold on v4.34.0 and v4.35.0
    alike, because `Lean/Elab/Import.lean`, `Lean/ResolveName.lean` and
    `Lean/Elab/DeclModifiers.lean` are byte-identical between the two toolchains.
    - *Definition bodies* (`@[expose]`). A non-`module` file imports at the `.private`
      olean level (`Lean/Elab/Import.lean:150-155`:
      `level := if isModule then (.server | .exported) else .private`). So it sees every
      body, exposed or not, and narrowed exposure (Batteries' `BinomialHeap` in 4.35)
      cannot break this package.
    - *Names* (private by default). In a `module` file, a declaration that is neither marked
      `public` nor inside a `public section` gets a private, mangled name
      (`Lean/Elab/DeclModifiers.lean:84-85, 246-247`). `isInaccessiblePrivateName`
      (`Lean/ResolveName.lean:278-292`) treats an imported private name as inaccessible
      unless the importer is itself a `module` that does `import all` of the defining
      module. A non-module importer therefore cannot write the name. The constant is still
      in its environment (loaded from the `.private` level), so `whnf`/`evalExpr`-based code
      can still unfold it; it just cannot be named in source.
    So "invisible" above means "cannot be named", not "absent". The prediction stands: if
    an upstream internal that an instance names in source leaves the public API, the
    failure here is a name-resolution error, not a shape change.

    **Probe (2026-10-25).** The probe used scratch files outside the package,
    compiled with each toolchain's own `lean` under the build lock. Module
    `VisA` holds a private-by-default `hidden`, a `public` but non-exposed
    `shown`, and an `@[expose] public` `shownExposed`. On **v4.34.0 and v4.35.0
    alike**:
    - *Non-module importer.* All three constants are in the environment with
      their values (`_private.VisA.0.VisA.hidden` included), and `rfl` proves
      `VisA.shown = 2`. But `#check VisA.hidden` fails with
      "Unknown identifier `VisA.hidden`".
    - *`module` importer without `import all`.* `rfl` on `VisA.shown` fails
      ("…not unfolded because their definition is not exposed"), and
      `VisA.hidden` is unknown.
    - *`module` importer with `import all`.* Both work.
* **Mathlib cache note**: `lake exe cache get` for v4.34.0 reports "2 files not found in the
  cache" (0 downloaded); this is benign here — `lake build` needed no Mathlib compilation
  (1035 jobs, all package modules only, seconds).
* Lake's `lake test` prints nothing when everything is already built and passing; force a
  rebuild of the package's own outputs (`rm -rf .lake/build/lib/lean/TreeScope*`) to see
  warning lines.

### Second-pass verification (2026-09-30)

Re-verified independently: deleted `.lake/build/lib/lean/TreeScope*` and
`.lake/build/ir/TreeScope*`, then `lake build` (exit 0, 1035 jobs, no `⚠`/warning/error
lines, no Mathlib module compiled) and `lake test` (exit 0, all 13 `TreeScopeTests.*`
modules rebuilt from scratch, no warnings). Census re-run on both trees: 404 / 72 / 476,
per-file figures as listed above.

**Third-pass correction (2026-09-30, audit follow-up):** the first two passes reported
74 `#guard_msgs` / 478 total because the `#guard_msgs` grep was not anchored to the line
start and picked up two docstring mentions (`CommandTests.lean:6`, `ReflectTests.lean:5`).
Anchored re-count: 72 `#guard_msgs` (Command 12, Reflect 26), 404 `#guard`, 476 total —
identical on the reference and ported trees, so parity was never in question. The Counts
table, the per-file list, the Pin-updates paragraph, risk item 5 and the README were
corrected accordingly.

**Correction to the first pass:** it stated that three `#guard_msgs` live in
`TreeScope/Demo.lean`. That is wrong — `Demo.lean` contains no `#guard`/`#guard_msgs`
at all (only `#tree_scope`, `#tree_evolve` and `#html` demo commands, which merely have
to elaborate under `lake build`). The Counts table and the README's test paragraph were
corrected accordingly; the test-lib figure (478 as then counted; 476 by the anchored
method, see the third-pass correction above) was never affected.
