import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export const CUP_EXTRACTION_PATCH_SOURCE =
  'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=10478';
export const CUP_EXTRACTION_PATCH_DATE = '2026-08-20';
export const CUP_EXTRACTION_IDENTITIES = {
  'Dawnbound Ekleta Necklace': 11732, 'Dawnbound Apeiron Necklace': 11734,
  'Moonhushed Ekleta Earring': 11897, 'Moonhushed Apeiron Earring': 11899,
  'Sunstarved Ekleta Ring': 12143, 'Sunstarved Apeiron Ring': 12145,
  'Duskborne Ekleta Belt': 12297, 'Duskborne Apeiron Belt': 12299,
};
const previous = 'Extract with Refined Essence of Emotions to recover the original accessory and cup.';
const current = 'Extract with Mirror of Equilibrium to recover the original accessory and cup.';

export function currentCupReformAcquisition(existing) {
  assert.equal(existing.itemId, CUP_EXTRACTION_IDENTITIES[existing.canonicalName]);
  assert.ok(existing.itemId && existing.routes?.length === 1);
  const result = structuredClone(existing);
  const route = result.routes[0];
  assert.equal(route.kind, 'item_reform');
  assert.ok(route.summary.endsWith(previous) || route.summary.endsWith(current));
  route.summary = route.summary.replace(previous, current);
  result.reviewedAt = CUP_EXTRACTION_PATCH_DATE;
  for (const source of route.sources) {
    if (source.url !== CUP_EXTRACTION_PATCH_SOURCE) {
      source.supports = source.supports.filter(s => s !== 'extraction');
    }
  }
  if (!route.sources.some(s => s.url === CUP_EXTRACTION_PATCH_SOURCE)) {
    route.sources.push({title: 'Official August 20, 2026 PC cup extraction update',
      url: CUP_EXTRACTION_PATCH_SOURCE, supports: ['extraction']});
  }
  return result;
}

export function applyCupExtractionPatch(catalog) {
  const before = structuredClone(catalog);
  for (const name of Object.keys(CUP_EXTRACTION_IDENTITIES)) {
    catalog.acquisitionInfo[name] = currentCupReformAcquisition(catalog.acquisitionInfo[name]);
  }
  const withoutScope = value => {
    const result = structuredClone(value);
    for (const name of Object.keys(CUP_EXTRACTION_IDENTITIES)) delete result.acquisitionInfo[name];
    return result;
  };
  assert.deepEqual(withoutScope(before), withoutScope(catalog), 'Unrelated catalog data changed');
  return catalog;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const target = new URL('../assets/data/app-data.json', import.meta.url);
  const original = await readFile(target, 'utf8');
  const output = JSON.stringify(applyCupExtractionPatch(JSON.parse(original)), null, 2) + '\n';
  if (process.argv.includes('--check')) {
    assert.equal(output, original, 'Cup extraction guidance is not current');
    console.log('Eight cup extraction source records are current and deterministic.');
  } else {
    await writeFile(target, output, 'utf8');
    console.log('Updated exactly eight acquisition records; recipes and historical identities retained.');
  }
}
