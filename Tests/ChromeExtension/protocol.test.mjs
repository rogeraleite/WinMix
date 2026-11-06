import test from "node:test";
import assert from "node:assert/strict";
import { validCommand, validPlayerState, tabMetadata } from "../../Extensions/Chrome/protocol.js";

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

test("playback commands are explicit and cannot write volume or mute", () => {
  const command = { version: 1, type: "playback", session: "s", requestID: "r", tabID: 1, action: "pause" };
  assert.equal(validCommand(command), true);
  assert.equal(validCommand({ ...command, action: "play" }), true);
  for (const change of [{ action: "toggle" }, { action: null }, { volume: 0.5 }, { muted: false },
    { session: "" }, { requestID: "" }, { tabID: -1 }, { type: "set" }]) {
    assert.equal(validCommand({ ...command, ...change }), false);
  }
  assert.equal(validCommand({ version: 1, type: "set", session: "s", requestID: "r", tabID: 1,
    volume: 0.5, muted: false, action: "pause" }), false);
  const metadata = tabMetadata({ id: 1 }, { playing: true, canPlay: false, canPause: true, playbackIssue: "Blocked" });
  assert.equal(metadata.playing, true); assert.equal(metadata.canPlay, false);
  assert.equal(metadata.canPause, true); assert.equal(metadata.playbackIssue, "Blocked");
  assert.equal(tabMetadata({ id: 2 }).canPlay, undefined);
});

test("frame state validates playback counts and capabilities while accepting legacy volume state", () => {
  const legacy = { volume: 0.3, mediaCount: 2, playingCount: 1 };
  assert.equal(validPlayerState(legacy), true);
  const state = { ...legacy, audibleCount: 0, canPlay: false, canPause: true, resumeCount: 0 };
  assert.equal(validPlayerState(state), true);
  for (const change of [{ audibleCount: 2 }, { resumeCount: 3 }, { canPlay: "yes" },
    { canPause: undefined }, { playbackIssue: "x".repeat(513) }, { volume: Infinity }, { playingCount: -1 }]) {
    assert.equal(validPlayerState({ ...state, ...change }), false);
  }
  assert.equal(validPlayerState({ ...legacy, canPlay: true }), false);
});
