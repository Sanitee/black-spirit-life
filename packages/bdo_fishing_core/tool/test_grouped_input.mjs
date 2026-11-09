import fs from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const js=await fs.readFile(new URL('../assets/fish_companion/static/app.js',import.meta.url),'utf8');
const snippet=js.slice(js.indexOf('function groupWholeEdit('),js.indexOf('const LIFE_SKILL_RANK_OFFSETS'));
const fields=Object.fromEntries(['haulMastery','profileMastery','haulSoldAmount','saleFinalAmount'].map(id=>[id,{
  value:'',selectionStart:0,selectionEnd:0,selectionDirection:'none',events:{},
  addEventListener(name,listener){(this.events[name]??=[]).push(listener);},
  setSelectionRange(start,end){this.selectionStart=start;this.selectionEnd=end;},
}]));
const context=vm.createContext({els:fields});vm.runInContext(snippet,context);
const format=context.groupWholeEdit;
assert.equal(format('10000',5,5).text,'10.000');
assert.equal(format('123456789012345',15,15).text,'123.456.789.012.345');
assert.equal(format('1.2',3,3).text,'1.2');
assert.equal(format('abc1000',7,7).text,'abc1000');
const middle=format('1.2934',4,4,{text:'1.234',start:3,end:3},'insertText');
assert.equal(middle.text,'12.934');assert.equal(middle.start,4);
const back=format('1234',1,1,{text:'1.234',start:2,end:2},'deleteContentBackward');
assert.equal(back.text,'234');assert.equal(back.start,0);
context.bindGroupedAmountInputs();context.bindGroupedAmountInputs();
for(const field of Object.values(fields)) {
 assert.equal(field.events.input.length,1);
 for(const digit of '1234567') {
  field.events.beforeinput[0]({inputType:'insertText'});
  field.value+=digit;field.selectionStart=field.selectionEnd=field.value.length;
  field.events.input[0]({inputType:'insertText',isComposing:false});
 }
 assert.equal(field.value,'1.234.567');assert.equal(field.selectionStart,9);
 field.value='10000';field.events.input[0]({isComposing:true});assert.equal(field.value,'10000');
}
assert(js.includes('  bindGroupedAmountInputs();'));
console.log('Fishing grouping: typing, paste, middle edits, deletion, exact large values, composition and all four fields PASS');
