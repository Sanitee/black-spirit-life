import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

export function applyReviewedTidalAlternative(catalog){
  const result=structuredClone(catalog),recipe=result.processing.items['Deep Blue Tidal Draught'];
  assert.equal(recipe.marketId,'767695');assert.equal(recipe.method,'Simple Alchemy');
  assert.equal(recipe.baseOutput,0.4);assert.equal(recipe.outputMin,1);assert.equal(recipe.outputMax,1);
  assert.equal(recipe.ingredients.length,2);const first=recipe.ingredients[0];
  assert.equal(first.name,'Tidal Draught');assert.equal(first.qty,4);
  assert.deepEqual(recipe.ingredients[1],{name:'Essence of Tides',qty:1});
  const reviewed={name:'Tidal Draught',qty:4,options:['Tidal Draught','Blue Tidal Draught'],substituteGroup:'Tidal Draught',substituteRatios:{'Tidal Draught':1,'Blue Tidal Draught':0.5}};
  assert([JSON.stringify({name:'Tidal Draught',qty:4}),JSON.stringify(reviewed)].includes(JSON.stringify(first)),'Unexpected input options');
  assert.equal(result.processing.items['Blue Tidal Draught'].marketId,'767694');
  assert.equal(result.processing.items['Tidal Draught'].marketId,'767693');
  recipe.ingredients[0]=reviewed;
  const originalNote='Imported from BDO Codex mrecipe 7590. 1 of 2 variants fit this planner recipe; remaining variants stay in import metadata.';
  const draftNote='Reviewed NA/EU PC April 30, 2025: Essence of Tides x1 with Tidal Draught x4 or Blue Tidal Draught x2. Fixed output x1.';
  const reviewedNote='Simple Alchemy · Processing (L)';
  assert([originalNote,draftNote,reviewedNote].includes(recipe.sourceNote));recipe.sourceNote=reviewedNote;
  const reverse=structuredClone(result);reverse.processing.items['Deep Blue Tidal Draught']=structuredClone(catalog.processing.items['Deep Blue Tidal Draught']);
  assert.deepEqual(reverse,catalog,'No unrelated records or defaults may change');return result;
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1]){
  const file=new URL('../assets/data/app-data.json',import.meta.url),raw=await fs.readFile(file,'utf8');
  const before=JSON.parse(raw),after=applyReviewedTidalAlternative(before);assert.deepEqual(applyReviewedTidalAlternative(after),after);
  const next=JSON.stringify(after,null,2)+'\n';if(next!==raw)await fs.writeFile(file,next);
  console.log('Verified one exact 4:2 ingredient alternative; catalyst, output, defaults and other records unchanged.');
}
