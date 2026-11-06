// Exact four identities only; preserves all historical and other active weights.
import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
const root=new URL('../',import.meta.url),path=new URL('assets/data/app-data.json',root);
const before=fs.readFileSync(path);
assert.equal(crypto.createHash('sha256').update(before).digest('hex'),'f74ebf4a38d50f86f0c827d09c24a640c1f9198823d16b21d526336500c709f6');
const data=JSON.parse(before);
const rows=[
 [766,'[Mix] EXP-Reaper Elixir'],
 [768,'[Mix] Swiftness-Wind-Spell Elixir'],
 [769,'[Mix] Manhunt-Rage Elixir'],
 [770,'[Mix] Thorn-Defense Elixir'],
];
assert.equal(Object.keys(data.itemWeightIds).length,1754);
assert.equal(Object.keys(data.itemWeightsLtById).length,1753);
for(const [id,name] of rows){
 assert.equal(Number(data.marketIds[name]),id);
 assert.equal(data.itemWeightIds[name],undefined);
 assert.equal(data.itemWeightsLtById[id],undefined);
 data.itemWeightIds[name]=String(id);data.itemWeightsLtById[id]=0.2;
}
const out=JSON.stringify(data,null,2)+'\n';fs.writeFileSync(path,out);
console.log(JSON.stringify({sha256:crypto.createHash('sha256').update(out).digest('hex'),bytes:Buffer.byteLength(out),added:rows.length,scope:'Four exact current PC item weights,0.2LT each; no formula, market or saved-data changes.'}));
