# PORT-NOTES — chart-kit (lib `ChartKit`), v4.32.2 → QED64 pairing (v4.34.0)

Reference (read-only): `widgets/chart-kit` — `leanprover/lean4:v4.32.2`,
ProofWidgets4 `6e311e2a844da9b2cc3971187df2fe0066947b93`.
Ported: `widgets-v4.34/chart-kit` — `leanprover/lean4:v4.34.0`,
ProofWidgets4 `106ff4fafc74ef4ac99d81dbf3ab399118f497a5`.

Result: **`lake build` exit 0 and `lake test` exit 0**, verified on a clean
tree (`rm -rf .lake/build` then full rebuild) with **zero warnings** — no
deprecation notices, no linter output. No `set_option` was needed anywhere.

## Changes

The Lean source tree is byte-identical to the reference except for one
docstring. `diff -r --exclude=.lake widgets/chart-kit widgets-v4.34/chart-kit`
reports only the three pre-set config files plus the docstring below.

| File | What | Why |
|---|---|---|
| `lean-toolchain` | `v4.32.2` → `v4.34.0` | Pre-set by the harness (not edited by this port). |
| `lakefile.toml` | proofwidgets rev `6e311e2…` → `106ff4f…` | Pre-set by the harness (not edited by this port). |
| `lake-manifest.json` | same rev bump | Pre-set by the harness; never re-ran `lake update`. |
| `ChartKit/FloatBridge.lean` | Module docstring: "Core v4.32.2 has no ready-made exact `Float → Rat`" → "Core Lean (checked on v4.32.2 and v4.34.0) has no ready-made exact `Float → Rat`". | Documentation accuracy only. Verified by grep: `Init/Data/Float/Float.lean` on v4.34.0 still has no `toRat`/`toRatParts`; `Float.frExp : Float → Float × Int` still returns the mantissa as a `Float`. Zero behaviour change. |
| `README.md` | Pins updated to v4.34.0 / `106ff4f`; test census corrected (see Counts); census method written down. | Task requirement; the old numbers were an undercount that predates the port. |
| `PORT-NOTES.md` | This file. | Task requirement. |

No API adaptations, no renamed lemmas, no module moves, no new `set_option`,
no `sorry`, no tests removed or weakened, no features dropped.

### Why nothing broke (risk list, checked against the pinned sources)

* **`Float.toBits` / FloatBridge exactness.** `Float.toBits : Float → UInt64`
  is still `@[extern "lean_float_to_bits"]` in
  `~/.elan/toolchains/leanprover--lean4---v4.34.0/src/lean/Init/Data/Float/Float.lean:147`
  — the same C-level bit view. All 28 `#guard`s in
  `ChartKitTests/FloatTests.lean` (dyadics, `0.1` = `3602879701896397/2^55`,
  `0.2`, `0.1+0.2 ≠ 0.3`, smallest subnormal `5e-324 = 2^-1074`, largest
  finite double `(2^53-1)·2^971`, signed zero, ±∞/NaN refusal, `Series.ofFloats`
  messages) evaluate exactly as pinned on 4.34.0. Float *literal* parsing
  (`OfScientific Float`) also did not change semantics for these pins.
* **Rat API.** `Rat` still lives in `Init/Data/Rat/Basic.lean` (same path on
  both toolchains, not `Std.Internal.Rat`). The only diffs in that file between
  the two toolchains are: the import `Init.Data.OfScientific` →
  `Init.Data.OfScientific.Basic` (irrelevant to users) and a new
  `@[implicit_reducible]` on `Rat.neg`. `Pow Rat Nat` (`Rat.pow`) and
  `Pow Rat Int` (`Rat.zpow`, used by `ChartKit.pow2`) are unchanged.
  `#guard` "uses the untrusted evaluator" (`Init/Guard.lean:125-127`,
  `syntax (name := guardCmd) "#guard " term : command`), not `rfl`/`decide`
  defeq checking, so reducibility attributes cannot change its outcome; all
  pins pass.
* **ProofWidgets 106ff4f types.** ChartKit imports only
  `ProofWidgets.Data.Html` and `ProofWidgets.Component.HtmlDisplay`. Between
  `6e311e2` and `106ff4f` the ProofWidgets diff (`git diff --stat`, `.lean`
  only) touches `ProofWidgets.lean` (root re-exports reordered / new
  components exported), `Component/MakeEditLink.lean`,
  `Component/RefreshComponent.lean` (mutex instead of unsafe `IO.Ref`),
  `Data/Svg.lean` (a **private** `Int.toFloat` helper removed — private, so it
  cannot have been visible downstream) and
  `Util.lean` (`open SubExpr` → `open Delaborator.SubExpr`). Neither of the
  two modules ChartKit uses changed; `inductive Html … deriving RpcEncodable`
  and `HtmlDisplayPanel : Component HtmlDisplayProps` are identical.
  Core `Lean.Widget.savePanelWidgetInfo (hash : UInt64) (props : StateM
  Server.RpcObjectStore Json) (stx : Syntax)` (`Lean/Widget/UserWidget.lean:216`)
  matches the call in `ChartKit/Widget.lean` unchanged.

## Pin updates

**None.** Every `#guard_msgs` pin (18 in `ChartKitTests/CommandTests.lean`,
1 in `ChartKit/Demo.lean`) and every `#guard` pin produces the identical
output on v4.34.0; they pass unmodified. In particular the error-message pins
that embed toolchain-produced text (`#chart: failed to evaluate …`, the
`sorry`/metavariable/noncomputable refusals, and the `(text := true)`
reports) are byte-identical between the two toolchains.

## Deviations

**None.** No test deleted, commented out, or weakened; no feature dropped;
no global option or linter suppression; no `sorry`.

## Counts

Census method (now documented in the README): count `#guard` directives at
the start of a line in `ChartKitTests.lean` + `ChartKitTests/*.lean` and in
`ChartKit/Demo.lean`, plus `#guard_msgs in` directives in the same files;
docstring mentions of the directives are excluded.

| Bucket | Reference (v4.32.2) | Ported (v4.34.0) |
|---|---:|---:|
| `#guard` in test library (`ChartKitTests.lean` 1, `ScaleTests` 90, `RenderTests` 54, `ModelTests` 37, `FloatTests` 28, `ContractTests` 26) | 236 | 236 |
| `#guard_msgs in` in test library (`CommandTests`) | 18 | 18 |
| `#guard` in `ChartKit/Demo.lean` | 6 | 6 |
| `#guard_msgs in` in `ChartKit/Demo.lean` | 1 | 1 |
| **Total** | **261** | **261** |

Ported ≥ reference: equal, 261 = 261 (the same directives, unchanged).

Note on the README's previous "230 + 18 + 6 + 1 = 255": that number was
already wrong for the *reference* tree (the reference source is identical and
also contains 236 test-library `#guard`s). The README now states 236 / 261
with the counting method, so the discrepancy is a documentation fix, not a
test change. Nothing was added or removed.

## 4.34 gotchas worth knowing for QED64

Observed while grepping the pinned sources for this port (none of them bit
ChartKit, but they are the things most likely to bite a sibling package):

1. **`backward.isDefEq.respectTransparency`** (`Init/MetaTypes.lean:82-107`).
   4.34's `isDefEq` now respects transparency settings more strictly;
   several core files (`Init/Data/Array/Count.lean`, `Array/DecidableEq.lean`,
   `Array/Bootstrap.lean`, `GrindInstances/Ring/Fin.lean`) carry
   `set_option backward.isDefEq.respectTransparency false in` on individual
   declarations. Related: core now marks selected defs `@[implicit_reducible]`
   (e.g. `Rat.neg` in `Init/Data/Rat/Basic.lean:278`). If a proof-heavy
   package's `rfl`/`decide`/`simp` proofs about `Rat`/`Array` start failing
   with "not definitionally equal" on 4.34, scope that option on the affected
   declaration rather than globally. ChartKit's `#guard`s are evaluated, not
   `rfl`-proved, so they are immune.
2. **`Init.Data.OfScientific` → `Init.Data.OfScientific.Basic`.** Module was
   split; anything importing the old name directly needs the new one. ChartKit
   only uses it transitively through `Init`.
3. **ProofWidgets `Util.lean`: `open SubExpr` → `open Delaborator.SubExpr`.**
   In 4.34 `Lean.PrettyPrinter.Delaborator.SubExpr` resolution inside
   `namespace Lean.PrettyPrinter.Delaborator` needs the qualified name.
   Packages that write custom delaborators (graph-scope-style) may hit this.
4. **ProofWidgets root re-exports changed.** `import ProofWidgets` now also
   exports `Component.ForceGraphDisplay`, `Component.Maximizable`,
   `Component.RefreshComponent`. Importing the specific modules you need (as
   ChartKit does: `Data.Html`, `Component.HtmlDisplay`) keeps a package
   insulated from such churn and from the `RefreshComponent` mutex rewrite.
5. **`Float` → `Rat` still has no core primitive on 4.34** (`Float.frExp`
   returns `Float × Int`, no `toRatParts`). `Float.toBits` remains the only
   exact route; ChartKit's `floatToRat?` is still the right tool.
6. **Zsh + paths with spaces.** Not a Lean gotcha, but every command in this
   port needed quoted paths and `${pipestatus[1]}` (lowercase) for exit
   codes; `${PIPESTATUS[0]}` silently prints empty in zsh.
