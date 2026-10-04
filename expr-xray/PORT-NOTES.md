# Port notes: expr-xray, Lean v4.32.2 → v4.34.0 (QED64 pairing)

Reference (read-only): `../../widgets/expr-xray` (Lean `v4.32.2`, ProofWidgets
`6e311e2a844da9b2cc3971187df2fe0066947b93`).
Port: this directory (Lean `v4.34.0`, ProofWidgets
`106ff4fafc74ef4ac99d81dbf3ab399118f497a5`, fresh `lake-manifest.json`).

Result: `lake build` exit 0 and `lake test` exit 0 on a fully clean
`.lake/build` (25 build jobs, 33 test jobs), **zero warnings** (no
deprecation, no linter output) — verified by rebuilding from scratch and
grepping the full log for `warning|error|deprecat|sorry`.

## Changes

| File | What | Why |
|------|------|-----|
| `lean-toolchain` | `leanprover/lean4:v4.32.2` → `leanprover/lean4:v4.34.0` | Done by the harness before this port started (not edited here). |
| `lakefile.toml` | ProofWidgets `rev` `6e311e2a…` → `106ff4fa…` | Done by the harness (ProofWidgets rev that builds on v4.34.0; not edited here). |
| `lake-manifest.json` | regenerated | Done by the harness (`lake update` ran once; never re-run). |
| `README.md` | toolchain/pin sentence updated; test-census sentence added | Documentation only, see "Counts". |
| `PORT-NOTES.md` | this file | New. |

**No Lean source file changed.** `diff -r` of `ExprXRay/`, `ExprXRay.lean`,
`ExprXRayTests/`, `ExprXRayTests.lean` against the reference is empty. Every
API on the risk list was checked against the pinned v4.34.0 sources and is
signature-identical to v4.32.2 at the call sites this package uses:

- `Meta.getFunInfoNArgs (fn : Expr) (nargs : Nat) : MetaM FunInfo`
  (`Lean/Meta/FunInfo.lean:140`, both toolchains) — used in
  `ExprXRay/Analyze.lean:82`; `ParamInfo.binderInfo` still carries the four
  `BinderInfo` cases the role classifier switches on.
- `Meta.getCoeFnInfo? (fn : Name) : CoreM (Option CoeFnInfo)`
  (`Lean/Meta/CoeAttr.lean:68`, both) — `Analyze.lean:28`.
- `MonadRuntimeException.tryCatchRuntimeEx (body : m α) (handler : Exception → m α)`
  (`Lean/CoreM.lean:819`, both; exported at top level) — `Diff.lean:122`.
- `Meta.isDefEq`, `withReducible`, `withNewMCtxDepth`, `withoutModifyingState`
  — unchanged; `Diff.lean:107–123`.
- ProofWidgets: `Html`, `Html.element/text/component`, `SelectionPanel`,
  `mk_rpc_widget%`, `server_rpc_method`, `widget_module` — the ProofWidgets
  diff `6e311e2a..106ff4fa` touches only `MakeEditLink.lean`,
  `RefreshComponent.lean`, `Data/Svg.lean`, `Util.lean` (see gotchas); none
  of those are imported by this package's public surface, and the
  `Html`/panel props types this package uses are byte-identical.

## Pin updates

None. All 17 `#guard_msgs` blocks (11 in `WidgetTests.lean`, 6 in
`DefeqTests.lean`), which pin the `#xray (text := true)` / `#xray_diff`
delaborator-derived text dumps and the defeq badges/summary lines, pass
unchanged on v4.34.0. The delaborator output for every pinned term
(`(1 + 1 : Nat)`, `((3 : Nat) : Int)`, the `ite`/`instDecidableEqNat` vs
`Classical.propDecidable` pair, `Sort (max 1 2)` vs `Sort 2`, the mvar
`undetermined` cases, …) is the same in both toolchains, so no old→new
entries exist.

## Deviations

None. No test was deleted, commented out, or weakened; no feature was
dropped; no `sorry`; no global option suppression; no `set_option` of any
kind was added.

## Counts

Method (the package README did not previously state one; it now does): a
static census of assertion *sites* in `ExprXRayTests/` — every pure
`#guard`, every `#guard_msgs` block, and every call of the throwing helpers
from `TestUtil.lean` (`assertTrue`, `assertFalse`, `assertEq`,
`assertContains`, `assertNotContains`). Reproduce with:

```sh
g=$(grep -rhE "^#guard[^_]" ExprXRayTests | wc -l)
gm=$(grep -rh "#guard_msgs" ExprXRayTests | wc -l)
a=$(grep -rhoE "\bassert(True|False|Eq|Contains|NotContains)\b" ExprXRayTests | wc -l)
echo $((g+gm+a))
```

| | `#guard` | `#guard_msgs` | `assert*` sites | total |
|---|---:|---:|---:|---:|
| reference (v4.32.2) | 95 | 17 | 344 | **456** |
| port (v4.34.0) | 95 | 17 | 344 | **456** |

Equal, as required (no test added, none removed). Note the suite-level
`widgets-v4.34/README.md` table quotes "520+" for this package; that is a
*runtime* figure — three assertion sites sit inside loops
(`DiffTests.lean:233` inside the 40-iteration purity loop,
`:328` and `DefeqTests.lean:338` iterate over every mismatch of a pair), so
the number of assertions *executed* exceeds the number of sites. The static
site count is the reproducible one and is what the README now states.

## 4.34 gotchas worth knowing for QED64

Observed while grepping the pinned sources for this port; none of them
forced a change here, but they are the places where a QED64 package that
does similar things could break.

1. **`backward.isDefEq.respectTransparency.types` flipped `false` → `true`**
   (`Lean/Meta/ExprDefEq.lean:57`; `backward.isDefEq.respectTransparency`
   itself was already `true` in v4.32.2, `implicitBump` still `true`). Under
   the new default, types compared during metavariable assignment are checked
   at `.implicit` transparency instead of being bumped to `.default`. This
   package's `checkDefeq` (`Diff.lean:107`) runs `withReducible (isDefEq a b)`
   first and `isDefEq` at default second, so a pair whose *type parameters*
   (e.g. the `n` in `Fin n`) are equal only after unfolding a semireducible
   definition can now report `defeqDefault` where a v4.32.2 run could report
   `defeqReducible`. None of the curated pairs in `DefeqTests.lean` is of that
   shape (all pins pass), but any QED64 test that pins `defeqReducible` on a
   type-parameter-dependent pair must be re-verified on this toolchain rather
   than copied. The fix, when it is a *library* definition, is
   `@[implicit_reducible]` (documented in `Init/MetaTypes.lean:70–110`), not
   `set_option backward.isDefEq.respectTransparency false`.
2. **`Int.toFloat` is now in core** (`Init/Data/OfScientific.lean:84`,
   `abbrev Int.toFloat := Float.ofInt`, absent in v4.32.2). ProofWidgets
   deleted its own private `_root_.Int.toFloat` from `Data/Svg.lean` in the
   v4.34.0-rc1 bump (`99e8ade`) because of the clash. No package in this
   suite defines a `_root_.Int.toFloat` (grepped), so nothing here is hit,
   but any QED64 code that shadows a core name under `_root_` should expect
   the same kind of duplicate-declaration error on a toolchain bump.
3. **`Lean.Char.utf16Size`** is still defined at
   `Lean/Data/Lsp/Utf16.lean:24` in v4.34.0 (unchanged from v4.32.2), yet
   ProofWidgets inlined a private copy into `MakeEditLink.lean` in its
   v4.33.0-rc1 bump (`b1436dc`), i.e. the core definition stopped being
   reachable through the imports `MakeEditLink.lean` has. A QED64 package
   that computed LSP positions via `c.utf16Size` relying on transitive
   ProofWidgets imports should import `Lean.Data.Lsp.Utf16` explicitly
   (the packages with click-to-insert links: graph-scope, hasse-view,
   interval-inspector, dist-lens). Not applicable to expr-xray.
4. **`ProofWidgets/Util.lean` now does `open Delaborator.SubExpr`** instead
   of `open SubExpr` inside `namespace Lean.PrettyPrinter.Delaborator` (same
   v4.33.0-rc1 bump, `b1436dc`) — bare `SubExpr` no longer resolves there.
   Packages that write custom delaborators with `open SubExpr` should expect
   an "unknown namespace" error and use the qualified form.
5. **`RefreshComponent.lean` switched from unsafe `IO.Ref` ops to a mutex**
   (`ebeca04`). No API change for consumers, but it is the one ProofWidgets
   behaviour change between the pins that is not a toolchain-bump
   adaptation; packages that use `RefreshComponent` should re-run their
   live-panel checks. The complete ProofWidgets Lean-source diff between the
   two pins is 5 files / 26+ 22- lines (the root `ProofWidgets.lean` import list from the d662197 totalize-imports chore, plus `MakeEditLink.lean`,
   `RefreshComponent.lean`, `Data/Svg.lean`, `Util.lean`); the remaining
   commits are toolchain-bump chores and `d662197 chore: totalize imports`.
6. **Nothing on this package's risk list moved**: `getFunInfo`,
   `getFunInfoNArgs`, `getCoeFnInfo?`, `isDefEq`, `tryCatchRuntimeEx`,
   `SelectionPanel` props and `Html` are signature-identical between the two
   pinned toolchains/revs. The delaborator output pinned by this package's
   `#guard_msgs` is also identical — so pretty-printer drift between 4.32.2
   and 4.34.0 does not affect `pp.explicit`/default printing of the term
   shapes used here (numerals, `ite`, `Sort`, `Nat`→`Int` casts, `id`,
   `Prop`/`Type` binders).
