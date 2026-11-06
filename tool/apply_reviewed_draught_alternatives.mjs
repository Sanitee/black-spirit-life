// Audited, exact-identity substitutions only. No yield, default or input change.
import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
const [mappingPath, backupPath] = process.argv.slice(2);
assert.ok(mappingPath && backupPath, 'Supply reviewed mapping and new backup path');
const path = 'assets/data/app-data.json';
const bytes = fs.readFileSync(path);
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
assert.equal(hash(bytes), '65cd4d2eb852e5ee086f61f1f08dd696a5c6554ec7c775b077913266980d85ca');
assert.ok(!fs.existsSync(backupPath), 'Never overwrite baseline');
const before = JSON.parse(bytes), data = structuredClone(before);
const review = JSON.parse(fs.readFileSync(mappingPath, 'utf8'));
assert.equal(review.candidates.length, 63);
assert.equal(new Set(review.candidates.map(r => r.name)).size, 10);
for (const row of review.candidates) {
  assert.equal(row.mode, 'processing');
  assert.ok(['exact output description', 'Tears of the Falling Moon description'].includes(row.proof), row.proof);
  const identity = review.identities[row.group];
  assert.equal(identity.normalId, row.normalId);
  assert.equal(identity.rareId, row.rareId);
  assert.deepEqual(new Set([row.input, row.alternative]), new Set([identity.normal, identity.rare]));
  assert.equal(row.ratio, row.input === identity.normal ? 1 / 3 : 3);
  const recipe = data.processing.items[row.name];
  assert.equal(+recipe.marketId, row.id);
  const formula = row.variant === 'base' ? recipe : recipe.variants.find(v => v.id === row.variant);
  const ingredients = formula.ingredients.filter(i => i.name === row.input);
  assert.equal(ingredients.length, 1);
  const ingredient = ingredients[0];
  assert.deepEqual(ingredient, {name: row.input, qty: row.qty});
  Object.assign(ingredient, {
    options: [row.input, row.alternative],
    substituteGroup: row.group,
    substituteRatios: {[row.input]: 1, [row.alternative]: row.ratio},
  });
}
// Reversing only the reviewed fields must recover the complete original data.
const reversed = structuredClone(data);
for (const row of review.candidates) {
  const recipe = reversed.processing.items[row.name];
  const formula = row.variant === 'base' ? recipe : recipe.variants.find(v => v.id === row.variant);
  const ingredient = formula.ingredients.find(i => i.name === row.input);
  delete ingredient.options;
  delete ingredient.substituteGroup;
  delete ingredient.substituteRatios;
}
assert.deepEqual(reversed, before);
fs.copyFileSync(path, backupPath, fs.constants.COPYFILE_EXCL);
const output = Buffer.from(JSON.stringify(data, null, 2) + '\n');
fs.writeFileSync(path, output);
fs.writeFileSync('docs/reviewed-draught-alternatives.json', JSON.stringify({
  reviewedAt: '2026-11-03',
  scope: '63 missing ingredient alternatives in 10 processing recipes, including all single and bulk forms.',
  rules: 'One blue elixir replaces three of its green counterpart. Existing primary inputs, quantities, catalysts, outputs, methods and default variants are unchanged.',
  beforeSha256: hash(bytes), afterSha256: hash(output), bytes: output.length,
  sources: [
    {url: 'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=6315', date: '2024-07-25', scope: 'Official PC draught-family higher-grade 1:3 rule; regional historical corroboration, not a separate EU live test.'},
    {source: 'Installed PC client through 2026-10-31, extracted 2026-11-02', scope: 'Exact output descriptions or the exact Tears of the Falling Moon recipe list; exact normal/rare item identities. No raw manufacturing method or probability inference.'},
  ],
  limitations: 'Does not certify undisclosed success rates or EXP. Existing unknown EXP remains unknown. No high-grade ratios inferred for unrelated recipes.',
  identities: review.identities, changes: review.candidates,
}, null, 2) + '\n');
console.log(JSON.stringify({changes: 63, recipes: 10, sha256: hash(output), bytes: output.length}));
