import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {additions} from '../../tool/item_source_additions_manifest.mjs';

test('Jangdok source manifest matches the projected Dart registry exactly',()=>{
  const dart=fs.readFileSync(new URL('../../lib/features/recipe_book/reviewed_item_source_additions.dart',import.meta.url),'utf8');
  for(const id of [9073,9075,9076,9078]){
    const row=additions.filter(r=>r.id===id);assert.equal(row.length,1);
    const block=dart.match(new RegExp('  '+id+': \\(([\\s\\S]*?)\\n  \\),'))?.[1];assert(block);
    assert(block.includes(JSON.stringify(row[0].lines[0])));
    assert(row[0].lines[0].endsWith('(Donghae / Seoul)'));
    assert(!row[0].lines[0].includes('Jangdokdae'));
    assert(row[0].evidence.includes('jangdokLocations20261104'));
  }
  assert(additions.find(r=>r.id===9075).lines[0].includes('Extra from Soybean Paste'));
});

test('the location hint matches retained workshop houses in both regions',()=>{
  const data=JSON.parse(fs.readFileSync(new URL('../../packages/bdo_map_core/assets/data/lodging_houses.json',import.meta.url),'utf8'));
  const names=data.towns.filter(t=>t.houses.some(h=>h.usages.some(u=>u.typeId===2009&&u.label==='Jangdok Platform'))).map(t=>t.name);
  assert.deepEqual(names,['Dalbeol Village',"Nampo's Moodle Village","Nopsae's Byeot County",'Yukjo Street','Godu Village','Bukpo']);
});
