(() => {
  const key = Symbol.for("MacVolume.ContentBridge");
  globalThis[key]?.dispose();
  const channel = "macvolume-page-v1", bridgeID = crypto.randomUUID();
  let port, retry, disposed = false, initialized = false, lastState;
  const waiting = new Map();
  function post(type, volume, requestID) {
    window.postMessage({ channel, direction: "bridge", bridgeID, type, volume, requestID }, location.origin);
  }
  function pageMessage(event) {
    const message = event.data, state = message?.state;
    if (event.source !== window || event.origin !== location.origin || message?.channel !== channel ||
        message.direction !== "page" || message.bridgeID !== bridgeID || !state ||
        !Number.isFinite(state.volume) || state.volume < 0 || state.volume > 1 ||
        !Number.isInteger(state.mediaCount) || state.mediaCount < 0 || state.mediaCount > 10000 ||
        !Number.isInteger(state.playingCount) || state.playingCount < 0 || state.playingCount > state.mediaCount) return;
    const same = lastState && ["volume", "mediaCount", "playingCount"].every(key => lastState[key] === state[key]);
    lastState = state;
    if (same && !message.requestID) return;
    try { port?.postMessage({ type: "state", state, requestID: message.requestID }); } catch { /* Reconnect handles a dead worker. */ }
    const item = waiting.get(message.requestID);
    if (item) { clearTimeout(item); waiting.delete(message.requestID); }
  }
  function connect() {
    if (disposed) return;
    try {
      if (!chrome.runtime.id) throw new Error("Extension unloaded");
      port = chrome.runtime.connect({ name: "macvolume-media" });
      port.onMessage.addListener(message => {
        if (message.type === "outOfScope") { if (initialized) post("reset"); dispose(); return; }
        if (!["init", "set", "reset", "state"].includes(message.type)) return;
        if (message.type === "init") initialized = true;
        if (message.requestID) waiting.set(message.requestID, setTimeout(() => {
          waiting.delete(message.requestID);
          try { port?.postMessage({ type: "error", requestID: message.requestID, error: "YouTube player did not confirm the volume. Reload this page once." }); } catch { /* Worker disconnected. */ }
        }, 2500));
        post(message.type, message.volume, message.requestID);
      });
      port.onDisconnect.addListener(() => {
        void chrome.runtime.lastError;
        port = undefined;
        retry = setTimeout(connect, 1000);
      });
      port.postMessage({ type: "hello", state: lastState });
    } catch {
      // The content context was invalidated (extension reload/disable). Restore site volume.
      if (initialized) post("reset");
      dispose();
    }
  }
  function dispose() {
    disposed = true; clearTimeout(retry); clearInterval(heartbeat);
    window.removeEventListener("message", pageMessage);
    for (const timeout of waiting.values()) clearTimeout(timeout);
    waiting.clear(); port?.disconnect(); port = undefined;
  }
  window.addEventListener("message", pageMessage);
  // Same-frame heartbeat refreshes playing state; it never resets gain on a timer.
  const heartbeat = setInterval(() => {
    if (!disposed && initialized) post("state");
    try { if (!chrome.runtime.id) throw new Error(); } catch { if (initialized) post("reset"); dispose(); }
  }, 1000);
  globalThis[key] = { dispose };
  connect();
})();
