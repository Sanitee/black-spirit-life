import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

export function applyReviewedProcessingGuidance(catalog) {
  const result=structuredClone(catalog);
  const routes=[
    {name:'Black Gold Ingot',id:4267,before:"Heat Ocean Stalker's Skin ×10 + Pure Platinum Crystal ×2.",after:"Heat [Guild] Ocean Stalker's Skin ×10 + Pure Platinum Crystal ×2."},
    {name:'Black Magic Crystal - Addis',id:15650,before:'Use the Processing method listed in Crafting Notes.',after:'Heat Black Essence: Addis ×1 + Ancient Magic Crystal - Addis ×1.'},
  ];
  for(const change of routes){
    const entry=result.acquisitionInfo[change.name];assert.equal(entry.itemId,change.id);assert.equal(entry.canonicalName,change.name);
    const matching=entry.routes.filter(r=>[change.before,change.after].includes(r.summary));assert.equal(matching.length,1);
    matching[0].summary=change.after;
  }
  const notes=[
    {name:'Delotia Powder',id:'5605',method:'Grinding',before:'Imported from BDO Codex mrecipe 2410. 1 of 3 variants fit this planner recipe; remaining variants stay in import metadata.',after:'Grinding · Delotia'},
    ...[['Breath of All Creations','56185'],["Elion's Tear",'17566']].map(([name,id])=>({name,id,method:'Simple Alchemy',before:'September 3, 2026 formula verified against the current game client.',after:'Simple Alchemy · Processing (L)'})),
  ];
  for(const change of notes){
    const recipe=result.processing.items[change.name];assert.equal(recipe.marketId,change.id);assert.equal(recipe.method,change.method);
    assert([change.before,change.after].includes(recipe.sourceNote));recipe.sourceNote=change.after;
  }
  const reverse=structuredClone(result);
  for(const c of routes)reverse.acquisitionInfo[c.name]=structuredClone(catalog.acquisitionInfo[c.name]);
  for(const c of notes)reverse.processing.items[c.name]=structuredClone(catalog.processing.items[c.name]);
  assert.deepEqual(reverse,catalog,'Only five reviewed source fields may change');
  return result;
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1]){
  const file=new URL('../assets/data/app-data.json',import.meta.url),raw=await fs.readFile(file,'utf8');
  const before=JSON.parse(raw),after=applyReviewedProcessingGuidance(before);assert.deepEqual(applyReviewedProcessingGuidance(after),after);
  const next=JSON.stringify(after,null,2)+'\n';if(next!==raw)await fs.writeFile(file,next);
  console.log('Five exact source fields updated; all recipe ingredients, outputs, identities and other data retained.');
}
