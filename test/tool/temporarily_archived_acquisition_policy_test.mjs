import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {
  archiveGeneratedAcquisitionInfo,
  readTemporarilyArchivedItemPolicy,
  temporarilyArchivedItemPolicy,
  supersededBossItemPolicy,
  readSupersededBossItemPolicy,
  retiredItemPolicy,
  readRetiredItemPolicy,
} from '../../tool/temporarily_archived_acquisition_policy.mjs';

test('retired identities share the application policy without broad name filters', () => {
  assert.equal(Object.keys(retiredItemPolicy.itemsById).length, 18);
  assert.equal(retiredItemPolicy.itemsById['5952'], 'Trace of Despair');
  assert.equal(retiredItemPolicy.itemsById['5960'], undefined);
  const info = Object.fromEntries(Object.entries(retiredItemPolicy.itemsById).map(
    ([itemId, name]) => [name, {itemId, status: 'reviewed', routes: [{summary: 'History'}]}]));
  const routes = info['Trace of Despair'].routes;
  info['Trace of Nature'] = {itemId: 5960, status: 'reviewed'};
  info['[Event] Permanent reward'] = {itemId: 750490, status: 'reviewed'};
  info['Custom current identity'] = {itemId: 999999, status: 'reviewed'};
  archiveGeneratedAcquisitionInfo(info);
  for (const name of Object.values(retiredItemPolicy.itemsById)) assert.equal(info[name].status, 'removed');
  for (const name of ['Trace of Nature', '[Event] Permanent reward', 'Custom current identity']) {
    assert.equal(info[name].status, 'reviewed');
  }
  assert.equal(info['Trace of Despair'].routes, routes);
  assert.throws(() => readRetiredItemPolicy(''), /Missing shared retired/);
  assert.throws(() => readRetiredItemPolicy('const retiredPcItemsById = <String, String>{ nope };'), /Unsupported/);
});

test('reform and recharge removals survive regeneration without removing current replacements', () => {
  const review = JSON.parse(fs.readFileSync(new URL('../../docs/practical-followthrough-20261104.json', import.meta.url)));
  const info = Object.fromEntries(review.removedItems.map(({id,name}) =>
    [name, {itemId:id,status:'reviewed',routes:[{summary:'Historical source'}]}]));
  for (const id of [6654,6655,6207,37949,752014,8917]) info[`Retained ${id}`] = {itemId:id,status:'reviewed'};
  archiveGeneratedAcquisitionInfo(info);
  for (const {id,name} of review.removedItems) {
    assert.equal(retiredItemPolicy.itemsById[id],name);
    assert.equal(info[name].status,'removed');
    assert.equal(info[name].routes[0].summary,'Historical source');
  }
  for (const id of [6654,6655,6207,37949,752014,8917]) assert.equal(info[`Retained ${id}`].status,'reviewed');
});

test('boss replacements retain routes but cannot become current during generation', () => {
  const doc = JSON.parse(fs.readFileSync(new URL('../../docs/reviewed-boss-material-simplification.json', import.meta.url)));
  assert.equal(doc.entries.length, 91);
  assert.deepEqual(supersededBossItemPolicy.itemsById,
    Object.fromEntries(doc.entries.map(r => [r.id, r.name])));
  const info = Object.fromEntries(doc.entries.map(r => [r.name,
    {canonicalName:r.name,itemId:r.id,status:'reviewed',routes:[{summary:'Old source'}]}]));
  for (const id of doc.retainedIds) info[`Retained ${id}`] = {itemId:id,status:'reviewed'};
  info['Explicit custom identity'] = {itemId:999999,status:'reviewed'};
  const oldRoutes = info['Concentrated Bheg Crystal'].routes;
  archiveGeneratedAcquisitionInfo(info);
  for (const r of doc.entries) assert.equal(info[r.name].status,'removed');
  for (const id of doc.retainedIds) assert.equal(info[`Retained ${id}`].status,'reviewed');
  assert.equal(info['Explicit custom identity'].status,'reviewed');
  assert.equal(info['Concentrated Bheg Crystal'].routes,oldRoutes);
  assert.equal(archiveGeneratedAcquisitionInfo(info),info);
  assert.throws(() => readSupersededBossItemPolicy(''), /Missing shared boss policy/);
});

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
