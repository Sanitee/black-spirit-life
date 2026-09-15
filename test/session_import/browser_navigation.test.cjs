"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { fixture, settle } = require("./browser_dom_fixture.cjs");

function remove(element) {
  element.parentElement.children = element.parentElement.children.filter((child) => child !== element);
  element.parentElement = null;
}
function landing({spotId = null} = {}) {
  const state = fixture({open:false});
  state.fixtureWrite(() => remove(state.opener));
  state.context.location = new URL("https://garmoth.com/grind-tracker/best-grind-spots");
  const originalDraft = state.draft;
  // Older callers can be name-only. Do not accidentally attach the unrelated
  // editor fixture ID 77 to rendered navigation examples with different IDs.
  state.draft = () => {
    const draft = originalDraft();
    draft.target.spotId = spotId;
    return draft;
  };
  return state;
}
function link(state, name, href) {
  let result;
  state.fixtureWrite(() => { result = state.document.body.appendChild(new state.Element("a", {href}, name)); });
  return result;
}
function noWrites(state) { assert.equal(state.writes.length, 0, "discovery never clicks or changes fields"); }
function optionalInput(state, name, type = "number", value = "19") {
  let input;
  state.fixtureWrite(() => {
    input = state.editor.appendChild(new state.HTMLInputElement({"aria-label":name,type}));
    input.value = value;
  });
  return input;
}
function agrisCheckbox(state, checked) {
  const control = optionalInput(state, "Agris Fever", "checkbox", "on");
  control.checked = checked;
  control.addEventListener("click", () => { control.checked = !control.checked; });
  return control;
}
function trackerSidebar(state, {collapsed = false, placeholder = false} = {}) {
  state.context.Date = class extends Date { static now() { return state.now; } };
  let aside;
  let back;
  const buttons = {};
  const addCategories = () => {
    const anchor = aside.appendChild(new state.Element("a", {href:"/grind-tracker/user/summary",class:"grid grid-cols-4 gap-1"}));
    for (const title of ["Grinding", "Lifeskill", "Scrolls", "Dungeon"]) {
      const button = anchor.appendChild(new state.HTMLButtonElement({type:"button"}, ""));
      button.appendChild(new state.Element("span", {}, title));
      buttons[title] = button;
      if (title === "Lifeskill") button.addEventListener("click", () => {
        const group = aside.appendChild(new state.Element("div", {}, "STONE SPOTS"));
        group.appendChild(new state.Element("a", {href:placeholder ? "/grind-tracker/null/spot/186" : "/grind-tracker/user/spot/186"}, "Rusalka's Coral"));
      });
    }
    state.document.hitElement = buttons.Lifeskill;
  };
  state.fixtureWrite(() => {
    const main = state.document.body.appendChild(new state.Element("main", {id:"main"}));
    const menu = main.appendChild(new state.Element("div", {id:"grind-menu"}));
    aside = menu.appendChild(new state.Element("aside", {class:"w-72 fixed"}));
    if (collapsed) {
      const row = aside.appendChild(new state.Element("div", {class:"flex items-center gap-1"}));
      back = row.appendChild(new state.Element("div", {class:"font-bold"}, "BACK"));
      back.addEventListener("click", () => { remove(back); addCategories(); });
      state.document.hitElement = back;
    } else addCategories();
  });
  return {aside,back,buttons};
}
function executeNav(state, action, draft = state.draft(), options = {}) {
  return state.context.TrackerContentTest.executeNavigationStep(state.document, draft, action,
    {assertActive() {},deadline:state.now + 10000,expectedUrl:state.discover(draft).expectedUrl,...options});
}
async function prepare(state, session = {}) {
  const draft = state.draft();
  Object.assign(draft.session, session);
  const pending = state.prepare(undefined, draft);
  await state.advance(150);
  return pending;
}

test("discovery resolves only the exact spot's rendered same-origin href", () => {
  const state = landing();
  link(state, "Personal tracker", "/grind-tracker/user-from-page/summary");
  link(state, "Rusalka's Coral Reef", "/grind-tracker/user-from-page/spot/other");
  link(state, "Rusalka’s Coral", "/grind-tracker/user-from-page/spot/actual-id");
  const result = state.discover();
  assert.equal(result.state, "navigate");
  assert.equal(result.url, "https://garmoth.com/grind-tracker/user-from-page/spot/actual-id");
  noWrites(state);
});

test("discovery recognizes exact child title without guessing a slug", () => {
  const state = landing();
  const row = link(state, "Recommended 300 AP ", "/grind-tracker/opaque-account/spot/opaque-spot");
  state.fixtureWrite(() => row.appendChild(new state.Element("h3", {}, "Rusalka's Coral")));
  assert.equal(state.discover().url, "https://garmoth.com/grind-tracker/opaque-account/spot/opaque-spot");
  noWrites(state);
});

test("personal tracker fallback uses the rendered href; no link never constructs target.url", () => {
  const state = landing();
  assert.equal(state.discover().state, "blocked");
  link(state, "Summary", "/grind-tracker/rendered-user/summary");
  assert.equal(state.discover().url, "https://garmoth.com/grind-tracker/rendered-user/summary");
  noWrites(state);
});

test("Summary takes precedence over generic tracker navigation and bare tracker redirect loops", () => {
  const state = landing();
  link(state, "Grind Tracker", "/grind-tracker/");
  link(state, "Grind Tracker", "/grind-tracker/public-overview");
  link(state, "Summary", "/grind-tracker/rendered-personal/summary");
  assert.equal(state.discover().url, "https://garmoth.com/grind-tracker/rendered-personal/summary");
  link(state, "My tracker", "/grind-tracker/explicit-personal/summary");
  assert.equal(state.discover().url, "https://garmoth.com/grind-tracker/explicit-personal/summary");
  noWrites(state);
});

test("explicit Add session works without a text Grind Tracker header", () => {
  const state = fixture({open:false});
  state.fixtureWrite(() => remove(state.document.querySelectorAll("h1")[0]));
  assert.equal(state.discover().state, "ready");
  assert.equal(state.context.TrackerContentTest.findOpenEditorButton(state.document), state.opener);
  noWrites(state);
});

test("generic Add requires session context and refuses ambiguous controls", () => {
  const state = landing();
  let generic;
  state.fixtureWrite(() => { generic = state.document.body.appendChild(new state.HTMLButtonElement({type:"button"}, "Add")); });
  assert.equal(state.context.TrackerContentTest.findOpenEditorButton(state.document), null);
  state.fixtureWrite(() => generic.setAttribute("aria-haspopup", "dialog"));
  assert.equal(state.context.TrackerContentTest.findOpenEditorButton(state.document), generic);
  state.fixtureWrite(() => state.document.body.appendChild(new state.HTMLButtonElement({type:"button","aria-haspopup":"dialog"}, "Add")));
  assert.equal(state.context.TrackerContentTest.findOpenEditorButton(state.document), null);
  noWrites(state);
});

test("observed collapsed BACK and Lifeskill controls expose the exact rendered Rusalka href", async () => {
  const state = landing({spotId:"186"});
  trackerSidebar(state, {collapsed:true});
  assert.equal(state.discover().action, "expand_tracker");
  assert.equal(executeNav(state, "expand_tracker").acted, true);
  assert.equal(state.discover().action, "select_activity");
  assert.equal(executeNav(state, "select_activity").acted, true);
  assert.equal(state.discover().state, "loading");
  await state.advance(300);
  const result = state.discover();
  assert.equal(result.state, "navigate");
  assert.equal(result.url, "https://garmoth.com/grind-tracker/user/spot/186");
  assert.equal(state.writes.filter((write) => write.kind === "click").length, 2);
  assert.equal(state.writes.some((write) => write.target === "save"), false);
});

test("clipped spot link is navigated by href after selecting Lifeskill, not clicked", async () => {
  const state = landing({spotId:"186"});
  const sidebar = trackerSidebar(state);
  assert.equal(state.discover().action, "select_activity");
  executeNav(state, "select_activity");
  await state.advance(300);
  assert.equal(state.document.hitElement, sidebar.buttons.Lifeskill);
  assert.equal(state.discover().url, "https://garmoth.com/grind-tracker/user/spot/186");
  assert.equal(state.writes.filter((write) => write.kind === "click").length, 1);
});

test("grinding selects Grinding while gathering and hunting select Lifeskill", () => {
  for (const [activity, category] of [["grinding","Grinding"],["gathering","Lifeskill"],["hunting","Lifeskill"]]) {
    const state = landing();
    const sidebar = trackerSidebar(state);
    state.document.hitElement = sidebar.buttons[category];
    const draft = state.draft();
    draft.target.activity = activity;
    assert.equal(state.discover(draft).action, "select_activity");
    assert.equal(executeNav(state, "select_activity", draft).acted, true);
    assert.equal(state.writes.filter((write) => write.kind === "click").length, 1);
  }
});

test("unrelated BACK and category-like controls outside the observed tracker sidebar are not clicked", () => {
  const state = landing();
  state.fixtureWrite(() => {
    state.document.hitElement = state.document.body.appendChild(new state.Element("div", {}, "BACK"));
    const link = state.document.body.appendChild(new state.Element("a", {href:"/grind-tracker/user/summary"}));
    for (const name of ["Grinding","Lifeskill","Scrolls","Dungeon"]) link.appendChild(new state.HTMLButtonElement({type:"button"}, name));
  });
  assert.equal(state.discover().state, "blocked");
  assert.equal(executeNav(state, "expand_tracker").acted, false);
  noWrites(state);
});

test("navigation actions refuse a changed action, expired deadline or cancelled request", () => {
  const state = landing();
  trackerSidebar(state, {collapsed:true});
  assert.equal(executeNav(state, "select_activity").acted, false);
  assert.equal(executeNav(state, "expand_tracker", state.draft(), {deadline:0}).acted, false);
  assert.throws(() => executeNav(state, "expand_tracker", state.draft(), {assertActive() { throw state.cancelError(); }}));
  noWrites(state);
});

test("category action exposes and revalidates only its rendered parent summary destination", () => {
  const state = landing();
  const sidebar = trackerSidebar(state);
  const decision = state.discover();
  assert.equal(decision.expectedUrl, "https://garmoth.com/grind-tracker/user/summary");
  assert.equal(executeNav(state, "select_activity", state.draft(), {expectedUrl:"https://garmoth.com/grind-tracker/other/summary"}).acted, false);
  noWrites(state);
  sidebar.buttons.Lifeskill.addEventListener("click", () => { state.context.location = new URL(decision.expectedUrl); });
  assert.equal(executeNav(state, "select_activity", state.draft(), {expectedUrl:decision.expectedUrl}).acted, true);
  assert.equal(state.context.location.href, decision.expectedUrl);
  assert.equal(state.writes.filter((write) => write.kind === "click").length, 1);
});

test("a parent href changed after discovery is refused before the nested button click", () => {
  const state = landing();
  const sidebar = trackerSidebar(state);
  const expectedUrl = state.discover().expectedUrl;
  state.fixtureWrite(() => sidebar.buttons.Lifeskill.parentElement.setAttribute("href", "/grind-tracker/other/summary"));
  assert.equal(executeNav(state, "select_activity", state.draft(), {expectedUrl}).acted, false);
  noWrites(state);
});

test("null account placeholder links are rejected after category selection", async () => {
  const state = landing();
  trackerSidebar(state, {placeholder:true});
  executeNav(state, "select_activity");
  await state.advance(300);
  assert.equal(state.discover().state, "blocked");
  for (const path of ["/null/spot/186", "/undefined/summary", "/%6eull/spot/186"]) {
    assert.equal(state.context.TrackerProtocol.isGarmothTrackerUrl("https://garmoth.com/grind-tracker" + path, false), false);
  }
});

test("a visible Login still stops sidebar actions and never starts account automation", () => {
  const state = landing();
  trackerSidebar(state, {collapsed:true});
  link(state, "Login", "/login");
  assert.equal(state.discover().state, "login_required");
  assert.equal(executeNav(state, "expand_tracker").acted, false);
  noWrites(state);
});

test("ambiguous exact spot destinations block while duplicate links to one destination deduplicate", () => {
  const state = landing();
  link(state, "Rusalka's Coral", "/grind-tracker/a/spot/1");
  link(state, "Rusalka's Coral", "/grind-tracker/a/spot/1");
  assert.equal(state.discover().state, "navigate");
  link(state, "Rusalka's Coral", "/grind-tracker/b/spot/1");
  assert.equal(state.discover().state, "blocked");
  noWrites(state);
});

test("unsafe, external, download and self links are never navigation destinations", () => {
  for (const href of ["http://garmoth.com/grind-tracker/a", "https://garmoth.com.evil.test/grind-tracker/a",
    "https://name:secret@garmoth.com/grind-tracker/a", "/best-grind-spots", "/grind-tracker/delete/1",
    "javascript:alert(1)", "/grind-tracker/best-grind-spots#same-page"]) {
    const state = landing();
    link(state, "Rusalka's Coral", href);
    assert.equal(state.discover().state, "blocked", href);
    noWrites(state);
  }
  const state = landing();
  const download = link(state, "Rusalka's Coral", "/grind-tracker/a/spot/1");
  state.fixtureWrite(() => download.setAttribute("download", ""));
  assert.equal(state.discover().state, "blocked");
});

test("an existing session select can change the spot without unsolicited navigation", () => {
  const state = fixture({initialSpot:"1"});
  link(state, "Rusalka's Coral", "/grind-tracker/elsewhere/spot/77");
  assert.equal(state.discover().state, "ready");
  assert.equal(state.select.value, "1");
  noWrites(state);
});

test("existing session with an unavailable exact spot blocks rather than following another link", () => {
  const state = fixture();
  link(state, "Missing place", "/grind-tracker/elsewhere/spot/999");
  const draft = state.draft();
  draft.target.spotId = "999";
  draft.target.spotName = "Missing place";
  assert.equal(state.discover(draft).state, "blocked");
  noWrites(state);
});

test("a visible login dialog blocks discovery and is never a session editor", () => {
  const state = fixture();
  state.fixtureWrite(() => {
    state.editor.setAttribute("aria-label", "Sign in");
    state.editor.appendChild(new state.Element("h2", {}, "Sign in"));
  });
  link(state, "Rusalka's Coral", "/grind-tracker/account/spot/77");
  assert.equal(state.context.TrackerContentTest.findSessionEditor(state.document), null);
  assert.equal(state.discover().state, "login_required");
  noWrites(state);
});

test("hidden login text is not proof of login required; loading remains read-only", () => {
  const state = landing();
  const login = link(state, "Login", "/login");
  login.hidden = true;
  assert.equal(state.discover().state, "blocked");
  state.fixtureWrite(() => state.document.body.appendChild(new state.Element("div", {"aria-busy":"true"})));
  assert.equal(state.discover().state, "loading");
  noWrites(state);
});

test("compound duration, loot, item quantity and Save section qualifies without an ARIA dialog", () => {
  const state = fixture();
  state.fixtureWrite(() => {
    state.editor.tagName = "SECTION";
    state.editor.removeAttribute("role");
    state.editor.removeAttribute("aria-label");
    state.editor.appendChild(new state.Element("h3", {}, "Loot"));
  });
  assert.equal(state.context.TrackerContentTest.findSessionEditor(state.document), state.editor);
  assert.equal(state.discover().state, "ready");
  noWrites(state);
});

test("Save plus ordinary inputs is not enough to qualify an arbitrary section", () => {
  const state = fixture();
  state.fixtureWrite(() => {
    state.editor.tagName = "SECTION";
    state.editor.removeAttribute("role");
    state.editor.removeAttribute("aria-label");
  });
  assert.equal(state.context.TrackerContentTest.findSessionEditor(state.document), null);
  noWrites(state);
});

test("public-origin form cannot be prepared outside strict tracker routes", () => {
  const state = fixture();
  state.context.location = new URL("https://garmoth.com/account");
  assert.equal(state.discover().state, "blocked");
  noWrites(state);
});

test("nullable metadata preserves zero and writes only explicitly labelled percentage/count inputs", async () => {
  const state = fixture();
  const count = optionalInput(state, "Agris used");
  const rate = optionalInput(state, "Additional Drop Rate (%)");
  const amount = optionalInput(state, "Additional Drop Amount");
  const toggle = optionalInput(state, "Agris", "checkbox", "on");
  const result = await prepare(state, {agrisUsed:0,additionalDropRate:12.5,additionalDropAmount:0});
  assert.equal(result.ok, true);
  assert.equal(count.value, "0");
  assert.equal(rate.value, "12.5");
  assert.equal(amount.value, "0");
  assert.equal(toggle.value, "on");
  assert.equal(state.writes.some((write) => write.target === "save"), false);
});

test("blank optional metadata leaves site choices untouched", async () => {
  const state = fixture();
  const count = optionalInput(state, "Agris points used");
  const rate = optionalInput(state, "Additional Drop Rate");
  assert.equal((await prepare(state)).ok, true);
  assert.equal(count.value, "19");
  assert.equal(rate.value, "19");
});

test("retry keeps omitted optional fields, including a user's correction, then accepts explicit zero", async () => {
  const state = fixture();
  const count = optionalInput(state, "Agris points used");
  const rate = optionalInput(state, "Additional Drop Rate");
  const amount = optionalInput(state, "Additional Drop Amount");
  assert.equal((await prepare(state, {agrisUsed:555,additionalDropRate:25,additionalDropAmount:100})).ok, true);
  state.fixtureWrite(() => { rate.value = "27"; });
  const omitted = {mastery:null,energySpent:null,agrisUsed:null,additionalDropRate:null,additionalDropAmount:null};
  assert.equal((await prepare(state, omitted)).ok, true);
  assert.equal(count.value, "555");
  assert.equal(rate.value, "27", "omission preserves a manual site correction too");
  assert.equal(amount.value, "100");
  assert.equal(state.fields.mastery.value, "2000");
  assert.equal(state.fields["energy-spent"].value, "321");
  assert.equal(rate.getAttribute("data-bsl-session-import-optional"), "additionalDropRate");
  assert.equal((await prepare(state, {mastery:0,energySpent:0,agrisUsed:0,additionalDropRate:0,additionalDropAmount:0})).ok, true);
  for (const field of [count,rate,amount,state.fields.mastery,state.fields["energy-spent"]]) assert.equal(field.value,"0");
  assert.equal((await prepare(state, omitted)).ok, true);
  for (const field of [count,rate,amount,state.fields.mastery,state.fields["energy-spent"]]) assert.equal(field.value,"0");
  assert.equal(state.writes.some(write=>write.kind==="click"&&write.target==="save"),false);
});

test("Agris Yes and No change only the exact checkbox and preserve numeric points", async () => {
  for (const desired of [true, false]) {
    const state = fixture();
    const toggle = agrisCheckbox(state, !desired);
    const points = optionalInput(state, "Agris used", "number", "555");
    const result = await prepare(state, {agrisActive:desired});
    assert.equal(result.ok, true);
    assert.equal(toggle.checked, desired);
    assert.equal(points.value, "555");
    assert.equal(state.writes.filter((write) => write.kind === "click").length, 1);
    assert.equal(state.writes.some((write) => write.target === "save"), false);
  }
});

test("Agris already at the desired state is idempotent and null leaves the choice alone", async () => {
  const state = fixture();
  const toggle = agrisCheckbox(state, false);
  assert.equal((await prepare(state, {agrisActive:false})).ok, true);
  assert.equal(toggle.checked, false);
  assert.equal(state.writes.some((write) => write.kind === "click"), false);
  toggle.checked = true;
  assert.equal((await prepare(state, {agrisActive:null})).ok, true);
  assert.equal(toggle.checked, true);
  assert.equal(state.writes.some((write) => write.kind === "click"), false);
});

test("Agris supports explicit aria-pressed state, not icon colour", async () => {
  const state = fixture();
  let toggle;
  state.fixtureWrite(() => {
    toggle = state.editor.appendChild(new state.HTMLButtonElement({type:"button","aria-label":"Agris","aria-pressed":"false"}, ""));
  });
  toggle.addEventListener("click", () => toggle.setAttribute("aria-pressed", "true"));
  const result = await prepare(state, {agrisActive:true});
  assert.equal(result.ok, true);
  assert.equal(toggle.getAttribute("aria-pressed"), "true");
  assert.equal(result.warnings.includes("agris_toggle_not_accepted"), false);
});

test("unknown, ambiguous or rejected Agris state reports review without guessing", async () => {
  const unknown = fixture();
  optionalInput(unknown, "Agris", "number", "1000");
  assert.ok((await prepare(unknown, {agrisActive:true})).warnings.includes("agris_toggle_not_found"));
  assert.equal(unknown.writes.some((write) => write.kind === "click"), false);
  const ambiguous = fixture();
  agrisCheckbox(ambiguous, false);
  agrisCheckbox(ambiguous, false);
  assert.ok((await prepare(ambiguous, {agrisActive:true})).warnings.includes("agris_toggle_not_found"));
  assert.equal(ambiguous.writes.some((write) => write.kind === "click"), false);
  const rejected = fixture();
  const toggle = agrisCheckbox(rejected, false);
  toggle.addEventListener("click", () => { toggle.checked = false; });
  assert.ok((await prepare(rejected, {agrisActive:true})).warnings.includes("agris_toggle_not_accepted"));
});

test("Agris accepts only boolean or absent values before any mutation", async () => {
  for (const value of [0, 1, "false", "true", "", {}]) {
    const state = fixture();
    const draft = state.draft();
    draft.session.agrisActive = value;
    await assert.rejects(state.prepare(undefined, draft), (error) => error.code === "invalid_agris_active");
    noWrites(state);
  }
});

test("cancellation after an Agris click prevents later item writes or prepared markers", async () => {
  const state = fixture();
  const toggle = agrisCheckbox(state, false);
  let cancelled = false;
  toggle.addEventListener("click", () => { cancelled = true; });
  const draft = state.draft();
  draft.session.agrisActive = true;
  const pending = state.prepare({assertActive() { if (cancelled) throw state.cancelError(); }}, draft)
    .then(() => null, (error) => error);
  await state.advance(150);
  assert.equal((await pending).code, "preparation_cancelled");
  assert.equal(state.fields.loot.value, "7");
  assert.equal(state.editor.getAttribute("data-bsl-session-import-draft"), null);
});

test("explicit seconds field preserves an exact timer duration", async () => {
  const state = fixture();
  const hours = optionalInput(state, "Hours", "number", "0");
  const seconds = optionalInput(state, "Seconds", "number", "0");
  const result = await prepare(state, {durationSeconds:95});
  assert.equal(result.ok, true);
  assert.equal(hours.value, "0");
  assert.equal(state.fields["duration-minutes"].value, "1");
  assert.equal(seconds.value, "35");
});

test("minute-only controls round down with an explicit warning and verified displayed duration", async () => {
  const state = fixture();
  const hours = optionalInput(state, "Hours", "number", "0");
  const result = await prepare(state, {durationSeconds:95});
  assert.equal(result.ok, true);
  assert.equal(hours.value, "0");
  assert.equal(state.fields["duration-minutes"].value, "1");
  assert.ok(result.warnings.includes("duration_rounded_to_minutes"));
});

test("one numeric minute field rounds explicitly; an unsupported subminute session cannot become ready", async () => {
  const state = fixture();
  const result = await prepare(state, {durationSeconds:95});
  assert.equal(result.ok, true);
  assert.equal(state.fields["duration-minutes"].value, "1");
  assert.ok(result.warnings.includes("duration_rounded_to_minutes"));
  const short = fixture();
  const failure = await prepare(short, {durationSeconds:35});
  assert.equal(failure.ok, false);
  assert.equal(failure.code, "duration_not_prepared");
  assert.equal(short.editor.getAttribute("data-bsl-session-import-draft"), null);
});

test("a field named only Minutes receives minutes, including explicit rounding", async () => {
  for (const type of ["number", "text"]) {
    const state = fixture();
    state.fixtureWrite(() => {
      state.fields["duration-minutes"].setAttribute("id", "minutes");
      state.fields["duration-minutes"].setAttribute("name", "Minutes");
      state.fields["duration-minutes"].setAttribute("type", type);
    });
    const result = await prepare(state, {durationSeconds:95});
    assert.equal(result.ok, true, type);
    assert.equal(state.fields["duration-minutes"].value, "1", type);
    assert.ok(result.warnings.includes("duration_rounded_to_minutes"));
  }
});

test("Firefox review finds the draft marked on a recognized inline session section", async () => {
  const state = fixture();
  state.fixtureWrite(() => {
    state.editor.tagName = "SECTION";
    state.editor.removeAttribute("role");
    state.editor.removeAttribute("aria-label");
    state.editor.appendChild(new state.Element("h3", {}, "Loot"));
  });
  const result = await prepare(state);
  assert.equal(result.ok, true);
  assert.equal(state.context.TrackerContentTest.findEditor(state.document), null);
  const status = await state.listeners[0]({type:"tracker_status"});
  assert.equal(status.ready, true);
  assert.equal(status.draftId, result.draftId);
  assert.equal(state.writes.some((write) => write.target === "save"), false);
});

test("generic Agris fields and ambiguous percentages are not guessed", async () => {
  const state = fixture();
  const agris = optionalInput(state, "Agris");
  const first = optionalInput(state, "Additional Drop Rate");
  const second = optionalInput(state, "Additional Drop Rate");
  const result = await prepare(state, {agrisUsed:500,additionalDropRate:100});
  assert.equal(agris.value, "19");
  assert.equal(first.value, "19");
  assert.equal(second.value, "19");
  assert.ok(result.warnings.includes("agris_field_not_found"));
  assert.ok(result.warnings.includes("additional_drop_rate_field_not_found"));
});

test("percentage validation rejects invalid types, negatives, excess precision and over-limit values before writes", async () => {
  for (const value of ["100", true, -1, 10000.01, 1.234, Infinity, NaN]) {
    const state = fixture();
    const draft = state.draft();
    draft.session.additionalDropRate = value;
    await assert.rejects(state.prepare(undefined, draft), (error) => error.code === "invalid_additional_drop_rate");
    noWrites(state);
  }
  const state = fixture();
  assert.equal((await prepare(state, {additionalDropRate:10000,additionalDropAmount:99.99})).ok, true);
});

test("missing duration is a structured failure with every item retained and no prepared marker", async () => {
  const state = fixture();
  state.fixtureWrite(() => remove(state.fields["duration-minutes"]));
  const result = await prepare(state);
  assert.equal(result.ok, false);
  assert.equal(result.code, "duration_not_prepared");
  assert.equal(result.skipped.length, 1);
  assert.equal(state.fields.loot.value, "7");
  assert.equal(state.editor.getAttribute("data-bsl-session-import-draft"), null);
});

test("rejected duration is never called ready", async () => {
  const state = fixture();
  state.fields["duration-minutes"].addEventListener("input", () => { state.fields["duration-minutes"].value = ""; });
  const result = await prepare(state);
  assert.equal(result.ok, false);
  assert.equal(result.code, "duration_not_prepared");
  assert.equal(state.editor.getAttribute("data-bsl-session-import-draft"), null);
});

test("a delayed duration reset during item events fails final readback", async () => {
  const state = fixture();
  state.fields.loot.addEventListener("input", () => { state.fields["duration-minutes"].value = "0"; });
  const result = await prepare(state);
  assert.equal(result.ok, false);
  assert.equal(result.code, "session_not_prepared");
  assert.equal(result.matched.length, 1);
  assert.equal(state.editor.getAttribute("data-bsl-session-import-draft"), null);
});

test("zero matched items is a structured failure, never a prepared draft", async () => {
  const state = fixture();
  state.fields.loot.addEventListener("input", () => { state.fields.loot.value = "0"; });
  const result = await prepare(state);
  assert.equal(result.ok, false);
  assert.equal(result.code, "no_items_prepared");
  assert.equal(result.skipped[0].reason, "value_not_accepted");
  assert.equal(state.editor.getAttribute("data-bsl-session-import-draft"), null);
});

test("partial supported items keep explicit skipped results and never click Save", async () => {
  const state = fixture();
  const draft = state.draft();
  const missing = state.draft().session.items[0];
  Object.assign(missing, {itemId:"absent-02",name:"Unavailable loot",quantity:5});
  draft.session.items.push(missing);
  const pending = state.prepare(undefined, draft);
  await settle();
  await state.advance(300);
  const result = await pending;
  assert.equal(result.ok, true);
  assert.equal(result.matched.length, 1);
  assert.equal(result.skipped.length, 1);
  assert.equal(state.writes.some((write) => write.target === "save"), false);
});
