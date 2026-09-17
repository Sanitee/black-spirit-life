import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {
  applyTwilightPatch, assertTwilightPatchScope, TWILIGHT_PATCH_SOURCE,
  TWILIGHT_SLOTS,
} from '../../tool/apply_twilight_patch_20260917.mjs';
import {
  EDANIA_PART_II_PROCESSING_RECIPES, EDANIA_PART_II_ACQUISITION_INFO,
} from '../../tool/edania_part_ii_catalog_manifest.mjs';

const catalog = JSON.parse(await readFile(
  new URL('../../assets/data/app-data.json', import.meta.url), 'utf8'));

function previousCatalog() {
  const previous = structuredClone(catalog);
  for (const slot of TWILIGHT_SLOTS) {
    const twilight = previous.processing.items[`Twilight of the End - ${slot}`];
    delete twilight.variants;
    delete twilight.defaultVariantId;
    const apeiron = previous.processing.items[`Apeiron ${slot}`];
    delete apeiron.recipeRole;
    Object.assign(apeiron, {
      baseOutput: 0.4, group: 'Processing - Heating', method: 'Heating',
      outputMin: 1, outputMax: 1,
      ingredients: [
        {name: `Twilight of the End - ${slot}`, qty: 10},
        {name: 'Caphras Stone', qty: 10}, {name: 'Magical Shard', qty: 10},
      ],
    });
    const acquisition = previous.acquisitionInfo[`Apeiron ${slot}`];
    acquisition.reviewedAt = '2026-08-15';
    acquisition.routes[0].summary =
      `Obtain Apeiron ${slot} from Inner Edania bosses and monsters, craft it by Heating, or buy it through the Central Market.`;
    acquisition.routes[0].sources = acquisition.routes[0].sources.filter(
      (source) => source.url !== TWILIGHT_PATCH_SOURCE);
    acquisition.routes[0].sources[0].supports.push('processing');
  }
  return previous;
}

test('patch changes only the eight recipe and four acquisition records', () => {
  const before = previousCatalog();
  const result = applyTwilightPatch(structuredClone(before));
  assertTwilightPatchScope(before, result);
  assert.deepEqual(result, catalog);
  for (const slot of TWILIGHT_SLOTS) {
    assert.notDeepEqual(before.processing.items[`Twilight of the End - ${slot}`],
      result.processing.items[`Twilight of the End - ${slot}`]);
    assert.notDeepEqual(before.processing.items[`Apeiron ${slot}`],
      result.processing.items[`Apeiron ${slot}`]);
    assert.notDeepEqual(before.acquisitionInfo[`Apeiron ${slot}`],
      result.acquisitionInfo[`Apeiron ${slot}`]);
  }
});

test('patch is idempotent and retains icons, identities, weights and defaults', () => {
  const result = applyTwilightPatch(structuredClone(catalog));
  assert.deepEqual(result, catalog);
  const changed = structuredClone(result);
  changed.defaults.inv = {Salt: 1};
  assert.throws(() => assertTwilightPatchScope(catalog, changed),
    /Unrelated catalog data/);
});

test('reference recovery routes keep separate identity and exact fixed outputs', () => {
  for (const slot of TWILIGHT_SLOTS) {
    const recipe = catalog.processing.items[`Twilight of the End - ${slot}`];
    assert.equal(recipe.recipeRole, 'manual_conversion');
    assert.equal(recipe.defaultVariantId, 'from-apeiron');
    assert.equal(recipe.method, 'Heating');
    assert.deepEqual(recipe.variants.map(({id, label, routeId}) => ({id, label, routeId})), [
      {id: 'from-apeiron', label: 'From Apeiron', routeId: 'from-apeiron'},
      {id: 'from-causality-shardstone', label: 'From Causality Shardstone',
        routeId: 'from-causality-shardstone'},
    ]);
    const [accessory, shardstone] = recipe.variants;
    assert.deepEqual(accessory.ingredients, [{name: `Apeiron ${slot}`, qty: 1}]);
    assert.deepEqual([accessory.outputMin, accessory.outputMax], [10, 10]);
    assert.deepEqual(shardstone.ingredients,
      [{name: `Causality Shardstone - ${slot}`, qty: 1}]);
    assert.deepEqual([shardstone.outputMin, shardstone.outputMax], [5, 5]);
    assert.equal(shardstone.sourceUrl, TWILIGHT_PATCH_SOURCE);
  }
});

test('original Edania manifest cannot resurrect the removed Apeiron formulas', () => {
  for (const slot of TWILIGHT_SLOTS) {
    const name = `Apeiron ${slot}`;
    assert.deepEqual(EDANIA_PART_II_PROCESSING_RECIPES[name],
      catalog.processing.items[name]);
    assert.equal(JSON.stringify(EDANIA_PART_II_PROCESSING_RECIPES[name]),
      JSON.stringify(catalog.processing.items[name]),
      'Legacy Edania upsert requires deterministic property order, not just values');
    assert.deepEqual(EDANIA_PART_II_ACQUISITION_INFO[name],
      catalog.acquisitionInfo[name]);
    const item = catalog.processing.items[name];
    assert.equal(item.recipeRole, 'manual_conversion');
    assert.deepEqual(item.ingredients, []);
    for (const field of ['method', 'outputMin', 'outputMax', 'variants']) {
      assert.equal(item[field], undefined);
    }
    assert.match(catalog.acquisitionInfo[name].routes[0].summary, /Central Market/);
    assert.doesNotMatch(catalog.acquisitionInfo[name].routes[0].summary, /Heating/);
  }
});

test('a future different formula or recovery variant needs another review', () => {
  const changedFormula = previousCatalog();
  changedFormula.processing.items['Apeiron Ring'].ingredients[0].qty = 7;
  assert.throws(() => applyTwilightPatch(changedFormula), /unreviewed Apeiron formula/);
  const changedRoute = structuredClone(catalog);
  changedRoute.processing.items['Twilight of the End - Belt'].variants[1].outputMax = 6;
  assert.throws(() => applyTwilightPatch(changedRoute), /unreviewed recovery variants/);
});

// Optional real accepted-baseline comparison for this request's release audit;
// normal test runs remain portable and never read personal saved data.
if (process.env.TWILIGHT_BASELINE_CATALOG) {
  test('accepted baseline differs at exactly the twelve approved records', async () => {
    const baseline = JSON.parse(await readFile(process.env.TWILIGHT_BASELINE_CATALOG, 'utf8'));
    assertTwilightPatchScope(baseline, catalog);
    assert.deepEqual(applyTwilightPatch(structuredClone(baseline)), catalog);
  });
}
