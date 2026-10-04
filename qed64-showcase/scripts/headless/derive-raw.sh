#!/usr/bin/env bash
# Derive raw (uncompressed) stock snapshots for headless controls:
#   $W/raw/init.snap     (122,364,117 bytes)  from the active pin's release .../init.<d16>.snapz
#   $W/raw/mathlib.snap  (1,127,272,685 bytes) from the active pin's release .../mathlib.<d16>.snapz
# ($W/raw is the active link into $W/runtimes/<buildId>/raw: the raw regions are per runtime, scripts/lib/pins.mjs)
# and a provenance sidecar $W/raw/<name>.snap.provenance.json
#   { name, index, snapz, snapzSha256, rawBytes, rawSha256 }
# that ties the raw CONTENT to the served .snapz digest (read by lib.mjs snapProvenance).
#
# Idempotent and safe to race with another lane:
#   - a raw file whose size matches AND whose sha256 equals the sidecar's rawSha256 is left alone;
#   - a raw file whose size matches but has no sidecar (e.g. derived by another lane) is
#     verified by gunzipping the digest-checked .snapz and comparing sha256, then the sidecar
#     is written; a content mismatch is an error (the file is NOT silently replaced);
#   - otherwise it is gunzipped to a unique temp file (hashing the stream) and renamed into
#     place atomically (mv on one filesystem).
# Exit 1 on any digest / size / content mismatch.
#   usage: scripts/headless/derive-raw.sh [init] [mathlib]   (default: both)
set -euo pipefail
SC="$(cd "$(dirname "$0")/../.." && pwd)"
. "$SC/scripts/lib/env.sh"   # W: scripts/lib/env.sh
R="$(node "$SC/scripts/lib/pins.mjs" release)/public/snapshots"   # the target pin's stock snapshots (SHOWCASE_PIN, else active)
RAW="$(node "$SC/scripts/lib/pins.mjs" store raw)"                 # its runtime's raw store ($W/raw, the active link, or $W/runtimes/<bid>/raw)
mkdir -p "$RAW"
names=("$@"); [ ${#names[@]} -eq 0 ] && names=(init mathlib)
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
for n in "${names[@]}"; do
  read -r url digest bytes < <(node -e '
    const ix = require(process.argv[1]); const e = ix.snapshots.find((s) => s.name === process.argv[2]);
    if (!e) process.exit(3); console.log(e.url.split("/").pop(), e.digest.replace("sha256:", ""), e.bytes);' "$R/index.json" "$n")
  out="$RAW/$n.snap"; side="$out.provenance.json"
  writeside() { # $1 = raw sha256
    node -e 'const [f, name, index, snapz, d, b, r] = process.argv.slice(1);
      require("fs").writeFileSync(f + ".tmp", JSON.stringify({ name, index, snapz, snapzSha256: d, rawBytes: Number(b), rawSha256: r,
        derivedBy: "scripts/headless/derive-raw.sh", at: new Date().toISOString() }, null, 1) + "\n");
      require("fs").renameSync(f + ".tmp", f);' "$side" "$n" "$R/index.json" "$R/$url" "$digest" "$bytes" "$1"
  }
  have=$(stat -f %z "$out" 2>/dev/null || echo 0)
  if [ "$have" = "$bytes" ] && [ -f "$side" ]; then
    want=$(node -e 'const s = require(process.argv[1]); console.log(s.snapzSha256 === process.argv[2] ? s.rawSha256 : "stale-sidecar")' "$side" "$digest")
    got=$(sha "$out")
    [ "$got" = "$want" ] || { echo "raw $n: content mismatch: sha256 $got != sidecar $want ($out)" >&2; exit 1; }
    echo "raw $n: present ($bytes bytes, sha256 ${got:0:16}… = sidecar, snapz ${digest:0:16}…) $out"; continue
  fi
  got=$(sha "$R/$url")
  [ "$got" = "$digest" ] || { echo "raw $n: snapz digest mismatch ($got != $digest)" >&2; exit 1; }
  if [ "$have" = "$bytes" ]; then # derived elsewhere without a sidecar: verify content, then record
    inflated=$(gunzip -c "$R/$url" | shasum -a 256 | cut -d' ' -f1)
    got=$(sha "$out")
    [ "$got" = "$inflated" ] || { echo "raw $n: content mismatch: sha256 $got != gunzip(snapz) $inflated ($out)" >&2; exit 1; }
    writeside "$got"
    echo "raw $n: present, verified against gunzip(snapz) and sidecar written ($bytes bytes, sha256 ${got:0:16}…) $out"; continue
  fi
  tmp="$out.tmp.$$"
  gunzip -c "$R/$url" > "$tmp"
  sz=$(stat -f %z "$tmp")
  [ "$sz" = "$bytes" ] || { rm -f "$tmp"; echo "raw $n: gunzip gave $sz bytes, index says $bytes" >&2; exit 1; }
  rs=$(sha "$tmp")
  # another lane may have finished first; keep whichever is complete (contents are identical by construction)
  have=$(stat -f %z "$out" 2>/dev/null || echo 0)
  if [ "$have" = "$bytes" ]; then rm -f "$tmp"; else mv -f "$tmp" "$out"; fi
  got=$(sha "$out")
  [ "$got" = "$rs" ] || { echo "raw $n: content mismatch after rename: $got != $rs" >&2; exit 1; }
  writeside "$rs"
  echo "raw $n: derived ($bytes bytes, sha256 ${rs:0:16}…, snapz sha256 $digest) $out"
done
