#!/bin/bash
# Build the showcase site: regenerate panel dumps (when probes are present and
# packages are built), then assemble site/index.html + site/verify.html.
# Usage: ./build.sh [--no-dump]   (run from anywhere)
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" != "--no-dump" ] && [ -n "$(ls probes/*.lean 2>/dev/null)" ]; then
  echo "── regenerating panel dumps from probes ──"
  for probe in probes/*.lean; do
    pkg=$(basename "$probe" .lean)
    if [ -d "../$pkg" ]; then
      echo "  $pkg"
      (cd "../$pkg" && lake env lean "../showcase/$probe")
    else
      echo "  skipping $probe (no ../$pkg)"; 
    fi
  done
else
  echo "── using committed dumps (no probes or --no-dump) ──"
fi

python3 assemble.py
echo "── site/ ready: index.html (gallery) + verify.html (strict harness) ──"
