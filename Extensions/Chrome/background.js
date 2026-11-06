import { HOST, VERSION, validCommand, validPlayerState, tabMetadata } from "./protocol.js";
import { SITE_PATTERNS, supportedURL } from "./scope.js";

const frames = new Map(), settings = new Map(), requests = new Map(), bootstrapErrors = new Map();
let port, acknowledged = false, lastError = "Open MacVolume to connect.", sessionID;
let snapshotQueue = Promise.resolve(), commandQueue = Promise.resolve();
const loaded = (async () => {
  const saved = await chrome.storage.session.get(["session", "tabSettings"]);
  sessionID = saved.session || crypto.randomUUID();
  for (const [id, value] of Object.entries(saved.tabSettings || {})) {
    if (Number.isSafeInteger(Number(id)) && value && Number.isFinite(value.volume) && value.volume >= 0 && value.volume <= 1) {
      settings.set(Number(id), { volume: value.volume, seen: Boolean(value.seen), originalMuted: value.originalMuted });
    }
  }
  await chrome.storage.session.set({ session: sessionID });
})();
function setting(tabID) {
  if (!settings.has(tabID)) settings.set(tabID, { volume: 1, seen: false });
  return settings.get(tabID);
}
async function save() {
  await chrome.storage.session.set({ tabSettings: Object.fromEntries([...settings].map(([id, value]) =>
    [id, { volume: value.volume, seen: value.seen, ...(typeof value.originalMuted === "boolean" ? { originalMuted: value.originalMuted } : {}) }])) });
}
function tabFrames(tabID) { return [...(frames.get(tabID)?.values() || [])].filter(frame => !frame.closed); }
function post(message) { try { port?.postMessage(message); } catch { /* onDisconnect updates status. */ } }
function report(error, requestID) {
  lastError = String(error.message || error).slice(0, 1024);
  post({ version: VERSION, type: "error", requestID, error: lastError });
}
function sendFrame(frame, type, volume, action, allowFallback = false) {
  if (frame.closed) return Promise.reject(new Error("The YouTube page changed. Try the control again."));
  const requestID = crypto.randomUUID();
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { requests.delete(requestID); reject(new Error("YouTube player did not confirm the control. Reload this page once.")); }, 3500);
    requests.set(requestID, { frame, resolve, reject, timer });
    try { frame.port.postMessage({ type, volume, requestID, action, allowFallback }); }
    catch { clearTimeout(timer); requests.delete(requestID); reject(new Error("YouTube controller disconnected.")); }
  });
}
function dropFrame(frame) {
  frame.closed = true;
  const group = frames.get(frame.tabID);
  if (group?.get(frame.key) === frame) group.delete(frame.key);
  if (group?.size === 0) frames.delete(frame.tabID);
  for (const [id, item] of requests) if (item.frame === frame) {
    clearTimeout(item.timer); requests.delete(id); item.reject(new Error("The YouTube page changed during the command."));
  }
}
chrome.runtime.onConnect.addListener(controllerPort => {
  const sender = controllerPort.sender;
  if (controllerPort.name !== "macvolume-media" || !sender?.tab || sender.tab.incognito ||
      !supportedURL(sender.url) || (sender.documentLifecycle && sender.documentLifecycle !== "active")) {
    controllerPort.disconnect(); return;
  }
  const frame = { port: controllerPort, tabID: sender.tab.id, frameID: sender.frameId,
    key: `${sender.frameId}:${sender.documentId || "current"}`, ready: false, state: undefined, closed: false };
  controllerPort.onDisconnect.addListener(() => { void chrome.runtime.lastError; dropFrame(frame); publish().catch(() => {}); });
  controllerPort.onMessage.addListener(message => {
    if (frame.closed) return;
    if (message.type === "hello") return;
    const item = requests.get(message.requestID);
    if (message.type === "error") {
      if (item?.frame === frame) { clearTimeout(item.timer); requests.delete(message.requestID); item.reject(new Error(String(message.error).slice(0, 512))); }
      return;
    }
    if (message.type !== "state" || !validPlayerState(message.state) ||
        (message.error !== undefined && (typeof message.error !== "string" || message.error.length > 512))) return;
    frame.state = message.state;
    if (item?.frame === frame) {
      clearTimeout(item.timer); requests.delete(message.requestID);
      if (message.error) item.reject(new Error(message.error)); else item.resolve(message.state);
    }
    else if (frame.ready) publish().catch(error => report(error));
  });
  (async () => {
    await loaded;
    const tab = await chrome.tabs.get(frame.tabID);
    if (frame.closed) return;
    if (!supportedURL(tab.url)) { controllerPort.postMessage({ type: "outOfScope" }); return; }
    for (const old of tabFrames(frame.tabID)) if (old.frameID === frame.frameID) { dropFrame(old); old.port.disconnect(); }
    if (!frames.has(frame.tabID)) frames.set(frame.tabID, new Map());
    frames.get(frame.tabID).set(frame.key, frame);
    const value = setting(frame.tabID);
    await sendFrame(frame, "init", value.desiredVolume ?? value.volume);
    frame.ready = true; bootstrapErrors.delete(frame.tabID);
    await publish();
  })().catch(error => { if (!frame.closed) bootstrapErrors.set(frame.tabID, error.message); publish().catch(() => {}); });
});

async function state(requestID) {
  await loaded;
  const tabs = [];
  let changed = false;
  for (const tab of await chrome.tabs.query({ url: SITE_PATTERNS })) {
    if (tab.incognito || !supportedURL(tab.url)) continue;
    const value = setting(tab.id), controllers = tabFrames(tab.id).filter(frame => frame.ready && frame.state);
    const playing = controllers.some(frame => frame.state.playingCount > 0);
    const audible = controllers.some(frame => (frame.state.audibleCount ?? frame.state.playingCount) > 0);
    const playback = controllers.filter(frame => typeof frame.state.canPlay === "boolean");
    const legacyActive = controllers.some(frame => typeof frame.state.canPlay !== "boolean" && frame.state.playingCount > 0);
    const resumeTargets = playback.some(frame => frame.state.resumeCount > 0);
    const canPlay = resumeTargets || playback.some(frame => frame.frameID === 0 && frame.state.canPlay);
    const playbackIssue = playback.find(frame => frame.state.playbackIssue)?.state.playbackIssue;
    if ((tab.audible || playing) && !value.seen) { value.seen = true; changed = true; }
    if (!value.seen && value.volume === 1) continue;
    const hasPlayer = controllers.some(frame => frame.state.mediaCount > 0);
    const confirmed = controllers.every(frame => Math.abs(frame.state.volume - value.volume) < 1e-9);
    tabs.push(tabMetadata(tab, {
      controlled: hasPlayer && confirmed, canMute: true, controlMode: "page", volume: value.volume,
      muted: Boolean(tab.mutedInfo?.muted), audible: !tab.mutedInfo?.muted && (audible || Boolean(tab.audible)),
      playing, canPlay, canPause: !legacyActive && playback.some(frame => frame.state.canPause),
      ...(playbackIssue ? { playbackIssue } : (playback.length === 0 && hasPlayer) || legacyActive
        ? { playbackIssue: "Reload this page once to enable play/pause with the updated extension." } : {}),
      ...(!hasPlayer ? { issue: bootstrapErrors.get(tab.id) || (controllers.length > 0
        ? "No supported audio/video player found; tab mute is available."
        : "Waiting for the YouTube controller. If this page was already open during the update, reload it once.") } : {})
    }));
    if (tabs.length === 500) break;
  }
  if (changed) await save();
  return { version: VERSION, type: "state", mode: "automatic-youtube", session: sessionID, tabs, ...(requestID ? { requestID } : {}) };
}
function publish(requestID) {
  const task = snapshotQueue.then(async () => { const message = await state(requestID); post(message); return message; });
  snapshotQueue = task.catch(() => {}); return task;
}
async function restoreTab(tabID, clear = false) {
  const value = settings.get(tabID);
  await Promise.allSettled(tabFrames(tabID).map(frame => sendFrame(frame, "reset")));
  const tab = await chrome.tabs.get(tabID).catch(() => undefined);
  if (tab?.mutedInfo?.extensionId === chrome.runtime.id && typeof value?.originalMuted === "boolean") {
    await chrome.tabs.update(tabID, { muted: value.originalMuted });
  }
  if (clear) settings.delete(tabID);
  else if (value) { value.volume = 1; delete value.desiredVolume; delete value.originalMuted; }
}
async function apply(message) {
  await loaded;
  if (!validCommand(message) || message.session !== sessionID) throw new Error("Invalid or expired tab command.");
  const tab = await chrome.tabs.get(message.tabID);
  if (!supportedURL(tab.url) || tab.incognito) throw new Error("Automatic controls are limited to YouTube and YouTube Music.");
  const value = setting(tab.id), previous = value.volume;
  const controllers = tabFrames(tab.id).filter(frame => frame.ready);
  if (message.type === "playback") {
    const capable = controllers.filter(frame => typeof frame.state?.canPlay === "boolean");
    if (!capable.length) throw new Error("Playback unavailable. Reload this YouTube page once after updating the extension.");
    if (message.action === "pause" && controllers.some(frame => frame.state?.playingCount > 0 && typeof frame.state.canPause !== "boolean")) {
      throw new Error("Reload this page once to update all its players before using play/pause.");
    }
    let targets;
    if (message.action === "pause") targets = capable.filter(frame => frame.state.canPause);
    else {
      targets = capable.filter(frame => frame.state.resumeCount > 0);
      if (!targets.length && !capable.some(frame => frame.state.playingCount > 0)) {
        targets = capable.filter(frame => frame.frameID === 0 && frame.state.canPlay);
        if (!targets.length) throw new Error("No previously active YouTube player is available to resume.");
      }
    }
    const results = await Promise.allSettled(targets.map(frame => sendFrame(frame, "playback", undefined,
      message.action, message.action === "play" && frame.state.resumeCount === 0 && frame.frameID === 0)));
    const failure = results.find(result => result.status === "rejected");
    if (failure) { await publish(); throw failure.reason; }
    await publish(message.requestID);
    return;
  }
  const hasPlayer = controllers.some(frame => frame.state?.mediaCount > 0);
  if (!hasPlayer && Math.abs(message.volume - previous) > 1e-9) throw new Error("The YouTube player is not available for volume control yet.");
  value.desiredVolume = message.volume;
  try {
    const states = await Promise.all(controllers.map(frame => sendFrame(frame, "set", message.volume)));
    if (states.some(state => Math.abs(state.volume - message.volume) > 1e-9)) throw new Error("YouTube did not apply the requested volume.");
    if (Boolean(tab.mutedInfo?.muted) !== message.muted) {
      if (typeof value.originalMuted !== "boolean") value.originalMuted = Boolean(tab.mutedInfo?.muted);
      await chrome.tabs.update(tab.id, { muted: message.muted });
    }
    value.volume = message.volume; value.seen = true;
    await save();
  } catch (error) {
    await Promise.allSettled(controllers.filter(frame => !frame.closed).map(frame => sendFrame(frame, "set", previous)));
    throw error;
  } finally { delete value.desiredVolume; }
  await publish(message.requestID);
}
function connect() {
  if (port) return;
  const candidate = chrome.runtime.connectNative(HOST);
  port = candidate; acknowledged = false;
  candidate.onMessage.addListener(message => {
    if (message?.version !== VERSION) { report(new Error("Update MacVolume and its extension together.")); return; }
    if (message.type === "ready") { acknowledged = true; lastError = ""; return; }
    if (message.type === "error") { lastError = message.error || "Bridge error."; return; }
    commandQueue = commandQueue.then(async () => {
      if (message.type === "shutdown") {
        await loaded;
        await Promise.allSettled([...settings.keys()].map(id => restoreTab(id)));
        await save(); await publish();
      } else await apply(message);
    }).catch(error => report(error, message.requestID));
  });
  candidate.onDisconnect.addListener(() => {
    const error = chrome.runtime.lastError;
    if (port !== candidate) return;
    port = undefined; acknowledged = false;
    lastError = error?.message || "MacVolume disconnected. Existing page volumes are preserved.";
  });
  setTimeout(() => {
    if (port === candidate && !acknowledged) { lastError = "MacVolume did not respond. Open the app and reconnect."; candidate.disconnect(); port = undefined; }
  }, 5000);
  publish().catch(error => report(error));
}
async function bootstrap(tab) {
  if (!tab || tab.incognito || !supportedURL(tab.url) || tab.discarded || tabFrames(tab.id).some(frame => frame.frameID === 0 && frame.ready)) return;
  try {
    // Bootstrap existing top-level players even if an ad iframe has a different origin.
    // New authorized child frames receive the declared all_frames content scripts.
    await chrome.scripting.executeScript({ target: { tabId: tab.id }, world: "MAIN", files: ["media-controller.js", "page-controller.js"] });
    await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["content-bridge.js"] });
  } catch { bootstrapErrors.set(tab.id, "Allow the extension access to YouTube and YouTube Music, then reload this page once."); }
}
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id || message?.target !== "worker") return;
  (async () => {
    if (message.type === "reconnect") connect();
    else if (message.type !== "status") throw new Error("Unknown automatic-control command.");
    return { connected: acknowledged, error: acknowledged ? "" : lastError, state: await state() };
  })().then(respond, error => respond({ error: error.message }));
  return true;
});
chrome.tabs.onUpdated.addListener((id, change, tab) => {
  (async () => {
    await loaded;
    if (!supportedURL(tab.url) && (settings.has(id) || frames.has(id))) {
      await restoreTab(id, true); bootstrapErrors.delete(id); await save();
    } else if (change.status === "complete") await bootstrap(tab);
    if (["audible", "title", "url", "mutedInfo", "status"].some(key => key in change)) await publish();
  })().catch(error => report(error));
});
chrome.tabs.onRemoved.addListener(id => {
  for (const frame of tabFrames(id)) { dropFrame(frame); frame.port.disconnect(); }
  settings.delete(id); bootstrapErrors.delete(id); save().catch(() => {}); publish().catch(() => {});
});
chrome.alarms.onAlarm.addListener(alarm => { if (alarm.name === "reconnect") connect(); });
chrome.alarms.create("reconnect", { periodInMinutes: 0.5 });
let startupTask;
function startup() {
  startupTask ??= loaded.then(async () => {
    connect(); await Promise.all((await chrome.tabs.query({ url: SITE_PATTERNS })).map(bootstrap));
  });
  startupTask.catch(error => report(error));
}
// Unpacked reloads fire onInstalled(update). Register these synchronously so Chrome wakes
// the worker even when no fresh document/content port exists yet.
chrome.runtime.onInstalled.addListener(startup);
chrome.runtime.onStartup.addListener(startup);
startup();
