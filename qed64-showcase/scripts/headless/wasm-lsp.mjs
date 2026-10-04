// Transports for rpc-probe.mjs. Both expose the same small LSP client surface
// as lean/goldens/lsp-golden.mjs's `Lsp` class:
//   request(method, params, timeoutMs) -> Promise<result>
//   notify(method, params)
//   diags: Map<uri, publishDiagnostics params>, progress: Map<uri, fileProgress params>
//   header: last $/qed64/headerStatus params (wasm only), stderr: string[]
//   close()
//
// WasmLsp boots the pinned QED64 runtime (stage1 lean.js/lean.wasm) IN THIS
// Node process exactly like QED64's resident-probe.mjs /
// header-switch-probe.mjs and the browser worker (public/workers/lean.worker.js):
//   own shared Memory64 (browser policy: 2 GiB initial when an umbrella region
//   is loaded, else 256 MiB; 6 GiB maximum) -> full Lean init ->
//   _lean_wasm_load_snapshot_mem(ptr, bytes, 1n) for every raw snapshot, in
//   order -> mark_preinitialized -> stdin ring -> per-byte stdout tap feeding
//   the product's LspFrameDecoder -> callMain(["--worker",
//   "-Dserver.reportDelayMs=0"]).
// Client frames obey the worker front door's rules (public/workers/
// lsp-front-door.js): the FileWorker reads `initialize` then `didOpen`
// directly (never answers initialize; no `initialized`), and only the
// allowlisted notifications are forwarded (anything else would kill it).
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { QED64_SRC } from './lib.mjs';

// JSON with lossless UInt64 (sessionId, javascriptHash)
export const parseJson = (s) => JSON.parse(s, (k, v, ctx) =>
  (typeof v === 'number' && Number.isInteger(v) && !Number.isSafeInteger(v)) ? JSON.rawJSON(ctx.source) : v);

const FORWARDED_NOTIFICATIONS = new Set(['textDocument/didChange', '$/cancelRequest', '$/lean/staleDependency',
  '$/lean/rpc/release', '$/lean/rpc/keepAlive']);
const MiB = 1048576, GiB = 1073741824, PAGE = 65536;

class ClientBase {
  constructor(log) {
    this.id = 0; this.pending = new Map(); this.diags = new Map(); this.progress = new Map();
    this.header = null; this.headerHistory = []; this.stderr = []; this.log = log; this.dead = null;
    this.serverRequests = [];
  }
  dispatch(msg) {
    if (msg.id !== undefined && msg.method) { // server -> client request: answer like vscode-languageclient
      this.serverRequests.push(msg.method); this.send({ id: msg.id, result: null }); return;
    }
    if (msg.id !== undefined) {
      const p = this.pending.get(msg.id); if (!p) return; this.pending.delete(msg.id);
      msg.error ? p.reject(Object.assign(new Error(`${p.method}: ${msg.error.message}`), { lsp: msg.error })) : p.resolve(msg.result);
      return;
    }
    if (msg.method === 'textDocument/publishDiagnostics') this.diags.set(msg.params.uri, msg.params);
    else if (msg.method === '$/lean/fileProgress') this.progress.set(msg.params.textDocument.uri, msg.params);
    else if (msg.method === '$/qed64/headerStatus') { this.header = msg.params; this.headerHistory.push(msg.params); }
    if (process.env.LSP_DEBUG && msg.method) console.error('<-', msg.method, JSON.stringify(msg.params).slice(0, 300));
  }
  request(method, params, timeoutMs = 600000) {
    if (this.dead) return Promise.reject(new Error(`server dead: ${this.dead}`));
    const id = ++this.id;
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => { this.pending.delete(id); reject(new Error(`timeout ${method}`)); }, timeoutMs);
      this.pending.set(id, { method, resolve: (v) => { clearTimeout(t); resolve(v); }, reject: (e) => { clearTimeout(t); reject(e); } });
      this.send({ id, method, params });
    });
  }
  fail(why) {
    this.dead = why;
    for (const p of this.pending.values()) p.reject(new Error(`server died: ${why}`));
    this.pending.clear();
  }
}

// ---------------------------------------------------------------------------
// wasm: the pinned QED64 runtime, in-process
// ---------------------------------------------------------------------------
export class WasmLsp extends ClientBase {
  /** opts: {artifact, lib, snaps: [paths], initialBytes?, maximumBytes?, log, wasmLog (file)} */
  static async boot(opts) {
    await import(pathToFileURL(path.join(QED64_SRC, 'public/workers/lsp-frames.js')).href); // globalThis.Qed64LspFrames
    const c = new WasmLsp(opts.log);
    await c.#boot(opts);
    return c;
  }
  #M = null; #ring = null; #mem = null; #frames = null; #CAP = 1 << 20; #wasmLogFd = null;
  timings = {}; loads = []; memory = {}; stdoutLines = [];

  #wlog(line) { if (this.#wasmLogFd !== null) fs.writeSync(this.#wasmLogFd, line + '\n'); }

  #boot(opts) {
    // the REAL path: $W/stage1 is a pin link (scripts/lib/pins.mjs) and Node loads lean.js from its realpath, so the
    // runtime looks for its own files (bin/) under the realpath; mounting the link path instead failed with
    // "no such file or directory (error code: 44) file: …/runtimes/<buildId>/stage1/bin" (multi-pin lane, 2026-10-02)
    const artifactDir = fs.realpathSync(path.resolve(opts.artifact)), lib = fs.realpathSync(path.resolve(opts.lib));
    const leanJs = path.join(artifactDir, 'bin/lean.js');
    if (!fs.existsSync(leanJs)) throw new Error(`${leanJs} not found`);
    if (opts.wasmLog) this.#wasmLogFd = fs.openSync(opts.wasmLog, 'w');
    const umbrella = opts.snaps.some((s) => path.basename(s) !== 'init.snap');
    const initialBytes = opts.initialBytes ?? (umbrella ? 2048 * MiB : 256 * MiB);
    const maximumBytes = opts.maximumBytes ?? 6 * GiB;
    this.#mem = new WebAssembly.Memory({ address: 'i64', initial: BigInt(initialBytes / PAGE), maximum: BigInt(maximumBytes / PAGE), shared: true });
    this.memory = { initialBytes, maximumBytes };
    const { LspFrameDecoder } = globalThis.Qed64LspFrames;
    this.#frames = new LspFrameDecoder({
      onFrame: (body) => { try { this.dispatch(parseJson(body)); } catch (e) { this.log(`unparseable frame: ${body.slice(0, 80)} (${e.message})`); } },
      onJunk: (line) => this.#wlog(`stdout-junk: ${line}`),
    });
    const t0 = performance.now();
    return new Promise((resolve, reject) => {
      process.chdir('/');
      process.argv[1] = '/bin/lean';
      const self = this;
      globalThis.Module = {
        noInitialRun: true,
        wasmMemory: this.#mem,
        INITIAL_MEMORY: initialBytes,
        locateFile: (f) => path.join(path.dirname(leanJs), f),
        mainScriptUrlOrBlob: leanJs,
        print: (t) => { self.stdoutLines.push(String(t)); self.#wlog(`stdout: ${t}`); },
        printErr: (t) => { const s = String(t); self.stderr.push(s); self.#wlog(`stderr: ${s}`); if (/\[WASM LSP\]/.test(s)) self.log(`wasm: ${s.slice(0, 200)}`); },
        preRun: [function mount() {
          const FS = globalThis.Module.FS; const NODEFS = FS.filesystems.NODEFS;
          const mkdirTree = (p) => { let c = ''; for (const part of p.split('/').filter(Boolean)) { c += `/${part}`; try { FS.mkdir(c); } catch {} } };
          for (const dir of ['/lib/lean', '/bin', '/workspace']) mkdirTree(dir);
          FS.mount(NODEFS, { root: lib }, '/lib/lean');
          // PROXY_TO_PTHREAD: the pthread derives the app path from HOST argv;
          // mirror the stage1 tree at its own host path (resident-probe.mjs).
          mkdirTree(artifactDir);
          FS.mount(NODEFS, { root: artifactDir }, artifactDir);
          globalThis.Module.ENV.LEAN_PATH = '/lib/lean';
          globalThis.Module.ENV.LEAN_SYSROOT = '/';
          FS.chdir('/workspace');
        }],
        onRuntimeInitialized() {
          try {
            const M = self.#M = globalThis.Module;
            M._lean_initialize_runtime_module();
            M._lean_initialize();
            M._lean_io_mark_end_initialization();
            if (M._lean_init_task_manager) M._lean_init_task_manager();
            if (M._lean_enable_initializer_execution) M._lean_enable_initializer_execution();
            const sp = M._lean_init_search_path();
            const tagOf = (res) => Number(M.getValue(Number(res) + 7, 'i8')) & 0xff;
            const valOf = (res) => BigInt(M.getValue(Number(res) + 8, 'i64'));
            if (tagOf(sp) !== 0) throw new Error('lean_init_search_path failed');
            self.timings.initMs = Math.round(performance.now() - t0);
            for (const snap of opts.snaps) {
              const total = fs.statSync(snap).size;
              const ts = performance.now();
              const raw = M._malloc(BigInt(total));
              const ptr = Number(raw);
              if (!ptr) throw new Error(`malloc(${total}) failed for ${snap}`);
              const fd = fs.openSync(snap, 'r'); const CH = 64 * MiB; const b = new Uint8Array(CH); let at = 0;
              const h = createHash('sha256'); // digest of the bytes actually staged into wasm memory
              while (at < total) {
                const n = fs.readSync(fd, b, 0, Math.min(CH, total - at), at);
                if (n <= 0) throw new Error(`short read at ${at}/${total} for ${snap}`);
                h.update(b.subarray(0, n));
                new Uint8Array(self.#mem.buffer, ptr + at, n).set(b.subarray(0, n)); // re-take: growth swaps the buffer
                at += n;
              }
              const loadedSha256 = h.digest('hex');
              fs.closeSync(fd);
              const tl = performance.now();
              const lr = M._lean_wasm_load_snapshot_mem(BigInt(ptr), BigInt(total), 1n); // bit 0: [init] replay (worker default)
              const tag = tagOf(lr); const v = valOf(lr); const scalar = (v & 1n) === 1n ? v >> 1n : null;
              const ok = tag === 0 && (scalar === null || scalar === 0n);
              const cached = [...self.stderr, ...self.stdoutLines].reverse().find((l) => /cached env for/.test(l)) ?? null;
              const ent = { snap, bytes: total, sha256: loadedSha256, stageMs: Math.round(tl - ts), loadMs: Math.round(performance.now() - tl), tag, scalar: scalar === null ? null : Number(scalar), ok,
                seededKey: cached ? /#\[([^\]]*)\]/.exec(cached)?.[1].split(',').map((s) => s.trim()) : null };
              self.loads.push(ent);
              self.log(`snapshot ${path.basename(snap)}: ${total} bytes, sha256 ${loadedSha256.slice(0, 16)}, load ${ent.loadMs} ms, tag=${tag} scalar=${ent.scalar} seeded #[${ent.seededKey?.join(', ')}]`);
              if (!ok) throw new Error(`snapshot load failed: ${snap} (tag ${tag}, scalar ${scalar})`);
            }
            self.memory.afterLoadsHeapBytes = self.#mem.buffer.byteLength;
            M._lean_wasm_shell_mark_preinitialized();
            const ringRaw = M._malloc(BigInt(16 + self.#CAP));
            self.#ring = Number(ringRaw);
            const st = M._lean_browser64_configure_input_ring(BigInt(self.#ring), self.#CAP);
            if (Number(st) !== 0) throw new Error(`stdin ring rejected: ${st}`);
            // per-byte stdout tap (resident-probe.mjs installStdoutTap / worker W1)
            const tty = globalThis.TTY?.ttys?.[M.FS.makedev(5, 0)];
            if (!tty?.ops?.put_char) throw new Error('stdout tap: TTY for /dev/stdout not in scope');
            const orig = tty.ops;
            tty.ops = { ...orig, put_char(t, val) { if (t.output?.length > 0) orig.fsync(t); if (val !== null) self.#frames.push(val); } };
            self.timings.bootMs = Math.round(performance.now() - t0);
            M.callMain(['--worker', '-Dserver.reportDelayMs=0']);
            resolve();
          } catch (e) { reject(e); }
        },
        onExit: (code) => { self.log(`lean --worker exited with code ${code}`); self.fail(`exit ${code}`); },
        onAbort: (what) => { self.log(`ABORT: ${what}`); self.fail(`abort ${what}`); reject(new Error(`abort: ${what}`)); },
      };
      globalThis.require = createRequire(leanJs);
      globalThis.__filename = '/bin/lean.js';
      globalThis.__dirname = '/bin';
      vm.runInThisContext(fs.readFileSync(leanJs, 'utf8'), { filename: leanJs });
    });
  }

  #views() {
    const buf = this.#mem.buffer;
    return { ctrl: new Int32Array(buf, this.#ring, 4), bytes: new Uint8Array(buf, this.#ring + 16, this.#CAP) };
  }
  #queue = []; #pumping = false;
  #ringWrite(payload) {
    this.#queue.push(payload);
    if (!this.#pumping) this.#pump();
  }
  #pump() {
    this.#pumping = true;
    while (this.#queue.length) {
      const payload = this.#queue[0];
      payload.off ??= 0;
      const { ctrl, bytes } = this.#views();
      const read = Atomics.load(ctrl, 0), write = Atomics.load(ctrl, 1);
      const free = (read - write - 1 + this.#CAP) % this.#CAP;
      if (free === 0) { setTimeout(() => this.#pump(), 2); return; }
      const n = Math.min(free, this.#CAP - write, payload.bytes.length - payload.off);
      bytes.set(payload.bytes.subarray(payload.off, payload.off + n), write);
      payload.off += n;
      Atomics.store(ctrl, 1, (write + n) % this.#CAP);
      Atomics.add(ctrl, 3, 1); Atomics.notify(ctrl, 3);
      if (payload.off === payload.bytes.length) this.#queue.shift();
    }
    this.#pumping = false;
  }
  send(obj) {
    const body = Buffer.from(JSON.stringify({ jsonrpc: '2.0', ...obj }), 'utf8');
    this.#ringWrite({ bytes: Buffer.concat([Buffer.from(`Content-Length: ${body.length}\r\n\r\n`), body]) });
  }
  notify(method, params) {
    if (!FORWARDED_NOTIFICATIONS.has(method) && method !== 'textDocument/didOpen') { this.log(`front-door rule: dropping notification ${method}`); return; }
    this.send({ method, params });
  }
  /** The opening sequence (front door): initialize, then didOpen, nothing between. */
  open(initializeParams, textDocument) {
    this.send({ id: ++this.id, method: 'initialize', params: initializeParams }); // never answered by the FileWorker
    this.send({ method: 'textDocument/didOpen', params: { textDocument } });
  }
  get frameStats() { return this.#frames?.stats; }
  close() {
    try { const { ctrl } = this.#views(); Atomics.store(ctrl, 2, 1); Atomics.add(ctrl, 3, 1); Atomics.notify(ctrl, 3); } catch {}
    if (this.#wasmLogFd !== null) { try { fs.closeSync(this.#wasmLogFd); } catch {} this.#wasmLogFd = null; }
  }
}

// ---------------------------------------------------------------------------
// native: stock `lean --server` (for control goldens / differential runs only)
// ---------------------------------------------------------------------------
export class NativeLsp extends ClientBase {
  constructor({ lean, env, cwd, log }) {
    super(log);
    this.proc = spawn(lean, ['--server'], { env, cwd, stdio: ['pipe', 'pipe', 'pipe'] });
    this.buf = Buffer.alloc(0);
    this.proc.stdout.on('data', (d) => this.#onData(d));
    this.proc.stderr.on('data', (d) => this.stderr.push(d.toString()));
    this.proc.on('exit', (c, s) => this.fail(`exit ${c} ${s}`));
  }
  send(msg) {
    const body = Buffer.from(JSON.stringify({ jsonrpc: '2.0', ...msg }), 'utf8');
    this.proc.stdin.write(`Content-Length: ${body.length}\r\n\r\n`); this.proc.stdin.write(body);
  }
  #onData(d) {
    this.buf = Buffer.concat([this.buf, d]);
    for (;;) {
      const h = this.buf.indexOf('\r\n\r\n'); if (h < 0) return;
      const n = Number(/Content-Length: (\d+)/i.exec(this.buf.subarray(0, h).toString())[1]);
      if (this.buf.length < h + 4 + n) return;
      const msg = parseJson(this.buf.subarray(h + 4, h + 4 + n).toString('utf8'));
      this.buf = this.buf.subarray(h + 4 + n); this.dispatch(msg);
    }
  }
  notify(method, params) { this.send({ method, params }); }
  async open(initializeParams, textDocument) {
    await this.request('initialize', initializeParams);
    this.notify('initialized', {});
    this.notify('textDocument/didOpen', { textDocument });
  }
  close() { try { this.proc.kill('SIGKILL'); } catch {} }
}
