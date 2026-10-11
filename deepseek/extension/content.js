/**
 * DeepSeek bridge — page side (content script).
 *
 * Runs inside a chat.deepseek.com tab. Keeps a WebSocket open to the local
 * bridge service (deepseek/server.mjs) and, for every `ask` message it gets,
 * it types the text into the composer, presses send, waits until DeepSeek has
 * *finished* streaming the answer, and sends the answer back.
 *
 * If DeepSeek ever redesigns the page, only the `CFG.selectors` block below
 * should need updating.
 */
(() => {
  "use strict";

  const CFG = {
    host: "127.0.0.1",
    // Tried in order until one accepts the connection. Keep in sync with
    // `--port` / DEEPSEEK_BRIDGE_PORT of server.mjs (8765 is the default).
    ports: [8765, 8766, 8767],

    // --- page selectors (all heuristics; first match wins) ----------------
    selectors: {
      message: '[class~="ds-message"]',
      // the composer row the send button lives in
      sendContainer: '[class~="bf38813a"]',
      input: ["textarea#chat-input", 'textarea[placeholder]', "textarea", '[contenteditable="true"]'],
    },

    // --- stream-completion detection --------------------------------------
    pollMs: 2000, // how often the reply is inspected
    stableMs: 1200, // text unchanged for this long => generation stopped
    startTimeoutMs: 40000, // give up if no reply node appears within this
    sendRetryMs: 3000, // wait this long for the click to take effect
    debug: true,
  };

  const log = (...a) => CFG.debug && console.log("[deepseek-bridge]", ...a);
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const norm = (s) => (s || "").replace(/\s+/g, " ").trim();

  // -----------------------------------------------------------------------
  // page helpers
  // -----------------------------------------------------------------------

  const isVisible = (el) =>
    !!el && (el.getClientRects().length > 0 || el.offsetParent !== null);

  const query = (sel) => {
    try {
      return document.querySelector(sel);
    } catch {
      return null;
    }
  };

  const messages = () => {
    try {
      return Array.from(document.querySelectorAll(CFG.selectors.message));
    } catch {
      return [];
    }
  };

  function findInput() {
    for (const sel of CFG.selectors.input) {
      for (const el of Array.from(document.querySelectorAll(sel))) {
        if (isVisible(el)) return el;
      }
    }
    return null;
  }

  /**
   * Put `text` in the composer the way a user would, so React notices it.
   * Returns nothing; throws when no usable input could be driven.
   */
  async function typeInto(input, text) {
    input.focus();

    const isFormField =
      input.tagName === "TEXTAREA" || input.tagName === "INPUT";

    if (isFormField) {
      const proto =
        input.tagName === "TEXTAREA"
          ? HTMLTextAreaElement.prototype
          : HTMLInputElement.prototype;
      const descriptor = Object.getOwnPropertyDescriptor(proto, "value");
      if (descriptor && descriptor.set) descriptor.set.call(input, text);
      else input.value = text;
      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
      return;
    }

    // contenteditable: put the caret at the end and insert like a keyboard
    // would, which is what `execCommand("insertText")` is good at.
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(input);
    range.collapse(false);
    selection.removeAllRanges();
    selection.addRange(range);

    let inserted = false;
    try {
      inserted = document.execCommand("insertText", false, text);
    } catch {
      inserted = false;
    }
    if (!inserted) {
      input.textContent = text;
      input.dispatchEvent(
        new InputEvent("input", { bubbles: true, data: text, inputType: "insertText" }),
      );
    }
  }

  function simulateClick(el) {
    const opts = { bubbles: true, cancelable: true, view: window, button: 0 };
    for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) {
      const Ctor = type.startsWith("pointer")
        ? window.PointerEvent || MouseEvent
        : MouseEvent;
      try {
        el.dispatchEvent(new Ctor(type, opts));
      } catch {
        /* ignore */
      }
    }
  }

  function pressEnter(el) {
    for (const type of ["keydown", "keypress", "keyup"]) {
      el.dispatchEvent(
        new KeyboardEvent(type, {
          key: "Enter",
          code: "Enter",
          keyCode: 13,
          which: 13,
          bubbles: true,
          cancelable: true,
        }),
      );
    }
  }

  function findSendButton() {
    const container = query(CFG.selectors.sendContainer);
    if (container) {
      // the clickable node is the first child of the last child
      const last = container.lastElementChild;
      const candidate =
        (last && last.firstElementChild) ||
        container.querySelector("button") ||
        container;
      if (candidate) return candidate;
    }
    // fallbacks: anything that announces itself as a send button
    for (const el of Array.from(document.querySelectorAll("button, [role='button'], [class*='ds-icon-button']"))) {
      if (!isVisible(el)) continue;
      const label = [el.getAttribute("aria-label"), el.getAttribute("title"), el.textContent]
        .filter(Boolean)
        .join(" ");
      if (/\b(send|submit)\b|发送/i.test(label)) return el;
    }
    return null;
  }

  /** The "stop generating" affordance, present only while streaming. */
  function findStopButton() {
    for (const el of Array.from(document.querySelectorAll("[class*='ds-icon-button'], button, [role='button']"))) {
      if (!isVisible(el)) continue;
      const label = [el.getAttribute("aria-label"), el.getAttribute("title"), el.textContent]
        .filter(Boolean)
        .join(" ");
      if (/停止|中止|中断|\b(stop|abort)\b/i.test(label)) return el;
    }
    return null;
  }

  const isDisabled = (el) =>
    !!el &&
    (el.disabled === true ||
      el.getAttribute("aria-disabled") === "true" ||
      /disabled/i.test(el.className || ""));

  async function clickSend(input, beforeNodes) {
    const button = findSendButton();
    const grew = () => messages().some((n) => !beforeNodes.includes(n));

    if (button && !isDisabled(button)) {
      simulateClick(button);
      const deadline = Date.now() + CFG.sendRetryMs;
      while (Date.now() < deadline) {
        await sleep(150);
        if (grew()) return "button";
      }
      log("send button click had no visible effect, trying Enter");
    } else {
      log("no enabled send button found, trying Enter");
    }

    pressEnter(input);
    const deadline = Date.now() + CFG.sendRetryMs;
    while (Date.now() < deadline) {
      await sleep(150);
      if (grew()) return "enter";
    }
    throw new Error(
      "could not send the message — the composer or send button selector needs updating",
    );
  }

  // -----------------------------------------------------------------------
  // the actual ask: type -> send -> wait for the stream to end -> read it
  // -----------------------------------------------------------------------

  async function askDeepSeek(text, timeoutMs, onProgress) {
    const beforeNodes = messages();
    const beforeTexts = new Set(beforeNodes.map((n) => norm(n.textContent)));
    const sentNorm = norm(text);

    onProgress("inject");
    const input = findInput();
    if (!input) throw new Error("could not find the DeepSeek message box on the page");
    await typeInto(input, text);
    await sleep(150);

    onProgress("send");
    const how = await clickSend(input, beforeNodes);
    log("sent via", how);

    onProgress("waiting");
    const startedAt = Date.now();
    const deadline = startedAt + timeoutMs;
    const mine = (n) =>
      !beforeNodes.includes(n) &&
      norm(n.textContent) !== "" &&
      norm(n.textContent) !== sentNorm &&
      !beforeTexts.has(norm(n.textContent));

    // 1. wait for the reply node to appear
    let reply = null;
    while (Date.now() < deadline) {
      reply = messages().filter(mine).pop() || null;
      if (reply) break;
      if (Date.now() - startedAt > CFG.startTimeoutMs) {
        throw new Error(
          "DeepSeek never started replying (no new message appeared within " +
            Math.round(CFG.startTimeoutMs / 1000) +
            "s)",
        );
      }
      await sleep(CFG.pollMs);
    }
    if (!reply) throw new Error("timed out before DeepSeek started replying");

    // 2. wait for the reply to stop changing
    onProgress("streaming");
    let lastText = norm(reply.textContent);
    let stableSince = Date.now();
    let lastReport = 0;

    while (Date.now() < deadline) {
      const current = messages().filter(mine).pop();
      if (current && current !== reply) {
        // DeepSeek started a fresh message node; follow it
        reply = current;
        lastText = norm(reply.textContent);
        stableSince = Date.now();
      }

      const text2 = norm(reply.textContent);
      if (text2 !== lastText) {
        lastText = text2;
        stableSince = Date.now();
        if (Date.now() - lastReport > 3000) {
          lastReport = Date.now();
          onProgress(`streaming ${lastText.length} chars`);
        }
      }

      // `settled` short-circuits first on purpose: the next two checks force
      // layout, so they only run once the text has already stopped changing.
      const settled = Date.now() - stableSince >= CFG.stableMs;
      if (settled && lastText !== "" && findStopButton() === null && !isDisabled(findSendButton())) {
        log("reply settled after", ((Date.now() - startedAt) / 1000).toFixed(1), "s");
        return reply.textContent.trim();
      }
      await sleep(CFG.pollMs);
    }

    if (lastText !== "") {
      log("timed out but keeping the partial reply");
      return reply.textContent.trim();
    }
    throw new Error("timed out waiting for DeepSeek's answer");
  }

  // -----------------------------------------------------------------------
  // WebSocket client -> local bridge service
  // -----------------------------------------------------------------------

  let ws = null;
  let portIndex = 0;

  function connect() {
    if (ws) return;
    const port = CFG.ports[portIndex % CFG.ports.length];

    let socket;
    try {
      socket = new WebSocket(`ws://${CFG.host}:${port}`);
    } catch (err) {
      log("could not open a WebSocket:", err);
      return scheduleReconnect(portIndex + 1);
    }

    let opened = false;
    const failTimer = setTimeout(() => {
      if (!opened) {
        try {
          socket.close();
        } catch {
          /* ignore */
        }
      }
    }, 4000);

    socket.onopen = () => {
      opened = true;
      clearTimeout(failTimer);
      ws = socket;
      log("connected to the bridge on port", port);
      socket.send(JSON.stringify({ type: "hello", version: 1, url: location.href }));
    };

    socket.onmessage = (event) => {
      let msg;
      try {
        msg = JSON.parse(event.data);
      } catch {
        return;
      }
      if (msg.type !== "ask") return;

      askDeepSeek(msg.text, msg.timeout_ms || 300000, (phase) => {
        if (socket.readyState === WebSocket.OPEN) {
          socket.send(JSON.stringify({ type: "progress", id: msg.id, phase }));
        }
      })
        .then((result) => {
          if (socket.readyState === WebSocket.OPEN) {
            socket.send(JSON.stringify({ type: "result", id: msg.id, ok: true, result }));
          }
        })
        .catch((err) => {
          log("ask failed:", err);
          if (socket.readyState === WebSocket.OPEN) {
            socket.send(
              JSON.stringify({
                type: "result",
                id: msg.id,
                ok: false,
                error: String((err && err.message) || err),
              }),
            );
          }
        });
    };

    socket.onclose = () => {
      clearTimeout(failTimer);
      const wasLive = ws === socket;
      if (wasLive) ws = null;
      log("bridge connection closed");
      // a live connection that dropped retries the same port; a port that
      // never answered moves on to the next candidate
      scheduleReconnect(wasLive ? portIndex : portIndex + 1);
    };

    socket.onerror = () => {
      /* onclose always follows */
    };
  }

  function scheduleReconnect(nextIndex) {
    portIndex = nextIndex;
    setTimeout(connect, 2000);
  }

  log("bridge client loaded for", location.href);
  connect();
})();
