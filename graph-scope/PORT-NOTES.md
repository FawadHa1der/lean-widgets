# GraphScope port: Lean v4.32.2 → v4.34.0 (QED64 pairing)

Reference (read-only): `../../widgets/graph-scope` (toolchain `leanprover/lean4:v4.32.2`,
Mathlib `v4.32.2`).  This tree: `leanprover/lean4:v4.34.0`, Mathlib `v4.34.0`
(lockfile `lake-manifest.json`, Mathlib oleans from `lake exe cache get`).

Result: `lake build` exit 0 and `lake test` exit 0 after a clean rebuild of the
package's own modules (`rm -rf .lake/build`), with **zero warnings** — no
deprecated lemma, module or API is used anywhere in the package, so no
`set_option` scoping for deprecations was needed.

## Changes

| File | What | Why |
|---|---|---|
| `lean-toolchain`, `lakefile.toml` | `v4.32.2` → `v4.34.0` (toolchain and Mathlib rev) | Pre-staged by the harness; not touched by the port agents. |
| `GraphScopeTests/InsertTests.lean` (`testDocMeta`) | `text := "".toFileMap` → `text := Lean.FileMap.ofString ""` | Forced. v4.34.0 moved `String.toFileMap` into the `Lean` namespace (`Lean.String.toFileMap`, `src/lean/Lean/Data/Position.lean:122`, a thin wrapper over `Lean.FileMap.ofString`). The test file does not `open Lean` at that point, so field notation `"".toFileMap` now fails with `Invalid field toFileMap: The environment does not contain String.toFileMap` (verified on this toolchain). Same `FileMap` value either way. |
| `GraphScopeTests/InsertTests.lean` (end of file) | New section "Toolchain transparency defaults (v4.34.0 port)": one `#guard_msgs` pin that `backward.isDefEq.respectTransparency.types` is `true` under this file's effective options, plus four `#guard_msgs in example … := by decide` checks (`pathGraph 5` adjacency and degree, `completeBipartiteGraph (Fin 2) (Fin 3)` adjacency and degree) that must decide under the toolchain **defaults**, with no `set_option … respectTransparency … false` anywhere in the package. | New tests (allowed). Started by the interrupted agent; this is the package's most exposed surface for the 4.34 transparency change (see gotchas): the click-to-insert feature promises that every offered `by decide` example compiles in a user file that only imports `GraphScope`, and those examples go through `Demo.lean`'s `decidable_of_iff` instances. |
| `GraphScopeTests/InsertTests.lean` (header) | Added `import Lean.Meta.ExprDefEq` with an explanatory comment. | Fixes the interrupted agent's breakage (`Unknown identifier Meta.backward.isDefEq.respectTransparency.types.get`). The constant exists (`opaque Lean.Meta.backward.isDefEq.respectTransparency.types : Lean.Option Bool`, registered in `Lean/Meta/ExprDefEq.lean` inside `namespace Lean.Meta`), but on v4.34.0 core, Mathlib and ProofWidgets are all `module` files, so a non-`module` file only sees their *public* import closure, and `Lean.Meta.ExprDefEq` is not publicly re-exported along the Mathlib/ProofWidgets path (while e.g. `Lean.maxRecDepth` from `Lean.Data.Options` is). Verified: same `#check` fails after `import GraphScopeTests.Helpers` and succeeds after adding `import Lean.Meta.ExprDefEq`. Test-only import; the library is unchanged. |
| `README.md` | Toolchain line → v4.34.0 / Mathlib v4.34.0 with a pointer to this file; assertion count 422 → 426 in both places. | Version/count bookkeeping (see Counts). |

No library file (`GraphScope/*.lean`, `GraphScope.lean`) changed: the whole
`SimpleGraph` surface the package uses (`Mathlib.Combinatorics.SimpleGraph.Basic`,
`.Hasse`, `.CycleGraph`, `.Connectivity.Finite`, `Mathlib.Data.Quot`) is still
canonical on Mathlib v4.34.0 (none of those files carries `deprecated_module`;
the Aug-2026 shims live under `SimpleGraph/Walks/*`, `Coloring*`,
`Connectivity/WalkCounting|WalkDecomp`, `EdgeLabeling`, `ConcreteColorings`,
which GraphScope never imported).  `evalExpr`, the `Decidable` instances for
`pathGraph` / `completeBipartiteGraph`, `MakeEditLink` / `mk_rpc_widget%` and the
Layered layout all compile and test unchanged.

## Pin updates

None.  Every `#guard_msgs` docstring, `#guard` value, text-mode report, error
message and insertion-suggestion table from the reference passes verbatim on
v4.34.0 (including the `Fintype Bool` enumeration order, the `Repr (Subtype p)`
label shape, the `decide` budget replicas and the exact noncomputable-instance
error texts).  The only new pins are the ones in the new test section above
(`info: true` for the option default, and "no messages" for the four `decide`
examples), each verified by running.

## Deviations

None.  No test was deleted, weakened or commented out; no feature was dropped;
no `sorry`; no global option/linter suppression; `lake update` was not re-run
and `lakefile.toml` / `lean-toolchain` were not edited.

Minor bookkeeping note (not a port deviation): the reference README states
"422 compile-time assertion commands", but the README's own counting method
(below) yields **421** on the reference sources — the reference README was
already off by one.  The ported README now states the verified figure.

## Counts

Method (from the README): line-leading `#guard`, `#guard_msgs`,
`#assert_graph_invariants` and `#assert_gate` commands in `GraphScopeTests/*.lean`
(`grep -cE '^(#guard|#guard_msgs|#assert_graph_invariants|#assert_gate)\b'`).

| File | reference v4.32.2 | ported v4.34.0 |
|---|---:|---:|
| AlgoTests | 72 | 72 |
| ClickE2E | 16 | 16 |
| CommandTests | 43 | 43 |
| ContractTests | 20 | 20 |
| InsertTests | 90 | **95** (+5 new, see Changes) |
| LayoutTests | 35 | 35 |
| ModelTests | 35 | 35 |
| OverlayTests | 24 | 24 |
| PropertyTests | 31 | 31 |
| RenderTests | 55 | 55 |
| **Total** | **421** (README said 422) | **426** |

By kind (reference): 327 `#guard`, 65 `#guard_msgs`, 11 `#assert_graph_invariants`,
18 `#assert_gate`.  Ported: 327 / 70 / 11 / 18.  Not counted by the method but
also unchanged: 13 `#assert_insertions_compile` (each compiles every generated
insertion text), 54 `#graph_scope` commands under `#guard_msgs`, and the
ClickE2E subprocess scenarios.

## 4.34 gotchas worth knowing for QED64

1. **`backward.isDefEq.respectTransparency.types` now defaults to `true`.**
   v4.32.2 registered it with `defValue := false -- TODO: replace with true
   after we fix stage0`; v4.34.0 ships `true` (`Lean/Meta/ExprDefEq.lean:57`).
   `backward.isDefEq.respectTransparency` itself was already `true` on both.
   Effect: when a metavariable is assigned, its type is compared with the
   term's type at *implicit* transparency instead of being bumped to
   `.default`, so instances/definitions that used to unfold during that check
   no longer do unless they are `[implicit_reducible]`.  For GraphScope this
   did **not** bite: `Demo.lean`'s `decidable_of_iff` instances for
   `pathGraph` and `completeBipartiteGraph` still let `by decide` prove
   adjacency, degree and connectivity facts under the defaults (pinned in
   `InsertTests.lean`).  The QED64 owner's observation that `deriving Fintype`
   needs `set_option backward.isDefEq.respectTransparency false in` is not
   exercised here — this package has no `deriving Fintype` (only `Repr`, `BEq`,
   `Inhabited`, `ToJson`, `FromJson`, `RpcEncodable`).  If a QED64 showcase
   file does derive `Fintype`, scope the option to that declaration rather than
   the file.
2. **Module system visibility.** Core, Mathlib and ProofWidgets are now
   `module` files.  A plain (non-`module`) file that imports them sees only
   their *public* import closure.  Concretely: `Lean.Meta.backward.isDefEq.*`
   (and other `Lean.Meta` internals) were not visible after `import Mathlib…`
   / `import ProofWidgets…` and needed an explicit `import Lean.Meta.ExprDefEq`
   (or `import Lean`).  If a QED64 playground snippet references a Lean-internal
   constant and gets `Unknown identifier` despite importing Mathlib, add the
   defining module's import — the olean is already loaded, only its names
   are hidden.  Note that the *option names* still work in `set_option`
   (options are looked up in the runtime registry, `Lean.getOptionDecl`),
   only the constants are hidden.
3. **`String.toFileMap` → `Lean.String.toFileMap`** (`Lean/Data/Position.lean`).
   Field notation on a `String` no longer finds it without `open Lean`; use
   `Lean.FileMap.ofString` or open the namespace.  Relevant to any widget code
   that fabricates a `DocumentMeta` for tests.
4. **Mathlib SimpleGraph reorganisation is benign for these imports.**  The
   modules GraphScope uses (`SimpleGraph.Basic`, `.Hasse`, `.CycleGraph`,
   `.Connectivity.Finite`) are canonical on v4.34.0; the `deprecated_module`
   shims are the `Walks/*`, `Coloring*`, `Connectivity/WalkCounting`,
   `Connectivity/WalkDecomp`, `EdgeLabeling` and `ConcreteColorings` files.
   A clean rebuild produced no deprecation warnings, so no `set_option
   linter.deprecated` scoping was needed.
5. **Nothing else moved.**  `Lean.Meta.evalExpr` (`safety := .unsafe`),
   `Lean.Core.checkSystem`, `Lean.Parser.runParserCategory`,
   `String.Pos.Raw.extract`, `MakeEditLinkProps.ofReplaceRange`,
   `mk_rpc_widget%`, `RequestM.readDoc` and ProofWidgets' `Html` all have the
   same signatures the v4.32.2 package relied on; `Fintype Bool` still
   enumerates `true` first and core's `Repr (Subtype p)` still prints the bare
   value — both are pinned by tests that stayed green.
