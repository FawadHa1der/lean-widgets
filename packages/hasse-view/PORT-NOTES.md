# Port notes — hasse-view: Lean v4.32.2 → v4.34.0 → v4.35.0 (QED64 pairing)

## Lean 4.34.0 → 4.35.0 (2026-10-25)

Result: `lake build` and `lake test` both exit 0 on 4.35.0 after a clean
`rm -rf .lake/build` (zero `Built Mathlib` jobs: Mathlib oleans come from the
cache). **The port needed no Lean code change and no test change.** Every
module of `HasseView/` and `HasseViewTests/` compiles and every pin holds
byte for byte. The port's diff is documentation only: two module docstrings
(one of them corrects a statement about Mathlib that v4.35.0 made false), the
README and this file. The post-audit pass (see "Post-audit fixes" below)
added 13 instance-selection assertions to `HasseViewTests/LinkTests.lean`
and touched only documentation otherwise: the README, this file, and one
comment-only edit to the `Links.lean` module docstring (lines 49-52, see
post-audit finding 1). No library code and no existing assertion changed.
The only warnings in either log are the 10 expected Lake "designed for use
with the module system" lines on four library modules (see gotcha 2); the
test modules emit none.

### Pins (set by the harness before the port started)

| | v4.34.0 (`qed64-pin-i`) | v4.35.0 (this tree) |
|---|---|---|
| `lean-toolchain` | `leanprover/lean4:v4.34.0` | `leanprover/lean4:v4.35.0` |
| `lakefile.toml` mathlib `rev` | `v4.34.0` (`5ed29652`) | `v4.35.0` (`56a005855ea17e0b0958f73ec801ae140b0a1679`) |
| ProofWidgets (transitive, from Mathlib's manifest) | `106ff4fa` | `df72b022e558978a1c50264cfc4d7fec86fa8e04` |
| Batteries / Aesop / Qq / plausible / importGraph / LeanSearchClient / Cli | (4.34 pins) | `66e46918` / `4a174c49` / `dce0ad79` / `dfa4f381` / `a41f0e9a` / `d6b4c7be` / `c24fe607` (v4.35.0) |

This package requires only `mathlib`, so ProofWidgets is not pinned in
`lakefile.toml`. The harness ran the one allowed `lake update` and
`lake exe cache get` ("No files to download", 9,031 files already
decompressed), and its first `lake build` was green (967 jobs). This port
ran no dependency-changing command.

### Changes

| File | What | Why |
|---|---|---|
| `HasseView/Links.lean` (module docstring, "The `⋖` decidability instance") | "Mathlib (v4.34.0 pin) only makes `· ⋖ ·` decidable for `Bool`" rewritten: Mathlib v4.35.0 provides `Fintype.instDecidableRelCovByOfDecidableLT`, which needs `[DecidableLT V]`; hand-written orders such as `Bowtie`, and `Bool × Bool`, lack that instance; HasseView's instance needs only `DecidableLE` and is the one selected wherever `HasseView` is imported. The post-audit pass later edited lines 49-52 of this paragraph, comment-only (see "Post-audit fixes", finding 1). | Mathlib PR #40728 (`1afbf2aa632`, 2026-10-12) **removed** `Bool.instDecidableRelCovBy` / `Bool.instDecidableRelWCovBy` from `Mathlib/Order/Cover.lean` and **added** general instances at `Mathlib/Data/Fintype/Defs.lean:261,265`, so the old sentence was false. Verified by probe (below). Documentation only. The instance itself is unchanged. |
| `HasseView/Extract.lean` (module docstring, item 2) | "in v4.34.0 `DecidableLE V` is a reducible abbreviation" → "in v4.35.0". | `Init/Prelude.lean:1417` in the v4.35.0 toolchain still reads `abbrev DecidableLE (α : Type u) [LE α] := DecidableRel (LE.le : α → α → Prop)` (line 1302 on v4.34.0). Version string only. |
| `README.md` | The same `DecidableLE` version string. The cover-link bullet now names Mathlib's new instance and its `DecidableLT` requirement instead of "Mathlib's pin only has the `Bool` instance". The "Verifying" pins are now `v4.35.0` / `56a00585` / `df72b022`. | Versions changed, and the Mathlib claim changed as in `Links.lean`. |
| `PORT-NOTES.md` | This section. The title gained "→ v4.35.0", and a heading now marks the previous port's notes. | Required deliverable. |

Not changed by the port: `HasseView/{Model,Layout,Render,Gate,Widget,Demo}.lean`,
`HasseView.lean`, `HasseViewTests.lean` and all ten test modules.
After the port, `diff -r` of `HasseViewTests/` and `HasseViewTests.lean`
against `git show qed64-pin-i:…` was empty; after the post-audit pass it
shows only the section added to `LinkTests.lean`. Neither pass added a
`set_option` or renamed or re-imported anything.

### `instDecidableRelCovByOfFintype` at Mathlib v4.35.0: still valid, still needed

I compiled two throwaway probe files with `lake env lean` under the lock.
They lived outside the package and are not part of it.

* **With `import HasseView`**, `#synth DecidableRel (· ⋖ · : V → V → Prop)`
  returns `HasseView.instDecidableRelCovByOfFintype` for the four linkable
  `Demo.lean` types (`Fin 5`, `Bool × Bool`, `Finset (Fin 3)`, `Bowtie`) and
  for `Bool` (a `CommandTests` type; the fifth `Demo.lean` type, `Div12`,
  has no `Preorder`, so no `⋖` instance applies to it). The same
  holds for the per-pair `Decidable ((1 : Fin 5) ⋖ 2)` and
  `Decidable ((1 : Bowtie) ⋖ 3)`. Both instances have the default priority,
  and HasseView's is declared later, so instance search tries it first. The
  inserted `by decide` examples and the gate's `synthInstance` + `evalExpr`
  therefore resolve exactly as on 4.34. (This probe was out of tree; the
  post-audit pass turned it into in-tree assertions, see "Post-audit
  fixes".)
* **Mathlib v4.35.0 alone** (no HasseView; same Mathlib imports and the
  `Bowtie` instances copied verbatim): Mathlib's
  `Fintype.instDecidableRelCovByOfDecidableLT` closes the `Fin 5`, `Bool`
  and `Finset (Fin 3)` cover examples. It fails with "failed to synthesize
  `Decidable ((false, false) ⋖ (false, true))`" for `Bool × Bool`, and with
  "failed to synthesize `Decidable (1 ⋖ 3)`" for `Bowtie`. Neither type has a
  `DecidableLT` instance: `decidableLTOfDecidableLE` is a `def`, not an
  instance (`Mathlib/Order/Defs/PartialOrder.lean:140`), and the product
  `Preorder` has none. Without the package's instance, two of the four
  linkable demo types would lose their cover links' `by decide`, as would
  ClickE2E's whole `𝓑`/`Bowtie` user file. So the instance stays, unchanged.

Both instances are `Decidable` and therefore subsingletons, so the overlap
cannot cause a diamond. Kernel `decide` works through either.

### Golden / expected-output changes

None. All 29 `#guard_msgs` docstrings (26 in `CommandTests.lean`, 3 in
`LinkTests.lean`) pass unchanged. So do all byte-exact `#guard` pins (text
reports, SVG fragments, layout coordinates, the serialized `MakeEditLink`
nodes with their edit JSON, the `⟨7, 35⟩` UTF-16 cursor pin), the five
`#compile_insertions … expecting n` counts (6 / 14 / 6 / 8 / 0), and every
ClickE2E literal (the full `uniCoverEdited` file and the 14 + 8 click-all
recompiles with `numMessages == 0`). The FACTS item about
`@[inherit_doc]`/doc-command goldens does not apply: no test here pins a
docstring warning. The post-audit pass added 13 `#assert_*` lines and
changed no existing expected output.

### Deviations

None. No assertion, `#guard`, `#guard_msgs`, test module or scenario was
deleted, loosened or skipped. There is no `sorry`, no `set_option` of any
scope, no `implemented_by`/`unsafe` change and no behaviour change. No file
was converted to `module`.

### Counts

These use the same method as the README census and the 4.34 section below,
on `git show qed64-pin-i:…` (before), on the tree the port left (after the
port) and on the final tree (after the post-audit fixes; re-counted with the
same greps):

| | before (v4.34.0) | after the port (v4.35.0) | after the post-audit fixes |
|---|---|---|---|
| `#guard` (all test files except `ClickE2E`) | 282 | 282 | 282 |
| `#guard_msgs` | 29 | 29 | 29 |
| `#assert_*` | 33 | 33 | 46 (`LinkTests` 21 → 34, `PropertyTests` 12) |
| `#compile_insertions` | 5 | 5 | 5 |
| **static subtotal** | **349** | **349** | **362** |
| `ClickE2E`: `#guard` lines | 12 | 12 | 12 |
| `ClickE2E`: executed `check` / `checkEqStr` calls | 98 | 98 (re-measured) | 98 (`ClickE2E.lean` untouched) |
| `ClickE2E`: `let some … \| throw` payload assertions | 4 | 4 | 4 |
| **Total** | **463** | **463** | **476** |
| (separately) `example` lines in `LinkTests.lean` | 11 | 11 | 11 |

The 98 was re-measured on 4.35.0. A copy of `ClickE2E.lean` in which
`check` and `checkEqStr` each print `E2E_MARK` first was run through
`lake env lean` (exit 0), and `grep -c E2E_MARK` gave 98.

### 4.35 gotchas

1. **Mathlib #40728 moved `⋖`/`⩿` decidability.** The `Bool`-only
   `Bool.instDecidableRelCovBy` / `Bool.instDecidableRelWCovBy`
   (`Order/Cover.lean:505,508` on v4.34.0) are gone without deprecation
   aliases, so code that names them breaks. The replacements are
   `Fintype.instDecidableRelCovByOfDecidableLT` (`[Fintype α] [LT α]
   [DecidableLT α]`) and `Fintype.instDecidableRelWCovByOfDecidableLE`
   (`[Fintype α] [Preorder α] [DecidableLE α]`), at
   `Data/Fintype/Defs.lean:261,265`. A type that has only `DecidableLE`
   (most hand-written demo orders) gets `⩿` from Mathlib but **not** `⋖`.
   A future link kind for `⩿` would need no local instance.
2. **The module-system warning comes from Lake, not from Lean**
   (`lake/Lake/Build/Module.lean:424`). It never reaches a `MessageLog`. So
   it cannot leak into `#guard_msgs`, and ClickE2E's in-process frontend
   (`Elab.IO.processCommands`) does not see it. `numMessages == 0` still
   holds for user files that `import HasseView` plus Mathlib modules. Here
   it shows up 10 times per build log: `Layout` 1, `Extract` 3, `Links` 2
   and `Demo` 4. The test modules import no Mathlib module directly, so they
   produce none. Per the house rule, nothing was converted to `module`.
3. **Core paths ClickE2E and the gate rely on are unchanged.** These files
   are byte-identical between the v4.34.0 and v4.35.0 toolchains:
   `Lean/Meta/Eval.lean` (`evalExpr`), `Lean/Elab/Import.lean`,
   `Lean/Parser/Module.lean`, `Lean/ImportingFlag.lean`,
   `Lean/Data/Lsp/Utf16.lean` and `Lean/Data/Position.lean`
   (`Lean.String.toFileMap` still delegates to `FileMap.ofString` and is not
   deprecated). The other diffs:
   - `Lean/Widget/UserWidget.lean`: `savePanelWidgetInfo` is unchanged. The
     "same hash(JS source code)" warning gained a space ("hash (JS"). The
     RPC helper now calls `Language.Lean.findInfoTreeAtPos`.
   - `Lean/Elab/Frontend.lean`: only `runFrontend` changed. It now folds
     `cmdState.codeQualityEntryTasks` into `Lean.Linter.codeQualityLogExt`,
     which is not on the `processCommands` path.
   - `Lean/Server/Utils.lean`: only an import changed (`InfoUtils` →
     `Elab.InfoTree.Util`). `replaceLspRange` is unchanged.
4. **ProofWidgets `106ff4fa` → `df72b022` has zero `.lean` changes.** Only
   `lean-toolchain` and CI moved (rc1 … v4.35.0 bumps). `MakeEditLink`,
   `OfRpcMethod`, `HtmlDisplay` and `Data/Html` are byte-identical.
5. **Mathlib line moves only.** `lt_iff_le_not_ge` is now at
   `Order/Defs/PartialOrder.lean:73`, not deprecated. The unsafe
   `Repr (Finset α)` is at `Data/Finset/Sort.lean:322`. `Nat.mem_divisors`
   stays at `NumberTheory/Divisors.lean:108`. `Fintype.subtype` /
   `Fintype.ofFinset` are still `@[instance_reducible]`
   (`Data/Fintype/Defs.lean:275,282`). `Mathlib.Order.Cover` no longer
   re-exports `Mathlib.Order.Antisymmetrization` (`ec6a61cec0d`, which
   demotes public imports); nothing here used it.
6. **FACTS items that did not bite here.** There is no enum
   `deriving Fintype` (so no `respectTransparency` override is needed), no
   `@[inherit_doc]` golden, and no import of the 87 modules dropped between
   QED64's 4.34 and 4.35 packs. That includes ClickE2E's user-file headers,
   which import only `HasseView`, `Mathlib.Data.Fintype.Powerset` and
   `Mathlib.Data.Finset.Sort`.

### Post-audit fixes (2026-10-25)

An adversarial audit of this port passed it, with three minor findings for
this package (a fourth, about the lock wrapper's stdin, concerns the harness,
not the package). Each finding and its fix:

1. **The instance-selection claim was unenforced.** The new `Links.lean`
   docstring said HasseView's `instDecidableRelCovByOfFintype` "is also the
   one instance search selects" (where Mathlib v4.35.0's
   `Fintype.instDecidableRelCovByOfDecidableLT` also applies). Only an
   out-of-tree `#synth` probe backed this: the audit's mutation M5
   (`instance (priority := low) …`, so that Mathlib's instance wins on
   `Fin`/`Bool`/`Finset`) survived `lake test`, ClickE2E included.
   **Fix:** a new section at the end of the static-examples part of
   `HasseViewTests/LinkTests.lean` with two test-local commands,
   `#assert_instance_head C => n` (instance search for class `C` must return
   a term with head constant `n`, looked up under the binders of an
   eta-expanded `DecidableRel` instance) and `#assert_no_instance C`, and 13
   assertions:
   - 7 pin HasseView's instance as the selected one: `DecidableRel (· ⋖ ·)`
     on `Fin 5`, `Bool`, `Finset (Fin 3)`, `Bool × Bool` and `Bowtie`, and
     the per-pair `Decidable ((1 : Fin 5) ⋖ 2)` and
     `Decidable ((1 : Bowtie) ⋖ 3)` that the inserted `by decide` actually
     synthesizes;
   - 2 pin why the instance is still needed: no `DecidableLT Bowtie` and no
     `DecidableLT (Bool × Bool)`;
   - 4 run with the package instance erased for one command each
     (`attribute [-instance] HasseView.instDecidableRelCovByOfFintype in`):
     Mathlib's instance is then selected for `Fin 5` and `Finset (Fin 3)`,
     and `Decidable ((1 : Bowtie) ⋖ 3)` and
     `Decidable ((false, false) ⋖ (false, true))` on `Bool × Bool` have no
     instance at all.
   M5 was re-run on the final tree and is now killed (see the transcript
   below).
   **Library docstring edit (comment-only).** This is the pass's only change
   to a library file. In the `Links.lean` module docstring, section "The `⋖`
   decidability instance", lines 49-52 now read "declared after Mathlib's
   instance (same default priority), it is also the one instance search
   selects there.  Both facts are pinned in `HasseViewTests/LinkTests.lean`
   (`#assert_instance_head`, `#assert_no_instance`)." The port round's text
   had neither the parenthetical, which says why declaration order decides
   the search, nor the second sentence. No code line changed, and every
   other `HasseView/*.lean` file is byte-identical to the port round.
2. **README "Known warts" bullet was stale.** It said the inserted
   `by decide` needs `HasseView` imported for
   `instDecidableRelCovByOfFintype`; at 4.35 that holds only for types
   without `DecidableLT`. **Fix:** reworded to say so, naming the types
   checked on each side (`Bowtie`, `Bool × Bool` need it; `Fin 5`, `Bool`,
   `Finset (Fin 3)` would also close through Mathlib's instance). The
   cover-link bullet now also says which instance is selected, and the
   README counts went from 463 to 476 (static 349 → 362).
3. **Wording nit: "all five demo types".** The probe paragraph listed
   `Fin 5`, `Bool`, `Bool × Bool`, `Finset (Fin 3)` and `Bowtie` as "all
   five demo types", but `Bool` appears only in `CommandTests`, and the
   fifth `Demo.lean` type is `Div12`, which has no `Preorder` and so no `⋖`
   instance. **Fix:** now "the four linkable `Demo.lean` types … and
   `Bool`", and "two of the four linkable demo types" further down.

The H1 title already covered both ports (v4.32.2 → v4.34.0 → v4.35.0).
No library behaviour changed: the only library edit is the comment-only
`Links.lean` docstring change described under finding 1. No existing
assertion was touched; the census above was re-counted mechanically.

**Re-audit (2026-10-26).** A second adversarial audit passed this package.
All five of its mutations were caught: H1 is M5 again; H2 turns the
instance into a `def`; H3 adds `[DecidableLT V]` to it; H4 makes it
`scoped`; H5 adds a `DecidableLT Bowtie` instance. It reported one minor
finding: the pass had been summarised as tests-only, but `Links.lean` is
not byte-identical to the port round. A `diff` of the port-round copy
(`shasum` `82142c94…`) against the final file (`e536b194…`) shows only the
docstring lines 49-52 quoted in finding 1. **Fix:** finding 1 and the
summary at the top of this section now record that edit explicitly.
Nothing else changed; `lake test` was re-run (see the transcript below).

### Verification transcript

Every command ran through
`BROWSER_LOCK_DIR=$HOME/.cache/lean-widgets-build-lock MIN_FREE_GB=10
LOCK_WAIT_S=43200 COOLDOWN_WAIT_S=7200 bash
".../widgets-v4.34/qed64-showcase/scripts/with-browser-lock.sh"
port435-hasse-view-<purpose> bash -c 'cd ".../packages/hasse-view" && …'`:

```
# port435-hasse-view-build: lake build (before the docstring edits)
Build completed successfully (967 jobs).
browser-lock: command exited rc=0
# port435-hasse-view-test: lake test (before the docstring edits)
✔ [976/977] Built HasseViewTests.ClickE2E (6.9s)
✔ [977/977] Built HasseViewTests (968ms)
browser-lock: command exited rc=0
# port435-hasse-view-probe: lake env lean <probe files>   (see the instance section)
# port435-hasse-view-e2ecount: lake env lean <instrumented ClickE2E copy>  → 98 × E2E_MARK, rc=0
# FINAL — port435-hasse-view-cleanbuild: rm -rf .lake/build && lake build
✔ [966/967] Built HasseView (896ms)
Build completed successfully (967 jobs).
browser-lock: command exited rc=0
# FINAL — port435-hasse-view-test: lake test
✔ [976/977] Built HasseViewTests.ClickE2E (6.6s)
✔ [977/977] Built HasseViewTests (914ms)
browser-lock: command exited rc=0
```

Final logs: 10 `warning:` lines each, all of the module-system kind; 0
`error` lines; 0 `Built Mathlib` jobs.

Post-audit runs (2026-10-25), each under the same lock prefix with
`MIN_FREE_GB=20` and stdin from `/dev/null`:

```
# port435-fix-hasse-view-buildtest: lake build; lake test (new LinkTests pins)
⚠ [962/967] Built HasseView.Links (4.1s)          (⚠ = module-system warnings only)
Build completed successfully (967 jobs).
### lake build rc=0
✔ [974/977] Built HasseViewTests.LinkTests (2.0s)
✔ [976/977] Built HasseViewTests.ClickE2E (6.9s)
✔ [977/977] Built HasseViewTests (859ms)
### lake test rc=0
# port435-fix-hasse-view-mutM5-final: M5 re-run, then restore and rebuild
65:instance (priority := low) instDecidableRelCovByOfFintype {V : Type*}
### M5: lake build HasseViewTests.LinkTests (expect FAIL)
error: HasseViewTests/LinkTests.lean:142:0: expected instance search for DecidableRel fun x1 x2 =>
  x1 ⋖
    x2 to select HasseView.instDecidableRelCovByOfFintype, got fun a b => Fintype.instDecidableRelCovByOfDecidableLT a b
error: HasseViewTests/LinkTests.lean:144:0: … (Bool, same message)
error: HasseViewTests/LinkTests.lean:146:0: … (Finset (Fin 3), same message)
error: HasseViewTests/LinkTests.lean:152:0: expected instance search for Decidable
  (1 ⋖ 2) to select HasseView.instDecidableRelCovByOfFintype, got Fintype.instDecidableRelCovByOfDecidableLT 1 2
error: build failed
### M5 rc=1
### restored byte-identical            (cmp against the saved copy)
Build completed successfully (967 jobs).
### lake build rc=0
✔ [976/977] Built HasseViewTests.LinkTests (1.7s)
### lake test rc=0
# FINAL — port435-fix-hasse-view-cleanfinal: rm -rf .lake/build/{lib/lean,ir}/HasseView* (own modules only), lake build, lake test
✔ [966/967] Built HasseView (759ms)
Build completed successfully (967 jobs).
### lake build rc=0
✔ [974/977] Built HasseViewTests.LinkTests (3.0s)
✔ [975/977] Built HasseViewTests.PropertyTests (3.2s)
✔ [976/977] Built HasseViewTests.ClickE2E (6.6s)
✔ [977/977] Built HasseViewTests (777ms)
### lake test rc=0
browser-lock: command exited rc=0
```

As M5 predicts, the `Bool × Bool` and `Bowtie` pins still pass under it:
HasseView's instance is the only one that applies to them. Final clean logs:
9 `HasseView*` library modules and 11 test modules (ClickE2E included) were
rebuilt; 10 `warning:` lines in each log, all of the module-system kind; 0
`error` lines; 0 `Built Mathlib` jobs.

Re-audit follow-up runs (2026-10-26). The only change was to this file, under
the same lock prefix with `MIN_FREE_GB=20` and stdin from `/dev/null`:

```
# fix2-hasse-view-test: lake test   (all 977 jobs up to date: replayed, nothing rebuilt)
### lake test rc=0
# fix2-hasse-view-cleantest: rm -rf .lake/build/{lib/lean,ir}/HasseView* (own modules only), lake build, lake test
✔ [966/967] Built HasseView (733ms)
Build completed successfully (967 jobs).
### lake build rc=0
✔ [974/977] Built HasseViewTests.LinkTests (2.0s)
✔ [975/977] Built HasseViewTests.PropertyTests (3.2s)
✔ [976/977] Built HasseViewTests.ClickE2E (5.8s)
✔ [977/977] Built HasseViewTests (755ms)
### lake test rc=0
browser-lock: command exited rc=0
```

The clean run rebuilt 9 `HasseView*` library modules and 11 test modules,
so every compile-time assertion ran again. Each log has 10 `warning:` lines,
all of the module-system kind, plus 0 `error` lines and 0 `Built Mathlib`
jobs. The static census, re-counted with the greps above, is unchanged
(282 / 29 / 46 / 5). `ClickE2E.lean` is untouched: its 12 `#guard` lines
were re-counted, and its 98 + 4 are as measured above. The total stays 476.

## Lean 4.32.2 → 4.34.0 (2026-09-30)

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
