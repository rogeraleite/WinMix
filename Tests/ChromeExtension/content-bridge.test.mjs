import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";

test("HTTP content bridge starts without secure-context crypto.randomUUID", () => {
  const posts = [];
  let command;
  const port = {
    onMessage: { addListener: callback => { command = callback; } },
    onDisconnect: { addListener() {} }, postMessage() {}, disconnect() {}
  };
  runInNewContext(readFileSync(new URL("../../Extensions/Chrome/content-bridge.js", import.meta.url), "utf8"), {
    crypto: { getRandomValues: bytes => { bytes.fill(7); return bytes; } },
    window: { addEventListener() {}, removeEventListener() {}, postMessage: message => posts.push(message) },
    location: { origin: "http://example.org" }, chrome: { runtime: { id: "extension", connect: () => port } },
    setInterval() { return 1; }, clearInterval() {}, setTimeout() { return 2; }, clearTimeout() {}
  });
  command({ type: "init", volume: 0.3, requestID: "request" });
  assert.equal(posts.length, 1);
  assert.match(posts[0].bridgeID, /^[a-f0-9]{32}$/);
  assert.equal(posts[0].volume, 0.3);
});
