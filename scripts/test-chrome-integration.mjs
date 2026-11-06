// Automatic-mode integration: isolated HTTPS fixtures, no popup or extension action.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { promises as fs } from "node:fs";
import path from "node:path";
import os from "node:os";
import net from "node:net";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { NativeProbe } from "./chrome-native-probe.mjs";

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const appPath = path.resolve(process.env.MACVOLUME_TEST_APP || path.join(root, "build/MacVolume.app"));
const extensionPath = path.join(appPath, "Contents/Resources/ChromeExtension");
const nativeMode = process.argv.includes("--native");
if (nativeMode && !process.env.MACVOLUME_TEST_OUTPUT) throw new Error("Set MACVOLUME_TEST_OUTPUT to an explicit output UID.");
const profile = await fs.mkdtemp(path.join(os.tmpdir(), "macvolume-auto-"));
const directory = await fs.mkdtemp("/tmp/mv-auto-");
const socketPath = path.join(directory, "chrome.sock");
let context, native, client, latest, listening = false;
const responses = new Map();
function frame(value) {
  const data = Buffer.from(JSON.stringify(value)), header = Buffer.alloc(4);
  header.writeUInt32LE(data.length); return Buffer.concat([header, data]);
}
async function until(predicate, label, timeout = 15000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const result = await predicate(); if (result) return result;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`Timed out: ${label}. Last state: ${JSON.stringify(latest)}`);
}
const server = net.createServer(socket => {
  client = socket; let buffer = Buffer.alloc(0);
  socket.on("error", () => {});
  socket.on("data", chunk => {
    buffer = Buffer.concat([buffer, chunk]);
    while (buffer.length >= 4 && buffer.length >= buffer.readUInt32LE(0) + 4) {
      const length = buffer.readUInt32LE(0), value = JSON.parse(buffer.subarray(4, 4 + length));
      buffer = buffer.subarray(4 + length);
      if (value.type === "state") { latest = value; socket.write(frame({ version: 1, type: "ready", session: value.session })); }
      if (value.requestID) responses.set(value.requestID, value);
    }
  });
});
function tone(frequency) {
  const count = 48000, data = Buffer.alloc(44 + count * 4);
  data.write("RIFF"); data.writeUInt32LE(data.length - 8, 4); data.write("WAVEfmt ", 8);
  data.writeUInt32LE(16, 16); data.writeUInt16LE(3, 20); data.writeUInt16LE(1, 22);
  data.writeUInt32LE(48000, 24); data.writeUInt32LE(48000 * 4, 28);
  data.writeUInt16LE(4, 32); data.writeUInt16LE(32, 34); data.write("data", 36); data.writeUInt32LE(count * 4, 40);
  for (let i = 0; i < count; i++) data.writeFloatLE(Math.sin(2 * Math.PI * frequency * i / 48000) * 0.0001, 44 + i * 4);
  return `data:audio/wav;base64,${data.toString("base64")}`;
}
const tone440 = tone(440), tone660 = tone(660);
function fixture(url) {
  const music = new URL(url).hostname === "music.youtube.com";
  if (url.includes("unsupported")) return `<!doctype html><title>Unsupported player fixture</title><script>
    window.context=new AudioContext(); const source=context.createOscillator(),gain=context.createGain();
    gain.gain.value=0.001; source.connect(gain).connect(context.destination); source.start(); context.resume();</script>`;
  return `<!doctype html><title>MacVolume automatic fixture ${music ? "music" : "video"}</title>
    <video id="player" loop src="${music ? tone660 : tone440}"></video>
    <script>const p=document.querySelector('video'); p.volume=${music ? "0.6" : "0.8"}; p.play();</script>`;
}
try {
  await fs.access(extensionPath);
  if (nativeMode) {
    native = new NativeProbe(appPath, socketPath, process.env.MACVOLUME_TEST_OUTPUT, value => { latest = value; });
    await native.request({ action: "status" });
  } else {
    await new Promise((resolve, reject) => { server.once("error", reject); server.listen(socketPath, resolve); });
    listening = true; await fs.chmod(socketPath, 0o600);
  }
  context = await chromium.launchPersistentContext(profile, {
    headless: true, ...(process.env.CHROME_BINARY ? { executablePath: process.env.CHROME_BINARY } : {}),
    ignoreDefaultArgs: ["--disable-extensions", "--mute-audio"],
    args: ["--enable-unsafe-extension-debugging", "--autoplay-policy=no-user-gesture-required"]
  });
  for (const pattern of ["https://**/*", "http://**/*"]) {
    await context.route(pattern, route => route.fulfill({ contentType: "text/html", body: fixture(route.request().url()) }));
  }
  // The official testing API marks the disposable extension as installed-via-CDP. A CLI-only
  // load is disabled by Chrome on reload when its protected Developer Mode preference is off.
  const browserCDP = await context.browser().newBrowserCDPSession();
  const { id } = await browserCDP.send("Extensions.loadUnpacked", { path: extensionPath });
  let worker = context.serviceWorkers()[0] || await context.waitForEvent("serviceworker");
  assert.equal(new URL(worker.url()).host, id);
  execFileSync("python3", [path.join(root, "scripts/install-chrome-bridge.py"), id, "--app", appPath,
    "--host-directory", path.join(profile, "NativeMessagingHosts")]);
  const shim = path.join(directory, "bridge"), executable = path.join(appPath, "Contents/MacOS/ChromeBridge");
  await fs.writeFile(shim, `#!/usr/bin/env python3\nimport os,sys\nos.environ['MACVOLUME_CHROME_SOCKET']=${JSON.stringify(socketPath)}\nos.execv(${JSON.stringify(executable)},[${JSON.stringify(executable)}]+sys.argv[1:])\n`, { mode: 0o700 });
  const manifestPath = path.join(profile, "NativeMessagingHosts/com.rogerleite.macvolume.chrome.json");
  const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8")); manifest.path = shim;
  await fs.writeFile(manifestPath, JSON.stringify(manifest));
  async function reconnect() {
    await worker.evaluate(() => chrome.alarms.create("reconnect", { when: Date.now() + 50, periodInMinutes: 0.5 }));
    try {
      // Preserve the production reconnect alarm if the immediate wake races host registration.
      await until(() => nativeMode ? latest?.connected : Boolean(client && latest), "automatic native connection", 40000);
    } catch (error) {
      console.error("Bridge diagnostics", await worker.evaluate(() => new Promise(resolve => {
        const probe = chrome.runtime.connectNative("com.rogerleite.macvolume.chrome");
        probe.onDisconnect.addListener(() => resolve({ error: chrome.runtime.lastError?.message }));
        probe.onMessage.addListener(message => { resolve({ message }); probe.disconnect(); });
        probe.postMessage({ version: 1, type: "state", mode: "automatic-sites", session: "diagnostic", tabs: [] });
        setTimeout(() => { resolve({ error: "No bridge reply" }); probe.disconnect(); }, 3000);
      })));
      throw error;
    }
  }
  await reconnect();
  const one = await context.newPage(), two = await context.newPage(), outside = await context.newPage();
  await one.goto("https://www.youtube.com/watch?v=fixture-one");
  await two.goto("https://music.youtube.com/watch?v=fixture-two");
  await outside.goto("http://example.org/player");
  await until(() => latest?.tabs?.filter(t => t.controlled).length === 3, "three automatically controlled tabs across HTTP/HTTPS sites");
  assert.equal(context.pages().some(p => p.url().includes("popup.html")), false, "No extension action/popup was opened");
  assert.deepEqual(new Set(latest.tabs.map(t => t.domain)), new Set(["www.youtube.com", "music.youtube.com", "example.org"]));
  assert.equal(await outside.evaluate(() => Boolean(window[Symbol.for("MacVolume.PageController")])), true);
  const first = latest.tabs.find(t => t.domain === "www.youtube.com"), second = latest.tabs.find(t => t.domain === "music.youtube.com");
  assert.equal(first.controlMode, "page"); assert.equal(first.canMute, true);
  async function command(tab, volume, muted) {
    if (nativeMode) {
      await native.request({ action: "tab", tabID: tab.id, volume });
      await until(() => latest.pending === 0 && latest.tabs.find(t => t.id === tab.id)?.volume === volume, "confirmed native volume");
      if (muted) {
        await native.request({ action: "tab", tabID: tab.id, muted });
        await until(() => latest.pending === 0 && latest.tabs.find(t => t.id === tab.id)?.muted, "confirmed native mute");
      }
    } else {
      const requestID = crypto.randomUUID();
      client.write(frame({ version: 1, type: "set", session: latest.session, requestID, tabID: tab.id, volume, muted }));
      const result = await until(() => responses.get(requestID), "confirmed page command");
      assert.equal(result.type, "state", result.error);
    }
  }
  async function playback(tab, action, expectedError = false) {
    if (nativeMode) {
      await native.request({ action: "tab", tabID: tab.id, playback: action });
      await until(() => latest.pending === 0 && (expectedError ? Boolean(latest.chromeError)
        : latest.tabs.find(t => t.id === tab.id)?.playing === (action === "play")), "confirmed native playback");
      if (!expectedError) assert.equal(latest.chromeError, "");
    } else {
      const requestID = crypto.randomUUID();
      client.write(frame({ version: 1, type: "playback", session: latest.session, requestID, tabID: tab.id, action }));
      const result = await until(() => responses.get(requestID), "confirmed playback command");
      assert.equal(result.type, expectedError ? "error" : "state", result.error);
    }
  }
  async function paused(page, value, selector = "#player") {
    assert.equal(await page.evaluate(selector => document.querySelector(selector).paused, selector), value);
  }
  async function player(page, expected, selector = "#player") {
    const result = await page.evaluate(selector => {
      const media = document.querySelector(selector), api = window[Symbol.for("MacVolume.PageController")];
      return { actual: api.actualVolume(media), base: media.volume, gain: api.controller.gain };
    }, selector);
    assert.ok(Math.abs(result.actual - expected) < 1e-6, `actual ${result.actual}, expected ${expected}`);
    console.log(`Player ${new URL(page.url()).hostname}: actual=${result.actual.toFixed(3)}, site=${result.base.toFixed(3)}, tab=${result.gain.toFixed(3)}`);
    return result;
  }
  const generic = latest.tabs.find(t => t.domain === "example.org");
  await command(generic, 0.55, false); await player(outside, 0.44);
  if (nativeMode) {
    await native.request({ action: "drag", tabID: generic.id, volumes: [0.2, 0.4, 0.6, 0.8] });
    await until(() => latest.pending === 0 && latest.tabs.find(t => t.id === generic.id)?.volume === 0.8,
      "native drag confirms the final requested gain");
    await player(outside, 0.64);
    await command(generic, 0.55, false);
  }
  await outside.goto("https://example.com/another-player");
  await until(() => latest.tabs.find(t => t.id === generic.id)?.domain === "example.com" &&
    latest.tabs.find(t => t.id === generic.id)?.controlled, "cross-site navigation retains independent gain");
  await player(outside, 0.44);
  // Pause the third tone before the native master measurements.
  await outside.evaluate(() => document.querySelector("#player").pause());
  await command(first, 0.3, false); await command(second, 0.7, false);
  await player(one, 0.24); await player(two, 0.42);
  await until(() => latest.tabs.find(t => t.id === first.id)?.canPause === true, "playback capability");
  await playback(first, "pause");
  await paused(one, true); await paused(two, false);
  assert.equal(latest.tabs.find(t => t.id === first.id).volume, 0.3);
  assert.equal(latest.tabs.find(t => t.id === second.id).volume, 0.7);
  assert.ok(latest.tabs.find(t => t.id === first.id).canPlay, "Paused tab retains resume control");
  if (!nativeMode) await playback(first, "pause"); // Explicit repeated Pause is a safe no-op.
  await playback(first, "play");
  await paused(one, false); await paused(two, false);
  await player(one, 0.24); await player(two, 0.42);
  await command(first, 0, true);
  await until(() => latest.tabs.find(t => t.id === first.id)?.playing === true, "muted zero-volume tab still playing");
  await playback(first, "pause"); await playback(first, "play");
  assert.equal(latest.tabs.find(t => t.id === first.id).volume, 0);
  assert.equal(latest.tabs.find(t => t.id === first.id).muted, true);
  await command(first, 0.3, false);
  await one.evaluate(() => { document.querySelector("#player").volume = 0.5; });
  await player(one, 0.15);
  for (let i = 0; i < 3; i++) await command(first, 0.3, false);
  await player(one, 0.15);
  await one.evaluate(src => {
    const media = document.createElement("audio"); media.id = "dynamic"; media.src = src; media.loop = true;
    document.body.append(media); media.volume = 0.4; return media.play();
  }, tone440);
  await player(one, 0.12, "#dynamic");
  await one.evaluate(src => {
    const idle = document.createElement("audio"); idle.id = "preload"; idle.src = src; idle.preload = "auto";
    document.body.append(idle);
  }, tone440);
  await playback(first, "pause");
  await paused(one, true); await paused(one, true, "#dynamic");
  await playback(first, "play");
  await paused(one, false); await paused(one, false, "#dynamic");
  await paused(one, true, "#preload"); await paused(two, false);
  await one.evaluate(() => {
    const iframe = document.createElement("iframe"); iframe.src = "https://music.youtube.com/watch?v=embedded-fixture";
    document.body.append(iframe);
  });
  const embedded = await until(() => one.frames().find(frame => frame.url().includes("embedded-fixture")), "authorized embedded player");
  await until(() => embedded.evaluate(() => window[Symbol.for("MacVolume.PageController")]?.controller.gain === 0.3), "embedded frame inherits gain");
  await playback(first, "pause");
  await paused(one, true); await paused(embedded, true); await paused(two, false);
  await embedded.evaluate(() => {
    const controller = window[Symbol.for("MacVolume.PageController")].controller;
    window.savedPlay = controller.play;
    controller.play = () => Promise.reject(new DOMException("Embedded player blocked", "NotAllowedError"));
  });
  await playback(first, "play", true);
  await paused(one, false); await paused(embedded, true); await paused(two, false);
  assert.equal(latest.tabs.find(t => t.id === first.id).playing, true, "Partial failure reports actual main-player state");
  assert.match(latest.tabs.find(t => t.id === first.id).playbackIssue, /blocked/i);
  await embedded.evaluate(() => { window[Symbol.for("MacVolume.PageController")].controller.play = window.savedPlay; });
  await playback(first, "pause"); await playback(first, "play");
  await paused(one, false); await paused(embedded, false); await paused(two, false);
  await one.evaluate(() => document.querySelector("iframe").remove());
  await one.evaluate(() => { const media = document.querySelector("#dynamic"); media.pause(); media.remove(); });
  await command(first, 0.3, true);
  await until(() => latest.tabs.find(t => t.id === first.id)?.muted, "muted tab stays in panel");
  assert.ok(latest.tabs.find(t => t.id === first.id));
  assert.equal(latest.tabs.find(t => t.id === second.id).muted, false);
  await command(first, 0.3, false);
  await one.evaluate(() => document.querySelector("#player").pause());
  await until(() => latest.tabs.find(t => t.id === first.id)?.playing === false, "website pause reflected and row retained");
  await playback(first, "play");
  await playback(first, "pause");
  // Inject a deterministic rejection at the controller's native-play seam. This
  // checks propagation through every transport without relying on autoplay prefs.
  await one.evaluate(() => {
    const controller = window[Symbol.for("MacVolume.PageController")].controller;
    window.savedPlay = controller.play;
    controller.play = () => Promise.reject(new DOMException("Blocked fixture", "NotAllowedError"));
  });
  await playback(first, "play", true);
  await paused(one, true); await paused(two, false);
  await player(one, 0.15);
  assert.match(latest.tabs.find(t => t.id === first.id).playbackIssue, /blocked/i);
  await one.evaluate(() => { window[Symbol.for("MacVolume.PageController")].controller.play = window.savedPlay; });
  await playback(first, "play");
  if (!nativeMode) {
    const requestID = crypto.randomUUID();
    client.write(frame({ version: 1, type: "set", session: "expired", requestID, tabID: first.id, volume: 1, muted: false }));
    assert.equal((await until(() => responses.get(requestID), "stale session rejection")).type, "error");
    await playback(first, "pause");
    const old = client; old.destroy();
    await worker.evaluate(() => new Promise(resolve => setTimeout(resolve, 250)));
    await worker.evaluate(() => chrome.alarms.create("reconnect", { when: Date.now() + 50 }));
    await until(() => client !== old, "bridge reconnect without popup");
    await player(one, 0.15); await player(two, 0.42);
    await paused(one, true); await paused(two, false);
    await playback(first, "play");
  } else {
    await until(() => latest.browserFound, "native browser ownership");
    await native.request({ action: "master", gain: 0.5 });
    async function meters(stage) {
      let result;
      await until(async () => {
        result = await native.request({ action: "meters" });
        return result.inputPeak > 0.000001 && Math.abs(result.ratio - 0.5) < 0.02;
      }, stage, 20000);
      assert.equal(result.mixerError, "");
      console.log(`Native ${stage}: input=${result.inputPeak.toFixed(7)} output=${result.outputPeak.toFixed(7)} ratio=${result.ratio.toFixed(3)} device=${result.output}`);
      return result;
    }
    await meters("automatic tabs plus master 50%");
    await two.evaluate(() => document.querySelector("#player").pause());
    await one.evaluate(() => { document.querySelector("#player").volume = 1; });
    await command(first, 1, false);
    await player(one, 1);
    const baseline = await meters("single player at 100%");
    await command(first, 0.3, false);
    await player(one, 0.3);
    const reduced = await meters("single player at 30%");
    assert.ok(Math.abs(reduced.inputPeak / baseline.inputPeak - 0.3) < 0.06, `HTML player gain measured ${reduced.inputPeak / baseline.inputPeak}`);
    await two.evaluate(() => document.querySelector("#player").play());
    for (const uid of process.env.MACVOLUME_TEST_OUTPUTS ? JSON.parse(process.env.MACVOLUME_TEST_OUTPUTS) : []) {
      await native.request({ action: "route", uid }); await meters(`route ${uid}`);
    }
  }
  const unsupported = await context.newPage();
  await unsupported.goto("https://music.youtube.com/watch?v=unsupported");
  const unavailable = await until(() => latest.tabs.find(t => t.title === "Unsupported player fixture"), "unsupported player is honestly reported");
  assert.equal(unavailable.controlled, false); assert.equal(unavailable.canMute, true); assert.ok(unavailable.issue);
  assert.equal(unavailable.canPlay, false); assert.equal(unavailable.canPause, false);
  if (nativeMode) {
    await native.request({ action: "tab", tabID: unavailable.id, muted: true });
  } else {
    const requestID = crypto.randomUUID();
    client.write(frame({ version: 1, type: "set", session: latest.session, requestID, tabID: unavailable.id, volume: 1, muted: true }));
    assert.equal((await until(() => responses.get(requestID), "mute-only command")).type, "state");
  }
  await until(() => latest.tabs.find(t => t.id === unavailable.id)?.muted, "mute-only native capability");
  await unsupported.close();
  // A 0.3 document can retain its old controller after an extension reload.
  // Exercise that legacy state shape: volume remains available, playback does not.
  await one.evaluate(() => {
    const controller = window[Symbol.for("MacVolume.PageController")].controller;
    window.savedState = controller.state;
    controller.state = function () {
      const { volume, mediaCount, playingCount } = window.savedState.call(this);
      return { volume, mediaCount, playingCount };
    };
  });
  await until(() => latest.tabs.find(t => t.id === first.id)?.canPause === false &&
    latest.tabs.find(t => t.id === first.id)?.playbackIssue?.includes("Reload this page"), "legacy controller requests one page reload");
  await command(first, 0.3, false); await player(one, nativeMode ? 0.3 : 0.15);
  await one.evaluate(() => { window[Symbol.for("MacVolume.PageController")].controller.state = window.savedState; });
  await until(() => latest.tabs.find(t => t.id === first.id)?.canPause === true, "modern playback capabilities restored");
  await playback(first, "pause");
  await one.goto("https://www.youtube.com/watch?v=fixture-next");
  await until(() => latest.tabs.find(t => t.id === first.id)?.controlled && latest.tabs.find(t => t.id === first.id)?.volume === 0.3, "navigation keeps gain automatically");
  await player(one, 0.24);
  await until(() => latest.tabs.find(t => t.id === first.id)?.playing === true, "navigation does not replay stale pause");
  assert.equal(await one.evaluate(() => window[Symbol.for("MacVolume.PageController")].controller.state().resumeCount), 0);
  // An extension reload must bootstrap already-open pages automatically, without a page/action click.
  const oldWorker = worker;
  await worker.evaluate(() => chrome.runtime.reload()).catch(() => {});
  worker = await until(async () => {
    for (const candidate of context.serviceWorkers()) {
      if (candidate === oldWorker) continue;
      try { if (await candidate.evaluate(() => Boolean(chrome.runtime.id))) return candidate; } catch { /* Target is restarting. */ }
    }
    return undefined;
  }, "reloaded extension worker", 12000).catch(async error => {
    for (const file of ["Preferences", "Secure Preferences"]) {
      const prefs = await fs.readFile(path.join(profile, "Default", file), "utf8").then(JSON.parse).catch(() => ({}));
      const entry = prefs.extensions?.settings?.[id];
      if (entry) console.error("Reload registration", file, { state: entry.state, disable_reasons: entry.disable_reasons, location: entry.location });
    }
    console.error("Reload diagnostics", { workers: context.serviceWorkers().map(w => w.url()), latest,
      pageGain: await one.evaluate(() => window[Symbol.for("MacVolume.PageController")]?.controller.gain) });
    throw error;
  });
  await worker.evaluate(() => chrome.alarms.create("reconnect", { when: Date.now() + 50 }));
  await until(() => latest.tabs.find(t => t.id === first.id)?.controlled && latest.tabs.find(t => t.id === first.id)?.volume === 1,
    "already-open page bootstraps after extension reload", 20000);
  await command(first, 0.45, false); await player(one, 0.36);
  await playback(first, "pause"); await playback(first, "play");
  await two.close(); await until(() => !latest.tabs.find(t => t.id === second.id), "closed tab removed");
  const shutdownPage = await context.newPage();
  await shutdownPage.goto("https://m.youtube.com/watch?v=shutdown-fixture");
  const shutdownTab = await until(() => latest.tabs.find(t => t.domain === "m.youtube.com" && t.canPause), "shutdown fixture discovered");
  await command(shutdownTab, 0.2, false); await playback(shutdownTab, "pause");
  if (nativeMode) await native.close(); else client.write(frame({ version: 1, type: "shutdown" }));
  await until(async () => (await one.evaluate(() => window[Symbol.for("MacVolume.PageController")].controller.gain)) === 1, "normal shutdown restores site volume");
  await player(one, 0.8);
  await paused(one, false); // Shutdown restores gain without stopping playback.
  await until(async () => (await shutdownPage.evaluate(() => window[Symbol.for("MacVolume.PageController")].controller.gain)) === 1, "paused tab gain restored at shutdown");
  await player(shutdownPage, 0.8); await paused(shutdownPage, true);
  console.log(`PASS (${nativeMode ? "native mixer" : "mock app"}): HTTP/HTTPS sites, independent gains and play/pause, muted/zero-volume playback, resume targeting, rejected Play, website state, cross-site navigation, reload and shutdown. No per-tab activation.`);
} finally {
  await context?.close(); await native?.close(); client?.destroy();
  if (listening) server.close();
  await fs.rm(profile, { recursive: true, force: true }); await fs.rm(directory, { recursive: true, force: true });
}
