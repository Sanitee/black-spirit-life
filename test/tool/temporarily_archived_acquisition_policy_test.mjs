import assert from 'node:assert/strict';
import test from 'node:test';
import {
  archiveGeneratedAcquisitionInfo,
  readTemporarilyArchivedItemPolicy,
  temporarilyArchivedItemPolicy,
} from '../../tool/temporarily_archived_acquisition_policy.mjs';

test('generator uses exactly the eight shared archived identities', () => {
  assert.deepEqual(Object.keys(temporarilyArchivedItemPolicy.itemsById).sort(),
    ['6211', '6011', '6007', '15202', '15208', '15209', '15210', '15215'].sort());
  const info = {};
  for (const [itemId, name] of Object.entries(temporarilyArchivedItemPolicy.itemsById)) {
    info[name] = {canonicalName: name, itemId: Number(itemId), status: 'reviewed',
      routes: [{summary: 'Historical source record'}]};
  }
  const originalRoutes = info['Monkey Blood'].routes;
  archiveGeneratedAcquisitionInfo(info);
  for (const entry of Object.values(info)) {
    assert.equal(entry.status, 'temporarily_archived');
    assert.equal(entry.archiveReason, temporarilyArchivedItemPolicy.reason);
  }
  assert.equal(info['Monkey Blood'].routes, originalRoutes);
  assert.equal(archiveGeneratedAcquisitionInfo(info), info);
});

test('explicit IDs beat names and adjacent live crystals stay reviewed', () => {
  const info = {
    'Monkey Blood': {itemId: 6210, status: 'reviewed'},
    'Custom alias': {itemId: ' 015202 ', status: 'reviewed'},
    ' monkey hide ': {status: 'reviewed'},
    'Sealed Black Magic Crystal': {itemId: 16001, status: 'reviewed'},
    'Black Magic Crystal - Precision': {itemId: 15201, status: 'reviewed'},
    'Cheetah Dragon Hide': {itemId: 6016, status: 'reviewed'},
    'Dinosaur Blood': {itemId: 6210, status: 'reviewed'},
  };
  archiveGeneratedAcquisitionInfo(info);
  assert.equal(info['Custom alias'].status, 'temporarily_archived');
  assert.equal(info[' monkey hide '].status, 'temporarily_archived');
  for (const name of ['Monkey Blood', 'Sealed Black Magic Crystal',
    'Black Magic Crystal - Precision', 'Cheetah Dragon Hide', 'Dinosaur Blood']) {
    assert.equal(info[name].status, 'reviewed');
  }
});

test('an unreadable policy stops generation rather than silently unarchiving', () => {
  assert.throws(() => readTemporarilyArchivedItemPolicy(''), /Could not read/);
  assert.throws(() => readTemporarilyArchivedItemPolicy(
    "const temporarilyArchivedItemsById = <String, String>{ unexpected };\n" +
    "const temporarilyArchivedItemReason = 'No current source confirmed.';"),
  /Unexpected identity/);
});
