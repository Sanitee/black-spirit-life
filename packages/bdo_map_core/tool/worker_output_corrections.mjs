import assert from 'node:assert/strict';

// Corrections to exact output identities in the separately hash-pinned inputs.
// These do not certify or change the retained empirical yield estimates.
export const reviewedWorkerOutputCorrections = Object.freeze([
  {
    nodeId: '1673',
    change: 'Marak Farm barley site: rekey Corn 7005 to Barley 7002.',
    evidence: 'https://bdocodex.com/us/node/1673/',
  },
  {
    nodeId: '1674',
    change: 'Marak Farm corn site: rekey Barley 7002 to Corn 7005.',
    evidence: 'https://bdocodex.com/us/node/1674/',
  },
  {
    nodeId: '1833',
    change: 'Dallae Pier: remove Starlight Powder 8022, removed May 29, 2024.',
    evidence:
      'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=7050&countryType=en-US',
  },
]);

export function applyReviewedWorkerOutputs(production) {
  const result = structuredClone(production);
  const nodeId = result.nodeId;
  if (nodeId === '1673' || nodeId === '1674') {
    const oldId = nodeId === '1673' ? '7005' : '7002';
    const newId = nodeId === '1673' ? '7002' : '7005';
    for (const [field, quantity] of [
      ['standardYields', 18],
      ['giantYields', 29.75029096],
    ]) {
      assert.deepEqual(result[field], { [oldId]: quantity },
        `Review changed upstream output mapping at ${nodeId}/${field}`);
      result[field] = { [newId]: quantity };
    }
  }
  if (nodeId === '1833') {
    for (const [field, quantity] of [
      ['standardYields', 1],
      ['giantYields', 1.34467985],
    ]) {
      assert.equal(result[field]['8022'], quantity,
        `Review changed upstream Starlight Powder at ${nodeId}/${field}`);
      delete result[field]['8022'];
    }
  }
  return result;
}
