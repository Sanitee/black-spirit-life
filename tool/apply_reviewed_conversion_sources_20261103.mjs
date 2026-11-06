import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';

export const melodySource = 'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=4655&countryType=en-US';
export const seaBoxSource = 'https://www.naeu.playblackdesert.com/en-us/News/Detail?countryType=en-us&groupContentNo=9334';
export const seaBoxExchangeSource = 'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=9683&countryType=en-US';
export function applyReviewedConversionSources(catalog) {
  const result = structuredClone(catalog);
  const melody = result.acquisitionInfo['Melody of the Stars'];
  assert.equal(melody.itemId, 8196);
  assert.equal(melody.canonicalName, 'Melody of the Stars');
  assert.equal(melody.routes[0].kind, 'manual_conversion');
  melody.reviewedAt = '2026-11-03';
  melody.routes[0].summary = 'Heating · Eligible blue-grade accessories: PRI gives 1, DUO 5, TRI 25. The accessory is consumed.';
  if (!melody.routes[0].sources.some(s => s.url === melodySource)) {
    melody.routes[0].sources.push({title:'Official NA/EU January 11, 2023 update',url:melodySource,supports:['method','enhancement-restrictions','output-quantity']});
  }
  for (const [name,id] of [['Origin of Margoria',8108],['Origin of Rusalka',821169]]) {
    const record = result.acquisitionInfo[name];
    assert.equal(record.itemId,id);
    assert.equal(record.canonicalName,name);
    record.reviewedAt = '2026-11-03';
    const summary = 'Deep Sea Crystal Box · Blue Battlefield rewards or 30 Wavelit Crystals (1 box/week, Manage Currency). Chance of 1–3.';
    // Supersede only this tool's earlier, incomplete wording.
    record.routes = record.routes.filter(r => r.summary !== 'Deep Sea Crystal Box · Blue Battlefield reward (chance of 1–3).');
    if (!record.routes.some(r => r.summary === summary)) record.routes.push({
      kind:'container',summary,availability:'permanent',confidence:'high',
      sources:[
        {title:'Official NA/EU November 20, 2025 Blue Battlefield rewards',url:seaBoxSource,supports:['container-content','reward-source','chance-not-guaranteed']},
        {title:'Official NA/EU February 5, 2026 reward update',url:seaBoxExchangeSource,supports:['current-rewards','wavelit-exchange-cost','weekly-limit']},
      ],
    });
  }
  const omit = value => { const copy=structuredClone(value); for(const name of ['Melody of the Stars','Origin of Margoria','Origin of Rusalka']) delete copy.acquisitionInfo[name]; return copy; };
  assert.deepEqual(omit(result),omit(catalog),'Only these three acquisition records may change; no recipes, IDs, icons or calculations.');
  return result;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const file = new URL('../assets/data/app-data.json',import.meta.url);
  const raw = await fs.readFile(file,'utf8');
  const before = JSON.parse(raw);
  const after = applyReviewedConversionSources(before);
  assert.deepEqual(applyReviewedConversionSources(after),after,'Must be idempotent');
  const next = JSON.stringify(after,null,2)+'\n';
  if(next !== raw) await fs.writeFile(file,next);
  console.log('Verified three source records only; conversions remain manual and formulas unchanged.');
}
