import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {applyReviewedProcessingGuidance} from '../../tool/apply_reviewed_processing_guidance_20261103.mjs';
const load=()=>JSON.parse(fs.readFileSync('assets/data/app-data.json'));
test('source correction is idempotent and keeps every mechanical field',()=>{
 const before=load(),after=applyReviewedProcessingGuidance(before);assert.deepEqual(after,before);
 for(const mode of ['processing','cooking','']){const records=(mode?before[mode]:before).items;
  for(const [name,r]of Object.entries(records)){
   const updated=(mode?after[mode]:after).items[name];const a=structuredClone(r),b=structuredClone(updated);delete a.sourceNote;delete b.sourceNote;assert.deepEqual(a,b);
  }
 }
});
test('Black Gold Ingot explicitly retains the guild ingredient identity',()=>{
 const b=load();b.acquisitionInfo['Black Gold Ingot'].routes[0].summary="Heat Ocean Stalker's Skin ×10 + Pure Platinum Crystal ×2.";
 assert.deepEqual(applyReviewedProcessingGuidance(b),load());
});
test('Addis generic guidance is replaced only for the exact output',()=>{
 const b=load();b.acquisitionInfo['Black Magic Crystal - Addis'].routes[0].summary='Use the Processing method listed in Crafting Notes.';
 assert.deepEqual(applyReviewedProcessingGuidance(b),load());b.acquisitionInfo['Black Magic Crystal - Addis'].itemId=15224;assert.throws(()=>applyReviewedProcessingGuidance(b));
});
test('unexpected source text and recipe identities fail closed',()=>{
 const b=load();b.processing.items['Delotia Powder'].marketId='1';assert.throws(()=>applyReviewedProcessingGuidance(b));
 const c=load();c.processing.items["Elion's Tear"].sourceNote='Unreviewed alternate method';assert.throws(()=>applyReviewedProcessingGuidance(c));
});
