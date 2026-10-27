# lean-widget-kit

One `require` and one `import LeanWidgetKit` for the whole InfoView widget suite. The kit is a meta-package: its
only module, `LeanWidgetKit.lean`, imports the root module of each of the eight packages and defines
`LeanWidgetKit.version`. It adds no code of its own.

| Package | Root module | Commands |
|---|---|---|
| [`interval-inspector`](../interval-inspector/) | `IntervalInspector` | `#interval_inspect`, `interval_inspect?` |
| [`expr-xray`](../expr-xray/) | `ExprXRay` | `#xray`, `#xray_diff` |
| [`simp-lens`](../simp-lens/) | `SimpLens` | `simp_lens` |
| [`graph-scope`](../graph-scope/) | `GraphScope` | `#graph_scope` |
| [`tree-scope`](../tree-scope/) | `TreeScope` | `#tree_scope`, `#tree_evolve` |
| [`hasse-view`](../hasse-view/) | `HasseView` | `#hasse` |
| [`dist-lens`](../dist-lens/) | `DistLens` | `#dist`, `#dist_film`, `#chain`, `pmf_num`, `ennreal_num` |
| [`chart-kit`](../chart-kit/) | `ChartKit` | `#chart` |

## Use

```toml
[[require]]
name = "lean-widget-kit"
path = "path/to/lean-widgets/packages/lean-widget-kit"
```

```lean
import LeanWidgetKit
```

The kit path-requires its eight siblings (`../<package>`), so it needs the repository's `packages/` layout. Each
package's own README documents its commands and limitations.

## Build and test

```bash
lake exe cache get   # once: fetches the Mathlib build cache
lake build
```

The kit has no test driver and no assertions of its own: the tests live in the eight packages. `../../test-all.sh`
builds and tests all eight packages and then builds the kit.

## Versions

Pinned to `leanprover/lean4:v4.35.0`. Mathlib `v4.35.0` (`56a00585`), ProofWidgets `df72b022` (the rev in Mathlib
v4.35.0's manifest) and Batteries `66e46918` come in through the packages; the kit's `lake-manifest.json` records
them (every rev equals Mathlib v4.35.0's own manifest). Ported from `v4.34.0` (itself ported from the `v4.32.2`
original) with no code change (the 4.35 port corrected one docstring pointer); see [`PORT-NOTES.md`](PORT-NOTES.md).
The packages' own 4.35 changes are in their `PORT-NOTES.md`. The one that forces a change in user files comes from
dist-lens: the uniform distributions are now
`DistLens.uniformOfFintype` / `DistLens.uniformOfFinset`, because Mathlib v4.35.0 removed `PMF.uniformOfFinset`
and made `PMF.uniformOfFintype` a deprecated alias of a Measure-valued definition (see dist-lens's README).

## License

Apache-2.0 ([LICENSE](LICENSE)).
