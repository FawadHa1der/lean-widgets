// A link-shaping TCP proxy (last-mile lane, 2026-10-03): one visitor's access link in front of serve.mjs, for the
// throttled first visit. CDP network emulation does not reach QED64's dedicated-worker downloads in Chrome 151
// (Network.emulateNetworkConditions in a worker session answers "Not supported", and page-level conditions leave the
// worker's fetches unshaped: out/ux/lastmile-throttle/explore/throttle-t50.json), so the link is shaped below the browser:
//   * every new connection waits one RTT before it reaches the server (the TCP handshake);
//   * client -> server bytes are delayed RTT/2; server -> client bytes are delayed RTT/2 AND paced through ONE token
//     bucket shared by all connections at --mbps (the downlink), with backpressure on the server socket;
//   * --up-mbps paces the uplink the same way (requests are tiny).
// Headers and bodies pass through unchanged (COOP/COEP/CORP intact). Every 5 s it logs bytes sent down and the achieved
// rate, and at exit a JSON summary (stdout). Usage:
//   node tests/ux/tools/throttle-proxy.mjs --listen 5198 --upstream 5197 --mbps 50 --rtt 40
import net from 'node:net';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const LISTEN = Number(arg('--listen', '5198')); const UP = Number(arg('--upstream', '5197'));
const MBPS = Number(arg('--mbps', '50')); const UPMBPS = Number(arg('--up-mbps', String(MBPS))); const RTT = Number(arg('--rtt', '40'));
const downBps = (MBPS * 1e6) / 8; const upBps = (UPMBPS * 1e6) / 8;
const link = { down: { freeAt: 0, bps: downBps, bytes: 0 }, up: { freeAt: 0, bps: upBps, bytes: 0 } };
const t0 = Date.now(); let conns = 0; let firstDown = null; let lastDown = null; const HIGH = 2 * 1024 * 1024;
/** Schedule `chunk` on `dir` of the link: not before now + RTT/2, and not before the link is free; returns the delay. */
function pace(dir, n) { const L = link[dir]; const now = Date.now(); const start = Math.max(now + RTT / 2, L.freeAt); L.freeAt = start + (n / L.bps) * 1000; L.bytes += n; return { at: start, end: L.freeAt }; }
function pipe(src, dst, dir) {
  let queued = 0; let ended = false; let pending = 0;
  // FIFO of this connection's slices. Each timer writes the OLDEST queued slice, never "its own": Node starts a timer
  // from the cached loop time, so two slices scheduled in different callbacks can expire out of order when their
  // `end` times are closer than the loop lag between those callbacks. Writing the closured slice then reordered bytes
  // within one connection (closure lane, 2026-10-03: a 50 Mbit/s first visit got a corrupt snapshot gzip, QED64's raw
  // prefetch failed with "invalid code lengths set"; $W/closure/proxy-order-test.mjs broke order in 6 of 6 runs).
  const fifo = [];
  src.on('data', (chunk) => {
    // split big chunks so pacing is smooth (64 KiB slices)
    for (let o = 0; o < chunk.length; o += 65536) {
      const slice = chunk.subarray(o, Math.min(chunk.length, o + 65536));
      const { end } = pace(dir, slice.length);
      queued += slice.length; pending++; fifo.push(slice);
      if (queued > HIGH) src.pause();
      setTimeout(() => {
        const part = fifo.shift();
        if (!dst.destroyed) dst.write(part);
        if (dir === 'down') { if (firstDown === null) firstDown = Date.now(); lastDown = Date.now(); }
        queued -= part.length; pending--;
        if (queued <= HIGH / 2 && src.isPaused()) src.resume();
        if (ended && pending === 0 && !dst.destroyed) dst.end();
      }, Math.max(0, end - Date.now()));
    }
  });
  src.on('end', () => { ended = true; if (pending === 0 && !dst.destroyed) dst.end(); });
  src.on('error', () => dst.destroy());
  src.on('close', () => { if (pending === 0) dst.destroy(); });
}
const onConn = (client) => {
  conns++;
  client.pause();
  setTimeout(() => { // one RTT for the handshake
    const up = net.connect(UP, '127.0.0.1', () => { pipe(client, up, 'up'); pipe(up, client, 'down'); client.resume(); });
    up.on('error', () => client.destroy());
    client.on('error', () => up.destroy());
  }, RTT);
};
net.createServer(onConn).listen(LISTEN, '127.0.0.1', () => console.log(`throttle-proxy :${LISTEN} -> :${UP} down ${MBPS} Mbit/s up ${UPMBPS} Mbit/s rtt ${RTT} ms`));
const server6 = net.createServer(onConn); server6.on('error', (e) => console.log(`no ::1 listener: ${e.message}`)); server6.listen(LISTEN, '::1');
let lastB = 0; let lastT = Date.now();
setInterval(() => { const now = Date.now(); const b = link.down.bytes; if (b !== lastB) console.log(`${new Date().toISOString()} down ${(b / 1e6).toFixed(1)} MB total, ${(((b - lastB) * 8) / ((now - lastT) * 1000)).toFixed(1)} Mbit/s over the last ${((now - lastT) / 1000).toFixed(1)} s, ${conns} connections`); lastB = b; lastT = now; }, 5000).unref();
const bye = () => { const span = firstDown && lastDown ? (lastDown - firstDown) / 1000 : null; console.log(`SUMMARY ${JSON.stringify({ mbps: MBPS, rttMs: RTT, connections: conns, downBytes: link.down.bytes, upBytes: link.up.bytes, downSpanS: span, achievedMbps: span ? +((link.down.bytes * 8) / (span * 1e6)).toFixed(1) : null, uptimeS: (Date.now() - t0) / 1000 })}`); process.exit(0); };
process.on('SIGTERM', bye); process.on('SIGINT', bye);
