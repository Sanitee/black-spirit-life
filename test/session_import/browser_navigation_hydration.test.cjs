"use strict";

// Shipped navigation helper in a mocked DOM. No browser, pointer, account,
// profile, network request or native input is used by these tests.
const assert = require("node:assert/strict");
const test = require("node:test");
const { fixture } = require("./browser_dom_fixture.cjs");

function detach(element) {
  element.parentElement.children = element.parentElement.children.filter(child => child !== element);
  element.parentElement = null;
}

function landing() {
  const state = fixture({ open: false });
  state.fixtureWrite(() => {
    detach(state.opener);
    for (const heading of state.document.querySelectorAll("h1")) detach(heading);
  });
  state.context.location = new URL("https://garmoth.com/grind-tracker/best-grind-spots");
  state.context.Date = class extends Date { static now() { return state.now; } };
  return state;
}

function collapsedRail(state, { placeholder = false, outsideMain = false, expand = true } = {}) {
  let aside, summary;
  const controls = {};
  let width = 56;
  state.fixtureWrite(() => {
    const scope = state.document.body.appendChild(new state.Element(outsideMain ? "div" : "main"));
    const menu = scope.appendChild(new state.Element("div", { id: "grind-menu" }));
    aside = menu.appendChild(new state.Element("aside", { class: "overflow-hidden" }));
    aside.getBoundingClientRect = () => ({ left: 0, top: 196, width, height: 450 });
    summary = aside.appendChild(new state.Element("a", {
      href: "/grind-tracker/" + (placeholder ? "null" : "fixture") + "/summary",
    }, "Summary"));
    summary.getBoundingClientRect = () => ({ left: 0, top: 196, width: 278, height: 40 });
    aside.addEventListener("mouseenter", () => {
      if (!expand) return;
      width = 278;
      const group = aside.appendChild(new state.Element("a", { href: "/grind-tracker/fixture/summary" }));
      for (const name of ["Grinding", "Lifeskill", "Scrolls", "Dungeon"]) {
        controls[name] = group.appendChild(new state.HTMLButtonElement({ type: "button" }, name));
      }
      state.document.hitElement = controls.Lifeskill;
    });
  });
  return { aside, summary, controls };
}

function execute(state, action = "expand_tracker", options = {}) {
  return state.context.TrackerContentTest.executeNavigationStep(state.document, state.draft(), action, {
    deadline: 5000, expectedUrl: null, assertActive() {}, ...options,
  });
}

function emptyCompletedShell() {
  const state=landing();
  state.document.readyState="complete";
  // The live trace established five body elements but did not identify their
  // tags or framework IDs. Only the observed empty-visible-content contract is
  // modeled here; the helper must not depend on invented framework markers.
  state.fixtureWrite(()=>{
    let parent=state.document.body;
    for(let index=0;index<5;index+=1)parent=parent.appendChild(new state.Element("div"));
  });
  return state;
}

test("hydration: a complete genuinely empty tracker document is loading, never ready or login",()=>{
  const state=emptyCompletedShell();
  assert.equal(state.document.body.querySelectorAll("*").length,5);
  assert.equal(state.discover().state,"loading");
  assert.deepEqual(state.writes,[]);
});

test("hydration: an empty shell can mount after four seconds and resume exact-link discovery",async()=>{
  const state=emptyCompletedShell();
  const draft=state.draft();draft.target.spotId="186";
  state.context.setTimeout(()=>state.fixtureWrite(()=>{
    state.document.body.appendChild(new state.Element("h1",{},"Best Grind Spots"));
    state.document.body.appendChild(new state.Element("a",{href:"/grind-tracker/fixture/spot/186"},"Rusalka's Coral"));
  }),4500);
  await state.advance(4100);
  assert.equal(state.discover(draft).state,"loading");
  await state.advance(400);
  const result=state.discover(draft);
  assert.equal(result.state,"navigate");
  assert.equal(result.url,"https://garmoth.com/grind-tracker/fixture/spot/186");
  assert.deepEqual(state.writes,[]);
});

test("hydration: visible errors and unrecognized nonempty pages are not empty startup shells",()=>{
  for(const text of ["500 Internal Server Error","Something went wrong","Unrecognized page content"]){
    const state=emptyCompletedShell();
    state.fixtureWrite(()=>state.document.body.appendChild(new state.Element("div",{},text)));
    assert.equal(state.discover().state,"blocked",text);
    assert.equal(state.discover().code,"no_matching_link",text);
    assert.deepEqual(state.writes,[]);
  }
});

test("hydration: positive visible Login retains the login-required state",()=>{
  const state=emptyCompletedShell();
  state.fixtureWrite(()=>state.document.body.appendChild(new state.Element("a",{href:"/login"},"Login")));
  assert.equal(state.discover().state,"login_required");
  assert.deepEqual(state.writes,[]);
});

test("hydration: visible textless controls, headings, errors and media prevent empty-shell classification",()=>{
  for(const [tag,attributes] of [["button",{}],["h1",{}],["div",{role:"alert"}],["img",{src:"/error.png"}],
    ["input",{type:"text"}],["svg",{}],["iframe",{}]]){
    const state=emptyCompletedShell();
    state.fixtureWrite(()=>state.document.body.appendChild(new state.Element(tag,attributes)));
    assert.equal(state.discover().state,"blocked",tag);
    assert.deepEqual(state.writes,[]);
  }
});

test("hydration: empty-shell loading stays inside the exact Garmoth tracker route",()=>{
  for(const url of ["https://example.com/grind-tracker/best-grind-spots","https://garmoth.com/","https://garmoth.com/grind-tracker/null/summary"]){
    const state=emptyCompletedShell();state.context.location=new URL(url);
    assert.equal(state.discover().state,"blocked",url);
    assert.deepEqual(state.writes,[]);
  }
});

test("rail: pointer-entry events expand only the observed narrow tracker aside without a click", () => {
  const state = landing();
  const rail = collapsedRail(state);
  const discovery = state.discover();
  assert.equal(discovery.state, "act");
  assert.equal(discovery.action, "expand_tracker");
  assert.equal(discovery.expectedUrl, null);
  assert.deepEqual(state.writes, []);
  assert.equal(execute(state).acted, true);
  assert.deepEqual(state.writes.filter(write => write.kind === "event").map(write => write.name), ["mouseenter", "mouseover"]);
  assert.equal(state.writes.some(write => write.kind === "click" || write.kind === "value"), false);
  assert.equal(rail.aside.getBoundingClientRect().width, 278);
  assert.equal(state.discover().action, "select_activity");
  assert.equal(state.context.location.href, "https://garmoth.com/grind-tracker/best-grind-spots");
});

test("rail: placeholder Summary or a lookalike outside main never triggers hover", () => {
  for (const options of [{ placeholder: true }, { outsideMain: true }]) {
    const state = landing();
    collapsedRail(state, options);
    assert.notEqual(state.discover().state, "act");
    assert.equal(execute(state).acted, false);
    assert.deepEqual(state.writes, []);
  }
});

test("rail: a hover that does not expand waits briefly then uses its real Summary link without repeating events", async () => {
  const state = landing();
  collapsedRail(state, { expand: false });
  assert.equal(execute(state).acted, true);
  assert.equal(state.discover().state, "loading");
  const writes = state.writes.length;
  await state.advance(2001);
  assert.equal(state.discover().state, "navigate");
  assert.equal(state.discover().url, "https://garmoth.com/grind-tracker/fixture/summary");
  assert.equal(state.writes.length, writes);
});

test("rail: cancellation from pointer entry prevents any later hover event", () => {
  const state = landing();
  const rail = collapsedRail(state, { expand: false });
  let cancelled = false;
  rail.aside.addEventListener("mouseenter", () => { cancelled = true; });
  assert.throws(() => execute(state, "expand_tracker", {
    assertActive() { if (cancelled) throw state.cancelError(); },
  }), error => error.code === "preparation_cancelled");
  assert.deepEqual(state.writes.filter(write => write.kind === "event").map(write => write.name), ["mouseenter"]);
});

test("hydration: a just-opened spot does not bounce to Summary before its heading exists", () => {
  const state = landing();
  state.context.location = new URL("https://garmoth.com/grind-tracker/fixture/spot/186");
  state.fixtureWrite(() => state.document.body.appendChild(new state.Element("a", {
    href: "/grind-tracker/fixture/summary",
  }, "Summary")));
  assert.equal(state.discover().state, "loading");
  assert.deepEqual(state.writes, []);
});

test("hydration: exact spot heading waits for Add then becomes ready without navigating", () => {
  const state = landing();
  state.context.location = new URL("https://garmoth.com/grind-tracker/fixture/spot/186");
  state.fixtureWrite(() => {
    state.document.body.appendChild(new state.Element("h1", {}, "Rusalka's Coral"));
    state.document.body.appendChild(new state.Element("a", { href: "/grind-tracker/fixture/summary" }, "Summary"));
  });
  assert.equal(state.discover().state, "loading");
  state.fixtureWrite(() => state.document.body.appendChild(new state.HTMLButtonElement({ type: "button" }, "Add session")));
  assert.equal(state.discover().state, "ready");
  assert.deepEqual(state.writes, []);
});

test("hydration: a different named spot still resolves the requested exact rendered destination", () => {
  const state = landing();
  state.context.location = new URL("https://garmoth.com/grind-tracker/fixture/spot/other");
  state.fixtureWrite(() => {
    state.document.body.appendChild(new state.Element("h1", {}, "Different spot"));
    state.document.body.appendChild(new state.Element("a", { href: "/grind-tracker/fixture/spot/186" }, "Rusalka's Coral"));
  });
  const draft = state.draft();
  draft.target.spotId = "186";
  const result = state.discover(draft);
  assert.equal(result.state, "navigate");
  assert.equal(result.url, "https://garmoth.com/grind-tracker/fixture/spot/186");
  assert.deepEqual(state.writes, []);
});

test("identity: duplicate spot names navigate only to the explicit observed spot ID", () => {
  for (const wanted of ["51", "62"]) {
    const state = landing();
    state.fixtureWrite(() => {
      for (const id of ["51", "62"]) state.document.body.appendChild(new state.Element("a", {
        href: "/grind-tracker/fixture/spot/" + id,
      }, "North Kaia Mountain Top"));
      state.document.body.appendChild(new state.Element("a", {
        href: "/grind-tracker/fixture/spot/" + wanted,
      }, "Different spot"));
    });
    const draft = state.draft();
    draft.target.spotName = "North Kaia Mountain Top";
    draft.target.spotId = wanted;
    const result = state.discover(draft);
    assert.equal(result.state, "navigate");
    assert.equal(result.url, "https://garmoth.com/grind-tracker/fixture/spot/" + wanted);
    assert.deepEqual(state.writes, []);
  }
});

test("identity: a missing explicit ID never falls back to a same-name destination", () => {
  const state = landing();
  state.fixtureWrite(() => {
    for (const id of ["51", "62"]) state.document.body.appendChild(new state.Element("a", {
      href: "/grind-tracker/fixture/spot/" + id,
    }, "North Kaia Mountain Top"));
  });
  const draft = state.draft();
  draft.target.spotName = "North Kaia Mountain Top";
  draft.target.spotId = "48";
  assert.equal(state.discover(draft).state, "blocked");
  draft.target.spotId = null;
  assert.equal(state.discover(draft).state, "blocked", "name-only callers still refuse ambiguous destinations");
  assert.deepEqual(state.writes, []);
});

function spotGroups(state, {expand=true,placeholder=false,outsideMain=false,unsafeHeader=false,categories=false}={}) {
  let aside,activity;
  const groups=[];
  state.fixtureWrite(()=>{
    const main=state.document.body.appendChild(new state.Element(outsideMain?"div":"main"));
    const menu=main.appendChild(new state.Element("div",{id:"grind-menu"}));
    aside=menu.appendChild(new state.Element("aside"));
    aside.getBoundingClientRect=()=>({left:0,top:100,width:278,height:650});
    aside.appendChild(new state.Element("a",{href:"/grind-tracker/fixture/summary"},"Summary"));
    if(categories){
      const anchor=aside.appendChild(new state.Element("a",{href:"/grind-tracker/fixture/summary"}));
      for(const label of ["Grinding","Lifeskill","Scrolls","Dungeon"]){
        const button=anchor.appendChild(new state.HTMLButtonElement({type:"button"},label));
        if(label==="Lifeskill")activity=button;
      }
      state.document.hitElement=activity;
    }
    for(const [id,label] of [["54","HERB SPOTS"],["55","MEAT SPOTS"]]){
      const group=aside.appendChild(new state.Element("div",{class:"rounded-md border border-light"}));
      const header=group.appendChild(new state.Element("div",{id:"group-"+id,class:"cursor-pointer select-none"}));
      header.appendChild(new state.Element("div",{class:"uppercase"},unsafeHeader?"SAVE SESSION":label));
      const panel=group.appendChild(new state.Element("div",{class:"overflow-hidden",style:"max-height: 0px; transition: max-height 0.4s ease-in-out;"}));
      const rows=panel.appendChild(new state.Element("div")).appendChild(new state.Element("div"));
      const link=rows.appendChild(new state.Element("a",{href:"/grind-tracker/"+(placeholder?"null":"fixture")+"/spot/"+id}));
      link.appendChild(new state.Element("span",{class:"cut-text"},"Behr"));
      let opened=false;
      link.getClientRects=()=>opened?[{}]:[];
      header.addEventListener("click",()=>{
        if(!expand)return;
        opened=true;
        panel.setAttribute("style","max-height: 400px; transition: max-height 0.4s ease-in-out;");
      });
      groups.push({header,panel,link});
    }
  });
  const draft=state.draft();draft.target.spotName="Behr";draft.target.spotId="54";
  const act=(action="expand_spot_group",options={})=>state.context.TrackerContentTest.executeNavigationStep(state.document,draft,action,
    {deadline:10000,expectedUrl:state.discover(draft).expectedUrl??null,assertActive(){},...options});
  return {aside,groups,activity,draft,act};
}

test("group: exact hidden Behr54 anchor opens only its associated observed HERB accordion",async()=>{
  const state=landing();const subject=spotGroups(state);
  const first=state.discover(subject.draft);
  assert.equal(first.state,"act");assert.equal(first.action,"expand_spot_group");assert.equal(first.expectedUrl,null);
  assert.deepEqual(state.writes,[]);
  assert.equal(subject.act().acted,true);
  assert.equal(state.discover(subject.draft).state,"loading");
  await state.advance(501);
  assert.equal(state.discover(subject.draft).url,"https://garmoth.com/grind-tracker/fixture/spot/54");
  assert.deepEqual(state.writes.filter(write=>write.kind==="click").map(write=>write.target),["group-54"]);
  assert.equal(subject.groups[1].panel.getAttribute("style").startsWith("max-height: 0px"),true);
});

test("group: activity selection remains owned while opening its nested group",async()=>{
  const state=landing();const subject=spotGroups(state,{categories:true});
  assert.equal(state.discover(subject.draft).action,"select_activity");
  assert.equal(subject.act("select_activity").acted,true);
  await state.advance(300);
  assert.equal(state.discover(subject.draft).action,"expand_spot_group");
  assert.equal(subject.act().acted,true);
  await state.advance(501);
  const next=state.discover(subject.draft);
  assert.equal(next.state,"navigate","must not repeatedly select Lifeskill after expanding a group");
  assert.equal(next.url,"https://garmoth.com/grind-tracker/fixture/spot/54");
  assert.equal(state.writes.filter(write=>write.kind==="click").length,2);
});

test("group: null routes, out-of-scope groups and Save-labelled controls are never toggled",()=>{
  for(const options of [{placeholder:true},{outsideMain:true},{unsafeHeader:true}]){
    const state=landing();const subject=spotGroups(state,options);
    assert.notEqual(state.discover(subject.draft).action,"expand_spot_group");
    assert.equal(subject.act().acted,false);
    assert.deepEqual(state.writes,[]);
  }
});

test("group: name and ID must both match, and changed links invalidate an already discovered action",()=>{
  const state=landing();const subject=spotGroups(state);
  subject.draft.target.spotId="99";
  assert.notEqual(state.discover(subject.draft).action,"expand_spot_group");
  subject.draft.target.spotId="54";subject.draft.target.spotName="Other spot";
  assert.notEqual(state.discover(subject.draft).action,"expand_spot_group");
  subject.draft.target.spotName="Behr";
  assert.equal(state.discover(subject.draft).action,"expand_spot_group");
  state.fixtureWrite(()=>subject.groups[0].link.setAttribute("href","/grind-tracker/fixture/spot/99"));
  assert.equal(subject.act().acted,false);
  assert.deepEqual(state.writes,[]);
});

test("group: refused expansion stops without toggling repeatedly",async()=>{
  const state=landing();const subject=spotGroups(state,{expand:false});
  assert.equal(subject.act().acted,true);
  await state.advance(501);
  assert.equal(state.discover(subject.draft).state,"blocked");
  assert.equal(subject.act().acted,false);
  assert.equal(state.writes.filter(write=>write.kind==="click").length,1);
});

test("group: cancellation and unexpected navigation expectations reject before the click",()=>{
  const state=landing();const subject=spotGroups(state);
  assert.equal(subject.act("expand_spot_group",{expectedUrl:"https://garmoth.com/grind-tracker/fixture/summary"}).acted,false);
  assert.throws(()=>subject.act("expand_spot_group",{assertActive(){throw state.cancelError();}}),error=>error.code==="preparation_cancelled");
  assert.deepEqual(state.writes,[]);
});
