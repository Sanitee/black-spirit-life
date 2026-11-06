// Deliberately narrow native-description rules. Unrecognized text stays a gap.
// Never derive recipes, probabilities, prices or eligibility from this copy.
const fold = value => value.toLowerCase().replaceAll('-', ' ').replace(/\s+/g, ' ').trim();
export function reviewedDescriptionSources(item, catalog) {
  const text = (item.description ?? '').replace(/<[^>]*>/g, '');
  const route = text.split('How to Obtain:')[1]?.split('\n')[0].trim();
  if (!route || route.includes('{')) return [];
  // Some rare dishes repeat the normal recipe's lower skill before a complete
  // parenthesized rare-result clause. Read only that anchored clause here; do
  // not assign the normal recipe's requirement to the special output.
  const wrappedRare = /^Craft via a Cooking Utensil in your residence if at least Cooking (?:Beginner|Apprentice|Skilled|Professional|Artisan|Master|Guru) \d+ \((slight chance of .+)\)\.?$/i.exec(route);
  const special = Object.entries(catalog.cookingSpecialMap).find(([, value]) => fold(value.name) === fold(item.name));
  const extra = /^Slight chance of (?:obtaining|acquiring) (?:a )?(.+?) (?:when|while) (?:making|producing) (.+?) (?:if (?:you are )?)?at least (?:Cooking )?((?:Beginner|Apprentice|Skilled|Professional|Artisan|Master|Guru) \d+)\.?$/i.exec(wrappedRare?.[1] ?? route);
  const parent = extra && Object.entries(catalog.cooking?.items ?? {}).find(([name, recipe]) =>
    fold(name) === fold(extra[2]) && recipe.type === 'cooking' && recipe.ingredients?.length)?.[0];
  if (extra && fold(extra[1]) === fold(item.name) &&
      (special ? fold(extra[2]) === fold(special[0]) : parent)) {
    return [`Cooking · Make ${special?.[0] ?? parent} (rare extra, ${extra[3]}+)`];
  }
  // Minimum skill for an actual normal recipe, never the lower parent skill
  // copied into a rare dish's description. Special-result thresholds stay on
  // their separately qualified chance route above.
  const craft = /^Craft via (?:a Cooking Utensil|an alchemy tool) in your residence(?: with the following materials)? if at least (Cooking|Alchemy) ((?:Beginner|Apprentice|Skilled|Professional|Artisan|Master|Guru) \d+)(?:\.| \(slight chance of .+\))?$/i.exec(route);
  if (craft) {
    const mode = craft[1].toLowerCase();
    const entries = mode === 'alchemy' ? catalog.items : catalog.cooking?.items;
    const recipe = Object.entries(entries ?? {}).find(([name]) => fold(name) === fold(item.name))?.[1];
    if (recipe?.type === mode && recipe.ingredients?.length) {
      return [`${mode === 'alchemy' ? 'Alchemy' : 'Cooking'} · ${craft[2]}+`];
    }
  }
  if (route === 'Farming (seeds via Plant Breeding in a garden)') {
    const planting = item.name.endsWith('Mushroom') ? 'Hyphae' : 'Seeds';
    return ['Garden · Grow in a fenced garden', `${planting} · Use Plant Breeding in your garden`];
  }
  if (route === 'Plant Breeding in a garden') return ['Garden · Use Plant Breeding to get seeds'];
  // Parse a whole documented Gathering clause, including its restrictions.
  // A gatheredFrom index alone is insufficient (processed items can be rare
  // mastery drops). Never infer ordinary gathering from those index entries.
  const clause = /(?:^|, )Gathering \(([^()]+)\)(?=$|, )/.exec(route);
  if (clause) {
    const hands = /^(.+?) with bare hands or a hoe(?:, (affected by Gathering Level|requires high Gathering Mastery))?$/i.exec(clause[1]);
    if (hands) return [`Gather · ${hands[1]} (hands or hoe${hands[2] ? '; '+hands[2].replace('affected by Gathering Level','depends on Gathering level').replace('requires high Gathering Mastery','high Gathering Mastery required') : ''})`];
    const bare = /^(.+?) with bare hands$/.exec(clause[1]);
    if (bare) return [`Gather · ${bare[1]} (by hand)`];
    if (clause[1] === 'underwater with a hoe') return ['Gather · Underwater corals (hoe)'];
  }
  const gather = /^Gathering \((.+) with bare hands or a hoe, affected by Gathering Level\)$/.exec(route);
  if (gather) return [`Gather · ${gather[1]} (hands or hoe; depends on Gathering level)`];
  if (route === 'Morning Light World Boss subjugation rewards') return ['World bosses · Morning Light'];
  if (route === 'Defeat monsters in Edania') return ['Monster drops · Edania'];
  if (route === 'Defeat monsters in Kamasylvia') return ['Monster drops · Kamasylvia'];
  if (route === 'Defeat certain monsters') return ['Monster drops · Check Monster Zone Info'];
  if (route === 'It can be obtained by grinding an alchemy stone.') return ['Processing · Grind an Alchemy Stone'];
  return [];
}
