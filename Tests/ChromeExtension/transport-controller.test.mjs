import test from "node:test";
import assert from "node:assert/strict";
import "../../Extensions/Chrome/transport-controller.js";

const Controller = globalThis[Symbol.for("MacVolume.TransportController")];

function fixture({ host = "music.youtube.com", topFrame = true, semanticState = true } = {}) {
  let shuffled = false, changed = 0;
  const media = { currentSrc: "blob:song", currentTime: 30 };
  const document = { title: "Track 1", location: { href: "https://music.youtube.com/" },
    querySelectorAll: () => [root],
    querySelector: selector => selector === "video, audio" ? media : selector === "ytmusic-app" ? app : undefined };
  function button(click) {
    return { disabled: false, hidden: false, clicks: 0,
      getAttribute(name) { return semanticState && name === "aria-pressed" && this === shuffle ? String(shuffled) : null; },
      closest() { return this.hidden ? {} : null; }, getClientRects() { return [{}]; }, querySelectorAll() { return []; },
      click() { this.clicks++; click(); } };
  }
  const previous = button(() => { media.currentTime = 0; });
  const next = button(() => { document.title = "Track 2"; });
  const shuffle = button(() => { shuffled = !shuffled; });
  const root = { querySelectorAll: selector => selector.includes("previous") || selector.includes("prev-button") ? [previous] :
    selector.includes("next") ? [next] : [shuffle] };
  const app = semanticState ? undefined : { polymerController: { store: { getState: () => ({ queue: { shuffleEnabled: shuffled } }) } } };
  const controller = new Controller({ document, hostname: host, topFrame, changed: () => { changed++; } });
  return { controller, previous, next, shuffle, media, document, changed: () => changed };
}

test("next and previous confirm a track change or restart without touching media gain", async () => {
  const f = fixture();
  assert.equal(f.controller.state().canNext, true);
  await f.controller.set("next");
  assert.equal(f.document.title, "Track 2"); assert.equal(f.next.clicks, 1);
  await f.controller.set("previous");
  assert.equal(f.media.currentTime, 0); assert.equal(f.previous.clicks, 1);
  assert.equal(f.changed(), 2);
});

test("explicit shuffle commands are idempotent and follow semantic or shared queue state", async () => {
  for (const semanticState of [true, false]) {
    const f = fixture({ semanticState });
    assert.equal(f.controller.state().shuffleEnabled, false);
    await f.controller.set("shuffle-on"); await f.controller.set("shuffle-on");
    assert.equal(f.controller.state().shuffleEnabled, true); assert.equal(f.shuffle.clicks, 1);
    await f.controller.set("shuffle-off"); await f.controller.set("shuffle-off");
    assert.equal(f.controller.state().shuffleEnabled, false); assert.equal(f.shuffle.clicks, 2);
  }
});

test("hidden, disabled, unsupported and iframe controls never receive a click", async () => {
  for (const options of [{ host: "example.com" }, { host: "youtube.com.attacker.test" }, { topFrame: false }]) {
    const f = fixture(options);
    assert.equal(f.controller.state().canNext, false);
    await assert.rejects(f.controller.set("next"), /does not offer/);
    assert.equal(f.next.clicks, 0);
  }
  const f = fixture(); f.next.disabled = true; f.previous.hidden = true;
  assert.equal(f.controller.state().canNext, false); assert.equal(f.controller.state().canPrevious, false);
  await assert.rejects(f.controller.set("next"), /does not offer/);
  await assert.rejects(f.controller.set("play"), /Invalid track action/);
  assert.equal(f.next.clicks, 0);
});

test("an unconfirmed track change reports failure and is not clicked twice", async () => {
  const f = fixture(); f.next.click = () => { f.next.clicks++; };
  await assert.rejects(f.controller.set("next"), /did not confirm/);
  assert.equal(f.next.clicks, 1);
  assert.match(f.controller.state().transportIssue, /did not confirm/);
});

test("shuffle is unavailable when the site cannot report its state", async () => {
  const f = fixture({ semanticState: false });
  f.document.querySelector = selector => selector === "video, audio" ? f.media : undefined;
  assert.equal(f.controller.state().canShuffle, false);
  await assert.rejects(f.controller.set("shuffle-on"), /does not report/);
  assert.equal(f.shuffle.clicks, 0);
});
