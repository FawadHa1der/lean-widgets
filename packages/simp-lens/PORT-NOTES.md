# Port notes — simp-lens: Lean v4.32.2 → v4.34.0 → v4.35.0 (QED64 pairing)

## Lean 4.34.0 → 4.35.0 (2026-10-25)

Result: **`lake build` exit 0 (22 jobs) and `lake test` exit 0 (32 jobs,
incl. `SimpLensTests.ClickE2E`, 35 s) on `leanprover/lean4:v4.35.0`**, with
**zero warnings** in both logs (no deprecation, no linter output, no replayed
warnings). **The port itself changed no Lean source file**; the post-audit
passes (see "Post-audit fixes" and "Re-audit fix" below) changed no library
file and only added tests (`SimpLensTests/Helpers.lean`,
`SimpLensTests/TraceTests.lean`). Every
SimpLens and SimpLensTests module was recompiled by 4.35.0 (the toolchain
change invalidates every build
trace: the harness's first `lake build` compiled the 8 library modules incl.
`SimpLens.Demo`; the `lake test` below compiled all 11 test-library modules,
whose `#e2e_*` commands re-elaborate their user files in-process on 4.35).

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
| `README.md` | "Built for" sentence → v4.35.0 / `df72b022`; port-history clause extended. | Task requirement. |
| `PORT-NOTES.md` | This section. | Task requirement. |

After the port, `git diff qed64-pin-i -- packages/simp-lens` listed only the
five files above; the post-audit passes add `SimpLensTests/Helpers.lean` and
`SimpLensTests/TraceTests.lean` (tests only, see "Post-audit fixes" and
"Re-audit fix"). The 4.34
port's `assert` → `assertThat` rename and its `[apply] simp` hint pins stay as
they are (still correct on 4.35, see gotchas 2-3).

### Golden/expected-output changes

**None.** All 85 `#guard_msgs` pins (including the three
`linter.unusedSimpArgs` `[apply] simp` hint pins the 4.34 port introduced, all
`Try this:` suggestions with their core line-wrapping, the no-progress errors,
the unsolved-goals reports and the tight-`maxHeartbeats` twins), the 106
`#guard`s, the 202 `#lens_*` / `#lens_at_*` pins and the 11 `#e2e_*`
click-harness commands (pinned insertion text, recompile with zero messages /
pinned error, leftover-token and negative-control checks) pass unmodified.
The post-audit pass added 22 new `#lens_*` / `#lens_at_*` pins and one new
command kind (`#lens_origins`), and the re-audit fix added 2 more
`#lens_origins` pins; neither changed an existing expected output.

### Deviations

**None.** No test deleted, commented out, skipped or weakened; no `sorry`; no
`set_option` added (the existing scoped `set_option maxHeartbeats … in` of the
heartbeat twins are unchanged test inputs); no feature dropped. The
pre-existing `@[implemented_by]` wrapper around `enableInitializersExecution`
in `ClickE2E.lean` (from before the 4.34 port) is untouched.

### Counts

Same census as the 4.34 section below / the README (lines starting with an
assertion command across `SimpLens/`, `SimpLensTests/`, `SimpLens.lean`,
`SimpLensTests.lean`):

```
grep -rhoE "^#[a-z_0-9]+" SimpLens SimpLensTests SimpLens.lean SimpLensTests.lean | sort | uniq -c
```

"Before" was run on a `git archive qed64-pin-i packages/simp-lens` export. After
the port, the per-kind `uniq -c` output was identical to it line for line
(`diff` empty). The post-audit column was re-counted with the same command on
the tree that pass left; its `diff` against "before" shows only the 22 added `#lens_*` /
`#lens_at_*` lines (`#lens_steps` +1, `#lens_used` +1, `#lens_step` +4,
`#lens_origins` +3 (new kind), `#lens_phases` +1, `#lens_depths` +1,
`#lens_closes` +1, `#lens_min` +1, `#lens_classify` +1, `#lens_chain` +1,
`#lens_equiv` +1, `#lens_at_step` +3, `#lens_at_closes` +1, `#lens_at_chain`
+1, `#lens_at_equiv` +1). The re-audit column was re-counted the same way on
the final tree (2026-10-26). Its `diff` against "before" lists the same lines
except `#lens_origins`, which is +5 (3 from the post-audit pass, 2 from the
re-audit fix), so 24 lines were added in all.

| | before (4.34, `qed64-pin-i`) | after the port (4.35) | after the post-audit fixes | after the re-audit fix |
|---|---|---|---|---|
| `#guard` | 106 | 106 | 106 | 106 |
| `#guard_msgs` | 85 | 85 | 85 | 85 |
| `#lens_*` / `#lens_at_*` | 202 (34 kinds) | 202 (34 kinds) | 224 (35 kinds) | 226 (35 kinds) |
| `#e2e_click` / `#e2e_click_warn` / `#e2e_click_open` / `#e2e_negative` | 8 / 1 / 1 / 1 | 8 / 1 / 1 / 1 | 8 / 1 / 1 / 1 | 8 / 1 / 1 / 1 |
| **Total** | **404** | **404** | **426** | **428** |

The port's first version of this table said "35 kinds" for the 4.34 tree (a
figure copied from the 4.34 table below without re-counting); the census lists
34 distinct `#lens_*` kinds there (`Helpers.lean` has a 35th distinct
`#lens_` string only because the bare prefix `#lens_at_` occurs in a
docstring, as `` `#lens_at_*` ``).

### 4.35 gotchas

1. **Simprocs now stop at the first rewrite per visit.** `Lean/Meta/Tactic/Simp/Simproc.lean`
   (`simprocCore` / `dsimprocCore`): on 4.34 a `.continue (some r)` result
   from one simproc kept trying the remaining candidates on the rewritten
   term and chained the proofs (`mkEqTrans?`); on 4.35 `.visit`, `.done` and
   `.continue (some r)` all return immediately ("the simplifier looks up
   candidates afresh when it revisits the rewritten expression"). A tracer
   that wraps `Simp.Methods` (as `SimpLens/Trace.lean` does) can therefore
   see a chain of simproc rewrites split into separate visits. None of the
   port's existing pinned runs (the `reduceIte` demo, the minimization and
   step pins) moved: no default simproc answers `.continue (some _)` with a
   changed term, so before the post-audit pass the tracer's
   `.continue (some r)` branch was pinned only by the unit `#guard` in
   `FilmTests.lean`. The post-audit section `SimpLensTests.ContinueSome` at
   the end of `TraceTests.lean` now pins this path end to end, with two
   test-only simprocs on the same subterm (see "Post-audit fixes").
2. **Two more non-reserved do-elements** (`Lean/Parser/Do.lean`,
   priority `default+10`, `includeIdent := true`, like 4.34's `assert`):
   `erased x := e` / `erased x ← act` (`doErased`, `doErasedArrow`); and
   `repeat` / `while` / `for` now take optional `invariant …` and
   `decreasing …` clauses, with `while`'s condition parsed
   `withForbiddens #["do", "invariant", "decreasing"]`. So a helper named
   `erased` at the head of a do-line, or an identifier `invariant` /
   `decreasing` inside a `while` condition, no longer parses as before.
   Grepped: this package has neither (the words occur only in docstrings).
   The `assertThat` rename from the 4.34 port remains necessary: `doAssertion`
   is unchanged.
3. **`linter.unusedSimpArgs` is unchanged except an error-text typo fix**
   ("mask size mismatch}:" → "mask size mismatch:", an internal error no
   test reaches), so the 4.34 `[apply] simp` pins hold. Likewise
   `Lean/Elab/Tactic/Simp.lean` only fixes the `` `discharger' `` quote in
   the `dsimp` error; `Simp/Types.lean`, `Simp/Main.lean`, `Simp/Rewrite.lean`,
   `Simp/Diagnostics.lean`, `SimpTheorems.lean`, `Elab/Tactic/Location.lean`,
   `Lean/Meta/Hint.lean` are byte-identical between the toolchains.
4. **`TryThis` gained `isValidTactic`** (`Lean/Meta/Tactic/TryThis.lean`: the
   replay check in the private `mkValidatedTactic` was factored into a new
   non-private `isValidTactic initialState tac expectedType? : TacticM Bool`); the
   `addSuggestion` signature and its rendering are unchanged, so every
   `Try this:` pin holds.
5. **`Core.Context` was split into `Context.Cold` + hot fields**
   (`Lean/CoreM.lean`): `maxHeartbeats`, `options`, `fileName`, `fileMap`,
   `cancelTk?`, … moved into the `Context.Cold` parent structure. The
   `{ c with maxHeartbeats := b }` update in `Exclude.lean:102`
   (`withPreviewBudget`) still elaborates through `extends`, and the preview
   budget tests pass; an anonymous-constructor `⟨…⟩` of `Core.Context`
   would break.
6. **The in-process frontend used by `ClickE2E` is unchanged in substance**:
   `Lean/Parser/Module.lean`, `Lean/Elab/Import.lean`,
   `Lean/ImportingFlag.lean` (`enableInitializersExecution : BaseIO Unit`),
   `Lean/Data/Lsp/Utf16.lean` and the four `Lean/Elab/InfoTree/` files that
   4.34 already had (`Basic`, `InlayHints`, `Main`, `Types`) are
   byte-identical. `Lean/Elab/InfoTree/Util.lean` is **new** in 4.35: it is
   4.34's `Lean/Server/InfoUtils.lean` moved byte for byte (`cmp` clean), and
   the old path is now a `deprecated_module (since := "2026-09-11")` shim
   that re-exports it. `InfoTree.foldInfo`, the only info-tree helper
   `ClickE2E` uses, lives there now; `ClickE2E` reaches it through
   `import SimpLens` (→ `import Lean`), never through the deprecated path,
   so no deprecation warning appears. `Lean/Elab/Frontend.lean` only adds
   code-quality-log bookkeeping to `runFrontend`, which `ClickE2E` does not
   call (it uses `Elab.IO.processCommands`).
7. **ProofWidgets `106ff4fa..df72b022` has zero `.lean` changes** (only
   `lean-toolchain` and CI workflow); and the "designed for use with the
   module system" warning fires only for Mathlib imports, so neither the
   `#guard_msgs` pins nor the `#e2e_*` zero-message checks (user files import
   only `SimpLens`) can pick it up. Lake now writes manifest version `1.3.0`.
8. **Builtin simproc changes** (`Lean/Meta/Tactic/Simp/BuiltinSimprocs/`;
   these change what plain `simp`, and so `simp_lens` and its `simp only`
   suggestions, do on the affected goals):
   - `dreduceIte` / `dreduceDIte` (`Core.lean`) were reimplemented. They
     are the `dsimproc` twins that act only `inDSimp`, i.e. under `dsimp`
     and in simp's own dsimp passes over dependent arguments and instances.
     They now `whnfD` the projection `.proj ``Decidable 0 i` (the `decide`
     field) and match `Bool.true` / `Bool.false` instead of matching
     `Decidable.isTrue` / `Decidable.isFalse` on `whnfD i`; `dreduceDIte`
     now passes `mkExpectedPropHint (.proj ``Decidable 1 i) c` (resp.
     `mkNot c`) as the branch proof. The simp-mode `reduceIte` /
     `reduceDIte` (lines 15-42) are byte-identical to 4.34, so the
     `reduceIte` demo and pins (`TraceTests`, `MinimizeTests`,
     `ExcludeTests`, `TacticTests`) are unaffected; no pinned goal puts an
     `ite`/`dite` in a dependent position.
   - New default `[simp, seval]` dsimprocs: `Nat.reduceLog2`
     (`Nat.log2 _`), `Nat.reducePowMod` (`Nat.powMod _ _ _`),
     `Fin.reducePow` (`_ ^ _ : Fin _`) and `BitVec.reduceOfNatClamp`
     (`BitVec.ofNatClamp _ _`). On a goal with such a literal subterm,
     `simp` now rewrites it and `simp_lens` shows the simproc as a frame
     and lists it in the suggestion. No pinned goal here mentions these
     functions (grepped `SimpLens/` and `SimpLensTests/`).
   - `simprocCore` / `dsimprocCore`: see gotcha 1.

### Post-audit fixes (2026-10-25)

An adversarial audit of this port passed it (clean rebuild green, all three
of its mutations caught) with five minor findings. Each finding and its fix:

1. **Wrong cross-reference.** The Changes section said the `assertThat`
   rename and the `[apply] simp` pins are "still correct on 4.35, see
   gotchas 1-2"; they are gotchas 2 (do-elements) and 3
   (`linter.unusedSimpArgs`). **Fix:** "gotchas 2-3".
2. **"35 kinds" was wrong.** The census lists 34 distinct `#lens_*` /
   `#lens_at_*` kinds on the 4.34 tree (and on the v4.32.2 tag
   `lean-v4.32.2`); 35 was copied from the 4.34 table, which had the same
   error. **Fix:** both tables now say 34 for those trees; the final tree
   has 35 (the new `#lens_origins`, below).
3. **README sentence contradicted itself.** "The v4.34.0 → v4.35.0 step
   needed no source or pin changes" sat next to the new ProofWidgets rev.
   **Fix:** it now says the step changed only the toolchain and
   ProofWidgets pins (no library source, no existing test or expected
   output), and that a post-audit pass added tests. The README census went
   from 404 to 426.
4. **The gotcha list missed 4.35's builtin simproc changes and over-claimed
   byte-identity of `Lean/Elab/InfoTree/`.** **Fix:** new gotcha 8 lists the
   `dreduceIte` / `dreduceDIte` reimplementation, the four new default
   dsimprocs (`Nat.reduceLog2`, `Nat.reducePowMod`, `Fin.reducePow`,
   `BitVec.reduceOfNatClamp`) and points at gotcha 1 for `simprocCore`.
   Checking the sources corrected the audit in two places. First, the
   reimplemented simprocs are the dsimp-mode twins `dreduceIte` /
   `dreduceDIte`; the simp-mode `reduceIte` / `reduceDIte` that this
   package's demo and pins use are byte-identical to 4.34. Second, besides
   the two `Nat` dsimprocs the audit named, `Fin.reducePow` and
   `BitVec.reduceOfNatClamp` are new too (`diff -rq` over
   `Lean/Meta/Tactic/Simp/` shows changes only in `BuiltinSimprocs/{BitVec,
   Core,Fin,Nat}.lean` and `Simproc.lean`). Gotcha 6 now says that only the
   four `InfoTree/` files 4.34 had are byte-identical, and that
   `InfoTree/Util.lean` is new: a byte-for-byte move (`cmp` clean) of
   4.34's `Lean/Server/InfoUtils.lean`, which is now a `deprecated_module`
   shim. `ClickE2E`'s `InfoTree.foldInfo` lives there now and is reached
   through `import Lean`.
5. **No end-to-end test exercised a traced `Step.continue (some _)`
   result.** That is the path whose semantics changed in 4.35 (gotcha 1). With
   the audit's mutation M2 (`stepResultExpr?` answering `none` for
   `.continue (some r)`) only the unit `#guard` at `FilmTests.lean:59`
   failed. **Fix, tests only (no package behaviour change):**
   - `SimpLensTests/Helpers.lean`: a new command `#lens_origins t at i =>
     [n1, …]` asserts *all* origins recorded for frame `i`, in order (the
     existing commands pin only the principal one).
   - `SimpLensTests/TraceTests.lean`: a new section
     `SimpLensTests.ContinueSome` (the last in the file, so no earlier run
     sees its simprocs). Its fixture is a constant function
     `lensZ (_ : Nat) : Nat := 0` and two test-only post simprocs keyed on
     the same pattern `lensZ _`: `lensZdec` answers
     `.continue (some (lensZ k))` on `lensZ (k+1)`, and `lensZzero` answers
     `.done 0` on `lensZ 0`. Both rewrite by `rfl` (`proof? := none`). On
     `lensZ 2 = 0` it pins the frame count (4), each frame's principal and
     before/after (`lensZ 2 ~> lensZ 1`, `lensZ 1 ~> lensZ 0` by `lensZdec`,
     `lensZ 0 ~> 0` by `lensZzero`, `0 = 0 ~> True` by `eq_self`), one
     origin per simproc frame (`#lens_origins`), phases, depths, the used
     list, the classification, the minimal call
     `simp only [lensZdec, lensZzero]`, chain invariants and `#lens_equiv`
     (traced = plain `simp`, and the minimal call replays it). It also pins
     the same three frames through the location engine (`at h`, where
     `h : lensZ 2 = 1` closes the goal), with `#lens_at_closes`,
     `#lens_at_chain` and `#lens_at_equiv`. That makes 22 new pins.
   From the 4.34 source, 4.34's `simprocCore` would have run `lensZzero` on
   `lensZ 0` inside the second `lensZdec` call: one merged
   `lensZ 1 ~> 0` frame with origins `[lensZdec, lensZzero]`, and 3 frames
   in all. The 4-frame, one-origin pins therefore also record the 4.35
   behaviour. (That 4.34 outcome is read from the source, assuming
   `lensZdec` is tried first; it was not run.) M2 was re-run on the final
   tree and is now caught by `TraceTests` (see the transcript below).

The H1 title now covers both ports (v4.32.2 → v4.34.0 → v4.35.0). No library
file changed and no existing assertion was touched; the census was
re-counted mechanically.

### Re-audit fix (2026-10-26)

A second adversarial audit passed this package. Four of its five simp-lens
mutations were caught: S1 (origins become cumulative), S2 (the first audit's
M2), S4 (wrong phase) and S5 (reversed origins). It reported one minor
finding:

1. **Side-condition origins were unpinned.** `#lens_origins` is documented
   to assert all of a frame's origins "in recording order (side-condition
   origins first, the principal one last)". But its three uses were all
   single-origin frames in the `ContinueSome` section. The re-audit's
   mutation S3 keeps only the principal origin (in `recordStep`, `origins :=
   fresh.toArray.extract (fresh.size - 1) fresh.size`), and it survived the
   whole `lake test`, `ClickE2E` included. Yet `SimpLens/Render.lean:52`
   shows these origins to the user as "(+N side-condition lemma(s))". S5 was
   caught only through the principal, by two `#lens_principal` pins.
   **Fix, tests only:** two `#lens_origins` pins in
   `SimpLensTests/TraceTests.lean`, each right after the `#lens_principal`
   pin of the same frame:
   - line 43, a simproc frame:
     `#lens_origins ∀ a b : Nat, (if true then a else b) = a at 1 => [eq_self, reduceIte]`.
     `eq_self` fires inside `reduceIte`'s own `simp c` on the condition
     `true = true` (`BuiltinSimprocs/Core.lean:17` in the v4.35.0
     toolchain), so it is recorded before the principal.
   - line 146, a theorem frame:
     `#lens_origins ∀ (n : Nat) (h : 0 < n), n / n = 1 hyps [h] at 0 => [h, Nat.div_self]`.
     `h` discharges `Nat.div_self`'s side condition `0 < n`.

   Both expected lists were first read off an out-of-tree probe
   (`lake env lean` on a scratch file importing `SimpLensTests.Helpers`).
   It printed `[eq_self, reduceIte]` and `[h, Nat.div_self]`, and the
   reversed list `[Nat.div_self, h]` failed there as a negative control.
   S3 and S5 were then re-run on the final tree, and each is now caught by
   both new pins (see the transcript below). The census went from 426 to 428
   (`#lens_origins` 3 → 5). No library file, existing assertion or expected
   output changed. One gap remains: the rendered text "(+N side-condition
   lemma(s))" itself is not pinned, so a mutation confined to
   `Render.lean`'s `sideCount` would still go uncaught.

The 7 inserted lines (4 after line 39, 3 after the old line 139) shift every
later line of `TraceTests.lean` by 7. So the `ContinueSome` line numbers in
the post-audit transcript below (197-222) are 204-229 on the final tree.

### Verification transcript

Both commands ran through the shared build lock in one wrapper invocation
(lane `port435-simp-lens-build-test`; run in the background, after waiting in
the FIFO queue behind other agents' builds):

```
BROWSER_LOCK_DIR=$HOME/.cache/lean-widgets-build-lock MIN_FREE_GB=10 LOCK_WAIT_S=43200 COOLDOWN_WAIT_S=7200 \
  bash ".../widgets-v4.34/qed64-showcase/scripts/with-browser-lock.sh" port435-simp-lens-build-test \
  bash -c 'cd ".../widgets-v4.34/packages/simp-lens" && lake build; …; lake test; …'
```

```
### lake build
Build completed successfully (22 jobs).
### lake build rc=0
### lake test
✔ [22/32] Built SimpLensTests.TacticTests (961ms)
✔ [23/32] Built SimpLensTests.Helpers (1.9s)
✔ [24/32] Built SimpLensTests.MinimizeTests (1.4s)
✔ [25/32] Built SimpLensTests.EquivTests (1.4s)
✔ [26/32] Built SimpLensTests.ExcludeTests (1.4s)
✔ [27/32] Built SimpLensTests.ContractTests (1.4s)
✔ [28/32] Built SimpLensTests.TraceTests (1.5s)
✔ [29/32] Built SimpLensTests.FilmTests (1.6s)
✔ [30/32] Built SimpLensTests.LocationTests (1.7s)
✔ [31/32] Built SimpLensTests.ClickE2E (35s)
✔ [32/32] Built SimpLensTests (581ms)
### lake test rc=0
browser-lock: command exited rc=0
```

Harness first build on 4.35 (`port435/simp-lens.build0.log`): `Build
completed successfully (22 jobs).`, no warnings.

Post-audit runs (2026-10-25), each under the same lock prefix
(`MIN_FREE_GB=10`, stdin from `/dev/null`):

```
# port435-fix-simp-lens-buildtest: lake build; lake test (new #lens_origins + ContinueSome pins)
Build completed successfully (22 jobs).
### lake build rc=0
✔ [24/32] Built SimpLensTests.Helpers (1.6s)
✔ [25/32] Built SimpLensTests.TraceTests (1.2s)
✔ [32/32] Built SimpLensTests (572ms)
### lake test rc=0
# port435-fix-simp-lens-mutM2-final: the audit's M2 re-run, then restore and rebuild
136:  | .continue (some _) => none
### M2: lake build SimpLensTests.TraceTests (expect FAIL)
error: SimpLensTests/TraceTests.lean:197:0: assertion failed: filmstrip length
  actual:   2
  expected: 4
error: SimpLensTests/TraceTests.lean:199:0: assertion failed: frame 0 principal
  actual:   SimpLensTests.ContinueSome.lensZzero
  expected: SimpLensTests.ContinueSome.lensZdec
  … (13 errors in all: lines 197, 199-202, 204-208, 218, 220, 222 —
     #lens_steps, #lens_step ×4, #lens_origins ×3, #lens_phases,
     #lens_depths, #lens_at_step ×3)
error: SimpLensTests/TraceTests.lean:220:0: assertion failed: frame 1 of h principal
  actual:   Nat.zero_ne_one
  expected: SimpLensTests.ContinueSome.lensZdec
error: build failed
### M2 rc=1
### restored byte-identical            (cmp against the saved copy)
Build completed successfully (22 jobs).
### lake build rc=0
✔ [31/32] Built SimpLensTests.TraceTests (693ms)
### lake test rc=0
# FINAL — port435-fix-simp-lens-cleanfinal: rm -rf .lake/build/{lib/lean,ir}/SimpLens* (own modules only), lake build, lake test
✔ [21/22] Built SimpLens (498ms)
Build completed successfully (22 jobs).
### lake build rc=0
✔ [28/32] Built SimpLensTests.TraceTests (1.3s)
✔ [29/32] Built SimpLensTests.FilmTests (1.4s)
✔ [30/32] Built SimpLensTests.LocationTests (1.4s)
✔ [31/32] Built SimpLensTests.ClickE2E (30s)
✔ [32/32] Built SimpLensTests (533ms)
### lake test rc=0
browser-lock: command exited rc=0
```

Under M2, only `#lens_used`, `#lens_closes`, `#lens_min`, `#lens_classify`,
`#lens_chain`, `#lens_equiv` and the `#lens_at_closes` / `#lens_at_chain` /
`#lens_at_equiv` pins of the new section still pass. That is expected:
dropping frames changes neither `usedTheorems` nor the landing goal. The
frame-level pins are the ones that catch it. In the final clean run all 8
library and 11 test modules (ClickE2E included) were rebuilt, with 0
`warning` and 0 `error` lines in either log.

Re-audit fix runs (2026-10-26), under the same lock prefix (`MIN_FREE_GB=10`,
stdin from `/dev/null`, in the background):

```
# fix2-simp-lens-probe: lake env lean <scratch OriginsProbe.lean>  (expect rc=1: deliberate wrong lists)
  (lines condensed: probe errors shown as "frame i origins  actual: …")
  [h, Nat.div_self] at 0 and [eq_self] at 1 of the div_self run: pass
  frame 0 origins  actual: [eq_self]             (reduceIte run)
  frame 1 origins  actual: [eq_self, reduceIte]  (reduceIte run)
  frame 2 origins  actual: [eq_self]             (reduceIte run)
  frame 0 origins  actual: [h, Nat.div_self]  expected: [Nat.div_self, h]   (negative control)
### probe rc=1
# fix2-simp-lens-test-mutate: lake test; S3 and S5 (each restored); clean rebuild
### lake test rc=0
✔ [31/32] Built SimpLensTests.TraceTests (611ms)
### S3 applied:
154:  ref.modify (·.push { origins := fresh.toArray.extract (fresh.size - 1) fresh.size, before, after, phase, depth })
### S3: lake build SimpLensTests.TraceTests (expect FAIL)
### S3 rc=1
error: SimpLensTests/TraceTests.lean:43:0: assertion failed: frame 1 origins
  actual:   [reduceIte]
  expected: [eq_self, reduceIte]
error: SimpLensTests/TraceTests.lean:146:0: assertion failed: frame 0 origins
  actual:   [Nat.div_self]
  expected: [h, Nat.div_self]
### S3 restored byte-identical
### S5 applied:
154:  ref.modify (·.push { origins := fresh.toArray.reverse, before, after, phase, depth })
### S5: lake build SimpLensTests.TraceTests (expect FAIL)
### S5 rc=1                                (its 4 errors, one line each)
error: SimpLensTests/TraceTests.lean:39:0:  frame 1 principal  actual: eq_self  expected: reduceIte
error: SimpLensTests/TraceTests.lean:43:0:  frame 1 origins    actual: [reduceIte, eq_self]
error: SimpLensTests/TraceTests.lean:143:0: frame 0 principal  actual: h        expected: Nat.div_self
error: SimpLensTests/TraceTests.lean:146:0: frame 0 origins    actual: [Nat.div_self, h]
### S5 restored byte-identical
fce8dbde7325de719e7f3266bd082f60d8ab4256  SimpLens/Trace.lean   (= the saved copy)
# FINAL: rm -rf .lake/build/{lib/lean,ir}/SimpLens* (own modules only), lake build, lake test
✔ [21/22] Built SimpLens (468ms)
Build completed successfully (22 jobs).
### lake build rc=0
✔ [28/32] Built SimpLensTests.TraceTests (1.3s)
✔ [31/32] Built SimpLensTests.ClickE2E (29s)
✔ [32/32] Built SimpLensTests (500ms)
### lake test rc=0
browser-lock: released (fix2-simp-lens-test-mutate)
```

The wrapper reported `command exited rc=1` for this job. That code came from
its last line, a `grep -c error` that found 0 matches (`grep` exits 1 when it
counts zero). Every `lake` step above has the rc shown. In the final logs all
8 library and 11 test modules were rebuilt, with 0 `warning` and 0 `error`
lines.

---

*The notes below are the previous port (Lean v4.32.2 → v4.34.0), unchanged
except one figure: its Counts table said "35 kinds", and the 4.35 post-audit
pass corrected that to the 34 distinct kinds the census lists.*

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
| `#lens_*` / `#lens_at_*` (34 kinds) | 202 | 202 |
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
