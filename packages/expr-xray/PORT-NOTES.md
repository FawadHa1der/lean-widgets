# Port notes: expr-xray, Lean v4.32.2 → v4.34.0 → v4.35.0 (QED64 pairing)

Two ports, newest first: v4.34.0 → v4.35.0 (next section) and the earlier
v4.32.2 → v4.34.0 (last section).

## Lean 4.34.0 → 4.35.0 (2026-10-25)

Result: **`lake build` exit 0 (25 jobs) and `lake test` exit 0 (33 jobs) on
`leanprover/lean4:v4.35.0`**, with **zero warnings** in both logs (no
deprecation, no linter output, no replayed warnings). **No Lean source file
changed** in the port. (A later gap-closure pass added tests to
`ExprXRayTests/AnalyzeTests.lean` and changed no library file; see *Gap
closure*.) Every ExprXRay and ExprXRayTests module was recompiled by 4.35.0
(the toolchain change invalidates every build trace: the harness's first
`lake build` compiled the 7 library modules incl. `ExprXRay.Demo`; the
`lake test` below compiled all 9 test-library modules).

### Pins (set by the harness; not edited by this port)

| | 4.34 port (`qed64-pin-i`) | 4.35 port |
|---|---|---|
| `lean-toolchain` | `leanprover/lean4:v4.34.0` | `leanprover/lean4:v4.35.0` |
| ProofWidgets4 (`lakefile.toml` rev, manifest `rev`/`inputRev`) | `106ff4fafc74ef4ac99d81dbf3ab399118f497a5` | `df72b022e558978a1c50264cfc4d7fec86fa8e04` (= Mathlib v4.35.0's own ProofWidgets pin) |
| `lake-manifest.json` `"version"` | `1.2.0` | `1.3.0` (written by 4.35's Lake during the harness's single `lake update`) |

No Mathlib dependency, so no `lake exe cache get` applied to this package.

### Changes

| File | What | Why |
|---|---|---|
| `lean-toolchain` | `v4.34.0` → `v4.35.0` | Harness (not edited here). |
| `lakefile.toml` | ProofWidgets rev `106ff4fa…` → `df72b022…` | Harness (not edited here). |
| `lake-manifest.json` | same rev bump; manifest version `1.2.0` → `1.3.0` | Harness's single `lake update` (never re-run). |
| `README.md` | Toolchain/ProofWidgets sentence → v4.35.0 / `df72b022`; port-history clause extended. Post-audit: census line corrected (459), and the port clause now says "no Lean code change". | Task requirement. |
| `PORT-NOTES.md` | This section. Post-audit: the title, the census, gotchas 2 and 6, a heading for the 4.34 notes, and errata in them. See *Post-audit fixes*. | Task requirement. |
| `ExprXRayTests/AnalyzeTests.lean` | Gap closure, after the port and its audit: new section *Coercion detection through `@[coe]` alone* (2 `#guard`, 2 `#guard_msgs`, 17 `assert*` calls). Additions only. | Closes the audit's surviving mutation M3. See *Gap closure*. |

`git diff qed64-pin-i -- packages/expr-xray` lists only the six files above
(the five of the port, plus the gap-closure test file);
`diff -r --exclude=.lake` of a `qed64-pin-i` export against this tree reports
only the three harness files (before the doc edits).

### Golden/expected-output changes

**None.** All 15 `#guard_msgs` commands (10 in `WidgetTests.lean`, 5 in
`DefeqTests.lean`) pass byte-identical on v4.35.0. They pin the
`#xray (text := true)` / `#xray_diff` delaborator dumps and the defeq
badges/summary lines. The 105 `#guard` commands and the 339 calls of the
throwing `assert*` helpers also pass. (These figures are the post-audit
recount; the first version of this section said 17 / 95 / 344. See *Counts*.)
The gap closure later added 2 new `#guard_msgs` pins in `AnalyzeTests.lean`;
no existing expected output changed.

### Deviations

**None.** No test deleted, commented out, skipped or weakened; no `sorry`; no
`set_option` of any scope; no feature dropped.

### Counts

The census is static. It counts assertion sites in `ExprXRayTests/`:
every `#guard` command, every `#guard_msgs` command, and every call of the
throwing helpers from `TestUtil.lean` (`assertTrue`, `assertFalse`,
`assertEq`, `assertContains`, `assertNotContains`). **Corrected method
(post-audit, 2026-10-25):** The trailing comments give the output on the
current tree, after the gap closure. Before it, the outputs were 105 / 15 /
344 tokens / 5 / 459.

```sh
g=$(grep -rhE '^\s*#guard\b' ExprXRayTests | grep -vc '#guard_msgs')                     # 107
gm=$(grep -rhE '^\s*#guard_msgs\b' ExprXRayTests | wc -l)                                # 17
a=$(grep -rhoE '\bassert(True|False|Eq|Contains|NotContains)\b' ExprXRayTests | wc -l)   # 361 tokens
d=$(grep -rhE '^def assert(True|False|Eq|Contains|NotContains)\b' ExprXRayTests | wc -l) # 5 helper defs
echo $((g + gm + a - d))                                                                 # 480
```

The method that this section (and the 4.34 section) first used gave
95 / 17 / 344 = 456, which is not a count of assertion sites. The commands
were `grep -rhE "^#guard[^_]"`, `grep -rh "#guard_msgs"` and the token grep
without subtracting the definitions. They had three faults:

- `^#guard[^_]` needs a character after `#guard` on the same line. It
  therefore misses the 10 bare `#guard` lines whose term starts on the next
  line, for example `DefeqTests.lean:50`, `DiffTests.lean:27` and
  `TypesTests.lean:35`.
- The unanchored `#guard_msgs` grep also matched 2 docstring mentions:
  `WidgetTests.lean:6` and `DefeqTests.lean:277`.
- The token grep counted the 5 helper *definitions* at `TestUtil.lean:59-79`
  as calls.

A comment- and string-aware recount (block comments, docstrings, `--`
comments and string literals stripped before matching) gives the same
105 / 15 / 339. Per file (`#guard` / `#guard_msgs` / `assert*` calls), in all
three trees: Analyze 0/0/86, Defeq 20/5/67, Diff 18/0/78, Edge 0/0/45,
Render 22/0/55, Types 45/0/0, Widget 0/10/8. The gap closure changed only
Analyze, to 2/2/103. The root `ExprXRayTests.lean`
lies outside `ExprXRayTests/` and is not in the census. It holds one more
`#guard` (`ExprXRay.version = "0.1.0"`) in every tree.

"Before" was counted on a `git archive qed64-pin-i packages/expr-xray`
export. The v4.32.2 original was counted on the repository tag
`lean-v4.32.2`, because the sibling `widgets/` checkout named in the 4.34
section is no longer on disk.

| | `#guard` | `#guard_msgs` | `assert*` calls | total |
|---|---:|---:|---:|---:|
| v4.32.2 original (`lean-v4.32.2`) | 105 | 15 | 339 | **459** |
| before (4.34, `qed64-pin-i`) | 105 | 15 | 339 | **459** |
| after (4.35) | 105 | 15 | 339 | **459** |
| after the gap closure (4.35, `@[coe]` tests) | 107 | 17 | 356 | **480** |
| *(old method's output, all three trees)* | *95* | *17* | *344* | *456* |

Parity is unaffected. The port left the test files byte-identical to
`qed64-pin-i`; only the stated numbers were wrong. The gap closure then only
appended to `AnalyzeTests.lean` (`git diff --numstat`: 95 added, 0 deleted).

### 4.35 gotchas

1. **ProofWidgets `106ff4fa..df72b022` has zero `.lean` changes** (`git diff
   --stat` in `.lake/packages/proofwidgets`: only `lean-toolchain` and
   `.github/workflows/build.yml`; 7 commits = the v4.35.0-rc1 … v4.35.0 bumps
   plus CI hardening). `SelectionPanel`, `Html`, `mk_rpc_widget%`,
   `server_rpc_method`, `widget_module` are therefore unchanged by
   construction.
2. **Two new `isDefEq` backward options** (`Lean/Meta/ExprDefEq.lean:97`,
   `:120`): `backward.isDefEq.throwOnStuckAfterApp` (default `false`: when a
   stuck-on-mvar check after a failed application comparison happens under
   `isDefEqStuckEx`, e.g. in instance search, 4.35 now tries the remaining
   heuristics before throwing) and
   `backward.isDefEq.respectTransparency.instanceSearchTypes` (default
   `true`: during instance search, assignments to instance-implicit mvars
   are type-checked at `.instances` transparency, fix for lean4#9077).
   `checkDefeq` (`Diff.lean:104`) is insulated from both options. It returns
   `undetermined` for any side with mvars, and runs on mvar-free terms in a
   fresh `withNewMCtxDepth`. All `DefeqTests` pins are unchanged: 20 `#guard`,
   5 `#guard_msgs` and 67 `assert*` calls. A QED64 test that pins
   `checkFailed`/`notDefeq` on a pair that needs instance synthesis is the
   place to look first if one moves.

   **Post-audit addition: the 4.35 changes in the same file that reach
   metavariable-free terms.** Source: `diff` of
   `src/lean/Lean/Meta/ExprDefEq.lean` between the v4.34.0 and v4.35.0
   toolchains. Line numbers are v4.35.0's unless marked "4.34".
   - **Failed application pairs take a restructured path.** This runs for
     every pair where both sides are applications, metavariables or not.
     - On 4.34, `isExprDefEqExpensive` tested
       `t.isApp <&&> s.isApp <&&> isDefEqApp t s` (4.34 `:2226`). On
       failure, `isDefEqApp` had already run `isDefEqOnFailure`
       (unification hints; 4.34 `:2166-2178`). The `false` then fell through
       to the `else` branch, which tried `isDefEqProjInst`,
       `isDefEqStringLit` and `isDefEqUnitLike` and finally ran
       `isDefEqOnFailure` a second time (4.34 `:2228-2232`).
     - On 4.35, `isDefEqApp` no longer calls `isDefEqOnFailure`. A failed
       pair goes to `isDefEqAppFallback` (`:2393-2408`, called at `:2432`).
       By default (`throwOnStuckAfterApp = false`) this runs
       `isDefEqOnFailure` once, catching a stuck-on-mvar exception. It then
       tries the same three cases, now grouped as `isDefEqLateSpecialCases`
       (`:2373-2379`), and re-throws the stuck exception only if none of
       them succeeds.
     - For metavariable-free terms the checks and their order are the same.
       The only difference is that the redundant second unification-hint
       pass is gone. The stuck-exception reordering needs metavariables.
     - The audit's description, that 4.34 tried the three late cases only
       for pairs that were *not* both applications, misreads the 4.34
       `<&&>` condition. A failed `isDefEqApp` makes the condition false
       and falls through to them.
     - In any case, at `checkDefeq`'s two transparencies (`withReducible`,
       then the ambient `.default`) `isDefEqProjInst` always declines,
       because it needs `.instances` or `.implicit` (`:2357`).
       `isDefEqStringLit` declines on application pairs, because it needs a
       string literal on one side (`:251-258`).
   - **No native reduction.** `isDefEqNative`, which evaluated
     `Lean.reduceBool`/`Lean.reduceNat` through the interpreter, is gone from
     `isExprDefEqExpensive` (4.34 `:2214`). `whnf` lost its `reduceNative?`
     too (`Lean/Meta/WHNF.lean`). This cannot change a verdict on a 4.35
     term: v4.35.0's `Init/Core.lean` no longer defines `Lean.reduceBool`,
     `Lean.reduceNat` or `Lean.ofReduceBool` (deprecated since 2026-02-01 in
     v4.34.0), so no term can contain them.
   - **First-pass transparency bump.** `isDefEqArgsFirstPass` now runs its
     "easy" argument cases under `withImplicitConfig` (`:390-399`) when
     `respectTransparency` is on and the parameter is instance-implicit or
     `implicitBump` is on. `withImplicitConfig` raises the transparency to at
     least `.implicit`. The easy cases are arguments where one side is an
     unassigned (eta-expanded) metavariable (`:390`). Mvar-free inputs reach
     them only through metavariables created during the check itself, for
     example by a unification hint. The same holds for the new
     instance-typed-mvar path in `checkTypesAndAssign`
     (`spineMVarsAdmissible`, `synthInstanceTypedMVarAndUnify`), which runs
     only when a metavariable is assigned.

   **Net effect on `checkDefeq`: no verdict change expected, and none
   observed.** A scratch probe, kept outside the package, checked this. It
   copies the `checkDefeq` algorithm from `Diff.lean:104-124` and was run with
   each toolchain's `lean` under the build lock. It gives **identical verdicts
   on v4.34.0 and v4.35.0 for all 15 metavariable-free pairs**:
   - 8 unit-like pairs, all `defeqReducible`. They include opaque
     different-head applications of type `Unit`, `PUnit.{2}`, a field-less
     `structure` and a one-constructor `inductive`, all of which take the
     restructured application-failure path.
   - 7 controls:
     - `notDefeq`: opaque `fN 1` vs `gN 2` at `Nat`, the
       `instDecidableEqNat 2 2` vs `instDecidableEqNat 1 1` pair, and the
       `ite` instance pair.
     - `defeqReducible`: `"ab"` vs `String.ofList ['a', 'b']`, and `p.1` vs
       `Pt.x p`.
     - `defeqDefault`: `HAdd.hAdd` vs `Add.add` under binders, and
       `decide (1 = 1)` vs `true`.

   The `DefeqTests` pins (20 `#guard`, 5 `#guard_msgs`, 67 `assert*` calls)
   agree: they pass unchanged on 4.35. None of them is a unit-typed
   application pair, so the probe is the evidence for that path.
3. **`Core.Context` was split into `Context.Cold` + hot fields**
   (`Lean/CoreM.lean:216-260`): `fileName`, `fileMap`, `options`,
   `maxHeartbeats`, `cancelTk?`, … now live in the `Context.Cold` parent;
   `currRecDepth`, `ref`, `diag`, `suppressElabErrors` stay on `Context`.
   Dot-access and `{ c with … }` updates still work through `extends`; an
   anonymous-constructor `⟨…⟩` of `Core.Context` would not. Not used here.
4. **APIs on this package's risk list are unchanged on 4.35**:
   `Lean/Meta/FunInfo.lean`, `Lean/Meta/CoeAttr.lean`,
   `Lean/PrettyPrinter/Delaborator/Builtins.lean` and
   `Lean/Widget/InteractiveCode.lean` are byte-identical between the two
   toolchains; `getFunInfoNArgs` (`FunInfo.lean:140`), `getCoeFnInfo?`
   (`CoeAttr.lean:68`) and `MonadRuntimeException.tryCatchRuntimeEx`
   (`CoreM.lean:833`) keep their signatures. `Lean/Widget/UserWidget.lean`
   changed only a warning's spacing ("same hash (JS source code)"), one
   import (`Lean.Language.Lean.Util`) and the
   internal info-tree lookup of the widget-instance request.
5. **Lake writes manifest version `1.3.0`** (`Lake/Load/Manifest.lean:55`:
   adds the optional `copy` path-dependency field; minor, backwards-compatible).
   Expect that line in every 4.35 manifest diff.
6. **The "designed for use with the module system" warning** cannot reach
   this package. It comes from Lake's existing `requiresModuleSystem` check
   (`lake/Lake/Build/Module.lean`, `fetchImportInfo`), which is byte-identical
   in v4.34.0 (lines 404-411) and v4.35.0 (lines 416-423). The check fires
   when a non-`module` file imports a module of *any* package or library that
   sets `requiresModuleSystem := true`. It is not Mathlib-specific; Mathlib
   v4.35.0 is simply the package in this suite that newly sets the option
   (`lakefile.lean:69`). ProofWidgets `df72b022`'s lakefile does not set it,
   and core is not a Lake package of the workspace. This package imports only
   core and ProofWidgets, so neither the build logs nor any `#guard_msgs` pin
   can see the warning. It is a Lake log line, not a Lean message, so
   `#guard_msgs` could not see it anyway.

### Post-audit fixes (2026-10-25)

The adversarial audit passed this package. The clean rebuild was green with 0
warnings, 2 of 3 source mutations were caught, and the counts matched under
the stated method. It raised four minor findings. This pass edited only this
file and `README.md`; no `.lean` file, test or expected output was touched.

| Finding | Fix |
|---|---|
| The `getCoeFnInfo?` branch of `isCoeName` (`ExprXRay/Analyze.lean:28`) is untested. Every tested coercion head (`Nat.cast`, `Int.ofNat`) is also on the hard-coded `knownCoeHeads` whitelist, so mutation M3 (`if false then`) survived. | **Fixed by the gap closure (2026-10-25); no longer a known gap.** New test: a test-local `@[coe] def XRayTestMeters.toNat`, reached through a `Coe` instance and not on `knownCoeHeads`, is asserted `isCoe` and `↑coe`-tagged, and its twin `XRayTestFeet.toNat` without `@[coe]` is asserted not flagged. See *Gap closure*. |
| The census numbers are not what they claim: "17 `#guard_msgs` blocks" includes 2 docstring mentions, `^#guard[^_]` misses bare `#guard` lines, and the `assert*` grep counts the 5 helper `def`s. The README repeated the numbers. | Recounted mechanically on the v4.32.2 original (tag `lean-v4.32.2`), on `qed64-pin-i` and on this tree, with corrected anchored commands and cross-checked by a comment-aware count. The result is 105 `#guard` + 15 `#guard_msgs` + 339 `assert*` calls = 459 in all three trees. *Counts* (with the old method's 95 / 17 / 344 = 456 kept for traceability), *Golden/expected-output changes*, gotcha 2 ("all six `DefeqTests` badge pins") and the README census line were corrected. The inherited 4.34 section got errata for its census, its "17 `#guard_msgs` blocks", and its loop remark: six `assert*` calls sit in three loops, not "three sites", and the 40-iteration loop holds no assertion. |
| Gotcha 2 named only the two new backward options. It did not mention the 4.35 `ExprDefEq.lean` changes that do apply to metavariable-free terms. | Extended from the toolchain source diff with three items. (1) Failed application pairs take a restructured path: `isDefEqAppFallback` runs `isDefEqOnFailure` once instead of twice, and defers a stuck exception until after `isDefEqLateSpecialCases`. (2) `isDefEqNative` is removed, which is moot because `Lean.reduceBool`/`reduceNat` no longer exist. (3) The first-pass `withImplicitConfig` bump only acts when an argument is an unassigned metavariable. The gotcha now says that none of the three changes a `checkDefeq` verdict. A scratch probe of the `checkDefeq` algorithm, run with both toolchains, gives identical verdicts on 15 metavariable-free pairs, 8 of them unit-like application pairs on the restructured path. The audit's evidence for item (1) said 4.34 tried the late special cases only when the two sides were not both applications. That misreads 4.34's `t.isApp <&&> s.isApp <&&> isDefEqApp t s` condition, which falls through to those cases when `isDefEqApp` fails. The probe agrees: the opaque `Unit` pair `fU 1` vs `gU 2` is `defeqReducible` on both toolchains. |
| The shared build lock (`qed64-showcase/scripts/with-browser-lock.sh`) did not serve waiters in FIFO order during the audit. | **Not fixed: outside this package.** The house rules forbid editing anything outside `packages/`, so this is reported to the orchestrator instead. It does not affect this package's results. |

Further corrections made in this pass:

- Gotcha 6 no longer calls the module-system warning Mathlib-only. It names
  Lake's unchanged `requiresModuleSystem` check and Mathlib v4.35.0's new
  `requiresModuleSystem := true`.
- Gotcha 2's second option is at `ExprDefEq.lean:120`, not `:121`.
- The 4.34 section's claim that `diff -r` against the reference is empty got
  an erratum: one `DefeqTests.lean` docstring line was reworded. The README's
  port sentence now says "no Lean code change" instead of "no Lean source
  changes".
- The H1 title now names both ports. The previous port's notes now have their
  own `## Lean v4.32.2 → v4.34.0 (previous port)` heading, in place of the
  `---` rule and italic line, and their subheadings were demoted one level.

### Verification transcript

Both commands ran through the shared build lock in one wrapper invocation
(lane `port435-expr-xray-build-test`; it waited in the FIFO queue behind
other agents' builds first):

```
BROWSER_LOCK_DIR=$HOME/.cache/lean-widgets-build-lock MIN_FREE_GB=10 LOCK_WAIT_S=43200 COOLDOWN_WAIT_S=7200 \
  bash ".../widgets-v4.34/qed64-showcase/scripts/with-browser-lock.sh" port435-expr-xray-build-test \
  bash -c 'cd ".../widgets-v4.34/packages/expr-xray" && lake build; …; lake test; …'
```

```
### lake build
Build completed successfully (25 jobs).
### lake build rc=0
### lake test
✔ [25/33] Built ExprXRayTests.TestUtil (1.9s)
✔ [26/33] Built ExprXRayTests.TypesTests (1.3s)
✔ [27/33] Built ExprXRayTests.WidgetTests (1.4s)
✔ [28/33] Built ExprXRayTests.RenderTests (1.7s)
✔ [29/33] Built ExprXRayTests.AnalyzeTests (1.8s)
✔ [30/33] Built ExprXRayTests.DefeqTests (2.0s)
✔ [31/33] Built ExprXRayTests.EdgeTests (2.0s)
✔ [32/33] Built ExprXRayTests.DiffTests (2.3s)
✔ [33/33] Built ExprXRayTests (632ms)
### lake test rc=0
browser-lock: command exited rc=0
```

Harness first build on 4.35 (`port435/expr-xray.build0.log`): `Build
completed successfully (25 jobs).`, no warnings.

Post-audit verification (2026-10-25), through the shared lock (`BROWSER_LOCK_DIR=$HOME/.cache/lean-widgets-build-lock MIN_FREE_GB=<10|20> LOCK_WAIT_S=43200 COOLDOWN_WAIT_S=7200 bash ".../widgets-v4.34/qed64-showcase/scripts/with-browser-lock.sh" <lane> …`):

1. Lane `port435-fix-expr-xray-buildtest` (`MIN_FREE_GB=10`) ran the gotcha-2 defeq probe
   with both toolchains, then `lake build` (`Build completed successfully (25 jobs).`,
   rc 0) and `lake test` (up to date, rc 0). That first probe run had elaboration errors:
   three probe `opaque`s lacked an `Inhabited` instance. So it was re-run with
   `deriving Inhabited` in lane `port435-fix-expr-xray-tree-scope-probes2`. Both toolchains
   then gave rc 0 and the 15 identical verdicts quoted in gotcha 2. The verdicts printed
   by the first run were the same.
2. Lane `port435-fix-ii-ts-ex-ck-cleanfinal` (`MIN_FREE_GB=20`) first deleted this
   package's own outputs, `.lake/build/{lib/lean,ir}/ExprXRay*`, leaving 0 entries;
   `.lake/packages` was not touched. It then ran `lake build` and `time lake test`. All 16
   own modules (7 library, 9 test) were rebuilt, with 0 warning or error lines:
   ```
   ✔ [24/25] Built ExprXRay (496ms)
   Build completed successfully (25 jobs).
   ### lake build rc=0
   ✔ [32/33] Built ExprXRayTests.DiffTests (2.0s)
   ✔ [33/33] Built ExprXRayTests (491ms)
   real	0m3.400s
   ### lake test rc=0
   browser-lock: command exited rc=0
   ```

Both runs were made after the documentation edits. Any later edit in this pass touched only Markdown files, which are not Lake inputs. `git status` lists no change under this package besides `PORT-NOTES.md`, `README.md` and the three harness files.


### Gap closure: `@[coe]` coverage (2026-10-25)

This pass closes the first audit finding: the `getCoeFnInfo?` branch of
`isCoeName` was untested. It adds tests only. No library file, existing test
or existing expected output changed. `ExprXRay/Analyze.lean` has the same
`shasum` as before the pass (`e2c0001c…`), and `git diff --numstat` on
`ExprXRayTests/AnalyzeTests.lean` reports 95 lines added and 0 deleted.

New section *Coercion detection through `@[coe]` alone* in
`ExprXRayTests/AnalyzeTests.lean`, after the existing coercion tests:

- Fixtures: two test-local structures with the same shape. Each has a
  function to `Nat` and a `Coe` instance built from that function.
  `XRayTestMeters.toNat` carries `@[coe]`. Its twin `XRayTestFeet.toNat` does
  not.
- 2 `#guard` preconditions: neither function is on `knownCoeHeads`, so only
  the `@[coe]` query can flag `XRayTestMeters.toNat`.
- An `#eval` with a fixture sanity check: `getCoeFnInfo?` is `some` for
  Meters and `none` for Feet. It then asserts that `isCoeName` is `true` for
  Meters and `false` for Feet.
- An `#eval` on `((⟨3⟩ : XRayTestMeters) : Nat)`. The elaborator inserts the
  coercion through the `Coe` instance and unfolds it to the `@[coe]` head. The
  test asserts that the app node and its head const are `isCoe` and that the
  coercee is not. A direct `XRayTestMeters.toNat ⟨3⟩` is flagged too.
- A control `#eval` on `((⟨3⟩ : XRayTestFeet) : Nat)`. It takes the same
  `Coe` path but has no `@[coe]`, and the test asserts that no node is
  flagged. This pins the README limitation that user coercions not
  registered with `@[coe]` are not flagged.
- 2 `#guard_msgs` pins of `#xray (text := true)` on `fun m => (m : Nat)`.
  The Meters dump carries `↑coe` on the app and head lines; the Feet dump
  carries no tag.

The census rose by 21, from 459 to 480 (see *Counts*).

Mutation proofs. Each mutation was applied to `ExprXRay/Analyze.lean:28` by
an exact-string replacement of a copy, then `lake build
ExprXRayTests.AnalyzeTests` was run. The file was restored from the copy, and
`shasum`/`cmp` confirmed it byte-identical to the pre-pass copy.

| Mutation | Lane | Result |
|---|---|---|
| M3: `if (← getCoeFnInfo? n).isSome then` → `if false then` (the mutation that survived the audit) | `gaps-expr-xray-mutM3` | **Caught.** Build rc 1. `AnalyzeTests.lean:209` `ASSERT FAILED [@[coe]: isCoeName Meters.toNat]`, `:219` `ASSERT FAILED [@[coe]: app node flagged]`, `:253` `#guard_msgs` mismatch (the `↑coe` tags are missing). The two control commands (`:235`, `:264`) still pass, as they should. Restored byte-identical. |
| M3b: `.isSome` → `.isNone` (inverted query; checks that the controls are not vacuous) | `gaps-expr-xray-mutM3b` | **Caught.** Build rc 1. The same 3 catchers fail, plus the controls: `:235` `ASSERT FAILED [@[coe] control: app node not flagged]` and `:264` `#guard_msgs` mismatch (`↑coe` on every Feet line). The pre-existing `:152` and `:161` negatives also fail. Restored byte-identical. |

Verification, through the shared lock (`MIN_FREE_GB=10`):

1. Lane `gaps-expr-xray-iter1`: `lake build ExprXRayTests.AnalyzeTests`
   succeeded on the first try (26 jobs, rc 0, 0 warnings).
2. Lane `gaps-expr-xray-final`, after both restores: `lake build` rebuilt the
   7 library modules (`Build completed successfully (25 jobs).`, rc 0).
   `lake test` gave rc 0.
3. Lane `gaps-expr-xray-cleantest`: this package's test outputs
   (`.lake/build/{lib/lean,ir}/ExprXRayTests*`) were deleted, leaving 0
   entries, and then `lake test` was run. All 9 test modules were rebuilt,
   with 0 warning lines:
   ```
   ✔ [25/33] Built ExprXRayTests.TestUtil (532ms)
   ✔ [26/33] Built ExprXRayTests.TypesTests (1.1s)
   ✔ [27/33] Built ExprXRayTests.WidgetTests (1.2s)
   ✔ [28/33] Built ExprXRayTests.RenderTests (1.5s)
   ✔ [29/33] Built ExprXRayTests.AnalyzeTests (1.6s)
   ✔ [30/33] Built ExprXRayTests.DefeqTests (1.8s)
   ✔ [31/33] Built ExprXRayTests.EdgeTests (1.8s)
   ✔ [32/33] Built ExprXRayTests.DiffTests (2.0s)
   ✔ [33/33] Built ExprXRayTests (475ms)
   ### lake test rc=0
   ```

After this pass, `git status` lists these changed files under this package:
`ExprXRayTests/AnalyzeTests.lean`, `PORT-NOTES.md`, `README.md` and the
three harness files.

## Lean v4.32.2 → v4.34.0 (previous port)

*The notes below are the previous port. They are unchanged except for the
post-audit errata of 2026-10-25, each marked **Erratum**, and their headings,
which were demoted one level so they sit under this section.*

Reference (read-only): `../../widgets/expr-xray` (Lean `v4.32.2`, ProofWidgets
`6e311e2a844da9b2cc3971187df2fe0066947b93`).
Port: this directory (Lean `v4.34.0`, ProofWidgets
`106ff4fafc74ef4ac99d81dbf3ab399118f497a5`, fresh `lake-manifest.json`).

Result: `lake build` exit 0 and `lake test` exit 0 on a fully clean
`.lake/build` (25 build jobs, 33 test jobs), **zero warnings** (no
deprecation, no linter output) — verified by rebuilding from scratch and
grepping the full log for `warning|error|deprecat|sorry`.

### Changes

| File | What | Why |
|------|------|-----|
| `lean-toolchain` | `leanprover/lean4:v4.32.2` → `leanprover/lean4:v4.34.0` | Done by the harness before this port started (not edited here). |
| `lakefile.toml` | ProofWidgets `rev` `6e311e2a…` → `106ff4fa…` | Done by the harness (ProofWidgets rev that builds on v4.34.0; not edited here). |
| `lake-manifest.json` | regenerated | Done by the harness (`lake update` ran once; never re-run). |
| `README.md` | toolchain/pin sentence updated; test-census sentence added | Documentation only, see "Counts". |
| `PORT-NOTES.md` | this file | New. |

**No Lean source file changed.** `diff -r` of `ExprXRay/`, `ExprXRay.lean`,
`ExprXRayTests/`, `ExprXRayTests.lean` against the reference is empty.

**Erratum:** that diff is not quite empty. The 4.34 port reworded one line of
`ExprXRayTests/DefeqTests.lean`'s module docstring, from "experiment on this
toolchain (v4.32.2)" to "experiment on the v4.32.2 toolchain, re-verified
unchanged on v4.34.0". Shown by `git diff lean-v4.32.2 dc60a94 --
expr-xray/ExprXRayTests/DefeqTests.lean`. No code, test or expected output
changed.

Every
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

### Pin updates

None. All 17 `#guard_msgs` blocks (11 in `WidgetTests.lean`, 6 in
`DefeqTests.lean`), which pin the `#xray (text := true)` / `#xray_diff`
delaborator-derived text dumps and the defeq badges/summary lines, pass
unchanged on v4.34.0. The delaborator output for every pinned term
(`(1 + 1 : Nat)`, `((3 : Nat) : Int)`, the `ite`/`instDecidableEqNat` vs
`Classical.propDecidable` pair, `Sort (max 1 2)` vs `Sort 2`, the mvar
`undetermined` cases, …) is the same in both toolchains, so no old→new
entries exist.

**Erratum:** there are 15 `#guard_msgs` commands (10 in `WidgetTests.lean`,
5 in `DefeqTests.lean`), not 17. The unanchored grep behind "17" also matched
two docstring mentions (`WidgetTests.lean:6`, `DefeqTests.lean:277`). All 15
passed unchanged, so the conclusion holds.

### Deviations

None. No test was deleted, commented out, or weakened; no feature was
dropped; no `sorry`; no global option suppression; no `set_option` of any
kind was added.

### Counts

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

**Erratum:** the method above does not count what it describes. The table
gives its output, 95 / 17 / 344 = 456, which is the same for both trees. The
actual site counts are 105 `#guard`, 15 `#guard_msgs` and 339 `assert*`
calls, 459 in total, also for both trees. The three faults:

- `^#guard[^_]` misses the 10 bare `#guard` lines whose term is on the next
  line.
- The unanchored `#guard_msgs` grep also matched 2 docstring mentions.
- The token grep counted the 5 helper `def`s in `TestUtil.lean` as calls.

The 4.35 section's *Counts* gives the corrected commands and a per-file
breakdown. The loop remark was also wrong. Not three but **six** `assert*`
calls sit inside loops, in three `for m in ms do` loops over a diff's
mismatches:

- `DiffTests.lean:233`, 1 call. The 40-iteration loop at `:228` only builds
  the test term and contains no assertion.
- `DiffTests.lean:328`, 4 calls, inside an `if`.
- `DefeqTests.lean:338`, 1 call.

### 4.34 gotchas worth knowing for QED64

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
