import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

export const dryingSourceCorrections = [
  {id:6520,name:'Dried Pearl Oyster Flesh',before:'Pearl Oyster Flesh',input:'Giant Pearl Clam',knowledgeId:7900},
  {id:8565,name:'Dried Silver Stripe Round Herring',before:'Silver Stripe Round Herring',input:'Silver-Stripe Round Herring',knowledgeId:7501},
];
export function applyReviewedDryingSources(catalog) {
  const result=structuredClone(catalog);
  for(const e of dryingSourceCorrections){
    const row=result.acquisitionInfo[e.name];
    assert.equal(row.itemId,e.id);assert.equal(row.canonicalName,e.name);
    const matches=row.routes.filter(r=>r.kind==='processing');assert.equal(matches.length,1);
    const route=matches[0],before=`Dry ${e.before} in the Processing window during clear weather.`,after=`Dry ${e.input} in the Processing window during clear weather.`;
    assert([before,after].includes(route.summary),'Unexpected source wording: '+e.name);
    route.summary=after;row.reviewedAt='2026-11-03';
    const source={title:'Official NA/EU Processing guide',url:'https://www.naeu.playblackdesert.com/en-US/Wiki?wikiNo=28',supports:['drying-method','clear-weather','on-land']};
    if(!route.sources.some(s=>s.url===source.url))route.sources.push(source);
    // Exact current client knowledge prose is archived in the audit, not a
    // fabricated public URL. Never infer the input from the output's name.
    route.reviewEvidence='docs/reviewed-drying-sources.json#'+e.id;
  }
  const omit=x=>{const c=structuredClone(x);for(const e of dryingSourceCorrections)delete c.acquisitionInfo[e.name];return c;};
  assert.deepEqual(omit(result),omit(catalog),'Only two exact acquisition records may change.');
  return result;
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1]){
  const file=new URL('../assets/data/app-data.json',import.meta.url),raw=await fs.readFile(file,'utf8');
  const after=applyReviewedDryingSources(JSON.parse(raw));
  assert.deepEqual(applyReviewedDryingSources(after),after);
  const next=JSON.stringify(after,null,2)+'\n';if(next!==raw)await fs.writeFile(file,next);
  console.log('Verified two drying input labels only; no identities, recipes, yields or saved data changed.');
}
