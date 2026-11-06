import test from "node:test";
import assert from "node:assert/strict";
import "../../Extensions/Chrome/media-controller.js";

const Controller = globalThis[Symbol.for("MacVolume.MediaController")];
const media = (volume = 1) => ({ actual: volume, paused: false, ended: false, muted: false, attached: true, source: true });
function controller() {
  return new Controller({ getVolume: e => e.actual, setVolume: (e, value) => { e.actual = value; },
    isPlaying: e => !e.paused && !e.ended,
    isAudible: e => !e.muted, canPlay: e => e.attached && e.source && !e.ended,
    play: async e => { if (e.blocked) throw new Error("Playback blocked"); e.paused = false; },
    pause: e => { e.paused = true; }, changed: () => {} });
}

test("independent tabs multiply site volume exactly once", () => {
  const one = controller(), two = controller(), a = media(0.8), b = media(0.6);
  one.track(a); two.track(b);
  one.setGain(0.3); two.setGain(0.7);
  assert.ok(Math.abs(a.actual - 0.24) < 1e-12);
  assert.ok(Math.abs(b.actual - 0.42) < 1e-12);
  for (let i = 0; i < 10; i++) one.setGain(0.3);
  assert.ok(Math.abs(a.actual - 0.24) < 1e-12);
  assert.equal(one.baseVolume(a), 0.8);
});

test("site volume changes compose with the existing tab gain", () => {
  const c = controller(), e = media(0.5);
  c.track(e); c.setGain(0.3); c.setBaseVolume(e, 0.9);
  assert.equal(c.baseVolume(e), 0.9);
  assert.ok(Math.abs(e.actual - 0.27) < 1e-12);
  c.observeNativeChange(e); // Own volumechange event must not multiply again.
  assert.equal(c.baseVolume(e), 0.9);
  e.actual = 0.4; c.observeNativeChange(e); // A native/browser volume control.
  assert.equal(c.baseVolume(e), 0.4);
  assert.ok(Math.abs(e.actual - 0.12) < 1e-12);
});

test("new players inherit the tab gain; pause is distinct from zero gain", () => {
  const c = controller(), a = media(), b = media(0.5);
  c.setGain(0.2); c.track(a); c.track(b);
  assert.equal(a.actual, 0.2); assert.equal(b.actual, 0.1);
  assert.equal(c.state().playingCount, 2);
  c.setGain(0); assert.equal(c.state().playingCount, 2);
  a.paused = true; assert.equal(c.state().playingCount, 1);
  b.muted = true; assert.equal(c.state().playingCount, 1);
  assert.equal(c.state().audibleCount, 0);
});

test("reset and removal restore site volume", () => {
  const c = controller(), a = media(0.8), b = media(0.6);
  c.track(a); c.track(b); c.setGain(0.2);
  c.untrack(a); assert.equal(a.actual, 0.8);
  assert.equal(c.state().mediaCount, 1);
  c.reset(); assert.equal(b.actual, 0.6);
  c.track(a); assert.equal(a.actual, 0.8);
});

test("invalid input never alters existing volume", () => {
  const c = controller(), e = media(0.5);
  c.track(e); c.setGain(0.3);
  for (const value of [-1, 2, NaN, Infinity, "0.5"]) assert.throws(() => c.setGain(value));
  assert.ok(Math.abs(e.actual - 0.15) < 1e-12);
});

test("pause and resume are independent, idempotent, and leave gains and mute unchanged", async () => {
  const one = controller(), two = controller(), a = media(0.8), b = media(0.6), preload = media();
  preload.paused = true;
  one.track(a); one.track(preload); two.track(b);
  one.setGain(0.3); two.setGain(0.7); a.muted = true;
  assert.equal(one.state().playingCount, 1);
  assert.equal(one.state().canPause, true);
  await one.setPlayback("pause"); await one.setPlayback("pause");
  assert.equal(a.paused, true); assert.equal(b.paused, false);
  assert.equal(one.state().resumeCount, 1);
  await one.setPlayback("play"); await one.setPlayback("play");
  assert.equal(a.paused, false); assert.equal(preload.paused, true);
  assert.equal(a.muted, true);
  assert.ok(Math.abs(a.actual - 0.24) < 1e-12);
  assert.ok(Math.abs(b.actual - 0.42) < 1e-12);
});

test("resume remembers all active players and fallback selects only the latest active player", async () => {
  const c = controller(), a = media(), b = media(), idle = media(); idle.paused = true;
  c.track(a); c.track(b); c.track(idle);
  await c.setPlayback("pause"); await c.setPlayback("play");
  assert.equal(a.paused, false); assert.equal(b.paused, false); assert.equal(idle.paused, true);
  c.notePlaying(a); c.notePlaying(b); a.paused = true; b.paused = true;
  await assert.rejects(c.setPlayback("play"), /available/); // No main-frame fallback grant.
  await c.setPlayback("play", true);
  assert.equal(a.paused, true); assert.equal(b.paused, false);
});

test("removed, ended and source-less resume targets do not restart; new players inherit gain only", async () => {
  const c = controller(), removed = media(), ended = media(), empty = media();
  c.track(removed); c.track(ended); c.track(empty); c.setGain(0.2);
  await c.setPlayback("pause");
  removed.attached = false; ended.ended = true; empty.source = false;
  assert.equal(c.state().resumeCount, 0); assert.equal(c.state().canPlay, false);
  await assert.rejects(c.setPlayback("play", true), /available/);
  const fresh = media(0.5); fresh.paused = true; c.track(fresh);
  assert.equal(fresh.actual, 0.1); assert.equal(fresh.paused, true);
  assert.equal(c.state().canPlay, false);
});

test("blocked and stalled Play report an issue without claiming success or changing gain", async () => {
  const c = controller(), a = media(0.8); c.track(a); c.setGain(0.3);
  await c.setPlayback("pause"); a.blocked = true;
  await assert.rejects(c.setPlayback("play"), /Playback blocked/);
  assert.equal(c.state().playingCount, 0); assert.equal(c.state().resumeCount, 1);
  assert.match(c.state().playbackIssue, /Playback blocked/);
  assert.ok(Math.abs(a.actual - 0.24) < 1e-12);
  a.blocked = false; await c.setPlayback("play");
  assert.equal(c.state().playbackIssue, undefined);
  c.play = () => new Promise(() => {});
  await c.setPlayback("pause");
  await assert.rejects(c.setPlayback("play"), /confirm playback/);
  assert.equal(c.state().playingCount, 0);
  await assert.rejects(c.setPlayback("toggle"), /Invalid playback/);
});
