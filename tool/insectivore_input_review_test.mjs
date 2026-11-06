import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {applyInsectivoreInputReview} from './apply_insectivore_input_review.mjs';
const catalog=()=>JSON.parse(readFileSync(new URL('../assets/data/app-data.json',import.meta.url)));
test('current input review is deterministic and preserves saved route identity',()=>{
 const c=catalog(),before=structuredClone(c);applyInsectivoreInputReview(c);assert.deepEqual(c,before);
 const v=c.processing.items['Insectivore Plant Powder'].variants[1];
 assert.equal(v.id,'leaves-and-fragments');assert.equal(v.label,'Leaves');assert.deepEqual(v.ingredients,[{name:'Insectivore Plant Leaf',qty:5}]);
});
test('historical fragment input is removed without weakening output uncertainty',()=>{
 const c=catalog(),v=c.processing.items['Insectivore Plant Powder'].variants[1];
  delete c.items['Insectivore Plant Powder'].variants;delete c.items['Insectivore Plant Powder'].defaultVariantId;
  delete c.items['Insectivore Plant Sap'].variants;delete c.items['Insectivore Plant Sap'].defaultVariantId;
 v.label='Leaves + Fragments';v.ingredients.push({name:'Tree Spirit Stone Fragment',qty:10});
 applyInsectivoreInputReview(c);assert.equal(v.ingredients.length,1);
 for(const n of ['Insectivore Plant Powder','Insectivore Plant Sap'])assert.ok(c.verifiedItemInformationReview.estimatedOutputs.includes(n));
});
test('both named routes are available without changing default inputs',()=>{
 const c=catalog();applyInsectivoreInputReview(c);
 assert.deepEqual(c.items['Insectivore Plant Powder'].variants,c.processing.items['Insectivore Plant Powder'].variants);
 assert.equal(c.items['Insectivore Plant Sap'].defaultVariantId,'stalks');
 assert.deepEqual(c.items['Insectivore Plant Sap'].variants[1],{id:'roots',label:'Roots',ingredients:[{name:'Insectivore Plant Root',qty:5}]});
});
test('unexpected recipe identities and inputs fail closed',()=>{
 for(const mutate of [c=>c.processing.items['Insectivore Plant Powder'].marketId='37576',c=>c.processing.items['Insectivore Plant Powder'].variants[1].ingredients[0].qty=6,c=>c.marketIds['Insectivore Plant Leaf']='5443',c=>c.items['Insectivore Plant Root'].marketId='5441']){
  const c=catalog();mutate(c);assert.throws(()=>applyInsectivoreInputReview(c));
 }
});

test('new alternative ingredients have exact ordinary catalog identities and existing art',()=>{
 const c=catalog();
 for(const [name,id] of [['Insectivore Plant Leaf',5441],['Insectivore Plant Root',5443]]){
  assert.deepEqual(c.items[name],{type:'gathered',baseOutput:1,group:'Base Items',ingredients:[],marketId:String(id)});
  assert.ok(c.itemIcons[name]);assert.equal(c.itemIcons[name],c.processing.itemIcons[name]);
  assert.equal(c.itemWeightIds[name],String(id));assert.equal(c.itemWeightsLtById[id],0.1);
 }
});
