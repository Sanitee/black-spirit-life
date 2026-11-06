import assert from 'node:assert/strict';
import test from 'node:test';
import { applyReviewedWorkerOutputs } from './worker_output_corrections.mjs';

const grain = (nodeId, itemId) => ({
  nodeId, baseWorkload: 280, workerTypes: [0, 1, 2],
  standardYields: { [itemId]: 18 },
  giantYields: { [itemId]: 29.75029096 },
  luckyBonusYields: { 1024: .3 }, townDistances: { 1604: 1234 },
});

test('rekeys exactly the two Marak grains without changing source or estimates', () => {
  for (const [nodeId, oldId, newId] of [['1673', 7005, 7002], ['1674', 7002, 7005]]) {
    const input = grain(nodeId, oldId), saved = structuredClone(input);
    const result = applyReviewedWorkerOutputs(input);
    assert.deepEqual(result, grain(nodeId, newId));
    assert.deepEqual(input, saved);
  }
});

test('future source changes require review rather than another blind rekey', () => {
  assert.throws(() => applyReviewedWorkerOutputs(grain('1673', 7002)));
  const changed = grain('1673', 7005);
  changed.giantYields[7005] = 30;
  assert.throws(() => applyReviewedWorkerOutputs(changed));
});

test('removes only the retired Dallae output', () => {
  const input = { nodeId: '1833', baseWorkload: 4000,
    standardYields: {8022: 1, 820138: 7.6},
    giantYields: {8022: 1.34467985, 820138: 12.33333302},
    luckyBonusYields: {1026: 4}, townDistances: {1801: 100},
  };
  const expected = structuredClone(input);
  delete expected.standardYields[8022];
  delete expected.giantYields[8022];
  assert.deepEqual(applyReviewedWorkerOutputs(input), expected);
  assert.equal(input.standardYields[8022], 1);
  assert.throws(() => applyReviewedWorkerOutputs(expected));
});

test('unrelated and unknown output identities are not silently filtered', () => {
  const input = grain('new-unreviewed-node', 7005);
  input.standardYields[999999] = 7;
  assert.deepEqual(applyReviewedWorkerOutputs(input), input);
});
