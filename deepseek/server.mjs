#!/usr/bin/env node
/**
 * DeepSeek web-page bridge — local service.
 *
 * Two sides:
 *   - HTTP  (this file, port 8765 by default): what Neovim (or curl) talks to.
 *       POST /send    {"text": "...", "timeout_ms": 15000}
 *         -> {"ok": true,  "delivered": true, "bytes": 1234, "page": "..."}
 *         -> {"ok": false, "error": "..."}
 *       GET  /status  -> {"ok": true, "version": 1, "pages": [...], "busy": false}
 *       GET  /        -> a tiny human-readable status page
 *
 *   - WebSocket (same port, path is irrelevant): one connection per open
 *     deepseek.com tab, created by extension/content.js. The service pushes
 *     {"type":"send","id":...,"text":...} down it; the page types the text into
 *     the composer, presses send, and answers {"type":"sent","id":...} (or
 *     {"type":"error","id":...,"error":"..."}). The answer itself is never sent
 *     back over this service — read it in the browser tab.
 *
 * No dependencies: the WebSocket server below is a minimal RFC 6455
 * implementation, so `node server.mjs` is all you need.
 *
 * Usage:
 *   node server.mjs [--port 8765] [--host 127.0.0.1] [--log bridge.log]
 *   DEEPSEEK_BRIDGE_PORT=9000 DEEPSEEK_BRIDGE_LOG=bridge.log node server.mjs
 */

import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";

// ---------------------------------------------------------------------------
// configuration
// ---------------------------------------------------------------------------

const argv = process.argv.slice(2);
const argValue = (name, fallback) => {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
};

const HOST = argValue("--host", process.env.DEEPSEEK_BRIDGE_HOST || "127.0.0.1");
const PORT = Number(argValue("--port", process.env.DEEPSEEK_BRIDGE_PORT || 8765));
const PROTOCOL_VERSION = 1;
const MAX_BODY_BYTES = 16 * 1024 * 1024;
// how long the browser page gets to type the text and press send
const DEFAULT_TIMEOUT_MS = 15_000;

const startedAt = Date.now();
// Where the service appends its own output, if anywhere. Neovim passes this
// when it starts the service for you: a detached child gets no console, and
// redirecting its stdio with `jobstart` is not portable.
const LOG_FILE = argValue("--log", process.env.DEEPSEEK_BRIDGE_LOG || "");

const stamp = () => `[${new Date().toISOString().slice(11, 19)}]`;

function emit(write, text) {
  write(text);
  if (!LOG_FILE) return;
  try {
    fs.appendFileSync(LOG_FILE, text + "\n");
  } catch {
    /* a log file that cannot be written must never take the bridge down */
  }
}

const log = (...args) => emit((t) => console.log(t), `${stamp()} ${args.join(" ")}`);
const logError = (...args) => emit((t) => console.error(t), `${stamp()} ${args.join(" ")}`);

// ---------------------------------------------------------------------------
// minimal WebSocket server (RFC 6455, server side)
// ---------------------------------------------------------------------------

const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

const OP_CONT = 0x0;
const OP_TEXT = 0x1;
const OP_BIN = 0x2;
const OP_CLOSE = 0x8;
const OP_PING = 0x9;
const OP_PONG = 0xa;

/** Encode a single unmasked (server -> client) frame. */
function encodeFrame(opcode, payload) {
  const len = payload.length;
  let header;
  if (len < 126) {
    header = Buffer.alloc(2);
    header[1] = len;
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  header[0] = 0x80 | opcode;
  return Buffer.concat([header, payload]);
}

class WSConnection {
  constructor(socket) {
    this.socket = socket;
    this.buf = Buffer.alloc(0);
    this.fragments = [];
    this.fragOpcode = 0;
    this.closed = false;
    this.url = null;
    this.onMessage = () => {};
    this.onClose = () => {};

    socket.on("data", (chunk) => this.#feed(chunk));
    socket.on("error", () => this.#destroy());
    socket.on("close", () => this.#destroy());
  }

  #feed(chunk) {
    this.buf = Buffer.concat([this.buf, chunk]);
    for (;;) {
      const frame = this.#decode();
      if (!frame) return;
      this.#handle(frame);
      if (this.closed) return;
    }
  }

  /** @returns {{fin:boolean,opcode:number,payload:Buffer}|null} */
  #decode() {
    const b = this.buf;
    if (b.length < 2) return null;

    const fin = (b[0] & 0x80) !== 0;
    const opcode = b[0] & 0x0f;
    const masked = (b[1] & 0x80) !== 0;
    let len = b[1] & 0x7f;
    let offset = 2;

    if (len === 126) {
      if (b.length < offset + 2) return null;
      len = b.readUInt16BE(offset);
      offset += 2;
    } else if (len === 127) {
      if (b.length < offset + 8) return null;
      len = Number(b.readBigUInt64BE(offset));
      offset += 8;
    }

    let mask = null;
    if (masked) {
      if (b.length < offset + 4) return null;
      mask = b.subarray(offset, offset + 4);
      offset += 4;
    }

    if (b.length < offset + len) return null;

    const payload = Buffer.from(b.subarray(offset, offset + len));
    if (mask) for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];

    this.buf = b.subarray(offset + len);
    return { fin, opcode, payload };
  }

  #handle({ fin, opcode, payload }) {
    switch (opcode) {
      case OP_PING:
        this.#write(encodeFrame(OP_PONG, payload));
        return;
      case OP_PONG:
        return;
      case OP_CLOSE:
        this.#write(encodeFrame(OP_CLOSE, Buffer.alloc(0)));
        this.#destroy();
        return;
      case OP_TEXT:
      case OP_BIN:
        if (fin) {
          this.#deliver(payload);
        } else {
          this.fragments = [payload];
          this.fragOpcode = opcode;
        }
        return;
      case OP_CONT:
        if (this.fragments.length === 0) return;
        this.fragments.push(payload);
        if (fin) {
          const whole = Buffer.concat(this.fragments);
          this.fragments = [];
          if (this.fragOpcode === OP_TEXT) this.#deliver(whole);
        }
        return;
      default:
        this.#destroy();
    }
  }

  #deliver(payload) {
    let data;
    try {
      data = JSON.parse(payload.toString("utf8"));
    } catch {
      log("page sent non-JSON payload, ignored");
      return;
    }
    this.onMessage(data);
  }

  #write(buffer) {
    if (this.closed || this.socket.destroyed) return;
    try {
      this.socket.write(buffer);
    } catch {
      this.#destroy();
    }
  }

  #destroy() {
    if (this.closed) return;
    this.closed = true;
    this.socket.destroy();
    this.onClose(this);
  }

  send(message) {
    this.#write(encodeFrame(OP_TEXT, Buffer.from(JSON.stringify(message), "utf8")));
  }

  destroy() {
    this.#destroy();
  }
}

// ---------------------------------------------------------------------------
// page registry + request routing
// ---------------------------------------------------------------------------

/** @type {Set<WSConnection>} */
const pages = new Set();
/** @type {Map<string, {resolve:Function,reject:Function,timer:any,page:WSConnection}>} */
const pending = new Map();

/** Settle (and forget) the pending send the page is answering. */
function settle(id, error) {
  const entry = pending.get(id);
  if (!entry) return;
  pending.delete(id);
  clearTimeout(entry.timer);
  if (error) entry.reject(new Error(error));
  else entry.resolve();
}

function onPageMessage(page, msg) {
  switch (msg.type) {
    case "hello":
      page.url = typeof msg.url === "string" ? msg.url : page.url;
      log(`page ready: ${page.url} (${pages.size} connected)`);
      return;
    case "sent":
      if (pending.has(msg.id)) log(`  ${msg.id.slice(0, 8)} typed and sent`);
      settle(msg.id);
      return;
    case "error":
      settle(msg.id, String(msg.error || "the page reported an error"));
      return;
    default:
      log(`unknown message type from page: ${msg.type}`);
  }
}

function onPageClose(page) {
  pages.delete(page);
  log(`page disconnected (${pages.size} left)`);
  for (const [id, entry] of [...pending]) {
    if (entry.page !== page) continue;
    settle(id, "the DeepSeek tab was closed or reloaded while sending");
  }
}

/** Hand `text` to the browser page; resolves once it has pressed send. */
function deliver(text, timeoutMs) {
  return new Promise((resolve, reject) => {
    const page = [...pages].find((p) => !p.closed);
    if (!page) {
      reject(
        new Error(
          "no DeepSeek page connected — load deepseek/extension in the browser " +
            "(edge://extensions -> Load unpacked) and keep a chat.deepseek.com tab open",
        ),
      );
      return;
    }
    if (pending.size > 0) {
      reject(new Error(`the page is still sending ${pending.size} other request(s)`));
      return;
    }

    const id = crypto.randomUUID();
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(
        new Error(`the DeepSeek tab did not confirm the send within ${Math.round(timeoutMs / 1000)}s`),
      );
    }, timeoutMs);

    pending.set(id, { resolve, reject, timer, page });
    log(`send ${id.slice(0, 8)} (${text.length} bytes) -> ${page.url}`);
    page.send({ type: "send", id, text });
  });
}

// ---------------------------------------------------------------------------
// HTTP server
// ---------------------------------------------------------------------------

function sendJSON(res, status, obj) {
  const body = Buffer.from(JSON.stringify(obj), "utf8");
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": body.length,
    "Connection": "close",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (c) => {
      size += c.length;
      if (size > MAX_BODY_BYTES) {
        reject(new Error("request body too large"));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

const STATUS_PAGE = (port) => `<!doctype html>
<meta charset="utf-8">
<title>DeepSeek bridge</title>
<style>
  body { font: 14px/1.6 system-ui, sans-serif; max-width: 46em; margin: 3em auto; padding: 0 1em; }
  code, pre { background: #f4f4f4; padding: .1em .3em; border-radius: 3px; }
  pre { padding: .8em; overflow-x: auto; }
</style>
<h1>DeepSeek bridge</h1>
<p id="status">checking…</p>
<h2>Usage</h2>
<pre>curl -s http://127.0.0.1:${port}/send \\
  -H 'content-type: application/json' \\
  -d '{"text":"Say hi in five words."}'</pre>
<p>The text is typed into the DeepSeek tab; the answer appears there.</p>
<p>In Neovim: <code>:InterlacedDeepseek</code></p>
<script>
  fetch("/status")
    .then((r) => r.json())
    .then((s) => {
      document.getElementById("status").textContent = s.pages.length
        ? "Connected to " + s.pages.join(", ")
        : "No browser page connected. Load the extension and open chat.deepseek.com.";
    });
</script>`;

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || "127.0.0.1"}`);

  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "content-type",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Connection": "close",
    });
    res.end();
    return;
  }

  if (req.method === "GET" && url.pathname === "/status") {
    sendJSON(res, 200, {
      ok: true,
      version: PROTOCOL_VERSION,
      pages: [...pages].filter((p) => !p.closed).map((p) => p.url || "(unknown url)"),
      busy: pending.size > 0,
      uptime_ms: Date.now() - startedAt,
    });
    return;
  }

  if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
    const body = Buffer.from(STATUS_PAGE(PORT), "utf8");
    res.writeHead(200, {
      "Content-Type": "text/html; charset=utf-8",
      "Content-Length": body.length,
      "Connection": "close",
    });
    res.end(body);
    return;
  }

  if (req.method === "POST" && (url.pathname === "/send" || url.pathname === "/")) {
    let raw;
    try {
      raw = await readBody(req);
    } catch (err) {
      sendJSON(res, 413, { ok: false, error: err.message });
      return;
    }

    let payload;
    try {
      payload = JSON.parse(raw);
    } catch {
      sendJSON(res, 400, { ok: false, error: "request body must be JSON" });
      return;
    }

    const text = typeof payload.text === "string" ? payload.text : "";
    if (text.trim() === "") {
      sendJSON(res, 400, { ok: false, error: "`text` must be a non-empty string" });
      return;
    }

    const timeoutMs =
      Number.isFinite(payload.timeout_ms) && payload.timeout_ms > 0
        ? Math.min(payload.timeout_ms, 120_000)
        : DEFAULT_TIMEOUT_MS;

    const t = Date.now();
    try {
      await deliver(text, timeoutMs);
      log(`delivered in ${((Date.now() - t) / 1000).toFixed(1)}s — read the answer in the tab`);
      sendJSON(res, 200, {
        ok: true,
        delivered: true,
        bytes: Buffer.byteLength(text, "utf8"),
        elapsed_ms: Date.now() - t,
        page: [...pages][0]?.url ?? null,
      });
    } catch (err) {
      log(`failed: ${err.message}`);
      sendJSON(res, 200, { ok: false, error: err.message, elapsed_ms: Date.now() - t });
    }
    return;
  }

  sendJSON(res, 404, { ok: false, error: `no route for ${req.method} ${url.pathname}` });
});

server.on("upgrade", (req, socket) => {
  const key = req.headers["sec-websocket-key"];
  if (!key || (req.headers.upgrade || "").toLowerCase() !== "websocket") {
    socket.destroy();
    return;
  }

  const accept = crypto
    .createHash("sha1")
    .update(key + WS_GUID)
    .digest("base64");

  socket.write(
    [
      "HTTP/1.1 101 Switching Protocols",
      "Upgrade: websocket",
      "Connection: Upgrade",
      `Sec-WebSocket-Accept: ${accept}`,
      "\r\n",
    ].join("\r\n"),
  );

  socket.setNoDelay(true);

  const conn = new WSConnection(socket);
  conn.onMessage = (msg) => onPageMessage(conn, msg);
  conn.onClose = () => onPageClose(conn);
  pages.add(conn);
  log(`browser page connected (${pages.size} total)`);
});

server.listen(PORT, HOST, () => {
  log(`DeepSeek bridge listening on http://${HOST}:${PORT}`);
  if (LOG_FILE) log(`logging to ${LOG_FILE}`);
  log("  the browser extension connects over WebSocket on the same port");
  log(`  POST /send  GET /status   (see http://${HOST}:${PORT}/ for details)`);
});

server.on("error", (err) => {
  if (err.code === "EADDRINUSE") {
    logError(
      `port ${PORT} is already in use — another bridge is probably running. ` +
        `Start this one with a different --port, or stop the other one.`,
    );
  } else {
    logError(err);
  }
  process.exit(1);
});

const shutdown = () => {
  log("shutting down");
  for (const [, entry] of pending) clearTimeout(entry.timer);
  pending.clear();
  for (const page of pages) page.destroy();
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 500).unref();
};
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
