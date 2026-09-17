import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';

const generator = fileURLToPath(new URL('../../tool/build_item_weight_catalog.mjs', import.meta.url));

test('weight generation includes reachable metadata options without case duplicates', async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'bsl-weight-generator-'));
  t.after(() => fs.rm(directory, {recursive: true, force: true}));
  const catalogPath = path.join(directory, 'catalog.json');
  const extractPath = path.join(directory, 'extract.json');
  const catalog = {
    items: {
      Reagent: {marketId: '5301', ingredients: [
        {name: 'Sunrise Herb', qty: 1},
        {name: 'High-quality Sunrise Herb', qty: 1},
        {name: 'Fox Blood', qty: 1},
        {name: 'Lizard Blood', qty: 1},
      ]},
    },
    meta: {
      bloodGroups: {Fox: ['Fox Blood', 'Monkey Blood']},
      substituteWorthGroups: {
        Herbs: {'Sunrise Herb': 1, 'High-Quality Sunrise Herb': 6, 'Pile of Sunrise Herbs': 6,
          'Invalid zero': 0, 'Invalid negative': -1, 'Invalid text': 'unknown'},
        Lizards: {'Lizard Blood': 1, 'Worm Blood': 2},
        Unused: {'Unused ingredient': 1, 'Unused alternative': 2},
      },
    },
    marketIds: {'Sunrise Herb': '5401', 'High-quality Sunrise Herb': '5444',
      'Pile of Sunrise Herbs': '5421', 'Fox Blood': '6201', 'Monkey Blood': '6211',
      'Lizard Blood': '6207', 'Worm Blood': '6209'},
  };
  const extract = ['5301', ...Object.values(catalog.marketIds)].map((id) => ({id, weight: 0.1}));
  await fs.writeFile(catalogPath, JSON.stringify(catalog));
  await fs.writeFile(extractPath, JSON.stringify(extract));
  const run = (...extra) => spawnSync(process.execPath,
    [generator, '--extract', extractPath, '--catalog', catalogPath, ...extra], {encoding: 'utf8'});

  const generated = run();
  assert.equal(generated.status, 0, generated.stderr);
  const actual = JSON.parse(await fs.readFile(catalogPath, 'utf8'));
  assert.equal(actual.itemWeightIds['Pile of Sunrise Herbs'], '5421');
  assert.equal(actual.itemWeightsLtById['5421'], 0.1);
  assert.equal(actual.itemWeightIds['Monkey Blood'], '6211');
  assert.equal(actual.itemWeightIds['Worm Blood'], '6209');
  assert.equal(actual.itemWeightIds['High-quality Sunrise Herb'], '5444');
  assert.equal(actual.itemWeightIds['High-Quality Sunrise Herb'], undefined);
  assert.equal(actual.itemWeightIds['Unused alternative'], undefined);
  assert.equal(actual.itemWeightIds['Invalid zero'], undefined);
  assert.deepEqual(actual.meta, catalog.meta);
  assert.deepEqual(actual.items, catalog.items);
  assert.equal(run('--check').status, 0);

  delete actual.itemWeightIds['Pile of Sunrise Herbs'];
  await fs.writeFile(catalogPath, JSON.stringify(actual));
  const stale = run('--check');
  assert.notEqual(stale.status, 0);
  assert.match(stale.stderr, /out of date/);

  await fs.writeFile(extractPath, JSON.stringify(extract.filter((record) => record.id !== '5421')));
  const incomplete = run();
  assert.notEqual(incomplete.status, 0);
  assert.match(incomplete.stderr, /5421 .*absent from the extract/);
});
