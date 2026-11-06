// Reviewed corrections, not a bulk import. Preserve unrelated catalog content.
// Provenance and deliberately unresolved findings: docs/verified-item-information.json.
import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
const catalogPath = 'assets/data/app-data.json';
const raw = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));
const modes = {alchemy: raw.items, cooking: raw.cooking.items, processing: raw.processing.items};
const corrections = [];
function recipe(mode, name, id) {
  const value = modes[mode][name];
  assert.equal(String(value?.marketId), String(id), `Identity: ${mode}/${name}`);
  return value;
}
function quantity(mode, name, id, input, before, after) {
  const value = recipe(mode,name,id);
  const row = value.ingredients.find(x => x.name === input);
  assert.ok(row && [before,after].includes(row.qty), `Quantity guard: ${name}/${input}`);
  row.qty = after;
  corrections.push({mode,name,input,quantity:after});
}
quantity('processing','Gem of Twilight',767077,'Caphras Stone',1,20000);
quantity('processing','Sunset Glow Crystal',8179,'Caphras Stone',1,10000);
quantity('alchemy','Defense Elixir',716,'Ash Sap',5,6);
quantity('cooking','Soft Bread',9260,'Corn Dough',3,6);
for(const [name,id,input,qty] of [['Elixir of Perforation',680,'Pine Sap',5],['Looney Elixir',777,'Powder of Flame',3]]) {
  const value = recipe('alchemy',name,id);
  const row = value.ingredients.find(x=>x.name===input);
  if(row) assert.equal(row.qty,qty); else value.ingredients.push({name:input,qty});
  corrections.push({mode:'alchemy',name,input,quantity:qty});
}
const sirutteok = recipe('cooking','Red Bean Sirutteok',820849);
const sugar = sirutteok.ingredients.find(x=>['Salt','Sugar'].includes(x.name));
assert.equal(sugar.qty,1); sugar.name='Sugar';
corrections.push({mode:'cooking',name:'Red Bean Sirutteok',input:'Sugar',quantity:1,replaces:'Salt'});
for(const [level,id] of [['I',8826],['II',8827],['III',8828],['IV',8829]]) {
  const name=`Resplendent Boss Armor Reform Stone ${level}`;
  const value=recipe('processing',name,id);
  const crystal=value.ingredients.find(x=>['Concentrated Giath Crystal','Concentrated Boss Crystal'].includes(x.name));
  assert.equal(crystal.qty,60); crystal.name='Concentrated Boss Crystal';
  if(level==='IV') { const gem=value.ingredients.find(x=>['Rough Ruby','Rough Diamond'].includes(x.name)); assert.equal(gem.qty,1); gem.name='Rough Diamond'; }
  corrections.push({mode:'processing',name,inputs:value.ingredients});
}
// Missing bounds on an otherwise identical standard processing recipe are not
// a second recipe. Copy only the reviewed bounds, without altering its yield.
const repeated = ['Barley Dough','Barley Flour','Butter','Corn Dough','Corn Flour','Cream','Potato Dough','Potato Flour','Sweet Potato Dough','Sweet Potato Flour','Wheat Dough','Wheat Flour'];
for(const name of repeated) {
  const processing=modes.processing[name], cooking=modes.cooking[name];
  assert.equal(processing.baseOutput,cooking.baseOutput);
  assert.equal(processing.outputMin,1); assert.equal(processing.outputMax,4);
  cooking.outputMin=1; cooking.outputMax=4;
  if(name.endsWith('Flour')) cooking.ingredients=structuredClone(processing.ingredients);
}
Object.assign(modes.processing['Melted Iron Shard'],{outputMin:1,outputMax:4});
// These two catalogs describe the same rice grinding route. Retain all three
// explicitly recorded grade choices when displaying/activating either copy.
assert.equal(modes.cooking['Rice Flour'].marketId,modes.processing['Rice Flour'].marketId);
modes.cooking['Rice Flour'].ingredients=structuredClone(modes.processing['Rice Flour'].ingredients);
// The imported Codex 'base product 1' is not a measured fixed proc rate.
// Retain the existing 1–4 / 2.5-average processing model from the Cooking copy,
// visibly marked as estimated, rather than presenting conflicting recipes.
// Exact input grade routes are corroborated by the PC client recipe snapshot.
for (const mode of ['cooking','processing']) {
  Object.assign(recipe(mode,'Red Pepper Powder',9077), {
    baseOutput:1,outputMin:1,outputMax:4,
    ingredients:[{name:'Hot Pepper',qty:5,options:['Hot Pepper','High-Quality Hot Pepper','Special Hot Pepper'],substituteGroup:'Hot Pepper',substituteRatios:{'Hot Pepper':1,'High-Quality Hot Pepper':0.4,'Special Hot Pepper':0.2}}],
  });
}
for(const [name,id,oldId] of [['Oatmeal',9261,9264],['Refined Oatmeal',9276,9265],['Organic Feed',54018,9603]]) {
  assert.equal(String(modes.cooking[name].marketId),String(id));
  for(const [map,key] of [[raw.marketIds,name],[raw.marketNameIds,name.toLowerCase()]]) {
    assert.ok([id,oldId].includes(+map[key])); map[key]=id;
  }
}
for (const [name,id,oldId] of [['Caphras Essence',821259,65582],['Daybreak Blue Coral',4479,1216],['Good Feed',54017,36999],['Special Honey Jar',54032,39240]]) {
  assert.equal(+raw.marketIds[name],id);
  assert.ok([oldId,id].includes(+raw.marketNameIds[name.toLowerCase()]));
  raw.marketNameIds[name.toLowerCase()]=id;
}
// Exact consumable and Manage Currency identities, not same-named knowledge
// items or superseded currencies. Exchanges already uses these reviewed IDs.
for (const [name,id,oldId] of [["Dark Spirit's Greed",767887,721023],['Millennial Wild Ginseng',820152,39154]]) {
  assert.ok([oldId,id].includes(+raw.marketNameIds[name.toLowerCase()]));
  assert.ok(raw.marketIds[name] == null || +raw.marketIds[name] === id);
  raw.marketNameIds[name.toLowerCase()]=id;
  raw.marketIds[name]=String(id);
}
for(const [name,id,note] of [
  ['High-Quality Hot Pepper',7327,'Garden · Grow High-Quality Hot Pepper'],
  ['Special Hot Pepper',7339,'Garden · Grow Special Hot Pepper'],
  ['Tiger Blood',6356,'Hunt tigers and collect their blood with a Fluid Collector.'],
  ['Pile of Sunrise Herbs',5421,'Gather Wild Herbs with bare hands or a hoe (depends on Gathering level).'],
]) {
  for(const entries of Object.values(modes)) if(entries[name]) {
    assert.equal(+(entries[name].marketId??raw.marketIds[name]),id);
    entries[name].sourceNote=note;
  }
}
for(const [name,id] of [['High-Quality Hot Pepper',7327],['Special Hot Pepper',7339]]) {
  assert.equal(+raw.marketIds[name],id);
  raw.itemWeightIds[name]=String(id); raw.itemWeightsLtById[id]=0.1;
}
raw.verifiedItemInformationReview={date:'2026-11-02',corrections,normalizedDuplicateBounds:[...repeated,'Melted Iron Shard'],canonicalGradeOptions:['Rice Flour','Red Pepper Powder'],estimatedOutputs:['Red Pepper Powder'],fallbackIdentities:['Oatmeal','Refined Oatmeal','Organic Feed','Caphras Essence','Daybreak Blue Coral','Good Feed','Special Honey Jar'],status:'Verified corrections only; remaining audit findings are not certified current.'};
raw.verifiedItemInformationReview.fallbackIdentities.push("Dark Spirit's Greed",'Millennial Wild Ginseng');
const output=JSON.stringify(raw,null,2)+'\n';
fs.writeFileSync(catalogPath,output);
const hash=crypto.createHash('sha256').update(output).digest('hex');
const parserPath='lib/data/catalog/bundled_catalog_parser.dart';
let parser=fs.readFileSync(parserPath,'utf8');
parser=parser.replace(/(const productionCatalogSha256 =\s*)'[^']+'/,`$1'${hash}'`).replace(/const productionCatalogByteCount = \d+;/,`const productionCatalogByteCount = ${Buffer.byteLength(output)};`)
  .replace(/'alchemy ingredients': 470/,'\'alchemy ingredients\': 472').replace(/'total ingredients': 2849/,'\'total ingredients\': 2851');
fs.writeFileSync(parserPath,parser);
console.log(JSON.stringify({hash,bytes:Buffer.byteLength(output),corrections:corrections.length}));
