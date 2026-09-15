"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const {fixture, settle, writtenAttribute} = require("./browser_dom_fixture.cjs");

const extensionRoot = path.resolve(__dirname,"../../windows/session_import/browser_extension/tracker_helper");
const start = "[BS Life: not included in Garmoth totals]";
const end = "[/BS Life]";
const missing = [
  {itemId:"6511",subKey:0,name:"Lobster",quantity:38},
  {itemId:"821350",subKey:0,name:"Cracked Terrashard",quantity:2},
  {itemId:"4477",subKey:0,name:"Blue Coral",quantity:5}
];
const plain = value => JSON.parse(JSON.stringify(value));
const block = (entries=missing) => start+"\n"+entries.map(item=>item.name+" × "+item.quantity).join("\n")+"\n"+end+"\n";
function detach(element) {
  element.parentElement.children=element.parentElement.children.filter(child=>child!==element);
  element.parentElement=null;
}
function installNotes(state,{collapsed=false,text="",delay=0,placeholder="Notes"}={}) {
  // Exact structural shape captured in live-notes-inspection/notes-inspection.json.
  let panel,header,body,control;
  state.fixtureWrite(()=>{
    panel=state.editor.appendChild(new state.Element("div",{class:"min-h-[2rem] overflow-hidden rounded-md bg-light border border-light"}));
    header=panel.appendChild(new state.Element("div",{id:"notes-header",class:"flex cursor-pointer select-none items-center justify-between bg-default px-3 py-1"}));
    header.appendChild(new state.Element("span",{class:"text-base font-semibold"},"Notes "));
    header.appendChild(new state.Element("svg",{class:"icon transition"}));
    body=new state.Element("div");
    const inset=body.appendChild(new state.Element("div",{class:"p-2"}));
    control=new state.context.HTMLTextAreaElement({id:"notes-input",rows:"3",placeholder,class:"block w-full px-2 py-1 text-sm font-normal placeholder:font-normal"});
    control.tagName="TEXTAREA";
    control.value=text;
    inset.appendChild(control);
    if (!collapsed) panel.appendChild(body);
  });
  header.addEventListener("click",()=>state.context.setTimeout(()=>state.fixtureWrite(()=>{
    if (!body.parentElement) panel.appendChild(body);
  }),delay));
  return {panel,header,body,control};
}
function subject(options) {
  const state=fixture();
  const notes=installNotes(state,options);
  const draft=state.draft();
  draft.session.items.push(...plain(missing));
  // Reparse the wire draft into the production protocol realm.
  return {state,notes,draft:state.draft(plain(draft))};
}
async function prepare(subject,options) {
  const pending=subject.state.prepare(options,subject.draft).then(result=>({result}),error=>({error}));
  await subject.state.advance(10000);
  const outcome=await pending;
  assert.equal(subject.state.writes.some(write=>write.kind==="click"&&write.target==="save"),false,"Save stays manual");
  return outcome;
}
function reparse(subject) {subject.draft=subject.state.draft(plain(subject.draft));}
function reinject(state) {vm.runInContext(fs.readFileSync(path.join(extensionRoot,"content.js"),"utf8"),state.context);}
function noteWrites(subject) {return subject.state.writes.filter(write=>write.target==="notes-input"&&write.kind==="value");}

test("Notes: captured collapsed accordion adds only definitive missing items with truthful structured counts",async()=>{
  const value=subject({collapsed:true,delay:200});
  const {result,error}=await prepare(value);
  assert.equal(error,undefined);
  assert.equal(result.ok,true);
  assert.equal(result.matched.length,1);
  assert.equal(result.skipped.length,3);
  assert.equal(result.notesStatus,"verified");
  assert.deepEqual(plain(result.notesVerified),missing.map((item,index)=>({index:index+1,...item})));
  assert.equal(value.notes.control.value,block());
  assert.equal(value.state.writes.filter(write=>write.kind==="click"&&write.target==="notes-header").length,1);
  assert.equal(value.notes.control.getAttribute(writtenAttribute),null,"Notes is never a whole-field cleanup target");
  assert.equal(value.state.fields.loot.value,"59");
});

test("Notes: existing user text remains byte-for-byte intact with a removable owned separator",async()=>{
  for(const text of ["User notes \n\n", "  User notes\t", "First\r\nSecond\r\n"]) {
    const value=subject({text});
    const first=await prepare(value);
    assert.equal(first.result.notesStatus,"verified");
    assert.equal(value.notes.control.value,text+(text.endsWith("\n")?"\n":"\n\n")+block());
    value.draft.session.items.length=1;
    reparse(value);
    const second=await prepare(value);
    assert.equal(second.result.notesStatus,"verified");
    assert.deepEqual(plain(second.result.notesVerified),[]);
    assert.equal(value.notes.control.value,text);
  }
});

test("Notes: reinjection and same draft do not duplicate or rewrite the owned block",async()=>{
  const value=subject();
  assert.equal((await prepare(value)).result.notesStatus,"verified");
  const count=noteWrites(value).length;
  reinject(value.state);
  value.draft.draftId="next-draft-after-status";
  assert.equal((await prepare(value)).result.notesStatus,"verified");
  assert.equal(value.notes.control.value,block());
  assert.equal(noteWrites(value).length,count);
});

test("Notes: new draft replaces only proven owned block, preserves user prefix and suffix, then removes only block",async()=>{
  const value=subject();
  await prepare(value);
  const prefix="User introduction\n",suffix="\nUser conclusion  ";
  value.state.fixtureWrite(()=>value.notes.control.value=prefix+value.notes.control.value+suffix);
  reinject(value.state);
  value.draft.session.items[1].quantity=42;
  value.draft.session.items.splice(2,1);
  const result=(await prepare(value)).result;
  assert.equal(result.notesStatus,"verified");
  assert.equal(value.notes.control.value,prefix+block([{...missing[0],quantity:42},missing[2]])+suffix);
  value.draft.session.items.length=1;
  assert.equal((await prepare(value)).result.notesStatus,"verified");
  assert.equal(value.notes.control.value,prefix+suffix);
  assert.equal(value.state.fields.loot.value,"59");
});

test("Notes: persisted or copied marker without current ownership cannot be overwritten",async()=>{
  const value=subject({text:"User\n"+block()});
  const before=value.notes.control.value;
  const {result}=await prepare(value);
  assert.equal(result.notesStatus,"failed");
  assert.ok(result.warnings.includes("unsupported_notes_conflict"));
  assert.equal(value.notes.control.value,before);
  assert.equal(noteWrites(value).length,0);
});

test("Notes: edits within an owned block and duplicated blocks fail closed",async()=>{
  for(const change of [text=>text.replace("Lobster × 38","Lobster × 39"),text=>text+text]) {
    const value=subject();
    await prepare(value);
    value.state.fixtureWrite(()=>value.notes.control.value=change(value.notes.control.value));
    const before=value.notes.control.value,count=noteWrites(value).length;
    const {result}=await prepare(value);
    assert.equal(result.notesStatus,"failed");
    assert.ok(result.warnings.includes("unsupported_notes_conflict"));
    assert.equal(value.notes.control.value,before);
    assert.equal(noteWrites(value).length,count);
  }
});

test("Notes: a different editor with copied Notes cannot inherit the previous editor ownership",async()=>{
  const value=subject();
  await prepare(value);
  const old=value.state.editor;
  let replacement;
  value.state.fixtureWrite(()=>{
    replacement=new value.state.Element("div",{role:"dialog","aria-label":"Add session"});
    for(const child of [...old.children]){detach(child);replacement.appendChild(child);}
    detach(old);value.state.document.body.appendChild(replacement);
  });
  const count=noteWrites(value).length;
  const {result}=await prepare(value);
  assert.equal(result.notesStatus,"failed");
  assert.ok(result.warnings.includes("unsupported_notes_conflict"));
  assert.equal(noteWrites(value).length,count);
});

test("Notes: textarea-only remount is verified and remains owned by its editor",async()=>{
  const value=subject();
  value.notes.control.addEventListener("input",()=>value.state.fixtureWrite(()=>{
    const previous=value.notes.control;
    const replacement=new value.state.context.HTMLTextAreaElement({id:"notes-input",placeholder:"Notes",rows:"3"});
    replacement.tagName="TEXTAREA";replacement.value=previous.value;
    const parent=previous.parentElement;detach(previous);parent.appendChild(replacement);value.notes.control=replacement;
  }));
  assert.equal((await prepare(value)).result.notesStatus,"verified");
  value.draft.session.items[1].quantity=41;
  assert.equal((await prepare(value)).result.notesStatus,"verified");
  assert.match(value.notes.control.value,/Lobster × 41/);
});

test("Notes: missing, ambiguous or wrong editable controls cannot receive text",async()=>{
  for(const kind of ["outside","duplicate-panel","two-fields","wrong-placeholder","readonly"]) {
    const value=subject();
    value.state.fixtureWrite(()=>{
      if(kind==="outside"){detach(value.notes.panel);value.state.document.body.appendChild(value.notes.panel);}
      if(kind==="duplicate-panel")installNotes(value.state);
      if(kind==="two-fields")value.notes.body.appendChild(new value.state.HTMLInputElement({placeholder:"Video link"}));
      if(kind==="wrong-placeholder")value.notes.control.setAttribute("placeholder","Video Link");
      if(kind==="readonly")value.notes.control.readOnly=true;
    });
    const {result}=await prepare(value);
    assert.equal(result.ok,true);
    assert.equal(result.notesStatus,"failed",kind);
    assert.ok(result.warnings.includes("unsupported_notes_not_found"),kind);
    assert.deepEqual(plain(result.notesVerified),[]);
    assert.equal(noteWrites(value).length,0,kind);
  }
});

test("Notes: rejected or later-reset text never produces verified entries",async()=>{
  for(const delay of [0,20]) {
    const value=subject({text:"Keep user notes"});
    value.notes.control.addEventListener("input",()=>{
      const reset=()=>value.state.fixtureWrite(()=>value.notes.control.value="Keep user notes");
      if(delay)value.state.context.setTimeout(reset,delay);else reset();
    });
    const {result}=await prepare(value);
    assert.equal(result.notesStatus,"failed");
    assert.ok(result.warnings.includes("unsupported_notes_not_accepted"));
    assert.deepEqual(plain(result.notesVerified),[]);
    assert.equal(value.notes.control.value,"Keep user notes");
  }
});

test("Notes: maximum length is checked before any write or verified claim",async()=>{
  for(const kind of ["dom-limit","bounded-total"]) {
    const value=subject({text:kind==="bounded-total"?"x".repeat(65536):"Keep"});
    if(kind==="dom-limit")value.state.fixtureWrite(()=>value.notes.control.setAttribute("maxlength","8"));
    const before=value.notes.control.value;
    const {result}=await prepare(value);
    assert.equal(result.notesStatus,"failed");
    assert.ok(result.warnings.includes("unsupported_notes_too_long"));
    assert.equal(value.notes.control.value,before);
    assert.equal(noteWrites(value).length,0);
  }
});

test("Notes: cancellation while the accordion mounts cannot produce late Notes writes",async()=>{
  const value=subject({collapsed:true,delay:500});
  let cancelled=false;
  value.notes.header.addEventListener("click",()=>{cancelled=true;});
  const {error}=await prepare(value,{assertActive(){if(cancelled)throw value.state.cancelError();}});
  assert.equal(error?.code,"preparation_cancelled");
  assert.equal(noteWrites(value).length,0);
  assert.equal(value.notes.control.value,"");
});

test("Notes: cancellation on input prevents subsequent events and false verification",async()=>{
  const value=subject();
  let cancelled=false;
  value.notes.control.addEventListener("input",()=>{cancelled=true;});
  const {error}=await prepare(value,{assertActive(){if(cancelled)throw value.state.cancelError();}});
  assert.equal(error?.code,"preparation_cancelled");
  assert.equal(value.state.writes.some(write=>write.target==="notes-input"&&write.kind==="event"&&write.name==="change"),false);
  assert.equal(value.notes.control.getAttribute(writtenAttribute),null);
});

test("Notes: spot changes while opening cannot receive notes for the previous spot",async()=>{
  const value=subject({collapsed:true,delay:200});
  value.notes.header.addEventListener("click",()=>value.state.fixtureWrite(()=>value.state.select.value="88"));
  const {error}=await prepare(value);
  assert.equal(error?.code,"spot_not_selected");
  assert.equal(noteWrites(value).length,0);
});

test("Notes: all unsupported items remain unsuccessful and cannot write Notes",async()=>{
  const value=subject({collapsed:true});
  value.draft.session.items.shift();
  const {result}=await prepare(value);
  assert.equal(result.ok,false);
  assert.equal(result.code,"no_items_prepared");
  assert.equal(result.matched.length,0);
  assert.equal(result.skipped.length,3);
  assert.equal(noteWrites(value).length,0);
  assert.equal(value.state.writes.some(write=>write.kind==="click"&&write.target==="notes-header"),false);
});

test("Notes: rejected structured values are not reclassified as unsupported Notes entries",async()=>{
  const value=subject();
  const extra=value.state.fields.loot.parentElement.appendChild(new value.state.Element("div",{"data-item-id":"extra-01"}));
  const input=extra.appendChild(new value.state.HTMLInputElement({id:"rejected-quantity",type:"number"}));
  input.addEventListener("input",()=>value.state.fixtureWrite(()=>input.value="0"));
  value.draft.session.items.push({itemId:"extra-01",subKey:0,name:"Rejected known item",quantity:4});
  reparse(value);
  const {result}=await prepare(value);
  assert.ok(result.skipped.some(item=>item.reason==="value_not_accepted"));
  assert.equal(result.notesVerified.length,3);
  assert.equal(value.notes.control.value.includes("Rejected known item"),false);
});

test("Notes: a Notes-triggered duration reset is reported, never marked prepared",async()=>{
  const value=subject();
  value.notes.control.addEventListener("input",()=>value.state.fixtureWrite(()=>value.state.fields["duration-minutes"].value="0"));
  const {result,error}=await prepare(value);
  assert.equal(error,undefined);
  assert.equal(result.ok,false);
  assert.equal(result.code,"session_not_prepared");
  assert.equal(value.state.editor.getAttribute("data-bsl-session-import-draft"),null);
});

test("Notes: explicit percentage values are rechecked after Notes input handlers",async()=>{
  const value=subject();
  const percent=value.state.editor.appendChild(new value.state.HTMLInputElement({id:"drop-rate","aria-label":"Additional drop rate",type:"number"}));
  value.draft.session.additionalDropRate=25;
  value.notes.control.addEventListener("input",()=>value.state.fixtureWrite(()=>percent.value="0"));
  const {result}=await prepare(value);
  assert.equal(result.ok,true);
  assert.ok(result.warnings.includes("additional_drop_rate_field_not_accepted"));
  assert.equal(result.notesStatus,"verified");
});

test("Notes: a structured quantity reset by Notes is downgraded, never rewritten or moved to Notes",async()=>{
  const value=subject();
  value.notes.control.addEventListener("input",()=>value.state.fixtureWrite(()=>value.state.fields.loot.value="0"));
  const {result,error}=await prepare(value);
  assert.equal(error,undefined);
  assert.equal(result.ok,false);
  assert.equal(result.code,"no_items_prepared");
  assert.equal(result.matched.length,0);
  assert.deepEqual(plain(result.skipped[0]),{index:0,itemId:"coral-01",subKey:0,reason:"value_not_accepted"});
  assert.ok(result.warnings.includes("item_values_not_accepted"));
  assert.equal(result.notesVerified.length,3);
  assert.equal(value.notes.control.value.includes("Rusalka"),false);
  assert.equal(value.state.fields.loot.value,"0");
  assert.equal(value.state.writes.filter(write=>write.target==="loot"&&write.kind==="value").length,1);
  assert.equal(value.state.editor.getAttribute("data-bsl-session-import-draft"),null);
});

test("Notes: structured remount is accepted only with current exact identity and quantity",async()=>{
  for(const kind of ["same","wrong-identity","wrong-quantity"]) {
    const value=subject();
    value.notes.control.addEventListener("input",()=>value.state.fixtureWrite(()=>{
      const previous=value.state.fields.loot,parent=previous.parentElement;
      detach(previous);
      const replacement=parent.appendChild(new value.state.HTMLInputElement({id:"remounted-loot",type:"number","aria-label":kind==="wrong-identity"?"Other item amount":"Rusalka's Coral amount"}));
      replacement.value=kind==="wrong-quantity"?"0":"59";
      value.state.fields.loot=replacement;
      if(kind==="wrong-identity") {
        parent.setAttribute("data-item-id","other-01");
        value.state.marker.setAttribute("alt","Other item");
      }
    }));
    const {result,error}=await prepare(value);
    assert.equal(error,undefined);
    assert.equal(result.ok,kind==="same",kind);
    assert.equal(result.matched.length,kind==="same"?1:0,kind);
    assert.equal(value.state.writes.some(write=>write.target==="remounted-loot"&&write.kind==="value"),false);
  }
});

test("Notes: a partial structured reset retains only currently verified matches",async()=>{
  const value=subject();
  const marker=value.state.editor.appendChild(new value.state.Element("div",{"data-item-id":"extra-01"}));
  const input=marker.appendChild(new value.state.HTMLInputElement({id:"extra-loot",type:"number"}));
  value.draft.session.items.push({itemId:"extra-01",subKey:0,name:"Known extra item",quantity:4});reparse(value);
  value.notes.control.addEventListener("input",()=>value.state.fixtureWrite(()=>value.state.fields.loot.value="0"));
  const {result}=await prepare(value);
  assert.equal(result.ok,true);
  assert.deepEqual(plain(result.matched),[{index:4,itemId:"extra-01",subKey:0}]);
  assert.equal(input.value,"4");
  assert.ok(result.warnings.includes("item_values_not_accepted"));
  assert.equal(result.notesVerified.length,3);
});

test("Notes: unchanged proven table bindings avoid a second tooltip sweep but never hide reset quantities or changed identity",async()=>{
  for(const kind of ["same","reset","changed-identity"]) {
    const value=subject();
    const state=value.state;
    let input,header,image,tooltip,hovers=0,name="Rusalka's Coral";
    state.fixtureWrite(()=>{
      detach(state.editor.children.find(child=>child.tagName==="FORM"));
      state.context.location=new URL("https://garmoth.com/grind-tracker/example/spot/77");
      state.document.body.children.find(child=>child.tagName==="H1").textContent=name;
      const table=state.editor.appendChild(new state.Element("table"));
      const heads=table.appendChild(new state.Element("thead")).appendChild(new state.Element("tr"));
      const cells=table.appendChild(new state.Element("tbody")).appendChild(new state.Element("tr"));
      for(const label of ["Hours",":","Mins"]) {
        heads.appendChild(new state.Element("th",{},label));
        const cell=cells.appendChild(new state.Element("td"));
        if(label!==":")cell.appendChild(new state.HTMLInputElement({type:"number"}));
      }
      header=heads.appendChild(new state.Element("th",{id:"item-header",class:"v-popper--has-tooltip"}));
      image=header.appendChild(new state.Element("img",{src:"https://assets.garmoth.com/items/2010.webp"}));
      input=cells.appendChild(new state.Element("td")).appendChild(new state.HTMLInputElement({id:"table-loot",type:"number"}));
    });
    header.addEventListener("mouseenter",()=>state.fixtureWrite(()=>{
      hovers+=1;tooltip=state.document.body.appendChild(new state.Element("div",{role:"tooltip"},name));
    }));
    header.addEventListener("mouseleave",()=>state.fixtureWrite(()=>{if(tooltip?.parentElement)detach(tooltip);}));
    value.draft.session.items[0].itemId="2010";
    value.draft.session.mastery=null;value.draft.session.energySpent=null;
    value.notes.control.addEventListener("input",()=>state.fixtureWrite(()=>{
      if(kind==="reset")input.value="0";
      if(kind==="changed-identity"){image.setAttribute("src","https://assets.garmoth.com/items/2011.webp");name="Other material";}
    }));
    const {result,error}=await prepare(value);
    assert.equal(error,undefined,kind);
    assert.equal(result.ok,kind==="same",kind);
    assert.equal(result.matched.length,kind==="same"?1:0,kind);
    assert.equal(hovers,kind==="changed-identity"?2:1,"no repeat tooltip latency for unchanged bindings");
    assert.equal(state.writes.filter(write=>write.target==="table-loot"&&write.kind==="value").length,1);
    assert.equal(result.notesVerified.length,3);
  }
});

test("Notes: item names remain literal data and app delimiters cannot impersonate ownership",async()=>{
  const value=subject();
  value.draft.session.items[1].name="<script>not executable</script>";
  const {result}=await prepare(value);
  assert.equal(result.notesStatus,"verified");
  assert.ok(value.notes.control.value.includes("<script>not executable</script> × 38"));
  assert.equal(value.notes.panel.querySelectorAll("script").length,0);
  value.draft.session.items[1].name=start;
  const before=value.notes.control.value;
  assert.equal((await prepare(value)).result.notesStatus,"failed");
  assert.equal(value.notes.control.value,before);
});

test("Notes: no unsupported items and no owned block leave unrelated Notes closed and untouched",async()=>{
  const value=subject({collapsed:true,text:"User notes"});
  value.draft.session.items.length=1;
  const {result}=await prepare(value);
  assert.equal(result.notesStatus,"not_needed");
  assert.deepEqual(plain(result.notesVerified),[]);
  assert.equal(value.notes.control.value,"User notes");
  assert.equal(value.state.writes.some(write=>write.kind==="click"&&write.target==="notes-header"),false);
});

test("Notes: real Firefox bridge relays verified notes separately from structured counts",async()=>{
  const event=()=>({listeners:[],addListener(callback){this.listeners.push(callback);},emit(value){for(const callback of this.listeners)callback(value);}});
  const native=event(),messages=[];
  const targetUrl="https://garmoth.com/grind-tracker/example/spot/77";
  const tab={id:20,windowId:1,url:targetUrl,active:false};
  const context={TextEncoder,URL,document:{getElementById(){return {textContent:"",dataset:{}};}},browser:{
    runtime:{onMessage:event(),async sendMessage(){},connectNative(){return {onMessage:native,onDisconnect:event(),postMessage(message){messages.push(plain(message));}};}},
    storage:{session:{async get(){return {sessionImportGarmothTabId:20};},async set(){},async remove(){}}},
    tabs:{onRemoved:event(),async getCurrent(){return {id:100,windowId:1};},async get(){return tab;},async update(_id,options){assert.notEqual(options.active,true);return tab;},async sendMessage(_id,message){
      if(message.type==="tracker_ping")return {ready:true};
      assert.equal(message.type,"prepare_draft");
      return {ok:true,draftId:message.draft.draftId,matched:[{index:0}],skipped:[{index:1,reason:"item_not_found"}],warnings:[],
        notesVerified:[{index:1,...missing[0]}],notesStatus:"verified"};
    }}
  }};
  vm.createContext(context);
  for(const file of ["protocol.js","bridge.js"])vm.runInContext(fs.readFileSync(path.join(extensionRoot,file),"utf8"),context);
  await settle();
  const draft=plain(fixture().draft());draft.session.items.push(missing[0]);
  context.wire=JSON.stringify({type:"prepare",requestId:"notes-relay",draft});
  native.emit(vm.runInContext("JSON.parse(wire)",context));
  await settle();
  const response=messages.find(message=>message.type==="prepareResult");
  assert.equal(response?.ok,true);
  assert.equal(response.matched,1);
  assert.equal(response.skipped.length,1);
  assert.equal(response.notesStatus,"verified");
  assert.deepEqual(response.notesVerified,[{index:1,...missing[0]}]);
});
