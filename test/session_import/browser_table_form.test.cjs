"use strict";

// Synthetic structural regressions for the observed table-shaped editor.
// These exercise shipped helper code, not an authenticated page. Exact live
// DOM details must be incorporated before claiming website compatibility.
const assert = require("node:assert/strict");
const test = require("node:test");
const { fixture } = require("./browser_dom_fixture.cjs");

const coralItems = [
  ["4006", "Rough Stone", 1005],
  ["4999", "Black Gem Fragment", 52],
  ["4998", "Sharp Black Crystal Shard", 8],
  ["6511", "Lobster", 38],
  ["821371", "Fairy's Breath", 162],
  ["721003", "Caphras Stone", 3],
  ["6501", "Coral Piece", 413],
  ["5651", "Fairy Powder", 132],
  ["821353", "Dim Heartvein Shard", 26],
  ["821255", "Rusalka's Coral", 59],
  ["821350", "Cracked Terrashard", 2],
  ["721002", "Ancient Spirit Dust", 37],
  ["5205", "Fruit of Nature", 4],
  ["4477", "Blue Coral", 5],
  ["4406", "Rough Translucent Crystal", 5],
  ["4411", "Rough Blue Crystal", 6],
].map(([itemId, name, quantity]) => ({ itemId, name, quantity, subKey: 0 }));

function detach(element) {
  element.parentElement.children = element.parentElement.children.filter(child => child !== element);
  element.parentElement = null;
}

function tableFixture({ items = coralItems, groupedHeaders = false, paddedIcons = false, separateClock = false } = {}) {
  const state = fixture();
  const inputs = new Map();
  const headers = new Map();
  const rows = [];
  let table, head, body, duration, minutes, agris;
  const element = (tag, attributes = {}, text = "") => {
    const node = new state.Element(tag, attributes, text);
    if (tag === "th" || tag === "td") {
      Object.defineProperties(node, {
        colSpan: { get: () => Number(node.getAttribute("colspan") || 1) },
        rowSpan: { get: () => Number(node.getAttribute("rowspan") || 1) },
        cellIndex: { get: () => node.parentElement.children.indexOf(node) },
      });
    }
    if (tag === "tr") Object.defineProperty(node, "cells", { get: () => node.children });
    return node;
  };
  const makeRow = () => {
    const row = body.appendChild(element("tr"));
    rows.push(row);
    const cell = control => row.appendChild(element("td")).appendChild(control);
    const clock = cell(new state.HTMLInputElement({ type: separateClock ? "number" : "text", placeholder:"0" }));
    clock.value = separateClock ? "0" : "00:00";
    let minuteControl;
    if (separateClock) {
      row.appendChild(element("td", {}, ":"));
      minuteControl = cell(new state.HTMLInputElement({ type:"number",placeholder:"0" }));
      minuteControl.value = "0";
    }
    // A generic X does not establish a boolean Agris contract. Optional Agris
    // is omitted in these tests until the real control attributes are known.
    const toggle = cell(separateClock ? new state.HTMLInputElement({type:"number",placeholder:"0"})
      : new state.HTMLButtonElement({ type: "button" }, "X"));
    if (separateClock) toggle.value = "117";
    for (const label of ["Mastery", "Energy"]) {
      const control = cell(new state.HTMLInputElement({ type: "number" }));
      control.value = "0";
    }
    for (const item of items) {
      const control = cell(new state.HTMLInputElement({ type: "number" }));
      control.value = "0";
      if (!inputs.has(item.itemId)) inputs.set(item.itemId, control);
    }
    return { row, clock, minuteControl, toggle };
  };

  state.fixtureWrite(() => {
    for (const child of [...state.editor.children]) detach(child);
    state.editor.removeAttribute("aria-label");
    if (separateClock) {
      state.editor.removeAttribute("role");
      state.editor.setAttribute("class", "flex flex-none flex-col gap-3");
    }
    detach(state.opener);
    state.document.body.appendChild(element("h1", {}, "Rusalka's Coral"));
    table = state.editor.appendChild(element("table"));
    head = table.appendChild(element("thead"));
    body = table.appendChild(element("tbody"));
    Object.defineProperties(table, {
      tHead: { get: () => head },
      tBodies: { get: () => [body] },
      rows: { get: () => [...head.children, ...body.children] },
    });
    for (const section of [head, body]) {
      Object.defineProperty(section, "rows", { get: () => section.children });
    }
    if (groupedHeaders) {
      const groups = head.appendChild(element("tr"));
      groups.appendChild(element("th", { colspan: separateClock ? "6" : "4" }, "Details"));
      groups.appendChild(element("th", { colspan: String(items.length) }, "Items"));
    }
    const labels = head.appendChild(element("tr"));
    for (const title of separateClock ? ["Hours", ":", "Mins", "Agris", "Mastery", "Energy"]
      : ["Hours:Mins", "Agris", "Mastery", "Energy"]) {
      labels.appendChild(element("th", {}, title));
    }
    for (const item of items) {
      const header = labels.appendChild(element("th"));
      const filename = paddedIcons ? item.itemId.padStart(8, "0") : item.itemId;
      header.appendChild(element("img", { src: "https://assets.garmoth.com/items/" + filename + ".png" }));
      headers.set(item.itemId, header);
    }
    ({ clock: duration, minuteControl: minutes, toggle: agris } = makeRow());
    state.editor.appendChild(new state.HTMLButtonElement({ id: "table-save", type: "submit" }, "Save"));
  });
  state.context.location = new URL("https://garmoth.com/grind-tracker/fixture/spot/186");
  const draft = state.draft();
  draft.target.spotId = "";
  draft.target.url = null;
  draft.session.durationSeconds = 900;
  draft.session.mastery = null;
  draft.session.energySpent = null;
  draft.session.items = items;
  // Re-enter through the wire JSON realm just like the real host.
  const wireDraft = state.draft({ target: draft.target, session: draft.session });
  return { state, table, head, body, rows, inputs, headers, duration, minutes, agris, makeRow, draft: wireDraft };
}

async function prepareTable(subject, options) {
  const pending = subject.state.prepare(options, subject.draft)
    .then(result => ({ result }), error => ({ error }));
  await subject.state.advance(10000);
  return pending;
}

function assertNoSave(subject) {
  assert.equal(subject.state.writes.some(write => write.kind === "click" && write.target === "table-save"), false);
}

function assertItems(subject) {
  for (const item of subject.draft.session.items) {
    assert.equal(subject.inputs.get(item.itemId).value, String(item.quantity), item.name);
  }
}

function installTableTooltips(subject, names = new Map(), { show = true } = {}) {
  const {state} = subject;
  state.fixtureWrite(() => {
    for (const [id,header] of subject.headers) {
      header.setAttribute("class","relative v-popper--has-tooltip");
      let popup;
      header.addEventListener("mouseenter", () => {
        if (!show) return;
        state.context.setTimeout(() => {
          popup = state.document.body.appendChild(new state.Element("div", {
            class:"v-popper__popper v-popper__popper--shown", "aria-hidden":"false",
          }, names.get(id) ?? subject.draft.session.items.find(item => item.itemId === id)?.name ?? "Unselected item"));
        },200);
      });
      header.addEventListener("mouseleave", () => { if (popup?.parentElement) detach(popup); });
    }
  });
}

const agrisGlyphs = {
  false: ["0 0 384 512", "M342.6 150.6c12.5-12.5 12.5-32.8 0-45.3s-32.8-12.5-45.3 0L192 210.7L86.6 105.4c-12.5-12.5-32.8-12.5-45.3 0s-12.5 32.8 0 45.3L146.7 256L41.4 361.4c-12.5 12.5-12.5 32.8 0 45.3s32.8 12.5 45.3 0L192 301.3l105.4 105.3c12.5 12.5 32.8 12.5 45.3 0s12.5-32.8 0-45.3L237.3 256z"],
  true: ["0 0 448 512", "M438.6 105.4c12.5 12.5 12.5 32.8 0 45.3l-256 256c-12.5 12.5-32.8 12.5-45.3 0l-128-128c-12.5-12.5-12.5-32.8 0-45.3s32.8-12.5 45.3 0L160 338.7l233.4-233.3c12.5-12.5 32.8-12.5 45.3 0z"],
};

function installAgrisHeader(subject, initial, { unknown = false, reject = false } = {}) {
  const {state} = subject;
  let current = initial;
  const header = subject.head.children.at(-1).children.find(cell => cell.textContent === "Agris");
  let svg,path;
  const render = () => {
    svg.setAttribute("viewBox",agrisGlyphs[current][0]);
    path.setAttribute("d",unknown ? "M0 0h1v1z" : agrisGlyphs[current][1]);
  };
  state.fixtureWrite(() => {
    header.setAttribute("id","table-agris-header");
    header.setAttribute("class","cursor-pointer v-popper--has-tooltip");
    svg=header.appendChild(new state.Element("svg", {class:"icon text-purple"}));
    path=svg.appendChild(new state.Element("path"));
    render();
    header.addEventListener("click",() => { if (!reject) { current=!current;render(); } });
  });
  return {header,state:()=>current,setState(value){current=value;render();}};
}

function installPercentageFields(subject) {
  const controls=[];
  subject.state.fixtureWrite(()=>{
    for(const label of ["Additional Drop RATE","Additional Drop AMOUNT"]){
      const field=subject.state.editor.appendChild(new subject.state.Element("div"));
      field.appendChild(new subject.state.Element("p",{},label));
      let wrapper=field;
      for(let depth=0;depth<3;depth+=1)wrapper=wrapper.appendChild(new subject.state.Element("div"));
      const input=wrapper.appendChild(new subject.state.HTMLInputElement({type:"text",placeholder:"0"}));
      wrapper.appendChild(new subject.state.Element("label",{for:""},"%"));
      input.value="17";
      controls.push(input);
    }
  });
  return controls;
}

test("table: sixteen icon headers map to their own input columns with compact Hours:Mins", async () => {
  const subject = tableFixture();
  assert.equal(subject.head.children[0].children.length, 20);
  const { result, error } = await prepareTable(subject);
  assert.equal(error, undefined);
  assert.equal(result.ok, true);
  assert.equal(result.matched.length, 16);
  assert.equal(subject.duration.value, "00:15");
  assertItems(subject);
  assertNoSave(subject);
});

test("table: reordered padded item icons and grouped header spans do not shift quantities", async () => {
  const subject = tableFixture({ items: [...coralItems].reverse(), paddedIcons: true, groupedHeaders: true });
  const { result, error } = await prepareTable(subject);
  assert.equal(error, undefined);
  assert.equal(result.ok, true);
  assert.equal(result.matched.length, 16);
  assertItems(subject);
  assertNoSave(subject);
});

test("table: multiple editable rows fail closed instead of choosing the first", async () => {
  const subject = tableFixture();
  subject.state.fixtureWrite(() => subject.makeRow());
  const { result, error } = await prepareTable(subject);
  assert.equal(Boolean(error) || result?.ok === false, true);
  assert.equal(subject.state.writes.some(write => write.kind === "value"), false);
  assertNoSave(subject);
});

test("table: duplicate item identity never writes an arbitrary matching column", async () => {
  const subject = tableFixture({ items: [coralItems[0], { ...coralItems[0] }] });
  const { result, error } = await prepareTable(subject);
  assert.equal(Boolean(error) || result?.ok === false, true);
  assert.equal(subject.inputs.get(coralItems[0].itemId).value, "0");
  assertNoSave(subject);
});

test("table: wrong current spot is refused before modifying table values", async () => {
  const subject = tableFixture();
  subject.draft.target.spotName = "Different exact spot";
  const { result, error } = await prepareTable(subject);
  assert.equal(Boolean(error) || result?.ok === false, true);
  assert.equal(subject.state.writes.some(write => write.kind === "value"), false);
  assertNoSave(subject);
});

test("table: initial cancellation prevents field writes and Save", async () => {
  const subject = tableFixture();
  const { error } = await prepareTable(subject, { assertActive() { throw subject.state.cancelError(); } });
  assert.equal(error?.code, "preparation_cancelled");
  assert.deepEqual(subject.state.writes, []);
  assertNoSave(subject);
});

test("table: captured separate Hours/colon/Mins generic DIV excludes history and price inputs", async () => {
  // Structure and empty attributes come from live-eighth/after-settled-structure.json,
  // entryForm, 2026-09-14. Item set is expanded here to test every requested item;
  // this fixture does not claim all sixteen are default live columns.
  const subject = tableFixture({ separateClock:true,paddedIcons:true });
  const {state} = subject;
  let price;
  state.fixtureWrite(() => {
    const history = state.document.body.appendChild(new state.Element("table"));
    history.appendChild(new state.Element("thead")).appendChild(new state.Element("tr"))
      .appendChild(new state.Element("th", {}, "Time ago"));
    const prices = state.editor.appendChild(new state.Element("table"));
    const header = prices.appendChild(new state.Element("thead")).appendChild(new state.Element("tr"));
    for (const name of ["Item", "Price", "Tax"]) header.appendChild(new state.Element("th", {}, name));
    const row = prices.appendChild(new state.Element("tbody")).appendChild(new state.Element("tr"));
    row.appendChild(new state.Element("td")).appendChild(new state.Element("img", {
      src:"https://assets.garmoth.com/img/new_icon/03_etc/07_productmaterial/00004006.webp",
    }));
    price = row.appendChild(new state.Element("td")).appendChild(new state.HTMLInputElement({type:"number"}));
    price.value = "999999";
  });
  subject.draft.session.agrisActive = false;
  const {result,error} = await prepareTable(subject);
  assert.equal(error,undefined);
  assert.equal(result.ok,true);
  assert.equal(result.matched.length,16);
  assert.equal(subject.duration.value,"0");
  assert.equal(subject.minutes.value,"15");
  assert.equal(subject.agris.value,"117","boolean No must not be converted into numeric Agris points");
  assert.equal(price.value,"999999","the item price table is not a loot input row");
  assertItems(subject);
  assertNoSave(subject);
});

test("table: captured nested P-labelled percentages preserve blank and accept explicit zero", async () => {
  const subject = tableFixture({separateClock:true,paddedIcons:true});
  const controls = [];
  subject.state.fixtureWrite(() => {
    for (const text of ["Additional Drop RATE","Additional Drop AMOUNT"]) {
      const field = subject.state.editor.appendChild(new subject.state.Element("div"));
      field.appendChild(new subject.state.Element("p", {}, text));
      let wrapper = field;
      for (let depth=0;depth<3;depth+=1) wrapper=wrapper.appendChild(new subject.state.Element("div"));
      const input=wrapper.appendChild(new subject.state.HTMLInputElement({type:"text",id:"",placeholder:"0"}));
      input.value="17";
      wrapper.appendChild(new subject.state.Element("label", {for:""}, "%"));
      controls.push(input);
    }
  });
  subject.draft.session.additionalDropRate=null;
  subject.draft.session.additionalDropAmount=0;
  const {result,error}=await prepareTable(subject);
  assert.equal(error,undefined);
  assert.equal(result.ok,true);
  assert.equal(controls[0].value,"17");
  assert.equal(controls[1].value,"0");
  subject.draft.session.additionalDropRate=25;
  subject.draft.session.additionalDropAmount=100;
  assert.equal((await prepareTable(subject)).result.ok,true);
  subject.draft.session.additionalDropRate=null;
  subject.draft.session.additionalDropAmount=null;
  assert.equal((await prepareTable(subject)).result.ok,true);
  assert.equal(controls[0].value,"25");
  assert.equal(controls[1].value,"100");
  subject.draft.session.additionalDropRate=0;
  subject.draft.session.additionalDropAmount=0;
  assert.equal((await prepareTable(subject)).result.ok,true);
  assert.equal(controls[0].value,"0");
  assert.equal(controls[1].value,"0");
  assertNoSave(subject);
});

test("table: final readback warns if loot input events reset explicit Agris and percentages", async () => {
  for(const desired of [{agris:true,rate:25,amount:100},{agris:false,rate:0,amount:0}]){
    const subject=tableFixture({separateClock:true,paddedIcons:true});
    const toggle=installAgrisHeader(subject,!desired.agris);
    const [rate,amount]=installPercentageFields(subject);
    subject.draft.session.agrisActive=desired.agris;
    subject.draft.session.additionalDropRate=desired.rate;
    subject.draft.session.additionalDropAmount=desired.amount;
    subject.inputs.values().next().value.addEventListener("input",()=>subject.state.fixtureWrite(()=>{
      toggle.setState(!desired.agris);
      rate.value=desired.rate===0?"":"0";
      amount.value=desired.amount===0?"":"0";
    }));
    const {result,error}=await prepareTable(subject);
    assert.equal(error,undefined);
    assert.equal(result.ok,true,"entered loot remains available for review");
    assert.equal(result.matched.length,16);
    for(const code of ["agris_toggle_not_accepted","additional_drop_rate_field_not_accepted","additional_drop_amount_field_not_accepted"])
      assert.equal(result.warnings.includes(code),true,code);
    assert.equal(toggle.state(),!desired.agris,"final validation must not silently reapply a reset option");
    assert.equal(subject.agris.value,"117");
    assertItems(subject);
    assertNoSave(subject);
  }
});

test("table: final readback does not validate or rewrite omitted session options", async () => {
  const subject=tableFixture({separateClock:true,paddedIcons:true});
  const toggle=installAgrisHeader(subject,false);
  const [rate,amount]=installPercentageFields(subject);
  subject.draft.session.agrisActive=null;
  subject.draft.session.additionalDropRate=null;
  subject.draft.session.additionalDropAmount=null;
  subject.inputs.values().next().value.addEventListener("input",()=>subject.state.fixtureWrite(()=>{
    toggle.setState(true);rate.value="25";amount.value="100";
  }));
  const {result,error}=await prepareTable(subject);
  assert.equal(error,undefined);
  assert.equal(result.ok,true);
  assert.deepEqual(Array.from(result.warnings),[]);
  assert.equal(toggle.state(),true);
  assert.equal(rate.value,"25");assert.equal(amount.value,"100");
  assert.equal(subject.state.writes.some(write=>write.kind==="click" && write.target==="table-agris-header"),false);
  assertNoSave(subject);
});

test("table: retry clears previously entered loot removed from the draft while preserving unrelated values", async () => {
  const subject=tableFixture({separateClock:true,paddedIcons:true});
  installTableTooltips(subject);
  assert.equal((await prepareTable(subject)).result.matched.length,16);
  subject.draft.session.items=[
    {...coralItems[0],quantity:1},
    {...coralItems[1],quantity:2},
    {itemId:"999999999",name:"Unrecognized fixture item",quantity:3,subKey:0},
  ];
  subject.draft=subject.state.draft({target:subject.draft.target,session:subject.draft.session});
  const {result,error}=await prepareTable(subject);
  assert.equal(error,undefined);
  assert.equal(result.ok,true);
  assert.equal(result.matched.length,2);
  assert.equal(result.skipped.length,1);
  assert.equal(subject.inputs.get("4006").value,"1");
  assert.equal(subject.inputs.get("4999").value,"2");
  for(const item of coralItems.slice(2)) {
    const input=subject.inputs.get(item.itemId);
    assert.equal(input.value,"",item.name+" must not remain as stale loot");
    assert.equal(input.getAttribute("data-bsl-session-import-written"),null);
    assert.equal(input.getAttribute("data-bsl-session-import-optional"),null);
  }
  assert.equal(subject.agris.value,"117","unowned numeric Agris points stay untouched");
  assert.equal(subject.duration.value,"0");
  assert.equal(subject.minutes.value,"15");
  assertNoSave(subject);
});

test("table: real tooltip names override swapped artwork instead of swapping quantities", async () => {
  const subject=tableFixture({items:coralItems.slice(0,2),separateClock:true,paddedIcons:true});
  subject.state.fixtureWrite(() => {
    subject.headers.get("4006").children[0].setAttribute("src","https://assets.garmoth.com/img/new_icon/00004999.webp");
    subject.headers.get("4999").children[0].setAttribute("src","https://assets.garmoth.com/img/new_icon/00004006.webp");
  });
  installTableTooltips(subject);
  const {result,error}=await prepareTable(subject);
  assert.equal(error,undefined);
  assert.equal(result.ok,true);
  assertItems(subject);
  assert.equal(subject.agris.value,"117");
  assertNoSave(subject);
});

test("table: shared Fairy artwork is resolved by each exact tooltip, never a hardcoded alias", async () => {
  const items=[coralItems.find(item=>item.itemId==="821371"),
    {itemId:"820014",name:"Dormant Fairy's Breath",quantity:7,subKey:0}];
  const subject=tableFixture({items,separateClock:true,paddedIcons:true});
  subject.state.fixtureWrite(() => {
    for (const header of subject.headers.values()) header.children[0].setAttribute("src",
      "https://assets.garmoth.com/img/new_icon/03_etc/07_productmaterial/000820014.webp");
  });
  installTableTooltips(subject);
  const {result,error}=await prepareTable(subject);
  assert.equal(error,undefined);
  assert.equal(result.ok,true);
  assert.equal(result.matched.length,2);
  assertItems(subject);
  assertNoSave(subject);
});

test("table: absent, prefix-only or duplicate tooltip identities never fall back to the artwork ID", async () => {
  for (const kind of ["absent","prefix","duplicate"]) {
    const subject=tableFixture({items:kind==="duplicate" ? coralItems.slice(0,2) : coralItems.slice(0,1),separateClock:true,paddedIcons:true});
    installTableTooltips(subject,new Map([["4006",kind==="prefix" ? "Rough Stone fragment" : "Rough Stone"],["4999","Rough Stone"]]),{show:kind!=="absent"});
    const {result,error}=await prepareTable(subject);
    assert.equal(error,undefined);
    assert.equal(result.ok,false,kind);
    for (const control of subject.inputs.values()) assert.equal(control.value,"0",kind);
    assert.equal(subject.agris.value,"117");
    assertNoSave(subject);
  }
});

test("table: actual Agris X/check shapes set Yes and No once without changing points or using colour", async () => {
  for (const desired of [true,false]) {
    const subject=tableFixture({separateClock:true,paddedIcons:true});
    const toggle=installAgrisHeader(subject,!desired);
    subject.draft.session.agrisActive=desired;
    const {result,error}=await prepareTable(subject);
    assert.equal(error,undefined);
    assert.equal(result.ok,true);
    assert.equal(toggle.state(),desired);
    assert.equal(subject.agris.value,"117");
    assert.equal(subject.state.writes.filter(write=>write.kind==="click" && write.target==="table-agris-header").length,1);
    assert.equal(result.warnings.includes("agris_toggle_not_found"),false);
    assert.equal(result.warnings.includes("agris_toggle_not_accepted"),false);
    assertNoSave(subject);
  }
});

test("table: Agris waits for its known state glyph to mount before an explicit Yes", async () => {
  const subject=tableFixture({separateClock:true,paddedIcons:true});
  const toggle=installAgrisHeader(subject,false);
  const svg=toggle.header.children.find(child=>child.tagName==="SVG");
  subject.state.fixtureWrite(()=>detach(svg));
  subject.state.context.setTimeout(()=>subject.state.fixtureWrite(()=>toggle.header.appendChild(svg)),150);
  subject.draft.session.agrisActive=true;
  const {result,error}=await prepareTable(subject);
  assert.equal(error,undefined);
  assert.equal(result.ok,true);
  assert.equal(toggle.state(),true);
  assert.equal(subject.agris.value,"117");
  assert.equal(subject.state.writes.filter(write=>write.kind==="click" && write.target==="table-agris-header").length,1);
  assert.equal(result.warnings.includes("agris_toggle_not_found"),false);
  assertNoSave(subject);
});

test("table: absent Agris glyph times out without a guessed toggle or late click", async () => {
  const subject=tableFixture({separateClock:true,paddedIcons:true});
  const toggle=installAgrisHeader(subject,false);
  const svg=toggle.header.children.find(child=>child.tagName==="SVG");
  subject.state.fixtureWrite(()=>detach(svg));
  subject.state.context.setTimeout(()=>subject.state.fixtureWrite(()=>toggle.header.appendChild(svg)),2000);
  subject.draft.session.agrisActive=true;
  const {result,error}=await prepareTable(subject);
  assert.equal(error,undefined);
  assert.equal(result.ok,true);
  assert.equal(toggle.state(),false);
  assert.equal(result.warnings.includes("agris_toggle_not_found"),true);
  assert.equal(subject.state.writes.some(write=>write.kind==="click" && write.target==="table-agris-header"),false);
  assert.equal(subject.agris.value,"117");
  assertNoSave(subject);
});

test("table: cancellation during Agris readiness stops before the delayed glyph can toggle", async () => {
  const subject=tableFixture({separateClock:true,paddedIcons:true});
  const toggle=installAgrisHeader(subject,false);
  const svg=toggle.header.children.find(child=>child.tagName==="SVG");
  subject.state.fixtureWrite(()=>detach(svg));
  subject.state.context.setTimeout(()=>subject.state.fixtureWrite(()=>toggle.header.appendChild(svg)),150);
  subject.draft.session.agrisActive=true;
  const {error}=await prepareTable(subject,{assertActive(){if(subject.state.now>=100)throw subject.state.cancelError();}});
  assert.equal(error?.code,"preparation_cancelled");
  assert.equal(toggle.state(),false);
  assert.equal(subject.state.writes.some(write=>write.kind==="click" && write.target==="table-agris-header"),false);
  assert.equal(subject.agris.value,"117");
  for(const input of subject.inputs.values())assert.equal(input.value,"0");
  assertNoSave(subject);
});

test("table: changed spot during Agris readiness cannot receive the old draft toggle", async () => {
  const subject=tableFixture({separateClock:true,paddedIcons:true});
  const toggle=installAgrisHeader(subject,false);
  const svg=toggle.header.children.find(child=>child.tagName==="SVG");
  subject.state.fixtureWrite(()=>detach(svg));
  subject.state.context.setTimeout(()=>subject.state.fixtureWrite(()=>{
    for(const heading of subject.state.document.querySelectorAll("h1"))heading.textContent="Different spot";
    toggle.header.appendChild(svg);
  }),100);
  subject.draft.session.agrisActive=true;
  const {error}=await prepareTable(subject);
  assert.equal(error?.code,"spot_not_selected");
  assert.equal(toggle.state(),false);
  assert.equal(subject.state.writes.some(write=>write.kind==="click" && write.target==="table-agris-header"),false);
  assert.equal(subject.agris.value,"117");
  assertNoSave(subject);
});

test("table: unknown or rejected Agris glyphs remain explicit warnings and never numeric writes", async () => {
  for (const kind of ["unknown","rejected","already-set"]) {
    const subject=tableFixture({separateClock:true,paddedIcons:true});
    installAgrisHeader(subject,kind==="already-set",{unknown:kind==="unknown",reject:kind==="rejected"});
    subject.draft.session.agrisActive=true;
    const {result,error}=await prepareTable(subject);
    assert.equal(error,undefined);
    assert.equal(result.ok,true);
    assert.equal(subject.agris.value,"117");
    const clicks=subject.state.writes.filter(write=>write.kind==="click" && write.target==="table-agris-header").length;
    assert.equal(clicks,kind==="rejected" ? 1 : 0);
    if (kind!=="already-set") assert.ok(result.warnings.includes(kind==="unknown" ? "agris_toggle_not_found" : "agris_toggle_not_accepted"));
    assertNoSave(subject);
  }
});
