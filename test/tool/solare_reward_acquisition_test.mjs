import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {applySolareRewardAcquisition} from '../../tool/solare_reward_acquisition.mjs';

test('Solare regeneration matches the bundled acquisition data exactly', () => {
  const bundle = JSON.parse(fs.readFileSync('assets/data/app-data.json', 'utf8'));
  const original = structuredClone(bundle.acquisitionInfo);
  applySolareRewardAcquisition(bundle.acquisitionInfo);
  assert.deepEqual(bundle.acquisitionInfo, original);
});

test('rank rewards are idempotent and preserve existing and unrelated routes', () => {
  const old = {kind:'npc_exchange', summary:'Existing exchange', availability:'permanent'};
  const unrelated = {canonicalName:'Salt', routes:[]};
  const info = {'Sturdy Forest Tread': {routes:[old]}, Salt:unrelated};
  applySolareRewardAcquisition(info);
  assert.equal(info.Salt, unrelated);
  assert.equal(info['Sturdy Forest Tread'].routes[1], old);
  assert.equal(info['Perfume of Courage'], undefined);
  assert.equal(info['Perfume of Deep Sea'], undefined);
  const once = structuredClone(info);
  applySolareRewardAcquisition(info);
  assert.deepEqual(info, once);
  for (const [name, count] of [['Sturdy Forest Tread',20],['Perfume of Envy',30],['Perfume of Tenacity',30]]) {
    const route = info[name].routes[0];
    assert.equal(route.kind, 'season_reward');
    assert.equal(route.availability, 'season-rank-limited');
    assert.match(route.summary, new RegExp(`Receive ${count} from`));
    assert.match(route.summary, /ranked season in the Top 100/);
    assert.equal(route.sources.length, 2);
  }
});
