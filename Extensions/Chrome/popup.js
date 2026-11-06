import { supportedURL } from "./scope.js";
const element = id => document.getElementById(id);
element("extension-id").textContent = chrome.runtime.id;

async function send(type) {
  const result = await chrome.runtime.sendMessage({ target: "worker", type });
  if (result?.error && result.connected === undefined) throw new Error(result.error);
  return result;
}

async function refresh() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    element("title").textContent = tab?.title || "Select a tab";
    const result = await send("status");
    const control = result.state.tabs.find(t => t.id === tab?.id);
    element("connection").textContent = result.connected ? "Connected to MacVolume" : result.error;
    element("automatic").textContent = !supportedURL(tab?.url)
      ? "Automatic controls are limited to YouTube and YouTube Music."
      : control?.issue || (control ? `Automatic · ${Math.round(control.volume * 100)}%${control.muted ? " · Muted" : ""}`
        : "Automatic mode is ready. Play audio and the tab will appear in MacVolume.");
  } catch (error) { element("error").textContent = error.message; }
}

element("reconnect").addEventListener("click", async () => {
  element("error").textContent = "";
  try { await send("reconnect"); await refresh(); } catch (error) { element("error").textContent = error.message; }
});
refresh();
setInterval(refresh, 1500);
