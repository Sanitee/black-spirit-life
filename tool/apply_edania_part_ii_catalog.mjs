import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  EDANIA_PART_II_ACQUISITION_INFO,
  EDANIA_PART_II_ALCHEMY_RECIPES,
  EDANIA_PART_II_ASIA_SOURCE,
  EDANIA_PART_II_INFERRED_PROCESSING_OUTPUTS,
  EDANIA_PART_II_ITEMS,
  EDANIA_PART_II_ORIGIN_CRYSTALS,
  EDANIA_PART_II_PENDING_MARKET_VERIFICATION,
  EDANIA_PART_II_PROCESSING_RECIPES,
  EDANIA_PART_II_REFERENCE_ITEMS,
  EDANIA_PART_II_REFORGE_EFFECTS,
  EDANIA_PART_II_REVIEWED_AT,
  EDANIA_PART_II_SOURCE,
  EDANIA_PART_II_UNRESOLVED_ITEMS,
} from './edania_part_ii_catalog_manifest.mjs';

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDirectory, '..');
const catalogPath = resolve(projectRoot, 'assets', 'data', 'app-data.json');
const checkOnly = process.argv.includes('--check');

const sourceText = await readFile(catalogPath, 'utf8');
const catalog = JSON.parse(sourceText);

for (const required of [
  'items',
  'itemIcons',
  'processing',
  'acquisitionInfo',
  'marketIds',
  'marketNameIds',
  'itemWeightIds',
  'itemWeightsLtById',
  'importedRecipeMeta',
]) {
  if (catalog[required] == null || typeof catalog[required] !== 'object') {
    throw new Error(`Bundled catalog is missing the required ${required} map.`);
  }
}
if (
  catalog.processing.items == null ||
  catalog.processing.itemIcons == null
) {
  throw new Error('Bundled processing catalog is incomplete.');
}

const names = new Set();
const ids = new Map();
for (const record of EDANIA_PART_II_ITEMS) {
  const folded = record.name.trim().toLowerCase();
  if (!record.name.trim() || !names.add(folded)) {
    throw new Error(`Duplicate or empty Edania item name: ${record.name}`);
  }
  if (!Number.isInteger(record.id) || record.id <= 0) {
    throw new Error(`Invalid item ID for ${record.name}.`);
  }
  const priorName = ids.get(record.id);
  if (priorName != null && priorName !== record.name) {
    throw new Error(
      `Item ID ${record.id} is assigned to both ${priorName} and ${record.name}.`,
    );
  }
  ids.set(record.id, record.name);
  if (!Number.isFinite(record.weight) || record.weight <= 0) {
    throw new Error(`Invalid item weight for ${record.name}.`);
  }
  if (!/^[a-f0-9]{64}$/.test(record.iconSha256)) {
    throw new Error(`Invalid pinned icon hash for ${record.name}.`);
  }
}

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const embeddedIconBytes = (value) => {
  const match = /^data:image\/webp;base64,([A-Za-z0-9+/=]+)$/.exec(
    String(value ?? ''),
  );
  return match == null ? null : Buffer.from(match[1], 'base64');
};

const downloadCache = new Map();
const resolveIcon = async (record, existing) => {
  const embedded = embeddedIconBytes(existing);
  if (embedded != null && sha256(embedded) === record.iconSha256) {
    return existing;
  }
  let request = downloadCache.get(record.iconUrl);
  if (request == null) {
    request = (async () => {
      const response = await fetch(record.iconUrl);
      if (!response.ok) {
        throw new Error(
          `Could not download ${record.iconUrl}: HTTP ${response.status}.`,
        );
      }
      return Buffer.from(await response.arrayBuffer());
    })();
    downloadCache.set(record.iconUrl, request);
  }
  const bytes = await request;
  const actualHash = sha256(bytes);
  if (actualHash !== record.iconSha256) {
    throw new Error(
      `Artwork hash changed for ${record.name}: expected ` +
        `${record.iconSha256}, found ${actualHash}.`,
    );
  }
  return `data:image/webp;base64,${bytes.toString('base64')}`;
};

const records = [...EDANIA_PART_II_ITEMS];
const resolvedIcons = new Map();
let nextIcon = 0;
const workers = Array.from({ length: Math.min(4, records.length) }, async () => {
  for (;;) {
    const index = nextIcon++;
    if (index >= records.length) return;
    const record = records[index];
    const iconMap =
      record.mode === 'alchemy'
        ? catalog.itemIcons
        : catalog.processing.itemIcons;
    resolvedIcons.set(
      record.name,
      await resolveIcon(record, iconMap[record.name]),
    );
  }
});
await Promise.all(workers);

const stableJson = (value) => JSON.stringify(value);
const upsertRecipe = (target, name, recipe) => {
  const existing = target[name];
  if (existing != null && stableJson(existing) !== stableJson(recipe)) {
    throw new Error(
      `Refusing to overwrite a different bundled recipe named ${name}.`,
    );
  }
  target[name] = recipe;
};

for (const [name, recipe] of Object.entries(
  EDANIA_PART_II_ALCHEMY_RECIPES,
)) {
  upsertRecipe(catalog.items, name, recipe);
}
for (const [name, recipe] of Object.entries(
  EDANIA_PART_II_PROCESSING_RECIPES,
)) {
  upsertRecipe(catalog.processing.items, name, recipe);
}
for (const [name, recipe] of Object.entries(EDANIA_PART_II_REFERENCE_ITEMS)) {
  upsertRecipe(catalog.processing.items, name, recipe);
}

for (const record of records) {
  const iconMap =
    record.mode === 'alchemy'
      ? catalog.itemIcons
      : catalog.processing.itemIcons;
  iconMap[record.name] = resolvedIcons.get(record.name);
  catalog.itemWeightIds[record.name] = String(record.id);
  catalog.itemWeightsLtById[String(record.id)] = record.weight;

  if (record.marketVerification === 'verified') {
    catalog.marketIds[record.name] = String(record.id);
    catalog.marketNameIds[record.name.trim().toLowerCase()] = String(record.id);
  } else {
    if (catalog.marketIds[record.name] != null) {
      throw new Error(
        `Pending/non-marketable item ${record.name} already has a market ID; ` +
          'review it explicitly instead of deleting or replacing it here.',
      );
    }
  }
}

for (const [name, information] of Object.entries(
  EDANIA_PART_II_ACQUISITION_INFO,
)) {
  const existing = catalog.acquisitionInfo[name];
  if (existing != null && stableJson(existing) !== stableJson(information)) {
    throw new Error(
      `Refusing to overwrite different reviewed acquisition data for ${name}.`,
    );
  }
  catalog.acquisitionInfo[name] = information;
}

catalog.edaniaPartIiReview = {
  reviewedAt: EDANIA_PART_II_REVIEWED_AT,
  officialSource: EDANIA_PART_II_SOURCE,
  officialSources: [EDANIA_PART_II_SOURCE, EDANIA_PART_II_ASIA_SOURCE],
  marketVerificationRule:
    'Missing market IDs remain unset until exact current market eligibility is independently verified.',
  pendingMarketVerification: EDANIA_PART_II_PENDING_MARKET_VERIFICATION,
  intentionallyNotMarketable: EDANIA_PART_II_ITEMS.filter(
    (record) => record.marketVerification === 'not_marketable',
  ).map((record) => ({ name: record.name, itemId: record.id })),
  reforgeEffects: EDANIA_PART_II_REFORGE_EFFECTS,
  originCrystals: EDANIA_PART_II_ORIGIN_CRYSTALS,
  referenceItems: Object.keys(EDANIA_PART_II_REFERENCE_ITEMS),
  inferredProcessingOutputs: EDANIA_PART_II_INFERRED_PROCESSING_OUTPUTS,
  unresolvedItems: EDANIA_PART_II_UNRESOLVED_ITEMS,
};

catalog.importedRecipeMeta.edaniaPartIi = {
  reviewedAt: EDANIA_PART_II_REVIEWED_AT,
  source: 'Official Edania Part II patch notes, cross-checked against exact BDO Codex item records',
  sourceUrls: [EDANIA_PART_II_SOURCE, EDANIA_PART_II_ASIA_SOURCE],
  alchemyRecipes: Object.keys(EDANIA_PART_II_ALCHEMY_RECIPES).length,
  processingRecipes: Object.keys(EDANIA_PART_II_PROCESSING_RECIPES).length,
  referenceItems: Object.keys(EDANIA_PART_II_REFERENCE_ITEMS).length,
  embeddedIcons: records.length,
  pendingMarketVerification: EDANIA_PART_II_PENDING_MARKET_VERIFICATION.length,
};

for (const [name, recipe] of Object.entries(
  EDANIA_PART_II_PROCESSING_RECIPES,
)) {
  if (stableJson(catalog.processing.items[name]) !== stableJson(recipe)) {
    throw new Error(`Postcondition failed for processing recipe ${name}.`);
  }
}
for (const [name, recipe] of Object.entries(
  EDANIA_PART_II_ALCHEMY_RECIPES,
)) {
  if (stableJson(catalog.items[name]) !== stableJson(recipe)) {
    throw new Error(`Postcondition failed for alchemy recipe ${name}.`);
  }
}
for (const [name, recipe] of Object.entries(EDANIA_PART_II_REFERENCE_ITEMS)) {
  if (stableJson(catalog.processing.items[name]) !== stableJson(recipe)) {
    throw new Error(`Postcondition failed for reference item ${name}.`);
  }
}

const output = `${JSON.stringify(catalog, null, 2)}\n`;
if (checkOnly) {
  if (output !== sourceText) {
    throw new Error(
      'The bundled catalog is not the deterministic Edania Part II result. ' +
        'Run tool/apply_edania_part_ii_catalog.mjs first.',
    );
  }
  console.log('Edania Part II catalog is deterministic and current.');
} else {
  await writeFile(catalogPath, output, 'utf8');
  console.log(
    `Applied ${Object.keys(EDANIA_PART_II_ALCHEMY_RECIPES).length} alchemy ` +
      `and ${Object.keys(EDANIA_PART_II_PROCESSING_RECIPES).length} processing ` +
      `recipes, ${Object.keys(EDANIA_PART_II_REFERENCE_ITEMS).length} ` +
      `reference items, and ${records.length} verified item records.`,
  );
}
