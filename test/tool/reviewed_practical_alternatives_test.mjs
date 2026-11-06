import fs from 'node:fs';
import assert from 'node:assert/strict';
import test from 'node:test';
import {applyPracticalAlternatives, practicalAlternatives, immortalConversions} from '../../tool/reviewed_practical_alternatives_20261104.mjs';
const load=()=>JSON.parse(fs.readFileSync('assets/data/app-data.json'));
test('reviewed six alternatives and two conversions are idempotent and narrowly scoped',()=>{
  const current=load();assert.deepEqual(applyPracticalAlternatives(current),current);
  const old=structuredClone(current);
  for(const row of practicalAlternatives){
    const r=old.processing.items[row.name];
    for(const f of [r,...(r.variants??[])]){const i=f.ingredients.find(i=>i.name===row.primary);delete i.options;delete i.substituteGroup;delete i.substituteRatios;}
  }
  for(const row of immortalConversions)old.processing.items[row.name].variants=old.processing.items[row.name].variants.filter(v=>v.routeId!=='immortal-perfume');
  delete old.acquisitionInfo["Khan's Dim Magic"];delete old.itemWeightIds["Khan's Dim Magic"];delete old.itemWeightsLtById['45517'];
  const copy=structuredClone(old);assert.deepEqual(applyPracticalAlternatives(old),current);assert.deepEqual(old,copy);
});

test('Immortal conversion routes keep exact per-output inputs and one bulk catalyst',()=>{
  const c=load();assert.equal(immortalConversions.length,2);
  for(const row of immortalConversions){
    const variants=c.processing.items[row.name].variants.filter(v=>v.routeId==='immortal-perfume');
    assert.equal(variants.length,2);
    for(const v of variants){
      const n=v.batchMultiplier;assert([1,10].includes(n));
      assert.equal(v.outputMin,n);assert.equal(v.outputMax,n);
      assert.deepEqual(v.ingredients.slice(1,3),[{name:'Shining Powder',qty:3*n},{name:'Caphras Essence',qty:10*n}]);
      assert.equal(v.ingredients[0].qty,n);
      assert.equal(v.ingredients.length,n===10?4:3);
      if(n===10)assert.deepEqual(v.ingredients[3],{name:"Ibellab's Essence",qty:1});
    }
  }
});
test('all bulk options preserve catalysts, quantities and fixed outputs',()=>{
  const c=load();for(const name of ['Sturdy Whale Tendon Elixir','Sturdy Whale Tendon Potion']){
    const r=c.processing.items[name];assert.equal(r.variants.length,2);
    for(const v of r.variants){const i=v.ingredients[0];assert.equal(i.qty*i.substituteRatios[i.options[1]],v.batchMultiplier*(name.endsWith('Elixir')?3:1));assert.equal(v.outputMin,v.batchMultiplier);assert.equal(v.outputMax,v.batchMultiplier);if(v.batchMultiplier===10)assert.deepEqual(v.ingredients.at(-1),{name:"Ibellab's Essence",qty:1});}
  }
});
test('changed identity, yield or preexisting options fail closed',()=>{
  for(const mutate of [c=>c.processing.items["Khan's Heart: Destruction"].marketId='45512',c=>c.processing.items['Sturdy Whale Tendon Potion'].outputMax=4,c=>c.processing.items['Sturdy Whale Tendon Elixir'].ingredients[0].qty=2]){const c=load();mutate(c);assert.throws(()=>applyPracticalAlternatives(c));}
});
