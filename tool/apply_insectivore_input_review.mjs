// Exact current PC item description + independently framed manufacturing inputs.
// Does not treat manufacturing success as a yield probability.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export function applyInsectivoreInputReview(catalog) {
  const before=structuredClone(catalog);
  const powder=catalog.processing.items['Insectivore Plant Powder'];
  assert.equal(+powder.marketId,5601);assert.equal(powder.method,'Grinding');
  assert.equal(powder.defaultVariantId,'flowers');assert.equal(powder.variants.length,2);
  const leaves=powder.variants.find(v=>v.id==='leaves-and-fragments');
  assert.ok(leaves&&['Leaves + Fragments','Leaves'].includes(leaves.label));
  const inputs=leaves.ingredients;
  assert.deepEqual(inputs[0],{name:'Insectivore Plant Leaf',qty:5});
  assert.ok(inputs.length===1||inputs.length===2);
  if(inputs.length===2)assert.deepEqual(inputs[1],{name:'Tree Spirit Stone Fragment',qty:10});
  // Keep the historical opaque ID so existing selected routes still resolve.
  leaves.label='Leaves';leaves.ingredients=[{name:'Insectivore Plant Leaf',qty:5}];
  // The matching Alchemy dependency must offer the same exact choices.
  const alchemyPowder=catalog.items['Insectivore Plant Powder'];
  assert.ok(alchemyPowder.variants==null||JSON.stringify(alchemyPowder.variants)===JSON.stringify(powder.variants));
  assert.ok(alchemyPowder.defaultVariantId==null||alchemyPowder.defaultVariantId==='flowers');
  alchemyPowder.variants=structuredClone(powder.variants);alchemyPowder.defaultVariantId='flowers';
  const sap=catalog.items['Insectivore Plant Sap'];
  assert.deepEqual(sap.ingredients,[{name:'Insectivore Plant Stalk',qty:5}]);
  const sapVariants=[{id:'stalks',label:'Stalks',ingredients:[{name:'Insectivore Plant Stalk',qty:5}]},{id:'roots',label:'Roots',ingredients:[{name:'Insectivore Plant Root',qty:5}]}];
  assert.ok(sap.variants==null||JSON.stringify(sap.variants)===JSON.stringify(sapVariants));
  assert.ok(sap.defaultVariantId==null||sap.defaultVariantId==='stalks');
  sap.variants=sapVariants;sap.defaultVariantId='stalks';
  const rootName='Insectivore Plant Root';
  assert.equal(+catalog.marketIds[rootName],5443);
  assert.equal(+catalog.marketNameIds[rootName.toLowerCase()],5443);
  assert.ok(catalog.processing.itemIcons[rootName]?.startsWith('data:image/'));
  assert.ok(catalog.itemIcons[rootName]==null||catalog.itemIcons[rootName]===catalog.processing.itemIcons[rootName]);
  catalog.itemIcons[rootName]=catalog.processing.itemIcons[rootName];
  assert.ok(catalog.itemWeightIds[rootName]==null||String(catalog.itemWeightIds[rootName])==='5443');
  assert.ok(catalog.itemWeightsLtById['5443']==null||catalog.itemWeightsLtById['5443']===0.1);
  catalog.itemWeightIds[rootName]='5443';catalog.itemWeightsLtById['5443']=0.1;
  // These exact normal-grade materials are marketable in current PC metadata.
  // Real catalog identities let all shared ingredient hosts resolve their stock;
  // do not relax fallback-name or unlisted-item request safeguards.
  for(const [name,id] of [['Insectivore Plant Leaf',5441],[rootName,5443]]){
    assert.equal(+catalog.marketIds[name],id);
    assert.equal(+catalog.marketNameIds[name.toLowerCase()],id);
    const record={type:'gathered',baseOutput:1,group:'Base Items',ingredients:[],marketId:String(id)};
    assert.ok(catalog.items[name]==null||JSON.stringify(catalog.items[name])===JSON.stringify(record));
    catalog.items[name]=record;
    assert.ok(catalog.processing.itemIcons[name]?.startsWith('data:image/'));
    assert.ok(catalog.itemIcons[name]==null||catalog.itemIcons[name]===catalog.processing.itemIcons[name]);
    catalog.itemIcons[name]=catalog.processing.itemIcons[name];
  }
  for(const[name,id]of[['Insectivore Plant Powder',5601],['Insectivore Plant Sap',5602]]){
    const item=catalog.items[name];assert.equal(+item.marketId,id);
    assert.equal(item.method,'Grinding');assert.equal(item.outputMin,1);assert.equal(item.outputMax,4);
    const names=catalog.verifiedItemInformationReview.estimatedOutputs;
    if(!names.includes(name))names.push(name);
  }
  const withoutScope=value=>{
    const c=structuredClone(value),v=c.processing.items['Insectivore Plant Powder'].variants.find(v=>v.id==='leaves-and-fragments');
    delete v.label;delete v.ingredients;
    for(const name of ['Insectivore Plant Powder','Insectivore Plant Sap']){delete c.items[name].variants;delete c.items[name].defaultVariantId;}
    delete c.itemIcons['Insectivore Plant Root'];delete c.itemWeightIds['Insectivore Plant Root'];delete c.itemWeightsLtById['5443'];
    delete c.itemIcons['Insectivore Plant Leaf'];delete c.items['Insectivore Plant Leaf'];delete c.items['Insectivore Plant Root'];
    c.verifiedItemInformationReview.estimatedOutputs=c.verifiedItemInformationReview.estimatedOutputs.filter(n=>!['Insectivore Plant Powder','Insectivore Plant Sap'].includes(n));
    return c;
  };
  assert.deepEqual(withoutScope(catalog),withoutScope(before),'Unrelated data changed');
  return catalog;
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const file=new URL('../assets/data/app-data.json',import.meta.url),before=await readFile(file,'utf8');
  const after=JSON.stringify(applyInsectivoreInputReview(JSON.parse(before)),null,2)+'\n';
  if(process.argv.includes('--check'))assert.equal(after,before);
  else await writeFile(file,after,'utf8');
  console.log('Insectivore leaves input corrected; stable route ID and all numerical yield assumptions retained. Both output models explicitly estimated.');
}
