import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export const TWILIGHT_PATCH_SOURCE =
  'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=19820';
export const TWILIGHT_PATCH_DATE = '2026-09-17';
export const TWILIGHT_SLOTS = ['Necklace', 'Earring', 'Ring', 'Belt'];

export function currentTwilightRecipe(existing, slot) {
  assert.ok(TWILIGHT_SLOTS.includes(slot));
  const ingredients = [{name: `Apeiron ${slot}`, qty: 1}];
  const variant = (id, label, input, output) => ({
    id, label, routeId: id, batchMultiplier: 1,
    baseOutput: output / 2.5, outputMin: output, outputMax: output,
    ingredients: [{name: input, qty: 1}],
  });
  return {
    ...existing,
    type: 'processing', baseOutput: 4,
    group: 'Reference - Destructive Conversion', method: 'Heating',
    outputMin: 10, outputMax: 10, ingredients,
    recipeRole: 'manual_conversion',
    defaultVariantId: 'from-apeiron',
    variants: [
      variant('from-apeiron', 'From Apeiron', `Apeiron ${slot}`, 10),
      {
        ...variant('from-causality-shardstone', 'From Causality Shardstone',
          `Causality Shardstone - ${slot}`, 5),
        sourceUrl: TWILIGHT_PATCH_SOURCE,
      },
    ],
  };
}

export function currentApeironReference(existing) {
  // Keep the same deterministic key order for fresh manifest records and
  // migrated catalog records: the legacy Edania importer compares JSON bytes.
  const identity = {type: 'processing', baseOutput: 1,
    group: 'Reference - Apeiron Accessories'};
  const result = {
    ...identity, ...existing, ...identity, ingredients: [],
    recipeRole: 'manual_conversion',
  };
  for (const field of ['method', 'outputMin', 'outputMax', 'variants',
    'defaultVariantId']) delete result[field];
  return result;
}

export function currentApeironAcquisition(existing, slot) {
  assert.ok(existing?.routes?.length, `Missing Apeiron ${slot} acquisition`);
  const result = structuredClone(existing);
  result.reviewedAt = TWILIGHT_PATCH_DATE;
  result.routes[0].summary =
    `Obtain Apeiron ${slot} from Inner Edania bosses and monsters, or buy it through the Central Market.`;
  for (const route of result.routes) {
    for (const source of route.sources ?? []) {
      source.supports = source.supports?.filter((support) => support !== 'processing');
    }
  }
  const sources = result.routes[0].sources;
  if (!sources.some((source) => source.url === TWILIGHT_PATCH_SOURCE)) {
    sources.push({
      title: 'Official September 17, 2026 update details',
      url: TWILIGHT_PATCH_SOURCE,
      supports: ['removed-heating-recipe'],
    });
  }
  return result;
}

// Compare whole semantic JSON trees after removing only the twelve approved
// records. Icons, IDs, weights, user defaults and unrelated recipes are intact.
export function assertTwilightPatchScope(before, after) {
  const withoutScope = (catalog) => {
    const copy = structuredClone(catalog);
    for (const slot of TWILIGHT_SLOTS) {
      delete copy.processing.items[`Twilight of the End - ${slot}`];
      delete copy.processing.items[`Apeiron ${slot}`];
      delete copy.acquisitionInfo[`Apeiron ${slot}`];
    }
    return copy;
  };
  assert.deepEqual(withoutScope(after), withoutScope(before),
    'Unrelated catalog data changed during the Twilight patch');
}

export function applyTwilightPatch(catalog) {
  const before = structuredClone(catalog);
  for (const slot of TWILIGHT_SLOTS) {
    const twilight = `Twilight of the End - ${slot}`;
    const apeiron = `Apeiron ${slot}`;
    assert.ok(catalog.processing.items[twilight], `Missing ${twilight}`);
    assert.ok(catalog.processing.items[apeiron], `Missing ${apeiron}`);
    const oldTwilight = catalog.processing.items[twilight];
    assert.deepEqual(oldTwilight.ingredients, [{name: apeiron, qty: 1}],
      `Unexpected existing recovery formula: ${twilight}`);
    assert.deepEqual([oldTwilight.baseOutput, oldTwilight.outputMin,
      oldTwilight.outputMax, oldTwilight.method, oldTwilight.recipeRole],
    [4, 10, 10, 'Heating', 'manual_conversion']);
    if (oldTwilight.variants != null) {
      assert.deepEqual(oldTwilight.variants,
        currentTwilightRecipe(oldTwilight, slot).variants,
        `Do not overwrite unreviewed recovery variants: ${twilight}`);
      assert.equal(oldTwilight.defaultVariantId, 'from-apeiron');
    }
    const oldApeiron = catalog.processing.items[apeiron];
    if (oldApeiron.ingredients.length > 0) {
      assert.deepEqual(oldApeiron.ingredients, [
        {name: twilight, qty: 10}, {name: 'Caphras Stone', qty: 10},
        {name: 'Magical Shard', qty: 10},
      ], `Do not overwrite an unreviewed Apeiron formula: ${apeiron}`);
      assert.deepEqual([oldApeiron.method, oldApeiron.outputMin,
        oldApeiron.outputMax], ['Heating', 1, 1]);
      assert.equal(oldApeiron.variants, undefined);
    } else {
      assert.equal(oldApeiron.recipeRole, 'manual_conversion');
      for (const field of ['method', 'outputMin', 'outputMax', 'variants']) {
        assert.equal(oldApeiron[field], undefined);
      }
    }
    catalog.processing.items[twilight] = currentTwilightRecipe(
      catalog.processing.items[twilight], slot);
    catalog.processing.items[apeiron] = currentApeironReference(
      catalog.processing.items[apeiron]);
    catalog.acquisitionInfo[apeiron] = currentApeironAcquisition(
      catalog.acquisitionInfo[apeiron], slot);
  }
  assertTwilightPatchScope(before, catalog);
  return catalog;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const catalogPath = fileURLToPath(new URL('../assets/data/app-data.json', import.meta.url));
  const original = await readFile(catalogPath, 'utf8');
  const output = JSON.stringify(applyTwilightPatch(JSON.parse(original)), null, 2) + '\n';
  if (process.argv.includes('--check')) {
    assert.equal(output, original, 'The September 17 Twilight patch is not current.');
    console.log('September 17 Twilight patch is deterministic and current.');
  } else {
    await writeFile(catalogPath, output, 'utf8');
    console.log('Applied exactly 8 scoped recipe and 4 Apeiron acquisition records.');
  }
}
