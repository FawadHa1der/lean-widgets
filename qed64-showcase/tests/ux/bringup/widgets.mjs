// The eight widgets in the gallery: select each card in turn (one boot, gallery switching), wait for its panel,
// check the first cursor's position-bound golden panel (examples.json expectPanel) AND its frozen spec expectations
// (lean/examples/<pkg>.json cursors[0].expect: panelTitle, texts, svgTagCounts, linkTexts — all inside the panel),
// check no "Unrecognised error", then screenshot the full gallery (1440x900) and a tight crop of the
// widget panel. With --thumbs, also write gallery/thumbs/<pkg>.png (480 px wide, <= 60 KB) from the real panel.
// Usage: scripts/with-browser-lock.sh bringup node tests/ux/bringup/widgets.mjs --dir after [--thumbs] [--scheme dark]
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { THUMBS_CHECK } from '../lib/qed64.mjs';
import { SC, ORIGIN, OUT, LAUNCH_ARGS, EXAMPLES, SPECS, SEL, lockHeld, classifyConsole, consoleLine, checkPanel, watchConsole, api, infoview, ivText, ivSettled, waitGalleryReady, writeJson, sleep, chromeRss, rssSampler, installTap, tapSummary } from './lib.mjs';

lockHeld();
const argv = process.argv.slice(2);
const opt = (k, d = null) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const dirName = opt('dir', 'after');
const scheme = opt('scheme', 'light');
const only = opt('only') ? opt('only').split(',') : EXAMPLES.map((e) => e.id);
const thumbs = argv.includes('--thumbs');
const DIR = path.join(OUT, dirName); fs.mkdirSync(DIR, { recursive: true });
const THUMBS = path.join(SC, 'gallery', 'thumbs');
if (thumbs) fs.mkdirSync(THUMBS, { recursive: true });
const t0 = Date.now();
const browser = await chromium.launch({ args: LAUNCH_ARGS });
const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2, colorScheme: scheme });
const tapReports = await installTap(ctx); // LSP tap: pairs each empty console.error with its -32800 reply (console.mjs pairWith)
// the warm OPFS profile is not used here on purpose: a fresh context also measures the cold boot
const page = await ctx.newPage();
const watch = watchConsole(page, t0, `widgets-${dirName}.console.jsonl`);
const rss = rssSampler(1000, t0);
const res = { dir: dirName, scheme, thumbs, widgets: {}, startedAt: new Date().toISOString() };

/**
 * The first cursor's panel, checked three ways (all must hold):
 *   1. position-bound golden expectation (examples.json firstCursor hint .expectPanel, lib.mjs checkPanel): the info
 *      block reads <file>.lean:<line>:<char>, the panel has the golden widget's title / rpc block, exact svg tag
 *      counts and the texts unique to this cursor;
 *   2. the frozen spec expectation lean/examples/<pkg>.json cursors[0].expect: panelTitle (enforced: the spec's title,
 *      or no title = an mk_rpc_widget% panel in the info block), svgTagCounts, texts and linkTexts, all inside the panel;
 *   3. no "Unrecognised error" / abortSignal anywhere in the InfoView.
 */
async function expectationsMet(ex) {
  const exp = (SPECS[ex.id].cursors[0] || {}).expect || {};
  const hint = ex.tryThis.find((h) => h.kind === 'cursor' && h.line === ex.firstCursor.line && h.character === ex.firstCursor.character);
  if (!hint || !hint.expectPanel) return { ok: false, reason: 'no expectPanel for the first cursor (rerun node scripts/build-gallery.mjs)', missingTexts: [], missingLinks: [], svgDiff: {} };
  const text = await ivText(page);
  const chk = await checkPanel(page, hint.expectPanel, { extraTexts: [...(exp.texts || []), ...(exp.linkTexts || [])] });
  const wantTitle = exp.panelTitle || null;
  const titleOk = chk.ok !== undefined && (hint.expectPanel.panelTitle || null) === wantTitle && (chk.panelTitle || null) === wantTitle;
  const specSvgDiff = {};
  for (const [k, v] of Object.entries(exp.svgTagCounts || {})) if (((chk.svgTags || {})[k] || 0) !== v) specSvgDiff[k] = { want: v, got: (chk.svgTags || {})[k] || 0 };
  const missingTexts = (chk.missingTexts || []).filter((t) => !(exp.linkTexts || []).includes(t));
  const missingLinks = (chk.missingTexts || []).filter((t) => (exp.linkTexts || []).includes(t));
  const svgOk = !Object.keys(specSvgDiff).length && !Object.keys(chk.svgDiff || {}).length;
  return {
    ok: !!chk.ok && titleOk && svgOk, reason: chk.reason || (titleOk ? null : `panelTitle ${JSON.stringify(chk.panelTitle)} != spec ${JSON.stringify(wantTitle)}`),
    titleOk, panelTitle: chk.panelTitle || null, wantTitle, missingTexts, missingLinks, svgOk, svgDiff: { ...chk.svgDiff, ...specSvgDiff },
    panel: chk.rect ? { summary: chk.panelTitle || chk.at, at: chk.at, heads: chk.heads, rect: chk.rect, graphicTop: chk.graphicTop, graphicBox: chk.graphicBox || null, svgTags: chk.svgTags, links: chk.links, text: chk.text } : null,
    unrecognised: /Unrecognised error|abortSignal/.test(text), ivHead: text.slice(0, 200),
  };
}

/**
 * Thumbnail, 480x300 max, from the panel's element screenshot (2x):
 *   - panel with an svg drawing: the WHOLE drawing (lib.mjs checkPanel graphicBox = union of painted shapes) scaled to
 *     fit (contain) and letterboxed on white, so no vertex or edge is ever cut off (bring-up audit 5 minor: the old
 *     top crop showed GraphScope's pentagon with only vertices 0, 4, 1);
 *   - otherwise (tables, text panels, a drawing wider than the panel): 480 px wide from the content top, cropped at 300 px.
 */
async function makeThumb(id, pngPath, panel) {
  const b64 = fs.readFileSync(pngPath).toString('base64');
  const thumbPage = await ctx.newPage();
  await thumbPage.goto(`${ORIGIN}/showcase/pin.json`); // same-origin blank-ish page for the canvas work
  const out = await thumbPage.evaluate(async ({ b64, box, y0css }) => {
    const img = new Image(); img.src = `data:image/png;base64,${b64}`; await img.decode();
    const W = 480, maxH = 300, LB_H = 220, D = 2; // the element screenshot is at deviceScaleFactor 2
    let src, dst, h, mode;
    if (box && !box.overflowX) { // a drawing wider than the panel (interval-inspector's number line) is clipped by the InfoView itself: top-crop
      src = { x: Math.round(box.x * D), y: Math.round(box.y * D), w: Math.min(img.naturalWidth - Math.round(box.x * D), Math.round(box.w * D)), h: Math.min(img.naturalHeight - Math.round(box.y * D), Math.round(box.h * D)) };
      // a fixed 480x220 frame (the open card's thumbnail box is ~288x132 css px, aspect ~2.2): shown with
      // object-fit: contain (examples.json thumb.fit), the whole drawing is visible in every card state
      h = LB_H;
      const s = Math.min(W / src.w, h / src.h, 1.5); // never upscale a small drawing by more than 1.5x
      dst = { w: Math.round(src.w * s), h: Math.round(src.h * s) }; dst.x = Math.round((W - dst.w) / 2); dst.y = Math.round((h - dst.h) / 2);
      mode = 'letterbox';
    } else {
      const scale = W / img.naturalWidth; const y0 = Math.round(y0css * D);
      h = Math.min(maxH, Math.round((img.naturalHeight - y0) * scale));
      src = { x: 0, y: y0, w: img.naturalWidth, h: Math.round(h / scale) }; dst = { x: 0, y: 0, w: W, h };
      mode = 'top-crop';
    }
    const enc = async (colors) => {
      const c = document.createElement('canvas'); c.width = W; c.height = h;
      const g = c.getContext('2d'); g.imageSmoothingQuality = 'high'; g.fillStyle = '#fff'; g.fillRect(0, 0, W, h);
      g.drawImage(img, src.x, src.y, src.w, src.h, dst.x, dst.y, dst.w, dst.h);
      if (colors) { // posterize to shrink the PNG; UI art has few distinct colours
        const d = g.getImageData(0, 0, W, h); const q = 256 / colors;
        for (let i = 0; i < d.data.length; i += 4) for (let k = 0; k < 3; k++) d.data[i + k] = Math.min(255, Math.round(Math.round(d.data[i + k] / q) * q));
        g.putImageData(d, 0, 0);
      }
      const blob = await new Promise((r) => c.toBlob(r, 'image/png'));
      return { b64: btoa(String.fromCharCode(...new Uint8Array(await blob.arrayBuffer()))), size: blob.size, w: W, h, colors: colors || 256, mode, src, dst };
    };
    let r = await enc(0);
    for (const colors of [32, 16, 8]) { if (r.size <= 60 * 1024) break; r = await enc(colors); }
    return r;
  }, { b64, box: panel && panel.graphicBox, y0css: (panel && panel.graphicTop) || 0 });
  await thumbPage.close();
  const dst = path.join(THUMBS, `${id}.png`);
  fs.writeFileSync(dst, Buffer.from(out.b64, 'base64'));
  return { path: path.relative(SC, dst), bytes: out.size, w: out.w, h: out.h, posterized: out.colors, mode: out.mode, src: out.src, dst: out.dst };
}

try {
  const first = only[0];
  await page.goto(`${ORIGIN}/showcase/#${first}`, { waitUntil: 'domcontentloaded' });
  const r = await waitGalleryReady(page);
  res.boot = { ms: r.ms, phase: r.s && r.s.phase, overlay: r.s && r.s.overlay, bridge: r.s && r.s.bridge, preflight: r.s && r.s.preflight && { ok: r.s.preflight.ok, availability: r.s.preflight.availability, regionImports: r.s.preflight.regionImports } };
  watch.mark('booted', { ms: r.ms });
  // every card's thumbnail is wired and loads (bring-up audit r2 minor: nothing checked this in the browser; a gallery.js
  // that loaded thumbs/<pkg>.jpg passed every check): selectors.json cardThumb, scrolled into view (loading="lazy"),
  // visible, src thumbs/<pkg>.png, naturalWidth 480. Same source as the UX suite's C1 (tests/ux/lib/qed64.mjs).
  res.thumbsCheck = await page.evaluate(THUMBS_CHECK, EXAMPLES.map((e) => e.id));
  res.thumbsOk = res.thumbsCheck.length === EXAMPLES.length && res.thumbsCheck.every((t) => t.ok);
  console.log(`THUMBS ${res.thumbsOk ? 'OK' : 'FAIL'} ${res.thumbsCheck.filter((t) => t.ok).length}/${EXAMPLES.length} ${JSON.stringify(res.thumbsCheck.map((t) => `${t.id} ${t.src} nw=${t.naturalWidth} ${t.w}x${t.h}${t.hidden ? ' hidden' : ''}`))}`);
  for (const id of only) {
    const ex = EXAMPLES.find((e) => e.id === id);
    const w = { id };
    const b0 = await api.bridge(page);
    const tS = Date.now();
    if ((await api.status(page)).current !== id || (await api.status(page)).shown !== id) { const s = await api.select(page, id); w.select = { ok: s.ok, code: s.code || null }; }
    w.selectMs = Date.now() - tS;
    w.settled = await ivSettled(page, { timeoutMs: 120000 });
    let e = null; const tP = Date.now();
    for (let i = 0; i < 120; i++) { e = await expectationsMet(ex); if (e.ok) break; await sleep(500); }
    w.panelMs = Date.now() - tP;
    await sleep(600);
    e = await expectationsMet(ex);
    Object.assign(w, e);
    const b1 = await api.bridge(page);
    w.bridgeDelta = b0 && b1 ? { stripped: b1.stripped - b0.stripped, wsFetched: b1.ws.fetched - b0.ws.fetched, wsCoalesced: b1.ws.coalesced - b0.ws.coalesced } : null;
    const st = await api.status(page);
    w.status = { phase: st.phase, shown: st.shown, cursor: st.cursor, qed64: st.qed64 && { phase: st.qed64.phase, header: st.qed64.header && st.qed64.header.mode, session: st.qed64.session } };
    w.chip = await page.locator(`#card-${id} .chip`).textContent().catch(() => null);
    await page.screenshot({ path: path.join(DIR, `gallery-${id}.png`) });
    const panel = infoview(page).locator('[data-bringup-panel]');
    if (await panel.count()) {
      const pp = path.join(DIR, `panel-${id}.png`);
      await panel.scrollIntoViewIfNeeded().catch(() => {});
      await panel.screenshot({ path: pp }).catch((err) => { w.panelShotError = err.message; });
      if (thumbs && fs.existsSync(pp)) w.thumb = await makeThumb(id, pp, w.panel);
    } else w.panelShotError = 'no panel element found';
    w.rss = chromeRss();
    res.widgets[id] = w;
    watch.mark('widget', { id, ok: w.ok });
    console.log(JSON.stringify({ id, ok: w.ok, unrec: w.unrecognised, missing: [...w.missingTexts, ...w.missingLinks], svg: w.svgDiff, title: w.panelTitle, reason: w.reason, stripped: w.bridgeDelta && w.bridgeDelta.stripped, panel: w.panel && w.panel.summary, thumb: w.thumb && w.thumb.bytes, ms: w.selectMs }));
  }
  if (thumbs) {
    // gallery/thumbs/thumbs.json: how each thumbnail was made; build-gallery.mjs turns mode into thumb.fit
    const mf = path.join(THUMBS, 'thumbs.json');
    let man = {}; try { man = JSON.parse(fs.readFileSync(mf, 'utf8')); } catch { man = {}; }
    for (const [id, w] of Object.entries(res.widgets)) if (w.thumb) man[id] = { mode: w.thumb.mode, w: w.thumb.w, h: w.thumb.h, bytes: w.thumb.bytes, src: w.thumb.src, dst: w.thumb.dst, madeAt: new Date().toISOString(), run: dirName };
    fs.writeFileSync(mf, `${JSON.stringify(man, null, 2)}\n`);
  }
  res.final = await api.status(page);
  res.bridgeStats = await api.bridge(page);
  res.relayStats = await page.evaluate(() => ({ ...document.getElementById('qed64-frame').contentWindow.qed64.relay.stats }));
} catch (e) {
  res.error = String(e && e.stack || e).slice(0, 1500);
} finally {
  rss.stop();
  res.crashed = watch.crashed; res.rssPeak = rss.peak; res.workersCreated = watch.workers.length;
  res.console = { messages: watch.messages.filter((m) => m.type === 'error' || m.type === 'warning'), pageErrors: watch.pageErrors, counts: watch.messages.reduce((a, m) => { a[m.type] = (a[m.type] || 0) + 1; return a; }, {}) };
  res.consoleVerdict = classifyConsole(watch, SEL.consoleAllowlist, { reports: tapReports }); res.tap = tapSummary(tapReports);
  console.log(consoleLine(res.consoleVerdict));
  res.allOk = !res.error && !res.crashed && res.consoleVerdict.ok && res.thumbsOk === true && only.every((id) => res.widgets[id] && res.widgets[id].ok && !res.widgets[id].unrecognised);
  res.wallMs = Date.now() - t0;
  writeJson(`widgets-${dirName}.json`, res);
  await browser.close().catch(() => {});
}
console.log(`WIDGETS ${res.allOk ? 'OK' : 'FAIL'} ${Object.values(res.widgets).filter((w) => w.ok && !w.unrecognised).length}/${only.length}${res.consoleVerdict && !res.consoleVerdict.ok ? ' (console)' : ''}${res.thumbsOk === true ? '' : ' (thumbnails)'}`);
process.exit(res.allOk ? 0 : 1);
