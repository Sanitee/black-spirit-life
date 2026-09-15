import fs from 'node:fs';

// Read the same small identity policy used by the app. No second archive list
// can drift from it when the acquisition catalog is regenerated.
const policyPath = new URL(
  '../lib/domain/catalog/temporarily_archived_items.dart',
  import.meta.url,
);

export function readTemporarilyArchivedItemPolicy(source) {
  const block = source.match(
    /const temporarilyArchivedItemsById = <String, String>\{([\s\S]*?)\};/,
  );
  const reason = source.match(
    /const temporarilyArchivedItemReason = '([^']*)';/,
  );
  if (!block || !reason) {
    throw new Error('Could not read the shared temporary item archive policy.');
  }
  const itemsById = {};
  for (const line of block[1].split(/\r?\n/).map((line) => line.trim())) {
    if (!line) continue;
    const entry = line.match(/^'(\d+)': '([^']+)',$/);
    if (!entry || itemsById[entry[1]]) {
      throw new Error('Unexpected identity in the temporary item archive policy.');
    }
    itemsById[entry[1]] = entry[2];
  }
  if (Object.keys(itemsById).length === 0) {
    throw new Error('The temporary item archive policy is empty.');
  }
  return Object.freeze({itemsById: Object.freeze(itemsById), reason: reason[1]});
}

export const temporarilyArchivedItemPolicy = readTemporarilyArchivedItemPolicy(
  fs.readFileSync(policyPath, 'utf8'),
);

export function archiveGeneratedAcquisitionInfo(
  info,
  policy = temporarilyArchivedItemPolicy,
) {
  for (const [name, entry] of Object.entries(info)) {
    const idText = String(entry.itemId ?? '').trim();
    const numericId = /^[+-]?\d+$/.test(idText) ? Number(idText) : null;
    const archived = numericId > 0
      ? Object.hasOwn(policy.itemsById, String(numericId))
      : Object.values(policy.itemsById).some(
          (canonical) => canonical.toLowerCase() === name.trim().toLowerCase(),
        );
    if (!archived) continue;
    // Preserve the raw route records as references. A non-reviewed status is
    // deliberately not displayable as a current acquisition recommendation.
    info[name] = {
      ...entry,
      status: 'temporarily_archived',
      archiveReason: policy.reason,
    };
  }
  return info;
}
