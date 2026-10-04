#!/usr/bin/env node
// gallery-hash.mjs — one content hash for "which gallery revision" a green claim is about.
//
//   node scripts/lib/gallery-hash.mjs          prints "<sha256>  gallery/ (<n> shipped files)"
//   node scripts/lib/gallery-hash.mjs --json   prints {"contentSha256": …, "files": n}
//
// Definition: sha256 over the lines "<sha256 of file>  <path relative to gallery/>\n" for every SHIPPED gallery file,
// sorted bytewise by path. Shipped = what /showcase/ serves in a deployment (scripts/deploy-manifest.mjs uses the same
// isShippedGalleryFile): every regular file under gallery/ except dotfiles (.DS_Store …), *.md (gallery/README.md)
// and x3.html (the X3 experiment page). So every edit that can change what the gallery does — gallery.js/.css,
// index.html, lib.js, the bridge, examples.json, pin.json, thumbs/ — changes it, and a docs-only edit does not.
// Equivalent shell (paths have no newlines):
//   cd gallery && find . -type f ! -name '.*' ! -name '*.md' ! -path ./x3.html | sed 's|^\./||' | LC_ALL=C sort |
//     while read -r f; do printf '%s  %s\n' "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$f"; done | shasum -a 256
// Used by scripts/showcase.sh (gallery, ux), scripts/deploy-manifest.mjs (manifest.gallery, G1/G2) and
// scripts/lib/ux-record.mjs (the SERVED hash: the same definition over the bytes an origin returns for each file).
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

export const isShippedGalleryFile = (r) => !r.endsWith('.md') && r !== 'x3.html' && !r.split('/').some((x) => x.startsWith('.'));

export function galleryFiles(dir, base = dir) { return files(dir, base); }
function files(dir, base = dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name.startsWith('.')) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...files(p, base)); else if (e.isFile()) out.push(path.relative(base, p).split(path.sep).join('/'));
  }
  return out;
}

export function galleryContentHash(dir = path.join(SC, 'gallery')) {
  const list = files(dir).filter(isShippedGalleryFile).sort((a, b) => (Buffer.compare(Buffer.from(a), Buffer.from(b))));
  const h = createHash('sha256');
  for (const r of list) h.update(`${createHash('sha256').update(fs.readFileSync(path.join(dir, r))).digest('hex')}  ${r}\n`);
  return { contentSha256: h.digest('hex'), files: list.length };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const g = galleryContentHash();
  console.log(process.argv.includes('--json') ? JSON.stringify(g) : `${g.contentSha256}  gallery/ (${g.files} shipped files)`);
}
