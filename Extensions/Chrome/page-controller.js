(() => {
  const key = Symbol.for("MacVolume.PageController"), channel = "macvolume-page-v1";
  // Duplicate bootstrap (including extension reload) reuses the original native accessors.
  if (window[key]) { window[key].announce(); return; }
  const Controller = window[Symbol.for("MacVolume.MediaController")];
  if (!Controller) return;
  const prototype = HTMLMediaElement.prototype;
  const descriptor = Object.getOwnPropertyDescriptor(prototype, "volume");
  const nativePlay = prototype.play;
  const nativePause = prototype.pause;
  let bridgeID, scheduled = false;
  const listeners = new WeakSet(), observedRoots = new WeakSet();
  function announce(requestID, error) {
    if (!bridgeID) return;
    window.postMessage({ channel, direction: "page", bridgeID, requestID, state: controller.state(),
      ...(error ? { error } : {}) }, location.origin);
  }
  function changed() {
    if (scheduled) return;
    scheduled = true;
    queueMicrotask(() => { scheduled = false; announce(); });
  }
  const controller = new Controller({
    getVolume: element => descriptor.get.call(element),
    setVolume: (element, value) => descriptor.set.call(element, value),
    isPlaying: element => !element.paused && !element.ended,
    isAudible: element => !element.muted && element.readyState >= 2,
    canPlay: element => element.isConnected && !element.ended && Boolean(element.currentSrc || element.src || element.srcObject),
    play: element => nativePlay.call(element), pause: element => nativePause.call(element),
    changed
  });
  function track(element) {
    controller.track(element);
    if (listeners.has(element)) return;
    listeners.add(element);
    element.addEventListener("volumechange", () => { controller.observeNativeChange(element); changed(); });
    element.addEventListener("playing", () => controller.notePlaying(element));
    for (const event of ["play", "playing", "pause", "ended", "emptied", "loadeddata"]) element.addEventListener(event, changed);
  }
  Object.defineProperty(prototype, "volume", {
    ...descriptor,
    get() { track(this); return controller.baseVolume(this); },
    set(value) {
      const numeric = Number(value);
      if (!Number.isFinite(numeric) || numeric < 0 || numeric > 1) {
        // Preserve the browser's native exception for invalid writes.
        descriptor.set.call(this, value); return;
      }
      track(this); controller.setBaseVolume(this, numeric);
    }
  });
  prototype.play = function (...args) { track(this); return nativePlay.apply(this, args); };
  function scan(root) {
    if (root instanceof HTMLMediaElement) track(root);
    for (const media of root.querySelectorAll?.("audio,video") || []) track(media);
    for (const element of root.querySelectorAll?.("*") || []) if (element.shadowRoot) observe(element.shadowRoot);
  }
  function observe(root) {
    if (observedRoots.has(root)) return;
    observedRoots.add(root); scan(root);
    const observer = new MutationObserver(changes => {
      for (const change of changes) for (const node of change.addedNodes) scan(node);
      changed();
    });
    observer.observe(root, { childList: true, subtree: true });
  }
  const attachShadow = Element.prototype.attachShadow;
  Element.prototype.attachShadow = function (...args) {
    const root = attachShadow.apply(this, args); observe(root); return root;
  };
  window.addEventListener("message", async event => {
    const message = event.data;
    if (event.source !== window || event.origin !== location.origin || message?.channel !== channel || message.direction !== "bridge") return;
    if (typeof message.bridgeID !== "string" || message.bridgeID.length > 80) return;
    if (message.type === "init") bridgeID = message.bridgeID;
    if (message.bridgeID !== bridgeID) return;
    if (message.type === "playback") {
      if (!["play", "pause"].includes(message.action) || typeof message.allowFallback !== "boolean") return;
      try { await controller.setPlayback(message.action, message.allowFallback); announce(message.requestID); }
      catch (error) { announce(message.requestID, String(error.message).slice(0, 512)); }
      return;
    } else if (message.type === "set" || message.type === "init") {
      try { controller.setGain(message.volume); } catch { return; }
    } else if (message.type === "reset") controller.reset();
    else if (message.type !== "state") return;
    announce(message.requestID);
  });
  observe(document);
  window[key] = { controller, announce, actualVolume: element => descriptor.get.call(element) };
})();
