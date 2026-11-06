import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
const [auditPath,nativePath]=process.argv.slice(2);
assert.ok(auditPath&&nativePath);
const file='assets/data/app-data.json',bytes=fs.readFileSync(file);
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
assert.equal(hash(bytes),'b5d863817aab69b48335594674d066240bf219afbd4a4e73edf7f10becb0dcd3');
const data=JSON.parse(bytes),before=structuredClone(data);
const native=JSON.parse(fs.readFileSync(nativePath)),byId=new Map(native.map(i=>[i.id,i]));
const external=JSON.parse(fs.readFileSync(auditPath+'/getCraftingRecipes.response.json')).result.data;
const groups=JSON.parse(fs.readFileSync(auditPath+'/getMaterialGroups.response.json')).result.data;
const descriptions=[];
for(const [id,name,normalIds] of [[792,"Beast's Draught",[712,714,702]],[793,"Giant's Draught",[704,762,680]]]){
 assert.equal(data.processing.items[name],undefined);assert.equal(data.items[name],undefined);
 const nativeItem=byId.get(id);assert.equal(nativeItem.name,name);
 const text=nativeItem.description.replace(/<[^>]+>/g,'');
 assert.ok(text.includes('Simple Alchemy')&&text.includes('1:3'));
 const inputs=normalIds.map(itemId=>{
  const n=byId.get(itemId),rare=byId.get(itemId+1);
  assert.ok(text.includes(n.name+' x3'));
  assert.ok(n.description.includes(rare.name));
  assert.equal(+data.marketIds[n.name],itemId);assert.equal(+data.marketIds[rare.name],itemId+1);
  return {name:n.name,qty:3,options:[n.name,rare.name],substituteGroup:n.name,substituteRatios:{[n.name]:1,[rare.name]:1/3}};
 });
 inputs.push({name:'Tears of the Falling Moon',qty:1});
 const bulk=inputs.map(i=>({...structuredClone(i),qty:i.qty*10}));bulk.push({name:"Ibellab's Essence",qty:1});
 const source=external.filter(r=>r.productItemId===id);
 assert.equal(source.length,1);const r=source[0];
 assert.equal(r.processingType,'simple_alchemy');assert.equal(r.minProc,10);assert.equal(r.maxProc,10);
 const normalized=r.ingredients.map(i=>{
  if(i.type==='item')return [i.itemId,i.quantity];
  const g=groups.find(g=>g.groupId===i.groupId);assert.equal(g.items.length,2);
  const normal=g.items.find(i=>i.value===1),rare=g.items.find(i=>i.value===3);
  assert.ok(normalIds.includes(normal.itemId));assert.equal(rare.itemId,normal.itemId+1);
  return [normal.itemId,i.quantity];
 }).sort((a,b)=>a[0]-b[0]);
 assert.deepEqual(normalized,bulk.map(i=>[Number(data.marketIds[i.name]??data.marketNameIds[i.name.toLowerCase()]),i.qty]).sort((a,b)=>a[0]-b[0]));
 data.processing.items[name]={type:'processing',baseOutput:.4,group:'Processing - Simple Alchemy',method:'Simple Alchemy',marketId:String(id),outputMin:1,outputMax:1,ingredients:inputs,defaultVariantId:'standard',variants:[
  {id:'standard',label:'Standard',routeId:'standard',batchMultiplier:1,baseOutput:.4,outputMin:1,outputMax:1,ingredients:structuredClone(inputs)},
  {id:'standard-10x',label:'Standard',routeId:'standard',batchMultiplier:10,baseOutput:4,outputMin:10,outputMax:10,ingredients:bulk},
 ]};
 descriptions.push({id,name,description:text,bulkReference:r});
}
const reversed=structuredClone(data);for(const n of ["Beast's Draught","Giant's Draught"])delete reversed.processing.items[n];assert.deepEqual(reversed,before);
const backup=auditPath+'/resumed-catalog-before-missing-draughts.json';assert.ok(!fs.existsSync(backup));fs.copyFileSync(file,backup,fs.constants.COPYFILE_EXCL);
const output=Buffer.from(JSON.stringify(data,null,2)+'\n');fs.writeFileSync(file,output);
fs.writeFileSync('docs/reviewed-missing-draughts.json',JSON.stringify({date:'2026-11-03',beforeSha256:hash(bytes),afterSha256:hash(output),bytes:output.length,change:'Restore two absent standard draught recipes, each with exact 1:3 grade alternatives and a separately selectable 10x batch. No inferred EXP or probability.',sources:[{url:'https://bdocodex.com/us/mrecipe/1704/',scope:'Indexed PC standard Beast output one and ingredients, corroborating current exact client text.'},{url:'https://bdocodex.com/us/mrecipe/1705/',scope:'Indexed PC standard Giant output one and ingredients.'},{url:'https://bdolytics.com/api/trpc/calculator.getCraftingRecipes',scope:'2026-11-02 retained exact group/ingredient-matched bulk recipes: output ten.'},{url:'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=738',date:'2019-01-09',scope:'Official PC introduction of Ibellab bulk catalyst.'}],limitations:'Mix-elixir routes remain separate review candidates. Current client Ibellab description requires Alchemy Skilled 1 for bulk; neither Processing skill nor an undisclosed EXP value is substituted.',recipes:descriptions},null,2)+'\n');
console.log(JSON.stringify({sha256:hash(output),bytes:output.length,added:2}));
