(() => {
  const key = Symbol.for("MacVolume.ContentBridge");
  globalThis[key]?.dispose();
  // getRandomValues also works on HTTP, where randomUUID is unavailable.
  const channel = "macvolume-page-v1", bridgeID = Array.from(crypto.getRandomValues(new Uint8Array(16)),
    byte => byte.toString(16).padStart(2, "0")).join("");
  let port, retry, disposed = false, initialized = false, lastState;
  const waiting = new Map();
  function post(type, volume, requestID, action, allowFallback) {
    window.postMessage({ channel, direction: "bridge", bridgeID, type, volume, requestID, action, allowFallback }, location.origin);
  }
  function validPlayback(state) {
    if (!["canPrevious", "canNext", "canShuffle", "shuffleEnabled"].every(key => state[key] === undefined || typeof state[key] === "boolean") ||
        (state.transportIssue !== undefined && (typeof state.transportIssue !== "string" || state.transportIssue.length > 512)) ||
        (state.canShuffle === true && typeof state.shuffleEnabled !== "boolean")) return false;
    if (state.audibleCount === undefined) return ["canPlay", "canPause", "resumeCount", "playbackIssue"].every(key => state[key] === undefined);
    return Number.isInteger(state.audibleCount) && state.audibleCount >= 0 && state.audibleCount <= state.playingCount &&
      typeof state.canPlay === "boolean" && typeof state.canPause === "boolean" &&
      Number.isInteger(state.resumeCount) && state.resumeCount >= 0 && state.resumeCount <= state.mediaCount &&
      (state.playbackIssue === undefined || (typeof state.playbackIssue === "string" && state.playbackIssue.length <= 512));
  }
  function pageMessage(event) {
    const message = event.data, state = message?.state;
    if (event.source !== window || event.origin !== location.origin || message?.channel !== channel ||
        message.direction !== "page" || message.bridgeID !== bridgeID || !state ||
        !Number.isFinite(state.volume) || state.volume < 0 || state.volume > 1 ||
        !Number.isInteger(state.mediaCount) || state.mediaCount < 0 || state.mediaCount > 10000 ||
        !Number.isInteger(state.playingCount) || state.playingCount < 0 || state.playingCount > state.mediaCount || !validPlayback(state) ||
        (message.error !== undefined && (typeof message.error !== "string" || message.error.length > 512))) return;
    const same = lastState && ["volume", "mediaCount", "playingCount", "audibleCount", "canPlay", "canPause", "resumeCount", "playbackIssue",
      "canPrevious", "canNext", "canShuffle", "shuffleEnabled", "transportIssue"]
      .every(key => lastState[key] === state[key]);
    lastState = state;
    if (same && !message.requestID) return;
    try { port?.postMessage({ type: "state", state, requestID: message.requestID, error: message.error }); } catch { /* Reconnect handles a dead worker. */ }
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
        if (!["init", "set", "reset", "state", "playback", "transport"].includes(message.type)) return;
        if (message.type === "transport" && !["previous", "next", "shuffle-on", "shuffle-off"].includes(message.action)) return;
        if (message.type === "playback" && (!["play", "pause"].includes(message.action) || typeof message.allowFallback !== "boolean")) return;
        if (message.type === "init") initialized = true;
        if (message.requestID) waiting.set(message.requestID, setTimeout(() => {
          waiting.delete(message.requestID);
          try { port?.postMessage({ type: "error", requestID: message.requestID, error: "Audio/video player did not confirm the control. Reload this page once." }); } catch { /* Worker disconnected. */ }
        }, 2500));
        post(message.type, message.volume, message.requestID, message.action, message.allowFallback);
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
