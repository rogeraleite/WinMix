import test from "node:test";
import assert from "node:assert/strict";
import "../../Extensions/Chrome/media-controller.js";

const Controller = globalThis[Symbol.for("MacVolume.MediaController")];
const media = (volume = 1) => ({ actual: volume, paused: false, ended: false, muted: false });
function controller() {
  return new Controller({ getVolume: e => e.actual, setVolume: (e, value) => { e.actual = value; },
    isPlaying: e => !e.paused && !e.ended && !e.muted, changed: () => {} });
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
  b.muted = true; assert.equal(c.state().playingCount, 0);
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
