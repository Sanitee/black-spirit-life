import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import {additions, sources, reviewedAt, reviewedNameAliases} from './item_source_additions_manifest.mjs';
import {reviewedDescriptionSources} from './item_source_description_rules.mjs';

// Explicit read-only inputs; raw game exports stay outside the repository.
// stdout is generated Dart; the optional audit is generated evidence, not app data.
const [clientPath, recipesPath, reportPath, auditPath, dartPath] = process.argv.slice(2);
const clientBytes = await fs.readFile(clientPath);
const hash = b => crypto.createHash('sha256').update(b).digest('hex').toUpperCase();
if (hash(clientBytes) !== sources.clientItems.sha256) throw Error('Wrong client snapshot');
const client = new Map(JSON.parse(clientBytes).map(x => [x.id,x]));
const recipeBytes = await fs.readFile(recipesPath);
const recipes = JSON.parse(recipeBytes);
const report = JSON.parse(await fs.readFile(reportPath,'utf8'));
const catalog = JSON.parse(await fs.readFile('assets/data/app-data.json','utf8'));
const folded = x => x.toLowerCase().replaceAll('-', ' ').replace(/\s+/g,' ').trim();
const marketSource = await fs.readFile('lib/data/opportunities/market_eligibility.dart','utf8');
const nonMarket = new Set([...marketSource.matchAll(/^  '(\d+)',/gm)].map(x=>+x[1]));
const archiveSource = await fs.readFile('lib/domain/catalog/temporarily_archived_items.dart','utf8');
const archived = new Set([...archiveSource.matchAll(/^  '(\d+)':/gm)].map(x=>+x[1]));
const matching = row => client.has(+row.id) && (folded(client.get(+row.id).name)===folded(row.name) ||
  reviewedNameAliases.some(alias => alias.id===+row.id && alias.name===row.name && alias.nativeName===client.get(+row.id).name));
// Prefer reviewed current mappings over a stale ID in the earlier audit report.
// Disagreements between current maps still fail the eligibility guard below.
const reportItems = report.items.map(row => {
  const ids=[...new Set([catalog.marketIds[row.name],catalog.marketNameIds[row.name.toLowerCase()]].filter(x=>x!=null).map(Number))];
  return ids.length===1 ? {...row,id:String(ids[0])} : row;
});
const maps = new Map();
const add = (id,name,lines,evidence) => {
  if(archived.has(id))throw Error('Archived item '+name);
  const old=maps.get(id)??{id,name,lines:[],evidence:[]};
  for(const l of lines)if(!old.lines.includes(l))old.lines.push(l);
  for(const e of evidence)if(!old.evidence.includes(e))old.evidence.push(e);
  maps.set(id,old);
};
for(const record of additions){
  if(!client.has(record.id)||folded(client.get(record.id).name)!==folded(record.name))throw Error('Identity mismatch '+JSON.stringify(record));
  add(record.id,record.name,record.lines,record.evidence);
}
// A known item ID alone is NOT market eligibility. Require positive client flag,
// matching name, current catalog mapping, and the existing exclusions. Never infer
// stock, price or vendor availability. Don't revive legacy/event-only guidance.
for(const row of reportItems){
  const id=+row.id, item=client.get(id);
  const original=row.after.join(' ');
  const catalogIds = [catalog.marketIds[row.name], catalog.marketNameIds[row.name.toLowerCase()]]
    .filter(value => value != null).map(Number);
  const active=!row.archived&&!archived.has(id)&&!row.name.startsWith('[Event]')&&
    !/\b(legacy|no longer|unavailable|removed|disabled|old copies)\b/i.test(original)&&
    !['Black Stone (Armor)','Black Stone (Weapon)'].includes(row.name);
  const marketVerified=active&&matching(row)&&item.marketable===true&&catalogIds.length>0&&catalogIds.every(value=>value===id)&&!nonMarket.has(id);
  if(marketVerified&&!/market/i.test(original))add(id,row.name,['Central Market · When in stock'],['clientItems','bundledMarketIdentity']);
  // Use exact worker recipe outputs/stations, never descriptive flavor text.
  // Keep the scope on sparse reference cards; don't duplicate full recipes.
  if(active&&matching(row)){
    const descriptions = reviewedDescriptionSources(item, catalog).filter(line =>
      !row.after.includes(line) && !(line.startsWith('Garden · ') && /garden|harvest|farming/i.test(original)) &&
      !(line.startsWith('Gather · ') && /\bgather|collect|underwater|hoe\b/i.test(original)));
    if (descriptions.length) add(id,row.name,descriptions,['clientItems','reviewedDescriptionRules']);
    if(row.after.length>1||row.recipes!==0)continue;
    const stations=[...new Set(recipes.filter(r=>r.output===`urn::item:${id}`&&r.type==='HOUSE').map(r=>r.station))];
    for(const station of stations){
      if(station==='Jangdok Platform'||!station||/workshop|worker|jeweler/i.test(original))continue;
      add(id,row.name,[`Workers · ${station}`],['clientRecipes']);
    }
  }
}
const records=[...maps.values()].map(r=>({...r,
  name:client.get(r.id).name,
  aliases:reviewedNameAliases.filter(alias=>alias.id===r.id && alias.nativeName===client.get(r.id).name).map(alias=>alias.name),
})).sort((a,b)=>a.id-b.id);
const audit={reviewedAt,sources,clientRecipesSha256:hash(recipeBytes),catalogSha256:hash(await fs.readFile('assets/data/app-data.json')),records,
  items:reportItems.map(row=>({name:row.name,id:row.id,previousLines:row.after,recipeCount:row.recipes,
    singleSourceCandidate:!row.archived&&row.after.length<=1&&row.recipes===0,
    clientIdentityMatched:matching(row),clientMarketable:matching(row)?client.get(+row.id).marketable===true:null,
    alreadyHasWorkerSource:row.after.some(l=>l.startsWith('Workers · ')),
    additions:matching(row)?maps.get(+row.id)?.lines??[]:[],
    disposition:row.archived?'archived; unchanged':matching(row)&&maps.has(+row.id)?'verified additions':matching(row)?'cross-checked snapshot; no verified addition':'identity/source unresolved; unchanged',
  })),
  limitations:['Systematic cross-check of all existing reference entries; not a fresh independent verification of every possible route.',
    'Client metadata and worker recipes are the hash-verified 2026-09-10 snapshot. Current bundled exclusions and later item identities take precedence.',
    'A missing addition is not proof of a sole source. Unresolved identities, legacy items and additional drop/quest locations remain explicit review gaps.',
    'No live stock, exact proc rates, event rewards, or new calculation routes are inferred.'],
};
if(auditPath)await fs.writeFile(auditPath,JSON.stringify(audit,null,2));
const quote=s=>JSON.stringify(s).replaceAll('$','\\$');
const generated = ['// Generated by tool/review_item_source_additions.mjs. Reference copy only.\n// Review/provenance: docs/broader-item-sources.json and docs/verified-item-information.json. Do not infer other grades.\nimport \'../../domain/catalog/temporarily_archived_items.dart\';\n\nfinal reviewedItemSourceAdditions = Map<int, ({String name, List<String> aliases, List<String> lines})>.unmodifiable({\n  for (final entry in _reviewedItemSourceAdditions.entries)\n    if (!isTemporarilyArchivedMarketItemId(\'${entry.key}\')) entry.key: entry.value,\n});\n\nconst _reviewedItemSourceAdditions = <int, ({String name, List<String> aliases, List<String> lines})>{',
  ...records.map(r=>`  ${r.id}: (name: ${quote(r.name)}, aliases: [${r.aliases.map(quote).join(', ')}], lines: [${r.lines.map(quote).join(', ')}]),`), '};', ''].join('\n');
if (dartPath) await fs.writeFile(dartPath, generated); else console.log(generated);
