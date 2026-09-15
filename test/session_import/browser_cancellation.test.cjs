"use strict";

// Real shipped protocol/content scripts in an isolated VM. The small DOM below
// models only the selectors/events these scripts use; it never starts a browser,
// reads a profile, loads a page, or performs HTTP/native messaging.
const assert = require("node:assert/strict");
const test = require("node:test");
const { fixture, settle, writtenAttribute } = require("./browser_dom_fixture.cjs");

function observed(promise) { return promise.then((result) => ({ result }), (error) => ({ error })); }
function assertCancelled(result) { assert.equal(result.error?.code, "preparation_cancelled"); }
function assertNoSave(state) { assert.equal(state.writes.some((write) => write.target === "save"), false); }

test("initial cancellation rejects before any DOM write or opening click", async () => {
  const state = fixture({ open: false });
  const result = await observed(state.prepare({ assertActive() { throw state.cancelError(); } }));
  assertCancelled(result);
  assert.deepEqual(state.writes, []);
  assert.equal(state.observerCount, 0);
});

test("cancellation during editor discovery prevents all writes when the editor appears later", async () => {
  const state = fixture({ open: false });
  let active = true;
  const pending = observed(state.prepare({ assertActive() { if (!active) throw state.cancelError(); } }));
  await settle();
  assert.equal(state.writes.filter((write) => write.kind === "click").length, 1);
  active = false;
  const before = state.writes.length;
  state.fixtureWrite(() => state.document.body.appendChild(state.editor));
  const result = await pending;
  assertCancelled(result);
  assert.equal(state.writes.length, before);
  assert.equal(state.observerCount, 0);
  assertNoSave(state);
});

test("cancellation during spot delay prevents cleanup markers and subsequent field writes", async () => {
  const state = fixture({ initialSpot: "1", previouslyWritten: true });
  let active = true;
  const pending = observed(state.prepare({ assertActive() { if (!active) throw state.cancelError(); } }));
  await settle();
  assert.equal(state.select.value, "77");
  active = false;
  const before = state.writes.length;
  await state.advance(60);
  assertCancelled(await pending);
  assert.equal(state.writes.length, before, "Cleanup must not remove write markers after cancellation.");
  assert.equal(state.fields.loot.getAttribute(writtenAttribute), "true");
  assert.equal(state.fields.loot.value, "7");
  assertNoSave(state);
});

test("deadline expiration during spot delay cannot cause late writes", async () => {
  const state = fixture({ initialSpot: "1" });
  const pending = observed(state.prepare({ assertActive() { if (state.now >= 50) throw state.cancelError(); } }));
  await settle();
  const before = state.writes.length;
  await state.advance(50);
  assert.equal(state.writes.length, before);
  await state.advance(500);
  assertCancelled(await pending);
  assert.equal(state.writes.length, before);
  assert.equal(state.fields["duration-minutes"].value, "");
  assert.equal(state.editor.getAttribute("data-bsl-session-import-draft"), null);
});

test("tooltip delay cancellation blocks hover-out events and later item writes", async () => {
  const state = fixture({ tooltipOnly: true });
  let active = true;
  const pending = observed(state.prepare({ assertActive() { if (!active) throw state.cancelError(); } }));
  await settle();
  assert.ok(state.writes.some((write) => write.target === "marker" && write.name === "mouseover"));
  active = false;
  const before = state.writes.length;
  await state.advance(45);
  assertCancelled(await pending);
  assert.equal(state.writes.length, before);
  assert.equal(state.fields.loot.value, "7");
  assert.equal(state.observerCount, 0);
  assertNoSave(state);
});

test("cancellation from a hover event still disconnects tooltip observation", async () => {
  const state = fixture({ tooltipOnly: true });
  let active = true;
  let atCancellation = 0;
  state.marker.addEventListener("mouseover", () => { active = false; atCancellation = state.writes.length; });
  const result = await observed(state.prepare({ assertActive() { if (!active) throw state.cancelError(); } }));
  assertCancelled(result);
  assert.equal(state.writes.length, atCancellation);
  assert.equal(state.observerCount, 0, "Cancellation must disconnect the observer even before the first await.");
  await state.advance(1000);
  assert.equal(state.writes.length, atCancellation);
});

test("cancellation from an input event prevents later change/blur events and subsequent fields", async () => {
  const state = fixture();
  let active = true;
  let atCancellation = 0;
  state.fields["duration-minutes"].addEventListener("input", () => { active = false; atCancellation = state.writes.length; });
  const result = await observed(state.prepare({ assertActive() { if (!active) throw state.cancelError(); } }));
  assertCancelled(result);
  assert.equal(state.writes.length, atCancellation);
  assert.equal(state.fields.mastery.value, "");
  assert.equal(state.fields.loot.value, "7");
  assert.equal(state.writes.some((write) => write.name === "change" || write.name === "blur"), false);
  assertNoSave(state);
});

test("cancellation during item readback does not mark a late completed draft", async () => {
  const state = fixture();
  let active = true;
  const pending = observed(state.prepare({ assertActive() { if (!active) throw state.cancelError(); } }));
  await settle();
  assert.equal(state.fields.loot.value, "59");
  active = false;
  const before = state.writes.length;
  await state.advance(45);
  assertCancelled(await pending);
  assert.equal(state.writes.length, before);
  assert.equal(state.editor.getAttribute("data-bsl-session-import-draft"), null);
});

test("concurrent preparations are rejected without replacing the first cancellation guard", async () => {
  const state = fixture({ initialSpot: "1" });
  let firstActive = true;
  let secondGuardCalls = 0;
  const first = observed(state.prepare({ assertActive() { if (!firstActive) throw state.cancelError(); } }));
  await settle();
  const before = state.writes.length;
  const second = await observed(state.prepare({ assertActive() { secondGuardCalls += 1; } }));
  assert.equal(second.error?.code, "preparation_busy");
  assert.equal(secondGuardCalls, 0);
  assert.equal(state.writes.length, before);
  firstActive = false;
  await state.advance(60);
  assertCancelled(await first);
  assert.equal(state.writes.length, before);
});

test("the busy gate resets after cancellation and the next default preparation succeeds", async () => {
  const state = fixture();
  assertCancelled(await observed(state.prepare({ assertActive() { throw state.cancelError(); } })));
  const next = observed(state.prepare());
  await state.advance(45);
  const result = await next;
  assert.equal(result.result?.ok, true);
  assert.equal(state.fields.loot.value, "59");
  assert.equal(state.editor.getAttribute("data-bsl-session-import-draft"), "fixture-cancellation");
  assertNoSave(state);
});

test("a timed-out caller cannot replace an older in-flight guard, then can retry after it settles", async () => {
  const state = fixture({ initialSpot: "1" });
  const first = observed(state.prepare({ assertActive() { if (state.now >= 50) throw state.cancelError(); } }));
  await settle();
  const before = state.writes.length;
  await state.advance(50); // Caller deadline expires before the 60 ms spot wait.
  const overlap = await observed(state.prepare());
  assert.equal(overlap.error?.code, "preparation_busy");
  await state.advance(10);
  assertCancelled(await first);
  assert.equal(state.writes.length, before);
  const next = observed(state.prepare());
  await state.advance(45);
  assert.equal((await next).result?.ok, true);
  assert.equal(state.fields.loot.value, "59");
  assertNoSave(state);
});

test("editor timeout disconnects observation and a late editor cannot receive stale writes", async () => {
  const state = fixture({ open: false });
  const first = observed(state.prepare());
  await state.advance(6000);
  assert.equal((await first).error?.code, "editor_not_found");
  assert.equal(state.observerCount, 0);
  const before = state.writes.length;
  state.fixtureWrite(() => state.document.body.appendChild(state.editor));
  await state.advance(6000);
  assert.equal(state.writes.length, before);
  assert.equal(state.fields.loot.value, "7");
  const next = observed(state.prepare());
  await state.advance(45);
  assert.equal((await next).result?.ok, true);
  assertNoSave(state);
});

test("the busy gate resets after validation errors without weakening plain-object checks", async () => {
  const state = fixture();
  const invalid = await observed(state.prepare(undefined, { schemaVersion: 1 }));
  assert.equal(invalid.error?.code, "invalid_draft");
  assert.deepEqual(state.writes, []);
  const next = observed(state.prepare());
  await state.advance(45);
  assert.equal((await next).result?.ok, true);
});

test("the default Firefox message listener still fills reviewed fields and never saves", async () => {
  const state = fixture({ initialSpot: "1" });
  const listener = state.listeners[0];
  const pending = observed(listener({ type: "prepare_draft", draft: state.draft() }));
  await state.advance(105);
  const result = (await pending).result;
  assert.equal(result.ok, true);
  assert.equal(result.matched.length, 1);
  assert.equal(result.skipped.length, 0);
  assert.equal(state.select.value, "77");
  assert.equal(state.fields["duration-minutes"].value, "60");
  assert.equal(state.fields.mastery.value, "2000");
  assert.equal(state.fields["energy-spent"].value, "321");
  assert.equal(state.fields.loot.value, "59");
  assertNoSave(state);
  assert.equal((await listener({ type: "tracker_ping" })).ready, true);
  assert.equal((await listener({ type: "tracker_status" })).draftId, "fixture-cancellation");
});

test("guarded and default preparations produce identical successful mutations", async () => {
  const guarded = fixture({ initialSpot: "1", previouslyWritten: true });
  const ordinary = fixture({ initialSpot: "1", previouslyWritten: true });
  let checks = 0;
  const first = observed(guarded.prepare({ assertActive() { checks += 1; } }));
  const second = observed(ordinary.prepare());
  await guarded.advance(105);
  await ordinary.advance(105);
  assert.equal((await first).result?.ok, true);
  assert.equal((await second).result?.ok, true);
  assert.ok(checks > 1);
  assert.deepEqual(guarded.writes, ordinary.writes);
  assertNoSave(guarded);
});
