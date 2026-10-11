# DeepSeek bridge

A local service that hands text to a DeepSeek chat page running in your browser
and gives back DeepSeek's answer. `interlaced.nvim` uses it to ask about the
window you are aligning (`:InterlacedDeepseek`), but it is useful on its own
from any script that speaks HTTP.

```
  Neovim / curl              node server.mjs                browser tab
  ─────────────              ────────────────               ───────────
  POST /ask        ────────▶  HTTP  ⇄  WebSocket  ────────▶  content.js
  { "text": ... }  ◀────────  { "ok": true, "result": ... }  (types, sends,
                                                              waits, reads)
```

It is deliberately dependency-free: `server.mjs` contains its own small
WebSocket server, so there is nothing to `npm install`.

## Requirements

+ **Node.js >= 18** (tested on v26)
+ **Edge or Chrome** (any Chromium browser that can load an unpacked extension)

## Setup

### 1. Start the service

```sh
node deepseek/server.mjs          # listens on http://127.0.0.1:8765
node deepseek/server.mjs --port 9000
```

Keep it running in the background. Neovim can also start it for you — see
`:InterlacedDeepseek` below.

### 2. Load the extension

1. Open `edge://extensions` (or `chrome://extensions`).
2. Turn on **Developer mode**.
3. **Load unpacked** → pick the `deepseek/extension` folder.
4. Open (or reload) <https://chat.deepseek.com> and log in.

The content script connects to the service on load. With a DeepSeek tab open,
`GET /status` should list it.

### 3. Check that the two ends are talking

```sh
curl -s http://127.0.0.1:8765/status
# {"ok":true,"version":1,"pages":["https://chat.deepseek.com/a/chat/s/..."],"busy":false}

curl -s http://127.0.0.1:8765/ask \
  -H 'content-type: application/json' \
  -d '{"text":"Reply with exactly: hello from the bridge"}'
# {"ok":true,"result":"hello from the bridge","elapsed_ms":4311,...}
```

`http://127.0.0.1:8765/` renders a small status page in the browser if you
prefer clicking to curling.

## HTTP API

| route | body | returns |
| - | - | - |
| `POST /ask` | `{"text": string, "timeout_ms"?: number}` | `{"ok":true,"result":string,"elapsed_ms":number}` or `{"ok":false,"error":string}` |
| `GET /status` | — | `{"ok":true,"pages":[url...],"busy":boolean,"uptime_ms":number}` |
| `GET /` | — | status page |

`POST /ask` answers on the same connection and then closes it, so plain
`curl` / a raw TCP client can read it to EOF.

## How it knows DeepSeek has finished

Waiting for a fixed delay is fragile, so `extension/content.js` combines
several signals and requires all of them to agree:

1. **A new reply node appeared.** The message nodes (`.ds-message`) present
   before sending are remembered; the answer must be a node that was not there
   before, is not the echo of the prompt just sent, and is not a re-render of an
   older message. This also fixes the "read the last message" bug where the
   previous answer would be picked up instead of the new one.
2. **The text stopped changing.** The reply's text is polled every 250 ms; it
   must be unchanged for `stableMs` (1200 ms) before it counts as finished.
   That is the load-bearing signal.
3. **No "stop generating" control is visible.** While streaming, DeepSeek
   shows a stop button; when it is gone, generation is over.
4. **The send button is enabled again.** It is disabled while a reply streams.

Rule 1 decides *when to start* reading, rules 2–4 decide *when to stop*. If a
reply ever comes back truncated, raise `stableMs`; if it is too slow, lower it.

## Fixing the page selectors

DeepSeek ships obfuscated, often-changing class names. Everything they depend
on lives in one place at the top of `extension/content.js`:

```js
const CFG = {
  host: "127.0.0.1",
  ports: [8765, 8766, 8767],
  selectors: {
    message: '[class~="ds-message"]',
    sendContainer: '[class~="bf38813a"]',
    input: ["textarea#chat-input", 'textarea[placeholder]', "textarea", '[contenteditable="true"]'],
  },
  pollMs: 250,
  stableMs: 1200,
  ...
};
```

Find the new class name in DevTools, put it in `selectors`, and reload the
page. The content script logs every step under the `[deepseek-bridge]` prefix —
open the browser console on the DeepSeek tab to watch it work.

`input` is a list of candidates tried in order, so a `textarea` composer and a
`contenteditable` composer both work: `textarea`s get the value written through
the native setter (plus `input`/`change` events), `contenteditable`s get
`document.execCommand("insertText", …)` with the caret moved to the end.

## Troubleshooting

| symptom | cause |
| - | - |
| `no DeepSeek page connected` | extension not loaded, DeepSeek tab closed, or the tab was open before the extension was loaded — reload it |
| extension never appears in `/status` | wrong port (both ends must agree), or the service is not running |
| `could not send the message — the composer or send button selector needs updating` | deepseek.com changed its markup; update `selectors` |
| reply comes back cut off | raise `stableMs` (e.g. 2000) |
| `the page is busy with N other request(s)` | a previous `/ask` is still waiting; one page handles one request at a time |

## Configuration

| setting | where | default |
| - | - | - |
| port | `--port`, `DEEPSEEK_BRIDGE_PORT`, `CFG.ports` in `content.js` | 8765 |
| host | `--host`, `DEEPSEEK_BRIDGE_HOST` | 127.0.0.1 |
| request timeout | `timeout_ms` in the request body | 300 s |
| stable-text window | `CFG.stableMs` in `content.js` | 1200 ms |

The service binds to loopback only; it is not reachable from your network.
