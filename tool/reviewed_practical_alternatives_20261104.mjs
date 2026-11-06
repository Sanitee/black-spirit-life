import assert from 'node:assert/strict';

// Exact current PC descriptions and official NA/EU material tables. This is
// deliberately not a generic grade-conversion rule or a new yield model.
export const practicalAlternatives = [
  ...[['Destruction', '45503'], ['Protection', '45513'], ['Life', '45514']].map(([suffix, id]) => ({
    name: `Khan's Heart: ${suffix}`, id,
    primary: "Khan's Concentrated Magic", alternative: "Khan's Dim Magic",
    quantity: 1, ratio: 3, group: "Khan's Concentrated Magic",
  })),
  {name: 'Sturdy Whale Tendon Elixir', id: '1361', primary: 'Tough Whale Tendon Elixir', alternative: 'Whale Tendon Elixir', quantity: 1, ratio: 3, group: 'Whale Tendon Elixir'},
  {name: 'Sturdy Whale Tendon Potion', id: '1360', primary: 'Whale Tendon Potion', alternative: 'Superior Whale Tendon Potion', quantity: 3, ratio: 1 / 3, group: 'Whale Tendon Potion'},
  {name: 'Fiery Celerity Draught', id: '757031', primary: 'Unbridled Celerity Draught', alternative: 'Celerity Draught', quantity: 2, ratio: 2, group: 'Celerity Draught'},
];

export const immortalConversions = [
  {name: 'Immortal: Perfume of Envy', id: '1412', input: 'Immortal: Perfume of Courage'},
  {name: 'Immortal: Perfume of Tenacity', id: '1414', input: 'Immortal: Perfume of Deep Sea'},
];

export function applyPracticalAlternatives(original) {
  const result = structuredClone(original);
  for (const row of practicalAlternatives) {
    const recipe = result.processing.items[row.name];
    assert.equal(recipe.marketId, row.id);
    assert.equal(recipe.method, 'Simple Alchemy');
    for (const formula of [recipe, ...(recipe.variants ?? [])]) {
      const batch = formula.batchMultiplier ?? 1;
      assert.equal(formula.outputMin, batch);
      assert.equal(formula.outputMax, batch);
      const input = formula.ingredients.find(i => i.name === row.primary);
      assert(input);
      assert.equal(input.qty, row.quantity * batch);
      const expected = {
        name: row.primary, qty: input.qty,
        options: [row.primary, row.alternative], substituteGroup: row.group,
        substituteRatios: {[row.primary]: 1, [row.alternative]: row.ratio},
      };
      assert([JSON.stringify({name: row.primary, qty: input.qty}), JSON.stringify(expected)].includes(JSON.stringify(input)), 'Unknown preexisting alternatives');
      Object.assign(input, expected);
    }
  }
  for (const row of immortalConversions) {
    const recipe = result.processing.items[row.name];
    assert.equal(recipe.marketId, row.id);
    assert.equal(recipe.method, 'Simple Alchemy');
    assert.equal(recipe.defaultVariantId, 'standard');
    assert.equal(recipe.outputMin, 1);
    assert.equal(recipe.outputMax, 1);
    const added = [1, 10].map(batch => ({
      id: batch === 1 ? 'immortal-perfume' : 'immortal-perfume-10x',
      label: 'Immortal perfume', routeId: 'immortal-perfume', batchMultiplier: batch,
      baseOutput: batch * 0.4, outputMin: batch, outputMax: batch,
      ingredients: [
        {name: row.input, qty: batch},
        {name: 'Shining Powder', qty: 3 * batch},
        {name: 'Caphras Essence', qty: 10 * batch},
        ...(batch === 10 ? [{name: "Ibellab's Essence", qty: 1}] : []),
      ],
    }));
    assert([2, 4].includes(recipe.variants.length));
    assert.deepEqual(recipe.variants.slice(0, 2).map(v => v.id), ['standard', 'standard-10x']);
    if(recipe.variants.length === 4) assert.deepEqual(recipe.variants.slice(2), added);
    else recipe.variants.push(...added);
  }
  assert.equal(`${result.marketIds["Khan's Dim Magic"]}`, '45517');
  assert.equal(result.itemIconGrades["khan's dim magic"], 3);
  assert(result.itemIconArtwork["khan's dim magic"].startsWith('data:image/'));
  // The original exact-ID artwork already exists in Processing. Shared item
  // windows use mode-owned indexes, so make that same icon available in all.
  for (const mode of [result, result.cooking]) {
    mode.itemIcons["Khan's Dim Magic"] = result.processing.itemIcons["Khan's Dim Magic"];
  }
  result.itemWeightIds["Khan's Dim Magic"] = '45517';
  result.itemWeightsLtById['45517'] = 0.1;
  result.acquisitionInfo["Khan's Dim Magic"] = {
    canonicalName: "Khan's Dim Magic", itemId: 45517, status: 'reviewed', reviewedAt: '2026-11-04',
    routes: [{kind: 'quest', summary: "Curio · Oquilla's Eye: complete his three Khan quests in order (once per family). Defeat Khan at each quest's required difficulty.", availability: 'permanent', confidence: 'high', sources: [{title: 'NA/EU PC October 18, 2023 update', url: 'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=6072&countryType=en-US', supports: ['identity', 'acquisition', 'restriction']}]}],
  };
  return result;
}
