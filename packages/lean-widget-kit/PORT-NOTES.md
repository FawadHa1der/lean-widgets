# Port notes — lean-widget-kit (lib `LeanWidgetKit`): Lean v4.32.2 → v4.34.0 → v4.35.0

The kit is a meta-package: `lakefile.toml` path-requires the eight widget packages (`../<package>`), and its only
module, `LeanWidgetKit.lean`, imports their root modules and defines `LeanWidgetKit.version`. It has no test driver
and no assertions of its own, so a port of the kit is its pins plus `lake build`; the eight packages carry the tests
and their own `PORT-NOTES.md`. This file did not exist before the 4.35 port; the 4.34 section below is reconstructed
from git.

## Lean 4.34.0 → 4.35.0 (2026-10-26)

Result: `lake build` exits 0 on `leanprover/lean4:v4.35.0` (3245 jobs), a scratch smoke file that runs one command
from each of the eight packages through `import LeanWidgetKit` compiles, and `../../test-all.sh` is GREEN for all
nine projects (see *Verification*). No code change was needed: the eight packages' ports made their root modules
build, and `LeanWidgetKit.lean` only imports them.

### Pins (set by the port harness; not edited here)

| File | 4.34.0 (`qed64-pin-i`, `4d93a28`) | 4.35.0 |
|---|---|---|
| `lean-toolchain` | `leanprover/lean4:v4.34.0` | `leanprover/lean4:v4.35.0` |
| `lakefile.toml` | eight path requires | unchanged (the kit names no Mathlib or ProofWidgets rev of its own) |
| `lake-manifest.json` | format `1.2.0`; ProofWidgets `106ff4fa`, Mathlib `5ed29652` (`v4.34.0`) | format `1.3.0` (each path entry gains `"copy": false`); ProofWidgets `df72b022`, Mathlib `56a00585` (`v4.35.0`), plausible `dfa4f381`, LeanSearchClient `d6b4c7be`, importGraph `a41f0e9a`, Aesop `4a174c49`, Qq `dce0ad79`, Batteries `66e46918`, Cli `c24fe607` |

Every git entry of the kit's manifest is `inherited` and equals the rev in Mathlib v4.35.0's own manifest
(`.lake/packages/mathlib/lake-manifest.json`), and the checkouts under `.lake/packages/` are at those revs (checked
with a script comparing the two manifests and `git rev-parse HEAD` in each checkout).

### Changes

| File | What | Why |
|---|---|---|
| `LeanWidgetKit.lean` | module docstring: "see the suite README one directory up" → "two directories up (the repository root)" | stale since the packages moved into `packages/` (commit `90e415c`); one directory up is `packages/`, which has no README. Docstring only. |
| `README.md` (new) | what the kit is, the eight root modules and their commands, how to require it, build/test, Versions | the kit had no README |
| `PORT-NOTES.md` (new) | this file | |

### Golden / expected-output changes

None: the kit has no tests.

### Counts

The kit has no assertions (no `#guard`, `#guard_msgs` or test driver). The suite's census is the sum of the eight
packages' censuses, recounted mechanically with each package's current counting method: 3,692 on the 4.34.0 tree,
3,916 on this tree (per package in the repository README's port summary). The 4.34.0 package READMEs' own figures
add up to 3,677: expr-xray's README said 456 (the old grep) and dist-lens's said 345 (counted before
`StackGuardTests` landed); see the note under that table.

### 4.35 gotchas (for the kit)

1. **The module-system warning is replayed for every package.** Lake prints "imports X from package mathlib,
   which is designed for use with the module system; consider adding `module`" for each Mathlib module imported
   by a non-module package file, and `lake build` in the kit replays those warnings from the packages' build logs
   (39 such lines, from 17 files, in the kit's build). `LeanWidgetKit.lean` imports only package modules, so it adds
   none. Expected; left alone, as in the packages.
2. **dist-lens's uniform constructors moved.** Through `import LeanWidgetKit`, the uniform distributions are
   `DistLens.uniformOfFintype` / `DistLens.uniformOfFinset`. Mathlib's `Mathlib.Probability.Distributions.Uniform`
   (where `PMF.uniformOfFintype` is now a deprecated alias of a Measure-valued definition) is not in the kit's import
   closure, so `PMF.uniformOfFintype` is not even declared there (checked by the smoke file below). A user file that
   also imports that module and opens `PMF DistLens` gets the ambiguity described in dist-lens's gotcha 2.

### Verification

Every run went through the shared build lock (`BROWSER_LOCK_DIR=$HOME/.cache/lean-widgets-build-lock`,
`LOCK_WAIT_S=43200 COOLDOWN_WAIT_S=7200`, stdin from `/dev/null`).

1. `fix2-lean-widget-kit-build` (`MIN_FREE_GB=10`), before the docstring edit: `lake build` →
   `✔ [3244/3245] Built LeanWidgetKit (14s)`, `Build completed successfully (3245 jobs).`, rc 0. The only warnings
   are the 39 replayed module-system lines (gotcha 1).
2. `fix2-lean-widget-kit-smoke` (`MIN_FREE_GB=10`), after the docstring edit: `lake build` rebuilt the kit
   (`✔ [3244/3245] Built LeanWidgetKit (9.5s)`, 3245 jobs, rc 0). Then `lake env lean` ran a scratch smoke file
   (outside the package, not committed) with rc 0 and no `error:` line. The file had one `import LeanWidgetKit`, then
   `#guard LeanWidgetKit.version = "0.1.0"`, then one command from each package: `#interval_inspect`, `#xray`,
   `simp_lens` (which printed its `Try this: [apply] simp only [zero_add]`), `#graph_scope (pathGraph 5)`,
   `#tree_scope`, `#hasse (Finset (Fin 3))`, and `#dist` plus `pmf_num` on a die written as bare `uniformOfFintype`
   under `open PMF DistLens`. It ended with a `run_cmd` that checks the die's head is `DistLens.uniformOfFintype` and
   that `PMF.uniformOfFintype` is not declared, and with `#chart (text := true)`.
3. `../../test-all.sh` under one lock hold at `MIN_FREE_GB=20`, the floor at the time; the user has since set the
   ClickE2E floor to 16. Attempts `fix2-suite-test-all` to `-5` never started: the lock's cooldown gave up after
   7200 s each (wrapper exit 76) with only 8–16 GiB reclaimable, because other processes on the host held the
   memory. Attempt `fix2-suite-test-all-6` passed cooldown at 2026-10-27T08:43:34Z (20.3 GiB) and finished in 3 min
   7 s with `test-all rc=0`:

   ```
   ── widget suite ──────────────────
     interval-inspector: GREEN (6s)
     expr-xray: GREEN (0s)
     simp-lens: GREEN (1s)
     graph-scope: GREEN (28s)
     tree-scope: GREEN (2s)
     hasse-view: GREEN (3s)
     dist-lens: GREEN (144s)
     chart-kit: GREEN (1s)
     lean-widget-kit: GREEN (2s)
   ──────────────────────────────────
   ```

   `test-all.sh` runs an incremental `lake build` and `lake test` in each package. The short times mean those
   packages' outputs were already up to date from the packages' own final runs and were replayed, not rebuilt.

## Lean 4.32.2 → 4.34.0 (commit `dc60a94`; reconstructed from git)

`git diff lean-v4.32.2:lean-widget-kit qed64-pin-i:packages/lean-widget-kit` (the kit moved from the repository root
into `packages/` in between): `LeanWidgetKit.lean` and `lakefile.toml` byte-identical; `lean-toolchain`
`v4.32.2` → `v4.34.0`; `lake-manifest.json` revs moved to Mathlib v4.34.0's manifest (Mathlib `5ed29652`,
ProofWidgets `106ff4fa`). No source change.
