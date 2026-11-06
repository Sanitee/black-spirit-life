// Exact reviewed mixed-elixir routes, not a generic elixir substitution rule.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
const [auditPath, nativePath] = process.argv.slice(2);
assert.ok(auditPath && nativePath);
const file = 'assets/data/app-data.json', bytes = fs.readFileSync(file);
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
assert.equal(hash(bytes), '5312d5da36565c25218e29269baea15b0e308f9123ce020d19c547d89b2b3b1c');
const data = JSON.parse(bytes), before = structuredClone(data);
const native = JSON.parse(fs.readFileSync(nativePath));
const byId = new Map(native.map(i => [i.id, i]));
const ledger = JSON.parse(fs.readFileSync(auditPath + '/research-reconciliation-ledger.json'));
const changes = [];
for (const [outputId, primaryId] of [[792, 766], [793, 769]]) {
  const name = byId.get(outputId).name, primary = byId.get(primaryId);
  const text = primary.description.replace(/<[^>]+>/g, '');
  assert.ok(text.includes(name) && text.includes('Simple Alchemy'));
  const first = byId.get(768).name, alternative = byId.get(770).name;
  for (const input of [primary.name, first, alternative, 'Tears of the Falling Moon']) {
    assert.ok(text.includes(input + ' x1'));
  }
  for (const id of [primaryId, 768, 770, 4925, 4986]) {
    assert.equal(Number(data.marketIds[byId.get(id).name]), id);
  }
  const recipe = data.processing.items[name];
  assert.equal(recipe.defaultVariantId, 'standard');
  assert.deepEqual(recipe.variants.map(v => v.id), ['standard', 'standard-10x']);
  for (const batch of [1, 10]) {
    const inputs = [
      {name: primary.name, qty: batch},
      {name: first, qty: batch, options: [first, alternative], substituteGroup: 'Mixed Elixir', substituteRatios: {[first]: 1, [alternative]: 1}},
      {name: 'Tears of the Falling Moon', qty: batch},
      ...(batch === 10 ? [{name: "Ibellab's Essence", qty: 1}] : []),
    ];
    const matchedKeys = [];
    for (const secondId of [768, 770]) {
      const expected = [[primaryId, batch], [secondId, batch], [4925, batch], ...(batch === 10 ? [[4986, 1]] : [])].sort((a,b) => a[0]-b[0]);
      const rows = ledger.filter(r => r.currentReview?.name === name && r.currentReview.category === 'native_processing_route_not_represented');
      const match = rows.filter(r => JSON.stringify(r.currentReview.relation.inputIdentities.map(i => [i.id, i.count]).sort((a,b) => a[0]-b[0])) === JSON.stringify(expected));
      assert.equal(match.length, 1); matchedKeys.push(match[0].key);
    }
    const variant = {id: batch === 1 ? 'mixed-elixirs' : 'mixed-elixirs-10x', label: 'Mixed elixirs', routeId: 'mixed-elixirs', batchMultiplier: batch, baseOutput: .4 * batch, outputMin: batch, outputMax: batch, ingredients: inputs};
    recipe.variants.push(variant);
    changes.push({name, outputId, batch, matchedKeys, variant, descriptionEvidence: text});
  }
}
const reverted = structuredClone(data);
for (const name of new Set(changes.map(r => r.name))) reverted.processing.items[name].variants = reverted.processing.items[name].variants.slice(0,2);
assert.deepEqual(reverted, before);
fs.copyFileSync(file, auditPath + '/resumed-catalog-before-mix-draughts.json', fs.constants.COPYFILE_EXCL);
const output = Buffer.from(JSON.stringify(data, null, 2) + '\n'); fs.writeFileSync(file, output);
fs.writeFileSync('docs/reviewed-mix-draughts.json', JSON.stringify({date:'2026-11-03', beforeSha256:hash(bytes), afterSha256:hash(output), bytes:output.length, changes, evidence:[
  {source:'Current installed PC item descriptions 766 and 769', scope:'Each explicitly documents both complete single-batch input sets and named output.'},
  {source:'https://bdocodex.com/us/mrecipe/1709/avd/?sl=1', scope:'PC single Beast recipe, output one.'},
  {source:'https://bdocodex.com/us/mrecipe/1711/', scope:'PC single Giant recipe, output one.'},
  {source:'https://bdocodex.com/us/mrecipe/4078/', scope:'PC Beast Thorn-Defense bulk, output ten.'},
  {source:'https://bdocodex.com/us/mrecipe/4079/', scope:'PC Beast Swiftness bulk, output ten, Alchemy Skilled 1.'},
  {source:'https://bdocodex.com/us/mrecipe/4086/', scope:'PC Giant Thorn-Defense bulk, output ten.'},
  {source:'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=738', date:'2019-01-09', scope:'Official PC Ibellab bulk support; current item 4986 retains 10x inputs plus one catalyst and Alchemy Skilled 1 requirement.'}
], limitations:'Single routes are expressly documented in current PC text, with native complete-input matches for all eight variants. Bulk corroborates the official Ibellab rule; no Global Lab/console source used. Do not infer how mixed elixirs are acquired from their n/a source text; no vendor source, crafting recipe, free cost, new XP or market-stock claim is added. Standard route remains default.'}, null, 2)+'\n');
console.log(JSON.stringify({sha256:hash(output),bytes:output.length,variants:changes.length,matchedFlags:changes.flatMap(r=>r.matchedKeys).length}));
