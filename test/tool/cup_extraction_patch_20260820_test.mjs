import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {applyCupExtractionPatch, currentCupReformAcquisition,
  CUP_EXTRACTION_IDENTITIES, CUP_EXTRACTION_PATCH_SOURCE}
  from '../../tool/apply_cup_extraction_patch_20260820.mjs';
import {EDANIA_PART_II_ACQUISITION_INFO} from '../../tool/edania_part_ii_catalog_manifest.mjs';

const catalog = JSON.parse(fs.readFileSync(new URL('../../assets/data/app-data.json', import.meta.url)));
test('eight current extraction records are deterministic and generator-aligned', () => {
  assert.equal(Object.keys(CUP_EXTRACTION_IDENTITIES).length, 8);
  const again = applyCupExtractionPatch(structuredClone(catalog));
  assert.deepEqual(again, catalog);
  for (const [name, id] of Object.entries(CUP_EXTRACTION_IDENTITIES)) {
    const info = catalog.acquisitionInfo[name];
    assert.equal(info.itemId, id);
    assert.deepEqual(info, EDANIA_PART_II_ACQUISITION_INFO[name]);
    assert.ok(info.routes[0].summary.includes('Extract with Mirror of Equilibrium'));
    assert.ok(!info.routes[0].summary.includes('Refined Essence of Emotions'));
    assert.deepEqual(info.routes[0].sources.filter(s => s.supports.includes('extraction')).map(s => s.url),
      [CUP_EXTRACTION_PATCH_SOURCE]);
  }
});
test('identity and unexpected-route mismatches cannot overwrite new facts', () => {
  const source = catalog.acquisitionInfo['Dawnbound Ekleta Necklace'];
  assert.throws(() => currentCupReformAcquisition({...source, itemId: 999999}));
  assert.throws(() => currentCupReformAcquisition({...source, canonicalName: 'Other necklace'}));
  const changed = structuredClone(source);
  changed.routes[0].summary = 'An independently changed extraction rule';
  assert.throws(() => currentCupReformAcquisition(changed));
});
test('only the eight extraction-source records change, never raw historical recipes', () => {
  const legacy = structuredClone(catalog);
  for (const name of Object.keys(CUP_EXTRACTION_IDENTITIES)) {
    const info = legacy.acquisitionInfo[name];
    info.routes[0].summary = info.routes[0].summary.replace('Mirror of Equilibrium', 'Refined Essence of Emotions');
    info.reviewedAt = '2026-08-15';
  }
  const result = applyCupExtractionPatch(legacy);
  assert.deepEqual(result, catalog);
  for (const name of ['Fused Crystal of Emotions', 'Refined Essence of Emotions']) {
    assert.ok(result.processing.items[name].ingredients.length);
  }
});
