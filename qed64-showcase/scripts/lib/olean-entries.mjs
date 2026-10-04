// olean-entries.mjs — read ModuleData.entries (env-extension entry counts) from a 64-bit .olean region.
// Same layout reader as QED64's pipeline/artifacts/olean-imports.mjs (deps/qed64); ModuleData object fields are
// imports(0) constNames(1) constants(2) extraConstNames(3) entries(4); entries : Array (Name × Array Entry).
// Used to confirm where a module's IR lives: a legacy (non-`module`) file keeps its IR decls in the
// main .olean (Lean.IR.declMapExt has entries), a module-system file moves them to <M>.ir.
import fs from 'node:fs';
export function oleanExtEntryCounts(bytes) {
  const base = bytes.readBigUInt64LE(80);
  const at = (p) => Number(p - base);
  const isBoxed = (w) => (w & 1n) === 1n;
  const tagOf = (o) => bytes.readUInt8(o + 7);
  const str = (o) => bytes.toString('utf8', o + 32, o + 32 + Number(bytes.readBigUInt64LE(o + 8)) - 1);
  const nameOf = (w) => { const parts = []; while (!isBoxed(w)) { const o = at(w); const c = bytes.readBigUInt64LE(o + 16); parts.push(tagOf(o) === 1 ? str(at(c)) : String(c >> 1n)); w = bytes.readBigUInt64LE(o + 8); } return parts.reverse().join('.'); };
  const arr = (o) => { const n = Number(bytes.readBigUInt64LE(o + 8)); return Array.from({ length: n }, (_, i) => bytes.readBigUInt64LE(o + 24 + 8 * i)); };
  const root = at(bytes.readBigUInt64LE(88));
  const entries = at(bytes.readBigUInt64LE(root + 8 + 8 * 4));
  const out = {};
  for (const w of arr(entries)) { const o = at(w); const name = nameOf(bytes.readBigUInt64LE(o + 8)); out[name] = arr(at(bytes.readBigUInt64LE(o + 16))).length; }
  const constNames = arr(at(bytes.readBigUInt64LE(root + 8 + 8 * 1))).length;
  return { constNames, entries: out };
}
if (process.argv[1] && process.argv[1].endsWith('olean-entries.mjs')) {
  for (const f of process.argv.slice(2)) {
    const r = oleanExtEntryCounts(fs.readFileSync(f));
    console.log(`${f}: constNames=${r.constNames} Lean.IR.declMapExt=${r.entries['Lean.IR.declMapExt'] ?? 'absent'} extensions=${Object.keys(r.entries).length}`);
  }
}
