import test from "node:test";
import assert from "node:assert/strict";
import { TabCommandQueue } from "../../Extensions/Chrome/command-queue.js";

test("a stalled tab does not block another tab; commands in the same tab stay ordered", async () => {
  const queue = new TabCommandQueue(), events = [];
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const one = queue.enqueue(1, async () => { events.push("first"); await gate; events.push("confirmed"); });
  const two = queue.enqueue(1, () => events.push("latest"));
  await queue.enqueue(2, () => events.push("other tab"));
  assert.deepEqual(events, ["first", "other tab"]);
  release(); await Promise.all([one, two]);
  assert.deepEqual(events, ["first", "other tab", "confirmed", "latest"]);
});

test("failure does not poison a tab queue and shutdown waits for earlier commands", async () => {
  const queue = new TabCommandQueue(), events = [];
  const failure = queue.enqueue(1, () => { throw new Error("Player unavailable"); });
  const next = queue.enqueue(1, () => events.push("next"));
  const shutdown = queue.drain(() => events.push("restore"));
  const after = queue.enqueue(2, () => events.push("after restore"));
  await assert.rejects(failure, /Player unavailable/);
  await Promise.all([next, shutdown, after]);
  assert.deepEqual(events, ["next", "restore", "after restore"]);
});
