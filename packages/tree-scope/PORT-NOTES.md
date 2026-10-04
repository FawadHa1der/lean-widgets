# Port notes: `tree-scope` (lib `TreeScope`) — Lean v4.32.2 → v4.34.0 / Mathlib v4.34.0

Reference (read-only): `widgets/tree-scope` (leanprover/lean4:v4.32.2, Mathlib v4.32.2).
Ported tree: `widgets-v4.34/tree-scope` (leanprover/lean4:v4.34.0, Mathlib `v4.34.0` =
`5ed2965256430c3649e86755f9576b54eca72435`; Batteries `f2effa3d`, ProofWidgets `106ff4fa`,
all on toolchain v4.34.0 per their `lean-toolchain`).

Result: **`lake build` exit 0, `lake test` exit 0, zero Lean source changes.**
A forced rebuild of every `TreeScope.*` and `TreeScopeTests.*` module (build outputs
deleted first) produced no `⚠` lines at all — no deprecation warnings, no linter notes.
`diff -r` against the reference differs only in `lean-toolchain`, the Mathlib `rev` in
`lakefile.toml`, and the regenerated `lake-manifest.json` (all pre-set by the harness).

## Changes

| File | What | Why |
|---|---|---|
| `lean-toolchain` | `v4.32.2` → `v4.34.0` | pre-set by the harness (not edited here) |
| `lakefile.toml` | mathlib `rev = "v4.34.0"` | pre-set by the harness (not edited here) |
| `lake-manifest.json` | regenerated for the new revs | pre-set by the harness (`lake update` was **not** run again) |
| `README.md` | "Built against" line → v4.34.0; test-count sentence made exact (476); new limitation bullet about `Lean.RBMap` being a deprecated module | versions/limitations changed |
| `PORT-NOTES.md` | this file | required deliverable |
| `TreeScope/**`, `TreeScopeTests/**`, `TreeScope.lean`, `TreeScopeTests.lean` | **unchanged** | every API the package touches is byte-identical in the pinned v4.34.0 sources (verified below) |

### Risk-list items, verified against the pinned sources (not guessed)

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

## Pin updates

None. Every `#guard_msgs` block (72, all in the test lib) and every
`#guard` (404) passes with its v4.32.2 expected output; the new toolchain produces exactly the
same messages, so no old→new pin edits were required.

## Deviations

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

## Counts

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

## 4.34 gotchas worth knowing for QED64

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
* **Mathlib cache note**: `lake exe cache get` for v4.34.0 reports "2 files not found in the
  cache" (0 downloaded); this is benign here — `lake build` needed no Mathlib compilation
  (1035 jobs, all package modules only, seconds).
* Lake's `lake test` prints nothing when everything is already built and passing; force a
  rebuild of the package's own outputs (`rm -rf .lake/build/lib/lean/TreeScope*`) to see
  warning lines.

## Second-pass verification (2026-09-30)

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
method, see the third-pass correction below) was never affected.
