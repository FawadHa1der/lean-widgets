// term-labels.mjs — card labels for Lean commands and terms, shortened only at TERM boundaries (bring-up audit 5
// minor: no mid-term "…"; bring-up audit r2 minor: cursor hint labels were the spec's truncated command prefix, e.g.
// "#interval_inspect ((3:ℝ) ∈", which reads as a complete but broken command). Shared by scripts/build-gallery.mjs
// (which writes the labels into gallery/examples.json) and scripts/check-gallery.mjs (which checks them).
/**
 * Shorten a Lean term for a card label at TERM boundaries only (bring-up audit 5 minor: no mid-term "…"): drop the
 * proof after a top-level ` := ` (`… := …`), then elide the contents of the longest innermost bracket group
 * (`(…)`, `[…]`) until it fits; plain oneLine() only if that still does not fit.
 */
const OPEN = '([{⟨'; const CLOSE = ')]}⟩';
/** Index of the first ` := ` at bracket depth 0 (outside string literals), or -1. */
function topLevelAssign(t) {
  let d = 0; let str = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (c === '"' && t[i - 1] !== '\\') str = !str;
    if (str) continue;
    if (OPEN.includes(c)) d++; else if (CLOSE.includes(c)) d = Math.max(0, d - 1);
    else if (d === 0 && t.startsWith(' := ', i)) return i;
  }
  return -1;
}
/** Bracket depth at the end of `t` (string literals skipped): > 0 while a group is still open. */
function openDepth(t) {
  let d = 0; let str = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (c === '"' && t[i - 1] !== '\\') str = !str;
    if (str) continue;
    if (OPEN.includes(c)) d++; else if (CLOSE.includes(c)) d--;
  }
  return d;
}
/** Brackets balance (each closer matches the innermost opener) and string quotes are paired: a shortened label must
 * still read as a well-formed (elided) term, never a fragment (bring-up audit r2 minor: cut-off hint labels). */
export function balancedLabel(t) {
  const st = []; let str = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (c === '"' && t[i - 1] !== '\\') { str = !str; continue; }
    if (str) continue;
    if (OPEN.includes(c)) st.push(c);
    else if (CLOSE.includes(c)) { if (!st.length || OPEN.indexOf(st.pop()) !== CLOSE.indexOf(c)) return false; }
  }
  return !str && st.length === 0;
}
const abbrevTerm = (s, max = 72) => {
  let t = String(s).replace(/\s*\n\s*/g, ' ').trim();
  if (t.length <= max) return t;
  const pr = topLevelAssign(t); if (pr > 0) t = `${t.slice(0, pr)} := …`;
  for (let guard = 0; t.length > max && guard < 20; guard++) {
    let best = null; const stack = [];
    for (let i = 0; i < t.length; i++) {
      const c = t[i];
      if (c === '(' || c === '[' || c === '{' || c === '⟨') stack.push({ i, leaf: true });
      else if ((c === ')' || c === ']' || c === '}' || c === '⟩') && stack.length) {
        const g = stack.pop(); const inner = t.slice(g.i + 1, i);
        if (stack.length && inner !== '…') stack[stack.length - 1].leaf = false; // an elided group no longer counts
        if (g.leaf && inner !== '…' && (!best || inner.length > best.len)) best = { a: g.i + 1, b: i, len: inner.length };
      }
    }
    if (!best) break;
    t = `${t.slice(0, best.a)}…${t.slice(best.b)}`;
  }
  if (t.length <= max) return t;
  // no bracket group left to elide: cut at the last top-level space that fits and say so (never inside a group)
  let cut = -1; let d = 0; let str = false;
  for (let i = 0; i < t.length && i <= max - 2; i++) {
    const c = t[i];
    if (c === '"' && t[i - 1] !== '\\') str = !str;
    if (str) continue;
    if (OPEN.includes(c)) d++; else if (CLOSE.includes(c)) d--;
    else if (c === ' ' && d === 0) cut = i;
  }
  return cut > 0 ? `${t.slice(0, cut)} …` : t;
};
/** The whole command that starts at (line, character): the rest of that line, plus each following line while a bracket
 * is still open or the line is indented deeper than the command's own column (Lean's continuation lines; a blank or
 * `--` line ends it), on one line. A cursor hint's label is this, shortened by abbrevTerm. */
function commandAt(lines, line, character) {
  let t = (lines[line] || '').slice(character);
  for (let i = line + 1; i < lines.length && i <= line + 12; i++) {
    const l = lines[i]; const ind = l.length - l.trimStart().length;
    const cont = openDepth(t) > 0 || (l.trim() !== '' && !l.trim().startsWith('--') && ind > character);
    if (!cont) break;
    t += ` ${l.trim()}`;
  }
  return t.replace(/\s+/g, ' ').trim();
}
export const CURSOR_LABEL_MAX = 64;
/** "Line N · <command>": the whole command when it fits, else abbrevTerm's term-boundary elision (always with "…"). */
export const cursorLabel = (lines, c) => `Line ${c.line + 1} · ${abbrevTerm(commandAt(lines, c.line, c.character), CURSOR_LABEL_MAX)}`;
export { commandAt, abbrevTerm, topLevelAssign, openDepth };
