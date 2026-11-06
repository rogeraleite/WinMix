import test from "node:test";
import assert from "node:assert/strict";
import { validCommand, tabMetadata } from "../../Extensions/Chrome/protocol.js";

test("bridge commands reject malformed or unsafe values", () => {
  const command = { version: 1, type: "set", session: "s", requestID: "r", tabID: 1, volume: 0.4, muted: false };
  assert.equal(validCommand(command), true);
  for (const change of [{ version: 2 }, { tabID: -1 }, { volume: NaN }, { volume: 2 }, { muted: 0 }, { session: "" }, { requestID: "" }]) {
    assert.equal(validCommand({ ...command, ...change }), false);
  }
});

test("metadata preserves distinct tabs, mute-only capability and Unicode titles", () => {
  const one = tabMetadata({ id: 1, title: "Same", url: "https://www.youtube.com/", audible: true });
  const two = tabMetadata({ id: 2, title: "Same", url: "https://www.youtube.com/", audible: true },
    { controlled: false, volume: 1, muted: true, audible: true, canMute: true, controlMode: "page", issue: "Volume unavailable" });
  assert.notEqual(one.id, two.id);
  assert.equal(two.controlled, false); assert.equal(two.canMute, true);
  assert.equal(two.controlMode, "page"); assert.equal(two.muted, true);
  const title = tabMetadata({ id: 3, title: "a".repeat(511) + "🎵", url: "https://music.youtube.com" });
  assert.equal(title.title.endsWith("🎵"), true);
});
