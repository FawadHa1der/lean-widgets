#!/bin/bash
# install-elan.sh — make `elan`/`lake` available to a CI job. GitHub's ubuntu runners have no elan: download the latest
# elan release for this platform and install it WITHOUT a default toolchain (each package's lean-toolchain selects its
# own) and without editing shell profiles; the bin directory goes to $GITHUB_PATH. On a machine that already has elan
# (a developer machine running ci/run-local.mjs) it only prints the version: nothing is installed or changed.
set -euo pipefail
if command -v elan >/dev/null 2>&1; then echo "elan present: $(elan --version)"; exit 0; fi
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) triple=x86_64-unknown-linux-gnu ;;
  Linux-aarch64) triple=aarch64-unknown-linux-gnu ;;
  Darwin-arm64) triple=aarch64-apple-darwin ;;
  Darwin-x86_64) triple=x86_64-apple-darwin ;;
  *) echo "install-elan: unsupported platform $(uname -s)-$(uname -m)" >&2; exit 2 ;;
esac
tmp=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/elan.XXXXXX")
curl -sSfL "https://github.com/leanprover/elan/releases/latest/download/elan-$triple.tar.gz" | tar xz -C "$tmp"
"$tmp/elan-init" -y --default-toolchain none --no-modify-path
bin="${ELAN_HOME:-$HOME/.elan}/bin"
[ -n "${GITHUB_PATH:-}" ] && echo "$bin" >> "$GITHUB_PATH"
"$bin/elan" --version
