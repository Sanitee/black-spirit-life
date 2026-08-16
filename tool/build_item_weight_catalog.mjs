import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const defaultCatalogPath = path.join(projectRoot, 'assets', 'data', 'app-data.json');
const nonMarketItemIds = Object.freeze({
  'Cottonseed Oil': '9022',
});

const args = parseArgs(process.argv.slice(2));
if (!args.extract) {
  fail('Usage: node tool/build_item_weight_catalog.mjs --extract <items.json> [--catalog <app-data.json>] [--check]');
}

const catalogPath = path.resolve(args.catalog ?? defaultCatalogPath);
const extractPath = path.resolve(args.extract);
const catalog = JSON.parse(await fs.readFile(catalogPath, 'utf8'));
const extract = JSON.parse(await fs.readFile(extractPath, 'utf8'));
if (!Array.isArray(extract)) fail('The item extract must be a JSON array.');

const extractById = new Map();
for (const record of extract) {
  const id = normalizedId(record?.id);
  if (!id) fail('Every item extract record must have an ID.');
  if (extractById.has(id)) fail(`Duplicate item ID ${id} in the extract.`);
  extractById.set(id, record);
}

const recipeIds = new Map();
const requiredNames = new Set();
for (const items of modeItemMaps(catalog)) {
  for (const [key, recipe] of Object.entries(items)) {
    const name = normalizedName(recipe?.name ?? key);
    const ingredients = Array.isArray(recipe?.ingredients) ? recipe.ingredients : [];
    const role = `${recipe?.recipeRole ?? recipe?.role ?? 'production'}`.trim().toLowerCase();
    if (!name || role !== 'production' || ingredients.length === 0 || fold(name) === 'assorted side dishes') {
      continue;
    }
    requiredNames.add(name);
    rememberRecipeId(recipeIds, name, recipe?.marketId);
    addIngredients(requiredNames, ingredients);
    for (const variant of Array.isArray(recipe?.variants) ? recipe.variants : []) {
      addIngredients(requiredNames, variant?.ingredients);
    }
  }
}

const supportingIds = new Map();
const supportingIdsFolded = new Map();
for (const [name, rawId] of Object.entries(catalog.marketIds ?? {})) {
  const id = normalizedId(rawId);
  if (!id) continue;
  supportingIds.set(name, id);
  const folded = fold(name);
  if (!supportingIdsFolded.has(folded)) supportingIdsFolded.set(folded, id);
}

const itemWeightIds = {};
const weightsById = new Map();
for (const name of [...requiredNames].sort(compareText)) {
  const id = recipeIds.get(name) ?? supportingIds.get(name) ?? supportingIdsFolded.get(fold(name)) ?? nonMarketItemIds[name];
  if (!id) fail(`No exact item ID is available for ${JSON.stringify(name)}.`);
  const record = extractById.get(id);
  if (!record) fail(`Item ID ${id} (${name}) is absent from the extract.`);
  const weight = Number(record.weight);
  if (!Number.isFinite(weight) || weight <= 0) {
    fail(`Item ID ${id} (${name}) has no positive finite weight.`);
  }
  itemWeightIds[name] = id;
  const previous = weightsById.get(id);
  if (previous != null && previous !== weight) fail(`Conflicting weights for item ID ${id}.`);
  weightsById.set(id, weight);
}

const itemWeightsLtById = Object.fromEntries(
  [...weightsById.entries()].sort(([left], [right]) => Number(left) - Number(right)),
);
const matches = stableJson(catalog.itemWeightIds) === stableJson(itemWeightIds) &&
  stableJson(catalog.itemWeightsLtById) === stableJson(itemWeightsLtById);

if (args.check) {
  if (!matches) fail('The bundled item-weight catalog is out of date. Run this tool without --check.');
} else {
  catalog.itemWeightIds = itemWeightIds;
  catalog.itemWeightsLtById = itemWeightsLtById;
  await fs.writeFile(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`, 'utf8');
}

process.stdout.write(
  `${args.check ? 'Verified' : 'Wrote'} ${Object.keys(itemWeightIds).length} names and ${Object.keys(itemWeightsLtById).length} exact item weights.\n`,
);

function modeItemMaps(root) {
  return [root.items, root.cooking?.items, root.processing?.items].map((value) => value ?? {});
}

function addIngredients(names, rawIngredients) {
  if (!Array.isArray(rawIngredients)) return;
  for (const ingredient of rawIngredients) {
    const name = normalizedName(ingredient?.name);
    if (name) names.add(name);
    for (const option of Array.isArray(ingredient?.options) ? ingredient.options : []) {
      const optionName = normalizedName(option);
      if (optionName) names.add(optionName);
    }
  }
}

function rememberRecipeId(ids, name, rawId) {
  const id = normalizedId(rawId);
  if (!id) return;
  const previous = ids.get(name);
  if (previous != null && previous !== id) fail(`Conflicting recipe IDs for ${name}: ${previous} and ${id}.`);
  ids.set(name, id);
}

function parseArgs(values) {
  const result = {check: false};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === '--check') result.check = true;
    else if (value === '--extract' || value === '--catalog') {
      const next = values[index + 1];
      if (!next) fail(`${value} requires a path.`);
      result[value.slice(2)] = next;
      index += 1;
    } else fail(`Unknown argument: ${value}`);
  }
  return result;
}

function normalizedName(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function normalizedId(value) {
  if (value == null) return '';
  const id = `${value}`.trim();
  return /^\d+$/.test(id) ? id : '';
}

function fold(value) {
  return value.trim().toLowerCase();
}

function compareText(left, right) {
  return left.localeCompare(right, 'en', {sensitivity: 'variant'});
}

function stableJson(value) {
  return JSON.stringify(value ?? null);
}

function fail(message) {
  throw new Error(message);
}
