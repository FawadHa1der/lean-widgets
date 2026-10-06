// gallery/lib.js — the gallery's pure logic (no DOM): overlay pairing preflight, overlay choice,
// URL re-rooting, the ?mem= knob parser and status classification. Imported by gallery.js in the
// browser and by scripts/check-gallery.mjs in Node (with a real or mocked fetch), so the preflight
// that guards navigation is the same code the static gate exercises.
//
// Facts this mirrors (QED64 @9fdf9b8, read from the submodule deps/qed64; qed64-boot.ts and resident-session.ts are unchanged since 1859b83):
//   * ?snapshots=<dir> fetches /<dir>/index.json and re-roots every entry url that starts with
//     /snapshots/ to /<dir>/ (frontend/src/qed64-boot.ts:96-106). A failed or malformed override index
//     fails SILENTLY in the page and only surfaces later as "snapshot 'init' failed to load"
//     (map-frontend-boot.md (1c)) — hence this preflight before navigation.
//   * A Mathlib header boots the snapshot names ['init','mathlib'] (resident-session.ts:85).
//   * The worker refuses a snapshot whose runtime differs from its own (SNAPSHOT_UNPAIRED,
//     public/workers/lean.worker.js:1236-1246); the page's bundle pins its runtime buildId
//     (qed64-boot.ts:62-78), which build-gallery.mjs copies into gallery/pin.json from QED64.lock.json
//     after checking the release bundle names exactly that buildId.
//   * The workers refuse transformed chunks (lean.worker.js:594-596): no Content-Encoding.
//   * The resident session's memory cap is 6 GiB (resident-session.ts:101).

export const SNAPSHOT_SCHEMA = 'qed64.snapshot-index/v1';
export const REQUIRED_SNAPSHOTS = ['init', 'mathlib'];
export const DEFAULT_OVERLAYS = ['widgets8', 'widgets7'];
export const OVERLAY_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
export const MiB = 1048576;
export const GiB = 1073741824;
export const MEM_MIN_BYTES = 1 * GiB;
export const MEM_MAX_BYTES = 6 * GiB; // DEFAULT_MAXIMUM_BYTES; initialBytes above the cap cannot be committed
export const MEM_STEP_BYTES = 256 * MiB;
export const BUFFER_KEY = 'qed64.buffer'; // main.ts:335-342 (the page's boot input), bundle: localStorage.getItem("qed64.buffer")
export const SAVED_KEY = 'qed64-showcase:saved';            // the FIRST user buffer the gallery displaced; never overwritten
export const SAVED_HISTORY_KEY = 'qed64-showcase:saved-history'; // later displaced user buffers, newest first, bounded
export const SAVED_HISTORY_MAX = 5;
export const EXAMPLE_EDIT_KEY = 'qed64-showcase:edited-example'; // the latest gallery-edited example (one slot; never a user buffer)
export const DOCUMENT_KEY = 'qed64-showcase:document'; // V1 (embed mode): the text the relay last forwarded ('document' events); re-seeds an adopted reload
export const MEM_PLACEHOLDER_PREFIX = '-- QED64 showcase:';

/**
 * The stock page URL for an overlay (relative to the gallery's origin). Legacy pins: `/?snapshots=snapshots/<overlay>`.
 * Embedding contract v1 (deps/qed64/docs/EMBEDDING.md §3, §4): {embed: true} adds `embed=1` (the page neither reads nor
 * writes qed64.buffer and hides its examples menu), {memoryGiB} adds `memory=<GiB>` (the page validates and clamps it: the
 * initial commit of EVERY session), {code} appends `#code=<encodeURIComponent(text)>` (the boot document, honoured only
 * inside a same-origin frame and read ONCE: the page drops it with history.replaceState).
 */
export function frameUrl(overlay, { embed = false, memoryGiB = null, code = null } = {}) {
  let u = `/?${embed ? 'embed=1&' : ''}snapshots=snapshots/${overlay}`;
  if (memoryGiB != null) u += `&memory=${memoryGiB}`;
  if (typeof code === 'string') u += `#code=${encodeURIComponent(code)}`;
  return u;
}
/** The document a v1 frame URL carries (`#code=`), decoded; null when none (mirrors page-api.ts codeFromHash). */
export function codeOfFrameUrl(url) {
  const m = /#(?:.*&)?code=([^&]*)/.exec(String(url || ''));
  if (!m) return null;
  try { return decodeURIComponent(m[1]); } catch { return null; }
}
/** Exactly the page's re-rooting: `e.url.replace(/^\/snapshots\//, `/${dir}/`)` with dir = snapshots/<overlay>. */
export const rerootUrl = (url, overlay) => url.replace(/^\/snapshots\//, `/snapshots/${overlay}/`);
/** The import module of a header line (`import ChartKit` → `ChartKit`), else null. */
export const moduleOfImport = (line) => { const m = /^\s*import\s+([A-Za-z_«][\w.«»']*)\s*$/.exec(line || ''); return m ? m[1] : null; };

/** Parse ?mem=<GiB>. Returns {ok, bytes|null, gib, note}. Rounded to 256 MiB, inside [1, 6] GiB. */
export function parseMem(raw) {
  if (raw === null || raw === undefined || raw === '') return { ok: true, bytes: null, gib: null, note: null };
  const gib = Number(raw);
  if (!Number.isFinite(gib) || gib <= 0) return { ok: false, bytes: null, gib: null, note: `?mem=${raw} is not a positive number of GiB` };
  let bytes = Math.round((gib * GiB) / MEM_STEP_BYTES) * MEM_STEP_BYTES;
  let note = null;
  if (bytes < MEM_MIN_BYTES) { bytes = MEM_MIN_BYTES; note = `?mem=${raw} raised to the 1 GiB minimum`; }
  if (bytes > MEM_MAX_BYTES) { bytes = MEM_MAX_BYTES; note = `?mem=${raw} lowered to the 6 GiB cap (the session's maximumBytes)`; }
  return { ok: true, bytes, gib: +(bytes / GiB).toFixed(3), note };
}

/** The text the light first session boots with under ?mem= (no import lines → ['init'], 256 MiB). */
export const memPlaceholder = (gib) =>
  `${MEM_PLACEHOLDER_PREFIX} starting a light session first, then the widgets environment with a ${gib} GiB initial memory commit (?mem=${gib}).\n`;

const isHtml = (ct) => /text\/html/i.test(ct || '');
const isJsonish = (ct) => /json/i.test(ct || '');

/**
 * The pairing preflight for one overlay. Never throws: every failure is a check with ok:false.
 * @param {{overlay:string, buildId:string, fetch:(url:string, init?:object)=>Promise<Response>, modules?:Record<string,string>, origin?:string}} o
 *   modules: example id → its package module (from the header's second import), for availability.
 *   origin: prefix for URLs (Node needs an absolute origin; the browser passes '').
 * @returns {Promise<{ok:boolean, overlay:string, checks:{id:string, ok:boolean, detail:string}[], notFound:boolean,
 *   index:object|null, entries:object[], availability:Record<string, boolean|null>|null, regionImports:string[]|null}>}
 */
export async function preflightOverlay(o) {
  const { overlay, buildId, fetch: f, modules = {}, origin = '' } = o;
  const checks = [];
  const res = { ok: false, overlay, checks, notFound: false, index: null, entries: [], availability: null, regionImports: null };
  const check = (id, ok, detail) => { checks.push({ id, ok: !!ok, detail }); return !!ok; };
  if (!check('overlay-name', OVERLAY_RE.test(overlay || ''), `overlay name ${JSON.stringify(overlay)} ${OVERLAY_RE.test(overlay || '') ? 'is valid' : 'must match ' + OVERLAY_RE}`)) return res;
  if (!check('build-id', /^wasm64-[0-9a-f]{16}$/.test(buildId || ''), `gallery pin buildId ${buildId || '(missing)'}`)) return res;

  // 1. The pinned runtime manifest the bundle asks for first (qed64-boot.ts:62-66) is served and names the buildId.
  try {
    const r = await f(`${origin}/runtime/runtime-manifest.${buildId}.json`, { cache: 'no-cache' });
    const ct = r.headers.get('content-type');
    let j = null; if (r.ok && isJsonish(ct)) { try { j = await r.json(); } catch { j = null; } }
    check('runtime-manifest', r.ok && j && j.buildId === buildId,
      r.ok ? (j ? `runtime-manifest.${buildId}.json names ${j.buildId}${j.leanVersion ? ` (Lean ${j.leanVersion})` : ''}` : `runtime manifest is not JSON (content-type ${ct})`) : `runtime manifest HTTP ${r.status}`);
  } catch (e) { check('runtime-manifest', false, `runtime manifest fetch failed: ${e && e.message || e}`); }

  // 2. The overlay index.
  let idx = null;
  try {
    const r = await f(`${origin}/snapshots/${overlay}/index.json`, { cache: 'no-cache' });
    const ct = r.headers.get('content-type');
    if (r.status === 404) res.notFound = true;
    if (check('index-http', r.ok && !isHtml(ct), r.ok ? (isHtml(ct) ? `index.json answered as HTML (SPA fallback?)` : `GET /snapshots/${overlay}/index.json 200 (${ct || 'no content-type'})`) : `GET /snapshots/${overlay}/index.json → HTTP ${r.status}`)) {
      const body = await r.text();
      try { idx = JSON.parse(body); } catch { idx = null; }
      check('index-json', !!idx, idx ? `index.json parses (${body.length} bytes)` : 'index.json is not valid JSON');
    }
  } catch (e) { check('index-http', false, `index fetch failed: ${e && e.message || e}`); }
  if (!idx) return res;
  res.index = idx;
  if (!check('index-schema', idx.schema === SNAPSHOT_SCHEMA && Array.isArray(idx.snapshots) && idx.snapshots.length > 0,
    `schema ${JSON.stringify(idx.schema)}, ${Array.isArray(idx.snapshots) ? idx.snapshots.length : 'no'} entries (want ${SNAPSHOT_SCHEMA})`)) return res;
  const names = idx.snapshots.map((e) => e && e.name);
  const dup = names.filter((n, i) => names.indexOf(n) !== i);
  check('index-names', REQUIRED_SNAPSHOTS.every((n) => names.includes(n)) && dup.length === 0,
    `entries [${names.join(', ')}]; the stock page boots a Mathlib header with [${REQUIRED_SNAPSHOTS.join(', ')}]${dup.length ? `; duplicate ${dup.join(', ')}` : ''}`);

  // 3. Per entry: pairing fields, then HEAD the re-rooted .snapz.
  for (const e of idx.snapshots) {
    const n = e && e.name;
    const fieldsOk = e && typeof e.url === 'string' && e.url.startsWith('/snapshots/') && /\.snapz$/.test(e.url)
      && /^sha256:[0-9a-f]{64}$/.test(e.digest || '') && Number.isSafeInteger(e.transfer) && e.transfer > 0;
    check(`entry-${n}-fields`, fieldsOk, fieldsOk ? `${n}: ${e.url} digest ${e.digest.slice(7, 23)}… transfer ${e.transfer}` : `${n}: malformed entry ${JSON.stringify(e).slice(0, 200)}`);
    check(`entry-${n}-runtime`, e && e.runtime === buildId, `${n}: runtime ${e && e.runtime} ${e && e.runtime === buildId ? '==' : '!='} bundle ${buildId}`);
    if (!fieldsOk) continue;
    const url = rerootUrl(e.url, overlay);
    try {
      const r = await f(`${origin}${url}`, { method: 'HEAD', cache: 'no-store' });
      const len = r.headers.get('content-length');
      const ct = r.headers.get('content-type');
      const enc = r.headers.get('content-encoding');
      const ok = r.status === 200 && len !== null && Number(len) === e.transfer && !isHtml(ct) && (!enc || enc === 'identity');
      check(`entry-${n}-head`, ok, `HEAD ${url} → ${r.status}, content-length ${len} (index transfer ${e.transfer}), ${ct || 'no content-type'}${enc ? `, content-encoding ${enc}` : ''}`);
    } catch (err) { check(`entry-${n}-head`, false, `HEAD ${url} failed: ${err && err.message || err}`); }
  }
  res.entries = idx.snapshots;

  // 4. Availability: which example packages the region was baked with (the bake's probe imports end up in the
  //    renamed entry's `imports`). Unknown (null) when the index does not say.
  const region = idx.snapshots.find((e) => e && e.name === 'mathlib');
  if (region && Array.isArray(region.imports)) {
    res.regionImports = region.imports.slice();
    res.availability = {};
    for (const [id, mod] of Object.entries(modules)) res.availability[id] = region.imports.includes(mod);
  }
  res.ok = checks.every((c) => c.ok);
  return res;
}

/**
 * Choose the overlay: an explicit ?overlay= is preflighted alone (never falls back); otherwise widgets8,
 * then widgets7. Returns {ok, overlay, result, attempts:[{overlay, ok, result}], fellBack, requested}.
 */
export async function chooseOverlay({ requested, buildId, fetch: f, modules, origin = '' }) {
  const list = requested ? [requested] : DEFAULT_OVERLAYS;
  const attempts = [];
  for (const overlay of list) {
    const result = await preflightOverlay({ overlay, buildId, fetch: f, modules, origin });
    attempts.push({ overlay, ok: result.ok, result });
    if (result.ok) return { ok: true, overlay, result, attempts, fellBack: attempts.length > 1, requested: requested || null };
  }
  // all failed: report the first attempt whose index exists (a real pairing failure beats a plain 404)
  const best = attempts.find((a) => !a.result.notFound) || attempts[0];
  return { ok: false, overlay: best.overlay, result: best.result, attempts, fellBack: false, requested: requested || null };
}

/**
 * Classify a qed64.status() snapshot. `everReady`: this page document reached ready at least once.
 * kind: 'none' | 'busy' | 'ready' | 'refused' | 'dead' | 'halted' | 'bootFailed'
 * hard: the gallery must show a blocking error card. soft: show a recoverable card and keep waiting.
 */
export function classifyStatus(st, everReady) {
  if (!st) return { kind: 'none', hard: false, soft: false, text: 'no status' };
  const death = st.lastDeath ? `${st.lastDeath.reason}${st.lastDeath.message ? `: ${st.lastDeath.message}` : ''}` : '';
  if (st.phase === 'halted' || st.relay === 'halted')
    return { kind: 'halted', hard: true, soft: false, text: `halted after repeated crashes${death ? ` (${death})` : ''}` };
  if (!everReady && st.lastDeath)
    return { kind: 'bootFailed', hard: false, soft: true, text: `could not start (${death}); QED64 is retrying` };
  if (st.phase === 'dead') return { kind: 'dead', hard: false, soft: false, text: `checker died${death ? ` (${death})` : ''}; restarting` };
  if (st.phase === 'headerRefused') return { kind: 'refused', hard: false, soft: false, text: `header refused${st.header && st.header.missing && st.header.missing.length ? `: missing ${st.header.missing.join(', ')}` : ''}` };
  if (st.phase === 'ready') return { kind: 'ready', hard: false, soft: false, text: 'ready' };
  return { kind: 'busy', hard: false, soft: false, text: st.phase || 'booting' };
}

/** 0-based LSP position (character in UTF-16 units) → Monaco position (1-based; Monaco columns count UTF-16 units). */
export const toMonaco = (line, character) => ({ lineNumber: line + 1, column: character + 1 });

/** Poll `fn` until it returns a truthy value. `fn` may throw to abort. */
export async function waitFor(fn, { timeoutMs = 60000, intervalMs = 100, label = 'condition' } = {}) {
  const t0 = Date.now();
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() - t0 > timeoutMs) { const e = new Error(`timed out after ${Math.round(timeoutMs / 1000)} s waiting for ${label}`); e.code = 'TIMEOUT'; throw e; }
    await new Promise((r) => setTimeout(r, intervalMs));
  }
}

/** How many leading lines identify an example document (the two-line header, a blank line, the doc title line). */
export const EXAMPLE_PREFIX_LINES = 4;
const prefixOf = (t) => String(t).split('\n').slice(0, EXAMPLE_PREFIX_LINES).join('\n');
/** Is `text` an example the user edited in the gallery (it starts with an example's exact first lines)? */
export function derivedFromExample(text, exampleTexts) {
  if (typeof text !== 'string' || !exampleTexts) return false;
  const p = prefixOf(text);
  if (p.split('\n').length < EXAMPLE_PREFIX_LINES) return false;
  for (const e of exampleTexts) if (prefixOf(e) === p) return true;
  return false;
}

/**
 * Decide what to store when the gallery is about to replace qed64.buffer (the page's boot document).
 * Pure: takes the current storage values, returns the new ones. Never overwrites an existing SAVED value: the first
 * displaced user buffer stays in SAVED forever (until the user clears it); later distinct ones go to a bounded,
 * newest-first history. Not user buffers, so never stored there: pristine example texts, the ?mem placeholder, the
 * text about to be seeded, and an example the user edited in the gallery (same first EXAMPLE_PREFIX_LINES lines as an
 * example: QED64 persists the editor, so every gallery edit comes back as qed64.buffer on the next visit). The latest
 * such edited example goes to its own one-slot key (EXAMPLE_EDIT_KEY, action 'example') and can never push a real
 * user buffer out of the history.
 * @returns {{saved:string|null, history:string[], exampleEdit:string|null, action:'none'|'saved'|'history'|'known'|'example'}}
 */
export function planSave({ prev, seedText, saved, history, exampleTexts }) {
  const hist = Array.isArray(history) ? history.filter((h) => typeof h === 'string') : [];
  const keep = { saved: saved ?? null, history: hist, exampleEdit: null };
  const isText = typeof prev === 'string' && prev.trim() !== '' && prev !== seedText && !(exampleTexts && exampleTexts.has(prev)) && !prev.startsWith(MEM_PLACEHOLDER_PREFIX);
  if (!isText) return { ...keep, action: 'none' };
  if (derivedFromExample(prev, exampleTexts)) return { ...keep, exampleEdit: prev, action: 'example' };
  if (saved === null || saved === undefined) return { ...keep, saved: prev, action: 'saved' };
  if (prev === saved || hist.includes(prev)) return { ...keep, action: 'known' };
  return { ...keep, history: [prev, ...hist].slice(0, SAVED_HISTORY_MAX), action: 'history' };
}

/**
 * Every kept user buffer, newest first: the history (newest first), then the first one ever saved. Index 0 is what
 * "Open my saved buffer" opens; the chooser lists them all.
 * @returns {{text:string, source:'history'|'saved', label:string}[]}
 */
export function savedEntries(saved, history) {
  const out = [];
  for (const h of Array.isArray(history) ? history : []) if (typeof h === 'string' && h !== saved) out.push({ text: h, source: 'history' });
  if (typeof saved === 'string' && saved !== '') out.push({ text: saved, source: 'saved' });
  return out.map((e, i) => {
    const first = (e.text.split('\n').find((l) => l.trim() !== '') || '').trim();
    const n = e.text.split('\n').length - (e.text.endsWith('\n') ? 1 : 0);
    const head = first.length > 40 ? `${first.slice(0, 39)}…` : first;
    const when = out.length === 1 ? 'saved' : i === 0 ? 'newest' : e.source === 'saved' ? 'first saved' : `older ${i}`;
    return { ...e, label: `${when}: ${head || '(blank)'} (${n} line${n === 1 ? '' : 's'})` };
  });
}

/** A deep-link hash → example id. Never throws: a malformed escape (e.g. "#%") or an unknown id gives {id:null, bad}. */
export function parseHash(hash, ids) {
  const raw = String(hash || '').replace(/^#/, '');
  if (raw === '') return { id: null, bad: null };
  let dec;
  try { dec = decodeURIComponent(raw); } catch { return { id: null, bad: raw.slice(0, 60) }; }
  return ids.includes(dec) ? { id: dec, bad: null } : { id: null, bad: dec.slice(0, 60) };
}

// ---------------------------------------------------------------- browser capabilities (checked before anything boots)
// What QED64's runtime needs from the browser, checked by the gallery BEFORE it fetches a snapshot or navigates the
// iframe, so that a browser that cannot run it gets a clear card instead of a page that silently never starts:
//   * cross-origin isolation (crossOriginIsolated): the page must be served with COOP/COEP; without it there is no
//     SharedArrayBuffer and no threads;
//   * SharedArrayBuffer (Lean's pthreads share one wasm memory);
//   * WebAssembly Memory64: the same 13-byte module QED64's worker validates (public/workers/lean.worker.js
//     MEMORY64_PROBE: a memory section with flags 0x04) and, where the first two hold, a SHARED 64-bit memory built the
//     way the worker builds it (lean.worker.js capabilities(): {initial 1, maximum 2, shared, address 'i64'});
//   * memory: navigator.deviceMemory where the browser exposes it (Chromium only; an approximate figure: Chrome 151 on this 36 GB host reports 32, UX C24). A Chromium tab
//     running the gallery uses about 8–9 GB at ready (renderer 8.2–9.0 GiB, UX C3) and peaks at about 12 GB on a
//     reload (C10); two tabs, or QED64's "Load exact imports", take about 17 GB (C18, C16; README "Browsers and
//     memory"), so the text asks for 16 GB of RAM or more and one showcase tab at a time. A device that reports less
//     than 8 GB gets a WARNING card with "Try anyway" (the figure is approximate), never a hard block; a browser that
//     does not expose it is not judged.
export const MEMORY64_PROBE = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x05, 0x03, 0x01, 0x04, 0x00];
export const MIN_DEVICE_MEMORY_GB = 8;
export const BROWSER_NEED = 'This showcase needs a Chromium-based desktop browser (Chrome, Edge, Brave, Arc) on a computer with 16 GB of RAM or more, one showcase tab at a time (a tab uses about 8–9 GB, about 12 GB on a reload)';
/**
 * env: {crossOriginIsolated, SharedArrayBuffer, WebAssembly, BigInt, deviceMemory} (the page passes its globals; tests
 * pass fakes). Returns {ok, hard: [ids], soft: [ids], missing: [ids], lacks: 'a, b and c' (what the browser lacks, in
 * words), checks: [{id, ok, soft, need, detail}], deviceMemory}. Never throws.
 */
export function checkCapabilities(env = {}) {
  const checks = [];
  const add = (id, ok, need, detail, soft = false) => checks.push({ id, ok: !!ok, soft, need, detail });
  const coi = env.crossOriginIsolated === true;
  add('coi', coi, 'cross-origin isolation', coi ? 'cross-origin isolated (COOP/COEP)' : 'crossOriginIsolated is false: the page was not served with COOP/COEP, or this browser does not isolate it');
  const sab = typeof env.SharedArrayBuffer === 'function';
  add('sab', sab, 'SharedArrayBuffer', sab ? 'SharedArrayBuffer is available' : 'SharedArrayBuffer is not available (Lean runs on threads that share memory)');
  const WA = env.WebAssembly;
  let m64 = false; let why = null;
  try {
    if (!WA || typeof WA.validate !== 'function') why = 'this browser has no WebAssembly';
    else if (!WA.validate(new Uint8Array(MEMORY64_PROBE))) why = 'WebAssembly Memory64 (64-bit memory) is not supported';
    else m64 = true;
  } catch (e) { why = `WebAssembly.validate threw: ${String(e && e.message || e).slice(0, 120)}`; }
  if (m64 && coi && sab) {
    // QED64 boots on a SHARED 64-bit memory; build one the way its worker does (only meaningful when SAB exists)
    try {
      const B = env.BigInt;
      if (typeof B !== 'function') throw new Error('no BigInt');
      new WA.Memory({ initial: B(1), maximum: B(2), shared: true, address: 'i64' }); // eslint-disable-line no-new
    } catch (e) { m64 = false; why = `a shared 64-bit WebAssembly memory cannot be created (${String(e && e.message || e).slice(0, 120)})`; }
  }
  add('memory64', m64, 'WebAssembly Memory64', m64 ? 'WebAssembly Memory64 is supported' : why);
  const dm = typeof env.deviceMemory === 'number' && Number.isFinite(env.deviceMemory) ? env.deviceMemory : null;
  const memOk = dm === null || dm >= MIN_DEVICE_MEMORY_GB;
  add('memory', memOk, 'enough memory', dm === null ? 'this browser does not report its device memory (not checked)'
    : memOk ? `the device reports ${dm} GB of memory` : `the device reports only ${dm} GB of memory; a showcase tab uses about 8–9 GB, about 12 GB on a reload`, true);
  const hard = checks.filter((c) => !c.ok && !c.soft).map((c) => c.id);
  const soft = checks.filter((c) => !c.ok && c.soft).map((c) => c.id);
  const missing = [...hard, ...soft];
  const words = checks.filter((c) => !c.ok).map((c) => c.need);
  const lacks = words.length <= 1 ? words.join('') : `${words.slice(0, -1).join(', ')} and ${words[words.length - 1]}`;
  return { ok: missing.length === 0, hard, soft, missing, lacks, checks, deviceMemory: dm };
}
