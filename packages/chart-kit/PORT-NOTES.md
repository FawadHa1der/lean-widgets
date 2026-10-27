# PORT-NOTES — chart-kit (lib `ChartKit`): Lean v4.32.2 → v4.34.0 → v4.35.0 (QED64 pairing)

Two ports, newest first: v4.34.0 → v4.35.0 (next section) and the earlier
v4.32.2 → v4.34.0 (last section).

## Lean 4.34.0 → 4.35.0 (2026-10-25)

Result: **`lake build` exit 0 and `lake test` exit 0 on `leanprover/lean4:v4.35.0`**,
with **zero warnings** in both logs (no deprecation notices, no linter output,
no replayed warnings). **No Lean source file changed**: the port is the three
harness-set config files plus documentation. Every ChartKit and ChartKitTests
module was recompiled by 4.35.0 (the toolchain change invalidates every build
trace: the harness's first `lake build` compiled the library jobs incl.
`ChartKit.Demo`, and the `lake test` below compiled all 8 test-library modules).

### Pins (set by the harness; not edited by this port)

| | 4.34 port (`qed64-pin-i`) | 4.35 port |
|---|---|---|
| `lean-toolchain` | `leanprover/lean4:v4.34.0` | `leanprover/lean4:v4.35.0` |
| ProofWidgets4 (`lakefile.toml` rev, manifest `rev`/`inputRev`) | `106ff4fafc74ef4ac99d81dbf3ab399118f497a5` | `df72b022e558978a1c50264cfc4d7fec86fa8e04` (= Mathlib v4.35.0's own ProofWidgets pin) |
| `lake-manifest.json` `"version"` | `1.2.0` | `1.3.0` (written by 4.35's Lake during the harness's single `lake update`) |

No Mathlib dependency (ProofWidgets is the only `require`), so no
`lake exe cache get` applied to this package.

### Changes

| File | What | Why |
|---|---|---|
| `lean-toolchain` | `v4.34.0` → `v4.35.0` | Harness (not edited here). |
| `lakefile.toml` | proofwidgets rev `106ff4fa…` → `df72b022…` | Harness (not edited here). |
| `lake-manifest.json` | same rev bump; manifest version `1.2.0` → `1.3.0` | Harness's single `lake update` (never re-run). |
| `README.md` | Versions sentence → Lean v4.35.0 / ProofWidgets `df72b022`; port-history clause extended. Post-audit: the v4.32.2 original is now located by the `lean-v4.32.2` tag. | Task requirement. |
| `PORT-NOTES.md` | This section. Post-audit: the title, gotcha 4, and a heading for the 4.34 notes. See *Post-audit fixes*. | Task requirement. |

`git diff qed64-pin-i -- packages/chart-kit` lists only the five files above.
`ChartKit/FloatBridge.lean`'s docstring ("checked on v4.32.2 and v4.34.0")
was deliberately left alone: it is still true, and re-checked on v4.35.0 —
`Init/Data/Float/Float.lean` still has `@[extern "lean_float_to_bits"] def
Float.toBits` (line 147) and `Float.frExp : Float → Float × Int` (line 288),
and still no `toRat`/`toRatParts` (the only new `Float` API is `Float.fma`).

### Golden/expected-output changes

**None.** All 18 `#guard_msgs` pins in `ChartKitTests/CommandTests.lean`, the
1 in `ChartKit/Demo.lean`, and every `#guard` produce identical output on
v4.35.0 and pass unmodified (including the pins that embed toolchain-produced
text: `#chart: failed to evaluate …`, the `sorry`/metavariable/noncomputable
refusals and the `(text := true)` reports).

### Deviations

**None.** No test deleted, commented out, skipped or weakened; no `sorry`; no
`set_option` of any scope; no feature dropped.

### Counts

Same census as the 4.34 section below and the README (`#guard` / `#guard_msgs in`
at the start of a line in `ChartKitTests.lean`, `ChartKitTests/*.lean`,
`ChartKit/Demo.lean`). "Before" counted on `git show qed64-pin-i:<path>`.

| Bucket | Before (4.34, `qed64-pin-i`) | After (4.35) |
|---|---:|---:|
| `#guard` in test library (`ChartKitTests.lean` 1, `ScaleTests` 90, `RenderTests` 54, `ModelTests` 37, `FloatTests` 28, `ContractTests` 26) | 236 | 236 |
| `#guard_msgs in` in test library (`CommandTests`) | 18 | 18 |
| `#guard` in `ChartKit/Demo.lean` | 6 | 6 |
| `#guard_msgs in` in `ChartKit/Demo.lean` | 1 | 1 |
| **Total** | **261** | **261** |

### 4.35 gotchas

1. **ProofWidgets `106ff4fa..df72b022` has zero `.lean` changes.**
   `git diff --stat` in `.lake/packages/proofwidgets` touches only
   `lean-toolchain` and `.github/workflows/build.yml`; the 7 commits are the
   v4.35.0-rc1 … v4.35.0 toolchain bumps and CI hardening (SHA-pinned
   actions, `GITHUB_TOKEN` permissions). So for a ProofWidgets-only package
   any 4.35 behaviour change must come from core, not from ProofWidgets.
2. **Lake writes manifest version `1.3.0`** (`Lake/Load/Manifest.lean:55`:
   "Add optional `copy` path dependency field"; a minor, backwards-compatible
   bump). Expect that one-line `lake-manifest.json` diff in every 4.35 bump;
   it is Lake's, not ours.
3. **Core APIs ChartKit uses are unchanged on 4.35**: `Init/Data/Rat/Basic.lean`
   and `Init/Guard.lean` are byte-identical between the v4.34.0 and v4.35.0
   toolchains; `Lean.Widget.savePanelWidgetInfo (hash : UInt64) (props :
   StateM Server.RpcObjectStore Json) (stx : Syntax) : CoreM Unit` has the same
   signature (now `Lean/Widget/UserWidget.lean:217`, was 216).
4. **The non-module-file warning does not apply here.** The warning reads
   "imports X from package P, which is designed for use with the module
   system; consider adding `module`…". It is neither new nor Mathlib-only. It
   is Lake's existing `requiresModuleSystem` check (`fetchImportInfo` in
   `lake/Lake/Build/Module.lean`). That code is byte-identical in v4.34.0
   (lines 404-411) and v4.35.0 (lines 416-423), and the option already existed
   in v4.34.0's `Lake/Config/LeanConfig.lean`. It fires whenever a
   non-`module` file imports a module of *any* package or library that sets
   `requiresModuleSystem := true`. Mathlib v4.35.0 newly sets it
   (`lakefile.lean:69`), which is why the Mathlib-backed sibling packages see
   it on 4.35. ProofWidgets `df72b022`'s lakefile does not set it, and core is
   not a Lake package of the workspace. ChartKit imports only ProofWidgets
   (`Data.Html`, `Component.HtmlDisplay`) and core. So the warning cannot
   appear in this package's build: both 4.35 logs have 0 warning lines. As a
   Lake log line, not a Lean message, it could never reach a `#guard_msgs`
   pin anyway. The conclusion is unchanged from the first version of this
   gotcha; only the stated cause was corrected after the audit.

### Post-audit fixes (2026-10-25)

The adversarial audit passed this package. All 3 source mutations were caught,
the clean rebuild was green with 0 warnings, and the counts matched
(261 = 261). It raised one minor finding. This pass edited only this file and
`README.md`; no `.lean` file, test or expected output was touched.

| Finding | Fix |
|---|---|
| Gotcha 4 called the "designed for use with the module system" warning new and said it fires only for Mathlib imports. It is Lake's existing `requiresModuleSystem` check, and it fires for any package that sets the option. | Gotcha 4 reworded. The Lake check is byte-identical in v4.34.0 and v4.35.0. What is new is that Mathlib v4.35.0 sets `requiresModuleSystem := true`. ProofWidgets `df72b022` does not, and core is not a workspace package. The conclusion is unchanged: no warning can reach this package's logs or pins. |

Three related edits:

- The H1 title now names both ports.
- The previous port's notes now sit under their own
  `## Lean v4.32.2 → v4.34.0 (previous port)` heading, which replaces the
  `---` rule and italic line, and their subheadings were demoted one level.
- The README no longer says the v4.32.2 original is in a sibling
  `widgets/chart-kit` tree, which is not on disk any more. It now points to
  the repository tag `lean-v4.32.2`, which holds the same sources.

Counts were recounted mechanically with the method in *Counts* on the v4.32.2
original (`lean-v4.32.2`), on `qed64-pin-i` and on this tree. The test library
has 236 `#guard` (ScaleTests 90, RenderTests 54, ModelTests 37, FloatTests 28,
ContractTests 26, root 1) and 18 `#guard_msgs in`; `Demo.lean` has 6 `#guard`
and 1 `#guard_msgs in`. That is 261 in all three trees. A second count, which
strips comments and docstrings first, agrees: 242 = 236 + 6 `#guard` and
19 = 18 + 1 `#guard_msgs`.

### Verification transcript

Both commands ran through the shared build lock in one wrapper invocation
(lane `port435-chart-kit-build-test`):

```
BROWSER_LOCK_DIR=$HOME/.cache/lean-widgets-build-lock MIN_FREE_GB=10 LOCK_WAIT_S=43200 COOLDOWN_WAIT_S=7200 \
  bash ".../widgets-v4.34/qed64-showcase/scripts/with-browser-lock.sh" port435-chart-kit-build-test \
  bash -c 'cd ".../widgets-v4.34/packages/chart-kit" && lake build; …; lake test; …'
```

```
### lake build
Build completed successfully (21 jobs).
### lake build rc=0
### lake test
✔ [21/28] Built ChartKitTests.Helpers (332ms)
✔ [22/28] Built ChartKitTests.CommandTests (568ms)
✔ [23/28] Built ChartKitTests.ModelTests (609ms)
✔ [24/28] Built ChartKitTests.FloatTests (603ms)
✔ [25/28] Built ChartKitTests.RenderTests (676ms)
✔ [26/28] Built ChartKitTests.ContractTests (603ms)
✔ [27/28] Built ChartKitTests.ScaleTests (732ms)
✔ [28/28] Built ChartKitTests (252ms)
### lake test rc=0
browser-lock: command exited rc=0
```

Harness first build on 4.35 (`port435/chart-kit.build0.log`): `Build completed
successfully (21 jobs).`, no warnings.

Post-audit verification (2026-10-25), through the shared lock (`BROWSER_LOCK_DIR=$HOME/.cache/lean-widgets-build-lock MIN_FREE_GB=<10|20> LOCK_WAIT_S=43200 COOLDOWN_WAIT_S=7200 bash ".../widgets-v4.34/qed64-showcase/scripts/with-browser-lock.sh" <lane> …`):

1. Lane `port435-fix-chart-kit-buildtest` (`MIN_FREE_GB=10`): `lake build` printed
   `Build completed successfully (21 jobs).` with rc 0. `lake test` was up to date and
   printed nothing, rc 0. Then `browser-lock: command exited rc=0`.
2. Lane `port435-fix-ii-ts-ex-ck-cleanfinal` (`MIN_FREE_GB=20`) first deleted this
   package's own outputs, `.lake/build/{lib/lean,ir}/ChartKit*`, leaving 0 entries;
   `.lake/packages` was not touched. It then ran `lake build` and `time lake test`. All 15
   own modules (7 library, 8 test) were rebuilt, with 0 warning or error lines:
   ```
   ✔ [20/21] Built ChartKit (215ms)
   Build completed successfully (21 jobs).
   ### lake build rc=0
   ✔ [27/28] Built ChartKitTests.RenderTests (547ms)
   ✔ [28/28] Built ChartKitTests (220ms)
   real	0m1.353s
   ### lake test rc=0
   browser-lock: command exited rc=0
   ```

Both runs were made after the documentation edits. Any later edit in this pass touched only Markdown files, which are not Lake inputs. `git status` lists no change under this package besides `PORT-NOTES.md`, `README.md` and the three harness files.


## Lean v4.32.2 → v4.34.0 (previous port)

*The notes below are the previous port. They are unchanged except that their
headings were demoted one level (post-audit, 2026-10-25) so they sit under
this section.*

Reference (read-only): `widgets/chart-kit` — `leanprover/lean4:v4.32.2`,
ProofWidgets4 `6e311e2a844da9b2cc3971187df2fe0066947b93`.
Ported: `widgets-v4.34/chart-kit` — `leanprover/lean4:v4.34.0`,
ProofWidgets4 `106ff4fafc74ef4ac99d81dbf3ab399118f497a5`.

Result: **`lake build` exit 0 and `lake test` exit 0**, verified on a clean
tree (`rm -rf .lake/build` then full rebuild) with **zero warnings** — no
deprecation notices, no linter output. No `set_option` was needed anywhere.

### Changes

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

#### Why nothing broke (risk list, checked against the pinned sources)

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

### Pin updates

**None.** Every `#guard_msgs` pin (18 in `ChartKitTests/CommandTests.lean`,
1 in `ChartKit/Demo.lean`) and every `#guard` pin produces the identical
output on v4.34.0; they pass unmodified. In particular the error-message pins
that embed toolchain-produced text (`#chart: failed to evaluate …`, the
`sorry`/metavariable/noncomputable refusals, and the `(text := true)`
reports) are byte-identical between the two toolchains.

### Deviations

**None.** No test deleted, commented out, or weakened; no feature dropped;
no global option or linter suppression; no `sorry`.

### Counts

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

### 4.34 gotchas worth knowing for QED64

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
