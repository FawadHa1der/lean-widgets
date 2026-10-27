# Widget-suite showcase

A static site presenting every widget package with its **real panels** — the
exact `Html` trees the Lean InfoView receives, rendered through the same React
conversion the InfoView uses.

* `site/index.html` — the public gallery (production React).
* `site/verify.html` — the strict verification build (development React): any
  React error **or warning** on any panel fails the page; the title reports the
  verdict and a table lists every panel.

## Building

```bash
./build.sh            # regenerate dumps from probes/ (needs built packages), then assemble
./build.sh --no-dump  # assemble from the committed dumps only (no Lean needed)
```

`probes/<pkg>.lean` files are headless dump scripts run with `lake env lean`
from each package directory; they serialize the contract-test-covered panel
outputs into `dumps/<pkg>.json`. The committed dumps let the site build
without a Lean toolchain (e.g. for quick previews); CI always regenerates.

### Lean v4.35.0 (2026-10-26)

The packages moved to Lean v4.35.0 / Mathlib v4.35.0 (`56a00585`) / ProofWidgets `df72b022`. All eight probes were
re-run on that tree (`lake env lean ../../showcase/probes/<pkg>.lean` from each package directory, exit 0, no
warnings), once before and once after the final green `test-all.sh` (2026-10-27), and every regenerated dump is
**byte-identical** to the committed v4.34.0 dump (`git diff --stat
showcase/dumps` empty; same SHA-1 for all eight files). `python3 assemble.py` then rewrote `site/` with only the footer's toolchain changed (below),
and `node verify.mjs` reports 60/60 panels clean. No probe needed a change:

* `probes/dist-lens.lean` still writes `uniformOfFintype (Fin 6)` under `open … DistLens … PMF`. Mathlib v4.35.0
  removed `PMF.uniformOfFinset` and made `PMF.uniformOfFintype` a deprecated alias of a Measure-valued definition
  in `Mathlib.Probability.Distributions.Uniform`, and dist-lens now ships `DistLens.uniformOfFintype` instead
  (dist-lens `PORT-NOTES.md`, "What broke, and why" and "Changes"). The probe imports only `DistLens` and
  `DistLensTests.Helpers`, neither of which imports that Mathlib module, so the bare name resolves to
  `DistLens.uniformOfFintype` alone, and the panel (weights, CDF, moments, the `unfold die; pmf_num` suggestions)
  is unchanged.
* The other 4.35 changes do not reach the dumped panels. graph-scope's library changes (graph-scope
  `PORT-NOTES.md`, "Post-audit fixes" rounds 1 and 2) are in `Gate.lean` and `Insert.lean`'s link gating, which
  decides which links `#graph_scope` offers; the probe's two interactive entries render the hand-written `LinkInfo`
  fixtures of `GraphScopeTests/InsertTests.lean` (`path3Links`, the gate-failure links), which do not go through
  that gating, and the text builders (`edgeExampleText`, `degreeExampleText`, `connectedExampleText`) and the render
  layer are unchanged. hasse-view's library changed docstrings only (its `PORT-NOTES.md`, "Changes"; the post-audit pass added a
  test section to `HasseViewTests/LinkTests.lean`, which the probe does not import), and the remaining packages
  changed tests and documentation only.

The site footer's "Lean toolchain …" used to be a hard-coded string in `assemble.py` and still said v4.34.0.
`assemble.py` now reads it from the packages' `lean-toolchain` files (and stops if they disagree), so
`site/index.html` and `site/verify.html` differ from their 4.34 versions in the footer line only.

## Headless verification (the CI gate)

```bash
node verify.mjs   # exit 1 on ANY React error/warning on ANY panel
```

Runs every dumped panel through React 18 development server-rendering in Node
(no browser, no npm — the vendored UMD builds are loaded in a vm sandbox), with
the same dev-mode validation the InfoView's React performs: string style props
throw (error #62), invalid DOM properties warn. This is what CI runs on every
commit; `site/verify.html` is the same check in interactive form.

## Deployment

`.github/workflows/lean-ci.yml` (at the repository root) builds and tests every
package in its own job, regenerates each package's dump from its probe (the
regenerated dumps must be byte-identical to the committed ones), assembles the
site with `build.sh --no-dump` and runs `verify.mjs`. It deploys `showcase/site`
to GitHub Pages only on a push to `main` when the repository variable
`DEPLOY_GITHUB_PAGES` is `true` and Settings → Pages → Source is "GitHub
Actions"; without those two settings the `pages` job is skipped. The pipeline
fails if any package's tests fail — the showcase only deploys from a fully
green suite.
