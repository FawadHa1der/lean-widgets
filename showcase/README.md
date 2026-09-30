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

`.github/workflows/pages.yml` (one directory up) builds + tests the whole
suite, regenerates the dumps, assembles the site, and deploys `showcase/site`
to GitHub Pages on every push to `main`. Enable it with repo Settings → Pages
→ Source = "GitHub Actions". The pipeline fails if any package's tests fail —
the showcase only deploys from a fully green suite.
