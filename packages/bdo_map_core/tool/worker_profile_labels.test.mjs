import assert from 'node:assert/strict';
import test from 'node:test';
import { workerSpeciesLabel } from './worker_profile_labels.mjs';

for (const [species, name] of [
  [0, 'Goblin'], [1, 'Human'], [2, 'Giant'], [3, 'Papu'], [4, 'Fadus'],
  [5, 'Dwarf'], [6, 'Dokkebi'], [7, 'Dolswe'], [8, 'Shellfolk'],
]) {
  test(`species ${species} is ${name}`, () => {
    assert.equal(workerSpeciesLabel(species), name);
    assert.equal(workerSpeciesLabel(String(species)), name);
  });
}
test('unreviewed species are not assigned a known identity', () => {
  assert.equal(workerSpeciesLabel(9), 'Worker type 9');
  assert.equal(workerSpeciesLabel(-1), 'Worker type -1');
  assert.equal(workerSpeciesLabel('new'), 'Worker type new');
  assert.equal(workerSpeciesLabel(null), 'Worker type null');
  assert.equal(workerSpeciesLabel(false), 'Worker type false');
});
