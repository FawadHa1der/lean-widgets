# lean/native — inputs of the native widget build (scripts/build-native.sh)

* `delta-phase1.txt` — the 38 Mathlib modules the seven phase-1 widget libraries import that the kernel build's Mathlib
  tree did not hold as native64 oleans (`build-native.sh delta` compiles them). `delta-phase2.txt` — the 402 more that
  DistLens + LeanWidgetKit need (compiled by `build-native.sh distlens` through Lake's dependency resolution; recorded
  for reference). Both are outputs of `scripts/delta.py --clone $W/mathlib4 --widgets $W/widgets-src --core
  $QED64_KERNEL_BUILD/native/stage1/lib/lean` for Mathlib `5ed2965` and the widget sources of the lock's
  WIDGETS_COMMIT (docs/STAGE-A-RESULTS.md); they were kept in the machine-local `out/` until 2026-10-04.
