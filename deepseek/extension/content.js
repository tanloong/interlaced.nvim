/**
 * DeepSeek bridge — page side (content script).
 *
 * Runs inside a chat.deepseek.com tab. Keeps a WebSocket open to the local
 * bridge service (deepseek/server.mjs) and, for every `send` message it gets,
 * types the text into the composer and presses send. That is all it does: the
 * answer is read by a human in the browser, so nothing here watches the stream
 * or parses a reply.
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
      // the composer row the send button lives in
      sendContainer: '[class~="bf38813a"]',
      input: ["textarea#chat-input", 'textarea[placeholder]', "textarea", '[contenteditable="true"]'],
    },

    // how long the composer is given to empty out after a send attempt
    confirmMs: 3000,
    debug: true,
  };

  const log = (...a) => CFG.debug && console.log("[deepseek-bridge]", ...a);
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

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

  const isDisabled = (el) =>
    !!el &&
    (el.disabled === true ||
      el.getAttribute("aria-disabled") === "true" ||
      /disabled/i.test(el.className || ""));

  const composerText = (input) =>
    input.tagName === "TEXTAREA" || input.tagName === "INPUT"
      ? input.value || ""
      : input.textContent || "";

  /**
   * DeepSeek empties the composer once the message is on its way, which is the
   * cheapest proof that the send took effect.
   */
  async function composerCleared(input) {
    const deadline = Date.now() + CFG.confirmMs;
    while (Date.now() < deadline) {
      await sleep(120);
      if (composerText(input).trim() === "") return true;
      if (!document.contains(input)) return true; // composer was swapped out
    }
    return false;
  }

  /** Type `text` into the composer and send it. Resolves with how it was sent. */
  async function sendText(text) {
    const input = findInput();
    if (!input) throw new Error("could not find the DeepSeek message box on the page");

    await typeInto(input, text);
    await sleep(150);

    const button = findSendButton();
    if (button && !isDisabled(button)) {
      simulateClick(button);
      if (await composerCleared(input)) return "button";
      log("the send button click had no effect, trying Enter");
    } else {
      log("no enabled send button found, trying Enter");
    }

    pressEnter(input);
    if (await composerCleared(input)) return "enter";

    throw new Error(
      "could not send the message — the composer or send button selector needs updating",
    );
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

    const reply = (message) => {
      if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
    };

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
      if (msg.type !== "send") return;

      sendText(msg.text)
        .then((how) => {
          log("sent via", how);
          reply({ type: "sent", id: msg.id });
        })
        .catch((err) => {
          log("send failed:", err);
          reply({
            type: "error",
            id: msg.id,
            error: String((err && err.message) || err),
          });
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
