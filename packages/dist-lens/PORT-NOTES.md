# PORT-NOTES — `dist-lens`: Lean / Mathlib v4.32.2 → v4.34.0 → v4.35.0

## Lean 4.34.0 → 4.35.0 (2026-10-25)

Status: `lake build` and `lake test` both exit 0 on `leanprover/lean4:v4.35.0` /
Mathlib `v4.35.0`, from a clean rebuild of this package's own outputs (the port's
transcript below, and the final tree's, after the second round of post-audit fixes, at
the end of this section).  One Mathlib API removal forced a source change: the
uniform `PMF` constructors (below).  Every assertion of the `v4.34.0` tree is
kept; the port added 6 (357 → 363), the post-audit fixes 33 more (363 → 396) and the
second fix round 5 more (396 → 401).  The audit's findings and their fixes are in
"Post-audit fixes"; the re-audit's findings, their fixes and the final tree's
transcript are in "Post-audit fixes, round 2", both at the end of this section.

### Pins (from the harness)

Set by the harness, not edited by the port: `lean-toolchain`
`leanprover/lean4:v4.34.0` → `leanprover/lean4:v4.35.0`; `lakefile.toml`
`mathlib` `rev = "v4.34.0"` → `rev = "v4.35.0"`; `lake-manifest.json` from the
harness's single `lake update` (every rev = Mathlib `v4.35.0`'s own pins):
Mathlib `56a00585`, ProofWidgets `106ff4fa` → `df72b022`, Batteries
`66e46918`, Aesop `4a174c49`, Qq `dce0ad79`, plausible `dfa4f381`,
importGraph `a41f0e9a`, LeanSearchClient `d6b4c7be`, Cli `c24fe607` (inputRev
`v4.35.0`).  `lake exe cache get`: 9030 cached files, nothing to download.
dist-lens does not require ProofWidgets directly.

### What broke, and why

The harness's first build (`dist-lens.build0.log`) stopped at
`DistLens/Extract.lean:225:29` and `:378:27`: ``Unknown constant
`PMF.uniformOfFinset` ``.  Cause: Mathlib #42909 (`be31cde2c2c`, 2026-10-05,
"change uniformOfFinset and ofMultiset from PMF to Measure", part of #42821
which deprecates `PMF`) rewrote `Mathlib/Probability/Distributions/Uniform.lean`:

* `PMF.uniformOfFinset (s) (hs : s.Nonempty) : PMF α` is **gone** (no alias);
  its replacement `MeasureTheory.Measure.uniformOfFinset (s : Finset α) :
  Measure α` is a *measure*.
* `PMF.uniformOfFintype` still exists, but only as
  `@[deprecated (since := "2026-10-04")] alias _root_.PMF.uniformOfFintype :=
  uniformOfFinset` — an alias **of the Measure-valued definition**, with no
  `+typeChanged` marker.  So the name still compiles inside ``` ``PMF.uniformOfFintype ```
  (`Extract.lean:225` and `:363` raised no error), but `e.isAppOfArity
  ``PMF.uniformOfFintype 3` can never match a PMF term again, and every user
  spelling `PMF.uniformOfFintype (Fin 6)` is now an elaboration error
  (`Application type mismatch: … Fin 6 has type Type but is expected to have
  type Finset ?m.1`, plus the deprecation warning) — verified with a scratch
  probe at v4.35.0.
* `PMF.uniformOfFintype_apply` is an alias of
  `Measure.uniformOfFinset_apply_singleton`; `PMF.uniformOfFinset_apply` is
  gone (the new alias is the root-level `uniformOfFinset_apply`).  `pmf_num`
  names both inside a syntax quotation, so `Verify.lean` *compiled*, but every
  `pmf_num` call would have failed at run time (unknown/wrong simp lemma →
  the `simp` step fails → `ennreal_num: cannot close …`).

The rest of the `PMF` API DistLens uses is unchanged at `v4.35.0` (checked by
`git diff 5ed29652 56a00585` over `Mathlib/Probability/ProbabilityMassFunction/`):
`pure`/`bind`/`map`/`ofFinset`/`ofFintype` and their `_apply` lemmas are
untouched (proof-term refactors only); `bernoulli`/`binomial` and their
`_apply` lemmas are still present, deprecated since 2026-04-07, now with
`+typeChanged` in the attribute (the tests and demo disable the linter, and
`pmf_num` sets it false internally, so no pinned message sees the new
wording).  `Mathlib.Probability.Distributions.Uniform` is imported by no other
Mathlib module.

### Changes

| File | What | Why |
|---|---|---|
| `DistLens/Uniform.lean` (new, 58 lines) | `DistLens.uniformOfFinset (s) (hs : s.Nonempty) : PMF α`, `DistLens.uniformOfFintype (α) [Fintype α] [Nonempty α] : PMF α`, and their `@[simp]` lemmas `uniformOfFinset_apply` (`rfl`, classical `if`) and `uniformOfFintype_apply` — Mathlib `v4.34.0`'s definitions, bodies, argument order, attributes and proofs verbatim (only the section `variable`s are written as binders, and the defs say `noncomputable` because Mathlib's file is a `noncomputable section`), on top of the unchanged `PMF.ofFinset`.  The support/`toOuterMeasure`/`toMeasure` lemmas DistLens never used are not carried over. | The constructors DistLens draws, verifies and suggests no longer exist as `PMF`s (see Deviations for the alternatives rejected). |
| `DistLens/Extract.lean` | `import Mathlib.Probability.Distributions.Uniform` → `import DistLens.Uniform`; `whitelistHeads` and the two `isAppOfArity` matches name ``` ``DistLens.uniformOfFintype ``` / ``` ``DistLens.uniformOfFinset ``` (same arities 3/3); the `unsupportedHead` refusal lists `DistLens.uniformOfFintype, DistLens.uniformOfFinset` instead of the `PMF.` names; one module-doc sentence | the build error, and the silent never-matching `PMF.uniformOfFintype` head |
| `DistLens/Verify.lean` | same import swap; in `pmf_num`'s simp set `PMF.uniformOfFintype_apply, PMF.uniformOfFinset_apply` → `DistLens.uniformOfFintype_apply, DistLens.uniformOfFinset_apply` (the other 12 lemmas, their order, the scoped options and the elaborator design untouched); module doc names the new home | the run-time breakage above |
| `DistLens.lean` | `import DistLens.Uniform` | the root lists every library module |
| `DistLensTests/ClickE2E.lean` | the user-file fixtures uFile1/2/5/6/7 spell `DistLens.uniformOfFintype` where they spelled `PMF.uniformOfFintype` (sources, and the pinned edited files / suggestion strings / would-be example derived from them); the three insert-range pins on the edited command lines move by the +5 UTF-16 units of the longer name (see the golden table) | the `v4.34.0` spelling no longer elaborates; the checks are the same checks on the new spelling |
| `DistLensTests/SuggestTests.lean` | the `srcTxt` argument `"(PMF.uniformOfFintype Ordering)"` → `"(DistLens.uniformOfFintype Ordering)"` in the opaque-carrier `#guard` (expected value `#[]` unchanged) | keeps it in sync with ClickE2E uFile7; a pure string input |
| `DistLensTests/ExtractTests.lean` | the refusal-message pin (golden table) | the message names the new constructors |
| `DistLensTests/MathlibUniformTests.lean` (new) + `DistLensTests.lean` (one import) | 3 `#guard_msgs` + 3 compiled `example`s with `Mathlib.Probability.Distributions.Uniform` imported and `open PMF DistLens` | new coverage for the new hazard (gotcha 2): what QED64's `import Mathlib` users hit |
| `README.md` | usage block opens `DistLens`; whitelist section explains the DistLens-owned uniform constructors; simp-set list, opaque-carrier limitation and deprecation bullet updated; Architecture row for `Uniform.lean`; "Versions" now `v4.35.0` / Mathlib `v4.35.0` (`56a00585`) / ProofWidgets `df72b022`; "Tests" census 345 → 363 (the old figure predated `StackGuardTests`) | documentation of the port |
| `PORT-NOTES.md` | this section | required deliverable |

Untouched: `Model.lean`, `Render.lean`, `Widget.lean`, `Demo.lean` (inside
`namespace DistLens.Demo` the bare `uniformOfFintype`/`uniformOfFinset`
resolve to `DistLens.*` through the namespace chain, before open
declarations), and every other test file — `VerifyTests`/`ExtractTests`/
`SuggestTests` keep their bare `uniformOfFintype …` spellings under `open PMF
DistLens`, which now resolve uniquely to DistLens's (DistLens no longer imports
Mathlib's `Uniform` module, so `PMF.uniformOfFintype` is not even in their
environment).  This table and paragraph describe the port itself; the post-audit
fixes below changed `Uniform.lean` (license header), `Extract.lean` and `Widget.lean`
(the Measure hint), `MathlibUniformTests.lean` (rewritten), and added
`UniformTests.lean` and `NOTICE`; round 2 changed `Extract.lean` (the `#chain` hint),
`MathlibUniformTests.lean` and `ExtractTests.lean` (new pins), `Uniform.lean` (header),
`LICENSE` and `NOTICE`, and added `LICENSE-APACHE-2.0`.

### Golden / expected-output changes

| File | Old → new | Why it is legitimate |
|---|---|---|
| `DistLensTests/ExtractTests.lean` (the `PMF.normalize` refusal, `error:` docstring) | `… DistLens matches PMF.pure, PMF.bind, PMF.map, PMF.uniformOfFintype, PMF.uniformOfFinset, PMF.bernoulli, …` → `… PMF.map, DistLens.uniformOfFintype, DistLens.uniformOfFinset, PMF.bernoulli, …` | The message enumerates the constructor whitelist; at `v4.35.0` the old two names are not `PMF` constructors (one is gone, one is a Measure alias), so the old text would be false.  Same check (a non-whitelisted head is refused, naming `@Subtype.mk`, with the full list); every other byte identical. |
| `DistLensTests/ClickE2E.lean` uFile2 | `check "uFile2: insertRange is ⟨2,36⟩" (… at' 2 36)` → `"⟨2,41⟩" (… at' 2 41)`; suggestions `(PMF.uniformOfFintype (Fin 3)) {k} = 1/3` → `(DistLens.uniformOfFintype (Fin 3)) {k} = 1/3` | Derived from the input change: 41 = UTF-16 length of `#dist (DistLens.uniformOfFintype (Fin 3))` (36 for the old line); the suggestion text is the user's own term text, so it carries the new spelling.  Same end-of-command and single-paren checks. |
| `DistLensTests/ClickE2E.lean` uFile5 | `(props.insertRange == at' 2 36)` → `at' 2 41`; pinned edited lines `#dist (PMF.uniformOfFintype (Fin 2))` / `example : (PMF.uniformOfFintype (Fin 2)) 0 = 1/2 := by pmf_num -- tail comment 🎲` → the `DistLens.` spellings | same derivation (the trailing-comment wart is pinned exactly as before) |
| `DistLensTests/ClickE2E.lean` uFile7 | `check "uFile7: insertRange is ⟨2,37⟩" (… at' 2 37)` → `"⟨2,42⟩" (… at' 2 42)`; would-be example `(PMF.uniformOfFintype Ordering) Ordering.lt = 1/3` → `(DistLens.uniformOfFintype Ordering) …` | same derivation; the reason pin (`ennreal_num: cannot close this ℝ≥0∞ goal`) is unchanged and still holds |
| `DistLensTests/ClickE2E.lean` uFile1, uFile6 | pinned edited files: the def line `… := PMF.uniformOfFintype (Fin 4)` / `(Fin 6)` → `… := DistLens.uniformOfFintype …` | the edited file is the input file plus the inserted line; insert ranges (⟨5,11⟩, ⟨4,9⟩) and suggestions unchanged |

No other expected output changed: all 36 `ExtractTests` pins but that one
(including `#dist_film … die` still printing `` `uniformOfFintype (Fin 6)` ``),
the four `VerifyTests` negatives (`⊢ False`, `⊢ 2 / 3 = 2⁻¹`, `⊢ 6⁻¹ + 6⁻¹ = 1`,
the `twoDice` sum), `SuggestTests`' `#unfold_names` pins, the six
`StackGuardTests` pins, and every other ClickE2E check.  The QED64-relayed
4.35 message changes (`@[inherit_doc]`, `deriving Fintype`) do not occur in
this package.

### Deviations

1. **A compat re-implementation instead of the moved Mathlib API** (rule 4
   prefers adapting).  The replacement `MeasureTheory.Measure.uniformOfFinset`
   is a `Measure`, not a `PMF`: it cannot be the source of `PMF.bind`/`PMF.map`,
   cannot be `#dist`ed, and `pmf_num`'s goals are `PMF` applications.
   Rejected: (a) whitelisting the measure — incompatible with every
   `bind`/`map`/demo/test; (b) a bridge `(Measure.uniformOfFinset s).toPMF` —
   needs `[MeasurableSpace α] [MeasurableSingletonClass α] [Countable α]` and an
   `IsProbabilityMeasure` instance Mathlib does not provide, changes the goal
   shapes, the recipe and the failure messages, and would refuse the opaque
   carriers (`Ordering`) DistLens displays; (c) re-declaring the old names in
   namespace `PMF` — `PMF.uniformOfFintype` is taken by Mathlib's alias, and a
   package should not squat Mathlib's namespace; (d) dropping uniform support —
   removes the flagship demo (`die`, `twoDice`, `dieParity`) and dozens of
   tests.  The shim is Mathlib `v4.34.0`'s code verbatim (two `def`s, two
   lemmas), so values, `simp` normal forms and every pinned output are those
   of the `v4.34.0` port.
2. **User-facing spelling.**  `PMF.uniformOfFintype (Fin n)` →
   `DistLens.uniformOfFintype (Fin n)` (or the bare name with `open DistLens`).
   Test *inputs* that spelled the Mathlib name changed accordingly (ClickE2E,
   one `SuggestTests` string); no assertion was removed or loosened.
3. **Dropped `import Mathlib.Probability.Distributions.Uniform`** from
   `Extract.lean`/`Verify.lean`.  At `v4.35.0` that module holds only
   Measure-valued API DistLens does not use, plus the alias that collides with
   DistLens's constructor name; it imports nothing beyond
   `ProbabilityMassFunction.Constructions` (already imported).  With it gone,
   `import DistLens` alone has no ambiguity (and the package tests, the
   `showcase/probes/dist-lens.lean` probe and ClickE2E's user files resolve the
   bare/`DistLens.` names uniquely); `import Mathlib` users get the ambiguity,
   which `MathlibUniformTests` pins as working.
4. **Coverage added**: the new `MathlibUniformTests` module (+3 `#guard_msgs`,
   +3 `example`s).  No `sorry`, no new `set_option` (the `v4.34.0` port's scoped
   `respectTransparency.types` option in `pmf_num` is kept — still needed, see
   gotcha 5), no module converted to `module`.

### Counts

Same method as the 4.34 section (anchored `grep` over `DistLensTests/` and
`DistLensTests.lean`; ClickE2E calls exclude the four `def check*` lines);
"before" is `git show qed64-pin-i:packages/dist-lens/…` (the `v4.34.0` tree,
which already contained `StackGuardTests`).

| Category | Before (qed64-pin-i, v4.34.0) | After the port (v4.35.0) | After the post-audit fixes | After round 2 |
|---|---|---|---|---|
| `#guard_msgs` blocks (36 Extract, 6 StackGuard, 4 Verify, 4 Suggest; port: + 3 MathlibUniform; fixes: MathlibUniform 3 → 18, + 2 Uniform; round 2: Extract 36 → 38, MathlibUniform 18 → 21) | 50 | 53 | 70 | 75 |
| `#guard` (46 Model, 43 Render, 24 Contract, 23 ChainMath, 21 ClickE2E, 20 Suggest, 18 Text, 9 Invariant, 1 driver root) | 205 | 205 | 205 | 205 |
| compiled `example`s (38 Verify, 6 StackGuard, 5 Suggest, 1 ClickE2E; port: + 3 MathlibUniform; fixes: MathlibUniform 3 → 7, + 12 Uniform) | 50 | 53 | 69 | 69 |
| ClickE2E runtime assertions (`check` 23, `checkClean` 15, `checkEq` 8, `checkFails` 6) | 52 | 52 | 52 | 52 |
| **Test-driver total (`lake test`)** | **357** | **363** | **396** | **401** |
| `DistLens/Demo.lean`: compiled `example`s / live panel commands (`lake build`) | 17 / 12 | 17 / 12 | 17 / 12 | 17 / 12 |

(The 4.34 section's 345 was counted before `StackGuardTests` landed on
2026-10-12, which added 6 `#guard_msgs` + 6 `example`s: 357 at qed64-pin-i.)

### 4.35 gotchas

1. **Mathlib v4.35.0 made the uniform `PMF`s Measure-valued** (#42909) and is
   deprecating `PMF` as a whole (#42821).  `PMF.uniformOfFinset` and
   `PMF.ofMultiset` are gone; **`PMF.uniformOfFintype` is a deprecated alias of
   a definition with a different type**, without `+typeChanged`.  Name
   literals (``` ``PMF.uniformOfFintype ```) still compile, so a whitelist/
   `isAppOfArity` matcher silently stops matching (here every uniform die would
   have become "not a supported PMF constructor"); grep for *every* use of a
   changed name, not just the build errors.  The same holds for lemma names
   inside syntax quotations (`pmf_num`'s simp set): they resolve at run time,
   so the library builds and only the tests catch it.  Next ports should expect
   `pure`/`bind`/`map`/`ofFintype`/`bernoulli`/`binomial` to follow.
2. **Bare-name collision with Mathlib's alias.**  With `import Mathlib` (or the
   `Uniform` module) and `open PMF DistLens`, `uniformOfFintype` is ambiguous
   between `PMF.uniformOfFintype` (the Measure alias) and
   `DistLens.uniformOfFintype`.  Lean elaborates both and keeps the one that
   succeeds (DistLens's; the failed alternative's deprecation warning is
   discarded), so it works warning-free — but the pretty-printer then prints
   the head qualified, `DistLens.uniformOfFintype (Fin 6)`, because the short
   name no longer resolves uniquely (pinned in `MathlibUniformTests`).  With
   only `open PMF` (no `open DistLens`) the bare name means Mathlib's alias and
   fails.  QED64's `qed64-showcase/lean/examples/dist-lens.lean` is exactly
   that case (`import Mathlib`, `open PMF`, `namespace Showcase.DistLens`,
   `uniformOfFintype (Fin 6)`).  It needs its **top-level** line `open PMF`
   changed to `open PMF DistLens` (or the qualified name): an `open DistLens`
   written *inside* `namespace Showcase.DistLens` resolves `DistLens` to the
   enclosing `Showcase.DistLens` and does not open `_root_.DistLens` (see the
   post-audit fixes: `MathlibUniformTests` §4 pins both the trap and the fix).
   Outside this package, not edited here.
3. **Namespace shadowing helps inside `DistLens.*`.**  In `namespace
   DistLens.Demo`, name resolution finds `DistLens.uniformOfFintype` through the
   enclosing namespaces before it looks at `open` declarations, so the demo
   needed no change; `namespace Showcase.DistLens` does *not* have `DistLens` as
   an enclosing namespace.
4. **ClickE2E insert ranges are column-exact**: renaming a constructor in a
   fixture's command line moves every pinned `insertRange` on that line by the
   UTF-16 length difference (+5 here).
5. **`backward.isDefEq.respectTransparency.types`** is still registered with
   `defValue := true` at v4.35.0 (`Lean/Meta/ExprDefEq.lean:57`), and `pmf_num`'s
   scoped `false` is still needed for `uniformOfFinset` with the `⟨1, by simp⟩`
   spelling: a scratch probe at v4.35.0 (`lake env lean`, not committed) running the
   recipe's `simp [DistLens.uniformOfFinset_apply]` on
   `(uniformOfFinset ({1, 2, 3} : Finset ℕ) ⟨1, by simp⟩) 2 = 3⁻¹` fails with
   "`simp` made no progress … The target expression is not type-correct under the
   `implicit` transparency level … has type `∃ x, x ∈ {1, 2, 3}` but is expected to
   have type `{1, 2, 3}.Nonempty`" at the default, and succeeds under
   `set_option backward.isDefEq.respectTransparency.types false in` (no error).
   The horizon in the 4.34 section's gotcha 8 still applies.
6. **Module-system warning**: `DistLens/Uniform.lean` and
   `DistLensTests/MathlibUniformTests.lean` (like every other file importing
   Mathlib) print the new "imports … designed for use with the module system;
   consider adding `module`" build warning.  Expected and left alone; it is a
   header warning, outside any `#guard_msgs` and outside ClickE2E's in-process
   compiles (their `clean` checks stay green).  The post-audit `UniformTests` imports
   only `DistLens.*` modules and prints none.
7. **Memory**: `/usr/bin/time -l lake test` on the evidence run: 130.5 s wall,
   "maximum resident set size" 18.9 GB (18914672640 bytes) — the in-process ClickE2E compile
   (123 s), in line with the ~20 GB of the 4.34 port.  Run `lake test` alone (the
   build lock serialises it), and with enough free memory: the audit's first clean
   `lake test`, admitted by the lock at `MIN_FREE_GB=10`, was SIGKILLed in ClickE2E
   (exit 137).  The peak varies from run to run between about 15 and 22 GB: 18.9 GB
   (the port), 19.07 GB (the audit's rerun), 15.1 GB (the post-audit final run),
   21.7 GB (21672067072 bytes, the re-audit's clean run, admitted at `MIN_FREE_GB=20`
   with 22.7 GiB reclaimable) and 19.2 GB (19245252608 bytes, round 2's final run,
   admitted at 20 with 20.6 GiB reclaimable).  So `MIN_FREE_GB=20`, the shared build
   rules' figure for a ClickE2E compile, is the floor, not a margin: the three runs
   admitted at 20 so far all passed, but the peak can exceed 20 GB.  Use more when the machine has it, and run nothing else memory-heavy
   alongside.  (Round 2 tried `MIN_FREE_GB=24` first; the lock found only 21.6–23.0 GiB
   reclaimable, so that run was stopped while it waited and was re-run at 20.)
   On 2026-10-27 the user lowered the shared floor to `MIN_FREE_GB=16`: this 36 GB host
   rarely has 20 GiB reclaimable, and runs at 20 were waiting hours in the lock's cooldown.
   That accepts the risk above (a peak of up to 22 GB from 16 GiB reclaimable): a run
   SIGKILLed in ClickE2E (exit 137) is rerun once.

### Verification transcript (2026-10-25, the port)

Run on 2026-10-25 from the package root, every lake invocation through the
shared build lock, as one locked job (background):

```
BROWSER_LOCK_DIR=$HOME/.cache/lean-widgets-build-lock MIN_FREE_GB=10 LOCK_WAIT_S=43200 \
  COOLDOWN_WAIT_S=7200 bash ".../widgets-v4.34/qed64-showcase/scripts/with-browser-lock.sh" \
  port435-dist-lens-evidence bash -c 'cd ".../widgets-v4.34/packages/dist-lens" &&
    rm -rf .lake/build/lib/lean/DistLens* .lake/build/ir/DistLens* &&
    lake build ...; /usr/bin/time -l lake test ...; lake env lean <scratch>/RespectProbe.lean'
```

The `rm` deletes only this package's own outputs, so every `DistLens.*` and
`DistLensTests.*` module was recompiled (Mathlib oleans from the cache).  No
`.lean` source changed after this run started (mtimes checked; only `README.md`
and this file were edited afterwards).

```
$ lake build
⚠ [3128/3136] Built DistLens.Model (1.2s)
⚠ [3129/3136] Built DistLens.Uniform (1.6s)
✔ [3130/3136] Built DistLens.Render (992ms)
⚠ [3131/3136] Built DistLens.Verify (2.0s)
⚠ [3132/3136] Built DistLens.Extract (2.5s)
✔ [3133/3136] Built DistLens.Widget (2.1s)
✔ [3134/3136] Built DistLens.Demo (4.0s)
✔ [3135/3136] Built DistLens (2.5s)
Build completed successfully (3136 jobs).
exit 0   # the ⚠ are exactly 11 "imports … designed for use with the module
         # system; consider adding `module`" warnings (Model 2, Uniform 1,
         # Verify 5, Extract 3); no other warning or error line

$ lake test
✔ [3137/3150] Built DistLensTests.Helpers (2.7s)
✔ [3138/3150] Built DistLensTests.StackGuardTests (2.7s)
⚠ [3139/3150] Built DistLensTests.MathlibUniformTests (2.7s)
✔ [3140/3150] Built DistLensTests.InvariantTests (5.4s)
✔ [3141/3150] Built DistLensTests.ChainMathTests (5.5s)
✔ [3142/3150] Built DistLensTests.TextTests (5.4s)
✔ [3143/3150] Built DistLensTests.RenderTests (5.5s)
✔ [3144/3150] Built DistLensTests.ContractTests (5.5s)
✔ [3145/3150] Built DistLensTests.ModelTests (5.6s)
✔ [3146/3150] Built DistLensTests.ExtractTests (5.6s)
✔ [3147/3150] Built DistLensTests.SuggestTests (6.3s)
✔ [3148/3150] Built DistLensTests.VerifyTests (8.4s)
✔ [3149/3150] Built DistLensTests.ClickE2E (123s)
✔ [3150/3150] Built DistLensTests (2.8s)
exit 0   # the same 11 module-system warnings replayed for DistLens.*, plus 1 for
         # MathlibUniformTests (its `Mathlib.Probability.Distributions.Uniform`
         # import); no other warning or error line
```

Before this run, the iterations were: `lake build` alone (green, plus the
alias probe of gotcha 2) and the twelve non-ClickE2E test modules alone (green); no
red build of the edited tree occurred.  After it, one more scratch probe (`lake env
lean`, through the lock) confirmed the README's opaque-carrier claim at v4.35.0:
`example : (DistLens.uniformOfFintype Ordering) Ordering.lt = 1/3 := by pmf_num`
fails with `ennreal_num: cannot close this ℝ≥0∞ goal` / `⊢ ↑(Fintype.card Ordering) = 3`,
as before.

### Post-audit fixes (2026-10-25)

An adversarial audit of the port (verdict *fail*: one major and six minor
findings; two of its seven mutations, M5 and M7, survived) was followed by these
fixes, on the same uncommitted tree.  The rules were the port's: package files only,
no assertion removed or loosened, every lake run through the build lock.

| # | Finding (severity) | Fix | Files |
|---|---|---|---|
| F1 | **major**: `DistLens/Uniform.lean` copies Mathlib `v4.34.0` code (two `def`s, two lemmas, with proofs) without its Apache-2.0 copyright notice or authors, while the package `LICENSE` says "Copyright 2026 Fawad Haider" | New header comment in `Uniform.lean` (above the imports).  It names the source: Mathlib, `Mathlib/Probability/Distributions/Uniform.lean` at tag `v4.34.0` = commit `5ed2965256430c3649e86755f9576b54eca72435`.  It keeps the original three header lines verbatim (`Copyright (c) 2024 Josha Dekker. All rights reserved.` / `Released under Apache 2.0 license …` / `Authors: Josha Dekker, Devon Tuma, Kexing Ying`) and states that the adaptation is under the same Apache License 2.0.  It lists every modification, as §4(b) requires: namespace `PMF` → `DistLens`, `noncomputable` written out, section `variable`s as binders, reduced `open`s, the dropped declarations (named one by one), imports, and docstrings.  (Round 2, G3: the first version's list missed `uniformPDF`, `uniformPDF_eq_pdf` and `uniformPDF_ite` and summarised the `IsUniform` lemmas; it now names all 35 dropped declarations.)  New `NOTICE` file: package copyright, plus the Mathlib-derived file with its source, commit, copyright and authors.  New README "License" section saying the same.  `LICENSE` itself is unchanged (same license, so nothing to reconcile); round 2 (G4) added the license's full text as `LICENSE-APACHE-2.0`, for §4(a). | `DistLens/Uniform.lean`, `NOTICE` (new), `README.md` |
| F2 | minor: M5 (drop `DistLens.uniformOfFinset_apply` from `pmf_num`'s simp set) and M7 (drop `@[simp]` from `DistLens.uniformOfFintype_apply`) survived, so the shim's own contract was unpinned | New module `DistLensTests/UniformTests.lean` (2 `#guard_msgs` + 12 `example`s), imported by the driver.  It uses both lemma statements and the `uniformOfFintype` definition by name, as terms.  Plain `simp` with no arguments closes goals on both constructors (needs both `@[simp]` attributes; the `Finset` goals use `Finset.insert_nonempty`, whose stated type is `Finset.Nonempty`).  Two negative controls (`attribute [-simp] … in`) pin that the same `simp` then fails with `` `simp` made no progress ``, so the positives really do depend on the attributes.  Three `pmf_num` examples run under `attribute [-simp] …`, so they need `pmf_num`'s *explicit* entries.  The mutation re-run below shows M5, M7 and their two siblings are now caught. | `DistLensTests/UniformTests.lean` (new), `DistLensTests.lean` |
| F3 | minor: `MathlibUniformTests` was only partly meaningful.  Its `uniformOfFinset` pair involved no ambiguity, and the user-facing failure paths (4.34 qualified spelling, `open PMF` only, namespace trap) were unpinned | Rewritten into four sections (module doc lists them): (1) `open PMF DistLens`: an `rfl` example pins which constant the bare `uniformOfFintype` resolves to, a `#check` pins the qualified pretty-printing, and the three original `#dist`/`pmf_num`/`die` checks are kept.  (2) … plus `open MeasureTheory.Measure`: here the original `uniformOfFinset` `#dist` + `pmf_num` pair sits under a real ambiguity, with an `rfl` resolution pin and the one-argument spelling's "Ambiguous term" error.  (3) `open PMF` only and no `open`: the alias at its Measure type (`#check`), the `v4.34.0` spellings `uniformOfFintype (Fin 6)` / `PMF.uniformOfFintype (Fin 6)`, the alias at its new type, `#dist_film`, `MeasureTheory.Measure.uniformOfFinset`, another measure (`dirac`), a Measure-valued `#chain` step, and the showcase shape (a `def` whose body fails, then `#dist` of it).  Each pin records Mathlib's deprecation warning, Lean's mismatch and DistLens's refusal in full.  (4) The namespace trap (`linter.ambiguousOpen` warning pinned, and the bare name still Mathlib's alias), then the top-level `open PMF DistLens` fix compiling, `#dist`ing and `pmf_num`-verifying a die inside `namespace Fixed.DistLens`.  All 6 original assertions are kept (3 → 18 `#guard_msgs`, 3 → 7 `example`s). | `DistLensTests/MathlibUniformTests.lean` |
| F4 | minor: writing Mathlib's alias `PMF.uniformOfFintype` (now Measure-valued) or `MeasureTheory.Measure.uniformOfFinset` got a generic refusal with no pointer to DistLens's constructors, and under `open PMF` the refused term printed as a bare `uniformOfFintype …` | New `DistLens.measureHint?` (`Extract.lean`).  When a refused term's type is a `MeasureTheory.Measure`, it appends a `Hint:` paragraph.  If the head is `PMF.uniformOfFintype` or `MeasureTheory.Measure.uniformOfFinset` (`measureUniformHeads`; single-backtick literals, because DistLens does not import the module that declares them), the hint names that constant fully qualified and explains the v4.35 change.  Otherwise it is a generic "DistLens draws `PMF`s, not measures".  Both versions say to write `DistLens.uniformOfFintype α` / `DistLens.uniformOfFinset s hs`, or to put `open DistLens` at top level.  It is used by `checkIsPMF` (`Widget.lean`: `#dist`, `#dist_film`) and by `extractChain`'s codomain check (`#chain`; for a `fun i => …` step it reads the body's head).  (Round 2, G1: as first written, the `#chain` call site gave no hint when the codomain mentions the bound variable, which is the case for the `v4.34.0` spelling `fun _ : Fin 2 => PMF.uniformOfFintype (Fin 2)`; fixed and pinned there.)  Non-Measure types keep the old message byte for byte (`ExtractTests`' `3 : ℕ` pin passes unchanged; round 2 added two `#chain` pins for that path).  Pinned in `MathlibUniformTests` §3–§4.  Not covered: a `def` whose body already failed to elaborate is `sorry`, so `#dist` of it can only say "`sorryAx` is not a supported PMF constructor" (pinned; the error that matters is Lean's own at the `def`). | `DistLens/Extract.lean`, `DistLens/Widget.lean` |
| F5 | minor: QED64's `qed64-showcase/lean/examples/dist-lens.lean` no longer compiles against the port, and gotcha 2's advice ("needs `open PMF DistLens`") was ambiguous: inside `namespace Showcase.DistLens` an `open DistLens` opens `Showcase.DistLens` instead | Outside this package, so not edited (reported to the orchestrator with the exact fix: change the top-level line 14 `open PMF` to `open PMF DistLens`, regenerate `gallery/examples.json`, re-record the two goldens' `exampleSha256`).  Gotcha 2 now says the `open` must be at top level.  `MathlibUniformTests` §4 pins both the trap and the fix's shape, so the advice is test-backed. | `PORT-NOTES.md`, `DistLensTests/MathlibUniformTests.lean` |
| F6 | minor: stale structure.  The H1 named only the 4.32.2 → 4.34.0 port, and that port's subsections were `##`, siblings of `## Lean 4.34.0 → 4.35.0` | H1 retitled `PORT-NOTES — dist-lens: Lean / Mathlib v4.32.2 → v4.34.0 → v4.35.0`.  The seven subsections of the previous port (Changes … the 2026-10-12 elaborator note) are demoted to `###` under `## Lean 4.32.2 → 4.34.0`, so each port is one `##` section. | `PORT-NOTES.md` |
| F7 | minor: `lake test` is fragile under memory pressure.  ClickE2E peaks at ≈ 19.1 GB, but the build lock admitted the audit's first run at `MIN_FREE_GB=10`, and it was SIGKILLed (exit 137) | Not a defect in the code (memory has not grown since the 4.34 port, ≈ 20 GB).  The lock threshold belongs to the caller: this package's `lake test` runs are now made with `MIN_FREE_GB=20` (gotcha 7 updated with the figure to use).  Splitting ClickE2E's in-process compiles into several modules was considered and not done: each fixture compiles against the same full Mathlib environment, so a split would multiply the import cost and change ClickE2E's structure and counts, for no gain under a serialised lock. | `PORT-NOTES.md` |

**Mutation re-run.**  Each mutation was applied to the final tree, built through the
lock with the named target, and then restored.  `shasum` over every `.lean` file was
byte-identical before and after.

| Mutation | Built | Result |
|---|---|---|
| M5 (the audit's, survived before): drop `DistLens.uniformOfFinset_apply` from `pmf_num`'s simp set (`Verify.lean`) | `DistLensTests.UniformTests` | **caught**: `UniformTests.lean:79:2`, `:83:2` `ennreal_num: cannot close this ℝ≥0∞ goal` (the two `uniformOfFinset` `pmf_num` examples under `attribute [-simp]`) |
| M5b: drop `DistLens.uniformOfFintype_apply` from the same set | `DistLensTests.UniformTests` | **caught**: `:75:60` `ennreal_num: cannot close …` |
| M7 (the audit's, survived before): delete the `@[simp]` line of `DistLens.uniformOfFintype_apply` (`Uniform.lean`) | `DistLensTests.UniformTests` | **caught**: `:42:58`, `:43:58` `` `simp` made no progress ``, plus the negative control's `#guard_msgs` at `:59` |
| M7b: delete the `@[simp]` line of `DistLens.uniformOfFinset_apply` | `DistLensTests.UniformTests` | **caught**: `:49:2`, `:52:2` `` `simp` made no progress ``, plus the control at `:66` |
| M8: `measureHint?` never hints (`unless … Measure …` → `return none`) | `DistLensTests.MathlibUniformTests` | **caught**: 8 `#guard_msgs` (`:158 :174 :189 :246 :254 :263 :272 :314`) |
| M9: drop `` `PMF.uniformOfFintype `` from `measureUniformHeads` (so the alias gets the generic hint) | `DistLensTests.MathlibUniformTests` | **caught**: 5 `#guard_msgs` (`:158 :174 :189 :246 :314`) |

**Counts after the fixes** (same anchored-grep method; per file: `#guard_msgs`
36 Extract, 18 MathlibUniform, 6 StackGuard, 4 Verify, 4 Suggest, 2 Uniform;
`example` 38 Verify, 12 Uniform, 7 MathlibUniform, 6 StackGuard, 5 Suggest,
1 ClickE2E): 70 `#guard_msgs` + 205 `#guard` + 69 `example`s + 52 ClickE2E calls =
**396** (363 after the port; +33, all new: +17 `#guard_msgs`, +16 `example`s).  No
assertion was removed and no expected output changed; the original `uniformOfFinset`
`#dist`/`pmf_num` pair of `MathlibUniformTests` now runs with `MeasureTheory.Measure`
open as well (a stricter context).  `Demo.lean` still has 17 examples and
12 panel commands.

**Verification transcript (post-audit, final tree).**

One locked job (`port435-fix-dist-lens-mutations-buildtest`, `MIN_FREE_GB=20`; the
lock reported 20.4 GiB reclaimable) on 2026-10-25 from the package root.  It ran a
precheck of the two new/rewritten modules (green), then the six mutations above, then
the byte-identity check (`RESTORE=byte-identical`).  Then `rm -rf
.lake/build/lib/lean/DistLens* .lake/build/ir/DistLens*` (this package's own outputs
only), so every `DistLens.*`/`DistLensTests.*` module was recompiled, and:

```
$ lake build
⚠ [3128/3136] Built DistLens.Model (1.4s)
⚠ [3129/3136] Built DistLens.Uniform (1.8s)
✔ [3130/3136] Built DistLens.Render (1.1s)
⚠ [3131/3136] Built DistLens.Verify (2.2s)
⚠ [3132/3136] Built DistLens.Extract (2.6s)
✔ [3133/3136] Built DistLens.Widget (2.1s)
✔ [3134/3136] Built DistLens.Demo (3.9s)
✔ [3135/3136] Built DistLens (1.7s)
Build completed successfully (3136 jobs).
exit 0   # the ⚠ are the same 11 module-system warnings as the port's run (Model 2,
         # Uniform 1, Verify 5, Extract 3); no other warning or error line

$ /usr/bin/time -l lake test
✔ [3137/3151] Built DistLensTests.Helpers (2.4s)
✔ [3138/3151] Built DistLensTests.StackGuardTests (2.4s)
✔ [3139/3151] Built DistLensTests.UniformTests (2.6s)
⚠ [3140/3151] Built DistLensTests.MathlibUniformTests (2.6s)
✔ [3141/3151] Built DistLensTests.TextTests (5.5s)
✔ [3142/3151] Built DistLensTests.ChainMathTests (5.6s)
✔ [3143/3151] Built DistLensTests.InvariantTests (5.5s)
✔ [3144/3151] Built DistLensTests.RenderTests (5.7s)
✔ [3145/3151] Built DistLensTests.ContractTests (5.7s)
✔ [3146/3151] Built DistLensTests.ModelTests (5.8s)
✔ [3147/3151] Built DistLensTests.ExtractTests (5.8s)
✔ [3148/3151] Built DistLensTests.SuggestTests (6.4s)
✔ [3149/3151] Built DistLensTests.VerifyTests (8.4s)
✔ [3150/3151] Built DistLensTests.ClickE2E (110s)
✔ [3151/3151] Built DistLensTests (1.0s)
      116.54 real        53.80 user        87.94 sys
         15097970688  maximum resident set size
exit 0   # 12 module-system warnings (the 11 replayed + 1 for MathlibUniformTests;
         # UniformTests imports no Mathlib module directly and prints none); no other
         # warning or error line
```

Before this job: one probe job (`port435-fix-dist-lens-probe`).  It ran `lake build`
(green), scratch probes (`lake env lean`, not committed) that printed every message
the new pins record, and the non-ClickE2E test modules; the new modules' first drafts
were red there (placeholder expectations, and `simp made no progress` without the
backticks Lean 4.35 prints), and the pins were then written from that output.
No `.lean` file changed after the final job started; only `PORT-NOTES.md` and
`README.md` were edited afterwards.

### Post-audit fixes, round 2 (2026-10-26)

A re-audit of the fixed tree (verdict *fail*: one major and four minor findings; one of
its seven mutations, X8, survived) was followed by these fixes, on the same uncommitted
tree and under the same rules.

| # | Finding (severity) | Fix | Files |
|---|---|---|---|
| G1 | **major**: no hint for the likeliest `#chain` migration case, a `v4.34.0`-spelled step `fun _ : Fin 2 => PMF.uniformOfFintype (Fin 2)` (or the bare name under `open PMF`).  The failed argument leaves the codomain `(x : Fin 2) → MeasureTheory.Measure (?m.7 x)`, so the codomain passed to `measureHint?` had a loose bound variable, and its guard `if ty.hasLooseBVars then return none` suppressed the hint.  Mutation X8 (delete the guard) survived | Guard deleted.  `extractChain` now opens the step's binder on a local (`withLocalDecl`, with the binder's own name, info and domain).  It passes `measureHint?` the codomain and, for a `fun i => …` step, the body, both instantiated with that local, so `measureHint?` only sees closed terms (its docstring says so).  Three new `#guard_msgs` pins in `MathlibUniformTests` §3, each recording Mathlib's deprecation warning, Lean's mismatch and the refusal in full: the bare `uniformOfFintype (Fin 2)` step under `open PMF` (`PMFOnly`) and the qualified `PMF.uniformOfFintype (Fin 2)` step (`NoOpen`), both with the specific `PMF.uniformOfFintype` hint; and a genuinely dependent Measure codomain, `fun i : Fin 2 => MeasureTheory.Measure.dirac (0 : Fin (i.val + 1))`, with the generic hint.  Item 3 of the module doc mentions the `#chain` case. | `DistLens/Extract.lean`, `DistLensTests/MathlibUniformTests.lean` |
| G2 | minor: no pin for `#chain`'s refusal of a non-Measure codomain (the `none` branch of the new call site).  The only `#chain` type pin, `(3 : ℕ)`, fails earlier, at the `.forallE` match | Two `#guard_msgs` pins in `ExtractTests` (no Mathlib `Uniform` import needed), each pinning the bare refusal with no hint: `fun _ : Fin 2 => PMF.pure (0 : Fin 3)` (a `PMF` codomain over the wrong carrier) and `fun _ : Fin 2 => (3 : ℕ)` (no `PMF` head at all). | `DistLensTests/ExtractTests.lean` |
| G3 | minor: the `Uniform.lean` header's list of dropped declarations omitted `MeasureTheory.pdf.uniformPDF`, `uniformPDF_eq_pdf` and `uniformPDF_ite`, so F1's "named one by one" was false | The list now names, by namespace, every declaration of the `v4.34.0` file except the four kept: `IsUniform`, its 13 lemmas and `IsUniform.cond`; the three `uniformPDF` declarations; the ten `PMF` support/measure lemmas; and the seven `OfMultiset` declarations (35 in all).  A script over `git show 5ed29652:Mathlib/Probability/Distributions/Uniform.lean` (39 `theorem`/`lemma`/`def` declarations) checked that each of the 35 is named in the header.  The header also records that Mathlib's file is a `module` with two more `public import`s, and that its module docstring was replaced.  The module docstring's summary of what was dropped is corrected to match. | `DistLens/Uniform.lean` |
| G4 | minor: Apache-2.0 §4(a) requires giving recipients a copy of the License, and `LICENSE` held only the 15-line notice pointing to the URL | New `LICENSE-APACHE-2.0`: the Apache License, Version 2.0 text verbatim, 201 lines / 11357 bytes, SHA-256 `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4`.  It is a copy of `.lake/packages/batteries/LICENSE`, byte-identical to the `LICENSE` of six more dependencies (Aesop, Qq, plausible, ProofWidgets, importGraph, LeanSearchClient).  `LICENSE` keeps its copyright line and notice and ends with a pointer to the new file.  `NOTICE` (twice: the package's license and Mathlib's), the `Uniform.lean` header and the README "License" section reference it. | `LICENSE-APACHE-2.0` (new), `LICENSE`, `NOTICE`, `DistLens/Uniform.lean`, `README.md` |
| G5 | minor: PORT-NOTES inaccuracies.  F4 said "`MathlibUniformTests` §2–§4", but §2 has no hint pin; gotcha 7's `MIN_FREE_GB=20` is below the re-audit's 21.7 GB peak; F4 inherited G1's false `#chain` claim | F4 says §3–§4 and notes the G1 gap; F1 notes G3 and G4; gotcha 7 lists the observed peaks (15.1–21.7 GB) and calls 20 a floor, not a margin; the counts table gains a round-2 column; "Untouched" lists the round-2 files.  README: the census, and the `open PMF` paragraph names the `#chain` case. | `PORT-NOTES.md`, `README.md` |

No existing assertion changed or was removed, and no expected output changed: round 2
only adds pins (the pre-existing `#chain` Measure pin and the `3 : ℕ` pins pass
unchanged).  The five new pins passed on their first build (`fix2-dist-lens-pins`:
`lake build DistLens DistLensTests.MathlibUniformTests DistLensTests.ExtractTests`,
exit 0), so their expected text is exactly what Lean prints.  The two step pins' first
three messages are, apart from file positions, the re-audit's `ChainAlias` probe
output for the same commands, with the hint now added.

**Mutations.**  Each one was applied to `DistLens/Extract.lean`, then
`DistLensTests.MathlibUniformTests` and `DistLensTests.ExtractTests` were built through
the lock, and the file was restored (`cmp` byte-identical every time).

| Mutation | Result |
|---|---|
| P1: the pre-round-2 `Extract.lean` (guard present, codomain passed open) | **caught**: `MathlibUniformTests:217` (bare step under `open PMF`), `:326` (qualified step), `:335` (dependent `dirac`) |
| P2b: the `#chain` `none` branch appends a hint (`throwError m!"{tyErr}\n\nHint: …"`) | **caught**: `ExtractTests:381`, `:387` (the G2 pins; nothing else pins that branch) |
| P3 (the re-audit's X2): delete `unless ty.isAppOf ``MeasureTheory.Measure do return none` | **caught**: `ExtractTests:349` (`#dist (3 : ℕ)`, as before), `:381`, `:387` (the G2 pins) |
| P2: the `none` branch appends only `"\n\n"` | survived: `#guard_msgs` trims trailing whitespace, so the change is invisible in any pinned message (it only adds trailing blank lines) |
| P4: no local, so codomain and body are passed with the loose bound variable (X8's state) | survived, as expected: `whnfR`, `isAppOf` and `getAppFn` give the same answers on these terms either way, as X8 showed.  The local exists so that no Meta function runs on an open term; it makes no observable difference |
| P5: the old guard restored on top of the local | survived, as expected: with the local in place no caller passes an open term, so the guard never fires |

**Counts after round 2** (same anchored-grep method, recounted by script on both the
pre-round-2 backup, which gives 396, and the final tree; per file: `#guard_msgs` 38
Extract, 21 MathlibUniform, 6 StackGuard, 4 Verify, 4 Suggest, 2 Uniform; `example`
unchanged): 75 `#guard_msgs` + 205 `#guard` + 69 `example`s + 52 ClickE2E calls =
**401** (+5, all new `#guard_msgs`: 3 MathlibUniform, 2 Extract).  `Demo.lean` still has
17 examples and 12 panel commands.

**Verification transcript (round 2, final tree).**

One locked job (`fix2-dist-lens-final-buildtest`, `MIN_FREE_GB=20`; the lock reported
20.6 GiB reclaimable) on 2026-10-26 from the package root.  It recorded `shasum` over
every `.lean` file, ran mutation P2b (above) and restored it (`P2b_RESTORED=byte-identical`,
`TREE=byte-identical`), then `rm -rf .lake/build/lib/lean/DistLens* .lake/build/ir/DistLens*`
(this package's own outputs only), so every `DistLens.*`/`DistLensTests.*` module was
recompiled, and:

```
$ lake build
⚠ [3128/3136] Built DistLens.Model (1.1s)
⚠ [3129/3136] Built DistLens.Uniform (1.5s)
✔ [3130/3136] Built DistLens.Render (909ms)
⚠ [3131/3136] Built DistLens.Verify (1.8s)
⚠ [3132/3136] Built DistLens.Extract (2.2s)
✔ [3133/3136] Built DistLens.Widget (1.7s)
✔ [3134/3136] Built DistLens.Demo (3.4s)
✔ [3135/3136] Built DistLens (1.4s)
Build completed successfully (3136 jobs).
exit 0   # the ⚠ are the same 11 module-system warnings (Model 2, Uniform 1, Verify 5,
         # Extract 3); no other warning or error line

$ /usr/bin/time -l lake test
✔ [3137/3151] Built DistLensTests.Helpers (1.8s)
✔ [3138/3151] Built DistLensTests.StackGuardTests (1.9s)
✔ [3139/3151] Built DistLensTests.UniformTests (1.0s)
⚠ [3140/3151] Built DistLensTests.MathlibUniformTests (2.0s)
✔ [3141/3151] Built DistLensTests.ChainMathTests (5.7s)
✔ [3142/3151] Built DistLensTests.TextTests (5.6s)
✔ [3143/3151] Built DistLensTests.RenderTests (5.7s)
✔ [3144/3151] Built DistLensTests.ContractTests (5.7s)
✔ [3145/3151] Built DistLensTests.InvariantTests (5.6s)
✔ [3146/3151] Built DistLensTests.ModelTests (5.8s)
✔ [3147/3151] Built DistLensTests.ExtractTests (5.8s)
✔ [3148/3151] Built DistLensTests.SuggestTests (6.3s)
✔ [3149/3151] Built DistLensTests.VerifyTests (8.4s)
✔ [3150/3151] Built DistLensTests.ClickE2E (92s)
✔ [3151/3151] Built DistLensTests (1.9s)
       97.61 real        49.40 user        83.09 sys
         19245252608  maximum resident set size
exit 0   # 12 module-system warnings (the 11 replayed + 1 for MathlibUniformTests);
         # no other warning or error line
```

The `.lean` `shasum` at the end of the job matched the one at its start
(`END_TREE=byte-identical`).  Before this job: `fix2-dist-lens-pins` (the five new pins'
first build, green) and `fix2-dist-lens-mutations` (P1–P5 above, each restored
byte-identically, then `AFTER_EXIT=0`).  A first attempt at this job with
`MIN_FREE_GB=24` was stopped while it waited for memory (21.6–23.0 GiB reclaimable),
before it ran anything.  No `.lean` file changed after the final job started; only
`PORT-NOTES.md` was edited afterwards.

---

## Lean 4.32.2 → 4.34.0 (the previous port)

Reference (read-only): `widgets/dist-lens` (toolchain `leanprover/lean4:v4.32.2`,
Mathlib `v4.32.2`, ProofWidgets `6e311e2a`).
Port: `widgets-v4.34/dist-lens` (toolchain `leanprover/lean4:v4.34.0`, Mathlib
`v4.34.0` = `5ed29652`, ProofWidgets `106ff4fa`, Batteries `f2effa3d`, Aesop
`355695d5`, Qq `6a489d9a`, plausible `118aa17e`, importGraph `e928b725`,
LeanSearchClient `ddf04cf3`, Cli `e92c9f15` — all taken from Mathlib's
manifest by the one `lake update` the harness ran; never run it again).

Status: `lake build` and `lake test` both exit 0 on v4.34.0 (the final
evidence run is transcribed in the "Verification transcript" section at the
bottom of this file — an earlier draft referred to a transcript that was
never actually pasted in).  Every test file, the demo file
and the whole library except one tactic macro are byte-identical to the
reference (`diff -ru` over the two trees excluding `.lake/`, `scratch/`,
`*.log` and the manifest shows exactly three files: `lean-toolchain`,
`lakefile.toml`, `DistLens/Verify.lean`).

### Changes

| File | What | Why |
|---|---|---|
| `lean-toolchain` | `leanprover/lean4:v4.32.2` → `leanprover/lean4:v4.34.0` | the port target (set by the harness, not edited by the port agents) |
| `lakefile.toml` | `mathlib` `rev = "v4.32.2"` → `rev = "v4.34.0"` | same |
| `lake-manifest.json` | every dependency rev bumped to the ones Mathlib `v4.34.0` pins; `Cli` inputRev `v4.32.0` → `v4.34.0` | produced by the harness's single `lake update`; ProofWidgets moves from `6e311e2a` to `106ff4fa` (no API this package uses changed — every panel/render/RPC test passes unmodified) |
| `DistLens/Verify.lean` | inside the `pmf_num` macro, the `simp` step is now wrapped as `(set_option backward.isDefEq.respectTransparency.types false in simp [...])`; the `try`, the lemma list, the `<;> ennreal_num` continuation and the outer `set_option linter.deprecated false in` are unchanged.  Comment added explaining the option (this session corrected its version claim: the default flipped at v4.33.0, not v4.34.0). | **Forced by the toolchain.**  `backward.isDefEq.respectTransparency.types` is registered in `Lean/Meta/ExprDefEq.lean` with `defValue := false` at v4.32.2 (`-- TODO: replace with true after we fix stage0`) and `defValue := true` at v4.33.0 and v4.34.0.  With `true`, when `simp` instantiates `PMF.uniformOfFinset_apply`'s `hs : s.Nonempty` metavariable with the user's proof term, the term's type is compared with the metavariable's type **without** bumping transparency to `.default`.  The natural spelling `⟨1, by simp⟩` (used by the demo, the tests, and every suggestion DistLens emits for `uniformOfFinset`) elaborates to an `Exists.intro` whose inferred type is `∃ x, x ∈ s`; `Finset.Nonempty s` is a semireducible `def` for exactly that proposition, so at implicit transparency the types do not match, the rewrite silently does not fire, and `pmf_num` ends in `ennreal_num: cannot close this ℝ≥0∞ goal ⊢ (uniformOfFinset {1, 2, 3} ⋯) 2 = 3⁻¹` — a refused *true* claim.  Verified by MWE at v4.34.0 (`scratch/Probe1.lean`, `scratch/Probe2.lean` from the first port agent, and this session's `ProbeOld.lean`): the v4.32.2 recipe verbatim fails on `uniformOfFinset`, `simp` reports `PMF.uniformOfFinset_apply` as an *unused* simp argument, and the same recipe still proves the `uniformOfFintype`, `bernoulli`, `binomial`, `ofFintype`, `bind`/`map` examples — only the `Finset.Nonempty` argument is affected.  The option is scoped to the single `simp` call, so nothing else in the recipe (and no user code) runs under the legacy behaviour; false claims still fail with the same deterministic message (pinned by `VerifyTests`' `#guard_msgs` negatives, which pass unchanged). |
| `README.md` | new "Versions" section; `pmf_num` section documents the scoped option; "Deprecated upstream API" bullet states the deprecations are still present (not removed) at `v4.34.0` and names the successors; "Tests" paragraph replaces the approximate "~237" with the explicit census below | documentation of the port |
| `PORT-NOTES.md` | this file | required deliverable |

Alternatives considered for the `Verify.lean` change and rejected:
* changing the *suggested* spelling (e.g. `(by simp)` instead of `⟨1, by simp⟩`,
  or `Finset.insert_nonempty _ _`) — would alter the generated suggestion
  text, the `#guard_msgs` pins and the demo, and would still leave a user's
  own `⟨_, _⟩` proof unprovable by `pmf_num`;
* adding `Finset.Nonempty` unfolding lemmas to the simp set — changes the
  recipe's normal forms and the pinned failure messages;
* setting the option globally — forbidden (global option suppression) and
  unnecessary.

### Pin updates

None.  No `#guard_msgs` block, no `#guard`, no byte-exact SVG/ASCII pin, no
suggestion text and no failure message changed between the reference and the
port — the test tree is byte-identical and green.  (The scoped option was
chosen precisely so that `pmf_num`'s observable behaviour, including the
deterministic failure messages pinned by `VerifyTests.lean`, is unchanged.)

### Deviations

None.  No test deleted, commented out or weakened; no `sorry`; no global
linter/option suppression; both whitelist entries (`PMF.bernoulli`,
`PMF.binomial`) and all 14 lemmas of the `pmf_num` simp set are retained
verbatim.

Risk list from the research, resolved:
* **`PMF.bernoulli`/`PMF.binomial` removed at v4.34.0?**  No.  At Mathlib
  `v4.34.0` they are still `@[deprecated ProbabilityTheory.bernoulliMeasure
  (since := "2026-04-07")]` / `@[deprecated ProbabilityTheory.binomial (since
  := "2026-04-07")]` with the same dates as at `v4.32.2`; `bernoulli_apply` →
  `bernoulliMeasure_apply`, `binomial_apply` →
  `binomial_real_singleton` are likewise still-present deprecations.  The
  whitelist, the simp set and the `set_option linter.deprecated false in`
  wrapper stay as they were.
* **PMF lemma names in the simp set.**  All 14 resolve unchanged
  (`PMF.bind_apply`, `map_apply`, `pure_apply`, `bernoulli_apply`,
  `uniformOfFintype_apply`, `uniformOfFinset_apply`, `binomial_apply`,
  `ofFintype_apply`, `tsum_fintype`, `tsum_bool`, `Fin.sum_univ_succ`,
  `Matrix.cons_val_zero`, `Matrix.cons_val_one`, `Matrix.head_cons`).
* **ENNReal / `finiteness` behaviour.**  Unchanged: all four `ennreal_num`
  branches close the same residues, all 38 `VerifyTests` examples and the 17
  demo examples compile, the negative pins match byte-for-byte.
* **Probability module moves.**  None of the five imports moved
  (`Mathlib.Probability.ProbabilityMassFunction.{Constructions,Binomial,Integrals}`,
  `Mathlib.Probability.Distributions.Uniform`, `Mathlib.Tactic.Finiteness`).
* **`Matrix.vecCons` literals.**  Unchanged: `![…]` weight vectors and
  `![…]`-vectors of PMFs still extract and still reduce under
  `Matrix.cons_val_*` (`ChainMathTests`, `ExtractTests`, the weather/triangle
  chains in `Demo.lean`).

### Counts

Method (reproducible with `grep` over the two trees; the test sources are
byte-identical so every number is the same on both sides):

| Category | Reference v4.32.2 | Port v4.34.0 |
|---|---|---|
| `#guard_msgs` blocks in `DistLensTests/` (36 Extract, 4 Verify, 4 Suggest) | 44 | 44 |
| `#guard` in `DistLensTests/` (46 Model, 43 Render, 24 Contract, 23 ChainMath, 20 Suggest, 18 Text, 9 Invariant, 21 ClickE2E, 1 driver root) | 205 | 205 |
| compiled `example`s in `DistLensTests/` (38 Verify, 5 Suggest, 1 ClickE2E) | 44 | 44 |
| ClickE2E runtime assertions (`check` 23, `checkClean` 15, `checkEq` 8, `checkFails` 6) across its 8 `#eval` suites | 52 | 52 |
| **Test-driver total (`lake test`)** | **345** | **345** |
| `DistLens/Demo.lean`: compiled `example`s / live panel commands (`lake build`) | 17 / 12 | 17 / 12 |

The README previously quoted "~237 pinned assertions" without stating a
counting method; it now quotes the census above with the method spelled out.

Exact commands (run from the package root; identical results on both trees):
`grep -rhE '^\s*#guard_msgs\b' DistLensTests DistLensTests.lean | wc -l` → 44;
`grep -rhE '^\s*#guard(\s|$)' DistLensTests DistLensTests.lean | wc -l` → 205;
`grep -rhE '^\s*example\b' DistLensTests DistLensTests.lean | wc -l` → 44;
ClickE2E call counts = occurrences of each `check*` identifier in
`DistLensTests/ClickE2E.lean` *excluding* the four `def check*` lines
(231/235/241/246) → 23 + 15 + 8 + 6 = 52. Correction (2026-09-30, audit
follow-up): an earlier draft said 45 `#guard_msgs` (37 Extract) and a
ClickE2E breakdown of 24/16/9/7 "= 52"; the `#guard_msgs` grep was
unanchored and matched the docstring mention at `ExtractTests.lean:6`, and
the breakdown had counted the four `def` lines. The totals above (44 and
345) are the anchored figures.

### 4.34 gotchas worth knowing for QED64

1. **`backward.isDefEq.respectTransparency.types` defaults to `true` from
   Lean v4.33.0.**  Per its `register_builtin_option` description, Lean no
   longer bumps transparency to `.default` "when checking whether the type
   of a metavariable matches the type of the term being assigned to it" —
   the check runs at whatever transparency the unifier is already in
   (reducible inside `simp`).  Any rewrite/simp lemma whose argument is a
   proof of a semireducible `def`-proposition (`Finset.Nonempty` is the
   verified case; `Set.Nonempty`-style defs are the same shape) stops
   firing when the user's proof term was elaborated through the unfolded
   form (anonymous constructor / `Exists.intro`).  Symptoms
   are silent: no error, `simp` just reports the lemma unused.  Fix at the
   call site with `set_option backward.isDefEq.respectTransparency.types false
   in` scoped to the one tactic, or spell the proof with a lemma that has the
   `def` as its stated type.  In an in-browser playground this is the kind of
   regression that turns a "verified" click-to-insert goal into a red
   squiggle, so every suggestion-emitting widget should compile its own
   suggestions in tests (DistLens does: `VerifyTests`, `SuggestTests`,
   `ClickE2E`, `Demo`).
2. **Recipe tactics are not linted for unused simp args.**  The
   `linter.unusedSimpArgs` warning (present since before v4.32.2) fires on a
   user-written `simp [...]` but not on the `simp` that `pmf_num` runs (first
   as a macro, since 2026-10-12 from its elaborator; see the last section),
   so inserted `by unfold …; pmf_num` lines stay warning-free (`ClickE2E`'s
   `checkClean` fixtures prove it at v4.34.0).  Keep tactic recipes behind a
   tactic of their own if their simp set is deliberately over-complete.
3. **`PMF.bernoulli`/`PMF.binomial` are deprecated-but-present** at Mathlib
   `v4.34.0` (since 2026-04-07).  Any widget that names them needs
   `linter.deprecated` set to false *inside* its tactic (as `pmf_num` does:
   `set_option … in` in the macro, `withOptions` in the elaborator), or every
   inserted proof will warn.  Successors are Measure-valued
   (`ProbabilityTheory.bernoulliMeasure`, `ProbabilityTheory.binomial`) and
   need a different lemma set and `MeasurableSet` side goals.
4. **No Probability module moves between v4.32.2 and v4.34.0** for the
   files this package imports; `Mathlib.Tactic.Finiteness` and
   `Mathlib.Tactic.NormNum` are unchanged.
5. **ProofWidgets `6e311e2a` → `106ff4fa`** (through Mathlib's manifest):
   `Html`, `MakeEditLink`, `mk_rpc_widget%`, `server_rpc_method`,
   `RequestM.readDoc` and the `LazyEncodable Json` component-props shape are
   all source-compatible for this package — zero changes in
   `Widget.lean`/`Render.lean`.
6. **Memory of the in-process ClickE2E harness.**  Compiling
   `DistLensTests.ClickE2E` imports a full Mathlib environment inside the
   elaborating `lean` process (~5 GB RSS at v4.34.0).  Running two such
   suites concurrently on a loaded machine got this one SIGKILLed (exit 137)
   once during the port; rerun alone it passes.  Not a toolchain regression,
   but worth a serial `lake test` in CI.
7. **`lake test` with a warm cache prints nothing.**  If every target is
   up to date the driver exits 0 silently; to see the suite actually run,
   delete `.lake/build/lib/lean/DistLensTests*` (and `ir/DistLensTests*`)
   first, as this port did for its evidence run.
8. **The `Verify.lean` fix has a horizon.**  It relies on the
   `backward.isDefEq.respectTransparency.types` compatibility option
   (verified still registered with `defValue := true` at v4.34.1 and
   v4.35.0-rc3).  Core eventually deletes `backward.*` options once the
   migration they cover is considered complete; when this one is removed,
   `set_option backward.isDefEq.respectTransparency.types false in` becomes
   an *unknown option* error and every `by pmf_num` on a `uniformOfFinset`
   goal (the demo, `VerifyTests`, every emitted suggestion) fails to
   elaborate.  The permanent fix will have to change what `pmf_num` does
   rather than how the unifier behaves: either emit/accept a proof whose
   *stated* type is `Finset.Nonempty s` (e.g. `Finset.insert_nonempty _ _`
   or a `show s.Nonempty from ⟨1, by simp⟩` spelling in the suggestion
   text — which changes the suggestion pins), or add a `Finset.Nonempty`-
   unfolding lemma / `Finset.nonempty_iff_exists_mem`-style rewrite to the
   simp set so the `hs` argument is matched after unfolding (which changes
   the recipe's normal forms and the pinned failure messages).  Neither was
   done in this port because both alter pinned behaviour; the scoped option
   is the zero-pin-change bridge.  Watch the Lean release notes for the
   option's removal.

### Verification transcript (2026-09-30, audit follow-up)

Run from the package root on `leanprover/lean4:v4.34.0` after deleting this
package's own outputs (`rm -rf .lake/build/lib/lean/DistLens*
.lake/build/ir/DistLens*`) so that every `DistLens.*` and `DistLensTests.*`
module was genuinely recompiled; Mathlib oleans came from the existing cache.
No source file was touched between the port's last edit and this run.

```
$ lake build
✔ [3081/3088] Built DistLens.Model (1.8s)
✔ [3082/3088] Built DistLens.Render (1.1s)
✔ [3083/3088] Built DistLens.Verify (5.6s)
✔ [3084/3088] Built DistLens.Extract (5.7s)
✔ [3085/3088] Built DistLens.Widget (2.3s)
✔ [3086/3088] Built DistLens.Demo (4.6s)
✔ [3087/3088] Built DistLens (1.8s)
Build completed successfully (3088 jobs).
exit 0            # 0 lines matching ⚠ / warning: / error:

$ lake test       # first attempt, while four other lake invocations ran concurrently
✔ [3088/3099] Built DistLensTests.Helpers (1.8s)
✔ [3089/3099] Built DistLensTests.TextTests (4.6s)
✔ [3090/3099] Built DistLensTests.RenderTests (4.6s)
✔ [3091/3099] Built DistLensTests.ContractTests (4.7s)
✔ [3092/3099] Built DistLensTests.InvariantTests (4.7s)
✔ [3093/3099] Built DistLensTests.ChainMathTests (4.9s)
✔ [3094/3099] Built DistLensTests.ModelTests (5.0s)
✔ [3095/3099] Built DistLensTests.ExtractTests (5.3s)
✔ [3096/3099] Built DistLensTests.SuggestTests (5.7s)
✔ [3097/3099] Built DistLensTests.VerifyTests (8.5s)
✖ [3098/3099] Building DistLensTests.ClickE2E (105s)
error: Lean exited with code 137
exit 1            # SIGKILL = gotcha 6 (memory), not a test failure

$ lake test       # rerun alone, nothing else building on the machine
✔ [3098/3099] Built DistLensTests.ClickE2E (146s)
✔ [3099/3099] Built DistLensTests (4.5s)
exit 0            # 0 lines matching ⚠ / warning: / error:
```

Net result: `lake build` exit 0 (3088 jobs); `lake test` exit 0 (3099 jobs,
all 12 `DistLensTests.*` modules + the driver rebuilt from scratch, zero
warnings). The exit-137 attempt is kept in the transcript on purpose: it is
the reproducible out-of-memory kill described in gotcha 6 (ClickE2E loads a
full Mathlib environment in-process) and goes away when the suite runs
alone — run `lake test` serially in CI.

### 2026-10-12: `pmf_num` / `ennreal_num` became elaborators (browser stack depth)

In the browser (QED64: a WebAssembly Lean whose engine stack is about 500 KiB per Worker, guarded by a probe that
raises "maximum recursion depth has been reached: the WebAssembly runtime's stack is exhausted" when headroom runs
low), the click examples `example : twoDice k = … := by unfold …; pmf_num` failed for k = 1…9 at QED64's default probe
(16384 slots), while the SAME steps typed as one flat tactic sequence passed on the same build: the extra stack came
from the nested tactic-framework layers of the two macros (macro expansion, `first`, `<;>`, `try`, parenthesised
sequences, `set_option … in`), each adding engine frames. Worse, when the guard tripped inside a converting layer
(instance synthesis rethrows runtime errors as "failed to synthesize"), `first` restored the state and the user saw
the misleading "ennreal_num: cannot close this ℝ≥0∞ goal" for a TRUE claim.

Both tactics are now `@[tactic]` elaborators in `DistLens/Verify.lean` that run the same recipe, in the same branch
order, as flat `evalTactic` steps with the options set programmatically (`withOptions` with the typed option
constants) and the goals iterated directly (`<;>` and `first` reimplemented as loops with the same restore semantics;
runtime errors propagate unchanged). Measured natively for `twoDice 5` (`lean --tstack=N -DElab.async=false`): the old
macros need 265 KB of thread stack, the elaborators 197 KB — the same as the hand-written flat sequence, so the
remaining depth is inside `simp`/`finiteness`/`norm_num` themselves. A false or unsupported goal still fails with the
byte-identical "ennreal_num: cannot close this ℝ≥0∞ goal" + goals (`VerifyTests`, `ClickE2E` unchanged); if a failed
branch's error or logged messages mention the WebAssembly stack guard, the failure says "ennreal_num: Lean ran out of
stack while checking this goal, so it could not decide it (the claim may well be true): …" instead (pinned by the new
`DistLensTests/StackGuardTests.lean`). Limit: a guard trip converted by instance synthesis and then swallowed inside
`finiteness` (Aesop) or `norm_num` without a trace still shows "cannot close"; only a QED64/kernel-side trip counter
would catch that. Background: the showcase's `qed64-showcase/docs/REPIN-LOG.md` (pin K) and
`docs/UPSTREAM-REPORT-QED64.md`.

