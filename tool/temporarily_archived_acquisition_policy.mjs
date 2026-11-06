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

// The dated boss replacement gate shares the app's exact identities. Never
// regenerate retained obsolete descriptions as current source advice.
export function readSupersededBossItemPolicy(source) {
  const itemsById = {};
  for (const name of ['supersededBossCrystalsById', 'supersededBossAurasById',
    'supersededLatentAurasById', 'supersededWeaponReformStonesById',
    'supersededArmorReformStonesById']) {
    const block = source.match(new RegExp(
      `const ${name} = <String, String>\\{([\\s\\S]*?)\\};`,
    ));
    if (!block) throw new Error(`Missing shared boss policy ${name}`);
    const entry = /'(\d+)'\s*:\s*'((?:\\.|[^'\\])*)'\s*,/g;
    let count = 0;
    const remainder = block[1].replace(entry, (_, id, escaped) => {
      if (Object.hasOwn(itemsById, id)) throw new Error(`Duplicate boss ID ${id}`);
      itemsById[id] = escaped.replace(/\\(['\\])/g, '$1');
      count++;
      return '';
    });
    if (!count || remainder.trim()) throw new Error(`Unsupported boss policy syntax ${name}`);
  }
  return Object.freeze({itemsById: Object.freeze(itemsById),
    reason: 'Replaced in the February 28, 2024 PC boss-material simplification.'});
}

export const supersededBossItemPolicy = readSupersededBossItemPolicy(
  fs.readFileSync(new URL('../lib/domain/catalog/superseded_boss_materials.dart', import.meta.url), 'utf8'),
);

export function readRetiredItemPolicy(source) {
  const block = source.match(/const retiredPcItemsById = <String, String>\{([\s\S]*?)\};/);
  if (!block) throw new Error('Missing shared retired item policy');
  const itemsById = {};
  const rest = block[1].replace(/'(\d+)'\s*:\s*'((?:\\.|[^'\\])*)'\s*,/g,
    (_, id, name) => {
      if (Object.hasOwn(itemsById, id)) throw new Error(`Duplicate retired ID ${id}`);
      itemsById[id] = name.replace(/\\(['\\])/g, '$1');
      return '';
    });
  if (rest.trim() || !Object.keys(itemsById).length) {
    throw new Error('Unsupported shared retired item policy');
  }
  return Object.freeze({itemsById: Object.freeze(itemsById), reason: 'No longer obtainable.'});
}

export const retiredItemPolicy = readRetiredItemPolicy(fs.readFileSync(policyPath, 'utf8'));

export function archiveGeneratedAcquisitionInfo(
  info,
  policy = temporarilyArchivedItemPolicy,
) {
  for (const [name, entry] of Object.entries(info)) {
    const idText = String(entry.itemId ?? '').trim();
    const numericId = /^[+-]?\d+$/.test(idText) ? Number(idText) : null;
    const retired = numericId > 0
      ? Object.hasOwn(retiredItemPolicy.itemsById, String(numericId))
      : Object.values(retiredItemPolicy.itemsById).some(
          (canonical) => canonical.toLowerCase() === name.trim().toLowerCase(),
        );
    if (retired) {
      info[name] = {...entry, status: 'removed', archiveReason: retiredItemPolicy.reason};
      continue;
    }
    const superseded = numericId > 0
      ? Object.hasOwn(supersededBossItemPolicy.itemsById, String(numericId))
      : Object.values(supersededBossItemPolicy.itemsById).some(
          (canonical) => canonical.toLowerCase() === name.trim().toLowerCase(),
        );
    if (superseded) {
      info[name] = {...entry, status: 'removed', archiveReason: supersededBossItemPolicy.reason};
      continue;
    }
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
