// Pure, deterministic merge: emits JSON to stdout; never writes source/evidence.
// Usage: node merge_garmoth_spot_catalog.cjs --sidebar <json> --source <json>
//   --client-items <items.json> --harvest <directory> [--harvest <retry-directory>]
//   --audit | --emit
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const args = process.argv.slice(2);
function values(flag) { return args.flatMap((value, index) => value === flag ? [args[index + 1]] : []); }
function required(flag) { const value = values(flag)[0]; if (!value) throw Error('Missing ' + flag); return value; }
const normalize = value => String(value ?? '').normalize('NFKC').replace(/[’`]/g, "'").trim().replace(/\s+/g, ' ').toLowerCase();
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex').toUpperCase();
const read = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const sidebarPath = required('--sidebar');
const source = read(required('--source'));
const sidebar = read(sidebarPath);
const clientBytes = fs.readFileSync(required('--client-items'));
const client = JSON.parse(clientBytes.toString('utf8'));
const byName = new Map();
for (const item of client) {
  const id = String(item.id);
  if (!/^\d+$/.test(id) || !item.name) continue;
  const key = normalize(item.name);
  if (!byName.has(key)) byName.set(key, new Map());
  byName.get(key).set(id, { id, name: item.name, aliases: [] });
}
const records = new Map();
for (const directory of values('--harvest')) {
  for (const file of fs.readdirSync(directory).filter(file => /^spot-\d+\.json$/.test(file)).sort()) {
    const fullPath = path.join(directory, file);
    const bytes = fs.readFileSync(fullPath);
    const record = JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/, ''));
    const old = records.get(record.spotId);
    if (!old || record.status === 'verified_header_structure' || old.record.status !== 'verified_header_structure')
      records.set(record.spotId, { record, sha256: digest(bytes) });
  }
}
// These are session expenditure columns, not positive location evidence.
// Exact observed names only; never infer a cost from an image or price value.
const costs = new Set([
  'Mystery Crystal Chest', 'Energy Potion (Extra Large)',
].map(normalize));
const synthetic = new Set(['Any Artifact'].map(normalize));
const allItems = new Map(source.items.map(item => [item.id, item]));
const unresolved = new Map();
let verified = 0;
const spots = sidebar.spots.map(spot => {
  const saved = records.get(spot.siteId);
  const result = { ...spot, verifiedSessionItemIds: [], costItemIds: [], noncanonicalHeaders: [], sessionEvidence: null };
  delete result.verifiedDropItemIds;
  delete result.dropEvidence;
  if (!saved || saved.record.status !== 'verified_header_structure') return result;
  const record = saved.record;
  const trailingNewBadge = /\s+NEW$/.test(spot.name) && normalize(record.name) === normalize(spot.name.replace(/\s+NEW$/, ''));
  if ((!trailingNewBadge && normalize(record.name) !== normalize(spot.name)) || normalize(record.category) !== normalize(spot.sidebarCategory))
    throw Error('Capture destination mismatch for ' + spot.siteId);
  if (trailingNewBadge) { result.name = record.name; result.badges = [...new Set([...result.badges, 'new'])]; }
  const observations = record.tooltipObservations ?? [];
  const columns = [];
  const expectedColumns = new Set([...record.headerImages, ...(record.structure?.otherHeaderImages ?? [])].map(image => image.column));
  const observedColumns = new Set(observations.map(observation => observation.column));
  let complete = expectedColumns.size > 0 && observedColumns.size === expectedColumns.size &&
    [...expectedColumns].every(column => observedColumns.has(column));
  for (const observation of observations) {
    const name = observation.tooltipName;
    if (observation.tooltipStatus !== 'observed' || !name || /\b(?:Average|Total|Price):/.test(name)) { complete = false; continue; }
    if (synthetic.has(normalize(name))) {
      result.noncanonicalHeaders.push({ name, kind: 'synthetic-session-header' });
      columns.push({ itemId: null, observedName: name, identityKind: 'noncanonical-session-header', candidateItemIds: [], role: 'noncanonical' });
      continue;
    }
    const matches = [...(byName.get(normalize(name))?.values() ?? [])];
    if (matches.length !== 1) {
      if (!unresolved.has(name)) unresolved.set(name, { name, candidateIds: matches.map(item => item.id), spotIds: [] });
      unresolved.get(name).spotIds.push(spot.siteId);
      result.noncanonicalHeaders.push({ name, kind: matches.length ? 'ambiguous-client-name' : 'unknown-client-name' });
      columns.push({ itemId: null, observedName: name, identityKind: matches.length ? 'ambiguous-exact-client-name' : 'noncanonical-session-header',
        candidateItemIds: matches.map(item => item.id), role: matches.length ? 'session-item' : 'noncanonical' });
      continue;
    }
    const item = matches[0];
    allItems.set(item.id, allItems.get(item.id) ?? item);
    const role = costs.has(normalize(name)) ? 'cost' : 'session-item';
    columns.push({ itemId: item.id, observedName: name, identityKind: 'exact-client-name', role });
    result.verifiedSessionItemIds.push(item.id);
    if (role === 'cost') result.costItemIds.push(item.id);
  }
  for (const field of ['verifiedSessionItemIds', 'costItemIds']) result[field] = [...new Set(result[field])];
  if (!complete) {
    result.verifiedSessionItemIds = [];
    result.costItemIds = [];
    return result;
  }
  // Individual identities can be verified even when a different column remains
  // unresolved. Coverage remains incomplete and cannot establish uniqueness.
  result.sessionEvidence = {
    kind: 'rendered-history-item-columns', meaning: 'supported-session-columns-not-natural-drop-proof',
    spotId: spot.siteId, complete, capturedAt: record.observedUtc,
    captureSha256: saved.sha256, columns,
  };
  if (complete) verified++;
  return result;
});
const audit = {
  observedDestinations: spots.length, capturedRecords: records.size,
  verifiedTables: verified, incompleteSpotIds: spots.filter(spot => !spot.sessionEvidence?.complete).map(spot => spot.siteId),
  unresolved: [...unresolved.values()].map(row => ({ ...row, spotIds: [...new Set(row.spotIds)] })), namedItems: allItems.size,
  costNames: [...new Set(spots.flatMap(spot => spot.sessionEvidence?.columns.filter(column => column.role === 'cost').map(column => column.observedName) ?? []))],
  coralCandidates: spots.filter(spot => spot.sessionEvidence?.columns.some(column => column.observedName === "Rusalka's Coral")).map(spot => [spot.siteId, spot.name]),
  exampleExtras: ['Lobster', 'Blue Coral', 'Cracked Terrashard'].map(name => ({ name,
    spotIds: spots.filter(spot => spot.sessionEvidence?.columns.some(column => normalize(column.observedName) === normalize(name))).map(spot => spot.siteId) })),
};
if (args.includes('--audit')) process.stdout.write(JSON.stringify(audit, null, 2) + '\n');
else if (args.includes('--emit')) {
  if (records.size !== spots.length) throw Error('Harvest enumeration is incomplete; do not publish it as a completed run.');
  const output = { ...sidebar, datasetVersion: 'garmoth-session-columns-2026-09-14-v2',
    coverage: { ...sidebar.coverage, verifiedDropSets: undefined, unresolvedIdentityTables: undefined,
      verifiedSessionTables: verified, uncheckedSessionTables: spots.length - verified,
      ambiguousCanonicalColumns: spots.reduce((sum, spot) => sum + (spot.sessionEvidence?.columns.filter(column => column.identityKind === 'ambiguous-exact-client-name').length ?? 0), 0),
      noncanonicalSessionHeaders: spots.reduce((sum, spot) => sum + (spot.sessionEvidence?.columns.filter(column => column.role === 'noncanonical').length ?? 0), 0) },
    provenance: { ...sidebar.provenance, clientItemsSha256: digest(clientBytes),
      mergeTool: 'tools/merge_garmoth_spot_catalog.cjs',
      columnMeaning: 'Exact named supported session columns; not natural drop proof. Costs and synthetic headers cannot identify a location.',
      identityPolicy: 'Unique normalized exact client names identify canonical IDs; duplicates retain candidate IDs without choosing one. Artwork keys are never item IDs.',
      excludedEvidenceNames: ['Mystery Crystal Chest', 'Energy Potion (Extra Large)'],
      excludedEvidenceReason: 'Root independently observed these two as negative-cost fields in the Rusalka session editor. No keyword-based cost classification.' },
    items: [...allItems.values()].sort((a, b) => Number(a.id) - Number(b.id)), spots };
  process.stdout.write(JSON.stringify(output, null, args.includes('--compact') ? undefined : 2) + '\n');
} else throw Error('Choose --audit or --emit.');
