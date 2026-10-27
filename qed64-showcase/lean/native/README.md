# lean/native — inputs of the native widget build (scripts/build-native.sh)

* `delta-phase1.txt` — the 38 modules (37 Mathlib ones and ProofWidgets' `SelectionPanel`) the seven phase-1 widget
  libraries import that the kernel build's Mathlib tree did not hold as native64 oleans (`build-native.sh delta`
  compiles them). `delta-phase2.txt` — the 404 more (all Mathlib) that DistLens + LeanWidgetKit need (compiled by
  `build-native.sh distlens` through Lake's dependency resolution; recorded for reference). Both are outputs of
  `scripts/delta.py --clone $W/mathlib4.56a00585 --widgets $W/widgets-src --core
  $W/kernel-build-native64-v4.35/native/stage1/lib/lean` (phase 2 adds `--roots DistLens,LeanWidgetKit --base-roots`
  with the seven phase-1 libraries and is that run's `increment.depToCompile`), regenerated 2026-10-27 for pin
  `521cf3f`'s Mathlib `56a00585` and the widget sources of its lock's WIDGETS_COMMIT `1a61003`
  (`$W/widgets-src/SOURCE-COMMIT.txt`); the JSON reports are `$W/logs/delta-phase1-pre.json` and
  `delta-phase2-pre.json`. The versions in git from `5ef6793` (2026-10-04) up to HEAD `1a61003` are the Mathlib
  `5ed2965` lists (38 and 402 modules, computed with `--clone $W/mathlib4`; docs/STAGE-A-RESULTS.md); before that they
  were kept in the machine-local `out/`. `$W/mathlib4` was then the only clone; it is now the legacy one, the
  `MATHLIB_CLONE` of the pins up to `58ebbad` (Mathlib `5ed2965`). A pin with another Mathlib commit has its own clone
  `$W/mathlib4.<first 8 hex of its lock's toolchain.mathlib.commit>` (`node scripts/lib/env.mjs` prints the target
  pin's `MATHLIB_CLONE`); `delta.py` for that commit takes it as `--clone`.
