# DeepSeek bridge

A local service that types text into a DeepSeek chat page running in your
browser and presses send. The answer is **not** sent back: it appears in the
browser tab, where you read it. `interlaced.nvim` uses it to push the window you
are aligning into DeepSeek (`:InterlacedDeepseek`), but it is useful on its own
from any script that speaks HTTP.

```
  Neovim / curl              node server.mjs                browser tab
  ─────────────              ────────────────               ───────────
  POST /send       ────────▶  HTTP  ⇄  WebSocket  ────────▶  content.js
  { "text": ... }  ◀────────  { "ok": true, "delivered": … }  (types, sends)
                                        ◀────────────────────  you read the answer
```

It is deliberately dependency-free: `server.mjs` contains its own small
WebSocket server, so there is nothing to `npm install`.

## Requirements

+ **Node.js >= 18** (tested on v26)
+ **Edge or Chrome** (any Chromium browser that can load an unpacked extension)

## Setup

### 1. Start the service

```sh
node deepseek/server.mjs                                    # listens on http://127.0.0.1:8765
node deepseek/server.mjs --port 9000
node deepseek/server.mjs --log bridge.log                    # also append output to a file
```

Keep it running in the background. Neovim can also start it for you — see
`:InterlacedDeepseek` below — in which case it appends its output to a file (a
temp file, or `vim.g.interlaced.deepseek.log_file`).

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

curl -s http://127.0.0.1:8765/send \
  -H 'content-type: application/json' \
  -d '{"text":"Say hi in five words."}'
# {"ok":true,"delivered":true,"bytes":20,"elapsed_ms":812,"page":"https://chat.deepseek.com/..."}
```

The text should now be in the DeepSeek tab, sent — switch to the browser and
watch it answer.

`http://127.0.0.1:8765/` renders a small status page in the browser if you
prefer clicking to curling.

## HTTP API

| route | body | returns |
| - | - | - |
| `POST /send` | `{"text": string, "timeout_ms"?: number}` | `{"ok":true,"delivered":true,"bytes":number,"page":string,"elapsed_ms":number}` or `{"ok":false,"error":string}` |
| `GET /status` | — | `{"ok":true,"pages":[url...],"busy":boolean,"uptime_ms":number}` |
| `GET /` | — | status page |

`POST /send` returns as soon as the page has typed the text and pressed send —
usually under a second. `timeout_ms` only bounds that step (default 15000, at
most 120000); it has nothing to do with how long DeepSeek takes to answer, since
the answer never comes back through this service. The connection is closed after
each response, so plain `curl` / a raw TCP client can read it to EOF.

## Fixing the page selectors

DeepSeek ships obfuscated, often-changing class names. Everything they depend
on lives in one place at the top of `extension/content.js`:

```js
const CFG = {
  host: "127.0.0.1",
  ports: [8765, 8766, 8767],
  selectors: {
    sendContainer: '[class~="bf38813a"]',
    input: ["textarea#chat-input", 'textarea[placeholder]', "textarea", '[contenteditable="true"]'],
  },
  confirmMs: 3000,
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

Sending is confirmed by the composer emptying out (`confirmMs`, 3000 ms by
default) — DeepSeek clears the box once the message is on its way. If the click
seems to have done nothing, the script falls back to pressing `Enter`, and only
reports a failure if neither worked.

## Troubleshooting

| symptom | cause |
| - | - |
| `no DeepSeek page connected` | extension not loaded, DeepSeek tab closed, or the tab was open before the extension was loaded — reload it |
| extension never appears in `/status` | wrong port (both ends must agree), or the service is not running |
| `could not send the message — the composer or send button selector needs updating` | deepseek.com changed its markup; update `selectors` |
| `the DeepSeek tab did not confirm the send within 15s` | the page is stuck (e.g. a modal is open) — check the tab, or raise `timeout_ms` |
| `the page is still sending N other request(s)` | a previous `/send` has not been confirmed yet; one page sends one message at a time |
| the text arrived but was not sent | raise `confirmMs` if DeepSeek is slow to accept, or check the console log for what the click hit |

## Configuration

| setting | where | default |
| - | - | - |
| port | `--port`, `DEEPSEEK_BRIDGE_PORT`, `CFG.ports` in `content.js` | 8765 |
| host | `--host`, `DEEPSEEK_BRIDGE_HOST` | 127.0.0.1 |
| log file | `--log`, `DEEPSEEK_BRIDGE_LOG` | none |
| send confirmation timeout | `timeout_ms` in the request body | 15 s |
| composer-cleared window | `CFG.confirmMs` in `content.js` | 3000 ms |

Neovim passes `--log` when it starts the service itself: a process that has to
outlive the editor cannot inherit its standard output, so the service writes its
own log instead.

The service binds to loopback only; it is not reachable from your network.
