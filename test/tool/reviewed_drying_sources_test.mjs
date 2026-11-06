import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {applyReviewedDryingSources,dryingSourceCorrections} from '../../tool/apply_reviewed_drying_sources_20261103.mjs';
const fixture=()=>({recipes:[{keep:true}],acquisitionInfo:Object.fromEntries(dryingSourceCorrections.map(e=>[e.name,{itemId:e.id,canonicalName:e.name,routes:[{kind:'processing',summary:`Dry ${e.before} in the Processing window during clear weather.`,sources:[]},{kind:'market',summary:'Central Market',sources:[]}]}]))});
test('correct exact input names and preserve independent routes and recipes',()=>{
 const before=fixture(),after=applyReviewedDryingSources(before);
 assert.deepEqual(after.recipes,before.recipes);
 for(const e of dryingSourceCorrections){assert.equal(after.acquisitionInfo[e.name].routes[0].summary,`Dry ${e.input} in the Processing window during clear weather.`);assert.deepEqual(after.acquisitionInfo[e.name].routes[1],before.acquisitionInfo[e.name].routes[1]);}
 assert.deepEqual(before,fixture());
});
test('repeated application is idempotent',()=>{const once=applyReviewedDryingSources(fixture());assert.deepEqual(applyReviewedDryingSources(once),once);});
test('wrong positive identity fails closed',()=>{const f=fixture();f.acquisitionInfo['Dried Pearl Oyster Flesh'].itemId=6509;assert.throws(()=>applyReviewedDryingSources(f));});
test('wrong name and unreviewed source wording fail closed',()=>{const f=fixture();f.acquisitionInfo['Dried Pearl Oyster Flesh'].canonicalName='Other';assert.throws(()=>applyReviewedDryingSources(f));const g=fixture();g.acquisitionInfo['Dried Pearl Oyster Flesh'].routes[0].summary='Unknown method';assert.throws(()=>applyReviewedDryingSources(g));});
test('regeneration matches the bundled data',()=>{const b=JSON.parse(fs.readFileSync('assets/data/app-data.json'));assert.deepEqual(applyReviewedDryingSources(b),b);});
