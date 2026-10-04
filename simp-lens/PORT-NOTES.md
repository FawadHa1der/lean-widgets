# Port notes — simp-lens: Lean v4.32.2 → v4.34.0 (QED64 pairing)

Reference (read-only): `../../widgets/simp-lens` (lean4 v4.32.2, ProofWidgets
`6e311e2a`). Ported tree: this directory (lean4 v4.34.0, ProofWidgets
`106ff4fafc74ef4ac99d81dbf3ab399118f497a5`, fresh `lake-manifest.json`; no
`lake update` was run during the port).

Result: `lake build` and `lake test` both exit 0 on a clean `.lake/build`
(`rm -rf .lake/build` before the final run), with **zero warnings** in either
log. Everything below is the *complete* diff against the reference apart from
`lean-toolchain`, `lakefile.toml` and `lake-manifest.json` (which were bumped
before the port started).

## Changes

| File | What | Why |
|---|---|---|
| `SimpLensTests/Helpers.lean` | Renamed the test helper `assert (cond : Bool) (msg : MessageData) : MetaM Unit` to `assertThat`; updated its 23 call sites (all in this file — `ClickE2E.lean` only uses the word in prose). No semantic change. | v4.34 adds the `doAssertion` do-element (`Lean/Parser/Do.lean`: `nonReservedSymbol "assert" (includeIdent := true)`, priority `default+10`) for the experimental intrinsic-verification syntax. A do-block line starting with the identifier `assert` is now parsed as that element, so `assert cond m!"…"` failed with "Function expected at … but this term has type Bool" plus a `Std.Internal.Do.WPMonad MetaM` instance failure and an `experimental.intrinsic` warning. A rename is the only honest fix (a `set_option experimental.intrinsic true` would silence the warning but not the parse). |
| `SimpLens/Demo.lean` (line ~85) | `#guard_msgs` pin of the `linter.unusedSimpArgs` hint for `simp_lens [Nat.mul_one]` updated (see Pin updates). Docstring of that example reworded ("strike-through hint" → "`[apply] simp` hint"). | Genuine new toolchain output, see below. |
| `SimpLensTests/TacticTests.lean` (lines ~66, ~80) | The same pin for `simp_lens [Nat.mul_one]` and its plain-`simp [Nat.mul_one]` twin updated. | Same. The twin pair is now byte-identical (on 4.32.2 they differed only in the struck-through call text), which is a stronger parity statement than before. |
| `README.md` | Toolchain/ProofWidgets pin line; hint description; new "Assertion census" paragraph (404). | Versions/limitations changed. |
| `PORT-NOTES.md` | This file. | Required deliverable. |

Not changed (verified compiling and behaving identically under 4.34 without
any edit): `SimpLens/Trace.lean`, `Film.lean`, `Minimize.lean`,
`Exclude.lean`, `Render.lean`, `Tactic.lean`, `SimpLens.lean`,
`SimpLensTests.lean`, and all test modules other than `Helpers.lean` /
`TacticTests.lean`.

## Pin updates

Three `#guard_msgs` docstrings, all the same message. Verified by running the
build and copying the toolchain's actual output.

Old (v4.32.2), `simp_lens [Nat.mul_one]` in `Demo.lean` and `TacticTests.lean`:

```
Hint: Omit it from the simp argument list.
  simp_̵l̵e̵n̵s̵ ̵[̵N̵a̵t̵.̵m̵u̵l̵_̵o̵n̵e̵]̵
```

Old (v4.32.2), plain `simp [Nat.mul_one]` twin in `TacticTests.lean`:

```
Hint: Omit it from the simp argument list.
  simp ̵[̵N̵a̵t̵.̵m̵u̵l̵_̵o̵n̵e̵]̵
```

New (v4.34.0), all three:

```
Hint: Omit it from the simp argument list.
  [apply] simp
```

Reason: `Lean/Linter/UnusedSimpArgs.lean` changed exactly one line between
the two toolchains —

```diff
-  let suggestion := { suggestion with span? := stx }
+  let suggestion := { suggestion with span? := stx, diffGranularity := .none }
```

— so the hint no longer renders a character-level diff of the source span
(`Meta.Hint` skips `readableDiff` when `diffGranularity` is `.none`) and
prints the suggestion syntax itself as an `[apply] …` line instead. The
suggestion syntax is `setSimpParams stx otherArgs` where `stx` is the syntax
carried by the `UnusedSimpArgsInfo` leaf; `simp_lens` pushes its rebuilt
core-`simp` syntax there (the linter only accepts kind `simp`/`simpAll`), so
it prints as `simp`. **The edit a click performs is unchanged**: on both
toolchains the code action replaces the `simp_lens [Nat.mul_one]` span with
`simp` (this was already documented in the test comment at
`TacticTests.lean:55-57`). Only the message rendering moved; no package code
was involved in the change and the other 82 `#guard_msgs` pins (all `Try
this:` suggestions, no-progress errors, unsolved-goals reports, heartbeat
twins) were unaffected.

## Deviations

None. No test was deleted, commented out or weakened; no feature was dropped;
no `sorry`; no global option/linter suppression. The only non-pin code change
is the `assert` → `assertThat` rename in the test helper.

One cosmetic point worth knowing (not a deviation, since it is core's
rendering of core's own suggestion): the unused-argument hint now literally
reads `[apply] simp` under a `simp_lens` call. A reader might wish it said
`simp_lens`; that would require the linter to accept the `simp_lens` syntax
kind, and it would then *also* change the click semantics (which today
rewrites to plain `simp`). Left exactly as core produces it.

## Counts

Method (the README's own: compile-time assertion commands — `#guard`,
`#guard_msgs`, custom `#lens_*` / `#lens_at_*`, and the `#e2e_*` click
harness commands), counted as lines starting with such a command across
`SimpLens/`, `SimpLensTests/`, `SimpLens.lean`, `SimpLensTests.lean`:

```
grep -rhoE "^#[a-z_0-9]+" SimpLens SimpLensTests SimpLens.lean SimpLensTests.lean | sort | uniq -c
```

| | reference (v4.32.2) | ported (v4.34.0) |
|---|---|---|
| `#guard` | 106 | 106 |
| `#guard_msgs` | 85 | 85 |
| `#lens_*` / `#lens_at_*` (35 kinds) | 202 | 202 |
| `#e2e_click` / `#e2e_click_warn` / `#e2e_click_open` / `#e2e_negative` | 8 / 1 / 1 / 1 | 8 / 1 / 1 / 1 |
| **Total** | **404** | **404** |

Per-kind breakdown is identical line for line (both trees were counted with
the same command). The `#e2e_*` commands each perform several internal checks
(pin compare, recompile, zero-messages / pinned-error / leftover-token /
negative-control checks), so the effective check count is higher than 404 on
both sides; the census counts commands, not internal checks, exactly as the
reference README does.

## 4.34 gotchas worth knowing for QED64

Ground truth from `~/.elan/toolchains/leanprover--lean4---v4.34.0/src/lean/`
diffed against `…v4.32.2/src/lean/`.

1. **`assert` is a do-element now.** `Lean/Parser/Do.lean` gained
   `doAssertion` (`assert P` / `assert s => P s`, part of the experimental
   intrinsic verification syntax, priority `default+10`, `includeIdent :=
   true`). Any user-defined function named `assert` called at the head of a
   do-block line stops parsing as a function call. Symptoms: "Function
   expected at … but this term has type Bool", `Std.Internal.Do.WPMonad`
   synthesis failure, and a warning mentioning `experimental.intrinsic`.
   Rename the helper (`assertThat`, `check`, …). `assert!` is unaffected.
2. **`linter.unusedSimpArgs` hint renders `[apply] <call>` instead of a
   strike-through diff** (`diffGranularity := .none` in
   `Lean/Linter/UnusedSimpArgs.lean`). Any `#guard_msgs` pin of that warning
   needs the new text; the code action is unchanged. Pins of *other* hints
   that still use `.auto` granularity (e.g. `Try this:` from `TryThis`, which
   defaults to `.none` in `addSuggestion` on both toolchains) did not move.
3. **The simp-side API surface this package touches is unchanged**, verified
   by diff: `Simp.Methods` (`pre/post/dpre/dpost/discharge?/wellBehavedDischarge`),
   `Simp.Step` / `Simp.DStep`, `Simp.Diagnostics`, `Simp.Config` fields,
   `mainCore`, `simpTarget`, `simpGoal`, `applySimpResult(ToTarget)`,
   `mkMethods` / `mkDefaultMethodsCore`, `SimpTheoremsArray.eraseTheorem`,
   `SimprocsArray.erase`, `mkSimpContext (stx) (eraseLocal) (kind :=
   SimpKind.simp)`, `mkSimpOnly (stx) (usedSimps) : MetaM Syntax`,
   `simpLocation`, `warnUnusedSimpArgs`, `withSimpDiagnostics`,
   `TryThis.addSuggestion` (same signature incl. `origSpan?` and
   `diffGranularity := .none` default), `Core.tryCatchRuntimeEx` /
   `MonadRuntimeException`, `withCurrHeartbeats`, `IO.get/setNumHeartbeats`.
   Heartbeat-parity twin tests at tight `maxHeartbeats` pass unchanged, so
   the traced run's cost profile did not move on these examples.
4. **New `Lean.Meta.Sym.*` tree** (`Lean/Meta/Sym/Simp/…`, `…/DSimp/…`): the
   `grind`-side "Sym" simplifier defines its *own* `Simp.Methods`,
   `Simp.Config`, `simpGoal`, `mkMethods` under `Lean.Meta.Sym.Simp`. With
   `open Lean Meta Simp` the classic `Lean.Meta.Simp.*` still wins (the
   `Sym` namespace is not opened), but a grep for "structure Methods" or
   "def simpGoal" now returns two hits — check the namespace before copying
   a signature. Do not `open Lean.Meta.Sym`.
5. **Transparency ladder gained a level**: `none < reducible < instances <
   implicit < default < all` (new `[implicit_reducible]` /
   `[instance_reducible]` split, `Init/MetaTypes.lean`), and
   `backward.isDefEq.respectTransparency` docs changed (implicit and
   instance-implicit arguments now checked at `implicit` transparency; a
   separate `backward.isDefEq.respectTransparency.types` option exists). No
   effect observed on this package's simp runs (all lemma sets, step counts,
   landing goals and `Try this:` texts are byte-identical to 4.32.2 across
   all 85 `#guard_msgs` and every `#lens_*` pin), but a Mathlib-backed
   package whose simp calls hinge on instance unfolding could see different
   lemma sets or `simp made no progress` flips. Look here first if a
   `#lens_used` / `#lens_at_equiv` pin moves.
6. **`ClickE2E` in-process frontend still works unchanged**:
   `Parser.parseHeader` → `Elab.processHeader` → `Elab.IO.processCommands`,
   `Info.ofCustomInfo` / `TryThisInfo` extraction, `FileMap.lspRangeToUtf8Range`,
   `String.Pos.Raw.extract`, and the `enableInitializersExecution` trick for
   nested `importModules` all compile and pass on 4.34.0 with no edits. The
   pinned core-`TryThis` line-wrapping (width 100 from the call column,
   2-space continuation) is also unchanged.
7. **ProofWidgets `106ff4fa`** builds against 4.34.0 and needed no source
   changes here: `Html` JSX DSL, `HtmlDisplayPanel`, `InteractiveCode`,
   `Widget.ppExprTagged`, `rpcEncode`, `savePanelWidgetInfo` are all
   source-compatible with the `6e311e2a` pin.
